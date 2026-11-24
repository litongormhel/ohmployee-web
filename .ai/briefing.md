# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Autonomous Single-Turn Execution Rule (Default Mode)
- **Single-Turn by Default**: The agent automatically executes and verifies tasks end-to-end in a **single turn** (Plan -> Implement -> Verify -> Test/Lint -> Commit -> Staging Auto-Push) without requiring the user to type "Direct" or "Proceed".
- **When to STOP and WAIT (Approval / Clarification Gate)**: The agent pauses and waits for user input ONLY if:
  (1) The user explicitly says "Plan only", "Plan muna", or asks for review/options first,
  (2) There is genuine ambiguity or uncertainty in business requirements (present 1–3 concrete recommendations and ask),
  (3) The change directly conflicts with an ADR architecture lock or contract invariant, OR
  (4) Irreversible destructive actions are involved (e.g. dropping production tables or deleting production assets).
*Standing UI Standard Loop Override:* The UI Standard loop (`ohm#l0u8s2d9` onward) runs WITHOUT an approval gate. The loop pauses only on the stop conditions in `docs/architecture/ui-standard-briefing.md` section 10 or when verification fails. This overrides the generic "stop and wait" rule for this project only. Do not ask for approval again unless a stop condition triggers.
*Scope-Expansion Rule:* If any later test or investigation shows a change is needed outside an approved plan (any function, table, file or migration not listed), STOP and present an amended plan. Do not extend scope.
*Post-Migration Live Diff Rule:* After applying any migration to staging, diff live `pg_get_functiondef` vs the committed file for every touched function.
*REPORTING INTEGRITY:* every table, count, SQL result, timestamp, assertion list and code excerpt in a report or handoff must be copied from a tool output of the current task, with the query or file and line shown. Never reconstruct, round, summarize from memory or fill in a result you did not obtain. If a check was not run, write NOT RUN. If a value is unknown, write NOT VERIFIED.

### Non-Breaking View & RPC Parity Rule (Mobile Protection Lock)
The Supabase database serves BOTH Web and Mobile (`OHMployee`).
1. **Views (Append-Only)**: In `CREATE OR REPLACE VIEW`, any new column MUST be appended to the very end of the column list. Never reorder, rename, or drop existing columns in views.
2. **RPC Functions (Default-Safe)**: Any new parameter added to existing RPC functions MUST specify `DEFAULT NULL` (or provide a backward-compatible wrapper overload) so Mobile app calls without the new parameter never fail.

### No Silent Catch & PostgREST Column Guard (`src/lib/queries/*.ts`)
- Never use empty or unlogged `catch {}` blocks around Supabase queries.
- Always log PostgREST errors via `console.error('[PostgREST Schema Error]', error)` with the query context.
- Before querying joined columns in `.select()`, cross-check the physical table columns in `scripts/check-sql-contracts.mjs` to ensure the column physically exists on that table (e.g. `stores` has `area_city, area_province`, NOT `area_name`).

### Auto-Numbered Migration Generation Rule
Never guess or manually concoct migration timestamps. Always generate new migrations using `npm run db:new <migration_name>` (`scripts/new-migration.mjs`), which automatically increments the highest numeric version prefix across Web and Mobile, guaranteeing zero duplicate version prefix collisions.

### Uncertainty, Clarification & Recommendation Standard
Whenever requirements, design decisions, edge cases, or scope boundaries are uncertain, ambiguous, or open to interpretation:
1. Do not assume or silently pick an arbitrary path.
2. STOP and ask the user for clarification.
3. Always accompany the question with 1–3 concrete, well-analyzed recommendations (highlighting the recommended option and explaining why).

### ADR Conflict & Architecture Safety Gate
If a prompt or instruction conflicts with ADR-001/ADR-002 locks, permanent architectural rules, or database contracts:
1. STOP immediately. Never proceed blindly or overwrite architectural locks.
2. Identify the exact ADR section or rule in conflict.
3. Clearly explain the risks (e.g. data corruption, mobile/web disparity, broken audit trail, capacity leakage).
4. Propose a safe recommendation that achieves the user's intent without compromising system architecture.
5. Wait for explicit confirmation or guidance before making any changes.

