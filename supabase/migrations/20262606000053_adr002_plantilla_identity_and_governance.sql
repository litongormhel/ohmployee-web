-- ============================================================
-- Migration: 20262606000053_adr002_plantilla_identity_and_governance.sql
-- ADR-002: Plantilla Import, Store Identity, Headcount Governance & Rollback
-- ============================================================

-- 1. Schema Additions / Adjustments

-- 1.1 Add mother_account and schedule fields to plantilla_import_rows
ALTER TABLE public.plantilla_import_rows
  ADD COLUMN IF NOT EXISTS mother_account text,
  ADD COLUMN IF NOT EXISTS schedule_days text,
  ADD COLUMN IF NOT EXISTS schedule_time text,
  ADD COLUMN IF NOT EXISTS needs_hrco boolean DEFAULT false;

-- 1.2 Add mother_account and schedule fields to stores
ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS mother_account text,
  ADD COLUMN IF NOT EXISTS schedule_days text,
  ADD COLUMN IF NOT EXISTS schedule_time text;

-- 1.3 Add mother_account and schedule fields to accounts
ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS mother_account text,
  ADD COLUMN IF NOT EXISTS with_penalty boolean DEFAULT false;

-- 1.4 Add fields to plantilla
ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS mother_account text,
  ADD COLUMN IF NOT EXISTS schedule_days text,
  ADD COLUMN IF NOT EXISTS schedule_time text,
  ADD COLUMN IF NOT EXISTS needs_hrco boolean DEFAULT false;

-- 1.5 Add fields to employee_store_allocations
ALTER TABLE public.employee_store_allocations
  ADD COLUMN IF NOT EXISTS schedule_days text,
  ADD COLUMN IF NOT EXISTS schedule_time text;

-- 1.6 Add tracking columns to plantilla_import_batches
ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS rollback_rejected_by uuid REFERENCES public.users_profile(id),
  ADD COLUMN IF NOT EXISTS rollback_rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_by_name text,
  ADD COLUMN IF NOT EXISTS rejected_by_name text;

