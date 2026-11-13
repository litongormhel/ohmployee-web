## 2026-11-13T02:33:31Z
You are M2 UI & Query Hooks Worker.
Working directory: d:\Projects\ohmployee-web
State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_worker_m2

MANDATORY: Read ORIGINAL_REQUEST.md at d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md and PROJECT.md at d:\Projects\ohmployee-web\PROJECT.md before beginning.

Review Explorer reports:
- M2 Explorer 1 handoff: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_1\handoff.md
- M2 Explorer 2 handoff: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_2\handoff.md
- M2 Explorer 3 handoff: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_3\handoff.md

Write Ownership:
You exclusively own:
- `src/lib/queries/governance.ts`
- `src/components/more/QaCenterModal.tsx`
- Any new child components in `src/components/more/qa/` (e.g. `QaStepTimeline.tsx`, `QaSimulationRunner.tsx`, `QaFindingsViewer.tsx`, `QaRunHistoryTable.tsx`)

Scope & Tasks:
1. Update `src/lib/queries/governance.ts`:
   - Export `QaScenarioStep` and `QaScenarioRunResult` interfaces.
   - Type `runQaScenarioRpc` to return `Promise<QaScenarioRunResult>` with safe parsing of steps array and finding counts.
   - Update `useRunQaScenario` / `useRunQaScenarioMutation`.
   - Fix column mappings in `fetchQaCenterSnapshot()`:
     * `v_qa_open_findings`: map `finding_type` -> `findingType` / `findingCode`, map `recommendation`, `reference_table`, `reference_record_id`, `run_id`.
     * `v_qa_schedules`: map `frequency`, `run_time`, `is_enabled` / `isActive`.
     * `v_qa_run_queue`: map `queue_status` -> `status`.
     * `v_qa_daily_reports`: align default environment to `'staging'`.
     * `v_qa_detection_run_summary`: map `summary`.
   - Change default environment in `generateDailyQaReportRpc` from `"production"` to `'staging'`.
2. Update `src/components/more/QaCenterModal.tsx` and subcomponents:
   - Add `{ code: "FULL_E2E_RELAY", label: "Full 6-Role Workflow Relay" }` to `COMMON_SCENARIOS` at index 0 and default to it.
   - In `handleRunScenario`, capture the returned mutation result in `lastScenarioResult` state.
   - Check `res.success`: if false, display `Scenario ${selectedScenario} completed with failures/findings. Check details.` instead of false positive success toast.
   - Render the Atomic Sandbox Rollback status badge (`QA_SANDBOX_ROLLBACK_SUCCESS` - Zero data pollution confirmed).
   - Render the 7-step Agent Step Timeline with role badges (`Head Admin`, `Encoder`, `Recruitment`, `HRCO`, `HR Personnel`, `Back Office`), action names, status pills (passed in emerald, failed in rose), and execution details.
   - In the Findings tab, render actual defect code (`finding_type`), semantic severity badges, and actionable remediation callout (`recommendation`).
   - In the Runs table, display run summary, sandbox rollback status, and steps count.
3. Verification:
   Run `npm run check:sql`
   Run `npm run check:adr`
   Run `npm run lint`
   Run `npm test`
   Run `npm run build`
   Ensure 0 lint errors, 211 tests passing, and build succeeds with exit code 0.
4. Write your completion report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_worker_m2\handoff.md`.
