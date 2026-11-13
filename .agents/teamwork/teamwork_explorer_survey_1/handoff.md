# Database & Sandbox Architecture Exploration Report
**Milestone**: QA Simulation Sandbox Architecture Investigation  
**State Folder**: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_1`  
**Date**: 2026-11-12T23:30:00Z  

---

## 1. Observation

### 1.1 Database Migration Landscape for QA Simulation
- **`public.qa_run_scenario`**:
  - Located in `supabase/migrations/20262606000045_qa_role_relay_engine.sql` (lines 7–520).
  - Signature: `public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY'::text) RETURNS jsonb`.
  - Properties: `SECURITY DEFINER`, `SET search_path TO 'public'`.
- **`public.qa_agent_runs`**:
  - Defined in `supabase/migrations/20260520012857_remote_schema.sql` (lines 1022–1035):
    * Columns: `id uuid DEFAULT gen_random_uuid() PRIMARY KEY`, `agent_name text NOT NULL`, `execution_type text NOT NULL`, `status text NOT NULL DEFAULT 'queued'`, `target_module text`, `target_record_id uuid`, `initiated_by uuid REFERENCES users_profile(id)`, `started_at timestamptz`, `completed_at timestamptz`, `summary text`, `metadata jsonb NOT NULL DEFAULT '{}'::jsonb`, `created_at timestamptz DEFAULT now()`.
    * Constraints: `qa_agent_runs_status_check` (`CHECK (status = ANY (ARRAY['queued', 'running', 'completed', 'failed', 'cancelled']))`), `qa_agent_runs_execution_type_check` (`CHECK (execution_type = ANY (ARRAY['manual', 'scheduled', 'event_driven']))`).
    * RLS: `qa_runs_insert` (`WITH CHECK (public.i_have_full_access() OR public.get_my_role_level() >= 90)`), `qa_runs_read` (`USING (public.i_have_full_access() OR initiated_by = public.get_current_profile_id())`), `qa_runs_update` (`USING (public.i_have_full_access() OR public.get_my_role_level() >= 90)`).
- **`public.qa_agent_findings`**:
  - Defined in `supabase/migrations/20260520012857_remote_schema.sql` (lines 980–997):
    * Columns: `id uuid DEFAULT gen_random_uuid() PRIMARY KEY`, `run_id uuid NOT NULL REFERENCES qa_agent_runs(id) ON DELETE CASCADE`, `severity text NOT NULL`, `finding_type text NOT NULL`, `module_name text`, `reference_table text`, `reference_record_id uuid`, `title text NOT NULL`, `details text`, `recommendation text`, `status text NOT NULL DEFAULT 'open'`, `assigned_to uuid`, `resolved_at timestamptz`, `resolved_by uuid`, `metadata jsonb NOT NULL DEFAULT '{}'::jsonb`, `created_at timestamptz DEFAULT now()`.
    * Constraints: `qa_agent_findings_severity_check` (`CHECK (severity = ANY (ARRAY['low', 'medium', 'high', 'critical']))`), `qa_agent_findings_status_check` (`CHECK (status = ANY (ARRAY['open', 'acknowledged', 'resolved', 'ignored']))`).
    * RLS: `qa_findings_read` and `qa_findings_write` require `public.i_have_full_access() OR public.get_my_role_level() >= 90`.
- **Helper Functions**:
  - `public.qa_start_detection_run(p_agent_name, p_target_module, p_metadata) RETURNS uuid`: Lines 13980–14018 of `20260520012857_remote_schema.sql`.
  - `public.qa_log_detection_finding(p_run_id, p_severity, p_finding_type, ...)`: Lines 13893–13939 of `20260520012857_remote_schema.sql`.
  - `public.qa_complete_detection_run(p_run_id, p_summary) RETURNS jsonb`: Lines 13617–13653 of `20260520012857_remote_schema.sql`.
- **Views**:
  - `public.v_qa_detection_run_summary` (`WITH (security_invoker = true)`): Defined in `supabase/migrations/20260603000001_security_advisor_phase1_low_risk.sql` (lines 225–245), joins `qa_agent_runs r` with `qa_agent_findings f` grouping by `r.id`.
  - `public.v_qa_open_findings`: Lines 17164–17178 of `20260520012857_remote_schema.sql`.

### 1.2 Current Sandbox Transaction Mechanism
In `supabase/migrations/20262606000045_qa_role_relay_engine.sql`:
- **Line 55**: Outer transaction registers run:
  ```sql
  v_run_id := public.qa_start_detection_run('QA_ROLE_RELAY_ENGINE', 'workflow_relay', ...);
  ```
