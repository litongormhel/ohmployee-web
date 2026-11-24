# Operations Hub (formerly More) & Settings Module State

## Overview
This document captures the current stable architecture and navigation contract for `/settings` and `/more` ("Operations Hub").

### Web Navigation & Sidebar Placement
- **Operations Hub (`/more`)**: Rebranded to "Operations Hub" across `src/lib/modules.ts`, `Sidebar.tsx`, and `AdminPageHeader`. Serves as the dedicated hub for batch XLSX imports (Data Team / Encoders), payroll review & reconciliations (Operations Managers), roving coverage & store transfers, governance tools, system diagnostics, QA sandboxing, and security/audit centers.
- **Settings (`/settings`) Integration**:
  - Permanently integrated into the `Sidebar.tsx` footer:
    - User identity badge (`userName` & `userRole`) functions as a direct 1-click link to `/settings`.
    - Dedicated ⚙️ Settings icon button added to the footer action group next to Theme toggle and Sign Out.
    - Excluded from the middle `secondaryModules` list to eliminate visual duplication while maintaining active-state indicator in the footer.

## Settings Module (`/settings`)
- **Tabs**:
  - `profile`: Profile & Security (avatar upload/delete, name, email, mobile validation `^09[0-9]{9}$`, assigned groups and accounts from `users_profile`, `roles`, and `user_scopes`).
    - *Error & Timeout Handling*: Includes a 15-second timeout wrapper (`Promise.race`) and single-retry configuration. Renders a high-contrast danger error banner with copy "Couldn't load profile information" and a dedicated `Retry` button upon failure.
  - `preferences`: Preferences & Appearance (theme switcher, alert toggles, typography, reduce motion, 30-minute idle auto-logout disclosure).
  - `security`: Security Center & Sessions (current device telemetry, active sessions list with revoke actions, security compliance audit trail).
- **Diagnostics Redirection**:
  - Legacy URL `settings?tab=diagnostics` is caught at page level:
    - Super Admin (`role_level >= 100` / `isSuperAdmin`) is redirected to `/more?tab=admin_tools&tool=system_diagnostics`.
    - Non-admin roles fallback safely to the default tab (`/settings`).
  - Settings page header subtitle: "Manage your profile security, application preferences, and device sessions."

