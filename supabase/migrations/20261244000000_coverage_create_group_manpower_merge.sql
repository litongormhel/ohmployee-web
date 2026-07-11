-- ============================================================================
-- ohm#cgfix7m4 — Coverage Group Create Group Manpower Merge
-- Migration: 20261244000000_coverage_create_group_manpower_merge.sql
-- ============================================================================

BEGIN;

-- ── §1. Update _review_coverage_request_phase3 ──────────────────────────────
-- Add 'create_coverage_group' to v_structural_supported.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._review_coverage_request_phase3(
  p_coverage_request_id  uuid,
  p_decision             public.request_status,
  p_reviewer_remarks     text DEFAULT NULL,
  p_rejection_reason     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
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

  -- ── Authorization ─────────────────────────────────────────────────────────
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: only Head Admin or Super Admin can approve or reject Coverage Requests'
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
    v_request.destination_coverage_group_id
  );

  -- ── Determine structural support ─────────────────────────────────────────
  v_structural_supported := v_request.request_type IN (
    'create_coverage_group'::public.request_type,
    'add_store'::public.request_type,
    'remove_store'::public.request_type,
    'convert_roving_to_stationary'::public.request_type,
    'dissolve_coverage_group'::public.request_type
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
$fn$;


-- ── §2. Update _coverage_request_review_artifacts ───────────────────────────
-- Suppress active_employees, active_vacancies, and active_pipelines warnings when request_type = 'create_coverage_group'.
-- ────────────────────────────────────────────────────────────────────────────
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


-- ── §3. Update _execute_approved_coverage_request ───────────────────────────
-- Add create_coverage_group branch and fix dissolve path store Links update.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._execute_approved_coverage_request(
  p_request public.coverage_requests,
  p_actor_id uuid,
  p_actor_name text,
  p_actor_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  -- ── iteration / loop cursors
  v_store_id               uuid;
  v_pl                     record;

  -- ── remove_store semantics (corrected per ohm#25f6a6ra)
  v_removed_store_ids      uuid[];
  v_remaining_store_ids    uuid[];
  v_remaining_count        integer;

  -- ── add_store
  v_store_ids              uuid[];
  v_replacement_store_ids  uuid[];

  v_below_minimum_action   text;

  -- ── reporting
  v_existing_cg_code       text;
  v_anchor_removed         boolean := false;
  v_stores_added           integer := 0;
  v_stores_removed         integer := 0;
  v_group_archived         boolean := false;
  v_notes                  text[]  := ARRAY[]::text[];

  -- ── stationary-conversion helpers
  v_remaining_store_id     uuid;
  v_remaining_store_name   text;
  v_remaining_store_vcode  text;

  -- ── imported-employee helpers
  v_active_allocs          integer;

  -- ── vacancy / slot reopening helpers
  v_existing_slot_id       uuid;
  v_new_slot_id            uuid;
  v_rows_updated           integer;
  v_store_account_id       uuid;
  v_store_group_id         uuid;
  v_store_vcode            text;
  v_store_name_local       text;
  v_store_account_name     text;
  v_store_position         text;
  v_store_employment_type  text;
  v_store_position_id      uuid;
  v_store_province_id      uuid;   -- always NULL; stores has no province_id
  v_store_area             text;
  v_store_chain_id         uuid;

  -- ── Bug 1 fix: pre-resolved group_id fallback from CG account
  v_cg_account_group_id    uuid;

  -- ── Bug 2 fix: pre-resolved position from coverage_groups → positions
  v_cg_position_name       text;
  v_cg_position_id         uuid;

  -- ── GAP-02 dissolve variables
  v_employee_home_stores   jsonb;
  v_retained_store_ids     uuid[];
  v_dissolved_store_ids    uuid[];
  v_employees_converted    integer := 0;
  v_vacancies_reopened     integer := 0;

  -- ── create_coverage_group variables
  v_new_cg_id              uuid;
  v_cg_code                text;
  v_store_count            integer;
  v_slot_ordinal           integer := 0;
  v_slot_id                uuid;
  v_anchor_store_name      text;
  v_anchor_store_vcode     text;
  v_old_slot_id            uuid;
  v_old_vcode              text;
BEGIN

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── create_coverage_group ───────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  IF p_request.request_type = 'create_coverage_group'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
    v_store_count := COALESCE(array_length(v_store_ids, 1), 0);

    IF v_store_count < 2 THEN
      RAISE EXCEPTION 'Coverage Group must have at least 2 member stores.' USING ERRCODE = '23514';
    END IF;

    v_new_cg_id := gen_random_uuid();
    v_cg_code := public.fn_generate_cgcode_for_account(p_request.account_id);

    -- STEP 1: Create coverage group structure
    INSERT INTO public.coverage_groups (
      id, coverage_code, account_id, position_id,
      employment_type, required_headcount, status,
      area_name, created_by, created_at
    ) VALUES (
      v_new_cg_id, v_cg_code, p_request.account_id, p_request.position_id,
      p_request.employment_type, v_store_count, 'open',
      p_request.payload ->> 'area_name', p_actor_id, now()
    );

    SELECT store_name, vcode INTO v_anchor_store_name, v_anchor_store_vcode
    FROM public.stores
    WHERE id = (p_request.payload ->> 'anchor_store_id')::uuid;

    -- STEP 2: Create coverage group member edges
    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      INSERT INTO public.coverage_group_stores (
        coverage_group_id, store_id, is_anchor, added_by
      ) VALUES (
        v_new_cg_id, v_store_id, (v_store_id = (p_request.payload ->> 'anchor_store_id')::uuid), p_actor_id
      );
    END LOOP;

    -- STEP 3 & 4: Evaluate member stores and assign active employees
    v_slot_ordinal := 0;
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.store_id = ANY(v_store_ids)
        AND pl.account_id = p_request.account_id
        AND pl.position_id = p_request.position_id
        AND pl.status = 'Active'
        AND COALESCE(pl.is_deleted, false) = false
        AND COALESCE(pl.is_archived, false) = false
    ) LOOP
      v_slot_id := gen_random_uuid();
      v_slot_ordinal := v_slot_ordinal + 1;

      -- Create active coverage slot row
      INSERT INTO public.coverage_slots (
        id, coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_slot_id, v_new_cg_id, v_slot_ordinal, 'active', v_pl.id, now(), now()
      );

      -- Update employee plantilla row to roving
      UPDATE public.plantilla
      SET deployment_type = 'Roving',
          coverage_group_id = v_new_cg_id,
          coverage_slot_id = v_slot_id,
          store_id = (p_request.payload ->> 'anchor_store_id')::uuid,
          store_name = v_anchor_store_name,
          vcode = NULL
      WHERE id = v_pl.id;

      -- Vacate/open old stationary slot in plantilla_slots
      SELECT id, legacy_vcode INTO v_old_slot_id, v_old_vcode
      FROM public.plantilla_slots
      WHERE current_occupant_plantilla_id = v_pl.id
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_old_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'open',
            current_occupant_plantilla_id = NULL,
            updated_at = now(),
            updated_by = p_actor_id
        WHERE id = v_old_slot_id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_old_slot_id, v_pl.account_id, 'employee_separated',
          'occupied', 'open', 'COVERAGE_GROUP_CREATED',
          p_actor_id, 'Employee converted to roving coverage in group ' || v_cg_code || '.', now()
        );
      END IF;

      -- Reconcile assignments/allocations
      IF v_pl.source_employee_import_batch_id IS NOT NULL
         OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        -- Deactivate old allocations
        UPDATE public.employee_store_allocations
        SET is_active = false,
            effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;

        -- Insert new allocations for all group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, v_new_cg_id,
            v_store_id, v_store_vcode, v_store_name_local,
            v_pl.account_id, v_pl.group_id,
            round(1.0 / v_store_count, 4), v_store_count,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        END LOOP;
      ELSE
        -- Live employee: deactivate old store links
        UPDATE public.plantilla_store_links
        SET status = 'Resigned',
            deleted_at = now(),
            unlinked_at = now(),
            unlinked_by = p_actor_id
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;

        -- Insert new store links for all group stores
        FOREACH v_store_id IN ARRAY v_store_ids LOOP
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.plantilla_store_links (
            plantilla_id,
            coverage_group_id,
            vcode,
            store_name,
            account,
            status,
            linked_at,
            linked_by,
            created_by,
            updated_by
          ) VALUES (
            v_pl.id,
            v_new_cg_id,
            v_store_vcode,
            v_store_name_local,
            (SELECT account_name FROM public.accounts WHERE id = v_pl.account_id),
            'Active',
            now(),
            p_actor_id,
            p_actor_id,
            p_actor_id
          );
        END LOOP;

        PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
      END IF;

      v_employees_converted := v_employees_converted + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|assigned_to_coverage_group:' || v_cg_code
      ];
    END LOOP;

    -- Create remaining open coverage slots up to v_store_count
    IF v_slot_ordinal < v_store_count THEN
      INSERT INTO public.coverage_slots (
        coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
      )
      SELECT v_new_cg_id, gs.ord, 'open', NULL, now(), now()
      FROM generate_series(v_slot_ordinal + 1, v_store_count) AS gs(ord);
    END IF;

    -- Link request target_coverage_group_id to the new group
    UPDATE public.coverage_requests
    SET target_coverage_group_id = v_new_cg_id
    WHERE id = p_request.id;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'create_coverage_group',
      'coverage_group_id',            v_new_cg_id,
      'coverage_code',                v_cg_code,
      'stores_added',                 v_store_count,
      'employees_converted',          v_employees_converted,
      'notes',                        to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── add_store ───────────────────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'add_store'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      SELECT cg.coverage_code INTO v_existing_cg_code
      FROM public.coverage_group_stores cgs
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      WHERE cgs.store_id = v_store_id
        AND cgs.archived_at IS NULL
        AND cg.archived_at IS NULL
        AND cg.id <> p_request.target_coverage_group_id
      LIMIT 1;

      IF v_existing_cg_code IS NOT NULL THEN
        RAISE EXCEPTION
          'store % is already active in coverage group %; remove it first',
          v_store_id, v_existing_cg_code
          USING ERRCODE = '23514';
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.coverage_group_stores
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND store_id = v_store_id
          AND archived_at IS NULL
      ) THEN
        RAISE EXCEPTION
          'store % is already an active member of this coverage group',
          v_store_id
          USING ERRCODE = '23514';
      END IF;

      INSERT INTO public.coverage_group_stores (
        coverage_group_id, store_id, is_anchor, added_by
      ) VALUES (
        p_request.target_coverage_group_id, v_store_id, false, p_actor_id
      );
      v_stores_added := v_stores_added + 1;

      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          IF NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations
            WHERE plantilla_id = v_pl.id AND store_id = v_store_id AND is_active = true
          ) THEN
            SELECT store_name, vcode
            INTO v_remaining_store_name, v_remaining_store_vcode
            FROM public.stores WHERE id = v_store_id;

            INSERT INTO public.employee_store_allocations (
              plantilla_id, employee_no, roving_group_id,
              store_id, vcode, store_name,
              account_id, group_id,
              filled_hc, active_store_count,
              effective_start, is_active,
              source_import_batch_id, created_by
            ) VALUES (
              v_pl.id, v_pl.employee_no, p_request.target_coverage_group_id,
              v_store_id, v_remaining_store_vcode, v_remaining_store_name,
              v_pl.account_id, v_pl.group_id,
              1, 1,
              CURRENT_DATE, true,
              v_pl.source_baseline_import_batch_id, p_actor_id
            );
          END IF;
        END IF;
      END LOOP;
    END LOOP;

    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        SELECT COUNT(*) INTO v_active_allocs
        FROM public.employee_store_allocations
        WHERE plantilla_id = v_pl.id AND is_active = true;

        IF v_active_allocs > 0 THEN
          UPDATE public.employee_store_allocations
          SET active_store_count = v_active_allocs,
              filled_hc = round(1.0 / v_active_allocs, 4)
          WHERE plantilla_id = v_pl.id AND is_active = true;
        END IF;
      END IF;
    END LOOP;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'add_store',
      'stores_added',                 v_stores_added,
      'stores_removed',               0,
      'group_archived',               false,
      'below_minimum_action_applied', null,
      'notes',                        to_jsonb(v_notes)
    );


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── remove_store / convert_roving_to_stationary ─────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'remove_store'::public.request_type
     OR p_request.request_type = 'convert_roving_to_stationary'::public.request_type
  THEN

    -- Pre-resolve group_id from coverage group's account
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Pre-resolve position from coverage_groups → positions
    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Resolve which stores are being REMOVED
    IF p_request.request_type = 'convert_roving_to_stationary'::public.request_type THEN
      v_remaining_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_removed_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_remaining_store_ids));
      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);
      v_below_minimum_action := 'convert_remaining_to_standalone';
    ELSE
      v_removed_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

      IF EXISTS (
        SELECT 1 FROM unnest(v_removed_store_ids) AS rid
        WHERE NOT EXISTS (
          SELECT 1 FROM public.coverage_group_stores
          WHERE coverage_group_id = p_request.target_coverage_group_id
            AND store_id = rid
            AND archived_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION
          'remove_store: one or more store_ids are not active members of this coverage group'
          USING ERRCODE = '23514';
      END IF;

      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_remaining_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_removed_store_ids));

      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);

      IF v_remaining_count = 0 THEN
        RAISE EXCEPTION
          'remove_store would leave 0 active stores; use dissolve_coverage_group instead'
          USING ERRCODE = '23514';
      ELSIF v_remaining_count = 1 THEN
        v_below_minimum_action := 'convert_remaining_to_standalone';
      ELSE
        v_below_minimum_action := NULL;
      END IF;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND is_anchor = true
        AND archived_at IS NULL
    ) THEN
      v_anchor_removed := true;
      v_notes := v_notes || ARRAY['anchor store removed; group has no active anchor'];
    END IF;

    -- Employee Integrity Lock
    IF v_remaining_count >= 2 THEN
      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          -- Imported employee: count ESA rows that survive after removal
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id
            AND is_active = true
            AND NOT (store_id = ANY(v_removed_store_ids));

          IF v_active_allocs = 0 THEN
            RAISE EXCEPTION
              'Employee integrity lock: removing these stores would leave employee % (%) with 0 active store assignments. '
              'Retain at least one store for this employee, or use Dissolve Coverage Group.',
              COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
              USING ERRCODE = '23514';
          END IF;
        ELSE
          -- Non-imported employee: count active store links surviving after removal
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.plantilla_store_links psl
          JOIN public.stores s ON psl.vcode = s.vcode
          WHERE psl.plantilla_id = v_pl.id
            AND psl.deleted_at IS NULL
            AND NOT (s.id = ANY(v_removed_store_ids));

          IF v_active_allocs = 0 THEN
            RAISE EXCEPTION
              'Employee integrity lock: removing these stores would leave employee % (%) with 0 active store assignments. '
              'Retain at least one store for this employee, or use Dissolve Coverage Group.',
              COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
              USING ERRCODE = '23514';
          END IF;
        END IF;
      END LOOP;
    END IF;

    -- Branch A: convert_remaining_to_standalone (remaining_count = 1)
    IF v_below_minimum_action = 'convert_remaining_to_standalone' THEN
      v_remaining_store_id := v_remaining_store_ids[1];
      SELECT store_name, vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores WHERE id = v_remaining_store_id;

      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        UPDATE public.plantilla
        SET deployment_type   = 'Stationary',
            coverage_group_id = NULL,
            coverage_slot_id  = NULL,
            store_id          = v_remaining_store_id,
            store_name        = v_remaining_store_name,
            vcode             = v_remaining_store_vcode
        WHERE id = v_pl.id;

        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          UPDATE public.employee_store_allocations
          SET is_active = false, effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id AND is_active = true;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, NULL,
            v_remaining_store_id, v_remaining_store_vcode, v_remaining_store_name,
            v_pl.account_id, v_pl.group_id,
            1.0, 1,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        ELSE
          UPDATE public.plantilla_store_links
          SET status = 'Resigned', deleted_at = now()
          WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
        END IF;
      END LOOP;

      UPDATE public.coverage_group_stores
      SET archived_at = now(), archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = v_remaining_store_id
        AND archived_at IS NULL;

      UPDATE public.coverage_slots
      SET slot_status = 'closed', updated_at = now()
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND slot_status <> 'closed';

      UPDATE public.coverage_groups
      SET archived_at    = now(),
          archived_by    = p_actor_id,
          archive_reason = 'Coverage Request execution: converted remaining store to standalone'
      WHERE id = p_request.target_coverage_group_id;

      v_group_archived := true;
      v_notes := v_notes || ARRAY['remaining store converted to standalone; group archived'];
    END IF;

    -- Archive removed store edges + employee sync
    IF NOT v_group_archived THEN
      UPDATE public.coverage_group_stores
      SET archived_at = now(), archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at IS NULL;

      GET DIAGNOSTICS v_stores_removed = ROW_COUNT;

      FOR v_pl IN (
        SELECT * FROM public.plantilla
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND status = 'Active'
          AND is_deleted = false
          AND is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL
          OR v_pl.source_baseline_import_batch_id IS NOT NULL
        THEN
          UPDATE public.employee_store_allocations
          SET is_active = false, effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND is_active = true;

          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id AND is_active = true;

          IF v_active_allocs > 0 THEN
            UPDATE public.employee_store_allocations
            SET active_store_count = v_active_allocs,
                filled_hc = round(1.0 / v_active_allocs, 4)
            WHERE plantilla_id = v_pl.id AND is_active = true;
          END IF;
        ELSE
          UPDATE public.plantilla_store_links psl
          SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
          FROM public.stores s
          WHERE psl.vcode = s.vcode
            AND psl.plantilla_id = v_pl.id
            AND s.id = ANY(v_removed_store_ids)
            AND psl.deleted_at IS NULL;
        END IF;
      END LOOP;
    END IF;

    -- Vacancy Slot Reopening for each removed store
    FOREACH v_store_id IN ARRAY v_removed_store_ids LOOP
      SELECT
        s.store_name,
        s.vcode,
        s.account_id,
        s.group_id,
        a.account_name,
        COALESCE(s.area_city, s.area_province, '') AS area_name
      INTO
        v_store_name_local,
        v_store_vcode,
        v_store_account_id,
        v_store_group_id,
        v_store_account_name,
        v_store_area
      FROM public.stores s
      LEFT JOIN public.accounts a ON a.id = s.account_id
      WHERE s.id = v_store_id;

      v_store_group_id := COALESCE(v_store_group_id, v_cg_account_group_id);
      v_store_province_id := NULL;

      IF v_store_vcode IS NULL THEN
        v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
        CONTINUE;
      END IF;

      SELECT
        COALESCE(pl.position, 'Unknown'),
        pl.position_id,
        pl.chain_id
      INTO
        v_store_position,
        v_store_position_id,
        v_store_chain_id
      FROM public.plantilla pl
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.is_deleted = false
        AND pl.is_archived = false
      LIMIT 1;

      IF v_store_position IS NULL OR v_store_position = 'Unknown' THEN
        v_store_position    := COALESCE(v_cg_position_name, 'Unknown');
        v_store_position_id := COALESCE(v_store_position_id, v_cg_position_id);
      END IF;

      v_store_employment_type := 'Stationary';

      UPDATE public.vacancies
      SET status              = 'Open',
          is_archived         = false,
          archived_at         = NULL,
          has_pending_closure = false,
          vacant_date         = CURRENT_DATE,
          updated_at          = now()
      WHERE vcode      = v_store_vcode
        AND deleted_at IS NULL
        AND status IN ('Filled', 'Closed', 'Archived', 'Open');

      GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

      IF v_rows_updated = 0 THEN
        INSERT INTO public.vacancies (
          vcode, account, position,
          account_id, chain_id, store_id,
          province_id, area_name, position_id,
          vacant_date, vacancy_type, status,
          source_plantilla_id, store_name,
          created_at, updated_at, required_headcount
        ) VALUES (
          v_store_vcode,
          COALESCE(v_store_account_name, 'UNKNOWN'),
          COALESCE(v_store_position, 'Unknown'),
          v_store_account_id,
          v_store_chain_id,
          v_store_id,
          v_store_province_id,
          v_store_area,
          v_store_position_id,
          CURRENT_DATE,
          'Backfill',
          'Open',
          NULL,
          v_store_name_local,
          now(), now(), 1
        )
        ON CONFLICT DO NOTHING;
      END IF;

      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE store_id   = v_store_id
        AND account_id = v_store_account_id
        AND slot_status <> 'closed'
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status                   = 'open',
            employment_type               = 'Stationary',
            group_id                      = COALESCE(group_id, v_store_group_id),
            current_occupant_plantilla_id  = NULL,
            closed_at                      = NULL,
            closed_by                      = NULL,
            closure_reason_code            = NULL,
            updated_at                     = now(),
            updated_by                     = p_actor_id
        WHERE id = v_existing_slot_id;

        v_new_slot_id := v_existing_slot_id;
      ELSE
        SELECT id INTO v_existing_slot_id
        FROM public.plantilla_slots
        WHERE store_id   = v_store_id
          AND account_id = v_store_account_id
          AND slot_status = 'closed'
        ORDER BY updated_at DESC
        LIMIT 1;

        IF v_existing_slot_id IS NOT NULL THEN
          UPDATE public.plantilla_slots
          SET slot_status                   = 'open',
              employment_type               = 'Stationary',
              group_id                      = COALESCE(group_id, v_store_group_id),
              current_occupant_plantilla_id  = NULL,
              closed_at                      = NULL,
              closed_by                      = NULL,
              closure_reason_code            = NULL,
              legacy_vcode                   = COALESCE(legacy_vcode, v_store_vcode),
              updated_at                     = now(),
              updated_by                     = p_actor_id
          WHERE id = v_existing_slot_id;

          v_new_slot_id := v_existing_slot_id;
        ELSE
          v_new_slot_id := gen_random_uuid();
          INSERT INTO public.plantilla_slots (
            id, store_id, account_id, group_id,
            position, employment_type, is_roving,
            slot_status, legacy_vcode,
            created_by, updated_by, created_at, updated_at
          ) VALUES (
            v_new_slot_id,
            v_store_id, v_store_account_id, v_store_group_id,
            COALESCE(v_store_position, 'Unknown'),
            'Stationary',
            false,
            'open',
            v_store_vcode,
            p_actor_id, p_actor_id, now(), now()
          );
        END IF;
      END IF;

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type,
        old_value, new_value, reason_code,
        performed_by, remarks, created_at
      ) VALUES (
        v_new_slot_id,
        v_store_account_id,
        'coverage_store_removed',
        'occupied_or_closed',
        'open',
        'COVERAGE_STORE_REMOVED',
        p_actor_id,
        'Coverage Request: store removed from group. Request approved by ' || p_actor_name || '.',
        now()
      );

      v_stores_removed := v_stores_removed + 1;
      v_notes := v_notes || ARRAY[
        'store_removed:' || COALESCE(v_store_name_local, v_store_id::text)
        || '|vcode:' || v_store_vcode
        || '|account:' || COALESCE(v_store_account_name, '')
      ];
    END LOOP;

    IF NOT v_group_archived THEN
      SELECT COUNT(*) INTO v_stores_removed
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at >= now() - interval '10 seconds';
    ELSE
      v_stores_removed := array_length(v_removed_store_ids, 1);
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  p_request.request_type,
      'stores_added',                  v_stores_added,
      'stores_removed',                v_stores_removed,
      'removed_store_ids',             to_jsonb(v_removed_store_ids),
      'remaining_store_ids',           to_jsonb(v_remaining_store_ids),
      'remaining_count',               v_remaining_count,
      'group_archived',                v_group_archived,
      'anchor_removed',                v_anchor_removed,
      'below_minimum_action_applied',  v_below_minimum_action,
      'notes',                         to_jsonb(v_notes)
    );


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── dissolve_coverage_group ─────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN

    -- Pre-resolve group/position
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    v_employee_home_stores := COALESCE(
      p_request.payload -> 'employee_home_stores',
      '{}'::jsonb
    );

    -- require home store for every active employee
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND pl.is_deleted = false
        AND pl.is_archived = false
    ) LOOP
      IF (v_employee_home_stores ->> v_pl.id::text) IS NULL THEN
        RAISE EXCEPTION
          'Dissolve blocked: no retained home store selected for employee % (%). '
          'Select a home store for every active employee before dissolving.',
          COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
          USING ERRCODE = '23514';
      END IF;
    END LOOP;

    -- Collect the set of retained store IDs
    SELECT COALESCE(array_agg(DISTINCT val::uuid), ARRAY[]::uuid[])
    INTO v_retained_store_ids
    FROM jsonb_each_text(v_employee_home_stores) AS t(key, val);

    -- Validate retained home stores are active members
    IF v_retained_store_ids IS NOT NULL AND array_length(v_retained_store_ids, 1) > 0 THEN
      IF EXISTS (
        SELECT 1 FROM unnest(v_retained_store_ids) AS rid
        WHERE NOT EXISTS (
          SELECT 1 FROM public.coverage_group_stores
          WHERE coverage_group_id = p_request.target_coverage_group_id
            AND store_id = rid
            AND archived_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION
          'Dissolve blocked: one or more retained home stores are not active members of this coverage group.'
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- Compute stores losing coverage
    SELECT COALESCE(array_agg(cgs.store_id), ARRAY[]::uuid[])
    INTO v_dissolved_store_ids
    FROM public.coverage_group_stores cgs
    WHERE cgs.coverage_group_id = p_request.target_coverage_group_id
      AND cgs.archived_at IS NULL
      AND NOT (cgs.store_id = ANY(COALESCE(v_retained_store_ids, ARRAY[]::uuid[])));

    -- Convert employee to Stationary
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND pl.is_deleted = false
        AND pl.is_archived = false
    ) LOOP
      v_remaining_store_id := (v_employee_home_stores ->> v_pl.id::text)::uuid;

      SELECT s.store_name, s.vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores s WHERE s.id = v_remaining_store_id;

      UPDATE public.plantilla
      SET deployment_type   = 'Stationary',
          coverage_group_id = NULL,
          coverage_slot_id  = NULL,
          store_id          = v_remaining_store_id,
          store_name        = v_remaining_store_name,
          vcode             = v_remaining_store_vcode
      WHERE id = v_pl.id;

      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        UPDATE public.employee_store_allocations
        SET is_active = false, effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id
          AND is_active = true
          AND store_id <> v_remaining_store_id;

        IF NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id
            AND store_id = v_remaining_store_id
            AND is_active = true
        ) THEN
          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          ) VALUES (
            v_pl.id, v_pl.employee_no, NULL,
            v_remaining_store_id, v_remaining_store_vcode, v_remaining_store_name,
            v_pl.account_id, v_pl.group_id,
            1.0, 1,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          );
        ELSE
          UPDATE public.employee_store_allocations
          SET roving_group_id    = NULL,
              active_store_count = 1,
              filled_hc          = 1.0
          WHERE plantilla_id = v_pl.id
            AND store_id = v_remaining_store_id
            AND is_active = true;
        END IF;
      ELSE
        UPDATE public.plantilla_store_links psl
        SET status = 'Resigned', deleted_at = now(), unlinked_at = now(), unlinked_by = p_actor_id
        FROM public.stores s
        WHERE psl.vcode = s.vcode
          AND psl.plantilla_id = v_pl.id
          AND s.id <> v_remaining_store_id
          AND psl.deleted_at IS NULL;
      END IF;

      v_employees_converted := v_employees_converted + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|converted_to_stationary_at:' || COALESCE(v_remaining_store_name, v_remaining_store_id::text)
      ];
    END LOOP;

    -- Archive group store edges
    UPDATE public.coverage_group_stores
    SET archived_at = now(), archived_by = p_actor_id
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    -- Close slots
    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND slot_status <> 'closed';

    -- Archive group
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request execution: dissolved — employees converted to Stationary'
    WHERE id = p_request.target_coverage_group_id;

    v_group_archived := true;

    -- Reopen vacancies for stores that lost coverage
    IF v_dissolved_store_ids IS NOT NULL
      AND array_length(v_dissolved_store_ids, 1) > 0
    THEN
      FOREACH v_store_id IN ARRAY v_dissolved_store_ids LOOP
        SELECT
          s.store_name,
          s.vcode,
          s.account_id,
          s.group_id,
          a.account_name,
          COALESCE(s.area_city, s.area_province, '') AS area_name
        INTO
          v_store_name_local,
          v_store_vcode,
          v_store_account_id,
          v_store_group_id,
          v_store_account_name,
          v_store_area
        FROM public.stores s
        LEFT JOIN public.accounts a ON a.id = s.account_id
        WHERE s.id = v_store_id;

        v_store_group_id    := COALESCE(v_store_group_id, v_cg_account_group_id);
        v_store_province_id := NULL;
        v_store_chain_id    := NULL;

        IF v_store_vcode IS NULL THEN
          v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
          CONTINUE;
        END IF;

        v_store_position    := COALESCE(v_cg_position_name, 'Unknown');
        v_store_position_id := v_cg_position_id;
        v_store_employment_type := 'Stationary';

        UPDATE public.vacancies
        SET status              = 'Open',
            is_archived         = false,
            archived_at         = NULL,
            has_pending_closure = false,
            vacant_date         = CURRENT_DATE,
            updated_at          = now()
        WHERE vcode      = v_store_vcode
          AND deleted_at IS NULL
          AND status IN ('Filled', 'Closed', 'Archived', 'Open');

        GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

        IF v_rows_updated = 0 THEN
          INSERT INTO public.vacancies (
            vcode, account, position,
            account_id, chain_id, store_id,
            province_id, area_name, position_id,
            vacant_date, vacancy_type, status,
            source_plantilla_id, store_name,
            created_at, updated_at, required_headcount
          ) VALUES (
            v_store_vcode,
            COALESCE(v_store_account_name, 'UNKNOWN'),
            COALESCE(v_store_position, 'Unknown'),
            v_store_account_id,
            v_store_chain_id,
            v_store_id,
            v_store_province_id,
            v_store_area,
            v_store_position_id,
            CURRENT_DATE,
            'Backfill',
            'Open',
            NULL,
            v_store_name_local,
            now(), now(), 1
          )
          ON CONFLICT DO NOTHING;
        END IF;

        SELECT id INTO v_existing_slot_id
        FROM public.plantilla_slots
        WHERE store_id   = v_store_id
          AND account_id = v_store_account_id
          AND slot_status <> 'closed'
        ORDER BY created_at DESC
        LIMIT 1;

        IF v_existing_slot_id IS NOT NULL THEN
          UPDATE public.plantilla_slots
          SET slot_status                   = 'open',
              employment_type               = 'Stationary',
              group_id                      = COALESCE(group_id, v_store_group_id),
              current_occupant_plantilla_id  = NULL,
              closed_at                      = NULL,
              closed_by                      = NULL,
              closure_reason_code            = NULL,
              updated_at                     = now(),
              updated_by                     = p_actor_id
          WHERE id = v_existing_slot_id;

          v_new_slot_id := v_existing_slot_id;
        ELSE
          SELECT id INTO v_existing_slot_id
          FROM public.plantilla_slots
          WHERE store_id   = v_store_id
            AND account_id = v_store_account_id
            AND slot_status = 'closed'
          ORDER BY updated_at DESC
          LIMIT 1;

          IF v_existing_slot_id IS NOT NULL THEN
            UPDATE public.plantilla_slots
            SET slot_status                   = 'open',
                employment_type               = 'Stationary',
                group_id                      = COALESCE(group_id, v_store_group_id),
                current_occupant_plantilla_id  = NULL,
                closed_at                      = NULL,
                closed_by                      = NULL,
                closure_reason_code            = NULL,
                legacy_vcode                   = COALESCE(legacy_vcode, v_store_vcode),
                updated_at                     = now(),
                updated_by                     = p_actor_id
            WHERE id = v_existing_slot_id;

            v_new_slot_id := v_existing_slot_id;
          ELSE
            v_new_slot_id := gen_random_uuid();
            INSERT INTO public.plantilla_slots (
              id, store_id, account_id, group_id,
              position, employment_type, is_roving,
              slot_status, legacy_vcode,
              created_by, updated_by, created_at, updated_at
            ) VALUES (
              v_new_slot_id,
              v_store_id, v_store_account_id, v_store_group_id,
              COALESCE(v_store_position, 'Unknown'),
              'Stationary',
              false,
              'open',
              v_store_vcode,
              p_actor_id, p_actor_id, now(), now()
            );
          END IF;
        END IF;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_new_slot_id,
          v_store_account_id,
          'coverage_group_dissolved',
          'occupied_or_closed',
          'open',
          'COVERAGE_GROUP_DISSOLVED',
          p_actor_id,
          'Coverage Request: coverage group dissolved. Request approved by ' || p_actor_name || '.',
          now()
        );

        v_vacancies_reopened := v_vacancies_reopened + 1;
        v_notes := v_notes || ARRAY[
          'store_released:' || COALESCE(v_store_name_local, v_store_id::text)
          || '|vcode:' || v_store_vcode
          || '|account:' || COALESCE(v_store_account_name, '')
        ];
      END LOOP;
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'dissolve_coverage_group',
      'group_archived',               true,
      'employees_converted',          v_employees_converted,
      'vacancies_reopened',           v_vacancies_reopened,
      'notes',                        to_jsonb(v_notes)
    );

  -- ── Deferred types ──────────────────────────────────────────────────────────
  ELSE
    RETURN jsonb_build_object(
      'structural_execution_enabled', false,
      'request_type',                 p_request.request_type,
      'note',                         'Structural execution for this request type is deferred.',
      'stores_added',                 0,
      'stores_removed',               0,
      'group_archived',               false
    );
  END IF;
