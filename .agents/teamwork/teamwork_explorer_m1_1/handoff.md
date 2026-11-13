# Milestone 1: Database Engine & Multi-Role Sandbox Migration Specification Report
**Milestone**: M1 - Database Engine & Multi-Role Sandbox Migration  
**State Folder**: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1`  
**Date**: 2026-11-13T01:15:00Z  
**Author**: M1 Explorer 1 (Migration Base & GUC Diff Specification Specialist)

---

## 1. Observation

### 1.1 Base Migration and Function Signature
- **Base Migration File**: `supabase/migrations/20262606000045_qa_role_relay_engine.sql`
- **Function Signature** (lines 7–12):
  ```sql
  CREATE OR REPLACE FUNCTION public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY'::text)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  ```
- **Uniqueness Check**: Executing `git grep -n "qa_run_scenario" supabase/migrations/` confirms that `20262606000045_qa_role_relay_engine.sql` is the sole migration defining `public.qa_run_scenario`.
- **Latest Migration In Tree**: `20262606000105_fix_approve_plantilla_import_batch_store_columns.sql`. The next sequential migration is `20262606000106_qa_run_scenario_dual_guc_and_constraint_fixes.sql`.

### 1.2 GUC Role Impersonation Flaws
- In `20262606000045_qa_role_relay_engine.sql` lines 316, 334, 352, 369, 386, 403, role switching was attempted using:
  ```sql
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_encoder_uid::text, 'role', 'authenticated'
  )::text, true);
  ```
- In `supabase/migrations/20260520012857_remote_schema.sql` (and Supabase core auth), `auth.uid()` reads `request.jwt.claim.sub` (`current_setting('request.jwt.claim.sub', true)`).
- Because `request.jwt.claim.sub` was never set, `auth.uid()` continued resolving to the initial caller UID (Head Admin).
- In `supabase/migrations/20260527000000_unify_role_level_source.sql` lines 84–90, `get_my_role_level()` invokes `get_effective_role()`, which queries:
  ```sql
  SELECT r.role_name INTO v_role
  FROM public.users_profile up
  LEFT JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid() AND coalesce(up.is_active, true)
  LIMIT 1;
  ```
- Consequently, in Step 7 (Negative Barrier Probe lines 421–425):
  ```sql
  IF (public.i_have_full_access() OR public.get_my_role_level() >= 90) THEN
    v_leak_detected := true;
  ```
  `get_my_role_level()` evaluated to 90 instead of 15 (Back Office), triggering a false positive `v_leak_detected := true`, causing Step 7 and the entire scenario run to fail with:
  `CRITICAL LEAK: Back Office impersonation satisfied admin access guard!`.

### 1.3 JWT Context Poisoning & Post-Sandbox Crash
- In `20262606000045_qa_role_relay_engine.sql` lines 467–469:
  ```sql
  IF v_orig_jwt IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
  END IF;
  ```
- `request.jwt.claim.sub` was not restored, and if `v_orig_jwt` was unset (e.g. running in test runner or psql), `request.jwt.claims` remained stuck on the simulated Back Office user.
- Lines 501–507 call `public.qa_complete_detection_run`, which checks:
  ```sql
  IF NOT (i_have_full_access() OR get_my_role_level() >= 90) THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can complete QA detection runs';
  END IF;
  ```
- Because the context was poisoned by Back Office impersonation (level 15), `qa_complete_detection_run` crashed with an unhandled exception outside the subtransaction, rolling back telemetry in `qa_agent_runs` and terminating the HTTP RPC with a 500 error.

### 1.4 Physical Check Constraint Violations
- **`hr_emploc.status`**:
  - `20260520012857_remote_schema.sql:2851`:
    ```sql
    CHECK ((status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'Ready for Plantilla'::text, 'Pending Approval'::text, 'Moved to Plantilla'::text, 'In Review'::text, 'Complete'::text, 'Ready for Deployment'::text, 'Backout'::text])))
    ```
  - In `20262606000045_qa_role_relay_engine.sql:239` (`HR_EMPLOC_001`) and line 391 (`FULL_E2E_RELAY` Step 5), status was hardcoded as `'Active'`, directly raising `check_violation`.
- **`plantilla.status`**:
  - `20260520012857_remote_schema.sql:2975`:
    ```sql
    CHECK ((status = ANY (ARRAY['Active'::text, 'Inactive'::text, 'For Deactivation'::text, 'Deactivated'::text, 'Resigned'::text, 'Transferred'::text, 'On Leave'::text])))
    ```
  - In `20262606000045_qa_role_relay_engine.sql:222` (`PLANTILLA_001`), status was updated to `'Vacant'`, directly raising `check_violation`.

### 1.5 Identifier Collisions on Test Actors and Vacancies
- **`users_profile` Unique Constraints**:
  - `20260520012857_remote_schema.sql:2341`: `users_profile_auth_user_id_key UNIQUE (auth_user_id)`
  - `20260520012857_remote_schema.sql:2343`: `users_profile_email_key UNIQUE (email)`
  - `20260520012857_remote_schema.sql:2345`: `users_profile_full_name_key UNIQUE (full_name)`
  - Lines 88–154 inserted hardcoded values like `'QA Test Encoder'` and `'qa_encoder@ohmployee.internal'`, creating repeated risk of `unique_violation`.