## More Module (`/more`)
- **Tabs**:
  1. `overview`: Profile & quick shortcuts (`User Management` [HA], `Account Requests` [HA], `Team Directory`, `Payroll Review Center` [OM only], `Account Settings`, `Sign Out`).
     - *OM Access Invariant*: Operations Managers (OM) do not have access to the `data_control` tab, so the `Payroll Review Center` shortcut is surfaced in Overview exclusively for OM. For Head Admin, Encoder, and Super Admin, the entry is accessible canonically under `data_control`.
  2. `admin_tools` (Super Admin Level 100 only):
     - `ohms_safespace`: OHM's Safespace (emergency controls and risk overview).
     - `system_diagnostics`: System Diagnostics (health probes, governance controls, freeze breakdown, and PostgREST schema cache reload utility `NOTIFY pgrst, 'reload schema';`).
     - `switch_role`: Role impersonation for development and testing.
     - `qa_center`: QA health metrics, test runs, findings, and scenarios.
  3. `permissions` (Head Admin & Super Admin):
     - `temp_permission`: Temporary Group Access overrides.
     - `access_control_center`: Access Control Center (Super Admin).
     - `permission_matrix`: Role permission overrides (Super Admin). Features interactive Allow/Deny toggles, per-row **"Reset to Default"** action for active overrides, and a toolbar **"Reset All to Default"** bulk action with audit confirmation dialog. Backed by PostgreSQL RPCs `get_effective_permission_matrix`, `apply_permission_overrides`, and `reset_permission_overrides`.
     - `role_permissions`: Read-only authorization matrix (Super Admin).
     - `permission_drift`: Authorization mismatch detector (Super Admin).
  4. `audit` (Super Admin Level 100 only):
     - `security_events`: Security alerts and threat indicators.
     - `allocation_health`: Workforce Integrity (`/cencom`).
     - `audit_logs`: Detailed system audit activity trail rendered with human-readable operational summaries (`audit_formatter.ts`), entity badges (person name, VCode, outlet), human-readable targets with subtle UUID copy trigger, and clean scalar field diffs (technical UUIDs and raw JSON dumps eliminated). Gated strictly at database level via `audit_logs_select` to Super Admin / Head Admin (`role_level >= 90`), with `v_audit_activity_feed` locked down with `security_invoker = true` and `SELECT` revoked from `authenticated`/`anon` (Hotfix A `ohm#4c8x1nw6`).
  5. `data_control` (Head Admin & Encoder):
     - Sub-tab `operations`:
       - `edit_lock_control`: Edit Lock Control (Security).
       - `data_archival_control`: Data Archival & Recovery (Canonical single entry point; Level 100 / Super Admin).
       - `global_store_transfer`: Global Store Transfer requests.
       - `roving_coverage_groups`: Roving coverage group pools (inspection modal with inline `+ Create Group` trigger opening `the unified 5-tab CreateCoverageGroupModal (Create, Add Store, Remove Store, Merge, Dissolve)`).
       - `payroll_review_center`: Payroll Review Center (Canonical review hub).
       - `ghost_detection`: Ghost Employees Detection Center (`tool=ghost_detection`). Comprehensive anomaly tracking and resolution surface for weekly MIKA biometric attendance uploads, categorizing anomalies into Type A (Unregistered / Missing from Plantilla) and Type B (Inactive / Separated Anomaly), enforcing 1-week resolution SLA with age tracking, and supporting automatic resolution upon Plantilla activation. Implements two-tier triage: Field Ops (HRCO, TL, ATL) view account-scoped cases and submit Operational Verification Notes; Data Team & Admins (Encoder 30, HA 70, SA 90) execute formal status mutations. MIKA batch approval triggers targeted notifications (Global for OM/Admins vs Account-Scoped for Field Ops).
     - Sub-tab `batch_imports`:
       - Full-Page Architecture: All 5 batch imports are rendered as URL-driven full-page views via `BatchImportPageShell` rather than modals, providing full-width/full-height content, unclipped preview tables scrolling inside the page body, and a sticky action footer (`sticky bottom-0`).
       - URL Contract: `/more?tab=data_control&subtab=batch_imports&import=<plantilla|hr_emploc|vacancy|mika|payroll>`.
         - Invalid or omitted `import` parameter cleanly falls back to the Batch Imports card grid.
         - Back control ("← Back to Batch Imports") and footer "Close" action both return to the card grid.
         - Browser back/forward navigation and refresh preserve active import and tab state.
         - Legacy `/hr-emploc/import` route and `open=import_hr_emploc` query param map to `import=hr_emploc`.
       - `hr_emploc_import`: HR Emploc XLSX bulk import (`import=hr_emploc`).
       - `plantilla_import`: Plantilla batch import (`import=plantilla`). Internal rejection and rollback confirmation actions retain focused `<Modal>` dialogs.
       - `vacancy_import`: Vacancy batch import (`import=vacancy`). Internal rollback and rejection actions retain focused `<Modal>` dialogs.
       - `mika_import`: Mika import (`import=mika`). Uploads MIKA biometric / attendance sheets with cross-check detection against active Plantilla (clean, ghost employee isolation, blocked account mismatch). Cross-check queries valid Plantilla columns (`status`, `is_deleted`, `deactivated_at`, `store_name`, `account`) and active roving allocations from `employee_store_allocations`, validating against official active accounts (public.accounts) and the employee's assigned account in public.plantilla; any unlisted account or mismatch against Plantilla is strictly flagged as locked (Mismatch), prohibiting store or retail chain names (e.g. SUPER 8) from being imported as accounts. Ingestion maps spreadsheet `dateHired` to PostgreSQL column `date_hired` in `public.mika_import_rows` in 100-row chunks, automatically cleans up orphaned header logs upon ingestion failure, and propagates API error details cleanly to the review banner. Import History table features clickable rows that open a detailed rows preview `<Modal>` displaying uploaded records, an `Uploaded Rows` count column, and 15-item `TablePagination`. Approving a pending batch in the Review Queue automatically propagates matched employee rows and statutory data to `public.plantilla`. Features a 72-hour Rollback window for Head Admin and Super Admin (`roleLevel >= 70`) in the History tab with confirmation modal requiring operational remarks, reverting `mika_import_logs.status` to `'Rolled Back'`, auto-clearing active ghost cases, and logging to `audit_logs`.
       - `payroll_import`: Payroll reconciliation import (`import=payroll`). Pure read-only checker with sticky review center handover trigger.

