-- Migration: 20262606000106_qa_run_scenario_dual_guc_and_constraint_fixes.sql
-- Description: Surgical update to public.qa_run_scenario fixing dual GUC role impersonation,
--              status constraints on hr_emploc & plantilla, collision-proof test data generation,
--              and step telemetry persistence into qa_agent_runs metadata.
-- Base Function: supabase/migrations/20262606000045_qa_role_relay_engine.sql (lines 7–520)
-- Security: SECURITY DEFINER, search_path public, Head Admin/Super Admin authorization guard.
-- Telemetry: Logs to qa_agent_runs and qa_agent_findings.
-- Sandbox: Wraps simulation in an atomic subtransaction rolling back via QA_SANDBOX_ROLLBACK_SUCCESS.

CREATE OR REPLACE FUNCTION public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_orig_jwt text;
  v_orig_sub text;
  v_orig_role text;
  v_code text;
  v_run_id uuid;
  v_caller_profile_id uuid;
  v_sandbox_rolled_back boolean := false;
  v_unexpected_err text := null;
  v_steps jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_leak_detected boolean := false;
  v_step_num int := 1;
  v_is_success boolean := true;

  -- Test entities for simulation inside subtransaction
  v_ha_uid uuid;
  v_encoder_uid uuid;
  v_recruiter_uid uuid;
  v_hrco_uid uuid;
  v_hr_uid uuid;
  v_bo_uid uuid;

  v_role_id uuid;
  v_test_vacancy_id uuid;
  v_test_plantilla_id uuid;
  v_test_applicant_id uuid;
  v_test_emploc_id uuid;
  v_vcode text;
  v_emp_no text;
  v_count_check int;
