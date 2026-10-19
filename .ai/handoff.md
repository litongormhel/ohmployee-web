# AI Handoff

## Unify Web `/approvals` Hub — Port Plantilla Deployment Queue & Integrate Account Requests Tab (ohm#w89p602c)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Mobile Queue Parity Achieved)**

### Objective
Achieved 100% Mobile-to-Web queue parity on `/approvals` (`src/app/(dashboard)/approvals/page.tsx`) by porting and integrating the two missing Mobile approval queues identified in `ohm#w89p602a-audit`:
1. **Plantilla Candidate Deployment Approvals (`plantilla_approvals`)**: Ported from Mobile `d:\Projects\OHMployee\lib\features\approval\approval_screen.dart` and `approval_service.dart`.
2. **Account Sign-Up Requests (`account_requests`)**: Integrated directly into `/approvals` horizontal category tab strip, supporting review, role/group/account scoping, and provisioning via backend RPC `approve_account_request_v2`.
3. **Synchronized Pending Badges**: Both new queues are fully aggregated into `fetchRequestCategoryCounts` and reflected in the Left Sidebar approvals counter and `/approvals` tab strip.

---

### Implementation Details

1. **Supabase Query & RPC Hooks (`src/lib/queries/requests.ts` & `src/lib/queries/accountRequests.ts`)**:
   - Added `plantilla_approvals` and `account_requests` to `RequestCategoryKey`, `REQUEST_CATEGORIES`, and `fetchRequestCategoryCounts()` with safe failure fallback.
   - Added TypeScript interfaces: `PlantillaApprovalItem`, `fetchPlantillaApprovals(tab)`, `fetchPlantillaApprovalCounts()`.
   - Wired backend RPCs:
     - `approve_plantilla_request(p_approval_id)` via `useApprovePlantillaRequest`.
     - `reject_plantilla_request(p_approval_id, p_remarks)` via `useRejectPlantillaRequest` (mandates rejection remarks).
   - In `accountRequests.ts`, implemented `fetchAccountRequestCounts()` and `useAccountRequestCounts()`, and added cache invalidation for `request-category-counts` on approve/reject.

2. **High-Density Table Components (`src/components/approvals/`)**:
   - Created `PlantillaApprovalDataTable.tsx`: High-density responsive data table matching `ApplicantMovementDataTable` and `ActiveQueueReviewPane`, displaying candidate name, target account, position, VCode slot, EMPLOC #, requester, date, and single/bulk Approve and Reject modals with required remarks.
   - Created `AccountRequestDataTable.tsx`: High-density review table displaying applicant name, email, phone, requested role, scope (global/scoped groups), notes, submission date, and interactive Approve modal (assign role, toggle global/scoped, assign groups & accounts) and Reject modal.

3. **Approvals Hub Integration (`src/app/(dashboard)/approvals/page.tsx` & `src/components/approvals/ActiveQueueReviewPane.tsx`)**:
   - Added `plantilla_approvals` ("Plantilla Placements") and `account_requests` ("Account Sign-Ups") into `VALID_CATEGORIES` and category navigation tabs with icons `Briefcase` and `UserPlus`.
   - Connected both review sections into `ActiveQueueReviewPane.tsx` with dedicated sub-tabs (Pending / Approved / Rejected) and search filters.
   - Maintained global Left Sidebar counter consistency through unified React Query cache updates.

---

### Verification Results
- `npm run lint`: **PASS** (0 errors, warnings are legacy unrelated modals).
- `npm run build`: **PASS** (19/19 routes compiled with Turbopack, including `/approvals`).

---

## Port Mobile Operational Reports Suite to Web `/reports` Hub (ohm#w89p602b)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Mobile Operational Reports Parity Achieved)**

### Objective
Replaced the `ModuleEmptyState` placeholder in `src/app/(dashboard)/reports/page.tsx` with the complete Operational Reports & Analytics Hub ported from Mobile `d:\Projects\OHMployee\lib\features\reports\` and `cencom_service.dart`. Delivered all 5 Mobile reporting surfaces:
1. **Overview & Quick Reports** (`tab=catalog`) with Universal Report Viewer (`ReportDetailView.tsx`) covering Attrition, Resigned, AWOL, Terminated, Back-Out, Combined Leakage, Time-to-Fill, and HR Emploc Late Updates. Includes employee/store separation drilldown (`AttritionDrilldownModal.tsx`).
2. **Floating Staff Report** (`tab=floating`) with duration tracking, aging buckets (<30d, 30–60d, >60d), account distribution breakdown, and full employee rows.
3. **Team Performance Report** (`tab=team_performance`) with operational discipline rankings, SLA compliance, turnaround metrics, coordinator scorecards, and account-level issue drilldown (`TeamPerformanceIssuesModal.tsx`).
4. **Data Integrity Report** (`tab=data_integrity`) surfacing delayed updates, vacancy delay, ghost occupancy, and pipeline anomalies across 4 audited sections with detail drilldowns (`DataIntegrityDetailModal.tsx`).
5. **Custom Report Builder** (`tab=custom`) allowing users to choose data sources, toggle columns, scope multi-condition filters, preview high-density data, and export to XLSX/CSV.

---

### Implementation Details

1. **Dedicated Supabase Reports Queries Module (`src/lib/queries/reports.ts`)**:
   - Implemented typed queries and TanStack React Query hooks wiring the Supabase views, tables, and RPCs:
     - `fetchReportFilterOptions` / `useReportFilterOptions`: Loads dynamic group and account scopes from `v_cencom_group_allocation_kpi` and `v_cencom_account_allocation_kpi`.
     - `fetchUniversalGroupReport` / `useUniversalGroupReport`: Unified dispatcher querying operational reports (`report_attrition_by_group`, `report_resigned_by_group`, `report_awol_by_group`, `report_terminated_by_group`, `report_backout_by_group`, `report_backout_terminated_by_group`, `report_time_to_fill_by_group`, `report_hr_emploc_late_update_by_group`).
     - `fetchAttritionDetails` / `useAttritionDetails`: Queries separated employees and store-level impacts via `fn_get_attrition_details`.
     - `fetchFloatingReport` / `useFloatingReport`: Queries floating personnel duration and aging via `fn_report_floating_employees`.
     - `fetchTeamPerformanceSummary` & `fetchTeamPerformanceDetail`: Queries group/account scorecards and detailed operational discipline breach logs via `fn_team_performance_summary` and `fn_team_performance_detail`.
     - `fetchDataIntegritySummary` & `fetchDataIntegrityDetailBySection`: Queries workforce anomalies via `fn_data_integrity_summary`, `fn_data_integrity_late_hr_detail`, `fn_data_integrity_vacancy_delay_detail`, `fn_data_integrity_ghost_occupancy_detail`, and `fn_data_integrity_pipeline_no_vacancy_detail`.
     - `fetchCustomReportPreview`: Queries ad-hoc datasets across Vacancy, HR Emploc, Plantilla, Deployment Summary, Data Integrity, and Team Performance.

2. **Universal Export Engine (`src/lib/utils/reports_export.ts`)**:
   - Developed client-side `exportToXlsx`, `exportMultiSheetXlsx`, and `exportToCsv` powered by `xlsx` with browser blob download streaming.

3. **Multi-Tab Web `/reports` Hub (`src/app/(dashboard)/reports/page.tsx`)**:
   - Preserved backward-compatible query redirects (`?tab=qa_center` -> `/more?open=qa_center`, `?tab=permission_drift` -> `/more?open=permission_drift`).
   - Wired bidirectional URL `?tab=` synchronization across `catalog`, `floating`, `team_performance`, `data_integrity`, and `custom`.
   - Wired `?report=` deep-linking to open the Universal Report Viewer directly into specific operational reports.

4. **Component Architecture (`src/components/reports/`)**:
   - `ReportsCatalogTab.tsx`: Categorized grid (Separation & Attrition, Recruitment Velocity & Turnaround, Workforce Health & Operational Audit).
   - `ReportDetailView.tsx`: Universal reporting shell with dynamic KPIs, date range presets, group/account scoping, client-side sorting, searchable table, and XLSX/CSV export.
   - `AttritionDrilldownModal.tsx`: Employee and store-level separation audit modal.
   - `FloatingStaffTab.tsx`: Aging buckets (<30d, 30–60d, >60d), account distribution pills, detailed employee roster, and exports.
   - `TeamPerformanceTab.tsx`: Operational discipline ranking leaderboard with progress badges, SLA metrics, and `TeamPerformanceIssuesModal.tsx`.
   - `DataIntegrityTab.tsx`: 4 audit section cards with metrics and `DataIntegrityDetailModal.tsx`.
   - `CustomReportTab.tsx`: 6 data sources, column toggles, condition filters, and preview table.

---

### Verification Results
- `npm run lint`: **PASS** (0 errors).
- `npm run build`: **PASS** (19/19 routes compiled with Turbopack, including `/reports`).

---

## Wire Governance & Audit Tools with Dedicated Modals & Deep Links (ohm#w89p601e)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Governance Tools Parity Achieved)**

### Objective
Audited and completed the functional targets for the 6 cards in `/more` (`System Hub & Governance Tools`) that previously routed generically to `/settings` or `/reports`:
1. `QA Center` (`v_qa_*` telemetry, runs, findings, schedules, reports)
2. `Permission Matrix` (editable role permissions with atomic overrides via `apply_permission_overrides`)
3. `Role Permissions` (read-only backend authorization matrix via `fn_get_permission_matrix`)
4. `Permission Drift` (authorization gap and enforcement mismatch detector via `fn_get_permission_drift_findings`)
5. `Security Events` (live realtime stream of security notices and session terminations via `security_events`)
6. `Audit Logs` (system activity and forensic change trails via `audit_logs` with before/after diffs)

---

### Implementation Details

1. **Governance Queries & Mutations Layer (`src/lib/queries/governance.ts` & `src/lib/queries/more.ts`)**:
   - Implemented dedicated types and TanStack React Query hooks wired directly to Supabase views, tables, and RPCs:
     - **QA Center**: `useQaCenterSnapshot`, `useRunQaCoreDetectionSuite`, `useRunQaScenario`, `useGenerateDailyQaReport` (backed by `v_qa_detection_run_summary`, `v_qa_open_findings`, `v_qa_schedules`, `v_qa_run_queue`, `v_qa_daily_reports`, `v_qa_health_metrics`, `v_qa_unstable_modules`, and `v_qa_flaky_tests`).
     - **Permission Matrix**: `useGovernanceRoles`, `useEffectivePermissionMatrix`, `useApplyPermissionOverrides` (backed by `get_effective_permission_matrix` and `apply_permission_overrides`).
     - **Role Permissions**: `useRolePermissionMatrix` (backed by `fn_get_permission_matrix`).
     - **Permission Drift**: `usePermissionDriftSummary`, `usePermissionDriftFindings` (backed by `fn_get_permission_drift_summary` and `fn_get_permission_drift_findings`).
     - **Security Events**: `useSecurityEvents` (backed by `security_events` table with user profile joins, severity filtering, and live Postgres realtime changes channel `gov_sec_events`).
     - **Audit Logs**: `useSystemAuditLogs` (backed by `audit_logs` table with actor profile joins, module/action/search filtering, date presets, and forensic diff payloads).
   - Re-exported all governance queries and types from `@/lib/queries/more`.

2. **Dedicated Governance Modals (`src/components/more/`)**:
   - **`QaCenterModal.tsx`**: Ported from Flutter's `qa_center_screen.dart` and `qa_center_service.dart`. Features 5 tabs (`Overview`, `Runs`, `Findings`, `Schedules & Queue`, `Daily Reports`), top KPI cards, module stability rankings, and execution action buttons ("Run Core Suite", "Run Scenario", "Generate Daily Report").
   - **`PermissionMatrixModal.tsx`**: Ported from Flutter's `permission_matrix_screen.dart`. Features role selection, Super Admin `SA_PROTECTED` lockout protection banner, expandable module groupings, permission Allow/Deny interactive toggles, bottom staging bar with count, and a transactional commit modal requiring audit reason justification.
   - **`RolePermissionsModal.tsx`**: Ported from Flutter's `role_permissions_screen.dart`. Quick-switch role pills, search/filter controls, sensitive/locked flags, and detailed enforcement tier inspection.
   - **`PermissionDriftModal.tsx`**: Ported from Flutter's `permission_drift_screen.dart`. Displays KPI summaries, severity and module filters, expected vs. observed enforcement comparative grids, recommendations, and code evidence traces.
   - **`SecurityEventsModal.tsx`**: Ported from Flutter's `security_dashboard_screen.dart`. Live realtime Postgres feed, KPI cards for critical incidents and terminated sessions, severity filters, search, and formatted JSON details payload viewer.
   - **`AuditLogsModal.tsx`**: Ported from Flutter's `audit_logs_screen.dart`. Forensic change history with actor attribution, module and action filters, search, date range presets, and expandable side-by-side JSON diffs (`old_data` vs `new_data`).

3. **Routing & Deep-Link Synchronization**:
   - **`/more/page.tsx`**:
     - Updated all 6 cards (`qa_center`, `permission_matrix`, `role_permissions`, `permission_drift`, `security_events`, `audit_logs`) to open their dedicated modals on click.
     - Added deep-link query parameter listener on mount (`?open=...`, `?modal=...`, `?tool=...`) allowing direct deep-linking (e.g. `/more?open=qa_center`, `/more?open=permission_matrix`, `/more?open=audit_logs`).
   - **`/settings/page.tsx`**:
     - Converted `activeTab` to derive directly from URL `?tab=` query parameter (`profile`, `preferences`, `security`, `diagnostics`), enabling seamless deep-links (e.g. `/settings?tab=security`).
   - **`/reports/page.tsx`**:
     - Added deep-link auto-router redirecting `/reports?tab=qa_center` and `/reports?tab=permission_drift` directly to `/more?open=qa_center` and `/more?open=permission_drift`.

---

### Verification Results
- `npm run lint`: **PASS** (0 errors).
- `npm run build`: **PASS** (19/19 routes generated with Turbopack).

---

## Phase 4 Web "More" Parity — Port OHM's Safespace, Switch Role, Roving Coverage Groups & Bulk Archive Execution (ohm#w89p601d)


**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Mobile-to-Web "More" Module Parity Achieved)**

### Summary of Changes

1. **OHM's Safespace Command Center (`src/components/more/OhmsSafespaceModal.tsx`)**:
   - Ported the owner command center (`safespace_screen.dart`, `super_admin_controls_screen.dart`, `risk_controls_screen.dart`, `freeze_modes_screen.dart`, `diagnostics_screen.dart`, `security_audit_logs_screen.dart`).
   - Integrated tabbed management for:
     - **Overview & Hub**: Quick access tiles to all system governance functions.
     - **System Controls**: Toggle `account_registration` and `import_plantilla` feature gates backed by `fn_update_governance_control` with mandatory audited reason prompt.
     - **Risk Controls**: Phase 1 capability restrictions (`risk_bulk_actions`, `risk_role_editing`, `risk_vcode_creation`, `risk_export_sensitive_data`, `risk_manual_deletion_actions`, `risk_import_rollback_actions`, `risk_cross_group_operations`) with non-emergency amber styling contract.
     - **Freeze Modes**: Domain suspension controls (`payroll_freeze`, `audit_freeze`, `recruitment_freeze`, `read_only_emergency`) via `fn_update_freeze_mode`.
     - **Diagnostics & Live Telemetry**: Live ping measuring round-trip RPC latency, RLS connection integrity, and freeze state evaluator.
     - **Security Audit Logs**: Stream of past governance actions from `fn_get_governance_audit_log`.

2. **Scoped Role Impersonation Utility (`src/components/more/SwitchRoleModal.tsx` & `src/components/DashboardAuthShell.tsx`)**:
   - Ported Flutter's `switch_role_screen.dart` allowing Super Admins to act as scoped roles for testing and view verification.
   - Wired to backend RPCs `get_active_acting_session`, `start_acting_session`, and `stop_acting_session`.
   - Features:
     - Quick switch buttons for common roles (Head Admin, Encoder, OM, HRCO, HR Personnel, Recruitment Team, Viewer).
     - Multi-select Group and Account scope limits.
     - Mandated justification reason input.
     - Persistent sticky Amber Acting Banner in `DashboardAuthShell.tsx` notifying the user of their active acting session with a one-click "Revert to Super Admin" button.

3. **Roving Coverage Groups Management (`src/components/more/RovingCoverageGroupsModal.tsx`)**:
   - Ported Flutter's `coverage_group_list_screen.dart` and `coverage_group_detail_screen.dart` to Web Data Control.
   - Wired to Supabase RPCs `list_coverage_groups` and `get_coverage_group_detail`.
   - Dual-pane layout:
     - Left pane: Searchable coverage group cards displaying code, account, position, required headcount, and active counts.
     - Right pane: Detailed inspection of cluster stores (highlighting anchor store), assigned headcount slots, and fulfillment status.

4. **Expanded Data Archival Center (`src/components/more/DataArchivalCenterModal.tsx`)**:
   - Added **Execute Archive / QA Reset** tab and **Batch History & Rollback** tab alongside existing Plantilla Restore, Vacancy Restore, and Audit Trail tabs.
   - Wired to Supabase RPCs:
     - `fn_get_archive_impact_preview`: Live counters for plantilla, vacancies, HR emploc, and Moses HQ items.
     - `fn_archive_all_operational_data` (QA Reset Archive), `fn_archive_plantilla_data`, `fn_archive_vacancy_data`, `fn_archive_hr_emploc_data`, and `fn_archive_moses_hq_data`.
     - Strict confirmation phrase validation (e.g. typing `ARCHIVE QA DATA` exactly) and mandatory operational reason.
     - `fn_get_archive_batch_history` and `fn_rollback_archive_batch` for 72-hour reversible batch rollbacks.

5. **Wired in `/more/page.tsx`**:
   - Replaced 404 links and placeholder alerts for `OHM's Safespace`, `Switch Role`, and `Roving Coverage Groups` with interactive modal launchers.
   - All 5 tabs (`overview`, `admin_tools`, `permissions`, `audit`, `data_control`) now have 100% working modules with 0 dead links or stubs.

