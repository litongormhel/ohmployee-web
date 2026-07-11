-- Migration: 20260707130000_plantilla_import_require_date_hired
-- Created: 2026-07-07
-- Prompt: ohm#c4e91a7b (Add Date Hired as Required Field in Plantilla Import)
-- Depends on: 20260707100001_hrco_email_import_validation.sql (latest full body
--   of submit_plantilla_baseline_import / approve_plantilla_import_batch)
--
-- Purpose: Add DATE_HIRED as a REQUIRED column in the Plantilla baseline import.
--   Target column: public.plantilla.date_hired (already exists, nullable date —
--   no ALTER needed on that table). New raw staging column added on
--   plantilla_import_rows only.
--
--   Validation (submit_plantilla_baseline_import, per row):
--     - required (blocks if blank/missing)
--     - must parse as a valid date
--     - must not be a future date (> CURRENT_DATE)
--
--   Non-breaking guarantees:
--     - employment_type and required_hc handling untouched.
--     - Existing plantilla rows are never modified by this migration (no backfill,
--       no UPDATE on existing employees' date_hired beyond the same
--       fill-if-blank rule already used for every other optional enrichment
--       field — existing non-null values are preserved).
--     - Every other validation rule, conflict-classification branch, slot wire,
--       and HRCO assignment path carried over byte-for-byte from
--       20260707100001.
BEGIN;

ALTER TABLE public.plantilla_import_rows
  ADD COLUMN IF NOT EXISTS date_hired_raw text;

COMMENT ON COLUMN public.plantilla_import_rows.date_hired_raw IS
  'ohm#c4e91a7b: REQUIRED CSV field — date hired, raw string as uploaded (YYYY-MM-DD expected).';

