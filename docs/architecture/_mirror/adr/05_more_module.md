<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-More. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/05_more_module.md
source_commit: 0eb4407 2026-11-23T23:02:59+08:00
source_sha256: 8663e0da06e5db8ce96f34ae8fb90987a7be1e4df59b71d33d427b754be9a2bc
synced_at: 2026-11-23T15:03:08.223Z
-->
# More Module Architecture (Operations Hub & Administrative Governance)

- **Status:** ACCEPTED & LOCKED
- **Scope:** Five Operational Tabs (Overview, Data Control, Permissions, Audit, Admin Tools), 5 Canonical Batch Imports with 72h Rollback, QA Simulation Sandbox, Role Impersonation, Permission Matrix Overrides, and MIKA Biometric Ghost Detection.

---

## More Module (Operations Hub & Administrative Governance)

Rule 1 and Rule 6 compliance: More Module's bulk archival and payroll-adjacent RPCs (`fn_archive_*`, `fn_qa_*`, `fn_rollback_archive_batch`) are the explicit, justified direct-writer carve-out named in Rule 1 above — bulk archival is not a lifecycle transition, so these functions may write `plantilla_slots.slot_status` directly rather than through `fn_set_slot_status`. They must still never write to a denormalized counter column (`hc_filled` etc.) per Rule 6 — only to the primary domain tables the archive operation targets.

### Five Operational Tabs Architecture (Operations Hub)

**Status: ACCEPTED.** Codifies the standard administrative surfaces and role-scoped hubs in Operations Hub (`/more`) across Web and Mobile:

1. **Tab 1: Overview** (`tab=overview`):
   - Fast operational dashboard and direct shortcuts: `User Management` (Head Admin), `Account Requests` (Head Admin), `Team Directory`, `Account Settings`, and `Sign Out`.
   - **OM Payroll Shortcut Invariant**: Operations Managers (OM) do not have access to the `data_control` tab; the `Payroll Review Center` shortcut is surfaced in Overview exclusively for OM. For Head Admin, Encoder, and Super Admin, the review hub is canonically accessed under `data_control`.
2. **Tab 2: Data Control** (`tab=data_control`, Head Admin 70, Encoder 30, Super Admin 100):
   - **Operations Sub-tab** (`subtab=operations`):
     - `ghost_detection`: Ghost Employees Detection Center (Type A / Type B dual anomaly classification, 7-day SLA, two-tier triage).
     - `payroll_review_center`: Payroll Review Center (canonical payroll review hub).
     - `roving_coverage_groups`: Roving coverage groups pool & 5-action coverage modal (Create, Add Store, Remove Store, Merge, Dissolve).
     - `global_store_transfer`: Cross-account and regional store reassignment governance.
     - `edit_lock_control`: Edit Lock security and field mutation freezes.
     - `data_archival_control`: Data Archival & Recovery Center (Super Admin Level 100 canonical single entry point).
   - **Batch Imports Sub-tab** (`subtab=batch_imports`): Canonical hub for spreadsheet batch ingestions.
3. **Tab 3: Permissions** (`tab=permissions`, Head Admin & Super Admin):
   - `permission_matrix`: Role permission overrides with interactive Allow/Deny toggles, per-row Reset to Default, and toolbar Reset All to Default (`get_effective_permission_matrix`, `apply_permission_overrides`, `reset_permission_overrides`).
   - `temp_permission`: Temporary Group Access overrides with expiring time-based grants.
   - `access_control_center`, `role_permissions`, and `permission_drift` mismatch detector.
4. **Tab 4: Audit** (`tab=audit`, Super Admin Level 100):
   - `audit_logs`: Detailed system audit activity trail rendered with human-readable operational summaries (`audit_formatter.ts`), entity badges (person name, VCode, outlet), and clean scalar field diffs. Locked down via `v_audit_activity_feed` (`role_level >= 90`).
   - `security_events`: Security alerts, unauthorized mutation flags, and threat indicators.
   - `allocation_health`: Workforce Integrity checks.
5. **Tab 5: Admin Tools** (`tab=admin_tools`, Super Admin Level 100):
   - `switch_role`: Role impersonation and acting sessions (`start_acting_session`, `stop_acting_session`).
   - `qa_center`: QA Simulation Engine (`qa_run_scenario`) with atomic subtransaction rollback and zero live table pollution.
   - `system_diagnostics`: System health probes, freeze diagnostics, and PostgREST schema cache reload utility (`NOTIFY pgrst, 'reload schema';`).
   - `ohms_safespace`: Emergency lockdown and system-wide killswitch.

### Canonical Batch Imports Architecture & 72-Hour Rollback Governance

**Status: ACCEPTED.** Governs spreadsheet batch ingestion across Web and Mobile:

1. **Full-Page URL Architecture**:
   - All 5 batch imports are rendered as full-page URL-driven views via `BatchImportPageShell` rather than modals: `/more?tab=data_control&subtab=batch_imports&import=<plantilla|hr_emploc|vacancy|mika|payroll>`.
   - Preserves browser history, provides unclipped horizontal scrolling for wide tabular previews, and pins sticky footer confirmation controls.
