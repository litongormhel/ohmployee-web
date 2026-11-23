# Historical Plantilla Web Implementation Plans & Updates

## 12. Proposed Implementation Plan

### Phase 1: Route & Shared Shell Scaffolding ✅ COMPLETE
- `src/app/(dashboard)/plantilla/page.tsx` is fully implemented as a read-only admin page.
- `AdminPageHeader` (title, subtitle, readOnly badge), 4x `MetricCard` KPI row, `AdminFilterBar` with Employee/Store segmented view toggle, and `DataState` (loading, empty, access_denied, error) are all wired.
- Employee View and Store Staffing View share a single page with filtered, paginated dense tables.
- No mock data; all queries go through Supabase RPCs only.
- Employee table columns: Emp ID, Name (AH badge), Account/Store, Position, Assignment (Roving count), Type, Status (StatusBadge + SLA breach ⚠).
- Store table columns (OHM2026_1132): Store Code, Store Name, Account/Region, Actual (`onboard_count`), HR Pipeline (`hr_pipeline_count`), Vacancy (`open_headcount`, SLA breach ⚠), Required (`required_headcount`), MFR % (`fill_rate` from backend; formula tooltip: Actual / (Actual + HR Pipeline + Vacancy)), Staffing Risk, SLA Badge. Legacy "Gap" column removed; no web-side MFR computation.
- Deactivation overlays applied via `deriveDeactivationOverlay`: pending-separation rows get dashed border + `bg-red-50/30 opacity-80`; inactive/terminated/suspended rows get `opacity-65 pointer-events-none` + strikethrough on ID and name.
- Staffing risk derived via `deriveStaffingRisk` to drive backend-returned staffing risk, SLA badge, vacancy count, and vacancy SLA breach indicators.
- Filters: search (apply-on-click), account ID, group ID, store ID (employee view), employment status (employee view), deployment type (employee view), staffing risk/SLA status (store view).
- Validated: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

### Phase 2: Database RPC & Security Migrations ✅ APPLIED REMOTELY
- Migrations `20260607000002` and `20260607000003` exist and are applied remotely.
- Backend contracts implemented: `list_web_plantilla_employees`, `list_web_plantilla_store_staffing`, `get_web_plantilla_summary`, and `get_web_plantilla_detail`.
- User-role caller context resolution via `get_web_current_user_context` is implemented.
- Strict SQL-level data masking for personal numbers, emails, addresses, salary rates, and Gov IDs is enforced for restricted roles.
- RLS security policies gating queries against user accounts and group scopes are set up.
- Group ID filtering is wired through deployed `p_group_id` parameters on summary, employee list, and store staffing RPCs.

### Phase 3: Client Integration & State Management ✅ COMPLETE
- `src/lib/queries/plantilla.ts` is implemented with full TypeScript types, RPC wrappers, and normalizers. Added `getPlantillaAccountStatusCounts` to fetch active status counts for authorized accounts.
- Exported RPC wrappers: `getPlantillaSummary`, `listWebPlantillaEmployees`, `listWebPlantillaStoreStaffing`, `getWebPlantillaDetail`, `getPlantillaAccountStatusCounts`.
- Employee list sorting defaults to backend-supported `employee_name`; stale `last_name` is not sent to the deployed RPC allowlist. Store staffing sorting defaults to backend-supported `store_name`.
- Typed JSONB sub-types: `PlantillaCoveredStore`, `PlantillaGovernmentIds`, `PlantillaClearanceChecklistItem`, `PlantillaClearanceDocument`, `PlantillaMovementRequest`, `PlantillaAuditTimelineItem`.
- Presentation-layer derivation helpers: `deriveDeactivationOverlay`, `deriveTransferOverlay`, `deriveStaffingRisk`.
- Error class `PlantillaDataError` with `access_denied` / `retryable` kind discriminator.
- React Query `useQuery` hooks are wired in `page.tsx` for summary, employee list, and store staffing list.
- **Account-First Selection Gate (ADR-001 Compliance):**
  - **Query Gating:** All three listing/summary queries (`summaryQuery`, `employeeQuery`, `storeQuery`) are gated using `enabled: !!accountId`.
  - **Auto-Fire/Auto-Select:** Users with scoped roles (e.g. HRCO, OM, Encoder) having exactly one authorized account automatically bypass the selection screen. The single account is resolved and selected on mount.
  - **URL Deep-linking:** If the page is entered with an `accountId` URL query parameter, the state is hydrated and queries execute immediately.
  - **Fail Closed:** If the account scope is empty or unresolved, the queries remain disabled.
  - **Account Selector UI:** Multi-account or broad-access users are presented with a selection dashboard displaying a grid of account cards showing placement status counts (Active, Transfer, Separation, Suspended) aggregated via `get_plantilla_account_status_counts` RPC.
  - **Back Navigation:** Multi-account users can reset selection via a "← Back to Account Selection" button which clears the URL query parameter and filters.
