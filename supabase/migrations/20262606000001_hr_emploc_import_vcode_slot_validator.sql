-- Migration: 20262606000001_hr_emploc_import_vcode_slot_validator
-- Created: 2026-06-26
-- Prompt ID: ohm#9r6m2xk7
-- Purpose: Rewrite VCode validation in submit_hr_emploc_import and approve_hr_emploc_import
--          to use plantilla_slots as the authoritative source (ADR-001 Rule 3 + Rule 6).
--          public.vacancies is retained only as a diagnostic fallback for the "legacy-only"
--          error message — it is never used to approve import eligibility.
--
-- Root cause fixed:
--   Previous validator queried public.vacancies.vcode exclusively. VCodes that exist as
--   open plantilla_slots.legacy_vcode entries but have no vacancies mirror were falsely
--   rejected with a generic "not found or is archived" message. slot_status was never
--   checked, so occupied/closed/hc_reduced slots could not produce correct error messages.
--
-- Validation order (submit_hr_emploc_import, per ADR-001 Rule 6):
--   1. Normalize uploaded VCode.
--   2. Look up plantilla_slots by legacy_vcode.
--   3. NOT FOUND → check vacancies for diagnostic legacy-only message.
--   4. slot_status = 'archived'     → "VCode is archived."
--   5. slot_status IN ('closed','hc_reduced') → "VCode is closed..."
--   6. slot_status = 'occupied' OR current_occupant IS NOT NULL → "already occupied by <name/no>"
--   7. group_id mismatch            → "VCode belongs to <actual group>, not selected <group>."
--   8. store_id → stores.store_name mismatch → specific store mismatch message.
--   9. position mismatch (if both slot and row have position) → specific position message.
--  10. Only open / pipeline / hr_processing slots pass all checks.
--
-- Approval re-check (approve_hr_emploc_import):
--   Re-verifies slot via plantilla_slots at approval time, not vacancies.
--   Blocks if slot no longer exists or is no longer in an importable state.
--
-- No schema changes. No Flutter changes. No other RPCs touched.
--
-- Smoke Tests:
-- S1: VCode in plantilla_slots with slot_status='open', correct group+store → valid
-- S2: VCode not in plantilla_slots, not in vacancies → "VCode not found. Create the vacancy slot first..."
-- S3: VCode not in plantilla_slots, but found in vacancies → "exists in legacy vacancy only..."
-- S4: VCode in plantilla_slots with slot_status='archived' → "VCode is archived."
-- S5: VCode in plantilla_slots with slot_status='closed' → "VCode is closed..."
-- S6: VCode in plantilla_slots with slot_status='hc_reduced' → "VCode is closed..."
-- S7: VCode in plantilla_slots with slot_status='occupied' → "already occupied by <name/no>"
-- S8: VCode in plantilla_slots, group_id != selected group → "VCode belongs to <actual group>..."
-- S9: VCode in plantilla_slots, store name mismatch → specific store mismatch message
-- S10: VCode in plantilla_slots, position mismatch (both sides non-null) → specific position message
-- S11: approve_hr_emploc_import — slot no longer exists at approval time → row blocked
-- S12: approve_hr_emploc_import — slot is occupied at approval time → row blocked
-- S13: Placeholder VC00001 (no slot, no vacancy) → "not found. Create the vacancy slot first..."

BEGIN;