### Workflow & Visibility Regression Guard
If any requested fix or enhancement would break an existing workflow, regress visibility (e.g. role-scoped action columns, tab rosters, audit logs, DOLE compliance badges), or disrupt upstream/downstream integrations:
1. STOP immediately.
2. Report the exact regression risk and affected user roles or views.
3. Provide a safe recommendation that resolves the user requirement without introducing regressions.

### SQL Function Surgical-Diff & Contract Gate (Anti-Overwrite Lock)
Because PostgreSQL `CREATE OR REPLACE FUNCTION` replaces the entire function body, rewriting a function from memory or an older migration causes regressions across modules. Whenever authoring a migration that modifies an existing SQL function:
1. **Locate the latest migration**: Run `git grep -l "FUNCTION public.<name>" supabase/migrations/` and read the latest file defining that function.
2. **Surgical diff only**: Copy that exact latest body as your base and modify only the specific lines required by the approved plan. Never drop existing table writes, slot/link synchronizations, or rollback snapshots.
3. **Automated SQL Contract Gate (`npm run check:sql`)**: `scripts/check-sql-contracts.mjs` is chained into `npm test` and `npm run lint`. It validates all `INSERT`/`UPDATE` columns against the physical schema of 28 core tables across the OHMployee ecosystem and enforces invariant contracts on 19 critical cross-module RPCs. Never bypass or weaken a contract check without explicit user approval.

### Task Decomposition & Subagent Delegation Standard
For heavy, multi-surface, or high-risk tasks (cross-module impact, complex business logic refactors, or multi-table schema/RPC audits):
1. **Avoid context pollution**: Heavy file reads and deep logs clog token memory and increase the risk of missing ADR rules.
2. **Decompose and delegate**: Utilize subagents (e.g., `research` or specialized agents via `invoke_subagent`) to trace schema dependencies, search the codebase, or cross-verify parity in isolated contexts.
3. **Primary Orchestration**: The primary agent remains responsible for all workflow rules, the Approval Gate, local commits, and communication with the user.

### ADR Architecture Lock Reference (Hub-and-Spoke Modular System)
ADR mirrors (read these): `docs/architecture/_mirror/adr/00_core_invariants.md` plus the active module's file in `docs/architecture/_mirror/adr/<module>.md` — read-only mirrors. To maintain maximum token efficiency, NEVER load all ADR files; load only Core Invariants and the active module file.
Source of truth: mobile repo `docs/architecture/adr/` (Windows: `D:\Projects\OHMployee`; override with env `OHM_MOBILE_REPO`).
Freshness check + auto-sync every prompt: `npm run check:adr` / `npm run sync:adr` (rules in AGENTS.md § ADR Mirrors). Module → ADR file routing: `.ai/current_state.md`.
Do not edit ADRs (or mirrors) from this web repo. If a loop requires an ADR update, log it in handoff under "ADR updates needed (Ohm applies in mobile repo)". In every loop report, state "ADR basis: <file + sections>" and the mirrors' `source_commit`.

