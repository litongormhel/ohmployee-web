-- ============================================================================
-- Migration: 20262606000086_archive_previous_applicants_on_vacancy_reopen.sql
-- Description:
--   1. Updates reopen_or_create_vacancy_for_plantilla() so that whenever a
--      vacancy is reopened on employee separation (Backfill), all previous
--      onboarded/active applicants under that vacancy_vcode are automatically
--      archived (is_archived = true, archived_at = NOW()).
--   2. Updates fn_plantilla_separation_to_vacancy() to ensure roving slot
--      reopenings also archive prior applicants for the vacated vcode.
--   3. One-time data cleanup: Archives prior applicant for VCTG2_0005 and
--      any other reopened backfill vacancies where the previous hire resigned.
-- ============================================================================

-- 1. Patch reopen_or_create_vacancy_for_plantilla
CREATE OR REPLACE FUNCTION public.reopen_or_create_vacancy_for_plantilla(
  p_plantilla_id uuid,
  p_effective_date date,
  p_vacancy_type text DEFAULT 'Backfill'::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_plantilla public.plantilla;
  v_vacancy_id uuid;
BEGIN
  SELECT *
    INTO v_plantilla
  FROM public.plantilla
  WHERE id = p_plantilla_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found: %', p_plantilla_id;
  END IF;

  -- Dynamic resolution of position_id if null or invalid
  IF v_plantilla.position_id IS NULL AND v_plantilla.position IS NOT NULL AND btrim(v_plantilla.position) <> '' THEN
    SELECT p.id INTO v_plantilla.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(v_plantilla.position))
    LIMIT 1;
    IF v_plantilla.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = v_plantilla.position_id
       WHERE id = v_plantilla.id;
    END IF;
  END IF;

  IF v_plantilla.position_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_plantilla.position_id
  ) THEN
    SELECT p.id INTO v_plantilla.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(v_plantilla.position))
    LIMIT 1;
    IF v_plantilla.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = v_plantilla.position_id
       WHERE id = v_plantilla.id;
    END IF;
  END IF;

  -- VCODE is the manpower slot identity.
  -- Reopen/reactivate existing slot first.
  SELECT id
    INTO v_vacancy_id
  FROM public.vacancies
  WHERE vcode = v_plantilla.vcode
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_vacancy_id IS NOT NULL THEN
    UPDATE public.vacancies
    SET
      status = 'Open',
      vacancy_type = COALESCE(p_vacancy_type, vacancy_type, 'Backfill'),
      vacant_date = p_effective_date,
      source_plantilla_id = v_plantilla.id,
      account = v_plantilla.account,
      account_id = v_plantilla.account_id,
      chain_id = v_plantilla.chain_id,
      store_id = v_plantilla.store_id,
      province_id = v_plantilla.province_id,
      position = v_plantilla.position,
      position_id = v_plantilla.position_id,
      area_name = COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      store_name = v_plantilla.store_name,
      is_archived = FALSE,
      archived_at = NULL,
      deleted_at = NULL,
      has_pending_closure = FALSE,
      updated_at = NOW(),
      updated_by = auth.uid()
    WHERE id = v_vacancy_id;

    -- Archive any previous applicants under this vcode so the reopened vacancy is clean & unoccupied
    IF v_plantilla.vcode IS NOT NULL THEN
      UPDATE public.applicants
         SET is_archived = true,
             archived_at = NOW()
       WHERE vacancy_vcode = v_plantilla.vcode
         AND COALESCE(is_archived, false) = false;
    END IF;

    RETURN v_vacancy_id;
  END IF;

  IF v_plantilla.position_id IS NOT NULL THEN
    INSERT INTO public.vacancies (
      vcode,
      account,
      position,
      account_id,
      chain_id,
      store_id,
      province_id,
      area_name,
      position_id,
      vacant_date,
      vacancy_type,
      status,
      source_plantilla_id,
      store_name,
      created_at,
      updated_at,
      created_by,
      updated_by,
      required_headcount
    )
    SELECT
      v_plantilla.vcode,
      v_plantilla.account,
      p.position_name,
      v_plantilla.account_id,
      v_plantilla.chain_id,
      v_plantilla.store_id,
      v_plantilla.province_id,
      COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      p.id,
      p_effective_date,
      COALESCE(p_vacancy_type, 'Backfill'),
      'Open',
      v_plantilla.id,
      v_plantilla.store_name,
      NOW(),
      NOW(),
      auth.uid(),
      auth.uid(),
      1
    FROM public.positions p
    WHERE p.id = v_plantilla.position_id
    RETURNING id INTO v_vacancy_id;
  END IF;

  IF v_vacancy_id IS NULL THEN
    INSERT INTO public.vacancies (
      vcode,
      account,
      position,
      account_id,
      chain_id,
      store_id,
      province_id,
      area_name,
      position_id,
      vacant_date,
      vacancy_type,
      status,
      source_plantilla_id,
      store_name,
      created_at,
      updated_at,
      created_by,
      updated_by,
      required_headcount
    ) VALUES (
      v_plantilla.vcode,
      v_plantilla.account,
      COALESCE(NULLIF(TRIM(v_plantilla.position), ''), 'UNSPECIFIED'),
      v_plantilla.account_id,
      v_plantilla.chain_id,
      v_plantilla.store_id,
      v_plantilla.province_id,
      COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      v_plantilla.position_id,
      p_effective_date,
      COALESCE(p_vacancy_type, 'Backfill'),
      'Open',
      v_plantilla.id,
      v_plantilla.store_name,
      NOW(),
      NOW(),
      auth.uid(),
      auth.uid(),
      1
    ) RETURNING id INTO v_vacancy_id;
  END IF;

  -- Archive any previous applicants under this vcode so the reopened vacancy is clean & unoccupied
  IF v_plantilla.vcode IS NOT NULL THEN
    UPDATE public.applicants
       SET is_archived = true,
           archived_at = NOW()
     WHERE vacancy_vcode = v_plantilla.vcode
       AND COALESCE(is_archived, false) = false;
  END IF;

  RETURN v_vacancy_id;
