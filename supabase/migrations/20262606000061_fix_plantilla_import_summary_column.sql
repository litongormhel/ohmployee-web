-- Migration: 20262606000061_fix_plantilla_import_summary_column.sql
-- Description: Fix column name in submit_plantilla_baseline_import:
--   Change non-existent column `summary_json` to `error_summary` in plantilla_import_batches UPDATE.
--   Also preserve batch counters and updated_at timestamp.

BEGIN;

CREATE OR REPLACE FUNCTION public.submit_plantilla_baseline_import(
  p_file_name  text,
  p_group_id   uuid,
  p_account_id uuid,
  p_rows       jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_role       text := public.get_my_role();
  v_batch_id   uuid;
  v_acct_group uuid;
  v_acct_name  text;

  v_row        jsonb;
  v_idx        int := 0;

  -- Store fields
  v_vcode       text;
  v_store_nm    text;
  v_mother_acct text;
  v_prov        text;
  v_city        text;
  v_position    text;

  -- Employee fields
  v_emp         text;
  v_last        text;
  v_first       text;
  v_middle      text;
  v_date_hired  text;

  -- Auto-computed & Derived
  v_emp_type    text;
  v_req_hc      text;
  v_with_pen    boolean;

  -- Optional fields
  v_civil_status    text;
  v_rate_raw        text;
  v_birthdate_raw   text;
  v_contact_raw     text;
  v_address_raw     text;
  v_sched_days_raw  text;
  v_sched_time_raw  text;
  v_dayoff_raw      text;
  v_coord_raw       text;
  v_hrco_email_raw  text;

  -- HRCO resolution
  v_acct_hrco_id     uuid;
  v_resolved_hrco_id uuid;
  v_needs_hrco       boolean;
  v_row_hrco_id      uuid;
  v_row_final_hrco_id uuid;
  v_row_needs_hrco   boolean;

  -- Per-row resolution state
  v_store_id        uuid;
  v_store_acct      uuid;
  v_store_grp       uuid;
  v_db_store_name   text;
  v_errs            jsonb;
  v_flags           jsonb;
  v_status          text;
  v_is_roving       boolean;
  v_store_cnt       int;
  v_is_new_store    boolean;
  v_is_existing_emp boolean;
  v_seen_pairs      text[] := '{}'::text[];

  -- Counters
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
  -- Auth & Governance
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE = '42501';
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

  -- Resolve Account HRCO state:
  -- If accounts.hrco_user_id is assigned, use it. Otherwise attempt users_profile fallback.
  v_resolved_hrco_id := v_acct_hrco_id;
  IF v_resolved_hrco_id IS NULL THEN
    SELECT u.id INTO v_resolved_hrco_id
      FROM public.users_profile u
     WHERE u.is_active = true
       AND u.account_id = p_account_id
       AND lower(u.role) IN ('hrco', 'hr coordinator')
     LIMIT 1;
  END IF;

  -- Account-level needs_hrco is false if an HRCO is assigned
  v_needs_hrco := (v_resolved_hrco_id IS NULL);

  -- Create batch
  INSERT INTO public.plantilla_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- Main processing loop
  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx      := v_idx + 1;
    v_total    := v_total + 1;
    v_errs     := '[]'::jsonb;
    v_flags    := '[]'::jsonb;
    v_status   := 'valid';
    v_is_roving     := false;
    v_store_cnt     := 0;
    v_is_new_store  := false;
    v_is_existing_emp := false;
    v_store_id := NULL; v_store_acct := NULL; v_store_grp := NULL; v_db_store_name := NULL;

    -- Parse Store Fields (Always Required)
    v_vcode       := upper(NULLIF(trim(COALESCE(v_row->>'VCODE','')), ''));
    v_store_nm    := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')), '');
    v_mother_acct := NULLIF(trim(COALESCE(v_row->>'MOTHER_ACCOUNT','')), '');
    v_prov        := NULLIF(trim(COALESCE(v_row->>'AREA_PROVINCE','')), '');
    v_city        := NULLIF(trim(COALESCE(v_row->>'AREA_CITY','')), '');
    v_position    := NULLIF(trim(COALESCE(v_row->>'POSITION','')), '');

    -- Parse Employee Fields (Conditionally Required)
    v_emp         := upper(NULLIF(trim(COALESCE(v_row->>'EMPLOYEE_NO','')), ''));
    v_last        := NULLIF(trim(COALESCE(v_row->>'LAST_NAME','')), '');
    v_first       := NULLIF(trim(COALESCE(v_row->>'FIRST_NAME','')), '');
    v_middle      := NULLIF(trim(COALESCE(v_row->>'MIDDLE_NAME','')), '');
    v_date_hired  := NULLIF(trim(COALESCE(v_row->>'DATE_HIRED','')), '');

    -- Optional Fields
    v_civil_status    := NULLIF(trim(COALESCE(v_row->>'CIVIL_STATUS','')), '');
    v_rate_raw        := NULLIF(trim(COALESCE(v_row->>'RATE','')), '');
    v_birthdate_raw   := NULLIF(trim(COALESCE(v_row->>'DATE_OF_BIRTH', v_row->>'BIRTHDATE', '')), '');
    v_contact_raw     := NULLIF(trim(COALESCE(v_row->>'CONTACT_NO', v_row->>'CONTACT', '')), '');
    v_address_raw     := NULLIF(trim(COALESCE(v_row->>'ADDRESS','')), '');
    v_sched_days_raw  := NULLIF(trim(COALESCE(v_row->>'SCHEDULE_DAYS', v_row->>'SCHEDULE', '')), '');
    v_sched_time_raw  := NULLIF(trim(COALESCE(v_row->>'SCHEDULE_TIME','')), '');
    v_dayoff_raw      := NULLIF(trim(COALESCE(v_row->>'DAYOFF','')), '');
    v_coord_raw       := NULLIF(trim(COALESCE(v_row->>'COORDINATOR','')), '');
    v_hrco_email_raw  := NULLIF(trim(COALESCE(v_row->>'HRCO_EMAIL','')), '');

    -- Resolve row HRCO
    v_row_hrco_id := NULL;
    IF v_hrco_email_raw IS NOT NULL THEN
      SELECT u.id INTO v_row_hrco_id
        FROM public.users_profile u
       WHERE lower(trim(u.email)) = lower(trim(v_hrco_email_raw))
         AND u.is_active = true
       LIMIT 1;
    END IF;

    v_row_final_hrco_id := COALESCE(v_row_hrco_id, v_resolved_hrco_id);
    -- Conditional HRCO Warning: ONLY appear if NEITHER account nor row has an assigned HRCO
    v_row_needs_hrco := (v_row_final_hrco_id IS NULL AND (v_hrco_email_raw IS NULL OR trim(v_hrco_email_raw) = ''));

    -- Required Store Field Validations
    IF v_vcode       IS NULL THEN v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE is required"}]'::jsonb; END IF;
    IF v_store_nm    IS NULL THEN v_errs := v_errs || '[{"field":"STORE_NAME","msg":"STORE_NAME is required"}]'::jsonb; END IF;
    IF v_mother_acct IS NULL THEN v_errs := v_errs || '[{"field":"MOTHER_ACCOUNT","msg":"MOTHER_ACCOUNT is required"}]'::jsonb; END IF;
    IF v_prov        IS NULL THEN v_errs := v_errs || '[{"field":"AREA_PROVINCE","msg":"AREA_PROVINCE is required"}]'::jsonb; END IF;
    IF v_city        IS NULL THEN v_errs := v_errs || '[{"field":"AREA_CITY","msg":"AREA_CITY is required"}]'::jsonb; END IF;
    IF v_position    IS NULL THEN v_errs := v_errs || '[{"field":"POSITION","msg":"POSITION is required"}]'::jsonb; END IF;

    -- Invariant 2: 1 Store Name = 1 VCODE Identity in Batch
    IF v_vcode IS NOT NULL AND v_store_nm IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_rows) elem
         WHERE upper(trim(elem->>'VCODE')) = v_vcode
           AND upper(trim(elem->>'STORE_NAME')) <> upper(trim(v_store_nm))
      ) THEN
        v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE is mapped to multiple different STORE_NAMEs in upload"}]'::jsonb;
      END IF;

      IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_rows) elem
         WHERE upper(trim(elem->>'STORE_NAME')) = upper(trim(v_store_nm))
           AND upper(trim(elem->>'VCODE')) <> v_vcode
      ) THEN
        v_errs := v_errs || '[{"field":"STORE_NAME","msg":"STORE_NAME is mapped to multiple different VCODEs in upload"}]'::jsonb;
      END IF;
    END IF;

    -- Invariant 2: 1 Store Name = 1 VCODE Identity against DB
    IF v_vcode IS NOT NULL THEN
      SELECT s.id, s.account_id, s.group_id, s.store_name
        INTO v_store_id, v_store_acct, v_store_grp, v_db_store_name
        FROM public.stores s
       WHERE upper(s.vcode) = v_vcode AND s.status = 'active'
       ORDER BY s.created_at LIMIT 1;

      IF v_store_id IS NOT NULL THEN
        IF v_store_acct <> p_account_id THEN
          v_errs := v_errs || '[{"field":"VCODE","msg":"cross-account: store VCODE belongs to a different account in DB"}]'::jsonb;
          v_xacct := v_xacct + 1;
        END IF;
        IF v_store_grp <> p_group_id THEN
          v_errs := v_errs || '[{"field":"VCODE","msg":"cross-group: store VCODE belongs to a different group in DB"}]'::jsonb;
          v_xgroup := v_xgroup + 1;
        END IF;
        IF v_store_nm IS NOT NULL AND upper(trim(v_db_store_name)) <> upper(trim(v_store_nm)) THEN
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field', 'STORE_NAME',
            'msg', format('1 Store = 1 VCODE conflict: VCODE "%s" already exists in DB with store name "%s"', v_vcode, v_db_store_name)
          ));
        END IF;
      END IF;
    END IF;

    v_is_new_store := (v_store_id IS NULL);

    -- Invariant 7: Strict Middle Name & Partial Employee Row Block
    IF v_emp IS NULL THEN
      -- Vacant row: valid baseline slot (do NOT skip even if store already exists)
      IF v_last IS NOT NULL OR v_first IS NOT NULL OR v_middle IS NOT NULL OR v_date_hired IS NOT NULL THEN
        v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"EMPLOYEE_NO is required when employee details are provided"}]'::jsonb;
      END IF;
    ELSE
      -- Assigned employee row
      IF v_last IS NULL THEN v_errs := v_errs || '[{"field":"LAST_NAME","msg":"LAST_NAME is required when EMPLOYEE_NO is provided"}]'::jsonb; END IF;
      IF v_first IS NULL THEN v_errs := v_errs || '[{"field":"FIRST_NAME","msg":"FIRST_NAME is required when EMPLOYEE_NO is provided"}]'::jsonb; END IF;
      IF v_date_hired IS NULL THEN v_errs := v_errs || '[{"field":"DATE_HIRED","msg":"DATE_HIRED is required when EMPLOYEE_NO is provided"}]'::jsonb; END IF;

      -- Middle name strict check
      IF v_middle IS NULL THEN
        v_errs := v_errs || '[{"field":"MIDDLE_NAME","msg":"MIDDLE_NAME is required when assigning an employee"}]'::jsonb;
      ELSE
        DECLARE
          v_clean_mid text := regexp_replace(v_middle, '[^a-zA-Z]', '', 'g');
        BEGIN
          IF upper(trim(v_middle)) NOT IN ('NA', 'N/A') AND length(v_clean_mid) < 2 THEN
            v_errs := v_errs || '[{"field":"MIDDLE_NAME","msg":"MIDDLE_NAME must be at least 2 alpha characters or ''NA'' (single-letter initials not accepted)"}]'::jsonb;
          END IF;
        END;
      END IF;
    END IF;

    -- Invariant 4: Compute Roving / Stationary and Fractional Headcount
    IF v_emp IS NOT NULL THEN
      SELECT count(DISTINCT upper(trim(elem->>'VCODE'))) INTO v_store_cnt
        FROM jsonb_array_elements(p_rows) elem
       WHERE upper(trim(elem->>'EMPLOYEE_NO')) = v_emp
         AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL;

      v_store_cnt := COALESCE(v_store_cnt, 1);
      IF v_store_cnt > 1 THEN
        v_is_roving := true;
        v_emp_type := 'roving';
        v_req_hc := trim(to_char(round(1.0 / v_store_cnt, 2), 'FM999990.00'));
        v_flags := v_flags || jsonb_build_array(jsonb_build_object(
          'flag', 'roving',
          'msg', format('roving employee across %s stores (fractional HC %s)', v_store_cnt, v_req_hc)
        ));
      ELSE
        v_emp_type := 'stationary';
        v_req_hc := '1.00';
      END IF;
    ELSE
      v_emp_type := 'stationary';
      v_req_hc := '1.00';
    END IF;

    -- Invariant 6: Derive with_penalty from MOTHER_ACCOUNT
    v_with_pen := false;
    IF v_mother_acct IS NOT NULL THEN
      SELECT with_penalty INTO v_with_pen
        FROM public.mother_account_configs
       WHERE upper(trim(mother_account)) = upper(trim(v_mother_acct))
       LIMIT 1;

      IF v_with_pen IS NULL THEN
        IF lower(COALESCE(v_row->>'WITH_PENALTY','')) IN ('yes','y','true','1') THEN
          v_with_pen := true;
        ELSE
          v_with_pen := false;
        END IF;
        INSERT INTO public.mother_account_configs (mother_account, with_penalty)
        VALUES (upper(trim(v_mother_acct)), v_with_pen)
        ON CONFLICT (mother_account) DO NOTHING;
      END IF;
    END IF;

    -- Conflict Checks for Assigned Employee
    IF v_emp IS NOT NULL AND v_status IS DISTINCT FROM 'skipped' THEN
      IF EXISTS (
        SELECT 1 FROM public.plantilla p
         WHERE p.employee_no = v_emp
           AND p.is_deleted = false
           AND p.account_id IS NOT NULL AND p.account_id <> p_account_id
           AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
      ) THEN
        v_errs  := v_errs  || '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee exists in active plantilla under a different account"}]'::jsonb;
        v_xacct := v_xacct + 1;
      END IF;

      IF (v_emp || '::' || v_vcode) = ANY(v_seen_pairs) THEN
        v_status := 'skipped';
        v_flags  := v_flags || '[{"flag":"duplicate_emp_vcode","msg":"same employee+VCODE already processed in batch - skipped"}]'::jsonb;
      END IF;
    END IF;

    -- Final status resolution
    IF v_status IS DISTINCT FROM 'skipped' THEN
      IF jsonb_array_length(v_errs) > 0 THEN
        v_status := 'blocked';
      ELSIF jsonb_array_length(v_flags) > 0 THEN
        v_status := 'flagged';
      ELSE
        v_status := 'valid';
      END IF;
    END IF;

    IF v_emp IS NOT NULL AND v_vcode IS NOT NULL AND v_status IN ('valid', 'flagged') THEN
      v_seen_pairs := array_append(v_seen_pairs, (v_emp || '::' || v_vcode));
    END IF;

    IF v_vcode IS NOT NULL AND v_status <> 'blocked' THEN
      IF v_is_new_store THEN v_new_stores := v_new_stores + 1;
      ELSE v_ex_stores := v_ex_stores + 1;
      END IF;
    END IF;

    -- Insert into import rows table
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
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_vcode, COALESCE(v_store_nm, v_row->>'STORE_NAME'), v_mother_acct, v_prov, v_city, v_position,
      v_emp_type, v_req_hc, CASE WHEN v_with_pen THEN 'yes' ELSE 'no' END,
      v_emp, v_last, v_first, v_middle, v_date_hired,
      v_civil_status, v_rate_raw, v_birthdate_raw, v_contact_raw, v_address_raw,
      v_sched_days_raw, v_sched_time_raw, v_dayoff_raw, v_coord_raw, v_hrco_email_raw,
      v_row_final_hrco_id, v_row_needs_hrco,
      v_store_id, p_account_id, p_group_id,
      v_status, v_errs, v_flags,
      v_is_roving, v_store_cnt, v_is_new_store, v_is_existing_emp
    );

    IF v_status = 'valid' THEN v_valid := v_valid + 1;
    ELSIF v_status = 'flagged' THEN v_flagged := v_flagged + 1;
    ELSIF v_status = 'skipped' THEN v_skipped := v_skipped + 1;
    ELSIF v_status = 'blocked' THEN v_blocked := v_blocked + 1;
    END IF;

  END LOOP;

  -- Update batch summary
  v_summary := jsonb_build_object(
    'total_rows', v_total,
    'valid_rows', v_valid,
    'flagged_rows', v_flagged,
    'skipped_rows', v_skipped,
    'blocked_rows', v_blocked,
    'new_stores', v_new_stores,
    'existing_stores', v_ex_stores,
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
END$func$;

REVOKE ALL ON FUNCTION public.submit_plantilla_baseline_import(text, uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_plantilla_baseline_import(text, uuid, uuid, jsonb) TO authenticated;

COMMIT;