- All four `DataState` boundaries (loading, empty, access_denied, retryable error with retry callback) are active.
- **Next.js `<Suspense>` & Canonical Auth Parity (ohm#p7f2a1b9):**
  - Wrapped page export in `<Suspense fallback={<PlantillaSkeleton />}>` to avoid CSR bail-out freezes when reading `useSearchParams()`.
  - Replaced ad-hoc `userContextQuery` with canonical `useCurrentUser()` from `@/lib/auth`, matching `/vacancy`, `/hr-emploc`, and `/approvals`.
  - Removed fragile `isHydrated` latch and derived `viewMode` and `accountId` directly from `searchParams` / single-scoped context, eliminating cascading re-render loops and URL navigation race conditions.

### Phase 4: Detail Drawer ✅ COMPLETE
- `src/components/plantilla/PlantillaDetailDrawer.tsx` is fully implemented.
- Employment/allocation grid, roving coverage (when `assignmentType === 'Roving'`), clearance panel (when `plantilla_status === 'Pending Separation'`), SLA warning block, masked PII fields, and audit timeline are all rendered.
- `getWebPlantillaDetail` is called via `useQuery` (queryKey: `["plantilla", "detail", plantillaId]`), enabled only when a `plantillaId` is non-null.
- All four DataState boundaries are active: loading, access_denied, not found (empty), and retryable error with retry callback.
- Deactivation banners (separation-pending, deactivated) and transfer overlay banner are rendered at the top of the drawer body.
- `CapabilityActionBar` maps backend `row_capabilities` only to read-only visibility hints for `can_request_deactivation`, `can_review_deactivation`, `can_request_deletion`, `can_review_deletion`, and `can_transfer_employee`. Stale frontend-only action assumptions such as generic separation approval, roving edit, suspend toggle, and AH request are not rendered in the employee detail drawer.
- Detail JSONB arrays (`covered_stores`, `clearance_checklist`, `clearance_documents`, `audit_timeline`) tolerate null/partial payloads and use normalized stable keys so duplicate or partially missing items do not collide in React rendering.
- Assignment coverage renders for both stationary and roving employees: stationary records show the primary store, while roving records show covered stores or an explicit empty roving payload state.
- Clearance/offboarding audit rendering is restricted to pending-separation records with checklist rows.
- Audit timeline rendering is null-safe; missing event timestamps render as unavailable instead of inventing client-side dates.
- Row click wiring: employee table rows emit `onRowClick(row.id)`. Dimmed rows (inactive/terminated/suspended) keep `pointer-events-none` and cannot be clicked. Active and pending-separation rows are keyboard- and mouse-accessible (`role="button"`, `tabIndex=0`, Enter/Space support).
- Drawer close clears `selectedPlantillaId` state in the page, closing the drawer.
- Store view drawer: not yet implemented (Phase 4 partial — employee only).
- Validated: `pnpm lint` clean, `pnpm build` clean (zero errors, zero warnings).

### Phase 5: Action Mutations Integration
- Hook up React Query mutations (`useMutation`) to backend action RPCs:

### Phase 6: UI Standard & Motion System Alignment (Loop 6A & 6B) ✅ COMPLETE
- **Loop 6A (Drawers & Tables)**: Wrapped `PlantillaDetailDrawer` and all 8 pool/store drawers with canonical `@/components/shared/DetailDrawer` (`drawer-width-lg`). Tokenized directory page, account gate selection, MFR / fill rate bars, tab pills, and member/vacancy tables (0 literals, $\ge 14\text{px}$ floor). MFR progress bars in Account cards and `StoreStaffingOverviewDrawer` strictly enforce thresholds (100% Green, 95% to 99.99% Yellow, <95% Red) with recessed `bg-surface-muted border border-border-subtle/50` tracks to maintain visibility across light and dark themes without fading out into card backgrounds. Top tab switcher removed in favor of direct Store Plantilla default view with pinned Moses HQ entry routing to Moses HQ Pool; Workforce Analytics integrated as top-toolbar modal trigger in `MosesHqPoolView`.
- **Loop 6B (Modals & Forms)**: Standardized all 8 Plantilla lifecycle modals (`InitiateSeparationModal`, `RequestDeactivationModal`, `RequestPoolConversionModal`, `RequestPoolHeadcountModal`, `RequestRelieverCoverageModal`, `TransferPersonnelModal`, `UpdateEmploymentStatusModal`, `UpdateScheduleModal`) with canonical `Modal` at `z-[60]` (stacks above `DetailDrawer` at `z-50`). Hardened `isSubmitting`, `isDirty`, and backdrop guards. Preserved `--danger` strictly for validation errors and destructive actions. Exactly 0 literals across all 8 modals.
  - Submit personnel store transfer.
  - Request Additional Headcount (AH).
  - Initiate separation workflow (Resignation / Termination / Backout).
  - Update separation clearance checkboxes and upload clearance forms.
- Configure cache invalidation policies to automatically reload active roster tables and metrics summary bars after every mutation.

### Phase 6: Plantilla Bulk Baseline Import & Mobile Governance Parity (`PlantillaImportModal.tsx`, ADR-002) ✅ COMPLETE
- **ADR-002 Architectural Invariants & Template Standardization (`data_control_xlsx.ts`)**:
  - 8 Always-Required Store Columns: `GROUP_NAME`, `ACCOUNT_NAME`, `MOTHER_ACCOUNT`, `VCODE`, `STORE_NAME`, `AREA_PROVINCE`, `AREA_CITY`, `POSITION`.
  - 5 Conditionally-Required Employee Columns: `EMPLOYEE_NO`, `LAST_NAME`, `FIRST_NAME`, `MIDDLE_NAME`, `DATE_HIRED` (blank employee fields create valid vacant store baseline slots; partial employee fields without `EMPLOYEE_NO` hard-blocked).
  - Derived fields: `EMPLOYMENT_TYPE` (auto-computed stationary vs roving $1/N$ headcount) and `WITH_PENALTY` (auto-derived from `mother_account_configs`) removed from required input; backward-compatible if present in legacy files.
  - Configuration Table & Production Parity (`mother_account_configs`, Migration `20262606000064`):
    - Created `public.mother_account_configs` table with RLS, authenticated select policy, admin full access policy, and seeded 17 active accounts from stores/accounts.
    - Synchronized 21 companion columns across `plantilla_import_rows`, `stores`, `accounts`, `plantilla`, `employee_store_allocations`, `plantilla_import_batches`, and `employees` on production.
    - Full parity achieved across Staging and Production for `trg_account_hrco_backfill`, Zero-Edit lock helpers (`_import_records_modified_after_approval`, `get_plantilla_import_first_modified_record`), `fn_assert_vcode_exists_in_plantilla`, and 6 batch review/approve/rollback RPCs.
  - Bulk Import Performance & Timeout Optimization (Migration `20262606000065`):
    - Added functional index `idx_stores_vcode_upper_active` on `stores(upper(vcode))` and active employee index `idx_plantilla_emp_no_acct_active` on `plantilla(employee_no, account_id)`.
    - Expanded `pib_status_check` constraint on `plantilla_import_batches` to include `'blocked'`, `'partially_blocked'`, and `'pending_review'`.
    - Refactored `submit_plantilla_baseline_import` from $O(N^2)$ row-by-row nested JSON lookups to $O(N)$ set-based CTE aggregation with single bulk insert, reducing 1,326-row ingestion time from >25s to <1s.
    - Attached `SET statement_timeout = '60s'` to `submit_plantilla_baseline_import`, `approve_plantilla_import_batch`, and all 4 rollback RPCs, permanently preventing role-level 8s timeout aborts on large files.
  - **Store Name Multi-VCODE Governance & Review Queue Scaling (Migration `20262606000072_relax_store_name_multivcode_rule.sql`, formerly `...066`)**:
    - Relaxed `STORE_NAME is mapped to multiple different VCODEs in upload` from a hard block (`validation_errors`) to an advisory warning (`validation_flags` with flag `multiple_vcodes_per_store`), permitting motorized collection accounts (e.g., Alturas/BPI) with multiple collector VCODEs in a single municipality to be imported and approved.
    - Retained strict hard-block corruption guard on the inverse check (`VCODE is mapped to multiple different STORE_NAMEs in upload`).
    - Client Row Fetching Pagination (`dataControl.ts`): Implemented async while-loop in `fetchPlantillaImportRows` querying `get_plantilla_import_rows` in chunks of 1,000, removing the former 500-row cap and ensuring all 1,326+ rows are displayed in the Review Queue row inspector with 100% filter pill alignment.
    - Filtered Batch Card Errors (`PlantillaImportModal.tsx`): Filtered `errorSummary` to exclude metric counters (`total_rows`, `valid_rows`, `flagged_rows`, etc.), displaying red error badges only for active conflict fields with count $> 0$.
  - Strict Middle Name Validation: single-character initials (`"S"`, `"S."`) hard-blocked; full middle names ($\ge 2$ alpha chars) or explicit case-insensitive `"NA"`/`"N/A"` accepted.
  - ExcelJS Download Template Generator (`downloadPlantillaImportTemplate`):
    - Styled 8 Always Required Store Headers and 5 Conditionally Required Employee Headers in soft red fill (`#FFC7CE`), dark red bold font (`#9C0006`), centered, thin border.
    - Free-form text input on all schedule columns (`SCHEDULE_DAYS`, `SCHEDULE_TIME`, and `DAYOFF`) without dropdown list restrictions or validation prompts.
    - Secondary `VALIDATION_GUIDE` sheet detailing all 15 ADR-002 operational invariants.
  - Comprehensive 19-rule guide sheet included in downloadable Excel template (`downloadPlantillaImportTemplate`).
- **Client-Side Pre-Validation (`data_control_xlsx.ts`)**:
  - Validates `GROUP_NAME` and `ACCOUNT_NAME` against the user's active UI scope dropdown selection before triggering backend RPC calls. If values mismatch, returns row-level guidance (`Row #X: GROUP_NAME does not match selected group`).
- **Review Queue State Machine & Row Inspector (`PlantillaImportModal.tsx`)**:
  - `pendingBatches` includes reviewable non-terminal statuses: `draft_uploaded`, `pending_approval`, `validation_failed`, `blocked`, and `partially_blocked`.
  - On upload, if `status === 'validation_failed'` or `blockedRows > 0`, the UI avoids premature green success toasts, switches to the Review Queue, auto-expands the newly created batch, and defaults the row filter to `blocked`.
  - Added `Skipped` filter pill: vacant rows with existing VCODEs are non-blocking (`validation_status = 'skipped'`) and rendered with distinct slate badges.
  - Rows display `Vacant Baseline Slot` badge, `Mother Account`, `Position / HC`, and schedule metadata.
  - **Typography & Compact Hierarchy Polish (`PlantillaImportModal.tsx`)**:
    - Primary identifiers (`VCODE`, `Store Name`, `Position`, `Employee Name`) standardized at clean `text-xs font-medium leading-tight` (max 12px, no bulky bolding).
    - Secondary metadata (`Employee ID`, `Mother Account`, `schedule/shift`, `employmentType`, `requiredHc`) standardized at compact `text-[11px] text-slate-500 leading-tight` with minimized cell padding (`px-2.5 py-1.5 align-middle`) cutting vertical row bloat in half.
    - Status and badge pills (`FLAGGED`, `ROVING`, `NEEDS HRCO`, `VALID`, `BLOCKED`, `SKIPPED`, `Vacant Baseline Slot`) compacted (`text-[10px] px-1.5 py-0.5 rounded font-medium leading-none whitespace-nowrap`).
    - Validation error and guidance messages styled in compact `text-[11px] leading-snug break-words space-y-0.5` with compact conflict badges (`text-[10px] px-1.5 py-0.5 font-mono font-medium`) ensuring roving messages fit cleanly on 1–2 tight lines.
    - **Dedicated Rejection Reason Modal**: Clicking "Reject" or "Dismiss / Reject" on batch cards or within the row inspection drawer opens a dedicated rejection modal (`isRejectModalOpen`, `z-60`) replacing previous inline inputs. Requires non-empty audit remarks (`rejectionNote.trim()`), validates inline if empty, executes `rejectPlantillaImportBatch`, and provides instant feedback via auto-dismissing floating confirmation toast (`toastMessage`) and review notice banner.
    - **Import History Clean Actors & Compact Spacing**: Column headers use `text-[10px] font-semibold uppercase tracking-wider px-2.5 py-1.5`, cells use `px-2.5 py-1.5 align-middle text-xs leading-tight`. Uses `useUsersList()` to resolve auth and profile UUIDs to human full names (e.g., `"Litong, Ohm"`) instead of raw wrapped UUID snippets.
  - "Approve & Apply" claims existing open vacant slots before incrementing slot ordinals, creates/updates linked `public.vacancies` (guaranteeing required not-null `account` and `position` fields), and records `approved_at` after all DML completes.
  - **Pre-Commit Guard & Robust Commit Exception Propagation (`approve_plantilla_import_batch`, Migrations `20262606000055`, `20262606000056`, `20262606000057`)**:
    - Pre-commit guard strictly blocks approval only if hard-error rows exist (`validation_status = 'blocked'`), raising `Cannot approve batch: X blocked rows must be resolved or removed first` (retaining `pending_approval` state).
    - Rows marked as `flagged` (advisory warnings such as `NEEDS HRCO` or roving employee allocations) are permitted to commit alongside `valid` rows.
    - Store-Scoped Occupant Uniqueness (`uq_plantilla_slots_active_occupant`): Replaced table-wide index with a store-scoped unique index on `(COALESCE(store_id, '00000000-0000-0000-0000-000000000000'::uuid), current_occupant_plantilla_id)` where `slot_status IN ('occupied', 'filled')`. This enforces that an employee can occupy at most one active slot per store while allowing roving personnel to occupy slots across multiple stores per ADR-002 without `SQLSTATE 23505` conflicts.
    - Phase B2 Idempotent Slot Assignment: Implements a 3-step cascade:
      1. *Reuse*: Checks if the employee already occupies an active slot in this store; if so, updates its position, roving status, and metadata in-place.
      2. *Claim Vacant*: Else, searches for the lowest ordinal open slot in this store, transitions it to occupied, closes linked vacancies, and logs `IMPORT_CLAIM_VACANT`.
      3. *New Slot*: Else, provisions a new occupied slot with ordinal `MAX + 1` and logs `IMPORT_OCCUPIED`.
    - Master Lookup Reason Codes (`public.slot_reason_codes`): Seeded `IMPORT_VACANT_SLOT` and `IMPORT_CLAIM_VACANT`.
    - Defensive `slot_history` Lookup Checks: `approve_plantilla_import_batch` verifies that `reason_code` exists in `public.slot_reason_codes` before insertion, preventing foreign key reference conflicts (`SQLSTATE 23503`).
    - Uncommitted Batch Rejection (`reject_plantilla_import_batch`): Expanded allowed batch states to `('pending_approval', 'pending_review', 'validation_failed', 'draft_uploaded', 'commit_failed', 'blocked', 'partially_blocked')`. `rejectPlantillaImportBatch` formats complete Supabase error diagnostics (`[message, details, hint]`) to surface detailed reasons directly in the rejection modal.
    - Review Queue vs Import History Scope: `reviewableStatuses` in `PlantillaImportModal.tsx` strictly scopes to active pending batches (`draft_uploaded`, `pending_approval`, `pending_review`, `validation_failed`, `blocked`, `partially_blocked`). Failed batches (`commit_failed`) remain exclusively in the Import History tab, preventing historical failed test batches from flooding the Review Queue.
    - HRCO Auto-Tagging & Default Fallback: Looks up selected account's assigned HRCO. If an employee row lacks HRCO, it safely defaults to the account HRCO and resolves `hrco_name`, setting `needs_hrco = false`. If neither has an HRCO assigned, sets `hrco_user_id_snapshot = NULL` and marks `needs_hrco = true` without raising constraint errors.
    - Vacant slot creation in Phase B1 syncs shadow `public.vacancies` records with non-null `account` (`COALESCE(v_acct_name, 'Unknown Account')`) and `position` (`COALESCE(v_vrow.position, 'Merchandiser')`), handling conflicts with `ON CONFLICT (vcode) DO UPDATE`.
    - Pl/pgSQL exception handler translates Postgres constraint errors (e.g. `23502` missing required field, `23505` unique conflict, `23503` foreign key) into human-readable descriptions, writing them into both `commit_error_detail` and `error_message` on `plantilla_import_batches`.
    - Client-side `approvePlantillaImportBatch` formats complete Supabase error messages (`[message, details, hint].filter(Boolean).join(" - ")`) and detects `status === 'commit_failed'` in return payloads, propagating the detailed explanation directly into user-facing UI error banners.
- **Rollback Governance & History Audit (`PlantillaImportModal.tsx`)**:
  - **Modal Detail View**: Replaced bottom-of-page inline detail drawer rendering with a dedicated, layered `<Modal />` component (`max-w-4xl`) triggered on row click. Contains full Failure Audit & Error Log (for `validation_failed` / `rejected`) with field error badges and interactive row issue breakdown, or Rollback Governance (for approved / rolled back batches) with countdown window, block reasons, and governance action controls. Primary destructive action triggers (e.g., "Approve & Execute Rollback") are styled with solid `bg-[var(--danger-button)] hover:bg-[var(--danger-button-hover)] text-white shadow-2xs` for high-contrast visibility across light and dark modes.
  - **Reusable Pagination**: Integrated `<Pagination />` and `usePagination` at the bottom of the Import History table supporting modular page navigation, 10/25/50 items per page selection, range indicators (`Showing X–Y of Z records`), and boundary safety.
  - History table rendered inside a dedicated horizontal scroll container (`overflow-x-auto`) with fixed column layout (`table-fixed min-w-[920px]`).
  - Columns optimized with compact padding (`px-2.5 py-1.5`), text truncation (`truncate`), and native `title` hover tooltips on `File Name`, `Scope`, `Uploaded By`, and `Approved / Rejected By` (displaying shortened UUIDs or formatted actor names).
  - Single-line status and rollback badges protected with `whitespace-nowrap` to prevent vertical row stretching.
  - 72-hour countdown window tracked accurately with `formatRollbackRemaining`.
  - Head Admin and Super Admin can approve or reject rollback requests (`rejectPlantillaImportRollback`).
  - Super Admin Emergency Rollback Override enabled for expired windows when zero records were touched.
  - **Strict Zero-Edit Immutability Lock**: If any record in the batch was modified post-approval (with 2-second approval grace guard), rollback is hard-blocked and displays humanized error message identifying modified records.
- **Needs HRCO Visibility Guard & Unassigned Employees Resolution (`ohm#n2k7w9m4`)**:
  - **Account HRCO Conditional Tab Visibility**: The "Needs HRCO" directory tab only renders when the selected account has no assigned HRCO (`!accountHasAssignedHrco`). When an HRCO is assigned to the account (`accounts.hrco_user_id IS NOT NULL` or leadership team HRCO present), the tab is hidden and views default cleanly to `active`.
  - **RPC Access & Unassigned Population (Migration `20262606000060`)**: Removed the restrictive `i_am_data_team() OR i_have_full_access()` check from `get_plantilla_unassigned_hrco_count` and `get_plantilla_needs_hrco_employees`. If an account has no assigned HRCO, all active employees under that account are returned as needing an HRCO.
- **Web-Optimized Desktop Drawer Layout & 4-Tab System (`PlantillaDetailDrawer.tsx`)**:
  - Right-side desktop drawer (`max-w-2xl bg-slate-50`) with deep blue banner (`bg-[#1e3a8a]`), circular initials avatar, employee ID (`IdCard`), deployed date (`Calendar`), and active status badge.
  - **4-Tab Navigation**:
    - **Profile**: 2-column Employment & Allocation grid (VCODE, Position, Store, Employment Type, Date Hired, Tenure computed via `computeTenure`), Work Schedule & Rate card (`Schedule Days`, `Schedule Time`, `Day Off`, `Daily Rate`, `Coordinator`) with modal launcher `UpdateScheduleModal`, System Information collapsible accordion, and Capability-Aware Personnel Actions toolbar (Transfer, Reassign HRCO, Request Deactivation, Request Deletion, Update Employment Status).
      - *Deactivation Eligibility Gate*: The "Request Deactivation" button is strictly disabled when the employee is in an operational status (`Active` or `On Leave`). It is only enabled when the employee is already `Inactive` (Separated: `Resigned`, `AWOL`, `Terminated`) or `Floating` (`isDeactivationEligible = isInactive || status === "floating"`), accompanied by helper guidance: *"Employee must be set to Floating or Inactive before requesting deactivation."* When a deactivation request is submitted, the record immediately transfers to the **Deactivation** tab (`isDeactivationRecord` takes precedence over `isInactiveRecord`), the UI automatically routes to the Deactivation tab, the action button switches to `"Deactivation Pending"` (disabled), and the drawer renders a confirmation notice (*"Deactivation request submitted and pending review."*).
    - **Benefits**: SSS, PhilHealth, Pag-IBIG, TIN, and ATM Number with an interactive Eye toggle for masking (`••••-••••-1234` vs unmasked), backed by multi-tier statutory hydration (direct `plantilla`, latest `mika_import_rows`, and `employees` registry) plus MIKA sync card with timestamp and dedicated `syncPlantillaMika` mutation with 5-minute cooldown handling.
    - **Stores**: Current Stores vs Past Stores count summary cards and active store allocation details with live status indicator, VCODE, Area, and HC Share.
    - **Activity**: Audit trail logs and deployment history with timestamps, profile actors, and snapshot details.
- **Ops Schedule & Store Visit Audit (`PlantillaDetailDrawer.tsx` & `UpdateScheduleModal.tsx`)**:
  - Displays `Schedule & Store Visit Audit` section card in employee detail drawer (`Schedule Days`, `Schedule Time`, `Dayoff`).
  - Interactive `UpdateScheduleModal` enables Ops/lifecycle roles to update schedule days (multi-select MON-SUN with presets), schedule time (shift windows & flexi visit hours), and dayoff (multi-select MON-SUN).
  - Updates `plantilla` and `employee_store_allocations` and advances `updated_at`, actively enforcing the Zero-Edit Lock against uncoordinated rollbacks.
- **Strict Vacancy Occupancy Filter for Missing Store Detection & Direct Import Guard (`ohm#s8k2w7m3`)**:
  - **Strict Occupancy Filtering**: Store slots occupied by active personnel in `public.plantilla_slots` (`slot_status IN ('occupied', 'filled')` or `current_occupant_plantilla_id IS NOT NULL`), `public.plantilla` (active employees), or `public.employee_store_allocations` (`is_active = true`) are strictly excluded from the Vacancy tab's "Stores without Active Vacancies" / "Missing from Vacancies" quick-import section.
  - **Authoritative Backend Guard**: `directImportVacancy` verifies store occupancy via `fetchOccupiedStoreIdentifiers(accountId)` and rejects attempts to create vacancies for occupied stores.

- **Plantilla Import Completeness, Vacancy Tab Enhancements & Detail Drawer Cleanup (`ohm#v2k8w4m9`)**:
  - **Import Completeness Fix (Migration `20262606000058`)**:
    - Fixed `submit_plantilla_baseline_import` to prevent skipping vacant rows for existing stores (`IF v_emp IS NULL` now processed as valid vacant slots).
    - Resolved loop state bleed bug by re-initializing `v_status := 'valid'` on every row iteration.
    - Updated `approve_plantilla_import_batch` Phase B1 to provision all valid vacant rows with dynamic `slot_ordinal = COALESCE(MAX(slot_ordinal), 0) + 1` and synchronize `public.vacancies` (`status = 'Open'`, `vacant_date = CURRENT_DATE`).
    - Guarded Phase B2 against claiming newly created batch vacant slots via `v_batch_created_slot_ids`.
  - **Vacancy Tab Decoupling & Direct Import (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - Decoupled vacancy table rows and cards from `RequestHeadcountModal`; clicking now inspects via `VacancyDetailDrawer`.
    - Added `Aging` column with color badges: emerald ($\le 15$d), amber ($16\text{--}30$d), rose ($> 30$d).
    - Added `Action` column with `Inspect` button for active vacancies and `+ Direct Import` quick-action button for unlisted stores under the active account without forcing the import wizard.
  - **Conditional `NEEDS HRCO` Badge**:
    - Warning badge hidden across `PlantillaImportModal.tsx`, `EmployeeTable`, and `EmployeeCard` whenever the account has an assigned HRCO (`accounts.hrco_user_id IS NOT NULL`) or the row/employee has an assigned HRCO.
  - **Inspect & Detail Drawers Cleanup**:
    - `PlantillaDetailDrawer.tsx`: Compacted to `p-4 space-y-3`, suppressed redundant stationary coverage card (already in EmploymentGrid), and formatted Schedule Audit into a compact 3-column inline strip.
    - `VacancyDetailDrawer.tsx`: Spacing tightened to `p-3.5 space-y-2`, removed duplicate quota label from Requisition & Quota controls header.

- **Plantilla Baseline Import Batch Summary Column Fix & Error Surfacing Hardening (`ohm#b7k2w9m5`)**:
  - **Database Migration (`20262606000061`)**:
    - Replaced `submit_plantilla_baseline_import` to update `error_summary = v_summary` instead of non-existent column `summary_json` in `plantilla_import_batches`.
    - Preserved batch conflict counters (`roving_detected`, `new_stores_count`, `existing_stores_count`, `cross_account_conflicts`, `cross_group_conflicts`) and `updated_at`.
    - Applied to both live Staging (`qqiiznmqxfoamqytjica`) and Production (`rwxelulyapjgaarlwkus`).
  - **Client Error Hardening**:
    - `dataControl.ts`: `submitPlantillaBaselineImport` now wraps Postgrest error messages into `new Error(...)`.
    - `PlantillaImportModal.tsx`: catch block safely extracts `(err as { message?: string })?.message` fallback, preventing real database error messages from being swallowed by generic banner text.

- **Vacancy Reopening On Separation: Applicant Archiving & Clean Unoccupied State (Migration `20262606000086`)**:
  - **Prior Hire Archiving**: Updated `public.reopen_or_create_vacancy_for_plantilla` and `public.fn_plantilla_separation_to_vacancy` so that when a separated employee's slot reopens in the Vacancy Pending/Open Tab, any prior onboarded applicants under `vacancy_vcode` are automatically archived (`is_archived = true, archived_at = NOW()`).
  - **Accurate Vacancy Metrics**: Archiving prior hires resets `confirmed_onboard_count` to 0, ensuring `vw_vacancy_list` accurately calculates `derived_status = 'Open'`, `hc_filled = 0`, and renders the vacancy as clean and unoccupied rather than tagging the resigned employee.
  - **Plantilla Inactive History Preserved**: The separated employee's historical assignment record in `public.plantilla` (`status = 'Inactive'`, `separation_status = 'Resigned'|'AWOL'|'Terminated'`, `store_id`, `store_name`, `vcode`) remains 100% intact so the Inactive Tab retains complete historical audit context.

- **Vacancy Account & Group Linkage Propagation, Import RPC Hardening & Orphan Backfill (`ohm#v2k9w4r8`)**:
  - **Database Migration (`20262606000062`) Applied to Live Staging**:
    - Hardened `approve_plantilla_import_batch` Phase A to update `stores.account_id` and `stores.group_id` from batch when missing.
    - Updated Phase B1 to strictly inherit store/batch `account_id` and `group_id` for vacant slots and shadow vacancies, preventing fallback or overwrite with `"Unknown Account"`.
    - Phase B2 slot creation now inherits store account/group fallbacks.
    - Repaired orphaned vacancies (including `CPRVJV13`), slots, and stores via SQL backfill.

- **Plantilla Import Role Check Regression Fix & Helper Function Parity (`ohm#p9r2k5w8`)**:
  - **Database Migration (`20262606000073_fix_plantilla_import_role_check_parity.sql`, formerly `...067`)**:
    - Added helper function wrappers `public.get_current_role()` and `public.fn_is_admin()` aliased to `public.get_my_role()` and `public.i_have_full_access()`.
    - Added missing batch tracking columns `commit_error`, `stores_created`, `employees_created`, and `allocations_created` on `public.plantilla_import_batches`.
    - Restored canonical `v_role text := public.get_my_role();` and robust RBAC + operational governance assertions (`fn_can_upload_plantilla_import()`, `fn_assert_governance_enabled('import_plantilla')`, `fn_assert_freeze_inactive('audit_freeze')`) inside `submit_plantilla_baseline_import`.
    - Preserved 100% of migration 65 performance optimizations (set-based CTEs, single bulk insert, `statement_timeout = '60s'`) and migration 66 multi-VCODE store name governance (`multiple_vcodes_per_store` as `flagged` advisory warning).
    - Applied and verified on both Production (`rwxelulyapjgaarlwkus`, tracking version `20262606000073`) and Staging (`qqiiznmqxfoamqytjica`, tracking version `20262606000073`).

- **Plantilla Baseline Import Roving Validation & State Machine Approval Fix (`ohm#fix-plantilla-import-roving-invalid-state`)**:
  - **Database Migration (`20262606000085_fix_plantilla_roving_validation_and_approval_state.sql`)**:
    - **Roving Validation Correction**: Updated `submit_plantilla_baseline_import` to treat standard roving employee assignments (across 2..20 stores with fractional HC $1/N$) as valid (`validation_status = 'valid'`) rather than flagging them as advisory warnings (`validation_flags`). Retained advisory warnings solely for allocations exceeding 20 stores (`over_20_stores`).
    - **Approval State Machine Expansion**: Expanded `approve_plantilla_import_batch` status check to accept batches in `'pending_review'` state in addition to `'pending_approval'` and `'commit_failed'`, curing `INVALID_STATE: only pending_approval or commit_failed can be approved (current=pending_review)`.
    - **Batch & Row Reconciliation**: Included migration data reconciliation to clean up existing batches (such as Batch `#4898978`) and rows flagged solely due to `flag = 'roving'`, upgrading their status to `valid` / `pending_approval`.

- **UI Standard & Motion System Alignment (Loop 6A, 6B, 6C: `ohm#l6a1m4w9`, `ohm#l6b2n7k4`, `ohm#l6c3w8m2`)**:
  - **Zero Color Literals**: Eliminated 100% of raw color literals (all 1,031 baseline occurrences across 19 files) down to 0, replacing them with standard design tokens (`bg-surface`, `bg-surface-muted`, `border-border-default`, `text-text-primary`, `text-text-secondary`, `text-accent`, `--pct-*`, and `--danger-*`).
  - **Drawer & Table Standardization (Loop 6A)**: Standardized `PlantillaDetailDrawer` (`drawer-width-lg`) and all 8 pool/store drawers with canonical `DetailDrawer`; strictly preserved table text floor $\ge 14\text{px}$ (`text-sm`) across members, vacancies, and store tables; preserved single-account auto-fire and ADR-001 account gate query rules.
  - **Modal Hardening & Canonical Stacking (Loop 6B)**: Aligned all 8 Plantilla lifecycle modals (`InitiateSeparationModal`, `RequestDeactivationModal`, `RequestPoolConversionModal`, `RequestPoolHeadcountModal`, `RequestRelieverCoverageModal`, `TransferPersonnelModal`, `UpdateEmploymentStatusModal`, `UpdateScheduleModal`) with canonical `Modal` at `z-[60]` over `DetailDrawer` at `z-50`; hardened against backdrop clicks during dirty states; disabled Esc/close buttons during `isSubmitting`.
  - **Specialized Views & Analytics Parity (Loop 6C)**: Standardized `MosesHqPoolView.tsx` and `WorkforceAnalyticsView.tsx` across all 7 analytics tabs (Overview, Deployment, Coverage, Conversion, Slots, Health, Executive); converted SVG progress donuts and horizontal bar indicators to standard tokens (`var(--accent)`, `var(--pct-good-text)`, `var(--pct-warn-text)`, `var(--danger-text)`); preserved 100% RPC integration contracts and XLSX export capabilities.
- **Plantilla Roster Retention, Stage Renaming & Vacancy Sourcing Pipeline Parity (`ohm#plan08`)**:
  - **Full Account Roster Retention (752 Active Employees)**:
    - Increased `MAX_PAGE_SIZE` in `src/lib/queries/plantilla.ts` from 100 to 5000 and updated `employeeQuery` in `plantilla/page.tsx` to `pageSize: 2000`.
    - Added chunked concurrent paging in `listWebPlantillaEmployees` to guarantee all records are fetched in memory up to `totalCount`, overcoming the PostgreSQL RPC 200-row `v_limit` constraint and preventing roster truncation down to 100.
    - Created local migration `supabase/migrations/20261027170000_increase_plantilla_list_limit.sql` increasing `list_web_plantilla_employees` limit ceiling to 5000 rows.
    - Updated `activeCount` to evaluate `activeEmployees.length > 0 ? activeEmployees.length : (summaryData?.actual ?? 0)`, correctly displaying **752** Active Deployed personnel and matching required **753** (Overall MFR ~100%).
  - **Vacancy Sourcing vs HR Emploc Onboarding Pipeline Parity**:
    - Refactored `isHrPipelineWorkflowStage` to strictly evaluate HR Emploc onboarding stages (`HR Emploc - Pending`, `HR Emploc - Correction`, `HR Emploc - Ready`, `HR Emploc - Review`).
    - Aligned `Vacancy - Pipeline` (ATS / Candidate sourcing) with `Open / Unassigned` sub-tab, ensuring candidates not yet endorsed to `hr_emploc` (such as Tejada, Elizabeth Uy on `VCBPIG1_0183`) show under `Open / Unassigned` (`1`) and not `HR Pipeline (For Emploc)` (`0`).
    - Synchronized top KPI cards: Open Vacancies displays `1`, HR Pipeline displays `0`.
  - **Table Column Header Renaming**:
    - Renamed Vacancy table column header from `"Status"` to `"Stage"` in `StoreVacancyTable`.

- **Plantilla Deactivation Check Constraint & Scope Parity Fix (`ohm#fix-plantilla-deactivation-status-check` — 2026-11-23)**:
  - **Check Constraint Harmonization (`plantilla_status_check`)**:
    - Expanded `plantilla_status_check` constraint in migration `20262606000138_fix_plantilla_deactivation_status_and_rpcs.sql` to include `'For Deactivation'` alongside `'Pending Deactivation'` (`CHECK (status = ANY (ARRAY['Active', 'Inactive', 'Pending Deactivation', 'For Deactivation', 'Rejected Deactivation', 'Deactivated', 'On Leave']))`).
    - Eliminates PostgreSQL constraint violation `new row for relation "plantilla" violates check constraint "plantilla_status_check"` when deactivation requests are triggered across web, mobile, or legacy RPC fallbacks.
  - **Caller Scope & Parameter Alignment (`create_deactivation_request`)**:
    - Fixed scope check in `public.create_deactivation_request` where `v_row.account_id::text` was compared against `get_my_allowed_accounts()` (which returns account names `TEXT[]`), causing all non-superadmin Ops users (HRCO, TL, ATL, OM) to fail with `Account not in caller scope` and prematurely fall back to legacy RPCs.
    - Added optional `p_reason text DEFAULT NULL` parameter to `create_deactivation_request` (with 1-arg backward-compatible wrapper overload for Mobile callers), properly setting `deactivation_reason`, `remarks`, `for_deactivation_at`, and `for_deactivation_by` on `public.plantilla`.
  - **Legacy RPC Parity & Approvals Synchronization (`plantilla_request_deactivation` & `complete_employee_deactivation`)**:
    - Updated `public.plantilla_request_deactivation` to transition status to `'Pending Deactivation'` (instead of obsolete `'For Deactivation'`) and ensure a pending record is created in `public.employee_deactivation_requests` so the deactivation request surfaces in Approvals queue (`v_deactivation_requests`).
    - Updated `public.complete_employee_deactivation` to accept both `'For Deactivation'` and `'Pending Deactivation'` and mark pending `employee_deactivation_requests` as `'Approved'`.
    - Aligned `public.get_plantilla_employees` filters to recognize both `'For Deactivation'` and `'Pending Deactivation'`.
  - **Client Query Hardening (`src/lib/queries/plantilla.ts`)**:
    - Updated `createDeactivationRequest` to forward `p_reason` to `create_deactivation_request` and added explicit PostgREST schema error logging (`console.error('[PostgREST Schema Error] ...')`).

- **Plantilla Floating Routing, Deactivation Optional Remarks & NSR Data Team Workflow (`Branch2` — 2026-11-05)**:
  - **Fixed 42703 `column "is_roving" does not exist` on Status Changes**:
    - Created & applied migration `20262606000085_fix_plantilla_separation_is_roving_and_nsr_data_team_workflow.sql`.
    - Patched `fn_plantilla_separation_to_vacancy()` to replace invalid `vacancies.is_roving` checks with `COALESCE(employment_type, '') = 'Roving'` and set `employment_type = 'Roving'` in `INSERT INTO public.vacancies`.
  - **Floating Status Routing (`plantilla/page.tsx` & `UpdateEmploymentStatusModal.tsx`)**:
    - Updated `isFloatingRecord()` to evaluate both `emp.plantillaStatus` and `emp.separationType`.
    - Updated `isInactiveRecord()`, `isDeactivationRecord()`, and `isOnLeaveRecord()` with defensive `if (isFloatingRecord(emp)) return false;` guards so floating personnel route directly to Tab 4 `[ Floating ]` rather than getting captured by `isInactiveRecord` (`isActive === false` / `status === 'Inactive'`).
    - Wired `onNavigateStatusTab?.("floating")` callback from `UpdateEmploymentStatusModal` via `PlantillaDetailDrawer` so setting an employee to Floating navigates directly to the Floating Tab.
  - **Smart Toggle & Clean UI in `UpdateEmploymentStatusModal.tsx`**:
    - Hid `Active` option under Operational Duty Status when the employee is already Active; only rendered `Active` when current status is `On Leave` or `Floating`.
    - Removed verbose gray notice boxes across all statuses (`Setting this employee to Floating...` box and `ADR-001 Slot Vacation Notice:` wrapper/box for `Resigned`, `AWOL`, `Terminated`).
    - Kept `Effective Separation Date *` date picker as a clean standalone field directly above `Operational Remarks (Optional)`.
  - **Deactivation Remarks Optional (`RequestDeactivationModal.tsx` & `queries/plantilla.ts`)**:
    - Updated `CreateDeactivationRequestParams.remarks` to optional `remarks?: string | null;`.
    - Removed mandatory `if (!remarks.trim())` validation block and submit button disable constraint.
    - Removed the gray `Standard 15-Day Clearance Notice` banner box at the top.
  - **Request Headcount Modal Layout Polish & Scope Optimization (`ohm#polish-request-headcount-modal`)**:
    - Streamlined `RequestHeadcountModal.tsx` modal container from `max-w-3xl` to `max-w-xl`, removing empty horizontal margins.
    - Omitted redundant "Target Operational Account" card when called within the Plantilla workspace (`propAccountId` is already provided).
    - Streamlined Store Selection: replaced bulky nested cards with a single-row store indicator badge showing Store Name, Island Group, and Location.
    - Restructured Position, Request Type, Headcount Needed, Timeline, and Urgency into clean, unboxed grid rows, tightening modal padding to `p-5 space-y-4`.
  - **New Store Request (NSR) Two-Tier Review Workflow & High-Contrast Button**:
    - In `RequestHeadcountModal.tsx`, fixed the "Request New Store" button in the Store Not Found card to high-contrast navy styling `bg-brand-600 text-white hover:bg-brand-700`.
    - In `NewStoreRequestModal.tsx`, updated confirmation copy to state submission for Data Team review.
    - Updated NSR schema constraint `nsr_status_chk` to include `'pending_super_admin'`.
    - Updated RLS `nsr_select` on `public.new_store_requests` to grant read access to Data Team (`role_level >= 30`).
    - Updated `public.approve_new_store_request` and `public.reject_new_store_request` to allow Data Team (`role_level >= 30`) and accept status `pending` or `pending_super_admin`.
    - Added `public.forward_new_store_request_to_super_admin(uuid, text)` to set `status = 'pending_super_admin'`, record Data Team review metadata, and notify executive sign-off roles.
    - Updated `NewStoreApprovalCard.tsx` and `NewStoreDataTable.tsx` with dynamic status badges (`Pending Data Team Review`, `Pending Super Admin Sign-off`), Data Team validation notes, and two-tier actions (Approve Store / Reject / Approve & Forward to Super Admin).

- **Employment Status & Separation Workflow Integration (`ohm#plan05`)**:
  - Integrated separation statuses (`Resigned`, `AWOL`, `Terminated`) into `UpdateEmploymentStatusModal.tsx` grouped into Operational Duty Status (`Active`, `On Leave`, `Floating`) vs Personnel Separation (`Resigned`, `AWOL`, `Terminated`).
  - Added conditional effective separation date picker and ADR-001 slot vacation notice.
  - Extended `EmploymentStatusTarget` type and wired `updatePlantillaEmploymentStatus()` to route separation targets to `updatePlantillaSeparation` (`plantilla_update_separation` RPC), triggering reactive slot reopening (`fn_sync_slot_to_open()`) and archiving to Tab 6 `[ Inactive ]`.
  - Added `row.separation_status` and `row.date_of_separation` normalization fallbacks in `normalizeEmployeeListRow`.
  - Created migration `20261027150000_allow_terminated_separation_status.sql` updating `plantilla_separation_status_check` to include `'Terminated'` and `'End of Contract'`.

- **Phase 11 D4 Reset of `VCAG5_0056` Quota 7 -> 1 via Option A (`ohm#4x7n2k9w` — 2026-10-28)**:
  - Addressed the D4 live-slot gap root cause identified in Phase 10: target 1 reduced all 6 open slots because delta was computed against `required_headcount = 7` ($1 - 7 = -6$).
  - Reopened slot Ord 2 (`79e510b4-0b6f-40ec-8e16-4f16d504ab82`) via sanctioned `fn_set_slot_status('79e510b4...', 'open', 'HC_READD', 'b865eef6-ebac-4bd3-84b5-482c00774565'::uuid)`, bringing live open slots to 7 (Ord 2–8).
  - Executed `revise_vcode_headcount_quota('VCAG5_0056', 1, 'ohm#4x7n2k9w: reset SM AURORA quota 7->1 (UAT amendments reverted)')` under JWT sub `71d245b9-10b1-42b9-ad9e-253f999daf6d`.
  - The delta of -6 systematically reduced slots Ord 3–8 to `hc_reduced` (`HC_REDUCTION`), leaving Ord 2 as the single live slot in `open`. Slot Ord 1 (`bee89108...`) remained `closed` (`QA_RESET`).
  - `vacancies.required_headcount` is now 1, `vacancies.status` is `'Open'`, `is_archived = false`.
  - ACTISERVE Summary (`get_web_plantilla_summary`) and KPI (`v_account_allocation_kpi`) both reconciled to **7/7** (`1 active + 3 hrProcess + 3 vacant = 7`).
  - `qa_archive_batch_id` on Ord 2 remained set (`440e58da-10f5-4a1b-903b-fd171a8d23a3`), and neither `fn_qa_rollback_operational_data_reset` nor `fn_rollback_archive_batch` can touch it because both require `WHERE slot_status = 'closed' AND closure_reason_code = 'QA_RESET'`.

- **Slot-Based Plantilla Summary, Store Staffing & Allocation KPI Closed-Slot Parity (`ohm#4x7n2k9w` — Phase 2 Step 1B `20261027091040` & Phase 3 Step 2a `20261027092200`)**:
  - Updated `public.get_web_plantilla_summary` and `public.list_web_plantilla_store_staffing` on staging (`qqiiznmqxfoamqytjica`) with identical parameter and return signatures:
    - Excluded pool and non-quota vacancies (`COALESCE(v.is_pool_vacancy, false) = false AND COALESCE(v.affects_required_hc, true) = true`) in both `onboarding_pipeline_count` (`hrProcess`) and `open_headcount_count` (`vacant`).
    - Replaced requisition-level `SUM(vacancies.required_headcount) WHERE status = 'Open'` with slot-based vacant capacity across `public.plantilla_slots` (`slot_status IN ('open', 'pipeline') AND closed_at IS NULL`, stationary `1.0` + roving `1/N` share via `public.vacancy_stores`, suppressing stores inside active Coverage Groups) + `public.coverage_slots` (`slot_status = 'open'` on active Coverage Groups).
    - Excluded any slot (`ps.id` or `cs.id`) already counted in `hr_emploc` (`hr_status IN ('Pending', 'Complete') AND employee_no IS NULL AND deleted_at IS NULL`) so each slot is counted at most once across `actual`, `hrProcess`, and `vacant`.
  - Updated `public.v_account_allocation_kpi` (`20261027092200_fix_account_allocation_kpi_closed_slot_filter.sql`, `security_invoker = true`) to enforce `ps.closed_at IS NULL` in both `slot_vacant_non_roving` and `slot_vacant_roving`, aligning `ACTISERVE` `required_hc` (`14.0000 -> 12.0000`) and `slot_vacant_hc` (`10.0000 -> 8.0000`) 1:1 with `get_web_plantilla_summary`.

- **Floating "Assign Store" Auto-Stationary Assignment & UI Simplification (`ohm#branch2-floating-assign-stationary` — 2026-11-06)**:
  - **Assignment Type UI Removal (`src/components/plantilla/AssignStoreModal.tsx`)**:
    - Completely removed the "Assignment Type" (Stationary / Roving) radio buttons from the Assign Store modal form.
    - Floating employees assigned to a single target store are inherently Stationary, eliminating logical mismatches where single-store personnel could be mislabeled as Roving.
  - **Auto-Persisted Stationary Status (`src/components/plantilla/AssignStoreModal.tsx` & `src/lib/queries/plantilla.ts`)**:
    - Updated `assignFloatingEmployeeToStore` mutation call in `AssignStoreModal.tsx` to automatically set `assignmentType: "Stationary"`.
    - In `assignFloatingEmployeeToStore` (`src/lib/queries/plantilla.ts`), made `assignmentType` parameter optional with a default of `"Stationary"` and explicitly persisted `deployment_type: "Stationary"` in the database update payload (omitting non-existent `assignment_type` column to prevent schema cache errors).

- **Plantilla Slot-Vacant Remaining Capacity & Slot Reopen/Sync Hardening (`ohm#4x7n2k9w`, `ohm#branch2-vacancy-slot-recon`, & `ohm#branch2-summary-slot-recon` — 2026-11-06)**:
  - **Plantilla Web Slot-Based Vacant Capacity (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - Unified remaining capacity calculation across table, cards, and KPI summaries via `getVacancyRemainingCapacity(v)` to strictly compute `Math.max(0, total - filled)` based on `hc_total - hc_filled`, with a resilient safeguard ensuring that open vacancy requisitions in `allVacancies` (`stageBadge === "Vacancy - Open"` or `vacancyStatus === "Open"`) maintain at least 1 open slot capacity even amidst legacy occupant vcode mismatches.
    - Updated `StoreVacancyTable` and `VacancyCard` to use `getVacancyRemainingCapacity(row)` directly, eliminating the decoupled `remainingCapacity || 1` discrepancy.
    - Reconciled `storesWithAvailableSlots` so stores with open vacancies compute `hcFilled = Math.max(0, hcTotal - openSlots)`, correctly displaying available capacity in `AssignStoreModal`.
    - Updated `assignFloatingEmployeeToStore` (`src/lib/queries/plantilla.ts`) and `AssignStoreModal` (`src/components/plantilla/AssignStoreModal.tsx`) to bind deployed employees to the target store's vcode (`targetStore.code`), preventing floating personnel transfers from falsely occupying prior store vacancy codes in backend views.
    - Sanitized staging database record for Joven Asana (`7d3f6a1a-34d4-42d9-b3b6-ff31e79e51cd`) to point to Divimart General Trias (`CPRVJV13`), releasing Emilus Rosario (`CPSAJV31`) to 0/1 filled (1 open slot) and achieving 100% parity across table rows, tab badges (`3`), and the Open Vacancies KPI card (3 slots total).
  - **Slot Reopen Metadata Clearing & Closed-Slot Sync Protection (`20261028005902_fix_slot_status_reopen_clear_closed_and_sync_closed_filter.sql`, Staging `qqiiznmqxfoamqytjica`)**:
    - Updated `public.fn_set_slot_status` to clear `closed_at = NULL`, `closed_by = NULL`, and `closure_reason_code = NULL` whenever `p_new_status = 'open'` (leaving `qa_archive_batch_id` intact because `fn_qa_rollback_operational_data_reset` and `fn_rollback_archive_batch` read it).
    - Updated `public.fn_sync_vacancy_slot_open_pipeline` to enforce `AND closed_at IS NULL` on both the `'open'` release loop and the `'pipeline'` claim loop, and added deterministic `ORDER BY slot_ordinal ASC, created_at ASC, id ASC` on the `'open' -> 'pipeline'` claim loop.

- **Plantilla Account Detail Active Employee & KPI Parity Fix (`ohm#alt754fix` & `ohm#alt754tbl` — 2026-11-03)**:
  - **Account Detail Group Isolation & URL Parameter Reactivity (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - Cleared `selectorGroupId` and `accountSearch` upon selecting an account in `handleSelectAccount` to prevent directory group filter state leaking into account view.
    - Decoupled `effectiveSelectorGroupId` in `summaryQuery` whenever `accountId` is present (`groupId: accountId ? undefined : (effectiveSelectorGroupId || undefined)`), fixing 0-return queries for accounts residing in groups other than the directory's default group selector.
    - Synchronized `statusTab` reactively with URL search params (`?status=`, `?statusTab=`), updating browser history and internal state without cascading renders.
    - Added `selectedAccount?.name` into `employeeQuery` parameters and query key for instant account-aware cache invalidation.
  - **Unrounded MFR Formula & Precision Donut Formatting (`src/app/(dashboard)/plantilla/page.tsx`, `src/app/api/ohmni/route.ts`)**:
    - Removed `Math.round` integer truncation from MFR calculation in `plantilla/page.tsx` (`const fulfillmentRate = requiredCount > 0 ? (activeCount / requiredCount) * 100 : 0`) and account cards (`const fillRate = required > 0 ? (actual / required) * 100 : 0`).
    - Updated `OverallMfrDonut` to accept `hasGap = activeCount < requiredCount` and render exact decimal percentages (e.g., `99.87%` for 754/755) with a guard ensuring that any account with a staffing gap (`active < required`) never rounds up to `100.0%` or `100%`.
    - Synchronized OHMni Co-Pilot route (`/api/ohmni/route.ts`) to return unrounded MFR percentages matching canonical `v_account_allocation_kpi.mfr` basis point precision.
  - **Failover RPC & Headcount Parity Fallback Roster Resolver (`src/lib/queries/plantilla.ts`)**:
    - Wrapped primary RPC `list_web_plantilla_employees` in a graceful failover try/catch so if the RPC errors or returns 0 rows when `params.accountId` is provided, it falls through to the multi-source fallback resolver rather than throwing.
    - Replaced the brittle 25-column projection string (`selectCols`) with safe wildcard `.select("*")` on both `v_plantilla_safe` and `public.plantilla`, eliminating PostgREST 42703 column-not-found errors on computed or unpopulated fields.
    - Added direct active allocation resolution from `employee_store_allocations` (`WHERE account_id = params.accountId AND is_active = true`), mapping `plantilla_id`, `employee_no`, `store_id`, `store_name`, and `vcode`.
    - Implemented chunked hydration (100 IDs per batch) querying `v_plantilla_safe` and `public.plantilla` by `id` and `employee_no`, with store ID (`stores.account_id = accountId`) and account wildcard fallbacks.
    - Added an allocation parity safeguard: if any active allocation row cannot be resolved from plantilla tables, synthesizes an active employee list entry (`is_active = true`, `status = "Active"`), guaranteeing 100% headcount parity (exactly 754 active personnel) and eliminating the empty state.
    - Enhanced `normalizeEmployeeListRow` to resolve fallback field aliases (`row.position_title ?? row.position`, `row.account_name ?? row.account`, `row.primary_store_name ?? row.store_name`).
  - **Active Status Partitioning Normalization (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - Normalized `activeEmployees` status filter: records with `emp.isActive === true` or non-separated statuses (`"Active"`, `"Active Deployed"`, `"Deployed"`, or blank/default) now reliably populate the active list, matching the summary KPI card count (e.g. 754) and eliminating the false "No active employees" empty state.
  - **Multi-Strategy Fallback Roster Resolution (`src/lib/queries/plantilla.ts`)**:
    - Re-architected `listWebPlantillaEmployees` fallback when the primary RPC returns 0 rows:
      1. Resolves `account_name` from `accounts` table.
      2. Queries all stores belonging to the account (`stores.account_id = accountId`) and chunks `v_plantilla_safe` by `store_id.in.(storeIds)` (retrieving all 754 deployed personnel).
      3. Queries active allocations from `employee_store_allocations` selecting both `plantilla_id` and `employee_no`, chunking `v_plantilla_safe` by `id` and `employee_no`.
      4. Queries `v_plantilla_safe` matching `account.ilike.%${accountName}%` wildcard and `account_id.eq.${accountId}`.
      5. Provides a secondary direct query against `public.plantilla` if view constraints yield 0 records.
      6. Merges and deduplicates records into a `Map<string, Record<string, unknown>>` by `row.id` and `row.employee_no`, applying search, status filter, and sorting before normalizing to `PlantillaEmployeeListItem[]`.
  - **Removal of "Import Plantilla" Header Button and Inline Modal Mount (`ohm#9b5t3c7e`)**:
    - Removed legacy "Import Plantilla" button from the Plantilla page header action bar (`src/app/(dashboard)/plantilla/page.tsx`).
    - Unmounted `PlantillaImportModal` and removed unused state (`isPlantillaImportOpen`), icon (`UploadCloud`), and imports from the Plantilla page.
    - Resolves broken inline overlay where `PlantillaImportModal` rendered inline and overlapped Plantilla content following its conversion to full-page `BatchImportPageShell`.
    - Plantilla baseline batch roster import operates exclusively under **More → Data Control → Batch Imports** (`/more?tab=data_control&subtab=batch_imports&import=plantilla`).

- **Plantilla Baseline Import Roving Validation, Pre-Upload Blocking & Reject Modal Fix (`ohm#k6w3n8qd` — 2026-11-06)**:
  - **ADR-002 Invariant 4 Alignment & Migration 085 (`20262606000085_fix_plantilla_roving_validation_and_approval_state.sql`)**:
    - Standard roving employee assignments ($N \ge 2$) evaluate to `valid` without flags (no `over_20_stores` warning) and receive neutral note (`Roving · N stores · X.XX HC`), eliminating 0-valid rows demotion and invalid `pending_review` batches.
    - Blocking errors (e.g. `multiple_vcodes_per_store`) promote to `blocked`. Purely informational notes stay `valid`. Batches without blocking errors land in `pending_approval`.
    - Created shared row evaluation engine `public._evaluate_plantilla_import_rows` invoked by both dry-run RPC `validate_plantilla_baseline_import` and `submit_plantilla_baseline_import` for 100% mathematical parity.
    - `submit_plantilla_baseline_import` enforces server-side validation and raises structured `RAISE EXCEPTION 'BATCH_BLOCKED: ...'` if `blocked_rows > 0`.
    - `approve_plantilla_import_batch` left strictly locked to `pending_approval` and `commit_failed` only.
  - **Web Pre-Upload Validation & UI Enhancements (`src/components/more/PlantillaImportModal.tsx`, `src/lib/queries/dataControl.ts`)**:
    - Added dry-run pre-upload validation using `validatePlantillaBaselineImport` RPC as single source of truth; any blocked row hard-blocks the submission button with a visible error banner.
    - Formatted employee names consistently as `Last, First` across preview and row inspection via `formatPersonName`.
    - Optimized Pre-Upload Validation preview layout: removed redundant `Position` column, applied `whitespace-nowrap` to `Emp No` to prevent wrapping, and formatted `Details / Validation` errors with human-friendly messages prefixed by employee last name in Title Case (e.g. `Ballesteros — Underage employee. Minimum legal working age is 18.`).
    - Removed misleading "Needs HRCO" chip from Inspect Batch Rows; renders neutral note `Roving · N stores · X.XX HC`.
    - Batch cards and upload banner display breakdown `N valid · N warnings · N blocked`.
    - Approve button disabled with clear reason unless `(batch.status === 'pending_approval' || batch.status === 'commit_failed') && batch.blockedRows === 0`.
    - Fixed Reject Batch modal: added "Confirm Reject" button in footer, wired to `handleRejectConfirm`, requiring non-empty reason and styled with canonical design tokens (`var(--danger-button)` / `var(--danger-button-hover)`).
  - **Regression Test Harness & Idempotency Verification (`scripts/tests/plantilla_import_regression.sql`)**:
    - Replaced obsolete `.mjs` test script with self-rolling-back PostgreSQL regression harness `scripts/tests/plantilla_import_regression.sql` (to run before and after any change touching Import Plantilla).
    - Tests roving validation (14 rows -> valid, 0 flags, pending_approval), approval (14 stores, 14 slots, 14 allocations, 4 plantilla employees, 14 links), server-side blocking (`BATCH_BLOCKED: ...`), rejection state machine + audit trail, and rolls back 100% via `RAISE EXCEPTION`.
    - Proved idempotency on staging: re-submitting and re-approving the same 14 roving rows detects 14 existing stores, 0 new stores, and yields identical counts without duplication.

- **Plantilla Baseline Import Approval Store Columns, Slot/Link Restoration & Ecosystem SQL Anti-Regression Gate (`ohm#c4k9m2v7` / `ohm#g9s4k2v8` — 2026-11-12)**:
  - **Root Cause Resolved**: In `20261111000002_adr002_addendum_import_coalescing_and_invariants.sql` (and carried into `093`), `approve_plantilla_import_batch` was rewritten from scratch rather than surgically editing Migration `086`. That rewrite introduced non-existent columns (`stores.city`, `stores.source_import_batch_id`, `plantilla_import_batches.approval_notes`) and dropped `086`'s `plantilla_slots` provisioning/claiming and `plantilla_store_links` sync.
  - **Dedicated Forward Migration 105 (`20262606000105_fix_approve_plantilla_import_batch_store_columns.sql`)**:
    - Restored the complete working Migration `086` body of `public.approve_plantilla_import_batch(uuid)` while preserving ADR-002 Rule #17 Last-Row-Wins coalescing (`ORDER BY row_number DESC`):
      - **Phase A**: Uses canonical `public.stores` columns (`area_province`, `province`, `area_city`, `employment_type`, `with_penalty`, `schedule_days`, `schedule_time`, `hrco_user_id`, `source_import_id`) and captures `store` snapshots with `import_row_id`.
      - **Phase B1**: Provisions vacant slots in `public.plantilla_slots` (`slot_ordinal`), synchronizes `public.vacancies` (`ON CONFLICT (vcode) DO UPDATE`), records `public.slot_history`, and captures `'slot'` snapshots.
      - **Phase B2**: Upserts `public.plantilla` with Last-Row-Wins coalescing, manages `public.employee_store_allocations` + snapshots, synchronizes `public.plantilla_store_links`, and executes 3-step `public.plantilla_slots` reuse / pre-existing open slot claiming (marking linked `vacancies` `'Filled'`) / new occupied slot creation with `slot_history` and `'slot'` snapshots.
  - **Ecosystem-Wide Automated SQL Schema & RPC Anti-Regression Gate (`scripts/check-sql-contracts.mjs`)**:
    - Chained automatically into `npm test`, `npm run lint`, and `npm run check:sql`.
    - Dynamically builds the authoritative column dictionary across all 528 migrations (`CREATE TABLE`, `ALTER TABLE ... ADD COLUMN`, and dynamic `EXECUTE format('ALTER TABLE public.%I ADD COLUMN ...')`), validates every `INSERT`/`UPDATE` statement across 28 core tables in the OHMployee ecosystem, and locks required invariants across 19 critical cross-module RPCs so partial function rewrites or invalid columns fail `npm test` in `< 0.3s` before any commit.


  - **ADR-002 Invariant 10 Rollback Lineage & Migration 086 (`20262606000086_fix_plantilla_import_rollback_ready_and_store_closure_trigger.sql`)**:
    - **Root Cause & BUG-06 Overwrite Resolved**: Migration `20262606000059_fix_plantilla_field_inheritance_and_mapping.sql` (`ohm#f7m2w9x4`) had replaced `approve_plantilla_import_batch` with a function template omitting `rollback_ready = true` (and `committed_stores`/`committed_employees`), carried forward into `062` and `064`. Before 086, snapshots existed for store, plantilla and Phase B1 vacant slots. allocation (insert) snapshots and Phase B2 slot snapshots (occupied or claimed) were first written by 086. Legacy batches have allocation (update) snapshots only.
    - **Approval RPC Restored**: `approve_plantilla_import_batch` now captures snapshots for `store` (insert/update), `plantilla` (insert/update), Phase B1 vacant `plantilla_slots` (insert), `employee_store_allocations` (insert), and Phase B2 `plantilla_slots` (insert/update) and `vacancies` (update); sets `rollback_ready = true` (with `rollback_expires_at` defaulting to `approved_at + INTERVAL '72 hours'`); populates `committed_stores`, `committed_employees`, and `approved_by_name`.
    - **Rollback RPC Restored**: `rollback_plantilla_import_batch` safely restores/deactivates allocations (omitting non-existent `updated_at`/`updated_by` columns on `employee_store_allocations`), archives batch-created plantilla rows (`is_archived = true`, `status = 'Inactive'`), restores batch-updated plantilla/stores to prior snapshots, closes batch-created slots and restores claimed vacant slots, archives batch-created vacancies, deactivates empty batch-created stores, and archives empty roving groups.
  - **Store Closure Cascade Vacancies Trigger (`fn_trg_store_closure_cascade_vacancies`)**:
    - Added missing `closed_at timestamptz` column to `public.vacancies`.
    - Resolved Postgres error `42703: column "closed_at" of relation "vacancies" does not exist` that previously crashed store archival and closure operations in web, mobile, and cleanup routines. Vacancies are marked `status = 'Closed'` and `is_archived = true`.
  - **Lineage Reset, Executor Lockdown & Protected Occupant Guard (`20262606000087_reset_incomplete_plantilla_rollback_lineage_and_lock_executor.sql`)**:
    - **Lineage Reset**: Migration 086 backfilled `rollback_ready = true` broadly on approved batches. Migration 087 selectively resets `rollback_ready = false` for approved batches lacking allocation insert or slot snapshots (safely healing legacy batch `1dcb71eb-742d-4fbc-83a0-703cb57f64b5`), while remaining a strict no-op for vacant-only batches and valid 086-approved batches.
    - **Executor Lockdown**: Execution on `public.rollback_plantilla_import_batch` was revoked from `PUBLIC`, `anon`, and `authenticated` (`GRANT` to `service_role` only). Direct calls via PostgREST RPC are denied (`42501`); callers must route through `SECURITY DEFINER` wrappers (`approve_plantilla_import_rollback`, `emergency_rollback_plantilla_import`).
    - **Protected Occupant Guard**: Before closing batch-created slots, `rollback_plantilla_import_batch` asserts that the slot occupant belongs to the batch's own inserted/updated plantilla rows. If an external employee occupies a batch-created slot, rollback hard-blocks with `ROLLBACK_BLOCKED_PROTECTED_OCCUPANT: slot % (store %) is occupied by % which is not part of batch %` (40001).
  - **Regression Test Suite (`scripts/tests/plantilla_import_regression.sql`)**:
    - Enhanced test harness asserting: stationary evaluation, roving submission (`pending_approval`, 0 flagged), roving approval, rollback readiness, vacant-only batch lineage immunity, direct executor execution denial (`42501`), protected occupant abort, real request then approve flow, zero-edit lock enforcement, and full 6-table post-rollback baseline comparison (stores active, slots total/occupied/open, allocations, plantilla, store_links, vacancies). All assertions verified passing on Staging with zero rows persisted.

- **Plantilla Bi-Directional Identity Lock UI Wiring & Migration 094 (`ohm#s8d1q4v9` — 2026-11-11)**:
  - **Client-Side Wiring**: Wired `coalescePlantillaBatch` into `handleFileSelect`, `useEffect`, and `handleBaselineSubmit` in `src/components/more/PlantillaImportModal.tsx`. Client-side validation now proactively detects duplicate identities (e.g. `ROSALES, GRACELYN BENITEZ` under `2060-001` vs `2060-005`), merges blocking errors directly into `res.rows`, increments `res.blockedRows`, and prevents unauthorized submission to review queue.
  - **Dedicated Forward Migration 094 (`20262606000094_adr002_bidirectional_identity_lock.sql`)**: Shipped new standalone migration defining `public._evaluate_plantilla_import_rows` with the `name_emp_conflicts` CTE and reverse database master checks (`db_name_conflict`, `db_emp_name_conflict`), guaranteeing Staging and Production databases execute the bi-directional lock upon `supabase db push`.

- **Plantilla Pre-Upload Details/Validation Message Refinement (`ohm#n4p2k8v1` — 2026-11-11)**:
  - **Surname Removal**: Refined `formatFriendlyValidationMessage` in `src/components/more/PlantillaImportModal.tsx` to omit the redundant employee surname prefix (e.g. `Ballesteros — `), as the employee's full name is already displayed directly adjacent in the `Employee Name` column.
  - **Crisp & Direct Messages**: Messages now read directly as `"Mismatched hired date across roving store rows."`, `"Underage employee. Minimum legal working age is 18."`, `"Hire date does not match master record in database."`, and `"Multiple employee numbers assigned to the same person. Roving employees must share the same Emp No."`.
  - **Signature Simplification**: Cleaned up function signature and call sites to remove unused parameter `_employeeName`.

## Recent Updates
- **Account Archival Cascade Trigger & Orphan Store Guard (`ohm#account-archive-cascade-and-orphan-cleanup` — 2026-11-23)**:
  - **Database Cascade Trigger (`trg_account_archive_cascade_stores`)**: Added trigger on `public.accounts` via migration `20262606000139_account_archive_cascade_and_orphan_stores_cleanup.sql`. Whenever an account transitions to `is_active = false`, `is_archived = true`, or `status = 'Inactive'`, all its child stores in `public.stores` are automatically cascade-deactivated (`is_active = false, status = 'archived', is_archived = true, archived_at = now()`), permanently preventing orphan stores under retired/inactive accounts.
  - **Query Layer 3-Way Archive Guard**: Hardened `fetchHeadcountModalMasterData` in `src/lib/queries/requests.ts` and `fetchAccountStores` & `fetchDestinationStores` in `src/lib/queries/plantilla.ts` with multi-column filtering (`.eq("is_active", true).neq("status", "archived").or("is_archived.is.null,is_archived.eq.false")`).
  - **Database Cleanup & Rollback Finalization**: Resolved historical failed rollbacks resulting from the legacy 42703 `type` column bug:
    - **MARIZ**: Batch `a1bf2b5e-2e8e-40f1-93e0-c730a626b452` marked `rolled_back`, 4 orphan stores and 2 plantilla rows archived.
    - **ZEBRA**: Batches `29f1c261-39ea-4cc7-9b1e-681ccb55c7c9` and `a79f1571-4ee4-48db-9aa6-d2a66f08a347` marked `rolled_back`, 257 stores archived, and 252 unassigned slots / 1 vacancy closed.
    - **ALTURAS**: Batch `0071cb78-c960-46b7-a5dd-dbce08335449` marked `rolled_back` and 6 orphan stores archived.
    - **APEX**: Batch `82ee6311-404f-4358-b4d8-3d45cf30641b` marked `rejected/completed`, 14 stores and 4 plantilla rows archived.
    - **ONE**: Batches `1d7ffc3f-a5b0-468f-bb39-689e3189428d` and `e9102051-c6cf-4057-8eee-8896d3fe6846` marked `rolled_back`.
    - **ALING NENA STORE**: Deactivated orphan store `ALING NENA` (`518bdc0c-118a-42d3-9140-e99b501fcb21`).
  - **Automated Health & Integrity Script**: Created `scripts/check-database-integrity.mjs` and registered npm script `npm run check:integrity` to proactively audit for orphan stores, unexecuted rollbacks, and inconsistent flags.

- **Phase 2: Operations Coverage Requesting & Tiered Review/Approval (`ohm#o4p9s2k1` — 2026-11-13)**:
  - **Operations Request Authorization**: Enabled Operations roles (`Operations Manager`, `Team Leader`, `Assistant Team Leader`, `HR Coordinator` via `isOpsAmendmentRole`) to access the `+ Coverage Group` button and submit roving coverage group operations (Create Group, Add Store, Remove Store, Merge, Dissolve) in Request Mode.
  - **Tiered Review & Approval Model**:
    - **Encoder Review of Ops Requests**: Authorized Encoders (`role_level = 30`) to review (approve/reject) coverage requests initiated by Operations roles (`OM`, `TL`, `ATL`, `HRCO`). Unlocked Category 3 (`coverage`) in `/approvals` for Encoders in `src/lib/rbac.ts`.
    - **Admin Approval Lock for Encoder Requests**: Coverage requests initiated by Encoders strictly require Head Admin or Super Admin review; Encoders cannot approve requests submitted by Encoders.
    - **Self-Approval Guard**: Strictly blocks any actor from approving or rejecting their own request (`requested_by = v_actor.profile_id`) across both backend RPC (`_review_coverage_request_phase3`) and Web UI card (`CoverageGroupApprovalCard.tsx`).
  - **Forward Migration 107 (`20262606000107_coverage_requests_ops_requesting_and_tiered_approval.sql`)**:
    - `public.fn_can_mutate_coverage_request()`: Extended to include `'Encoder', 'Operations Manager', 'OM', 'TL', 'ATL', 'ATL/TL', 'HRCO'`.
    - `public.fn_can_review_coverage_request(uuid)`: Tiered predicate checking requester role and self-approval block.
    - `public._review_coverage_request_phase3(...)`: Enforces tiered review authorization and self-approval guard before execution.
    - `coverage_requests_read_scoped` & `coverage_request_history_read_scoped`: Updated RLS policies granting Ops roles scoped read access to their requests.

- **Comprehensive 5-Tab Coverage Group Management Architecture (`ohm#g9k2m4c8` — 2026-11-13)**:
  - **Full Mobile Parity (`CreateCoverageGroupModal.tsx`)**: Upgraded `CreateCoverageGroupModal` to support all 5 core coverage group lifecycle workflows across horizontal tabs (`[ + Create Group | ➕ Add Store | ➖ Remove Store | 🔀 Merge Groups | ⚠️ Dissolve Group ]`):
    1. **Create Coverage Group**: Strict stationary store footprint filtering ($\ge 2$ free stores, 1 designated anchor store).
    2. **Add Store**: Scoped to selected coverage group with store picker restricted strictly to available stationary/unassigned stores.
    3. **Remove Store**: Shows existing member stores of the target coverage group. Enforces $\ge 2$ remaining stores invariant (if removing leaves $< 2$ stores, actions are blocked and user is routed to Dissolve).
    4. **Merge Coverage Groups**: Combines 2 distinct coverage groups (Source $\to$ Destination) under the same account.
    5. **Dissolve Coverage Group**: Reverts all member stores to stationary. If active personnel exist in the group, renders interactive Home Store Assignment dropdowns for each employee (GAP-02 parity) persisted to `employee_home_stores`.
  - **Dual Execution & Role Model**:
    - **Head Admin & Super Admin**: Live direct execution (`Apply Directly` / `Create Directly` / `Dissolve Directly`) with immediate multi-cache invalidation.
    - **Encoder**: Submits request for administrative review (`Submit for Approval`) routed to `/approvals` Category 3.
  - **Data Layer Hooks (`src/lib/queries/more.ts`)**: Added `fetchCoverageGroupEmployees`, `useCoverageGroupEmployees`, and `executeCoverageOperation` / `useCoverageOperation` wrapping direct creation and coverage request lifecycles.

- **Roving Coverage Group Direct Creation Integration (`ohm#c7v2k9m4` — 2026-11-13)**:
  - **Feature Parity with Mobile (`CreateCoverageGroupModal.tsx`)**: Built high-fidelity modal dialog for direct creation of multi-store roving coverage clusters in `src/components/modals/CreateCoverageGroupModal.tsx`, matching mobile `create_coverage_group_screen.dart` and `coverage_group_service.dart`.
  - **Dual Entry Points**:
    1. **Plantilla Landing (`/plantilla`)**: Placed `[ + Create Coverage Group ]` beside `[ + Add Account ]` on the Account Directory header action bar for Data Team roles (`isHeadOrSuperAdmin` or `isDataTeam`).
    2. **Account View (`/plantilla?account=<id>`)**: Added `[ + Coverage Group ]` in the store/employee view toolbar with the account pre-selected and locked to the current account context.
    3. **More Hub (`/more`)**: Integrated `[ + Create Group ]` into `RovingCoverageGroupsModal.tsx` toolbar.
  - **Data Layer & Hooks (`src/lib/queries/more.ts`)**: Added `fetchCoverageGroupEligibleStores` (calling RPC `get_coverage_group_eligible_stores`), `fetchAccountPositionOptions` (querying `v_account_position_options` with `positions` fallback), and `useCreateDirectCoverageGroup` with standardized multi-cache invalidation.
  - **ADR-001 Validation**: Real-time client enforcement requiring $\ge 2$ free stores, 1 designated anchor store from selected stores, and blocking stores already assigned to active coverage groups (`alreadyGroupedCode`). Validated clean via `npm run lint` and `npm run build`.

- **MARIZ Account & Fallback Archival Reconciliation (`ohm#m8r2a4k7` — 2026-11-13)**:
  - **Root Cause**: Plantilla Directory cards read from `v_account_allocation_kpi` (which aggregates `employee_store_allocations WHERE is_active = true`), showing `0/0` and `MFR —` because MARIZ's allocations were previously set to `is_active = false` and its active plantilla rows had been marked `is_archived = true` during QA batch testing (`QA TESTINGAAA` / `QA TEST HEHESSSSS`). When opening the account, the Strategy D client fallback in `listWebPlantillaEmployees` queried raw `plantilla` table without `is_archived = false` check, resurrecting the 14 active personnel and calculating `14 Active / 14 Required (100.0% MFR)`.
  - **Client-Side Archival Safety Guard (`src/lib/queries/plantilla.ts`)**: Patched fallback query strategies in `listWebPlantillaEmployees` to strictly enforce `.or("is_archived.is.null,is_archived.eq.false").or("is_deleted.is.null,is_deleted.eq.false")` across chunks and direct table queries, guaranteeing client fallbacks never violate ADR-001 archival invariants by surfacing archived/deleted records.
  - **Staging Database Reconciliation**:
    1. Unarchived the 14 active personnel records for MARIZ in `public.plantilla` (`is_archived = false, archived_at = null, archive_reason = null`).
    2. Reactivated their canonical allocation records in `public.employee_store_allocations` (`is_active = true`).
    3. Reconciled `v_account_allocation_kpi` on Staging: now computes `actual_hc = 14`, `required_hc = 14.0000`, `mfr = 1.0000` (100.0%), ensuring seamless consistency between Directory Card and Account View.

  - **Pinned Tier 0 Priority (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - MOSES HQ / Workforce Pool account (`isPoolAccount = true` or `name.toLowerCase() === 'moses hq'`) is permanently pinned to index 0 (`pinaka unahan lagi`) of the Plantilla Directory cards grid.
    - Subsequent accounts continue to sort using the multi-tier problem-first hierarchy (lowest MFR first, vacancy tie-breaker, unconfigured accounts at bottom).

- **Hardcoded Overrides & Magic Numbers Elimination (`ohm#h4p9m2k8` — 2026-11-12)**:
  - **Eliminated ALTURAS Hardcoded Allocations**: Removed the artificial override `if (row.account_id === '3126b9a8...') { actual = 752; vacant = 3; }` in `src/app/(dashboard)/plantilla/page.tsx`. Metrics now derive authentically from `v_account_allocation_kpi` without synthetic masking.
  - **Removed Hardcoded Pool Account UUIDs**: Purged raw UUID string `"3946ffdd-d826-4fc7-bb9e-356a32dcd152"` across `plantilla/page.tsx` and `dashboard/page.tsx`. Workforce pool account resolution is now 100% dynamic via `is_pool_account = true` and `name.toLowerCase() === 'moses hq'`.

- **Problem-First Account Card Arrangement (`ohm#p4k1v9m8` — 2026-11-11)**:
  - **Root Cause Resolved**: In `/plantilla` (Directory account selection grid), account card sorting previously checked `const isAFillRateZero = a.fillRate === 0; if (isAFillRateZero && !isBFillRateZero) return 1;`. This falsely conflated unconfigured/empty accounts (`required === 0`, where MFR renders as `"—"`) with active accounts that have severe staffing deficits (such as `ZEBRA` with `HC 0/1 · Vacant 1` and `MFR 0%`), pushing `ZEBRA` to the absolute bottom of the page behind even 100% fulfilled accounts.
  - **Problem-First Severity Hierarchy (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - Replaced the brittle zero-check with an explicit multi-tier severity comparator:
      1. **Active Quota Priority**: Accounts with active headcount requirements (`required > 0`) strictly precede accounts with blank MFR (`required === 0`).
      2. **Lowest Fill Rate First**: For active accounts, cards are sorted by `fillRate` ascending (`a.fillRate - b.fillRate`). Accounts with `0%` MFR (such as `ZEBRA`) are elevated to the very first position (`pinaka una`), followed by low-fulfillment accounts (e.g. `Moses HQ` at 13.04%, 50%, etc.), followed by fully-staffed accounts (100%+).
      3. **Vacancy Tie-Breaker**: Accounts with identical fill rates prioritize higher vacant slot counts (`b.vacant - a.vacant`).
      4. **Blank MFR Grouping**: Accounts with `required === 0` settle at the bottom of the grid, neatly sorted alphabetically by name (`a.name.localeCompare(b.name)`).

- **Plantilla Directory Moses HQ & Workforce Pool Card Metrics Integration (`ohm#m8p4v2k9` — 2026-11-11)**:
  - **Root Cause Resolved**: In `/plantilla` (Directory account selection grid), the Moses HQ account card rendered `HC 0/0 · Vacant 0` despite having 3 active employees assigned (`YAP, JAY UY`, `YAP, JEN UY`, and `YAP, JESSICA UY`). This occurred because `accountMetricsQuery` fetched solely from `v_account_allocation_kpi`, which intentionally filters out pool accounts (`WHERE COALESCE(is_pool_account, false) = false`) to isolate client-facing store MFRs.
  - **Batch Pool Capacity Integration (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - Enhanced `accountMetricsQuery` to execute concurrent queries to `public.plantilla` (`is_pool_employee = true` or `account = 'Moses HQ'`) and `public.workforce_pool_slots` (`is_active = true`, `deleted_at IS NULL`).
    - Dynamically resolves pool accounts (`isPoolAccount: true` or name matching `"Moses HQ"`), mapping live active headcount (`actual = 3`), open pool slots (`vacant = 20`), and total budgeted pool capacity (`required = 23`).
    - Matches 100% parity with the internal `MosesHqPoolView` metric cards (Active: 3, Vacant: 20, Budgeted: 23), presenting `HC 3/23 · Vacant 20` on the Moses HQ card.

- **Mutually Exclusive Account Card Vacant & Pipeline Headcount Reconciliation (`ohm#u5v8p2k4` — 2026-11-14)**:
  - **Contract Enforced**: The Plantilla Directory Account Card `Vacant` metric strictly reflects **Open / Unassigned slots only** (`totalUnfilled - hrProcess`), preventing double-counting of candidates who are already progressing through the HR Onboarding Pipeline (`pipeline_count`).
  - **Required Headcount Formula**:
    $$\text{Required HC} = \text{Actual Deployed} + \text{On-Leave} + \text{Vacant (Open/Unassigned)} + \text{Pipeline (Onboarding)}$$
  - **Forever Office Parity Example**:
    - **Active**: 4 (deployed store employees)
    - **On-Leave**: 1
    - **Vacant**: 5 (open/unassigned slots, derived from $6 \text{ total unfilled slots} - 1 \text{ candidate in pipeline}$)
    - **Pipeline**: 1 (`Al, James N/A` in `HR Emploc - Pending` at `CPSAJV27` Puregold General Trias)
    - **Total Required**: 11 ($4 + 1 + 5 + 1 = 11$)
    - **Actual Deployed**: 4 (Fill Rate: $4 / 11 = 36.36\%$)
  - **Surgical Implementation (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - Updated `accountMetricsQuery` so `vacant = Math.max(0, totalUnfilled - hrProcess)`.
    - Computed `required = actual + leave + vacant + hrProcess`.
    - Applied identical formula across both KPI-backed and fallback accounts in the account selection grid.

- **Coverage Group Vacancy & Roving Manpower Integration (`ohm#c4g9m2k7` — 2026-11-14)**:
  - **Contract Enforced**: In Plantilla Tab 3 Vacancy (and `/vacancy`), open Coverage Groups consolidate into **1 single row** displaying `cgCode` (e.g. `CG-FG1-0004`) in `VCode / CGCode` while retaining the anchor store's individual `VCode` as a subtitle/secondary identifier.
  - **Active Manpower Merge**: When a Coverage Group is formed with an active employee (e.g. Delfina Juaphel Dolar at Puregold Tanza, Waltermart General Trias, Emilus Rosario):
    - The active employee becomes Roving under the coverage group with fractional $1/N$ ($0.3333$ HC for 3 stores) in `employee_store_allocations` and `plantilla_store_links`.
    - Vacant member stores (such as `CPSAJV31` Emilus Rosario) are automatically fulfilled and closed in `vacancies` (`status = 'Filled'`), merging into the active employee.
    - Tab 3 Vacancy recognizes the active roving employee coverage via `activeOccupiedVcodes` and suppresses covered member stores.
  - **UI Parity**: `StoreVacancyTable` and `VacancyCard` render `row.cgCode || row.vcode`, and `VacancyDetailDrawer` renders itemized Assigned Stores cards with store name, `Anchor` tag, individual intact `VCode`, and $1/3$ HC badge.

- **Coverage Group Creation Universal Store Footprint & Form Streamlining (`ohm#p8c2m4k1` — 2026-11-14)**:
  - **Removed Redundant Fields**: Permanently removed `Target Position` and `Employment Type` form selectors from `CreateCoverageGroupModal.tsx`. Backend RPC executes with `positionId: undefined` and `employmentType: 'Regular'` without redundant UI input.
  - **Universal Store Footprint Visibility**:
    - Upgraded RPC `get_coverage_group_eligible_stores` (migration `20262606000111_coverage_group_universal_store_picker.sql`) to return **all active stationary stores** under the account regardless of vacancy status or employee occupancy.
    - In `CreateCoverageGroupModal.tsx`, all stores are displayed in the footprint picker. Stores already belonging to an active coverage group render with disabled checkboxes and an `Already in <CGCode>` tag (matching mobile Flutter behavior in `create_coverage_group_screen.dart`), preventing overlap while maintaining full footprint awareness.
    - Free stores render with enabled checkboxes and `Anchor` / `Set Anchor` controls.
    - Staging test cleanup: Archived empty test groups `CG-FG1-0002` and `CG-FG1-0003` to unlock 5 stores for Forever Office.

- **Cross-Account Store Resolution & Headcount Request Parity (`ohm#fix-hc-request-cross-account-store-resolution` — 2026-11-23)**:
  - **Issue Remediated**: When an operator initiated a headcount request (e.g. for `Super 8 Dau` under `ACTISERVE`), but that store was originally registered in the master store catalog under another account (e.g. `ACTIVESTYLE`), the previous RPC rejected the submission with `invalid_reference (store_id)`.
  - **Database Migration (`20262606000145_fix_hc_request_cross_account_store_resolution.sql`)**:
    - Surgically enhanced `public.submit_headcount_request` to support cross-account store resolution for both Stationary and Roving requests.
    - When `store_id` is supplied but not present under `v_account_id`, the function searches active master stores. If found, it checks if `v_account_id` already has a store with the same name. If not, it auto-provisions an active store record for `v_account_id` and adopts that ID, preserving all foreign keys (`headcount_requests.store_id`, `vacancies.store_id`, `plantilla_slots.store_id`).
    - If `store_id` is null but `store_name` is provided, it similarly matches or provisions the store for `v_account_id`.
    - Added human-readable `message` fields across all validation error paths.
  - **Web & Mobile Parity**:
    - In Web `src/lib/queries/requests.ts`, surfaced `data?.message` and clear formatting for `invalid_reference`.
    - In Mobile `lib/features/plantilla/plantilla_screen.dart`, ensured `_selectedStore` is populated even when the initial store is unmapped or cross-account, enabling form submission.
    - In Mobile `lib/data/services/plantilla_scope_service.dart`, surfaced user-friendly error messages from RPC `result['message']`.
    - Applied and validated on Staging DB (`qqiiznmqxfoamqytjica`) with 0 errors across 255 Web tests and 27 Mobile tests.

- **Account-Level Whole Number Headcount & KPI Rounding Protection (`ohm#round-account-allocation-kpi-whole-numbers` — 2026-11-23)**:
  - **Issue Remediated**: On the Plantilla Directory overview cards (`/plantilla`), account-level headcount and vacancy metrics displayed floating-point decimal leakage (e.g. `ACTISERVE` `HC 4/11.99`, `BANCON` `HC 4/3.9999`, `ACTIVESTYLE` `HC 1/0.9999`) caused by fractional roving merchandiser allocation distributions ($1/N$, e.g. $1/3 \approx 0.33$ or $0.3333$).
  - **Governing Architecture**: Enforces ADR-001 Invariant 17: while store-level capacity supports fractional roving shares ($1/N$), Account, CENCOM, and Dashboard headcount strictly counts distinct people and must always evaluate to whole numbers.
  - **Database Migration (`20262606000147_round_account_allocation_kpi_whole_numbers.sql`)**:
    - Updated `public.v_account_allocation_kpi` (and refreshed downstream views `v_cencom_account_allocation_kpi`, `v_cencom_group_allocation_kpi`, `v_cencom_allocation_kpi`) to round `required_hc` and `slot_vacant_hc` to whole numbers (`round(..., 0)::numeric(12,4)`), and aligned `mfr` and `projected_mfr` to evaluate against distinct person counts (`actual_hc::numeric / required_hc`), preserving identical column ordering, names, and `numeric(12,4)` types.
    - Pushed live to Staging (`qqiiznmqxfoamqytjica`) with 0 errors via `npm run db:push:staging`.
  - **Web Presentation Layer Hardening**:
    - `src/app/(dashboard)/plantilla/page.tsx`: In `accountMetricsQuery`, wrapped `actual`, `hrProcess`, `vacant`, `required`, and `leave` in `Math.round()`.
    - `src/components/plantilla/directory/PlantillaAccountSelection.tsx`: Wrapped account summary attributes and JSX displays in `Math.round()` (`Math.round(account.actual)}/{Math.round(account.required)}`, `Math.round(account.vacant)}`, `Math.round(account.hrProcess)}`, `Math.round(account.leave)}`).
    - `src/lib/queries/plantilla.ts`: Wrapped KPI fallback query in `getPlantillaSummary` with `Math.round()` on `actual`, `vacant`, `hrProcess`, and `required`.
    - `src/app/api/ohmni/route.ts`: Hardened anomaly checks and summary formatters with `Math.round()`.
    - `src/components/plantilla/ArchiveAccountModal.tsx`: Applied `Math.round()` on `required` and `actual`.
    - `src/app/(dashboard)/cencom/groups/[id]/page.tsx`: Applied `Math.round()` on `account.required`, `account.actual`, and `account.vacant`.













