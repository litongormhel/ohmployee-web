# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.
*Standing UI Standard Loop Override:* The UI Standard loop (`ohm#l0u8s2d9` onward) runs WITHOUT an approval gate. The loop pauses only on the stop conditions in `docs/architecture/ui-standard-briefing.md` section 10 or when verification fails. This overrides the generic "stop and wait" rule for this project only. Do not ask for approval again unless a stop condition triggers.
*Scope-Expansion Rule:* If any later test or investigation shows a change is needed outside an approved plan (any function, table, file or migration not listed), STOP and present an amended plan. Do not extend scope.
*Post-Migration Live Diff Rule:* After applying any migration to staging, diff live `pg_get_functiondef` vs the committed file for every touched function.
*REPORTING INTEGRITY:* every table, count, SQL result, timestamp, assertion list and code excerpt in a report or handoff must be copied from a tool output of the current task, with the query or file and line shown. Never reconstruct, round, summarize from memory or fill in a result you did not obtain. If a check was not run, write NOT RUN. If a value is unknown, write NOT VERIFIED.

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

### ADR Architecture Lock Reference
ADR mirrors (read these): `docs/architecture/_mirror/ADR-001-ohmployee-system-architecture.md` and `docs/architecture/_mirror/adr002_plantilla_import_store_identity_and_governance.md` — read-only mirrors.
Source of truth: mobile repo `.ai/architecture_locks/` and `docs/architecture/` (Windows: `D:\Projects\OHMployee`; override with env `OHM_MOBILE_REPO`).
Freshness check + auto-sync every prompt: `npm run check:adr` / `npm run sync:adr` (rules in AGENTS.md § ADR Mirrors). Module → ADR section routing: `.ai/current_state.md`.
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
No DDL, function execution, or writes against any Supabase project without Ohm's explicit instruction in that prompt, and NEVER from a UI loop. All database access for UI work is strictly prohibited.

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
6. Conclude Turn Sign-off — conclude every response with both an explicit **Next Steps** section and a helpful `> [!TIP]` callout covering immediate next operational actions, relevant verification steps, or deployment commands.

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
1. **ohm#p5s1d8k2 (Plantilla Table Pagination Standardization to 15 Rows)**: Updated default page size for Plantilla Employee View from 10 to 15 rows and standardized `pageSizeOptions` across both Employee and Store Views to `[15, 30, 50]`. Enables medium-sized client rosters (such as MARIZ with 14 active employees) to render completely on Page 1 without pagination splits while utilizing reclaimed vertical viewport height. Verified cleanly via `npm run check:adr` (FRESH), `npm run check:sql` (28 core tables & 19 RPC contracts OK), `npm test` (211/211 passed), `npm run lint` (0 errors), and `npm run build` (Next.js 16.2.4 exit code 0); local commit on main.
2. **ohm#u8s2d9k3 (Plantilla Header & Layout Streamlining: Summary Cards Removal, Button Uniformity & Icon Deduplication)**: Streamlined the Plantilla account view (`/plantilla`) by removing the legacy 5-card metric section (Overall MFR donut, Active Deployed, Open Vacancies, HR Pipeline, Leadership Team) to reclaim ~130px of vertical space. Removed the misplaced `[role]` badge beside the account title in the header breadcrumb. Unified `+ Request Headcount` button styling to match `+ Coverage Group` and `Absorb Employees` as outlined enterprise action buttons. Deduplicated emoji icons on the `Employee View` and `Store View` switcher, preserving clean single Lucide SVG icons. Cleaned up unused helper functions and query hooks (`teamDirectoryQuery`). Verified cleanly via `npm run check:adr` (FRESH), `npm run check:sql` (28 core tables & 19 RPC contracts OK), `npm test` (211/211 passed), `npm run lint` (0 errors), and `npm run build` (Next.js 16.2.4 exit code 0); local commit on main.
3. **ohm#q4m8s2k1 (Audit and ensure QA simulation engine, multi-role relay, and QA Center UI readiness)**: Audited, hardened, and verified the complete QA Agents simulation feature in More Module (`/more?tab=admin_tools&tool=qa_center`). Verified surgical migration `20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` on Staging (`qqiiznmqxfoamqytjica`), implementing dual GUC role impersonation (`request.jwt.claim.sub` and `request.jwt.claims`), schema constraint compliance (`hr_emploc.status = 'Pending Emploc'`, `plantilla.status = 'Resigned'`), collision-proof test identifiers (`vcode`, `users_profile`), 6-role workflow relay (`Head Admin` -> `Encoder` -> `Recruitment` -> `HRCO` -> `HR Personnel` -> `Back Office` -> `Barrier Check`), atomic PL/pgSQL subtransaction rollback (`QA_SANDBOX_ROLLBACK_SUCCESS`), and step telemetry persistence into `qa_agent_runs` and `qa_agent_findings`. Built high-fidelity UI components (`QaSimulationRunner`, `QaStepTimeline`, `QaRunHistoryTable`, `QaFindingsViewer`) and client contracts in `src/lib/queries/governance.ts`. Implemented automated test runner `scripts/test_m3_e2e_staging_simulation.mjs` verifying live execution of `FULL_E2E_RELAY` and `VAC_ARCHIVE_001` on Staging, zero-pollution database state (0 records in `vacancies`, `plantilla`, `applicants`, `hr_emploc`, `users_profile`), and persistent telemetry. Verified cleanly via `npm run check:adr` (FRESH), `npm run check:sql` (28 core tables & 19 RPCs OK), `npm test` (211/211 passed), `npm run lint` (0 errors), and `npm run build` (Next.js 16.2.4 exit code 0); local commit on main.
4. **ohm#m9x4k2v1 (Unify Auto Context Loading, Workflow Safety Gates, and Cross-Repo SQL Contract Guard Across Mobile & Web)**: Synchronized Mobile (`D:\Projects\ohmployee`) and Web (`D:\Projects\ohmployee-web`) AI workflow governance and SQL anti-regression locks. Upgraded `scripts/check-sql-contracts.mjs` in both repositories (`collectMigrationEntries()`) to merge and scan all 630 unique `.sql` migrations across Mobile and Web so both repos verify the exact same 28 core tables and 19 cross-module RPC contracts. Added mandatory Auto Context Loading (`briefing.md` -> `current_state.md` Routing Index -> module state file -> `ADR-001` / `ADR-002`, starting every turn with `"Context loaded: <files + ADR sections>"`), the structured Module Routing Table in `.ai/current_state.md`, the SQL Function Surgical-Diff & Contract Gate, Uncertainty/ADR Conflict/Visibility Regression Gates, Task Decomposition Gate, and `ai-finish.ps1` / `ai-finish.sh` STATE 3 SQL contract enforcement to the Mobile repo. Verified clean via `npm run check:sql`, `npm test` (211/211 passed), `npm run lint` (0 errors), and `npm run build` (Next.js 16.2.4 exit code 0); local commits on main in both repos.
5. **ohm#g9s4k2v8 (Ecosystem-Wide SQL Schema & RPC Anti-Regression Gate + Canonical Migration 105 Slot/Link Restoration)**: Built `scripts/check-sql-contracts.mjs` and chained it into `npm test`, `npm run lint`, and `npm run check:sql` to permanently prevent cross-module SQL regressions across the entire OHMployee ecosystem. The guard dynamically extracts the physical column catalog across all 528 migrations (`CREATE TABLE`, `ALTER TABLE ... ADD COLUMN`, and dynamic `EXECUTE format('ALTER TABLE public.%I ADD COLUMN ...')`), validates every `INSERT`/`UPDATE` statement across 28 core tables (`stores`, `plantilla`, `plantilla_slots`, `plantilla_store_links`, `employee_store_allocations`, `plantilla_import_batches`, `vacancies`, `applicants`, `hr_emploc`, `coverage_groups`, `workforce_assignments`, `users_profile`, `audit_logs`, etc.), and locks invariant footprints across 19 critical RPCs. Restored the complete Migration `086` body (`plantilla_slots` provisioning/claiming, `plantilla_store_links` sync, `vacancies` shadow sync, `slot_history`, and `import_row_id` snapshots) + ADR-002 Rule #17 Last-Row-Wins coalescing into `supabase/migrations/20262606000105_fix_approve_plantilla_import_batch_store_columns.sql`. Added the mandatory SQL Function Surgical-Diff & Contract Gate to `AGENTS.md` and `.ai/briefing.md`. Verified clean via `npm run check:sql`, `npm test` (211/211 passed), `npm run lint` (0 errors), and `npm run build` (Next.js 16.2.4 exit code 0); local commit on main.

> Older entries trimmed 2026-11-13 (`ohm#z8m4k1p6`) to keep this list to 5 — see git history for earlier entries in full.
