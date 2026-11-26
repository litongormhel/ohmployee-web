<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-Plantilla. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/01_plantilla.md
source_commit: f4b7a3b 2026-11-26T10:11:00+08:00
source_sha256: b18e3e80d66727d7b847e30d9bda2ddc95f854194e8fa3d00ecf8608acc4e941
synced_at: 2026-11-26T02:11:10.465Z
-->
# Plantilla Module Architecture & Headcount Governance

- **Status:** ACCEPTED & LOCKED
- **Scope:** Store Identity (1 Store = 1 VCODE), Plantilla Baseline Import, Headcount Fractions ($1/N$), Dual Views, Six Status Sub-Tabs, DOLE Floating, and On-Leave Reliever SLA.

---

## Part 1: Store Identity, Plantilla Baseline Import & Headcount Governance (ADR-002)

This Architecture Decision Record (ADR-002) establishes the definitive system of record rules for Store Identity, Plantilla Import validation, Headcount computation, and Rollback governance across OHMployee and OHMployee Web. It resolves historical discrepancies between legacy slot assumptions and operational realities by locking in ten core invariants.

---

## The 10 Architectural Invariants

### Invariant 1 — Plantilla as Upstream Source of Truth & 1:1 Headcount to Physical Slot Identity
Plantilla Baseline Import is the primary upstream origin for stores, slots, and initial employee allocations in the system.
- **1:1 Slot-to-Headcount Parity**: Regardless of whether a store/position originated from Plantilla Baseline Import or Requisition / Headcount Request, authorized headcount maps 1:1 to physical rows in `public.plantilla_slots`. Every active deployed employee must hold a corresponding occupied slot (`slot_status = 'occupied'`, `current_occupant_plantilla_id = plantilla.id`).
- Batches and rows may be uploaded without an employee (creating vacant baseline slots on fresh VCODEs).
- Downstream imports (`Vacancy Import` and `HR Emploc Import`) must validate that any referenced `VCODE` already exists in Plantilla (`stores` / `plantilla_slots`) before accepting records. Uploading downstream records for unseeded VCODEs is blocked.

### Invariant 2 — Permanent 1 Store Name = 1 VCODE Identity
Within an Account, 1 `STORE_NAME` maps 1:1 to 1 `VCODE`.
- Even if 10 employees are assigned to that store, all employees and slots share the store's single `VCODE` with distinct, sequential `slot_ordinal`s (1..N).
- Same `STORE_NAME` with a different `VCODE` within the Account is hard-blocked.
- Same `VCODE` with a different `STORE_NAME` within the Account is hard-blocked.
- **Headcount Expansion on Existing Stores Contract**: An approved Headcount Request for an already existing store/VCode **MUST NEVER route to New VCode / New Store Creation**. It must strictly execute in-place Quota Revision via `revise_vcode_headcount_quota` (incrementing `hc_required` on the store) and provision additional physical `plantilla_slots` with sequential `slot_ordinal`s (e.g., ordinal 2, 3) under that exact same VCode. Generating duplicate VCodes or spawning new stores for existing store locations is strictly prohibited.

### Invariant 3 — `CGCODE` (Coverage Group) Coexistence with Permanent `VCODE` & Universal Roving Binding
Every store permanently retains its individual `VCODE` even when grouped into a roving Coverage Group (`CGCODE`).
- A `CGCODE` is a roving group overlay across multiple stores (e.g., 5 stores grouped under 1 unique `CGCODE`).
- The underlying `VCODE`s of those 5 stores are NEVER deleted, mutated, or removed, because any store can revert to `stationary` deployment later on.
- **Mandatory CGCode for All Roving Personnel**: All roving personnel deployed across $N \ge 2$ stores are strictly bound to a `CGCODE`. Roving personnel must never be deployed or imported as independent/unassigned roving without a parent Coverage Group overlay.
- **CGCode Strict Monotonicity & Dissolution Retirement Invariant (Permanent Non-Recycling Rule)**: Every minted Coverage Group Code (`CGCODE`, format `CG-<AccountInitial><GroupCode>-NNNN`) is permanently unique and monotonic for all time within its account.
  - **Dissolution Retirement**: When a Coverage Group is dissolved via `dissolve_coverage_group`, merged into another group, or archived, its `CGCODE` is permanently retired (`coverage_groups.archived_at = now()`).
  - **Zero-Recycling / Re-clustering Rule**: If the member stores, personnel, or roving cluster footprint are subsequently brought back together into a Coverage Group (re-clustered, reformed, or re-uploaded), the system is **STRICTLY PROHIBITED** from reusing, recycling, or resurrecting the old `CGCODE`.
  - A fresh, strictly sequential, monotonically incremental `CGCODE` (e.g., `CG-FG1-0007` $\rightarrow$ `CG-FG1-0008`) MUST ALWAYS be minted.
  - **Audit & Separation Integrity**: Permanent monotonicity preserves historical audit integrity, ensures employee movement and separation logs unambiguously reflect exact group tenure, prevents foreign key or reporting ambiguity in CENCOM / analytics, and eliminates cache collision across Web and Mobile.
  - **Database Level Guarantee**: `fn_generate_cgcode_for_account` probes against ALL historical coverage groups for that account (both active and archived, omitting any `archived_at IS NULL` bypass), and `public.coverage_groups` enforces permanent account-level uniqueness across all time (`account_id, coverage_code`).

