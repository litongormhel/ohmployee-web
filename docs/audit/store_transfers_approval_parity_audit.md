# Store & Account Group Transfers Approval Parity Audit

**Prompt ID:** `ohm#w37s528b`  
**Date:** 2026-10-12  
**Auditor:** Antigravity (Deep Technical Architecture & Parity Audit Pass)  
**Target Codebases:**
- Mobile Source of Truth: `D:\Projects\OHMployee`
  - `lib/features/account_group_transfer/account_group_transfer_screens.dart`
  - `lib/data/services/account_group_transfer_service.dart`
  - `lib/features/user_management/global_store_transfer_screen.dart`
  - `lib/data/services/global_store_transfer_service.dart`
  - `lib/features/transfer/transfer_screens.dart`
  - `supabase/migrations/20261227000000_account_group_transfer_workflow.sql`
  - `supabase/migrations/20260520012857_remote_schema.sql` (employee transfers & views)
- Web Target: `D:\Projects\ohmployee-web`
  - `src/components/approvals/ActiveQueueReviewPane.tsx`
  - `src/lib/queries/requests.ts`
  - `src/app/(dashboard)/approvals/page.tsx`
  - `src/components/approvals/RequestCategoryNavigation.tsx`

---

## 1. Executive Summary & Architecture Disambiguation

An in-depth inspection of both codebases reveals that "Transfers" within OHMployee encompasses three distinct operational concepts:

1. **Account Group Transfers (`account_group_transfers`):**
   - **Nature:** High-level organizational governance request. Shifts complete operational ownership of an entire account (`accounts.group_id` and transitively all associated stores `stores.group_id`) from one operational CENCOM group to another.
   - **Database Backing:** Complete, production-grade migration (`20261227000000_account_group_transfer_workflow.sql`) with real tables (`account_group_transfer_requests`, `account_group_transfer_request_history`), audit logging, automated notifications, and RPCs:
     - `simulate_account_group_transfer(p_account_id, p_to_group_id)`
     - `submit_account_group_transfer_request(p_account_id, p_to_group_id, p_reason)`
     - `approve_account_group_transfer_request(p_request_id)`
     - `reject_account_group_transfer_request(p_request_id, p_reason)`
   - **Current Web State:** Registered as Category 8 in `REQUEST_CATEGORIES` (`requests.ts`), counted via `useRequestCategoryCounts()`, but in `ActiveQueueReviewPane.tsx` it currently renders only a fallback placeholder info card directing the user to `/cencom` or `/approvals`.
   - **Target Parity Need:** Direct in-place approval queue with rich metric review cards, impact simulation snapshot display, and Super Admin execution actions.

2. **Global Store Transfers (`global_store_transfer`):**
   - **Nature:** Multi-employee bulk store-reassignment wizard designed for Head Admins and Super Admins. Moves active employees from a Source Group/Account/Store into vacant placeholder slots at a Target Group/Account/Store.
   - **Mobile Implementation:** `GlobalStoreTransferScreen` (in `lib/features/user_management/` placed under More -> Data Control).
   - **Database Backing:** Reads live groups (`get_plantilla_scope_menu`), accounts (`get_accounts_by_group`), employees (`v_plantilla_safe`), and stores (`stores`). However, submission, pending queue, and approval are documented as **MVP UI preview only** (see `docs/state/account_transfer_state.md` entries `OHM2026_0065` to `OHM2026_0072`). There are **no backend RPCs** named `approve_store_transfer` or `fn_simulate_store_transfer` in the database migrations for global store batch transfers.
   - **Current Web State:** Placed in More -> Data Control as a link to `/plantilla`. Not integrated into the `/approvals` center.