### Verification Results
- `npx tsc --noEmit`: **PASS** (0 TypeScript errors).
- `npm run build`: **PASS** (19/19 static pages compiled and prerendered cleanly).

---


**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH**

### Summary of Changes

1. **Spreadsheet Utilities & Official Template Generators (`src/lib/utils/data_control_xlsx.ts`)**:
   - Ported official two-sheet XLSX template builders and client-side validators matching mobile implementations:
     - `downloadPlantillaImportTemplate()`: Two-sheet workbook (`IMPORT_TEMPLATE` + `VALIDATION_GUIDE`) with required store master and employee baseline columns.
     - `downloadVacancyImportTemplate()`: Two-sheet workbook with VCODE, requisition dates, headcount, and candidate pipeline fields.
     - `downloadMikaImportTemplate()`: Two-sheet workbook with Employee No., Fullname, Account, and biometric registration attributes.
     - `downloadPayrollCheckTemplate()`: Official 3-column payroll reconciliation workbook (`PAYROLL_TEMPLATE` + `GUIDE`).
     - `parseSpreadsheetToRows()`: General robust XLSX/CSV parser returning normalized column headers and row objects with empty row filtering.

2. **Data Control Query Hooks & Backend RPC Wiring (`src/lib/queries/dataControl.ts`)**:
   - Scope menu helpers: `useDataControlGroups()`, `useDataControlAccounts(groupId)`.
   - **Plantilla Baseline Import**: `submitPlantillaBaselineImport`, `fetchPlantillaImportBatches`, `fetchPlantillaImportRows`, `approvePlantillaImportBatch`, `rejectPlantillaImportBatch`.
   - **Vacancy Requisition Import**: `submitVacancyImport`, `fetchVacancyImportBatches`, `fetchVacancyImportRows`, `approveVacancyImportBatch`, `rejectVacancyImportBatch`.
   - **MIKA Biometric & Attendance**: `fetchMikaImportLogs`, `fetchMikaImportRows`, `submitMikaImport` (chunked 100-row inserts), `approveMikaImport` (isolated to checker; does not mutate employee roster).
   - **Payroll Reconciliation Checker**: `fetchGlobalPlantillaForPayrollCheck`, `reconcilePayroll` algorithm matching `payroll_check_service.dart` with normalized string matching for name/account and classification into:
     - Missing in Payroll
     - Missing in Plantilla
     - Paid Inactive
     - Mismatch
     - Duplicates
     - Clean
   - **Payroll Review Center**: `fetchPayrollReviewSessions`, `fetchPayrollReviewItems`, `createPayrollReviewSession`, `submitOpsPayrollReviewComment`, `closePayrollReviewItem`, `closePayrollReviewSession`.

3. **Built 5 Complete Web Modals in `src/components/more/`**:
   - **`PlantillaImportModal.tsx`**: Group & Account scope picker, XLSX template download, file dropzone, live parsed preview table with column validation, review queue for HA/SA approval or audited rejection, and historical import logs.
   - **`VacancyImportModal.tsx`**: Scope selector, vacancy XLSX template download, drag-and-drop file parser, requisition preview table, review queue with row inspection, and approval/rejection controls.
   - **`MikaImportModal.tsx`**: MIKA attendance upload, client-side cross-check against active Plantilla slots to automatically flag possible ghost employees (Type A) and account mismatches (Type B / Blocked), review queue, and approval.
   - **`PayrollImportModal.tsx`**: 3-column XLSX parser, live global plantilla reconciliation with tabbed discrepancy metrics, table inspection, and "Send to Ops Review" session publisher.
   - **`PayrollReviewCenterModal.tsx`**: Ops review session list with status filtering (All, Open, Closed), session drilldown with item filter tabs, Ops response / remarks resolution drawer, item closure, and session closure controls.

4. **Connected in `/more/page.tsx` (`tab=data_control`)**:
   - Replaced all 5 Phase 3 badges/alerts on the cards with direct modal trigger handlers (`onClick`) and active operational badges (`BASELINE`, `INTAKE`, `BIOMETRIC`, `CHECKER`, `REVIEWS`).
   - Mounted all 5 modals with state controls, allowing seamless cross-navigation (e.g. from Payroll Import directly into Payroll Review Center).

### Verification Results
- `npm run lint`: **PASS** (0 errors).
- `npm run build`: **PASS** (19/19 static pages compiled and prerendered cleanly).

---

## Execute Web "More" Module Parity — Wire Orphaned Modals, Add Data Control Tab & Build Core Governance Modals (ohm#w89p601b)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH**

### Summary of Changes

1. **Expanded `/more/page.tsx` Tab Navigation & Grid**:
   - Added 5th tab: **`Data Control`** (`tab=data_control`, Icon: `Database`) alongside `Overview`, `Admin Tools`, `Permissions & Access`, and `Audit & Integrity`.
   - Replaced rigid 3-card limits with responsive multi-row card grids (`grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4`).

2. **Wired Pre-built Orphaned Modals & Existing Routes**:
   - **`Overview` Tab (`tab=overview`)**:
     - Added **`User Management`** card linking to `/users`.
     - Added **`Account Requests`** card wired to open the new `AccountRequestsModal.tsx`.
   - **`Admin Tools` Tab (`tab=admin_tools`)**:
     - Added **`Data Archival Center`** card wired to open `DataArchivalCenterModal.tsx`.
   - **`Permissions & Access` Tab (`tab=permissions`)**:
     - Added **`Temporary Group Access`** card wired to open `TempPermissionModal.tsx`.
     - Added **`Access Control Center`** card wired to open `AccessControlCenterModal.tsx`.
   - **`Audit & Integrity` Tab (`tab=audit`)**:
     - Added **`Data Archival & Recovery`** card wired to open `DataArchivalCenterModal.tsx`.
   - **`Data Control` Tab (`tab=data_control`)**:
     - **`Import HR Emploc`**: Links directly to `/hr-emploc/import`.
     - **`Edit Lock Control`**: Wired to open `EditLockControlModal.tsx`.
     - **`Data Archival / Recovery`**: Wired to open `DataArchivalCenterModal.tsx`.
     - **`Global Store Transfer`**: Wired to open `GlobalStoreTransferModal.tsx`.
     - **`Roving Coverage Groups`**: Links to `/approvals?tab=coverage`.
     - **Remaining Bulk Importers** (`Import Plantilla`, `Import Vacancy`, `Import MIKA`, `Import Payroll`, `Payroll Review Center`): Rendered with accurate descriptions, icons, and Phase 3 badges for 100% visual parity with Mobile.

3. **Built High-Priority Missing Governance Modals**:
   - **`AccessControlCenterModal.tsx`**:
     - Ported from Mobile `access_control_center_screen.dart` and `module_visibility_service.dart`.
     - Super Admin user search, role baseline computation, per-user module visibility overrides (`allow` | `deny` | `inherit`) via `fn_set_module_visibility_override` RPC, and audit history via `fn_module_override_audit`.
   - **`GlobalStoreTransferModal.tsx`**:
     - Ported 4-step store transfer flow from Mobile (`global_store_transfer_screen.dart` and `global_store_transfer_service.dart`).
     - Step 1: Source scope (group, account). Step 2: Employee multi-select. Step 3: Target scope (group, account, store) with vacant slot assignment. Step 4: Review and audited reason submission.
   - **`AccountRequestsModal.tsx`**:
     - Built using backend RPC `get_approval_queue` and `approve_account_request_v2`.
     - Allows Super Admins to view pending, approved, and rejected registration requests, assign roles (excluding SA/HA) and operational group/account scopes, or reject with audited reasons.
     - Wired into both `/more` and `/users` header actions (`actionSlot`).

4. **Query & Model Extensions (`src/lib/queries/more.ts`, `src/lib/queries/accountRequests.ts`)**:
   - Added typed fetchers, mutations, and React Query hooks for `acc-users`, `acc-overrides`, `acc-audit`, store transfer options/submission, and account approval queues.

### Verification Results
- `npm run lint`: **PASS** (0 errors).
- `npm run build`: **PASS** (19/19 static pages compiled and prerendered cleanly).

---

## Fix Silent {0,0,0} Counts Fallback — Error Visibility Across Approvals Queues (ohm#4f8k1v7n)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH**

### Summary of Changes

1. **Error Throwing and Console Logging on 9 Count Queries (`src/lib/queries/requests.ts`, `src/lib/queries/hr_emploc.ts`)**:
   - Replaced silent `if (error || !data) return { pending: 0, approved: 0, rejected: 0 }` fallback across all 9 count functions:
     - `fetchHeadcountCounts`
     - `fetchNewStoreCounts`
     - `fetchVacancyClosureCounts`
     - `fetchApplicantMovementCounts`
     - `fetchDeactivationCounts`
     - `fetchAccountGroupTransferCounts`
     - `fetchRelieverCounts`
     - `fetchCoverageCounts`
     - `fetchEmplocDeletionCounts`
   - When an error is returned by Supabase, the function logs `console.error("[functionName] query failed:", error.code, error.message)` to aid debugging in browser console, then throws `RequestDataError` (or calls `throwHrEmplocError(error)`).
   - If `!data` (no error, empty/null payload), it safely returns `{ pending: 0, approved: 0, rejected: 0 }`.

2. **Retry Configuration on 9 Hooks (`src/lib/queries/requests.ts`, `src/lib/queries/hr_emploc.ts`)**:
   - Added `retry: 1` to `useHeadcountCounts`, `useNewStoreCounts`, `useVacancyClosureCounts`, `useApplicantMovementCounts`, `useDeactivationCounts`, `useAccountGroupTransferCounts`, `useRelieverCounts`, `useCoverageCounts`, and `useEmplocDeletionCounts`.

3. **Status Badge Error and Loading Visibility (`src/components/approvals/ActiveQueueReviewPane.tsx`)**:
   - Updated `QueueToolbarProps` and `QueueToolbar` to accept `isCountsLoading?: boolean` and `isCountsError?: boolean`.
   - Distinct badge states:
     - Loading: displays `"..."` in muted font.
     - Error / Undefined: displays quiet `"—"` in muted font.
     - Success: displays the numeric count (with warm accent styling when pending > 0 on the pending tab).
   - Removed `= { pending: 0, approved: 0, rejected: 0 }` destructuring default assignments from all 9 count hook invocations so `0` is rendered only after a successful fetch.
   - Wired `isCountsLoading` and `isCountsError` props into the `QueueToolbar` for all 9 review queues (`new_stores`, `vacancy_closures`, `hr_emploc_deletions`, `headcount`, `applicant_movements`, `deactivations`, `account_group_transfers`, `coverage`, `relievers`).

4. **Preserved Scopes & Unconfirmed Root Cause**:
   - Aggregates (`fetchRequestCategoryCounts`), sidebar Approvals badge, and category tab navigation badges remain untouched and resilient.
   - The root cause of the Vacancy Closures Pending badge mismatch remains unconfirmed pending browser Network tab inspection (`GET vacancy_closure_requests?select=status`).
   - No DB writes, migrations, or RLS modifications performed.
   - "Withdrawn" status handling in `VacancyClosureDataTable.tsx` remains untouched.

### Verification Results
- `npx tsc --noEmit`: **PASS** (0 errors).
- ESLint (targeted): **PASS** on `src/lib/queries/requests.ts`, `src/lib/queries/hr_emploc.ts`, and `src/components/approvals/ActiveQueueReviewPane.tsx` (0 errors, 0 warnings).
- `npm run build`: **PASS** (18/18 static pages compiled and prerendered cleanly).

---

## Minimalist Web Pass — New Sidebar + Approvals Restyle + Global Minimal Tokens (ohm#9d4t2w6c)

**Status: COMPLETE — CLIENT-SIDE PRESENTATION & TOKENS ONLY, MAIN BRANCH**

### Summary of Changes

Successfully executed a comprehensive minimalist visual pass across OHMployee Web matching the approved design specification and mockup `OHMployee Web - Minimal Approvals.html` without modifying any business logic, routing, RBAC, data models, or backend/Supabase schemas:

1. **Global Minimal Tokens (`src/app/globals.css`)**:
   - Palette calibrated to minimal tokens (`--bg: #ffffff`, `--side: #fafafb`, `--soft: #f4f4f6`, `--line: #ececef`, `--text: #16161a`, `--muted: #8a8a94`, `--accent: #2b4fd6`, `--ok: #1a8a5a`, `--bad: #c4372b`, `--warn: #b7791f`, `--pillbg: #eef2ff`).
   - Removed drop shadows on cards, tables, topbar, and sidebar; maintained elevation and shadows exclusively on floating overlays (modals, dropdowns, popovers, drawers).
   - Preserved all token alias names and retained existing font variables (`DM_Sans` and `DM_Mono`).

2. **Sidebar Rebuild (`src/components/Sidebar.tsx`, `src/components/DashboardAuthShell.tsx`)**:
   - Implemented exact mockup hierarchy: Header with "OHMployee" (15px bold) and "Admin Command" (12px muted).
   - Primary group: Vacancy, HR Emploc, Plantilla with 14px high-contrast typography.
   - 1px hairline divider (`border-[var(--line)]`).
   - Secondary group: Dashboard, CENCOM, Approvals, User management, Team directory, Notifications, Reports, Settings, More with 13.5px muted typography.
   - Dynamic trailing badge on Approvals displaying the aggregate pending count (`bg-[var(--accent)] text-white text-[10.5px] px-1.5 py-0.2 rounded-full font-bold`).
   - Active state styling: Soft background fill (`bg-[var(--soft)] text-[var(--text)] font-semibold`) with zero icons, zero colored accent bars, and zero shadows.
   - Footer: Rendered user full name and role in muted small typography.
   - Fully preserved responsive drawer handling, logout flow, and RBAC module visibility (`visibleModules`).

3. **Admin Topbar Flat Pass (`src/components/AdminTopbar.tsx`)**:
   - Swapped heavy shadow and border styling for a clean flat `bg-[var(--bg)] border-b border-[var(--line)]` layout with tracking uppercase eyebrow breadcrumb.

4. **Approvals Page Layout & Navigation (`src/app/(dashboard)/approvals/page.tsx`, `src/components/approvals/RequestCategoryNavigation.tsx`)**:
   - Card container converted to flat `rounded-xl border border-[var(--line)] bg-[var(--surface-base)]` with zero shadows.
   - Tab strip: Outline-styled active tab (`border border-[var(--line)] bg-[var(--surface-base)] font-semibold text-[var(--text)]`) and quiet accent badge (`bg-[var(--pillbg)] text-[var(--accent)] border border-blue-200/50`) preserving unacknowledged notification tracking without logic alteration.

5. **Operational States & Queue Toolbar (`src/components/shared/DataState.tsx`, `src/components/approvals/ActiveQueueReviewPane.tsx`)**:
   - Removed decorative SVG graphics from empty/loading/error states in favor of clean operational typography.
   - Built unified `QueueToolbar` across all 9 review queues: flat search input with 1px hairline border, segmented status control with embedded counts, and ghost refresh button.

6. **All 9 Approvals Queue Data Tables Restyled**:
   - Restyled `VacancyClosureDataTable.tsx`, `HeadcountDataTable.tsx`, `NewStoreDataTable.tsx`, `CoverageDataTable.tsx`, `DeactivationDataTable.tsx`, `ApplicantMovementDataTable.tsx`, `AccountTransferDataTable.tsx`, `RelieverDataTable.tsx`, and `HrEmplocDeletionDataTable.tsx`.
   - Applied sticky table headers with muted `text-[12.5px] font-medium`, row hover (`hover:bg-[var(--soft)]`), mono bold VCode/Request # (`font-mono font-bold text-[13px] text-[var(--text)]`), small outlined Account pill (`rounded-[6px] border border-blue-200/50 bg-[var(--pillbg)] text-[var(--accent)]`), branch name stacked beneath store, timestamp stacked beneath requester name, quiet outlined red Reject action (`border border-[var(--bad)]/40 text-[var(--bad)] hover:bg-[var(--bad)]/10`), and solid green Approve button (`bg-[var(--ok)] text-white hover:bg-emerald-700`).

