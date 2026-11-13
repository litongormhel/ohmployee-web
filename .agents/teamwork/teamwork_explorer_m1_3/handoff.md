# Handoff Report: M1 Explorer 3 — Migration Naming & SQL Contract Guard Verification Specialist

## 1. Observation

### 1.1 Migration Indexing and Ordering in `supabase/migrations/`
- Tool command: `Get-ChildItem -Path supabase/migrations -File | Sort-Object Name -Descending | Select-Object -First 10`
- Observed Output:
  ```
  20262606000105_fix_approve_plantilla_import_batch_store_columns.sql
  20262606000104_restore_hr_emploc_for_emploc_and_upload_docs_rpcs.sql
  20262606000103_fix_get_my_allowed_accounts_union_group_scopes.sql
  20262606000102_harden_user_management_activation_and_hrco_sync.sql
  20262606000101_align_list_web_vacancies_adr001_rule4_open_capacity.sql
  20262606000100_grant_list_web_vacancies_postgres.sql
  20262606000099_expose_hc_in_list_web_vacancies_row_capabilities.sql
  20262606000098_block_vacancy_closure_when_applicants_active.sql
  20262606000097_fix_orphan_stores_and_closure_lifecycle.sql
  20262606000096_user_management_as_hrco_source_of_truth.sql
  ```
- Tool command: Cross-repository migration check across `../ohmployee/supabase/migrations`, `../ohmployee-web/supabase/migrations`, and `ROOT/supabase/migrations` via Node script (`collectMigrationEntries` algorithm from `scripts/check-sql-contracts.mjs`):
  ```
  Total migrations: 630
  Last 5 migrations:
    20262606000101_align_list_web_vacancies_adr001_rule4_open_capacity.sql
    20262606000102_harden_user_management_activation_and_hrco_sync.sql
    20262606000103_fix_get_my_allowed_accounts_union_group_scopes.sql
    20262606000104_restore_hr_emploc_for_emploc_and_upload_docs_rpcs.sql
    20262606000105_fix_approve_plantilla_import_batch_store_columns.sql
  ```
- Lexicographical Ordering Check:
  In JavaScript `localeCompare` and Supabase CLI migration runner, `"20262606..."` sorts AFTER all `"202611..."` and `"202605..."` migrations (index 4 character `'2'` > `'1'`).
  Therefore, the latest applied migration in the system is `20262606000105_fix_approve_plantilla_import_batch_store_columns.sql`.
  The next strictly monotonic migration version is **`20262606000106`**.

### 1.2 Inspection of `scripts/check-sql-contracts.mjs`
- File path: `scripts/check-sql-contracts.mjs`, lines 595–605:
  ```javascript
  // 1. Check DML columns in the latest definition of all functions touched in active migrations (20262606000050+)
  for (const [, funcInfo] of latestFunctions) {
    const isModernMigration =
      (funcInfo.file.startsWith("20262606") &&
        funcInfo.file >= "20262606000050") ||
      funcInfo.file.startsWith("202611");
    if (!isModernMigration) {
      continue;
    }
    const dmlErrors = validateFunctionDmlColumns(funcInfo, enforcedTables);
    violations.push(...dmlErrors);
  }
  ```
- Observation: Any function defined in migration `20262606000106_...` satisfies `isModernMigration = true`. Every `INSERT INTO public.<table> (...)` and `UPDATE public.<table> SET ...` targeting any of the 28 `ENFORCED_DML_TABLES` is validated against the physical column catalog extracted from all 630 migrations.

- Physical Table Columns Verified in Catalog for `qa_run_scenario`:
  1. `users_profile`: `id` (OK), `auth_user_id` (OK), `full_name` (OK), `email` (OK), `role_id` (OK), `role` (OK), `is_active` (OK).
  2. `vacancies`: `id` (OK), `vcode` (OK), `account` (OK), `position` (OK), `status` (OK), `created_at` (OK), `required_headcount` (OK).
  3. `plantilla`: `id` (OK), `employee_name` (OK), `employee_no` (OK), `account` (OK), `status` (OK), `position` (OK), `resignation_date` (OK), `vacancy_id` (OK), `vcode` (OK), `remarks` (OK).
  4. `applicants`: `id` (OK), `vacancy_vcode` (OK), `full_name` (OK), `first_name` (OK), `last_name` (OK), `status` (OK), `contact_number` (OK), `hired_date` (OK).
  5. `hr_emploc`: `id` (OK), `applicant_name` (OK), `vcode` (OK), `account` (OK), `position` (OK), `employee_no` (OK), `status` (OK), `applicant_id` (OK), `vacancy_id` (OK).

### 1.3 Physical Schema Check Constraints Identified
- `hr_emploc.status`:
  From `supabase/migrations/20260520012857_remote_schema.sql` line 3012:
  `CHECK (status = ANY (ARRAY['Pending Emploc', 'Pending Requirements', 'For Compliance', 'Ready for Plantilla', 'Pending Approval', 'Moved to Plantilla', 'In Review', 'Complete', 'Ready for Deployment', 'Backout']))`
  `'Active'` violates this check constraint. Simulation MUST insert `'Pending Emploc'`.
