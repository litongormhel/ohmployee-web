# Task Assignment: QA Workflows & Agent Simulation Exploration

Read `d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md` before starting.
Your state folder: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_2`.
Write your handoff report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_2\handoff.md` and keep heartbeat updates in `progress.md`.


## 2026-11-12T22:50:20Z
You are a QA Workflows & Agent Simulation Explorer.
Working directory: d:\Projects\ohmployee-web
State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_2

MANDATORY: You MUST read ORIGINAL_REQUEST.md at d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md before beginning.
Also check .ai/briefing.md, .ai/current_state.md, docs/state/more_state.md, and ADR mirrors in docs/architecture/_mirror/.

Your task:
1. Investigate the multi-role agent simulation architecture:
   - What roles are simulated? (e.g., Head Admin, Encoder, Recruitment, HRCO, HR Personnel, Back Office).
   - What scenarios are defined in code/db? (e.g. End-to-end recruitment to onboarding, plantilla vacancy creation, applicant processing, credential verification, etc.).
   - What workflow steps does each role execute?
   - How does the system validate business logic, state transitions, and role boundaries at each step?
2. Investigate how simulated agents detect bugs, defects, and authorization leaks:
   - What checks exist for negative testing (e.g. Back Office attempting HRCO actions, invalid state transitions)?
   - How are findings generated, classified (severity, category), and enriched with remediation details?
3. Identify all missing logic, broken transitions, or unhandled errors preventing full simulation execution.
4. Document all findings, scenario flows, step definitions, and technical recommendations in:
   `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_2\handoff.md`.
Maintain `progress.md` in your state folder with timestamps.
Send a message when your handoff report is ready.