7. **Report on Pending Badge (0 vs 2 Pending Rows on Vacancy Closures)**:
   - *Cause 1 (Client Acknowledgment)*: Selecting any category tab immediately triggers `handleSelectCategory()`, adding the key to `acknowledgedCategories` and deliberately suppressing the category tab badge.
   - *Cause 2 (RLS Scoping Policy)*: `fetchVacancyClosureCounts()` selects `status` from `vacancy_closure_requests`. Under policy `vacancy_closure_req_read_scoped`, non-admin or unauthenticated contexts yield 0 rows, returning `{ pending: 0 }`.
   - *Cause 3 (Missing Invalidation)*: Mutation hook `useReviewVacancyClosureRequest()` invalidates `['vacancy-closure-requests']` and `['request-category-counts']`, but fails to invalidate `['vacancy-closure-counts']`.

### Verification Results
- `npx tsc --noEmit`: **PASS** (0 errors).
- `npm run build`: **PASS** (18/18 static routes compiled and prerendered cleanly in 56s).
- `npx eslint`: **PASS** on all 16 touched components/pages (0 errors, 0 warnings).
- Git branch: `main` only (no new branches created; no DB writes).

### Files Changed
- `src/app/globals.css`
- `src/components/DashboardAuthShell.tsx`
- `src/components/Sidebar.tsx`
- `src/components/AdminTopbar.tsx`
- `src/app/(dashboard)/approvals/page.tsx`
- `src/components/approvals/RequestCategoryNavigation.tsx`
- `src/components/shared/DataState.tsx`
- `src/components/approvals/ActiveQueueReviewPane.tsx`
- `src/components/approvals/VacancyClosureDataTable.tsx`
- `src/components/approvals/HeadcountDataTable.tsx`
- `src/components/approvals/NewStoreDataTable.tsx`
- `src/components/approvals/CoverageDataTable.tsx`
- `src/components/approvals/DeactivationDataTable.tsx`
- `src/components/approvals/ApplicantMovementDataTable.tsx`
- `src/components/approvals/AccountTransferDataTable.tsx`
- `src/components/approvals/RelieverDataTable.tsx`
- `src/components/approvals/HrEmplocDeletionDataTable.tsx`
- `.ai/briefing.md`
- `.ai/handoff.md`

---

## Baseline Audit of ohmployee_web Architecture, Theme, and Core Modules (ohm#w10a482b)

**Status: COMPLETE — READ-ONLY BASELINE AUDIT & IMPLEMENTATION ROADMAP**

### Summary of Changes

Conducted a comprehensive baseline architecture, theme, and module audit of `ohmployee_web` to establish the architectural foundation for mirroring recent mobile capabilities across:
1. Global Light Mode default enforcement.
2. Headcount Quota Revision (`Adjust Quota` and `Request HC Adjustment` actions, commitment safety floor formula $\max(1, occupied + hr\_processing + pipeline)$).
3. Request Center menu label streamlining (dropped "Request"/"Requests" suffixes across all 8 modules) and live pending count badges.
4. CENCOM slot-authority metric alignment (formula: $actual \ge required \implies vacant = 0, required = actual, mfr = 1.0$) and group performance views.

**Deliverables created:**
- `docs/audit/baseline_audit_architecture_theme_modules_2026-10-09.md`: Comprehensive audit report covering framework discovery, Tailwind v4 styling tokens, Supabase client/auth patterns, light theme enforcement instructions, and step-by-step module implementation plans.
- `scripts/ai-finish.ps1`: End-of-task orchestrator script for PowerShell environments in `ohmployee-web`, managing scope file declarations and invoking `finish.js`.

---

## Plantilla Web — Account-First Gate, Scope Parsing Fix, Unified KPI Summary, & Group Filters (ohm#9m2v5jqk)

**Status: COMPLETE — CLIENT-SIDE ONLY, STAGING DEPLOYED & VERIFIED**

### Summary of Changes

Implemented the account-first entry flow for the Plantilla web module in compliance with audit `ohm#7k3n9dqm` (P1 gap) and ADR-001 coverage architecture locks (`ohm#4t8w2xhp`), resolved a critical authentication scope parsing bug, disabled dark mode app-wide, unified page layouts to always show summary cards, and added a group selection dropdown on the account selector.

- **Unified Summary Cards Layout**: Refactored Plantilla layout to render the KPI summary cards (**Required / Actual / HR Process / Vacant**) at the top of the page across both the Account Selection view and Roster directories.
  - The `AdminPageHeader` ("Plantilla Directory" title/subtitle block) is gated behind `accountId` resolution, removing the redundant header details on the Account Selection dashboard.
  - When no account is selected (`!accountId`), `summaryQuery` executes with `accountId := null`, returning the aggregate cross-account (global) summary metrics for all authorized accounts.
  - Selecting an account or group automatically recalculates and updates these cards in real-time.
  - Derived total `required` count dynamically as `Actual + HR Process + Vacant`.
- **Group Select Dropdown on Selection View**: Added a `<select>` dropdown beside the "Search accounts..." input on the Account Selection dashboard.
  - Dynamically populates with unique groups (`uniqueGroups` via `useMemo` of `allowedAccountsQuery` data) associated with the user's allowed billing accounts.
  - Filters the cards grid by group and updates the global summary metrics at the top to reflect only the selected group's counts.
- **Dark Mode Removal**: Completely deleted the `@media (prefers-color-scheme: dark)` styling block in `globals.css` to lock the user interface to light mode.
- **User Context Scope Parsing Fix**: Resolved a critical pre-existing bug in `src/lib/auth.ts` where `loadCurrentUserContext` attempted to read flat non-existent properties (`group_scope_mode`, `group_scope_ids`, `account_scope_mode`, `account_scope_ids`) directly from `rpcRow`. Because the database RPC `get_web_current_user_context` returns `group_scope` and `account_scope` as nested JSONB objects, the client resolved the scope mode as `"none"`, incorrectly locking out all accounts (including Super Admin). Refactored to cleanly extract the mode and list mapping from the raw JSONB objects while resolving all TypeScript/eslint typecasting constraints.
- **Gated Queries**: Modified React Query hooks (`employeeQuery`, `storeQuery`) to be conditionally enabled only when `accountId` is resolved (`enabled: !!accountId`).
- **URL Hydration & Deep-linking**: Integrated Next.js `useSearchParams` on mount to check for pre-existing `accountId` parameters in the URL, executing search queries immediately and avoiding redundant selection screens.
- **Auto-select / Auto-fire Scoped Roles**: Added logic to bypass selection screen for scoped role users (OM, HRCO, etc.) who are authorized for exactly one billing account in `get_web_current_user_context()`. The single account is auto-selected and fired automatically.
- **Fail Closed**: If the user's authorized account list is empty or unresolved, the queries remain disabled.
- **Mobile-Parity Account Selector Dashboard**: Built a curated grid-based selection interface (2/3 columns depending on screen size) for broad-access and multi-account users. Cards feature:
  - Account group name prefixes (`Group [Name] • `).
  - Left icon block (gated by `is_pool_account` column value): Network/branches icon (`Share2`) in a light purple container for pools; store icon (`Building`) in a light blue container for regular accounts.
  - Interactive chevrons (`ChevronRight`) and dynamic status badges: `POOL` (purple) for pool accounts, and `WARNING` (amber) if the Manpower Fill Rate (MFR) drops below 80%.
  - Real-time personnel stats: `HC [Actual]/[Required] • Vacant [Vacant] • Pipeline [Pipeline]` details.
  - Manpower Fill Rate (MFR) Bar: Renders a horizontal orange progress bar showing fill rate percentages.
  - Parallel Client summaries: Uses React Query `useQueries` to fetch individual summaries for all allowed accounts in parallel, resolving metrics dynamic client-side.
  - Real-time client-side search/filter on account name.
- **Back Control Navigation**: Added a back-control link for multi-account users to reset selection, clearing states and URL query parameters to return to the selection list.
- **Dual-View Consistency**: Ensured gating logic and selector screens apply uniformly to both the Employee-centric and Store-centric views.
- **Clean Compilation**: Verified Next.js build passes cleanly (`Compiled successfully`) and ESLint checks verify zero warnings/errors in the modified Plantilla files.

### Files Changed
- `src/app/globals.css` — Removed prefers-color-scheme dark media query to enforce light mode app-wide.
- `src/lib/auth.ts` — Refactored user context scope mapping to parse JSONB `group_scope` and `account_scope` columns correctly.
- `src/lib/queries/plantilla.ts` — Redefined `PlantillaSummary` and updated `normalizeSummary` to map Required, Actual, HR Process, and Vacant metrics.
- `src/app/(dashboard)/plantilla/page.tsx` — Implemented entry-flow gate logic, URL params, auto-fire checks, selector layout, back control, unified summary cards headers, and dynamic group filter.

---

## ADR-001 Compliance Check — Plantilla Account-First Flow (ohm#4t8w2xhp)

**Status: COMPLETE — READ-ONLY COMPLIANCE VERDICT, NO CODE CHANGES**

### Summary of Changes

Conducted a thorough compliance check of the proposed client-side account-first flow for the Plantilla module against ADR-001 (Plantilla Slot as Single Source of Truth). Verified security boundaries, RLS/RPC integration, and Regression Guard Protocol concerns.

**Deliverable created:** `docs/audit/adr001_plantilla_account_gate_2026-07-11.md`

### Findings
- **Verdict:** CONDITIONAL PASS.
- **Conditions:**
  1. Auto-select and auto-fire for single-account scoped roles.
  2. Implement gating consistently across both Employee-centric and Store-centric views.
  3. Wire search/list React Query hooks using `enabled: !!accountId`.
  4. Ensure compatibility with URL query parameters for deep-linking.
  5. Retain backend security / RLS as the absolute authority.
- **Scope:** Purely client-side gating change. No backend migrations, RPC contract revisions, or database schema modifications.

---

## Web-Mobile UX Parity Audit — All Modules (Read-Only) (ohm#7k3n9dqm)

**Status: COMPLETE — READ-ONLY AUDIT, NO CODE CHANGES**

### Summary of Changes

Full read-only navigation/entry-flow audit across all in-scope web modules vs. their mobile counterparts, using the selection-first progressive-disclosure pattern as the reference target.

**Deliverable created:** `docs/audit/web_mobile_parity_2026-07-11.md`

### Audit Findings

| Module | Gap? | ADR-001 | Priority |
|--------|------|---------|----------|
| Dashboard | **No** — aggregate surface, backend scopes via `auth.uid()` | ⚠️ Yes (no change needed) | N/A |
| Vacancy | **Partial** — full list loads on mount; account selector is optional text input, not a gating step | ⚠️ Yes | P2 |
| HR Emploc | **Partial** — full queue loads on mount; lower priority (workflow queue, not directory) | No | P3 |
| Plantilla | **YES (confirmed reference case)** — full roster loads on mount; mobile requires account selection first | ⚠️ Yes | P1 |
| CENCOM | **Cannot assess** — scaffold stub only, no state document | ⚠️ Yes | P4 |
| Approvals | **Cannot assess** — scaffold stub only, no state document | No | P5 |

### Key Decisions / Flags

- **Plantilla (P1):** The account-first entry change is confirmed-as-approved in the prompt but NOT YET implemented in code — `plantilla/page.tsx` still fires both `summaryQuery` and `employeeQuery` on mount with no `enabled` guard on `accountId`. Separate implementation prompt required.
- **5 Regression Guard Protocol flags** raised (RGP-001 through RGP-005) covering: roster auto-fire for scoped roles, KPI summary inconsistency when list is gated, broad-access admin workflow disruption on Vacancy, store-view consistency with employee-view gate, and detail drawer open/close state during page restructuring.
- **4 ADR-001 compliance audit scope entries** defined: Plantilla, Vacancy, CENCOM, Dashboard (no-change noted).
- **CENCOM and Approvals** are scaffold stubs with no state documents — parity cannot be assessed until `cencom_web_state.md` and `approvals_web_state.md` are created.

### Files Changed

- `docs/audit/web_mobile_parity_2026-07-11.md` — **[NEW]** Full audit report.
- `.ai/briefing.md` — prepended `ohm#7k3n9dqm` to Last Completed Tasks.
- `.ai/handoff.md` — prepended this entry.
- No `docs/state/<module>_state.md` files modified (audit only, no behavior change).

### Not Changed

- No source code modified.
- No migrations run.
- No RPC calls that write.
- No module state documents updated (read-only audit pass).

---

## ohmployee-web — Add .gitignore Entries + Push 12 Commits to origin/main (ohm#2vbn6xkq)

**Status: COMPLETE — CONFIG UPDATED, COMMITTED VIA FINISH.JS, REMOTE SYNCED**

### Summary of Changes

Two small, low-risk cleanup steps:
1. **.gitignore updated**: Added `.claude/` and `supabase/.temp/` as new entries to `.gitignore` under the `# tooling` section. Verified that `git status` no longer lists these directories as untracked.
2. **Git Commit**: Committed the `.gitignore` change using the `finish.js` gate script. Since the target environment is Staging (`qqiiznmqxfoamqytjica`), the script auto-committed the staged modifications and `.ai` metadata updates.
3. **Remote Push**: Verified that the current branch is `main` and tracked `origin/main` correctly. Ran `git push origin main` successfully. Checked `git status` to verify the local branch is now in sync with `origin/main` (0 ahead, 0 behind).
4. **Documentation Sync**: Updated `.ai/briefing.md`, `.ai/handoff.md`, and `docs/state/web_target_state.md` to reflect the changes.

### Commits Pushed
- `(cleanup commit)` — `auto: ohm#2vbn6xkq — ohmployee-web — Add .gitignore Entries + Push 12 Commits to origin/main`
- `b2369b8` — `docs: update shared briefing, handoff, and target state documentation`
- `ad1ec5f` — `auto: ohm#5jhq8mwv — ohmployee-web — Commit 443 Backfilled Migration Files via finish.js Gate`
- `938ba47` — `auto: ohm#8kfq3wzn — ohmployee-web — Git Status Audit + Mirror ai-finish.sh PROD Gate Script`
- `80c6fef` — `auto: ohm#7bxk1nte — ohmployee-web — Fix HR Emploc row_capabilities Missing RBAC Fields (Blocking Workflow)`
- `65ca3db` — `docs: update shared briefing, handoff, and target state documentation`
- `214a1b0` — `auto: ohm#7k2m9xq4 — Scaffold docs/ui/ structure (Mobile + Web layout separation)`
- `7a848da` — `auto: ohm#7bxk1nte — Fix HR Emploc row_capabilities Missing RBAC Fields (DB Migration)`
- `bd3cb42` — `auto: ohm#1cme8bzn — Fix vw_vacancy_detail Missing Columns (DB Migration)`
- `50a1f8c` — `auto: OHM2026_1097 — Design Token System Handoff (Font Setup)`
- `fbc1275` — `auto: ohm#6dq9wshl — Fix Client-Side Field/Param Mismatches (Vacancy + HR Emploc)`
- `01a52ab` — `auto: ohm#8vt3nkrq — Split Inactive Employees into Separate Tab/View — Plantilla`
- `6f83790` — `auto: ohm#3k8h5wte — Establish Staging Environment (Env Split)`

---

## ohmployee-web — Commit 443 Backfilled Migration Files via finish.js Gate (ohm#5jhq8mwv)

**Status: COMPLETE — LOCAL COMMITTED ONLY, NO DATABASE COMMANDS RUN**

### Summary of Changes

Committed the 443 untracked migration files (added in `ohm#6ynv2crx`) under `supabase/migrations/` using the `finish.js` gate script.

- **Active Env Verification**: Confirmed environment resolved to `STAGING` (ref `qqiiznmqxfoamqytjica.supabase.co`) from `.env` before running.
- **finish.js safety gate**: Scoped the commit to exactly the 443 untracked migration files under `supabase/migrations/` by setting `OHM_SCOPE_FILES` to the colon-separated list of all 443 migration file paths.
- **Commit creation**: Run `npm run finish` which triggered auto-commit on STAGING without human interaction or requiring `CONFIRM-PROD`.
- **Git status verification**: Confirmed git status is clean of any untracked or modified migration files.
- **Not touched**: No database commands were executed (no db push, db pull, or apply_migration). No manual file content changes were made.

---

## ohmployee-web — Clean Up Stale Duplicate schema_migrations Rows (PROD) (ohm#9frm5ktz)

**Status: COMPLETE — PROD TRACKING-TABLE MUTATION, GATED**

### Summary of Changes

Executed step 3 of the reconciliation plan from `ohm#3wpx7ldk` (`docs/state/web_target_state.md` § 6.D/E): removed the 2 repair-artifact duplicate rows in `supabase_migrations.schema_migrations` on PROD (`rwxelulyapjgaarlwkus`) left behind by `ohm#4qwz9tgk`'s `migration repair` runs.

