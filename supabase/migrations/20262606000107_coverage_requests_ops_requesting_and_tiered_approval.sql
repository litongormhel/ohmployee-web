-- ============================================================
-- Migration: 20262606000107_coverage_requests_ops_requesting_and_tiered_approval.sql
-- Ticket: ohm#o4p9s2k1
-- Purpose: Phase 2: Operations Coverage Requesting & Tiered Review/Approval
--          - Authorizes Operations roles (OM, TL, ATL, HRCO) to initiate coverage requests
--          - Enforces tiered review: Encoders may review Ops-initiated requests;
--            Encoder-initiated requests strictly require Head Admin / Super Admin review
--          - Hardens self-approval prevention
--          - Expands RLS read policy on coverage_requests for Ops visibility
-- ============================================================

-- ------------------------------------------------------------
-- §1. Coverage Request Mutation Authorization
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_can_mutate_coverage_request()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public.i_have_full_access()
      OR public.get_my_role() IN ('Encoder', 'Operations Manager', 'OM', 'TL', 'ATL', 'ATL/TL', 'HRCO');
$fn$;

COMMENT ON FUNCTION public.fn_can_mutate_coverage_request() IS
  'TRUE for Encoder, Operations roles (OM, TL, ATL, HRCO), Head Admin, or Super Admin. Backend gate for Coverage Request create, submit, and cancel.';

