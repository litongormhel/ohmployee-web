-- ============================================================
-- OHM2026_0022 — Phase 6.4: Wire Occupied → Open Slot Transition
-- Migration: 20260813000004_wire_occupied_open_slot_transition.sql
-- Depends on: 20260812000000_fn_set_slot_status.sql      (Phase 6.0)
--             20260813000001_wire_open_pipeline_slot_transitions.sql      (Phase 6.1)
--             20260813000002_wire_pipeline_hr_processing_slot_transition.sql (Phase 6.2)
--             20260813000003_wire_hr_processing_occupied_slot_transition.sql (Phase 6.3)
--             20260520012857_remote_schema.sql           (_apply_separation — latest live)
--             20260524116000_fix_deactivation_notification_user_id.sql
--               (approve_deactivation_requests_batch — latest live)
-- ============================================================
-- Phase 6.4 of slot_lifecycle_automation_plan.md (OHM2026_0017).
--
-- SCOPE: Wire the occupied → open slot transition (+ clear occupant link)
-- into the separation and deactivation finalization paths. No other workflow,
-- vacancy/applicant behavior, HR Emploc behavior, UI, or migration is changed.
--
-- Hook points:
--   _apply_separation      — resignation / endo / AWOL / generic separation paths.
--                            Fires after _log_employee_action (audit written),
--                            before RETURN. Stationary (non-roving) only.
--   approve_deactivation_requests_batch — deactivation finalization (Backoffice approve).
--                            Fires per plantilla_id after audit log INSERT,
--                            before the notifications loop.
--
-- Slot lookup strategy (per OHM2026_0017 Q6):
--   Primary:  plantilla_slots.current_occupant_plantilla_id = plantilla.id
--   Fallback: plantilla_slots.legacy_vcode = plantilla.vcode AND is_roving = false
--   Roving slots excluded at both helper and host RPC levels (no reliable
--   1:1 VCODE→slot until the deferred coverage model lands).
--
-- Reason code mapping (per task spec OHM2026_0022):
--   _apply_separation  Endo         → ENDO
--   _apply_separation  Resigned     → RESIGNED
--   _apply_separation  AWOL/Other   → RESIGNED  (best existing reason maps safely)
--   approve_deactivation_requests_batch → RESIGNED  (generic deactivation finalization)
--
-- Non-blocking contract (hard requirement — OHM2026_0017 Q1):
--   A slot sync error must NEVER roll back or alter the host RPC's transaction.
--   fn_sync_slot_to_open (§1) catches ALL exceptions internally and emits
--   RAISE NOTICE only. PERFORM (not SELECT INTO) used in host RPCs so the
--   return value is discarded.
--
-- Roving / pool carve-out:
--   resign_roving_employee is intentionally NOT hooked in Phase 6.4.
--   Roving slots have N VCODEs → 1 slot; no reliable 1:1 mapping until the
--   deferred coverage model lands (OHM2026_0017 Q6 carve-out).
--   fn_sync_slot_to_open also guards internally (deployment_type = 'Roving' → skip).
--
-- Sections:
--   §1  fn_sync_slot_to_open   (internal non-blocking helper)
--   §2  Patch _apply_separation
--   §3  Patch approve_deactivation_requests_batch
--   §4  GRANT
-- ============================================================


-- ============================================================
-- §1  fn_sync_slot_to_open
-- ============================================================
-- Non-blocking internal helper that transitions a vacancy slot from
-- occupied to open when an employee leaves the Plantilla active set.
--
-- Called AFTER the host RPC has written the plantilla status change and
-- its audit log — the transition represents confirmed, committed state.
--
-- Arguments
-- ---------
--   p_plantilla_id — plantilla.id of the departing employee.
--   p_reason_code  — RESIGNED | ENDO | TRANSFER_OUT (default: RESIGNED).
--   p_performed_by — Acting user UUID for slot_history.performed_by.
--   p_source_fn    — Calling function name; written to slot_history.remarks.
--
-- Slot lookup order:
--   1. current_occupant_plantilla_id = p_plantilla_id (authoritative occupant link)
--   2. legacy_vcode = plantilla.vcode AND is_roving = false (bridge fallback)
--
-- Returns: JSONB from fn_set_slot_status (ok / no_op / blocked), or NULL
--          when skipped (null plantilla_id, not found, roving, no slot, any error).
-- NEVER RAISES.

CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_open(
  p_plantilla_id uuid,
  p_reason_code  text DEFAULT 'RESIGNED',
  p_performed_by uuid DEFAULT NULL,
  p_source_fn    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Phase 6.4 — non-blocking occupied→open slot sync (OHM2026_0022).

  Locates the slot by current_occupant_plantilla_id first (authoritative),
  falling back to legacy_vcode (1:1 bridge, non-roving only).
  Delegates to fn_set_slot_status with:
    p_new_status            = 'open'
    p_occupant_plantilla_id = NULL  (cleared automatically by fn_set_slot_status)

  Blocked or no_op results from fn_set_slot_status are logged via
  RAISE NOTICE and returned as-is — they never raise into the host RPC.
*/
DECLARE
  v_plantilla_row record;
  v_slot_id       uuid;
  v_result        jsonb;
BEGIN
  -- ── Guard: plantilla_id required ───────────────────────────────────────
  IF p_plantilla_id IS NULL THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: skipped — p_plantilla_id is null (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Fetch plantilla row (vcode, deployment_type, employee_no) ───────────
  -- We read even if the row is now Inactive/Deactivated (the host RPC
  -- already committed the status change before calling this helper).
  SELECT id, vcode, deployment_type, employee_no
    INTO v_plantilla_row
    FROM public.plantilla
   WHERE id = p_plantilla_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: plantilla % not found, skipped (source=%)',
      p_plantilla_id, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Roving carve-out (OHM2026_0017 Q6) ──────────────────────────────────
  -- Roving slots have N VCODEs → 1 slot; no reliable 1:1 mapping until the
  -- deferred roving coverage model lands. Skip unconditionally.
  IF COALESCE(v_plantilla_row.deployment_type, '') = 'Roving' THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: skipped — roving plantilla % not in Phase 6.4 scope (source=%)',
      p_plantilla_id, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Locate slot: occupant link preferred, legacy_vcode fallback ──────────
  -- Phase 6.3 sets current_occupant_plantilla_id when hr_processing→occupied.
  -- For pre-Phase-6.3 slots (backfilled to occupied but no occupant link),
  -- fall back to the 1:1 legacy_vcode bridge.
  SELECT id INTO v_slot_id
    FROM public.plantilla_slots
   WHERE current_occupant_plantilla_id = p_plantilla_id
     AND is_roving = false
  LIMIT 1;

  -- Fallback: locate by legacy_vcode bridge (non-roving, non-null VCODE)
  IF v_slot_id IS NULL AND v_plantilla_row.vcode IS NOT NULL THEN
    SELECT id INTO v_slot_id
      FROM public.plantilla_slots
     WHERE legacy_vcode = v_plantilla_row.vcode
       AND is_roving    = false
    LIMIT 1;
  END IF;

  IF v_slot_id IS NULL THEN
    -- No slot for this plantilla (pre-slot-era legacy vacancy, roving, or pool).
    -- Skip silently — not an error; normal for records predating the slot model.
    RETURN NULL;
  END IF;

  -- ── Delegate to central transition helper ────────────────────────────────
  -- fn_set_slot_status handles: matrix validation, slot row update
  -- (slot_status = 'open', current_occupant_plantilla_id = NULL, updated_at/by),
  -- and slot_history append with new_value='open' (→ aging episode restarts).
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'open',
    p_reason_code           => p_reason_code,
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.4 / %s / plantilla_id=%s / employee_no=%s / reason=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_plantilla_id::text,
                                 COALESCE(v_plantilla_row.employee_no, 'null'),
                                 COALESCE(p_reason_code, 'null')
                               ),
    p_occupant_plantilla_id => NULL  -- occupant cleared on any separation/deactivation
  ) INTO v_result;

  -- Log blocked/no_op outcomes for observability; never raise.
  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_open: % for slot_id=% plantilla_id=% source=% — %',
      v_result->>'status',
      v_slot_id,
      p_plantilla_id,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_slot_to_open: error for plantilla_id=% source=% — % (sqlstate=%)',
    p_plantilla_id, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_slot_to_open(uuid, text, uuid, text) IS
  'Phase 6.4 — non-blocking occupied→open slot sync helper (OHM2026_0022). '
  'Locates slot by current_occupant_plantilla_id (preferred) then legacy_vcode fallback '
  '(non-roving only). Calls fn_set_slot_status with p_new_status=open and clears '
  'current_occupant_plantilla_id. NEVER raises. Blocked/no_op results are RAISE NOTICEd. '
  'Callers: _apply_separation (resignation/endo/separation), '
  'approve_deactivation_requests_batch (deactivation finalize). '
  'Roving slots excluded (no reliable 1:1 VCODE→slot in Phase 6.4).';


