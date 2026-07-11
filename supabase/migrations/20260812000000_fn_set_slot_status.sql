-- ============================================================
-- OHM2026_0018 — Central Slot Status Helper (Phase 6.0)
-- Migration:  20260812000000_fn_set_slot_status.sql
-- Depends on: 20260804000000_plantilla_slot_foundation_v1.sql
--             (plantilla_slots, slot_history, slot_reason_codes)
-- ============================================================
-- Scope: DATABASE FUNCTION ONLY.
--
-- Implements fn_set_slot_status — the single, authoritative
-- helper for all plantilla_slots.slot_status transitions.
--
-- CENTRAL HELPER ONLY — no current workflow behavior changes.
-- This function is NOT wired into any existing RPC yet.
-- Future workflow hooks (Phase 6.1–6.5) must call this helper
-- instead of writing plantilla_slots directly. No direct client
-- writes to slot_status are permitted (RLS + REVOKE in foundation).
--
-- Sections:
--   §1  fn_set_slot_status
--   §2  GRANT
--
-- Transition matrix (from slot_lifecycle_automation_plan.md §Q2–Q3):
--
--   VALID transitions:
--     open          → pipeline       (first active applicant for VCODE)
--     pipeline      → open           (last active applicant goes terminal)
--     pipeline      → hr_processing  (confirm onboard)
--     hr_processing → occupied       (move to plantilla; occupant required)
--     hr_processing → open           (applicant backout during HR Emploc)
--     occupied      → open           (resignation / ENDO / deactivation)
--     open          → occupied       (transfer-in only; occupant required — deferred Phase 6.6)
--     open          → closed         (slot closure approved — deferred Phase 6.7)
--     pipeline      → closed         (slot closure approved — deferred Phase 6.7)
--     X             → X              (same-state: silent no-op)
--
--   BLOCKED transitions (return status='blocked', never raise):
--     open          → hr_processing  (skips pipeline/applicant context)
--     pipeline      → occupied       (skips HR Emploc onboarding compliance)
--     occupied      → pipeline       (occupant must leave first → open)
--     occupied      → hr_processing  (occupant must leave first → open)
--     hr_processing → pipeline       (no backward pipeline regression)
--     closed        → *              (terminal under automation; reopen = HC re-add workflow)
--     * → occupied with NULL occupant
--     any other pair
--
--   STRUCTURAL ERRORS (RAISE EXCEPTION — caller cannot recover):
--     NULL p_slot_id
--     Unknown p_new_status value
--     Slot not found
-- ============================================================


-- ============================================================
-- §1  fn_set_slot_status
-- ============================================================

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
/*
  Central slot-status transition helper.

  Parameters
  ----------
  p_slot_id               — UUID of the plantilla_slots row to transition.
  p_new_status            — Target status: open | pipeline | hr_processing | occupied | closed.
  p_reason_code           — Optional: slot_reason_codes.code (RESIGNED, ENDO, TRANSFER_OUT, …).
  p_performed_by          — Optional: users_profile.id of the acting user (written to slot_history).
  p_remarks               — Optional: short free-text context (e.g. deactivation request id).
  p_occupant_plantilla_id — Required when transitioning INTO 'occupied'; ignored otherwise.

  Returns
  -------
  JSONB with one of three outcomes:

    { "status": "ok",      "slot_id": …, "from_status": …, "to_status": …,
      "action_type": …, "reason_code": …, "history_id": … }

    { "status": "no_op",   "slot_id": …, "from_status": …, "to_status": … }

    { "status": "blocked", "slot_id": …, "from_status": …, "to_status": …,
      "blocked_reason": … }

  RAISE EXCEPTION is reserved for structurally invalid inputs only
  (NULL slot_id, unknown status value, slot not found).  Workflow hooks
  must treat 'blocked' as a skip-and-log, never as an error that rolls
  back the host RPC transaction.
*/
DECLARE
  v_slot           record;
  v_from_status    text;
  v_action_type    text;
  v_history_id     uuid;
  v_transition_ok  boolean := false;
  v_blocked_reason text;
