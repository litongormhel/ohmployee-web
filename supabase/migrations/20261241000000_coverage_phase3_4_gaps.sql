-- ============================================================================
-- ohm#7k2m9xq4 — Coverage Phase 3 & 4 (GAP-05, GAP-06, GAP-09, GAP-10)
-- Migration: 20261241000000_coverage_phase3_4_gaps.sql
--
-- GAP-05 — Missing Executed History Event
--   On successful execution, insert a coverage_request_history record with
--   event_type = 'executed' and a rich payload: action_type, executed_by,
--   executed_by_name, executed_at, before_state, after_state, execution_detail.
--
-- GAP-06 — executed_at Not Populated
--   On successful execution, set coverage_requests.executed_at = now().
--   Already present in _review_coverage_request_phase3 from 20261230000000;
--   carried forward here to confirm the fix in the canonical live version.
--
-- GAP-09 — Retained Home Store Validation (convert_roving_to_stationary)
--   Validate that each active imported employee in the target coverage group
--   has at least one of the retained stores (payload.store_ids) in their
--   active employee_store_allocations. Block if not.
--   Error: 'Selected Home Store is not assigned to employee.'
--
-- GAP-10 — Early Store Conflict Validation (add_store, create_coverage_group)
--   Detect store overlap at Draft Save and Submit — before approval or execution.
--   A store that already belongs to an active Coverage Group must be blocked
--   when saving or submitting a draft, not only at execution.
--   Error: 'Store already belongs to Coverage Group CG-XXXX.'
--
-- Scope:
--   §1 — Update _validate_coverage_request_payload (GAP-09, GAP-10)
--   §2 — Update _review_coverage_request_phase3   (GAP-05, GAP-06)
--
-- RLS / Security:
--   No new table writes. No new RLS grants.
--   _validate_coverage_request_payload: VOLATILE (reads live tables), no SECURITY DEFINER.
--   _review_coverage_request_phase3:    SECURITY DEFINER (unchanged from 20261230000000).
--
-- Execution guards:
--   GAP-09 and GAP-10 run in _validate_coverage_request_payload, which is
--   called by create_coverage_request (draft save), submit_coverage_request,
--   update_draft (via create/submit paths), and _review_coverage_request_phase3
--   (approval). A second-level guard is therefore not required in
--   _execute_approved_coverage_request.
--
-- Apply after: 20261240000000_phase1_employee_integrity_and_dissolve_compliance.sql
-- ============================================================================

BEGIN;

-- ── §1. _validate_coverage_request_payload ─────────────────────────────────
-- Full rewrite incorporating GAP-09 and GAP-10.
-- Base: 20261240000000 (which supersedes 20261022000000 for dissolve_coverage_group).
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

  -- Normalize imported roving groups before validation
  IF p_target_coverage_group_id IS NOT NULL AND v_target_account_id IS NULL THEN
    PERFORM public.fn_normalize_imported_roving_group(p_target_coverage_group_id);
    SELECT account_id INTO v_target_account_id
    FROM public.coverage_groups
    WHERE id = p_target_coverage_group_id AND archived_at IS NULL;
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
    -- employee_store_allocations.  Non-imported employees are not ESA-tracked
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
  'ohm#7k2m9xq4 GAP-09: convert_roving_to_stationary validates retained stores '
  'are in active employee_store_allocations for imported employees. '
  'GAP-10: add_store and create_coverage_group block at draft/submit if any '
  'proposed store already belongs to an active Coverage Group. '
  'Supersedes 20261240000000.';


-- ── §2. _review_coverage_request_phase3 ────────────────────────────────────
-- GAP-05: Enrich the executed history event payload with action_type,
--         executed_by, executed_by_name, executed_at, before_state,
--         after_state, and execution_detail.
-- GAP-06: executed_at = now() on coverage_requests when execution succeeds
--         (carried forward from 20261230000000, confirmed here).
-- Base: 20261230000000 (which supersedes 20261023000000).
-- ────────────────────────────────────────────────────────────────────────────
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
  -- GAP-05: enriched executed-history payload
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
    v_request.destination_coverage_group_id
  );

  -- ── Determine structural support ─────────────────────────────────────────
  v_structural_supported := v_request.request_type IN (
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

    -- GAP-06: Record executed_at when structural execution succeeded.
    v_executed_at := CASE WHEN v_structural_supported THEN now() ELSE NULL END;

    UPDATE public.coverage_requests
    SET status           = 'approved'::public.request_status,
        approved_by      = v_actor.profile_id,
        approved_by_name = v_actor.full_name,
        approved_at      = now(),
        executed_at      = v_executed_at,            -- GAP-06
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
  -- GAP-05: Rich payload with action_type, executed_by, executed_by_name,
  --         executed_at, before_state, after_state, execution_detail.
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
      'approved'::public.request_status,   -- status unchanged — execution is not a status change
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

COMMENT ON FUNCTION public._review_coverage_request_phase3(uuid, public.request_status, text, text) IS
  'ohm#7k2m9xq4 GAP-05: executed history event now includes action_type, executed_by, '
  'executed_by_name, executed_at, before_state, after_state, execution_detail. '
  'GAP-06: executed_at set on coverage_requests when structural execution succeeds. '
  'Lifecycle chain: created → submitted → approved → executed. '
  'Supersedes 20261230000000.';

NOTIFY pgrst, 'reload schema';

-- ── Smoke-test queries (run manually after applying) ────────────────────────
/*
  -- GAP-05 & GAP-06 smoke test:
  -- 1. Approve a Coverage Request that supports structural execution.
  SELECT approve_coverage_request('<pending_request_uuid>', 'GAP-05/06 smoke test');
  -- 2. Confirm history has submitted, approved, executed entries.
  SELECT event_type, actor_name, created_at, event_payload
  FROM coverage_request_history
  WHERE coverage_request_id = '<request_uuid>'
  ORDER BY created_at;
  -- Expected: rows with event_type IN ('submitted', 'approved', 'executed').
  -- 3. Confirm executed event has rich payload.
  SELECT event_payload
  FROM coverage_request_history
  WHERE coverage_request_id = '<request_uuid>' AND event_type = 'executed';
  -- Expected: { action_type, executed_by, executed_by_name, executed_at,
  --             before_state: "approved", after_state: "executed", execution_detail: {...} }
  -- 4. Confirm executed_at populated on the request.
  SELECT executed_at FROM coverage_requests WHERE id = '<request_uuid>';
  -- Expected: NOT NULL, approximately now().

  -- GAP-09 smoke test:
  -- Submit a convert_roving_to_stationary request with a retained store_id
  -- that is NOT in any active employee_store_allocations for employees in the CG.
  SELECT submit_coverage_request('<draft_request_uuid>');
  -- Expected: ERROR 23514 — 'Selected Home Store is not assigned to employee.'

  -- GAP-10 smoke test:
  -- Create or submit an add_store request where the store already belongs to
  -- a different active Coverage Group.
  SELECT create_coverage_request(
    'add_store', '{"store_ids": ["<store_uuid_already_in_cg>"]}'::jsonb,
    NULL, NULL, NULL, '<target_cg_uuid>'
  );
  -- Expected: ERROR 23514 — 'Store already belongs to Coverage Group CG-XXXX.'
*/

COMMIT;
