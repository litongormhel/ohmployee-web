## 2026-11-13T03:51:46Z

You are worker_m3_1_gen1, a teamwork_worker.
Your working directory is d:\Projects\ohmployee-web.
Your state folder is d:\Projects\ohmployee-web\.agents\teamwork\worker_m3_1_gen1.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Context & Rules:
- User request: d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md
- Project plan: d:\Projects\ohmployee-web\PROJECT.md
- Working rules: AGENTS.md and .ai/briefing.md (Follow "Mandatory Workflow Rules" and "After Every Completed Prompt" rules).
- Environment Safety Guard: Staging only (`qqiiznmqxfoamqytjica`). Never touch production (`rwxelulyapjgaarlwkus`).
- Main branch only: Do not switch or create branches. Never push.

Milestone 3 Scope & Objectives:
1. End-to-End Simulation & Zero-Pollution Database Verification:
   - Create an automated test runner script `scripts/test_m3_e2e_staging_simulation.mjs` that runs against Staging database instance.
   - Call `public.qa_run_scenario('FULL_E2E_RELAY')` (and legacy scenarios like `VAC_ARCHIVE_001`).
   - Verify the return shape: `success === true`, `sandbox_rolled_back === true`, `steps.length === 7`, and step outcomes.
   - Query live database tables: `vacancies`, `plantilla`, `applicants`, `hr_emploc`, `users_profile` to prove that zero mock/simulation data remains in live tables (0 records found).
   - Query telemetry tables: `qa_agent_runs` and `qa_agent_findings` to confirm `run_id` exists, summary is populated, and `metadata->'steps'` holds all 7 steps.
2. Update Repository Documentation:
   - Update `docs/state/more_state.md` to document the QA Center simulation engine, sandbox rollback, multi-role relay, telemetry persistence, and UI components.
   - Update `.ai/briefing.md` (Recent completions, state index, etc.).
   - Append a complete prompt handoff entry to `.ai/handoff.md` following the required format in `.ai/briefing.md` (Context loaded, Observation, Logic Chain, Caveats, Conclusion, Verification Method, Next Steps, and `> [!TIP]` callout).
3. Verification Suite:
   - Run `node scripts/test_m3_e2e_staging_simulation.mjs`
   - Run `npm run check:adr`
   - Run `npm run check:sql`
   - Run `npm run lint`
   - Run `npm test`
   - Run `npm run build`
4. Local Commit:
   - Follow `.ai/briefing.md` § Local Commit Rule:
     * Check `git status`
     * Make a LOCAL commit on `main` committing only the files modified in this prompt using EXPLICIT paths (never `git add .`, never `git push`).
     * Commit message format: `feat(more): audit and ensure qa simulation engine and qa center ui readiness`

Write your comprehensive completion report to `handoff.md` in your state folder (`d:\Projects\ohmployee-web\.agents\teamwork\worker_m3_1_gen1\handoff.md`). Include all verification outputs, commit hash, and query proof.
Send a message back when complete.
