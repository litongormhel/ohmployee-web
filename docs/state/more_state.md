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
     - `audit_logs`: Detailed system audit activity trail rendered with human-readable operational summaries (`audit_formatter.ts`), entity badges (person name, VCode, outlet), actor context, and meaningful field diffs with optional raw JSON.
  5. `data_control` (Head Admin & Encoder):
     - Sub-tab `operations`:
       - `edit_lock_control`: Edit Lock Control (Security).
       - `data_archival_control`: Data Archival & Recovery (Canonical single entry point; Level 100 / Super Admin).
       - `global_store_transfer`: Global Store Transfer requests.
       - `roving_coverage_groups`: Roving coverage group pools.
       - `payroll_review_center`: Payroll Review Center (Canonical review hub).
     - Sub-tab `batch_imports`:
       - `hr_emploc_import`: HR Emploc XLSX bulk import.
       - `plantilla_import`: Plantilla batch import.
       - `vacancy_import`: Vacancy batch import.
       - `mika_import`: Mika import.
       - `payroll_import`: Payroll reconciliation import.

## Data Archival & Recovery Consolidation
- Canonical entry point is strictly located in **More > Data Control > Operations & Governance > "Data Archival & Recovery"** (Level 100).
- Duplicate entry points in Admin Tools ("Data Archival Center") and Audit & Integrity ("Data Archival & Recovery") have been retired.
- Opens `DataArchivalCenterModal` allowing Super Admins to inspect soft-deleted plantilla and vacancy records and perform restorations with audited justification logging.
