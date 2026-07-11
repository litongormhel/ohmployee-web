-- Migration: 20262506000001_hr_emploc_import_template_v2
-- Created: 2026-06-25
-- Purpose: Update HR Emploc import to v2 template (add VCode+Store required, fix group-scope
--          parsing, add DB-level VCode/Account/Store validation, fix get_hr_emploc_import_rows
--          to include vcode output column)
--
-- Smoke Tests:
-- S1:  Row with valid GROUP, ACCOUNT, VCODE, STORE, names, DATE_HIRED → validation_status = 'valid'
-- S2:  Row with VCode that does not exist in vacancies → blocked (vcode_not_found)
-- S3:  Row where VCode exists but group_id ≠ selected group → blocked (vcode_wrong_group)
-- S4:  Row where VCode store_name ≠ STORE column → blocked (vcode_store_mismatch)
-- S5:  Row where ACCOUNT not found in group → blocked (account_not_found)
-- S6:  Row with VCode already active in hr_emploc → blocked (vcode_already_in_use)
-- S7:  Two rows with same VCode in one file → second row blocked (vcode_dup_in_file)
-- S8:  Row with MIDDLE_NAME blank → blocked (middle_name_required)
-- S9:  Approve batch → hr_emploc.vcode = row.vcode (not NULL)
-- S10: get_hr_emploc_import_rows returns vcode column correctly

BEGIN;

-- ── 1. Add vcode column to hr_emploc_import_rows ─────────────────────────────
ALTER TABLE public.hr_emploc_import_rows
  ADD COLUMN IF NOT EXISTS vcode TEXT;

-- ── 2. submit_hr_emploc_import (v2 — new headers + DB validation) ─────────────
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
  v_caller_id       UUID;
  v_batch_id        UUID;
  v_group_name      TEXT;
  v_row             JSONB;
  v_row_number      INTEGER := 0;
  v_total           INTEGER := 0;
  v_valid           INTEGER := 0;
  v_blocked         INTEGER := 0;
  v_duplicate       INTEGER := 0;
  -- per-row values
  v_last_name       TEXT;
  v_first_name      TEXT;
  v_middle_name     TEXT;
  v_account_name    TEXT;
  v_store           TEXT;
  v_vcode           TEXT;
  v_date_hired      DATE;
  v_position        TEXT;
  v_employment_type TEXT;
  v_row_group       TEXT;
  -- vacancy lookup
  v_vac_group_id    UUID;
  v_vac_store_name  TEXT;
  v_vac_account_id  UUID;
  v_acct_id         UUID;
  -- validation
  v_errors          JSONB;
  v_status          TEXT;
  v_identity        TEXT;
  -- de-dup tracking
  v_seen_identities TEXT[]  := ARRAY[]::TEXT[];
  v_seen_vcodes     TEXT[]  := ARRAY[]::TEXT[];
  v_seen_groups     TEXT[]  := ARRAY[]::TEXT[];
  v_multi_group     BOOLEAN := FALSE;
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
    v_caller_id, now()
  ) RETURNING id INTO v_batch_id;

  -- ── Process rows ──────────────────────────────────────────────────────────
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_row_number      := v_row_number + 1;
    v_total           := v_total + 1;
    v_errors          := '[]'::jsonb;
    v_status          := 'valid';

    -- Extract all fields (XLSX sends the exact column header as the key)
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

      -- 1. VCode existence + group + store match (single lookup)
      SELECT va.group_id, va.store_name, va.account_id
        INTO v_vac_group_id, v_vac_store_name, v_vac_account_id
      FROM public.vacancies va
      WHERE va.vcode = v_vcode
        AND va.deleted_at IS NULL
        AND (va.is_archived IS NULL OR va.is_archived = false)
      LIMIT 1;

      IF NOT FOUND THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE', 'msg', format('VCode "%s" not found or is archived.', v_vcode)
        ));
        v_status := 'blocked';
      ELSE
        -- VCode must belong to the selected group
        IF v_vac_group_id IS DISTINCT FROM p_group_id THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" does not belong to the selected group.', v_vcode)
          ));
          v_status := 'blocked';
        END IF;

        -- VCode store_name must match STORE column
        IF v_vac_store_name IS NULL
           OR UPPER(TRIM(v_vac_store_name)) <> UPPER(TRIM(v_store))
        THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'STORE',
            'msg', format(
              'VCode "%s" is for store "%s", but STORE column says "%s".',
              v_vcode,
              COALESCE(v_vac_store_name, '(none)'),
              v_store
            )
          ));
          v_status := 'blocked';
        END IF;
      END IF;

      -- 2. Account must belong to the selected group
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

      -- 3. VCode already active in hr_emploc (not yet rolled back or deleted)
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

      -- 4. In-file VCode duplicate
      IF v_status = 'valid' THEN
        IF UPPER(v_vcode) = ANY(v_seen_vcodes) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" appears more than once in this file.', v_vcode)
          ));
          v_status  := 'blocked';
          v_duplicate := v_duplicate + 1;
        ELSE
          v_seen_vcodes := array_append(v_seen_vcodes, UPPER(v_vcode));
        END IF;
      END IF;

      -- 5. In-file name duplicate
      IF v_status = 'valid' THEN
        v_identity := UPPER(COALESCE(v_last_name,''))  || '|'
                   || UPPER(COALESCE(v_first_name,'')) || '|'
                   || UPPER(COALESCE(v_middle_name,''))|| '|'
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

      -- 6. DB name+account+date duplicate check
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

