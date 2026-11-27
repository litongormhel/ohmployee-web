<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-Approvals. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/04_approvals_requisitions.md
source_commit: 08ac81e 2026-11-25T19:31:17+08:00
source_sha256: 6c887659938127abd1bd2dff631975da760546993daafa300e913c71b1ec677f
synced_at: 2026-11-27T01:40:31.645Z
-->
# Approvals & Headcount Requisitions Architecture

- **Status:** ACCEPTED & LOCKED
- **Scope:** Stationary vs. Roving Semantics, Eleven Functional Review Queues, Option 1 Requisition Routing, Unified Roving with Atomic Store Provisioning (ADR-003), Account Group Transfers, and /my-requests.

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

---

## Supplementary Specification: ADR-003 Unified Roving Requisitions & Atomic Store Provisioning

## 1. Context & Problem Statement

In the OHMployee Headcount Requisition workflow (`submit_headcount_request`), staffing demands are divided into two primary workforce deployment paradigms:
1. **Stationary Workforce**: A dedicated employee assigned 1:1 to a single store outlet.
2. **Roving Workforce**: An employee who rotates across a cluster of 2 to 20 store outlets under a single Coverage Group (`CGCODE`), with auto-computed roving capacity fractions ($1/N$).

### Current Operational Bottleneck
When an operational account prepares for upcoming store openings (e.g., opening 3 new stores simultaneously: Store 1, Store 2, and Store 3):
- **Stationary Limitation**: The stationary workflow allows linking a single new store via `NewStoreRequestModal`. However, using stationary for a roving role forces the user to submit **3 separate headcount requisitions**, generating 3 separate headcount quotas instead of 1 shared roving personnel.
- **Roving Store Picker Limitation**: The current roving workflow **strictly restricts store selection to existing, active stores** already registered in `public.stores`. There is no mechanism to introduce new, unlisted, or opening stores into a roving cluster.
- **Geographic Dispersion**: Roving stores often span **different cities or municipalities** (e.g., Quezon City, Pasig, Mandaluyong) or different provinces within the same geographic cluster (e.g., Cavite + Laguna). The current UI filter structure binds store selection to a single Province/City dropdown, causing friction when searching across multiple cities.
- **Optional Operational Justification**: In `RequestHeadcountModal.tsx` and `submit_headcount_request`, business justification was only mandatory for "HC Reduction". For all other request types ("Additional Headcount", "Replacement", "Reliever", "Commando"), justification was optional, leading to vague or unreviewed requisition submissions.

---

## 2. Decision Drivers

1. **Unified Single-Turn Requisition ("1 time lang")**: Operations users must be able to request roving headcount covering 2–20 stores (whether existing, newly opening, or a mix of both) in a single requisition submission.
2. **Atomic Store Provisioning & Zero Database Pollution**: Unapproved store openings must **never pollute** `public.stores`. If a roving headcount request is rejected, cancelled, or withdrawn, no draft stores must remain in `public.stores`. Store creation must occur atomically upon requisition approval.
3. **ADR-001 Island Group Invariant Preservation**: A Coverage Group must never span multiple island groups (Luzon, Visayas, Mindanao). Multi-city and multi-province roving within the same island group is fully valid and encouraged.
4. **Transparent Approver Visibility**: Approvers in the Approvals Center (`/approvals`) must clearly distinguish between existing registered stores and newly proposed store openings, with geographic details (City, Province, Island Group) visible at a glance.
5. **Universal Justification Requirement**: Operational Justification must be strictly mandatory ($\ge 20$ characters) across all request types and platforms (Web UI and backend RPC).

---

## 3. Considered Options

### Option 1: Unified Single Requisition with Atomic Store Provisioning on Approval (SELECTED)
- Users can add existing stores from search and create new store definitions (Store Name, Province, City) directly in the Roving store selector.
- Submitting creates 1 `headcount_requests` record with all store associations in `public.hc_request_stores`. New stores are flagged as `is_new_store = true` with null `store_id`.
- On approval, the backend RPC atomically:
  1. Inserts the new stores into `public.stores`.
  2. Updates `hc_request_stores.store_id` with the newly generated store UUIDs.
  3. Creates the Coverage Group (`CGCODE`), individual store VCodes, Vacancies, and Plantilla Slots.
  4. Records `new_store_requests` entries for audit trail parity.
