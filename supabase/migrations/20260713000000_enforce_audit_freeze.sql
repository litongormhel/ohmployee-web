-- ─────────────────────────────────────────────────────────────────────────────
-- OHM's Safespace: Audit Freeze Gated Enforcement (Phase 2A)
-- Migration: 20260713000000_enforce_audit_freeze.sql
-- Enforces audit freeze on CSV import submissions, import rollback actions,
-- and administrative data deletions.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- ── 1. Define updated fn_assert_freeze_inactive ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_freeze_inactive(p_freeze_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.fn_check_freeze_active(p_freeze_key) THEN
    IF public.fn_check_freeze_active('read_only_emergency') THEN
      RAISE EXCEPTION 'System is in Read-Only Emergency Mode. Operations are temporarily suspended.'
        USING ERRCODE = 'P0001';
    ELSIF p_freeze_key = 'recruitment_freeze' THEN
      RAISE EXCEPTION 'Recruitment operations are temporarily frozen by System Administration.'
        USING ERRCODE = 'P0001';
    ELSIF p_freeze_key = 'audit_freeze' THEN
      RAISE EXCEPTION 'Audit-sensitive operations are temporarily frozen by System Administration.'
        USING ERRCODE = 'P0001';
    ELSE
      RAISE EXCEPTION 'This operation is suspended due to an active %.', replace(p_freeze_key, '_', ' ')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_assert_freeze_inactive(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_assert_freeze_inactive(text) TO authenticated;

-- ── 2. Gate submit_plantilla_baseline_import ──────────────────────────────────
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

  -- ── Audit Freeze Gate (Phase 2A) ─────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

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

-- ── 3. Gate submit_employee_import_v1 ─────────────────────────────────────────
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

  -- ── Audit Freeze Gate (Phase 2A) ─────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

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

-- ── 4. Gate submit_store_import_rbac ──────────────────────────────────────────
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

  -- ── Audit Freeze Gate (Phase 2A) ─────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

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

-- ── 5. Gate rollback_plantilla_import_batch ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.rollback_plantilla_import_batch(
  p_batch_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid   uuid := auth.uid();
  v_actor uuid := public.get_current_profile_id();
  v_batch public.plantilla_import_batches%ROWTYPE;
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
  v_archive_reason text;
  v_caller_role text;

  v_plantilla_restored    int := 0;
  v_plantilla_archived    int := 0;
  v_stores_restored       int := 0;
  v_stores_deactivated    int := 0;
  v_allocations_restored  int := 0;
  v_allocations_deactivated int := 0;
  v_roving_groups_archived  int := 0;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Audit Freeze Gate (Phase 2A) ─────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- ── Caller role (for audit enrichment) ───────────────────────────────────
  v_caller_role := public.get_my_role();

  -- ── Advisory lock: serialise concurrent rollback/approval for this batch ──
  PERFORM pg_advisory_xact_lock(4207900, hashtext(p_batch_id::text));

  -- ── Lock + state check ───────────────────────────────────────────────────
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches
   WHERE id = p_batch_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency guard: already rolled back
  IF v_batch.status = 'rolled_back' THEN
    RAISE EXCEPTION 'Batch already processed.'
      USING ERRCODE = 'P0001';
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

  -- ── Entity rollback block ─────────────────────────────────────────────────
  BEGIN

    -- ── Batch-level superseded scope check ───────────────────────────────────
    IF EXISTS (
      SELECT 1
        FROM public.plantilla_import_batches newer
       WHERE newer.selected_group_id   = v_batch.selected_group_id
         AND newer.selected_account_id = v_batch.selected_account_id
         AND newer.status IN ('approved', 'rollback_pending')
         AND newer.approved_at > v_batch.approved_at
         AND newer.id <> p_batch_id
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: a newer approved import batch exists for this scope. Rolling back would corrupt newer batch state.'
        USING ERRCODE = '40001';
    END IF;

    -- ── Entity-level superseded checks ───────────────────────────────────────
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
          SELECT DISTINCT employee_no
            FROM public.plantilla_import_rows
           WHERE batch_id = p_batch_id
             AND validation_status IN ('valid','flagged')
             AND employee_no IS NOT NULL
        ) emp
        JOIN public.employee_store_allocations a
          ON a.employee_no = emp.employee_no
         AND a.account_id = v_batch.selected_account_id
         AND a.is_active
       WHERE a.source_import_batch_id IS DISTINCT FROM p_batch_id
    ) THEN
      RAISE EXCEPTION 'ROLLBACK_UNSAFE: active allocations have been superseded after batch %',
        p_batch_id USING ERRCODE = '40001';
    END IF;

    -- ── Batch-created allocations: deactivate only (preserve history) ─────────
    UPDATE public.employee_store_allocations a
       SET is_active = false,
           effective_end = CURRENT_DATE
     WHERE a.source_import_batch_id = p_batch_id
       AND a.is_active;
    GET DIAGNOSTICS v_allocations_deactivated = ROW_COUNT;

    -- ── Batch-updated allocations: restore prior allocation rows ──────────────
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
       SET plantilla_id         = (snap.r).plantilla_id,
           employee_no          = (snap.r).employee_no,
           roving_group_id      = (snap.r).roving_group_id,
           store_id             = (snap.r).store_id,
           vcode                = (snap.r).vcode,
           store_name           = (snap.r).store_name,
           account_id           = (snap.r).account_id,
           group_id             = (snap.r).group_id,
           filled_hc            = (snap.r).filled_hc,
           active_store_count   = (snap.r).active_store_count,
           effective_start      = (snap.r).effective_start,
           effective_end        = (snap.r).effective_end,
           is_active            = (snap.r).is_active,
           source_import_batch_id = (snap.r).source_import_batch_id,
           created_at           = (snap.r).created_at,
           created_by           = (snap.r).created_by
      FROM snap
     WHERE a.id = snap.entity_id;
    GET DIAGNOSTICS v_allocations_restored = ROW_COUNT;

    -- ── Batch-created plantilla rows: soft archive, never hard delete ─────────
    UPDATE public.plantilla p
       SET is_archived    = true,
           archived_at    = now(),
           archived_by    = v_actor,
           archive_reason = v_archive_reason,
           status         = 'Inactive',
           updated_at     = now(),
           updated_by     = v_actor
      FROM public.plantilla_import_commit_snapshots s
     WHERE s.batch_id = p_batch_id
       AND s.entity_type = 'plantilla'
       AND s.action = 'insert'
       AND s.entity_id = p.id
       AND p.source_baseline_import_batch_id = p_batch_id
       AND COALESCE(p.is_archived, false) = false;
    GET DIAGNOSTICS v_plantilla_archived = ROW_COUNT;

    -- ── Batch-updated plantilla rows: restore prior row snapshot ─────────────
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
       SET employee_name              = (snap.r).employee_name,
           employee_no                = (snap.r).employee_no,
           account                    = (snap.r).account,
           status                     = (snap.r).status,
           emploc_no                  = (snap.r).emploc_no,
           vcode                      = (snap.r).vcode,
           position                   = (snap.r).position,
           created_at                 = (snap.r).created_at,
           hr_emploc_id               = (snap.r).hr_emploc_id,
           vacancy_id                 = (snap.r).vacancy_id,
           vacancy_code_snapshot      = (snap.r).vacancy_code_snapshot,
           employee_name_snapshot     = (snap.r).employee_name_snapshot,
           account_id                 = (snap.r).account_id,
           chain_id                   = (snap.r).chain_id,
           store_id                   = (snap.r).store_id,
           province_id                = (snap.r).province_id,
           area_name_snapshot         = (snap.r).area_name_snapshot,
           hrco_user_id_snapshot      = (snap.r).hrco_user_id_snapshot,
           om_user_id_snapshot        = (snap.r).om_user_id_snapshot,
           atl_user_id_snapshot       = (snap.r).atl_user_id_snapshot,
           position_id                = (snap.r).position_id,
           rest_day                   = (snap.r).rest_day,
           resignation_date           = (snap.r).resignation_date,
           remarks                    = (snap.r).remarks,
           moved_by_user_id           = (snap.r).moved_by_user_id,
           created_by                 = (snap.r).created_by,
           updated_at                 = (snap.r).updated_at,
           updated_by                 = (snap.r).updated_by,
           store_name                 = (snap.r).store_name,
           area                       = (snap.r).area,
           rate                       = (snap.r).rate,
           schedule                   = (snap.r).schedule,
           deployment_type            = (snap.r).deployment_type,
           has_penalty                = (snap.r).has_penalty,
           date_hired                 = (snap.r).date_hired,
           coordinator                = (snap.r).coordinator,
           hrco_name                  = (snap.r).hrco_name,
           last_name                  = (snap.r).last_name,
           first_name                 = (snap.r).first_name,
           middle_name                = (snap.r).middle_name,
           date_of_separation         = (snap.r).date_of_separation,
           separation_status          = (snap.r).separation_status,
           tagged_at                  = (snap.r).tagged_at,
           inactive_at                = (snap.r).inactive_at,
           inactive_by                = (snap.r).inactive_by,
           for_deactivation_at        = (snap.r).for_deactivation_at,
           for_deactivation_by        = (snap.r).for_deactivation_by,
           deactivated_at             = (snap.r).deactivated_at,
           deactivated_by             = (snap.r).deactivated_by,
           deactivated_visible_until  = (snap.r).deactivated_visible_until,
           last_mika_synced_at        = (snap.r).last_mika_synced_at,
           last_mika_synced_by        = (snap.r).last_mika_synced_by,
           source_headcount_request_id = (snap.r).source_headcount_request_id,
           is_deleted                 = (snap.r).is_deleted,
           over_headcount             = (snap.r).over_headcount,
           deactivation_reason        = (snap.r).deactivation_reason,
           deletion_requested_at      = (snap.r).deletion_requested_at,
           deletion_requested_by      = (snap.r).deletion_requested_by,
           deletion_reason            = (snap.r).deletion_reason,
           deletion_remarks           = (snap.r).deletion_remarks,
           deletion_approved_at       = (snap.r).deletion_approved_at,
           deletion_approved_by       = (snap.r).deletion_approved_by,
           sss_no                     = (snap.r).sss_no,
           philhealth_no              = (snap.r).philhealth_no,
           pagibig_no                 = (snap.r).pagibig_no,
           atm_no                     = (snap.r).atm_no,
           civil_status               = (snap.r).civil_status,
           date_of_birth              = (snap.r).date_of_birth,
           transferred_from_store_id  = (snap.r).transferred_from_store_id,
           last_transfer_at           = (snap.r).last_transfer_at,
           last_transfer_by           = (snap.r).last_transfer_by,
           inactive_visible_until     = (snap.r).inactive_visible_until,
           is_archived                = (snap.r).is_archived,
           archived_at                = (snap.r).archived_at,
           archived_by                = (snap.r).archived_by,
           archive_reason             = (snap.r).archive_reason,
           restored_at                = (snap.r).restored_at,
           restored_by                = (snap.r).restored_by,
           source_baseline_import_batch_id = (snap.r).source_baseline_import_batch_id,
           roving_assignment_id       = (snap.r).roving_assignment_id,
           is_pool_employee           = (snap.r).is_pool_employee
      FROM snap
     WHERE p.id = snap.entity_id
       AND p.source_baseline_import_batch_id = p_batch_id;
    GET DIAGNOSTICS v_plantilla_restored = ROW_COUNT;

    -- ── Batch-updated stores: restore prior row snapshot ──────────────────────
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
       SET account_id      = (snap.r).account_id,
           store_name      = (snap.r).store_name,
           store_branch    = (snap.r).store_branch,
           area_city       = (snap.r).area_city,
           province        = (snap.r).province,
           is_active       = (snap.r).is_active,
           created_at      = (snap.r).created_at,
           updated_at      = (snap.r).updated_at,
           group_id        = (snap.r).group_id,
           hrco_user_id    = (snap.r).hrco_user_id,
           om_user_id      = (snap.r).om_user_id,
           vcode           = (snap.r).vcode,
           area_province   = (snap.r).area_province,
           type            = (snap.r).type,
           with_penalty    = (snap.r).with_penalty,
           status          = (snap.r).status,
           created_by      = (snap.r).created_by,
           updated_by      = (snap.r).updated_by,
           approved_by     = (snap.r).approved_by,
           approved_at     = (snap.r).approved_at,
           source_import_id = (snap.r).source_import_id,
           employment_type = (snap.r).employment_type
      FROM snap
     WHERE st.id = snap.entity_id
       AND st.source_import_id = p_batch_id;
    GET DIAGNOSTICS v_stores_restored = ROW_COUNT;

    -- ── Batch-created stores: deactivate only when no live plantilla/allocation ─
    UPDATE public.stores st
       SET is_active  = false,
           status     = 'archived',
           updated_at = now(),
           updated_by = v_actor
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

    -- ── Roving groups created by this batch: close if no active allocations ───
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

    -- ── Mark rollback success ─────────────────────────────────────────────────
    UPDATE public.plantilla_import_batches
       SET status                    = 'rolled_back',
           rolled_back_by            = v_uid,
           rolled_back_at            = now(),
           rollback_reason           = v_reason,
           rollback_error_detail     = NULL,
           rollback_role             = v_caller_role,
           rollback_latency_seconds  = round(
             extract(epoch from (now() - v_batch.approved_at))::numeric, 2
           ),
           updated_at                = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_uid,
      'plantilla_import_batches',
      'UPDATE',
      p_batch_id,
      jsonb_build_object('status', 'approved'),
      jsonb_build_object(
        'status',                   'rolled_back',
        'batch_id',                 p_batch_id,
        'plantilla_restored',       v_plantilla_restored,
        'plantilla_archived',       v_plantilla_archived,
        'stores_restored',          v_stores_restored,
        'stores_deactivated',       v_stores_deactivated,
        'allocations_restored',     v_allocations_restored,
        'allocations_deactivated',  v_allocations_deactivated,
        'roving_groups_archived',   v_roving_groups_archived,
        'rollback_role',            v_caller_role,
        'rollback_latency_seconds', round(
          extract(epoch from (now() - v_batch.approved_at))::numeric, 2
        ),
        'reason',                   v_reason
      )
    );

    RETURN jsonb_build_object(
      'batch_id',           p_batch_id,
      'status',             'rolled_back',
      'plantilla_restored', v_plantilla_restored,
      'plantilla_archived', v_plantilla_archived,
      'stores_restored',    v_stores_restored,
      'stores_archived',    v_stores_deactivated
    );

  EXCEPTION WHEN OTHERS THEN
    UPDATE public.plantilla_import_batches
       SET status                = 'approved', -- revert state on rollback failure
           rollback_error_detail = format('[%s] %s', SQLSTATE, SQLERRM),
           updated_at            = now()
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id', p_batch_id,
      'status',   'rollback_failed',
      'error',    format('[%s] %s', SQLSTATE, SQLERRM)
    );
  END;

