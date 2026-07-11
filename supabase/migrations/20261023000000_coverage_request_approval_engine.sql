-- ============================================================
-- OHM2026_0095 — Coverage Request Approval Engine
--
-- Phase 3 scope:
--   - approval/rejection RPCs
--   - simulation summary generation
--   - conflict detection report
--   - persist generated review artifacts on the request and history
--
-- Explicitly out of scope:
--   - Coverage Group structural mutation
--   - HC, slot, vacancy, or pipeline creation
--   - execution engine
-- ============================================================

CREATE OR REPLACE FUNCTION public._coverage_request_review_artifacts(
  p_request public.coverage_requests
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_store_ids uuid[] := ARRAY[]::uuid[];
  v_group_ids uuid[] := ARRAY[]::uuid[];
  v_affected_stores jsonb := '[]'::jsonb;
  v_affected_employees jsonb := '[]'::jsonb;
  v_affected_vacancies jsonb := '[]'::jsonb;
  v_affected_pipelines jsonb := '[]'::jsonb;
  v_conflicts jsonb := '[]'::jsonb;
  v_structural_migration_required boolean := false;
BEGIN
  IF p_request.payload ? 'store_ids' THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', false);
  END IF;

  SELECT COALESCE(array_agg(DISTINCT group_id), ARRAY[]::uuid[])
  INTO v_group_ids
  FROM unnest(ARRAY[
    p_request.target_coverage_group_id,
    p_request.source_coverage_group_id,
    p_request.destination_coverage_group_id
  ]) AS group_id
  WHERE group_id IS NOT NULL;

  IF COALESCE(array_length(v_group_ids, 1), 0) > 0 THEN
    SELECT COALESCE(array_agg(DISTINCT cgs.store_id), ARRAY[]::uuid[])
    INTO v_store_ids
    FROM (
      SELECT unnest(v_store_ids) AS store_id
      UNION
      SELECT cgs.store_id
      FROM public.coverage_group_stores cgs
      WHERE cgs.coverage_group_id = ANY (v_group_ids)
        AND cgs.archived_at IS NULL
    ) cgs;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'store_id', s.id,
        'store_name', s.store_name,
        'store_branch', s.store_branch,
        'account_id', s.account_id,
        'is_active', COALESCE(s.is_active, true),
        'is_existing_coverage_member', EXISTS (
          SELECT 1
          FROM public.coverage_group_stores cgs
          WHERE cgs.store_id = s.id
            AND cgs.archived_at IS NULL
            AND (
              COALESCE(array_length(v_group_ids, 1), 0) = 0
              OR NOT (cgs.coverage_group_id = ANY (v_group_ids))
            )
        )
      )
      ORDER BY s.store_name, s.store_branch
    ),
    '[]'::jsonb
  )
  INTO v_affected_stores
  FROM public.stores s
  WHERE s.id = ANY (v_store_ids);

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'plantilla_id', p.id,
        'employee_no', p.employee_no,
        'employee_name', p.employee_name,
        'store_id', p.store_id,
        'coverage_group_id', p.coverage_group_id,
        'coverage_slot_id', p.coverage_slot_id,
        'status', p.status
      )
      ORDER BY p.employee_name
    ),
    '[]'::jsonb
  )
  INTO v_affected_employees
  FROM public.plantilla p
  WHERE COALESCE(p.is_deleted, false) = false
    AND p.status = 'Active'
    AND (
      (COALESCE(array_length(v_group_ids, 1), 0) > 0 AND p.coverage_group_id = ANY (v_group_ids))
      OR (COALESCE(array_length(v_store_ids, 1), 0) > 0 AND p.store_id = ANY (v_store_ids))
    );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'vacancy_id', v.id,
        'vcode', v.vcode,
        'status', v.status,
        'store_id', v.store_id,
        'account_id', v.account_id,
        'position_id', v.position_id,
        'employment_type', v.employment_type
      )
      ORDER BY v.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_affected_vacancies
  FROM public.vacancies v
  WHERE COALESCE(v.is_archived, false) = false
    AND v.archived_at IS NULL
    AND v.deleted_at IS NULL
    AND v.status IN ('Open', 'For Sourcing', 'Pipeline')
    AND (
      (COALESCE(array_length(v_store_ids, 1), 0) > 0 AND v.store_id = ANY (v_store_ids))
      OR (
        p_request.account_id IS NOT NULL
        AND v.account_id = p_request.account_id
        AND (p_request.position_id IS NULL OR v.position_id = p_request.position_id)
        AND (
          NULLIF(TRIM(COALESCE(p_request.employment_type, '')), '') IS NULL
          OR lower(v.employment_type) = lower(p_request.employment_type)
        )
      )
    );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'applicant_id', a.id,
        'full_name', a.full_name,
        'status', a.status,
        'vacancy_vcode', a.vacancy_vcode,
        'coverage_group_id', a.coverage_group_id,
        'coverage_slot_id', a.coverage_slot_id
      )
      ORDER BY a.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_affected_pipelines
  FROM public.applicants a
  LEFT JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE COALESCE(a.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a.status)
    AND (
      (COALESCE(array_length(v_group_ids, 1), 0) > 0 AND a.coverage_group_id = ANY (v_group_ids))
      OR (COALESCE(array_length(v_store_ids, 1), 0) > 0 AND v.store_id = ANY (v_store_ids))
      OR (
        p_request.account_id IS NOT NULL
        AND v.account_id = p_request.account_id
        AND (p_request.position_id IS NULL OR v.position_id = p_request.position_id)
      )
    );

  IF jsonb_array_length(v_affected_employees) > 0 THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'active_employees',
      'severity', 'warning',
      'count', jsonb_array_length(v_affected_employees),
      'message', 'Active employees are attached to the affected stores or coverage groups.'
    ));
  END IF;

  IF jsonb_array_length(v_affected_vacancies) > 0 THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'active_vacancies',
      'severity', 'warning',
      'count', jsonb_array_length(v_affected_vacancies),
      'message', 'Active vacancies exist in the affected scope.'
    ));
  END IF;

  IF jsonb_array_length(v_affected_pipelines) > 0 THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'active_pipelines',
      'severity', 'warning',
      'count', jsonb_array_length(v_affected_pipelines),
      'message', 'Active pipeline applicants exist in the affected scope.'
    ));
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.coverage_group_stores cgs
    WHERE cgs.archived_at IS NULL
      AND cgs.store_id = ANY (v_store_ids)
      AND (
        p_request.request_type IN (
          'create_coverage_group'::public.request_type,
          'convert_stationary_to_roving'::public.request_type,
          'add_store'::public.request_type
        )
        OR NOT (cgs.coverage_group_id = ANY (v_group_ids))
      )
  ) THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'existing_coverage_membership',
      'severity', 'warning',
      'count', (
        SELECT count(*)
        FROM public.coverage_group_stores cgs
        WHERE cgs.archived_at IS NULL
          AND cgs.store_id = ANY (v_store_ids)
      ),
      'message', 'One or more affected stores already have active coverage membership.'
    ));
  END IF;

  v_structural_migration_required := p_request.request_type IN (
    'remove_store'::public.request_type,
    'convert_stationary_to_roving'::public.request_type,
    'convert_roving_to_stationary'::public.request_type,
    'merge_coverage_groups'::public.request_type,
    'dissolve_coverage_group'::public.request_type
  );

  IF v_structural_migration_required THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'structural_migration_required',
      'severity', 'info',
      'count', 1,
      'message', 'Approval records intent only. Structural execution remains disabled.'
    ));
  END IF;

  RETURN jsonb_build_object(
    'simulation_summary', jsonb_build_object(
      'request_type', p_request.request_type,
      'affected_stores', v_affected_stores,
      'affected_employees', v_affected_employees,
      'affected_vacancies', v_affected_vacancies,
      'affected_pipelines', v_affected_pipelines,
      'approval_required', true,
      'structural_execution_enabled', false
    ),
    'conflict_report', jsonb_build_object(
      'has_conflicts', jsonb_array_length(v_conflicts) > 0,
      'checks', jsonb_build_object(
        'active_employees', jsonb_array_length(v_affected_employees),
        'active_vacancies', jsonb_array_length(v_affected_vacancies),
        'active_pipelines', jsonb_array_length(v_affected_pipelines),
        'existing_coverage_membership', EXISTS (
          SELECT 1
          FROM public.coverage_group_stores cgs
          WHERE cgs.archived_at IS NULL
            AND cgs.store_id = ANY (v_store_ids)
        ),
        'structural_migration_required', v_structural_migration_required
      ),
      'conflicts', v_conflicts
    )
  );
