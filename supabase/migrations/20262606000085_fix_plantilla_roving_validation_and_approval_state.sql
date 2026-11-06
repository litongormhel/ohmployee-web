-- ============================================================================
-- Migration: 20262606000085_fix_plantilla_roving_validation_and_approval_state.sql
-- Description:
--   1. Create internal helper public._evaluate_plantilla_import_rows to provide
--      a single source of truth for validation across dry-run and commit RPCs.
--   2. Standard roving employees (across >= 2 stores with 1/N HC) are 'valid'
--      (no demotion to flagged; roving info retained as neutral advisory note).
--   3. Data-conflicting flags (multiple_vcodes_per_store) are promoted to 'blocked'.
--   4. Create public.validate_plantilla_baseline_import (dry-run RPC, STABLE, writes nothing).
--   5. Update public.submit_plantilla_baseline_import to refuse batches with blocked
--      rows (RAISE EXCEPTION 'BATCH_BLOCKED: ...') and route clean batches directly
--      to 'pending_approval'.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Internal Shared Evaluation Function
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._evaluate_plantilla_import_rows(
  p_group_id   uuid,
  p_account_id uuid,
  p_rows       jsonb
)
RETURNS TABLE (
  row_num               int,
  raw_row               jsonb,
  vcode                 text,
  final_store_name      text,
  mother_acct           text,
  prov                  text,
  city                  text,
  "position"            text,
  emp_no                text,
  last_name             text,
  first_name            text,
  middle_name           text,
  date_hired            text,
  civil_status          text,
  rate_raw              text,
  birthdate_raw         text,
  contact_raw           text,
  address_raw           text,
  sched_days_raw        text,
  sched_time_raw        text,
  dayoff_raw            text,
  coord_raw             text,
  hrco_email_raw        text,
  row_final_hrco_id     uuid,
  row_needs_hrco        boolean,
  resolved_store_id     uuid,
  is_new_store          boolean,
  is_existing_emp       boolean,
  is_roving             boolean,
  roving_store_count    int,
  employment_type       text,
  required_hc_raw       text,
  with_penalty_raw      text,
  validation_errors     jsonb,
  validation_flags      jsonb,
  is_dup_pair           boolean,
  validation_status     text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $func$
DECLARE
  v_acct_hrco_id     uuid;
  v_resolved_hrco_id uuid;
  v_needs_hrco       boolean;
BEGIN
  SELECT hrco_user_id
    INTO v_acct_hrco_id
    FROM public.accounts WHERE id = p_account_id;

  v_resolved_hrco_id := v_acct_hrco_id;
  IF v_resolved_hrco_id IS NULL THEN
    SELECT u.id INTO v_resolved_hrco_id
      FROM public.users_profile u
     WHERE u.is_active = true
       AND u.account_id = p_account_id
       AND lower(u.role) IN ('hrco', 'hr coordinator')
     LIMIT 1;
  END IF;
  v_needs_hrco := (v_resolved_hrco_id IS NULL);

  RETURN QUERY
  WITH parsed AS MATERIALIZED (
    SELECT
      (row_number() OVER ())::int AS row_num,
      elem.value AS raw_row,
      upper(NULLIF(trim(COALESCE(elem.value->>'VCODE','')), '')) AS vcode,
      NULLIF(trim(COALESCE(elem.value->>'STORE_NAME','')), '') AS store_nm,
      NULLIF(trim(COALESCE(elem.value->>'MOTHER_ACCOUNT','')), '') AS mother_acct,
      NULLIF(trim(COALESCE(elem.value->>'AREA_PROVINCE','')), '') AS prov,
      NULLIF(trim(COALESCE(elem.value->>'AREA_CITY','')), '') AS city,
      NULLIF(trim(COALESCE(elem.value->>'POSITION','')), '') AS pos,
      upper(NULLIF(trim(COALESCE(elem.value->>'EMPLOYEE_NO','')), '')) AS emp_no,
      NULLIF(trim(COALESCE(elem.value->>'LAST_NAME','')), '') AS last_name,
      NULLIF(trim(COALESCE(elem.value->>'FIRST_NAME','')), '') AS first_name,
      NULLIF(trim(COALESCE(elem.value->>'MIDDLE_NAME','')), '') AS middle_name,
      NULLIF(trim(COALESCE(elem.value->>'DATE_HIRED','')), '') AS date_hired,
      NULLIF(trim(COALESCE(elem.value->>'CIVIL_STATUS','')), '') AS civil_status,
      NULLIF(trim(COALESCE(elem.value->>'RATE','')), '') AS rate_raw,
      NULLIF(trim(COALESCE(elem.value->>'DATE_OF_BIRTH', elem.value->>'BIRTHDATE', '')), '') AS birthdate_raw,
      NULLIF(trim(COALESCE(elem.value->>'CONTACT_NO', elem.value->>'CONTACT', '')), '') AS contact_raw,
      NULLIF(trim(COALESCE(elem.value->>'ADDRESS','')), '') AS address_raw,
      NULLIF(trim(COALESCE(elem.value->>'SCHEDULE_DAYS', elem.value->>'SCHEDULE', '')), '') AS sched_days_raw,
      NULLIF(trim(COALESCE(elem.value->>'SCHEDULE_TIME','')), '') AS sched_time_raw,
      NULLIF(trim(COALESCE(elem.value->>'DAYOFF','')), '') AS dayoff_raw,
      NULLIF(trim(COALESCE(elem.value->>'COORDINATOR','')), '') AS coord_raw,
      NULLIF(trim(COALESCE(elem.value->>'HRCO_EMAIL','')), '') AS hrco_email_raw
    FROM jsonb_array_elements(p_rows) AS elem
  ),
  vcode_conflicts AS MATERIALIZED (
    SELECT p.vcode 
    FROM parsed p
    WHERE p.vcode IS NOT NULL AND p.store_nm IS NOT NULL 
    GROUP BY p.vcode 
    HAVING count(DISTINCT upper(trim(p.store_nm))) > 1
  ),
  store_conflicts AS MATERIALIZED (
    SELECT upper(trim(p.store_nm)) AS store_upper 
    FROM parsed p
    WHERE p.vcode IS NOT NULL AND p.store_nm IS NOT NULL 
    GROUP BY upper(trim(p.store_nm)) 
    HAVING count(DISTINCT p.vcode) > 1
  ),
  emp_store_counts AS MATERIALIZED (
    SELECT p.emp_no, count(DISTINCT p.vcode) AS store_cnt 
    FROM parsed p
    WHERE p.emp_no IS NOT NULL AND p.vcode IS NOT NULL 
    GROUP BY p.emp_no
  ),
  emp_vcode_dups AS MATERIALIZED (
    SELECT sub.row_num 
    FROM (
      SELECT p.row_num, row_number() OVER (PARTITION BY p.emp_no, p.vcode ORDER BY p.row_num) as rn
      FROM parsed p
      WHERE p.emp_no IS NOT NULL AND p.vcode IS NOT NULL
    ) sub 
    WHERE sub.rn > 1
  ),
  evaluated AS (
    SELECT
      p.row_num,
      p.raw_row,
      p.vcode,
      COALESCE(p.store_nm, p.raw_row->>'STORE_NAME') AS final_store_name,
      p.mother_acct,
      p.prov,
      p.city,
      p.pos AS position_val,
      p.emp_no,
      p.last_name,
      p.first_name,
      p.middle_name,
      p.date_hired,
      p.civil_status,
      p.rate_raw,
      p.birthdate_raw,
      p.contact_raw,
      p.address_raw,
      p.sched_days_raw,
      p.sched_time_raw,
      p.dayoff_raw,
      p.coord_raw,
      p.hrco_email_raw,

      -- HRCO resolution
      COALESCE(row_hrco.id, v_resolved_hrco_id) AS row_final_hrco_id,
      (COALESCE(row_hrco.id, v_resolved_hrco_id) IS NULL AND (p.hrco_email_raw IS NULL OR trim(p.hrco_email_raw) = '')) AS row_needs_hrco,

      -- DB store resolution
      db_store.id AS resolved_store_id,
      (db_store.id IS NULL) AS is_new_store,
      false AS is_existing_emp,

      -- Roving & HC
      (p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 1) > 1) AS is_roving,
      COALESCE(esc.store_cnt, 0)::int AS roving_store_count,
      CASE 
        WHEN p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 1) > 1 THEN 'roving'
        ELSE 'stationary'
      END AS employment_type,
      CASE 
        WHEN p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 1) > 1 THEN trim(to_char(round(1.0 / esc.store_cnt, 2), 'FM999990.00'))
        ELSE '1.00'
      END AS required_hc_raw,

      -- With penalty
      CASE 
        WHEN COALESCE(mac.with_penalty, (lower(COALESCE(p.raw_row->>'WITH_PENALTY','')) IN ('yes','y','true','1'))) THEN 'yes'
        ELSE 'no'
      END AS with_penalty_raw,

      -- Validation errors array (Hard blocking errors)
      (
        SELECT COALESCE(jsonb_agg(err), '[]'::jsonb)
        FROM (
          SELECT CASE WHEN p.vcode IS NULL THEN jsonb_build_object('field','VCODE','msg','VCODE is required') END AS err UNION ALL
          SELECT CASE WHEN p.store_nm IS NULL THEN jsonb_build_object('field','STORE_NAME','msg','STORE_NAME is required') END UNION ALL
          SELECT CASE WHEN p.mother_acct IS NULL THEN jsonb_build_object('field','MOTHER_ACCOUNT','msg','MOTHER_ACCOUNT is required') END UNION ALL
          SELECT CASE WHEN p.prov IS NULL THEN jsonb_build_object('field','AREA_PROVINCE','msg','AREA_PROVINCE is required') END UNION ALL
          SELECT CASE WHEN p.city IS NULL THEN jsonb_build_object('field','AREA_CITY','msg','AREA_CITY is required') END UNION ALL
          SELECT CASE WHEN p.pos IS NULL THEN jsonb_build_object('field','POSITION','msg','POSITION is required') END UNION ALL
          SELECT CASE WHEN p.vcode IS NOT NULL AND p.store_nm IS NOT NULL AND vc.vcode IS NOT NULL THEN jsonb_build_object('field','VCODE','msg','VCODE is mapped to multiple different STORE_NAMEs in upload') END UNION ALL
          -- Data-conflicting store-vcode mismatch promoted to BLOCKED per Flags Policy A
          SELECT CASE WHEN p.vcode IS NOT NULL AND p.store_nm IS NOT NULL AND sc.store_upper IS NOT NULL THEN jsonb_build_object('field','STORE_NAME','msg','STORE_NAME is mapped to multiple different VCODEs in upload') END UNION ALL
          SELECT CASE WHEN p.vcode IS NOT NULL AND db_store.id IS NOT NULL AND db_store.account_id <> p_account_id THEN jsonb_build_object('field','VCODE','msg','cross-account: store VCODE belongs to a different account in DB') END UNION ALL
          SELECT CASE WHEN p.vcode IS NOT NULL AND db_store.id IS NOT NULL AND db_store.group_id <> p_group_id THEN jsonb_build_object('field','VCODE','msg','cross-group: store VCODE belongs to a different group in DB') END UNION ALL
          SELECT CASE WHEN p.vcode IS NOT NULL AND db_store.id IS NOT NULL AND p.store_nm IS NOT NULL AND upper(trim(db_store.store_name)) <> upper(trim(p.store_nm)) THEN jsonb_build_object('field','STORE_NAME','msg',format('1 Store = 1 VCODE conflict: VCODE "%s" already exists in DB with store name "%s"', p.vcode, db_store.store_name)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NULL AND (p.last_name IS NOT NULL OR p.first_name IS NOT NULL OR p.middle_name IS NOT NULL OR p.date_hired IS NOT NULL) THEN jsonb_build_object('field','EMPLOYEE_NO','msg','EMPLOYEE_NO is required when employee details are provided') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.last_name IS NULL THEN jsonb_build_object('field','LAST_NAME','msg','LAST_NAME is required when EMPLOYEE_NO is provided') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.first_name IS NULL THEN jsonb_build_object('field','FIRST_NAME','msg','FIRST_NAME is required when EMPLOYEE_NO is provided') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.date_hired IS NULL THEN jsonb_build_object('field','DATE_HIRED','msg','DATE_HIRED is required when EMPLOYEE_NO is provided') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.middle_name IS NULL THEN jsonb_build_object('field','MIDDLE_NAME','msg','MIDDLE_NAME is required when assigning an employee') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.middle_name IS NOT NULL AND upper(trim(p.middle_name)) NOT IN ('NA','N/A') AND length(regexp_replace(p.middle_name, '[^a-zA-Z]', '', 'g')) < 2 THEN jsonb_build_object('field','MIDDLE_NAME','msg','MIDDLE_NAME must be at least 2 alpha characters or ''NA'' (single-letter initials not accepted)') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND x_emp.id IS NOT NULL THEN jsonb_build_object('field','EMPLOYEE_NO','msg','cross-account: employee exists in active plantilla under a different account') END
        ) err_list
        WHERE err IS NOT NULL
      ) AS validation_errors,

      -- Validation flags array (purely informational notes)
      (
        SELECT COALESCE(jsonb_agg(flg), '[]'::jsonb)
        FROM (
          SELECT CASE WHEN p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 1) > 1 THEN jsonb_build_object('flag','roving_info','msg',format('Roving · %s stores · %s HC', esc.store_cnt, trim(to_char(round(1.0 / esc.store_cnt, 2), 'FM999990.00')))) END AS flg UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND evd.row_num IS NOT NULL THEN jsonb_build_object('flag','duplicate_emp_vcode','msg','same employee+VCODE already processed in batch - skipped') END
        ) flg_list
        WHERE flg IS NOT NULL
      ) AS validation_flags,

      (p.emp_no IS NOT NULL AND evd.row_num IS NOT NULL) AS is_dup_pair
    FROM parsed p
    LEFT JOIN vcode_conflicts vc ON vc.vcode = p.vcode
    LEFT JOIN store_conflicts sc ON sc.store_upper = upper(trim(p.store_nm))
    LEFT JOIN emp_store_counts esc ON esc.emp_no = p.emp_no
    LEFT JOIN emp_vcode_dups evd ON evd.row_num = p.row_num
    LEFT JOIN LATERAL (
      SELECT s.id, s.account_id, s.group_id, s.store_name 
      FROM public.stores s 
      WHERE upper(s.vcode) = p.vcode AND s.status = 'active' 
      ORDER BY s.created_at LIMIT 1
    ) db_store ON true
    LEFT JOIN public.mother_account_configs mac ON upper(trim(mac.mother_account)) = upper(trim(p.mother_acct))
    LEFT JOIN LATERAL (
      SELECT pl.id FROM public.plantilla pl 
      WHERE pl.employee_no = p.emp_no 
        AND pl.is_deleted = false 
        AND pl.account_id IS NOT NULL AND pl.account_id <> p_account_id 
        AND pl.status IN ('Active','For Deactivation','On Leave','Pending Deactivation') 
      LIMIT 1
    ) x_emp ON true
    LEFT JOIN LATERAL (
      SELECT u.id FROM public.users_profile u 
      WHERE p.hrco_email_raw IS NOT NULL 
        AND lower(u.email) = lower(trim(p.hrco_email_raw)) 
        AND u.is_active = true 
      LIMIT 1
    ) row_hrco ON true
  )
  SELECT
    e.row_num,
    e.raw_row,
    e.vcode,
    e.final_store_name,
    e.mother_acct,
    e.prov,
    e.city,
    e.position_val AS "position",
    e.emp_no,
    e.last_name,
    e.first_name,
    e.middle_name,
    e.date_hired,
    e.civil_status,
    e.rate_raw,
    e.birthdate_raw,
    e.contact_raw,
    e.address_raw,
    e.sched_days_raw,
    e.sched_time_raw,
    e.dayoff_raw,
    e.coord_raw,
    e.hrco_email_raw,
    e.row_final_hrco_id,
    e.row_needs_hrco,
    e.resolved_store_id,
    e.is_new_store,
    e.is_existing_emp,
    e.is_roving,
    e.roving_store_count,
    e.employment_type,
    e.required_hc_raw,
    e.with_penalty_raw,
    e.validation_errors,
    e.validation_flags,
    e.is_dup_pair,
    CASE
      WHEN jsonb_array_length(e.validation_errors) > 0 THEN 'blocked'
      WHEN e.is_dup_pair THEN 'skipped'
      ELSE 'valid'
    END AS validation_status
  FROM evaluated e;
