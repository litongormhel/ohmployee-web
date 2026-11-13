# Milestone 1 Forensic Audit Report: Database Engine & Multi-Role Sandbox Migration

**Work Product**: `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`  
**Profile**: General Project  
**Integrity Mode**: Development (per `ORIGINAL_REQUEST.md`)  
**Verdict**: **CLEAN**  
**Date**: 2026-11-13T02:05:00Z  
**Auditor**: M1 Forensic Auditor (`teamwork_auditor_m1_1`)  

---

## 1. Observation

### 1.1 Git Status & Workspace Hygiene
Execution of `git status` revealed:
```text
On branch main
Your branch is ahead of 'origin/main' by 22 commits.
  (use "git push" to publish your local commits)

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	.agents/teamwork/
	PROJECT.md
	supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql

nothing added to commit but untracked files present (use "git add" to track)
```
- No modified tracked files exist in the repository.
- `main` remains pristine.
- The only introduced database change is the authorized migration file `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`.

### 1.2 Forensic Static Analysis of Migration 106
Line-by-line inspection of `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`:

1. **Authorization Guard (Lines 48–51)**:
   ```sql
   IF NOT (public.i_have_full_access() OR public.get_my_role_level() >= 90) THEN
     RAISE EXCEPTION 'Only Head Admin or Super Admin can execute QA scenarios';
   END IF;
   ```
   Direct empirical test calling `SELECT public.qa_run_scenario('FULL_E2E_RELAY');` without role claims returned verbatim:
   ```text
   ERROR: P0001: Only Head Admin or Super Admin can execute QA scenarios
   CONTEXT: PL/pgSQL function qa_run_scenario(text) line 36 at RAISE
   ```
   The security guard is authentic and rejects unauthorized callers.

2. **Dual GUC Role Impersonation & Restoration (Lines 223–227, 574–598)**:
   Simulated roles set all three GUCs synchronously inside the subtransaction:
   ```sql
   PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
   PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
   PERFORM set_config('request.jwt.claims', jsonb_build_object(
     'sub', v_ha_uid::text, 'role', 'authenticated'
   )::text, true);
   ```
   Post-rollback, defensive restoration caches `v_orig_jwt`, `v_orig_sub`, and `v_orig_role` at function entry (Lines 54–56) and restores them defensively, falling back to `v_ha_uid` to guarantee subsequent session queries never execute with Back Office privileges.

3. **Atomic Savepoint Subtransaction & Zero Leakage (Lines 73, 560–572)**:
   ```sql
   BEGIN
     ...
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
   ```
   All test actors created in `users_profile` (Lines 87–96, 112–121, 136–145, 161–170, 185–194, 208–217) and operational table mutations (`vacancies`, `plantilla`, `applicants`, `hr_emploc`) occur strictly within this `BEGIN ... EXCEPTION ... END` subtransaction.

4. **Negative Permission Barrier & Finding Logging (Lines 528–556, 600–626)**:
   - Evaluates whether Back Office actor has `i_have_full_access() OR get_my_role_level() >= 90`. If true, records `v_leak_detected := true`, sets `v_is_success := false`, and logs a `'critical'` finding to `qa_agent_findings`.
   - Any runtime error caught inside the subtransaction records `v_unexpected_err := SQLERRM`, sets `v_is_success := false`, and logs a `'high'` severity finding to `qa_agent_findings`.

### 1.3 Empirical Staging Database Execution
Direct execution of `qa_run_scenario('FULL_E2E_RELAY')` under Head Admin context (`59917295-9844-47d4-bcd9-03742b1c9c8d`) on Staging (`qqiiznmqxfoamqytjica`):

