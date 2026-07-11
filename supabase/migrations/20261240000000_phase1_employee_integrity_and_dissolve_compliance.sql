-- ============================================================================
-- OHM2026_CG_0003 Phase 1 — Employee Integrity Lock & Dissolve Compliance
-- Migration: 20261240000000_phase1_employee_integrity_and_dissolve_compliance.sql
--
-- Implements ADR-001 compliance for three audit gaps:
--
--   GAP-01 — Employee Integrity Lock (Remove Store)
--     Before executing a Remove Store request, validate that no active
--     employee would be left with 0 active store assignments. Applies to
--     both imported employees (ESA rows) and non-imported (plantilla_store_links).
--     Block with ERRCODE 23514 if any employee would reach 0 stores.
--
--   GAP-02 — Dissolve Coverage Group Compliance
--     dissolve_coverage_group must NOT mark employees inactive.
--     Every active roving employee must retain a Home Store selected by the
--     approver. Employees are converted to Stationary at their retained store.
--     Requires payload.employee_home_stores = {plantilla_id: store_id, ...}.
--     Block if any employee is missing a retained home store.
--
--   GAP-03 — Vacancy Reuse / Reopen on Dissolve
--     Dissolve must reopen existing vacancies (by VCode) for every store
--     that loses coverage. Never create a duplicate vacancy. Uses the same
--     slot-first vacancy reopen logic already proven for Remove Store.
--
-- Supersedes:
--   dissolve_coverage_group branch of 20261236000000 (and all prior versions).
--   remove_store validation is additive on top of 20261236000000.
--
-- §1  Seed slot_reason_codes: COVERAGE_GROUP_DISSOLVED
-- §2  Update _validate_coverage_request_payload: allow employee_home_stores
-- §3  Update _execute_approved_coverage_request: GAP-01 + GAP-02 + GAP-03
-- ============================================================================

BEGIN;

-- ── §1. Seed slot reason code ───────────────────────────────────────────────
INSERT INTO public.slot_reason_codes (code, label, description, sort_order)
VALUES (
  'COVERAGE_GROUP_DISSOLVED',
  'Coverage Group Dissolved',
  'Slot reopened because its coverage group was dissolved via Coverage Request.',
  (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM public.slot_reason_codes)
)
ON CONFLICT (code) DO NOTHING;

-- ── §2. Update _validate_coverage_request_payload ───────────────────────────
-- Add employee_home_stores to allowed keys for dissolve_coverage_group.
-- Format: {"<plantilla_uuid>": "<store_uuid>", ...}
-- Validation of individual store membership is handled at execution time.
CREATE OR REPLACE FUNCTION public._validate_coverage_request_payload(
  p_request_type public.request_type,
  p_payload jsonb,
  p_account_id uuid DEFAULT NULL,
  p_position_id uuid DEFAULT NULL,
  p_employment_type text DEFAULT NULL,
  p_target_coverage_group_id uuid DEFAULT NULL,
  p_source_coverage_group_id uuid DEFAULT NULL,
  p_destination_coverage_group_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_store_ids uuid[];
  v_anchor_store_id uuid;
  v_target_account_id uuid;
  v_source_account_id uuid;
  v_destination_account_id uuid;
  v_effective_account_id uuid;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'payload must be a json object' USING ERRCODE = '22023';
  END IF;

  IF p_payload::text ~* '"(required_hc|required_headcount|headcount|hc|slot_id|slot_ids|vacancy_id|vacancy_vcode|vcode|pipeline_id|coverage_weight|hc_share|store_count)"[[:space:]]*:' THEN
    RAISE EXCEPTION 'Coverage Request payload must remain structure-only; HC, slot, vacancy, pipeline, coverage weight, and HC share fields are not allowed'
      USING ERRCODE = '22023';
  END IF;

  IF p_target_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_target_account_id
    FROM public.coverage_groups
    WHERE id = p_target_coverage_group_id
      AND archived_at IS NULL;

    IF v_target_account_id IS NULL THEN
      RAISE EXCEPTION 'target coverage group not found or archived'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF p_source_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_source_account_id
    FROM public.coverage_groups
    WHERE id = p_source_coverage_group_id
      AND archived_at IS NULL;
  END IF;

  IF p_destination_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_destination_account_id
    FROM public.coverage_groups
    WHERE id = p_destination_coverage_group_id
      AND archived_at IS NULL;
  END IF;

  -- Normalize imported roving groups for validation
  IF p_target_coverage_group_id IS NOT NULL AND v_target_account_id IS NULL THEN
    PERFORM public.fn_normalize_imported_roving_group(p_target_coverage_group_id);
    SELECT account_id INTO v_target_account_id
    FROM public.coverage_groups
    WHERE id = p_target_coverage_group_id AND archived_at IS NULL;
  END IF;

  IF p_request_type = 'create_coverage_group'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['store_ids', 'anchor_store_id', 'area_name', 'employment_type', 'notes']
    );
    IF p_account_id IS NULL THEN
      RAISE EXCEPTION 'create_coverage_group requires account_id' USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'add_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'add_store requires target_coverage_group_id' USING ERRCODE = '22023';
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
      RAISE EXCEPTION 'convert_roving_to_stationary requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

  ELSIF p_request_type = 'merge_coverage_groups'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['notes']);
    IF p_source_coverage_group_id IS NULL OR p_destination_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'merge_coverage_groups requires source_coverage_group_id and destination_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    IF p_source_coverage_group_id = p_destination_coverage_group_id THEN
      RAISE EXCEPTION 'merge_coverage_groups source and destination must be different'
        USING ERRCODE = '22023';
    END IF;
    IF v_source_account_id <> v_destination_account_id THEN
      RAISE EXCEPTION 'merge_coverage_groups source and destination must belong to the same account'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    -- GAP-02: employee_home_stores is now a valid dissolve payload key
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['notes', 'employee_home_stores']
    );
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'dissolve_coverage_group requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    -- Validate employee_home_stores structure if present
    IF (p_payload -> 'employee_home_stores') IS NOT NULL
      AND jsonb_typeof(p_payload -> 'employee_home_stores') <> 'object'
    THEN
      RAISE EXCEPTION 'employee_home_stores must be a JSON object {plantilla_id: store_id}'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'unsupported request_type: %', p_request_type
      USING ERRCODE = '22023';
  END IF;
