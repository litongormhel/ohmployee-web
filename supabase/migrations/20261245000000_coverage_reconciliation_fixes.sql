-- Migration: 20261245000000_coverage_reconciliation_fixes.sql
-- Purpose: Fix Coverage Group Create execution no-op + pending store blocks + make position_id nullable.
-- ============================================================

BEGIN;

-- ── 1. Make position_id nullable on coverage_groups ─────────────────────────
ALTER TABLE public.coverage_groups ALTER COLUMN position_id DROP NOT NULL;

-- ── 2. Drop existing function signatures before redefining ──────────────────
DROP FUNCTION IF EXISTS public._validate_coverage_request_payload(
  public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid
) CASCADE;

-- ── 3. Redefine _validate_coverage_request_payload with request_id check ────
CREATE OR REPLACE FUNCTION public._validate_coverage_request_payload(
  p_request_type                 public.request_type,
  p_payload                      jsonb,
  p_account_id                   uuid DEFAULT NULL,
  p_position_id                  uuid DEFAULT NULL,
  p_employment_type              text DEFAULT NULL,
  p_target_coverage_group_id     uuid DEFAULT NULL,
  p_source_coverage_group_id     uuid DEFAULT NULL,
  p_destination_coverage_group_id uuid DEFAULT NULL,
  p_request_id                   uuid DEFAULT NULL
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

  -- Validation helpers
  v_action_noun             text;
  v_conflicting_store_name  text;
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

  v_action_noun := CASE
    WHEN p_request_type = 'create_coverage_group'::public.request_type THEN 'create Coverage Group'
    WHEN p_request_type = 'add_store'::public.request_type THEN 'add store'
    WHEN p_request_type = 'remove_store'::public.request_type THEN 'remove store'
    WHEN p_request_type = 'dissolve_coverage_group'::public.request_type THEN 'dissolve Coverage Group'
    ELSE 'process coverage request'
  END;

  -- ── Resolve target/source/destination account_ids ────────────────────────
  IF p_target_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_target_account_id
    FROM public.coverage_groups
    WHERE id = p_target_coverage_group_id
      AND archived_at IS NULL;

    -- Imported roving groups may need normalization before account_id resolves.
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

  -- ── Extract store IDs depending on request type ──────────────────────────
  IF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_target_coverage_group_id
      AND archived_at IS NULL;
  ELSE
    IF p_payload ? 'store_ids' THEN
      -- If remove_store, require stores to be listed
      v_store_ids := public._coverage_request_uuid_array(
        p_payload,
        'store_ids',
        (p_request_type = 'remove_store'::public.request_type)
      );
    END IF;
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

  ELSIF p_request_type = 'add_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'add_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;

    -- GAP-10: block if any proposed store already belongs to another active CG
    -- (excluding the target group itself — already-member guard is at execution)
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

  -- ── 4. General Store Footprint Validations ─────────────────────────────────
  IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
    
    -- A. Check for duplicates in the selected stores array (exclude dissolve/merge where store list is derived)
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      IF (
        SELECT COUNT(DISTINCT id) != COUNT(*)
        FROM unnest(v_store_ids) AS id
      ) THEN
        RAISE EXCEPTION 'Cannot %. Selected stores list contains duplicates.',
          v_action_noun
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- B. Check for archived/inactive stores (exclude dissolve where stores are already members)
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      SELECT store_name INTO v_conflicting_store_name
      FROM public.stores
      WHERE id = ANY(v_store_ids)
        AND (is_active = false OR archived_at IS NOT NULL)
      LIMIT 1;

      IF v_conflicting_store_name IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot %. Store % is inactive or archived.',
          v_action_noun,
          v_conflicting_store_name
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- C. Check for invalid store account scope
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      DECLARE
        v_scoped_account_id uuid;
      BEGIN
        v_scoped_account_id := p_account_id;
        IF v_scoped_account_id IS NULL AND p_target_coverage_group_id IS NOT NULL THEN
          SELECT account_id INTO v_scoped_account_id
          FROM public.coverage_groups
          WHERE id = p_target_coverage_group_id;
        END IF;

        IF v_scoped_account_id IS NOT NULL THEN
          SELECT store_name INTO v_conflicting_store_name
          FROM public.stores
          WHERE id = ANY(v_store_ids)
            AND account_id <> v_scoped_account_id
          LIMIT 1;

          IF v_conflicting_store_name IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot %. Store % does not belong to the selected account scope.',
              v_action_noun,
              v_conflicting_store_name
              USING ERRCODE = '23514';
          END IF;
        END IF;
      END;
    END IF;

    -- D. Check for cross-island group (only for create_coverage_group and convert_stationary_to_roving)
    IF p_request_type IN ('create_coverage_group', 'convert_stationary_to_roving') THEN
      IF (
        SELECT COUNT(DISTINCT island_group)
        FROM public.stores
        WHERE id = ANY(v_store_ids)
      ) > 1 THEN
        RAISE EXCEPTION 'Cannot %. Stores must belong to the same island group.',
          v_action_noun
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- E. Block if any store already has a pending coverage request (excluding this request p_request_id)
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'dissolve_coverage_group') THEN
      DECLARE
        v_conflicting_store_name text;
      BEGIN
        WITH pending_requests AS (
          SELECT id, request_type, payload, target_coverage_group_id, source_coverage_group_id, destination_coverage_group_id
          FROM public.coverage_requests
          WHERE status = 'pending'::public.request_status
            AND archived_at IS NULL
            AND (p_request_id IS NULL OR id <> p_request_id)
        ),
        pending_stores AS (
          -- Stores explicitly listed in payload
          SELECT DISTINCT s_id
          FROM pending_requests pr,
               lateral unnest(public._coverage_request_uuid_array(pr.payload, 'store_ids', false)) AS s_id
          WHERE pr.request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving', 'convert_roving_to_stationary')

          UNION

          -- Stores in target group for dissolve
          SELECT DISTINCT cgs.store_id
          FROM pending_requests pr
          JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id = pr.target_coverage_group_id
          WHERE pr.request_type = 'dissolve_coverage_group'
            AND cgs.archived_at IS NULL

          UNION

          -- Stores in source/destination group for merge
          SELECT DISTINCT cgs.store_id
          FROM pending_requests pr
          JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id IN (pr.source_coverage_group_id, pr.destination_coverage_group_id)
          WHERE pr.request_type = 'merge_coverage_groups'
            AND cgs.archived_at IS NULL
        )
        SELECT store_name INTO v_conflicting_store_name
        FROM public.stores
        WHERE id = ANY(v_store_ids)
          AND id IN (SELECT s_id FROM pending_stores)
        LIMIT 1;

        IF v_conflicting_store_name IS NOT NULL THEN
          RAISE EXCEPTION 'Cannot %. One or more selected stores already have a pending coverage request. Pending request already exists for: %',
            v_action_noun,
            v_conflicting_store_name
            USING ERRCODE = '23514';
        END IF;
      END;
    END IF;

  END IF;

