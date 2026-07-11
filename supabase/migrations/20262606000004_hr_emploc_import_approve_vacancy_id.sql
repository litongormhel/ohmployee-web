-- Migration: 20262606000004_hr_emploc_import_approve_vacancy_id
-- Created: 2026-06-26
-- Prompt ID: ohm#6t9v3a1k (continuation — UAT regression fix)
-- Purpose: Fix approve_hr_emploc_import to satisfy hr_emploc_assignment_type_consistency_chk.
--
-- Root cause:
--   The constraint requires vacancy_id IS NOT NULL when assignment_type = 'Stationary'.
--   20262606000003 rewrote approve to derive store/position from slot but did not add
--   vacancy_id to the hr_emploc INSERT. The INSERT also omitted store_id and
--   vacancy_code_snapshot which the normal (non-import) creation path populates.
--
-- Changes vs 20262606000003 (approve_hr_emploc_import only):
--   1. DECLARE: +v_vacancy_id UUID
--   2. After slot + duplicate guards pass: resolve vacancy_id from vacancies.
--      If not found: block row (vacancy_id IS NOT NULL required for Stationary).
--   3. hr_emploc INSERT: add vacancy_id, store_id (= slot store), vacancy_code_snapshot.
--
-- No other functions touched (submit/reject/rollback/fn_set_slot_status unchanged).
-- No schema changes. No Flutter changes.
--
-- Smoke Tests:
-- S1: Approve batch for VCAPG2_0007 → no constraint error; hr_emploc row created
-- S2: hr_emploc.vacancy_id NOT NULL; store_id = slot store; slot_id NOT NULL;
--     vacancy_code_snapshot = vcode; assignment_type = Stationary
-- S3: vacancies.status = 'Filled' for VCAPG2_0007 after approval
-- S4: Vacancy not found → row downgraded to blocked;
--     error: "Vacancy record not found for VCode ..."

BEGIN;