- **PROD Push Gate**: Fresh out-of-band passphrase was required and obtained from the user in this session before any write; no previously-stated value was accepted.
- **Re-query before touching anything**: Queried PROD live for the 4 candidate rows — state matched `docs/state/web_target_state.md` § 6.D exactly, confirming no drift since the read-only investigation.
- **Before state (4 rows)**:
  | version | name |
  | :--- | :--- |
  | `20260711025531` | `20262606000010_fix_vw_vacancy_detail_missing_columns` |
  | `20260711034157` | `20262606000020_add_hr_emploc_row_capabilities_fields` |
  | `20262606000010` | `fix_vw_vacancy_detail_missing_columns` |
  | `20262606000020` | `add_hr_emploc_row_capabilities_fields` |
- **Action**: `DELETE FROM supabase_migrations.schema_migrations WHERE version IN ('20260711025531','20260711034157');` — the 2 stale auto-generated-timestamp rows only.
- **After state (2 rows, verified)**:
  | version | name |
  | :--- | :--- |
  | `20262606000010` | `fix_vw_vacancy_detail_missing_columns` |
  | `20262606000020` | `add_hr_emploc_row_capabilities_fields` |

### Not touched (by design)
- No other `schema_migrations` rows.
- No view/function definitions changed — tracking table only.
- No `supabase db push`/`db pull` run.

### Next suggested step
Section 6 (Migration Gap Classification & Reconciliation Plan) is now fully resolved — both the 443-file backfill and this tracking cleanup are complete. Per § 5/§ 6.E item 4, the underlying mis-recording behavior for future MCP `apply_migration` calls is still unaddressed procedurally; consider a follow-up to always chain an MCP apply with an immediate `migration repair --status applied <real-version>`.

---

## ohmployee-web — Backfill 443 Missing Migration Files from Mobile Repo (ohm#6ynv2crx)

**Status: COMPLETE — LOCAL FILE COPY ONLY, NO DATABASE COMMANDS RUN**

### Summary of Changes

Executed the bulk-copy step proposed (but not run) in `ohm#3wpx7ldk` (`docs/state/web_target_state.md` § 6).

- **Re-verification before copying**: Re-ran the mobile-vs-web comparison rather than trusting the prior list. Confirmed unchanged: mobile repo (`D:/Projects/OHMployee/supabase/migrations/`) has 443 top-level `.sql` files (448 total entries minus 4 non-migration `.json` housekeeping files and the `_legacy_unversioned/` folder), web repo had 2. Confirmed zero filename collisions between the 443 and the 2 existing web-local files.
- **Copy**: Copied all 443 `.sql` files verbatim (byte-for-byte, no content modification) from the mobile repo into `ohmployee-web/supabase/migrations/`.
- **Verification**: `md5sum` checksum comparison of all 443 copied files against their mobile-repo source — **identical, zero mismatches**. Local file count in `ohmployee-web/supabase/migrations/` now 445 (2 pre-existing + 443 backfilled).
- **Git status check**: `git status --short supabase/migrations/` shows exactly 443 new untracked (`??`) files, no modifications to any existing file in that directory (the 2 pre-existing web-specific migrations `20262606000010`/`20262606000020` are untouched).

### Not touched (by design — file-copy-only prompt)
- No `supabase db push`, `db pull`, `migration repair`, or any other CLI/MCP database command.
- No changes to `schema_migrations` on any environment (the 2 duplicate repair-artifact rows flagged in § 6.D remain unaddressed — still needs its own PROD-gated prompt).
- No commit made — files are staged as untracked only; committing is left to the finish.js gate per the prompt's instructions.
- Full classification/verification detail: `docs/state/web_target_state.md` § 6 (now marked complete).

### Next suggested step
Per the original plan (§ 6.E), an optional read-only `supabase migration list --linked` run would confirm all 443 now show as "in sync" against PROD — not run in this prompt since it wasn't in scope, but safe to do next.

---

## ohmployee-web — Investigate & Reconcile ~400-Migration Local/PROD Gap (Read-Only) (ohm#3wpx7ldk)

**Status: INVESTIGATION COMPLETE — READ-ONLY, NOTHING WRITTEN TO PROD/STAGING/TRACKING**

### Summary of Findings

Full-shape investigation of the ~400-migration gap flagged in `ohm#4qwz9tgk`, cross-referencing PROD's `supabase_migrations.schema_migrations` (447 rows, via MCP `list_migrations`) against both this repo's local `supabase/migrations/` (2 files) and the mobile repo's (`D:/Projects/OHMployee/supabase/migrations/`, 448 files).

**Classification — clean split, no ambiguous cases:**
- **443 migrations (category a)**: missing from web, present in mobile repo — version AND descriptive-name matched PROD's `schema_migrations` exactly for all 443, zero mismatches, zero filename collisions. Safe to bulk-copy verbatim.
- **0 migrations (category b)**: no true orphans — nothing exists only as raw PROD history with no source-controlled file anywhere.
- **0 migrations (category c)**: nothing needed individual/unclear review.
- **2 already-local**: the `20262606000010`/`20262606000020` web-specific fixes already in this repo (confirmed via `diff` that mobile does NOT have these two — expected, they were authored directly in web repo).

**New finding not previously known**: the `supabase migration repair --status applied <version> --linked` runs from `ohm#4qwz9tgk` did **not** clean up the original mis-recorded rows — they inserted new rows for the correct version instead. PROD's `schema_migrations` now has **4 rows** for what should be 2 migrations (`20260711025531`/`20262606000010` pair and `20260711034157`/`20262606000020` pair). Low risk as-is, but flagged for a future cleanup decision (needs its own PROD-gated prompt — deletion of tracking rows is a PROD mutation).

**Also noted (not actionable)**: mobile repo's `supabase/migrations/_legacy_unversioned/` holds 54 pre-2026-05-20 files that predate PROD's earliest tracked migration — evidence of an earlier baseline/history reset on the mobile side, unrelated to this gap.

### Proposed Reconciliation Plan (NOT EXECUTED)

1. Bulk-copy the 443 verified `.sql` files from mobile repo into web repo's `supabase/migrations/` (local-file-only, low risk, safe to automate).
2. Run `supabase migration list --linked` (read-only) afterward to confirm sync.
3. Separately scoped, PROD-gated prompt: decide on deleting the 2 stale timestamp-keyed tracking rows.
4. Procedural fix needed to prevent recurrence: any future MCP `apply_migration` will keep mis-recording versions the same way until followed by an immediate `migration repair`.

### Tool Recommendation

`supabase db pull` against PROD is **not recommended** — it would flatten 447 reviewable incremental migrations (including one with a `DROP VIEW ... CASCADE`) into a single undifferentiated current-state snapshot, obscuring history that's actually safe to reconstruct file-by-file. The surgical bulk-copy approach is safer and was verified to have zero content/name collisions.

### Not Touched (by design — read-only prompt)
- No `supabase db pull`, no migration repair commands, no file copying/writing, no PROD/staging schema changes of any kind.
- Full details, classification table, and per-category risk assessment: `docs/state/web_target_state.md` § 6.

---

## ohmployee-web — CLI-Based PROD Push: HR Emploc row_capabilities Migration (ohm#4qwz9tgk)

**Status: COMPLETE — PRODUCTION DEPLOYED (via MCP fallback after CLI blocker)**

### Summary of Changes

**Part A — Pre-flight diagnostic (critical finding, resolved):**
- Queried `supabase_migrations.schema_migrations` on PROD directly and found migration `20262606000010` (applied earlier via MCP `apply_migration`) was recorded under an auto-generated timestamp version (`20260711025531`) instead of its real version key `20262606000010`. Confirmed root cause: MCP `apply_migration` does **not** write to `schema_migrations` the same way CLI push does.
- Confirmed via `supabase migration list --linked` that this would have caused `supabase db push` to attempt to re-run both migration 010 (risky — its `DROP VIEW ... CASCADE` could cascade-drop objects added by later, unrelated migrations that depend on `vw_vacancy_detail`) and 020, not just 020.
- Ran `supabase migration repair --status applied 20262606000010 --linked` to correct the tracking row. Re-verified via `supabase migration list --linked`: scope reduced to single-migration (020 only).

**Bigger structural finding (reported, not fixed — separate task needed):**
- Discovered this repo's local `supabase/migrations/` directory only contains 2 files, while PROD's `schema_migrations` table has ~400 applied migrations. Most of PROD's schema history was applied directly via MCP and never saved as local migration files. This means `supabase db push` cannot function safely in general for this project — it will always see hundreds of "remote-only" versions and abort. Confirmed live: `supabase db push --linked --yes` failed immediately and its own suggested fix was to mark ~400 production migration versions as "reverted," which was correctly refused as out-of-scope and unsafe. **Recommend a dedicated task to reconcile/backfill the local migrations directory against PROD's actual applied history before CLI `db push` is relied upon again.**

**Part B — Push (executed via MCP fallback, not CLI, after CLI was confirmed blocked by the structural issue above):**
- User explicitly authorized falling back to MCP `apply_migration` for migration `20262606000020_add_hr_emploc_row_capabilities_fields` only, after CLI `db push` proved unworkable.
- PROD Push Gate: passphrase `DRACARYS` was requested; user confirmed reuse of the prior push's passphrase was intentional (flagged as a reuse of a value already stored in this file, user explicitly confirmed anyway).
- Applied migration 020 to PROD (`rwxelulyapjgaarlwkus`) via `apply_migration`, updating `list_web_hr_emplocs` and `get_web_hr_emploc_detail` to return `can_tag_deficiency`, `can_assign_employee_no`, `can_review_deletion`, and `can_review_correction` in `row_capabilities`.
- Repaired the resulting tracking mismatch the same way as 010 (`supabase migration repair --status applied 20262606000020 --linked`) so future `db push` attempts see it as applied.

