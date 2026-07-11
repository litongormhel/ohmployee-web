-- Migration: 20260703000001_fix_search_path_critical_security_definer_functions
-- Created: 2026-07-03
-- Purpose: Fix missing search_path on the 31 CRITICAL SECURITY DEFINER functions
--          flagged in docs/audit/security_definer_audit_2026-07-03.md (prosecdef=true,
--          no fixed search_path in proconfig — classic search-path-hijack vector).
--          Search-path fix only: no function logic, ownership, or grant changes in this pass.
--          Every function body was inspected via pg_get_functiondef; all unqualified
--          object references resolve within the `public` schema (auth.uid() calls are
--          already schema-qualified in the source), so `public, pg_temp` is correct and
--          sufficient for all 31 — no ambiguous cross-schema dependency was found.
--
-- Smoke Tests:
-- S1: For the 4 RBAC gate functions (i_am_super_admin, is_super_admin,
--     get_current_profile_id, can_manage_target_user), call as a known test
--     authenticated user and confirm the returned value is unchanged from pre-migration.
-- S2: For prevent_audit_log_modification / trg_enforce_user_hierarchy, confirm
--     UPDATE/DELETE on audit_logs is still blocked and role-hierarchy writes on
--     users_profile are still enforced identically to before.
-- S3: pg_proc.proconfig now contains 'search_path=public, pg_temp' for all 31
--     functions listed below (verified via the same ground-truth query used in
--     the audit).

BEGIN;

-- ── Priority 1: Core RBAC gate functions ────────────────────────────────────
ALTER FUNCTION public.i_am_super_admin() SET search_path = public, pg_temp;
ALTER FUNCTION public.is_super_admin() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_current_profile_id() SET search_path = public, pg_temp;
ALTER FUNCTION public.can_manage_target_user(uuid) SET search_path = public, pg_temp;

-- ── Priority 2: Integrity triggers ───────────────────────────────────────────
ALTER FUNCTION public.prevent_audit_log_modification() SET search_path = public, pg_temp;
ALTER FUNCTION public.trg_enforce_user_hierarchy() SET search_path = public, pg_temp;

-- ── Priority 3: Remaining 25 CRITICAL functions ──────────────────────────────
ALTER FUNCTION public.archive_vacancy_on_closure_approval() SET search_path = public, pg_temp;
ALTER FUNCTION public.check_ghost_encoding_deadlines() SET search_path = public, pg_temp;
ALTER FUNCTION public.generate_vcodes_for_request(uuid, text, text, integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.generate_vcodes_from_request(uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_hr_emploc_filter_counts(text) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_my_profile_id() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_target_role_level(uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_team_performance(text, uuid, uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_team_performance_summary(text, uuid, uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_unread_notification_count() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_user_drilldown(uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_ghost_encoding_assigned() SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_vacancy_request_approved() SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_vacancy_request_submitted() SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_vcode_created_notify_requestor() SET search_path = public, pg_temp;
ALTER FUNCTION public.i_am_encoder() SET search_path = public, pg_temp;
ALTER FUNCTION public.i_am_ops() SET search_path = public, pg_temp;
ALTER FUNCTION public.i_am_recruitment() SET search_path = public, pg_temp;
ALTER FUNCTION public.i_can_act_on_plantilla() SET search_path = public, pg_temp;
ALTER FUNCTION public.i_can_view_plantilla() SET search_path = public, pg_temp;
ALTER FUNCTION public.log_users_profile_changes() SET search_path = public, pg_temp;
ALTER FUNCTION public.on_auth_user_password_changed() SET search_path = public, pg_temp;
ALTER FUNCTION public.record_login_session(text, text) SET search_path = public, pg_temp;
ALTER FUNCTION public.trg_account_deactivation_cascade() SET search_path = public, pg_temp;
ALTER FUNCTION public.trg_prevent_duplicate_closure_request() SET search_path = public, pg_temp;

COMMIT;
