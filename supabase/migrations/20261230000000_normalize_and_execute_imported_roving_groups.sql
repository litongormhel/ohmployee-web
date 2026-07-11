-- ============================================================================
-- OHM2026_0103 — Treat Imported Roving Groups and HC Coverage Groups Equally
-- Migration: 20261230000000_normalize_and_execute_imported_roving_groups.sql
-- ============================================================================

BEGIN;

-- ── 1. Create Normalization Helper ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_normalize_imported_roving_group(
  p_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_irg record;
  v_pl record;
  v_esa record;
  v_pos_id uuid;
  v_slot_id uuid;
  v_anchor_store_id uuid;
BEGIN
  -- Check if the ID exists in import_roving_groups and NOT in coverage_groups
  SELECT * INTO v_irg
  FROM public.import_roving_groups
  WHERE id = p_id;

  IF v_irg.id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.coverage_groups WHERE id = p_id
  ) THEN
    -- Get employee details from plantilla
    SELECT * INTO v_pl
    FROM public.plantilla
    WHERE id = v_irg.plantilla_id;

    IF v_pl.id IS NULL THEN
      RAISE EXCEPTION 'plantilla employee not found for imported roving group' USING ERRCODE = 'P0002';
    END IF;

    -- Resolve position_id
    v_pos_id := v_pl.position_id;
    IF v_pos_id IS NULL THEN
      SELECT id INTO v_pos_id FROM public.positions WHERE position_name = v_pl.position LIMIT 1;
      IF v_pos_id IS NULL THEN
        RAISE EXCEPTION 'position % not found in database', v_pl.position USING ERRCODE = 'P0002';
      END IF;
    END IF;

    -- Insert into coverage_groups (satisfying constraints and matching import data)
    INSERT INTO public.coverage_groups (
      id,
      coverage_code,
      account_id,
      position_id,
      employment_type,
      required_headcount,
      status,
      area_name,
      created_at,
      created_by
    ) VALUES (
      v_irg.id,
      'CG-' || v_irg.employee_no,
      v_irg.account_id,
      v_pos_id,
      'Roving',
      1,
      'active',
      v_pl.area,
      v_irg.created_at,
      v_irg.created_by
    );

    -- Insert member stores into coverage_group_stores from active allocations
    FOR v_esa IN (
      SELECT DISTINCT store_id, store_name, created_at
      FROM public.employee_store_allocations
      WHERE roving_group_id = v_irg.id
        AND is_active = true
        AND effective_end IS NULL
    ) LOOP
      IF EXISTS (
        SELECT 1 FROM public.stores
        WHERE id = v_esa.store_id
          AND is_active = true
          AND lower(COALESCE(status, 'active')) <> 'archived'
      ) THEN
        INSERT INTO public.coverage_group_stores (
          coverage_group_id,
          store_id,
          is_anchor,
          added_at
        ) VALUES (
          v_irg.id,
          v_esa.store_id,
          COALESCE(v_esa.store_id = v_pl.store_id, false),
          COALESCE(v_esa.created_at, now())
        ) ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;

    -- Guarantee exactly one active anchor store
    IF EXISTS (
      SELECT 1 FROM public.coverage_group_stores WHERE coverage_group_id = v_irg.id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.coverage_group_stores WHERE coverage_group_id = v_irg.id AND is_anchor = true
    ) THEN
      UPDATE public.coverage_group_stores
      SET is_anchor = true
      WHERE id = (
        SELECT id FROM public.coverage_group_stores
        WHERE coverage_group_id = v_irg.id
        ORDER BY store_id ASC
        LIMIT 1
      );
    END IF;

    -- Create 1 active coverage slot
    v_slot_id := gen_random_uuid();
    INSERT INTO public.coverage_slots (
      id,
      coverage_group_id,
      slot_ordinal,
      slot_status,
      created_at,
      updated_at
    ) VALUES (
      v_slot_id,
      v_irg.id,
      1,
      'active',
      v_irg.created_at,
      v_irg.updated_at
    );

    -- Link plantilla employee to the newly created coverage group and slot
    UPDATE public.plantilla
    SET coverage_group_id = v_irg.id,
        coverage_slot_id = v_slot_id
    WHERE id = v_irg.plantilla_id;

    -- Soft-archive/deactivate the import roving group so it doesn't duplicate in vw_coverage_group_shadow
    UPDATE public.import_roving_groups
    SET archived_at = now()
    WHERE id = v_irg.id;

  END IF;
