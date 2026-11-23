-- ============================================================================
-- Migration: 20262606000138_fix_plantilla_deactivation_status_and_rpcs.sql
-- Prompt ID: ohm#fix-plantilla-deactivation-status-check
-- Date:      2026-11-23
-- Purpose:   (1) Expand plantilla_status_check constraint to include 'For Deactivation'
--                alongside 'Pending Deactivation' to permanently eliminate check constraint
--                violations across all legacy and current caller paths.
--            (2) Fix public.create_deactivation_request scope check where
--                v_row.account_id::text was compared against get_my_allowed_accounts()
--                (which returns account names, not UUIDs), causing Ops-scoped callers
--                to fail and prematurely fall back to legacy RPCs.
--            (3) Add optional p_reason text DEFAULT NULL to create_deactivation_request
--                and persist deactivation_reason/remarks and timestamps on plantilla.
--            (4) Fix public.plantilla_request_deactivation to write status = 'Pending Deactivation'
--                and synchronize with public.employee_deactivation_requests.
--            (5) Support 'Pending Deactivation' in complete_employee_deactivation and
--                get_plantilla_employees status filters.
-- ============================================================================

-- ── 1. Expand plantilla_status_check constraint ─────────────────────────────
ALTER TABLE public.plantilla
  DROP CONSTRAINT IF EXISTS plantilla_status_check;

ALTER TABLE public.plantilla
  ADD CONSTRAINT plantilla_status_check
  CHECK (status = ANY (ARRAY[
    'Active'::text,
    'Inactive'::text,
    'Pending Deactivation'::text,
    'For Deactivation'::text,
    'Rejected Deactivation'::text,
    'Deactivated'::text,
    'On Leave'::text
  ])) NOT VALID;

