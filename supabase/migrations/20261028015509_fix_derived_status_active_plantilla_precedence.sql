-- ============================================================================
-- Migration: 20261028015509_fix_derived_status_active_plantilla_precedence.sql
-- Description: Align derived_status in vw_vacancy_list and vw_vacancy_detail
-- with ADR-001 Rule 2 (active_plantilla_count >= required_headcount -> 'Hired').
-- Stamped by apply_migration on staging: 20261028015509
-- ============================================================================

CREATE OR REPLACE VIEW public.vw_vacancy_list AS
WITH applicant_stats AS (
  SELECT a_1.vacancy_vcode,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND (
          replace(replace(lower(btrim(COALESCE(a_1.status, ''::text))), ' '::text, '_'::text), '-'::text, '_'::text)
          <> ALL (ARRAY['failed'::text, 'backout'::text, 'rejected'::text, 'did_not_report'::text, 'rejected_by_ops'::text, 'withdrew'::text, 'confirmed_onboard'::text])
        )
    ) AS active_applicant_count,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
    ) AS confirmed_onboard_count,
    max(a_1.hired_at) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
    ) AS latest_hire_at,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
        AND COALESCE(a_1.hired_visible_until, a_1.hired_at + '7 days'::interval) > now()
    ) > 0 AS has_recent_hire
  FROM public.applicants a_1
  GROUP BY a_1.vacancy_vcode
),
plantilla_stats AS (
  SELECT p.vcode,
    count(*) FILTER (
      WHERE p.status = 'Active'::text
        AND COALESCE(p.is_deleted, false) = false
        AND COALESCE(p.is_archived, false) = false
    ) AS active_plantilla_count
  FROM public.plantilla p
  WHERE p.vcode IS NOT NULL
  GROUP BY p.vcode
),
slot_stats AS (
  SELECT ps.legacy_vcode AS vcode,
    count(*) FILTER (
      WHERE ps.slot_status = 'hr_processing'::text
        AND ps.closed_at IS NULL
    ) AS hr_processing_count
  FROM public.plantilla_slots ps
  WHERE ps.legacy_vcode IS NOT NULL
    AND ps.is_roving = false
  GROUP BY ps.legacy_vcode
)
SELECT v.id,
  v.vcode,
  v.account,
  v.account_id,
  COALESCE(
    NULLIF(btrim(v.store_name), ''::text),
    NULLIF(btrim(v.store_branch), ''::text),
    CASE
      WHEN v.is_pool_vacancy = true
        OR v.source = 'pool'::text
        OR v.vcode ~~ '%GHQ%'::text
        OR lower(btrim(COALESCE(v.account, ''::text))) = 'moses hq'::text
        OR lower(btrim(COALESCE(a.account_name, ''::text))) = 'moses hq'::text
        OR lower(btrim(COALESCE(g.group_name, ga.group_name, ''::text))) = 'global hq'::text
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
    WHEN COALESCE(pls.active_plantilla_count, 0::bigint)::numeric >= GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)
      OR COALESCE(s.confirmed_onboard_count, 0::bigint)::numeric >= GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)
      OR v.status = 'Filled'::text THEN 'Hired'::text
    WHEN COALESCE(v.has_pending_closure, false) = true
      OR lower(COALESCE(v.closure_request_status, ''::text)) = 'pending'::text
      OR (lower(COALESCE(v.status, ''::text)) = ANY (ARRAY['closure'::text, 'for_closure'::text]))
      OR (
        EXISTS (
          SELECT 1
          FROM public.vacancy_closure_requests vcr
          WHERE vcr.vacancy_vcode = v.vcode
            AND lower(vcr.status) = 'pending'::text
        )
      ) THEN 'For Closure'::text
    WHEN (COALESCE(s.confirmed_onboard_count, 0::bigint) + COALESCE(s.active_applicant_count, 0::bigint))::numeric < GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric) THEN 'Open'::text
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
      ORDER BY us_acc.created_at
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
      ORDER BY us_grp.created_at
      LIMIT 1
    )
  ) AS hrco_user_id,
  COALESCE(
    CASE
      WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name
      ELSE NULL::text
    END,
    CASE
      WHEN up_st_hrco.is_active = true AND r_st_hrco.role_name = 'HRCO'::text THEN up_st_hrco.full_name
      ELSE NULL::text
    END,
    CASE
      WHEN up_a_hrco.is_active = true AND r_a_hrco.role_name = 'HRCO'::text THEN up_a_hrco.full_name
      ELSE NULL::text
    END,
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = COALESCE(v.account_id, a.id)
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
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
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    NULLIF(btrim(v.hrco_name), ''::text)
  ) AS hrco_name,
  COALESCE(s.has_recent_hire, false) AS has_recent_hire,
  COALESCE(pls.active_plantilla_count, 0::bigint)::integer AS hc_filled,
  GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer AS hc_total,
  format(
    '%s/%s'::text,
    COALESCE(pls.active_plantilla_count, 0::bigint),
    GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer
  ) AS hc_display,
  COALESCE(ss.hr_processing_count, 0::bigint)::integer AS hr_processing_count,
  COALESCE(v.is_pool_vacancy, false) AS is_pool_vacancy,
  COALESCE(v.affects_required_hc, true) AS affects_required_hc
