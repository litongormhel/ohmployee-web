# QA Workflows & Agent Simulation Architecture Investigation Handoff

## 1. Observation

### 1.1 Existing Architecture & File Inventory
- **Database Simulation Engine**: `supabase/migrations/20262606000045_qa_role_relay_engine.sql`
  - Defines `public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY'::text) RETURNS jsonb`.
  - Implements an atomic rollback subtransaction catching `QA_SANDBOX_ROLLBACK_SUCCESS`.
  - Intended to execute a 6-Role AI Agent Workflow Relay across Head Admin, Encoder, Recruitment, HRCO, HR Personnel, and Back Office.
- **Frontend QA Center Modal**: `src/components/more/QaCenterModal.tsx`
  - Dropdown options defined in `COMMON_SCENARIOS` (lines 39–45):
    ```typescript
    const COMMON_SCENARIOS = [
      { code: "VAC_ARCHIVE_001", label: "Vacancy Archival Integrity" },
      { code: "PLANTILLA_001", label: "Plantilla Slot Allocation" },
      { code: "HR_EMPLOC_001", label: "HR Emploc Active Sync" },
      { code: "CENCOM_001", label: "CENCOM Edit Lock & Quota" },
      { code: "AUTH_MATRIX_001", label: "Authorization Drift Probe" },
    ];
    ```
    `FULL_E2E_RELAY` is omitted.
  - Scenario execution handler (lines 73–81):
    ```typescript
    const handleRunScenario = async () => {
      if (!selectedScenario) return;
      try {
        await runScenarioMutation.mutateAsync(selectedScenario);
        showToast(`Scenario ${selectedScenario} executed successfully.`);
      } catch (err: unknown) {
        showToast(`Scenario run failed: ${(err as Error).message}`);
      }
    };
    ```
    The RPC return payload (`data`) containing the `steps` array is discarded; only a 4-second toast notification is shown.
- **Query & Mutation Layer**: `src/lib/queries/governance.ts`
  - Lines 464–471:
    ```typescript
    export async function runQaScenarioRpc(scenarioCode: string) {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("qa_run_scenario", {
        p_scenario_code: scenarioCode.trim(),
      });
      if (error) throw error;
      return data;
    }
    ```
- **Telemetry & Core Detection Engine**: `supabase/migrations/20260520012857_remote_schema.sql`
  - Tables: `public.qa_agent_runs` (lines 1022–1038), `public.qa_agent_findings` (lines 1000–1020).
  - Core Detection Suite: `public.qa_run_core_detection_suite()` (lines 13942–13978) orchestrating:
    - `public.qa_detect_duplicate_active_employee_numbers(p_run_id)` (lines 13656–13698)
    - `public.qa_detect_duplicate_active_vcodes(p_run_id)` (lines 13702–13746)
    - `public.qa_detect_orphan_hr_emploc(p_run_id)` (lines 13750–13795)
    - `public.qa_detect_orphan_plantilla(p_run_id)` (lines 13799–13844)
    - `public.qa_detect_workflow_status_mismatch(p_run_id)` (lines 13848–13889)
  - Lifecycle RPCs: `public.qa_start_detection_run` (line 13980), `public.qa_complete_detection_run` (line 13630), `public.qa_log_detection_finding` (line 13893).
- **Role & Authorization Functions**:
  - `public.get_effective_role()` (`supabase/migrations/20260520012857_remote_schema.sql:9404–9431`) resolves role by querying `users_profile` where `auth_user_id = auth.uid()`.
  - `public.get_my_role_level()` (`supabase/migrations/20260527000000_unify_role_level_source.sql:75–94`) maps `get_effective_role()` to `roles.role_level`.
  - `public.i_have_full_access()` (`supabase/migrations/20261228000000_fix_permission_drift_f01_f02.sql:5–14`) checks `public.get_my_role_level() >= 90`.

---

### 1.2 Observed Roles in the Simulation
In `supabase/migrations/20262606000045_qa_role_relay_engine.sql` (lines 68–155), six roles are simulated:
1. **Head Admin** (`v_ha_uid`): Queried where `r.role_name IN ('Head Admin', 'Super Admin')` (Level 90–100).
2. **Encoder** (`v_encoder_uid`): Queried where `r.role_name ILIKE 'Encoder'` (Level 30).
3. **Recruitment** (`v_recruiter_uid`): Queried where `r.role_name ILIKE 'Recruitment'` (Level 20).
4. **HRCO / Operations** (`v_hrco_uid`): Queried where `r.role_name IN ('HRCO', 'Operations Manager', 'OM')` (Level 45–70).
5. **HR Personnel** (`v_hr_uid`): Queried where `r.role_name ILIKE 'HR Personnel'` (Level 25).
6. **Back Office** (`v_bo_uid`): Queried where `r.role_name IN ('Back Office', 'Backoffice')` (Level 15).