END$func$;

REVOKE ALL ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rollback_plantilla_import_batch(uuid, text) TO authenticated;

-- ── 6. Gate fn_request_emploc_deletion ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_request_emploc_deletion(
  p_hr_emploc_id       uuid,
  p_reason             text,
  p_deletion_type      text DEFAULT 'Backout',
  p_original_emploc_id uuid DEFAULT NULL
)
RETURNS public.hr_emploc_deletion_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_emp         public.hr_emploc;
  v_profile     public.users_profile;
  v_req         public.hr_emploc_deletion_requests;
  v_full_name   text;
  v_last_name   text;
  v_first_name  text;
  v_store       text;
  v_name        text;
  v_parts       text[];
BEGIN
  -- RBAC: Ops roles or full access
  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: Ops or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Audit Freeze Gate (Phase 2A) ─────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  IF p_deletion_type NOT IN ('Backout', 'Duplicate Record') THEN
    RAISE EXCEPTION 'invalid deletion_type: %. Must be Backout or Duplicate Record', p_deletion_type
      USING ERRCODE = '22023';
  END IF;

  IF p_deletion_type = 'Duplicate Record' AND p_original_emploc_id IS NULL THEN
    RAISE EXCEPTION 'original_emploc_id is required for Duplicate Record deletion type'
      USING ERRCODE = '22023';
  END IF;

  IF p_original_emploc_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.hr_emploc
      WHERE id = p_original_emploc_id AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'original_emploc_id % not found or archived', p_original_emploc_id
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or already archived', p_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION 'cannot request deletion: employee is already in Plantilla'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.plantilla
    WHERE hr_emploc_id = p_hr_emploc_id
      AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'cannot request deletion: active Plantilla record exists'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'a pending deletion request already exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_profile FROM public.users_profile WHERE id = public.get_my_profile_id();
  v_full_name := COALESCE(v_profile.full_name, public.get_my_full_name());

  -- Immutable name snapshot (Last, First or First Last)
  v_name := COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name);
  IF v_name LIKE '%, %' THEN
    v_last_name  := BTRIM(split_part(v_name, ', ', 1));
    v_first_name := BTRIM(split_part(v_name, ', ', 2));
  ELSE
    v_parts      := regexp_split_to_array(BTRIM(v_name), '\s+');
    v_last_name  := v_parts[array_length(v_parts, 1)];
    v_first_name := BTRIM(array_to_string(v_parts[1:array_length(v_parts,1)-1], ' '));
  END IF;

  v_store := COALESCE(NULLIF(BTRIM(COALESCE(v_emp.store_name, '')), ''), v_emp.account);

  INSERT INTO public.hr_emploc_deletion_requests (
    hr_emploc_id,
    applicant_name,
    vcode,
    account,
    reason,
    requested_by,
    requested_by_role,
    requested_by_user_id,
    deletion_type,
    original_emploc_id,
    reopen_vacancy,
    original_hr_status,
    snapshot_last_name,
    snapshot_first_name,
    snapshot_position,
    snapshot_store,
    status
  ) VALUES (
    p_hr_emploc_id,
    COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name),
    v_emp.vcode,
    v_emp.account,
    BTRIM(p_reason),
    v_full_name,
    COALESCE(v_profile.role, public.get_my_role()),
    public.get_my_profile_id(),
    p_deletion_type,
    p_original_emploc_id,
    (p_deletion_type = 'Backout'),
    v_emp.hr_status,
    v_last_name,
    v_first_name,
    v_emp.position,
    v_store,
    'Pending'
  )
  RETURNING * INTO v_req;

  INSERT INTO public.hr_emploc_deletion_activities (
    request_id, activity_type, performed_by, performed_by_user_id, remarks, snapshot
  ) VALUES (
    v_req.id,
    'Request Submitted',
    v_full_name,
    public.get_my_profile_id(),
    BTRIM(p_reason),
    jsonb_build_object(
      'deletion_type',     p_deletion_type,
      'applicant_name',    v_req.applicant_name,
      'snapshot_last_name', v_last_name,
      'snapshot_first_name', v_first_name,
      'vcode',             v_req.vcode,
      'account',           v_req.account,
      'snapshot_position', v_emp.position,
      'snapshot_store',    v_store,
      'requested_by',      v_full_name,
      'requested_by_role', COALESCE(v_profile.role, public.get_my_role()),
      'original_emploc_id', p_original_emploc_id,
      'submitted_at',      NOW()
    )
  );

  -- Overlay hr_status (main status field is untouched)
  UPDATE public.hr_emploc
  SET hr_status  = 'Pending Deletion',
      updated_at = NOW(),
      updated_by = public.get_my_profile_id()
  WHERE id = p_hr_emploc_id;

  RETURN v_req;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_request_emploc_deletion(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_request_emploc_deletion(uuid, text, text, uuid) TO authenticated;

-- ── 7. Gate plantilla_request_deletion ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.plantilla_request_deletion(p_plantilla_id uuid, p_reason text, p_remarks text DEFAULT NULL::text)
 RETURNS public.plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_row public.plantilla;
BEGIN
  IF NOT public.i_can_act_on_plantilla() THEN
    RAISE EXCEPTION 'forbidden: insufficient role for deletion request';
  END IF;

  -- ── Audit Freeze Gate (Phase 2A) ─────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  IF p_reason NOT IN ('Store Closed','Position No Longer Needed','Duplicate','Wrong Entry') THEN
    RAISE EXCEPTION 'invalid deletion_reason: %', p_reason;
  END IF;

  SELECT * INTO v_row FROM public.plantilla
  WHERE id = p_plantilla_id AND COALESCE(is_deleted, FALSE) = FALSE
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plantilla not found'; END IF;

  IF v_row.status = 'Active' THEN
    RAISE EXCEPTION 'cannot delete an Active employee';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope';
  END IF;

  UPDATE public.plantilla
  SET deletion_requested_at = NOW(),
      deletion_requested_by = auth.uid(),
      deletion_reason       = p_reason,
      deletion_remarks      = p_remarks,
      updated_by            = auth.uid(),
      updated_at            = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$
;

REVOKE ALL ON FUNCTION public.plantilla_request_deletion(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plantilla_request_deletion(uuid, text, text) TO authenticated;

COMMIT;
