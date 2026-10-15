-- Migration: 20261014193500_fix_vacancy_closure_lifecycle_and_tab_filtering.sql
-- Ticket: ohm#w63v754b - Fix Vacancy Remaining in Open Tab After Store / Vacancy Closure Request
--
-- Purpose:
--   1. Update vw_vacancy_list derived_status to include 'For Closure' when:
--      has_pending_closure = true OR closure_request_status = 'Pending' OR status IN ('closure', 'for_closure')
--      OR referenced by a pending vacancy_closure_request.
--   2. Update list_web_vacancies and get_web_vacancy_summary to strictly exclude vacancies with active
--      in-flight closure requests from the 'Open' and 'Pipeline' queues, while including them in the 'Closure' queue.
--   3. Ensure rpc_submit_vacancy_closure_request and handle_closure_requested update vacancies state
--      (has_pending_closure = true, closure_request_status = 'Pending', updated_at = NOW()).
--   4. Ensure handle_closure_approval resets has_pending_closure and closure_request_status appropriately on review.

-- 1. Update vw_vacancy_list
CREATE OR REPLACE VIEW public.vw_vacancy_list AS
 WITH applicant_stats AS (
         SELECT a.vacancy_vcode,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND (a.status <> ALL (ARRAY['Failed'::text, 'Backout'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Confirmed Onboard'::text]))) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text AND COALESCE(a.hired_visible_until, a.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
           FROM applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    v.store_name,
    v.store_id,
    v.area_name,
    v.area_city,
    v.province,
    v.store_branch,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
        CASE
            WHEN v.is_archived = true OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text])) THEN 'Archived'::text
            WHEN v.status = 'Filled'::text THEN 'Hired'::text
            WHEN COALESCE(v.has_pending_closure, false) = true
                 OR LOWER(COALESCE(v.closure_request_status, '')) = 'pending'
                 OR LOWER(COALESCE(v.status, '')) IN ('closure', 'for_closure')
                 OR EXISTS (
                   SELECT 1 FROM public.vacancy_closure_requests vcr
                   WHERE vcr.vacancy_vcode = v.vcode AND LOWER(vcr.status) = 'pending'
                 ) THEN 'For Closure'::text
            WHEN COALESCE(s.active_applicant_count, 0::bigint) > 0 THEN 'Pipeline'::text
            ELSE 'Open'::text
        END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    CURRENT_DATE - v.vacant_date AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, 0::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, 0::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    v.group_id,
    g.group_name,
    v.hrco_user_id,
        CASE
            WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name
            ELSE NULL::text
        END AS hrco_name,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire
   FROM vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN groups g ON g.id = v.group_id
     LEFT JOIN users_profile up_hrco ON up_hrco.id = v.hrco_user_id
     LEFT JOIN roles r_hrco ON r_hrco.id = up_hrco.role_id
  WHERE v.deleted_at IS NULL;

GRANT ALL ON public.vw_vacancy_list TO authenticated, postgres, service_role;

-- 2. Update list_web_vacancies
CREATE OR REPLACE FUNCTION public.list_web_vacancies(
  p_status        text    DEFAULT NULL,
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_position      text    DEFAULT NULL,
  p_urgency       text    DEFAULT NULL,
  p_aging_bucket  text    DEFAULT NULL,
  p_search        text    DEFAULT NULL,
  p_vacant_from   date    DEFAULT NULL,
  p_vacant_to     date    DEFAULT NULL,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'vacant_date',
  p_sort_dir      text    DEFAULT 'desc'
)
RETURNS TABLE (
  vacancy_id        uuid,
  vcode             text,
  account_id        uuid,
  account_name      text,
  group_id          uuid,
  group_name        text,
  store_id          uuid,
  store_name        text,
  position_title    text,
  employment_type   text,
  vacancy_status    text,
  pipeline_status   text,
  vacant_date       date,
  aging_days        integer,
  aging_bucket      text,
  target_fill_date  date,
  urgency           text,
  penalty_exposure  numeric,
  hrco_name         text,
  row_capabilities  jsonb,
  total_count       bigint
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
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'vacant_date'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'vcode',
    'account_name',
    'group_name',
    'store_name',
    'position_title',
    'vacancy_status',
    'pipeline_status',
    'vacant_date',
    'aging_days',
    'target_fill_date',
    'urgency'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by
      USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      vl.id AS vacancy_id,
      vl.vcode,
      vl.account_id,
      vl.account AS account_name,
      vl.group_id,
      vl.group_name,
      vl.store_id,
      vl.store_name,
      vl.position AS position_title,
      vl.employment_type,
      vl.status AS vacancy_status,
      vl.derived_status AS pipeline_status,
      coalesce(vl.has_pending_closure, v_raw.has_pending_closure, false) AS has_pending_closure,
      coalesce(vl.closure_request_status, v_raw.closure_request_status) AS closure_request_status,
      vl.vacant_date,
      vl.aging_days::integer AS aging_days,
      CASE
        WHEN vl.aging_days IS NULL THEN 'unknown'
        WHEN vl.aging_days <= 7 THEN '0_7'
        WHEN vl.aging_days <= 14 THEN '8_14'
        WHEN vl.aging_days <= 30 THEN '15_30'
        ELSE '31_plus'
      END AS aging_bucket,
      vl.target_fill_date,
      vl.urgency_level AS urgency,
      CASE
        WHEN coalesce(v_raw.has_penalty, false)
          THEN coalesce(v_raw.penalty_amount, 0::numeric)
        ELSE 0::numeric
      END AS penalty_exposure,
      vl.hrco_name,
      jsonb_build_object(
        'can_view_detail', true,
        'can_request_closure_hint',
          coalesce(v_role_level, 0) >= 30
          AND coalesce(vl.is_archived, false) = false
          AND coalesce(vl.has_pending_closure, v_raw.has_pending_closure, false) = false
          AND coalesce(vl.closure_request_status, v_raw.closure_request_status, '') <> 'Pending'
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived', 'closure', 'for_closure']),
        'authority', 'rls_action_rpcs'
      ) AS row_capabilities
    FROM public.vw_vacancy_list vl
    JOIN public.vacancies v_raw ON v_raw.id = vl.id
    WHERE
      coalesce(vl.is_archived, false) = false
      AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
      AND (
        coalesce(v_role_level, 0) >= 90
        OR (
          vl.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = v_profile_id
              AND us.account_id = vl.account_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            JOIN public.accounts a ON a.id = vl.account_id
            WHERE us.user_id = v_profile_id
              AND us.account_id IS NULL
              AND us.group_id = a.group_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.users_profile up_fallback
            JOIN public.accounts a ON a.id = vl.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (
                SELECT 1
                FROM public.user_scopes us_any
                WHERE us_any.user_id = v_profile_id
                  AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
              )
              AND (
                up_fallback.account_id = vl.account_id
                OR up_fallback.group_id = a.group_id
              )
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (
        p_status IS NULL
        OR CASE
             WHEN lower(btrim(p_status)) = 'open' THEN 
               lower(s.pipeline_status) = 'open'
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure')
             WHEN lower(btrim(p_status)) = 'pipeline' THEN 
               lower(s.pipeline_status) = 'pipeline'
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure')
             WHEN lower(btrim(p_status)) IN ('closure', 'for_closure', 'closed') THEN
               lower(s.pipeline_status) IN ('closure', 'for closure')
               OR s.has_pending_closure = true
               OR lower(coalesce(s.closure_request_status, '')) = 'pending'
               OR lower(coalesce(s.vacancy_status, '')) IN ('closure', 'for_closure')
             ELSE (lower(s.vacancy_status) = lower(btrim(p_status)) OR lower(s.pipeline_status) = lower(btrim(p_status)))
           END
      )
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_position IS NULL OR lower(s.position_title) = lower(btrim(p_position)))
      AND (p_urgency IS NULL OR lower(coalesce(s.urgency, '')) = lower(btrim(p_urgency)))
      AND (p_aging_bucket IS NULL OR s.aging_bucket = lower(btrim(p_aging_bucket)))
      AND (p_vacant_from IS NULL OR s.vacant_date >= p_vacant_from)
      AND (p_vacant_to IS NULL OR s.vacant_date <= p_vacant_to)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.group_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.store_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.vacancy_id,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.employment_type,
    c.vacancy_status,
    c.pipeline_status,
    c.vacant_date,
    c.aging_days,
    c.aging_bucket,
    c.target_fill_date,
    c.urgency,
    c.penalty_exposure,
    c.hrco_name,
    c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title'   THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title'   THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vacancy_status'   THEN c.vacancy_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vacancy_status'   THEN c.vacancy_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'pipeline_status'  THEN c.pipeline_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'pipeline_status'  THEN c.pipeline_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vacant_date'      THEN c.vacant_date END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vacant_date'      THEN c.vacant_date END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'target_fill_date' THEN c.target_fill_date END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'target_fill_date' THEN c.target_fill_date END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'urgency'          THEN c.urgency END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'urgency'          THEN c.urgency END DESC NULLS LAST,
    c.vcode ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

-- 3. Update get_web_vacancy_summary
CREATE OR REPLACE FUNCTION public.get_web_vacancy_summary(
  p_status        text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL,
  p_position      text DEFAULT NULL,
  p_urgency       text DEFAULT NULL,
  p_search        text DEFAULT NULL,
  p_vacant_from   date DEFAULT NULL,
  p_vacant_to     date DEFAULT NULL
)
RETURNS TABLE (
  total_open        bigint,
  with_applicant    bigint,
  rejected          bigint,
  backout           bigint,
  aging_0_7         bigint,
  aging_8_14        bigint,
  aging_15_30       bigint,
  aging_31_plus     bigint,
  aging_unknown     bigint,
  critical_urgency  bigint,
  high_urgency      bigint
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
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy summary requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      vl.id AS vacancy_id,
      vl.vcode,
      vl.account_id,
      vl.account AS account_name,
      vl.group_id,
      vl.group_name,
      vl.store_name,
      vl.position AS position_title,
      vl.status AS vacancy_status,
      vl.derived_status AS pipeline_status,
      coalesce(vl.has_pending_closure, v_raw.has_pending_closure, false) AS has_pending_closure,
      coalesce(vl.closure_request_status, v_raw.closure_request_status) AS closure_request_status,
      vl.vacant_date,
      vl.aging_days::integer AS aging_days,
      CASE
        WHEN vl.aging_days IS NULL THEN 'unknown'
        WHEN vl.aging_days <= 7 THEN '0_7'
        WHEN vl.aging_days <= 14 THEN '8_14'
        WHEN vl.aging_days <= 30 THEN '15_30'
        ELSE '31_plus'
      END AS aging_bucket,
      vl.urgency_level AS urgency,
      vl.active_applicant_count
    FROM public.vw_vacancy_list vl
    JOIN public.vacancies v_raw ON v_raw.id = vl.id
    WHERE
      coalesce(vl.is_archived, false) = false
      AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
      AND (
        coalesce(v_role_level, 0) >= 90
        OR (
          vl.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = v_profile_id
              AND us.account_id = vl.account_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            JOIN public.accounts a ON a.id = vl.account_id
            WHERE us.user_id = v_profile_id
              AND us.account_id IS NULL
              AND us.group_id = a.group_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.users_profile up_fallback
            JOIN public.accounts a ON a.id = vl.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (
                SELECT 1
                FROM public.user_scopes us_any
                WHERE us_any.user_id = v_profile_id
                  AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
              )
              AND (
                up_fallback.account_id = vl.account_id
                OR up_fallback.group_id = a.group_id
              )
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (
        p_status IS NULL
        OR CASE
             WHEN lower(btrim(p_status)) = 'open' THEN 
               lower(s.pipeline_status) = 'open'
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure')
             WHEN lower(btrim(p_status)) = 'pipeline' THEN 
               lower(s.pipeline_status) = 'pipeline'
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure')
             WHEN lower(btrim(p_status)) IN ('closure', 'for_closure', 'closed') THEN
               lower(s.pipeline_status) IN ('closure', 'for closure')
               OR s.has_pending_closure = true
               OR lower(coalesce(s.closure_request_status, '')) = 'pending'
               OR lower(coalesce(s.vacancy_status, '')) IN ('closure', 'for_closure')
             ELSE (lower(s.vacancy_status) = lower(btrim(p_status)) OR lower(s.pipeline_status) = lower(btrim(p_status)))
           END
      )
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_position IS NULL OR lower(s.position_title) = lower(btrim(p_position)))
      AND (p_urgency IS NULL OR lower(coalesce(s.urgency, '')) = lower(btrim(p_urgency)))
      AND (p_vacant_from IS NULL OR s.vacant_date >= p_vacant_from)
      AND (p_vacant_to IS NULL OR s.vacant_date <= p_vacant_to)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.group_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.store_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  applicant_rollup AS (
    SELECT
      f.vacancy_id,
      count(a.id) FILTER (
        WHERE COALESCE(a.is_archived, false) = false
          AND replace(lower(btrim(coalesce(a.status, ''))), ' ', '_') IN ('rejected', 'rejected_by_ops')
      ) AS rejected_count,
      count(a.id) FILTER (
        WHERE COALESCE(a.is_archived, false) = false
          AND replace(lower(btrim(coalesce(a.status, ''))), ' ', '_') IN ('backout', 'failed', 'did_not_report')
      ) AS backout_count
    FROM filtered f
    LEFT JOIN public.applicants a ON a.vacancy_vcode = f.vcode
    GROUP BY f.vacancy_id
  )
  SELECT
    count(*) FILTER (
      WHERE f.pipeline_status = 'Open'
        AND f.has_pending_closure = false
        AND lower(coalesce(f.closure_request_status, '')) <> 'pending'
        AND lower(coalesce(f.vacancy_status, '')) NOT IN ('closure', 'for_closure')
    )::bigint AS total_open,
    count(*) FILTER (
      WHERE f.pipeline_status = 'Pipeline'
        AND f.has_pending_closure = false
        AND lower(coalesce(f.closure_request_status, '')) <> 'pending'
        AND lower(coalesce(f.vacancy_status, '')) NOT IN ('closure', 'for_closure')
    )::bigint AS with_applicant,
    count(*) FILTER (WHERE coalesce(ar.rejected_count, 0) > 0)::bigint AS rejected,
    count(*) FILTER (WHERE coalesce(ar.backout_count, 0) > 0)::bigint AS backout,
    count(*) FILTER (WHERE f.aging_bucket = '0_7')::bigint AS aging_0_7,
    count(*) FILTER (WHERE f.aging_bucket = '8_14')::bigint AS aging_8_14,
    count(*) FILTER (WHERE f.aging_bucket = '15_30')::bigint AS aging_15_30,
    count(*) FILTER (WHERE f.aging_bucket = '31_plus')::bigint AS aging_31_plus,
    count(*) FILTER (WHERE f.aging_bucket = 'unknown')::bigint AS aging_unknown,
    count(*) FILTER (WHERE lower(coalesce(f.urgency, '')) = 'critical')::bigint AS critical_urgency,
    count(*) FILTER (WHERE lower(coalesce(f.urgency, '')) = 'high')::bigint AS high_urgency
  FROM filtered f
  LEFT JOIN applicant_rollup ar ON ar.vacancy_id = f.vacancy_id;
END;
$$;

-- 4. Update rpc_submit_vacancy_closure_request
CREATE OR REPLACE FUNCTION public.rpc_submit_vacancy_closure_request(
  p_vacancy_vcode text, 
  p_reason text, 
  p_details text DEFAULT NULL::text, 
  p_requested_by text DEFAULT NULL::text, 
  p_requested_by_role text DEFAULT 'Ops'::text, 
  p_requested_by_user_id uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_request_id uuid;
BEGIN
  IF nullif(trim(p_vacancy_vcode), '') IS NULL THEN
    RAISE EXCEPTION 'Vacancy vcode is required';
  END IF;

  IF nullif(trim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Closure reason is required';
  END IF;

  -- T0004: fulfillment guard (Layer 1)
  PERFORM public.fn_assert_vacancy_closeable(p_vacancy_vcode);

  IF EXISTS (
    SELECT 1 FROM public.vacancy_closure_requests
    WHERE vacancy_vcode = p_vacancy_vcode
      AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'Pending closure request already exists';
  END IF;

  INSERT INTO public.vacancy_closure_requests (
    vacancy_vcode,
    reason,
    details,
    requested_by,
    requested_by_user_id,
    status,
    encoder_decision
  )
  VALUES (
    p_vacancy_vcode,
    trim(p_reason),
    nullif(trim(p_details), ''),
    COALESCE(nullif(trim(p_requested_by), ''), nullif(trim(p_requested_by_role), ''), 'Ops'),
    p_requested_by_user_id,
    'Pending',
    'Pending'
  )
  RETURNING id INTO v_request_id;

  -- Explicitly update vacancy state & set pending clearance flag
  UPDATE public.vacancies
  SET has_pending_closure = true,
      closure_request_status = 'Pending',
      updated_at = NOW()
  WHERE vcode = p_vacancy_vcode;

  RETURN v_request_id;
END;
$function$;

-- 5. Update handle_closure_requested trigger function
CREATE OR REPLACE FUNCTION public.handle_closure_requested()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_vacancy RECORD;
  v_encoder RECORD;
BEGIN
  UPDATE public.vacancies
  SET has_pending_closure = true,
      closure_request_status = 'Pending',
      updated_at = NOW()
  WHERE vcode = NEW.vacancy_vcode;

  SELECT v.id AS vacancy_id,
         COALESCE(a.account_name, v.account) AS account_name,
         COALESCE(a.group_id, v.group_id) AS group_id
  INTO v_vacancy
  FROM public.vacancies v
  LEFT JOIN public.accounts a ON a.id = v.account_id
  WHERE v.vcode = NEW.vacancy_vcode
  LIMIT 1;

  SELECT up.auth_user_id, up.role
  INTO v_encoder
  FROM public.users_profile up
  WHERE up.role = 'Encoder'
    AND up.is_active = true
    AND up.auth_user_id IS NOT NULL
    AND up.group_id = v_vacancy.group_id
  LIMIT 1;

  IF v_encoder.auth_user_id IS NOT NULL THEN
    PERFORM public.notify_user(
      v_encoder.auth_user_id,
      'Encoder',
      'Vacancy Closure Request — ' || COALESCE(v_vacancy.account_name, 'Account'),
      COALESCE(NEW.requested_by, 'Ops') || ' has requested to close vacancy ' || NEW.vacancy_vcode || ' for ' || COALESCE(v_vacancy.account_name, 'the account') || '. Please review.',
      'submission',
      'vacancy_closure',
      'vacancy_closure',
      NEW.id::TEXT,
      FORMAT('/vacancies/%s/closure-request/%s', COALESCE(v_vacancy.vacancy_id::TEXT, NEW.vacancy_vcode), NEW.id),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$;

-- 6. Update handle_closure_approval trigger function
CREATE OR REPLACE FUNCTION public.handle_closure_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_vacancy RECORD;
  v_requestor RECORD;
  v_type TEXT;
BEGIN
  IF NEW.status = 'Approved' AND OLD.status = 'Pending' THEN
    PERFORM public.fn_assert_vacancy_closeable(NEW.vacancy_vcode);

    UPDATE public.vacancies
    SET status = 'Closed',
        is_archived = true,
        archived_at = NOW(),
        archived_by = NEW.reviewed_by,
        has_pending_closure = false,
        closure_request_status = 'Approved',
        updated_at = NOW()
    WHERE vcode = NEW.vacancy_vcode;
  END IF;

  IF NEW.status = 'Rejected' AND OLD.status = 'Pending' THEN
    UPDATE public.vacancies
    SET has_pending_closure = false,
        closure_request_status = 'Rejected',
        updated_at = NOW()
    WHERE vcode = NEW.vacancy_vcode;
  END IF;

  IF NEW.status IN ('Approved', 'Rejected') AND OLD.status IS DISTINCT FROM NEW.status THEN
    SELECT v.id AS vacancy_id,
           COALESCE(a.account_name, v.account) AS account_name
    INTO v_vacancy
    FROM public.vacancies v
    LEFT JOIN public.accounts a ON a.id = v.account_id
    WHERE v.vcode = NEW.vacancy_vcode
    LIMIT 1;

    SELECT up.auth_user_id, up.role
    INTO v_requestor
    FROM public.users_profile up
    WHERE up.auth_user_id = NEW.requested_by_user_id
       OR up.id = NEW.requested_by_user_id
    LIMIT 1;

    v_type := CASE WHEN NEW.status = 'Approved' THEN 'approval' ELSE 'rejection' END;

    IF COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id) IS NOT NULL THEN
      PERFORM public.notify_user(
        COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id),
        COALESCE(v_requestor.role, 'Ops'),
        CASE WHEN NEW.status = 'Approved' THEN 'Vacancy Closure Approved' ELSE 'Vacancy Closure Rejected' END,
        CASE WHEN NEW.status = 'Approved'
          THEN 'Your closure request for ' || NEW.vacancy_vcode || ' (' || COALESCE(v_vacancy.account_name, 'Account') || ') has been approved by ' || COALESCE(NEW.reviewed_by, NEW.encoder_by, 'Encoder') || '.'
          ELSE 'Your closure request for ' || NEW.vacancy_vcode || ' (' || COALESCE(v_vacancy.account_name, 'Account') || ') was rejected by ' || COALESCE(NEW.reviewed_by, NEW.encoder_by, 'Encoder') || '. Reason: ' || COALESCE(NEW.reviewer_remarks, NEW.details, NEW.reason, 'No reason provided') || '.'
        END,
        v_type,
        'vacancy_closure',
        'vacancy_closure',
        NEW.id::TEXT,
        FORMAT('/vacancies/%s/closure-request/%s', COALESCE(v_vacancy.vacancy_id::TEXT, NEW.vacancy_vcode), NEW.id),
        NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- 6. Update vw_vacancy_detail
CREATE OR REPLACE VIEW public.vw_vacancy_detail AS
 WITH applicant_stats AS (
         SELECT a.vacancy_vcode,
            count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status <> ALL (ARRAY['Failed'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Confirmed Onboard'::text])))) AS active_applicant_count,
            count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text))) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text))) AS latest_hire_at,
            (count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text) AND (COALESCE(a.hired_visible_until, (a.hired_at + '7 days'::interval)) > now()))) > 0) AS has_recent_hire
           FROM applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    v.store_name,
    v.store_id,
    v.area_name,
    v.area_city,
    v.province,
    v.store_branch,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
    CASE
        WHEN ((v.is_archived = true) OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text]))) THEN 'Archived'::text
        WHEN (coalesce(v.has_pending_closure, false) = true
              OR lower(coalesce(v.closure_request_status, '')) = 'pending'
              OR v.status = ANY (ARRAY['closure'::text, 'for_closure'::text])
              OR EXISTS (SELECT 1 FROM vacancy_closure_requests vcr WHERE vcr.vacancy_vcode = v.vcode AND lower(vcr.status) = 'pending'))
          THEN 'For Closure'::text
        WHEN (v.status = 'Filled'::text) THEN 'Hired'::text
        WHEN (COALESCE(s.active_applicant_count, (0)::bigint) > 0) THEN 'Pipeline'::text
        ELSE 'Open'::text
    END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    (CURRENT_DATE - v.vacant_date) AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, (0)::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, (0)::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    v.has_reliever,
    v.reliever_name,
    v.requested_by_user_id,
    v.requested_date,
    v.group_id,
    g.group_name,
    v.hrco_user_id,
    v.hrco_name,
    COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
    NULL::text AS triggered_by_role,
    vr.vacancy_type AS hc_request_type,
    vr.requested_by AS hc_request_requested_by,
    vr.requested_by_user_id AS hc_request_requested_by_user_id,
    vr.created_at AS hc_request_date_created,
    vr.no_of_slots AS hc_request_no_of_slots,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire,
    v.request_type
   FROM ((((vacancies v
     LEFT JOIN applicant_stats s ON ((s.vacancy_vcode = v.vcode)))
     LEFT JOIN groups g ON ((g.id = v.group_id)))
     LEFT JOIN users_profile up ON ((up.id = v.triggered_by_user_id)))
     LEFT JOIN vacancy_requests vr ON ((vr.id = v.source_vacancy_request_id)))
  WHERE (v.deleted_at IS NULL);

