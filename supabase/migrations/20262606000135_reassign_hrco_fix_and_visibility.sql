-- ============================================================================
-- Migration: 20262606000135_reassign_hrco_fix_and_visibility.sql
-- Description: Fixes HRCO reassignment and view visibility.
--   1. Expands fn_can_assign_hrco to include Operations Manager and role level >= 70.
--   2. Updates fn_is_valid_hrco_for_account to match by auth_user_id OR profile id (uuid)
--      and recognize hrco_global_visibility.
--   3. Enhances assign_hrco_to_plantilla and fn_transfer_employee_hrco to update both
--      plantilla_hrco_assignments AND public.plantilla (coordinator, hrco_name)
--      and log an audit event.
--   4. Fixes v_plantilla_safe so that pha.hrco_name_snapshot / pha.hrco_user_id take
--      priority over arbitrary LIMIT 1 user_scopes, enabling multi-HRCO accounts to
--      display employee-specific assigned HRCOs correctly.
--   5. Restores dependent views (vw_plantilla_inactive, v_dashboard_*) dropped on CASCADE.
-- ============================================================================

-- 1. Helper: Can assign HRCO
CREATE OR REPLACE FUNCTION public.fn_can_assign_hrco()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT public.get_effective_role() IN ('Encoder', 'Head Admin', 'Super Admin', 'Operations Manager', 'OM')
      OR public.get_my_role_level() >= 70;
$$;

-- 2. Helper: Validate HRCO for Account
CREATE OR REPLACE FUNCTION public.fn_is_valid_hrco_for_account(p_user_id uuid, p_account_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE (up.auth_user_id = p_user_id OR up.id = p_user_id)
      AND COALESCE(up.is_active, true)
      AND r.role_name = 'HRCO'
      AND (
        up.hrco_global_visibility = true
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = up.id
            AND us.is_active = true
            AND (
              us.account_id = p_account_id
              OR us.group_id = (SELECT group_id FROM public.accounts WHERE id = p_account_id)
            )
        )
      )
  );
$$;

