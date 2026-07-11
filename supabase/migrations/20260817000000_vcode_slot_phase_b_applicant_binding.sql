-- ============================================================
-- OHM2026_0041 — VCODE ↔ Slot Phase B: Applicant-to-Slot Binding
-- Migration:  20260817000000_vcode_slot_phase_b_applicant_binding.sql
-- Depends on:
--   20260816000000_vcode_slot_phase_a_schema_bridge.sql
--     (applicants.slot_id FK, plantilla_slots.slot_ordinal, composite unique)
--   20260813000001_wire_open_pipeline_slot_transitions.sql
--     (fn_sync_vacancy_slot_open_pipeline, fn_update_applicant_status,
--      create_applicant_and_link_to_vacancy — Phase 6.1 base)
--   20260812000000_fn_set_slot_status.sql
--     (fn_set_slot_status — central transition helper)
--   20260616000000_restore_fn_is_active_vacancy_applicant_status.sql
--     (fn_is_active_vacancy_applicant_status — canonical active predicate)
-- ============================================================
-- Scope: Phase B applicant-to-slot binding.
--
-- Authorising documents (locked):
--   docs/architecture/vcode_slot_bridge_redesign.md  (OHM2026_0035) §4, §5, §9
--   docs/architecture/vcode_slot_phase_b_applicant_binding_plan.md (OHM2026_0040)
--
-- Phase B makes applicants.slot_id the source of truth for applicant-slot
-- ownership and retires all legacy_vcode-only LIMIT 1 routing for the
-- open ↔ pipeline lifecycle. Phase A shipped the columns (slot_id FK,
-- slot_ordinal, composite unique) as empty. Phase B fills them.
--
-- What this migration does:
--   B1  Backfill applicants.slot_id for existing active applicants
--   B2  Partial unique: one active applicant per slot
--   B3  Reconcile slot status to bound reality (safety step, expected no-op)
--   B4  fn_release_applicant_slot — new internal non-blocking helper
--   B5  Replace create_applicant_and_link_to_vacancy — slot-aware claim
--   B6  Replace fn_update_applicant_status — slot-aware terminal release
--   B7  GRANTs
--   B8  Post-migration validation queries (manual, in comments)
--
-- What this migration deliberately does NOT do:
--   • Modify Flutter UI or any client-side code
--   • Modify HR Emploc binding (Phase C) or hr_emploc.slot_id
--   • Modify shadow view aggregation (Phase D)
--   • Modify HC request VCODE generation
--   • Modify transfer, closure, or roving logic
--   • Recreate or apply 20260815000000_one_store_one_vcode.sql (BLOCKED)
--   • Modify confirm_applicant_onboard or fn_sync_slot_to_hr_processing (Phase 6.2)
--   • Modify plantilla.slot_id (deferred)
--
-- Roving slots and VCODEs with no slot retain the legacy path throughout.
--
-- ============================================================
-- §B0 — Pre-migration gate (run MANUALLY before applying)
-- ============================================================
--
-- Gate 1: applicants.slot_id all NULL (Phase A shipped empty).
--   SELECT COUNT(*) FROM public.applicants WHERE slot_id IS NOT NULL;
--   -- Expected: 0. Any non-zero = prior partial run; reconcile before re-applying.
--
-- Gate 2: 1:1 precondition — at most 1 non-roving slot per VCODE.
--   SELECT legacy_vcode, COUNT(*) AS slot_count
--     FROM public.plantilla_slots
--     WHERE legacy_vcode IS NOT NULL AND is_roving = false
--     GROUP BY legacy_vcode HAVING COUNT(*) > 1;
--   -- Expected: 0 rows. Any rows = Phase A composite unique violated; stop.
--
-- Gate 3: No active applicant double-bound to same VCODE (uq_applicants_one_active_per_vcode).
--   SELECT vacancy_vcode, COUNT(*) FROM public.applicants
--     WHERE COALESCE(is_archived, false) = false
--       AND public.fn_is_active_vacancy_applicant_status(status)
--     GROUP BY vacancy_vcode HAVING COUNT(*) > 1;
--   -- Expected: 0 rows. (Uniqueness already enforced by uq_applicants_one_active_per_vcode.)
--
-- Gate 4: P1–P8 parity baseline GREEN (OHM2026_0039 state).
--   -- Re-run the P1–P8 parity suite; confirm shadow == legacy baseline.
-- ============================================================