END;
$fn$;

COMMENT ON FUNCTION public.fn_normalize_imported_roving_group(uuid) IS
  'OHM2026_0103: Normalizes an imported roving group from import_roving_groups into real coverage_groups and coverage_slots.';

GRANT EXECUTE ON FUNCTION public.fn_normalize_imported_roving_group(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_normalize_imported_roving_group(uuid) TO service_role;


-- ── 2. Update Payload Validation to Auto-Normalize ─────────────────────────
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

  -- Auto-normalize target, source, and destination groups if they are imported roving groups
  IF p_target_coverage_group_id IS NOT NULL THEN
    PERFORM public.fn_normalize_imported_roving_group(p_target_coverage_group_id);
  END IF;
  IF p_source_coverage_group_id IS NOT NULL THEN
    PERFORM public.fn_normalize_imported_roving_group(p_source_coverage_group_id);
  END IF;
  IF p_destination_coverage_group_id IS NOT NULL THEN
    PERFORM public.fn_normalize_imported_roving_group(p_destination_coverage_group_id);
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

    IF v_source_account_id IS NULL THEN
      RAISE EXCEPTION 'source coverage group not found or archived'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF p_destination_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_destination_account_id
    FROM public.coverage_groups
    WHERE id = p_destination_coverage_group_id
      AND archived_at IS NULL;

    IF v_destination_account_id IS NULL THEN
      RAISE EXCEPTION 'destination coverage group not found or archived'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  v_effective_account_id := COALESCE(
    p_account_id,
    v_target_account_id,
    v_source_account_id,
    v_destination_account_id
  );

  IF v_effective_account_id IS NOT NULL
     AND NOT public.i_have_full_access()
     AND NOT (v_effective_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: account is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF p_request_type = 'create_coverage_group'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload,
      ARRAY['store_ids', 'anchor_store_id', 'area_name', 'proposed_name', 'notes']
    );

    IF p_account_id IS NULL OR p_position_id IS NULL OR NULLIF(TRIM(COALESCE(p_employment_type, '')), '') IS NULL THEN
      RAISE EXCEPTION 'create_coverage_group requires account_id, position_id, and employment_type'
        USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = p_account_id) THEN
      RAISE EXCEPTION 'account not found' USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.positions WHERE id = p_position_id) THEN
      RAISE EXCEPTION 'position not found' USING ERRCODE = 'P0002';
    END IF;

    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    IF jsonb_typeof(p_payload -> 'anchor_store_id') IS DISTINCT FROM 'string'
       OR NOT ((p_payload ->> 'anchor_store_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') THEN
      RAISE EXCEPTION 'payload.anchor_store_id must be a uuid string'
        USING ERRCODE = '22023';
    END IF;

    v_anchor_store_id := (p_payload ->> 'anchor_store_id')::uuid;

    IF NOT (v_anchor_store_id = ANY (v_store_ids)) THEN
      RAISE EXCEPTION 'payload.anchor_store_id must be one of payload.store_ids'
        USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM unnest(v_store_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.stores s
        WHERE s.id = sid
          AND s.account_id = p_account_id
          AND COALESCE(s.is_active, true) = true
      )
    ) THEN
      RAISE EXCEPTION 'all payload.store_ids must be active stores under account_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'add_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'add_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    IF EXISTS (
      SELECT 1
      FROM unnest(v_store_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.stores s
        WHERE s.id = sid
          AND s.account_id = v_target_account_id
          AND COALESCE(s.is_active, true) = true
      )
    ) THEN
      RAISE EXCEPTION 'all payload.store_ids must be active stores under the target coverage group account'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'remove_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'below_minimum_action', 'replacement_store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'remove_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    IF EXISTS (
      SELECT 1
      FROM unnest(v_store_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.coverage_group_stores cgs
        WHERE cgs.coverage_group_id = p_target_coverage_group_id
          AND cgs.store_id = sid
          AND cgs.archived_at IS NULL
      )
    ) THEN
      RAISE EXCEPTION 'all payload.store_ids must be active member stores of the target coverage group'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'convert_stationary_to_roving'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload,
      ARRAY['store_ids', 'anchor_store_id', 'area_name', 'notes']
    );
    IF p_account_id IS NULL OR p_position_id IS NULL OR NULLIF(TRIM(COALESCE(p_employment_type, '')), '') IS NULL THEN
      RAISE EXCEPTION 'convert_stationary_to_roving requires account_id, position_id, and employment_type'
        USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = p_account_id) THEN
      RAISE EXCEPTION 'account not found' USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.positions WHERE id = p_position_id) THEN
      RAISE EXCEPTION 'position not found' USING ERRCODE = 'P0002';
    END IF;

    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    IF jsonb_typeof(p_payload -> 'anchor_store_id') IS DISTINCT FROM 'string'
       OR NOT ((p_payload ->> 'anchor_store_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') THEN
      RAISE EXCEPTION 'payload.anchor_store_id must be a uuid string'
        USING ERRCODE = '22023';
    END IF;

    v_anchor_store_id := (p_payload ->> 'anchor_store_id')::uuid;

    IF NOT (v_anchor_store_id = ANY (v_store_ids)) THEN
      RAISE EXCEPTION 'payload.anchor_store_id must be one of payload.store_ids'
        USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM unnest(v_store_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.stores s
        WHERE s.id = sid
          AND s.account_id = p_account_id
          AND COALESCE(s.is_active, true) = true
      )
    ) THEN
      RAISE EXCEPTION 'all payload.store_ids must be active stores under account_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'convert_roving_to_stationary'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'convert_roving_to_stationary requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    IF EXISTS (
      SELECT 1
      FROM unnest(v_store_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.coverage_group_stores cgs
        WHERE cgs.coverage_group_id = p_target_coverage_group_id
          AND cgs.store_id = sid
          AND cgs.archived_at IS NULL
      )
    ) THEN
      RAISE EXCEPTION 'all payload.store_ids must be active member stores of the target coverage group'
        USING ERRCODE = '22023';
    END IF;

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
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'dissolve_coverage_group requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'unsupported request_type: %', p_request_type
      USING ERRCODE = '22023';
  END IF;
