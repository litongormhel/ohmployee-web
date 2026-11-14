-- Migration: 20260810000002_fix_v_workforce_pool_employees_grant
-- Created: 2026-08-10
-- Purpose: Restore the `authenticated` SELECT grant on v_workforce_pool_employees
--          that was lost when ohm#9x2k7m4q (20262606000036) replaced the view,
--          causing Bundler Pool / Workforce Pool screens to fail on staging with
--          PostgrestException 42501 "permission denied for view
--          v_workforce_pool_employees". Confirmed via pg_catalog on staging that
--          only postgres retained SELECT after the CREATE OR REPLACE VIEW; the
--          original grant came from 20262306000000_grant_authenticated_select_all_views.sql
--          (authenticated only, no anon) and was never reissued by 20262606000036.
--          Grants-only fix — the view's SELECT logic/join from ohm#9x2k7m4q is untouched.
--
-- Smoke Tests:
-- S1: SELECT grantee, privilege_type FROM information_schema.role_table_grants
--     WHERE table_schema='public' AND table_name='v_workforce_pool_employees'
--     AND grantee='authenticated' AND privilege_type='SELECT'; -- expect 1 row
-- S2: Bundler Pool / Workforce Pool screen loads pool data without 42501 error.

BEGIN;

GRANT SELECT ON public.v_workforce_pool_employees TO authenticated;

COMMIT;