END;
$fn$;

COMMENT ON FUNCTION public._validate_coverage_request_payload(
  public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, uuid
) IS
  'Validates the payload of a Coverage Request. Enforces duplicate, inactive, island-group, scope, and pending request constraints.';

REVOKE EXECUTE ON FUNCTION public._validate_coverage_request_payload(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;


-- ── 4. Re-define calling RPCs to supply request_id ──────────────────────────

-- A. create_coverage_request (9 args)
CREATE OR REPLACE FUNCTION public.create_coverage_request(
  p_request_type public.request_type,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_account_id uuid DEFAULT NULL,
  p_position_id uuid DEFAULT NULL,
  p_employment_type text DEFAULT NULL,
  p_target_coverage_group_id uuid DEFAULT NULL,
  p_source_coverage_group_id uuid DEFAULT NULL,
  p_destination_coverage_group_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
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
$fn$;

GRANT EXECUTE ON FUNCTION public.create_coverage_request(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text)
  TO authenticated;


-- B. update_coverage_request_draft (10 args)
CREATE OR REPLACE FUNCTION public.update_coverage_request_draft(
  p_coverage_request_id           uuid,
  p_request_type                  public.request_type,
  p_payload                       jsonb,
  p_account_id                    uuid    DEFAULT NULL,
  p_position_id                   uuid    DEFAULT NULL,
  p_employment_type               text    DEFAULT NULL,
  p_target_coverage_group_id      uuid    DEFAULT NULL,
  p_source_coverage_group_id      uuid    DEFAULT NULL,
  p_destination_coverage_group_id uuid    DEFAULT NULL,
  p_reason                        text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
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
$fn$;

GRANT EXECUTE ON FUNCTION public.update_coverage_request_draft(uuid, public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text)
  TO authenticated;


-- C. submit_coverage_request (1 arg)
CREATE OR REPLACE FUNCTION public.submit_coverage_request(
  p_coverage_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'draft'::public.request_status THEN
    RAISE EXCEPTION 'coverage request can only be submitted from draft status'
      USING ERRCODE = '22023';
  END IF;

  IF v_request.requested_by <> v_actor.profile_id
     AND NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: only the requester or HA/SA can submit this draft'
      USING ERRCODE = '42501';
  END IF;

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

  UPDATE public.coverage_requests
  SET status = 'pending'::public.request_status,
      submitted_by = v_actor.profile_id,
      submitted_by_name = v_actor.full_name,
      submitted_at = now(),
      updated_by = v_actor.profile_id,
      updated_at = now()
  WHERE id = p_coverage_request_id;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    'draft'::public.request_status,
    'pending'::public.request_status,
    'submitted',
    '{}'::jsonb,
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    NULL
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'coverage_request_id', p_coverage_request_id,
    'request_status', 'pending'
  );
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.submit_coverage_request(uuid)
  TO authenticated;


-- D. review_coverage_request (4 args)
CREATE OR REPLACE FUNCTION public.review_coverage_request(
  p_coverage_request_id uuid,
  p_decision text,
  p_reviewer_remarks text DEFAULT NULL,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: only Head Admin or Super Admin can review Coverage Requests'
      USING ERRCODE = '42501';
  END IF;

  IF lower(trim(COALESCE(p_decision, ''))) NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'review decision must be approved or rejected'
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
    RAISE EXCEPTION 'coverage request can only be reviewed from pending status'
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
    v_request.destination_coverage_group_id,
    p_coverage_request_id
  );

  RAISE EXCEPTION 'review_coverage_request is a Phase 2 contract stub; approval and rejection status changes are intentionally deferred'
    USING ERRCODE = '0A000';
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.review_coverage_request(uuid, text, text, text)
  TO authenticated;


-- E. _review_coverage_request_phase3 (4 args)
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
    v_request.destination_coverage_group_id,
    p_coverage_request_id
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


-- ── 5. Redefine _coverage_request_review_artifacts to add warnings ──────────
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
  IF EXISTS (
    SELECT 1 FROM public.stores s
    WHERE s.id = ANY (v_store_ids)
      AND (s.is_active = false OR s.archived_at IS NOT NULL)
  ) THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'inactive_or_archived_store',
      'severity', 'warning',
      'count', (
        SELECT count(*)
        FROM public.stores s
        WHERE s.id = ANY (v_store_ids)
          AND (s.is_active = false OR s.archived_at IS NOT NULL)
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
        'pending_coverage_request', EXISTS (
          SELECT 1
          FROM public.stores s
          WHERE s.id = ANY(v_store_ids)
            AND s.id IN (
              SELECT DISTINCT s_id
              FROM public.coverage_requests pr,
                   lateral unnest(public._coverage_request_uuid_array(pr.payload, 'store_ids', false)) AS s_id
              WHERE pr.status = 'pending'::public.request_status
                AND pr.archived_at IS NULL
                AND pr.id <> p_request.id
                AND pr.request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving', 'convert_roving_to_stationary')

              UNION

              SELECT DISTINCT cgs.store_id
              FROM public.coverage_requests pr
              JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id = pr.target_coverage_group_id
              WHERE pr.status = 'pending'::public.request_status
                AND pr.archived_at IS NULL
                AND pr.id <> p_request.id
                AND pr.request_type = 'dissolve_coverage_group'
                AND cgs.archived_at IS NULL

              UNION

              SELECT DISTINCT cgs.store_id
              FROM public.coverage_requests pr
              JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id IN (pr.source_coverage_group_id, pr.destination_coverage_group_id)
              WHERE pr.status = 'pending'::public.request_status
                AND pr.archived_at IS NULL
                AND pr.id <> p_request.id
                AND pr.request_type = 'merge_coverage_groups'
                AND cgs.archived_at IS NULL
            )
        ),
        'inactive_or_archived_store', EXISTS (
          SELECT 1 FROM public.stores s
          WHERE s.id = ANY(v_store_ids) AND (s.is_active = false OR s.archived_at IS NOT NULL)
        ),
        'structural_migration_required', v_structural_migration_required
      ),
      'conflicts', v_conflicts
    )
  );
END;
$fn$;


-- ── 6. Update _execute_approved_coverage_request (ignore position in create) ──
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

    -- STEP 1: Create coverage group structure (position_id is nullable now)
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

    -- STEP 3 & 4: Evaluate member stores and assign active employees (ignoring position constraint!)
    v_slot_ordinal := 0;
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.store_id = ANY(v_store_ids)
        AND pl.account_id = p_request.account_id
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
          -- Deactivate removed allocations
          UPDATE public.employee_store_allocations
          SET is_active     = false,
              effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id
            AND store_id = ANY (v_removed_store_ids)
            AND is_active = true;

          -- Re-weight surviving allocations
          SELECT COUNT(*) INTO v_active_allocs
          FROM public.employee_store_allocations
          WHERE plantilla_id = v_pl.id AND is_active = true;

          IF v_active_allocs > 0 THEN
            UPDATE public.employee_store_allocations
            SET active_store_count = v_active_allocs,
                filled_hc          = round(1.0 / v_active_allocs, 4)
            WHERE plantilla_id = v_pl.id AND is_active = true;
          END IF;
        ELSE
          -- Deactivate unlinked store links
          UPDATE public.plantilla_store_links psl
          SET status = 'Resigned',
              deleted_at = now()
          FROM public.stores s
          WHERE psl.vcode = s.vcode
            AND psl.plantilla_id = v_pl.id
            AND s.id = ANY (v_removed_store_ids)
            AND psl.deleted_at IS NULL;

          PERFORM public.fn_sync_employee_store_allocations(v_pl.employee_no);
        END IF;
      END LOOP;
    END IF;

    -- Vacancy Reopening (run for all v_removed_store_ids)
    FOREACH v_store_id IN ARRAY v_removed_store_ids LOOP
      SELECT store_name, vcode, account_id, group_id, province_id, area_name
      INTO v_store_name_local, v_store_vcode, v_store_account_id, v_store_group_id, v_store_province_id, v_store_area
      FROM public.stores WHERE id = v_store_id;

      SELECT account_name INTO v_store_account_name
      FROM public.accounts WHERE id = v_store_account_id;

      -- Always set to NULL because stores has no province_id
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
              updated_at                     = now(),
              updated_by                     = p_actor_id
          WHERE id = v_existing_slot_id;

          v_new_slot_id := v_existing_slot_id;
        ELSE
          v_new_slot_id := gen_random_uuid();
          INSERT INTO public.plantilla_slots (
            id, account_id, group_id, store_id, vcode, legacy_vcode,
            "position", position_id, employment_type, slot_status,
            is_roving, created_at, updated_at
          ) VALUES (
            v_new_slot_id, v_store_account_id,
            COALESCE(v_cg_account_group_id, v_store_group_id),
            v_store_id, v_store_vcode, v_store_vcode,
            COALESCE(v_store_position, 'Unknown'), v_store_position_id,
            'Stationary', 'open', false, now(), now()
          );
        END IF;
      END IF;

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type,
        old_value, new_value, reason_code,
        performed_by, remarks, created_at
      ) VALUES (
        v_new_slot_id, v_store_account_id, 'status_changed',
        'closed', 'open', 'COVERAGE_STORE_REMOVED',
        p_actor_id, 'Slot reopened due to store removal from roving coverage group.', now()
      );

      v_vacancies_reopened := v_vacancies_reopened + 1;
    END LOOP;

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

    -- Resolve all store members currently in the group
    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_dissolved_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    -- Extract employee_home_stores mapping
    v_employee_home_stores := p_request.payload -> 'employee_home_stores';

    -- Extract home stores to be retained
    SELECT COALESCE(array_agg(DISTINCT val::uuid), ARRAY[]::uuid[]) INTO v_retained_store_ids
    FROM jsonb_each_text(v_employee_home_stores) AS jet(key, val);

    -- Loop over active employees in the group and convert to stationary
    FOR v_pl IN (
      SELECT pl.*, a.group_id
      FROM public.plantilla pl
      JOIN public.accounts a ON a.id = pl.account_id
      WHERE pl.coverage_group_id = p_request.target_coverage_group_id
        AND pl.status = 'Active'
        AND pl.is_deleted = false
        AND pl.is_archived = false
    ) LOOP
      -- Get retained home store for this employee
      v_remaining_store_id := (v_employee_home_stores ->> v_pl.id::text)::uuid;

      IF v_remaining_store_id IS NULL THEN
        RAISE EXCEPTION 'Dissolve Coverage Group: home store mapping missing for employee % (%)',
          COALESCE(v_pl.employee_name, ''), COALESCE(v_pl.employee_no, '')
          USING ERRCODE = '23514';
      END IF;

      SELECT store_name, vcode INTO v_remaining_store_name, v_remaining_store_vcode
      FROM public.stores WHERE id = v_remaining_store_id;

      -- Convert plantilla employee to Stationary at their home store
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
        -- Deactivate old allocations
        UPDATE public.employee_store_allocations
        SET is_active     = false,
            effective_end = CURRENT_DATE
          WHERE plantilla_id = v_pl.id AND is_active = true;

        -- Insert single active allocation for home store
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
        -- Deactivate excess store links (keep only home store if exists, otherwise deactivate all)
        UPDATE public.plantilla_store_links
        SET status     = 'Resigned',
            deleted_at = now()
        WHERE plantilla_id = v_pl.id
          AND deleted_at IS NULL;
      END IF;

      v_employees_converted := v_employees_converted + 1;
    END LOOP;

    -- Archive store membership edges
    UPDATE public.coverage_group_stores
    SET archived_at = now(),
        archived_by = p_actor_id
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;

    -- Close active coverage slots
    UPDATE public.coverage_slots
    SET slot_status = 'closed',
        updated_at  = now()
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND slot_status <> 'closed';

    -- Archive coverage group structure
    UPDATE public.coverage_groups
    SET archived_at    = now(),
        archived_by    = p_actor_id,
        archive_reason = 'Coverage Request execution: dissolved group'
    WHERE id = p_request.target_coverage_group_id;

    -- Reopen vacancies for all stores losing coverage (dissolved stores NOT in retained home stores list)
    FOREACH v_store_id IN ARRAY v_dissolved_store_ids LOOP
      -- Only reopen if it was not chosen as a home store for any employee in the group
      IF NOT (v_store_id = ANY (v_retained_store_ids)) THEN
        SELECT store_name, vcode, account_id, group_id, province_id, area_name
        INTO v_store_name_local, v_store_vcode, v_store_account_id, v_store_group_id, v_store_province_id, v_store_area
        FROM public.stores WHERE id = v_store_id;

        SELECT account_name INTO v_store_account_name
        FROM public.accounts WHERE id = v_store_account_id;

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

        -- Reopen or create vacancy row
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

        -- Reopen or create plantilla slot row
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
                updated_at                     = now(),
                updated_by                     = p_actor_id
            WHERE id = v_existing_slot_id;

            v_new_slot_id := v_existing_slot_id;
          ELSE
            v_new_slot_id := gen_random_uuid();
            INSERT INTO public.plantilla_slots (
              id, account_id, group_id, store_id, vcode, legacy_vcode,
              "position", position_id, employment_type, slot_status,
              is_roving, created_at, updated_at
            ) VALUES (
              v_new_slot_id, v_store_account_id,
              COALESCE(v_cg_account_group_id, v_store_group_id),
              v_store_id, v_store_vcode, v_store_vcode,
              COALESCE(v_store_position, 'Unknown'), v_store_position_id,
              'Stationary', 'open', false, now(), now()
            );
          END IF;
        END IF;

        INSERT INTO public.slot_history (
          slot_id, account_id, action_type,
          old_value, new_value, reason_code,
          performed_by, remarks, created_at
        ) VALUES (
          v_new_slot_id, v_store_account_id, 'status_changed',
          'closed', 'open', 'COVERAGE_GROUP_DISSOLVED',
          p_actor_id, 'Slot reopened due to coverage group dissolution.', now()
        );

        v_vacancies_reopened := v_vacancies_reopened + 1;
      END IF;
    END LOOP;

    RETURN jsonb_build_object(
      'structural_execution_enabled', true,
      'request_type',                 'dissolve_coverage_group',
      'stores_added',                 0,
      'stores_removed',               COALESCE(array_length(v_dissolved_store_ids, 1), 0),
      'group_archived',               true,
      'employees_converted',          v_employees_converted,
      'vacancies_reopened',           v_vacancies_reopened,
      'notes',                        to_jsonb(v_notes)
    );

  ELSE
    RAISE EXCEPTION 'unsupported request_type for structural execution: %', p_request.request_type
      USING ERRCODE = '22023';
  END IF;

END;
$fn$;

COMMENT ON FUNCTION public._execute_approved_coverage_request(public.coverage_requests, uuid, text, text) IS
  'Executes structural and manpower changes for approved Coverage Requests, promoting active store employees to roving status and ignoring position constraint.';

COMMIT;

NOTIFY pgrst, 'reload schema';
