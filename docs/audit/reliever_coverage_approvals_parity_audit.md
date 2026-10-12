# Reliever Endorsements & Coverage Requests Approvals Parity Audit

**Prompt ID:** `ohm#w39r730d`  
**Date:** 2026-10-12  
**Auditor:** Antigravity (Deep Technical Architecture & Parity Audit Pass)  
**Target Codebases:**
- **Mobile Source of Truth:** `D:\Projects\OHMployee`
  - `lib/features/coverage/coverage_request_screen.dart`
  - `lib/features/plantilla/moses_hq_pool_screen.dart`
  - `lib/data/services/workforce_pool_service.dart`
  - `lib/data/services/coverage_request_service.dart`
  - `lib/data/repositories/coverage_request_repository.dart`
  - `supabase/migrations/20261215000003_drop_old_request_reliever_coverage_overload.sql`
  - `supabase/migrations/20261215000004_fix_approve_reliever_coverage_request.sql`
  - `supabase/migrations/20261021000000_coverage_request_foundation.sql`
  - `supabase/migrations/20261022000000_coverage_request_rpc_contracts.sql`
  - `supabase/migrations/20261023000000_coverage_request_approval_engine.sql`
  - `supabase/migrations/20260520012857_remote_schema.sql` (views & initial schema)
- **Web Target:** `D:\Projects\ohmployee-web`
  - `src/components/approvals/ActiveQueueReviewPane.tsx`
  - `src/components/approvals/RequestCategoryNavigation.tsx`
  - `src/lib/queries/requests.ts`

---

## 1. Executive Summary & Domain Disambiguation

Our in-depth audit of both codebases clarifies a critical architectural distinction between **Reliever Endorsements (Workforce Assignment Requests)** and **Coverage Requests (Roving Coverage Structure)**:

### 1.1 Reliever Endorsements (`workforce_assignment_requests` / `v_workforce_assignment_request_queue`)
- **Operational Purpose:** Requesting an available reliever from a workforce pool (MOSES HQ Pool, Commando, etc.) to temporarily deploy to a specific store for a designated date window (`start_date` to `end_date`), covering an on-leave employee or an open vacancy.
- **Requester:** Operations / Coordinators / Encoders.
- **Approver:** Data Team / Head Admin / Super Admin (Role level $\ge 30$, or users with full access).
- **Approval Outcome:** Converts the pending request into an active record in `workforce_assignments` with status `Approved`, binding the employee to the store.
- **Rejection Outcome:** Updates `workforce_assignment_requests.status` to `Rejected` with `rejection_reason`.

### 1.2 Coverage Requests (`coverage_requests`)
- **Operational Purpose:** CENCOM roving group structural governance. Manages roving cluster operations across multiple stores:
  - `create_coverage_group`: Initialize a new roving cluster.
  - `add_store`: Attach a store to an existing roving coverage group.
  - `remove_store`: Detach a store from a coverage group.
  - `merge_coverage_groups`: Merge source group into destination group.
  - `dissolve_coverage_group`: Dissolve group and return stores/employees to single-store home allocations.
- **Requester:** Encoders / Coordinators / Ops.
- **Approver:** Head Admin / Super Admin (`i_have_full_access()`).
- **Approval Outcome:** Generates simulation/conflict review artifacts via `_coverage_request_review_artifacts` and transitions status to `approved`.

### 1.3 Current Web State vs. Mobile State
| Feature Aspect | Mobile (`OHMployee`) | Web (`ohmployee-web`) | Parity Status |
| :--- | :--- | :--- | :--- |
| **Category in Navigation** | Separate tabs/screens: `Coverage Requests` screen & `MOSES HQ Pool` requests tab | Registered as Category 3 (`coverage`) pointing to table `coverage_requests` | ⚠️ Partially mapped; Reliever endorsements not explicitly integrated |
| **Pending Count Query** | Live queries on `coverage_requests` & `v_workforce_assignment_request_queue` | Counts `coverage_requests` where status is `pending` or `draft` (`requests.ts` L166-171) | ⚠️ Missing reliever queue counts |
| **Active Queue Review Pane** | Full review cards with Approve/Reject buttons, dialogs, and impact simulation | Rendered as fallback placeholder card linking to `/cencom` (L1195-1234) | ❌ Gap: No in-place review card |
| **Approval / Rejection RPCs** | Invokes `approve_reliever_coverage_request`, `reject_reliever_coverage_request`, `approve_coverage_request`, `reject_coverage_request` | RPCs completely unwired in web `requests.ts` | ❌ Gap: Zero mutation hooks |

