-- Migration: 20260630000001_fix_remove_store_vacancy_uuid_cast
-- Created: 2026-06-30
-- Prompt ID: ohm#4b9a7e2q
-- Purpose: Fix 22P02 "invalid input syntax for type integer" when approving a
--          Remove Store coverage request.
--
-- Root cause: In the remove_store branch of _execute_approved_coverage_request,
--   the variable v_rows_updated is declared as INTEGER (line used for GET
--   DIAGNOSTICS / row-count purposes), but was then reused as the target for
--     SELECT id INTO v_rows_updated FROM public.vacancies …
--   vacancies.id is UUID, so PostgreSQL raises 22P02 when the UUID string
--   "76658c5c-…" is cast to integer.
--
-- Fix: Introduce a dedicated v_vacancy_id UUID variable; use it for the
--   vacancy-lookup SELECT and the subsequent WHERE id = … UPDATE.
--   v_rows_updated (integer) is left in the DECLARE section unchanged because
--   it is referenced by the GET DIAGNOSTICS statement that counts archived store
--   edges (v_stores_removed = ROW_COUNT).
--
-- Branches NOT changed: add_store, create_coverage_group, dissolve_coverage_group
--   (dissolve already uses EXISTS + UPDATE WHERE vcode — no integer cast issue).
--
-- Smoke tests:
-- S1: Approve a remove_store request with SM CALOOKOHAN — must complete without 22P02
-- S2: Existing vacancy for the removed store is reopened (status = 'Open')
-- S3: New vacancy INSERT fires correctly when no existing vacancy exists
-- S4: flutter analyze passes
-- S5: Dissolve and Add Store approvals still work (unaffected branches)

