-- Migration: 20262606000003_hr_emploc_import_remove_store_pos_emptype
-- Created: 2026-06-26
-- Prompt ID: ohm#6t9v3a1k
-- Purpose: Remove STORE, POSITION, and EMPLOYMENT_TYPE from the HR Emploc Import
--          XLSX template and backend validation. Derive store_name and position from
--          the resolved Plantilla Slot (VCode-first slot architecture, ADR-001 Rule 3).
--          Add comprehensive MIDDLE_NAME validation.
--
-- Root cause:
--   STORE, POSITION, and EMPLOYMENT_TYPE were user-supplied columns in the import
--   template. Since VCODE now resolves to an authoritative Plantilla Slot, these fields
--   are already known from the slot. Requiring them from the user introduces redundancy
--   and an unnecessary validation surface that causes false rejections.
--
-- Changes vs 20262606000002 (submit_hr_emploc_import):
--   1. Remove v_store, v_employment_type from DECLARE.
--   2. Change v_middle_name extraction to raw TRIM (not NULLIF) to enable full validation.
--   3. Remove v_store / v_employment_type extraction from uploaded row JSON.
--   4. Remove required-field check for STORE.
--   5. Replace simple MIDDLE_NAME null check with 5-rule validation block:
--        blank → specific required message
--        N/A (any case variant) → use NA message
--        placeholder (-, ., ?) → invalid message
--        NA (any case) → normalize to 'NA'
--        single letter (<2 chars, not NA/placeholder) → length message
--   6. In slot ELSE branch: keep STEP 7 (group check); remove STEP 8 (store check);
--      add store_name derivation from slot store_id; remove STEP 9 (position check).
--   7. In hr_emploc_import_rows INSERT: store_name from slot, position from slot,
--      employment_type = NULL.
--   Pass 2 (slot reservation) is unchanged.
--
-- Changes vs 20262606000002 (approve_hr_emploc_import):
--   1. Add v_slot_store_id_rc UUID, v_slot_position_rc TEXT, v_slot_store_name_rc TEXT
--      to DECLARE.
--   2. Expand slot SELECT to also capture ps.store_id and ps.position.
--   3. After slot validity confirmed, resolve store_name from stores by slot's store_id.
--   4. In hr_emploc INSERT: use COALESCE(v_slot_position_rc, '') and v_slot_store_name_rc
--      instead of v_row.position / v_row.store_name.
--   reject_hr_emploc_import and rollback_hr_emploc_import are unchanged.
--
-- No schema changes. No Flutter model changes. No other RPCs touched.
--
-- Smoke Tests:
-- S1: Upload file without STORE/POSITION/EMPLOYMENT_TYPE columns → parses and submits OK
-- S2: MIDDLE_NAME blank → blocked: "Middle Name is required. Use 'NA'..."
-- S3: MIDDLE_NAME = "N/A" → blocked: "Use 'NA' instead of 'N/A'..."
-- S4: MIDDLE_NAME = "n/a" → blocked (same)
-- S5: MIDDLE_NAME = "A" → blocked: "Middle Name must contain at least two characters..."
-- S6: MIDDLE_NAME = "-" → blocked: "Middle Name is invalid..."
-- S7: MIDDLE_NAME = "NA" → valid; stored as 'NA'
-- S8: MIDDLE_NAME = "na" → normalized to 'NA'; valid
-- S9: MIDDLE_NAME = "Dela Cruz" → valid
-- S10: Approve batch → store_name and position in hr_emploc derived from slot, not from row
-- S11: Slot VCode with store "ABC Trinoma" → hr_emploc.store_name = 'ABC Trinoma' (no STORE column needed)
-- S12: All existing slot-first validation (occupied, archived, group mismatch) unchanged

BEGIN;

