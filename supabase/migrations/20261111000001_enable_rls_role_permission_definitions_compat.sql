-- ═══════════════════════════════════════════════════════════════════════════
-- Migration: 20261111000001_enable_rls_role_permission_definitions_compat.sql
-- Description: Enable RLS and restrict permissions on role_permission_definitions_compat
--              Fixes Supabase Security Advisor finding: rls_disabled_in_public
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' 
      AND table_name = 'role_permission_definitions_compat'
  ) THEN
    -- 1. Enable Row Level Security
    ALTER TABLE public.role_permission_definitions_compat ENABLE ROW LEVEL SECURITY;

    -- 2. Revoke all public / anonymous access
    REVOKE ALL ON TABLE public.role_permission_definitions_compat FROM anon;
    REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.role_permission_definitions_compat FROM authenticated;

    -- 3. Create read-only policy for authenticated sessions
    DROP POLICY IF EXISTS rpd_compat_read_authenticated ON public.role_permission_definitions_compat;
    CREATE POLICY rpd_compat_read_authenticated
      ON public.role_permission_definitions_compat
      FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;
