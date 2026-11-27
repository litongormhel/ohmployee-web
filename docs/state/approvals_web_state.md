# Approvals Module (Web) State

## 1. Overview & Architecture
The Approvals Module (`/approvals`) serves as the administrative hub and request review center for operational requests across 11 functional categories:
1. `new_stores` — New Store Requests & Roving Door Expansion Requisitions (Option 1)
2. `headcount` — Headcount Quota Amendments & Standard Requisitions
3. `account_requests` — Account Sign-Ups & Provisioning
4. `coverage` — Roving Coverage Group Requests
5. `vacancy_closures` — Vacancy Closure Requests
6. `hr_emploc_deletions` — HR Emploc Deletion Requests
7. `deactivations` — Employee Deactivation & Separation Clearance
8. `applicant_movements` — Applicant Movements & Cross-Store Transfers
9. `relievers` — Reliever Coverage Endorsements
10. `account_archives` — Billing Account Retirement and Archive Approval Queue (Super Admin only)
11. `rollbacks` — Import Batch Rollbacks & Reversal Queue (Super Admin & Head Admin)

*(Note: "All Requests" unified master tab and "Account Group Transfers" approval queue have been removed from `/approvals`. Account Group Transfers are now directly executed by Head Admin and Super Admin within Plantilla with full audit trail logging).*

---

## 2. Headcount & New Store Requisition Routing (Option 1)
- Requisitions submitted via headcount amendment that contain unlisted / new store doors (`hc_request_stores.is_new_store = true`) are automatically routed to the **New Stores** approval queue (`/approvals?tab=new_stores`).
- Standard headcount and quota amendment requests remain in the **Headcount** approval queue (`/approvals?tab=headcount`).
- New Stores approval and rejection handlers support both standalone `new_store_requests` rows and headcount roving door additions (`approve_headcount_request` fallback).

---

## 3. Account Group Transfer (Direct Admin Execution)
- Transferred out of `/approvals` queues per operational policy.
- Replaced with direct execution restricted strictly to Head Admin (`role_level >= 90`) and Super Admin (`role_level >= 100`).
- Surface: Plantilla Directory Account Card 3-dot context menu (`Transfer Group`).
- Modal: `TransferAccountGroupModal` with live impact simulation (`simulate_account_group_transfer`), destination group selection, and optional remarks.
- Execution: RPC `transfer_account_group_direct(p_account_id, p_to_group_id, p_reason)` updating `accounts.group_id`, `stores.group_id`, and writing mandatory audit logs to `public.audit_logs`.

---

## 3. UI Layout & Navigation
- **Header**: `AdminPageHeader` with title, subtitle, refresh button, and module category tag.
- **Top Tab Strip**: `RequestCategoryNavigation` rendering pill tabs in responsive wrapping layout (`flex-wrap gap-2`) with live counts and acknowledgment badges for authorized categories (`canViewApprovalsHub`, `getAllowedApprovalCategories`), guaranteeing that all 13 tabs remain 100% visible and accessible without requiring browser zoom-out or horizontal scroll hunting.
- **Main Review Pane**: `ActiveQueueReviewPane` rendered with `key={selectedCategory}` for immediate state isolation and clean tab remounting. Container padding optimized (`p-4 sm:p-5 lg:p-6`) to give maximum horizontal real estate to tables.
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
  - **Approve Archive**: Opens confirmation modal summarizing account and headcount. Invokes dedicated SECURITY DEFINER RPC `public.approve_account_archive(p_notification_id)`:
    1. Sets `accounts.is_active = false` and `accounts.status = 'Inactive'` (triggering `trg_account_archive_cascade_stores` to cascade to child stores).
    2. Updates notification status to approved (`is_read = true`, `is_archived = true`, `read_at = now()`).
    3. Logs audit trail in `public.audit_logs` (`action = 'UPDATE'`, `module = 'plantilla'`, `event = 'ACCOUNT_ARCHIVE_APPROVED'`).
    4. Invalidates TanStack Query keys (`["plantilla"]`, `["plantilla", "allowed-accounts"]`, `["plantilla", "account-metrics"]`, `["account-archive-requests"]`, `["account-archive-counts"]`, `["request-category-counts"]`).
  - **Reject Archive**: Opens rejection dialog with mandatory reviewer justification. Invokes dedicated SECURITY DEFINER RPC `public.reject_account_archive(p_notification_id, p_reason)`:
    1. Sets notification status to rejected (`is_read = true`, `is_archived = true`, `read_at = now()`, message prepended with `[REJECTED: <reason>]`).
    2. Leaves account active in `accounts` table.
    3. Logs audit trail in `public.audit_logs` (`action = 'UPDATE'`, `module = 'approvals'`, `event = 'ACCOUNT_ARCHIVE_REJECTED'`).
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
  - Columns: Batch #, Module (`Plantilla` | `Vacancy`), File Name, Scope (`Group / Account`), Rollback Reason / Note (reason code badge on top with note text stacked below), Requester & Date, Governance Window / Countdown, and Actions.
  - Search: Real-time client filter matching batch ID, file name, scope, uploader, requester, and reason note.
  - Pagination: Uses reusable `<Pagination />` component with page index, page size `[10, 25, 50]`, and range summary label.
