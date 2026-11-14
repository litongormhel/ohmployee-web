-- Migration: 20262606000069_support_vacant_slot_plantilla_import
-- Created: 2026-10-23
-- Purpose: Support Vacant Store Slots in Plantilla Baseline Import (Full Parity with Legacy Store Import & ADR-001)
--   1. submit_plantilla_baseline_import:
--      - Accepts baseline vacant store slot rows (only 10 store columns populated, employee fields blank).
--      - Safeguard 1: Strict vacant vs. partial employee detection.
--        Blocks partial employee details missing EMPLOYEE_NO.
--      - Removes hardblock 'store row has no employee - every VCODE must have an assigned employee'.
--   2. approve_plantilla_import_batch:
--      - Allows committable batches with vacant slots (vcode IS NOT NULL).
--      - Phase A.2: Provisions vacant plantilla_slots with status='open' up to required_hc (incrementing slot_ordinal).
--      - Idempotently creates/syncs public.vacancies with status='Open' so vw_slot_derived_vacancy_shadow surfaces the open slot.
--   3. rollback_plantilla_import_batch:
--      - Reverses created vacant slots (status='closed', reason='IMPORT_ROLLBACK') and vacancies if unoccupied.

BEGIN;

-- 1. Seed reason codes for slot history & closure
INSERT INTO public.slot_reason_codes (code, label, description)
VALUES 
  ('IMPORT_OPEN', 'Imported Open', 'Slot created as open via plantilla baseline import.'),
  ('IMPORT_ROLLBACK', 'Import Rollback', 'Slot closed via plantilla baseline import rollback.')
ON CONFLICT (code) DO NOTHING;

-- 2. Expand entity_type check constraint on commit snapshots
ALTER TABLE public.plantilla_import_commit_snapshots DROP CONSTRAINT IF EXISTS pics_entity_check;
ALTER TABLE public.plantilla_import_commit_snapshots ADD CONSTRAINT pics_entity_check CHECK (entity_type IN ('store', 'plantilla', 'allocation', 'slot', 'vacancy'));

-- 3. Update submit_plantilla_baseline_import
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

  -- In-memory pre-pass structures (avoids temp tables & broad DDL/DML)
  v_dup_vcodes           text[] := '{}';
  v_emp_cov              jsonb  := '{}'::jsonb;
  v_seen_pairs           text[] := '{}';
  v_active_owners        jsonb  := '{}'::jsonb;
  v_rollback_safe_vcodes text[] := '{}';
  v_blocked_vcodes       text[] := '{}';

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

  -- Pre-passes (in-memory)

  -- [A] Duplicate VCODEs within this upload (all occurrences will be blocked)
  SELECT COALESCE(array_agg(vcode), '{}') INTO v_dup_vcodes
  FROM (
    SELECT upper(trim(elem->>'VCODE')) AS vcode
    FROM jsonb_array_elements(p_rows) elem
    WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
    GROUP BY 1 HAVING count(*) > 1
  ) d;

  -- [B] Employee -> store coverage (roving detection)
  SELECT COALESCE(jsonb_object_agg(emp, store_count), '{}'::jsonb) INTO v_emp_cov
  FROM (
    SELECT
      upper(trim(elem->>'EMPLOYEE_NO')) AS emp,
      count(DISTINCT upper(trim(elem->>'VCODE'))) AS store_count
    FROM jsonb_array_elements(p_rows) elem
    WHERE NULLIF(trim(elem->>'EMPLOYEE_NO'),'') IS NOT NULL
      AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
    GROUP BY 1
  ) c;

  -- [D] VCODEs actively assigned in the live system: vcode -> employee_no
  SELECT COALESCE(jsonb_object_agg(upper(trim(a.vcode)), upper(trim(a.employee_no))), '{}'::jsonb) INTO v_active_owners
  FROM public.employee_store_allocations a
  WHERE a.is_active
    AND a.vcode IS NOT NULL
    AND a.employee_no IS NOT NULL;

  -- [E] OHM2026_0079: Rollback-safe VCodes
  SELECT COALESCE(array_agg(upper(trim(vv.vcode))), '{}') INTO v_rollback_safe_vcodes
  FROM public.vacancies vv
  JOIN public.vacancy_import_batches vib ON vib.id = vv.source_vacancy_import_batch_id
  WHERE vv.vcode IS NOT NULL
    AND vv.deleted_at IS NOT NULL
    AND vib.rollback_status = 'completed';

  -- [F] OHM2026_0079: Blocked (archived/non-reusable) VCodes
  SELECT COALESCE(array_agg(upper(trim(vv.vcode))), '{}') INTO v_blocked_vcodes
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

    IF v_vcode IS NOT NULL AND (v_vcode = ANY(v_dup_vcodes)) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"duplicate VCODE in upload - each VCODE must appear exactly once"}]'::jsonb;
    END IF;

    IF v_vcode IS NOT NULL AND (
      (v_emp IS NULL AND v_active_owners ? v_vcode)
      OR (v_emp IS NOT NULL AND (v_active_owners ? v_vcode) AND (v_active_owners->>v_vcode) <> v_emp)
    ) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE already actively assigned to an employee in plantilla"}]'::jsonb;
    END IF;

    -- OHM2026_0079: VCode archived/non-reusable conflict blocking
    IF v_vcode IS NOT NULL
       AND NOT (v_active_owners ? v_vcode AND (v_emp IS NULL OR (v_active_owners->>v_vcode) <> v_emp))
    THEN
      IF (v_vcode = ANY(v_rollback_safe_vcodes)) THEN
        v_flags := v_flags || jsonb_build_array(jsonb_build_object(
          'flag',         'rollback_safe_vcode',
          'conflict_type','rollback_safe_vcode',
          'msg',          'Rollback record detected - eligible for re-upload.'
        ));
      ELSIF (v_vcode = ANY(v_blocked_vcodes)) THEN
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
       AND ((v_emp || ':' || v_vcode) = ANY(v_seen_pairs))
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
        v_store_cnt := COALESCE((v_emp_cov->>v_emp)::int, 0);
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
        v_seen_pairs := array_append(v_seen_pairs, v_emp || ':' || v_vcode);
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
    FROM jsonb_each_text(v_emp_cov) WHERE value::int > 1;

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