- **Line 66–464**: Subtransaction block:
  ```sql
  BEGIN
    -- Operational mutations in vacancies, plantilla, applicants, hr_emploc
    ...
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
  ```
- **Line 467–507**: Post-subtransaction telemetry:
  ```sql
  IF v_orig_jwt IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
  END IF;
  ...
  IF v_unexpected_err IS NOT NULL THEN
    PERFORM public.qa_log_detection_finding(v_run_id, 'high', 'scenario_runtime_error', ...);
  END IF;
  v_counts := public.qa_complete_detection_run(v_run_id, ...);
  ```

### 1.3 Verbatim Constraints and Physical Schema Invariants
- **`public.hr_emploc.status` constraint**:
  - `20260520012857_remote_schema.sql:2851`:
    ```sql
    alter table "public"."hr_emploc" add constraint "hr_emploc_status_check" CHECK ((status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'Ready for Plantilla'::text, 'Pending Approval'::text, 'Moved to Plantilla'::text, 'In Review'::text, 'Complete'::text, 'Ready for Deployment'::text, 'Backout'::text]))) not valid;
    ```
- **`public.plantilla.status` constraint**:
  - `20260520012857_remote_schema.sql:2975`:
    ```sql
    alter table "public"."plantilla" add constraint "plantilla_status_check" CHECK ((status = ANY (ARRAY['Active'::text, 'Inactive'::text, 'For Deactivation'::text, 'Deactivated'::text, 'Resigned'::text, 'Transferred'::text, 'On Leave'::text]))) not valid;
    ```
- **`public.users_profile` unique constraints**:
  - `20260520012857_remote_schema.sql:3319`: `alter table "public"."users_profile" add constraint "users_profile_email_key" UNIQUE using index "users_profile_email_key";`
  - `20260520012857_remote_schema.sql:3321`: `alter table "public"."users_profile" add constraint "users_profile_full_name_key" UNIQUE using index "users_profile_full_name_key";`
- **`public.vacancies.vcode` constraint**:
  - `20260520012857_remote_schema.sql:3405`: `alter table "public"."vacancies" add constraint "vacancies_vcode_key" UNIQUE using index "vacancies_vcode_key";`

---

## 2. Logic Chain

### 2.1 Why PostgreSQL Rollback Happens Cleanly for Zero Data Pollution
1. **Observation**: PostgreSQL PL/pgSQL implements `BEGIN ... EXCEPTION ... END` by creating an internal savepoint (subtransaction).
2. **Observation**: All DML modifications executed inside the `BEGIN ... EXCEPTION` block on `vacancies`, `plantilla`, `applicants`, `hr_emploc`, `users_profile`, as well as trigger-driven side effects (`audit_logs` via `trg_audit_*`, `employee_activity_log` via `on_plantilla_insert_log`, `notifications`), belong to this subtransaction.
3. **Logic**: When `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'` is thrown at line 453, PostgreSQL aborts the subtransaction and rolls back all modifications back to the savepoint before control transfers to the `WHEN OTHERS THEN` handler.
4. **Logic**: Because `qa_start_detection_run` occurred *before* entering the `BEGIN ... EXCEPTION` block, its insert into `qa_agent_runs` is in the outer transaction and was never part of the rolled-back subtransaction.
5. **Logic**: Because `qa_log_detection_finding` and `qa_complete_detection_run` execute *after* the `BEGIN ... EXCEPTION` block, their DML writes to `qa_agent_findings` and `qa_agent_runs` occur in the valid outer transaction.
6. **Conclusion**: When PostgREST commits the RPC call, the outer transaction commits `qa_agent_runs` and `qa_agent_findings`, while all operational tables (`vacancies`, `plantilla`, `applicants`, `hr_emploc`) remain completely untouched. This satisfies Requirement R3: zero live data pollution without needing external `dblink` or autonomous transaction extensions.

### 2.2 Root Causes for Simulation Failures and Stalls

#### Root Cause 1: `hr_emploc_status_check` Constraint Violation
- **Observation**: In `20262606000045_qa_role_relay_engine.sql` line 391 (FULL_E2E_RELAY Role 5) and line 239 (HR_EMPLOC_001), the function executes:
  `INSERT INTO public.hr_emploc (..., status) VALUES (..., 'Active')`