-- ============================================================
-- §2  Patch _apply_separation (Phase 6.4 slot sync hook)
-- ============================================================
-- Source: 20260520012857_remote_schema.sql
--   (latest live version — stationary separation: resign / endo / AWOL / other).
-- Change: TWO additions —
--   (a) DECLARE v_sep_reason_code text
--   (b) Phase 6.4 hook inserted after PERFORM _log_employee_action
--       and before the final RETURN.
-- All existing behavior — RBAC, plantilla status update, separation_status
-- mapping, audit log, return shape, SECURITY DEFINER — is preserved IDENTICALLY.
-- No parameter or return type changes.
--
-- Hook guard: COALESCE(v_old.deployment_type, '') <> 'Roving'
--   Roving employees are separated via resign_roving_employee (different RPC).
--   _apply_separation is only invoked for stationary employees in practice,
--   but the guard is explicit for safety.
--
-- Reason code mapping:
--   Endo      → ENDO     (end of deployment)
--   Resigned  → RESIGNED (voluntary resignation)
--   AWOL / Separated / Terminated / others → RESIGNED
--     (best existing reason code per OHM2026_0022 task spec)

CREATE OR REPLACE FUNCTION public._apply_separation(
  p_plantilla_id   uuid,
  p_separation_type text,
  p_separation_date date,
  p_remarks         text,
  p_capability      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_old            plantilla%ROWTYPE;
  v_sep_status     text;
  v_sep_reason_code text;  -- Phase 6.4: slot reason code
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, p_capability) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_old FROM public.plantilla WHERE id = p_plantilla_id FOR UPDATE;
  IF v_old.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','plantilla_not_found');
  END IF;
  IF v_old.status <> 'Active' THEN
    RETURN jsonb_build_object('ok',false,'error','only_active_can_be_separated','current_status',v_old.status);
  END IF;

  -- Map UI separation type to allowed separation_status check values
  v_sep_status := CASE p_separation_type
    WHEN 'Resigned'   THEN 'Resigned'
    WHEN 'Endo'       THEN 'Endo'
    WHEN 'AWOL'       THEN 'AWOL'
    WHEN 'Separated'  THEN 'Others'
    WHEN 'Terminated' THEN 'Others'
    ELSE 'Others'
  END;

  UPDATE public.plantilla
  SET status              = 'Inactive',
      inactive_at         = NOW(),
      inactive_by         = public.get_current_profile_id(),
      date_of_separation  = p_separation_date,
      resignation_date    = p_separation_date,
      separation_status   = v_sep_status,
      remarks             = COALESCE(p_remarks, remarks),
      updated_at          = NOW(),
      updated_by          = public.get_current_profile_id()
  WHERE id = p_plantilla_id;

  -- Existing trigger trg_plantilla_separation_to_vacancy fires here
  -- and creates the backfill vacancy reusing the same vcode.

  PERFORM public._log_employee_action(
    p_plantilla_id,
    'SEPARATION_'||UPPER(p_separation_type),
    format('Employee marked %s effective %s', p_separation_type, p_separation_date),
    to_jsonb(v_old),
    jsonb_build_object('separation_type',p_separation_type,'date',p_separation_date,'remarks',p_remarks)
  );

  -- ── Phase 6.4: non-blocking slot occupied→open sync ──────────────────────
  -- Wires the separation event into the slot lifecycle model so the matching
  -- plantilla slot reopens (occupied→open) and its occupant link is cleared.
  -- Only fires for stationary (non-roving) employees; roving separation is
  -- handled by resign_roving_employee and is deferred (OHM2026_0017 Q6).
  -- fn_sync_slot_to_open NEVER raises; a slot error will not roll back
  -- this function's plantilla update, trigger, or audit log writes.
  v_sep_reason_code := CASE p_separation_type
    WHEN 'Endo' THEN 'ENDO'   -- end of deployment
    ELSE 'RESIGNED'            -- Resigned, AWOL, Separated, Terminated, Others
  END;

  IF COALESCE(v_old.deployment_type, '') <> 'Roving' THEN
    PERFORM public.fn_sync_slot_to_open(
      p_plantilla_id => p_plantilla_id,
      p_reason_code  => v_sep_reason_code,
      p_performed_by => public.get_current_profile_id(),
      p_source_fn    => '_apply_separation'
    );
  END IF;

  RETURN jsonb_build_object('ok',true,'plantilla_id',p_plantilla_id,'new_status','Inactive',
                            'separation_status',v_sep_status,'vcode',v_old.vcode);
