<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-001-Full. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/.ai/architecture_locks/ADR-001-ohmployee-system-architecture.md
source_commit: 08ac81e 2026-11-25T19:31:17+08:00
source_sha256: c01612a7fef31bf1cfd3bd322c6b61146b2dddda58f529e8165e71b0f4f3907c
synced_at: 2026-11-27T02:09:40.990Z
-->
# ADR-001: OHMployee System Architecture

## Status & Scope

**Status:** ACCEPTED. Mandatory architecture lock for all AI-assisted work.

**Active modules:** Vacancy, HR Emploc, Plantilla, More Module, Dashboard, CENCOM.

This document is the single canonical ADR-001. It consolidates two files that evolved separately under the shared "ADR-001" label:

- `docs/architecture/ADR-001-system-slot-and-derived-invariants.md` (originally `ADR-001-vacancy-derived-logic.md`, accepted 2026-07-30) — the 6 cross-module Core Invariants (Slot Authority, Hired HC Source, Lifecycle Sync, Classification Priority, Ordering Contract, Denormalized Writes).
- `.ai/architecture_locks/adr_001_coverage_architecture_v2.md` ("ADR-001: Coverage Architecture v2") — HC Request / Coverage Group semantics, the 6 Coverage Change actions, Employee Integrity, and the HR Emploc Import slot-first lifecycle.

Both governed real, overlapping architecture (both touch HC Request, Vacancy, Plantilla, HR Emploc Import, Dashboard, CENCOM) and both were live-enforced, so neither could simply be deleted in favor of the other. This file merges them by module so a future task can target-read one section instead of the whole document. **Merged and superseded 2026-08-04 (`ohm#8n4t6w2r`)** — `docs/architecture/ADR-001-system-slot-and-derived-invariants.md` is deleted; this file is the sole ADR-001.

Any AI agent must read the relevant section(s) of this ADR before editing: HC Request, Vacancy, Plantilla, HR Emploc Import, Dashboard, CENCOM, or More Module. If existing code or docs conflict with this ADR, treat this ADR as the architecture lock and document the conflict before changing behavior.

---

## Core Cross-Module Invariants

These four rules are binding across every module that touches slot state, hired-headcount derivation, or denormalized counters. Documented once here — not duplicated per module. Do not revert any rule without equally explicit re-verification and an update to this document.

### Rule 1 — Slot Authority

**Module scope:** Plantilla & Vacancy primarily; HR Emploc and Onboarding write paths also participate.

`fn_set_slot_status` is the ONLY path that may change `plantilla_slots.slot_status`. All lifecycle writers are rewired through it: `move_to_plantilla` (reserve/finalize), `_execute_approved_coverage_request` (all 5 slot writes), `tag_backout` (slot release), and HR Emploc Import's submit/approve/reject/rollback flow (open→hr_processing→pipeline transitions). Callers RAISE on a `blocked` result — never silently ignore it. `anon`/`authenticated` hold zero table- or column-level UPDATE privilege on `plantilla_slots` (guard-asserted live).

The 5 SA-gated admin/QA bulk archive functions (`fn_archive_*`, `fn_qa_*`, `fn_rollback_archive_batch`) remain justified direct writers — bulk archival is not a lifecycle transition. (This is the basis for the More Module compliance note below.)

**Backout releases the slot in the same transaction:** `tag_backout` resolves the linked plantilla slot (`hr_emploc.slot_id`, else unambiguous single-`hr_processing`-slot fallback on the vcode) and releases it → open via `fn_set_slot_status(reason 'BACKOUT')`; blocked release is FATAL (22023). Slots occupied by a different employee are never released. Reason codes `BACKOUT`/`HC_READD` are seeded into `slot_reason_codes`; `slot_history.reason_code` is FK-checked. Matrix extension: `closed`/`hc_reduced`→`open` only with reason `HC_READD`/`COVERAGE_STORE_REMOVED`/`COVERAGE_GROUP_DISSOLVED`.

#### Slot-Level Position Independence Contract (Multi-HC Heterogeneous Positions)
For multi-headcount stores, distinct physical slots under the same store `VCODE` are permitted to hold **heterogeneous positions** (e.g., Slot 1 = `Quality Assurance`, Slot 2 = `Stockman`).
- **Slot Ownership of Position**: Position identity is a property of the physical slot (`plantilla_slots.position_id` / `position_name_snapshot`) and vacancy requisition, not permanently frozen or collapsed at the store level.
- **No Blanket Position Overwrite**: Headcount expansion, amendment approvals, and separation triggers must preserve and stamp the specific requested position onto the newly generated or reopened slot. Approval RPCs (`approve_headcount_amendment_request`, `approve_headcount_request`) and views (`vw_vacancy_list`, `v_plantilla_safe`) are **STRICTLY PROHIBITED** from overwriting all existing store slots with a single parent position.

### Rule 2 — Hired HC Source

**Module scope:** Cross-module derived read. Source of truth lives in Plantilla; consumed by Vacancy, Dashboard, CENCOM, HR Emploc, and Onboarding.

`hired_count` derives STRICTLY from `plantilla.status = 'Active'` per VCode, filtered to active occupants only. No other source (applicant status, `hc_filled`, view fallbacks) may contribute to a Hired count. A Confirmed-Onboard applicant not yet in Plantilla counts nowhere — its slot sits `hr_processing`, not hired. When an employee is tagged Inactive (Resigned, AWOL, Terminated, Endo, Backout, etc.), `hired_count` drops immediately and the slot/vacancy reopens.

### Rule 3 — Lifecycle Sync

**Module scope:** Cross-module (Applicant / Vacancy / Plantilla / HR Emploc / Onboarding).

An applicant/vacancy status change (hire, backout, separation) must never leave its corresponding `plantilla_slots` row dangling. This is enforced as a backstop, not just a convention: a deferred CONSTRAINT TRIGGER (`trg_applicant_terminal_slot_sync`) on `applicants` fails the transaction at COMMIT if a move into Backout/Withdrawn/Separated leaves its slot unclaimed (`hr_processing`) or still occupied/filled by that applicant's plantilla row.

#### Separation Vacancy Reopen & Attribution Contract
When an active employee separates (Resigned, AWOL, Terminated, Endo) and their slot is reopened via `fn_plantilla_separation_to_vacancy` / `_apply_separation`:
1. **Accurate Vacancy Date Reset**: The resulting vacancy's `vacancy_date` must be **reset to the employee's separation `effective_date`** (or `date_of_separation`), rather than retaining an ancient vacancy date from years or months prior. This ensures SLA and aging metrics accurately reflect the current unfulfilled period.
2. **Deterministic Ownership Attribution**: `vacancies.triggered_by` must record the authenticated actor (or `users_profile.id`) who submitted or executed the separation, guaranteeing unambiguous auditability.

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

### Validation

`SELECT * FROM fn_adr001_smoke();` — 6 assertions (A1 slot/occupant coherence, A2 derived hired, A3 single-tab priority, A4 ordering, A5 privilege lockdown, A6 rolled-back lifecycle probes), zero persistent changes. Run it after any change touching slots, hired-HC derivation, or vacancy tab classification.

### Slot-Creation Traceability (`ohm#7v3k9m5r` — 2026-08-06)

`fn_trg_auto_create_vacancy_slot()` — the `AFTER INSERT OR UPDATE OF status, required_headcount ON vacancies` trigger that auto-creates `plantilla_slots` rows — stamps `source_hc_request_id = NEW.source_headcount_request_id` at INSERT time (falling back to `NULL` only when that column is itself `NULL` on the vacancy row). Previously hardcoded `NULL`, relying entirely on `create_plantilla_slot_from_request`'s follow-up "adoption" `UPDATE ... WHERE source_hc_request_id IS NULL` to backfill the real value — a step that only ran when that RPC was the caller. Direct admin writes to `vacancies.required_headcount`/`status` (RLS-restricted to Super Admin/Head Admin) bypassed adoption entirely, leaving permanently untraceable slots — confirmed live on staging across multiple pre-existing rows, not just the two `ohm#8t4w6r9p`/`ohm#3k7m9x2v` incident rows.

**Binding rule:** direct admin writes to `required_headcount`/`status` remain fully permitted (unchanged, RLS-gated) — they no longer produce untraceable orphans as a side effect. `create_plantilla_slot_from_request`'s adoption `UPDATE` is left in place as a defensive no-op (it fires only when the trigger's stamped value was itself `NULL`); do not remove it.

**Known consequence, not a defect:** when an HC request increases `required_headcount` on a VCode reused from a *different, earlier* HC request (no fresh `vacancies` INSERT), the new slot inherits the vacancy row's original `source_headcount_request_id`, not the expanding request's id — traces to demand origin rather than to whichever request most recently touched the row. Accepted as more architecturally correct than the prior mis-attribution behavior.

**Not covered by this fix:** pre-existing orphaned slots created before `20260806020000` are not backfilled. Migration `20260806020000_fix_trigger_slot_source_hc_request_id.sql`.

---

## HC Request & Coverage Semantics

### Core Decisions

1. HC means People only.
2. Coverage Group means store structure only.
3. Store count must never affect HC.
4. Manual Coverage Weight and manual HC Share inputs are deprecated for headcount derivation; per-store fractional capacity ($1/N$) is auto-computed strictly by the database (ADR-002 Invariant 4) for store-level capacity views while Account/Company HC remains people-only.
5. Coverage Request never creates slot, vacancy, pipeline, or HC.
6. HC Request is the only source of workforce demand.
7. Roving workforce uses Coverage Group vacancy.
8. Stationary workforce uses Store vacancy.
9. Coverage Request replaces the old Coverage Group and Coverage Change Request modules.
10. Before editing HC Request, Vacancy, Plantilla, Recruitment, Dashboard, CENCOM, or Coverage modules, AI must read ADR-001 first.
11. Store Master (`stores` table) is the single source of truth for `province`, `city`, and `island_group`. Never infer location from store name. `island_group` is always derived from province via `fn_derive_island_group()`.
12. Roving HC Request — Store-Array Path: when a Roving HC Request carries `hc_request_stores` rows (≥2 stores), approval creates N VCodes (one per store) and 1 new CGCode. VCode = per-store vacancy identity. CGCode = grouping layer. They are disjoint namespaces. CGCode never replaces VCode.
13. Roving HC Request — Legacy Path: when a Roving HC Request carries a `coverage_group_id` (no `hc_request_stores` rows), approval adds `coverage_slots` to the existing Coverage Group. This path is preserved and unchanged.
14. No cross-island Coverage Groups: a Coverage Group cannot span Luzon + Visayas, Luzon + Mindanao, or Visayas + Mindanao. Validated at backend (hard block in `submit_headcount_request` and `create_plantilla_slot_from_request`) and at UI (client-side warning via `fn_validate_coverage_island_group`).
15. Store removal from Coverage Group: a removed store's VCode survives. Only the coverage membership (`coverage_group_stores` row) is removed. Vacancies are never deleted by coverage structure changes.
16. Adding stores to an existing Coverage Group: use Coverage Change Request → Add Store (not a new HC Request). A new HC Request always creates a new Coverage Group.
17. Mixed Stationary + Roving Store Coexistence: A store with active Stationary employee(s) may simultaneously be covered by one or more Roving employees under a Coverage Group (CGCODE). Store-level capacity sums Stationary (1.00 each) + Roving ($1/N$ each, e.g., 1.50 for 2-store roving, 1.33 for 3-store roving), while Account/CENCOM/Dashboard HC always counts distinct people.
18. Request Headcount vs. Request New Store Separation: Request Headcount (Plantilla Store View per-row Stationary action + Plantilla header Roving action) operates strictly on existing stores. Request New Store is an independent Plantilla header flow owning all unlisted store openings (Stationary 1-store with initial HC >= 1, and Roving multi-door openings per ADR-003).
19. Automatic Inactive Status on Effective Date of Separation: When `plantilla.date_of_separation` is populated and `<= CURRENT_DATE`, the employee's status automatically transitions to `Inactive` (or `Deactivated`), even without a prior deactivation request. The employee is immediately excluded from active deployed headcount (`Actual = 0`), and their occupied slot in `plantilla_slots` is vacated (`slot_status = 'open'`), reopening the replacement vacancy for the store.
20. Headcount Expansion on Existing Stores Contract: An approved Headcount Request for an already existing store/VCode MUST NEVER route to New VCode / New Store Creation. It must strictly execute in-place Quota Revision via `revise_vcode_headcount_quota` (incrementing `hc_required` on the store) and provision additional physical `plantilla_slots` with sequential `slot_ordinal`s (e.g., ordinal 2, 3) under that exact same VCode. Generating duplicate VCodes or spawning new stores for existing store locations is strictly prohibited.

### Definitions

