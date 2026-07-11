-- Migration: 20260702000004_fix_unscoped_insert_rls_policies
-- Created: 2026-07-02
-- Purpose: Close the unscoped WITH CHECK (true) INSERT policies on notifications,
--          sla_breach_logs, and applicant_status_history (RLS audit
--          docs/audit/rls_audit_2026-07-02.md, Finding 1 — High). All three tables
--          are written exclusively by SECURITY DEFINER functions owned by
--          `postgres` (rolbypassrls = true), verified live on staging: notify_user,
--          fn_notify_role, create_workforce_notification, check_plantilla_sla_breaches,
--          check_sla_breach, handle_sla_breach_check, fn_update_applicant_status.
--          These bypass RLS as owner regardless of policy, so direct authenticated/
--          public INSERT access is replaced with a service_role-only policy.
--          SELECT/UPDATE/DELETE policies are untouched.
--
-- Smoke Tests:
-- S1: As an authenticated non-service role, attempt a direct INSERT into
--     notifications / sla_breach_logs / applicant_status_history — must be rejected
--     by RLS (no matching policy for that role).
-- S2: Call public.notify_user(...) (or another SECURITY DEFINER writer) as an
--     authenticated user — the underlying INSERT must still succeed (function
--     bypasses RLS as owner postgres), confirming no regression to legitimate
--     notification/audit-trail writes.

BEGIN;

-- notifications: remove unscoped "to public" INSERT, restrict to service_role
DROP POLICY IF EXISTS "notif_insert_system" ON public.notifications;

CREATE POLICY "notif_insert_service_role"
  ON public.notifications
  AS PERMISSIVE
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- sla_breach_logs: remove unscoped "to public" INSERT, restrict to service_role
DROP POLICY IF EXISTS "sla_breach_insert_service" ON public.sla_breach_logs;

CREATE POLICY "sla_breach_insert_service_role"
  ON public.sla_breach_logs
  AS PERMISSIVE
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- applicant_status_history: remove unscoped "to authenticated" INSERT, restrict to service_role
DROP POLICY IF EXISTS "ash_insert_authenticated" ON public.applicant_status_history;

CREATE POLICY "ash_insert_service_role"
  ON public.applicant_status_history
  AS PERMISSIVE
  FOR INSERT
  TO service_role
  WITH CHECK (true);

COMMIT;
