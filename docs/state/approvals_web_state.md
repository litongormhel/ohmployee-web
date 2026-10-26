# Approvals Module (Web) State

## 1. Overview & Architecture
The Approvals Module (`/approvals`) serves as the administrative hub and request review center for operational requests across 11 functional categories, arranged in alphabetical order (A-Z):
1. `account_group_transfers` — Account Group Transfers
2. `account_requests` — Account Sign-Ups & Provisioning
3. `applicant_movements` — Applicant Movements & Cross-Store Transfers
4. `coverage` — Roving Coverage Group Requests
5. `deactivations` — Employee Deactivation & Separation Clearance
6. `headcount` — Headcount Quota Amendments & Requests
7. `hr_emploc_deletions` — HR Emploc Deletion Requests
8. `new_stores` — New Store Requests
9. `plantilla_approvals` — Plantilla Placements & Deployments
10. `relievers` — Reliever Coverage Endorsements
11. `vacancy_closures` — Vacancy Closure Requests

---

## 2. UI Layout & Navigation
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

## 5. Archival, QA Reset & Rollback Filtering Contract
- **Operational Queues Swept**: `account_group_transfers`, `applicant_movements`, `coverage`, `deactivations`, `headcount`, `hr_emploc_deletions`, `new_stores`, `plantilla_approvals`, `relievers`, `vacancy_closures`.
- **Gated Predicates**: All operational queue queries and badge counters enforce `COALESCE(is_archived, FALSE) = FALSE AND suppressed_by_batch_id IS NULL`.
- **Preserved Queues**: `account_requests` (Account Sign-Ups) are explicitly preserved and never archived or suppressed during QA Reset cycles.
- **Rollback Behavior**: Batch rollback restores active requests to `is_archived = false` and clears `suppressed_by_batch_id = NULL` on pre-archived items without reopening closed records.