CREATE OR REPLACE FUNCTION public.submit_plantilla_baseline_import(p_file_name text, p_group_id uuid, p_account_id uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300000'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_role       text := public.get_my_role();
  v_batch_id   uuid;
  v_acct_group uuid;
  v_acct_name  text;

  v_row        jsonb;
  v_idx        int := 0;

  -- Required CSV fields
  v_vcode      text;
  v_store_nm   text;
  v_prov       text;
  v_city       text;
  v_position   text;
  v_emp_type   text;
  v_req_hc     text;
  v_pen_raw    text;
  v_emp        text;
  v_last       text;
  v_first      text;
  v_middle     text;

  -- ohm#c4e91a7b: DATE_HIRED — required, validated field
  v_date_hired_raw    text;
  v_date_hired_parsed date;

  -- Optional enrichment fields
  v_civil_status    text;
  v_rate_raw        text;
  v_birthdate_raw   text;
  v_contact_raw     text;
  v_address_raw     text;
  v_schedule_raw    text;
  v_dayoff_raw      text;
  v_coordinator_raw text;

  -- ohm#k8d2x7qf: HRCO_EMAIL optional-but-validated field
  v_hrco_email_raw  text;
  v_hrco_user_id    uuid;

  -- Resolved references
  v_store_id   uuid;
  v_store_acct uuid;
  v_store_grp  uuid;

  -- Per-row state
  v_errs            jsonb;
  v_flags           jsonb;
  v_status          text;
  v_is_roving       boolean;
  v_store_cnt       int;
  v_is_new_store    boolean;
  v_is_existing_emp boolean;
  v_existing_pid    uuid;

  -- Employee conflict classification
  v_emp_conflict_type  text;   -- 'active_employee' | 'archived_employee' | 'rollback_safe_employee' | 'inactive_or_archived_existing_record' | NULL
  v_active_emp_name    text;

  -- Batch counters
  v_total      int := 0;
  v_valid      int := 0;
  v_flagged    int := 0;
  v_skipped    int := 0;
  v_blocked    int := 0;
  v_roving     int := 0;
  v_new_stores int := 0;
  v_ex_stores  int := 0;
  v_ex_emps    int := 0;
  v_xacct      int := 0;
  v_xgroup     int := 0;
  v_over20     int := 0;
  v_missing    int := 0;

  v_summary    jsonb;
  v_final      text;
BEGIN
  -- Auth
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Governance gate
  PERFORM public.fn_assert_governance_enabled('import_plantilla');

  -- Audit Freeze Gate (Phase 2A)
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- Input validation
  IF p_file_name IS NULL OR length(trim(p_file_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: file_name required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows must be a jsonb array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows is empty' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN
    RAISE EXCEPTION 'INVALID_INPUT: max 5000 rows per batch' USING ERRCODE = '22023';
  END IF;

  -- Scope validation
  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'INVALID_GROUP: %', p_group_id USING ERRCODE = '23503';
  END IF;
  SELECT group_id, account_name INTO v_acct_group, v_acct_name
    FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: %', p_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %',
      p_account_id, p_group_id USING ERRCODE = '23503';
  END IF;
  IF NOT public.i_have_full_access()
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  -- Create batch
  INSERT INTO public.plantilla_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- Pre-passes

  -- [A] Duplicate VCODEs within this upload (all occurrences will be blocked)
  DROP TABLE IF EXISTS _pib_dup_vcodes;
  CREATE TEMP TABLE _pib_dup_vcodes ON COMMIT DROP AS
  SELECT upper(trim(elem->>'VCODE')) AS vcode
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1 HAVING count(*) > 1;

  -- [B] Employee -> store coverage (roving detection)
  DROP TABLE IF EXISTS _pib_emp_cov;
  CREATE TEMP TABLE _pib_emp_cov ON COMMIT DROP AS
  SELECT
    upper(trim(elem->>'EMPLOYEE_NO')) AS emp,
    count(DISTINCT upper(trim(elem->>'VCODE'))) AS store_count
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'EMPLOYEE_NO'),'') IS NOT NULL
    AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1;

  -- [C] Already-seen (employee_no, vcode) pairs for exact-duplicate skip detection
  DROP TABLE IF EXISTS _pib_seen_pairs;
  CREATE TEMP TABLE _pib_seen_pairs (emp text, vcode text) ON COMMIT DROP;

  -- [D] VCODEs actively assigned in the live system: vcode -> employee_no
  DROP TABLE IF EXISTS _pib_active_vcode_owners;
  CREATE TEMP TABLE _pib_active_vcode_owners ON COMMIT DROP AS
  SELECT upper(trim(a.vcode)) AS vcode,
         upper(trim(a.employee_no)) AS employee_no
    FROM public.employee_store_allocations a
   WHERE a.is_active
     AND a.vcode IS NOT NULL
     AND a.employee_no IS NOT NULL;

  -- [E] OHM2026_0079: Rollback-safe VCodes
  --     Vacancies soft-deleted via a completed vacancy import rollback.
  --     These VCODEs may be re-used in a new plantilla import.
  DROP TABLE IF EXISTS _pib_rollback_safe_vcodes;
  CREATE TEMP TABLE _pib_rollback_safe_vcodes ON COMMIT DROP AS
  SELECT upper(trim(vv.vcode)) AS vcode
    FROM public.vacancies vv
    JOIN public.vacancy_import_batches vib ON vib.id = vv.source_vacancy_import_batch_id
   WHERE vv.vcode IS NOT NULL
     AND vv.deleted_at IS NOT NULL
     AND vib.rollback_status = 'completed';

  -- [F] OHM2026_0079: Blocked (archived/non-reusable) VCodes
  --     Vacancies that are archived or soft-deleted without a completed rollback.
  DROP TABLE IF EXISTS _pib_blocked_vcodes;
  CREATE TEMP TABLE _pib_blocked_vcodes ON COMMIT DROP AS
  SELECT upper(trim(vv.vcode)) AS vcode
    FROM public.vacancies vv
   WHERE vv.vcode IS NOT NULL
     AND (
       COALESCE(vv.is_archived, false) = true
       OR vv.status = 'Archived'
       OR (
         vv.deleted_at IS NOT NULL
         AND NOT (
           vv.source_vacancy_import_batch_id IS NOT NULL
           AND EXISTS (
             SELECT 1 FROM public.vacancy_import_batches vib2
              WHERE vib2.id = vv.source_vacancy_import_batch_id
                AND vib2.rollback_status = 'completed'
           )
         )
       )
     );

  -- Row loop
  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx      := v_idx + 1;
    v_total    := v_total + 1;
    v_errs     := '[]'::jsonb;
    v_flags    := '[]'::jsonb;
    v_is_roving     := false;
    v_store_cnt     := 0;
    v_is_new_store  := false;
    v_is_existing_emp := false;
    v_store_id := NULL; v_store_acct := NULL; v_store_grp := NULL;
    v_existing_pid := NULL;
    v_emp_conflict_type := NULL;
    v_date_hired_parsed := NULL;

    -- Parse required CSV fields
    v_vcode    := upper(NULLIF(trim(COALESCE(v_row->>'VCODE','')), ''));
    v_store_nm := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')), '');
    v_prov     := NULLIF(trim(COALESCE(v_row->>'AREA_PROVINCE','')), '');
    v_city     := NULLIF(trim(COALESCE(v_row->>'AREA_CITY','')), '');
    v_position := NULLIF(trim(COALESCE(v_row->>'POSITION','')), '');
    v_emp_type := NULLIF(trim(COALESCE(v_row->>'EMPLOYMENT_TYPE','')), '');
    v_req_hc   := NULLIF(trim(COALESCE(v_row->>'REQUIRED_HC','')), '');
    v_pen_raw  := NULLIF(trim(COALESCE(v_row->>'WITH_PENALTY','')), '');
    v_emp      := upper(NULLIF(trim(COALESCE(v_row->>'EMPLOYEE_NO','')), ''));
    v_last     := NULLIF(trim(COALESCE(v_row->>'LAST_NAME','')), '');
    v_first    := NULLIF(trim(COALESCE(v_row->>'FIRST_NAME','')), '');
    v_middle   := NULLIF(trim(COALESCE(v_row->>'MIDDLE_NAME','')), '');
    v_date_hired_raw := NULLIF(trim(COALESCE(v_row->>'DATE_HIRED','')), '');

    -- Parse optional enrichment fields (safe: null if blank or absent)
    v_civil_status    := nullif(trim(coalesce(v_row->>'CIVIL_STATUS', '')), '');
    v_rate_raw        := nullif(trim(coalesce(v_row->>'RATE', '')), '');
    v_birthdate_raw   := nullif(trim(coalesce(v_row->>'BIRTHDATE', '')), '');
    v_contact_raw     := nullif(trim(coalesce(v_row->>'CONTACT', '')), '');
    v_address_raw     := nullif(trim(coalesce(v_row->>'ADDRESS', '')), '');
    v_schedule_raw    := nullif(trim(coalesce(v_row->>'SCHEDULE', '')), '');
    v_dayoff_raw      := nullif(trim(coalesce(v_row->>'DAYOFF', '')), '');
    v_coordinator_raw := nullif(trim(coalesce(v_row->>'COORDINATOR', '')), '');
    v_hrco_email_raw  := nullif(trim(coalesce(v_row->>'HRCO_EMAIL', '')), '');

    -- Blocking: required fields
    IF v_vcode    IS NULL THEN v_errs := v_errs || '[{"field":"VCODE","msg":"required"}]'::jsonb; END IF;
    IF v_store_nm IS NULL THEN v_errs := v_errs || '[{"field":"STORE_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_prov     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_PROVINCE","msg":"required"}]'::jsonb; END IF;
    IF v_city     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_CITY","msg":"required"}]'::jsonb; END IF;
    IF v_emp      IS NULL THEN v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"required"}]'::jsonb; END IF;
    IF v_last     IS NULL THEN v_errs := v_errs || '[{"field":"LAST_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_first    IS NULL THEN v_errs := v_errs || '[{"field":"FIRST_NAME","msg":"required"}]'::jsonb; END IF;

    -- ohm#c4e91a7b: DATE_HIRED — required, must be a valid date, must not be future.
    IF v_date_hired_raw IS NULL THEN
      v_errs := v_errs || '[{"field":"DATE_HIRED","msg":"required"}]'::jsonb;
    ELSE
      BEGIN
        v_date_hired_parsed := v_date_hired_raw::date;
      EXCEPTION WHEN OTHERS THEN
        v_date_hired_parsed := NULL;
      END;

      IF v_date_hired_parsed IS NULL THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field', 'DATE_HIRED',
          'msg',   'invalid date — expected YYYY-MM-DD'
        ));
      ELSIF v_date_hired_parsed > CURRENT_DATE THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field', 'DATE_HIRED',
          'msg',   'DATE_HIRED cannot be a future date'
        ));
        v_date_hired_parsed := NULL;
      END IF;
    END IF;
    -- End ohm#c4e91a7b DATE_HIRED validation

    IF v_vcode IS NOT NULL AND v_store_nm IS NOT NULL AND v_emp IS NULL THEN
      v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"store row has no employee - every VCODE must have an assigned employee"}]'::jsonb;
    END IF;

    IF v_vcode IS NOT NULL AND EXISTS (SELECT 1 FROM _pib_dup_vcodes WHERE vcode = v_vcode) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"duplicate VCODE in upload - each VCODE must appear exactly once"}]'::jsonb;
    END IF;

    IF v_vcode IS NOT NULL AND v_emp IS NOT NULL AND EXISTS (
      SELECT 1 FROM _pib_active_vcode_owners
      WHERE vcode = v_vcode AND employee_no <> v_emp
    ) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE already actively assigned to a different employee"}]'::jsonb;
    END IF;

    -- OHM2026_0079: VCode archived/non-reusable conflict blocking
    IF v_vcode IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM _pib_active_vcode_owners
                        WHERE vcode = v_vcode AND employee_no <> v_emp)
    THEN
      IF EXISTS (SELECT 1 FROM _pib_rollback_safe_vcodes WHERE vcode = v_vcode) THEN
        v_flags := v_flags || jsonb_build_array(jsonb_build_object(
          'flag',         'rollback_safe_vcode',
          'conflict_type','rollback_safe_vcode',
          'msg',          'Rollback record detected - eligible for re-upload.'
        ));
      ELSIF EXISTS (SELECT 1 FROM _pib_blocked_vcodes WHERE vcode = v_vcode) THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field',         'VCODE',
          'conflict_type', 'archived_vcode',
          'msg',           'Archived VCode cannot be reused.'
        ));
      END IF;
    END IF;
    -- End OHM2026_0079 VCode conflict blocking

    IF v_req_hc IS NULL THEN
      v_flags := v_flags || '[{"flag":"missing_required_hc","msg":"REQUIRED_HC not provided"}]'::jsonb;
    END IF;

    -- ohm#k8d2x7qf: HRCO_EMAIL validation. Optional field, but once provided,
    -- resolves to a blocking error if invalid. Same rule as assign_hrco_to_plantilla
    -- via fn_is_valid_hrco_for_account -- single code path, no divergent logic between
    -- CSV import and manual Assign/Reassign.
    v_hrco_user_id := NULL;
    IF v_hrco_email_raw IS NOT NULL THEN
      SELECT up.auth_user_id INTO v_hrco_user_id
        FROM public.users_profile up
       WHERE lower(up.email) = lower(v_hrco_email_raw)
       LIMIT 1;

      IF v_hrco_user_id IS NULL THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field',         'HRCO_EMAIL',
          'conflict_type', 'hrco_email_not_found',
          'msg',           'HRCO_EMAIL not found: no user exists with this email.'
        ));
      ELSIF NOT public.fn_is_valid_hrco_for_account(v_hrco_user_id, p_account_id) THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field',         'HRCO_EMAIL',
          'conflict_type', 'hrco_email_not_hrco_on_account',
          'msg',           'HRCO_EMAIL is not an HRCO on this account roster.'
        ));
        v_hrco_user_id := NULL;
      END IF;
    END IF;
    -- End ohm#k8d2x7qf HRCO_EMAIL validation

    IF v_emp IS NOT NULL AND v_vcode IS NOT NULL
       AND EXISTS (SELECT 1 FROM _pib_seen_pairs WHERE emp = v_emp AND vcode = v_vcode)
    THEN
      v_status := 'skipped';
      v_flags  := v_flags || '[{"flag":"duplicate_emp_vcode","msg":"same employee+VCODE already processed - skipped"}]'::jsonb;
    ELSE

      IF v_vcode IS NOT NULL THEN
        SELECT s.id, s.account_id, s.group_id
          INTO v_store_id, v_store_acct, v_store_grp
          FROM public.stores s
         WHERE upper(s.vcode) = v_vcode AND s.status = 'active'
         ORDER BY s.created_at LIMIT 1;
      END IF;
      v_is_new_store := (v_store_id IS NULL);

      IF v_store_id IS NOT NULL AND v_store_grp IS NOT NULL
         AND v_store_grp <> p_group_id THEN
        v_errs   := v_errs   || '[{"field":"VCODE","msg":"cross-group: store VCODE belongs to a different group"}]'::jsonb;
        v_xgroup := v_xgroup + 1;
      END IF;

      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.employee_store_allocations a
        WHERE upper(trim(a.employee_no)) = v_emp AND a.is_active
          AND a.account_id IS NOT NULL AND a.account_id <> p_account_id
      ) THEN
        v_errs  := v_errs  || '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee already deployed in another account"}]'::jsonb;
        v_xacct := v_xacct + 1;
      END IF;

      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.employee_store_allocations a
        WHERE upper(trim(a.employee_no)) = v_emp AND a.is_active
          AND a.group_id IS NOT NULL AND a.group_id <> p_group_id
      ) THEN
        v_errs   := v_errs   || '[{"field":"EMPLOYEE_NO","msg":"cross-group: employee already deployed in another group"}]'::jsonb;
        v_xgroup := v_xgroup + 1;
      END IF;

      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE p.employee_no = v_emp
          AND p.is_deleted = false
          AND p.account_id IS NOT NULL
          AND p.account_id <> p_account_id
          AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
      ) THEN
        v_errs  := v_errs  || '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee exists in plantilla under a different account"}]'::jsonb;
        v_xacct := v_xacct + 1;
      END IF;

      IF v_emp IS NOT NULL THEN
        SELECT store_count INTO v_store_cnt FROM _pib_emp_cov WHERE emp = v_emp;
        v_store_cnt := COALESCE(v_store_cnt, 0);
        IF v_store_cnt > 1 THEN
          v_is_roving := true;
          v_flags := v_flags || jsonb_build_array(
            jsonb_build_object('flag','roving','msg',
              'roving employee: ' || v_store_cnt || ' stores')
          );
        END IF;
        IF v_store_cnt > 20 THEN
          v_flags := v_flags || jsonb_build_array(
            jsonb_build_object('flag','over_20_stores','msg',
              v_store_cnt || ' stores (>20 allowed but flagged)')
          );
          v_over20 := v_over20 + 1;
        END IF;
      END IF;

      -- Employee conflict classification
      -- Priority order (first match wins):
      --   1. Rollback-safe plantilla row   -> ALLOWED (flag: rollback_safe_employee)
      --   2. Active plantilla row          -> BLOCKED  (error: active_employee)
      --   3. Archived/deleted non-rollback -> BLOCKED  (error: archived_employee)
      --   4. Inactive row (OHM2026_0083)   -> BLOCKED  (error: inactive_or_archived_existing_record)
      --      (Previously: FLAG / reconcile path -- changed by OHM2026_0083)
      --   5. No existing row               -> new employee (no flag)
      IF v_emp IS NOT NULL THEN
        v_emp_conflict_type := NULL;
        v_is_existing_emp   := false;

        -- Priority 1: rollback-safe plantilla row
        IF EXISTS (
          SELECT 1 FROM public.plantilla p
           JOIN public.plantilla_import_batches pib
             ON pib.id = p.source_baseline_import_batch_id
          WHERE p.employee_no = v_emp
            AND pib.status = 'rolled_back'
            AND pib.rolled_back_at IS NOT NULL
        ) THEN
          v_emp_conflict_type := 'rollback_safe_employee';
          v_flags := v_flags || jsonb_build_array(jsonb_build_object(
            'flag',         'rollback_safe_employee',
            'conflict_type','rollback_safe_employee',
            'msg',          'Rollback record detected - eligible for re-upload.'
          ));

        -- Priority 2: active plantilla row
        ELSIF EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = v_emp
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
        ) THEN
          SELECT NULLIF(
                   CASE
                     WHEN NULLIF(trim(p.last_name), '') IS NULL
                       OR NULLIF(trim(p.first_name), '') IS NULL
                     THEN NULL
                     ELSE trim(
                       initcap(lower(trim(p.last_name))) ||
                       ', ' || initcap(lower(trim(p.first_name))) ||
                       COALESCE(CASE
                         WHEN NULLIF(trim(p.middle_name), '') IS NULL THEN NULL
                         WHEN upper(trim(p.middle_name)) IN ('NA', 'N/A') THEN NULL
                         ELSE ' ' || initcap(lower(trim(p.middle_name)))
                       END, '')
                     )
                   END,
                   ''
                 )
            INTO v_active_emp_name
            FROM public.plantilla p
           WHERE p.employee_no = v_emp
             AND p.is_deleted = false
             AND COALESCE(p.is_archived, false) = false
             AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
           ORDER BY p.updated_at DESC NULLS LAST, p.created_at DESC NULLS LAST
           LIMIT 1;

          v_emp_conflict_type := 'active_employee';
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field',         'EMPLOYEE_NO',
            'conflict_type', 'active_employee',
            'msg',           CASE
                               WHEN v_active_emp_name IS NULL THEN
                                 'Employee already exists in active plantilla.'
                               ELSE
                                 'Employee already exists in active plantilla: ' || v_active_emp_name || '.'
                             END
          ));

        -- Priority 3: archived/soft-deleted plantilla row without rollback linkage
        ELSIF EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = v_emp
            AND (p.is_deleted = true OR COALESCE(p.is_archived, false) = true)
        ) THEN
          v_emp_conflict_type := 'archived_employee';
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field',         'EMPLOYEE_NO',
            'conflict_type', 'archived_employee',
            'msg',           'Employee exists in archived plantilla and cannot be reused.'
          ));

        -- Priority 4 (OHM2026_0083): inactive row -- BLOCKED
        -- Changed from FLAG (reconcile path) to BLOCK.
        -- Inactive/Rejected Deactivation employees must be manually restored
        -- before re-import. Do not auto-reactivate via import commit.
        ELSIF EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = v_emp
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Inactive', 'Rejected Deactivation')
        ) THEN
          v_emp_conflict_type := 'inactive_or_archived_existing_record';
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field',         'EMPLOYEE_NO',
            'conflict_type', 'inactive_or_archived_existing_record',
            'msg',           'Cannot import because matching employee, emploc, or VCode is inactive/archived. Restore/reactivate first or use a valid active record.'
          ));

        -- Priority 5: no existing plantilla record -- new employee
        ELSE
          v_emp_conflict_type := NULL;
        END IF;
      END IF;
      -- End employee conflict classification

      -- OHM2026_0079: HR Emploc archived conflict blocking
      -- Only runs when employee is not already fully blocked.
      IF v_emp IS NOT NULL
         AND v_emp_conflict_type IS DISTINCT FROM 'active_employee'
         AND v_emp_conflict_type IS DISTINCT FROM 'archived_employee'
         AND v_emp_conflict_type IS DISTINCT FROM 'inactive_or_archived_existing_record'
      THEN
        IF EXISTS (
          SELECT 1 FROM public.hr_emploc h
          WHERE upper(trim(COALESCE(h.emploc_no, ''))) = v_emp
            AND h.emploc_no IS NOT NULL
            AND h.emploc_no <> ''
            AND h.deleted_at IS NOT NULL
        ) THEN
          IF EXISTS (
            SELECT 1 FROM public.employee_store_allocations a
             JOIN public.plantilla_import_batches pib ON pib.id = a.source_import_batch_id
            WHERE upper(trim(COALESCE(a.employee_no, ''))) = v_emp
              AND pib.status = 'rolled_back'
          ) THEN
            v_flags := v_flags || jsonb_build_array(jsonb_build_object(
              'flag',         'rollback_safe_emploc',
              'conflict_type','rollback_safe_emploc',
              'msg',          'Rollback record detected - eligible for re-upload.'
            ));
          ELSE
            v_errs := v_errs || jsonb_build_array(jsonb_build_object(
              'field',         'EMPLOYEE_NO',
              'conflict_type', 'archived_emploc',
              'msg',           'Archived Emploc cannot be reused.'
            ));
          END IF;
        END IF;
      END IF;
      -- End OHM2026_0079 HR Emploc conflict blocking

      IF jsonb_array_length(v_errs) > 0 THEN
        v_status := 'blocked';
      ELSIF jsonb_array_length(v_flags) > 0 THEN
        v_status := 'flagged';
      ELSE
        v_status := 'valid';
      END IF;

      IF v_emp IS NOT NULL AND v_vcode IS NOT NULL AND v_status IN ('valid', 'flagged') THEN
        INSERT INTO _pib_seen_pairs(emp, vcode) VALUES (v_emp, v_vcode);
      END IF;

      IF v_vcode IS NOT NULL AND v_status <> 'blocked' THEN
        IF v_is_new_store THEN v_new_stores := v_new_stores + 1;
        ELSE v_ex_stores := v_ex_stores + 1;
        END IF;
      END IF;

    END IF; -- end non-skip branch

    INSERT INTO public.plantilla_import_rows (
      batch_id, row_number, raw_data,
      vcode, store_name, area_province, area_city, position, employment_type,
        required_hc_raw, with_penalty_raw,
      employee_no, last_name, first_name, middle_name,
      date_hired_raw,
      civil_status, rate_raw, birthdate_raw, contact_raw,
      address_raw, schedule_raw, dayoff_raw, coordinator_raw,
      hrco_email_raw, resolved_hrco_user_id,
      resolved_store_id, resolved_account_id, resolved_group_id,
      validation_status, validation_errors, validation_flags,
      is_roving, roving_store_count, is_new_store, is_existing_employee
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_vcode, v_store_nm, v_prov, v_city, v_position, v_emp_type,
        v_req_hc, v_pen_raw,
      v_emp, v_last, v_first, v_middle,
      v_date_hired_raw,
      v_civil_status, v_rate_raw, v_birthdate_raw, v_contact_raw,
      v_address_raw, v_schedule_raw, v_dayoff_raw, v_coordinator_raw,
      v_hrco_email_raw, v_hrco_user_id,
      v_store_id, v_store_acct, v_store_grp,
      v_status, v_errs, v_flags,
      v_is_roving, v_store_cnt, v_is_new_store, v_is_existing_emp
    );

    CASE v_status
      WHEN 'valid'   THEN v_valid    := v_valid    + 1;
      WHEN 'flagged' THEN v_flagged  := v_flagged  + 1;
      WHEN 'skipped' THEN v_skipped  := v_skipped  + 1;
      WHEN 'blocked' THEN v_blocked  := v_blocked  + 1;
      ELSE NULL;
    END CASE;

  END LOOP;

  -- Post-loop: HC mismatch sweep
  UPDATE public.plantilla_import_rows AS r
     SET validation_flags  = r.validation_flags || jsonb_build_array(
           jsonb_build_object(
             'flag', CASE WHEN hc.uploaded_count < hc.total_req
                          THEN 'hc_under_required'
                          ELSE 'hc_over_required'
                     END,
             'msg',  format('%s employee(s) uploaded for "%s / %s" but REQUIRED_HC sums to %s',
                            hc.uploaded_count, hc.store_nm, hc.pos, hc.total_req)
           )
         ),
         validation_status = CASE
           WHEN r.validation_status = 'valid' THEN 'flagged'
           ELSE r.validation_status
         END
    FROM (
      SELECT
        store_name  AS store_nm,
        position    AS pos,
        count(*)    AS uploaded_count,
        sum(
          COALESCE(
            NULLIF(regexp_replace(COALESCE(required_hc_raw,''),'[^0-9]','','g'), '')::int,
            0
          )
        )           AS total_req
      FROM public.plantilla_import_rows
     WHERE batch_id = v_batch_id
       AND validation_status IN ('valid','flagged')
       AND store_name IS NOT NULL
       AND position   IS NOT NULL
     GROUP BY store_name, position
    HAVING count(*) <>
           sum(COALESCE(
             NULLIF(regexp_replace(COALESCE(required_hc_raw,''),'[^0-9]','','g'), '')::int,
             0
           ))
    ) AS hc
   WHERE r.batch_id      = v_batch_id
     AND r.store_name    = hc.store_nm
     AND r.position      = hc.pos
     AND r.validation_status IN ('valid','flagged');

  SELECT count(*) FILTER (WHERE validation_status = 'valid')
    INTO v_valid
    FROM public.plantilla_import_rows WHERE batch_id = v_batch_id;

  SELECT count(*) FILTER (WHERE validation_status = 'flagged')
    INTO v_flagged
    FROM public.plantilla_import_rows WHERE batch_id = v_batch_id;

  -- Post-loop: roving dedup
  SELECT count(*) INTO v_roving
    FROM _pib_emp_cov WHERE store_count > 1;

  -- existing_employees_count: OHM2026_0083 -- inactive employees are now BLOCKED,
  -- so is_existing_employee is false for those rows.
  -- This counter reflects only non-blocked existing employees (should be 0 for
  -- inactive rows after this migration).
  SELECT count(DISTINCT employee_no) INTO v_ex_emps
    FROM public.plantilla_import_rows r
   WHERE r.batch_id = v_batch_id
     AND r.validation_status IN ('valid','flagged')
     AND r.is_existing_employee;

  -- Post-loop: missing from upload
  SELECT count(*) INTO v_missing
    FROM public.plantilla p
   WHERE p.account_id = p_account_id
     AND p.is_deleted = false
     AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
     AND NOT EXISTS (
       SELECT 1 FROM public.plantilla_import_rows r
        WHERE r.batch_id = v_batch_id
          AND r.employee_no = p.employee_no
          AND r.validation_status IN ('valid','flagged')
     );

  -- Aggregate error summary
  SELECT COALESCE(jsonb_object_agg(field_name, cnt), '{}'::jsonb) INTO v_summary
    FROM (
      SELECT (e.value->>'field') AS field_name, count(*) AS cnt
        FROM public.plantilla_import_rows r
        CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
       WHERE r.batch_id = v_batch_id
       GROUP BY 1
    ) s;

  v_final := CASE
    WHEN (v_valid + v_flagged) = 0 THEN 'validation_failed'
    ELSE 'pending_approval'
  END;

  UPDATE public.plantilla_import_batches
     SET total_rows                = v_total,
         valid_rows                = v_valid,
         flagged_rows              = v_flagged,
         skipped_rows              = v_skipped,
         blocked_rows              = v_blocked,
         roving_detected           = v_roving,
         new_stores_count          = v_new_stores,
         existing_stores_count     = v_ex_stores,
         existing_employees_count  = v_ex_emps,
         cross_account_conflicts   = v_xacct,
         cross_group_conflicts     = v_xgroup,
         over_20_store_warnings    = v_over20,
         missing_from_upload_count = v_missing,
         error_summary             = v_summary,
         status                    = v_final,
         updated_at                = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id',                   v_batch_id,
    'status',                     v_final,
    'total_rows',                 v_total,
    'valid_rows',                 v_valid,
    'flagged_rows',               v_flagged,
    'skipped_rows',               v_skipped,
    'blocked_rows',               v_blocked,
    'roving_detected',            v_roving,
    'new_stores_count',           v_new_stores,
    'existing_stores_count',      v_ex_stores,
    'existing_employees_count',   v_ex_emps,
    'cross_account_conflicts',    v_xacct,
    'cross_group_conflicts',      v_xgroup,
    'over_20_store_warnings',     v_over20,
    'missing_from_upload_count',  v_missing,
    'error_summary',              v_summary
  );