-- ── 2. Update create_deactivation_request RPC ───────────────────────────────
CREATE OR REPLACE FUNCTION public.create_deactivation_request(
  p_plantilla_id  uuid,
  p_reason        text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id         uuid;
  v_row               public.plantilla;
  v_existing_req_id   uuid;
  v_new_req_id        uuid;
  v_group_id          uuid;
BEGIN
  -- ── Auth guard ───────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Ops role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Lock and load plantilla row ──────────────────────────────
  SELECT * INTO v_row
    FROM public.plantilla
   WHERE id = p_plantilla_id
     AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plantilla row not found or already deleted: %', p_plantilla_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Scope check (account name or account_id text against allowed accounts) ─
  IF NOT public.i_have_full_access() THEN
    IF NOT (
      v_row.account = ANY(public.get_my_allowed_accounts())
      OR (v_row.account_id IS NOT NULL AND v_row.account_id::text = ANY(public.get_my_allowed_accounts()))
    ) THEN
      RAISE EXCEPTION 'Account not in caller scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Status check ─────────────────────────────────────────────
  -- Idempotent: if already Pending Deactivation or For Deactivation, return existing request
  IF v_row.status IN ('Pending Deactivation', 'For Deactivation') THEN
    SELECT id INTO v_existing_req_id
      FROM public.employee_deactivation_requests
     WHERE plantilla_id = p_plantilla_id
       AND status = 'Pending'
       AND is_archived = false
     LIMIT 1;

    -- Update reason/remarks if provided
    IF p_reason IS NOT NULL AND TRIM(p_reason) <> '' THEN
      UPDATE public.plantilla SET
        deactivation_reason = COALESCE(NULLIF(TRIM(p_reason), ''), deactivation_reason),
        remarks             = COALESCE(NULLIF(TRIM(p_reason), ''), remarks),
        updated_at          = NOW(),
        updated_by          = v_caller_id
      WHERE id = p_plantilla_id;
    END IF;

    RETURN jsonb_build_object(
      'request_id',  v_existing_req_id,
      'plantilla_id', p_plantilla_id,
      'status', 'Pending',
      'idempotent', true
    );
  END IF;

  -- Allow Inactive (first-time request) and Rejected Deactivation (resubmission).
  -- Block Deactivated, Active, and any other status.
  IF v_row.status NOT IN ('Inactive', 'Rejected Deactivation') THEN
    RAISE EXCEPTION 'Employee must be Inactive or Rejected Deactivation to request deactivation. Current status: %',
      v_row.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Resolve group_id ─────────────────────────────────────────
  SELECT group_id INTO v_group_id
    FROM public.user_scopes
   WHERE user_id = v_caller_id
   LIMIT 1;

  IF v_group_id IS NULL THEN
    SELECT COALESCE(up.group_id, a.group_id) INTO v_group_id
      FROM public.users_profile up
      LEFT JOIN public.accounts a ON a.id = v_row.account_id
     WHERE up.id = v_caller_id;
  END IF;

  -- ── Idempotent check: abort early if a Pending request exists ─
  SELECT id INTO v_existing_req_id
    FROM public.employee_deactivation_requests
   WHERE plantilla_id = p_plantilla_id
     AND status = 'Pending'
     AND is_archived = false
   LIMIT 1;

  IF v_existing_req_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'request_id',   v_existing_req_id,
      'plantilla_id', p_plantilla_id,
      'status',       'Pending',
      'idempotent',   true
    );
  END IF;

  -- ── Create request ───────────────────────────────────────────
  INSERT INTO public.employee_deactivation_requests (
    plantilla_id,
    requestor_profile_id,
    group_id,
    account_id,
    employee_name,
    employee_no,
    account_name,
    status
  ) VALUES (
    p_plantilla_id,
    v_caller_id,
    v_group_id,
    v_row.account_id,
    v_row.employee_name,
    v_row.employee_no,
    v_row.account,
    'Pending'
  )
  RETURNING id INTO v_new_req_id;

  -- ── Update plantilla status ──────────────────────────────────
  UPDATE public.plantilla SET
    status                 = 'Pending Deactivation',
    for_deactivation_at    = NOW(),
    for_deactivation_by    = v_caller_id,
    deactivation_reason    = COALESCE(NULLIF(TRIM(p_reason), ''), deactivation_reason),
    remarks                = COALESCE(NULLIF(TRIM(p_reason), ''), remarks),
    inactive_visible_until = NOW() + INTERVAL '30 days',
    updated_at             = NOW(),
    updated_by             = v_caller_id
  WHERE id = p_plantilla_id;

  -- ── Audit log ────────────────────────────────────────────────
  INSERT INTO public.employee_deactivation_audit_log (
    request_id,
    plantilla_id,
    action,
    performed_by_profile_id,
    metadata
  ) VALUES (
    v_new_req_id,
    p_plantilla_id,
    'REQUEST_CREATED',
    v_caller_id,
    jsonb_build_object(
      'employee_name', v_row.employee_name,
      'reason', p_reason
    )
  );

  RETURN jsonb_build_object(
    'request_id',  v_new_req_id,
    'plantilla_id', p_plantilla_id,
    'status', 'Pending',
    'idempotent', false
  );

EXCEPTION
  WHEN unique_violation THEN
    -- Race condition safety net: unique index blocked the insert
    SELECT id INTO v_existing_req_id
      FROM public.employee_deactivation_requests
     WHERE plantilla_id = p_plantilla_id
       AND status = 'Pending'
       AND is_archived = false
     LIMIT 1;

    RETURN jsonb_build_object(
      'request_id',  v_existing_req_id,
      'plantilla_id', p_plantilla_id,
      'status', 'Pending',
      'idempotent', true
    );
END;
$$;