- `plantilla.status`:
  From `supabase/migrations/20261007000001_on_leave_floating_status.sql` line 27 and `20262606000074_fix_revert_hr_emploc_plantilla_status.sql` line 4:
  `CHECK (status = ANY (ARRAY['Active', 'Inactive', 'Pending Deactivation', 'Rejected Deactivation', 'Deactivated', 'On Leave']))`
  `'Vacant'` violates this check constraint. Simulation transition MUST use `'Deactivated'` or `'Inactive'`.

### 1.4 GUC Impersonation Invariant
- File: `supabase/migrations/20260520012857_remote_schema.sql` line 9425 (`get_effective_role`) checks:
  `where up.auth_user_id = auth.uid()`
- In Supabase PostgreSQL, `auth.uid()` checks `current_setting('request.jwt.claim.sub', true)` before `request.jwt.claims`.
- In `20262606000045_qa_role_relay_engine.sql` line 316, 334, 352, 369, 386, 403:
  Only `request.jwt.claims` was configured. `request.jwt.claim.sub` remained set to the ambient caller (Head Admin), causing impersonation to leak and the negative barrier probe to fail.
- Dual GUC setting is required:
  ```sql
  PERFORM set_config('request.jwt.claim.sub', v_simulated_uid::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_simulated_uid::text, 'role', 'authenticated')::text, true);
  ```

### 1.5 Current Verification Gate Status
- `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH — ADR-001 (3729ccb), ADR-002 (49d7a40)`.
- `npm run check:sql`: `[sql-guard] SQL_CONTRACTS_OK — verified 28 core tables & 19 cross-module RPC contracts across 630 migrations.`
- Git branch: `main` (verified clean working tree, untracked `.agents/teamwork/` and `PROJECT.md`).
- Supabase Project Ref: `qqiiznmqxfoamqytjica` (Staging confirmed).

---

## 2. Logic Chain

1. **Migration Naming**:
   - Observation 1.1 establishes that `20262606000105_fix_approve_plantilla_import_batch_store_columns.sql` is the latest migration across both web and mobile repositories.
   - Any timestamp using standard UTC (e.g. `20261113010000`) would sort before `20262606000105` in ASCII order because `'1' < '2'`. This would cause the migration runner to attempt out-of-order execution and would prevent `scripts/check-sql-contracts.mjs` from recognizing it as the latest function definition.
   - Therefore, the next forward migration must strictly increment the counter: **`20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`**.

2. **Physical Column Guard Compliance**:
   - Observation 1.2 proves that `scripts/check-sql-contracts.mjs` will strictly evaluate DML in `qa_run_scenario` because `20262606000106` is `>= 20262606000050`.
   - The test run using the catalog parser verified that all columns accessed in `users_profile`, `vacancies`, `plantilla`, `applicants`, and `hr_emploc` match physical schema definitions.
   - No hallucinated columns (`city`, `source_import_batch_id`, etc.) are introduced, ensuring `npm run check:sql` will pass cleanly.

3. **Physical Schema Constraint Compliance**:
   - Observation 1.3 shows that `hr_emploc` lacks `'Active'` and `plantilla` lacks `'Vacant'` in their respective `CHECK` constraints.
   - Correcting `hr_emploc.status` to `'Pending Emploc'` and `plantilla.status` to `'Deactivated'` eliminates runtime `23514 check_violation` errors inside the simulation subtransaction, allowing the simulation to proceed without false failure.

4. **Telemetry & Atomic Rollback Invariant**:
   - The outer function starts a run via `v_run_id := public.qa_start_detection_run(...)`.
   - The inner subtransaction executes simulation steps, records telemetry steps in `v_steps`, and concludes with `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`.
   - The exception handler catches `QA_SANDBOX_ROLLBACK_SUCCESS`, sets `v_sandbox_rolled_back := true`, restores ambient JWT GUCs, logs findings outside the rollback via `public.qa_log_detection_finding`, persists `steps` into `public.qa_agent_runs.metadata`, and completes the run via `public.qa_complete_detection_run`.

---

## 3. Caveats

- **Existing Staging State**: This investigation verified migration files and schema declarations from the code repositories. When applying migration `106` to staging (`qqiiznmqxfoamqytjica`), the M1 Worker must ensure no uncommitted manual changes exist on staging.
- **RPC Invariant List**: `public.qa_run_scenario` is not currently in the 19 RPCs listed in `RPC_INVARIANT_CONTRACTS` in `scripts/check-sql-contracts.mjs`. However, its DML is automatically validated by the universal column checker because the filename starts with `20262606000106`.

---

## 4. Conclusion

1. **Exact Migration Version & Filename**:
   `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`