-- 3. RPC: assign_hrco_to_plantilla
CREATE OR REPLACE FUNCTION public.assign_hrco_to_plantilla(
  p_plantilla_id uuid,
  p_hrco_user_id uuid,
  p_reason text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_account_id    uuid;
  v_employee_no   text;
  v_old_hrco      text;
  v_new_id        uuid;
  v_hrco_profile  record;
  v_actor_profile uuid;
BEGIN
  IF NOT public.fn_can_assign_hrco() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, Super Admin, or Operations Manager required' USING ERRCODE = '42501';
  END IF;

  SELECT account_id, employee_no, COALESCE(coordinator, hrco_name)
    INTO v_account_id, v_employee_no, v_old_hrco
    FROM public.plantilla
   WHERE id = p_plantilla_id AND NOT is_deleted
   FOR UPDATE;

  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'plantilla_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.fn_is_valid_hrco_for_account(p_hrco_user_id, v_account_id) THEN
    RAISE EXCEPTION 'invalid_hrco: not an HRCO on this account roster' USING ERRCODE = '22023';
  END IF;

  SELECT up.id, up.auth_user_id, up.full_name, up.email
    INTO v_hrco_profile
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE (up.auth_user_id = p_hrco_user_id OR up.id = p_hrco_user_id)
     AND r.role_name = 'HRCO'
   LIMIT 1;

  IF v_hrco_profile.id IS NULL THEN
    RAISE EXCEPTION 'hrco_profile_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_actor_profile := public.get_current_profile_id();

  -- Deactivate any existing active assignment
  UPDATE public.plantilla_hrco_assignments
     SET is_active = false, effective_end = now()
   WHERE plantilla_id = p_plantilla_id AND is_active;

  -- Insert new active assignment
  INSERT INTO public.plantilla_hrco_assignments (
    plantilla_id, employee_no, account_id, hrco_user_id,
    hrco_email_snapshot, hrco_name_snapshot,
    assigned_by, assignment_source
  )
  VALUES (
    p_plantilla_id,
    v_employee_no,
    v_account_id,
    COALESCE(v_hrco_profile.auth_user_id, v_hrco_profile.id),
    v_hrco_profile.email,
    v_hrco_profile.full_name,
    v_actor_profile,
    'manual'
  )
  RETURNING id INTO v_new_id;

  -- Synchronize direct plantilla master columns
  UPDATE public.plantilla
     SET coordinator = v_hrco_profile.full_name,
         hrco_name   = v_hrco_profile.full_name,
         updated_at  = now()
   WHERE id = p_plantilla_id;

  -- Log audit event safely
  BEGIN
    PERFORM public.log_audit_event(
      'plantilla',
      'reassign_hrco',
      p_plantilla_id,
      jsonb_build_object('coordinator', v_old_hrco),
      jsonb_build_object('coordinator', v_hrco_profile.full_name, 'reason', p_reason)
    );
  EXCEPTION WHEN OTHERS THEN
    -- Prevent audit log failures from rolling back reassignment
    NULL;
  END;

  RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_hrco_to_plantilla(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assign_hrco_to_plantilla(uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.assign_hrco_to_plantilla(uuid, uuid, text) TO authenticated;

-- 4. RPC: Bulk/Single transfer employee HRCO
CREATE OR REPLACE FUNCTION public.fn_transfer_employee_hrco(
  p_plantilla_ids uuid[],
  p_hrco_user_id uuid,
  p_reason text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_plantilla_id uuid;
  v_count        integer := 0;
BEGIN
  FOREACH v_plantilla_id IN ARRAY p_plantilla_ids
  LOOP
    PERFORM public.assign_hrco_to_plantilla(v_plantilla_id, p_hrco_user_id, p_reason);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_transfer_employee_hrco(uuid[], uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_transfer_employee_hrco(uuid[], uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_transfer_employee_hrco(uuid[], uuid, text) TO authenticated;

-- 5. View: v_plantilla_safe (Append-Only column contract preserved, prioritizes pha)
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
  -- 1. Coordinator: prioritize specific employee assignment, then account/group HRCO
  COALESCE(
    pha.hrco_name_snapshot,
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
    p.hrco_name,
    p.coordinator
  ) AS coordinator,
  -- 2. hrco_name: prioritize specific employee assignment, then account/group HRCO
  COALESCE(
    pha.hrco_name_snapshot,
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
  -- 3. assigned_hrco_user_id: prioritize specific employee assignment, then account/group HRCO
  COALESCE(
    pha.hrco_user_id,
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
    )
  ) AS assigned_hrco_user_id,
  -- 4. assigned_hrco_name: prioritize specific employee assignment, then account/group HRCO
  COALESCE(
    pha.hrco_name_snapshot,
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
    )
  ) AS assigned_hrco_name,
  COALESCE(
    pha.hrco_email_snapshot,
    (
      SELECT up_sc.email
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
      SELECT up_scg.email
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
    )
  ) AS assigned_hrco_email,
  pha.effective_start AS assigned_hrco_date
FROM public.plantilla p
LEFT JOIN public.stores s ON s.id = p.store_id
LEFT JOIN public.plantilla_hrco_assignments pha ON pha.plantilla_id = p.id AND pha.is_active
WHERE p.is_deleted = false
  AND (p.is_archived = false OR p.is_archived IS NULL);

ALTER VIEW public.v_plantilla_safe OWNER TO postgres;
ALTER VIEW public.v_plantilla_safe SET (security_invoker = true);
GRANT SELECT ON public.v_plantilla_safe TO authenticated, service_role;

-- 6. Restore dependent views (re-created with security_invoker = true)
CREATE OR REPLACE VIEW public.vw_plantilla_inactive
WITH (security_invoker = true) AS
SELECT vps.*
FROM public.v_plantilla_safe vps
WHERE vps.status <> 'Active'
  AND vps.source_headcount_request_id IS NULL
ORDER BY vps.date_of_separation DESC NULLS LAST,
         vps.employee_name ASC;

GRANT SELECT ON public.vw_plantilla_inactive TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_account_breakdown
  WITH (security_invoker = true)
AS
SELECT
  account,
  COUNT(*) FILTER (WHERE status = 'Active')   AS active,
  COUNT(*) FILTER (WHERE status = 'Resigned') AS resigned
FROM public.v_plantilla_safe
GROUP BY account
HAVING COUNT(*) FILTER (WHERE status IN ('Active', 'Resigned')) > 0
ORDER BY active DESC;

GRANT SELECT ON public.v_dashboard_account_breakdown TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_account_mfr_breakdown
  WITH (security_invoker = true)
AS
 WITH active_agg AS (
         SELECT v_plantilla_safe.account,
            count(*) AS active
           FROM v_plantilla_safe
          WHERE v_plantilla_safe.status = 'Active'::text AND v_plantilla_safe.account IS NOT NULL AND TRIM(BOTH FROM v_plantilla_safe.account) <> ''::text
          GROUP BY v_plantilla_safe.account
        ), pipeline_agg AS (
         SELECT hr_emploc.account,
            count(*) AS pipeline
           FROM hr_emploc
          WHERE (hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])) AND hr_emploc.deleted_at IS NULL AND hr_emploc.account IS NOT NULL AND TRIM(BOTH FROM hr_emploc.account) <> ''::text
          GROUP BY hr_emploc.account
        ), vac_agg AS (
         SELECT vw_slot_derived_vacancy_shadow.account_name AS account,
            count(*) AS vacancies
           FROM vw_slot_derived_vacancy_shadow
          WHERE (vw_slot_derived_vacancy_shadow.open_count - vw_slot_derived_vacancy_shadow.pipeline_count - vw_slot_derived_vacancy_shadow.hr_processing_count) > 0 AND vw_slot_derived_vacancy_shadow.account_name IS NOT NULL AND TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.account_name) <> ''::text
          GROUP BY vw_slot_derived_vacancy_shadow.account_name
        ), all_accounts AS (
         SELECT active_agg.account
           FROM active_agg
        UNION
         SELECT pipeline_agg.account
           FROM pipeline_agg
        UNION
         SELECT vac_agg.account
           FROM vac_agg
        )
 SELECT aa.account,
    COALESCE(a.active, 0::bigint) AS active,
    COALESCE(p.pipeline, 0::bigint) AS pipeline,
    COALESCE(v.vacancies, 0::bigint) AS vacancies,
    COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint) AS required,
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint))::numeric
            ELSE 1.0
        END AS mfr
   FROM all_accounts aa
     LEFT JOIN active_agg a ON a.account = aa.account
     LEFT JOIN pipeline_agg p ON p.account = aa.account
     LEFT JOIN vac_agg v ON v.account = aa.account
  ORDER BY (
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint))::numeric
            ELSE 1.0
        END), aa.account;