BEGIN
  -- ── 0. Structural validation ────────────────────────────────────────────────
  -- These are programmer errors; raising here is intentional.

  IF p_slot_id IS NULL THEN
    RAISE EXCEPTION 'fn_set_slot_status: p_slot_id is required';
  END IF;

  IF p_new_status NOT IN ('open', 'pipeline', 'hr_processing', 'occupied', 'closed') THEN
    RAISE EXCEPTION 'fn_set_slot_status: unknown status value ''%''', p_new_status;
  END IF;

  -- ── 1. Fetch and lock slot row ──────────────────────────────────────────────
  SELECT * INTO v_slot
  FROM public.plantilla_slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_set_slot_status: slot % not found', p_slot_id;
  END IF;

  v_from_status := v_slot.slot_status;

  -- ── 2. Same-state no-op (idempotent re-entry) ──────────────────────────────
  IF v_from_status = p_new_status THEN
    RETURN jsonb_build_object(
      'status',      'no_op',
      'slot_id',     p_slot_id,
      'from_status', v_from_status,
      'to_status',   p_new_status
    );
  END IF;

  -- ── 3. Transition matrix ────────────────────────────────────────────────────
  -- Each branch sets v_transition_ok + v_action_type, or sets v_blocked_reason.
  -- 'closed' is checked first because it is a terminal FROM state regardless of
  -- the target.

  IF v_from_status = 'closed' THEN
    -- Terminal state; reopen requires an HC re-add workflow, not automation.
    v_transition_ok  := false;
    v_blocked_reason := 'closed is terminal under automation; '
                        're-opening a slot requires an HC re-add workflow';

  ELSIF v_from_status = 'open' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'pipeline';

  ELSIF v_from_status = 'open' AND p_new_status = 'occupied' THEN
    -- Transfer-in path only (Phase 6.6 — deferred; matrix entry exists so the
    -- helper is ready when the transfer RPC lands).
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := 'open→occupied (transfer-in) requires p_occupant_plantilla_id';
    ELSE
      v_transition_ok := true;
      v_action_type   := 'transfer_in';
    END IF;

  ELSIF v_from_status = 'open' AND p_new_status = 'closed' THEN
    -- Slot closure workflow (Phase 6.7 — deferred; matrix entry exists).
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'open' AND p_new_status = 'hr_processing' THEN
    -- Skips pipeline / applicant context — blocked.
    v_transition_ok  := false;
    v_blocked_reason := 'open→hr_processing is blocked: slot must pass through pipeline first';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'hr_processing';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'occupied' THEN
    -- Skips HR Emploc onboarding compliance — blocked.
    v_transition_ok  := false;
    v_blocked_reason := 'pipeline→occupied is blocked: slot must pass through hr_processing first';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'closed' THEN
    -- Slot closure workflow (Phase 6.7 — deferred; matrix entry exists).
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'occupied' THEN
    -- Occupant required; into-occupied without a plantilla id is a data error.
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := 'hr_processing→occupied requires p_occupant_plantilla_id';
    ELSE
      v_transition_ok := true;
      v_action_type   := 'occupied';
    END IF;

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'open' THEN
    -- Applicant backout during HR Emploc; slot reopens without going back to pipeline.
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'pipeline' THEN
    -- No backward pipeline regression — emploc backout always goes to open.
    v_transition_ok  := false;
    v_blocked_reason := 'hr_processing→pipeline is blocked: emploc backout transitions to open, not pipeline';

  ELSIF v_from_status = 'occupied' AND p_new_status = 'open' THEN
    -- Resignation / ENDO / deactivation / transfer-out.
    -- action_type is determined by reason_code so slot_history is unambiguous.
    v_transition_ok := true;
    v_action_type   := CASE p_reason_code
                          WHEN 'TRANSFER_OUT' THEN 'transfer_out'
                          ELSE 'resigned'     -- covers RESIGNED, ENDO, NULL
                        END;

  ELSIF v_from_status = 'occupied' AND p_new_status IN ('pipeline', 'hr_processing') THEN
    -- Occupant must leave first (→ open) before re-recruiting.
    v_transition_ok  := false;
    v_blocked_reason := format(
      'occupied→%s is blocked: occupant must separate first (occupied→open), '
      'then the slot re-enters recruitment', p_new_status
    );

  ELSE
    -- Any other pair not covered above.
    v_transition_ok  := false;
    v_blocked_reason := format(
      'transition %s→%s is not in the valid transition matrix',
      v_from_status, p_new_status
    );
  END IF;

  -- ── 4. Return blocked result (non-blocking contract) ────────────────────────
  -- Workflow hooks must treat this as skip-and-log, never raise into the host RPC.
  IF NOT v_transition_ok THEN
    RETURN jsonb_build_object(
      'status',         'blocked',
      'slot_id',        p_slot_id,
      'from_status',    v_from_status,
      'to_status',      p_new_status,
      'blocked_reason', v_blocked_reason
    );
  END IF;

  -- ── 5. Apply slot update ─────────────────────────────────────────────────────
  UPDATE public.plantilla_slots
  SET
    slot_status                   = p_new_status,

    -- Occupant link: set when occupying, clear when leaving occupied state.
    current_occupant_plantilla_id = CASE
      WHEN p_new_status = 'occupied'
        THEN p_occupant_plantilla_id
      WHEN p_new_status IN ('open', 'pipeline', 'hr_processing', 'closed')
        THEN NULL
      ELSE current_occupant_plantilla_id   -- fallback (never reached with valid matrix)
    END,

    -- Closure metadata: stamp on transition to closed only.
    closure_reason_code           = CASE
      WHEN p_new_status = 'closed' THEN p_reason_code
      ELSE closure_reason_code
    END,
    closed_at                     = CASE
      WHEN p_new_status = 'closed' THEN now()
      ELSE closed_at
    END,
    closed_by                     = CASE
      WHEN p_new_status = 'closed' THEN p_performed_by
      ELSE closed_by
    END,

    -- Standard audit stamps.
    updated_at                    = now(),
    updated_by                    = p_performed_by

  WHERE id = p_slot_id;

  -- ── 6. Write one slot_history row (append-only) ─────────────────────────────
  -- One row per accepted transition.  new_value='open' on any true reopen
  -- (pipeline→open, hr_processing→open, occupied→open, transfer_out) correctly
  -- starts a new open episode for the shadow view's aging basis (Q5 design rule).
  v_history_id := gen_random_uuid();

  INSERT INTO public.slot_history (
    id,
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
    v_history_id,
    p_slot_id,
    v_slot.account_id,   -- denormalized from slot for scope-safe RLS
    v_action_type,
    v_from_status,
    p_new_status,
    p_reason_code,
    p_performed_by,
    p_remarks,
    now()
  );

  -- ── 7. Return success summary ─────────────────────────────────────────────────
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
  'Central helper for all plantilla_slots.slot_status transitions (Phase 6.0). '
  'Validates the transition matrix, updates slot metadata, and appends one slot_history '
  'row atomically. Returns JSONB: status=ok|no_op|blocked. '
  'NEVER raises for invalid transitions — workflow hooks must skip on blocked result. '
  'RAISES EXCEPTION for structural errors only (null slot_id, unknown status, slot not found). '
  'NOT YET WIRED into any existing RPC. Future hooks (Phase 6.1–6.5) must call this '
  'function instead of writing plantilla_slots directly.';


