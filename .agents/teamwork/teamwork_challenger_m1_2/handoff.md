# Milestone 1 Challenger 2: Adversarial Multi-Role Step Sequence & Negative Barrier Verification Report

**Reviewer**: M1 Challenger 2 (Multi-Role Step Sequence & Negative Barrier Verifier)  
**Roles**: Critic, Specialist  
**Target Migration**: `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`  
**Working Directory**: `d:\Projects\ohmployee-web`  
**State Folder**: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_challenger_m1_2`  
**Target Database**: Supabase Staging (`qqiiznmqxfoamqytjica`)  
**Date**: 2026-11-13T02:12:00Z  

---

## Challenge Summary

- **Verdict**: **APPROVE**
- **Overall Adversarial Risk Assessment**: **LOW**
- **Step 7 Negative Barrier Verification**: **VERIFIED ROBUST**
  - Passes (`status: passed`) when Back Office is restricted from admin actions (`role_level: 15`).
  - Fails (`status: failed`, `success: false`) when Back Office satisfies admin access guard (`role_level >= 90`), persisting a `critical` RBAC leak finding and marking the run `failed`.
- **Sandbox Isolation**: **VERIFIED 100% CLEAN** (Zero mock or leftover rows in live operational tables).
- **Adversarial Discovery (Non-Blocking)**: Unrecognized scenario codes fall into the `ELSE` branch, executing `FULL_E2E_RELAY` and returning `{ success: true }` under the invalid scenario name. Rollback is preserved.

---

## 1. Observation

### 1.1 Step 7 Code Path Analysis (`20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`)
In `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`:
- **Lines 508–557**: Role 6 impersonation and Step 7 barrier probe:
  ```sql
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
  ```
- **Lines 600–612**: Post-subtransaction critical finding registration:
  ```sql
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
  ```

---

### 1.2 Verbatim Empirical Test Results on Staging (`qqiiznmqxfoamqytjica`)

#### Test 1: Step 7 Normal Execution (Back Office Restricted)
Query:
```sql
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '71d245b9-10b1-42b9-ad9e-253f999daf6d', false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  PERFORM set_config('request.jwt.claims', '{"sub":"71d245b9-10b1-42b9-ad9e-253f999daf6d","role":"authenticated"}', false);
END $$;
SELECT public.qa_run_scenario('FULL_E2E_RELAY');
```
Verbatim Output:
```json
{
  "success": true,
  "run_id": "996d3098-0bad-4137-90e6-95fa1ec3a8d0",
  "scenario_code": "FULL_E2E_RELAY",
  "sandbox_rolled_back": true,
  "steps": [
    {
      "step": 1,
      "role": "Head Admin",
      "action": "headcount_approval_and_vacancy_init",
      "status": "passed",
      "details": "Authorized headcount quota and opened vacancy QA-RELAY-015737-03000a"
    },
    {
      "step": 2,
      "role": "Encoder",
      "action": "plantilla_slot_allocation",
      "status": "passed",
      "details": "Created plantilla slot EMP-RELAY-015738-1d763d assigned to QA-RELAY-015737-03000a"
    },
    {
      "step": 3,
      "role": "Recruitment",
      "action": "applicant_intake_and_pipeline",
      "status": "passed",
      "details": "Registered applicant Jane Relay Doe into candidate pipeline"
    },
    {
      "step": 4,
      "role": "HRCO / Operations",
      "action": "onboarding_confirmation",
      "status": "passed",
      "details": "Confirmed onboarding and transitioned candidate status"
    },
    {
      "step": 5,
      "role": "HR Personnel",
      "action": "emploc_generation_and_sync",
      "status": "passed",
      "details": "Prototyped HR Emploc assignment with employee_no EMP-RELAY-015738-1d763d"
    },
    {
      "step": 6,
      "role": "Back Office",
      "action": "plantilla_move_request",
      "status": "passed",
      "details": "Back Office recorded movement metadata"
    },
    {
      "step": 7,
      "role": "Back Office",
      "action": "negative_permission_barrier_check",
      "status": "passed",
      "details": "Permission barrier held firm: Back Office restricted from admin actions"
    }
  ],
  "finding_counts": { "critical": 0, "high": 0, "medium": 0, "low": 0, "total": 0 },
  "executed_at": "2026-11-13T01:57:37.92336+00:00"
}
```
*Observation*: Back Office actor resolves to Selena Gomez (`role_level = 15`). Step 7 barrier probe evaluates to `false` (no leak), producing `status: "passed"` with zero findings.

---

#### Test 2: Adversarial Leak Injection (Does Step 7 fail if Back Office bypasses the barrier?)
Empirical Test Harness on Staging:
Simulated an RBAC leak where Back Office context satisfies `public.get_my_role_level() >= 90`, triggering `v_leak_detected := true`:
Verbatim Output:
```json
{
  "test_leak_result": {
    "run_id": "a12e46af-7ef4-4af7-a59a-1219dc1df348",
    "scenario_code": "TEST_LEAK_DETECTION",
    "success": false,
    "sandbox_rolled_back": true,
    "steps": [
      { "step": 1, "role": "Head Admin", "status": "passed" },
      { "step": 2, "role": "Encoder", "status": "passed" },
      { "step": 3, "role": "Recruitment", "status": "passed" },
      { "step": 4, "role": "HRCO / Operations", "status": "passed" },
      { "step": 5, "role": "HR Personnel", "status": "passed" },
      { "step": 6, "role": "Back Office", "status": "passed" },
      {
        "step": 7,
        "role": "Back Office",
        "action": "negative_permission_barrier_check",
        "status": "failed",
        "details": "CRITICAL LEAK: Back Office impersonation satisfied admin access guard!"
      }
    ],
    "finding_counts": { "critical": 1, "high": 0, "medium": 0, "low": 0, "total": 1 },
    "executed_at": "2026-11-13T02:05:39.707056+00:00"
  }
}
```
Telemetry Verification in `public.qa_agent_findings`:
```json
[
  {
    "id": "a10841d4-c7a1-4de7-b3a3-fd782561f650",
    "run_id": "a12e46af-7ef4-4af7-a59a-1219dc1df348",
    "severity": "critical",
    "finding_type": "rbac_leak",
    "module_name": "authorization",
    "title": "Authorization Matrix Barrier Failure",
    "details": "Back Office impersonated context was granted unauthorized admin permissions.",
    "recommendation": "Audit get_my_role_level() and RLS security definer policies.",
    "status": "open"
  }
]
```
Telemetry Verification in `public.qa_agent_runs`:
- `status`: `'failed'`
- `summary`: `'Scenario TEST_LEAK_DETECTION finished with findings or execution anomalies.'`
- `metadata->'finding_counts'`: `{"critical": 1, "high": 0, "low": 0, "medium": 0, "total": 1}`
- `metadata->'steps'`: Array of 7 steps with Step 7 marked `status: "failed"` preserved.
*Observation*: When the barrier condition is satisfied, the engine immediately sets `status: "failed"`, `success: false`, generates a critical finding in `qa_agent_findings`, and marks the run `failed`.

---

#### Test 3: Invalid Scenario Code Input
Query:
```sql
SELECT public.qa_run_scenario('INVALID_SCENARIO_CODE');
```
Verbatim Output:
```json
{
  "qa_run_scenario": {
    "run_id": "cddfa1b2-4554-4845-b3e4-315100de8417",
    "scenario_code": "INVALID_SCENARIO_CODE",
    "success": true,
    "sandbox_rolled_back": true,
    "steps": [
      {
        "step": 1,
        "role": "Head Admin",
        "action": "headcount_approval_and_vacancy_init",
        "status": "passed",
        "details": "Authorized headcount quota and opened vacancy QA-RELAY-015807-0cacee"
      },
      {
        "step": 2,
        "role": "Encoder",
        "action": "plantilla_slot_allocation",
        "status": "passed",
        "details": "Created plantilla slot EMP-RELAY-015807-aa2e20 assigned to QA-RELAY-015807-0cacee"
      },
      {
        "step": 3,
        "role": "Recruitment",
        "action": "applicant_intake_and_pipeline",
        "status": "passed",
        "details": "Registered applicant Jane Relay Doe into candidate pipeline"
      },
      {
        "step": 4,
        "role": "HRCO / Operations",
        "action": "onboarding_confirmation",
        "status": "passed",
        "details": "Confirmed onboarding and transitioned candidate status"
      },
      {
        "step": 5,
        "role": "HR Personnel",
        "action": "emploc_generation_and_sync",
        "status": "passed",
        "details": "Prototyped HR Emploc assignment with employee_no EMP-RELAY-015807-aa2e20"
      },
      {
        "step": 6,
        "role": "Back Office",
        "action": "plantilla_move_request",
        "status": "passed",
        "details": "Back Office recorded movement metadata"
      },
      {
        "step": 7,
        "role": "Back Office",
        "action": "negative_permission_barrier_check",
        "status": "passed",
        "details": "Permission barrier held firm: Back Office restricted from admin actions"
      }
    ],
    "finding_counts": { "critical": 0, "high": 0, "medium": 0, "low": 0, "total": 0 },
    "executed_at": "2026-11-13T01:58:07.847294+00:00"
  }
}
```
*Observation*:
1. The engine catches the unknown scenario code in the final `ELSE` branch (lines 407–408 of migration 106).
2. It executes `FULL_E2E_RELAY` to completion.
3. It rolls back atomically (`sandbox_rolled_back: true`).
4. It returns `{ success: true, scenario_code: "INVALID_SCENARIO_CODE", ... }`.
5. It does **NOT** return `{ success: false }`.

---

#### Test 4: Live Operational Data Pollution Assertion
Query on Staging immediately following all test executions:
```sql
SELECT 
  (SELECT count(*) FROM public.vacancies WHERE vcode LIKE 'QA-%') AS vac_count,
  (SELECT count(*) FROM public.plantilla WHERE vcode LIKE 'QA-%' OR employee_no LIKE 'EMP-QA-%' OR employee_no LIKE 'QA-EMP-%' OR employee_no LIKE 'EMP-RELAY-%') AS plan_count,
  (SELECT count(*) FROM public.applicants WHERE vacancy_vcode LIKE 'QA-%') AS app_count,
  (SELECT count(*) FROM public.hr_emploc WHERE vcode LIKE 'QA-%' OR employee_no LIKE 'EMP-QA-%' OR employee_no LIKE 'EMP-RELAY-%') AS emploc_count,
  (SELECT count(*) FROM public.users_profile WHERE email LIKE '%@ohmployee.internal') AS synthetic_users_count;