END;
$fn$;

-- ── §3. Update _execute_approved_coverage_request ───────────────────────────
-- Full function rewrite. Supersedes 20261236000000.
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
BEGIN

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── add_store ───────────────────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  IF p_request.request_type = 'add_store'::public.request_type THEN
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

    -- ── Bug 1 fix: Pre-resolve group_id from coverage group's account ──────────
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- ── Bug 2 fix: Pre-resolve position from coverage_groups → positions ───────
    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- ── Resolve which stores are being REMOVED ────────────────────────────────
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

    -- ════════════════════════════════════════════════════════════════════════
    -- ── GAP-01: Employee Integrity Lock ─────────────────────────────────────
    --
    -- Only applies when remaining_count >= 2 (employees stay in group).
    -- When remaining_count == 1, Branch A converts the employee to
    -- Stationary at the retained store — always exactly 1 store. Safe.
    --
    -- When remaining_count >= 2: ESA rows for removed stores are deactivated.
    -- Block if any employee would be left with 0 active store assignments.
    -- ════════════════════════════════════════════════════════════════════════
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
          FROM public.plantilla_store_links
          WHERE plantilla_id = v_pl.id
            AND deleted_at IS NULL
            AND NOT (store_id = ANY(v_removed_store_ids));

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

    -- ── Branch A: convert_remaining_to_standalone (remaining_count = 1) ────────
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

    -- ── Archive removed store edges + employee sync ─────────────────────────
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
          UPDATE public.plantilla_store_links
          SET status = 'Resigned', deleted_at = now()
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND deleted_at IS NULL;
        END IF;
      END LOOP;
    END IF;

    -- ════════════════════════════════════════════════════════════════════════
    -- ── Vacancy Slot Reopening for each removed store (slot-first) ──────────
    -- ════════════════════════════════════════════════════════════════════════
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
  -- ── dissolve_coverage_group (GAP-02 + GAP-03) ─────────────────────────────
  --
  -- GAP-02: Every active roving employee must retain a Home Store.
  --         Employees are converted to Stationary — NOT marked Inactive.
  -- GAP-03: Stores losing coverage get vacancies reopened/created (slot-first,
  --         reusing existing VCode — never creating duplicates).
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN

    -- Pre-resolve group/position (Bug 1 + Bug 2 equivalent for dissolve)
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

    -- Read employee_home_stores from payload
    v_employee_home_stores := COALESCE(
      p_request.payload -> 'employee_home_stores',
      '{}'::jsonb
    );

    -- ── GAP-02 validation: require home store for every active employee ─────
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

    -- Collect the set of retained store IDs (distinct across all employees)
    SELECT COALESCE(array_agg(DISTINCT val::uuid), ARRAY[]::uuid[])
    INTO v_retained_store_ids
    FROM jsonb_each_text(v_employee_home_stores) AS t(key, val);

    -- Validate that all retained stores are active members of this group
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

    -- Compute stores that will lose coverage = all group stores NOT retained by any employee
    SELECT COALESCE(array_agg(cgs.store_id), ARRAY[]::uuid[])
    INTO v_dissolved_store_ids
    FROM public.coverage_group_stores cgs
    WHERE cgs.coverage_group_id = p_request.target_coverage_group_id
      AND cgs.archived_at IS NULL
      AND NOT (cgs.store_id = ANY(COALESCE(v_retained_store_ids, ARRAY[]::uuid[])));

    -- ── GAP-02: Convert each employee to Stationary at their retained store ──
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

      -- Convert to Stationary (employee stays ACTIVE — not Inactive)
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
        -- Deactivate all ESA rows for non-retained stores
        UPDATE public.employee_store_allocations
        SET is_active = false, effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id
          AND is_active = true
          AND store_id <> v_remaining_store_id;

        -- Ensure the retained store has an active ESA
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
        -- Non-imported: mark non-retained store links as resigned
        UPDATE public.plantilla_store_links
        SET status = 'Resigned', deleted_at = now()
        WHERE plantilla_id = v_pl.id
          AND store_id <> v_remaining_store_id
          AND deleted_at IS NULL;
      END IF;

      v_employees_converted := v_employees_converted + 1;
      v_notes := v_notes || ARRAY[
        'employee:' || COALESCE(v_pl.employee_name, v_pl.employee_no, v_pl.id::text)
        || '|converted_to_stationary_at:' || COALESCE(v_remaining_store_name, v_remaining_store_id::text)
      ];
    END LOOP;

    -- Archive all group store edges
    UPDATE public.coverage_group_stores
    SET archived_at = now(), archived_by = p_actor_id
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    -- Close all coverage slots
    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND slot_status <> 'closed';

    -- Archive the coverage group
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request execution: dissolved — employees converted to Stationary'
    WHERE id = p_request.target_coverage_group_id;

    v_group_archived := true;

    -- ── GAP-03: Reopen vacancies for stores that lost coverage ───────────────
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
        v_store_chain_id    := NULL;  -- not tracked at store level

        IF v_store_vcode IS NULL THEN
          v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
          CONTINUE;
        END IF;

        v_store_position    := COALESCE(v_cg_position_name, 'Unknown');
        v_store_position_id := v_cg_position_id;
        v_store_employment_type := 'Stationary';

        -- Step 1: Reopen existing vacancy by VCode (GAP-03: reuse, never duplicate)
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

        -- Step 2: Create vacancy only if none exists
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

        -- Step 3: Reopen existing plantilla_slot (prefer non-closed)
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

        -- Step 4: slot_history audit entry
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

