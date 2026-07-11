-- Migration: 20261242000000_coverage_fix_p0002_normalization_ordering
-- Created: 2026-06-23
-- Purpose: Fix P0002 regression in _validate_coverage_request_payload where
--          fn_normalize_imported_roving_group was dead code (called after the
--          not-found exception, never reached); move normalization before the
--          exception so imported roving groups resolve correctly.
--
-- Smoke Tests:
-- S1: Convert Roving → Stationary on ROV-2026-08678 / WAREHOUSE / Dela Cruz
--     → should succeed (no P0002)
-- S2: Same request with a retained store NOT in employee's ESA
--     → should still block with 'Selected Home Store is not assigned to employee.'
--
-- Root cause (ohm#3v8d5n2k):
--   20261241000000 introduced a logic ordering regression:
--     1. SELECT account_id → NULL for imported roving group
--     2. RAISE EXCEPTION P0002                ← fires here
--     3. PERFORM fn_normalize_imported_roving_group  ← never reached (dead code)
--   Fix: move normalization inside the target lookup block, before the exception.
--
-- Scope: §1 only — _validate_coverage_request_payload rewrite.
--   _review_coverage_request_phase3 (GAP-05/06) is unchanged.
--   No new tables, no RLS changes, no new grants.
--
-- Apply after: 20261241000000_coverage_phase3_4_gaps.sql
-- ============================================================================

BEGIN;

-- ── §1. _validate_coverage_request_payload ─────────────────────────────────
-- Carries forward all logic from 20261241000000 (GAP-09, GAP-10, dissolve key
-- from 20261240000000) with one structural fix: fn_normalize_imported_roving_group
-- is now called inside the target lookup block, before the not-found exception,
-- so imported roving groups can resolve before the guard fires.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._validate_coverage_request_payload(
  p_request_type                 public.request_type,
  p_payload                      jsonb,
  p_account_id                   uuid DEFAULT NULL,
  p_position_id                  uuid DEFAULT NULL,
  p_employment_type              text DEFAULT NULL,
  p_target_coverage_group_id     uuid DEFAULT NULL,
  p_source_coverage_group_id     uuid DEFAULT NULL,
  p_destination_coverage_group_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_store_ids               uuid[];
  v_anchor_store_id         uuid;
  v_target_account_id       uuid;
  v_source_account_id       uuid;
  v_destination_account_id  uuid;

  -- GAP-09: employee with no retained-store allocation
  v_gap09_employee_name     text;

  -- GAP-10: coverage group code for a conflicting store
  v_gap10_cg_code           text;
BEGIN

  -- ── Structural-only guard ─────────────────────────────────────────────────
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'payload must be a json object' USING ERRCODE = '22023';
  END IF;

  IF p_payload::text ~* '"(required_hc|required_headcount|headcount|hc|slot_id|slot_ids|vacancy_id|vacancy_vcode|vcode|pipeline_id|coverage_weight|hc_share|store_count)"[[:space:]]*:' THEN
    RAISE EXCEPTION
      'Coverage Request payload must remain structure-only; HC, slot, vacancy, pipeline, coverage weight, and HC share fields are not allowed'
      USING ERRCODE = '22023';
  END IF;

  -- ── Resolve target/source/destination account_ids ────────────────────────
  IF p_target_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_target_account_id
    FROM public.coverage_groups
    WHERE id = p_target_coverage_group_id
      AND archived_at IS NULL;

    -- Imported roving groups may need normalization before account_id resolves.
    -- FIX (ohm#3v8d5n2k): normalization was previously placed after the
    -- not-found exception (dead code). Moved here so it runs before the guard.
    IF v_target_account_id IS NULL THEN
      PERFORM public.fn_normalize_imported_roving_group(p_target_coverage_group_id);
      SELECT account_id INTO v_target_account_id
      FROM public.coverage_groups
      WHERE id = p_target_coverage_group_id
        AND archived_at IS NULL;
    END IF;

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

  -- ── Per-type validation ───────────────────────────────────────────────────

  IF p_request_type = 'create_coverage_group'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload,
      ARRAY['store_ids', 'anchor_store_id', 'area_name', 'employment_type', 'notes']
    );
    IF p_account_id IS NULL THEN
      RAISE EXCEPTION 'create_coverage_group requires account_id'
        USING ERRCODE = '22023';
    END IF;

    -- GAP-10: block if any proposed store already belongs to another active CG
    IF p_payload ? 'store_ids' THEN
      v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', false);
      IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
        SELECT cg.coverage_code
        INTO   v_gap10_cg_code
        FROM   unnest(v_store_ids) AS sid
        JOIN   public.coverage_group_stores cgs ON cgs.store_id = sid
        JOIN   public.coverage_groups       cg  ON cg.id = cgs.coverage_group_id
        WHERE  cgs.archived_at IS NULL
          AND  cg.archived_at  IS NULL
        LIMIT 1;

        IF v_gap10_cg_code IS NOT NULL THEN
          RAISE EXCEPTION 'Store already belongs to Coverage Group %.', v_gap10_cg_code
            USING ERRCODE = '23514';
        END IF;
      END IF;
    END IF;

  ELSIF p_request_type = 'add_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'add_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;

    -- GAP-10: block if any proposed store already belongs to another active CG
    -- (excluding the target group itself — already-member guard is at execution)
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', false);
    IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
      SELECT cg.coverage_code
      INTO   v_gap10_cg_code
      FROM   unnest(v_store_ids) AS sid
      JOIN   public.coverage_group_stores cgs ON cgs.store_id = sid
      JOIN   public.coverage_groups       cg  ON cg.id = cgs.coverage_group_id
      WHERE  cgs.archived_at IS NULL
        AND  cg.archived_at  IS NULL
        AND  cg.id <> p_target_coverage_group_id
      LIMIT 1;

      IF v_gap10_cg_code IS NOT NULL THEN
        RAISE EXCEPTION 'Store already belongs to Coverage Group %.', v_gap10_cg_code
          USING ERRCODE = '23514';
      END IF;
    END IF;

  ELSIF p_request_type = 'remove_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['store_ids', 'below_minimum_action', 'notes']
    );
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'remove_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'convert_stationary_to_roving'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['store_ids', 'anchor_store_id', 'area_name', 'employment_type', 'notes']
    );
    IF p_account_id IS NULL THEN
      RAISE EXCEPTION 'convert_stationary_to_roving requires account_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'convert_roving_to_stationary'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'convert_roving_to_stationary requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    -- GAP-09: For each active imported employee in the target coverage group,
    -- at least one retained store (payload.store_ids) must be in their active
    -- employee_store_allocations. Non-imported employees are not ESA-tracked
    -- and their store assignment derives from CG membership; they are excluded.
    IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
      SELECT pl.employee_name
      INTO   v_gap09_employee_name
      FROM   public.plantilla pl
      WHERE  pl.coverage_group_id = p_target_coverage_group_id
        AND  pl.status = 'Active'
        AND  COALESCE(pl.is_deleted,  false) = false
        AND  COALESCE(pl.is_archived, false) = false
        AND  (
               pl.source_employee_import_batch_id  IS NOT NULL
            OR pl.source_baseline_import_batch_id  IS NOT NULL
             )
        AND  NOT EXISTS (
               SELECT 1
               FROM   public.employee_store_allocations esa
               WHERE  esa.plantilla_id = pl.id
                 AND  esa.store_id     = ANY(v_store_ids)
                 AND  esa.is_active    = true
             )
      LIMIT 1;

      IF v_gap09_employee_name IS NOT NULL THEN
        RAISE EXCEPTION 'Selected Home Store is not assigned to employee.'
          USING ERRCODE = '23514';
      END IF;
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
    -- GAP-02 (from 20261240000000): employee_home_stores is a valid dissolve key
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['notes', 'employee_home_stores']
    );
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'dissolve_coverage_group requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
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

