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
1. **ohm#require-middle-name-and-mobile-number-on-signup (Require Middle Name and Mobile Number on Web Account Sign-Up)**: Made Middle Name and Mobile Number mandatory required fields on the Web Account Sign-Up form (`/signup`). Updated form labels with red required asterisks (`*`) replacing `(Optional)`, added `required` input attributes, and integrated strict validation in `handleSubmit` ensuring non-empty middle name and valid 11-digit Philippine mobile numbers matching `^09\d{9}$` (supporting hyphens and spaces). Updated `SignupPayload` and `submitAccountRequest` in `src/lib/queries/signup.ts` to strictly type and pass normalized `middle_name` and `mobile_number` to Supabase Auth metadata and `fn_enrich_account_request`. Verified: 257/257 unit tests passed, 0 lint errors, and clean Turbopack build.
2. **ohm#add-web-account-signup-and-admin-tools-toggle (Add Web Account Sign-Up, Forgot Password, and Admin Tools Governance Toggle)**: Implemented end-to-end Web Account Sign-Up (`/signup`), Forgot Password (`/forgot-password`), Password Reset (`/reset-password`), and Super Admin governance controls in Admin Tools (`/more?tab=admin_tools`). (1) Backend Governance & Auth Trigger: Authored migration `20262606000167_wire_account_registration_governance_and_signup_guard.sql` integrating `fn_check_governance_control('account_registration')` into `handle_new_auth_user()` to reject unauthorized registrations with `P0001` when paused; extended `get_request_account_signup_options()` to return `is_registration_enabled` and non-admin roles (`role_level < 90`), groups, and accounts; added public RPC `is_account_signup_enabled()`. Pushed to Staging (`qqiiznmqxfoamqytjica`) with 0 errors. (2) Admin Governance Toggle: Added Super Admin Level 100 control modal `AccountSignupControlModal.tsx` and live Account Sign-Up Governance Card in Admin Tools (`/more?tab=admin_tools`) supporting 1-click Enable/Disable with audited reason logging (`fn_update_governance_control`). (3) Public Auth Screens: Built `/signup` with real-time governance status check, role/group/account cascading selector, metadata enrichment matching `handle_new_auth_user` schema, and pending administrator review state; added `/forgot-password` and `/reset-password` flows with branded OHMployee styling; updated `/login` with "Forgot password?" and "Request Account" links. Verified: 257/257 unit tests passed, 0 lint warnings, and clean Next.js 16.2.4 Turbopack production build.
3. **ohm#standardize-plantilla-vacancy-stages-and-pending-closure (Standardize Plantilla Vacancy Stage Badges & Pending Closure Capacity Preservation)**: Diagnosed and resolved pipeline counter discrepancy, coverage group requisition visibility, and stage badge alignment per user mandate. (1) Forensic Diagnosis: Clarified that `Pipeline = 1` on the Account Card is computed by `v_account_allocation_kpi` from `hr_emploc` (where candidate James AL on `CPSAJV27` is `Pending Emploc`), while `/vacancy` Pipeline tab displays active ATS screening candidates (`public.applicants`), where James AL is already `Confirmed Onboard` / `is_archived = true` (ATS count 0). Clarified that `CPPGJV19` was synthesized in Plantilla Vacancy tab because separated employee Eurie Baculi had inactive status with remarks `"Incomplete Docs"`, while anchor `CPSAJV27` was suppressed due to 0 required headcount in `CG-FG1-0005`. (2) Stage Badge Standardization: Standardized canonical workflow stages across Plantilla and Vacancy tables: `Vacancy - Open`, `Vacancy - Pipeline`, `Vacancy - Closure`, `HR Emploc - Pending`, `HR Emploc - For Emploc`, `HR Emploc - Correction`, and `HR Emploc - Review`. Added `Vacancy - Closure` (rose badge) and `HR Emploc - For Emploc` (indigo badge) variants. (3) Pending Closure Capacity Preservation & ADR Amendment: Aligned `resolveVacancyWorkflowStage`, `plantilla/page.tsx`, and `vacancyListing.ts` so that requisitions with pending closure requests retain their count in Open capacity and appear in the Open tab with `Vacancy - Closure` badge until administrative approval. Formally codified the approved Pending Closure Capacity Retention Invariant into `OHMployee/docs/architecture/adr/02_vacancy.md` (`2ad3464`) and synchronized web mirrors via `npm run sync:adr` (`0eb4407` → `2ad3464`). Verified: 257/257 unit tests passed, 0 lint errors, and clean Next.js 16.2.4 Turbopack build.
4. **ohm#default-light-theme-all-roles (Enforce Default Light Mode for All Roles & Fix Auto Dark Mode on Login)**: Fixed the defect where logging into different operational roles (e.g. HRCO, OM, Encoder, Recruiter, Store Supervisor, Viewer) automatically forced the application into dark mode. Forensic investigation revealed that database table `public.user_settings` had `theme_mode text NOT NULL DEFAULT 'system'` and trigger `handle_create_default_user_settings` provisioned user profiles with `'system'`. When logging in as any role on a device with OS dark mode (`prefers-color-scheme: dark`), `ThemeProvider` fetched `'system'`, synced it to `localStorage`, and resolved the theme to Obsidian dark mode. Created database migration `20262606000165_default_light_theme_all_roles.sql` setting `user_settings.theme_mode` default to `'light'`, updated all existing 41 user profiles to `'light'`, and updated `handle_create_default_user_settings` to explicitly initialize new users with `'light'`. Updated client-side authentication handlers in `login/page.tsx`, `Sidebar.tsx`, `more/page.tsx`, `DashboardAuthShell.tsx`, and `auth.ts` to normalize `localStorage.ohmployee_theme_mode` to `'light'` and purge stale React Query settings caches on sign-in and sign-out. Verified live on Staging (`qqiiznmqxfoamqytjica`) confirming 41/41 profiles set to `'light'` and clean `pg_get_functiondef`. Passed all 257 tests, 0 lint warnings, and clean Next.js 16.2.4 Turbopack build.
5. **ohm#fix-account-archive-reject-and-approval-rpcs (Fix Account Archive Approval & Rejection RPCs and Notifications RLS)**: Resolved the defect where clicking the Reject (or Approve) button in the Account Archives review queue (`/approvals?tab=account_archives`) failed to update or remove the request. Forensic diagnosis revealed that `public.notifications` RLS policy `notif_update_own` was restricted strictly to `recipient_user_id = auth.uid()` without granting update access to Super Admin (`i_have_full_access()`), and `requestAccountArchive` had erroneously set `recipient_user_id` to the requester's ID rather than broadcasting to Super Admins. When reviewing notifications authored by another user (e.g. `EUROMED PLANT` by UAT Test 3), direct updates from the client failed RLS with 0 rows updated, and the client swallowed the error without updating `is_archived = true`. Created dedicated database SECURITY DEFINER RPCs `public.reject_account_archive` and `public.approve_account_archive`, aligned `notif_update_own` RLS policy to include `OR (SELECT i_have_full_access())`, nullified user-siloed `recipient_user_id` on existing archive requests, updated `src/lib/queries/requests.ts` and `src/lib/queries/plantilla.ts`, and hardened modal state cleanup in `AccountArchiveDataTable.tsx`. Authored and applied migration `20262606000164` cleanly to Staging (`qqiiznmqxfoamqytjica`).
> Older entries trimmed 2026-11-24 (ohm#compact-reports-module-sweep, ohm#compact-reports-catalog-design, ohm#restrict-deficiency-review-to-hr-personnel, ohm#slot-drawer-and-store-vcode-audit-polish, ohm#phase4-mixed-roving-hc-mobile) to keep this list to 5 — see git history for earlier entries in full.
