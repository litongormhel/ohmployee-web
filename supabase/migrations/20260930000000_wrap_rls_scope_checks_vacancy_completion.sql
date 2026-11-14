-- RLS InitPlan wrap — Vacancy module completion (ohm#7n3wk8qm).
-- Wraps bare scope-check function calls as (select fn()) so Postgres caches one
-- evaluation per query instead of re-evaluating per row. Same category as Phase 1/2
-- (ohm#3xk7m2wq / ohm#5n8wq3vt) but covers functions never in scope before:
-- get_my_role_level, i_am_ops, get_my_full_name, get_my_profile_id.
-- All wrapped functions confirmed STABLE via pg_proc.provolatile before this migration.
-- Text/logic identical to the live bare policies except for the wrap — verified via
-- rolled-back-transaction row-count+md5 fingerprint A/B across Head Admin/OM/HRCO on
-- staging (24/24 combinations byte-identical) before this file was authored.
--
-- Deviations found vs. this prompt's original policy-name list (live pg_policies is
-- authoritative, per the mandated methodology):
--  - "vacancies_write_scoped" does not exist on staging. The live SELECT policy with a
--    bare in-scope call is "vacancies_select_secure" (has a bare get_my_role_level()) —
--    wrapped that instead. Its i_am_assigned_to_vacancy(id) call is out of scope (not
--    an audited function, takes an argument) and is left bare.
--  - "vreq_insert_ops_scoped" does not exist; live policy is "vreq_insert_ops_or_encoder".
--    Its i_am_encoder() call is out of scope (not in the audited function list, not
--    STABLE-verified this session) and is left bare.

-- vacancies_select_secure: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS vacancies_select_secure ON public.vacancies;
CREATE POLICY vacancies_select_secure ON public.vacancies
FOR SELECT
TO authenticated
USING (
  ((deleted_at IS NULL) OR (select i_have_full_access()))
  AND (
    (select i_have_full_access())
    OR (account_id = ANY ((select get_my_allowed_account_ids())::uuid[]))
    OR i_am_assigned_to_vacancy(id)
    OR ((select get_my_role_level()) = ANY (ARRAY[100, 90, 30]))
  )
);

-- closure_req_insert_ops_scoped: PERMISSIVE, INSERT, public
DROP POLICY IF EXISTS closure_req_insert_ops_scoped ON public.vacancy_closure_requests;
CREATE POLICY closure_req_insert_ops_scoped ON public.vacancy_closure_requests
FOR INSERT
TO public
WITH CHECK (
  (select i_have_full_access())
  OR (
    (select i_am_ops())
    AND (vacancy_vcode IN (
      SELECT vacancies.vcode FROM vacancies
      WHERE (vacancies.account = ANY ((select get_my_allowed_accounts())::text[]))
    ))
  )
);

-- closure_req_update_encoder_plus: PERMISSIVE, UPDATE, public
DROP POLICY IF EXISTS closure_req_update_encoder_plus ON public.vacancy_closure_requests;
CREATE POLICY closure_req_update_encoder_plus ON public.vacancy_closure_requests
FOR UPDATE
TO public
USING (
  (select i_have_full_access())
  OR (
    ((select get_my_role_level()) = 30)
    AND (vacancy_vcode IN (
      SELECT v.vcode FROM vacancies v
      WHERE (v.account = ANY ((select get_my_allowed_accounts())::text[]))
    ))
  )
);

-- closure_reasons_write_admin: PERMISSIVE, ALL, authenticated
DROP POLICY IF EXISTS closure_reasons_write_admin ON public.vacancy_closure_reasons;
CREATE POLICY closure_reasons_write_admin ON public.vacancy_closure_reasons
FOR ALL
TO authenticated
USING ((select i_have_full_access()));

-- vacancy_coverage_insert: PERMISSIVE, INSERT, authenticated
DROP POLICY IF EXISTS vacancy_coverage_insert ON public.vacancy_coverage;
CREATE POLICY vacancy_coverage_insert ON public.vacancy_coverage
FOR INSERT
TO authenticated
WITH CHECK (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- vacancy_coverage_select: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS vacancy_coverage_select ON public.vacancy_coverage;
CREATE POLICY vacancy_coverage_select ON public.vacancy_coverage
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- vacancy_coverage_update: PERMISSIVE, UPDATE, authenticated
DROP POLICY IF EXISTS vacancy_coverage_update ON public.vacancy_coverage;
CREATE POLICY vacancy_coverage_update ON public.vacancy_coverage
FOR UPDATE
TO authenticated
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
)
WITH CHECK (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
);

-- vreq_insert_ops_or_encoder: PERMISSIVE, INSERT, authenticated (i_am_encoder() left bare — out of scope)
DROP POLICY IF EXISTS vreq_insert_ops_or_encoder ON public.vacancy_requests;
CREATE POLICY vreq_insert_ops_or_encoder ON public.vacancy_requests
FOR INSERT
TO authenticated
WITH CHECK (
  (select i_have_full_access())
  OR (
    ((select i_am_ops()) OR i_am_encoder())
    AND (account = ANY ((select get_my_allowed_accounts())::text[]))
  )
);

-- vreq_select_scoped: PERMISSIVE, SELECT, public
DROP POLICY IF EXISTS vreq_select_scoped ON public.vacancy_requests;
CREATE POLICY vreq_select_scoped ON public.vacancy_requests
FOR SELECT
TO public
USING (
  (select i_have_full_access())
  OR (account = ANY ((select get_my_allowed_accounts())::text[]))
  OR (requested_by = (select get_my_full_name()))
);

-- vcodes_read_scoped: PERMISSIVE, SELECT, authenticated
DROP POLICY IF EXISTS vcodes_read_scoped ON public.vcodes;
CREATE POLICY vcodes_read_scoped ON public.vcodes
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (account_code = ANY ((select get_my_allowed_accounts())::text[]))
);

-- vcodes_write_admin: PERMISSIVE, ALL, authenticated
DROP POLICY IF EXISTS vcodes_write_admin ON public.vcodes;
CREATE POLICY vcodes_write_admin ON public.vcodes
FOR ALL
TO authenticated
USING ((select i_have_full_access()))
WITH CHECK ((select i_have_full_access()));

-- hc_request_stores_select: PERMISSIVE, SELECT, authenticated (get_current_profile_id() left bare — out of scope)
DROP POLICY IF EXISTS hc_request_stores_select ON public.hc_request_stores;
CREATE POLICY hc_request_stores_select ON public.hc_request_stores
FOR SELECT
TO authenticated
USING (
  (select i_have_full_access())
  OR (EXISTS (
    SELECT 1 FROM headcount_requests hr
    WHERE (hr.id = hc_request_stores.request_id)
      AND (hr.requested_by_user_id = get_current_profile_id())
  ))
);

-- hcreq_insert_ops_scoped: PERMISSIVE, INSERT, public (i_have_full_access/get_my_allowed_accounts already wrapped by Phase 2; only i_am_ops was bare)
DROP POLICY IF EXISTS hcreq_insert_ops_scoped ON public.headcount_requests;
CREATE POLICY hcreq_insert_ops_scoped ON public.headcount_requests
FOR INSERT
TO public
WITH CHECK (
  (select i_have_full_access())
  OR (
    (select i_am_ops())
    AND (account_name_snapshot = ANY ((select get_my_allowed_accounts())::text[]))
  )
);
