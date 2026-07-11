-- ============================================================
-- ohm#hc_reduce_001 — HC Reduction Workflow
-- Migration: 20261226000000_hc_reduction_workflow.sql
-- ============================================================
-- Adds HC Reduction as a new HC Request type available in both
-- Plantilla (headcount_requests → plantilla_slots) and MOSES HQ
-- (workforce_pool_requests → workforce_pool_slots).
--
-- Sections:
--   §1  Add 'hc_reduced' to plantilla_slots.slot_status constraint
--   §2  Update fn_set_slot_status to accept hc_reduced
--   §3  Add 'hc_reduced' to workforce_pool_slots.status constraint
--   §4  execute_hc_reduction RPC (Plantilla HC Reduction execution)
--   §5  create_pool_hc_reduction_request RPC (MOSES HQ submission)
--   §6  execute_pool_hc_reduction RPC (MOSES HQ execution on approval)
--
-- Business Rules (authoritative):
--   - Only Ops roles may submit HC Reduction requests
--   - Only HA/SA may approve
--   - Reducible slots: slot_status = 'open' only
--     (no active employee, no HR Emploc, no pipeline applicant)
--   - Current active HC - requested reduction >= 1 (min HC = 1)
--   - Slot selection strategy: newest eligible first (created_at DESC)
--   - 'hc_reduced' is NOT deleted — preserved for audit history
--   - Required HC reporting excludes 'hc_reduced' slots (already
--     excluded by existing filters that only count 'open'/'pipeline'/
--     'hr_processing'/'occupied')
--
-- Regression Protection:
--   - Does NOT touch approve_headcount_request
--   - Does NOT touch create_plantilla_slot_from_request
--   - Does NOT touch approve_pool_vacancy_request
--   - Does NOT touch create_pool_vacancy
--   - HC Increase flow unchanged
--
-- Smoke Tests:
--   ST1: Current HC=5 Vacant=2 Reduction=1  → Approved, newest slot hc_reduced, required HC=4
--   ST2: Current HC=2 Reduction=1           → Approved, required HC=1
--   ST3: Current HC=1 Reduction=1           → Rejected (min HC violation)
--   ST4: Current HC=5 Vacant=1 Reduction=2  → Rejected (insufficient reducible slots)
--   ST5: Current HC=5 Occupied=4 Vacant=1   Reduction=1 → Approved
--   ST6: Current HC=5 Pipeline=1 Vacant=1   Reduction=2 → Rejected
-- ============================================================


-- ============================================================
-- §1  Add 'hc_reduced' to plantilla_slots.slot_status constraint
-- ============================================================

DO $$
BEGIN
  -- Drop and recreate the check constraint to add 'hc_reduced'
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'plantilla_slots_status_check'
  ) THEN
    ALTER TABLE public.plantilla_slots DROP CONSTRAINT plantilla_slots_status_check;
  END IF;

  ALTER TABLE public.plantilla_slots
    ADD CONSTRAINT plantilla_slots_status_check
    CHECK (slot_status IN (
      'open', 'pipeline', 'hr_processing', 'occupied', 'closed', 'hc_reduced'
    ));
END $$;

COMMENT ON COLUMN public.plantilla_slots.slot_status IS
  'open=unfilled vacancy; pipeline=applicant in recruitment; '
  'hr_processing=applicant in HR Emploc; occupied=active employee; '
  'closed=permanently closed; hc_reduced=slot removed via HC Reduction approval.';


-- ============================================================
-- §2  Update fn_set_slot_status to accept 'hc_reduced'
-- ============================================================
-- Adds open→hc_reduced as a valid transition.
-- All other transitions that were previously valid remain unchanged.