-- 1.7 Mother Account Configuration Table
CREATE TABLE IF NOT EXISTS public.mother_account_configs (
  mother_account text PRIMARY KEY,
  with_penalty boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Seed mother_account_configs from existing stores and accounts
INSERT INTO public.mother_account_configs (mother_account, with_penalty)
SELECT DISTINCT upper(trim(a.account_name)), bool_or(COALESCE(s.with_penalty, false))
FROM public.accounts a
JOIN public.stores s ON s.account_id = a.id
WHERE a.account_name IS NOT NULL AND trim(a.account_name) <> ''
GROUP BY 1
ON CONFLICT (mother_account) DO NOTHING;

-- 2. Reactive Backfill: Account HRCO Assignment Trigger
CREATE OR REPLACE FUNCTION public.fn_trg_account_hrco_backfill()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.hrco_user_id IS NOT NULL AND (OLD.hrco_user_id IS DISTINCT FROM NEW.hrco_user_id) THEN
    -- Backfill all plantilla rows for this account that need HRCO
    UPDATE public.plantilla
       SET hrco_user_id_snapshot = NEW.hrco_user_id,
           needs_hrco = false,
           updated_at = now()
     WHERE account_id = NEW.id
       AND needs_hrco = true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_hrco_backfill ON public.accounts;
CREATE TRIGGER trg_account_hrco_backfill
  AFTER UPDATE OF hrco_user_id ON public.accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_account_hrco_backfill();

-- 3. Zero-Edit Lock Helper Functions with False-Positive Guard
CREATE OR REPLACE FUNCTION public.get_plantilla_import_first_modified_record(
  p_batch_id uuid,
  p_approved_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_rec record;
  v_grace_approved_at timestamptz := p_approved_at + interval '2 seconds';
BEGIN
  IF p_approved_at IS NULL THEN
    RETURN NULL;
  END IF;

  -- Check plantilla rows
  SELECT p.employee_no, p.employee_name, p.updated_at, 'plantilla' AS entity
    INTO v_rec
    FROM public.plantilla_import_commit_snapshots s
    JOIN public.plantilla p ON p.id = s.entity_id
   WHERE s.batch_id = p_batch_id
     AND s.entity_type = 'plantilla'
     AND s.action IN ('insert', 'update', 'reactivate')
     AND (
       p.source_baseline_import_batch_id IS DISTINCT FROM p_batch_id
       OR p.updated_at > v_grace_approved_at
     )
   ORDER BY p.updated_at DESC
   LIMIT 1;

  IF v_rec.employee_no IS NOT NULL THEN
    RETURN jsonb_build_object(
      'entity', v_rec.entity,
      'employee_no', v_rec.employee_no,
      'employee_name', v_rec.employee_name,
      'updated_at', v_rec.updated_at
    );
  END IF;

  -- Check stores
  SELECT st.vcode, st.store_name, st.updated_at, 'store' AS entity
    INTO v_rec
    FROM public.plantilla_import_commit_snapshots s
    JOIN public.stores st ON st.id = s.entity_id
   WHERE s.batch_id = p_batch_id
     AND s.entity_type = 'store'
     AND s.action IN ('insert', 'update')
     AND (
       st.source_import_id IS DISTINCT FROM p_batch_id
       OR st.updated_at > v_grace_approved_at
     )
   ORDER BY st.updated_at DESC
   LIMIT 1;

  IF v_rec.vcode IS NOT NULL THEN
    RETURN jsonb_build_object(
      'entity', v_rec.entity,
      'vcode', v_rec.vcode,
      'store_name', v_rec.store_name,
      'updated_at', v_rec.updated_at
    );
  END IF;

  RETURN NULL;
END;
$func$;

CREATE OR REPLACE FUNCTION public._import_records_modified_after_approval(
  p_module text,
  p_batch_id uuid,
  p_approved_at timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_batch_status text;
  v_grace_approved_at timestamptz;
BEGIN
  IF p_approved_at IS NULL THEN
    RETURN false;
  END IF;

  v_grace_approved_at := p_approved_at + interval '2 seconds';

  IF p_module = 'plantilla' THEN
    SELECT b.status INTO v_batch_status
      FROM public.plantilla_import_batches b
     WHERE b.id = p_batch_id;

    IF v_batch_status = 'rolled_back' THEN
      RETURN false;
    END IF;

    RETURN EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.plantilla p ON p.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'plantilla'
         AND s.action IN ('insert', 'update', 'reactivate')
         AND (
           p.source_baseline_import_batch_id IS DISTINCT FROM p_batch_id
           OR p.updated_at > v_grace_approved_at
         )
    ) OR EXISTS (
      SELECT 1
        FROM public.plantilla_import_commit_snapshots s
        JOIN public.stores st ON st.id = s.entity_id
       WHERE s.batch_id = p_batch_id
         AND s.entity_type = 'store'
         AND s.action IN ('insert', 'update')
         AND (
           st.source_import_id IS DISTINCT FROM p_batch_id
           OR st.updated_at > v_grace_approved_at
         )
    ) OR EXISTS (
      SELECT 1
        FROM public.employee_store_allocations a
       WHERE a.source_import_batch_id = p_batch_id
         AND a.created_at > v_grace_approved_at
    );
  END IF;

  IF p_module = 'vacancy' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.vacancies v
       WHERE v.source_vacancy_import_batch_id = p_batch_id
         AND v.updated_at > v_grace_approved_at
    );
  END IF;

  RETURN false;
END;
$func$;

-- 4. Rewrite submit_plantilla_baseline_import with ADR-002 Invariants
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
  v_resolved_hrco_id uuid;
  v_needs_hrco       boolean;
  v_acct_hrco_cnt    int;

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
  SELECT group_id, account_name INTO v_acct_group, v_acct_name
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

  -- Resolve Account HRCO state (Invariant 9)
  v_resolved_hrco_id := NULL;
  v_needs_hrco := false;

  SELECT count(DISTINCT u.id) INTO v_acct_hrco_cnt
    FROM public.users_profile u
   WHERE u.is_active = true
     AND (
       u.id = (SELECT hrco_user_id FROM public.accounts WHERE id = p_account_id)
       OR (u.account_id = p_account_id AND u.role IN ('HRCO', 'HR Coordinator'))
     );

  IF v_acct_hrco_cnt = 1 THEN
    SELECT u.id INTO v_resolved_hrco_id
      FROM public.users_profile u
     WHERE u.is_active = true
       AND (
         u.id = (SELECT hrco_user_id FROM public.accounts WHERE id = p_account_id)
         OR (u.account_id = p_account_id AND u.role IN ('HRCO', 'HR Coordinator'))
       )
     LIMIT 1;
  ELSE
    v_needs_hrco := true;
  END IF;

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
      -- Vacant row
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

    -- Invariant 5: Multi-batch existing VCODE rule
    IF v_vcode IS NOT NULL AND NOT v_is_new_store THEN
      IF v_emp IS NULL THEN
        -- Vacant row for existing VCODE -> SKIP
        v_status := 'skipped';
        v_flags  := v_flags || '[{"flag":"existing_vcode_skipped","msg":"Existing VCODE skipped (vacant row — only fresh VCODEs create new vacant slots)"}]'::jsonb;
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
        v_flags  := v_flags || '[{"flag":"duplicate_emp_vcode","msg":"same employee+VCODE already processed in batch — skipped"}]'::jsonb;
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
      v_resolved_hrco_id, v_needs_hrco,
      v_store_id, p_account_id, p_group_id,
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

  SELECT count(*) INTO v_roving
    FROM (
      SELECT upper(trim(elem->>'EMPLOYEE_NO'))
        FROM jsonb_array_elements(p_rows) elem
       WHERE NULLIF(trim(elem->>'EMPLOYEE_NO'),'') IS NOT NULL
         AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
       GROUP BY 1 HAVING count(DISTINCT upper(trim(elem->>'VCODE'))) > 1
    ) sub;

  -- Summary object
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
     SET status                   = v_final,
         total_rows               = v_total,
         valid_rows               = v_valid,
         flagged_rows             = v_flagged,
         skipped_rows             = v_skipped,
         blocked_rows             = v_blocked,
         roving_detected          = v_roving,
         new_stores_count         = v_new_stores,
         existing_stores_count    = v_ex_stores,
         existing_employees_count = v_ex_emps,
         cross_account_conflicts  = v_xacct,
         cross_group_conflicts    = v_xgroup,
         over_20_store_warnings   = v_over20,
         missing_from_upload_count= v_missing,
         error_summary            = v_summary,
         updated_at               = now()
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
END$func$;

REVOKE ALL ON FUNCTION public.submit_plantilla_baseline_import(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_plantilla_baseline_import(text,uuid,uuid,jsonb) TO authenticated;

-- 5. Rewrite approve_plantilla_import_batch with ADR-002 Commit Rules
CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_user_name  text;
  v_batch      public.plantilla_import_batches%ROWTYPE;
  v_acct_name  text;

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
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;
  v_vacant_slots   int := 0;

  -- Slot claiming
  v_target_slot_id uuid;
  v_next_ordinal   int;

  -- Commit counts
  v_committable int;
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
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)', v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;
  SELECT account_name INTO v_acct_name FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- Pre-commit guard: Committable includes valid + flagged with vcode (employee_no may be null for vacant slots)
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid','flagged')
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch' USING ERRCODE = '22023';
  END IF;

  BEGIN
    -- Phase A: Store upsert for all committable rows
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, mother_account, area_province, area_city,
             employment_type, with_penalty_raw, schedule_days, schedule_time,
             row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
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
          group_id, account_id, status,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.mother_account, v_srow.area_province, v_srow.area_city,
          COALESCE(v_srow.employment_type, 'stationary'), v_pen_bool, v_srow.schedule_days, v_srow.schedule_time,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active',
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

    -- Phase B1: Vacant Store Slot Creation (rows where employee_no IS NULL)
    FOR v_vrow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, position, area_province, area_city, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND employee_no IS NULL
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      SELECT id INTO v_new_store_id FROM public.stores WHERE upper(vcode) = upper(v_vrow.vcode) AND status = 'active' LIMIT 1;

      -- Check if open slot already exists
      IF NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots
         WHERE legacy_vcode = v_vrow.vcode AND slot_status = 'open'
      ) THEN
        INSERT INTO public.plantilla_slots (
          store_id, account_id, group_id,
          position, employment_type, is_roving,
          slot_status, slot_ordinal, legacy_vcode,
          current_occupant_plantilla_id,
          created_at, updated_at, created_by, updated_by
        ) VALUES (
          v_new_store_id, v_batch.selected_account_id, v_batch.selected_group_id,
          COALESCE(v_vrow.position, 'Unknown'), 'stationary', false,
          'open', 1, v_vrow.vcode, NULL,
          now(), now(), v_actor, v_actor
        ) RETURNING id INTO v_target_slot_id;

        -- Sync vacancies record for shadow view
        INSERT INTO public.vacancies (
          vcode, store_name, area_city, province, area_name,
          required_headcount, status, store_id, account_id, group_id,
          created_at, updated_at, created_by
        ) VALUES (
          v_vrow.vcode, v_vrow.store_name, v_vrow.area_city, v_vrow.area_province,
          v_vrow.area_province || ' - ' || v_vrow.area_city,
          1, 'Open', v_new_store_id, v_batch.selected_account_id, v_batch.selected_group_id,
          now(), now(), v_actor
        ) ON CONFLICT (vcode) DO UPDATE
        SET status = 'Open',
            deleted_at = NULL,
            is_archived = false,
            updated_at = now();

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type, old_value, new_value,
          reason_code, performed_by, remarks, created_at
        ) VALUES (
          v_target_slot_id, v_batch.selected_account_id, 'created',
          NULL, 'open', 'IMPORT_VACANT_SLOT', v_actor,
          format('Vacant slot created by baseline import batch %s', p_batch_id), now()
        );

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_vrow.row_id, 'slot', v_target_slot_id, 'insert', NULL, v_uid);

        v_vacant_slots := v_vacant_slots + 1;
      END IF;
    END LOOP;

    -- Phase B2: Assigned Employee Upsert & Slot Claiming
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number))[1]                            AS middle_name,
        (array_agg(position    ORDER BY row_number) FILTER (WHERE position IS NOT NULL))[1] AS position,
        (array_agg(mother_account ORDER BY row_number) FILTER (WHERE mother_account IS NOT NULL))[1] AS mother_account,
        (array_agg(area_province ORDER BY row_number) FILTER (WHERE area_province IS NOT NULL))[1] AS area_province,
        (array_agg(area_city ORDER BY row_number) FILTER (WHERE area_city IS NOT NULL))[1] AS area_city,
        (array_agg(civil_status ORDER BY row_number) FILTER (WHERE civil_status IS NOT NULL))[1] AS civil_status,
        (array_agg(rate_raw ORDER BY row_number) FILTER (WHERE rate_raw IS NOT NULL))[1] AS rate_raw,
        (array_agg(birthdate_raw ORDER BY row_number) FILTER (WHERE birthdate_raw IS NOT NULL))[1] AS birthdate_raw,
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
         AND validation_status IN ('valid','flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      -- Plantilla lookup
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no AND is_deleted = false
       LIMIT 1;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      IF v_plantilla_id IS NULL THEN
        -- Insert new plantilla record
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          mother_account, position, deployment_type,
          area, area_name_snapshot,
          civil_status, daily_rate, birthdate,
          contact_no, address,
          schedule, schedule_days, schedule_time, dayoff, coordinator,
          hrco_user_id_snapshot, needs_hrco,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        ) VALUES (
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no, v_acct_name, 'Active',
          v_batch.selected_account_id, v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          v_emp_rec.mother_account, v_emp_rec.position,
          CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          COALESCE(v_emp_rec.area_city, v_emp_rec.area_province),
          v_emp_rec.civil_status,
          NULLIF(trim(COALESCE(v_emp_rec.rate_raw,'')), '')::numeric,
          NULLIF(trim(COALESCE(v_emp_rec.birthdate_raw,'')), '')::date,
          v_emp_rec.contact_raw, v_emp_rec.address_raw,
          v_emp_rec.schedule_days, v_emp_rec.schedule_days, v_emp_rec.schedule_time,
          v_emp_rec.dayoff_raw, v_emp_rec.coordinator_raw,
          v_emp_rec.hrco_id, COALESCE(v_emp_rec.needs_hrco_agg, false),
          p_batch_id, v_actor, v_actor
        ) RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);
      ELSE
        -- Update existing plantilla record
        UPDATE public.plantilla
           SET employee_name      = v_emp_name,
               last_name          = v_emp_rec.last_name,
               first_name         = v_emp_rec.first_name,
               middle_name        = v_emp_rec.middle_name,
               mother_account     = COALESCE(v_emp_rec.mother_account, mother_account),
               position           = COALESCE(v_emp_rec.position, position),
               deployment_type    = CASE WHEN v_store_cnt > 1 THEN 'Roving' ELSE 'Stationary' END,
               schedule_days      = COALESCE(v_emp_rec.schedule_days, schedule_days),
               schedule_time      = COALESCE(v_emp_rec.schedule_time, schedule_time),
               dayoff             = COALESCE(v_emp_rec.dayoff_raw, dayoff),
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

      -- Store allocations loop
      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, pir.store_name, pir.schedule_days, pir.schedule_time
          FROM public.plantilla_import_rows pir
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid','flagged')
         ORDER BY pir.vcode, pir.row_number
      LOOP
        SELECT id INTO v_new_store_id FROM public.stores WHERE upper(vcode) = upper(v_store_rec.vcode) AND status = 'active' LIMIT 1;

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
          v_batch.selected_account_id, v_batch.selected_group_id,
          v_filled, v_store_cnt,
          v_store_rec.schedule_days, v_store_rec.schedule_time,
          CURRENT_DATE, true,
          p_batch_id, v_actor
        );
        v_alloc_done := v_alloc_done + 1;

        -- Safeguard 3: Vacant-to-Occupied Slot Claiming
        v_target_slot_id := NULL;
        SELECT id INTO v_target_slot_id
          FROM public.plantilla_slots
         WHERE legacy_vcode = v_store_rec.vcode
           AND slot_status = 'open'
         ORDER BY slot_ordinal ASC
         LIMIT 1;

        IF v_target_slot_id IS NOT NULL THEN
          -- Claim and transition open vacant slot to occupied
          UPDATE public.plantilla_slots
             SET slot_status = 'occupied',
                 current_occupant_plantilla_id = v_plantilla_id,
                 updated_at = now(),
                 updated_by = v_actor
           WHERE id = v_target_slot_id;

          -- Close / mark linked vacancies as Filled
          UPDATE public.vacancies
             SET status = 'Filled',
                 updated_at = now()
           WHERE vcode = v_store_rec.vcode
             AND status = 'Open';

          INSERT INTO public.slot_history (
            slot_id, account_id, action_type, old_value, new_value,
            reason_code, performed_by, remarks, created_at
          ) VALUES (
            v_target_slot_id, v_batch.selected_account_id, 'occupied',
            'open', 'occupied', 'IMPORT_CLAIM_VACANT', v_actor,
            format('Claimed vacant slot for employee %s via batch %s', v_emp_rec.employee_no, p_batch_id),
            now()
          );
        ELSE
          -- Create additional slot with incremented ordinal if needed
          IF NOT EXISTS (
            SELECT 1 FROM public.plantilla_slots
             WHERE legacy_vcode = v_store_rec.vcode
               AND current_occupant_plantilla_id = v_plantilla_id
          ) THEN
            SELECT COALESCE(MAX(slot_ordinal), 0) + 1 INTO v_next_ordinal
              FROM public.plantilla_slots
             WHERE legacy_vcode = v_store_rec.vcode;

            INSERT INTO public.plantilla_slots (
              store_id, account_id, group_id,
              position, employment_type, is_roving,
              slot_status, slot_ordinal, legacy_vcode,
              current_occupant_plantilla_id,
              created_at, updated_at, created_by, updated_by
            ) VALUES (
              v_new_store_id, v_batch.selected_account_id, v_batch.selected_group_id,
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
              v_target_slot_id, v_batch.selected_account_id, 'occupied',
              NULL, 'occupied', 'IMPORT_OCCUPIED', v_actor,
              format('New occupied slot ordinal %s for employee %s', v_next_ordinal, v_emp_rec.employee_no),
              now()
            );
          END IF;
        END IF;

      END LOOP;

    END LOOP;

    -- Safeguard 2: Zero-Edit Lock False-Positive Guard
    -- Ensure approved_at is recorded AFTER all entity changes finish.
    v_approved_timestamp := clock_timestamp();

    UPDATE public.plantilla_import_batches
       SET status              = 'approved',
           approved_by         = v_uid,
           approved_at         = v_approved_timestamp,
           approved_by_name    = v_user_name,
           committed_stores    = v_stores_done,
           committed_employees = v_employees_done,
           rollback_ready      = true,
           updated_at          = v_approved_timestamp
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id',            p_batch_id,
      'status',              'approved',
      'stores_committed',    v_stores_done,
      'employees_committed', v_employees_done,
      'vacant_slots_created', v_vacant_slots,
      'allocations_created', v_alloc_done
    );

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;

    v_err_out := format('[%s] %s', v_err_state, v_err_msg);

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
END$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated;