END$function$;

-- ── approve_plantilla_import_batch: commit date_hired alongside HRCO assignment ──
CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300000'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_batch      public.plantilla_import_batches%ROWTYPE;
  v_acct_name  text;

  -- Phase A locals
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_emp_type_norm      text;
  v_stores_done        int := 0;

  -- Phase B locals
  v_emp_rec        record;
  v_store_rec      record;
  v_plantilla_id   uuid;
  v_roving_id      uuid;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;

  -- Optional enrichment parsing
  v_daily_rate_parsed  numeric;
  v_birthdate_parsed   date;
  v_date_hired_parsed  date;
  v_deployment_type    text;
  v_area_val           text;
  v_has_penalty        boolean;

  -- Commit counts
  v_committable int;

  -- VCODE resolution guard
  v_unresolved_vcode text;

  -- Humanised error
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;

  -- OHM2026_0071: Inactive reconcile path (preserved; unreachable for new batches after OHM2026_0083)
  v_inactive_id      uuid;
  v_deactivated_id   uuid;

  -- OHM2026_0071: Slot occupancy wire
  v_slot_id          uuid;
  v_slot_vcode       text;
  v_slot_result      jsonb;
  v_slot_ordinal     int;
  v_slot_store_id    uuid;

  -- OHM2026_0079: Defensive revalidation
  v_reval_emp    text;
  v_reval_vcode  text;

