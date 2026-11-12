-- Migration: 20262606000101_align_list_web_vacancies_adr001_rule4_open_capacity.sql
-- Description: Align public.list_web_vacancies Open tab filter with ADR-001 Rule 4.
-- Replaces overly broad hc_filled < hc_total with remaining capacity check
-- ((hc_total - hc_filled - hr_processing_count - active_applicant_count) > 0)
-- and strictly excludes 'hired' and 'pipeline' statuses from the Open queue.

BEGIN;

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
                 -- ADR-001 Rule 4: visible iff (hc_needed - hired_count - pipeline_count - hr_processing_count) > 0
                 (s.hc_total - s.hc_filled - s.hr_processing_count - s.active_applicant_count) > 0
                 OR lower(s.pipeline_status) = 'open'
               )
               AND lower(s.pipeline_status) NOT IN ('hired', 'pipeline')
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

COMMIT;