- If rejected, the request is marked `rejected`; zero stores are inserted into `public.stores`.

### Option 2: Pre-Register Inactive Stores
- Immediately insert new stores into `public.stores` with `status = 'pending_activation'`.
- *Why rejected*: Pollutes `public.stores` with orphaned stores if the headcount request is rejected or abandoned. Complicates active store queries and store deduplication guards.

### Option 3: Separate Batch New Store Request (NSR) First
- Require the user to submit 3 separate New Store Requests first, wait for Data Team / Admin approval, and only then submit the Roving Headcount Request.
- *Why rejected*: Violates the user's explicit operational requirement for a single unified submission ("1 time lang") and multiplies approval turnaround times.

---

## 4. Architectural Specifications & Database Contracts

### 4.1 Schema Evolution: `public.hc_request_stores`

`public.hc_request_stores` is upgraded to support both existing stores (`store_id` foreign key) and new store proposals (`is_new_store = true`):

```sql
-- Migration: Upgrade hc_request_stores for new store draft support
ALTER TABLE public.hc_request_stores
  ALTER COLUMN store_id DROP NOT NULL;

ALTER TABLE public.hc_request_stores
  ADD COLUMN IF NOT EXISTS is_new_store boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS store_name text NULL,
  ADD COLUMN IF NOT EXISTS area_province text NULL,
  ADD COLUMN IF NOT EXISTS area_city text NULL,
  ADD COLUMN IF NOT EXISTS island_group text NULL,
  ADD COLUMN IF NOT EXISTS created_store_id uuid NULL REFERENCES public.stores(id);

-- Enforce integrity: either existing store_id OR new store metadata must be present
ALTER TABLE public.hc_request_stores
  ADD CONSTRAINT chk_hc_request_stores_target CHECK (
    (is_new_store = false AND store_id IS NOT NULL) OR
    (is_new_store = true AND store_name IS NOT NULL AND area_province IS NOT NULL AND area_city IS NOT NULL)
  );
```

### 4.2 Backend RPC Upgrade: `public.submit_headcount_request(p_input jsonb)`

1. **Mandatory Operational Justification Guard**:
   ```sql
   v_reason := trim(coalesce(p_input->>'reason', ''));
   IF length(v_reason) < 20 THEN
     RETURN jsonb_build_object(
       'ok', false,
       'error', 'justification_required',
       'message', 'Operational justification is mandatory (minimum 20 characters).'
     );
   END IF;
   ```

2. **Polymorphic Store Array Parsing**:
   `p_input->'stores'` (or `p_input->'store_ids'`) accepts an array of store objects or UUIDs:
   - For existing stores: `{ "store_id": "uuid" }` or `"uuid"`.
   - For new stores: `{ "store_name": "Store 1", "area_province": "Rizal", "area_city": "Antipolo", "is_new_store": true }`.

3. **Multi-City & Island Group Validation**:
   - The backend validates all stores (existing and new).
   - Island group is resolved for each store using `public.ref_provinces` or `public.ref_cities`.
   - **Hard Block**: If stores span more than 1 island group (e.g. Luzon + Visayas), the transaction aborts with `island_group_span_violation`.
   - Stores in different cities/provinces within the same island group are accepted.

### 4.3 Backend Approval RPC: `public.create_plantilla_slot_from_request(p_request_id uuid)`

When an authorized approver approves the request:
1. **Phase 1: Atomic Store Provisioning**:
   ```sql
   FOR v_hc_store_row IN
     SELECT * FROM public.hc_request_stores
     WHERE request_id = p_request_id AND is_new_store = true AND store_id IS NULL
   LOOP
     INSERT INTO public.stores (
       account_id, group_id, store_name,
       area_city, province, is_active, status,
       created_by, approved_by, approved_at
     ) VALUES (
       v_req.account_id, v_group_id, v_hc_store_row.store_name,
       v_hc_store_row.area_city, v_hc_store_row.area_province,
       true, 'active',
       v_req.requested_by_user_id, v_reviewer_id, now()
     ) RETURNING id INTO v_generated_store_id;

     UPDATE public.hc_request_stores
     SET store_id = v_generated_store_id,
         created_store_id = v_generated_store_id
     WHERE id = v_hc_store_row.id;
   END LOOP;
   ```