---

## 2. Review Card Layout & Metadata Inventory

### 2.1 Reliever Endorsement Request (`_RequestSlaCard` in `moses_hq_pool_screen.dart`)
In mobile, the reliever request card presents the following critical fields:

| Field Name | Source Column | Display Format / UI Presentation |
| :--- | :--- | :--- |
| **Reliever Name** | `employee_name` | Full formatted name (e.g., `formatPlantillaEmployeeCardName(request.employeeName)`) |
| **Employee Number** | `employee_number` | Subtitle badge / mono text (e.g. `2024-00123`) |
| **Source Pool** | `pool_type` / `pool_type_name` | Badge chip (e.g., `MOSES HQ Pool`, `Commando`, `HQ Backup`) |
| **Assigned Store & Account** | `requested_store`, `requested_account` | Location tag: `[Account Name] / [Store Name]` (with store branch if available) |
| **Assigned Group** | `requested_group` | Group pill (e.g., `Group 1 - Banko`) |
| **Coverage Period** | `start_date`, `end_date` | Date range string: `MMM d, yyyy - MMM d, yyyy` + Duration days `(X days)` |
| **Requested Position** | `requested_position` | Title-cased position name |
| **Priority** | `priority` | Priority badge with color coding: `Urgent` (Red), `High` (Orange), `Normal` (Slate) |
| **Purpose / Reason** | `reason` | Blockquote / multi-line text container |
| **Requester** | `requested_by` | Requester profile name |
| **Request Date & Age** | `created_at`, `request_age_days` | Relative date (`Xd ago`) + SLA Escalation Level (`Normal`, `Notify Head Admin`, `Notify OM`, `Notify Super Admin`) |
| **Approval Status** | `status` | Status badge (`Pending`, `Approved`, `Rejected`, `Withdrawn`) |

#### Actions:
- **Approve Button:** Triggers modal confirmation `"Approve coverage request for [Employee]? A workforce assignment will be created."`, calling `approve_reliever_coverage_request(p_request_id, p_notes)`.
- **Reject Button:** Triggers rejection reason prompt modal, calling `reject_reliever_coverage_request(p_request_id, p_reason)`.

---

### 2.2 Roving Coverage Request (`_CoverageRequestCard` & Detail in `coverage_request_screen.dart`)
In mobile, the structural coverage request cards display:

| Field Name | Source Column / Expression | Display Format / UI Presentation |
| :--- | :--- | :--- |
| **Request Type** | `request_type` | Humanized label: `Create Coverage Group`, `Add Store(s)`, `Remove Store(s)`, `Merge Groups`, `Dissolve Group` |
| **Status** | `status` | Status badge (`draft`, `pending`, `approved`, `rejected`, `cancelled`) |
| **Account Name** | `account_id` $\to$ `accounts.account_name` | Bold Account Name |
| **Target Coverage Group** | `target_coverage_group_id` | Group code (e.g., `CG-BKO-01`) and group name |
| **Stores to Cover / Affected** | `payload -> store_ids` | List of store badges with store name and branch |
| **Reason / Purpose** | `reason` | Multi-line text block |
| **Requester Audit** | `requested_by_name`, `requested_by_role`, `requested_at` | Avatar / user name, role badge, timestamp |
| **Simulation Summary** | `execution_summary -> simulation_summary` | Pre-review impacted stores, active plantilla affected, vacancies, and pipelines |
| **Conflict Report** | `execution_summary -> conflict_report` | Warnings for store overlaps or multi-group assignments |