### Invariant 4 — Auto-Computed `EMPLOYMENT_TYPE`, Fractional `REQUIRED_HC` ($1/N$) & Universal Automatic Coverage Group (`CGCODE`) Provisioning
`EMPLOYMENT_TYPE` and `REQUIRED_HC` are removed from required Excel spreadsheet inputs and are computed directly by the database:
- **Vacant Row** (`EMPLOYEE_NO` blank): Defaults to `stationary` employment type and `1.00` required headcount.
- **Assigned Employee** (`EMPLOYEE_NO` present): Distinct stores ($N$) assigned to that `EMPLOYEE_NO` across the batch and active allocations are evaluated:
  - If $N = 1 \implies$ `stationary` (`1.00` HC).
  - If $N > 1 \implies$ `roving`, and each assigned store is allocated fractional headcount $1 / N$ (e.g., 5 stores $\implies 0.20$ HC per store).
  - Standard roving employee assignments ($N \ge 2$) evaluate to `validation_status = 'valid'` with fractional HC $1/N$ and a neutral advisory info note (`Roving · N stores · X.XX HC · Auto-assigned Coverage Group`). Valid roving assignments are NOT demoted to `flagged`.
  - Batch-blocking errors (e.g. `multiple_vcodes_per_store`) are promoted to `validation_status = 'blocked'`. Purely informational notes remain `valid`. Submission no longer produces batches in `pending_review` status. Batches without blocking errors land directly in `pending_approval`.
  - Pre-upload dry-run validation RPC (`validate_plantilla_baseline_import`) acts as the single source of truth for file validation. If any row is blocked (`blocked_rows > 0`), the entire file is blocked from submission at Upload & Preview. Server-side `submit_plantilla_baseline_import` re-validates the payload and hard-refuses (`RAISE EXCEPTION`) if `blocked_rows > 0`.
  - **Universal Automatic Coverage Group (`CGCODE`) Provisioning Invariant**: Regardless of origin (whether initiated via Headcount Request / Coverage Request, Plantilla Baseline Import, HR Emploc Onboarding Deployment, or Store Movement/Transfer), whenever an employee or requisition is assigned across $N \ge 2$ distinct stores (Roving deployment), the system MUST automatically provision or resolve a Coverage Group (`CGCODE`) overlay for that store footprint. Roving employees must never exist as independent or unattached roving without an assigned `CGCODE`. At import approval commit time (`approve_plantilla_import_batch`), any roving employee with $N \ge 2$ stores automatically creates a `coverage_groups` record (if one for that exact store footprint does not already exist) with an auto-generated `coverage_code`, inserts member stores into `coverage_group_stores` (with the primary store designated as anchor and fractional HC share $1/N$), provisions occupied coverage slots, and links `plantilla.coverage_group_id` atomically.

