-- Migration: 20260819200000_fix_hr_emploc_import_data_team_gate.sql
-- Module: HR Emploc Import
-- Prompt: ohm#3wv7n2kx (BUG-04)
--
-- Root cause: submit_hr_emploc_import / get_hr_emploc_import_groups /
-- get_hr_emploc_import_batches / get_hr_emploc_import_rows all gated on
-- `get_my_role_level() < 50` (raising P0001 'Insufficient permissions' below
-- that level). roles.role_level for 'Encoder' is 30 (set by
-- 20260527000000_unify_role_level_source.sql, confirmed live, never
-- changed since), so Encoder — a documented Data Team role intended to have
-- HR Emploc Import access alongside Super Admin/Head Admin — was hard-blocked
-- from the entire module. Docs (docs/state/hr_emploc_state.md) assumed
-- Encoder's level was >=50; it is not.
--
-- Fix: replace the role_level<50 gate with i_am_data_team() (existing helper,
-- SECURITY DEFINER STABLE, defined as
-- get_effective_role() IN ('Encoder','Head Admin','Super Admin')) across all
-- 4 affected RPCs. This is the same access set the module's docs describe.
--
-- Confirmed via live pg_proc (2026-08-19) that exactly these 4 functions carry
-- the `get_my_role_level() < 50` gate anywhere in the schema. The 3 other
-- HR Emploc Import RPCs (approve_hr_emploc_import, reject_hr_emploc_import,
-- rollback_hr_emploc_import) use `get_my_role_level() < 90` (SA/HA only) —
-- correct per the access matrix, untouched here.
--
-- Behavior change: Operations Manager (role_level=70) currently passes the
-- old `< 50` gate but has no client-side entry point into this module
-- (More Module's ModuleVisibility.keyImports defaults to hasFullAccess only;
-- OM is not in the module's MoreAccess list) — confirmed via grep, only one
-- Flutter service file (hr_emploc_import_service.dart) calls these RPCs.
-- Removing OM's incidental backend access is an intentional tightening,
-- approved by Ohm, not a functional regression for real OM usage.
--
-- No schema/RLS/table changes. CREATE OR REPLACE only; every other line of
-- each function body is byte-identical to the live version (verified via
-- pg_get_functiondef before writing this file).

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
  IF NOT i_am_data_team() THEN
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

CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_batches()
RETURNS TABLE (
  id uuid,
  file_name text,
  status text,
  group_id uuid,
  group_name text,
  total_rows integer,
  valid_rows integer,
  blocked_rows integer,
  duplicate_rows integer,
  created_rows integer,
  uploaded_by uuid,
  uploaded_by_name text,
  uploaded_at timestamp with time zone,
  approved_by uuid,
  approved_by_name text,
  approved_at timestamp with time zone,
  rejected_by uuid,
  rejected_by_name text,
  rejected_at timestamp with time zone,
  rejection_reason_code text,
  rejection_reason_note text,
  rolled_back_by uuid,
  rolled_back_by_name text,
  rolled_back_at timestamp with time zone,
  rollback_reason text,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF NOT i_am_data_team() THEN
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

CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_rows(p_batch_id uuid)
RETURNS TABLE (
  id uuid,
  batch_id uuid,
  row_number integer,
  group_name text,
  account_name text,
  last_name text,
  first_name text,
  middle_name text,
  date_hired date,
  position_name text,
  store_name text,
  employment_type text,
  vcode text,
  validation_status text,
  validation_errors jsonb,
  hr_emploc_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF NOT i_am_data_team() THEN
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
  IF NOT i_am_data_team() THEN
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