#### Actions:
- **Approve Button:** Calls `approve_coverage_request(p_coverage_request_id, p_reviewer_remarks)`.
- **Reject Button:** Calls `reject_coverage_request(p_coverage_request_id, p_rejection_reason, p_reviewer_remarks)`.

---

## 3. Database Schema & RPC Signatures Mapping

### 3.1 Reliever Endorsements (`workforce_assignment_requests`)

#### Primary Table: `public.workforce_assignment_requests`
```sql
CREATE TABLE public.workforce_assignment_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  employee_id uuid NOT NULL REFERENCES public.plantilla(id),
  pool_type_id uuid REFERENCES public.workforce_pool_types(id),
  requested_group_id uuid REFERENCES public.groups(id),
  requested_account_id uuid REFERENCES public.accounts(id),
  requested_store_id uuid REFERENCES public.stores(id),
  requested_position text,
  priority text NOT NULL DEFAULT 'Normal',
  start_date date NOT NULL,
  end_date date NOT NULL,
  reason text,
  status text NOT NULL DEFAULT 'Pending',
  requested_by text,
  requested_by_id uuid REFERENCES auth.users(id),
  reviewed_by text,
  reviewed_at timestamptz,
  rejection_reason text,
  converted_assignment_id uuid REFERENCES public.workforce_assignments(id),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
```

#### Primary View: `public.v_workforce_assignment_request_queue`
```sql
SELECT 
  war.id AS request_id,
  war.employee_id,
  p.employee_no AS employee_number,
  p.employee_name,
  wpt.name AS pool_type,
  a.account_name AS requested_account,
  s.store_name AS requested_store,
  g.group_name AS requested_group,
  war.priority,
  war.start_date,
  war.end_date,
  war.reason,
  war.status,
  war.requested_by,
  war.rejection_reason,
  war.reviewed_by,
  war.reviewed_at,
  war.converted_assignment_id,
  war.created_at,
  (EXTRACT(day FROM (now() - war.created_at)))::integer AS request_age_days,
  CASE ... END AS escalation_level,
  CASE ... END AS notify_target_role
FROM public.workforce_assignment_requests war
JOIN public.plantilla p ON p.id = war.employee_id
JOIN public.workforce_pool_types wpt ON wpt.id = war.pool_type_id
LEFT JOIN public.accounts a ON a.id = war.requested_account_id
LEFT JOIN public.stores s ON s.id = war.requested_store_id
LEFT JOIN public.groups g ON g.id = war.requested_group_id;
```

#### RPC 1: `approve_reliever_coverage_request`
- **Migration:** `20261215000004_fix_approve_reliever_coverage_request.sql`
- **Signature:**
  ```sql
  FUNCTION public.approve_reliever_coverage_request(
    p_request_id uuid,
    p_assigned_employee_id uuid DEFAULT NULL::uuid,
    p_notes text DEFAULT NULL::text
  )
  RETURNS TABLE(request_id uuid, assignment_id uuid, status text, message text)
  ```
- **RBAC Requirement:** Role level 100 (Super Admin), 90 (Head Admin), 30 (Data Team), or `i_have_full_access()`.
- **Side Effects:**
  1. Validates employee is active and in workforce pool.
  2. Inserts new record into `workforce_assignments` with status `'Approved'`.
  3. Updates `workforce_assignment_requests` setting status to `'Approved'`, `converted_assignment_id`, `reviewed_by`, and `reviewed_at`.
  4. Returns new assignment ID.

#### RPC 2: `reject_reliever_coverage_request`
- **Migration:** `20260520012857_remote_schema.sql` (L14433)
- **Signature:**
  ```sql
  FUNCTION public.reject_reliever_coverage_request(
    p_request_id uuid,
    p_rejection_reason text
  )
  RETURNS void
  ```
- **RBAC Requirement:** Role level 100, 90, 30, or `i_have_full_access()`.
- **Side Effects:**
  1. Validates request is `'Pending'`.
  2. Updates `workforce_assignment_requests` setting `status = 'Rejected'`, `rejection_reason = p_rejection_reason`, `reviewed_by = get_my_full_name()`, `reviewed_at = now()`.