### Invariant 5 — Multi-Batch Existing `VCODE` Rule & Slot Provisioning
When uploading Plantilla batches, if a row's `VCODE` already exists in the database:
- **No Employee** (`EMPLOYEE_NO` is null / blank): The row is marked as **`skipped`** (`validation_status = 'skipped'`, non-blocking, informational message: `"Existing VCODE skipped (vacant row — only fresh VCODEs create new vacant slots)"`). It is ignored during approval commit.
- **Assigned Employee** (`EMPLOYEE_NO` is populated): The row is **allowed**. During commit, it claims and occupies an existing open vacant slot at that `VCODE` or creates an occupied slot ordinal under that store's existing `VCODE` (`slot_status = 'occupied'`, `current_occupant_plantilla_id = v_plantilla_id`). If no open slot exists, an occupied slot row MUST be auto-provisioned to guarantee 1:1 parity between deployed personnel and `plantilla_slots`.

### Invariant 6 — `MOTHER_ACCOUNT` Penalty Inheritance
- `MOTHER_ACCOUNT` is a mandatory column in Plantilla Import (positioned immediately following `ACCOUNT_NAME`).
- `WITH_PENALTY` is removed from required Excel spreadsheet input columns and is derived automatically in the database from the `MOTHER_ACCOUNT` configuration. If a mother account record is newly referenced or unconfigured, safe fallback defaults to `false`.

### Invariant 7 — Strict `MIDDLE_NAME` Validation
Whenever `EMPLOYEE_NO` is populated:
- `MIDDLE_NAME` is mandatory.
- Blank, null, or single-character initials (e.g., `"S"` or `"S."`, alpha length $< 2$) are hard-blocked.
- Only full middle names ($\ge 2$ alpha characters) or explicit `"NA"` / `"N/A"` (case-insensitive) are accepted.
- If `EMPLOYEE_NO` is blank, all employee fields (`LAST_NAME`, `FIRST_NAME`, `MIDDLE_NAME`, and `DATE_HIRED`) must also be blank. If any employee detail is provided without `EMPLOYEE_NO`, the row is hard-blocked with `"EMPLOYEE_NO is required when employee details are provided"`.

### Invariant 8 — Schedule Days, Flexible Schedule Time & Dayoff Audit Model
- `SCHEDULE` is replaced by `SCHEDULE_DAYS` (multi-select MON–SUN in Web; preset dropdown + custom comma-separated days in Excel).
- `SCHEDULE_TIME` is added (`text`, optional in Excel, editable in Web by Ops per store allocation for store visit audits). Supports fixed shift windows (e.g., `08:00 AM - 05:00 PM`) and flexible roving visit durations (e.g., `FLEXI (4 HRS)`, `FLEXI (6 HRS)`).
- `DAYOFF` supports multi-select in Web and preset dropdown + custom multi-day values in Excel.

### Invariant 9 — Per-Account `HRCO_EMAIL` Auto-Population & Reactive Backfill
- **On Import**: If `HRCO_EMAIL` is blank in the uploaded spreadsheet, inspect the target Account's assigned HR Coordinator(s):
  - If the Account has **exactly 1 HRCO**, auto-populate that HRCO.
  - If the Account has **0 or $> 1$ HRCOs**, tag the record with `needs_hrco = true` (`"NEEDS HRCO"` tag).
- **Reactive Backfill**: When an HRCO is subsequently assigned or updated on an Account, the database automatically backfills all `plantilla` records under that Account having `needs_hrco = true` to the newly assigned HRCO and clears `needs_hrco = false`.

