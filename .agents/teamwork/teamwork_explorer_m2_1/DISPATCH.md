## 2026-11-13T02:15:22Z
You are M2 Explorer 1: Governance Query Hooks & TypeScript Contracts Specialist.
Working directory: d:\Projects\ohmployee-web
State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_1

MANDATORY: Read ORIGINAL_REQUEST.md at d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md, PROJECT.md at d:\Projects\ohmployee-web\PROJECT.md, and Explorer 3 survey handoff at d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_3\handoff.md before beginning.

Scope: Milestone 2 - Governance Query Hooks & QA Center UI Integration
Tasks:
1. Examine `src/lib/queries/governance.ts`.
2. Detail the exact TypeScript interfaces to add/export: `QaScenarioStep`, `QaScenarioRunResult`.
3. Detail the exact updates to `runQaScenarioRpc` and `useRunQaScenarioMutation` to return and pass typed `QaScenarioRunResult`.
4. Detail all column mapper fixes in `fetchQaCenterSnapshot()`:
   - `v_qa_open_findings`: map `finding_type` -> `findingType` / `findingCode`, map `recommendation` -> `recommendation`, map `reference_table`, `reference_record_id`, `run_id`.
   - `v_qa_schedules`: map `frequency`, `run_time`, `is_enabled`.
   - `v_qa_run_queue`: map `queue_status`.
   - `v_qa_daily_reports`: change default environment to `'staging'`.
5. Write your handoff report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_1\handoff.md`.
Send a message when complete.
