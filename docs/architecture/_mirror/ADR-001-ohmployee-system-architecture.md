<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-001. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/.ai/architecture_locks/ADR-001-ohmployee-system-architecture.md
source_commit: 390162b 2026-11-14T17:52:07+08:00
source_sha256: 30ff17e68425cd93a1b16b71bc103dda440f1cfecc18e7ca736c3395c4b5b988
synced_at: 2026-11-14T09:52:18.705Z
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

### Rule 2 — Hired HC Source

**Module scope:** Cross-module derived read. Source of truth lives in Plantilla; consumed by Vacancy, Dashboard, CENCOM, HR Emploc, and Onboarding.

`hired_count` derives STRICTLY from `plantilla.status = 'Active'` per VCode, filtered to active occupants only. No other source (applicant status, `hc_filled`, view fallbacks) may contribute to a Hired count. A Confirmed-Onboard applicant not yet in Plantilla counts nowhere — its slot sits `hr_processing`, not hired. When an employee is tagged Inactive (Resigned, AWOL, Terminated, Endo, Backout, etc.), `hired_count` drops immediately and the slot/vacancy reopens.

### Rule 3 — Lifecycle Sync

**Module scope:** Cross-module (Applicant / Vacancy / Plantilla / HR Emploc / Onboarding).

An applicant/vacancy status change (hire, backout, separation) must never leave its corresponding `plantilla_slots` row dangling. This is enforced as a backstop, not just a convention: a deferred CONSTRAINT TRIGGER (`trg_applicant_terminal_slot_sync`) on `applicants` fails the transaction at COMMIT if a move into Backout/Withdrawn/Separated leaves its slot unclaimed (`hr_processing`) or still occupied/filled by that applicant's plantilla row.

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
4. Coverage Weight and HC Share are deprecated.
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

### Deprecated Concepts

Coverage Weight and HC Share are deprecated and must not be used for new logic, calculations, dashboards, requests, or workflow decisions. Do not derive HC from Coverage Weight, HC Share, store count, or store footprint.

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

---

## HR Emploc Import

### Core Lifecycle

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

---

## Vacancy

### Rule 4 — Classification Priority

**Module scope:** Vacancy (authoritative implementation). Dashboard and CENCOM are downstream consumers.

**Authoritative rule (do not revert without equally explicit re-verification — this exact rule has flipped 7 times in this repo's history; see `docs/state/vacancy_state.md` §`ohm#8j4q1r6z`):**

> Open tab: visible iff `(hc_needed - hired_count - pipeline_count - hr_processing_count) > 0`, shown with that value. Pipeline tab: visible iff `pipeline_count > 0`, independent of Open. A vacancy may appear in Open, Pipeline, both, or neither.

Closure still takes unconditional priority over both — a vacancy with a closed slot or pending closure request never shows in Open or Pipeline.

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
- `fn_archive_hired_vacancies` — archives stale hired vacancies (Confirmed-Onboard ≥ 7 days)

**Informational, not an action item:** 3 of the 6 (`fn_qa_archive_operational_data_reset`, `archive_vacancy_record`, `fn_archive_hired_vacancies`) are currently unwired from any Flutter call site (confirmed via `.dart` source grep — only referenced in the auto-generated `database_types.ts` type file, never invoked). Flagged for a future cleanup/consolidation decision; not resolved here.

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

---

## More Module

Rule 1 and Rule 6 compliance: More Module's bulk archival and payroll-adjacent RPCs (`fn_archive_*`, `fn_qa_*`, `fn_rollback_archive_batch`) are the explicit, justified direct-writer carve-out named in Rule 1 above — bulk archival is not a lifecycle transition, so these functions may write `plantilla_slots.slot_status` directly rather than through `fn_set_slot_status`. They must still never write to a denormalized counter column (`hc_filled` etc.) per Rule 6 — only to the primary domain tables the archive operation targets.

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
