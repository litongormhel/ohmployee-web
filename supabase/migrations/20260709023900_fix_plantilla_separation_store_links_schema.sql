-- ============================================================================
-- Fix plantilla_store_links schema mismatch in roving separation branch
-- Migration: 20260709020000_fix_plantilla_separation_store_links_schema.sql
-- Task: task_414236b0 / ohm#pv4h9m2x
-- ============================================================================
-- PROBLEM:
--   20260708140000_assignment_hc_sync.sql rewrote the roving branch of
--   fn_plantilla_separation_to_vacancy() to add HC-sync logic, but conflated
--   employee_store_allocations vocabulary (store_id, is_active) with
--   plantilla_store_links vocabulary. public.plantilla_store_links has no
--   is_active, store_id, or deactivated_at columns (live columns:
--   status text CHECK IN ('Active','Backed Out','Resigned'), vcode text
--   NOT NULL, account text NOT NULL, unlinked_at timestamptz). Every roving
--   employee separation currently fails with 42703.
--
-- FIX (single column-mapping fix layered onto the live 20260709013328 body —
--      NOT a revert; the HC-sync additions from 20260708140000 are kept):
--   - plantilla_store_links.is_active = true/false
--       -> status = 'Active' / status IN ('Resigned','Backed Out')
--   - plantilla_store_links.deactivated_at = NOW()
--       -> unlinked_at = NOW(), written together with the status change
--          (paired write, matching the pre-regression baseline in
--          20260520012857_remote_schema.sql)
--   - plantilla_store_links.store_id (does not exist)
--       -> resolved via the vcode column both plantilla_store_links and
--          employee_store_allocations already carry (no shared store_id,
--          no stores join needed — vcode is a common key on both tables)
--   - Resigned vs Backed Out determination restored from the pre-regression
--     baseline pattern, using NEW.separation_status (exists on plantilla,
--     confirmed via information_schema).
--
--   The stationary path, the esa.store_id / esa.is_active references (a
--   DIFFERENT table, already correct), the is_roving/deployment_type guard
--   fixed under ohm#5m2vqk8j, and the trigger filter logic are untouched.
-- ============================================================================

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

  -- ── Roving employee path ─────────────────────────────────────────────────
  IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

    v_link_status := CASE
      WHEN NEW.separation_status IN ('AWOL','Resigned','Terminated','End of Contract','Endo','Others')
        THEN 'Resigned'
      ELSE 'Backed Out'
    END;

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
        END IF;

        UPDATE public.plantilla_store_links
           SET status      = v_link_status,
               unlinked_at = NOW()
         WHERE id = v_link.id;

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
           AND is_roving   = true
           AND deleted_at  IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Cancelled')
         LIMIT 1;

        IF NOT FOUND THEN
          -- Hard guard for position_id validity
          IF NOT EXISTS (
            SELECT 1 FROM public.positions WHERE id = NEW.position_id
          ) THEN
            RAISE EXCEPTION 'Invalid position_id: %', NEW.position_id;
          END IF;

          INSERT INTO public.vacancies (
            vcode, account, account_id, store_id, position, position_id,
            status, vacancy_type, is_roving, required_headcount,
            source, created_at, updated_at
          )
          SELECT
            v_esa.store_id::text,
            NEW.account,
            NEW.account_id,
            v_esa.store_id,
            p.position_name,
            p.id,
            'Open',
            'Backfill',
            true,
            GREATEST(v_hc, 1),
            'plantilla',
            NOW(),
            NOW()
          FROM public.positions p
          WHERE p.id = NEW.position_id
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
          plantilla_id, account, vcode, vacancy_id, status
        )
        SELECT NEW.id, NEW.account, v_link_vcode, v_vac.id, v_link_status
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
  -- Hard guard for position_id validity before reopening or creating vacancy
  IF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = NEW.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', NEW.position_id;
  END IF;

  PERFORM public.reopen_or_create_vacancy_for_plantilla(
    NEW.id,
    NEW.date_of_separation,
    'Backfill'
  );

  v_resolved_requirement_id := public.resolve_requirement_for_separation(
    NEW.vacancy_requirement_id,
    NEW.store_id,
    NEW.account_id
  );

  IF v_resolved_requirement_id IS NOT NULL THEN
    UPDATE public.vacancy_requirements
       SET hc_filled = GREATEST(0, hc_filled - 1)
     WHERE id = v_resolved_requirement_id;
  END IF;

  UPDATE public.employee_store_allocations
     SET is_active     = false,
         effective_end = COALESCE(NEW.date_of_separation, CURRENT_DATE)
   WHERE plantilla_id = NEW.id
     AND is_active    = true;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.fn_plantilla_separation_to_vacancy() IS
  'Separation trigger (AFTER UPDATE ON plantilla). Roving branch fixed '
  '2026-07-09 (ohm#pv4h9m2x / task_414236b0): plantilla_store_links has no '
  'is_active/store_id/deactivated_at columns — replaced with '
  'status/vcode/unlinked_at. esa.store_id/esa.is_active (employee_store_allocations, '
  'a different table) and the deployment_type roving guard (ohm#5m2vqk8j) are unchanged.';