### Invariant 10 — Rollback Governance (72h Window + Zero-Edit Immutability Lock + History Audit)
- **72-Hour Request Window**: The uploader (Data Team) can request batch rollback within 72 hours of approval. Head Admin (HA) and Super Admin (SA) can approve or reject the rollback request.
- **SA Window Override**: Super Admin can override an expired ($> 72\text{h}$) window **ONLY IF** zero records in the batch were edited after import approval.
- **Strict Zero-Edit Immutability Lock**: If **any** record in the batch was edited in Plantilla or allocations after import approval (e.g., Ops changed `dayoff`, `schedule_days`, `schedule_time`, rate, position, status, etc., causing `updated_at > approved_at`), rollback is **HARD BLOCKED** for all roles (even SA cannot override). The system returns an explicit error naming the exact employee number, employee name, and modification timestamp.
- **Import History Visibility**: Import History must clearly surface Batch # (e.g. `#703cdbc4`), Stores/HC count (e.g. `11/10`), and Approved/Rejected By actor details along with rollback state indicators.
- **Rollback Records Must Not Be Treated as Archive Data (Re-Upload Allowed)**: When an import batch is rolled back, the created plantilla rows are soft-archived for lineage and reversibility. However, these rollback records MUST NOT be treated as genuine operational archive/separated data. Re-uploading the original file (or an updated version) of a rolled-back batch is **ALLOWED** and must not trigger `inactive_or_archived_existing_record`.
  - **Re-Upload Safety Gate**: Re-upload is permitted **UNLESS** an employee in the file already possesses a separate, genuine operational inactive/archived record (`status IN ('Inactive', 'Rejected Deactivation')` from actual separation, resignation, AWOL, termination, or non-rollback archive) that pre-dated the rollback ("unless may dating naka archive na data na na dagdag"). Legitimate separated personnel remain strictly blocked from re-import.
  - **New Batch Commitment**: Upon approval of the re-uploaded batch, the system creates a fresh active plantilla record under the new batch (`status = 'Active'`), preserving the rolled-back record's historical audit lineage without mutating or resurrecting the old batch snapshot. Archival stores under the same account and VCODE are cleanly reactivated.

---

## Addendum: Multi-Row Validation, Coalescing & Schedule Normalization (Rules #16 – #19)

### Invariant 16 — Multi-Row & Bi-Directional Identity Invariant
Employee identity mapping is strictly **bi-directional**:
- **Forward Invariant (1 EMPLOYEE_NO = 1 Person):** For multi-row `EMPLOYEE_NO` (roving) within an import batch and against existing DB master records (`plantilla` / `employees`), normalized `LAST_NAME`, `FIRST_NAME`, `MIDDLE_NAME`, and `DATE_HIRED` must strictly match. Any mismatch is **HARD BLOCKED**.
- **Reverse Invariant (1 Person = 1 EMPLOYEE_NO):** A human identity defined by normalized `(LAST_NAME, FIRST_NAME, MIDDLE_NAME)` CANNOT be assigned multiple distinct `EMPLOYEE_NO`s within the same batch or against existing DB master records. Any duplicate person assigned a differing employee number is **HARD BLOCKED** (e.g. preventing typo errors such as assigning `2060-001` on row 1 and `2060-005` on row 2 to the same individual). Roving employees must share the exact same `EMPLOYEE_NO` across all assigned stores.

### Invariant 17 — Employee-Level Coalescing & Conflict Flag
Employee-level fields (`POSITION`, `RATE`, `CIVIL_STATUS`, `DATE_OF_BIRTH`, `CONTACT_NO`, `ADDRESS`, `DAYOFF`) silently coalesce across blank rows sharing the same `EMPLOYEE_NO`. Conflicting non-blank values trigger a non-blocking **WARNING FLAG** and apply **Last-Row-Wins** persistence upon batch commit.

### Invariant 18 — Minimum Age Enforcement (18+)
If `DATE_OF_BIRTH` is provided (post-coalescing), the employee must be at least **18 years old** as of `DATE_HIRED`. Underage records are **HARD BLOCKED** across all rows associated with that `EMPLOYEE_NO`.

### Invariant 19 — Canonical Schedule Day Expansion & Rest Day Carving
Range formats (e.g., `MON-SAT`, wrap-arounds like `SAT-TUE`, hybrid lists) in `SCHEDULE_DAYS` and `DAYOFF` are automatically expanded into discrete canonical day tokens (`MON,TUE,WED,THU,FRI,SAT,SUN`) strictly ordered `MON` to `SUN`. Overlapping rest days are carved out from duty days to maintain mutually exclusive pill states in the Web UI (`Edit Schedule & Work Terms`).

---

## Plantilla

### Rule 5 — Ordering Contract

**Module scope:** Module-specific — each module that needs a stable sort order must enforce it in a DB view, not client-side.

**✅ Plantilla is COMPLIANT (`ohm#6w3p9x4k`, 2026-08-03).** `vw_plantilla_inactive` — security_invoker wrapper over `v_plantilla_safe` (`status <> 'Active' AND source_headcount_request_id IS NULL`) with in-DB `ORDER BY date_of_separation DESC NULLS LAST, employee_name ASC`. `plantilla_screen.dart`'s `_fetchInactiveTabEmployees` (store-scoped) and `_paginateAccountQuery`'s `inactive: true` branch (account-scoped) both query this view and no longer apply a client-side `.order()` — the view's in-DB `ORDER BY` is the sole ordering source. Live-verified against staging, including the NULL `date_of_separation` edge case. Full detail: `docs/state/plantilla_state.md`.

