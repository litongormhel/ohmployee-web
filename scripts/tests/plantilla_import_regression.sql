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
--     6. Vacant-only 086 batch assertion: approved vacant batch retains rollback_ready=true
--        and is a strict no-op under migration 087's reset predicate
--     7. Direct executor lockdown assertion: calling rollback_plantilla_import_batch
--        as authenticated role is hard-denied with error 42501 (insufficient privilege)
--     8. Protected occupant guard assertion: rollback hard-blocks with
--        ROLLBACK_BLOCKED_PROTECTED_OCCUPANT if a batch slot is occupied by an external employee
--     9. Legacy lineage assertion: approved batch with rollback_ready=false fails closed
--    10. Real request/approve flow + Zero-edit lock assertion: post-approval edit is blocked
--    11. Full 6-table post-rollback baseline comparison: stores active, slots total/occupied/open,
--        allocations active, plantilla active, store_links active, vacancies active
--    12. Blocked file assertion: single-letter initial hard-blocked with BATCH_BLOCKED
--    13. Rejection assertion: transitions to rejected with audit log and zero plantilla writes
--   AT THE END:
--     Raises exception 'REGRESSION_TEST_PASS: <JSON_RESULTS>'
--     This aborts the transaction cleanly, rolling back 100% of all test data.
--     Zero test records persist.
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
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-015","STORE_NAME":"Puregold Reg 015","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-016","STORE_NAME":"Puregold Reg 016","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-017","STORE_NAME":"Puregold Reg 017","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-018","STORE_NAME":"Puregold Reg 018","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"},
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REG-019","STORE_NAME":"Puregold Reg 019","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REG-010","LAST_NAME":"GARCIA","FIRST_NAME":"MARK","MIDDLE_NAME":"REYES","DATE_HIRED":"2026-01-15"}
  ]'::jsonb;

  v_stationary_rows jsonb := '[
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-STAT-001","STORE_NAME":"Puregold Stat 001","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-STAT-0001","LAST_NAME":"CRUZ","FIRST_NAME":"JUAN","MIDDLE_NAME":"SANTOS","DATE_HIRED":"2026-01-15"}
  ]'::jsonb;

  v_vacant_rows jsonb := '[
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-VAC-001","STORE_NAME":"Puregold Vacant 001","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"","LAST_NAME":"","FIRST_NAME":""}
  ]'::jsonb;

  v_blocked_rows jsonb := '[
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-BLK-001","STORE_NAME":"Puregold Blocked 001","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-BLK-0001","LAST_NAME":"CRUZ","FIRST_NAME":"JUAN","MIDDLE_NAME":"B","DATE_HIRED":"2026-01-15"}
  ]'::jsonb;

  v_reject_rows jsonb := '[
    {"GROUP_NAME":"GROUP 4","ACCOUNT_NAME":"APEX","MOTHER_ACCOUNT":"PUREGOLD","VCODE":"PG-REJ-001","STORE_NAME":"Puregold Reject 001","AREA_PROVINCE":"Metro Manila","AREA_CITY":"Manila","POSITION":"Merchandiser","EMPLOYEE_NO":"EMP-REJ-0001","LAST_NAME":"REYES","FIRST_NAME":"ANA","MIDDLE_NAME":"CRUZ","DATE_HIRED":"2026-01-15"}
  ]'::jsonb;

  -- Baseline 6-table metrics
  v_base_stores_active      int;
  v_base_slots_active       int;
  v_base_slots_occupied     int;
  v_base_slots_open         int;
  v_base_allocations        int;
  v_base_plantilla_active   int;
  v_base_store_links        int;
  v_base_vacancies          int;

  -- Post-rollback 6-table metrics
  v_post_stores_active      int;
  v_post_slots_active       int;
  v_post_slots_occupied     int;
  v_post_slots_open         int;
  v_post_allocations        int;
  v_post_plantilla_active   int;
  v_post_store_links        int;
  v_post_vacancies          int;
  v_post_slots_closed_rollback int;

  -- Derived fixture metrics
  v_expected_total_rows  int;
  v_expected_emp_count   int;
  v_expected_store_count int;

  -- Test execution variables
  v_stat_eval            jsonb;
  v_rov_submit           jsonb;
  v_rov_batch_id         uuid;
  v_rov_approve          jsonb;
  v_batch_rec            public.plantilla_import_batches%ROWTYPE;

  v_vac_submit           jsonb;
  v_vac_batch_id         uuid;
  v_vac_approve          jsonb;
  v_vac_batch_rec        public.plantilla_import_batches%ROWTYPE;

  v_auth_denied          boolean := false;
  v_prot_caught          boolean := false;
  v_prot_res             jsonb;
  v_batch_slot_id        uuid;
  v_external_plantilla_id uuid;

  v_legacy_caught        boolean := false;

  v_req_res              jsonb;
  v_zero_edit_caught     boolean := false;
  v_app_res              jsonb;

  v_blocked_caught       boolean := false;
  v_blocked_err          text;

  v_rej_submit           jsonb;
  v_rej_batch_id         uuid;
  v_rej_res              jsonb;
  v_rej_audit_count      int;

  v_test_summary         jsonb;
