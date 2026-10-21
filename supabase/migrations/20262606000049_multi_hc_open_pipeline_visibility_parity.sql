-- Migration: 20262606000049_multi_hc_open_pipeline_visibility_parity.sql
-- Description:
--   1. Update vw_vacancy_list and vw_vacancy_detail:
--      Capacity-aware derived_status: A multi-headcount requisition stays 'Open'
--      as long as hc_filled < hc_total (i.e. confirmed_onboard_count < required_headcount).
--   2. Update list_web_vacancies:
--      - 'open' queue includes all active requisitions where hc_filled < hc_total.
--      - 'pipeline' queue includes all requisitions with active_applicant_count > 0.
--   3. Update get_web_vacancy_summary:
--      - total_open counts all non-closure active vacancies where hc_filled < hc_total.
--      - with_applicant counts total active pipeline candidates so badge matches rendered candidate rows.
--   4. Update vw_slot_derived_vacancy_shadow:
--      - vacancy_tab evaluates open capacity before pipeline so remaining slots keep requisition in 'Open'.
--   5. Automate vacancy re-opening on slot vacancy:
--      - Trigger trg_reopen_vacancy_on_slot_open automatically restores vacancies.status = 'Open' and
--        clears is_archived when a plantilla_slots row transitions to 'open'.
--   6. One-time data fix: restore VCAG5_0056 status to 'Open'.