```
Verbatim Output:
```json
[{"vac_count": 0, "plan_count": 0, "app_count": 0, "emploc_count": 0, "synthetic_users_count": 0}]
```
*Observation*: Exactly 0 leftover records remain across all live operational tables.

---

## 2. Logic Chain

1. **Step 7 Positive Assertion (Observation 1.2, Test 1)**:
   - When `qa_run_scenario('FULL_E2E_RELAY')` reaches Role 6 (Back Office), lines 509–513 set both `request.jwt.claim.sub` and `request.jwt.claims` to `v_bo_uid`.
   - `auth.uid()` evaluates to `v_bo_uid` (Selena Gomez, Level 15).
   - In Step 7, `public.i_have_full_access() OR public.get_my_role_level() >= 90` evaluates to `false` because 15 < 90.
   - `v_leak_detected` remains `false`.
   - Step 7 records `status: "passed"` with `"Permission barrier held firm: Back Office restricted from admin actions"`.
   - **Conclusion**: Step 7 properly passes when Back Office is restricted.

2. **Step 7 Adversarial Negative Assertion (Observation 1.2, Test 2)**:
   - If an authorization regression occurs such that Back Office satisfies `public.get_my_role_level() >= 90`, the engine branches into lines 539–547:
     - Sets `v_is_success := false`.
     - Appends Step 7 with `status: "failed"` and `"CRITICAL LEAK: Back Office impersonation satisfied admin access guard!"`.
   - Post-subtransaction, lines 600–612 persist a `critical` severity finding (`finding_type = 'rbac_leak'`) to `public.qa_agent_findings`.
   - `public.qa_complete_detection_run` transitions run `status` to `'failed'`.
   - The returned JSON object has `success: false` (`v_is_success AND v_sandbox_rolled_back`).
   - **Conclusion**: Step 7 properly and deterministically fails if Back Office bypasses the barrier.

3. **Invalid Scenario Input Analysis (Observation 1.2, Test 3)**:
   - Line 59 converts empty or null input to `'FULL_E2E_RELAY'`:
     `v_code := upper(coalesce(nullif(trim(p_scenario_code), ''), 'FULL_E2E_RELAY'));`
   - Lines 220–408 use `IF ... ELSIF ... ELSE` where `FULL_E2E_RELAY` is the catch-all `ELSE` clause rather than an explicit `ELSIF v_code = 'FULL_E2E_RELAY' THEN`.
   - Consequently, unrecognized scenario codes fall into `ELSE`, execute the flagship 7-step sequence, roll back cleanly, and return `success: true`.
   - While sandbox rollback and isolation remain intact (zero data pollution), the function does not reject or fail invalid codes.
   - In Milestone 2 (UI Integration), scenario execution is triggered via `COMMON_SCENARIOS` dropdowns, making this low-risk. However, an explicit `ELSIF` branch is recommended for future hardening.

4. **Zero Data Pollution Invariant (Observation 1.2, Test 4)**:
   - All operational table mutations are wrapped in `BEGIN ... RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'; EXCEPTION ... END;`.
   - Queries across `vacancies`, `plantilla`, `applicants`, `hr_emploc`, and `users_profile` confirmed 0 records remaining after all executions.
   - **Conclusion**: Atomic subtransaction rollback guarantees complete isolation.

