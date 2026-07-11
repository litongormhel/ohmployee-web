-- ============================================================================
-- ohm#9f4k2m7x — Fix Remove Store Vacancy Snapshot and Approved Detail Display
-- Migration: 20261236000000_fix_remove_store_vacancy_snapshot.sql
--
-- Root Causes:
--
--   Bug 1 — Group missing on created vacancy:
--     stores.group_id may be NULL for some operational stores. The slot INSERT
--     uses v_store_group_id = stores.group_id. When NULL, the shadow view
--     (vw_slot_derived_vacancy_shadow) cannot JOIN ps.group_id → groups and
--     returns group_name = NULL.
--
--   Bug 2 — Position shows 'Unknown':
--     Branch A (convert_remaining_to_standalone) NULLs plantilla.coverage_group_id
--     BEFORE the FOREACH v_store_id LOOP runs its position SELECT. After Branch A,
--     the SELECT FROM plantilla WHERE coverage_group_id = target returns 0 rows,
--     so v_store_position stays NULL and COALESCE picks 'Unknown'.
--     Pure structural coverage groups (no active plantilla) also trigger this.
--
--   Bug 3 — Employment type shows raw lowercase 'stationary':
--     The slot reopen UPDATE paths (reopening existing open or closed slots) do
--     NOT update employment_type. If the existing slot was originally created with
--     employment_type = 'stationary' (lowercase, e.g. from stores.employment_type),
--     it stays lowercase. The shadow view reads ps.employment_type verbatim.
--
-- Fixes:
--
--   1. Pre-resolve group_id from coverage_groups → accounts BEFORE any loop,
--      as a fallback for stores where stores.group_id IS NULL.
--      After fetching stores.group_id, COALESCE with the pre-resolved fallback.
--
--   2. Pre-resolve position from coverage_groups → positions BEFORE Branch A
--      modifies plantilla rows. Use as fallback when plantilla SELECT returns NULL.
--
--   3. When reopening existing slots (both open-like and closed paths), also set
--      employment_type = 'Stationary' to normalize casing in existing data.
--
--   4. Enrich the notes array with the VCode of the created/reopened vacancy so
--      the Flutter UI can display it in the Approved detail card without extra
--      DB round-trips.
--
-- Supersedes 20261235000000 (which supersedes 20261233/20261234/20261232...).
-- Apply in sequence: 20261233 → 20261234 → 20261235 → 20261236.
-- ============================================================================