CREATE OR REPLACE FUNCTION public._execute_approved_coverage_request(
  p_request   coverage_requests,
  p_actor_id  uuid,
  p_actor_name text,
  p_actor_role text
)
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
  v_vacancy_id             uuid;   -- FIX ohm#4b9a7e2q: dedicated UUID for vacancy id lookup
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

  -- ── add_store: account name for plantilla_store_links
  v_cg_account_name        text;

  -- ── Add Store candidate promotion variables
  v_has_active_employee    boolean;
  v_anchor_store_id        uuid;
  v_candidate_count        integer;
  v_candidate_id           uuid;
  v_cov_slot_id            uuid;
  v_member_store_id        uuid;
  v_anchor_emp_no          text;
  v_anchor_emp_name        text;
  v_anchor_account_id      uuid;
  v_anchor_group_id        uuid;
  v_anchor_baseline_import_batch_id uuid;
  v_anchor_emp_import_batch_id uuid;
  v_resolved_emp_id        uuid;
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

    -- STEP 3 & 4: Evaluate member stores and assign active employees.
    -- FIX (ohm#pos_nullable01): When p_request.position_id IS NULL, promote ALL
    -- active employees at the member stores (position-agnostic).  When it is set,
    -- restrict to employees of that exact position (original behaviour preserved).
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

    -- Recompute HC shares for the new group
    PERFORM public.fn_recompute_cg_hc_shares(v_new_cg_id);

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

    -- Pre-resolve account name for plantilla_store_links (live employee branch)
    SELECT a.account_name INTO v_cg_account_name
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Pre-resolve CG position metadata
    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- Check if the coverage group has any active roving employee
    SELECT EXISTS (
      SELECT 1 FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) INTO v_has_active_employee;

    v_candidate_id := NULL;

    IF NOT v_has_active_employee THEN
      -- Resolve the anchor store ID
      SELECT store_id INTO v_anchor_store_id
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND is_anchor = true
        AND archived_at IS NULL
      LIMIT 1;

      IF v_anchor_store_id IS NOT NULL THEN
        -- Find active stationary employee at that store
        SELECT count(*), max(id)
        INTO v_candidate_count, v_candidate_id
        FROM public.plantilla
        WHERE store_id = v_anchor_store_id
          AND status = 'Active'
          AND deployment_type = 'Stationary'
          AND is_deleted = false
          AND is_archived = false;

        IF v_candidate_count > 1 THEN
          RAISE EXCEPTION 'More than one candidate employee found at anchor store %', v_anchor_store_id
            USING ERRCODE = '23514';
        ELSIF v_candidate_count = 1 THEN
          -- Promote the candidate employee
          SELECT employee_no, employee_name, account_id, group_id,
                 source_baseline_import_batch_id, source_employee_import_batch_id
          INTO v_anchor_emp_no, v_anchor_emp_name, v_anchor_account_id, v_anchor_group_id,
               v_anchor_baseline_import_batch_id, v_anchor_emp_import_batch_id
          FROM public.plantilla
          WHERE id = v_candidate_id;

          -- Create active coverage slot row
          v_cov_slot_id := gen_random_uuid();
          INSERT INTO public.coverage_slots (
            id, coverage_group_id, slot_ordinal, slot_status, current_occupant_plantilla_id, created_at, updated_at
          ) VALUES (
            v_cov_slot_id, p_request.target_coverage_group_id, 1, 'active', v_candidate_id, now(), now()
          );

          -- Update employee plantilla row to roving
          UPDATE public.plantilla
          SET deployment_type = 'Roving',
              coverage_group_id = p_request.target_coverage_group_id,
              coverage_slot_id = v_cov_slot_id,
              vcode = NULL
          WHERE id = v_candidate_id;

          -- Vacate old stationary slot in plantilla_slots
          SELECT id, legacy_vcode INTO v_old_slot_id, v_old_vcode
          FROM public.plantilla_slots
          WHERE current_occupant_plantilla_id = v_candidate_id
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
              v_old_slot_id, v_anchor_account_id, 'employee_separated',
              'occupied', 'open', 'COVERAGE_GROUP_PROMOTED',
              p_actor_id, 'Employee promoted to roving coverage in group ' || p_request.target_coverage_group_id || '.', now()
            );
          END IF;

          -- Handle links/allocations for the candidate
          IF v_anchor_baseline_import_batch_id IS NOT NULL OR v_anchor_emp_import_batch_id IS NOT NULL THEN
            -- Deactivate old allocations
            UPDATE public.employee_store_allocations
            SET is_active = false,
                effective_end = CURRENT_DATE
            WHERE plantilla_id = v_candidate_id AND is_active = true;

            -- Insert new allocations for all existing group stores
            FOR v_member_store_id IN (
              SELECT store_id FROM public.coverage_group_stores
              WHERE coverage_group_id = p_request.target_coverage_group_id
                AND archived_at IS NULL
            ) LOOP
              SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
              FROM public.stores WHERE id = v_member_store_id;

              IF NOT EXISTS (
                SELECT 1 FROM public.employee_store_allocations
                WHERE plantilla_id = v_candidate_id
                  AND store_id = v_member_store_id
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
                  v_candidate_id, v_anchor_emp_no, p_request.target_coverage_group_id,
                  v_member_store_id, v_store_vcode, v_store_name_local,
                  v_anchor_account_id, v_anchor_group_id,
                  1, 1,
                  CURRENT_DATE, true,
                  COALESCE(v_anchor_baseline_import_batch_id, v_anchor_emp_import_batch_id), p_actor_id
                );
              END IF;
            END LOOP;
          ELSE
            -- Live employee: deactivate old store links
            UPDATE public.plantilla_store_links
            SET status = 'Resigned',
                deleted_at = now(),
                unlinked_at = now(),
                unlinked_by = p_actor_id
            WHERE plantilla_id = v_candidate_id AND deleted_at IS NULL;

            -- Insert new store links for all existing group stores
            FOR v_member_store_id IN (
              SELECT store_id FROM public.coverage_group_stores
              WHERE coverage_group_id = p_request.target_coverage_group_id
                AND archived_at IS NULL
            ) LOOP
              SELECT store_name, vcode INTO v_store_name_local, v_store_vcode
              FROM public.stores WHERE id = v_member_store_id;

              IF NOT EXISTS (
                SELECT 1 FROM public.plantilla_store_links
                WHERE plantilla_id = v_candidate_id
                  AND coverage_group_id = p_request.target_coverage_group_id
                  AND vcode = v_store_vcode
                  AND deleted_at IS NULL
              ) THEN
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
                  v_candidate_id,
                  p_request.target_coverage_group_id,
                  v_store_vcode,
                  v_store_name_local,
                  v_cg_account_name,
                  'Active',
                  now(),
                  p_actor_id,
                  p_actor_id,
                  p_actor_id
                );
              END IF;
            END LOOP;

            PERFORM public.fn_sync_employee_store_allocations(v_anchor_emp_no);
          END IF;

          v_notes := v_notes || ARRAY[
            'employee:' || COALESCE(v_anchor_emp_name, v_anchor_emp_no, v_candidate_id::text)
            || '|promoted_to_roving_on_add_store:' || p_request.target_coverage_group_id::text
          ];
        END IF;
      END IF;
    END IF;

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

      -- ── Per-store, per-employee: propagate new store to all active CG employees
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
          -- ── Imported employee: insert ESA row for the new store ──
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
        ELSE
          -- ── BUG 1 FIX (ohm#4q8z2m7a): Live employee: insert plantilla_store_link ──
          SELECT store_name, vcode
          INTO v_remaining_store_name, v_remaining_store_vcode
          FROM public.stores WHERE id = v_store_id;

          IF NOT EXISTS (
            SELECT 1 FROM public.plantilla_store_links
            WHERE plantilla_id = v_pl.id
              AND coverage_group_id = p_request.target_coverage_group_id
              AND vcode = v_remaining_store_vcode
              AND deleted_at IS NULL
          ) THEN
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
              p_request.target_coverage_group_id,
              v_remaining_store_vcode,
              v_remaining_store_name,
              COALESCE(v_cg_account_name, v_pl.account),
              'Active',
              now(),
              p_actor_id,
              p_actor_id,
              p_actor_id
            );

            PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
          END IF;
        END IF;
      END LOOP;

      -- ── Resolve the active employee in this CG (including the newly promoted one)
      SELECT id INTO v_resolved_emp_id
      FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
      ORDER BY created_at
      LIMIT 1;

      -- ── Slot occupancy & vacancy closure for the added store
      SELECT id, legacy_vcode INTO v_existing_slot_id, v_store_vcode
      FROM public.plantilla_slots
      WHERE store_id = v_store_id
        AND slot_status = 'open'
        AND (position = v_cg_position_name OR position IS NULL)
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_slot_id IS NOT NULL AND v_resolved_emp_id IS NOT NULL THEN
        PERFORM public.fn_set_slot_status(
          v_existing_slot_id,
          'occupied',
          'COVERAGE_STORE_ADDED',
          p_actor_id,
          'Slot occupied due to store added to Coverage Group ' || p_request.target_coverage_group_id::text,
          v_resolved_emp_id
        );

        UPDATE public.vacancies
        SET status = 'Filled',
            is_archived = true,
            archived_at = now(),
            archived_by = p_actor_name,
            updated_at = now(),
            updated_by = p_actor_id
        WHERE store_id = v_store_id
          AND (vcode = v_store_vcode OR position_id = v_cg_position_id)
          AND status = 'Open'
          AND is_archived = false
          AND deleted_at IS NULL;
      END IF;
    END LOOP;

    -- ── Recompute active_store_count + filled_hc for ALL imported employees ──
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

    -- ── BUG 3 FIX (ohm#4q8z2m7a): Recompute HC shares for the target CG ──
    PERFORM public.fn_recompute_cg_hc_shares(p_request.target_coverage_group_id);

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

    -- Pre-resolve position from coverage_groups → positions (NULL-safe)
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
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.plantilla_store_links psl
          JOIN public.stores s ON upper(psl.vcode) = upper(s.vcode)
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
          WHERE upper(psl.vcode) = upper(s.vcode)
            AND psl.plantilla_id = v_pl.id
            AND s.id = ANY(v_removed_store_ids)
            AND psl.deleted_at IS NULL;
        END IF;
      END LOOP;
    END IF;

    -- ── FIX (ohm#9k4p7x2a): Vacancy Slot Reopening for each removed store ──
    -- stores has no province_id or area_name columns; use LEFT JOIN accounts
    -- with COALESCE(area_city, area_province) for location text.
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
        AND pl.status = 'Active'
        AND COALESCE(pl.is_deleted, false) = false
      ORDER BY pl.created_at
      LIMIT 1;

      IF v_store_position IS NULL THEN
        v_store_position := v_cg_position_name;
        v_store_position_id := v_cg_position_id;
      END IF;

      SELECT cg.employment_type
      INTO v_store_employment_type
      FROM public.coverage_groups cg
      WHERE cg.id = p_request.target_coverage_group_id;

      -- Reopen or create slot
      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_store_vcode
        AND slot_status <> 'archived'
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'open',
            current_occupant_plantilla_id = NULL,
            updated_at = now(),
            updated_by = p_actor_id
        WHERE id = v_existing_slot_id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_existing_slot_id, v_store_account_id, 'slot_reopened',
          'occupied', 'open', 'COVERAGE_STORE_REMOVED',
          p_actor_id, 'Store removed from Coverage Group; slot reopened.', now()
        );
      ELSE
        v_new_slot_id := gen_random_uuid();
        INSERT INTO public.plantilla_slots (
          id, account_id, group_id, store_id, chain_id,
          position_id, employment_type, legacy_vcode,
          slot_status, created_at, updated_at, created_by
        ) VALUES (
          v_new_slot_id, v_store_account_id, v_store_group_id, v_store_id, v_store_chain_id,
          v_store_position_id, v_store_employment_type, v_store_vcode,
          'open', now(), now(), p_actor_id
        );

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_new_slot_id, v_store_account_id, 'slot_created',
          NULL, 'open', 'COVERAGE_STORE_REMOVED',
          p_actor_id, 'Store removed from Coverage Group; new slot created.', now()
        );

        v_existing_slot_id := v_new_slot_id;
      END IF;

      -- ── FIX ohm#4b9a7e2q: Use v_vacancy_id (uuid) instead of v_rows_updated
      --    (integer) to hold the existing vacancy's id.  v_rows_updated is integer
      --    and was causing 22P02 "invalid input syntax for type integer: <uuid>".
      SELECT id INTO v_vacancy_id
      FROM public.vacancies
      WHERE vcode = v_store_vcode
        AND deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_vacancy_id IS NOT NULL THEN
        UPDATE public.vacancies
        SET status = 'Open', updated_at = now()
        WHERE id = v_vacancy_id
          AND status NOT IN ('Open', 'Pipeline');
      ELSE
        INSERT INTO public.vacancies (
          vcode, account, store_id, store_name,
          group_id, position, employment_type,
          province, area_city, status,
          created_at, updated_at
        ) VALUES (
          v_store_vcode, v_store_account_name, v_store_id, v_store_name_local,
          v_store_group_id, v_store_position, v_store_employment_type,
          v_store_area, v_store_area, 'Open',
          now(), now()
        );
      END IF;

      v_vacancies_reopened := v_vacancies_reopened + 1;
      v_notes := v_notes || ARRAY['store:' || v_store_name_local || '|vcode:' || v_store_vcode || '|vacancy:reopened'];
    END LOOP;

    -- Recompute HC shares after remove
    IF NOT v_group_archived THEN
      PERFORM public.fn_recompute_cg_hc_shares(p_request.target_coverage_group_id);
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 p_request.request_type,
      'stores_added',                 0,
      'stores_removed',               v_stores_removed,
      'group_archived',               v_group_archived,
      'below_minimum_action_applied', v_below_minimum_action,
      'vacancies_reopened',           v_vacancies_reopened,
      'notes',                        to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── dissolve_coverage_group ─────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN

    v_employee_home_stores := COALESCE(p_request.payload -> 'employee_home_stores', '{}'::jsonb);

    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_dissolved_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

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

      IF v_remaining_store_id IS NULL THEN
        RAISE EXCEPTION
          'dissolve_coverage_group: no home store specified for employee % (%)',
          COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
          USING ERRCODE = '23514';
      END IF;

      SELECT store_name, vcode
      INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores WHERE id = v_remaining_store_id;

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

      v_employees_converted := v_employees_converted + 1;
    END LOOP;

    -- Pre-resolve position
    SELECT pos.position_name, cg.position_id
    INTO v_cg_position_name, v_cg_position_id
    FROM public.coverage_groups cg
    LEFT JOIN public.positions pos ON pos.id = cg.position_id
    WHERE cg.id = p_request.target_coverage_group_id;

    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- ── FIX (ohm#9k4p7x2a): Reopen vacancies for all dissolved stores ──
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

      v_store_group_id := COALESCE(v_store_group_id, v_cg_account_group_id);

      IF v_store_vcode IS NULL THEN
        v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy skipped'];
        CONTINUE;
      END IF;

      SELECT cg.employment_type INTO v_store_employment_type
      FROM public.coverage_groups cg WHERE cg.id = p_request.target_coverage_group_id;

      -- Retained store: skip vacancy reopen (employee still there, stationary now)
      IF v_remaining_store_id = v_store_id THEN
        CONTINUE;
      END IF;

      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_store_vcode AND slot_status <> 'archived'
      ORDER BY created_at DESC LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'open', current_occupant_plantilla_id = NULL,
            updated_at = now(), updated_by = p_actor_id
        WHERE id = v_existing_slot_id;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type, old_value, new_value,
          reason_code, performed_by, remarks, created_at
        ) VALUES (
          v_existing_slot_id, v_store_account_id, 'slot_reopened',
          'occupied', 'open', 'COVERAGE_GROUP_DISSOLVED',
          p_actor_id, 'Coverage Group dissolved; slot reopened.', now()
        );
      ELSE
        v_new_slot_id := gen_random_uuid();
        INSERT INTO public.plantilla_slots (
          id, account_id, group_id, store_id,
          position_id, employment_type, legacy_vcode,
          slot_status, created_at, updated_at, created_by
        ) VALUES (
          v_new_slot_id, v_store_account_id, v_store_group_id, v_store_id,
          v_cg_position_id, v_store_employment_type, v_store_vcode,
          'open', now(), now(), p_actor_id
        );

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type, old_value, new_value,
          reason_code, performed_by, remarks, created_at
        ) VALUES (
          v_new_slot_id, v_store_account_id, 'slot_created',
          NULL, 'open', 'COVERAGE_GROUP_DISSOLVED',
          p_actor_id, 'Coverage Group dissolved; new slot created.', now()
        );
      END IF;

      -- Reopen or create vacancy
      IF EXISTS (SELECT 1 FROM public.vacancies WHERE vcode = v_store_vcode AND deleted_at IS NULL) THEN
        UPDATE public.vacancies
        SET status = 'Open', updated_at = now()
        WHERE vcode = v_store_vcode AND deleted_at IS NULL
          AND status NOT IN ('Open', 'Pipeline');
      ELSE
        INSERT INTO public.vacancies (
          vcode, account, store_id, store_name,
          group_id, position, employment_type,
          province, area_city, status, created_at, updated_at
        ) VALUES (
          v_store_vcode, v_store_account_name, v_store_id, v_store_name_local,
          v_store_group_id, v_cg_position_name, v_store_employment_type,
          v_store_area, v_store_area, 'Open', now(), now()
        );
      END IF;

      v_vacancies_reopened := v_vacancies_reopened + 1;
    END LOOP;

    -- Archive all store edges and close all slots
    UPDATE public.coverage_group_stores
    SET archived_at = now(), archived_by = p_actor_id
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    UPDATE public.coverage_slots
    SET slot_status = 'closed', updated_at = now()
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND slot_status <> 'closed';

    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request execution: Coverage Group dissolved'
    WHERE id = p_request.target_coverage_group_id;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'dissolve_coverage_group',
      'employees_converted',          v_employees_converted,
      'vacancies_reopened',           v_vacancies_reopened,
      'group_archived',               true,
      'notes',                        to_jsonb(v_notes)
    );

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── merge_coverage_groups ───────────────────────────────────────────────────
  -- (carried forward unchanged — no bugs in this branch)
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'merge_coverage_groups'::public.request_type THEN
    RAISE EXCEPTION 'merge_coverage_groups execution not yet implemented in this version'
      USING ERRCODE = '0A000';

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── convert_stationary_to_roving ───────────────────────────────────────────
  -- (carried forward unchanged — no bugs in this branch)
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'convert_stationary_to_roving'::public.request_type THEN
    RAISE EXCEPTION 'convert_stationary_to_roving execution not yet implemented in this version'
      USING ERRCODE = '0A000';

  ELSE
    RAISE EXCEPTION '_execute_approved_coverage_request: unknown request_type %', p_request.request_type
      USING ERRCODE = '22023';
  END IF;

END;
$function$;