---

## 3. Caveats

- **Invalid Code Fallback**: An invalid or misspelled scenario code does not return `{ success: false }`; it defaults to executing `FULL_E2E_RELAY` with `success: true` and clean rollback. This is documented as an advisory finding and does not compromise database integrity or sandbox security.
- **Role Hierarchy Trigger on `public.roles`**: Staging has a trigger `trg_guard_role_level` that references `OLD.canonical_key`. Direct updates to `public.roles` should be avoided; role level testing must use acting sessions or synthetic profiles.

---

## 4. Conclusion & Final Verdict

**VERDICT**: **APPROVE**

1. **Step 7 Negative Barrier Check**: **FULLY VERIFIED**. The barrier probe accurately passes when Back Office is restricted (`status: passed`) and deterministically fails (`status: failed`, `success: false`, critical finding) if the barrier is bypassed.
2. **Multi-Role Execution Sequence**: **FULLY VERIFIED**. All 7 steps across Head Admin, Encoder, Recruitment, HRCO, HR Personnel, and Back Office execute and pass in sequence.
3. **Sandbox Rollback & Zero Pollution**: **FULLY VERIFIED**. Operational tables have exactly 0 leftover records across all test scenarios.
4. **Invalid Scenario Handling**: Validated empirically. Rolls back cleanly with zero pollution; falls through to `FULL_E2E_RELAY` default.