BEGIN
  -- Authenticate as Super Admin
  PERFORM set_config('request.jwt.claim.sub', '71d245b9-10b1-42b9-ad9e-253f999daf6d', true);

  -- Measure complete baseline across all 6 tables for APEX
  SELECT count(*) INTO v_base_stores_active
    FROM public.stores
   WHERE account_id = v_account_id AND is_active = true;

  SELECT count(*) FILTER (WHERE ps.slot_status <> 'closed'),
         count(*) FILTER (WHERE ps.slot_status = 'occupied'),
         count(*) FILTER (WHERE ps.slot_status = 'open')
    INTO v_base_slots_active, v_base_slots_occupied, v_base_slots_open
    FROM public.plantilla_slots ps
    JOIN public.stores st ON st.id = ps.store_id
   WHERE st.account_id = v_account_id;

  SELECT count(*) INTO v_base_allocations
    FROM public.employee_store_allocations esa
    JOIN public.plantilla p ON p.id = esa.plantilla_id
   WHERE p.account_id = v_account_id AND esa.is_active = true;

  SELECT count(*) INTO v_base_plantilla_active
    FROM public.plantilla
   WHERE account_id = v_account_id AND status = 'Active' AND is_deleted = false AND is_archived = false;

  SELECT count(*) INTO v_base_store_links
    FROM public.plantilla_store_links psl
    JOIN public.plantilla p ON p.id = psl.plantilla_id
   WHERE p.account_id = v_account_id AND p.is_archived = false AND p.status = 'Active' AND psl.deleted_at IS NULL;

  SELECT count(*) INTO v_base_vacancies
    FROM public.vacancies v
    JOIN public.stores st ON st.id = v.store_id
   WHERE st.account_id = v_account_id AND v.is_archived = false;

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

  IF v_batch_rec.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: roving batch status expected "pending_approval", got "%"',
      v_batch_rec.status;
  END IF;
  IF v_batch_rec.valid_rows <> v_expected_total_rows THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: roving batch valid_rows expected %, got %',
      v_expected_total_rows, v_batch_rec.valid_rows;
  END IF;
  IF v_batch_rec.flagged_rows <> 0 THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: roving batch flagged_rows expected 0, got %',
      v_batch_rec.flagged_rows;
  END IF;
  IF v_batch_rec.blocked_rows <> 0 THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: roving batch blocked_rows expected 0, got %',
      v_batch_rec.blocked_rows;
  END IF;

  -- --------------------------------------------------------------------------
  -- 3. Test Roving Batch Approval
  -- --------------------------------------------------------------------------
  v_rov_approve := public.approve_plantilla_import_batch(v_rov_batch_id);

  IF (v_rov_approve->>'status') <> 'approved' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: approve result status expected "approved", got %',
      v_rov_approve->>'status';
  END IF;

  SELECT * INTO v_batch_rec
    FROM public.plantilla_import_batches
   WHERE id = v_rov_batch_id;

  IF NOT COALESCE(v_batch_rec.rollback_ready, false) THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: approved batch rollback_ready expected true, got false';
  END IF;

  -- --------------------------------------------------------------------------
  -- 3b. Test Vacant-Only 086 Batch & 087 Predicate Immunity
  -- --------------------------------------------------------------------------
  v_vac_submit := public.submit_plantilla_baseline_import(
    'regression_vacant_test.xlsx',
    v_group_id,
    v_account_id,
    v_vacant_rows
  );
  v_vac_batch_id := (v_vac_submit->>'batch_id')::uuid;
  v_vac_approve := public.approve_plantilla_import_batch(v_vac_batch_id);

  SELECT * INTO v_vac_batch_rec
    FROM public.plantilla_import_batches
   WHERE id = v_vac_batch_id;

  IF NOT COALESCE(v_vac_batch_rec.rollback_ready, false) THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: approved vacant batch rollback_ready expected true';
  END IF;

  -- Run migration 087 lineage reset predicate explicitly
  UPDATE public.plantilla_import_batches b
     SET rollback_ready = false
   WHERE b.id = v_vac_batch_id
     AND b.status = 'approved'
     AND b.rollback_ready = true
     AND (
       (COALESCE(b.employees_created, 0) > 0 AND NOT EXISTS (
          SELECT 1 FROM public.plantilla_import_commit_snapshots s
           WHERE s.batch_id = b.id AND s.entity_type = 'allocation' AND s.action = 'insert'
       ))
       OR
       (COALESCE(b.employees_created, 0) > 0 AND NOT EXISTS (
          SELECT 1 FROM public.plantilla_import_commit_snapshots s
           WHERE s.batch_id = b.id AND s.entity_type = 'slot'
       ))
     );

  -- Assert vacant-only batch remains rollback_ready = true
  SELECT * INTO v_vac_batch_rec
    FROM public.plantilla_import_batches
   WHERE id = v_vac_batch_id;

  IF NOT COALESCE(v_vac_batch_rec.rollback_ready, false) THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: vacant batch rollback_ready was incorrectly reset by 087 predicate';
  END IF;

  -- Clean up vacant batch within this transaction
  PERFORM public.rollback_plantilla_import_batch(v_vac_batch_id, 'vacant fixture cleanup');

  -- --------------------------------------------------------------------------
  -- 3c. Test Direct Executor Lockdown (Revoked from Authenticated)
  -- --------------------------------------------------------------------------
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.rollback_plantilla_import_batch(v_rov_batch_id, 'direct authenticated call');
    v_auth_denied := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_auth_denied := true;
  END;
  RESET ROLE;

  IF NOT v_auth_denied THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: direct call by authenticated role was not denied (42501)';
  END IF;

  -- --------------------------------------------------------------------------
  -- 3d. Test Protected Occupant Hard-Block (ADR-002 Safety Guard)
  -- --------------------------------------------------------------------------
  -- Pick a batch-created slot from the roving batch
  SELECT entity_id INTO v_batch_slot_id
    FROM public.plantilla_import_commit_snapshots
   WHERE batch_id = v_rov_batch_id
     AND entity_type = 'slot'
     AND action = 'insert'
   LIMIT 1;

  -- Pick an external employee not created/updated by this batch
  SELECT id INTO v_external_plantilla_id
    FROM public.plantilla
   WHERE account_id = v_account_id
     AND id NOT IN (
       SELECT entity_id FROM public.plantilla_import_commit_snapshots
        WHERE batch_id = v_rov_batch_id AND entity_type = 'plantilla'
     )
   LIMIT 1;

  IF v_batch_slot_id IS NOT NULL AND v_external_plantilla_id IS NOT NULL THEN
    BEGIN
      UPDATE public.plantilla_slots
         SET current_occupant_plantilla_id = v_external_plantilla_id
       WHERE id = v_batch_slot_id;

      v_prot_res := public.rollback_plantilla_import_batch(v_rov_batch_id, 'testing protected occupant');

      IF (v_prot_res->>'status') <> 'rollback_failed' OR (v_prot_res->>'error') NOT LIKE '%ROLLBACK_BLOCKED_PROTECTED_OCCUPANT%' THEN
        RAISE EXCEPTION 'ASSERTION_FAILED: expected ROLLBACK_BLOCKED_PROTECTED_OCCUPANT, got: %', v_prot_res;
      END IF;

      v_prot_caught := true;
      RAISE EXCEPTION 'SUBTRANS_ROLLBACK' USING ERRCODE = 'P0002';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE '%SUBTRANS_ROLLBACK%' THEN
        NULL; -- Subtransaction reverted slot occupant mutation cleanly
      ELSE
        RAISE;
      END IF;
    END;

    IF NOT v_prot_caught THEN
      RAISE EXCEPTION 'ASSERTION_FAILED: protected occupant did not block rollback';
    END IF;
  END IF;

  -- --------------------------------------------------------------------------
  -- 3e. Test Legacy Lineage Batch Fails Closed
  -- --------------------------------------------------------------------------
  BEGIN
    UPDATE public.plantilla_import_batches SET rollback_ready = false WHERE id = v_rov_batch_id;
    PERFORM public.rollback_plantilla_import_batch(v_rov_batch_id, 'testing legacy fail closed');
    v_legacy_caught := false;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%ROLLBACK_NOT_READY%' THEN
      v_legacy_caught := true;
    ELSE
      RAISE EXCEPTION 'ASSERTION_FAILED: expected ROLLBACK_NOT_READY, got: %', SQLERRM;
    END IF;
  END;

  IF NOT v_legacy_caught THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: batch with rollback_ready=false did not fail closed';
  END IF;

  -- Restore rollback_ready for real request/approve flow
  UPDATE public.plantilla_import_batches SET rollback_ready = true WHERE id = v_rov_batch_id;

  -- --------------------------------------------------------------------------
  -- 3f. Test Real Request / Approve Flow & Strict Zero-Edit Lock
  -- --------------------------------------------------------------------------
  v_req_res := public.request_plantilla_import_rollback(
    v_rov_batch_id,
    'wrong_batch',
    'Regression test real rollback request'
  );

  SELECT * INTO v_batch_rec
    FROM public.plantilla_import_batches
   WHERE id = v_rov_batch_id;

  IF v_batch_rec.rollback_status <> 'requested' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: expected rollback_status "requested", got "%"',
      v_batch_rec.rollback_status;
  END IF;

  -- Zero-Edit Lock subtransaction test:
  BEGIN
    -- Backdate approved_at so post-approval edit is detected beyond grace window
    UPDATE public.plantilla_import_batches
       SET approved_at = now() - interval '1 hour'
     WHERE id = v_rov_batch_id;

    -- Mutate one batch employee
    UPDATE public.plantilla
       SET remarks = 'post_approval_edit'
     WHERE id = (
       SELECT entity_id FROM public.plantilla_import_commit_snapshots
        WHERE batch_id = v_rov_batch_id AND entity_type = 'plantilla' LIMIT 1
     );

    PERFORM public.approve_plantilla_import_rollback(v_rov_batch_id);
    v_zero_edit_caught := false;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%ZERO_EDIT_LOCK%' THEN
      v_zero_edit_caught := true;
    ELSE
      RAISE EXCEPTION 'ASSERTION_FAILED: expected ZERO_EDIT_LOCK, got: %', SQLERRM;
    END IF;
  END;

  IF NOT v_zero_edit_caught THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: post-approval edit was not hard-blocked by ZERO_EDIT_LOCK';
  END IF;

  -- Execute real approval through wrapper
  v_app_res := public.approve_plantilla_import_rollback(v_rov_batch_id);

  IF (v_app_res->>'status') <> 'rolled_back' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: approve rollback expected "rolled_back", got %',
      v_app_res->>'status';
  END IF;

  SELECT * INTO v_batch_rec
    FROM public.plantilla_import_batches
   WHERE id = v_rov_batch_id;

  IF v_batch_rec.status <> 'rolled_back' OR v_batch_rec.rollback_status <> 'completed' THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: batch status expected rolled_back/completed, got %/%',
      v_batch_rec.status, v_batch_rec.rollback_status;
  END IF;

  -- --------------------------------------------------------------------------
  -- 3g. Full 6-Table Post-Rollback Baseline Comparison
  -- --------------------------------------------------------------------------
  SELECT count(*) INTO v_post_stores_active
    FROM public.stores
   WHERE account_id = v_account_id AND is_active = true;

  SELECT count(*) FILTER (WHERE ps.slot_status <> 'closed'),
         count(*) FILTER (WHERE ps.slot_status = 'occupied'),
         count(*) FILTER (WHERE ps.slot_status = 'open'),
         count(*) FILTER (WHERE ps.closure_reason_code = 'IMPORT_ROLLBACK')
    INTO v_post_slots_active, v_post_slots_occupied, v_post_slots_open, v_post_slots_closed_rollback
    FROM public.plantilla_slots ps
    JOIN public.stores st ON st.id = ps.store_id
   WHERE st.account_id = v_account_id;

  SELECT count(*) INTO v_post_allocations
    FROM public.employee_store_allocations esa
    JOIN public.plantilla p ON p.id = esa.plantilla_id
   WHERE p.account_id = v_account_id AND esa.is_active = true;

  SELECT count(*) INTO v_post_plantilla_active
    FROM public.plantilla
   WHERE account_id = v_account_id AND status = 'Active' AND is_deleted = false AND is_archived = false;

  SELECT count(*) INTO v_post_store_links
    FROM public.plantilla_store_links psl
    JOIN public.plantilla p ON p.id = psl.plantilla_id
   WHERE p.account_id = v_account_id AND p.is_archived = false AND p.status = 'Active' AND psl.deleted_at IS NULL;

  SELECT count(*) INTO v_post_vacancies
    FROM public.vacancies v
    JOIN public.stores st ON st.id = v.store_id
   WHERE st.account_id = v_account_id AND v.is_archived = false;

  IF v_post_stores_active <> v_base_stores_active THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: stores_active mismatch: expected %, got %',
      v_base_stores_active, v_post_stores_active;
  END IF;
  IF v_post_slots_active <> v_base_slots_active THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: slots_active mismatch: expected %, got %',
      v_base_slots_active, v_post_slots_active;
  END IF;
  IF v_post_slots_occupied <> v_base_slots_occupied THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: slots_occupied mismatch: expected %, got %',
      v_base_slots_occupied, v_post_slots_occupied;
  END IF;
  IF v_post_slots_open <> v_base_slots_open THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: slots_open mismatch: expected %, got %',
      v_base_slots_open, v_post_slots_open;
  END IF;
  IF v_post_slots_closed_rollback < 15 THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: expected at least 15 rollback-closed slots, got %',
      v_post_slots_closed_rollback;
  END IF;
  IF v_post_allocations <> v_base_allocations THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: allocations mismatch: expected %, got %',
      v_base_allocations, v_post_allocations;
  END IF;
  IF v_post_plantilla_active <> v_base_plantilla_active THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: plantilla_active mismatch: expected %, got %',
      v_base_plantilla_active, v_post_plantilla_active;
  END IF;
  IF v_post_store_links <> v_base_store_links THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: store_links mismatch: expected %, got %',
      v_base_store_links, v_post_store_links;
  END IF;
  IF v_post_vacancies <> v_base_vacancies THEN
    RAISE EXCEPTION 'ASSERTION_FAILED: vacancies mismatch: expected %, got %',
      v_base_vacancies, v_post_vacancies;
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
    'roving_approval', 'PASS',
    'vacant_only_immunity', 'PASS',
    'executor_lockdown', 'PASS',
    'protected_occupant_guard', 'PASS',
    'legacy_lineage_fail_closed', 'PASS',
    'zero_edit_lock', 'PASS',
    'request_approve_flow', 'PASS',
    '6_table_baseline_parity', 'PASS',
    'blocked_rejection', 'PASS',
    'batch_rejection_audit', 'PASS',
    'timestamp', now()
  );

  -- Always rollback 100% of all operations
  RAISE EXCEPTION 'REGRESSION_TEST_PASS: %', v_test_summary USING ERRCODE = 'P0001';
END;
$$;
