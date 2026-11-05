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
5. **Rule #5 (Employee Detail Navigation & State Preservation Contract):** Clicking an employee record across all status tabs (Active, On-Leave, Floating, Deactivation, Inactive) in both table and card views navigates to the dedicated full-page Employee Profile view (`/plantilla/[id]`), replacing the cramped right-side `PlantillaDetailDrawer`. The full-page view organizes employee data into 5 dedicated category tabs (Employment & Allocation, Work Schedule & Rate, Benefits & Statutory, Stores & Coverage, Activity & System Info) and features an always-visible top summary card and capability-aware actions bar (`Update Employment Status`, `Transfer Employee`, `Reassign HRCO`, `Request Deactivation`, `Request Deletion`). The return navigation link (`← Back to Plantilla`) strictly preserves the originating context (status tab, view mode `table` vs `cards`, search filter, account scope, and pagination page) via URL parameters, guaranteeing zero disruption of operational context when returning to the plantilla roster.

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
1. **ohm#branch2-streamline-employee-header-metadata-and-active-dot (Streamline Employee Detail Header Metadata & Add Active Green Dot Indicator on Branch2)**: Streamlined the employee summary card in `src/app/(dashboard)/plantilla/[id]/page.tsx` per UI design review: replaced the bulky `Active` badge with a sleek green status indicator dot beside the employee name, and removed redundant `VCode` and `Store` entries from the top metadata strip (keeping `ID`, `Position`, and `Date Hired / Tenure`). Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
2. **ohm#branch2-remove-deactivation-note-banner (Remove Ineligible Deactivation Note Banner from Dedicated Employee Detail Page on Branch2)**: Removed the static italic note callout (`Note: Employee must be moved to Floating or Inactive status before requesting official plantilla deactivation`) from the top summary card in `src/app/(dashboard)/plantilla/[id]/page.tsx`, keeping the header clean and relying on the button's native disabled state and hover tooltip. Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
3. **ohm#branch2-simplify-employee-detail-top-nav (Simplify Top Navigation Bar in Dedicated Employee Detail Page on Branch2)**: Streamlined the top navigation header on the Dedicated Employee Profile page (`src/app/(dashboard)/plantilla/[id]/page.tsx`) by removing the redundant top-right `Sync MIKA` button (consolidated under the `Benefits & Statutory` tab), removing the chevron divider and duplicate employee name breadcrumb (`> Name`), and eliminating full-width horizontal dividing border clutter for a clean, focused `← Back to Plantilla` return control with preserved query state. Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
4. **ohm#branch2-plantilla-dedicated-employee-profile-and-category-tabs (Plantilla Dedicated Full-Page Employee Profile with Category Tabs and State Preservation on Branch2)**: Replaced the cramped right-side `PlantillaDetailDrawer` with a dedicated full-page Employee Profile view (`/plantilla/[id]`). Implemented 5 full-width Category Tabs (`Employment & Allocation`, `Work Schedule & Rate`, `Benefits & Statutory`, `Stores & Coverage`, and `Activity & System Info`), an always-visible top summary card with initials avatar and metadata, and a top-anchored capability-aware action bar (`Update Employment Status`, `Transfer Employee`, `Reassign HRCO`, `Request Deactivation` respecting eligibility gates, and `Request Deletion`). Wired row and card clicks across all 5 employee status tabs (`Active`, `On-Leave`, `Floating`, `Deactivation`, `Inactive`) to route to `/plantilla/[id]` while preserving complete URL state (`status`, `display`, `search`, `page`, `accountId`) for seamless `← Back to Plantilla` return navigation. Enshrined permanent architectural Rule #5 in `.ai/briefing.md` and `docs/state/plantilla_web_state.md`. Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
5. **ohm#branch2-floating-tab-dole-tracking-and-slot-restriction (Plantilla Floating Tab DOLE Tracking, Table Layout Streamlining & Store Slot Restriction on Branch2)**: Added DOLE Article 301 compliance countdown tracking (`FloatingDoleBadge` / `getFloatingDurationDays`) across Floating tab table and card views to monitor the statutory 180-day temporary layoff ceiling (<30d: Fresh, 30–60d: Active aging, 60–120d: Elevated risk, >120d: Critical, ≥180d: DOLE Breach). Cleaned up `EmployeeFloatingTable` per design requirement (`image_a97f7f.png`) by removing the Status column and Details action button, keeping Assign Store as the primary action. Restricted `AssignStoreModal` store dropdown strictly to locations with available headcount slots (`hc_filled < hc_total`, e.g. `1/2`), completely filtering out fully occupied stores (`1/1`, `2/2`) to prevent over-allocation. Enshrined permanent architectural Rule #4 in `.ai/briefing.md` and `docs/state/plantilla_web_state.md`. Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