-- ============================================================
-- §2  GRANT
-- ============================================================
-- SECURITY DEFINER function; restrict direct call to
-- authenticated roles only. Anon must never reach this.

REVOKE ALL ON FUNCTION public.fn_set_slot_status(
  uuid, text, text, uuid, text, uuid
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_set_slot_status(
  uuid, text, text, uuid, text, uuid
) TO authenticated;


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — Function exists
--   SELECT routine_name, routine_type, security_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public'
--     AND routine_name = 'fn_set_slot_status';
--   -- Expected: 1 row, FUNCTION, DEFINER
--
-- V2 — Valid transition: open → pipeline
--   (Requires a slot in 'open' status. Replace <slot_id> with a real UUID.)
--   SELECT public.fn_set_slot_status('<slot_id>', 'pipeline');
--   -- Expected: {"status":"ok","from_status":"open","to_status":"pipeline","action_type":"pipeline",...}
--
-- V2b — Idempotent re-call (same status)
--   SELECT public.fn_set_slot_status('<slot_id>', 'pipeline');
--   -- Expected: {"status":"no_op","from_status":"pipeline","to_status":"pipeline"}
--
-- V3 — Blocked transition: pipeline → occupied (skips hr_processing)
--   SELECT public.fn_set_slot_status('<pipeline_slot_id>', 'occupied',
--     NULL, NULL, NULL, gen_random_uuid());
--   -- Expected: {"status":"blocked","blocked_reason":"pipeline→occupied is blocked:..."}
--
-- V4 — Blocked transition: closed → open (terminal)
--   SELECT public.fn_set_slot_status('<closed_slot_id>', 'open');
--   -- Expected: {"status":"blocked","blocked_reason":"closed is terminal under automation;..."}
--
-- V5 — slot_history written only on successful transition
--   SELECT sh.*
--   FROM public.slot_history sh
--   WHERE sh.slot_id = '<slot_id>'
--   ORDER BY sh.created_at DESC
--   LIMIT 5;
--   -- Expected: one row per accepted transition (V2 above), none for blocked or no-op
--
-- V6 — No existing UI behavior changed (baseline vacancy counts unchanged)
--   SELECT count(*) FROM public.vacancies WHERE status NOT IN ('Filled','Cancelled');
--   -- Compare to pre-migration count; must be identical.
--
-- V7 — No existing slot statuses mutated by this migration
--   SELECT slot_status, count(*) FROM public.plantilla_slots GROUP BY 1 ORDER BY 1;
--   -- Compare to pre-migration snapshot; must be identical (function definition only).
-- ============================================================
