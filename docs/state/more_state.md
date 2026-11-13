# More & Settings Module State

## Overview
This document captures the current stable architecture and navigation contract for `/settings` and `/more`.

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
     - `permission_matrix`: Role permission overrides (Super Admin).
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
       - `mika_import`: Mika import (`import=mika`). Uploads MIKA biometric / attendance sheets with cross-check detection against active Plantilla (clean, ghost employee isolation, blocked account mismatch). Cross-check queries valid Plantilla columns (`status`, `is_deleted`, `deactivated_at`, `store_name`, `account`) and active roving allocations from `employee_store_allocations`, validating against official active accounts (public.accounts) and the employee's assigned account in public.plantilla; any unlisted account or mismatch against Plantilla is strictly flagged as locked (Mismatch), prohibiting store or retail chain names (e.g. SUPER 8) from being imported as accounts. Ingestion maps spreadsheet `dateHired` to PostgreSQL column `date_hired` in `public.mika_import_rows` in 100-row chunks, automatically cleans up orphaned header logs upon ingestion failure, and propagates API error details cleanly to the review banner. Import History table features clickable rows that open a detailed rows preview `<Modal>` displaying uploaded records, an `Uploaded Rows` count column, and 15-item `TablePagination`. Approving a pending batch in the Review Queue automatically propagates matched employee rows and statutory data to `public.plantilla`.
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