## Data Archival & Recovery Consolidation
- Canonical entry point is strictly located in **More > Data Control > Operations & Governance > "Data Archival & Recovery"** (Level 100).
- Duplicate entry points in Admin Tools ("Data Archival Center") and Audit & Integrity ("Data Archival & Recovery") have been retired.
- Opens `DataArchivalCenterModal` allowing Super Admins to inspect soft-deleted plantilla and vacancy records and perform restorations with audited justification logging.

## QA Center & Simulation Engine (More > Admin Tools > QA Center)
- **Modal Entry**: `QaCenterModal` rendered from `/more?tab=admin_tools&tool=qa_center`.
- **Database Engine**: `public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY')` (Security Definer, search_path `public`, Head Admin / Super Admin authorization guard).
- **Atomic Sandbox Isolation & Zero Pollution**:
  - The simulation executes within an atomic PL/pgSQL subtransaction (`BEGIN ... EXCEPTION ... END`).
  - Controlled rollback is triggered via `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`.
  - Guarantees 100% rollback of all mock/simulated operational records across `vacancies`, `plantilla`, `applicants`, `hr_emploc`, and `users_profile` (0 records remain in live tables).
- **Multi-Role Simulation Relay (`FULL_E2E_RELAY`)**:
  - Executes a sequential 7-step workflow relay across 6 key roles:
    1. **Head Admin**: Headcount quota authorization & vacancy opening (`QA-RELAY-*`).
    2. **Encoder**: Plantilla slot allocation and binding (`EMP-RELAY-*`).
    3. **Recruitment**: Applicant candidate intake and pipeline registration (`Jane Relay Doe`).
    4. **HRCO / Operations**: Onboarding confirmation and candidate stage progression.
    5. **HR Personnel**: HR Emploc assignment generation and employee number synchronization.
    6. **Back Office**: Plantilla movement request metadata recording.
    7. **Back Office (Negative Security Barrier)**: Verification that Back Office actor is strictly blocked from executing administrative / Head Admin mutations.
- **Dual GUC Impersonation**: Sets both `request.jwt.claim.sub` and `request.jwt.claims` so `auth.uid()` and `get_my_role_level()` evaluate the simulated actor's level correctly, with defensive restoration of original JWT claims upon completion.
- **Persistent Telemetry**:
  - Telemetry is recorded outside the rolled-back subtransaction:
  - Run metadata is persisted to `public.qa_agent_runs` (`id`, `agent_name = 'QA_ROLE_RELAY_ENGINE'`, `execution_type = 'manual'`, `status = 'completed'`, `summary`, `metadata->'steps'`).
  - Defect findings (if any) are logged to `public.qa_agent_findings` (`run_id`, `severity`, `finding_type`, `category`, `title`, `details`, `recommendation`).
- **UI Components (`src/components/more/qa/`)**:
  - `QaCenterModal.tsx`: Host modal orchestrating QA snapshot queries, scenario execution, and subviews.
  - `QaSimulationRunner.tsx`: Scenario selector (`FULL_E2E_RELAY`, `VAC_ARCHIVE_001`, `RBAC_AUDIT_001`, etc.) and execution trigger.
  - `QaStepTimeline.tsx`: Sequential step-by-step progress timeline displaying step numbers, role badges (`Head Admin`, `Encoder`, `Recruitment`, `HRCO`, `HR Personnel`, `Back Office`), action names, status (`passed` / `failed`), and details.
  - `QaRunHistoryTable.tsx`: Historical test run table displaying run ID, agent name, status, duration, steps badge, and isolation status.
  - `QaFindingsViewer.tsx`: Defect inspection list displaying finding code, severity badge, category, details, and actionable remediation callouts.

## Reports Module (`/reports`)
- **Overview**: Standard operational and analytical workforce reporting cockpit providing group/account aggregated metrics, timeline filters, interactive drilldowns, and CSV/XLSX export capabilities.
- **Reports Catalog Architecture (`ReportsCatalogTab.tsx`)**:
  - Compact High-Density Grid: Re-architected from oversized ~190px cards to sleek, horizontal ~70px cards (`grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5`), achieving a 62% reduction in vertical footprint while preserving full keyboard accessibility and touch targets.
  - Giant Hero Banner Removed: Eliminated redundant 180px hero banner to bring all 13 reports immediately above the fold below `AdminPageHeader`.
  - Filter & Search Toolbar: Integrated category filter chips (`All Reports [13]`, `Separation [6]`, `Velocity [3]`, `Operations [4]`) and real-time live search input with quick clear `(×)` action.