REVOKE ALL ON FUNCTION public.create_deactivation_request(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_deactivation_request(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_deactivation_request(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_deactivation_request(uuid, text) TO service_role;

-- Backward-compatible 1-arg wrapper overload for Mobile callers
CREATE OR REPLACE FUNCTION public.create_deactivation_request(
  p_plantilla_id  uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.create_deactivation_request(p_plantilla_id, NULL::text);
$$;

REVOKE ALL ON FUNCTION public.create_deactivation_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_deactivation_request(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_deactivation_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_deactivation_request(uuid) TO service_role;

-- ── 3. Update plantilla_request_deactivation RPC ────────────────────────────
CREATE OR REPLACE FUNCTION public.plantilla_request_deactivation(
  p_plantilla_id uuid,
  p_reason text DEFAULT NULL::text
)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_row public.plantilla;
  v_profile_id uuid;
  v_group_id uuid;
  v_existing_req_id uuid;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'request_deact') THEN
    RAISE EXCEPTION 'forbidden: Ops role required for deactivation request'
      USING errcode = '42501';
  END IF;

  v_profile_id := public.get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'current user profile not found; cannot request deactivation'
      USING errcode = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.plantilla
  WHERE id = p_plantilla_id
    AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found';
  END IF;

  IF lower(trim(COALESCE(v_row.status, ''))) = 'active' THEN
    RAISE EXCEPTION 'cannot request deactivation for an Active employee; separate first';
  END IF;

  IF lower(trim(COALESCE(v_row.status, ''))) = 'deactivated' THEN
    RAISE EXCEPTION 'employee is already deactivated';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (
       v_row.account = ANY(public.get_my_allowed_accounts())
       OR (v_row.account_id IS NOT NULL AND v_row.account_id::text = ANY(public.get_my_allowed_accounts()))
     ) THEN
    RAISE EXCEPTION 'forbidden: account out of scope'
      USING errcode = '42501';
  END IF;

  -- Idempotent check: if already pending, return row directly
  IF v_row.status IN ('Pending Deactivation', 'For Deactivation') THEN
    RETURN v_row;
  END IF;

  -- Update plantilla to Pending Deactivation
  UPDATE public.plantilla
  SET status                 = 'Pending Deactivation',
      for_deactivation_at    = NOW(),
      for_deactivation_by    = v_profile_id,
      deactivation_reason    = COALESCE(NULLIF(TRIM(p_reason), ''), deactivation_reason),
      remarks                = COALESCE(NULLIF(TRIM(p_reason), ''), remarks),
      inactive_visible_until = NOW() + INTERVAL '30 days',
      updated_by             = v_profile_id,
      updated_at             = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  -- Also ensure employee_deactivation_requests has a pending record for Approvals queue
  SELECT id INTO v_existing_req_id
    FROM public.employee_deactivation_requests
   WHERE plantilla_id = p_plantilla_id
     AND status = 'Pending'
     AND is_archived = false
   LIMIT 1;

  IF v_existing_req_id IS NULL AND v_row.account_id IS NOT NULL THEN
    SELECT group_id INTO v_group_id
      FROM public.user_scopes
     WHERE user_id = v_profile_id
     LIMIT 1;

    IF v_group_id IS NULL THEN
      SELECT COALESCE(up.group_id, a.group_id) INTO v_group_id
        FROM public.users_profile up
        LEFT JOIN public.accounts a ON a.id = v_row.account_id
       WHERE up.id = v_profile_id;
    END IF;

    INSERT INTO public.employee_deactivation_requests (
      plantilla_id,
      requestor_profile_id,
      group_id,
      account_id,
      employee_name,
      employee_no,
      account_name,
      status
    ) VALUES (
      p_plantilla_id,
      v_profile_id,
      v_group_id,
      v_row.account_id,
      v_row.employee_name,
      v_row.employee_no,
      v_row.account,
      'Pending'
    )
    ON CONFLICT DO NOTHING;
  END IF;

  PERFORM public._log_employee_action(
    p_plantilla_id,
    'REQUEST_DEACTIVATION',
    format('Deactivation requested for %s', v_row.employee_name),
    NULL,
    jsonb_build_object(
      'status', 'Pending Deactivation',
      'reason', p_reason
    )
  );

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.plantilla_request_deactivation(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.plantilla_request_deactivation(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.plantilla_request_deactivation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.plantilla_request_deactivation(uuid, text) TO service_role;

-- ── 4. Update complete_employee_deactivation RPC ────────────────────────────
CREATE OR REPLACE FUNCTION public.complete_employee_deactivation(
  p_plantilla_id uuid,
  p_remarks text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_old plantilla%ROWTYPE;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'complete_deact') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_old FROM public.plantilla WHERE id = p_plantilla_id FOR UPDATE;
  IF v_old.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plantilla_not_found');
  END IF;

  IF v_old.status NOT IN ('For Deactivation', 'Pending Deactivation') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'must_be_for_deactivation', 'current_status', v_old.status);
  END IF;

  UPDATE public.plantilla
  SET status                    = 'Deactivated',
      deactivated_at            = NOW(),
      deactivated_by            = public.get_current_profile_id(),
      deactivated_visible_until = NOW() + INTERVAL '15 days',
      inactive_visible_until    = NULL,
      remarks                   = COALESCE(p_remarks, remarks),
      updated_at                = NOW(),
      updated_by                = public.get_current_profile_id()
  WHERE id = p_plantilla_id;

  -- Also update corresponding pending request in employee_deactivation_requests
  UPDATE public.employee_deactivation_requests
  SET status                  = 'Approved',
      processed_by_profile_id = public.get_current_profile_id(),
      processed_at            = NOW(),
      updated_at              = NOW()
  WHERE plantilla_id = p_plantilla_id
    AND status = 'Pending';

  PERFORM public.fn_sync_slot_to_open(
    p_plantilla_id => p_plantilla_id,
    p_reason_code  => 'RESIGNED',
    p_performed_by => public.get_current_profile_id(),
    p_source_fn    => 'complete_employee_deactivation'
  );

  PERFORM public._log_employee_action(
    p_plantilla_id, 'DEACTIVATION_COMPLETED',
    format('Deactivation completed for %s', v_old.employee_name),
    to_jsonb(v_old),
    jsonb_build_object('status', 'Deactivated', 'visible_until', NOW() + INTERVAL '15 days', 'remarks', p_remarks)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'plantilla_id', p_plantilla_id,
    'new_status', 'Deactivated',
    'visible_until', NOW() + INTERVAL '15 days'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_employee_deactivation(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_employee_deactivation(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.complete_employee_deactivation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_employee_deactivation(uuid, text) TO service_role;

-- ── 5. Update get_plantilla_employees status filters ────────────────────────
CREATE OR REPLACE FUNCTION public.get_plantilla_employees(
  p_store_id uuid,
  p_status_filter text DEFAULT 'all'::text
)
RETURNS TABLE(
  id uuid,
  employee_name text,
  employee_no text,
  emploc_no text,
  vcode text,
  position_name text,
  deployment_type text,
  account text,
  store_name text,
  status text,
  separation_status text,
  inactive_at timestamp with time zone,
  for_deactivation_at timestamp with time zone,
  deactivated_at timestamp with time zone,
  deactivated_visible_until timestamp with time zone,
  sla_status text,
  sla_due_date date,
  can_reassign_store boolean,
  can_resign boolean,
  can_endo boolean,
  can_separate boolean,
  can_request_deactivation boolean,
  can_complete_deactivation boolean,
  can_view_benefits boolean,
  can_sync_mika boolean,
  can_reveal_benefits boolean,
  area_city text,
  area_province text,
  derived_employment_type text,
  assigned_hrco_user_id uuid,
  assigned_hrco_name text,
  assigned_hrco_email text,
  assigned_hrco_date timestamp with time zone
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role          text    := public.get_my_role();
  v_is_ops        boolean := public.i_am_ops();
  v_is_full       boolean := public.i_have_full_access();
  v_is_backoffice boolean := v_role IN ('Back Office', 'Backoffice');
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.employee_name,
    p.employee_no,
    p.emploc_no,
    p.vcode,
    p.position::text,
    p.deployment_type,
    p.account,
    p.store_name,
    p.status,
    p.separation_status,
    p.inactive_at,
    p.for_deactivation_at,
    p.deactivated_at,
    p.deactivated_visible_until,
    -- SLA status
    CASE
      WHEN p.status = 'Inactive' AND p.inactive_at < NOW() - INTERVAL '3 days'
        THEN 'breach_inactive_no_request'
      WHEN p.status IN ('For Deactivation', 'Pending Deactivation') AND p.for_deactivation_at < NOW() - INTERVAL '3 days'
        THEN 'breach_deactivation_overdue'
      WHEN p.status IN ('Inactive', 'For Deactivation', 'Pending Deactivation') THEN 'within_sla'
      ELSE NULL
    END,
    -- SLA due date
    CASE
      WHEN p.status = 'Inactive'         THEN (p.inactive_at + INTERVAL '3 days')::date
      WHEN p.status IN ('For Deactivation', 'Pending Deactivation') THEN (p.for_deactivation_at + INTERVAL '3 days')::date
      ELSE NULL
    END,
    -- can_reassign_store: Active and On Leave employees
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_resign
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_endo
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_separate
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_request_deactivation: Inactive employees
    (v_is_full OR (v_is_ops AND p.status IN ('Inactive', 'Rejected Deactivation'))),
    -- can_complete_deactivation: Backoffice for For Deactivation / Pending Deactivation
    ((v_is_backoffice OR v_is_full) AND p.status IN ('For Deactivation', 'Pending Deactivation')),
    true,
    (v_is_full OR v_is_ops OR v_is_backoffice),
    (v_is_full OR v_is_ops OR v_is_backoffice),
    s.area_city::text,
    COALESCE(s.area_province, s.province)::text,
    CASE
      WHEN (
        SELECT COUNT(*)
          FROM public.plantilla_store_links psl
         WHERE psl.plantilla_id = p.id
           AND psl.deleted_at IS NULL
           AND psl.status = 'Active'
      ) > 1
      THEN 'Roving'
      ELSE COALESCE(p.deployment_type, 'Stationary')
    END AS derived_employment_type,
    -- Assigned HRCO fields
    pha.hrco_user_id AS assigned_hrco_user_id,
    pha.hrco_name_snapshot AS assigned_hrco_name,
    pha.hrco_email_snapshot AS assigned_hrco_email,
    pha.effective_start AS assigned_hrco_date
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  LEFT JOIN public.plantilla_hrco_assignments pha ON pha.plantilla_id = p.id AND pha.is_active
  WHERE p.store_id = p_store_id
    AND (
      v_is_full
      OR p.account = ANY (public.get_my_allowed_accounts())
    )
    AND (
      CASE LOWER(p_status_filter)
        WHEN 'all'                  THEN p.status IN ('Active', 'On Leave', 'Inactive', 'For Deactivation', 'Pending Deactivation', 'Deactivated')
                                         AND (p.status <> 'Deactivated'
                                              OR p.deactivated_visible_until > NOW())
        WHEN 'active'               THEN p.status = 'Active'
        WHEN 'on_leave'             THEN p.status = 'On Leave'
        WHEN 'on leave'             THEN p.status = 'On Leave'
        WHEN 'floating'             THEN (p.status = 'Floating' OR p.separation_status = 'Floating')
                                         AND p.source_headcount_request_id IS NULL
        WHEN 'inactive'             THEN p.status IN ('Inactive', 'For Deactivation', 'Pending Deactivation', 'Deactivated')
                                         AND COALESCE(p.separation_status, '') <> 'Floating'
                                         AND p.status <> 'Floating'
                                         AND p.source_headcount_request_id IS NULL
        WHEN 'for_deactivation'     THEN p.status IN ('For Deactivation', 'Pending Deactivation')
        WHEN 'pending_deactivation' THEN p.status IN ('For Deactivation', 'Pending Deactivation')
        WHEN 'deactivated'          THEN p.status = 'Deactivated'
                                         AND p.deactivated_visible_until > NOW()
        ELSE true
      END
    )
  ORDER BY
    CASE p.status
      WHEN 'Active'                 THEN 1
      WHEN 'On Leave'               THEN 2
      WHEN 'Inactive'               THEN 3
      WHEN 'For Deactivation'       THEN 4
      WHEN 'Pending Deactivation'   THEN 4
      WHEN 'Deactivated'            THEN 5
      ELSE 6
    END,
    p.employee_name;
END;
$function$;