END;
$fn$;


-- ── 3. Re-implement Execution Engine ─────────────────────────────────────────
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

  -- ── remove_store / convert_roving_to_stationary ────────────────────────────
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

    -- Enforce minimum 2-store rule for remove_store
    IF v_remaining_count < 2 THEN
      v_below_minimum_action := NULLIF(TRIM(COALESCE(p_request.payload ->> 'below_minimum_action', '')), '');

      -- convert_roving_to_stationary naturally converts to stationary, so below_minimum_action is implicitly convert_remaining_to_standalone
      IF p_request.request_type = 'convert_roving_to_stationary'::public.request_type THEN
        v_below_minimum_action := 'convert_remaining_to_standalone';
      END IF;

      IF v_below_minimum_action IS NULL THEN
        RAISE EXCEPTION
          'removal would leave fewer than 2 active stores in coverage group; '
          'payload.below_minimum_action is required (convert_remaining_to_standalone | add_replacement_store)'
          USING ERRCODE = '23514';
      END IF;

      IF v_below_minimum_action = 'add_replacement_store' THEN
        v_replacement_store_ids := public._coverage_request_uuid_array(p_request.payload, 'replacement_store_ids', true);

        IF COALESCE(array_length(v_replacement_store_ids, 1), 0) = 0 THEN
          RAISE EXCEPTION 'below_minimum_action = add_replacement_store requires payload.replacement_store_ids'
            USING ERRCODE = '22023';
        END IF;

        FOREACH v_store_id IN ARRAY v_replacement_store_ids LOOP
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
              'replacement store % is already active in coverage group %',
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
              'replacement store % is already an active member of this coverage group',
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

        v_notes := v_notes || ARRAY['replacement stores added before removal'];

      ELSIF v_below_minimum_action = 'convert_remaining_to_standalone' THEN
        -- If exactly 1 store remains, convert employees to Stationary
        IF v_remaining_count = 1 THEN
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

        ELSE
          -- v_remaining_count = 0: dissolve the group and set employees Inactive
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
              archive_reason = 'Coverage Request execution: dissolved due to no stores remaining'
          WHERE id = p_request.target_coverage_group_id;

          v_group_archived := true;
          v_notes := v_notes || ARRAY['all stores removed; group dissolved'];
        END IF;

      ELSE
        RAISE EXCEPTION
          'unrecognized below_minimum_action: %; must be convert_remaining_to_standalone or add_replacement_store',
          v_below_minimum_action
          USING ERRCODE = '22023';
      END IF;
    END IF;

    -- Check if anchor is being removed
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
  'OHM2026_0103: Executes structural updates for approved Coverage Requests. Supports add_store, remove_store, convert_roving_to_stationary, and dissolve_coverage_group for both normal and imported roving groups.';


