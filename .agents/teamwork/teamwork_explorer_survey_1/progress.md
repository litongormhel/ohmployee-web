# Progress Log — Database & Sandbox Architecture Explorer

Last visited: 2026-11-12T23:20:00Z

## Status
- [x] Initialized briefing, dispatch tracking, and ADR freshness check (`ADR_MIRROR_STATUS: FRESH`).
- [x] Verified environment safety guard: Staging only, production ref untouched.
- [x] Located all relevant migrations defining QA simulation functions, tables, and views:
  - `public.qa_run_scenario` in `supabase/migrations/20262606000045_qa_role_relay_engine.sql`
  - `public.qa_agent_runs` in `20260520012857_remote_schema.sql` (schema, indexes, constraints, RLS)
  - `public.qa_agent_findings` in `20260520012857_remote_schema.sql` (schema, indexes, constraints, RLS)
  - Helper functions: `qa_start_detection_run`, `qa_complete_detection_run`, `qa_log_detection_finding`
  - Views: `v_qa_detection_run_summary`, `v_qa_open_findings`, `v_qa_daily_reports`
- [x] Thoroughly investigated transaction mechanism and zero data pollution:
  - PL/pgSQL `BEGIN ... EXCEPTION ... END` subtransaction (PostgreSQL internal savepoint).
  - Deliberate `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'` triggers rollback of operational mutations (`vacancies`, `plantilla`, `applicants`, `hr_emploc`, `audit_logs`).
  - Outside transaction persists telemetry in `qa_agent_runs` and `qa_agent_findings`.
- [x] Identified 6 critical failure modes and root causes preventing simulations from executing or reporting results:
  1. `hr_emploc_status_check` violation (`'Active'` is not valid for `hr_emploc.status`).
  2. `plantilla_status_check` violation in scenario `PLANTILLA_001` (`'Vacant'` is not valid for `plantilla.status`).
  3. `request.jwt.claims` GUC restoration failure when `v_orig_jwt` is NULL, leaving context as Back Office and causing `qa_complete_detection_run` to throw unhandled authorization error.
  4. Collision on synthesized test actors in `users_profile` due to unique constraints (`users_profile_email_key`, `users_profile_full_name_key`).
  5. Timestamp-based `vcode` (`QA-RELAY-HH24MISS`) collision risk within the same second against `vacancies_vcode_key`.
  6. Frontend disconnect in `QaCenterModal.tsx`: `FULL_E2E_RELAY` is missing from `COMMON_SCENARIOS`, and scenario run results (steps, pass/fail, finding counts) are discarded rather than displayed.
- [x] Formulated architectural recommendations and surgical diff design adhering to SQL Function Surgical-Diff & Contract Gate.
- [ ] Compiling comprehensive handoff report in `handoff.md`.