END
$$;

COMMENT ON FUNCTION public._apply_separation(uuid, text, date, text, text) IS
  'Internal separation executor for stationary employees (resign / endo / AWOL / other). '
  'Phase 6.4 (OHM2026_0022): syncs the matching plantilla slot occupied→open '
  'after the audit log write, on the stationary (non-roving) path only, '
  'via fn_sync_slot_to_open (non-blocking). '
  'Reason code: Endo→ENDO; all other types→RESIGNED. '
  'Roving employees excluded (use resign_roving_employee — Phase 6.4 carve-out).';


-- ============================================================
-- §3  Patch approve_deactivation_requests_batch (Phase 6.4 slot sync hook)
-- ============================================================
-- Source: 20260524116000_fix_deactivation_notification_user_id.sql
--   (latest live version — fixed notification recipient_user_id FK).
-- Change: TWO additions —
--   (a) DECLARE v_deact_rec RECORD
--   (b) Phase 6.4 hook loop inserted after the audit log INSERT and before
--       the notifications loop.
-- All existing behavior — RBAC, batch validation, plantilla status update
-- to 'Deactivated', audit log, notifications, return shape, SECURITY DEFINER,
-- and OHM2026_2064 notification FK fix — is preserved IDENTICALLY.
-- No parameter or return type changes.
--
-- Hook guard: fn_sync_slot_to_open handles roving internally (deployment_type
--   check). No explicit guard needed at the host level since fn_sync_slot_to_open
--   is fully non-blocking.
--
-- Reason code: RESIGNED
--   approve_deactivation_requests_batch carries no per-employee separation type.
--   RESIGNED is the canonical code for occupant departure/slot reopen.

