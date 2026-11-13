# BRIEFING — 2026-11-13T02:27:00Z

## Mission
Analyze `src/lib/queries/governance.ts` and specify exact TypeScript contract additions, RPC hook return type fixes (`QaScenarioStep`, `QaScenarioRunResult`), and column mapper corrections for `fetchQaCenterSnapshot()` to satisfy Milestone 2 requirements.

## 🔒 My Identity
- Archetype: explorer
- Roles: Governance Query Hooks & TypeScript Contracts Specialist
- Working directory: d:\Projects\ohmployee-web
- State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_1
- Original parent: 6863d778-d94c-4bc3-b617-a727a50f6360
- Milestone: Milestone 2 - Governance Query Hooks & QA Center UI Integration

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly
- Write only to state folder: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_1`
- Comply with AGENTS.md, ADR-001/002 architectural invariants
- Report via 5-component handoff and notify caller via `send_message`

## Current Parent
- Conversation ID: 6863d778-d94c-4bc3-b617-a727a50f6360
- Updated: 2026-11-13T02:27:00Z

## Investigation State
- **Explored paths**:
  - `src/lib/queries/governance.ts` (lines 1-520)
  - `src/components/more/QaCenterModal.tsx` (usages of governance hooks and types)
  - `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` (RPC payload contract)
  - `supabase/migrations/20260521062543_remote_schema.sql` (view definitions for `v_qa_*`)
  - `supabase/migrations/20260603000001_security_advisor_phase1_low_risk.sql` (`v_qa_detection_run_summary`)
  - `PROJECT.md` and Explorer 3 survey handoff
- **Key findings**:
  - `public.qa_run_scenario` returns a JSON object with `success`, `run_id`, `scenario_code`, `sandbox_rolled_back`, `steps` array, `finding_counts`, `executed_at`.
  - Currently `runQaScenarioRpc` returns untyped `data` and `useRunQaScenario` returns an unconstrained mutation.
  - `fetchQaCenterSnapshot` drops `finding_type` (fallback to `"QA_FINDING"`), `recommendation`, `reference_table`, `reference_record_id`, and `run_id` from `v_qa_open_findings`.
  - `v_qa_schedules` columns `frequency`, `run_time`, `is_enabled` are unmapped, causing hardcoded `"@daily"` and always-active schedules.
  - `v_qa_run_queue` column `queue_status` is unmapped, causing all queue items to display as `"queued"`.
  - `v_qa_daily_reports` and `generateDailyQaReportRpc` default to `"production"` instead of `"staging"`.
  - `v_qa_detection_run_summary` column `summary` is dropped by `QaRunSummary`.
- **Unexplored areas**: None within M2 query hooks scope.

## Key Decisions Made
- Detailed exact TypeScript interfaces (`QaScenarioStep`, `QaScenarioRunResult`) with both snake_case (canonical Postgres RPC) and camelCase convenience properties.
- Defined surgical diff for `runQaScenarioRpc` with defensive parsing and type guarantees.
- Defined exact column mappings for `v_qa_open_findings`, `v_qa_schedules`, `v_qa_run_queue`, `v_qa_daily_reports`, and `v_qa_detection_run_summary`.
- Set default environment to `'staging'` for `generateDailyQaReportRpc` and `v_qa_daily_reports`.

## Artifact Index
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_1\BRIEFING.md` — persistent memory
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_1\progress.md` — heartbeat and task progress
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m2_1\handoff.md` — final 5-component report
