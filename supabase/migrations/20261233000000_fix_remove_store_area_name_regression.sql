-- ============================================================================
-- ohm#c7k9f2a1 — Fix Coverage Remove Store Approval s.area_name SQL Regression
-- Migration: 20261233000000_fix_remove_store_area_name_regression.sql
--
-- Root Cause:
--   _execute_approved_coverage_request (introduced in 20261232000000) fetches
--   store details in the remove_store vacancy-reopening FOREACH loop using:
--
--     COALESCE(s.area_city, s.area_name, '') AS area_name
--
--   The `stores` table has `area_city` and `area_province`, but NO `area_name`
--   column. (`area_name` lives on `vacancies`, not `stores`.)
--
--   PL/pgSQL compiles function bodies at first call, not at CREATE time, so
--   the migration applied cleanly but raises PostgrestException 42703
--   ("column s.area_name does not exist") on the first approve_coverage_request
--   call for any remove_store request.
--
-- Fix:
--   Replace the stale fallback:
--     COALESCE(s.area_city, s.area_name, '') AS area_name
--   with the correct stores-table column:
--     COALESCE(s.area_city, s.area_province, '') AS area_name
--
-- Scope: _execute_approved_coverage_request only.
--   approve_coverage_request, reject_coverage_request, and all other
--   Coverage Request RPCs are untouched.
--   Coverage Request creation behavior is untouched.
--   Coverage Group behavior is untouched.
--
-- Smoke Tests (see §3):
--   A. pending remove_store request can be approved with no 42703 error
--   B. removed store is archived in coverage_group_stores
--   C. vacancy slot is reopened or created for the removed store
--   D. COVERAGE_STORE_REMOVED slot_history entry is written
-- ============================================================================

BEGIN;

-- ── §1. Fix _execute_approved_coverage_request ───────────────────────────────
--
--   Only the COALESCE(s.area_city, s.area_name, ...) line changes.
--   All other logic is identical to 20261232000000.
--
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
  v_store                  record;

  -- ── remove_store semantics (corrected)
  v_removed_store_ids      uuid[];   -- stores to REMOVE (from payload.store_ids)
  v_remaining_store_ids    uuid[];   -- stores that remain after removal
  v_remaining_count        integer;

  -- ── add_store / replacement (unchanged)
  v_store_ids              uuid[];   -- for add_store: stores to ADD
  v_replacement_store_ids  uuid[];

  -- ── below-minimum handling
  v_below_minimum_action   text;

  -- ── reporting / counters
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
  v_existing_vacancy_id    uuid;
  v_rows_updated           integer;
  v_store_account_id       uuid;
  v_store_group_id         uuid;
  v_store_vcode            text;
  v_store_name_local       text;
  v_store_account_name     text;
  v_store_position         text;
  v_store_employment_type  text;
  v_store_position_id      uuid;
  v_store_province_id      uuid;
  v_store_area             text;
  v_store_chain_id         uuid;