COMMENT ON FUNCTION public._execute_approved_coverage_request(public.coverage_requests, uuid, text, text) IS
  'OHM2026_CG_0003 Phase 1: '
  'GAP-01 — employee integrity lock: remove_store blocked if any employee would reach 0 active store assignments. '
  'GAP-02 — dissolve no longer marks employees inactive; requires employee_home_stores payload; converts each employee to Stationary at retained store. '
  'GAP-03 — dissolve reopens/creates vacancies for all stores losing coverage (slot-first, VCode reuse, never duplicate). '
  'Supersedes 20261236000000 dissolve branch.';

NOTIFY pgrst, 'reload schema';

-- ── Smoke tests (run manually after applying) ────────────────────────────────
/*
  -- TEST-01: Roving employee 3 stores → Dissolve, retain Store 1
  -- 1. Find employee 2026-XXXXX in a 3-store coverage group
  -- 2. Submit dissolve request with employee_home_stores = {plantilla_uuid: store1_uuid}
  -- 3. Approve dissolve request
  -- Expected:
  --   SELECT deployment_type, status, store_id FROM plantilla WHERE id = '...';
  --   → deployment_type = 'Stationary', status = 'Active', store_id = store1_id
  --   SELECT vcode, status FROM vacancies WHERE store_id IN (store2_id, store3_id);
  --   → 2 rows with status = 'Open'

  -- TEST-02: Remove Store would leave employee with 0 stores
  -- 1. Find imported employee with ESAs for only 1 store in a 3-store group
  --    (edge case: employee only allocated to the stores being removed)
  -- 2. Submit remove_store for those stores
  -- 3. Approve
  -- Expected: RAISE EXCEPTION ERRCODE 23514 — employee integrity lock

  -- TEST-03: Dissolve without home store
  -- 1. Submit dissolve with empty employee_home_stores {}
  -- 2. Approve
  -- Expected: RAISE EXCEPTION ERRCODE 23514 — home store missing

  -- TEST-04: Dissolve when vacancy already exists
  -- 1. Ensure vacancy exists for one of the dissolve stores
  -- 2. Approve dissolve
  -- Expected:
  --   SELECT COUNT(*) FROM vacancies WHERE vcode = '<store_vcode>';
  --   → 1 (reused, not duplicated)
  --   SELECT status FROM vacancies WHERE vcode = '<store_vcode>';
  --   → 'Open'
*/

COMMIT;
