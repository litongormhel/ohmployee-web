-- ============================================================
-- Production Readiness Blocker #1
-- Coverage Request RBAC hardening
--
-- Scope:
--   - Backend-enforce create/submit/cancel roles:
--       Encoder, Head Admin, Super Admin
--   - Backend-enforce approve/reject roles:
--       Head Admin, Super Admin
--   - Re-assert Coverage Request table RLS as read-only from client roles.
--   - Revoke function EXECUTE from PUBLIC/anon and grant only the required
--     Supabase API role. App-role authorization remains inside the RPCs.
-- ============================================================

-- ------------------------------------------------------------
-- §1. Coverage Request RBAC predicates
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_can_mutate_coverage_request()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public.i_have_full_access() OR public.get_my_role() = 'Encoder';
$fn$;

COMMENT ON FUNCTION public.fn_can_mutate_coverage_request() IS
  'TRUE for Encoder, Head Admin, or Super Admin. Backend gate for Coverage Request create, submit, and cancel.';

CREATE OR REPLACE FUNCTION public.fn_can_review_coverage_request()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public.i_have_full_access();
$fn$;

COMMENT ON FUNCTION public.fn_can_review_coverage_request() IS
  'TRUE for Head Admin or Super Admin only. Backend gate for Coverage Request approve and reject.';

-- ------------------------------------------------------------
-- §2. Re-assert table RLS posture
-- ------------------------------------------------------------

ALTER TABLE public.coverage_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coverage_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE public.coverage_request_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coverage_request_history FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.coverage_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.coverage_request_history FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.coverage_requests TO authenticated;
GRANT SELECT ON TABLE public.coverage_request_history TO authenticated;

DROP POLICY IF EXISTS coverage_requests_read_scoped ON public.coverage_requests;
CREATE POLICY coverage_requests_read_scoped
  ON public.coverage_requests
  FOR SELECT
  TO authenticated
  USING (
    (
      public.i_have_full_access()
      OR public.get_my_role() = 'Encoder'
    )
    AND (
      public.i_have_full_access()
      OR requested_by = public.get_current_profile_id()
      OR account_id = ANY (public.get_my_allowed_account_ids())
      OR EXISTS (
        SELECT 1
        FROM public.coverage_groups cg
        WHERE cg.id IN (
          coverage_requests.target_coverage_group_id,
          coverage_requests.source_coverage_group_id,
          coverage_requests.destination_coverage_group_id
        )
          AND cg.account_id = ANY (public.get_my_allowed_account_ids())
      )
    )
  );

DROP POLICY IF EXISTS coverage_request_history_read_scoped ON public.coverage_request_history;
CREATE POLICY coverage_request_history_read_scoped
  ON public.coverage_request_history
  FOR SELECT
  TO authenticated
  USING (
    (
      public.i_have_full_access()
      OR public.get_my_role() = 'Encoder'
    )
    AND EXISTS (
      SELECT 1
      FROM public.coverage_requests cr
      WHERE cr.id = coverage_request_history.coverage_request_id
    )
  );

COMMENT ON POLICY coverage_requests_read_scoped ON public.coverage_requests IS
  'Read-only visibility for Encoder, Head Admin, and Super Admin only. Encoder remains scoped; HA/SA have full access. No direct INSERT/UPDATE/DELETE policies exist; Coverage Request mutations must go through RBAC-gated SECURITY DEFINER RPCs.';

COMMENT ON POLICY coverage_request_history_read_scoped ON public.coverage_request_history IS
  'Read-only history visibility for Encoder, Head Admin, and Super Admin only, through parent Coverage Request scope. No direct INSERT/UPDATE/DELETE policies exist.';

