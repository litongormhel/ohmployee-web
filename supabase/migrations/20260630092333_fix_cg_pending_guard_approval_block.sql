-- Migration: 20260630000003_fix_cg_pending_guard_approval_block
-- Created: 2026-06-30
-- Purpose: Allow approval/rejection of existing pending Coverage Requests even when
--          the same Coverage Group has other pending requests (pre-existing duplicates).
--          Adds p_skip_cg_pending_guard boolean DEFAULT FALSE to
--          _validate_coverage_request_payload; Section F is skipped when TRUE.
--          _review_coverage_request_phase3 passes TRUE so approval/rejection is
--          never blocked by the one-pending-per-CG guard.
--
-- Smoke Tests:
-- S1: approve_coverage_request on a pending request whose CG has another pending
--     request must succeed (no "already has a pending request" error).
-- S2: create_coverage_request / submit_coverage_request for a CG with an existing
--     pending request must still be blocked (Section F fires, guard enabled).
-- S3: After all pending requests for a CG are resolved, new request creation works.

BEGIN;

-- ── §1. Drop old 9-arg overload to avoid ambiguity ──────────────────────────
-- The new 10-arg function (with DEFAULT FALSE) covers all existing call sites.

DROP FUNCTION IF EXISTS public._validate_coverage_request_payload(
  public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, uuid
);


-- ── §2. Redefine _validate_coverage_request_payload (10 args) ───────────────
-- Identical to 20260630000002 except:
--   • New 10th parameter: p_skip_cg_pending_guard boolean DEFAULT FALSE
--   • Section F is wrapped: IF NOT p_skip_cg_pending_guard THEN … END IF

CREATE OR REPLACE FUNCTION public._validate_coverage_request_payload(
  p_request_type                  public.request_type,
  p_payload                       jsonb,
  p_account_id                    uuid    DEFAULT NULL,
  p_position_id                   uuid    DEFAULT NULL,
  p_employment_type               text    DEFAULT NULL,
  p_target_coverage_group_id      uuid    DEFAULT NULL,
  p_source_coverage_group_id      uuid    DEFAULT NULL,
  p_destination_coverage_group_id uuid    DEFAULT NULL,
  p_request_id                    uuid    DEFAULT NULL,
  p_skip_cg_pending_guard         boolean DEFAULT FALSE
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
    WHEN p_request_type = 'add_store'::public.request_type            THEN 'add store'
    WHEN p_request_type = 'remove_store'::public.request_type         THEN 'remove store'
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

  -- GAP-09 check for dissolve
  IF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    IF (p_payload -> 'employee_home_stores') IS NOT NULL THEN
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
  END IF;

  -- ── 4. General Store Footprint Validations ─────────────────────────────────
  IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN

    -- A. Check for duplicates in the selected stores array
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

    -- B. Check for archived/inactive stores
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      SELECT store_name INTO v_conflicting_store_name
      FROM public.stores
      WHERE id = ANY(v_store_ids)
        AND (is_active = false OR status = 'archived')
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

    -- D. Cross-island group check
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

    -- E. Block if any store already has a pending coverage request (excluding current request)
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

  -- ── F. Block if the involved Coverage Group already has any pending request ──
  -- Skipped when p_skip_cg_pending_guard = TRUE (approval/rejection context).
  -- The guard must only fire during new request creation or submission, never
  -- when resolving (approving or rejecting) an already-pending request.
  IF NOT p_skip_cg_pending_guard
     AND p_request_type <> 'create_coverage_group'::public.request_type
  THEN
    DECLARE
      v_pending_for_group uuid;
    BEGIN
      SELECT id INTO v_pending_for_group
      FROM public.coverage_requests
      WHERE status = 'pending'::public.request_status
        AND archived_at IS NULL
        AND (p_request_id IS NULL OR id <> p_request_id)
        AND (
              (p_target_coverage_group_id IS NOT NULL AND (
                    target_coverage_group_id      = p_target_coverage_group_id
                 OR source_coverage_group_id      = p_target_coverage_group_id
                 OR destination_coverage_group_id = p_target_coverage_group_id
              ))
           OR (p_source_coverage_group_id IS NOT NULL AND (
                    target_coverage_group_id      = p_source_coverage_group_id
                 OR source_coverage_group_id      = p_source_coverage_group_id
                 OR destination_coverage_group_id = p_source_coverage_group_id
              ))
           OR (p_destination_coverage_group_id IS NOT NULL AND (
                    target_coverage_group_id      = p_destination_coverage_group_id
                 OR source_coverage_group_id      = p_destination_coverage_group_id
                 OR destination_coverage_group_id = p_destination_coverage_group_id
              ))
            )
      LIMIT 1;

      IF v_pending_for_group IS NOT NULL THEN
        RAISE EXCEPTION 'This Coverage Group already has a pending request. Please approve or reject the current request before creating another one.'
          USING ERRCODE = '23514';
      END IF;
    END;
  END IF;

END;
$fn$;

COMMENT ON FUNCTION public._validate_coverage_request_payload(
  public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, uuid, boolean
) IS
  'Validates the payload of a Coverage Request. Enforces duplicate, inactive, island-group, scope, pending store (Section E), and one-pending-per-CG (Section F) constraints. Pass p_skip_cg_pending_guard => TRUE from approval/rejection contexts to bypass Section F.';

REVOKE EXECUTE ON FUNCTION public._validate_coverage_request_payload(
  public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, uuid, boolean
) FROM PUBLIC, anon, authenticated;


-- ── §3. Update _review_coverage_request_phase3 to skip Section F ────────────
-- All other logic is identical to 20261245000000. Only the validate call gains
-- p_skip_cg_pending_guard => TRUE so approving/rejecting a pending request that
-- shares a CG with other pending requests is no longer blocked.

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

  -- ── Payload validation ────────────────────────────────────────────────────
  -- p_skip_cg_pending_guard => TRUE: approval/rejection resolves an existing
  -- pending request and must never be blocked by the one-pending-per-CG guard.
  -- All other checks (structural payload, GAP-09, GAP-10, Section E) still run.
  PERFORM public._validate_coverage_request_payload(
    v_request.request_type,
    v_request.payload,
    v_request.account_id,
    v_request.position_id,
    v_request.employment_type,
    v_request.target_coverage_group_id,
    v_request.source_coverage_group_id,
    v_request.destination_coverage_group_id,
    p_coverage_request_id,        -- p_request_id: exclude self from store-level pending check
    TRUE                          -- p_skip_cg_pending_guard: do NOT block approval/rejection
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

  -- ── History: status-transition event ─────────────────────────────────────
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

REVOKE EXECUTE ON FUNCTION public._review_coverage_request_phase3(uuid, public.request_status, text, text)
  FROM PUBLIC, anon, authenticated;

COMMIT;
