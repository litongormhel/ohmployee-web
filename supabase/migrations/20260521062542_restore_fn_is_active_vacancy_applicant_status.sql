-- Pre-schema shim: ensure helper exists before remote_schema.sql
-- uq_applicants_one_active_per_vcode (created in 20260521062543) depends on this function.

CREATE OR REPLACE FUNCTION public.fn_is_active_vacancy_applicant_status(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT replace(lower(btrim(coalesce(p_status, ''))), ' ', '_') IN (
    'new',
    'for_interview',
    'for_requirements',
    'for_onboard'
  );
$$;

REVOKE ALL ON FUNCTION public.fn_is_active_vacancy_applicant_status(text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_is_active_vacancy_applicant_status(text)
TO authenticated, service_role;