2. **The Five Canonical Batch Ingestion Engines**:
   - `plantilla`: Baseline and slot-first plantilla import (strictly governed by ADR-002; identity coalescing, 18+ age validation, schedule matrix validation).
   - `hr_emploc`: HR Emploc candidates bulk import (slot-first lifecycle, initial status `'Pending Emploc'`).
   - `vacancy`: Batch vacancy requirements and store openings import.
   - `mika`: Weekly biometric attendance and ghost employee detection ingestion.
   - `payroll`: Read-only payroll reconciliation checker with sticky review center handover.
3. **Standard 72-Hour Operational Rollback Window**:
   - Head Admin (70) and Super Admin (100) are authorized to execute batch rollbacks within **72 hours** of batch approval.
   - Requires mandatory operational justification (`rollback_reason`), transitions batch status to `'Rolled Back'`, unlinks/cleanses created domain records, restores slot statuses via `fn_set_slot_status`, and records immutable entries in `public.audit_logs`.

### QA Simulation Engine & Atomic Sandbox Isolation

**Status: ACCEPTED.** Codifies automated end-to-end multi-role testing in production and staging:

1. **Atomic Subtransaction Rollback (`public.qa_run_scenario`)**:
   - The simulation engine executes sequential operational workflows within an atomic PL/pgSQL block (`BEGIN ... EXCEPTION ... END`).
   - Forces controlled rollback via `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`, guaranteeing **100% zero live table pollution** across `vacancies`, `plantilla`, `applicants`, `hr_emploc`, and `users_profile`.
2. **Multi-Role Relay (`FULL_E2E_RELAY`)**:
   - Executes a 7-step cross-role relay: Head Admin (Quota) $\rightarrow$ Encoder (Slot) $\rightarrow$ Recruitment (Candidate) $\rightarrow$ HRCO (Onboard) $\rightarrow$ HR Personnel (Emploc ID) $\rightarrow$ Back Office (Movement) $\rightarrow$ Back Office Negative Security Barrier (asserting unauthorized mutations fail).
3. **Dual GUC Impersonation & Telemetry Persistence**:
   - Sets both `request.jwt.claim.sub` and `request.jwt.claims` for authentic role authorization testing, with defensive restoration of original claims.
   - Run telemetry and defect findings are persisted outside the rolled-back subtransaction in `public.qa_agent_runs` and `public.qa_agent_findings`.

### Role Impersonation & Acting Sessions Governance

**Status: ACCEPTED.** Governs runtime role simulation for debugging and operational auditing:

1. **Authority Gate (`public.start_acting_session`)**:
   - Strictly restricted to physical `role_level >= 100` (Super Admin) or system owner (`ohmpayatt@proton.me`).
   - Terminates any existing active acting session before initializing a new session in `public.acting_sessions`.
2. **Dynamic Context Overlay (`public.get_web_current_user_context()`)**:
   - Re-evaluates `allowed_module_keys` and `module_capabilities` to match the simulated role (e.g. simulating HRCO locks out Admin Tools and scopes data to assigned accounts).
   - **Email Privilege Containment**: Normalized role checks evaluate before physical email privileges in `getRoleLevel` and `hasFullAccess`, preventing super-admin bypasses from leaking during lower-role simulation.
3. **Clean Session Teardown (`public.stop_acting_session`)**:
   - Restores the caller's native context and comprehensively invalidates client query caches (`["currentUserContext"]`, `["active-acting-session"]`).

### Permission Matrix Overrides & Bulk Reset Contract

**Status: ACCEPTED.** Governs dynamic role capabilities and safety recovery:

1. **Granular Overrides (`public.apply_permission_overrides`)**:
   - Super Admin may configure per-role, per-module Allow/Deny capabilities (`role_permission_overrides`).
2. **Safety Recovery & Bulk Reset (`public.reset_permission_overrides`)**:
   - Supports both single-action "Reset to Default" and a toolbar "Reset All to Default" with confirmation modal.
   - Purges custom overrides and immediately restores baseline code-defined role capabilities across Web and Mobile.

### Audit Activity Feed Lockdown & Human-Readable Logging

**Status: ACCEPTED.** Protects corporate audit confidentiality and optimizes operational visibility:

1. **Database Access Lockdown**:
   - Base table `public.audit_logs` and view `public.v_audit_activity_feed` are restricted strictly to `role_level >= 90` (Head Admin and Super Admin) with `security_invoker = true`. Revoked from `authenticated` and `anon`.
2. **Human-Readable Entity Formatting (`audit_formatter.ts`)**:
   - Replaces raw JSON dumps and database UUIDs with contextual operational summaries, entity badges (Person name, VCode, Store branch), and clean scalar field diffs (`Field: Old Value → New Value`).

### MIKA Biometric Import & Ghost Employees Detection Center (`ohm#g8h4m2v9` — 2026-11-15)

