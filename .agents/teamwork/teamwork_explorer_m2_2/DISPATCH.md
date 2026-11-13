# Task Assignment: M2 Explorer 2 - Simulation Runner & Step Timeline UI Specification

Read `d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md`, `d:\Projects\ohmployee-web\PROJECT.md`, and `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_3\handoff.md` before starting.
Your state folder: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_2`.
Deliver your report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_2\handoff.md`.


## 2026-11-13T02:15:52Z
You are M2 Explorer 2: Simulation Runner & Step Timeline UI Specialist.
Working directory: d:\Projects\ohmployee-web
State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_2

MANDATORY: Read ORIGINAL_REQUEST.md at d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md, PROJECT.md at d:\Projects\ohmployee-web\PROJECT.md, and Explorer 3 survey handoff at d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_3\handoff.md before beginning.

Scope: Milestone 2 - Governance Query Hooks & QA Center UI Integration
Tasks:
1. Examine `src/components/more/QaCenterModal.tsx`.
2. Detail how to add `{ code: "FULL_E2E_RELAY", label: "Full 6-Role Workflow Relay" }` to `COMMON_SCENARIOS` and set it as default.
3. Detail how `handleRunScenario` must capture the returned mutation payload into `lastScenarioResult` state.
4. Detail the UI component design for:
   - Atomic Sandbox Rollback status badge (`QA_SANDBOX_ROLLBACK_SUCCESS` - Zero data pollution confirmed).
   - Agent Step Timeline: rendering all 7 steps with step number, role badge (Head Admin, Encoder, Recruitment, HRCO, HR Personnel, Back Office), action name, status pill (passed/failed in green/red), and execution details.
   - Defect count and quick link to findings.
5. Write your handoff report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_2\handoff.md`.
Send a message when complete.
