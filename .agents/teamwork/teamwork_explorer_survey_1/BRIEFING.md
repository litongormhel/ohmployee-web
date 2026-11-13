# BRIEFING — 2026-11-12T23:22:00Z

## Mission
Investigate database & sandbox architecture for QA simulations, zero data pollution mechanisms, transaction rollback vs persistence, and root causes of simulation failures.

## 🔒 My Identity
- Archetype: explorer
- Roles: Teamwork explorer, Database & Sandbox Architecture Explorer
- Working directory: d:\Projects\ohmployee-web
- State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_1
- Original parent: 6863d778-d94c-4bc3-b617-a727a50f6360
- Milestone: QA Simulation Sandbox Architecture Investigation

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Do NOT directly modify source code or database migrations
- Write only to own folder (.agents/teamwork/teamwork_explorer_survey_1)
- Never rewrite SQL functions from scratch; observe surgical-diff and SQL contract requirements
- Report back to parent agent via send_message

## Current Parent
- Conversation ID: 6863d778-d94c-4bc3-b617-a727a50f6360
- Updated: 2026-11-12T23:22:00Z

## Investigation State
- **Explored paths**:
  - `supabase/migrations/20262606000045_qa_role_relay_engine.sql`
  - `supabase/migrations/20260520012857_remote_schema.sql` (lines 980-1050, 1420-1460, 2650-3400, 13615-14020, 21390-21460)
  - `supabase/migrations/20260521062543_remote_schema.sql`
  - `supabase/migrations/20260527000000_unify_role_level_source.sql`
  - `supabase/migrations/20260603000001_security_advisor_phase1_low_risk.sql`
  - `supabase/migrations/20261019000000_fix_additional_store_multislot_and_applicant_contact.sql`
  - `supabase/migrations/20261026000002_qa_reset_soft_archive_and_atomic_rollback.sql`
  - `supabase/migrations/20261228000000_fix_permission_drift_f01_f02.sql`
  - `supabase/migrations/20262606000092_fix_audit_logs_actor_id_fk_and_safe_resolution.sql`
  - `src/lib/queries/governance.ts`
  - `src/components/more/QaCenterModal.tsx`
  - `scripts/check-sql-contracts.mjs`
- **Key findings**:
  1. Transaction isolation operates via PL/pgSQL subtransaction savepoints (`BEGIN ... EXCEPTION WHEN OTHERS THEN ... END`) with `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`.
  2. Telemetry (`qa_agent_runs`, `qa_agent_findings`) is persisted because registration is initiated before the subtransaction and completion/findings logging happens after the subtransaction has rolled back.
  3. Identified 6 major bugs/failure modes: (1) `hr_emploc_status_check` violation (`status = 'Active'`); (2) `plantilla_status_check` violation (`status = 'Vacant'`); (3) unhandled exception in `qa_complete_detection_run` when `v_orig_jwt` is NULL; (4) `users_profile` unique constraint collisions; (5) timestamp collision on `vacancies.vcode`; (6) UI omission of `FULL_E2E_RELAY` and omission of step-by-step telemetry display.
- **Unexplored areas**: None regarding core survey scope. Ready to draft handoff.

## Key Decisions Made
- Confirmed that PL/pgSQL savepoints cleanly roll back all operational table mutations (`vacancies`, `plantilla`, `applicants`, `hr_emploc`) and trigger side effects (`audit_logs`, `employee_activity_log`, `notifications`) without requiring dblink or autonomous transactions.
- Designed exact surgical fixes to make `qa_run_scenario` and `QaCenterModal` production-ready.

## Artifact Index
- .agents/teamwork/teamwork_explorer_survey_1/DISPATCH.md — Incoming messages and task assignments
- .agents/teamwork/teamwork_explorer_survey_1/BRIEFING.md — Situational awareness and working memory
- .agents/teamwork/teamwork_explorer_survey_1/progress.md — Liveness heartbeat and progress tracking
- .agents/teamwork/teamwork_explorer_survey_1/handoff.md — Final 5-component handoff report
