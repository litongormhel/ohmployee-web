-- =====================================================================
-- OHM2026_0041 — Wire Governance Control Enforcement
-- Migration: 20260708000000_wire_governance_control_enforcement.sql
-- Depends on: 20260707000000_governance_controls_foundation.sql
--             20260522200000_account_request_identity_v1_1.sql
--             20260706000000_patch_import_optional_employee_fields.sql
--             20260603010000_plantilla_import_dry_run_v1.sql
-- =====================================================================
-- Purpose
--   Wires fn_check_governance_control into the backend RPCs that execute
--   account registration and Plantilla imports. When a control is disabled,
--   the gated RPC raises an immediately user-facing error:
--     "This feature is currently disabled by System Administration."
--
--   Gates applied:
--     account_registration → fn_enrich_account_request
--     import_plantilla     → submit_plantilla_baseline_import
--                            submit_employee_import_v1
--                            submit_store_import_rbac
--
--   Flutter client reads are supplemental only. Backend is authoritative.
--
-- Sections
--   §1  fn_assert_governance_enabled — shared raise helper
--   §2  fn_enrich_account_request — account_registration gate
--   §3  submit_plantilla_baseline_import — import_plantilla gate
--   §4  submit_employee_import_v1 — import_plantilla gate
--   §5  submit_store_import_rbac — import_plantilla gate
--
-- What is NOT changed
--   - governance_controls / governance_audit_log schema and RLS
--   - fn_get_governance_controls / fn_update_governance_control / fn_check_governance_control
--   - All approve/reject/rollback RPCs (approval path is not gated)
--   - CENCOM, HR Emploc, Vacancy, Deactivation, MIKA modules
--   - RBAC, role levels, user_scopes
--
-- Replay safety
--   All functions use CREATE OR REPLACE. Idempotent.
--   No table or column DDL. No RLS changes.
-- =====================================================================


-- =====================================================================
-- §1  fn_assert_governance_enabled
-- =====================================================================
-- Called inside each gated RPC. Raises with the canonical user-facing
-- error if the control is disabled. SECURITY DEFINER so it can read
-- governance_controls regardless of caller role.