```json
{
  "run_id": "00922e5e-b923-4473-9dd0-eaa86a914628",
  "success": true,
  "sandbox_rolled_back": true,
  "scenario_code": "FULL_E2E_RELAY",
  "steps": [
    {
      "step": 1,
      "role": "Head Admin",
      "action": "headcount_approval_and_vacancy_init",
      "status": "passed",
      "details": "Authorized headcount quota and opened vacancy QA-RELAY-020255-8c4bfc"
    },
    {
      "step": 2,
      "role": "Encoder",
      "action": "plantilla_slot_allocation",
      "status": "passed",
      "details": "Created plantilla slot EMP-RELAY-020255-83da49 assigned to QA-RELAY-020255-8c4bfc"
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
      "details": "Prototyped HR Emploc assignment with employee_no EMP-RELAY-020255-83da49"
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
  "executed_at": "2026-11-13T02:02:55.229854+00:00"
}
```

Post-execution assertion query immediately after:
```sql
SELECT 
  (SELECT count(*) FROM public.vacancies WHERE vcode = 'QA-RELAY-020255-8c4bfc') AS vac_found,
  (SELECT count(*) FROM public.plantilla WHERE employee_no = 'EMP-RELAY-020255-83da49') AS plan_found,
  (SELECT count(*) FROM public.applicants WHERE vacancy_vcode = 'QA-RELAY-020255-8c4bfc') AS app_found,
  (SELECT count(*) FROM public.hr_emploc WHERE employee_no = 'EMP-RELAY-020255-83da49') AS emploc_found,
  (SELECT count(*) FROM public.vacancies WHERE vcode LIKE 'QA-%') AS total_vac_leaks,
  (SELECT count(*) FROM public.plantilla WHERE employee_no LIKE '%RELAY%') AS total_plan_leaks,
  (SELECT count(*) FROM public.hr_emploc WHERE employee_no LIKE '%RELAY%') AS total_emploc_leaks,
  (SELECT count(*) FROM public.users_profile WHERE email LIKE '%@ohmployee.internal') AS total_users_leaks;
```
Result:
```json
[{"vac_found": 0, "plan_found": 0, "app_found": 0, "emploc_found": 0, "total_vac_leaks": 0, "total_plan_leaks": 0, "total_emploc_leaks": 0, "total_users_leaks": 0}]
```
Zero simulation data exists in live operational tables.

### 1.4 Automated Project Verification Commands
- `npm run check:sql`: Verified 28 core tables & 19 cross-module RPC contracts across 631 migrations (PASS, code 0).
- `npm run check:adr`: Verified ADR freshness; ADR-001 and ADR-002 are `FRESH` (PASS, code 0).
- `npm run lint`: 0 errors, 0 warnings (PASS, code 0).
- `npm test`: 211 tests executed, 211 passed, 0 failed (PASS, code 0).
- `npm run build`: Next.js Turbopack production compilation succeeded (PASS, code 0).

---

## 2. Logic Chain

1. **Absence of Facades or Hardcoded Bypasses**:
   - Analysis of migration 106 confirms that `qa_run_scenario` executes genuine `INSERT`, `UPDATE`, and `SELECT` statements with dynamically generated identifiers (`QA-RELAY-HHMMSS-uuid`).
   - The steps array is constructed dynamically row-by-row during execution.
   - The negative permission barrier executes `public.get_my_role_level()` against the impersonated context and genuinely asserts that level < 90.

2. **Savepoint Subtransaction Integrity**:
   - PostgreSQL PL/pgSQL creates an internal savepoint on `BEGIN ... EXCEPTION ... END`.
   - When `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'` fires, all state changes made inside that block are rolled back.
   - Empirical queries executed on Staging immediately after run completion confirmed exactly 0 records in `vacancies`, `plantilla`, `applicants`, `hr_emploc`, and `users_profile`.

3. **Telemetry Persistence Outside Sandbox**:
   - `qa_start_detection_run` and `qa_complete_detection_run` are executed outside the subtransaction, ensuring the telemetry record is preserved in `qa_agent_runs`.
   - Post-execution queries on `qa_agent_runs` confirmed run record `00922e5e-b923-4473-9dd0-eaa86a914628` is intact with all 7 steps stored in `metadata->'steps'`.

