-- ohm#8m4w1q6n (2026-08-10)
-- Fix: Encoder (role_level 30) cannot SELECT their own auto-created
-- Workforce Pool vacancy rows on `vacancies` — RLS blocked because
-- vacancies_select_secure only grants unconditional read via
-- i_have_full_access() (role_level >= 90, SA/HA only), and Encoder's
-- fallback `account_id = ANY(get_my_allowed_account_ids())` fails when
-- the encoder has no user_scopes row for the Moses HQ pool account
-- (the account create_pool_vacancy always writes for Data Team-created
-- pool vacancies). Sibling tables (workforce_pool_requests,
-- workforce_pool_request_items, workforce_pool_slots) already carry an
-- explicit Data Team carve-out (`get_my_role_level() = ANY(ARRAY[100,90,30])`)
-- — `vacancies` was missing the equivalent. Investigated in ohm#3n7q9wxk.
--
-- Additive OR clause only — no existing grant narrowed or removed.
-- hasFullAccess (SA/HA) behavior is unchanged; OM/HRCO/ATL/TL/Recruitment
-- scoping via get_my_allowed_account_ids()/i_am_assigned_to_vacancy is
-- unchanged.

DROP POLICY IF EXISTS vacancies_select_secure ON public.vacancies;

CREATE POLICY vacancies_select_secure ON public.vacancies
FOR SELECT
TO authenticated
USING (
  ((deleted_at IS NULL) OR i_have_full_access())
  AND (
    i_have_full_access()
    OR (account_id = ANY (get_my_allowed_account_ids()))
    OR i_am_assigned_to_vacancy(id)
    OR get_my_role_level() = ANY (ARRAY[100, 90, 30])
  )
);
