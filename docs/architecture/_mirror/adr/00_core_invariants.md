<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-Core. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/00_core_invariants.md
source_commit: 7ed2e40 2026-11-27T09:40:20+08:00
source_sha256: d47e1ae83ad7b9ef9017b6104ffb5d4afda2c1590239201a86728670f8386cc6
synced_at: 2026-11-27T08:16:10.115Z
-->
# ADR Architecture — Core Cross-Module Invariants

- **Status:** ACCEPTED & BINDING (Single Source of Truth)
- **Scope:** Cross-Module Invariants binding every module in OHMployee and OHMployee Web.

This document contains the core, non-negotiable cross-module invariants that govern slot state, hired-headcount derivation, user management, and denormalized counters across all modules.

> [!IMPORTANT]
> **Hub-and-Spoke Context Loading Rule:**
> When executing a prompt, an AI agent loads:
> 1. `00_core_invariants.md` (this file)
> 2. The specific module file in `docs/architecture/adr/` corresponding to the active task (e.g., `02_vacancy.md` for Vacancy work).
> Do NOT load unrelated module files.

---

## Core Cross-Module Invariants

These core cross-module rules are binding across every module that touches slot state, hired-headcount derivation, or denormalized counters. Documented once here — not duplicated per module. Do not revert any rule without equally explicit re-verification and an update to this document.

> [!NOTE]
> **Module-Specific Rules from Original ADR-001:**
> In the modular Hub-and-Spoke structure, module-specific rules are housed directly in their authoritative module specifications:
> - **Rule 4 — Standardized Open Visibility Filter:** Documented in [`docs/architecture/adr/02_vacancy.md`](02_vacancy.md) § Standardized Open Visibility Filter & Waterfall Priority.
> - **Rule 5 — In-Database Ordering Contract:** Documented in [`docs/architecture/adr/01_plantilla.md`](01_plantilla.md) § Rule 5 — Ordering Contract.

### Rule 1 — Slot Authority

**Module scope:** Plantilla & Vacancy primarily; HR Emploc and Onboarding write paths also participate.

`fn_set_slot_status` is the ONLY path that may change `plantilla_slots.slot_status`. All lifecycle writers are rewired through it: `move_to_plantilla` (reserve/finalize), `_execute_approved_coverage_request` (all 5 slot writes), `tag_backout` (slot release), and HR Emploc Import's submit/approve/reject/rollback flow (open→hr_processing→pipeline transitions). Callers RAISE on a `blocked` result — never silently ignore it. `anon`/`authenticated` hold zero table- or column-level UPDATE privilege on `plantilla_slots` (guard-asserted live).

The 5 SA-gated admin/QA bulk archive functions (`fn_archive_*`, `fn_qa_*`, `fn_rollback_archive_batch`) remain justified direct writers — bulk archival is not a lifecycle transition. (This is the basis for the More Module compliance note below.)

**Backout releases the slot in the same transaction:** `tag_backout` resolves the linked plantilla slot (`hr_emploc.slot_id`, else unambiguous single-`hr_processing`-slot fallback on the vcode) and releases it → open via `fn_set_slot_status(reason 'BACKOUT')`; blocked release is FATAL (22023). Slots occupied by a different employee are never released. Reason codes `BACKOUT`/`HC_READD` are seeded into `slot_reason_codes`; `slot_history.reason_code` is FK-checked. Matrix extension: `closed`/`hc_reduced`→`open` only with reason `HC_READD`/`COVERAGE_STORE_REMOVED`/`COVERAGE_GROUP_DISSOLVED`.

#### Slot-Level Position Independence Contract (Multi-HC Heterogeneous Positions)
For multi-headcount stores, distinct physical slots under the same store `VCODE` are permitted to hold **heterogeneous positions** (e.g., Slot 1 = `Quality Assurance`, Slot 2 = `Stockman`). 
- **Slot Ownership of Position**: Position identity is a property of the physical slot (`plantilla_slots.position_id` / `position_name_snapshot`) and vacancy requisition, not permanently frozen or collapsed at the store level.
- **No Blanket Position Overwrite**: Headcount expansion, amendment approvals, and separation triggers must preserve and stamp the specific requested position onto the newly generated or reopened slot. Approval RPCs (`approve_headcount_amendment_request`, `approve_headcount_request`) and views (`vw_vacancy_list`, `v_plantilla_safe`) are **STRICTLY PROHIBITED** from overwriting all existing store slots with a single parent position.

### Rule 2 — Hired HC Source & Dual Context Delineation

**Module scope:** Cross-module derived read. Source of truth lives in Plantilla; consumed by Vacancy, Dashboard, CENCOM, HR Emploc, and Onboarding.

To permanently eliminate cross-module ambiguity, the system strictly delineates between **Plantilla Active Personnel** and **Vacancy Recruitment Fulfillment**:

1. **Company & Plantilla Headcount (`hired_count`)**:
   - `hired_count` and `active_plantilla_count` derive STRICTLY from `plantilla.status = 'Active'` per VCode, filtered to active deployed occupants only.
   - No other source (applicant status, `hc_filled`, view fallbacks) may contribute to Plantilla deployed headcount.
   - A candidate undergoing onboarding in HR Emploc sits in `plantilla_slots.slot_status = 'hr_processing'`. When an employee is tagged Inactive (Resigned, AWOL, Terminated, Endo, Backout, etc.), `hired_count` drops immediately and the slot/vacancy reopens.
2. **Vacancy Module Queue Classification (`derived_status = 'Hired'`)**:
   - Within the Vacancy module, a store requisition evaluates to **Tab 3 (`Hired`)** the moment its candidates reach **Confirmed Onboard** (`confirmed_onboard_count >= required_headcount`) or are deployed in Active Plantilla (`(active_plantilla_count + confirmed_onboard_count) >= required_headcount`).
   - This signifies that **recruitment demand is 100% fulfilled** (the candidate has passed screening and is in HR Emploc onboarding compliance), ensuring the requisition cleanly vacates the Open Tab and permanently prevents zero-capacity requisitions from lingering in Open (Cross-Module Dual-Existence Prohibition Invariant).

### Rule 3 — Lifecycle Sync

**Module scope:** Cross-module (Applicant / Vacancy / Plantilla / HR Emploc / Onboarding).

An applicant/vacancy status change (hire, backout, separation) must never leave its corresponding `plantilla_slots` row dangling. This is enforced as a backstop, not just a convention: a deferred CONSTRAINT TRIGGER (`trg_applicant_terminal_slot_sync`) on `applicants` fails the transaction at COMMIT if a move into Backout/Withdrawn/Separated leaves its slot unclaimed (`hr_processing`) or still occupied/filled by that applicant's plantilla row.

#### Separation Vacancy Reopen & Attribution Contract
When an active employee separates (Resigned, AWOL, Terminated, Endo) and their slot is reopened via `fn_plantilla_separation_to_vacancy` / `_apply_separation`:
1. **Accurate Vacancy Date Reset**: The resulting vacancy's `vacancy_date` must be **reset to the employee's separation `effective_date`** (or `date_of_separation`), rather than retaining an ancient vacancy date from years or months prior. This ensures SLA and aging metrics accurately reflect the current unfulfilled period.
2. **Deterministic Ownership Attribution**: `vacancies.triggered_by` must record the authenticated actor (or `users_profile.id`) who submitted or executed the separation, guaranteeing unambiguous auditability.

### Rule 4 — Standardized Vacancy Open Visibility Filter
*(Housed in `docs/architecture/adr/02_vacancy.md` § Standardized Open Visibility Filter & Waterfall Priority)*

### Rule 5 — Stable In-Database Ordering Contract
*(Housed in `docs/architecture/adr/01_plantilla.md` § Rule 5 — Ordering Contract)*

### Rule 6 — Denormalized Writes

**Module scope:** Cross-module.

Denormalized count columns (e.g. `hc_filled`) must never be written directly — they must be derived. `vacancy_requirements.hc_filled` is FROZEN and DEPRECATED: `trg_freeze_vr_hc_filled` forces INSERT to 0 and raises on any UPDATE attempting to change it. The derived read path is `vw_vacancy_requirements` (security_invoker), which computes `hc_filled` as a live count of Active non-deleted Plantilla rows linked via `plantilla.vacancy_requirement_id`. Physical column removal is deferred (migration lint forbids the DDL token; requires an explicit override in a future prompt).

### Rule 7 — User Management as HRCO Single Source of Truth

**Module scope:** Cross-module (Vacancy, Plantilla, HR Emploc, Dashboard, Accounts).

User Management (`public.user_scopes` joined to `public.users_profile` with `roles.role_name = 'HRCO'`) is the exclusive authoritative Single Source of Truth for HR Coordinator (HRCO) assignments across all modules:

1. **Vacancy Resolution**: `public.vw_vacancy_list` and `public.list_web_vacancies` resolve `hrco_name` and `hrco_user_id` dynamically from active user scopes (account-level scope first, cascaded group-level scope second).
2. **Plantilla Resolution**: `public.v_plantilla_safe` and `public.list_web_plantilla_employees` resolve `hrco_name` and `coordinator` dynamically from active user scopes.
3. **Accounts Synchronization**: `public.accounts.hrco_user_id` is maintained in strict synchronization with User Management via `public.fn_reevaluate_hrco_auto_tags`.
4. **HR Emploc Inheritance**: New candidate deployments inherit their `hrco_name` and `hrco_user_id_snapshot` directly from the account/vacancy HRCO.
5. **Active Filter Contract**: Only active, non-archived user profiles (`users_profile.is_active = TRUE AND users_profile.archived_at IS NULL`) are recognized and projected as HRCOs. Soft-archived or suspended profiles are strictly suppressed and will render as `Unassigned` on requisitions until an active HRCO is assigned or the profile is reactivated.
6. **Self-Healing Reactivation Contract**: When an Administrator modifies a user's role/scopes (`public.upsert_user_profile_and_scopes`) or activates a user (`public.set_user_active`), the database automatically restores `is_active = TRUE`, clears `archived_at = NULL` and `archived_by = NULL`, and dispatches `public.fn_reevaluate_hrco_auto_tags` across all affected account scopes.

