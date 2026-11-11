-- ============================================================================
-- Migration: 20262606000096_user_management_as_hrco_source_of_truth.sql
-- Description: Establishes User Management (user_scopes + users_profile with role HRCO)
--              as the authoritative Single Source of Truth for HRCO assignments across
--              vw_vacancy_list, v_plantilla_safe, and public.accounts.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Sync accounts.hrco_user_id helper & trigger enhancement
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reevaluate_hrco_auto_tags(p_account_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_hrco_count  int;
  v_sole_hrco   uuid;
  v_assigned_by uuid;
  v_sole_profile_id uuid;
BEGIN
  IF p_account_id IS NULL THEN
    RETURN;
  END IF;

  SELECT count(DISTINCT up.auth_user_id) INTO v_hrco_count
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE r.role_name = 'HRCO'
     AND COALESCE(up.is_active, true)
     AND up.archived_at IS NULL
     AND EXISTS (
       SELECT 1 FROM public.user_scopes us
        WHERE us.user_id = up.id
          AND COALESCE(us.is_active, true)
          AND (
            us.account_id = p_account_id
            OR (us.group_id = (SELECT group_id FROM public.accounts WHERE id = p_account_id) AND us.account_id IS NULL)
          )
     );

  IF v_hrco_count = 0 THEN
    -- Revert to "Needs HRCO" -- auto-assigned rows only, never manual/csv_import.
    UPDATE public.plantilla_hrco_assignments
       SET is_active = false, effective_end = now()
     WHERE account_id = p_account_id
       AND is_active
       AND assignment_source = 'auto_single_hrco';

    -- Sync account-level HRCO column
    UPDATE public.accounts
       SET hrco_user_id = NULL
     WHERE id = p_account_id
       AND hrco_user_id IS NOT NULL;
    RETURN;
  END IF;

  IF v_hrco_count > 1 THEN
    -- On multi-HRCO rosters, leave specific employee assignments as-is.
    RETURN;
  END IF;

  -- Exactly one HRCO on the roster from User Management
  SELECT DISTINCT up.auth_user_id, up.id INTO v_sole_hrco, v_sole_profile_id
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE r.role_name = 'HRCO'
     AND COALESCE(up.is_active, true)
     AND up.archived_at IS NULL
     AND EXISTS (
       SELECT 1 FROM public.user_scopes us
        WHERE us.user_id = up.id
          AND COALESCE(us.is_active, true)
          AND (
            us.account_id = p_account_id
            OR (us.group_id = (SELECT group_id FROM public.accounts WHERE id = p_account_id) AND us.account_id IS NULL)
          )
     )
   LIMIT 1;

  v_assigned_by := COALESCE(
    public.get_current_profile_id(),
    v_sole_profile_id
  );

  -- Keep public.accounts.hrco_user_id synchronized with User Management
  UPDATE public.accounts
     SET hrco_user_id = v_sole_profile_id
   WHERE id = p_account_id
     AND (hrco_user_id IS DISTINCT FROM v_sole_profile_id);

  -- Sole HRCO changed identity (e.g. account had HRCO X, now has HRCO Y)
  UPDATE public.plantilla_hrco_assignments pha
     SET is_active = false, effective_end = now()
   WHERE pha.account_id = p_account_id
     AND pha.is_active
     AND pha.assignment_source = 'auto_single_hrco'
     AND pha.hrco_user_id IS DISTINCT FROM v_sole_hrco;

  -- Auto-assign active employees lacking any assignment
  INSERT INTO public.plantilla_hrco_assignments (
    plantilla_id, employee_no, account_id, hrco_user_id,
    hrco_email_snapshot, hrco_name_snapshot,
    assigned_by, assignment_source
  )
  SELECT p.id, p.employee_no, p.account_id, v_sole_hrco,
         up.email, up.full_name,
         v_assigned_by, 'auto_single_hrco'
    FROM public.plantilla p
    JOIN public.users_profile up ON up.auth_user_id = v_sole_hrco
   WHERE p.account_id = p_account_id
     AND p.status = 'Active'
     AND p.is_deleted IS NOT TRUE
     AND (p.is_archived = false OR p.is_archived IS NULL)
     AND NOT EXISTS (
       SELECT 1 FROM public.plantilla_hrco_assignments pha
        WHERE pha.plantilla_id = p.id AND pha.is_active
     );
END;
$function$;

-- ----------------------------------------------------------------------------
-- 2. Update public.vw_vacancy_list
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.vw_vacancy_list CASCADE;

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
  -- 1. HRCO User ID (User Management as authoritative Source of Truth)
  COALESCE(
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
    ),
    v.hrco_user_id,
    st.hrco_user_id,
    a.hrco_user_id
  ) AS hrco_user_id,
  -- 2. HRCO Name (User Management as authoritative Source of Truth)
  COALESCE(
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
LEFT JOIN public.accounts a ON a.id = v.account_id
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

-- ----------------------------------------------------------------------------
-- 3. Update public.v_plantilla_safe
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.v_plantilla_safe CASCADE;

CREATE OR REPLACE VIEW public.v_plantilla_safe AS
SELECT
  p.id,
  p.employee_name,
  p.employee_no,
  p.account,
  p.account_id,
  p.chain_id,
  p.store_id,
  p.province_id,
  p."position",
  p.position_id,
  p.status,
  p.separation_status,
  p.date_of_separation,
  p.over_headcount,
  p.deactivated_at,
  p.deactivated_visible_until,
  p.deactivation_reason,
  p.deletion_requested_at,
  p.deletion_reason,
  p.sss_no,
  p.philhealth_no,
  p.pagibig_no,
  CASE
    WHEN p.atm_no IS NULL THEN NULL::text
    WHEN length(p.atm_no) <= 4 THEN '****'::text
    ELSE repeat('*'::text, length(p.atm_no) - 4) || right(p.atm_no, 4)
  END AS atm_no_masked,
  p.civil_status,
  p.date_of_birth,
  CASE
    WHEN p.date_of_birth IS NOT NULL THEN EXTRACT(year FROM age(p.date_of_birth::timestamp with time zone))::integer
    ELSE NULL::integer
  END AS age,
  CASE
    WHEN p.date_hired IS NOT NULL THEN (EXTRACT(epoch FROM age(now(), p.date_hired::timestamp with time zone)) / ((60 * 60 * 24)::numeric * 30.4375))::integer
    ELSE NULL::integer
  END AS tenure_months,
  p.last_mika_synced_at,
  p.last_mika_synced_by,
  p.store_name,
  p.area,
  p.rate,
  p.schedule,
  p.deployment_type,
  p.has_penalty,
  p.date_hired,
  -- 1. Coordinator: User Management as authoritative Source of Truth
  COALESCE(
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
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
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    pha.hrco_name_snapshot,
    p.hrco_name,
    p.coordinator
  ) AS coordinator,
  -- 2. hrco_name: User Management as authoritative Source of Truth
  COALESCE(
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
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
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    pha.hrco_name_snapshot,
    p.hrco_name,
    p.coordinator
  ) AS hrco_name,
  p.vcode,
  p.hr_emploc_id,
  p.roving_assignment_id,
  p.created_at,
  p.updated_at,
  p.source_headcount_request_id,
  COALESCE((
    SELECT count(*) AS count
    FROM public.plantilla_store_links psl
    WHERE psl.plantilla_id = p.id
      AND psl.deleted_at IS NULL
      AND psl.status = 'Active'::text
  ), 0::bigint)::integer AS roving_store_count,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'vcode', psl.vcode,
        'store_name', psl.store_name,
        'account', psl.account,
        'status', psl.status,
        'linked_at', psl.linked_at
      ) ORDER BY psl.vcode
    ) AS jsonb_agg
    FROM public.plantilla_store_links psl
    WHERE psl.plantilla_id = p.id
      AND psl.deleted_at IS NULL
  ) AS roving_stores,
  p.inactive_visible_until,
  s.area_city,
  COALESCE(s.area_province, s.province) AS area_province,
  CASE
    WHEN ((
      SELECT count(*) AS count
      FROM public.plantilla_store_links psl
      WHERE psl.plantilla_id = p.id
        AND psl.deleted_at IS NULL
        AND psl.status = 'Active'::text
    )) > 1 THEN 'Roving'::text
    ELSE COALESCE(p.deployment_type, 'Stationary'::text)
  END AS derived_employment_type,
  p.emploc_no,
  p.rest_day,
  -- 3. assigned_hrco_user_id: User Management as authoritative Source of Truth
  COALESCE(
    (
      SELECT us_acc.user_id
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
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
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    pha.hrco_user_id
  ) AS assigned_hrco_user_id,
  -- 4. assigned_hrco_name: User Management as authoritative Source of Truth
  COALESCE(
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = p.account_id
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
      JOIN public.accounts acc ON acc.id = p.account_id
      WHERE us_grp.group_id = acc.group_id
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    pha.hrco_name_snapshot
  ) AS assigned_hrco_name,
  pha.hrco_email_snapshot AS assigned_hrco_email,
  pha.effective_start AS assigned_hrco_date
FROM public.plantilla p
LEFT JOIN public.stores s ON s.id = p.store_id
LEFT JOIN public.plantilla_hrco_assignments pha ON pha.plantilla_id = p.id AND pha.is_active
WHERE p.is_deleted = false
  AND (p.is_archived = false OR p.is_archived IS NULL);

ALTER VIEW public.v_plantilla_safe OWNER TO postgres;
GRANT SELECT ON public.v_plantilla_safe TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. Initial Synchronization of accounts.hrco_user_id from User Management
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN SELECT id FROM public.accounts WHERE is_active = true LOOP
    PERFORM public.fn_reevaluate_hrco_auto_tags(rec.id);
  END LOOP;
END $$;