-- ── 3. get_hr_emploc_import_rows (add vcode column) ──────────────────────────
-- Must drop first: adding a return column changes the function signature.
DROP FUNCTION IF EXISTS public.get_hr_emploc_import_rows(UUID);
CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_rows(p_batch_id UUID)
RETURNS TABLE (
  id                UUID,
  batch_id          UUID,
  row_number        INTEGER,
  group_name        TEXT,
  account_name      TEXT,
  last_name         TEXT,
  first_name        TEXT,
  middle_name       TEXT,
  date_hired        DATE,
  position_name     TEXT,
  store_name        TEXT,
  employment_type   TEXT,
  vcode             TEXT,
  validation_status TEXT,
  validation_errors JSONB,
  hr_emploc_id      UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.hr_emploc_import_batches b
    WHERE b.id = p_batch_id
      AND b.deleted_at IS NULL
      AND (
        i_have_full_access()
        OR b.group_id IN (
          SELECT DISTINCT a.group_id FROM public.accounts a
          WHERE a.id::text = ANY(get_my_allowed_accounts())
        )
      )
  ) THEN
    RAISE EXCEPTION 'Batch not found or access denied' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT
    r.id, r.batch_id, r.row_number,
    r.group_name, r.account_name, r.last_name, r.first_name, r.middle_name,
    r.date_hired, r.position AS position_name, r.store_name, r.employment_type,
    r.vcode,
    r.validation_status, r.validation_errors, r.hr_emploc_id
  FROM public.hr_emploc_import_rows r
  WHERE r.batch_id = p_batch_id
  ORDER BY r.row_number;
END;
$$;

-- ── 4. approve_hr_emploc_import (use vcode from row, not NULL) ───────────────
CREATE OR REPLACE FUNCTION public.approve_hr_emploc_import(p_batch_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id    UUID;
  v_batch        public.hr_emploc_import_batches%ROWTYPE;
  v_row          public.hr_emploc_import_rows%ROWTYPE;
  v_account_id   UUID;
  v_account_name TEXT;
  v_hr_id        UUID;
  v_full_name    TEXT;
  v_created      INTEGER := 0;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can approve HR Emploc imports'
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
    WHEN 'approved'      THEN RAISE EXCEPTION 'This batch has already been approved' USING ERRCODE = 'P0001';
    WHEN 'rejected'      THEN RAISE EXCEPTION 'Rejected batches cannot be approved' USING ERRCODE = 'P0001';
    WHEN 'rolled_back'   THEN RAISE EXCEPTION 'Rolled-back batches cannot be re-approved' USING ERRCODE = 'P0001';
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
    -- Resolve account
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

    -- Re-verify VCode still exists and is not yet taken
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies
      WHERE vcode = v_row.vcode AND deleted_at IS NULL AND (is_archived IS NULL OR is_archived = false)
    ) THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" no longer exists at approval time.', v_row.vcode)
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- Build applicant_name
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
      v_row.vcode,                                    -- linked vacancy VCode
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
      v_caller_id,
      v_caller_id,
      p_batch_id
    ) RETURNING id INTO v_hr_id;

    UPDATE public.hr_emploc_import_rows
    SET hr_emploc_id = v_hr_id
    WHERE id = v_row.id;

    v_created := v_created + 1;
  END LOOP;

  UPDATE public.hr_emploc_import_batches SET
    status       = 'approved',
    approved_by  = v_caller_id,
    approved_at  = now(),
    created_rows = v_created
  WHERE id = p_batch_id;

  RETURN json_build_object('records_created', v_created);
END;
$$;

COMMIT;