> **Note on source discrepancy:** the merge-source Coverage ADR text this document was assembled from described this rule's status as "DRIFTED, not yet fixed." That was accurate before `ohm#6w3p9x4k` shipped (2026-08-03, same day) but is stale now — both `docs/architecture/ADR-001-system-slot-and-derived-invariants.md` (pre-merge) and `docs/state/plantilla_state.md` independently confirm compliance. This document reflects the current, verified state rather than the stale draft text, per the instruction to preserve substance rather than force a fit — flagged here per the "flag deviations from the approved structure" instruction.

**⚠️ Known gap — Dashboard and CENCOM remain NON-COMPLIANT.** Both currently sort client-side in Dart rather than relying on in-DB `ORDER BY`. Confirmed, documented drift — not yet fixed. Tracked in "Known Gaps" below. (HR Emploc closed `ohm#h4t8x1qy`, 2026-08-04 — see Known Gaps.)

### HRCO Employee-Level Scope Isolation (`ohm#k8d2x7qf` — 2026-07-07)

**Status: ACCEPTED.** Approved by Ohm 2026-07-07. Supersedes and closes `.ai/architecture_locks/adr_001_hrco_scope_draft.md` (deleted — content merged here).

**Problem.** `plantilla_read_scoped` scoped SELECT by account only, via `get_my_allowed_accounts()`. On accounts with multiple HRCOs, every HRCO could see every employee in the account regardless of who actually handles them — a scope leak, not a query bug.

**Decision.** New employee-level assignment table, `plantilla_hrco_assignments`, modeled on `employee_store_allocations`' active/history pattern. Exactly one active row per `plantilla_id`, enforced by a partial unique index (data-layer, not app-layer). `plantilla_read_scoped` gains a role-conditional branch: Super Admin / Head Admin unchanged (account-wide); non-HRCO Ops/Data roles unchanged (account-wide); HRCO role narrowed to rows with an active assignment where `hrco_user_id = auth.uid()`.

**Core Rules (binding):**

1. Exactly one **active** HRCO assignment may exist per Plantilla employee at any time — enforced by partial unique index `(plantilla_id) WHERE is_active`.
2. HRCO role visibility on Plantilla SELECT is scoped to active-assignment rows only. Role membership alone is no longer sufficient for HRCO read access.
3. Super Admin and Head Admin retain full account-wide Plantilla visibility, unaffected.
4. Reassignment is deactivate-old + insert-new in a single transaction. No hard delete, no update-in-place of `hrco_user_id` on an existing row — full audit trail preserved (mirrors ESA supersede pattern).
5. An employee may have **zero** active HRCO assignment — blank/unassigned is a valid, accepted state, never an error. Unassigned employees are visible to Data Team roles via the "Needs HRCO" tab, never to HRCO role.
6. Assignment/reassignment is Encoder / Head Admin / Super Admin only (`fn_can_assign_hrco()`). HRCO cannot self-assign or reassign.
7. `HRCO_EMAIL` CSV import validation and the Assign/Reassign search UI use the same underlying validation rule (`fn_is_valid_hrco_for_account`) — one code path, no divergent validation logic between import and manual assign.
8. This addition affects **Plantilla only**. Vacancy and HR Emploc read paths are explicitly out of scope; `vacancies.hrco_user_id` and `hr_emploc.hrco_user_id_snapshot`/`hrco_name` are pre-existing, unrelated point-in-time attribution columns and are not touched.
9. "Data Team" for the "Needs HRCO" tab gate means role_name IN (`Encoder`, `Head Admin`, `Super Admin`) — narrower than `i_have_full_access()` (SA+HA only). New helper: `i_am_data_team()`.

**Backfill Decision.** Option A (clean start). All existing Plantilla employees begin unassigned on migration day. Data Team assigns via the "Needs HRCO" tab over time. No backfill migration logic. (A one-time CSV backfill reusing the `HRCO_EMAIL` import path remains available as a future follow-up if Ohm supplies a mapping file, but is not part of this migration.)