CREATE OR REPLACE FUNCTION public.fn_set_slot_status(
  p_slot_id               uuid,
  p_new_status            text,
  p_reason_code           text     DEFAULT NULL,
  p_performed_by          uuid     DEFAULT NULL,
  p_remarks               text     DEFAULT NULL,
  p_occupant_plantilla_id uuid     DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slot           record;
  v_from_status    text;
  v_action_type    text;
  v_history_id     uuid;
  v_transition_ok  boolean := false;
  v_blocked_reason text;
BEGIN
  IF p_slot_id IS NULL THEN
    RAISE EXCEPTION 'fn_set_slot_status: p_slot_id is required';
  END IF;

  IF p_new_status NOT IN (
    'open', 'pipeline', 'hr_processing', 'occupied', 'closed', 'hc_reduced'
  ) THEN
    RAISE EXCEPTION 'fn_set_slot_status: unknown status value ''%''', p_new_status;
  END IF;

  SELECT * INTO v_slot
  FROM public.plantilla_slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_set_slot_status: slot % not found', p_slot_id;
  END IF;

  v_from_status := v_slot.slot_status;

  IF v_from_status = p_new_status THEN
    RETURN jsonb_build_object(
      'status',      'no_op',
      'slot_id',     p_slot_id,
      'from_status', v_from_status,
      'to_status',   p_new_status
    );
  END IF;

  -- Transition matrix
  IF v_from_status IN ('closed', 'hc_reduced') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      '%s is terminal under automation; re-opening a slot requires an HC re-add workflow',
      v_from_status
    );

  ELSIF v_from_status = 'open' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'pipeline';

  ELSIF v_from_status = 'open' AND p_new_status = 'occupied' THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := 'open→occupied (transfer-in) requires p_occupant_plantilla_id';
    ELSE
      v_transition_ok := true;
      v_action_type   := 'transfer_in';
    END IF;

  ELSIF v_from_status = 'open' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'open' AND p_new_status = 'hc_reduced' THEN
    -- HC Reduction: only open slots may be reduced (per business rules)
    v_transition_ok := true;
    v_action_type   := 'hc_reduced';

  ELSIF v_from_status = 'open' AND p_new_status = 'hr_processing' THEN
    v_transition_ok  := false;
    v_blocked_reason := 'open→hr_processing is blocked: slot must pass through pipeline first';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'hr_processing';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'occupied' THEN
    v_transition_ok  := false;
    v_blocked_reason := 'pipeline→occupied is blocked: slot must pass through hr_processing first';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'occupied' THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := 'hr_processing→occupied requires p_occupant_plantilla_id';
    ELSE
      v_transition_ok := true;
      v_action_type   := 'occupied';
    END IF;

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'pipeline' THEN
    v_transition_ok  := false;
    v_blocked_reason := 'hr_processing→pipeline is blocked: emploc backout transitions to open, not pipeline';

  ELSIF v_from_status = 'occupied' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := CASE p_reason_code
                          WHEN 'TRANSFER_OUT' THEN 'transfer_out'
                          ELSE 'resigned'
                        END;

  ELSIF v_from_status = 'occupied' AND p_new_status IN ('pipeline', 'hr_processing') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      'occupied→%s is blocked: occupant must separate first (occupied→open), '
      'then the slot re-enters recruitment', p_new_status
    );

  ELSE
    v_transition_ok  := false;
    v_blocked_reason := format('%s→%s is not a supported transition', v_from_status, p_new_status);
  END IF;

  IF NOT v_transition_ok THEN
    RETURN jsonb_build_object(
      'status',         'blocked',
      'slot_id',        p_slot_id,
      'from_status',    v_from_status,
      'to_status',      p_new_status,
      'blocked_reason', v_blocked_reason
    );
  END IF;

  -- Apply transition
  UPDATE public.plantilla_slots
  SET
    slot_status                   = p_new_status,
    current_occupant_plantilla_id = CASE
      WHEN p_new_status = 'occupied' THEN p_occupant_plantilla_id
      WHEN p_new_status IN ('open', 'closed', 'hc_reduced') THEN NULL
      ELSE current_occupant_plantilla_id
    END,
    closed_at                     = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN now()
      ELSE closed_at
    END,
    closed_by                     = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN p_performed_by
      ELSE closed_by
    END,
    closure_reason_code           = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN p_reason_code
      ELSE closure_reason_code
    END,
    updated_at                    = now(),
    updated_by                    = p_performed_by
  WHERE id = p_slot_id;

  INSERT INTO public.slot_history (
    slot_id,
    account_id,
    action_type,
    old_value,
    new_value,
    reason_code,
    performed_by,
    remarks
  ) VALUES (
    p_slot_id,
    v_slot.account_id,
    v_action_type,
    v_from_status,
    p_new_status,
    p_reason_code,
    p_performed_by,
    p_remarks
  )
  RETURNING id INTO v_history_id;

  RETURN jsonb_build_object(
    'status',      'ok',
    'slot_id',     p_slot_id,
    'from_status', v_from_status,
    'to_status',   p_new_status,
    'action_type', v_action_type,
    'reason_code', p_reason_code,
    'history_id',  v_history_id
  );
