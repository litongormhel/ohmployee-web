-- ============================================================
-- OHMployee - Restore fn_is_active_vacancy_applicant_status
-- Prompt ID : OHM2026_RESTORE_APPLICANT_STATUS_HELPER
-- Date      : 2026-05-26
-- Scope     : Restore missing helper so supabase db pull succeeds
-- ============================================================
-- Root cause: uq_applicants_one_active_per_vcode partial index
-- references this function, which was missing from the remote DB,
-- causing supabase db pull to fail with:
--   ERROR: function public.fn_is_active_vacancy_applicant_status(text)
--          does not exist
-- This migration is additive — it only (re)creates the function.
-- Active statuses match OHM2026_2019 canonical definition.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_is_active_vacancy_applicant_status(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT replace(lower(btrim(COALESCE(p_status, ''))), ' ', '_') IN (
    'new',
    'for_interview',
    'for_requirements',
    'for_onboard'
  );
$$;

COMMENT ON FUNCTION public.fn_is_active_vacancy_applicant_status(text) IS
  'OHM2026_2019 - Canonical Vacancy slot occupancy predicate. '
  'Only New, For Interview, For Requirements, and For Onboard, '
  'including lowercase/snake_case equivalents, are active. '
  'Restored by OHM2026_RESTORE_APPLICANT_STATUS_HELPER to fix schema pull.';

GRANT EXECUTE ON FUNCTION public.fn_is_active_vacancy_applicant_status(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_is_active_vacancy_applicant_status(text) TO service_role;
