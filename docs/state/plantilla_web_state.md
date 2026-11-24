# Plantilla Web State & Architecture Specification

> [!NOTE]
> **Governing Architecture:** Governed by [ADR-002: Plantilla Import, Store Identity, Headcount Governance & Rollback Architecture](../architecture/_mirror/adr002_plantilla_import_store_identity_and_governance.md).
> Key rules: 1 Store Name = 1 Permanent VCODE; Vacant baseline imports allowed; Auto-computed roving headcount fractions ($1/N$); Strict middle name rules; Per-Account HRCO auto-population and reactive backfill; 72-hour rollback window with strict Zero-Edit Lock.

## 1. Scope & Core Purpose

This document specifies the target architecture, visual structures, data contracts, and user workflows for the **Plantilla Web** module of the OHMployee Web dashboard. 

### Permanent Architectural Rule Locks
1. **Rule #1 (Inactive Roster Persistence):** Employees who are disengaged, separated, or pending deactivation (`Resigned`, `AWOL`, `Terminated`) must **always** remain visible in the Inactive Tab for historical and reporting continuity. They must never be filtered out or hidden into isolated views that remove them from historical logs. Tab 5 (Deactivation) serves as an action queue for pending deactivation processing, while Tab 6 (Inactive) is the persistent historical roster.
2. **Rule #2 (Safe Audit Logging):** Audit log triggers (`fn_audit_log`) and audit log callers (`log_audit_event`) must always use safe actor ID resolution (`resolve_audit_actor_id`) with fallbacks to `NULL` on `foreign_key_violation`. In addition, a universal trigger (`trg_safe_audit_logs_actor_id` on `public.audit_logs`) guarantees that any unresolvable actor ID not found in `auth.users` is automatically converted to `NULL` before constraint evaluation, permanently preventing operational mutation failures (e.g. during employment status updates, Floating, Resigned, AWOL, Terminated) due to missing auth users or FK constraints. 
3. **Rule #3 (Plantilla Table & Universal Cards Contract):** The Deactivation Tab roster strictly enforces column layout `Emploc# / Member / VCode / Store / Position / Assignment / Status` (with Actions column completely removed); the Inactive Tab roster strictly removes `Clearance Status` and dynamically resolves operational/separation remarks from `plantilla.remarks` with waterfall fallback to `audit_logs`; and the `Table / Cards` view toggle must remain fully supported and crash-free across all status tabs (Active, On-Leave, Vacancy, Floating, Deactivation, Inactive).
4. **Rule #4 (Floating Compliance, Layout & Store Slot Restriction):** Floating records must continuously track duration and days elapsed for DOLE compliance monitoring (Article 301 maximum 180-day temporary layoff limit) via reactive countdown badges across table and card views. The Floating tab table strictly excludes the `Details` action button and the `Status` column, maintaining `Assign Store` as the single primary action. Store assignments for floating personnel in `AssignStoreModal` are strictly restricted to locations with open or available slots (`hc_filled < hc_total`, e.g., `1/2`), with fully occupied stores (`1/1`, `2/2`) filtered out and hidden to prevent over-allocation. 
5. **Rule #5 (Employee Detail Navigation & State Preservation Contract):** Clicking an employee record across all status tabs (Active, On-Leave, Floating, Deactivation, Inactive) in both table and card views navigates to the dedicated full-page Employee Profile view (`/plantilla/[id]`), replacing the cramped right-side `PlantillaDetailDrawer`. The full-page view organizes employee data into 4 dedicated category tabs (Employment & Allocation, Schedule & Store Coverage, Benefits & Statutory, Activity & System Info) and features an always-visible top summary card and capability-aware actions bar (`Update Employment Status`, `Transfer Employee`, `Reassign HRCO`, `Request Deactivation`, `Request Deletion`). The return navigation link (`← Back to Plantilla`) strictly preserves the originating context (status tab, view mode `table` vs `cards`, search filter, account scope, and pagination page) via URL parameters, guaranteeing zero disruption of operational context when returning to the plantilla roster. 
6. **Rule #6 (Store-Level Schedule & HC Allocation Matrix):** Merchandiser and store personnel scheduling supports granular, store-level duty day and shift time assignments paired with fractional Headcount (HC) Share distribution (e.g. Store 1: `MON-TUE-WED`, `8:00 AM - 5:00 PM`, `0.50 HC`; Store 2: `THU-FRI-SAT`, `8:00 AM - 5:00 PM`, `0.50 HC`). In the Dedicated Employee Profile (`/plantilla/[id]`), the previous separate 'Work Schedule & Rate' and 'Stores & Coverage' tabs are permanently consolidated into a single comprehensive **`Schedule & Store Coverage`** tab. It features a top global terms bar (Daily Wage, Designated Rest Days supporting 1, 2, or more days off, Assigned HR Coordinator) and a Store Schedule & Headcount Allocation Matrix displaying store branch, VCode, duty days, shift window, HC share, and external visibility presence badges (`DAYS • HC Share`). In `UpdateScheduleModal`, Store Name, VCode, and HC Share are strictly read-only to prevent encoding errors; store additions and deletions are completely removed (store assignments are governed exclusively by official Plantilla / Movement allocations); rest days support multi-select (e.g., Saturday and Sunday); and duty days and shift hours are fully configurable per store. Under `ohm#7k2q9d4x`, `ohm#fix-update-schedule-modal-reset-clear-all`, `ohm#schedule-overlap-detection-and-auto-split`, and `ohm#soft-overlap-duty-day-toggle`, `UpdateScheduleModal` features a sticky footer (`Reset` with clear-all semantics wiping all rest and store duty days, live status text, `Cancel`, `Save`), live 7-day Weekly Coverage Preview strip (MON–SUN) with active conflict/overlap detection tiles (`⚠️ N Stores Overlap`), an amber schedule conflict banner with an instant `Auto-Split Days Evenly` quick-action button, compact rest day selector with automatic duty day carving and dismissible notification banner, collapsible store accordion cards (`① name · VCode · Mon, Tue · 8 AM – 5 PM · 0.25 HC`) with `⚠️ Overlapping` tags on conflicted stores, non-destructive duty day toggling where each store's schedule is edited independently without silently deleting days from other stores, cross-store aware duty day chips with `⚠️ Overlap` badges, per-day duration calculations, inline time error validation, "Apply this time to all stores" quick-action, and total weekly hours tracking. In the Dedicated Employee Profile (`/plantilla/[id]`), an amber alert card surfaces whenever a roving employee possesses overlapping duty days across stores, with a direct link to resolve in the schedule editor. 
7. **Rule #7 (Floating to Active Transition):** When assigning a Store to a Floating employee (selecting a Vacant store with available slots), the system must immediately change the employee's status to **Active** (not Inactive), auto-set assignment type to **Stationary** (`deployment_type: 'Stationary'`), and bind their `vcode` to the target store's vacancy code (`vcode: targetStore.code`), releasing the previous store's slot. Because deployment from floating to a single store is strictly Stationary, the assignment type selector in `AssignStoreModal` is removed and auto-persisted behind the scenes. The employee is now deployed to that store, which consumes the vacancy slot and makes them appear in the Active Tab. All previous floating or separation dates, timestamps, and remarks (`separation_status`, `inactive_at`, `inactive_by`, `date_of_separation`, `resignation_date`, `remarks`, `deactivation_reason`, `for_deactivation_at`, `for_deactivation_by`, `deactivated_at`, `deactivated_by`) are strictly cleared/nullified upon deployment. 
8. **Rule #16 (Multi-Row & Bi-Directional Identity Invariant):** Employee identity mapping is strictly bi-directional: (1) Forward Invariant: For multi-row `EMPLOYEE_NO` (roving) and existing DB master records (`plantilla` / `employees`), normalized `LAST_NAME`, `FIRST_NAME`, `MIDDLE_NAME`, and `DATE_HIRED` must strictly match across all rows. Any mismatch is **HARD BLOCKED**. (2) Reverse Invariant: Normalized full name `(LAST_NAME, FIRST_NAME, MIDDLE_NAME)` cannot have multiple distinct `EMPLOYEE_NO`s in the batch or against DB master records. Mismatched or typo employee numbers for the same person are **HARD BLOCKED**. Roving employees must share the exact same `EMPLOYEE_NO` across all rows.
9. **Rule #17 (Employee-Level Coalescing & Conflict Flag):** Employee-level demographic, compensation, and rest day fields (`POSITION`, `RATE`, `CIVIL_STATUS`, `DATE_OF_BIRTH`, `CONTACT_NO`, `ADDRESS`, `DAYOFF`) silently coalesce across blank rows sharing the same `EMPLOYEE_NO`. If conflicting non-blank values exist, the import emits a non-blocking **WARNING FLAG** and applies **Last-Row-Wins** persistence upon batch commit.
10. **Rule #18 (Minimum Age Enforcement 18+):** If `DATE_OF_BIRTH` is provided (or resolved via coalescing), the employee must be at least **18 years old** as of `DATE_HIRED` (or evaluation date). Underage records are **HARD BLOCKED** across all rows of that employee.
11. **Rule #19 (Canonical Schedule Day Expansion & Rest Day Carving):** Shorthand day ranges in `SCHEDULE_DAYS` and `DAYOFF` (e.g. `MON-SAT`, `MON-FRI`, wrap-around `SAT-TUE`, hybrid lists) are automatically expanded into discrete, canonical 3-letter day codes strictly ordered `MON` to `SUN`. Overlapping rest days are carved out from duty days to maintain mutually exclusive pill states in the Web UI. 
12. **Rule #20 (3-Way Store Inactive / Archive State Synchronization & Lineage Cleanup):** `fn_stores_sync_legacy_ins` and `fn_stores_sync_legacy_upd` enforce strict 3-way synchronization across `status = 'archived'`, `is_active = false`, and `is_archived = true` (with `archived_at = now()`). Setting any one of these columns automatically synchronizes the other two. When an account or import batch is archived, rolled back, or QA-reset, orphan stores with 0 active allocations, 0 active slots, and 0 open vacancies/requisitions are strictly archived to guarantee they never resurface in `+ Request Headcount` or Store rosters. All historically de-synced stores across the database (where `status = 'archived'` or `is_active = false`) are guaranteed aligned with `is_archived = true`. 
13. **Rule #21 (Rollback Records Re-Upload Eligibility & Archive Separation):** Plantilla records soft-archived by an import batch rollback (`status = 'Inactive', is_archived = true` with `source_baseline_import_batch_id` pointing to a rolled-back batch or `archive_reason ILIKE '%rollback%'`) must **never** be treated as operational archived or separated data during baseline batch imports. Re-uploading a file belonging to a rolled-back batch is **strictly allowed** and does not trigger `inactive_or_archived_existing_record`, emitting instead a non-blocking `rollback_safe_employee` flag. Pre-upload blocking remains enforced **only** if an employee already possesses a pre-existing genuine operational inactive/archived record (`status IN ('Inactive', 'Rejected Deactivation')` from actual separation, resignation, AWOL, termination, or non-rollback archive) that pre-dated the rollback ("unless may dating naka archive na data na na dagdag"). Upon approval of the re-uploaded batch, the system provisions a fresh active plantilla record under the new batch (`status = 'Active'`), preserving the rolled-back record's historical audit lineage without overwriting old batch snapshots. Archival stores under the same account and VCODE are cleanly reactivated. 
14. **Rule #22 (Automatic Inactive Status on Effective Date of Separation — ADR-001 Invariant 19):** When `date_of_separation` is populated on a `plantilla` record and is effective (`date_of_separation <= CURRENT_DATE`), database trigger `trg_plantilla_auto_separation_sync` automatically transitions the employee's status to `'Inactive'` (even if a formal deactivation request was not yet filed or approved). The employee is immediately excluded from active deployed headcount (`Actual = 0`), and trigger `trg_plantilla_vacate_slot_on_inactive` automatically vacates any occupied slot in `plantilla_slots` (`slot_status = 'open'`), reopening the store's replacement vacancy.
15. **Rule #23 (1:1 Headcount to Physical Slot Identity & Active Deployed Filtering — ADR-002 Invariant 1 & 5):** Regardless of whether a store/position originated from Plantilla Baseline Import or Requisition / Headcount Request, authorized headcount maps 1:1 to physical rows in `public.plantilla_slots`. Every active deployed employee holds a corresponding occupied slot (`slot_status = 'occupied'`, `current_occupant_plantilla_id = plantilla.id`). In `StoreDetailsModal`, the `Deployed Personnel` tab strictly filters out separated/inactive/deactivated personnel (`status IN ('Inactive', 'Deactivated', 'Separated')`), rendering only genuinely active/on-leave staff with dynamic badge variants reflecting their true operational status. 
16. **Rule #24 (Two-Digit Year Pivot Hardening & Birthdate Calendar Normalization):** Two-digit year inputs (`YY`) in Excel imports and date strings are strictly normalized with a dynamic pivot window: if `2000 + YY > CURRENT_DATE + 1 year` (e.g. `68` -> `1968` instead of `2068`), the date pivots to the 20th century (`1900 + YY`), preventing negative ages. Excel numerical zero-date artifacts (`1/0/00`, `0/0/00`, `0`) and calendar dates earlier than `1900-01-01` (such as `0001-01-01 BC`) are strictly nullified in `public.safe_parse_date` and client-side `normalizeDateToIso`. In database views (`public.v_plantilla_safe`) and UI screens across Web and Mobile, age calculations are guarded with boundary checks ($0 \le \text{age} \le 120$ and $\text{dob} \le \text{today}$), permanently preventing negative or astronomical ages from displaying. 
17. **Rule #25 (Multi-Slot Candidate Expansion & Slot-Level Parity — ADR-002 Invariants 1 & 5, Rule 8):** In Plantilla Tab 3 (Vacancy), multi-slot store requisitions (`required_headcount > 1`) and requisitions with multiple active onboarding/pipeline candidates strictly expand into 1 row per physical slot (`1 Row = 1 Individual Slot`). Each slot independently reflects its assigned candidate details (`applicantName`, contact, onboarding stage badge `HR Emploc - *` or `Vacancy - Pipeline`), and remaining unfilled slots render as distinct `Vacancy - Open` rows with sequential `slotOrdinal` badges (`Slot 1`, `Slot 2`, `Slot 3`). The tab roster count matches the total unfilled physical slots count in the tab badge (`Vacancy X (Y slots)`), guaranteeing that no candidate is collapsed or hidden. 
18. **Rule #26 (Option A Standard: Strict Slot-Level Granularity & Multi-Position Independence — ADR-002 Invariants 1 & 5, Rule 8, Rule 26):** In Plantilla Tab 3 (Vacancy), every physical slot in a multi-slot store requisition strictly renders as a distinct, solo row (`1 Row = 1 Physical Slot / Tao`). (1) Anti-Table Jitter Lock (Zero-Collapse Rule): Unassigned open slots with zero applicants are NEVER merged or collapsed into a single summary store row, guaranteeing zero layout jumping when candidates are added or dropped, zero pagination displacement, and 100% parity between rendered table rows and the total slots counter in the tab badge (`Vacancy X (Y slots)`). (2) Multi-Position Independence: When multiple positions exist under the same store/VCode (e.g. 2 Cashiers + 1 Bundler), each slot independently reflects its physical position (`plantilla_slots.position` or `hr_emploc.position`), allowing precise position filtering and preventing multi-position stores from collapsing into a single position label. (3) Sequential Slot Ordinal Identity: Each slot row displays its distinct sequential slot badge (`Slot 1`, `Slot 2`, `Slot 3`) providing direct operational clarity across recruitment and store management. 

