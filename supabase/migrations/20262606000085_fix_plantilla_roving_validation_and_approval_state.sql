-- ============================================================================
-- Migration: 20262606000085_fix_plantilla_roving_validation_and_approval_state.sql
-- Description:
--   1. Fix submit_plantilla_baseline_import so standard roving employee assignments
--      (across 2..20 stores with fractional HC 1/N) are recognized as valid and
--      not demoted to flagged rows. Retain advisory flag only for extreme cases (>20 stores).
--   2. Fix approve_plantilla_import_batch state assertion to allow batches in
--      'pending_review' state to be approved (in addition to 'pending_approval'
--      and 'commit_failed'), aligning with pre-commit committable rules.
--   3. Reconcile existing pending batches and rows (such as Batch #4898978) whose
--      rows were flagged solely due to the advisory 'roving' flag.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Restored submit_plantilla_baseline_import with Roving Flag Correction
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
  v_resolved_hrco_id uuid;
  v_needs_hrco       boolean;
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

  -- Resolve Account HRCO state
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

  -- Create batch
  INSERT INTO public.plantilla_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- Seed any unseeded mother accounts from the batch
  INSERT INTO public.mother_account_configs (mother_account, with_penalty)
  SELECT DISTINCT 
    upper(trim(r->>'MOTHER_ACCOUNT')),
    (lower(COALESCE(r->>'WITH_PENALTY','')) IN ('yes','y','true','1'))
  FROM jsonb_array_elements(p_rows) AS r
  WHERE NULLIF(trim(r->>'MOTHER_ACCOUNT'), '') IS NOT NULL
  ON CONFLICT (mother_account) DO NOTHING;

  -- Set-based evaluation and single bulk insert
  WITH parsed AS MATERIALIZED (
    SELECT
      (row_number() OVER ())::int AS row_num,
      elem.value AS raw_row,
      upper(NULLIF(trim(COALESCE(elem.value->>'VCODE','')), '')) AS vcode,
      NULLIF(trim(COALESCE(elem.value->>'STORE_NAME','')), '') AS store_nm,
      NULLIF(trim(COALESCE(elem.value->>'MOTHER_ACCOUNT','')), '') AS mother_acct,
      NULLIF(trim(COALESCE(elem.value->>'AREA_PROVINCE','')), '') AS prov,
      NULLIF(trim(COALESCE(elem.value->>'AREA_CITY','')), '') AS city,
      NULLIF(trim(COALESCE(elem.value->>'POSITION','')), '') AS position,
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
    SELECT vcode 
    FROM parsed 
    WHERE vcode IS NOT NULL AND store_nm IS NOT NULL 
    GROUP BY vcode 
    HAVING count(DISTINCT upper(trim(store_nm))) > 1
  ),
  store_conflicts AS MATERIALIZED (
    SELECT upper(trim(store_nm)) AS store_upper 
    FROM parsed 
    WHERE vcode IS NOT NULL AND store_nm IS NOT NULL 
    GROUP BY upper(trim(store_nm)) 
    HAVING count(DISTINCT vcode) > 1
  ),
  emp_store_counts AS MATERIALIZED (
    SELECT emp_no, count(DISTINCT vcode) AS store_cnt 
    FROM parsed 
    WHERE emp_no IS NOT NULL AND vcode IS NOT NULL 
    GROUP BY emp_no
  ),
  emp_vcode_dups AS MATERIALIZED (
    SELECT row_num 
    FROM (
      SELECT row_num, row_number() OVER (PARTITION BY emp_no, vcode ORDER BY row_num) as rn
      FROM parsed 
      WHERE emp_no IS NOT NULL AND vcode IS NOT NULL
    ) sub 
    WHERE rn > 1
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
      p.position,
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
      COALESCE(esc.store_cnt, 0) AS roving_store_count,
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

      -- Validation errors array (blocking errors)
      (
        SELECT COALESCE(jsonb_agg(err), '[]'::jsonb)
        FROM (
          SELECT CASE WHEN p.vcode IS NULL THEN jsonb_build_object('field','VCODE','msg','VCODE is required') END AS err UNION ALL
          SELECT CASE WHEN p.store_nm IS NULL THEN jsonb_build_object('field','STORE_NAME','msg','STORE_NAME is required') END UNION ALL
          SELECT CASE WHEN p.mother_acct IS NULL THEN jsonb_build_object('field','MOTHER_ACCOUNT','msg','MOTHER_ACCOUNT is required') END UNION ALL
          SELECT CASE WHEN p.prov IS NULL THEN jsonb_build_object('field','AREA_PROVINCE','msg','AREA_PROVINCE is required') END UNION ALL
          SELECT CASE WHEN p.city IS NULL THEN jsonb_build_object('field','AREA_CITY','msg','AREA_CITY is required') END UNION ALL
          SELECT CASE WHEN p.position IS NULL THEN jsonb_build_object('field','POSITION','msg','POSITION is required') END UNION ALL
          SELECT CASE WHEN p.vcode IS NOT NULL AND p.store_nm IS NOT NULL AND vc.vcode IS NOT NULL THEN jsonb_build_object('field','VCODE','msg','VCODE is mapped to multiple different STORE_NAMEs in upload') END UNION ALL
          SELECT CASE WHEN p.vcode IS NOT NULL AND db_store.id IS NOT NULL AND db_store.account_id <> p_account_id THEN jsonb_build_object('field','VCODE','msg','cross-account: store VCODE belongs to a different account in DB') END UNION ALL
          SELECT CASE WHEN p.vcode IS NOT NULL AND db_store.id IS NOT NULL AND db_store.group_id <> p_group_id THEN jsonb_build_object('field','VCODE','msg','cross-group: store VCODE belongs to a different group in DB') END UNION ALL
          SELECT CASE WHEN p.vcode IS NOT NULL AND db_store.id IS NOT NULL AND p.store_nm IS NOT NULL AND upper(trim(db_store.store_name)) <> upper(trim(p.store_nm)) THEN jsonb_build_object('field','STORE_NAME','msg',format('1 Store = 1 VCODE conflict: VCODE "%s" already exists in DB with store name "%s"', p.vcode, db_store.store_name)) END UNION ALL
          SELECT CASE WHEN p.emp_no IS NULL AND (p.last_name IS NOT NULL OR p.first_name IS NOT NULL OR p.middle_name IS NOT NULL OR p.date_hired IS NOT NULL) THEN jsonb_build_object('field','EMPLOYEE_NO','msg','EMPLOYEE_NO is required when employee details are provided') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.last_name IS NULL THEN jsonb_build_object('field','LAST_NAME','msg','LAST_NAME is required when EMPLOYEE_NO is provided') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.first_name IS NULL THEN jsonb_build_object('field','FIRST_NAME','msg','FIRST_NAME is required when EMPLOYEE_NO is provided') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.date_hired IS NULL THEN jsonb_build_object('field','DATE_HIRED','msg','DATE_HIRED is required when EMPLOYEE_NO is provided') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.middle_name IS NULL THEN jsonb_build_object('field','MIDDLE_NAME','msg','MIDDLE_NAME is required when assigning an employee') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND p.middle_name IS NOT NULL AND upper(trim(p.middle_name)) NOT IN ('NA','N/A') AND length(regexp_replace(p.middle_name, '[^a-zA-Z]', '', 'g')) < 2 THEN jsonb_build_object('field','MIDDLE_NAME','msg','MIDDLE_NAME must be at least 2 alpha characters or ''NA'' (single-letter initials not accepted)') END UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND x_emp IS NOT NULL THEN jsonb_build_object('field','EMPLOYEE_NO','msg','cross-account: employee exists in active plantilla under a different account') END
        ) err_list
        WHERE err IS NOT NULL
      ) AS validation_errors,

      -- Validation flags array (advisory warnings only; standard roving across 2..20 stores is valid and NOT flagged)
      (
        SELECT COALESCE(jsonb_agg(flg), '[]'::jsonb)
        FROM (
          SELECT CASE WHEN p.vcode IS NOT NULL AND p.store_nm IS NOT NULL AND sc.store_upper IS NOT NULL THEN jsonb_build_object('flag','multiple_vcodes_per_store','field','STORE_NAME','msg','STORE_NAME is mapped to multiple different VCODEs in upload') END AS flg UNION ALL
          SELECT CASE WHEN p.emp_no IS NOT NULL AND COALESCE(esc.store_cnt, 1) > 20 THEN jsonb_build_object('flag','over_20_stores','msg',format('roving employee across %s stores (>20 allowed but flagged)', esc.store_cnt)) END UNION ALL
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
    e.position,
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
    CASE
      WHEN jsonb_array_length(e.validation_errors) > 0 THEN 'blocked'
      WHEN e.is_dup_pair THEN 'skipped'
      WHEN jsonb_array_length(e.validation_flags) > 0 THEN 'flagged'
      ELSE 'valid'
    END AS validation_status,
    e.validation_errors,
    e.validation_flags,
    e.is_roving,
    e.roving_store_count,
    e.is_new_store,
    e.is_existing_emp
  FROM evaluated e;

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

  v_final := CASE
    WHEN v_blocked > 0 AND (v_valid + v_flagged) > 0 THEN 'partially_blocked'
    WHEN v_blocked > 0 THEN 'blocked'
    WHEN v_flagged > 0 THEN 'pending_review'
    ELSE 'pending_approval'
  END;

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
GRANT EXECUTE ON FUNCTION public.submit_plantilla_baseline_import(text, uuid, uuid, jsonb) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Restored approve_plantilla_import_batch allowing 'pending_review'
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid            uuid := auth.uid();
  v_actor          uuid := public.get_current_profile_id();
  v_user_name      text;
  v_batch          public.plantilla_import_batches%ROWTYPE;
  v_acct_name      text;
  v_acct_hrco_id   uuid;
  v_acct_hrco_name text;

  -- Phase A locals
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_stores_done        int := 0;

  -- Phase B locals
  v_vrow           record;
  v_emp_rec        record;
  v_store_rec      record;
  v_plantilla_id   uuid;
  v_primary_store_id uuid;
  v_parsed_rate    numeric;
  v_parsed_date_hired date;
  v_parsed_birthdate  date;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;
  v_vacant_slots   int := 0;

  -- Target linkage locals
  v_store_acct_id     uuid;
  v_store_grp_id      uuid;
  v_target_account_id uuid;
  v_target_group_id   uuid;
  v_target_acct_name  text;

  -- HRCO resolution locals
  v_final_hrco_id   uuid;
  v_final_hrco_name text;
  v_needs_hrco      boolean;

  -- Slot claiming & assignment locals
  v_target_slot_id uuid;
  v_next_ordinal   int;
  v_batch_created_slot_ids uuid[] := '{}'::uuid[];

  -- Commit counts & pre-commit guards
  v_blocked_cnt int := 0;
  v_committable int := 0;
  v_approved_timestamp timestamptz;

  -- Error handling
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Allow pending_approval, pending_review, or commit_failed
  IF v_batch.status NOT IN ('pending_approval', 'pending_review', 'commit_failed') THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval, pending_review, or commit_failed can be approved (current=%)', v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;
  SELECT account_name, hrco_user_id INTO v_acct_name, v_acct_hrco_id
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  IF v_acct_hrco_id IS NOT NULL THEN
    SELECT full_name INTO v_acct_hrco_name
      FROM public.users_profile
     WHERE id = v_acct_hrco_id;
  END IF;

  -- Pre-commit guard 1: Block approval strictly if there are hard-blocked rows
  SELECT count(*) INTO v_blocked_cnt
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status = 'blocked';

  IF v_blocked_cnt > 0 THEN
    RAISE EXCEPTION 'Cannot approve batch: % blocked rows must be resolved or removed first', v_blocked_cnt USING ERRCODE = '22023';
  END IF;

  -- Pre-commit guard 2: Committable includes valid and flagged rows with vcode (employee_no may be null for vacant slots)
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid', 'flagged')
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch' USING ERRCODE = '22023';
  END IF;

  BEGIN
    -- Phase A: Store upsert for all committable rows (valid + flagged)
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, mother_account, area_province, area_city,
             employment_type, with_penalty_raw, schedule_days, schedule_time,
             row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid', 'flagged')
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_pen_bool := (lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1'));

      SELECT to_jsonb(s.*) INTO v_old_store_snap
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_srow.vcode) AND s.status = 'active'
       ORDER BY s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
        INSERT INTO public.stores (
          vcode, store_name, mother_account, area_province, area_city,
          employment_type, with_penalty, schedule_days, schedule_time,
          group_id, account_id, status, hrco_user_id,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.mother_account, v_srow.area_province, v_srow.area_city,
          COALESCE(v_srow.employment_type, 'stationary'), v_pen_bool, v_srow.schedule_days, v_srow.schedule_time,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active', v_acct_hrco_id,
          v_uid, v_uid, v_uid, now(), p_batch_id
        ) RETURNING id INTO v_new_store_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_new_store_id, 'insert', NULL, v_uid);
      ELSE
        v_existing_store_id := (v_old_store_snap->>'id')::uuid;

        UPDATE public.stores
           SET store_name      = v_srow.store_name,
               mother_account  = COALESCE(v_srow.mother_account, mother_account),
               area_province   = v_srow.area_province,
               area_city       = v_srow.area_city,
               employment_type = COALESCE(v_srow.employment_type, employment_type),
               with_penalty    = COALESCE(v_pen_bool, with_penalty),
               schedule_days   = COALESCE(v_srow.schedule_days, schedule_days),
               schedule_time   = COALESCE(v_srow.schedule_time, schedule_time),
               account_id      = COALESCE(stores.account_id, v_batch.selected_account_id),
               group_id        = COALESCE(stores.group_id, v_batch.selected_group_id),
               hrco_user_id    = COALESCE(v_acct_hrco_id, hrco_user_id),
               updated_by      = v_uid,
               approved_by     = v_uid,
               approved_at     = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- Phase B1: Vacant Store Slot Creation (committable rows where employee_no IS NULL)
    FOR v_vrow IN
      SELECT vcode, store_name, position, area_province, area_city, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid', 'flagged')
         AND employee_no IS NULL
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_new_store_id := NULL;
      v_store_acct_id := NULL;
      v_store_grp_id := NULL;

      SELECT id, account_id, group_id
        INTO v_new_store_id, v_store_acct_id, v_store_grp_id
        FROM public.stores
       WHERE upper(vcode) = upper(v_vrow.vcode) AND status = 'active'
       ORDER BY created_at LIMIT 1;

      v_target_account_id := COALESCE(v_batch.selected_account_id, v_store_acct_id);
      v_target_group_id   := COALESCE(v_batch.selected_group_id, v_store_grp_id);

      IF v_target_account_id IS NOT NULL AND (v_acct_name IS NULL OR v_acct_name = 'Unknown Account') THEN
        SELECT account_name INTO v_target_acct_name FROM public.accounts WHERE id = v_target_account_id;
      ELSE
        v_target_acct_name := v_acct_name;
      END IF;

      -- Calculate next available ordinal for this store
      SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
        FROM public.plantilla_slots
       WHERE store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_vrow.vcode));

      INSERT INTO public.plantilla_slots (
        store_id, account_id, group_id,
        position, employment_type, is_roving,
        slot_status, slot_ordinal, legacy_vcode,
        current_occupant_plantilla_id,
        created_at, updated_at, created_by, updated_by
      ) VALUES (
        v_new_store_id, v_target_account_id, v_target_group_id,
        COALESCE(v_vrow.position, 'Merchandiser'), 'stationary', false,
        'open', v_next_ordinal::smallint, v_vrow.vcode, NULL,
        now(), now(), v_actor, v_actor
      ) RETURNING id INTO v_target_slot_id;

      v_batch_created_slot_ids := array_append(v_batch_created_slot_ids, v_target_slot_id);

      -- Sync vacancies record for shadow view
      INSERT INTO public.vacancies (
        vcode, account, position, store_name, area_city, province, area_name,
        required_headcount, status, store_id, account_id, group_id,
        hrco_user_id, hrco_name,
        created_at, updated_at, created_by
      ) VALUES (
        v_vrow.vcode,
        COALESCE(v_target_acct_name, v_acct_name, 'Unknown Account'),
        COALESCE(v_vrow.position, 'Merchandiser'),
        v_vrow.store_name,
        v_vrow.area_city,
        v_vrow.area_province,
        v_vrow.area_province || ' - ' || v_vrow.area_city,
        1, 'Open', v_new_store_id, v_target_account_id, v_target_group_id,
        v_acct_hrco_id, v_acct_hrco_name,
        now(), now(), v_actor
      ) ON CONFLICT (vcode) DO UPDATE
      SET status = 'Open',
          account = CASE
            WHEN EXCLUDED.account IS NOT NULL AND EXCLUDED.account <> 'Unknown Account' THEN EXCLUDED.account
            ELSE COALESCE(NULLIF(vacancies.account, 'Unknown Account'), EXCLUDED.account)
          END,
          position = EXCLUDED.position,
          store_name = EXCLUDED.store_name,
          area_city = EXCLUDED.area_city,
          province = EXCLUDED.province,
          area_name = EXCLUDED.area_name,
          store_id = COALESCE(EXCLUDED.store_id, vacancies.store_id),
          account_id = COALESCE(EXCLUDED.account_id, vacancies.account_id),
          group_id = COALESCE(EXCLUDED.group_id, vacancies.group_id),
          required_headcount = GREATEST(vacancies.required_headcount, 1),
          hrco_user_id = COALESCE(EXCLUDED.hrco_user_id, vacancies.hrco_user_id),
          hrco_name = COALESCE(EXCLUDED.hrco_name, vacancies.hrco_name),
          deleted_at = NULL,
          is_archived = false,
          updated_at = now();

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type, old_value, new_value,
        reason_code, performed_by, remarks, created_at
      ) VALUES (
        v_target_slot_id, v_target_account_id, 'created',
        NULL, 'open',
        CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_VACANT_SLOT') THEN 'IMPORT_VACANT_SLOT' ELSE NULL END,
        v_actor,
        format('Vacant slot created by baseline import batch %s', p_batch_id), now()
      );

      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      VALUES (p_batch_id, v_vrow.row_id, 'slot', v_target_slot_id, 'insert', NULL, v_uid);

      v_vacant_slots := v_vacant_slots + 1;
    END LOOP;

    -- Phase B2: Assigned Employee Upsert & Slot Provisioning (valid + flagged)
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number))[1]                            AS middle_name,
        (array_agg(position    ORDER BY row_number) FILTER (WHERE position IS NOT NULL))[1] AS position,
        (array_agg(vcode       ORDER BY row_number) FILTER (WHERE vcode IS NOT NULL))[1] AS primary_vcode,
        (array_agg(store_name  ORDER BY row_number) FILTER (WHERE store_name IS NOT NULL))[1] AS primary_store_name,
        (array_agg(mother_account ORDER BY row_number) FILTER (WHERE mother_account IS NOT NULL))[1] AS mother_account,
        (array_agg(area_province ORDER BY row_number) FILTER (WHERE area_province IS NOT NULL))[1] AS area_province,
        (array_agg(area_city ORDER BY row_number) FILTER (WHERE area_city IS NOT NULL))[1] AS area_city,
        (array_agg(civil_status ORDER BY row_number) FILTER (WHERE civil_status IS NOT NULL))[1] AS civil_status,
        (array_agg(rate_raw ORDER BY row_number) FILTER (WHERE rate_raw IS NOT NULL))[1] AS rate_raw,
        (array_agg(birthdate_raw ORDER BY row_number) FILTER (WHERE birthdate_raw IS NOT NULL))[1] AS birthdate_raw,
        (array_agg(date_hired_raw ORDER BY row_number) FILTER (WHERE date_hired_raw IS NOT NULL))[1] AS date_hired_raw,
        (array_agg(contact_raw ORDER BY row_number) FILTER (WHERE contact_raw IS NOT NULL))[1] AS contact_raw,
        (array_agg(address_raw ORDER BY row_number) FILTER (WHERE address_raw IS NOT NULL))[1] AS address_raw,
        (array_agg(schedule_days ORDER BY row_number) FILTER (WHERE schedule_days IS NOT NULL))[1] AS schedule_days,
        (array_agg(schedule_time ORDER BY row_number) FILTER (WHERE schedule_time IS NOT NULL))[1] AS schedule_time,
        (array_agg(dayoff_raw ORDER BY row_number) FILTER (WHERE dayoff_raw IS NOT NULL))[1] AS dayoff_raw,
        (array_agg(coordinator_raw ORDER BY row_number) FILTER (WHERE coordinator_raw IS NOT NULL))[1] AS coordinator_raw,
        bool_or(needs_hrco) AS needs_hrco_agg,
        (array_agg(resolved_hrco_user_id ORDER BY row_number) FILTER (WHERE resolved_hrco_user_id IS NOT NULL))[1] AS hrco_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid', 'flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      -- Resolve Primary Store ID
      v_primary_store_id := NULL;
      IF v_emp_rec.primary_vcode IS NOT NULL THEN
        SELECT id INTO v_primary_store_id
          FROM public.stores
         WHERE upper(vcode) = upper(v_emp_rec.primary_vcode) AND status = 'active'
         ORDER BY created_at LIMIT 1;
      END IF;

      -- Parse numeric rate and dates
      v_parsed_rate := public.safe_parse_numeric(v_emp_rec.rate_raw);
      v_parsed_date_hired := public.safe_parse_date(v_emp_rec.date_hired_raw);
      v_parsed_birthdate := public.safe_parse_date(v_emp_rec.birthdate_raw);

      -- HRCO resolution: row-level first, then Account assigned HRCO fallback
      v_final_hrco_id := COALESCE(v_emp_rec.hrco_id, v_acct_hrco_id);
      IF v_final_hrco_id IS NOT NULL THEN
        IF v_final_hrco_id = v_acct_hrco_id AND v_acct_hrco_name IS NOT NULL THEN
          v_final_hrco_name := v_acct_hrco_name;
        ELSE
          SELECT full_name INTO v_final_hrco_name
            FROM public.users_profile
           WHERE id = v_final_hrco_id;
        END IF;
        v_needs_hrco := false;
      ELSE
        v_final_hrco_name := NULL;
        v_needs_hrco := true;
      END IF;

      -- Plantilla lookup
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no AND is_deleted = false
       LIMIT 1;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- Insert new plantilla record with all inherited fields
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          mother_account, position, deployment_type,
          store_id, store_name, vcode,
          area, area_name_snapshot,
          civil_status, rate, daily_rate, birthdate, date_of_birth, date_hired,
          contact_no, address,
          schedule, schedule_days, schedule_time, dayoff, coordinator,
          hrco_user_id_snapshot, hrco_name, needs_hrco,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        ) VALUES (
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no, v_acct_name, 'Active',
          v_batch.selected_account_id, v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          v_emp_rec.mother_account, v_emp_rec.position,
          CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
          v_primary_store_id, v_emp_rec.primary_store_name, v_emp_rec.primary_vcode,
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          v_emp_rec.civil_status,
          v_parsed_rate,
          v_parsed_rate,
          v_parsed_birthdate,
          v_parsed_birthdate,
          v_parsed_date_hired,
          v_emp_rec.contact_raw, v_emp_rec.address_raw,
          v_emp_rec.schedule_days, v_emp_rec.schedule_days, v_emp_rec.schedule_time,
          v_emp_rec.dayoff_raw, v_emp_rec.coordinator_raw,
          v_final_hrco_id, v_final_hrco_name, v_needs_hrco,
          p_batch_id, v_actor, v_actor
        ) RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);
      ELSE
        -- Update existing plantilla record with inherited fields
        UPDATE public.plantilla
           SET employee_name      = v_emp_name,
               last_name          = v_emp_rec.last_name,
               first_name         = v_emp_rec.first_name,
               middle_name        = v_emp_rec.middle_name,
               mother_account     = COALESCE(v_emp_rec.mother_account, mother_account),
               position           = COALESCE(v_emp_rec.position, position),
               deployment_type    = CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
               store_id           = COALESCE(v_primary_store_id, store_id),
               store_name         = COALESCE(v_emp_rec.primary_store_name, store_name),
               vcode              = COALESCE(v_emp_rec.primary_vcode, vcode),
               rate               = COALESCE(v_parsed_rate, rate),
               daily_rate         = COALESCE(v_parsed_rate, daily_rate),
               date_hired         = COALESCE(v_parsed_date_hired, date_hired),
               address            = COALESCE(v_emp_rec.address_raw, address),
               contact_no         = COALESCE(v_emp_rec.contact_raw, contact_no),
               birthdate          = COALESCE(v_parsed_birthdate, birthdate),
               date_of_birth      = COALESCE(v_parsed_birthdate, date_of_birth),
               civil_status       = COALESCE(v_emp_rec.civil_status, civil_status),
               schedule_days      = COALESCE(v_emp_rec.schedule_days, schedule_days),
               schedule_time      = COALESCE(v_emp_rec.schedule_time, schedule_time),
               dayoff             = COALESCE(v_emp_rec.dayoff_raw, dayoff),
               coordinator        = COALESCE(v_emp_rec.coordinator_raw, coordinator),
               hrco_user_id_snapshot = COALESCE(v_final_hrco_id, hrco_user_id_snapshot),
               hrco_name          = COALESCE(v_final_hrco_name, hrco_name),
               needs_hrco         = CASE WHEN v_final_hrco_id IS NOT NULL THEN false ELSE COALESCE(v_emp_rec.needs_hrco_agg, needs_hrco) END,
               updated_at         = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      -- Deactivate old allocations
      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
        WHERE employee_no = v_emp_rec.employee_no
          AND is_active
          AND account_id = v_batch.selected_account_id;

      -- Store allocations loop (committable valid + flagged)
      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, pir.store_name, pir.schedule_days, pir.schedule_time
          FROM public.plantilla_import_rows pir
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid', 'flagged')
         ORDER BY pir.vcode, pir.row_number
      LOOP
        v_new_store_id := NULL;
        v_store_acct_id := NULL;
        v_store_grp_id := NULL;

        SELECT id, account_id, group_id
          INTO v_new_store_id, v_store_acct_id, v_store_grp_id
          FROM public.stores
         WHERE upper(vcode) = upper(v_store_rec.vcode) AND status = 'active'
         ORDER BY created_at LIMIT 1;

        v_target_account_id := COALESCE(v_batch.selected_account_id, v_store_acct_id);
        v_target_group_id   := COALESCE(v_batch.selected_group_id, v_store_grp_id);

        INSERT INTO public.employee_store_allocations (
          plantilla_id, employee_no,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          schedule_days, schedule_time,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_plantilla_id, v_emp_rec.employee_no,
          v_new_store_id, v_store_rec.vcode, v_store_rec.store_name,
          v_target_account_id, v_target_group_id,
          v_filled, v_store_cnt,
          v_store_rec.schedule_days, v_store_rec.schedule_time,
          CURRENT_DATE, true,
          p_batch_id, v_actor
        );
        v_alloc_done := v_alloc_done + 1;

        -- Sync active roving link in plantilla_store_links for safe view consistency
        INSERT INTO public.plantilla_store_links (
          plantilla_id, vcode, store_name, account, status, linked_at
        ) VALUES (
          v_plantilla_id, v_store_rec.vcode, v_store_rec.store_name, v_acct_name, 'Active', now()
        ) ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
        DO UPDATE SET
          store_name = EXCLUDED.store_name,
          account = EXCLUDED.account,
          status = 'Active';

        -- Store-level idempotent slot reuse, pre-existing vacant claiming, or slot provisioning
        v_target_slot_id := NULL;

        -- Step 1: Check if employee already occupies an active slot in this store
        SELECT id INTO v_target_slot_id
          FROM public.plantilla_slots
         WHERE (store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode)))
           AND current_occupant_plantilla_id = v_plantilla_id
           AND slot_status IN ('occupied', 'filled')
         LIMIT 1;

        IF v_target_slot_id IS NOT NULL THEN
          -- Re-import / idempotent update of existing active slot for this employee in this store
          UPDATE public.plantilla_slots
             SET store_id        = COALESCE(store_id, v_new_store_id),
                 account_id      = COALESCE(account_id, v_target_account_id),
                 group_id        = COALESCE(group_id, v_target_group_id),
                 position        = COALESCE(v_emp_rec.position, position),
                 is_roving       = (v_store_cnt > 1),
                 employment_type = CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
                 updated_at      = now(),
                 updated_by      = v_actor
           WHERE id = v_target_slot_id;

        ELSE
          -- Step 2: Employee does NOT already have an active slot here.
          -- Can we claim an open vacant slot that existed prior to this import (NOT created in Phase B1 of this batch)?
          SELECT id INTO v_target_slot_id
            FROM public.plantilla_slots
           WHERE (store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode)))
             AND slot_status = 'open'
             AND (v_batch_created_slot_ids IS NULL OR id <> ALL(v_batch_created_slot_ids))
           ORDER BY slot_ordinal ASC
           LIMIT 1;

          IF v_target_slot_id IS NOT NULL THEN
            -- Claim pre-existing vacant slot
            UPDATE public.plantilla_slots
               SET slot_status = 'occupied',
                   store_id = COALESCE(store_id, v_new_store_id),
                   account_id = COALESCE(account_id, v_target_account_id),
                   group_id = COALESCE(group_id, v_target_group_id),
                   position = COALESCE(v_emp_rec.position, position),
                   is_roving = (v_store_cnt > 1),
                   employment_type = CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
                   current_occupant_plantilla_id = v_plantilla_id,
                   updated_at = now(),
                   updated_by = v_actor
             WHERE id = v_target_slot_id;

            -- Close / mark linked vacancies as Filled
            UPDATE public.vacancies
               SET status = 'Filled',
                   updated_at = now()
             WHERE upper(vcode) = upper(v_store_rec.vcode)
               AND status = 'Open';

            INSERT INTO public.slot_history (
              slot_id, account_id, action_type, old_value, new_value,
              reason_code, performed_by, remarks, created_at
            ) VALUES (
              v_target_slot_id, v_target_account_id, 'occupied',
              'open', 'occupied',
              CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_CLAIM_VACANT') THEN 'IMPORT_CLAIM_VACANT' ELSE NULL END,
              v_actor,
              format('Claimed vacant slot for employee %s via batch %s', v_emp_rec.employee_no, p_batch_id),
              now()
            );

          ELSE
            -- Step 3: No pre-existing open slot exists. Create a new occupied slot with incremented ordinal
            SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
              FROM public.plantilla_slots
             WHERE store_id = v_new_store_id OR (store_id IS NULL AND upper(legacy_vcode) = upper(v_store_rec.vcode));

            INSERT INTO public.plantilla_slots (
              store_id, account_id, group_id,
              position, employment_type, is_roving,
              slot_status, slot_ordinal, legacy_vcode,
              current_occupant_plantilla_id,
              created_at, updated_at, created_by, updated_by
            ) VALUES (
              v_new_store_id, v_target_account_id, v_target_group_id,
              COALESCE(v_emp_rec.position, 'Unknown'),
              CASE WHEN v_store_cnt > 1 THEN 'roving' ELSE 'stationary' END,
              (v_store_cnt > 1),
              'occupied', v_next_ordinal::smallint, v_store_rec.vcode,
              v_plantilla_id,
              now(), now(), v_actor, v_actor
            ) RETURNING id INTO v_target_slot_id;

            INSERT INTO public.slot_history (
              slot_id, account_id, action_type, old_value, new_value,
              reason_code, performed_by, remarks, created_at
            ) VALUES (
              v_target_slot_id, v_target_account_id, 'occupied',
              NULL, 'occupied',
              CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = 'IMPORT_OCCUPIED') THEN 'IMPORT_OCCUPIED' ELSE NULL END,
              v_actor,
              format('New occupied slot ordinal %s for employee %s', v_next_ordinal, v_emp_rec.employee_no),
              now()
            );
          END IF;
        END IF;

      END LOOP;

    END LOOP;

    -- Update batch status
    v_approved_timestamp := clock_timestamp();
    UPDATE public.plantilla_import_batches
       SET status             = 'approved',
           approved_by        = v_uid,
           approved_at        = v_approved_timestamp,
           rejection_reason   = NULL,
           commit_error       = NULL,
           stores_created     = v_stores_done,
           employees_created  = v_employees_done,
           allocations_created= v_alloc_done
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'success', true,
      'batch_id', p_batch_id,
      'status', 'approved',
      'stores_processed', v_stores_done,
      'employees_processed', v_employees_done,
      'allocations_created', v_alloc_done,
      'vacant_slots_created', v_vacant_slots,
      'approved_at', v_approved_timestamp
    );

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;
    v_err_out := format('[%s] %s', v_err_state, v_err_msg);

    UPDATE public.plantilla_import_batches
       SET status       = 'commit_failed',
           commit_error = v_err_out
     WHERE id = p_batch_id;

    RAISE EXCEPTION 'COMMIT_FAILED: %', v_err_out USING ERRCODE = v_err_state;
  END;
