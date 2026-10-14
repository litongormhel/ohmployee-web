-- Migration: 20262606000030_add_dashboard_metrics_and_analytics_rpcs
-- Purpose: Provide fn_dashboard_metrics and fn_dashboard_operational_analytics RPCs
--          for cross-module KPIs, operational analytics, and security metrics.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_dashboard_metrics(
  p_account_id uuid DEFAULT NULL,
  p_group_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_uid            uuid := auth.uid();
  v_role_level          integer;
  v_is_admin            boolean;
  v_allowed_acc_ids     uuid[];

  v_open_vacancies      bigint := 0;
  v_emploc_pending      bigint := 0;
  v_active_plantilla    bigint := 0;
  v_understaffed_stores bigint := 0;
  v_active_sla_breaches bigint := 0;
  v_pending_approvals   bigint := NULL;
  v_security_event_count bigint := NULL;
BEGIN
  IF v_auth_uid IS NULL THEN
    IF (auth.jwt() ->> 'role') = 'service_role' OR session_user = 'postgres' THEN
      v_is_admin := true;
    ELSE
      RAISE EXCEPTION 'unauthenticated: dashboard metrics requires a valid session'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    v_role_level := COALESCE(public.get_my_role_level(), 0);
    v_is_admin := (v_role_level >= 90);

    IF NOT EXISTS (
      SELECT 1 FROM public.users_profile
      WHERE auth_user_id = v_auth_uid
        AND is_active = true
        AND archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: dashboard caller is not authorized'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Determine account filtering scope
  IF v_is_admin THEN
    IF p_account_id IS NOT NULL THEN
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(id) INTO v_allowed_acc_ids
      FROM public.accounts
      WHERE group_id = p_group_id AND is_active = true;
    ELSE
      v_allowed_acc_ids := NULL; -- All accounts
    END IF;
  ELSE
    v_allowed_acc_ids := public.get_my_allowed_account_ids();
    IF p_account_id IS NOT NULL THEN
      IF NOT (p_account_id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]))) THEN
        RAISE EXCEPTION 'forbidden: account is out of scope' USING ERRCODE = '42501';
      END IF;
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(a.id) INTO v_allowed_acc_ids
      FROM public.accounts a
      WHERE a.group_id = p_group_id
        AND a.is_active = true
        AND a.id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]));
    END IF;
  END IF;

  -- 1. Open Vacancies
  SELECT count(*)::bigint INTO v_open_vacancies
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  -- 2. HR Emploc Pending
  SELECT count(*)::bigint INTO v_emploc_pending
  FROM public.hr_emploc h
  WHERE h.deleted_at IS NULL
    AND h.hr_status IN ('Pending', 'For Correction', 'For Review')
    AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids));

  -- 3. Active Plantilla
  SELECT count(*)::bigint INTO v_active_plantilla
  FROM public.plantilla p
  WHERE p.status = 'Active'
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  -- 4. Under-Staffed Stores (stores with open vacancies)
  SELECT count(DISTINCT v.store_id)::bigint INTO v_understaffed_stores
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND v.store_id IS NOT NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  -- 5. Active SLA Breaches
  IF v_allowed_acc_ids IS NULL THEN
    SELECT count(*)::bigint INTO v_active_sla_breaches
    FROM public.sla_breach_logs;
  ELSE
    SELECT count(*)::bigint INTO v_active_sla_breaches
    FROM public.sla_breach_logs s
    WHERE s.account = ANY(public.get_my_allowed_accounts());
  END IF;

  -- 6. Security KPIs: Pending Approvals & Security Events (Admin-only)
  IF v_is_admin THEN
    SELECT (
      COALESCE((SELECT count(*) FROM public.account_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.applicant_movement_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.coverage_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.deactivation_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.hr_emploc_deletion_requests WHERE status::text ILIKE 'pending'), 0)
    )::bigint INTO v_pending_approvals;

    SELECT (
      COALESCE((SELECT count(*) FROM public.security_audit_logs WHERE created_at >= CURRENT_DATE), 0) +
      COALESCE((SELECT count(*) FROM public.security_events WHERE happened_at >= CURRENT_DATE), 0)
    )::bigint INTO v_security_event_count;
  ELSE
    v_pending_approvals := NULL;
    v_security_event_count := NULL;
  END IF;

  RETURN jsonb_build_object(
    'total_open_vacancies', v_open_vacancies,
    'total_hr_emploc_pending', v_emploc_pending,
    'total_active_plantilla', v_active_plantilla,
    'understaffed_stores', v_understaffed_stores,
    'active_sla_breaches', v_active_sla_breaches,
    'pending_approvals', v_pending_approvals,
    'security_event_count', v_security_event_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_dashboard_metrics(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_dashboard_metrics(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_dashboard_operational_analytics(
  p_account_id uuid DEFAULT NULL,
  p_group_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_uid            uuid := auth.uid();
  v_role_level          integer;
  v_is_admin            boolean;
  v_allowed_acc_ids     uuid[];

  v_pipeline_total      bigint := 0;
  v_hires_this_month    bigint := 0;
  v_separations_month   bigint := 0;
  v_actual_hc           numeric := 0;
  v_hr_pipeline         numeric := 0;
  v_vacant_hc           numeric := 0;
  v_denominator         numeric := 0;
  v_avg_fill_rate       numeric := NULL;
BEGIN
  IF v_auth_uid IS NULL THEN
    IF (auth.jwt() ->> 'role') = 'service_role' OR session_user = 'postgres' THEN
      v_is_admin := true;
    ELSE
      RAISE EXCEPTION 'unauthenticated: dashboard operational analytics requires a valid session'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    v_role_level := COALESCE(public.get_my_role_level(), 0);
    v_is_admin := (v_role_level >= 90);

    IF NOT EXISTS (
      SELECT 1 FROM public.users_profile
      WHERE auth_user_id = v_auth_uid
        AND is_active = true
        AND archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: dashboard caller is not authorized'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Determine account filtering scope
  IF v_is_admin THEN
    IF p_account_id IS NOT NULL THEN
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(id) INTO v_allowed_acc_ids
      FROM public.accounts
      WHERE group_id = p_group_id AND is_active = true;
    ELSE
      v_allowed_acc_ids := NULL; -- All accounts
    END IF;
  ELSE
    v_allowed_acc_ids := public.get_my_allowed_account_ids();
    IF p_account_id IS NOT NULL THEN
      IF NOT (p_account_id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]))) THEN
        RAISE EXCEPTION 'forbidden: account is out of scope' USING ERRCODE = '42501';
      END IF;
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(a.id) INTO v_allowed_acc_ids
      FROM public.accounts a
      WHERE a.group_id = p_group_id
        AND a.is_active = true
        AND a.id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]));
    END IF;
  END IF;

  -- 1. Pipeline Total (Active applicants in pipeline + pending HR Emploc)
  SELECT (
    COALESCE((
      SELECT count(*)
      FROM public.applicants ap
      WHERE COALESCE(ap.is_archived, false) = false
        AND public.fn_is_active_vacancy_applicant_status(ap.status)
        AND (
          v_allowed_acc_ids IS NULL
          OR EXISTS (
            SELECT 1 FROM public.vacancies v
            WHERE v.vcode = ap.vacancy_vcode
              AND v.account_id = ANY(v_allowed_acc_ids)
          )
        )
    ), 0) +
    COALESCE((
      SELECT count(*)
      FROM public.hr_emploc h
      WHERE h.deleted_at IS NULL
        AND h.hr_status IN ('Pending', 'For Correction', 'For Review')
        AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids))
    ), 0)
  )::bigint INTO v_pipeline_total;

  -- 2. Hires This Month
  SELECT (
    COALESCE((
      SELECT count(*)
      FROM public.applicants ap
      WHERE ap.hired_date IS NOT NULL
        AND date_trunc('month', ap.hired_date::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
        AND (
          v_allowed_acc_ids IS NULL
          OR EXISTS (
            SELECT 1 FROM public.vacancies v
            WHERE v.vcode = ap.vacancy_vcode
              AND v.account_id = ANY(v_allowed_acc_ids)
          )
        )
    ), 0) +
    COALESCE((
      SELECT count(*)
      FROM public.hr_emploc h
      WHERE h.hired_date IS NOT NULL
        AND date_trunc('month', h.hired_date::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
        AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids))
    ), 0)
  )::bigint INTO v_hires_this_month;

  -- 3. Separations This Month
  SELECT count(*)::bigint INTO v_separations_month
  FROM public.plantilla p
  WHERE p.date_of_separation IS NOT NULL
    AND date_trunc('month', p.date_of_separation::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  -- 4. Avg Fill Rate: Actual / (Actual + HR Pipeline + Vacancy)
  SELECT count(*)::numeric INTO v_actual_hc
  FROM public.plantilla p
  WHERE p.status = 'Active'
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  SELECT count(*)::numeric INTO v_hr_pipeline
  FROM public.hr_emploc h
  WHERE h.deleted_at IS NULL
    AND h.hr_status = ANY(ARRAY['Pending'::text, 'Complete'::text])
    AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids));

  SELECT count(*)::numeric INTO v_vacant_hc
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  v_denominator := v_actual_hc + v_hr_pipeline + v_vacant_hc;

  IF v_denominator = 0 THEN
    v_avg_fill_rate := 1.0;
  ELSE
    v_avg_fill_rate := round(v_actual_hc / v_denominator, 4);
  END IF;

  RETURN jsonb_build_object(
    'pipeline_total', v_pipeline_total,
    'hires_this_month', v_hires_this_month,
    'separations_this_month', v_separations_month,
    'avg_fill_rate', v_avg_fill_rate
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_dashboard_operational_analytics(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_dashboard_operational_analytics(uuid, uuid) TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
