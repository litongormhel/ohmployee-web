-- ============================================================================
-- Plantilla Import Regression Test Suite (Self-Rolling-Back)
-- File: scripts/tests/plantilla_import_regression.sql
--
-- USAGE:
--   Run in Supabase SQL Editor (or psql) on STAGING (qqiiznmqxfoamqytjica).
--   Instruction: Run before and after any change touching Import Plantilla.
--
-- HOW IT WORKS:
--   Executes a complete lifecycle audit inside a single transaction:
--     1. Stationary valid assignment (1.00 HC, is_roving=false)
--     2. Multi-store roving assignment (14 rows, 4 roving employees across 14 stores)
--     3. Valid evaluation assertion: 0 flagged, 14 valid, neutral roving_info note
--     4. Submission assertion: routes directly to 'pending_approval' (no pending_review)
--     5. Approval assertion: completes without INVALID_STATE, creates derived counts
--     6. Blocked file assertion: single-letter initial hard-blocked with BATCH_BLOCKED
--     7. Rejection assertion: transitions to rejected with audit log and zero plantilla writes
--   AT THE END:
--     Raises exception 'REGRESSION_TEST_PASS: <JSON_RESULTS>'
--     This aborts the transaction cleanly, rolling back 100% of all test data.
--     Zero test records persist.
--
-- WHY IT FAILS AGAINST PRE-085 FUNCTION BODIES:
--   1. Assertion 2 (Flags Check): In pre-085, submit emitted advisory 'roving'
--      flags on every roving row, causing validation_status to evaluate to
--      'flagged' instead of 'valid', producing flagged_rows = 14 and valid_rows = 0.
--   2. Assertion 3 (Submission Status Check): Pre-085 routed batches with flagged
--      rows to status = 'pending_review' instead of 'pending_approval'.
--   3. Assertion 4 (Approval State Machine Check): Pre-085 approve_plantilla_import_batch
--      asserted status IN ('pending_approval', 'commit_failed'). Calling approve
--      on a roving batch raised INVALID_STATE: only pending_approval or commit_failed
--      can be approved (current=pending_review).
-- ============================================================================

DO $$
DECLARE
  v_group_id   uuid := '295d1da6-c799-4f12-a693-0a5e23845368'; -- Group 4
  v_account_id uuid := '42a3cec9-a5eb-4c90-ac45-45669c212b12'; -- APEX

  -- Fixtures
  v_roving_rows jsonb := '[
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-006","STORE_NAME":"Puregold Reg 006","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0006","LAST_NAME":"ROSALES","FIRST_NAME":"GRACELYN","MIDDLE_NAME":"BENITEZ","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-007","STORE_NAME":"Puregold Reg 007","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0006","LAST_NAME":"ROSALES","FIRST_NAME":"GRACELYN","MIDDLE_NAME":"BENITEZ","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-008","STORE_NAME":"Puregold Reg 008","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0008","LAST_NAME":"MENDOZA","FIRST_NAME":"JOSHUA","MIDDLE_NAME":"ALVAREZ","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-009","STORE_NAME":"Puregold Reg 009","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0008","LAST_NAME":"MENDOZA","FIRST_NAME":"JOSHUA","MIDDLE_NAME":"ALVAREZ","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-010","STORE_NAME":"Puregold Reg 010","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0008","LAST_NAME":"MENDOZA","FIRST_NAME":"JOSHUA","MIDDLE_NAME":"ALVAREZ","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-011","STORE_NAME":"Puregold Reg 011","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0009","LAST_NAME":"DELA CRUZ","FIRST_NAME":"CHRISTIAN","MIDDLE_NAME":"SANTOS","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-012","STORE_NAME":"Puregold Reg 012","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0009","LAST_NAME":"DELA CRUZ","FIRST_NAME":"CHRISTIAN","MIDDLE_NAME":"SANTOS","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-013","STORE_NAME":"Puregold Reg 013","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0009","LAST_NAME":"DELA CRUZ","FIRST_NAME":"CHRISTIAN","MIDDLE_NAME":"SANTOS","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-014","STORE_NAME":"Puregold Reg 014","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0009","LAST_NAME":"DELA CRUZ","FIRST_NAME":"CHRISTIAN","MIDDLE_NAME":"SANTOS","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-015","STORE_NAME":"Puregold Reg 015","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-016","STORE_NAME":"Puregold Reg 016","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-017","STORE_NAME":"Puregold Reg 017","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-018","STORE_NAME":"Puregold Reg 018","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-019","STORE_NAME":"Puregold Reg 019","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-0010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"}
  ]'::jsonb;

  v_stationary_rows jsonb := '[
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-STAT-001","STORE_NAME":"Puregold Stat 001","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-STAT-0001","LAST_NAME":"CRUZ","FIRST_NAME":"JUAN","MIDDLE_NAME":"SANTOS","DATE_HIRED":"2026-01-15"}
  ]'::jsonb;

  v_blocked_rows jsonb := '[
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-BLK-001","STORE_NAME":"Puregold Blocked 001","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-BLK-0001","LAST_NAME":"CRUZ","FIRST_NAME":"JUAN","MIDDLE_NAME":"B","DATE_HIRED":"2026-01-15"}
  ]'::jsonb;

  v_reject_rows jsonb := '[
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REJ-001","STORE_NAME":"Puregold Reject 001","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REJ-0001","LAST_NAME":"REYES","FIRST_NAME":"ANA","MIDDLE_NAME":"CRUZ","DATE_HIRED":"2026-01-15"}
  ]'::jsonb;

  -- Derived fixture metrics
  v_expected_total_rows int;
  v_expected_emp_count  int;
  v_expected_store_count int;

  -- Test execution variables
  v_stat_eval jsonb;
  v_rov_submit jsonb;
  v_rov_batch_id uuid;
  v_rov_approve jsonb;
  v_batch_rec public.plantilla_import_batches%ROWTYPE;
  v_before_plantilla int;
  v_after_plantilla int;
  v_before_allocations int;
  v_after_allocations int;

  v_blocked_caught boolean := false;
  v_blocked_err text;

  v_rej_submit jsonb;
  v_rej_batch_id uuid;
  v_rej_res jsonb;
  v_rej_audit_count int;

  v_test_summary jsonb;