**Status: ACCEPTED.** Codifies the architecture for MIKA biometric ingestion, anomaly classification, and the Operations Hub Ghost Employees Detection Center.

**Problem.** Weekly MIKA biometric attendance uploads audit employee presence in stores. Flagged discrepancies risk payroll fraud or untracked personnel, but without a unified cross-platform detection center, recurring weekly uploads either duplicate cases, lose tracking history, or leave separated personnel undetected.

**Architecture Decisions & Invariants (binding):**

1. **Dual Anomaly Classification (Strict Separation):**
   - **Type A (Unregistered / Missing from Plantilla):** Biometric record exists in MIKA with an Employee Number not found in active `public.plantilla`. Requires encoding or investigation.
   - **Type B (Inactive / Separated Anomaly):** Biometric record exists in MIKA, but matches an employee tagged as `Inactive`, `Separated`, `Deactivated`, or `Resigned` in `public.plantilla`. High-severity payroll leakage / immediate biometric revocation alert.

2. **Weekly Upload Case Continuity & SLA Age Preservation:**
   - A single continuous investigation case exists per employee in `public.possible_ghost_employees` while unresolved (`status NOT IN ('Cleared', 'Resolved', 'Auto Resolved', 'Confirmed Ghost', 'For Termination')`).
   - Subsequent weekly uploads of the same unresolved employee must NOT spawn duplicate rows; they update `last_revalidated_at = now()`, increment the revalidation count, and associate the latest `import_log_id`.
   - The initial detection timestamp (`created_at`) is permanently preserved to enforce the **1-week (7-day) SLA**:
     - *< 48 hours:* Normal Investigation (`Under Investigation`).
     - *48–72 hours:* Head Admin escalation notification.
     - *72 hours – 7 days:* Super Admin escalation notification.
     - *> 7 days (1 week):* Automatic **"Breached SLA (>7 Days)"** critical operational lock.

3. **Strict Plantilla Invariant & Two-Tier Triage Permissions:**
   - Pre-deployment onboarding status (e.g. HR Emploc pipeline) remains classified under strict investigation until the employee physically attains `status = 'Active'` in `public.plantilla`.
   - The database trigger `trg_ghost_resolve_on_plantilla_active` automatically transitions Type A cases to `'Cleared'` (`auto_resolved = true`, `resolved_at = now()`, `resolution_remarks = 'Auto-resolved: Found in Active Plantilla'`).
   - **Two-Tier Triage Permissions:**
     - *Field Ops (HRCO, TL, ATL):* Scoped to their allowed accounts (`account = ANY(get_my_allowed_accounts())`). May inspect cases and submit audited **Operational Verification Notes** (e.g., confirming store presence or unrecorded separation).
     - *Data Team & Admin (Encoder 30, HA 70, SA 90):* Authorized to execute formal status mutations: Assign to Encoder (72h deadline), Mark Cleared (audited reason), or Confirm Ghost / Payroll Freeze.

4. **Coalesced Statutory Benefits Hydration:**
   - Weekly MIKA import strictly prioritizes biometric attendance cross-checking and ghost detection.
   - Government statutory numbers (SSS, PhilHealth, Pag-IBIG, TIN, ATM) only coalesce into blank/null fields in `public.plantilla` upon batch approval without overwriting existing verified data.

5. **Approval-Triggered Targeted Notifications & Deep-Link Invariants:**
   - When a MIKA import batch is approved (`mika_import_logs.status = 'Approved'`) with detected ghost cases, notifications fire automatically:
     - *Operations Manager (60), Head Admin (70), Super Admin (90):* Global notification: `"{count} possible ghost employees flagged across all accounts. View here"` → links to `/more?tab=data_control&subtab=operations&tool=ghost_detection`.
     - *HRCO (40), TL (50), ATL (55), Encoder (30):* Account-targeted notification: `"{count} possible ghost employees flagged in {account}. Verify here"` → links to `/more?tab=data_control&subtab=operations&tool=ghost_detection&account={account}`.
   - Operations Hub surface contract: Located at `/more?tab=data_control&subtab=operations&tool=ghost_detection`, with deep links from CENCOM and Executive Dashboard anomaly alerts (`"Resolve Anomalies →"`).

6. **MIKA Rollback Governance & Ghost Invalidation:**
   - Head Admin (70) and Super Admin (90) can execute batch rollbacks within a 72-hour operational window if an erroneous or corrupt MIKA file was approved.
   - Sets `mika_import_logs.status = 'Rolled Back'`, records `rolled_back_by`, `rolled_back_at`, and mandatory `rollback_reason`.
   - Automatically cancels all open ghost employee cases generated by that batch (`public.possible_ghost_employees.status = 'Cleared'`, `resolution_remarks = 'Import Batch Rolled Back: ' || reason`), preventing false SLA alerts.
   - Audited via `public.audit_logs` with action `'MIKA_IMPORT_ROLLBACK'`.

---