END;
$function$;

-- 2. Update fn_plantilla_separation_to_vacancy()
CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link        RECORD;
  v_vac         public.vacancies%ROWTYPE;
  v_esa         RECORD;
  v_new_link_id uuid;
  v_hc          numeric;
  v_resolved_requirement_id uuid;
  v_link_status text;
  v_link_vcode  text;
BEGIN
  -- Trigger filter logic
  IF OLD.status NOT IN ('Active', 'On Leave', 'For Deactivation')
    OR NEW.status NOT IN ('Resigned', 'AWOL', 'Endo', 'Terminated', 'Others',
                          'Inactive', 'Floating', 'For Deactivation')
    OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Dynamic resolution of position_id if null or invalid
  IF NEW.position_id IS NULL AND NEW.position IS NOT NULL AND btrim(NEW.position) <> '' THEN
    SELECT p.id INTO NEW.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(NEW.position))
    LIMIT 1;
    IF NEW.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = NEW.position_id
       WHERE id = NEW.id;
    END IF;
  END IF;

  IF NEW.position_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = NEW.position_id
  ) THEN
    SELECT p.id INTO NEW.position_id
    FROM public.positions p
    WHERE lower(btrim(p.position_name)) = lower(btrim(NEW.position))
    LIMIT 1;
    IF NEW.position_id IS NOT NULL THEN
      UPDATE public.plantilla
         SET position_id = NEW.position_id
       WHERE id = NEW.id;
    END IF;
  END IF;

  -- 1. Release the Coverage Group slot this employee occupied, if any.
  IF NEW.coverage_slot_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE id = NEW.coverage_slot_id
       AND current_occupant_plantilla_id = NEW.id;

    UPDATE public.hr_emploc
       SET deleted_at = NOW()
     WHERE coverage_slot_id = NEW.coverage_slot_id
       AND deleted_at IS NULL
       AND status = 'Moved to Plantilla';

  ELSIF NEW.coverage_group_id IS NOT NULL THEN
    UPDATE public.coverage_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = NOW()
     WHERE coverage_group_id = NEW.coverage_group_id
       AND current_occupant_plantilla_id = NEW.id;

    UPDATE public.hr_emploc
       SET deleted_at = NOW()
     WHERE coverage_group_id = NEW.coverage_group_id
       AND deleted_at IS NULL
       AND status = 'Moved to Plantilla'
       AND coverage_slot_id IN (
         SELECT id FROM public.coverage_slots
          WHERE coverage_group_id = NEW.coverage_group_id
            AND current_occupant_plantilla_id IS NULL
       );
  END IF;

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

    v_link_status := CASE
      WHEN lower(COALESCE(NEW.separation_status, '')) IN ('awol','resigned','terminated','end of contract','endo','others')
        THEN 'Resigned'
      ELSE 'Backed Out'
    END;

    IF NEW.coverage_slot_id IS NOT NULL OR NEW.coverage_group_id IS NOT NULL THEN
      UPDATE public.plantilla_store_links
         SET status      = v_link_status,
             unlinked_at = NOW()
       WHERE plantilla_id = NEW.id
         AND status       = 'Active';

      UPDATE public.employee_store_allocations
         SET is_active     = false,
             effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
       WHERE plantilla_id = NEW.id
         AND is_active    = true;

      RETURN NEW;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.plantilla_store_links
       WHERE plantilla_id = NEW.id AND status = 'Active'
    ) THEN
      FOR v_link IN
        SELECT * FROM public.plantilla_store_links
         WHERE plantilla_id = NEW.id AND status = 'Active'
      LOOP
        SELECT COALESCE(esa.filled_hc, 1)::numeric INTO v_hc
          FROM public.employee_store_allocations esa
         WHERE esa.plantilla_id        = NEW.id
           AND esa.vcode               = v_link.vcode
           AND esa.is_active           = true
         LIMIT 1;

        v_hc := COALESCE(v_hc, 1);

        IF v_link.vacancy_id IS NOT NULL THEN
          SELECT * INTO v_vac FROM public.vacancies
           WHERE id = v_link.vacancy_id AND deleted_at IS NULL LIMIT 1;
        ELSE
          SELECT * INTO v_vac FROM public.vacancies
           WHERE vcode = v_link.vcode AND deleted_at IS NULL LIMIT 1;
        END IF;

        IF v_vac.id IS NOT NULL THEN
          IF v_vac.status IN ('Filled', 'Closed') THEN
            UPDATE public.vacancies
               SET status         = 'Open',
                   is_archived    = false,
                   archived_at    = NULL,
                   archived_by    = NULL,
                   required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at     = NOW()
             WHERE id = v_vac.id;
          ELSE
            UPDATE public.vacancies
               SET required_headcount = GREATEST(
                                         COALESCE(required_headcount, 0) + v_hc,
                                         1
                                       ),
                   updated_at = NOW()
             WHERE id = v_vac.id;
          END IF;
        ELSE
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, store_name, position, position_id,
            status, vacancy_type, required_headcount, employment_type,
            source, created_at, updated_at
          )
          SELECT
            v_link.vcode,
            NEW.account,
            NEW.account_id,
            s.id,
            s.store_name,
            COALESCE(p.position_name, NEW.position, 'UNSPECIFIED'),
            p.id,
            'Open',
            'Backfill',
            GREATEST(v_hc, 1),
            'Roving',
            'plantilla',
            NOW(),
            NOW()
          FROM (SELECT 1) dummy
          LEFT JOIN public.positions p ON p.id = NEW.position_id
          LEFT JOIN public.stores s ON s.vcode = v_link.vcode
          RETURNING * INTO v_vac;

          UPDATE public.plantilla_store_links
             SET vacancy_id = v_vac.id
           WHERE id = v_link.id;
        END IF;

        UPDATE public.plantilla_store_links
           SET status      = v_link_status,
               unlinked_at = NOW()
         WHERE id = v_link.id;

        -- Archive previous applicants for this roving slot
        IF v_link.vcode IS NOT NULL THEN
          UPDATE public.applicants
             SET is_archived = true,
                 archived_at = NOW()
           WHERE vacancy_vcode = v_link.vcode
             AND COALESCE(is_archived, false) = false;
        END IF;

      END LOOP;

    ELSE
      FOR v_esa IN
        SELECT * FROM public.employee_store_allocations
         WHERE plantilla_id = NEW.id AND is_active = true
      LOOP
        v_hc := COALESCE(v_esa.filled_hc, 1)::numeric;

        SELECT * INTO v_vac FROM public.vacancies
         WHERE store_id    = v_esa.store_id
           AND account_id  = NEW.account_id
           AND COALESCE(employment_type, '') = 'Roving'
           AND deleted_at  IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Cancelled')
         LIMIT 1;

        IF NOT FOUND THEN
          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, position, position_id,
            status, vacancy_type, employment_type, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_esa.store_id::text,
            NEW.account,
            NEW.account_id,
            v_esa.store_id,
            COALESCE(p.position_name, NEW.position, 'UNSPECIFIED'),
            p.id,
            'Open',
            'Backfill',
            'Roving',
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
          FROM (SELECT 1) dummy
          LEFT JOIN public.positions p ON p.id = NEW.position_id
          RETURNING * INTO v_vac;
        ELSE
          UPDATE public.vacancies
             SET required_headcount = GREATEST(
                                       COALESCE(required_headcount, 0) + v_hc,
                                       1
                                     ),
                 status    = CASE
                               WHEN status IN ('Filled', 'Closed') THEN 'Open'
                               ELSE status
                             END,
                 is_archived = false,
                 archived_at = NULL,
                 archived_by = NULL,
                 updated_at  = NOW()
           WHERE id = v_vac.id
          RETURNING * INTO v_vac;
        END IF;

        v_link_vcode := COALESCE(v_vac.vcode, v_esa.vcode, v_esa.store_id::text);

        INSERT INTO public.plantilla_store_links (
          plantilla_id, account, vcode, store_name, vacancy_id, status
        )
        SELECT NEW.id, NEW.account, v_link_vcode, v_esa.store_name, v_vac.id, v_link_status
         WHERE NOT EXISTS (
           SELECT 1 FROM public.plantilla_store_links psl
            WHERE psl.plantilla_id = NEW.id
              AND psl.vcode        = v_link_vcode
         )
        RETURNING id INTO v_new_link_id;

        IF v_new_link_id IS NOT NULL THEN
          UPDATE public.plantilla_store_links
             SET unlinked_at = NOW()
           WHERE id = (
             SELECT id FROM public.plantilla_store_links
              WHERE plantilla_id = NEW.id
                AND vcode        = v_link_vcode
              ORDER BY created_at DESC
              LIMIT 1
           );
        END IF;

        -- Archive previous applicants for this roving slot
        IF v_link_vcode IS NOT NULL THEN
          UPDATE public.applicants
             SET is_archived = true,
                 archived_at = NOW()
           WHERE vacancy_vcode = v_link_vcode
             AND COALESCE(is_archived, false) = false;
        END IF;

      END LOOP;
    END IF;

    UPDATE public.employee_store_allocations
       SET is_active     = false,
           effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
     WHERE plantilla_id = NEW.id
       AND is_active    = true;

    RETURN NEW;
  END IF;

  -- ── Stationary employee path ─────────────────────────────────────────────
  PERFORM public.reopen_or_create_vacancy_for_plantilla(
    NEW.id,
    NEW.date_of_separation,
    'Backfill'
  );

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$function$;

-- 3. One-Time Data Cleanup & Backfill
-- A. Specific target VCTG2_0005: Archive prior applicant DELA CRUZ, JUAN SANTOS
UPDATE public.applicants
   SET is_archived = true,
       archived_at = NOW()
 WHERE id = 'c3f7a259-0dd3-4b53-89ab-3a417cb33696';

-- B. Systematic backfill for any other reopened backfill vacancy where prior hire already separated
UPDATE public.applicants a
   SET is_archived = true,
       archived_at = NOW()
  FROM public.vacancies v
  JOIN public.plantilla p ON p.id = v.source_plantilla_id
 WHERE a.vacancy_vcode = v.vcode
   AND COALESCE(a.is_archived, false) = false
   AND v.status = 'Open'
   AND v.vacancy_type = 'Backfill'
   AND (p.status = 'Inactive' OR p.separation_status IS NOT NULL);