FROM public.vacancies v
LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
LEFT JOIN plantilla_stats pls ON pls.vcode = v.vcode
LEFT JOIN slot_stats ss ON ss.vcode = v.vcode
LEFT JOIN public.accounts a ON a.id = v.account_id OR (v.account_id IS NULL AND lower(TRIM(BOTH FROM a.account_name)) = lower(TRIM(BOTH FROM v.account)))
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

ALTER VIEW public.vw_vacancy_list OWNER TO postgres;
GRANT SELECT ON public.vw_vacancy_list TO authenticated, service_role;


CREATE OR REPLACE VIEW public.vw_vacancy_detail AS
WITH applicant_stats AS (
  SELECT a_1.vacancy_vcode,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND (
          replace(replace(lower(btrim(COALESCE(a_1.status, ''::text))), ' '::text, '_'::text), '-'::text, '_'::text)
          <> ALL (ARRAY['failed'::text, 'backout'::text, 'rejected'::text, 'did_not_report'::text, 'rejected_by_ops'::text, 'withdrew'::text, 'confirmed_onboard'::text])
        )
    ) AS active_applicant_count,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
    ) AS confirmed_onboard_count,
    max(a_1.hired_at) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
    ) AS latest_hire_at,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
        AND COALESCE(a_1.hired_visible_until, a_1.hired_at + '7 days'::interval) > now()
    ) > 0 AS has_recent_hire
  FROM public.applicants a_1
  GROUP BY a_1.vacancy_vcode
),
plantilla_stats AS (
  SELECT p.vcode,
    count(*) FILTER (
      WHERE p.status = 'Active'::text
        AND COALESCE(p.is_deleted, false) = false
        AND COALESCE(p.is_archived, false) = false
    ) AS active_plantilla_count
  FROM public.plantilla p
  WHERE p.vcode IS NOT NULL
  GROUP BY p.vcode
),
slot_stats AS (
  SELECT ps.legacy_vcode AS vcode,
    count(*) FILTER (
      WHERE ps.slot_status = 'hr_processing'::text
        AND ps.closed_at IS NULL
    ) AS hr_processing_count
  FROM public.plantilla_slots ps
  WHERE ps.legacy_vcode IS NOT NULL
    AND ps.is_roving = false
  GROUP BY ps.legacy_vcode
)
SELECT v.id,
  v.vcode,
  COALESCE(NULLIF(a.account_name, ''::text), NULLIF(ast.account_name, ''::text), NULLIF(v.account, 'Unknown Account'::text), v.account) AS account,
  COALESCE(v.account_id, a.id, st.account_id, st_vcode.account_id) AS account_id,
  COALESCE(
    NULLIF(btrim(v.store_name), ''::text),
    NULLIF(btrim(v.store_branch), ''::text),
    CASE
      WHEN v.is_pool_vacancy = true
        OR v.source = 'pool'::text
        OR v.vcode ~~ '%GHQ%'::text
        OR lower(btrim(COALESCE(v.account, ''::text))) = 'moses hq'::text
        OR lower(btrim(COALESCE(a.account_name, ''::text))) = 'moses hq'::text
        OR lower(btrim(COALESCE(g.group_name, ga.group_name, ''::text))) = 'global hq'::text
        OR v.home_account_id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152'::uuid
      THEN 'Moses HQ'::text
      ELSE NULL::text
    END
  ) AS store_name,
  COALESCE(v.store_id, st.id, st_vcode.id) AS store_id,
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
    WHEN COALESCE(pls.active_plantilla_count, 0::bigint)::numeric >= GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)
      OR COALESCE(s.confirmed_onboard_count, 0::bigint)::numeric >= GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)
      OR v.status = 'Filled'::text THEN 'Hired'::text
    WHEN COALESCE(v.has_pending_closure, false) = true
      OR lower(COALESCE(v.closure_request_status, ''::text)) = 'pending'::text
      OR (lower(COALESCE(v.status, ''::text)) = ANY (ARRAY['closure'::text, 'for_closure'::text]))
      OR (
        EXISTS (
          SELECT 1
          FROM public.vacancy_closure_requests vcr
          WHERE vcr.vacancy_vcode = v.vcode
            AND lower(vcr.status) = 'pending'::text
        )
      ) THEN 'For Closure'::text
    WHEN (COALESCE(s.confirmed_onboard_count, 0::bigint) + COALESCE(s.active_applicant_count, 0::bigint))::numeric < GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric) THEN 'Open'::text
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
  COALESCE(v.group_id, a.group_id, st.group_id, st_vcode.group_id, ga.id, gst.id) AS group_id,
  COALESCE(g.group_name, ga.group_name, gst.group_name) AS group_name,
  COALESCE(
    v.hrco_user_id,
    st.hrco_user_id,
    st_vcode.hrco_user_id,
    a.hrco_user_id,
    (
      SELECT us_acc.user_id
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = COALESCE(v.account_id, a.id, st.account_id, st_vcode.account_id)
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT us_grp.user_id
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id, st.group_id, st_vcode.group_id)
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    )
  ) AS hrco_user_id,
  COALESCE(
    CASE
      WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name
      ELSE NULL::text
    END,
    CASE
      WHEN up_st_hrco.is_active = true AND r_st_hrco.role_name = 'HRCO'::text THEN up_st_hrco.full_name
      ELSE NULL::text
    END,
    CASE
      WHEN up_a_hrco.is_active = true AND r_a_hrco.role_name = 'HRCO'::text THEN up_a_hrco.full_name
      ELSE NULL::text
    END,
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = COALESCE(v.account_id, a.id, st.account_id, st_vcode.account_id)
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT up_scg.full_name
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id, st.group_id, st_vcode.group_id)
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    NULLIF(btrim(v.hrco_name), ''::text)
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
  COALESCE(pls.active_plantilla_count, 0::bigint)::integer AS hc_filled,
  GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer AS hc_total,
  format(
    '%s/%s'::text,
    COALESCE(pls.active_plantilla_count, 0::bigint),
    GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer
  ) AS hc_display,
  COALESCE(ss.hr_processing_count, 0::bigint)::integer AS hr_processing_count,
  COALESCE(v.is_pool_vacancy, false) AS is_pool_vacancy,
  COALESCE(v.affects_required_hc, true) AS affects_required_hc