- **Administrative Actions**:
  - **Approve Rollback**: Styled with solid danger button (`bg-[var(--danger-button)] hover:bg-[var(--danger-button-hover)] text-white shadow-2xs`). Opens confirmation modal summarizing irreversible impacts and invokes RPC `approve_plantilla_import_rollback` or `approve_vacancy_import_rollback`.
  - **Reject Rollback Request**: Opens rejection dialog requiring reviewer justification, invoking `reject_plantilla_import_rollback` or updating vacancy batch status with rejection remarks.
  - **Row Inspection**: Clicking any row opens comprehensive batch detail `<Modal>` displaying metadata, headcount rows, rollback window status, and reason notes.

---

## 8. HR Emploc Deletion Review Queue (`hr_emploc_deletions`)
- **Access Control**: Visible to Super Admin (`level >= 100` / `isOwner`), Head Admin (`level === 90`), and Encoder (`level === 30`) via `getAllowedApprovalCategories` in `src/lib/rbac.ts`.
- **Data Source & Resolution Contract (`fetchEmplocDeletionRequests`)**:
  - Pulls records from `hr_emploc_deletion_requests` joined with `hr_emploc`.
  - Scope Enrichment: Queries `accounts` (with `groups(group_name)`) by `account_id` and `account_name`, with secondary fallback to `vacancies` by `vcode` (`accounts(groups(group_name))` and `groups(group_name)`). Resolves full `groupName` and `accountName` to prevent empty/dash fields in UI.
- **Review Queue (`HrEmplocDeletionDataTable`)**:
  - Columns: Type, Group, Account, Emploc / VCODE, Applicant Name, Store / Position, Requested By, and Action / Rejection Reason.
  - Search: Full text matching applicant name, vcode, store name, position title, group name, account name, requester, and employee number.
  - Approve Modal: Summarizes applicant, VCODE, deletion type, and scope (`Group / Account`) with optional pipeline vacancy slot reopen toggle.

---

## 9. Super Admin Universal Bypass & RBAC Guard
- **Universal Super Admin Bypass**: Super Admin identity (`isOwner`, `email === 'ohmpayatt@proton.me'`, `role_level === 100`, or `roleKey === 'super_admin'`) unconditionally bypasses all module and category restrictions:
  - In `src/lib/rbac.ts`, `isOwner` checks email, `roleLevel >= 100`, and `AppRole.SUPER_ADMIN`.
  - In `src/lib/rbac.ts`, `isModuleAllowedForUser` grants immediate exit `if (isOwner(user)) return true;`.
  - In `src/app/(dashboard)/approvals/page.tsx`, `isSuperAdmin` bypasses `canViewApprovalsHub` and guarantees access to all 13 approval categories, preventing false positive `DataState kind="access_denied"` screens.
  - In `src/lib/auth.ts`, `loadCurrentUserContext` populates `roleLevel: 100` and `role_level: 100` on `WebCurrentUserContext`.
