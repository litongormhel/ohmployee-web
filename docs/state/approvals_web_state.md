# Approvals Module (Web) State

## 1. Overview & Architecture
The Approvals Module (`/approvals`) serves as the administrative hub and request review center for operational requests across 11 functional categories:
1. `new_stores` — New Store Requests
2. `headcount` — Headcount Quota Amendments & Requests
3. `plantilla_approvals` — Plantilla Placements & Deployments
4. `account_requests` — Account Sign-Ups & Provisioning
5. `coverage` — Roving Coverage Group Requests
6. `vacancy_closures` — Vacancy Closure Requests
7. `hr_emploc_deletions` — HR Emploc Deletion Requests
8. `deactivations` — Employee Deactivation & Separation Clearance
9. `applicant_movements` — Applicant Movements & Cross-Store Transfers
10. `account_group_transfers` — Account Group Transfers
11. `relievers` — Reliever Coverage Endorsements

---

## 2. UI Layout & Navigation
- **Header**: `AdminPageHeader` with title, subtitle, refresh button, and module category tag.
- **Top Tab Strip**: `RequestCategoryNavigation` rendering pill tabs with live counts and acknowledgment badges for authorized categories (`canViewApprovalsHub`, `getAllowedApprovalCategories`).
- **Main Review Pane**: `ActiveQueueReviewPane` rendered with `key={selectedCategory}` for immediate state isolation and clean tab remounting.
  - Sub-Tabs: Pending, Approved, Rejected (or Deactivated for deactivations) with real-time badges.
  - Search Toolbar: Client-side keyword search across multiple metadata fields with auto-reset to page 1 on input change.
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