- **`vacancies.vcode` Unique Constraint**:
  - `20260520012857_remote_schema.sql:3405`: `vacancies_vcode_key UNIQUE (vcode)`
  - `to_char(now(), 'HH24MISS')` has 1-second resolution, creating collisions under rapid or concurrent executions.

---

## 2. Logic Chain

1. **Dual GUC Alignment**:
   - `auth.uid()` reads `request.jwt.claim.sub`. PostgREST reads `request.jwt.claims`. Other RLS policies check `request.jwt.claim.role`.
   - Setting all three GUCs synchronously inside the simulation ensures `auth.uid()`, `get_effective_role()`, and `get_my_role_level()` evaluate to the exact simulated actor level at each step (Head Admin=90, Encoder=30, Recruitment=20, HRCO=45, HR Personnel=25, Back Office=15).
   - This allows Step 7 (Negative Barrier Probe) to accurately observe `get_my_role_level() = 15 < 90`, correctly proving the security boundary holds firm and preventing false positive leak alarms.

2. **Defensive Sandbox Exit Restoration**:
   - Caching `v_orig_jwt := current_setting('request.jwt.claims', true)`, `v_orig_sub := current_setting('request.jwt.claim.sub', true)`, and `v_orig_role := current_setting('request.jwt.claim.role', true)` at entry, and restoring all three at sandbox exit, prevents JWT context leakage.
   - Adding a fallback to `v_ha_uid` (Head Admin actor) if `v_orig_sub` was NULL ensures test harnesses or SQL runners do not trigger the `role_level >= 90` guard in `qa_complete_detection_run`.

3. **Status Constraint Corrections**:
   - In `hr_emploc`, replacing `'Active'` with `'Pending Emploc'` matches both the column's default value (`default 'Pending Emploc'::text`) and the allowed values in `hr_emploc_status_check`.
   - In `plantilla`, replacing `'Vacant'` with `'Resigned'` and setting `separation_status = 'Resigned'` complies with `plantilla_status_check` while triggering standard separation lifecycle triggers.

4. **Collision-Proof Test Data**:
   - Appending `clock_timestamp()` and `substr(gen_random_uuid()::text, 1, 6)` to `vcode` and `employee_no` eliminates duplicate key errors.
   - Appending `substr(v_uid::text, 1, 8)` to synthetic `full_name` and `email` ensures synthetic test actors never collide with existing user profiles or concurrent sandbox runs.

5. **Telemetry Persistence**:
   - Executing `UPDATE public.qa_agent_runs SET metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('steps', v_steps) WHERE id = v_run_id;` immediately before completing the run preserves the full step-by-step audit trail in `qa_agent_runs.metadata`.

---

## 3. Caveats
- No direct database writes or migration creations were made during this investigation (strictly read-only per Teamwork Explorer rules).
- The exact proposed SQL file has been authored into our state folder at `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1\proposed_migration.sql` for the Milestone 1 Worker to apply.
- No other caveats.

---

## 4. Conclusion & Concrete Implementation Instructions for Milestone 1 Worker

### 4.1 Migration File Destination
Create the migration file:
`supabase/migrations/20262606000106_qa_run_scenario_dual_guc_and_constraint_fixes.sql`

### 4.2 Exact Surgical Diff Specification

#### Diff 1: Declare original GUC caching variables
```sql
<<<< BASE (lines 14-25)
  v_orig_jwt text;
  v_code text;
  v_run_id uuid;
==== PROPOSED
  v_orig_jwt text;
  v_orig_sub text;
  v_orig_role text;
  v_code text;
  v_run_id uuid;
>>>>
```

#### Diff 2: Cache caller GUCs at entry
```sql
<<<< BASE (lines 48-52)
  v_orig_jwt := current_setting('request.jwt.claims', true);
  v_caller_profile_id := public.get_current_profile_id();
==== PROPOSED
  v_orig_jwt := current_setting('request.jwt.claims', true);
  v_orig_sub := current_setting('request.jwt.claim.sub', true);
  v_orig_role := current_setting('request.jwt.claim.role', true);
  v_caller_profile_id := public.get_current_profile_id();
>>>>
```

#### Diff 3: Collision-proof synthetic actor generation
Ensure synthetic `full_name` and `email` append `substr(v_uid::text, 1, 8)`:
```sql
<<<< BASE (lines 88-90)
        INSERT INTO public.users_profile (id, auth_user_id, full_name, email, role_id, role, is_active)
        VALUES (gen_random_uuid(), v_encoder_uid, 'QA Test Encoder', 'qa_encoder@ohmployee.internal', v_role_id, 'Encoder', true);
==== PROPOSED
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
>>>>
```
(Apply symmetrically to Recruiter, HRCO, HR Personnel, and Back Office).