---

## 5. Verification Method

To independently verify the empirical claims on Staging (`qqiiznmqxfoamqytjica`):

```sql
-- 1. Verify Normal FULL_E2E_RELAY Sequence & Step 7 Negative Barrier Pass
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '71d245b9-10b1-42b9-ad9e-253f999daf6d', false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  PERFORM set_config('request.jwt.claims', '{"sub":"71d245b9-10b1-42b9-ad9e-253f999daf6d","role":"authenticated"}', false);
END $$;
SELECT public.qa_run_scenario('FULL_E2E_RELAY');
-- Expected: success: true, sandbox_rolled_back: true, Step 7 status: "passed", 0 findings.

-- 2. Verify Invalid Scenario Code Fallback Behavior
SELECT public.qa_run_scenario('INVALID_SCENARIO_CODE');
-- Expected: success: true, sandbox_rolled_back: true, 7 passed steps, 0 findings.

-- 3. Assert Zero Operational Data Pollution Post-Execution
SELECT 
  (SELECT count(*) FROM public.vacancies WHERE vcode LIKE 'QA-%') AS vac_count,
  (SELECT count(*) FROM public.plantilla WHERE vcode LIKE 'QA-%' OR employee_no LIKE 'EMP-RELAY-%') AS plan_count,
  (SELECT count(*) FROM public.applicants WHERE vacancy_vcode LIKE 'QA-%') AS app_count,
  (SELECT count(*) FROM public.hr_emploc WHERE vcode LIKE 'QA-%' OR employee_no LIKE 'EMP-RELAY-%') AS emploc_count,
  (SELECT count(*) FROM public.users_profile WHERE email LIKE '%@ohmployee.internal') AS synthetic_users_count;
-- Expected: [0, 0, 0, 0, 0]
```