The **Plantilla** module is the final authority and active directory for all deployed personnel across the organization. In the operational hiring and deployment pipeline, a record progresses through the following canonical stages:

```
Vacancy → Applicant → Endorsed to Ops → Confirmed Onboard → HR Emploc (Onboarding Compliance) → Plantilla Approval (Movement) → Plantilla (Official Active Employee)
```

The core responsibilities of the Plantilla Web module are:
1. **Roster & Directory Authority**: Maintaining the single source of truth for active employee allocations, personal records, and employment statuses.
2. **Budgetary & Capacity Control**: Auditing active store placements against contracted store plantilla capacities to prevent over-allocation.
3. **Headcount Extensions**: Governing requests, reviews, and allocations for temporary or seasonal **Additional Headcount (AH)**.
4. **Personnel Movements**: Tracking active transfers, roving assignments, and multi-store scheduling splits.
5. **Clearance & Offboarding**: Executing clean **Separation Workflows** (Resignations, Terminations, Backouts) backed by interactive clearance tracking and row edit overlays.

Like other modules in OHMployee Web, this is designed as a thin admin presentation layer. **Supabase is the absolute authority** for data access scopes, Row-Level Security (RLS) enforcement, notification dispatch, and transactional mutations.

---

## 2. Dual Views Architecture (Employee vs. Store)

Admin users can switch seamlessly between reviewing individual personnel and auditing store capacity compliance. The Plantilla module implements **Dual Views** driven by a top-right segmented pill toggle (`[ Employee View | Store View ]`) beside uniform outlined action buttons (`+ Request Roving HC`, `+ Request New Store`, `+ Coverage Group`, `Absorb Employees`):

```
[ Plantilla Header (← Accounts / ACCOUNT_NAME) ]     [ Employee View | Store View ]  [ + Request Roving HC ]  [ + Request New Store ]  [ + Coverage Group ]  [ Absorb Employees ]
=================================================================================================================================================================================
Search: "Search employees, IDs, stores..."    [ All Stores (Area -> City) ]    [ All Types (Stationary / Roving) ]
=================================================================================================================================================================================
[ 6 Status Sub-Tabs: Active (count) | On-Leave (count) | Vacancy (count) | Floating (count) | Deactivation (count) | Inactive (count) ]
```

