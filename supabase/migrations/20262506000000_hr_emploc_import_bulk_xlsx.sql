-- Migration: 20262506000000_hr_emploc_import_bulk_xlsx
-- Created: 2026-06-25
-- Purpose: Add HR Emploc bulk XLSX import with HA/SA approval, group-scoped validation, and rollback support
--
-- Smoke Tests:
-- S1:  SA calls submit_hr_emploc_import with valid rows → batch created, pending_approval
-- S2:  Row with duplicate name+account+hired_date → validation_status = 'blocked'
-- S3:  Rows containing multiple groups → all rows blocked (cross_group error)
-- S4:  Missing LAST_NAME or ACCOUNT_NAME → blocked with field error
-- S5:  Encoder calls approve_hr_emploc_import → error (level < 90)
-- S6:  HA calls approve_hr_emploc_import → hr_emploc rows created, batch approved
-- S7:  HA calls approve_hr_emploc_import again → error (already approved)
-- S8:  HA calls reject_hr_emploc_import on pending batch → batch rejected
-- S9:  HA calls approve_hr_emploc_import on rejected batch → error
-- S10: HA calls rollback_hr_emploc_import on approved batch → hr_emploc rows soft-deleted
-- S11: HA calls rollback_hr_emploc_import again → error (already rolled back)
-- S12: rollback only removes imported rows; manually created hr_emploc rows unchanged
-- S13: plantilla table row count unchanged after approve + rollback cycle
-- S14: vacancies table row count unchanged after full import cycle

BEGIN;

-- ── 1. Add import_batch_id to hr_emploc for rollback traceability ─────────────
ALTER TABLE public.hr_emploc
  ADD COLUMN IF NOT EXISTS import_batch_id UUID;

-- ── 2. Create hr_emploc_import_batches ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hr_emploc_import_batches (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  file_name             TEXT        NOT NULL,
  status                TEXT        NOT NULL DEFAULT 'pending_approval'
                          CHECK (status IN ('pending_approval','approved','rejected','rolled_back')),
  group_id              UUID        NOT NULL REFERENCES public.groups(id),
  group_name            TEXT,
  -- summary counts (set on submit, updated on approve)
  total_rows            INTEGER     NOT NULL DEFAULT 0,
  valid_rows            INTEGER     NOT NULL DEFAULT 0,
  blocked_rows          INTEGER     NOT NULL DEFAULT 0,
  duplicate_rows        INTEGER     NOT NULL DEFAULT 0,
  created_rows          INTEGER     NOT NULL DEFAULT 0,
  -- audit trail
  uploaded_by           UUID        REFERENCES public.users_profile(id),
  uploaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_by           UUID        REFERENCES public.users_profile(id),
  approved_at           TIMESTAMPTZ,
  rejected_by           UUID        REFERENCES public.users_profile(id),
  rejected_at           TIMESTAMPTZ,
  rejection_reason_code TEXT,
  rejection_reason_note TEXT,
  rolled_back_by        UUID        REFERENCES public.users_profile(id),
  rolled_back_at        TIMESTAMPTZ,
  rollback_reason       TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at            TIMESTAMPTZ
);

ALTER TABLE public.hr_emploc_import_batches ENABLE ROW LEVEL SECURITY;

-- Scoped SELECT: group member or full access
DROP POLICY IF EXISTS "hr_emploc_import_batches_select" ON public.hr_emploc_import_batches;
CREATE POLICY "hr_emploc_import_batches_select"
  ON public.hr_emploc_import_batches FOR SELECT TO authenticated
  USING (
    i_have_full_access()
    OR group_id IN (
      SELECT DISTINCT a.group_id FROM public.accounts a
      WHERE a.id::text = ANY(get_my_allowed_accounts())
    )
  );

-- Deny direct DML — all mutations go through SECURITY DEFINER RPCs
DROP POLICY IF EXISTS "hr_emploc_import_batches_no_insert" ON public.hr_emploc_import_batches;
CREATE POLICY "hr_emploc_import_batches_no_insert"
  ON public.hr_emploc_import_batches FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS "hr_emploc_import_batches_no_update" ON public.hr_emploc_import_batches;
