-- Migration: 20262606000006_hr_emploc_import_name_char_validation
-- Created: 2026-06-26
-- Prompt ID: ohm#6t9v3a1k (continuation — name character validation)
-- Purpose: Block invalid special characters in LAST_NAME, FIRST_NAME, and MIDDLE_NAME
--          during HR Emploc Import submission. Allowed: letters, digits, space,
--          apostrophe ('), hyphen (-), period (.), Ñ, ñ.
--
-- Root cause:
--   submit_hr_emploc_import had no character-set validation on name fields.
--   Values like "JU@N", "PEDR#O", "MAR!A", "DELA*CRUZ" passed client presence checks
--   and were staged without error, causing downstream data quality issues.
--
-- Changes vs 20262606000003 (submit_hr_emploc_import only):
--   1. After LAST_NAME IS NULL check: add char check — blocks if name contains
--      a character not in [A-Za-z0-9 '.Ññ-]. Error: 'LAST_NAME contains invalid characters...'
--   2. After FIRST_NAME IS NULL check: same char check for FIRST_NAME.
--   3. In MIDDLE_NAME ELSIF chain: add char check between the 'NA' normalization
--      branch and the single-letter length branch.
--      Char check only runs for values that passed blank/N/A/placeholder/NA branches.
--
-- No schema changes. No approve/reject/rollback/fn_set_slot_status changes.
-- No Flutter changes (Dart-side char validation added separately in same task).
-- Mirrors client-side _kValidNameCharsPattern = RegExp(r"^[A-Za-z0-9 '.\-Ññ]+$").
--
-- Smoke Tests:
-- S1: Submit row with LAST_NAME='JU@N'     → blocked: 'LAST_NAME contains invalid characters...'
-- S2: Submit row with FIRST_NAME='MAR!A'   → blocked: 'FIRST_NAME contains invalid characters...'
-- S3: Submit row with MIDDLE_NAME='SANC@HEZ' → blocked: 'MIDDLE_NAME contains invalid characters...'
-- S4: Submit row with LAST_NAME='PEÑA'     → valid (Ñ allowed)
-- S5: Submit row with LAST_NAME='MUÑOZ'    → valid (Ñ allowed)
-- S6: Submit row with LAST_NAME="O'CONNOR" → valid (apostrophe allowed)
-- S7: Submit row with FIRST_NAME='ANNE-MARIE' → valid (hyphen allowed)
-- S8: Existing MIDDLE_NAME rules unchanged (blank/N/A/placeholder/NA/single-letter)
-- S9: MIDDLE_NAME='DELA*CRUZ' (non-placeholder, non-NA) → char error, not length error

BEGIN;

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

    -- ── LAST_NAME character check ──────────────────────────────────────────
    -- Regex: any character NOT in [A-Za-z0-9 space apostrophe period Ñ ñ hyphen]
    IF v_last_name IS NOT NULL AND v_last_name ~ '[^A-Za-z0-9 ''.Ññ-]' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'LAST_NAME',
        'msg', 'LAST_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe (''), period (.), and Ñ/ñ are allowed.'
      ));
      v_status := 'blocked';
    END IF;

    -- ── FIRST_NAME character check ─────────────────────────────────────────
    IF v_first_name IS NOT NULL AND v_first_name ~ '[^A-Za-z0-9 ''.Ññ-]' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'FIRST_NAME',
        'msg', 'FIRST_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe (''), period (.), and Ñ/ñ are allowed.'
      ));
      v_status := 'blocked';
    END IF;

    -- ── MIDDLE_NAME validation (5 existing rules + new char check) ────────
    IF LENGTH(v_middle_name) = 0 THEN
      -- Rule 1: Blank
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name is required. Use ''NA'' if the employee has no middle name.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF UPPER(v_middle_name) ~ '^N\s*/\s*A$' THEN
      -- Rule 2: N/A variant (any case/spacing)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Use ''NA'' instead of ''N/A'' for employees without a middle name.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF v_middle_name = ANY(ARRAY['-', '.', '?']) THEN
      -- Rule 3: Single-character placeholder — specific message (before generic char check)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name is invalid. Use a valid middle name or ''NA'' if none exists.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF UPPER(v_middle_name) = 'NA' THEN
      -- Rule 4: Normalize NA to uppercase
      v_middle_name := 'NA';

    ELSIF v_middle_name ~ '[^A-Za-z0-9 ''.Ññ-]' THEN
      -- Rule 5 (new): Invalid character in name (only reached for multi-char non-NA values)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'MIDDLE_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe (''), period (.), and Ñ/ñ are allowed.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF LENGTH(v_middle_name) < 2 THEN
      -- Rule 6: Single letter (1 char not caught by placeholder check)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name must contain at least two characters, or use ''NA'' if none exists.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    END IF;
    -- v_middle_name is now either NULL (blocked), 'NA', or a valid ≥2-char clean name.

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

GRANT EXECUTE ON FUNCTION public.submit_hr_emploc_import(text, uuid, jsonb) TO authenticated;

COMMIT;