CREATE OR REPLACE FUNCTION public.fn_assert_governance_enabled(p_control_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.fn_check_governance_control(p_control_key) THEN
    RAISE EXCEPTION 'This feature is currently disabled by System Administration.'
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_assert_governance_enabled(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_assert_governance_enabled(text) TO authenticated;

COMMENT ON FUNCTION public.fn_assert_governance_enabled IS
  'OHM2026_0041: Raises P0001 with canonical user-facing message when the named '
  'governance control is disabled. Called at the top of each gated RPC.';


-- =====================================================================
-- §2  fn_enrich_account_request — account_registration gate
-- =====================================================================
-- Carries forward OHM2026_2010 (20260522200000) with governance gate
-- added immediately after the authentication guard.

CREATE OR REPLACE FUNCTION public.fn_enrich_account_request(
  p_last_name       TEXT,
  p_first_name      TEXT,
  p_middle_name     TEXT     DEFAULT NULL,
  p_mobile_number   TEXT     DEFAULT NULL,
  p_requested_role_id UUID   DEFAULT NULL,
  p_group_ids       UUID[]   DEFAULT ARRAY[]::UUID[],
  p_account_ids     UUID[]   DEFAULT ARRAY[]::UUID[]
)
  RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_request        public.account_requests%ROWTYPE;
  v_mobile_norm    TEXT;
  v_role_name      TEXT;
  v_role_upper     TEXT;
  v_gid            UUID;
  v_aid            UUID;
  v_dup_count      INT;
BEGIN
  -- ── 1. Caller must be authenticated ──────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  -- ── 2. Governance gate ───────────────────────────────────────────────────
  PERFORM public.fn_assert_governance_enabled('account_registration');

  -- ── 3. Load and lock own pending request ─────────────────────────────────
  SELECT * INTO v_request
  FROM public.account_requests
  WHERE auth_user_id = auth.uid()
    AND status = 'pending'::public.account_request_status
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no pending account request found for caller'
      USING ERRCODE = 'P0002';
  END IF;

  -- ── 4. Validate required name fields ─────────────────────────────────────
  IF NULLIF(TRIM(p_last_name),  '') IS NULL THEN
    RAISE EXCEPTION 'last_name is required' USING ERRCODE = '23502';
  END IF;
  IF NULLIF(TRIM(p_first_name), '') IS NULL THEN
    RAISE EXCEPTION 'first_name is required' USING ERRCODE = '23502';
  END IF;

  -- ── 5. Mobile normalization & duplicate check ─────────────────────────────
  IF p_mobile_number IS NOT NULL AND TRIM(p_mobile_number) <> '' THEN
    v_mobile_norm := public.fn_normalize_ph_mobile(p_mobile_number);

    SELECT COUNT(*) INTO v_dup_count
    FROM public.account_requests
    WHERE mobile_number = v_mobile_norm
      AND id <> v_request.id
      AND status <> 'rejected'::public.account_request_status;

    IF v_dup_count > 0 THEN
      RAISE EXCEPTION 'mobile_number_already_registered: % is already in use', v_mobile_norm
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- ── 6. Role validation ────────────────────────────────────────────────────
  IF p_requested_role_id IS NOT NULL THEN
    SELECT UPPER(role_name) INTO v_role_name
    FROM public.roles
    WHERE id = p_requested_role_id;

    IF v_role_name IS NULL THEN
      RAISE EXCEPTION 'requested role not found: %', p_requested_role_id
        USING ERRCODE = 'P0002';
    END IF;

    v_role_upper := v_role_name;

    IF v_role_upper IN ('SUPER ADMIN', 'SUPERADMIN', 'HEAD ADMIN', 'HEADADMIN') THEN
      RAISE EXCEPTION 'super_admin and head_admin roles cannot be self-requested'
        USING ERRCODE = '42501';
    END IF;

    IF v_role_upper IN ('OM', 'ENCODER') THEN
      IF COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0) > 0 THEN
        RAISE EXCEPTION 'role_scope_violation: % may only request group scope (no accounts)', v_role_upper
          USING ERRCODE = '22023';
      END IF;
    END IF;

    IF COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0) > 0
      AND COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0) = 0 THEN
      RAISE EXCEPTION 'account scope requires at least one group'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── 7. Update account_requests with identity fields ───────────────────────
  UPDATE public.account_requests
  SET
    last_name          = TRIM(p_last_name),
    first_name         = TRIM(p_first_name),
    middle_name        = public.fn_coalesce_middle_name(p_middle_name),
    mobile_number      = v_mobile_norm,
    full_name          = TRIM(CONCAT_WS(' ',
                           TRIM(p_first_name),
                           public.fn_coalesce_middle_name(p_middle_name),
                           TRIM(p_last_name)
                         )),
    requested_role_id  = COALESCE(p_requested_role_id, requested_role_id),
    updated_at         = NOW()
  WHERE id = v_request.id;

  -- ── 8. Scope rows: replace requested scope ────────────────────────────────
  DELETE FROM public.account_request_group_scopes
  WHERE account_request_id = v_request.id;

  DELETE FROM public.account_request_account_scopes
  WHERE account_request_id = v_request.id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    INSERT INTO public.account_request_group_scopes (account_request_id, group_id)
    VALUES (v_request.id, v_gid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  FOREACH v_aid IN ARRAY p_account_ids LOOP
    INSERT INTO public.account_request_account_scopes (account_request_id, account_id)
    VALUES (v_request.id, v_aid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- ── 9. Return summary ─────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',        TRUE,
    'request_id',     v_request.id,
    'last_name',      TRIM(p_last_name),
    'first_name',     TRIM(p_first_name),
    'mobile_number',  v_mobile_norm,
    'role_id',        p_requested_role_id,
    'group_count',    COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0),
    'account_count',  COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_enrich_account_request(TEXT, TEXT, TEXT, TEXT, UUID, UUID[], UUID[])
  TO authenticated;

COMMENT ON FUNCTION public.fn_enrich_account_request IS
  'OHM2026_0041: Adds account_registration governance gate (§2). '
  'Carries forward OHM2026_2010 identity enrichment. '
  'Raises P0001 if account_registration is disabled; raises 42501 if unauthenticated.';


-- =====================================================================
-- §3  submit_plantilla_baseline_import — import_plantilla gate
-- =====================================================================
-- Carries forward OHM2026_0080 (20260706000000) with governance gate
-- added immediately after the RBAC auth guard.

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

  -- Optional enrichment fields
  v_civil_status    text;
  v_rate_raw        text;
  v_birthdate_raw   text;
  v_contact_raw     text;
  v_address_raw     text;
  v_schedule_raw    text;
  v_dayoff_raw      text;
  v_coordinator_raw text;

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
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Governance gate ───────────────────────────────────────────────────────
  PERFORM public.fn_assert_governance_enabled('import_plantilla');

  -- ── Input validation ─────────────────────────────────────────────────────
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

  -- ── Scope validation ─────────────────────────────────────────────────────
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

  -- ── Create batch ─────────────────────────────────────────────────────────
  INSERT INTO public.plantilla_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- ── Pre-passes ───────────────────────────────────────────────────────────

  -- [A] Duplicate VCODEs within this upload (all occurrences will be blocked)
  DROP TABLE IF EXISTS _pib_dup_vcodes;
  CREATE TEMP TABLE _pib_dup_vcodes ON COMMIT DROP AS
  SELECT upper(trim(elem->>'VCODE')) AS vcode
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1 HAVING count(*) > 1;

  -- [B] Employee → store coverage (roving detection)
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

  -- [D] VCODEs actively assigned in the live system: vcode → employee_no
  DROP TABLE IF EXISTS _pib_active_vcode_owners;
  CREATE TEMP TABLE _pib_active_vcode_owners ON COMMIT DROP AS
  SELECT upper(trim(a.vcode)) AS vcode,
         upper(trim(a.employee_no)) AS employee_no
    FROM public.employee_store_allocations a
   WHERE a.is_active
     AND a.vcode IS NOT NULL
     AND a.employee_no IS NOT NULL;

  -- ── Row loop ─────────────────────────────────────────────────────────────
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

    -- Parse optional enrichment fields (safe: null if blank or absent)
    v_civil_status    := nullif(trim(coalesce(v_row->>'CIVIL_STATUS', '')), '');
    v_rate_raw        := nullif(trim(coalesce(v_row->>'RATE', '')), '');
    v_birthdate_raw   := nullif(trim(coalesce(v_row->>'BIRTHDATE', '')), '');
    v_contact_raw     := nullif(trim(coalesce(v_row->>'CONTACT', '')), '');
    v_address_raw     := nullif(trim(coalesce(v_row->>'ADDRESS', '')), '');
    v_schedule_raw    := nullif(trim(coalesce(v_row->>'SCHEDULE', '')), '');
    v_dayoff_raw      := nullif(trim(coalesce(v_row->>'DAYOFF', '')), '');
    v_coordinator_raw := nullif(trim(coalesce(v_row->>'COORDINATOR', '')), '');

    -- ── Blocking: required fields ─────────────────────────────────────────
    IF v_vcode    IS NULL THEN v_errs := v_errs || '[{"field":"VCODE","msg":"required"}]'::jsonb; END IF;
    IF v_store_nm IS NULL THEN v_errs := v_errs || '[{"field":"STORE_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_prov     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_PROVINCE","msg":"required"}]'::jsonb; END IF;
    IF v_city     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_CITY","msg":"required"}]'::jsonb; END IF;
    IF v_emp      IS NULL THEN v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"required"}]'::jsonb; END IF;
    IF v_last     IS NULL THEN v_errs := v_errs || '[{"field":"LAST_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_first    IS NULL THEN v_errs := v_errs || '[{"field":"FIRST_NAME","msg":"required"}]'::jsonb; END IF;

    IF v_vcode IS NOT NULL AND v_store_nm IS NOT NULL AND v_emp IS NULL THEN
      v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"store row has no employee — every VCODE must have an assigned employee"}]'::jsonb;
    END IF;

    IF v_vcode IS NOT NULL AND EXISTS (SELECT 1 FROM _pib_dup_vcodes WHERE vcode = v_vcode) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"duplicate VCODE in upload — each VCODE must appear exactly once"}]'::jsonb;
    END IF;

    IF v_vcode IS NOT NULL AND v_emp IS NOT NULL AND EXISTS (
      SELECT 1 FROM _pib_active_vcode_owners
      WHERE vcode = v_vcode AND employee_no <> v_emp
    ) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE already actively assigned to a different employee"}]'::jsonb;
    END IF;

    IF v_req_hc IS NULL THEN
      v_flags := v_flags || '[{"flag":"missing_required_hc","msg":"REQUIRED_HC not provided"}]'::jsonb;
    END IF;

    IF v_emp IS NOT NULL AND v_vcode IS NOT NULL
       AND EXISTS (SELECT 1 FROM _pib_seen_pairs WHERE emp = v_emp AND vcode = v_vcode)
    THEN
      v_status := 'skipped';
      v_flags  := v_flags || '[{"flag":"duplicate_emp_vcode","msg":"same employee+VCODE already processed — skipped"}]'::jsonb;
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

      IF v_emp IS NOT NULL THEN
        SELECT id INTO v_existing_pid
          FROM public.plantilla
         WHERE employee_no = v_emp
           AND is_deleted = false
           AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
         LIMIT 1;
        v_is_existing_emp := (v_existing_pid IS NOT NULL);
        IF v_is_existing_emp THEN
          v_flags := v_flags || '[{"flag":"existing_employee","msg":"employee_no already in active plantilla — will upsert on commit"}]'::jsonb;
          v_ex_emps := v_ex_emps + 1;
        END IF;
      END IF;

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
      civil_status, rate_raw, birthdate_raw, contact_raw,
      address_raw, schedule_raw, dayoff_raw, coordinator_raw,
      resolved_store_id, resolved_account_id, resolved_group_id,
      validation_status, validation_errors, validation_flags,
      is_roving, roving_store_count, is_new_store, is_existing_employee
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_vcode, v_store_nm, v_prov, v_city, v_position, v_emp_type,
        v_req_hc, v_pen_raw,
      v_emp, v_last, v_first, v_middle,
      v_civil_status, v_rate_raw, v_birthdate_raw, v_contact_raw,
      v_address_raw, v_schedule_raw, v_dayoff_raw, v_coordinator_raw,
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

  -- ── Post-loop: HC mismatch sweep ─────────────────────────────────────────
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

  -- ── Post-loop: roving dedup ───────────────────────────────────────────────
  SELECT count(*) INTO v_roving
    FROM _pib_emp_cov WHERE store_count > 1;

  SELECT count(DISTINCT employee_no) INTO v_ex_emps
    FROM public.plantilla_import_rows r
   WHERE r.batch_id = v_batch_id
     AND r.validation_status IN ('valid','flagged')
     AND r.is_existing_employee;

  -- ── Post-loop: missing from upload ───────────────────────────────────────
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

  -- ── Aggregate error summary ───────────────────────────────────────────────
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
END$func$;

