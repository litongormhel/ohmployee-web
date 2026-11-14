-- ============================================================================
-- Migration: 20262606000066_wrap_get_my_scoped_vcodes_initplan.sql
-- Prompt ID: ohm#9q5n3wvx
-- Title: Fix 1 - Wrap scope functions in get_my_scoped_vcodes as InitPlans
--
-- Objectives:
--   1. Wrap get_my_allowed_accounts() and get_my_allowed_account_ids() calls
--      inside get_my_scoped_vcodes() into scalar subqueries ((SELECT func())::type[])
--      so PostgreSQL executes them once as InitPlans rather than evaluating
--      them per-row during slot/vacancy/coverage_group scans.
--   2. Preserve all existing predicates (deleted_at, legacy_vcode IS NOT NULL,
--      coverage_code IS NOT NULL, search_path, SECURITY DEFINER, STABLE).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_my_scoped_vcodes()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT ARRAY(
    SELECT DISTINCT vcode FROM (
      SELECT v.vcode
      FROM public.vacancies v
      WHERE v.account = ANY((SELECT public.get_my_allowed_accounts())::text[])
        AND v.deleted_at IS NULL
      UNION
      SELECT ps.legacy_vcode AS vcode
      FROM public.plantilla_slots ps
      WHERE ps.account_id = ANY((SELECT public.get_my_allowed_account_ids())::uuid[])
        AND ps.legacy_vcode IS NOT NULL
      UNION
      SELECT cg.coverage_code AS vcode
      FROM public.coverage_groups cg
      WHERE cg.account_id = ANY((SELECT public.get_my_allowed_account_ids())::uuid[])
        AND cg.coverage_code IS NOT NULL
    ) sub
  );
$function$;
