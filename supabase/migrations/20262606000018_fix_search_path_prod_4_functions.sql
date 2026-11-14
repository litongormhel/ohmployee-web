-- Migration: 20262606000018_fix_search_path_prod_4_functions
-- Created: 2026-08-03
-- Purpose: Port the search_path hardening from migration 20260703000001 to the
--          4 SECURITY DEFINER functions confirmed still unhardened on Production
--          (docs/audit/prod_staging_parity_2026-08-03.md, finding #3):
--          i_am_encoder, i_am_recruitment, i_am_super_admin, on_auth_user_password_changed.
--
--          Prod's schema_migrations shows 20260703000001 as "applied" (verified via
--          direct query), but live pg_get_functiondef() comparison against Staging
--          confirms the search_path SET clause was never executed on Prod's function
--          bodies (proconfig was NULL on all 4) -- same falsified-history pattern
--          previously found and fixed for fn_get_hired_applicants (ohm#a36isorp).
--
--          Function bodies were compared byte-for-byte (aside from the search_path
--          clause itself) between Prod and Staging before authoring this migration --
--          no logic, ownership, or grant differences exist. This is a search_path
--          fix only, ported verbatim from 20260703000001's existing pattern.
--
-- Smoke Tests:
-- S1: For i_am_encoder / i_am_recruitment / i_am_super_admin, call as a known test
--     authenticated user of each role and confirm the returned boolean is unchanged
--     from pre-migration (SELECT get_my_role() = '<role>' logic untouched).
-- S2: Trigger a password change on a test auth user and confirm
--     on_auth_user_password_changed still inserts the CHANGE_PASSWORD audit_logs row
--     identically to before, and still swallows exceptions (no lockout on error).
-- S3: pg_proc.proconfig now contains 'search_path=public, pg_temp' for all 4
--     functions listed below (verified via the same ground-truth query used in
--     the audit and in migration 20260703000001).

BEGIN;

ALTER FUNCTION public.i_am_encoder() SET search_path = public, pg_temp;
ALTER FUNCTION public.i_am_recruitment() SET search_path = public, pg_temp;
ALTER FUNCTION public.i_am_super_admin() SET search_path = public, pg_temp;
ALTER FUNCTION public.on_auth_user_password_changed() SET search_path = public, pg_temp;

COMMIT;