2. **Guarded Physical Table Columns**:
   - `public.users_profile`: `(id, auth_user_id, full_name, email, role_id, role, is_active)`
   - `public.vacancies`: `(id, vcode, account, position, status, created_at, required_headcount)`
   - `public.plantilla`: `(id, employee_name, employee_no, account, status, position, vacancy_id, vcode, remarks, resignation_date)`
   - `public.applicants`: `(id, vacancy_vcode, full_name, first_name, last_name, status, contact_number, hired_date)`
   - `public.hr_emploc`: `(id, applicant_name, vcode, account, position, employee_no, status, applicant_id, vacancy_id)`
3. **Mandatory DML Constraint Corrections**:
   - `hr_emploc.status` must be `'Pending Emploc'` (never `'Active'`).
   - `plantilla.status` must be `'Deactivated'` (never `'Vacant'`).
   - Dual GUC setting must be used: `set_config('request.jwt.claim.sub', ...)` AND `set_config('request.jwt.claims', ...)`.
4. **Pre-Commit and Post-Commit Verification Checklist**: Established below for M1 Worker execution.

---

## 5. Verification Method (M1 Worker Checklist)

### 5.1 Pre-Authoring Checklist
```powershell
# 1. Environment Safety Check (Ensure Staging, NEVER Production)
Get-Content supabase\.temp\project-ref
# Expected output: qqiiznmqxfoamqytjica

# 2. Branch Check (Must be on main)
git branch --show-current
# Expected output: main

# 3. ADR Freshness Check
npm run check:adr
# Expected output: ADR_MIRROR_STATUS: FRESH

# 4. SQL Contract Baseline
npm run check:sql
# Expected output: [sql-guard] SQL_CONTRACTS_OK
```

### 5.2 Implementation Checklist (Authoring Migration 106)
- File: `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`
- Surgical diff base: `supabase/migrations/20262606000045_qa_role_relay_engine.sql`.
- Applied corrections:
  1. Fix dual GUC setting in all 6 role steps (`request.jwt.claim.sub` + `request.jwt.claims`).
  2. Fix cache & restoration of both `request.jwt.claim.sub` and `request.jwt.claims`.
  3. Fix `hr_emploc.status = 'Pending Emploc'` in simulation steps.
  4. Fix `plantilla.status = 'Deactivated'` in simulation steps.
  5. Collision-proof `vcode` (`QA-RELAY-` + unix epoch + random hex) and actor emails.
  6. Persist full `steps` JSON array into `qa_agent_runs.metadata`.
  7. Correct negative permission barrier check logic for Back Office.

### 5.3 Pre-Commit Verification Pipeline
```powershell
# 1. Verify SQL Contract & Schema Guards
npm run check:sql
# Expected output: [sql-guard] SQL_CONTRACTS_OK — verified 28 core tables & 19 cross-module RPC contracts across 631 migrations.

# 2. Run Linting (chains check:sql)
npm run lint
# Expected output: 0 errors

# 3. Run Unit Tests (chains check:sql)
npm test
# Expected output: 211/211 passed (or current suite clean)

# 4. Verify Next.js Build
npm run build
# Expected output: Next.js build completed successfully (exit code 0)
```

### 5.4 Database Verification & Live Rollback Assertion (Staging)
```sql
-- 1. Execute Scenario Run on Staging
SELECT public.qa_run_scenario('FULL_E2E_RELAY');

-- 2. Verify Atomic Sandbox Zero-Pollution
SELECT count(*) FROM public.vacancies WHERE vcode LIKE 'QA-RELAY-%';
-- Expected count: 0

SELECT count(*) FROM public.plantilla WHERE vcode LIKE 'QA-RELAY-%' OR employee_no LIKE 'EMP-RELAY-%';
-- Expected count: 0

SELECT count(*) FROM public.applicants WHERE vacancy_vcode LIKE 'QA-RELAY-%';
-- Expected count: 0

SELECT count(*) FROM public.hr_emploc WHERE vcode LIKE 'QA-RELAY-%' OR employee_no LIKE 'EMP-RELAY-%';
-- Expected count: 0

-- 3. Verify Telemetry Persistence
SELECT id, agent_name, status, summary, metadata->'steps' AS steps, metadata->'finding_counts' AS finding_counts
FROM public.qa_agent_runs
WHERE agent_name = 'QA_ROLE_RELAY_ENGINE'
ORDER BY started_at DESC
LIMIT 1;
-- Expected: Status 'completed' or 'failed' (with steps array and finding_counts populated)
```

### 5.5 Local Commit Checklist
```powershell
# 1. Check git status to ensure only expected files are staged
git status

# 2. Stage only explicitly changed files (never git add .)
git add supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql
git add .ai/briefing.md
git add .ai/handoff.md
git add PROJECT.md

# 3. Commit locally on main (DO NOT PUSH)
git commit -m "ohm#m1_db: Deploy QA sandbox simulation engine and multi-role relay migration 106"
```
