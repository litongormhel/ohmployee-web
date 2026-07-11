-- ============================================================================
-- ohm#25f6a6r9 — Fix Remove Store Approval Auto-Conversion Below Minimum Rule
-- Migration: 20261231000000_fix_remove_store_auto_convert.sql
--
-- Root Cause:
--   _execute_approved_coverage_request required payload.below_minimum_action
--   for remove_store requests that leave < 2 stores. The Flutter frontend
--   never sends this field. convert_roving_to_stationary already auto-injects
--   the value, but remove_store did not.
--
-- Fix:
--   Auto-compute the correct action during execution based on remaining_count:
--     remaining_count >= 2  → remove stores, keep group active (no change)
--     remaining_count == 1  → auto-convert remaining store to Stationary,
--                             archive group (was: require payload field)
--     remaining_count == 0  → RAISE EXCEPTION with clear dissolve hint
--
--   payload.below_minimum_action is kept in the allowed-keys list for
--   backward compatibility (existing smoke tests still send it) but its
--   value is now IGNORED at execution time.
--
-- Applies equally to:
--   - Normal HC-created coverage groups
--   - Imported roving groups (normalized via fn_normalize_imported_roving_group)
-- ============================================================================

BEGIN;

-- ── Re-implement Execution Engine (remove_store auto-conversion fix) ─────────
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
  v_store_ids              uuid[];
  v_replacement_store_ids  uuid[];
  v_removed_store_ids      uuid[];
  v_store_id               uuid;
  v_remaining_count        integer;
  v_blocking_slot_count    integer;
  v_below_minimum_action   text;
  v_existing_cg_code       text;
  v_anchor_removed         boolean := false;
  v_stores_added           integer := 0;
  v_stores_removed         integer := 0;
  v_group_archived         boolean := false;
  v_notes                  text[]  := ARRAY[]::text[];
  v_pl                     record;
  v_active_allocs          integer;
  v_remaining_store_id     uuid;
  v_remaining_store_name   text;
  v_remaining_store_vcode  text;
