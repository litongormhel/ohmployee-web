# Approvals Module (Web) State

## 1. Overview & Architecture
The Approvals Module (`/approvals`) serves as the administrative hub and request review center for operational requests across functional categories, led by the unified **All Requests** command tab, followed by 11 functional categories:
0. `all_requests` — All Requests Unified Hub (Default active tab for Super Admin / Admin review)
1. `account_archives` — Account Archive Requests (Super Admin only)
2. `account_group_transfers` — Account Group Transfers
3. `account_requests` — Account Sign-Ups & Provisioning
4. `applicant_movements` — Applicant Movements & Cross-Store Transfers
5. `coverage` — Roving Coverage Group Requests
6. `deactivations` — Employee Deactivation & Separation Clearance
7. `headcount` — Headcount Quota Amendments & Requests
8. `hr_emploc_deletions` — HR Emploc Deletion Requests
9. `new_stores` — New Store Requests
10. `relievers` — Reliever Coverage Endorsements
11. `rollbacks` — Import Batch Rollbacks & Reversal Queue (Super Admin & Head Admin)
12. `vacancy_closures` — Vacancy Closure Requests

---

## 2. All Requests Unified Command Center (`all_requests`)
- **Default Landing Tab**: Automatically defaults to `"all_requests"` when entering `/approvals` without a `?tab=` query parameter.
- **Top Badge**: Sum of all pending operational requests across categories.
- **Toolbar & Global Search**: Status pills (`Pending`, `Approved / Completed`, `Rejected`), global search input filtering items across all categories simultaneously, and a unified refresh button.
- **Resilient Parallel Fetching**: Utilizes `Promise.allSettled()` to fetch queues across all operational categories in parallel; individual category failures are safely isolated without crashing the entire hub.
- **Smart Category Accordions**:
  - **Dynamic Sorting**: Categories with active items (`count > 0` for current status and search query) sort automatically to the top; categories with `0` items sort to the bottom.
  - **Auto-Expand / Collapse**: Auto-expands categories with active items (`count > 0`); auto-collapses empty categories into a compact 1-line header with `0` badge while preserving manual toggle control.
  - **Header Actions**: Each category card includes an `"Open Tab ->"` action button that smoothly routes to that category's dedicated main tab.
  - **Preview Cap (5 items)**: Displays up to 5 items per category by default, with a `"Show all X requests"` toggle and deep-link navigation.
  - **Direct In-Line Actions**: Direct row action buttons (Approve, Reject, Review, View) are functional in-place using existing modular modal and mutation workflows, auto-invalidating category queries and global badges upon completion.

---

## 3. UI Layout & Navigation
- **Header**: `AdminPageHeader` with title, subtitle, refresh button, and module category tag.
- **Top Tab Strip**: `RequestCategoryNavigation` rendering pill tabs in alphabetical sequence (A-Z) with live counts and acknowledgment badges for authorized categories (`canViewApprovalsHub`, `getAllowedApprovalCategories`).
- **Main Review Pane**: `ActiveQueueReviewPane` rendered with `key={selectedCategory}` for immediate state isolation and clean tab remounting.
  - **Inline Toolbar (`QueueToolbar`)**: A single horizontal row containing:
    - Left side: Search input alongside status filter tabs (`Pending`, `Approved`, `Rejected` / `Deactivated`) with live count badges.
    - Right side: `Refresh` button.
  - Data States: Loading, error with retry, and contextual empty states via `ApprovalsDataState`.

---

## 3. Pagination Architecture (1:1 Vacancy Parity)
Pagination follows the canonical pattern established by `VacancyTable` and `TablePagination`:
- **Shared Component**: Uses `@/components/shared/TablePagination`.
- **Card Placement**: Nested directly below the table body inside the table container card (`border-t border-table-rule-section px-4 py-3`).
- **Parameters**:
  - `page`: active 1-based page index (defaults to `1`).
  - `pageSize`: rows per page (defaults to `10`, with options `[10, 25, 50]`).
  - `totalCount`: total number of matching items in the active queue/filter slice.
  - Dynamic resets:
    - Switching sub-category reset: `key={selectedCategory}` resets pane state to page 1.
    - Switching sub-tab (`pending`, `approved`, `rejected`): triggers `setPage(1)`.
    - Typing in search input: triggers `setPage(1)`.
    - Changing page size: sets `pageSize` and triggers `setPage(1)`.
- **Bulk Action Integration**:
  - `isAllSelected` evaluates visible items on `paginatedRequests`.
  - `toggleSelectAll` selects or deselects visible items on the active page without invalidating multi-page operations.

---

## 4. Query Layer & API Contracts
All fetch functions in `src/lib/queries/requests.ts`, `accountRequests.ts`, and `hr_emploc.ts` accept an optional `RequestPaginationParams`:
```ts
export interface RequestPaginationParams {
  page?: number;
  limit?: number;
}
```
When pagination parameters are provided, queries apply `.range((page - 1) * limit, page * limit - 1)`. When omitted, full dataset queries enable exhaustive client-side multi-field searching without backend serialization barriers.

---