### Permanent Architectural Rule Locks
1. **Rule #1 (Inactive Roster Persistence):** Employees who are disengaged, separated, or pending deactivation (`Resigned`, `AWOL`, `Terminated`) must **always** remain visible in the Inactive Tab for historical and reporting continuity. They must never be filtered out or hidden into isolated views that remove them from historical logs. Tab 5 (Deactivation) operates as a transactional queue for offboarding approval; Tab 6 (Inactive) serves as the persistent historical roster.
2. **Rule #2 (Safe Audit Logging):** Audit log triggers (`fn_audit_log`) must always use safe actor ID resolution (`resolve_audit_actor_id`) with fallbacks to `NULL` on `foreign_key_violation` to permanently prevent operational mutation failures (e.g. during employment status updates, resignations, AWOL, terminations) due to missing user profiles or FK constraints.
3. **Rule #3 (Plantilla Table & Universal Cards Contract):** The Deactivation Tab roster strictly enforces column layout `Emploc# / Member / VCode / Store / Position / Assignment / Status` (with Actions column completely removed); the Inactive Tab roster strictly removes `Clearance Status` and dynamically resolves operational/separation remarks from `plantilla.remarks` with waterfall fallback to `audit_logs`; and the `Table / Cards` view toggle must remain fully supported and crash-free across all status tabs (Active, On-Leave, Vacancy, Floating, Deactivation, Inactive).
4. **Rule #4 (Floating Compliance, Layout & Store Slot Restriction):** Floating records must continuously track duration and days elapsed for DOLE compliance monitoring (Article 301 maximum 180-day temporary layoff limit) via reactive countdown badges across table and card views. The Floating tab table strictly excludes the `Details` action button and the `Status` column, maintaining `Assign Store` as the single primary action. Store assignments for floating personnel in `AssignStoreModal` are strictly restricted to locations with open or available slots (`hc_filled < hc_total`, e.g., `1/2`), with fully occupied stores (`1/1`, `2/2`) filtered out and hidden to prevent over-allocation.
5. **Rule #5 (Employee Detail Navigation & State Preservation Contract):** Clicking an employee record across all status tabs (Active, On-Leave, Floating, Deactivation, Inactive) in both table and card views navigates to the dedicated full-page Employee Profile view (`/plantilla/[id]`), replacing the cramped right-side `PlantillaDetailDrawer`. The full-page view organizes employee data into 4 dedicated category tabs (Employment & Allocation, Schedule & Store Coverage, Benefits & Statutory, Activity & System Info) and features an always-visible top summary card and capability-aware actions bar (`Update Employment Status`, `Transfer Employee`, `Reassign HRCO`, `Request Deactivation`, `Request Deletion`). The return navigation link (`← Back to Plantilla`) strictly preserves the originating context (status tab, view mode `table` vs `cards`, search filter, account scope, and pagination page) via URL parameters, guaranteeing zero disruption of operational context when returning to the plantilla roster.
6. **Rule #6 (Store-Level Schedule & HC Allocation Matrix):** Merchandiser and store personnel scheduling supports granular, store-level duty day and shift time assignments paired with fractional Headcount (HC) Share distribution (e.g. Store 1: `MON-TUE-WED`, `8:00 AM - 5:00 PM`, `0.50 HC`; Store 2: `THU-FRI-SAT`, `8:00 AM - 5:00 PM`, `0.50 HC`). In the Dedicated Employee Profile (`/plantilla/[id]`), the previous separate 'Work Schedule & Rate' and 'Stores & Coverage' tabs are permanently consolidated into a single comprehensive **`Schedule & Store Coverage`** tab. It features a top global terms bar (Daily Wage, Designated Rest Days supporting 1, 2, or more days off, Assigned HR Coordinator) and a Store Schedule & Headcount Allocation Matrix displaying store branch, VCode, duty days, shift window, HC share, and external visibility presence badges (`DAYS • HC Share`). In `UpdateScheduleModal`, Store Name, VCode, and HC Share are strictly read-only to prevent encoding errors; store additions and deletions are completely removed (store assignments are governed exclusively by official Plantilla / Movement allocations); rest days support multi-select (e.g., Saturday and Sunday); and duty days and shift hours are fully configurable per store.
7. **Rule #7 (Floating to Active Transition):** When assigning a Store to a Floating employee (selecting a Vacant store with available slots), the system must immediately change the employee's status to **Active** (not Inactive), auto-set assignment type to **Stationary** (`deployment_type: 'Stationary'`), and bind their `vcode` to the target store's vacancy code (`vcode: targetStore.code`), releasing the previous store's slot. Because deployment from floating to a single initial store is strictly Stationary, the assignment type selector in `AssignStoreModal` is removed and auto-persisted behind the scenes. The employee is now deployed to that store, which consumes the vacancy slot and makes them appear in the Active Tab. All previous floating or separation dates, timestamps, and remarks (`separation_status`, `inactive_at`, `inactive_by`, `date_of_separation`, `resignation_date`, `remarks`, `deactivation_reason`, `for_deactivation_at`, `for_deactivation_by`, `deactivated_at`, `deactivated_by`) are strictly cleared/nullified upon deployment.
8. **Rule #8 (Vacancy Pipeline Candidate-Level Headcount Contract):** In Vacancy Management (`/vacancy`), the **Pipeline** tab (both badge counter and data table rows) strictly operates on **candidate-level granularity (1 row = 1 applicant / per tao)**. Even when multiple candidates are active under the same store or requisition code (`vcode`), each applicant represents an individual headcount unit in the pipeline badge and renders as a distinct row with independent candidate contact details, stage progression, and action capabilities. Under no circumstances should the Pipeline count or table be collapsed to distinct store/requisition records.