-- ============================================================
-- §1  submit_hr_emploc_import — remove STORE/POSITION/EMPLOYMENT_TYPE;
--     derive from slot; add MIDDLE_NAME validation
-- ============================================================

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
  v_caller_id        UUID;
  v_profile_id       UUID;
  v_batch_id         UUID;
  v_group_name       TEXT;
  v_row              JSONB;
  v_row_number       INTEGER := 0;
  v_total            INTEGER := 0;
  v_valid            INTEGER := 0;
  v_blocked          INTEGER := 0;
  v_duplicate        INTEGER := 0;
  -- per-row values (STORE and EMPLOYMENT_TYPE removed — derived from slot)
  v_last_name        TEXT;
  v_first_name       TEXT;
  v_middle_name      TEXT;
  v_account_name     TEXT;
  v_vcode            TEXT;
  v_date_hired       DATE;
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
  -- Pass 2: slot reservation
  v_valid_vcodes     TEXT[]  := ARRAY[]::TEXT[];
  v_reserve_vcode    TEXT;
  v_slot_result      JSONB;
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

  -- ── Pass 1: Validate all rows and stage them ──────────────────────────────
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_row_number   := v_row_number + 1;
    v_total        := v_total + 1;
    v_errors       := '[]'::jsonb;
    v_status       := 'valid';

    -- Extract uploaded fields (STORE/POSITION/EMPLOYMENT_TYPE intentionally absent)
    v_row_group    := NULLIF(TRIM(COALESCE(v_row->>'GROUP',       '')), '');
    v_account_name := NULLIF(TRIM(COALESCE(v_row->>'ACCOUNT',     '')), '');
    v_vcode        := NULLIF(TRIM(COALESCE(v_row->>'VCODE',       '')), '');
    v_last_name    := NULLIF(TRIM(COALESCE(v_row->>'LAST_NAME',   '')), '');
    v_first_name   := NULLIF(TRIM(COALESCE(v_row->>'FIRST_NAME',  '')), '');
    -- MIDDLE_NAME: raw trim only (NULLIF deferred — full validation below)
    v_middle_name  := TRIM(COALESCE(v_row->>'MIDDLE_NAME', ''));

    -- Reset slot-derived fields for this row
    v_slot_id          := NULL;
    v_slot_status      := NULL;
    v_slot_group_id    := NULL;
    v_slot_store_id    := NULL;
    v_slot_position    := NULL;
    v_slot_occupant_id := NULL;
    v_slot_store_name  := NULL;
    v_actual_group_name := NULL;
    v_occupant_label   := NULL;

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

    -- ── Required field checks ──────────────────────────────────────────────
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
    IF v_last_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','LAST_NAME','msg','Last name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_first_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','FIRST_NAME','msg','First name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_date_hired IS NULL AND v_status = 'valid' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','DATE_HIRED','msg','Date hired is required.'));
      v_status := 'blocked';
    END IF;

    -- ── MIDDLE_NAME validation (replaces simple null check) ────────────────
    IF LENGTH(v_middle_name) = 0 THEN
      -- Blank
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name is required. Use ''NA'' if the employee has no middle name.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF UPPER(v_middle_name) ~ '^N\s*/\s*A$' THEN
      -- N/A in any case variant (N/A, n/a, N / A, N/a, etc.)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Use ''NA'' instead of ''N/A'' for employees without a middle name.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF v_middle_name = ANY(ARRAY['-', '.', '?']) THEN
      -- Placeholder values
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name is invalid. Use a valid middle name or ''NA'' if none exists.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF UPPER(v_middle_name) = 'NA' THEN
      -- Normalize any case of NA to uppercase
      v_middle_name := 'NA';

    ELSIF LENGTH(v_middle_name) < 2 THEN
      -- Single letter (1 char not already caught by placeholder check)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name must contain at least two characters, or use ''NA'' if none exists.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    END IF;
    -- v_middle_name is now either NULL (blocked), 'NA', or a valid ≥2-char name.

    -- ── Cross-group check ──────────────────────────────────────────────────
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
        IF EXISTS (SELECT 1 FROM public.vacancies WHERE vcode = v_vcode) THEN
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
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" is archived.', v_vcode)
        ));
        v_status := 'blocked';

      ELSIF v_slot_status IN ('closed', 'hc_reduced') THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" is closed and cannot be imported to HR Emploc.', v_vcode)
        ));
        v_status := 'blocked';

      ELSIF v_slot_status = 'occupied' OR v_slot_occupant_id IS NOT NULL THEN
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
        -- Slot is open / pipeline / hr_processing — proceed with checks

        -- STEP 7: Group check using slot's group_id (unchanged)
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

        -- Derive store_name from slot (STEP 8 removed — no longer user-supplied)
        -- v_slot_position is already captured from the STEP 1 SELECT above.
        IF v_status = 'valid' THEN
          SELECT s.store_name INTO v_slot_store_name
          FROM public.stores s WHERE s.id = v_slot_store_id;
        END IF;

        -- STEP 9 (position cross-check) removed — position is slot-derived, not user input.

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
        v_identity := UPPER(COALESCE(v_last_name,''))    || '|'
                   || UPPER(COALESCE(v_first_name,''))   || '|'
                   || UPPER(COALESCE(v_middle_name,''))  || '|'
                   || UPPER(COALESCE(v_account_name,'')) || '|'
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
              v_first_name || ' ' || COALESCE(v_middle_name, '') || ' ' || v_last_name
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

    -- Tally and collect valid vcodes for Pass 2 slot reservation
    IF v_status = 'valid' THEN
      v_valid        := v_valid + 1;
      v_valid_vcodes := array_append(v_valid_vcodes, v_vcode);
    ELSE
      v_blocked := v_blocked + 1;
    END IF;

    -- Stage row (store_name and position from slot; employment_type = NULL)
    INSERT INTO public.hr_emploc_import_rows (
      batch_id, row_number,
      group_name, account_name, last_name, first_name, middle_name,
      date_hired, position, store_name, employment_type, vcode,
      validation_status, validation_errors
    ) VALUES (
      v_batch_id, v_row_number,
      v_row_group, v_account_name, v_last_name, v_first_name, v_middle_name,
      v_date_hired, v_slot_position, v_slot_store_name, NULL, v_vcode,
      v_status, v_errors
    );
  END LOOP;

  -- ── Pass 2: Reserve Plantilla Slots for all valid rows ────────────────────
  -- Unchanged from 20262606000002. Slot reservation logic is unaffected by
  -- the removal of STORE/POSITION/EMPLOYMENT_TYPE from user input.
  FOREACH v_reserve_vcode IN ARRAY v_valid_vcodes
  LOOP
    v_slot_id     := NULL;
    v_slot_result := NULL;

    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE legacy_vcode = v_reserve_vcode
    FOR UPDATE;

    IF v_slot_id IS NULL THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" Plantilla slot not found at reservation time. '
            'The slot may have been archived between validation and submission. Please resubmit.',
            v_reserve_vcode
          )
        ))
      WHERE batch_id = v_batch_id
        AND vcode    = v_reserve_vcode
        AND validation_status = 'valid';

      v_valid   := v_valid   - 1;
      v_blocked := v_blocked + 1;
      CONTINUE;
    END IF;

    SELECT public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_performed_by => v_profile_id,
      p_remarks      => 'import_batch:' || v_batch_id::TEXT
    ) INTO v_slot_result;

    IF (v_slot_result->>'status') = 'blocked' THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" slot could not be reserved — slot state changed between '
            'validation and submission (%s). Please resubmit.',
            v_reserve_vcode,
            COALESCE(v_slot_result->>'blocked_reason', 'state transition blocked')
          )
        ))
      WHERE batch_id = v_batch_id
        AND vcode    = v_reserve_vcode
        AND validation_status = 'valid';

      v_valid   := v_valid   - 1;
      v_blocked := v_blocked + 1;
    END IF;
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


