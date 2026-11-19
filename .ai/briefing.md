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
1. **ohm#rbac-full-role-and-function-sanity-check (Comprehensive RBAC Sanity Test Suite Across All 11 Roles & Functions)**: Implemented exhaustive automated sanity test suite in `src/lib/utils/__tests__/rbac_sanity.test.mjs` verifying all 11 system roles across 7 test suites (249 total assertions): (1) Role Normalization & Numeric Levels: Verified canonical `AppRole` mapping, level assignments (10-100), and case/whitespace tolerance for all 11 roles and synonyms (added `recruitmentspecialist` and `managementviewer` to `normalizeRole`). (2) Role Groupings: Verified exclusivity for `isOwner`, `hasFullAccess`, `isDataTeam`, `isOpsTeam`, and `isEncoder`. (3) Module Allowance: Evaluated `isModuleAllowedForUser` across all 13 modules, verifying `/rbac` is locked exclusively to Super Admin (`level 100`) and administrative universal immunity for Head Admin (`level 90`). (4) 33 Authoritative Drawer Actions: Evaluated all 11 roles against 33 drawer actions (363 combinations) in `canPerformDrawerAction`, verifying Head Admin administrative immunity on operational actions and Super Admin exclusivity on the 4 SA-only actions (`Archive / Soft-Delete User Account`, `Terminate Active User Sessions`, `Toggle System Edit Lock`, `Manage Permission Matrix Overrides`). (5) Action Convenience Helpers: Confirmed 100% 1:1 behavioral parity between `canPerformDrawerAction` and all 33 wrapper helpers. (6) Specialized Functions: Verified `canAddApplicant`, `canManageApplicantPipeline`, `canEditApplicantProfile`, `canReviewVacancyClosures`, `canRequestVacancyClosure`, `canRequestHeadcountAdjustment`, and `canReviseHeadcountQuota`. (7) Approvals Categories: Verified `getAllowedApprovalCategories` across all roles. Converted `AppRole` from enum to const object + type alias with `.ts` relative imports to support both Node `--test` and Next.js compilation. Verified cleanly: 249/249 tests passing (`npm test`), 0 ESLint errors/warnings (`npm run lint`), and clean Next.js build (`npm run build`).
2. **ohm#rbac-independent-matrix-page (Standalone Hierarchical RBAC Matrix Page at /rbac)**: Built independent, full-page RBAC management interface at `/rbac` (`src/app/(dashboard)/rbac/page.tsx`) with Module / Route / Roles hierarchy, live cell toggles, multi-level reset, and staged atomic commits. (1) Backend Migration: Authored and applied `20262606000125_rbac_page_batch_matrix_rpc.sql` introducing `public.get_all_roles_effective_permission_matrix()`, returning all 11 roles × 58 definitions (638 rows) in a single fast, security-definer RPC guarded by `public.is_super_admin()`. Pushed to Staging (`qqiiznmqxfoamqytjica`) with exact live parity. (2) Route & Gating Security: Registered `rbac` module (`/rbac`, `KeyRound` icon) in `src/lib/modules.ts`, strictly locked to Super Admin (`roleLevel >= 100` / `isOwner`) in `src/lib/auth.ts`, `src/lib/rbac.ts`, and `src/components/DashboardAuthShell.tsx`. (3) Hierarchical Matrix UI: Implemented sticky columns, expandable module headers with route badges (`Vacancy` • `/vacancy`), role group filter pills (`All Roles (11)`, `Operations`, `Data Team`, `HR & Recruitment`, `Viewer`), search bar, and custom toggle switches. Super Admin column is permanently locked ON (`SA_PROTECTED`). (4) Staging & Atomic Reset: Floating bottom bar tracks staged changes with "Discard" and "Review & Save Changes" modal requiring audit justification via `apply_permission_overrides`. Added multi-level reset: inline cell revert, per-role column reset (`↺ Reset Role`), and global reset modal (`↺ Reset All Overrides`). Verified cleanly: 242/242 tests passing (`npm test`), 0 ESLint errors/warnings (`npm run lint`), and 22/22 routes compiling in Next.js Turbopack (`npm run build`).
3. **ohm#hr-emploc-role-actions-and-upload-cleanup (Restrict Upload Docs to Pending/Correction and Role-Based Action Column Hiding)**: (1) Upload Docs Restrictions: Removed `Upload Docs` buttons from `for_emploc`, `review`, and `deployed` tabs in `HrEmplocTable.tsx`, strictly restricting upload actions to `pending` and `correction` queues; guarded `Upload Docs` in `HrEmplocDetailDrawer.tsx` (header `actionSlot` and Section 6 card) to `Pending` and `For Correction` statuses only. (2) Role & Capability-Based Action Column Hiding: Implemented `roleHasActionsOnQueue(role, queue, rows)` in `HrEmplocTable.tsx` checking role eligibility per queue (Pending: Ops + SA; For Emploc: HR Personnel, Head Admin, Encoder + SA; Correction: Ops + SA; Review: HR Personnel + SA; Deployed: Head Admin, Encoder + SA) and verifying at least one row possesses executable capabilities; sets `shouldHideActions = true` to suppress the entire `Actions` column header and cells when a role has no operational actions on that tab. (3) Docs Column Removal on Corrections: Fully verified removal of `Docs` header from `getTableColumns("correction")` and suppression of document cells in `<tbody>`. Verified cleanly: 242/242 tests passing (`npm test`), 0 ESLint errors/warnings (`npm run lint`), and Next.js Turbopack build clean.
4. **ohm#hr-emploc-table-sla-and-action-cleanup (HR Emploc Action Visibility, SLA Color Coding & Column Clean-up)**: Resolved UI and usability gaps on HR Emploc table and drawer. (1) Action Visibility: Exposed `+ Add Emploc` as an explicit visible button on `Pending` queue in `HrEmplocTable.tsx` when `caps.can_assign_employee_no && onAddEmploc` is true, replacing the hidden 3-dots `<MoreVertical>` overflow dropdown. Propagated `onAddEmploc` to `HrEmplocDetailDrawer.tsx` (`actionSlot` header and Section 6 card) and wired it from `hr-emploc/page.tsx`. (2) Vertical Line Fix: Removed `shadow-[-4px_0_6px_-2px_rgba(0,0,0,0.06)]` from sticky Actions column in both `<th>` and `<td>`, eliminating the dark artificial vertical line artifact. (3) Docs Column Clean-up: Removed "Docs" column header and cells across `pending`, `for_emploc`, `correction`, and `default` queues (keeping "Attachment" exclusively on `review` queue). (4) Dynamic SLA Color Coding: Replaced static monotone SLA styling with dynamic `getSlaBadgeClass` (emerald for $\le 1$d, amber for $2$d warning, red for $\ge 3$d or breached), and updated detail drawer SLA breach badge to `variant="danger"`. Verified cleanly via 242/242 tests passing (`npm test`), 0 ESLint errors/warnings (`npm run lint`), and clean Next.js Turbopack production build (`npm run build`).
5. **ohm#super-admin-upload-docs-all-tabs (Super Admin Upload Docs Across All HR Emploc Tabs)**: Fixed document upload capabilities for Super Admin across all HR Emploc queue tabs (`Pending`, `For Emploc`, `For Correction`, `For Review`, `Deployed`). (1) Database Architecture: Created and applied migrations `20262606000120` through `20262606000124`. Updated `can_upload_hr_emploc_docs` to check `public.is_super_admin()` upfront prior to status checks, permitting Super Admin uploads across any queue while keeping non-Super Admin restricted to Pending/Correction. Refined `authorize_hr_emploc_doc_upload` and `register_hr_emploc_document` to bypass stage restrictions for Super Admin, and projected `can_upload_docs` across `list_web_hr_emplocs` and `get_web_hr_emploc_detail`. Pushed cleanly to Staging DB (`qqiiznmqxfoamqytjica`) with 0 contract errors across 649 migrations. (2) Frontend Action Exposure: Updated `HrEmplocTable.tsx` to render `Upload Docs` button across `for_emploc`, `review`, and `deployed` tabs whenever `caps.can_upload_docs` is true. Updated `HrEmplocDetailDrawer.tsx` to include an `Upload Docs` action button directly in Section 6 (Requirements & Attachments). (3) Modal State Transition Safety: Hardened `UploadDocsModal.tsx` so non-pending/non-correction uploads complete cleanly without attempting invalid state advancements (`submit_hr_emploc_requirements` or `submit_hrco_correction_update`). Verified cleanly via live RPC execution on Staging, 242/242 tests passing (`npm test`), 0 ESLint errors (`npm run lint`), and clean Next.js Turbopack production build (`npm run build`).
> Older entries trimmed 2026-11-15 (ohm#rbac-admin-immunity-bypass-web-mobile, ohm#streamline-cencom-plantilla-dual-computation, ohm#thin-arch-vacancy-dashboard-mobile-announcements) to keep this list to 5 — see git history for earlier entries in full.