- **RPC & Database Contracts**:
  1. `public.fn_get_attrition_details(p_account_id uuid, p_start_date date, p_end_date date)`:
     - Returns individual employee drilldown records for attrition analysis (`plantilla_id`, `employee_number`, `employee_name`, `store_name`, `position`, `date_of_separation`, `deactivation_reason`, `separation_status`, `remarks`).
     - Reason Waterfall: Resolves `deactivation_reason` using `COALESCE(NULLIF(TRIM(p.deactivation_reason), ''), NULLIF(TRIM(p.remarks), ''), p.separation_status, 'Separated')`.
     - Supports `p_start_date IS NULL` and `p_end_date IS NULL` for all-time historical separation queries.
     - Preserves ADR Rule 5 ordering: `ORDER BY COALESCE(p.date_of_separation, p.deactivated_at::date, p.created_at::date) DESC, p.full_name ASC`.
  2. `public.report_terminated_by_group(p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_group_id uuid DEFAULT NULL, p_account_id uuid DEFAULT NULL)`:
     - Aggregates involuntary separations across groups and accounts.
     - Status Filter: Strictly includes `p.separation_status IN ('Terminated', 'End of Contract', 'Endo', 'Others')` (or `p.deactivation_reason ILIKE '%terminat%'`).
     - Date Filter: Evaluates `COALESCE(p.date_of_separation, p.deactivated_at::date)`.
  3. `public.report_backout_by_group(p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_group_id uuid DEFAULT NULL, p_account_id uuid DEFAULT NULL)`:
     - Aggregates candidate and onboarded employee dropouts across groups and accounts.
     - Candidate Deduplication & Inclusion: Captures both post-offer `hr_emploc` dropouts (independent of `deleted_at`, since `public.tag_backout` sets `deleted_at = now()`) and pre-onboarding pipeline dropouts from `public.applicants` (`status ILIKE '%backout%'`), deduplicated via `LEFT JOIN hr_emploc ON hr_emploc.applicant_id = a.id WHERE hr_emploc.id IS NULL`.
     - Date Filter: Evaluates `COALESCE(h.backout_date::date, h.updated_at::date)` and `a.updated_at::date`.
  4. `public.report_backout_terminated_by_group(p_start_date date DEFAULT NULL, p_end_date date DEFAULT NULL, p_group_id uuid DEFAULT NULL, p_account_id uuid DEFAULT NULL)`:
     - Combined headcount loss report unifying candidate back-outs and employee terminations.
     - CTE Qualification: Avoids PL/pgSQL variable collisions (`ERROR: 42702`) by explicitly alias-qualifying column projections in `UNION ALL`.
     - UI Contract (`ReportDetailView.tsx`): Displays combined total count with secondary breakdown badge (`{total} ({backout} back-outs • {term} term)`) and exports dedicated `Back-Outs` and `Terminated` columns in CSV/XLSX.

- **Modal Entry**: `SwitchRoleModal` triggered from `/more?tab=admin_tools` tile (`switch_role`) or `targetModal === "switch_role"`.
- **Database Engine**:
  - `public.start_acting_session(p_acting_role, p_group_ids, p_account_ids, p_reason)`: Verified against caller's physical `users_profile` record (`role_level >= 100` or `ohmpayatt@proton.me`), eliminating self-lockout when switching across roles without stopping. Terminates existing active session before inserting new active record in `public.acting_sessions`.
  - `public.stop_acting_session()`: Reverts session by setting `is_active = false, ended_at = now()`.
  - `public.get_web_current_user_context()`: Honors active acting session overlay with 100% Mobile `EffectiveUserContext` parity. Returns acting `role_name`, `role_key`, acting scopes (`group_scope`, `account_scope`), and dynamically evaluates `allowed_module_keys` and `module_capabilities` for the simulated role.
- **Frontend Reactivity & Cache Layer**:
  - `DashboardAuthShell`: Subscribes to TanStack Query cache updates on `["currentUserContext"]`, reactively updating `currentUser`, `Sidebar` user role & visible modules, `AdminTopbar`, and route access guards without requiring manual page reload.
  - `src/lib/rbac.ts`: Evaluates normalized role (`normalizeRole`) first in `getRoleLevel`, `isOwner`, and `hasFullAccess` to prevent email privileges from leaking during lower-role simulation.
  - `src/lib/queries/more.ts`: `useStartActingSession` and `useStopActingSession` comprehensively invalidate `["currentUserContext"]`, `["active-acting-session"]`, and operational data queries (`plantilla`, `vacancies`, `approvals`, `team-directory`, `cencom`).