2. **Phase 2: Roving Coverage Group & VCode Generation**:
   - Creates the Coverage Group (`CGCODE`).
   - For each store in `hc_request_stores`, assigns a VCode, generates Vacancies, and sets up Plantilla Slots.

---

## 5. Frontend UI/UX Specifications

### 5.1 Request Headcount Modal (`RequestHeadcountModal.tsx`)
1. **Roving Store Selector Enhancements**:
   - **Multi-City Search**: Search bar searches across all stores under the account without restricting to a single city.
   - **"+ Add Unlisted Store" Action**: Accessible at any time and prominently displayed when a store search returns no results.
   - **Quick Add Unlisted Store Sub-Form**:
     - Store Name (required)
     - Province (required dropdown populated from `useRefProvinces`)
     - City / Municipality (required dropdown populated from `useRefCities(province)`)
     - Auto-derived Island Group badge.
   - **Selected Store Chips**:
     - Existing stores: Standard store chip with Island Group indicator.
     - New stores: Highlighted with a `Sparkles` / `New Store` badge and City/Province detail.
   - **Validation Rules**:
     - Minimum 2 stores, maximum 20 stores.
     - Real-time client-side Island Group mismatch alert.
     - Duplicate store name detection within the account.

2. **Mandatory Operational Justification**:
   - Textarea labelled `Operational Justification` with `<RequiredAsterisk />`.
   - Character counter displaying `X / 20 characters minimum`.
   - Validation blocks submission if `trimmed.length < 20`.

### 5.2 Approvals Center (`/approvals`)
- Headcount Request review cards (`HeadcountApprovalCard.tsx` / `ActiveQueueReviewPane.tsx`) fetch store breakdown via `get_hc_request_stores(request_id)`.
- Roving store list displays:
  - Existing stores: `Store Name • City, Province (Existing)`
  - New stores: `Store Name • City, Province (New Store — Will be created on approval)`
- Approving triggers the upgraded `create_plantilla_slot_from_request` RPC atomically.

---

## 6. ADR Invariants & Safety Guarantees

1. **Zero Premature Stores**: Unapproved new stores exist ONLY inside `hc_request_stores`. No rows are inserted into `public.stores` until formal approval.
2. **Atomic Rollback on Failure**: If any store creation or VCode generation fails during approval, the entire database transaction rolls back.
3. **Island Group Immutability**: No roving coverage group may ever link stores from different island groups.
4. **Backward Compatibility**: Existing mobile app versions submitting standard `store_ids: [uuid, uuid]` continue to work without modification.

---

## 7. Migration & Rollout Plan

1. **Step 1: Codify ADR-003** (This document).
2. **Step 2: Database Migration**:
   - Generate auto-numbered migration `npm run db:new roving_hc_new_stores_and_mandatory_justification`.
   - Upgrade `hc_request_stores` schema.
   - Update `submit_headcount_request` (polymorphic store ingestion + 20-char justification guard).
   - Update `create_plantilla_slot_from_request` (atomic store provisioning).
   - Update `get_hc_request_stores` (return `is_new_store`, `area_province`, `area_city`).
   - Validate via `npm run check:sql` and staging push.
3. **Step 3: Web Client Implementation**:
   - Enhance `RequestHeadcountModal.tsx` with unlisted store quick-add form and multi-city support.
   - Enforce mandatory $\ge 20$-char justification.
   - Update `src/lib/queries/requests.ts` types and payload builders.
   - Update Approvals Center review pane.
4. **Step 4: Automated Testing & Verification**:
   - Add unit tests verifying validation and payload formatting.
   - Verify `npm test`, `npm run lint`, and `npm run build`.