-- ============================================================
-- §B1 — Backfill applicants.slot_id for active applicants
-- ============================================================
-- Binds each active (pipeline-active, non-archived, non-roving) applicant
-- to the single non-roving slot for its VCODE.
--
-- Data is 1:1 today (Phase A verified: 22 slots, each VCODE ≤ 1 slot,
-- all ordinals = 1). The subquery ORDER BY is N-slot-safe: it always
-- picks slot_ordinal=1 (the only slot per VCODE in the current dataset).
--
-- Terminal applicants: left NULL (audit trail not required at this phase;
-- Phase C may backfill confirmed_onboard applicants if needed).
--
-- Roving slots (is_roving = true): excluded — NULL slot_id preserved,
-- legacy path retained (OHM2026_0017 carve-out).

UPDATE public.applicants a
SET
  slot_id    = (
    SELECT ps.id
    FROM   public.plantilla_slots ps
    WHERE  ps.legacy_vcode = a.vacancy_vcode
      AND  ps.is_roving    = false
    ORDER  BY ps.slot_ordinal ASC, ps.created_at ASC, ps.id ASC
    LIMIT  1
  ),
  updated_at = NOW()
WHERE a.slot_id IS NULL
  AND COALESCE(a.is_archived, false) = false
  AND public.fn_is_active_vacancy_applicant_status(a.status)
  AND EXISTS (
    SELECT 1 FROM public.plantilla_slots ps
    WHERE  ps.legacy_vcode = a.vacancy_vcode
      AND  ps.is_roving    = false
  );


