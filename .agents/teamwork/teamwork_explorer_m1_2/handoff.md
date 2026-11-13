# Milestone 1: Workflow Step Logic & Negative Barrier Verification Report
**Role**: M1 Explorer 2 — Workflow Step Logic & Negative Barrier Verification Specialist  
**State Folder**: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_2`  
**Date**: 2026-11-13T01:20:00Z  

---

## 1. Observation

### 1.1 Existing Implementation of `FULL_E2E_RELAY` in `public.qa_run_scenario`
File: `supabase/migrations/20262606000045_qa_role_relay_engine.sql`

#### Role Actor Resolution & Synthesis (Lines 67–156):
- **Role 1 (Head Admin)**:
  ```sql
  SELECT up.auth_user_id INTO v_ha_uid
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE r.role_name IN ('Head Admin', 'Super Admin')
    AND coalesce(up.is_active, true) AND up.auth_user_id IS NOT NULL
  LIMIT 1;
  IF v_ha_uid IS NULL THEN v_ha_uid := auth.uid(); END IF;
  ```
- **Roles 2–6 (Encoder, Recruitment, HRCO, HR Personnel, Back Office)**:
  Looked up from `users_profile` joining `roles` by name. If missing, each block synthesizes a mock actor inside the subtransaction using a static email, e.g. line 89:
  `'qa_encoder@ohmployee.internal'`, line 105: `'qa_recruiter@ohmployee.internal'`, line 121: `'qa_hrco@ohmployee.internal'`, line 137: `'qa_hrpersonnel@ohmployee.internal'`, line 153: `'qa_backoffice@ohmployee.internal'`.
  - **Constraint Conflict**: `public.users_profile` enforces unique constraints `users_profile_email_key` (`UNIQUE (email)`) and `users_profile_full_name_key` (`UNIQUE (full_name)`) (`20260520012857_remote_schema.sql:3319–3321`). Any persistent record or simultaneous session with these hardcoded emails causes `unique_violation`.

#### Step Sequence Execution (Lines 313–450):
- **Step 1 (Head Admin)**: `headcount_approval_and_vacancy_init` (lines 315–331)
  - Impersonation: `PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid::text, 'role', 'authenticated')::text, true);`
  - Action: Inserts into `public.vacancies`:
    ```sql
    v_vcode := 'QA-RELAY-' || to_char(now(), 'HH24MISS');
    INSERT INTO public.vacancies (id, vcode, account, position, status, required_headcount)
    VALUES (gen_random_uuid(), v_vcode, 'QA Relay Account', 'Relay Specialist', 'Open', 1)
    RETURNING id INTO v_test_vacancy_id;
    ```
  - Appends to `v_steps`: `step: 1, role: 'Head Admin', action: 'headcount_approval_and_vacancy_init', status: 'passed'`.
  - **Constraint Conflict**: `v_vcode` uses 1-second resolution `HH24MISS`. `public.vacancies` has `vacancies_vcode_key UNIQUE (vcode)`. Rapid consecutive executions cause `unique_violation`.
- **Step 2 (Encoder)**: `plantilla_slot_allocation` (lines 333–350)
  - Impersonation: `set_config('request.jwt.claims', ..., true)` with `v_encoder_uid`.
  - Action: Inserts into `public.plantilla`:
    ```sql
    v_emp_no := 'EMP-RELAY-' || to_char(now(), 'HH24MISS');
    INSERT INTO public.plantilla (id, employee_name, employee_no, account, status, position, vacancy_id, vcode)
    VALUES (gen_random_uuid(), 'Unassigned Slot', v_emp_no, 'QA Relay Account', 'Active', 'Relay Specialist', v_test_vacancy_id, v_vcode)
    RETURNING id INTO v_test_plantilla_id;
    ```
  - Appends to `v_steps`: `step: 2, role: 'Encoder', action: 'plantilla_slot_allocation', status: 'passed'`.
- **Step 3 (Recruitment)**: `applicant_intake_and_pipeline` (lines 351–366)
  - Impersonation: `set_config('request.jwt.claims', ..., true)` with `v_recruiter_uid`.
  - Action: Inserts into `public.applicants`:
    ```sql
    INSERT INTO public.applicants (id, vacancy_vcode, full_name, first_name, last_name, status, contact_number)
    VALUES (gen_random_uuid(), v_vcode, 'Jane Relay Doe', 'Jane', 'Doe', 'Screening', '09170000000')
    RETURNING id INTO v_test_applicant_id;
    ```
  - Appends to `v_steps`: `step: 3, role: 'Recruitment', action: 'applicant_intake_and_pipeline', status: 'passed'`.
  - Validates against `chk_applicants_contact_number_format` (`^09[0-9]{9}$`) and FK `fk_applicants_vacancy_vcode`.
- **Step 4 (HRCO / Operations)**: `onboarding_confirmation` (lines 368–383)
  - Impersonation: `set_config('request.jwt.claims', ..., true)` with `v_hrco_uid`.
  - Action: Updates `public.applicants`:
    ```sql
    UPDATE public.applicants
    SET status = 'Confirmed Onboard', hired_date = CURRENT_DATE
    WHERE id = v_test_applicant_id;
    ```
  - Appends to `v_steps`: `step: 4, role: 'HRCO / Operations', action: 'onboarding_confirmation', status: 'passed'`.
- **Step 5 (HR Personnel)**: `emploc_generation_and_sync` (lines 385–400)
  - Impersonation: `set_config('request.jwt.claims', ..., true)` with `v_hr_uid`.
  - Action: Inserts into `public.hr_emploc`:
    ```sql
    INSERT INTO public.hr_emploc (id, applicant_name, vcode, account, position, employee_no, status, applicant_id, vacancy_id)
    VALUES (gen_random_uuid(), 'Jane Relay Doe', v_vcode, 'QA Relay Account', 'Relay Specialist', v_emp_no, 'Active', v_test_applicant_id, v_test_vacancy_id)
    RETURNING id INTO v_test_emploc_id;
    ```
  - Appends to `v_steps`: `step: 5, role: 'HR Personnel', action: 'emploc_generation_and_sync', status: 'passed'`.
  - **FATAL RUNTIME ERROR**: `public.hr_emploc` enforces `hr_emploc_status_check` (`20260520012857_remote_schema.sql:2851`):
    `CHECK (status = ANY (ARRAY['Pending Emploc', 'Pending Requirements', 'For Compliance', 'Ready for Plantilla', 'Pending Approval', 'Moved to Plantilla', 'In Review', 'Complete', 'Ready for Deployment', 'Backout']))`.
    `'Active'` is NOT a valid status for `hr_emploc`. Step 5 crashes immediately with a check constraint error, aborting the subtransaction before Steps 6 and 7 can execute.
- **Step 6 (Back Office)**: `plantilla_move_request` (lines 402–418)
  - Impersonation: `set_config('request.jwt.claims', ..., true)` with `v_bo_uid`.
  - Action: Updates `public.plantilla`:
    ```sql
    UPDATE public.plantilla
    SET remarks = 'Moved by Back Office Relay QA'
    WHERE id = v_test_plantilla_id;
    ```
  - Appends to `v_steps`: `step: 6, role: 'Back Office', action: 'plantilla_move_request', status: 'passed'`.
- **Step 7 (Back Office)**: `negative_permission_barrier_check` (lines 419–449)
  - Evaluates:
    ```sql
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
    ```
  - Conditional branch:
    ```sql
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