CREATE POLICY "hr_emploc_import_batches_no_update"
  ON public.hr_emploc_import_batches FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS "hr_emploc_import_batches_no_delete" ON public.hr_emploc_import_batches;
CREATE POLICY "hr_emploc_import_batches_no_delete"
  ON public.hr_emploc_import_batches FOR DELETE TO authenticated USING (false);

-- ── 3. Create hr_emploc_import_rows ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hr_emploc_import_rows (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id          UUID        NOT NULL REFERENCES public.hr_emploc_import_batches(id),
  row_number        INTEGER     NOT NULL,
  -- identity fields (from XLSX — stored in canonical case)
  group_name        TEXT,
  account_name      TEXT,
  last_name         TEXT,
  first_name        TEXT,
  middle_name       TEXT,
  date_hired        DATE,
  -- optional fields
  position          TEXT,
  store_name        TEXT,
  employment_type   TEXT,
  -- validation outcome
  validation_status TEXT        NOT NULL DEFAULT 'valid'
                      CHECK (validation_status IN ('valid','blocked')),
  validation_errors JSONB       NOT NULL DEFAULT '[]'::jsonb,
  -- linked hr_emploc record (populated on approval)
  hr_emploc_id      UUID        REFERENCES public.hr_emploc(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.hr_emploc_import_rows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hr_emploc_import_rows_select" ON public.hr_emploc_import_rows;
CREATE POLICY "hr_emploc_import_rows_select"
  ON public.hr_emploc_import_rows FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.hr_emploc_import_batches b
      WHERE b.id = batch_id
        AND b.deleted_at IS NULL
        AND (
          i_have_full_access()
          OR b.group_id IN (
            SELECT DISTINCT a.group_id FROM public.accounts a
            WHERE a.id::text = ANY(get_my_allowed_accounts())
          )
        )
    )
  );

DROP POLICY IF EXISTS "hr_emploc_import_rows_no_insert" ON public.hr_emploc_import_rows;
CREATE POLICY "hr_emploc_import_rows_no_insert"
  ON public.hr_emploc_import_rows FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS "hr_emploc_import_rows_no_update" ON public.hr_emploc_import_rows;
CREATE POLICY "hr_emploc_import_rows_no_update"
  ON public.hr_emploc_import_rows FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS "hr_emploc_import_rows_no_delete" ON public.hr_emploc_import_rows;
CREATE POLICY "hr_emploc_import_rows_no_delete"
  ON public.hr_emploc_import_rows FOR DELETE TO authenticated USING (false);

-- ── 4. Indexes ────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_hr_emploc_import_batch_id
  ON public.hr_emploc (import_batch_id)
  WHERE import_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_hr_emploc_import_rows_batch
  ON public.hr_emploc_import_rows (batch_id);

CREATE INDEX IF NOT EXISTS idx_hr_emploc_import_batches_group
  ON public.hr_emploc_import_batches (group_id)
  WHERE deleted_at IS NULL;