GRANT ALL ON public.vw_vacancy_detail TO authenticated, postgres, service_role;

-- 7. Update get_web_vacancy_detail to expose pending closure info in row_capabilities
CREATE OR REPLACE FUNCTION public.get_web_vacancy_detail(p_vacancy_id uuid)
 RETURNS TABLE(vacancy_id uuid, vcode text, position_title text, employment_type text, vacancy_type text, account_id uuid, account_name text, group_id uuid, group_name text, store_id uuid, store_name text, store_branch text, area_name text, area_city text, province text, vacancy_status text, pipeline_status text, vacant_date date, target_fill_date date, aging_days integer, aging_bucket text, urgency text, penalty_exposure numeric, hrco_name text, recruiter_name text, requester_name text, triggered_by_name text, pipeline_summary jsonb, activity_history jsonb, row_capabilities jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            'source_channel', a.applicant_source,
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
      'has_pending_closure', coalesce(vd.has_pending_closure, false),
      'closure_request_status', vd.closure_request_status,
      'authority', 'rls_action_rpcs'
    ) AS row_capabilities
    
  FROM public.vw_vacancy_detail vd
  JOIN public.vacancies v_raw ON v_raw.id = vd.id
  LEFT JOIN public.users_profile up_rec ON up_rec.id = vd.assigned_encoder_id
  LEFT JOIN public.users_profile up_req ON up_req.id = vd.requested_by_user_id
  WHERE vd.id = p_vacancy_id;

END;
$function$;
