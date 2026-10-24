-- ============================================================================
-- Migration: 20262606000063_fix_vacancy_detail_audit_action_enum.sql
-- Description:
--   1. Safely add 'DELETE' to public.audit_action enum if not present.
--   2. Update get_web_vacancy_detail RPC to cast al.action to text
--      (al.action::text) when building event_label and event_description,
--      preventing Postgres 22P02 invalid input value errors and supporting
--      both DELETE and SOFT_DELETE.
-- ============================================================================

-- 1. Ensure 'DELETE' exists in audit_action enum
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'DELETE';

-- 2. Update get_web_vacancy_detail RPC with text-safe audit_action comparisons
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
    
    -- Aggregated applicant/pipeline summary strictly without PII
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'applicant_id', a.id,
            'display_name', COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), a.full_name),
            'status_label', a.status,
            'onboard_date', a.hired_at::date,
            'updated_at', a.updated_at,
            'recruiter_name', up_a_rec.full_name,
            'deployed_by_name', up_a_dep.full_name
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
    
    -- Row Capabilities strictly reflecting user authority
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
      'hc_filled', vd.hc_filled,
      'hc_total', vd.hc_total,
      'hc_display', vd.hc_display
    ) AS row_capabilities

  FROM public.vw_vacancy_detail vd
  JOIN public.vacancies v_raw ON v_raw.id = vd.id
  LEFT JOIN public.users_profile up_rec ON up_rec.id = v_raw.assigned_encoder_id
  LEFT JOIN public.users_profile up_req ON up_req.id = v_raw.requested_by_user_id
  WHERE vd.id = p_vacancy_id
  LIMIT 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_vacancy_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_web_vacancy_detail(uuid) TO authenticated;