- **Strict Role Integrity**: Non-admin roles (OM, HRCO, Recruitment, Backoffice, Viewer) retain their strict ADR-001 defense-in-depth boundaries (HRCO strictly denied Approvals, CENCOM, Reports; Backoffice restricted to deactivations only; Encoder restricted to 5 categories).

---

## 10. Dedicated Requester Tracking Feed (`/my-requests`)
- **Overview**: Dedicated personal request tracker positioned directly below `Approvals` in the sidebar navigation, providing 100% parity with mobile OHMployee `my_requests_screen.dart`.
- **Target Audience**: All authenticated roles (Operations Managers, HR Coordinators, Area Coordinators, Team Leaders, Encoders, Admins). Enables requesters who lack access to the admin `/approvals` clearinghouse to monitor their submitted requests.
- **Unified Request Aggregation (`fetchMyRequests`)**:
  - Pulls user-submitted requests across 6 operational tables/views: `headcount_requests`, `new_store_requests`, `vacancy_closure_requests`, `v_deactivation_requests`, `vw_amr_list` (AMR joined view), and `coverage_requests` (with explicit `accounts!account_id` and `coverage_groups!target_coverage_group_id` disambiguation).
  - Normalizes payloads into `MyRequestItem` with unified status taxonomy (`pending`, `approved`, `rejected`, `cancelled`).
  - Cross-references user identity via `authUserId` and `profileId` with PostgREST column error guards. Ensures 100% physical schema alignment for views without extraneous columns (e.g. `rejection_reason` on `v_deactivation_requests`) and uses canonical views for joins (`vw_amr_list`).
- **UI Presentation (`MyRequestsPage`)**:
  - Streamlined header layout maximizing vertical space for table reading (top KPI metric cards removed in favor of status tab badge counters).
  - Segmented status tabs with integrated counters (`All (N)`, `Pending (N)`, `Approved (N)`, `Rejected (N)`), category dropdown selector, client search filter, and responsive View Switcher (`Table` default vs `Cards`).
  - High-readability enterprise data table (`MyRequestsDataTable`): Displays compact, non-redundant columns (`Type` with category badge and relative time, `Request Subject` focused strictly on the role, personnel identity, or target VCode without repeating account/store or category prefixes, `Account & Store`, `Stated Justification` italicized snippet, `Submitted` date and time, and `Status & Milestone` with review subtext; redundant Action column removed in favor of whole-row interaction).
  - Interactive Request Details Modal (`MyRequestDetailModal`): Opened by clicking any table row, displaying complete operational scope grid, stated justification, review status banners (Pending review notice with 1-click Follow-Up copy shortcut, Cleared by Approver with remarks, or Rejection feedback with audit timestamps).
  - Client-side pagination powered by `TablePagination` (`10, 20, 50` rows per page).

---

## 11. ADR-003: Unified Roving Headcount Requisition with Atomic Store Provisioning
- **Overview**: Solves multi-store opening bottlenecks for Roving Headcount requisitions (`submit_headcount_request`). Allows unlisted/opening stores to be requested alongside existing stores in a single submission, with zero database pollution in `public.stores` until formal approval.
- **Database Architecture (Migrations `20262606000126` & `20262606000128`)**:
  - `public.hc_request_stores`: `store_id` nullable, added `is_new_store`, `store_name`, `area_province`, `area_city`, `island_group`, and `created_store_id REFERENCES public.stores(id)` with check constraint `chk_hc_request_stores_target`.
  - `submit_headcount_request`: polymorphic store array ingestion (`stores` / `store_ids`), mandatory Operational Justification ($\ge 20$ chars) enforced across all request types, and hard-block Island Group span guard across registered and proposed stores. Migration `20262606000128` resolved an island group resolution regression by deriving island groups for proposed new stores using the canonical database function `public.fn_derive_island_group(p_province)` rather than querying `ref_locations` (which does not carry `island_group`).
  - `create_plantilla_slot_from_request`: Phase 1 atomic store provisioning inserts unlisted stores into `public.stores` upon approval and binds them to `created_store_id`, followed by Phase 2 Coverage Group (`CGCODE`), per-store VCodes, Vacancies, and Plantilla Slots.
  - `get_hc_request_stores`: returns `is_new_store`, `store_name`, `province`, `city`, `island_group`, and `created_store_id`.