Full schema/RLS/RPC/Flutter design: `docs/architecture/hrco_scope_isolation_design_draft.md`.

### HRCO Global Visibility Override (`ohm#7gk2d9xq` — 2026-07-07)

**Status: ACCEPTED.** Implemented in `supabase/migrations/20260707120000_hrco_global_visibility.sql`. Extends, does not replace, HRCO Employee-Level Scope Isolation above.

**Problem.** Employee-level assignment (`plantilla_hrco_assignments`) is correct for accounts with multiple HRCOs but over-narrows visibility for accounts where a single HRCO (or an HR-head-style HRCO) legitimately needs to see every employee in their allowed accounts without per-employee assignment overhead.

**Decision.** New per-user override column `users_profile.hrco_global_visibility boolean NOT NULL DEFAULT false`, HRCO-role-only in effect. `plantilla_read_scoped`'s HRCO branch gains an additive `OR` condition — bypass the `plantilla_hrco_assignments` EXISTS check when the flag is set — but the account boundary (`account = ANY (get_my_allowed_accounts())`) is never bypassed. Every other branch of the policy (full access, non-HRCO scoped, pool-employee) is preserved byte-for-byte.

**Core Rules (binding):**

1. `hrco_global_visibility` has effect only when the profile's role is HRCO (`i_am_hrco_only()`); it is inert for every other role.
2. Global visibility never crosses the account boundary — it is always intersected with `get_my_allowed_accounts()`, same as the assignment-scoped branch it bypasses.
3. Toggling takes effect on the next query — no re-login required (`i_have_hrco_global_visibility()` is a live per-request `STABLE` lookup, not session/JWT-cached).
4. Only Data Team roles (`i_am_data_team()`) or full-access roles (`i_have_full_access()`) may set the flag, via `set_hrco_global_visibility(profile_id, enabled)`. HRCO cannot self-elevate.
5. `set_hrco_global_visibility` rejects any target profile whose role is not HRCO (`ERRCODE 22023`) and rejects unknown profile ids (`ERRCODE P0002`).
6. Every toggle is audit-logged (`audit_logs`, action `UPDATE_USER_ROLE`, old/new value captured) — no silent flips.
7. This is a bypass branch, not a replacement: `plantilla_hrco_assignments` and its active/history semantics are untouched and remain the default (`false`) behavior for every HRCO.

**Known Limitation (inherited, not expanded).** `plantilla_read_scoped` still does not gate on `is_archived` / `inactive_visible_until` independent of `deactivated_visible_until` — pre-existing gap, tracked separately, not touched by this addition.

**Non-Goals.** Does not introduce role-based visibility variants beyond HRCO. Does not add account-level defaults or bulk-enable tooling. Does not change Vacancy or HR Emploc read paths.

### Dual Views & Seven Status Sub-Tabs Architecture (`ohm#plantilla-subtabs-arch` — 2026-11-23, updated 2026-11-25)

**Status: ACCEPTED.** Codifies the standard interface and lifecycle organization for Plantilla across Web and Mobile.

The Plantilla module operates under **Dual Views** driven by a segmented view toggle:
1. **Store View (`Store Capacity Table`)**: Audits contracted store plantilla headcount compliance. Displays stores with active personnel or vacancies, computing fractional capacity for roving personnel ($1/N$). Stores without active personnel or vacancies are filtered out.
2. **Employee View (Directory Roster)**: Organizes workforce members across **Seven Status Sub-Tabs**:
   - **Tab 1: Active** — Official deployed personnel with `status = 'Active'`.
   - **Tab 2: On-Leave** — Personnel on approved leave, tracking Expected Date of Return (EDR) and reliever coverage. (Counted as part of company Actual Headcount: `Actual Headcount = Active + On-Leave`, recognizing that employees on authorized leave remain officially active employees and are not resigned, separated, or floating).
   - **Tab 3: Vacancy** — Strictly open, unfilled required store slots awaiting candidates (`Vacancy - Open` or pending closure). Slots with active onboarding candidates are routed to Tab 4 (Pipeline) to prevent duplicate counting.
   - **Tab 4: Pipeline** — Candidates undergoing onboarding and compliance processing in `hr_emploc` (`Confirmed Onboard`, `Pending Emploc`) prior to crossing the Plantilla Entry Gate, strictly preventing premature counting in Active Plantilla (Anti-Ghost Hire Contract).
   - **Tab 5: Floating** — Active personnel temporarily unassigned, subject to DOLE Article 301 monitoring.
   - **Tab 6: Deactivation** — Action queue for pending deactivation/separation approval requests.
   - **Tab 7: Inactive** — Persistent historical roster of separated personnel (`Resigned`, `AWOL`, `Terminated`, `Deactivated`), ordered via `vw_plantilla_inactive`.

