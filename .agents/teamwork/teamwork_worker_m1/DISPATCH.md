# Task Assignment: Milestone 1 Worker - Database Migration Implementation

Read `d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md` and `d:\Projects\ohmployee-web\PROJECT.md` before starting.
Your state folder: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_worker_m1`.
Review Explorer findings at:
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1\handoff.md`
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1\proposed_migration.sql`
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_2\handoff.md`
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_3\handoff.md`

Your tasks:
1. Create migration file:
   `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`
   implementing the surgical diff for `public.qa_run_scenario` (dual GUC impersonation, status check constraints, collision-proof IDs, metadata steps persistence, defensive JWT restoration).
2. Run `npm run check:sql` and `npm run check:adr` to verify physical schema contracts and ADR invariants.
3. Write your completion report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_worker_m1\handoff.md`.


## 2026-11-13T01:23:27Z
You are M1 Database Migration Worker.
Working directory: d:\Projects\ohmployee-web
State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_worker_m1

MANDATORY: You MUST read ORIGINAL_REQUEST.md at d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md and PROJECT.md at d:\Projects\ohmployee-web\PROJECT.md before beginning.

Review the Explorer findings and proposed code:
- Explorer 1 handoff & proposed SQL: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1\handoff.md and d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1\proposed_migration.sql
- Explorer 2 handoff: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_2\handoff.md
- Explorer 3 handoff: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_3\handoff.md

Write Ownership:
You exclusively own: `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`.
Do NOT edit any frontend or typescript files in this milestone.

Scope & Tasks:
1. Create `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` containing the full, surgical `CREATE OR REPLACE FUNCTION public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY'::text)` with:
   - Setting both `request.jwt.claim.sub` AND `request.jwt.claims` (and `request.jwt.claim.role`) during role impersonation across all 6 roles.
   - Symmetrically caching `v_orig_jwt`, `v_orig_sub`, `v_orig_role` at entry and restoring them upon sandbox exit, with fallback to `v_ha_uid` so subsequent calls to `qa_complete_detection_run` never crash.
   - Fixing `hr_emploc.status` to `'Pending Emploc'` (Step 5 & HR_EMPLOC_001) to satisfy `hr_emploc_status_check`.
   - Fixing `plantilla.status` in `PLANTILLA_001` to `'Resigned'` and `separation_status = 'Resigned'` to satisfy `plantilla_status_check`.
   - Collision-proofing synthetic test actors in `users_profile` with randomized unique names/emails.
   - Collision-proofing `vcode` and `employee_no` with random UUID suffixes.
   - Persisting full `v_steps` json array into `public.qa_agent_runs.metadata`.
2. Run SQL contract and ADR verification commands:
   `npm run check:sql`
   `npm run check:adr`
   Verify that all contracts pass cleanly with 0 errors.
3. Write a comprehensive completion handoff report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_worker_m1\handoff.md`. Include verbatim command outputs.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Send a message when your handoff report is ready.