-- ── 1. submit_hr_emploc_import (slot-first VCode validator) ──────────────────
CREATE OR REPLACE FUNCTION public.submit_hr_emploc_import(
  p_file_name TEXT,
  p_group_id  UUID,
  p_rows      JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id        UUID;  -- auth.users.id — session check only
  v_profile_id       UUID;  -- users_profile.id — for FK columns
  v_batch_id         UUID;
  v_group_name       TEXT;
  v_row              JSONB;
  v_row_number       INTEGER := 0;
  v_total            INTEGER := 0;
  v_valid            INTEGER := 0;
  v_blocked          INTEGER := 0;
  v_duplicate        INTEGER := 0;
  -- per-row values
  v_last_name        TEXT;
  v_first_name       TEXT;
  v_middle_name      TEXT;
  v_account_name     TEXT;
  v_store            TEXT;
  v_vcode            TEXT;
  v_date_hired       DATE;
  v_position         TEXT;
  v_employment_type  TEXT;
  v_row_group        TEXT;
  -- slot-first VCode lookup
  v_slot_id          UUID;
  v_slot_status      TEXT;
  v_slot_group_id    UUID;
  v_slot_store_id    UUID;
  v_slot_position    TEXT;
  v_slot_occupant_id UUID;
  v_slot_store_name  TEXT;
  v_actual_group_name TEXT;
  v_occupant_label   TEXT;
  -- account resolution
  v_acct_id          UUID;
  -- validation
  v_errors           JSONB;
  v_status           TEXT;
  v_identity         TEXT;
  -- de-dup tracking
  v_seen_identities  TEXT[]  := ARRAY[]::TEXT[];
  v_seen_vcodes      TEXT[]  := ARRAY[]::TEXT[];
  v_seen_groups      TEXT[]  := ARRAY[]::TEXT[];
  v_multi_group      BOOLEAN := FALSE;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions to submit HR Emploc import'
      USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Validate group ─────────────────────────────────────────────────────────
  SELECT group_name INTO v_group_name
  FROM public.groups WHERE id = p_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0001';
  END IF;

  -- ── Pre-pass: detect multiple groups in file ───────────────────────────────
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_row_group := UPPER(TRIM(COALESCE(v_row->>'GROUP', '')));
    IF v_row_group <> '' AND NOT (v_row_group = ANY(v_seen_groups)) THEN
      v_seen_groups := array_append(v_seen_groups, v_row_group);
    END IF;
  END LOOP;
  IF array_length(v_seen_groups, 1) > 1 THEN
    v_multi_group := TRUE;
  END IF;

  -- ── Create batch ──────────────────────────────────────────────────────────
  INSERT INTO public.hr_emploc_import_batches (
    file_name, status, group_id, group_name,
    total_rows, valid_rows, blocked_rows, duplicate_rows,
    uploaded_by, uploaded_at
  ) VALUES (
    p_file_name, 'pending_approval', p_group_id, v_group_name,
    0, 0, 0, 0,
    v_profile_id, now()
  ) RETURNING id INTO v_batch_id;

  -- ── Process rows ──────────────────────────────────────────────────────────
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_row_number      := v_row_number + 1;
    v_total           := v_total + 1;
    v_errors          := '[]'::jsonb;
    v_status          := 'valid';

    v_row_group       := NULLIF(TRIM(COALESCE(v_row->>'GROUP', '')), '');
    v_account_name    := NULLIF(TRIM(COALESCE(v_row->>'ACCOUNT', '')), '');
    v_vcode           := NULLIF(TRIM(COALESCE(v_row->>'VCODE', '')), '');
    v_store           := NULLIF(TRIM(COALESCE(v_row->>'STORE', '')), '');
    v_last_name       := NULLIF(TRIM(COALESCE(v_row->>'LAST_NAME', '')), '');
    v_first_name      := NULLIF(TRIM(COALESCE(v_row->>'FIRST_NAME', '')), '');
    v_middle_name     := NULLIF(TRIM(COALESCE(v_row->>'MIDDLE_NAME', '')), '');
    v_position        := NULLIF(TRIM(COALESCE(v_row->>'POSITION', '')), '');
    v_employment_type := NULLIF(TRIM(COALESCE(v_row->>'EMPLOYMENT_TYPE', '')), '');

    -- Parse DATE_HIRED
    v_date_hired := NULL;
    BEGIN
      v_date_hired := (v_row->>'DATE_HIRED')::DATE;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'DATE_HIRED', 'msg', 'Invalid date format — use YYYY-MM-DD.'
      ));
      v_status := 'blocked';
    END;

    -- Required field checks
    IF v_row_group IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','GROUP','msg','Group is required.'));
      v_status := 'blocked';
    END IF;
    IF v_account_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','ACCOUNT','msg','Account is required.'));
      v_status := 'blocked';
    END IF;
    IF v_vcode IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','VCODE','msg','VCode is required.'));
      v_status := 'blocked';
    END IF;
    IF v_store IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','STORE','msg','Store is required.'));
      v_status := 'blocked';
    END IF;
    IF v_last_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','LAST_NAME','msg','Last name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_first_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','FIRST_NAME','msg','First name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_middle_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','MIDDLE_NAME','msg','Middle name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_date_hired IS NULL AND v_status = 'valid' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','DATE_HIRED','msg','Date hired is required.'));
      v_status := 'blocked';
    END IF;

    -- Cross-group check
    IF v_multi_group THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'GROUP',
        'msg', 'Upload blocked: file contains rows from multiple groups. One group per upload only.'
      ));
      v_status := 'blocked';
    ELSIF v_row_group IS NOT NULL
      AND UPPER(v_row_group) <> UPPER(v_group_name)
    THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'GROUP',
        'msg', format('Group "%s" does not match selected group "%s".', v_row_group, v_group_name)
      ));
      v_status := 'blocked';
    END IF;

    -- ── DB validation (only when basic fields are present) ──────────────────
    IF v_status = 'valid' THEN

      -- ── STEP 1: Plantilla Slot lookup (authoritative per ADR-001 Rule 3) ──
      v_slot_id          := NULL;
      v_slot_status      := NULL;
      v_slot_group_id    := NULL;
      v_slot_store_id    := NULL;
      v_slot_position    := NULL;
      v_slot_occupant_id := NULL;
      v_slot_store_name  := NULL;
      v_actual_group_name := NULL;
      v_occupant_label   := NULL;

      SELECT
        ps.id,
        ps.slot_status,
        ps.group_id,
        ps.store_id,
        ps.position,
        ps.current_occupant_plantilla_id
      INTO
        v_slot_id,
        v_slot_status,
        v_slot_group_id,
        v_slot_store_id,
        v_slot_position,
        v_slot_occupant_id
      FROM public.plantilla_slots ps
      WHERE ps.legacy_vcode = v_vcode
      LIMIT 1;

      IF NOT FOUND THEN
        -- Diagnostic fallback: check legacy vacancies only for a clearer message.
        -- vacancies result does NOT grant eligibility.
        IF EXISTS (
          SELECT 1 FROM public.vacancies WHERE vcode = v_vcode
        ) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" exists in legacy vacancy only. No Plantilla slot found. Repair or create the Plantilla slot first.',
              v_vcode
            )
          ));
        ELSE
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" not found. Create the vacancy slot first via Vacancy Import or HC Request.',
              v_vcode
            )
          ));
        END IF;
        v_status := 'blocked';

      ELSIF v_slot_status = 'archived' THEN
        -- STEP 4: Archived slot
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" is archived.', v_vcode)
        ));
        v_status := 'blocked';

      ELSIF v_slot_status IN ('closed', 'hc_reduced') THEN
        -- STEP 5: Closed or HC-reduced slot
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" is closed and cannot be imported to HR Emploc.', v_vcode)
        ));
        v_status := 'blocked';

      ELSIF v_slot_status = 'occupied' OR v_slot_occupant_id IS NOT NULL THEN
        -- STEP 6: Occupied slot — resolve occupant label from plantilla
        IF v_slot_occupant_id IS NOT NULL THEN
          SELECT
            COALESCE(
              NULLIF(TRIM(p.employee_no), ''),
              NULLIF(TRIM(p.employee_name), ''),
              'an active employee'
            )
          INTO v_occupant_label
          FROM public.plantilla p
          WHERE p.id = v_slot_occupant_id;
        END IF;
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" is already occupied by %s.',
            v_vcode,
            COALESCE(v_occupant_label, 'an active employee')
          )
        ));
        v_status := 'blocked';

      ELSIF v_slot_status NOT IN ('open', 'pipeline', 'hr_processing') THEN
        -- STEP 10: Unknown or non-importable slot state (future-proofing)
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" is not in an importable state (current state: %s).',
            v_vcode,
            COALESCE(v_slot_status, 'unknown')
          )
        ));
        v_status := 'blocked';

      ELSE
        -- Slot is open / pipeline / hr_processing — proceed with attribute checks

        -- STEP 7: Group check using slot's group_id
        IF v_slot_group_id IS DISTINCT FROM p_group_id THEN
          SELECT g.group_name INTO v_actual_group_name
          FROM public.groups g WHERE g.id = v_slot_group_id;

          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" belongs to %s, not selected %s.',
              v_vcode,
              COALESCE(v_actual_group_name, v_slot_group_id::TEXT),
              v_group_name
            )
          ));
          v_status := 'blocked';
        END IF;

        -- STEP 8: Store check — slot store_id → stores.store_name vs STORE column
        IF v_status = 'valid' THEN
          SELECT s.store_name INTO v_slot_store_name
          FROM public.stores s WHERE s.id = v_slot_store_id;

          IF v_slot_store_name IS NULL
             OR UPPER(TRIM(v_slot_store_name)) <> UPPER(TRIM(v_store))
          THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'field', 'STORE',
              'msg', format(
                'VCode "%s" is for store "%s", but STORE column says "%s".',
                v_vcode,
                COALESCE(v_slot_store_name, '(none)'),
                v_store
              )
            ));
            v_status := 'blocked';
          END IF;
        END IF;

        -- STEP 9: Position check — only when both slot and row carry a non-null position
        IF v_status = 'valid'
           AND v_slot_position IS NOT NULL
           AND v_position IS NOT NULL
        THEN
          IF UPPER(TRIM(v_slot_position)) <> UPPER(TRIM(v_position)) THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'field', 'POSITION',
              'msg', format(
                'VCode "%s" is for position "%s", but POSITION column says "%s".',
                v_vcode,
                v_slot_position,
                v_position
              )
            ));
            v_status := 'blocked';
          END IF;
        END IF;

      END IF; -- end slot state branch

      -- ── STEP A: Account must belong to the selected group ──────────────────
      IF v_status = 'valid' THEN
        SELECT a.id INTO v_acct_id
        FROM public.accounts a
        WHERE a.group_id = p_group_id
          AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_account_name))
        LIMIT 1;

        IF v_acct_id IS NULL THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'ACCOUNT',
            'msg', format('Account "%s" not found in the selected group.', v_account_name)
          ));
          v_status := 'blocked';
        END IF;
      END IF;

      -- ── STEP B: VCode already active in hr_emploc ──────────────────────────
      IF v_status = 'valid' THEN
        IF EXISTS (
          SELECT 1 FROM public.hr_emploc h
          WHERE h.vcode = v_vcode
            AND h.deleted_at IS NULL
        ) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" already has an active HR Emploc record.', v_vcode)
          ));
          v_status := 'blocked';
        END IF;
      END IF;

      -- ── STEP C: In-file VCode duplicate ────────────────────────────────────
      IF v_status = 'valid' THEN
        IF UPPER(v_vcode) = ANY(v_seen_vcodes) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" appears more than once in this file.', v_vcode)
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        ELSE
          v_seen_vcodes := array_append(v_seen_vcodes, UPPER(v_vcode));
        END IF;
      END IF;

      -- ── STEP D: In-file name duplicate ─────────────────────────────────────
      IF v_status = 'valid' THEN
        v_identity := UPPER(COALESCE(v_last_name,''))   || '|'
                   || UPPER(COALESCE(v_first_name,''))  || '|'
                   || UPPER(COALESCE(v_middle_name,'')) || '|'
                   || UPPER(COALESCE(v_account_name,''))|| '|'
                   || COALESCE(v_date_hired::TEXT,'');

        IF v_identity = ANY(v_seen_identities) THEN
          v_errors  := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'identity',
            'msg', 'Duplicate within this file (same name, account, and date hired).'
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        ELSE
          v_seen_identities := array_append(v_seen_identities, v_identity);
        END IF;
      END IF;

      -- ── STEP E: DB name+account+date duplicate ─────────────────────────────
      IF v_status = 'valid' THEN
        IF EXISTS (
          SELECT 1
          FROM public.hr_emploc h
          JOIN public.accounts a ON a.id = h.account_id
          WHERE h.deleted_at IS NULL
            AND a.group_id = p_group_id
            AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_account_name))
            AND h.hired_date = v_date_hired
            AND UPPER(TRIM(h.applicant_name)) = UPPER(TRIM(
              v_first_name || ' ' || v_middle_name || ' ' || v_last_name
            ))
        ) THEN
          v_errors  := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'identity',
            'msg', 'Duplicate: HR Emploc record with this name and date hired already exists.'
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        END IF;
      END IF;

    END IF; -- end DB validation block

    -- Tally
    IF v_status = 'valid' THEN
      v_valid   := v_valid + 1;
    ELSE
      v_blocked := v_blocked + 1;
    END IF;

    -- Insert staged row
    INSERT INTO public.hr_emploc_import_rows (
      batch_id, row_number,
      group_name, account_name, last_name, first_name, middle_name,
      date_hired, position, store_name, employment_type, vcode,
      validation_status, validation_errors
    ) VALUES (
      v_batch_id, v_row_number,
      v_row_group, v_account_name, v_last_name, v_first_name, v_middle_name,
      v_date_hired, v_position, v_store, v_employment_type, v_vcode,
      v_status, v_errors
    );
  END LOOP;

  -- Update batch summary counts
  UPDATE public.hr_emploc_import_batches SET
    total_rows     = v_total,
    valid_rows     = v_valid,
    blocked_rows   = v_blocked,
    duplicate_rows = v_duplicate
  WHERE id = v_batch_id;

  RETURN json_build_object('batch_id', v_batch_id);