REVOKE ALL ON FUNCTION public.submit_plantilla_baseline_import(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_plantilla_baseline_import(text,uuid,uuid,jsonb) TO authenticated;

COMMENT ON FUNCTION public.submit_plantilla_baseline_import IS
  'OHM2026_0041: Adds import_plantilla governance gate (§3). '
  'Carries forward OHM2026_0080 optional enrichment fields. '
  'Raises P0001 if import_plantilla is disabled before any batch is created.';


-- =====================================================================
-- §4  submit_employee_import_v1 — import_plantilla gate
-- =====================================================================
-- Carries forward OHM2026_0050 (20260603010000) with governance gate
-- added immediately after the RBAC auth guard.

CREATE OR REPLACE FUNCTION public.submit_employee_import_v1(
  p_file_name  text,
  p_group_id   uuid,
  p_account_id uuid,
  p_rows       jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_role       text := public.get_my_role();
  v_batch_id   uuid;
  v_acct_group uuid;

  v_row        jsonb;
  v_idx        int := 0;
  v_emp        text;
  v_last       text;
  v_first      text;
  v_middle     text;
  v_vcode      text;

  v_store_id   uuid;
  v_store_name text;
  v_store_acct uuid;
  v_store_grp  uuid;
  v_position   text;

  v_errs       jsonb;
  v_flags      jsonb;
  v_status     text;
  v_is_roving  boolean;
  v_store_cnt  int;

  v_total      int := 0;
  v_valid      int := 0;
  v_flagged    int := 0;
  v_skipped    int := 0;
  v_blocked    int := 0;
  v_roving     int := 0;
  v_xacct      int := 0;
  v_xgroup     int := 0;
  v_over20     int := 0;
  v_summary    jsonb;
  v_final      text;
BEGIN
  -- ── Auth: uploader gate ──────────────────────────────────────────────────
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Governance gate ───────────────────────────────────────────────────────
  PERFORM public.fn_assert_governance_enabled('import_plantilla');

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

  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'INVALID_GROUP: %', p_group_id USING ERRCODE = '23503';
  END IF;
  SELECT group_id INTO v_acct_group FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: %', p_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %', p_account_id, p_group_id
      USING ERRCODE = '23503';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account is outside caller scope' USING ERRCODE = '42501';
  END IF;

  -- ── Create batch ─────────────────────────────────────────────────────────
  INSERT INTO public.employee_import_batches (
    file_name, uploaded_by, uploaded_role, selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  DROP TABLE IF EXISTS _emp_cov;
  DROP TABLE IF EXISTS _seen_pairs;
  CREATE TEMP TABLE _emp_cov ON COMMIT DROP AS
  SELECT
    upper(trim(elem->>'EMPLOYEE_NO'))                 AS emp,
    count(DISTINCT upper(trim(elem->>'VCODE')))       AS store_count
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'EMPLOYEE_NO'),'') IS NOT NULL
    AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1;

  CREATE TEMP TABLE _seen_pairs (emp text, vcode text) ON COMMIT DROP;

  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx   := v_idx + 1;
    v_total := v_total + 1;
    v_errs  := '[]'::jsonb;
    v_flags := '[]'::jsonb;
    v_is_roving := false;
    v_store_cnt := 0;
    v_store_id := NULL; v_store_name := NULL; v_store_acct := NULL; v_store_grp := NULL; v_position := NULL;

    v_emp    := upper(NULLIF(trim(COALESCE(v_row->>'EMPLOYEE_NO','')), ''));
    v_last   := NULLIF(trim(COALESCE(v_row->>'LAST_NAME','')), '');
    v_first  := NULLIF(trim(COALESCE(v_row->>'FIRST_NAME','')), '');
    v_middle := NULLIF(trim(COALESCE(v_row->>'MIDDLE_NAME','')), '');
    v_vcode  := upper(NULLIF(trim(COALESCE(v_row->>'VCODE','')), ''));

    IF v_emp   IS NULL THEN v_errs := v_errs || jsonb_build_object('field','EMPLOYEE_NO','msg','required'); END IF;
    IF v_last  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','LAST_NAME','msg','required'); END IF;
    IF v_first IS NULL THEN v_errs := v_errs || jsonb_build_object('field','FIRST_NAME','msg','required'); END IF;
    IF v_vcode IS NULL THEN v_errs := v_errs || jsonb_build_object('field','VCODE','msg','required'); END IF;

    IF v_vcode IS NOT NULL THEN
      SELECT s.id, s.store_name, s.account_id, s.group_id
        INTO v_store_id, v_store_name, v_store_acct, v_store_grp
        FROM public.stores s
       WHERE upper(s.vcode) = v_vcode AND s.status = 'active'
       ORDER BY s.created_at
       LIMIT 1;

      IF v_store_id IS NULL THEN
        v_errs := v_errs || jsonb_build_object('field','VCODE','msg','no active store found for vcode');
      ELSE
        SELECT v.position INTO v_position
          FROM public.vacancies v
         WHERE upper(v.vcode) = v_vcode AND NOT COALESCE(v.is_archived,false)
         ORDER BY v.created_at LIMIT 1;
      END IF;
    END IF;

    IF v_emp IS NOT NULL THEN
      SELECT store_count INTO v_store_cnt FROM _emp_cov WHERE emp = v_emp;
      v_store_cnt := COALESCE(v_store_cnt, 0);
      IF v_store_cnt > 1 THEN
        v_is_roving := true;
      END IF;
      IF v_store_cnt > 20 THEN
        v_flags := v_flags || jsonb_build_object('flag','over_20_stores','msg', v_store_cnt || ' stores (>20 allowed but flagged)');
      END IF;
    END IF;

    IF v_emp IS NOT NULL AND v_vcode IS NOT NULL
       AND EXISTS (SELECT 1 FROM _seen_pairs sp WHERE sp.emp = v_emp AND sp.vcode = v_vcode) THEN
      v_status := 'skipped';
      v_flags := v_flags || jsonb_build_object('flag','duplicate_emp_vcode','msg','duplicate employee+vcode within CSV — skipped');
    ELSE
      IF v_emp IS NOT NULL AND v_store_id IS NOT NULL THEN
        IF v_store_grp IS NOT NULL AND v_store_grp <> p_group_id THEN
          v_errs := v_errs || jsonb_build_object('field','VCODE','msg','cross-group: store group differs from batch group');
        END IF;

        IF (
          SELECT count(DISTINCT s2.account_id)
          FROM jsonb_array_elements(p_rows) AS e2(value)
          JOIN public.stores s2 ON upper(s2.vcode) = upper(trim(e2.value->>'VCODE')) AND s2.status='active'
          WHERE upper(trim(e2.value->>'EMPLOYEE_NO')) = v_emp
        ) > 1 THEN
          v_errs := v_errs || jsonb_build_object('field','EMPLOYEE_NO','msg','cross-account: same employee across multiple accounts — blocked');
          v_flags := v_flags || jsonb_build_object('flag','cross_account','msg','review by Encoder / Head Admin');
        END IF;

        IF EXISTS (
          SELECT 1 FROM public.employee_store_allocations a
          WHERE a.employee_no = v_emp AND a.is_active
            AND a.account_id IS NOT NULL AND a.account_id <> v_store_acct
        ) THEN
          v_errs := v_errs || jsonb_build_object('field','EMPLOYEE_NO','msg','cross-account: employee already deployed in another account');
          v_flags := v_flags || jsonb_build_object('flag','cross_account','msg','review by Encoder / Head Admin');
        END IF;
      END IF;

      IF jsonb_array_length(v_errs) > 0 THEN
        v_status := 'blocked';
      ELSIF jsonb_array_length(v_flags) > 0 THEN
        v_status := 'flagged';
      ELSE
        v_status := 'valid';
      END IF;

      IF v_emp IS NOT NULL AND v_vcode IS NOT NULL THEN
        INSERT INTO _seen_pairs(emp, vcode) VALUES (v_emp, v_vcode);
      END IF;
    END IF;

    INSERT INTO public.employee_import_rows (
      batch_id, row_number, raw_data,
      employee_no, last_name, first_name, middle_name, vcode,
      resolved_store_id, resolved_store_name, resolved_account_id, resolved_group_id, resolved_position,
      validation_status, validation_errors, validation_flags, is_roving, roving_store_count
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_emp, v_last, v_first, v_middle, v_vcode,
      v_store_id, v_store_name, v_store_acct, v_store_grp, v_position,
      v_status, v_errs, v_flags, v_is_roving, v_store_cnt
    );

    CASE v_status
      WHEN 'valid'   THEN v_valid := v_valid + 1;
      WHEN 'flagged' THEN v_flagged := v_flagged + 1;
      WHEN 'skipped' THEN v_skipped := v_skipped + 1;
      WHEN 'blocked' THEN v_blocked := v_blocked + 1;
      ELSE NULL;
    END CASE;

    IF v_flags @> '[{"flag":"over_20_stores"}]'::jsonb THEN v_over20 := v_over20 + 1; END IF;
    IF v_status <> 'skipped' AND v_flags @> '[{"flag":"cross_account"}]'::jsonb THEN
      v_xacct := v_xacct + 1;
    END IF;
    IF v_status = 'blocked'
       AND v_errs @> '[{"msg":"cross-group: store group differs from batch group"}]'::jsonb THEN
      v_xgroup := v_xgroup + 1;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_roving FROM _emp_cov WHERE store_count > 1;

  SELECT COALESCE(jsonb_object_agg(field_name, cnt), '{}'::jsonb) INTO v_summary
  FROM (
    SELECT (e.value->>'field') AS field_name, count(*) AS cnt
    FROM public.employee_import_rows r
    CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
    WHERE r.batch_id = v_batch_id
    GROUP BY 1
  ) s;

  v_final := CASE
    WHEN (v_valid + v_flagged) = 0 THEN 'validation_failed'
    ELSE 'pending_approval'
  END;

  UPDATE public.employee_import_batches
     SET total_rows              = v_total,
         valid_rows              = v_valid,
         flagged_rows            = v_flagged,
         skipped_duplicate_rows  = v_skipped,
         blocked_rows            = v_blocked,
         roving_detected         = v_roving,
         cross_account_conflicts = v_xacct,
         cross_group_conflicts   = v_xgroup,
         over_20_store_warnings  = v_over20,
         error_summary           = v_summary,
         status                  = v_final,
         updated_at              = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id', v_batch_id,
    'status', v_final,
    'total_rows', v_total,
    'valid_rows', v_valid,
    'flagged_rows', v_flagged,
    'skipped_duplicate_rows', v_skipped,
    'blocked_rows', v_blocked,
    'roving_detected', v_roving,
    'cross_account_conflicts', v_xacct,
    'cross_group_conflicts', v_xgroup,
    'over_20_store_warnings', v_over20,
    'error_summary', v_summary
  );
