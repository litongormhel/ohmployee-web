-- ============================================================================
-- Migration: 20262606000177_clean_open_vacancy_and_applicant_terminal_archival.sql
-- Description: Enforce Clean Open Requisition Invariant upon Backout / Terminal Dropouts,
--              add automatic terminal archival trigger on public.applicants,
--              reconcile historical un-archived dropouts, and surgically filter
--              get_web_vacancy_detail to exclude dropouts from active applicant list.
-- ============================================================================

BEGIN;

-- 1. Reconcile existing historical terminal dropouts (e.g. James Cruz on TEST011)
UPDATE public.applicants
SET is_archived = true,
    archived_at = COALESCE(archived_at, updated_at, now()),
    slot_id = NULL
WHERE is_archived = false
  AND (
    replace(replace(lower(btrim(COALESCE(status, ''))), ' ', '_'), '-', '_')
    = ANY (ARRAY['failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew'])
  );

-- 2. Trigger on public.applicants: auto-archive and unlink slot on terminal status
CREATE OR REPLACE FUNCTION public.fn_trg_applicants_terminal_archival()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF replace(replace(lower(btrim(COALESCE(NEW.status, ''))), ' ', '_'), '-', '_')
     = ANY (ARRAY['failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew']) THEN
    NEW.is_archived := true;
    IF NEW.archived_at IS NULL THEN
      NEW.archived_at := now();
    END IF;
    NEW.slot_id := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_applicants_terminal_archival ON public.applicants;
CREATE TRIGGER trg_applicants_terminal_archival
BEFORE INSERT OR UPDATE OF status, is_archived ON public.applicants
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_applicants_terminal_archival();

-- 3. Surgical update to public.get_web_vacancy_detail to strictly exclude terminal dropouts from pipeline_summary
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
    
    -- Aggregated applicant/pipeline summary strictly excluding terminal dropouts
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
          AND (
            replace(replace(lower(btrim(coalesce(a.status, ''))), ' ', '_'), '-', '_')
            <> ALL (ARRAY['failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew'])
          )
      ),
      '[]'::jsonb
    ) AS pipeline_summary,
    
    -- Comprehensive, human-readable Vacancy Activity History Timeline (What, Who, When)
    public.get_vacancy_activity_timeline(vd.id) AS activity_history,
    
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