-- ── 5a. submit_hr_emploc_import ───────────────────────────────────────────────
-- Validates and stages rows; creates batch in pending_approval status.
-- Allowed: encoder (level ≥ 50), headAdmin, superAdmin.
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
  -- per-row extracted values
  v_last_name       TEXT;
  v_first_name      TEXT;
  v_middle_name     TEXT;
  v_account_name    TEXT;
  v_date_hired      DATE;
  v_position        TEXT;
  v_store_name      TEXT;
  v_employment_type TEXT;
  v_row_group       TEXT;
  -- validation state
  v_errors          JSONB;
  v_status          TEXT;
  v_identity        TEXT;
  -- de-dup tracking
  v_seen_identities TEXT[]   := ARRAY[]::TEXT[];
  v_seen_groups     TEXT[]   := ARRAY[]::TEXT[];
  v_multi_group     BOOLEAN  := FALSE;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions to submit HR Emploc import (encoder or above required)'
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
    v_row_group := UPPER(TRIM(COALESCE(v_row->>'GROUP_NAME', '')));
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

    -- Extract fields (XLSX sends uppercase header keys)
    v_last_name       := NULLIF(TRIM(COALESCE(v_row->>'LAST_NAME', '')), '');
    v_first_name      := NULLIF(TRIM(COALESCE(v_row->>'FIRST_NAME', '')), '');
    v_middle_name     := NULLIF(TRIM(COALESCE(v_row->>'MIDDLE_NAME', '')), '');
    v_account_name    := NULLIF(TRIM(COALESCE(v_row->>'ACCOUNT_NAME', '')), '');
    v_position        := NULLIF(TRIM(COALESCE(v_row->>'POSITION', '')), '');
    v_store_name      := NULLIF(TRIM(COALESCE(v_row->>'STORE_NAME', '')), '');
    v_employment_type := NULLIF(TRIM(COALESCE(v_row->>'EMPLOYMENT_TYPE', '')), '');
    v_row_group       := NULLIF(TRIM(COALESCE(v_row->>'GROUP_NAME', '')), '');

    -- Parse DATE_HIRED
    v_date_hired := NULL;
    BEGIN
      v_date_hired := (v_row->>'DATE_HIRED')::DATE;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors
        || jsonb_build_array(jsonb_build_object(
          'field', 'DATE_HIRED',
          'msg', 'Invalid date format — use YYYY-MM-DD.'
        ));
      v_status := 'blocked';
    END;

    -- Required fields
    IF v_last_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','LAST_NAME','msg','Last name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_first_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','FIRST_NAME','msg','First name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_account_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','ACCOUNT_NAME','msg','Account name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_row_group IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','GROUP_NAME','msg','Group name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_date_hired IS NULL AND v_status = 'valid' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','DATE_HIRED','msg','Date hired is required.'));
      v_status := 'blocked';
    END IF;

    -- Cross-group check
    IF v_multi_group THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'GROUP_NAME',
        'msg', 'Upload blocked: file contains rows from multiple groups. One group per upload only.'
      ));
      v_status := 'blocked';
    ELSIF v_row_group IS NOT NULL
      AND UPPER(v_row_group) <> UPPER(v_group_name)
    THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'GROUP_NAME',
        'msg', format('Group "%s" does not match selected group "%s".', v_row_group, v_group_name)
      ));
      v_status := 'blocked';
    END IF;

    -- In-file duplicate detection
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

    -- DB duplicate check: existing HR Emploc with same name + account + hired_date
    IF v_status = 'valid' THEN
      IF EXISTS (
        SELECT 1
        FROM public.hr_emploc h
        JOIN public.accounts a ON a.id = h.account_id
        WHERE h.deleted_at IS NULL
          AND a.group_id = p_group_id
          AND UPPER(TRIM(a.account_name)) = UPPER(v_account_name)
          AND h.hired_date = v_date_hired
          AND UPPER(TRIM(h.applicant_name)) = UPPER(TRIM(
            CASE WHEN v_middle_name IS NOT NULL
              THEN v_first_name || ' ' || v_middle_name || ' ' || v_last_name
              ELSE v_first_name || ' ' || v_last_name
            END
          ))
      ) THEN
        v_errors  := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'identity',
          'msg', 'Duplicate: HR Emploc record with this name and date hired already exists in the system.'
        ));
        v_status    := 'blocked';
        v_duplicate := v_duplicate + 1;
      END IF;
    END IF;

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
      date_hired, position, store_name, employment_type,
      validation_status, validation_errors
    ) VALUES (
      v_batch_id, v_row_number,
      v_row_group, v_account_name, v_last_name, v_first_name, v_middle_name,
      v_date_hired, v_position, v_store_name, v_employment_type,
      v_status, v_errors
    );
  END LOOP;

  -- Update batch summary counts
  UPDATE public.hr_emploc_import_batches SET
    total_rows    = v_total,
    valid_rows    = v_valid,
    blocked_rows  = v_blocked,
    duplicate_rows = v_duplicate
  WHERE id = v_batch_id;

  RETURN json_build_object('batch_id', v_batch_id);