END$function$;

REVOKE ALL ON FUNCTION public.submit_employee_import_v1(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_employee_import_v1(text,uuid,uuid,jsonb) TO authenticated;

COMMENT ON FUNCTION public.submit_employee_import_v1 IS
  'OHM2026_0041: Adds import_plantilla governance gate (§4). '
  'Carries forward OHM2026_0050 employee import validation. '
  'Raises P0001 if import_plantilla is disabled before any batch is created.';


-- =====================================================================
-- §5  submit_store_import_rbac — import_plantilla gate
-- =====================================================================
-- Carries forward OHM2026_0050 (20260603010000 §14) with governance
-- gate added immediately after the RBAC auth guard.

CREATE OR REPLACE FUNCTION public.submit_store_import_rbac(
  p_file_name text, p_group_id uuid, p_account_id uuid, p_rows jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_role  text := public.get_my_role();
  v_bid   uuid;
  v_acct_group uuid;
  v_row   jsonb; v_idx int := 0;
  v_vcode text; v_name text; v_prov text; v_city text; v_type text; v_type_raw text;
  v_pen boolean; v_pen_raw text; v_errs jsonb;
  v_dup jsonb; v_total int := 0; v_valid int := 0; v_invalid int := 0;
  v_summary jsonb; v_final text;
BEGIN
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE='42501';
  END IF;

  -- ── Governance gate ───────────────────────────────────────────────────────
  PERFORM public.fn_assert_governance_enabled('import_plantilla');

  IF p_file_name IS NULL OR length(trim(p_file_name))=0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: file_name required' USING ERRCODE='22023'; END IF;
  IF jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows)=0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows must be a non-empty array' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN
    RAISE EXCEPTION 'INVALID_INPUT: max 5000 rows per batch' USING ERRCODE='22023'; END IF;

  SELECT group_id INTO v_acct_group FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL OR v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % not in group %', p_account_id, p_group_id USING ERRCODE='23503'; END IF;
  IF NOT public.i_have_full_access() AND NOT (p_account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account outside caller scope' USING ERRCODE='42501'; END IF;

  INSERT INTO public.store_import_batches (
    file_name, uploaded_by, uploaded_role, selected_group_id, selected_account_id, status
  ) VALUES (p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded')
  RETURNING id INTO v_bid;

  v_dup := (
    SELECT COALESCE(jsonb_agg(d.v), '[]'::jsonb) FROM (
      SELECT lower(trim(elem->>'VCODE')) AS v
      FROM jsonb_array_elements(p_rows) elem
      WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
      GROUP BY 1 HAVING count(*) > 1
    ) d
  );

  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value) LOOP
    v_idx := v_idx + 1; v_total := v_total + 1; v_errs := '[]'::jsonb;
    v_vcode := NULLIF(trim(COALESCE(v_row->>'VCODE','')),'');
    v_name  := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')),'');
    v_prov  := NULLIF(trim(COALESCE(v_row->>'AREA_PROVINCE','')),'');
    v_city  := NULLIF(trim(COALESCE(v_row->>'AREA_CITY','')),'');
    v_type_raw := lower(NULLIF(trim(COALESCE(v_row->>'EMPLOYMENT_TYPE', v_row->>'TYPE','')),''));
    v_pen_raw  := lower(NULLIF(trim(COALESCE(v_row->>'WITH_PENALTY','')),''));

    IF v_vcode IS NULL THEN v_errs := v_errs || jsonb_build_object('field','VCODE','msg','required'); END IF;
    IF v_name  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','STORE_NAME','msg','required'); END IF;
    IF v_prov  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','AREA_PROVINCE','msg','required'); END IF;
    IF v_city  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','AREA_CITY','msg','required'); END IF;

    IF v_type_raw IS NULL THEN v_type := NULL;
    ELSIF v_type_raw IN ('stationary','roving') THEN v_type := v_type_raw;
    ELSE v_errs := v_errs || jsonb_build_object('field','EMPLOYMENT_TYPE','msg','must be stationary or roving'); v_type := NULL; END IF;

    IF v_pen_raw IS NULL THEN v_pen := NULL;
    ELSIF v_pen_raw IN ('yes','y','true','1') THEN v_pen := true;
    ELSIF v_pen_raw IN ('no','n','false','0') THEN v_pen := false;
    ELSE v_errs := v_errs || jsonb_build_object('field','WITH_PENALTY','msg','must be yes or no'); v_pen := NULL; END IF;

    IF v_vcode IS NOT NULL AND v_dup ? lower(v_vcode) THEN
      v_errs := v_errs || jsonb_build_object('field','VCODE','msg','duplicate within CSV'); END IF;
    IF v_vcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.stores WHERE lower(vcode)=lower(v_vcode) AND status='active') THEN
      v_errs := v_errs || jsonb_build_object('field','VCODE','msg','already exists in active stores'); END IF;

    INSERT INTO public.store_import_rows (
      batch_id,row_number,raw_data,vcode,store_name,area_province,area_city,type,with_penalty,validation_status,validation_errors
    ) VALUES (
      v_bid, v_idx, v_row, v_vcode, v_name, v_prov, v_city, v_type, v_pen,
      CASE WHEN jsonb_array_length(v_errs)=0 THEN 'valid' ELSE 'invalid' END, v_errs
    );
    IF jsonb_array_length(v_errs)=0 THEN v_valid := v_valid+1; ELSE v_invalid := v_invalid+1; END IF;
  END LOOP;

  SELECT COALESCE(jsonb_object_agg(field_name,cnt),'{}'::jsonb) INTO v_summary FROM (
    SELECT (e.value->>'field') AS field_name, count(*) AS cnt
    FROM public.store_import_rows r CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
    WHERE r.batch_id=v_bid GROUP BY 1
  ) s;

  v_final := CASE WHEN v_total=0 OR v_invalid>0 THEN 'validation_failed' ELSE 'pending_approval' END;
  UPDATE public.store_import_batches
     SET total_rows=v_total, valid_rows=v_valid, invalid_rows=v_invalid,
         error_summary=v_summary, status=v_final, updated_at=now()
   WHERE id=v_bid;

  RETURN jsonb_build_object('batch_id',v_bid,'status',v_final,'total_rows',v_total,
    'valid_rows',v_valid,'invalid_rows',v_invalid,'error_summary',v_summary);
END$function$;

REVOKE ALL ON FUNCTION public.submit_store_import_rbac(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_store_import_rbac(text,uuid,uuid,jsonb) TO authenticated;

COMMENT ON FUNCTION public.submit_store_import_rbac IS
  'OHM2026_0041: Adds import_plantilla governance gate (§5). '
  'Carries forward OHM2026_0050 store master import. '
  'Raises P0001 if import_plantilla is disabled before any batch is created.';


-- =====================================================================
-- Validation SQL (read-only — run manually after applying)
-- =====================================================================
--
-- V1: Helper function exists and is SECURITY DEFINER
--   SELECT proname, prosecdef
--   FROM pg_proc
--   WHERE proname = 'fn_assert_governance_enabled'
--     AND pronamespace = 'public'::regnamespace;
--   → must return 1 row with prosecdef = true
--
-- V2: All four gated functions reference fn_assert_governance_enabled
--   SELECT proname
--   FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND prosrc LIKE '%fn_assert_governance_enabled%'
--   ORDER BY proname;
--   → must return: fn_enrich_account_request, submit_employee_import_v1,
--                  submit_plantilla_baseline_import, submit_store_import_rbac
--
-- V3: Governance check raises correct error when disabled
--   UPDATE governance_controls SET enabled = false
--    WHERE control_key = 'import_plantilla';
--   Then call submit_plantilla_baseline_import (or any other import RPC):
--   → must raise P0001 with message:
--     'This feature is currently disabled by System Administration.'
--   Restore: UPDATE governance_controls SET enabled = true
--             WHERE control_key = 'import_plantilla';
--
-- V4: account_registration gate
--   UPDATE governance_controls SET enabled = false
--    WHERE control_key = 'account_registration';
--   Then call fn_enrich_account_request as an authenticated user:
--   → must raise P0001 with the standard governance message.
--   Restore: UPDATE governance_controls SET enabled = true
--             WHERE control_key = 'account_registration';
--
-- V5: Governance check passes when control is enabled (normal flow)
--   Ensure both controls are enabled:
--     SELECT control_key, enabled FROM governance_controls
--      WHERE control_key IN ('account_registration','import_plantilla');
--   → both must show enabled = true
--   Normal import/registration calls proceed without governance error.
--
-- V6: RBAC check still fires before governance check would matter
--   Call submit_plantilla_baseline_import as an unauthorized role (e.g. viewer):
--   → must raise 42501 (RBAC forbidden), NOT the governance error.
--   The governance check is secondary to auth — RBAC gates remain first.
--
-- V7: fn_check_governance_control defaults to true for unknown keys
--   SELECT public.fn_check_governance_control('nonexistent_key');
--   → must return true (safe fallback — no false denials on missing keys)
-- =====================================================================
