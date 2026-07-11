-- Migration: 20260606000000_web_vacancy_detail_rpc.sql
-- Ticket: OHM2026_1083 - Web Vacancy detail read-only RPC
--
-- Purpose:
--   Safe, read-only OHMployee Web presentation contract for Vacancy detail drawer.
--   This RPC reuses the Mobile vacancy detail view and existing role/scope semantics
--   for display only.
--
-- Security invariants:
--   - Caller identity is derived only from auth.uid().
--   - No user/profile/scope arguments are accepted.
--   - Scope is derived from users_profile + user_scopes.
--   - HR Personnel and unknown/inactive/archived users fail closed.
--   - Sensitive employee/Plantilla fields and applicant PII (names, contact info) are not returned.
--   - Row capabilities are UI hints only; RLS/action RPCs remain authority.
--   - Execution is granted only to authenticated.
--

DROP FUNCTION IF EXISTS public.get_web_vacancy_detail(uuid);

CREATE OR REPLACE FUNCTION public.get_web_vacancy_detail(p_vacancy_id uuid)
RETURNS TABLE (
  vacancy_id                  uuid,
  vcode                       text,
  position_title              text,
  employment_type             text,
  vacancy_type                text,
  
  account_id                  uuid,
  account_name                text,
  group_id                    uuid,
  group_name                  text,
  store_id                    uuid,
  store_name                  text,
  store_branch                text,
  area_name                   text,
  area_city                   text,
  province                    text,
  
  vacancy_status              text,
  pipeline_status             text,
  
  vacant_date                 date,
  target_fill_date            date,
  aging_days                  integer,
  aging_bucket                text,
  
  urgency                     text,
  penalty_exposure            numeric,
  
  hrco_name                   text,
  recruiter_name              text,
  requester_name              text,
  triggered_by_name           text,
  
  pipeline_summary            jsonb,
  activity_history            jsonb,
  row_capabilities            jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_is_active    boolean;
  v_in_scope     boolean := false;
BEGIN
  -- 1. Authentication Check
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Fetch User Profile and Role Context
  SELECT up.id, r.role_name, r.role_level, up.is_active
  INTO v_profile_id, v_role_name, v_role_level, v_is_active
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  -- 3. Fail closed if unauthenticated, inactive, missing profile, or unauthorized role
  IF v_profile_id IS NULL OR NOT coalesce(v_is_active, FALSE) OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- 4. Scope and Vacancy Existence Check
  -- Check if the vacancy exists and is within the user's scope.
  -- If v_role_level >= 90 (Super Admin / Head Admin), they have global access to all non-deleted vacancies.
  -- If v_role_level < 90, the vacancy must not be archived/deleted, must not have terminal statuses (Filled, Closed, Archived),
  -- and must match the caller's allowed accounts or user scopes.
  SELECT EXISTS (
    SELECT 1
    FROM public.vw_vacancy_detail vd
    WHERE vd.id = p_vacancy_id
      AND (
        v_role_level >= 90
        OR (
          coalesce(vd.is_archived, false) = false
          AND vd.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
          AND (
            vd.account = ANY (public.get_my_allowed_accounts())
            OR EXISTS (
              SELECT 1
              FROM public.user_scopes us
              WHERE us.user_id = v_profile_id
                AND us.account_id = vd.account_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.user_scopes us
              JOIN public.accounts a ON a.id = vd.account_id
              WHERE us.user_id = v_profile_id
                AND us.account_id IS NULL
                AND us.group_id = a.group_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.users_profile up_fallback
              JOIN public.accounts a ON a.id = vd.account_id
              WHERE up_fallback.id = v_profile_id
                AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_scopes us_any
                  WHERE us_any.user_id = v_profile_id
                    AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
                )
                AND (
                  up_fallback.account_id = vd.account_id
                  OR up_fallback.group_id = a.group_id
                )
            )
          )
        )
      )
  ) INTO v_in_scope;

  IF NOT v_in_scope THEN
    RAISE EXCEPTION 'forbidden: vacancy is out of scope or does not exist'
      USING ERRCODE = '42501';
  END IF;

  -- 5. Return the detail record
  RETURN QUERY
  SELECT
    vd.id AS vacancy_id,
    vd.vcode,
    vd.position AS position_title,
    vd.employment_type,
    vd.vacancy_type,
    
    vd.account_id,
    vd.account AS account_name,
    vd.group_id,
    vd.group_name,
    vd.store_id,
    vd.store_name,
    vd.store_branch,
    vd.area_name,
    vd.area_city,
    vd.province,
    
    vd.status AS vacancy_status,
    vd.derived_status AS pipeline_status,
    
    vd.vacant_date,
    vd.target_fill_date,
    vd.aging_days::integer AS aging_days,
    CASE
      WHEN vd.aging_days IS NULL THEN 'unknown'
      WHEN vd.aging_days <= 7 THEN '0_7'
      WHEN vd.aging_days <= 14 THEN '8_14'
      WHEN vd.aging_days <= 30 THEN '15_30'
      ELSE '31_plus'
    END AS aging_bucket,
    
    vd.urgency_level AS urgency,
    CASE
      WHEN coalesce(v_raw.has_penalty, false)
        THEN coalesce(v_raw.penalty_amount, 0::numeric)
      ELSE 0::numeric
    END AS penalty_exposure,
    
    vd.hrco_name,
    up_rec.full_name AS recruiter_name,
    coalesce(up_req.full_name, vd.hc_request_requested_by) AS requester_name,
    vd.triggered_by_full_name AS triggered_by_name,
    
    -- 6. Aggregated applicant/pipeline summary strictly without PII
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'applicant_id', a.id,
            'status', a.status,
            'source_channel', a.source_channel,
            'created_at', a.created_at,
            'updated_at', a.updated_at
          ) ORDER BY a.created_at DESC
        )
        FROM public.applicants a
        WHERE a.vacancy_vcode = vd.vcode
          AND COALESCE(a.is_archived, false) = false
      ),
      '[]'::jsonb
    ) AS pipeline_summary,
    
    -- 7. Activity/history placeholder
    '[]'::jsonb AS activity_history,
    
    -- 8. Row/Action capabilities (UI Hints only)
    jsonb_build_object(
      'can_view_detail', true,
      'can_request_closure_hint',
        coalesce(v_role_level, 0) >= 30
        AND coalesce(vd.is_archived, false) = false
        AND vd.status <> ALL (ARRAY['Filled', 'Closed', 'Archived']),
      'authority', 'rls_action_rpcs'
    ) AS row_capabilities
    
  FROM public.vw_vacancy_detail vd
  JOIN public.vacancies v_raw ON v_raw.id = vd.id
  LEFT JOIN public.users_profile up_rec ON up_rec.id = vd.assigned_encoder_id
  LEFT JOIN public.users_profile up_req ON up_req.id = vd.requested_by_user_id
  WHERE vd.id = p_vacancy_id;

END;
$$;

COMMENT ON FUNCTION public.get_web_vacancy_detail(uuid) IS
  'OHM2026_1083 - Web presentation detail contract only. Returns single scoped Vacancy details from vw_vacancy_detail. RLS/action RPCs remain authority.';

REVOKE ALL ON FUNCTION public.get_web_vacancy_detail(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_vacancy_detail(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_vacancy_detail(uuid) TO authenticated;
