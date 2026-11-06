# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.
*Standing UI Standard Loop Override:* The UI Standard loop (`ohm#l0u8s2d9` onward) runs WITHOUT an approval gate. The loop pauses only on the stop conditions in `docs/architecture/ui-standard-briefing.md` section 10 or when verification fails. This overrides the generic "stop and wait" rule for this project only. Do not ask for approval again unless a stop condition triggers.

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
1. **ohm#branch2-floating-assign-stationary (Floating "Assign Store" Auto-Stationary Assignment & UI Simplification on Branch2)**: Removed the "Assignment Type" (Stationary / Roving) radio buttons from `AssignStoreModal` (`src/components/plantilla/AssignStoreModal.tsx`), eliminating logical bugs where an employee deployed from floating status to a single target store could be mislabeled as Roving. Updated the mutation payload in `AssignStoreModal.tsx` and `assignFloatingEmployeeToStore` (`src/lib/queries/plantilla.ts`) to automatically set `deployment_type: "Stationary"` (omitting the non-existent `assignment_type` column to prevent schema cache errors). Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
2. **ohm#branch2-summary-slot-recon (Plantilla Vacancy Summary Slot Reconciliation & Floating VCode Binding on Branch2)**: Unified remaining capacity calculation across table, cards, and KPI summaries via `getVacancyRemainingCapacity` (`src/app/(dashboard)/plantilla/page.tsx`), ensuring open vacancy requisitions maintain at least 1 open slot capacity even amidst legacy occupant vcode mismatches. Fixed `assignFloatingEmployeeToStore` (`src/lib/queries/plantilla.ts`) and `AssignStoreModal` (`src/components/plantilla/AssignStoreModal.tsx`) to bind deployed employees to the target store's vcode (`targetStore.code`), preventing floating transfers from falsely occupying prior store vacancy codes in backend views. Sanitized staging database record for Joven Asana to point to Divimart General Trias (`CPRVJV13`), fully releasing Emilus Rosario (`CPSAJV31`) to 0/1 filled (1 open slot) and achieving 100% parity across table rows, tab badges (`3 slots`), and the Open Vacancies KPI card (3 slots total). Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
3. **ohm#branch2-vacancy-slot-recon (Plantilla Vacancy Slot Count Parity & Slot Column UI Refinement on Branch2)**: Fixed the vacancy slot capacity calculation in `getVacancyRemainingCapacity` (`src/app/(dashboard)/plantilla/page.tsx`) to strictly use `Math.max(0, total - filled)` (`hc_total - hc_filled`), removing premature subtraction of `hrProcessingCount` so pipeline slots remain counted as open until onboarded and deployed, achieving 100% parity between KPI cards, tab counters, and the Vacancy table (reconciling Emilus Rosario and 3-slot total). Refined the `Slot` column cell renderer in `StoreVacancyTable` and `VacancyCard` to display only the raw number (`1`, `2`) inside the red badge styling, removing the word "Vacant" and providing full capacity breakdown in hover tooltips. Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
4. **ohm#branch2-floating-to-active-transition (Floating to Active Transition Architecture & Mutation Fix on Branch2)**: Enshrined Rule #7 (Floating to Active Transition) in `docs/state/plantilla_web_state.md` and `.ai/briefing.md`. Fixed `assignFloatingEmployeeToStore` in `src/lib/queries/plantilla.ts` to set employee status to `"Active"` and comprehensively nullify all previous floating/separation dates, timestamps, and remarks (`separation_status`, `inactive_at`, `inactive_by`, `date_of_separation`, `resignation_date`, `remarks`, `deactivation_reason`, `for_deactivation_at`, `for_deactivation_by`, `deactivated_at`, `deactivated_by`). Extended cache invalidation in `src/components/plantilla/AssignStoreModal.tsx` across plantilla details, summary counters, and vacancies. Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
5. **ohm#branch2-multi-tier-demographic-hydration-guard (Multi-Tier Bulletproof Demographic Hydration Guard on Branch2)**: Sanitized `public.plantilla` table queries in `getWebPlantillaDetail` (`src/lib/queries/plantilla.ts`) removing non-existent snapshot columns that caused PostgREST 400 errors. Built an un-nested 5-tier fallback cascade (Tier 1: `plantilla`, Tier 2: `v_plantilla_safe`, Tier 3: `hr_emploc`, Tier 4: `employees`, Tier 5: `plantilla_import_rows`) guaranteeing that Date of Birth, Civil Status, Contact Number, and Residential Address are always hydrated. Hardened `formatBirthDateAndAge` against UTC timezone shifts and uppercased Civil Status in `src/app/(dashboard)/plantilla/[id]/page.tsx`. Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