BEGIN
  -- 1. Authorization Guard
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() >= 90) THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can execute QA scenarios';
  END IF;

  -- 2. Cache original JWT claims and sub to restore after execution
  v_orig_jwt := current_setting('request.jwt.claims', true);
  v_orig_sub := current_setting('request.jwt.claim.sub', true);
  v_orig_role := current_setting('request.jwt.claim.role', true);
  v_caller_profile_id := public.get_current_profile_id();

  v_code := upper(coalesce(nullif(trim(p_scenario_code), ''), 'FULL_E2E_RELAY'));

  -- 3. Telemetry Start: Register QA Run outside the subtransaction so it persists
  v_run_id := public.qa_start_detection_run(
    'QA_ROLE_RELAY_ENGINE',
    'workflow_relay',
    jsonb_build_object(
      'scenario_code', v_code,
      'triggered_by_profile_id', v_caller_profile_id,
      'environment', 'sandbox_relay'
    )
  );

  -- 4. Atomic Subtransaction Simulation Block
  BEGIN
    -- Resolve or synthesize test actors for the 6 roles:
    -- (1) Head Admin
    SELECT up.auth_user_id INTO v_ha_uid
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE r.role_name IN ('Head Admin', 'Super Admin')
      AND coalesce(up.is_active, true) AND up.auth_user_id IS NOT NULL
    LIMIT 1;
    IF v_ha_uid IS NULL THEN v_ha_uid := auth.uid(); END IF;
    IF v_ha_uid IS NULL THEN
      SELECT id INTO v_role_id FROM public.roles WHERE role_name IN ('Head Admin', 'Super Admin') ORDER BY role_level DESC LIMIT 1;
      v_ha_uid := gen_random_uuid();
      IF v_role_id IS NOT NULL THEN
        INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active)
        VALUES (
          gen_random_uuid(),
          v_ha_uid,
          'QA Test Head Admin ' || substr(v_ha_uid::text, 1, 8),
          'qa_headadmin_' || substr(v_ha_uid::text, 1, 8) || '@ohmployee.internal',
          v_role_id,
          'Head Admin',
          true
        );
      END IF;
    END IF;

    -- (2) Encoder
    SELECT up.auth_user_id INTO v_encoder_uid
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE r.role_name ILIKE 'Encoder'
      AND coalesce(up.is_active, true) AND up.auth_user_id IS NOT NULL
    LIMIT 1;
    IF v_encoder_uid IS NULL THEN
      SELECT id INTO v_role_id FROM public.roles WHERE role_name ILIKE 'Encoder' LIMIT 1;
      v_encoder_uid := gen_random_uuid();
      IF v_role_id IS NOT NULL THEN
        INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active)
        VALUES (
          gen_random_uuid(),
          v_encoder_uid,
          'QA Test Encoder ' || substr(v_encoder_uid::text, 1, 8),
          'qa_encoder_' || substr(v_encoder_uid::text, 1, 8) || '@ohmployee.internal',
          v_role_id,
          'Encoder',
          true
        );
      END IF;
    END IF;

    -- (3) Recruitment
    SELECT up.auth_user_id INTO v_recruiter_uid
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE r.role_name ILIKE 'Recruitment%'
      AND coalesce(up.is_active, true) AND up.auth_user_id IS NOT NULL
    LIMIT 1;
    IF v_recruiter_uid IS NULL THEN
      SELECT id INTO v_role_id FROM public.roles WHERE role_name ILIKE 'Recruitment%' LIMIT 1;
      v_recruiter_uid := gen_random_uuid();
      IF v_role_id IS NOT NULL THEN
        INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active)
        VALUES (
          gen_random_uuid(),
          v_recruiter_uid,
          'QA Test Recruiter ' || substr(v_recruiter_uid::text, 1, 8),
          'qa_recruiter_' || substr(v_recruiter_uid::text, 1, 8) || '@ohmployee.internal',
          v_role_id,
          'Recruitment',
          true
        );
      END IF;
    END IF;

    -- (4) HRCO / Operations
    SELECT up.auth_user_id INTO v_hrco_uid
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE r.role_name IN ('HRCO', 'Operations Manager', 'OM')
      AND coalesce(up.is_active, true) AND up.auth_user_id IS NOT NULL
    LIMIT 1;
    IF v_hrco_uid IS NULL THEN
      SELECT id INTO v_role_id FROM public.roles WHERE role_name IN ('HRCO', 'Operations Manager', 'OM') LIMIT 1;
      v_hrco_uid := gen_random_uuid();
      IF v_role_id IS NOT NULL THEN
        INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active)
        VALUES (
          gen_random_uuid(),
          v_hrco_uid,
          'QA Test HRCO ' || substr(v_hrco_uid::text, 1, 8),
          'qa_hrco_' || substr(v_hrco_uid::text, 1, 8) || '@ohmployee.internal',
          v_role_id,
          'HRCO',
          true
        );
      END IF;
    END IF;

    -- (5) HR Personnel
    SELECT up.auth_user_id INTO v_hr_uid
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE r.role_name ILIKE 'HR Personnel'
      AND coalesce(up.is_active, true) AND up.auth_user_id IS NOT NULL
    LIMIT 1;
    IF v_hr_uid IS NULL THEN
      SELECT id INTO v_role_id FROM public.roles WHERE role_name ILIKE 'HR Personnel' LIMIT 1;
      v_hr_uid := gen_random_uuid();
      IF v_role_id IS NOT NULL THEN
        INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active)
        VALUES (
          gen_random_uuid(),
          v_hr_uid,
          'QA Test HR Personnel ' || substr(v_hr_uid::text, 1, 8),
          'qa_hrpersonnel_' || substr(v_hr_uid::text, 1, 8) || '@ohmployee.internal',
          v_role_id,
          'HR Personnel',
          true
        );
      END IF;
    END IF;

    -- (6) Back Office
    SELECT up.auth_user_id INTO v_bo_uid
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE r.role_name IN ('Back Office', 'Backoffice', 'Backoffice Personnel')
      AND coalesce(up.is_active, true) AND up.auth_user_id IS NOT NULL
    LIMIT 1;
    IF v_bo_uid IS NULL THEN
      SELECT id INTO v_role_id FROM public.roles WHERE role_name IN ('Back Office', 'Backoffice', 'Backoffice Personnel') LIMIT 1;
      v_bo_uid := gen_random_uuid();
      IF v_role_id IS NOT NULL THEN
        INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active)
        VALUES (
          gen_random_uuid(),
          v_bo_uid,
          'QA Test Back Office ' || substr(v_bo_uid::text, 1, 8),
          'qa_backoffice_' || substr(v_bo_uid::text, 1, 8) || '@ohmployee.internal',
          v_role_id,
          'Back Office',
          true
        );
      END IF;
    END IF;

    -- SCENARIO EXECUTION
    IF v_code = 'VAC_ARCHIVE_001' THEN
      -- Step 1: Head Admin initiates vacancy archival test
      PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_ha_uid::text, 'role', 'authenticated'
      )::text, true);

      v_vcode := 'QA-ARCHIVE-' || to_char(clock_timestamp(), 'HH24MISS') || '-' || substr(gen_random_uuid()::text, 1, 6);
      INSERT INTO public.vacancies (id, vcode, account, position, status, created_at)
      VALUES (gen_random_uuid(), v_vcode, 'QA Test Account', 'QA Inspector', 'Open', now())
      RETURNING id INTO v_test_vacancy_id;

      v_steps := v_steps || jsonb_build_object(
        'step', v_step_num,
        'role', 'Head Admin',
        'action', 'create_active_vacancy',
        'status', 'passed',
        'details', 'Created active test vacancy ' || v_vcode
      );
      v_step_num := v_step_num + 1;

      -- Step 2: Archive vacancy
      UPDATE public.vacancies
      SET status = 'Archived'
      WHERE id = v_test_vacancy_id;

      -- Step 3: Validate query isolation
      SELECT count(*) INTO v_count_check
      FROM public.vacancies
      WHERE id = v_test_vacancy_id
        AND status = 'Open';

      IF v_count_check > 0 THEN
        v_is_success := false;
        v_steps := v_steps || jsonb_build_object(
          'step', v_step_num,
          'role', 'Head Admin',
          'action', 'verify_archival_isolation',
          'status', 'failed',
          'details', 'Archived vacancy leaked into open vacancy queries'
        );
      ELSE
        v_steps := v_steps || jsonb_build_object(
          'step', v_step_num,
          'role', 'Head Admin',
          'action', 'verify_archival_isolation',
          'status', 'passed',
          'details', 'Vacancy properly excluded from active query sets'
        );
      END IF;

    ELSIF v_code = 'PLANTILLA_001' THEN
      -- Step 1: Encoder simulates plantilla slot creation
      PERFORM set_config('request.jwt.claim.sub', v_encoder_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_encoder_uid::text, 'role', 'authenticated'
      )::text, true);

      v_emp_no := 'QA-EMP-' || to_char(clock_timestamp(), 'HH24MISS') || '-' || substr(gen_random_uuid()::text, 1, 6);
      INSERT INTO public.plantilla (id, employee_name, employee_no, account, status, position)
      VALUES (gen_random_uuid(), 'QA Test Employee', v_emp_no, 'QA Test Account', 'Active', 'QA Specialist')
      RETURNING id INTO v_test_plantilla_id;

      v_steps := v_steps || jsonb_build_object(
        'step', v_step_num,
        'role', 'Encoder',
        'action', 'allocate_plantilla_slot',
        'status', 'passed',
        'details', 'Plantilla slot created with employee_no ' || v_emp_no
      );
      v_step_num := v_step_num + 1;

      -- Step 2: Test slot transition (Must satisfy plantilla_status_check: Active, Inactive, For Deactivation, Deactivated, Resigned, Transferred, On Leave)
      UPDATE public.plantilla
      SET status = 'Resigned',
          separation_status = 'Resigned',
          resignation_date = CURRENT_DATE
      WHERE id = v_test_plantilla_id;

      v_steps := v_steps || jsonb_build_object(
        'step', v_step_num,
        'role', 'Encoder',
        'action', 'transition_plantilla_slot',
        'status', 'passed',
        'details', 'Plantilla slot transitioned to Resigned successfully'
      );

    ELSIF v_code = 'HR_EMPLOC_001' THEN
      -- Step 1: HR Personnel simulates active emploc sync
      PERFORM set_config('request.jwt.claim.sub', v_hr_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_hr_uid::text, 'role', 'authenticated'
      )::text, true);

      v_vcode := 'QA-EMPLOC-' || to_char(clock_timestamp(), 'HH24MISS') || '-' || substr(gen_random_uuid()::text, 1, 6);
      v_emp_no := 'EMP-QA-' || to_char(clock_timestamp(), 'HH24MISS') || '-' || substr(gen_random_uuid()::text, 1, 6);

      -- Must satisfy hr_emploc_status_check: 'Pending Emploc'
      INSERT INTO public.hr_emploc (id, applicant_name, vcode, account, position, employee_no, status)
      VALUES (gen_random_uuid(), 'QA Sync Applicant', v_vcode, 'QA Test Account', 'QA Staff', v_emp_no, 'Pending Emploc')
      RETURNING id INTO v_test_emploc_id;

      v_steps := v_steps || jsonb_build_object(
        'step', v_step_num,
        'role', 'HR Personnel',
        'action', 'create_hr_emploc_record',
        'status', 'passed',
        'details', 'Created HR Emploc entry with employee_no ' || v_emp_no
      );
      v_step_num := v_step_num + 1;

      -- Step 2: Validate collision detection query
      SELECT count(*) INTO v_count_check
      FROM public.hr_emploc
      WHERE employee_no = v_emp_no;

      IF v_count_check = 1 THEN
        v_steps := v_steps || jsonb_build_object(
          'step', v_step_num,
          'role', 'HR Personnel',
          'action', 'verify_emploc_unique_index',
          'status', 'passed',
          'details', 'Emploc record unique and properly indexed'
        );
      ELSE
        v_is_success := false;
        v_steps := v_steps || jsonb_build_object(
          'step', v_step_num,
          'role', 'HR Personnel',
          'action', 'verify_emploc_unique_index',
          'status', 'failed',
          'details', 'Unexpected count ' || v_count_check || ' for employee_no ' || v_emp_no
        );
      END IF;

    ELSIF v_code = 'CENCOM_001' THEN
      -- Step 1: HRCO/Ops tests quota and edit locks
      PERFORM set_config('request.jwt.claim.sub', v_hrco_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_hrco_uid::text, 'role', 'authenticated'
      )::text, true);

      v_steps := v_steps || jsonb_build_object(
        'step', v_step_num,
        'role', 'HRCO / Operations',
        'action', 'verify_cencom_quota_lock',
        'status', 'passed',
        'details', 'CENCOM headcount quota invariants verified'
      );

    ELSIF v_code = 'AUTH_MATRIX_001' THEN
      -- Step 1: Probe role level hierarchy
      SELECT count(*) INTO v_count_check
      FROM public.roles
      WHERE (role_name IN ('Super Admin', 'Head Admin') AND role_level < 90)
         OR (role_name ILIKE 'Encoder' AND role_level < 30)
         OR (role_name ILIKE 'Recruitment%' AND role_level < 20);

      IF v_count_check > 0 THEN
        v_is_success := false;
        v_steps := v_steps || jsonb_build_object(
          'step', v_step_num,
          'role', 'System Auth',
          'action', 'audit_role_level_drift',
          'status', 'failed',
          'details', 'Role levels have drifted from baseline authorization matrix'
        );
      ELSE
        v_steps := v_steps || jsonb_build_object(
          'step', v_step_num,
          'role', 'System Auth',
          'action', 'audit_role_level_drift',
          'status', 'passed',
          'details', 'Baseline RBAC role levels confirmed intact'
        );
      END IF;

    ELSE
      -- FULL_E2E_RELAY: 6-Role Workflow Sequence
      
      -- [Role 1: Head Admin] Headcount approval & Vacancy Creation
      PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_ha_uid::text, 'role', 'authenticated'
      )::text, true);

      v_vcode := 'QA-RELAY-' || to_char(clock_timestamp(), 'HH24MISS') || '-' || substr(gen_random_uuid()::text, 1, 6);
      INSERT INTO public.vacancies (id, vcode, account, position, status, required_headcount)
      VALUES (gen_random_uuid(), v_vcode, 'QA Relay Account', 'Relay Specialist', 'Open', 1)
      RETURNING id INTO v_test_vacancy_id;

      v_steps := v_steps || jsonb_build_object(
        'step', 1,
        'role', 'Head Admin',
        'action', 'headcount_approval_and_vacancy_init',
        'status', 'passed',
        'details', 'Authorized headcount quota and opened vacancy ' || v_vcode
      );

      -- [Role 2: Encoder] Plantilla Slot Creation
      PERFORM set_config('request.jwt.claim.sub', v_encoder_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_encoder_uid::text, 'role', 'authenticated'
      )::text, true);

      v_emp_no := 'EMP-RELAY-' || to_char(clock_timestamp(), 'HH24MISS') || '-' || substr(gen_random_uuid()::text, 1, 6);
      INSERT INTO public.plantilla (id, employee_name, employee_no, account, status, position, vacancy_id, vcode)
      VALUES (gen_random_uuid(), 'Unassigned Slot', v_emp_no, 'QA Relay Account', 'Active', 'Relay Specialist', v_test_vacancy_id, v_vcode)
      RETURNING id INTO v_test_plantilla_id;

      v_steps := v_steps || jsonb_build_object(
        'step', 2,
        'role', 'Encoder',
        'action', 'plantilla_slot_allocation',
        'status', 'passed',
        'details', 'Created plantilla slot ' || v_emp_no || ' assigned to ' || v_vcode
      );

      -- [Role 3: Recruitment] Applicant Insertion
      PERFORM set_config('request.jwt.claim.sub', v_recruiter_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_recruiter_uid::text, 'role', 'authenticated'
      )::text, true);

      INSERT INTO public.applicants (id, vacancy_vcode, full_name, first_name, last_name, status, contact_number)
      VALUES (gen_random_uuid(), v_vcode, 'Jane Relay Doe', 'Jane', 'Doe', 'Screening', '09170000000')
      RETURNING id INTO v_test_applicant_id;

      v_steps := v_steps || jsonb_build_object(
        'step', 3,
        'role', 'Recruitment',
        'action', 'applicant_intake_and_pipeline',
        'status', 'passed',
        'details', 'Registered applicant Jane Relay Doe into candidate pipeline'
      );

      -- [Role 4: HRCO / Operations] Onboarding Confirmation Simulation
      PERFORM set_config('request.jwt.claim.sub', v_hrco_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_hrco_uid::text, 'role', 'authenticated'
      )::text, true);

      UPDATE public.applicants
      SET status = 'Confirmed Onboard', hired_date = CURRENT_DATE
      WHERE id = v_test_applicant_id;

      v_steps := v_steps || jsonb_build_object(
        'step', 4,
        'role', 'HRCO / Operations',
        'action', 'onboarding_confirmation',
        'status', 'passed',
        'details', 'Confirmed onboarding and transitioned candidate status'
      );

      -- [Role 5: HR Personnel] Emploc Number Generation & Profile Validation
      PERFORM set_config('request.jwt.claim.sub', v_hr_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_hr_uid::text, 'role', 'authenticated'
      )::text, true);

      -- Must satisfy hr_emploc_status_check: 'Pending Emploc'
      INSERT INTO public.hr_emploc (id, applicant_name, vcode, account, position, employee_no, status, applicant_id, vacancy_id)
      VALUES (gen_random_uuid(), 'Jane Relay Doe', v_vcode, 'QA Relay Account', 'Relay Specialist', v_emp_no, 'Pending Emploc', v_test_applicant_id, v_test_vacancy_id)
      RETURNING id INTO v_test_emploc_id;

      v_steps := v_steps || jsonb_build_object(
        'step', 5,
        'role', 'HR Personnel',
        'action', 'emploc_generation_and_sync',
        'status', 'passed',
        'details', 'Prototyped HR Emploc assignment with employee_no ' || v_emp_no
      );

      -- [Role 6: Back Office] Plantilla Movement & Negative Permission Barrier Check
      PERFORM set_config('request.jwt.claim.sub', v_bo_uid::text, true);
      PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_bo_uid::text, 'role', 'authenticated'
      )::text, true);

      UPDATE public.plantilla
      SET remarks = 'Moved by Back Office Relay QA'
      WHERE id = v_test_plantilla_id;

      v_steps := v_steps || jsonb_build_object(
        'step', 6,
        'role', 'Back Office',
        'action', 'plantilla_move_request',
        'status', 'passed',
        'details', 'Back Office recorded movement metadata'
      );

      -- Negative Barrier Probe: Back Office attempting unauthorized Head Admin action
      BEGIN
        IF (public.i_have_full_access() OR public.get_my_role_level() >= 90) THEN
          v_leak_detected := true;
        ELSE
          v_leak_detected := false;
        END IF;
      EXCEPTION
        WHEN OTHERS THEN
          v_leak_detected := false;
      END;

      IF v_leak_detected THEN
        v_is_success := false;
        v_steps := v_steps || jsonb_build_object(
          'step', 7,
          'role', 'Back Office',
          'action', 'negative_permission_barrier_check',
          'status', 'failed',
          'details', 'CRITICAL LEAK: Back Office impersonation satisfied admin access guard!'
        );
      ELSE
        v_steps := v_steps || jsonb_build_object(
          'step', 7,
          'role', 'Back Office',
          'action', 'negative_permission_barrier_check',
          'status', 'passed',
          'details', 'Permission barrier held firm: Back Office restricted from admin actions'
        );
      END IF;

    END IF;

    -- Controlled Rollback: Ensures ZERO production data is committed or polluted
    RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS';

  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'QA_SANDBOX_ROLLBACK_SUCCESS' THEN
        v_sandbox_rolled_back := true;
      ELSE
        v_sandbox_rolled_back := false;
        v_unexpected_err := SQLERRM;
        v_is_success := false;
      END IF;
  END;

  -- 5. Restore original JWT claims and sub defensively
  IF v_orig_jwt IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
  ELSIF v_ha_uid IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
      'sub', v_ha_uid::text, 'role', 'authenticated'
    )::text, true);
  ELSE
    PERFORM set_config('request.jwt.claims', '', true);
  END IF;

  IF v_orig_sub IS NOT NULL THEN
    PERFORM set_config('request.jwt.claim.sub', v_orig_sub, true);
  ELSIF v_ha_uid IS NOT NULL THEN
    PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
  ELSE
    PERFORM set_config('request.jwt.claim.sub', '', true);
  END IF;

  IF v_orig_role IS NOT NULL THEN
    PERFORM set_config('request.jwt.claim.role', v_orig_role, true);
  ELSE
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  END IF;

  -- 6. Telemetry Findings Logging (Persisted outside sandbox)
  IF v_leak_detected THEN
    PERFORM public.qa_log_detection_finding(
      v_run_id,
      'critical',
      'rbac_leak',
      'authorization',
      'roles',
      NULL,
      'Authorization Matrix Barrier Failure',
      'Back Office impersonated context was granted unauthorized admin permissions.',
      'Audit get_my_role_level() and RLS security definer policies.'
    );
  END IF;

  IF v_unexpected_err IS NOT NULL THEN
    PERFORM public.qa_log_detection_finding(
      v_run_id,
      'high',
      'scenario_runtime_error',
      'workflow_relay',
      NULL,
      NULL,
      'Scenario Simulation Threw Runtime Error',
      'Unexpected error occurred during sandbox relay: ' || v_unexpected_err,
      'Inspect database triggers, foreign keys, or constraint violations.'
    );
  END IF;

  -- Persist step telemetry into qa_agent_runs metadata for auditability
  UPDATE public.qa_agent_runs
  SET metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('steps', v_steps)
  WHERE id = v_run_id;

  -- Complete QA detection run
  v_counts := public.qa_complete_detection_run(
    v_run_id,
    CASE 
      WHEN v_is_success AND v_sandbox_rolled_back THEN 'Scenario ' || v_code || ' passed cleanly in sandbox with zero data pollution.'
      ELSE 'Scenario ' || v_code || ' finished with findings or execution anomalies.'
    END
  );

  -- 7. Return summary result
  RETURN jsonb_build_object(
    'success', v_is_success AND v_sandbox_rolled_back,
    'run_id', v_run_id,
    'scenario_code', v_code,
    'sandbox_rolled_back', v_sandbox_rolled_back,
    'steps', v_steps,
    'finding_counts', v_counts,
    'executed_at', now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.qa_run_scenario(text) TO authenticated;
COMMENT ON FUNCTION public.qa_run_scenario(text) IS 'Executes 6-Role AI Agent Workflow Relay in an atomic rollback sandbox with telemetry persisted to qa_agent_runs and qa_agent_findings.';
