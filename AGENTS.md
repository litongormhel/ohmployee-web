## Core Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)
- Read `.ai/briefing.md` first. Follow its "Mandatory Workflow Rules" section on EVERY prompt.
- Auto Context Loading (EVERY prompt, no Context block needed):
  1. `.ai/briefing.md`
  2. `.ai/current_state.md` → "Routing Index" section only
  3. Infer the module(s) from the prompt (route, component, RPC, or module name). Load each
     module's web state file(s) and its ADR-001 sections from the Routing Index table.
  4. ADR mirror → § Core Cross-Module Invariants + the module section(s).
  If the module is ambiguous, ask before loading. Start every report with
  "Context loaded: <files + ADR sections>". Fail loudly: if any file is missing, STOP and report
  the missing path. Never proceed silently. All paths are relative to THIS web repo.
  A Context block in the prompt is optional: it overrides or extends this default.
- ADR Mirrors: ADR-001 and ADR-002 are read from `docs/architecture/_mirror/`
  (read-only copies; source of truth is the mobile repo). At the start of EVERY prompt run
  `npm run check:adr` and act on `ADR_MIRROR_STATUS`:
  `FRESH` → proceed. `STALE` / `MIRROR_MISSING` / `MIRROR_EDITED` → run `npm run sync:adr`
  (exempt from the Approval Gate: copy only, no code/logic), then include the mirror file(s) in the
  prompt's local commit and report "ADR mirror synced: <old> → <new>". `NOT_VERIFIED` → use the
  mirrors and write "ADR freshness: NOT VERIFIED" in the report. Never edit mirrors by hand.
- The post-prompt documentation update is mandatory on EVERY prompt, even if the prompt body
  does not mention it. Checklist: `.ai/briefing.md` § After Every Completed Prompt.
- Autonomous Single-Turn Execution Rule (Default Mode):
  - **Single-Turn by Default**: The agent automatically executes and verifies tasks end-to-end in a **single turn** (Plan -> Implement -> Verify -> Test/Lint -> Commit -> Staging Auto-Push) without requiring the user to type "Direct" or "Proceed".
  - **When to STOP and WAIT (Approval / Clarification Gate)**: The agent pauses and waits for user input ONLY if:
    (1) The user explicitly says "Plan only", "Plan muna", or asks for review/options first,
    (2) There is genuine ambiguity or uncertainty in business requirements (present 1–3 concrete recommendations and ask),
    (3) The change directly conflicts with an ADR architecture lock or contract invariant, OR
    (4) Irreversible destructive actions are involved (e.g. dropping production tables or deleting production assets).
- Non-Breaking View & RPC Parity Rule (Mobile Protection Lock):
  The Supabase database serves BOTH Web and Mobile (`OHMployee`).
  1. **Views (Append-Only)**: In `CREATE OR REPLACE VIEW`, any new column MUST be appended to the very end of the column list. Never reorder, rename, or drop existing columns in views.
  2. **RPC Functions (Default-Safe)**: Any new parameter added to existing RPC functions MUST specify `DEFAULT NULL` (or provide a backward-compatible wrapper overload) so Mobile app calls without the new parameter never fail.
- No Silent Catch & PostgREST Column Guard (`src/lib/queries/*.ts`):
  - Never use empty or unlogged `catch {}` blocks around Supabase queries.
  - Always log PostgREST errors via `console.error('[PostgREST Schema Error]', error)` with the query context.
  - Before querying joined columns in `.select()`, cross-check the physical table columns in `scripts/check-sql-contracts.mjs` to ensure the column physically exists on that table (e.g. `stores` has `area_city, area_province`, NOT `area_name`).
- Auto-Numbered Migration Generation Rule:
  - Never guess or manually concoct migration timestamps. Always generate new migrations using `npm run db:new <migration_name>` (`scripts/new-migration.mjs`), which automatically increments the highest numeric version prefix across Web and Mobile, guaranteeing zero duplicate version prefix collisions.
- Uncertainty & Clarification Gate: If requirements, user intent, edge cases, or scope boundaries
  are unclear or ambiguous, NEVER make assumptions or proceed blindly. Always STOP, ask clarifying
  questions, and explicitly provide 1–3 concrete recommendations with rationale.