CREATE OR REPLACE FUNCTION public.approve_deactivation_requests_batch(
  p_request_ids   uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_processor_id       uuid;
  v_batch_id           uuid;
  v_valid_count        int;
  v_input_count        int;
  v_invalid_ids        uuid[];
  v_requestor_rec      RECORD;
  v_deact_rec          RECORD;  -- Phase 6.4: per-plantilla slot sync loop
  v_notifications_sent int := 0;
  v_approved_count     int;
BEGIN
  -- ── Auth guard ───────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_am_backoffice() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Backoffice role required'
      USING ERRCODE = '42501';
  END IF;

  v_processor_id := public.get_current_profile_id();
  IF v_processor_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Input validation ─────────────────────────────────────────
  v_input_count := array_length(p_request_ids, 1);

  IF v_input_count IS NULL OR v_input_count = 0 THEN
    RAISE EXCEPTION 'p_request_ids must be a non-empty array'
      USING ERRCODE = '22023';
  END IF;

  -- Verify all IDs exist AND are Pending — fail whole batch if any invalid
  SELECT COUNT(*) INTO v_valid_count
    FROM public.employee_deactivation_requests
   WHERE id = ANY(p_request_ids)
     AND status = 'Pending'
     AND is_archived = false;

  IF v_valid_count <> v_input_count THEN
    SELECT array_agg(unnested) INTO v_invalid_ids
    FROM unnest(p_request_ids) AS unnested
    WHERE unnested NOT IN (
      SELECT id FROM public.employee_deactivation_requests
       WHERE id = ANY(p_request_ids)
         AND status = 'Pending'
         AND is_archived = false
    );

    RAISE EXCEPTION 'Batch validation failed: % of % request(s) are not in Pending status or do not exist. Invalid IDs: %',
      (v_input_count - v_valid_count), v_input_count, v_invalid_ids
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Generate shared batch_id ─────────────────────────────────
  v_batch_id := gen_random_uuid();

  -- ── Approve all requests ─────────────────────────────────────
  UPDATE public.employee_deactivation_requests SET
    status                    = 'Approved',
    batch_id                  = v_batch_id,
    processed_by_profile_id   = v_processor_id,
    processed_at              = NOW(),
    updated_at                = NOW()
  WHERE id = ANY(p_request_ids);

  GET DIAGNOSTICS v_approved_count = ROW_COUNT;

  -- ── Update plantilla rows ────────────────────────────────────
  UPDATE public.plantilla p SET
    status                    = 'Deactivated',
    deactivated_at            = NOW(),
    deactivated_by            = v_processor_id,
    deactivated_visible_until = NOW() + INTERVAL '15 days',
    inactive_visible_until    = NULL,
    updated_at                = NOW()
  FROM public.employee_deactivation_requests r
  WHERE r.id = ANY(p_request_ids)
    AND p.id = r.plantilla_id;

  -- ── Audit log — one row per approved request ─────────────────
  INSERT INTO public.employee_deactivation_audit_log (
    request_id,
    plantilla_id,
    action,
    performed_by_profile_id,
    metadata
  )
  SELECT
    r.id,
    r.plantilla_id,
    'APPROVED',
    v_processor_id,
    jsonb_build_object(
      'batch_size',   v_approved_count,
      'batch_id',     v_batch_id
    )
  FROM public.employee_deactivation_requests r
  WHERE r.id = ANY(p_request_ids);

  -- ── Phase 6.4: non-blocking slot occupied→open sync per deactivated plantilla ─
  -- Wires the deactivation approval into the slot lifecycle model so each matching
  -- plantilla slot reopens (occupied→open) and its occupant link is cleared.
  -- fn_sync_slot_to_open is non-blocking: errors are logged via RAISE NOTICE and
  -- never propagate into this batch approval. Roving carve-out is handled inside
  -- fn_sync_slot_to_open (deployment_type = 'Roving' → skip).
  -- Reason code RESIGNED: deactivation batch carries no per-employee separation type;
  -- RESIGNED is the canonical code for occupant departure / slot reopen.
  FOR v_deact_rec IN
    SELECT r.plantilla_id
      FROM public.employee_deactivation_requests r
     WHERE r.id = ANY(p_request_ids)
  LOOP
    PERFORM public.fn_sync_slot_to_open(
      p_plantilla_id => v_deact_rec.plantilla_id,
      p_reason_code  => 'RESIGNED',
      p_performed_by => v_processor_id,
      p_source_fn    => 'approve_deactivation_requests_batch'
    );
  END LOOP;

  -- ── Notifications — one per unique requestor ──────────────────
  -- recipient_user_id references auth.users(id) via users_profile.auth_user_id.
  -- Profiles with no linked auth user are skipped silently so a missing
  -- linkage never aborts the whole approval batch.
  -- OHM2026_2064: fixed to use auth_user_id (not requestor_profile_id) to avoid
  -- notifications_user_id_fkey FK violation.
  FOR v_requestor_rec IN
    SELECT
      r.requestor_profile_id,
      COUNT(*)::int AS request_count,
      COALESCE(ro.role_name, 'ops') AS requestor_role,
      up.auth_user_id AS requestor_auth_user_id
    FROM public.employee_deactivation_requests r
    LEFT JOIN public.users_profile up ON up.id = r.requestor_profile_id
    LEFT JOIN public.roles ro ON ro.id = up.role_id
    WHERE r.id = ANY(p_request_ids)
    GROUP BY r.requestor_profile_id, ro.role_name, up.auth_user_id
  LOOP
    IF v_requestor_rec.requestor_auth_user_id IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO public.notifications (
      recipient_role,
      recipient_user_id,
      notification_type,
      event_type,
      title,
      message,
      deep_link_route,
      reference_type,
      reference_id
    ) VALUES (
      COALESCE(v_requestor_rec.requestor_role, 'ops'),
      v_requestor_rec.requestor_auth_user_id,
      'deactivation',
      'DEACTIVATION_PROCESSED',
      'Deactivation Requests Processed',
      v_requestor_rec.request_count || ' deactivation request(s) have been approved.',
      '/deactivation/my-requests',
      'deactivation_batch',
      v_batch_id::text
    );

    v_notifications_sent := v_notifications_sent + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'approved',           v_approved_count,
    'batch_id',           v_batch_id,
    'notifications_sent', v_notifications_sent
  );
