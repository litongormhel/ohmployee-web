-- Migration: 20260701000005_fix_dissolve_review_artifacts_archived_at_regression
-- Created: 2026-07-01
-- Purpose: Fix `column s.archived_at does not exist` (42703) raised when reviewing/approving/rejecting
--          a Coverage Request (reported live on Dissolve Coverage Group). Migration 20261246000000
--          previously fixed this exact bug in _coverage_request_review_artifacts by replacing
--          `s.archived_at IS NOT NULL` with `s.status = 'archived'` (public.stores has no archived_at
--          column). Migration 20260701000002 did a full CREATE OR REPLACE of the same function (to
--          drop merge_coverage_groups from v_structural_migration_required) and unintentionally
--          reintroduced the old broken archived_at references, regressing the earlier fix.
--
-- Smoke Tests:
-- S1: Submit a Dissolve Coverage Group request for a group whose stores are still referenced by
--     Vacancy records, then approve/reject it as HA/SA — request must resolve without a 42703 error.
-- S2: fn_coverage_group_diagnostics / review artifacts for create_coverage_group, add_store, and
--     remove_store request types still return correct inactive/archived store conflict counts.

BEGIN;

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

  v_pending_request_count integer;
BEGIN
  IF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN
    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;
  ELSE
    IF p_request.payload ? 'store_ids' THEN
      v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', false);
    END IF;
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

  -- Suppress checks for create_coverage_group
  IF p_request.request_type <> 'create_coverage_group'::public.request_type THEN
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
  END IF;

  -- Store duplicates check
  IF p_request.request_type IN ('create_coverage_group'::public.request_type, 'add_store'::public.request_type, 'remove_store'::public.request_type) THEN
    IF (
      SELECT COUNT(DISTINCT id) != COUNT(*)
      FROM unnest(v_store_ids) AS id
    ) THEN
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'check', 'duplicate_stores',
        'severity', 'warning',
        'count', 1,
        'message', 'Selected stores list contains duplicates.'
      ));
    END IF;
  END IF;

  -- Store archived/inactive check
  -- FIX (ohm#dissolve-archived-at): public.stores has no archived_at column; use status = 'archived'
  IF EXISTS (
    SELECT 1 FROM public.stores s
    WHERE s.id = ANY (v_store_ids)
      AND (s.is_active = false OR s.status = 'archived')
  ) THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'inactive_or_archived_store',
      'severity', 'warning',
      'count', (
        SELECT count(*)
        FROM public.stores s
        WHERE s.id = ANY (v_store_ids)
          AND (s.is_active = false OR s.status = 'archived')
      ),
      'message', 'One or more selected stores are archived or inactive.'
    ));
  END IF;

  -- Existing coverage group membership check
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

  -- Pending request check
  DECLARE
    v_pending_exists boolean;
  BEGIN
    WITH pending_requests AS (
      SELECT id, request_type, payload, target_coverage_group_id, source_coverage_group_id, destination_coverage_group_id
      FROM public.coverage_requests
      WHERE status = 'pending'::public.request_status
        AND archived_at IS NULL
        AND id <> p_request.id
    ),
    pending_stores AS (
      SELECT DISTINCT s_id
      FROM pending_requests pr,
           lateral unnest(public._coverage_request_uuid_array(pr.payload, 'store_ids', false)) AS s_id
      WHERE pr.request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving', 'convert_roving_to_stationary')

      UNION

      SELECT DISTINCT cgs.store_id
      FROM pending_requests pr
      JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id = pr.target_coverage_group_id
      WHERE pr.request_type = 'dissolve_coverage_group'
        AND cgs.archived_at IS NULL

      UNION

      SELECT DISTINCT cgs.store_id
      FROM pending_requests pr
      JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id IN (pr.source_coverage_group_id, pr.destination_coverage_group_id)
      WHERE pr.request_type = 'merge_coverage_groups'
        AND cgs.archived_at IS NULL
    )
    SELECT EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = ANY(v_store_ids)
        AND s.id IN (SELECT s_id FROM pending_stores)
    ) INTO v_pending_exists;

    IF v_pending_exists THEN
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'check', 'pending_coverage_request',
        'severity', 'warning',
        'count', (
          SELECT count(*)
          FROM public.stores s
          WHERE s.id = ANY(v_store_ids)
            AND s.id IN (SELECT s_id FROM pending_stores)
        ),
        'message', 'One or more affected stores already have a pending coverage request.'
      ));
    END IF;
  END;

  -- ohm#8a4f71d2: merge_coverage_groups removed — execution is now enabled
  v_structural_migration_required := p_request.request_type IN (
    'remove_store'::public.request_type,
    'convert_stationary_to_roving'::public.request_type,
    'convert_roving_to_stationary'::public.request_type,
    'dissolve_coverage_group'::public.request_type
    -- merge_coverage_groups INTENTIONALLY ABSENT — structural execution enabled
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
      'structural_execution_enabled', NOT v_structural_migration_required
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
        'pending_coverage_request', EXISTS (
          SELECT 1
          FROM public.coverage_requests pr
          JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id IN (pr.source_coverage_group_id, pr.destination_coverage_group_id)
          WHERE pr.status = 'pending'::public.request_status
            AND pr.archived_at IS NULL
            AND pr.id <> p_request.id
            AND pr.request_type = 'merge_coverage_groups'
            AND cgs.archived_at IS NULL
        ),
        'inactive_or_archived_store', EXISTS (
          SELECT 1 FROM public.stores s
          WHERE s.id = ANY(v_store_ids)
            AND (s.is_active = false OR s.status = 'archived')
        ),
        'structural_migration_required', v_structural_migration_required
      ),
      'conflicts', v_conflicts
    )
  );
END;
$fn$;

COMMENT ON FUNCTION public._coverage_request_review_artifacts(public.coverage_requests) IS
  'Generates simulation and conflict details for Coverage Request review. Checks for active employees, vacancies, pipelines, duplicates, and inactive/archived status.';

REVOKE EXECUTE ON FUNCTION public._coverage_request_review_artifacts(public.coverage_requests) FROM PUBLIC, anon, authenticated;

COMMIT;