BEGIN
  -- Auth
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Lock + state check
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  -- Pre-commit guard
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid','flagged')
     AND employee_no IS NOT NULL
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch (valid+flagged with employee_no and vcode)'
      USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- Temp store commit map
  DROP TABLE IF EXISTS _pib_store_map;
  CREATE TEMP TABLE _pib_store_map (
    vcode    text,
    store_id uuid,
    is_new   boolean
  ) ON COMMIT DROP;

  -- Inner exception block -- all commit DML is atomic
  BEGIN

    -- OHM2026_0079 + OHM2026_0083: Defensive revalidation
    -- Re-run the same conflict classification as submit_plantilla_baseline_import.
    -- Catches state changes that occurred between Review Import and Approve.

    -- Check 1 (OHM2026_0079): Active non-rollback-safe plantilla employee
    SELECT pir.employee_no INTO v_reval_emp
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.employee_no IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = pir.employee_no
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
            AND NOT EXISTS (
              SELECT 1 FROM public.plantilla_import_batches pib2
               WHERE pib2.id = p.source_baseline_import_batch_id
                 AND pib2.status = 'rolled_back'
                 AND pib2.rolled_back_at IS NOT NULL
            )
       )
     LIMIT 1;

    IF v_reval_emp IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: employee_no % is now active in plantilla. '
        'Re-submit this batch so Review Import can reclassify the conflict.',
        v_reval_emp
        USING ERRCODE = '55000';
    END IF;

    -- Check 2 (OHM2026_0079): Archived non-rollback-safe VCode
    SELECT pir.vcode INTO v_reval_vcode
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.vcode IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.vacancies vv
          WHERE upper(trim(vv.vcode)) = pir.vcode
            AND (
              COALESCE(vv.is_archived, false) = true
              OR vv.status = 'Archived'
              OR (
                vv.deleted_at IS NOT NULL
                AND NOT (
                  vv.source_vacancy_import_batch_id IS NOT NULL
                  AND EXISTS (
                    SELECT 1 FROM public.vacancy_import_batches vib2
                     WHERE vib2.id = vv.source_vacancy_import_batch_id
                       AND vib2.rollback_status = 'completed'
                  )
                )
              )
            )
       )
     LIMIT 1;

    IF v_reval_vcode IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: VCode % is now archived or non-reusable. '
        'Re-submit this batch so Review Import can reclassify the conflict.',
        v_reval_vcode
        USING ERRCODE = '55000';
    END IF;

    -- Check 3 (OHM2026_0083): Inactive/Rejected-Deactivation plantilla employee
    -- in valid/flagged rows. Catches in-flight batches submitted before this
    -- migration where such rows were flagged (reconcile path) rather than blocked.
    v_reval_emp := NULL;
    SELECT pir.employee_no INTO v_reval_emp
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.employee_no IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = pir.employee_no
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Inactive', 'Rejected Deactivation')
       )
     LIMIT 1;

    IF v_reval_emp IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: employee_no % has an inactive plantilla record. '
        'Cannot import because matching employee is inactive/archived. '
        'Restore/reactivate first or use a valid active record.',
        v_reval_emp
        USING ERRCODE = '55000';
    END IF;
    -- End defensive revalidation

    -- Phase A: Store upsert
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, area_province, area_city,
             employment_type, with_penalty_raw, row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_emp_type_norm := CASE
        WHEN lower(COALESCE(v_srow.employment_type,'')) IN ('stationary','roving')
          THEN lower(v_srow.employment_type)
        ELSE NULL
      END;

      v_pen_bool := CASE
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      SELECT to_jsonb(s.*) INTO v_old_store_snap
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_srow.vcode) AND s.status = 'active'
       ORDER BY s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
        INSERT INTO public.stores (
          vcode, store_name, area_province, area_city,
          employment_type, with_penalty,
          group_id, account_id, status,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.area_province, v_srow.area_city,
          v_emp_type_norm, v_pen_bool,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active',
          v_uid, v_uid, v_uid, now(), p_batch_id
        ) RETURNING id INTO v_new_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_new_store_id, true);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_new_store_id, 'insert', NULL, v_uid);

      ELSE
        v_existing_store_id := (v_old_store_snap->>'id')::uuid;

        UPDATE public.stores
           SET store_name      = v_srow.store_name,
               area_province   = v_srow.area_province,
               area_city       = v_srow.area_city,
               employment_type = COALESCE(v_emp_type_norm, employment_type),
               with_penalty    = COALESCE(v_pen_bool, with_penalty),
               updated_by      = v_uid,
               approved_by     = v_uid,
               approved_at     = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_existing_store_id, false);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      UPDATE public.plantilla_import_rows
         SET previous_store_snapshot = v_old_store_snap
       WHERE batch_id = p_batch_id
         AND upper(vcode) = upper(v_srow.vcode)
         AND validation_status IN ('valid','flagged');

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- Post-Phase-A: VCODE resolution guard (OHM2026_1144)
    SELECT r.vcode INTO v_unresolved_vcode
      FROM public.plantilla_import_rows r
     WHERE r.batch_id = p_batch_id
       AND r.validation_status IN ('valid','flagged')
       AND r.vcode IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM _pib_store_map sm WHERE sm.vcode = upper(r.vcode)
       )
     LIMIT 1;

    IF v_unresolved_vcode IS NOT NULL THEN
      RAISE EXCEPTION 'STORE_RESOLUTION_FAILED: VCODE % not resolved after store upsert -- cannot commit plantilla rows',
        v_unresolved_vcode
        USING ERRCODE = '23503';
    END IF;

    -- Phase B: Employee / plantilla upsert
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number))[1]                            AS middle_name,
        (array_agg(position          ORDER BY row_number)
           FILTER (WHERE position IS NOT NULL))[1]                                 AS position,
        (array_agg(employment_type   ORDER BY row_number)
           FILTER (WHERE employment_type IS NOT NULL))[1]                          AS employment_type_raw,
        (array_agg(with_penalty_raw  ORDER BY row_number)
           FILTER (WHERE with_penalty_raw IS NOT NULL))[1]                         AS with_penalty_raw_agg,
        (array_agg(area_province     ORDER BY row_number)
           FILTER (WHERE area_province IS NOT NULL))[1]                            AS area_province,
        (array_agg(area_city         ORDER BY row_number)
           FILTER (WHERE area_city IS NOT NULL))[1]                                AS area_city,
        (array_agg(date_hired_raw    ORDER BY row_number)
           FILTER (WHERE date_hired_raw IS NOT NULL))[1]                           AS date_hired_raw,
        (array_agg(civil_status      ORDER BY row_number)
           FILTER (WHERE civil_status    IS NOT NULL))[1]                          AS civil_status,
        (array_agg(rate_raw          ORDER BY row_number)
           FILTER (WHERE rate_raw        IS NOT NULL))[1]                          AS rate_raw,
        (array_agg(birthdate_raw     ORDER BY row_number)
           FILTER (WHERE birthdate_raw   IS NOT NULL))[1]                          AS birthdate_raw,
        (array_agg(contact_raw       ORDER BY row_number)
           FILTER (WHERE contact_raw     IS NOT NULL))[1]                          AS contact_raw,
        (array_agg(address_raw       ORDER BY row_number)
           FILTER (WHERE address_raw     IS NOT NULL))[1]                          AS address_raw,
        (array_agg(schedule_raw      ORDER BY row_number)
           FILTER (WHERE schedule_raw    IS NOT NULL))[1]                          AS schedule_raw,
        (array_agg(dayoff_raw        ORDER BY row_number)
           FILTER (WHERE dayoff_raw      IS NOT NULL))[1]                          AS dayoff_raw,
        (array_agg(coordinator_raw   ORDER BY row_number)
           FILTER (WHERE coordinator_raw IS NOT NULL))[1]                          AS coordinator_raw,
        (array_agg(resolved_hrco_user_id ORDER BY row_number)
           FILTER (WHERE resolved_hrco_user_id IS NOT NULL))[1]                    AS resolved_hrco_user_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      v_deployment_type := CASE
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'stationary' THEN 'Stationary'
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'roving'     THEN 'Roving'
        ELSE NULLIF(trim(COALESCE(v_emp_rec.employment_type_raw,'')), '')
      END;

      v_area_val := NULLIF(trim(COALESCE(
        v_emp_rec.area_city,
        v_emp_rec.area_province,
        ''
      )), '');

      v_has_penalty := CASE
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      v_daily_rate_parsed := NULL;
      BEGIN
        v_daily_rate_parsed := nullif(trim(coalesce(v_emp_rec.rate_raw, '')), '')::numeric;
      EXCEPTION WHEN OTHERS THEN
        v_daily_rate_parsed := NULL;
      END;

      v_birthdate_parsed := NULL;
      BEGIN
        v_birthdate_parsed := nullif(trim(coalesce(v_emp_rec.birthdate_raw, '')), '')::date;
      EXCEPTION WHEN OTHERS THEN
        v_birthdate_parsed := NULL;
      END;

      -- ohm#c4e91a7b: DATE_HIRED already validated (required + valid + not future)
      -- at submit time. Defensive re-parse only -- failure here should be
      -- unreachable for any row that made it to valid/flagged status.
      v_date_hired_parsed := NULL;
      BEGIN
        v_date_hired_parsed := nullif(trim(coalesce(v_emp_rec.date_hired_raw, '')), '')::date;
      EXCEPTION WHEN OTHERS THEN
        v_date_hired_parsed := NULL;
      END;

      -- OHM2026_0071: Multi-step plantilla lookup
      -- Step 1: Active / On Leave / Pending Deactivation  (existing path)
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

      -- Step 2 (OHM2026_0071): Inactive / Rejected Deactivation  -- reconcile path
      -- NOTE (OHM2026_0083): New batches will never reach this path because
      -- inactive employees are now BLOCKED at review time. This branch is
      -- preserved for data-integrity safety only. Defensive revalidation
      -- (Check 3 above) will have already raised REVALIDATION_FAILED for any
      -- in-flight batch that has an inactive employee in valid/flagged rows.
      v_inactive_id := NULL;
      IF v_plantilla_id IS NULL THEN
        SELECT p_inactive.id INTO v_inactive_id
          FROM public.plantilla p_inactive
         WHERE p_inactive.employee_no = v_emp_rec.employee_no
           AND p_inactive.is_deleted = false
           AND p_inactive.status IN ('Inactive', 'Rejected Deactivation')
           AND NOT EXISTS (
             SELECT 1 FROM public.plantilla_import_batches pib2
              WHERE pib2.id = p_inactive.source_baseline_import_batch_id
                AND pib2.status = 'rolled_back'
                AND pib2.rolled_back_at IS NOT NULL
           )
         LIMIT 1;

        IF v_inactive_id IS NOT NULL THEN
          v_plantilla_id := v_inactive_id;
        END IF;
      END IF;

      -- Step 3 (OHM2026_0071): Deactivated guard -- skip with NOTICE, do not reactivate
      v_deactivated_id := NULL;
      IF v_plantilla_id IS NULL THEN
        SELECT id INTO v_deactivated_id
          FROM public.plantilla
         WHERE employee_no = v_emp_rec.employee_no
           AND is_deleted = false
           AND status = 'Deactivated'
         LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
          RAISE NOTICE
            'OHM2026_0071: Skipping employee_no=% -- existing row is Deactivated (id=%). '
            'Deactivated employees cannot be reactivated via import; manual review required.',
            v_emp_rec.employee_no, v_deactivated_id;
          v_employees_done := v_employees_done - 1;
          CONTINUE;
        END IF;
      END IF;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      v_roving_id := NULL;
      IF v_store_cnt > 1 THEN
        INSERT INTO public.import_roving_groups (
          employee_no, account_id, group_id, account_name, label,
          active_store_count, filled_hc_per_store, source_import_batch_id, created_by
        ) VALUES (
          v_emp_rec.employee_no,
          v_batch.selected_account_id, v_batch.selected_group_id,
          v_acct_name, v_emp_name || ' -- Roving',
          v_store_cnt, v_filled, p_batch_id, v_actor
        ) RETURNING id INTO v_roving_id;
      END IF;

      -- OHM2026_0065B: Roving override -- if store_count > 1, deployment_type = 'Roving'
      IF v_store_cnt > 1 THEN
        v_deployment_type := 'Roving';
      END IF;

      IF v_plantilla_id IS NULL THEN
        -- New employee: INSERT plantilla master
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          roving_assignment_id, is_pool_employee,
          position, deployment_type, has_penalty, area, area_name_snapshot,
          vcode, store_id, store_name,
          date_hired,
          civil_status, daily_rate, birthdate,
          contact_no, address, schedule, dayoff, coordinator,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        )
        SELECT
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no,
          v_acct_name, 'Active',
          v_batch.selected_account_id,
          v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          NULL, false,
          nullif(trim(coalesce(v_emp_rec.position, '')), ''),
          v_deployment_type,
          v_has_penalty,
          v_area_val,
          v_area_val,
          CASE WHEN v_store_cnt = 1 THEN r.vcode     ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN r.store_name ELSE NULL END,
          v_date_hired_parsed,
          nullif(trim(coalesce(v_emp_rec.civil_status, '')),    ''),
          v_daily_rate_parsed,
          v_birthdate_parsed,
          nullif(trim(coalesce(v_emp_rec.contact_raw, '')),     ''),
          nullif(trim(coalesce(v_emp_rec.address_raw, '')),     ''),
          nullif(trim(coalesce(v_emp_rec.schedule_raw, '')),    ''),
          nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')),      ''),
          nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), ''),
          p_batch_id, v_actor, v_actor
        FROM (
          SELECT vcode, store_name
            FROM public.plantilla_import_rows
           WHERE batch_id = p_batch_id AND employee_no = v_emp_rec.employee_no
             AND validation_status IN ('valid','flagged')
           ORDER BY row_number LIMIT 1
        ) r
        LEFT JOIN _pib_store_map sm ON sm.vcode = upper(r.vcode)
        RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);

      ELSIF v_inactive_id IS NOT NULL THEN
        -- OHM2026_0071: Inactive/Rejected Deactivation reconcile path
        -- NOTE (OHM2026_0083): Defensive Check 3 above prevents reaching this
        -- path for new batches. This branch remains for historical data-integrity
        -- completeness only.
        UPDATE public.plantilla
           SET status                    = 'Active',
               inactive_at              = NULL,
               inactive_by              = NULL,
               separation_status        = NULL,
               date_of_separation       = NULL,
               resignation_date         = NULL,
               inactive_visible_until   = NULL,
               employee_name            = v_emp_name,
               last_name                = v_emp_rec.last_name,
               first_name               = v_emp_rec.first_name,
               middle_name              = v_emp_rec.middle_name,
               position                 = COALESCE(
                                            NULLIF(trim(COALESCE(position, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                          ),
               deployment_type          = COALESCE(
                                            NULLIF(trim(COALESCE(deployment_type, '')), ''),
                                            v_deployment_type
                                          ),
               has_penalty              = COALESCE(has_penalty, v_has_penalty),
               area                     = COALESCE(
                                            NULLIF(trim(COALESCE(area, '')), ''),
                                            v_area_val
                                          ),
               area_name_snapshot       = COALESCE(
                                            NULLIF(trim(COALESCE(area_name_snapshot, '')), ''),
                                            v_area_val
                                          ),
               date_hired               = COALESCE(date_hired, v_date_hired_parsed),
               civil_status             = COALESCE(
                                            NULLIF(trim(COALESCE(civil_status, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                          ),
               daily_rate               = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate                = COALESCE(birthdate,  v_birthdate_parsed),
               contact_no               = CASE
                                            WHEN contact_no IS NOT NULL AND contact_no <> ''
                                            THEN contact_no
                                            ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                          END,
               address                  = CASE
                                            WHEN address IS NOT NULL AND address <> ''
                                            THEN address
                                            ELSE nullif(trim(coalesce(v_emp_rec.address_raw, '')), '')
                                          END,
               schedule                 = COALESCE(
                                            NULLIF(trim(COALESCE(schedule, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.schedule_raw, '')), '')
                                          ),
               dayoff                   = COALESCE(
                                            NULLIF(trim(COALESCE(dayoff, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')), '')
                                          ),
               coordinator              = COALESCE(
                                            NULLIF(trim(COALESCE(coordinator, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), '')
                                          ),
               updated_at               = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_inactive_id;

        UPDATE public.employee_deactivation_requests
           SET status     = 'Cancelled',
               updated_at = now()
         WHERE plantilla_id = v_inactive_id
           AND status IN ('Pending')
           AND is_archived = false;

        INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
        VALUES (v_uid, 'plantilla_import', 'IMPORT_REACTIVATION', v_inactive_id,
          jsonb_build_object(
            'employee_no',  v_emp_rec.employee_no,
            'previous_status', v_old_plant_snap->>'status',
            'batch_id',     p_batch_id,
            'note',         'Employee re-imported as Active; was Inactive/Rejected Deactivation'
          ));

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_inactive_id, 'reactivate', v_old_plant_snap, v_uid);

      ELSE
        -- Normal existing employee UPDATE path
        UPDATE public.plantilla
           SET employee_name    = v_emp_name,
               last_name        = v_emp_rec.last_name,
               first_name       = v_emp_rec.first_name,
               middle_name      = v_emp_rec.middle_name,
               position         = COALESCE(
                                     NULLIF(trim(COALESCE(position, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                   ),
               deployment_type  = COALESCE(
                                     NULLIF(trim(COALESCE(deployment_type, '')), ''),
                                     v_deployment_type
                                   ),
               has_penalty      = COALESCE(has_penalty, v_has_penalty),
               area             = COALESCE(
                                     NULLIF(trim(COALESCE(area, '')), ''),
                                     v_area_val
                                   ),
               area_name_snapshot = COALESCE(
                                      NULLIF(trim(COALESCE(area_name_snapshot, '')), ''),
                                      v_area_val
                                    ),
               date_hired       = COALESCE(date_hired, v_date_hired_parsed),
               civil_status     = COALESCE(
                                     NULLIF(trim(COALESCE(civil_status, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                   ),
               daily_rate       = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate        = COALESCE(birthdate,  v_birthdate_parsed),
               contact_no       = CASE
                                    WHEN contact_no IS NOT NULL AND contact_no <> ''
                                    THEN contact_no
                                    ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                  END,
               address          = CASE
                                    WHEN address IS NOT NULL AND address <> ''
                                    THEN address
                                    ELSE nullif(trim(coalesce(v_emp_rec.address_raw, '')), '')
                                  END,
               schedule         = COALESCE(
                                     NULLIF(trim(COALESCE(schedule, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.schedule_raw, '')), '')
                                   ),
               dayoff           = COALESCE(
                                     NULLIF(trim(COALESCE(dayoff, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')), '')
                                   ),
               coordinator      = COALESCE(
                                     NULLIF(trim(COALESCE(coordinator, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), '')
                                   ),
               updated_at       = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      -- ohm#k8d2x7qf: HRCO_EMAIL import assignment. Reuses the exact deactivate-old
      -- insert-new invariant as assign_hrco_to_plantilla so "one active per employee"
      -- can never be violated from the import path either (belt-and-suspenders with
      -- the partial unique index). No-op if this employee's resolved HRCO already
      -- matches their current active assignment (re-import idempotency).
      IF v_emp_rec.resolved_hrco_user_id IS NOT NULL AND v_plantilla_id IS NOT NULL THEN
        UPDATE public.plantilla_hrco_assignments
           SET is_active = false, effective_end = now()
         WHERE plantilla_id = v_plantilla_id AND is_active
           AND hrco_user_id IS DISTINCT FROM v_emp_rec.resolved_hrco_user_id;

        IF NOT EXISTS (
          SELECT 1 FROM public.plantilla_hrco_assignments
           WHERE plantilla_id = v_plantilla_id AND is_active
             AND hrco_user_id = v_emp_rec.resolved_hrco_user_id
        ) THEN
          INSERT INTO public.plantilla_hrco_assignments (
            plantilla_id, employee_no, account_id, hrco_user_id,
            hrco_email_snapshot, hrco_name_snapshot,
            assigned_by, assignment_source, source_import_batch_id
          )
          SELECT v_plantilla_id, v_emp_rec.employee_no, v_batch.selected_account_id,
                 v_emp_rec.resolved_hrco_user_id,
                 up.email, up.full_name,
                 v_actor, 'csv_import', p_batch_id
            FROM public.users_profile up
           WHERE up.auth_user_id = v_emp_rec.resolved_hrco_user_id;
        END IF;
      END IF;
      -- End ohm#k8d2x7qf HRCO_EMAIL import assignment

      IF v_roving_id IS NOT NULL THEN
        UPDATE public.import_roving_groups SET plantilla_id = v_plantilla_id
         WHERE id = v_roving_id;
      END IF;

      UPDATE public.plantilla_import_rows
         SET previous_plantilla_snapshot = v_old_plant_snap
       WHERE batch_id = p_batch_id
         AND employee_no = v_emp_rec.employee_no
         AND validation_status IN ('valid','flagged');

      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      SELECT
        p_batch_id, 'allocation', a.id, 'update', to_jsonb(a.*), v_uid
        FROM public.employee_store_allocations a
       WHERE a.employee_no = v_emp_rec.employee_no
         AND a.is_active
         AND a.account_id = v_batch.selected_account_id;

      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
       WHERE employee_no = v_emp_rec.employee_no
         AND is_active
         AND account_id = v_batch.selected_account_id;

      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, sm.store_id,
               pir.store_name, pir.resolved_account_id, pir.resolved_group_id
          FROM public.plantilla_import_rows pir
          LEFT JOIN _pib_store_map sm ON sm.vcode = upper(pir.vcode)
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid','flagged')
         ORDER BY pir.vcode, pir.row_number
      LOOP
        INSERT INTO public.employee_store_allocations (
          plantilla_id, employee_no, roving_group_id,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_plantilla_id, v_emp_rec.employee_no, v_roving_id,
          v_store_rec.store_id, v_store_rec.vcode, v_store_rec.store_name,
          COALESCE(v_store_rec.resolved_account_id, v_batch.selected_account_id),
          COALESCE(v_store_rec.resolved_group_id,   v_batch.selected_group_id),
          v_filled, v_store_cnt,
          CURRENT_DATE, true,
          p_batch_id, v_actor
        );
        v_alloc_done := v_alloc_done + 1;
      END LOOP;

      -- OHM2026_0071: S2 Slot occupancy wire
      IF v_store_cnt = 1 AND v_plantilla_id IS NOT NULL THEN
        BEGIN
          SELECT pir.vcode INTO v_slot_vcode
            FROM public.plantilla_import_rows pir
           WHERE pir.batch_id = p_batch_id
             AND pir.employee_no = v_emp_rec.employee_no
             AND pir.validation_status IN ('valid','flagged')
           ORDER BY pir.row_number
           LIMIT 1;

          IF v_slot_vcode IS NOT NULL THEN
            v_slot_id := NULL;

            SELECT id INTO v_slot_id
              FROM public.plantilla_slots
             WHERE current_occupant_plantilla_id = v_plantilla_id
               AND is_roving = false
             LIMIT 1;

            IF v_slot_id IS NULL THEN
              SELECT id INTO v_slot_id
                FROM public.plantilla_slots
               WHERE legacy_vcode = v_slot_vcode
                 AND is_roving    = false
               LIMIT 1;
            END IF;

            IF v_slot_id IS NOT NULL THEN
              DECLARE
                v_slot_current_status text;
              BEGIN
                SELECT slot_status INTO v_slot_current_status
                  FROM public.plantilla_slots
                 WHERE id = v_slot_id;

                IF v_slot_current_status = 'occupied'
                   AND (SELECT current_occupant_plantilla_id FROM public.plantilla_slots WHERE id = v_slot_id) = v_plantilla_id THEN
                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% already occupied by plantilla_id=% (vcode=%)',
                    v_slot_id, v_plantilla_id, v_slot_vcode;

                ELSIF v_slot_current_status = 'closed' THEN
                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% is closed, skipping occupancy wire for plantilla_id=% (vcode=%)',
                    v_slot_id, v_plantilla_id, v_slot_vcode;

                ELSE
                  UPDATE public.plantilla_slots
                     SET slot_status                   = 'occupied',
                         current_occupant_plantilla_id = v_plantilla_id,
                         updated_at                    = now(),
                         updated_by                    = v_actor
                   WHERE id = v_slot_id;

                  INSERT INTO public.slot_history (
                    slot_id, account_id, action_type, old_value, new_value,
                    reason_code, performed_by, remarks, created_at
                  ) VALUES (
                    v_slot_id,
                    v_batch.selected_account_id,
                    'occupied',
                    v_slot_current_status,
                    'occupied',
                    'IMPORT_OCCUPIED',
                    v_actor,
                    format(
                      'OHM2026_0071 import slot wire: batch_id=%s employee_no=%s plantilla_id=%s',
                      p_batch_id::text, v_emp_rec.employee_no, v_plantilla_id::text
                    ),
                    now()
                  );

                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% transitioned %->occupied for plantilla_id=% (vcode=%)',
                    v_slot_id, v_slot_current_status, v_plantilla_id, v_slot_vcode;
                END IF;
              END;

            ELSE
              SELECT sm.store_id INTO v_slot_store_id
                FROM _pib_store_map sm
               WHERE sm.vcode = upper(v_slot_vcode)
               LIMIT 1;

              SELECT COALESCE(MAX(ps.slot_ordinal), 0) + 1 INTO v_slot_ordinal
                FROM public.plantilla_slots ps
               WHERE ps.legacy_vcode = v_slot_vcode;

              INSERT INTO public.plantilla_slots (
                store_id, account_id, group_id,
                position, employment_type, is_roving,
                slot_status, slot_ordinal, legacy_vcode,
                current_occupant_plantilla_id,
                created_at, updated_at, created_by, updated_by
              ) VALUES (
                v_slot_store_id,
                v_batch.selected_account_id,
                v_batch.selected_group_id,
                COALESCE(nullif(trim(coalesce(v_emp_rec.position, '')), ''), 'Unknown'),
                COALESCE(lower(nullif(trim(coalesce(v_emp_rec.employment_type_raw, '')), '')), 'stationary'),
                false,
                'occupied',
                v_slot_ordinal::smallint,
                v_slot_vcode,
                v_plantilla_id,
                now(), now(),
                v_actor, v_actor
              )
              RETURNING id INTO v_slot_id;

              INSERT INTO public.slot_history (
                slot_id, account_id, action_type, old_value, new_value,
                reason_code, performed_by, remarks, created_at
              ) VALUES (
                v_slot_id,
                v_batch.selected_account_id,
                'occupied',
                NULL,
                'occupied',
                'IMPORT_OCCUPIED',
                v_actor,
                format(
                  'OHM2026_0071 new slot created by import: batch_id=%s employee_no=%s plantilla_id=%s',
                  p_batch_id::text, v_emp_rec.employee_no, v_plantilla_id::text
                ),
                now()
              );

              RAISE NOTICE
                'OHM2026_0071 slot wire: created new slot_id=% (occupied) for plantilla_id=% (vcode=%)',
                v_slot_id, v_plantilla_id, v_slot_vcode;
            END IF;
          END IF;

        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE
            'OHM2026_0071 slot wire: non-fatal error for employee_no=% plantilla_id=% -- % (sqlstate=%)',
            v_emp_rec.employee_no, v_plantilla_id, SQLERRM, SQLSTATE;
        END;
      END IF;
      -- End OHM2026_0071 slot wire

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'plantilla_import', 'APPROVAL', v_plantilla_id,
        jsonb_build_object(
          'employee_no',         v_emp_rec.employee_no,
          'store_count',         v_store_cnt,
          'filled_hc_per_store', v_filled,
          'roving',              (v_roving_id IS NOT NULL),
          'batch_id',            p_batch_id,
          'reconciled',          (v_inactive_id IS NOT NULL)
        ));
    END LOOP;

    UPDATE public.plantilla_import_batches
       SET status             = 'approved',
           approved_by        = v_uid,
           approved_at        = now(),
           committed_stores   = v_stores_done,
           committed_employees= v_employees_done,
           rollback_ready     = true,
           updated_at         = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'plantilla_import_batches', 'APPROVAL', p_batch_id,
      jsonb_build_object(
        'stores',      v_stores_done,
        'employees',   v_employees_done,
        'allocations', v_alloc_done
      ));

    RETURN jsonb_build_object(
      'batch_id',            p_batch_id,
      'status',              'approved',
      'stores_committed',    v_stores_done,
      'employees_committed', v_employees_done,
      'allocations_created', v_alloc_done
    );

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;

    -- REVALIDATION_FAILED is already human-readable; return verbatim.
    IF v_err_state = '55000'
       AND position('REVALIDATION_FAILED' IN COALESCE(v_err_msg,'')) > 0
    THEN
      v_err_out := v_err_msg;
    ELSIF v_err_state = '23505'
       AND position('uq_plantilla_vcode_active_occupied' IN COALESCE(v_err_msg,'')) > 0
    THEN
      v_err_out := 'VCODE_ALREADY_OCCUPIED: a VCODE in this batch is already held '
                || 'by another active employee in plantilla -- only one active '
                || 'occupancy per VCODE is allowed';
    ELSE
      v_err_out := format('[%s] %s', v_err_state, v_err_msg);
    END IF;

    UPDATE public.plantilla_import_batches
       SET status              = 'commit_failed',
           commit_error_detail = v_err_out,
           updated_at          = now()
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id', p_batch_id,
      'status',   'commit_failed',
      'error',    v_err_out
    );
  END;

END$function$;

COMMIT;