-- ============================================================================
-- Section 1. Transition validator: allow Pipeline -> Open
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_is_valid_vacancy_transition(p_old text, p_new text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    -- NULL/blank old (insert path) → only Draft / Pending Approval / Open allowed at create time
    WHEN p_old IS NULL OR p_old = '' THEN p_new IN ('Draft','Pending Approval','Open')
    WHEN p_old = p_new THEN TRUE
    WHEN p_old = 'Draft'            AND p_new IN ('Pending Approval','Closed','Rejected') THEN TRUE
    WHEN p_old = 'Pending Approval' AND p_new IN ('Open','Rejected','Closed')             THEN TRUE
    WHEN p_old = 'Open'             AND p_new IN ('On Hold','Filled','Closed','Pipeline')  THEN TRUE
    WHEN p_old = 'Pipeline'         AND p_new IN ('Open','Filled','Closed','On Hold')      THEN TRUE
    WHEN p_old = 'On Hold'          AND p_new IN ('Open','Closed')                         THEN TRUE
    -- Filled / Closed → Open / Closed: allowed for Coverage Group, Slot Reopen, and Backout / Reopen flows.
    WHEN p_old IN ('Filled', 'Closed') AND p_new IN ('Open','Closed')                     THEN TRUE
    -- Legacy values: allow same-state and migration to canon.
    WHEN p_old IN ('For Sourcing','Backout') AND p_new IN ('Open','Closed','Filled','On Hold') THEN TRUE
    WHEN p_old = 'Archived'         AND p_new = 'Archived'                                  THEN TRUE
    WHEN p_new = 'Archived' THEN TRUE
    WHEN p_old = 'Archived'         AND p_new <> 'Archived'                                 THEN TRUE
    ELSE FALSE
  END;
$function$;

-- ============================================================================
-- Section 2. Update vw_vacancy_list
-- ============================================================================
CREATE OR REPLACE VIEW public.vw_vacancy_list AS
 WITH applicant_stats AS (
          SELECT a.vacancy_vcode,
            count(*) FILTER (
              WHERE COALESCE(a.is_archived, false) = false
                AND replace(replace(lower(btrim(COALESCE(a.status, ''))), ' ', '_'), '-', '_') NOT IN (
                  'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew', 'confirmed_onboard'
                )
            ) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text AND COALESCE(a.hired_visible_until, a.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
           FROM public.applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    COALESCE(
      NULLIF(btrim(v.store_name), ''),
      NULLIF(btrim(v.store_branch), ''),
      CASE
        WHEN v.is_pool_vacancy = true
          OR v.source = 'pool'
          OR v.vcode LIKE '%GHQ%'
          OR lower(btrim(COALESCE(v.account, ''))) = 'moses hq'
          OR lower(btrim(COALESCE(a.account_name, ''))) = 'moses hq'
          OR lower(btrim(COALESCE(g.group_name, ga.group_name, ''))) = 'global hq'
          OR v.home_account_id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152'::uuid
        THEN 'Moses HQ'::text
        ELSE NULL::text
      END
    ) AS store_name,
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
        WHEN COALESCE(s.confirmed_onboard_count, 0::bigint) >= GREATEST(COALESCE(v.required_headcount, 1), 1)
             OR v.status = 'Filled'::text THEN 'Hired'::text
        WHEN COALESCE(v.has_pending_closure, false) = true
             OR LOWER(COALESCE(v.closure_request_status, '')) = 'pending'
             OR LOWER(COALESCE(v.status, '')) IN ('closure', 'for_closure')
             OR EXISTS (
               SELECT 1 FROM public.vacancy_closure_requests vcr
               WHERE vcr.vacancy_vcode = v.vcode AND LOWER(vcr.status) = 'pending'
             ) THEN 'For Closure'::text
        -- Capacity-aware rule: Stays 'Open' as long as quota is not completely filled
        WHEN COALESCE(s.confirmed_onboard_count, 0::bigint) < GREATEST(COALESCE(v.required_headcount, 1), 1) THEN 'Open'::text
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
    COALESCE(v.group_id, a.group_id) AS group_id,
    COALESCE(g.group_name, ga.group_name) AS group_name,
    COALESCE(
      v.hrco_user_id,
      st.hrco_user_id,
      a.hrco_user_id,
      (
        SELECT us_acc.user_id
        FROM public.user_scopes us_acc
        JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
        JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
        WHERE us_acc.account_id = COALESCE(v.account_id, a.id)
          AND r_sc.role_name = 'HRCO'::text
          AND up_sc.is_active = true
          AND up_sc.archived_at IS NULL
        ORDER BY us_acc.created_at ASC
        LIMIT 1
      ),
      (
        SELECT us_grp.user_id
        FROM public.user_scopes us_grp
        JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
        JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
        WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id)
          AND us_grp.account_id IS NULL
          AND r_scg.role_name = 'HRCO'::text
          AND up_scg.is_active = true
          AND up_scg.archived_at IS NULL
        ORDER BY us_grp.created_at ASC
        LIMIT 1
      )
    ) AS hrco_user_id,
    COALESCE(
      CASE WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name ELSE NULL::text END,
      CASE WHEN up_st_hrco.is_active = true AND r_st_hrco.role_name = 'HRCO'::text THEN up_st_hrco.full_name ELSE NULL::text END,
      CASE WHEN up_a_hrco.is_active = true AND r_a_hrco.role_name = 'HRCO'::text THEN up_a_hrco.full_name ELSE NULL::text END,
      (
        SELECT up_sc.full_name
        FROM public.user_scopes us_acc
        JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
        JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
        WHERE us_acc.account_id = COALESCE(v.account_id, a.id)
          AND r_sc.role_name = 'HRCO'::text
          AND up_sc.is_active = true
          AND up_sc.archived_at IS NULL
        ORDER BY us_acc.created_at ASC
        LIMIT 1
      ),
      (
        SELECT up_scg.full_name
        FROM public.user_scopes us_grp
        JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
        JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
        WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id)
          AND us_grp.account_id IS NULL
          AND r_scg.role_name = 'HRCO'::text
          AND up_scg.is_active = true
          AND up_scg.archived_at IS NULL
        ORDER BY us_grp.created_at ASC
        LIMIT 1
      ),
      NULLIF(btrim(v.hrco_name), '')
    ) AS hrco_name,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire,
    COALESCE(s.confirmed_onboard_count, 0::bigint)::integer AS hc_filled,
    GREATEST(COALESCE(v.required_headcount, 1), 1)::integer AS hc_total,
    format('%s/%s', COALESCE(s.confirmed_onboard_count, 0::bigint), GREATEST(COALESCE(v.required_headcount, 1), 1)::integer) AS hc_display
   FROM public.vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN public.accounts a ON a.id = v.account_id OR (v.account_id IS NULL AND lower(trim(a.account_name)) = lower(trim(v.account)))
     LEFT JOIN public.stores st ON st.id = v.store_id
     LEFT JOIN public.groups g ON g.id = v.group_id
     LEFT JOIN public.groups ga ON ga.id = a.group_id
     LEFT JOIN public.users_profile up_hrco ON up_hrco.id = v.hrco_user_id
     LEFT JOIN public.roles r_hrco ON r_hrco.id = up_hrco.role_id
     LEFT JOIN public.users_profile up_st_hrco ON up_st_hrco.id = st.hrco_user_id
     LEFT JOIN public.roles r_st_hrco ON r_st_hrco.id = up_st_hrco.role_id
     LEFT JOIN public.users_profile up_a_hrco ON up_a_hrco.id = a.hrco_user_id
     LEFT JOIN public.roles r_a_hrco ON r_a_hrco.id = up_a_hrco.role_id
  WHERE v.deleted_at IS NULL;

GRANT ALL ON public.vw_vacancy_list TO authenticated, postgres, service_role;

-- ============================================================================
-- Section 3. Update vw_vacancy_detail
-- ============================================================================
CREATE OR REPLACE VIEW public.vw_vacancy_detail AS
 WITH applicant_stats AS (
          SELECT a_1.vacancy_vcode,
            count(*) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND (replace(replace(lower(btrim(COALESCE(a_1.status, ''::text))), ' '::text, '_'::text), '-'::text, '_'::text) <> ALL (ARRAY['failed'::text, 'backout'::text, 'rejected'::text, 'did_not_report'::text, 'rejected_by_ops'::text, 'withdrew'::text, 'confirmed_onboard'::text]))) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND a_1.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a_1.hired_at) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND a_1.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND a_1.status = 'Confirmed Onboard'::text AND COALESCE(a_1.hired_visible_until, a_1.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
           FROM public.applicants a_1
          GROUP BY a_1.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    COALESCE(NULLIF(btrim(v.store_name), ''::text), NULLIF(btrim(v.store_branch), ''::text),
        CASE
            WHEN v.is_pool_vacancy = true OR v.source = 'pool'::text OR v.vcode ~~ '%GHQ%'::text OR lower(btrim(COALESCE(v.account, ''::text))) = 'moses hq'::text OR lower(btrim(COALESCE(a.account_name, ''::text))) = 'moses hq'::text OR lower(btrim(COALESCE(g.group_name, ga.group_name, ''::text))) = 'global hq'::text OR v.home_account_id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152'::uuid THEN 'Moses HQ'::text
            ELSE NULL::text
        END) AS store_name,
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
        WHEN COALESCE(s.confirmed_onboard_count, 0::bigint) >= GREATEST(COALESCE(v.required_headcount, 1), 1)
             OR v.status = 'Filled'::text THEN 'Hired'::text
        WHEN COALESCE(v.has_pending_closure, false) = true
             OR LOWER(COALESCE(v.closure_request_status, '')) = 'pending'
             OR LOWER(COALESCE(v.status, '')) IN ('closure', 'for_closure')
             OR EXISTS (
               SELECT 1 FROM public.vacancy_closure_requests vcr
               WHERE vcr.vacancy_vcode = v.vcode AND LOWER(vcr.status) = 'pending'
             ) THEN 'For Closure'::text
        -- Capacity-aware rule: Stays 'Open' as long as quota is not completely filled
        WHEN COALESCE(s.confirmed_onboard_count, 0::bigint) < GREATEST(COALESCE(v.required_headcount, 1), 1) THEN 'Open'::text
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
    v.has_reliever,
    v.reliever_name,
    v.requested_by_user_id,
    v.requested_date,
    COALESCE(v.group_id, a.group_id) AS group_id,
    COALESCE(g.group_name, ga.group_name) AS group_name,
    COALESCE(
      v.hrco_user_id,
      st.hrco_user_id,
      a.hrco_user_id,
      (
        SELECT us_acc.user_id
        FROM public.user_scopes us_acc
        JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
        JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
        WHERE us_acc.account_id = COALESCE(v.account_id, a.id)
          AND r_sc.role_name = 'HRCO'::text
          AND up_sc.is_active = true
          AND up_sc.archived_at IS NULL
        ORDER BY us_acc.created_at ASC
        LIMIT 1
      ),
      (
        SELECT us_grp.user_id
        FROM public.user_scopes us_grp
        JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
        JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
        WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id)
          AND us_grp.account_id IS NULL
          AND r_scg.role_name = 'HRCO'::text
          AND up_scg.is_active = true
          AND up_scg.archived_at IS NULL
        ORDER BY us_grp.created_at ASC
        LIMIT 1
      )
    ) AS hrco_user_id,
    COALESCE(
      CASE WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name ELSE NULL::text END,
      CASE WHEN up_st_hrco.is_active = true AND r_st_hrco.role_name = 'HRCO'::text THEN up_st_hrco.full_name ELSE NULL::text END,
      CASE WHEN up_a_hrco.is_active = true AND r_a_hrco.role_name = 'HRCO'::text THEN up_a_hrco.full_name ELSE NULL::text END,
      (
        SELECT up_sc.full_name
        FROM public.user_scopes us_acc
        JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
        JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
        WHERE us_acc.account_id = COALESCE(v.account_id, a.id)
          AND r_sc.role_name = 'HRCO'::text
          AND up_sc.is_active = true
          AND up_sc.archived_at IS NULL
        ORDER BY us_acc.created_at ASC
        LIMIT 1
      ),
      (
        SELECT up_scg.full_name
        FROM public.user_scopes us_grp
        JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
        JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
        WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id)
          AND us_grp.account_id IS NULL
          AND r_scg.role_name = 'HRCO'::text
          AND up_scg.is_active = true
          AND up_scg.archived_at IS NULL
        ORDER BY us_grp.created_at ASC
        LIMIT 1
      ),
      NULLIF(btrim(v.hrco_name), '')
    ) AS hrco_name,
    COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
    NULL::text AS triggered_by_role,
    vr.vacancy_type AS hc_request_type,
    vr.requested_by AS hc_request_requested_by,
    vr.requested_by_user_id AS hc_request_requested_by_user_id,
    vr.created_at AS hc_request_date_created,
    vr.no_of_slots AS hc_request_no_of_slots,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire,
    v.request_type,
    COALESCE(s.confirmed_onboard_count, 0::bigint)::integer AS hc_filled,
    GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer AS hc_total,
    format('%s/%s'::text, COALESCE(s.confirmed_onboard_count, 0::bigint), GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer) AS hc_display
   FROM public.vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN public.accounts a ON a.id = v.account_id OR (v.account_id IS NULL AND lower(trim(a.account_name)) = lower(trim(v.account)))
     LEFT JOIN public.stores st ON st.id = v.store_id
     LEFT JOIN public.groups g ON g.id = v.group_id
     LEFT JOIN public.groups ga ON ga.id = a.group_id
     LEFT JOIN public.users_profile up ON up.id = v.triggered_by_user_id
     LEFT JOIN public.vacancy_requests vr ON vr.id = v.source_vacancy_request_id
     LEFT JOIN public.users_profile up_hrco ON up_hrco.id = v.hrco_user_id
     LEFT JOIN public.roles r_hrco ON r_hrco.id = up_hrco.role_id
     LEFT JOIN public.users_profile up_st_hrco ON up_st_hrco.id = st.hrco_user_id
     LEFT JOIN public.roles r_st_hrco ON r_st_hrco.id = up_st_hrco.role_id
     LEFT JOIN public.users_profile up_a_hrco ON up_a_hrco.id = a.hrco_user_id
     LEFT JOIN public.roles r_a_hrco ON r_a_hrco.id = up_a_hrco.role_id
  WHERE v.deleted_at IS NULL;

