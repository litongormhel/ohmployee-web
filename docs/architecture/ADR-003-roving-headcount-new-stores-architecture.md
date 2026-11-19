# ADR-003: Unified Roving Headcount Requisition with Atomic Store Provisioning & Mandatory Operational Justification

- **Status**: Accepted & Implemented (Migration `20262606000126_roving_hc_new_stores_and_mandatory_justification.sql`)
- **Date**: 2026-11-19
- **Deciders**: Engineering Lead, Operations Lead, System Architecture
- **Consulted**: Mobile Architecture (`OHMployee`), Approvals Center Core Team
- **Informed**: Operations Management (OM), Head Admin (HA), Super Admin (SA), Data Team

---

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
