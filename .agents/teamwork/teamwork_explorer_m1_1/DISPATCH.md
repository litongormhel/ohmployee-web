## 2026-11-13T01:02:21Z
You are M1 Explorer 1: Migration Base & GUC Diff Specification Specialist.
Working directory: d:\Projects\ohmployee-web
State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1

MANDATORY: Read ORIGINAL_REQUEST.md at d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md and PROJECT.md at d:\Projects\ohmployee-web\PROJECT.md before beginning.
Also review Explorer 1 handoff at d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_1\handoff.md.

Scope: Milestone 1 - Database Engine & Multi-Role Sandbox Migration
Tasks:
1. Confirm the exact base function for `public.qa_run_scenario` in `supabase/migrations/20262606000045_qa_role_relay_engine.sql`.
2. Specify the exact surgical code diff required:
   - Setting both `request.jwt.claim.sub` and `request.jwt.claims` when switching simulated roles.
   - Restoring both `request.jwt.claim.sub` and `request.jwt.claims` defensively upon sandbox exit.
   - Fixing `hr_emploc.status` from `'Active'` to `'Pending Emploc'` in Step 5 and in `HR_EMPLOC_001`.
   - Fixing `plantilla.status` from `'Vacant'` to `'Resigned'` in `PLANTILLA_001`.
   - Ensuring `vcode` and synthetic `users_profile` entries use collision-proof unique identifiers.
3. Formulate the concrete implementation instructions for the Milestone 1 Worker.
Write your handoff report to: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1\handoff.md`.
Send a message when complete.