#### Diff 4: Fix `PLANTILLA_001` status transition
```sql
<<<< BASE (lines 221-224)
      UPDATE public.plantilla
      SET status = 'Vacant', resignation_date = CURRENT_DATE
      WHERE id = v_test_plantilla_id;
==== PROPOSED
      UPDATE public.plantilla
      SET status = 'Resigned',
          separation_status = 'Resigned',
          resignation_date = CURRENT_DATE
      WHERE id = v_test_plantilla_id;
>>>>
```

#### Diff 5: Fix `HR_EMPLOC_001` status
```sql
<<<< BASE (lines 238-240)
      INSERT INTO public.hr_emploc (id, applicant_name, vcode, account, position, employee_no, status)
      VALUES (gen_random_uuid(), 'QA Sync Applicant', v_vcode, 'QA Test Account', 'QA Staff', v_emp_no, 'Active')
      RETURNING id INTO v_test_emploc_id;
==== PROPOSED
      INSERT INTO public.hr_emploc (id, applicant_name, vcode, account, position, employee_no, status)
      VALUES (gen_random_uuid(), 'QA Sync Applicant', v_vcode, 'QA Test Account', 'QA Staff', v_emp_no, 'Pending Emploc')
      RETURNING id INTO v_test_emploc_id;
>>>>
```

#### Diff 6: Dual GUC impersonation in `FULL_E2E_RELAY` steps
For each role in the sequence (Role 1 to Role 6), execute:
```sql
PERFORM set_config('request.jwt.claim.sub', <actor_uid>::text, true);
PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
PERFORM set_config('request.jwt.claims', jsonb_build_object(
  'sub', <actor_uid>::text, 'role', 'authenticated'
)::text, true);
```

#### Diff 7: Fix `FULL_E2E_RELAY` Step 5 `hr_emploc.status`
```sql
<<<< BASE (lines 390-392)
      INSERT INTO public.hr_emploc (id, applicant_name, vcode, account, position, employee_no, status, applicant_id, vacancy_id)
      VALUES (gen_random_uuid(), 'Jane Relay Doe', v_vcode, 'QA Relay Account', 'Relay Specialist', v_emp_no, 'Active', v_test_applicant_id, v_test_vacancy_id)
      RETURNING id INTO v_test_emploc_id;
==== PROPOSED
      INSERT INTO public.hr_emploc (id, applicant_name, vcode, account, position, employee_no, status, applicant_id, vacancy_id)
      VALUES (gen_random_uuid(), 'Jane Relay Doe', v_vcode, 'QA Relay Account', 'Relay Specialist', v_emp_no, 'Pending Emploc', v_test_applicant_id, v_test_vacancy_id)
      RETURNING id INTO v_test_emploc_id;
>>>>
```

#### Diff 8: Defensive JWT restoration upon sandbox exit
```sql
<<<< BASE (lines 466-470)
  IF v_orig_jwt IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', v_orig_jwt, true);
  END IF;
==== PROPOSED
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
>>>>
```

#### Diff 9: Persist full step telemetry in `qa_agent_runs.metadata`
```sql
  -- Persist step telemetry into qa_agent_runs metadata for auditability
  UPDATE public.qa_agent_runs
  SET metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('steps', v_steps)
  WHERE id = v_run_id;
```

---

## 5. Verification Method

1. **Verify ADR Invariants**:
   ```powershell
   npm run check:adr
   ```
   Must report `ADR_MIRROR_STATUS: FRESH`.

2. **Verify SQL Schema & Cross-Module Contracts**:
   ```powershell
   npm run check:sql
   ```
   Must report `SQL_CONTRACTS_OK` verifying 28 core tables & 19 cross-module RPC contracts across all migrations.

3. **Verify Staging Environment Link**:
   Ensure `.env` and `supabase/.temp/project-ref` point to Staging (`qqiiznmqxfoamqytjica`) and never Production (`rwxelulyapjgaarlwkus`).

4. **Verify Scenario Execution via RPC**:
   Execute `SELECT public.qa_run_scenario('FULL_E2E_RELAY');` in Staging database.
   Verify returned JSON:
   - `success: true`
   - `sandbox_rolled_back: true`
   - `steps` contains 7 passed steps
   - `qa_agent_runs` has 1 completed run with `steps` in metadata
   - `vacancies`, `plantilla`, `applicants`, `hr_emploc` contain 0 records created by the run.

---

## Next Steps
1. Hand off this specification and `proposed_migration.sql` to Milestone 1 Worker.
2. Present the approval gate plan to user prior to authoring the migration file.
3. Worker creates `supabase/migrations/20262606000106_qa_run_scenario_dual_guc_and_constraint_fixes.sql` using the verbatim code from `proposed_migration.sql`.

> [!TIP]
> Setting both `request.jwt.claim.sub` and `request.jwt.claims` is the canonical technique for multi-role simulation in Supabase, guaranteeing that `auth.uid()` and `get_my_role_level()` evaluate simultaneously without session drift.
