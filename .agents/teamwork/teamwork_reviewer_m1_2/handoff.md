# Milestone 1 Security & Sandbox Isolation Review: Handoff Report

**Reviewer**: M1 Reviewer 2 (Security & Sandbox Isolation Reviewer)  
**State Folder**: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_reviewer_m1_2`  
**Date**: 2026-11-13T02:06:00Z  
**Verdict**: **APPROVE**  
**Integrity Assessment**: **NO INTEGRITY VIOLATIONS DETECTED** (Zero hardcoding, zero dummy facades, real transactional simulation executed, genuine telemetry verified).

---

## Executive Summary & Security Assessment

Migration `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` was subjected to rigorous security review, static analysis, adversarial stress testing, and live runtime verification against Staging (`qqiiznmqxfoamqytjica`).

| Security Dimension | Evaluation | Result |
|---|---|---|
| **GUC Role Impersonation** | Synchronously sets `request.jwt.claim.sub`, `request.jwt.claim.role`, and `request.jwt.claims` for each actor | **PASS** — Both `auth.uid()` and `get_my_role_level()` resolve the exact simulated actor context |
| **Defensive GUC Restoration** | Restores cached caller GUCs (`v_orig_jwt`, `v_orig_sub`, `v_orig_role`) with fallback to Head Admin | **PASS** — Zero session residue, Back Office context never leaks to subsequent queries |
| **Atomic Sandbox Isolation** | Encapsulates all operational mutations in a subtransaction ending in `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'` | **PASS** — Verified 0 leftover records across `vacancies`, `plantilla`, `applicants`, `hr_emploc` |
| **Telemetry & Findings Integrity** | Logs findings via `qa_log_detection_finding` and completes runs via `qa_complete_detection_run` | **PASS** — Severities strictly conform to check constraints (`critical`, `high`), status defaults to `'open'`, steps persisted |
| **Authorization Guard** | Restricts execution to Head Admin / Super Admin (`i_have_full_access() OR get_my_role_level() >= 90`) | **PASS** — Tested with Operations Manager (`role_level = 70`); correctly hard-blocked |

---

## 1. Security Architecture & Isolation Analysis

### 1.1 Dual GUC Context Switching (`auth.uid()` and `get_my_role_level()`)
- **Mechanism**:
  ```sql
  PERFORM set_config('request.jwt.claim.sub', <actor_uid>::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', <actor_uid>::text, 'role', 'authenticated'
  )::text, true);
  ```
- **Context Resolution Chain**:
  1. `auth.uid()` reads `current_setting('request.jwt.claim.sub', true)` first, resolving to `<actor_uid>`.
  2. `get_my_role_level()` invokes `get_effective_role()`.
  3. `get_effective_role()` queries `public.users_profile up WHERE up.auth_user_id = auth.uid()`.
  4. With `auth.uid()` = `<actor_uid>`, it finds the simulated actor's profile and returns their assigned role (e.g., `'Back Office'`, `'Encoder'`, `'Recruitment'`).
  5. `get_my_role_level()` joins against `public.roles` and returns the exact numerical level (Back Office = 15, Recruitment = 20, Encoder = 30, Head Admin = 90).
- **Verification**: In Step 7 of `FULL_E2E_RELAY`, the negative barrier probe tests whether Back Office can satisfy `i_have_full_access() OR get_my_role_level() >= 90`. Because level evaluates to 15, the check returns `false`, confirming that authorization guards actively distinguish low-privilege actors during simulation.

### 1.2 Defensive Restoration & JWT Leak Prevention
- **Mechanism**:
  - Original claims are cached prior to subtransaction entry:
    ```sql
    v_orig_jwt := current_setting('request.jwt.claims', true);
    v_orig_sub := current_setting('request.jwt.claim.sub', true);
    v_orig_role := current_setting('request.jwt.claim.role', true);
    ```
  - Post-rollback (Section 5), all three GUCs are explicitly restored.
  - If the original caller had no GUCs (e.g. direct SQL console / service role), it falls back safely to `v_ha_uid` (Head Admin), guaranteeing that subsequent telemetry completion (`qa_complete_detection_run`) and PostgREST session handling never inherit Back Office privileges.
  - All `set_config` calls specify `is_local = true`, scoping changes to the current transaction.

