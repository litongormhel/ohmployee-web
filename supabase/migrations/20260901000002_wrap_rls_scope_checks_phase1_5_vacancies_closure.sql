-- Phase 1.5: wrap remaining bare scope-check calls on vacancies (3 policies Phase 1 missed
-- because they don't exist on staging under identical names) and vacancy_closure_requests
-- (untouched by Phase 1/2). Same (select ...) InitPlan-caching pattern as Phase 1/2.
-- All wrapped functions confirmed STABLE via pg_proc.provolatile before this migration.

-- vacancies_hide_deleted: RESTRICTIVE, SELECT, authenticated — preserve AS RESTRICTIVE
DROP POLICY IF EXISTS vacancies_hide_deleted ON public.vacancies;
CREATE POLICY vacancies_hide_deleted ON public.vacancies
AS RESTRICTIVE
FOR SELECT
TO authenticated
USING ((deleted_at IS NULL) OR (select i_have_full_access()));

-- vacancies_read_hired_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS vacancies_read_hired_scoped ON public.vacancies;
CREATE POLICY vacancies_read_hired_scoped ON public.vacancies
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (
    (account = ANY ((select get_my_allowed_accounts())::text[]))
    AND (status = 'Filled'::text)
    AND (deleted_at IS NULL)
  )
);

-- vacancies_read_scoped: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS vacancies_read_scoped ON public.vacancies;
CREATE POLICY vacancies_read_scoped ON public.vacancies
FOR SELECT
TO public
USING (
  (select i_have_full_access())
  OR (
    (account = ANY ((select get_my_allowed_accounts())::text[]))
    AND (status <> ALL (ARRAY['Filled'::text, 'Closed'::text, 'Archived'::text]))
    AND (COALESCE(is_archived, false) = false)
    AND ((NOT COALESCE(is_pool_vacancy, false)) OR (COALESCE(is_ops_request, false) = true))
  )
  OR (
    (COALESCE(is_pool_vacancy, false) = true)
    AND (
      ((select get_my_role_level()) = 20)
      OR ((select get_my_role_level()) = 30)
      OR ((select get_my_role_level()) >= 90)
    )
  )
);

-- vacancy_closure_req_read_scoped: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS vacancy_closure_req_read_scoped ON public.vacancy_closure_requests;
CREATE POLICY vacancy_closure_req_read_scoped ON public.vacancy_closure_requests
FOR SELECT
TO public
USING (
  (select i_have_full_access())
  OR (requested_by = (select get_my_full_name()))
  OR (requested_by_user_id = (select get_my_profile_id()))
  OR (
    vacancy_vcode IN (
      SELECT v.vcode FROM vacancies v
      WHERE (v.account = ANY ((select get_my_allowed_accounts())::text[]))
    )
  )
);
