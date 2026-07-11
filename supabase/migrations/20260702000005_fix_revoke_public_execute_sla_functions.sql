-- Migration: 20260702000005_fix_revoke_public_execute_sla_functions
-- Created: 2026-07-02
-- Purpose: Revoke PUBLIC EXECUTE on check_plantilla_sla_breaches() and check_sla_breach() and restrict to service_role only — these are system SLA scan functions that must never be directly RPC-callable by anon/authenticated clients.
--
-- Smoke Tests:
-- S1: SELECT check_plantilla_sla_breaches(); as authenticated role -> expect permission denied (42501)
-- S2: SELECT check_plantilla_sla_breaches(); as service_role -> expect successful jsonb result

BEGIN;

REVOKE EXECUTE ON FUNCTION public.check_plantilla_sla_breaches() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_plantilla_sla_breaches() FROM anon;
REVOKE EXECUTE ON FUNCTION public.check_plantilla_sla_breaches() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_plantilla_sla_breaches() TO service_role;

REVOKE EXECUTE ON FUNCTION public.check_sla_breach() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_sla_breach() FROM anon;
REVOKE EXECUTE ON FUNCTION public.check_sla_breach() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_sla_breach() TO service_role;

COMMIT;