END;
$function$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. Data Reconciliation for Existing Batches & Rows (e.g. Batch #4898978)
-- ----------------------------------------------------------------------------
-- Clear purely advisory 'roving' flags from validation_flags
UPDATE public.plantilla_import_rows
   SET validation_flags = (
     SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
     FROM jsonb_array_elements(validation_flags) AS elem
     WHERE elem->>'flag' <> 'roving'
   )
 WHERE validation_flags @> '[{"flag":"roving"}]'::jsonb;

-- Update rows that now have no validation flags from flagged to valid
UPDATE public.plantilla_import_rows
   SET validation_status = 'valid'
 WHERE validation_status = 'flagged'
   AND (validation_flags IS NULL OR jsonb_array_length(validation_flags) = 0);

-- Recalculate batch metrics and status for affected pending batches
UPDATE public.plantilla_import_batches b
   SET valid_rows = sub.v_valid,
       flagged_rows = sub.v_flagged,
       status = CASE
         WHEN sub.v_blocked > 0 AND (sub.v_valid + sub.v_flagged) > 0 THEN 'partially_blocked'
         WHEN sub.v_blocked > 0 THEN 'blocked'
         WHEN sub.v_flagged > 0 THEN 'pending_review'
         ELSE 'pending_approval'
       END,
       updated_at = now()
  FROM (
    SELECT batch_id,
           count(*) FILTER (WHERE validation_status = 'valid') AS v_valid,
           count(*) FILTER (WHERE validation_status = 'flagged') AS v_flagged,
           count(*) FILTER (WHERE validation_status = 'blocked') AS v_blocked
      FROM public.plantilla_import_rows
     GROUP BY batch_id
  ) sub
 WHERE b.id = sub.batch_id
   AND b.status IN ('pending_review', 'pending_approval');