GRANT ALL ON public.vw_vacancy_detail TO authenticated, postgres, service_role;

-- ============================================================================
-- Section 4. Update list_web_vacancies
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
      vl.hc_filled,
      vl.hc_total,
      jsonb_build_object(
        'can_view_detail', true,
        'hc_filled', vl.hc_filled,
        'hc_total', vl.hc_total,
        'hc_display', vl.hc_display,
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
                 -- Multi-headcount: stays Open until all required quota is fulfilled (hc_filled < hc_total)
                 s.hc_filled < s.hc_total
                 OR lower(s.pipeline_status) = 'open'
               )
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
GRANT EXECUTE ON FUNCTION public.list_web_vacancies(text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text) TO authenticated, service_role;

-- ============================================================================
-- Section 5. Update get_web_vacancy_summary
-- ============================================================================
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
      vl.active_applicant_count,
      vl.hc_filled,
      vl.hc_total
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
                 s.hc_filled < s.hc_total
                 OR lower(s.pipeline_status) = 'open'
               )
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
      ) AS backout_count,
      count(a.id) FILTER (
        WHERE COALESCE(a.is_archived, false) = false
          AND replace(replace(lower(btrim(coalesce(a.status, ''))), ' ', '_'), '-', '_') NOT IN (
            'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew', 'confirmed_onboard'
          )
      ) AS active_pipeline_count
    FROM filtered f
    LEFT JOIN public.applicants a ON a.vacancy_vcode = f.vcode
    GROUP BY f.vacancy_id
  )
  SELECT
    count(*) FILTER (
      WHERE (
        (f.hc_filled < f.hc_total)
        OR lower(f.pipeline_status) = 'open'
      )
      AND f.vacancy_status <> 'Filled'
      AND f.has_pending_closure = false
      AND lower(coalesce(f.closure_request_status, '')) <> 'pending'
      AND lower(coalesce(f.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
    )::bigint AS total_open,
    COALESCE(sum(ar.active_pipeline_count), 0)::bigint AS with_applicant,
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

-- ============================================================================
-- Section 6. Update vw_slot_derived_vacancy_shadow
-- ============================================================================
CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_shadow AS
 WITH aging_basis AS (
         SELECT DISTINCT ON (sh.slot_id) sh.slot_id,
            sh.created_at AS open_episode_start
           FROM public.slot_history sh
          WHERE sh.new_value = 'open'::text
          ORDER BY sh.slot_id, sh.created_at DESC
        ), pending_closure AS (
         SELECT DISTINCT vcr.vacancy_vcode
           FROM public.vacancy_closure_requests vcr
             JOIN public.vacancies v_1 ON v_1.vcode = vcr.vacancy_vcode AND v_1.deleted_at IS NULL AND COALESCE(v_1.is_archived, false) = false
          WHERE vcr.status = 'Pending'::text
        ), applicant_counts AS (
         SELECT a_1.vacancy_vcode,
            count(DISTINCT a_1.id) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND public.fn_is_active_vacancy_applicant_status(a_1.status)) AS pipeline_count
           FROM public.applicants a_1
          WHERE a_1.vacancy_vcode IS NOT NULL
          GROUP BY a_1.vacancy_vcode
        ), plantilla_counts AS (
         SELECT p.vcode,
            count(DISTINCT p.id) FILTER (WHERE COALESCE(p.is_deleted, false) = false AND p.status = 'Active'::text) AS active_emp_count
           FROM public.plantilla p
          WHERE p.vcode IS NOT NULL
          GROUP BY p.vcode
        ), req_counts AS (
         SELECT vr.vacancy_id,
            sum(vr.hc_needed) AS req_hc_needed
           FROM public.vacancy_requirements vr
          GROUP BY vr.vacancy_id
        )
 SELECT ps.legacy_vcode,
    ps.legacy_vcode AS vacancy_id,
    v.id AS legacy_vacancy_id,
    v.store_name,
    v.area_city,
    v.province,
    v.area_name,
    v.required_headcount,
    (array_agg(ps.store_id ORDER BY ps.created_at, (ps.id::text)))[1] AS store_id,
    min(st.store_branch) AS store_branch,
    (array_agg(ps.account_id ORDER BY ps.created_at, (ps.id::text)))[1] AS account_id,
    min(a.account_name) AS account_name,
    (array_agg(ps.group_id ORDER BY ps.created_at, (ps.id::text)))[1] AS group_id,
    min(g.group_name) AS group_name,
    min(ps."position") AS "position",
    min(ps.employment_type) AS employment_type,
    false AS is_roving,
    count(*) AS required_hc,
    COALESCE(rc.req_hc_needed, count(*)) AS hc_needed,
    COALESCE(max(ac.pipeline_count), 0::bigint) AS pipeline_count,
    COALESCE(max(plc.active_emp_count), 0::bigint) AS hired_count,
        CASE
            WHEN bool_or(pc.vacancy_vcode IS NOT NULL) OR (EXISTS ( SELECT 1
               FROM public.plantilla_slots ps_closed
              WHERE ps_closed.legacy_vcode = ps.legacy_vcode AND ps_closed.slot_status = 'closed'::text)) OR (EXISTS ( SELECT 1
               FROM public.stores s
              WHERE s.id = v.store_id AND (s.is_deletion_requested = true OR (s.status = ANY (ARRAY['Pending Deletion'::text, 'Closure Requested'::text]))))) THEN 0::bigint
            ELSE GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint))
        END AS open_count,
    count(*) FILTER (WHERE ps.slot_status = 'hr_processing'::text) AS hr_processing_count,
    count(*) FILTER (WHERE ps.slot_status = 'occupied'::text) AS occupied_count,
    count(*) FILTER (WHERE ps.slot_status = 'closed'::text) AS closed_count,
    COALESCE(max(ac.pipeline_count), 0::bigint) AS active_applicant_count,
    bool_or(pc.vacancy_vcode IS NOT NULL) OR (EXISTS ( SELECT 1
           FROM public.stores s
          WHERE s.id = v.store_id AND (s.is_deletion_requested = true OR (s.status = ANY (ARRAY['Pending Deletion'::text, 'Closure Requested'::text]))))) AS has_pending_closure,
        CASE
            WHEN bool_or(pc.vacancy_vcode IS NOT NULL) OR (EXISTS ( SELECT 1
               FROM public.plantilla_slots ps_closed
              WHERE ps_closed.legacy_vcode = ps.legacy_vcode AND ps_closed.slot_status = 'closed'::text)) OR (EXISTS ( SELECT 1
               FROM public.stores s
              WHERE s.id = v.store_id AND (s.is_deletion_requested = true OR (s.status = ANY (ARRAY['Pending Deletion'::text, 'Closure Requested'::text]))))) THEN 'Closure'::text
            -- Open capacity check precedes pipeline
            WHEN GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint)) > 0 THEN 'Open'::text
            WHEN COALESCE(max(plc.active_emp_count), 0::bigint) >= COALESCE(rc.req_hc_needed, count(*)) THEN 'Hired'::text
            WHEN COALESCE(max(ac.pipeline_count), 0::bigint) > 0 THEN 'Pipeline'::text
            ELSE 'Open'::text
        END AS vacancy_tab,
    min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text) AS aging_start_at,
        CASE
            WHEN GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint)) = 0 THEN NULL::integer
            WHEN min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text)::date > CURRENT_DATE THEN NULL::integer
            ELSE CURRENT_DATE - min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text)::date
        END AS aging_days,
    min(ps.created_at) AS created_at,
    max(ps.updated_at) AS updated_at,
    max(ps.closed_at) AS closed_at,
    (array_agg(ps.source_hc_request_id ORDER BY ps.created_at, (ps.id::text)))[1] AS source_hc_request_id,
    v.urgency_level,
    v.hrco_name,
    v.hrco_user_id,
    v.target_fill_date,
    v.triggered_by_user_id,
    v.triggered_by_name
   FROM public.plantilla_slots ps
     LEFT JOIN aging_basis ab ON ab.slot_id = ps.id
     LEFT JOIN public.stores st ON st.id = ps.store_id
     LEFT JOIN public.accounts a ON a.id = ps.account_id
     LEFT JOIN public.groups g ON g.id = ps.group_id
     LEFT JOIN pending_closure pc ON pc.vacancy_vcode = ps.legacy_vcode
     LEFT JOIN applicant_counts ac ON ac.vacancy_vcode = ps.legacy_vcode
     LEFT JOIN plantilla_counts plc ON plc.vcode = ps.legacy_vcode
     JOIN public.vacancies v ON v.vcode = ps.legacy_vcode AND v.deleted_at IS NULL AND COALESCE(v.is_archived, false) = false AND v.status <> 'Archived'::text
     LEFT JOIN req_counts rc ON rc.vacancy_id = v.id
  WHERE ps.legacy_vcode IS NOT NULL AND ps.is_roving = false
  GROUP BY ps.legacy_vcode, v.id, rc.req_hc_needed;

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated, service_role;