---

### 1.2 Observation on Auth Impersonation & Negative Barrier Failure
1. **GUC Configuration Mechanism**:
   In `supabase/migrations/20262606000045_qa_role_relay_engine.sql`:
   - Line 49: `v_orig_jwt := current_setting('request.jwt.claims', true);` (caches only `request.jwt.claims`, omits `request.jwt.claim.sub`).
   - Lines 316, 334, 352, 369, 386, 403: Sets only `request.jwt.claims`. Never calls `set_config('request.jwt.claim.sub', ..., true)`.
2. **Supabase `auth.uid()` Resolution**:
   In standard Supabase/PostgREST runtime:
   `auth.uid()` evaluates:
   ```sql
   COALESCE(
     NULLIF(current_setting('request.jwt.claim.sub', true), ''),
     (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
   )::uuid
   ```
   PostgREST sets `request.jwt.claim.sub` when the caller makes an API request. Because `qa_run_scenario` never updates `request.jwt.claim.sub`, `COALESCE` always selects the initial non-null caller UID.
3. **Role & Permission Derivation**:
   - `public.get_effective_role()` (`20260520012857_remote_schema.sql:9404–9431`) checks:
     `SELECT r.role_name FROM public.users_profile up LEFT JOIN public.roles r ON r.id = up.role_id WHERE up.auth_user_id = auth.uid()`
   - Since `auth.uid()` evaluates to the calling admin, `get_effective_role()` returns `'Super Admin'` or `'Head Admin'`.
   - `public.get_my_role_level()` (`20260527000000_unify_role_level_source.sql:75–94`) maps that role name to `100` or `90`.
   - `public.i_have_full_access()` (`20261228000000_fix_permission_drift_f01_f02.sql:5–14`) returns `get_my_role_level() >= 90` which is `TRUE`.
   - As a direct consequence, `v_leak_detected` becomes `true`. Step 7 records `failed` with `"CRITICAL LEAK: Back Office impersonation satisfied admin access guard!"`, logs an `rbac_leak` finding, and marks the entire run `v_is_success := false`.