**HC** — a count of people required by the workforce plan. HC is not a count of stores, store assignments, coverage links, routes, branches, or area footprints. One employee is one HC, regardless of how many stores they cover.

**Coverage Group** — store structure only. Represents a group of stores, anchors, or area coverage relationships for roving work. A Coverage Group does not create demand by itself.

**HC Request** — the only approved source of workforce demand. Approved HC Requests create or change workforce demand according to the approved slot and vacancy architecture.

**Coverage Request** — manages changes to coverage structure and coverage relationships. Coverage Request never creates: Slot, Vacancy, Pipeline, or HC. Coverage Request replaces the old Coverage Group and Coverage Change Request modules.

### Workforce Rules

**Stationary Workforce** — demand uses Store vacancy. A stationary employee belongs to the store vacancy and slot model.

**Roving Workforce** — demand uses Coverage Group vacancy. A roving employee may cover multiple stores, but still counts as one HC. Coverage Group vacancy is the vacancy surface for approved roving workforce demand.

- *Store-Array Path (`ohm#r8v2k7m4`, 2026-06-22):* When a Roving HC Request is submitted with a `store_ids` array (≥2 stores via `hc_request_stores`): on approval, N VCodes are created (one per store) + 1 CGCode (new Coverage Group). `hc_request_stores` rows carry `store_name_snapshot`, `province_snapshot`, `city_snapshot`, `island_group_snapshot`. Island group is validated before submission: all selected stores must share the same island group. The Coverage Group binds the N vacancies via `coverage_group_stores`.
- *Legacy Path (preserved):* When a Roving HC Request carries a `coverage_group_id` (no `hc_request_stores`): on approval, `coverage_slots` are added to the existing Coverage Group. This path is unchanged and must not be broken.

**Store Master Authority** — `stores.island_group` is the canonical source for island group, automatically derived from `stores.province` (or `stores.area_province`) via the `fn_derive_island_group()` trigger. Client code must read `island_group` from the store record — never infer it from store name text.

**Coverage Group Island Group Constraint** — a Coverage Group must never span more than one island group (Luzon, Visayas, Mindanao). Enforcement: backend hard block in `submit_headcount_request` and `create_plantilla_slot_from_request`; client-side pre-validation via `fn_validate_coverage_island_group(account_id, store_ids)`.

**VCode vs CGCode Namespace** — VCode: per-store vacancy identity, one per store vacancy. CGCode: Coverage Group identifier, groups N VCodes for roving workforce. Disjoint namespaces — CGCode never replaces VCode. VCodes are never deleted when a store is removed from a Coverage Group.

**Coverage Group Vacancy Consolidation & Fractional Capacity Contract (`ohm#cg-vac-frac`, 2026-11-14)** — When stores are assembled into a Coverage Group (roving cluster), whether occupied or vacant:
1. **Module-Scoped Row Consolidation**:
   - **Vacancy Module (`/vacancy`)**: Member stores belonging to an active Coverage Group consolidate into **one single row** under the minted `CGCode` (with underlying store `VCode`s preserved in details). Headcount remains 1-employee recruitment demand (`0/1` or confirmed/total) without confusing fractional HC fractions in the list table.
   - **Plantilla Vacancy Tab (`/plantilla`)**: Member stores maintain **1:1 rows per store** (unmerged), representing individual store-level slots. Each store displays its own dedicated `VCode` and branch name with a `Roving` badge.
2. **Fractional Slot Allocation**: In the Plantilla Vacancy tab, each roving member store's slot allocation reflects fractional roving capacity ($\text{Slot} = 1/N$, e.g., $0.5$ for 2 stores, $1/3$ for 3 stores). The total headcount demand across the cluster remains governed by the 1-employee-per-roving-slot invariant.
3. **Structure-Only & Vacant Grouping**: If a Coverage Group is formed from vacant stores without an active employee (`v_employees_converted = 0`), member stores' plantilla slots transition to `is_roving = true, employment_type = 'Roving'`, and their vacancies are linked under the group's `CGCode`.

**Mixed Stationary + Roving Store Capacity & Entry-Point Architecture (`ohm#phase1-mixed-roving-hc`, 2026-11-23)** — Cross-repo binding invariants for simultaneous Stationary and Roving coverage at the same store and clean Request Headcount vs. Request New Store entry-point separation:
1. **Stationary + Roving Coexistence on Same Store**: Store 1 (Juan, Stationary = `1.00`) + Store 2 (Pedro, Stationary = `1.00`) + Maria (Roving across Store 1 & Store 2 = `0.50` each) yields Store 1 = `1.50`, Store 2 = `1.50`, Account Total = `3` people. Approving a Roving HC Request on an already-occupied store MUST create a distinct `plantilla_slots` row (`slot_ordinal = max + 1`, `is_roving = true`, `employment_type = 'Roving'`, `coverage_group_id = v_new_cg_id`) without altering or converting existing Stationary slots/employees.
2. **Dynamic $1/N$ Recalculation on Coverage Structure Changes**: Adding or removing a store in a Coverage Group (`Add Store` / `Remove Store` via `_execute_approved_coverage_request`) MUST atomically insert/deactivate the member store's `employee_store_allocations` row and recompute `filled_hc = ROUND(1.0 / N, 2)` across all active member stores for every roving employee in that group (e.g., adding Store 3 shifts Maria from `0.50` → `0.33`, yielding Store 1 = `1.33`, Store 2 = `1.33`, Store 3 = `0.33` or `1.33` if Store 3 also has a stationary).
3. **Account vs. Store Reconciliation Parity (Web + Mobile)**: Account, Dashboard, and CENCOM HC ALWAYS count distinct people (`3` people, never summing rounded `0.33` fractions). Store View (`StoreCapacityTable` on Web and Store View on Mobile) computes `Active Deployed = SUM(filled_hc)` and `Open Vacancy = SUM(stationary open slots + 1/N per roving open slot)` from the shared Supabase DB so Web and Mobile display identical `1.50` / `1.33` values.
4. **Request Headcount vs. Request New Store Entry-Point Architecture (Web + Mobile)**:
   - **Plantilla → Store View (per-row `Request HC`)**: Pre-locked Stationary HC request for that existing store (all request types: Additional, Replacement, Reliever, Commando, HC Reduction; zero New Store detour).
   - **Plantilla Header (`+ Request Roving HC`)**: Existing stores only (2–20 stores, same Island Group).
   - **Plantilla Header (`+ Request New Store`)**: Independent entry point for all unlisted/opening stores — Stationary mode (1 new store + initial HC >= 1 so approved stores immediately receive an Open Vacancy and appear in Store View) and Roving mode (2–20 new/mixed stores per ADR-003 atomic provisioning → `/approvals?tab=new_stores`).
   - **Vacancy Detail Drawer**: Retains Admin `Adjust Headcount Quota` and Ops `Request HC Adjustment` for quick existing-VCode adjustments.

### Deprecated Concepts

Manual Coverage Weight and manual HC Share inputs are deprecated for company headcount derivation and must not be used to inflate company/account HC from store count or store footprint. DB-computed $1/N$ fractional store allocation (ADR-002 Invariant 4) governs Store View capacity display only.

### Forbidden Logic Examples

- `SUM(hc_share)`
- `store_count = HC`
- Coverage Group creates vacancy
- One employee counted as multiple HC
- Multiplying HC by the number of stores in a Coverage Group
- Treating Coverage Group store membership as workforce demand
- Creating slots from Coverage Request approval
- Creating pipeline records from Coverage Request approval
- Deriving Dashboard HC from coverage store footprint

### Coverage Change Architecture (added OHM2026_CG_0001 — 2026-06-22)

Coverage Change Requests support exactly **six actions**. These are distinct, non-overlapping, and locked.

| # | Action | Scope |
|---|--------|-------|
| 1 | Add Store | Add a store to an existing Coverage Group |
| 2 | Remove Store | Remove a single store; group must retain ≥2 stores |
| 3 | Convert Stationary to Roving | Employee-centric; may create or join a Coverage Group |
| 4 | Convert Roving to Stationary | Employee-centric; user selects retained Home Store |
| 5 | Merge Coverage Groups | Combine multiple groups into one |
| 6 | Dissolve Coverage Group | Remove entire group relationship; all roving → Stationary |

**Add Store Rules** — Target Coverage Group must exist and be active. Store cannot belong to another active Coverage Group. Store cannot be archived or inactive. Active employees remain assigned — no automatic conversion. No automatic vacancy creation. Coverage simulation required.

**Remove Store Rules** — Coverage Group must retain ≥2 stores after removal. Removing from a 2-store group is blocked — use Dissolve Coverage Group. Employee assignments remain unchanged. Vacancy recalculated if coverage is lost.

**Convert Stationary to Roving Rules** — Employee-centric action. May create a new Coverage Group or join an existing one. No duplicate employee records. No automatic employee replacement. Coverage simulation required.

**Convert Roving to Stationary Rules** — Employee-centric action. User must select retained Home Store. Employee must retain at least one active store. Other stores become uncovered → vacancy slots created/opened if needed. Coverage simulation required.

**Merge Coverage Groups Rules** — Duplicate store membership blocks merge — conflicts must be resolved first. Employee assignments remain unchanged. Vacancy state preserved. Old groups become merged/inactive.

**Dissolve Coverage Group Rules** — Group-centric action. Every active roving employee must be assigned a retained Home Store before dissolution. No employee may end with zero active stores. All roving employees become Stationary. Uncovered stores become vacant. **Existing vacancies must be reused** — create a new vacancy only if no existing vacancy exists. Simulation required before approval.

**Global Coverage Group Rules (Locked)**

| Rule | Lock |
|------|------|
| Coverage Group may exist with zero employees | Store relationship, not employee relationship |
| Minimum active group size = 2 stores | A 1-store group is not a Coverage Group |
| Add Store never auto-converts employees | Conversion is always explicit |
| Multiple roving employees allowed per group | No restriction on roving employee count |
| Merge blocked on duplicate store membership | Conflicts must be resolved first |
| Dissolve must reuse existing vacancies | No duplicate vacancies |
| Coverage History mandatory for all 6 actions | See field list below |

**Coverage History Mandatory Fields** — all 6 Coverage Change actions must write a history record with: Request ID, Action Type, Before State, After State, Requested By, Approved By, Approval Timestamp, Reason.

### Employee Integrity Architecture Lock (added OHM2026_CG_0001 — 2026-06-22)

> **An active employee must always retain at least one active store assignment.**

Hard architecture lock enforced across all Coverage Change actions and all other modules that affect store-employee assignment (including HC Request, Vacancy, Plantilla, and Coverage Execution).

**Forbidden state:** `Employee → active_store_assignments = 0`. Never permitted for any active employee regardless of which Coverage Change action is in progress. Applies to all 6 actions (Add Store, Remove Store, Convert Stationary to Roving, Convert Roving to Stationary, Merge Coverage Groups, Dissolve Coverage Group). Any RPC, migration, or Flutter action that would leave an active employee with zero active store assignments must be blocked before execution.

### Coverage Group Creation Details (`ohm#4h8w1qz6` — 2026-07-06)