**Universal View Modes**: Both Table and Responsive Cards views are universally supported across all 7 tabs.

### Floating Employee Governance & DOLE Article 301 Statutory Ceiling (`ohm#floating-dole-governance` — 2026-11-23)

**Status: ACCEPTED.** Enforces statutory compliance and slot integrity for unassigned personnel.

1. **DOLE Article 301 Compliance Monitoring**: Under Philippine Labor Code (Article 301), floating (temporary layoff) duration must not exceed **180 calendar days**. Every floating record tracks days elapsed since the effective floating date with reactive status badges:
   - `< 30d`: Fresh
   - `30–60d`: Active aging
   - `60–120d`: Elevated risk
   - `> 120d`: Critical risk
   - `≥ 180d`: DOLE Statutory Breach
2. **Slot-Restricted Store Assignment**: Floating employees can only be assigned to stores with open, unfilled slots (`hc_filled < hc_total` or open vacancy count > 0). Fully occupied stores are strictly hidden in the store assignment interface to prevent over-allocation.
3. **Deployment State Transition**: Assigning a store to a floating employee automatically transitions their status to `'Active'`, binds their `vcode` to the target store, sets deployment type to `'Stationary'`, transitions the target slot to `'occupied'`, and nullifies all prior separation/floating timestamps and remarks.

### On-Leave EDR SLA Governance & Reliever Lifecycle (`ohm#onleave-edr-sla` — 2026-11-23)

**Status: ACCEPTED.** Governs leave monitoring, escalation thresholds, and temporary reliever assignments.

1. **Expected Date of Return (EDR) SLA Escalation**:
   - Every on-leave record tracks `expected_date_of_return`.
   - **Days 1–2 Past EDR (Lapsed)**: Renders amber badge (`Lapsed ({d}d) • HRCO Notified`) and dispatches notification to the assigned HR Coordinator to verify status or execute return.
   - **Day 3+ Past EDR (Breached)**: Renders critical red badge (`Breached ({d}d) • OM Escalated`) and escalates to the Operations Manager as an operational SLA breach.
2. **Moses HQ Reliever Integration**: Temporary store coverage is fulfilled by assigning available pool employees (`availability_status = 'Available'`) via `workforce_assignments` linking `covered_plantilla_id`.
3. **Reliever Auto-Release**: When the regular employee returns to duty (`Return to Active`), the database trigger / mutation automatically terminates the temporary reliever assignment, returning the reliever to available pool status without leaving orphaned assignments.

### Multi-Slot & Multi-Position Granularity Invariant (`ohm#multi-slot-multi-position-granularity` — 2026-11-24)

**Status: ACCEPTED & LOCKED (Option A Standard).** Enforces strict slot-level granularity and independent position resolution for Plantilla Tab 3 (Vacancy):

1. **Strict 1 Row = 1 Slot Granularity (Zero-Collapse Rule):**
   - In Plantilla Tab 3 (Vacancy), every physical slot in a multi-slot store requisition (`required_headcount > 1`) strictly renders as a distinct, independent row (`1 Row = 1 Physical Slot / Tao`).
   - **Anti-Table Jitter Lock (No Merging When Empty)**: Unallocated slots with zero active applicants are NEVER collapsed or merged into a single summary store row. This guarantees:
     - Zero table layout jumping / jitter when candidates are endorsed or dropped.
     - Zero pagination displacement (predictable row distribution across pages).
     - 100% parity between rendered table rows and the total slots counter in the tab badge (`Vacancy X (Y slots)`).
2. **Multi-Position Independence per Store:**
   - When a store requires multiple distinct roles (e.g. 2 Cashiers + 1 Bundler under the same store/VCode), each slot row independently reflects its exact physical `position` (`plantilla_slots.position` or `hr_emploc.position`), rather than collapsing to a single store-level default.
   - Filtering by `Position` strictly targets individual slot capabilities without breaking or omitting multi-position stores.