-- 4. Update approve_plantilla_import_batch
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
  v_vrow               record;
  v_vrow_store_id      uuid;
  v_vrow_emp_type      text;
  v_existing_slot_cnt  int;
  v_vac_id             uuid;
  v_new_vac_id         uuid;
  v_new_slot_id        uuid;
  v_old_vac_snap       jsonb;
  v_store_map          jsonb := '{}'::jsonb;
  v_slot_idx           int;
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

  -- Normalised middle name
  v_middle_norm        text;

  -- Position_id FK resolution
  v_position_id        uuid;

  -- Commit counts
  v_committable int;

  -- VCODE resolution guard
  v_unresolved_vcode text;

  -- Humanised error
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;

  -- Inactive reconcile path
  v_inactive_id      uuid;
  v_deactivated_id   uuid;

  -- Slot occupancy wire
  v_slot_id          uuid;
  v_slot_vcode       text;
  v_slot_result      jsonb;
  v_slot_ordinal     int;
  v_slot_store_id    uuid;

  -- Defensive revalidation
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
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch (valid+flagged with vcode)'
      USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;



  -- Inner exception block -- all commit DML is atomic
  BEGIN

    -- Defensive revalidation
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

        v_store_map := jsonb_set(v_store_map, ARRAY[upper(v_srow.vcode)], to_jsonb(v_new_store_id));

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

        v_store_map := jsonb_set(v_store_map, ARRAY[upper(v_srow.vcode)], to_jsonb(v_existing_store_id));

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

    -- VCODE resolution guard
    SELECT r.vcode INTO v_unresolved_vcode
      FROM public.plantilla_import_rows r
     WHERE r.batch_id = p_batch_id
       AND r.validation_status IN ('valid','flagged')
       AND r.vcode IS NOT NULL
       AND NOT (v_store_map ? upper(r.vcode))
     LIMIT 1;

    IF v_unresolved_vcode IS NOT NULL THEN
      RAISE EXCEPTION 'STORE_RESOLUTION_FAILED: VCODE % not resolved after store upsert — cannot commit plantilla rows',
        v_unresolved_vcode
        USING ERRCODE = '23503';
    END IF;

    -- ── Phase A.2: Vacant Slot & Vacancy Provisioning (ADR-001) ─────────────
    -- For rows with vcode and NO employee assigned (vacant store slots):
    FOR v_vrow IN
      SELECT
        upper(trim(vcode)) AS vcode,
        (array_agg(store_name ORDER BY row_number))[1] AS store_name,
        (array_agg(position ORDER BY row_number) FILTER (WHERE position IS NOT NULL))[1] AS position,
        (array_agg(employment_type ORDER BY row_number) FILTER (WHERE employment_type IS NOT NULL))[1] AS employment_type_raw,
        MAX(COALESCE(NULLIF(regexp_replace(COALESCE(required_hc_raw,''),'[^0-9]','','g'), '')::int, 1)) AS req_hc,
        (array_agg(id ORDER BY row_number))[1] AS row_id
      FROM public.plantilla_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND employee_no IS NULL
       AND vcode IS NOT NULL
     GROUP BY upper(trim(vcode))
    LOOP
      v_vrow_store_id := (v_store_map->>v_vrow.vcode)::uuid;

      v_vrow_emp_type := CASE
        WHEN lower(COALESCE(v_vrow.employment_type_raw, '')) = 'roving' THEN 'Roving'
        ELSE 'Stationary'
      END;

      -- 1. Provision plantilla_slots for vacant slot (up to required_hc)
      SELECT count(*) INTO v_existing_slot_cnt
        FROM public.plantilla_slots
       WHERE legacy_vcode = v_vrow.vcode
         AND slot_status <> 'closed';

      IF v_existing_slot_cnt < v_vrow.req_hc THEN
        FOR v_slot_idx IN 1 .. (v_vrow.req_hc - v_existing_slot_cnt) LOOP
          SELECT COALESCE(MAX(ps.slot_ordinal), 0) + 1 INTO v_slot_ordinal
            FROM public.plantilla_slots ps
           WHERE ps.legacy_vcode = v_vrow.vcode;

          v_new_slot_id := gen_random_uuid();

          INSERT INTO public.plantilla_slots (
            id, store_id, account_id, group_id,
            position, employment_type, is_roving,
            slot_status, slot_ordinal, legacy_vcode,
            current_occupant_plantilla_id,
            created_at, updated_at, created_by, updated_by
          ) VALUES (
            v_vrow_store_id, v_batch.selected_account_id, v_batch.selected_group_id,
            v_vrow.position, v_vrow_emp_type, (v_vrow_emp_type = 'Roving'),
            'open', v_slot_ordinal, v_vrow.vcode,
            NULL,
            now(), now(), v_actor, v_actor
          );

          INSERT INTO public.slot_history (
            slot_id, account_id, action_type, old_value, new_value,
            reason_code, performed_by, remarks, created_at
          ) VALUES (
            v_new_slot_id, v_batch.selected_account_id, 'open', NULL, 'open',
            'IMPORT_OPEN', v_actor,
            format('Baseline import batch %s: vacant slot created (ordinal %s)', p_batch_id, v_slot_ordinal),
            now()
          );

          INSERT INTO public.plantilla_import_commit_snapshots (
            batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by
          ) VALUES (
            p_batch_id, v_vrow.row_id, 'slot', v_new_slot_id, 'insert', NULL, v_uid
          );
        END LOOP;
      END IF;

      -- 2. Vacancies table idempotent sync so vw_slot_derived_vacancy_shadow surfaces the open slot
      SELECT id INTO v_vac_id
        FROM public.vacancies
       WHERE upper(trim(vcode)) = v_vrow.vcode
       LIMIT 1;

      IF v_vac_id IS NULL THEN
        v_new_vac_id := gen_random_uuid();
        INSERT INTO public.vacancies (
          id, vcode, account, account_id, group_id,
          store_id, store_name, position, status,
          required_headcount, employment_type,
          created_at, updated_at, created_by, updated_by
        ) VALUES (
          v_new_vac_id, v_vrow.vcode, v_acct_name, v_batch.selected_account_id, v_batch.selected_group_id,
          v_vrow_store_id, v_vrow.store_name, v_vrow.position, 'Open',
          v_vrow.req_hc, v_vrow_emp_type,
          now(), now(), v_actor, v_actor
        );

        INSERT INTO public.plantilla_import_commit_snapshots (
          batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by
        ) VALUES (
          p_batch_id, v_vrow.row_id, 'vacancy', v_new_vac_id, 'insert', NULL, v_uid
        );
      ELSE
        SELECT to_jsonb(v.*) INTO v_old_vac_snap FROM public.vacancies v WHERE id = v_vac_id;

        UPDATE public.vacancies
           SET store_id = v_vrow_store_id,
               store_name = v_vrow.store_name,
               position = COALESCE(v_vrow.position, position),
               required_headcount = GREATEST(required_headcount, v_vrow.req_hc),
               status = CASE WHEN status IN ('Archived', 'Closed', 'Filled') THEN 'Open' ELSE status END,
               is_archived = false,
               deleted_at = NULL,
               updated_at = now(),
               updated_by = v_actor
         WHERE id = v_vac_id;

        INSERT INTO public.plantilla_import_commit_snapshots (
          batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by
        ) VALUES (
          p_batch_id, v_vrow.row_id, 'vacancy', v_vac_id, 'update', v_old_vac_snap, v_uid
        );
      END IF;
    END LOOP;

    -- ── Phase B: Employee / plantilla upsert ──────────────────────────────────
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number)
           FILTER (WHERE middle_name IS NOT NULL))[1]                              AS middle_name,
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

      v_middle_norm := NULLIF(trim(COALESCE(v_emp_rec.middle_name, '')), '');
      IF upper(COALESCE(v_middle_norm, '')) IN ('NA', 'N/A', 'N.A.', 'N.A') THEN
        v_middle_norm := NULL;
      END IF;

      v_emp_name := trim(COALESCE(v_emp_rec.last_name, ''))
                    || ', '
                    || trim(COALESCE(v_emp_rec.first_name, ''))
                    || CASE
                         WHEN v_middle_norm IS NOT NULL
                         THEN ' ' || trim(v_middle_norm)
                         ELSE ''
                       END;

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

      v_date_hired_parsed := NULL;
      BEGIN
        v_date_hired_parsed := nullif(trim(coalesce(v_emp_rec.date_hired_raw, '')), '')::date;
      EXCEPTION WHEN OTHERS THEN
        v_date_hired_parsed := NULL;
      END;

      -- Position_id FK resolution
      v_position_id := NULL;
      IF NULLIF(trim(COALESCE(v_emp_rec.position, '')), '') IS NOT NULL THEN
        SELECT pos.id INTO v_position_id
          FROM public.positions pos
         WHERE lower(trim(pos.position_name)) = lower(trim(v_emp_rec.position))
           AND COALESCE(pos.is_active, true) = true
         LIMIT 1;

        IF v_position_id IS NULL THEN
          RAISE EXCEPTION
            'POSITION_NOT_FOUND: position "%" (employee_no %) does not match any active row in positions.position_name -- add it to Position Master before importing',
            v_emp_rec.position, v_emp_rec.employee_no
            USING ERRCODE = '23503';
        END IF;
      END IF;

      -- Plantilla lookup
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

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

      IF v_store_cnt > 1 THEN
        v_deployment_type := 'Roving';
      END IF;

      IF v_plantilla_id IS NULL THEN
        -- New employee insert
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          roving_assignment_id, is_pool_employee,
          position, position_id, deployment_type, has_penalty, area, area_name_snapshot,
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
          nullif(trim(coalesce(v_emp_rec.position, '')), ''), v_position_id,
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
        LEFT JOIN LATERAL (SELECT (v_store_map->>upper(r.vcode))::uuid AS store_id) sm ON true
        RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);

      ELSIF v_inactive_id IS NOT NULL THEN
        -- Inactive employee reactivation path
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
               position_id              = COALESCE(position_id, v_position_id),
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
        -- Normal existing employee update
        UPDATE public.plantilla
           SET employee_name    = v_emp_name,
               last_name        = v_emp_rec.last_name,
               first_name       = v_emp_rec.first_name,
               middle_name      = v_emp_rec.middle_name,
               position         = COALESCE(
                                     NULLIF(trim(COALESCE(position, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                   ),
               position_id      = COALESCE(position_id, v_position_id),
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

      -- HRCO email assignments
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
               pir.vcode, (v_store_map->>upper(pir.vcode))::uuid AS store_id,
               pir.store_name, pir.resolved_account_id, pir.resolved_group_id
          FROM public.plantilla_import_rows pir
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

      -- Slot occupancy wire
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
                  SELECT public.fn_set_slot_status(v_slot_id, 'occupied', v_plantilla_id)
                    INTO v_slot_result;
                END IF;
              END;
            END IF;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          GET STACKED DIAGNOSTICS v_err_state = RETURNED_SQLSTATE,
                                  v_err_msg   = MESSAGE_TEXT;
          RAISE NOTICE 'OHM2026_0071 slot wire non-fatal: employee_no=% vcode=% state=% msg=%',
            v_emp_rec.employee_no, v_slot_vcode, v_err_state, v_err_msg;
        END;
      END IF;

    END LOOP;

    UPDATE public.plantilla_import_batches
       SET status       = 'approved',
           approved_by  = v_uid,
           approved_at  = now(),
           updated_at   = now()
     WHERE id = p_batch_id;

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;

    v_err_out := format('[%s] %s', v_err_state, v_err_msg);

    UPDATE public.plantilla_import_batches
       SET status             = 'commit_failed', -- Fixed status here (was 'commit_error')
           commit_error_detail = v_err_out,
           updated_at          = now()
     WHERE id = p_batch_id;

    RAISE;
  END;

  RETURN jsonb_build_object(
    'ok',              true,
    'batch_id',        p_batch_id,
    'stores_created',  v_stores_done,
    'employees_done',  v_employees_done,
    'allocations_done',v_alloc_done
  );
END$function$
;;

-- 5. Update rollback_plantilla_import_batch
CREATE OR REPLACE FUNCTION public.rollback_plantilla_import_batch(p_batch_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_actor uuid := public.get_current_profile_id();
  v_batch public.plantilla_import_batches%ROWTYPE;
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
  v_archive_reason text;

  v_plantilla_restored      int := 0;
  v_plantilla_archived      int := 0;
  v_stores_restored         int := 0;
  v_stores_deactivated      int := 0;
  v_allocations_restored    int := 0;
  v_allocations_deactivated int := 0;
  v_roving_groups_archived  int := 0;
BEGIN
  -- Auth
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Lock + state check
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches
   WHERE id = p_batch_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  IF NOT COALESCE(v_batch.rollback_ready, false) THEN
    RAISE EXCEPTION 'ROLLBACK_NOT_READY: batch has no completed rollback lineage'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
  ) THEN
    RAISE EXCEPTION 'ROLLBACK_NOT_READY: no commit snapshots found for batch'
      USING ERRCODE = '22023';
  END IF;

  v_archive_reason := 'Import batch rollback'
    || CASE WHEN v_reason IS NULL THEN '' ELSE ': ' || v_reason END;

  UPDATE public.plantilla_import_batches
     SET status = 'rollback_pending',
         rollback_error_detail = NULL,
         rollback_reason = v_reason,
         updated_at = now()
   WHERE id = p_batch_id;

  -- Entity rollback block. Any error rolls back all entity changes.
  BEGIN
    -- Refuse to restore older state if another import has superseded this one.
    IF EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.plantilla p ON p.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'plantilla'
         AND s.action = 'update'
         AND (
           p.source_baseline_import_batch_id IS DISTINCT FROM p_batch_id
           OR p.updated_at > COALESCE(v_batch.approved_at, v_batch.updated_at)
         )
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: plantilla state has been superseded after batch %',
        p_batch_id USING ERRCODE = '40001';
    END IF;

    IF EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.stores st ON st.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'store'
         AND s.action = 'update'
         AND (
           st.source_import_id IS DISTINCT FROM p_batch_id
           OR st.updated_at > COALESCE(v_batch.approved_at, v_batch.updated_at)
         )
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: store state has been superseded after batch %',
        p_batch_id USING ERRCODE = '40001';
    END IF;

    IF EXISTS (
      SELECT 1
        FROM (
          SELECT DISTINCT employee_no, upper(trim(vcode)) AS vcode
            FROM public.plantilla_import_rows
           WHERE batch_id = p_batch_id
             AND validation_status IN ('valid','flagged')
             AND employee_no IS NOT NULL
             AND vcode IS NOT NULL
        ) target_alloc
        JOIN public.employee_store_allocations a
          ON a.employee_no = target_alloc.employee_no
         AND a.account_id = v_batch.selected_account_id
         AND upper(trim(a.vcode)) = target_alloc.vcode
         AND a.is_active
       WHERE a.source_import_batch_id IS DISTINCT FROM p_batch_id
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: target batch allocations have been superseded after batch %',
        p_batch_id USING ERRCODE = '40001';
    END IF;

    -- Batch-created allocations: preserve history, deactivate only.
    UPDATE public.employee_store_allocations a
       SET is_active     = false,
           effective_end = CURRENT_DATE
     WHERE a.source_import_batch_id = p_batch_id
       AND a.is_active;
    GET DIAGNOSTICS v_allocations_deactivated = ROW_COUNT;

    -- Batch-updated allocations: restore the exact prior allocation rows.
    WITH snap AS (
      SELECT
        s.entity_id,
        jsonb_populate_record(NULL::public.employee_store_allocations, s.previous_snapshot) AS r
      FROM public.plantilla_import_commit_snapshots s
      WHERE s.batch_id = p_batch_id
        AND s.entity_type = 'allocation'
        AND s.action = 'update'
        AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.employee_store_allocations a
       SET plantilla_id            = (snap.r).plantilla_id,
           employee_no             = (snap.r).employee_no,
           roving_group_id         = (snap.r).roving_group_id,
           store_id                = (snap.r).store_id,
           vcode                   = (snap.r).vcode,
           store_name              = (snap.r).store_name,
           account_id              = (snap.r).account_id,
           group_id                = (snap.r).group_id,
           filled_hc               = (snap.r).filled_hc,
           active_store_count      = (snap.r).active_store_count,
           effective_start         = (snap.r).effective_start,
           effective_end           = (snap.r).effective_end,
           is_active               = (snap.r).is_active,
           source_import_batch_id  = (snap.r).source_import_batch_id,
           created_at              = (snap.r).created_at,
           created_by              = (snap.r).created_by
      FROM snap
     WHERE a.id = snap.entity_id;
    GET DIAGNOSTICS v_allocations_restored = ROW_COUNT;

    -- Batch-created plantilla rows: soft archive, never hard delete.
    UPDATE public.plantilla p
       SET is_archived   = true,
           archived_at   = now(),
           archived_by   = v_actor,
           archive_reason = v_archive_reason,
           status        = 'Inactive',
           updated_at    = now(),
           updated_by    = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'plantilla'
       AND s.action = 'insert'
       AND s.entity_id = p.id
       AND p.source_baseline_import_batch_id = p_batch_id
       AND COALESCE(p.is_archived, false) = false;
    GET DIAGNOSTICS v_plantilla_archived = ROW_COUNT;

    -- Batch-updated plantilla rows: restore the prior row snapshot.
    WITH snap AS (
      SELECT
        s.entity_id,
        jsonb_populate_record(NULL::public.plantilla, s.previous_snapshot) AS r
      FROM public.plantilla_import_commit_snapshots s
      WHERE s.batch_id = p_batch_id
        AND s.entity_type = 'plantilla'
        AND s.action = 'update'
        AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.plantilla p
       SET employee_name                   = (snap.r).employee_name,
           employee_no                     = (snap.r).employee_no,
           account                         = (snap.r).account,
           status                          = (snap.r).status,
           emploc_no                       = (snap.r).emploc_no,
           vcode                           = (snap.r).vcode,
           position                        = (snap.r).position,
           created_at                      = (snap.r).created_at,
           hr_emploc_id                    = (snap.r).hr_emploc_id,
           vacancy_id                      = (snap.r).vacancy_id,
           vacancy_code_snapshot           = (snap.r).vacancy_code_snapshot,
           employee_name_snapshot          = (snap.r).employee_name_snapshot,
           account_id                      = (snap.r).account_id,
           chain_id                        = (snap.r).chain_id,
           store_id                        = (snap.r).store_id,
           province_id                     = (snap.r).province_id,
           area_name_snapshot              = (snap.r).area_name_snapshot,
           hrco_user_id_snapshot           = (snap.r).hrco_user_id_snapshot,
           om_user_id_snapshot             = (snap.r).om_user_id_snapshot,
           atl_user_id_snapshot            = (snap.r).atl_user_id_snapshot,
           position_id                     = (snap.r).position_id,
           rest_day                        = (snap.r).rest_day,
           resignation_date                = (snap.r).resignation_date,
           remarks                         = (snap.r).remarks,
           moved_by_user_id                = (snap.r).moved_by_user_id,
           created_by                      = (snap.r).created_by,
           updated_at                      = (snap.r).updated_at,
           updated_by                      = (snap.r).updated_by,
           store_name                      = (snap.r).store_name,
           area                            = (snap.r).area,
           rate                            = (snap.r).rate,
           schedule                        = (snap.r).schedule,
           deployment_type                 = (snap.r).deployment_type,
           has_penalty                     = (snap.r).has_penalty,
           date_hired                      = (snap.r).date_hired,
           coordinator                     = (snap.r).coordinator,
           hrco_name                       = (snap.r).hrco_name,
           last_name                       = (snap.r).last_name,
           first_name                      = (snap.r).first_name,
           middle_name                     = (snap.r).middle_name,
           date_of_separation              = (snap.r).date_of_separation,
           separation_status               = (snap.r).separation_status,
           tagged_at                       = (snap.r).tagged_at,
           inactive_at                     = (snap.r).inactive_at,
           inactive_by                     = (snap.r).inactive_by,
           for_deactivation_at             = (snap.r).for_deactivation_at,
           for_deactivation_by             = (snap.r).for_deactivation_by,
           deactivated_at                  = (snap.r).deactivated_at,
           deactivated_by                  = (snap.r).deactivated_by,
           deactivated_visible_until       = (snap.r).deactivated_visible_until,
           last_mika_synced_at             = (snap.r).last_mika_synced_at,
           last_mika_synced_by             = (snap.r).last_mika_synced_by,
           source_headcount_request_id     = (snap.r).source_headcount_request_id,
           is_deleted                      = (snap.r).is_deleted,
           over_headcount                  = (snap.r).over_headcount,
           deactivation_reason             = (snap.r).deactivation_reason,
           deletion_requested_at           = (snap.r).deletion_requested_at,
           deletion_requested_by           = (snap.r).deletion_requested_by,
           deletion_reason                 = (snap.r).deletion_reason,
           deletion_remarks                = (snap.r).deletion_remarks,
           deletion_approved_at            = (snap.r).deletion_approved_at,
           deletion_approved_by            = (snap.r).deletion_approved_by,
           sss_no                          = (snap.r).sss_no,
           philhealth_no                   = (snap.r).philhealth_no,
           pagibig_no                      = (snap.r).pagibig_no,
           atm_no                          = (snap.r).atm_no,
           civil_status                    = (snap.r).civil_status,
           date_of_birth                   = (snap.r).date_of_birth,
           transferred_from_store_id       = (snap.r).transferred_from_store_id,
           last_transfer_at                = (snap.r).last_transfer_at,
           last_transfer_by                = (snap.r).last_transfer_by,
           inactive_visible_until          = (snap.r).inactive_visible_until,
           is_archived                     = (snap.r).is_archived,
           archived_at                     = (snap.r).archived_at,
           archived_by                     = (snap.r).archived_by,
           archive_reason                  = (snap.r).archive_reason,
           restored_at                     = (snap.r).restored_at,
           restored_by                     = (snap.r).restored_by,
           source_baseline_import_batch_id = (snap.r).source_baseline_import_batch_id,
           roving_assignment_id            = (snap.r).roving_assignment_id,
           is_pool_employee                = (snap.r).is_pool_employee
      FROM snap
     WHERE p.id = snap.entity_id
       AND p.source_baseline_import_batch_id = p_batch_id;
    GET DIAGNOSTICS v_plantilla_restored = ROW_COUNT;

    -- Batch-updated stores: restore the prior row snapshot.
    -- NOTE: `type` is NOT a column of public.stores and is intentionally
    -- excluded from this SET list. OHM2026_0075 smoke-test fix.
    WITH snap AS (
      SELECT
        s.entity_id,
        jsonb_populate_record(NULL::public.stores, s.previous_snapshot) AS r
      FROM public.plantilla_import_commit_snapshots s
      WHERE s.batch_id = p_batch_id
        AND s.entity_type = 'store'
        AND s.action = 'update'
        AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.stores st
       SET account_id       = (snap.r).account_id,
           store_name       = (snap.r).store_name,
           store_branch     = (snap.r).store_branch,
           area_city        = (snap.r).area_city,
           province         = (snap.r).province,
           is_active        = (snap.r).is_active,
           created_at       = (snap.r).created_at,
           updated_at       = (snap.r).updated_at,
           group_id         = (snap.r).group_id,
           hrco_user_id     = (snap.r).hrco_user_id,
           om_user_id       = (snap.r).om_user_id,
           vcode            = (snap.r).vcode,
           area_province    = (snap.r).area_province,
           with_penalty     = (snap.r).with_penalty,
           status           = (snap.r).status,
           created_by       = (snap.r).created_by,
           updated_by       = (snap.r).updated_by,
           approved_by      = (snap.r).approved_by,
           approved_at      = (snap.r).approved_at,
           source_import_id = (snap.r).source_import_id,
           employment_type  = (snap.r).employment_type
      FROM snap
     WHERE st.id = snap.entity_id
       AND st.source_import_id = p_batch_id;
    GET DIAGNOSTICS v_stores_restored = ROW_COUNT;

    -- Batch-created stores: deactivate only when no active plantilla/allocation remains.
    UPDATE public.stores st
       SET is_active   = false,
           status      = 'archived',
           updated_at  = now(),
           updated_by  = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'store'
       AND s.action = 'insert'
       AND s.entity_id = st.id
       AND st.source_import_id = p_batch_id
       AND NOT EXISTS (
         SELECT 1
           FROM public.plantilla p
          WHERE p.store_id = st.id
            AND p.status IN ('Active','Pending Deactivation','On Leave','For Deactivation')
            AND COALESCE(p.is_archived, false) = false
            AND COALESCE(p.is_deleted, false) = false
       )
       AND NOT EXISTS (
         SELECT 1
           FROM public.employee_store_allocations a
          WHERE a.store_id = st.id
            AND a.is_active
       );
    GET DIAGNOSTICS v_stores_deactivated = ROW_COUNT;

    -- Batch-created plantilla slots: close if unoccupied
    UPDATE public.plantilla_slots ps
       SET slot_status         = 'closed',
           closure_reason_code = 'IMPORT_ROLLBACK',
           closed_at           = now(),
           updated_at          = now(),
           updated_by          = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'slot'
       AND s.action = 'insert'
       AND s.entity_id = ps.id
       AND ps.slot_status = 'open'
       AND ps.current_occupant_plantilla_id IS NULL;

    -- Batch-created vacancies: archive if still open
    UPDATE public.vacancies v
       SET status     = 'Archived',
           is_archived = true,
           deleted_at = now(),
           updated_at = now(),
           updated_by = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'vacancy'
       AND s.action = 'insert'
       AND s.entity_id = v.id
       AND v.status = 'Open';

    -- Batch-updated vacancies: restore previous snapshot
    WITH snap AS (
      SELECT s.entity_id, jsonb_populate_record(NULL::public.vacancies, s.previous_snapshot) AS r
        FROM public.plantilla_import_commit_snapshots s
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'vacancy'
         AND s.action = 'update'
         AND s.previous_snapshot IS NOT NULL
    )
    UPDATE public.vacancies v
       SET status             = (snap.r).status,
           store_id           = (snap.r).store_id,
           store_name         = (snap.r).store_name,
           position           = (snap.r).position,
           required_headcount = (snap.r).required_headcount,
           is_archived        = (snap.r).is_archived,
           deleted_at         = (snap.r).deleted_at,
           updated_at         = now(),
           updated_by         = v_actor
      FROM snap
     WHERE v.id = snap.entity_id;

    -- Roving groups created by this batch: close them if no active allocations remain.
    UPDATE public.import_roving_groups g
       SET archived_at = COALESCE(g.archived_at, now()),
           updated_at  = now()
     WHERE g.source_import_batch_id = p_batch_id
       AND NOT EXISTS (
         SELECT 1
           FROM public.employee_store_allocations a
          WHERE a.roving_group_id = g.id
            AND a.is_active
       );
    GET DIAGNOSTICS v_roving_groups_archived = ROW_COUNT;

    -- Mark rollback success.
    UPDATE public.plantilla_import_batches
       SET status               = 'rolled_back',
           rolled_back_by       = v_uid,
           rolled_back_at       = now(),
           rollback_reason      = v_reason,
           rollback_error_detail = NULL,
           updated_at           = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status',                  'rolled_back',
        'batch_id',                p_batch_id,
        'plantilla_restored',      v_plantilla_restored,
        'plantilla_archived',      v_plantilla_archived,
        'stores_restored',         v_stores_restored,
        'stores_deactivated',      v_stores_deactivated,
        'allocations_restored',    v_allocations_restored,
        'allocations_deactivated', v_allocations_deactivated,
        'roving_groups_archived',  v_roving_groups_archived,
        'reason',                  v_reason
      )
    );

    RETURN jsonb_build_object(
      'status',                  'rolled_back',
      'batch_id',                p_batch_id,
      'plantilla_restored',      v_plantilla_restored,
      'plantilla_archived',      v_plantilla_archived,
      'stores_restored',         v_stores_restored,
      'stores_deactivated',      v_stores_deactivated,
      'allocations_restored',    v_allocations_restored,
      'allocations_deactivated', v_allocations_deactivated,
      'reason',                  v_reason
    );

  EXCEPTION WHEN OTHERS THEN
    UPDATE public.plantilla_import_batches
       SET status               = 'rollback_failed',
           rollback_error_detail = format('[%s] %s', SQLSTATE, SQLERRM),
           rollback_reason      = v_reason,
           updated_at           = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status',   'rollback_failed',
        'batch_id', p_batch_id,
        'error',    format('[%s] %s', SQLSTATE, SQLERRM),
        'reason',   v_reason
      )
    );

    RETURN jsonb_build_object(
      'status',   'rollback_failed',
      'batch_id', p_batch_id,
      'error',    format('[%s] %s', SQLSTATE, SQLERRM),
      'reason',   v_reason
    );
  END;
END;
$function$
;;

COMMIT;