---

### 3.2 Roving Coverage Requests (`coverage_requests`)

#### Primary Table: `public.coverage_requests`
- **Migration:** `20261021000000_coverage_request_foundation.sql`
- **Key Columns:** `id`, `request_type`, `status`, `account_id`, `position_id`, `employment_type`, `target_coverage_group_id`, `source_coverage_group_id`, `destination_coverage_group_id`, `payload` (JSONB), `reason`, `requested_by`, `requested_by_name`, `requested_at`, `approved_by`, `approved_at`, `rejected_by`, `rejection_reason`, `reviewer_remarks`, `execution_summary` (JSONB).

#### RPC 3: `review_coverage_request` / `approve_coverage_request` / `reject_coverage_request`
- **Migration:** `20261023000000_coverage_request_approval_engine.sql`
- **Signatures:**
  ```sql
  FUNCTION public.approve_coverage_request(
    p_coverage_request_id uuid,
    p_reviewer_remarks text DEFAULT NULL::text
  )
  RETURNS jsonb

  FUNCTION public.reject_coverage_request(
    p_coverage_request_id uuid,
    p_rejection_reason text,
    p_reviewer_remarks text DEFAULT NULL::text
  )
  RETURNS jsonb

  FUNCTION public.review_coverage_request(
    p_coverage_request_id uuid,
    p_decision text,
    p_reviewer_remarks text DEFAULT NULL::text,
    p_rejection_reason text DEFAULT NULL::text
  )
  RETURNS jsonb
  ```
- **RBAC Requirement:** `i_have_full_access()` (Head Admin or Super Admin).
- **Side Effects:** Generates simulation/conflict JSONB summaries, updates status to `'approved'` or `'rejected'`, logs to `coverage_request_history`.

---

## 4. Parity Gap Analysis

### 4.1 Categorization Strategy Gap
In `ohmployee-web`, the navigation item is currently named `"Coverage"` with key `"coverage"`.
However, users commonly refer to temporary reliever deployment requests as **"Reliever Endorsements"** or **"Reliever Requests"**, while CENCOM group operations are referred to as **"Roving Coverage"**.
- In the mobile app:
  - Reliever endorsement approvals live inside **MOSES HQ Pool** (`moses_hq_pool_screen.dart` tab `Requests`).
  - Coverage group requests live inside **Coverage Requests** (`coverage_request_screen.dart`).
- In the web approvals center:
  - Category `coverage` currently targets `coverage_requests` only.
  - Reliever endorsement requests in `v_workforce_assignment_request_queue` are completely unreachable from the Approvals Center.

**Recommended Solution:**
Unify Category 3 (`coverage`) into **"Reliever & Coverage Requests"** (or keep the key `coverage` with a segmented tab / filter inside the review pane: **Reliever Endorsements** vs. **Roving Coverage Groups**), or introduce `reliever_endorsements` as an explicit dedicated queue category if 9 categories are preferred. Given the prompt specifies *"specifically category reliever_endorsements"*, we should support both:
1. Support `reliever_endorsements` or a dual-tab toggle in `coverage` review pane to inspect both `workforce_assignment_requests` and `coverage_requests`.

### 4.2 Data Query & Hook Gaps
In `src/lib/queries/requests.ts`:
1. **Missing Query Hook:** No hook exists to query `v_workforce_assignment_request_queue` or pending `coverage_requests`.
2. **Missing Mutation Hooks:**
   - `useApproveRelieverCoverageRequest()` $\to$ calls `approve_reliever_coverage_request`
   - `useRejectRelieverCoverageRequest()` $\to$ calls `reject_reliever_coverage_request`
   - `useApproveCoverageRequest()` $\to$ calls `approve_coverage_request`
   - `useRejectCoverageRequest()` $\to$ calls `reject_coverage_request`

### 4.3 Review Card UI Gap
In `src/components/approvals/`:
- `RelieverCoverageApprovalCard.tsx` does not exist.
- `ActiveQueueReviewPane.tsx` drops into the fallback info banner with a link to `/cencom` instead of rendering live review cards.