3. **Sequential Slot Ordinal Identity:**
   - Each rendered slot row displays its distinct sequential slot indicator (`Slot 1`, `Slot 2`, `Slot 3`), enabling direct operational clarity for recruiters, HR coordinators, and store managers.

### Plantilla Account Roster Standard Tabs & Status Isolation Contract

**Status: ACCEPTED & LOCKED.** Codifies the standard tab roster and strict status isolation for Plantilla Account Views across Web and Mobile:

1. **Tab 1: Active** (`status = 'Active'`): Currently deployed, active employees.
2. **Tab 2: Pipeline**: Active candidates undergoing recruitment screening/processing for the account.
3. **Tab 3: Vacancy**: Open physical slot requisitions requiring staffing.
4. **Tab 4: On-Leave** (`status = 'On Leave'` or `separation_status = 'On Leave'`): Employees with authorized temporary leave. Must be **strictly excluded** from the Inactive tab roster.
5. **Tab 5: Floating** (`status = 'Floating'` or `separation_status = 'Floating'`): Employees awaiting reassignment under DOLE 6-month floating status. Must be **strictly excluded** from the Inactive tab roster. Redundant `Floating` badge is hidden in this tab view as the grouping is self-evident.
6. **Tab 6: Inactive**: Historical separated personnel (`Resigned`, `Terminated`, `Endo`, `AWOL`, `Separated`). On-Leave and Floating employees are **strictly prohibited** from rendering in this tab.
7. **Conditional Tab: Needs HRCO**: Renders if and only if the account has zero assigned active HRCOs (`active_assigned_hrco_count = 0`). Accounts with $\ge 1$ assigned active HRCO must never display the `Needs HRCO` badge or tab.
8. **View Mode Toggle Parity**: The `Employee / Store` view switcher must be prominently accessible inline below the account title. In `Store` view, all store cards are displayed and individual employee status tabs are hidden.

### Store View Active Fleet Visibility & Full-Lifecycle Transparency Invariant (`ohm#store-view-all-active-stores` — 2026-11-26)

**Status: ACCEPTED & LOCKED.** Codifies the Store View visibility contract across Web and Mobile:

1. **STORE VIEW = All Active Stores Fleet Invariant (Zero Ghost-Dropping Lock):**
   - In Store View, every active store profile belonging to the Account (`stores.is_active = TRUE AND stores.is_archived = FALSE`) must **permanently be visible**, regardless of its operational, vacancy, or recruitment lifecycle stage.
   - An active store must **NEVER silently disappear or be dropped** from the Store View roster simply because it currently has zero deployed personnel, zero on-leave personnel, or zero open vacancies.
2. **Lifecycle Stage Transparency & Fulfillment Status:**
   - **100% Fulfilled**: `active_deployed >= plantilla_required` and `open_vacancy = 0` (emerald badge).
   - **Understaffed**: `active_deployed < plantilla_required` with open recruitment slots (rose/red badge).
   - **In Pipeline**: Requisition has active candidate(s) undergoing recruitment screening or HR Emploc onboarding compliance (amber/blue badge). Store View must reflect pipeline candidates and must not drop the store.
   - **Zero Quota / Standby**: Active store profile where authorized headcount is zero or all vacancies/slots were formally closed (e.g. approved Vacancy Closure). Renders with `Required: 0 | Actual: 0 | Vacancy: 0`, tagged as `Standby / Zero Quota` (slate badge), retaining the `+ Request HC` action so Operations can request new headcount whenever business resumes.
3. **Archived / Closed Stores Separation:**
   - Stores that are soft-archived or deactivated in the database (`stores.is_archived = TRUE` or `stores.is_active = FALSE`) represent historical, deleted, or dissolved locations.
   - To preserve operational focus and prevent KPI distortion, archived stores are **strictly excluded** from the default Store View table and header KPI totals (`Required`, `Actual`, `Vacancy`).
   - They are accessible exclusively via an explicit **`Archived / Closed Stores`** sub-filter toggle in the Store View toolbar, rendered with an `Archived` tag and with the `+ Request HC` action disabled.

---
