-- Migration: reassert_function_bodies
-- Purpose: Migration integrity recovery (non-functional, no behavior change).
-- Reasserts the CURRENT LIVE staging bodies of functions whose migration-history-derived
-- definitions have drifted from what is actually live, and of functions with no
-- reproducible CREATE FUNCTION statement anywhere in migration history. This file is the
-- single source of truth for these functions going forward, so a fresh-database replay of
-- the full migration chain reproduces current live staging state exactly.
--
-- Source of truth: pg_get_functiondef() against staging (qqiiznmqxfoamqytjica), 2026-07-02.
-- Scope: 145 functions (129 drifted vs. migration history, 16 with no prior migration
-- definition at all). See supabase/migrations/_fn_drift_report_v2.json for the full
-- per-function classification this migration was generated from.
--
-- Safety: idempotent CREATE OR REPLACE FUNCTION only. No DROP, no data mutation, no schema
-- changes, no new logic. Statement order is immaterial: every function this migration
-- touches already exists as a live catalog object by the time this migration runs (either
-- created by an earlier migration in the chain, or already present as an application-level
-- function on the target database), and CREATE OR REPLACE FUNCTION does not require its
-- callees to already carry their final body, only to already exist by name/signature.

BEGIN;

CREATE OR REPLACE FUNCTION public._coverage_request_review_artifacts(p_request coverage_requests)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public._execute_approved_coverage_request(p_request coverage_requests, p_actor_id uuid, p_actor_name text, p_actor_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- ── ohm#8a4f71d2 merge_coverage_groups variables
  v_surviving_cg_id        uuid;
  v_merged_cg_id           uuid;
  v_surviving_cg_code      text;
  v_merged_cg_code         text;
  v_stores_transferred     integer := 0;
  v_employees_transferred  integer := 0;
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
        AND (p_request.position_id IS NULL OR pl.position_id = p_request.position_id)
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
    IF v_slot_ordinal < v_store_count AND v_employees_converted = 0 THEN
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
        AND status NOT IN ('Open', 'Pipeline');

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


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── merge_coverage_groups (ohm#8a4f71d2) ────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'merge_coverage_groups'::public.request_type THEN

    -- ── Step 1: Load both CGs (FOR UPDATE) ─────────────────────────────────
    SELECT coverage_code INTO v_surviving_cg_code
    FROM public.coverage_groups
    WHERE id = p_request.source_coverage_group_id AND archived_at IS NULL
    FOR UPDATE;

    SELECT coverage_code INTO v_merged_cg_code
    FROM public.coverage_groups
    WHERE id = p_request.destination_coverage_group_id AND archived_at IS NULL
    FOR UPDATE;

    IF v_surviving_cg_code IS NULL OR v_merged_cg_code IS NULL THEN
      RAISE EXCEPTION 'merge: one or both coverage groups not found or archived'
        USING ERRCODE = 'P0002';
    END IF;

    -- ── Step 2: Determine surviving (lowest CGCode) vs merged (higher) ─────
    IF v_surviving_cg_code <= v_merged_cg_code THEN
      -- source = surviving, destination = merged
      v_surviving_cg_id   := p_request.source_coverage_group_id;
      v_merged_cg_id      := p_request.destination_coverage_group_id;
      -- codes already assigned correctly above
    ELSE
      -- destination = surviving, source = merged
      v_surviving_cg_id   := p_request.destination_coverage_group_id;
      v_surviving_cg_code := v_merged_cg_code;  -- destination has lower code
      v_merged_cg_id      := p_request.source_coverage_group_id;
      v_merged_cg_code    := v_surviving_cg_code;  -- source has higher code
    END IF;

    -- Re-resolve codes from IDs to avoid swap confusion
    SELECT coverage_code INTO v_surviving_cg_code
    FROM public.coverage_groups WHERE id = v_surviving_cg_id;
    SELECT coverage_code INTO v_merged_cg_code
    FROM public.coverage_groups WHERE id = v_merged_cg_id;

    -- ── Step 3: Transfer stores: merged → surviving ─────────────────────────
    UPDATE public.coverage_group_stores
    SET coverage_group_id = v_surviving_cg_id
    WHERE coverage_group_id = v_merged_cg_id
      AND archived_at IS NULL;

    GET DIAGNOSTICS v_stores_transferred = ROW_COUNT;

    -- ── Step 4: Transfer employees from merged CG → surviving CG ───────────
    -- Get current max slot_ordinal in surviving CG
    SELECT COALESCE(MAX(slot_ordinal), 0) INTO v_slot_ordinal
    FROM public.coverage_slots
    WHERE coverage_group_id = v_surviving_cg_id;

    FOR v_pl IN (
      SELECT pl.*, a.group_id AS account_group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = v_merged_cg_id
        AND pl.status = 'Active'
        AND COALESCE(pl.is_deleted, false) = false
        AND COALESCE(pl.is_archived, false) = false
    ) LOOP
      -- Close old coverage_slot in merged group
      IF v_pl.coverage_slot_id IS NOT NULL THEN
        UPDATE public.coverage_slots
        SET slot_status = 'closed', updated_at = now()
        WHERE id = v_pl.coverage_slot_id;
      END IF;

      -- Create new occupied coverage_slot in surviving group
      v_slot_id := gen_random_uuid();
      v_slot_ordinal := v_slot_ordinal + 1;

      INSERT INTO public.coverage_slots (
        id, coverage_group_id, slot_ordinal, slot_status,
        current_occupant_plantilla_id, created_at, updated_at
      ) VALUES (
        v_slot_id, v_surviving_cg_id, v_slot_ordinal, 'active',
        v_pl.id, now(), now()
      );

      -- Update employee to surviving group + new slot
      UPDATE public.plantilla
      SET coverage_group_id = v_surviving_cg_id,
          coverage_slot_id  = v_slot_id
      WHERE id = v_pl.id;

      -- Handle ESA / store links
      IF v_pl.source_employee_import_batch_id IS NOT NULL
         OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        -- Imported employee: update roving_group_id to surviving CG
        UPDATE public.employee_store_allocations
        SET roving_group_id = v_surviving_cg_id
        WHERE plantilla_id = v_pl.id AND is_active = true;
      ELSE
        -- Non-imported employee: update coverage_group_id on active store links
        UPDATE public.plantilla_store_links
        SET coverage_group_id = v_surviving_cg_id
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
        -- fn_sync called after store collection is complete (below)
      END IF;

      v_employees_transferred := v_employees_transferred + 1;
      v_notes := v_notes || ARRAY[
        'employee_transferred:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|from:' || v_merged_cg_code
        || '|to:' || v_surviving_cg_code
      ];
    END LOOP;

    -- ── Step 5: Collect total stores in surviving CG after merge ───────────
    SELECT COALESCE(array_agg(DISTINCT store_id), ARRAY[]::uuid[]) INTO v_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = v_surviving_cg_id AND archived_at IS NULL;

    v_store_count := COALESCE(array_length(v_store_ids, 1), 0);

    -- ── Step 6: ESA rebalancing for all imported employees in surviving CG ──
    --   Includes both original surviving employees (who now cover merged stores)
    --   and transferred employees (who now cover surviving + merged stores).
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = v_surviving_cg_id
        AND status = 'Active'
        AND COALESCE(is_deleted, false) = false
        AND COALESCE(is_archived, false) = false
        AND (source_employee_import_batch_id IS NOT NULL
             OR source_baseline_import_batch_id IS NOT NULL)
    ) LOOP
      -- Insert ESA rows for any stores not yet covered
      FOREACH v_store_id IN ARRAY v_store_ids LOOP
        IF NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id
            AND store_id = v_store_id
            AND is_active = true
        ) THEN
          SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
          FROM public.stores WHERE id = v_store_id;

          INSERT INTO public.employee_store_allocations (
            plantilla_id, employee_no, roving_group_id,
            store_id, vcode, store_name,
            account_id, group_id,
            filled_hc, active_store_count,
            effective_start, is_active,
            source_import_batch_id, created_by
          )
          SELECT
            v_pl.id, v_pl.employee_no, v_surviving_cg_id,
            v_store_id, v_store_vcode, v_store_name_local,
            v_pl.account_id,
            COALESCE(v_pl.group_id, (SELECT group_id FROM public.accounts WHERE id = v_pl.account_id)),
            CASE WHEN v_store_count > 0 THEN round(1.0 / v_store_count, 4) ELSE 1.0 END,
            v_store_count,
            CURRENT_DATE, true,
            v_pl.source_baseline_import_batch_id, p_actor_id
          WHERE NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations
            WHERE plantilla_id = v_pl.id AND store_id = v_store_id AND is_active = true
          );
        END IF;
      END LOOP;

      -- Rebalance filled_hc for all active ESA rows
      SELECT COUNT(*) INTO v_active_allocs
      FROM public.employee_store_allocations
      WHERE plantilla_id = v_pl.id AND is_active = true;

      IF v_active_allocs > 0 THEN
        UPDATE public.employee_store_allocations
        SET active_store_count = v_active_allocs,
            filled_hc          = round(1.0 / v_active_allocs, 4),
            roving_group_id    = v_surviving_cg_id
        WHERE plantilla_id = v_pl.id AND is_active = true;
      END IF;
    END LOOP;

    -- ── Step 7: fn_sync for non-imported employees in surviving CG ──────────
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = v_surviving_cg_id
        AND status = 'Active'
        AND COALESCE(is_deleted, false) = false
        AND COALESCE(is_archived, false) = false
        AND source_employee_import_batch_id IS NULL
        AND source_baseline_import_batch_id IS NULL
    ) LOOP
      PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
    END LOOP;

    -- ── Step 8: Transfer applicants ─────────────────────────────────────────
    UPDATE public.applicants
    SET coverage_group_id = v_surviving_cg_id
    WHERE coverage_group_id = v_merged_cg_id
      AND COALESCE(is_archived, false) = false;

    -- ── Step 9: Update surviving group required_headcount = total stores ────
    UPDATE public.coverage_groups
    SET required_headcount = v_store_count
    WHERE id = v_surviving_cg_id
      AND v_store_count > 0;

    -- ── Step 10: Close remaining coverage_slots in merged CG ───────────────
    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = v_merged_cg_id
      AND slot_status <> 'closed';

    -- ── Step 11: Archive merged group with merge metadata ──────────────────
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Merged into ' || v_surviving_cg_code || ' by Coverage Request execution',
        merged_into    = v_surviving_cg_id,
        merged_at      = now(),
        merged_by      = p_actor_id
    WHERE id = v_merged_cg_id;

    -- ── Step 12: Update coverage_request target → surviving CG ─────────────
    UPDATE public.coverage_requests
    SET target_coverage_group_id = v_surviving_cg_id
    WHERE id = p_request.id;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                  'merge_coverage_groups',
      'surviving_cg_id',               v_surviving_cg_id,
      'surviving_cg_code',             v_surviving_cg_code,
      'merged_cg_id',                  v_merged_cg_id,
      'merged_cg_code',                v_merged_cg_code,
      'stores_transferred',            v_stores_transferred,
      'employees_transferred',         v_employees_transferred,
      'total_stores',                  v_store_count,
      'notes',                         to_jsonb(v_notes)
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
$function$;

CREATE OR REPLACE FUNCTION public._log_coverage_request_history(p_coverage_request_id uuid, p_from_status request_status, p_to_status request_status, p_event_type text, p_event_payload jsonb DEFAULT '{}'::jsonb, p_actor_id uuid DEFAULT NULL::uuid, p_actor_name text DEFAULT NULL::text, p_actor_role text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.coverage_request_history (
    coverage_request_id,
    from_status,
    to_status,
    event_type,
    event_payload,
    actor_id,
    actor_name,
    actor_role,
    note
  ) VALUES (
    p_coverage_request_id,
    p_from_status,
    p_to_status,
    p_event_type,
    COALESCE(p_event_payload, '{}'::jsonb),
    p_actor_id,
    p_actor_name,
    p_actor_role,
    NULLIF(TRIM(COALESCE(p_note, '')), '')
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public._ohm_normalize_role(p_role text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(regexp_replace(coalesce(p_role, ''), '[^a-z0-9]', '', 'gi'));
$function$;

CREATE OR REPLACE FUNCTION public._review_coverage_request_phase3(p_coverage_request_id uuid, p_decision request_status, p_reviewer_remarks text DEFAULT NULL::text, p_rejection_reason text DEFAULT NULL::text)
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

CREATE OR REPLACE FUNCTION public._rnw_notify_roles(p_roles text[], p_title text, p_message text, p_notif_type text, p_event_type text, p_ref_type text, p_ref_id text, p_deep_link text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN
    SELECT DISTINCT ON (up.auth_user_id) up.auth_user_id, ro.role_name
    FROM public.users_profile up
    JOIN public.roles ro         ON ro.id  = up.role_id
    JOIN auth.users   au         ON au.id  = up.auth_user_id  -- skip stale/deleted auth users
    WHERE up.is_active      = true
      AND up.auth_user_id  IS NOT NULL
      AND ro.role_name      = ANY (p_roles)
    ORDER BY up.auth_user_id
  LOOP
    BEGIN
      PERFORM public.notify_user(
        r.auth_user_id, r.role_name, p_title, p_message,
        p_notif_type, p_event_type, p_ref_type, p_ref_id, p_deep_link, NULL
      );
      n := n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        '_rnw_notify_roles: skipped recipient %, role %, ref_id %, error: %',
        r.auth_user_id, r.role_name, p_ref_id, SQLERRM;
    END;
  END LOOP;
  RETURN n;
END;
$function$;

CREATE OR REPLACE FUNCTION public._validate_coverage_request_payload(p_request_type request_type, p_payload jsonb, p_account_id uuid DEFAULT NULL::uuid, p_position_id uuid DEFAULT NULL::uuid, p_employment_type text DEFAULT NULL::text, p_target_coverage_group_id uuid DEFAULT NULL::uuid, p_source_coverage_group_id uuid DEFAULT NULL::uuid, p_destination_coverage_group_id uuid DEFAULT NULL::uuid, p_request_id uuid DEFAULT NULL::uuid, p_skip_cg_pending_guard boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_store_ids               uuid[];
  v_anchor_store_id         uuid;
  v_target_account_id       uuid;
  v_source_account_id       uuid;
  v_destination_account_id  uuid;
  v_gap09_employee_name     text;
  v_gap10_cg_code           text;
  v_action_noun             text;
  v_conflicting_store_name  text;
BEGIN

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'payload must be a json object' USING ERRCODE = '22023';
  END IF;

  IF p_payload::text ~* '"(required_hc|required_headcount|headcount|hc|slot_id|slot_ids|vacancy_id|vacancy_vcode|vcode|pipeline_id|coverage_weight|hc_share|store_count)"[[:space:]]*:' THEN
    RAISE EXCEPTION
      'Coverage Request payload must remain structure-only; HC, slot, vacancy, pipeline, coverage weight, and HC share fields are not allowed'
      USING ERRCODE = '22023';
  END IF;

  v_action_noun := CASE
    WHEN p_request_type = 'create_coverage_group'::public.request_type THEN 'create Coverage Group'
    WHEN p_request_type = 'add_store'::public.request_type            THEN 'add store'
    WHEN p_request_type = 'remove_store'::public.request_type         THEN 'remove store'
    WHEN p_request_type = 'dissolve_coverage_group'::public.request_type THEN 'dissolve Coverage Group'
    ELSE 'process coverage request'
  END;

  IF p_target_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_target_account_id
    FROM public.coverage_groups
    WHERE id = p_target_coverage_group_id AND archived_at IS NULL;
    IF v_target_account_id IS NULL THEN
      PERFORM public.fn_normalize_imported_roving_group(p_target_coverage_group_id);
      SELECT account_id INTO v_target_account_id
      FROM public.coverage_groups
      WHERE id = p_target_coverage_group_id AND archived_at IS NULL;
    END IF;
    IF v_target_account_id IS NULL THEN
      RAISE EXCEPTION 'target coverage group not found or archived' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF p_source_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_source_account_id
    FROM public.coverage_groups WHERE id = p_source_coverage_group_id AND archived_at IS NULL;
  END IF;

  IF p_destination_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_destination_account_id
    FROM public.coverage_groups WHERE id = p_destination_coverage_group_id AND archived_at IS NULL;
  END IF;

  IF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_target_coverage_group_id AND archived_at IS NULL;
  ELSE
    IF p_payload ? 'store_ids' THEN
      v_store_ids := public._coverage_request_uuid_array(
        p_payload, 'store_ids',
        (p_request_type = 'remove_store'::public.request_type)
      );
    END IF;
  END IF;

  IF p_request_type = 'create_coverage_group'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['store_ids', 'anchor_store_id', 'area_name', 'employment_type', 'notes']
    );
    IF p_account_id IS NULL THEN
      RAISE EXCEPTION 'create_coverage_group requires account_id' USING ERRCODE = '22023';
    END IF;
    IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
      SELECT cg.coverage_code INTO v_gap10_cg_code
      FROM unnest(v_store_ids) AS sid
      JOIN public.coverage_group_stores cgs ON cgs.store_id = sid
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      WHERE cgs.archived_at IS NULL AND cg.archived_at IS NULL
      LIMIT 1;
      IF v_gap10_cg_code IS NOT NULL THEN
        RAISE EXCEPTION 'Store already belongs to Coverage Group %.', v_gap10_cg_code USING ERRCODE = '23514';
      END IF;
    END IF;
  ELSIF p_request_type = 'add_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'add_store requires target_coverage_group_id' USING ERRCODE = '22023';
    END IF;
    IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
      SELECT cg.coverage_code INTO v_gap10_cg_code
      FROM unnest(v_store_ids) AS sid
      JOIN public.coverage_group_stores cgs ON cgs.store_id = sid
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      WHERE cgs.archived_at IS NULL AND cg.archived_at IS NULL
        AND cg.id <> p_target_coverage_group_id
      LIMIT 1;
      IF v_gap10_cg_code IS NOT NULL THEN
        RAISE EXCEPTION 'Store already belongs to Coverage Group %.', v_gap10_cg_code USING ERRCODE = '23514';
      END IF;
    END IF;
  ELSIF p_request_type = 'remove_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['store_ids', 'below_minimum_action', 'notes']
    );
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'remove_store requires target_coverage_group_id' USING ERRCODE = '22023';
    END IF;
  ELSIF p_request_type = 'convert_stationary_to_roving'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['store_ids', 'anchor_store_id', 'area_name', 'employment_type', 'notes']
    );
    IF p_account_id IS NULL THEN
      RAISE EXCEPTION 'convert_stationary_to_roving requires account_id' USING ERRCODE = '22023';
    END IF;
  ELSIF p_request_type = 'convert_roving_to_stationary'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'convert_roving_to_stationary requires target_coverage_group_id' USING ERRCODE = '22023';
    END IF;
  ELSIF p_request_type = 'merge_coverage_groups'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['notes']);
    IF p_source_coverage_group_id IS NULL OR p_destination_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'merge_coverage_groups requires source_coverage_group_id and destination_coverage_group_id' USING ERRCODE = '22023';
    END IF;
    IF p_source_coverage_group_id = p_destination_coverage_group_id THEN
      RAISE EXCEPTION 'merge_coverage_groups source and destination must be different' USING ERRCODE = '22023';
    END IF;
    IF v_source_account_id <> v_destination_account_id THEN
      RAISE EXCEPTION 'merge_coverage_groups source and destination must belong to the same account' USING ERRCODE = '22023';
    END IF;
  ELSIF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['notes', 'employee_home_stores']
    );
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'dissolve_coverage_group requires target_coverage_group_id' USING ERRCODE = '22023';
    END IF;
    IF (p_payload -> 'employee_home_stores') IS NOT NULL
       AND jsonb_typeof(p_payload -> 'employee_home_stores') <> 'object'
    THEN
      RAISE EXCEPTION 'employee_home_stores must be a JSON object {plantilla_id: store_id}' USING ERRCODE = '22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'unsupported request_type: %', p_request_type USING ERRCODE = '22023';
  END IF;

  IF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    IF (p_payload -> 'employee_home_stores') IS NOT NULL THEN
      SELECT pl.employee_name INTO v_gap09_employee_name
      FROM public.plantilla pl
      WHERE pl.coverage_group_id = p_target_coverage_group_id
        AND pl.status = 'Active'
        AND COALESCE(pl.is_deleted,  false) = false
        AND COALESCE(pl.is_archived, false) = false
        AND (pl.source_employee_import_batch_id IS NOT NULL OR pl.source_baseline_import_batch_id IS NOT NULL)
        AND NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations esa
          WHERE esa.plantilla_id = pl.id AND esa.store_id = ANY(v_store_ids) AND esa.is_active = true
        )
      LIMIT 1;
      IF v_gap09_employee_name IS NOT NULL THEN
        RAISE EXCEPTION 'Selected Home Store is not assigned to employee.' USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;

  IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      IF (SELECT COUNT(DISTINCT id) != COUNT(*) FROM unnest(v_store_ids) AS id) THEN
        RAISE EXCEPTION 'Cannot %. Selected stores list contains duplicates.', v_action_noun USING ERRCODE = '23514';
      END IF;
    END IF;
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      SELECT store_name INTO v_conflicting_store_name
      FROM public.stores WHERE id = ANY(v_store_ids) AND (is_active = false OR status = 'archived') LIMIT 1;
      IF v_conflicting_store_name IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot %. Store % is inactive or archived.', v_action_noun, v_conflicting_store_name USING ERRCODE = '23514';
      END IF;
    END IF;
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      DECLARE v_scoped_account_id uuid;
      BEGIN
        v_scoped_account_id := p_account_id;
        IF v_scoped_account_id IS NULL AND p_target_coverage_group_id IS NOT NULL THEN
          SELECT account_id INTO v_scoped_account_id FROM public.coverage_groups WHERE id = p_target_coverage_group_id;
        END IF;
        IF v_scoped_account_id IS NOT NULL THEN
          SELECT store_name INTO v_conflicting_store_name
          FROM public.stores WHERE id = ANY(v_store_ids) AND account_id <> v_scoped_account_id LIMIT 1;
          IF v_conflicting_store_name IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot %. Store % does not belong to the selected account scope.', v_action_noun, v_conflicting_store_name USING ERRCODE = '23514';
          END IF;
        END IF;
      END;
    END IF;
    IF p_request_type IN ('create_coverage_group', 'convert_stationary_to_roving') THEN
      IF (SELECT COUNT(DISTINCT island_group) FROM public.stores WHERE id = ANY(v_store_ids)) > 1 THEN
        RAISE EXCEPTION 'Cannot %. Stores must belong to the same island group.', v_action_noun USING ERRCODE = '23514';
      END IF;
    END IF;
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'dissolve_coverage_group') THEN
      DECLARE v_conflicting_store_name text;
      BEGIN
        WITH pending_requests AS (
          SELECT id, request_type, payload, target_coverage_group_id, source_coverage_group_id, destination_coverage_group_id
          FROM public.coverage_requests
          WHERE status = 'pending'::public.request_status AND archived_at IS NULL
            AND (p_request_id IS NULL OR id <> p_request_id)
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
          WHERE pr.request_type = 'dissolve_coverage_group' AND cgs.archived_at IS NULL
          UNION
          SELECT DISTINCT cgs.store_id
          FROM pending_requests pr
          JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id IN (pr.source_coverage_group_id, pr.destination_coverage_group_id)
          WHERE pr.request_type = 'merge_coverage_groups' AND cgs.archived_at IS NULL
        )
        SELECT store_name INTO v_conflicting_store_name
        FROM public.stores WHERE id = ANY(v_store_ids) AND id IN (SELECT s_id FROM pending_stores) LIMIT 1;
        IF v_conflicting_store_name IS NOT NULL THEN
          RAISE EXCEPTION 'Cannot %. One or more selected stores already have a pending coverage request. Pending request already exists for: %',
            v_action_noun, v_conflicting_store_name USING ERRCODE = '23514';
        END IF;
      END;
    END IF;
  END IF;

  IF NOT p_skip_cg_pending_guard AND p_request_type <> 'create_coverage_group'::public.request_type THEN
    DECLARE v_pending_for_group uuid;
    BEGIN
      SELECT id INTO v_pending_for_group
      FROM public.coverage_requests
      WHERE status = 'pending'::public.request_status AND archived_at IS NULL
        AND (p_request_id IS NULL OR id <> p_request_id)
        AND (
          (p_target_coverage_group_id IS NOT NULL AND (
            target_coverage_group_id = p_target_coverage_group_id OR
            source_coverage_group_id = p_target_coverage_group_id OR
            destination_coverage_group_id = p_target_coverage_group_id
          ))
          OR (p_source_coverage_group_id IS NOT NULL AND (
            target_coverage_group_id = p_source_coverage_group_id OR
            source_coverage_group_id = p_source_coverage_group_id OR
            destination_coverage_group_id = p_source_coverage_group_id
          ))
          OR (p_destination_coverage_group_id IS NOT NULL AND (
            target_coverage_group_id = p_destination_coverage_group_id OR
            source_coverage_group_id = p_destination_coverage_group_id OR
            destination_coverage_group_id = p_destination_coverage_group_id
          ))
        )
      LIMIT 1;
      IF v_pending_for_group IS NOT NULL THEN
        RAISE EXCEPTION 'This Coverage Group already has a pending request. Please approve or reject the current request before creating another one.' USING ERRCODE = '23514';
      END IF;
    END;
  END IF;

END;
$function$;

CREATE OR REPLACE FUNCTION public.add_applicant_to_coverage_group(p_coverage_group_id uuid, p_last_name text, p_first_name text, p_contact_number text, p_middle_name text DEFAULT NULL::text, p_status text DEFAULT 'new'::text, p_remarks text DEFAULT NULL::text, p_source_channel text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor       uuid;
  v_grp         public.coverage_groups%ROWTYPE;
  v_status_opt  public.applicant_status_options%ROWTYPE;
  v_app_id      uuid;
  v_full_name   text;
  v_middle      text;
  v_bind_result jsonb;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR public.i_am_ops()
    OR public.i_am_recruitment()
  ) THEN
    RAISE EXCEPTION 'forbidden: insufficient role to add applicants to a coverage group'
      USING ERRCODE = '42501';
  END IF;

  v_actor := public.get_my_profile_id();

  SELECT cg.* INTO v_grp
  FROM public.coverage_groups cg
  JOIN public.accounts a
    ON a.id = cg.account_id
   AND a.is_active = true
   AND lower(COALESCE(a.status, 'active')) <> 'archived'
  WHERE cg.id = p_coverage_group_id
    AND cg.archived_at IS NULL
    AND lower(COALESCE(cg.status, '')) <> 'archived';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found or archived'
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_grp.account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: coverage group account outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_status_opt
  FROM public.applicant_status_options
  WHERE status_code = p_status
    AND is_active = true
    AND allow_on_create = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid or non-createable status_code: %', p_status
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.coverage_slots
    WHERE coverage_group_id = p_coverage_group_id
      AND slot_status = 'open'
    LIMIT 1
  ) THEN
    RAISE EXCEPTION
      'no_open_coverage_slot: % has no open slots. All required headcount is currently in pipeline or filled. Contact your Admin to create an approved roving HC Request before adding another applicant.',
      v_grp.coverage_code
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.applicants a
    WHERE LOWER(TRIM(a.contact_number)) = LOWER(TRIM(p_contact_number))
      AND LOWER(TRIM(a.last_name)) = LOWER(TRIM(p_last_name))
      AND LOWER(TRIM(a.first_name)) = LOWER(TRIM(p_first_name))
      AND (
        p_middle_name IS NULL
        OR TRIM(COALESCE(p_middle_name, '')) = ''
        OR LOWER(TRIM(a.middle_name)) = LOWER(TRIM(p_middle_name))
      )
      AND public.fn_is_active_vacancy_applicant_status(a.status)
      AND COALESCE(a.is_archived, false) = false
      AND (
        (a.coverage_group_id IS NOT NULL AND a.coverage_group_id <> p_coverage_group_id)
        OR (a.coverage_slot_id IS NULL AND a.vacancy_vcode IS NOT NULL)
      )
  ) THEN
    RAISE EXCEPTION
      'duplicate_applicant_identity: An active applicant with the same name and contact number already exists in another vacancy or coverage group. Back out or archive the existing applicant record before adding a new one.'
      USING ERRCODE = 'P0001';
  END IF;

  v_middle := NULLIF(TRIM(COALESCE(p_middle_name, '')), '');
  v_full_name := TRIM(p_last_name) || ', ' || TRIM(p_first_name)
    || CASE WHEN v_middle IS NOT NULL THEN ' ' || v_middle ELSE '' END;

  INSERT INTO public.applicants (
    last_name,
    first_name,
    middle_name,
    full_name,
    contact_number,
    status,
    remarks,
    is_archived
  ) VALUES (
    TRIM(p_last_name),
    TRIM(p_first_name),
    v_middle,
    v_full_name,
    TRIM(p_contact_number),
    v_status_opt.label,
    NULLIF(TRIM(COALESCE(p_remarks, '')), ''),
    false
  )
  RETURNING id INTO v_app_id;

  SELECT public.fn_bind_applicant_to_coverage_group(
    p_applicant_id => v_app_id,
    p_coverage_group_id => p_coverage_group_id,
    p_performed_by => v_actor
  ) INTO v_bind_result;

  IF (v_bind_result->>'status') <> 'ok' THEN
    RAISE EXCEPTION
      'coverage_slot_bind_failed: slot transition blocked - %. The open slot may have been claimed concurrently. Please try again.',
      COALESCE(v_bind_result->>'blocked_reason', 'unknown')
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.log_audit_event(
    'vacancy_module',
    'INSERT',
    v_app_id,
    NULL,
    jsonb_build_object(
      'action', 'add_applicant_to_coverage_group',
      'coverage_group_id', p_coverage_group_id,
      'coverage_code', v_grp.coverage_code,
      'coverage_slot_id', v_bind_result->>'coverage_slot_id',
      'slot_ordinal', v_bind_result->>'slot_ordinal'
    )
  );

  RETURN jsonb_build_object(
    'applicant_id', v_app_id,
    'coverage_group_id', p_coverage_group_id,
    'coverage_slot_id', (v_bind_result->>'coverage_slot_id')::uuid,
    'slot_ordinal', (v_bind_result->>'slot_ordinal')::integer
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_correction_request(p_correction_request_id uuid, p_approved_by text DEFAULT NULL::text)
 RETURNS hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.hr_emploc;
BEGIN
  SELECT * INTO v_row
  FROM public.hr_emploc
  WHERE id = p_correction_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'HR Emploc record not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_row.hr_status <> 'For Review' THEN
    RAISE EXCEPTION 'Only For Review records can be approved'
      USING ERRCODE = 'P0001';
  END IF;

  IF coalesce(nullif(trim(v_row.employee_no), ''), nullif(trim(v_row.emploc_no), '')) IS NULL THEN
    RAISE EXCEPTION 'EMPLoc number required before approval'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.hr_emploc
  SET
    hr_status              = 'Complete',
    status                 = 'Ready for Plantilla',
    hr_reviewed_by         = coalesce(nullif(trim(p_approved_by), ''), get_my_full_name()),
    hr_reviewed_by_user_id = get_my_profile_id(),
    hr_reviewed_at         = now(),
    updated_at             = now(),
    updated_by             = get_my_profile_id()
  WHERE id = p_correction_request_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_coverage_request(p_coverage_request_id uuid, p_reviewer_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public._review_coverage_request_phase3(
    p_coverage_request_id,
    'approved'::public.request_status,
    p_reviewer_remarks,
    NULL
  );
$function$;

CREATE OR REPLACE FUNCTION public.approve_hr_emploc_import(p_batch_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id          UUID;
  v_profile_id         UUID;
  v_batch              public.hr_emploc_import_batches%ROWTYPE;
  v_row                public.hr_emploc_import_rows%ROWTYPE;
  v_account_id         UUID;
  v_account_name       TEXT;
  v_hr_id              UUID;
  v_full_name          TEXT;
  v_created            INTEGER := 0;
  -- slot re-verification
  v_slot_id            UUID;
  v_slot_status_rc     TEXT;
  v_slot_occupant_rc   UUID;
  v_occupant_label     TEXT;
  -- slot-derived metadata (not from user upload)
  v_slot_store_id_rc   UUID;
  v_slot_position_rc   TEXT;
  v_slot_store_name_rc TEXT;
  -- vacancy resolution (required for Stationary constraint)
  v_vacancy_id         UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can approve HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_batch
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;

  CASE v_batch.status
    WHEN 'approved'    THEN RAISE EXCEPTION 'This batch has already been approved' USING ERRCODE = 'P0001';
    WHEN 'rejected'    THEN RAISE EXCEPTION 'Rejected batches cannot be approved' USING ERRCODE = 'P0001';
    WHEN 'rolled_back' THEN RAISE EXCEPTION 'Rolled-back batches cannot be re-approved' USING ERRCODE = 'P0001';
    ELSE NULL;
  END CASE;

  IF v_batch.valid_rows = 0 THEN
    RAISE EXCEPTION 'No valid rows to import — all rows are blocked' USING ERRCODE = 'P0001';
  END IF;

  FOR v_row IN
    SELECT * FROM public.hr_emploc_import_rows
    WHERE batch_id = p_batch_id AND validation_status = 'valid'
    ORDER BY row_number
  LOOP
    -- Re-verify account
    SELECT a.id, a.account_name INTO v_account_id, v_account_name
    FROM public.accounts a
    WHERE a.group_id = v_batch.group_id
      AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_row.account_name))
    LIMIT 1;

    IF v_account_id IS NULL THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'ACCOUNT',
          'msg', format('Account "%s" not found at approval time.', v_row.account_name)
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- Re-verify Plantilla Slot
    v_slot_id            := NULL;
    v_slot_status_rc     := NULL;
    v_slot_occupant_rc   := NULL;
    v_occupant_label     := NULL;
    v_slot_store_id_rc   := NULL;
    v_slot_position_rc   := NULL;
    v_slot_store_name_rc := NULL;
    v_vacancy_id         := NULL;

    SELECT
      ps.id,
      ps.slot_status,
      ps.current_occupant_plantilla_id,
      ps.store_id,
      ps.position
    INTO
      v_slot_id,
      v_slot_status_rc,
      v_slot_occupant_rc,
      v_slot_store_id_rc,
      v_slot_position_rc
    FROM public.plantilla_slots ps
    WHERE ps.legacy_vcode = v_row.vcode
    LIMIT 1;

    IF NOT FOUND THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" no longer has a Plantilla slot at approval time.',
            v_row.vcode
          )
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    IF v_slot_status_rc NOT IN ('open', 'pipeline', 'hr_processing') THEN
      IF v_slot_status_rc = 'occupied' OR v_slot_occupant_rc IS NOT NULL THEN
        IF v_slot_occupant_rc IS NOT NULL THEN
          SELECT COALESCE(NULLIF(TRIM(p.employee_no), ''), NULLIF(TRIM(p.employee_name), ''), 'an active employee')
          INTO v_occupant_label
          FROM public.plantilla p
          WHERE p.id = v_slot_occupant_rc;
        END IF;
        UPDATE public.hr_emploc_import_rows SET
          validation_status = 'blocked',
          validation_errors = jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" was occupied between submit and approval by %s.',
              v_row.vcode,
              COALESCE(v_occupant_label, 'an active employee')
            )
          ))
        WHERE id = v_row.id;
      ELSE
        UPDATE public.hr_emploc_import_rows SET
          validation_status = 'blocked',
          validation_errors = jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" is no longer importable at approval time (current state: %s).',
              v_row.vcode,
              COALESCE(v_slot_status_rc, 'unknown')
            )
          ))
        WHERE id = v_row.id;
      END IF;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- Guard: prevent duplicate slot occupancy
    IF v_slot_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.hr_emploc
      WHERE slot_id = v_slot_id
        AND deleted_at IS NULL
    ) THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" slot already has an active HR Emploc record at approval time.',
            v_row.vcode
          )
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- Resolve store_name from slot
    SELECT s.store_name INTO v_slot_store_name_rc
    FROM public.stores s WHERE s.id = v_slot_store_id_rc;

    -- Resolve vacancy_id (required: Stationary constraint vacancy_id IS NOT NULL)
    SELECT id INTO v_vacancy_id
    FROM public.vacancies
    WHERE vcode      = v_row.vcode
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_vacancy_id IS NULL THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'Vacancy record not found for VCode "%s". '
            'A vacancy is required to create a Stationary HR Emploc record.',
            v_row.vcode
          )
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- All checks passed — create HR Emploc record
    v_full_name := TRIM(
      v_row.first_name || ' ' ||
      COALESCE(NULLIF(TRIM(v_row.middle_name), ''), '') || ' ' ||
      v_row.last_name
    );

    INSERT INTO public.hr_emploc (
      applicant_name,
      vcode,
      vacancy_code_snapshot,
      vacancy_id,
      account,
      account_id,
      store_id,
      position,
      store_name,
      status,
      hr_status,
      requirement_overall_status,
      assignment_type,
      covered_stores,
      hired_date,
      created_by,
      updated_by,
      import_batch_id,
      slot_id
    ) VALUES (
      v_full_name,
      v_row.vcode,
      v_row.vcode,
      v_vacancy_id,
      COALESCE(v_account_name, v_row.account_name),
      v_account_id,
      v_slot_store_id_rc,
      COALESCE(v_slot_position_rc, ''),
      v_slot_store_name_rc,
      'Pending Emploc',
      'Pending',
      'Incomplete',
      'Stationary'::public.hr_emploc_assignment_type,
      '[]'::jsonb,
      v_row.date_hired,
      v_profile_id,
      v_profile_id,
      p_batch_id,
      v_slot_id
    ) RETURNING id INTO v_hr_id;

    UPDATE public.hr_emploc_import_rows
    SET hr_emploc_id = v_hr_id
    WHERE id = v_row.id;

    -- Close vacancy (ADR-001 Rule 5)
    UPDATE public.vacancies
    SET
      status     = 'Filled',
      updated_at = now(),
      updated_by = v_profile_id
    WHERE vcode      = v_row.vcode
      AND deleted_at IS NULL
      AND (is_archived IS NULL OR is_archived = false)
      AND status NOT IN ('Filled', 'Closed', 'Cancelled', 'Archived');

    v_created := v_created + 1;
  END LOOP;

  UPDATE public.hr_emploc_import_batches SET
    status       = 'approved',
    approved_by  = v_profile_id,
    approved_at  = now(),
    created_rows = v_created
  WHERE id = p_batch_id;

  RETURN json_build_object('records_created', v_created);
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_new_store_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_reviewer_id     uuid;
  v_reviewer_name   text;
  v_reviewer_role   text;
  v_req             public.new_store_requests;
  v_new_store_id    uuid;
  v_requester_auth  uuid;
  v_requester_role  text;
BEGIN
  -- ── Auth guard ────────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Insufficient permissions — Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  v_reviewer_id := public.get_current_profile_id();
  IF v_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Resolve reviewer display name ─────────────────────────────
  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'admin')
  INTO v_reviewer_name, v_reviewer_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_reviewer_id;

  -- ── Lock and load request row ─────────────────────────────────
  SELECT * INTO v_req
  FROM public.new_store_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'New store request not found: %', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is not in pending status (current: %)', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Insert active store into registry ─────────────────────────
  INSERT INTO public.stores (
    account_id,
    group_id,
    store_name,
    area_city,
    province,
    is_active,
    status,
    created_by,
    approved_by,
    approved_at
  ) VALUES (
    v_req.account_id,
    v_req.group_id,
    v_req.store_name,
    v_req.city,
    v_req.province,
    true,
    'active',
    v_reviewer_id,
    v_reviewer_id,
    now()
  )
  RETURNING id INTO v_new_store_id;

  -- ── Mark request approved ─────────────────────────────────────
  UPDATE public.new_store_requests SET
    status           = 'approved',
    reviewed_by      = v_reviewer_id,
    reviewed_by_name = v_reviewer_name,
    reviewed_at      = now(),
    created_store_id = v_new_store_id,
    updated_at       = now()
  WHERE id = p_request_id;

  -- ── Notify requester ──────────────────────────────────────────
  SELECT up.auth_user_id, COALESCE(ro.role_name, 'ops')
  INTO v_requester_auth, v_requester_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_req.requested_by;

  IF v_requester_auth IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users WHERE id = v_requester_auth) THEN
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_requester_role,
        v_requester_auth,
        'new_store_request',
        'NEW_STORE_REQUEST_APPROVED',
        'Store Request Approved',
        'Your request for ' || v_req.store_name ||
          ' has been approved and added to the store registry.',
        '/new_store_request/' || p_request_id::text,
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'approve_new_store_request: skipped requester %, role %, request_id %, error: %',
        v_requester_auth, v_requester_role, p_request_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'request_id',    p_request_id,
    'store_id',      v_new_store_id,
    'status',        'approved'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300000'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_batch      public.plantilla_import_batches%ROWTYPE;
  v_acct_name  text;

  -- Phase A locals
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_emp_type_norm      text;
  v_stores_done        int := 0;

  -- Phase B locals
  v_emp_rec        record;
  v_store_rec      record;
  v_plantilla_id   uuid;
  v_roving_id      uuid;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;

  -- Optional enrichment parsing
  v_daily_rate_parsed  numeric;
  v_birthdate_parsed   date;
  v_deployment_type    text;
  v_area_val           text;
  v_has_penalty        boolean;

  -- Commit counts
  v_committable int;

  -- VCODE resolution guard
  v_unresolved_vcode text;

  -- Humanised error
  v_err_state text;
  v_err_msg   text;
  v_err_out   text;

  -- OHM2026_0071: Inactive reconcile path (preserved; unreachable for new batches after OHM2026_0083)
  v_inactive_id      uuid;
  v_deactivated_id   uuid;

  -- OHM2026_0071: Slot occupancy wire
  v_slot_id          uuid;
  v_slot_vcode       text;
  v_slot_result      jsonb;
  v_slot_ordinal     int;
  v_slot_store_id    uuid;

  -- OHM2026_0079: Defensive revalidation
  v_reval_emp    text;
  v_reval_vcode  text;

BEGIN
  -- â”€â”€ Auth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- â”€â”€ Lock + state check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  -- â”€â”€ Pre-commit guard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid','flagged')
     AND employee_no IS NOT NULL
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch (valid+flagged with employee_no and vcode)'
      USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- â”€â”€ Temp store commit map â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  DROP TABLE IF EXISTS _pib_store_map;
  CREATE TEMP TABLE _pib_store_map (
    vcode    text,
    store_id uuid,
    is_new   boolean
  ) ON COMMIT DROP;

  -- â”€â”€ Inner exception block â€” all commit DML is atomic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  BEGIN

    -- â”€â”€ OHM2026_0079 + OHM2026_0083: Defensive revalidation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- Re-run the same conflict classification as submit_plantilla_baseline_import.
    -- Catches state changes that occurred between Review Import and Approve.

    -- Check 1 (OHM2026_0079): Active non-rollback-safe plantilla employee
    SELECT pir.employee_no INTO v_reval_emp
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.employee_no IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = pir.employee_no
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
            AND NOT EXISTS (
              SELECT 1 FROM public.plantilla_import_batches pib2
               WHERE pib2.id = p.source_baseline_import_batch_id
                 AND pib2.status = 'rolled_back'
                 AND pib2.rolled_back_at IS NOT NULL
            )
       )
     LIMIT 1;

    IF v_reval_emp IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: employee_no % is now active in plantilla. '
        'Re-submit this batch so Review Import can reclassify the conflict.',
        v_reval_emp
        USING ERRCODE = '55000';
    END IF;

    -- Check 2 (OHM2026_0079): Archived non-rollback-safe VCode
    SELECT pir.vcode INTO v_reval_vcode
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.vcode IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.vacancies vv
          WHERE upper(trim(vv.vcode)) = pir.vcode
            AND (
              COALESCE(vv.is_archived, false) = true
              OR vv.status = 'Archived'
              OR (
                vv.deleted_at IS NOT NULL
                AND NOT (
                  vv.source_vacancy_import_batch_id IS NOT NULL
                  AND EXISTS (
                    SELECT 1 FROM public.vacancy_import_batches vib2
                     WHERE vib2.id = vv.source_vacancy_import_batch_id
                       AND vib2.rollback_status = 'completed'
                  )
                )
              )
            )
       )
     LIMIT 1;

    IF v_reval_vcode IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: VCode % is now archived or non-reusable. '
        'Re-submit this batch so Review Import can reclassify the conflict.',
        v_reval_vcode
        USING ERRCODE = '55000';
    END IF;

    -- Check 3 (OHM2026_0083): Inactive/Rejected-Deactivation plantilla employee
    -- in valid/flagged rows. Catches in-flight batches submitted before this
    -- migration where such rows were flagged (reconcile path) rather than blocked.
    v_reval_emp := NULL;
    SELECT pir.employee_no INTO v_reval_emp
      FROM public.plantilla_import_rows pir
     WHERE pir.batch_id = p_batch_id
       AND pir.validation_status IN ('valid','flagged')
       AND pir.employee_no IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = pir.employee_no
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Inactive', 'Rejected Deactivation')
       )
     LIMIT 1;

    IF v_reval_emp IS NOT NULL THEN
      RAISE EXCEPTION
        'REVALIDATION_FAILED: employee_no % has an inactive plantilla record. '
        'Cannot import because matching employee is inactive/archived. '
        'Restore/reactivate first or use a valid active record.',
        v_reval_emp
        USING ERRCODE = '55000';
    END IF;
    -- â”€â”€ End defensive revalidation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    -- â”€â”€ Phase A: Store upsert â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, area_province, area_city,
             employment_type, with_penalty_raw, row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_emp_type_norm := CASE
        WHEN lower(COALESCE(v_srow.employment_type,'')) IN ('stationary','roving')
          THEN lower(v_srow.employment_type)
        ELSE NULL
      END;

      v_pen_bool := CASE
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      SELECT to_jsonb(s.*) INTO v_old_store_snap
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_srow.vcode) AND s.status = 'active'
       ORDER BY s.created_at LIMIT 1;

      IF v_old_store_snap IS NULL THEN
        INSERT INTO public.stores (
          vcode, store_name, area_province, area_city,
          employment_type, with_penalty,
          group_id, account_id, status,
          created_by, updated_by, approved_by, approved_at, source_import_id
        ) VALUES (
          v_srow.vcode, v_srow.store_name, v_srow.area_province, v_srow.area_city,
          v_emp_type_norm, v_pen_bool,
          v_batch.selected_group_id, v_batch.selected_account_id, 'active',
          v_uid, v_uid, v_uid, now(), p_batch_id
        ) RETURNING id INTO v_new_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_new_store_id, true);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_new_store_id, 'insert', NULL, v_uid);

      ELSE
        v_existing_store_id := (v_old_store_snap->>'id')::uuid;

        UPDATE public.stores
           SET store_name      = v_srow.store_name,
               area_province   = v_srow.area_province,
               area_city       = v_srow.area_city,
               employment_type = COALESCE(v_emp_type_norm, employment_type),
               with_penalty    = COALESCE(v_pen_bool, with_penalty),
               updated_by      = v_uid,
               approved_by     = v_uid,
               approved_at     = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_existing_store_id, false);

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      UPDATE public.plantilla_import_rows
         SET previous_store_snapshot = v_old_store_snap
       WHERE batch_id = p_batch_id
         AND upper(vcode) = upper(v_srow.vcode)
         AND validation_status IN ('valid','flagged');

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- â”€â”€ Post-Phase-A: VCODE resolution guard (OHM2026_1144) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    SELECT r.vcode INTO v_unresolved_vcode
      FROM public.plantilla_import_rows r
     WHERE r.batch_id = p_batch_id
       AND r.validation_status IN ('valid','flagged')
       AND r.vcode IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM _pib_store_map sm WHERE sm.vcode = upper(r.vcode)
       )
     LIMIT 1;

    IF v_unresolved_vcode IS NOT NULL THEN
      RAISE EXCEPTION 'STORE_RESOLUTION_FAILED: VCODE % not resolved after store upsert â€” cannot commit plantilla rows',
        v_unresolved_vcode
        USING ERRCODE = '23503';
    END IF;

    -- â”€â”€ Phase B: Employee / plantilla upsert â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    FOR v_emp_rec IN
      SELECT
        employee_no,
        count(DISTINCT vcode)                                                       AS store_count,
        (array_agg(last_name   ORDER BY row_number))[1]                            AS last_name,
        (array_agg(first_name  ORDER BY row_number))[1]                            AS first_name,
        (array_agg(middle_name ORDER BY row_number))[1]                            AS middle_name,
        (array_agg(position          ORDER BY row_number)
           FILTER (WHERE position IS NOT NULL))[1]                                 AS position,
        (array_agg(employment_type   ORDER BY row_number)
           FILTER (WHERE employment_type IS NOT NULL))[1]                          AS employment_type_raw,
        (array_agg(with_penalty_raw  ORDER BY row_number)
           FILTER (WHERE with_penalty_raw IS NOT NULL))[1]                         AS with_penalty_raw_agg,
        (array_agg(area_province     ORDER BY row_number)
           FILTER (WHERE area_province IS NOT NULL))[1]                            AS area_province,
        (array_agg(area_city         ORDER BY row_number)
           FILTER (WHERE area_city IS NOT NULL))[1]                                AS area_city,
        (array_agg(civil_status      ORDER BY row_number)
           FILTER (WHERE civil_status    IS NOT NULL))[1]                          AS civil_status,
        (array_agg(rate_raw          ORDER BY row_number)
           FILTER (WHERE rate_raw        IS NOT NULL))[1]                          AS rate_raw,
        (array_agg(birthdate_raw     ORDER BY row_number)
           FILTER (WHERE birthdate_raw   IS NOT NULL))[1]                          AS birthdate_raw,
        (array_agg(contact_raw       ORDER BY row_number)
           FILTER (WHERE contact_raw     IS NOT NULL))[1]                          AS contact_raw,
        (array_agg(address_raw       ORDER BY row_number)
           FILTER (WHERE address_raw     IS NOT NULL))[1]                          AS address_raw,
        (array_agg(schedule_raw      ORDER BY row_number)
           FILTER (WHERE schedule_raw    IS NOT NULL))[1]                          AS schedule_raw,
        (array_agg(dayoff_raw        ORDER BY row_number)
           FILTER (WHERE dayoff_raw      IS NOT NULL))[1]                          AS dayoff_raw,
        (array_agg(coordinator_raw   ORDER BY row_number)
           FILTER (WHERE coordinator_raw IS NOT NULL))[1]                          AS coordinator_raw
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND employee_no IS NOT NULL
       GROUP BY employee_no
    LOOP
      v_employees_done := v_employees_done + 1;
      v_store_cnt := v_emp_rec.store_count;
      v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
      v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                     || COALESCE(' ' || v_emp_rec.middle_name, '');

      v_deployment_type := CASE
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'stationary' THEN 'Stationary'
        WHEN lower(COALESCE(v_emp_rec.employment_type_raw,'')) = 'roving'     THEN 'Roving'
        ELSE NULLIF(trim(COALESCE(v_emp_rec.employment_type_raw,'')), '')
      END;

      v_area_val := NULLIF(trim(COALESCE(
        v_emp_rec.area_city,
        v_emp_rec.area_province,
        ''
      )), '');

      v_has_penalty := CASE
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_emp_rec.with_penalty_raw_agg,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      v_daily_rate_parsed := NULL;
      BEGIN
        v_daily_rate_parsed := nullif(trim(coalesce(v_emp_rec.rate_raw, '')), '')::numeric;
      EXCEPTION WHEN OTHERS THEN
        v_daily_rate_parsed := NULL;
      END;

      v_birthdate_parsed := NULL;
      BEGIN
        v_birthdate_parsed := nullif(trim(coalesce(v_emp_rec.birthdate_raw, '')), '')::date;
      EXCEPTION WHEN OTHERS THEN
        v_birthdate_parsed := NULL;
      END;

      -- â”€â”€ OHM2026_0071: Multi-step plantilla lookup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      -- Step 1: Active / On Leave / Pending Deactivation  (existing path)
      v_plantilla_id := NULL;
      SELECT id INTO v_plantilla_id
        FROM public.plantilla
       WHERE employee_no = v_emp_rec.employee_no
         AND is_deleted = false
         AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       LIMIT 1;

      -- Step 2 (OHM2026_0071): Inactive / Rejected Deactivation  â€” reconcile path
      -- NOTE (OHM2026_0083): New batches will never reach this path because
      -- inactive employees are now BLOCKED at review time. This branch is
      -- preserved for data-integrity safety only. Defensive revalidation
      -- (Check 3 above) will have already raised REVALIDATION_FAILED for any
      -- in-flight batch that has an inactive employee in valid/flagged rows.
      v_inactive_id := NULL;
      IF v_plantilla_id IS NULL THEN
        SELECT p_inactive.id INTO v_inactive_id
          FROM public.plantilla p_inactive
         WHERE p_inactive.employee_no = v_emp_rec.employee_no
           AND p_inactive.is_deleted = false
           AND p_inactive.status IN ('Inactive', 'Rejected Deactivation')
           AND NOT EXISTS (
             SELECT 1 FROM public.plantilla_import_batches pib2
              WHERE pib2.id = p_inactive.source_baseline_import_batch_id
                AND pib2.status = 'rolled_back'
                AND pib2.rolled_back_at IS NOT NULL
           )
         LIMIT 1;

        IF v_inactive_id IS NOT NULL THEN
          v_plantilla_id := v_inactive_id;
        END IF;
      END IF;

      -- Step 3 (OHM2026_0071): Deactivated guard â€” skip with NOTICE, do not reactivate
      v_deactivated_id := NULL;
      IF v_plantilla_id IS NULL THEN
        SELECT id INTO v_deactivated_id
          FROM public.plantilla
         WHERE employee_no = v_emp_rec.employee_no
           AND is_deleted = false
           AND status = 'Deactivated'
         LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
          RAISE NOTICE
            'OHM2026_0071: Skipping employee_no=% â€” existing row is Deactivated (id=%). '
            'Deactivated employees cannot be reactivated via import; manual review required.',
            v_emp_rec.employee_no, v_deactivated_id;
          v_employees_done := v_employees_done - 1;
          CONTINUE;
        END IF;
      END IF;

      SELECT to_jsonb(p.*) INTO v_old_plant_snap
        FROM public.plantilla p WHERE id = v_plantilla_id;

      v_roving_id := NULL;
      IF v_store_cnt > 1 THEN
        INSERT INTO public.import_roving_groups (
          employee_no, account_id, group_id, account_name, label,
          active_store_count, filled_hc_per_store, source_import_batch_id, created_by
        ) VALUES (
          v_emp_rec.employee_no,
          v_batch.selected_account_id, v_batch.selected_group_id,
          v_acct_name, v_emp_name || ' â€” Roving',
          v_store_cnt, v_filled, p_batch_id, v_actor
        ) RETURNING id INTO v_roving_id;
      END IF;

      -- OHM2026_0065B: Roving override â€” if store_count > 1, deployment_type = 'Roving'
      IF v_store_cnt > 1 THEN
        v_deployment_type := 'Roving';
      END IF;

      IF v_plantilla_id IS NULL THEN
        -- â”€â”€ New employee: INSERT plantilla master â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        INSERT INTO public.plantilla (
          employee_name, employee_no, emploc_no, account, status,
          account_id, last_name, first_name, middle_name,
          roving_assignment_id, is_pool_employee,
          position, deployment_type, has_penalty, area, area_name_snapshot,
          vcode, store_id, store_name,
          civil_status, daily_rate, birthdate,
          contact_no, address, schedule, dayoff, coordinator,
          source_baseline_import_batch_id, created_by, moved_by_user_id
        )
        SELECT
          v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no,
          v_acct_name, 'Active',
          v_batch.selected_account_id,
          v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
          NULL, false,
          nullif(trim(coalesce(v_emp_rec.position, '')), ''),
          v_deployment_type,
          v_has_penalty,
          v_area_val,
          v_area_val,
          CASE WHEN v_store_cnt = 1 THEN r.vcode     ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
          CASE WHEN v_store_cnt = 1 THEN r.store_name ELSE NULL END,
          nullif(trim(coalesce(v_emp_rec.civil_status, '')),    ''),
          v_daily_rate_parsed,
          v_birthdate_parsed,
          nullif(trim(coalesce(v_emp_rec.contact_raw, '')),     ''),
          nullif(trim(coalesce(v_emp_rec.address_raw, '')),     ''),
          nullif(trim(coalesce(v_emp_rec.schedule_raw, '')),    ''),
          nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')),      ''),
          nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), ''),
          p_batch_id, v_actor, v_actor
        FROM (
          SELECT vcode, store_name
            FROM public.plantilla_import_rows
           WHERE batch_id = p_batch_id AND employee_no = v_emp_rec.employee_no
             AND validation_status IN ('valid','flagged')
           ORDER BY row_number LIMIT 1
        ) r
        LEFT JOIN _pib_store_map sm ON sm.vcode = upper(r.vcode)
        RETURNING id INTO v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);

      ELSIF v_inactive_id IS NOT NULL THEN
        -- â”€â”€ OHM2026_0071: Inactive/Rejected Deactivation reconcile path â”€â”€â”€â”€â”€
        -- NOTE (OHM2026_0083): Defensive Check 3 above prevents reaching this
        -- path for new batches. This branch remains for historical data-integrity
        -- completeness only.
        UPDATE public.plantilla
           SET status                    = 'Active',
               inactive_at              = NULL,
               inactive_by              = NULL,
               separation_status        = NULL,
               date_of_separation       = NULL,
               resignation_date         = NULL,
               inactive_visible_until   = NULL,
               employee_name            = v_emp_name,
               last_name                = v_emp_rec.last_name,
               first_name               = v_emp_rec.first_name,
               middle_name              = v_emp_rec.middle_name,
               position                 = COALESCE(
                                            NULLIF(trim(COALESCE(position, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                          ),
               deployment_type          = COALESCE(
                                            NULLIF(trim(COALESCE(deployment_type, '')), ''),
                                            v_deployment_type
                                          ),
               has_penalty              = COALESCE(has_penalty, v_has_penalty),
               area                     = COALESCE(
                                            NULLIF(trim(COALESCE(area, '')), ''),
                                            v_area_val
                                          ),
               area_name_snapshot       = COALESCE(
                                            NULLIF(trim(COALESCE(area_name_snapshot, '')), ''),
                                            v_area_val
                                          ),
               civil_status             = COALESCE(
                                            NULLIF(trim(COALESCE(civil_status, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                          ),
               daily_rate               = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate                = COALESCE(birthdate,  v_birthdate_parsed),
               contact_no               = CASE
                                            WHEN contact_no IS NOT NULL AND contact_no <> ''
                                            THEN contact_no
                                            ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                          END,
               address                  = CASE
                                            WHEN address IS NOT NULL AND address <> ''
                                            THEN address
                                            ELSE nullif(trim(coalesce(v_emp_rec.address_raw, '')), '')
                                          END,
               schedule                 = COALESCE(
                                            NULLIF(trim(COALESCE(schedule, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.schedule_raw, '')), '')
                                          ),
               dayoff                   = COALESCE(
                                            NULLIF(trim(COALESCE(dayoff, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')), '')
                                          ),
               coordinator              = COALESCE(
                                            NULLIF(trim(COALESCE(coordinator, '')), ''),
                                            nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), '')
                                          ),
               updated_at               = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_inactive_id;

        UPDATE public.employee_deactivation_requests
           SET status     = 'Cancelled',
               updated_at = now()
         WHERE plantilla_id = v_inactive_id
           AND status IN ('Pending')
           AND is_archived = false;

        INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
        VALUES (v_uid, 'plantilla_import', 'IMPORT_REACTIVATION', v_inactive_id,
          jsonb_build_object(
            'employee_no',  v_emp_rec.employee_no,
            'previous_status', v_old_plant_snap->>'status',
            'batch_id',     p_batch_id,
            'note',         'Employee re-imported as Active; was Inactive/Rejected Deactivation'
          ));

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_inactive_id, 'reactivate', v_old_plant_snap, v_uid);

      ELSE
        -- â”€â”€ Normal existing employee UPDATE path â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        UPDATE public.plantilla
           SET employee_name    = v_emp_name,
               last_name        = v_emp_rec.last_name,
               first_name       = v_emp_rec.first_name,
               middle_name      = v_emp_rec.middle_name,
               position         = COALESCE(
                                     NULLIF(trim(COALESCE(position, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.position, '')), '')
                                   ),
               deployment_type  = COALESCE(
                                     NULLIF(trim(COALESCE(deployment_type, '')), ''),
                                     v_deployment_type
                                   ),
               has_penalty      = COALESCE(has_penalty, v_has_penalty),
               area             = COALESCE(
                                     NULLIF(trim(COALESCE(area, '')), ''),
                                     v_area_val
                                   ),
               area_name_snapshot = COALESCE(
                                      NULLIF(trim(COALESCE(area_name_snapshot, '')), ''),
                                      v_area_val
                                    ),
               civil_status     = COALESCE(
                                     NULLIF(trim(COALESCE(civil_status, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.civil_status, '')), '')
                                   ),
               daily_rate       = COALESCE(daily_rate, v_daily_rate_parsed),
               birthdate        = COALESCE(birthdate,  v_birthdate_parsed),
               contact_no       = CASE
                                    WHEN contact_no IS NOT NULL AND contact_no <> ''
                                    THEN contact_no
                                    ELSE nullif(trim(coalesce(v_emp_rec.contact_raw, '')), '')
                                  END,
               address          = CASE
                                    WHEN address IS NOT NULL AND address <> ''
                                    THEN address
                                    ELSE nullif(trim(coalesce(v_emp_rec.address_raw, '')), '')
                                  END,
               schedule         = COALESCE(
                                     NULLIF(trim(COALESCE(schedule, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.schedule_raw, '')), '')
                                   ),
               dayoff           = COALESCE(
                                     NULLIF(trim(COALESCE(dayoff, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.dayoff_raw, '')), '')
                                   ),
               coordinator      = COALESCE(
                                     NULLIF(trim(COALESCE(coordinator, '')), ''),
                                     nullif(trim(coalesce(v_emp_rec.coordinator_raw, '')), '')
                                   ),
               updated_at       = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_plantilla_id;

        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      IF v_roving_id IS NOT NULL THEN
        UPDATE public.import_roving_groups SET plantilla_id = v_plantilla_id
         WHERE id = v_roving_id;
      END IF;

      UPDATE public.plantilla_import_rows
         SET previous_plantilla_snapshot = v_old_plant_snap
       WHERE batch_id = p_batch_id
         AND employee_no = v_emp_rec.employee_no
         AND validation_status IN ('valid','flagged');

      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      SELECT
        p_batch_id, 'allocation', a.id, 'update', to_jsonb(a.*), v_uid
        FROM public.employee_store_allocations a
       WHERE a.employee_no = v_emp_rec.employee_no
         AND a.is_active
         AND a.account_id = v_batch.selected_account_id;

      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
       WHERE employee_no = v_emp_rec.employee_no
         AND is_active
         AND account_id = v_batch.selected_account_id;

      FOR v_store_rec IN
        SELECT DISTINCT ON (pir.vcode)
               pir.vcode, sm.store_id,
               pir.store_name, pir.resolved_account_id, pir.resolved_group_id
          FROM public.plantilla_import_rows pir
          LEFT JOIN _pib_store_map sm ON sm.vcode = upper(pir.vcode)
         WHERE pir.batch_id = p_batch_id
           AND pir.employee_no = v_emp_rec.employee_no
           AND pir.validation_status IN ('valid','flagged')
         ORDER BY pir.vcode, pir.row_number
      LOOP
        INSERT INTO public.employee_store_allocations (
          plantilla_id, employee_no, roving_group_id,
          store_id, vcode, store_name,
          account_id, group_id,
          filled_hc, active_store_count,
          effective_start, is_active,
          source_import_batch_id, created_by
        ) VALUES (
          v_plantilla_id, v_emp_rec.employee_no, v_roving_id,
          v_store_rec.store_id, v_store_rec.vcode, v_store_rec.store_name,
          COALESCE(v_store_rec.resolved_account_id, v_batch.selected_account_id),
          COALESCE(v_store_rec.resolved_group_id,   v_batch.selected_group_id),
          v_filled, v_store_cnt,
          CURRENT_DATE, true,
          p_batch_id, v_actor
        );
        v_alloc_done := v_alloc_done + 1;
      END LOOP;

      -- â”€â”€ OHM2026_0071: Â§2 Slot occupancy wire â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      IF v_store_cnt = 1 AND v_plantilla_id IS NOT NULL THEN
        BEGIN
          SELECT pir.vcode INTO v_slot_vcode
            FROM public.plantilla_import_rows pir
           WHERE pir.batch_id = p_batch_id
             AND pir.employee_no = v_emp_rec.employee_no
             AND pir.validation_status IN ('valid','flagged')
           ORDER BY pir.row_number
           LIMIT 1;

          IF v_slot_vcode IS NOT NULL THEN
            v_slot_id := NULL;

            SELECT id INTO v_slot_id
              FROM public.plantilla_slots
             WHERE current_occupant_plantilla_id = v_plantilla_id
               AND is_roving = false
             LIMIT 1;

            IF v_slot_id IS NULL THEN
              SELECT id INTO v_slot_id
                FROM public.plantilla_slots
               WHERE legacy_vcode = v_slot_vcode
                 AND is_roving    = false
               LIMIT 1;
            END IF;

            IF v_slot_id IS NOT NULL THEN
              DECLARE
                v_slot_current_status text;
              BEGIN
                SELECT slot_status INTO v_slot_current_status
                  FROM public.plantilla_slots
                 WHERE id = v_slot_id;

                IF v_slot_current_status = 'occupied'
                   AND (SELECT current_occupant_plantilla_id FROM public.plantilla_slots WHERE id = v_slot_id) = v_plantilla_id THEN
                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% already occupied by plantilla_id=% (vcode=%)',
                    v_slot_id, v_plantilla_id, v_slot_vcode;

                ELSIF v_slot_current_status = 'closed' THEN
                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% is closed, skipping occupancy wire for plantilla_id=% (vcode=%)',
                    v_slot_id, v_plantilla_id, v_slot_vcode;

                ELSE
                  UPDATE public.plantilla_slots
                     SET slot_status                   = 'occupied',
                         current_occupant_plantilla_id = v_plantilla_id,
                         updated_at                    = now(),
                         updated_by                    = v_actor
                   WHERE id = v_slot_id;

                  INSERT INTO public.slot_history (
                    slot_id, account_id, action_type, old_value, new_value,
                    reason_code, performed_by, remarks, created_at
                  ) VALUES (
                    v_slot_id,
                    v_batch.selected_account_id,
                    'occupied',
                    v_slot_current_status,
                    'occupied',
                    'IMPORT_OCCUPIED',
                    v_actor,
                    format(
                      'OHM2026_0071 import slot wire: batch_id=%s employee_no=%s plantilla_id=%s',
                      p_batch_id::text, v_emp_rec.employee_no, v_plantilla_id::text
                    ),
                    now()
                  );

                  RAISE NOTICE
                    'OHM2026_0071 slot wire: slot_id=% transitioned %â†’occupied for plantilla_id=% (vcode=%)',
                    v_slot_id, v_slot_current_status, v_plantilla_id, v_slot_vcode;
                END IF;
              END;

            ELSE
              SELECT sm.store_id INTO v_slot_store_id
                FROM _pib_store_map sm
               WHERE sm.vcode = upper(v_slot_vcode)
               LIMIT 1;

              SELECT COALESCE(MAX(ps.slot_ordinal), 0) + 1 INTO v_slot_ordinal
                FROM public.plantilla_slots ps
               WHERE ps.legacy_vcode = v_slot_vcode;

              INSERT INTO public.plantilla_slots (
                store_id, account_id, group_id,
                position, employment_type, is_roving,
                slot_status, slot_ordinal, legacy_vcode,
                current_occupant_plantilla_id,
                created_at, updated_at, created_by, updated_by
              ) VALUES (
                v_slot_store_id,
                v_batch.selected_account_id,
                v_batch.selected_group_id,
                COALESCE(nullif(trim(coalesce(v_emp_rec.position, '')), ''), 'Unknown'),
                COALESCE(lower(nullif(trim(coalesce(v_emp_rec.employment_type_raw, '')), '')), 'stationary'),
                false,
                'occupied',
                v_slot_ordinal::smallint,
                v_slot_vcode,
                v_plantilla_id,
                now(), now(),
                v_actor, v_actor
              )
              RETURNING id INTO v_slot_id;

              INSERT INTO public.slot_history (
                slot_id, account_id, action_type, old_value, new_value,
                reason_code, performed_by, remarks, created_at
              ) VALUES (
                v_slot_id,
                v_batch.selected_account_id,
                'occupied',
                NULL,
                'occupied',
                'IMPORT_OCCUPIED',
                v_actor,
                format(
                  'OHM2026_0071 new slot created by import: batch_id=%s employee_no=%s plantilla_id=%s',
                  p_batch_id::text, v_emp_rec.employee_no, v_plantilla_id::text
                ),
                now()
              );

              RAISE NOTICE
                'OHM2026_0071 slot wire: created new slot_id=% (occupied) for plantilla_id=% (vcode=%)',
                v_slot_id, v_plantilla_id, v_slot_vcode;
            END IF;
          END IF;

        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE
            'OHM2026_0071 slot wire: non-fatal error for employee_no=% plantilla_id=% â€” % (sqlstate=%)',
            v_emp_rec.employee_no, v_plantilla_id, SQLERRM, SQLSTATE;
        END;
      END IF;
      -- â”€â”€ End OHM2026_0071 slot wire â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'plantilla_import', 'APPROVAL', v_plantilla_id,
        jsonb_build_object(
          'employee_no',         v_emp_rec.employee_no,
          'store_count',         v_store_cnt,
          'filled_hc_per_store', v_filled,
          'roving',              (v_roving_id IS NOT NULL),
          'batch_id',            p_batch_id,
          'reconciled',          (v_inactive_id IS NOT NULL)
        ));
    END LOOP;

    UPDATE public.plantilla_import_batches
       SET status             = 'approved',
           approved_by        = v_uid,
           approved_at        = now(),
           committed_stores   = v_stores_done,
           committed_employees= v_employees_done,
           rollback_ready     = true,
           updated_at         = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'plantilla_import_batches', 'APPROVAL', p_batch_id,
      jsonb_build_object(
        'stores',      v_stores_done,
        'employees',   v_employees_done,
        'allocations', v_alloc_done
      ));

    RETURN jsonb_build_object(
      'batch_id',            p_batch_id,
      'status',              'approved',
      'stores_committed',    v_stores_done,
      'employees_committed', v_employees_done,
      'allocations_created', v_alloc_done
    );

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_state = RETURNED_SQLSTATE,
      v_err_msg   = MESSAGE_TEXT;

    -- REVALIDATION_FAILED is already human-readable; return verbatim.
    IF v_err_state = '55000'
       AND position('REVALIDATION_FAILED' IN COALESCE(v_err_msg,'')) > 0
    THEN
      v_err_out := v_err_msg;
    ELSIF v_err_state = '23505'
       AND position('uq_plantilla_vcode_active_occupied' IN COALESCE(v_err_msg,'')) > 0
    THEN
      v_err_out := 'VCODE_ALREADY_OCCUPIED: a VCODE in this batch is already held '
                || 'by another active employee in plantilla â€” only one active '
                || 'occupancy per VCODE is allowed';
    ELSE
      v_err_out := format('[%s] %s', v_err_state, v_err_msg);
    END IF;

    UPDATE public.plantilla_import_batches
       SET status              = 'commit_failed',
           commit_error_detail = v_err_out,
           updated_at          = now()
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id', p_batch_id,
      'status',   'commit_failed',
      'error',    v_err_out
    );
  END;

END$function$;

CREATE OR REPLACE FUNCTION public.approve_vacancy_request(p_vacancy_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := get_my_profile_id();
  v_role       text := get_my_role();
  v            public.vacancies;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Only Super Admin or Head Admin can approve vacancies' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;

  -- Head Admin scope-check (if user_scopes entries exist for this HA)
  IF v_role = 'Head Admin'
     AND EXISTS (SELECT 1 FROM public.user_scopes WHERE user_id = v_profile_id)
     AND NOT public.i_have_account_scope(v.account_id) THEN
    RAISE EXCEPTION 'Vacancy % is outside your assigned scope', p_vacancy_id USING ERRCODE='42501';
  END IF;

  IF v.status <> 'Pending Approval' THEN
    RAISE EXCEPTION 'Only Pending Approval vacancies can be approved (current: %)', v.status
      USING ERRCODE='check_violation';
  END IF;

  UPDATE public.vacancies
     SET status = 'Open', updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','APPROVAL', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Open','semantic_action','APPROVE_VACANCY','actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status', 'Open');
END;
$function$;

CREATE OR REPLACE FUNCTION public.assert_vacancy_edit_allowed()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.fn_assert_vacancy_edit_allowed_op('UPDATE');
END;
$function$;

CREATE OR REPLACE FUNCTION public.assign_applicant_to_vacancy(p_vacancy_id uuid, p_applicant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := get_my_profile_id();
  v_role       text := get_my_role();
  v_role_lvl   int  := get_my_role_level();
  v            public.vacancies;
  v_app        public.applicants;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;

  -- Recruitment / Encoder / HRCO / OM / SA / HA may assign
  IF v_role_lvl < 20 OR v_role = 'Viewer' OR v_role = 'Back Office' THEN
    RAISE EXCEPTION 'Role % cannot assign applicants', v_role USING ERRCODE='42501';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;
  IF v.status <> 'Open' THEN
    RAISE EXCEPTION 'Can only assign applicants to Open vacancies (current: %)', v.status
      USING ERRCODE='check_violation';
  END IF;
  IF NOT (public.i_have_full_access() OR public.i_have_account_scope(v.account_id)) THEN
    RAISE EXCEPTION 'Vacancy outside your scope' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Applicant not found: %', p_applicant_id; END IF;

  UPDATE public.applicants
     SET vacancy_vcode = v.vcode,
         updated_by    = v_profile_id,
         updated_at    = now()
   WHERE id = p_applicant_id;

  PERFORM public.log_audit_event(
    'applicants','UPDATE', p_applicant_id,
    to_jsonb(v_app),
    jsonb_build_object('vacancy_vcode', v.vcode, 'vacancy_id', v.id,
                       'semantic_action','ASSIGN_APPLICANT_TO_VACANCY', 'actor_role', v_role)
  );
  RETURN jsonb_build_object('vacancy_id', v.id, 'applicant_id', p_applicant_id, 'vacancy_vcode', v.vcode);
END;
$function$;

CREATE OR REPLACE FUNCTION public.assign_hr_emploc_number(p_id uuid, p_employee_no text)
 RETURNS hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old   public.hr_emploc;
  v_new   public.hr_emploc;
  v_clean text := nullif(btrim(p_employee_no),'');
BEGIN
  IF NOT (i_am_hr_dept() OR is_super_admin()) THEN
    RAISE EXCEPTION 'forbidden: HR Dept role required' USING ERRCODE = '42501';
  END IF;

  IF v_clean IS NULL THEN
    RAISE EXCEPTION 'employee_no is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;

  -- PENDING DELETION LOCK
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM hr_emploc
    WHERE employee_no = v_clean AND id <> p_id
      AND deleted_at IS NULL
      AND status NOT IN ('Backout','Moved to Plantilla')
  ) THEN
    RAISE EXCEPTION 'employee_no % already in use on active hr_emploc', v_clean USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1 FROM plantilla
    WHERE employee_no = v_clean
      AND is_deleted = false
      AND status IN ('Active','For Deactivation','On Leave')
  ) THEN
    RAISE EXCEPTION 'employee_no % already exists in active plantilla', v_clean USING ERRCODE = '23505';
  END IF;

  UPDATE hr_emploc
  SET employee_no            = v_clean,
      emploc_no              = v_clean,
      hr_status              = 'Complete',
      status                 = 'Ready for Plantilla',
      hr_reviewed_at         = now(),
      hr_reviewed_by         = get_my_full_name(),
      hr_reviewed_by_user_id = get_my_profile_id(),
      updated_at             = now(),
      updated_by             = get_my_profile_id()
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM log_audit_event('hr_emploc','UPDATE', p_id, to_jsonb(v_old), to_jsonb(v_new));
  RETURN v_new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_closure_request_sla()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r          RECORD;
  u          RECORD;
  lvl        SMALLINT;
  v_req_auth uuid;
  v_link     text;
BEGIN
  FOR r IN
    SELECT cr.*, v.id AS vacancy_id,
           COALESCE(a.account_name, v.account, 'Account') AS account_name
    FROM public.vacancy_closure_requests cr
    LEFT JOIN public.vacancies v ON v.vcode    = cr.vacancy_vcode
    LEFT JOIN public.accounts  a ON a.id       = v.account_id
    WHERE cr.status    = 'Pending'
      AND cr.created_at < NOW() - INTERVAL '3 days'
  LOOP
    lvl    := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    v_link := FORMAT('/vacancies/%s/closure-request/%s',
                     COALESCE(r.vacancy_id::TEXT, r.vacancy_vcode), r.id);

    IF NOT public.notification_sla_exists('vacancy_closure', r.id::TEXT, lvl) THEN
      IF lvl = 2 THEN
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Super Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(
            u.auth_user_id, 'Super Admin'::text,
            'Escalated Closure Request — ' || r.account_name,
            'Closure request for ' || r.vacancy_vcode
              || ' remains unactioned after 5 days.',
            'escalation'::text, 'vacancy_closure'::text, 'vacancy_closure'::text,
            r.id::TEXT, v_link, 2::smallint);
        END LOOP;
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL
           AND EXISTS (SELECT 1 FROM auth.users WHERE id = v_req_auth) THEN
          PERFORM public.notify_user(
            v_req_auth, 'Ops'::text,
            'Your Closure Request Escalated to Super Admin',
            'Your closure request for ' || r.vacancy_vcode
              || ' has been escalated to Super Admin after 5 days of no action.',
            'escalation'::text, 'vacancy_closure'::text, 'vacancy_closure'::text,
            r.id::TEXT, v_link, 2::smallint);
        END IF;
      ELSE
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Head Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(
            u.auth_user_id, 'Head Admin'::text,
            'Unactioned Closure Request — ' || r.account_name,
            'Closure request for ' || r.vacancy_vcode
              || ' has been pending for 3 days with no action from Encoder.',
            'escalation'::text, 'vacancy_closure'::text, 'vacancy_closure'::text,
            r.id::TEXT, v_link, 1::smallint);
        END LOOP;
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL
           AND EXISTS (SELECT 1 FROM auth.users WHERE id = v_req_auth) THEN
          PERFORM public.notify_user(
            v_req_auth, 'Ops'::text,
            'Your Closure Request Has Been Escalated',
            'Your closure request for ' || r.vacancy_vcode
              || ' has been escalated to Head Admin.',
            'escalation'::text, 'vacancy_closure'::text, 'vacancy_closure'::text,
            r.id::TEXT, v_link, 1::smallint);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_hc_request_sla()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r          RECORD;
  u          RECORD;
  lvl        SMALLINT;
  v_req_auth uuid;
BEGIN
  FOR r IN
    SELECT h.*,
           COALESCE(h.account_name_snapshot, a.account_name, 'the account') AS account_name,
           COALESCE(h.group_name_snapshot,   g.group_name,   'Group')       AS group_name
    FROM public.headcount_requests h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.groups   g ON g.id = COALESCE(h.group_id, a.group_id)
    WHERE LOWER(h.status) = 'pending'
      AND h.created_at    < NOW() - INTERVAL '3 days'
  LOOP
    lvl := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    IF NOT public.notification_sla_exists('hc_request', r.id::TEXT, lvl) THEN
      IF lvl = 2 THEN
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Super Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(
            u.auth_user_id, 'Super Admin'::text,
            'Escalated HC Request — ' || r.group_name,
            'An HC request for ' || r.account_name
              || ' remains unactioned after 5 days.',
            'escalation'::text, 'hc_request'::text, 'headcount_request'::text,
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 2::smallint);
        END LOOP;
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL
           AND EXISTS (SELECT 1 FROM auth.users WHERE id = v_req_auth) THEN
          PERFORM public.notify_user(
            v_req_auth, r.requested_by_role::text,
            'Your HC Request Escalated to Super Admin',
            'Your HC request for ' || r.account_name
              || ' has been escalated to Super Admin after 5 days of no action.',
            'escalation'::text, 'hc_request'::text, 'headcount_request'::text,
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 2::smallint);
        END IF;
      ELSE
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Head Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(
            u.auth_user_id, 'Head Admin'::text,
            'Unactioned HC Request — ' || r.group_name,
            r.requested_by_name || '''s HC request for ' || r.account_name
              || ' has been pending for 3 days. Please review.',
            'escalation'::text, 'hc_request'::text, 'headcount_request'::text,
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 1::smallint);
        END LOOP;
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL
           AND EXISTS (SELECT 1 FROM auth.users WHERE id = v_req_auth) THEN
          PERFORM public.notify_user(
            v_req_auth, r.requested_by_role::text,
            'Your HC Request Has Been Escalated',
            'Your HC request for ' || r.account_name
              || ' has been escalated to Head Admin due to no action.',
            'escalation'::text, 'hc_request'::text, 'headcount_request'::text,
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 1::smallint);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.close_vacancy_request(p_vacancy_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := get_my_profile_id();
  v_role       text := get_my_role();
  v            public.vacancies;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Closure reason is required';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;

  -- Scope: SA/HA always; Encoder/HRCO/OM in account scope
  IF NOT (public.i_have_full_access() OR public.i_have_account_scope(v.account_id)) THEN
    RAISE EXCEPTION 'Vacancy % is outside your scope', p_vacancy_id USING ERRCODE='42501';
  END IF;

  -- Transition guard (validator handles it too, but give a clearer error here)
  IF v.status NOT IN ('Draft','Pending Approval','Open','On Hold') THEN
    RAISE EXCEPTION 'Cannot close vacancy in status %', v.status USING ERRCODE='check_violation';
  END IF;

  UPDATE public.vacancies
     SET status = 'Closed',
         closure_request_status = 'Approved',
         has_pending_closure = false,
         remarks = COALESCE(remarks,'') ||
                   CASE WHEN remarks IS NULL OR remarks='' THEN '' ELSE E'\n' END ||
                   '[CLOSED] ' || p_reason,
         updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','UPDATE', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Closed','semantic_action','CLOSE_VACANCY','reason', p_reason,'actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status','Closed');
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(p_applicant_id uuid, p_last_name text DEFAULT NULL::text, p_first_name text DEFAULT NULL::text, p_middle_name text DEFAULT NULL::text, p_full_name text DEFAULT NULL::text, p_contact_number text DEFAULT NULL::text, p_remarks text DEFAULT NULL::text, p_roving_assignment_id uuid DEFAULT NULL::uuid, p_hired_by_user_id uuid DEFAULT NULL::uuid, p_endorsed_by_deployer_id uuid DEFAULT NULL::uuid, p_endorsed_by_name text DEFAULT NULL::text, p_hired_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text    := public.get_my_role();
  v_role_level  int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id  uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_app         public.applicants%ROWTYPE;
  v_vac         public.vacancies%ROWTYPE;
  v_hr          public.hr_emploc%ROWTYPE;
  v_full_name   text;
  v_hired_by_id uuid;
  v_is_roving   boolean;
  v_store_link_id uuid;
  v_late_result   jsonb;
  -- fast-track vars
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
  -- §1 OHM2026_0068: diagnostic vars for controlled NOT FOUND error (vacancy lookup)
  v_diag_is_archived  boolean;
  v_diag_deleted_at   timestamptz;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────────────────
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock applicant ─────────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.status, 'New') IN (
    'Failed', 'Backout', 'Did Not Report', 'Rejected by Ops'
  ) THEN
    RAISE EXCEPTION
      'cannot confirm onboarding: applicant is in terminal status %', v_app.status
      USING ERRCODE = '22023';
  END IF;

  -- ── Resolve roving flag ───────────────────────────────────────────────────
  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  -- ── Idempotent guard ─────────────────────────────────────────────────────
  IF v_app.status = 'Confirmed Onboard' THEN
    IF v_is_roving THEN
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
         AND assignment_type = 'Roving'
         AND deleted_at IS NULL
       ORDER BY created_at ASC LIMIT 1;
    ELSE
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE deleted_at IS NULL
         AND (
           applicant_id = v_app.id
           OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
         )
       ORDER BY created_at DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
      'ok',               true,
      'applicant_id',     v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id',     v_hr.id,
      'vcode',            v_app.vacancy_vcode,
      'idempotent',       true
    );
  END IF;

  -- ── Fetch and lock vacancy ────────────────────────────────────────────────
  -- §2 OHM2026_0068: Source-agnostic — hc_request, migration/import, manual, and
  -- restored-import vacancies are treated identically. The vacancy.source column is
  -- NEVER consulted for approval eligibility; only is_archived and deleted_at matter.
  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Controlled diagnostic guard: distinguish the exact reason so the Flutter
    -- client receives a machine-parseable prefix and a human-readable message
    -- instead of a raw PostgREST P0002 (no_data_found) exception.
    -- ERRCODE 22023 (invalid_parameter_value) → HTTP 400 via PostgREST, which
    -- the Flutter catch handler decodes into a clean snackbar message.
    SELECT COALESCE(is_archived, false), deleted_at
      INTO v_diag_is_archived, v_diag_deleted_at
      FROM public.vacancies
     WHERE vcode = v_app.vacancy_vcode
     LIMIT 1;

    IF FOUND AND v_diag_is_archived THEN
      RAISE EXCEPTION 'VACANCY_ARCHIVED: Vacancy % has been archived. Restore the vacancy before approving.',
        v_app.vacancy_vcode
        USING ERRCODE = '22023';
    ELSIF FOUND AND v_diag_deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'VACANCY_REMOVED: Vacancy % is no longer active. It may have been removed or rolled back from an import batch.',
        v_app.vacancy_vcode
        USING ERRCODE = '22023';
    ELSE
      RAISE EXCEPTION 'VACANCY_NOT_FOUND: No active vacancy record found for %. Please refresh and try again.',
        v_app.vacancy_vcode
        USING ERRCODE = '22023';
    END IF;
  END IF;

  IF COALESCE(v_vac.has_pending_closure, false) = true THEN
    RAISE EXCEPTION
      'onboarding blocked: vacancy % has a pending closure request. Withdraw the closure request first.',
      v_vac.vcode
      USING ERRCODE = '55000';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF p_contact_number IS NOT NULL AND btrim(p_contact_number) <> '' THEN
    PERFORM public.fn_validate_ph_contact_number(p_contact_number);
  END IF;

  -- ── Resolve full name ─────────────────────────────────────────────────────
  v_full_name := COALESCE(
    NULLIF(btrim(p_full_name), ''),
    NULLIF(btrim(concat_ws(' ',
      NULLIF(p_first_name, ''),
      NULLIF(p_middle_name, ''),
      NULLIF(p_last_name, '')
    )), ''),
    v_app.full_name
  );

  v_hired_by_id := COALESCE(p_hired_by_user_id, v_profile_id);

  -- ── Update applicant ─────────────────────────────────────────────────────
  -- p_hired_date (caller-supplied) takes precedence over any existing
  -- hired_date; falls back to CURRENT_DATE only when both are absent.
  -- RETURNING * captures slot_id / coverage_slot_id / coverage_group_id for the
  -- Phase C (stationary) + Phase R-C (coverage) propagation below.
  UPDATE public.applicants
  SET
    last_name                = COALESCE(NULLIF(p_last_name, ''),    last_name),
    first_name               = COALESCE(NULLIF(p_first_name, ''),   first_name),
    middle_name              = p_middle_name,
    full_name                = v_full_name,
    full_name_snapshot       = v_full_name,
    contact_number           = COALESCE(NULLIF(p_contact_number, ''), contact_number),
    remarks                  = p_remarks,
    roving_assignment_id     = COALESCE(p_roving_assignment_id, roving_assignment_id),
    status                   = 'Confirmed Onboard',
    hired_date               = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
    hired_at                 = COALESCE(hired_at, NOW()),
    hired_by                 = v_actor_name,
    hired_by_team            = v_role,
    hired_by_user_id         = v_hired_by_id,
    endorsed_by_deployer_id  = p_endorsed_by_deployer_id,
    endorsed_by_name         = p_endorsed_by_name,
    deployed_by_user_id      = v_profile_id,
    is_archived              = false,
    updated_at               = NOW(),
    updated_by               = v_profile_id
  WHERE id = p_applicant_id
  RETURNING * INTO v_app;
  -- v_app.slot_id (Phase B), v_app.coverage_slot_id / coverage_group_id (Phase R-B)
  -- now reflect the bound values (or NULL). Used in propagation below.

  -- ── Existing employee fast-track ──────────────────────────────────────────
  -- Employee numbers already in active Plantilla do not go back through HR
  -- Emploc. For roving/multi-store approvals, reuse the existing Plantilla
  -- employee and add/activate only the missing store assignment.
  SELECT * INTO v_existing_plt
    FROM public.plantilla
   WHERE account = v_vac.account
     AND status = 'Active'
     AND is_deleted = false
     AND employee_no IS NOT NULL
     AND (
       (
         COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL
         AND roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       )
       OR LOWER(TRIM(employee_name)) = LOWER(TRIM(v_full_name))
     )
   ORDER BY
     CASE
       WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
       ELSE 1
     END,
     created_at DESC
   LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    v_roving_id := COALESCE(
      v_existing_plt.roving_assignment_id,
      p_roving_assignment_id,
      v_app.roving_assignment_id
    );

    IF v_roving_id IS NULL THEN
      INSERT INTO public.roving_assignments (
        master_applicant_id, account, account_id,
        primary_vcode, label, created_by, updated_by
      ) VALUES (
        v_app.id, v_vac.account, v_vac.account_id,
        COALESCE(v_existing_plt.vcode, v_vac.vcode),
        v_full_name,
        v_profile_id, v_profile_id
      )
      RETURNING id INTO v_roving_id;

      v_new_roving := true;
    END IF;

    UPDATE public.applicants
    SET
      roving_assignment_id = v_roving_id,
      updated_at = NOW(),
      updated_by = v_profile_id
    WHERE id = v_app.id
    RETURNING * INTO v_app;

    UPDATE public.plantilla
    SET
      deployment_type      = 'Roving',
      roving_assignment_id = v_roving_id,
      updated_at           = NOW(),
      updated_by           = v_profile_id
    WHERE id = v_existing_plt.id;

    IF v_existing_plt.vcode IS NOT NULL THEN
      SELECT id INTO v_plt_store_link_id
        FROM public.plantilla_store_links
       WHERE plantilla_id = v_existing_plt.id
         AND roving_assignment_id = v_roving_id
         AND (vacancy_id = v_existing_plt.vacancy_id OR vcode = v_existing_plt.vcode)
         AND deleted_at IS NULL
       LIMIT 1
      FOR UPDATE;

      IF v_plt_store_link_id IS NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, roving_assignment_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_existing_plt.id, v_roving_id,
          v_existing_plt.vacancy_id, v_existing_plt.vcode,
          v_existing_plt.store_name, v_existing_plt.account,
          'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    v_plt_store_link_id := NULL;

    SELECT id INTO v_plt_store_link_id
      FROM public.plantilla_store_links
     WHERE plantilla_id = v_existing_plt.id
       AND roving_assignment_id = v_roving_id
       AND (
         vacancy_id = v_vac.id
         OR vcode = v_vac.vcode
         OR (
           account = v_vac.account
           AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
         )
       )
       AND deleted_at IS NULL
     LIMIT 1
    FOR UPDATE;

    IF v_plt_store_link_id IS NULL THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_roving_id,
        v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_plt_store_link_id;

      IF v_plt_store_link_id IS NULL THEN
        SELECT id INTO v_plt_store_link_id
         FROM public.plantilla_store_links
         WHERE plantilla_id = v_existing_plt.id
           AND roving_assignment_id = v_roving_id
           AND (
             vacancy_id = v_vac.id
             OR vcode = v_vac.vcode
             OR (
               account = v_vac.account
               AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
             )
           )
           AND deleted_at IS NULL
         LIMIT 1;
      END IF;
    ELSE
      UPDATE public.plantilla_store_links
      SET
        status      = 'Active',
        unlinked_at = NULL,
        unlinked_by = NULL,
        updated_at  = NOW(),
        updated_by  = v_profile_id
      WHERE id = v_plt_store_link_id;
    END IF;

    UPDATE public.vacancies
    SET
      status     = 'Filled',
      updated_at = NOW(),
      updated_by = v_profile_id
    WHERE id = v_vac.id;

    INSERT INTO public.employee_activity_log (
      emploc_no, vcode, activity_type, description, performed_by, metadata
    ) VALUES (
      COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_app.full_name),
      v_vac.vcode,
      'confirmed_onboard_fast_track',
      'Existing Plantilla employee fast-tracked to new store, bypassing HR Emploc queue for ' || v_vac.vcode,
      v_actor_name,
      jsonb_build_object(
        'applicant_id',              v_app.id,
        'hr_emploc_id',              NULL,
        'plantilla_id',              v_existing_plt.id,
        'plantilla_store_link_id',   v_plt_store_link_id,
        'vacancy_id',                v_vac.id,
        'employee_no',               v_existing_plt.employee_no,
        'roving_assignment_id',      v_roving_id,
        'new_roving_created',        v_new_roving,
        'skipped_hr_emploc',         true,
        'role',                      v_role,
        'hired_by_user_id',          v_hired_by_id,
        'hired_date',                v_app.hired_date,
        'movement_at',               NOW()
      )
    );

    -- Fast-track: existing Plantilla employee bypasses HR Emploc entirely.
    -- No slot sync here — this path skips the hr_processing state and goes
    -- directly to occupied (handled by Phase 6.3 in move_to_plantilla).
    RETURN jsonb_build_object(
      'ok',                       true,
      'applicant_id',             v_app.id,
      'applicant_status',         v_app.status,
      'hr_emploc_id',             NULL,
      'plantilla_id',             v_existing_plt.id,
      'plantilla_store_link_id',  v_plt_store_link_id,
      'vcode',                    v_vac.vcode,
      'hired_by_user_id',         v_hired_by_id,
      'hired_date',               v_app.hired_date,
      'is_roving',                true,
      'fast_tracked',             true,
      'skipped_hr_emploc',        true,
      'new_roving_created',       v_new_roving
    );
  END IF;

  -- ── Find or create HR Emploc ──────────────────────────────────────────────
  IF v_is_roving THEN
    -- ROVING: look for existing master by roving_assignment_id
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       AND assignment_type = 'Roving'
       AND deleted_at IS NULL
     ORDER BY created_at ASC LIMIT 1
    FOR UPDATE;

    v_roving_hr_found := FOUND;

    IF v_roving_hr_found THEN
      v_existing_employee_no := COALESCE(
        NULLIF(BTRIM(v_hr.employee_no), ''),
        NULLIF(BTRIM(v_hr.emploc_no), '')
      );

      IF v_hr.status = 'Moved to Plantilla' OR v_existing_employee_no IS NOT NULL THEN
        SELECT * INTO v_existing_plt
          FROM public.plantilla
         WHERE is_deleted = false
           AND status IN ('Active', 'For Deactivation', 'On Leave')
           AND (
             roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
             OR hr_emploc_id = v_hr.id
             OR (
               v_existing_employee_no IS NOT NULL
               AND employee_no = v_existing_employee_no
               AND account = v_vac.account
             )
           )
         ORDER BY
           CASE
             WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
             WHEN hr_emploc_id = v_hr.id THEN 1
             ELSE 2
           END,
           created_at DESC
         LIMIT 1
        FOR UPDATE;

        IF FOUND THEN
          v_roving_id := COALESCE(
            v_existing_plt.roving_assignment_id,
            v_hr.roving_assignment_id,
            p_roving_assignment_id,
            v_app.roving_assignment_id
          );

          UPDATE public.applicants
          SET
            roving_assignment_id = v_roving_id,
            updated_at = NOW(),
            updated_by = v_profile_id
          WHERE id = v_app.id
          RETURNING * INTO v_app;

          UPDATE public.plantilla
          SET
            deployment_type      = 'Roving',
            roving_assignment_id = v_roving_id,
            updated_at           = NOW(),
            updated_by           = v_profile_id
          WHERE id = v_existing_plt.id;

          SELECT id INTO v_plt_store_link_id
            FROM public.plantilla_store_links
           WHERE plantilla_id = v_existing_plt.id
             AND roving_assignment_id = v_roving_id
             AND (
               vacancy_id = v_vac.id
               OR vcode = v_vac.vcode
               OR (
                 account = v_vac.account
                 AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
               )
             )
             AND deleted_at IS NULL
           LIMIT 1
          FOR UPDATE;

          IF v_plt_store_link_id IS NULL THEN
            INSERT INTO public.plantilla_store_links (
              plantilla_id, roving_assignment_id,
              vacancy_id, vcode, store_name, account,
              status, linked_at, linked_by, created_by, updated_by
            ) VALUES (
              v_existing_plt.id, v_roving_id,
              v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
              'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
            )
            ON CONFLICT DO NOTHING
            RETURNING id INTO v_plt_store_link_id;

            IF v_plt_store_link_id IS NULL THEN
              SELECT id INTO v_plt_store_link_id
                FROM public.plantilla_store_links
               WHERE plantilla_id = v_existing_plt.id
                 AND roving_assignment_id = v_roving_id
                 AND (
                   vacancy_id = v_vac.id
                   OR vcode = v_vac.vcode
                   OR (
                     account = v_vac.account
                     AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
                   )
                 )
                 AND deleted_at IS NULL
               LIMIT 1;
            END IF;
          ELSE
            UPDATE public.plantilla_store_links
            SET
              status      = 'Active',
              unlinked_at = NULL,
              unlinked_by = NULL,
              updated_at  = NOW(),
              updated_by  = v_profile_id
            WHERE id = v_plt_store_link_id;
          END IF;

          UPDATE public.vacancies
          SET
            status     = 'Filled',
            updated_at = NOW(),
            updated_by = v_profile_id
          WHERE id = v_vac.id;

          INSERT INTO public.employee_activity_log (
            emploc_no, vcode, activity_type, description, performed_by, metadata
          ) VALUES (
            COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_existing_employee_no, v_app.full_name),
            v_vac.vcode,
            'confirmed_onboard_fast_track',
            'Existing roving employee fast-tracked to new store, bypassing duplicate HR Emploc creation for ' || v_vac.vcode,
            v_actor_name,
            jsonb_build_object(
              'applicant_id',              v_app.id,
              'hr_emploc_id',              v_hr.id,
              'plantilla_id',              v_existing_plt.id,
              'plantilla_store_link_id',   v_plt_store_link_id,
              'vacancy_id',                v_vac.id,
              'employee_no',               COALESCE(v_existing_plt.employee_no, v_existing_employee_no),
              'roving_assignment_id',      v_roving_id,
              'skipped_hr_emploc_insert',  true,
              'role',                      v_role,
              'hired_by_user_id',          v_hired_by_id,
              'hired_date',                v_app.hired_date,
              'movement_at',               NOW()
            )
          );

          -- Roving fast-track duplicate guard: no slot sync (roving carve-out).
          RETURN jsonb_build_object(
            'ok',                       true,
            'applicant_id',             v_app.id,
            'applicant_status',         v_app.status,
            'hr_emploc_id',             v_hr.id,
            'plantilla_id',             v_existing_plt.id,
            'plantilla_store_link_id',  v_plt_store_link_id,
            'vcode',                    v_vac.vcode,
            'hired_by_user_id',         v_hired_by_id,
            'hired_date',               v_app.hired_date,
            'is_roving',                true,
            'fast_tracked',             true,
            'skipped_hr_emploc',        true,
            'duplicate_roving_guard',   true
          );
        END IF;
      END IF;
    END IF;

    IF NOT v_roving_hr_found THEN
      -- First store: create roving master.
      -- Roving INSERT: no slot_id (roving carve-out — OHM2026_0044).
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_code_snapshot,
        account, account_id, chain_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Roving'::public.hr_emploc_assignment_type,
        COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
        '[]'::jsonb
      )
      ON CONFLICT DO NOTHING
      RETURNING * INTO v_hr;

      IF v_hr.id IS NULL THEN
        SELECT * INTO v_hr
          FROM public.hr_emploc
         WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
           AND assignment_type = 'Roving'
           AND deleted_at IS NULL
         ORDER BY created_at ASC LIMIT 1
        FOR UPDATE;
      END IF;
    END IF;

    -- Insert store link (idempotent)
    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, roving_assignment_id, vacancy_id, vcode,
      store_name, account, status, confirmed_at, confirmed_by,
      created_by, updated_by
    ) VALUES (
      v_hr.id,
      COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
      v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_store_link_id;

    -- ── Late store auto-link ─────────────────────────────────────────────
    IF v_hr.status = 'Moved to Plantilla' AND v_store_link_id IS NOT NULL THEN
      SELECT public.link_late_store_to_plantilla(v_store_link_id) INTO v_late_result;
    END IF;

  ELSE
    -- ── STATIONARY / COVERAGE: find or create HR Emploc ──────────────────────
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE deleted_at IS NULL
       AND (
         applicant_id = v_app.id
         OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
       )
     ORDER BY created_at DESC LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      -- Phase C: propagate applicants.slot_id into hr_emploc.slot_id at INSERT.
      -- Phase R-C (OHM2026_0075): ALSO propagate applicants.coverage_slot_id +
      -- coverage_group_id (NULL for genuine stationary; set for coverage applicants,
      -- whose slot_id is NULL — the mutex CHECK keeps the two lineages disjoint).
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores,
        slot_id,            -- Phase C (OHM2026_0045): exact stationary slot; NULL for no-slot VCODEs
        coverage_slot_id,   -- Phase R-C (OHM2026_0075): exact coverage slot; NULL for stationary
        coverage_group_id   -- Phase R-C (OHM2026_0075): coverage group (query convenience); NULL for stationary
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb,
        v_app.slot_id,            -- Phase C: NULL when applicant has no bound stationary slot
        v_app.coverage_slot_id,   -- Phase R-C: NULL when applicant has no bound coverage slot
        v_app.coverage_group_id   -- Phase R-C: NULL when applicant has no coverage group
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  -- ── Audit log ────────────────────────────────────────────────────────────
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id',            v_app.id,
      'hr_emploc_id',            v_hr.id,
      'vacancy_id',              v_vac.id,
      'role',                    v_role,
      'hired_by_user_id',        v_hired_by_id,
      'endorsed_by_deployer_id', p_endorsed_by_deployer_id,
      'endorsed_by_name',        p_endorsed_by_name,
      'is_roving',               v_is_roving,
      'hired_date',              v_app.hired_date,
      'late_store_linked',       v_late_result IS NOT NULL,
      'movement_at',             NOW()
    )
  );

  -- ── Slot pipeline→hr_processing sync (routed by binding lineage) ──────────
  -- Phase R-C (OHM2026_0075) routes by the applicant's binding column. The mutex
  -- CHECK (RC2 / applicants_slot_coverage_mutex_chk) guarantees at most one of
  -- coverage_slot_id / slot_id is set, so the branches are disjoint.
  --
  --   coverage_slot_id IS NOT NULL → ROVING (Phase R-C): exact coverage slot
  --     pipeline→hr_processing via fn_sync_coverage_slot_to_hr_processing. NO
  --     coverage_group_id LIMIT 1, NO stationary VCODE LIMIT 1 on the carrier VCODE.
  --     Non-blocking — the helper NEVER raises (plan Q4).
  --   slot_id set / no slot (NOT v_is_roving) → STATIONARY (Phase C, UNCHANGED):
  --     fn_sync_slot_to_hr_processing with the exact slot (or legacy VCODE fallback).
  --   legacy roving (roving_assignment_id, NULL coverage_slot_id) → no slot sync
  --     (roving carve-out, unchanged).
  IF v_app.coverage_slot_id IS NOT NULL THEN
    PERFORM public.fn_sync_coverage_slot_to_hr_processing(
      p_coverage_slot_id => v_app.coverage_slot_id,
      p_applicant_id     => v_app.id,
      p_performed_by     => v_profile_id,
      p_source_fn        => 'confirm_applicant_onboard'
    );
  ELSIF NOT v_is_roving THEN
    PERFORM public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard',
      p_slot_id      => v_app.slot_id   -- Phase C: exact slot; NULL → legacy path
    );
  END IF;

  RETURN jsonb_build_object(
    'ok',               true,
    'applicant_id',     v_app.id,
    'applicant_status', v_app.status,
    'hr_emploc_id',     v_hr.id,
    'vcode',            v_vac.vcode,
    'hired_by_user_id', v_hired_by_id,
    'hired_date',       v_app.hired_date,
    'is_roving',        v_is_roving,
    'late_store_linked', v_late_result
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_coverage_group_onboarding(p_applicant_id uuid, p_selected_store_ids uuid[], p_hired_by_user_id uuid DEFAULT NULL::uuid, p_hired_date date DEFAULT NULL::date, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role         text    := public.get_my_role();
  v_role_level   int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id   uuid    := public.get_my_profile_id();
  v_actor_name   text    := public.get_my_full_name();
  v_app          public.applicants%ROWTYPE;
  v_group        public.coverage_groups%ROWTYPE;
  v_hr           public.hr_emploc%ROWTYPE;
  v_hired_by_id  uuid;
  v_store_record record;
  v_covered_json jsonb   := '[]'::jsonb;
  v_store_id     uuid;
BEGIN
  -- 1. RBAC Guard
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Fetch and lock applicant
  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant not found or archived' USING ERRCODE = 'P0002';
  END IF;

  IF v_app.coverage_group_id IS NULL OR v_app.coverage_slot_id IS NULL THEN
    RAISE EXCEPTION 'applicant is not assigned to a coverage group slot' USING ERRCODE = '22023';
  END IF;

  IF COALESCE(v_app.status, 'New') IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops') THEN
    RAISE EXCEPTION 'cannot onboard: applicant is in terminal status %', v_app.status USING ERRCODE = '22023';
  END IF;

  -- 3. Fetch and lock coverage group
  SELECT * INTO v_group FROM public.coverage_groups WHERE id = v_app.coverage_group_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found' USING ERRCODE = 'P0002';
  END IF;

  -- 4. Scope Guard
  IF NOT public.i_have_full_access() AND NOT (v_group.account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: coverage group is outside caller scope' USING ERRCODE = '42501';
  END IF;

  IF array_length(p_selected_store_ids, 1) IS NULL OR array_length(p_selected_store_ids, 1) < 1 THEN
    RAISE EXCEPTION 'at least one store must be selected' USING ERRCODE = '22023';
  END IF;

  -- 5. Build covered_stores JSONB array and validate footprint
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.store_name, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'store % is not part of active coverage group footprint', v_store_id USING ERRCODE = '22023';
    END IF;

    v_covered_json := v_covered_json || jsonb_build_object(
      'store_id',   v_store_id,
      'store_name', v_store_record.store_name,
      'is_anchor',  v_store_record.is_anchor
    );
  END LOOP;

  v_hired_by_id := COALESCE(p_hired_by_user_id, v_profile_id);

  -- 6. Update applicant status
  UPDATE public.applicants
     SET status             = 'Confirmed Onboard',
         hired_date         = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
         hired_at           = COALESCE(hired_at, NOW()),
         hired_by           = v_actor_name,
         hired_by_team      = v_role,
         hired_by_user_id   = v_hired_by_id,
         deployed_by_user_id = v_profile_id,
         updated_at         = NOW(),
         updated_by         = v_profile_id
   WHERE id = p_applicant_id;

  -- 7. Insert Coverage HR Emploc.
  --    vcode = NULL            : fk_hr_emploc_vcode skips NULL values.
  --    vacancy_code_snapshot   : CGCODE for display/traceability; no FK.
  INSERT INTO public.hr_emploc (
    applicant_name, applicant_name_snapshot, applicant_id,
    vcode, vacancy_code_snapshot,
    account, account_id, position_id_snapshot, position,
    status, hr_status, hired_date,
    deployed_by_user_id, created_by, updated_by, date_requested,
    assignment_type, coverage_group_id, coverage_slot_id, covered_stores,
    ops_remarks
  ) VALUES (
    v_app.full_name, v_app.full_name, v_app.id,
    NULL, v_group.coverage_code,
    (SELECT account_name FROM public.accounts WHERE id = v_group.account_id),
    v_group.account_id, v_group.position_id,
    (SELECT position_name FROM public.positions WHERE id = v_group.position_id),
    'Pending Emploc', 'Pending', COALESCE(p_hired_date, CURRENT_DATE),
    v_profile_id, v_profile_id, v_profile_id, NOW(),
    'Coverage'::public.hr_emploc_assignment_type,
    v_group.id, v_app.coverage_slot_id, v_covered_json,
    p_remarks
  )
  RETURNING * INTO v_hr;

  -- 8. Populate hr_emploc_store_links for each selected store.
  --    vcode = NULL            : avoids uq_hr_emploc_store_links_emploc_vcode_active
  --                              collision (all Coverage links share the same CGCODE).
  --                              NULL values are treated as distinct in B-tree indexes.
  --    coverage_slot_id        : full slot traceability per store link.
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.store_name, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
      vcode, store_name, account,
      status, confirmed_at, confirmed_by, created_by, updated_by
    ) VALUES (
      v_hr.id, v_group.id, v_app.coverage_slot_id, v_store_id,
      NULL, v_store_record.store_name, v_hr.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    );
  END LOOP;

  -- 9. Transition slot from pipeline → hr_processing
  PERFORM public.fn_sync_coverage_slot_to_hr_processing(
    p_coverage_slot_id => v_app.coverage_slot_id,
    p_applicant_id     => v_app.id,
    p_performed_by     => v_profile_id,
    p_source_fn        => 'confirm_coverage_group_onboarding'
  );

  -- 10. Log activity
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    v_app.full_name,
    v_group.coverage_code,
    'confirmed_onboard',
    'Coverage applicant confirmed onboard to ' || array_to_string(p_selected_store_ids::text[], ', '),
    v_actor_name,
    jsonb_build_object(
      'applicant_id',       v_app.id,
      'hr_emploc_id',       v_hr.id,
      'coverage_group_id',  v_group.id,
      'coverage_slot_id',   v_app.coverage_slot_id,
      'selected_stores',    v_covered_json
    )
  );

  RETURN jsonb_build_object(
    'ok',                true,
    'hr_emploc_id',      v_hr.id,
    'coverage_group_id', v_group.id,
    'coverage_slot_id',  v_app.coverage_slot_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_applicant_and_link_to_vacancy(p_vacancy_id uuid, p_last_name text, p_first_name text, p_middle_name text, p_contact_number text, p_application_date date, p_source_channel text DEFAULT 'Walk-in'::text, p_comment text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  OHM2026_0043 — Patched: removed application_date, source_channel, comment,
  master_applicant_id from INSERT (columns do not exist in public.applicants).
  Phase B slot-claim logic (§B5) is identical to 20260817000000.
*/
DECLARE
  v              public.vacancies%ROWTYPE;
  new_id         uuid;
  v_claimed_slot uuid;
  v_claimed_ord  smallint;
  v_slot_count   bigint;
  v_slot_result  jsonb;
BEGIN
  IF NOT public.i_am_ops() THEN
    RAISE EXCEPTION 'forbidden: ops only';
  END IF;

  -- Required-field guard
  IF p_last_name IS NULL OR p_first_name IS NULL OR p_middle_name IS NULL
     OR p_contact_number IS NULL THEN
    RAISE EXCEPTION 'last_name, first_name, middle_name, contact_number are required';
  END IF;

  -- Format guard
  PERFORM public.fn_validate_ph_contact_number(p_contact_number);

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'vacancy not found'; END IF;
  IF v.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'vacancy archived'; END IF;
  IF COALESCE(v.has_pending_closure, false) THEN
    RAISE EXCEPTION 'vacancy is locked pending deletion';
  END IF;
  IF NOT (v.account = ANY (public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: out of scope';
  END IF;

  -- ── Phase B: slot-aware claim ─────────────────────────────────────────────
  -- Count non-roving slots for this VCODE (roving skipped — carve-out).
  SELECT COUNT(*) INTO v_slot_count
  FROM   public.plantilla_slots
  WHERE  legacy_vcode = v.vcode
    AND  is_roving    = false;

  IF v_slot_count > 0 THEN
    -- VCODE has slots — claim the lowest available open slot.
    -- FOR UPDATE SKIP LOCKED: concurrent adds take different slots instead
    -- of colliding; uq_applicants_one_active_per_slot is the backstop.
    SELECT id, slot_ordinal
      INTO v_claimed_slot, v_claimed_ord
    FROM   public.plantilla_slots
    WHERE  legacy_vcode = v.vcode
      AND  slot_status  = 'open'
      AND  is_roving    = false
    ORDER  BY slot_ordinal ASC, created_at ASC, id ASC
    LIMIT  1
    FOR UPDATE SKIP LOCKED;

    IF v_claimed_slot IS NULL THEN
      -- All slots are occupied/pipeline/hr_processing/closed — hard reject.
      RAISE EXCEPTION
        'no_open_slot: VCODE % has % slot(s) but none are open. '
        'All headcount is in pipeline, processing, filled, or closed. '
        'Request additional HC before adding another applicant.',
        v.vcode, v_slot_count
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  -- If v_slot_count = 0: v_claimed_slot stays NULL → legacy path below.
  -- ─────────────────────────────────────────────────────────────────────────

  INSERT INTO public.applicants (
    vacancy_vcode, last_name, first_name, middle_name, full_name,
    contact_number, status, slot_id, created_by
  ) VALUES (
    v.vcode, p_last_name, p_first_name, p_middle_name,
    p_last_name || ', ' || p_first_name || ' ' || p_middle_name,
    p_contact_number,
    'New', v_claimed_slot, public.get_my_profile_id()
  ) RETURNING id INTO new_id;

  PERFORM public.log_audit_event(
    'vacancy_module', 'INSERT', new_id,
    NULL,
    jsonb_build_object('action', 'create_applicant', 'vacancy_id', v.id)
  );

  -- ── Phase B: slot status transition ──────────────────────────────────────
  IF v_claimed_slot IS NOT NULL THEN
    -- Slot-aware path: direct open → pipeline transition for the claimed slot.
    -- This is a validated (blocking) call — if the transition is unexpectedly
    -- blocked the insert rolls back, surfacing a data integrity issue.
    SELECT public.fn_set_slot_status(
      p_slot_id      => v_claimed_slot,
      p_new_status   => 'pipeline',
      p_reason_code  => NULL,
      p_performed_by => public.get_my_profile_id(),
      p_remarks      => format(
        'Phase B / create_applicant_and_link_to_vacancy / VCODE=%s / '
        'applicant=%s / slot_ordinal=%s',
        v.vcode, new_id, v_claimed_ord
      )
    ) INTO v_slot_result;

    IF (v_slot_result->>'status') = 'blocked' THEN
      RAISE EXCEPTION
        'slot_transition_blocked: claimed slot % could not transition to '
        'pipeline — %. This indicates a data integrity issue; resolve '
        'slot status before adding applicants.',
        v_claimed_slot, v_slot_result->>'blocked_reason'
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- No slots for this VCODE — legacy non-blocking sync (no-op if no slot).
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v.vcode,
      p_performed_by => public.get_my_profile_id(),
      p_source_fn    => 'create_applicant_and_link_to_vacancy'
    );
  END IF;
  -- ─────────────────────────────────────────────────────────────────────────

  RETURN new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_coverage_group(p_account_id uuid, p_position_id uuid, p_employment_type text, p_area_name text, p_store_ids uuid[], p_anchor_store_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id      uuid;
  v_role           text;
  v_cgcode         text;
  v_group_id       uuid;
  v_store_id       uuid;
  v_overlap_store  text;
  v_overlap_cgcode text;
BEGIN
  SELECT id INTO v_caller_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_name INTO v_role
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.id = v_caller_id;

  IF v_role NOT IN ('Super Admin', 'Head Admin', 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  IF v_role = 'Encoder'
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.accounts
    WHERE id = p_account_id
      AND is_active = true
      AND lower(COALESCE(status, 'active')) <> 'archived'
  ) THEN
    RAISE EXCEPTION 'account not found or archived' USING ERRCODE = '42501';
  END IF;

  IF p_store_ids IS NULL OR array_length(p_store_ids, 1) < 2 THEN
    RAISE EXCEPTION 'coverage group requires at least 2 stores; use the normal Vacancy workflow for a single store'
      USING ERRCODE = '22023';
  END IF;

  IF p_anchor_store_id IS NULL OR NOT (p_anchor_store_id = ANY (p_store_ids)) THEN
    RAISE EXCEPTION 'anchor store must be one of the selected stores'
      USING ERRCODE = '22023';
  END IF;

  SELECT s.store_name, cg.coverage_code
  INTO v_overlap_store, v_overlap_cgcode
  FROM unnest(p_store_ids) AS t(sid)
  JOIN public.coverage_group_stores cgs
    ON cgs.store_id = t.sid
   AND cgs.archived_at IS NULL
  JOIN public.coverage_groups cg
    ON cg.id = cgs.coverage_group_id
   AND cg.archived_at IS NULL
   AND lower(COALESCE(cg.status, '')) <> 'archived'
  JOIN public.stores s
    ON s.id = t.sid
   AND s.is_active = true
   AND lower(COALESCE(s.status, 'active')) <> 'archived'
  LIMIT 1;

  IF v_overlap_store IS NOT NULL THEN
    RAISE EXCEPTION 'store "%" is already assigned to active coverage group %',
      v_overlap_store, v_overlap_cgcode
      USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(p_store_ids) AS sid
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.stores s
      WHERE s.id = sid
        AND s.account_id = p_account_id
        AND s.is_active = true
        AND lower(COALESCE(s.status, 'active')) <> 'archived'
        AND (
          EXISTS (
            SELECT 1
            FROM public.plantilla_slots ps
            WHERE ps.store_id = s.id
              AND ps.slot_status <> 'closed'
          )
          OR EXISTS (
            SELECT 1
            FROM public.employee_store_allocations esa
            WHERE esa.store_id = s.id
              AND esa.is_active = true
          )
        )
    )
  ) THEN
    RAISE EXCEPTION 'all stores must belong to the account and have active, non-archived Plantilla operational footprint'
      USING ERRCODE = '22023';
  END IF;

  v_cgcode := public.fn_generate_cgcode_for_account(p_account_id);

  INSERT INTO public.coverage_groups (
    coverage_code,
    account_id,
    position_id,
    employment_type,
    required_headcount,
    area_name,
    created_by
  ) VALUES (
    v_cgcode,
    p_account_id,
    p_position_id,
    p_employment_type,
    0,
    nullif(trim(coalesce(p_area_name, '')), ''),
    v_caller_id
  )
  RETURNING id INTO v_group_id;

  FOREACH v_store_id IN ARRAY p_store_ids LOOP
    INSERT INTO public.coverage_group_stores (
      coverage_group_id,
      store_id,
      is_anchor,
      added_by
    ) VALUES (
      v_group_id,
      v_store_id,
      (v_store_id = p_anchor_store_id),
      v_caller_id
    );
  END LOOP;

  RETURN json_build_object(
    'coverage_group_id', v_group_id,
    'coverage_code', v_cgcode
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.create_coverage_request(p_request_type request_type, p_payload jsonb DEFAULT '{}'::jsonb, p_account_id uuid DEFAULT NULL::uuid, p_position_id uuid DEFAULT NULL::uuid, p_employment_type text DEFAULT NULL::text, p_target_coverage_group_id uuid DEFAULT NULL::uuid, p_source_coverage_group_id uuid DEFAULT NULL::uuid, p_destination_coverage_group_id uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor record;
  v_request_id uuid;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
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
    p_destination_coverage_group_id,
    NULL -- No request_id yet since it is a new draft
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
$function$;

CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role               text := public.get_my_role();
  v_req                public.headcount_requests%ROWTYPE;
  v_account            public.accounts%ROWTYPE;
  v_store              public.stores%ROWTYPE;
  v_position           public.positions%ROWTYPE;
  v_coverage_group     public.coverage_groups%ROWTYPE;
  v_store_name         text;
  v_store_id           uuid;
  v_vcode              text;
  v_vcodes             text[];
  v_plantilla_id       uuid;
  v_vacancy_id         uuid;
  v_first_plantilla_id uuid;
  v_count              integer;
  i                    integer;
  v_triggered_by_id    uuid;
  v_triggered_by_name  text;
  v_hrco_user_id       uuid;
  v_hrco_name          text;
  v_group_id           uuid;
  v_group_name         text;
  v_slot_result        jsonb;
  v_max_ordinal        integer;
  -- store-array path
  v_hc_store_row       public.hc_request_stores%ROWTYPE;
  v_new_cg_id          uuid;
  v_cg_code            text;
  v_store_vcodes       jsonb := '[]'::jsonb;
  v_stores_added       integer := 0;
  v_store_row          public.stores%ROWTYPE;
  -- stationary path VCODE reuse fields
  v_reused_vcode       boolean := false;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_approved', 'current', v_req.status);
  END IF;

  v_count := COALESCE(v_req.headcount_needed, 1);

  IF v_count < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  IF v_count > 20 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'headcount_limit_exceeded', 'max', 20);
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_req.account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  END IF;

  SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;
  IF v_position.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  END IF;

  v_triggered_by_id := public.get_current_profile_id();
  SELECT full_name INTO v_triggered_by_name
  FROM public.users_profile WHERE id = v_triggered_by_id;

  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  SELECT group_name INTO v_group_name FROM public.groups WHERE id = v_group_id;

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  -- ── Detect roving path ─────────────────────────────────────────────────────
  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'roving' THEN

    -- Check if this is the new store-array path
    IF EXISTS (
      SELECT 1 FROM public.hc_request_stores WHERE request_id = p_request_id LIMIT 1
    ) THEN
      -- ══ NEW ROVING STORE-ARRAY PATH ══════════════════════════════════════
      -- Creates N VCodes (one per store) + 1 CGCode
      -- ═════════════════════════════════════════════════════════════════════
      v_vcodes := ARRAY[]::text[];

      -- Step 1: Create the Coverage Group (structure only)
      v_new_cg_id := gen_random_uuid();
      v_cg_code   := public.fn_generate_cgcode_for_account(v_req.account_id);

      INSERT INTO public.coverage_groups (
        id, account_id, group_id, position_id,
        coverage_code, area_name, employment_type,
        status, required_headcount,
        created_by, updated_by
      ) VALUES (
        v_new_cg_id,
        v_req.account_id,
        v_group_id,
        v_req.position_id,
        v_cg_code,
        COALESCE(v_req.area, ''),
        COALESCE(v_req.employment_type, 'Roving'),
        'open',
        v_count,
        v_triggered_by_id,
        v_triggered_by_id
      );

      -- Step 2: For each store in hc_request_stores, create VCode + Vacancy + Slot
      FOR v_hc_store_row IN
        SELECT * FROM public.hc_request_stores
        WHERE request_id = p_request_id
        ORDER BY sort_order ASC
      LOOP
        SELECT * INTO v_store_row FROM public.stores WHERE id = v_hc_store_row.store_id;

        -- Reuse existing VCODE for store if active vacancy exists
        v_vcode := public.find_reusable_store_vcode(v_req.account_id, v_hc_store_row.store_id, v_hc_store_row.store_name_snapshot);

        IF v_vcode IS NULL THEN
          v_vcode := public.generate_vcode_for_account(v_req.account_id);

          -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
          IF v_hc_store_row.store_id IS NOT NULL THEN
            UPDATE public.stores
            SET vcode = v_vcode
            WHERE id = v_hc_store_row.store_id
              AND (vcode IS NULL OR trim(vcode) = '');
          END IF;
        END IF;

        v_vcodes := array_append(v_vcodes, v_vcode);

        -- Upsert vacancy for this store
        INSERT INTO public.vacancies (
          vcode, account, position, status,
          account_id, store_id, position_id, group_id,
          area_name, store_name, vacant_date,
          required_headcount, source_plantilla_id,
          vacancy_type, employment_type, urgency_level,
          target_fill_date, triggered_by_user_id, triggered_by_name,
          hrco_user_id, hrco_name,
          source, source_headcount_request_id,
          area_city, province, store_branch,
          chain, chain_id,
          created_by, updated_by
        ) VALUES (
          v_vcode,
          v_account.account_name,
          v_position.position_name,
          'Open',
          v_account.id,
          v_hc_store_row.store_id,
          v_position.id,
          v_group_id,
          COALESCE(v_hc_store_row.province_snapshot, v_store_row.province, v_store_row.area_province),
          v_hc_store_row.store_name_snapshot,
          COALESCE(v_req.vacant_date, CURRENT_DATE),
          1,  -- 1 HC per store; total coverage HC = v_count slots on the CG
          NULL,
          CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
          COALESCE(v_req.employment_type, 'Roving'),
          v_req.urgency,
          v_req.target_fill_date,
          v_triggered_by_id, v_triggered_by_name,
          v_hrco_user_id, v_hrco_name,
          'hc_request', p_request_id,
          v_hc_store_row.city_snapshot,
          v_hc_store_row.province_snapshot,
          v_store_row.store_branch,
          v_group_name, v_group_id,
          v_triggered_by_id, v_triggered_by_id
        )
        ON CONFLICT (vcode) DO UPDATE
          SET required_headcount = public.vacancies.required_headcount + 1,
              updated_by = v_triggered_by_id
        RETURNING id INTO v_vacancy_id;

        -- Create or adopt plantilla_slots for this store VCode
        IF NOT EXISTS (
          SELECT 1 FROM public.plantilla_slots WHERE legacy_vcode = v_vcode LIMIT 1
        ) THEN
          PERFORM public.fn_create_slots_from_hc_request(p_request_id, 1, v_vcode);
        END IF;

        -- Add store to coverage_group_stores
        INSERT INTO public.coverage_group_stores (
          coverage_group_id, store_id, store_name_snapshot, account_id
        ) VALUES (
          v_new_cg_id,
          v_hc_store_row.store_id,
          v_hc_store_row.store_name_snapshot,
          v_req.account_id
        )
        ON CONFLICT DO NOTHING;

        v_stores_added := v_stores_added + 1;
      END LOOP;

      -- Step 3: Create coverage slots for the overall CG demand
      SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_new_cg_id;

      INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
      SELECT v_new_cg_id, v_max_ordinal + gs.ord, 'open'
      FROM generate_series(1, v_count) AS gs(ord);

      -- Step 4: Finalise the HC request
      UPDATE public.headcount_requests
      SET status                      = 'completed',
          vacancy_created             = true,
          slot_created_by_user_id     = v_triggered_by_id,
          slot_created_at             = NOW(),
          coverage_group_id           = v_new_cg_id,
          coverage_group_code_snapshot = v_cg_code,
          created_vcode               = NULL,
          created_vcodes              = v_vcodes
      WHERE id = p_request_id;

      RETURN jsonb_build_object(
        'ok',                    true,
        'request_id',            p_request_id,
        'workforce_type',        'roving',
        'path',                  'store_array',
        'coverage_group_id',     v_new_cg_id,
        'coverage_code',         v_cg_code,
        'stores_processed',      v_stores_added,
        'vcodes',                v_vcodes,
        'vcode_count',           array_length(v_vcodes, 1),
        'coverage_slots_created', v_count,
        'vacancy_created',       true
      );

    ELSE
      -- ══ OLD ROVING PATH: add coverage slots to existing CG (UNCHANGED) ══
      IF v_req.coverage_group_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_required_for_roving');
      END IF;

      SELECT * INTO v_coverage_group
      FROM public.coverage_groups
      WHERE id = v_req.coverage_group_id
        AND account_id = v_req.account_id
        AND archived_at IS NULL
      FOR UPDATE;

      IF v_coverage_group.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'coverage_group_id');
      END IF;

      IF v_coverage_group.position_id <> v_req.position_id THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_position_mismatch');
      END IF;

      SELECT COALESCE(MAX(slot_ordinal), 0)
        INTO v_max_ordinal
      FROM public.coverage_slots
      WHERE coverage_group_id = v_coverage_group.id;

      INSERT INTO public.coverage_slots (coverage_group_id, slot_ordinal, slot_status)
      SELECT v_coverage_group.id, v_max_ordinal + gs.ord, 'open'
      FROM generate_series(1, v_count) AS gs(ord);

      UPDATE public.coverage_groups
      SET required_headcount = required_headcount + v_count,
          status = 'open'
      WHERE id = v_coverage_group.id;

      UPDATE public.headcount_requests
      SET status                      = 'completed',
          vacancy_created             = true,
          slot_created_by_user_id     = v_triggered_by_id,
          slot_created_at             = NOW(),
          coverage_group_code_snapshot = COALESCE(coverage_group_code_snapshot, v_coverage_group.coverage_code),
          created_vcode               = NULL,
          created_vcodes              = ARRAY[]::text[]
      WHERE id = p_request_id;

      RETURN jsonb_build_object(
        'ok',                    true,
        'request_id',            p_request_id,
        'headcount_created',     v_count,
        'workforce_type',        'roving',
        'path',                  'coverage_group',
        'coverage_group_id',     v_coverage_group.id,
        'coverage_code',         v_coverage_group.coverage_code,
        'coverage_slots_created', v_count,
        'vacancy_created',       true
      );
    END IF;
  END IF;

  -- ── Floating path ──────────────────────────────────────────────────────────
  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'floating' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'floating_workforce_not_enabled');
  END IF;

  -- ── Stationary path ────────────────────────────────────────────────────────
  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
  END IF;

  v_store_name := NULLIF(TRIM(COALESCE(v_store.store_name, v_req.store_name_snapshot)), '');
  v_store_id   := v_store.id;

  IF v_store_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_name');
  END IF;

  -- ── ohm#9kq4m2z8: 1-store-1-VCODE reuse check ─────────────────────────────
  v_vcode := public.find_reusable_store_vcode(v_account.id, v_store_id, v_store_name);

  IF v_vcode IS NOT NULL THEN
    v_reused_vcode := true;

    SELECT id INTO v_vacancy_id
    FROM public.vacancies
    WHERE vcode                          = v_vcode
      AND status                         IN ('Open', 'Pipeline')
      AND COALESCE(is_archived, false)   = false
      AND deleted_at                     IS NULL
    LIMIT 1;

    IF v_vacancy_id IS NULL THEN
      v_vcode        := public.generate_vcode_for_account(v_account.id);
      v_reused_vcode := false;

      INSERT INTO public.vacancies (
        vcode, account, position, status,
        account_id, store_id, position_id, group_id,
        area_name, store_name, vacant_date,
        required_headcount, source_plantilla_id,
        vacancy_type, employment_type, urgency_level,
        target_fill_date, triggered_by_user_id, triggered_by_name,
        hrco_user_id, hrco_name,
        source, source_headcount_request_id,
        area_city, province, store_branch,
        chain, chain_id,
        created_by, updated_by
      ) VALUES (
        v_vcode, v_account.account_name, v_position.position_name, 'Open',
        v_account.id, v_store_id, v_position.id, v_group_id,
        COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
        v_store_name,
        COALESCE(v_req.vacant_date, CURRENT_DATE),
        v_count,
        NULL,
        CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
        v_req.employment_type, v_req.urgency, v_req.target_fill_date,
        v_triggered_by_id, v_triggered_by_name,
        v_hrco_user_id, v_hrco_name,
        'hc_request', p_request_id,
        COALESCE(v_store.area_city, v_req.city_municipality),
        COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
        v_store.store_branch,
        v_group_name, v_group_id,
        v_triggered_by_id, v_triggered_by_id
      ) RETURNING id INTO v_vacancy_id;

      -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
      IF v_store_id IS NOT NULL THEN
        UPDATE public.stores
        SET vcode = v_vcode
        WHERE id = v_store_id
          AND (vcode IS NULL OR trim(vcode) = '');
      END IF;
    ELSE
      UPDATE public.vacancies
      SET required_headcount = required_headcount + v_count,
          updated_by         = v_triggered_by_id,
          updated_at         = NOW()
      WHERE id = v_vacancy_id;
    END IF;

  ELSE
    v_vcode := public.generate_vcode_for_account(v_account.id);

    INSERT INTO public.vacancies (
      vcode, account, position, status,
      account_id, store_id, position_id, group_id,
      area_name, store_name, vacant_date,
      required_headcount, source_plantilla_id,
      vacancy_type, employment_type, urgency_level,
      target_fill_date, triggered_by_user_id, triggered_by_name,
      hrco_user_id, hrco_name,
      source, source_headcount_request_id,
      area_city, province, store_branch,
      chain, chain_id,
      created_by, updated_by
    ) VALUES (
      v_vcode, v_account.account_name, v_position.position_name, 'Open',
      v_account.id, v_store_id, v_position.id, v_group_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_store_name,
      COALESCE(v_req.vacant_date, CURRENT_DATE),
      v_count,
      NULL,
      CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
      v_req.employment_type, v_req.urgency, v_req.target_fill_date,
      v_triggered_by_id, v_triggered_by_name,
      v_hrco_user_id, v_hrco_name,
      'hc_request', p_request_id,
      COALESCE(v_store.area_city, v_req.city_municipality),
      COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
      v_store.store_branch,
      v_group_name, v_group_id,
      v_triggered_by_id, v_triggered_by_id
    ) RETURNING id INTO v_vacancy_id;

    -- Sync this new VCode to public.stores.vcode (fix: ohm#9x4p2k7q)
    IF v_store_id IS NOT NULL THEN
      UPDATE public.stores
      SET vcode = v_vcode
      WHERE id = v_store_id
        AND (vcode IS NULL OR trim(vcode) = '');
    END IF;
  END IF;

  v_vcodes := ARRAY[v_vcode];

  -- ── Plantilla (VACANT SLOT) rows ──
  FOR i IN 1..v_count LOOP
    INSERT INTO public.plantilla (
      employee_name, employee_no,
      account, status, vcode, position,
      account_id, store_id, area, position_id,
      store_name, deployment_type,
      source_headcount_request_id,
      chain_id,
      created_by, updated_by, tagged_at
    ) VALUES (
      '(VACANT SLOT)', '(PENDING)',
      v_account.account_name, 'Inactive', v_vcode, v_position.position_name,
      v_account.id, v_store_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_position.id,
      v_store_name, v_req.employment_type,
      p_request_id,
      v_group_id,
      v_triggered_by_id, v_triggered_by_id, CURRENT_DATE
    ) RETURNING id INTO v_plantilla_id;

    IF v_first_plantilla_id IS NULL THEN
      v_first_plantilla_id := v_plantilla_id;
    END IF;
  END LOOP;

  -- Link vacancy back to first plantilla if this was a new vacancy
  IF NOT v_reused_vcode THEN
    UPDATE public.vacancies
    SET source_plantilla_id = v_first_plantilla_id,
        updated_by          = v_triggered_by_id
    WHERE id = v_vacancy_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.plantilla_slots
    WHERE legacy_vcode = v_vcode
    LIMIT 1
  ) THEN
    UPDATE public.plantilla_slots
    SET source_hc_request_id = p_request_id,
        updated_by           = v_triggered_by_id,
        updated_at           = now()
    WHERE legacy_vcode = v_vcode
      AND source_hc_request_id IS NULL;

    v_slot_result := jsonb_build_object(
      'ok',      true,
      'adopted', true,
      'hint',    'slots created by trg_auto_create_vacancy_slot; linked to HC request'
    );
  ELSE
    v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count, v_vcode);
  END IF;

  UPDATE public.headcount_requests
  SET status                  = 'completed',
      vacancy_created         = true,
      slot_created_by_user_id = v_triggered_by_id,
      slot_created_at         = NOW(),
      created_plantilla_id    = v_first_plantilla_id,
      created_vcode           = v_vcode,
      created_vcodes          = v_vcodes
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',                true,
    'request_id',        p_request_id,
    'headcount_created', v_count,
    'workforce_type',    'stationary',
    'vcode_count',       1,
    'vcodes',            v_vcodes,
    'vacancy_created',   true,
    'reused_vcode',      v_reused_vcode,
    'slot_result',       v_slot_result
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_vacancy_request(p_account_id uuid, p_store_id uuid, p_position_id uuid, p_vacancy_type text DEFAULT 'New'::text, p_required_headcount integer DEFAULT 1, p_vacant_date date DEFAULT NULL::date, p_remarks text DEFAULT NULL::text, p_source_plantilla_id uuid DEFAULT NULL::uuid, p_has_penalty boolean DEFAULT false, p_penalty_amount numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := get_my_profile_id();
  v_role       text := get_my_role();
  v_role_lvl   int  := get_my_role_level();
  v_account    record;
  v_store      record;
  v_position   record;
  v_new_id     uuid;
  v_dup_id     uuid;
  v_plant      record;
BEGIN
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  IF v_role_lvl < 30 OR v_role IN ('Viewer','Back Office') THEN
    RAISE EXCEPTION 'Role % cannot create vacancies', v_role USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_account_scope(p_account_id) THEN
    RAISE EXCEPTION 'Account % is outside your scope', p_account_id USING ERRCODE = '42501';
  END IF;

  SELECT a.* INTO v_account FROM public.accounts a WHERE a.id = p_account_id;
  IF NOT FOUND OR v_account.is_active IS NOT TRUE THEN
    RAISE EXCEPTION 'Account not found or inactive: %', p_account_id;
  END IF;

  SELECT s.* INTO v_store FROM public.stores s WHERE s.id = p_store_id;
  IF NOT FOUND OR COALESCE(v_store.is_active, true) = false THEN
    RAISE EXCEPTION 'Store not found or inactive: %', p_store_id;
  END IF;
  IF v_store.account_id IS NOT NULL AND v_store.account_id <> p_account_id THEN
    RAISE EXCEPTION 'Store % does not belong to account %', p_store_id, p_account_id;
  END IF;

  SELECT pos.* INTO v_position FROM public.positions pos WHERE pos.id = p_position_id;
  IF NOT FOUND OR COALESCE(v_position.is_active, true) = false THEN
    RAISE EXCEPTION 'Position not found or inactive: %', p_position_id;
  END IF;

  -- Plantilla integrity (if creating from existing slot)
  IF p_source_plantilla_id IS NOT NULL THEN
    SELECT pl.* INTO v_plant FROM public.plantilla pl WHERE pl.id = p_source_plantilla_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Source plantilla not found: %', p_source_plantilla_id;
    END IF;
    IF v_plant.account_id IS NOT NULL AND v_plant.account_id <> p_account_id THEN
      RAISE EXCEPTION 'Source plantilla account mismatch';
    END IF;
    IF v_plant.store_id IS NOT NULL AND v_plant.store_id <> p_store_id THEN
      RAISE EXCEPTION 'Source plantilla store mismatch';
    END IF;
    IF v_plant.position_id IS NOT NULL AND v_plant.position_id <> p_position_id THEN
      RAISE EXCEPTION 'Source plantilla position mismatch';
    END IF;
  END IF;

  -- Duplicate active vacancy guard
  SELECT v.id INTO v_dup_id
  FROM public.vacancies v
  WHERE v.store_id = p_store_id
    AND v.position_id = p_position_id
    AND v.status IN ('Draft','Pending Approval','Open','On Hold')
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
  LIMIT 1;

  IF v_dup_id IS NOT NULL THEN
    RAISE EXCEPTION 'Duplicate active vacancy already exists for this store/position (id=%)', v_dup_id
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO public.vacancies (
    account_id, store_id, position_id,
    account, store_name, position,
    vacancy_type, required_headcount, vacant_date,
    remarks, source_plantilla_id,
    has_penalty, penalty_amount,
    status, requested_by_user_id, created_by, created_by_user_id, requested_date
  ) VALUES (
    p_account_id, p_store_id, p_position_id,
    v_account.account_name, v_store.store_name, v_position.position_name,
    COALESCE(p_vacancy_type,'New'), GREATEST(p_required_headcount,1), p_vacant_date,
    p_remarks, p_source_plantilla_id,
    COALESCE(p_has_penalty,false), p_penalty_amount,
    'Draft', v_profile_id, v_profile_id, v_profile_id, CURRENT_DATE
  )
  RETURNING id INTO v_new_id;

  PERFORM public.log_audit_event(
    'vacancies', 'INSERT', v_new_id, NULL,
    jsonb_build_object('semantic_action','CREATE_VACANCY_REQUEST',
                       'actor_role', v_role,
                       'account_id', p_account_id,
                       'store_id',   p_store_id,
                       'position_id', p_position_id)
  );
  RETURN v_new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_approve_applicant_profile_edit_request(p_request_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_req        public.applicant_profile_edit_requests%ROWTYPE;
  v_app        public.applicants%ROWTYPE;
  v_changed    jsonb := '{}';
  -- computed new full_name parts (resolved after applying overrides)
  v_new_last   text;
  v_new_first  text;
  v_new_middle text;
BEGIN
  -- RBAC: Encoder | Head Admin | Super Admin
  IF NOT (
    v_level IN (30, 90, 100)
    OR public.i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required to approve profile corrections'
      USING ERRCODE = '42501';
  END IF;

  -- Fetch and lock request
  SELECT * INTO v_req
    FROM public.applicant_profile_edit_requests
   WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile edit request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status != 'Pending' THEN
    RAISE EXCEPTION 'request is not Pending (current status: %)', v_req.status
      USING ERRCODE = '22023';
  END IF;

  -- Fetch current applicant values
  SELECT * INTO v_app FROM public.applicants WHERE id = v_req.applicant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found', v_req.applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Scope check for Encoder (not full-access)
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Build changed_fields audit payload
  IF v_req.new_last_name IS NOT NULL
     AND v_req.new_last_name IS DISTINCT FROM v_app.last_name THEN
    v_changed := v_changed || jsonb_build_object('last_name',
      jsonb_build_object('old', v_app.last_name, 'new', v_req.new_last_name));
  END IF;
  IF v_req.new_first_name IS NOT NULL
     AND v_req.new_first_name IS DISTINCT FROM v_app.first_name THEN
    v_changed := v_changed || jsonb_build_object('first_name',
      jsonb_build_object('old', v_app.first_name, 'new', v_req.new_first_name));
  END IF;
  IF v_req.new_middle_name IS NOT NULL
     AND v_req.new_middle_name IS DISTINCT FROM v_app.middle_name THEN
    v_changed := v_changed || jsonb_build_object('middle_name',
      jsonb_build_object('old', v_app.middle_name, 'new', v_req.new_middle_name));
  END IF;
  IF v_req.new_contact_number IS NOT NULL
     AND v_req.new_contact_number IS DISTINCT FROM v_app.contact_number THEN
    v_changed := v_changed || jsonb_build_object('contact_number',
      jsonb_build_object('old', v_app.contact_number, 'new', v_req.new_contact_number));
  END IF;

  -- Resolve final name parts (for full_name rebuild)
  v_new_last   := COALESCE(v_req.new_last_name,   v_app.last_name);
  v_new_first  := COALESCE(v_req.new_first_name,  v_app.first_name);
  v_new_middle := COALESCE(v_req.new_middle_name, v_app.middle_name);

  -- Apply field changes to applicant record
  UPDATE public.applicants
  SET
    last_name      = COALESCE(v_req.new_last_name,      last_name),
    first_name     = COALESCE(v_req.new_first_name,     first_name),
    middle_name    = COALESCE(v_req.new_middle_name,    middle_name),
    contact_number = COALESCE(v_req.new_contact_number, contact_number),
    full_name      = TRIM(
                       v_new_last || ', ' || v_new_first
                       || CASE WHEN v_new_middle IS NOT NULL
                               THEN ' ' || v_new_middle
                               ELSE '' END
                     ),
    updated_at     = NOW(),
    updated_by     = v_profile_id
  WHERE id = v_req.applicant_id;

  -- Mark request Approved
  UPDATE public.applicant_profile_edit_requests
  SET
    status           = 'Approved',
    reviewed_by      = v_profile_id,
    reviewed_at      = NOW(),
    reviewer_remarks = p_remarks,
    updated_at       = NOW()
  WHERE id = p_request_id;

  -- Write immutable change history
  IF v_changed != '{}' THEN
    INSERT INTO public.applicant_profile_change_history (
      applicant_id,
      request_id,
      changed_fields,
      changed_by,
      approved_by,
      reason,
      changed_at,
      source_module
    ) VALUES (
      v_req.applicant_id,
      p_request_id,
      v_changed,
      v_req.requested_by,
      v_profile_id,
      v_req.reason,
      NOW(),
      'vacancy'
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_approve_plantilla_additional_store(p_applicant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role         text  := public.get_my_role();
  v_role_level   int   := COALESCE(public.get_my_role_level(), 0);
  v_profile_id   uuid  := public.get_my_profile_id();
  v_auth_user_id uuid  := auth.uid();
  v_app          public.applicants%ROWTYPE;
  v_linked_plt   public.plantilla%ROWTYPE;
  v_vac          public.vacancies%ROWTYPE;
  v_new_esa_id   uuid;
  v_target_vcode text;
BEGIN
  IF v_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'authenticated user required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.i_have_full_access()
    OR v_role_level IN (30, 90, 100)
    OR public.i_am_ops()
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team or Data Team required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.applicant_source, 'manual') <> 'plantilla' THEN
    RAISE EXCEPTION
      'applicant % is not a plantilla-sourced applicant (source=%)',
      p_applicant_id, COALESCE(v_app.applicant_source, 'manual')
      USING ERRCODE = '22023';
  END IF;

  IF v_app.linked_plantilla_id IS NULL THEN
    RAISE EXCEPTION
      'applicant % has applicant_source=plantilla but no linked_plantilla_id',
      p_applicant_id
      USING ERRCODE = '22023';
  END IF;

  IF v_app.status = 'Confirmed Onboard' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'applicant_id', v_app.id,
      'applicant_status', v_app.status,
      'vcode', v_app.vacancy_vcode,
      'idempotent', true
    );
  END IF;

  SELECT * INTO v_linked_plt
    FROM public.plantilla
   WHERE id = v_app.linked_plantilla_id
     AND COALESCE(is_deleted, false) = false
     AND COALESCE(is_archived, false) = false
     AND status IN ('Active', 'For Deactivation', 'On Leave')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'linked plantilla employee % not found or not active',
      v_app.linked_plantilla_id USING ERRCODE = 'P0002';
  END IF;

  IF v_linked_plt.employee_no IS NULL OR btrim(v_linked_plt.employee_no) = '' THEN
    RAISE EXCEPTION 'linked plantilla employee has no employee_no'
      USING ERRCODE = '22023';
  END IF;

  v_target_vcode := v_app.vacancy_vcode;

  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_target_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'active vacancy not found for vcode %', v_target_vcode
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_vac.has_pending_closure, false) = true THEN
    RAISE EXCEPTION
      'onboarding blocked: vacancy % has a pending closure request',
      v_target_vcode USING ERRCODE = '55000';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.employee_store_allocations
     WHERE plantilla_id = v_linked_plt.id
       AND vcode = v_target_vcode
       AND is_active = true
       AND effective_end IS NULL
  ) THEN
    RAISE EXCEPTION
      'employee % already has an active store allocation for VCODE %',
      v_linked_plt.employee_no, v_target_vcode
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.employee_store_allocations (
    plantilla_id,
    employee_no,
    store_id,
    store_name,
    vcode,
    account_id,
    group_id,
    filled_hc,
    active_store_count,
    effective_start,
    effective_end,
    is_active,
    created_by,
    created_at
  )
  VALUES (
    v_linked_plt.id,
    v_linked_plt.employee_no,
    v_vac.store_id,
    v_vac.store_name,
    v_target_vcode,
    v_vac.account_id,
    v_vac.chain_id,
    1.0,
    1,
    CURRENT_DATE,
    NULL,
    true,
    v_profile_id,
    NOW()
  )
  RETURNING id INTO v_new_esa_id;

  PERFORM public.fn_sync_slot_to_occupied(
    p_vcode        => v_target_vcode,
    p_hr_emploc_id => NULL,
    p_plantilla_id => v_linked_plt.id,
    p_performed_by => v_profile_id,
    p_source_fn    => 'fn_approve_plantilla_additional_store'
  );

  IF v_vac.id IS NOT NULL THEN
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_profile_id
     WHERE id = v_vac.id
       AND NOT EXISTS (
         SELECT 1
           FROM public.plantilla_slots ps
          WHERE ps.legacy_vcode = v_target_vcode
            AND COALESCE(ps.is_roving, false) = false
            AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
       );
  END IF;

  UPDATE public.vacancies
     SET status     = 'Filled',
         updated_at = NOW(),
         updated_by = v_profile_id
   WHERE vcode = v_target_vcode
     AND status IN ('Open', 'For Sourcing')
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
     AND NOT EXISTS (
       SELECT 1
         FROM public.plantilla_slots ps
        WHERE ps.legacy_vcode = v_target_vcode
          AND COALESCE(ps.is_roving, false) = false
          AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
     );

  UPDATE public.applicants
     SET status     = 'Confirmed Onboard',
         hired_date = COALESCE(hired_date, CURRENT_DATE),
         updated_at = NOW(),
         updated_by = v_profile_id
   WHERE id = p_applicant_id;

  INSERT INTO public.audit_logs (
    actor_id, module, action, record_id, new_data, role
  ) VALUES (
    v_auth_user_id,
    'Plantilla',
    'INSERT',
    v_new_esa_id,
    jsonb_build_object(
      'business_action', 'PLANTILLA_ADDITIONAL_STORE_ESA',
      'employee_no', v_linked_plt.employee_no,
      'target_vcode', v_target_vcode,
      'source_plantilla_id', v_app.linked_plantilla_id,
      'applicant_id', p_applicant_id,
      'new_esa_id', v_new_esa_id,
      'target_store_id', v_vac.store_id,
      'target_store_name', v_vac.store_name,
      'label', 'Additional store assignment created'
    ),
    v_role
  );

  RETURN jsonb_build_object(
    'ok', true,
    'applicant_id', p_applicant_id,
    'applicant_status', 'Confirmed Onboard',
    'new_esa_id', v_new_esa_id,
    'source_plantilla_id', v_linked_plt.id,
    'vcode', v_target_vcode,
    'employee_no', v_linked_plt.employee_no,
    'idempotent', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_archive_all_operational_data(p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id          uuid;
  v_caller_name        text;
  v_batch_id           uuid := gen_random_uuid();
  v_now                timestamptz := now();
  v_plantilla_count    integer := 0;
  v_vacancy_count      integer := 0;
  v_hr_emploc_count    integer := 0;
  v_slots_count        integer := 0;
  v_hc_count           integer := 0;
  v_assign_count       integer := 0;
  v_slot_review_count  integer := 0;
  v_req_item_count     integer := 0;
  v_request_count      integer := 0;
  v_coverage_count     integer := 0;
  v_pool_slot_count    integer := 0;
  v_moses_hq_count     integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'archive_reason must be at least 10 characters' USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();

  -- MODULE 1: PLANTILLA
  UPDATE public.plantilla
  SET is_archived = true, archived_at = v_now, archived_by = v_caller_id, archive_reason = p_reason,
      qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE is_deleted = false AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

  -- MODULE 2: VACANCIES (all, incl. pool vacancies)
  UPDATE public.vacancies
  SET is_archived = true, archived_at = v_now, archived_by_id = v_caller_id, archived_by = v_caller_name,
      archive_reason = p_reason, status = 'Archived', qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE deleted_at IS NULL AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

  -- MODULE 3: HR EMPLOC
  UPDATE public.hr_emploc
  SET deleted_at = v_now, qa_archived_at = v_now, qa_archived_by = v_caller_id,
      qa_archive_reason = p_reason, qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_hr_emploc_count = ROW_COUNT;

  -- MODULE 4: PLANTILLA SLOTS
  UPDATE public.plantilla_slots
  SET slot_status = 'closed', closed_at = v_now, closed_by = v_caller_id,
      closure_reason_code = 'QA_RESET', qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE slot_status <> 'closed';
  GET DIAGNOSTICS v_slots_count = ROW_COUNT;

  -- MODULE 5: HEADCOUNT REQUESTS
  UPDATE public.headcount_requests
  SET is_archived = true, archived_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now
  WHERE is_archived = false;
  GET DIAGNOSTICS v_hc_count = ROW_COUNT;

  -- MODULE 6: MOSES HQ (pool vacancies already archived in MODULE 2)
  UPDATE public.workforce_assignments
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  UPDATE public.workforce_slot_reviews
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  UPDATE public.workforce_pool_request_items
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  UPDATE public.workforce_pool_requests
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  UPDATE public.vacancy_coverage
  SET archived_at = v_now, archived_by = v_caller_id, qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  UPDATE public.workforce_pool_slots
  SET is_active = false, deleted_at = v_now, qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE is_active = true AND deleted_at IS NULL;
  GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

  v_moses_hq_count := v_assign_count + v_slot_review_count + v_req_item_count
                    + v_request_count + v_coverage_count + v_pool_slot_count;

  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, moses_hq_count, status)
  VALUES
    (v_batch_id, 'qa_reset', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72),
     v_plantilla_count, v_vacancy_count, v_hr_emploc_count, v_moses_hq_count, 'ACTIVE');

  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('qa_reset_enterprise', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id', v_batch_id, 'action_type', 'qa_reset',
       'executed_by', v_caller_id, 'executed_at', v_now, 'reason', p_reason,
       'plantilla_count', v_plantilla_count, 'vacancy_count', v_vacancy_count,
       'hr_emploc_count', v_hr_emploc_count, 'slots_count', v_slots_count,
       'headcount_request_count', v_hc_count,
       'moses_hq_assignment_count', v_assign_count, 'moses_hq_slot_review_count', v_slot_review_count,
       'moses_hq_req_item_count', v_req_item_count, 'moses_hq_request_count', v_request_count,
       'moses_hq_coverage_count', v_coverage_count, 'moses_hq_pool_slot_count', v_pool_slot_count,
       'moses_hq_count', v_moses_hq_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id', v_batch_id, 'plantilla_count', v_plantilla_count,
    'vacancy_count', v_vacancy_count, 'hr_emploc_count', v_hr_emploc_count,
    'slots_count', v_slots_count, 'headcount_request_count', v_hc_count,
    'moses_hq_count', v_moses_hq_count, 'moses_hq_assignment_count', v_assign_count,
    'moses_hq_request_count', v_request_count, 'moses_hq_pool_slot_count', v_pool_slot_count,
    'executed_by', v_caller_id, 'executed_at', v_now
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_archive_moses_hq_data(p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id          uuid;
  v_caller_name        text;
  v_batch_id           uuid := gen_random_uuid();
  v_now                timestamptz := now();
  v_assign_count       integer := 0;
  v_slot_review_count  integer := 0;
  v_req_item_count     integer := 0;
  v_request_count      integer := 0;
  v_coverage_count     integer := 0;
  v_slot_count         integer := 0;
  v_pool_vacancy_count integer := 0;
  v_moses_hq_count     integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'archive_reason must be at least 10 characters'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();

  UPDATE public.workforce_assignments
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  UPDATE public.workforce_slot_reviews
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  UPDATE public.workforce_pool_request_items
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  UPDATE public.workforce_pool_requests
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  UPDATE public.vacancy_coverage
  SET archived_at = v_now, archived_by = v_caller_id, qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  UPDATE public.workforce_pool_slots
  SET is_active = false, deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE is_active = true AND deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_count = ROW_COUNT;

  UPDATE public.vacancies
  SET is_archived = true, archived_at = v_now, archived_by_id = v_caller_id, archived_by = v_caller_name,
      archive_reason = p_reason, status = 'Archived', qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE is_pool_vacancy = true AND deleted_at IS NULL AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_pool_vacancy_count = ROW_COUNT;

  v_moses_hq_count := v_assign_count + v_slot_review_count + v_req_item_count
                    + v_request_count + v_coverage_count + v_slot_count + v_pool_vacancy_count;

  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, moses_hq_count, status)
  VALUES
    (v_batch_id, 'moses_hq', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72), 0, 0, 0, v_moses_hq_count, 'ACTIVE');

  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('moses_hq_archive', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id', v_batch_id, 'action_type', 'moses_hq',
       'executed_by', v_caller_id, 'executed_at', v_now, 'reason', p_reason,
       'assignment_count', v_assign_count, 'slot_review_count', v_slot_review_count,
       'request_item_count', v_req_item_count, 'request_count', v_request_count,
       'coverage_count', v_coverage_count, 'slot_count', v_slot_count,
       'pool_vacancy_count', v_pool_vacancy_count, 'moses_hq_count', v_moses_hq_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id', v_batch_id, 'moses_hq_count', v_moses_hq_count,
    'assignment_count', v_assign_count, 'slot_review_count', v_slot_review_count,
    'request_item_count', v_req_item_count, 'request_count', v_request_count,
    'coverage_count', v_coverage_count, 'slot_count', v_slot_count,
    'pool_vacancy_count', v_pool_vacancy_count, 'executed_by', v_caller_id, 'executed_at', v_now
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_archive_plantilla_data(p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id          uuid;
  v_caller_name        text;
  v_batch_id           uuid := gen_random_uuid();
  v_now                timestamptz := now();
  v_plantilla_count    integer := 0;
  v_slots_count        integer := 0;
  v_assign_count       integer := 0;
  v_slot_review_count  integer := 0;
  v_req_item_count     integer := 0;
  v_request_count      integer := 0;
  v_coverage_count     integer := 0;
  v_pool_slot_count    integer := 0;
  v_pool_vacancy_count integer := 0;
  v_moses_hq_count     integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'archive_reason must be at least 10 characters' USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();

  UPDATE public.plantilla
  SET is_archived = true, archived_at = v_now, archived_by = v_caller_id, archive_reason = p_reason,
      qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE is_deleted = false AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

  UPDATE public.plantilla_slots
  SET slot_status = 'closed', closed_at = v_now, closed_by = v_caller_id,
      closure_reason_code = 'QA_RESET', qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE slot_status <> 'closed';
  GET DIAGNOSTICS v_slots_count = ROW_COUNT;

  -- CASCADE: Moses HQ
  UPDATE public.workforce_assignments
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  UPDATE public.workforce_slot_reviews
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  UPDATE public.workforce_pool_request_items
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  UPDATE public.workforce_pool_requests
  SET deleted_at = v_now, qa_archive_batch_id = v_batch_id, updated_at = v_now, updated_by = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  UPDATE public.vacancy_coverage
  SET archived_at = v_now, archived_by = v_caller_id, qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  UPDATE public.workforce_pool_slots
  SET is_active = false, deleted_at = v_now, qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE is_active = true AND deleted_at IS NULL;
  GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

  UPDATE public.vacancies
  SET is_archived = true, archived_at = v_now, archived_by_id = v_caller_id, archived_by = v_caller_name,
      archive_reason = p_reason, status = 'Archived', qa_archive_batch_id = v_batch_id,
      updated_at = v_now, updated_by = v_caller_id
  WHERE is_pool_vacancy = true AND deleted_at IS NULL AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_pool_vacancy_count = ROW_COUNT;

  v_moses_hq_count := v_assign_count + v_slot_review_count + v_req_item_count
                    + v_request_count + v_coverage_count + v_pool_slot_count + v_pool_vacancy_count;

  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, moses_hq_count, status)
  VALUES
    (v_batch_id, 'plantilla', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72), v_plantilla_count, 0, 0, v_moses_hq_count, 'ACTIVE');

  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('plantilla_archive', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id', v_batch_id, 'action_type', 'plantilla',
       'executed_by', v_caller_id, 'executed_at', v_now, 'reason', p_reason,
       'plantilla_count', v_plantilla_count, 'slots_count', v_slots_count,
       'moses_hq_cascade', true, 'assignment_count', v_assign_count,
       'slot_review_count', v_slot_review_count, 'request_item_count', v_req_item_count,
       'request_count', v_request_count, 'coverage_count', v_coverage_count,
       'pool_slot_count', v_pool_slot_count, 'pool_vacancy_count', v_pool_vacancy_count,
       'moses_hq_count', v_moses_hq_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id', v_batch_id, 'plantilla_count', v_plantilla_count,
    'slots_count', v_slots_count, 'moses_hq_count', v_moses_hq_count,
    'assignment_count', v_assign_count, 'slot_review_count', v_slot_review_count,
    'request_item_count', v_req_item_count, 'request_count', v_request_count,
    'coverage_count', v_coverage_count, 'pool_slot_count', v_pool_slot_count,
    'pool_vacancy_count', v_pool_vacancy_count, 'executed_by', v_caller_id, 'executed_at', v_now
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_assert_applicant_no_cross_account_active()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_account_id   uuid;
  v_last         text;
  v_first        text;
  v_contact      text;
  v_conflict_acc text;
BEGIN
  -- Only enforce when the resulting row is an ACTIVE, non-archived applicant.
  IF COALESCE(NEW.is_archived, false) = true
     OR NOT public.fn_is_active_vacancy_applicant_status(NEW.status) THEN
    RETURN NEW;
  END IF;

  -- Normalise identity components.
  v_last    := lower(btrim(COALESCE(NEW.last_name, '')));
  v_first   := lower(btrim(COALESCE(NEW.first_name, '')));
  v_contact := btrim(COALESCE(NEW.contact_number, ''));

  -- Incomplete identity -> cannot reliably match a person -> skip.
  IF v_last = '' OR v_first = '' OR v_contact = '' THEN
    RETURN NEW;
  END IF;

  -- Resolve this applicant's account via the vacancy.
  SELECT v.account_id
    INTO v_account_id
  FROM public.vacancies v
  WHERE v.vcode = NEW.vacancy_vcode
    AND v.deleted_at IS NULL
  LIMIT 1;

  -- No resolvable account -> cannot compare across accounts -> skip.
  IF v_account_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Look for an active applicant with the same identity bound to a
  -- DIFFERENT account.
  SELECT v2.account
    INTO v_conflict_acc
  FROM public.applicants a2
  JOIN public.vacancies v2 ON v2.vcode = a2.vacancy_vcode
  WHERE a2.id <> NEW.id
    AND v2.deleted_at IS NULL
    AND v2.account_id IS NOT NULL
    AND v2.account_id IS DISTINCT FROM v_account_id
    AND COALESCE(a2.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a2.status)
    AND lower(btrim(COALESCE(a2.last_name, '')))  = v_last
    AND lower(btrim(COALESCE(a2.first_name, ''))) = v_first
    AND btrim(COALESCE(a2.contact_number, ''))    = v_contact
  ORDER BY a2.created_at
  LIMIT 1;

  IF v_conflict_acc IS NOT NULL THEN
    RAISE EXCEPTION
      'Applicant already has an active application under another account.'
      USING
        DETAIL  = format('Conflicting account: %s', v_conflict_acc),
        ERRCODE = '23505';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_assert_freeze_inactive(p_freeze_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.fn_check_freeze_active(p_freeze_key) THEN
    IF public.fn_check_freeze_active('read_only_emergency') THEN
      RAISE EXCEPTION 'System is in Read-Only Emergency Mode. Operations are temporarily suspended.'
        USING ERRCODE = 'P0001';
    ELSIF p_freeze_key = 'recruitment_freeze' THEN
      RAISE EXCEPTION 'Recruitment operations are temporarily frozen by System Administration.'
        USING ERRCODE = 'P0001';
    ELSIF p_freeze_key = 'audit_freeze' THEN
      RAISE EXCEPTION 'Audit-sensitive operations are temporarily frozen by System Administration.'
        USING ERRCODE = 'P0001';
    ELSE
      RAISE EXCEPTION 'This operation is suspended due to an active %.', replace(p_freeze_key, '_', ' ')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_assert_governance_enabled(p_control_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.fn_check_governance_control(p_control_key) THEN
    RAISE EXCEPTION 'This feature is currently disabled by System Administration.'
      USING ERRCODE = 'P0001';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_assert_risk_control_enabled(p_control_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.fn_check_governance_control(p_control_key) THEN
    RAISE EXCEPTION 'This capability is currently restricted by System Administration.'
      USING ERRCODE = 'P0001';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_assert_vacancy_edit_allowed_op(p_op text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_is_locked       boolean;
  v_override_active boolean;
  v_role            text;
  v_user_id         uuid;
BEGIN
  v_is_locked := public.is_vacancy_edit_locked();
  IF NOT v_is_locked THEN
    RETURN; -- system is fully open — allow all
  END IF;

  -- When an admin override is active the scheduled lock window is lifted for
  -- ALL roles. Normal Vacancy RBAC (RLS + mutating RPC guards) remains the only
  -- gate. The lock itself must not be the barrier.
  SELECT COALESCE(l.is_override_active, false)
  INTO   v_override_active
  FROM   public.vacancy_edit_locks l
  WHERE  l.id = 1;

  IF v_override_active THEN
    RETURN; -- override active: lock enforcement bypassed, normal RBAC applies
  END IF;

  -- Lock is active and no override — apply role-based rules.
  v_role    := public.get_effective_role();
  v_user_id := public.get_current_profile_id();

  -- Super Admin and Head Admin bypass all operations (audit logged).
  IF v_role IN ('Super Admin', 'Head Admin') THEN
    INSERT INTO public.vacancy_edit_lock_audit (
      action_type, actor_user_id, actor_role, reason, previous_state, new_state
    ) VALUES (
      'override',
      v_user_id,
      v_role,
      v_role || ' mutation bypass during active lock (op=' || p_op || ')',
      NULL,
      NULL
    );
    RETURN;
  END IF;

  -- Encoder bypasses INSERT only (VCODE creation via SECURITY DEFINER RPCs).
  IF v_role = 'Encoder' AND p_op = 'INSERT' THEN
    RETURN;
  END IF;

  -- All other roles / operations are blocked while locked.
  RAISE EXCEPTION 'Vacancy edits are currently locked. Non-admin edits are prohibited.'
    USING ERRCODE = '42501';
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bind_applicant_to_coverage_group(p_applicant_id uuid, p_coverage_group_id uuid, p_performed_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app          public.applicants%ROWTYPE;
  v_grp          public.coverage_groups%ROWTYPE;
  v_claimed_slot uuid;
  v_claimed_ord  integer;
  v_open_cnt     bigint;
  v_actor        uuid := COALESCE(p_performed_by, public.get_my_profile_id());
  v_slot_result  jsonb;
BEGIN
  -- Allow: Super Admin, Head Admin (i_have_full_access),
  --        Ops roles om/hrco/atl/tl (i_am_ops),
  --        Recruitment / Recruitment Team (i_am_recruitment).
  IF NOT (
    public.i_have_full_access()
    OR public.i_am_ops()
    OR public.i_am_recruitment()
  ) THEN
    RAISE EXCEPTION 'forbidden: insufficient role to bind applicants' USING ERRCODE = '42501';
  END IF;

  -- ── Resolve + scope the coverage group ────────────────────────────────────
  SELECT * INTO v_grp
    FROM public.coverage_groups
   WHERE id = p_coverage_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_grp.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'coverage group is archived' USING ERRCODE = 'P0001';
  END IF;

  -- ── Scope check ───────────────────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_grp.account_id = ANY (public.get_my_allowed_account_ids())) THEN
      RAISE EXCEPTION 'forbidden: coverage group account outside caller scope' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Lock + validate the applicant ─────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Mutual exclusivity (plan Q9): a stationary applicant cannot take a coverage slot.
  IF v_app.slot_id IS NOT NULL THEN
    RAISE EXCEPTION
      'applicant % is stationary (slot_id set) — cannot bind to a coverage slot',
      p_applicant_id USING ERRCODE = 'P0001';
  END IF;
  IF v_app.coverage_slot_id IS NOT NULL THEN
    RAISE EXCEPTION
      'applicant % is already bound to coverage_slot %',
      p_applicant_id, v_app.coverage_slot_id USING ERRCODE = 'P0001';
  END IF;

  -- ── Claim the lowest-ordinal open coverage slot (Q1/Q2/Q3) ────────────────
  SELECT id, slot_ordinal
    INTO v_claimed_slot, v_claimed_ord
    FROM public.coverage_slots
   WHERE coverage_group_id = v_grp.id
     AND slot_status       = 'open'
   ORDER BY slot_ordinal ASC, created_at ASC, id ASC
   LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_claimed_slot IS NULL THEN
    SELECT COUNT(*) INTO v_open_cnt
      FROM public.coverage_slots
     WHERE coverage_group_id = v_grp.id;
    RAISE EXCEPTION
      'no_open_coverage_slot: CGCODE % has % slot(s) but none are open. '
      'All headcount is in pipeline, processing, filled, or closed. '
      'Increase required headcount before adding another applicant.',
      v_grp.coverage_code, v_open_cnt
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Bind BOTH FK columns in one statement (Q1) ────────────────────────────
  UPDATE public.applicants
     SET coverage_slot_id  = v_claimed_slot,
         coverage_group_id = v_grp.id,
         updated_at        = now(),
         updated_by        = v_actor
   WHERE id = p_applicant_id;

  -- ── Transition the exact claimed slot open → pipeline (blocking) ──────────
  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => v_claimed_slot,
    p_new_status   => 'pipeline',
    p_performed_by => v_actor,
    p_remarks      => format(
      'Phase R-B / fn_bind_applicant_to_coverage_group / CGCODE=%s / '
      'applicant=%s / slot_ordinal=%s',
      v_grp.coverage_code, p_applicant_id, v_claimed_ord
    )
  ) INTO v_slot_result;

  IF (v_slot_result->>'status') = 'blocked' THEN
    RAISE EXCEPTION
      'coverage_slot_transition_blocked: claimed slot % could not transition to '
      'pipeline — %. Resolve coverage slot status before binding.',
      v_claimed_slot, v_slot_result->>'blocked_reason'
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.log_audit_event(
    'vacancy_module', 'UPDATE', p_applicant_id,
    NULL,
    jsonb_build_object(
      'action',            'bind_applicant_to_coverage_group',
      'coverage_group_id', v_grp.id,
      'coverage_code',     v_grp.coverage_code,
      'coverage_slot_id',  v_claimed_slot,
      'slot_ordinal',      v_claimed_ord
    )
  );

  RETURN jsonb_build_object(
    'status',            'ok',
    'applicant_id',      p_applicant_id,
    'coverage_group_id', v_grp.id,
    'coverage_slot_id',  v_claimed_slot,
    'slot_ordinal',      v_claimed_ord
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cencom_deployment_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
WITH
  period AS (
    SELECT
      date_trunc('month', now())::date                         AS month_start,
      (date_trunc('month', now()) + interval '1 month')::date AS month_end
  ),
  allowed AS (
    -- Full-access users: NULL sentinel means "no filter needed".
    -- Scoped users: array of permitted account UUIDs.
    SELECT CASE
      WHEN public.i_have_full_access() THEN NULL::uuid[]
      ELSE public.get_my_allowed_account_ids()
    END AS ids
  ),
  departures AS (
    SELECT count(*) AS cnt
    FROM public.employee_deactivation_requests d
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE d.status = 'Approved'
      AND d.processed_at::date >= p.month_start
      AND d.processed_at::date <  p.month_end
      AND d.is_archived = false
      AND (sc.ids IS NULL OR d.account_id = ANY(sc.ids))
  ),
  additional_hc AS (
    SELECT count(*) AS cnt
    FROM public.headcount_requests h
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE h.status IN ('approved_pending_vcode', 'completed')
      AND COALESCE(h.head_admin_approved_at, h.reviewed_at)::date >= p.month_start
      AND COALESCE(h.head_admin_approved_at, h.reviewed_at)::date <  p.month_end
      AND COALESCE(h.is_archived, false) = false
      AND (sc.ids IS NULL OR h.account_id = ANY(sc.ids))
  ),
  deleted_vcode AS (
    SELECT count(*) AS cnt
    FROM public.vacancies v
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE COALESCE(v.archived_at, v.deleted_at)::date >= p.month_start
      AND COALESCE(v.archived_at, v.deleted_at)::date <  p.month_end
      AND (sc.ids IS NULL OR v.account_id = ANY(sc.ids))
  ),
  deployment AS (
    SELECT count(*) AS cnt
    FROM public.hr_emploc he
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE he.hired_date >= p.month_start
      AND he.hired_date <  p.month_end
      AND he.deleted_at IS NULL
      AND (sc.ids IS NULL OR he.account_id = ANY(sc.ids))
  )
SELECT jsonb_build_object(
  'total_departures', COALESCE((SELECT cnt FROM departures),   0),
  'additional_hc',    COALESCE((SELECT cnt FROM additional_hc), 0),
  'deleted_vcode',    COALESCE((SELECT cnt FROM deleted_vcode), 0),
  'deployment',       COALESCE((SELECT cnt FROM deployment),    0)
);
$function$;

CREATE OR REPLACE FUNCTION public.fn_check_freeze_active(p_freeze_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Validate key
  IF p_freeze_key NOT IN ('payroll_freeze', 'audit_freeze', 'recruitment_freeze', 'read_only_emergency') THEN
    RAISE EXCEPTION 'Invalid freeze mode key: %', p_freeze_key;
  END IF;

  -- If read_only_emergency is enabled (true), it overrides everything and returns true (freeze is active)
  IF COALESCE((SELECT enabled FROM public.governance_controls WHERE control_key = 'read_only_emergency'), false) THEN
    RETURN true;
  END IF;

  -- Otherwise check specific key state
  RETURN COALESCE((SELECT enabled FROM public.governance_controls WHERE control_key = p_freeze_key), false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_check_governance_control(p_control_key text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT enabled FROM governance_controls WHERE control_key = p_control_key),
    true  -- default to enabled if key not found (safe fallback)
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_check_vcode_applicant_slot(p_vcode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_existing record;
BEGIN
  IF nullif(btrim(p_vcode), '') IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'available', false,
      'has_active_applicant', false,
      'error', 'vcode_required'
    );
  END IF;

  SELECT
    a.id,
    a.status,
    COALESCE(
      NULLIF(a.full_name, ''),
      NULLIF(btrim(concat_ws(' ', a.first_name, a.middle_name, a.last_name)), ''),
      'Unknown'
    ) AS applicant_name
  INTO v_existing
  FROM public.applicants a
  WHERE a.vacancy_vcode = p_vcode
    AND COALESCE(a.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a.status)
  ORDER BY COALESCE(a.updated_at, a.created_at) DESC NULLS LAST, a.created_at DESC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'available', false,
      'has_active_applicant', true,
      'active_applicant_id', v_existing.id,
      'active_applicant_name', v_existing.applicant_name,
      'active_applicant_status', v_existing.status,
      'message', 'VCODE already occupied'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'available', true,
    'has_active_applicant', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_enforce_vacancy_transition()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT public.fn_is_valid_vacancy_transition(OLD.status, NEW.status) THEN
      RAISE EXCEPTION 'Invalid vacancy status transition: % -> %', OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_accounts_by_groups(p_group_ids uuid[])
 RETURNS TABLE(id uuid, account_name text, group_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT a.id, a.account_name, a.group_id
  FROM public.accounts a
  WHERE a.group_id = ANY(p_group_ids)
    AND a.is_active = TRUE
    AND a.status = 'Active'
  ORDER BY a.group_id, a.account_name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_applicant_pipeline_history(p_applicant_id uuid, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, update_type text, changed_field text, old_value text, new_value text, changed_by uuid, changed_by_name text, changed_at timestamp with time zone, changed_at_display text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_vcode      text;
BEGIN
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  -- Resolve the applicant's vacancy vcode for scope check.
  SELECT a.vacancy_vcode
  INTO   v_vcode
  FROM   public.applicants a
  WHERE  a.id = p_applicant_id
    AND  COALESCE(a.is_archived, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Non-full-access callers must own the vacancy's account.
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1
      FROM   public.vacancies v
      WHERE  v.vcode      = v_vcode
        AND  v.account    = ANY(public.get_my_allowed_accounts())
        AND  v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    h.id,
    h.update_type,
    h.changed_field,
    h.old_value,
    h.new_value,
    h.changed_by,
    h.changed_by_name,
    h.changed_at,
    TO_CHAR(
      h.changed_at AT TIME ZONE 'Asia/Manila',
      'FMMonth FMDD, YYYY FMHH12:MI AM'
    ) AS changed_at_display
  FROM   public.applicant_status_history h
  WHERE  h.applicant_id = p_applicant_id
  ORDER  BY h.changed_at DESC
  LIMIT  COALESCE(p_limit, 50);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_applicant_source_channels(p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'id',         c.id,
        'label',      c.label,
        'is_default', c.is_default,
        'sort_order', c.sort_order,
        'is_active',  c.is_active
      ) ORDER BY c.sort_order
    ), '[]'::jsonb)
    FROM public.applicant_source_channels c
    WHERE (p_include_inactive OR c.is_active = true)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_applicant_status_options(p_include_inactive boolean DEFAULT false, p_exclude_system_only boolean DEFAULT false, p_applicant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_current_status_code text;
BEGIN
  -- Resolve the applicant's current status_code when filtering.
  IF p_applicant_id IS NOT NULL THEN
    SELECT opt.status_code
    INTO   v_current_status_code
    FROM   public.applicants a
    JOIN   public.applicant_status_options opt
           ON  opt.status_code = a.status
            OR opt.label       = a.status
            OR lower(regexp_replace(opt.label, '[^a-zA-Z0-9]+', '_', 'g'))
               = lower(regexp_replace(COALESCE(a.status, ''), '[^a-zA-Z0-9]+', '_', 'g'))
    WHERE  a.id = p_applicant_id
    ORDER  BY CASE WHEN opt.status_code = a.status THEN 0 ELSE 1 END
    LIMIT  1;
    -- If the applicant is not found, v_current_status_code remains NULL
    -- and the Sourcing exclusion is skipped (safe default).
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'status_code',     s.status_code,
        'label',           s.label,
        'is_terminal',     s.is_terminal,
        'allow_on_create', s.allow_on_create,
        'is_system_only',  s.is_system_only,
        'color_key',       s.color_key,
        'sort_order',      s.sort_order,
        'is_active',       s.is_active
      ) ORDER BY s.sort_order
    ), '[]'::jsonb)
    FROM public.applicant_status_options s
    WHERE (p_include_inactive OR s.is_active = true)
      AND (NOT p_exclude_system_only OR s.is_system_only = false)
      -- Exclude Sourcing (status_code='new') when the applicant is past it.
      -- NULL v_current_status_code means no applicant filter → keep 'new'.
      -- v_current_status_code='new' means still at Sourcing → keep 'new'.
      -- Any other value means past Sourcing → hide 'new'.
      AND (
        v_current_status_code IS NULL
        OR v_current_status_code = 'new'
        OR s.status_code <> 'new'
      )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_archive_batch_history()
 RETURNS TABLE(id uuid, archive_batch_id uuid, action_type text, reason text, executed_by_name text, executed_at timestamp with time zone, rollback_deadline timestamp with time zone, plantilla_count integer, vacancy_count integer, hr_emploc_count integer, moses_hq_count integer, total_count integer, status text, rolled_back_by_name text, rolled_back_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    b.id, b.archive_batch_id, b.action_type, b.reason,
    COALESCE(up.full_name, 'Unknown') AS executed_by_name,
    b.executed_at, b.rollback_deadline,
    b.plantilla_count, b.vacancy_count, b.hr_emploc_count, b.moses_hq_count,
    b.plantilla_count + b.vacancy_count + b.hr_emploc_count + b.moses_hq_count AS total_count,
    CASE WHEN b.status = 'ACTIVE' AND now() > b.rollback_deadline THEN 'EXPIRED' ELSE b.status END AS status,
    rb.full_name AS rolled_back_by_name,
    b.rolled_back_at
  FROM public.system_archive_batches b
  LEFT JOIN public.users_profile up ON up.id = b.executed_by
  LEFT JOIN public.users_profile rb ON rb.id = b.rolled_back_by
  ORDER BY b.executed_at DESC;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_archive_impact_preview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plantilla_count          integer;
  v_vacancy_count            integer;
  v_hr_emploc_count          integer;
  v_moses_hq_pool_count      integer;
  v_moses_hq_assign_count    integer;
  v_moses_hq_open_slot_count integer;
  v_moses_hq_request_count   integer;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*) INTO v_plantilla_count
  FROM public.plantilla
  WHERE is_deleted = false
    AND (is_archived = false OR is_archived IS NULL);

  SELECT COUNT(*) INTO v_vacancy_count
  FROM public.vacancies
  WHERE deleted_at IS NULL
    AND (is_archived = false OR is_archived IS NULL);

  SELECT COUNT(*) INTO v_hr_emploc_count
  FROM public.hr_emploc
  WHERE deleted_at IS NULL;

  SELECT COUNT(DISTINCT pool_type_id) INTO v_moses_hq_pool_count
  FROM public.workforce_pool_slots
  WHERE is_active = true
    AND deleted_at IS NULL;

  SELECT COUNT(*) INTO v_moses_hq_assign_count
  FROM public.workforce_assignments
  WHERE deleted_at IS NULL
    AND status NOT IN ('Completed', 'Ended', 'Cancelled');

  SELECT COUNT(*) INTO v_moses_hq_open_slot_count
  FROM public.workforce_pool_slots
  WHERE is_active = true
    AND deleted_at IS NULL;

  SELECT COUNT(*) INTO v_moses_hq_request_count
  FROM public.workforce_pool_requests
  WHERE deleted_at IS NULL
    AND status NOT IN ('rejected', 'cancelled');

  RETURN jsonb_build_object(
    'plantilla_count',             v_plantilla_count,
    'vacancy_count',               v_vacancy_count,
    'hr_emploc_count',             v_hr_emploc_count,
    'total_count',                 v_plantilla_count + v_vacancy_count + v_hr_emploc_count,
    'moses_hq_pool_count',         v_moses_hq_pool_count,
    'moses_hq_assignment_count',   v_moses_hq_assign_count,
    'moses_hq_open_slot_count',    v_moses_hq_open_slot_count,
    'moses_hq_request_count',      v_moses_hq_request_count
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_freeze_modes()
 RETURNS TABLE(control_key text, enabled boolean, updated_at timestamp with time zone, reason text, updated_by_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level int;
BEGIN
  -- Enforce superAdmin-only caller
  SELECT r.role_level INTO v_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_get_freeze_modes requires superAdmin.';
  END IF;

  RETURN QUERY
  SELECT
    gc.control_key,
    gc.enabled,
    gc.updated_at,
    gc.reason,
    up.full_name AS updated_by_name
  FROM public.governance_controls gc
  LEFT JOIN public.users_profile up ON up.id = gc.updated_by
  WHERE gc.control_key IN ('payroll_freeze', 'audit_freeze', 'recruitment_freeze', 'read_only_emergency')
  ORDER BY gc.control_key;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_governance_audit_log()
 RETURNS TABLE(id uuid, control_key text, action text, before_value jsonb, after_value jsonb, changed_at timestamp with time zone, reason text, changed_by_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level int;
BEGIN
  -- Enforce superAdmin-only caller
  SELECT r.role_level INTO v_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_get_governance_audit_log requires superAdmin.';
  END IF;

  RETURN QUERY
  SELECT
    gal.id,
    gal.control_key,
    gal.action,
    gal.before_value,
    gal.after_value,
    gal.changed_at,
    gal.reason,
    up.full_name AS changed_by_name
  FROM public.governance_audit_log gal
  LEFT JOIN public.users_profile up ON up.id = gal.changed_by
  ORDER BY gal.changed_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_governance_controls()
 RETURNS TABLE(control_key text, enabled boolean, updated_at timestamp with time zone, reason text, updated_by_name text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    gc.control_key,
    gc.enabled,
    gc.updated_at,
    gc.reason,
    up.full_name AS updated_by_name
  FROM governance_controls gc
  LEFT JOIN users_profile up ON up.id = gc.updated_by
  ORDER BY gc.control_key;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_hired_applicants(p_vcode text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, vacancy_vcode text, full_name text, last_name text, first_name text, middle_name text, contact_number text, status text, hired_date date, hired_by text, hired_by_team text, hired_at timestamp with time zone, hired_visible_until timestamp with time zone, days_remaining integer, group_name text, account text, position_name text, state text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    a.id,
    a.vacancy_vcode,
    a.full_name,
    a.last_name,
    a.first_name,
    a.middle_name,
    a.contact_number,
    a.status,
    a.hired_date,
    a.hired_by,
    a.hired_by_team,
    a.hired_at,
    a.hired_visible_until,
    GREATEST(
      0,
      CEIL(EXTRACT(EPOCH FROM (a.hired_visible_until - NOW())) / 86400)::integer
    ) AS days_remaining,
    COALESCE(g.group_name, 'Group') AS group_name,
    v.account,
    v.position AS position_name,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM public.plantilla p
        WHERE (p.hr_emploc_id = he.id
            OR (p.vcode = a.vacancy_vcode AND p.employee_name = a.full_name))
          AND COALESCE(p.is_archived, false) = false
          AND COALESCE(p.is_deleted, false) = false
      ) THEN 'Plantilla'
      WHEN he.id IS NOT NULL THEN 'HR Emploc'
      ELSE 'Vacancy / Pending HR Emploc'
    END AS state
  FROM public.applicants a
  JOIN public.vacancies v
    ON v.vcode = a.vacancy_vcode
   AND v.deleted_at IS NULL
   AND COALESCE(v.is_archived, false) = false
   AND v.status <> 'Archived'
  LEFT JOIN public.groups g ON g.id = v.group_id
  LEFT JOIN public.hr_emploc he
    ON he.applicant_id = a.id
   AND he.deleted_at IS NULL
  WHERE COALESCE(a.is_archived, false) = false
    AND (a.hired_at IS NOT NULL OR a.hired_date IS NOT NULL)
    AND a.hired_visible_until > NOW()
    AND (p_vcode IS NULL OR a.vacancy_vcode = p_vcode)
  ORDER BY a.hired_at DESC NULLS LAST, a.hired_date DESC NULLS LAST;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_get_risk_controls()
 RETURNS TABLE(control_key text, enabled boolean, updated_at timestamp with time zone, reason text, updated_by_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level int;
BEGIN
  SELECT r.role_level INTO v_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_get_risk_controls requires superAdmin.';
  END IF;

  RETURN QUERY
  SELECT
    gc.control_key,
    gc.enabled,
    gc.updated_at,
    gc.reason,
    up.full_name AS updated_by_name
  FROM public.governance_controls gc
  LEFT JOIN public.users_profile up ON up.id = gc.updated_by
  WHERE gc.control_key LIKE 'risk_%'
  ORDER BY gc.control_key;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_is_valid_vacancy_transition(p_old text, p_new text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_old IS NULL OR p_old = '' THEN p_new IN ('Draft','Pending Approval','Open')
    WHEN p_old = p_new THEN TRUE
    WHEN p_old = 'Draft'            AND p_new IN ('Pending Approval','Closed','Rejected') THEN TRUE
    WHEN p_old = 'Pending Approval' AND p_new IN ('Open','Rejected','Closed')             THEN TRUE
    WHEN p_old = 'Open'             AND p_new IN ('On Hold','Filled','Closed')             THEN TRUE
    WHEN p_old = 'On Hold'          AND p_new IN ('Open','Closed')                         THEN TRUE
    WHEN p_old = 'Filled'           AND p_new = 'Open'                                     THEN TRUE
    WHEN p_old IN ('For Sourcing','Backout') AND p_new IN ('Open','Closed','Filled','On Hold') THEN TRUE
    WHEN p_old = 'Archived'         AND p_new = 'Archived'                                  THEN TRUE
    ELSE FALSE
  END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_mask_vacancy_for_role(p_row vacancies, p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v jsonb := to_jsonb(p_row);
BEGIN
  IF p_role = 'Encoder' THEN
    v := v
      - 'hrco_name' - 'hrco_mobile' - 'hrco_user_id'
      - 'om_name'   - 'om_user_id'
      - 'atl_user_id'
      - 'has_penalty' - 'penalty_amount' - 'penalty_aging_detail'
      - 'chain' - 'chain_id'
      - 'requested_by_user_id';
  END IF;
  RETURN v;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_record_assisted_rbac_drift_scan(p_scan_name text, p_scanner_codes text[], p_results jsonb, p_module_filter text DEFAULT NULL::text, p_flutter_snapshot jsonb DEFAULT NULL::jsonb, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_level   integer;
  v_result_count   integer;
  v_run_id         uuid;
  v_result         jsonb;
  v_result_id      uuid;
  v_evidence_item  jsonb;
  v_scanner_code   text;
  v_fingerprint    text;
  v_severity       text;
  v_finding_code   text;
  v_module_key     text;
  v_resource_key   text;
  v_action_key     text;
  v_role_name      text;
  v_expected_rule  text;
  v_observed_rule  text;
  v_result_summary text;
  v_recommendation text;
  v_confidence     numeric(5,2);
  v_is_regression  boolean;
  v_total_count    integer := 0;
  v_critical_count integer := 0;
  v_high_count     integer := 0;
  v_medium_count   integer := 0;
  v_low_count      integer := 0;
  v_info_count     integer := 0;
  v_bad_codes      text[];
BEGIN
  -- ─── Auth guard ───────────────────────────────────────────────────────────
  v_caller_level := public.get_my_role_level();
  IF v_caller_level < 90 THEN
    RAISE EXCEPTION 'Insufficient permissions to record assisted RBAC drift scan'
      USING ERRCODE = '42501';
  END IF;

  -- ─── Validate p_results is a JSON array ───────────────────────────────────
  IF p_results IS NULL OR jsonb_typeof(p_results) <> 'array' THEN
    RAISE EXCEPTION 'p_results must be a non-null JSON array'
      USING ERRCODE = '22023';
  END IF;

  -- ─── Validate result count cap ────────────────────────────────────────────
  v_result_count := jsonb_array_length(p_results);
  IF v_result_count > 50 THEN
    RAISE EXCEPTION 'Result count % exceeds maximum of 50 per assisted scan run. '
      'Split into multiple calls if needed.', v_result_count
      USING ERRCODE = '22023';
  END IF;

  -- ─── Validate all scanner codes exist in the registry ────────────────────
  IF array_length(p_scanner_codes, 1) > 0 THEN
    SELECT array_agg(requested_code)
    INTO v_bad_codes
    FROM unnest(p_scanner_codes) AS requested_code
    WHERE NOT EXISTS (
      SELECT 1 FROM public.rbac_drift_scanner_definitions d
      WHERE d.scanner_code = requested_code
    );

    IF v_bad_codes IS NOT NULL AND array_length(v_bad_codes, 1) > 0 THEN
      RAISE EXCEPTION 'Unknown scanner code(s): %. All scanner_codes must exist in rbac_drift_scanner_definitions.',
        array_to_string(v_bad_codes, ', ')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ─── Validate all scanner_code values within p_results ───────────────────
  SELECT array_agg(DISTINCT (item->>'scanner_code'))
  INTO v_bad_codes
  FROM jsonb_array_elements(p_results) AS item
  WHERE (item->>'scanner_code') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.rbac_drift_scanner_definitions d
      WHERE d.scanner_code = item->>'scanner_code'
    );

  IF v_bad_codes IS NOT NULL AND array_length(v_bad_codes, 1) > 0 THEN
    RAISE EXCEPTION 'Unknown scanner_code value(s) in results: %. Must match rbac_drift_scanner_definitions.',
      array_to_string(v_bad_codes, ', ')
      USING ERRCODE = '22023';
  END IF;

  -- ─── Validate severity values within p_results ────────────────────────────
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_results) AS item
    WHERE (item->>'severity') NOT IN ('critical', 'high', 'medium', 'low', 'info')
  ) THEN
    RAISE EXCEPTION 'Invalid severity value in results. Allowed: critical, high, medium, low, info'
      USING ERRCODE = '22023';
  END IF;

  -- ─── Insert scan run (status = running) ───────────────────────────────────
  INSERT INTO public.rbac_drift_scan_runs (
    scan_name, scan_mode, scan_status, triggered_by,
    scanner_codes, module_filter, flutter_snapshot,
    started_at, notes
  ) VALUES (
    p_scan_name, 'assisted', 'running', auth.uid(),
    p_scanner_codes, p_module_filter, p_flutter_snapshot,
    now(), p_notes
  )
  RETURNING id INTO v_run_id;

  -- ─── Insert results and evidence ──────────────────────────────────────────
  FOR v_result IN SELECT * FROM jsonb_array_elements(p_results)
  LOOP
    -- Extract scalar fields with safe defaults.
    v_scanner_code   := v_result->>'scanner_code';
    v_fingerprint    := COALESCE(v_result->>'fingerprint', gen_random_uuid()::text);
    v_severity       := v_result->>'severity';
    v_finding_code   := v_result->>'finding_code';
    v_module_key     := v_result->>'module_key';
    v_resource_key   := v_result->>'resource_key';
    v_action_key     := v_result->>'action_key';
    v_role_name      := v_result->>'role_name';
    v_expected_rule  := v_result->>'expected_rule';
    v_observed_rule  := v_result->>'observed_rule';
    v_result_summary := COALESCE(v_result->>'result_summary', '');
    v_recommendation := v_result->>'recommendation';
    v_confidence     := COALESCE((v_result->>'confidence_score')::numeric(5,2), 0.80);
    v_is_regression  := COALESCE((v_result->>'is_regression')::boolean, false);

    -- Insert result row; skip duplicates within the same run by fingerprint.
    INSERT INTO public.rbac_drift_scan_results (
      scan_run_id, scanner_code, finding_code, fingerprint,
      severity, status, module_key, resource_key, action_key,
      role_name, expected_rule, observed_rule, result_summary,
      recommendation, confidence_score, is_regression
    ) VALUES (
      v_run_id, v_scanner_code, v_finding_code, v_fingerprint,
      v_severity, 'detected', v_module_key, v_resource_key, v_action_key,
      v_role_name, v_expected_rule, v_observed_rule, v_result_summary,
      v_recommendation, v_confidence, v_is_regression
    )
    ON CONFLICT (scan_run_id, fingerprint) DO NOTHING
    RETURNING id INTO v_result_id;

    -- Only insert evidence when the result row was actually inserted.
    IF v_result_id IS NOT NULL THEN
      -- Accumulate severity counts.
      v_total_count := v_total_count + 1;
      CASE v_severity
        WHEN 'critical' THEN v_critical_count := v_critical_count + 1;
        WHEN 'high'     THEN v_high_count     := v_high_count     + 1;
        WHEN 'medium'   THEN v_medium_count   := v_medium_count   + 1;
        WHEN 'low'      THEN v_low_count      := v_low_count      + 1;
        WHEN 'info'     THEN v_info_count     := v_info_count     + 1;
        ELSE NULL;
      END CASE;

      -- Insert each evidence item belonging to this result.
      IF v_result ? 'evidence' AND jsonb_typeof(v_result->'evidence') = 'array' THEN
        FOR v_evidence_item IN SELECT * FROM jsonb_array_elements(v_result->'evidence')
        LOOP
          INSERT INTO public.rbac_drift_scan_evidence (
            result_id, evidence_type, reference_path, reference_name,
            line_note, matched_pattern, expected_value, observed_value,
            evidence_payload
          ) VALUES (
            v_result_id,
            COALESCE(v_evidence_item->>'evidence_type', 'audit_gap'),
            v_evidence_item->>'reference_path',
            v_evidence_item->>'reference_name',
            v_evidence_item->>'line_note',
            v_evidence_item->>'matched_pattern',
            v_evidence_item->>'expected_value',
            v_evidence_item->>'observed_value',
            COALESCE((v_evidence_item->'evidence_payload'), '{}'::jsonb)
          );
        END LOOP;
      END IF;
    END IF;

    -- Reset per-iteration ID to detect ON CONFLICT skips correctly.
    v_result_id := NULL;
  END LOOP;

  -- ─── Finalize scan run ────────────────────────────────────────────────────
  UPDATE public.rbac_drift_scan_runs
  SET
    scan_status    = 'completed',
    completed_at   = now(),
    total_results  = v_total_count,
    critical_count = v_critical_count,
    high_count     = v_high_count,
    medium_count   = v_medium_count,
    low_count      = v_low_count,
    info_count     = v_info_count
  WHERE id = v_run_id;

  RETURN v_run_id;

EXCEPTION
  WHEN OTHERS THEN
    -- Mark the scan run as failed before re-raising.
    IF v_run_id IS NOT NULL THEN
      UPDATE public.rbac_drift_scan_runs
      SET scan_status = 'failed', completed_at = now()
      WHERE id = v_run_id;
    END IF;
    RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_reject_applicant_profile_edit_request(p_request_id uuid, p_remarks text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_req        public.applicant_profile_edit_requests%ROWTYPE;
BEGIN
  -- RBAC: Encoder | Head Admin | Super Admin
  IF NOT (
    v_level IN (30, 90, 100)
    OR public.i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required to reject profile corrections'
      USING ERRCODE = '42501';
  END IF;

  -- Rejection remarks required
  IF TRIM(COALESCE(p_remarks, '')) = '' THEN
    RAISE EXCEPTION 'reviewer_remarks is required when rejecting a profile edit request'
      USING ERRCODE = '22023';
  END IF;

  -- Fetch and lock request
  SELECT * INTO v_req
    FROM public.applicant_profile_edit_requests
   WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile edit request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status != 'Pending' THEN
    RAISE EXCEPTION 'request is not Pending (current status: %)', v_req.status
      USING ERRCODE = '22023';
  END IF;

  -- Scope check for Encoder
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.applicants a
      JOIN public.vacancies  v ON v.vcode = a.vacancy_vcode
      WHERE a.id = v_req.applicant_id
        AND v.account = ANY(public.get_my_allowed_accounts())
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Mark request Rejected
  UPDATE public.applicant_profile_edit_requests
  SET
    status           = 'Rejected',
    reviewed_by      = v_profile_id,
    reviewed_at      = NOW(),
    reviewer_remarks = p_remarks,
    updated_at       = NOW()
  WHERE id = p_request_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_release_applicant_slot(p_slot_id uuid, p_performed_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  Phase B — non-blocking slot release on applicant terminal (OHM2026_0041).

  After the host fn_update_applicant_status has already written the
  terminal status, this function checks whether any other active applicant
  still holds p_slot_id. If none remain, the slot transitions pipeline → open
  (aging restarts for the reopened slot, per Phase B design §Q6).

  The check runs AFTER the host status write so the count reflects the
  new state (the departing applicant is no longer pipeline-active).

  Reason code: NULL (pipeline→open reopen carries no reason code at the
  pipeline layer — backout/rejection is captured on the applicant row, not
  on slot_history; see vcode_slot_phase_b_applicant_binding_plan.md §Q7).
*/
DECLARE
  v_active_cnt bigint;
  v_result     jsonb;
BEGIN
  IF p_slot_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Count active applicants still bound to this slot (post-terminal write).
  SELECT COUNT(*) INTO v_active_cnt
  FROM   public.applicants
  WHERE  slot_id = p_slot_id
    AND  public.fn_is_active_vacancy_applicant_status(status)
    AND  COALESCE(is_archived, false) = false;

  IF v_active_cnt > 0 THEN
    -- Another active applicant still holds the slot; do not reopen.
    RETURN jsonb_build_object(
      'status',    'no_op',
      'reason',    'other_active_applicant_remains',
      'slot_id',   p_slot_id,
      'remaining', v_active_cnt
    );
  END IF;

  -- No remaining active applicant — release: pipeline → open.
  SELECT public.fn_set_slot_status(
    p_slot_id      => p_slot_id,
    p_new_status   => 'open',
    p_reason_code  => NULL,
    p_performed_by => p_performed_by,
    p_remarks      => format(
      'Phase B release / last active applicant went terminal / slot=%s',
      p_slot_id
    )
  ) INTO v_result;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_release_applicant_slot: error for slot=% — % (sqlstate=%)',
    p_slot_id, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_release_coverage_slot(p_slot_id uuid, p_performed_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_active_cnt bigint;
  v_result     jsonb;
BEGIN
  IF p_slot_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COUNT(*) INTO v_active_cnt
  FROM   public.applicants
  WHERE  coverage_slot_id = p_slot_id
    AND  public.fn_is_active_vacancy_applicant_status(status)
    AND  COALESCE(is_archived, false) = false;

  IF v_active_cnt > 0 THEN
    -- Another active applicant still holds the slot; do not reopen.
    RETURN jsonb_build_object(
      'status',    'no_op',
      'reason',    'other_active_applicant_remains',
      'slot_id',   p_slot_id,
      'remaining', v_active_cnt
    );
  END IF;

  -- No remaining active applicant — release the EXACT slot: pipeline → open.
  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => p_slot_id,
    p_new_status   => 'open',
    p_performed_by => p_performed_by,
    p_remarks      => format(
      'Phase R-B release / last active applicant went terminal / coverage_slot=%s',
      p_slot_id
    )
  ) INTO v_result;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_release_coverage_slot: error for slot=% — % (sqlstate=%)',
    p_slot_id, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_request_applicant_profile_edit(p_applicant_id uuid, p_reason text, p_new_first_name text DEFAULT NULL::text, p_new_middle_name text DEFAULT NULL::text, p_new_last_name text DEFAULT NULL::text, p_new_contact_number text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_role       text := public.get_my_role();
  v_app        public.applicants%ROWTYPE;
  v_req_id     uuid;
BEGIN
  -- RBAC: Ops (40–70) | Recruitment (20) | Super Admin (100)
  -- Encoder (30) + Head Admin (90) must NOT request — they approve.
  IF NOT (
    public.i_am_ops()           -- 40–70
    OR public.i_am_recruitment() -- 20
    OR v_level = 100             -- Super Admin
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Recruitment Team, or Super Admin required to request profile corrections'
      USING ERRCODE = '42501';
  END IF;

  -- Require at least one field
  IF p_new_first_name     IS NULL
     AND p_new_middle_name   IS NULL
     AND p_new_last_name     IS NULL
     AND p_new_contact_number IS NULL THEN
    RAISE EXCEPTION 'at least one field (first_name, middle_name, last_name, contact_number) must be specified'
      USING ERRCODE = '22023';
  END IF;

  -- Require reason
  IF TRIM(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'reason is required for profile edit requests'
      USING ERRCODE = '22023';
  END IF;

  -- Fetch applicant
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Scope check (skip for full-access)
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Block if a pending request already exists (unique index also enforces this)
  IF EXISTS (
    SELECT 1 FROM public.applicant_profile_edit_requests
    WHERE applicant_id = p_applicant_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'a pending profile edit request already exists for this applicant — resolve it before creating another'
      USING ERRCODE = '23505';
  END IF;

  -- Create request with current field snapshot
  INSERT INTO public.applicant_profile_edit_requests (
    applicant_id,
    reason,
    status,
    new_first_name,
    new_middle_name,
    new_last_name,
    new_contact_number,
    snapshot_first_name,
    snapshot_middle_name,
    snapshot_last_name,
    snapshot_contact_number,
    requested_by,
    requested_by_role,
    requested_at
  ) VALUES (
    p_applicant_id,
    p_reason,
    'Pending',
    p_new_first_name,
    p_new_middle_name,
    p_new_last_name,
    p_new_contact_number,
    v_app.first_name,
    v_app.middle_name,
    v_app.last_name,
    v_app.contact_number,
    v_profile_id,
    v_role,
    NOW()
  )
  RETURNING id INTO v_req_id;

  RETURN v_req_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_request_emploc_deletion(p_hr_emploc_id uuid, p_reason text, p_deletion_type text DEFAULT 'Backout'::text, p_original_emploc_id uuid DEFAULT NULL::uuid)
 RETURNS hr_emploc_deletion_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp         public.hr_emploc;
  v_profile     public.users_profile;
  v_req         public.hr_emploc_deletion_requests;
  v_full_name   text;
  v_last_name   text;
  v_first_name  text;
  v_store       text;
  v_name        text;
  v_parts       text[];
BEGIN
  -- RBAC: Ops roles or full access
  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: Ops or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Audit Freeze Gate (Phase 2A) ──────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_manual_deletion_actions');

  IF p_deletion_type NOT IN ('Backout', 'Duplicate Record') THEN
    RAISE EXCEPTION 'invalid deletion_type: %. Must be Backout or Duplicate Record', p_deletion_type
      USING ERRCODE = '22023';
  END IF;

  IF p_deletion_type = 'Duplicate Record' AND p_original_emploc_id IS NULL THEN
    RAISE EXCEPTION 'original_emploc_id is required for Duplicate Record deletion type'
      USING ERRCODE = '22023';
  END IF;

  IF p_original_emploc_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.hr_emploc
      WHERE id = p_original_emploc_id AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'original_emploc_id % not found or archived', p_original_emploc_id
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or already archived', p_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION 'cannot request deletion: employee is already in Plantilla'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.plantilla
    WHERE hr_emploc_id = p_hr_emploc_id
      AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'cannot request deletion: active Plantilla record exists'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'a pending deletion request already exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_profile FROM public.users_profile WHERE id = public.get_my_profile_id();
  v_full_name := COALESCE(v_profile.full_name, public.get_my_full_name());

  -- Immutable name snapshot (Last, First or First Last)
  v_name := COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name);
  IF v_name LIKE '%, %' THEN
    v_last_name  := BTRIM(split_part(v_name, ', ', 1));
    v_first_name := BTRIM(split_part(v_name, ', ', 2));
  ELSE
    v_parts      := regexp_split_to_array(BTRIM(v_name), '\s+');
    v_last_name  := v_parts[array_length(v_parts, 1)];
    v_first_name := BTRIM(array_to_string(v_parts[1:array_length(v_parts,1)-1], ' '));
  END IF;

  v_store := COALESCE(NULLIF(BTRIM(COALESCE(v_emp.store_name, '')), ''), v_emp.account);

  INSERT INTO public.hr_emploc_deletion_requests (
    hr_emploc_id,
    applicant_name,
    vcode,
    account,
    reason,
    requested_by,
    requested_by_role,
    requested_by_user_id,
    deletion_type,
    original_emploc_id,
    reopen_vacancy,
    original_hr_status,
    snapshot_last_name,
    snapshot_first_name,
    snapshot_position,
    snapshot_store,
    status
  ) VALUES (
    p_hr_emploc_id,
    COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name),
    v_emp.vcode,
    v_emp.account,
    BTRIM(p_reason),
    v_full_name,
    COALESCE(v_profile.role, public.get_my_role()),
    public.get_my_profile_id(),
    p_deletion_type,
    p_original_emploc_id,
    (p_deletion_type = 'Backout'),
    v_emp.hr_status,
    v_last_name,
    v_first_name,
    v_emp.position,
    v_store,
    'Pending'
  )
  RETURNING * INTO v_req;

  RETURN v_req;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_rollback_archive_batch(p_batch_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_batch                record;
  v_caller_id            uuid;
  v_now                  timestamptz;
  v_plantilla_count      integer := 0;
  v_vacancy_count        integer := 0;
  v_hr_emploc_count      integer := 0;
  v_slots_count          integer := 0;
  v_hc_count             integer := 0;
  v_assign_count         integer := 0;
  v_slot_review_count    integer := 0;
  v_req_item_count       integer := 0;
  v_request_count        integer := 0;
  v_coverage_count       integer := 0;
  v_pool_slot_count      integer := 0;
  v_pool_vacancy_count   integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'rollback_reason is required and must not be empty' USING ERRCODE = '22000';
  END IF;

  SELECT * INTO v_batch
  FROM public.system_archive_batches
  WHERE archive_batch_id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Archive batch % not found', p_batch_id USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status = 'ROLLED_BACK' THEN
    RAISE EXCEPTION 'Archive batch has already been rolled back' USING ERRCODE = '55000';
  END IF;

  v_now := now();
  IF v_now > v_batch.rollback_deadline THEN
    UPDATE public.system_archive_batches SET status = 'EXPIRED'
    WHERE id = v_batch.id AND status = 'ACTIVE';
    RAISE EXCEPTION 'Rollback window has expired. This archive is now final.' USING ERRCODE = '55000';
  END IF;

  v_caller_id := public.get_current_profile_id();

  -- RESTORE PLANTILLA
  IF v_batch.action_type IN ('plantilla', 'qa_reset') THEN
    UPDATE public.plantilla
    SET is_archived = false, archived_at = NULL, archived_by = NULL, archive_reason = NULL,
        restored_at = v_now, restored_by = v_caller_id, qa_archive_batch_id = NULL,
        updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND is_archived = true;
    GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

    UPDATE public.plantilla_slots
    SET slot_status = 'open', closed_at = NULL, closed_by = NULL, closure_reason_code = NULL,
        qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND slot_status = 'closed' AND closure_reason_code = 'QA_RESET';
    GET DIAGNOSTICS v_slots_count = ROW_COUNT;
  END IF;

  -- RESTORE VACANCIES
  IF v_batch.action_type IN ('vacancy', 'qa_reset') THEN
    UPDATE public.vacancies
    SET is_archived = false, archived_at = NULL, archived_by_id = NULL, archived_by = NULL,
        archive_reason = NULL, status = 'Open', restored_at = v_now, restored_by = v_caller_id,
        qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND is_archived = true;
    GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

    UPDATE public.headcount_requests
    SET is_archived = false, archived_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now
    WHERE qa_archive_batch_id = p_batch_id AND is_archived = true;
    GET DIAGNOSTICS v_hc_count = ROW_COUNT;
  END IF;

  -- RESTORE HR EMPLOC
  IF v_batch.action_type IN ('hr_emploc', 'qa_reset') THEN
    UPDATE public.hr_emploc
    SET deleted_at = NULL, qa_archived_at = NULL, qa_archived_by = NULL, qa_archive_reason = NULL,
        qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id;
    GET DIAGNOSTICS v_hr_emploc_count = ROW_COUNT;
  END IF;

  -- RESTORE MOSES HQ
  IF v_batch.action_type IN ('moses_hq', 'plantilla', 'qa_reset') THEN
    IF v_batch.action_type = 'moses_hq' THEN
      UPDATE public.vacancies
      SET is_archived = false, archived_at = NULL, archived_by_id = NULL, archived_by = NULL,
          archive_reason = NULL, status = 'Open', restored_at = v_now, restored_by = v_caller_id,
          qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
      WHERE qa_archive_batch_id = p_batch_id AND is_pool_vacancy = true AND is_archived = true;
      GET DIAGNOSTICS v_pool_vacancy_count = ROW_COUNT;
    END IF;

    UPDATE public.workforce_pool_slots
    SET is_active = true, deleted_at = NULL, qa_archive_batch_id = NULL,
        updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND is_active = false;
    GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

    UPDATE public.vacancy_coverage
    SET archived_at = NULL, archived_by = NULL, qa_archive_batch_id = NULL,
        updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND archived_at IS NOT NULL;
    GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

    UPDATE public.workforce_pool_requests
    SET deleted_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_request_count = ROW_COUNT;

    UPDATE public.workforce_pool_request_items
    SET deleted_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now
    WHERE qa_archive_batch_id = p_batch_id AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

    UPDATE public.workforce_slot_reviews
    SET deleted_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now
    WHERE qa_archive_batch_id = p_batch_id AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

    UPDATE public.workforce_assignments
    SET deleted_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_assign_count = ROW_COUNT;
  END IF;

  UPDATE public.system_archive_batches
  SET status = 'ROLLED_BACK', rolled_back_by = v_caller_id, rolled_back_at = v_now
  WHERE id = v_batch.id;

  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, restored_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('enterprise_archive_rollback', p_batch_id, 'qa_rollback', v_caller_id, p_reason, p_batch_id,
     jsonb_build_object(
       'archive_batch_id', p_batch_id, 'action_type', v_batch.action_type,
       'rolled_back_by', v_caller_id, 'rolled_back_at', v_now, 'reason', p_reason,
       'plantilla_restored_count', v_plantilla_count, 'slots_restored_count', v_slots_count,
       'vacancy_restored_count', v_vacancy_count, 'hc_requests_count', v_hc_count,
       'hr_emploc_restored_count', v_hr_emploc_count,
       'moses_hq_assign_restored', v_assign_count, 'moses_hq_slot_review_restored', v_slot_review_count,
       'moses_hq_req_item_restored', v_req_item_count, 'moses_hq_request_restored', v_request_count,
       'moses_hq_coverage_restored', v_coverage_count, 'moses_hq_pool_slot_restored', v_pool_slot_count,
       'moses_hq_pool_vacancy_restored', v_pool_vacancy_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id', p_batch_id,
    'plantilla_restored_count', v_plantilla_count, 'slots_restored_count', v_slots_count,
    'vacancy_restored_count', v_vacancy_count, 'hc_requests_restored_count', v_hc_count,
    'hr_emploc_restored_count', v_hr_emploc_count,
    'moses_hq_assign_restored', v_assign_count, 'moses_hq_request_restored', v_request_count,
    'moses_hq_pool_slot_restored', v_pool_slot_count, 'moses_hq_pool_vacancy_restored', v_pool_vacancy_count,
    'rolled_back_by', v_caller_id, 'rolled_back_at', v_now
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_search_applicants_scoped(p_last_name text, p_first_name text, p_middle_name text DEFAULT NULL::text, p_vacancy_vcode text DEFAULT NULL::text, p_limit integer DEFAULT 20)
 RETURNS SETOF applicants
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_target_account   text;
  v_allowed_accounts text[];
BEGIN
  -- Require authenticated session
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated'
      USING ERRCODE = '42501';
  END IF;

  v_allowed_accounts := public.get_my_allowed_accounts();

  IF p_vacancy_vcode IS NOT NULL AND btrim(p_vacancy_vcode) <> '' THEN
    -- Resolve the target vacancy's account.
    -- Filter: deleted_at IS NULL only.
    --   • Includes: Open, Pipeline, Filled, Closed, Archived vacancies
    --     (both manually created and imported — all have valid account data).
    --   • Excludes: rolled-back import vacancies (deleted_at IS NOT NULL).
    --   • is_archived is intentionally NOT filtered here: an archived vacancy
    --     still carries the correct account and vcode for scope resolution.
    SELECT v.account INTO v_target_account
    FROM public.vacancies v
    WHERE v.vcode = p_vacancy_vcode
      AND v.deleted_at IS NULL
    LIMIT 1;

    IF v_target_account IS NULL THEN
      RAISE EXCEPTION 'vacancy % not found or has been deleted', p_vacancy_vcode
        USING ERRCODE = 'P0002';
    END IF;

    -- Enforce: caller must have access to this account
    IF NOT public.i_have_full_access()
       AND NOT (v_target_account = ANY(v_allowed_accounts)) THEN
      RAISE EXCEPTION 'forbidden: vacancy % is outside caller account scope', p_vacancy_vcode
        USING ERRCODE = '42501';
    END IF;

    -- Return applicants scoped strictly to the target vacancy's account.
    -- Result JOIN: deleted_at IS NULL on vacancies so rolled-back import rows
    -- are excluded; is_archived is NOT filtered so applicants from
    -- Archived/Closed vacancies in the same account remain findable.
    -- Applicant-level: is_archived = false excludes withdrawn/archived applicants.
    RETURN QUERY
    SELECT DISTINCT ON (a.last_name, a.first_name, a.contact_number) a.*
    FROM public.applicants a
    JOIN public.vacancies v
      ON v.vcode = a.vacancy_vcode
     AND v.account = v_target_account
     AND v.deleted_at IS NULL
    WHERE COALESCE(a.is_archived, false) = false
      AND a.last_name  ILIKE '%' || btrim(p_last_name)  || '%'
      AND a.first_name ILIKE '%' || btrim(p_first_name) || '%'
      AND (
        p_middle_name IS NULL
        OR btrim(p_middle_name) = ''
        OR a.middle_name ILIKE '%' || btrim(p_middle_name) || '%'
      )
    ORDER BY a.last_name, a.first_name, a.contact_number, a.created_at DESC
    LIMIT p_limit;

  ELSE
    -- No vacancy context: fall back to all accounts in caller's scope.
    -- Behaves identically to the previous applicants_read_scoped RLS path.
    RETURN QUERY
    SELECT DISTINCT ON (a.last_name, a.first_name, a.contact_number) a.*
    FROM public.applicants a
    JOIN public.vacancies v
      ON v.vcode = a.vacancy_vcode
     AND (
       public.i_have_full_access()
       OR v.account = ANY(v_allowed_accounts)
     )
     AND v.deleted_at IS NULL
    WHERE COALESCE(a.is_archived, false) = false
      AND a.last_name  ILIKE '%' || btrim(p_last_name)  || '%'
      AND a.first_name ILIKE '%' || btrim(p_first_name) || '%'
      AND (
        p_middle_name IS NULL
        OR btrim(p_middle_name) = ''
        OR a.middle_name ILIKE '%' || btrim(p_middle_name) || '%'
      )
    ORDER BY a.last_name, a.first_name, a.contact_number, a.created_at DESC
    LIMIT p_limit;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_set_coverage_slot_status(p_slot_id uuid, p_new_status text, p_performed_by uuid DEFAULT NULL::uuid, p_remarks text DEFAULT NULL::text, p_occupant_plantilla_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cur text;
  v_ord integer;
BEGIN
  IF p_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_slot');
  END IF;

  SELECT slot_status, slot_ordinal
    INTO v_cur, v_ord
    FROM public.coverage_slots
   WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason', 'slot_not_found', 'slot_id', p_slot_id);
  END IF;

  IF v_cur = p_new_status THEN
    RETURN jsonb_build_object('status', 'no_op',
      'reason', 'already_in_status', 'slot_id', p_slot_id, 'slot_status', v_cur);
  END IF;

  IF p_new_status = 'active' AND p_occupant_plantilla_id IS NULL THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason', 'occupant_plantilla_required_for_active',
      'slot_id', p_slot_id);
  END IF;

  IF NOT ( (v_cur = 'open'          AND p_new_status = 'pipeline')
        OR (v_cur = 'pipeline'      AND p_new_status = 'open')
        OR (v_cur = 'pipeline'      AND p_new_status = 'hr_processing')
        OR (v_cur = 'hr_processing' AND p_new_status = 'open')
        OR (v_cur = 'hr_processing' AND p_new_status = 'active') ) THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason',
        format('edge %s -> %s not owned by R-D (open<->pipeline, '
               'pipeline->hr_processing, hr_processing->open, '
               'hr_processing->active only)', v_cur, p_new_status),
      'slot_id', p_slot_id);
  END IF;

  UPDATE public.coverage_slots
     SET slot_status = p_new_status,
         current_occupant_plantilla_id =
           CASE WHEN p_new_status = 'active' THEN p_occupant_plantilla_id ELSE NULL END,
         updated_at  = now()
   WHERE id = p_slot_id;

  RETURN jsonb_build_object('status', 'ok',
    'slot_id', p_slot_id,
    'from', v_cur,
    'to', p_new_status,
    'slot_ordinal', v_ord,
    'occupant_plantilla_id',
      CASE WHEN p_new_status = 'active' THEN p_occupant_plantilla_id ELSE NULL END);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_set_slot_status(p_slot_id uuid, p_new_status text, p_reason_code text DEFAULT NULL::text, p_performed_by uuid DEFAULT NULL::uuid, p_remarks text DEFAULT NULL::text, p_occupant_plantilla_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slot           record;
  v_from_status    text;
  v_action_type    text;
  v_history_id     uuid;
  v_transition_ok  boolean := false;
  v_blocked_reason text;
BEGIN
  IF p_slot_id IS NULL THEN
    RAISE EXCEPTION 'fn_set_slot_status: p_slot_id is required';
  END IF;

  IF p_new_status NOT IN ('open', 'pipeline', 'hr_processing', 'occupied', 'closed') THEN
    RAISE EXCEPTION 'fn_set_slot_status: unknown status value ''%''', p_new_status;
  END IF;

  SELECT * INTO v_slot
  FROM public.plantilla_slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_set_slot_status: slot % not found', p_slot_id;
  END IF;

  v_from_status := v_slot.slot_status;

  IF v_from_status = p_new_status THEN
    RETURN jsonb_build_object(
      'status',      'no_op',
      'slot_id',     p_slot_id,
      'from_status', v_from_status,
      'to_status',   p_new_status
    );
  END IF;

  IF v_from_status = 'closed' THEN
    v_transition_ok  := false;
    v_blocked_reason := 'closed is terminal under automation; '
                        're-opening a slot requires an HC re-add workflow';

  ELSIF v_from_status = 'open' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'pipeline';

  ELSIF v_from_status = 'open' AND p_new_status = 'occupied' THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := 'open→occupied (transfer-in) requires p_occupant_plantilla_id';
    ELSE
      v_transition_ok := true;
      v_action_type   := 'transfer_in';
    END IF;

  ELSIF v_from_status = 'open' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'open' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'import_reserved';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'hr_processing';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'occupied' THEN
    v_transition_ok  := false;
    v_blocked_reason := 'pipeline→occupied is blocked: slot must pass through hr_processing first';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'occupied' THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := 'hr_processing→occupied requires p_occupant_plantilla_id';
    ELSE
      v_transition_ok := true;
      v_action_type   := 'occupied';
    END IF;

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'import_rejected';

  ELSIF v_from_status = 'occupied' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := CASE p_reason_code
                          WHEN 'TRANSFER_OUT' THEN 'transfer_out'
                          ELSE 'resigned'
                        END;

  ELSIF v_from_status = 'occupied' AND p_new_status IN ('pipeline', 'hr_processing') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      'occupied→%s is blocked: occupant must separate first (occupied→open), '
      'then the slot re-enters recruitment', p_new_status
    );

  ELSE
    v_transition_ok  := false;
    v_blocked_reason := format(
      'transition %s→%s is not in the valid transition matrix',
      v_from_status, p_new_status
    );
  END IF;

  IF NOT v_transition_ok THEN
    RETURN jsonb_build_object(
      'status',         'blocked',
      'slot_id',        p_slot_id,
      'from_status',    v_from_status,
      'to_status',      p_new_status,
      'blocked_reason', v_blocked_reason
    );
  END IF;

  UPDATE public.plantilla_slots
  SET
    slot_status                   = p_new_status,
    current_occupant_plantilla_id = CASE
      WHEN p_new_status = 'occupied'
        THEN p_occupant_plantilla_id
      WHEN p_new_status IN ('open', 'pipeline', 'hr_processing', 'closed')
        THEN NULL
      ELSE current_occupant_plantilla_id
    END,
    closure_reason_code           = CASE
      WHEN p_new_status = 'closed' THEN p_reason_code
      ELSE closure_reason_code
    END,
    closed_at                     = CASE
      WHEN p_new_status = 'closed' THEN now()
      ELSE closed_at
    END,
    closed_by                     = CASE
      WHEN p_new_status = 'closed' THEN p_performed_by
      ELSE closed_by
    END,
    updated_at                    = now(),
    updated_by                    = p_performed_by
  WHERE id = p_slot_id;

  v_history_id := gen_random_uuid();

  INSERT INTO public.slot_history (
    id, slot_id, account_id, action_type,
    old_value, new_value, reason_code, performed_by, remarks, created_at
  ) VALUES (
    v_history_id, p_slot_id, v_slot.account_id, v_action_type,
    v_from_status, p_new_status, p_reason_code, p_performed_by, p_remarks, now()
  );

  RETURN jsonb_build_object(
    'status',      'ok',
    'slot_id',     p_slot_id,
    'from_status', v_from_status,
    'to_status',   p_new_status,
    'action_type', v_action_type,
    'reason_code', p_reason_code,
    'history_id',  v_history_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_super_admin_update_applicant_profile(p_applicant_id uuid, p_reason text, p_new_first_name text DEFAULT NULL::text, p_new_middle_name text DEFAULT NULL::text, p_new_last_name text DEFAULT NULL::text, p_new_contact_number text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_app        public.applicants%ROWTYPE;
  v_changed    jsonb := '{}';
  v_new_last   text;
  v_new_first  text;
  v_new_middle text;
BEGIN
  -- Super Admin ONLY
  IF public.get_my_role_level() != 100 THEN
    RAISE EXCEPTION 'forbidden: Super Admin only for direct profile overrides'
      USING ERRCODE = '42501';
  END IF;

  IF TRIM(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'reason is required for a Super Admin direct profile override'
      USING ERRCODE = '22023';
  END IF;

  IF p_new_first_name      IS NULL
     AND p_new_middle_name  IS NULL
     AND p_new_last_name    IS NULL
     AND p_new_contact_number IS NULL THEN
    RAISE EXCEPTION 'at least one field must be specified for the override'
      USING ERRCODE = '22023';
  END IF;

  -- Fetch applicant (super admin can access any)
  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Build audit payload
  IF p_new_last_name IS NOT NULL
     AND p_new_last_name IS DISTINCT FROM v_app.last_name THEN
    v_changed := v_changed || jsonb_build_object('last_name',
      jsonb_build_object('old', v_app.last_name, 'new', p_new_last_name));
  END IF;
  IF p_new_first_name IS NOT NULL
     AND p_new_first_name IS DISTINCT FROM v_app.first_name THEN
    v_changed := v_changed || jsonb_build_object('first_name',
      jsonb_build_object('old', v_app.first_name, 'new', p_new_first_name));
  END IF;
  IF p_new_middle_name IS NOT NULL
     AND p_new_middle_name IS DISTINCT FROM v_app.middle_name THEN
    v_changed := v_changed || jsonb_build_object('middle_name',
      jsonb_build_object('old', v_app.middle_name, 'new', p_new_middle_name));
  END IF;
  IF p_new_contact_number IS NOT NULL
     AND p_new_contact_number IS DISTINCT FROM v_app.contact_number THEN
    v_changed := v_changed || jsonb_build_object('contact_number',
      jsonb_build_object('old', v_app.contact_number, 'new', p_new_contact_number));
  END IF;

  -- Resolve final name parts
  v_new_last   := COALESCE(p_new_last_name,   v_app.last_name);
  v_new_first  := COALESCE(p_new_first_name,  v_app.first_name);
  v_new_middle := COALESCE(p_new_middle_name, v_app.middle_name);

  -- Apply override directly (no approval required for Super Admin)
  UPDATE public.applicants
  SET
    last_name      = COALESCE(p_new_last_name,      last_name),
    first_name     = COALESCE(p_new_first_name,     first_name),
    middle_name    = COALESCE(p_new_middle_name,    middle_name),
    contact_number = COALESCE(p_new_contact_number, contact_number),
    full_name      = TRIM(
                       v_new_last || ', ' || v_new_first
                       || CASE WHEN v_new_middle IS NOT NULL
                               THEN ' ' || v_new_middle
                               ELSE '' END
                     ),
    updated_at     = NOW(),
    updated_by     = v_profile_id
  WHERE id = p_applicant_id;

  -- Write immutable change history (no request_id for direct overrides)
  IF v_changed != '{}' THEN
    INSERT INTO public.applicant_profile_change_history (
      applicant_id,
      request_id,
      changed_fields,
      changed_by,
      approved_by,
      reason,
      changed_at,
      source_module
    ) VALUES (
      p_applicant_id,
      NULL,
      v_changed,
      v_profile_id,
      v_profile_id,
      p_reason,
      NOW(),
      'super_admin_override'
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_coverage_slot_hr_processing_to_open(p_coverage_slot_id uuid, p_hr_emploc_id uuid DEFAULT NULL::uuid, p_deletion_reason text DEFAULT NULL::text, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF p_coverage_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_coverage_slot');
  END IF;

  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => p_coverage_slot_id,
    p_new_status   => 'open',
    p_performed_by => p_performed_by,
    p_remarks      => format(
      'Phase R-C / %s / hr_processing->open (backout) / coverage_slot=%s / '
      'hr_emploc=%s / reason=%s',
      COALESCE(p_source_fn, 'fn_sync_coverage_slot_hr_processing_to_open'),
      p_coverage_slot_id, p_hr_emploc_id, p_deletion_reason
    )
  ) INTO v_result;

  IF (v_result->>'status') = 'blocked' THEN
    RAISE NOTICE
      'fn_sync_coverage_slot_hr_processing_to_open: blocked for coverage_slot=% hr_emploc=% source=% — %',
      p_coverage_slot_id, p_hr_emploc_id, p_source_fn, v_result->>'blocked_reason';
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_coverage_slot_hr_processing_to_open: error for coverage_slot=% hr_emploc=% source=% — % (sqlstate=%)',
    p_coverage_slot_id, p_hr_emploc_id, p_source_fn, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_coverage_slot_to_active(p_coverage_slot_id uuid, p_plantilla_id uuid, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF p_coverage_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_coverage_slot');
  END IF;

  IF p_plantilla_id IS NULL THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason', 'plantilla_id_required',
      'slot_id', p_coverage_slot_id);
  END IF;

  SELECT public.fn_set_coverage_slot_status(
    p_slot_id               => p_coverage_slot_id,
    p_new_status            => 'active',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
      'Phase R-D / %s / hr_processing->active / coverage_slot=%s / plantilla=%s',
      COALESCE(p_source_fn, 'fn_sync_coverage_slot_to_active'),
      p_coverage_slot_id,
      p_plantilla_id
    ),
    p_occupant_plantilla_id => p_plantilla_id
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_coverage_slot_to_active: % for coverage_slot=% plantilla=% source=% reason=%',
      v_result->>'status',
      p_coverage_slot_id,
      p_plantilla_id,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', v_result->>'reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_coverage_slot_to_active: error for coverage_slot=% plantilla=% source=% — % (sqlstate=%)',
    p_coverage_slot_id,
    p_plantilla_id,
    COALESCE(p_source_fn, 'unknown'),
    SQLERRM,
    SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_coverage_slot_to_hr_processing(p_coverage_slot_id uuid, p_applicant_id uuid DEFAULT NULL::uuid, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF p_coverage_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_coverage_slot');
  END IF;

  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => p_coverage_slot_id,
    p_new_status   => 'hr_processing',
    p_performed_by => p_performed_by,
    p_remarks      => format(
      'Phase R-C / %s / pipeline->hr_processing / coverage_slot=%s / applicant=%s',
      COALESCE(p_source_fn, 'fn_sync_coverage_slot_to_hr_processing'),
      p_coverage_slot_id, p_applicant_id
    )
  ) INTO v_result;

  IF (v_result->>'status') = 'blocked' THEN
    RAISE NOTICE
      'fn_sync_coverage_slot_to_hr_processing: blocked for coverage_slot=% applicant=% source=% — %',
      p_coverage_slot_id, p_applicant_id, p_source_fn, v_result->>'blocked_reason';
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_coverage_slot_to_hr_processing: error for coverage_slot=% applicant=% source=% — % (sqlstate=%)',
    p_coverage_slot_id, p_applicant_id, p_source_fn, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_employee_store_allocations(p_employee_no text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_has_live   boolean;
  v_cnt        integer;
  v_each       numeric(8,4);
  v_remainder  numeric(8,4);
  v_first_id   uuid;
  v_total      numeric;
BEGIN
  IF p_employee_no IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT
    EXISTS (
      SELECT 1 FROM public.plantilla m
       WHERE m.employee_no = p_employee_no
         AND m.is_deleted = false
         AND COALESCE(m.is_archived, false) = false
         AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
         AND m.source_employee_import_batch_id IS NULL
         AND m.source_baseline_import_batch_id IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM public.employee_store_allocations a
       WHERE a.employee_no = p_employee_no
         AND a.is_active
         AND a.source_import_batch_id IS NULL
    )
  INTO v_has_live;

  IF NOT v_has_live THEN
    RETURN NULL;
  END IF;

  WITH masters AS (
    SELECT m.id AS plantilla_id, m.deployment_type, m.roving_assignment_id,
           m.store_id, m.vcode, m.store_name, m.account_id, m.hr_emploc_id,
           m.coverage_group_id
    FROM public.plantilla m
    WHERE m.employee_no = p_employee_no
      AND m.is_deleted = false
      AND COALESCE(m.is_archived, false) = false
      AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
      AND m.source_employee_import_batch_id IS NULL
      AND m.source_baseline_import_batch_id IS NULL
  ),
  footprints AS (
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    SELECT m.plantilla_id, hsl.vcode, hsl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint
    FROM masters m
    JOIN public.hr_emploc_store_links hsl
      ON hsl.deleted_at IS NULL
     AND hsl.status = 'Confirmed'
     AND (
       hsl.hr_emploc_id = m.hr_emploc_id
       OR hsl.roving_assignment_id = m.roving_assignment_id
     )
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           s.id AS store_id_hint, m.account_id AS account_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.coverage_group_id = m.coverage_group_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    LEFT JOIN public.stores s ON upper(s.vcode) = upper(psl.vcode) AND s.is_active = true
    WHERE m.deployment_type = 'Roving'
      AND m.coverage_group_id IS NOT NULL
      AND m.roving_assignment_id IS NULL
    UNION ALL
    SELECT m.plantilla_id, m.vcode, m.store_name,
           m.store_id AS store_id_hint, m.account_id AS account_id_hint
    FROM masters m
    WHERE NOT (m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL)
      AND NOT (m.deployment_type = 'Roving' AND m.coverage_group_id IS NOT NULL AND m.roving_assignment_id IS NULL)
      AND m.vcode IS NOT NULL
  ),
  resolved AS (
    SELECT DISTINCT ON (f.plantilla_id, upper(f.vcode))
           f.plantilla_id, f.vcode
    FROM footprints f
    WHERE f.vcode IS NOT NULL
  )
  UPDATE public.employee_store_allocations esa
     SET is_active = false,
         effective_end = CURRENT_DATE
   WHERE esa.employee_no = p_employee_no
     AND esa.is_active
     AND esa.source_import_batch_id IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM resolved r
       WHERE r.plantilla_id = esa.plantilla_id
         AND upper(r.vcode) = upper(esa.vcode)
     );

  WITH masters AS (
    SELECT m.id AS plantilla_id, m.deployment_type, m.roving_assignment_id,
           m.store_id, m.vcode, m.store_name, m.account_id, m.hr_emploc_id,
           m.coverage_group_id
    FROM public.plantilla m
    WHERE m.employee_no = p_employee_no
      AND m.is_deleted = false
      AND COALESCE(m.is_archived, false) = false
      AND m.status IN ('Active','On Leave','For Deactivation','Pending Deactivation')
      AND m.source_employee_import_batch_id IS NULL
      AND m.source_baseline_import_batch_id IS NULL
  ),
  footprints AS (
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint,
           NULL::uuid AS coverage_group_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    SELECT m.plantilla_id, hsl.vcode, hsl.store_name,
           NULL::uuid AS store_id_hint, NULL::uuid AS account_id_hint,
           NULL::uuid AS coverage_group_id_hint
    FROM masters m
    JOIN public.hr_emploc_store_links hsl
      ON hsl.deleted_at IS NULL
     AND hsl.status = 'Confirmed'
     AND (
       hsl.hr_emploc_id = m.hr_emploc_id
       OR hsl.roving_assignment_id = m.roving_assignment_id
     )
    WHERE m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL
    UNION ALL
    SELECT m.plantilla_id, psl.vcode, psl.store_name,
           s.id AS store_id_hint, m.account_id AS account_id_hint,
           m.coverage_group_id AS coverage_group_id_hint
    FROM masters m
    JOIN public.plantilla_store_links psl
      ON psl.plantilla_id = m.plantilla_id
     AND psl.coverage_group_id = m.coverage_group_id
     AND psl.status = 'Active'
     AND psl.deleted_at IS NULL
    LEFT JOIN public.stores s ON upper(s.vcode) = upper(psl.vcode) AND s.is_active = true
    WHERE m.deployment_type = 'Roving'
      AND m.coverage_group_id IS NOT NULL
      AND m.roving_assignment_id IS NULL
    UNION ALL
    SELECT m.plantilla_id, m.vcode, m.store_name,
           m.store_id AS store_id_hint, m.account_id AS account_id_hint,
           NULL::uuid AS coverage_group_id_hint
    FROM masters m
    WHERE NOT (m.deployment_type = 'Roving' AND m.roving_assignment_id IS NOT NULL)
      AND NOT (m.deployment_type = 'Roving' AND m.coverage_group_id IS NOT NULL AND m.roving_assignment_id IS NULL)
      AND m.vcode IS NOT NULL
  ),
  resolved AS (
    SELECT DISTINCT ON (f.plantilla_id, upper(f.vcode))
           f.plantilla_id,
           f.vcode,
           COALESCE(f.store_id_hint, st.id, va.store_id)        AS store_id,
           COALESCE(st.store_name, f.store_name)                AS store_name,
           COALESCE(f.account_id_hint, st.account_id, va.account_id) AS account_id,
           COALESCE(st.group_id, acc.group_id)                  AS group_id,
           f.coverage_group_id_hint                              AS roving_group_id
    FROM footprints f
    LEFT JOIN LATERAL (
      SELECT s.id, s.store_name, s.account_id, s.group_id
      FROM public.stores s
      WHERE upper(s.vcode) = upper(f.vcode) AND s.is_active = true
      ORDER BY s.created_at
      LIMIT 1
    ) st ON true
    LEFT JOIN LATERAL (
      SELECT v.store_id, v.account_id
      FROM public.vacancies v
      WHERE v.vcode = f.vcode
      ORDER BY v.created_at
      LIMIT 1
    ) va ON true
    LEFT JOIN public.accounts acc
      ON acc.id = COALESCE(f.account_id_hint, st.account_id, va.account_id)
    WHERE f.vcode IS NOT NULL
  )
  INSERT INTO public.employee_store_allocations (
    plantilla_id, employee_no, roving_group_id,
    store_id, vcode, store_name,
    account_id, group_id,
    filled_hc, active_store_count,
    effective_start, is_active,
    source_import_batch_id, created_by
  )
  SELECT
    r.plantilla_id, p_employee_no, r.roving_group_id,
    r.store_id, r.vcode, r.store_name,
    r.account_id, r.group_id,
    1, 1,
    CURRENT_DATE, true,
    NULL, NULL
  FROM resolved r
  WHERE NOT EXISTS (
    SELECT 1 FROM public.employee_store_allocations e
    WHERE e.employee_no = p_employee_no
      AND e.is_active
      AND e.plantilla_id = r.plantilla_id
      AND upper(e.vcode) = upper(r.vcode)
  );

  WITH ranked AS (
    SELECT e.id,
           row_number() OVER (
             PARTITION BY e.employee_no, e.plantilla_id, upper(COALESCE(e.vcode, ''))
             ORDER BY e.effective_start, e.created_at, e.id
           ) AS rn
    FROM public.employee_store_allocations e
    WHERE e.employee_no = p_employee_no
      AND e.is_active
      AND e.source_import_batch_id IS NULL
  )
  UPDATE public.employee_store_allocations e
     SET is_active = false,
         effective_end = CURRENT_DATE
    FROM ranked r
   WHERE e.id = r.id
     AND r.rn > 1;

  SELECT count(*) INTO v_cnt
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL;

  IF v_cnt = 0 THEN
    RETURN 0;
  END IF;

  v_each      := round(1.0 / v_cnt, 4);
  v_remainder := round(1.0 - (v_each * v_cnt), 4);

  SELECT id INTO v_first_id
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL
  ORDER BY effective_start, created_at, id
  LIMIT 1;

  UPDATE public.employee_store_allocations
     SET active_store_count = v_cnt,
         filled_hc = CASE WHEN id = v_first_id THEN v_each + v_remainder ELSE v_each END
   WHERE employee_no = p_employee_no
     AND is_active
     AND source_import_batch_id IS NULL;

  SELECT COALESCE(sum(filled_hc), 0) INTO v_total
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no
    AND is_active
    AND source_import_batch_id IS NULL;

  RETURN v_total;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_slot_hr_processing_to_open(p_vcode text, p_hr_emploc_id uuid DEFAULT NULL::uuid, p_deletion_reason text DEFAULT NULL::text, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text, p_slot_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  Phase C upgrade — non-blocking hr_processing→open slot sync (OHM2026_0045).

  Phase C adds p_slot_id: when non-NULL (v_emp.slot_id captured before the
  emploc archive in fn_approve_emploc_deletion_request), the exact slot is
  used directly — no legacy_vcode LIMIT 1 lookup, slot_ordinal preserved,
  aging restarts correctly (OHM2026_0044 §Q5).
  When NULL (legacy no-slot HR Emploc row / roving / hr_emploc_id was NULL),
  falls back to the Phase 6.5 VCODE LIMIT 1 legacy path.

  Called only for Backout deletion type — Duplicate Record is excluded by the
  host RPC guard (IF v_req.deletion_type = 'Backout').

  Reason code: REPLACEMENT (task-specified for Phase 6.5/C, per OHM2026_0023/0045).
  new_value='open' written to slot_history → aging episode restarts.
*/
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN

  -- ── Phase C: exact slot_id path ─────────────────────────────────────────
  IF p_slot_id IS NOT NULL THEN
    SELECT public.fn_set_slot_status(
      p_slot_id               => p_slot_id,
      p_new_status            => 'open',
      p_reason_code           => 'REPLACEMENT',
      p_performed_by          => p_performed_by,
      p_remarks               => format(
        'Phase C / %s / VCODE=%s / hr_emploc_id=%s / reason=%s / slot_id=%s',
        COALESCE(p_source_fn,       'unknown'),
        COALESCE(p_vcode,           'unknown'),
        COALESCE(p_hr_emploc_id::text, 'null'),
        COALESCE(p_deletion_reason, 'null'),
        p_slot_id
      ),
      p_occupant_plantilla_id => NULL
    ) INTO v_result;

    IF (v_result->>'status') IN ('blocked', 'no_op') THEN
      RAISE NOTICE
        'fn_sync_slot_hr_processing_to_open (exact): % for slot_id=% VCODE=% source=% — %',
        v_result->>'status',
        p_slot_id,
        COALESCE(p_vcode, 'unknown'),
        COALESCE(p_source_fn, 'unknown'),
        COALESCE(v_result->>'blocked_reason', 'same-state no_op');
    END IF;

    RETURN v_result;
  END IF;

  -- ── Legacy path: VCODE LIMIT 1 (Phase 6.5 — no-slot VCODEs, roving) ────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_slot_hr_processing_to_open: skipped — p_vcode null/empty '
      'and p_slot_id null (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- Locate slot via legacy_vcode bridge (non-roving only).
  SELECT id INTO v_slot_id
  FROM   public.plantilla_slots
  WHERE  legacy_vcode = p_vcode
    AND  is_roving    = false
  LIMIT  1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'open',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
      'Phase 6.5 (legacy vcode path) / %s / VCODE=%s / hr_emploc_id=%s / reason=%s',
      COALESCE(p_source_fn,       'unknown'),
      p_vcode,
      COALESCE(p_hr_emploc_id::text, 'null'),
      COALESCE(p_deletion_reason, 'null')
    ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_hr_processing_to_open (legacy): % for slot_id=% VCODE=% source=% — %',
      v_result->>'status',
      v_slot_id,
      p_vcode,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_slot_hr_processing_to_open: error for VCODE=% slot_id=% source=% — % (sqlstate=%)',
    COALESCE(p_vcode, 'null'),
    COALESCE(p_slot_id::text, 'null'),
    COALESCE(p_source_fn, 'unknown'),
    SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_hr_processing(p_vcode text, p_applicant_id uuid DEFAULT NULL::uuid, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text, p_slot_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  Phase C upgrade — non-blocking pipeline→hr_processing slot sync (OHM2026_0045).

  Phase C adds p_slot_id: when non-NULL, the exact slot is used directly —
  no legacy_vcode LIMIT 1 lookup, no slot ambiguity under N-slot VCODEs.
  When NULL (no-slot VCODE, roving, pre-backfill edge row), falls back to
  the Phase 6.2 VCODE LIMIT 1 legacy path.

  Asymmetry vs Phase B (deliberate, per OHM2026_0044 §Q3):
    • Phase B create_applicant_and_link_to_vacancy: slot transition is the
      PRIMARY operation → blocked transition rolls back the insert.
    • Here (Confirmed Onboard): slot transition is a DOWNSTREAM SIDE EFFECT
      of an already-authorised workflow hand-off → blocked/no_op transitions
      are logged via RAISE NOTICE, never raised into the host RPC.

  Reason code: REPLACEMENT (task-specified for the pipeline→hr_processing
  transition, per OHM2026_0020/0045).
*/
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN

  -- ── Phase C: exact slot_id path ─────────────────────────────────────────
  IF p_slot_id IS NOT NULL THEN
    SELECT public.fn_set_slot_status(
      p_slot_id               => p_slot_id,
      p_new_status            => 'hr_processing',
      p_reason_code           => 'REPLACEMENT',
      p_performed_by          => p_performed_by,
      p_remarks               => format(
        'Phase C / %s / VCODE=%s / applicant_id=%s / slot_id=%s',
        COALESCE(p_source_fn,    'unknown'),
        COALESCE(p_vcode,        'unknown'),
        COALESCE(p_applicant_id::text, 'null'),
        p_slot_id
      ),
      p_occupant_plantilla_id => NULL
    ) INTO v_result;

    IF (v_result->>'status') IN ('blocked', 'no_op') THEN
      RAISE NOTICE
        'fn_sync_slot_to_hr_processing (exact): % for slot_id=% VCODE=% source=% — %',
        v_result->>'status',
        p_slot_id,
        COALESCE(p_vcode, 'unknown'),
        COALESCE(p_source_fn, 'unknown'),
        COALESCE(v_result->>'blocked_reason', 'same-state no_op');
    END IF;

    RETURN v_result;
  END IF;

  -- ── Legacy path: VCODE LIMIT 1 (Phase 6.2 — no-slot VCODEs, roving) ────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_slot_to_hr_processing: skipped — p_vcode null/empty '
      'and p_slot_id null (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- Locate slot via legacy_vcode bridge (non-roving only).
  SELECT id INTO v_slot_id
  FROM   public.plantilla_slots
  WHERE  legacy_vcode = p_vcode
    AND  is_roving    = false
  LIMIT  1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'hr_processing',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
      'Phase 6.2 (legacy vcode path) / %s / VCODE=%s / applicant_id=%s',
      COALESCE(p_source_fn,    'unknown'),
      p_vcode,
      COALESCE(p_applicant_id::text, 'null')
    ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_hr_processing (legacy): % for slot_id=% VCODE=% source=% — %',
      v_result->>'status',
      v_slot_id,
      p_vcode,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_slot_to_hr_processing: error for VCODE=% slot_id=% source=% — % (sqlstate=%)',
    COALESCE(p_vcode, 'null'),
    COALESCE(p_slot_id::text, 'null'),
    COALESCE(p_source_fn, 'unknown'),
    SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_occupied(p_vcode text, p_hr_emploc_id uuid DEFAULT NULL::uuid, p_plantilla_id uuid DEFAULT NULL::uuid, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: skipped - p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  IF p_plantilla_id IS NULL THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: skipped - p_plantilla_id is null, cannot set occupant link (VCODE=%, source=%)',
      p_vcode, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  SELECT id INTO v_slot_id
    FROM public.plantilla_slots
   WHERE legacy_vcode = p_vcode
     AND COALESCE(is_roving, false) = false
     AND slot_status IN ('hr_processing', 'pipeline', 'open')
   ORDER BY CASE slot_status
              WHEN 'hr_processing' THEN 1
              WHEN 'pipeline' THEN 2
              WHEN 'open' THEN 3
              ELSE 4
            END,
            created_at,
            id
   LIMIT 1;

  IF v_slot_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'occupied',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'OHM2026_0090 / %s / VCODE=%s / hr_emploc_id=%s / plantilla_id=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_vcode,
                                 COALESCE(p_hr_emploc_id::text, 'null'),
                                 p_plantilla_id::text
                               ),
    p_occupant_plantilla_id => p_plantilla_id
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: % for slot_id=% VCODE=% plantilla_id=% source=% - %',
      v_result->>'status',
      v_slot_id,
      p_vcode,
      p_plantilla_id,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_slot_to_occupied: error for VCODE=% plantilla_id=% source=% - % (sqlstate=%)',
    p_vcode, p_plantilla_id, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_open(p_plantilla_id uuid, p_reason_code text DEFAULT 'RESIGNED'::text, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  Phase 6.4 — non-blocking occupied→open slot sync (OHM2026_0022).

  Locates the slot by current_occupant_plantilla_id first (authoritative),
  falling back to legacy_vcode (1:1 bridge, non-roving only).
  Delegates to fn_set_slot_status with:
    p_new_status            = 'open'
    p_occupant_plantilla_id = NULL  (cleared automatically by fn_set_slot_status)

  Blocked or no_op results from fn_set_slot_status are logged via
  RAISE NOTICE and returned as-is — they never raise into the host RPC.
*/
DECLARE
  v_plantilla_row record;
  v_slot_id       uuid;
  v_result        jsonb;
BEGIN
  -- ── Guard: plantilla_id required ───────────────────────────────────────
  IF p_plantilla_id IS NULL THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: skipped — p_plantilla_id is null (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Fetch plantilla row (vcode, deployment_type, employee_no) ───────────
  -- We read even if the row is now Inactive/Deactivated (the host RPC
  -- already committed the status change before calling this helper).
  SELECT id, vcode, deployment_type, employee_no
    INTO v_plantilla_row
    FROM public.plantilla
   WHERE id = p_plantilla_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: plantilla % not found, skipped (source=%)',
      p_plantilla_id, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Roving carve-out (OHM2026_0017 Q6) ──────────────────────────────────
  -- Roving slots have N VCODEs → 1 slot; no reliable 1:1 mapping until the
  -- deferred roving coverage model lands. Skip unconditionally.
  IF COALESCE(v_plantilla_row.deployment_type, '') = 'Roving' THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: skipped — roving plantilla % not in Phase 6.4 scope (source=%)',
      p_plantilla_id, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Locate slot: occupant link preferred, legacy_vcode fallback ──────────
  -- Phase 6.3 sets current_occupant_plantilla_id when hr_processing→occupied.
  -- For pre-Phase-6.3 slots (backfilled to occupied but no occupant link),
  -- fall back to the 1:1 legacy_vcode bridge.
  SELECT id INTO v_slot_id
    FROM public.plantilla_slots
   WHERE current_occupant_plantilla_id = p_plantilla_id
     AND is_roving = false
  LIMIT 1;

  -- Fallback: locate by legacy_vcode bridge (non-roving, non-null VCODE)
  IF v_slot_id IS NULL AND v_plantilla_row.vcode IS NOT NULL THEN
    SELECT id INTO v_slot_id
      FROM public.plantilla_slots
     WHERE legacy_vcode = v_plantilla_row.vcode
       AND is_roving    = false
    LIMIT 1;
  END IF;

  IF v_slot_id IS NULL THEN
    -- No slot for this plantilla (pre-slot-era legacy vacancy, roving, or pool).
    -- Skip silently — not an error; normal for records predating the slot model.
    RETURN NULL;
  END IF;

  -- ── Delegate to central transition helper ────────────────────────────────
  -- fn_set_slot_status handles: matrix validation, slot row update
  -- (slot_status = 'open', current_occupant_plantilla_id = NULL, updated_at/by),
  -- and slot_history append with new_value='open' (→ aging episode restarts).
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'open',
    p_reason_code           => p_reason_code,
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.4 / %s / plantilla_id=%s / employee_no=%s / reason=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_plantilla_id::text,
                                 COALESCE(v_plantilla_row.employee_no, 'null'),
                                 COALESCE(p_reason_code, 'null')
                               ),
    p_occupant_plantilla_id => NULL  -- occupant cleared on any separation/deactivation
  ) INTO v_result;

  -- Log blocked/no_op outcomes for observability; never raise.
  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: % for slot_id=% plantilla_id=% source=% — %',
      v_result->>'status',
      v_slot_id,
      p_plantilla_id,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_slot_to_open: error for plantilla_id=% source=% — % (sqlstate=%)',
    p_plantilla_id, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sync_vacancy_slot_open_pipeline(p_vcode text, p_performed_by uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  Phase 6.1 — non-blocking open↔pipeline slot sync (OHM2026_0019).

  Active-applicant predicate mirrors vw_vacancy_list:
    fn_is_active_vacancy_applicant_status → new, for_interview,
    for_requirements, for_onboard.

  Reason code is NULL for both open→pipeline and pipeline→open:
  these transitions have no matching reason code in the design matrix
  (slot_lifecycle_automation_plan.md Q2/Q3 — "(none)").
  Context is fully captured in p_remarks via source function + VCODE + count.
*/
DECLARE
  v_slot_id    uuid;
  v_active_cnt bigint;
  v_target     text;
  v_result     jsonb;
BEGIN
  -- ── Guard: VCODE required ───────────────────────────────────────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_vacancy_slot_open_pipeline: skipped — p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Locate slot via legacy_vcode bridge ──────────────────────────
  -- Partial-unique index on legacy_vcode guarantees at most one match.
  -- Roving slots excluded: no reliable 1:1 VCODE→slot until coverage model.
  SELECT id INTO v_slot_id
  FROM public.plantilla_slots
  WHERE legacy_vcode = p_vcode
    AND is_roving = false
  LIMIT 1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  -- ── Count active applicants for this VCODE (post-host-write) ────
  SELECT count(*) INTO v_active_cnt
  FROM public.applicants
  WHERE vacancy_vcode = p_vcode
    AND public.fn_is_active_vacancy_applicant_status(status)
    AND COALESCE(is_archived, false) = false;

  -- ── Derive target slot status ────────────────────────────────────
  v_target := CASE WHEN v_active_cnt > 0 THEN 'pipeline' ELSE 'open' END;

  -- ── Delegate to central transition helper ───────────────────────
  -- fn_set_slot_status handles: same-state no-op, matrix validation,
  -- slot row update (slot_status + updated_at/by), and slot_history append.
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => v_target,
    p_reason_code           => NULL,
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.1 / %s / VCODE=%s / active_applicants=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_vcode,
                                 v_active_cnt
                               ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_vacancy_slot_open_pipeline: error for VCODE=% source=% — % (sqlstate=%)',
    p_vcode, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_team_performance_detail(p_group_id uuid DEFAULT NULL::uuid, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(account_id uuid, account_name text, group_id uuid, group_name text, hrco_name text, issue_category text, issue_label text, issue_detail text, days_impacted integer, store_name text, employee_name text, vcode text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authenticated access required';
  END IF;

  RETURN QUERY
  WITH
  base_accounts AS (
    SELECT
      a.id           AS acct_id,
      a.account_name AS acct_name,
      g.id           AS grp_id,
      g.group_name   AS grp_name,
      (
        SELECT up.full_name FROM users_profile up
        WHERE up.id = a.hrco_user_id LIMIT 1
      ) AS hrco
    FROM accounts a
    JOIN groups g ON g.id = a.group_id
    WHERE
      (p_group_id   IS NULL OR g.id = p_group_id)
      AND (p_account_id IS NULL OR a.id = p_account_id)
      AND (
        i_have_full_access()
        OR a.account_name = ANY(get_my_allowed_accounts())
      )
  ),

  aged_issues AS (
    SELECT
      ba.acct_id,
      ba.acct_name,
      ba.grp_id,
      ba.grp_name,
      ba.hrco,
      'aged_vacancy'::text                    AS cat,
      'Aged Vacancy'::text                    AS lbl,
      'Open vacancy older than 30 days'::text AS dtl,
      (CURRENT_DATE - COALESCE(v.vacant_date, v.created_at)::date) AS days,
      COALESCE(v.store_name, v.account)::text AS store,
      NULL::text                              AS emp,
      v.vcode::text                           AS vc
    FROM vacancies v
    JOIN base_accounts ba ON ba.acct_id = v.account_id
    WHERE v.status = 'Open'
      AND v.deleted_at IS NULL
      AND v.archived_at IS NULL
      AND COALESCE(v.vacant_date, v.created_at)::date < CURRENT_DATE - INTERVAL '30 days'
  ),

  late_hr_issues AS (
    SELECT
      ba.acct_id,
      ba.acct_name,
      ba.grp_id,
      ba.grp_name,
      ba.hrco,
      'late_hr'::text                                                   AS cat,
      'Late HR Update'::text                                            AS lbl,
      'Separation recorded more than 7 days after effective date'::text AS dtl,
      (p.updated_at::date - p.date_of_separation)::int                 AS days,
      COALESCE(p.store_name, '')::text                                  AS store,
      COALESCE(p.employee_name, '')::text                               AS emp,
      NULL::text                                                        AS vc
    FROM plantilla p
    JOIN base_accounts ba ON ba.acct_id = p.account_id
    WHERE p.date_of_separation IS NOT NULL
      AND p.is_deleted = false
      AND (p.updated_at::date - p.date_of_separation) > 7
  )

  SELECT acct_id, acct_name, grp_id, grp_name, hrco, cat, lbl, dtl, days, store, emp, vc
  FROM aged_issues
  UNION ALL
  SELECT acct_id, acct_name, grp_id, grp_name, hrco, cat, lbl, dtl, days, store, emp, vc
  FROM late_hr_issues
  ORDER BY acct_name, cat, days DESC NULLS LAST;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_team_performance_summary(p_group_id uuid DEFAULT NULL::uuid, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authenticated access required';
  END IF;

  WITH
  base_accounts AS (
    SELECT
      a.id           AS account_id,
      a.account_name,
      g.id           AS group_id,
      g.group_name,
      (
        SELECT up.full_name
        FROM users_profile up
        WHERE up.id = a.hrco_user_id
        LIMIT 1
      ) AS hrco_name
    FROM accounts a
    JOIN groups g ON g.id = a.group_id
    WHERE
      (p_group_id   IS NULL OR g.id = p_group_id)
      AND (p_account_id IS NULL OR a.id = p_account_id)
      AND (
        i_have_full_access()
        OR a.account_name = ANY(get_my_allowed_accounts())
      )
  ),

  actual_hc AS (
    SELECT account_id, COUNT(*) AS hc
    FROM plantilla
    WHERE status IN ('Active', 'On Leave')
      AND is_deleted = false
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  vacant_hc AS (
    SELECT account_id, COUNT(*) AS hc
    FROM vacancies
    WHERE status = 'Open'
      AND deleted_at IS NULL
      AND archived_at IS NULL
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  aged_vac AS (
    SELECT account_id, COUNT(*) AS cnt
    FROM vacancies
    WHERE status = 'Open'
      AND deleted_at IS NULL
      AND archived_at IS NULL
      AND COALESCE(vacant_date, created_at)::date < CURRENT_DATE - INTERVAL '30 days'
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  late_hr AS (
    SELECT account_id, COUNT(*) AS cnt
    FROM plantilla
    WHERE date_of_separation IS NOT NULL
      AND is_deleted = false
      AND (updated_at::date - date_of_separation) > 7
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  metrics AS (
    SELECT
      ba.account_id,
      ba.account_name,
      ba.group_id,
      ba.group_name,
      ba.hrco_name,
      COALESCE(ah.hc,  0) AS actual_hc,
      COALESCE(vh.hc,  0) AS vacant_hc,
      COALESCE(ah.hc,  0) + COALESCE(vh.hc, 0) AS required_hc,
      COALESCE(av.cnt, 0) AS aged_vacancies,
      COALESCE(lh.cnt, 0) AS late_hr_updates
    FROM base_accounts ba
    LEFT JOIN actual_hc ah ON ah.account_id = ba.account_id
    LEFT JOIN vacant_hc vh ON vh.account_id = ba.account_id
    LEFT JOIN aged_vac  av ON av.account_id = ba.account_id
    LEFT JOIN late_hr   lh ON lh.account_id = ba.account_id
  ),

  scored AS (
    SELECT
      *,
      CASE
        WHEN required_hc = 0 THEN 0.0
        ELSE LEAST(1.0, actual_hc::float / required_hc::float)
      END AS mfr,
      GREATEST(0, LEAST(100,
        100
        - CASE
            WHEN required_hc = 0 THEN 0
            WHEN actual_hc::float / required_hc::float < 0.70 THEN 30
            WHEN actual_hc::float / required_hc::float < 0.80 THEN 20
            WHEN actual_hc::float / required_hc::float < 0.90 THEN 10
            WHEN actual_hc::float / required_hc::float < 0.95 THEN 5
            ELSE 0
          END
        - LEAST(aged_vacancies * 3, 20)
        - LEAST(late_hr_updates * 5, 15)
      )) AS score
    FROM metrics
  ),

  final AS (
    SELECT
      *,
      CASE
        WHEN score >= 90 THEN 'Excellent'
        WHEN score >= 80 THEN 'Good'
        WHEN score >= 70 THEN 'Watch'
        ELSE 'Critical'
      END AS severity
    FROM scored
  )

  SELECT jsonb_build_object(
    'kpis', jsonb_build_object(
      'best_group',         (SELECT account_name FROM final ORDER BY score DESC, account_name LIMIT 1),
      'best_group_score',   (SELECT score          FROM final ORDER BY score DESC, account_name LIMIT 1),
      'lowest_group',       (SELECT account_name FROM final ORDER BY score ASC,  account_name LIMIT 1),
      'lowest_group_score', (SELECT score          FROM final ORDER BY score ASC,  account_name LIMIT 1),
      'average_score',      ROUND(COALESCE((SELECT AVG(score) FROM final), 0)::numeric, 1),
      'critical_count',     (SELECT COUNT(*) FROM final WHERE score < 70)
    ),
    'leaderboard', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'account_id',      account_id,
            'account_name',    account_name,
            'group_id',        group_id,
            'group_name',      group_name,
            'hrco_name',       hrco_name,
            'score',           score,
            'severity',        severity,
            'mfr',             mfr,
            'aged_vacancies',  aged_vacancies,
            'late_hr_updates', late_hr_updates,
            'actual_hc',       actual_hc,
            'vacant_hc',       vacant_hc,
            'required_hc',     required_hc
          )
          ORDER BY score DESC, account_name
        )
        FROM final
      ),
      '[]'::jsonb
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_trg_applicant_insert_slot_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Guard: only sync for active, non-archived applicants with a VCODE.
  -- Archived inserts (is_archived = true at insert time, e.g. Backout)
  -- and rows with no VCODE (should not exist) are skipped silently.
  IF COALESCE(NEW.is_archived, false) = false
    AND NEW.vacancy_vcode IS NOT NULL
    AND btrim(NEW.vacancy_vcode) <> ''
    AND public.fn_is_active_vacancy_applicant_status(NEW.status)
  THEN
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => NEW.vacancy_vcode,
      p_performed_by => COALESCE(NEW.created_by, NEW.updated_by),
      p_source_fn    => 'trg_applicant_insert_slot_sync'
    );
  END IF;
  -- AFTER trigger: return value is ignored for row triggers.
  RETURN NULL;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: never roll back the host INSERT.
  RAISE NOTICE
    'fn_trg_applicant_insert_slot_sync: unexpected error for applicant=% vcode=% — % (sqlstate=%)',
    NEW.id, NEW.vacancy_vcode, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_trg_auto_create_vacancy_slot()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_required_hc  int;
  v_max_ordinal  int;
  v_slot_id      uuid;
  v_store_id     uuid;
  v_ordinal      int;
  v_slot_status  text;
  v_aging_ts     timestamptz;
  v_emp_type     text;
BEGIN
  -- Only fire for non-pool, non-deleted, non-roving, VCODE-bearing vacancies
  -- that have affects_required_hc = true (or NULL, which defaults to true).
  IF COALESCE(NEW.is_pool_vacancy, false)       = true  THEN RETURN NEW; END IF;
  IF NEW.deleted_at IS NOT NULL                          THEN RETURN NEW; END IF;
  IF NEW.vcode IS NULL                                   THEN RETURN NEW; END IF;
  IF COALESCE(NEW.affects_required_hc, true)    = false THEN RETURN NEW; END IF;

  -- Only fire when the vacancy is entering or staying at Open/Pipeline
  IF lower(NEW.status) NOT IN ('open', 'pipeline') THEN RETURN NEW; END IF;

  -- On UPDATE: skip if status did not change to/from an open state
  -- (avoids re-firing on unrelated column updates when status is already Open)
  IF TG_OP = 'UPDATE' THEN
    IF lower(OLD.status) = lower(NEW.status) THEN
      -- Status unchanged — only re-evaluate if required_headcount increased
      IF COALESCE(NEW.required_headcount, 1) <= COALESCE(OLD.required_headcount, 1) THEN
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  v_required_hc := GREATEST(COALESCE(NEW.required_headcount, 1), 1);
  v_slot_status  := CASE
                      WHEN lower(NEW.status) = 'pipeline' THEN 'pipeline'
                      ELSE 'open'
                    END;
  v_aging_ts     := COALESCE(NEW.vacant_date::timestamptz, now());
  v_emp_type     := COALESCE(NEW.employment_type, 'stationary');

  -- Resolve store_id, prioritizing NEW.store_id (fix: ohm#9x4p2k7q)
  -- Previously only did VCode lookup, causing NULL store_id for new stores
  -- where stores.vcode had not yet been set.
  IF NEW.store_id IS NOT NULL THEN
    v_store_id := NEW.store_id;
  ELSE
    SELECT s.id INTO v_store_id
    FROM public.stores s
    WHERE upper(s.vcode) = upper(NEW.vcode)
      AND s.status = 'active'
    ORDER BY s.created_at
    LIMIT 1;
  END IF;

  -- Determine how many slots already exist for this VCODE
  SELECT COALESCE(MAX(ps.slot_ordinal), 0) INTO v_max_ordinal
  FROM public.plantilla_slots ps
  WHERE ps.legacy_vcode = NEW.vcode;

  -- Create only the missing ordinals (v_max_ordinal+1 .. required_hc)
  FOR v_ordinal IN (v_max_ordinal + 1) .. v_required_hc LOOP
    -- Idempotency guard
    IF EXISTS (
      SELECT 1 FROM public.plantilla_slots ps2
      WHERE ps2.legacy_vcode = NEW.vcode
        AND ps2.slot_ordinal = v_ordinal
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,
      legacy_vcode,
      source_hc_request_id,
      created_at,
      updated_at
    ) VALUES (
      v_store_id,
      NEW.account_id,
      NEW.group_id,
      COALESCE(NEW.position, ''),
      v_emp_type,
      false,
      v_slot_status,
      v_ordinal::smallint,
      NEW.vcode,
      NULL,
      now(),
      now()
    )
    RETURNING id INTO v_slot_id;

    INSERT INTO public.slot_history (
      slot_id,
      account_id,
      action_type,
      old_value,
      new_value,
      reason_code,
      performed_by,
      remarks,
      created_at
    ) VALUES (
      v_slot_id,
      NEW.account_id,
      'status_change',
      NULL,
      v_slot_status,
      NULL,
      public.get_current_profile_id(),
      'Auto-created by fn_trg_auto_create_vacancy_slot on vacancy ' || NEW.vcode,
      v_aging_ts
    );
  END LOOP;

  RETURN NEW;
END$function$;

CREATE OR REPLACE FUNCTION public.fn_update_applicant_pipeline(p_applicant_id uuid, p_new_status text DEFAULT NULL::text, p_follow_up_date date DEFAULT NULL::date, p_recruitment_remarks text DEFAULT NULL::text, p_ops_remarks text DEFAULT NULL::text, p_deployed_reliever boolean DEFAULT NULL::boolean, p_deployed_commando boolean DEFAULT NULL::boolean, p_reason_id uuid DEFAULT NULL::uuid, p_reason_type text DEFAULT NULL::text, p_clear_recruitment_remarks boolean DEFAULT false, p_clear_ops_remarks boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level int := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text;

  v_app record;
  v_vac record;
  v_old_status_code text;
  v_old_status_terminal boolean := false;
  v_new_status public.applicant_status_options%ROWTYPE;
  v_new_status_code text;
  v_new_status_label text;

  v_now timestamptz := now();
  v_history_ids uuid[] := ARRAY[]::uuid[];
  v_change_count int := 0;

  v_old_recruitment_remarks text;
  v_new_recruitment_remarks text;
  v_old_ops_remarks text;
  v_new_ops_remarks text;
  v_old_follow_up_date date;
  v_new_follow_up_date date;

  v_has_deployed_reliever boolean := false;
  v_has_deployed_commando boolean := false;
  v_old_deployed_reliever boolean;
  v_old_deployed_commando boolean;

  v_status_changed boolean := false;
  v_follow_up_changed boolean := false;
  v_recruitment_remarks_changed boolean := false;
  v_ops_remarks_changed boolean := false;
  v_deployed_reliever_changed boolean := false;
  v_deployed_commando_changed boolean := false;

  v_history_id uuid;
BEGIN
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason_type IS NOT NULL
     AND p_reason_type NOT IN ('backout', 'rejected', 'other') THEN
    RAISE EXCEPTION 'invalid reason_type: %. Must be backout | rejected | other', p_reason_type
      USING ERRCODE = '22023';
  END IF;

  IF p_new_status IS NULL
     AND p_follow_up_date IS NULL
     AND p_recruitment_remarks IS NULL
     AND p_ops_remarks IS NULL
     AND p_deployed_reliever IS NULL
     AND p_deployed_commando IS NULL
     AND NOT COALESCE(p_clear_recruitment_remarks, false)
     AND NOT COALESCE(p_clear_ops_remarks, false) THEN
    RAISE EXCEPTION 'no applicant pipeline changes requested'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public.fn_assert_vacancy_edit_allowed_op('UPDATE');

  SELECT up.full_name
  INTO v_actor_name
  FROM public.users_profile up
  WHERE up.id = v_profile_id;

  SELECT *
  INTO v_app
  FROM public.applicants
  WHERE id = p_applicant_id
    AND COALESCE(is_archived, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT *
  INTO v_vac
  FROM public.vacancies
  WHERE vcode = v_app.vacancy_vcode;

  IF v_vac.source = 'pool' AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update pool vacancy applicants'
      USING ERRCODE = '42501';
  END IF;

  v_old_status_code := lower(regexp_replace(COALESCE(v_app.status, ''), '[^a-zA-Z0-9]+', '_', 'g'));

  SELECT is_terminal
  INTO v_old_status_terminal
  FROM public.applicant_status_options
  WHERE status_code = v_old_status_code
     OR label = v_app.status
     OR lower(regexp_replace(COALESCE(label, ''), '[^a-zA-Z0-9]+', '_', 'g')) = v_old_status_code
  ORDER BY CASE WHEN status_code = v_old_status_code THEN 0 ELSE 1 END
  LIMIT 1;

  IF COALESCE(v_old_status_terminal, false) AND v_level < 100 THEN
    RAISE EXCEPTION 'cannot change status from terminal status % without Super Admin override', v_app.status
      USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'applicants' AND column_name = 'deployed_reliever'
  ) INTO v_has_deployed_reliever;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'applicants' AND column_name = 'deployed_commando'
  ) INTO v_has_deployed_commando;

  IF p_deployed_reliever IS NOT NULL AND NOT v_has_deployed_reliever THEN
    RAISE EXCEPTION 'applicants.deployed_reliever is not available in this schema'
      USING ERRCODE = '42703';
  END IF;

  IF p_deployed_commando IS NOT NULL AND NOT v_has_deployed_commando THEN
    RAISE EXCEPTION 'applicants.deployed_commando is not available in this schema'
      USING ERRCODE = '42703';
  END IF;

  IF (p_deployed_reliever IS NOT NULL OR p_deployed_commando IS NOT NULL)
     AND NOT (v_level = 100 OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'only HRCO/ATL/TL/OM or Super Admin may update deployment flags'
      USING ERRCODE = '42501';
  END IF;

  IF p_new_status IS NOT NULL THEN
    v_new_status_code := lower(regexp_replace(btrim(p_new_status), '[^a-zA-Z0-9]+', '_', 'g'));

    SELECT *
    INTO v_new_status
    FROM public.applicant_status_options aso
    WHERE aso.is_active = true
      AND (
        aso.status_code = v_new_status_code
        OR aso.label = btrim(p_new_status)
        OR lower(regexp_replace(aso.label, '[^a-zA-Z0-9]+', '_', 'g')) = v_new_status_code
      )
    LIMIT 1;

    IF v_new_status.status_code IS NULL THEN
      RAISE EXCEPTION 'invalid status: %', p_new_status
        USING ERRCODE = '22023';
    END IF;

    IF v_new_status.status_code <> v_old_status_code THEN
      v_status_changed := true;
      v_new_status_label := v_new_status.label;
    END IF;
  END IF;

  IF p_follow_up_date IS NOT NULL AND COALESCE(v_app.follow_up_date, '1970-01-01'::date) <> p_follow_up_date THEN
    v_follow_up_changed := true;
    v_old_follow_up_date := v_app.follow_up_date;
    v_new_follow_up_date := p_follow_up_date;
  END IF;

  IF COALESCE(p_clear_recruitment_remarks, false) THEN
    IF v_app.recruitment_remarks IS NOT NULL THEN
      v_recruitment_remarks_changed := true;
      v_old_recruitment_remarks := v_app.recruitment_remarks;
      v_new_recruitment_remarks := NULL;
    END IF;
  ELSIF p_recruitment_remarks IS NOT NULL AND COALESCE(v_app.recruitment_remarks, '') <> btrim(p_recruitment_remarks) THEN
    v_recruitment_remarks_changed := true;
    v_old_recruitment_remarks := v_app.recruitment_remarks;
    v_new_recruitment_remarks := btrim(p_recruitment_remarks);
  END IF;

  IF COALESCE(p_clear_ops_remarks, false) THEN
    IF v_app.ops_remarks IS NOT NULL THEN
      v_ops_remarks_changed := true;
      v_old_ops_remarks := v_app.ops_remarks;
      v_new_ops_remarks := NULL;
    END IF;
  ELSIF p_ops_remarks IS NOT NULL AND COALESCE(v_app.ops_remarks, '') <> btrim(p_ops_remarks) THEN
    v_ops_remarks_changed := true;
    v_old_ops_remarks := v_app.ops_remarks;
    v_new_ops_remarks := btrim(p_ops_remarks);
  END IF;

  IF v_has_deployed_reliever AND p_deployed_reliever IS NOT NULL THEN
    EXECUTE 'SELECT COALESCE(deployed_reliever, false) FROM public.applicants WHERE id = $1'
      INTO v_old_deployed_reliever USING v_app.id;
    IF v_old_deployed_reliever <> p_deployed_reliever THEN
      v_deployed_reliever_changed := true;
    END IF;
  END IF;

  IF v_has_deployed_commando AND p_deployed_commando IS NOT NULL THEN
    EXECUTE 'SELECT COALESCE(deployed_commando, false) FROM public.applicants WHERE id = $1'
      INTO v_old_deployed_commando USING v_app.id;
    IF v_old_deployed_commando <> p_deployed_commando THEN
      v_deployed_commando_changed := true;
    END IF;
  END IF;

  IF NOT (
    v_status_changed OR
    v_follow_up_changed OR
    v_recruitment_remarks_changed OR
    v_ops_remarks_changed OR
    v_deployed_reliever_changed OR
    v_deployed_commando_changed
  ) THEN
    RETURN jsonb_build_object('ok', true, 'applicant_id', v_app.id, 'changed', false);
  END IF;

  UPDATE public.applicants
  SET
    status            = CASE WHEN v_status_changed             THEN v_new_status_label      ELSE status            END,
    follow_up_date    = CASE WHEN v_follow_up_changed          THEN v_new_follow_up_date     ELSE follow_up_date    END,
    recruitment_remarks = CASE WHEN v_recruitment_remarks_changed THEN v_new_recruitment_remarks ELSE recruitment_remarks END,
    ops_remarks       = CASE WHEN v_ops_remarks_changed        THEN v_new_ops_remarks        ELSE ops_remarks       END,
    last_activity_at  = v_now,
    last_activity_by  = v_profile_id,
    last_activity_by_name = v_actor_name,
    updated_at        = v_now,
    updated_by        = v_profile_id
  WHERE id = v_app.id;

  IF v_deployed_reliever_changed THEN
    EXECUTE 'UPDATE public.applicants SET deployed_reliever = $1 WHERE id = $2'
      USING p_deployed_reliever, v_app.id;
  END IF;

  IF v_deployed_commando_changed THEN
    EXECUTE 'UPDATE public.applicants SET deployed_commando = $1 WHERE id = $2'
      USING p_deployed_commando, v_app.id;
  END IF;

  IF v_status_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, v_new_status_label,
      p_reason_id, p_reason_type, NULL, v_profile_id, v_now, 'vacancy',
      'status_change', 'status', v_app.status, v_new_status_label, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_follow_up_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_follow_up_date, new_follow_up_date,
      changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'follow_up_update',
      'follow_up_date', v_old_follow_up_date::text, v_new_follow_up_date::text,
      v_old_follow_up_date, v_new_follow_up_date, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_recruitment_remarks_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_recruitment_remarks,
      new_recruitment_remarks, changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'recruitment_remarks_update',
      'recruitment_remarks', v_old_recruitment_remarks, v_new_recruitment_remarks,
      v_old_recruitment_remarks, v_new_recruitment_remarks, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_ops_remarks_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_ops_remarks, new_ops_remarks,
      changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'ops_remarks_update',
      'ops_remarks', v_old_ops_remarks, v_new_ops_remarks,
      v_old_ops_remarks, v_new_ops_remarks, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_deployed_reliever_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_deployed_reliever,
      new_deployed_reliever, changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'deployed_reliever_update',
      'deployed_reliever', v_old_deployed_reliever::text, p_deployed_reliever::text,
      v_old_deployed_reliever, p_deployed_reliever, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_deployed_commando_changed THEN
    v_history_id := gen_random_uuid();
    INSERT INTO public.applicant_status_history (
      id, applicant_id, from_status, to_status, reason_id, reason_type,
      remarks, changed_by, changed_at, source_module, update_type,
      changed_field, old_value, new_value, old_deployed_commando,
      new_deployed_commando, changed_by_name
    ) VALUES (
      v_history_id, v_app.id, v_app.status, NULL, p_reason_id, p_reason_type,
      NULL, v_profile_id, v_now, 'vacancy', 'deployed_commando_update',
      'deployed_commando', v_old_deployed_commando::text, p_deployed_commando::text,
      v_old_deployed_commando, p_deployed_commando, v_actor_name
    );
    v_history_ids := array_append(v_history_ids, v_history_id);
    v_change_count := v_change_count + 1;
  END IF;

  IF v_status_changed THEN
    DECLARE
      v_slot_type text := 'stationary';
    BEGIN
      IF v_app.coverage_slot_id IS NOT NULL THEN
        v_slot_type := 'roving';
      END IF;

      IF v_slot_type = 'roving' THEN
        IF v_new_status.is_terminal THEN
          PERFORM public.fn_release_coverage_slot(v_app.coverage_slot_id, v_profile_id);
        END IF;
      ELSE
        PERFORM public.fn_sync_vacancy_slot_open_pipeline(
          v_app.vacancy_vcode,
          v_profile_id,
          p_source_fn => 'fn_update_applicant_pipeline'
        );
      END IF;
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'applicant_id', v_app.id,
    'changed', true,
    'change_count', v_change_count,
    'history_ids', v_history_ids
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_update_applicant_profile_once(p_applicant_id uuid, p_first_name text, p_last_name text, p_contact_number text, p_middle_name text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- i_have_full_access() = headAdmin (level 90) OR superAdmin (level 100)
  v_is_full_access boolean := public.i_have_full_access();
  v_profile_id     uuid    := public.get_my_profile_id();
  v_app            public.applicants%ROWTYPE;
  v_is_override    boolean := false;
  v_new_edit_count integer;

  -- Statuses that indicate the applicant has left Vacancy/Pipeline.
  -- confirmed_onboard → triggers move to HR Emploc.
  -- transferred / hired → moved to Plantilla or beyond.
  -- lower() tolerates mixed-case stored values.
  c_locked_statuses text[] := ARRAY[
    'confirmed_onboard', 'transferred', 'hired'
  ];
BEGIN
  -- ── RBAC ──────────────────────────────────────────────────────
  -- Allowed: Ops Team (40-70), Recruitment Team (20),
  --          Head Admin (90), Super Admin (100).
  -- Denied:  Encoder (30), HR Personnel (25), Backoffice (15),
  --          Viewer (10), and all others below headAdmin who are
  --          not Ops or Recruitment.
  IF NOT (
    public.i_am_ops()            -- levels 40-70
    OR public.i_am_recruitment() -- level 20
    OR v_is_full_access          -- headAdmin (90) OR superAdmin (100)
  ) THEN
    RAISE EXCEPTION
      'forbidden: Ops Team, Recruitment Team, Head Admin, or Super Admin required to edit applicant profile'
      USING ERRCODE = '42501';
  END IF;

  -- ── Required fields ────────────────────────────────────────────
  IF TRIM(COALESCE(p_first_name, '')) = '' THEN
    RAISE EXCEPTION 'p_first_name is required' USING ERRCODE = '22023';
  END IF;
  IF TRIM(COALESCE(p_last_name, '')) = '' THEN
    RAISE EXCEPTION 'p_last_name is required' USING ERRCODE = '22023';
  END IF;
  IF TRIM(COALESCE(p_contact_number, '')) = '' THEN
    RAISE EXCEPTION 'p_contact_number is required' USING ERRCODE = '22023';
  END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'p_reason (comments/reason) is required' USING ERRCODE = '22023';
  END IF;

  -- ── Fetch applicant ────────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Scope check ────────────────────────────────────────────────
  -- Full-access users (headAdmin + superAdmin) bypass scope.
  IF NOT v_is_full_access THEN
    IF NOT EXISTS (
      SELECT 1
        FROM public.vacancies v
       WHERE v.vcode       = v_app.vacancy_vcode
         AND v.account     = ANY(public.get_my_allowed_accounts())
         AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION
        'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Lock check ─────────────────────────────────────────────────
  -- Locked once the applicant has progressed beyond Vacancy/Pipeline.
  -- Terminal Vacancy statuses (rejected/failed/backout) are NOT locked
  -- because the applicant record remains in the Vacancy context.
  -- Lock applies to ALL callers — no override for lock state.
  IF lower(COALESCE(v_app.status, '')) = ANY(c_locked_statuses) THEN
    RAISE EXCEPTION
      'applicant profile is locked: applicant has progressed beyond the Vacancy pipeline (status: %)',
      v_app.status
      USING ERRCODE = '22023';
  END IF;

  -- ── One-time enforcement ───────────────────────────────────────
  -- Full-access users (headAdmin + superAdmin) may edit after the
  -- one-time limit has been used. Regular callers (Ops/Recruitment)
  -- are blocked after their single edit.
  -- Note: is_super_admin_override column retains its name for schema
  -- compatibility; it now semantically covers headAdmin overrides too.
  IF COALESCE(v_app.profile_edit_count, 0) >= 1 THEN
    IF NOT v_is_full_access THEN
      RAISE EXCEPTION
        'one-time profile edit already used for applicant % — Head Admin or Super Admin override required',
        p_applicant_id
        USING ERRCODE = '22023';
    END IF;
    -- Full-access override path (headAdmin or superAdmin)
    v_is_override := true;
  END IF;

  -- ── Change detection ───────────────────────────────────────────
  -- Reject no-op calls where nothing actually differs.
  IF p_first_name IS NOT DISTINCT FROM v_app.first_name
     AND COALESCE(p_middle_name, '') = COALESCE(v_app.middle_name, '')
     AND p_last_name IS NOT DISTINCT FROM v_app.last_name
     AND p_contact_number IS NOT DISTINCT FROM v_app.contact_number
  THEN
    RAISE EXCEPTION
      'no field changes detected — at least one field must differ from current values'
      USING ERRCODE = '22023';
  END IF;

  -- ── Write immutable audit row ──────────────────────────────────
  -- Always logged regardless of caller role.
  -- is_super_admin_override = true for headAdmin OR superAdmin overrides.
  INSERT INTO public.applicant_profile_edit_history (
    applicant_id,
    edited_by,
    old_first_name,     new_first_name,
    old_middle_name,    new_middle_name,
    old_last_name,      new_last_name,
    old_contact_number, new_contact_number,
    reason,
    is_super_admin_override,
    source_module
  ) VALUES (
    p_applicant_id,
    v_profile_id,
    v_app.first_name,     p_first_name,
    v_app.middle_name,    p_middle_name,
    v_app.last_name,      p_last_name,
    v_app.contact_number, p_contact_number,
    p_reason,
    v_is_override,
    'vacancy'
  );

  -- ── Compute new edit count ─────────────────────────────────────
  -- Full-access overrides (headAdmin/superAdmin) do NOT increment
  -- the counter so the one-time gate stays intact for OPS/Recruitment
  -- after an admin override.
  v_new_edit_count := CASE
    WHEN v_is_full_access THEN COALESCE(v_app.profile_edit_count, 0)
    ELSE                       COALESCE(v_app.profile_edit_count, 0) + 1
  END;

  -- ── Apply field changes immediately ────────────────────────────
  -- full_name rebuilt as "LAST, FIRST MIDDLE" — same convention as
  -- fn_approve_applicant_profile_edit_request. Flutter name_formatter
  -- handles final display rendering.
  UPDATE public.applicants
  SET
    first_name             = p_first_name,
    middle_name            = p_middle_name,
    last_name              = p_last_name,
    contact_number         = p_contact_number,
    full_name              = TRIM(
                               p_last_name || ', ' || p_first_name
                               || CASE
                                    WHEN TRIM(COALESCE(p_middle_name, '')) NOT IN
                                         ('', 'NA', 'N/A', 'NONE', 'N.A.')
                                    THEN ' ' || p_middle_name
                                    ELSE ''
                                  END
                             ),
    profile_edit_count     = v_new_edit_count,
    last_profile_edited_at = now(),
    last_profile_edited_by = v_profile_id,
    updated_at             = now(),
    updated_by             = v_profile_id
  WHERE id = p_applicant_id;

  -- ── Return success payload ─────────────────────────────────────
  RETURN jsonb_build_object(
    'success',      true,
    'applicant_id', p_applicant_id,
    'is_override',  v_is_override,
    'edit_count',   v_new_edit_count,
    'updated_at',   now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_update_applicant_status(p_applicant_id uuid, p_new_status text, p_remarks text DEFAULT NULL::text, p_reason_id uuid DEFAULT NULL::uuid, p_reason_type text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level         int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id    uuid := public.get_my_profile_id();
  v_app           public.applicants%ROWTYPE;
  v_to_opt        public.applicant_status_options%ROWTYPE;
  v_from_code     text;
  v_old_status    text;
  v_from_terminal boolean;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Validate reason_type ─────────────────────────────────────
  IF p_reason_type IS NOT NULL
     AND p_reason_type NOT IN ('backout', 'rejected', 'other') THEN
    RAISE EXCEPTION 'invalid reason_type: %. Must be backout | rejected | other', p_reason_type
      USING ERRCODE = '22023';
  END IF;

  -- ── Resolve target status option ─────────────────────────────
  SELECT * INTO v_to_opt
    FROM public.applicant_status_options
   WHERE status_code = p_new_status
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid or inactive status_code: %', p_new_status
      USING ERRCODE = '22023';
  END IF;

  -- ── Block system-only targets for non-Super Admin ────────────
  IF v_to_opt.is_system_only AND v_level != 100 THEN
    RAISE EXCEPTION 'status % is system-only and cannot be set manually', p_new_status
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock applicant ──────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  v_old_status := COALESCE(v_app.status, 'New');

  -- ── Resolve current status_code from stored label ────────────
  SELECT status_code INTO v_from_code
    FROM public.applicant_status_options
   WHERE label = v_old_status
  LIMIT 1;

  IF v_from_code IS NULL THEN
    v_from_code := 'new';
  END IF;

  -- ── Terminal source guard ─────────────────────────────────────
  SELECT is_terminal INTO v_from_terminal
    FROM public.applicant_status_options
   WHERE status_code = v_from_code;

  IF COALESCE(v_from_terminal, false) THEN
    IF v_level != 100 THEN
      RAISE EXCEPTION
        'cannot transition from terminal status "%" without Super Admin authority',
        v_old_status
        USING ERRCODE = '22023';
    END IF;
  ELSE
    -- RELAXED TRANSITION RULE (OHM2026_2025): from any active (non-terminal)
    -- status, any non-system-only active target is allowed.
    NULL;
  END IF;

  -- ── Scope check ───────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Apply status update ───────────────────────────────────────
  UPDATE public.applicants
  SET
    status     = v_to_opt.label,
    updated_at = NOW(),
    updated_by = v_profile_id
  WHERE id = p_applicant_id;

  -- ── Write immutable status history ────────────────────────────
  INSERT INTO public.applicant_status_history (
    applicant_id,
    from_status,
    to_status,
    reason_id,
    reason_type,
    remarks,
    changed_by,
    changed_at,
    source_module
  ) VALUES (
    p_applicant_id,
    v_old_status,
    v_to_opt.label,
    p_reason_id,
    p_reason_type,
    p_remarks,
    v_profile_id,
    NOW(),
    'vacancy'
  );

  -- ── Slot-aware open↔pipeline sync (stationary + roving + legacy) ──────────
  -- Routed by binding column. Mutual exclusivity (RB2) guarantees at most one
  -- of slot_id / coverage_slot_id is set, so the branches are disjoint.
  IF v_app.slot_id IS NOT NULL THEN
    -- ── STATIONARY (Phase B, UNCHANGED) ──────────────────────────────────
    IF COALESCE(v_to_opt.is_terminal, false) THEN
      -- Terminal transition: release the specific bound stationary slot.
      PERFORM public.fn_release_applicant_slot(
        p_slot_id      => v_app.slot_id,
        p_performed_by => v_profile_id
      );
    END IF;
    -- Non-terminal with bound slot: no slot status change (Phase 6.2 owns
    -- pipeline→hr_processing via confirm_applicant_onboard).
  ELSIF v_app.coverage_slot_id IS NOT NULL THEN
    -- ── ROVING (Phase R-B, NEW) ──────────────────────────────────────────
    -- Direct FK dereference — act on THAT specific coverage slot, never a
    -- group-only LIMIT 1 lookup (plan Q7).
    IF COALESCE(v_to_opt.is_terminal, false) THEN
      -- Terminal transition: release the exact coverage slot (pipeline→open
      -- if no other active applicant remains). NEVER RAISES.
      PERFORM public.fn_release_coverage_slot(
        p_slot_id      => v_app.coverage_slot_id,
        p_performed_by => v_profile_id
      );
    END IF;
    -- Non-terminal with bound coverage slot: no slot status change. Confirmed
    -- Onboard (pipeline→hr_processing) is R-C, not wired here.
  ELSE
    -- ── LEGACY / UNBOUND (Phase 6.1, UNCHANGED) ──────────────────────────
    -- No-slot VCODE, legacy roving (roving_assignment_id), or pre-backfill row.
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v_app.vacancy_vcode,
      p_performed_by => v_profile_id,
      p_source_fn    => 'fn_update_applicant_status'
    );
  END IF;

END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_update_freeze_mode(p_control_key text, p_enabled boolean, p_reason text, p_actor_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_before     boolean;
  v_level      int;
  v_actor_auth uuid;
BEGIN
  -- Enforce superAdmin-only caller role check
  SELECT r.role_level, up.auth_user_id INTO v_level, v_actor_auth
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.id = p_actor_id;

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_update_freeze_mode requires superAdmin.';
  END IF;

  -- Spoof guard: ensure actor corresponds to the authenticated database user
  IF v_actor_auth IS NULL OR v_actor_auth <> auth.uid() THEN
    RAISE EXCEPTION 'Access denied: Actor ID does not match authenticated user.';
  END IF;

  -- Key guard: restrict modification to freeze keys only
  IF p_control_key NOT IN ('payroll_freeze', 'audit_freeze', 'recruitment_freeze', 'read_only_emergency') THEN
    RAISE EXCEPTION 'Invalid freeze mode key: %', p_control_key;
  END IF;

  -- Mandatory reason verification
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A non-empty reason is required to activate or deactivate a freeze mode.';
  END IF;

  -- Read prior value for audit logging
  SELECT gc.enabled INTO v_before
  FROM public.governance_controls gc
  WHERE gc.control_key = p_control_key;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown governance control: %', p_control_key;
  END IF;

  -- Apply update atomically
  UPDATE public.governance_controls
  SET
    enabled    = p_enabled,
    updated_by = p_actor_id,
    updated_at = now(),
    reason     = trim(p_reason)
  WHERE control_key = p_control_key;

  -- Write append-only governance audit log entry
  INSERT INTO public.governance_audit_log (
    control_key,
    action,
    before_value,
    after_value,
    changed_by,
    reason
  ) VALUES (
    p_control_key,
    CASE WHEN p_enabled THEN 'freeze_activate' ELSE 'freeze_deactivate' END,
    jsonb_build_object('enabled', v_before),
    jsonb_build_object('enabled', p_enabled),
    p_actor_id,
    trim(p_reason)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_update_governance_control(p_control_key text, p_enabled boolean, p_reason text, p_actor_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_before  boolean;
  v_level   int;
BEGIN
  -- Enforce superAdmin-only caller
  SELECT r.role_level INTO v_level
  FROM users_profile up
  JOIN roles r ON r.id = up.role_id
  WHERE up.id = p_actor_id;

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_update_governance_control requires superAdmin.';
  END IF;

  -- Read current value for audit
  SELECT enabled INTO v_before
  FROM governance_controls
  WHERE control_key = p_control_key;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown governance control: %', p_control_key;
  END IF;

  -- Apply update
  UPDATE governance_controls
  SET
    enabled    = p_enabled,
    updated_by = p_actor_id,
    updated_at = now(),
    reason     = p_reason
  WHERE control_key = p_control_key;

  -- Write audit entry
  INSERT INTO governance_audit_log (
    control_key, action, before_value, after_value, changed_by, reason
  ) VALUES (
    p_control_key,
    CASE WHEN p_enabled THEN 'enable' ELSE 'disable' END,
    jsonb_build_object('enabled', v_before),
    jsonb_build_object('enabled', p_enabled),
    p_actor_id,
    p_reason
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_active_acting_session()
 RETURNS acting_sessions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select s.*
    from public.acting_sessions s
    where s.user_id = auth.uid()
      and s.is_active = true
      and s.expires_at > now()
    order by s.created_at desc
    limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.get_applicant_movement_requests(p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS SETOF vw_amr_list
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me            public.users_profile%ROWTYPE;
  v_me_role_level int;
  v_mine_only     bool;
  v_status_filter text;
  v_type_filter   text;
BEGIN
  SELECT * INTO v_me FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT r.role_level INTO v_me_role_level
  FROM public.roles r WHERE r.id = v_me.role_id;

  v_mine_only     := COALESCE((p_filter->>'mine_only')::bool, false);
  v_status_filter := p_filter->>'status';
  v_type_filter   := p_filter->>'movement_type';

  RETURN QUERY
  SELECT *
  FROM public.vw_amr_list r
  WHERE
    (
      -- Requester sees own requests
      r.requested_by = v_me.id
      -- Approvers see all (with RLS on base table already filtering)
      OR (NOT v_mine_only AND (i_have_full_access() OR v_me_role_level >= 30))
    )
    AND (v_status_filter IS NULL OR r.status = v_status_filter)
    AND (v_type_filter IS NULL OR r.movement_type = v_type_filter)
  ORDER BY r.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_approval_queue(p_status account_request_status DEFAULT 'pending'::account_request_status)
 RETURNS SETOF v_approval_queue
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT * FROM public.v_approval_queue WHERE status = p_status;
$function$;

CREATE OR REPLACE FUNCTION public.get_coverage_group_eligible_accounts()
 RETURNS TABLE(account_id uuid, account_name text, group_id uuid, group_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT
    a.id AS account_id,
    a.account_name,
    a.group_id,
    g.group_name
  FROM public.accounts a
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE a.is_active = true
    AND lower(COALESCE(a.status, 'active')) <> 'archived'
    AND COALESCE(a.is_pool_account, false) = false
    AND (
      public.i_have_full_access()
      OR a.id = ANY (public.get_my_allowed_account_ids())
    )
    AND EXISTS (
      SELECT 1
      FROM public.stores s
      WHERE s.account_id = a.id
        AND s.is_active = true
        AND lower(COALESCE(s.status, 'active')) <> 'archived'
        AND (
          EXISTS (
            SELECT 1
            FROM public.plantilla_slots ps
            WHERE ps.store_id = s.id
              AND ps.slot_status <> 'closed'
          )
          OR EXISTS (
            SELECT 1
            FROM public.employee_store_allocations esa
            WHERE esa.store_id = s.id
              AND esa.is_active = true
          )
        )
    )
  ORDER BY a.account_name;
$function$;

CREATE OR REPLACE FUNCTION public.get_coverage_group_eligible_stores(p_account_id uuid)
 RETURNS TABLE(store_id uuid, store_name text, account_id uuid, area_city text, area_province text, already_grouped_code text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_role      text;
BEGIN
  SELECT id INTO v_caller_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_name INTO v_role
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.id = v_caller_id;

  IF v_role NOT IN ('Super Admin', 'Head Admin', 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  IF v_role = 'Encoder'
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.accounts a
    WHERE a.id = p_account_id
      AND a.is_active = true
      AND lower(COALESCE(a.status, 'active')) <> 'archived'
  ) THEN
    RAISE EXCEPTION 'account not found or archived' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT DISTINCT ON (s.id)
    s.id AS store_id,
    s.store_name,
    s.account_id,
    COALESCE(s.area_city, '') AS area_city,
    COALESCE(s.area_province, '') AS area_province,
    (
      SELECT cg.coverage_code
      FROM public.coverage_group_stores cgs2
      JOIN public.coverage_groups cg
        ON cg.id = cgs2.coverage_group_id
       AND cg.archived_at IS NULL
       AND lower(COALESCE(cg.status, '')) <> 'archived'
      WHERE cgs2.store_id = s.id
        AND cgs2.archived_at IS NULL
      LIMIT 1
    ) AS already_grouped_code
  FROM public.stores s
  WHERE s.account_id = p_account_id
    AND s.is_active = true
    AND lower(COALESCE(s.status, 'active')) <> 'archived'
    AND (
      -- Predicate 1 (original): Active plantilla slot linked to this store
      EXISTS (
        SELECT 1
        FROM public.plantilla_slots ps
        WHERE ps.store_id = s.id
          AND ps.slot_status <> 'closed'
      )
      -- Predicate 2 (original): Active employee store allocation
      OR EXISTS (
        SELECT 1
        FROM public.employee_store_allocations esa
        WHERE esa.store_id = s.id
          AND esa.is_active = true
      )
      -- Predicate 3 (new — ohm#8r6xk2m9): Active open/pipeline vacancy linked to this store
      -- Defense against vacancy-only stores where plantilla_slots.store_id is NULL
      -- (e.g., legacy orphan slots where the trigger resolved store_id = NULL before §1 fix)
      -- Excludes: filled, closed, deleted, archived, pool vacancies
      OR EXISTS (
        SELECT 1
        FROM public.vacancies v
        WHERE v.store_id = s.id
          AND v.deleted_at IS NULL
          AND COALESCE(v.is_archived, false) = false
          AND lower(COALESCE(v.status, '')) IN ('open', 'pipeline')
          AND COALESCE(v.is_pool_vacancy, false) = false
      )
    )
  ORDER BY s.id, s.store_name;
END
$function$;

CREATE OR REPLACE FUNCTION public.get_employee_import_batches(p_status text DEFAULT NULL::text)
 RETURNS SETOF employee_import_batches
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT b.* FROM public.employee_import_batches b
  WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
    AND (p_status IS NULL OR b.status = p_status)
  ORDER BY b.created_at DESC;
$function$;

CREATE OR REPLACE FUNCTION public.get_employee_import_rows(p_batch_id uuid)
 RETURNS SETOF employee_import_rows
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT r.* FROM public.employee_import_rows r
  WHERE r.batch_id = p_batch_id
    AND (
      public.i_have_full_access()
      OR EXISTS (SELECT 1 FROM public.employee_import_batches b
                 WHERE b.id = r.batch_id AND b.uploaded_by = auth.uid())
    )
  ORDER BY r.row_number;
$function$;

CREATE OR REPLACE FUNCTION public.get_global_plantilla_for_payroll_check()
 RETURNS TABLE(plantilla_id uuid, employee_no text, last_name text, first_name text, middle_name text, account_name text, group_name text, is_active boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Access denied — HA/SA only'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id                                                              AS plantilla_id,
    COALESCE(btrim(p.employee_no), '')                               AS employee_no,
    COALESCE(btrim(p.last_name),   '')                               AS last_name,
    COALESCE(btrim(p.first_name),  '')                               AS first_name,
    COALESCE(btrim(p.middle_name), '')                               AS middle_name,
    COALESCE(btrim(a.account_name), '')                              AS account_name,
    COALESCE(btrim(g.group_name),   '')                              AS group_name,
    (
      lower(COALESCE(NULLIF(btrim(p.status), ''), 'active'))
        NOT IN ('deactivated', 'archived', 'inactive')
      AND lower(COALESCE(NULLIF(btrim(p.separation_status), ''), ''))
        NOT IN ('deactivated', 'terminated', 'resigned', 'awol')
    )                                                                 AS is_active
  FROM  public.plantilla p
  JOIN  public.accounts  a ON a.id = p.account_id
  JOIN  public.groups    g ON g.id = a.group_id
  WHERE COALESCE(p.is_pool_employee, false) = false
    AND p.employee_no IS NOT NULL
    AND btrim(p.employee_no) <> ''
  ORDER BY p.employee_no;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_batches()
 RETURNS TABLE(id uuid, file_name text, status text, group_id uuid, group_name text, total_rows integer, valid_rows integer, blocked_rows integer, duplicate_rows integer, created_rows integer, uploaded_by uuid, uploaded_by_name text, uploaded_at timestamp with time zone, approved_by uuid, approved_by_name text, approved_at timestamp with time zone, rejected_by uuid, rejected_by_name text, rejected_at timestamp with time zone, rejection_reason_code text, rejection_reason_note text, rolled_back_by uuid, rolled_back_by_name text, rolled_back_at timestamp with time zone, rollback_reason text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT
    b.id,
    b.file_name,
    b.status,
    b.group_id,
    b.group_name,
    b.total_rows,
    b.valid_rows,
    b.blocked_rows,
    b.duplicate_rows,
    b.created_rows,
    b.uploaded_by,
    up.full_name AS uploaded_by_name,
    b.uploaded_at,
    b.approved_by,
    ap.full_name AS approved_by_name,
    b.approved_at,
    b.rejected_by,
    rp.full_name AS rejected_by_name,
    b.rejected_at,
    b.rejection_reason_code,
    b.rejection_reason_note,
    b.rolled_back_by,
    rbp.full_name AS rolled_back_by_name,
    b.rolled_back_at,
    b.rollback_reason,
    b.created_at
  FROM public.hr_emploc_import_batches b
  LEFT JOIN public.users_profile up  ON up.id  = b.uploaded_by
  LEFT JOIN public.users_profile ap  ON ap.id  = b.approved_by
  LEFT JOIN public.users_profile rp  ON rp.id  = b.rejected_by
  LEFT JOIN public.users_profile rbp ON rbp.id = b.rolled_back_by
  WHERE b.deleted_at IS NULL
    AND (
      i_have_full_access()
      OR b.group_id IN (
        SELECT DISTINCT a.group_id FROM public.accounts a
        WHERE a.id::text = ANY(get_my_allowed_accounts())
      )
    )
  ORDER BY b.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_groups()
 RETURNS TABLE(group_id uuid, group_name text, sort_order integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.' USING ERRCODE = 'P0001';
  END IF;

  IF i_have_full_access() THEN
    RETURN QUERY
    SELECT
      g.id,
      g.group_name,
      ROW_NUMBER() OVER (ORDER BY g.group_code)::INTEGER
    FROM public.groups g
    WHERE COALESCE(g.cencom_scope, false) = true
    ORDER BY g.group_code;
    RETURN;
  END IF;

  -- Scoped users: their assigned groups that are operational
  RETURN QUERY
  SELECT DISTINCT
    g.id,
    g.group_name,
    ROW_NUMBER() OVER (ORDER BY g.group_code)::INTEGER
  FROM public.user_scopes us
  JOIN public.groups g ON g.id = us.group_id
  WHERE us.user_id = v_profile_id
    AND COALESCE(g.cencom_scope, false) = true
  ORDER BY g.group_code;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_rows(p_batch_id uuid)
 RETURNS TABLE(id uuid, batch_id uuid, row_number integer, group_name text, account_name text, last_name text, first_name text, middle_name text, date_hired date, position_name text, store_name text, employment_type text, vcode text, validation_status text, validation_errors jsonb, hr_emploc_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.hr_emploc_import_batches b
    WHERE b.id = p_batch_id
      AND b.deleted_at IS NULL
      AND (
        i_have_full_access()
        OR b.group_id IN (
          SELECT DISTINCT a.group_id FROM public.accounts a
          WHERE a.id::text = ANY(get_my_allowed_accounts())
        )
      )
  ) THEN
    RAISE EXCEPTION 'Batch not found or access denied' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT
    r.id, r.batch_id, r.row_number,
    r.group_name, r.account_name, r.last_name, r.first_name, r.middle_name,
    r.date_hired, r.position AS position_name, r.store_name, r.employment_type,
    r.vcode,
    r.validation_status, r.validation_errors, r.hr_emploc_id
  FROM public.hr_emploc_import_rows r
  WHERE r.batch_id = p_batch_id
  ORDER BY r.row_number;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_allowed_account_ids()
 RETURNS uuid[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level INT;
  v_profile_id UUID;
  v_acc_count  INT;
BEGIN
  v_role_level := get_my_role_level();
  v_profile_id := get_my_profile_id();

  -- SA / HA: full access
  IF v_role_level >= 90 THEN
    RETURN ARRAY(SELECT id FROM public.accounts WHERE is_active = true);
  END IF;

  -- OM (level 70): group-scoped
  IF v_role_level = 70 THEN
    RETURN ARRAY(
      SELECT a.id FROM public.accounts a
      JOIN public.user_scopes us ON us.group_id = a.group_id
      WHERE us.user_id = v_profile_id AND a.is_active = true
    );
  END IF;

  -- HRCO (60), ATL (50), TL (40), Encoder (30), Recruitment (20):
  -- account-scoped if any account_id rows; else group-scoped fallback
  SELECT COUNT(*) INTO v_acc_count
  FROM public.user_scopes
  WHERE user_id = v_profile_id AND account_id IS NOT NULL;

  IF v_acc_count > 0 THEN
    RETURN ARRAY(
      SELECT a.id FROM public.accounts a
      JOIN public.user_scopes us ON us.account_id = a.id
      WHERE us.user_id = v_profile_id AND a.is_active = true
    );
  ELSE
    RETURN ARRAY(
      SELECT a.id FROM public.accounts a
      JOIN public.user_scopes us ON us.group_id = a.group_id
      WHERE us.user_id = v_profile_id AND a.is_active = true
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_vacancies(p_status_filter text DEFAULT NULL::text, p_limit integer DEFAULT 200, p_offset integer DEFAULT 0)
 RETURNS TABLE(vacancy jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text := get_my_role();
  v_profile_id  uuid := get_my_profile_id();
  v_full_access bool := i_have_full_access();
BEGIN
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
  END IF;

  RETURN QUERY
  SELECT public.fn_mask_vacancy_for_role(v.*, v_role)
  FROM public.vacancies v
  WHERE COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (
      v_full_access
      OR v.account_id = ANY (public.get_my_allowed_account_ids())
      OR (v_role IN ('HRCO','Recruitment Team','Encoder')
          AND (v.hrco_user_id = v_profile_id
               OR v.assigned_encoder_id = v_profile_id
               OR v.requested_by_user_id = v_profile_id))
    )
    AND (p_status_filter IS NULL OR v.status = p_status_filter)
  ORDER BY v.created_at DESC
  LIMIT GREATEST(p_limit, 0) OFFSET GREATEST(p_offset, 0);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_plantilla_import_rows(p_batch_id uuid, p_offset integer DEFAULT 0, p_limit integer DEFAULT 500)
 RETURNS SETOF plantilla_import_rows
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT r.*
    FROM public.plantilla_import_rows r
   WHERE r.batch_id = p_batch_id
     AND (
       public.i_have_full_access()
       OR EXISTS (
         SELECT 1
           FROM public.plantilla_import_batches b
          WHERE b.id = r.batch_id
            AND b.uploaded_by = auth.uid()
       )
     )
   ORDER BY r.row_number
   LIMIT  GREATEST(1, LEAST(p_limit, 1000))
   OFFSET GREATEST(0, p_offset);
$function$;

CREATE OR REPLACE FUNCTION public.get_request_account_signup_options()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  Intentionally public-safe.
  This RPC is called unauthenticated by the Request Account screen to populate
  role/scope selection dropdowns. It exposes only non-sensitive lookup data:
    - A fixed allowlist of requestable role names (id + role_name only)
    - Active groups (id + group_name only)
    - Active non-pool accounts (id + account_name + group_id only)

  Super Admin, Head Admin, Executive Viewer, and any role not in the allowlist
  are never returned regardless of what exists in the roles table.
*/
DECLARE
  v_roles    jsonb;
  v_groups   jsonb;
  v_accounts jsonb;
BEGIN
  -- Requestable roles: exact allowlist only.
  -- Excluded: Super Admin, Head Admin, Executive Viewer, any unlisted role.
  SELECT jsonb_agg(
    jsonb_build_object('id', r.id, 'role_name', r.role_name)
    ORDER BY r.role_name
  )
  INTO v_roles
  FROM public.roles r
  WHERE r.role_name IN (
    'Operations Manager',
    'Encoder',
    'Recruitment',
    'Recruitment Team',
    'HRCO',
    'ATL',
    'TL'
  );

  -- Active groups only. id + group_name only — no internal metadata exposed.
  SELECT jsonb_agg(
    jsonb_build_object('id', g.id, 'group_name', g.group_name)
    ORDER BY g.group_name
  )
  INTO v_groups
  FROM public.groups g
  WHERE g.is_active = true;

  -- Active, non-pool accounts only. id + account_name + group_id only.
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',           a.id,
      'account_name', a.account_name,
      'group_id',     a.group_id
    )
    ORDER BY a.account_name
  )
  INTO v_accounts
  FROM public.accounts a
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false;

  RETURN jsonb_build_object(
    'roles',    COALESCE(v_roles,    '[]'::jsonb),
    'groups',   COALESCE(v_groups,   '[]'::jsonb),
    'accounts', COALESCE(v_accounts, '[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_team_directory(p_search text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_group_id uuid DEFAULT NULL::uuid, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(auth_user_id uuid, full_name text, last_name text, first_name text, middle_name text, display_name text, mobile_number text, email text, role_name text, role_level integer, group_names text[], account_names text[], directory_status text, profile_photo_url text, full_name_search text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- ── Team Directory — operational contact access only ──────────────────────────
-- Sensitive HR data must not be exposed. Visibility is RBAC + scope-based.
DECLARE
  v_caller_uid        UUID := auth.uid();
  v_caller_profile_id UUID;
  v_caller_role_level INT;
  v_caller_group_ids  UUID[];
BEGIN
  -- ── 1. Authentication guard — anon may not call ───────────────────────────
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: team directory requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- ── 2. Resolve caller profile and effective role level ───────────────────
  SELECT up.id, r.role_level
  INTO   v_caller_profile_id, v_caller_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_caller_uid
    AND  up.is_active = TRUE;

  IF v_caller_profile_id IS NULL THEN
    RAISE EXCEPTION 'team directory: caller profile not found or inactive'
      USING ERRCODE = '42501';
  END IF;

  -- ── 3. Sub-Viewer guard — roles below level 10 get no access ─────────────
  -- Fix 1: threshold changed from <= 10 to < 10 so Viewer (level 10)
  -- passes through.  Any future sub-Viewer role (< 10) is still blocked.
  IF COALESCE(v_caller_role_level, 0) < 10 THEN
    RETURN;  -- empty result set, no error
  END IF;

  -- ── 4. Resolve caller's group scope for scoped-access roles ─────────────
  -- Applies to all callers below Head Admin (level < 90), including Viewer.
  IF COALESCE(v_caller_role_level, 0) < 90 THEN
    SELECT ARRAY_AGG(DISTINCT us.group_id)
    INTO   v_caller_group_ids
    FROM   public.user_scopes us
    WHERE  us.user_id   = v_caller_profile_id
      AND  us.group_id IS NOT NULL;

    IF v_caller_group_ids IS NULL THEN
      SELECT ARRAY[up.group_id]
      INTO   v_caller_group_ids
      FROM   public.users_profile up
      WHERE  up.id          = v_caller_profile_id
        AND  up.group_id IS NOT NULL;
    END IF;
  END IF;

  -- ── 5. Main directory query ───────────────────────────────────────────────
  RETURN QUERY
  SELECT
    up.auth_user_id,
    up.full_name,
    up.last_name,
    up.first_name,
    up.middle_name,

    -- Fix 2: display_name → "Last, First M." (INITCAP proper case;
    -- single middle initial + period; omitted when middle_name is absent).
    CASE
      WHEN up.last_name  IS NOT NULL
       AND up.first_name IS NOT NULL
        THEN TRIM(
               INITCAP(up.last_name) || ', ' || INITCAP(up.first_name)
               || CASE
                    WHEN up.middle_name IS NOT NULL
                     AND TRIM(up.middle_name) <> ''
                      THEN ' ' || UPPER(LEFT(TRIM(up.middle_name), 1)) || '.'
                    ELSE ''
                  END
             )
      ELSE up.full_name
    END::TEXT                                      AS display_name,

    up.mobile_number,
    up.email,
    r.role_name,
    r.role_level::INT                              AS role_level,

    -- group_names: aggregated from user_scopes; falls back to profile.group_id
    COALESCE(
      (
        SELECT ARRAY_AGG(DISTINCT g.group_name ORDER BY g.group_name)
        FROM   public.user_scopes us2
        JOIN   public.groups g ON g.id = us2.group_id
        WHERE  us2.user_id   = up.id
          AND  us2.group_id IS NOT NULL
      ),
      (
        SELECT ARRAY[g2.group_name]
        FROM   public.groups g2
        WHERE  g2.id = up.group_id
      ),
      ARRAY[]::TEXT[]
    )                                              AS group_names,

    -- account_names: aggregated from user_scopes
    COALESCE(
      (
        SELECT ARRAY_AGG(DISTINCT a.account_name ORDER BY a.account_name)
        FROM   public.user_scopes us3
        JOIN   public.accounts a ON a.id = us3.account_id
        WHERE  us3.user_id    = up.id
          AND  us3.account_id IS NOT NULL
      ),
      ARRAY[]::TEXT[]
    )                                              AS account_names,

    COALESCE(up.directory_status, 'Available')     AS directory_status,
    NULL::TEXT                                     AS profile_photo_url,  -- V1: reserved
    up.full_name_search

  FROM  public.users_profile up
  JOIN  public.roles r ON r.id = up.role_id

  WHERE
    -- ── Base exclusions (always applied) ─────────────────────────────────────
    up.is_active   = TRUE
    AND r.role_level > 10         -- Viewer and below never appear in the directory

    -- ── RBAC + scope visibility gate (§2a) ───────────────────────────────────
    AND CASE
          -- Super Admin: sees all active directory users
          WHEN v_caller_role_level = 100 THEN
            TRUE

          -- Head Admin: sees all active directory users
          WHEN v_caller_role_level = 90 THEN
            TRUE

          -- Recruitment Team (20): all active users except Viewer (already
          -- filtered above) and Super Admin.
          WHEN v_caller_role_level = 20 THEN
            r.role_level < 100

          -- OM (70): peer OM visibility + lower-role users in own group scope.
          WHEN v_caller_role_level = 70 THEN
            r.role_level = 70
            OR (
              r.role_level < 70
              AND v_caller_group_ids IS NOT NULL
              AND EXISTS (
                SELECT 1
                FROM   public.user_scopes us_t
                WHERE  us_t.user_id  = up.id
                  AND  us_t.group_id = ANY(v_caller_group_ids)
              )
            )

          -- Fix 1: Viewer (10) added to the scoped-access band.
          -- Scoped-access roles: Viewer(10), Back Office(15), HR Personnel(25),
          -- Encoder(30), ATL/TL(40-42), HRCO(45).
          -- These see only users who share at least one group scope.
          -- Recruitment (20) is handled above with broader access.
          WHEN v_caller_role_level BETWEEN 10 AND 45
           AND v_caller_role_level <> 20 THEN
            v_caller_group_ids IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM   public.user_scopes us_t
              WHERE  us_t.user_id  = up.id
                AND  us_t.group_id = ANY(v_caller_group_ids)
            )

          -- Fallback for any unlisted role: deny
          ELSE FALSE
        END

    -- ── Fix 3: p_search matches name, mobile number, or email ────────────────
    AND (
      p_search IS NULL
      OR up.full_name_search ILIKE '%' || LOWER(TRIM(p_search)) || '%'
      OR up.mobile_number    ILIKE '%' || TRIM(p_search)        || '%'
      OR LOWER(COALESCE(up.email, '')) ILIKE '%' || LOWER(TRIM(p_search)) || '%'
    )
    AND (
      p_role IS NULL
      OR LOWER(r.role_name) = LOWER(p_role)
    )
    AND (
      p_group_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us_f
        WHERE  us_f.user_id  = up.id
          AND  us_f.group_id = p_group_id
      )
    )
    -- OHM2026_2070 fix preserved: accept group-level scopes for account lookup.
    AND (
      p_account_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us_f
        WHERE  us_f.user_id    = up.id
          AND  us_f.account_id = p_account_id
      )
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us_f
        JOIN   public.accounts    a  ON a.id = p_account_id
        WHERE  us_f.user_id  = up.id
          AND  us_f.group_id = a.group_id
      )
    )

  ORDER BY
    r.role_level DESC,
    up.last_name  ASC  NULLS LAST,
    up.first_name ASC  NULLS LAST;

END;
$function$;

CREATE OR REPLACE FUNCTION public.get_vacancy_edit_lock_status()
 RETURNS TABLE(is_locked boolean, mode text, reason text, locked_by_name text, locked_at timestamp with time zone, can_override boolean, can_edit boolean, schedule_description text, is_override_active boolean, override_by_name text, override_until timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_manual_locked         boolean;
  v_manual_reason         text;
  v_manual_locked_by      uuid;
  v_manual_locked_by_name text;
  v_manual_locked_at      timestamp with time zone;
  v_override_stored       boolean;
  v_override_by_id        uuid;
  v_override_by_name      text;
  v_override_until        timestamp with time zone;

  v_sched_active       boolean;
  v_final_locked       boolean;
  v_final_mode         text;
  v_final_reason       text;
  v_final_by_name      text;
  v_final_at           timestamp with time zone;

  v_override_effective boolean;
  v_role               text;
  v_can_override       boolean;
  v_can_edit           boolean;
BEGIN
  SELECT l.is_locked, l.reason, l.locked_by, up.full_name, l.locked_at,
         l.is_override_active, l.override_by, l.override_until
  INTO   v_manual_locked, v_manual_reason, v_manual_locked_by,
         v_manual_locked_by_name, v_manual_locked_at,
         v_override_stored, v_override_by_id, v_override_until
  FROM public.vacancy_edit_locks l
  LEFT JOIN public.users_profile up ON up.id = l.locked_by
  WHERE l.id = 1;

  v_manual_locked   := COALESCE(v_manual_locked, false);
  v_override_stored := COALESCE(v_override_stored, false);
  v_sched_active    := public.is_scheduled_lock_active();
  v_final_locked    := v_manual_locked OR v_sched_active;

  -- Override is effective when: stored flag set AND scheduled window still active
  -- AND no manual lock placed on top (lock_vacancy_editing clears the override).
  v_override_effective := v_override_stored AND v_sched_active AND NOT v_manual_locked;

  IF v_override_stored AND v_override_by_id IS NOT NULL THEN
    SELECT full_name INTO v_override_by_name
    FROM public.users_profile
    WHERE id = v_override_by_id;
  END IF;

  IF v_manual_locked THEN
    v_final_mode    := 'manual';
    v_final_reason  := COALESCE(v_manual_reason, 'Manual lock active');
    v_final_by_name := COALESCE(v_manual_locked_by_name, 'Unknown Admin');
    v_final_at      := v_manual_locked_at;
  ELSIF v_override_effective THEN
    v_final_mode    := 'override';
    v_final_reason  := COALESCE(v_manual_reason, 'Admin override during scheduled lock');
    v_final_by_name := 'System (Scheduled)';
    v_final_at      := timezone('Asia/Manila',
                         date_trunc('week', timezone('Asia/Manila', now()))
                         + interval '17 hours');
  ELSIF v_sched_active THEN
    v_final_mode    := 'scheduled';
    v_final_reason  := 'Weekly scheduled lock window';
    v_final_by_name := 'System';
    v_final_at      := timezone('Asia/Manila',
                         date_trunc('week', timezone('Asia/Manila', now()))
                         + interval '17 hours');
  ELSE
    v_final_mode    := NULL;
    v_final_reason  := NULL;
    v_final_by_name := NULL;
    v_final_at      := NULL;
  END IF;

  v_role         := public.get_effective_role();
  v_can_override := v_role IN ('Super Admin', 'Head Admin');

  -- can_edit = true when:
  --   (a) system fully unlocked (no manual lock, no scheduled window), OR
  --   (b) override is effective — lock bypassed for ALL roles, normal RBAC gates, OR
  --   (c) caller is SA/HA — always bypass regardless of lock state.
  -- Do NOT conflate can_override with can_edit.
  v_can_edit := NOT v_final_locked
                OR v_override_effective
                OR v_role IN ('Super Admin', 'Head Admin');

  RETURN QUERY SELECT
    v_final_locked                         AS is_locked,
    v_final_mode                           AS mode,
    v_final_reason                         AS reason,
    v_final_by_name                        AS locked_by_name,
    v_final_at                             AS locked_at,
    v_can_override                         AS can_override,
    v_can_edit                             AS can_edit,
    'Monday 5:00 PM to Tuesday 2:00 PM'::text AS schedule_description,
    v_override_effective                   AS is_override_active,
    v_override_by_name                     AS override_by_name,
    v_override_until                       AS override_until;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_vacancy_import_rows(p_batch_id uuid)
 RETURNS SETOF vacancy_import_rows
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT r.*
    FROM public.vacancy_import_rows r
   WHERE r.batch_id = p_batch_id
     AND (
       public.i_have_full_access()
       OR EXISTS (
         SELECT 1 FROM public.vacancy_import_batches b
          WHERE b.id = r.batch_id AND b.uploaded_by = auth.uid()
       )
     )
   ORDER BY r.row_number;
$function$;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  viewer_role_id uuid;
  first_name text;
  last_name text;
  computed_full_name text;
  profile_id uuid;
begin
  select id
    into viewer_role_id
  from public.roles
  where role_name = 'Viewer'
  limit 1;

  if viewer_role_id is null then
    raise exception 'Viewer role is not configured in public.roles';
  end if;

  first_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'first_name', '')), '');
  last_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'last_name', '')), '');
  computed_full_name := trim(
    both ' ' from coalesce(
      nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
      concat_ws(' ', first_name, last_name),
      split_part(coalesce(new.email, ''), '@', 1)
    )
  );

  select id
    into profile_id
  from public.users_profile
  where auth_user_id = new.id
  limit 1;

  if profile_id is null then
    insert into public.users_profile (
      auth_user_id,
      email,
      full_name,
      role_id,
      is_active
    )
    values (
      new.id,
      lower(new.email),
      computed_full_name,
      viewer_role_id,
      false
    )
    returning id into profile_id;
  else
    update public.users_profile
      set email = lower(new.email),
          full_name = computed_full_name
    where id = profile_id;
  end if;

  insert into public.notifications (
    recipient_role,
    title,
    message,
    reference_type,
    reference_id
  )
  values
    (
      'Super Admin',
      'New account request',
      computed_full_name || ' requested account access.',
      'account_request',
      profile_id
    ),
    (
      'Head Admin',
      'New account request',
      computed_full_name || ' requested account access.',
      'account_request',
      profile_id
    );

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.i_am_assigned_to_vacancy(p_vacancy_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id UUID := get_my_profile_id();
  v_hit BOOLEAN;
BEGIN
  IF v_profile_id IS NULL THEN RETURN FALSE; END IF;
  SELECT TRUE INTO v_hit
  FROM public.vacancies
  WHERE id = p_vacancy_id
    AND (hrco_user_id        = v_profile_id
      OR om_user_id          = v_profile_id
      OR atl_user_id         = v_profile_id
      OR assigned_encoder_id = v_profile_id
      OR requested_by_user_id= v_profile_id
      OR created_by          = v_profile_id
      OR created_by_user_id  = v_profile_id);
  RETURN COALESCE(v_hit, FALSE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.i_am_data_team()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.i_have_full_access()   -- Head Admin + Super Admin
      OR public.get_my_role_level() = 30; -- Encoder
$function$;

CREATE OR REPLACE FUNCTION public.i_am_encoder()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT get_my_role() = 'Encoder';
$function$;

CREATE OR REPLACE FUNCTION public.i_am_head_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT get_my_role() = 'Head Admin';
$function$;

CREATE OR REPLACE FUNCTION public.i_am_hrco()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT get_my_role() = 'HRCO';
$function$;

CREATE OR REPLACE FUNCTION public.i_am_om()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT get_my_role() = 'Operations Manager';
$function$;

CREATE OR REPLACE FUNCTION public.i_am_recruitment()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT get_my_role() = 'Recruitment Team';
$function$;

CREATE OR REPLACE FUNCTION public.i_am_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT get_my_role() = 'Super Admin';
$function$;

CREATE OR REPLACE FUNCTION public.i_have_account_scope(p_account_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT i_have_full_access() OR (p_account_id = ANY (get_my_allowed_account_ids()));
$function$;

CREATE OR REPLACE FUNCTION public.list_coverage_groups(p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(coverage_group_id uuid, coverage_code text, account_id uuid, account_name text, group_id uuid, group_name text, position_id uuid, position_name text, employment_type text, area_name text, group_status text, created_at timestamp with time zone, required_hc integer, open_count bigint, pipeline_count bigint, hr_processing_count bigint, active_count bigint, closed_count bigint, slot_total bigint, filled_hc bigint, mfr_pct numeric, is_mfr_met boolean, vacancy_tab text, active_store_count bigint, anchor_store_id uuid, anchor_store_name text, store_preview text, store_ids uuid[])
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT
    coverage_group_id,
    coverage_code,
    account_id,
    account_name,
    group_id,
    group_name,
    position_id,
    position_name,
    employment_type,
    area_name,
    group_status,
    created_at,
    required_hc,
    open_count,
    pipeline_count,
    hr_processing_count,
    active_count,
    closed_count,
    slot_total,
    filled_hc,
    mfr_pct,
    is_mfr_met,
    vacancy_tab,
    active_store_count,
    anchor_store_id,
    anchor_store_name,
    store_preview,
    store_ids
  FROM public.vw_coverage_group_shadow
  WHERE (p_account_id IS NULL OR account_id = p_account_id)
  ORDER BY created_at DESC;
$function$;

CREATE OR REPLACE FUNCTION public.list_web_vacancies(p_status text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid, p_position text DEFAULT NULL::text, p_urgency text DEFAULT NULL::text, p_aging_bucket text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_vacant_from date DEFAULT NULL::date, p_vacant_to date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_sort_by text DEFAULT 'vacant_date'::text, p_sort_dir text DEFAULT 'desc'::text)
 RETURNS TABLE(vacancy_id uuid, vcode text, account_id uuid, account_name text, group_id uuid, group_name text, store_id uuid, store_name text, position_title text, employment_type text, vacancy_status text, pipeline_status text, vacant_date date, aging_days integer, aging_bucket text, target_fill_date date, urgency text, penalty_exposure numeric, hrco_name text, row_capabilities jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'vacant_date'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'vcode',
    'account_name',
    'group_name',
    'store_name',
    'position_title',
    'vacancy_status',
    'pipeline_status',
    'vacant_date',
    'aging_days',
    'target_fill_date',
    'urgency'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by
      USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      vl.id AS vacancy_id,
      vl.vcode,
      vl.account_id,
      vl.account AS account_name,
      vl.group_id,
      vl.group_name,
      vl.store_id,
      vl.store_name,
      vl.position AS position_title,
      vl.employment_type,
      vl.status AS vacancy_status,
      vl.derived_status AS pipeline_status,
      vl.vacant_date,
      vl.aging_days::integer AS aging_days,
      CASE
        WHEN vl.aging_days IS NULL THEN 'unknown'
        WHEN vl.aging_days <= 7 THEN '0_7'
        WHEN vl.aging_days <= 14 THEN '8_14'
        WHEN vl.aging_days <= 30 THEN '15_30'
        ELSE '31_plus'
      END AS aging_bucket,
      vl.target_fill_date,
      vl.urgency_level AS urgency,
      CASE
        WHEN coalesce(v_raw.has_penalty, false)
          THEN coalesce(v_raw.penalty_amount, 0::numeric)
        ELSE 0::numeric
      END AS penalty_exposure,
      vl.hrco_name,
      jsonb_build_object(
        'can_view_detail', true,
        'can_request_closure_hint',
          coalesce(v_role_level, 0) >= 30
          AND coalesce(vl.is_archived, false) = false
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived']),
        'authority', 'rls_action_rpcs'
      ) AS row_capabilities
    FROM public.vw_vacancy_list vl
    JOIN public.vacancies v_raw ON v_raw.id = vl.id
    WHERE
      (
        coalesce(v_role_level, 0) >= 90
        OR (
          coalesce(vl.is_archived, false) = false
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
          AND (
            vl.account = ANY (public.get_my_allowed_accounts())
            OR
            EXISTS (
              SELECT 1
              FROM public.user_scopes us
              WHERE us.user_id = v_profile_id
                AND us.account_id = vl.account_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.user_scopes us
              JOIN public.accounts a ON a.id = vl.account_id
              WHERE us.user_id = v_profile_id
                AND us.account_id IS NULL
                AND us.group_id = a.group_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.users_profile up_fallback
              JOIN public.accounts a ON a.id = vl.account_id
              WHERE up_fallback.id = v_profile_id
                AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_scopes us_any
                  WHERE us_any.user_id = v_profile_id
                    AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
                )
                AND (
                  up_fallback.account_id = vl.account_id
                  OR up_fallback.group_id = a.group_id
                )
            )
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_status IS NULL OR lower(s.vacancy_status) = lower(btrim(p_status)) OR lower(s.pipeline_status) = lower(btrim(p_status)))
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_position IS NULL OR lower(s.position_title) = lower(btrim(p_position)))
      AND (p_urgency IS NULL OR lower(coalesce(s.urgency, '')) = lower(btrim(p_urgency)))
      AND (p_aging_bucket IS NULL OR s.aging_bucket = lower(btrim(p_aging_bucket)))
      AND (p_vacant_from IS NULL OR s.vacant_date >= p_vacant_from)
      AND (p_vacant_to IS NULL OR s.vacant_date <= p_vacant_to)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.group_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.store_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.vacancy_id,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.employment_type,
    c.vacancy_status,
    c.pipeline_status,
    c.vacant_date,
    c.aging_days,
    c.aging_bucket,
    c.target_fill_date,
    c.urgency,
    c.penalty_exposure,
    c.hrco_name,
    c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title'   THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title'   THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vacancy_status'   THEN c.vacancy_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vacancy_status'   THEN c.vacancy_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'pipeline_status'  THEN c.pipeline_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'pipeline_status'  THEN c.pipeline_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vacant_date'      THEN c.vacant_date END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vacant_date'      THEN c.vacant_date END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'target_fill_date' THEN c.target_fill_date END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'target_fill_date' THEN c.target_fill_date END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'urgency'          THEN c.urgency END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'urgency'          THEN c.urgency END DESC NULLS LAST,
    c.vcode ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

CREATE OR REPLACE FUNCTION public.lock_vacancy_editing(p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role      text;
  v_user_id   uuid;
  v_old_state jsonb;
  v_new_state jsonb;
BEGIN
  v_role := public.get_effective_role();
  IF v_role NOT IN ('Super Admin', 'Head Admin') THEN
    RAISE EXCEPTION 'Access Denied: Head Admin or Super Admin only' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason is required for manual lock' USING ERRCODE = '22000';
  END IF;

  v_user_id := public.get_current_profile_id();

  SELECT to_jsonb(l.*) INTO v_old_state
  FROM public.vacancy_edit_locks l WHERE l.id = 1;

  UPDATE public.vacancy_edit_locks
  SET is_locked         = true,
      lock_mode         = 'manual',
      is_override_active = false,
      override_by       = NULL,
      override_until    = NULL,
      reason            = p_reason,
      locked_by         = v_user_id,
      locked_at         = now(),
      unlocked_by       = NULL,
      unlocked_at       = NULL,
      updated_at        = now()
  WHERE id = 1;

  SELECT to_jsonb(l.*) INTO v_new_state
  FROM public.vacancy_edit_locks l WHERE l.id = 1;

  INSERT INTO public.vacancy_edit_lock_audit (
    action_type, actor_user_id, actor_role, reason, previous_state, new_state
  ) VALUES ('lock', v_user_id, v_role, p_reason, v_old_state, v_new_state);

  RETURN jsonb_build_object('success', true, 'is_locked', true, 'locked_at', now());
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_for_correction(p_id uuid, p_issues jsonb, p_hr_remarks text DEFAULT NULL::text)
 RETURNS hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old     public.hr_emploc;
  v_new     public.hr_emploc;
  v_issue   jsonb;
  v_code    text;
  v_comment text;
  v_needs_comment boolean;
BEGIN
  IF NOT (i_am_hr_dept() OR i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: HR Dept role required' USING ERRCODE = '42501';
  END IF;

  IF p_issues IS NULL
     OR jsonb_typeof(p_issues) <> 'array'
     OR jsonb_array_length(p_issues) = 0 THEN
    RAISE EXCEPTION 'p_issues must be a non-empty JSONB array of {code, comment} objects'
      USING ERRCODE = '22023';
  END IF;

  FOR v_issue IN SELECT * FROM jsonb_array_elements(p_issues) LOOP
    v_code    := NULLIF(BTRIM(COALESCE(v_issue->>'code', '')), '');
    v_comment := BTRIM(COALESCE(v_issue->>'comment', ''));

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'each issue entry must include a non-empty code'
        USING ERRCODE = '22023';
    END IF;

    SELECT requires_comment
      INTO v_needs_comment
      FROM hr_emploc_issue_types
     WHERE code = v_code AND is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'unknown or inactive issue code: %', v_code
        USING ERRCODE = '22023';
    END IF;

    IF v_needs_comment AND v_comment = '' THEN
      RAISE EXCEPTION 'comment is required for issue code: %', v_code
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  SELECT * INTO v_old FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;

  UPDATE hr_emploc
     SET hr_status            = 'For Correction',
         status               = 'For Compliance',
         correction_reason    = p_issues,
         hr_remarks           = COALESCE(
                                  NULLIF(BTRIM(COALESCE(p_hr_remarks, '')), ''),
                                  hr_remarks
                                ),
         hr_reviewed_at       = now(),
         hr_reviewed_by       = get_my_full_name(),
         hr_reviewed_by_user_id = get_my_profile_id(),
         updated_at           = now(),
         updated_by           = get_my_profile_id()
   WHERE id = p_id
   RETURNING * INTO v_new;

  PERFORM log_audit_event('hr_emploc', 'UPDATE', p_id, to_jsonb(v_old), to_jsonb(v_new));
  RETURN v_new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_vacancy_filled(p_vacancy_id uuid, p_applicant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := get_my_profile_id();
  v_role       text := get_my_role();
  v_role_lvl   int  := get_my_role_level();
  v            public.vacancies;
  v_app        public.applicants;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  -- Encoder, HRCO, OM, SA, HA can mark filled
  IF v_role NOT IN ('Super Admin','Head Admin','Encoder','HRCO','Operations Manager') THEN
    RAISE EXCEPTION 'Role % cannot mark vacancy filled', v_role USING ERRCODE='42501';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;
  IF NOT (public.i_have_full_access() OR public.i_have_account_scope(v.account_id)) THEN
    RAISE EXCEPTION 'Vacancy outside your scope' USING ERRCODE='42501';
  END IF;
  IF v.status <> 'Open' THEN
    RAISE EXCEPTION 'Only Open vacancies can be marked Filled (current: %)', v.status
      USING ERRCODE='check_violation';
  END IF;

  IF p_applicant_id IS NOT NULL THEN
    SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Applicant not found: %', p_applicant_id; END IF;
    IF v_app.vacancy_vcode IS DISTINCT FROM v.vcode THEN
      RAISE EXCEPTION 'Applicant % is not assigned to vacancy %', p_applicant_id, p_vacancy_id;
    END IF;
    UPDATE public.applicants
       SET status='Hired', hired_date = COALESCE(hired_date, CURRENT_DATE),
           hired_at = COALESCE(hired_at, now()),
           deployed_by_user_id = v_profile_id,
           updated_by = v_profile_id, updated_at = now()
     WHERE id = p_applicant_id;
  END IF;

  UPDATE public.vacancies
     SET status='Filled', updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','APPROVAL', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Filled','semantic_action','MARK_VACANCY_FILLED',
                       'applicant_id', p_applicant_id, 'actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status','Filled', 'applicant_id', p_applicant_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
/*
  OHM2026_0081: for the pure-stationary path, fn_sync_slot_to_occupied is now
  called BEFORE the vacancy status updates, and both vacancy-closing UPDATEs
  carry a NOT EXISTS slot guard.  Only when all non-closed slots are occupied
  (no open/pipeline/hr_processing remaining) does the vacancy transition to
  'Filled' — preventing premature archival on the first hire of a multi-slot
  vacancy.

  All other paths (pool, roving, CGCODE coverage) are unchanged.
*/
DECLARE
  v_emp             public.hr_emploc;
  v_pl              public.plantilla;
  v_actor           uuid := get_my_profile_id();
  v_is_pool         boolean := false;
  v_pool_type_id    uuid;
  v_home_account_id uuid;
  v_home_acct       public.accounts;
BEGIN
  -- Data Team = Encoder + Head Admin + Super Admin
  IF NOT (i_have_full_access() OR get_my_role() = 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;
  IF v_emp.status <> 'Ready for Plantilla' THEN
    RAISE EXCEPTION 'cannot move: status is "%", expected "Ready for Plantilla"', v_emp.status
      USING ERRCODE = '22023';
  END IF;
  IF v_emp.employee_no IS NULL THEN
    RAISE EXCEPTION 'cannot move: employee_no is null' USING ERRCODE = '22023';
  END IF;

  -- Guard A: hr_emploc_id already active in plantilla
  IF EXISTS (
    SELECT 1
      FROM public.plantilla
     WHERE hr_emploc_id              = p_id
       AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'hr_emploc % already moved to plantilla', p_id USING ERRCODE = '23505';
  END IF;

  -- Guard B: moved_to_plantilla_at already stamped
  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION
      'hr_emploc % already has moved_to_plantilla_at set', p_id USING ERRCODE = '23505';
  END IF;

  -- Detect pool vacancy
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  -- ── POOL PATH ───────────────────────────────────────────────────────────────
  IF v_is_pool THEN

    IF v_home_account_id IS NULL THEN
      RAISE EXCEPTION 'pool vacancy % has no home_account_id — cannot route to pool',
        v_emp.vcode USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'home account % not found', v_home_account_id USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE employee_no = v_emp.employee_no
         AND account_id  = v_home_account_id
         AND is_deleted  = false
         AND status IN ('Active', 'For Deactivation', 'On Leave')
    ) THEN
      RAISE EXCEPTION
        'pool plantilla already has active record for employee_no % under home account',
        v_emp.employee_no USING ERRCODE = '23505';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      is_pool_employee,     pool_type_id,
      requesting_account,   requesting_account_id,   requesting_store_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_home_acct.account_name, v_home_acct.id,
      NULL, NULL,
      v_emp.position,           v_emp.position_id_snapshot,
      v_emp.employee_no,        v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,       v_emp.philhealth_snapshot,    v_emp.pagibig_snapshot,
      v_emp.hired_date,         v_emp.vacancy_id,             v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,          v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot,  v_emp.area_name_snapshot,
      v_emp.id,
      true,                     v_pool_type_id,
      v_emp.account,            v_emp.account_id,             v_emp.store_id,
      'Active',                 CURRENT_DATE,
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    -- Close via vacancy_id if available (pool vacancy semantics: single-slot)
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    -- VCODE fallback: close any remaining Open vacancy for this VCODE
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

    -- Mark pool slot occupied
    UPDATE public.workforce_pool_slots
       SET status     = 'filled',
           updated_at = NOW()
     WHERE vcode      = v_emp.vcode
       AND deleted_at IS NULL;

  -- ── ROVING PATH ─────────────────────────────────────────────────────────────
  ELSIF v_emp.assignment_type = 'Roving' THEN

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE roving_assignment_id = v_emp.roving_assignment_id
         AND is_deleted = false
    ) THEN
      RAISE EXCEPTION
        'roving plantilla master already exists for roving_assignment_id %. '
        'Use link_late_store_to_plantilla for new store additions.',
        v_emp.roving_assignment_id USING ERRCODE = '23505';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM hr_emploc_store_links
       WHERE hr_emploc_id = p_id
         AND status       = 'Confirmed'
         AND deleted_at   IS NULL
    ) THEN
      RAISE EXCEPTION 'no confirmed store links found for roving hr_emploc %', p_id
        USING ERRCODE = '22023';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,         pagibig_no,
      date_hired,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      roving_assignment_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,            updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
      v_emp.position, v_emp.position_id_snapshot,
      v_emp.employee_no, v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.roving_assignment_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    INSERT INTO public.plantilla_store_links (
      plantilla_id,
      roving_assignment_id,
      hr_emploc_store_link_id,
      vacancy_id,
      vcode,
      store_name,
      account,
      status,
      linked_at,
      linked_by,
      created_by,
      updated_by
    )
    SELECT
      v_pl.id,
      sl.roving_assignment_id,
      sl.id,
      sl.vacancy_id,
      sl.vcode,
      sl.store_name,
      sl.account,
      'Active',
      NOW(),
      v_actor,
      v_actor,
      v_actor
    FROM public.hr_emploc_store_links sl
    WHERE sl.hr_emploc_id = p_id
      AND sl.status       = 'Confirmed'
      AND sl.deleted_at   IS NULL;

    -- Close confirmed store vacancies via vacancy_id
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE id IN (
       SELECT vacancy_id
         FROM public.hr_emploc_store_links
        WHERE hr_emploc_id = p_id
          AND status       = 'Confirmed'
          AND deleted_at   IS NULL
          AND vacancy_id   IS NOT NULL
     )
     AND status NOT IN ('Filled', 'Closed', 'Archived');

    -- VCODE fallback: close any remaining Open vacancy for the roving VCODE
    -- (v_emp.vcode is NULL for roving masters — this is a safe no-op)
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

  -- ── STATIONARY PATH / CGCODE COVERAGE SUB-PATH ─────────────────────────────
  ELSE

    IF v_emp.coverage_slot_id IS NOT NULL THEN
      -- ── CGCODE COVERAGE SUB-PATH (unchanged) ─────────────────────────────
      INSERT INTO plantilla (
        account,              account_id,           chain_id,             province_id,
        position,             position_id,
        employee_no,          emploc_no,
        employee_name,        employee_name_snapshot,
        civil_status,         date_of_birth,
        sss_no,               philhealth_no,         pagibig_no,
        date_hired,           vacancy_id,            vacancy_code_snapshot,
        vcode,
        hrco_name,            hrco_user_id_snapshot,
        om_user_id_snapshot,  atl_user_id_snapshot,
        area,                 area_name_snapshot,
        hr_emploc_id,
        coverage_slot_id,     coverage_group_id,
        deployment_type,
        status,               tagged_at,
        moved_by_user_id,     created_by,            updated_by,
        created_at,           updated_at
      )
      VALUES (
        v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
        v_emp.position, v_emp.position_id_snapshot,
        v_emp.employee_no, v_emp.employee_no,
        COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
        COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
        v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
        v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
        v_emp.hired_date, v_emp.vacancy_id, v_emp.vacancy_code_snapshot,
        v_emp.vcode,
        v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
        v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
        v_emp.area_name_snapshot, v_emp.area_name_snapshot,
        v_emp.id,
        v_emp.coverage_slot_id, v_emp.coverage_group_id,
        'Roving',
        'Active', CURRENT_DATE,
        v_actor, v_actor, v_actor,
        NOW(), NOW()
      )
      RETURNING * INTO v_pl;

      -- Close carrier CGCODE vacancy via vacancy_id if available (unchanged)
      IF v_emp.vacancy_id IS NOT NULL THEN
        UPDATE vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor
         WHERE id = v_emp.vacancy_id;
      END IF;

      -- VCODE fallback: close any remaining Open carrier vacancy (unchanged)
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE vcode      = v_emp.vcode
         AND status     IN ('Open', 'For Sourcing')
         AND COALESCE(is_archived, false) = false
         AND deleted_at IS NULL;

    ELSE
      -- ── PURE STATIONARY PATH ──────────────────────────────────────────────
      -- OHM2026_0081: fn_sync_slot_to_occupied is called HERE (before the
      -- vacancy update) so the slot is 'occupied' when the NOT EXISTS guard
      -- evaluates. This prevents premature 'Filled' + archival on the first
      -- hire of a multi-slot (HC>1) vacancy.

      IF EXISTS (
        SELECT 1 FROM plantilla
         WHERE employee_no = v_emp.employee_no
           AND is_deleted  = false
           AND status IN ('Active', 'For Deactivation', 'On Leave')
      ) THEN
        RAISE EXCEPTION 'plantilla already has active record for employee_no %',
          v_emp.employee_no USING ERRCODE = '23505';
      END IF;

      INSERT INTO plantilla (
        account,              account_id,            chain_id,             store_id,
        store_name,           position,              position_id,
        province_id,
        employee_no,          emploc_no,
        employee_name,        employee_name_snapshot,
        civil_status,         date_of_birth,
        sss_no,               philhealth_no,          pagibig_no,
        date_hired,           vacancy_id,              vacancy_code_snapshot,
        vcode,
        hrco_name,            hrco_user_id_snapshot,
        om_user_id_snapshot,  atl_user_id_snapshot,
        area,                 area_name_snapshot,
        hr_emploc_id,
        status,               tagged_at,
        moved_by_user_id,     created_by,              updated_by,
        created_at,           updated_at
      )
      VALUES (
        v_emp.account,        v_emp.account_id,       v_emp.chain_id,       v_emp.store_id,
        v_emp.store_name,     v_emp.position,         v_emp.position_id_snapshot,
        v_emp.province_id,
        v_emp.employee_no,    v_emp.employee_no,
        COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
        COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
        v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
        v_emp.sss_snapshot,   v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
        v_emp.hired_date,     v_emp.vacancy_id,        v_emp.vacancy_code_snapshot,
        v_emp.vcode,
        v_emp.hrco_name,      v_emp.hrco_user_id_snapshot,
        v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
        v_emp.area_name_snapshot, v_emp.area_name_snapshot,
        v_emp.id,
        'Active',             CURRENT_DATE,
        v_actor, v_actor, v_actor, NOW(), NOW()
      )
      RETURNING * INTO v_pl;

      -- OHM2026_0081 §1a: sync slot to occupied BEFORE the vacancy status
      -- update. After this call the current slot's slot_status = 'occupied',
      -- so the NOT EXISTS guard below correctly sees only the remaining
      -- unfilled slots when deciding whether to close the vacancy.
      PERFORM public.fn_sync_slot_to_occupied(
        p_vcode        => v_emp.vcode,
        p_hr_emploc_id => p_id,
        p_plantilla_id => v_pl.id,
        p_performed_by => v_actor,
        p_source_fn    => 'move_to_plantilla'
      );

      -- OHM2026_0081 §1b: close via vacancy_id only when all slots occupied.
      -- For HC=1 vacancies the NOT EXISTS is satisfied immediately (the just-
      -- synced slot is the only one). For HC=N, it fires only on the N-th hire.
      IF v_emp.vacancy_id IS NOT NULL THEN
        UPDATE vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor
         WHERE id = v_emp.vacancy_id
           AND NOT EXISTS (
             SELECT 1 FROM public.plantilla_slots ps
             WHERE ps.legacy_vcode = v_emp.vcode
               AND ps.is_roving    = false
               AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
           );
      END IF;

      -- OHM2026_0081 §1b: VCODE fallback — same NOT EXISTS guard.
      -- Only marks Filled (and triggers on_vacancy_filled_archive → is_archived)
      -- when truly every slot is occupied.
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE vcode      = v_emp.vcode
         AND status     IN ('Open', 'For Sourcing')
         AND COALESCE(is_archived, false) = false
         AND deleted_at IS NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.plantilla_slots ps
           WHERE ps.legacy_vcode = v_emp.vcode
             AND ps.is_roving    = false
             AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
         );

    END IF; -- end coverage/pure-stationary split

  END IF; -- end pool/roving/stationary split

  -- ── Common: update hr_emploc status ─────────────────────────────────────────
  UPDATE hr_emploc
     SET status                = 'Moved to Plantilla',
         hr_status             = 'Transferred',
         moved_to_plantilla_at = NOW(),
         moved_to_plantilla_by = v_actor,
         updated_at            = NOW(),
         updated_by            = v_actor
   WHERE id = p_id;

  PERFORM log_audit_event('plantilla', 'INSERT', v_pl.id, NULL, to_jsonb(v_pl));
  PERFORM log_audit_event('hr_emploc', 'UPDATE', p_id, to_jsonb(v_emp),
                          to_jsonb((SELECT h FROM hr_emploc h WHERE h.id = p_id)));

  -- OHM2026_0081 §1c: fn_sync_slot_to_occupied is now called inside the pure-
  -- stationary sub-path (before the vacancy update). Only fn_sync_coverage_slot_
  -- to_active remains here for the CGCODE coverage path.
  -- Pool path and roving path never called fn_sync_slot_to_occupied (unchanged).
  IF v_emp.coverage_slot_id IS NOT NULL THEN
    PERFORM public.fn_sync_coverage_slot_to_active(
      p_coverage_slot_id => v_emp.coverage_slot_id,
      p_plantilla_id     => v_pl.id,
      p_performed_by     => v_actor,
      p_source_fn        => 'move_to_plantilla'
    );
  END IF;

  RETURN v_pl;
END
$function$;

CREATE OR REPLACE FUNCTION public.on_auth_user_password_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_profile_id UUID;
  v_full_name  TEXT;
BEGIN
  IF NEW.encrypted_password IS DISTINCT FROM OLD.encrypted_password THEN
    -- Resolve linked user profile
    SELECT id, full_name
      INTO v_profile_id, v_full_name
      FROM public.users_profile
     WHERE auth_user_id = NEW.id;

    -- Insert password change audit entry
    INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      NEW.id,
      'User Profile',
      'CHANGE_PASSWORD'::public.audit_action,
      COALESCE(v_profile_id, NEW.id),
      jsonb_build_object('email', NEW.email, 'full_name', v_full_name, 'action', 'Password updated'),
      jsonb_build_object('email', NEW.email, 'full_name', v_full_name, 'action', 'Password successfully updated')
    );
  END IF;
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Swallow error to ensure auth.users password updates never fail/lockout
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.plantilla_request_deactivation(p_plantilla_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.plantilla;
  v_profile_id uuid;
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
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope'
      USING errcode = '42501';
  END IF;

  IF v_row.status = 'For Deactivation' THEN
    RETURN v_row;
  END IF;

  UPDATE public.plantilla
  SET status              = 'For Deactivation',
      for_deactivation_at = NOW(),
      for_deactivation_by = v_profile_id,
      remarks             = COALESCE(NULLIF(TRIM(p_reason), ''), remarks),
      updated_by          = v_profile_id,
      updated_at          = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  PERFORM public._log_employee_action(
    p_plantilla_id,
    'REQUEST_DEACTIVATION',
    format('Deactivation requested for %s', v_row.employee_name),
    NULL,
    jsonb_build_object('status', 'For Deactivation')
  );

  RETURN v_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.plantilla_request_deletion(p_plantilla_id uuid, p_reason text, p_remarks text DEFAULT NULL::text)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_row public.plantilla;
BEGIN
  IF NOT public.i_can_act_on_plantilla() THEN
    RAISE EXCEPTION 'forbidden: insufficient role for deletion request';
  END IF;

  -- ── Audit Freeze Gate (Phase 2A) ──────────────────────────────────────────
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_manual_deletion_actions');

  IF p_reason NOT IN ('Store Closed','Position No Longer Needed','Duplicate','Wrong Entry') THEN
    RAISE EXCEPTION 'invalid deletion_reason: %', p_reason;
  END IF;

  SELECT * INTO v_row FROM public.plantilla
  WHERE id = p_plantilla_id AND COALESCE(is_deleted, FALSE) = FALSE
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plantilla not found'; END IF;

  IF v_row.status = 'Active' THEN
    RAISE EXCEPTION 'cannot delete an Active employee';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope';
  END IF;

  UPDATE public.plantilla
  SET deletion_requested_at = NOW(),
      deletion_requested_by = auth.uid(),
      deletion_reason       = p_reason,
      deletion_remarks      = p_remarks,
      updated_by            = auth.uid(),
      updated_at            = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.plantilla_sync_mika(p_plantilla_id uuid, p_sss text DEFAULT NULL::text, p_philhealth text DEFAULT NULL::text, p_pagibig text DEFAULT NULL::text, p_atm text DEFAULT NULL::text, p_civil_status text DEFAULT NULL::text, p_date_of_birth date DEFAULT NULL::date)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.plantilla;
  v_role text := public.get_my_role();
begin
  if v_role = 'Viewer' then
    raise exception 'forbidden: viewer cannot sync MIKA data' using errcode = '42501';
  end if;

  select * into v_row
  from public.plantilla
  where id = p_plantilla_id
    and coalesce(is_deleted, false) = false
  for update;

  if not found then
    raise exception 'plantilla not found';
  end if;

  if not public.i_have_full_access()
     and not (v_row.account = any(public.get_my_allowed_accounts())) then
    raise exception 'forbidden: account out of scope' using errcode = '42501';
  end if;

  if v_row.last_mika_synced_at is not null
     and v_row.last_mika_synced_at > now() - interval '5 minutes' then
    raise exception 'MIKA sync cooldown active. Try again after 5 minutes.' using errcode = '42501';
  end if;

  update public.plantilla
  set sss_no              = coalesce(p_sss,           sss_no),
      philhealth_no       = coalesce(p_philhealth,    philhealth_no),
      pagibig_no          = coalesce(p_pagibig,       pagibig_no),
      atm_no              = coalesce(p_atm,           atm_no),
      civil_status        = coalesce(p_civil_status,  civil_status),
      date_of_birth       = coalesce(p_date_of_birth, date_of_birth),
      last_mika_synced_at = now(),
      last_mika_synced_by = auth.uid(),
      updated_by          = auth.uid(),
      updated_at          = now()
  where id = p_plantilla_id
  returning * into v_row;

  perform public._log_employee_action(
    p_plantilla_id,
    'MIKA_SYNC',
    format('%s synced MIKA data', public.get_my_full_name()),
    null,
    jsonb_build_object(
      'synced_by_role', v_role,
      'synced_at', now()
    )
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION public.plantilla_transfer(p_plantilla_id uuid, p_target_store_id uuid, p_target_position_id uuid DEFAULT NULL::uuid, p_remarks text DEFAULT NULL::text)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row             public.plantilla;
  v_store           public.stores;
  v_position_id_eff uuid;
  v_filled_after    int;
  v_required_max    int;
begin
  if not public._can_act_on_plantilla(p_plantilla_id, 'reassign') then
    raise exception 'forbidden: Ops role required for plantilla transfer' using errcode = '42501';
  end if;

  select * into v_row
  from public.plantilla
  where id = p_plantilla_id
    and coalesce(is_deleted, false) = false
  for update;

  if not found then
    raise exception 'plantilla not found';
  end if;

  if not public.i_have_full_access()
     and not (v_row.account = any(public.get_my_allowed_accounts())) then
    raise exception 'forbidden: account out of scope' using errcode = '42501';
  end if;

  select * into v_store
  from public.stores
  where id = p_target_store_id;

  if not found then
    raise exception 'target store not found: %', p_target_store_id;
  end if;

  if v_store.account_id is distinct from v_row.account_id then
    raise exception 'cross-account transfer is not allowed';
  end if;

  v_position_id_eff := coalesce(p_target_position_id, v_row.position_id);

  update public.plantilla
  set store_id                  = v_store.id,
      store_name                = v_store.store_name,
      area                      = coalesce(v_store.area_city, area),
      province_id               = coalesce(v_store.id, province_id),
      transferred_from_store_id = v_row.store_id,
      last_transfer_at          = now(),
      last_transfer_by          = auth.uid(),
      position_id               = v_position_id_eff,
      remarks                   = coalesce(p_remarks, remarks),
      updated_by                = auth.uid(),
      updated_at                = now()
  where id = p_plantilla_id;

  select count(*) into v_filled_after
  from public.plantilla
  where store_id = v_store.id
    and position_id = v_position_id_eff
    and status = 'Active'
    and coalesce(is_deleted, false) = false;

  select coalesce(max(required_headcount), 0) into v_required_max
  from public.vacancies
  where store_id = v_store.id
    and position_id = v_position_id_eff;

  update public.plantilla
  set over_headcount = (v_required_max > 0 and v_filled_after > v_required_max)
  where id = p_plantilla_id
  returning * into v_row;

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION public.plantilla_update_separation(p_plantilla_id uuid, p_separation_status text, p_effective_date date, p_remarks text DEFAULT NULL::text)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row              public.plantilla;
  v_sep_reason_code  text;  -- Phase 6.4 slot reason code (OHM2026_0072)
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'separate') THEN
    RAISE EXCEPTION 'forbidden: Ops role required for plantilla status update'
      USING ERRCODE = '42501';
  END IF;

  IF p_effective_date IS NULL THEN
    RAISE EXCEPTION 'effective_date is required';
  END IF;

  IF p_separation_status NOT IN ('Resigned','AWOL','Terminated','End of Contract','Endo','Others') THEN
    RAISE EXCEPTION 'invalid separation_status: %', p_separation_status;
  END IF;

  SELECT * INTO v_row
  FROM public.plantilla
  WHERE id = p_plantilla_id
    AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found: %', p_plantilla_id;
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.plantilla
     SET separation_status  = p_separation_status,
         date_of_separation = p_effective_date,
         status             = 'Inactive',
         remarks            = COALESCE(p_remarks, remarks),
         updated_by         = auth.uid(),
         updated_at         = NOW()
   WHERE id = p_plantilla_id
   RETURNING * INTO v_row;

  -- ── Phase 6.4: non-blocking slot occupied→open sync (OHM2026_0072) ──────
  -- Mirrors the hook added to _apply_separation by 20260813000004 (OHM2026_0022).
  -- When the employee's slot is 'occupied' (wired by OHM2026_0071 import backfill
  -- or by the Phase 6.3 hr_processing→occupied transition), fn_sync_slot_to_open
  -- transitions it to 'open', clears current_occupant_plantilla_id, and appends
  -- slot_history — making the vacancy visible again in the Vacancy Open tab.
  --
  -- Reason code: Endo / End of Contract → ENDO; everything else → RESIGNED.
  -- Roving carve-out: deployment_type = 'Roving' → skip (OHM2026_0017 Q6).
  -- fn_sync_slot_to_open NEVER raises; errors are RAISE NOTICE only.
  IF COALESCE(v_row.deployment_type, '') <> 'Roving' THEN
    v_sep_reason_code := CASE p_separation_status
      WHEN 'Endo'            THEN 'ENDO'
      WHEN 'End of Contract' THEN 'ENDO'
      ELSE 'RESIGNED'
    END;

    PERFORM public.fn_sync_slot_to_open(
      p_plantilla_id => p_plantilla_id,
      p_reason_code  => v_sep_reason_code,
      p_performed_by => public.get_current_profile_id(),
      p_source_fn    => 'plantilla_update_separation'
    );
  END IF;

  RETURN v_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_hr_emploc_import(p_batch_id uuid, p_reason_code text, p_reason_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id    UUID;
  v_profile_id   UUID;
  v_status       TEXT;
  v_reject_row   RECORD;
  v_slot_id      UUID;
  v_prior_status TEXT;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can reject HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_reason_code IS NULL OR TRIM(p_reason_code) = '' THEN
    RAISE EXCEPTION 'Rejection reason code is required' USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO v_status
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;
  IF v_status <> 'pending_approval' THEN
    RAISE EXCEPTION 'Only pending_approval batches can be rejected (current status: %)', v_status
      USING ERRCODE = 'P0001';
  END IF;

  FOR v_reject_row IN
    SELECT vcode FROM public.hr_emploc_import_rows
    WHERE batch_id = p_batch_id AND validation_status = 'valid'
  LOOP
    v_slot_id      := NULL;
    v_prior_status := NULL;

    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE legacy_vcode = v_reject_row.vcode
    LIMIT 1;

    IF v_slot_id IS NULL THEN
      RAISE NOTICE
        'reject_hr_emploc_import: Plantilla slot not found for vcode % in batch % — skipping slot restoration.',
        v_reject_row.vcode, p_batch_id;
      CONTINUE;
    END IF;

    SELECT sh.old_value INTO v_prior_status
    FROM public.slot_history sh
    WHERE sh.slot_id     = v_slot_id
      AND sh.action_type = 'import_reserved'
      AND sh.remarks     = 'import_batch:' || p_batch_id::TEXT
    ORDER BY sh.created_at DESC
    LIMIT 1;

    IF v_prior_status IS NULL THEN
      RAISE NOTICE
        'reject_hr_emploc_import: no import_reserved entry in slot_history for slot % '
        '(vcode %) batch % — slot was already hr_processing before submit; leaving unchanged.',
        v_slot_id, v_reject_row.vcode, p_batch_id;
      CONTINUE;
    END IF;

    IF v_prior_status = 'open' THEN
      PERFORM public.fn_set_slot_status(
        p_slot_id      => v_slot_id,
        p_new_status   => 'open',
        p_performed_by => v_profile_id,
        p_remarks      => 'import_batch_rejected:' || p_batch_id::TEXT
      );

    ELSIF v_prior_status = 'pipeline' THEN
      PERFORM public.fn_set_slot_status(
        p_slot_id      => v_slot_id,
        p_new_status   => 'pipeline',
        p_performed_by => v_profile_id,
        p_remarks      => 'import_batch_rejected:' || p_batch_id::TEXT
      );

    ELSIF v_prior_status = 'hr_processing' THEN
      RAISE NOTICE
        'reject_hr_emploc_import: slot % was hr_processing before batch % — no restoration.',
        v_slot_id, p_batch_id;

    ELSE
      RAISE NOTICE
        'reject_hr_emploc_import: unexpected prior status "%" for slot % (vcode %) batch %. Leaving unchanged.',
        v_prior_status, v_slot_id, v_reject_row.vcode, p_batch_id;
    END IF;
  END LOOP;

  UPDATE public.hr_emploc_import_batches SET
    status                = 'rejected',
    rejected_by           = v_profile_id,
    rejected_at           = now(),
    rejection_reason_code = p_reason_code,
    rejection_reason_note = p_reason_note
  WHERE id = p_batch_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_new_store_request(p_request_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_reviewer_id     uuid;
  v_reviewer_name   text;
  v_reviewer_role   text;
  v_req             public.new_store_requests;
  v_requester_auth  uuid;
  v_requester_role  text;
BEGIN
  -- ── Auth guard ────────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Insufficient permissions — Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Reason is mandatory for rejection
  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'Rejection reason is required'
      USING ERRCODE = '22023';
  END IF;

  v_reviewer_id := public.get_current_profile_id();
  IF v_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Resolve reviewer display name ─────────────────────────────
  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'admin')
  INTO v_reviewer_name, v_reviewer_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_reviewer_id;

  -- ── Lock and load request row ─────────────────────────────────
  SELECT * INTO v_req
  FROM public.new_store_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'New store request not found: %', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is not in pending status (current: %)', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Mark rejected ─────────────────────────────────────────────
  UPDATE public.new_store_requests SET
    status           = 'rejected',
    reviewed_by      = v_reviewer_id,
    reviewed_by_name = v_reviewer_name,
    reviewed_at      = now(),
    review_reason    = TRIM(p_reason),
    updated_at       = now()
  WHERE id = p_request_id;

  -- ── Notify requester ──────────────────────────────────────────
  SELECT up.auth_user_id, COALESCE(ro.role_name, 'ops')
  INTO v_requester_auth, v_requester_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_req.requested_by;

  IF v_requester_auth IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users WHERE id = v_requester_auth) THEN
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_requester_role,
        v_requester_auth,
        'new_store_request',
        'NEW_STORE_REQUEST_REJECTED',
        'Store Request Rejected',
        'Your request for ' || v_req.store_name ||
          ' was rejected. Reason: ' || TRIM(p_reason) || '.',
        '/new_store_request/' || p_request_id::text,
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'reject_new_store_request: skipped requester %, role %, request_id %, error: %',
        v_requester_auth, v_requester_role, p_request_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'request_id', p_request_id,
    'status',     'rejected'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_vacancy_request(p_vacancy_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := get_my_profile_id();
  v_role       text := get_my_role();
  v            public.vacancies;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Only Super Admin or Head Admin can reject vacancies' USING ERRCODE='42501';
  END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Rejection reason is required';
  END IF;

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;

  IF v_role = 'Head Admin'
     AND EXISTS (SELECT 1 FROM public.user_scopes WHERE user_id = v_profile_id)
     AND NOT public.i_have_account_scope(v.account_id) THEN
    RAISE EXCEPTION 'Vacancy % is outside your assigned scope', p_vacancy_id USING ERRCODE='42501';
  END IF;

  IF v.status NOT IN ('Pending Approval','Draft') THEN
    RAISE EXCEPTION 'Cannot reject vacancy in status %', v.status USING ERRCODE='check_violation';
  END IF;

  UPDATE public.vacancies
     SET status = 'Rejected',
         remarks = COALESCE(remarks,'') ||
                   CASE WHEN remarks IS NULL OR remarks='' THEN '' ELSE E'\n' END ||
                   '[REJECTED] ' || p_reason,
         updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','UPDATE', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Rejected','semantic_action','REJECT_VACANCY','reason', p_reason,'actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status', 'Rejected');
END;
$function$;

CREATE OR REPLACE FUNCTION public.review_web_hr_emploc_correction(p_hr_emploc_id uuid, p_decision text, p_resolved_keys jsonb, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid                   uuid    := auth.uid();
  v_profile_id                 uuid;
  v_role_level                 integer;
  v_old                        public.hr_emploc;
  v_new                        public.hr_emploc;
  v_existing_codes             text[];
  v_resolved_codes             text[];
  v_residual_codes             text[];
  v_residual_correction_reason jsonb;
BEGIN

  -- ----------------------------------------------------------------
  -- 1. Auth guard — fail closed, no session = no access
  -- ----------------------------------------------------------------
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: correction review requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 2. Profile resolution — active, non-archived profile + role level
  -- ----------------------------------------------------------------
  SELECT up.id, r.role_level
  INTO   v_profile_id, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active    = TRUE
    AND  up.archived_at  IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR COALESCE(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: caller profile is inactive or not found'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 3. RBAC capability guard
  --    Mirrors approve_correction_request: HR Dept (hrPersonnel) or
  --    full access (headAdmin / superAdmin). All other roles denied.
  -- ----------------------------------------------------------------
  IF NOT (public.i_am_hr_dept() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: HR Personnel or Admin role required for correction review'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 4. Decision validation
  -- ----------------------------------------------------------------
  IF p_decision NOT IN ('approve', 'return') THEN
    RAISE EXCEPTION 'invalid decision: must be ''approve'' or ''return'''
      USING ERRCODE = '22023';
  END IF;

  -- ----------------------------------------------------------------
  -- 5. Lock and fetch the record
  --    FOR UPDATE prevents concurrent state changes during validation.
  -- ----------------------------------------------------------------
  SELECT * INTO v_old
  FROM   public.hr_emploc
  WHERE  id = p_hr_emploc_id
  FOR    UPDATE;

  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'forbidden: hr_emploc record not found or archived'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 6. Scope gate — non-global callers (role_level < 90) must have
  --    an account/group assignment that covers the record's account.
  --    Identical pattern to tag_web_hr_emploc_deficiency and the
  --    read RPCs for consistency.
  -- ----------------------------------------------------------------
  IF COALESCE(v_role_level, 0) < 90 THEN
    IF NOT (
      v_old.account = ANY (public.get_my_allowed_accounts())
      OR EXISTS (
        SELECT 1 FROM public.user_scopes us
        WHERE  us.user_id    = v_profile_id
          AND  us.account_id = v_old.account_id
      )
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us
        JOIN   public.accounts   ac ON ac.id = v_old.account_id
        WHERE  us.user_id    = v_profile_id
          AND  us.account_id IS NULL
          AND  us.group_id   = ac.group_id
      )
      OR EXISTS (
        SELECT 1
        FROM   public.users_profile up_f
        JOIN   public.accounts      ac ON ac.id = v_old.account_id
        WHERE  up_f.id = v_profile_id
          AND  NOT EXISTS (
            SELECT 1 FROM public.user_scopes us_any
            WHERE  us_any.user_id = v_profile_id
              AND  (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
          )
          AND  (up_f.account_id = v_old.account_id OR up_f.group_id = ac.group_id)
      )
    ) THEN
      RAISE EXCEPTION 'forbidden: hr_emploc record is outside your assigned scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ----------------------------------------------------------------
  -- 7. Terminal state guard
  --    Records already moved to Plantilla must never be modified.
  -- ----------------------------------------------------------------
  IF v_old.moved_to_plantilla_at IS NOT NULL
     OR v_old.status    = 'Moved to Plantilla'
     OR v_old.hr_status = 'Transferred'
  THEN
    RAISE EXCEPTION 'action not allowed: employee has already been moved to Plantilla'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 8. Pending deletion lock
  --    Mirrors tag_web_hr_emploc_deficiency and existing correction RPCs.
  -- ----------------------------------------------------------------
  IF EXISTS (
    SELECT 1
    FROM   public.hr_emploc_deletion_requests
    WHERE  hr_emploc_id = p_hr_emploc_id
      AND  status       = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 9. hr_status guard — must be in For Review
  -- ----------------------------------------------------------------
  IF v_old.hr_status <> 'For Review' THEN
    RAISE EXCEPTION 'action not allowed: hr_status is "%" — expected "For Review"',
      v_old.hr_status
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 10. status guard — must be Pending Emploc
  -- ----------------------------------------------------------------
  IF v_old.status <> 'Pending Emploc' THEN
    RAISE EXCEPTION 'action not allowed: status is "%" — expected "Pending Emploc"',
      v_old.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 11. Compute existing, resolved, and residual correction codes
  --     correction_reason is a JSONB array of {code, comment} objects
  --     (Web format set by tag_web_hr_emploc_deficiency).
  --     Old-format objects (non-array) yield no extractable codes.
  -- ----------------------------------------------------------------
  SELECT COALESCE(array_agg(elem->>'code'), '{}')
  INTO   v_existing_codes
  FROM   jsonb_array_elements(
           CASE WHEN jsonb_typeof(v_old.correction_reason) = 'array'
                THEN v_old.correction_reason
                ELSE '[]'::jsonb
           END
         ) elem
  WHERE  NULLIF(elem->>'code', '') IS NOT NULL;

  SELECT COALESCE(array_agg(v), '{}')
  INTO   v_resolved_codes
  FROM   jsonb_array_elements_text(COALESCE(p_resolved_keys, '[]'::jsonb)) v;

  SELECT COALESCE(array_agg(c), '{}')
  INTO   v_residual_codes
  FROM   unnest(v_existing_codes) c
  WHERE  NOT (c = ANY(v_resolved_codes));

  -- ----------------------------------------------------------------
  -- 12a. APPROVE path
  -- ----------------------------------------------------------------
  IF p_decision = 'approve' THEN

    -- All existing correction codes must appear in p_resolved_keys.
    IF COALESCE(array_length(v_residual_codes, 1), 0) > 0 THEN
      RAISE EXCEPTION
        'approve requires all existing correction keys to be resolved; % unresolved key(s) remain: %',
        COALESCE(array_length(v_residual_codes, 1), 0),
        array_to_string(v_residual_codes, ', ')
        USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.hr_emploc
    SET    hr_status         = 'Complete',
           correction_reason = NULL,
           hr_remarks        = COALESCE(
                                 NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
                                 hr_remarks
                               ),
           hr_reviewed_by    = public.get_my_full_name(),
           hr_reviewed_at    = now(),
           updated_at        = now(),
           updated_by        = v_profile_id
    WHERE  id = p_hr_emploc_id
    RETURNING * INTO v_new;

    PERFORM public.log_audit_event(
      'hr_emploc',
      'UPDATE',
      p_hr_emploc_id,
      to_jsonb(v_old),
      to_jsonb(v_new)
    );

    RETURN jsonb_build_object(
      'status',        'ok',
      'hr_emploc_id',  v_new.id,
      'decision',      'approve',
      'hr_status',     v_new.hr_status,
      'resolved_keys', to_jsonb(v_resolved_codes),
      'residual_keys', to_jsonb(ARRAY[]::text[]),
      'reviewed_by',   public.get_my_full_name(),
      'reviewed_at',   now()
    );

  END IF;

  -- ----------------------------------------------------------------
  -- 12b. RETURN path
  -- ----------------------------------------------------------------

  -- Require at least one residual key or a non-empty remark.
  IF COALESCE(array_length(v_residual_codes, 1), 0) = 0
     AND NULLIF(BTRIM(COALESCE(p_remarks, '')), '') IS NULL
  THEN
    RAISE EXCEPTION
      'return requires at least one unresolved correction key or a non-empty remark'
      USING ERRCODE = '22023';
  END IF;

  -- Build residual correction_reason: keep only items whose code is unresolved.
  IF COALESCE(array_length(v_residual_codes, 1), 0) > 0 THEN
    SELECT jsonb_agg(elem)
    INTO   v_residual_correction_reason
    FROM   jsonb_array_elements(
             CASE WHEN jsonb_typeof(v_old.correction_reason) = 'array'
                  THEN v_old.correction_reason
                  ELSE '[]'::jsonb
             END
           ) elem
    WHERE  elem->>'code' = ANY(v_residual_codes);
  ELSE
    -- All codes resolved but remark present: correction reason is cleared.
    v_residual_correction_reason := NULL;
  END IF;

  UPDATE public.hr_emploc
  SET    hr_status         = 'For Correction',
         correction_reason = v_residual_correction_reason,
         hr_remarks        = COALESCE(
                               NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
                               hr_remarks
                             ),
         hr_reviewed_by    = public.get_my_full_name(),
         hr_reviewed_at    = now(),
         updated_at        = now(),
         updated_by        = v_profile_id
  WHERE  id = p_hr_emploc_id
  RETURNING * INTO v_new;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  RETURN jsonb_build_object(
    'status',        'ok',
    'hr_emploc_id',  v_new.id,
    'decision',      'return',
    'hr_status',     v_new.hr_status,
    'resolved_keys', to_jsonb(v_resolved_codes),
    'residual_keys', to_jsonb(v_residual_codes),
    'reviewed_by',   public.get_my_full_name(),
    'reviewed_at',   now()
  );

END;
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rollback_hr_emploc_import(p_batch_id uuid, p_reason text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id   UUID;
  v_profile_id  UUID;
  v_batch       public.hr_emploc_import_batches%ROWTYPE;
  v_moved_count INTEGER;
  v_removed     INTEGER := 0;
  v_hr_row      RECORD;
  v_slot_id     UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can roll back HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'Rollback reason must be at least 10 characters'
      USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_batch
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;

  CASE v_batch.status
    WHEN 'rolled_back'      THEN RAISE EXCEPTION 'This batch has already been rolled back' USING ERRCODE = 'P0001';
    WHEN 'rejected'         THEN RAISE EXCEPTION 'Rejected batches cannot be rolled back — no records were created' USING ERRCODE = 'P0001';
    WHEN 'pending_approval' THEN RAISE EXCEPTION 'Pending batches cannot be rolled back — reject instead' USING ERRCODE = 'P0001';
    ELSE NULL;
  END CASE;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'Only approved batches can be rolled back' USING ERRCODE = 'P0001';
  END IF;

  SELECT COUNT(*) INTO v_moved_count
  FROM public.hr_emploc
  WHERE import_batch_id = p_batch_id
    AND deleted_at IS NULL
    AND status = 'Moved to Plantilla';

  IF v_moved_count > 0 THEN
    RAISE EXCEPTION
      'Rollback blocked: % record(s) from this batch have already been moved to Plantilla. Remove them from Plantilla first.',
      v_moved_count
      USING ERRCODE = 'P0001';
  END IF;

  FOR v_hr_row IN
    SELECT id, slot_id, vcode
    FROM public.hr_emploc
    WHERE import_batch_id = p_batch_id
      AND deleted_at IS NULL
  LOOP
    v_slot_id := v_hr_row.slot_id;

    IF v_slot_id IS NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_hr_row.vcode
      LIMIT 1;
    END IF;

    IF v_slot_id IS NOT NULL THEN
      PERFORM public.fn_set_slot_status(
        p_slot_id      => v_slot_id,
        p_new_status   => 'open',
        p_reason_code  => 'REPLACEMENT',
        p_performed_by => v_profile_id,
        p_remarks      => 'import_batch_rolled_back:' || p_batch_id::TEXT
      );
    ELSE
      RAISE NOTICE
        'rollback_hr_emploc_import: no slot found for hr_emploc.id=% vcode=% — slot not restored.',
        v_hr_row.id, v_hr_row.vcode;
    END IF;

    UPDATE public.vacancies
    SET
      status     = 'Open',
      updated_at = now(),
      updated_by = v_profile_id
    WHERE vcode      = v_hr_row.vcode
      AND status     = 'Filled'
      AND deleted_at IS NULL
      AND (is_archived IS NULL OR is_archived = false);

    UPDATE public.hr_emploc
    SET deleted_at = now()
    WHERE id = v_hr_row.id;

    v_removed := v_removed + 1;
  END LOOP;

  UPDATE public.hr_emploc_import_batches SET
    status          = 'rolled_back',
    rolled_back_by  = v_profile_id,
    rolled_back_at  = now(),
    rollback_reason = TRIM(p_reason)
  WHERE id = p_batch_id;

  RETURN json_build_object('records_removed', v_removed);
END;
$function$;

CREATE OR REPLACE FUNCTION public.search_global_index(p_query text, p_limit integer DEFAULT 50)
 RETURNS TABLE(result_type text, record_id text, primary_label text, secondary_label text, status text, matched_field text, group_name text, account_name text, created_at timestamp with time zone, navigation_target text, navigation_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid             uuid;
  v_profile_id      uuid;
  v_role_name       text;
  v_role_norm       text;
  v_has_full_access bool;
  v_query_clean     text;
  v_pattern         text;
  v_allowed_accts   text[];
BEGIN
  -- ── 1. Auth ──────────────────────────────────────────────────────────────
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- ── 2. Resolve caller profile & role ────────────────────────────────────
  SELECT up.id, r.role_name
  INTO v_profile_id, v_role_name
  FROM users_profile up
  JOIN roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_uid
  LIMIT 1;

  v_role_norm := _ohm_normalize_role(v_role_name);

  -- ── 3. Access gate: Data Team + superAdmin only ──────────────────────────
  IF v_role_norm NOT IN ('superadmin', 'headadmin', 'encoder') THEN
    RAISE EXCEPTION 'Access denied: Global Search is restricted to Data Team and above';
  END IF;

  -- ── 4. Full-access flag ──────────────────────────────────────────────────
  v_has_full_access := v_role_norm IN ('superadmin', 'headadmin');

  -- ── 5. Sanitize query ────────────────────────────────────────────────────
  -- Strip commas and extra whitespace
  v_query_clean := trim(regexp_replace(replace(p_query, ',', ' '), '\s+', ' ', 'g'));

  -- Reject N/A, NA, empty, or < 2 chars
  IF lower(v_query_clean) IN ('n/a', 'na', '') OR char_length(v_query_clean) < 2 THEN
    RETURN;
  END IF;

  v_pattern := '%' || upper(v_query_clean) || '%';

  -- ── 6. Resolve allowed accounts for encoder (scoped) ────────────────────
  IF NOT v_has_full_access THEN
    SELECT array_agg(DISTINCT a.account_name)
    INTO v_allowed_accts
    FROM user_scopes us
    LEFT JOIN accounts a ON a.id = us.account_id
    WHERE us.user_id = v_profile_id
      AND a.account_name IS NOT NULL;

    -- Also expand group-level scopes
    SELECT array_cat(
      v_allowed_accts,
      array_agg(DISTINCT a2.account_name)
    )
    INTO v_allowed_accts
    FROM user_scopes us2
    JOIN accounts a2 ON a2.group_id = us2.group_id
    WHERE us2.user_id = v_profile_id
      AND us2.group_id IS NOT NULL
      AND a2.account_name IS NOT NULL;

    IF v_allowed_accts IS NULL OR array_length(v_allowed_accts, 1) = 0 THEN
      RETURN; -- encoder with no scopes sees nothing
    END IF;
  END IF;

  -- ── 7. Union search with priority ordering ───────────────────────────────
  RETURN QUERY
  WITH

  -- Priority 1: exact VCODE match
  vac_exact AS (
    SELECT
      'vacancy'::text,
      v.id::text,
      v.vcode::text                                           AS primary_label,
      (COALESCE(v.position,'') || ' · ' || COALESCE(v.account,''))::text AS secondary_label,
      COALESCE(v.status,'')::text,
      'vcode'::text                                           AS matched_field,
      COALESCE(g.group_name,'')::text,
      COALESCE(v.account,'')::text,
      v.created_at::timestamptz,
      'vacancy'::text                                         AS navigation_target,
      v.vcode::text                                           AS navigation_id,
      1::int                                                  AS priority
    FROM vacancies v
    LEFT JOIN accounts ac ON lower(ac.account_name) = lower(COALESCE(v.account,''))
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE upper(v.vcode) = upper(v_query_clean)
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  -- Priority 2: exact emploc_no match
  emploc_exact AS (
    SELECT
      'hr_emploc'::text,
      he.id::text,
      COALESCE(he.emploc_no, he.id::text)::text,
      (COALESCE(he.applicant_name,'') || ' · ' || COALESCE(he.account,''))::text,
      COALESCE(he.status,'')::text,
      'emploc_no'::text,
      ''::text,
      COALESCE(he.account,'')::text,
      he.date_requested::timestamptz,
      'hr_emploc'::text,
      he.id::text,
      2::int
    FROM hr_emploc he
    WHERE upper(COALESCE(he.emploc_no,'')) = upper(v_query_clean)
      AND (v_has_full_access OR he.account = ANY(v_allowed_accts))
  ),

  -- Priority 3: Active plantilla employee name/no match
  plant_active AS (
    SELECT
      'plantilla'::text,
      p.id::text,
      COALESCE(p.employee_name,'')::text,
      (COALESCE(p.employee_no,'') || ' · ' || COALESCE(p.account,''))::text,
      COALESCE(p.status,'Active')::text,
      CASE
        WHEN upper(replace(COALESCE(p.employee_no,''),',',' ')) ILIKE v_pattern THEN 'employee_no'
        ELSE 'employee_name'
      END::text,
      ''::text,
      COALESCE(p.account,'')::text,
      p.created_at::timestamptz,
      'plantilla'::text,
      p.id::text,
      3::int
    FROM plantilla p
    WHERE p.status = 'Active'
      AND (
        upper(replace(COALESCE(p.employee_name,''),',',' ')) ILIKE v_pattern
        OR upper(replace(COALESCE(p.employee_no,''),',',' '))  ILIKE v_pattern
      )
      AND (v_has_full_access OR p.account = ANY(v_allowed_accts))
  ),

  -- Priority 4: HR Emploc applicant name match
  emploc_name AS (
    SELECT
      'hr_emploc'::text,
      he.id::text,
      COALESCE(he.applicant_name,'')::text,
      (COALESCE(he.emploc_no,'') || ' · ' || COALESCE(he.account,''))::text,
      COALESCE(he.status,'')::text,
      'applicant_name'::text,
      ''::text,
      COALESCE(he.account,'')::text,
      he.date_requested::timestamptz,
      'hr_emploc'::text,
      he.id::text,
      4::int
    FROM hr_emploc he
    WHERE upper(replace(COALESCE(he.applicant_name,''),',',' ')) ILIKE v_pattern
      AND upper(COALESCE(he.emploc_no,'')) != upper(v_query_clean)
      AND (v_has_full_access OR he.account = ANY(v_allowed_accts))
  ),

  -- Priority 5: Vacancy VCODE partial match
  vac_partial AS (
    SELECT
      'vacancy'::text,
      v.id::text,
      v.vcode::text,
      (COALESCE(v.position,'') || ' · ' || COALESCE(v.account,''))::text,
      COALESCE(v.status,'')::text,
      'vcode'::text,
      COALESCE(g.group_name,'')::text,
      COALESCE(v.account,'')::text,
      v.created_at::timestamptz,
      'vacancy'::text,
      v.vcode::text,
      5::int
    FROM vacancies v
    LEFT JOIN accounts ac ON lower(ac.account_name) = lower(COALESCE(v.account,''))
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE upper(v.vcode) ILIKE v_pattern
      AND upper(v.vcode) != upper(v_query_clean)
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  -- Priority 6: Applicant name match (linked via vacancy for scope)
  applicant_match AS (
    SELECT
      'applicant'::text,
      a.id::text,
      trim(
        COALESCE(a.first_name,'') || ' ' ||
        COALESCE(a.middle_name,'') || ' ' ||
        COALESCE(a.last_name,'')
      )::text,
      (a.vacancy_vcode || ' · ' || COALESCE(a.status,''))::text,
      COALESCE(a.status,'')::text,
      'applicant_name'::text,
      ''::text,
      COALESCE(v.account,'')::text,
      a.created_at::timestamptz,
      'vacancy'::text,
      a.vacancy_vcode::text,
      6::int
    FROM applicants a
    LEFT JOIN vacancies v ON v.vcode = a.vacancy_vcode
    WHERE upper(replace(
        trim(COALESCE(a.first_name,'') || ' ' || COALESCE(a.middle_name,'') || ' ' || COALESCE(a.last_name,'')),
        ',', ' '
      )) ILIKE v_pattern
      AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  -- Priority 7: All plantilla (inactive/deactivated) name match
  plant_all AS (
    SELECT
      'plantilla'::text,
      p.id::text,
      COALESCE(p.employee_name,'')::text,
      (COALESCE(p.employee_no,'') || ' · ' || COALESCE(p.account,''))::text,
      COALESCE(p.status,'')::text,
      CASE
        WHEN upper(replace(COALESCE(p.employee_no,''),',',' ')) ILIKE v_pattern THEN 'employee_no'
        ELSE 'employee_name'
      END::text,
      ''::text,
      COALESCE(p.account,'')::text,
      p.created_at::timestamptz,
      'plantilla'::text,
      p.id::text,
      7::int
    FROM plantilla p
    WHERE (p.status IS NULL OR p.status != 'Active')
      AND (
        upper(replace(COALESCE(p.employee_name,''),',',' ')) ILIKE v_pattern
        OR upper(replace(COALESCE(p.employee_no,''),',',' '))  ILIKE v_pattern
      )
      AND (v_has_full_access OR p.account = ANY(v_allowed_accts))
  ),

  -- Priority 8: Vacancy position/account partial match (broadest)
  vac_position AS (
    SELECT
      'vacancy'::text,
      v.id::text,
      v.vcode::text,
      (COALESCE(v.position,'') || ' · ' || COALESCE(v.account,''))::text,
      COALESCE(v.status,'')::text,
      CASE
        WHEN upper(COALESCE(v.account,'')) ILIKE v_pattern THEN 'account'
        ELSE 'position'
      END::text,
      COALESCE(g.group_name,'')::text,
      COALESCE(v.account,'')::text,
      v.created_at::timestamptz,
      'vacancy'::text,
      v.vcode::text,
      8::int
    FROM vacancies v
    LEFT JOIN accounts ac ON lower(ac.account_name) = lower(COALESCE(v.account,''))
    LEFT JOIN groups g ON g.id = ac.group_id
    WHERE (
      upper(COALESCE(v.position,'')) ILIKE v_pattern
      OR upper(COALESCE(v.account,'')) ILIKE v_pattern
    )
    AND upper(v.vcode) NOT ILIKE v_pattern
    AND (v_has_full_access OR v.account = ANY(v_allowed_accts))
  ),

  combined AS (
    SELECT * FROM vac_exact
    UNION ALL SELECT * FROM emploc_exact
    UNION ALL SELECT * FROM plant_active
    UNION ALL SELECT * FROM emploc_name
    UNION ALL SELECT * FROM vac_partial
    UNION ALL SELECT * FROM applicant_match
    UNION ALL SELECT * FROM plant_all
    UNION ALL SELECT * FROM vac_position
  ),

  -- Deduplicate: keep the highest-priority match per record
  deduped AS (
    SELECT DISTINCT ON (result_type, record_id)
      result_type, record_id, primary_label, secondary_label,
      status, matched_field, group_name, account_name,
      created_at, navigation_target, navigation_id, priority
    FROM combined
    ORDER BY result_type, record_id, priority ASC
  )

  SELECT
    d.result_type,
    d.record_id,
    d.primary_label,
    d.secondary_label,
    d.status,
    d.matched_field,
    d.group_name,
    d.account_name,
    d.created_at,
    d.navigation_target,
    d.navigation_id
  FROM deduped d
  ORDER BY d.priority ASC, d.created_at DESC NULLS LAST
  LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.simulate_account_group_transfer(p_account_id uuid, p_to_group_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_role_level      integer;
  v_current_group_id       uuid;
  v_current_group_name     text;
  v_current_group_code     text;
  v_to_group_name          text;
  v_to_group_code          text;
  
  v_stores_count           integer;
  v_plantilla_count        integer;
  v_vacancies_count        integer;
  v_hr_emploc_count        integer;
  
  v_losing_count           integer;
  v_gaining_count          integer;
  
  v_conflicts              jsonb := '[]'::jsonb;
  v_cg_warnings            jsonb := '[]'::jsonb;
  v_deployment_warnings    jsonb := '[]'::jsonb;
  v_warnings               jsonb := '[]'::jsonb;
  v_warning_count          integer := 0;
BEGIN
  -- Verify caller role
  v_caller_role_level := COALESCE(public.get_my_role_level(), 0);
  IF v_caller_role_level < 90 AND NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin role required' USING ERRCODE = '42501';
  END IF;

  -- Get current group info
  SELECT a.group_id, g.group_name, g.group_code
    INTO v_current_group_id, v_current_group_name, v_current_group_code
  FROM public.accounts a
  JOIN public.groups g ON g.id = a.group_id
  WHERE a.id = p_account_id;

  IF v_current_group_id IS NULL THEN
    RAISE EXCEPTION 'account not found' USING ERRCODE = 'P0002';
  END IF;

  -- Get destination group info
  SELECT g.group_name, g.group_code
    INTO v_to_group_name, v_to_group_code
  FROM public.groups g
  WHERE g.id = p_to_group_id;

  IF v_to_group_name IS NULL THEN
    RAISE EXCEPTION 'destination group not found' USING ERRCODE = 'P0002';
  END IF;

  -- Same group validation - warning only
  IF v_current_group_id = p_to_group_id THEN
    v_warnings := jsonb_build_array('Account is already owned by the destination group.');
  END IF;

  -- 1. Affected stores count
  SELECT COUNT(*) INTO v_stores_count
  FROM public.stores
  WHERE account_id = p_account_id
    AND is_active = true
    AND lower(COALESCE(status, 'active')) <> 'archived';

  -- 2. Affected plantilla count (active employees only)
  SELECT COUNT(*) INTO v_plantilla_count
  FROM public.plantilla
  WHERE account_id = p_account_id
    AND status = 'Active';

  -- 3. Affected vacancies count (open only)
  SELECT COUNT(*) INTO v_vacancies_count
  FROM public.vacancies
  WHERE account_id = p_account_id
    AND status = 'Open'
    AND archived_at IS NULL
    AND deleted_at IS NULL;

  -- 4. Affected HR Emploc count (active/pending only)
  SELECT COUNT(*) INTO v_hr_emploc_count
  FROM public.hr_emploc
  WHERE account_id = p_account_id
    AND deleted_at IS NULL;

  -- 5. Calculate visibility impact (group-scoped users losing/gaining access)
  -- Users with group-level scopes who will lose visibility of this account
  SELECT COUNT(DISTINCT us.user_id) INTO v_losing_count
  FROM public.user_scopes us
  JOIN public.users_profile up ON up.id = us.user_id
  JOIN public.roles r ON r.id = up.role_id
  WHERE us.group_id = v_current_group_id
    AND us.account_id IS NULL
    AND r.role_level < 90;

  -- Users with group-level scopes who will gain visibility of this account
  SELECT COUNT(DISTINCT us.user_id) INTO v_gaining_count
  FROM public.user_scopes us
  JOIN public.users_profile up ON up.id = us.user_id
  JOIN public.roles r ON r.id = up.role_id
  WHERE us.group_id = p_to_group_id
    AND us.account_id IS NULL
    AND r.role_level < 90;

  -- 6. Detect coverage group warnings (Coverage groups containing stores that will move ownership groups after transfer)
  SELECT COALESCE(
    jsonb_agg(
      'Coverage Group ' || cg.coverage_code || ' contains stores that will move ownership groups after transfer.'
    ),
    '[]'::jsonb
  ) INTO v_cg_warnings
  FROM (
    SELECT DISTINCT cg.coverage_code
    FROM public.coverage_group_stores cgs
    JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
    JOIN public.stores s ON s.id = cgs.store_id
    WHERE s.account_id = p_account_id
      AND cgs.archived_at IS NULL
      AND cg.archived_at IS NULL
    ORDER BY cg.coverage_code
  ) cg;

  -- 7. Detect active reliever/commando deployments warnings (from other groups)
  SELECT COALESCE(
    jsonb_agg(
      'Active reliever/commando deployment: ' || p.employee_name || ' deployed at ' || s.store_name || ' (Home Group: ' || g_home.group_name || ').'
    ),
    '[]'::jsonb
  ) INTO v_deployment_warnings
  FROM public.workforce_assignments wa
  JOIN public.plantilla p ON p.id = wa.employee_id
  JOIN public.accounts a_home ON a_home.id = p.account_id
  JOIN public.groups g_home ON g_home.id = a_home.group_id
  JOIN public.stores s ON s.id = wa.assigned_store_id
  WHERE s.account_id = p_account_id
    AND wa.status IN ('Active', 'Approved')
    AND g_home.id <> p_to_group_id;

  -- Format conflicts details if needed by UI
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'employee_name', p.employee_name,
        'store_name', s.store_name,
        'home_group_name', g_home.group_name,
        'conflict_type', 'cross-group deployment'
      )
    ),
    '[]'::jsonb
  ) INTO v_conflicts
  FROM public.workforce_assignments wa
  JOIN public.plantilla p ON p.id = wa.employee_id
  JOIN public.accounts a_home ON a_home.id = p.account_id
  JOIN public.groups g_home ON g_home.id = a_home.group_id
  JOIN public.stores s ON s.id = wa.assigned_store_id
  WHERE s.account_id = p_account_id
    AND wa.status IN ('Active', 'Approved')
    AND g_home.id <> p_to_group_id;

  -- Combine all warnings
  v_warnings := v_warnings || v_cg_warnings || v_deployment_warnings;
  v_warning_count := jsonb_array_length(v_warnings);

  RETURN jsonb_build_object(
    'current_group_id', v_current_group_id,
    'current_group_name', v_current_group_name,
    'current_group_code', v_current_group_code,
    'destination_group_id', p_to_group_id,
    'destination_group_name', v_to_group_name,
    'destination_group_code', v_to_group_code,
    'affected_stores', v_stores_count,
    'affected_plantilla_count', v_plantilla_count,
    'affected_vacancies_count', v_vacancies_count,
    'affected_hr_emploc_count', v_hr_emploc_count,
    'coverage_group_conflicts', v_conflicts,
    'users_gaining_visibility', COALESCE(v_gaining_count, 0),
    'users_losing_visibility', COALESCE(v_losing_count, 0),
    'has_coverage_conflict', false, -- Warning only, never blocks
    'blocking_reason', null,
    'warnings', v_warnings,
    'warning_count', v_warning_count
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_correction(p_id uuid, p_ops_remark text)
 RETURNS hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old public.hr_emploc;
  v_new public.hr_emploc;
begin
  if not (i_am_ops() or i_have_full_access()) then
    raise exception 'forbidden: Ops role required' using errcode = '42501';
  end if;

  if coalesce(btrim(p_ops_remark),'') = '' then
    raise exception 'ops remark is required' using errcode = '22023';
  end if;

  select * into v_old
  from hr_emploc
  where id = p_id
  for update;

  if not found or v_old.deleted_at is not null then
    raise exception 'hr_emploc % not found or archived', p_id using errcode = 'P0002';
  end if;

  if v_old.hr_status <> 'For Correction' then
    raise exception 'cannot submit correction: hr_status is %', v_old.hr_status using errcode = '22023';
  end if;

  update hr_emploc
     set hr_status   = 'Pending',
         status      = 'Pending Emploc',
         ops_remarks = p_ops_remark,
         last_correction_submitter_user_id = get_my_profile_id(),
         updated_at  = now(),
         updated_by  = get_my_profile_id()
   where id = p_id
   returning * into v_new;

  perform log_audit_event('hr_emploc','UPDATE', p_id, to_jsonb(v_old), to_jsonb(v_new));
  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.submit_headcount_request(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role                  text := public.get_my_role();
  v_account               accounts%ROWTYPE;
  v_store                 stores%ROWTYPE;
  v_position              positions%ROWTYPE;
  v_group                 groups%ROWTYPE;
  v_coverage_group        coverage_groups%ROWTYPE;
  v_request_id            uuid;
  v_account_id            uuid;
  v_store_id              uuid;
  v_position_id           uuid;
  v_coverage_group_id     uuid;
  v_store_name            text;
  v_workforce_type        text;
  v_headcount_needed      integer;
  -- store-array path
  v_store_ids             uuid[];
  v_store_ids_raw         jsonb;
  v_store_count           integer;
  v_island_groups         text[];
  v_island_group          text;
  v_store_rec             stores%ROWTYPE;
  v_sort_order            integer;
  v_source_nsr_id         uuid;
BEGIN
  IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  v_workforce_type := lower(nullif(trim(coalesce(
    p_input->>'workforce_type',
    p_input->>'employment_type',
    'stationary'
  )), ''));

  IF v_workforce_type NOT IN ('stationary', 'roving', 'floating') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_workforce_type');
  END IF;

  IF v_workforce_type = 'floating' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'floating_workforce_not_enabled',
      'message', 'Floating workforce is reserved for a future phase.'
    );
  END IF;

  BEGIN
    v_account_id  := (p_input->>'account_id')::uuid;
    v_store_id    := nullif(trim(coalesce(p_input->>'store_id', '')), '')::uuid;
    v_position_id := (p_input->>'position_id')::uuid;
    v_coverage_group_id := nullif(trim(coalesce(p_input->>'coverage_group_id', '')), '')::uuid;
    v_headcount_needed := coalesce((p_input->>'headcount_needed')::int, 1);
    v_source_nsr_id := nullif(trim(coalesce(p_input->>'source_new_store_request_id', '')), '')::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'uuid_cast',
        'detail', sqlerrm
      );
  END;

  -- ── HC Request idempotency guard (ohm#c3f9a8z1) ─────────────────────────
  -- Defense-in-depth: UI already disables the CTA, but the backend must not
  -- rely solely on the client. Pending always blocks; approved is a
  -- permanent lock; rejected allows retry.
  IF v_source_nsr_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.headcount_requests
      WHERE source_new_store_request_id = v_source_nsr_id
        AND status IN ('pending', 'under_review')
    ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'hc_request_already_pending',
        'message', 'A headcount request for this store is already pending.'
      );
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.headcount_requests
      WHERE source_new_store_request_id = v_source_nsr_id
        AND status IN ('approved_pending_vcode', 'completed')
    ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'hc_request_already_approved',
        'message', 'This store already has an approved headcount request.'
      );
    END IF;
  END IF;

  -- Parse store_ids jsonb array (for new roving store-array path)
  v_store_ids_raw := p_input->'store_ids';
  IF v_store_ids_raw IS NOT NULL AND jsonb_typeof(v_store_ids_raw) = 'array' THEN
    SELECT ARRAY(
      SELECT (elem #>> '{}')::uuid
      FROM jsonb_array_elements(v_store_ids_raw) AS elem
      WHERE elem #>> '{}' IS NOT NULL AND trim(elem #>> '{}') <> ''
    ) INTO v_store_ids;
  END IF;

  IF v_headcount_needed < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  END IF;

  SELECT * INTO v_position FROM public.positions WHERE id = v_position_id;
  IF v_position.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_account.account_name = ANY(public.get_my_allowed_accounts())) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'out_of_scope');
  END IF;

  IF v_workforce_type = 'stationary' THEN
    -- ── Stationary path: unchanged ─────────────────────────────────────────
    IF v_store_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'store_required_for_stationary');
    END IF;

    SELECT * INTO v_store
    FROM public.stores
    WHERE id = v_store_id
      AND account_id = v_account_id
      AND coalesce(is_active, true) = true;

    IF v_store.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_id');
    END IF;

    v_store_name := nullif(trim(v_store.store_name), '');
    IF v_store_name IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'store_name_required');
    END IF;

  ELSIF v_workforce_type = 'roving' THEN
    -- ── Roving: detect new store-array path vs old coverage_group_id path ──
    v_store_count := coalesce(array_length(v_store_ids, 1), 0);

    IF v_store_count > 0 THEN
      -- ── NEW path: store-array → will create N VCodes + 1 CGCode on approval ─
      IF v_store_count < 2 THEN
        RETURN jsonb_build_object(
          'ok', false,
          'error', 'roving_requires_minimum_2_stores',
          'message', 'Roving HC Requests require at least 2 stores.'
        );
      END IF;

      IF v_store_count > 20 THEN
        RETURN jsonb_build_object(
          'ok', false,
          'error', 'roving_store_count_limit_exceeded',
          'message', 'Maximum 20 stores per roving HC Request.'
        );
      END IF;

      -- Validate all stores: must belong to account and be active
      v_island_groups := ARRAY[]::text[];
      v_sort_order := 0;

      FOREACH v_store_id IN ARRAY v_store_ids LOOP
        SELECT * INTO v_store_rec
        FROM public.stores
        WHERE id = v_store_id
          AND account_id = v_account_id
          AND coalesce(is_active, true) = true
          AND status = 'active';

        IF v_store_rec.id IS NULL THEN
          RETURN jsonb_build_object(
            'ok', false,
            'error', 'invalid_store',
            'store_id', v_store_id,
            'message', 'One or more selected stores are invalid, inactive, or outside scope.'
          );
        END IF;

        -- Collect island groups for validation
        IF v_store_rec.island_group IS NOT NULL
           AND NOT (v_store_rec.island_group = ANY(v_island_groups)) THEN
          v_island_groups := array_append(v_island_groups, v_store_rec.island_group);
        END IF;
      END LOOP;

      -- ── Island group validation (HARD BLOCK) ────────────────────────────
      IF array_length(v_island_groups, 1) > 1 THEN
        RETURN jsonb_build_object(
          'ok', false,
          'error', 'island_group_span_violation',
          'island_groups', v_island_groups,
          'message',
            'Coverage Group cannot span multiple island groups. '
            'Create separate HC Requests per island group.'
        );
      END IF;

      v_island_group := CASE
        WHEN array_length(v_island_groups, 1) = 1 THEN v_island_groups[1]
        ELSE NULL
      END;

      v_store_id   := NULL;  -- no single store on the request row
      v_store_name := NULL;  -- store name comes from hc_request_stores

    ELSE
      -- ── OLD path: coverage_group_id → add slots to existing CG ────────────
      IF v_coverage_group_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_required_for_roving');
      END IF;

      SELECT * INTO v_coverage_group
      FROM public.coverage_groups
      WHERE id = v_coverage_group_id
        AND account_id = v_account_id
        AND archived_at IS NULL;

      IF v_coverage_group.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'coverage_group_id');
      END IF;

      IF v_coverage_group.position_id <> v_position_id THEN
        RETURN jsonb_build_object('ok', false, 'error', 'coverage_group_position_mismatch');
      END IF;

      v_store_id   := NULL;
      v_store_name := v_coverage_group.coverage_code;
      v_island_group := NULL;
    END IF;
  END IF;

  SELECT * INTO v_group FROM public.groups WHERE id = v_account.group_id;

  INSERT INTO public.headcount_requests (
    account_id, store_id, position_id,
    employment_type, workforce_type, coverage_group_id, coverage_group_code_snapshot,
    area, city_municipality, request_type,
    headcount_needed, vacant_date, target_fill_date,
    urgency, reason,
    status,
    group_id, account_name_snapshot, store_name_snapshot,
    position_name_snapshot, group_name_snapshot,
    requested_by_user_id, requested_by_name, requested_by_role,
    island_group, source_new_store_request_id
  ) VALUES (
    v_account_id, v_store_id, v_position_id,
    coalesce(p_input->>'employment_type', initcap(v_workforce_type)),
    v_workforce_type,
    CASE WHEN v_workforce_type = 'roving' AND v_store_count = 0 THEN v_coverage_group_id ELSE NULL END,
    CASE WHEN v_workforce_type = 'roving' AND v_store_count = 0 THEN v_coverage_group.coverage_code ELSE NULL END,
    coalesce(p_input->>'area_province', p_input->>'area', v_coverage_group.area_name),
    nullif(trim(coalesce(p_input->>'area_city', '')), ''),
    coalesce(p_input->>'request_type', 'Replacement'),
    v_headcount_needed,
    nullif(p_input->>'vacant_date', '')::date,
    nullif(p_input->>'target_fill_date', '')::date,
    coalesce(p_input->>'urgency', 'Medium'),
    p_input->>'reason',
    'pending',
    v_account.group_id, v_account.account_name, v_store_name,
    v_position.position_name, v_group.group_name,
    public.get_current_profile_id(), public.get_my_full_name(), v_role,
    v_island_group, v_source_nsr_id
  ) RETURNING id INTO v_request_id;

  -- Insert hc_request_stores rows for new store-array path
  IF v_store_count > 0 THEN
    v_sort_order := 0;
    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      SELECT * INTO v_store_rec FROM public.stores WHERE id = v_store_id;
      INSERT INTO public.hc_request_stores (
        request_id, store_id,
        store_name_snapshot, province_snapshot, city_snapshot, island_group_snapshot,
        sort_order
      ) VALUES (
        v_request_id, v_store_id,
        v_store_rec.store_name,
        COALESCE(v_store_rec.province, v_store_rec.area_province),
        v_store_rec.area_city,
        v_store_rec.island_group,
        v_sort_order
      );
      v_sort_order := v_sort_order + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'ok',              true,
    'request_id',      v_request_id,
    'status',          'pending',
    'workforce_type',  v_workforce_type,
    'store_count',     v_store_count,
    'island_group',    v_island_group
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.submit_hr_emploc_import(p_file_name text, p_group_id uuid, p_rows jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id        UUID;
  v_profile_id       UUID;
  v_batch_id         UUID;
  v_group_name       TEXT;
  v_row              JSONB;
  v_row_number       INTEGER := 0;
  v_total            INTEGER := 0;
  v_valid            INTEGER := 0;
  v_blocked          INTEGER := 0;
  v_duplicate        INTEGER := 0;
  -- per-row values (STORE and EMPLOYMENT_TYPE removed — derived from slot)
  v_last_name        TEXT;
  v_first_name       TEXT;
  v_middle_name      TEXT;
  v_account_name     TEXT;
  v_vcode            TEXT;
  v_date_hired       DATE;
  v_row_group        TEXT;
  -- slot-first VCode lookup
  v_slot_id          UUID;
  v_slot_status      TEXT;
  v_slot_group_id    UUID;
  v_slot_store_id    UUID;
  v_slot_position    TEXT;
  v_slot_occupant_id UUID;
  v_slot_store_name  TEXT;
  v_actual_group_name TEXT;
  v_occupant_label   TEXT;
  -- account resolution
  v_acct_id          UUID;
  -- validation
  v_errors           JSONB;
  v_status           TEXT;
  v_identity         TEXT;
  -- de-dup tracking
  v_seen_identities  TEXT[]  := ARRAY[]::TEXT[];
  v_seen_vcodes      TEXT[]  := ARRAY[]::TEXT[];
  v_seen_groups      TEXT[]  := ARRAY[]::TEXT[];
  v_multi_group      BOOLEAN := FALSE;
  -- Pass 2: slot reservation
  v_valid_vcodes     TEXT[]  := ARRAY[]::TEXT[];
  v_reserve_vcode    TEXT;
  v_slot_result      JSONB;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions to submit HR Emploc import'
      USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Validate group ─────────────────────────────────────────────────────────
  SELECT group_name INTO v_group_name
  FROM public.groups WHERE id = p_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0001';
  END IF;

  -- ── Pre-pass: detect multiple groups in file ───────────────────────────────
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_row_group := UPPER(TRIM(COALESCE(v_row->>'GROUP', '')));
    IF v_row_group <> '' AND NOT (v_row_group = ANY(v_seen_groups)) THEN
      v_seen_groups := array_append(v_seen_groups, v_row_group);
    END IF;
  END LOOP;
  IF array_length(v_seen_groups, 1) > 1 THEN
    v_multi_group := TRUE;
  END IF;

  -- ── Create batch ──────────────────────────────────────────────────────────
  INSERT INTO public.hr_emploc_import_batches (
    file_name, status, group_id, group_name,
    total_rows, valid_rows, blocked_rows, duplicate_rows,
    uploaded_by, uploaded_at
  ) VALUES (
    p_file_name, 'pending_approval', p_group_id, v_group_name,
    0, 0, 0, 0,
    v_profile_id, now()
  ) RETURNING id INTO v_batch_id;

  -- ── Pass 1: Validate all rows and stage them ──────────────────────────────
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_row_number   := v_row_number + 1;
    v_total        := v_total + 1;
    v_errors       := '[]'::jsonb;
    v_status       := 'valid';

    -- Extract uploaded fields (STORE/POSITION/EMPLOYMENT_TYPE intentionally absent)
    v_row_group    := NULLIF(TRIM(COALESCE(v_row->>'GROUP',       '')), '');
    v_account_name := NULLIF(TRIM(COALESCE(v_row->>'ACCOUNT',     '')), '');
    v_vcode        := NULLIF(TRIM(COALESCE(v_row->>'VCODE',       '')), '');
    v_last_name    := NULLIF(TRIM(COALESCE(v_row->>'LAST_NAME',   '')), '');
    v_first_name   := NULLIF(TRIM(COALESCE(v_row->>'FIRST_NAME',  '')), '');
    -- MIDDLE_NAME: raw trim only (NULLIF deferred — full validation below)
    v_middle_name  := TRIM(COALESCE(v_row->>'MIDDLE_NAME', ''));

    -- Reset slot-derived fields for this row
    v_slot_id          := NULL;
    v_slot_status      := NULL;
    v_slot_group_id    := NULL;
    v_slot_store_id    := NULL;
    v_slot_position    := NULL;
    v_slot_occupant_id := NULL;
    v_slot_store_name  := NULL;
    v_actual_group_name := NULL;
    v_occupant_label   := NULL;

    -- Parse DATE_HIRED
    v_date_hired := NULL;
    BEGIN
      v_date_hired := (v_row->>'DATE_HIRED')::DATE;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'DATE_HIRED', 'msg', 'Invalid date format — use YYYY-MM-DD.'
      ));
      v_status := 'blocked';
    END;

    -- ── Required field checks ──────────────────────────────────────────────
    IF v_row_group IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','GROUP','msg','Group is required.'));
      v_status := 'blocked';
    END IF;
    IF v_account_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','ACCOUNT','msg','Account is required.'));
      v_status := 'blocked';
    END IF;
    IF v_vcode IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','VCODE','msg','VCode is required.'));
      v_status := 'blocked';
    END IF;
    IF v_last_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','LAST_NAME','msg','Last name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_first_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','FIRST_NAME','msg','First name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_date_hired IS NULL AND v_status = 'valid' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','DATE_HIRED','msg','Date hired is required.'));
      v_status := 'blocked';
    END IF;

    -- ── LAST_NAME character check ──────────────────────────────────────────
    -- Regex: any character NOT in [A-Za-z0-9 space apostrophe period Ñ ñ hyphen]
    IF v_last_name IS NOT NULL AND v_last_name ~ '[^A-Za-z0-9 ''.Ññ-]' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'LAST_NAME',
        'msg', 'LAST_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe (''), period (.), and Ñ/ñ are allowed.'
      ));
      v_status := 'blocked';
    END IF;

    -- ── FIRST_NAME character check ─────────────────────────────────────────
    IF v_first_name IS NOT NULL AND v_first_name ~ '[^A-Za-z0-9 ''.Ññ-]' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'FIRST_NAME',
        'msg', 'FIRST_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe (''), period (.), and Ñ/ñ are allowed.'
      ));
      v_status := 'blocked';
    END IF;

    -- ── MIDDLE_NAME validation (5 existing rules + new char check) ────────
    IF LENGTH(v_middle_name) = 0 THEN
      -- Rule 1: Blank
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name is required. Use ''NA'' if the employee has no middle name.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF UPPER(v_middle_name) ~ '^N\s*/\s*A$' THEN
      -- Rule 2: N/A variant (any case/spacing)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Use ''NA'' instead of ''N/A'' for employees without a middle name.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF v_middle_name = ANY(ARRAY['-', '.', '?']) THEN
      -- Rule 3: Single-character placeholder — specific message (before generic char check)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name is invalid. Use a valid middle name or ''NA'' if none exists.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF UPPER(v_middle_name) = 'NA' THEN
      -- Rule 4: Normalize NA to uppercase
      v_middle_name := 'NA';

    ELSIF v_middle_name ~ '[^A-Za-z0-9 ''.Ññ-]' THEN
      -- Rule 5 (new): Invalid character in name (only reached for multi-char non-NA values)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'MIDDLE_NAME contains invalid characters. Only letters, spaces, hyphen (-), apostrophe (''), period (.), and Ñ/ñ are allowed.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    ELSIF LENGTH(v_middle_name) < 2 THEN
      -- Rule 6: Single letter (1 char not caught by placeholder check)
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'MIDDLE_NAME',
        'msg', 'Middle Name must contain at least two characters, or use ''NA'' if none exists.'
      ));
      v_status      := 'blocked';
      v_middle_name := NULL;

    END IF;
    -- v_middle_name is now either NULL (blocked), 'NA', or a valid ≥2-char clean name.

    -- ── Cross-group check ──────────────────────────────────────────────────
    IF v_multi_group THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'GROUP',
        'msg', 'Upload blocked: file contains rows from multiple groups. One group per upload only.'
      ));
      v_status := 'blocked';
    ELSIF v_row_group IS NOT NULL
      AND UPPER(v_row_group) <> UPPER(v_group_name)
    THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'GROUP',
        'msg', format('Group "%s" does not match selected group "%s".', v_row_group, v_group_name)
      ));
      v_status := 'blocked';
    END IF;

    -- ── DB validation (only when basic fields are present) ──────────────────
    IF v_status = 'valid' THEN

      -- ── STEP 1: Plantilla Slot lookup (authoritative per ADR-001 Rule 3) ──
      SELECT
        ps.id,
        ps.slot_status,
        ps.group_id,
        ps.store_id,
        ps.position,
        ps.current_occupant_plantilla_id
      INTO
        v_slot_id,
        v_slot_status,
        v_slot_group_id,
        v_slot_store_id,
        v_slot_position,
        v_slot_occupant_id
      FROM public.plantilla_slots ps
      WHERE ps.legacy_vcode = v_vcode
      LIMIT 1;

      IF NOT FOUND THEN
        -- Diagnostic fallback: check legacy vacancies only for a clearer message.
        IF EXISTS (SELECT 1 FROM public.vacancies WHERE vcode = v_vcode) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" exists in legacy vacancy only. No Plantilla slot found. Repair or create the Plantilla slot first.',
              v_vcode
            )
          ));
        ELSE
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" not found. Create the vacancy slot first via Vacancy Import or HC Request.',
              v_vcode
            )
          ));
        END IF;
        v_status := 'blocked';

      ELSIF v_slot_status = 'archived' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" is archived.', v_vcode)
        ));
        v_status := 'blocked';

      ELSIF v_slot_status IN ('closed', 'hc_reduced') THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" is closed and cannot be imported to HR Emploc.', v_vcode)
        ));
        v_status := 'blocked';

      ELSIF v_slot_status = 'occupied' OR v_slot_occupant_id IS NOT NULL THEN
        IF v_slot_occupant_id IS NOT NULL THEN
          SELECT
            COALESCE(
              NULLIF(TRIM(p.employee_no), ''),
              NULLIF(TRIM(p.employee_name), ''),
              'an active employee'
            )
          INTO v_occupant_label
          FROM public.plantilla p
          WHERE p.id = v_slot_occupant_id;
        END IF;
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" is already occupied by %s.',
            v_vcode,
            COALESCE(v_occupant_label, 'an active employee')
          )
        ));
        v_status := 'blocked';

      ELSIF v_slot_status NOT IN ('open', 'pipeline', 'hr_processing') THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" is not in an importable state (current state: %s).',
            v_vcode,
            COALESCE(v_slot_status, 'unknown')
          )
        ));
        v_status := 'blocked';

      ELSE
        -- Slot is open / pipeline / hr_processing — proceed with checks

        -- STEP 7: Group check using slot's group_id (unchanged)
        IF v_slot_group_id IS DISTINCT FROM p_group_id THEN
          SELECT g.group_name INTO v_actual_group_name
          FROM public.groups g WHERE g.id = v_slot_group_id;

          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" belongs to %s, not selected %s.',
              v_vcode,
              COALESCE(v_actual_group_name, v_slot_group_id::TEXT),
              v_group_name
            )
          ));
          v_status := 'blocked';
        END IF;

        -- Derive store_name from slot (STEP 8 removed — no longer user-supplied)
        -- v_slot_position is already captured from the STEP 1 SELECT above.
        IF v_status = 'valid' THEN
          SELECT s.store_name INTO v_slot_store_name
          FROM public.stores s WHERE s.id = v_slot_store_id;
        END IF;

        -- STEP 9 (position cross-check) removed — position is slot-derived, not user input.

      END IF; -- end slot state branch

      -- ── STEP A: Account must belong to the selected group ──────────────────
      IF v_status = 'valid' THEN
        SELECT a.id INTO v_acct_id
        FROM public.accounts a
        WHERE a.group_id = p_group_id
          AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_account_name))
        LIMIT 1;

        IF v_acct_id IS NULL THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'ACCOUNT',
            'msg', format('Account "%s" not found in the selected group.', v_account_name)
          ));
          v_status := 'blocked';
        END IF;
      END IF;

      -- ── STEP B: VCode already active in hr_emploc ──────────────────────────
      IF v_status = 'valid' THEN
        IF EXISTS (
          SELECT 1 FROM public.hr_emploc h
          WHERE h.vcode = v_vcode
            AND h.deleted_at IS NULL
        ) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" already has an active HR Emploc record.', v_vcode)
          ));
          v_status := 'blocked';
        END IF;
      END IF;

      -- ── STEP C: In-file VCode duplicate ────────────────────────────────────
      IF v_status = 'valid' THEN
        IF UPPER(v_vcode) = ANY(v_seen_vcodes) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" appears more than once in this file.', v_vcode)
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        ELSE
          v_seen_vcodes := array_append(v_seen_vcodes, UPPER(v_vcode));
        END IF;
      END IF;

      -- ── STEP D: In-file name duplicate ─────────────────────────────────────
      IF v_status = 'valid' THEN
        v_identity := UPPER(COALESCE(v_last_name,''))    || '|'
                   || UPPER(COALESCE(v_first_name,''))   || '|'
                   || UPPER(COALESCE(v_middle_name,''))  || '|'
                   || UPPER(COALESCE(v_account_name,'')) || '|'
                   || COALESCE(v_date_hired::TEXT,'');

        IF v_identity = ANY(v_seen_identities) THEN
          v_errors  := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'identity',
            'msg', 'Duplicate within this file (same name, account, and date hired).'
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        ELSE
          v_seen_identities := array_append(v_seen_identities, v_identity);
        END IF;
      END IF;

      -- ── STEP E: DB name+account+date duplicate ─────────────────────────────
      IF v_status = 'valid' THEN
        IF EXISTS (
          SELECT 1
          FROM public.hr_emploc h
          JOIN public.accounts a ON a.id = h.account_id
          WHERE h.deleted_at IS NULL
            AND a.group_id = p_group_id
            AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_account_name))
            AND h.hired_date = v_date_hired
            AND UPPER(TRIM(h.applicant_name)) = UPPER(TRIM(
              v_first_name || ' ' || COALESCE(v_middle_name, '') || ' ' || v_last_name
            ))
        ) THEN
          v_errors  := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'identity',
            'msg', 'Duplicate: HR Emploc record with this name and date hired already exists.'
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        END IF;
      END IF;

    END IF; -- end DB validation block

    -- Tally and collect valid vcodes for Pass 2 slot reservation
    IF v_status = 'valid' THEN
      v_valid        := v_valid + 1;
      v_valid_vcodes := array_append(v_valid_vcodes, v_vcode);
    ELSE
      v_blocked := v_blocked + 1;
    END IF;

    -- Stage row (store_name and position from slot; employment_type = NULL)
    INSERT INTO public.hr_emploc_import_rows (
      batch_id, row_number,
      group_name, account_name, last_name, first_name, middle_name,
      date_hired, position, store_name, employment_type, vcode,
      validation_status, validation_errors
    ) VALUES (
      v_batch_id, v_row_number,
      v_row_group, v_account_name, v_last_name, v_first_name, v_middle_name,
      v_date_hired, v_slot_position, v_slot_store_name, NULL, v_vcode,
      v_status, v_errors
    );
  END LOOP;

  -- ── Pass 2: Reserve Plantilla Slots for all valid rows ────────────────────
  FOREACH v_reserve_vcode IN ARRAY v_valid_vcodes
  LOOP
    v_slot_id     := NULL;
    v_slot_result := NULL;

    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE legacy_vcode = v_reserve_vcode
    FOR UPDATE;

    IF v_slot_id IS NULL THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" Plantilla slot not found at reservation time. '
            'The slot may have been archived between validation and submission. Please resubmit.',
            v_reserve_vcode
          )
        ))
      WHERE batch_id = v_batch_id
        AND vcode    = v_reserve_vcode
        AND validation_status = 'valid';

      v_valid   := v_valid   - 1;
      v_blocked := v_blocked + 1;
      CONTINUE;
    END IF;

    SELECT public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_performed_by => v_profile_id,
      p_remarks      => 'import_batch:' || v_batch_id::TEXT
    ) INTO v_slot_result;

    IF (v_slot_result->>'status') = 'blocked' THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" slot could not be reserved — slot state changed between '
            'validation and submission (%s). Please resubmit.',
            v_reserve_vcode,
            COALESCE(v_slot_result->>'blocked_reason', 'state transition blocked')
          )
        ))
      WHERE batch_id = v_batch_id
        AND vcode    = v_reserve_vcode
        AND validation_status = 'valid';

      v_valid   := v_valid   - 1;
      v_blocked := v_blocked + 1;
    END IF;
  END LOOP;

  -- Update batch summary counts
  UPDATE public.hr_emploc_import_batches SET
    total_rows     = v_total,
    valid_rows     = v_valid,
    blocked_rows   = v_blocked,
    duplicate_rows = v_duplicate
  WHERE id = v_batch_id;

  RETURN json_build_object('batch_id', v_batch_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_new_store_request(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_name         text;
  v_caller_role         text;
  -- input fields
  v_store_name          text;
  v_province            text;
  v_city                text;
  v_account_id          uuid;
  v_account_name        text;
  v_group_id            uuid;
  v_position            text;
  v_requested_hc        integer;
  v_reason              text;
  -- outcome
  v_new_req_id          uuid;
  v_notif_rec           RECORD;
  v_notifications_sent  int := 0;
BEGIN
  -- ── Auth guard ────────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- Ops roles (hrco/atl/tl/om, level 40-70) OR HA/SA (full access).
  -- Recruitment, Encoder, Viewer are implicitly blocked because neither
  -- i_am_ops() nor i_have_full_access() returns true for them.
  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Ops or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Parse input ───────────────────────────────────────────────
  v_store_name   := TRIM(p_input ->> 'store_name');
  v_province     := TRIM(p_input ->> 'province');
  v_city         := TRIM(p_input ->> 'city');
  v_account_id   := (p_input ->> 'account_id')::uuid;
  v_account_name := TRIM(p_input ->> 'account_name');
  v_reason       := TRIM(p_input ->> 'reason');
  v_position     := NULLIF(TRIM(COALESCE(p_input ->> 'position', '')), '');
  v_requested_hc := NULLIF(p_input ->> 'requested_hc', '')::integer;
  v_group_id     := NULLIF(p_input ->> 'group_id', '')::uuid;

  -- Required field validation
  IF v_store_name  IS NULL OR v_store_name  = '' THEN
    RAISE EXCEPTION 'store_name is required'   USING ERRCODE = '22023';
  END IF;
  IF v_province    IS NULL OR v_province    = '' THEN
    RAISE EXCEPTION 'province is required'     USING ERRCODE = '22023';
  END IF;
  IF v_city        IS NULL OR v_city        = '' THEN
    RAISE EXCEPTION 'city is required'         USING ERRCODE = '22023';
  END IF;
  IF v_account_id  IS NULL THEN
    RAISE EXCEPTION 'account_id is required'   USING ERRCODE = '22023';
  END IF;
  IF v_account_name IS NULL OR v_account_name = '' THEN
    RAISE EXCEPTION 'account_name is required' USING ERRCODE = '22023';
  END IF;
  IF v_reason      IS NULL OR v_reason      = '' THEN
    RAISE EXCEPTION 'reason is required'       USING ERRCODE = '22023';
  END IF;

  -- ── Resolve caller display name and role ──────────────────────
  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'ops')
  INTO v_caller_name, v_caller_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_caller_id;

  -- ── Layer A: exact active store exists ────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.stores
    WHERE account_id = v_account_id
      AND LOWER(TRIM(store_name)) = LOWER(v_store_name)
      AND LOWER(TRIM(area_city))  = LOWER(v_city)
      AND LOWER(TRIM(province))   = LOWER(v_province)
      AND is_active = true AND status = 'active'
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'An active store with this name already exists in the selected account and location.'
      USING ERRCODE = 'P0001', HINT = 'STORE_ALREADY_EXISTS';
  END IF;

  -- ── Layer B: exact pending request exists ─────────────────────
  IF EXISTS (
    SELECT 1 FROM public.new_store_requests
    WHERE account_id = v_account_id
      AND LOWER(TRIM(store_name)) = LOWER(v_store_name)
      AND LOWER(TRIM(city))       = LOWER(v_city)
      AND LOWER(TRIM(province))   = LOWER(v_province)
      AND status = 'pending' AND is_archived = false
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'A pending request for this store already exists.'
      USING ERRCODE = 'P0001', HINT = 'DUPLICATE_PENDING_REQUEST';
  END IF;

  -- ── Insert request ────────────────────────────────────────────
  INSERT INTO public.new_store_requests (
    store_name,
    province,
    city,
    account_id,
    account_name,
    group_id,
    position,
    requested_hc,
    reason,
    requested_by,
    requested_by_name
  ) VALUES (
    v_store_name,
    v_province,
    v_city,
    v_account_id,
    v_account_name,
    v_group_id,
    v_position,
    v_requested_hc,
    v_reason,
    v_caller_id,
    v_caller_name
  )
  RETURNING id INTO v_new_req_id;

  -- ── Notify all HA/SA ──────────────────────────────────────────
  FOR v_notif_rec IN
    SELECT DISTINCT ON (up.auth_user_id)
      up.auth_user_id,
      ro.role_name
    FROM public.users_profile up
    JOIN public.roles ro         ON ro.id = up.role_id
    JOIN auth.users au           ON au.id = up.auth_user_id  -- skip stale/deleted auth users
    WHERE up.is_active = true
      AND up.auth_user_id IS NOT NULL
      AND ro.role_name IN ('Super Admin', 'Head Admin')
    ORDER BY up.auth_user_id
  LOOP
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_notif_rec.role_name,
        v_notif_rec.auth_user_id,
        'new_store_request',
        'NEW_STORE_REQUEST_SUBMITTED',
        'New Store Request',
        v_caller_name || ' requested to add ' || v_store_name ||
          ' (' || v_city || ', ' || v_province || ') under ' || v_account_name || '.',
        '/new_store_request/' || v_new_req_id::text,
        'new_store_request',
        v_new_req_id::text
      );
      v_notifications_sent := v_notifications_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'submit_new_store_request: skipped recipient %, role %, request_id %, error: %',
        v_notif_rec.auth_user_id, v_notif_rec.role_name, v_new_req_id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'request_id',          v_new_req_id,
    'status',              'pending',
    'notifications_sent',  v_notifications_sent
  );

EXCEPTION
  WHEN unique_violation THEN
    -- Race condition: the partial unique index blocked the insert
    RAISE EXCEPTION 'A pending request for this store already exists (race condition).'
      USING ERRCODE = 'P0001', HINT = 'DUPLICATE_PENDING_REQUEST';
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_plantilla_baseline_import(p_file_name text, p_group_id uuid, p_account_id uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300000'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_role       text := public.get_my_role();
  v_batch_id   uuid;
  v_acct_group uuid;
  v_acct_name  text;

  v_row        jsonb;
  v_idx        int := 0;

  -- Required CSV fields
  v_vcode      text;
  v_store_nm   text;
  v_prov       text;
  v_city       text;
  v_position   text;
  v_emp_type   text;
  v_req_hc     text;
  v_pen_raw    text;
  v_emp        text;
  v_last       text;
  v_first      text;
  v_middle     text;

  -- Optional enrichment fields
  v_civil_status    text;
  v_rate_raw        text;
  v_birthdate_raw   text;
  v_contact_raw     text;
  v_address_raw     text;
  v_schedule_raw    text;
  v_dayoff_raw      text;
  v_coordinator_raw text;

  -- Resolved references
  v_store_id   uuid;
  v_store_acct uuid;
  v_store_grp  uuid;

  -- Per-row state
  v_errs            jsonb;
  v_flags           jsonb;
  v_status          text;
  v_is_roving       boolean;
  v_store_cnt       int;
  v_is_new_store    boolean;
  v_is_existing_emp boolean;
  v_existing_pid    uuid;

  -- Employee conflict classification
  v_emp_conflict_type  text;   -- 'active_employee' | 'archived_employee' | 'rollback_safe_employee' | 'inactive_or_archived_existing_record' | NULL
  v_active_emp_name    text;

  -- Batch counters
  v_total      int := 0;
  v_valid      int := 0;
  v_flagged    int := 0;
  v_skipped    int := 0;
  v_blocked    int := 0;
  v_roving     int := 0;
  v_new_stores int := 0;
  v_ex_stores  int := 0;
  v_ex_emps    int := 0;
  v_xacct      int := 0;
  v_xgroup     int := 0;
  v_over20     int := 0;
  v_missing    int := 0;

  v_summary    jsonb;
  v_final      text;
BEGIN
  -- â”€â”€ Auth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- â”€â”€ Governance gate â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  PERFORM public.fn_assert_governance_enabled('import_plantilla');

  -- â”€â”€ Audit Freeze Gate (Phase 2A) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  PERFORM public.fn_assert_freeze_inactive('audit_freeze');

  -- â”€â”€ Input validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  IF p_file_name IS NULL OR length(trim(p_file_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: file_name required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows must be a jsonb array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows is empty' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN
    RAISE EXCEPTION 'INVALID_INPUT: max 5000 rows per batch' USING ERRCODE = '22023';
  END IF;

  -- â”€â”€ Scope validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'INVALID_GROUP: %', p_group_id USING ERRCODE = '23503';
  END IF;
  SELECT group_id, account_name INTO v_acct_group, v_acct_name
    FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: %', p_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %',
      p_account_id, p_group_id USING ERRCODE = '23503';
  END IF;
  IF NOT public.i_have_full_access()
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  -- â”€â”€ Create batch â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  INSERT INTO public.plantilla_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- â”€â”€ Pre-passes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  -- [A] Duplicate VCODEs within this upload (all occurrences will be blocked)
  DROP TABLE IF EXISTS _pib_dup_vcodes;
  CREATE TEMP TABLE _pib_dup_vcodes ON COMMIT DROP AS
  SELECT upper(trim(elem->>'VCODE')) AS vcode
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1 HAVING count(*) > 1;

  -- [B] Employee â†’ store coverage (roving detection)
  DROP TABLE IF EXISTS _pib_emp_cov;
  CREATE TEMP TABLE _pib_emp_cov ON COMMIT DROP AS
  SELECT
    upper(trim(elem->>'EMPLOYEE_NO')) AS emp,
    count(DISTINCT upper(trim(elem->>'VCODE'))) AS store_count
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'EMPLOYEE_NO'),'') IS NOT NULL
    AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1;

  -- [C] Already-seen (employee_no, vcode) pairs for exact-duplicate skip detection
  DROP TABLE IF EXISTS _pib_seen_pairs;
  CREATE TEMP TABLE _pib_seen_pairs (emp text, vcode text) ON COMMIT DROP;

  -- [D] VCODEs actively assigned in the live system: vcode â†’ employee_no
  DROP TABLE IF EXISTS _pib_active_vcode_owners;
  CREATE TEMP TABLE _pib_active_vcode_owners ON COMMIT DROP AS
  SELECT upper(trim(a.vcode)) AS vcode,
         upper(trim(a.employee_no)) AS employee_no
    FROM public.employee_store_allocations a
   WHERE a.is_active
     AND a.vcode IS NOT NULL
     AND a.employee_no IS NOT NULL;

  -- [E] OHM2026_0079: Rollback-safe VCodes
  --     Vacancies soft-deleted via a completed vacancy import rollback.
  --     These VCODEs may be re-used in a new plantilla import.
  DROP TABLE IF EXISTS _pib_rollback_safe_vcodes;
  CREATE TEMP TABLE _pib_rollback_safe_vcodes ON COMMIT DROP AS
  SELECT upper(trim(vv.vcode)) AS vcode
    FROM public.vacancies vv
    JOIN public.vacancy_import_batches vib ON vib.id = vv.source_vacancy_import_batch_id
   WHERE vv.vcode IS NOT NULL
     AND vv.deleted_at IS NOT NULL
     AND vib.rollback_status = 'completed';

  -- [F] OHM2026_0079: Blocked (archived/non-reusable) VCodes
  --     Vacancies that are archived or soft-deleted without a completed rollback.
  DROP TABLE IF EXISTS _pib_blocked_vcodes;
  CREATE TEMP TABLE _pib_blocked_vcodes ON COMMIT DROP AS
  SELECT upper(trim(vv.vcode)) AS vcode
    FROM public.vacancies vv
   WHERE vv.vcode IS NOT NULL
     AND (
       COALESCE(vv.is_archived, false) = true
       OR vv.status = 'Archived'
       OR (
         vv.deleted_at IS NOT NULL
         AND NOT (
           vv.source_vacancy_import_batch_id IS NOT NULL
           AND EXISTS (
             SELECT 1 FROM public.vacancy_import_batches vib2
              WHERE vib2.id = vv.source_vacancy_import_batch_id
                AND vib2.rollback_status = 'completed'
           )
         )
       )
     );

  -- â”€â”€ Row loop â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx      := v_idx + 1;
    v_total    := v_total + 1;
    v_errs     := '[]'::jsonb;
    v_flags    := '[]'::jsonb;
    v_is_roving     := false;
    v_store_cnt     := 0;
    v_is_new_store  := false;
    v_is_existing_emp := false;
    v_store_id := NULL; v_store_acct := NULL; v_store_grp := NULL;
    v_existing_pid := NULL;
    v_emp_conflict_type := NULL;

    -- Parse required CSV fields
    v_vcode    := upper(NULLIF(trim(COALESCE(v_row->>'VCODE','')), ''));
    v_store_nm := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')), '');
    v_prov     := NULLIF(trim(COALESCE(v_row->>'AREA_PROVINCE','')), '');
    v_city     := NULLIF(trim(COALESCE(v_row->>'AREA_CITY','')), '');
    v_position := NULLIF(trim(COALESCE(v_row->>'POSITION','')), '');
    v_emp_type := NULLIF(trim(COALESCE(v_row->>'EMPLOYMENT_TYPE','')), '');
    v_req_hc   := NULLIF(trim(COALESCE(v_row->>'REQUIRED_HC','')), '');
    v_pen_raw  := NULLIF(trim(COALESCE(v_row->>'WITH_PENALTY','')), '');
    v_emp      := upper(NULLIF(trim(COALESCE(v_row->>'EMPLOYEE_NO','')), ''));
    v_last     := NULLIF(trim(COALESCE(v_row->>'LAST_NAME','')), '');
    v_first    := NULLIF(trim(COALESCE(v_row->>'FIRST_NAME','')), '');
    v_middle   := NULLIF(trim(COALESCE(v_row->>'MIDDLE_NAME','')), '');

    -- Parse optional enrichment fields (safe: null if blank or absent)
    v_civil_status    := nullif(trim(coalesce(v_row->>'CIVIL_STATUS', '')), '');
    v_rate_raw        := nullif(trim(coalesce(v_row->>'RATE', '')), '');
    v_birthdate_raw   := nullif(trim(coalesce(v_row->>'BIRTHDATE', '')), '');
    v_contact_raw     := nullif(trim(coalesce(v_row->>'CONTACT', '')), '');
    v_address_raw     := nullif(trim(coalesce(v_row->>'ADDRESS', '')), '');
    v_schedule_raw    := nullif(trim(coalesce(v_row->>'SCHEDULE', '')), '');
    v_dayoff_raw      := nullif(trim(coalesce(v_row->>'DAYOFF', '')), '');
    v_coordinator_raw := nullif(trim(coalesce(v_row->>'COORDINATOR', '')), '');

    -- â”€â”€ Blocking: required fields â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_vcode    IS NULL THEN v_errs := v_errs || '[{"field":"VCODE","msg":"required"}]'::jsonb; END IF;
    IF v_store_nm IS NULL THEN v_errs := v_errs || '[{"field":"STORE_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_prov     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_PROVINCE","msg":"required"}]'::jsonb; END IF;
    IF v_city     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_CITY","msg":"required"}]'::jsonb; END IF;
    IF v_emp      IS NULL THEN v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"required"}]'::jsonb; END IF;
    IF v_last     IS NULL THEN v_errs := v_errs || '[{"field":"LAST_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_first    IS NULL THEN v_errs := v_errs || '[{"field":"FIRST_NAME","msg":"required"}]'::jsonb; END IF;

    IF v_vcode IS NOT NULL AND v_store_nm IS NOT NULL AND v_emp IS NULL THEN
      v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"store row has no employee â€” every VCODE must have an assigned employee"}]'::jsonb;
    END IF;

    IF v_vcode IS NOT NULL AND EXISTS (SELECT 1 FROM _pib_dup_vcodes WHERE vcode = v_vcode) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"duplicate VCODE in upload â€” each VCODE must appear exactly once"}]'::jsonb;
    END IF;

    IF v_vcode IS NOT NULL AND v_emp IS NOT NULL AND EXISTS (
      SELECT 1 FROM _pib_active_vcode_owners
      WHERE vcode = v_vcode AND employee_no <> v_emp
    ) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE already actively assigned to a different employee"}]'::jsonb;
    END IF;

    -- â”€â”€ OHM2026_0079: VCode archived/non-reusable conflict blocking â”€â”€â”€â”€â”€â”€â”€
    IF v_vcode IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM _pib_active_vcode_owners
                        WHERE vcode = v_vcode AND employee_no <> v_emp)
    THEN
      IF EXISTS (SELECT 1 FROM _pib_rollback_safe_vcodes WHERE vcode = v_vcode) THEN
        v_flags := v_flags || jsonb_build_array(jsonb_build_object(
          'flag',         'rollback_safe_vcode',
          'conflict_type','rollback_safe_vcode',
          'msg',          'Rollback record detected â€” eligible for re-upload.'
        ));
      ELSIF EXISTS (SELECT 1 FROM _pib_blocked_vcodes WHERE vcode = v_vcode) THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field',         'VCODE',
          'conflict_type', 'archived_vcode',
          'msg',           'Archived VCode cannot be reused.'
        ));
      END IF;
    END IF;
    -- â”€â”€ End OHM2026_0079 VCode conflict blocking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    IF v_req_hc IS NULL THEN
      v_flags := v_flags || '[{"flag":"missing_required_hc","msg":"REQUIRED_HC not provided"}]'::jsonb;
    END IF;

    IF v_emp IS NOT NULL AND v_vcode IS NOT NULL
       AND EXISTS (SELECT 1 FROM _pib_seen_pairs WHERE emp = v_emp AND vcode = v_vcode)
    THEN
      v_status := 'skipped';
      v_flags  := v_flags || '[{"flag":"duplicate_emp_vcode","msg":"same employee+VCODE already processed â€” skipped"}]'::jsonb;
    ELSE

      IF v_vcode IS NOT NULL THEN
        SELECT s.id, s.account_id, s.group_id
          INTO v_store_id, v_store_acct, v_store_grp
          FROM public.stores s
         WHERE upper(s.vcode) = v_vcode AND s.status = 'active'
         ORDER BY s.created_at LIMIT 1;
      END IF;
      v_is_new_store := (v_store_id IS NULL);

      IF v_store_id IS NOT NULL AND v_store_grp IS NOT NULL
         AND v_store_grp <> p_group_id THEN
        v_errs   := v_errs   || '[{"field":"VCODE","msg":"cross-group: store VCODE belongs to a different group"}]'::jsonb;
        v_xgroup := v_xgroup + 1;
      END IF;

      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.employee_store_allocations a
        WHERE upper(trim(a.employee_no)) = v_emp AND a.is_active
          AND a.account_id IS NOT NULL AND a.account_id <> p_account_id
      ) THEN
        v_errs  := v_errs  || '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee already deployed in another account"}]'::jsonb;
        v_xacct := v_xacct + 1;
      END IF;

      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.employee_store_allocations a
        WHERE upper(trim(a.employee_no)) = v_emp AND a.is_active
          AND a.group_id IS NOT NULL AND a.group_id <> p_group_id
      ) THEN
        v_errs   := v_errs   || '[{"field":"EMPLOYEE_NO","msg":"cross-group: employee already deployed in another group"}]'::jsonb;
        v_xgroup := v_xgroup + 1;
      END IF;

      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE p.employee_no = v_emp
          AND p.is_deleted = false
          AND p.account_id IS NOT NULL
          AND p.account_id <> p_account_id
          AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
      ) THEN
        v_errs  := v_errs  || '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee exists in plantilla under a different account"}]'::jsonb;
        v_xacct := v_xacct + 1;
      END IF;

      IF v_emp IS NOT NULL THEN
        SELECT store_count INTO v_store_cnt FROM _pib_emp_cov WHERE emp = v_emp;
        v_store_cnt := COALESCE(v_store_cnt, 0);
        IF v_store_cnt > 1 THEN
          v_is_roving := true;
          v_flags := v_flags || jsonb_build_array(
            jsonb_build_object('flag','roving','msg',
              'roving employee: ' || v_store_cnt || ' stores')
          );
        END IF;
        IF v_store_cnt > 20 THEN
          v_flags := v_flags || jsonb_build_array(
            jsonb_build_object('flag','over_20_stores','msg',
              v_store_cnt || ' stores (>20 allowed but flagged)')
          );
          v_over20 := v_over20 + 1;
        END IF;
      END IF;

      -- â”€â”€ Employee conflict classification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      -- Priority order (first match wins):
      --   1. Rollback-safe plantilla row   â†’ ALLOWED (flag: rollback_safe_employee)
      --   2. Active plantilla row          â†’ BLOCKED  (error: active_employee)
      --   3. Archived/deleted non-rollback â†’ BLOCKED  (error: archived_employee)
      --   4. Inactive row (OHM2026_0083)   â†’ BLOCKED  (error: inactive_or_archived_existing_record)
      --      (Previously: FLAG / reconcile path â€” changed by OHM2026_0083)
      --   5. No existing row               â†’ new employee (no flag)
      IF v_emp IS NOT NULL THEN
        v_emp_conflict_type := NULL;
        v_is_existing_emp   := false;

        -- Priority 1: rollback-safe plantilla row
        IF EXISTS (
          SELECT 1 FROM public.plantilla p
           JOIN public.plantilla_import_batches pib
             ON pib.id = p.source_baseline_import_batch_id
          WHERE p.employee_no = v_emp
            AND pib.status = 'rolled_back'
            AND pib.rolled_back_at IS NOT NULL
        ) THEN
          v_emp_conflict_type := 'rollback_safe_employee';
          v_flags := v_flags || jsonb_build_array(jsonb_build_object(
            'flag',         'rollback_safe_employee',
            'conflict_type','rollback_safe_employee',
            'msg',          'Rollback record detected â€” eligible for re-upload.'
          ));

        -- Priority 2: active plantilla row
        ELSIF EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = v_emp
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
        ) THEN
          SELECT NULLIF(
                   CASE
                     WHEN NULLIF(trim(p.last_name), '') IS NULL
                       OR NULLIF(trim(p.first_name), '') IS NULL
                     THEN NULL
                     ELSE trim(
                       initcap(lower(trim(p.last_name))) ||
                       ', ' || initcap(lower(trim(p.first_name))) ||
                       COALESCE(CASE
                         WHEN NULLIF(trim(p.middle_name), '') IS NULL THEN NULL
                         WHEN upper(trim(p.middle_name)) IN ('NA', 'N/A') THEN NULL
                         ELSE ' ' || initcap(lower(trim(p.middle_name)))
                       END, '')
                     )
                   END,
                   ''
                 )
            INTO v_active_emp_name
            FROM public.plantilla p
           WHERE p.employee_no = v_emp
             AND p.is_deleted = false
             AND COALESCE(p.is_archived, false) = false
             AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
           ORDER BY p.updated_at DESC NULLS LAST, p.created_at DESC NULLS LAST
           LIMIT 1;

          v_emp_conflict_type := 'active_employee';
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field',         'EMPLOYEE_NO',
            'conflict_type', 'active_employee',
            'msg',           CASE
                               WHEN v_active_emp_name IS NULL THEN
                                 'Employee already exists in active plantilla.'
                               ELSE
                                 'Employee already exists in active plantilla: ' || v_active_emp_name || '.'
                             END
          ));

        -- Priority 3: archived/soft-deleted plantilla row without rollback linkage
        ELSIF EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = v_emp
            AND (p.is_deleted = true OR COALESCE(p.is_archived, false) = true)
        ) THEN
          v_emp_conflict_type := 'archived_employee';
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field',         'EMPLOYEE_NO',
            'conflict_type', 'archived_employee',
            'msg',           'Employee exists in archived plantilla and cannot be reused.'
          ));

        -- Priority 4 (OHM2026_0083): inactive row â€” BLOCKED
        -- Changed from FLAG (reconcile path) to BLOCK.
        -- Inactive/Rejected Deactivation employees must be manually restored
        -- before re-import. Do not auto-reactivate via import commit.
        ELSIF EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE p.employee_no = v_emp
            AND p.is_deleted = false
            AND COALESCE(p.is_archived, false) = false
            AND p.status IN ('Inactive', 'Rejected Deactivation')
        ) THEN
          v_emp_conflict_type := 'inactive_or_archived_existing_record';
          v_errs := v_errs || jsonb_build_array(jsonb_build_object(
            'field',         'EMPLOYEE_NO',
            'conflict_type', 'inactive_or_archived_existing_record',
            'msg',           'Cannot import because matching employee, emploc, or VCode is inactive/archived. Restore/reactivate first or use a valid active record.'
          ));

        -- Priority 5: no existing plantilla record â€” new employee
        ELSE
          v_emp_conflict_type := NULL;
        END IF;
      END IF;
      -- â”€â”€ End employee conflict classification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

      -- â”€â”€ OHM2026_0079: HR Emploc archived conflict blocking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      -- Only runs when employee is not already fully blocked.
      IF v_emp IS NOT NULL
         AND v_emp_conflict_type IS DISTINCT FROM 'active_employee'
         AND v_emp_conflict_type IS DISTINCT FROM 'archived_employee'
         AND v_emp_conflict_type IS DISTINCT FROM 'inactive_or_archived_existing_record'
      THEN
        IF EXISTS (
          SELECT 1 FROM public.hr_emploc h
          WHERE upper(trim(COALESCE(h.emploc_no, ''))) = v_emp
            AND h.emploc_no IS NOT NULL
            AND h.emploc_no <> ''
            AND h.deleted_at IS NOT NULL
        ) THEN
          IF EXISTS (
            SELECT 1 FROM public.employee_store_allocations a
             JOIN public.plantilla_import_batches pib ON pib.id = a.source_import_batch_id
            WHERE upper(trim(COALESCE(a.employee_no, ''))) = v_emp
              AND pib.status = 'rolled_back'
          ) THEN
            v_flags := v_flags || jsonb_build_array(jsonb_build_object(
              'flag',         'rollback_safe_emploc',
              'conflict_type','rollback_safe_emploc',
              'msg',          'Rollback record detected â€” eligible for re-upload.'
            ));
          ELSE
            v_errs := v_errs || jsonb_build_array(jsonb_build_object(
              'field',         'EMPLOYEE_NO',
              'conflict_type', 'archived_emploc',
              'msg',           'Archived Emploc cannot be reused.'
            ));
          END IF;
        END IF;
      END IF;
      -- â”€â”€ End OHM2026_0079 HR Emploc conflict blocking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

      IF jsonb_array_length(v_errs) > 0 THEN
        v_status := 'blocked';
      ELSIF jsonb_array_length(v_flags) > 0 THEN
        v_status := 'flagged';
      ELSE
        v_status := 'valid';
      END IF;

      IF v_emp IS NOT NULL AND v_vcode IS NOT NULL AND v_status IN ('valid', 'flagged') THEN
        INSERT INTO _pib_seen_pairs(emp, vcode) VALUES (v_emp, v_vcode);
      END IF;

      IF v_vcode IS NOT NULL AND v_status <> 'blocked' THEN
        IF v_is_new_store THEN v_new_stores := v_new_stores + 1;
        ELSE v_ex_stores := v_ex_stores + 1;
        END IF;
      END IF;

    END IF; -- end non-skip branch

    INSERT INTO public.plantilla_import_rows (
      batch_id, row_number, raw_data,
      vcode, store_name, area_province, area_city, position, employment_type,
        required_hc_raw, with_penalty_raw,
      employee_no, last_name, first_name, middle_name,
      civil_status, rate_raw, birthdate_raw, contact_raw,
      address_raw, schedule_raw, dayoff_raw, coordinator_raw,
      resolved_store_id, resolved_account_id, resolved_group_id,
      validation_status, validation_errors, validation_flags,
      is_roving, roving_store_count, is_new_store, is_existing_employee
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_vcode, v_store_nm, v_prov, v_city, v_position, v_emp_type,
        v_req_hc, v_pen_raw,
      v_emp, v_last, v_first, v_middle,
      v_civil_status, v_rate_raw, v_birthdate_raw, v_contact_raw,
      v_address_raw, v_schedule_raw, v_dayoff_raw, v_coordinator_raw,
      v_store_id, v_store_acct, v_store_grp,
      v_status, v_errs, v_flags,
      v_is_roving, v_store_cnt, v_is_new_store, v_is_existing_emp
    );

    CASE v_status
      WHEN 'valid'   THEN v_valid    := v_valid    + 1;
      WHEN 'flagged' THEN v_flagged  := v_flagged  + 1;
      WHEN 'skipped' THEN v_skipped  := v_skipped  + 1;
      WHEN 'blocked' THEN v_blocked  := v_blocked  + 1;
      ELSE NULL;
    END CASE;

  END LOOP;

  -- â”€â”€ Post-loop: HC mismatch sweep â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  UPDATE public.plantilla_import_rows AS r
     SET validation_flags  = r.validation_flags || jsonb_build_array(
           jsonb_build_object(
             'flag', CASE WHEN hc.uploaded_count < hc.total_req
                          THEN 'hc_under_required'
                          ELSE 'hc_over_required'
                     END,
             'msg',  format('%s employee(s) uploaded for "%s / %s" but REQUIRED_HC sums to %s',
                            hc.uploaded_count, hc.store_nm, hc.pos, hc.total_req)
           )
         ),
         validation_status = CASE
           WHEN r.validation_status = 'valid' THEN 'flagged'
           ELSE r.validation_status
         END
    FROM (
      SELECT
        store_name  AS store_nm,
        position    AS pos,
        count(*)    AS uploaded_count,
        sum(
          COALESCE(
            NULLIF(regexp_replace(COALESCE(required_hc_raw,''),'[^0-9]','','g'), '')::int,
            0
          )
        )           AS total_req
      FROM public.plantilla_import_rows
     WHERE batch_id = v_batch_id
       AND validation_status IN ('valid','flagged')
       AND store_name IS NOT NULL
       AND position   IS NOT NULL
     GROUP BY store_name, position
    HAVING count(*) <>
           sum(COALESCE(
             NULLIF(regexp_replace(COALESCE(required_hc_raw,''),'[^0-9]','','g'), '')::int,
             0
           ))
    ) AS hc
   WHERE r.batch_id      = v_batch_id
     AND r.store_name    = hc.store_nm
     AND r.position      = hc.pos
     AND r.validation_status IN ('valid','flagged');

  SELECT count(*) FILTER (WHERE validation_status = 'valid')
    INTO v_valid
    FROM public.plantilla_import_rows WHERE batch_id = v_batch_id;

  SELECT count(*) FILTER (WHERE validation_status = 'flagged')
    INTO v_flagged
    FROM public.plantilla_import_rows WHERE batch_id = v_batch_id;

  -- â”€â”€ Post-loop: roving dedup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SELECT count(*) INTO v_roving
    FROM _pib_emp_cov WHERE store_count > 1;

  -- existing_employees_count: OHM2026_0083 â€” inactive employees are now BLOCKED,
  -- so is_existing_employee is false for those rows.
  -- This counter reflects only non-blocked existing employees (should be 0 for
  -- inactive rows after this migration).
  SELECT count(DISTINCT employee_no) INTO v_ex_emps
    FROM public.plantilla_import_rows r
   WHERE r.batch_id = v_batch_id
     AND r.validation_status IN ('valid','flagged')
     AND r.is_existing_employee;

  -- â”€â”€ Post-loop: missing from upload â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SELECT count(*) INTO v_missing
    FROM public.plantilla p
   WHERE p.account_id = p_account_id
     AND p.is_deleted = false
     AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
     AND NOT EXISTS (
       SELECT 1 FROM public.plantilla_import_rows r
        WHERE r.batch_id = v_batch_id
          AND r.employee_no = p.employee_no
          AND r.validation_status IN ('valid','flagged')
     );

  -- â”€â”€ Aggregate error summary â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SELECT COALESCE(jsonb_object_agg(field_name, cnt), '{}'::jsonb) INTO v_summary
    FROM (
      SELECT (e.value->>'field') AS field_name, count(*) AS cnt
        FROM public.plantilla_import_rows r
        CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
       WHERE r.batch_id = v_batch_id
       GROUP BY 1
    ) s;

  v_final := CASE
    WHEN (v_valid + v_flagged) = 0 THEN 'validation_failed'
    ELSE 'pending_approval'
  END;

  UPDATE public.plantilla_import_batches
     SET total_rows                = v_total,
         valid_rows                = v_valid,
         flagged_rows              = v_flagged,
         skipped_rows              = v_skipped,
         blocked_rows              = v_blocked,
         roving_detected           = v_roving,
         new_stores_count          = v_new_stores,
         existing_stores_count     = v_ex_stores,
         existing_employees_count  = v_ex_emps,
         cross_account_conflicts   = v_xacct,
         cross_group_conflicts     = v_xgroup,
         over_20_store_warnings    = v_over20,
         missing_from_upload_count = v_missing,
         error_summary             = v_summary,
         status                    = v_final,
         updated_at                = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id',                   v_batch_id,
    'status',                     v_final,
    'total_rows',                 v_total,
    'valid_rows',                 v_valid,
    'flagged_rows',               v_flagged,
    'skipped_rows',               v_skipped,
    'blocked_rows',               v_blocked,
    'roving_detected',            v_roving,
    'new_stores_count',           v_new_stores,
    'existing_stores_count',      v_ex_stores,
    'existing_employees_count',   v_ex_emps,
    'cross_account_conflicts',    v_xacct,
    'cross_group_conflicts',      v_xgroup,
    'over_20_store_warnings',     v_over20,
    'missing_from_upload_count',  v_missing,
    'error_summary',              v_summary
  );
END$function$;

CREATE OR REPLACE FUNCTION public.submit_vacancy_for_approval(p_vacancy_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := get_my_profile_id();
  v_role       text := get_my_role();
  v            public.vacancies;
BEGIN
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vacancy not found: %', p_vacancy_id; END IF;

  IF NOT (public.i_have_full_access() OR public.i_have_account_scope(v.account_id)) THEN
    RAISE EXCEPTION 'Vacancy % is outside your scope', p_vacancy_id USING ERRCODE='42501';
  END IF;

  IF v.status <> 'Draft' THEN
    RAISE EXCEPTION 'Only Draft vacancies can be submitted (current: %)', v.status
      USING ERRCODE='check_violation';
  END IF;

  UPDATE public.vacancies
     SET status = 'Pending Approval', updated_by = v_profile_id, updated_at = now()
   WHERE id = p_vacancy_id;

  PERFORM public.log_audit_event(
    'vacancies','UPDATE', p_vacancy_id,
    jsonb_build_object('status', v.status),
    jsonb_build_object('status','Pending Approval','semantic_action','SUBMIT_FOR_APPROVAL','actor_role', v_role)
  );
  RETURN jsonb_build_object('id', p_vacancy_id, 'status', 'Pending Approval');
END;
$function$;

CREATE OR REPLACE FUNCTION public.tag_web_hr_emploc_deficiency(p_hr_emploc_id uuid, p_deficiencies jsonb, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid      uuid    := auth.uid();
  v_profile_id    uuid;
  v_role_name     text;
  v_role_level    integer;
  v_old           public.hr_emploc;
  v_new           public.hr_emploc;
  v_issue         jsonb;
  v_code          text;
  v_comment       text;
  v_needs_comment boolean;
BEGIN

  -- ----------------------------------------------------------------
  -- 1. Auth guard — fail closed, no session = no access
  -- ----------------------------------------------------------------
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: deficiency tagging requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 2. Profile resolution — active, non-archived profile + role
  -- ----------------------------------------------------------------
  SELECT up.id, r.role_name, r.role_level
  INTO   v_profile_id, v_role_name, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active    = TRUE
    AND  up.archived_at  IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR COALESCE(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: caller profile is inactive or not found'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 3. RBAC capability guard
  --    Mirrors mark_for_correction: HR Dept (hrPersonnel) or full access
  --    (headAdmin / superAdmin). All other roles are denied.
  -- ----------------------------------------------------------------
  IF NOT (public.i_am_hr_dept() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: HR Personnel or Admin role required for deficiency tagging'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 4. Validate deficiencies input
  --    Must be a non-empty JSONB array of {code, comment} objects.
  --    Every code must exist and be active in hr_emploc_issue_types.
  --    Codes that require_comment must supply a non-empty comment.
  -- ----------------------------------------------------------------
  IF p_deficiencies IS NULL
     OR jsonb_typeof(p_deficiencies) <> 'array'
     OR jsonb_array_length(p_deficiencies) = 0
  THEN
    RAISE EXCEPTION 'p_deficiencies must be a non-empty JSONB array of {code, comment} objects'
      USING ERRCODE = '22023';
  END IF;

  FOR v_issue IN SELECT * FROM jsonb_array_elements(p_deficiencies) LOOP
    v_code    := NULLIF(BTRIM(COALESCE(v_issue->>'code',    '')), '');
    v_comment :=        BTRIM(COALESCE(v_issue->>'comment', ''));

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'each deficiency entry must include a non-empty code'
        USING ERRCODE = '22023';
    END IF;

    SELECT requires_comment
    INTO   v_needs_comment
    FROM   public.hr_emploc_issue_types
    WHERE  code      = v_code
      AND  is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'unknown or inactive deficiency code: %', v_code
        USING ERRCODE = '22023';
    END IF;

    IF v_needs_comment AND v_comment = '' THEN
      RAISE EXCEPTION 'comment is required for deficiency code: %', v_code
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  -- ----------------------------------------------------------------
  -- 5. Lock and fetch the record
  --    FOR UPDATE prevents concurrent state changes during validation.
  -- ----------------------------------------------------------------
  SELECT * INTO v_old
  FROM   public.hr_emploc
  WHERE  id = p_hr_emploc_id
  FOR    UPDATE;

  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'forbidden: hr_emploc record not found or archived'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 6. Scope gate — non-global callers (role_level < 90) must have
  --    an account/group assignment that covers the record's account.
  --    Mirrors scoping logic from list_web_hr_emplocs and
  --    get_web_hr_emploc_detail for consistency.
  -- ----------------------------------------------------------------
  IF COALESCE(v_role_level, 0) < 90 THEN
    IF NOT (
      v_old.account = ANY (public.get_my_allowed_accounts())
      OR EXISTS (
        SELECT 1 FROM public.user_scopes us
        WHERE  us.user_id    = v_profile_id
          AND  us.account_id = v_old.account_id
      )
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us
        JOIN   public.accounts   ac ON ac.id = v_old.account_id
        WHERE  us.user_id    = v_profile_id
          AND  us.account_id IS NULL
          AND  us.group_id   = ac.group_id
      )
      OR EXISTS (
        SELECT 1
        FROM   public.users_profile up_f
        JOIN   public.accounts      ac ON ac.id = v_old.account_id
        WHERE  up_f.id = v_profile_id
          AND  NOT EXISTS (
            SELECT 1 FROM public.user_scopes us_any
            WHERE  us_any.user_id = v_profile_id
              AND  (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
          )
          AND  (up_f.account_id = v_old.account_id OR up_f.group_id = ac.group_id)
      )
    ) THEN
      RAISE EXCEPTION 'forbidden: hr_emploc record is outside your assigned scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ----------------------------------------------------------------
  -- 7. Terminal state guard
  --    Records already moved to Plantilla must never be modified.
  -- ----------------------------------------------------------------
  IF v_old.moved_to_plantilla_at IS NOT NULL
     OR v_old.status = 'Moved to Plantilla'
  THEN
    RAISE EXCEPTION 'action not allowed: employee has already been moved to Plantilla'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 8. Pending deletion lock
  --    Mirrors trg_hr_emploc_pending_deletion_lock and the explicit
  --    guard in assign_hr_emploc_number / submit_hrco_correction_update.
  -- ----------------------------------------------------------------
  IF EXISTS (
    SELECT 1
    FROM   public.hr_emploc_deletion_requests
    WHERE  hr_emploc_id = p_hr_emploc_id
      AND  status       = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 9. Complete state guard
  --    Complete = employee number assigned and ready for Plantilla.
  --    Deficiency tagging on a Complete record is a logical conflict.
  -- ----------------------------------------------------------------
  IF v_old.hr_status = 'Complete' THEN
    RAISE EXCEPTION 'action not allowed: hr_emploc is already in Complete state (employee number assigned)'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 10. Apply deficiency tagging
  --     Mirrors mark_for_correction semantics:
  --       correction_reason ← p_deficiencies (JSONB array)
  --       hr_status         ← 'For Correction'
  --       status            ← 'For Compliance'
  --       hr_remarks        ← p_remarks if non-empty, else preserve existing
  --       audit fields      ← stamped
  -- ----------------------------------------------------------------
  UPDATE public.hr_emploc
  SET    correction_reason = p_deficiencies,
         hr_status         = 'For Correction',
         status            = 'For Compliance',
         hr_remarks        = COALESCE(
                               NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
                               hr_remarks
                             ),
         hr_reviewed_at    = now(),
         hr_reviewed_by    = public.get_my_full_name(),
         updated_at        = now(),
         updated_by        = v_profile_id
  WHERE  id = p_hr_emploc_id
  RETURNING * INTO v_new;

  -- ----------------------------------------------------------------
  -- 11. Audit trail via existing log_audit_event helper
  -- ----------------------------------------------------------------
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  -- ----------------------------------------------------------------
  -- 12. Return JSONB result envelope
  -- ----------------------------------------------------------------
  RETURN jsonb_build_object(
    'status',           'ok',
    'hr_emploc_id',     v_new.id,
    'hr_status',        v_new.hr_status,
    'deficiency_count', jsonb_array_length(p_deficiencies),
    'tagged_by',        public.get_my_full_name(),
    'tagged_at',        now()
  );

END;
$function$;

CREATE OR REPLACE FUNCTION public.tg_auto_close_coverage_on_slot_occupied()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cov_row            record;
  v_wa_row             record;
  v_vac_row            record;
BEGIN
  -- Trigger executes only when slot transitions to 'occupied'
  IF NEW.slot_status = 'occupied' AND OLD.slot_status IS DISTINCT FROM 'occupied' THEN
    
    -- If store_id is null, there is nothing to stop
    IF NEW.store_id IS NOT NULL THEN
      
      -- A. Close ALL active vacancy coverages for this store
      FOR v_cov_row IN
        SELECT vc.*, v.vcode AS vac_vcode
        FROM public.vacancy_coverage vc
        JOIN public.vacancies v ON (vc.vacancy_id = v.id OR vc.vcode = v.vcode)
        WHERE v.store_id = NEW.store_id
          AND vc.status = 'Active'::public.vacancy_coverage_status
          AND vc.archived_at IS NULL
      LOOP
        UPDATE public.vacancy_coverage
        SET status = 'Ended'::public.vacancy_coverage_status,
            covered_until = CURRENT_DATE,
            updated_at = NOW(),
            updated_by = auth.uid()
        WHERE id = v_cov_row.id;

        -- Write audit log for coverage closure
        PERFORM public.log_audit_event(
          'vacancy_coverage',
          'UPDATE',
          v_cov_row.id,
          to_jsonb(v_cov_row),
          jsonb_build_object(
            'status', 'Ended',
            'covered_until', CURRENT_DATE,
            'notes', 'Coverage Auto Closed. Reason: Position Filled / Applicant Onboarded. Triggered By: System. Affected Vacancy: ' || v_cov_row.vac_vcode
          )
        );
      END LOOP;

      -- B. Close ALL active workforce assignments for this store
      -- Resolve the primary vacancy matching the slot's position first
      SELECT id, vcode INTO v_vac_row
      FROM public.vacancies
      WHERE store_id = NEW.store_id
        AND lower(trim(position)) = lower(trim(NEW.position))
        AND deleted_at IS NULL
        AND is_archived = false
      LIMIT 1;

      -- Fallback: match by store only
      IF v_vac_row.id IS NULL THEN
        SELECT id, vcode INTO v_vac_row
        FROM public.vacancies
        WHERE store_id = NEW.store_id
          AND deleted_at IS NULL
          AND is_archived = false
        LIMIT 1;
      END IF;

      FOR v_wa_row IN
        SELECT 
          wa.id, 
          wa.employee_id, 
          wa.deployment_type, 
          wa.start_date, 
          wa.end_date, 
          wa.assigned_store_id, 
          wa.assigned_account_id, 
          pt.employee_no,
          pt.employee_name
        FROM public.workforce_assignments wa
        JOIN public.plantilla pt ON pt.id = wa.employee_id
        WHERE wa.assigned_store_id = NEW.store_id
          AND wa.status = ANY (ARRAY['Approved', 'Deployed', 'Active', 'In Progress'])
      LOOP
        UPDATE public.workforce_assignments
        SET status = 'Completed',
            completed_at = NOW(),
            end_reason = 'Position Filled / Applicant Onboarded',
            covered_vacancy_id = v_vac_row.id,
            notes = CONCAT_WS(E'\n', NULLIF(notes, ''), 'Auto-closed: covered vacancy store was filled')
        WHERE id = v_wa_row.id;

        -- Write audit log for assignment update
        PERFORM public.log_audit_event(
          'workforce_assignments',
          'UPDATE',
          v_wa_row.id,
          jsonb_build_object('status', 'Active'),
          jsonb_build_object(
            'status', 'Completed',
            'end_reason', 'Position Filled / Applicant Onboarded',
            'covered_vacancy_id', v_vac_row.id,
            'notes', 'Auto-closed: covered vacancy store was filled'
          )
        );

        -- Write employee activity log
        INSERT INTO public.employee_activity_log (
          emploc_no,
          vcode,
          activity_type,
          description,
          performed_by,
          metadata
        ) VALUES (
          v_wa_row.employee_no,
          COALESCE(v_vac_row.vcode, '—'),
          'Coverage Auto Closed',
          format(
            E'Coverage Auto Closed\nReason:\nPosition Filled / Applicant Onboarded\n\nTriggered By:\nSystem\n\nAffected Vacancy:\n%s\n\nAffected Workforce Assignment:\n%s',
            COALESCE(v_vac_row.vcode, '—'),
            v_wa_row.id::text
          ),
          'System',
          jsonb_build_object(
            'affected_vacancy_vcode', COALESCE(v_vac_row.vcode, '—'),
            'affected_workforce_assignment_id', v_wa_row.id,
            'employee_name', v_wa_row.employee_name,
            'deployment_type', v_wa_row.deployment_type,
            'store_id', v_wa_row.assigned_store_id,
            'account_id', v_wa_row.assigned_account_id,
            'position_covered', NEW.position,
            'start_date', v_wa_row.start_date,
            'end_date', v_wa_row.end_date
          )
        );
      END LOOP;

    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_coverage_request_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link     text := '/coverage-requests/' || NEW.id::text;
  v_kind     text;
  v_req_auth uuid;
  v_req_role text;
BEGIN
  v_kind := CASE WHEN NEW.request_type::text ILIKE '%group%'
                 THEN 'Coverage Group Request' ELSE 'Coverage Request' END;

  -- Submitted: draft -> pending  →  notify all active SA/HA/Encoder approvers
  IF NEW.status::text = 'pending' AND OLD.status::text = 'draft' THEN
    BEGIN
      PERFORM public._rnw_notify_roles(
        ARRAY['Super Admin','Head Admin','Encoder'],
        'New ' || v_kind,
        COALESCE(NEW.requested_by_name, 'A user') || ' submitted a '
          || lower(v_kind) || ' for review.',
        'coverage_request', 'COVERAGE_REQUEST_SUBMITTED',
        'coverage_request', NEW.id::text, v_link
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'trg_coverage_request_notify: approver notification failed — request_id: %, error: %',
        NEW.id, SQLERRM;
    END;
    RETURN NEW;
  END IF;

  -- Decision: pending -> approved | rejected  →  notify requester
  IF NEW.status IS DISTINCT FROM OLD.status
     AND OLD.status::text = 'pending'
     AND NEW.status::text IN ('approved','rejected') THEN

    v_req_auth := public._rnw_auth_uid(NEW.requested_by);
    IF v_req_auth IS NOT NULL THEN
      BEGIN
        SELECT ro.role_name INTO v_req_role
        FROM public.users_profile up
        JOIN public.roles ro ON ro.id = up.role_id
        WHERE up.auth_user_id = v_req_auth
        LIMIT 1;

        PERFORM public.notify_user(
          v_req_auth, COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
          v_kind || ' ' || initcap(NEW.status::text),
          'Your ' || lower(v_kind) || ' was ' || NEW.status::text
            || COALESCE('. Reason: ' || NULLIF(NEW.rejection_reason, ''), '') || '.',
          'coverage_request',
          CASE WHEN NEW.status::text = 'approved'
               THEN 'COVERAGE_REQUEST_APPROVED' ELSE 'COVERAGE_REQUEST_REJECTED' END,
          'coverage_request', NEW.id::text, v_link, NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'trg_coverage_request_notify: requester notification failed — request_id: %, recipient: %, error: %',
          NEW.id, v_req_auth, SQLERRM;
      END;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_hc_request_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link     text := '/headcount-requests/' || NEW.id::text;
  v_label    text;
  v_req_auth uuid;
  v_req_role text;
BEGIN
  v_label := COALESCE(NEW.position_name_snapshot, 'Headcount')
           || ' ×' || COALESCE(NEW.headcount_needed, 1)::text
           || ' @ ' || COALESCE(NULLIF(NEW.store_name_snapshot, ''),
                                NULLIF(NEW.account_name_snapshot, ''), 'store');

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'Pending Approval' THEN
      BEGIN
        PERFORM public._rnw_notify_roles(
          ARRAY['Super Admin','Head Admin','Encoder'],
          'New Headcount Request',
          COALESCE(NEW.requested_by_name, 'A user') || ' submitted an HC request: ' || v_label || '.',
          'headcount_request', 'HC_REQUEST_SUBMITTED',
          'headcount_request', NEW.id::text, v_link
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'trg_hc_request_notify: approver notification failed — request_id: %, error: %',
          NEW.id, SQLERRM;
      END;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE OF status: notify requestor on Approved / Rejected / Slot Created
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('Approved','Rejected','Slot Created') THEN

    v_req_auth := public._rnw_auth_uid(NEW.requested_by_user_id);
    IF v_req_auth IS NOT NULL THEN
      BEGIN
        SELECT ro.role_name INTO v_req_role
        FROM public.users_profile up
        JOIN public.roles ro ON ro.id = up.role_id
        WHERE up.auth_user_id = v_req_auth
        LIMIT 1;

        PERFORM public.notify_user(
          v_req_auth, COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
          CASE NEW.status
            WHEN 'Approved'     THEN 'Headcount Request Approved'
            WHEN 'Rejected'     THEN 'Headcount Request Rejected'
            ELSE                     'Headcount Request Fulfilled'
          END,
          'Your headcount request ' || v_label || ' is now "' || NEW.status || '".',
          'headcount_request',
          CASE NEW.status
            WHEN 'Approved'     THEN 'HC_REQUEST_APPROVED'
            WHEN 'Rejected'     THEN 'HC_REQUEST_REJECTED'
            ELSE                     'HC_REQUEST_COMPLETED'
          END,
          'headcount_request', NEW.id::text, v_link, NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'trg_hc_request_notify: requester notification failed — request_id: %, recipient: %, error: %',
          NEW.id, v_req_auth, SQLERRM;
      END;
    ELSE
      RAISE WARNING
        'trg_hc_request_notify: could not resolve auth UUID for requested_by_user_id %, request_id %; notification skipped.',
        NEW.requested_by_user_id, NEW.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.unlock_vacancy_editing(p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text;
  v_user_id     uuid;
  v_sched       boolean;
  v_old_state   jsonb;
  v_new_state   jsonb;
  v_action_type text;
BEGIN
  v_role := public.get_effective_role();
  IF v_role NOT IN ('Super Admin', 'Head Admin') THEN
    RAISE EXCEPTION 'Access Denied: Head Admin or Super Admin only' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason is required for manual unlock' USING ERRCODE = '22000';
  END IF;

  v_user_id := public.get_current_profile_id();
  v_sched   := public.is_scheduled_lock_active();

  SELECT to_jsonb(l.*) INTO v_old_state
  FROM public.vacancy_edit_locks l WHERE l.id = 1;

  IF v_sched THEN
    -- Scheduled window is active: record as an explicit admin override.
    -- is_locked stays false; non-admin users remain blocked by the scheduled
    -- lock; SA/HA bypass it via fn_assert_vacancy_edit_allowed_op.
    v_action_type := 'override';
    UPDATE public.vacancy_edit_locks
    SET is_locked          = false,
        is_override_active = true,
        override_by        = v_user_id,
        override_until     = NULL,   -- active until next manual lock or window end
        reason             = p_reason,
        unlocked_by        = v_user_id,
        unlocked_at        = now(),
        updated_at         = now()
    WHERE id = 1;
  ELSE
    -- Normal unlock outside scheduled window
    v_action_type := 'unlock';
    UPDATE public.vacancy_edit_locks
    SET is_locked          = false,
        is_override_active = false,
        override_by        = NULL,
        override_until     = NULL,
        reason             = p_reason,
        unlocked_by        = v_user_id,
        unlocked_at        = now(),
        updated_at         = now()
    WHERE id = 1;
  END IF;

  SELECT to_jsonb(l.*) INTO v_new_state
  FROM public.vacancy_edit_locks l WHERE l.id = 1;

  INSERT INTO public.vacancy_edit_lock_audit (
    action_type, actor_user_id, actor_role, reason, previous_state, new_state
  ) VALUES (v_action_type, v_user_id, v_role, p_reason, v_old_state, v_new_state);

  RETURN jsonb_build_object(
    'success',           true,
    'is_locked',         false,
    'is_override_active', v_sched,
    'unlocked_at',       now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_coverage_request_draft(p_coverage_request_id uuid, p_request_type request_type, p_payload jsonb, p_account_id uuid DEFAULT NULL::uuid, p_position_id uuid DEFAULT NULL::uuid, p_employment_type text DEFAULT NULL::text, p_target_coverage_group_id uuid DEFAULT NULL::uuid, p_source_coverage_group_id uuid DEFAULT NULL::uuid, p_destination_coverage_group_id uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor   record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  -- Identify caller
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  -- Load the draft (with lock)
  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'draft'::public.request_status THEN
    RAISE EXCEPTION 'only draft requests can be edited (status: %)', v_request.status
      USING ERRCODE = '22023';
  END IF;

  -- Authorization: requester OR mutate-capable role
  IF v_request.requested_by <> v_actor.profile_id
     AND NOT public.fn_can_mutate_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only the requester or Encoder/HA/SA can edit this draft'
      USING ERRCODE = '42501';
  END IF;

  -- Validate payload for the new type/scope, passing the draft request ID to exclude from conflict checks
  PERFORM public._validate_coverage_request_payload(
    p_request_type,
    p_payload,
    p_account_id,
    p_position_id,
    p_employment_type,
    p_target_coverage_group_id,
    p_source_coverage_group_id,
    p_destination_coverage_group_id,
    p_coverage_request_id
  );

  -- Apply update
  UPDATE public.coverage_requests
  SET
    request_type                  = p_request_type,
    payload                       = p_payload,
    account_id                    = p_account_id,
    position_id                   = p_position_id,
    employment_type               = p_employment_type,
    target_coverage_group_id      = p_target_coverage_group_id,
    source_coverage_group_id      = p_source_coverage_group_id,
    destination_coverage_group_id = p_destination_coverage_group_id,
    reason                        = p_reason,
    updated_by                    = v_actor.profile_id,
    updated_at                    = now()
  WHERE id = p_coverage_request_id;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    'draft'::public.request_status,
    'draft'::public.request_status,
    'draft_updated',
    jsonb_build_object('updated_by', v_actor.full_name),
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    NULL
  );

  RETURN jsonb_build_object(
    'status',               'ok',
    'coverage_request_id',  p_coverage_request_id,
    'request_status',       'draft'
  );
END;
$function$;


COMMIT;