-- ------------------------------------------------------------
-- §3. Lifecycle RPCs: create / submit / cancel
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_coverage_request(
  p_request_type public.request_type,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_account_id uuid DEFAULT NULL,
  p_position_id uuid DEFAULT NULL,
  p_employment_type text DEFAULT NULL,
  p_target_coverage_group_id uuid DEFAULT NULL,
  p_source_coverage_group_id uuid DEFAULT NULL,
  p_destination_coverage_group_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request_id uuid;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.fn_can_mutate_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only Encoder, Head Admin, or Super Admin can create Coverage Requests'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public._validate_coverage_request_payload(
    p_request_type,
    COALESCE(p_payload, '{}'::jsonb),
    p_account_id,
    p_position_id,
    p_employment_type,
    p_target_coverage_group_id,
    p_source_coverage_group_id,
    p_destination_coverage_group_id
  );

  INSERT INTO public.coverage_requests (
    request_type,
    status,
    account_id,
    position_id,
    employment_type,
    target_coverage_group_id,
    source_coverage_group_id,
    destination_coverage_group_id,
    payload,
    reason,
    requested_by,
    requested_by_name,
    requested_by_role,
    created_by,
    updated_by
  ) VALUES (
    p_request_type,
    'draft'::public.request_status,
    p_account_id,
    p_position_id,
    NULLIF(TRIM(COALESCE(p_employment_type, '')), ''),
    p_target_coverage_group_id,
    p_source_coverage_group_id,
    p_destination_coverage_group_id,
    COALESCE(p_payload, '{}'::jsonb),
    NULLIF(TRIM(COALESCE(p_reason, '')), ''),
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    v_actor.profile_id,
    v_actor.profile_id
  )
  RETURNING id INTO v_request_id;

  PERFORM public._log_coverage_request_history(
    v_request_id,
    NULL,
    'draft'::public.request_status,
    'created',
    jsonb_build_object('request_type', p_request_type),
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    p_reason
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'coverage_request_id', v_request_id,
    'request_status', 'draft'
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.submit_coverage_request(
  p_coverage_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.fn_can_mutate_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only Encoder, Head Admin, or Super Admin can submit Coverage Requests'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'draft'::public.request_status THEN
    RAISE EXCEPTION 'coverage request can only be submitted from draft status'
      USING ERRCODE = '22023';
  END IF;

  IF v_request.requested_by <> v_actor.profile_id
     AND NOT public.fn_can_review_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only the requester or HA/SA can submit this draft'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public._validate_coverage_request_payload(
    v_request.request_type,
    v_request.payload,
    v_request.account_id,
    v_request.position_id,
    v_request.employment_type,
    v_request.target_coverage_group_id,
    v_request.source_coverage_group_id,
    v_request.destination_coverage_group_id
  );

  UPDATE public.coverage_requests
  SET status = 'pending'::public.request_status,
      submitted_by = v_actor.profile_id,
      submitted_by_name = v_actor.full_name,
      submitted_at = now(),
      updated_by = v_actor.profile_id,
      updated_at = now()
  WHERE id = p_coverage_request_id;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    'draft'::public.request_status,
    'pending'::public.request_status,
    'submitted',
    '{}'::jsonb,
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    NULL
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'coverage_request_id', p_coverage_request_id,
    'request_status', 'pending'
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.cancel_coverage_request(
  p_coverage_request_id uuid,
  p_cancellation_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.fn_can_mutate_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only Encoder, Head Admin, or Super Admin can cancel Coverage Requests'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status NOT IN ('draft'::public.request_status, 'pending'::public.request_status) THEN
    RAISE EXCEPTION 'coverage request can only be cancelled from draft or pending status'
      USING ERRCODE = '22023';
  END IF;

  IF v_request.requested_by <> v_actor.profile_id
     AND NOT public.fn_can_review_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only the requester or HA/SA can cancel this request'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.coverage_requests
  SET status = 'cancelled'::public.request_status,
      cancelled_by = v_actor.profile_id,
      cancelled_by_name = v_actor.full_name,
      cancelled_at = now(),
      cancellation_reason = NULLIF(TRIM(COALESCE(p_cancellation_reason, '')), ''),
      updated_by = v_actor.profile_id,
      updated_at = now()
  WHERE id = p_coverage_request_id;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    v_request.status,
    'cancelled'::public.request_status,
    'cancelled',
    '{}'::jsonb,
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    p_cancellation_reason
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'coverage_request_id', p_coverage_request_id,
    'request_status', 'cancelled'
  );
END;
$fn$;

-- ------------------------------------------------------------
-- §4. Review RPCs: approve / reject / compatibility wrapper
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._review_coverage_request_phase3(
  p_coverage_request_id uuid,
  p_decision public.request_status,
  p_reviewer_remarks text DEFAULT NULL,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request public.coverage_requests%ROWTYPE;
  v_artifacts jsonb;
  v_summary jsonb;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.fn_can_review_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only Head Admin or Super Admin can approve or reject Coverage Requests'
      USING ERRCODE = '42501';
  END IF;

  IF p_decision NOT IN ('approved'::public.request_status, 'rejected'::public.request_status) THEN
    RAISE EXCEPTION 'decision must be approved or rejected'
      USING ERRCODE = '22023';
  END IF;

  IF p_decision = 'rejected'::public.request_status
     AND NULLIF(TRIM(COALESCE(p_rejection_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'rejection_reason is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'pending'::public.request_status THEN
    RAISE EXCEPTION 'coverage request can only be approved or rejected from pending status'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public._validate_coverage_request_payload(
    v_request.request_type,
    v_request.payload,
    v_request.account_id,
    v_request.position_id,
    v_request.employment_type,
    v_request.target_coverage_group_id,
    v_request.source_coverage_group_id,
    v_request.destination_coverage_group_id
  );

  v_artifacts := public._coverage_request_review_artifacts(v_request);
  v_summary := jsonb_build_object(
    'phase', 'coverage_request_approval_phase_3',
    'generated_at', now(),
    'generated_by', v_actor.profile_id,
    'generated_by_name', v_actor.full_name,
    'decision', p_decision,
    'structural_execution_enabled', false,
    'structural_execution_note', 'Approval/rejection updates status only. Structural execution remains disabled.'
  ) || v_artifacts;

  IF p_decision = 'approved'::public.request_status THEN
    UPDATE public.coverage_requests
    SET status = 'approved'::public.request_status,
        approved_by = v_actor.profile_id,
        approved_by_name = v_actor.full_name,
        approved_at = now(),
        reviewer_remarks = NULLIF(TRIM(COALESCE(p_reviewer_remarks, '')), ''),
        execution_summary = v_summary,
        updated_by = v_actor.profile_id,
        updated_at = now()
    WHERE id = p_coverage_request_id;
  ELSE
    UPDATE public.coverage_requests
    SET status = 'rejected'::public.request_status,
        rejected_by = v_actor.profile_id,
        rejected_by_name = v_actor.full_name,
        rejected_at = now(),
        rejection_reason = NULLIF(TRIM(COALESCE(p_rejection_reason, '')), ''),
        reviewer_remarks = NULLIF(TRIM(COALESCE(p_reviewer_remarks, '')), ''),
        execution_summary = v_summary,
        updated_by = v_actor.profile_id,
        updated_at = now()
    WHERE id = p_coverage_request_id;
  END IF;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    v_request.status,
    p_decision,
    CASE WHEN p_decision = 'approved'::public.request_status THEN 'approved' ELSE 'rejected' END,
    v_summary,
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    COALESCE(p_rejection_reason, p_reviewer_remarks)
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'coverage_request_id', p_coverage_request_id,
    'request_status', p_decision,
    'simulation_summary', v_summary -> 'simulation_summary',
    'conflict_report', v_summary -> 'conflict_report',
    'structural_execution_enabled', false
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.approve_coverage_request(
  p_coverage_request_id uuid,
  p_reviewer_remarks text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public._review_coverage_request_phase3(
    p_coverage_request_id,
    'approved'::public.request_status,
    p_reviewer_remarks,
    NULL
  );
$fn$;

CREATE OR REPLACE FUNCTION public.reject_coverage_request(
  p_coverage_request_id uuid,
  p_rejection_reason text,
  p_reviewer_remarks text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public._review_coverage_request_phase3(
    p_coverage_request_id,
    'rejected'::public.request_status,
    p_reviewer_remarks,
    p_rejection_reason
  );
$fn$;

CREATE OR REPLACE FUNCTION public.review_coverage_request(
  p_coverage_request_id uuid,
  p_decision text,
  p_reviewer_remarks text DEFAULT NULL,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_decision text := lower(trim(COALESCE(p_decision, '')));
BEGIN
  IF NOT public.fn_can_review_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only Head Admin or Super Admin can approve or reject Coverage Requests'
      USING ERRCODE = '42501';
  END IF;

  IF v_decision = 'approved' THEN
    RETURN public.approve_coverage_request(p_coverage_request_id, p_reviewer_remarks);
  ELSIF v_decision = 'rejected' THEN
    RETURN public.reject_coverage_request(p_coverage_request_id, p_rejection_reason, p_reviewer_remarks);
  END IF;

  RAISE EXCEPTION 'review decision must be approved or rejected'
    USING ERRCODE = '22023';
END;
$fn$;

COMMENT ON FUNCTION public.create_coverage_request(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text) IS
  'Creates a draft Coverage Request. Backend RBAC: Encoder, Head Admin, Super Admin. Structure-only contract; does not create Coverage Groups, HC, slots, vacancies, or pipeline rows.';
COMMENT ON FUNCTION public.submit_coverage_request(uuid) IS
  'Submits own draft Coverage Request, or any draft for HA/SA. Backend RBAC: Encoder, Head Admin, Super Admin.';
COMMENT ON FUNCTION public.cancel_coverage_request(uuid, text) IS
  'Cancels own draft/pending Coverage Request, or any draft/pending request for HA/SA. Backend RBAC: Encoder, Head Admin, Super Admin.';
COMMENT ON FUNCTION public.approve_coverage_request(uuid, text) IS
  'Approves a pending Coverage Request. Backend RBAC: Head Admin or Super Admin only. Status-only; no structural execution.';
COMMENT ON FUNCTION public.reject_coverage_request(uuid, text, text) IS
  'Rejects a pending Coverage Request. Backend RBAC: Head Admin or Super Admin only. Status-only; no structural execution.';
COMMENT ON FUNCTION public.review_coverage_request(uuid, text, text, text) IS
  'Compatibility wrapper for Coverage Request approval/rejection. Backend RBAC: Head Admin or Super Admin only.';

-- ------------------------------------------------------------
-- §5. Explicit EXECUTE grants
-- ------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.fn_can_mutate_coverage_request() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_can_review_coverage_request() FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public._coverage_request_actor() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._coverage_request_uuid_array(jsonb, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._coverage_request_payload_has_only_keys(jsonb, text[]) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._validate_coverage_request_payload(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._log_coverage_request_history(uuid, public.request_status, public.request_status, text, jsonb, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._coverage_request_review_artifacts(public.coverage_requests) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._review_coverage_request_phase3(uuid, public.request_status, text, text) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.create_coverage_request(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.submit_coverage_request(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cancel_coverage_request(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.approve_coverage_request(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reject_coverage_request(uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.review_coverage_request(uuid, text, text, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_coverage_request(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_coverage_request(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_coverage_request(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_coverage_request(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_coverage_request(uuid, text, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_coverage_request(uuid, text, text, text)
  TO authenticated;
