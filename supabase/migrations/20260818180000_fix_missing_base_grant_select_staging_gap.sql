-- ============================================================
-- ohm#6t4wn8vq — Fix missing base GRANT SELECT on staging (42 tables)
-- Migration: 20260818180000_fix_missing_base_grant_select_staging_gap.sql
-- ============================================================
-- Context
-- -------
-- Found during Phase 2 (ohm#5n8wq3vt): tables with RLS enabled and a
-- SELECT policy defined, but no base GRANT SELECT to `authenticated`
-- at the table-privilege level — meaning a real client query hits a
-- 42501 permission-denied error today regardless of what the RLS
-- policy says. The Phase 2 note estimated 9 tables; live re-derivation
-- via has_table_privilege() against pg_class/pg_policies found the
-- real count is 42, not 9 (staging: qqiiznmqxfoamqytjica, re-pulled
-- live per standing instruction — never assume a stale inventory).
--
-- Verified against production (rwxelulyapjgaarlwkus): all 42 tables
-- already have authenticated_has_select = true there. This is a
-- staging-only gap, not a live production defect.
--
-- Root cause
-- ----------
-- pg_default_acl on staging shows two different default-privilege
-- sets on public relations: objects created by `supabase_admin` get
-- full arwdDxtm granted by default to authenticated/anon/service_role;
-- objects created by `postgres` (the role `supabase db push` runs as)
-- get only Dxtm (truncate/references/trigger/maintain) — no
-- select/insert/update/delete — unless the creating migration
-- includes an explicit GRANT statement. All 42 affected tables are
-- owned by `postgres` and their creating migrations omitted the
-- explicit grant; correctly-granted tables (accounts, stores,
-- cencom_weekly_snapshots, etc.) all have it. Every one of the 42
-- tables is also missing the same grant for `service_role` (same
-- default-ACL gap), which would also 42501 any backend/edge-function
-- path using the service-role key against these tables. `anon` is
-- correctly ungranted on all 42 (RLS-gated, not meant to be
-- anon-visible) and is left untouched.
--
-- Fix
-- ---
-- Adds `GRANT SELECT ... TO authenticated;` and `GRANT SELECT ... TO
-- service_role;` for each of the 42 tables, matching the convention
-- used by every correctly-granted table in this schema. This only
-- ADDS access already sanctioned by each table's existing RLS SELECT
-- policy — it does not loosen anything beyond what the policy already
-- allows, and does not touch INSERT/UPDATE/DELETE privileges or any
-- policy definition. Brings staging to exact parity with production's
-- already-correct state. Staging only — production already correct,
-- untouched per instruction.
-- ============================================================

GRANT SELECT ON public.account_group_transfer_request_history TO authenticated;
GRANT SELECT ON public.account_group_transfer_request_history TO service_role;

GRANT SELECT ON public.account_group_transfer_requests TO authenticated;
GRANT SELECT ON public.account_group_transfer_requests TO service_role;

GRANT SELECT ON public.active_user_sessions TO authenticated;
GRANT SELECT ON public.active_user_sessions TO service_role;

GRANT SELECT ON public.applicant_movement_request_history TO authenticated;
GRANT SELECT ON public.applicant_movement_request_history TO service_role;

GRANT SELECT ON public.applicant_movement_requests TO authenticated;
GRANT SELECT ON public.applicant_movement_requests TO service_role;

GRANT SELECT ON public.applicant_movement_reservations TO authenticated;
GRANT SELECT ON public.applicant_movement_reservations TO service_role;

GRANT SELECT ON public.archival_audit_logs TO authenticated;
GRANT SELECT ON public.archival_audit_logs TO service_role;

GRANT SELECT ON public.employee_deactivation_audit_log TO authenticated;
GRANT SELECT ON public.employee_deactivation_audit_log TO service_role;

GRANT SELECT ON public.employee_deactivation_requests TO authenticated;
GRANT SELECT ON public.employee_deactivation_requests TO service_role;

GRANT SELECT ON public.employee_import_batches TO authenticated;
GRANT SELECT ON public.employee_import_batches TO service_role;

GRANT SELECT ON public.employee_import_rows TO authenticated;
GRANT SELECT ON public.employee_import_rows TO service_role;

GRANT SELECT ON public.governance_audit_log TO authenticated;
GRANT SELECT ON public.governance_audit_log TO service_role;

GRANT SELECT ON public.governance_controls TO authenticated;
GRANT SELECT ON public.governance_controls TO service_role;

GRANT SELECT ON public.hr_emploc_import_batches TO authenticated;
GRANT SELECT ON public.hr_emploc_import_batches TO service_role;

GRANT SELECT ON public.hr_emploc_import_rows TO authenticated;
GRANT SELECT ON public.hr_emploc_import_rows TO service_role;

GRANT SELECT ON public.module_visibility_override_audit TO authenticated;
GRANT SELECT ON public.module_visibility_override_audit TO service_role;

GRANT SELECT ON public.module_visibility_overrides TO authenticated;
GRANT SELECT ON public.module_visibility_overrides TO service_role;

GRANT SELECT ON public.notification_push_dispatches TO authenticated;
GRANT SELECT ON public.notification_push_dispatches TO service_role;

GRANT SELECT ON public.permission_drift_evidence TO authenticated;
GRANT SELECT ON public.permission_drift_evidence TO service_role;

GRANT SELECT ON public.permission_drift_findings TO authenticated;
GRANT SELECT ON public.permission_drift_findings TO service_role;

GRANT SELECT ON public.permission_drift_scan_runs TO authenticated;
GRANT SELECT ON public.permission_drift_scan_runs TO service_role;

GRANT SELECT ON public.plantilla_import_batches TO authenticated;
GRANT SELECT ON public.plantilla_import_batches TO service_role;

GRANT SELECT ON public.plantilla_import_commit_snapshots TO authenticated;
GRANT SELECT ON public.plantilla_import_commit_snapshots TO service_role;

GRANT SELECT ON public.plantilla_import_incidents TO authenticated;
GRANT SELECT ON public.plantilla_import_incidents TO service_role;

GRANT SELECT ON public.plantilla_import_notifications TO authenticated;
GRANT SELECT ON public.plantilla_import_notifications TO service_role;

GRANT SELECT ON public.plantilla_import_rows TO authenticated;
GRANT SELECT ON public.plantilla_import_rows TO service_role;

GRANT SELECT ON public.push_device_tokens TO authenticated;
GRANT SELECT ON public.push_device_tokens TO service_role;

GRANT SELECT ON public.rbac_drift_scan_evidence TO authenticated;
GRANT SELECT ON public.rbac_drift_scan_evidence TO service_role;

GRANT SELECT ON public.rbac_drift_scan_results TO authenticated;
GRANT SELECT ON public.rbac_drift_scan_results TO service_role;

GRANT SELECT ON public.rbac_drift_scan_runs TO authenticated;
GRANT SELECT ON public.rbac_drift_scan_runs TO service_role;

GRANT SELECT ON public.rbac_drift_scanner_definitions TO authenticated;
GRANT SELECT ON public.rbac_drift_scanner_definitions TO service_role;

GRANT SELECT ON public.role_permission_audit_logs TO authenticated;
GRANT SELECT ON public.role_permission_audit_logs TO service_role;

GRANT SELECT ON public.role_permission_definitions TO authenticated;
GRANT SELECT ON public.role_permission_definitions TO service_role;

GRANT SELECT ON public.role_permission_matrix TO authenticated;
GRANT SELECT ON public.role_permission_matrix TO service_role;

GRANT SELECT ON public.role_permission_overrides TO authenticated;
GRANT SELECT ON public.role_permission_overrides TO service_role;

GRANT SELECT ON public.security_audit_logs TO authenticated;
GRANT SELECT ON public.security_audit_logs TO service_role;

GRANT SELECT ON public.slot_reason_codes TO authenticated;
GRANT SELECT ON public.slot_reason_codes TO service_role;

GRANT SELECT ON public.system_archive_batches TO authenticated;
GRANT SELECT ON public.system_archive_batches TO service_role;

GRANT SELECT ON public.user_settings TO authenticated;
GRANT SELECT ON public.user_settings TO service_role;

GRANT SELECT ON public.vacancy_edit_lock_audit TO authenticated;
GRANT SELECT ON public.vacancy_edit_lock_audit TO service_role;

GRANT SELECT ON public.vacancy_import_batches TO authenticated;
GRANT SELECT ON public.vacancy_import_batches TO service_role;

GRANT SELECT ON public.vacancy_import_rows TO authenticated;
GRANT SELECT ON public.vacancy_import_rows TO service_role;