END;
$$;

COMMENT ON FUNCTION public.fn_set_slot_status IS
  'Central helper for all plantilla_slots.slot_status transitions. '
  'Validates the transition matrix, updates slot metadata, and appends one slot_history row. '
  'Valid statuses: open, pipeline, hr_processing, occupied, closed, hc_reduced. '
  'New: open→hc_reduced supported (HC Reduction workflow — ohm#hc_reduce_001).';

REVOKE ALL ON FUNCTION public.fn_set_slot_status(uuid, text, text, uuid, text, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.fn_set_slot_status(uuid, text, text, uuid, text, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_set_slot_status(uuid, text, text, uuid, text, uuid)
  TO service_role;


-- ============================================================
-- §3  Add 'hc_reduced' to workforce_pool_slots.status constraint
-- ============================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'wps_status_values'
  ) THEN
    ALTER TABLE public.workforce_pool_slots DROP CONSTRAINT wps_status_values;
  END IF;

  ALTER TABLE public.workforce_pool_slots
    ADD CONSTRAINT wps_status_values
    CHECK (status IN ('open', 'filled', 'under_review', 'closed', 'hc_reduced'));
END $$;


-- ============================================================
-- §4  execute_hc_reduction (Plantilla HC Reduction execution)
-- ============================================================
-- Called by Data Team (Encoder/HA/SA) after approve_headcount_request
-- approves the HC Reduction request.
--
-- Business Rules enforced:
--   • Only for headcount_requests with request_type = 'HC Reduction'
--   • Status must be 'approved_pending_vcode'
--   • active_slots - reduction >= 1 (minimum HC = 1)
--   • open_slots >= reduction (no pipeline/hr/occupied slots may be reduced)
--   • Selects newest open slots first (created_at DESC)
--   • Marks slot_status = 'hc_reduced', writes slot_history
--   • Soft-deletes any linked 'Open' vacancy via legacy_vcode
--   • Sets request status = 'completed'

CREATE OR REPLACE FUNCTION public.execute_hc_reduction(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role          text    := public.get_my_role();
  v_caller_id     uuid    := public.get_current_profile_id();
  v_req           public.headcount_requests%ROWTYPE;
  v_reduction     integer;
  v_active_count  integer;
  v_open_count    integer;
  v_slot_ids      uuid[];
  v_slot_id       uuid;
  v_legacy_vcode  text;
BEGIN
  -- RBAC: Data Team and full-access roles (mirrors create_plantilla_slot_from_request)
  IF v_role NOT IN ('Encoder', 'Head Admin', 'Super Admin') THEN
    RETURN jsonb_build_object(
      'ok',   false,
      'error','forbidden',
      'hint', 'requires Encoder, Head Admin, or Super Admin'
    );
  END IF;

  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  IF lower(coalesce(v_req.request_type, '')) <> 'hc reduction' THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'not_an_hc_reduction',
      'hint',  'This RPC only processes HC Reduction request types'
    );
  END IF;

  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object(
      'ok',      false,
      'error',   'request_not_in_approved_state',
      'current', v_req.status,
      'expected','approved_pending_vcode'
    );
  END IF;

  -- Roving reduction not supported (coverage_slots are a separate subsystem)
  IF lower(coalesce(v_req.workforce_type, 'stationary')) = 'roving' THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'roving_reduction_not_supported',
      'hint',  'HC Reduction is only supported for stationary requests'
    );
  END IF;

  v_reduction := COALESCE(v_req.headcount_needed, 1);

  IF v_reduction < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reduction_quantity');
  END IF;

  -- Count all active slots for this account+store
  -- Active = all slots that are NOT 'hc_reduced' or 'closed'
  SELECT COUNT(*) INTO v_active_count
  FROM public.plantilla_slots
  WHERE account_id = v_req.account_id
    AND (
      (v_req.store_id IS NOT NULL AND store_id = v_req.store_id)
      OR
      (v_req.store_id IS NULL AND store_id IS NULL)
    )
    AND slot_status NOT IN ('hc_reduced', 'closed');

  -- Minimum HC protection: result must be >= 1
  IF (v_active_count - v_reduction) < 1 THEN
    RETURN jsonb_build_object(
      'ok',              false,
      'error',           'minimum_hc_violation',
      'message',         'HC Reduction is not allowed. Stores must maintain a minimum required headcount of 1.',
      'current_active',  v_active_count,
      'requested_reduction', v_reduction
    );
  END IF;

  -- Count only open (vacant) slots — these are the ONLY reducible slots
  SELECT COUNT(*) INTO v_open_count
  FROM public.plantilla_slots
  WHERE account_id = v_req.account_id
    AND (
      (v_req.store_id IS NOT NULL AND store_id = v_req.store_id)
      OR
      (v_req.store_id IS NULL AND store_id IS NULL)
    )
    AND slot_status = 'open';

  -- Guard: cannot reduce more than available open slots
  IF v_open_count < v_reduction THEN
    RETURN jsonb_build_object(
      'ok',              false,
      'error',           'insufficient_reducible_slots',
      'message',         'Requested reduction exceeds available vacant slots.',
      'open_slots',      v_open_count,
      'requested_reduction', v_reduction
    );
  END IF;

  -- Select newest eligible open slots (created_at DESC, LIMIT = reduction count)
  SELECT ARRAY(
    SELECT id
    FROM public.plantilla_slots
    WHERE account_id = v_req.account_id
      AND (
        (v_req.store_id IS NOT NULL AND store_id = v_req.store_id)
        OR
        (v_req.store_id IS NULL AND store_id IS NULL)
      )
      AND slot_status = 'open'
    ORDER BY created_at DESC
    LIMIT v_reduction
    FOR UPDATE
  ) INTO v_slot_ids;

  -- Mark each slot as hc_reduced and close its linked vacancy if any
  FOREACH v_slot_id IN ARRAY v_slot_ids LOOP
    -- Get legacy_vcode before updating slot
    SELECT legacy_vcode INTO v_legacy_vcode
    FROM public.plantilla_slots
    WHERE id = v_slot_id;

    -- Transition slot via authoritative helper
    PERFORM public.fn_set_slot_status(
      v_slot_id,
      'hc_reduced',
      'HC_REDUCTION',
      v_caller_id,
      format('HC Reduction of %s applied from request %s', v_reduction, p_request_id)
    );

    -- Soft-delete linked vacancy if it is still Open
    IF v_legacy_vcode IS NOT NULL THEN
      UPDATE public.vacancies
      SET deleted_at = NOW(),
          updated_by = v_caller_id
      WHERE vcode = v_legacy_vcode
        AND status = 'Open'
        AND deleted_at IS NULL;
    END IF;
  END LOOP;

  -- Mark request as completed (no vcode created for reductions)
  UPDATE public.headcount_requests
  SET status                  = 'completed',
      vacancy_created         = false,
      slot_created_by_user_id = v_caller_id,
      slot_created_at         = NOW(),
      created_vcode           = NULL,
      created_vcodes          = ARRAY[]::text[]
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',           true,
    'request_id',   p_request_id,
    'slots_reduced', v_reduction,
    'slot_ids',     v_slot_ids
  );