## 5. Archival, QA Reset & Filtering Contract
- **Operational Tables with Dedicated Archival Flags**:
  - `new_store_requests` & `headcount_requests`: enforce `is_archived = false`.
  - `coverage_requests`: enforces `archived_at IS NULL`.
  - `v_deactivation_requests`: database view definition natively encapsulates `WHERE is_archived = false`.
- **Self-Contained Lifecycle Queues**:
  - `account_group_transfer_requests`, `applicant_movement_requests` (`vw_amr_list`), `vacancy_closure_requests`, `hr_emploc_deletion_requests`, and `v_workforce_assignment_request_queue`: lifecycle status columns (`status IN ('pending', 'approved', 'rejected', ...)`) manage queue retention without invalid synthetic `suppressed_by_batch_id` / `is_archived` filters.
- **Preserved Queues**: `account_requests` (Account Sign-Ups) are explicitly preserved and never archived or suppressed during QA Reset cycles.
- **Auto-Scrolling Navigation**: `RequestCategoryNavigation` automatically keeps the active category tab in view via `activeTabRef.current.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' })`.

---

## 6. Account Archive Approval Workflow (`account_archives`)
- **Access Control**: Category navigation tab and review queue are strictly visible to Super Admin (`level >= 100` / `isOwner`) via `getAllowedApprovalCategories` in `src/lib/rbac.ts`.
- **Data Source**: Backed by `public.notifications` (with `reference_type = 'account'` and `event_type = 'account_archive_request'`), written securely via database SECURITY DEFINER RPC `public.notify_user(...)` to comply with RLS policy `notif_insert_service_role` and `recipient_role` NOT NULL constraints. Tracks requester, target account, justification remarks (>= 30 characters), and active employee snapshot at request time.
- **Review Queue (`AccountArchiveDataTable`)**:
  - Filter tabs: `Pending`, `Approved`, `Rejected` with live counter badges.
  - Columns: Account Name & Code, Remarks / Justification, Headcount Impact (snapshot at request time), Requester & Date, Status, and Actions.
  - Search: Real-time client search filtering by account name, account code, or remarks.
  - Pagination: 1:1 parity with standard `TablePagination` (page index, page size `[10, 25, 50]`).
- **Super Admin Actions**:
  - **Approve Archive**: Opens confirmation modal summarizing account and headcount. Upon confirmation:
    1. Sets `accounts.is_active = false` and `accounts.status = 'Inactive'`.
    2. Updates notification status to approved (`is_read = true`, `is_archived = false`, title updated with `[APPROVED]`).
    3. Logs audit trail in `public.audit_logs` (`action = 'UPDATE'`, `table_name = 'accounts'`).
    4. Invalidates TanStack Query keys (`["plantilla-accounts"]`, `["account-archive-requests"]`, `["request-category-counts"]`).
  - **Reject Archive**: Opens rejection dialog with mandatory reviewer justification. Upon submission:
    1. Sets notification status to rejected (`is_read = true`, `is_archived = true`, title updated with `[REJECTED]`).
    2. Leaves account active in `accounts` table.
    3. Logs audit trail in `public.audit_logs`.
    4. Invalidates TanStack Query keys to refresh counts and queue state.

---

## 7. Import Batch Rollback Review Queue (`rollbacks`)
- **Access Control**: Visible to Super Admin (`level >= 100` / `isOwner`) and Head Admin (`level === 90`) via `getAllowedApprovalCategories` in `src/lib/rbac.ts`.
- **Data Source**: Aggregates batch records from `plantilla_import_batches` and `vacancy_import_batches` via RPCs `get_plantilla_import_batches` and `get_vacancy_import_batches` alongside fast table counts:
  - `pending`: Batches where `rollback_status = 'requested'`.
  - `approved`: Batches where `rollback_status = 'completed'` or `status = 'rolled_back'`.
  - `rejected`: Batches where `rollback_status IN ('rejected', 'failed')`.
- **Review Queue (`RollbackDataTable`)**:
  - Filter tabs: `Pending`, `Approved`, `Rejected` with live counter badges.
  - Columns: Batch #, Module (`Plantilla` | `Vacancy`), File Name, Scope (`Group / Account`), Rollback Reason / Note, Requester & Date, Governance Window / Countdown, and Actions.
  - Search: Real-time client filter matching batch ID, file name, scope, uploader, requester, and reason note.
  - Pagination: Uses reusable `<Pagination />` component with page index, page size `[10, 25, 50]`, and range summary label.
- **Administrative Actions**:
  - **Approve & Execute Rollback**: Styled with solid danger button (`bg-[var(--danger-button)] hover:bg-[var(--danger-button-hover)] text-white shadow-2xs`). Opens confirmation modal summarizing irreversible impacts and invokes RPC `approve_plantilla_import_rollback` or `approve_vacancy_import_rollback`.
  - **Reject Rollback Request**: Opens rejection dialog requiring reviewer justification, invoking `reject_plantilla_import_rollback` or updating vacancy batch status with rejection remarks.
  - **View Details**: Opens comprehensive batch detail `<Modal>` displaying metadata, headcount rows, rollback window status, and reason notes.