BEGIN;

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
    -- Used as fallback when stores.group_id IS NULL.
    SELECT a.group_id
    INTO v_cg_account_group_id
    FROM public.coverage_groups cg
    JOIN public.accounts a ON a.id = cg.account_id
    WHERE cg.id = p_request.target_coverage_group_id;

    -- ── Bug 2 fix: Pre-resolve position from coverage_groups → positions ───────
    -- Must happen BEFORE Branch A, which NULLs plantilla.coverage_group_id.
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

    -- ── Branch A: convert_remaining_to_standalone (remaining_count = 1) ────────
    -- NOTE: This nulls plantilla.coverage_group_id. Position was already
    -- pre-resolved above (v_cg_position_name / v_cg_position_id) so the
    -- FOREACH loop below still has position data.
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
    --
    -- FIX HISTORY (ohm#9f4k2m7x):
    --   Bug 1: stores.group_id may be NULL → fallback to CG account group
    --   Bug 2: position pre-resolved above; plantilla SELECT fallback added
    --   Bug 3: slot reopen UPDATE now sets employment_type = 'Stationary'
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

      -- Bug 1 fix: if stores.group_id is NULL, use the CG account's group
      v_store_group_id := COALESCE(v_store_group_id, v_cg_account_group_id);

      v_store_province_id := NULL;

      IF v_store_vcode IS NULL THEN
        v_notes := v_notes || ARRAY['store ' || v_store_id::text || ' has no vcode; vacancy not created'];
        CONTINUE;
      END IF;

      -- Resolve position from active plantilla in the group.
      -- Bug 2 fix: Branch A has already NULLed coverage_group_id on plantilla,
      -- so also try v_cg_position_name (pre-resolved above) as fallback.
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

      -- Bug 2 fix: fallback to coverage_groups.position when plantilla has none
      IF v_store_position IS NULL OR v_store_position = 'Unknown' THEN
        v_store_position   := COALESCE(v_cg_position_name, 'Unknown');
        v_store_position_id := COALESCE(v_store_position_id, v_cg_position_id);
      END IF;

      v_store_employment_type := 'Stationary';

      -- ── Step 1: Reopen existing vacancy by VCode ─────────────────────────
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

      -- ── Step 2: Create vacancy if none exists ────────────────────────────
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

      -- ── Step 3: Reopen existing plantilla_slot ───────────────────────────
      SELECT id INTO v_existing_slot_id
      FROM public.plantilla_slots
      WHERE store_id   = v_store_id
        AND account_id = v_store_account_id
        AND slot_status <> 'closed'
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_slot_id IS NOT NULL THEN
        -- Bug 3 fix: also normalize employment_type on reopen
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
          -- Bug 3 fix: also normalize employment_type on reopen
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

      -- ── Step 4: slot_history entry ───────────────────────────────────────
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
      -- Enrich notes with VCode so Flutter approved-detail card can display it
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
  -- ── dissolve_coverage_group ────────────────────════════════════════════════
  -- ════════════════════════════════════════════════════════════════════════════
  ELSIF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN
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
        archive_reason = 'Coverage Request execution: dissolved'
    WHERE id = p_request.target_coverage_group_id;

    FOR v_pl IN (
      SELECT * FROM public.plantilla
      WHERE coverage_group_id = p_request.target_coverage_group_id
        AND status = 'Active'
        AND is_deleted = false
        AND is_archived = false
    ) LOOP
      UPDATE public.plantilla
      SET status = 'Inactive', coverage_group_id = NULL, coverage_slot_id = NULL
      WHERE id = v_pl.id;

      IF v_pl.source_employee_import_batch_id IS NOT NULL
        OR v_pl.source_baseline_import_batch_id IS NOT NULL
      THEN
        UPDATE public.employee_store_allocations
        SET is_active = false, effective_end = CURRENT_DATE
        WHERE plantilla_id = v_pl.id AND is_active = true;
      ELSE
        UPDATE public.plantilla_store_links
        SET status = 'Resigned', deleted_at = now()
        WHERE plantilla_id = v_pl.id AND deleted_at IS NULL;
      END IF;
    END LOOP;

    RETURN jsonb_build_object(
      'structural_execution_enabled',  true,
      'request_type',                  'dissolve_coverage_group',
      'stores_added',                  0,
      'stores_removed',                0,
      'group_archived',                true,
      'notes',                         to_jsonb(ARRAY['group dissolved; employees marked inactive'])
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
  'ohm#9f4k2m7x: Bug 1 — group_id fallback from CG account when stores.group_id IS NULL. '
  'Bug 2 — position pre-resolved from coverage_groups → positions before Branch A. '
  'Bug 3 — employment_type = ''Stationary'' set on slot reopen UPDATEs (not only INSERT). '
  'Notes enriched with store_name|vcode|account for Flutter approved-detail display. '
  'ohm#c7k9f2a1c: pl.employment_type → ''Stationary'' (plantilla has no employment_type). '
  'ohm#c7k9f2a1b: s.province_id → NULL (stores has no province_id). '
  'ohm#c7k9f2a1: s.area_name → COALESCE(s.area_city, s.area_province, ''''). '
  'ohm#25f6a6ra: payload.store_ids = stores to REMOVE (corrected semantics). '
  'Supersedes 20261230000000–20261235000000.';

NOTIFY pgrst, 'reload schema';

-- ── Sanity check queries (run manually after applying) ──────────────────────
/*
  -- 1. Approve a remove_store request and confirm no runtime errors
  SELECT approve_coverage_request('<pending_remove_store_uuid>', 'Test approval');

  -- 2. Confirm vacancy created with correct position (not 'Unknown')
  SELECT vcode, position, status, store_name FROM vacancies
  WHERE vcode = '<store_vcode>' AND status = 'Open';
  -- Expected: position = actual position name (not 'Unknown')

  -- 3. Confirm slot has group_id populated and employment_type = 'Stationary'
  SELECT id, slot_status, group_id, employment_type, is_roving FROM plantilla_slots
  WHERE store_id = '<removed_store_uuid>' AND slot_status = 'open';
  -- Expected: group_id IS NOT NULL, employment_type = 'Stationary', is_roving = false

  -- 4. Confirm vacancy shadow view shows group_name
  SELECT vcode, group_name, employment_type, position FROM vw_slot_derived_vacancy_shadow
  WHERE legacy_vcode = '<store_vcode>';
  -- Expected: group_name IS NOT NULL, employment_type = 'Stationary'

  -- 5. Confirm no s.area_name regression (should not error)
  SELECT approve_coverage_request('<any_remove_store_uuid>', 'Regression check');

  -- 6. Confirm notes contain enriched store info
  SELECT execution_summary->'notes' FROM coverage_requests
  WHERE id = '<approved_request_uuid>';
  -- Expected: ["store_removed:SM AURORA|vcode:ONE-00001|account:ONE"]
*/

COMMIT;