END;
$$;

COMMENT ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) IS
  'Atomically approves a batch of Pending deactivation requests. '
  'Fails entire batch if any request is invalid. '
  'Sends one notification per unique requestor using auth.users.id '
  'resolved from users_profile.auth_user_id. '
  'OHM2026_2064: fixed notifications_user_id_fkey violation. '
  'Phase 6.4 (OHM2026_0022): also syncs each deactivated plantilla slot '
  'occupied→open after the audit log write, via fn_sync_slot_to_open '
  '(non-blocking; reason_code=RESIGNED; roving excluded by helper).';


-- ============================================================
-- §4  GRANT
-- ============================================================
-- fn_sync_slot_to_open is an internal helper called only from
-- SECURITY DEFINER RPCs; restrict to authenticated.

REVOKE ALL ON FUNCTION public.fn_sync_slot_to_open(uuid, text, uuid, text)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_sync_slot_to_open(uuid, text, uuid, text)
  TO authenticated;

-- Preserve existing GRANTs on _apply_separation (unchanged from 20260520012857).
REVOKE ALL ON FUNCTION public._apply_separation(uuid, text, date, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._apply_separation(uuid, text, date, text, text)
  TO authenticated;

-- Preserve existing GRANTs on approve_deactivation_requests_batch (unchanged from 20260524116000).
REVOKE ALL ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) TO authenticated;


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — Helper function exists with correct signature
--   SELECT routine_name, routine_type, security_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public'
--     AND routine_name = 'fn_sync_slot_to_open';
--   -- Expected: 1 row, FUNCTION, DEFINER
--
-- V2 — _apply_separation body includes Phase 6.4 hook
--   SELECT prosrc LIKE '%fn_sync_slot_to_open%'
--   FROM pg_proc
--   WHERE proname = '_apply_separation'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: true
--
-- V3 — approve_deactivation_requests_batch body includes Phase 6.4 hook
--   SELECT prosrc LIKE '%fn_sync_slot_to_open%'
--   FROM pg_proc
--   WHERE proname = 'approve_deactivation_requests_batch'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: true
--
-- V4 — Slot moves occupied → open on stationary resignation
--   (After calling resign_employee for a stationary employee whose slot
--    is currently in occupied status)
--   SELECT slot_status, current_occupant_plantilla_id
--   FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: slot_status='open', current_occupant_plantilla_id=NULL
--
--   SELECT action_type, old_value, new_value, reason_code, remarks
--   FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--   ORDER BY created_at DESC LIMIT 5;
--   -- Expected: one row with action_type='resigned', old_value='occupied',
--   --           new_value='open', reason_code='RESIGNED',
--   --           remarks includes 'Phase 6.4 / _apply_separation'
--
-- V5 — Endo separation writes ENDO reason code
--   (After calling endo_employee for a stationary employee)
--   SELECT reason_code FROM public.slot_history
--   WHERE remarks LIKE 'Phase 6.4 / _apply_separation%'
--   ORDER BY created_at DESC LIMIT 1;
--   -- Expected: 'ENDO'
--
-- V6 — Deactivation approval clears occupant link
--   (After approve_deactivation_requests_batch for an occupied slot)
--   SELECT slot_status, current_occupant_plantilla_id
--   FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: slot_status='open', current_occupant_plantilla_id=NULL
--
--   SELECT action_type, old_value, new_value, reason_code, remarks
--   FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--   ORDER BY created_at DESC LIMIT 5;
--   -- Expected: one row with action_type='resigned', old_value='occupied',
--   --           new_value='open', reason_code='RESIGNED',
--   --           remarks includes 'Phase 6.4 / approve_deactivation_requests_batch'
--
-- V7 — Slot appears in vw_slot_derived_vacancy_shadow after reopen
--   SELECT vcode, slot_status, derived_status
--   FROM public.vw_slot_derived_vacancy_shadow
--   WHERE vcode = '<test_vcode>';
--   -- Expected: 1 row with slot_status='open' (shadow view projects open/pipeline/closed)
--
-- V8 — current_occupant_plantilla_id is NULL after separation
--   SELECT ps.current_occupant_plantilla_id
--   FROM public.plantilla_slots ps
--   WHERE ps.legacy_vcode = '<test_vcode>';
--   -- Expected: NULL
--
-- V9 — slot_history written with new_value='open' (aging episode restarts)
--   SELECT new_value, created_at FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--     AND action_type = 'resigned'
--   ORDER BY created_at DESC LIMIT 1;
--   -- Expected: new_value='open' (fn_set_slot_status writes this on occupied→open)
--
-- V10 — Roving paths NOT touched by Phase 6.4 sync
--   SELECT slot_status, current_occupant_plantilla_id
--   FROM public.plantilla_slots
--   WHERE is_roving = true;
--   -- Status and occupant must match pre-migration snapshot
--
-- V11 — resign_roving_employee is not hooked (Phase 6.4 carve-out)
--   SELECT prosrc LIKE '%fn_sync_slot_to_open%'
--   FROM pg_proc
--   WHERE proname = 'resign_roving_employee'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: false (roving deferred to Phase 6.6+)
--
-- V12 — Separation/deactivation flow still works end-to-end
--   (Test: resign_employee, endo_employee, separate_employee, approve_deactivation_requests_batch
--    all return their expected shapes with 'ok':true or 'approved':N)
--   -- Expected: no change in return values or behavior vs pre-migration
--
-- V13 — P1–P8 reconciliation baseline after Phase 6.4
--   (Re-run the parity suite from OHM2026_0016 / 20260811000000_fix_backfill_parity_d1_d2.sql)
--   NOTE: occupied slots that have been separated now move to open in the shadow view.
--   Any slot now in open (post-separation) will appear in both legacy (as Open/For Sourcing)
--   AND the shadow view. This is correct expected behavior — aging episode restarts.
--   Any slot still in occupied (no separation yet) appears in legacy as Filled
--   and NOT in shadow — unchanged from Phase 6.3.
--
-- V14 — RESIGNED and ENDO reason codes are valid in slot_reason_codes
--   SELECT code, label FROM public.slot_reason_codes WHERE code IN ('RESIGNED', 'ENDO');
--   -- Expected: 2 rows (defined in 20260804000000_plantilla_slot_foundation_v1.sql)
-- ============================================================