- `create_coverage_group` execution must insert exactly **one** `coverage_slots` row (slot_ordinal=1, status='open') for pure-structure groups (`v_employees_converted = 0`), regardless of member store count. Store count must never scale open-slot rows — this is a corollary of Core Decision #3 ("Store count must never affect HC").
- `coverage_groups.position_id` on creation is inherited from the anchor store (`plantilla_slots` has no `position_id` column, only a text `position` column):
  - **Occupied case:** the anchor store's active `plantilla` row's `plantilla.position_id` (the current active employee's position — a real uuid FK).
  - **Open-slot fallback:** `plantilla_slots.position` (text) matched by name against `positions.position_name` (text) to resolve `positions.id`.
  - If neither resolves, `position_id` remains NULL. This never blocks Coverage Group creation.

### Approvals Clearinghouse Architecture (Eleven Functional Review Queues)

**Status: ACCEPTED.** Codifies the centralized request clearinghouse (`/approvals`) across Web and Mobile:

1. **Eleven Dedicated Functional Queues**:
   Review operations are partitioned into 11 strictly separated functional queues:
   - `new_stores`: New Store Requests & Roving Door Expansion Requisitions (Option 1).
   - `headcount`: Standard Headcount Quota Amendments & Requisitions for existing stores.
   - `account_requests`: User Account Sign-Ups & Profile Provisioning.
   - `coverage`: Roving Coverage Group Requests (Add Store, Remove Store, Merge, Dissolve).
   - `vacancy_closures`: Vacancy Closure Requests (linked to Vacancy Closure Tab).
   - `hr_emploc_deletions`: HR Emploc Candidate Deletion Requests.
   - `deactivations`: Employee Deactivation & Separation Clearance.
   - `applicant_movements`: Cross-Store Applicant Movement & Transfer Requests (`vw_amr_list`).
   - `relievers`: Workforce Pool Reliever Coverage Endorsements (`v_workforce_assignment_request_queue`).
   - `account_archives`: Billing Account Retirement Approval Queue (Super Admin only).
   - `rollbacks`: Spreadsheet Import Batch Rollbacks & Reversal Queue (Super Admin & Head Admin).
2. **Access Control & Universal Super Admin Bypass**:
   - **Super Admin (`role_level >= 100` / `isOwner`)**: Holds universal bypass authority across all 11 review queues.
   - **Head Admin (`role_level >= 90`)**: Access to all operational request queues, user provisioning, and import rollbacks.
   - **Encoder (`role_level === 30`)**: Scoped access to operational queues (`headcount`, `new_stores`, `hr_emploc_deletions`, `deactivations`).
   - **Operations Manager (OM) & Field Roles**: Strictly blocked from administrative clearinghouse queues unless specifically granted approval authority over their direct team endorsements.

### Option 1 Requisition Queue Routing (New Doors vs. Headcount Quota)

**Status: ACCEPTED.** Eliminates operational ambiguity and blank store lines in the Headcount queue:

1. **Automatic Routing Trigger (`hc_request_stores.is_new_store = true`)**:
   - Requisitions submitted via headcount amendment that contain proposed unlisted / new store doors automatically route out of the standard `Headcount` queue and land in **Tab 1: New Stores** (`/approvals?tab=new_stores`).
   - Requisitions on pre-existing stores without new doors remain in **Tab 2: Headcount** (`/approvals?tab=headcount`).
2. **Review Pane Display Invariant**:
   - In `New Stores`, multi-door roving proposals render all proposed branches (`Store 1, Store 2, Store 3`) with location snapshots and a `✨ New Roving Doors (N)` badge.
   - In `Headcount`, store columns reliably display registered store names without ambiguous `Store: —` fallbacks.
3. **Dispatch & Execution Parity**:
   - Approving a new store headcount request dispatches to `approve_headcount_request`, which atomically provisions the unlisted stores in `public.stores` before minting CGCode, VCodes, and Slots.

### ADR-003 Unified Roving Requisitions & Atomic Store Provisioning

**Status: ACCEPTED.** Solves multi-store opening bottlenecks for Roving Headcount requisitions (`submit_headcount_request`):

1. **Zero Database Pollution**:
   - Proposed unlisted stores submitted in `hc_request_stores` carry location metadata (`store_name`, `area_province`, `area_city`, `island_group`) but cause **zero speculative rows in `public.stores`** during the pending request lifecycle.
2. **Atomic Store Insertion upon Approval (`create_plantilla_slot_from_request`)**:
   - When the requisition is formally approved by Head Admin or Super Admin:
     - **Step 1.5 (Atomic Store Provisioning)**: Inserts each unlisted store into `public.stores` (with auto-generated store code, account binding, and derived island group via `fn_derive_island_group`), updating `hc_request_stores.created_store_id`.
     - **Step 2 (Coverage Group & Slot Creation)**: Binds the newly created stores into a new Coverage Group (`CGCode`), mints per-store VCodes in `public.vacancies`, and creates `plantilla_slots` rows in a single database transaction.
3. **Hard-Block Island Group Span Constraint**:
   - Proposed roving store clusters spanning multiple island groups (Luzon, Visayas, Mindanao) are rejected at both frontend validation and database level (`submit_headcount_request`).

### Account Group Transfer Direct Admin Execution Policy

**Status: ACCEPTED.** Simplifies operational hierarchy and governance:

1. **Retirement from Approval Queues**:
   - Account Group Transfers are permanently removed from `/approvals` queues (`account_group_transfer_requests` queue retired).
2. **Direct Execution in Plantilla**:
   - Head Admin (`role_level >= 90`) and Super Admin (`role_level >= 100`) execute group transfers directly from the Plantilla Account Directory context menu (`Transfer Group`).
   - Backed by RPC `transfer_account_group_direct(p_account_id, p_to_group_id, p_reason)` with pre-execution impact simulation (`simulate_account_group_transfer`) and mandatory audit logging to `public.audit_logs`.

### Dedicated Requester Tracking Feed (/my-requests)

**Status: ACCEPTED.** Provides personal request tracking across Web and Mobile:

1. **Cross-Platform Requester Surface**:
   - Requesters who lack access to the admin `/approvals` clearinghouse (OM, HRCO, TL, ATL, Encoders) track all their submitted requests via `/my-requests` (Web) and `My Requests` (Mobile).
2. **Unified Aggregation across Six Request Sources**:
   - Queries and normalizes user-submitted rows from: `headcount_requests`, `new_store_requests`, `vacancy_closure_requests`, `v_deactivation_requests`, `vw_amr_list`, and `coverage_requests`.
   - Unified status taxonomy: `pending`, `approved`, `rejected`, `cancelled`.
3. **Option 1 Parity**: Headcount requests introducing new store doors render under `category: "new_stores"` with clear title `New Store (Position): Store Names` and subtitle `Account · N New Door(s) Proposed`.

---

## HR Emploc (Onboarding Compliance & Import Lifecycle)

### Core Pipeline & Lifecycle

The HR Emploc module bridges candidate onboarding confirmation and official deployment as an active employee:

```
Vacancy (Confirmed Onboard) → HR Emploc (Onboarding Compliance) → Plantilla (Official Active Employee)
```

For batch spreadsheet uploads, the lifecycle strictly follows:

```
HC Request approved
        ↓
Plantilla Vacancy Slot created
        ↓
Vacancy opens (Open / Pipeline)
        ↓
Employee gets hired
        ↓
HR Emploc Import (references VCode → occupies existing slot)
        ↓
Employee appears in HR Emploc
        ↓
Vacancy automatically closes
```

### Rule 1 — Slot-First Architecture

HR Emploc Import shall always require a valid Plantilla Slot identified by a VCode. No Plantilla Slot means no HR Emploc Import. HR Emploc Import may only occupy an existing Plantilla vacancy slot. It does not create workforce capacity.

### Rule 2 — HR Emploc Import Never Creates Capacity

HR Emploc Import must never: create Plantilla Slots, create Vacancy records, increase Required HC, or bypass the Plantilla lifecycle. Its sole responsibility is to occupy an existing open slot and advance the employee into the HR Emploc stage.

### Rule 3 — VCode Is the Source of Truth

HR Emploc Import shall always require a valid Plantilla Slot identified by a VCode. Approval occupies the existing Plantilla Slot and preserves the VCode throughout the employee lifecycle. Every HR Emploc Import row references exactly one VCode. That VCode resolves the Plantilla Slot, Group, Account, Store, and Position. All attributes must be validated against the Plantilla Slot — never derived from manually uploaded column values. Every HR Emploc record must remain linked to a valid Plantilla Slot through its assigned VCode. HR Emploc records without a corresponding Plantilla Slot are prohibited. Historical implementations may have allowed HR Emploc records without linked Plantilla Slots — this behavior is deprecated and must not be reintroduced.

### Rule 4 — Valid Slot States for Import

Import is permitted only when the Plantilla Slot is in one of these states: `open`, `pipeline` or `hr_processing`. Import must be rejected when the slot is: `occupied` (already has an active occupant), `archived`, `closed`, `hc_reduced`, or non-existent for the given VCode.

### Rule 5 — Approval Behavior

When an import batch is approved: one HR Emploc record is created per valid row; the corresponding Plantilla Slot is marked occupied; the corresponding Vacancy is closed (status → Filled); the VCode is preserved on the HR Emploc record; the full audit history is preserved. Duplicate HR Emploc records and duplicate slot occupancy are never permitted.

### Rule 6 — Validation Error Messages

Validation must never return a generic error. Every rejection must state the exact reason, including: VCode not found, Plantilla slot not found, VCode belongs to another group, Slot already occupied, Slot archived, Slot closed, Position mismatch, Store mismatch.

### Rule 7 — Single Occupancy

One Plantilla Slot may have only one active occupant at any time. Duplicate occupancy must be rejected before any record is committed.

### Rule 8 — Audit Trail

Every import event must preserve the identity of who uploaded, who approved, when the import occurred, which employee was imported, which VCode was used, and what the previous vacancy status was. Audit records must never be overwritten or deleted.

### Forbidden Patterns

- Accepting an import row without a resolvable VCode and Plantilla Slot
- Creating a new Plantilla Slot from import approval
- Creating a new Vacancy from import approval
- Bypassing slot state validation
- Importing into an occupied, archived, closed, or non-existent slot
- Returning generic validation errors in place of field-specific messages

### Vacancy Closure on HR Emploc Import

Vacancy represents the open demand surface for a Plantilla Slot. When HR Emploc Import occupies the slot, the corresponding vacancy must close automatically.

| Event | Vacancy State Change |
|-------|----------------------|
| HC Request approved | Vacancy created (`Open`) |
| Applicant enters pipeline | Vacancy → `Pipeline` |
| HR Emploc Import approved (slot occupied) | Vacancy → `Filled` |
| Import rolled back | Vacancy re-opened if slot is unoccupied |

### Five Operational Queues (Status Tabs Architecture)

**Status: ACCEPTED.** Codifies the standard onboarding queues in HR Emploc across Web and Mobile:

1. **Tab 1: Pending** (`status = 'Pending Emploc'` AND `hr_status = 'Pending'`): Operational requirements intake. Field Ops coordinators in scope (OM, TL, ATL, HRCO) and Super Admin upload candidate compliance documents to private storage bucket `hr-corrections`. Advancing to `For Emploc` via `submit_hr_emploc_requirements` strictly requires at least 1 uploaded document.
2. **Tab 2: For Emploc** (`status = 'Pending Emploc'` AND `hr_status = 'For Emploc'`): Deployment readiness queue. Requirements are verified and the record is ready for Emploc ID assignment.
   - Primary Actions: `+ Add Emploc` (assigns employee number and auto-deploys to Plantilla) and `! Tag Deficiency` (returns record to `For Correction`).
   - Document upload/removal is strictly disabled on this tab.
3. **Tab 3: Correction** (`hr_status = 'For Correction'`): Deficiency queue. Displays deficient documents returned to field coordinators. In-scope Ops coordinators re-upload corrected compliance files and resubmit to review (`submit_hrco_correction_update`), transitioning the record to `For Review`.
4. **Tab 4: Review** (`hr_status = 'For Review'`): Review queue for corrected resubmissions. Authorized reviewers evaluate the resubmission to either `Approve` (assigns Emploc ID and auto-deploys to Plantilla in same transaction) or `Return to Correction`.
5. **Tab 5: Deployed** (`status = 'Moved to Plantilla'` OR `hr_status = 'Transferred'` with `deleted_at IS NULL`): Historical and audit queue for records assigned an Employee ID and deployed to Plantilla.
   - Actions: `Edit Emploc` and `Revert to Pending` (Data Team & Super Admin only).
   - SLA timer freezes displaying `Completed in X days`.

### Emploc Number Assignment Ownership (HR Personnel Primary, Data Team Backup)

**Status: ACCEPTED.** Governs operational roles and responsibilities for assigning Employee Numbers (`employee_no` / `emploc_no`):

1. **Primary Operational Owner — HR Personnel**:
   - **HR Personnel** is the primary, dedicated authority responsible for verifying candidate compliance documents and assigning Employee Numbers in the `For Emploc` and `Review` queues.
2. **Operational Backup — Data Team (Head Admin & Encoder)**:
   - **Data Team** (Encoder and Head Admin) serves as operational backup. They are fully authorized to step in and assign Employee Numbers (`+ Add Emploc`) when candidate volume is high or when HR Personnel is heavily loaded, ensuring onboarding throughput is never throttled.
   - Head Admin and Encoder remain strictly BLOCKED from tagging deficiencies (`Tag Deficiency`) or reviewing corrected documents (`Review Return`), preserving HR compliance integrity.
3. **Super Admin**: Retains full administrative override capability across all queues and workflows.

### Atomic Deployment to Plantilla & Permanent Employee Number Registry (Rules a–d)

**Status: ACCEPTED.** Enforces transaction safety and 1:1 lifetime identity governance:

1. **Atomic Deployment (`_assign_and_deploy_emploc_core`)**:
   Assigning an Employee Number (via `assign_hr_emploc_number` on Pending/For Emploc or via `review_web_hr_emploc_correction` on Review) executes atomically in the **exact same database transaction**:
   - Validates `/^[A-Za-z0-9._-]+$/` employee number format.
   - Asserts permanent 1:1 ownership in `public.employee_number_registry` under the four registry lock rules below.
   - Transitions the linked `plantilla_slots` row to `slot_status = 'occupied'` (`current_occupant_plantilla_id = plantilla.id`).
   - Inserts the new active `public.plantilla` employee record (`status = 'Active'`).
   - Updates `public.hr_emploc` to `status = 'Moved to Plantilla'` and `hr_status = 'Transferred'`, recording `moved_to_plantilla_at = now()`.
   - Closes the corresponding vacancy slot and generates a unified audit trail entry.
2. **Permanent Employee Number Registry Lock Rules (under `SELECT FOR UPDATE`)**:
   - **Rule a (Hard Block)**: If the number is already assigned to a different person (evaluated via normalized full name) $\rightarrow$ raises `EMPLOYEE_NO_ALREADY_ASSIGNED` (`23505`).
   - **Rule b (Hard Block)**: If the same person already has an active placement or active Plantilla record with that number $\rightarrow$ raises `EMPLOYEE_ALREADY_ACTIVE` (`23505`).
   - **Rule c (Rehire Confirmation)**: If the same person was previously assigned that number but all prior records are inactive/resigned $\rightarrow$ raises `REHIRE_CONFIRM_REQUIRED` (`23505`) until `p_confirm_reuse = true` with a mandatory rehire justification is supplied.
   - **Rule d (Duplicate Warning)**: If the same person already owns a different number in the registry $\rightarrow$ raises `POSSIBLE_DUPLICATE_PERSON` (`23505`) until confirmed with reason.
3. **Strict Missing Required Fields Assertions (No Silent Defaults)**:
   - Moving to Plantilla strictly requires non-null `hired_date`, `position`, `account`/`account_id`, `store_name`/`store_id`, and applicant structured name. Silent fallbacks (`CURRENT_DATE` defaults, synthetic name splitting) are prohibited and raise `FIELD_REQUIRED_MISSING` (`23502`).

### Canonical Onboarding Compliance Requirements & 3-Day Storage Purge Queue

**Status: ACCEPTED.** Establishes required compliance artifacts and storage lifecycle:

1. **Canonical Statutory Requirements (4 items)**:
   Only four standard statutory and documentation items are recognized for onboarding compliance:
   - `INVALID_SSS`: SSS Card / ID Document (Remarks optional).
   - `INVALID_PAGIBIG`: Pag-IBIG Member ID (Remarks optional).
   - `INVALID_PHILHEALTH`: PhilHealth ID / MDF (Remarks optional).
   - `INCOMPLETE_REQUIREMENT`: Incomplete Documentation (Remarks strictly mandatory).
   *(Legacy NBI Clearance and PSA Birth Certificate are deprecated and removed from required onboarding checklists).*
2. **Three-Day Storage Purge Queue (`run_at = now() + interval '3 days'`)**:
   - Upon deployment to Plantilla, all uploaded compliance and correction documents in bucket `hr-corrections` are automatically enqueued into `storage_cleanup_queue` with a **3-day TTL**.
   - When the cleanup queue executes, physical storage objects are permanently deleted via Storage API and metadata records tagged `is_deleted = true, deleted_reason = 'deployed_3day_ttl'` for storage hygiene and PII protection.
3. **Three-Day Revert Grace Window**:
   - Data Team or Super Admin may execute `Revert to Pending` (`revert_hr_emploc_to_pending`) within the **3-day window**:
     - *Within 3 Days (Before Purge)*: The pending purge is cancelled, uploaded documents are preserved, and status is restored to `'For Emploc'`.
     - *After 3 Days (Post-Purge)*: Documents have been purged; status is restored to `'Pending'` requiring Ops to re-upload compliance documents.
   - Reverting to Pending soft-deletes the `plantilla` row, reopens the `plantilla_slots` row to `open`, and clears `employee_no = NULL`.

### Deployed Tab Revert Governance (Data Team Authority & Plantilla Cancellation)

**Status: ACCEPTED.** Codifies operational authority and atomic lifecycle mechanics when reverting records from the Deployed Tab:

1. **Role Authority (`public.can_edit_deployed_hr_emploc()`)**:
   - Only the **Data Team** (`Encoder`, `Head Admin`) and `Super Admin` are authorized to execute `Revert to Pending` (`revert_hr_emploc_to_pending`) on records in the **Deployed Tab**.
   - Field Operations coordinators (OM, TL, ATL, HRCO) and HR Personnel are strictly blocked from reverting deployed records, safeguarding active workforce rosters against unauthorized modification.
2. **Atomic Plantilla Cancellation & Disappearance**:
   - The deployed employee record in `public.plantilla` is soft-deleted and deactivated (`is_deleted = true`, `status = 'Deactivated'`). The employee **immediately disappears** from active Plantilla rosters and views (`v_plantilla_safe`).
   - Store links in `public.plantilla_store_links` are marked `status = 'Backed Out', unlinked_at = now()`.
3. **Plantilla Slot & Vacancy Reopening (Rule 1 & Rule 2)**:
   - The occupied slot in `public.plantilla_slots` is released via `public.fn_set_slot_status` back to `slot_status = 'open'` with `reason_code = 'BACKOUT'` and occupant cleared (`current_occupant_plantilla_id = NULL`).
   - The associated vacancy is reconciled and reopened (`status = 'Open'`).
4. **Restoration into HR Emploc Queues**:
   - The record returns to HR Emploc in status `status = 'Pending Emploc'` with `employee_no = NULL` and `moved_to_plantilla_at = NULL`.
   - **Queue Placement**:
     - *Within 3-Day Purge Window*: Queued storage purge is cancelled, uploaded documents are preserved, and the record is placed in **Tab 2: For Emploc** (`hr_status = 'For Emploc'`).
     - *Post 3-Day Purge Window*: If documents were already purged, the record is placed in **Tab 1: Pending** (`hr_status = 'Pending'`), requiring Operations to re-upload compliance documents.
   - The Employee Number Registry records the action in `history` (`action: 'revert_to_pending'`), releasing the number assignment while retaining full audit traceability.

### Three-Day Operational Compliance SLA Clock

**Status: ACCEPTED.** Enforces onboarding velocity and managerial escalation:

1. **SLA Calculation**: Baseline is `coalesce(date_requested, created_at)`. Threshold is **3 calendar days** (72 hours).
2. **Escalation Ladder**:
   - **SLA Tier 1 (3 Days)**: If a record has no `employee_no` assigned after 3 days, `sla_breached` evaluates to `true`. Renders prominent red alert badge in UI and dispatches notification to `Head Admin`.
   - **SLA Tier 2 (5 Days)**: Critical escalation. High-priority notification dispatched directly to `Super Admin`.

### Applicant Backout in HR Emploc & Vacancy Aging Continuity Invariant

**Status: ACCEPTED.** Governs operational backouts during HR Emploc onboarding (pre-deployment):

1. **Backout Execution (`tag_backout` / `reject_hr_emploc`)**:
   - When an applicant awaiting documentation or number assignment in HR Emploc backs out:
     - The applicant record is tagged `backout` and routes to the **Failed / Backout Tab** in Vacancy.
     - The linked slot in `public.plantilla_slots` transitions from `hr_processing` $\rightarrow$ `open` via `fn_set_slot_status(slot_id, 'open', 'BACKOUT')`.
     - The corresponding requisition immediately reappears in the **Vacancy Open Tab** (`remaining_open` increments).
2. **Original Vacancy Aging Continuity (Anti-Reset Lock)**:
   - When a slot returns to Open following an HR Emploc backout, its vacancy aging (`aging_days`, `aging_start_at`) **MUST NOT RESET** to the backout timestamp or `CURRENT_DATE`.
   - The aging clock preserves unbroken continuity from the **original date the position became vacant** (`vacant_date` / start of the vacancy episode when the prior employee separated or when the requisition was first created).
   - This ensures operational KPIs, aging alert badges (30d/60d), and executive dashboards truthfully report cumulative store vacancy duration without masking delays caused by applicant dropouts during onboarding.

---

## Vacancy

### Rule 4 — Classification Priority

**Module scope:** Vacancy (authoritative implementation). Dashboard and CENCOM are downstream consumers.

**Authoritative rule (do not revert without equally explicit re-verification — this exact rule has flipped 7 times in this repo's history; see `docs/state/vacancy_state.md` §`ohm#8j4q1r6z`):**

> Open tab: visible iff `(hc_needed - hired_count - pipeline_count - hr_processing_count) > 0`, shown with that value. Pipeline tab: visible iff `pipeline_count > 0`, independent of Open. A vacancy may appear in Open, Pipeline, both, or neither.

Closure still takes unconditional priority over both — a vacancy with a closed slot or pending closure request never shows in Open or Pipeline.

#### Operational Capacity Contract (Single-Slot vs. Multi-Slot Behavioral Matrix)
To eliminate operational ambiguity between Open and Pipeline queues across Web and Mobile:

1. **Single-Slot Vacancies (`required_headcount = 1`)**:
   - **Unassigned (`0/1`)**: Appears in the **Open Tab** (`remaining_open = 1`).
   - **Applicant Endorsed / Undergoing Screening (`1/1 in Pipeline`)**: The moment an applicant is added or enters screening (`For Interview / Intro`, `For Medical`, etc.), that single slot is under active processing. It **leaves the Open Tab** (`remaining_open = 1 - 1 = 0`) and moves to the **Pipeline Tab**.
2. **Multi-Slot Vacancies (`required_headcount > 1`, e.g. `3` Headcount)**:
   - **Partially Sourced (`1/3` or `2/3`)**: As long as unallocated capacity remains (`remaining_open > 0`), the requisition **MUST REMAIN in the Open Tab** displaying the remaining open slots (e.g. `1 Available` when 2 of 3 slots are in pipeline or hired). Simultaneously, the active applicants appear in the **Pipeline Tab**.
   - **Fully Allocated (`3/3`)**: Once all slots are occupied by active pipeline candidates, confirmed onboards, or active hires (`hired_count + pipeline_count + hr_processing_count >= hc_needed`), the requisition has zero unallocated demand (`remaining_open = 0`) and **completely leaves the Open Tab**.

### Standard Five Status Tabs Architecture & Candidate-Level Pipeline Expansion

**Status: ACCEPTED.** Codifies the standard queue surfaces and row granularity for the Vacancy module across Web and Mobile:

1. **Tab 1: Open** (`p_status = 'Open'`): Active store requisitions with remaining unallocated capacity (`(hc_needed - hired_count - pipeline_count - hr_processing_count) > 0`), displaying remaining unfilled slots.
2. **Tab 2: Pipeline** (`p_status = 'Pipeline'`): Active candidates undergoing recruitment screening.
   - **Candidate-Level Expansion Invariant (`ohm#p6k2v9q4`)**: In the Pipeline tab, requisitions expand into **1 Row per Candidate** (**per tao ang bilang**). A 3-headcount requisition with 2 active applicants renders as 2 distinct actionable rows displaying each candidate's full name, contact details, stage, and aging. The tab badge strictly reflects total active candidates, guaranteeing 1:1 parity with the rendered roster.
3. **Tab 3: Hired** (`p_status = 'Hired'`): Requisitions where candidates reached confirmed onboard status (`confirmed_onboard_count >= required_headcount`) or active Plantilla deployment.
4. **Tab 4: Closure** (`p_status = 'Closure'`): Requisitions with pending store closure or headcount reduction requests awaiting administrative approval (`has_pending_closure = true`).
5. **Tab 5: Failed / Backout** (`p_status = 'Failed'`): Historical roster of candidates who dropped out, backed out, failed medical/ops evaluation, or did not report.

#### Coverage Group Vacancy Invisibility & Shadow Section Deprecation
- **Dedicated Coverage Group Surface**: Vacancies for roving roles spanning $N \ge 2$ stores are managed exclusively under the parent Coverage Group (`CGCODE`).
- **Standard Vacancy Tab Exclusion**: Stationary stores that belong to an active Coverage Group do not generate actionable open vacancies in the standard store vacancy queue.
- **Deprecation of "Covered by Coverage Group" Cards**: The experimental read-only shadow section ("Covered by Coverage Group") previously rendered inside the standard Account Vacancy tab is **deprecated and retired from the UI**. All Coverage Group vacancies are managed within their dedicated Coverage Group views to prevent operational confusion.

### Strict Applicant Closure Lock Invariant (`ohm#c3m8v1k4` — 2026-11-12)

**Status: ACCEPTED.** Database trigger / assertion `public.fn_assert_vacancy_closeable(p_vcode)` enforces that:
- Requesting vacancy closure or approving closure is **HARD BLOCKED for all roles** (including Super Admin, Ops, and Recruitment) whenever active, non-terminal applicants exist in the pipeline.
- Requesters must first formally advance candidates to confirmed placement (`Mark Hired`) or record terminal dropouts (`Backout`, `Failed`, `Rejected`, `Did Not Report`) with mandatory reason capture before closure can be initiated.

### Six Canonical Pipeline Stages & One-Time Profile Edit Policy (`ohm#p8r4m2k9`, `ohm#p9v2k4m7`)

1. **Six Progressive Pipeline Stages**: Candidate progression strictly standardizes on 6 sequential stages:
   `1. For Interview / Intro` $\rightarrow$ `2. For Requirements` $\rightarrow$ `3. For Medical` $\rightarrow$ `4. Pending Approval` $\rightarrow$ `5. For Deployment` $\rightarrow$ `6. For Onboard`.
2. **Terminal Dropouts**: Terminal exits are categorized into `Backout`, `Failed / Rejected by Ops`, `Rejected`, or `Did Not Report` with mandatory audit reason logging.
3. **One-Time Profile Edit Policy (`fn_update_applicant_profile_once`)**: Non-admin users are restricted to exactly one profile identity edit (`profile_edit_count = 0`) with uppercase name normalization, contact number verification, and mandatory edit audit justification. Super Admin and Head Admin maintain administrative bypass.

### Slot-Based Vacancy Demand Authority (Slots, Not Store Count)

**Status: ACCEPTED.** Total vacancy across an account or the organization is STRICTLY derived from authorized, unfulfilled **physical slots** (`plantilla_slots`), NEVER from the count of store branches:
1. **Multi-Headcount Stores**: A single store requiring 3 employees with 0 deployed staff constitutes **3 Vacancy Slots**, NOT 1 vacancy.
2. **Roving Coverage Groups**: A roving coverage group spanning 5 stores for 1 roaming merchandiser constitutes **1 Vacancy Slot**, NOT 5 vacancies.
3. **Core Invariant**: Store count must never dictate vacancy demand. Physical rows in `public.plantilla_slots` with `slot_status IN ('open', 'pipeline')` remain the sole unit of measure for vacancy counting across all views, KPIs, and reports.

### Vacancy Lifecycle Transitions (Backout Reopening, In-Flight Closure, & 30-Day Hired Auto-Archive)

**Status: ACCEPTED.** Codifies the state transitions between the 5 operational tabs:

1. **Applicant Backout & Immediate Slot Reopening with Aging Continuity**:
   - When an active candidate backs out (whether in Vacancy screening via `failBackoutApplicant` or in HR Emploc onboarding via `tag_backout`):
     - The applicant record is tagged `backout` and routes to the **Failed / Backout Tab**.
     - The linked plantilla slot is immediately released to `open` via `fn_set_slot_status(slot_id, 'open', 'BACKOUT')`.
     - Database trigger `trg_reopen_vacancy_on_slot_open` restores `vacancies.status = 'Open'`, and because unallocated capacity increases (`remaining_open > 0`), the store **immediately reappears in the Open Tab** ready for new candidate endorsement.
     - **Aging Continuity Invariant (Anti-Reset Lock)**: Reopening the vacancy MUST NOT reset its aging clock (`aging_days`) to the backout date or `CURRENT_DATE`. The requisition's aging strictly maintains unbroken continuity from the original date the position became vacant (`vacant_date` / separation date of the previous employee / initial headcount requisition creation). Failed recruitments and candidate dropouts during screening or HR Emploc onboarding never wipe out the accumulated vacancy duration.
2. **In-Flight Closure Request Routing**:
   - When Operations submits a vacancy closure request (`has_pending_closure = true`, `closure_request_status = 'Pending'`):
     - The requisition **immediately vacates the Open and Pipeline tabs** (Rule 4 closure priority).
     - It routes to the **Closure Tab** (`p_status = 'Closure'`) to await administrative review and approval (`Approve / Reject / Withdraw`).
3. **Hired Auto-Archive 30-Day Governance**:
   - Fulfilled requisitions / confirmed onboards remain visible in the **Hired Tab** for an operational auditing window of **30 calendar days**.
   - Database sweep function `fn_archive_hired_vacancies` automatically transitions records with `a.hired_at < NOW() - INTERVAL '30 days'` to `is_archived = true`, `status = 'Archived'`, cleanly archiving completed historical hiring cycles while preserving full audit history.

**7th revision (`ohm#w8r4n2yj`, 2026-08-04):** added `hr_processing_count` as a third subtraction term. Rationale: a Confirmed-Onboard/HIRED applicant sitting in `plantilla_slots.slot_status = 'hr_processing'` (awaiting Employee Number, before reaching `Plantilla.status = 'Active'`) was previously counted in NEITHER `hired_count` NOR `pipeline_count` — a real population, already exposed as `hr_processing_count` in `vw_slot_derived_vacancy_shadow`, that business confirms is effectively already hired and not truly vacant. No SQL change required — the column already existed in the view; only `VacancyItem.remainingOpenCount` (`models.dart`) and Dashboard's parallel raw-map formula (`dashboard_screen.dart`) were updated.

**Status: SHIPPED, live-verified (commit `622fa4f`; 7th revision commit pending).** The DB's raw `open_count`/`derivedOpenCount` field (`hc_needed - hired_count`, no pipeline or hr_processing subtraction) is a distinct, still-valid field used by 9+ other call sites for org-wide capacity totals — it is not itself wrong, it simply is not the Open-tab membership/display formula.

**Known gaps** for Dashboard/CENCOM consumers of this rule are tracked in the "Dashboard & CENCOM" section below, not here — this section is Vacancy's own authoritative implementation only.

### vw_slot_derived_vacancy_shadow / Standardized Open Visibility Filter

This is the original 2026-07-30 decision this ADR started from, preserved here as Rule 4's Vacancy-specific detail:

1. **Derived Logic as Single Source of Truth**: All layers (API, service queries, repository methods, dashboard aggregations, movement targets, and UI screens) MUST rely EXCLUSIVELY on derived vacancy state from `vw_slot_derived_vacancy_shadow`.
2. **Standardized Open Visibility Filter**: A vacancy is defined as "Open" if and only if `open_count > 0` (or `vacancy_tab = 'Open'`) — the base-line filter that Vacancy's tab logic further refines with the pipeline subtraction above.
3. **Deprecation of Legacy Visibility Flags**: Base table fields `closed_at`, `status`, and `is_active` MUST NOT determine vacancy visibility, filtering, or counting in any query or endpoint.
4. **Backward Compatibility**: `closed_at` and `status` remain on `vacancies` for audit and historical record tracking only.

```sql
-- Standard Open Vacancy Query (Authoritative API / UI base filter)
SELECT *
FROM vw_slot_derived_vacancy_shadow
WHERE open_count > 0;

-- FORBIDDEN FOR VISIBILITY FILTERING (Do NOT use)
-- WHERE closed_at IS NULL
-- WHERE status = 'Open'
```

**Edge Case Resolution**: Even if `closed_at` is NOT NULL on legacy rows, if `open_count > 0`, the vacancy STILL SHOWS as Open. Audit and historical logs remain intact while operational queries rely on real-time slot state.

### Vacancy Requirements Normalization (`ohm#7f3a9c2d` — 2026-07-08)

**Status: ACCEPTED — MIGRATION APPLIED TO STAGING.** `supabase/migrations/20260708012728_add_vacancy_requirements_normalization.sql`.

**Context.** Vacancy previously assumed 1 position per VCode (`vacancies.position_id` + `vacancies.required_headcount`). This caused HC ambiguity when multiple positions were required under a single request.

**Decision.** Introduce `public.vacancy_requirements` as line items under a vacancy (VCode): `vacancy_id` (FK → `vacancies.id`, cascade), `position_id` (not null), `employment_type`, `hc_needed` (> 0), `hc_filled` (>= 0, trigger-guarded to never exceed `hc_needed`).

**Consequences.**
- Enables per-position HC tracking under a single VCode.
- Enables structured assignment (future UI/RPC work — not part of this migration).
- Legacy `vacancies.position_id` / `vacancies.required_headcount` are preserved byte-for-byte — no destructive change, no column drop, no existing query rewritten.
- RLS is read-only for `authenticated` for now: `vr_same_access_as_vacancy` composes with `vacancies_read_scoped` via an `EXISTS` subquery (a role only sees a requirement row if it could also see the parent vacancy row). No INSERT/UPDATE/DELETE policy is granted to `authenticated`/`anon` — per the RPC-first mutation rule, writes are deferred to a follow-up migration that introduces the assignment RPC. Until then only `service_role` can write.

**Backfill Result (verified on staging, 2026-07-08).** 117 of 245 `vacancies` rows have a non-null `position_id` and were backfilled 1:1 (`hc_needed = required_headcount`, `hc_filled = 0`). **Known gap:** 128 rows have `position_id IS NULL` and were skipped (the column is `NOT NULL` on `vacancy_requirements` by design — no fabricated FK values were inserted). Of those 128: 127 are historical (archived/closed/filled/soft-deleted, not live). **1 live exception:** `VCSSG2_0300` (account TWO, WAREHOUSE, status Open, not archived, not deleted) has `position` text (`WAREHOUSEMAN`) but no resolved `position_id` — a pre-existing data-quality gap in `vacancies` itself, not caused by or fixed by this migration. Flagged for a future data-repair pass; not blocking, since it's a single row and the legacy read path (`vacancies.position`/`required_headcount`) is completely unaffected.

**Requires (future work, not in this migration).** UI for the per-position assignment step. A `SECURITY DEFINER` RPC (with RBAC guard) to write `hc_filled` as positions are filled, replacing the current read-only-RLS posture.

### `vacancies.status = 'Archived'` Direct Writers (`ohm#9r4t7wln` — 2026-08-10)

**Distinct from Rule 1's "5" count above.** Rule 1's carve-out (`fn_archive_all_operational_data`, `fn_archive_plantilla_data`, `fn_qa_archive_operational_data_reset`, `fn_qa_rollback_operational_data_reset`, `fn_rollback_archive_batch`) is scoped specifically to direct writers of `plantilla_slots.slot_status` — a different table/column than this note. This note names the confirmed live direct writers of `vacancies.status = 'Archived'`, audited separately under `ohm#3k8n5wqz`, and applies the same underlying principle to them explicitly: **bulk archival is not a lifecycle transition**, so these SA-gated functions are justified in writing `vacancies.status` directly rather than being subject to `fn_is_valid_vacancy_transition()`'s transition-matrix gate.

Confirmed live writers (all `SECURITY DEFINER`, all gated on `is_super_admin()`, verified live 2026-08-10):

- `archive_vacancy_record` — single-record manual archive
- `fn_archive_all_operational_data` — full cross-module QA reset
- `fn_qa_archive_operational_data_reset` — full cross-module QA reset (earlier/parallel build of the function above)
- `fn_archive_vacancy_data` — Vacancy-module-only bulk archive
- `fn_archive_moses_hq_data` — archives pool vacancies (`is_pool_vacancy = true`)
- `fn_archive_hired_vacancies` — archives stale hired vacancies (Confirmed-Onboard ≥ 30 days)

**Informational, not an action item:** 3 of the 6 (`fn_qa_archive_operational_data_reset`, `archive_vacancy_record`, `fn_archive_hired_vacancies`) are currently unwired from any Flutter call site (confirmed via `.dart` source grep — only referenced in the auto-generated `database_types.ts` type file, never invoked). Flagged for a future cleanup/consolidation decision; not resolved here.

---

## Plantilla

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

### Dual Views & Six Status Sub-Tabs Architecture (`ohm#plantilla-subtabs-arch` — 2026-11-23)

**Status: ACCEPTED.** Codifies the standard interface and lifecycle organization for Plantilla across Web and Mobile.

The Plantilla module operates under **Dual Views** driven by a segmented view toggle:
1. **Store View (`Store Capacity Table`)**: Audits contracted store plantilla headcount compliance. Displays stores with active personnel or vacancies, computing fractional capacity for roving personnel ($1/N$). Stores without active personnel or vacancies are filtered out.
2. **Employee View (Directory Roster)**: Organizes workforce members across **Six Status Sub-Tabs**:
   - **Tab 1: Active** — Deployed personnel with `status = 'Active'`.
   - **Tab 2: On-Leave** — Personnel on approved leave, tracking Expected Date of Return (EDR) and reliever coverage.
   - **Tab 3: Vacancy** — All unfilled required slots (`1 Row = 1 Individual Slot`) and candidate onboarding pipeline (`Vacancy - Open`, `Vacancy - Pipeline`, `HR Emploc - *`).
   - **Tab 4: Floating** — Active personnel temporarily unassigned, subject to DOLE Article 301 monitoring.
   - **Tab 5: Deactivation** — Action queue for pending deactivation/separation approval requests.
   - **Tab 6: Inactive** — Persistent historical roster of separated personnel (`Resigned`, `AWOL`, `Terminated`, `Deactivated`), ordered via `vw_plantilla_inactive`.

**Universal View Modes**: Both Table and Responsive Cards views are universally supported across all 6 tabs.

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

---

## Dashboard & CENCOM

### Rule 4 compliance

**SHIPPED (`ohm#2q7x5m9j`, commit `c597b5c`; formula extended `ohm#w8r4n2yj`, 2026-08-04).** Shared `VacancyItem.remainingOpenCount` getter (`derivedOpenCount - displayPipelineCount - hrProcessingCount`, floored at 0) in `models.dart`. Dashboard's `openVacRowCount`/`agingList` row-count fallback and CENCOM's `_mapOperationalVacancies` aging-bucket/Target-Deployment membership filter both now gate on this formula, matching Vacancy's Rule 4 tab logic.

**Still non-compliant:** each module's *primary/headline* Open/Vacant KPI (Dashboard's `openVacCount` via `slotOpenVacCount`; CENCOM's `mfrVacant`/`_totalVacant`) is sourced from `slot_vacant_hc` (`v_account_allocation_kpi`/`v_cencom_allocation_kpi`) — a structurally different, `slot_status`-based formula (counts `slot_status IN ('open','pipeline')` as vacant) that is explicitly LOCKED (see `docs/state/cencom_state.md`, "Locked KPI Formulas OHM2026_0067/0073" — must not be changed without a new prompt decision). The `hr_processing_count` fix (`ohm#w8r4n2yj`) does NOT close this gap: `slot_vacant_hc` still counts pipeline slots as vacant capacity while Rule 4's `remainingOpenCount` subtracts pipeline, so the two formulas diverge whenever pipeline > 0 (they only coincide in the pipeline=0 case). Closing this fully still requires a backend migration and a deliberate decision to reopen that lock — a separate, dedicated prompt, not a Flutter-only change. Do not assume Dashboard/CENCOM's headline figures match the Vacancy screen's Open tab count until that follow-up ships.

### Rule 5 compliance

**Dashboard: COMPLETE, 6 of 6 sites (`ohm#d4w7k2ml`, 2026-08-05, extends `ohm#c8x1r6np`, 2026-08-04, extends `ohm#b6k9m4hp`, 2026-08-04, extends `ohm#a5t3g8ny`, 2026-08-04, extends `ohm#d7m2q8vx`, 2026-08-04).** All 6 confirmed client-side sort sites in `dashboard_screen.dart` are now fixed: the group-ops-summary site (`_buildOperationsGroups`) — new wrapper view `v_dashboard_group_allocation_kpi` (migration `20262606000027`, security_invoker over the unmodified `v_cencom_group_allocation_kpi`) enforces `ORDER BY mfr ASC, slot_vacant_hc DESC, group_name ASC` in-DB; `accountBreakdown` — new view `v_dashboard_account_breakdown` (migration `20262606000028`, security_invoker `GROUP BY account` aggregate over `v_plantilla_safe`) enforces `ORDER BY active DESC` in-DB; `agingList` — new view `v_dashboard_aging_vacancies` (migration `20262606000029`, security_invoker over `vw_slot_derived_vacancy_shadow`, gated on the full Rule 4 formula, reusing the base view's `aging_days` column) enforces `ORDER BY days_open DESC` in-DB; and `omStoreAging` — new view `v_dashboard_store_aging` (migration `20262606000030`, security_invoker `GROUP BY account_name` aggregate over `vw_slot_derived_vacancy_shadow`, `MAX(aging_days)` per store, same Rule-4-consistent open formula as `agingList` but without its `>= 30`-day floor) enforces `ORDER BY days_open DESC` in-DB — also a correctness fix, since the prior client-side loop read fields (`status`, `account`, `vacant_date`) absent from its source query's select and always returned empty. **Final 2 sites closed `ohm#d4w7k2ml`, 2026-08-05:** `accountMfrBreakdown` — new view `v_dashboard_account_mfr_breakdown` (migration `20262606000032`, security_invoker 3-way aggregate of `v_plantilla_safe`/`hr_emploc`/`vw_slot_derived_vacancy_shadow` grouped by `account`, vacancy component gated on the same Rule 4 formula) enforces `ORDER BY mfr ASC` in-DB; `omHrcoBreakdown` — new view `v_dashboard_hrco_breakdown` (migration `20262606000033`, same 3-way aggregate shape grouped by `hrco_name`, blank/null vacancy-source `hrco_name` bucketed to `'Unassigned'`) enforces `ORDER BY name ASC` with `'Unassigned'` pinned last in-DB — also a correctness fix, confirmed independently: both sites' vacancy component read `v['status']`/`v['account']`, neither of which exist in `vacQ`'s select, so it was always 0. Full detail: `docs/state/dashboard_state.md`.

**CENCOM: DRIFTED, not yet fixed.** CENCOM has 8+ client-side sort call sites, still sorting in Dart rather than relying on an in-DB `ORDER BY` view.

**Shared-view note:** `v_cencom_group_allocation_kpi` is now consumed by both modules with two different DB-enforced orders (CENCOM: `group_code ASC`; Dashboard via `v_dashboard_group_allocation_kpi`: `mfr ASC, slot_vacant_hc DESC, group_name ASC`). Any future change to the base view must be regression-checked against both.

### Known gap

`slotOpenVacCount`/`mfrVacant` headline KPIs still read the separately-locked `slot_vacant_hc` view, NOT the Rule 4 formula — requires a deliberate backend decision, out of scope until explicitly reopened.

### Executive Dashboard Command Center Architecture (/dashboard)

**Status: ACCEPTED.** Codifies the primary operational overview surface for executive leadership and managers:

1. **Top Four Executive KPI Cards**:
   - **Workforce Coverage**: Displays organizational average fill rate % (`avgFillRatePct`), seats filled subtitle (`X of Y seats filled`), and a prominent 3-color segmented progress bar (Active Plantilla, HR Emploc Pending, Open Vacancies) with target indicators (`Above 80% target` / `Below 80% target`). Routes to `/plantilla`.
   - **Open Vacancies**: Total active open vacancy slots, neutral unassigned count (`N unassigned to HRCO`), and direct navigation link. Routes to `/vacancy`.
   - **Hiring Pipeline**: Total pipeline candidate volume, active funnel badge, and monthly momentum indicator (`This month: +hired · −separated`). Routes to `/hr-emploc`.
   - **SLA Breaches**: Total active SLA breach count across vacancies and operational requests with action required pill. Routes to `/cencom`.
2. **Dashboard Announcement Banner Strip & Mandatory Urgent Acknowledgements**:
   - Displays active, non-expired announcements sorted with pinned items first, styled by priority (`urgent`: red alert, `important`: amber warning, `info`: blue notice).
   - **Mandatory Urgent Acknowledgement (`UrgentAnnouncementModal`)**: Blocks normal dashboard interaction until unacknowledged `urgent` items are formally acknowledged by the user (`public.announcement_acknowledgements`).
   - Subscribes to Supabase Realtime channel `realtime:announcements` and fans out in-app and mobile push notifications via database trigger `trg_announcement_notify()`.
3. **Asymmetric 2-Column Command Workspace**:
   - **Left Column (8 cols) — "Where is the gap?"**:
     - *Tab 1: Group Matrix*: Displays Group 1 to Group 5 by default with **MOSES HQ pinned below Group 5** (displaying real active headcount from global-to-CENCOM delta with `Standby` status). Rows in critical health receive high-visibility red highlights.
     - *Tab 2: SLA Breaches*: Live breach items with store branch, category, scope owner, aging, and action link.
     - *Tab 3: Under-staffed Stores*: Stores with urgent headcount deficits requiring immediate recruiter allocation.
   - **Right Column (4 cols) — "Needs your attention"**: Compact operational alert cards prioritizing critical groups, reconciled pending approvals count, under-staffed stores, and ghost employee anomalies linking to resolution centers.
4. **Recent Activity Feed (`public.fn_get_recent_activity`)**:
   - Chronological audit stream rendered as individual 1-by-1 subject-first sentences (`"<Actor>: <Subject> [<no>] transferred to Plantilla [<account>]"`).
   - Automatically deduplicates same-transaction mutations and scopes events to the caller's assigned organization or account.

### CENCOM Central Command Technical Architecture (/cencom)

**Status: ACCEPTED.** Codifies workforce fulfillment tracking, vacancy aging, and placement velocity:

1. **Five Standard Operational Tabs**:
   - **Tab 1: Overview** (`overview`): Hero Overall MFR sweep ring gauge, neutral KPI metrics (Total required, Total actual, Open vacancies, Deployed stores), and monthly deployment summaries.
   - **Tab 2: Groups** (`groups`): Granular group performance table with search, health filtering, store counts, and `PercentageBar` MFR progress indicators.
   - **Tab 3: Target Deployment** (`target_deployment`): Six standardized vacancy aging brackets (**1–15d, 16–30d, 31–60d, 61–120d, >121d, Advance**), province aging breakdowns, and store outlet drilldowns.
   - **Tab 4: Deployments** (`deployments`): Chronological candidate placement records and onboarding velocity.
   - **Tab 5: Quick Reports** (`reports`): 18 standard analytical workforce reports using semantic card surfaces.
2. **Standardized MFR Health Scale & Thresholds**:
   - **Healthy ($\ge 100\%$)**: Green status pill. Full capacity achieved.
   - **At Risk ($95\% - 99.99\%$)**: Amber status pill. Mild operational deficit requiring recruiter attention.
   - **Critical ($< 95\%$)**: Red alert pill. Urgent operational staffing deficit triggering managerial escalation.
3. **Dynamic Group Scope Selector**:
   - Dynamic organizational dropdown filtering metrics across `All groups` or individual assigned groups, strictly obeying caller scope boundaries (`cencom_scope = true` for broad access; scoped to assigned groups for OM, TL, ATL).

### Authoritative Database Pass-Through Principle ("Database Computes, UI Renders")

**Status: ACCEPTED.** Enforces architectural simplicity (KISS) and bandwidth optimization:

1. **Zero Client-Side Headcount Calculation**:
   - Client applications on Web and Mobile are strictly prohibited from downloading entire raw tables (`plantilla`, `plantilla_slots`) over the network to calculate headcount sums, fill rates, or vacancy totals in memory.
2. **Authoritative View Sourcing**:
   - All group metrics, account breakdowns, and KPI aggregates are computed natively by database views (`v_cencom_group_allocation_kpi`, `v_cencom_account_allocation_kpi`, `v_account_allocation_kpi`, `v_plantilla_safe`).
   - The UI layer functions purely as a presentation renderer of verified database-computed columns.

### Whole-Number Headcount & KPI Rounding Contract (Migration 20262606000147)

**Status: ACCEPTED.** Enforces clean executive reporting across organizational views:

1. **Whole-Number Corporate Presentation**:
   - Account-level and group-level headcount allocations and KPI metrics in views (`v_account_allocation_kpi`, `v_cencom_account_allocation_kpi`, `v_cencom_group_allocation_kpi`) display rounded whole numbers (`ROUND(actual_hc)`, `ROUND(slot_vacant_hc)`, `ROUND(required_hc)`).
   - Eliminates awkward fractional headcount decimals (e.g., `12.33` or `45.67`) on high-level executive cards, while underlying store-level allocations maintain mathematically accurate fractional capacity ($1/N$).

---

## More Module (Operations Hub & Administrative Governance)

Rule 1 and Rule 6 compliance: More Module's bulk archival and payroll-adjacent RPCs (`fn_archive_*`, `fn_qa_*`, `fn_rollback_archive_batch`) are the explicit, justified direct-writer carve-out named in Rule 1 above — bulk archival is not a lifecycle transition, so these functions may write `plantilla_slots.slot_status` directly rather than through `fn_set_slot_status`. They must still never write to a denormalized counter column (`hc_filled` etc.) per Rule 6 — only to the primary domain tables the archive operation targets.

### Five Operational Tabs Architecture (Operations Hub)

**Status: ACCEPTED.** Codifies the standard administrative surfaces and role-scoped hubs in Operations Hub (`/more`) across Web and Mobile:

1. **Tab 1: Overview** (`tab=overview`):
   - Fast operational dashboard and direct shortcuts: `User Management` (Head Admin), `Account Requests` (Head Admin), `Team Directory`, `Account Settings`, and `Sign Out`.
   - **OM Payroll Shortcut Invariant**: Operations Managers (OM) do not have access to the `data_control` tab; the `Payroll Review Center` shortcut is surfaced in Overview exclusively for OM. For Head Admin, Encoder, and Super Admin, the review hub is canonically accessed under `data_control`.
2. **Tab 2: Data Control** (`tab=data_control`, Head Admin 70, Encoder 30, Super Admin 100):
   - **Operations Sub-tab** (`subtab=operations`):
     - `ghost_detection`: Ghost Employees Detection Center (Type A / Type B dual anomaly classification, 7-day SLA, two-tier triage).
     - `payroll_review_center`: Payroll Review Center (canonical payroll review hub).
     - `roving_coverage_groups`: Roving coverage groups pool & 5-action coverage modal (Create, Add Store, Remove Store, Merge, Dissolve).
     - `global_store_transfer`: Cross-account and regional store reassignment governance.
     - `edit_lock_control`: Edit Lock security and field mutation freezes.
     - `data_archival_control`: Data Archival & Recovery Center (Super Admin Level 100 canonical single entry point).
   - **Batch Imports Sub-tab** (`subtab=batch_imports`): Canonical hub for spreadsheet batch ingestions.
3. **Tab 3: Permissions** (`tab=permissions`, Head Admin & Super Admin):
   - `permission_matrix`: Role permission overrides with interactive Allow/Deny toggles, per-row Reset to Default, and toolbar Reset All to Default (`get_effective_permission_matrix`, `apply_permission_overrides`, `reset_permission_overrides`).
   - `temp_permission`: Temporary Group Access overrides with expiring time-based grants.
   - `access_control_center`, `role_permissions`, and `permission_drift` mismatch detector.
4. **Tab 4: Audit** (`tab=audit`, Super Admin Level 100):
   - `audit_logs`: Detailed system audit activity trail rendered with human-readable operational summaries (`audit_formatter.ts`), entity badges (person name, VCode, outlet), and clean scalar field diffs. Locked down via `v_audit_activity_feed` (`role_level >= 90`).
   - `security_events`: Security alerts, unauthorized mutation flags, and threat indicators.
   - `allocation_health`: Workforce Integrity checks.
5. **Tab 5: Admin Tools** (`tab=admin_tools`, Super Admin Level 100):
   - `switch_role`: Role impersonation and acting sessions (`start_acting_session`, `stop_acting_session`).
   - `qa_center`: QA Simulation Engine (`qa_run_scenario`) with atomic subtransaction rollback and zero live table pollution.
   - `system_diagnostics`: System health probes, freeze diagnostics, and PostgREST schema cache reload utility (`NOTIFY pgrst, 'reload schema';`).
   - `ohms_safespace`: Emergency lockdown and system-wide killswitch.

### Canonical Batch Imports Architecture & 72-Hour Rollback Governance

**Status: ACCEPTED.** Governs spreadsheet batch ingestion across Web and Mobile:

1. **Full-Page URL Architecture**:
   - All 5 batch imports are rendered as full-page URL-driven views via `BatchImportPageShell` rather than modals: `/more?tab=data_control&subtab=batch_imports&import=<plantilla|hr_emploc|vacancy|mika|payroll>`.
   - Preserves browser history, provides unclipped horizontal scrolling for wide tabular previews, and pins sticky footer confirmation controls.
2. **The Five Canonical Batch Ingestion Engines**:
   - `plantilla`: Baseline and slot-first plantilla import (strictly governed by ADR-002; identity coalescing, 18+ age validation, schedule matrix validation).
   - `hr_emploc`: HR Emploc candidates bulk import (slot-first lifecycle, initial status `'Pending Emploc'`).
   - `vacancy`: Batch vacancy requirements and store openings import.
   - `mika`: Weekly biometric attendance and ghost employee detection ingestion.
   - `payroll`: Read-only payroll reconciliation checker with sticky review center handover.
3. **Standard 72-Hour Operational Rollback Window**:
   - Head Admin (70) and Super Admin (100) are authorized to execute batch rollbacks within **72 hours** of batch approval.
   - Requires mandatory operational justification (`rollback_reason`), transitions batch status to `'Rolled Back'`, unlinks/cleanses created domain records, restores slot statuses via `fn_set_slot_status`, and records immutable entries in `public.audit_logs`.

### QA Simulation Engine & Atomic Sandbox Isolation

**Status: ACCEPTED.** Codifies automated end-to-end multi-role testing in production and staging:

1. **Atomic Subtransaction Rollback (`public.qa_run_scenario`)**:
   - The simulation engine executes sequential operational workflows within an atomic PL/pgSQL block (`BEGIN ... EXCEPTION ... END`).
   - Forces controlled rollback via `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`, guaranteeing **100% zero live table pollution** across `vacancies`, `plantilla`, `applicants`, `hr_emploc`, and `users_profile`.
2. **Multi-Role Relay (`FULL_E2E_RELAY`)**:
   - Executes a 7-step cross-role relay: Head Admin (Quota) $\rightarrow$ Encoder (Slot) $\rightarrow$ Recruitment (Candidate) $\rightarrow$ HRCO (Onboard) $\rightarrow$ HR Personnel (Emploc ID) $\rightarrow$ Back Office (Movement) $\rightarrow$ Back Office Negative Security Barrier (asserting unauthorized mutations fail).
3. **Dual GUC Impersonation & Telemetry Persistence**:
   - Sets both `request.jwt.claim.sub` and `request.jwt.claims` for authentic role authorization testing, with defensive restoration of original claims.
   - Run telemetry and defect findings are persisted outside the rolled-back subtransaction in `public.qa_agent_runs` and `public.qa_agent_findings`.

### Role Impersonation & Acting Sessions Governance

**Status: ACCEPTED.** Governs runtime role simulation for debugging and operational auditing:

1. **Authority Gate (`public.start_acting_session`)**:
   - Strictly restricted to physical `role_level >= 100` (Super Admin) or system owner (`ohmpayatt@proton.me`).
   - Terminates any existing active acting session before initializing a new session in `public.acting_sessions`.
2. **Dynamic Context Overlay (`public.get_web_current_user_context()`)**:
   - Re-evaluates `allowed_module_keys` and `module_capabilities` to match the simulated role (e.g. simulating HRCO locks out Admin Tools and scopes data to assigned accounts).
   - **Email Privilege Containment**: Normalized role checks evaluate before physical email privileges in `getRoleLevel` and `hasFullAccess`, preventing super-admin bypasses from leaking during lower-role simulation.
3. **Clean Session Teardown (`public.stop_acting_session`)**:
   - Restores the caller's native context and comprehensively invalidates client query caches (`["currentUserContext"]`, `["active-acting-session"]`).

### Permission Matrix Overrides & Bulk Reset Contract

**Status: ACCEPTED.** Governs dynamic role capabilities and safety recovery:

1. **Granular Overrides (`public.apply_permission_overrides`)**:
   - Super Admin may configure per-role, per-module Allow/Deny capabilities (`role_permission_overrides`).
2. **Safety Recovery & Bulk Reset (`public.reset_permission_overrides`)**:
   - Supports both single-action "Reset to Default" and a toolbar "Reset All to Default" with confirmation modal.
   - Purges custom overrides and immediately restores baseline code-defined role capabilities across Web and Mobile.

### Audit Activity Feed Lockdown & Human-Readable Logging

**Status: ACCEPTED.** Protects corporate audit confidentiality and optimizes operational visibility:

1. **Database Access Lockdown**:
   - Base table `public.audit_logs` and view `public.v_audit_activity_feed` are restricted strictly to `role_level >= 90` (Head Admin and Super Admin) with `security_invoker = true`. Revoked from `authenticated` and `anon`.
2. **Human-Readable Entity Formatting (`audit_formatter.ts`)**:
   - Replaces raw JSON dumps and database UUIDs with contextual operational summaries, entity badges (Person name, VCode, Store branch), and clean scalar field diffs (`Field: Old Value → New Value`).

### MIKA Biometric Import & Ghost Employees Detection Center (`ohm#g8h4m2v9` — 2026-11-15)

**Status: ACCEPTED.** Codifies the architecture for MIKA biometric ingestion, anomaly classification, and the Operations Hub Ghost Employees Detection Center.

**Problem.** Weekly MIKA biometric attendance uploads audit employee presence in stores. Flagged discrepancies risk payroll fraud or untracked personnel, but without a unified cross-platform detection center, recurring weekly uploads either duplicate cases, lose tracking history, or leave separated personnel undetected.

**Architecture Decisions & Invariants (binding):**

1. **Dual Anomaly Classification (Strict Separation):**
   - **Type A (Unregistered / Missing from Plantilla):** Biometric record exists in MIKA with an Employee Number not found in active `public.plantilla`. Requires encoding or investigation.
   - **Type B (Inactive / Separated Anomaly):** Biometric record exists in MIKA, but matches an employee tagged as `Inactive`, `Separated`, `Deactivated`, or `Resigned` in `public.plantilla`. High-severity payroll leakage / immediate biometric revocation alert.

2. **Weekly Upload Case Continuity & SLA Age Preservation:**
   - A single continuous investigation case exists per employee in `public.possible_ghost_employees` while unresolved (`status NOT IN ('Cleared', 'Resolved', 'Auto Resolved', 'Confirmed Ghost', 'For Termination')`).
   - Subsequent weekly uploads of the same unresolved employee must NOT spawn duplicate rows; they update `last_revalidated_at = now()`, increment the revalidation count, and associate the latest `import_log_id`.
   - The initial detection timestamp (`created_at`) is permanently preserved to enforce the **1-week (7-day) SLA**:
     - *< 48 hours:* Normal Investigation (`Under Investigation`).
     - *48–72 hours:* Head Admin escalation notification.
     - *72 hours – 7 days:* Super Admin escalation notification.
     - *> 7 days (1 week):* Automatic **"Breached SLA (>7 Days)"** critical operational lock.

3. **Strict Plantilla Invariant & Two-Tier Triage Permissions:**
   - Pre-deployment onboarding status (e.g. HR Emploc pipeline) remains classified under strict investigation until the employee physically attains `status = 'Active'` in `public.plantilla`.
   - The database trigger `trg_ghost_resolve_on_plantilla_active` automatically transitions Type A cases to `'Cleared'` (`auto_resolved = true`, `resolved_at = now()`, `resolution_remarks = 'Auto-resolved: Found in Active Plantilla'`).
   - **Two-Tier Triage Permissions:**
     - *Field Ops (HRCO, TL, ATL):* Scoped to their allowed accounts (`account = ANY(get_my_allowed_accounts())`). May inspect cases and submit audited **Operational Verification Notes** (e.g., confirming store presence or unrecorded separation).
     - *Data Team & Admin (Encoder 30, HA 70, SA 90):* Authorized to execute formal status mutations: Assign to Encoder (72h deadline), Mark Cleared (audited reason), or Confirm Ghost / Payroll Freeze.

4. **Coalesced Statutory Benefits Hydration:**
   - Weekly MIKA import strictly prioritizes biometric attendance cross-checking and ghost detection.
   - Government statutory numbers (SSS, PhilHealth, Pag-IBIG, TIN, ATM) only coalesce into blank/null fields in `public.plantilla` upon batch approval without overwriting existing verified data.

5. **Approval-Triggered Targeted Notifications & Deep-Link Invariants:**
   - When a MIKA import batch is approved (`mika_import_logs.status = 'Approved'`) with detected ghost cases, notifications fire automatically:
     - *Operations Manager (60), Head Admin (70), Super Admin (90):* Global notification: `"{count} possible ghost employees flagged across all accounts. View here"` → links to `/more?tab=data_control&subtab=operations&tool=ghost_detection`.
     - *HRCO (40), TL (50), ATL (55), Encoder (30):* Account-targeted notification: `"{count} possible ghost employees flagged in {account}. Verify here"` → links to `/more?tab=data_control&subtab=operations&tool=ghost_detection&account={account}`.
   - Operations Hub surface contract: Located at `/more?tab=data_control&subtab=operations&tool=ghost_detection`, with deep links from CENCOM and Executive Dashboard anomaly alerts (`"Resolve Anomalies →"`).

6. **MIKA Rollback Governance & Ghost Invalidation:**
   - Head Admin (70) and Super Admin (90) can execute batch rollbacks within a 72-hour operational window if an erroneous or corrupt MIKA file was approved.
   - Sets `mika_import_logs.status = 'Rolled Back'`, records `rolled_back_by`, `rolled_back_at`, and mandatory `rollback_reason`.
   - Automatically cancels all open ghost employee cases generated by that batch (`public.possible_ghost_employees.status = 'Cleared'`, `resolution_remarks = 'Import Batch Rolled Back: ' || reason`), preventing false SLA alerts.
   - Audited via `public.audit_logs` with action `'MIKA_IMPORT_ROLLBACK'`.

---

## Known Gaps (cross-cutting tracker)

- **Rule 5 (Ordering Contract) open in:** CENCOM only. (Dashboard fully closed `ohm#d4w7k2ml`, 2026-08-05 — 6 of 6 sites: group-ops-summary `ohm#d7m2q8vx`, accountBreakdown `ohm#a5t3g8ny`, agingList `ohm#b6k9m4hp`, omStoreAging `ohm#c8x1r6np`, accountMfrBreakdown + omHrcoBreakdown `ohm#d4w7k2ml`, all 2026-08-04/05. Plantilla closed `ohm#6w3p9x4k`, 2026-08-03 — see Plantilla section above. HR Emploc closed `ohm#h4t8x1qy`, 2026-08-04 — both flagged `.sort()` sites are false positives: transient RPC input selection and a zero-rows fallback, not UI ordering contracts — not counted as drift.)
- **Rule 4 headline KPI gap:** `slot_vacant_hc`-derived headline KPIs (Dashboard `slotOpenVacCount`, CENCOM `mfrVacant`) not aligned with the Rule 4 formula — requires a dedicated backend-migration prompt to reopen the locked formula decision.

---

## Changelog

Historical record, chronological. Full rule substance now lives in the module sections above — entries here are trimmed to prompt ID, date, one-line summary, and a pointer to where the rule now lives.

- **2026-06-22 — OHM2026_CG_0001 / `ohm#r8v2k7m4`** — Coverage Change Architecture Lock (6 actions) + Employee Integrity Lock + Roving HC Request Store-Array Path. → "HC Request & Coverage Semantics" above.
- **2026-06-26 — `ohm#4n8x7kq2`** — Plantilla Slot as Single Source of Truth; HR Emploc Import Slot-First Lifecycle (8 rules) authored. → "HR Emploc Import" above; carve-out referenced in Rule 1.
- **2026-07-06 — `ohm#4h8w1qz6`** — Coverage Group creation: single `coverage_slots` row per pure-structure group regardless of store count; `position_id` inheritance from anchor store. → "HC Request & Coverage Semantics" above.
- **2026-07-07 — `ohm#k8d2x7qf`** — HRCO Employee-Level Scope Isolation (`plantilla_hrco_assignments`). → "Plantilla" above.
- **2026-07-07 — `ohm#7gk2d9xq`** — HRCO Global Visibility Override (bypass branch on the above). → "Plantilla" above.
- **2026-07-08 — `ohm#7f3a9c2d`** — Vacancy Requirements Normalization (`vacancy_requirements` line-item table). → "Vacancy" above.
- **2026-07-30** — Original ADR-001 acceptance (Vacancy-only at the time): `vw_slot_derived_vacancy_shadow` + `open_count > 0` as single source of truth for vacancy visibility. → "Vacancy" above (Standardized Open Visibility Filter).
- **2026-08-03 — `ohm#7k2d9f4a`** — DB-level enforcement shipped for all 6 cross-module rules: Slot Authority privilege lockdown, Lifecycle Sync constraint trigger, Rule 5 Plantilla Inactive ordering view, `fn_adr001_smoke()` validation RPC. → "Core Cross-Module Invariants" above.
- **2026-08-03 — `ohm#9m3w7v1r`** — Read-only 6-rule audit across HR Emploc, Dashboard, CENCOM, More Module, Onboarding; confirmed Rule 4/Rule 5 non-compliance gaps in Dashboard/CENCOM. No content change.
- **2026-08-03 — `ohm#7c4m9x2q`** — Read-only audit confirming ADR-001 scope mismatch (Vacancy-only doc vs. 6-rule briefing gate); recommended the cross-module consolidation. No content change.
- **2026-08-03 — `ohm#4d8n2k6t`** — Consolidated the Vacancy-scoped ADR-001 doc into a cross-module System & Slot Architecture Lock (`docs/architecture/ADR-001-system-slot-and-derived-invariants.md`), formalizing all 6 rules with per-rule module scope. First step toward this file; superseded by `ohm#8n4t6w2r` below.
- **2026-08-03 — `ohm#2q7x5m9j`** — Rule 4 drift fix in Dashboard and CENCOM (`remainingOpenCount` getter, commit `c597b5c`). → "Dashboard & CENCOM" above.
- **2026-08-03 — `ohm#6w3p9x4k`** — Rule 5 drift fix in Plantilla (`vw_plantilla_inactive` repoint, commit `b482a5a`) — Plantilla reaches Rule 5 compliance. → "Plantilla" above.
- **2026-08-04 — `ohm#d7m2q8vx`** — Rule 5 drift investigation + partial fix in Dashboard (group-ops-summary site only; `v_dashboard_group_allocation_kpi` wrapper, migration `20262606000027`). 5 of 6 Dashboard sort sites remain open — deferred, no existing DB shape to attach ordering to. → "Dashboard & CENCOM" above.
- **2026-08-04 — `ohm#a5t3g8ny`** — Rule 5 drift fix in Dashboard, site 2 (`accountBreakdown`; `v_dashboard_account_breakdown` wrapper, migration `20262606000028`). 4 of 6 Dashboard sort sites remain open. → "Dashboard & CENCOM" above.
- **2026-08-04 — `ohm#b6k9m4hp`** — Rule 5 drift fix in Dashboard, site 1 (`agingList`; `v_dashboard_aging_vacancies` wrapper reusing `vw_slot_derived_vacancy_shadow`'s `aging_days`, migration `20262606000029`). Also fixed a latent bug in the same diff: `vacQ`'s select was missing `hr_processing_count` despite the Rule 4 formula (`ohm#w8r4n2yj`) reading it. 3 of 6 Dashboard sort sites remain open. → "Dashboard & CENCOM" above.
- **2026-08-04 — `ohm#8n4t6w2r`** — Merged `docs/architecture/ADR-001-system-slot-and-derived-invariants.md` and `.ai/architecture_locks/adr_001_coverage_architecture_v2.md` into this single canonical, module-organized ADR-001; renamed to `ADR-001-ohmployee-system-architecture.md`; deleted the vacancy-scoped source file; corrected all cross-repo references; corrected `AI.md`'s stale ADR-001 module list to the confirmed active set (Vacancy, HR Emploc, Plantilla, More Module, Dashboard, CENCOM). Docs-only, no code/schema/migration changes.
- **2026-08-04 — `ohm#w8r4n2yj`** — Rule 4, 7th formula revision: added `hr_processing_count` as a third subtraction term (`remaining_open = hc_needed - hired_count - pipeline_count - hr_processing_count`). Fixes a real, previously-uncounted population (Confirmed-Onboard applicants awaiting Employee Number). Updated `VacancyItem.remainingOpenCount` (`models.dart`) and Dashboard's parallel raw-map formula (`dashboard_screen.dart`); CENCOM inherits automatically via the shared getter. No SQL/migration — `hr_processing_count` already existed in `vw_slot_derived_vacancy_shadow`. Does not close the `slot_vacant_hc` divergence gap (diverges whenever pipeline_count > 0). → "Vacancy" and "Dashboard & CENCOM" above.
- **2026-08-04 — `ohm#a5t3g8ny`** (this entry) — Rule 5 drift fix in Dashboard, `accountBreakdown` site (site 2 of the 5 remaining after `ohm#d7m2q8vx`; lowest-risk — single-table aggregate, no cross-table join, no known bug). New `v_dashboard_account_breakdown` view (migration `20262606000028`, security_invoker `GROUP BY account` over `v_plantilla_safe`) enforces `ORDER BY active DESC` in-DB. `dashboard_screen.dart` drops the client-side `accountMap` aggregation + `.sort()`, queries the new view via a 6th parallel Wave 1 call. 4 of 6 Dashboard sort sites remain open. → "Dashboard & CENCOM" above.
- **2026-08-04 — `ohm#c8x1r6np`** — Rule 5 drift fix + correctness fix in Dashboard, site 4 (`omStoreAging`; `v_dashboard_store_aging` view, `GROUP BY account_name` over `vw_slot_derived_vacancy_shadow`, migration `20262606000030`). Confirmed the field was fully broken (always empty) — prior Dart loop read `status`/`account`/`vacant_date` fields absent from its source query's select. New view uses the same Rule-4-consistent open formula as `agingList` but without the 30-day floor (that floor is specific to the aging-alert-list use case and would wrongly hide low-aging stores). 2 of 6 Dashboard sort sites remain open (`accountMfrBreakdown`, `omHrcoBreakdown`). → "Dashboard & CENCOM" above.
- **2026-08-05 — `ohm#d4w7k2ml`** — Rule 5 drift fix + correctness fix in Dashboard, sites 3 & 5 (FINAL, closes Dashboard Rule 5 6 of 6): `accountMfrBreakdown` (`v_dashboard_account_mfr_breakdown`, migration `20262606000032`) and `omHrcoBreakdown` (`v_dashboard_hrco_breakdown`, migration `20262606000033`) — both new `security_invoker` 3-way aggregates of `v_plantilla_safe`/`hr_emploc`/`vw_slot_derived_vacancy_shadow`, vacancy component gated on the Rule 4 formula, kept as two separate views (not one parameterized artifact) due to genuinely different blank-dimension-value semantics between `account` and `hrco_name`. Confirmed the same dead-vacancy-loop bug as sites 1/4: `v['status']`/`v['account']` don't exist in `vacQ`'s select, so the vacancy component of both breakdowns was always 0 — the `'Unassigned'` HRCO bucket, only ever creatable by that dead loop, had never once appeared despite its pinned-last sort logic already existing. Dashboard Rule 5 now fully compliant (6 of 6 sites); only CENCOM remains open. → "Dashboard & CENCOM" above.
- **2026-11-23 — `ohm#plantilla-subtabs-arch`** — Codified Plantilla Dual Views, Six Status Sub-Tabs, DOLE Article 301 Floating Governance (180-day statutory ceiling + slot-restricted reassignment), and On-Leave EDR SLA Escalation with Moses HQ Reliever Auto-Release. → "Plantilla" above.
- **2026-11-23 — `ohm#vacancy-capacity-governance`** — Codified Vacancy Rule 4 Single-Slot vs. Multi-Slot Capacity Behavioral Matrix (1/1 moves to Pipeline, multi-slot 1/3 and 2/3 remain in Open until 3/3 filled), Five Status Tabs, Candidate-Level Pipeline Expansion (1 Row = 1 Candidate), Strict Applicant Closure Lock, 6-Stage Pipeline Lifecycle, and 1-Time Profile Edit Policy. → "Vacancy" above.
- **2026-11-23 — `ohm#vacancy-lifecycle-transitions`** — Codified Applicant Backout & Slot Reopening (moves applicant to Failed/Backout, restores store to Open), In-Flight Closure Request Routing (moves out of Open/Pipeline into Closure Tab), 30-Day Hired Retention & Auto-Archival Window (`INTERVAL '30 days'`), and Slot-Based Vacancy Authority (demand strictly measured in physical slots, never store count). → "Vacancy" above.
- **2026-11-23 — `ohm#hr-emploc-compliance-arch`** — Codified HR Emploc Five Operational Queues (Pending, For Emploc, Correction, Review, Deployed), Emploc Number Ownership (HR Personnel Primary, Data Team Backup), Atomic Plantilla Deployment & Registry Rules a–d, Canonical Statutory Requirements (4 items), 3-Day Storage Purge Queue & Revert Grace Window, 3-Day Compliance SLA, and Deployed Tab Revert Governance (Data Team Authority & Plantilla Cancellation). → "HR Emploc" above.
- **2026-11-23 — `ohm#emploc-backout-aging-continuity`** — Codified HR Emploc Backout to Vacancy Open Tab with Original Aging Continuity Invariant (retains original vacancy date, never resetting to backout date) and Deployed Tab Revert Governance (Data Team authority, soft-deletes Plantilla row, releases slot to open via BACKOUT). → "HR Emploc" and "Vacancy" above.
- **2026-11-23 — `ohm#more-module-operations-hub-arch`** — Codified More Module (Operations Hub) Five Operational Tabs (Overview, Data Control, Permissions, Audit, Admin Tools), 5 Canonical Batch Imports (Plantilla, HR Emploc, Vacancy, Mika, Payroll) with 72h Rollback Governance, QA Simulation Engine (Atomic Sandbox Isolation with 0 live pollution), Role Impersonation (Acting Sessions), Permission Matrix Overrides with Bulk Reset, and Audit Activity Feed Lockdown. → "More Module" above.
- **2026-11-23 — `ohm#approvals-clearinghouse-and-routing-arch`** — Codified Approvals Module Eleven Functional Review Queues, Option 1 Requisition Routing (New Doors vs. Headcount Quota), ADR-003 Unified Roving Requisitions with Atomic Store Provisioning, Account Group Transfer Direct Admin Execution Policy, and Dedicated Requester Tracking Feed (/my-requests). → "HC Request & Coverage Semantics" above.
- **2026-11-23 — `ohm#dashboard-cencom-command-arch`** — Codified Executive Dashboard Command Center Architecture (/dashboard), CENCOM Central Command 5 Operational Tabs (/cencom), Authoritative Database Pass-Through Principle ("Database Computes, UI Renders"), MFR Health Threshold Scale, and Whole-Number Headcount KPI Rounding Contract (Migration 20262606000147). → "Dashboard & CENCOM" above.
