-- ============================================================================
-- Migration: 20262606000183_grant_allowed_account_ids_to_public.sql
-- Description:
--   Grants EXECUTE on public.get_my_allowed_account_ids() and
--   public.get_my_scoped_accounts() to PUBLIC to align with get_my_allowed_accounts().
-- ============================================================================

BEGIN;

GRANT EXECUTE ON FUNCTION public.get_my_allowed_account_ids() TO PUBLIC, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_scoped_accounts() TO PUBLIC, authenticated, service_role;

COMMIT;