GRANT SELECT ON public.v_dashboard_account_mfr_breakdown TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_hrco_breakdown
  WITH (security_invoker = true)
AS
 WITH active_agg AS (
         SELECT v_plantilla_safe.hrco_name AS hrco,
            count(*) AS active
           FROM v_plantilla_safe
          WHERE v_plantilla_safe.status = 'Active'::text AND v_plantilla_safe.hrco_name IS NOT NULL AND TRIM(BOTH FROM v_plantilla_safe.hrco_name) <> ''::text
          GROUP BY v_plantilla_safe.hrco_name
        ), pipeline_agg AS (
         SELECT hr_emploc.hrco_name AS hrco,
            count(*) AS pipeline
           FROM hr_emploc
          WHERE (hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])) AND hr_emploc.deleted_at IS NULL AND hr_emploc.hrco_name IS NOT NULL AND TRIM(BOTH FROM hr_emploc.hrco_name) <> ''::text
          GROUP BY hr_emploc.hrco_name
        ), vac_agg AS (
         SELECT COALESCE(NULLIF(TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.hrco_name), ''::text), 'Unassigned'::text) AS hrco,
            count(*) AS vacant
           FROM vw_slot_derived_vacancy_shadow
          WHERE (vw_slot_derived_vacancy_shadow.open_count - vw_slot_derived_vacancy_shadow.pipeline_count - vw_slot_derived_vacancy_shadow.hr_processing_count) > 0
          GROUP BY (COALESCE(NULLIF(TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.hrco_name), ''::text), 'Unassigned'::text))
        ), all_hrco AS (
         SELECT active_agg.hrco
           FROM active_agg
        UNION
         SELECT pipeline_agg.hrco
           FROM pipeline_agg
        UNION
         SELECT vac_agg.hrco
           FROM vac_agg
        )
 SELECT ah.hrco,
    COALESCE(v.vacant, 0::bigint) AS vacant,
    COALESCE(a.active, 0::bigint) AS active,
    COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint) AS required,
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint))::numeric
            ELSE 1.0
        END AS mfr
   FROM all_hrco ah
     LEFT JOIN active_agg a ON a.hrco = ah.hrco
     LEFT JOIN pipeline_agg p ON p.hrco = ah.hrco
     LEFT JOIN vac_agg v ON v.hrco = ah.hrco
  ORDER BY (
        CASE
            WHEN ah.hrco = 'Unassigned'::text THEN 1
            ELSE 0
        END), ah.hrco;

GRANT SELECT ON public.v_dashboard_hrco_breakdown TO authenticated, service_role;
