# "More" Module Mobile-to-Web Parity Audit & Implementation Roadmap

**Prompt ID:** `ohm#w28m619e`  
**Date:** 2026-10-10  
**Auditor:** Antigravity (Pair Programming / Read-Only Deep Audit Pass)  
**Target Codebases:**
- Mobile Source of Truth: `D:\Projects\OHMployee` (`lib/features/more/more_screen.dart`, `docs/state/more_module_state.md`, sub-screens in `lib/features/more/`)
- Web Implementation Target: `D:\Projects\ohmployee-web` (`src/app/(dashboard)/more/page.tsx`, `src/lib/modules.ts`, navigation shells)

---

## 1. Executive Summary

In the mobile Flutter codebase ([`OHMployee`](file:///D:/Projects/OHMployee)), the **"More" screen** serves as the central administrative, tertiary utilities, governance, and request navigation hub. It contains:
1. A **Compact Profile Identity Card** linking to profile settings, personal information, and password change.
2. A **Temporary Access Banner Card** (`temp_permission_overrides`) notifying users of active time-bound group overrides.
3. **6 Hierarchical Operational Sections** containing **26 feature tiles/menu entries**, complete with dynamic badge polling (Request Center pending queues and user's own submitted requests) and per-user module visibility overrides (`OHM2026_3001`).
4. A prominent **Logout** action.

In the Next.js 15 App Router web app ([`ohmployee-web`](file:///D:/Projects/ohmployee-web)):
- Route [`src/app/(dashboard)/more/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/more/page.tsx) currently renders only `<ModuleEmptyState href="/more" />`.
- Many tertiary utilities (such as Request Center queues, Data Control tools, Admin Tools, and System Settings) are either partially split into dedicated desktop sidebar items (e.g., [`/approvals`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/approvals/page.tsx), [`/users`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/users/page.tsx), [`/team-directory`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/team-directory/page.tsx), [`/settings`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/settings/page.tsx)) or currently completely unmapped.

This document establishes the exhaustive feature inventory, role gating, database/RPC dependencies, mobile vs. web platform adaptations, and a phased implementation plan for achieving full 1-to-1 operational parity.

---

## 2. Feature & Tile Inventory (Mobile vs. Web)

The mobile `MoreScreen` defines 6 sections (`MoreSectionId`): `teamDirectory`, `adminTools`, `requests`, `accessManagement`, `dataControl`, and `system`.

### 2.1 Profile Identity Header & Temporary Access Banner
| Element / Feature | Mobile Implementation | Web Current State | Web Parity Target & Adaptation |
| :--- | :--- | :--- | :--- |
| **Profile Identity Card** | `ProfileIdentityCard` displaying user avatar/initials, full name, role title. Tapping opens `ProfileSettingsScreen` (profile view, edit details, change password). | Present in desktop topbar / layout headers to some degree, but missing from `/more`. | Card rendered at top of `/more` or linked in topbar dropdown. In `/more`, render compact identity card linking to `/settings/profile` or modal profile sheet. |
| **Temporary Access Banner** | `_TempAccessStatusCard` querying `temp_permission_overrides` for active override records (`additional_groups`, `expires_at`, `reason`). | None on web. | Component checking `temp_permission_overrides` for current `auth.uid()` / profile ID. Renders amber/green card with expiration countdown. |

---

### 2.2 Section 1: Team Directory (`teamDirectory`)
| Item ID | Title & Subtitle | Allowed Roles | Target Route / Component | Web Platform Adaptation |
| :--- | :--- | :--- | :--- | :--- |
| `team_directory` | **Team Directory**<br>*Find and contact Ops, Recruitment, and Data Team users* | All Roles (Super Admin, Head Admin, OM, HRCO, ATL, TL, Encoder, Recruitment, HR, Backoffice, Viewer) | Mobile: `TeamDirectoryScreen`<br>Web: `/team-directory` | Web already has top-level route `/team-directory` (currently placeholder). Link tile to `/team-directory` or render directory table. |

---

### 2.3 Section 2: Admin Tools (`adminTools`)
*Strictly restricted to **Super Admin** (`role_level >= 100`). Hidden for all other roles.*

| Item ID | Title & Subtitle | Mobile Screen Target | Backend / Data Dependencies | Web Platform Adaptation |
| :--- | :--- | :--- | :--- | :--- |
| `ohms_safespace` | **OHM's Safespace**<br>*Owner command center — system controls, risk, and diagnostics* | `SafespaceScreen` | Diagnostics RPCs, system kill-switches, error tracking, telemetry | Admin command center dashboard under `/more/safespace` or `/admin/safespace`. |
| `switch_role` | **Switch Role**<br>*Act as a different role with scoped access for testing* | `SwitchRoleScreen` | Session/role switcher token/claim override in client state | Development / Super Admin impersonation bar or drawer dialog. |
| `qa_center` | **QA Center**<br>*Read QA health, runs, findings, schedules, and reports* | `QaCenterScreen` | QA test execution tables, automated check runs, discrepancy tables | Web QA dashboard with run history and test suites. |
| `permission_matrix` | **Permission Matrix**<br>*Edit role permissions with audited overrides* | `PermissionMatrixScreen` | `role_permissions`, `module_visibility_overrides`, audit logging | Interactive data grid / matrix table editor with role permission checkboxes and save dialog. |
| `role_permissions` | **Role Permissions**<br>*Read-only backend authorization matrix* | `RolePermissionsScreen` | `roles`, `role_permissions` schema views | Read-only matrix view comparing role permissions against system defaults. |
| `permission_drift` | **Permission Drift**<br>*Authorization gap and mismatch findings* | `PermissionDriftScreen` | Drift inspection RPCs comparing DB policies vs role metadata | Discrepancy report table highlighting permission mismatches. |
| `security_events` | **Security Events**<br>*Security activity and alerts* | `SecurityDashboardWrapper` | `security_events`, `auth_audit_logs`, `SecurityDashboardService` | Security event feed and threat indicator dashboard under `/more/security`. |
| `allocation_health` | **Workforce Integrity**<br>*Allocation, roving, import, and CENCOM operational health checks* | `WorkforceAllocationHealthScreen` | `fn_check_workforce_allocation_health`, roving conflict queries | Automated validation diagnostic report for orphaned plantilla entries, overlapping roving coverage, and missing CENCOM links. |
| `audit_logs` | **Audit Logs**<br>*System activity and changes* | `AuditLogsScreen` | `audit_logs` table (filtering by entity, actor, timestamp) | Searchable, paginated audit trail data table with JSON payload inspector. |
| `access_control_center` | **Access Control Center**<br>*Module visibility overrides per user* | `AccessControlCenterScreen` | `module_visibility_overrides` (`OHM2026_3001`) | Per-user module override matrix (granting/denying specific module visibility). |
| `data_archival_center` | **Data Archival Center**<br>*Archive and rollback operational data with audit controls* | `DataArchivalCenterScreen` | `data_archival_center_service`, archival batch tables | Multi-tab admin tool for archiving operational cycles and viewing batch rollback logs. |

---

### 2.4 Section 3: Request Center (`requests`)
*Scoped by item based on operational role. Displays live numeric badges for pending counts.*

| Item ID | Title & Subtitle | Allowed Roles & Gate | Mobile Screen Target | Web Current State & Adaptation |
| :--- | :--- | :--- | :--- | :--- |
| `my_requests` | **My Requests**<br>*Track status of your submitted requests* | All operational roles (`_canSeeMyRequests`). Badge: `_myRequestsBadgeCount`. | `MyRequestsScreen` | Web currently has approvals queue for admins under `/approvals`, but needs `/requests/my-requests` or dedicated "Submitted by Me" view tab. |
| `new_store_request` | **New Stores**<br>*Review store creation request status and approvals* | SA, HA, Data Team (`user.hasFullAccess \|\| user.appRole.isDataTeam`). Badge: pending new stores. | `RequestCenterScreen(initialTypeFilter: 'New Store Requests')` | Integrated into web `/approvals` left navigation (`new_stores` category). |
| `headcount_requests` | **Headcount**<br>*Review and approve headcount requests* | SA, HA, Encoder, Viewer. Badge: pending headcount requests. | `HeadcountRequestsScreen` | Integrated into web `/approvals` (`headcount` category). |
| `coverage_requests` | **Coverage**<br>*Draft and review structure-only coverage changes* | SA, HA, Encoder. Badge: pending coverage. | `CoverageRequestScreen` | Integrated into web `/approvals` (`coverage` category). |
| `vacancy_closure` | **Vacancy Closures**<br>*Review closure/deletion requests* | SA, HA, Encoder (`user.canReviewClosure`). Badge: pending closures. | `VacancyClosureReviewScreen` | Integrated into web `/approvals` (`vacancy_closures` category). |
| `emploc_deletion` | **HR Emploc Deletions**<br>*Review HR Emploc deletion requests* | SA, HA, Encoder (`user.canReviewDeletion`). Badge: pending deletions. | `HrEmplocDeletionReviewScreen` | Integrated into web `/approvals` (`hr_emploc_deletions` category). |
| `deactivation` | **Deactivations**<br>*Manage employee deactivation requests* | SA, HA, Backoffice Personnel. Badge: pending deactivations. | `DeactivationRequestsScreen` | Integrated into web `/approvals` (`deactivations` category). |
| `applicant_movement_requests` | **Applicant Movements**<br>*Transfer or swap pipeline applicants between vacancies* | SA, HA, Encoder (hidden from OM, HRCO, ATL, TL, Recruitment, Backoffice). Badge: pending movements. | `ApplicantMovementRequestScreen` | Integrated into web `/approvals` (`applicant_movements` category). |
| `account_group_transfer_requests` | **Account Group Transfers**<br>*Transfer account ownership between groups* | SA, HA. Badge: pending group transfers. | `AccountGroupTransferRequestsScreen` | Integrated into web `/approvals` (`account_group_transfers` category). |

---

### 2.5 Section 4: Access Management (`accessManagement`)
| Item ID | Title & Subtitle | Allowed Roles | Mobile Screen Target | Web Current State & Adaptation |
| :--- | :--- | :--- | :--- | :--- |
| `account_requests` | **Account Requests**<br>*Approve or reject new account sign-ups* | SA, HA (`user.hasFullAccess`) | `AccountApprovalQueuePage` | Approval queue for pending self-registrations / invitations. Needs web queue table under `/users/requests` or `/more/account-requests`. |
| `user_management` | **User Management**<br>*Password reset / transfer account* | SA, HA (`user.canManageUsers`) + Module Visibility Override | `UserManagementScreen` | Dedicated web route `/users` exists in sidebar (currently empty state). Audit document [`user_management_mobile_web_parity_audit.md`](file:///d:/Projects/ohmployee-web/docs/audit/user_management_mobile_web_parity_audit.md) specifies web implementation. Tile on `/more` links directly to `/users`. |
| `access_control` | **Temporary Group Access**<br>*Grant time-bound additional group scope to encoders* | SA, HA (`user.isSuperAdmin \|\| user.isHeadAdmin`) | `TempPermissionScreen` | Admin screen to grant encoders temporary access to groups with expiration timestamp. Route under `/more/temp-access`. |

---

### 2.6 Section 5: Data Control (`dataControl`)
| Item ID | Title & Subtitle | Allowed Roles | Mobile Screen Target | Web Platform Adaptation |
| :--- | :--- | :--- | :--- | :--- |
| `import_plantilla` | **Import Plantilla**<br>*Upload Store Master List CSV* | SA, HA, Encoder + Module Override | `StoreImportScreen` | Web CSV bulk upload dropzone with column mapping and dry-run validation preview under `/plantilla/import` or `/more/import-plantilla`. |
| `import_hr_emploc` | **Import HR Emploc**<br>*Bulk upload HR Emploc records via XLSX with HA/SA approval* | SA, HA, Encoder + Module Override | `HrEmplocImportScreen` | Web XLSX uploader with staging approval flow under `/hr-emploc/import` or `/more/import-hr-emploc`. |
| `global_store_transfer` | **Global Store Transfer**<br>*Request employee store transfers for SA approval* | SA, HA (`user.hasFullAccess`) | `GlobalStoreTransferScreen` | Multi-select transfer modal or wizard transferring employees between stores across account boundaries. |
| `import_vacancy` | **Import Vacancy**<br>*One-time migration of existing vacancies from Google Sheets* | SA, HA, Encoder + Module Override | `VacancyImportScreen` | Spreadsheet migration wizard under `/vacancy/import` or `/more/import-vacancy`. |
| `import_files` | **Import MIKA**<br>*Upload MIKA file* | SA, HA + Module Override | `MikaImportScreen` | File upload interface for MIKA operational reports. |
| `import_payroll` | **Import Payroll**<br>*Compare payroll file against active Plantilla* | SA, HA (`user.hasFullAccess`) | `PayrollCheckScreen` | Reconciliation file uploader comparing external payroll records against active Plantilla roster. |
| `payroll_review_center` | **Payroll Review Center**<br>*Review findings with Ops and track resolution* | SA, HA, Encoder, OM (`user.hasFullAccess \|\| user.isDataTeam \|\| user.appRole == AppRole.om`) | `OpsPayrollReviewScreen` (for OM) / `PayrollReviewCenterScreen` (for others) | Operational variance dispute and discrepancy resolution queue. |
| `edit_lock` | **Edit Lock Control**<br>*Restrict edits during CENCOM or review periods* | SA, HA (`user.isSuperAdmin \|\| user.isHeadAdmin`) | `EditLockControlScreen` | Master system switch locking edits across Vacancy, Plantilla, and Headcount with audited override reasons. |
| `roving_coverage_groups` | **Roving Coverage Groups**<br>*Manage roving store coverage groups* | SA, HA, Data Team (`user.hasFullAccess \|\| user.isDataTeam`) | `CoverageGroupListScreen` | Configuration grid for defining multi-store roving clusters. |
| `data_recovery` | **Data Archival / Recovery**<br>*Review archived records and audit history* | SA, HA (`user.isSuperAdmin \|\| user.isHeadAdmin`) | `DataArchivalRecoveryScreen` | Trash bin / recovery center for inspecting soft-deleted plantilla, vacancies, and records with one-click restore. |

---

### 2.7 Section 6: System (`system`)
| Item ID | Title & Subtitle | Allowed Roles | Mobile Screen Target | Web Platform Adaptation |
| :--- | :--- | :--- | :--- | :--- |
| `app_settings` | **App Settings**<br>*Theme, biometrics, and session preferences* | All Roles | `AppSettingsScreen` | Desktop `/settings` route. Contains Appearance (Light/Dark theme), Session Timeout info, Notification alert preferences, and App Version diagnostics. *(Biometric login is mobile-specific, omitted on web).* |

---

## 3. Platform Distinction Analysis: Mobile-Only vs. Web Adaptations

To avoid anti-patterns when transitioning from mobile to desktop web, the audit identifies which behaviors must be adapted:

| Component / Feature | Mobile Behavior | Web Adaptation Strategy |
| :--- | :--- | :--- |
| **Biometric Authentication** | Device FaceID / Fingerprint toggle (`BiometricAuthService`, `local_auth`). | **Mobile-Only**: Do not include hardware biometrics on web. Replace with WebAuthn/Passkeys in a future iteration, or omit in favor of standard session cookies & Supabase Auth. |
| **Session Timeout** | App-level timer triggering local biometric / PIN re-lock. | Web uses `IdleWarningModal.tsx` and Supabase cookie expiration, which is already configured. |
| **Navigation Structure** | Single-column scroll list (`ListView`) with iOS Settings grouping style. | **Dual Surface Architecture on Web**: <br>1. **Primary Desktop Sidebar**: High-frequency items already live in the left sidebar (`/approvals`, `/users`, `/team-directory`, `/settings`, `/plantilla`, `/cencom`).<br>2. **Hub Page (`/more`)**: Responsive grid layout (2 or 3 columns of group cards) categorizing Tertiary Admin, Governance, Data Control, and Archival tools for fast discoverability. |
| **Badge Counter Clearing** | Tapping a Request Center item locally clears its pending badge in UI state before server refetch. | Web Approvals (`approvals/page.tsx`) already implemented this clear-on-click pattern via `acknowledgedCategories`. Maintain parity across `/more` badges. |
| **File Import / Bulk Operations** | File picker dialog (`file_picker`) uploading single CSV/XLSX. | Full desktop Drag & Drop dropzone with live schema column mapping and client-side PapaParse / SheetJS validation. |

---

## 4. Permission & Role Gating Logic

The mobile implementation enforces a three-tier permission model that web must mirror:

```
┌─────────────────────────────────────────────────────────────────┐
│                      1. Core Role Level                         │
│  - Super Admin (100): Full access to all 6 sections             │
│  - Head Admin (90): Access to Requests, Access, Data, System    │
│  - Encoder (30): Scoped Requests, Data Imports, Roving          │
│  - Operations (OM/HRCO/ATL/TL): My Requests, Payroll Review, Dir│
│  - Backoffice (10): Deactivations Queue, Directory, Settings    │
│  - Viewer (0): Directory, Settings, Read-only queues            │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│              2. Per-Item Permission Capabilities                │
│  - user.canManageUsers                                          │
│  - user.canReviewClosure / user.canReviewDeletion               │
│  - user.canManageAdminOverrides (Edit Lock)                     │
│  - user.hasFullAccess (SA || HA)                                │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│         3. OHM2026_3001 Module Visibility Overrides            │
│  Table: module_visibility_overrides                             │
│  States: 'allow' (force visible) | 'deny' (force hidden) |       │
│          'inherit' (fall back to role default)                  │
│  Governs: keySecurity, keyImports, keyUserManagement            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Backend Dependencies & RPC Map

The "More" ecosystem interfaces with the following Supabase tables, views, and stored procedures:

### Core Tables
1. `users_profile`: User profiles, role references, HRCO global visibility.
2. `roles`: Role definitions and authorization levels (`role_level`).
3. `temp_permission_overrides`: Temporary group scoping for encoders.
4. `module_visibility_overrides`: Per-user module allow/deny overrides.
5. `edit_lock_status` / `system_settings`: Master operational edit locking.
6. `audit_logs`: Centralized audit trail for all admin actions.
7. `data_archival_batches` / `archived_*`: Data Archival Center history and soft-deleted records.

### RPCs & Functions
- `fn_get_my_requests_pending_count(user_id)`: Badge count for submitted requests.
- `fn_get_request_center_pending_counts()`: Category count dictionary for the 8 request queues.
- `fn_lock_vacancy_editing(actor_id, reason)` / `fn_unlock_vacancy_editing(actor_id, reason)`: Edit lock controls.
- `fn_restore_plantilla_record(id, reason)` / `fn_restore_vacancy_record(id, reason)`: Data recovery actions.
- `fn_get_active_temp_permission(user_id)`: Checks active temporary access for user.

---

## 6. Implementation Roadmap for Web Parity

### Phase 1: `/more` Hub Dashboard & Section Layout (Current Step)
- [ ] Transform [`src/app/(dashboard)/more/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/more/page.tsx) from `ModuleEmptyState` into an interactive settings & operational hub.
- [ ] Implement the **Compact Profile Identity Card** and **Temporary Access Banner** (`_TempAccessStatusCard`).
- [ ] Group menu tiles into responsive card clusters:
  1. **Team Directory**
  2. **Admin Tools** (gated strictly to Super Admin)
  3. **Request Center** (showing live badges, routing to `/approvals` or sub-queues)
  4. **Access Management** (routing to `/users` and `/more/temp-access`)
  5. **Data Control** (routing to import wizards, edit lock, archival recovery)
  6. **System** (routing to `/settings`)
- [ ] Implement per-user module visibility override checks (`OHM2026_3001`).

### Phase 2: High-Priority Utilities & Gated Modals
- [ ] **Edit Lock Control** (`/more/edit-lock` or modal drawer): Add toggle with reason prompt for freezing operations during review cycles.
- [ ] **Temporary Group Access** (`/more/temp-access`): Manage encoder time-bound group overrides.
- [ ] **Data Archival / Recovery Center** (`/more/data-recovery`): Inspect and restore archived records.
- [ ] **Workforce Integrity & Audit Logs**: Add audit trail inspection page and workforce health diagnostics.

### Phase 3: Import & Data Migration Wizards
- [ ] **Import Plantilla**: Master Store CSV uploader.
- [ ] **Import HR Emploc**: XLSX uploader with HA/SA approval queue.
- [ ] **Import Vacancy**: Google Sheets migration parser.
- [ ] **Import Payroll / Payroll Review Center**: External payroll reconciliation tool.

---

## 7. Verification Checklist

- [x] Full inventory of all 26 tiles, 6 sections, header card, and bottom action.
- [x] Role gating and `OHM2026_3001` override rules documented.
- [x] Backend tables, RPCs, and query services mapped.
- [x] Mobile-only features identified (biometrics) and web alternatives established.
- [x] Report saved to `docs/audit/more_module_mobile_web_parity_audit.md`.
