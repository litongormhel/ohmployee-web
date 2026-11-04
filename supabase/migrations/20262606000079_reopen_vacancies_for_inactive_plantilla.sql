-- ============================================================================
-- Migration: 20262606000079_reopen_vacancies_for_inactive_plantilla.sql
-- Description: Reopen vacancies and deactivate store allocations for inactive
--              plantilla personnel (guaranteeing headcount parity 752 + 3 = 755).
-- ============================================================================

BEGIN;

-- ── 1. Reconcile Existing Inactive Personnel ────────────────────────────────
-- A. Deactivate orphan active store allocations for inactive employees
UPDATE public.employee_store_allocations esa
SET is_active = false,
    effective_end = COALESCE(p.date_of_separation, CURRENT_DATE)
FROM public.plantilla p
WHERE (esa.plantilla_id = p.id OR (esa.employee_no = p.employee_no AND p.employee_no IS NOT NULL))
  AND esa.is_active = true
  AND (
    p.deactivated_at IS NOT NULL
    OR p.date_of_separation IS NOT NULL
    OR lower(coalesce(nullif(btrim(p.status), ''), '')) IN ('inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated', 'awol')
    OR lower(coalesce(nullif(btrim(p.separation_status), ''), '')) IN ('inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated', 'awol')
  );

-- B. Reopen vacancies and release slots for inactive employees without active occupants
DO $$
DECLARE
  rec RECORD;
  v_store RECORD;
  v_vac_id uuid;
  v_active_occupant_count integer;