-- ============================================================================
-- Section 7. Trigger: Automatically Reopen Vacancy when Slot Transitions to 'open'
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_reopen_vacancy_on_slot_open()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.slot_status = 'open' AND (OLD.slot_status IS NULL OR OLD.slot_status <> 'open') AND NEW.legacy_vcode IS NOT NULL THEN
    -- If vacancy was marked Filled or Archived, reset it to Open
    UPDATE public.vacancies
    SET status = 'Open',
        is_archived = false,
        archived_at = NULL,
        archived_by = NULL,
        updated_at = now()
    WHERE vcode = NEW.legacy_vcode
      AND (status = 'Filled' OR status = 'Pipeline' OR is_archived = true);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_reopen_vacancy_on_slot_open
AFTER UPDATE OF slot_status ON public.plantilla_slots
FOR EACH ROW
WHEN (NEW.slot_status = 'open' AND OLD.slot_status <> 'open')
EXECUTE FUNCTION public.fn_reopen_vacancy_on_slot_open();

-- ============================================================================
-- Section 8. Data repair: Ensure VCAG5_0056 and unfulfilled requisitions are 'Open'
-- ============================================================================
UPDATE public.vacancies
SET status = 'Open',
    is_archived = false,
    archived_at = NULL,
    archived_by = NULL,
    updated_at = now()
WHERE vcode = 'VCAG5_0056'
  AND status = 'Pipeline';