END;
$func$;

REVOKE ALL ON FUNCTION public._evaluate_plantilla_import_rows(uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._evaluate_plantilla_import_rows(uuid, uuid, jsonb) TO authenticated;


-- ----------------------------------------------------------------------------
-- 2. Dry-run RPC: validate_plantilla_baseline_import (writes nothing)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_plantilla_baseline_import(
  p_file_name   text,
  p_group_id    uuid,
  p_account_id  uuid,
  p_rows        jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $func$
DECLARE
  v_role         text := public.get_my_role();
  v_acct_group   uuid;
  v_acct_name    text;
  v_acct_hrco_id uuid;

  v_total      int := 0;
  v_valid      int := 0;
  v_flagged    int := 0;
  v_skipped    int := 0;
  v_blocked    int := 0;
  v_roving     int := 0;
  v_new_stores int := 0;
  v_ex_stores  int := 0;
  v_xacct      int := 0;
  v_xgroup     int := 0;

  v_summary    jsonb;
  v_rows_json  jsonb;
BEGIN
  -- RBAC & Governance check (must match submit gate exactly)
  IF NOT (
    public.fn_can_upload_plantilla_import()
    OR public.i_have_full_access()
    OR public.fn_is_admin()
    OR lower(COALESCE(v_role, '')) IN ('om', 'operations manager', 'hrco', 'hr coordinator')
  ) THEN
    RAISE EXCEPTION 'forbidden: caller lacks permission to import plantilla' USING ERRCODE = '42501';
  END IF;
  PERFORM public.fn_assert_governance_enabled('import_plantilla');
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- Input checks
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

  -- Scope check
  SELECT group_id, account_name, hrco_user_id
    INTO v_acct_group, v_acct_name, v_acct_hrco_id
    FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: %', p_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %', p_account_id, p_group_id USING ERRCODE = '23503';
  END IF;
  IF NOT public.i_have_full_access() AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account is outside caller scope' USING ERRCODE = '42501';
  END IF;

  -- Evaluate rows through single source of truth helper
  SELECT
    count(*)::int,
    count(*) FILTER (WHERE e.validation_status = 'valid')::int,
    count(*) FILTER (WHERE e.validation_status = 'flagged')::int,
    count(*) FILTER (WHERE e.validation_status = 'skipped')::int,
    count(*) FILTER (WHERE e.validation_status = 'blocked')::int,
    count(*) FILTER (WHERE e.is_roving = true)::int,
    count(*) FILTER (WHERE e.vcode IS NOT NULL AND e.validation_status <> 'blocked' AND e.is_new_store = true)::int,
    count(*) FILTER (WHERE e.vcode IS NOT NULL AND e.validation_status <> 'blocked' AND e.is_new_store = false)::int,
    count(*) FILTER (WHERE e.validation_errors @> '[{"field":"VCODE","msg":"cross-account: store VCODE belongs to a different account in DB"}]'::jsonb OR e.validation_errors @> '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee exists in active plantilla under a different account"}]'::jsonb)::int,
    count(*) FILTER (WHERE e.validation_errors @> '[{"field":"VCODE","msg":"cross-group: store VCODE belongs to a different group in DB"}]'::jsonb)::int,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'row_number', e.row_num,
          'vcode', e.vcode,
          'store_name', e.final_store_name,
          'mother_account', e.mother_acct,
          'area_province', e.prov,
          'area_city', e.city,
          'position', e."position",
          'employment_type', e.employment_type,
          'required_hc', e.required_hc_raw,
          'employee_no', e.emp_no,
          'last_name', e.last_name,
          'first_name', e.first_name,
          'middle_name', e.middle_name,
          'date_hired', e.date_hired,
          'is_roving', e.is_roving,
          'roving_store_count', e.roving_store_count,
          'is_new_store', e.is_new_store,
          'needs_hrco', e.row_needs_hrco,
          'resolved_hrco_user_id', e.row_final_hrco_id,
          'hrco_email_raw', e.hrco_email_raw,
          'validation_status', e.validation_status,
          'validation_errors', e.validation_errors,
          'validation_flags', e.validation_flags
        ) ORDER BY e.row_num
      ),
      '[]'::jsonb
    )
  INTO
    v_total, v_valid, v_flagged, v_skipped, v_blocked,
    v_roving, v_new_stores, v_ex_stores, v_xacct, v_xgroup,
    v_rows_json
  FROM public._evaluate_plantilla_import_rows(p_group_id, p_account_id, p_rows) e;

  v_summary := jsonb_build_object(
    'total_rows', v_total,
    'valid_rows', v_valid,
    'flagged_rows', v_flagged,
    'skipped_rows', v_skipped,
    'blocked_rows', v_blocked,
    'roving_detected', v_roving,
    'new_stores_count', v_new_stores,
    'existing_stores_count', v_ex_stores,
    'cross_account_conflicts', v_xacct,
    'cross_group_conflicts', v_xgroup
  );

  RETURN jsonb_build_object(
    'status', CASE WHEN v_blocked > 0 THEN 'blocked' ELSE 'valid' END,
    'total_rows', v_total,
    'valid_rows', v_valid,
    'flagged_rows', v_flagged,
    'skipped_rows', v_skipped,
    'blocked_rows', v_blocked,
    'error_summary', v_summary,
    'rows', v_rows_json
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.validate_plantilla_baseline_import(text, uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.validate_plantilla_baseline_import(text, uuid, uuid, jsonb) TO authenticated;


-- ----------------------------------------------------------------------------
-- 3. submit_plantilla_baseline_import with Hard Blocking & Roving Parity
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_plantilla_baseline_import(
  p_file_name   text,
  p_group_id    uuid,
  p_account_id  uuid,
  p_rows        jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $func$
DECLARE
  v_uid              uuid := auth.uid();
  v_role             text := public.get_my_role();
  v_acct_group       uuid;
  v_acct_name        text;
  v_acct_hrco_id     uuid;
  v_batch_id         uuid;

  v_total      int := 0;
  v_valid      int := 0;
  v_flagged    int := 0;
  v_skipped    int := 0;
  v_blocked    int := 0;
  v_roving     int := 0;
  v_new_stores int := 0;
  v_ex_stores  int := 0;
  v_xacct      int := 0;
  v_xgroup     int := 0;

  v_summary jsonb;
  v_final   text;
BEGIN
  -- RBAC & Governance
  IF NOT (
    public.fn_can_upload_plantilla_import()
    OR public.i_have_full_access()
    OR public.fn_is_admin()
    OR lower(COALESCE(v_role, '')) IN ('om', 'operations manager', 'hrco', 'hr coordinator')
  ) THEN
    RAISE EXCEPTION 'forbidden: caller lacks permission to import plantilla' USING ERRCODE = '42501';
  END IF;
  PERFORM public.fn_assert_governance_enabled('import_plantilla');
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- Input checks
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

  -- Scope check
  SELECT group_id, account_name, hrco_user_id
    INTO v_acct_group, v_acct_name, v_acct_hrco_id
    FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: %', p_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %', p_account_id, p_group_id USING ERRCODE = '23503';
  END IF;
  IF NOT public.i_have_full_access() AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account is outside caller scope' USING ERRCODE = '42501';
  END IF;

  -- Seed any unseeded mother accounts from the batch
  INSERT INTO public.mother_account_configs (mother_account, with_penalty)
  SELECT DISTINCT 
    upper(trim(r->>'MOTHER_ACCOUNT')),
    (lower(COALESCE(r->>'WITH_PENALTY','')) IN ('yes','y','true','1'))
  FROM jsonb_array_elements(p_rows) AS r
  WHERE NULLIF(trim(r->>'MOTHER_ACCOUNT'), '') IS NOT NULL
  ON CONFLICT (mother_account) DO NOTHING;

  -- Create batch in draft state
  INSERT INTO public.plantilla_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- Insert evaluated rows using shared helper
  INSERT INTO public.plantilla_import_rows (
    batch_id, row_number, raw_data,
    vcode, store_name, mother_account, area_province, area_city, position,
    employment_type, required_hc_raw, with_penalty_raw,
    employee_no, last_name, first_name, middle_name, date_hired_raw,
    civil_status, rate_raw, birthdate_raw, contact_raw, address_raw,
    schedule_days, schedule_time, dayoff_raw, coordinator_raw, hrco_email_raw,
    resolved_hrco_user_id, needs_hrco,
    resolved_store_id, resolved_account_id, resolved_group_id,
    validation_status, validation_errors, validation_flags,
    is_roving, roving_store_count, is_new_store, is_existing_employee
  )
  SELECT
    v_batch_id,
    e.row_num,
    e.raw_row,
    e.vcode,
    e.final_store_name,
    e.mother_acct,
    e.prov,
    e.city,
    e."position",
    e.employment_type,
    e.required_hc_raw,
    e.with_penalty_raw,
    e.emp_no,
    e.last_name,
    e.first_name,
    e.middle_name,
    e.date_hired,
    e.civil_status,
    e.rate_raw,
    e.birthdate_raw,
    e.contact_raw,
    e.address_raw,
    e.sched_days_raw,
    e.sched_time_raw,
    e.dayoff_raw,
    e.coord_raw,
    e.hrco_email_raw,
    e.row_final_hrco_id,
    e.row_needs_hrco,
    e.resolved_store_id,
    p_account_id,
    p_group_id,
    e.validation_status,
    e.validation_errors,
    e.validation_flags,
    e.is_roving,
    e.roving_store_count,
    e.is_new_store,
    e.is_existing_emp
  FROM public._evaluate_plantilla_import_rows(p_group_id, p_account_id, p_rows) e;

  -- Aggregate batch summary
  SELECT
    count(*)::int,
    count(*) FILTER (WHERE validation_status = 'valid')::int,
    count(*) FILTER (WHERE validation_status = 'flagged')::int,
    count(*) FILTER (WHERE validation_status = 'skipped')::int,
    count(*) FILTER (WHERE validation_status = 'blocked')::int,
    count(*) FILTER (WHERE is_roving = true)::int,
    count(*) FILTER (WHERE vcode IS NOT NULL AND validation_status <> 'blocked' AND is_new_store = true)::int,
    count(*) FILTER (WHERE vcode IS NOT NULL AND validation_status <> 'blocked' AND is_new_store = false)::int,
    count(*) FILTER (WHERE validation_errors @> '[{"field":"VCODE","msg":"cross-account: store VCODE belongs to a different account in DB"}]'::jsonb OR validation_errors @> '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee exists in active plantilla under a different account"}]'::jsonb)::int,
    count(*) FILTER (WHERE validation_errors @> '[{"field":"VCODE","msg":"cross-group: store VCODE belongs to a different group in DB"}]'::jsonb)::int
  INTO
    v_total, v_valid, v_flagged, v_skipped, v_blocked,
    v_roving, v_new_stores, v_ex_stores, v_xacct, v_xgroup
  FROM public.plantilla_import_rows
  WHERE batch_id = v_batch_id;

  -- Hard blocking guard: server refuses any batch with blocked rows
  IF v_blocked > 0 THEN
    RAISE EXCEPTION 'BATCH_BLOCKED: import contains % blocked row(s). Review and resolve all errors before submitting.', v_blocked
      USING ERRCODE = '22000';
  END IF;

  v_summary := jsonb_build_object(
    'total_rows', v_total,
    'valid_rows', v_valid,
    'flagged_rows', v_flagged,
    'skipped_rows', v_skipped,
    'blocked_rows', v_blocked,
    'roving_detected', v_roving,
    'new_stores_count', v_new_stores,
    'existing_stores_count', v_ex_stores,
    'cross_account_conflicts', v_xacct,
    'cross_group_conflicts', v_xgroup
  );

  -- Since v_blocked is 0 and advisory roving is valid (0 flagged), status is pending_approval
  v_final := 'pending_approval';

  UPDATE public.plantilla_import_batches
     SET status = v_final,
         total_rows = v_total,
         valid_rows = v_valid,
         flagged_rows = v_flagged,
         skipped_rows = v_skipped,
         blocked_rows = v_blocked,
         roving_detected = v_roving,
         new_stores_count = v_new_stores,
         existing_stores_count = v_ex_stores,
         cross_account_conflicts = v_xacct,
         cross_group_conflicts = v_xgroup,
         error_summary = v_summary,
         updated_at = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id', v_batch_id,
    'status', v_final,
    'total_rows', v_total,
    'valid_rows', v_valid,
    'flagged_rows', v_flagged,
    'skipped_rows', v_skipped,
    'blocked_rows', v_blocked,
    'error_summary', v_summary
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.submit_plantilla_baseline_import(text, uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_plantilla_baseline_import(text, uuid, uuid, jsonb) TO authenticated;