REVOKE EXECUTE ON FUNCTION public.fn_can_mutate_coverage_request() FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- §2. Coverage Request Review Authorization Predicate
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_can_review_coverage_request(p_coverage_request_id uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_req record;
BEGIN
  -- Super Admin and Head Admin can always review
  IF public.i_have_full_access() THEN
    RETURN TRUE;
  END IF;

  -- Encoders have tiered review authority
  IF public.get_my_role() = 'Encoder' THEN
    -- General capability check when no specific request ID is passed
    IF p_coverage_request_id IS NULL THEN
      RETURN TRUE;
    END IF;

    -- For a specific request: Encoders may review only if requested by an Ops role and not self
    SELECT requested_by, requested_by_role INTO v_req
    FROM public.coverage_requests
    WHERE id = p_coverage_request_id;

    IF NOT FOUND THEN
      RETURN FALSE;
    END IF;

    IF v_req.requested_by = auth.uid() THEN
      RETURN FALSE;
    END IF;

    RETURN v_req.requested_by_role IN ('Operations Manager', 'OM', 'TL', 'ATL', 'ATL/TL', 'HRCO');
  END IF;

  RETURN FALSE;
END;
$fn$;

COMMENT ON FUNCTION public.fn_can_review_coverage_request(uuid) IS
  'TRUE for Head Admin and Super Admin; TRUE for Encoders reviewing requests submitted by Operations roles.';

REVOKE EXECUTE ON FUNCTION public.fn_can_review_coverage_request(uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- §3. Tiered Review & Execution Engine (_review_coverage_request_phase3)
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._review_coverage_request_phase3(
  p_coverage_request_id uuid,
  p_decision request_status,
  p_reviewer_remarks text DEFAULT NULL::text,
  p_rejection_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor                   record;
  v_request                 public.coverage_requests%ROWTYPE;
  v_artifacts               jsonb;
  v_summary                 jsonb;
  v_execution_result        jsonb;
  v_structural_supported    boolean;
  v_executed_event_payload  jsonb;
  v_executed_at             timestamptz;
BEGIN

  -- ── Actor Resolution ───────────────────────────────────────────────────────
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  -- ── Input validation ──────────────────────────────────────────────────────
  IF p_decision NOT IN ('approved'::public.request_status, 'rejected'::public.request_status) THEN
    RAISE EXCEPTION 'decision must be approved or rejected'
      USING ERRCODE = '22023';
  END IF;

  IF p_decision = 'rejected'::public.request_status
     AND NULLIF(TRIM(COALESCE(p_rejection_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'rejection_reason is required'
      USING ERRCODE = '22023';
  END IF;

  -- ── Load request ─────────────────────────────────────────────────────────
  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found' USING ERRCODE = 'P0002';
  END IF;

  -- ── Self-Approval Guard ───────────────────────────────────────────────────
  IF v_request.requested_by = v_actor.profile_id THEN
    RAISE EXCEPTION 'forbidden: self-approval is not permitted'
      USING ERRCODE = '42501';
  END IF;

  -- ── Tiered Review Authorization ──────────────────────────────────────────
  -- 1. Head Admin and Super Admin can review any request.
  -- 2. Encoder can review requests initiated by Operations roles (OM, TL, ATL, HRCO).
  -- 3. All other roles are strictly blocked.
  IF NOT public.i_have_full_access() THEN
    IF public.get_my_role() = 'Encoder' THEN
      IF v_request.requested_by_role NOT IN ('Operations Manager', 'OM', 'TL', 'ATL', 'ATL/TL', 'HRCO') THEN
        RAISE EXCEPTION 'forbidden: Encoders may only review Coverage Requests submitted by Operations roles'
          USING ERRCODE = '42501';
      END IF;
    ELSE
      RAISE EXCEPTION 'forbidden: only Head Admin, Super Admin, or Encoders (for Ops requests) can approve or reject Coverage Requests'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  IF v_request.status <> 'pending'::public.request_status THEN
    RAISE EXCEPTION 'coverage request can only be approved or rejected from pending status'
      USING ERRCODE = '22023';
  END IF;

  -- ── Payload validation (runs GAP-09 and GAP-10 checks too) ───────────────
  PERFORM public._validate_coverage_request_payload(
    v_request.request_type,
    v_request.payload,
    v_request.account_id,
    v_request.position_id,
    v_request.employment_type,
    v_request.target_coverage_group_id,
    v_request.source_coverage_group_id,
    v_request.destination_coverage_group_id,
    p_coverage_request_id
  );

  -- ── Determine structural support ─────────────────────────────────────────
  v_structural_supported := v_request.request_type IN (
    'create_coverage_group'::public.request_type,
    'add_store'::public.request_type,
    'remove_store'::public.request_type,
    'convert_roving_to_stationary'::public.request_type,
    'dissolve_coverage_group'::public.request_type,
    'merge_coverage_groups'::public.request_type      -- ohm#8a4f71d2: enabled
  );

  -- ── Generate simulation + conflict artifacts ──────────────────────────────
  v_artifacts := public._coverage_request_review_artifacts(v_request);
  v_summary := jsonb_build_object(
    'phase',                         'coverage_request_approval_phase_4',
    'generated_at',                   now(),
    'generated_by',                   v_actor.profile_id,
    'generated_by_name',              v_actor.full_name,
    'decision',                       p_decision,
    'structural_execution_enabled',   v_structural_supported
                                      AND p_decision = 'approved'::public.request_status
  ) || v_artifacts;

  -- ── Approve path ─────────────────────────────────────────────────────────
  IF p_decision = 'approved'::public.request_status THEN

    IF v_structural_supported THEN
      v_execution_result := public._execute_approved_coverage_request(
        v_request,
        v_actor.profile_id,
        v_actor.full_name,
        v_actor.role_name
      );
    ELSE
      v_execution_result := jsonb_build_object(
        'structural_execution_enabled', false,
        'request_type',                  v_request.request_type,
        'note',                          'Structural execution for this request type is deferred.'
      );
    END IF;

    v_summary := v_summary || jsonb_build_object('execution_result', v_execution_result);

    -- Record executed_at when structural execution succeeded.
    v_executed_at := CASE WHEN v_structural_supported THEN now() ELSE NULL END;

    UPDATE public.coverage_requests
    SET status           = 'approved'::public.request_status,
        approved_by      = v_actor.profile_id,
        approved_by_name = v_actor.full_name,
        approved_at      = now(),
        executed_at      = v_executed_at,
        reviewer_remarks = NULLIF(TRIM(COALESCE(p_reviewer_remarks, '')), ''),
        execution_summary = v_summary,
        updated_by       = v_actor.profile_id,
        updated_at       = now()
    WHERE id = p_coverage_request_id;

  -- ── Reject path ───────────────────────────────────────────────────────────
  ELSE
    UPDATE public.coverage_requests
    SET status           = 'rejected'::public.request_status,
        rejected_by      = v_actor.profile_id,
        rejected_by_name = v_actor.full_name,
        rejected_at      = now(),
        rejection_reason = NULLIF(TRIM(COALESCE(p_rejection_reason, '')), ''),
        reviewer_remarks = NULLIF(TRIM(COALESCE(p_reviewer_remarks, '')), ''),
        execution_summary = v_summary,
        updated_by       = v_actor.profile_id,
        updated_at       = now()
    WHERE id = p_coverage_request_id;
  END IF;

  -- ── History: status-transition event (approved | rejected) ────────────────
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

  -- ── History: executed event — only when structural execution succeeded ────
  IF p_decision = 'approved'::public.request_status AND v_structural_supported THEN
    v_executed_event_payload := jsonb_build_object(
      'action_type',       v_request.request_type,
      'executed_by',       v_actor.profile_id,
      'executed_by_name',  v_actor.full_name,
      'executed_at',       v_executed_at,
      'before_state',      'approved',
      'after_state',       'executed',
      'execution_detail',  COALESCE(v_execution_result, '{}'::jsonb)
    );

    PERFORM public._log_coverage_request_history(
      p_coverage_request_id,
      'approved'::public.request_status,
      'approved'::public.request_status,
      'executed',
      v_executed_event_payload,
      v_actor.profile_id,
      v_actor.full_name,
      v_actor.role_name,
      'Structural execution completed.'
    );
  END IF;

  -- ── Return ────────────────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'status',                        'ok',
    'coverage_request_id',           p_coverage_request_id,
    'request_status',                p_decision,
    'simulation_summary',            v_summary -> 'simulation_summary',
    'conflict_report',               v_summary -> 'conflict_report',
    'structural_execution_enabled',  v_structural_supported
                                      AND p_decision = 'approved'::public.request_status,
    'execution_result',              v_execution_result
  );
END;
$function$;

COMMENT ON FUNCTION public._review_coverage_request_phase3(uuid, request_status, text, text) IS
  'Executes coverage request approval/rejection with tiered authorization: HA/SA universal, Encoder for Ops requests.';

REVOKE EXECUTE ON FUNCTION public._review_coverage_request_phase3(uuid, request_status, text, text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- §4. RLS Posture Update: Operations Role Read Visibility
-- ------------------------------------------------------------

DROP POLICY IF EXISTS coverage_requests_read_scoped ON public.coverage_requests;
CREATE POLICY coverage_requests_read_scoped
  ON public.coverage_requests
  FOR SELECT
  TO authenticated
  USING (
    (
      public.i_have_full_access()
      OR public.get_my_role() IN ('Encoder', 'Operations Manager', 'OM', 'TL', 'ATL', 'ATL/TL', 'HRCO')
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

COMMENT ON POLICY coverage_requests_read_scoped ON public.coverage_requests IS
  'Read-only visibility for Encoder, Operations roles (OM, TL, ATL, HRCO), Head Admin, and Super Admin under assigned account scope.';

DROP POLICY IF EXISTS coverage_request_history_read_scoped ON public.coverage_request_history;
CREATE POLICY coverage_request_history_read_scoped
  ON public.coverage_request_history
  FOR SELECT
  TO authenticated
  USING (
    (
      public.i_have_full_access()
      OR public.get_my_role() IN ('Encoder', 'Operations Manager', 'OM', 'TL', 'ATL', 'ATL/TL', 'HRCO')
    )
    AND EXISTS (
      SELECT 1
      FROM public.coverage_requests cr
      WHERE cr.id = coverage_request_history.coverage_request_id
    )
  );

COMMENT ON POLICY coverage_request_history_read_scoped ON public.coverage_request_history IS
  'Read-only history visibility for Encoder, Operations roles, Head Admin, and Super Admin through parent Coverage Request scope.';