### Verification
- Called `list_web_hr_emplocs` and `get_web_hr_emploc_detail` live on PROD under a simulated Super Admin session. Confirmed both RPCs return the new `row_capabilities` keys correctly (all `false` for the one existing "Transferred" status row on PROD, which is correct per the RPC's status-gated logic).

### Not touched
- `--include-all` flag: not used.
- No other migrations, modules, or client code touched.
- The ~400-migration local/remote drift: reported only, intentionally out of scope.

---

## ohmployee-web — Git Status Audit + Mirror ai-finish.sh PROD Gate Script (ohm#8kfq3wzn)

**Status: COMPLETE — CLIENT-SIDE ONLY, STAGING VERIFIED**

### Summary of Changes

1. **Git Status Audit (Part A)**:
   - Audited the uncommitted repository state. Identified 9 files containing modifications or additions accumulated from prior tasks (`ohm#3k8h5wte`, `ohm#8vt3nkrq`, `ohm#6dq9wshl`, `OHM2026_1097`, `ohm#1cme8bzn`, `ohm#7bxk1nte`, `ohm#7k2m9xq4`).
   - Staged and committed these changes in 8 distinct git commits corresponding to each task boundary.

2. **Mirror PROD Gate Script (Part B)**:
   - Designed and created a cross-platform, environment-aware Node script [finish.js](file:///D:/Projects/OHMployee-web/scripts/finish.js) to act as the git commit safety orchestrator.
   - The script parses [.env](file:///D:/Projects/OHMployee-web/.env) to read the active `NEXT_PUBLIC_SUPABASE_URL` and matches the project reference:
     - **STAGING** (`qqiiznmqxfoamqytjica`) target: proceeds to auto-stage in-scope files and commit automatically.
     - **PRODUCTION** (`rwxelulyapjgaarlwkus`) or **UNRESOLVED** (ambiguous/missing env) target: halts the process, warns the user, and requires them to manually enter `CONFIRM-PROD` to proceed.
   - Integrates with git to stage tracked changes and task-scoped untracked files declared in `OHM_SCOPE_FILES`.
   - Wired `finish` script as a command shortcut inside `package.json` (`npm run finish` or `pnpm finish`).

3. **Verification**:
   - Verified Staging auto-commit behavior successfully (committed the orchestrator files automatically with `auto` prefix and parsed briefing metadata).
   - Verified Production safety gate (blocked commit and aborted when `CONFIRM-PROD` was refused).
   - Verified Unresolved safety gate (blocked commit and aborted when `.env` was missing/unparsed).

---

## ohmployee-web — Fix HR Emploc row_capabilities Missing RBAC Fields (Blocking Workflow) (ohm#7bxk1nte)

**Status: COMPLETE — STAGING DEPLOYED & VERIFIED**

### Summary of Changes

Fixed the `row_capabilities` structural gap blocking HR Emploc admin workflows on STAGING:
1. **Migration Version**:
   - Created and applied DB migration version `20262606000020_add_hr_emploc_row_capabilities_fields.sql` to STAGING (`qqiiznmqxfoamqytjica`) only.
2. **RPC and View Logic Updates**:
   - Updated `list_web_hr_emplocs` and `get_web_hr_emploc_detail` to compute and return the missing keys (`can_tag_deficiency`, `can_assign_employee_no`, `can_review_deletion`) in the `row_capabilities` JSONB payload.
   - Also projected `can_review_correction` to `list_web_hr_emplocs` for consistency.
   - Refactored `is_pending_deletion` and capabilities like `can_withdraw_deletion_request`, `can_approve_deletion`, `can_reject_deletion`, and `can_review_deletion` to check for active deletion requests in the `hr_emploc_deletion_requests` table using `EXISTS (...)` rather than looking for `hr_status = 'Pending Deletion'` in the table (which is prevented by check constraints).
3. **Verification**:
   - Simulated different roles (`HR Personnel`, `Encoder`, `Head Admin`, `Super Admin`) across different workflow states (Pending, Complete, Pending Deletion) inside a transaction.
   - Confirmed the RPCs return correct capability bits for all roles and lock-states (e.g. `Head Admin` is blocked from `can_assign_employee_no` but can review deletions; `Encoder` can assign IDs when Complete and review deletions; `HR Personnel` can tag deficiencies).
4. **Client-Side Validation**:
   - Confirmed client-side normalizers map these new fields cleanly.
   - Ran `pnpm build` locally under staging environment. Build completed successfully with zero type or bundling errors.

**PROD not touched — awaiting separate push prompt with passphrase gate**

---

## ohmployee-web — PROD Push: vw_vacancy_detail store_branch/province + source_channel Fix (ohm#5tmy2rzk)

**Status: COMPLETE — PRODUCTION DEPLOYED**

### Summary of Changes

Applied the staging-verified migration `20262606000010_fix_vw_vacancy_detail_missing_columns` to the PRODUCTION database (`rwxelulyapjgaarlwkus`):
1. **Passphrase Authorization**:
   - Honored the mandatory PROD Push Gate. Requested and received the out-of-band passphrase (`DRACARYS`) before applying the migration.
2. **`vw_vacancy_detail` View Update**:
   - Added `province` and `store_branch` to the view projection `public.vw_vacancy_detail` on PRODUCTION.
   - Re-applied select grants to `authenticated` and `service_role`.
3. **`get_web_vacancy_detail` RPC Fix**:
   - Fixed the runtime compiling error `column a.source_channel does not exist` by re-mapping it to the existing `a.applicant_source` column on PRODUCTION.
   - Re-applied execute grants to `authenticated` and `service_role`.
4. **Post-Apply Verification**:
   - Verified execution on the PRODUCTION database. Called `get_web_vacancy_detail` with active vacancy ID `0775ccc6-a5ce-4f02-8af3-0d3bbad3e121` under a simulated authenticated user session.
   - Confirmed the RPC compiles and returns the correct payload, including resolving `province` ("Laguna"), `store_branch` (`null`), and the candidate's `source_channel` ("manual") inside the `pipeline_summary` array.

---

## ohmployee-web — Deep Investigation: Vacancy Aging/Pipeline + HR Emploc row_capabilities Gaps (ohm#9plk4jzc)

**Status: INVESTIGATION COMPLETE — READ-ONLY**

### Summary of Findings

#### 1. Vacancy Aging-Bucket Taxonomy Mismatch
- **Root Cause**: Taxonomy disagreement. The database RPCs (`list_web_vacancies`, `get_web_vacancy_summary`, and `get_web_vacancy_detail`) hardcode a simplified 5-bucket system (`0_7`, `8_14`, `15_30`, `31_plus`, `unknown`). Meanwhile, the UI dropdown and client query expect a 6-bucket system (`advance`, `1_15`, `16_30`, `31_60`, `61_120`, `gt121`). When the client sends the UI-selected value, the RPC does a direct string match and silently returns zero rows.
- **Fix Path**: RPC change + DB Migration (to update the RPC definitions to compute `aging_bucket` via the existing canonical DB function `public.fn_cencom_td_aging_bucket`).
- **Risk Level**: Functionally broken (medium risk).

#### 2. Missing Pipeline-Status Parameter
- **Root Cause**: Missing DB capability. The client dropdown filter "Pipeline status" in the UI does nothing because the database list and summary RPCs do not accept an independent parameter to filter by `derived_status` (they only have `p_status`, which is bound to the list tab's selected state).
- **Fix Path**: RPC change + DB Migration (extend RPC parameters with `p_pipeline_status` / `p_derived_status` and apply filter) + Client wiring.
- **Risk Level**: Functionally broken / dead UI control (medium risk).

#### 3. Columns with no Backing RPC Field
- **Root Cause**: Missing DB projections & dead UI columns.
  - `department` / `business_unit`: Does not exist anywhere in the database schema.
  - `active_applicant_count`, `confirmed_onboard_count`, `has_recent_hire`, `has_pending_closure`, `closure_request_status`: Exist in views `vw_vacancy_list`/`vw_vacancy_detail` but are omitted from the RPC output.
  - `derivedStatus`: Omitted from RPC output (only `pipeline_status` is returned).
  - `last_activity_at`: Does not exist in the database (could map to `latest_hire_at` or `updated_at`).
  - `pending_review` summary count: Omitted from summary RPC output.
- **Fix Path**: RPC change + DB Migration (project view-backing columns and calculate pending closure counts) + Client update (clean up normalizers, map `derivedStatus` properly, drop `department`).
- **Risk Level**: Cosmetic / Minor functionally broken (low risk).

#### 4. HR Emploc row_capabilities Structural Gap
- **Root Cause**: RBAC / permission-shape mismatch. The web client hides/disables crucial administrative action buttons ("Tag Deficiency", "Enter Employee ID", "Review Deletion") because it expects `can_tag_deficiency`, `can_assign_employee_no`, and `can_review_deletion` flags inside the `row_capabilities` JSON object returned by the RPCs. However, the database does not compute or return these keys.
- **Fix Path**: RPC change + DB Migration (compute and return these keys in `list_web_hr_emplocs` and `get_web_hr_emploc_detail`) + Client cleanup.
- **Risk Level**: Blocking a real user workflow (high risk).

---

## ohmployee-web — Fix vw_vacancy_detail Missing store_branch/province Columns (DB Migration) (ohm#1cme8bzn)

**Status: COMPLETE — STAGING ONLY**

### Summary of Changes

Fixed the database view `vw_vacancy_detail` and function `get_web_vacancy_detail` on STAGING to resolve the runtime crash:
1. **`vw_vacancy_detail` View Update**:
   - Added `province` and `store_branch` to the view projection `public.vw_vacancy_detail`, matching `vw_vacancy_list`.
   - Re-applied select grants to `authenticated` and `service_role`.
2. **`get_web_vacancy_detail` RPC Fix**:
   - Fixed the runtime compilation error `column a.source_channel does not exist` by re-mapping `a.source_channel` to the existing table column `a.applicant_source`.
   - Re-applied execute grants to `authenticated` and `service_role`.
3. **Migration Version**:
   - Created and applied DB migration version `20262606000010_fix_vw_vacancy_detail_missing_columns` to STAGING (`qqiiznmqxfoamqytjica`) only.
4. **Verification**:
   - Verified that `get_web_vacancy_detail('f0690db0-825a-443d-9688-fb94106ad268')` executes successfully and returns the expected columns, including `province` ("Kalinga") and `store_branch` (`null`).

**PROD not touched — awaiting manual confirmation gate**

---

## Remove misplaced Mobile UI docs from Web repo (ohm#4t8w1z6p)

**Status: COMPLETE**

### Summary of Changes

1. **Deleted Mobile UI Layout Documents**:
   - Removed the directory `docs/ui/mobile/` and its 4 misplaced markdown layout specification files:
     - `vacancy_layout.md`
     - `plantilla_layout.md`
     - `hr_emploc_layout.md`
     - `dashboard_layout.md`
   - Mobile layout documentation now lives exclusively in the separate Mobile repository (`D:/Projects/OHMployee/docs/ui/mobile/`).
   
2. **Preserved Web UI Layout Documents**:
   - `docs/ui/web/*` layout documents remain untouched under the correct location in this repository.

3. **Confirmed State File Links**:
   - Confirmed each remaining `docs/ui/web/*_layout.md` file's "Linked state file" path.
   - Updated [dashboard_layout.md](file:///d:/Projects/ohmployee-web/docs/ui/web/dashboard_layout.md) to point to the correct, existing [web_foundation_state.md](file:///d:/Projects/ohmployee-web/docs/state/web_foundation_state.md) state file path since `docs/state/dashboard_state.md` does not exist.
   - Verified that `vacancy_layout.md`, `plantilla_layout.md`, and `hr_emploc_layout.md` correctly point to existing state files under `docs/state/` (`vacancy_web_state.md`, `plantilla_web_state.md`, and `hr_emploc_web_state.md` respectively).

4. **Shared Documentation Integrity**:
   - Did not modify `docs/architecture/` or `docs/state/` content (except for validating the link paths), preserving this repo as the single source of truth for shared documentation.

---

## Fix Client-Side Field/Param Mismatches (Vacancy + HR Emploc) (ohm#6dq9wshl)

**Status: COMPLETE — CLIENT-SIDE ONLY, STAGING VERIFIED**

### Summary of Changes

Fixed the client-side RPC parameter and field-normalization mismatches confirmed by `ohm#2fh6xrqw` (root cause: commit `f1f965c` refactored client payloads without matching deployed DB signatures). All fixes are in [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts) and [hr_emploc.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts) only. No DB migration. Verified live against staging (`qqiiznmqxfoamqytjica`) by re-reading `pg_proc` signatures/definitions and executing each RPC with a simulated authenticated session (`set_config('request.jwt.claims', ...)`).

1. **`vacancy.ts` — parameter shape**:
   - `getVacancyRpcFilters` rewritten from the wrapped `{ p_queue, p_search, p_filters }` payload to the flat parameter set the deployed `get_web_vacancy_summary` / `list_web_vacancies` actually accept: `p_status, p_account_id, p_group_id, p_position, p_urgency, p_search, p_vacant_from, p_vacant_to` (+ `p_aging_bucket, p_limit, p_offset, p_sort_by, p_sort_dir` for the list RPC only — the summary RPC has no `p_aging_bucket` parameter).
   - Renamed `p_sort` → `p_sort_by` in `listVacancies`.
   - `VacancySortField`/`supportedSortFields` corrected to the DB's real sort whitelist (`urgency` instead of `urgency_level`, dropped nonexistent `updated_at`, added `vacancy_status`/`pipeline_status`).
   - Removed `normalizePipelineStatus`/`supportedPipelineStatuses` — the deployed RPCs have no `p_pipeline_status` parameter; `p_status` alone matches either `vacancy_status` or `pipeline_status` server-side, so the client's "Pipeline status" dropdown filter (Open/Pipeline) in `vacancy/page.tsx` cannot currently be forwarded to the RPC at all. **Flagged, not fixed — needs a follow-up decision on whether the dropdown should be removed or the RPC needs a dedicated param.**

2. **`vacancy.ts` — field normalization** (`normalizeListRow`, `normalizeCapabilities`, `normalizeSummary`):
   - `urgencyLevel` now reads `row.urgency` (was `row.urgency_level`).
   - `canRequestClosure` now reads `row.row_capabilities.can_request_closure_hint` (was `can_request_closure`).
   - `normalizeSummary` rewritten against the live `RETURNS TABLE(total_open, with_applicant, rejected, backout, aging_0_7, aging_8_14, aging_15_30, aging_31_plus, aging_unknown, critical_urgency, high_urgency)`: `open`←`total_open`, `withApplicant`←`with_applicant`, `rejected`/`backout` unchanged (already matched), `agingWatch` derived as `aging_31_plus + aging_unknown` (no single "aging watch" counter exists server-side), `total` derived as the sum of the four status buckets. **`pendingReview` has no backing column anywhere in the RPC output — left at 0, flagged, not fabricated.**
   - Additional discovered mismatches in `list_web_vacancies`' actual output vs. `VacancyListItem` — **no backing RPC columns exist for**: `department`, `derivedStatus`, `activeApplicantCount`, `confirmedOnboardCount`, `hasRecentHire`, `hasPendingClosure`, `closureRequestStatus`, `lastActivityAt`, `canApprove`, `canUpdateApplicantStatus`. These fields will continue to render as null/false/0. Flagged, not fixed (would require DB projection changes).
   - **Discovered but not fixed**: the client's aging-bucket filter vocabulary (`advance/1_15/16_30/31_60/61_120/gt121`, used by the `agingBucket` dropdown in `vacancy/page.tsx`) does not match the DB's actual bucket taxonomy (`0_7/8_14/15_30/31_plus/unknown`), so the aging-bucket filter will silently return zero rows whenever applied. This is a business-logic/taxonomy gap, not a simple rename, and needs its own follow-up (touches `page.tsx` UI options too).
   - `normalizeDetailRow`/`getVacancyDetail` intentionally left untouched — `get_web_vacancy_detail` still throws at runtime (`store_branch`/`province` bug, separate DB migration prompt) so its output can't be live-verified right now.

3. **`hr_emploc.ts` — field normalization**:
   - `normalizeSummary`: `totalPending`←`pending_count`, `actionNeeded`←`correction_count`, `readyToDeploy`←`ready_count` (as specified). `pendingDeletion`/`slaBreaches` were already correctly falling back to `pending_deletion_count`/`sla_breached_count` — no change needed there.
   - `normalizeListRow`/`normalizeDetailRow`: `slaElapsedDays` now reads `row.aging_days` (was `sla_elapsed_days`, which doesn't exist).
   - `normalizeDetailRow`: `uploadedAttachments` now sourced from `row.correction_attachments` (was `row.uploaded_attachments`); `auditLogsTimeline` now sourced from `row.timeline` (was `row.audit_logs_timeline`); `activeDeletionRequest` now sourced from `row.deletion_request` (was `row.active_deletion_request`).
   - **Additional mismatches found and fixed** (same class, not explicitly named in the prompt but discovered by re-deriving the full field list from the live RPC definitions):
     - `normalizeAttachment`: DB attachment shape is `{id, original_filename, mime_type, size_bytes, uploaded_by, uploaded_at, storage_path}`, not `{attachment_id, file_name, file_url, file_size, ...}`. Fixed `attachmentId`←`id`, `fileName`←`original_filename`, `fileUrl`←`storage_path`, `fileSize`←`size_bytes`.
     - `normalizeAuditLog`: DB timeline event shape has `remarks`/`actor_name`, not `event_description`/`profile_name`. Fixed `eventDescription`←`remarks`, `profileName`←`actor_name`.
     - `normalizeDeletionRequest`: DB deletion-request object shape has `id`/`created_at`, not `request_id`/`requested_at`. Fixed `requestId`←`id`, `requestedAt`←`created_at`.
     - `deficiencySummary`: type was declared `string | null` but the DB returns a jsonb object `{active_count, issues: [{code, comment, label}]}`, so `asString()` on it always evaluated to `null`. Added `summarizeDeficiency()` to join issue labels into a display string (rendered directly in `HrEmplocTable.tsx`).
   - **Discovered but not fixed**: `HrEmplocRowCapabilities` (`canTagDeficiency`, `canAssignEmployeeNo`, `canReviewDeletion`) has no matching keys in the DB's actual `row_capabilities` (`can_view_detail, can_request_deletion, can_withdraw_deletion_request, can_approve_deletion, can_reject_deletion, can_approve_correction, can_revert_correction, can_review_correction, can_submit_correction, can_move_to_plantilla`). These three capabilities will always resolve to `false`. Structural mismatch, not a rename — flagged for a follow-up decision rather than guessed at.
     `coveredStoresCount` on the list row also has no backing column in `list_web_hr_emplocs` (only the detail RPC returns `covered_stores`) — flagged, not fixed.

### Verification
- `pnpm build` (staging env) — compiles clean, typechecks clean, static generation succeeds for all 17 routes including `/vacancy` and `/hr-emploc`.
- Live staging RPC calls (via Supabase MCP, simulated authenticated session):
  - `get_web_vacancy_summary()` → `{total_open:3, with_applicant:2, rejected:0, backout:2, aging_0_7:5, ...}` — succeeds, matches new normalizer.
  - `list_web_vacancies(p_limit:=3, p_sort_by:='aging_days', p_sort_dir:='desc')` → rows returned with `urgency`, `row_capabilities.can_request_closure_hint` present — succeeds, matches new normalizer.
  - `get_web_hr_emploc_summary()` → `{pending_count:1, correction_count:0, review_count:0, ready_count:0, ...}` — succeeds, matches new normalizer.
  - `list_web_hr_emplocs(p_limit:=3)` → rows returned with `aging_days`, `deficiency_summary` object, `row_capabilities` present — succeeds, matches new normalizer.
- No in-browser smoke test performed (per prompt — user performs UI smoke test manually).

### Still Outstanding (separate prompts)
- `get_web_vacancy_detail` `store_branch`/`province` DB bug — server-side/DB migration, explicitly out of scope here.
- Aging-bucket filter taxonomy mismatch (vacancy) — needs a decision + `page.tsx` UI change.
- Pipeline-status filter has no backing RPC param (vacancy) — needs a decision + possible DB change.
- HR Emploc `row_capabilities` structural mismatch (3 capabilities with no DB analog) — needs a decision on what the correct capability model should be.

---

## Scaffold docs/ui/ structure (Mobile + Web layout separation) (ohm#7k2m9xq4)

**Status: COMPLETE**

### Summary of Changes

1. **Scaffolded Layout Documentation Folder Structure**:
   - Created the folder structure:
     - `docs/ui/mobile/`
     - `docs/ui/web/`
   - Generated standard TBD layout spec templates for all modules present (`vacancy`, `plantilla`, `hr_emploc`, `dashboard`) under both platforms.

2. **Files Created/Modified**:
   - **Created**:
     - [vacancy_layout.md (mobile)](file:///d:/Projects/ohmployee-web/docs/ui/mobile/vacancy_layout.md)
     - [vacancy_layout.md (web)](file:///d:/Projects/ohmployee-web/docs/ui/web/vacancy_layout.md)
     - [plantilla_layout.md (mobile)](file:///d:/Projects/ohmployee-web/docs/ui/mobile/plantilla_layout.md)
     - [plantilla_layout.md (web)](file:///d:/Projects/ohmployee-web/docs/ui/web/plantilla_layout.md)
     - [hr_emploc_layout.md (mobile)](file:///d:/Projects/ohmployee-web/docs/ui/mobile/hr_emploc_layout.md)
     - [hr_emploc_layout.md (web)](file:///d:/Projects/ohmployee-web/docs/ui/web/hr_emploc_layout.md)
     - [dashboard_layout.md (mobile)](file:///d:/Projects/ohmployee-web/docs/ui/mobile/dashboard_layout.md)
     - [dashboard_layout.md (web)](file:///d:/Projects/ohmployee-web/docs/ui/web/dashboard_layout.md)
   - **Modified**:
     - [.ai/briefing.md](file:///d:/Projects/ohmployee-web/.ai/briefing.md)
     - [.ai/handoff.md](file:///d:/Projects/ohmployee-web/.ai/handoff.md)

3. **Content Extraction Audit**:
   - Audited all existing state documentation under `docs/state/*_state.md`.
   - Found no embedded mobile UI/UX layout notes or layout specifications inside the state files (references to Mobile were only related to matching backend RPC interfaces/behaviors). Therefore, no content extraction or file stripping of existing state docs was required.

---

## Diagnose Vacancy RPC Failure (PROD) (ohm#2fh6xrqw)

**Status: DIAGNOSIS COMPLETE — READ-ONLY INVESTIGATION**

### Findings & Root Cause

1. **RPC Parameter Signature Mismatch**:
   - The query code in [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts) (updated in commit `f1f965c`) was rewritten to pass query filters in a wrapped shape:
     - `list_web_vacancies` calls: `{ p_queue, p_search, p_filters, p_limit, p_offset, p_sort, p_sort_dir }`
     - `get_web_vacancy_summary` calls: `{ p_queue, p_search, p_filters }`
   - However, the deployed database functions on both Staging (`qqiiznmqxfoamqytjica`) and PROD (`rwxelulyapjgaarlwkus`) still expect the old flat filter parameters:
     - `list_web_vacancies` expects: `(p_status, p_account_id, p_group_id, p_position, p_urgency, p_aging_bucket, p_search, p_vacant_from, p_vacant_to, p_limit, p_offset, p_sort_by, p_sort_dir)`
     - `get_web_vacancy_summary` expects: `(p_status, p_account_id, p_group_id, p_position, p_urgency, p_search, p_vacant_from, p_vacant_to)`
   - This signature mismatch causes the calls to fail with Postgres error `42883: function does not exist`, which is caught and thrown as a `"retryable"` error in the UI.

2. **Database View Column Mismatch in `get_web_vacancy_detail`**:
   - Calling the detail RPC `get_web_vacancy_detail(p_vacancy_id)` on PROD throws a database runtime exception: `ERROR: 42703: column vd.store_branch does not exist`.
   - The SQL definition of `get_web_vacancy_detail` references `vd.store_branch` and `vd.province` from `public.vw_vacancy_detail vd`, but these columns are omitted from the SELECT clause of the `vw_vacancy_detail` view in the database (even though they are present in `vw_vacancy_list`).

3. **Field Normalization Mismatches**:
   - Multiple columns returned by database functions do not match what is read in [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts):
     - `urgencyLevel` is read as `row.urgency_level` but returned as `urgency`.
     - `rowCapabilities` reads `can_request_closure` but DB returns `can_request_closure_hint`.
     - `activeApplicantsList` reads `row.active_applicants_list` but DB returns `pipeline_summary`.
     - Summary KPI normalizer reads `open` from `row.open_count`/`row.open` but DB returns `total_open`.
     - Several list/detail operational columns (e.g., `active_applicant_count`, `confirmed_onboard_count`, `has_recent_hire`, `has_pending_closure`) are missing from the SQL projections.

4. **Wider Impact (Other Modules)**:
   - A quick audit of [hr_emploc.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts) queries shows the same class of normalization mismatches. For example:
     - `normalizeSummary` reads `total_pending`, `action_needed`, and `ready_to_deploy` but the database returns `pending_count`, `correction_count`, and `ready_count`.
     - `normalizeDetailRow` reads `uploaded_attachments` and `audit_logs_timeline` but the database returns `correction_attachments` and `timeline`.
     - `normalizeListRow` reads `sla_elapsed_days` but the database returns `aging_days`.

### Proposed Fix Plan

1. **Option A: Align Frontend Code (Recommended)**
   Update the query file [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts) to:
   - Flatten parameters in `getVacancyRpcFilters` to match the current database signature.
   - Map `p_sort` parameter to `p_sort_by`.
   - Correct the field name maps in the normalization layer (e.g., read `row.urgency` instead of `row.urgency_level`, read `total_open` instead of `open`, etc.).
   - Adjust `get_web_vacancy_detail` query fields to read from `pipeline_summary` instead of `active_applicants_list`.
   
2. **Option B: Align Database Functions via Migration**
   Deploy a migration to:
   - Update `list_web_vacancies` and `get_web_vacancy_summary` functions to accept the `{ p_queue, p_filters }` schema design.
   - Fix `get_web_vacancy_detail` function by joining/reading `store_branch` and `province` from `public.vacancies v_raw` instead of `vd.store_branch` / `vd.province`, or update `public.vw_vacancy_detail` to select these columns.

3. **Spot-check and Fix HR Emploc Normalization**:
   Apply similar alignment changes in [hr_emploc.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts) to resolve hidden bugs in badge counts and attachment/timeline displays.

---

## Split Inactive Employees into Separate Tab/View — Plantilla (ohm#8vt3nkrq)

**Status: COMPLETE — WEB ONLY, NO MIGRATIONS**

Mirrors the *structural* pattern of mobile's Active/Vacancy/Inactive tab split (data filtering, status logic) — web stays table-based, no card redesign.

**RPC-level change needed: NONE.** `list_web_plantilla_employees` already accepts `p_active_state` (`'active' | 'inactive' | 'all' | null`), computed server-side from `plantilla.status`/`deactivated_at`/`date_of_separation` against the same inactive-status vocabulary mobile uses (`inactive, deactivated, resigned, separated, endo, terminated`). Only client-side wiring was needed — `PlantillaEmployeeListParams.activeState` already existed in `plantilla.ts` but `page.tsx` wasn't passing it.

**Blocking bug found and fixed in the same pass (pre-existing, not introduced by this task):** `normalizeEmployeeListRow` in `src/lib/queries/plantilla.ts` read RPC field names (`plantilla_status`, `assignment_type`, `covered_stores_count`, `date_deployed`) that do not exist on the actual deployed `list_web_plantilla_employees` function (confirmed via `pg_get_function_result` on both staging `qqiiznmqxfoamqytjica` and prod `rwxelulyapjgaarlwkus` — real columns are `status`, `deployment_type`, `roving_store_count`, `date_hired`). This meant the Status badge was always blank and the dimming logic never fired in production prior to this fix. Fixed with `??` fallbacks to the real column names (`row.plantilla_status ?? row.status`, etc.) — no RPC/migration touched. `plantillaType` (Budgeted/AH) and `baseRateMasked`/`slaBreached` still have no backing RPC column at all (not part of this task's visible table columns — left as pre-existing gaps, flagged, not fixed).

**Changes in `src/app/(dashboard)/plantilla/page.tsx`:**
- `ViewMode` extended to `"employee" | "inactive" | "store"`; third toggle button "Inactive" added next to "Employee View" / "Store Staffing".
- `employeeQuery` now passes `activeState: view === "inactive" ? "inactive" : "active"` and is `enabled` for both `employee` and `inactive` views (reuses the same query/table, just a different `activeState` + cache key) — no separate query hook needed.
- Filter bar: Store ID + Deployment Type filters now show for both Employee and Inactive views; the employment-Status dropdown (`STATUS_OPTIONS`) is Employee-view-only (redundant inside a view that's already status-partitioned).
- `EmployeeTable`: removed all `opacity-65` / `pointer-events-none` / `line-through` dimming (the `isDimmed` branch of `deriveDeactivationOverlay`) — dead now that inactive rows never reach the Employee view. Rows are unconditionally clickable/keyboard-navigable in both views, matching mobile's confirmed behavior (Inactive tab keeps tap-to-detail, per `plantilla_state.md` ohm#a3d9k7q2 — no card visual, since web stays table-based). The `isPendingSeparation` dashed-red-border banner treatment was kept (not part of the "dimming" being removed — it's a still-active-but-flagged state, not disabled).

**Verified:**
- `pnpm build` — clean, 0 type errors.
- Row-count parity confirmed via direct SQL against staging (`qqiiznmqxfoamqytjica`), replicating the RPC's own `is_active`/`is_inactive` predicate over all of `public.plantilla` (excluding `source_headcount_request_id IS NOT NULL` rows, same as the RPC's base filter): **376 active + 3448 inactive = 3824 total**, exact partition, no loss/duplication.
- Live in-browser click-through **not done this session** — no test login credentials are checked into either repo (confirmed via repo-wide search), and the dev server on :3000 required auth past the login screen. Verification relied on `pnpm build` + direct DB-level partition-count confirmation instead.

**Not touched:** Store Staffing view, card layouts, RPC/migrations, `plantillaType`/`baseRateMasked`/`slaBreached` field gaps (flagged only).

---

## Plantilla UI Current-State Audit (ohm#5r9k2vqp)

- **Audit Purpose**: Assess existing Plantilla module UI, queries, and styling to scope a future mobile card-parity redesign.
- **Current Display Pattern**: Table-based dense rows in `src/app/(dashboard)/plantilla/page.tsx` (`EmployeeTable` and `StoreTable`), not cards.
- **Tab Structure**: Toggles between "Employee View" and "Store Staffing". There is no Active / Vacancy / Inactive tab structure (Vacancy has its own module, and Inactive personnel are styled as dimmed/strikethrough rows in the employee table).
- **Multi-store Handling**: Handled in detail drawer (`PlantillaDetailDrawer.tsx` roving stores list) but not in list view (rendered only as a roving count badge, no store-chip navigation).
- **RPC Support**: `get_web_plantilla_detail` exposes employee metadata, status, type, roving covered stores array, and capabilities. However, `list_web_plantilla_employees` only exposes `covered_stores_count` (integer), not the full store list. To support store chips in the list, list RPC updates would be required. No dedicated avatar URL field exists (initials derived from first/last name).
- **Design Tokens**: Exposes theme variables via Tailwind v4, but currently uses default system fallbacks for font-sans/font-mono instead of DM Sans/DM Mono.

## Current Workflow

- Keep Next.js App Router route files in `src/app/**`.
- Keep reusable presentation components in `src/components/**`.
- Keep shared clients, providers, query contracts, and future server/client utilities in `src/lib/**`.
- Keep thin-client behavior: UI may call lightweight client helpers, but business rules, RBAC, RLS, and data integrity belong in Supabase.
- Keep the admin shell scaffold in the dashboard route group and source navigation from `src/lib/modules.ts`.
- Use `src/components/ModuleEmptyState.tsx` for scaffold-only module pages until real contracts are approved.

## Foundation Notes

- Supabase browser client setup exists at `src/lib/supabase/client.ts`.
- React Query is mounted through `src/app/providers.tsx` from the root layout.
- The dashboard shell provides a persistent desktop sidebar, topbar, responsive mobile module strip, active-route styling, and constrained main content container.
- `src/components/DashboardAuthShell.tsx` now owns the lightweight client-side dashboard guard and current-user context load from `get_web_current_user_context`.
- `src/lib/auth.ts` defines the RPC-backed current-user context, blocked-access states, and fail-closed module visibility helper.
- `src/lib/modules.ts` includes stable module keys for future backend capability mapping.
- Most module routes are placeholders only; do not add business logic until Supabase contracts and RLS are defined. Vacancy is the first read-only RPC-backed module surface.
- Root `/` redirects to `/dashboard` as the web app foundation entry point.

## Auth/RBAC Handoff

- Auth/RBAC architecture is documented in `docs/state/web_auth_rbac_state.md`.
- Dashboard route-group auth guarding is implemented through the client auth shell because the project currently has `@supabase/supabase-js` only; no SSR cookie adapter is installed.
- The temporary Supabase Auth-only context has been replaced with a call to `supabase.rpc("get_web_current_user_context")`.
- The shell renders only when `access_status === "allowed"`; missing sessions still redirect to `/login`.
- Missing profile, inactive/disabled account, unauthorized web role, RPC failure, missing module arrays, and malformed capabilities block the shell.
- Module visibility uses `src/lib/modules.ts` plus backend `allowed_module_keys`; `module_capabilities` is presentation-only metadata for sidebar/topbar display.
- Frontend role checks are display/navigation only. Backend RLS/RPC policies remain the authority for all data access, mutations, scopes, and workflow rules.
- Do not invent web-only roles; mirror Mobile role, group scope, and account scope semantics from Supabase.

## Backend Contract Handoff

- This repo currently has no local `supabase/migrations` directory.
- Backend implementation should happen in the authoritative Supabase migration workflow, or after adding an approved migration directory to this repo.
- Required canonical contract for the current frontend: `public.get_web_current_user_context()` RPC.
- Optional read contract: `public.web_current_user_context` as a `security_invoker = true` view once the RPC is safe.
- The context must include current Auth user id, safe full name/email, existing Mobile role key/name, `access_status`, group scope, account scope, `allowed_module_keys`, and `module_capabilities`.
- The contract must derive identity from `auth.uid()`, not caller arguments, and must not expose service-role data.
- Fail closed for unauthenticated, missing-profile, inactive, disabled, and unauthorized-web cases.
- See the `OHM2026_1072-IMPL-1` prompt in `docs/state/web_auth_rbac_state.md` for the exact migration/RPC/view implementation brief.

## Vacancy Web Handoff

- Vacancy Web architecture is documented in `docs/state/vacancy_web_state.md`.
- Current Vacancy implementation is a client desktop admin command center with a compact header, RPC-backed KPI cards, status tabs, submitted search, account/group UUID filters, aging/urgency/vacant-date filters, dense read-only table rows spanning full-screen width, pagination, loading/empty/error/blocked states, and a right-side sliding overlay drawer that renders complete vacancy detail contexts.
- The Vacancy page integrates `get_web_vacancy_summary(...)`, `list_web_vacancies(...)`, and `get_web_vacancy_detail(p_vacancy_id uuid)` queries through `src/lib/queries/vacancy.ts`.
- Vacancy list/summary payloads use the deployed backend's flat individual-param contract (OHM2026_1071/OHM2026_1130 fixes). The frontend sends `p_status`, `p_account_id`, `p_group_id`, `p_aging_bucket`, `p_urgency`, `p_search`, `p_vacant_from`, `p_vacant_to`, `p_limit`, `p_offset`, `p_sort_by`, `p_sort_dir` for the list RPC, and `p_status`, `p_account_id`, `p_group_id`, `p_urgency`, `p_search`, `p_vacant_from`, `p_vacant_to` for the summary RPC. Tab queue values map to backend `p_status`: `open`→`Open`, `with_applicant`→`Pipeline`; `rejected`/`backout` pass `null` (no direct list-level applicant-terminal-status filter support in the deployed RPC).
- Vacancy list/detail rows use the RPC field name `position_title` end-to-end in the frontend item contract, table, and detail drawer.
- Do not add raw table queries, caller-controlled role/scope parameters, fake data, CRUD, or mutations.
- Target UX is a desktop admin command center: KPI summary row, status tabs, filter/search toolbar, dense full-width table, sliding right-side detail drawer, candidate summary listing (shielded PII), audit timeline, and capability-controlled action area.
- Web must mirror Mobile vacancy business rules and status transitions, but present them in a dense admin-panel workflow rather than Mobile cards.
- `OHM2026_1077` and `OHM2026_1082` define the backend read-contract architecture for Vacancy Web. The recommended Supabase migration creates `public.list_web_vacancies(...)` for dense list rows, `public.get_web_vacancy_summary(...)` for KPI counts, and `public.get_web_vacancy_detail(p_vacancy_id uuid)` for the selected vacancy's detail drawer context.
- The Vacancy Detail contract must reuse existing Mobile semantics from `vw_vacancy_detail`, `fn_is_active_vacancy_applicant_status`, and existing RBAC/scope helpers. It enforces strict access controls using the caller's `auth.uid()`, segregates list-only vs. detail-only fields, exposes capability hints (`can_approve`, `can_update_applicant_status`, `can_request_closure`), and provides candidate sub-lists and timelines without exposing candidate contact PII (emails/phone numbers).
- Scoped reads must be enforced in Supabase from `auth.uid()` and existing RBAC/scope helpers (Super Admin/Head Admin broad access; OM/ATL/TL/HRCO/Recruitment scoped access; Viewer scoped read-only access).
- Current Vacancy UI uses backend `row_capabilities` only for presentation hints inside the drawer. Actual mutations are disabled because no action RPC contract is implemented.
- See the `OHM2026_1077-IMPL-1` and `OHM2026_1082-IMPL-1` prompts in `docs/state/vacancy_web_state.md` for the exact Supabase migration implementation briefs.

## Shared Web UI System Handoff

- **Design System Blueprint**: Documented completely in `docs/state/web_ui_system_state.md`. Defines the core architecture for extracting consistent, reusable, desktop-first administrative layout structures.
- **Audited Visual Patterns**: Audited KPI metric cards, dense scrolling grids, search-and-filter bars, status badges, details drawers, access-denied RLS boundaries, network retry elements, loading skeletons, and capability action lists.
- **Shared Primitives & Layouts**: Implementation is complete for Phase 2 low-risk primitives:
  - `AdminPageHeader` (`src/components/shared/AdminPageHeader.tsx`): Reusable header with read-only badge indicator and custom administrative button actions.
  - `MetricCard` (`src/components/shared/MetricCard.tsx`): Centralized KPI item supporting blank state indicators, loading behaviors, error/retry states, and blocked-access overrides.
  - `DataState` (`src/components/shared/DataState.tsx`): Single-point presenter for data states (loading spinner, custom empty records, lock-shield access denied block, warning alert card with retry triggers).
  - `StatusBadge` (`src/components/ui/StatusBadge.tsx`): Consistent mapping of raw backend strings to tailored HSL variant color schemes, safely wrapping/extending basic badges.
- **Shared Primitives & Layouts**: Implementation is complete for both Phase 2 primitives and Phase 3 structural containers:
  - `AdminPageHeader` (`src/components/shared/AdminPageHeader.tsx`): Reusable header with read-only badge indicator and custom administrative button actions.
  - `MetricCard` (`src/components/shared/MetricCard.tsx`): Centralized KPI item supporting blank state indicators, loading behaviors, error/retry states, and blocked-access overrides.
  - `DataState` (`src/components/shared/DataState.tsx`): Single-point presenter for data states (loading spinner, custom empty records, lock-shield access denied block, warning alert card with retry triggers).
  - `StatusBadge` (`src/components/ui/StatusBadge.tsx`): Consistent mapping of raw backend strings to HSL variant styles, safely wrapping/extending basic badges.
  - `DetailDrawer` (`src/components/shared/DetailDrawer.tsx`): Reusable slide-over aside drawer that locks body scroll, listens to ESC keys, dim overlay, and accepts dynamic header badge/slots.
  - `AdminFilterBar` (`src/components/shared/AdminFilterBar.tsx`): Modular form panel container featuring standard search bars and supporting modular selects or action buttons via children slots.
  - `CapabilityActionBar` (`src/components/shared/CapabilityActionBar.tsx`): Locked administrative capability bars displaying indicator badges showing available or unexposed states.
- **Domain Boundaries**: Column definitions, raw database statuses, query RPC bindings, candidate detail PII blocks, and custom log events must remain module-specific to avoid layout dilution or scope leaks.
- **Extraction Roadmap**: Structured in 5 clear phases (Docs [Done] -> Low-risk primitives [Done] -> Structural layouts [Done] -> Vacancy refactoring [Done] -> HR Emploc/Plantilla deployment [Active]) to ensure safe execution.
- **Next Phase Actions**: Refer to Phase 5 in `docs/state/web_ui_system_state.md` to deploy shared structures across `HR Emploc` and `Plantilla` routes, replacing basic empty states with high-fidelity, shared UI shells.

- **Implementation Status**: The frontend read-only queue page, summary KPI metrics, compact dense grid table, and 640px sliding details drawer are fully implemented and validated (compiled cleanly in both linting and production bundling tests).
- **Security & RLS boundaries**: PII shielding is active (contact numbers/email are never rendered), and data queries strictly consume server-derived RLS scopes.
- **Workflow Action Area**: CapabilityActionBar buttons are fully mapped to dynamic permission flags returned on `rowCapabilities` (`canTagDeficiency`, `canAssignEmployeeNo`, `canMoveToPlantilla`, `canRequestDeletion`).
- **Next Phase Steps**:
  1. Approve the backend transactional mutation RPC signatures on Supabase (tagging deficiencies, entering employee IDs, transitioning plantilla directories, separator approvals).
  2. Implement React Query mutations (`useMutation`) and cache invalidation triggers on the client.

## Design Token System Handoff (OHM2026_1097)

- **Source of truth**: tokens are defined in `src/app/globals.css`; the blueprint is `docs/state/web_design_tokens.md` (§0 documents the activation/implementation details).
- **How tokens are exposed**:
  - Semantic colors (`--surface-*`, `--text-*`, `--border-*`, `--background`, `--foreground`) live as runtime `:root` variables and are bridged to Tailwind via `@theme inline`, producing utilities like `bg-surface-base`, `text-text-primary`, `text-text-secondary`, `text-text-muted`, `border-border-default`, `border-border-subtle`, `bg-surface-hover`, `bg-surface-selected`.
  - Static scales use plain `@theme`: `brand-50…700`, `status-{success,warning,danger,info,neutral}-{bg,border,text}`, `radius-*`, and `animate-drawer-in|drawer-out|fade-in`.
  - Layout/motion constants are plain `:root` custom properties used through arbitrary values: `--sidebar-width` (240px), `--topbar-height`, `--drawer-width-md|lg|xl`, `--z-base…toast`, `--space-*`, `--duration-*`.
- **Dark mode**: native via `@media (prefers-color-scheme: dark)` overriding the `:root` semantic variables. No theme toggle / class strategy is wired; add a `data-theme`/class override block in `globals.css` later if a manual switch is required.
- **What was refactored**: shared primitives only (`AdminPageHeader`, `MetricCard`, `DataState`, `DetailDrawer`, `AdminFilterBar`, `StatusBadge`). Dense module tables keep literal classes except for the targeted consistency fixes.
- **Fixes landed**: sidebar 288px→240px (`--sidebar-width`); `DetailDrawer` now slides in via `animate-drawer-in` (previously mounted at `translate-x-0` so the slide never played) and uses `--surface-overlay` + `animate-fade-in` backdrop; HR Emploc row selection/hover aligned to `bg-blue-50` / `hover:bg-gray-50`; invalid `gray-150`/`gray-850` classes replaced.
- **Guardrails honored**: no module redesign, no Plantilla implementation, no new libraries, no mutations, no unrelated module refactors. Validated with `pnpm lint` and `pnpm build`.
- **Table interior tokenization (OHM2026_1098)**: All hardcoded `bg-white`, `bg-gray-*`, `border-gray-*`, `text-gray-*`, and selected/hover row classes in `VacancyTable.tsx` and `HrEmplocTable.tsx` have been replaced with dedicated table tokens (`table-header`, `table-row`, `table-row-hover`, `table-row-selected`, `table-rule`, `table-rule-section`, `table-text`, `table-text-sub`, `table-text-muted`, `mono-pill-surface`, `mono-pill-ink`, `mono-pill-ring`). Both tables are now dark-mode readable. Pending deletion row (`bg-red-50 hover:bg-red-100`) and status badge colors (emerald, blue, red) remain as literal classes since they are intentional semantic indicators. Validated via `pnpm lint` and `pnpm build` (clean).

## Read Workflow Consistency Handoff (OHM2026_1105)

- **Audit scope**: Vacancy, HR Emploc, and Plantilla read-only modules — loading states, empty states, access denied, retryable errors, row click, drawer close, keyboard accessibility, token usage, spacing, badge consistency, KPI consistency, filter bar consistency.
- **Fixes applied**: 11 low-risk changes across 5 files. See `docs/state/web_ui_system_state.md §7` for the full table.
- **Remaining intentional inconsistencies**:
  - Drawer loading pattern: Vacancy/HR Emploc use custom pulse skeletons; Plantilla uses `DataState kind="loading"`. Skeletons are better for CLS; migrate Plantilla in a future pass.
  - Inline drawer error states in Vacancy/HR Emploc vs shared `DataState` in Plantilla. `DataState` is the preferred forward direction.
  - Tab active color `bg-blue-600` in Vacancy/HR Emploc vs `bg-brand-600` in Plantilla. Pending dedicated token migration pass for those two modules.
  - `CapabilityActionBar` hardcoded gray classes — pending dedicated token migration pass.
  - Plantilla missing footer boundary notice present in Vacancy/HR Emploc.
  - `formatDate` locale `en-PH` in Plantilla vs `en` in Vacancy/HR Emploc (intentional).
- **Validated**: `pnpm lint` clean, `pnpm build` clean.

## Wide Admin Layout Standardization (OHM2026_1070)

- **Scope completed**: HR Emploc reference layout, Vacancy, Plantilla, and scaffold-only modules (`Approvals`, `User Management`, `Team Directory`, `Notifications`, `Reports`, `Settings`) now share the maximized admin layout direction.
- **Shared shell changes**: `DashboardAuthShell` no longer constrains dashboard content to `max-w-7xl`; the fixed compact sidebar remains unchanged while main content uses the full available desktop canvas with responsive page gutters.
- **Shared UI changes**: `AdminPageHeader`, `MetricCard`, and `AdminFilterBar` use the larger admin typography/spacing scale. `ModuleEmptyState` now renders the same module header, KPI metric row, and full-width workspace shell instead of a narrow centered placeholder card.
- **Module changes**: HR Emploc, Vacancy, and Plantilla page wrappers no longer add nested page padding; KPI grids use consistent gaps; tabs/segmented controls and filter controls are taller and more readable; dense tables use wider minimum desktop widths, larger body text, larger row/header padding, and full-width table containers.
- **Backend/RBAC guardrails**: No Supabase schema, RPC, RLS, query contract, role visibility, or mutation logic changed. Placeholder modules still do not mock records or actions.
- **State docs**: No `docs/state/*_web_state.md` update was needed because this batch changed layout presentation only, not stable module behavior.
- **Validated**: `pnpm lint` clean. `pnpm build` initially failed in the sandbox with Turbopack `Operation not permitted` while creating a process/binding to a port, then passed outside the sandbox (Next.js 16.2.4, zero build errors).

## Web Mutation Workflow Handoff (OHM2026_1107 → OHM2026_1109 → OHM2026_1127)

- **Architecture doc**: `docs/state/web_mutation_workflow_state.md` — full spec and phase order for HR Emploc deficiency tagging as the first mutation.
- **Selected first mutation**: **HR Emploc deficiency tagging** (`Pending`/`For Review` → `For Correction`). Most reversible, lowest blast radius, zero cross-module coupling, least-privileged actor (`hrPersonnel`).
- **Deferred order**: correction review (natural second — closes the loop but is a forward gate); Vacancy closure (cross-pipeline); Plantilla deactivation (highest blast radius — archives an employee, reopens vacancy on Backout).
- **Backend contract (deployed — migration `20260607000004`)**: `public.tag_web_hr_emploc_deficiency(p_hr_emploc_id uuid, p_deficiencies jsonb, p_remarks text default null)` — `SECURITY DEFINER`, locked `search_path`, identity from `auth.uid()` only, granted to `authenticated`. One transaction: capability + scope + record-state checks → write `correction_reason` + set `hr_status='For Correction'` → insert immutable audit event → existing `trg_notify_hr_emploc_correction_tagged` fires. Returns JSONB envelope `{ ok, hr_emploc_id, new_hr_status, correction_reason, tagged_at }`.
- **Frontend wiring status (OHM2026_1109 — COMPLETE):**
  - `src/lib/queries/hr_emploc.ts`: `tagWebHrEmplocDeficiency()` wrapper calls `supabase.rpc("tag_web_hr_emploc_deficiency", ...)`. `HrEmplocDataErrorKind` extended with `"invalid_state"`. `getErrorKind` maps `P0001` → `invalid_state`, `42501` → `access_denied`. `TagDeficiencyParams` and `TagDeficiencyResult` types exported.
  - `src/components/shared/CapabilityActionBar.tsx`: button enabled when `isAvailable && !!action.onClick`; disabled otherwise (backward-compatible).
  - `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`: `isTagModalOpen` state; "Tag Deficiency" action has `onClick: () => setIsTagModalOpen(true)` gated on `canTagDeficiency && !isPendingDeletion`; `TagDeficiencyModal` sub-component with checkboxes, per-issue note inputs, remarks textarea, submitting state, inline error display. On success: invalidates `["hr-emploc-detail", hrEmplocId]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No optimistic UI.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).
- **Backend deployed:** mutation executes end-to-end.

## Second Mutation — Correction Review Handoff (OHM2026_1110 → OHM2026_1112)

- **Architecture doc**: `docs/state/web_mutation_workflow_state.md` **Part II (§10–§18)** — full backend-authoritative spec, approval-model comparison, state map, and the exact implementation prompt (OHM2026_1110-IMPL-1).
- **What it is**: the inverse of the first mutation — it *closes* the correction loop. Reviewable state is `For Review` (the state a record reaches after the HRCO resubmits corrected docs). The intermediate HRCO upload step (`For Correction`→`For Review`) is an ops/Mobile RPC and is **out of scope** for the web layer.
- **State transitions** (one RPC, `p_decision` discriminator):
  - `approve`: `For Review` → `Complete` — only when **all** `correction_reason` deficiencies are affirmed resolved; clears `correction_reason`; does **not** touch `employee_no`; audit `Correction Approved`.
  - `return`: `For Review` → `For Correction` — residual deficiencies kept as the new `correction_reason`; re-fires the HRCO correction notification; audit `Correction Returned`.
- **Backend contract (deployed — migration `20260609000000`)**: `public.review_web_hr_emploc_correction(p_hr_emploc_id uuid, p_decision text, p_resolved_keys text[] default null, p_remarks text default null)` — `SECURITY DEFINER`, locked `search_path`, identity from `auth.uid()` only, granted to `authenticated`. Returns `{ ok, hr_emploc_id, decision, new_hr_status, correction_reason, reviewed_at }`.
- **Allowed roles**: `hrPersonnel` (and `superAdmin` global override). Re-checked server-side; frontend gating is ergonomics only.
- **Capability flag**: `can_review_correction` is present in the live `get_web_hr_emploc_detail` row capability payload (true only for authorized reviewers on `For Review`, non-`Pending Deletion` records). Keep distinct from `can_review_deletion` (deletion approvals) and `can_tag_deficiency` (Part I). The Review Correction button renders from this canonical capability only; missing/false/malformed capability payloads remain fail-closed.
- **Recommended model**: **strict all-deficiencies-resolved** (partial-compliance approval rejected). Rationale: `Complete` is an irreversible forward gate to employee-number assignment / Plantilla movement, and there is no web-side path to re-open a `Complete` record (the Part I tagging RPC rejects `Complete`). The `return` path is the in-loop safety valve for partial fixes.
- **Blocked states**: non-`For Review` `hr_status`, `Pending Deletion`, `status != 'Pending Emploc'`, out-of-scope. No optimistic UI.
- **Invalidation**: `["hr-emploc-detail", id]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No Vacancy/Plantilla cache touch.
- **Error mapping**: reuses existing `getErrorKind` (`42501`→`access_denied`, `P0001`→`invalid_state`); no new error kinds needed.
- **Frontend wiring status (OHM2026_1112 — COMPLETE):**
  - `src/lib/queries/hr_emploc.ts`: `reviewWebHrEmplocCorrection()` wrapper calls `supabase.rpc("review_web_hr_emploc_correction", ...)`. `canReviewCorrection` normalized from `can_review_correction` only (canonical key; stale `can_approve_correction` alias removed). `ReviewCorrectionParams` and `ReviewCorrectionResult` types exported.
  - `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`: `isReviewModalOpen` state; "Review Correction Resubmission (HR Compliance)" action enabled from backend `canReviewCorrection` only; `ReviewCorrectionModal` sub-component with per-deficiency Resolved/Still-Deficient checkboxes, auto-derived decision, decision-preview block, optional remarks textarea, submitting state, inline error display. On success: invalidates `["hr-emploc-detail", hrEmplocId]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No optimistic UI.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

## HR Emploc Mutation Stability Audit (OHM2026_1127)

- **Scope**: audit and stabilize all existing HR Emploc mutation workflows, capability payload enforcement, invalidation consistency, audit/timeline integrity, and notification-safe frontend handling.
- **Capability enforcement fixes (OHM2026_1127)**:
  - Removed stale `can_tag_correction` alias from `canTagDeficiency` normalization — canonical key is `can_tag_deficiency`.
  - Removed stale `can_approve_correction` alias from `canReviewCorrection` normalization — canonical key is `can_review_correction`.
  - Review correction button visibility now depends only on normalized `can_review_correction`; backend state/status/deletion checks remain authoritative in the live detail payload.
- **Audit/timeline fixes (OHM2026_1127)**:
  - `HrEmplocAuditLogItem.createdAt` changed to `string | null`; normalizer no longer invents `new Date().toISOString()` for null timestamps — `formatDateTime(null)` renders `"--"`.
  - `CorrectionAttachmentItem.uploadedAt` changed to `string | null`; same fix applied.
  - `DeletionRequestItem.requestedAt` changed to `string | null`; same fix applied.
- **Render key stability (OHM2026_1127)**:
  - `auditLogsTimeline.map`: key is now `item.eventId || \`timeline-${index}\`` — prevents duplicate key crash on null/empty `event_id` payloads.
  - `uploadedAttachments.map`: key is now `file.attachmentId || \`attachment-${index}\``.
  - `coveredStores.map` in drawer: key is now `store.storeId || \`store-${index}\``.
- **Type cleanup (OHM2026_1127)**:
  - `HrEmplocDetailItem.correctionReason` changed from `Record<string, unknown> | null` to `Record<string, unknown>` — matches the normalizer, which always returns `{}` for null payloads via `asObject()`. The redundant `?? {}` in the drawer's `ReviewCorrectionModal` prop was removed.
- **Mutation safety (OHM2026_1127)**:
  - Both `TagDeficiencyModal` and `ReviewCorrectionModal`: `isPending` disables all form inputs, cancel button, submit button, and backdrop click. No optimistic UI. `setSubmitError(null)` on each retry. Modal unmounts on close so error state is discarded. No duplicate-submit paths exist.
- **Stale footer copy (OHM2026_1127)**: `page.tsx` footer disclaimer updated — no longer claims all mutations are read-only; correctly reflects deployed (tag deficiency, review correction) vs. pending (employee ID assignment, Plantilla deployment, separation requests).
- **Files changed**: `src/lib/queries/hr_emploc.ts`, `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`, `src/app/(dashboard)/hr-emploc/page.tsx`.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

## HR Emploc Live Correction Review Capability Validation (OHM2026_1129)

- **Scope**: live detail payload validation only for review-correction rendering, fail-closed behavior, modal UX, and stale capability aliases.
- **Root cause fixed**: the Review Correction drawer action still combined canonical `canReviewCorrection` with local status/deletion guards. Since `get_web_hr_emploc_detail` now returns backend-authoritative `can_review_correction`, the action visibility has been narrowed to that normalized capability only.
- **Capability rendering result**: authorized live payloads with `can_review_correction: true` render the action; unauthorized users, wrong statuses, pending deletion rows, missing keys, malformed capability payloads, and false values hide the action through the normalized canonical flag.
- **UX validation result**: correction reasons render from `correctionReason`; attachments render with stable attachment/fallback keys; audit timeline renders with stable event/fallback keys and null-safe timestamps; review modal opens/closes from drawer state and unmounts on close; submitting disables inputs, cancel, close, backdrop, and submit; retry clears inline errors; success invalidates detail, list, and summary query caches.
- **Validated**: `pnpm lint` clean. `pnpm build` initially failed inside sandbox with Turbopack `Operation not permitted` while creating a process/binding to a port, then passed outside the sandbox (Next.js 16.2.4, zero build errors).
- **Files changed**: `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`, `.ai/handoff.md`, `docs/state/hr_emploc_web_state.md`.

## Plantilla Web Handoff

- **Target Architecture & Specification**: Fully documented in `docs/state/plantilla_web_state.md`.
- **Core Focus Areas**:
  1. **Dual Views**: Segmented View Toggle (`/plantilla`) switching between Employee-Centric (active roster listing with monospaced employee IDs, positions, primary store, status badges) and Store-Centric (staffing capacities listing targets, active budgeted/AH, vacancies, and staffing SLA health statuses).
  2. **Scoped RBAC**: RLS-enforced read restrictions based on authenticated profiles. Scoped roles (`om`, `hrco`, `atl`, `tl`) see only their allowed accounts.
  3. **PII Masking**: Strict database-level masking of sensitive contact details (phone, email, address, salary rates, government IDs) for restricted roles, returning pre-masked strings over the network.
  4. **Deactivation Overlays**: 65% opacity, dashed borders, and warning banner overlays for suspended, inactive, or separation-pending rows/profiles.
  5. **Separation Workflows**: Resignations, involuntary Terminations, Day 1 Backouts (which automatically reopen original Vacancies), and Administrative Archives backed by asset return checklists and interactive clearances.
  6. **Additional Headcount (AH)**: Tracking of seasonal, temporary headcount slots with expiration calendars and visual warning countdown indicators.
  7. **Detail Drawer**: High-density 640px overlay featuring employment/allocation details, roving coverages, separation checklists, SLA breachers, and timelines.
  8. **SLA Breach Clocks**: 48h movement SLAs and 7-day store vacancy vacancy alarm clocks.
- **Backend RPC Status**: Migrations `20260607000002` and `20260607000003` exist and are applied remotely. Implemented contracts: `list_web_plantilla_employees`, `list_web_plantilla_store_staffing`, `get_web_plantilla_summary`, and `get_web_plantilla_detail`.
- **Query Contract Status**: `src/lib/queries/plantilla.ts` is fully implemented. Exports: `getPlantillaSummary`, `listWebPlantillaEmployees`, `listWebPlantillaStoreStaffing`, `getWebPlantillaDetail`, `PlantillaDataError`, and all typed structs. Presentation helpers `deriveDeactivationOverlay`, `deriveTransferOverlay`, `deriveStaffingRisk` are pure functions that accept normalized data and return overlay hint objects — no backend calls.
- **RPC names wired**: `get_web_plantilla_summary`, `list_web_plantilla_employees`, `list_web_plantilla_store_staffing`, `get_web_plantilla_detail`. All use `auth.uid()`-derived scopes server-side; no caller-controlled role/scope params are passed from the frontend.
- **Masking contract**: backend returns pre-masked strings for `contact_number`, `email_address`, `residential_address`, `base_rate_masked`, and `government_ids` JSONB for restricted roles. The frontend never strips or applies masking itself.
- **Page Shell Status (OHM2026_1103 / OHM2026_1125)**: `src/app/(dashboard)/plantilla/page.tsx` is fully implemented as a read-only dual-view shell. `AdminPageHeader`, 4x `MetricCard` (wired to `getPlantillaSummary`), `AdminFilterBar` (segmented Employee/Store toggle + per-view filter selects), and two inline dense tables (employee roster, store staffing) are all live. DataState handles all four boundary states. `deriveDeactivationOverlay` and `deriveStaffingRisk` are applied inline. Store Staffing renders the backend-returned grouped metrics `required_headcount`, `active_headcount`, `vacancy_count`, `pipeline_count`, `staffing_gap`, `staffing_risk`, and `sla_badge`; the frontend does not recompute staffing metrics. Pagination is wired and resets on apply/reset/view switch. `pnpm lint` and `pnpm build` are clean.
- **Detail Drawer Status (OHM2026_1104)**: Fully implemented and wired in `src/components/plantilla/PlantillaDetailDrawer.tsx`. Employee rows in `page.tsx` emit `onRowClick(row.id)` to set `selectedPlantillaId` state; the drawer opens and fetches `getWebPlantillaDetail` via React Query. Dimmed rows (inactive/terminated/suspended) are non-clickable via `pointer-events-none`. Active and pending-separation rows are keyboard-accessible (`role="button"`, `tabIndex=0`, Enter/Space). Drawer close clears state. All DataState boundaries active. `deriveTransferOverlay` and `deriveDeactivationOverlay` applied to drawer body banners.
- **Plantilla Detail Validation (OHM2026_1126)**: Detail hydration now accepts `id`, `employee_id`, or `plantilla_id` from `get_web_plantilla_detail`; JSONB detail arrays (`covered_stores`, `clearance_checklist`, `clearance_documents`, `audit_timeline`) are null-safe and normalized with stable keys for duplicate/partial items. Employee detail actions now render only backend capability payload flags: `can_request_deactivation`, `can_review_deactivation`, `can_request_deletion`, `can_review_deletion`, and `can_transfer_employee`. The drawer no longer renders stale generic separation approval, roving edit, suspend toggle, or AH-request actions for employee details. Assignment coverage renders stationary primary-store rows and roving covered-store rows separately; clearance audit renders only for pending-separation rows; audit timeline dates tolerate nulls without client-invented timestamps.
- **Known gaps**:
  - `groupId` filter is present in the UI and is passed as `p_group_id` to summary, employee list, and store staffing RPCs.
  - Store staffing rows have no detail drawer yet (store-centric detail is not yet implemented).
  - No action mutations yet (Phase 5).
- **Next Phase Steps**:
  1. Keep Store Staffing backend hydration aligned with the deployed grouped metric contract before adding store-detail UX.
  2. Wire operational mutations (transfers, AH requests, separations, clearance ticks) — Phase 5.

## Vacancy RPC Param Fix (OHM2026_1071)

- **Root cause**: `src/lib/queries/vacancy.ts` was sending `p_queue`/`p_filters` (JSONB) and `p_sort` to the deployed Supabase RPCs, but the deployed functions (`20260524130000_web_vacancy_list_summary_rpcs.sql`) expect flat individual params (`p_status`, `p_aging_bucket`, `p_urgency`, `p_search`, `p_vacant_from`, `p_vacant_to`, `p_limit`, `p_offset`, `p_sort_by`, `p_sort_dir`). PostgREST rejected every call as no-function-found → `retryable` error banner on every load.
- **Fix**: Replaced `VacancyRpcPayload` type and `getVacancyRpcFilters` function with two new builders matching the deployed signatures: `getSummaryRpcParams` and `getListRpcParams`. Removed dead helpers `normalizeStatus`, `normalizePipelineStatus`, `supportedStatuses`, `supportedPipelineStatuses`. Added `tabToRpcStatus` to map queue tabs → `p_status` values (`open`→`"Open"`, `with_applicant`→`"Pipeline"`, `rejected`/`backout`→`null`).
- **Secondary normalizer fixes**: `normalizeSummary` now reads `row.total_open` (backend field) to populate `open`; `normalizeListRow` reads `row.urgency_level ?? row.urgency` to populate `urgencyLevel`. Dev-only `console.error` added in `throwVacancyError` to surface the real Supabase error message during development.
- **Known gap**: The deployed `list_web_vacancies` does not return `derived_status`, `active_applicant_count`, `confirmed_onboard_count`, `has_recent_hire`, `has_pending_closure`, `closure_request_status`, or `last_activity_at`. These fields default to null/0 in the list rows. The summary `pendingReview` and `agingWatch` KPI fields also have no backend equivalent and display zero. The `rejected`/`backout` tabs cannot filter the list by applicant terminal status with the current backend RPC — they display all scoped active vacancies.
- **No backend changes made**: No Supabase schema, RPC, RLS, or migration was modified.
- **Files changed**: `src/lib/queries/vacancy.ts`, `.ai/handoff.md`, `docs/state/vacancy_web_state.md`.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

## Vacancy Live QA After Flat Param Fix (OHM2026_1130)

- **Scope**: validated only the Vacancy query layer, `/vacancy` page, Vacancy table/drawer components, and relevant Vacancy state/handoff docs.
- **Root causes found**:
  - The deployed RPC supports `p_account_id` and `p_group_id`, but the page/query wrapper did not expose or send account/group filters.
  - The page still showed a standalone Pipeline dropdown even though the deployed backend has no separate pipeline filter param; selecting it only changed the React Query key and did not affect RPC params.
  - Detail rendering used presentation fallbacks that looked like real business values (`Open`, `Full-time`, `Replacement`, `advance`) and the activity normalizer invented a current timestamp for missing history dates.
- **Frontend fixes**:
  - Added account/group UUID filter inputs and flat `p_account_id` / `p_group_id` RPC params for both summary and list reads. Invalid UUID-shaped values normalize to `null` and do not leak unsupported values into the RPC call.
  - Removed the unsupported Pipeline dropdown; queue status remains controlled by tabs (`open`→`Open`, `with_applicant`→`Pipeline`, `rejected`/`backout`→`null`).
  - Detail drawer now renders missing backend fields as unavailable placeholders and no longer invents missing activity timestamps.
- **Known backend limitations confirmed**:
  - `rejected` and `backout` tabs cannot filter applicant terminal statuses through the deployed list RPC and intentionally show the scoped active vacancy list with `p_status = null`.
  - `pendingReview` and `agingWatch` KPI cards may show `0` when the summary RPC does not return equivalent fields.
  - Some list fields normalize to `null`/`0` when the deployed list RPC does not return them.
- **Validation status**: `pnpm lint` clean. `pnpm build` initially failed inside the sandbox with the known Turbopack `Operation not permitted` port-binding error, then passed outside the sandbox (Next.js 16.2.4, zero build errors). Browser QA reached the local `/vacancy` route against `.env.local`, but the app redirected to Login because no authenticated Supabase browser session was available; no PostgREST function-not-found error was observed in the unauthenticated browser console.

## Dashboard Web Implementation (OHM2026_1133)

- **Contracts wired**: `fn_dashboard_metrics()` and `fn_dashboard_operational_analytics()` — both new RPCs from OHM2026_1132 backend deployment.
- **Query layer**: `src/lib/queries/dashboard.ts` — `getDashboardMetrics()`, `getDashboardOperationalAnalytics()`, `DashboardDataError` (access_denied / retryable).
- **Dashboard page**: `src/app/(dashboard)/dashboard/page.tsx` replaced `ModuleEmptyState` with a full read-only admin page:
  - **Operational KPI row** (5 cards): Open Vacancies, HR Emploc Pending, Active Plantilla, Under-Staffed Stores, Active SLA Breaches — all from `fn_dashboard_metrics()`.
  - **Operational Analytics section**: Pipeline Total, Hires This Month, Separations This Month, Avg Fill Rate — from `fn_dashboard_operational_analytics()`.
  - **Security Dashboard section** (RBAC-gated): Pending Approvals, Security Events — from `fn_dashboard_metrics()`. Fields are null from the backend when the caller's role lacks admin access. The frontend shows `DataState kind="access_denied"` when both security fields are null after a successful RPC call. No frontend role-key check is performed; backend is the sole authority.
- **Normalizer behavior**: All fields use defensive normalizers (`asCount` defaults to 0, `asNullableCount` passes through null). Missing fields from a different backend deploy version return 0 / null without errors.
- **State docs**: `docs/state/dashboard_state.md` created.
- **Validated**: `npm run lint` clean, `npm run build` clean (Next.js 16.2.4, zero errors, zero warnings).
- **Remaining gaps**: `fn_dashboard_metrics()` and `fn_dashboard_operational_analytics()` backend migrations must be deployed remotely. Exact return field names will be confirmed after backend deployment; normalizers are defensive.

## Plantilla Store Staffing MFR Breakdown (OHM2026_1133)

- **Backend contract update**: `list_web_plantilla_store_staffing()` now returns `onboard_count`, `hr_pipeline_count`, `open_headcount`, `required_headcount`, `fill_rate` (OHM2026_1132).
- **MFR formula**: `Actual / (Actual + HR Pipeline + Vacancy)` = `fill_rate` from backend. The web layer does NOT compute MFR.
- **Type changes** (`src/lib/queries/plantilla.ts`): `PlantillaStoreStaffingRow` gains four new canonical fields:
  - `onboardCount` (Actual, from `onboard_count`)
  - `hrPipelineCount` (HR Pipeline, from `hr_pipeline_count`)
  - `openHeadcount` (Vacancy, from `open_headcount`)
  - `fillRate` (MFR %, from `fill_rate`; null when backend does not return it)
  - Legacy aliases `activeHeadcount`, `vacancyCount`, `pipelineCount` retained as pass-throughs to the new canonical fields to preserve `deriveStaffingRisk` backward compat.
- **Normalizer update** (`normalizeStoreStaffingRow`): reads new field names first, falls back to legacy field names for older backend deploys.
- **UI update** (`src/app/(dashboard)/plantilla/page.tsx`):
  - `StoreTable` column headers changed: "Active HC" → "Actual", "Pipeline" → "HR Pipeline", "Vacancies" → "Vacancy", "Required HC" → "Required". "Gap" column removed. "MFR %" column added.
  - MFR % rendered as `(fill_rate * 100).toFixed(1)%` with a tooltip showing the formula.
  - `min-w-[1400px]` updated from `1280px` to accommodate the new column layout.
- **Duplicate MFR calculation removed**: there was no prior web-side MFR computation; guardrail comments added to the normalizer and type to prevent future web-side calculations that exclude HR Pipeline.
- **State docs**: `docs/state/plantilla_web_state.md` store staffing section updated with MFR breakdown table.
- **Validated**: `npm run lint` clean, `npm run build` clean (Next.js 16.2.4, zero errors, zero warnings).

## Read-Only Emergency Mode Enforcement — Vacancy Add Applicant (OHM2026_1132)

- **Issue fixed**: Read-Only Emergency Mode (`read_only_emergency` governance control) was ACTIVE but OM could still add applicants and progress the Vacancy pipeline. The `applicants` RLS policies and SECURITY DEFINER RPCs (`create_applicant_and_link_to_vacancy`, `fn_update_applicant_status`) did not check freeze mode.
- **Root cause**: Both `applicants_insert_ops_only` and `applicants_update_ops_recruitment` RLS policies lacked a freeze guard. SECURITY DEFINER RPCs bypass RLS entirely, creating a second gap.
- **Backend migration**: `20260614000001_web_vacancy_applicant_freeze_enforcement.sql` (sibling Supabase repo):
  - §1 Patched `applicants_insert_ops_only` WITH CHECK: adds `NOT fn_check_freeze_active('read_only_emergency')` guard.
  - §2 Patched `applicants_update_ops_recruitment` USING: adds `NOT fn_check_freeze_active('read_only_emergency')` guard.
  - §3 Added `BEFORE INSERT OR UPDATE` trigger `trg_applicants_read_only_check` on `public.applicants`. Fires even inside SECURITY DEFINER functions — the primary enforcement layer for `create_applicant_and_link_to_vacancy` and `fn_update_applicant_status`. Raises `P0001` with message "Read-Only Emergency Mode is active. Write actions are temporarily disabled."
  - §4 Created `get_web_freeze_mode_status()` SECURITY DEFINER RPC (granted to `authenticated`; revoked from anon/public). Returns `{ is_read_only_emergency_active, activated_at, activated_by_name, reason }` JSONB.
- **RBAC**: OM, HRCO, ATL, TL, Encoder, Recruitment, HA — all blocked from applicant writes when freeze is active (trigger fires regardless of role). SA can deactivate the freeze via `fn_update_freeze_mode` only; SA is NOT bypassing normal applicant writes while freeze is active.
- **Web query layer**: `src/lib/queries/freeze.ts` — `getWebFreezeModeStatus()`, `FreezeModeStatus` type, `FreezeModeError` class. Polls `get_web_freeze_mode_status` with 30s stale-time.
- **Vacancy page** (`src/app/(dashboard)/vacancy/page.tsx`): Fetches freeze status via React Query (`["freeze-mode-status"]` key, 30s stale-time). Renders a full-width red `role="alert"` banner above KPI cards when freeze is active, showing the freeze reason and activating user. Passes `isFreezeModeActive` to `VacancyDetailDrawer`.
- **VacancyDetailDrawer** (`src/components/vacancy/VacancyDetailDrawer.tsx`): Accepts `isFreezeModeActive?: boolean` prop. Passes it to `CapabilityActionBar` as `isReadOnlyEmergencyActive`. Added "Add Applicant" as an explicit action item alongside "Update Applicant Status" (both gated by `canUpdateApplicantStatus`).
- **CapabilityActionBar** (`src/components/shared/CapabilityActionBar.tsx`): New `isReadOnlyEmergencyActive?: boolean` prop. When active: renders a red in-bar `ShieldOff` banner ("Read-Only Emergency Mode is active. Write actions are temporarily disabled."), forces all buttons to `disabled`, and replaces badge labels with "read-only mode" (red styling).
- **Enforcement principle**: Frontend is ergonomics only. Backend trigger + RLS is the authority. Supabase will reject any write regardless of frontend state.
- **Smoke tests**: `docs/smoke-tests/vacancy_freeze_mode_enforcement.sql` — 9 targeted tests (T1–T9) covering trigger existence, RLS policy update, RPC existence, inactive/active state reads, OM Add Applicant blocked, Update Status blocked, direct INSERT blocked, and post-deactivation recovery.
- **Validated**: `npm run lint` clean, `npm run build` clean (Next.js 16.2.4, zero errors, zero warnings).
