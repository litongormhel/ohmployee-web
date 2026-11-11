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

### ADR Architecture Lock Reference
ADR-001 location (read-only from mobile repo): `/Users/armanjr/Projects/OHMployee/OHMployee/.ai/architecture_locks/adr_001_coverage_architecture_v2.md`.
Do not edit the ADR from this web repo. If a loop requires an ADR update, log it in handoff under "ADR updates needed (Ohm applies in mobile repo)". In every loop report, state "ADR basis: <file + sections>".

### Permanent Architectural Rule Locks
1. **Rule #1 (Inactive Roster Persistence):** Employees who are disengaged, separated, or pending deactivation (`Resigned`, `AWOL`, `Terminated`) must **always** remain visible in the Inactive Tab for historical and reporting continuity. They must never be filtered out or hidden into isolated views that remove them from historical logs. Tab 5 (Deactivation) operates as a transactional queue for offboarding approval; Tab 6 (Inactive) serves as the persistent historical roster.
2. **Rule #2 (Safe Audit Logging):** Audit log triggers (`fn_audit_log`) must always use safe actor ID resolution (`resolve_audit_actor_id`) with fallbacks to `NULL` on `foreign_key_violation` to permanently prevent operational mutation failures (e.g. during employment status updates, resignations, AWOL, terminations) due to missing user profiles or FK constraints.
3. **Rule #3 (Plantilla Table & Universal Cards Contract):** The Deactivation Tab roster strictly enforces column layout `Emploc# / Member / VCode / Store / Position / Assignment / Status` (with Actions column completely removed); the Inactive Tab roster strictly removes `Clearance Status` and dynamically resolves operational/separation remarks from `plantilla.remarks` with waterfall fallback to `audit_logs`; and the `Table / Cards` view toggle must remain fully supported and crash-free across all status tabs (Active, On-Leave, Vacancy, Floating, Deactivation, Inactive).
4. **Rule #4 (Floating Compliance, Layout & Store Slot Restriction):** Floating records must continuously track duration and days elapsed for DOLE compliance monitoring (Article 301 maximum 180-day temporary layoff limit) via reactive countdown badges across table and card views. The Floating tab table strictly excludes the `Details` action button and the `Status` column, maintaining `Assign Store` as the single primary action. Store assignments for floating personnel in `AssignStoreModal` are strictly restricted to locations with open or available slots (`hc_filled < hc_total`, e.g., `1/2`), with fully occupied stores (`1/1`, `2/2`) filtered out and hidden to prevent over-allocation.
5. **Rule #5 (Employee Detail Navigation & State Preservation Contract):** Clicking an employee record across all status tabs (Active, On-Leave, Floating, Deactivation, Inactive) in both table and card views navigates to the dedicated full-page Employee Profile view (`/plantilla/[id]`), replacing the cramped right-side `PlantillaDetailDrawer`. The full-page view organizes employee data into 4 dedicated category tabs (Employment & Allocation, Schedule & Store Coverage, Benefits & Statutory, Activity & System Info) and features an always-visible top summary card and capability-aware actions bar (`Update Employment Status`, `Transfer Employee`, `Reassign HRCO`, `Request Deactivation`, `Request Deletion`). The return navigation link (`← Back to Plantilla`) strictly preserves the originating context (status tab, view mode `table` vs `cards`, search filter, account scope, and pagination page) via URL parameters, guaranteeing zero disruption of operational context when returning to the plantilla roster.
6. **Rule #6 (Store-Level Schedule & HC Allocation Matrix):** Merchandiser and store personnel scheduling supports granular, store-level duty day and shift time assignments paired with fractional Headcount (HC) Share distribution (e.g. Store 1: `MON-TUE-WED`, `8:00 AM - 5:00 PM`, `0.50 HC`; Store 2: `THU-FRI-SAT`, `8:00 AM - 5:00 PM`, `0.50 HC`). In the Dedicated Employee Profile (`/plantilla/[id]`), the previous separate 'Work Schedule & Rate' and 'Stores & Coverage' tabs are permanently consolidated into a single comprehensive **`Schedule & Store Coverage`** tab. It features a top global terms bar (Daily Wage, Designated Rest Days supporting 1, 2, or more days off, Assigned HR Coordinator) and a Store Schedule & Headcount Allocation Matrix displaying store branch, VCode, duty days, shift window, HC share, and external visibility presence badges (`DAYS • HC Share`). In `UpdateScheduleModal`, Store Name, VCode, and HC Share are strictly read-only to prevent encoding errors; store additions and deletions are completely removed (store assignments are governed exclusively by official Plantilla / Movement allocations); rest days support multi-select (e.g., Saturday and Sunday); and duty days and shift hours are fully configurable per store.
7. **Rule #7 (Floating to Active Transition):** When assigning a Store to a Floating employee (selecting a Vacant store with available slots), the system must immediately change the employee's status to **Active** (not Inactive), auto-set assignment type to **Stationary** (`deployment_type: 'Stationary'`), and bind their `vcode` to the target store's vacancy code (`vcode: targetStore.code`), releasing the previous store's slot. Because deployment from floating to a single initial store is strictly Stationary, the assignment type selector in `AssignStoreModal` is removed and auto-persisted behind the scenes. The employee is now deployed to that store, which consumes the vacancy slot and makes them appear in the Active Tab. All previous floating or separation dates, timestamps, and remarks (`separation_status`, `inactive_at`, `inactive_by`, `date_of_separation`, `resignation_date`, `remarks`, `deactivation_reason`, `for_deactivation_at`, `for_deactivation_by`, `deactivated_at`, `deactivated_by`) are strictly cleared/nullified upon deployment.

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
- NEVER connect to the production ref (`rwxelulyapjgaarlwkus`).