- ADR & Architecture Conflict Gate: If a user instruction directly conflicts with ADR-001/ADR-002
  architectural locks, permanent rule locks, or database contracts, NEVER implement it silently.
  STOP immediately, cite the conflicting ADR section/rule, explain the specific risks and breakages
  if implemented as requested, and provide a safe recommendation that satisfies the objective without
  violating architectural integrity. Wait for explicit confirmation or override.
- Workflow & Visibility Regression Guard: If any proposed change risks breaking an existing workflow,
  regressing visibility (e.g., role-scoped action buttons, tab rosters, historical separation logs),
  or corrupting state transitions, STOP immediately. Detail what breaks, ask the user, and present
  a safe recommendation that avoids regression.
- SQL Function Surgical-Diff & Contract Gate (Anti-Overwrite Lock): NEVER rewrite a SQL function
  (`CREATE OR REPLACE FUNCTION`) from memory or from an older migration template. Before authoring
  any migration that modifies an existing RPC or trigger function:
  1. Locate the latest migration defining that function (`git grep -l "FUNCTION public.<name>" supabase/migrations/`).
  2. Copy that exact latest function body as the base and apply ONLY the minimal surgical diff required.
  3. Run `npm run check:sql` (also chained into `npm test` and `npm run lint` via `scripts/check-sql-contracts.mjs`)
     to verify that all `INSERT`/`UPDATE` table columns exist in the physical schema and that no
     cross-module RPC invariants (e.g., `plantilla_slots`, `plantilla_store_links`, rollback snapshots,
     `row_capabilities`, `user_scopes`) were dropped.
- Task Decomposition & Subagent Delegation Gate: When a prompt or task is heavy, multi-surface, or
  architecturally complex (e.g., spans multiple modules, involves large refactoring, requires deep
  codebase or RPC tracing, or carries high regression risk), the agent MUST decompose the problem.
  It should spawn specialized subagents (e.g., Codebase Researcher, Schema/RPC Auditor, or Verification
  Specialist via `invoke_subagent`) to perform isolated investigations or checks without polluting the
  primary context window. The primary agent remains the orchestrator: it synthesizes subagent findings,
  enforces the Approval Gate and ADR contracts, and delivers the unified report and recommendations to the user.
- Work on `main` only. Never create a branch unless the prompt says "create a branch". Never
  merge, push, or delete a branch on your own. If the environment created a branch, report it
  in the handoff entry; Ohm verifies (`npm run lint` / `npm run build` / manual test), merges
  to `main`, and deletes it.
- After items 1-3 of the checklist, make a LOCAL commit of only the files this prompt changed
  (explicit paths, never `git add .`). NEVER push. Rules: `.ai/briefing.md` § Local Commit Rule.
- Environment Safety Guard: If the workspace or Supabase CLI is detected pointing to Production (`rwxelulyapjgaarlwkus` in `.env` or `supabase/.temp/project-ref`), immediately switch back to Staging (`qqiiznmqxfoamqytjica` via `.env.staging` / `npx supabase link --project-ref qqiiznmqxfoamqytjica`) before executing tasks.
- Staging Migration Pre-Push Validation & Prod Delta Reporting Rule:
  1. **Pre-Push Error Gate**: Before pushing any migration to Staging (`qqiiznmqxfoamqytjica`), always validate that the migration has zero errors (`npm run check:sql` and `npx supabase db push --dry-run --linked` via `npm run db:push:staging`). If any error occurs (syntax, constraint, prefix collision, or contract error), fix the migration first and re-validate until it passes with 0 errors before pushing to Staging.
  2. **End-of-Turn Prod vs. Staging Migration Counter**: Whenever a prompt includes or touches database migrations, query the read-only migration lists for Production (`rwxelulyapjgaarlwkus`) and Staging (`qqiiznmqxfoamqytjica`) via the Supabase MCP `list_migrations` tool (strictly read-only metadata check; never link `.env` or execute DDL/SQL against Prod) and include the following summary block at the end of the turn report, listing the exact filenames of any pending migrations:
     ```text
     prod: <X> migrations
     staging: <Y> migrations

     <N> migrations are not on prod:
     - <filename_1>
     - <filename_2>
     ```
- Conclude every turn report with both: (1) an explicit **Next Steps** section covering immediate actions/guidance, and (2) a helpful `> [!TIP]` callout covering operational tips, verification commands, or deployment commands.

<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->
