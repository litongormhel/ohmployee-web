# Task Assignment: M1 Reviewer 2 - Security & Sandbox Isolation Review

Read `d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md`, `d:\Projects\ohmployee-web\PROJECT.md`, and `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_worker_m1\handoff.md`.
Your state folder: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_reviewer_m1_2`.
Examine `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`.
Evaluate dual GUC setting, rollback isolation, and telemetry persistence.
Deliver your review report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_reviewer_m1_2\handoff.md` with explicit verdict (APPROVE or REQUEST_CHANGES).


## 2026-11-13T01:53:21Z
You are M1 Reviewer 2: Security & Sandbox Isolation Reviewer.
Working directory: d:\Projects\ohmployee-web
State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_reviewer_m1_2

MANDATORY: Read ORIGINAL_REQUEST.md at d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md, PROJECT.md at d:\Projects\ohmployee-web\PROJECT.md, and M1 Worker handoff at d:\Projects\ohmployee-web\.agents\teamwork\teamwork_worker_m1\handoff.md before beginning.

Scope: Review `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`.
Tasks:
1. Review the security architecture:
   - Does setting `request.jwt.claim.sub` + `request.jwt.claims` + `request.jwt.claim.role` accurately switch the context of `auth.uid()` and `get_my_role_level()`?
   - Does the defensive restoration prevent JWT leaks to Back Office?
   - Is atomic rollback via `QA_SANDBOX_ROLLBACK_SUCCESS` strictly isolated from live operational tables?
   - Are findings logged with valid severities and status?
2. Run `npm test` and `npm run lint` independently.
3. Deliver your review report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_reviewer_m1_2\handoff.md` with explicit verdict (APPROVE or REQUEST_CHANGES).
Send a message when complete.