### After Every Completed Prompt (mandatory, in this order)
1. `.ai/briefing.md` — prepend PROMPT ID + title to "Last Completed Tasks" (keep only 5)
2. `.ai/handoff.md` — prepend full handoff entry
3. `docs/state/<module>_state.md` — surgical update if behavior changed
4. Local commit (see "Local Commit Rule" below)
5. Branch close-out — if a branch exists, Ohm verifies (`npm run lint` / `npm run build` /
   manual test), merges into `main`, then deletes the branch. AI only reports the branch.

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
1. **ohm#d9k4p1v7 (ADR-002 Invariant #16 Bi-Directional Identity Lock: 1 Person = 1 EMPLOYEE_NO)**: Implemented Bi-Directional Identity Invariant locking across client pre-validation and database RPCs to close duplicate person / typo employee number vulnerability. Enforced reverse check: normalized full name (`LAST_NAME` + `FIRST_NAME` + `MIDDLE_NAME`) cannot have multiple distinct `EMPLOYEE_NO`s within the import batch or against DB master records (`plantilla` / `employees`), preventing phantom duplicate employees and erroneous stationary allocations when roving employees have mistyped employee numbers. Updated `src/lib/utils/plantilla_normalization.ts`, `supabase/migrations/20261111000002_adr002_addendum_import_coalescing_and_invariants.sql`, `src/lib/utils/data_control_xlsx.ts`, `docs/architecture/adr002_plantilla_import_store_identity_and_governance.md`, and `docs/state/plantilla_web_state.md`. Added adversarial unit tests covering duplicate identity detection and legitimate roving employee validation in `src/lib/utils/__tests__/adversarial_coalescing_and_age.test.mjs`. Verified via `npm test` (211/211 passed), `npm run lint` clean (0 errors), and `npm run build` (Next.js 16.2.4 exit code 0); local commit on main.
2. **ohm#p5r2m9v1 (Verify Production Migration Push 100% Parity with Staging)**: Verified Ohm's successful remote migration push to Production (`rwxelulyapjgaarlwkus`). Ran live SQL verification against `supabase_migrations.schema_migrations`: confirmed Production now has exactly 515 migrations applied, achieving 100% parity with Staging (515) and local repository (515). All 13 previously missing migrations are confirmed applied without errors; local commit on main.
3. **ohm#c7k2v4m8 (Audit Migration Parity Across Local, Staging and Production)**: Performed an audit comparing `supabase_migrations.schema_migrations` across Staging (`qqiiznmqxfoamqytjica`), Production (`rwxelulyapjgaarlwkus`), and local repository (`supabase/migrations`). Confirmed Local (515) and Staging (515) are in 100% parity (0 missing). Identified exactly 13 migrations applied on Staging that are missing/unapplied on Production (`20261111000001` through `20261111000003`, and `20262606000083` through `20262606000092`). Confirmed 0 migrations exist on Production that are missing on Staging; local commit on main.
4. **ohm#m4s8d1q9 (Fix Staging Remote Migration Push Collisions & Parameter Defaults)**: Resolved errors blocking `supabase db push --remote --include-all` against Staging (`qqiiznmqxfoamqytjica`). Fixed PostgreSQL error 42P13 in `supabase/migrations/20261026000002_qa_reset_soft_archive_and_atomic_rollback.sql` by maintaining parameter default `p_input_user_id UUID DEFAULT NULL` on `public.resolve_audit_actor_id`. Resolved primary key collisions on `supabase_migrations.schema_migrations` caused by Branch 2 merge duplicate timestamps by renumbering `20262606000085` -> `20262606000090`, `20262606000086` -> `20262606000091`, and `20262606000087` -> `20262606000092`. Successfully applied all pending migrations to Staging; confirmed `Remote database is up to date` via dry run and clean `npm run lint` (0 errors); local commit on main.
5. **ohm#v3r8c1p9 (Verify Vercel Production Build Health and Deployment Status)**: Investigated Vercel deployment alert for `ohmployee-web-p64x` reporting a failed build on `main` ("pnpm run build exited with 1"). Verified local compiles via `npm run build` and `pnpm run build` (both exit 0), clean lint (0 errors), and test suite (209/209 passed). Inspected Vercel remote deployments via CLI: traced failure to prior intermediate merge commits on Nov 10 (`b8887f5` / `d5d146e`). Confirmed subsequent deployment `5amo4mmeq` succeeded, and the latest production deployment `dx0i0iq83` (`dpl_EoaoLf7yEYyQMejaY2iYPdqrgDiP`) for commit `aad0459` successfully built in 1m 21s with status `● Ready`. Verified live endpoint `https://ohmployee-web.vercel.app` returns HTTP 200 OK.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