END;
$$;

-- ── 5b. get_hr_emploc_import_batches ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_batches()
RETURNS TABLE (
  id                    UUID,
  file_name             TEXT,
  status                TEXT,
  group_id              UUID,
  group_name            TEXT,
  total_rows            INTEGER,
  valid_rows            INTEGER,
  blocked_rows          INTEGER,
  duplicate_rows        INTEGER,
  created_rows          INTEGER,
  uploaded_by           UUID,
  uploaded_by_name      TEXT,
  uploaded_at           TIMESTAMPTZ,
  approved_by           UUID,
  approved_by_name      TEXT,
  approved_at           TIMESTAMPTZ,
  rejected_by           UUID,
  rejected_by_name      TEXT,
  rejected_at           TIMESTAMPTZ,
  rejection_reason_code TEXT,
  rejection_reason_note TEXT,
  rolled_back_by        UUID,
  rolled_back_by_name   TEXT,
  rolled_back_at        TIMESTAMPTZ,
  rollback_reason       TEXT,
  created_at            TIMESTAMPTZ
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

  RETURN QUERY
  SELECT
    b.id,
    b.file_name,
    b.status,
    b.group_id,
    b.group_name,
    b.total_rows,
    b.valid_rows,
    b.blocked_rows,
    b.duplicate_rows,
    b.created_rows,
    b.uploaded_by,
    up.full_name AS uploaded_by_name,
    b.uploaded_at,
    b.approved_by,
    ap.full_name AS approved_by_name,
    b.approved_at,
    b.rejected_by,
    rp.full_name AS rejected_by_name,
    b.rejected_at,
    b.rejection_reason_code,
    b.rejection_reason_note,
    b.rolled_back_by,
    rbp.full_name AS rolled_back_by_name,
    b.rolled_back_at,
    b.rollback_reason,
    b.created_at
  FROM public.hr_emploc_import_batches b
  LEFT JOIN public.users_profile up  ON up.id  = b.uploaded_by
  LEFT JOIN public.users_profile ap  ON ap.id  = b.approved_by
  LEFT JOIN public.users_profile rp  ON rp.id  = b.rejected_by
  LEFT JOIN public.users_profile rbp ON rbp.id = b.rolled_back_by
  WHERE b.deleted_at IS NULL
    AND (
      i_have_full_access()
      OR b.group_id IN (
        SELECT DISTINCT a.group_id FROM public.accounts a
        WHERE a.id::text = ANY(get_my_allowed_accounts())
      )
    )
  ORDER BY b.created_at DESC;
END;
$$;

-- ── 5c. get_hr_emploc_import_rows ────────────────────────────────────────────
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

  -- Verify caller can access this batch
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
    r.validation_status, r.validation_errors, r.hr_emploc_id
  FROM public.hr_emploc_import_rows r
  WHERE r.batch_id = p_batch_id
  ORDER BY r.row_number;
END;
$$;

-- ── 5d. approve_hr_emploc_import (HA/SA only) ─────────────────────────────────
-- Transactionally inserts hr_emploc rows for all 'valid' staged rows.
-- Only fully valid rows are imported. Blocked rows remain excluded.
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

  -- Lock batch row
  SELECT * INTO v_batch
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;

  -- State guards (full transition matrix)
  CASE v_batch.status
    WHEN 'approved'     THEN RAISE EXCEPTION 'This batch has already been approved' USING ERRCODE = 'P0001';
    WHEN 'rejected'     THEN RAISE EXCEPTION 'Rejected batches cannot be approved'  USING ERRCODE = 'P0001';
    WHEN 'rolled_back'  THEN RAISE EXCEPTION 'Rolled-back batches cannot be re-approved' USING ERRCODE = 'P0001';
    ELSE NULL;
  END CASE;

  IF v_batch.valid_rows = 0 THEN
    RAISE EXCEPTION 'No valid rows to import — all rows are blocked' USING ERRCODE = 'P0001';
  END IF;

  -- Process only 'valid' rows
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
      -- Account not found at approval time — block this row
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'ACCOUNT_NAME',
          'msg', format('Account "%s" not found in group at approval time.', v_row.account_name)
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- Build applicant_name in DB format: FIRST [MIDDLE] LAST
    v_full_name := TRIM(
      CASE WHEN v_row.middle_name IS NOT NULL AND v_row.middle_name <> ''
        THEN v_row.first_name || ' ' || v_row.middle_name || ' ' || v_row.last_name
        ELSE v_row.first_name || ' ' || v_row.last_name
      END
    );

    -- Create HR Emploc record (no vcode/vacancy link — bulk import path)
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
      NULL,                                         -- no vacancy link
      COALESCE(v_account_name, v_row.account_name), -- account name snapshot
      v_account_id,
      COALESCE(v_row.position, ''),
      v_row.store_name,                             -- may be NULL
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

    -- Link staged row → created record
    UPDATE public.hr_emploc_import_rows
    SET hr_emploc_id = v_hr_id
    WHERE id = v_row.id;

    v_created := v_created + 1;
  END LOOP;

  -- Mark batch approved
  UPDATE public.hr_emploc_import_batches SET
    status       = 'approved',
    approved_by  = v_caller_id,
    approved_at  = now(),
    created_rows = v_created
  WHERE id = p_batch_id;

  RETURN json_build_object('records_created', v_created);
END;
$$;

-- ── 5e. reject_hr_emploc_import (HA/SA only) ─────────────────────────────────
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
  v_caller_id  UUID;
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
    rejected_by           = v_caller_id,
    rejected_at           = now(),
    rejection_reason_code = p_reason_code,
    rejection_reason_note = p_reason_note
  WHERE id = p_batch_id;
END;
$$;

-- ── 5f. rollback_hr_emploc_import (HA/SA only) ───────────────────────────────
-- Soft-deletes only the hr_emploc rows created by this batch.
-- Blocked if any imported record has been moved to Plantilla.
-- Never touches Plantilla, Vacancy, or Coverage data.
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
  v_caller_id    UUID;
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

  SELECT * INTO v_batch
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;

  -- State transition guards
  CASE v_batch.status
    WHEN 'rolled_back'     THEN RAISE EXCEPTION 'This batch has already been rolled back' USING ERRCODE = 'P0001';
    WHEN 'rejected'        THEN RAISE EXCEPTION 'Rejected batches cannot be rolled back — no records were created' USING ERRCODE = 'P0001';
    WHEN 'pending_approval'THEN RAISE EXCEPTION 'Pending batches cannot be rolled back — reject instead' USING ERRCODE = 'P0001';
    ELSE NULL;
  END CASE;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'Only approved batches can be rolled back' USING ERRCODE = 'P0001';
  END IF;

  -- Safety: block if any imported record reached Plantilla
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

  -- Soft-delete ONLY the hr_emploc records created by this import batch
  UPDATE public.hr_emploc
  SET deleted_at = now()
  WHERE import_batch_id = p_batch_id
    AND deleted_at IS NULL;

  GET DIAGNOSTICS v_removed = ROW_COUNT;

  -- Mark batch rolled_back
  UPDATE public.hr_emploc_import_batches SET
    status          = 'rolled_back',
    rolled_back_by  = v_caller_id,
    rolled_back_at  = now(),
    rollback_reason = TRIM(p_reason)
  WHERE id = p_batch_id;

  RETURN json_build_object('records_removed', v_removed);
END;
$$;

-- ── 6. Grants ─────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.submit_hr_emploc_import(TEXT, UUID, JSONB)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_hr_emploc_import_batches()                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_hr_emploc_import_rows(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_hr_emploc_import(UUID)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_hr_emploc_import(UUID, TEXT, TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_hr_emploc_import(UUID, TEXT)            TO authenticated;

COMMIT;