FROM public.vacancies v
LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
LEFT JOIN plantilla_stats pls ON pls.vcode = v.vcode
LEFT JOIN slot_stats ss ON ss.vcode = v.vcode
LEFT JOIN public.stores st ON st.id = v.store_id
LEFT JOIN public.stores st_vcode ON st_vcode.id = (
  SELECT s_sub.id
  FROM public.stores s_sub
  WHERE upper(s_sub.vcode) = upper(v.vcode)
    AND s_sub.status = 'active'::text
  ORDER BY s_sub.created_at
  LIMIT 1
)
LEFT JOIN public.accounts a ON a.id = v.account_id OR (v.account_id IS NULL AND lower(TRIM(BOTH FROM a.account_name)) = lower(TRIM(BOTH FROM v.account)) AND lower(TRIM(BOTH FROM v.account)) <> 'unknown account'::text)
LEFT JOIN public.accounts ast ON ast.id = COALESCE(st.account_id, st_vcode.account_id)
LEFT JOIN public.groups g ON g.id = v.group_id
LEFT JOIN public.groups ga ON ga.id = COALESCE(a.group_id, v.group_id)
LEFT JOIN public.groups gst ON gst.id = COALESCE(st.group_id, st_vcode.group_id, ast.group_id)
LEFT JOIN public.users_profile up ON up.id = v.triggered_by_user_id
LEFT JOIN public.vacancy_requests vr ON vr.id = v.source_vacancy_request_id
LEFT JOIN public.users_profile up_hrco ON up_hrco.id = v.hrco_user_id
LEFT JOIN public.roles r_hrco ON r_hrco.id = up_hrco.role_id
LEFT JOIN public.users_profile up_st_hrco ON up_st_hrco.id = COALESCE(st.hrco_user_id, st_vcode.hrco_user_id)
LEFT JOIN public.roles r_st_hrco ON r_st_hrco.id = up_st_hrco.role_id
LEFT JOIN public.users_profile up_a_hrco ON up_a_hrco.id = a.hrco_user_id
LEFT JOIN public.roles r_a_hrco ON r_a_hrco.id = up_a_hrco.role_id;

ALTER VIEW public.vw_vacancy_detail OWNER TO postgres;
GRANT SELECT ON public.vw_vacancy_detail TO authenticated, service_role;