END;
$fn$;

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

  IF NOT public.i_have_full_access() THEN
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
  IF v_decision = 'approved' THEN
    RETURN public.approve_coverage_request(p_coverage_request_id, p_reviewer_remarks);
  ELSIF v_decision = 'rejected' THEN
    RETURN public.reject_coverage_request(p_coverage_request_id, p_rejection_reason, p_reviewer_remarks);
  END IF;

  RAISE EXCEPTION 'review decision must be approved or rejected'
    USING ERRCODE = '22023';
END;
$fn$;

COMMENT ON FUNCTION public._coverage_request_review_artifacts(public.coverage_requests) IS
  'Generates Phase 3 Coverage Request simulation_summary and conflict_report JSON. Read-only; no structural execution.';
COMMENT ON FUNCTION public.approve_coverage_request(uuid, text) IS
  'Phase 3 approval RPC. HA/SA only. Generates and stores simulation/conflict artifacts, then updates status to approved only; no structure, HC, slot, vacancy, or pipeline mutation.';
COMMENT ON FUNCTION public.reject_coverage_request(uuid, text, text) IS
  'Phase 3 rejection RPC. HA/SA only. Generates and stores simulation/conflict artifacts, then updates status to rejected only; no structural mutation.';
COMMENT ON FUNCTION public.review_coverage_request(uuid, text, text, text) IS
  'Compatibility wrapper for Phase 3 approval/rejection RPCs.';

REVOKE EXECUTE ON FUNCTION public._coverage_request_review_artifacts(public.coverage_requests) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._review_coverage_request_phase3(uuid, public.request_status, text, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.approve_coverage_request(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_coverage_request(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_coverage_request(uuid, text, text, text) TO authenticated;