-- ── 4. Update approval queue structure support ──────────────────────────────
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
  v_actor                   record;
  v_request                 public.coverage_requests%ROWTYPE;
  v_artifacts               jsonb;
  v_summary                 jsonb;
  v_execution_result        jsonb;
  v_structural_supported    boolean;
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

  -- Determine if this request type has execution support. Updated to include dissolve_coverage_group.
  v_structural_supported := v_request.request_type IN (
    'add_store'::public.request_type,
    'remove_store'::public.request_type,
    'convert_roving_to_stationary'::public.request_type,
    'dissolve_coverage_group'::public.request_type
  );

  v_artifacts := public._coverage_request_review_artifacts(v_request);

  v_summary := jsonb_build_object(
    'phase',                        'coverage_request_approval_phase_4',
    'generated_at',                  now(),
    'generated_by',                  v_actor.profile_id,
    'generated_by_name',             v_actor.full_name,
    'decision',                      p_decision,
    'structural_execution_enabled',  v_structural_supported
                                      AND p_decision = 'approved'::public.request_status
  ) || v_artifacts;

  IF p_decision = 'approved'::public.request_status THEN
    -- Execute structural mutation atomically before committing approval status.
    -- If execution raises an exception the approval transaction is rolled back.
    IF v_structural_supported THEN
      v_execution_result := public._execute_approved_coverage_request(
        v_request,
        v_actor.profile_id,
        v_actor.full_name,
        v_actor.role_name
      );
      v_summary := v_summary || jsonb_build_object('execution_result', v_execution_result);
    ELSE
      v_execution_result := jsonb_build_object(
        'structural_execution_enabled', false,
        'request_type',                  v_request.request_type,
        'note',                          'Structural execution for this request type is deferred.'
      );
      v_summary := v_summary || jsonb_build_object('execution_result', v_execution_result);
    END IF;

    UPDATE public.coverage_requests
    SET status           = 'approved'::public.request_status,
        approved_by      = v_actor.profile_id,
        approved_by_name = v_actor.full_name,
        approved_at      = now(),
        executed_at      = CASE WHEN v_structural_supported THEN now() ELSE NULL END,
        reviewer_remarks = NULLIF(TRIM(COALESCE(p_reviewer_remarks, '')), ''),
        execution_summary = v_summary,
        updated_by       = v_actor.profile_id,
        updated_at       = now()
    WHERE id = p_coverage_request_id;

  ELSE
    -- Rejection: status-only, no structural changes.
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

  -- History: status transition entry.
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

  -- History: separate execution entry for approved+supported types.
  IF p_decision = 'approved'::public.request_status AND v_structural_supported THEN
    PERFORM public._log_coverage_request_history(
      p_coverage_request_id,
      'approved'::public.request_status,
      'approved'::public.request_status,
      'executed',
      COALESCE(v_execution_result, '{}'::jsonb),
      v_actor.profile_id,
      v_actor.full_name,
      v_actor.role_name,
      'Structural execution completed.'
    );
  END IF;

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

COMMIT;