END;
$fn$;


-- ── §4. Re-apply view vw_slot_derived_vacancy_shadow ────────────────────────
-- Suppress vacancies for stores that belong to active Coverage Groups containing active coverage manpower.
-- ────────────────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow CASCADE;

CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_shadow AS
 WITH aging_basis AS (
         SELECT DISTINCT ON (sh.slot_id) sh.slot_id,
            sh.created_at AS open_episode_start
           FROM slot_history sh
          WHERE sh.new_value = 'open'::text
          ORDER BY sh.slot_id, sh.created_at DESC
        ), pending_closure AS (
         SELECT DISTINCT vcr.vacancy_vcode
           FROM vacancy_closure_requests vcr
             JOIN vacancies v_1 ON v_1.vcode = vcr.vacancy_vcode AND v_1.deleted_at IS NULL AND COALESCE(v_1.is_archived, false) = false
          WHERE vcr.status = 'Pending'::text
        )
 SELECT ps.legacy_vcode,
    v.id AS legacy_vacancy_id,
    v.store_name,
    v.area_city,
    v.province,
    v.area_name,
    v.required_headcount,
    (array_agg(ps.store_id ORDER BY ps.created_at, (ps.id::text)))[1] AS store_id,
    min(st.store_branch) AS store_branch,
    (array_agg(ps.account_id ORDER BY ps.created_at, (ps.id::text)))[1] AS account_id,
    min(a.account_name) AS account_name,
    (array_agg(ps.group_id ORDER BY ps.created_at, (ps.id::text)))[1] AS group_id,
    min(g.group_name) AS group_name,
    min(ps."position") AS "position",
    min(ps.employment_type) AS employment_type,
    false AS is_roving,
    count(*) AS required_hc,
    count(*) FILTER (WHERE ps.slot_status = 'open'::text) AS open_count,
    count(*) FILTER (WHERE ps.slot_status = 'pipeline'::text) AS pipeline_count,
    count(*) FILTER (WHERE ps.slot_status = 'hr_processing'::text) AS hr_processing_count,
    count(*) FILTER (WHERE ps.slot_status = 'occupied'::text) AS occupied_count,
    count(*) FILTER (WHERE ps.slot_status = 'closed'::text) AS closed_count,
    count(*) FILTER (WHERE ps.slot_status = 'pipeline'::text) AS active_applicant_count,
    bool_or(pc.vacancy_vcode IS NOT NULL) AS has_pending_closure,
        CASE
            WHEN bool_or(pc.vacancy_vcode IS NOT NULL) THEN 'Closure'::text
            WHEN count(*) FILTER (WHERE ps.slot_status = 'open'::text) > 0 THEN 'Open'::text
            WHEN count(*) FILTER (WHERE ps.slot_status = 'pipeline'::text) > 0 THEN 'Pipeline'::text
            WHEN count(*) FILTER (WHERE ps.slot_status = 'closed'::text) = count(*) AND count(*) > 0 THEN 'Closure'::text
            ELSE NULL::text
        END AS vacancy_tab,
    min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text) AS aging_start_at,
        CASE
            WHEN count(*) FILTER (WHERE ps.slot_status = 'open'::text) = 0 THEN NULL::integer
            WHEN min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text)::date > CURRENT_DATE THEN NULL::integer
            ELSE CURRENT_DATE - min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text)::date
        END AS aging_days,
    min(ps.created_at) AS created_at,
    max(ps.updated_at) AS updated_at,
    max(ps.closed_at) AS closed_at,
    (array_agg(ps.source_hc_request_id ORDER BY ps.created_at, (ps.id::text)))[1] AS source_hc_request_id,
    v.urgency_level,
    v.hrco_name,
    v.hrco_user_id,
    v.target_fill_date,
    v.triggered_by_user_id,
    v.triggered_by_name
   FROM plantilla_slots ps
     LEFT JOIN aging_basis ab ON ab.slot_id = ps.id
     LEFT JOIN stores st ON st.id = ps.store_id
     LEFT JOIN accounts a ON a.id = ps.account_id
     LEFT JOIN groups g ON g.id = ps.group_id
     LEFT JOIN pending_closure pc ON pc.vacancy_vcode = ps.legacy_vcode
     JOIN vacancies v ON v.vcode = ps.legacy_vcode AND v.deleted_at IS NULL AND COALESCE(v.is_archived, false) = false AND v.status <> 'Archived'::text
  WHERE ps.legacy_vcode IS NOT NULL AND ps.is_roving = false
    -- Suppress vacancies for stores that belong to active Coverage Groups containing active coverage manpower.
    AND NOT EXISTS (
      SELECT 1 FROM public.coverage_group_stores cgs
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      WHERE cgs.store_id = ps.store_id
        AND cgs.archived_at IS NULL
        AND cg.archived_at IS NULL
        AND EXISTS (
          SELECT 1 FROM public.plantilla pl
          WHERE pl.coverage_group_id = cg.id
            AND pl.status = 'Active'
            AND COALESCE(pl.is_deleted, false) = false
            AND COALESCE(pl.is_archived, false) = false
        )
    )
  GROUP BY ps.legacy_vcode, v.id;

-- Re-grant permissions
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;

COMMIT;
