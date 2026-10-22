-- Migration: 20262606000052_harmonize_dashboard_metrics_and_approvals
-- Purpose: Harmonize fn_dashboard_metrics with the full 11 operational request queues
--          and surface live ghost employee count, unassigned vacancies, and admin security approvals.

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
  v_admin_approvals     bigint := NULL;
  v_security_event_count bigint := NULL;
  v_ghost_employee_count bigint := 0;
  v_unassigned_vacancies bigint := 0;
  v_assigned_vacancies   bigint := 0;
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

  -- 1b. Unassigned vs Assigned Vacancies
  SELECT count(*)::bigint INTO v_unassigned_vacancies
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v.hrco_name IS NULL OR TRIM(v.hrco_name) = '')
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  v_assigned_vacancies := GREATEST(0, v_open_vacancies - v_unassigned_vacancies);

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

  -- 6. Approvals & Security KPIs
  IF v_is_admin THEN
    -- Total operational + administrative pending approvals (all 11 queues)
    SELECT (
      COALESCE((SELECT count(*) FROM public.new_store_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.headcount_requests WHERE is_archived = false AND (status::text ILIKE 'pending' OR status::text ILIKE 'under_review')), 0) +
      COALESCE((SELECT count(*) FROM public.plantilla_approvals WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.account_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.coverage_requests WHERE archived_at IS NULL AND status::text IN ('pending', 'draft')), 0) +
      COALESCE((SELECT count(*) FROM public.v_workforce_assignment_request_queue WHERE status::text ILIKE 'pending' OR status::text ILIKE 'for review'), 0) +
      COALESCE((SELECT count(*) FROM public.vacancy_closure_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.hr_emploc_deletion_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.deactivation_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.applicant_movement_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.account_group_transfer_requests WHERE status::text ILIKE 'pending'), 0)
    )::bigint INTO v_pending_approvals;

    -- Security-only approvals (access provisioning & security exceptions)
    SELECT (
      COALESCE((SELECT count(*) FROM public.account_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.applicant_movement_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.coverage_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.deactivation_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.hr_emploc_deletion_requests WHERE status::text ILIKE 'pending'), 0)
    )::bigint INTO v_admin_approvals;

    SELECT (
      COALESCE((SELECT count(*) FROM public.security_audit_logs WHERE created_at >= CURRENT_DATE), 0) +
      COALESCE((SELECT count(*) FROM public.security_events WHERE happened_at >= CURRENT_DATE), 0)
    )::bigint INTO v_security_event_count;

    SELECT count(*)::bigint INTO v_ghost_employee_count
    FROM public.possible_ghost_employees
    WHERE status NOT IN ('Cleared', 'For Termination');
  ELSE
    v_pending_approvals := NULL;
    v_admin_approvals := NULL;
    v_security_event_count := NULL;
    v_ghost_employee_count := 0;
  END IF;

  RETURN jsonb_build_object(
    'total_open_vacancies', v_open_vacancies,
    'unassigned_vacancies', v_unassigned_vacancies,
    'assigned_vacancies', v_assigned_vacancies,
    'total_hr_emploc_pending', v_emploc_pending,
    'total_active_plantilla', v_active_plantilla,
    'understaffed_stores', v_understaffed_stores,
    'active_sla_breaches', v_active_sla_breaches,
    'pending_approvals', v_pending_approvals,
    'admin_security_approvals', v_admin_approvals,
    'security_event_count', v_security_event_count,
    'ghost_employee_count', v_ghost_employee_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_dashboard_metrics(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_dashboard_metrics(uuid, uuid) TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