If any non-admin role actor is missing from `users_profile`, a mock test actor is inserted inside the subtransaction with a generated UUID, e.g. lines 86–90:
```sql
IF v_encoder_uid IS NULL THEN
  SELECT id INTO v_role_id FROM public.roles WHERE role_name ILIKE 'Encoder' LIMIT 1;
  v_encoder_uid := gen_random_uuid();
  IF v_role_id IS NOT NULL THEN
    INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active)
    VALUES (gen_random_uuid(), v_encoder_uid, 'QA Test Encoder', 'qa_encoder@ohmployee.internal', v_role_id, 'Encoder', true);
  END IF;
END IF;
```

---

### 1.3 Observed Scenarios in Code/DB
Six scenario codes are handled in `qa_role_relay_engine.sql`:

| Scenario Code | Scenario Label | Implemented Steps | Current Status / Observations |
|---|---|---|---|
| `FULL_E2E_RELAY` | 6-Role AI Agent Workflow Relay | Step 1: Head Admin opens vacancy.<br>Step 2: Encoder creates plantilla slot.<br>Step 3: Recruitment screens applicant.<br>Step 4: HRCO confirms onboarding.<br>Step 5: HR Personnel generates HR Emploc.<br>Step 6: Back Office updates remarks.<br>Step 7: Back Office negative barrier check. | **Fails at Step 7** due to GUC context impersonation flaw. Not listed in frontend modal dropdown. |
| `VAC_ARCHIVE_001` | Vacancy Archival Integrity | Step 1: Creates test vacancy.<br>Step 2: Updates status to `Archived`.<br>Step 3: Queries active vacancy view to verify isolation. | Functional in sandbox. |
| `PLANTILLA_001` | Plantilla Slot Allocation | Step 1: Creates active plantilla slot.<br>Step 2: Updates status to `Vacant` with resignation date. | Functional in sandbox; does not test `plantilla_slots` or DOLE compliance. |
| `HR_EMPLOC_001` | HR Emploc Active Sync | Step 1: Creates active HR Emploc entry.<br>Step 2: Asserts unique index uniqueness count = 1. | Functional in sandbox; does not test document verification or plantilla deployment. |
| `CENCOM_001` | CENCOM Edit Lock & Quota | Step 1: Returns hardcoded passed step without executing assertions (lines 275–284). | **Stub / No-Op**: No real assertions executed. |
| `AUTH_MATRIX_001` | Authorization Drift Probe | Step 1: Queries `public.roles` for degraded role levels (SA/HA < 90, Encoder < 30, Recruitment < 20). | Functional; verifies baseline role levels in `roles` table. |

---

### 1.4 Observed Step Actions in `FULL_E2E_RELAY`
The step sequence in `20262606000045_qa_role_relay_engine.sql` lines 313–450 executes:
- **Step 1 (Head Admin)**: `headcount_approval_and_vacancy_init`
  - Action: Inserts into `public.vacancies` (`vcode = 'QA-RELAY-...'`, `status = 'Open'`, `required_headcount = 1`).
  - Triggers fired: `trg_auto_create_vacancy_slot` inserts into `plantilla_slots`.
- **Step 2 (Encoder)**: `plantilla_slot_allocation`
  - Action: Inserts into `public.plantilla` (`employee_name = 'Unassigned Slot'`, `employee_no = 'EMP-RELAY-...'`, `status = 'Active'`).
- **Step 3 (Recruitment)**: `applicant_intake_and_pipeline`
  - Action: Inserts into `public.applicants` (`full_name = 'Jane Relay Doe'`, `status = 'Screening'`).
- **Step 4 (HRCO / Operations)**: `onboarding_confirmation`
  - Action: Updates `public.applicants` (`status = 'Confirmed Onboard'`, `hired_date = CURRENT_DATE`).
- **Step 5 (HR Personnel)**: `emploc_generation_and_sync`
  - Action: Inserts into `public.hr_emploc` (`employee_no = v_emp_no`, `status = 'Active'`).
- **Step 6 (Back Office)**: `plantilla_move_request`
  - Action: Updates `public.plantilla` (`remarks = 'Moved by Back Office Relay QA'`).
- **Step 7 (Back Office)**: `negative_permission_barrier_check`
  - Action: Tests whether Back Office impersonated context can satisfy `i_have_full_access() OR get_my_role_level() >= 90`.
- **Controlled Sandbox Rollback**:
  - `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'` initiates atomic rollback to implicit block savepoint.

---