- **UI Components & Option 1 Queue Routing**:
  - `RequestHeadcountModal.tsx`: multi-city roving store search, quick-add unlisted store sub-form with province/city selectors and synchronous `deriveIslandGroup(unlistedProvince)` resolution, selected chips with `(New Store)` badges, and live character counter enforcing $\ge 20$-char justification.
  - `locations.ts`: `fetchRefLocations` queries physical columns `province, city` from `ref_locations` and derives `island_group` in memory via `deriveIslandGroup`, adhering to the PostgREST column guard.
  - **New Stores Queue Routing (`Option 1`)**:
    - When a headcount requisition introduces proposed new stores (`hc_request_stores.some(s => s.is_new_store)`), it routes out of the standard `Headcount` approval queue and into the **`New Stores`** tab (`/approvals?tab=new_stores`) and `/my-requests` New Store category.
    - `fetchHeadcountRequests` & `fetchHeadcountCounts`: filter out requisitions containing proposed new stores, preventing ambiguous `Store: —` displays in the headcount table.
    - `fetchNewStoreRequests` & `fetchNewStoreCounts`: merge unlisted roving cluster requisitions, showing all proposed doors (`Store 1, Store 2, Store 3`), primary location, and a `✨ New Roving Doors (N)` badge with position details.
    - `NewStoreDataTable.tsx`: integrates dual action dispatching—delegating standard new store requests to `approveNewStoreRequest` and roving headcount requests with new doors to `approveHeadcountRequest` (which seamlessly triggers Step 1.5 atomic store provisioning in `create_plantilla_slot_from_request`) and `rejectHeadcountRequest`.
    - `fetchMyRequests` (`/my-requests`): categorizes headcount requests with new stores under `category: "new_stores"` with clear title `New Store (Position): Store Names` and subtitle `Account · N New Door(s) Proposed`.

---

## 12. Import Batch Rollback Status Reconciliation & ZERO_EDIT_LOCK Guard (`ohm#fix-plantilla-rollback-status-desync-and-guard`)
- **Root Cause & Forensics**: Investigated high Supabase CPU alerts caused by repetitive 1-second `approve_plantilla_import_rollback` error loops on Staging (`qqiiznmqxfoamqytjica`). Diagnosed that historical batch `aa79f9c7-9d44-4f35-9224-8c701534cee7` had `status = 'rolled_back'` but `rollback_status = 'requested'`, causing it to linger in the Pending Approvals queue. When an execution attempt was made, `public.approve_plantilla_import_rollback` evaluated ADR-002 Zero-Edit Lock checks before verifying if the batch was already rolled back, crashing on employee `2023-12046` (`VASQUEZ, JULIUS JULIUS`, modified months post-approval) with Postgres error `40001 ZERO_EDIT_LOCK`.
- **Database Hardening (Migration `20262606000175`)**:
  - Reconciled historical batches where `status = 'rolled_back'` to `rollback_status = 'completed'`.
  - Realigned check constraints `pib_rollback_status_check` and `vib_rollback_status_check` to permit `'rejected'`.
  - Hardened `public.approve_plantilla_import_rollback(p_batch_id)`:
    - Added Guard 1: If `v_batch.status = 'rolled_back'`, auto-completes `rollback_status = 'completed'` and returns cleanly without triggering downstream mutation checks.
    - Added Guard 2: Strictly validates `v_batch.status = 'approved'` before evaluating `public.get_plantilla_import_first_modified_record`.
