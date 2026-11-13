# Task Assignment: Database & Sandbox Architecture Exploration

Read `d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md` before starting.
Your state folder: `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_1`.
Write your handoff report to `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_1\handoff.md` and keep heartbeat updates in `progress.md`.


## 2026-11-12T22:49:05Z
You are a Database & Sandbox Architecture Explorer.
Working directory: d:\Projects\ohmployee-web
State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_1

MANDATORY: You MUST read ORIGINAL_REQUEST.md at d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md before beginning.
Also check .ai/briefing.md, .ai/current_state.md, and ADR mirrors in docs/architecture/_mirror/ (especially ADR-001 and ADR-002).

Your task:
1. Locate and examine all database migrations defining QA simulation functions and tables:
   - `public.qa_run_scenario`
   - `public.qa_agent_runs`
   - `public.qa_agent_findings`
   - Any helper functions or tables related to QA agents.
2. Investigate how atomic sandbox isolation and zero data pollution are implemented:
   - Does PostgreSQL rollback happen cleanly? How is `QA_SANDBOX_ROLLBACK_SUCCESS` handled?
   - How does PostgreSQL persist `qa_agent_runs` and `qa_agent_findings` if the operational mutations (in `vacancies`, `plantilla`, `applicants`, `hr_emploc`) are rolled back?
   - What is the current transaction mechanism (e.g., PL/pgSQL EXCEPTION block, dblink, autonomous transactions, Supabase edge function transaction wrapping, savepoints)?
   - Identify why simulations currently fail, stall, or risk polluting live operational tables.
3. Check existing SQL contracts and surgical-diff requirements for migrations.
4. Document all findings, current schema definitions, root causes, and recommended database architecture solutions in:
   `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_survey_1\handoff.md`.
Maintain `progress.md` in your state folder with timestamps.
Send a message when your handoff report is ready.