### 1.5 The GUC Context Impersonation & Negative Testing Flaw
At lines 48–49, 316–318, 403–405, and 420–448:
```sql
v_orig_jwt := current_setting('request.jwt.claims', true);
...
-- [Role 6: Back Office]
PERFORM set_config('request.jwt.claims', jsonb_build_object(
  'sub', v_bo_uid::text, 'role', 'authenticated'
)::text, true);
...
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
```
- When an authenticated user calls an RPC via PostgREST, PostgREST sets multiple GUC configuration settings:
  - `request.jwt.claims` (JSON string, e.g. `'{"sub":"<uuid>","role":"authenticated"}'`)
  - `request.jwt.claim.sub` (scalar string, e.g. `'<uuid>'`)
  - `request.jwt.claim.role` (scalar string, e.g. `'authenticated'`)
- In Supabase, the standard definition of `auth.uid()` checks `current_setting('request.jwt.claim.sub', true)` before `request.jwt.claims`.
- `qa_run_scenario` sets `request.jwt.claims` but does NOT set `request.jwt.claim.sub`.
- As a result, `auth.uid()` remains locked to the initial Super Admin caller.
- `public.get_effective_role()` inspects `users_profile` for `auth_user_id = auth.uid()`, returning the caller's role (`Super Admin`).
- `public.get_my_role_level()` returns `100`.
- `public.i_have_full_access()` evaluates `100 >= 90` which is `TRUE`.
- Therefore, `v_leak_detected := true`.
- Step 7 reports: `"CRITICAL LEAK: Back Office impersonation satisfied admin access guard!"` with status `failed`.
- Telemetry logs a `critical` finding: `'rbac_leak'` ("Authorization Matrix Barrier Failure").
- The entire simulation run marks `status = 'failed'` on every execution.

---

## 2. Logic Chain

1. **Premise**: In PostgreSQL/PostgREST, role resolution and row-level security depend on `auth.uid()`, which evaluates `current_setting('request.jwt.claim.sub', true)` first and falls back to `request.jwt.claims` only when the former is null.
2. **Observation**: `qa_role_relay_engine.sql` (lines 316, 334, 352, 369, 386, 403) sets only `request.jwt.claims` and does not set `request.jwt.claim.sub`.
3. **Inference**: During all simulated role steps, `auth.uid()` remains bound to the caller (Super Admin).
4. **Consequence**: When Step 7 executes `public.i_have_full_access() OR public.get_my_role_level() >= 90`, the function checks the caller's level (100) instead of the Back Office level (15).
5. **Deduction**: Step 7 flags a false-positive authorization breach (`v_leak_detected := true`), logs a critical finding to `public.qa_agent_findings`, and sets `v_is_success := false`.
6. **UI Observation**: In `QaCenterModal.tsx`:
   - `FULL_E2E_RELAY` is not in `COMMON_SCENARIOS`, so administrators cannot select it from the dropdown.
   - When any scenario runs, `runScenarioMutation.mutateAsync` returns `{ success, run_id, scenario_code, sandbox_rolled_back, steps, finding_counts }`, but `QaCenterModal.tsx` completely ignores the return object, leaving the user with only a 4-second toast.
   - The UI contains no component, timeline, or drawer to inspect the agent steps, their outcomes, or details.
7. **Database Storage Observation**: `public.qa_complete_detection_run` does not persist the `v_steps` array into `qa_agent_runs.metadata`. Therefore, once the RPC returns, the step-by-step audit trail is erased from persistent database records.
8. **Conclusion**: The QA simulation engine suffers from two blockers:
   - A database-level GUC impersonation defect causing simulation failure and false-positive critical bug reports.
   - A frontend-level presentation omission where `FULL_E2E_RELAY` cannot be selected and step outcomes cannot be reviewed.

---

## 3. Caveats

1. **Staging vs Production**: The investigation observed migrations and frontend components directly in the repository and confirmed environment pointer `.env` references Staging (`qqiiznmqxfoamqytjica`). No live mutation was executed.
2. **Acting Sessions Overlay**: If a user has an active acting session in `acting_sessions`, `public.get_effective_role()` prioritizes `acting_sessions.acting_role` over `users_profile.role_id`. In a sterile simulation environment, test actor IDs do not have active acting sessions.
3. **Direct Table Mutations vs Canonical RPCs**: The simulation currently executes raw `INSERT`/`UPDATE` statements against `vacancies`, `plantilla`, `applicants`, and `hr_emploc` instead of invoking the canonical business logic RPCs (such as `approve_hc_request`, `hr_emploc_deploy_to_plantilla`, or `plantilla_update_separation`). While this isolates data mutations in the subtransaction, it does not fully stress-test the validation logic inside those RPCs.

---

## 4. Conclusion

The Multi-Role Agent Simulation Architecture in OHMployee is structurally well-designed with atomic subtransaction rollback (`QA_SANDBOX_ROLLBACK_SUCCESS`), zero-data-pollution guarantees, and persistent telemetry (`qa_agent_runs` / `qa_agent_findings`). However, it cannot currently pass or be fully operated from the web application due to four specific issues:

1. **Context Impersonation GUC Bug**: `qa_run_scenario` sets `request.jwt.claims` but fails to set `request.jwt.claim.sub`. This causes `auth.uid()` to remain Super Admin throughout, triggering a false-positive critical security leak at Step 7 (`v_leak_detected = true`) and failing the run.
2. **Missing Frontend Dropdown Option**: `COMMON_SCENARIOS` in `QaCenterModal.tsx` omits `FULL_E2E_RELAY`.
3. **Discarded Step Telemetry in UI**: `QaCenterModal.tsx` discards the returned `steps` array from `runScenarioMutation.mutateAsync()`, failing the acceptance criterion to display step outcomes (`passed`/`failed`) and descriptions.
4. **Steps Omitted from Database Metadata**: `public.qa_complete_detection_run` does not persist `steps` into `qa_agent_runs.metadata`, preventing retroactive inspection from the "Runs" tab.

### Concrete Technical Recommendations

#### Recommendation 1: Surgical Fix for Database Function `public.qa_run_scenario`
Apply a surgical update to `public.qa_run_scenario`:
1. Cache both original settings:
   ```sql
   v_orig_jwt := current_setting('request.jwt.claims', true);
   v_orig_sub := current_setting('request.jwt.claim.sub', true);
   ```
2. When switching roles before each step, set both GUCs:
   ```sql
   PERFORM set_config('request.jwt.claim.sub', v_target_uid::text, true);
   PERFORM set_config('request.jwt.claims', jsonb_build_object(
     'sub', v_target_uid::text, 'role', 'authenticated'
   )::text, true);
   ```
3. Restore both GUCs in the cleanup block:
   ```sql
   IF v_orig_sub IS NOT NULL THEN
     PERFORM set_config('request.jwt.claim.sub', v_orig_sub, true);
   END IF;
   IF v_orig_jwt IS NOT NULL THEN
     PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
   END IF;
   ```
4. Save `v_steps` into `qa_agent_runs.metadata`:
   ```sql
   UPDATE public.qa_agent_runs
   SET metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('steps', v_steps, 'scenario_code', v_code)
   WHERE id = v_run_id;
   ```
5. Implement real assertion logic in `CENCOM_001` (validating group headcounts and quota lock settings) instead of a hardcoded stub.

#### Recommendation 2: Frontend Upgrades in `QaCenterModal.tsx`
1. Add `FULL_E2E_RELAY` to `COMMON_SCENARIOS`:
   ```typescript
   { code: "FULL_E2E_RELAY", label: "Full 6-Role E2E Workflow Relay" }
   ```
   Set it as the default selected scenario (`useState("FULL_E2E_RELAY")`).
2. Add a `lastScenarioResult` state to store `{ success, run_id, scenario_code, steps, finding_counts }`.
3. In `handleRunScenario`, capture the returned mutation result and store it in state:
   ```typescript
   const res = await runScenarioMutation.mutateAsync(selectedScenario);
   setLastScenarioResult(res);
   ```
4. Render a dedicated "Agent Simulation Steps" card or drawer in the UI when `lastScenarioResult` is present, displaying:
   - Scenario badge and overall outcome (`Sandbox Rolled Back: Zero Data Pollution`).
   - Step sequence items with Role icon, Step Number, Role Name, Action Name, Status pill (`PASSED` in green / `FAILED` in red), and description details.
   - Collapsible raw JSON telemetry viewer for debugging.

---

## 5. Verification Method

To independently verify these findings:

1. **Verify Role Impersonation Behavior**:
   Inspect `supabase/migrations/20262606000045_qa_role_relay_engine.sql` at lines 48–51, 316, 403, and 420–448:
   Confirm that only `request.jwt.claims` is set with `set_config`, while `request.jwt.claim.sub` is never set.
2. **Verify Frontend Scenario Options and Result Discard**:
   Inspect `src/components/more/QaCenterModal.tsx` lines 39–45 (`COMMON_SCENARIOS`) and lines 73–81 (`handleRunScenario`).
   Confirm `FULL_E2E_RELAY` is missing from `COMMON_SCENARIOS` and `mutateAsync` return data is discarded.
3. **Verify Database Contract Compliance**:
   Run the project's contract validation suite:
   ```powershell
   npm run check:sql
   npm run check:adr
   npm test
   ```
   Confirm all physical schema contracts and ADR invariants are green.
4. **Invalidation Conditions**:
   - If Supabase's `auth.uid()` implementation in the target database does not read `request.jwt.claim.sub` (e.g. if it strictly reads `request.jwt.claims ->> 'sub'`), then Step 7 would pass. However, standard Supabase PostgREST sets `request.jwt.claim.sub`, causing `auth.uid()` to read the scalar setting first.
   - If `QaCenterModal.tsx` was already updated in an uncommitted branch, but `git status` confirms working tree is clean.