-- 6. Rollback Governance RPCs (Invariant 10)

-- 6.1 Request Rollback (Uploader / Data Team)
CREATE OR REPLACE FUNCTION public.request_plantilla_import_rollback(
  p_batch_id    uuid,
  p_reason_code text,
  p_reason_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid         uuid := auth.uid();
  v_batch       public.plantilla_import_batches%ROWTYPE;
  v_modified    jsonb;
BEGIN
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be requested for rollback (current=%)', v_batch.status USING ERRCODE = '22023';
  END IF;

  -- 72-hour window check
  IF now() > (v_batch.approved_at + interval '72 hours') THEN
    RAISE EXCEPTION 'ROLLBACK_WINDOW_EXPIRED: 72-hour rollback request window has expired' USING ERRCODE = '22023';
  END IF;

  -- Strict Zero-Edit Lock Check
  v_modified := public.get_plantilla_import_first_modified_record(p_batch_id, v_batch.approved_at);
  IF v_modified IS NOT NULL THEN
    RAISE EXCEPTION 'ZERO_EDIT_LOCK: Batch records have been modified post-approval. Employee % (%) was edited on %. Rollback is hard-blocked.',
      v_modified->>'employee_no', v_modified->>'employee_name', v_modified->>'updated_at'
      USING ERRCODE = '40001';
  END IF;

  UPDATE public.plantilla_import_batches
     SET rollback_status       = 'requested',
         rollback_requested_by = v_uid,
         rollback_requested_at = now(),
         rollback_reason       = p_reason_note,
         rollback_reason_code  = p_reason_code,
         rollback_reason_note  = p_reason_note,
         updated_at            = now()
   WHERE id = p_batch_id;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'rollback_status', 'requested'
  );