BEGIN
  FOR rec IN
    SELECT p.id AS plantilla_id, p.vcode, p.account, p.account_id, p.store_id, p.store_name,
           p.position, p.position_id, p.chain_id, p.province_id, p.area, p.area_name_snapshot,
           p.date_of_separation, p.deployment_type
    FROM public.plantilla p
    WHERE (
      p.deactivated_at IS NOT NULL
      OR p.date_of_separation IS NOT NULL
      OR lower(coalesce(nullif(btrim(p.status), ''), '')) IN ('inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated', 'awol')
      OR lower(coalesce(nullif(btrim(p.separation_status), ''), '')) IN ('inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated', 'awol')
    )
    AND p.vcode IS NOT NULL
    AND COALESCE(p.is_deleted, false) = false
  LOOP
    -- Count active occupants for this VCode
    SELECT COUNT(*) INTO v_active_occupant_count
    FROM public.plantilla ap
    WHERE ap.vcode = rec.vcode
      AND ap.id <> rec.plantilla_id
      AND COALESCE(ap.is_deleted, false) = false
      AND ap.deactivated_at IS NULL
      AND ap.date_of_separation IS NULL
      AND lower(coalesce(nullif(btrim(ap.status), ''), 'active')) NOT IN ('inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated', 'awol')
      AND lower(coalesce(nullif(btrim(ap.separation_status), ''), '')) NOT IN ('inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated', 'awol');

    IF v_active_occupant_count = 0 THEN
      -- 1. Reopen or insert vacancy
      SELECT id INTO v_vac_id
      FROM public.vacancies
      WHERE vcode = rec.vcode
      ORDER BY created_at ASC
      LIMIT 1;

      IF v_vac_id IS NOT NULL THEN
        UPDATE public.vacancies
        SET status = 'Open',
            is_archived = false,
            archived_at = NULL,
            archived_by = NULL,
            deleted_at = NULL,
            has_pending_closure = false,
            vacant_date = COALESCE(rec.date_of_separation, CURRENT_DATE),
            account_id = COALESCE(account_id, rec.account_id),
            store_id = COALESCE(store_id, rec.store_id),
            store_name = COALESCE(store_name, rec.store_name),
            position = COALESCE(position, rec.position),
            position_id = COALESCE(position_id, rec.position_id),
            updated_at = now()
        WHERE id = v_vac_id;
      ELSE
        IF rec.store_id IS NULL AND rec.vcode IS NOT NULL THEN
          SELECT s.id, s.store_name, s.account_id
          INTO v_store
          FROM public.stores s
          WHERE upper(s.vcode) = upper(rec.vcode)
          LIMIT 1;

          rec.store_id := v_store.id;
          rec.account_id := COALESCE(rec.account_id, v_store.account_id);
        END IF;

        INSERT INTO public.vacancies (
          vcode,
          account,
          account_id,
          store_id,
          store_name,
          position,
          position_id,
          chain_id,
          province_id,
          area_name,
          vacant_date,
          vacancy_type,
          status,
          source_plantilla_id,
          required_headcount,
          is_archived,
          created_at,
          updated_at
        )
        VALUES (
          rec.vcode,
          COALESCE(rec.account, 'ALTURAS'),
          rec.account_id,
          rec.store_id,
          rec.store_name,
          COALESCE(rec.position, 'Motorized Collector'),
          rec.position_id,
          rec.chain_id,
          rec.province_id,
          COALESCE(rec.area_name_snapshot, rec.area),
          COALESCE(rec.date_of_separation, CURRENT_DATE),
          'Backfill',
          'Open',
          rec.plantilla_id,
          1,
          false,
          now(),
          now()
        )
        ON CONFLICT DO NOTHING;
      END IF;

      -- 2. Release slot in plantilla_slots
      UPDATE public.plantilla_slots
      SET slot_status = 'open',
          current_occupant_plantilla_id = NULL,
          updated_at = now()
      WHERE (legacy_vcode = rec.vcode OR current_occupant_plantilla_id = rec.plantilla_id)
        AND is_roving = false;

      -- 3. Create missing slot in plantilla_slots if not present
      IF NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots
        WHERE legacy_vcode = rec.vcode AND is_roving = false
      ) AND rec.account_id IS NOT NULL THEN
        INSERT INTO public.plantilla_slots (
          account_id,
          store_id,
          legacy_vcode,
          slot_status,
          is_roving,
          created_at,
          updated_at
        )
        VALUES (
          rec.account_id,
          rec.store_id,
          rec.vcode,
          'open',
          false,
          now(),
          now()
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END LOOP;
END $$;

-- ── 2. Update plantilla_update_separation to Permanently Enforce Synchronization
DROP FUNCTION IF EXISTS public.plantilla_update_separation(uuid, text, date, text);
DROP FUNCTION IF EXISTS public.plantilla_update_separation;
CREATE OR REPLACE FUNCTION public.plantilla_update_separation(
  p_plantilla_id    uuid,
  p_separation_status text,
  p_effective_date  date,
  p_remarks         text DEFAULT NULL::text
)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row              public.plantilla;
  v_sep_reason_code  text;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'separate') THEN
    RAISE EXCEPTION 'forbidden: Ops role required for plantilla status update'
      USING ERRCODE = '42501';
  END IF;

  IF p_effective_date IS NULL THEN
    RAISE EXCEPTION 'effective_date is required';
  END IF;

  IF p_separation_status NOT IN ('Resigned','AWOL','Terminated','End of Contract','Endo','Others') THEN
    RAISE EXCEPTION 'invalid separation_status: %', p_separation_status;
  END IF;

  SELECT * INTO v_row
  FROM public.plantilla
  WHERE id = p_plantilla_id
    AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found: %', p_plantilla_id;
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.plantilla
     SET separation_status  = p_separation_status,
         date_of_separation = p_effective_date,
         status             = 'Inactive',
         remarks            = COALESCE(p_remarks, remarks),
         updated_by         = auth.uid(),
         updated_at         = NOW()
   WHERE id = p_plantilla_id
   RETURNING * INTO v_row;

  -- Deactivate active store allocations
  UPDATE public.employee_store_allocations
     SET is_active = false,
         effective_end = p_effective_date
   WHERE (plantilla_id = p_plantilla_id OR (employee_no = v_row.employee_no AND v_row.employee_no IS NOT NULL))
     AND is_active = true;

  -- Phase 6.4: non-blocking slot occupied→open sync
  IF COALESCE(v_row.deployment_type, '') <> 'Roving' THEN
    v_sep_reason_code := CASE p_separation_status
      WHEN 'Endo'            THEN 'ENDO'
      WHEN 'End of Contract' THEN 'ENDO'
      ELSE 'RESIGNED'
    END;

    PERFORM public.fn_sync_slot_to_open(
      p_plantilla_id => p_plantilla_id,
      p_reason_code  => v_sep_reason_code,
      p_performed_by => public.get_current_profile_id(),
      p_source_fn    => 'plantilla_update_separation'
    );

    -- Ensure vacancy is marked Open in public.vacancies
    IF v_row.vcode IS NOT NULL THEN
      UPDATE public.vacancies
      SET status = 'Open',
          is_archived = false,
          archived_at = NULL,
          archived_by = NULL,
          deleted_at = NULL,
          has_pending_closure = false,
          vacant_date = p_effective_date,
          updated_at = NOW()
      WHERE vcode = v_row.vcode;
    END IF;
  END IF;

  RETURN v_row;
END;
$function$;

REVOKE ALL ON FUNCTION public.plantilla_update_separation(uuid, text, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.plantilla_update_separation(uuid, text, date, text) TO authenticated, service_role;

COMMIT;