---

### 1.3 Observation on Run Completion & Post-Rollback Permissions
1. **Subtransaction Rollback**:
   Line 453: `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS';` rolls back all changes made inside the `BEGIN ... EXCEPTION` block to the savepoint.
2. **GUC Restoration Block**:
   Lines 467–469:
   ```sql
   IF v_orig_jwt IS NOT NULL THEN
     PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
   END IF;
   ```
   - If `v_orig_jwt` is NULL (e.g. executing via SQL editor, CLI, or test script where claims were not initialized), `request.jwt.claims` remains set to `v_bo_uid`.
   - `request.jwt.claim.sub` is never touched, so if it was modified, it would remain in the modified state.
3. **Telemetry Execution**:
   - Line 473: `PERFORM public.qa_log_detection_finding(...)`
   - Line 487: `PERFORM public.qa_log_detection_finding(...)`
   - Line 501: `v_counts := public.qa_complete_detection_run(v_run_id, ...)`
   Both `qa_log_detection_finding` (`20260520012857_remote_schema.sql:13902`) and `qa_complete_detection_run` (`20260520012857_remote_schema.sql:13627`) execute:
   ```sql
   if not (i_have_full_access() or get_my_role_level() >= 90) then
     raise exception 'Only Head Admin or Super Admin can ...';
   end if;
   ```
   If the session GUCs still point to `v_bo_uid`, this check raises an unhandled exception outside the subtransaction, crashing the entire outer transaction and discarding `qa_agent_runs`.
4. **Metadata Persistence Omission**:
   - `public.qa_complete_detection_run` only merges `'finding_counts'` into `qa_agent_runs.metadata`.
   - `qa_run_scenario` returns `v_steps` as an in-memory JSONB property of the function response, but NEVER executes an `UPDATE public.qa_agent_runs SET metadata = ...` containing `v_steps`.
   - As a result, historical records in `qa_agent_runs` contain no step execution history.

---

## 2. Logic Chain

### 2.1 Logic Chain for Step 1–6 Sequence Integrity
1. **Premise**: In PostgreSQL, every `INSERT` and `UPDATE` statement must satisfy active table constraints, valid enum/check values, and foreign keys.
2. **Observation**: Step 5 inserts `status = 'Active'` into `public.hr_emploc`.
3. **Observation**: `hr_emploc_status_check` limits statuses strictly to:
   `'Pending Emploc', 'Pending Requirements', 'For Compliance', 'Ready for Plantilla', 'Pending Approval', 'Moved to Plantilla', 'In Review', 'Complete', 'Ready for Deployment', 'Backout'`.
4. **Deduction**: Step 5 inevitably throws `check_violation`. The subtransaction aborts prematurely at Step 5, jumping to `EXCEPTION WHEN OTHERS`.
5. **Deduction**: Because the error is `check_violation` rather than `'QA_SANDBOX_ROLLBACK_SUCCESS'`, `v_unexpected_err` is populated, `v_sandbox_rolled_back` becomes `false`, Steps 6 and 7 are never reached, and the simulation fails.
6. **Solution**: Correct Step 5 in `FULL_E2E_RELAY` to use `status = 'Pending Emploc'`.