END;
$$;

-- ── 2. approve_hr_emploc_import (slot-first re-verification) ─────────────────
CREATE OR REPLACE FUNCTION public.approve_hr_emploc_import(p_batch_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id        UUID;  -- auth.users.id — session check only
  v_profile_id       UUID;  -- users_profile.id — for FK columns
  v_batch            public.hr_emploc_import_batches%ROWTYPE;
  v_row              public.hr_emploc_import_rows%ROWTYPE;
  v_account_id       UUID;
  v_account_name     TEXT;
  v_hr_id            UUID;
  v_full_name        TEXT;
  v_created          INTEGER := 0;
  -- slot re-verification
  v_slot_status_rc   TEXT;
  v_slot_occupant_rc UUID;
  v_occupant_label   TEXT;
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

    -- ── Re-verify Plantilla Slot (authoritative — not vacancies) ────────────
    v_slot_status_rc   := NULL;
    v_slot_occupant_rc := NULL;
    v_occupant_label   := NULL;

    SELECT ps.slot_status, ps.current_occupant_plantilla_id
      INTO v_slot_status_rc, v_slot_occupant_rc
    FROM public.plantilla_slots ps
    WHERE ps.legacy_vcode = v_row.vcode
    LIMIT 1;

    IF NOT FOUND THEN
      -- Slot no longer exists
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
      -- Slot is no longer in an importable state
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

    -- ── All checks passed — create HR Emploc record ──────────────────────────
    v_full_name := TRIM(v_row.first_name || ' ' || v_row.middle_name || ' ' || v_row.last_name);

    INSERT INTO public.hr_emploc (
      applicant_name,
      vcode,
      account,
      account_id,
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
      import_batch_id
    ) VALUES (
      v_full_name,
      v_row.vcode,
      COALESCE(v_account_name, v_row.account_name),
      v_account_id,
      COALESCE(v_row.position, ''),
      v_row.store_name,
      'Pending Emploc',
      'Pending',
      'Incomplete',
      'Stationary'::public.hr_emploc_assignment_type,
      '[]'::jsonb,
      v_row.date_hired,
      v_profile_id,
      v_profile_id,
      p_batch_id
    ) RETURNING id INTO v_hr_id;

    UPDATE public.hr_emploc_import_rows
    SET hr_emploc_id = v_hr_id
    WHERE id = v_row.id;

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

COMMIT;