- **Observation**: `hr_emploc_status_check` strictly allows `['Pending Emploc', 'Pending Requirements', 'For Compliance', 'Ready for Plantilla', 'Pending Approval', 'Moved to Plantilla', 'In Review', 'Complete', 'Ready for Deployment', 'Backout']`. `'Active'` is invalid.
- **Logic**: When Step 5 executes, PostgreSQL raises `check_violation: new row for relation "hr_emploc" violates check constraint "hr_emploc_status_check"`.
- **Logic**: This unhandled error triggers subtransaction abort, aborting subsequent steps (Role 6 Back Office and Step 7 Negative Barrier Check). `v_unexpected_err` is populated with the check constraint error, and the scenario reports failure.

#### Root Cause 2: `plantilla_status_check` Constraint Violation in `PLANTILLA_001`
- **Observation**: In `20262606000045_qa_role_relay_engine.sql` line 222, `PLANTILLA_001` executes:
  `UPDATE public.plantilla SET status = 'Vacant', resignation_date = CURRENT_DATE WHERE id = v_test_plantilla_id;`
- **Observation**: `plantilla_status_check` permits `['Active', 'Inactive', 'For Deactivation', 'Deactivated', 'Resigned', 'Transferred', 'On Leave']`. `'Vacant'` is invalid (it is a slot/vacancy status, not a plantilla employee status).
- **Logic**: PostgreSQL immediately throws `check_violation`, causing `PLANTILLA_001` to fail on execution.

#### Root Cause 3: JWT Context Poisoning & Post-Sandbox Crash
- **Observation**: Lines 316, 334, 352, 369, 386, 403 switch `request.jwt.claims` via `set_config('request.jwt.claims', ..., true)`.
- **Observation**: Step 6 sets `request.jwt.claims` to `v_bo_uid` (Back Office, role level 15).
- **Observation**: Line 467 restores `v_orig_jwt` via:
  ```sql
  IF v_orig_jwt IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
  END IF;
  ```
- **Logic**: If `v_orig_jwt` is NULL (e.g. running from Supabase SQL Runner, background task, or test runner where `request.jwt.claims` was unset), `v_orig_jwt` is not restored.
- **Logic**: Subsequent calls at line 487 (`qa_log_detection_finding`) and line 501 (`qa_complete_detection_run`) check:
  `IF NOT (i_have_full_access() OR get_my_role_level() >= 90) THEN RAISE EXCEPTION 'Only Head Admin or Super Admin can complete QA detection runs';`
- **Logic**: Because `request.jwt.claims` still reflects `v_bo_uid`, `get_my_role_level()` returns 15. The check raises an unhandled exception outside the subtransaction. The entire transaction crashes, causing a 500 error in PostgREST and discarding `qa_agent_runs`.

#### Root Cause 4: Synthesized Test Actor Collisions on `users_profile`
- **Observation**: Lines 88–154 synthesize missing test actors:
  `INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active) VALUES (gen_random_uuid(), v_encoder_uid, 'QA Test Encoder', 'qa_encoder@ohmployee.internal', ...);`
- **Observation**: `users_profile` enforces `users_profile_full_name_key UNIQUE` and `users_profile_email_key UNIQUE`.
- **Logic**: If a previous run committed or test fixture created a profile with `'QA Test Encoder'` or `'qa_encoder@ohmployee.internal'`, any subsequent insert will crash with `unique_violation`.
- **Logic**: Furthermore, because these inserts happen inside the rolled-back subtransaction, every run re-attempts them, firing `users_profile_audit_trigger` and risking trigger race conditions.

#### Root Cause 5: Timestamp VCODE Collision Risk
- **Observation**: Line 320 creates `v_vcode := 'QA-RELAY-' || to_char(now(), 'HH24MISS');`.
- **Observation**: `vacancies_vcode_key` is a strict UNIQUE constraint.
- **Logic**: `to_char(now(), 'HH24MISS')` has 1-second resolution. If two simulations execute concurrently or within the same second, PostgreSQL raises `unique_violation` on `vacancies_vcode_key`.

#### Root Cause 6: Disconnection in `QaCenterModal.tsx`
- **Observation**: In `src/components/more/QaCenterModal.tsx` line 39:
  `COMMON_SCENARIOS` contains only `VAC_ARCHIVE_001`, `PLANTILLA_001`, `HR_EMPLOC_001`, `CENCOM_001`, `AUTH_MATRIX_001`. The canonical `FULL_E2E_RELAY` is omitted.
- **Observation**: In `src/components/more/QaCenterModal.tsx` line 73:
  `handleRunScenario` calls `mutateAsync(selectedScenario)` and shows a generic toast (`showToast(...)`), completely discarding the returned JSON payload (`steps`, `finding_counts`, `sandbox_rolled_back`).
- **Logic**: Users cannot see whether each individual agent step passed or failed, or what findings were logged, violating Requirements R2 and R4.

