# Original User Request

## Initial Request — 2026-11-12T22:43:11Z

Audit and ensure the QA Agents simulation feature in the More Module (QA Center) is fully functional as a production feature, executing logic and workflow checks across roles in an atomic rollback sandbox with telemetry logged to QA tables without polluting real data, and reporting pass/fail outcomes and bugs.

Integrity mode: development

## Requirements

### R1. Audit Existing QA Simulation Architecture
Audit the current QA agent implementation, including the More Module QA Center UI (`src/components/more/QaCenterModal.tsx`), query hooks (`src/lib/queries/governance.ts`), and database functions/telemetry (`public.qa_run_scenario`, `public.qa_agent_runs`, `public.qa_agent_findings`), to identify root causes preventing simulations from executing or reporting results.

### R2. End-to-End Multi-Role Workflow Simulation Execution
Ensure that running a simulation triggers the simulated agents to execute their end-to-end workflow sequence across roles (e.g., Head Admin, Encoder, Recruitment, HRCO, HR Personnel, Back Office), validating business logic, state transitions, and role boundaries at each step.

### R3. Atomic Sandbox Isolation & Zero Data Pollution
Ensure that all simulated operational data mutations are confined strictly to an atomic transaction/subtransaction that rolls back cleanly upon completion (`QA_SANDBOX_ROLLBACK_SUCCESS`), guaranteeing zero mock or leftover records in live application tables on staging or production.

### R4. Telemetry Logging and Bug Reporting
Persist simulation run summaries, step-by-step statuses, and detected bugs or permission anomalies to `public.qa_agent_runs` and `public.qa_agent_findings`, and surface them clearly (pass/fail status, execution details, and findings) in the QA Center web interface.

## Acceptance Criteria

### Simulation Execution & UI
- [ ] Executing a simulation scenario from the QA Center modal in More Module runs the multi-role agent sequence to completion without unhandled errors.
- [ ] Each agent workflow step displays its outcome (pass/fail) and descriptive details in the UI.
- [ ] Detected workflow defects or authorization leaks are logged as findings with severity, category, and actionable remediation details.

### Sandbox & Isolation Verification
- [ ] After simulation execution, live operational tables (`vacancies`, `plantilla`, `applicants`, `hr_emploc`) contain no temporary or mock simulation records.
- [ ] The simulation run record is successfully saved in `public.qa_agent_runs` with status, duration, and finding counts.

### Environment Safety
- [ ] All database changes and verification are performed strictly against the Staging environment (`qqiiznmqxfoamqytjica`); Production (`rwxelulyapjgaarlwkus`) remains completely untouched.
- [ ] Database function updates adhere to the SQL function surgical-diff rules and pass `npm run check:sql`.