4. **Surgical Diff Compliance**:
   - Comparing migration 106 against base migration 045 confirms that only the necessary bugfixes (dual GUC setter, check constraint values `'Pending Emploc'` and `'Resigned'`, collision avoidance suffixes, and metadata step enrichment) were applied. No unrelated database objects or cross-module invariants were modified.

---

## 3. Caveats

- **No Caveats**: All static checks and empirical live database verifications succeeded without anomalies.
- Staging environment (`qqiiznmqxfoamqytjica`) was used exclusively; production (`rwxelulyapjgaarlwkus`) was untouched.

---

## 4. Conclusion & Verdict

### Final Verdict: **CLEAN**

The work product `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` contains NO integrity violations, NO hardcoded facades, NO skipped assertions, and NO data pollution leaks. It is fully authentic, robust, and ready for Milestone 2 frontend integration.

### Phase Results Summary
| Check | Requirement | Result |
|---|---|---|
| Hardcoded Output Detection | No embedded PASS strings or skipped logic | **PASS** |
| Facade Detection | Authentic SQL execution across all 6 roles | **PASS** |
| Pre-populated Artifacts | No pre-baked telemetry logs | **PASS** |
| Atomic Sandbox Isolation | `QA_SANDBOX_ROLLBACK_SUCCESS` rolls back 100% of operational data | **PASS** |
| Test Actor Isolation | `users_profile` synthetic actors rolled back cleanly | **PASS** |
| Security Definier & RBAC | Rejects unprivileged callers with error `P0001` | **PASS** |
| Telemetry Invariant | Step details persisted in `qa_agent_runs.metadata` | **PASS** |
| Project Build & Tests | `check:sql`, `check:adr`, `lint`, `test`, `build` all pass | **PASS** |

---

## 5. Verification Method

To independently reproduce the forensic audit results:

```powershell
# 1. Verify SQL physical schema contracts and ADR freshness
npm run check:sql
npm run check:adr

# 2. Run codebase tests and lint
npm run lint
npm test

# 3. Verify unauthorized rejection via SQL (must fail with P0001)
# Executed against Staging (qqiiznmqxfoamqytjica):
SELECT public.qa_run_scenario('FULL_E2E_RELAY');

# 4. Verify authorized execution with Head Admin context
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '59917295-9844-47d4-bcd9-03742b1c9c8d', false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  PERFORM set_config('request.jwt.claims', '{"sub":"59917295-9844-47d4-bcd9-03742b1c9c8d","role":"authenticated"}', false);
END $$;
SELECT public.qa_run_scenario('FULL_E2E_RELAY');

# 5. Verify zero operational table leakage post-execution
SELECT 
  (SELECT count(*) FROM public.vacancies WHERE vcode LIKE 'QA-%') AS vac_count,
  (SELECT count(*) FROM public.plantilla WHERE employee_no LIKE '%RELAY%') AS plan_count,
  (SELECT count(*) FROM public.applicants WHERE vacancy_vcode LIKE 'QA-%') AS app_count,
  (SELECT count(*) FROM public.hr_emploc WHERE employee_no LIKE '%RELAY%') AS emploc_count,
  (SELECT count(*) FROM public.users_profile WHERE email LIKE '%@ohmployee.internal') AS users_count;
# Expected: all counts return 0.
```

---

## Next Steps
1. Hand off the audited migration to the Milestone 2 Worker for UI implementation in `src/components/more/QaCenterModal.tsx` and query integration in `src/lib/queries/governance.ts`.
2. Proceed with updating the UI timeline to render the authentic 7-step sequence returned by `public.qa_run_scenario('FULL_E2E_RELAY')`.

> [!TIP]
> When executing `public.qa_run_scenario` in the client application via Supabase RPC (`supabase.rpc('qa_run_scenario', ...)`), the authenticated user's session JWT is transmitted automatically, so the Head Admin authorization check and caller profile ID resolution succeed natively without manual GUC emulation.