-- ============================================================
-- §B2 — Partial unique: one active applicant per slot
-- ============================================================
-- Structural guard for the invariant "at most one pipeline-active
-- applicant owns a given slot at any moment."
--
-- Terminal applicants retain slot_id for audit trail and are not subject
-- to this constraint (they're excluded by the WHERE clause).
--
-- Built AFTER §B1 so the index validates the backfill is clean.
-- Coexists with uq_applicants_one_active_per_vcode (1:1 era guard);
-- that index remains and is compatible while data stays 1:1. Phase F
-- (N-slot) will need to drop uq_applicants_one_active_per_vcode, but
-- that is explicitly out of Phase B scope.

CREATE UNIQUE INDEX IF NOT EXISTS uq_applicants_one_active_per_slot
  ON public.applicants (slot_id)
  WHERE slot_id IS NOT NULL
    AND COALESCE(is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(status);

COMMENT ON INDEX public.uq_applicants_one_active_per_slot IS
  'Phase B (OHM2026_0041): enforces one active (pipeline-active) applicant '
  'per plantilla_slots row. Terminal applicants retain slot_id for audit. '
  'Partial: slot_id IS NOT NULL AND is_archived=false AND active status. '
  'Coexists with uq_applicants_one_active_per_vcode while data is 1:1.';


-- ============================================================
-- §B3 — Reconcile slot status to bound reality (safety step)
-- ============================================================
-- After §B1 backfill, slot status and applicant binding should already
-- be in lockstep (Phase 6.1 fn_sync_vacancy_slot_open_pipeline maintained
-- this). This DO block catches any pre-existing drift and corrects it via
-- fn_set_slot_status (which writes slot_history for auditability).
--
-- Expected: both loops execute zero iterations on clean data.
-- Any RAISE NOTICE output signals a pre-existing discrepancy that was
-- corrected — review the slot_history rows written by this reconcile.

DO $$
DECLARE
  v_slot   record;
  v_result jsonb;
BEGIN
  -- Case A: 'pipeline' slot with no active bound applicant → reopen
  FOR v_slot IN
    SELECT ps.id, ps.legacy_vcode, ps.slot_ordinal
    FROM   public.plantilla_slots ps
    WHERE  ps.slot_status = 'pipeline'
      AND  ps.is_roving   = false
      AND  NOT EXISTS (
             SELECT 1 FROM public.applicants a
             WHERE  a.slot_id = ps.id
               AND  public.fn_is_active_vacancy_applicant_status(a.status)
               AND  COALESCE(a.is_archived, false) = false
           )
  LOOP
    v_result := public.fn_set_slot_status(
      p_slot_id    => v_slot.id,
      p_new_status => 'open',
      p_remarks    => format(
        'Phase B §B3 reconcile: pipeline slot with no active applicant / '
        'legacy_vcode=%s slot_ordinal=%s',
        v_slot.legacy_vcode, v_slot.slot_ordinal
      )
    );
    RAISE NOTICE
      'B3 reconcile (pipeline→open): slot=% vcode=% ordinal=% result=%',
      v_slot.id, v_slot.legacy_vcode, v_slot.slot_ordinal, v_result;
  END LOOP;

  -- Case B: 'open' slot that has an active bound applicant → set pipeline
  FOR v_slot IN
    SELECT ps.id, ps.legacy_vcode, ps.slot_ordinal
    FROM   public.plantilla_slots ps
    WHERE  ps.slot_status = 'open'
      AND  ps.is_roving   = false
      AND  EXISTS (
             SELECT 1 FROM public.applicants a
             WHERE  a.slot_id = ps.id
               AND  public.fn_is_active_vacancy_applicant_status(a.status)
               AND  COALESCE(a.is_archived, false) = false
           )
  LOOP
    v_result := public.fn_set_slot_status(
      p_slot_id    => v_slot.id,
      p_new_status => 'pipeline',
      p_remarks    => format(
        'Phase B §B3 reconcile: open slot with active applicant / '
        'legacy_vcode=%s slot_ordinal=%s',
        v_slot.legacy_vcode, v_slot.slot_ordinal
      )
    );
    RAISE NOTICE
      'B3 reconcile (open→pipeline): slot=% vcode=% ordinal=% result=%',
      v_slot.id, v_slot.legacy_vcode, v_slot.slot_ordinal, v_result;
  END LOOP;
END;
$$;


-- ============================================================
-- §B4 — fn_release_applicant_slot (new internal non-blocking helper)
-- ============================================================
-- Called after a bound applicant goes terminal. If no other active
-- applicant still holds the slot, transitions the slot pipeline → open
-- (preserving slot_ordinal — the locked reopen rule).
--
-- Non-blocking: NEVER RAISES. A slot release failure must not roll back
-- the host applicant status change.
--
-- Arguments
-- ---------
--   p_slot_id      — the exact slot the departing applicant owns.
--   p_performed_by — acting user UUID for slot_history.performed_by.
--
-- Returns JSONB from fn_set_slot_status, or NULL if skipped/error.

CREATE OR REPLACE FUNCTION public.fn_release_applicant_slot(
  p_slot_id      uuid,
  p_performed_by uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Phase B — non-blocking slot release on applicant terminal (OHM2026_0041).

  After the host fn_update_applicant_status has already written the
  terminal status, this function checks whether any other active applicant
  still holds p_slot_id. If none remain, the slot transitions pipeline → open
  (aging restarts for the reopened slot, per Phase B design §Q6).

  The check runs AFTER the host status write so the count reflects the
  new state (the departing applicant is no longer pipeline-active).

  Reason code: NULL (pipeline→open reopen carries no reason code at the
  pipeline layer — backout/rejection is captured on the applicant row, not
  on slot_history; see vcode_slot_phase_b_applicant_binding_plan.md §Q7).
*/
DECLARE
  v_active_cnt bigint;
  v_result     jsonb;
BEGIN
  IF p_slot_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Count active applicants still bound to this slot (post-terminal write).
  SELECT COUNT(*) INTO v_active_cnt
  FROM   public.applicants
  WHERE  slot_id = p_slot_id
    AND  public.fn_is_active_vacancy_applicant_status(status)
    AND  COALESCE(is_archived, false) = false;

  IF v_active_cnt > 0 THEN
    -- Another active applicant still holds the slot; do not reopen.
    RETURN jsonb_build_object(
      'status',    'no_op',
      'reason',    'other_active_applicant_remains',
      'slot_id',   p_slot_id,
      'remaining', v_active_cnt
    );
  END IF;

  -- No remaining active applicant — release: pipeline → open.
  SELECT public.fn_set_slot_status(
    p_slot_id      => p_slot_id,
    p_new_status   => 'open',
    p_reason_code  => NULL,
    p_performed_by => p_performed_by,
    p_remarks      => format(
      'Phase B release / last active applicant went terminal / slot=%s',
      p_slot_id
    )
  ) INTO v_result;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_release_applicant_slot: error for slot=% — % (sqlstate=%)',
    p_slot_id, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_release_applicant_slot(uuid, uuid) IS
  'Phase B (OHM2026_0041) — non-blocking slot release on applicant terminal. '
  'If no other active applicant remains bound to p_slot_id, transitions '
  'pipeline → open (aging restarts). NEVER RAISES. '
  'Caller: fn_update_applicant_status (terminal status path).';


-- ============================================================
-- §B5 — Replace create_applicant_and_link_to_vacancy (slot-aware claim)
-- ============================================================
-- Source: 20260813000001_wire_open_pipeline_slot_transitions.sql §3
--         (Phase 6.1 version — the basis patched here).
--
-- Phase B changes (all others are IDENTICAL to Phase 6.1):
--   1. Before INSERT: check if VCODE has non-roving slots.
--      a. If YES: claim lowest open slot (ORDER BY slot_ordinal, created_at, id
--                 LIMIT 1 FOR UPDATE SKIP LOCKED); reject if none available.
--      b. If NO:  skip slot binding — legacy path (no slot era).
--   2. INSERT applicant with slot_id = claimed slot id (or NULL for legacy).
--   3. After INSERT: if slot claimed → fn_set_slot_status(slot, 'pipeline')
--                    directly (validated, blocking for slot-aware path).
--                    else → fn_sync_vacancy_slot_open_pipeline (legacy no-op).
--   4. fn_sync_vacancy_slot_open_pipeline call removed for slot-aware path
--      (replaced by direct fn_set_slot_status above).
--
-- Return shape: uuid (applicant id) — unchanged.
-- RBAC, scope, field validation: unchanged.
-- Error code for no-open-slot: SQLSTATE P0001 (raise_exception).

CREATE OR REPLACE FUNCTION public.create_applicant_and_link_to_vacancy(
  p_vacancy_id      uuid,
  p_last_name       text,
  p_first_name      text,
  p_middle_name     text,
  p_contact_number  text,
  p_application_date date,
  p_source_channel  text DEFAULT 'Walk-in',
  p_comment         text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v              public.vacancies%ROWTYPE;
  new_id         uuid;
  v_claimed_slot uuid;
  v_claimed_ord  smallint;
  v_slot_count   bigint;
  v_slot_result  jsonb;
BEGIN
  IF NOT public.i_am_ops() THEN
    RAISE EXCEPTION 'forbidden: ops only';
  END IF;

  -- Required-field guard
  IF p_last_name IS NULL OR p_first_name IS NULL OR p_middle_name IS NULL
     OR p_contact_number IS NULL OR p_application_date IS NULL THEN
    RAISE EXCEPTION 'last_name, first_name, middle_name, contact_number, application_date are required';
  END IF;

  -- Format guard
  PERFORM public.fn_validate_ph_contact_number(p_contact_number);

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'vacancy not found'; END IF;
  IF v.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'vacancy archived'; END IF;
  IF COALESCE(v.has_pending_closure, false) THEN
    RAISE EXCEPTION 'vacancy is locked pending deletion';
  END IF;
  IF NOT (v.account = ANY (public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: out of scope';
  END IF;

  -- ── Phase B: slot-aware claim ─────────────────────────────────────────────
  -- Count non-roving slots for this VCODE (roving skipped — carve-out).
  SELECT COUNT(*) INTO v_slot_count
  FROM   public.plantilla_slots
  WHERE  legacy_vcode = v.vcode
    AND  is_roving    = false;

  IF v_slot_count > 0 THEN
    -- VCODE has slots — claim the lowest available open slot.
    -- FOR UPDATE SKIP LOCKED: concurrent adds take different slots instead
    -- of colliding; uq_applicants_one_active_per_slot is the backstop.
    SELECT id, slot_ordinal
      INTO v_claimed_slot, v_claimed_ord
    FROM   public.plantilla_slots
    WHERE  legacy_vcode = v.vcode
      AND  slot_status  = 'open'
      AND  is_roving    = false
    ORDER  BY slot_ordinal ASC, created_at ASC, id ASC
    LIMIT  1
    FOR UPDATE SKIP LOCKED;

    IF v_claimed_slot IS NULL THEN
      -- All slots are occupied/pipeline/hr_processing/closed — hard reject.
      RAISE EXCEPTION
        'no_open_slot: VCODE % has % slot(s) but none are open. '
        'All headcount is in pipeline, processing, filled, or closed. '
        'Request additional HC before adding another applicant.',
        v.vcode, v_slot_count
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  -- If v_slot_count = 0: v_claimed_slot stays NULL → legacy path below.
  -- ─────────────────────────────────────────────────────────────────────────

  INSERT INTO public.applicants (
    vacancy_vcode, last_name, first_name, middle_name, full_name,
    contact_number, application_date, source_channel, comment,
    status, slot_id, created_by
  ) VALUES (
    v.vcode, p_last_name, p_first_name, p_middle_name,
    p_last_name || ', ' || p_first_name || ' ' || p_middle_name,
    p_contact_number, p_application_date, p_source_channel, p_comment,
    'New', v_claimed_slot, public.get_my_profile_id()
  ) RETURNING id INTO new_id;

  -- self-master if no link provided
  UPDATE public.applicants SET master_applicant_id = new_id WHERE id = new_id;

  PERFORM public.log_audit_event(
    'vacancy_module', 'INSERT', new_id,
    NULL,
    jsonb_build_object('action', 'create_applicant', 'vacancy_id', v.id)
  );

  -- ── Phase B: slot status transition ──────────────────────────────────────
  IF v_claimed_slot IS NOT NULL THEN
    -- Slot-aware path: direct open → pipeline transition for the claimed slot.
    -- This is a validated (blocking) call — if the transition is unexpectedly
    -- blocked the insert rolls back, surfacing a data integrity issue.
    SELECT public.fn_set_slot_status(
      p_slot_id      => v_claimed_slot,
      p_new_status   => 'pipeline',
      p_reason_code  => NULL,
      p_performed_by => public.get_my_profile_id(),
      p_remarks      => format(
        'Phase B / create_applicant_and_link_to_vacancy / VCODE=%s / '
        'applicant=%s / slot_ordinal=%s',
        v.vcode, new_id, v_claimed_ord
      )
    ) INTO v_slot_result;

    IF (v_slot_result->>'status') = 'blocked' THEN
      RAISE EXCEPTION
        'slot_transition_blocked: claimed slot % could not transition to '
        'pipeline — %. This indicates a data integrity issue; resolve '
        'slot status before adding applicants.',
        v_claimed_slot, v_slot_result->>'blocked_reason'
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- No slots for this VCODE — legacy non-blocking sync (no-op if no slot).
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v.vcode,
      p_performed_by => public.get_my_profile_id(),
      p_source_fn    => 'create_applicant_and_link_to_vacancy'
    );
  END IF;
  -- ─────────────────────────────────────────────────────────────────────────

  RETURN new_id;
END;
$$;

COMMENT ON FUNCTION public.create_applicant_and_link_to_vacancy(uuid, text, text, text, text, date, text, text) IS
  'Creates and links a new applicant to a vacancy. '
  'Phase B (OHM2026_0041): claims the lowest open non-roving slot for the VCODE '
  'before INSERT (FOR UPDATE SKIP LOCKED); binds applicants.slot_id; transitions '
  'the claimed slot open→pipeline via fn_set_slot_status. '
  'Rejects (SQLSTATE P0001) if the VCODE has slots but none are open. '
  'VCODEs with no slots use the legacy fn_sync_vacancy_slot_open_pipeline path. '
  'Roving slots are skipped (legacy path).';


-- ============================================================
-- §B6 — Replace fn_update_applicant_status (slot-aware terminal release)
-- ============================================================
-- Source: 20260813000001_wire_open_pipeline_slot_transitions.sql §2
--         (Phase 6.1 version — the basis patched here).
--
-- Phase B changes (all others are IDENTICAL to Phase 6.1):
--   1. After the applicant status write, check v_app.slot_id:
--      a. slot_id IS NOT NULL AND new status is terminal:
--         → call fn_release_applicant_slot(v_app.slot_id) — per-slot release
--           (pipeline → open if no other active applicant remains).
--         → does NOT call fn_sync_vacancy_slot_open_pipeline.
--      b. slot_id IS NOT NULL AND new status is NOT terminal:
--         → no slot status change; slot stays as-is (pipeline for active
--           transitions; Phase 6.2 / confirm_applicant_onboard handles
--           pipeline→hr_processing for Confirmed Onboard).
--      c. slot_id IS NULL (unbound/legacy/roving applicant):
--         → fall back to fn_sync_vacancy_slot_open_pipeline (Phase 6.1 legacy path).
--
-- Rationale: per-slot release eliminates VCODE LIMIT 1 routing, enforces
-- the "exact slot, slot_ordinal preserved" reopen rule, and is N-slot-correct.
-- The legacy fallback preserves behavior for VCODEs with no slot and roving.
--
-- Return type: void — unchanged.
-- RBAC, scope, field validation, history write: unchanged.

CREATE OR REPLACE FUNCTION public.fn_update_applicant_status(
  p_applicant_id uuid,
  p_new_status   text,
  p_remarks      text DEFAULT NULL,
  p_reason_id    uuid DEFAULT NULL,
  p_reason_type  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level         int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id    uuid := public.get_my_profile_id();
  v_app           public.applicants%ROWTYPE;
  v_to_opt        public.applicant_status_options%ROWTYPE;
  v_from_code     text;
  v_old_status    text;
  v_from_terminal boolean;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Validate reason_type ─────────────────────────────────────
  IF p_reason_type IS NOT NULL
     AND p_reason_type NOT IN ('backout', 'rejected', 'other') THEN
    RAISE EXCEPTION 'invalid reason_type: %. Must be backout | rejected | other', p_reason_type
      USING ERRCODE = '22023';
  END IF;

  -- ── Resolve target status option ─────────────────────────────
  SELECT * INTO v_to_opt
    FROM public.applicant_status_options
   WHERE status_code = p_new_status
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid or inactive status_code: %', p_new_status
      USING ERRCODE = '22023';
  END IF;

  -- ── Block system-only targets for non-Super Admin ────────────
  IF v_to_opt.is_system_only AND v_level != 100 THEN
    RAISE EXCEPTION 'status % is system-only and cannot be set manually', p_new_status
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock applicant ──────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  v_old_status := COALESCE(v_app.status, 'New');

  -- ── Resolve current status_code from stored label ────────────
  SELECT status_code INTO v_from_code
    FROM public.applicant_status_options
   WHERE label = v_old_status
  LIMIT 1;

  IF v_from_code IS NULL THEN
    v_from_code := 'new';
  END IF;

  -- ── Terminal source guard ─────────────────────────────────────
  SELECT is_terminal INTO v_from_terminal
    FROM public.applicant_status_options
   WHERE status_code = v_from_code;

  IF COALESCE(v_from_terminal, false) THEN
    IF v_level != 100 THEN
      RAISE EXCEPTION
        'cannot transition from terminal status "%" without Super Admin authority',
        v_old_status
        USING ERRCODE = '22023';
    END IF;
  ELSE
    -- RELAXED TRANSITION RULE (OHM2026_2025): from any active (non-terminal)
    -- status, any non-system-only active target is allowed.
    NULL;
  END IF;

  -- ── Scope check ───────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Apply status update ───────────────────────────────────────
  UPDATE public.applicants
  SET
    status     = v_to_opt.label,
    updated_at = NOW(),
    updated_by = v_profile_id
  WHERE id = p_applicant_id;

  -- ── Write immutable status history ────────────────────────────
  INSERT INTO public.applicant_status_history (
    applicant_id,
    from_status,
    to_status,
    reason_id,
    reason_type,
    remarks,
    changed_by,
    changed_at,
    source_module
  ) VALUES (
    p_applicant_id,
    v_old_status,
    v_to_opt.label,
    p_reason_id,
    p_reason_type,
    p_remarks,
    v_profile_id,
    NOW(),
    'vacancy'
  );

  -- ── Phase B: slot-aware open↔pipeline sync ────────────────────
  -- Route by v_app.slot_id when the applicant is bound to a slot.
  -- Fall back to legacy fn_sync_vacancy_slot_open_pipeline for unbound
  -- applicants (no-slot VCODEs, roving, or pre-backfill legacy rows).
  IF v_app.slot_id IS NOT NULL THEN
    IF COALESCE(v_to_opt.is_terminal, false) THEN
      -- Terminal transition: release the specific bound slot.
      -- fn_release_applicant_slot NEVER raises; a slot error will not
      -- roll back this function's applicant or history writes.
      -- Reads active count AFTER the status write above, so the departing
      -- applicant is already excluded from the count.
      PERFORM public.fn_release_applicant_slot(
        p_slot_id      => v_app.slot_id,
        p_performed_by => v_profile_id
      );
    END IF;
    -- Non-terminal with bound slot: no slot status change.
    -- • Pipeline-active transitions (e.g. New→For Interview): slot stays pipeline.
    -- • Confirmed Onboard / Endorsed to Ops: slot stays pipeline;
    --   pipeline→hr_processing is Phase 6.2 (confirm_applicant_onboard RPC).
  ELSE
    -- No slot bound (legacy no-slot VCODE, roving, or unbackfilled row).
    -- Phase 6.1 legacy sync: counts active applicants for the VCODE and
    -- transitions the slot open↔pipeline (NEVER RAISES).
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v_app.vacancy_vcode,
      p_performed_by => v_profile_id,
      p_source_fn    => 'fn_update_applicant_status'
    );
  END IF;

END;
$$;

COMMENT ON FUNCTION public.fn_update_applicant_status(uuid, text, text, uuid, text) IS
  'Updates an applicant status with RBAC, scope, and history enforcement. '
  'Phase B (OHM2026_0041): routes slot release by applicants.slot_id for '
  'bound applicants — terminal status calls fn_release_applicant_slot (exact slot, '
  'pipeline→open, non-blocking). Non-terminal bound transitions leave slot untouched. '
  'Unbound applicants (no-slot VCODEs, roving) fall back to the Phase 6.1 '
  'fn_sync_vacancy_slot_open_pipeline legacy path (also non-blocking).';


-- ============================================================
-- §B7 — GRANTs
-- ============================================================

-- fn_release_applicant_slot: internal helper, authenticated only.
REVOKE ALL ON FUNCTION public.fn_release_applicant_slot(uuid, uuid)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_release_applicant_slot(uuid, uuid)
  TO authenticated;

-- Existing GRANTs on patched functions (unchanged from Phase 6.1):
GRANT EXECUTE ON FUNCTION public.fn_update_applicant_status(uuid, text, text, uuid, text)
  TO authenticated;

-- create_applicant_and_link_to_vacancy: inherited from remote_schema;
-- no change required.


-- ============================================================
-- §B8 — Post-migration validation queries (run manually)
-- ============================================================
--
-- ── Structural checks ────────────────────────────────────────────────────
--
-- V1 — uq_applicants_one_active_per_slot index exists and is partial.
--   SELECT indexname, indexdef
--     FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'applicants'
--       AND indexname  = 'uq_applicants_one_active_per_slot';
--   -- Expected: 1 row; indexdef contains WHERE clause with
--   --           slot_id IS NOT NULL, is_archived, fn_is_active_vacancy_applicant_status.
--
-- V2 — fn_release_applicant_slot exists with correct signature.
--   SELECT routine_name, routine_type, security_type
--     FROM information_schema.routines
--     WHERE routine_schema = 'public'
--       AND routine_name   = 'fn_release_applicant_slot';
--   -- Expected: 1 row, FUNCTION, DEFINER.
--
-- V3 — create_applicant_and_link_to_vacancy body includes Phase B slot claim.
--   SELECT prosrc LIKE '%fn_release_applicant_slot%' OR prosrc LIKE '%v_claimed_slot%'
--     FROM pg_proc
--     WHERE proname      = 'create_applicant_and_link_to_vacancy'
--       AND pronamespace = 'public'::regnamespace;
--   -- Expected: true.
--
-- V4 — fn_update_applicant_status body includes Phase B slot-aware block.
--   SELECT prosrc LIKE '%fn_release_applicant_slot%'
--     FROM pg_proc
--     WHERE proname      = 'fn_update_applicant_status'
--       AND pronamespace = 'public'::regnamespace;
--   -- Expected: true.
--
-- ── Data invariant checks (B1–B10 parity) ───────────────────────────────
--
-- B1 — No slot has >1 active applicant.
--   SELECT slot_id, COUNT(*) AS cnt
--     FROM public.applicants
--     WHERE slot_id IS NOT NULL
--       AND COALESCE(is_archived, false) = false
--       AND public.fn_is_active_vacancy_applicant_status(status)
--     GROUP BY slot_id HAVING COUNT(*) > 1;
--   -- Expected: 0 rows.
--
-- B2 — Every pipeline slot has exactly 1 active bound applicant.
--   SELECT ps.id, ps.legacy_vcode,
--          COUNT(a.id) AS active_applicants
--     FROM public.plantilla_slots ps
--     LEFT JOIN public.applicants a
--       ON a.slot_id = ps.id
--          AND public.fn_is_active_vacancy_applicant_status(a.status)
--          AND COALESCE(a.is_archived, false) = false
--     WHERE ps.slot_status = 'pipeline'
--       AND ps.is_roving   = false
--     GROUP BY ps.id, ps.legacy_vcode
--     HAVING COUNT(a.id) != 1;
--   -- Expected: 0 rows.
--
-- B3 — Every open slot has 0 active bound applicants.
--   SELECT ps.id, ps.legacy_vcode, COUNT(a.id) AS active_applicants
--     FROM public.plantilla_slots ps
--     LEFT JOIN public.applicants a
--       ON a.slot_id = ps.id
--          AND public.fn_is_active_vacancy_applicant_status(a.status)
--          AND COALESCE(a.is_archived, false) = false
--     WHERE ps.slot_status = 'open'
--       AND ps.is_roving   = false
--     GROUP BY ps.id, ps.legacy_vcode
--     HAVING COUNT(a.id) > 0;
--   -- Expected: 0 rows.
--
-- B4 — Every active non-roving applicant has non-NULL slot_id.
--   SELECT COUNT(*) AS unbound_active
--     FROM public.applicants a
--     WHERE a.slot_id IS NULL
--       AND COALESCE(a.is_archived, false) = false
--       AND public.fn_is_active_vacancy_applicant_status(a.status)
--       AND EXISTS (
--         SELECT 1 FROM public.plantilla_slots ps
--         WHERE ps.legacy_vcode = a.vacancy_vcode
--           AND ps.is_roving    = false
--       );
--   -- Expected: 0.
--
-- B5 — Binding matches VCODE (slot.legacy_vcode = applicant.vacancy_vcode).
--   SELECT COUNT(*) AS mismatched
--     FROM public.applicants a
--     JOIN public.plantilla_slots ps ON ps.id = a.slot_id
--     WHERE ps.legacy_vcode != a.vacancy_vcode;
--   -- Expected: 0.
--
-- B6 — No active applicant bound to a non-pipeline slot
--      (hr_processing, occupied, closed — Phase B only owns open↔pipeline).
--   SELECT a.id, a.status, ps.slot_status
--     FROM public.applicants a
--     JOIN public.plantilla_slots ps ON ps.id = a.slot_id
--     WHERE public.fn_is_active_vacancy_applicant_status(a.status)
--       AND COALESCE(a.is_archived, false) = false
--       AND ps.slot_status NOT IN ('open', 'pipeline');
--   -- Expected: 0 rows.
--
-- B7 — Slot-side vs applicant-side active counts agree per VCODE.
--   SELECT
--     slot_side.legacy_vcode,
--     slot_side.pipeline_slots,
--     app_side.active_applicants
--   FROM (
--     SELECT legacy_vcode, COUNT(*) AS pipeline_slots
--       FROM public.plantilla_slots
--       WHERE slot_status = 'pipeline' AND is_roving = false
--       GROUP BY legacy_vcode
--   ) slot_side
--   FULL OUTER JOIN (
--     SELECT vacancy_vcode, COUNT(DISTINCT slot_id) AS active_applicants
--       FROM public.applicants
--       WHERE slot_id IS NOT NULL
--         AND COALESCE(is_archived, false) = false
--         AND public.fn_is_active_vacancy_applicant_status(status)
--       GROUP BY vacancy_vcode
--   ) app_side ON app_side.vacancy_vcode = slot_side.legacy_vcode
--   WHERE COALESCE(slot_side.pipeline_slots, 0)
--      != COALESCE(app_side.active_applicants, 0);
--   -- Expected: 0 rows.
--
-- B8 — FK integrity: no orphan slot_id in applicants.
--   SELECT COUNT(*) AS orphans
--     FROM public.applicants a
--     LEFT JOIN public.plantilla_slots ps ON ps.id = a.slot_id
--     WHERE a.slot_id IS NOT NULL AND ps.id IS NULL;
--   -- Expected: 0.
--
-- B9 — Roving applicants have NULL slot_id.
--   SELECT COUNT(*) AS roving_with_slot
--     FROM public.applicants a
--     JOIN public.plantilla_slots ps
--       ON ps.legacy_vcode = a.vacancy_vcode
--       AND ps.is_roving   = true
--     WHERE a.slot_id IS NOT NULL;
--   -- Expected: 0 (roving applicants should remain unbound).
--
-- B10 — P1–P8 (OHM2026_0016/0039) re-run: open↔pipeline counts unchanged
--       except for intended slot status moves from §B3 reconcile.
--   -- Re-run the P1–P8 parity suite. Only open↔pipeline counts should differ
--   -- (if §B3 corrected any discrepancy). hr_processing, occupied, closed: unchanged.
--
-- ── Functional smoke tests ──────────────────────────────────────────────
--
-- S1 — Add Applicant claims a slot and moves it to pipeline.
--   (Call create_applicant_and_link_to_vacancy for a VCODE with an open slot.)
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: 'pipeline'.
--   SELECT slot_id FROM public.applicants WHERE id = '<new_applicant_id>';
--   -- Expected: non-NULL uuid (the claimed slot).
--   SELECT action_type, new_value FROM public.slot_history
--     WHERE slot_id = '<slot_id>' ORDER BY created_at DESC LIMIT 1;
--   -- Expected: action_type='pipeline', new_value='pipeline'.
--
-- S2 — Add Applicant to VCODE with all slots occupied returns error.
--   (Manually set all slots for a test VCODE to 'pipeline', then attempt add.)
--   -- Expected: RAISE EXCEPTION with SQLSTATE P0001, message contains 'no_open_slot'.
--
-- S3 — Terminal status releases slot back to open.
--   (Set the applicant from S1 to backout/failed via fn_update_applicant_status.)
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: 'open'.
--   SELECT action_type, new_value FROM public.slot_history
--     WHERE slot_id = '<slot_id>' ORDER BY created_at DESC LIMIT 1;
--   -- Expected: action_type='reopened', new_value='open'.
--
-- S4 — Non-terminal status change does not move slot.
--   (Set applicant status to 'for_interview' via fn_update_applicant_status.)
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: unchanged (still 'pipeline').
--
-- S5 — Add Applicant to no-slot VCODE succeeds (legacy path).
--   (Call for a VCODE that has no plantilla_slots row.)
--   SELECT id FROM public.applicants WHERE id = '<new_applicant_id>';
--   -- Expected: row exists, slot_id IS NULL.
-- ============================================================