### 1.3 Atomic Sandbox Rollback & Zero Operational Data Pollution
- **Mechanism**:
  - All simulation mutations occur strictly inside:
    ```sql
    BEGIN
      -- inserts & updates on vacancies, plantilla, applicants, hr_emploc, users_profile
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
  - In PostgreSQL PL/pgSQL, this construct establishes an internal savepoint. Raising the exception and catching it rolls back all data mutations, constraint triggers, and audit log entries generated within the block.
  - Telemetry operations (`qa_start_detection_run`, `qa_log_detection_finding`, `qa_complete_detection_run`, and `UPDATE qa_agent_runs`) are executed outside the subtransaction, ensuring telemetry persists while operational tables remain completely clean.

### 1.4 Findings Logging Validation
- **Severity Conformance**:
  - `qa_log_detection_finding` enforces: `if p_severity not in ('low','medium','high','critical') then raise exception ...`
  - In migration 106, findings are logged with:
    - `'critical'` for RBAC permission barrier breaches (`rbac_leak`)
    - `'high'` for unexpected simulation runtime errors (`scenario_runtime_error`)
  - Both strictly satisfy the severity check constraint.
- **Status & Recommendation**:
  - Status is assigned `'open'` automatically by `qa_log_detection_finding`.
  - Every finding call includes clear `title`, `details`, and actionable `recommendation` strings.

---

## 2. Independent Verification & Test Outputs

### 2.1 ADR Freshness Verification (`npm run check:adr`)
```text
> ohmployee_web@0.1.0 check:adr
> node scripts/adr-mirror.mjs check

[adr] Remote check: mobile ADRs are up to date with upstream.
[adr] ADR_MIRROR_STATUS: FRESH — ADR-001 (3729ccb 2026-11-12T10:33:06+08:00), ADR-002 (49d7a40 2026-11-12T17:34:47+08:00)
```
Status: **FRESH**

### 2.2 SQL Contract Gate (`npm run check:sql`)
```text
> ohmployee_web@0.1.0 check:sql
> node scripts/check-sql-contracts.mjs

[sql-guard] SQL_CONTRACTS_OK — verified 28 core tables & 19 cross-module RPC contracts across 631 migrations.
```
Status: **PASS**

### 2.3 Codebase Linting (`npm run lint`)
```text
> ohmployee_web@0.1.0 lint
> node scripts/adr-mirror.mjs check && node scripts/check-sql-contracts.mjs && eslint