### 2.2 Logic Chain for Step 7 Negative Barrier Verification
1. **Premise**: `auth.uid()` inspects `request.jwt.claim.sub` before inspecting `request.jwt.claims ->> 'sub'`.
2. **Observation**: `qa_run_scenario` sets `request.jwt.claims` but leaves `request.jwt.claim.sub` unchanged.
3. **Deduction**: When Step 7 queries `public.i_have_full_access() OR public.get_my_role_level() >= 90`, `auth.uid()` returns the admin caller ID instead of `v_bo_uid`.
4. **Deduction**: Both functions evaluate against the admin caller (role level 100), returning `true`.
5. **Deduction**: `v_leak_detected` is set to `true`. Step 7 marks status `failed`, logs a critical defect finding, and fails the simulation.
6. **Solution**: Before Step 7 (and before each simulated role step), execute:
   ```sql
   PERFORM set_config('request.jwt.claim.sub', v_target_uid::text, true);
   PERFORM set_config('request.jwt.claims', jsonb_build_object(
     'sub', v_target_uid::text, 'role', 'authenticated'
   )::text, true);
   ```
7. **Verification of Fixed Behavior**:
   - `auth.uid()` returns `v_bo_uid`.
   - `get_effective_role()` finds `users_profile` with `auth_user_id = v_bo_uid` and resolves role `'Back Office'`.
   - `get_my_role_level()` resolves `'Back Office'` to `15` in `roles`.
   - `15 >= 90` evaluates to `FALSE`.
   - `i_have_full_access()` evaluates to `FALSE`.
   - `v_leak_detected` evaluates to `false`.
   - Step 7 appends:
     ```json
     {
       "step": 7,
       "role": "Back Office",
       "action": "negative_permission_barrier_check",
       "status": "passed",
       "details": "Permission barrier held firm: Back Office restricted from admin actions"
     }
     ```
   - `v_is_success` remains `true`, and no spurious `rbac_leak` finding is logged.

### 2.3 Logic Chain for Step Telemetry Persistence (`v_steps`)
1. **Premise**: In PostgreSQL, variables in PL/pgSQL local memory are lost when the function returns unless written to a table.
2. **Observation**: `public.qa_agent_runs` has a `metadata jsonb NOT NULL DEFAULT '{}'::jsonb` column.
3. **Observation**: `public.qa_complete_detection_run` only sets `metadata = metadata || jsonb_build_object('finding_counts', v_counts)`.
4. **Observation**: `qa_run_scenario` does not update `qa_agent_runs.metadata` with `v_steps`.
5. **Deduction**: Historical runs cannot display the step breakdown in the More Module QA Center UI unless `v_steps` is stored in `qa_agent_runs.metadata`.
6. **Solution**: In `qa_run_scenario`, post-rollback, execute:
   ```sql
   UPDATE public.qa_agent_runs
   SET metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
     'steps', v_steps,
     'scenario_code', v_code,
     'sandbox_rolled_back', v_sandbox_rolled_back,
     'unexpected_error', v_unexpected_err
   )
   WHERE id = v_run_id;
   ```

### 2.4 Logic Chain for Post-Rollback Telemetry Security & Definer Permissions
1. **Premise**: Functions `qa_log_detection_finding` and `qa_complete_detection_run` as well as RLS policies on `qa_agent_runs` and `qa_agent_findings` enforce:
   `public.i_have_full_access() OR public.get_my_role_level() >= 90`.
2. **Observation**: If session GUCs remain set to `v_bo_uid` (Back Office, level 15) when calling these functions, the authorization check fails with `raise exception 'Only Head Admin or Super Admin can ...'`.
3. **Observation**: Because this occurs outside the subtransaction, the exception aborts the entire transaction, throwing a 500 error and deleting the run.
4. **Solution**:
   - Symmetrically capture `v_orig_jwt`, `v_orig_sub`, and `v_caller_auth_uid := auth.uid()` at function entry.
   - Post-rollback, restore BOTH settings to `v_orig_sub` (or fallback to `v_caller_auth_uid`) and `v_orig_jwt` (or fallback to admin token).
   - Wrap `qa_log_detection_finding` and `qa_complete_detection_run` in defensive `BEGIN ... EXCEPTION WHEN OTHERS THEN` blocks so any telemetry anomaly cannot crash the outer transaction.

---

## 3. Caveats

1. **Active Acting Sessions**:
   If an administrator executing the scenario has an active acting session in `acting_sessions`, `public.get_effective_role()` checks `get_active_acting_session()` first. In automated or staging simulations, test actor UUIDs are newly created and do not have entries in `acting_sessions`.
2. **Read-Only Scope**:
   Per workflow rules, this investigation conducted strict read-only analysis without applying modifications to migration files or staging tables.
3. **No other caveats.**

---

## 4. Conclusion

The 6-Role Workflow Simulation (`FULL_E2E_RELAY`) in `public.qa_run_scenario` is architecturally well-conceived with its savepoint rollback mechanism, but requires four specific surgical updates in a forward migration:

1. **Step 5 Status Correction**:
   Change `status` in `hr_emploc` insertion from `'Active'` to `'Pending Emploc'`.
2. **Dual-GUC Role Impersonation**:
   In each step switch, set BOTH `request.jwt.claim.sub` and `request.jwt.claims`. When Back Office attempts the admin barrier in Step 7, it will accurately resolve to Level 15, fail the admin check, set `v_leak_detected := false`, and report `status: "passed"`.
3. **Step Telemetry Persistence**:
   Add an explicit `UPDATE public.qa_agent_runs SET metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('steps', v_steps, ...)` post-rollback so step breakdowns are preserved in table storage for historical review.
4. **Defensive Post-Rollback Identity Restoration**:
   Restore both GUC settings back to the authenticated admin caller before invoking `qa_log_detection_finding` and `qa_complete_detection_run`, and wrap telemetry calls in defensive exception handlers to guarantee transaction completion.

### Proposed Surgical Diff for `public.qa_run_scenario`

```sql
-- Caching caller context at entry:
v_orig_jwt := current_setting('request.jwt.claims', true);
v_orig_sub := current_setting('request.jwt.claim.sub', true);
v_caller_auth_uid := auth.uid();
v_caller_profile_id := public.get_current_profile_id();

-- Role impersonation helper inside subtransaction before each step:
PERFORM set_config('request.jwt.claim.sub', v_target_uid::text, true);
PERFORM set_config('request.jwt.claims', jsonb_build_object(
  'sub', v_target_uid::text, 'role', 'authenticated'
)::text, true);

-- Step 5 hr_emploc status fix:
INSERT INTO public.hr_emploc (id, applicant_name, vcode, account, position, employee_no, status, applicant_id, vacancy_id)
VALUES (gen_random_uuid(), 'Jane Relay Doe', v_vcode, 'QA Relay Account', 'Relay Specialist', v_emp_no, 'Pending Emploc', v_test_applicant_id, v_test_vacancy_id)
RETURNING id INTO v_test_emploc_id;

-- Post-rollback GUC restoration:
IF v_orig_sub IS NOT NULL AND v_orig_sub <> '' THEN
  PERFORM set_config('request.jwt.claim.sub', v_orig_sub, true);
ELSIF v_caller_auth_uid IS NOT NULL THEN
  PERFORM set_config('request.jwt.claim.sub', v_caller_auth_uid::text, true);
ELSE
  PERFORM set_config('request.jwt.claim.sub', '', true);
END IF;

IF v_orig_jwt IS NOT NULL AND v_orig_jwt <> '' THEN
  PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
ELSIF v_caller_auth_uid IS NOT NULL THEN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_caller_auth_uid::text, 'role', 'authenticated')::text, true);
ELSE
  PERFORM set_config('request.jwt.claims', '', true);
END IF;

-- Persisting steps to metadata post-rollback:
UPDATE public.qa_agent_runs
SET metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
  'steps', v_steps,
  'scenario_code', v_code,
  'sandbox_rolled_back', v_sandbox_rolled_back,
  'unexpected_error', v_unexpected_err
)
WHERE id = v_run_id;
```

---

## 5. Verification Method

### 5.1 Independent Code & Invariant Verification
1. **Verify Table Status Constraints**:
   Inspect `supabase/migrations/20260520012857_remote_schema.sql` at line 2851:
   Confirm `hr_emploc_status_check` does not permit `'Active'`, validating why Step 5 currently fails.
2. **Verify SQL Contracts & ADR Integrity**:
   Run the project gates:
   ```powershell
   npm run check:adr
   npm run check:sql
   ```
   Both checks must pass cleanly with `ADR_MIRROR_STATUS: FRESH` and `SQL_CONTRACTS_OK`.
3. **Verify GUC Pattern in Codebase**:
   Inspect `scripts/tests/plantilla_import_regression.sql:134`:
   Confirm that setting `request.jwt.claim.sub` is the standard pattern across the repo for impersonating users in PL/pgSQL tests.
4. **Invalidation Conditions**:
   - If Supabase `auth.uid()` implementation is re-written to read exclusively from `request.jwt.claims ->> 'sub'` without consulting `request.jwt.claim.sub`, then setting `request.jwt.claims` alone would suffice. However, in Supabase PostgREST, `request.jwt.claim.sub` takes precedence.