END$func$;

REVOKE ALL ON FUNCTION public.request_plantilla_import_rollback(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_plantilla_import_rollback(uuid, text, text) TO authenticated;

-- 6.2 Approve Rollback (HA / SA)
CREATE OR REPLACE FUNCTION public.approve_plantilla_import_rollback(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid       uuid := auth.uid();
  v_actor     uuid := public.get_current_profile_id();
  v_user_name text;
  v_batch     public.plantilla_import_batches%ROWTYPE;
  v_modified  jsonb;
  v_res       jsonb;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;

  -- Strict Zero-Edit Lock Check
  v_modified := public.get_plantilla_import_first_modified_record(p_batch_id, v_batch.approved_at);
  IF v_modified IS NOT NULL THEN
    RAISE EXCEPTION 'ZERO_EDIT_LOCK: Batch records have been modified post-approval. Employee % (%) was edited on %. Rollback is hard-blocked.',
      v_modified->>'employee_no', v_modified->>'employee_name', v_modified->>'updated_at'
      USING ERRCODE = '40001';
  END IF;

  -- Execute rollback
  v_res := public.rollback_plantilla_import_batch(p_batch_id, COALESCE(v_batch.rollback_reason_note, 'Approved by admin'));

  UPDATE public.plantilla_import_batches
     SET rollback_status      = 'completed',
         rollback_approved_by = v_uid,
         rollback_approved_at = now(),
         approved_by_name     = v_user_name,
         updated_at           = now()
   WHERE id = p_batch_id;

  RETURN v_res;
END$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_rollback(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_rollback(uuid) TO authenticated;

-- 6.3 Reject Rollback (HA / SA)
CREATE OR REPLACE FUNCTION public.reject_plantilla_import_rollback(
  p_batch_id uuid,
  p_reason   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid       uuid := auth.uid();
  v_actor     uuid := public.get_current_profile_id();
  v_user_name text;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required' USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;

  UPDATE public.plantilla_import_batches
     SET rollback_status        = 'rejected',
         rollback_rejected_by   = v_actor,
         rollback_rejected_at   = now(),
         rejected_by_name       = v_user_name,
         rollback_error_detail  = p_reason,
         updated_at             = now()
   WHERE id = p_batch_id;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'rollback_status', 'rejected'
  );
END$func$;

REVOKE ALL ON FUNCTION public.reject_plantilla_import_rollback(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_plantilla_import_rollback(uuid, text) TO authenticated;

-- 6.4 Super Admin Override Rollback (>72h Expired Window Override)
CREATE OR REPLACE FUNCTION public.override_plantilla_import_rollback(
  p_batch_id uuid,
  p_reason   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  RETURN public.emergency_rollback_plantilla_import(p_batch_id, p_reason);
END$func$;

REVOKE ALL ON FUNCTION public.override_plantilla_import_rollback(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.override_plantilla_import_rollback(uuid, text) TO authenticated;

-- 7. Downstream VCODE Existence Guard for Vacancy Import (Invariant 1)
CREATE OR REPLACE FUNCTION public.fn_assert_vcode_exists_in_plantilla(p_vcode text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.stores s WHERE upper(s.vcode) = upper(trim(p_vcode))
  ) OR EXISTS (
    SELECT 1 FROM public.plantilla_slots ps WHERE upper(ps.legacy_vcode) = upper(trim(p_vcode))
  );
$$;

REVOKE ALL ON FUNCTION public.fn_assert_vcode_exists_in_plantilla(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_assert_vcode_exists_in_plantilla(text) TO authenticated;