---

## 3. Caveats
- No direct database writes, DDL executions, or RPC invocations were executed during this investigation (strictly read-only per system prompt and `AGENTS.md`).
- Sequences in PostgreSQL (e.g., auto-increment counters) do not roll back upon transaction abort; however, all primary tables in OHMployee (`vacancies`, `plantilla`, `applicants`, `hr_emploc`) utilize `uuid DEFAULT gen_random_uuid()`, so no sequence gaps or sequence lock contentions occur.
- No other caveats.

---

## 4. Conclusion & Recommended Architecture Solutions

### 4.1 Transaction Architecture Confirmation
The PL/pgSQL savepoint approach (`BEGIN ... EXCEPTION WHEN OTHERS ... END` + `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`) is **architecturally sound and optimal for PostgreSQL/Supabase**:
1. It guarantees zero data pollution without requiring external server extensions like `dblink` or `pg_background`.
2. It allows telemetry (`qa_agent_runs` and `qa_agent_findings`) to be committed in the outer transaction while rolling back 100% of operational mutations.
3. It cascades rollback to all trigger-generated rows in `audit_logs`, `employee_activity_log`, and `notifications`.

### 4.2 Required Database Function Surgical Diff (`qa_run_scenario`)
A forward migration should update `public.qa_run_scenario` in `supabase/migrations/` with the following surgical corrections:
1. **Fix `hr_emploc.status`**:
   - In Step 5 of `FULL_E2E_RELAY`: Change `status` from `'Active'` to `'Pending Emploc'` (or `'Ready for Plantilla'`).
   - In `HR_EMPLOC_001`: Change `status` from `'Active'` to `'Pending Emploc'`.
2. **Fix `plantilla.status` in `PLANTILLA_001`**:
   - Change `SET status = 'Vacant'` to `SET status = 'Resigned', separation_status = 'Resigned'`.
3. **Defensive JWT Claim Restoration**:
   - Save caller identity before switching: `v_orig_jwt := current_setting('request.jwt.claims', true);`.
   - Restore using:
     ```sql
     IF v_orig_jwt IS NOT NULL THEN
       PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
     ELSE
       PERFORM set_config('request.jwt.claims', '', true);
     END IF;
     ```
   - In `qa_complete_detection_run` and `qa_log_detection_finding`, ensure the caller profile ID check or execution permissions use `SECURITY DEFINER` privileges or caller profile fallback to prevent unhandled security gate exceptions when finishing runs.
4. **Collision-Proof Identifiers**:
   - Replace `to_char(now(), 'HH24MISS')` with `to_char(now(), 'HH24MISS') || '-' || substr(gen_random_uuid()::text, 1, 6)`.
5. **Deterministic Test Actor Resolution**:
   - Select existing users with the target role. If none exist, synthesize using randomized emails/names (e.g. `qa_encoder_` || substr(gen_random_uuid()::text, 1, 8) || `@ohmployee.internal`) to permanently avoid `unique_violation` collisions.

### 4.3 Required Frontend UI Updates (`QaCenterModal.tsx`)
1. Add `{ code: "FULL_E2E_RELAY", label: "Full 6-Role Workflow Relay" }` to `COMMON_SCENARIOS`.
2. Capture the returned `steps` array in state upon scenario completion.
3. Render an interactive execution timeline drawer/card displaying each role's step, status badge (passed/failed), action name, and details.

---

## 5. Verification Method

### 5.1 Independent Codebase & Schema Verification
1. **Verify SQL Contracts and Invariants**:
   ```powershell
   npm run check:sql
   ```
   Must report `SQL_CONTRACTS_OK` verifying 28 core tables & 19 cross-module RPC contracts.
2. **Verify ADR Freshness**:
   ```powershell
   npm run check:adr
   ```
   Must report `ADR_MIRROR_STATUS: FRESH`.
3. **Verify Lint and Unit Tests**:
   ```powershell
   npm test
   npm run lint
   ```
4. **Staging Environment Pre-Flight Inspection**:
   Inspect `.env` to verify connection points to Staging (`qqiiznmqxfoamqytjica`) and never Production (`rwxelulyapjgaarlwkus`).

---

## Next Steps
1. Submit this survey report to the parent agent (`6863d778-d94c-4bc3-b617-a727a50f6360`) via `send_message`.
2. Present the implementation plan and regression risk assessment for user approval prior to authoring the surgical migration.

> [!TIP]
> Always run `npm run check:sql` after authoring or modifying any SQL function migration to ensure zero cross-module contract regressions.