BEGIN
  -- ── add_store ─────────────────────────────────────────────────────────────
  IF p_request.request_type = 'add_store'::public.request_type THEN
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

    FOREACH v_store_id IN ARRAY v_store_ids LOOP
      -- Overlap guard: store must not be active in another CG under same account.
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

      -- Check not already in this group (unique index would block it, but give a clear message).
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
        coverage_group_id,
        store_id,
        is_anchor,
        added_by
      ) VALUES (
        p_request.target_coverage_group_id,
        v_store_id,
        false,
        p_actor_id
      );
      v_stores_added := v_stores_added + 1;

      -- Sync for imported roving employees if they exist
      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL OR v_pl.source_baseline_import_batch_id IS NOT NULL THEN
          -- Check if active allocation exists, if not, insert it
          IF NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations
            WHERE plantilla_id = v_pl.id AND store_id = v_store_id AND is_active = true
          ) THEN
            SELECT store_name, vcode INTO v_remaining_store_name, v_remaining_store_vcode
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

    -- Recalculate fractions for imported employees
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      IF v_pl.source_employee_import_batch_id IS NOT NULL OR v_pl.source_baseline_import_batch_id IS NOT NULL THEN
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

  -- ── remove_store ────────────────────────────────────────────────────────────
  --
  --   AUTO-CONVERSION RULE (ohm#25f6a6r9):
  --   payload.below_minimum_action is no longer required for remove_store.
  --   The correct action is auto-computed from remaining_count:
  --
  --     remaining_count >= 2  → remove selected stores, keep group active
  --     remaining_count == 1  → remove selected stores, convert remaining
  --                             store to Stationary, archive group
  --     remaining_count == 0  → REJECT (use dissolve_coverage_group instead)
  --
  --   For convert_roving_to_stationary the behavior is unchanged:
  --   it still implicitly uses 'convert_remaining_to_standalone'.
  --
  ELSIF p_request.request_type = 'remove_store'::public.request_type
     OR p_request.request_type = 'convert_roving_to_stationary'::public.request_type
  THEN
    -- v_store_ids contains the stores to KEEP (from payload.store_ids)
    v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

    -- Find the stores to REMOVE
    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_removed_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL
      AND NOT (store_id = ANY (v_store_ids));

    v_remaining_count := COALESCE(array_length(v_store_ids, 1), 0);

    -- ── Branch: below-minimum handling ──────────────────────────────────────
    IF v_remaining_count < 2 THEN

      -- convert_roving_to_stationary always converts the remaining store.
      IF p_request.request_type = 'convert_roving_to_stationary'::public.request_type THEN
        v_below_minimum_action := 'convert_remaining_to_standalone';

      -- remove_store: auto-compute action based on remaining_count.
      -- payload.below_minimum_action is intentionally IGNORED here (ohm#25f6a6r9).
      ELSIF v_remaining_count = 0 THEN
        -- All stores removed via remove_store → hard block; use dissolve instead.
        RAISE EXCEPTION
          'remove_store would leave 0 active stores in coverage group; '
          'use dissolve_coverage_group to fully dissolve the group'
          USING ERRCODE = '23514';

      ELSE
        -- remaining_count = 1 → auto-convert remaining store to Stationary.
        v_below_minimum_action := 'convert_remaining_to_standalone';
      END IF;

      -- ── Execute: convert_remaining_to_standalone ─────────────────────────
      IF v_below_minimum_action = 'convert_remaining_to_standalone' THEN
        -- Exactly 1 store remains → convert employees to Stationary
        v_remaining_store_id := v_store_ids[1];
        SELECT store_name, vcode INTO v_remaining_store_name, v_remaining_store_vcode
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
          -- Convert employee to Stationary
          UPDATE public.plantilla
          SET deployment_type = 'Stationary',
              coverage_group_id = NULL,
              coverage_slot_id = NULL,
              store_id = v_remaining_store_id,
              store_name = v_remaining_store_name,
              vcode = v_remaining_store_vcode
          WHERE id = v_pl.id;

          IF v_pl.source_employee_import_batch_id IS NOT NULL OR v_pl.source_baseline_import_batch_id IS NOT NULL THEN
            -- Imported employee: deactivate roving allocations and insert stationary allocation
            UPDATE public.employee_store_allocations
            SET is_active = false,
                effective_end = CURRENT_DATE
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
            -- Live employee: deactivate all links (plantilla update trigger will sync allocations)
            UPDATE public.plantilla_store_links
            SET status = 'Resigned',
                deleted_at = now()
            WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
          END IF;
        END LOOP;

        -- Archive remaining store edge
        UPDATE public.coverage_group_stores
        SET archived_at = now(),
            archived_by = p_actor_id
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND store_id = v_remaining_store_id
          AND archived_at IS NULL;

        -- Close slots
        UPDATE public.coverage_slots
        SET slot_status = 'closed',
            updated_at  = now()
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND slot_status <> 'closed';

        -- Archive group
        UPDATE public.coverage_groups
        SET archived_at    = now(),
            archived_by    = p_actor_id,
            archive_reason = 'Coverage Request execution: converted remaining store to standalone'
        WHERE id = p_request.target_coverage_group_id;

        v_group_archived := true;
        v_notes := v_notes || ARRAY['remaining store converted to standalone; group archived'];

      END IF; -- convert_remaining_to_standalone

    END IF; -- remaining_count < 2

    -- Check if anchor is being removed (for logging/reporting only)
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

    -- Skip removal if the group was already archived above
    IF NOT v_group_archived THEN
      -- Archive removed store edges
      UPDATE public.coverage_group_stores
      SET archived_at = now(),
          archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at IS NULL;

      GET DIAGNOSTICS v_stores_removed = ROW_COUNT;

      -- Sync for all employees in the group
      FOR v_pl IN (
        SELECT * FROM public.plantilla
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND status = 'Active'
          AND is_deleted = false
          AND is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL OR v_pl.source_baseline_import_batch_id IS NOT NULL THEN
          -- Deactivate allocations for removed stores
          UPDATE public.employee_store_allocations
          SET is_active = false,
              effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND is_active = true;

          -- Re-calculate fractions for remaining allocations
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
          -- Live employee: update plantilla_store_links (will trigger sync)
          UPDATE public.plantilla_store_links
          SET status = 'Resigned',
              deleted_at = now()
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND deleted_at IS NULL;
        END IF;
      END LOOP;
    END IF;

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  p_request.request_type,
      'stores_added',                  v_stores_added,
      'stores_removed',                v_stores_removed,
      'group_archived',                v_group_archived,
      'anchor_removed',                v_anchor_removed,
      'below_minimum_action_applied',  v_below_minimum_action,
      'notes',                         to_jsonb(v_notes)
    );

  -- ── dissolve_coverage_group ────────────────────────────────────────────────
  ELSIF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN
    -- Archive all store edges
    UPDATE public.coverage_group_stores
    SET archived_at = now(),
        archived_by = p_actor_id
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    -- Close all slots
    UPDATE public.coverage_slots
    SET slot_status = 'closed',
        updated_at  = now()
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND slot_status <> 'closed';

    -- Archive group
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request execution: dissolved'
    WHERE id = p_request.target_coverage_group_id;

    -- Update employees in group
    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      UPDATE public.plantilla
      SET status = 'Inactive',
          coverage_group_id = NULL,
          coverage_slot_id = NULL
      WHERE id = v_pl.id;

      IF v_pl.source_employee_import_batch_id IS NOT NULL OR v_pl.source_baseline_import_batch_id IS NOT NULL THEN
        UPDATE public.employee_store_allocations
        SET is_active = false,
            effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;
      ELSE
        UPDATE public.plantilla_store_links
        SET status = 'Resigned',
            deleted_at = now()
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
      END IF;
    END LOOP;

    v_group_archived := true;

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  'dissolve_coverage_group',
      'stores_added',                  0,
      'stores_removed',                0,
      'group_archived',                true,
      'notes',                         to_jsonb(ARRAY['group dissolved and employees marked inactive'])
    );

  -- ── Deferred types (status-only) ──────────────────────────────────────────
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
  'ohm#25f6a6r9: Auto-converts remaining store to Stationary when remove_store leaves exactly 1 store. '
  'payload.below_minimum_action is no longer required; the action is computed from remaining_count. '
  'Applies equally to normal HC-created groups and imported roving groups.';

COMMIT;