[adr] Remote check: mobile ADRs are up to date with upstream.
[adr] ADR_MIRROR_STATUS: FRESH — ADR-001 (3729ccb 2026-11-12T10:33:06+08:00), ADR-002 (49d7a40 2026-11-12T17:34:47+08:00)
[sql-guard] SQL_CONTRACTS_OK — verified 28 core tables & 19 cross-module RPC contracts across 631 migrations.
```
Result: 0 errors, 0 warnings (Exit code: 0).

### 2.4 Independent Unit Test Execution (`npm test`)
```text
> ohmployee_web@0.1.0 test
> node scripts/adr-mirror.mjs check && node scripts/check-sql-contracts.mjs && node --test src/lib/utils/__tests__/*.test.mjs src/lib/queries/__tests__/*.test.mjs

[adr] Remote check: mobile ADRs are up to date with upstream.
[adr] ADR_MIRROR_STATUS: FRESH — ADR-001 (3729ccb 2026-11-12T10:33:06+08:00), ADR-002 (49d7a40 2026-11-12T17:34:47+08:00)
[sql-guard] SQL_CONTRACTS_OK — verified 28 core tables & 19 cross-module RPC contracts across 631 migrations.
...
ℹ tests 211
ℹ suites 0
ℹ pass 211
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1127.1128
```
Result: 211 tests passing, 0 failures.

### 2.5 Live Scenario Execution on Staging (`qqiiznmqxfoamqytjica`)
Executed flagship scenario `FULL_E2E_RELAY` independently:
- **Run ID**: `9e0b75ea-35a2-4c96-af2a-74731943f519`
- **Output**:
  ```json
  {
    "success": true,
    "run_id": "9e0b75ea-35a2-4c96-af2a-74731943f519",
    "scenario_code": "FULL_E2E_RELAY",
    "sandbox_rolled_back": true,
    "steps": [
      {
        "step": 1,
        "role": "Head Admin",
        "action": "headcount_approval_and_vacancy_init",
        "status": "passed",
        "details": "Authorized headcount quota and opened vacancy QA-RELAY-020258-853b20"
      },
      {
        "step": 2,
        "role": "Encoder",
        "action": "plantilla_slot_allocation",
        "status": "passed",
        "details": "Created plantilla slot EMP-RELAY-020258-c99967 assigned to QA-RELAY-020258-853b20"
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
        "details": "Prototyped HR Emploc assignment with employee_no EMP-RELAY-020258-c99967"
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
    "executed_at": "2026-11-13T02:02:58.934321+00:00"
  }
  ```

### 2.6 Live Multi-Scenario Execution
Executed remaining 5 scenarios (`VAC_ARCHIVE_001`, `PLANTILLA_001`, `HR_EMPLOC_001`, `CENCOM_001`, `AUTH_MATRIX_001`):
All 5 returned `success: true` and `sandbox_rolled_back: true`.

### 2.7 Zero-Pollution Table Verification
Query executed against live Staging tables after running all scenarios:
```sql
SELECT 
  (SELECT count(*) FROM public.vacancies WHERE vcode LIKE 'QA-%') AS vac_count,
  (SELECT count(*) FROM public.plantilla WHERE vcode LIKE 'QA-%' OR employee_no LIKE 'EMP-RELAY-%' OR employee_no LIKE 'QA-EMP-%') AS plan_count,
  (SELECT count(*) FROM public.applicants WHERE vacancy_vcode LIKE 'QA-%') AS app_count,
  (SELECT count(*) FROM public.hr_emploc WHERE vcode LIKE 'QA-%' OR employee_no LIKE 'EMP-RELAY-%' OR employee_no LIKE 'EMP-QA-%') AS emploc_count,
  (SELECT count(*) FROM public.users_profile WHERE email LIKE '%@ohmployee.internal') AS users_count;
```
Result:
`[{"vac_count": 0, "plan_count": 0, "app_count": 0, "emploc_count": 0, "users_count": 0}]`  
**Zero simulation rows exist in live operational tables.**

### 2.8 Telemetry Persistence Verification
Queried `public.qa_agent_runs` for run `9e0b75ea-35a2-4c96-af2a-74731943f519`:
- Status: `'completed'`
- Summary: `'Scenario FULL_E2E_RELAY passed cleanly in sandbox with zero data pollution.'`
- Step count: 7 passed steps preserved in `metadata->'steps'`.
- Rolled back: `true`.

---

## 3. Adversarial Challenges & Stress-Testing

### Challenge 1: Authorization Bypass by Low-Privilege Callers
- **Assumption Challenged**: Does `qa_run_scenario` genuinely enforce role restrictions against non-admin callers?
- **Attack Scenario**: Simulated an Operations Manager (`role_level = 70 < 90`, `auth_user_id = '54935b05-65a1-48aa-b953-15e6c756e80e'`) attempting to call `public.qa_run_scenario('FULL_E2E_RELAY')`.
- **Observed Behavior**: The function threw exception `Only Head Admin or Super Admin can execute QA scenarios` at Step 1 before any simulation or telemetry logic could execute.
- **Outcome**: **PASS** (Zero vulnerability).

### Challenge 2: Search Path Hijacking in SECURITY DEFINER Function
- **Assumption Challenged**: Could a malicious schema intercept function resolution?
- **Attack Scenario**: Investigated function definition for unqualified object calls.
- **Observed Defense**: The function explicitly specifies `SET search_path TO 'public'` (line 14), and all object references explicitly qualify schema `public.` (`public.vacancies`, `public.qa_start_detection_run`, `public.get_my_role_level`).
- **Outcome**: **PASS** (Standard PostgreSQL security definer lock implemented).

### Challenge 3: Negative Barrier False Alarm vs False Negative
- **Assumption Challenged**: Does Step 7 accurately test the negative barrier without false positives or false negatives?
- **Analysis**:
  - In `20262606000045`, Step 7 produced a false-positive leak alarm because `request.jwt.claim.sub` was not updated, leaving `auth.uid()` set to Head Admin.
  - In `20262606000106`, `request.jwt.claim.sub` is updated to `v_bo_uid`.
  - When `get_my_role_level()` runs, it resolves Back Office (level 15).
  - `i_have_full_access()` checks `role_level >= 90`, evaluating to `false`.
  - Step 7 reports `Permission barrier held firm: Back Office restricted from admin actions`.
  - If a real authorization leak existed (e.g., if Back Office had level >= 90), `v_leak_detected` would evaluate to `true`, log a critical finding, and mark the simulation failed.
- **Outcome**: **PASS** (Accurate negative boundary testing).

---

## 4. 5-Component Handoff Protocol

### 1. Observation
- Migration file `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` contains 676 lines.
- Defines `public.qa_run_scenario(text)` with `SECURITY DEFINER` and `SET search_path TO 'public'`.
- Chained checks pass: `npm run check:adr` (FRESH), `npm run check:sql` (631 migrations OK), `npm run lint` (0 errors), `npm test` (211/211 tests pass).
- Live execution on Staging (`qqiiznmqxfoamqytjica`): `FULL_E2E_RELAY` run `9e0b75ea-35a2-4c96-af2a-74731943f519` completed with 7 passed steps, 0 findings, `sandbox_rolled_back: true`.
- Zero live table pollution confirmed across `vacancies`, `plantilla`, `applicants`, `hr_emploc`, `users_profile`.
- Unauthorized caller test confirmed hard block.

### 2. Logic Chain
1. In PostgreSQL with Supabase Auth, `auth.uid()` derives primarily from `request.jwt.claim.sub`. Synchronously setting `request.jwt.claim.sub`, `request.jwt.claim.role`, and `request.jwt.claims` guarantees that both `auth.uid()` and `get_my_role_level()` reflect the simulated actor.
2. Defensive restoration caches the original JWT GUCs at entry and re-applies them post-rollback with Head Admin fallback, completely preventing Back Office residue from persisting into subsequent queries.
3. Wrapping operational mutations in an atomic PL/pgSQL subtransaction ending with `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'` ensures that all table inserts and trigger cascades are rolled back by the database engine.
4. Logging findings and run completion outside the subtransaction guarantees telemetry persistence in `qa_agent_runs` and `qa_agent_findings` without keeping any mock data in operational tables.

### 3. Caveats
- No caveats. The migration is fully verified on Staging and passes all contract tests.
- Note for Milestone 2: `public.qa_run_scenario` defaults to `'FULL_E2E_RELAY'` if an empty string or null is provided, but frontend query hooks should pass `'FULL_E2E_RELAY'` explicitly.

### 4. Conclusion
Migration `20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` fully meets all security, isolation, and functional requirements of Milestone 1. Verdict is **APPROVE**.

### 5. Verification Method
To independently verify:
```powershell
# 1. Run codebase checks
npm run check:adr
npm run check:sql
npm run lint
npm test

# 2. Run scenario on Staging via Supabase SQL
SELECT set_config('request.jwt.claim.sub', '71d245b9-10b1-42b9-ad9e-253f999daf6d', false);
SELECT set_config('request.jwt.claim.role', 'authenticated', false);
SELECT set_config('request.jwt.claims', '{"sub":"71d245b9-10b1-42b9-ad9e-253f999daf6d","role":"authenticated"}', false);
SELECT public.qa_run_scenario('FULL_E2E_RELAY');

# 3. Verify zero live table pollution
SELECT count(*) FROM public.vacancies WHERE vcode LIKE 'QA-%';
SELECT count(*) FROM public.plantilla WHERE vcode LIKE 'QA-%';
SELECT count(*) FROM public.applicants WHERE vacancy_vcode LIKE 'QA-%';
SELECT count(*) FROM public.hr_emploc WHERE vcode LIKE 'QA-%';
```
All counts must equal `0`.