---

## 5. Implementation Roadmap (1-to-1 Parity Plan)

### Phase 1: Query & Mutation Layer (`src/lib/queries/requests.ts`)
1. **Define Types:**
   - `RelieverEndorsementItem`: mapped from `v_workforce_assignment_request_queue`.
   - `CoverageGroupRequestItem`: mapped from `coverage_requests` with joined account and store names.
2. **Implement Fetch Hooks:**
   - `usePendingRelieverEndorsements()`: queries `v_workforce_assignment_request_queue` where `status IN ('Pending', 'For Review')` ordered by `request_age_days DESC, created_at ASC`.
   - `usePendingCoverageRequests()`: queries `coverage_requests` where `status = 'pending'` ordered by `created_at DESC`.
3. **Implement Mutation Hooks:**
   - `useApproveRelieverCoverage()`: calls RPC `approve_reliever_coverage_request`.
   - `useRejectRelieverCoverage()`: calls RPC `reject_reliever_coverage_request`.
   - `useApproveCoverageGroupRequest()`: calls RPC `approve_coverage_request`.
   - `useRejectCoverageGroupRequest()`: calls RPC `reject_coverage_request`.
4. **Update `useRequestCategoryCounts()`:**
   - Aggregate counts for `v_workforce_assignment_request_queue` (and `coverage_requests`) so the badge reflects live pending items.

### Phase 2: In-Place Review Card (`src/components/approvals/RelieverCoverageApprovalCard.tsx`)
Create a high-density, accessible review card matching the UX patterns of `StoreTransferApprovalCard.tsx` and `ApplicantMovementApprovalCard.tsx`:
1. **Card Header:**
   - Employee Name, Employee No, Pool Type chip (`MOSES HQ Pool`, `Commando`).
   - Priority badge (Color-coded: Red for High/Urgent, Slate for Normal).
   - SLA / Age badge (`Xd ago`, Escalation Level).
2. **Routing & Scope Section:**
   - Assigned Account & Store / Branch.
   - Coverage Date Range (`start_date` to `end_date`) and computed duration in days.
   - Requested Position & Requester details.
3. **Reason & Notes Section:**
   - Requester reason callout container.
4. **Action Controls:**
   - **Approve Button:** Opens confirmation modal with optional review notes.
   - **Reject Button:** Opens rejection dialog requiring a mandatory rejection reason.
   - Role gates: Enabled for Data Team, Head Admin, Super Admin (Role level $\ge 30$).

### Phase 3: Active Queue Review Pane Wiring (`src/components/approvals/ActiveQueueReviewPane.tsx`)
1. Integrate `usePendingRelieverEndorsements()` and `usePendingCoverageRequests()`.
2. Replace the static fallback banner for `coverage` with:
   - Filter / Segmented toggle: **Reliever Endorsements** (default) vs. **Roving Coverage**.
   - Search input supporting search by employee name, employee number, store name, or account.
   - Priority filter (`All`, `Urgent`, `High`, `Normal`).
   - Data states: Loading skeleton, Error retry, Empty state with search query feedback.
   - Map items to `RelieverCoverageApprovalCard`.

---

## 6. Verification Checklist

- [x] Review mobile codebase: `lib/features/coverage/coverage_request_screen.dart`, `moses_hq_pool_screen.dart`, `workforce_pool_service.dart`, `coverage_request_service.dart`.
- [x] Trace schema structures: `workforce_assignment_requests`, `v_workforce_assignment_request_queue`, `coverage_requests`.
- [x] Map exact RPC signatures: `approve_reliever_coverage_request`, `reject_reliever_coverage_request`, `approve_coverage_request`, `reject_coverage_request`, `review_coverage_request`.
- [x] Audit web implementation: `ActiveQueueReviewPane.tsx`, `RequestCategoryNavigation.tsx`, `requests.ts`.
- [x] Generate comprehensive parity report at `docs/audit/reliever_coverage_approvals_parity_audit.md`.
