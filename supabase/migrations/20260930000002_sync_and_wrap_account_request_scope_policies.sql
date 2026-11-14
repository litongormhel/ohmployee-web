-- Sync account_request_account_scopes / account_request_group_scopes RLS policies
-- across environments (staging was missing all 4 — drift, not a design gap) and wrap
-- the bare i_have_full_access() calls in the SELECT policies as part of the InitPlan-wrap
-- effort. no_direct_write policies are qual=false with no function calls — nothing to wrap.
-- Idempotent: safe to run on production (already has these 4, this just re-applies
-- identically) and on staging (currently missing all 4).

DROP POLICY IF EXISTS aras_no_direct_write ON public.account_request_account_scopes;
CREATE POLICY aras_no_direct_write ON public.account_request_account_scopes
FOR ALL
TO authenticated
USING (false);

DROP POLICY IF EXISTS aras_select_admin_only ON public.account_request_account_scopes;
CREATE POLICY aras_select_admin_only ON public.account_request_account_scopes
FOR SELECT
TO authenticated
USING ((select i_have_full_access()));

DROP POLICY IF EXISTS args_no_direct_write ON public.account_request_group_scopes;
CREATE POLICY args_no_direct_write ON public.account_request_group_scopes
FOR ALL
TO authenticated
USING (false);

DROP POLICY IF EXISTS args_select_admin_only ON public.account_request_group_scopes;
CREATE POLICY args_select_admin_only ON public.account_request_group_scopes
FOR SELECT
TO authenticated
USING ((select i_have_full_access()));