- **UI & Query Hardening**:
  - `src/lib/queries/requests.ts`: `fetchRollbackApprovalRequests` and `fetchRollbackApprovalCounts` strictly require `status = 'approved'` for `rollbackStatus = 'requested'` items to qualify for the `pending` queue, accurately classifying already rolled-back batches under `approved` (`Rolled Back`).
  - `src/lib/queries/dataControl.ts`: updated `humanizeRollbackError` to recognize `zero_edit_lock` before generic `"lock"` checks, eliminating misleading "Another rollback is already in progress. Please wait and retry" messages.
  - `src/components/approvals/RollbackDataTable.tsx`: catches `ZERO_EDIT_LOCK` / `40001` and surfaces a permanent warning, swapping the Confirm button for "Close" to permanently prevent rapid repeated retries.

---

## 13. Active-Category Query Scoping & Role-Gated Category Counts (`ohm#fix-anon-permission-denied-log-burst-and-approvals-polling`)
- **Active-Category Query Isolation (`src/components/approvals/ActiveQueueReviewPane.tsx`)**:
  - All 11 approval queue list and status-count hooks (`useHeadcountRequests`, `useHeadcountCounts`, `useEmplocDeletionRequests`, `useEmplocDeletionCounts`, `useNewStoreRequests`, `useNewStoreCounts`, `useVacancyClosureRequests`, `useVacancyClosureCounts`, `useApplicantMovementRequests`, `useApplicantMovementCounts`, `useDeactivationRequests`, `useDeactivationCounts`, `useRelieverEndorsements`, `useRelieverCounts`, `useCoverageRequests`, `useCoverageCounts`, `useAccountApprovalQueue`, `useAccountRequestCounts`, `useAccountArchiveRequests`, `useAccountArchiveCounts`, `useRollbackApprovalRequests`, `useRollbackApprovalCounts`) accept `{ enabled?: boolean }` and are strictly gated by `enabled: selectedCategory === "<category_key>"`.
  - Switching tabs in `/approvals` executes only the 2 queries belonging to the selected queue rather than fanning out 22 queries across all 11 queues simultaneously.
- **Role-Gated & Session-Guarded Category Counters**:
  - `useRequestCategoryCounts` in `Sidebar.tsx`, `DashboardPage`, and `ApprovalsPage` is gated by `enabled: Boolean(currentUser && (hasFullAccess(currentUser) || canViewApprovalsHub(currentUser)))`, and `fetchRequestCategoryCounts` checks `supabase.auth.getSession()` before dispatching count queries.

---

## 14. New Store Approval Table & Request Reference Standardization (`ohm#fix-new-store-approval-slot-collision-and-kpi-parity`)
- **New Store Table (`src/components/approvals/NewStoreDataTable.tsx`)**:
  - Column headers: `Group`, `Account`, `Store Name`, `Location`, `HC`, `Requested by`, `Date and Time`, `Action` (or `Rejected reason`).
  - Removed redundant `Pending Review` status badge below `Store Name` and removed the `Forward` button/modal from `Action` (retaining `Reject` and `Approve`).
- **8-Char Alphanumeric Request Reference (`src/components/modals/NewStoreRequestModal.tsx`)**:
  - `Request Reference` displays an 8-character uppercase alphanumeric code derived from the request UUID (`requestId.replace(/-/g, "").slice(0, 8).toUpperCase()`) with full UUID preserved in the tooltip.
- **Slot Idempotency & Roving Store Filter**:
  - `approve_new_store_request` guards `plantilla_slots` inserts against `fn_trg_auto_create_vacancy_slot` so `uq_plantilla_slots_legacy_vcode_ordinal` never collides.
  - `fetchHeadcountModalMasterData` (`src/lib/queries/requests.ts`) enforces strict 3-way active-store filtering (`is_active = true`, `status = 'active'`, `is_archived IS NULL OR false`).