COMMENT ON FUNCTION public._validate_coverage_request_payload(
  public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid
) IS
  'ohm#3v8d5n2k FIX: fn_normalize_imported_roving_group now runs inside the '
  'target lookup block before the not-found exception (was dead code in 20261241000000). '
  'Carries forward GAP-09 (retained-store ESA validation for convert_roving_to_stationary), '
  'GAP-10 (store-conflict at draft/submit for add_store and create_coverage_group), '
  'and dissolve employee_home_stores key (20261240000000). '
  'Supersedes 20261241000000.';

NOTIFY pgrst, 'reload schema';

-- ── Smoke-test queries (run manually after applying) ────────────────────────
/*
  -- Prerequisites: supply real UUIDs for your test data.
  --   <rov_cg_id>         = coverage_groups.id for ROV-2026-08678
  --   <warehouse_store_id> = stores.id for WAREHOUSE store
  --   <bad_store_id>      = stores.id for a store NOT in Dela Cruz ESA
  --   <other_cg_store_id> = stores.id already in another active CG
  --   <target_cg_id>      = coverage_groups.id for add_store target
  --   <approved_req_id>   = coverage_requests.id of a pending structural request

  -- S1 — GAP-09 positive: Convert Roving → Stationary on ROV-2026-08678 / WAREHOUSE
  --       Expected: request saves / submits without error (no P0002)
  SELECT create_coverage_request(
    'convert_roving_to_stationary',
    jsonb_build_object('store_ids', jsonb_build_array('<warehouse_store_id>'::uuid)),
    NULL, NULL, NULL,
    '<rov_cg_id>'::uuid
  );

  -- S2 — GAP-09 negative: same request but with a store NOT in Dela Cruz ESA
  --       Expected: ERROR 23514 'Selected Home Store is not assigned to employee.'
  SELECT create_coverage_request(
    'convert_roving_to_stationary',
    jsonb_build_object('store_ids', jsonb_build_array('<bad_store_id>'::uuid)),
    NULL, NULL, NULL,
    '<rov_cg_id>'::uuid
  );

  -- S3 — GAP-10: Add Store where store already belongs to another active CG
  --       Expected: ERROR 23514 'Store already belongs to Coverage Group CG-XXXX.'
  SELECT create_coverage_request(
    'add_store',
    jsonb_build_object('store_ids', jsonb_build_array('<other_cg_store_id>'::uuid)),
    NULL, NULL, NULL,
    '<target_cg_id>'::uuid
  );

  -- S4 — GAP-05/06: Approve a pending structural request
  --       Expected: coverage_request_history has 'executed' event with rich payload;
  --                 coverage_requests.executed_at IS NOT NULL
  SELECT approve_coverage_request('<approved_req_id>'::uuid, 'GAP-05/06 smoke test');

  SELECT event_type, actor_name, created_at, event_payload
  FROM   public.coverage_request_history
  WHERE  coverage_request_id = '<approved_req_id>'::uuid
  ORDER  BY created_at;

  SELECT id, status, executed_at
  FROM   public.coverage_requests
  WHERE  id = '<approved_req_id>'::uuid;
*/

COMMIT;
