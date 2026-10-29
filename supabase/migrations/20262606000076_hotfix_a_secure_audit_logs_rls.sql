-- Migration: 20262606000076_hotfix_a_secure_audit_logs_rls.sql
-- Purpose: Hotfix A - Secure audit_logs RLS and close v_audit_activity_feed backdoor
-- 1. Restrict audit_logs_select policy strictly to Super Admin and Head Admin (role_level >= 90).
-- 2. Revoke permissions and set security_invoker on v_audit_activity_feed to eliminate RLS bypass.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tighten audit_logs_select policy on public.audit_logs
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "audit_logs_select" ON public.audit_logs;
DROP POLICY IF EXISTS "pol_audit_admin_read" ON public.audit_logs;

CREATE POLICY "audit_logs_select"
ON public.audit_logs
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.auth_user_id = auth.uid()
      AND up.is_active = TRUE
      AND up.archived_at IS NULL
      AND (r.role_level >= 90 OR public.i_have_full_access())
  )
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Close v_audit_activity_feed RLS bypass
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'v_audit_activity_feed'
  ) THEN
    -- Enforce security_invoker so view respects underlying table RLS
    ALTER VIEW public.v_audit_activity_feed SET (security_invoker = true);
    
    -- Revoke SELECT from public, anon, and authenticated
    REVOKE ALL ON public.v_audit_activity_feed FROM PUBLIC, anon, authenticated;
  END IF;
END $$;
