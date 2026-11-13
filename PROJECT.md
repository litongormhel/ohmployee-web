# Project: QA Agents Simulation & Production Readiness in More Module

## Architecture
- **Database Engine**: `public.qa_run_scenario(p_scenario_code)` executing within a PL/pgSQL savepoint (`BEGIN ... EXCEPTION ... END` + `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`). Rolls back 100% of operational mutations (`vacancies`, `plantilla`, `applicants`, `hr_emploc`) and trigger side-effects while persisting run telemetry in `qa_agent_runs` and findings in `qa_agent_findings`.
- **Telemetry Layer**: Functions `qa_start_detection_run`, `qa_log_detection_finding`, `qa_complete_detection_run`, and views `v_qa_detection_run_summary`, `v_qa_open_findings`, `v_qa_schedules`, `v_qa_run_queue`, `v_qa_unstable_modules`, `v_qa_flaky_tests`, `v_qa_daily_reports`.
- **Client & Hook Layer**: `src/lib/queries/governance.ts` typing and invoking `qa_run_scenario`, fetching `v_qa_*` views with accurate column mappings.
- **Presentation Layer**: `src/components/more/QaCenterModal.tsx` and child components (`QaSimulationRunner`, `QaStepTimeline`, `QaRunHistoryTable`, `QaFindingsViewer`) rendering scenario selection, execution progress, role badges, step outcomes, atomic rollback verification, and actionable defect recommendations.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | Atomic Sandbox Rollback & Zero Pollution | Operational data mutations in `vacancies`, `plantilla`, `applicants`, `hr_emploc` roll back atomically with `QA_SANDBOX_ROLLBACK_SUCCESS`. | M1 | Survey (Explorer 1) |
| F2 | Dual GUC Impersonation Fix | Set both `request.jwt.claim.sub` and `request.jwt.claims` so `auth.uid()` and `get_my_role_level()` evaluate the simulated actor's level correctly. | M1 | Survey (Explorer 1 & 2) |
| F3 | Physical Schema Constraint Compliance | Fix `hr_emploc.status` from `'Active'` to `'Pending Emploc'` and `plantilla.status` from `'Vacant'` to `'Resigned'` in simulation steps. | M1 | Survey (Explorer 1) |
| F4 | Collision-Proof Test Data Identifiers | Generate collision-proof `vcode` and dynamic unique test actor credentials in `users_profile`. | M1 | Survey (Explorer 1) |
| F5 | Step Telemetry Persistence in Run Metadata | Persist the full `steps` JSON array into `qa_agent_runs.metadata` upon scenario completion for persistent auditability. | M1 | Survey (Explorer 1 & 2) |
| F6 | 6-Role Workflow Relay Execution Logic | Execute full workflow relay across Head Admin, Encoder, Recruitment, HRCO, HR Personnel, and Back Office with accurate negative barrier check. | M1 | Survey (Explorer 2) |
| F7 | Robust Defect & Permission Leak Logging | Record findings with valid `severity`, `finding_type`, `title`, `details`, and actionable `recommendation` into `qa_agent_findings`. | M1 | Survey (Explorer 2) |
| F8 | Governance Query Hooks & Type Contracts | Define typed `QaScenarioRunResult` and `QaScenarioStep`, and fix view column mappings (`finding_type`, `recommendation`, `is_enabled`, `queue_status`, `generated_at`, etc.). | M2 | Survey (Explorer 3) |
| F9 | Flagship Scenario Selection in UI | Add `FULL_E2E_RELAY` ("6-Role AI Agent Workflow Relay") as primary default scenario in `COMMON_SCENARIOS`. | M2 | Survey (Explorer 3) |
| F10 | Live Simulation Execution & Step Viewer UI | Render real-time/completed simulation outcomes, atomic rollback verification badge, and step timeline with role badges, status, and details. | M2 | Survey (Explorer 3) |
| F11 | Actionable Defect Remediation Viewer | Surface findings with actual defect code (`finding_type`), severity badge, and clear remediation callout (`recommendation`). | M2 | Survey (Explorer 3) |
| F12 | Environment Safety Default | Set default environment in report generators and scenario execution to `'staging'` (never hardcoded `"production"`). | M2 | Survey (Explorer 3) |
| F13 | Full E2E Simulation Verification Suite | Automated test suite verifying 100% scenario execution, rollback isolation, telemetry integrity, and UI rendering. | M3 | Project Architecture |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Database Engine & Multi-Role Sandbox Migration | Surgical migration `20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` fixing GUC impersonation (`request.jwt.claim.sub`), status constraints (`hr_emploc`, `plantilla`), unique collision avoidance, 6-role workflow execution, negative barrier validation, and steps metadata persistence. | none | DONE |
| M2 | Governance Query Hooks & QA Center UI Integration | TypeScript interfaces, view mapper fixes in `governance.ts`, `COMMON_SCENARIOS` update with `FULL_E2E_RELAY`, execution results & step timeline rendering, and remediation display in `QaCenterModal.tsx`. | M1 | DONE |
| M3 | E2E Testing, Zero-Pollution Verification & Hardening | Comprehensive test harness executing scenario runs against database, asserting zero data pollution in live tables, telemetry persistence, UI component tests, documentation updates, and local commit. | M1, M2 | DONE |

## Interface Contracts

### `public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY')`
- **Input**: `p_scenario_code text`
- **Output**: `jsonb`:
  ```json
  {
    "success": true,
    "run_id": "uuid",
    "scenario_code": "FULL_E2E_RELAY",
    "sandbox_rolled_back": true,
    "steps": [
      {
        "step": 1,
        "role": "Head Admin",
        "action": "headcount_approval_and_vacancy_init",
        "status": "passed",
        "details": "Authorized headcount quota and opened vacancy QA-RELAY-123456-abc"
      }
    ],
    "finding_counts": { "critical": 0, "high": 0, "medium": 0, "low": 0, "total": 0 },
    "executed_at": "ISO-8601"
  }
  ```
- **Error Behavior**: Caught internally inside subtransaction, rolls back live changes, logs `scenario_runtime_error` finding, sets `success: false` and `sandbox_rolled_back: true`.

### TypeScript Contracts (`src/lib/queries/governance.ts`)
```ts
export interface QaScenarioStep {
  step: number;
  role: string;
  action: string;
  status: "passed" | "failed";
  details: string;
}

export interface QaScenarioRunResult {
  success: boolean;
  run_id: string;
  scenario_code: string;
  sandbox_rolled_back: boolean;
  steps: QaScenarioStep[];
  finding_counts: {
    critical?: number;
    high?: number;
    medium?: number;
    low?: number;
    total?: number;
  };
  executed_at: string;
}
```

## Code Layout
- `supabase/migrations/`: Database migrations containing surgical diffs for `public.qa_run_scenario`.
- `src/lib/queries/governance.ts`: Data access layer, query hooks, RPC callers, and typed data mappers.
- `src/components/more/QaCenterModal.tsx`: Host modal and child UI components for the QA Center.
- `src/components/more/qa/`: Modular QA components (`QaSimulationRunner.tsx`, `QaStepTimeline.tsx`, etc.).
