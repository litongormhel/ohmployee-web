-- Migration: 20262606000117_fix_multi_slot_open_visibility_and_vacancy_detail.sql
-- Description:
--   1. Align public.list_web_vacancies and public.get_web_vacancy_summary Open tab filter
--      with unfulfilled capacity requirement: (hc_total - hc_filled - hr_processing_count) > 0.
--      Permits multi-slot vacancies (e.g. 1/2 fulfilled) to remain visible in the Open tab
--      while simultaneously showing active pipeline applicants in the Pipeline tab.
--   2. Update public.get_web_vacancy_detail RPC:
--      - Include applicant names (first_name, last_name, middle_name, full_name, display_name)
--        and contact details in pipeline_summary JSON so candidates never render as "Anonymous".
--      - Join vw_vacancy_list to expose accurate hc_filled, hc_total, hc_display,
--        active_applicant_count, confirmed_onboard_count, and hr_processing_count
--        in row_capabilities JSON payload.

BEGIN;

-- ============================================================================
-- 1. Update public.list_web_vacancies
-- ============================================================================
CREATE OR REPLACE FUNCTION public.list_web_vacancies(
  p_status text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id uuid DEFAULT NULL::uuid,
  p_position text DEFAULT NULL::text,
  p_urgency text DEFAULT NULL::text,
  p_aging_bucket text DEFAULT NULL::text,
  p_search text DEFAULT NULL::text,
  p_vacant_from date DEFAULT NULL::date,
  p_vacant_to date DEFAULT NULL::date,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_sort_by text DEFAULT 'vacant_date'::text,
  p_sort_dir text DEFAULT 'desc'::text
)
RETURNS TABLE(
  vacancy_id uuid,
  vcode text,
  account_id uuid,
  account_name text,
  group_id uuid,
  group_name text,
  store_id uuid,
  store_name text,
  position_title text,
  employment_type text,
  vacancy_status text,
  pipeline_status text,
  vacant_date date,
  aging_days integer,
  aging_bucket text,
  target_fill_date date,
  urgency text,
  penalty_exposure numeric,
  hrco_name text,
  row_capabilities jsonb,
  total_count bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
      vl.active_applicant_count,
      vl.hr_processing_count,
      vl.hc_filled,
      vl.hc_total,
      jsonb_build_object(
        'can_view_detail', true,
        'hc_filled', vl.hc_filled,
        'hc_total', vl.hc_total,
        'hc_display', vl.hc_display,
        'hr_processing_count', vl.hr_processing_count,
        'is_pool_vacancy', vl.is_pool_vacancy,
        'can_request_closure_hint',
          coalesce(v_role_level, 0) >= 30
          AND coalesce(vl.is_archived, false) = false
          AND vl.archived_at IS NULL
          AND coalesce(vl.has_pending_closure, v_raw.has_pending_closure, false) = false
          AND coalesce(vl.closure_request_status, v_raw.closure_request_status, '') <> 'Pending'
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived', 'closure', 'for_closure']),
        'authority', 'rls_action_rpcs'
      ) AS row_capabilities
    FROM public.vw_vacancy_list vl
    JOIN public.vacancies v_raw ON v_raw.id = vl.id
    WHERE
      coalesce(vl.is_archived, false) = false
      AND vl.archived_at IS NULL
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
               (
                 -- Open capacity: visible iff unfulfilled capacity exists:
                 -- (s.hc_total - s.hc_filled - s.hr_processing_count) > 0
                 (s.hc_total - s.hc_filled - s.hr_processing_count) > 0
                 OR lower(s.pipeline_status) = 'open'
               )
               AND lower(s.pipeline_status) <> 'hired'
               AND s.vacancy_status <> 'Filled'
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
             WHEN lower(btrim(p_status)) = 'pipeline' THEN 
               (
                 s.active_applicant_count > 0
                 OR lower(s.pipeline_status) = 'pipeline'
               )
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
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
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.hrco_name, '') ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT count(*)::bigint AS cnt FROM filtered
  )
  SELECT
    f.vacancy_id,
    f.vcode,
    f.account_id,
    f.account_name,
    f.group_id,
    f.group_name,
    f.store_id,
    f.store_name,
    f.position_title,
    f.employment_type,
    f.vacancy_status,
    f.pipeline_status,
    f.vacant_date,
    f.aging_days,
    f.aging_bucket,
    f.target_fill_date,
    f.urgency,
    f.penalty_exposure,
    f.hrco_name,
    f.row_capabilities,
    c.cnt AS total_count
  FROM filtered f
  CROSS JOIN counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc' THEN
      CASE v_sort_by
        WHEN 'vcode' THEN f.vcode
        WHEN 'account_name' THEN f.account_name
        WHEN 'group_name' THEN f.group_name
        WHEN 'store_name' THEN f.store_name
        WHEN 'position_title' THEN f.position_title
        WHEN 'vacancy_status' THEN f.vacancy_status
        WHEN 'pipeline_status' THEN f.pipeline_status
        WHEN 'urgency' THEN f.urgency
        ELSE NULL
      END
    END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' THEN
      CASE v_sort_by
        WHEN 'vcode' THEN f.vcode
        WHEN 'account_name' THEN f.account_name
        WHEN 'group_name' THEN f.group_name
        WHEN 'store_name' THEN f.store_name
        WHEN 'position_title' THEN f.position_title
        WHEN 'vacancy_status' THEN f.vacancy_status
        WHEN 'pipeline_status' THEN f.pipeline_status
        WHEN 'urgency' THEN f.urgency
        ELSE NULL
      END
    END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc' THEN
      CASE v_sort_by
        WHEN 'vacant_date' THEN f.vacant_date
        WHEN 'target_fill_date' THEN f.target_fill_date
        ELSE NULL
      END
    END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' THEN
      CASE v_sort_by
        WHEN 'vacant_date' THEN f.vacant_date
        WHEN 'target_fill_date' THEN f.target_fill_date
        ELSE NULL
      END
    END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'aging_days' THEN f.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days' THEN f.aging_days END DESC NULLS LAST,
    f.vacant_date DESC NULLS LAST,
    f.vacancy_id ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_web_vacancies(text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_web_vacancies(text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text) TO authenticated, service_role, postgres;

-- ============================================================================
-- 2. Update public.get_web_vacancy_summary
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_web_vacancy_summary(
  p_status text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id uuid DEFAULT NULL::uuid,
  p_position text DEFAULT NULL::text,
  p_urgency text DEFAULT NULL::text,
  p_search text DEFAULT NULL::text,
  p_vacant_from date DEFAULT NULL::date,
  p_vacant_to date DEFAULT NULL::date
)
RETURNS TABLE(
  total_open bigint,
  with_applicant bigint,
  rejected bigint,
  backout bigint,
  aging_0_7 bigint,
  aging_8_14 bigint,
  aging_15_30 bigint,
  aging_31_plus bigint,
  aging_unknown bigint,
  critical_urgency bigint,
  high_urgency bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
      vl.active_applicant_count,
      vl.hc_filled,
      vl.hc_total,
      vl.hr_processing_count
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
               (
                 (s.hc_total - s.hc_filled - s.hr_processing_count) > 0
                 OR lower(s.pipeline_status) = 'open'
               )
               AND lower(s.pipeline_status) <> 'hired'
               AND s.vacancy_status <> 'Filled'
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
             WHEN lower(btrim(p_status)) = 'pipeline' THEN 
               (
                 s.active_applicant_count > 0
                 OR lower(s.pipeline_status) = 'pipeline'
               )
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
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
      WHERE (
        (f.hc_total - f.hc_filled - f.hr_processing_count) > 0
        OR f.pipeline_status = 'Open'
      )
        AND lower(f.pipeline_status) <> 'hired'
        AND f.vacancy_status <> 'Filled'
        AND f.has_pending_closure = false
        AND lower(coalesce(f.closure_request_status, '')) <> 'pending'
        AND lower(coalesce(f.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
    )::bigint AS total_open,
    count(*) FILTER (
      WHERE (
        f.active_applicant_count > 0
        OR f.pipeline_status = 'Pipeline'
      )
        AND f.has_pending_closure = false
        AND lower(coalesce(f.closure_request_status, '')) <> 'pending'
        AND lower(coalesce(f.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
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
$function$;

REVOKE ALL ON FUNCTION public.get_web_vacancy_summary(text, uuid, uuid, text, text, text, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_vacancy_summary(text, uuid, uuid, text, text, text, date, date) TO authenticated, service_role, postgres;

-- ============================================================================
-- 3. Update public.get_web_vacancy_detail
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_web_vacancy_detail(p_vacancy_id uuid)
RETURNS TABLE(
  vacancy_id uuid,
  vcode text,
  position_title text,
  employment_type text,
  vacancy_type text,
  account_id uuid,
  account_name text,
  group_id uuid,
  group_name text,
  store_id uuid,
  store_name text,
  store_branch text,
  area_name text,
  area_city text,
  province text,
  vacancy_status text,
  pipeline_status text,
  vacant_date date,
  target_fill_date date,
  aging_days integer,
  aging_bucket text,
  urgency text,
  penalty_exposure numeric,
  hrco_name text,
  recruiter_name text,
  requester_name text,
  triggered_by_name text,
  pipeline_summary jsonb,
  activity_history jsonb,
  row_capabilities jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
      AND coalesce(vd.is_archived, false) = false
      AND vd.archived_at IS NULL
      AND vd.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
      AND (
        v_role_level >= 90
        OR (
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
    
    -- Aggregated applicant/pipeline summary with complete candidate identity and contact info
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'applicant_id', a.id,
            'first_name', a.first_name,
            'last_name', a.last_name,
            'middle_name', a.middle_name,
            'full_name', a.full_name,
            'display_name', COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), a.full_name, 'Anonymous'),
            'contact_number', a.contact_number,
            'status', a.status,
            'status_label', a.status,
            'onboard_date', a.hired_at::date,
            'created_at', a.created_at,
            'updated_at', a.updated_at,
            'recruiter_name', up_a_rec.full_name,
            'deployed_by_name', up_a_dep.full_name,
            'profile_edit_count', COALESCE(a.profile_edit_count, 0)
          )
          ORDER BY a.created_at ASC
        )
        FROM public.applicants a
        LEFT JOIN public.users_profile up_a_rec ON up_a_rec.id = COALESCE(a.created_by, v_raw.assigned_encoder_id)
        LEFT JOIN public.users_profile up_a_dep ON up_a_dep.id = a.deployed_by_user_id
        WHERE a.vacancy_vcode = vd.vcode
          AND coalesce(a.is_archived, false) = false
      ),
      '[]'::jsonb
    ) AS pipeline_summary,
    
    -- Recent vacancy audit logs/events (cast action to text to safely handle all enum variants)
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'event_id', al.id,
            'event_label', CASE
              WHEN al.action::text = 'INSERT' THEN 'Vacancy Created'
              WHEN al.action::text = 'UPDATE' AND (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status') THEN 'Status changed to ' || (al.new_data->>'status')
              WHEN al.action::text = 'UPDATE' AND (al.new_data->>'is_archived')::boolean = true THEN 'Vacancy Archived'
              WHEN al.action::text IN ('DELETE', 'SOFT_DELETE') THEN 'Vacancy Deleted'
              ELSE 'Vacancy Updated'
            END,
            'event_description', CASE
              WHEN al.action::text = 'INSERT' THEN 'Record initialized via ' || coalesce(v_raw.source, 'system')
              WHEN al.action::text = 'UPDATE' AND (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status') THEN 'Previous status: ' || coalesce(al.old_data->>'status', 'Unknown')
              ELSE 'Attributes synchronized'
            END,
            'created_at', al.timestamp,
            'profile_name', coalesce(up_al.full_name, 'System')
          )
          ORDER BY al.timestamp DESC
        )
        FROM (
          SELECT *
          FROM public.audit_logs
          WHERE record_id = vd.id
             OR (module = 'applicants' AND (new_data->>'vacancy_vcode' = vd.vcode OR old_data->>'vacancy_vcode' = vd.vcode))
          ORDER BY timestamp DESC
          LIMIT 10
        ) al
        LEFT JOIN public.users_profile up_al ON up_al.auth_user_id = al.actor_id OR up_al.id = al.actor_id
      ),
      '[]'::jsonb
    ) AS activity_history,
    
    -- Row Capabilities strictly reflecting user authority and accurate headcount quota
    jsonb_build_object(
      'can_view_detail', true,
      'can_approve', (v_role_level >= 90),
      'can_update_applicant_status', (v_role_level >= 30),
      'can_request_closure', (
        v_role_level >= 30
        AND vd.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
        AND coalesce(vd.has_pending_closure, false) = false
      ),
      'has_pending_closure', coalesce(vd.has_pending_closure, false),
      'closure_request_status', vd.closure_request_status,
      'hc_filled', coalesce(vl.hc_filled, 0),
      'hc_total', coalesce(vl.hc_total, vd.hc_needed, 1),
      'hc_display', coalesce(vl.hc_display, (coalesce(vl.hc_filled, 0) || '/' || coalesce(vl.hc_total, vd.hc_needed, 1))),
      'active_applicant_count', coalesce(vl.active_applicant_count, 0),
      'confirmed_onboard_count', coalesce(vl.confirmed_onboard_count, 0),
      'hr_processing_count', coalesce(vl.hr_processing_count, 0),
      'is_pool_vacancy', coalesce(vl.is_pool_vacancy, false),
      'authority', 'rls_action_rpcs'
    ) AS row_capabilities

  FROM public.vw_vacancy_detail vd
  JOIN public.vacancies v_raw ON v_raw.id = vd.id
  LEFT JOIN public.vw_vacancy_list vl ON vl.id = vd.id
  LEFT JOIN public.users_profile up_rec ON up_rec.id = v_raw.assigned_encoder_id
  LEFT JOIN public.users_profile up_req ON up_req.id = v_raw.requested_by_user_id
  WHERE vd.id = p_vacancy_id
  LIMIT 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_vacancy_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_web_vacancy_detail(uuid) TO authenticated, service_role, postgres;

COMMIT;