END;
$$;

COMMENT ON FUNCTION public.execute_hc_reduction(uuid) IS
  'Executes an approved HC Reduction request on plantilla_slots. '
  'Marks newest open slots as hc_reduced, soft-deletes linked vacancies, '
  'sets request status=completed. RBAC: Encoder | Head Admin | Super Admin. '
  'ohm#hc_reduce_001.';

REVOKE ALL ON FUNCTION public.execute_hc_reduction(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.execute_hc_reduction(uuid) TO authenticated;


-- ============================================================
-- §5  create_pool_hc_reduction_request (MOSES HQ submission)
-- ============================================================
-- Submits a pending MOSES HQ HC Reduction request.
-- Always creates as 'pending' — requires HA/SA approval.
-- Does NOT create vacancies or slots.

CREATE OR REPLACE FUNCTION public.create_pool_hc_reduction_request(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role              text := public.get_my_role();
  v_caller_id         uuid := public.get_current_profile_id();
  v_caller_name       text;
  v_pool_type         public.workforce_pool_types%ROWTYPE;
  v_pool_account      public.accounts%ROWTYPE;
  v_op_account        public.accounts%ROWTYPE;
  v_pool_type_id      uuid;
  v_requesting_acct   uuid;
  v_op_acct_id        uuid;
  v_headcount         integer;
  v_request_id        uuid;
  v_priority          text;
BEGIN
  IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  BEGIN
    v_pool_type_id    := (p_input->>'pool_type_id')::uuid;
    v_requesting_acct := (p_input->>'requesting_account_id')::uuid;
    v_op_acct_id      := nullif(trim(coalesce(p_input->>'operational_account_id','')),  '')::uuid;
    v_headcount       := coalesce((p_input->>'headcount_needed')::int, 1);
  EXCEPTION
    WHEN invalid_text_representation THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_uuid');
  END;

  IF v_headcount < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  SELECT * INTO v_pool_type FROM public.workforce_pool_types WHERE id = v_pool_type_id;
  IF v_pool_type.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_pool_type_id');
  END IF;

  SELECT * INTO v_pool_account FROM public.accounts WHERE id = v_requesting_acct;
  IF v_pool_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_requesting_account_id');
  END IF;

  IF v_op_acct_id IS NOT NULL THEN
    SELECT * INTO v_op_account FROM public.accounts WHERE id = v_op_acct_id;
    IF v_op_account.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_operational_account_id');
    END IF;
    -- Scope guard for Ops: must own the operational account
    IF NOT public.i_have_full_access()
       AND NOT (v_op_account.account_name = ANY(public.get_my_allowed_accounts())) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'out_of_scope');
    END IF;
  END IF;

  v_priority := COALESCE(nullif(trim(p_input->>'priority'), ''), 'normal');
  IF v_priority NOT IN ('normal', 'urgent', 'critical') THEN
    v_priority := 'normal';
  END IF;

  SELECT full_name INTO v_caller_name
  FROM public.users_profile WHERE id = v_caller_id;

  INSERT INTO public.workforce_pool_requests (
    pool_type_id,
    requesting_account_id,
    requesting_account,
    headcount_needed,
    priority,
    reason,
    status,
    request_type,
    is_ops_request,
    operational_account_id,
    operational_account_name,
    is_global_pool_request,
    created_by,
    created_by_name
  ) VALUES (
    v_pool_type_id,
    v_requesting_acct,
    v_pool_account.account_name,
    v_headcount,
    v_priority,
    p_input->>'reason',
    'pending',
    'HC Reduction',
    (v_op_acct_id IS NOT NULL),
    v_op_acct_id,
    v_op_account.account_name,
    (v_op_acct_id IS NULL),
    v_caller_id::text,
    v_caller_name
  )
  RETURNING id INTO v_request_id;

  RETURN jsonb_build_object(
    'ok',        true,
    'request_id', v_request_id,
    'status',    'pending'
  );
END;
$$;

COMMENT ON FUNCTION public.create_pool_hc_reduction_request(jsonb) IS
  'Submits a MOSES HQ HC Reduction request (always pending, requires HA/SA approval). '
  'Does NOT create any vacancies or pool slots. ohm#hc_reduce_001.';

REVOKE ALL ON FUNCTION public.create_pool_hc_reduction_request(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pool_hc_reduction_request(jsonb) TO authenticated;


-- ============================================================
-- §6  execute_pool_hc_reduction (MOSES HQ approval + execution)
-- ============================================================
-- Called by HA/SA from the MOSES HQ Review Queue to approve AND
-- immediately execute a pool HC Reduction request.
-- Combines approval + execution in one step (mirrors how
-- approve_pool_vacancy_request approves AND creates slots).

CREATE OR REPLACE FUNCTION public.execute_pool_hc_reduction(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id     uuid    := public.get_current_profile_id();
  v_caller_name   text;
  v_req           public.workforce_pool_requests%ROWTYPE;
  v_reduction     integer;
  v_account_id    uuid;
  v_active_count  integer;
  v_open_count    integer;
  v_slot_ids      uuid[];
  v_slot_id       uuid;
  v_linked_vac_id uuid;
BEGIN
  IF NOT public.i_have_full_access() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden',
      'hint', 'requires Head Admin or Super Admin');
  END IF;

  SELECT * INTO v_req
  FROM public.workforce_pool_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  IF lower(coalesce(v_req.request_type, '')) <> 'hc reduction' THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'not_an_hc_reduction',
      'hint',  'This RPC only processes HC Reduction requests'
    );
  END IF;

  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object(
      'ok',      false,
      'error',   'invalid_status',
      'current', v_req.status,
      'expected','pending'
    );
  END IF;

  v_reduction := COALESCE(v_req.headcount_needed, 1);

  -- Resolve which account to scope pool slots by
  v_account_id := COALESCE(v_req.operational_account_id, v_req.requesting_account_id);

  -- Count active pool slots (not closed/hc_reduced) for this pool type + account
  SELECT COUNT(*) INTO v_active_count
  FROM public.workforce_pool_slots
  WHERE pool_type_id = v_req.pool_type_id
    AND account_id   = v_account_id
    AND status NOT IN ('closed', 'hc_reduced')
    AND deleted_at IS NULL;

  IF (v_active_count - v_reduction) < 1 THEN
    RETURN jsonb_build_object(
      'ok',              false,
      'error',           'minimum_hc_violation',
      'message',         'HC Reduction is not allowed. Pool must maintain a minimum required headcount of 1.',
      'current_active',  v_active_count,
      'requested_reduction', v_reduction
    );
  END IF;

  SELECT COUNT(*) INTO v_open_count
  FROM public.workforce_pool_slots
  WHERE pool_type_id = v_req.pool_type_id
    AND account_id   = v_account_id
    AND status       = 'open'
    AND deleted_at IS NULL;

  IF v_open_count < v_reduction THEN
    RETURN jsonb_build_object(
      'ok',              false,
      'error',           'insufficient_reducible_slots',
      'message',         'Requested reduction exceeds available vacant pool slots.',
      'open_slots',      v_open_count,
      'requested_reduction', v_reduction
    );
  END IF;

  -- Select newest open pool slots
  SELECT ARRAY(
    SELECT id
    FROM public.workforce_pool_slots
    WHERE pool_type_id = v_req.pool_type_id
      AND account_id   = v_account_id
      AND status       = 'open'
      AND deleted_at IS NULL
    ORDER BY created_at DESC
    LIMIT v_reduction
    FOR UPDATE
  ) INTO v_slot_ids;

  SELECT full_name INTO v_caller_name
  FROM public.users_profile WHERE id = v_caller_id;

  FOREACH v_slot_id IN ARRAY v_slot_ids LOOP
    -- Get linked vacancy if any
    SELECT vacancy_id INTO v_linked_vac_id
    FROM public.workforce_pool_slots WHERE id = v_slot_id;

    -- Mark pool slot as hc_reduced
    UPDATE public.workforce_pool_slots
    SET status     = 'hc_reduced',
        deleted_at = NOW(),
        updated_at = NOW(),
        updated_by = v_caller_id::text
    WHERE id = v_slot_id;

    -- Soft-delete linked vacancy if open
    IF v_linked_vac_id IS NOT NULL THEN
      UPDATE public.vacancies
      SET deleted_at = NOW(),
          updated_by = v_caller_id
      WHERE id = v_linked_vac_id
        AND status = 'Open'
        AND deleted_at IS NULL;
    END IF;
  END LOOP;

  -- Approve and mark request completed
  UPDATE public.workforce_pool_requests
  SET status      = 'approved',
      approved_by = v_caller_name,
      approved_at = NOW(),
      updated_at  = NOW(),
      updated_by  = v_caller_id::text
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',            true,
    'request_id',    p_request_id,
    'slots_reduced', v_reduction,
    'slot_ids',      v_slot_ids
  );
END;
$$;

COMMENT ON FUNCTION public.execute_pool_hc_reduction(uuid) IS
  'Approves and executes a MOSES HQ HC Reduction request. '
  'Marks newest open workforce_pool_slots as hc_reduced, soft-deletes linked vacancies, '
  'sets request status=approved. RBAC: Head Admin | Super Admin. ohm#hc_reduce_001.';

REVOKE ALL ON FUNCTION public.execute_pool_hc_reduction(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.execute_pool_hc_reduction(uuid) TO authenticated;
