-- Migration: 20262606000078_super_admin_plantilla_employee_rls.sql
-- Description: Ensure authenticated users with the "Super Admin" role have full SELECT access to plantilla and employees tables

-- 1. Ensure RLS is active on both tables
ALTER TABLE public.plantilla ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2. PLANTILLA TABLE: Dedicated Super Admin Full SELECT Policy
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "plantilla_super_admin_select" ON public.plantilla;

CREATE POLICY "plantilla_super_admin_select"
ON public.plantilla
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
  -- Check 1: Canonical roles table lookup via users_profile
  EXISTS (
    SELECT 1
    FROM public.users_profile up
    LEFT JOIN public.roles r ON r.id = up.role_id
    WHERE up.auth_user_id = auth.uid()
      AND COALESCE(up.is_active, true) = true
      AND up.archived_at IS NULL
      AND (
        r.role_name = 'Super Admin'
        OR up.role = 'Super Admin'
        OR COALESCE(r.role_level, 0) >= 100
      )
  )
  -- Check 2: System level helper function
  OR public.i_have_full_access()
  -- Check 3: Custom JWT claims / Supabase app_metadata fallback
  OR (COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') ILIKE '%super%admin%')
  OR (COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', '') ILIKE '%super%admin%')
  OR (auth.jwt() ->> 'role' = 'service_role')
);

-- ----------------------------------------------------------------------------
-- 3. EMPLOYEES TABLE: Dedicated Super Admin Full SELECT Policy
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "employees_super_admin_select" ON public.employees;

CREATE POLICY "employees_super_admin_select"
ON public.employees
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
  -- Check 1: Canonical roles table lookup via users_profile
  EXISTS (
    SELECT 1
    FROM public.users_profile up
    LEFT JOIN public.roles r ON r.id = up.role_id
    WHERE up.auth_user_id = auth.uid()
      AND COALESCE(up.is_active, true) = true
      AND up.archived_at IS NULL
      AND (
        r.role_name = 'Super Admin'
        OR up.role = 'Super Admin'
        OR COALESCE(r.role_level, 0) >= 100
      )
  )
  -- Check 2: System level helper function
  OR public.i_have_full_access()
  -- Check 3: Custom JWT claims / Supabase app_metadata fallback
  OR (COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') ILIKE '%super%admin%')
  OR (COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', '') ILIKE '%super%admin%')
  OR (auth.jwt() ->> 'role' = 'service_role')
);