> [!NOTE]
> **Layout & Header Modernization (ohm#u8s2d9k3)**:
> In `ohm#u8s2d9k3`, the Plantilla account view was streamlined for enterprise density:
> 1. **Summary Cards Removed**: The legacy 5-card top metric widget (Overall MFR, Active Deployed, Open Vacancies, HR Pipeline, Leadership Team) was completely removed to reclaim ~130px of vertical space, bringing the employee and store rosters above the fold without requiring initial scrolling. Core status counts remain directly accessible via the sub-tab badges (`Active`, `Vacancy`, etc.).
> 2. **Account Breadcrumb Cleanup**: Removed the misplaced `{userRole}` pill badge previously rendered beside the account name (e.g. `← Accounts / MARIZ [Super Admin]`), avoiding confusion between billing account identity and user auth role.
> 3. **Action Button Uniformity**: Standardized `+ Request Headcount` to match `+ Coverage Group` and `Absorb Employees` as uniform outlined enterprise action buttons (`border border-border-default bg-surface-base ...`).
> 4. **Single-Icon View Switcher**: Removed duplicate emojis (`👥` and `🏬`) from the `Employee View` and `Store View` toggle buttons, standardizing exclusively on crisp Lucide SVG icons.
> 5. **Pagination Ergonomics (Employee 10 rows, Store 15 rows)**: Set Employee View default page size to 10 rows (with `[10, 15, 25, 50]` options) so roster rows and pagination controls fit comfortably above the fold on 1080p laptop displays without internal scrolling. Store View maintains a default of 15 rows (with `[15, 30, 50]` options) suited for dense capacity auditing.

> [!NOTE]
> **Batch Import Entry Point & Contract**: Plantilla baseline batch roster imports are centralized under **More → Data Control → Batch Imports** (`/more?tab=data_control&subtab=batch_imports&import=plantilla`). The legacy inline "Import Plantilla" header action button and `<PlantillaImportModal>` mount on `/plantilla` were removed in `ohm#9b5t3c7e` to prevent inline layout overlaps after batch imports became full-page views.
> For the governing validation contract, pre-upload dry-run blocking, roving status evaluation, and rollback requirements, refer to [ADR-002: Plantilla Import, Store Identity, Headcount Governance & Rollback Architecture](../architecture/_mirror/adr002_plantilla_import_store_identity_and_governance.md) § Invariant 4 and Invariant 10.
> Self-rolling-back SQL regression test harness is maintained at `scripts/tests/plantilla_import_regression.sql` (run before and after any change touching Import Plantilla).

### A. Employee View (Default)
When `Employee View` is active, the interface renders the **6 Status Sub-Tabs** with live count badges, filtering the employee directory:

1. **Tab 1: Active** (All Active Employees Only)
   - **Filter**: Employees with status `Active` (`employee != null` and `status == Active`).
   - **Columns**: `Member` (Avatar, Name, Emp No) | `Store` (Store Name + Area/City pill) | `Position` (Role) | `Assignment` (Stationary/Roving) | `Actions` (`Update` button opening `UpdateEmploymentStatusModal`). (Note: Redundant `Status` column, redundant Details button, and legacy "Standard Tier" subtitle under Position removed).

2. **Tab 2: On-Leave** (All On-Leave Employees Only)
   - **Filter**: Employees on official approved leave (`On-Leave` or `On Leave`).
   - **Columns**:
     - `Member` (Avatar, Name, Emp No)
     - `Store` (Store Name + Area/City pill)
     - `Position` (Role)
     - `Leave Reason`: Displays the leave reason matching the modal dropdown options (`Sick / Medical Leave`, `Maternity / Paternity Leave`, `Vacation Leave`, `Emergency Family Leave`, `Other Authorized Leave`), dynamically resolved via `resolveLeaveDetails` from `plantilla.remarks` and `audit_logs` (with waterfall fallback to valid dropdown reasons).
     - `EDR`: Expected Date of Return displayed as a formatted date (resolved from active reliever temporary coverage `endDate` in `v_workforce_store_temporary_coverage` or remarks/metadata, displaying em dash `—` if unassigned). Includes reactive two-tier SLA indicators (`getEdrLapseStatus`): Days 1–2 past EDR display amber badge `Lapsed ({d}d) • HRCO Notified` (alerts HRCO to update status or return to Active); Day 3+ displays critical red badge `Breached ({d}d) • OM Escalated` (escalates to Operations Manager as SLA Breach). Backend daily sweep `check_on_leave_edr_sla()` dispatches corresponding notifications via `notify_user` with daily deduplication guards.
     - `Reliever (Moses HQ)`: If a reliever is assigned via `workforce_assignments` (`v_workforce_store_temporary_coverage`), shows `Reliever Name` and `Reliever Emp ID`. If unassigned, displays only the action button `+ Assign Reliever` (opening `AssignRelieverModal`) without the redundant `Unassigned` label.
     - `Actions`: `Return to Active` button (opens `ReturnToActiveModal` with return date picker and Reliever Auto-Release notice, invoking `updatePlantillaEmploymentStatus`). Row click navigates to full profile view.

3. **Tab 3: Vacancy** (All Open Slots + HR Onboarding Pipeline)
   - **Filter**: Unfilled required slots (`1 Row = 1 Individual Slot`), housing both unassigned vacancies (`Status: Vacancy - Open`) and onboarding candidates (`Status: Vacancy - Pipeline` or `HR Emploc - *`) until Day-1 store deployment. Loaded via `listVacancies` with `pageSize: 2000` (supported by `MAX_PAGE_SIZE = 5000` in `vacancy.ts`), with applicant and HR Emploc status enrichment. Requisitions with unfulfilled capacity (`v.hcFilled < v.hcTotal`) are protected from premature deduplication drops.
   - **Inactive Personnel Slot Reopening Parity**: When an employee becomes inactive (`Resigned`, `AWOL`, `Terminated`, `Separated`), their store allocation is deactivated (`employee_store_allocations.is_active = false`), their slot in `plantilla_slots` is set to `open` (`current_occupant_plantilla_id = NULL`), and their vacancy is reopened in `public.vacancies` (`status = 'Open'`, `is_archived = false`). In the Plantilla UI and Vacancy module, any vacated slot not occupied by an active employee is guaranteed to appear in **Tab 3: Vacancy**, ensuring strict headcount reconciliation ($\text{Active Deployed} + \text{Open Vacancies} = \text{Target Required}$, e.g. $752 + 3 = 755$ for ALTURAS).
   - **Floating Redeployment VCode Binding & Slot Invariant (ohm#b7v6m1k9)**: When assigning a store to a floating personnel, `vcode` in `public.plantilla` must strictly bind to the destination store's permanent VCode (`targetStore.code`), 1 open slot in `public.plantilla_slots` under that store must transition to `slot_status = 'occupied'` (`current_occupant_plantilla_id = employee.id`), and `public.employee_store_allocations` must insert/activate the store allocation. Stale VCodes from vacated stores must never persist on active master records, preventing false suppression of the source store's open vacancy in Tab 3.
   - **Archived & Closed Outlet Protection**: Ghost vacancies are strictly prevented from resurrecting closed stores or archived requisitions. Synthetic vacancy generation for inactive personnel strictly excludes any VCode that belongs to an archived/closed vacancy or an inactive/archived store (`stores.is_active = false`, `stores.is_archived = true`, `status = 'archived'`). In addition, approved store closure requests (`handle_closure_approval`) automatically cascade to deactivate the store in `public.stores` and close all dangling open/pipeline slots in `public.plantilla_slots`.
   - **Automatic Active Transition Rule**: The moment a candidate completes onboarding and moves to Plantilla (via `move_to_plantilla` or approved import batch), their slot is marked occupied: the record immediately **disappears** from **Tab 3: Vacancy** and appears under **Tab 1: Active**. Multi-headcount requisitions stay visible only if remaining unfilled slots exist.
   - **Sub-Filters**: `All Vacancies (count · slots)` | `Open / Unassigned (count · slots)` | `HR Pipeline (For Emploc) (count · slots)`. Top KPI cards `Open Vacancies` and `HR Pipeline` display synchronized live headcount slot counts (with requisition count subtitles) and auto-filter this tab.
   - **Detailed Stage Status Labels**:
     - *Open / Unassigned Group*:
       - `Vacancy - Open`: For vacant slots with no applicant assigned or attached (neutral gray badge).
       - `Vacancy - Closure`: For requisitions flagged with a pending closure request (rose badge). While pending approval, the requisition remains counted in Open capacity.
     - *HR Pipeline Group*:
       - `Vacancy - Pipeline`: Initial candidate recruitment pipeline state (blue badge).
       - `HR Emploc - Pending`: When candidate is in pending employee-location/onboarding stage (`hr_status = 'Pending'` or `'Pending Emploc'`, amber badge).
       - `HR Emploc - For Emploc`: When candidate is queued for Emploc processing (`hr_status = 'For Emploc'`, indigo badge).
       - `HR Emploc - Correction`: When details require correction (`hr_status = 'For Correction'`, red badge).
       - `HR Emploc - Ready`: When ready for final processing/onboarding (`hr_status = 'Complete'` or `'Ready for Plantilla'`, emerald badge).
       - `HR Emploc - Review`: Under review by HR/Ops (`hr_status = 'For Review'`, purple badge).
   - **Columns (Strict 9-Column Sequence, Actions column deleted)**:
     1. `VCode / CGCode`: Dedicated primary column displaying `VCode` or `CGCode`.
     2. `Store Branch / Anchor Branch`: Clean branch name with subtle `Roving` badge if roving.
     3. `Area & City`: Store location pill.
     4. `Applicant`: Candidate name synced live from Vacancy/HR Emploc (empty state: muted `—`).
     5. `Stage`: Stage badge (`Vacancy - Open`, `Vacancy - Pipeline`, `Vacancy - Closure`, `HR Emploc - Pending`, `HR Emploc - For Emploc`, `HR Emploc - Correction`, `HR Emploc - Ready`, `HR Emploc - Review`).
     6. `Aging`: Aging days (`Xd`) calculated from Effective Vacancy Date (`vacantDate`).
     7. `Position`: Position title.
     8. `Slot`: Dynamic capacity badge: In Plantilla Vacancy, member stores maintain **1:1 rows per store** (`consolidateCoverageGroups: false`), displaying each store's dedicated `VCode` and branch name with `Roving` badge. Roving slots render fractional roving capacity `${rovingSlotShare} Vacant` (e.g. `0.5 Vacant` for 2 stores, `0.33 Vacant` for 3 stores). For stationary multi-headcount requisitions, renders `${remainingCapacity} Vacant (${hcFilled}/${hcTotal})` or `${remainingCapacity || 1} Vacant` for single-slot lines.
     - **Store-Level Invariant**: Coverage group rows are never merged in Plantilla Vacancy; consolidation into 1 row under `CGCode` is strictly scoped to the Vacancy Module (`/vacancy`). Each store slot appears 1:1. Single-VCode deduplication prevents duplicate synthesis without suppressing distinct member store rows.
     9. `Remarks`: Displays latest operational/recruitment remarks (`ops_remarks`, `recruitment_remarks`, or general `remarks` from candidate pipeline, or `hr_remarks`, `correction_reason`, or `ops_remarks` from HR Emploc issues, with fallback to vacancy requisition remarks or empty state: `—`). Also rendered as a quote pill in Card view for full view-mode parity.
   - **Row Interaction**: Entire row has `cursor: pointer` and opens the interactive `VacancyDetailDrawer` with inline editable Effective Vacancy Date (`vacantDate`) for instant reactive aging recalculation.

4. **Tab 4: Floating** (All Floating Employees Only)
   - **Filter**: Employees with status `Floating` (active employees temporarily awaiting store redeployment).
   - **DOLE Compliance Tracking**: Every floating record tracks days elapsed since effective separation/floating date (`separationDate` with fallback to `updatedAt` / `createdAt`) and renders a prominent color-coded countdown badge against the DOLE Article 301 180-day statutory temporary layoff ceiling (<30d: Fresh, 30–60d: Active aging, 60–120d: Elevated risk, >120d: Critical, ≥180d: DOLE Breach).
   - **Columns (Strict 5-Column Sequence, Status column and Details action removed)**:
     1. `Member`: Avatar initials, display name, monospace employee/VCode ID, and inline `FloatingDoleBadge`.
     2. `Store`: Muted italic `Unassigned` with store area/city location pill.
     3. `Position`: Position title with plantilla tier tag.
     4. `Assignment`: `Roving` or `Stationary` assignment badge.
     5. `Actions`: Dedicated `Assign Store` action button only (`Details` button and `Status` column are strictly removed).
   - **Store Slot Restriction**: The `Assign Store` modal filters stores strictly to those with available headcount slots (`hc_filled < hc_total` or open vacancy slots > 0). Fully occupied stores (`1/1`, `2/2`) are hidden to prevent over-allocation.
   - **Row Interaction**: The entire row is clickable (`cursor: pointer`), triggering the interactive `PlantillaDetailDrawer`.

5. **Tab 5: Deactivation** (Pending Offboarding & Deactivation Requests)
   - **Filter**: Employees with pending/for-approval offboarding or deactivation requests (`pending for deactivation`, `for deactivation`).
   - **Columns (Strict 7-Column Sequence, Actions column removed)**:
     1. `Emploc#`: Monospace employee ID number (`row.employeeNo`).
     2. `Member`: Avatar initials circle with display name (`formatPersonName(...)`).
     3. `VCode`: Dedicated monospace `VCode` or `CGCode`.
     4. `Store`: Primary store branch name with location tag pill (`city • province`).
     5. `Position`: Position title with plantilla tier tag.
     6. `Assignment`: `Roving` or `Stationary` assignment badge.
     7. `Status`: Semantic status badge (`Pending for Deactivation` amber badge, `Deactivated` red badge).
   - **Row Interaction**: The entire row is clickable (`cursor: pointer`), triggering the interactive `PlantillaDetailDrawer`. The legacy `Actions` column has been completely removed to provide cleaner horizontal real estate.

6. **Tab 6: Inactive** (Historical & Attrition Archive)
   - **Filter**: Separated personnel marked as `Resigned`, `AWOL`, or `Terminated`, as well as personnel undergoing deactivation / separation (`isActive === false` or deactivation/separation statuses). When an employee transitions to Inactive, their vacated slot immediately spawns in the `Vacancy` tab and `Vacancy Module` with `Effective Vacancy Date = Separation Date`. Personnel requested for deactivation remain permanently visible in this tab for historical and reporting continuity even while actively tracked in Tab 5.
   - **Columns (Redesigned 7-Column Sequence with Deactivation Action)**:
     1. `Member / Employee`: Avatar initials, employee name, monospace employee ID, and Position directly beside Emploc ID (`{employeeNo}  {positionTitle}`).
     2. `Last Store Branch`: Store branch name (+ `Roving` badge if roving) with VCode/CGCode and Area & City location pill tag side by side below.
     3. `Separation Type`: Semantic separation badge (`Resigned` warning, `AWOL` danger, `Terminated` danger).
     4. `Separation Date`: Formatted separation date with tabular nums.
     5. `Status`: Deactivation lifecycle status badge (`Pending for Deactivation` amber badge, `Deactivated` red badge, or `Inactive` neutral badge).
     6. `Remarks`: Dynamically reflects operational remarks / separation notes resolved from `plantilla.remarks` with waterfall fallback to `audit_logs`.
     7. `Action`: If no existing request, renders `Request Deactivation` action button opening `RequestDeactivationModal` (calls `useCreateDeactivationRequest`). If already pending deactivation or deactivated, renders no action button (`—`).

---

### Universal Cards View Support Across All Tabs
The `Table / Cards` view toggle (`displayView: "table" | "cards"`) is universally supported and fully functional across all 6 status tabs:
- **Active**: Renders `EmployeeCard` with avatar, employee number, vcode, store, position, and status.
- **On-Leave**: Renders `EmployeeOnLeaveCard` with leave details, active coverage status (assigned reliever vs unassigned), and quick actions (`Assign Reliever`, `Return to Active`).
- **Vacancy**: Renders `VacancyCard` with VCode, store branch, position, dynamic slot capacity (`X Vacant`), workflow stage, aging days, and applicant badge.
- **Floating**: Renders `EmployeeFloatingCard` with status badge and `Assign Store` action button.
- **Deactivation**: Renders `EmployeeDeactivationCard` with Emploc#, VCode, store, position, and deactivation status badge.
- **Inactive**: Renders `EmployeeInactiveCard` with separation type, deactivation status badge, separation date, resolved operational/separation remarks, and quick `Request Deactivation` action when eligible.

All card views implement the responsive 3-column layout (`grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3`), smooth scrolling, empty states, and pagination integration.

---

### B. Store View (Store Capacity Table)
When `Store View` is active, the 5 Employee Status Sub-Tabs are hidden and replaced with the **Store Capacity Table** grouped per store branch:

- **Strict Population Logic & Roving Headcount Parity (Zero-Record Orphan Filter)**:
  - The Store View **ONLY** populates stores that have at least one associated record in the following states: **Active OR On-Leave OR Open Vacancy** (`activeDeployed > 0 || onLeave > 0 || openVacancy > 0`).
  - **Roving Fractional Headcount ($1/N$) & Multi-Store Visibility**: Stores assigned to roving personnel (via `employee_store_allocations`) are dynamically included in candidate stores and credited with the employee's fractional headcount (`filled_hc`, e.g. `0.33` for 3 stores). Open vacancies similarly multiply `remainingCapacity * rovingShare` (`1 / N` for Roving vacancies) and render with `formatCapacityCount` (`Number(val.toFixed(2)).toString()`). All roving member stores (e.g. `PUREGOLD QC`, `PUREGOLD BULACAN`, `PUREGOLD PILI`) remain fully visible in Store View with their proportional `Plantilla Required` and `Active Deployed` counts, rather than being suppressed or erroneously rounded to `1.00`.
  - Orphaned stores having 0 Active, 0 On-Leave, and 0 Vacancies (e.g., Festival Mall, SM Caloocan) are strictly filtered out and hidden from this view.
  - Stores with active deployed personnel whose records lack a direct `store_id` foreign key or are not pre-registered in `public.stores` under the current account portfolio (e.g., `Super 8 Dau`) are dynamically consolidated and fetched, preserving full visibility over operational deployments with fallback city/province lookup.
- **Default Pagination**:
  - Store View features a dedicated independent pagination controller defaulting to **15 rows per page** with `[15, 30, 50]` page size options.
- **Columns**:
  1. `Store Branch`: Keyboard-accessible store name opening `StoreDetailsModal`; the permanent VCode is always visible beside it. Deployment type is signaled directly on the VCode badge: blue for Stationary, violet for Roving, or indigo/dual-gradient for mixed slot capacity. Stores without an assigned VCode display a dashed `No VCode` badge in the same deployment color.
  2. `Area & City`: City and province pill tags.
  3. `Plantilla Required`: Contracted store headcount requirement (formerly Quota, centered).
  4. `Active Deployed`: Actual deployed headcount (centered, emerald bold text).
  5. `On-Leave`: Count of employees on leave for that store (centered, amber text).
  6. `Open Vacancy`: Unfilled headcount gaps (centered, red bold text if > 0; weighted by fractional roving share).
  7. `Fulfillment Status`: `100% Fulfilled` green badge (`active >= required`) or `Understaffed` amber/red badge.
  8. `Actions`: Per-row `Request HC` button (gated by `canRequestHeadcount`) opening `RequestHeadcountModal` pre-locked to that existing store (`lockedStore=true`, `lockedWorkforceType="stationary"`).
- **Deployment & History Detail**: Selecting a Store Branch opens `StoreDetailsModal`, featuring three dedicated tabs: `Deployed Personnel` (listing all active/on-leave employees assigned to that store with positions, schedules, and roving fractional shares), `Store History` (chronological timeline of slot modifications and activity logs via `useStoreHistory`), and `Plantilla Slots` (with `Inspect Slot` navigation to `SlotDetailDrawer`).
- **Slot Detail Drawer (`SlotDetailDrawer.tsx`)**: Inspecting any plantilla slot opens the dedicated right-side drawer:
  1. **Header VCode Badge**: Color-coded to match the slot's deployment type (Blue for Stationary, Violet for Roving, dashed for unassigned), accompanied by `Slot #ordinal`.
  2. **Clean Store Branch Subtitle**: Uses `formatStoreName` to strip obsolete `[roving]` naming suffixes.
  3. **Position Type Casing & Deduplication**: Intelligently resolves redundant raw casing (`stationary • Stationary` -> clean `Stationary`; `roving • Roving` -> clean `Roving`).
  4. **Slot Audit Trail**: Formats raw database remarks into clear enterprise audit entries (parsing `plantilla_update_separation`, `reason=RESIGNED/AWOL/TERMINATED`, and `auto_move_to_plantilla` into clear explanations and stripping internal RPC signatures, parameter dumps, and UUIDs), with old -> new status badges and resolved performer names.

---

### C. Top 5 KPI & Leadership Cards
Responsive 5-column grid (`grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4`) with centered content:
1. **Overall MFR**: Circular SVG progress ring with rounded caps (`stroke-linecap="round"`), dynamic stroke color (`100%` green `var(--pct-good-bar, #16a34a)`, `95%–99.99%` yellow `var(--pct-warn-bar, #ca8a04)`, `< 95%` red `var(--pct-bad-bar, #dc2626)`), centered percentage (e.g., `99.87%`), and footer `[activeCount] active / [requiredCount] required`.
2. **Active Deployed**: Metric count + subtext `Active deployed personnel`.
3. **Open Vacancies**: Metric count + subtext `Approved open vacancy slots`.
4. **HR Pipeline**: Metric count + subtext `Candidate onboarding pipeline`.
5. **Leadership Team**: Clean typography rows for `OM`, `TL`, `ATL`, and `HRCO`. Conditional rendering hides `TL` and `ATL` rows if no leader is assigned (`null`, `""`, or `"—"`).

---

### D. Hierarchical Area → City Filter Bar & Assignment Type Filter
- Dropdown options group stores by **Area** (`area:<province>`) with **Cities** (`city:<area_city>`) listed underneath.
- Selecting an Area filters all stores matching that province; selecting a City filters specifically for that city.
- Redundant "All Statuses" dropdown removed in favor of the 5 Sub-Tabs.
- **Universal Assignment Type Filter ("All Types")**: Filters personnel and stores by `Stationary` or `Roving` across both Employee View (checking `assignmentType`, covered stores $> 1$, and coverage group codes) and Store View (checking store deployment types: Stationary, Roving, and Mixed). Fully synchronized with the Reset Filters action.

---

### E. Reliever & Store Assignment Flows
- **`AssignRelieverModal`**: Queries available pool employees from `v_workforce_pool_employees` (`availability_status = 'Available'`), allows date range selection and notes, and inserts a coverage assignment into `workforce_assignments` linking `covered_plantilla_id`.
- **`ReturnToActiveModal`**: Confirms employee return from leave, provides an Actual Return Date picker, highlights the Reliever Auto-Release Notice (which unassigns relievers via DB trigger/`set_plantilla_active`), and invalidates plantilla caches.
- **`AssignStoreModal`**: Allows assignment of floating employees to stores, prioritizing open vacancies, setting assignment type (`Stationary`/`Roving`), and updating employee status to `Active`.

---

### F. Responsive Viewport Flex Layout & Compact Vertical Density
To ensure the interface auto-fits cleanly at 100% browser zoom on 1080p and 900p displays without vertical window scrolling clipping the pagination footer:
- **Compact KPI Cards**: Cards use `px-3 py-2` padding, metric counts are `text-2xl`, and the MFR Donut SVG is sized at `68px` with an inner `text-sm` percentage.
- **Section Spacing**: Tightened vertical margins (`gap-2` between sections; `h-8` sub-tab buttons; `h-8.5` filter inputs and dropdowns).
- **Flex-Viewport Auto-Fitting (`lg:h-[calc(100vh-5.5rem)] lg:overflow-hidden`)**: The desktop container uses responsive flex column constraints where the table container flexes (`flex-1 min-h-0 overflow-auto`) with a sticky table header (`sticky top-0 z-10 bg-table-header shadow-2xs`), ensuring the **Pagination Footer (`Showing X–Y of Z records`)** remains permanently visible on-screen at 100% zoom. Mobile viewports flow naturally with standard document scrolling.

---

## 3. Scoped RBAC Visibility & RLS Boundaries

Web presentations are governed strictly by the capabilities returned from `get_web_current_user_context()`. The Supabase backend enforces access boundaries at the table level using PostgreSQL Row-Level Security (RLS) policies.

```
                             [Role Access Matrix]
========================================================================================================================
Role             | Read Scope       | Personal PII Masking | Mutations (RPCs Allowed)
========================================================================================================================
superAdmin       | Global           | Unmasked             | Full transfers, separations, AH approvals, salary overrides
------------------------------------------------------------------------------------------------------------------------
headAdmin        | Global           | Unmasked             | Approve transfers, approve separations, review AH, adjust rates
------------------------------------------------------------------------------------------------------------------------
Encoder          | Scoped           | Unmasked             | Edit employee profiles, upload clearances, initiate transfers
                 | (Allowed Accts)  |                      | (BLOCKED: Final separation & rate approval)
------------------------------------------------------------------------------------------------------------------------
hrPersonnel      | Global           | Unmasked             | Verify clearances, initiate separations, audit roving coverages
------------------------------------------------------------------------------------------------------------------------
om               | Scoped           | Masked               | Request personnel transfers, request Additional Headcount (AH),
                 | (Allowed Accts)  |                      | initiate separation workflows for account staff
------------------------------------------------------------------------------------------------------------------------
hrco             | Scoped           | Masked               | Upload clearance files, submit transfer recommendations,
                 | (Allowed Accts)  |                      | report resignations/backouts
------------------------------------------------------------------------------------------------------------------------
atl / tl         | Scoped           | Masked               | Read-only scoped directory view. Roving check-ins audit.
------------------------------------------------------------------------------------------------------------------------
viewer           | Scoped           | Masked               | Read-only. (Mutation RPCs strictly blocked)
========================================================================================================================
```

* **Caller Validation**: All queries and RPCs fetch caller metadata directly from `auth.uid()`. The frontend never passes `profile_id` or `role_key` as arguments.
* **Super Admin Unrestricted SELECT Policies**: Dedicated permissive RLS policies (`plantilla_super_admin_select` on `public.plantilla` and `employees_super_admin_select` on `public.employees`) verify authenticated caller status via `public.users_profile` joined with `public.roles` (`role_name = 'Super Admin'` or `role_level >= 100`), `public.i_have_full_access()`, and JWT app/user metadata fallbacks, guaranteeing full read access to all plantilla and employee records across all status and lifecycle buckets.
* **Resilient Detail Query Fallback (`getWebPlantillaDetail`)**: To prevent false-positive access-restricted / 42501 blocks when viewing personnel, `getWebPlantillaDetail` wraps `get_web_plantilla_detail` in defensive try/catch and falls back to querying `public.v_plantilla_safe`, `public.plantilla`, and `public.employee_store_allocations` directly by UUID or employee number.
* **Scope Isolation**: In scoped roles (e.g. `om`, `hrco`), the backend filters all records to match the caller's authorized account and group list. If a scoped caller requests details for a personnel outside their hierarchy, the RPC raises an access-denied error.
* **Strict Plantilla Group & Account Scoping (Front-End & Presentation Layer)**:
  - Users with scoped permissions (including `HRCO`) only see the groups and accounts explicitly assigned to them in User Management.
  - Only users holding company-wide "All Scope" permissions (`groupScope.mode === 'all' && accountScope.mode === 'all'`, e.g. Super Admin, Head Admin, or users assigned to "Global HQ") are permitted to view all Plantilla groups.
  - The Plantilla group filter selector renders "All Assigned Groups" (or individual assigned group names) and strictly excludes unassigned groups for scoped users.
  - Direct URL access to unauthorized accounts (`?accountId=<unauthorized-id>`) is intercepted on the client and displays an `access_denied` state, preventing unauthorized account data queries.
  - All Plantilla sub-surfaces (Workforce Analytics, Pool Headcount Request, Reliever Coverage Request, Pool Conversion) use centralized `fetchPlantillaScopedAccounts` to strictly enforce this perimeter.

---

## 4. Masking Rules (PII Shielding)

To satisfy strict data privacy mandates, sensitive candidate details must be hidden or partially masked when displayed to non-authorized roles.

### A. Masked Fields & Formats:
1. **Personal Contact Number**:
   - *Format*: Mask all but country prefix and last 2 digits.
   - *Example*: `+63 917 *** **42`
2. **Personal Email Address**:
   - *Format*: Mask characters in the username, leaving only first character and domain.
   - *Example*: `s****s@domain.com`
3. **Residential Address**:
   - *Format*: Mask precise house numbers and streets, leaving only Barangay and City.
   - *Example*: `Unit ***, ******* Blvd, Cebu City`
4. **Base Salary & Day Rate**:
   - *Format*: Replace numerical characters with asterisks or replace the string entirely.
   - *Example*: `₱**,***.**` (or fully display `[RESTRICTED]`).
5. **Government IDs (SSS, PhilHealth, PagIBIG, TIN)**:
   - *Format*: Mask all but the last 2 digits.
   - *Example*: `03-****42-9`

### B. Security Enforcement Boundary (Backend Masking):
PII masking is **enforced at the database query layer (within SQL functions)** rather than on the client. 

The backend RPC checks the caller's role context via `get_web_current_user_context()`. If the user is a restricted role (`om`, `hrco`, `atl`, `tl`, `viewer`), the RPC returns already-masked strings. This guarantees that raw, unmasked PII is **never sent over the network**, preventing local memory audits or client console inspections from capturing sensitive information.

---

## 5. Deactivation Overlays & Status Styling

Personnel in deactivated, suspended, or pending separation states require immediate, prominent visual identifiers in the administrative grid. This prevents operational errors such as scheduling or deploying workers who are no longer active.

```
+-----------------------------------------------------------------------+
| Row: Active Employee (Normal display)                                 |
| EMP-001042  Santos, Maria      Cebu Regional     Active               |
+-----------------------------------------------------------------------+
| Row: Pending Separation (Dashed borders, 65% opacity overlay)         |
| ░░░ EMP-001101  Del Rosario, A.   Davao South    [Sep Pending]  ░░░░░  |
+-----------------------------------------------------------------------+
| Row: Inactive / Terminated (Dimmed grey background, crossed-out style)|
| [<s>EMP-001202  Abad, Clara       Manila Region  Terminated</s>]       |
+-----------------------------------------------------------------------+
```

### A. CSS / Tailwind Class Rules:
1. **Pending Separation**:
   - Row wrapper gains a dashed border: `border-dashed border-status-danger-border`.
   - Slight dimmed overlay: `opacity-80`.
   - Subtle alert highlight: `bg-red-50/30`.
2. **Inactive / Terminated / Suspended**:
   - Row opacity is dimmed: `opacity-65`.
   - Hover highlights are disabled: `hover:bg-transparent pointer-events-none`.
   - Font colors are grayed out: `text-gray-400`.
   - monospaced IDs and Names get strikethrough styling: `line-through decoration-gray-300`.

### B. Drawer Warnings:
When a deactivated or separation-pending record is viewed, the detail drawer renders an immediate top-anchored banner:
* **Pending Separation Banner**: `bg-status-danger-bg border border-status-danger-border text-status-danger-text p-3 rounded-md flex items-center gap-2 mb-4` showing: *"This employee has an active separation request pending clearance approval. Roster details are currently locked."*
* **Deactivated Banner**: `bg-status-neutral-bg border border-status-neutral-border text-status-neutral-text p-3 rounded-md flex items-center gap-2 mb-4` showing: *"This profile is INACTIVE. This record is locked and archived."*

---

## 6. Separation Workflows & Clearance Auditing

Transitioning a personnel out of the active Plantilla roster is a multi-step operation to ensure organizational clearances are satisfied before archiving the profile.

```
                   [Separation Workflow State Machine]
                                 
      +--------+     (Initiate Separation)     +--------------------+
      | ACTIVE | ────────────────────────────> | PENDING SEPARATION |
      +--------+                               +--------------------+
                                                         │
                                               (Complete Checklist)
                                               (Approve Clearance)
                                                         │
                                                         ▼
                                               +--------------------+
                                               | INACTIVE / ARCHIVED|
                                               +--------------------+
```

### A. Separation Types & Visual Triggers:
1. **Resignation (Voluntary)**:
   - *Requires*: Upload of signed resignation letter, 30-day notice period tracking, asset return checklist.
2. **Termination (Involuntary)**:
   - *Requires*: Upload of memo/disciplinary filings, immediate scheduling block, asset return checklist.
3. **Backout (Day 1 No-Show)**:
   - *Requires*: Coordinator confirmation. 
   - *System Action*: Deactivates the plantilla record and **automatically reopens** the corresponding original Vacancy slot (changes `vacancies.status` back to `Open` and increments open targets) so the recruiter can immediately fill it.
4. **Administrative Archive**:
   - *Use Case*: Fixing duplicate placements or data-entry errors. Archives the record without modifying vacancy metrics.

### B. Clearance Auditing Checklist (Detail Drawer View):
The detail drawer renders an interactive clearance board for records in `Pending Separation` status:
* **Asset Returns Checklist**:
  - `[ ]` Company Uniform Returned
  - `[ ]` Company ID Card Surrendered
  - `[ ]` Mobile SIM/Device Returned
* **Compliance Checks**:
  - `[ ]` Government ID Verification (SSS, PagIBIG, PhilHealth matches verified)
  - `[ ]` Handover Documentation Completed
* **Clearance File Attachment**: File uploader for signed clearance forms.
* **Separation Action Lock**: While `Pending Separation` is active, all other mutations (such as processing store transfers, editing base rates, or adding roving locations) are **strictly blocked and disabled**.

---

## 7. Additional Headcount (AH) Integration

Retailers often require temporary, seasonal, or campaign-based personnel who sit outside standard budgeted allocations. The Plantilla module integrates budgeted and temporary staffing into a single schema while preserving separate compliance rails.

### A. Budgeted vs. Additional Headcount (AH):
* **Budgeted Slots**: Contractual, long-term headcount targets approved at the Account/Store level (e.g. Cebu Mall is contracted for exactly 5 long-term Merchandisers). Deploys to these slots require matching available budget vacancy slots.
* **Additional Headcount (AH)**: Temporary slots created for specific durations (e.g., "Holiday Campaign 2026", "Store Launch Promo"). They require an approved business justification, target headcount size, and strict expiry dates.

### B. Additional Headcount Roster Workflow:
1. **Initiate Request**: Ops Managers (`om`) or Field Coordinators (`hrco`) submit an Additional Headcount Request through the dashboard, indicating target Store, Position, Count needed, Start Date, Expiry Date, and Business Justification.
2. **Approval Gateway**: The request is routed to the Approvals queue. `headAdmin` or `superAdmin` reviews and approves/rejects the request.
3. **Plantilla Adjustment**: Upon approval, the target store's available plantilla capacity is dynamically incremented by the approved amount under the `Additional` category.
4. **Personnel Assignment**: HRCOs can deploy incoming hires directly into these approved temporary slots. These employees are explicitly marked in the roster with `Plantilla Type = Additional Headcount`.

### C. Visual Indicators & Expiry Countdown Tickers:
* **Roster Badge**: Displays an orange-bordered semantic badge next to the employee name or type column: `bg-amber-50 border border-status-warning-border text-status-warning-text rounded px-1.5 py-0.5 text-xs font-semibold tracking-wide`.
* **Expiry countdown ticker**: If an AH personnel's slot is within 15 days of expiration, the detail drawer displays a countdown badge:
  - *Within 15 days*: `[Expires in 12 days]` in amber warning styling.
  - *Lapsed/Expired*: `[EXPIRED]` in rose danger styling with a recommendation to initiate a transfer or separation workflow.

---

## 8. Dedicated Employee Profile View (`/plantilla/[id]`) & Navigation Contract

Per **Rule #5 (Employee Detail Navigation & State Preservation Contract)**, clicking any employee row or card across the 5 employee status tabs (Active, On-Leave, Floating, Deactivation, Inactive) navigates to a dedicated full-page Employee Profile view at `/plantilla/[id]`, replacing the cramped slide-over drawer (`PlantillaDetailDrawer`).

### A. Navigation & URL State Preservation
- **State Continuity**: On row or card click, the parent page context is preserved in URL query parameters (`status` or `fromTab`, `display` mode `table` or `cards`, `page`, `search`, `accountId`).
- **Return Contract**: Clicking the top **`← Back to Plantilla`** link returns the operator to the exact status tab, display view mode, search filter query, and pagination page they originated from.

### B. Layout Architecture: Top Header & Prominent Action Bar
- **Top Summary Card**:
  - Avatar initials, Employee Full Name, Semantic Status Badge (`Active`, `On Leave`, `Floating`, `Pending Deactivation`, `Inactive`).
  - Metadata strip: Employee ID (`Emploc#`), VCode, Assigned Store, Position, Date Hired, and dynamic Tenure calculation.
- **Always-Visible Personnel Actions Bar**:
  - `Update Employment Status` (Primary brand button) → Opens `UpdateEmploymentStatusModal` (disabled when Inactive or Deactivated).
  - `Transfer Employee` → Opens `TransferPersonnelModal` (disabled when Inactive or Deactivated).
  - `Reassign HRCO` → Governed by the **2+ HRCO Visibility Rule**: only visible if 2 or more HR Coordinators are scoped to the employee's account/group; hidden if 0 or 1 HRCO. Opens `ReassignHrcoModal` allowing selection from available account/group HRCOs, displays currently assigned HRCO, and invokes `assign_hrco_to_plantilla` RPC with live cache invalidation (disabled when Inactive or Deactivated).
  - `Request Deactivation` → Opens `RequestDeactivationModal` (disabled for Active/On-Leave; disabled with "Deactivated" label when already deactivated; shows `"Deactivation Pending"` if pending).
  - `Request Deletion` → Routes deletion request to operations queue (disabled when Deactivated).
- **Deactivated State Action Lock**:
  - When an employee is Deactivated (`status === 'Deactivated'`), ALL mutation and action controls across the profile (`Update Employment Status`, `Transfer`, `Reassign HRCO`, `Request Deactivation`, `Request Deletion`, `Edit Schedule & Allocations`, `Sync from MIKA`) are strictly disabled with clear muted styling (`disabled:opacity-40 disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-text-muted`) and informative tooltips explaining that the employee is offboarded and read-only. A prominent offboarding notice banner is displayed below the summary card.

### C. Category Tabs Structure
The full-width content area is structured into 4 clean, uncluttered Category Tabs:
1. **Employment & Allocation**: Divided into two dedicated sections:
   - *Employment & Placement Specifications*: Features an equal-height 3-column compact specifications grid (`Coverage Group Code (CGCode)`, `Permanent VCODE`, `Designated Position`, `Employment / Assignment Type`, `Account Portfolio`, `Area / City / Province`, `Date Hired / Deployed`, and `Tenure`). CGCode is promoted as the first compact field with monospace formatting and a copy affordance; if unassigned/null, it displays an explicit muted italic `"Not assigned"` label (preventing confusing `"—"` dashes when roving overlays are not yet attached per ADR-002 Invariants 3 & 4). Permanent VCODE is displayed as its own distinct compact field with copy affordance so the store anchor code is never obscured.
   - *Assigned Store Allocations*: Full-width allocation section featuring card title, `ROVING • N STORES` summary chip, and an `HC` column header. Each store row cleanly displays `[● primary dot] STORE NAME` (bold uppercase) + `PRIMARY` badge if primary + store code / VCode sub-line with a plain right-aligned numeric allocation share (e.g., `0.50` or `1.00`, monospace tabular figures, zero `"HC"` suffixes, and zero bordered pill chrome). For multi-store roving personnel, includes a total summary row (`Σ Total Allocated` ... `1.00`, numeric only).
   - *Personal & Demographic Information*: 3-column card grid displaying Date of Birth (formatted with computed age and timezone-safe date parsing), Contact Number, Civil Status (formatted in uppercase), and full-width Residential Address. Guarded by an un-nested 5-tier hydration cascade in `getWebPlantillaDetail` (`public.plantilla` table, `public.v_plantilla_safe` view, `public.hr_emploc` onboarding snapshots, `public.employees` directory, and `public.plantilla_import_rows` batch import records), guaranteeing demographic completeness even when backend RPCs or intermediate tables omit fields.
2. **Schedule & Store Coverage**: Consolidated tab per **Rule #6**, uniting global compensation/scheduling terms and store allocations:
   - *Top Summary Bar (Global Work Terms & Rate)*: Base Daily Wage / Statutory Rate, Designated Rest Days (supporting multi-day off configurations with dynamic rest days count badge), and Assigned HR Coordinator / Supervisor. Clean layout focused exclusively on global compensation and supervisory assignment terms.
   - *Store Schedule & Headcount Allocation Matrix*: Positioned directly below Global Work Terms & Rate, housing the primary action button (`Edit Schedule & Allocations`) positioned alongside the live Total Allocation balance meter (`1.00 / 1.00 HC`). Breakdown of assigned stores with Store Branch Name, VCode (styled with high-contrast, dark-mode aware brand tokens `bg-brand-50 text-brand-700 dark:bg-brand-950/60 dark:text-brand-300 border border-brand-200 dark:border-brand-800`, permanently preventing washed-out white-on-white pills in dark mode), Duty Days (e.g. Store 1: `MON, TUE`, Store 2: `WED, THU`, Store 3: `FRI, SAT`), Shift Window (e.g. `08:00 AM - 05:00 PM`), Headcount (HC) Share (e.g. `0.33` for 3-store roving personnel, derived proportionally via `1 / N` store count when allocation percent is not specified or unbundled), and presence badge (`DAYS • HC Share`). Prevents over-allocation / 1.00 duplication across multi-store roving schedules. Header identity avatar (`JC`) is similarly styled with dark mode support (`dark:bg-brand-950/40 dark:border-brand-800 dark:text-brand-300`).
   - *Edit Modal (`UpdateScheduleModal`)*: Interactive modal allowing adjustments to duty days (multi-select pill toggles + presets) and shift time windows per store card, plus multi-select designated rest days standardized in size and proportions (`py-1 text-[11px] font-bold rounded`, `gap-1`) to match duty day toggles. Subtitle cleanly states `"Configuring rest days, per-store duty days, and shift time windows"`. Persistence invokes the authoritative `SECURITY DEFINER` RPC `update_plantilla_schedule` (with resilient fallback to direct `plantilla` mutation), updating `public.plantilla` (`deployment_type: "Roving" | "Stationary"`, `schedule_days`, `schedule_time`, `rest_day`, `dayoff`, `updated_at`) and atomically updating `public.employee_store_allocations` (`schedule_days`, `schedule_time`, `filled_hc`, `vcode`, `store_id`) across all assigned stores (with automatic reactivation of inactive rows and insertion if missing), without triggering 42501 permission or 42703 column errors. Under migration `20262606000133_project_store_schedule_in_plantilla_detail.sql`, `get_web_plantilla_detail` RPC projects `store_id`, `schedule_days`, `schedule_time`, and `filled_hc` into `roving_stores` / `covered_stores`, guaranteeing that each roving store retains and displays its distinct duty days both on profile view and when re-opening `UpdateScheduleModal`, eliminating primary-store schedule inheritance bugs. In the Employee Detail view header (`/plantilla/[id]`), the summary card layout switches at `xl:flex-row` with `flex-1 min-w-0` and `truncate` on `{displayName}` to prevent employee names from colliding into action buttons across all viewport widths. Guarded by `isScheduleComplete` (with resilient `08:00 AM - 05:00 PM` state fallbacks preventing false incomplete locks), `isHcValid` (validating headcount balance), strict rest day mutual exclusion (`hasRestDayConflict`), and strict roving overlap validation (`hasRovingConflict` / `rovingOverlapConflicts`) strictly preventing and alerting on overlapping duty days and shift windows across assigned stores. Store Name, VCode, and Headcount (HC) Share are strictly read-only, and store mutation buttons (`+ Add Store`, `Delete Store`) are disabled/removed, ensuring store assignments remain strictly governed by official Plantilla / Movement approvals.
3. **Benefits & Statutory**: Maskable government statutory IDs (SSS, PhilHealth, Pag-IBIG, TIN, ATM Payroll Account) with mask/reveal toggle (`Eye` / `EyeOff`), plus MIKA HRIS master synchronization trigger card.
4. **Activity & System Info**: Universal chronological audit timeline (`auditTimeline` / Lifecycle Event Log & Audit Timeline). Aggregates operational mutations from `public.audit_logs` (employment status updates such as `Tagged as On Leave`, `Returned to Active`, `Transferred to Floating`, `Personnel Separated`; schedule & allocation edits; store movements; HR coordinator reassignments; and MIKA synchronization), `public.employee_transfers` (transfer requests and approvals), `public.employee_deactivation_audit_log`, `public.employee_deactivation_requests`, and direct `plantilla` record timestamps (`updated_at`, `updated_by`, `last_mika_synced_at`, `last_mika_synced_by`, `date_deployed`). Formatted as a streamlined single-line human-readable activity feed (`[Icon] {User} {action} {timestamp}`, e.g., `[CalendarClock] Litong, Ohm update the status to On Leave ... Nov 10, 2026, 1:13 PM`), with operational notes (e.g. leave reason, EDR) subtly preserved below, automatically deduplicated within 60-second operational windows, and rendered with semantic icons and color-coded badges (`CalendarClock` amber for On Leave, `UserCheck` emerald for Active, `Share2` purple for Floating, `Calendar` blue for Schedule, `ArrowRightLeft` indigo for Transfers, `ShieldCheck` teal for HRCO, `RefreshCw` cyan for MIKA, `UserMinus` rose for Deactivations, `Trash2` red for Deletion, and `Store` blue for Deployments).

---

## 9. SLA & Status Transition Rules

Operational bottlenecks in personnel movement directly impact retail performance. The system enforces strict timers and escalates breaches:

```
[Transfer Requested] ──(48 Hours SLA Clock)──> [SLA Breached Alert] ──(72 Hours)──> [SuperAdmin Escalated Alert]
```

### A. Personnel Movement Approval SLA:
* **Calculation Baseline**: `movement_requested_at` timestamp.
* **Response Window**: **48 Hours** (2 days).
* **Behavior**: If a transfer or promotion remains in `Pending Approval` beyond 48 hours without action:
  - **SLA Tier 1 Breach**: The status text shifts to red inside the table queue. A warning alert icon displays inside the detail drawer. The dashboard's "SLA Breaches" metric card increments by 1.
  - **SLA Tier 2 Breach (72 Hours)**: An automated notification is sent directly to the `Super Admin` to override or expedite approval.

### B. Store Staffing Vacancy SLA:
* **Calculation Baseline**: The date a store's active budgeted staff falls below the budgeted plantilla target (`STR-V-01` date of vacancy opening).
* **Response Window**: **7 Days** (168 hours).
* **Behavior**: In **Store-Centric View**, if a contracted budgeted slot remains vacant for more than 7 days, the store row displays a red vacancy alarm badge: `[Under-staffed SLA Breach]`. This flags the account to recruiters to prioritize filling the vacancy.

---

## 10. Proposed Database RPC Contracts

To integrate seamlessly with the Supabase thin-client presentation model, we recommend the following backend RPC signatures:

### A. List Employees Contract
```sql
CREATE OR REPLACE FUNCTION public.list_web_plantilla_employees(
  p_search          text    DEFAULT NULL, -- searches employee number or name
  p_account_id      uuid    DEFAULT NULL,
  p_group_id        uuid    DEFAULT NULL,
  p_store_id        uuid    DEFAULT NULL,
  p_employment_status text DEFAULT NULL, -- 'active', 'suspended', 'pending_separation', 'inactive'
  p_deployment      text    DEFAULT NULL, -- 'budgeted', 'additional'
  p_active_state    text    DEFAULT NULL,
  p_limit           integer DEFAULT 50,
  p_offset          integer DEFAULT 0,
  p_sort_by         text    DEFAULT 'employee_name',
  p_sort_dir        text    DEFAULT 'asc'
)
RETURNS TABLE (
  id                    uuid,
  employee_no           text,
  first_name            text,
  last_name             text,
  position_title        text,
  account_name          text,
  primary_store_name    text,
  assignment_type       text, -- 'Stationary', 'Roving'
  covered_stores_count  integer,
  plantilla_type        text, -- 'Budgeted', 'AH'
  plantilla_status      text,
  date_deployed         date,
  tenure_days           integer,
  base_rate_masked      text,
  sla_breached          boolean,
  row_capabilities      jsonb, -- dynamic actions authorized for caller
  total_count           bigint
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

Supported employee sort fields are `employee_name`, `employee_no`, `account_name`, `primary_store_name`, `position_title`, `plantilla_type`, `plantilla_status`, `date_deployed`, and `created_at`.

### B. List Stores Contract
```sql
CREATE OR REPLACE FUNCTION public.list_web_plantilla_store_staffing(
  p_search        text    DEFAULT NULL, -- searches store code or name
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_risk_filter   text    DEFAULT NULL, -- 'under-staffed', 'fully-staffed', 'over-staffed'
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'store_name',
  p_sort_dir      text    DEFAULT 'asc'
)
RETURNS TABLE (
  store_id                uuid,
  store_code              text,
  store_name              text,
  account_name            text,
  region                  text,
  required_headcount      integer,
  active_headcount        integer,
  vacancy_count           integer,
  pipeline_count          integer,
  staffing_gap            integer,
  staffing_risk           text,
  sla_badge               text,
  vacancy_sla_breached    boolean,
  row_capabilities        jsonb,
  total_count             bigint
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

Supported store staffing sort fields are `store_name`, `store_code`, `account_name`, `region`, `required_headcount`, `active_headcount`, `vacancy_count`, `pipeline_count`, `staffing_gap`, `staffing_risk`, and `sla_badge`.

### C. Summary Count Metrics Contract
```sql
CREATE OR REPLACE FUNCTION public.get_web_plantilla_summary(
  p_search        text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL
)
RETURNS TABLE (
  total_active_roster     bigint, -- count of active employees
  total_budgeted_slots    bigint, -- count of budgeted employees
  total_additional_slots  bigint, -- count of active AH employees
  understaffed_stores     bigint, -- count of stores where active < budgeted target
  sla_breaches_count      bigint  -- count of active movement or vacancy SLA breaches
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

### D. Detail Drawer Contract
```sql
CREATE OR REPLACE FUNCTION public.get_web_plantilla_detail(
  p_employee_id uuid
)
RETURNS TABLE (
  id                    uuid,
  employee_no           text,
  first_name            text,
  last_name             text,
  position_title        text,
  account_name          text,
  primary_store_name    text,
  assignment_type       text,
  covered_stores        jsonb, -- array of covered stores with allocation %
  plantilla_type        text,
  plantilla_status      text,
  date_deployed         date,
  tenure_description    text, -- formatted text "1 Year, 4 Months"
  base_rate_masked      text, -- dynamic masking based on caller role
  contact_number        text, -- masked/unmasked contact number
  email_address         text, -- masked/unmasked email address
  residential_address   text, -- masked/unmasked address
  government_ids        jsonb, -- SSS, PagIBIG, PhilHealth, TIN (masked/unmasked)
  clearance_status      text, -- 'Complete', 'Pending', 'Incomplete'
  clearance_checklist   jsonb, -- interactive checklist states
  clearance_documents   jsonb, -- array of uploaded clearance files
  sla_elapsed_hours     integer,
  sla_breached          boolean,
  active_movement_req   jsonb, -- active transfer/movement metadata if any
  audit_timeline        jsonb, -- historical logs array
  row_capabilities      jsonb  -- capability keys
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

---

## 11. Shared Component Reuse Mapping

To achieve perfect visual alignment with the design systems defined in `web_ui_system_state.md`, the Plantilla Web module consumes the core shared component library:

```
[Plantilla Main Dashboard]
 ├── AdminPageHeader ───────────────── Title: "Plantilla Directory"
 │                                     Subtitle: "Manage active personnel, audit store capacities, and govern movements."
 │                                     Primary Action: Scoped "Request Additional Headcount" (OM / Admin only)
 │                                     Top Action Slot: "+ Add Account" (Head Admin / Super Admin only)
 ├── Account Selection Grid ────────── Account Cards with MFR, Headcount, Pipeline, Fill Rate
 │    └── Three-Dot Context Menu (⋮) ─ Actions: [ Absorb Employees ] | [ Archive Account ]
 ├── MetricCard (Grid) ─────────────── Renders: 1. Active Roster | 2. Budgeted Slots
 │                                              3. AH (Temp) Slots | 4. Under-Staffed Stores
 ├── AdminFilterBar ────────────────── Search: "Search by employee, store, or VCode..."
 │                                     Segmented Switch: [ Employee View ] vs. [ Store View ]
 │                                     Select Dropdowns: Account, Position, Plantilla Type, SLA Status
 ├── Compact Table ─────────────────── Rendered grid of personnel or store records.
 │    └── DataState ────────────────── Handles Loading skeletons, Empty records, Access Denied shields,
 │                                     and Connection alerts with retry callbacks
 └─ Detail Drawer
      ├── DetailDrawer ────────────── Width token: drawer-width-lg (640px)
      │                                Handles Escape keypresses, backdrop dismissals, and background scroll locking
      ├── StatusBadge ──────────────── Maps statuses ('Active' -> success, 'Pending Separation' -> danger)
      └── CapabilityActionBar ──────── Renders context action options:
                                                - [ Transfer Personnel ] (Encoder / HeadAdmin / SuperAdmin)
                                                - [ Absorb Employees ] (Encoder -> Pending Approval; HA/SA -> Direct DB Update)
                                                - [ Initiate Separation ] (OM / HRCO / HR / Admin)
                                                - [ Approve Clearance ] (HR Personnel / Admin)
                                                - [ Adjust Roving Schedule ] (HRCO / OM / Admin)
```

---

## 11.1 Account Lifecycle Governance & Operations (ohm#p4a8x2m9)

### 1. Add Account Feature
- **UI Placement:** Upper right corner of the Plantilla Directory header (`AdminPageHeader` action slot).
- **Access Control:** Rendered conditionally via `isHeadOrSuperAdmin(currentUser.roleKey) || isHeadOrSuperAdmin(currentUser.roleName)`. Visible strictly to Head Admin (`HA`, Level 90) and Super Admin (`SA`, Level 100). Hidden for Encoders and lower operational roles.
- **Form Architecture (`AddAccountModal.tsx`):**
  - Inputs: `account_name` (required), `account_code` (optional uppercase identifier), and `group_id` (required).
  - Data Source: Dynamic group list fetched via `useGroupsQuery()` from Supabase `public.groups`. Zero hardcoding.
  - Execution: Directly creates active account in `public.accounts` (`is_active = true, status = 'Active'`) and invalidates TanStack Query cache keys (`['plantilla', 'allowed-accounts']`, `['plantilla', 'account-metrics']`).

### 2. Archive Account Feature
- **UI Placement:** Three-dot context menu (`⋮` / `MoreVertical`) placed in the top right of each billing account card in the Plantilla Directory grid.
- **Smart Active Employee Intercept (`ArchiveAccountModal.tsx`):**
  - Checks `account.actual > 0`.
  - If active employees exist: Renders an intercepting dialog: *"There are active employees in this account. Would you like to absorb them into another account first?"*
    - Primary Button: "Absorb Employees First" -> routes to the Absorption Workflow modal for this account.
    - Secondary Button: "Proceed to Archive" -> progresses directly to the remarks form.
  - If `account.actual === 0`: Skips intercept dialog directly to the remarks form.
- **Remarks Validation:** Requires a justification of **at least 30 characters** (`remarks.trim().length >= 30`). Live validation counter (`X / 30 min characters`) prevents submission until the character threshold is satisfied.
- **Governance & Approval Routing:** Submitting does NOT delete or hide the account immediately. It dispatches an approval notification to the `SA` role in `public.notifications` and records an audit log (`ARCHIVE_ACCOUNT_REQUESTED`). While pending, the account remains fully visible and active in all dashboard capacity computations.

### 3. Absorption Workflow (Employee Transfer)
- **UI Placement:**
  - "Absorb Employees" action inside each account card's three-dot menu (`⋮`).
  - "Absorb Employees" header action button inside the detailed Account View (`AdminPageHeader` action slot).
- **Transfer Interface (`AbsorbEmployeesModal.tsx`):**
  - Destination Account Dropdown: Displays authorized accounts excluding the source account.
  - Active Employee Selection: Renders active personnel roster with search filtering and a "Select All" batch toggle.
  - Live count pill displays selected records.
- **Role-Based Execution:**
  - **Encoder (Level 30):** Submits batch transfer request to `public.employee_transfers` with `status = 'Pending'` and creates an admin notification in `public.notifications`. Active employee account assignments in the database remain unchanged pending review.
  - **HA / SA (Levels 90 / 100):** Executes immediate direct database updates in Supabase on `public.plantilla` (`account`, `account_id`) and `public.hr_emploc` (`account`), records approved audit rows in `public.employee_transfers`, and invalidates queries (`['plantilla']`, `['team-directory']`, `['plantilla', 'employees-all']`, `['plantilla', 'account-metrics']`) to refresh roster data and metrics immediately.

---

---

> [!NOTE]
> **Historical Implementation Phases & Changelogs Archive:**
> Phased delivery checklists and historical prompt changelogs (Sections 12+) have been archived to [`docs/state/archive/plantilla_web_state_historical.md`](archive/plantilla_web_state_historical.md) to keep this live specification token-optimized.
