-- Migration: 20262606000000_hr_emploc_import_fix_fk_and_groups
-- Created: 2026-06-26
-- Purpose: Fix hr_emploc_import_batches FK violation (uploaded_by/approved_by/rejected_by/rolled_back_by
--          must use users_profile.id via get_current_profile_id(), not auth.uid()); add
--          get_hr_emploc_import_groups() RPC that returns only cencom_scope=true operational groups.
--
-- Smoke Tests:
-- S1: SA submits import → batch created with uploaded_by = users_profile.id (no FK violation)
-- S2: SA approves batch → hr_emploc rows created with created_by = users_profile.id (no FK violation)
-- S3: SA rejects batch → batch rejected_by = users_profile.id (no FK violation)
-- S4: SA rolls back approved batch → rolled_back_by = users_profile.id (no FK violation)
-- S5: User with no users_profile row → submit raises clean error (not a PG FK exception)
-- S6: get_hr_emploc_import_groups() for SA → returns only cencom_scope=true groups (no Global HQ)
-- S7: get_hr_emploc_import_groups() for scoped user → returns their groups filtered to cencom_scope=true

BEGIN;

-- ── 1. get_hr_emploc_import_groups ────────────────────────────────────────────
-- Returns only operational (cencom_scope = true) groups visible to the caller.
-- SA/HA: all operational groups. Scoped users: their assigned groups that are operational.
CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_groups()
RETURNS TABLE (
  group_id   UUID,
  group_name TEXT,
  sort_order INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.' USING ERRCODE = 'P0001';
  END IF;

  IF i_have_full_access() THEN
    RETURN QUERY
    SELECT
      g.id,
      g.group_name,
      ROW_NUMBER() OVER (ORDER BY g.group_code)::INTEGER
    FROM public.groups g
    WHERE COALESCE(g.cencom_scope, false) = true
    ORDER BY g.group_code;
    RETURN;
  END IF;

  -- Scoped users: their assigned groups that are operational
  RETURN QUERY
  SELECT DISTINCT
    g.id,
    g.group_name,
    ROW_NUMBER() OVER (ORDER BY g.group_code)::INTEGER
  FROM public.user_scopes us
  JOIN public.groups g ON g.id = us.group_id
  WHERE us.user_id = v_profile_id
    AND COALESCE(g.cencom_scope, false) = true
  ORDER BY g.group_code;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_hr_emploc_import_groups() TO authenticated;

-- ── 2. submit_hr_emploc_import (FK fix — use get_current_profile_id()) ────────
-- Identical to v2 (20262506000001) except:
--   v_profile_id resolved via get_current_profile_id() and used for uploaded_by.
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
  v_caller_id       UUID;  -- auth.users.id — for auth session check only
  v_profile_id      UUID;  -- users_profile.id — for FK columns
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

  -- Resolve users_profile.id for FK columns
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
    v_profile_id, now()  -- v_profile_id = users_profile.id (FK-safe)
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

      -- 1. VCode existence + group + store match
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
        IF v_vac_group_id IS DISTINCT FROM p_group_id THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" does not belong to the selected group.', v_vcode)
          ));
          v_status := 'blocked';
        END IF;

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

      -- 3. VCode already active in hr_emploc
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
          v_status    := 'blocked';
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

-- ── 3. approve_hr_emploc_import (FK fix) ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.approve_hr_emploc_import(p_batch_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id    UUID;  -- auth.users.id — session check only
  v_profile_id   UUID;  -- users_profile.id — for FK columns
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
      v_profile_id,  -- users_profile.id (FK-safe)
      v_profile_id,  -- users_profile.id (FK-safe)
      p_batch_id
    ) RETURNING id INTO v_hr_id;

    UPDATE public.hr_emploc_import_rows
    SET hr_emploc_id = v_hr_id
    WHERE id = v_row.id;

    v_created := v_created + 1;
  END LOOP;

  UPDATE public.hr_emploc_import_batches SET
    status       = 'approved',
    approved_by  = v_profile_id,  -- users_profile.id (FK-safe)
    approved_at  = now(),
    created_rows = v_created
  WHERE id = p_batch_id;

  RETURN json_build_object('records_created', v_created);
END;
$$;

-- ── 4. reject_hr_emploc_import (FK fix) ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_hr_emploc_import(
  p_batch_id    UUID,
  p_reason_code TEXT,
  p_reason_note TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id  UUID;  -- auth.users.id — session check only
  v_profile_id UUID;  -- users_profile.id — for FK columns
  v_status     TEXT;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can reject HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_reason_code IS NULL OR TRIM(p_reason_code) = '' THEN
    RAISE EXCEPTION 'Rejection reason code is required' USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO v_status
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;
  IF v_status <> 'pending_approval' THEN
    RAISE EXCEPTION 'Only pending_approval batches can be rejected (current status: %)', v_status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.hr_emploc_import_batches SET
    status                = 'rejected',
    rejected_by           = v_profile_id,  -- users_profile.id (FK-safe)
    rejected_at           = now(),
    rejection_reason_code = p_reason_code,
    rejection_reason_note = p_reason_note
  WHERE id = p_batch_id;
END;
$$;

-- ── 5. rollback_hr_emploc_import (FK fix) ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rollback_hr_emploc_import(
  p_batch_id UUID,
  p_reason   TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id    UUID;  -- auth.users.id — session check only
  v_profile_id   UUID;  -- users_profile.id — for FK columns
  v_batch        public.hr_emploc_import_batches%ROWTYPE;
  v_moved_count  INTEGER;
  v_removed      INTEGER;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can roll back HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'Rollback reason must be at least 10 characters'
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
    WHEN 'rolled_back'      THEN RAISE EXCEPTION 'This batch has already been rolled back' USING ERRCODE = 'P0001';
    WHEN 'rejected'         THEN RAISE EXCEPTION 'Rejected batches cannot be rolled back — no records were created' USING ERRCODE = 'P0001';
    WHEN 'pending_approval' THEN RAISE EXCEPTION 'Pending batches cannot be rolled back — reject instead' USING ERRCODE = 'P0001';
    ELSE NULL;
  END CASE;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'Only approved batches can be rolled back' USING ERRCODE = 'P0001';
  END IF;

  SELECT COUNT(*) INTO v_moved_count
  FROM public.hr_emploc
  WHERE import_batch_id = p_batch_id
    AND deleted_at IS NULL
    AND status = 'Moved to Plantilla';

  IF v_moved_count > 0 THEN
    RAISE EXCEPTION
      'Rollback blocked: % record(s) from this batch have already been moved to Plantilla. Remove them from Plantilla first.',
      v_moved_count
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.hr_emploc
  SET deleted_at = now()
  WHERE import_batch_id = p_batch_id
    AND deleted_at IS NULL;

  GET DIAGNOSTICS v_removed = ROW_COUNT;

  UPDATE public.hr_emploc_import_batches SET
    status          = 'rolled_back',
    rolled_back_by  = v_profile_id,  -- users_profile.id (FK-safe)
    rolled_back_at  = now(),
    rollback_reason = TRIM(p_reason)
  WHERE id = p_batch_id;

  RETURN json_build_object('records_removed', v_removed);
END;
$$;

COMMIT;
