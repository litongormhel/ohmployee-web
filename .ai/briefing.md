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
1. **ohm#enforce-cgcode-strict-monotonicity-and-dissolution-retirement (Enforce CGCode Strict Monotonicity & Dissolution Retirement Invariant - ADR-002)**: (1) Architecture Lock (ADR-002 Invariant 3): Codified that when a Coverage Group is dissolved, merged, or archived, its `CGCODE` is permanently retired for all time. Re-clustering stores or personnel into a coverage group can NEVER reuse, recycle, or resurrect the old `CGCODE`, strictly minting a fresh, sequential, monotonically incremental `CGCODE`. (2) Database Hardening (`20262606000173_enforce_cgcode_strict_monotonicity_and_dissolution_retirement.sql`): Added permanent table index `uq_coverage_groups_account_code_permanent` enforcing global uniqueness across all active and archived groups; updated `fn_generate_cgcode_for_account` to probe across ALL historical coverage groups without `archived_at IS NULL` bypass; aligned sequence counters to strictly exceed historical max suffixes. (3) Verification: Applied cleanly to Staging (`qqiiznmqxfoamqytjica`), verified live `pg_get_functiondef`, 263/263 unit tests passed, 0 lint warnings, 0 SQL contract errors.
2. **ohm#auto-roving-coverage-group-provisioning-and-backtrack (Universal Automatic Coverage Group Provisioning and Historical Backtrack - ADR-002)**: (1) Architecture Lock (ADR-002 Invariants 3 & 4): Codified that all roving personnel ($N \ge 2$ stores) strictly require an official Coverage Group Code (`CGCODE`), regardless of whether they originated via Baseline Batch Import or Operational Requisition. (2) Database Migration (`20262606000172_auto_roving_coverage_group_provisioning_and_backtrack.sql`): Updated `public.approve_plantilla_import_batch` to automatically mint/attach Coverage Groups, member store edges (with 1 anchor and fractional $1/N$ `hc_share`), and occupied coverage slots for all future roving imports. Executed a comprehensive historical backtrack provisioning active Coverage Groups for all 48 roving employees across historical accounts dating back to June imports. (3) Target Record Resolved: Assigned Jessie Dela Cruz (`2021-09660`) to `CG-FG1-0007` with `PUREGOLD CENTENIAL KAWIT` (anchor, 0.50 HC) and `EMILUS TANZA` (0.50 HC), populating the `Already in CG-FG1-0007` badge in `CreateCoverageGroupModal`. (4) Verification: Applied cleanly to Staging (`qqiiznmqxfoamqytjica`), 263/263 unit tests passed, 0 lint warnings, 0 SQL contract errors, and verified live database state.
3. **ohm#fix-coverage-group-dropdown-visibility-and-vacancy-suppression (Fix Coverage Group Dropdown Visibility Across Operations and Resolve Roving Vacancy Suppression)**: (1) Roving Coverage Group Dropdown Visibility: In `CreateCoverageGroupModal.tsx`, replaced strict case-sensitive `g.groupStatus === "Active"` check with case-insensitive non-archived filter (`s !== "archived" && s !== "dissolved" && s !== "closed"`), immediately populating operational roving groups (`CG-FG1-0004`, `CG-FG1-0005`) across **Add Store**, **Remove Store**, **Merge Groups**, and **Dissolve Group** target dropdowns. (2) Roving Vacancy Suppression Resolution: Root-caused why `Puregold General Trias` was missing from the Vacancy tab under account `FOREVER OFFICE` — its group `CG-FG1-0005` had denormalized `required_headcount = 0` in `coverage_groups`, causing `listVacancies` to drop its member stores as a 0-headcount test group. In `src/lib/queries/vacancy/vacancyListing.ts`, defaulted `requiredHc` to at least 1 when active slots exist, authored and applied migration `20262606000171_align_coverage_groups_required_headcount.sql` on Staging (`qqiiznmqxfoamqytjica`) aligning `required_headcount = 1`. (3) Vacancy Tab Unoccupied Slot Isolation: In `src/app/(dashboard)/plantilla/page.tsx`, updated slot expansion to filter out physical slots already occupied by active personnel (`unoccupiedPhysicalSlots`), ensuring filled slots (e.g. SMCO Kawit Slot 1 filled by Fred Richard Borillo) render in the Active Tab and only genuinely open slots (Slot 2) render in Vacancy, cleanly resolving the user's verified 5-slot vacancy roster (`Vacancy 5`). (4) Coverage Group Staffing Investigation: Verified that Waltermart General Trias and Puregold Tanza are member stores of `CG-FG1-0004` which is 100% filled by active employee `JUAPHEL DELFINA` (`2019-08946`), plus Waltermart has active stationary employee `RAMMEL VILLA` (`2021-09665`), properly justifying their 0-vacancy status.
4. **ohm#align-plantilla-vacancy-tab-badge-to-slot-count (Align Plantilla Vacancy Tab Badge Directly to Total Rendered Slot Count)**: Replaced composite requisition-count badge (`3 (5 slots)`) on Plantilla Tab 3 with direct total slot count (`Vacancy 5`) ([page.tsx](file:///D:/Projects/ohmployee-web/src/app/(dashboard)/plantilla/page.tsx), [PlantillaFilterToolbar.tsx](file:///D:/Projects/ohmployee-web/src/components/plantilla/directory/PlantillaFilterToolbar.tsx), [plantilla_web_state.md](file:///D:/Projects/ohmployee-web/docs/state/plantilla_web_state.md)). Under Option A Standard (1 Row = 1 Slot Granularity), every row rendered in the Vacancy tab represents an individual slot. Aligned `vacancyCount` to `allVacancies.length` and streamlined `PlantillaFilterToolbar` to render `{vacancyCount}` directly, establishing 1:1 visual parity between the tab badge count (5) and the 5 rendered roster rows, perfectly consistent with sibling tabs (`Active 4`, `On-Leave 0`, `Floating 0`, `Deactivation 1`, `Inactive 3`).
5. **ohm#multi-position-vacancy-intake-and-slot-quota-bounds (Implement Multi-Position Vacancy Intake, Disambiguation Parity, and Strict Slot Quota Bounds)**: Architected and implemented multi-position candidate intake and disambiguation parity with Mobile for multi-role stores, and enforced strict authorized slot quota bounds in Plantilla Tab 3 ([AddApplicantModal.tsx](file:///D:/Projects/ohmployee-web/src/components/vacancy/AddApplicantModal.tsx), [MarkHiredModal.tsx](file:///D:/Projects/ohmployee-web/src/components/vacancy/MarkHiredModal.tsx), [VacancyDetailDrawer.tsx](file:///D:/Projects/ohmployee-web/src/components/vacancy/VacancyDetailDrawer.tsx), [PlantillaTableViews.tsx](file:///D:/Projects/ohmployee-web/src/components/plantilla/directory/PlantillaTableViews.tsx), [PlantillaCardViews.tsx](file:///D:/Projects/ohmployee-web/src/components/plantilla/directory/PlantillaCardViews.tsx), [page.tsx](file:///D:/Projects/ohmployee-web/src/app/(dashboard)/plantilla/page.tsx), [page.tsx](file:///D:/Projects/ohmployee-web/src/app/(dashboard)/vacancy/page.tsx), [types.ts](file:///D:/Projects/ohmployee-web/src/lib/queries/vacancy/types.ts), [vacancyListing.ts](file:///D:/Projects/ohmployee-web/src/lib/queries/vacancy/vacancyListing.ts), [vacancyMutations.ts](file:///D:/Projects/ohmployee-web/src/lib/queries/vacancy/vacancyMutations.ts), [multi_position_vacancy_intake.test.mjs](file:///D:/Projects/ohmployee-web/src/lib/queries/__tests__/multi_position_vacancy_intake.test.mjs), [vacancy_web_state.md](file:///D:/Projects/ohmployee-web/docs/state/vacancy_web_state.md)). (1) Multi-Position Intake: When a store requisition requires 2+ positions under a single VCode (ADR-002 Invariant 2), `AddApplicantModal` queries `vacancy_requirements`. Auto-selects for single positions; surfaces interactive position selection cards for multi-position stores, disabling full positions and blocking submission until selected. Persists `vacancy_requirement_id` to `applicants`. (2) Disambiguation & Onboarding Linkage: Pipeline tab resolves candidate roles from `vacancy_requirements` + `positions`. `MarkHiredModal` threads requirement ID into `confirm_applicant_onboard` with legacy fallback selector. (3) Strict Slot Quota Bounds: Fixed multi-slot expansion in Plantilla Vacancy tab to bound rows strictly to approved headcount (`Math.max(1, Math.trunc(hcTotal))`), preventing excess rows from decommissioned slots (e.g. SM Aurora strictly renders 3 rows for 3 slots). Renamed table column to HC displaying `1` per row. (4) Verification: Passed all 263 unit tests, 0 ESLint errors/warnings, 0 secret leaks, 0 SQL contract violations, and clean Next.js 16.2.4 Turbopack build.
> Older entries trimmed 2026-11-24 (ohm#fix-get-web-current-user-context-ambiguity, ohm#deprecate-dormant-rbac-definitions, ohm#add-web-account-signup-and-admin-tools-toggle, ohm#standardize-plantilla-vacancy-stages-and-pending-closure, ohm#compact-reports-module-sweep, ohm#compact-reports-catalog-design, ohm#restrict-deficiency-review-to-hr-personnel) to keep this list to 5 — see git history for earlier entries in full.
> Older entries trimmed 2026-11-24 (ohm#deprecate-dormant-rbac-definitions, ohm#add-web-account-signup-and-admin-tools-toggle, ohm#standardize-plantilla-vacancy-stages-and-pending-closure, ohm#compact-reports-module-sweep, ohm#compact-reports-catalog-design, ohm#restrict-deficiency-review-to-hr-personnel) to keep this list to 5 — see git history for earlier entries in full.
> Older entries trimmed 2026-11-24 (ohm#add-web-account-signup-and-admin-tools-toggle, ohm#standardize-plantilla-vacancy-stages-and-pending-closure, ohm#compact-reports-module-sweep, ohm#compact-reports-catalog-design, ohm#restrict-deficiency-review-to-hr-personnel) to keep this list to 5 — see git history for earlier entries in full.