CREATE OR REPLACE FUNCTION public.approve_hr_emploc_import(p_batch_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id          UUID;
  v_profile_id         UUID;
  v_batch              public.hr_emploc_import_batches%ROWTYPE;
  v_row                public.hr_emploc_import_rows%ROWTYPE;
  v_account_id         UUID;
  v_account_name       TEXT;
  v_hr_id              UUID;
  v_full_name          TEXT;
  v_created            INTEGER := 0;
  -- slot re-verification
  v_slot_id            UUID;
  v_slot_status_rc     TEXT;
  v_slot_occupant_rc   UUID;
  v_occupant_label     TEXT;
  -- slot-derived metadata (not from user upload)
  v_slot_store_id_rc   UUID;
  v_slot_position_rc   TEXT;
  v_slot_store_name_rc TEXT;
  -- vacancy resolution (required for Stationary constraint)
  v_vacancy_id         UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can approve HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_batch
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;

  CASE v_batch.status
    WHEN 'approved'    THEN RAISE EXCEPTION 'This batch has already been approved' USING ERRCODE = 'P0001';
    WHEN 'rejected'    THEN RAISE EXCEPTION 'Rejected batches cannot be approved' USING ERRCODE = 'P0001';
    WHEN 'rolled_back' THEN RAISE EXCEPTION 'Rolled-back batches cannot be re-approved' USING ERRCODE = 'P0001';
    ELSE NULL;
  END CASE;

  IF v_batch.valid_rows = 0 THEN
    RAISE EXCEPTION 'No valid rows to import — all rows are blocked' USING ERRCODE = 'P0001';
  END IF;

  FOR v_row IN
    SELECT * FROM public.hr_emploc_import_rows
    WHERE batch_id = p_batch_id AND validation_status = 'valid'
    ORDER BY row_number
  LOOP
    -- ── Re-verify account ────────────────────────────────────────────────────
    SELECT a.id, a.account_name INTO v_account_id, v_account_name
    FROM public.accounts a
    WHERE a.group_id = v_batch.group_id
      AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_row.account_name))
    LIMIT 1;

    IF v_account_id IS NULL THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'ACCOUNT',
          'msg', format('Account "%s" not found at approval time.', v_row.account_name)
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- ── Re-verify Plantilla Slot — capture store_id and position ─────────────
    v_slot_id            := NULL;
    v_slot_status_rc     := NULL;
    v_slot_occupant_rc   := NULL;
    v_occupant_label     := NULL;
    v_slot_store_id_rc   := NULL;
    v_slot_position_rc   := NULL;
    v_slot_store_name_rc := NULL;
    v_vacancy_id         := NULL;

    SELECT
      ps.id,
      ps.slot_status,
      ps.current_occupant_plantilla_id,
      ps.store_id,
      ps.position
    INTO
      v_slot_id,
      v_slot_status_rc,
      v_slot_occupant_rc,
      v_slot_store_id_rc,
      v_slot_position_rc
    FROM public.plantilla_slots ps
    WHERE ps.legacy_vcode = v_row.vcode
    LIMIT 1;

    IF NOT FOUND THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" no longer has a Plantilla slot at approval time.',
            v_row.vcode
          )
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    IF v_slot_status_rc NOT IN ('open', 'pipeline', 'hr_processing') THEN
      IF v_slot_status_rc = 'occupied' OR v_slot_occupant_rc IS NOT NULL THEN
        IF v_slot_occupant_rc IS NOT NULL THEN
          SELECT COALESCE(NULLIF(TRIM(p.employee_no), ''), NULLIF(TRIM(p.employee_name), ''), 'an active employee')
          INTO v_occupant_label
          FROM public.plantilla p
          WHERE p.id = v_slot_occupant_rc;
        END IF;
        UPDATE public.hr_emploc_import_rows SET
          validation_status = 'blocked',
          validation_errors = jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" was occupied between submit and approval by %s.',
              v_row.vcode,
              COALESCE(v_occupant_label, 'an active employee')
            )
          ))
        WHERE id = v_row.id;
      ELSE
        UPDATE public.hr_emploc_import_rows SET
          validation_status = 'blocked',
          validation_errors = jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" is no longer importable at approval time (current state: %s).',
              v_row.vcode,
              COALESCE(v_slot_status_rc, 'unknown')
            )
          ))
        WHERE id = v_row.id;
      END IF;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- ── Guard: prevent duplicate slot occupancy ───────────────────────────────
    IF v_slot_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.hr_emploc
      WHERE slot_id = v_slot_id
        AND deleted_at IS NULL
    ) THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" slot already has an active HR Emploc record at approval time.',
            v_row.vcode
          )
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- ── Resolve store_name from slot ─────────────────────────────────────────
    SELECT s.store_name INTO v_slot_store_name_rc
    FROM public.stores s WHERE s.id = v_slot_store_id_rc;

    -- ── Resolve vacancy_id (required: Stationary constraint vacancy_id IS NOT NULL) ──
    SELECT id INTO v_vacancy_id
    FROM public.vacancies
    WHERE vcode      = v_row.vcode
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_vacancy_id IS NULL THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'Vacancy record not found for VCode "%s". '
            'A vacancy is required to create a Stationary HR Emploc record.',
            v_row.vcode
          )
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- ── All checks passed — create HR Emploc record ──────────────────────────
    -- Slot stays hr_processing (ADR-001 B2): move_to_plantilla transitions it
    -- to occupied when the Plantilla employee record is created.
    v_full_name := TRIM(
      v_row.first_name || ' ' ||
      COALESCE(NULLIF(TRIM(v_row.middle_name), ''), '') || ' ' ||
      v_row.last_name
    );

    INSERT INTO public.hr_emploc (
      applicant_name,
      vcode,
      vacancy_code_snapshot,
      vacancy_id,
      account,
      account_id,
      store_id,
      position,
      store_name,
      status,
      hr_status,
      requirement_overall_status,
      assignment_type,
      covered_stores,
      hired_date,
      created_by,
      updated_by,
      import_batch_id,
      slot_id
    ) VALUES (
      v_full_name,
      v_row.vcode,
      v_row.vcode,                          -- vacancy_code_snapshot
      v_vacancy_id,                          -- vacancy_id (satisfies Stationary constraint)
      COALESCE(v_account_name, v_row.account_name),
      v_account_id,
      v_slot_store_id_rc,                    -- store_id from slot
      COALESCE(v_slot_position_rc, ''),      -- position from slot
      v_slot_store_name_rc,                  -- store_name from slot
      'Pending Emploc',
      'Pending',
      'Incomplete',
      'Stationary'::public.hr_emploc_assignment_type,
      '[]'::jsonb,
      v_row.date_hired,
      v_profile_id,
      v_profile_id,
      p_batch_id,
      v_slot_id
    ) RETURNING id INTO v_hr_id;

    UPDATE public.hr_emploc_import_rows
    SET hr_emploc_id = v_hr_id
    WHERE id = v_row.id;

    -- ── Close vacancy (ADR-001 Rule 5: vacancy → Filled on import approval) ──
    UPDATE public.vacancies
    SET
      status     = 'Filled',
      updated_at = now(),
      updated_by = v_profile_id
    WHERE vcode      = v_row.vcode
      AND deleted_at IS NULL
      AND (is_archived IS NULL OR is_archived = false)
      AND status NOT IN ('Filled', 'Closed', 'Cancelled', 'Archived');

    v_created := v_created + 1;
  END LOOP;

  UPDATE public.hr_emploc_import_batches SET
    status       = 'approved',
    approved_by  = v_profile_id,
    approved_at  = now(),
    created_rows = v_created
  WHERE id = p_batch_id;

  RETURN json_build_object('records_created', v_created);
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_hr_emploc_import(uuid) TO authenticated;

COMMIT;