-- ============================================================
-- §2  approve_hr_emploc_import — derive store_name and position
--     from slot at approval time (not from user-uploaded row values)
-- ============================================================

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

    -- ── Re-verify Plantilla Slot — capture store_id and position for HR Emploc INSERT ──
    -- STORE and POSITION are now derived from the slot at approval time, not from
    -- user-uploaded values.
    v_slot_id            := NULL;
    v_slot_status_rc     := NULL;
    v_slot_occupant_rc   := NULL;
    v_occupant_label     := NULL;
    v_slot_store_id_rc   := NULL;
    v_slot_position_rc   := NULL;
    v_slot_store_name_rc := NULL;

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

    -- ── Guard: prevent duplicate slot occupancy (race between two approvals) ─
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

    -- ── Resolve store_name from slot (not from user-uploaded STORE column) ───
    SELECT s.store_name INTO v_slot_store_name_rc
    FROM public.stores s WHERE s.id = v_slot_store_id_rc;

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
      import_batch_id,
      slot_id
    ) VALUES (
      v_full_name,
      v_row.vcode,
      COALESCE(v_account_name, v_row.account_name),
      v_account_id,
      COALESCE(v_slot_position_rc, ''),   -- from slot, not user upload
      v_slot_store_name_rc,               -- from slot, not user upload
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


-- ============================================================
-- §3  GRANTs (preserve existing grants)
-- ============================================================

GRANT EXECUTE ON FUNCTION public.submit_hr_emploc_import(text, uuid, jsonb)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_hr_emploc_import(uuid)               TO authenticated;


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — Template: upload file with only GROUP, ACCOUNT, VCODE, LAST_NAME, FIRST_NAME,
--   MIDDLE_NAME, DATE_HIRED columns. No STORE/POSITION/EMPLOYMENT_TYPE columns.
--   Expected: parses successfully; submits OK.
--
-- V2 — MIDDLE_NAME blank:
--   Expected: blocked — "Middle Name is required. Use 'NA' if the employee has no middle name."
--
-- V3 — MIDDLE_NAME = 'N/A':
--   Expected: blocked — "Use 'NA' instead of 'N/A' for employees without a middle name."
--
-- V4 — MIDDLE_NAME = 'n/a':
--   Expected: blocked (same message as V3).
--
-- V5 — MIDDLE_NAME = 'A' (single letter):
--   Expected: blocked — "Middle Name must contain at least two characters..."
--
-- V6 — MIDDLE_NAME = '-':
--   Expected: blocked — "Middle Name is invalid..."
--
-- V7 — MIDDLE_NAME = 'NA':
--   Expected: valid; stored as 'NA'.
--
-- V8 — MIDDLE_NAME = 'na':
--   Expected: valid; normalized to 'NA'; stored as 'NA'.
--
-- V9 — MIDDLE_NAME = 'Dela Cruz':
--   Expected: valid; stored as 'Dela Cruz'.
--
-- V10 — After submit: hr_emploc_import_rows.store_name = slot's store_name (not NULL, not user input).
--   SELECT ir.store_name, ir.position, ir.employment_type
--   FROM public.hr_emploc_import_rows ir WHERE ir.batch_id = '<batch_id>';
--   Expected: store_name = derived from slot; position = from slot; employment_type = NULL.
--
-- V11 — After approve: hr_emploc.store_name and position derived from slot.
--   SELECT h.store_name, h.position FROM public.hr_emploc WHERE import_batch_id = '<batch_id>';
--   Expected: values match plantilla_slots fields, not any user-uploaded column.
--
-- V12 — Slot-first VCode validation unchanged:
--   archived/closed/occupied/group-mismatch paths produce the same error messages as before.
-- ============================================================

COMMIT;