BEGIN
  -- Authenticate as Super Admin
  PERFORM set_config('request.jwt.claim.sub', '71d245b9-10b1-42b9-ad9e-253f999daf6d', true);

  -- Derive expected counts directly from fixture structure
  SELECT count(*),
         count(DISTINCT r->>'EMPLOYEE_NO'),
         count(DISTINCT r->>'VCODE')
    INTO v_expected_total_rows, v_expected_emp_count, v_expected_store_count
    FROM jsonb_array_elements(v_roving_rows) r;

  -- --------------------------------------------------------------------------
  -- 1. Test Stationary Evaluation
  -- --------------------------------------------------------------------------
  SELECT jsonb_agg(to_jsonb(e)) INTO v_stat_eval
    FROM public._evaluate_plantilla_import_rows(v_group_id, v_account_id, v_stationary_rows) e;

  IF (v_stat_eval->0->>'validation_status') <> 'valid' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: stationary row status expected "valid", got %',
      v_stat_eval->0->>'validation_status';
  END IF;
  IF (v_stat_eval->0->>'is_roving')::boolean <> false THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: stationary row is_roving expected false';
  END IF;
  IF (v_stat_eval->0->>'required_hc_raw') <> '1.00' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: stationary row required_hc_raw expected "1.00", got %',
      v_stat_eval->0->>'required_hc_raw';
  END IF;

  -- --------------------------------------------------------------------------
  -- 2. Test Roving Fixture Evaluation & Submission
  -- --------------------------------------------------------------------------
  -- Measure baseline before roving approval
  SELECT count(*) INTO v_before_plantilla
    FROM public.plantilla
   WHERE account_id = v_account_id AND status = 'Active' AND is_deleted = false;

  SELECT count(*) INTO v_before_allocations
    FROM public.employee_store_allocations esa
    JOIN public.plantilla p ON p.id = esa.plantilla_id
   WHERE p.account_id = v_account_id AND esa.is_active = true;

  -- Submit roving batch
  v_rov_submit := public.submit_plantilla_baseline_import(
    'regression_roving_test.xlsx',
    v_group_id,
    v_account_id,
    v_roving_rows
  );
  v_rov_batch_id := (v_rov_submit->>'batch_id')::uuid;

  SELECT * INTO v_batch_rec
    FROM public.plantilla_import_batches
   WHERE id = v_rov_batch_id;

  -- Assertions on batch state:
  -- In pre-085, roving rows had advisory 'roving' flags, producing flagged_rows = 14,
  -- valid_rows = 0, and status = 'pending_review'.
  IF v_batch_rec.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: roving batch status expected "pending_approval", got "%" (pre-085 regression: roving flagged as pending_review)',
      v_batch_rec.status;
  END IF;
  IF v_batch_rec.valid_rows <> v_expected_total_rows THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: roving batch valid_rows expected %, got %',
      v_expected_total_rows, v_batch_rec.valid_rows;
  END IF;
  IF v_batch_rec.flagged_rows <> 0 THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: roving batch flagged_rows expected 0, got % (pre-085 regression: roving demoted to flagged)',
      v_batch_rec.flagged_rows;
  END IF;
  IF v_batch_rec.blocked_rows <> 0 THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: roving batch blocked_rows expected 0, got %',
      v_batch_rec.blocked_rows;
  END IF;

  -- --------------------------------------------------------------------------
  -- 3. Test Roving Batch Approval
  -- --------------------------------------------------------------------------
  -- In pre-085, calling approve on a pending_review batch threw INVALID_STATE
  v_rov_approve := public.approve_plantilla_import_batch(v_rov_batch_id);

  IF (v_rov_approve->>'status') <> 'approved' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: approve result status expected "approved", got %',
      v_rov_approve->>'status';
  END IF;

  -- Assert active plantilla count increased by exactly distinct employee count
  SELECT count(*) INTO v_after_plantilla
    FROM public.plantilla
   WHERE account_id = v_account_id AND status = 'Active' AND is_deleted = false;

  IF (v_after_plantilla - v_before_plantilla) <> v_expected_emp_count THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: active plantilla delta expected %, got %',
      v_expected_emp_count, (v_after_plantilla - v_before_plantilla);
  END IF;

  -- Assert active allocations count increased by exactly store count
  SELECT count(*) INTO v_after_allocations
    FROM public.employee_store_allocations esa
    JOIN public.plantilla p ON p.id = esa.plantilla_id
   WHERE p.account_id = v_account_id AND esa.is_active = true;

  IF (v_after_allocations - v_before_allocations) <> v_expected_store_count THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: active allocations delta expected %, got %',
      v_expected_store_count, (v_after_allocations - v_before_allocations);
  END IF;

  -- --------------------------------------------------------------------------
  -- 4. Test Hard-Blocked File Rejection
  -- --------------------------------------------------------------------------
  BEGIN
    PERFORM public.submit_plantilla_baseline_import(
      'regression_blocked_test.xlsx',
      v_group_id,
      v_account_id,
      v_blocked_rows
    );
  EXCEPTION WHEN OTHERS THEN
    v_blocked_caught := true;
    v_blocked_err := SQLERRM;
  END;

  IF NOT v_blocked_caught THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: blocked file did not raise an exception';
  END IF;
  IF v_blocked_err NOT LIKE '%BATCH_BLOCKED%' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: expected BATCH_BLOCKED exception, got: %', v_blocked_err;
  END IF;
  IF EXISTS (SELECT 1 FROM public.plantilla_import_batches WHERE file_name = 'regression_blocked_test.xlsx') THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: blocked batch was persisted in plantilla_import_batches';
  END IF;

  -- --------------------------------------------------------------------------
  -- 5. Test Batch Rejection & Audit Log
  -- --------------------------------------------------------------------------
  v_rej_submit := public.submit_plantilla_baseline_import(
    'regression_reject_test.xlsx',
    v_group_id,
    v_account_id,
    v_reject_rows
  );
  v_rej_batch_id := (v_rej_submit->>'batch_id')::uuid;

  v_rej_res := public.reject_plantilla_import_batch(
    v_rej_batch_id,
    'uploaded_by_mistake',
    'Automated regression rejection'
  );

  IF (v_rej_res->>'status') <> 'rejected' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: reject result status expected "rejected", got %',
      v_rej_res->>'status';
  END IF;

  SELECT count(*) INTO v_rej_audit_count
    FROM public.audit_logs
   WHERE record_id = v_rej_batch_id;

  IF v_rej_audit_count < 1 THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: audit_logs entry missing for rejected batch';
  END IF;

  IF EXISTS (SELECT 1 FROM public.plantilla WHERE employee_no = 'EMP-REJ-0001') THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: rejected batch created employee in plantilla';
  END IF;

  -- --------------------------------------------------------------------------
  -- Final Summary & Forced Rollback
  -- --------------------------------------------------------------------------
  v_test_summary := jsonb_build_object(
    'status', 'ALL_ASSERTIONS_PASSED',
    'roving_fixture_rows', v_expected_total_rows,
    'roving_employees_created', v_expected_emp_count,
    'roving_allocations_created', v_expected_store_count,
    'stationary_evaluation', 'PASS',
    'blocked_rejection', 'PASS',
    'batch_rejection_audit', 'PASS',
    'timestamp', now()
  );

  -- Always rollback 100% of all operations
  RAISE EXCEPTION 'REGRESSION_TEST_PASS: %', v_test_summary USING ERRCODE = 'P0001';
END;
$$;