### Branch Policy
Work on `main` only. Never create a branch unless the prompt explicitly says "create a branch".
Never merge, push, or delete a branch on your own initiative. If the session environment
created a branch (e.g. remote/cloud task isolation), report it in the handoff entry; Ohm
verifies, merges to `main`, and deletes it.

### Database Access & Modification Rule
- **Standing Staging Migration Auto-Push & Pre-Push Error Gate**: The Web repository (`ohmployee-web`) is the designated primary migration runner. Once Ohm approves an implementation plan that includes a database migration:
  1. **Pre-Push Error Check**: Before pushing to Staging (`qqiiznmqxfoamqytjica`), ensure the migration has zero errors (`npm run check:sql` + `npx supabase db push --dry-run --linked` inside `npm run db:push:staging`). If any error occurs, fix the migration first and re-validate until 0 errors before pushing to Staging.
  2. **Auto-Push & Live Diff**: Push to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging` (`scripts/push-staging-migrations.mjs`), followed by live `pg_get_functiondef` verification.
  3. **End-of-Turn Prod vs. Staging Migration Counter**: Whenever a prompt includes or touches migrations, query the read-only migration lists for Production (`rwxelulyapjgaarlwkus`) and Staging (`qqiiznmqxfoamqytjica`) via Supabase MCP `list_migrations` (strictly read-only metadata check; never link `.env` or execute DDL/SQL on Prod) and include this exact block at the end of the turn report, listing the exact filenames of any pending migrations:
     ```text
     prod: <X> migrations
     staging: <Y> migrations

     <N> migrations are not on prod:
     - <filename_1>
     - <filename_2>
     ```
- **Production Lock**: NEVER connect `.env` to, execute DDL/SQL against, or push migrations to Production (`rwxelulyapjgaarlwkus`). All database access from a pure UI loop remains prohibited.

### Supabase Environments & Project References
- **Production:** `rwxelulyapjgaarlwkus`
- **Staging:** `qqiiznmqxfoamqytjica`
- Agent sessions and localhost must use staging (`qqiiznmqxfoamqytjica`).
- NEVER connect to or run commands against the production ref (`rwxelulyapjgaarlwkus`).
- **Auto-Switch to Staging Guard**: If the current environment or Supabase CLI is detected pointing to Production (`rwxelulyapjgaarlwkus` in `.env` or `supabase/.temp/project-ref`), ALWAYS immediately switch back to Staging (`qqiiznmqxfoamqytjica`) via copying `.env.staging` -> `.env` and running `npx supabase link --project-ref qqiiznmqxfoamqytjica` before executing any task or command.

### After Every Completed Prompt (mandatory, in this order)
1. `.ai/briefing.md` — prepend PROMPT ID + title to "Last Completed Tasks" (keep only 5)
2. `.ai/handoff.md` — prepend full handoff entry
3. `docs/state/<module>_state.md` — surgical update if behavior changed
4. Local commit (see "Local Commit Rule" below)
5. Branch close-out — if a branch exists, Ohm verifies (`npm run lint` / `npm run build` /
   manual test), merges into `main`, then deletes the branch. AI only reports the branch.
6. Conclude Turn Sign-off — conclude every response with both an explicit **Next Steps** section and a helpful `> [!TIP]` callout covering immediate next operational actions, relevant verification steps, or deployment commands (plus the mandatory `prod` / `staging` migration counter block whenever the prompt includes or touches migrations).

### Local Commit Rule (every prompt, after items 1-3)
- Commit LOCALLY on `main`. NEVER `git push`, merge, rebase, amend, reset, or delete anything.
- Stage ONLY the files this prompt changed, by explicit path. Never `git add .` or `git add -A`.
- Include the doc files updated in items 1-3 (briefing.md, handoff.md, state file) and any new
  migration file this prompt created. Committing a migration file does NOT apply it.
- Before committing, run `git status`. If a file this prompt touched already had uncommitted
  changes from before this prompt started, do NOT stage it. Report it and skip the commit.
- Commit only if verification passed: `npm run lint` clean for any code change (docs-only
  prompts need no lint). If verification fails, do not commit; report the failure.
- Commit only if on `main`. If on any other branch, do not commit; report it.
- Message format: `<PROMPT ID>: <PROMPT TITLE>`.
- After committing, report the commit hash and the exact files included.

State files = current stable behavior only. handoff.md = active sprint continuity only.
Archive obsolete logs to `docs/archive/`.

## Last Completed Tasks
1. **ohm#vacancy-detail-modal-and-activity-timeline (Refactor Vacancy Detail Surface to Multi-Tab Modal & Detailed What/Who/When Activity History Timeline)**: (1) Tabbed Modal Redesign ([VacancyDetailDrawer.tsx](file:///D:/Projects/ohmployee-web/src/components/vacancy/VacancyDetailDrawer.tsx)): Converted the cramped right-side slide-over drawer into a spacious centered Modal (`max-w-3xl`) featuring an always-visible top KPI strip (`Hired`, `Pipeline`, `Avail`, `Aging`) and 4 segmented navigation tabs: `Pipeline & Applicants`, `Vacancy Details`, `Ownership & Team`, and `Activity History`. (2) True Activity History Trail (`20262606000174_friendly_vacancy_activity_history_timeline.sql`): Fixed the frontend mapping bug that passed `eventDescription` instead of module to `formatActivityHistorySummary` (which collapsed events into generic `"Vacancy updated"` lines). Created `public.get_vacancy_activity_timeline(p_vacancy_id)` and wired `public.get_web_vacancy_detail(p_vacancy_id)` to aggregate and deduplicate chronological events across `vacancies`, `applicants`, `applicant_status_history`, `applicant_profile_edit_history`, `vacancy_closure_requests`, `hr_emploc`, and meaningful field-level `audit_logs` diffs, rendering full **What, Who, When** cards with exact timestamps. (3) Verification: Applied cleanly to Staging (`qqiiznmqxfoamqytjica`), 263/263 unit tests passed, 0 ESLint errors/warnings, 0 SQL contract violations.
2. **ohm#fix-vercel-auth-fallback (Inline Staging Fallback in Next Config and Client for Instant Vercel Auth)**: (1) Root Cause & Implementation: To resolve the infinite sign-in hang on Vercel (`https://ohmployee-web.vercel.app`) without requiring manual environment variable configuration in the Vercel dashboard, embedded the public Staging Supabase project URL and anon key as the default fallback in `src/lib/supabase/client.ts` and injected them into `next.config.ts` under `env: { NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY }`. Turbopack inlines these values during Vercel builds so the browser client always initializes a functional Supabase connection. (2) Secret Scanner Exemption: Updated `scripts/check-secrets.mjs` to exempt `STAGING_ANON_KEY` as a documented public anon key while retaining strict leak detection for all other credentials. (3) Verification: Passed all 263 unit tests (`npm test`), 0 ESLint errors/warnings (`npm run lint`), 0 secret leaks (`check:secrets`), 0 SQL contract violations (`check:sql`), and clean Next.js 16.2.4 production build (`npm run build`).
3. **ohm#fix-login-hanging-and-surface-missing-env-guard (Fix Login Hanging on "Signing In..." and Surface Missing Hosting Env Guard)**: (1) Root Cause Diagnosed on Vercel: Inspected live client bundle at `https://ohmployee-web.vercel.app/_next/static/chunks/0j_ybxiq3~rlj.js`. Next.js Turbopack compiled `g.default.env.NEXT_PUBLIC_SUPABASE_URL` instead of string literals because `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` were not configured in Vercel Project Settings > Environment Variables. In the browser, `createClient()` threw an uncaught error. (2) Infinite Spinner Fix: In `src/app/(auth)/login/page.tsx`, `handleLogin` previously called `setIsSubmitting(true)` without a `try ... catch` block around `createClient()`. The unhandled exception crashed execution before `setIsSubmitting(false)` could be called, permanently freezing the submit button on "Signing in...". Wrapped `handleLogin` in full `try ... catch` error handling, setting `isSubmitting(false)` and displaying the error. (3) Proactive Configuration Alert: Added `isSupabaseConfigured()` check to proactively render a configuration alert banner and disable the submit button when environment variables are missing. (4) Verification: Passed all 263 unit tests (`npm test`), 0 ESLint errors/warnings (`npm run lint`), 0 secret leaks (`check:secrets`), 0 SQL contract violations (`check:sql`), and clean Turbopack production build (`npm run build`).
4. **ohm#sync-pnpm-lockfile-for-vercel-ci (Synchronize pnpm-lock.yaml and package-lock.json with package.json for Vercel Frozen Lockfile CI Deployments)**: (1) Root Cause: Commit `1f7b2cb` removed `xlsx@^0.18.5` from `package.json`, but `pnpm-lock.yaml` was left desynchronized with `xlsx` still listed in lockfile importers and package snapshots. When Vercel CI ran `pnpm install --frozen-lockfile`, it failed with `ERR_PNPM_OUTDATED_LOCKFILE: Cannot install with "frozen-lockfile" because pnpm-lock.yaml is not up to date with <ROOT>/package.json (* 1 dependencies were removed: xlsx@^0.18.5)`. (2) Lockfile Synchronization: Regenerated `pnpm-lock.yaml` and `package-lock.json` via `pnpm install --lockfile-only` and `npm install --package-lock-only`, removing `xlsx@0.18.5` and its 7 transitive dependencies (`adler-32`, `cfb`, `codepage`, `frac`, `ssf`, `wmf`, `word`). (3) Frozen-Lockfile Validation: Verified in an isolated clean environment that `pnpm install --frozen-lockfile` skips resolution and installs cleanly with 0 errors. (4) Verification: Passed all 263 unit tests (`npm test`), 0 ESLint errors/warnings (`npm run lint`), 0 secret leaks (`check:secrets`), 0 SQL contract violations (`check:sql`), and clean Next.js 16.2.4 production build (`npm run build`).
5. **ohm#enforce-cgcode-strict-monotonicity-and-dissolution-retirement (Enforce CGCode Strict Monotonicity & Dissolution Retirement Invariant - ADR-002)**: (1) Architecture Lock (ADR-002 Invariant 3): Codified that when a Coverage Group is dissolved, merged, or archived, its `CGCODE` is permanently retired for all time. Re-clustering stores or personnel into a coverage group can NEVER reuse, recycle, or resurrect the old `CGCODE`, strictly minting a fresh, sequential, monotonically incremental `CGCODE`. (2) Database Hardening (`20262606000173_enforce_cgcode_strict_monotonicity_and_dissolution_retirement.sql`): Added permanent table index `uq_coverage_groups_account_code_permanent` enforcing global uniqueness across all active and archived groups; updated `fn_generate_cgcode_for_account` to probe across ALL historical coverage groups without `archived_at IS NULL` bypass; aligned sequence counters to strictly exceed historical max suffixes. (3) Verification: Applied cleanly to Staging (`qqiiznmqxfoamqytjica`), verified live `pg_get_functiondef`, 263/263 unit tests passed, 0 lint warnings, 0 SQL contract errors.
> Older entries trimmed 2026-11-24 (`ohm#vacancy-detail-modal-and-activity-timeline`) to keep this list to 5 — dropped `ohm#auto-roving-coverage-group-provisioning-and-backtrack` and earlier entries — see git history for that and earlier entries in full.