3. **Legacy Employee Transfers / Applicant Movement Requests (AMR):**
   - **Legacy Single Employee Transfers:** Backed by table `public.employee_transfers` (and view `public.transfer_requests`) with RPCs `public.approve_transfer_request(p_transfer_id, p_remarks)` and triggers on `public.employee_transfers`.
   - **Applicant Movement Requests (AMR):** Already modernized in web as Category 7 (`applicant_movement_requests`) with [`ApplicantMovementApprovalCard.tsx`](file:///d:/Projects/ohmployee-web/src/components/approvals/ApplicantMovementApprovalCard.tsx).

### Scope Focus of this Audit
To achieve 1-to-1 parity in the Approvals Center (`/approvals`), the web application must wire the pending approval queue for **Account Group Transfers** (`account_group_transfers`), and prepare the layout/card structure (`StoreTransferApprovalCard.tsx` / `AccountGroupTransferApprovalCard.tsx`) to support both account-level and store-level transfer reviews.

---

## 2. Transfer Review Card Layout & Metrics Comparison

### 2.1 Mobile Account Group Transfer Review Card Layout
In mobile (`AccountGroupTransferDetailScreen` and `_RequestCard` in `account_group_transfer_screens.dart`), the review UI displays:

1. **Header & Identifiers:**
   - Request Number (e.g. `AGT-2026-0001`) with copyable chip.
   - Status badge (`PENDING`, `APPROVED`, `REJECTED`) with distinct status colors (Amber, Green, Red).
   - Requested Date & Time (formatted as `MMM d, yyyy h:mma`, e.g. `Oct 12, 2026 12:00PM`).
   - Requester Name (`requested_by_name`).

2. **Account & Scope Routing:**
   - Account Name (`account_name`) in bold header typography.
   - Visual transfer path: `FROM GROUP` (`from_group_name (from_group_code)`) $\longrightarrow$ `TO GROUP` (`to_group_name (to_group_code)`).
   - Transfer Reason (max 10 characters as validated on submission, e.g. "Reorg", "Territory").

3. **Pre-computed Impact Simulation Metrics (`simulation_snapshot`):**
   The card renders a dedicated "Impact Simulation" panel displaying:
   - **Affected Stores:** `affected_stores` (count of active non-archived stores owned by the account).
   - **Affected Plantilla (Active):** `affected_plantilla_count` (active employees moving group ownership).
   - **Affected Vacancies (Open):** `affected_vacancies_count` (open vacancies whose ownership scope changes).
   - **Affected HR Emploc:** `affected_hr_emploc_count` (active HR Emploc assignment links).
   - **Visibility Shifts:**
     - `Users Gaining Visibility`: Group-scoped users (role level < 90) in the destination group gaining access.
     - `Users Losing Visibility`: Group-scoped users (role level < 90) in the source group losing access.

4. **Warnings & Conflict Checks:**
   - Simulation warnings banner (`warnings` array):
     - Same-group warning ("Account is already owned by the destination group.").
     - Coverage Group Warnings ("Coverage Group `[code]` contains stores that will move ownership groups after transfer.").
     - Cross-group Deployments ("Active reliever/commando deployment: `[name]` deployed at `[store]` (Home Group: `[group])`.").
   - When no warnings are present, displays green badge: `"No warnings detected. Ready for transfer."`
   - *Crucial Rule:* Warnings are informational only and do not block Super Admin approval.

5. **Reviewer Audit Trail (Post-Decision):**
   - Reviewed By name (`reviewed_by_name`).
   - Reviewed Date (`reviewed_at`).
   - Rejection Reason (`rejection_reason`) if rejected.

---

### 2.2 Global Store Transfer Layout (Mobile Screen Reference)
In `GlobalStoreTransferScreen`, the preview and review card models present:
- **Employee Info:** Display Name, Employee No, Current Store, Position, Current VCode.
- **Source Slot $\to$ Target Slot Mapping:**
  - Source: `VCode / Store / Position`
  - Target Vacant Slot: `VCode / Store / Position` (from candidate vacant slots where `source_headcount_request_id IS NOT NULL`).
- **Validation Status:** `Valid` vs `Blocked` (e.g., slot already taken).
- **Action Controls:** Segmented button (`Approve` / `Reject`) per employee row.

---

### 2.3 Proposed Web Card Layout: `StoreTransferApprovalCard.tsx`
For the web Approvals Center (`/approvals`), the card must follow the standard design language of existing web cards (`ApplicantMovementApprovalCard.tsx`, `NewStoreApprovalCard.tsx`, `DeactivationApprovalCard.tsx`):

```
+---------------------------------------------------------------------------------------------------+
| [Layers Icon]  AGT-2026-0004   [PENDING]                                            2d ago (Oct 10) |
| Account: PUREGOLD NORTH LUZON                                                                     |
+---------------------------------------------------------------------------------------------------+
|  FROM: North Luzon Group (NLUZ)  ------->  TO: Central Luzon Group (CLUZ)                          |
|  Reason: "Territory"  •  Requested by: Juan Dela Cruz (Head Admin)                                |
+---------------------------------------------------------------------------------------------------+
|  IMPACT SIMULATION (Live Snapshot)                                                                |
|  [Stores: 14]   [Active Headcount: 86]   [Open Vacancies: 5]   [HR Emploc: 86]                     |
|  Visibility: +12 users gaining  /  -9 users losing                                                |
+---------------------------------------------------------------------------------------------------+
|  [!] WARNINGS (Informational):                                                                    |
|  • Coverage Group CG-NLUZ-01 contains 3 stores moving ownership.                                  |
|  • Active reliever deployment: Maria Santos at Puregold Bulacan (Home Group: GMA).               |
+---------------------------------------------------------------------------------------------------+
|  [Actions: SA Only]                                [ Reject Transfer ]   [ Approve & Execute ]     |
+---------------------------------------------------------------------------------------------------+
```

---

## 3. Database Schema & RPC Mapping

### 3.1 Tables & Schema

#### `public.account_group_transfer_requests`
| Column Name | Type | Constraints / References | Description |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | Primary Key, `default gen_random_uuid()` | Unique request ID |
| `request_number` | `text` | Unique, Not Null | Formatted sequence: `AGT-YYYY-XXXX` |
| `account_id` | `uuid` | Not Null, FK $\to$ `accounts(id)` | Target account being moved |
| `from_group_id` | `uuid` | Not Null, FK $\to$ `groups(id)` | Current owner group |
| `to_group_id` | `uuid` | Not Null, FK $\to$ `groups(id)` | Destination group |
| `reason` | `text` | Not Null | Requester justification (max 10 chars) |
| `status` | `text` | `CHECK (status IN ('pending', 'approved', 'rejected'))` | Request state |
| `simulation_snapshot` | `jsonb` | Not Null, Default `'{}'::jsonb` | Complete output of `simulate_account_group_transfer` |
| `requested_by` | `uuid` | Not Null, FK $\to$ `users_profile(id)` | Requester profile ID |
| `requested_by_name` | `text` | Not Null | Requester snapshot name |
| `requested_at` | `timestamptz` | Not Null, Default `now()` | Submission timestamp |
| `reviewed_by` | `uuid` | FK $\to$ `users_profile(id)` | Reviewer profile ID |
| `reviewed_by_name` | `text` | Nullable | Reviewer snapshot name |
| `reviewed_at` | `timestamptz` | Nullable | Decision timestamp |
| `rejection_reason` | `text` | Nullable | Justification if rejected |
| `created_at` | `timestamptz` | Default `now()` | Record creation timestamp |
| `updated_at` | `timestamptz` | Default `now()` | Record update timestamp |

#### `public.account_group_transfer_request_history`
| Column Name | Type | Constraints / References | Description |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | Primary Key | Audit entry ID |
| `request_id` | `uuid` | FK $\to$ `account_group_transfer_requests(id)` | Parent request |
| `from_status` | `text` | Nullable | Previous state |
| `to_status` | `text` | Not Null | Transitioned state |
| `action` | `text` | `CHECK (action IN ('submitted', 'approved', 'rejected'))` | Action type |
| `actor_id` | `uuid` | FK $\to$ `users_profile(id)` | Actor who triggered event |
| `actor_name` | `text` | Nullable | Actor name snapshot |
| `note` | `text` | Nullable | Transition notes or rejection reason |
| `created_at` | `timestamptz` | Default `now()` | Timestamp |

---

### 3.2 Authoritative RPCs

#### 1. Simulation: `simulate_account_group_transfer`
```sql
public.simulate_account_group_transfer(
  p_account_id uuid,
  p_to_group_id uuid
) RETURNS jsonb
```
- **Security:** `SECURITY DEFINER`, accessible to callers with role level $\ge 90$ (`Head Admin`, `Super Admin`).
- **Returns JSON Object:**
  ```json
  {
    "current_group_id": "...",
    "current_group_name": "...",
    "current_group_code": "...",
    "destination_group_id": "...",
    "destination_group_name": "...",
    "destination_group_code": "...",
    "affected_stores": 14,
    "affected_plantilla_count": 86,
    "affected_vacancies_count": 5,
    "affected_hr_emploc_count": 86,
    "users_gaining_visibility": 12,
    "users_losing_visibility": 9,
    "has_coverage_conflict": false,
    "blocking_reason": null,
    "coverage_group_conflicts": [...],
    "warnings": [
      "Coverage Group CG-NLUZ-01 contains stores that will move ownership groups after transfer.",
      "Active reliever/commando deployment: Maria Santos deployed at Puregold Bulacan (Home Group: GMA)."
    ],
    "warning_count": 2
  }
  ```

#### 2. Request Submission: `submit_account_group_transfer_request`
```sql
public.submit_account_group_transfer_request(
  p_account_id uuid,
  p_to_group_id uuid,
  p_reason text
) RETURNS uuid
```
- **Security:** Head Admin or Super Admin (role level $\ge 90$).
- **Logic:** Validates account, generates `AGT-YYYY-XXXX`, captures simulation snapshot, inserts history and audit log, and dispatches in-app notifications.

#### 3. Request Approval: `approve_account_group_transfer_request`
```sql
public.approve_account_group_transfer_request(
  p_request_id uuid
) RETURNS void
```
- **Security:** **Super Admin only** (role level $= 100$).
- **Self-Approval Guard:** Blocked if caller is requester, *unless* caller is Super Admin (SA always overrides).
- **Execution Payload:**
  - Updates `public.accounts.group_id = v_to_group_id`.
  - Updates all linked stores: `public.stores.group_id = v_to_group_id WHERE account_id = v_account_id`.
  - Sets request status to `'approved'`, records reviewer ID and name.
  - Inserts transition record in `account_group_transfer_request_history`.
  - Inserts entry in `public.audit_logs`.
  - Sends notifications to Requester, Source Group HRCOs, Destination Group HRCOs, and Admins.
  - Executes `NOTIFY pgrst, 'reload schema'`.

#### 4. Request Rejection: `reject_account_group_transfer_request`
```sql
public.reject_account_group_transfer_request(
  p_request_id uuid,
  p_reason text
) RETURNS void
```
- **Security:** Super Admin only (role level $= 100$).
- **Validation:** `p_reason` must be non-empty.
- **Execution Payload:**
  - Sets request status to `'rejected'`.
  - Records reviewer ID, timestamp, and `rejection_reason`.
  - Inserts transition record into history.
  - Inserts audit log entry.
  - Sends notifications to Requester and Stakeholders.

---

## 4. Current Web Implementation Analysis & Parity Gaps

| Feature Area | Mobile Source of Truth (`OHMployee`) | Web Target (`ohmployee-web`) | Parity Status |
| :--- | :--- | :--- | :--- |
| **Category Registration** | Listed in More -> Requests | Registered in `REQUEST_CATEGORIES` as `account_group_transfers` | **PARITY OK** |
| **Pending Counter** | Aggregated in `RequestCenterBadgeService` | Counted in `fetchRequestCategoryCounts()` via `account_group_transfer_requests` | **PARITY OK** |
| **Navigation Tab** | Account Group Transfers list screen | Left sidebar in `/approvals` renders tab with Layers icon | **PARITY OK** |
| **Pending Queue Query** | `fetchRequests()` in `AccountGroupTransferService` | **Missing:** No query hook `usePendingAccountGroupTransfers()` in `requests.ts` | **GAP: Missing Query** |
| **Queue Review Pane** | Dedicated `_buildRequestList()` in Flutter | `ActiveQueueReviewPane.tsx` hits fallback block showing generic message | **GAP: Missing Pane Block** |
| **Review Card Component** | `_RequestCard` & `AccountGroupTransferDetailScreen` | **Missing:** No `StoreTransferApprovalCard.tsx` or `AccountGroupTransferApprovalCard.tsx` | **GAP: Missing Component** |
| **Simulation Metrics Display** | Impact simulation card with 6 counters + warnings list | Not displayed anywhere on web | **GAP: Missing Card UI** |
| **Approve / Reject Mutations** | Direct calls to Supabase RPCs | **Missing:** No `useApproveAccountGroupTransfer()` or `useRejectAccountGroupTransfer()` | **GAP: Missing Mutations** |
| **Role-gating & Self-approval** | SA-only action buttons; HA view-only; SA self-override | Auth helpers exist (`isHeadOrSuperAdmin`) but need SA-specific check for execution | **GAP: Role Verification** |

---

## 5. Step-by-Step Implementation Roadmap

To achieve 1-to-1 operational parity in `ohmployee-web`, the following tasks are defined:

### Task 1: TypeScript Types & Queries in `src/lib/queries/requests.ts`
1. Define TypeScript interface `AccountGroupTransferRequestItem`:
   ```typescript
   export interface AccountGroupTransferSimulationSnapshot {
     affected_stores: number;
     affected_plantilla_count: number;
     affected_vacancies_count: number;
     affected_hr_emploc_count: number;
     users_gaining_visibility: number;
     users_losing_visibility: number;
     has_coverage_conflict?: boolean;
     warnings?: string[];
     warning_count?: number;
     coverage_group_conflicts?: Array<{
       employee_name: string;
       store_name: string;
       home_group_name: string;
       conflict_type: string;
     }>;
   }

   export interface AccountGroupTransferRequestItem {
     id: string;
     requestNumber: string;
     accountId: string;
     accountName: string;
     fromGroupId: string;
     fromGroupName: string;
     fromGroupCode: string;
     toGroupId: string;
     toGroupName: string;
     toGroupCode: string;
     reason: string;
     status: "pending" | "approved" | "rejected";
     simulationSnapshot: AccountGroupTransferSimulationSnapshot;
     requestedBy: string;
     requestedByName: string;
     requestedAt: string;
     reviewedBy?: string | null;
     reviewedByName?: string | null;
     reviewedAt?: string | null;
     rejectionReason?: string | null;
     createdAt: string;
     updatedAt: string;
   }
   ```
2. Implement query function `fetchPendingAccountGroupTransfers()`:
   - Query `account_group_transfer_requests` with joined relations:
     ```typescript
     .from("account_group_transfer_requests")
     .select(`
       *,
       accounts:account_id(account_name),
       from_groups:from_group_id(group_name, group_code),
       to_groups:to_group_id(group_name, group_code)
     `)
     .ilike("status", "pending")
     .order("created_at", { ascending: false });
     ```
3. Export React Query hook: `usePendingAccountGroupTransfers()`.
4. Implement mutations and hooks:
   - `approveAccountGroupTransfer(requestId: string)` calling RPC `approve_account_group_transfer_request`.
   - `rejectAccountGroupTransfer({ requestId, reason }: { requestId: string; reason: string })` calling RPC `reject_account_group_transfer_request`.
   - Invalidate queries: `["request-category-counts"]`, `["account-group-transfers"]`, `["accounts"]`, `["stores"]`.

### Task 2: Build `src/components/approvals/StoreTransferApprovalCard.tsx`
1. Component Props: `request: AccountGroupTransferRequestItem`.
2. Header: Request Number, Status pill, relative timestamp (`formatRelativeAge`), absolute date formatted via `Intl`.
3. Account Transfer Route banner:
   - Account Name header.
   - Origin group $\to$ Destination group badges with group codes.
   - Requester info and Stated Reason.
4. Impact Simulation Accordion / Panel:
   - Key metric pills: `Affected Stores`, `Plantilla Employees`, `Open Vacancies`, `HR Emploc Links`.
   - Visibility shift pills: `+X users gaining`, `-Y users losing`.
   - Warning banner: Displays list of warnings (if any) with amber alert styling, or green confirmation when zero warnings.
5. Decision Action Controls:
   - Check if current user is Super Admin (`currentUser?.roleKey === "super_admin"` or role level 100).
   - "Approve Transfer" button (opens confirmation dialog detailing that linked stores will move ownership immediately).
   - "Reject" button (opens rejection dialog with mandatory multiline reason input).

### Task 3: Wire Queue into `ActiveQueueReviewPane.tsx`
1. Hook call:
   ```typescript
   const {
     data: transferRequests = [],
     isLoading: isTransferLoading,
     isError: isTransferError,
     refetch: refetchTransfers,
     isRefetching: isTransferRefetching,
   } = usePendingAccountGroupTransfers();
   ```
2. Add search query state: `transferSearchQuery`.
3. Filter requests by account name, request number, group names, requester, or reason.
4. Render dedicated section when `selectedCategory === "account_group_transfers"`:
   - Toolbar with title, pending count badge, refresh button, search input.
   - Loading, Error, and Empty states using `<DataState />`.
   - Map filtered items to `<StoreTransferApprovalCard />`.

---

## 6. Verification & Validation Plan

1. **RPC Availability Check:**
   Verify `approve_account_group_transfer_request`, `reject_account_group_transfer_request`, and `simulate_account_group_transfer` exist in database schema.
2. **Access Control Check:**
   - Head Admins can see the queue and view the simulation snapshot, but execution buttons are disabled or restricted to Super Admins.
   - Super Admins can approve and reject requests.
3. **Empty & Search Verification:**
   - Searching by request number (e.g. `AGT-`), account name, or group code filters the queue accurately.
   - Clearing search restores full queue.
4. **Data Contract Integrity:**
   Ensure simulation JSON safely handles null or missing keys (e.g. `warnings`, `affected_stores`).