### Rule 8 — Universal Global Search Lifecycle De-duplication & Direct Target Navigation Contract

**Module scope:** Cross-module (Plantilla, Vacancy, HR Emploc, Onboarding, Stores, Accounts).

Universal Global Search (`public.search_global_index`) and command palette navigation across Web and Mobile enforce strict workforce lifecycle deduplication and direct contextual target routing:

1. **Current State Single-Occurrence Invariant (Zero-Duplicate Identity Lock):**
   - Every individual workforce member or candidate across recruitment, onboarding, deployment, and separation must appear **strictly once** in global search results, reflecting their single authoritative **current operational state**.
   - Lifecycle precedence strictly governs result resolution: **Plantilla Active/On-Leave/Floating/Deactivation > Plantilla Inactive > HR Emploc > Pipeline Applicants**.
   - Duplicate records resulting from multi-batch baseline imports, historical separation logs, multi-store roving allocations, or multi-stage progression are deterministically coalesced on human identity key (`dedup_key = 'person::' || COALESCE(employee_no, emploc_no, account || '::' || employee_name)`). When multiple records share the same identity at the same lifecycle stage, the most recent record (`created_at DESC`) is projected. Stale or duplicate entries are permanently suppressed.
2. **Direct Contextual Target Routing Contract (Employee vs. Store):**
   - **Employee Navigation**: Selecting an employee record routes **directly to that individual's profile or active processing record**:
     - Plantilla personnel navigate directly to the dedicated full-page Employee Profile (`/plantilla/[id]` on Web; `EmployeeProfileScreen` on Mobile).
     - HR Emploc candidates navigate directly to their queue record with modal detail auto-selected (`/hr-emploc?id=[id]`).
     - Pipeline applicants navigate directly to the vacancy pipeline workspace (`/vacancy?tab=pipeline&search=[vcode]`).
   - **Store Navigation**: Selecting a store location (matched by store name, branch, or VCode) routes **directly to that Store**:
     - On Web, routes directly to Plantilla Store View with the target store capacity detail modal automatically opened (`/plantilla?view=store&search=[vcode]&storeId=[id]`), allowing instant inspection of store authorized headcount, active personnel, open vacancies, and operational duty schedules.
     - On Mobile, routes directly to Plantilla Store View filtered to the selected store location.

### Validation

`SELECT * FROM fn_adr001_smoke();` — 6 assertions (A1 slot/occupant coherence, A2 derived hired, A3 single-tab priority, A4 ordering, A5 privilege lockdown, A6 rolled-back lifecycle probes), zero persistent changes. Run it after any change touching slots, hired-HC derivation, or vacancy tab classification.

### Slot-Creation Traceability (`ohm#7v3k9m5r` — 2026-08-06)

`fn_trg_auto_create_vacancy_slot()` — the `AFTER INSERT OR UPDATE OF status, required_headcount ON vacancies` trigger that auto-creates `plantilla_slots` rows — stamps `source_hc_request_id = NEW.source_headcount_request_id` at INSERT time (falling back to `NULL` only when that column is itself `NULL` on the vacancy row). Previously hardcoded `NULL`, relying entirely on `create_plantilla_slot_from_request`'s follow-up "adoption" `UPDATE ... WHERE source_hc_request_id IS NULL` to backfill the real value — a step that only ran when that RPC was the caller. Direct admin writes to `vacancies.required_headcount`/`status` (RLS-restricted to Super Admin/Head Admin) bypassed adoption entirely, leaving permanently untraceable slots — confirmed live on staging across multiple pre-existing rows, not just the two `ohm#8t4w6r9p`/`ohm#3k7m9x2v` incident rows.

**Binding rule:** direct admin writes to `required_headcount`/`status` remain fully permitted (unchanged, RLS-gated) — they no longer produce untraceable orphans as a side effect. `create_plantilla_slot_from_request`'s adoption `UPDATE` is left in place as a defensive no-op (it fires only when the trigger's stamped value was itself `NULL`); do not remove it.

**Known consequence, not a defect:** when an HC request increases `required_headcount` on a VCode reused from a *different, earlier* HC request (no fresh `vacancies` INSERT), the new slot inherits the vacancy row's original `source_headcount_request_id`, not the expanding request's id — traces to demand origin rather than to whichever request most recently touched the row. Accepted as more architecturally correct than the prior mis-attribution behavior.

**Not covered by this fix:** pre-existing orphaned slots created before `20260806020000` are not backfilled. Migration `20260806020000_fix_trigger_slot_source_hc_request_id.sql`.

---