BEGIN

  -- ════════════════════════════════════════════════════════════════════════════
  -- ── add_store ───────────────────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
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

      -- Sync for imported roving employees
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


  -- ════════════════════════════════════════════════════════════════════════════
  -- ── remove_store / convert_roving_to_stationary ─────────────────────────────
  --
  --   SEMANTICS (ohm#25f6a6ra — CORRECTED):
  --     payload.store_ids  = stores to REMOVE  (user selected for removal)
  --     v_removed_store_ids = payload.store_ids
  --     v_remaining_store_ids = active CG stores NOT in v_removed_store_ids
  --     v_remaining_count   = len(v_remaining_store_ids)
  --
  --   AUTO-CONVERSION RULE:
  --     remaining_count >= 2  → remove selected, group stays active
  --     remaining_count == 1  → remove selected, convert remaining to Stationary,
  --                             archive group
  --     remaining_count == 0  → REJECT (use dissolve_coverage_group)
  --
  --   VACANCY REOPENING (slot-first architecture):
  --     For each removed store:
  --       1. Reopen existing open vacancy by VCode (stores.vcode)
  --       2. If no open vacancy, create one (vacancy_type = 'Backfill', status = 'Open')
  --       3. Reopen existing plantilla_slot for store, or create new one
  --       4. Write slot_history entry (reason COVERAGE_STORE_REMOVED)
  --
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'remove_store'::public.request_type
     OR p_request.request_type = 'convert_roving_to_stationary'::public.request_type
  THEN

    -- ── Resolve: which stores are being REMOVED ──────────────────────────────
    -- For remove_store: payload.store_ids = stores to REMOVE (corrected semantics)
    -- For convert_roving_to_stationary: all CG stores are being removed (convert all)
    IF p_request.request_type = 'convert_roving_to_stationary'::public.request_type THEN
      -- All current CG stores except the one to keep (store_ids = keep list)
      -- For convert_roving: payload.store_ids = the ONE store that becomes the stationary home.
      -- All OTHER stores are removed.
      v_remaining_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);
      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_removed_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_remaining_store_ids));
      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);
      v_below_minimum_action := 'convert_remaining_to_standalone';
    ELSE
      -- remove_store: payload.store_ids = stores to REMOVE (corrected semantics)
      v_removed_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', true);

      -- Validate: all removed stores must be active members of the group
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

      -- Compute remaining stores (NOT in removal list)
      SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_remaining_store_ids
      FROM public.coverage_group_stores
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND archived_at IS NULL
        AND NOT (store_id = ANY (v_removed_store_ids));

      v_remaining_count := COALESCE(array_length(v_remaining_store_ids, 1), 0);

      -- Auto-compute action from remaining_count
      IF v_remaining_count = 0 THEN
        RAISE EXCEPTION
          'remove_store would leave 0 active stores in coverage group; '
          'use dissolve_coverage_group to fully dissolve the group'
          USING ERRCODE = '23514';
      ELSIF v_remaining_count = 1 THEN
        v_below_minimum_action := 'convert_remaining_to_standalone';
      ELSE
        v_below_minimum_action := NULL; -- normal multi-store removal
      END IF;
    END IF;

    -- ── Check if anchor is being removed (for reporting only) ───────────────
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
    -- ── Branch A: convert_remaining_to_standalone (remaining_count = 1) ────
    -- ════════════════════════════════════════════════════════════════════════
    IF v_below_minimum_action = 'convert_remaining_to_standalone' THEN
      v_remaining_store_id := v_remaining_store_ids[1];
      SELECT store_name, vcode INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores WHERE id = v_remaining_store_id;

      -- Convert each employee in the group to Stationary
      FOR v_pl IN (
        SELECT pl.*, a.group_id
        FROM public.plantilla pl
        JOIN public.accounts a ON a.id = pl.account_id
        WHERE pl.coverage_group_id = p_request.target_coverage_group_id
          AND pl.status = 'Active'
          AND pl.is_deleted = false
          AND pl.is_archived = false
      ) LOOP
        -- Update plantilla → Stationary, pointing to the remaining store
        UPDATE public.plantilla
        SET deployment_type    = 'Stationary',
            coverage_group_id  = NULL,
            coverage_slot_id   = NULL,
            store_id           = v_remaining_store_id,
            store_name         = v_remaining_store_name,
            vcode              = v_remaining_store_vcode
        WHERE id = v_pl.id;

        IF v_pl.source_employee_import_batch_id IS NOT NULL OR v_pl.source_baseline_import_batch_id IS NOT NULL THEN
          -- Imported employee: deactivate roving allocations and insert stationary one
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
          -- Live employee: mark all store links as Resigned
          UPDATE public.plantilla_store_links
          SET status = 'Resigned',
              deleted_at = now()
          WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
        END IF;
      END LOOP;

      -- Archive remaining store edge (now stationary → no longer in CG)
      UPDATE public.coverage_group_stores
      SET archived_at = now(),
          archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = v_remaining_store_id
        AND archived_at IS NULL;

      -- Close all coverage slots for this group
      UPDATE public.coverage_slots
      SET slot_status = 'closed',
          updated_at  = now()
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND slot_status <> 'closed';

      -- Archive the group
      UPDATE public.coverage_groups
      SET archived_at    = now(),
          archived_by    = p_actor_id,
          archive_reason = 'Coverage Request execution: converted remaining store to standalone'
      WHERE id = p_request.target_coverage_group_id;

      v_group_archived := true;
      v_notes := v_notes || ARRAY['remaining store converted to standalone; group archived'];
    END IF; -- convert_remaining_to_standalone

    -- ════════════════════════════════════════════════════════════════════════
    -- ── Archive removed store edges + employee sync ─────────────────────────
    -- ════════════════════════════════════════════════════════════════════════
    IF NOT v_group_archived THEN
      -- Archive coverage_group_stores edges for removed stores
      UPDATE public.coverage_group_stores
      SET archived_at = now(),
          archived_by = p_actor_id
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND store_id = ANY (v_removed_store_ids)
        AND archived_at IS NULL;

      GET DIAGNOSTICS v_stores_removed = ROW_COUNT;

      -- Sync employee allocations for each removed store
      FOR v_pl IN (
        SELECT * FROM public.plantilla
        WHERE coverage_group_id = p_request.target_coverage_group_id
          AND status = 'Active'
          AND is_deleted = false
          AND is_archived = false
      ) LOOP
        IF v_pl.source_employee_import_batch_id IS NOT NULL OR v_pl.source_baseline_import_batch_id IS NOT NULL THEN
          -- Imported employee: deactivate allocations for removed stores
          UPDATE public.employee_store_allocations
          SET is_active = false,
              effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND is_active = true;

          -- Recalculate fractions for remaining allocations
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
          -- Live employee: mark store links for removed stores as Resigned
          UPDATE public.plantilla_store_links
          SET status = 'Resigned',
              deleted_at = now()
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND deleted_at IS NULL;
        END IF;
      END LOOP;
    END IF;

    -- ════════════════════════════════════════════════════════════════════════
    -- ── Vacancy Slot Reopening for each removed store ───────────────────────
    --    Slot-first architecture: reopen or create plantilla_slot + vacancy.
    --    VCode reuse: use stores.vcode — do NOT generate a new VCode if one exists.
    --    This runs for ALL removed stores regardless of group_archived status.
    -- ════════════════════════════════════════════════════════════════════════
    FOREACH v_store_id IN ARRAY v_removed_store_ids LOOP
      -- Fetch store details
      -- FIX ohm#c7k9f2a1: stores has area_city / area_province, NOT area_name.
      -- area_name lives on vacancies. Fallback chain: area_city → area_province → ''.
      SELECT
        s.store_name,
        s.vcode,
        s.account_id,
        s.group_id,
        a.account_name,
        COALESCE(s.area_city, s.area_province, '') AS area_name,
        s.province_id
      INTO
        v_store_name_local,
        v_store_vcode,
        v_store_account_id,
        v_store_group_id,
        v_store_account_name,
        v_store_area,
        v_store_province_id
      FROM public.stores s
      LEFT JOIN public.accounts a ON a.id = s.account_id
      WHERE s.id = v_store_id;

      IF v_store_vcode IS NULL THEN
        -- Store has no VCode — skip vacancy creation (edge case, not slot-eligible)
        v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
        CONTINUE;
      END IF;

      -- ── Resolve position / employment type from any active plantilla in the group
      SELECT
        COALESCE(pl.position, 'Unknown'),
        COALESCE(pl.employment_type, 'Regular'),
        pl.position_id,
        pl.chain_id
      INTO
        v_store_position,
        v_store_employment_type,
        v_store_position_id,
        v_store_chain_id
      FROM public.plantilla pl
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.is_deleted = false
        AND pl.is_archived = false
      LIMIT 1;

      -- ── Step 1: Reopen existing Open/closed vacancy by VCode ─────────────
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

      -- ── Step 2: If no vacancy exists for this VCode, create one ──────────
      IF v_rows_updated = 0 THEN
        INSERT INTO public.vacancies (
          vcode,
          account,
          position,
          account_id,
          chain_id,
          store_id,
          province_id,
          area_name,
          position_id,
          vacant_date,
          vacancy_type,
          status,
          source_plantilla_id,
          store_name,
          created_at,
          updated_at,
          required_headcount
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
          NULL, -- NULL to avoid uq_vacancy_source_plantilla conflict
          v_store_name_local,
          now(),
          now(),
          1
        )
        ON CONFLICT DO NOTHING;
      END IF;

      -- ── Step 3: Reopen existing plantilla_slot for this store ─────────────
      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE store_id  = v_store_id
        AND account_id = v_store_account_id
        AND slot_status <> 'closed'
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        -- Slot exists in an open-like state → update reason, reset occupant
        UPDATE public.plantilla_slots
        SET slot_status                  = 'open',
            current_occupant_plantilla_id = NULL,
            closed_at                     = NULL,
            closed_by                     = NULL,
            closure_reason_code           = NULL,
            updated_at                    = now(),
            updated_by                    = p_actor_id
        WHERE id = v_existing_slot_id;

        v_new_slot_id := v_existing_slot_id;
      ELSE
        -- Check for a closed slot to reopen
        SELECT id INTO v_existing_slot_id
        FROM public.plantilla_slots
        WHERE store_id   = v_store_id
          AND account_id = v_store_account_id
          AND slot_status = 'closed'
        ORDER BY updated_at DESC
        LIMIT 1;

        IF v_existing_slot_id IS NOT NULL THEN
          -- Reopen the most recently closed slot
          UPDATE public.plantilla_slots
          SET slot_status                   = 'open',
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
          -- No slot exists for this store → create a new one
          v_new_slot_id := gen_random_uuid();
          INSERT INTO public.plantilla_slots (
            id,
            store_id,
            account_id,
            group_id,
            position,
            employment_type,
            is_roving,
            slot_status,
            legacy_vcode,
            created_by,
            updated_by,
            created_at,
            updated_at
          ) VALUES (
            v_new_slot_id,
            v_store_id,
            v_store_account_id,
            v_store_group_id,
            COALESCE(v_store_position, 'Unknown'),
            COALESCE(v_store_employment_type, 'Regular'),
            false, -- stationary slot
            'open',
            v_store_vcode,
            p_actor_id,
            p_actor_id,
            now(),
            now()
          );
        END IF;
      END IF;

      -- ── Step 4: Write slot_history entry ─────────────────────────────────
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
      v_notes := v_notes || ARRAY['store removed and vacancy reopened: ' || COALESCE(v_store_name_local, v_store_id::text)];
    END LOOP; -- foreach removed store

    -- Correct v_stores_removed to actual archived CG store count
    -- (the loop above also counts per-store; reset from actual archival)
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
  -- ── dissolve_coverage_group ────────────────────────────────────────────────
  -- ════════════════════════════════════════════════════════════════════════════
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

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  'dissolve_coverage_group',
      'stores_added',                  0,
      'stores_removed',                0,
      'group_archived',                true,
      'notes',                         to_jsonb(ARRAY['group dissolved and employees marked inactive'])
    );


  -- ── Deferred types (status-only) ────────────────────────────────────────────
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
  'ohm#c7k9f2a1: Fix s.area_name regression — stores has area_city/area_province, not area_name. '
  'Fallback chain: COALESCE(s.area_city, s.area_province, '''') as area_name. '
  'ohm#25f6a6ra: remove_store semantics — payload.store_ids = stores to REMOVE (not keep). '
  'Reopens or creates vacancy slot for each removed store (slot-first, VCode reuse). '
  'Writes slot_history with COVERAGE_STORE_REMOVED reason. '
  'Auto-converts to Stationary if remaining_count = 1. '
  'Supersedes 20261230000000, 20261231000000, and 20261232000000 remove_store branches.';


-- ── §2. Signal PostgREST schema cache reload ─────────────────────────────────
NOTIFY pgrst, 'reload schema';


-- ── §3. Smoke test comments (run manually against linked DB) ─────────────────
/*
-- A. Verify function compiles (no 42703 at parse/plan time):
--    SELECT public._execute_approved_coverage_request(
--      (SELECT * FROM coverage_requests WHERE request_type = 'remove_store' AND status = 'pending' LIMIT 1),
--      auth.uid(), 'Test Actor', 'headAdmin'
--    );
--    Expected: returns jsonb with structural_execution_enabled = true, no error.

-- B. Verify removed store is archived:
--    SELECT archived_at FROM coverage_group_stores
--    WHERE coverage_group_id = <target_cg_id>
--      AND store_id = ANY (<removed_store_ids>);
--    Expected: archived_at IS NOT NULL for each removed store.

-- C. Verify vacancy slot reopened or created:
--    SELECT id, slot_status FROM plantilla_slots
--    WHERE store_id = ANY (<removed_store_ids>)
--    ORDER BY updated_at DESC LIMIT 5;
--    Expected: slot_status = 'open' for each removed store's slot.

-- D. Verify slot_history COVERAGE_STORE_REMOVED entry:
--    SELECT reason_code, action_type, created_at FROM slot_history
--    WHERE reason_code = 'COVERAGE_STORE_REMOVED'
--    ORDER BY created_at DESC LIMIT 5;
--    Expected: one row per removed store with reason_code = 'COVERAGE_STORE_REMOVED'.

-- E. Verify no s.area_name error:
--    Full approve flow: SELECT approve_coverage_request(<pending_remove_store_id>, 'Approved.');
--    Expected: returns jsonb with approved status, no 42703 error.
*/

COMMIT;
