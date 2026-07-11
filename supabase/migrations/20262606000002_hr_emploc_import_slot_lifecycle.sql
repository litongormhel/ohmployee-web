-- Migration: 20262606000002_hr_emploc_import_slot_lifecycle
-- Created: 2026-06-26
-- Prompt ID: ohm#7xq2m9p4
-- Purpose: Wire the four HR Emploc Import RPCs into the Plantilla Slot lifecycle
--          per ADR-001 Slot-First Architecture Rules 4, 5, and 8.
--
-- Root cause: submit/approve/reject/rollback performed zero slot mutations.
--   Slots were validated but never reserved; hr_emploc.slot_id was never set;
--   vacancies were never closed on approval; rollback never reopened vacancies.
--
-- What this migration implements:
--   §1  fn_set_slot_status — extend transition matrix with two import-specific paths:
--         open → hr_processing  (action_type: import_reserved)   ← B1 approved
--         hr_processing → pipeline (action_type: import_rejected) ← C1 approved
--   §2  submit_hr_emploc_import — Pass 2: reserve Plantilla Slots for all valid rows
--         via fn_set_slot_status after Pass 1 validation completes; remarks carry
--         batch_id for prior-status recovery in §4.
--   §3  approve_hr_emploc_import — capture slot_id; set hr_emploc.slot_id on INSERT;
--         close vacancy (status → Filled); slot stays hr_processing (move_to_plantilla
--         handles hr_processing → occupied when Plantilla record is created).
--   §4  reject_hr_emploc_import — restore prior slot status for each valid row using
--         slot_history WHERE action_type='import_reserved' AND remarks='import_batch:<id>'.
--         Restores open/pipeline/hr_processing as appropriate; RAISE NOTICE if unresolvable.
--   §5  rollback_hr_emploc_import — loop through hr_emploc rows, restore slot to open
--         (emploc-backout semantics; reason_code=REPLACEMENT), reopen vacancy (Filled→Open),
--         then soft-delete. Uses hr_emploc.slot_id for exact slot match; vcode fallback for
--         rows approved before this migration.
--   §6  GRANTs
--
-- Architecture decisions locked before coding (confirmed by user):
--   B1: open→hr_processing allowed for import path only (bypasses applicant pipeline).
--   B2: Slot stays hr_processing after approval; move_to_plantilla handles hr_processing→occupied.
--   B3: Reject restores to prior slot status via slot_history (not always open).
--       Rollback always restores to open (emploc-backout semantics — no prior-status query needed).
--   C1: hr_processing→pipeline added to fn_set_slot_status for import rejection only.
--       Normal applicant backout still goes hr_processing→open (fn_sync_slot_hr_processing_to_open).
--
-- No schema changes. No Flutter changes. No other RPCs touched.
--
-- Smoke Tests:
-- S1: submit row (slot open)          → slot becomes hr_processing; slot_history action_type=import_reserved; old_value=open
-- S2: submit row (slot pipeline)      → slot becomes hr_processing; slot_history old_value=pipeline
-- S3: submit row (slot hr_processing) → fn_set_slot_status no_op; row still valid; no slot_history written
-- S4: concurrent race (slot occupied between validate and Pass 2) → row downgraded to blocked; batch still created
-- S5: approve valid batch             → hr_emploc.slot_id set; vacancies.status=Filled; slot stays hr_processing
-- S6: reject batch (prior open)       → slot restored to open; slot_history action_type=reopened
-- S7: reject batch (prior pipeline)   → slot restored to pipeline; slot_history action_type=import_rejected
-- S8: reject batch (prior hr_processing) → RAISE NOTICE; slot unchanged
-- S9: rollback approved batch         → hr_emploc soft-deleted; slot→open (action_type=reopened); vacancy→Open
-- S10: rollback row where slot_id IS NULL (legacy) → vcode fallback resolves slot
-- S11: normal applicant backout (fn_approve_emploc_deletion_request) → still hr_processing→open (unaffected)
-- S12: repeat submit on same batch (no-op idempotency via fn_set_slot_status no_op)

BEGIN;

-- ============================================================
-- §1  fn_set_slot_status — extend transition matrix
-- ============================================================
-- Changes vs 20260812000000:
--   open → hr_processing: was blocked; now import_reserved (B1)
--   hr_processing → pipeline: was blocked; now import_rejected (C1)
-- All other transitions, the no-op path, the blocked contract,
-- and the slot_history write are identical.
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
  Central slot-status transition helper (Phase 6.0 + ohm#7xq2m9p4 import extensions).

  Parameters
  ----------
  p_slot_id               — UUID of the plantilla_slots row to transition.
  p_new_status            — Target status: open | pipeline | hr_processing | occupied | closed.
  p_reason_code           — Optional: slot_reason_codes.code (RESIGNED, ENDO, TRANSFER_OUT, …).
  p_performed_by          — Optional: users_profile.id of the acting user.
  p_remarks               — Optional: short free-text context.
  p_occupant_plantilla_id — Required when transitioning INTO 'occupied'; ignored otherwise.

  Returns
  -------
  JSONB with one of three outcomes:

    { "status": "ok",      "slot_id": …, "from_status": …, "to_status": …,
      "action_type": …, "reason_code": …, "history_id": … }

    { "status": "no_op",   "slot_id": …, "from_status": …, "to_status": … }

    { "status": "blocked", "slot_id": …, "from_status": …, "to_status": …,
      "blocked_reason": … }

  RAISE EXCEPTION is reserved for structurally invalid inputs only.
  Workflow hooks must treat 'blocked' as a skip-and-log, never as a rollback trigger.

  Transition matrix additions (ohm#7xq2m9p4):
  ─────────────────────────────────────────────────────────────────────────────────
  open → hr_processing   (import_reserved)
    HR Emploc Import slot reservation. Bypasses the normal applicant pipeline path.
    ONLY reachable from SECURITY DEFINER import RPCs (submit_hr_emploc_import).
    Normal applicant workflow: open → pipeline → hr_processing (pipeline not skipped).

  hr_processing → pipeline   (import_rejected)
    Import batch rejection restoration. Valid ONLY when slot_history confirms the
    import submission moved the slot from pipeline → hr_processing. The reject RPC
    (reject_hr_emploc_import) queries slot_history before calling this transition.
    Do NOT use for normal applicant backout — those use hr_processing → open.
  ─────────────────────────────────────────────────────────────────────────────────
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
  -- 'closed' is checked first because it is a terminal FROM state regardless of target.

  IF v_from_status = 'closed' THEN
    v_transition_ok  := false;
    v_blocked_reason := 'closed is terminal under automation; '
                        're-opening a slot requires an HC re-add workflow';

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

  ELSIF v_from_status = 'open' AND p_new_status = 'hr_processing' THEN
    -- HR Emploc Import reservation path (B1 — ohm#7xq2m9p4).
    -- Bypasses the normal open→pipeline applicant step.
    -- Only reachable from SECURITY DEFINER import RPCs.
    v_transition_ok := true;
    v_action_type   := 'import_reserved';

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
    -- Applicant backout during HR Emploc; also used by import rollback.
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'pipeline' THEN
    -- Import batch rejection restoration (C1 — ohm#7xq2m9p4).
    -- Valid ONLY when reject_hr_emploc_import has confirmed via slot_history that
    -- the import moved the slot from pipeline → hr_processing.
    -- Normal applicant backout never uses this branch — it goes hr_processing → open.
    v_transition_ok := true;
    v_action_type   := 'import_rejected';

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
    v_blocked_reason := format(
      'transition %s→%s is not in the valid transition matrix',
      v_from_status, p_new_status
    );
  END IF;

  -- ── 4. Return blocked result (non-blocking contract) ────────────────────────
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
    current_occupant_plantilla_id = CASE
      WHEN p_new_status = 'occupied'
        THEN p_occupant_plantilla_id
      WHEN p_new_status IN ('open', 'pipeline', 'hr_processing', 'closed')
        THEN NULL
      ELSE current_occupant_plantilla_id
    END,
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
    updated_at                    = now(),
    updated_by                    = p_performed_by
  WHERE id = p_slot_id;

  -- ── 6. Write one slot_history row (append-only) ─────────────────────────────
  v_history_id := gen_random_uuid();

  INSERT INTO public.slot_history (
    id, slot_id, account_id, action_type,
    old_value, new_value, reason_code, performed_by, remarks, created_at
  ) VALUES (
    v_history_id, p_slot_id, v_slot.account_id, v_action_type,
    v_from_status, p_new_status, p_reason_code, p_performed_by, p_remarks, now()
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
  'Central helper for all plantilla_slots.slot_status transitions. '
  'Validates the transition matrix, updates slot metadata, and appends one slot_history row atomically. '
  'Returns JSONB: status=ok|no_op|blocked. NEVER raises for invalid transitions. '
  'RAISES EXCEPTION for structural errors only (null slot_id, unknown status, slot not found). '
  'ohm#7xq2m9p4 additions: open→hr_processing (import_reserved) for HR Emploc Import slot '
  'reservation; hr_processing→pipeline (import_rejected) for import batch rejection restoration '
  'when slot_history proves the import moved the slot from pipeline. '
  'Normal applicant backout still uses hr_processing→open (never hr_processing→pipeline).';


-- ============================================================
-- §2  submit_hr_emploc_import — two-pass: validate then reserve slots
-- ============================================================
-- Based on 20262606000001 (slot-first VCode validator).
-- Changes vs previous version:
--   DECLARE: +v_valid_vcodes, +v_reserve_vcode, +v_slot_result
--   Tally block: collect valid vcodes for Pass 2
--   Pass 2 (after main loop): FOR EACH valid vcode, lock slot via
--     plantilla_slots WHERE legacy_vcode FOR UPDATE, call
--     fn_set_slot_status(slot_id, 'hr_processing',
--       p_remarks := 'import_batch:<batch_id>').
--     On blocked: downgrade row to blocked, adjust counts.
--     On no_op (slot already hr_processing): row stays valid.
--   All mutations in the same transaction — full rollback on any EXCEPTION.
-- ============================================================

CREATE OR REPLACE FUNCTION public.submit_hr_emploc_import(
  p_file_name TEXT,
  p_group_id  UUID,
  p_rows      JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id        UUID;
  v_profile_id       UUID;
  v_batch_id         UUID;
  v_group_name       TEXT;
  v_row              JSONB;
  v_row_number       INTEGER := 0;
  v_total            INTEGER := 0;
  v_valid            INTEGER := 0;
  v_blocked          INTEGER := 0;
  v_duplicate        INTEGER := 0;
  -- per-row values
  v_last_name        TEXT;
  v_first_name       TEXT;
  v_middle_name      TEXT;
  v_account_name     TEXT;
  v_store            TEXT;
  v_vcode            TEXT;
  v_date_hired       DATE;
  v_position         TEXT;
  v_employment_type  TEXT;
  v_row_group        TEXT;
  -- slot-first VCode lookup
  v_slot_id          UUID;
  v_slot_status      TEXT;
  v_slot_group_id    UUID;
  v_slot_store_id    UUID;
  v_slot_position    TEXT;
  v_slot_occupant_id UUID;
  v_slot_store_name  TEXT;
  v_actual_group_name TEXT;
  v_occupant_label   TEXT;
  -- account resolution
  v_acct_id          UUID;
  -- validation
  v_errors           JSONB;
  v_status           TEXT;
  v_identity         TEXT;
  -- de-dup tracking
  v_seen_identities  TEXT[]  := ARRAY[]::TEXT[];
  v_seen_vcodes      TEXT[]  := ARRAY[]::TEXT[];
  v_seen_groups      TEXT[]  := ARRAY[]::TEXT[];
  v_multi_group      BOOLEAN := FALSE;
  -- Pass 2: slot reservation
  v_valid_vcodes     TEXT[]  := ARRAY[]::TEXT[];  -- vcodes of valid rows for slot reservation
  v_reserve_vcode    TEXT;                         -- current vcode in Pass 2 loop
  v_slot_result      JSONB;                        -- fn_set_slot_status return value
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 50 THEN
    RAISE EXCEPTION 'Insufficient permissions to submit HR Emploc import'
      USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Validate group ─────────────────────────────────────────────────────────
  SELECT group_name INTO v_group_name
  FROM public.groups WHERE id = p_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0001';
  END IF;

  -- ── Pre-pass: detect multiple groups in file ───────────────────────────────
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_row_group := UPPER(TRIM(COALESCE(v_row->>'GROUP', '')));
    IF v_row_group <> '' AND NOT (v_row_group = ANY(v_seen_groups)) THEN
      v_seen_groups := array_append(v_seen_groups, v_row_group);
    END IF;
  END LOOP;
  IF array_length(v_seen_groups, 1) > 1 THEN
    v_multi_group := TRUE;
  END IF;

  -- ── Create batch ──────────────────────────────────────────────────────────
  INSERT INTO public.hr_emploc_import_batches (
    file_name, status, group_id, group_name,
    total_rows, valid_rows, blocked_rows, duplicate_rows,
    uploaded_by, uploaded_at
  ) VALUES (
    p_file_name, 'pending_approval', p_group_id, v_group_name,
    0, 0, 0, 0,
    v_profile_id, now()
  ) RETURNING id INTO v_batch_id;

  -- ── Pass 1: Validate all rows and stage them ──────────────────────────────
  -- No slot mutations in this pass. Slot reservations are deferred to Pass 2
  -- so that no slots are mutated unless all validations complete first.
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_row_number      := v_row_number + 1;
    v_total           := v_total + 1;
    v_errors          := '[]'::jsonb;
    v_status          := 'valid';

    v_row_group       := NULLIF(TRIM(COALESCE(v_row->>'GROUP', '')), '');
    v_account_name    := NULLIF(TRIM(COALESCE(v_row->>'ACCOUNT', '')), '');
    v_vcode           := NULLIF(TRIM(COALESCE(v_row->>'VCODE', '')), '');
    v_store           := NULLIF(TRIM(COALESCE(v_row->>'STORE', '')), '');
    v_last_name       := NULLIF(TRIM(COALESCE(v_row->>'LAST_NAME', '')), '');
    v_first_name      := NULLIF(TRIM(COALESCE(v_row->>'FIRST_NAME', '')), '');
    v_middle_name     := NULLIF(TRIM(COALESCE(v_row->>'MIDDLE_NAME', '')), '');
    v_position        := NULLIF(TRIM(COALESCE(v_row->>'POSITION', '')), '');
    v_employment_type := NULLIF(TRIM(COALESCE(v_row->>'EMPLOYMENT_TYPE', '')), '');

    -- Parse DATE_HIRED
    v_date_hired := NULL;
    BEGIN
      v_date_hired := (v_row->>'DATE_HIRED')::DATE;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'DATE_HIRED', 'msg', 'Invalid date format — use YYYY-MM-DD.'
      ));
      v_status := 'blocked';
    END;

    -- Required field checks
    IF v_row_group IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','GROUP','msg','Group is required.'));
      v_status := 'blocked';
    END IF;
    IF v_account_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','ACCOUNT','msg','Account is required.'));
      v_status := 'blocked';
    END IF;
    IF v_vcode IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','VCODE','msg','VCode is required.'));
      v_status := 'blocked';
    END IF;
    IF v_store IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','STORE','msg','Store is required.'));
      v_status := 'blocked';
    END IF;
    IF v_last_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','LAST_NAME','msg','Last name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_first_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','FIRST_NAME','msg','First name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_middle_name IS NULL THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','MIDDLE_NAME','msg','Middle name is required.'));
      v_status := 'blocked';
    END IF;
    IF v_date_hired IS NULL AND v_status = 'valid' THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('field','DATE_HIRED','msg','Date hired is required.'));
      v_status := 'blocked';
    END IF;

    -- Cross-group check
    IF v_multi_group THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'GROUP',
        'msg', 'Upload blocked: file contains rows from multiple groups. One group per upload only.'
      ));
      v_status := 'blocked';
    ELSIF v_row_group IS NOT NULL
      AND UPPER(v_row_group) <> UPPER(v_group_name)
    THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'field', 'GROUP',
        'msg', format('Group "%s" does not match selected group "%s".', v_row_group, v_group_name)
      ));
      v_status := 'blocked';
    END IF;

    -- ── DB validation (only when basic fields are present) ──────────────────
    IF v_status = 'valid' THEN

      -- ── STEP 1: Plantilla Slot lookup (authoritative per ADR-001 Rule 3) ──
      v_slot_id          := NULL;
      v_slot_status      := NULL;
      v_slot_group_id    := NULL;
      v_slot_store_id    := NULL;
      v_slot_position    := NULL;
      v_slot_occupant_id := NULL;
      v_slot_store_name  := NULL;
      v_actual_group_name := NULL;
      v_occupant_label   := NULL;

      SELECT
        ps.id,
        ps.slot_status,
        ps.group_id,
        ps.store_id,
        ps.position,
        ps.current_occupant_plantilla_id
      INTO
        v_slot_id,
        v_slot_status,
        v_slot_group_id,
        v_slot_store_id,
        v_slot_position,
        v_slot_occupant_id
      FROM public.plantilla_slots ps
      WHERE ps.legacy_vcode = v_vcode
      LIMIT 1;

      IF NOT FOUND THEN
        IF EXISTS (
          SELECT 1 FROM public.vacancies WHERE vcode = v_vcode
        ) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" exists in legacy vacancy only. No Plantilla slot found. Repair or create the Plantilla slot first.',
              v_vcode
            )
          ));
        ELSE
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" not found. Create the vacancy slot first via Vacancy Import or HC Request.',
              v_vcode
            )
          ));
        END IF;
        v_status := 'blocked';

      ELSIF v_slot_status = 'archived' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" is archived.', v_vcode)
        ));
        v_status := 'blocked';

      ELSIF v_slot_status IN ('closed', 'hc_reduced') THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format('VCode "%s" is closed and cannot be imported to HR Emploc.', v_vcode)
        ));
        v_status := 'blocked';

      ELSIF v_slot_status = 'occupied' OR v_slot_occupant_id IS NOT NULL THEN
        IF v_slot_occupant_id IS NOT NULL THEN
          SELECT
            COALESCE(
              NULLIF(TRIM(p.employee_no), ''),
              NULLIF(TRIM(p.employee_name), ''),
              'an active employee'
            )
          INTO v_occupant_label
          FROM public.plantilla p
          WHERE p.id = v_slot_occupant_id;
        END IF;
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" is already occupied by %s.',
            v_vcode,
            COALESCE(v_occupant_label, 'an active employee')
          )
        ));
        v_status := 'blocked';

      ELSIF v_slot_status NOT IN ('open', 'pipeline', 'hr_processing') THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" is not in an importable state (current state: %s).',
            v_vcode,
            COALESCE(v_slot_status, 'unknown')
          )
        ));
        v_status := 'blocked';

      ELSE
        -- Slot is open / pipeline / hr_processing — check attributes

        -- STEP 7: Group check
        IF v_slot_group_id IS DISTINCT FROM p_group_id THEN
          SELECT g.group_name INTO v_actual_group_name
          FROM public.groups g WHERE g.id = v_slot_group_id;

          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" belongs to %s, not selected %s.',
              v_vcode,
              COALESCE(v_actual_group_name, v_slot_group_id::TEXT),
              v_group_name
            )
          ));
          v_status := 'blocked';
        END IF;

        -- STEP 8: Store check
        IF v_status = 'valid' THEN
          SELECT s.store_name INTO v_slot_store_name
          FROM public.stores s WHERE s.id = v_slot_store_id;

          IF v_slot_store_name IS NULL
             OR UPPER(TRIM(v_slot_store_name)) <> UPPER(TRIM(v_store))
          THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'field', 'STORE',
              'msg', format(
                'VCode "%s" is for store "%s", but STORE column says "%s".',
                v_vcode,
                COALESCE(v_slot_store_name, '(none)'),
                v_store
              )
            ));
            v_status := 'blocked';
          END IF;
        END IF;

        -- STEP 9: Position check (only when both sides carry a non-null position)
        IF v_status = 'valid'
           AND v_slot_position IS NOT NULL
           AND v_position IS NOT NULL
        THEN
          IF UPPER(TRIM(v_slot_position)) <> UPPER(TRIM(v_position)) THEN
            v_errors := v_errors || jsonb_build_array(jsonb_build_object(
              'field', 'POSITION',
              'msg', format(
                'VCode "%s" is for position "%s", but POSITION column says "%s".',
                v_vcode,
                v_slot_position,
                v_position
              )
            ));
            v_status := 'blocked';
          END IF;
        END IF;

      END IF; -- end slot state branch

      -- ── STEP A: Account must belong to the selected group ──────────────────
      IF v_status = 'valid' THEN
        SELECT a.id INTO v_acct_id
        FROM public.accounts a
        WHERE a.group_id = p_group_id
          AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_account_name))
        LIMIT 1;

        IF v_acct_id IS NULL THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'ACCOUNT',
            'msg', format('Account "%s" not found in the selected group.', v_account_name)
          ));
          v_status := 'blocked';
        END IF;
      END IF;

      -- ── STEP B: VCode already active in hr_emploc ──────────────────────────
      IF v_status = 'valid' THEN
        IF EXISTS (
          SELECT 1 FROM public.hr_emploc h
          WHERE h.vcode = v_vcode
            AND h.deleted_at IS NULL
        ) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" already has an active HR Emploc record.', v_vcode)
          ));
          v_status := 'blocked';
        END IF;
      END IF;

      -- ── STEP C: In-file VCode duplicate ────────────────────────────────────
      IF v_status = 'valid' THEN
        IF UPPER(v_vcode) = ANY(v_seen_vcodes) THEN
          v_errors := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format('VCode "%s" appears more than once in this file.', v_vcode)
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        ELSE
          v_seen_vcodes := array_append(v_seen_vcodes, UPPER(v_vcode));
        END IF;
      END IF;

      -- ── STEP D: In-file name duplicate ─────────────────────────────────────
      IF v_status = 'valid' THEN
        v_identity := UPPER(COALESCE(v_last_name,''))   || '|'
                   || UPPER(COALESCE(v_first_name,''))  || '|'
                   || UPPER(COALESCE(v_middle_name,'')) || '|'
                   || UPPER(COALESCE(v_account_name,''))|| '|'
                   || COALESCE(v_date_hired::TEXT,'');

        IF v_identity = ANY(v_seen_identities) THEN
          v_errors  := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'identity',
            'msg', 'Duplicate within this file (same name, account, and date hired).'
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        ELSE
          v_seen_identities := array_append(v_seen_identities, v_identity);
        END IF;
      END IF;

      -- ── STEP E: DB name+account+date duplicate ─────────────────────────────
      IF v_status = 'valid' THEN
        IF EXISTS (
          SELECT 1
          FROM public.hr_emploc h
          JOIN public.accounts a ON a.id = h.account_id
          WHERE h.deleted_at IS NULL
            AND a.group_id = p_group_id
            AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_account_name))
            AND h.hired_date = v_date_hired
            AND UPPER(TRIM(h.applicant_name)) = UPPER(TRIM(
              v_first_name || ' ' || v_middle_name || ' ' || v_last_name
            ))
        ) THEN
          v_errors  := v_errors || jsonb_build_array(jsonb_build_object(
            'field', 'identity',
            'msg', 'Duplicate: HR Emploc record with this name and date hired already exists.'
          ));
          v_status    := 'blocked';
          v_duplicate := v_duplicate + 1;
        END IF;
      END IF;

    END IF; -- end DB validation block

    -- Tally and collect valid vcodes for Pass 2 slot reservation
    IF v_status = 'valid' THEN
      v_valid        := v_valid + 1;
      v_valid_vcodes := array_append(v_valid_vcodes, v_vcode);
    ELSE
      v_blocked := v_blocked + 1;
    END IF;

    -- Stage row
    INSERT INTO public.hr_emploc_import_rows (
      batch_id, row_number,
      group_name, account_name, last_name, first_name, middle_name,
      date_hired, position, store_name, employment_type, vcode,
      validation_status, validation_errors
    ) VALUES (
      v_batch_id, v_row_number,
      v_row_group, v_account_name, v_last_name, v_first_name, v_middle_name,
      v_date_hired, v_position, v_store, v_employment_type, v_vcode,
      v_status, v_errors
    );
  END LOOP;

  -- ── Pass 2: Reserve Plantilla Slots for all valid rows ────────────────────
  -- Runs after all rows are staged to guarantee no partial slot mutations
  -- within the batch. A slot that can no longer be reserved downgrades the
  -- row from valid to blocked (e.g., concurrent approval of another batch).
  -- fn_set_slot_status no_op (slot already hr_processing) is treated as success.
  -- p_remarks carries the batch_id so reject_hr_emploc_import can recover
  -- the prior slot status from slot_history (old_value field).
  FOREACH v_reserve_vcode IN ARRAY v_valid_vcodes
  LOOP
    v_slot_id     := NULL;
    v_slot_result := NULL;

    -- Lock slot row for this reservation
    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE legacy_vcode = v_reserve_vcode
    FOR UPDATE;

    IF v_slot_id IS NULL THEN
      -- Slot disappeared between Pass 1 validation and Pass 2 (rare race condition)
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" Plantilla slot not found at reservation time. '
            'The slot may have been archived between validation and submission. Please resubmit.',
            v_reserve_vcode
          )
        ))
      WHERE batch_id = v_batch_id
        AND vcode    = v_reserve_vcode
        AND validation_status = 'valid';

      v_valid   := v_valid   - 1;
      v_blocked := v_blocked + 1;
      CONTINUE;
    END IF;

    -- Reserve slot: open or pipeline → hr_processing (or no_op if already hr_processing)
    -- remarks carry the batch_id for prior-status lookup in reject_hr_emploc_import
    SELECT public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_performed_by => v_profile_id,
      p_remarks      => 'import_batch:' || v_batch_id::TEXT
    ) INTO v_slot_result;

    IF (v_slot_result->>'status') = 'blocked' THEN
      -- Slot state changed between validation and reservation (concurrent mutation)
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" slot could not be reserved — slot state changed between '
            'validation and submission (%s). Please resubmit.',
            v_reserve_vcode,
            COALESCE(v_slot_result->>'blocked_reason', 'state transition blocked')
          )
        ))
      WHERE batch_id = v_batch_id
        AND vcode    = v_reserve_vcode
        AND validation_status = 'valid';

      v_valid   := v_valid   - 1;
      v_blocked := v_blocked + 1;
    END IF;
    -- 'ok'    → slot reserved; slot_history written with old_value for reject recovery
    -- 'no_op' → slot was already hr_processing; row stays valid; no slot_history written
  END LOOP;

  -- Update batch summary counts (v_valid may have been adjusted in Pass 2)
  UPDATE public.hr_emploc_import_batches SET
    total_rows     = v_total,
    valid_rows     = v_valid,
    blocked_rows   = v_blocked,
    duplicate_rows = v_duplicate
  WHERE id = v_batch_id;

  RETURN json_build_object('batch_id', v_batch_id);
END;
$$;


-- ============================================================
-- §3  approve_hr_emploc_import — set slot_id, close vacancy
-- ============================================================
-- Based on 20262606000001 (slot-first re-verification).
-- Changes vs previous version:
--   DECLARE: +v_slot_id (UUID)
--   Slot re-verify SELECT: capture ps.id into v_slot_id
--   Before INSERT: guard against duplicate slot occupancy
--   hr_emploc INSERT: add slot_id = v_slot_id
--   After INSERT: UPDATE vacancies SET status = 'Filled'
--   Slot stays hr_processing (ADR-001 B2 decision):
--     move_to_plantilla handles hr_processing → occupied when
--     the Plantilla employee record is created.
-- ============================================================

CREATE OR REPLACE FUNCTION public.approve_hr_emploc_import(p_batch_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id        UUID;
  v_profile_id       UUID;
  v_batch            public.hr_emploc_import_batches%ROWTYPE;
  v_row              public.hr_emploc_import_rows%ROWTYPE;
  v_account_id       UUID;
  v_account_name     TEXT;
  v_hr_id            UUID;
  v_full_name        TEXT;
  v_created          INTEGER := 0;
  -- slot re-verification
  v_slot_id          UUID;    -- captured at approval time; written to hr_emploc.slot_id
  v_slot_status_rc   TEXT;
  v_slot_occupant_rc UUID;
  v_occupant_label   TEXT;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can approve HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_batch
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;

  CASE v_batch.status
    WHEN 'approved'    THEN RAISE EXCEPTION 'This batch has already been approved' USING ERRCODE = 'P0001';
    WHEN 'rejected'    THEN RAISE EXCEPTION 'Rejected batches cannot be approved' USING ERRCODE = 'P0001';
    WHEN 'rolled_back' THEN RAISE EXCEPTION 'Rolled-back batches cannot be re-approved' USING ERRCODE = 'P0001';
    ELSE NULL;
  END CASE;

  IF v_batch.valid_rows = 0 THEN
    RAISE EXCEPTION 'No valid rows to import — all rows are blocked' USING ERRCODE = 'P0001';
  END IF;

  FOR v_row IN
    SELECT * FROM public.hr_emploc_import_rows
    WHERE batch_id = p_batch_id AND validation_status = 'valid'
    ORDER BY row_number
  LOOP
    -- ── Re-verify account ────────────────────────────────────────────────────
    SELECT a.id, a.account_name INTO v_account_id, v_account_name
    FROM public.accounts a
    WHERE a.group_id = v_batch.group_id
      AND UPPER(TRIM(a.account_name)) = UPPER(TRIM(v_row.account_name))
    LIMIT 1;

    IF v_account_id IS NULL THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'ACCOUNT',
          'msg', format('Account "%s" not found at approval time.', v_row.account_name)
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- ── Re-verify Plantilla Slot (authoritative — not vacancies) ────────────
    -- Capture slot_id here; it will be written to hr_emploc.slot_id below.
    v_slot_id          := NULL;
    v_slot_status_rc   := NULL;
    v_slot_occupant_rc := NULL;
    v_occupant_label   := NULL;

    SELECT ps.id, ps.slot_status, ps.current_occupant_plantilla_id
      INTO v_slot_id, v_slot_status_rc, v_slot_occupant_rc
    FROM public.plantilla_slots ps
    WHERE ps.legacy_vcode = v_row.vcode
    LIMIT 1;

    IF NOT FOUND THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" no longer has a Plantilla slot at approval time.',
            v_row.vcode
          )
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    IF v_slot_status_rc NOT IN ('open', 'pipeline', 'hr_processing') THEN
      IF v_slot_status_rc = 'occupied' OR v_slot_occupant_rc IS NOT NULL THEN
        IF v_slot_occupant_rc IS NOT NULL THEN
          SELECT COALESCE(NULLIF(TRIM(p.employee_no), ''), NULLIF(TRIM(p.employee_name), ''), 'an active employee')
          INTO v_occupant_label
          FROM public.plantilla p
          WHERE p.id = v_slot_occupant_rc;
        END IF;
        UPDATE public.hr_emploc_import_rows SET
          validation_status = 'blocked',
          validation_errors = jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" was occupied between submit and approval by %s.',
              v_row.vcode,
              COALESCE(v_occupant_label, 'an active employee')
            )
          ))
        WHERE id = v_row.id;
      ELSE
        UPDATE public.hr_emploc_import_rows SET
          validation_status = 'blocked',
          validation_errors = jsonb_build_array(jsonb_build_object(
            'field', 'VCODE',
            'msg', format(
              'VCode "%s" is no longer importable at approval time (current state: %s).',
              v_row.vcode,
              COALESCE(v_slot_status_rc, 'unknown')
            )
          ))
        WHERE id = v_row.id;
      END IF;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- ── Guard: prevent duplicate slot occupancy (race between two approvals) ─
    IF v_slot_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.hr_emploc
      WHERE slot_id = v_slot_id
        AND deleted_at IS NULL
    ) THEN
      UPDATE public.hr_emploc_import_rows SET
        validation_status = 'blocked',
        validation_errors = jsonb_build_array(jsonb_build_object(
          'field', 'VCODE',
          'msg', format(
            'VCode "%s" slot already has an active HR Emploc record at approval time.',
            v_row.vcode
          )
        ))
      WHERE id = v_row.id;
      UPDATE public.hr_emploc_import_batches SET
        blocked_rows = blocked_rows + 1,
        valid_rows   = valid_rows   - 1
      WHERE id = p_batch_id;
      CONTINUE;
    END IF;

    -- ── All checks passed — create HR Emploc record ──────────────────────────
    -- Slot stays hr_processing (ADR-001 B2): move_to_plantilla transitions it
    -- to occupied when the Plantilla employee record is created.
    v_full_name := TRIM(v_row.first_name || ' ' || v_row.middle_name || ' ' || v_row.last_name);

    INSERT INTO public.hr_emploc (
      applicant_name,
      vcode,
      account,
      account_id,
      position,
      store_name,
      status,
      hr_status,
      requirement_overall_status,
      assignment_type,
      covered_stores,
      hired_date,
      created_by,
      updated_by,
      import_batch_id,
      slot_id          -- set at approval time per ADR-001 Rule 5 (Phase C binding)
    ) VALUES (
      v_full_name,
      v_row.vcode,
      COALESCE(v_account_name, v_row.account_name),
      v_account_id,
      COALESCE(v_row.position, ''),
      v_row.store_name,
      'Pending Emploc',
      'Pending',
      'Incomplete',
      'Stationary'::public.hr_emploc_assignment_type,
      '[]'::jsonb,
      v_row.date_hired,
      v_profile_id,
      v_profile_id,
      p_batch_id,
      v_slot_id
    ) RETURNING id INTO v_hr_id;

    UPDATE public.hr_emploc_import_rows
    SET hr_emploc_id = v_hr_id
    WHERE id = v_row.id;

    -- ── Close vacancy (ADR-001 Rule 5: vacancy → Filled on import approval) ──
    -- Uses vcode match; idempotent if vacancy is already Filled/Closed/Cancelled/Archived.
    UPDATE public.vacancies
    SET
      status     = 'Filled',
      updated_at = now(),
      updated_by = v_profile_id
    WHERE vcode      = v_row.vcode
      AND deleted_at IS NULL
      AND (is_archived IS NULL OR is_archived = false)
      AND status NOT IN ('Filled', 'Closed', 'Cancelled', 'Archived');

    v_created := v_created + 1;
  END LOOP;

  UPDATE public.hr_emploc_import_batches SET
    status       = 'approved',
    approved_by  = v_profile_id,
    approved_at  = now(),
    created_rows = v_created
  WHERE id = p_batch_id;

  RETURN json_build_object('records_created', v_created);
END;
$$;


-- ============================================================
-- §4  reject_hr_emploc_import — restore prior slot status
-- ============================================================
-- Based on 20262606000000 (FK fix version).
-- Changes vs previous version:
--   DECLARE: +v_reject_row (RECORD), +v_slot_id (UUID),
--            +v_prior_status (TEXT)
--   Before batch status update: loop through valid rows,
--     query slot_history WHERE action_type='import_reserved'
--     AND remarks='import_batch:<batch_id>' to recover old_value.
--     Restore: open → fn_set_slot_status(open);
--              pipeline → fn_set_slot_status(pipeline) [C1];
--              hr_processing → no-op (slot unchanged);
--              NOT FOUND → RAISE NOTICE; slot unchanged.
-- ============================================================

CREATE OR REPLACE FUNCTION public.reject_hr_emploc_import(
  p_batch_id    UUID,
  p_reason_code TEXT,
  p_reason_note TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id    UUID;
  v_profile_id   UUID;
  v_status       TEXT;
  -- slot restoration
  v_reject_row   RECORD;  -- hr_emploc_import_rows row
  v_slot_id      UUID;
  v_prior_status TEXT;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can reject HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_reason_code IS NULL OR TRIM(p_reason_code) = '' THEN
    RAISE EXCEPTION 'Rejection reason code is required' USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT status INTO v_status
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;
  IF v_status <> 'pending_approval' THEN
    RAISE EXCEPTION 'Only pending_approval batches can be rejected (current status: %)', v_status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Restore Plantilla Slot status for each valid row ─────────────────────
  -- Query slot_history for the prior slot state before this batch reserved it
  -- (submit_hr_emploc_import Pass 2 wrote slot_history with remarks='import_batch:<id>').
  -- Prior status recovery:
  --   old_value='open'          → restore to open  (hr_processing → open; action_type=reopened)
  --   old_value='pipeline'      → restore to pipeline (hr_processing → pipeline; action_type=import_rejected)
  --   old_value='hr_processing' → slot was already hr_processing before import; no change
  --   NOT FOUND                 → submit produced no_op (slot was already hr_processing); no change
  FOR v_reject_row IN
    SELECT vcode FROM public.hr_emploc_import_rows
    WHERE batch_id = p_batch_id AND validation_status = 'valid'
  LOOP
    v_slot_id      := NULL;
    v_prior_status := NULL;

    -- Resolve slot by VCode
    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE legacy_vcode = v_reject_row.vcode
    LIMIT 1;

    IF v_slot_id IS NULL THEN
      RAISE NOTICE
        'reject_hr_emploc_import: Plantilla slot not found for vcode % in batch % — skipping slot restoration.',
        v_reject_row.vcode, p_batch_id;
      CONTINUE;
    END IF;

    -- Find prior status from slot_history written by submit Pass 2
    SELECT sh.old_value INTO v_prior_status
    FROM public.slot_history sh
    WHERE sh.slot_id     = v_slot_id
      AND sh.action_type = 'import_reserved'
      AND sh.remarks     = 'import_batch:' || p_batch_id::TEXT
    ORDER BY sh.created_at DESC
    LIMIT 1;

    IF v_prior_status IS NULL THEN
      -- No slot_history entry: submit produced a no_op (slot was already hr_processing).
      -- The slot was not moved by this batch — leave it unchanged.
      RAISE NOTICE
        'reject_hr_emploc_import: no import_reserved entry in slot_history for slot % '
        '(vcode %) batch % — slot was already hr_processing before submit; leaving unchanged.',
        v_slot_id, v_reject_row.vcode, p_batch_id;
      CONTINUE;
    END IF;

    IF v_prior_status = 'open' THEN
      -- Restore: hr_processing → open (normal reopened transition)
      PERFORM public.fn_set_slot_status(
        p_slot_id      => v_slot_id,
        p_new_status   => 'open',
        p_performed_by => v_profile_id,
        p_remarks      => 'import_batch_rejected:' || p_batch_id::TEXT
      );

    ELSIF v_prior_status = 'pipeline' THEN
      -- Restore: hr_processing → pipeline (import_rejected — C1 transition)
      -- Valid because slot_history proves the import brought the slot to hr_processing from pipeline.
      PERFORM public.fn_set_slot_status(
        p_slot_id      => v_slot_id,
        p_new_status   => 'pipeline',
        p_performed_by => v_profile_id,
        p_remarks      => 'import_batch_rejected:' || p_batch_id::TEXT
      );

    ELSIF v_prior_status = 'hr_processing' THEN
      -- Slot was already hr_processing before submit moved it — no restoration needed.
      RAISE NOTICE
        'reject_hr_emploc_import: slot % was hr_processing before batch % — no restoration.',
        v_slot_id, p_batch_id;

    ELSE
      -- Unexpected prior status (future-proofing for new states)
      RAISE NOTICE
        'reject_hr_emploc_import: unexpected prior status "%" for slot % (vcode %) batch %. Leaving unchanged.',
        v_prior_status, v_slot_id, v_reject_row.vcode, p_batch_id;
    END IF;
  END LOOP;

  -- ── Mark batch rejected ────────────────────────────────────────────────────
  UPDATE public.hr_emploc_import_batches SET
    status                = 'rejected',
    rejected_by           = v_profile_id,
    rejected_at           = now(),
    rejection_reason_code = p_reason_code,
    rejection_reason_note = p_reason_note
  WHERE id = p_batch_id;
END;
$$;


-- ============================================================
-- §5  rollback_hr_emploc_import — restore slots + reopen vacancies
-- ============================================================
-- Based on 20262606000000 (FK fix version).
-- Changes vs previous version:
--   DECLARE: +v_hr_row (RECORD), +v_slot_id (UUID)
--   Replace bulk UPDATE soft-delete with a per-row loop that:
--     1. Resolves slot: use hr_emploc.slot_id (set at approval time);
--        fallback to plantilla_slots WHERE legacy_vcode for rows approved
--        before this migration (slot_id IS NULL).
--     2. Calls fn_set_slot_status(slot_id, 'open', REPLACEMENT)
--        (emploc-backout semantics — always open, no prior-status query).
--     3. Reopens vacancy: UPDATE vacancies SET status='Open'
--        WHERE vcode = hr_row.vcode AND status='Filled'.
--     4. Soft-deletes the hr_emploc row.
--   v_removed incremented per-row (replaces GET DIAGNOSTICS).
-- ============================================================

CREATE OR REPLACE FUNCTION public.rollback_hr_emploc_import(
  p_batch_id UUID,
  p_reason   TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id   UUID;
  v_profile_id  UUID;
  v_batch       public.hr_emploc_import_batches%ROWTYPE;
  v_moved_count INTEGER;
  v_removed     INTEGER := 0;
  -- per-row slot + vacancy restoration
  v_hr_row      RECORD;  -- hr_emploc row (id, slot_id, vcode)
  v_slot_id     UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Only Head Admin or Super Admin can roll back HR Emploc imports'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'Rollback reason must be at least 10 characters'
      USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_batch
  FROM public.hr_emploc_import_batches
  WHERE id = p_batch_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Import batch not found' USING ERRCODE = 'P0001';
  END IF;

  CASE v_batch.status
    WHEN 'rolled_back'      THEN RAISE EXCEPTION 'This batch has already been rolled back' USING ERRCODE = 'P0001';
    WHEN 'rejected'         THEN RAISE EXCEPTION 'Rejected batches cannot be rolled back — no records were created' USING ERRCODE = 'P0001';
    WHEN 'pending_approval' THEN RAISE EXCEPTION 'Pending batches cannot be rolled back — reject instead' USING ERRCODE = 'P0001';
    ELSE NULL;
  END CASE;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'Only approved batches can be rolled back' USING ERRCODE = 'P0001';
  END IF;

  -- Guard: block rollback if any record was already moved to Plantilla
  SELECT COUNT(*) INTO v_moved_count
  FROM public.hr_emploc
  WHERE import_batch_id = p_batch_id
    AND deleted_at IS NULL
    AND status = 'Moved to Plantilla';

  IF v_moved_count > 0 THEN
    RAISE EXCEPTION
      'Rollback blocked: % record(s) from this batch have already been moved to Plantilla. Remove them from Plantilla first.',
      v_moved_count
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Per-row rollback: restore slot + reopen vacancy + soft-delete ─────────
  -- Emploc-backout semantics: slot always returns to open (reason_code=REPLACEMENT).
  -- No prior-status query needed (contrast with reject which must recover prior state).
  FOR v_hr_row IN
    SELECT id, slot_id, vcode
    FROM public.hr_emploc
    WHERE import_batch_id = p_batch_id
      AND deleted_at IS NULL
  LOOP
    -- 1. Resolve slot (prefer slot_id FK; fallback to vcode for legacy rows)
    v_slot_id := v_hr_row.slot_id;

    IF v_slot_id IS NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_hr_row.vcode
      LIMIT 1;
    END IF;

    -- 2. Restore slot to open (hr_processing → open; action_type=reopened)
    IF v_slot_id IS NOT NULL THEN
      PERFORM public.fn_set_slot_status(
        p_slot_id      => v_slot_id,
        p_new_status   => 'open',
        p_reason_code  => 'REPLACEMENT',
        p_performed_by => v_profile_id,
        p_remarks      => 'import_batch_rolled_back:' || p_batch_id::TEXT
      );
    ELSE
      RAISE NOTICE
        'rollback_hr_emploc_import: no slot found for hr_emploc.id=% vcode=% — slot not restored.',
        v_hr_row.id, v_hr_row.vcode;
    END IF;

    -- 3. Reopen vacancy (reverses the Filled closure from approve_hr_emploc_import)
    UPDATE public.vacancies
    SET
      status     = 'Open',
      updated_at = now(),
      updated_by = v_profile_id
    WHERE vcode      = v_hr_row.vcode
      AND status     = 'Filled'
      AND deleted_at IS NULL
      AND (is_archived IS NULL OR is_archived = false);

    -- 4. Soft-delete HR Emploc record
    UPDATE public.hr_emploc
    SET deleted_at = now()
    WHERE id = v_hr_row.id;

    v_removed := v_removed + 1;
  END LOOP;

  -- ── Mark batch rolled back ─────────────────────────────────────────────────
  UPDATE public.hr_emploc_import_batches SET
    status          = 'rolled_back',
    rolled_back_by  = v_profile_id,
    rolled_back_at  = now(),
    rollback_reason = TRIM(p_reason)
  WHERE id = p_batch_id;

  RETURN json_build_object('records_removed', v_removed);
END;
$$;


-- ============================================================
-- §6  GRANTs
-- ============================================================

-- fn_set_slot_status: SECURITY DEFINER; restrict to authenticated only
REVOKE ALL ON FUNCTION public.fn_set_slot_status(
  uuid, text, text, uuid, text, uuid
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_set_slot_status(
  uuid, text, text, uuid, text, uuid
) TO authenticated;

-- Import RPCs: authenticated callers; role level enforced inside each function
GRANT EXECUTE ON FUNCTION public.submit_hr_emploc_import(text, uuid, jsonb)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_hr_emploc_import(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_hr_emploc_import(uuid, text, text)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_hr_emploc_import(uuid, text)        TO authenticated;


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — fn_set_slot_status: open→hr_processing now allowed
--   SELECT public.fn_set_slot_status('<open_slot_id>', 'hr_processing',
--     NULL, '<profile_uuid>', 'import_batch:<uuid>');
--   -- Expected: {"status":"ok","action_type":"import_reserved","from_status":"open","to_status":"hr_processing",...}
--
-- V2 — fn_set_slot_status: hr_processing→pipeline now allowed
--   SELECT public.fn_set_slot_status('<hr_processing_slot_id>', 'pipeline',
--     NULL, '<profile_uuid>', 'import_batch_rejected:<uuid>');
--   -- Expected: {"status":"ok","action_type":"import_rejected","from_status":"hr_processing","to_status":"pipeline",...}
--
-- V3 — submit: slot reserved after submit
--   SELECT public.submit_hr_emploc_import('<filename>', '<group_id>', '[{...}]');
--   -- Then check:
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: 'hr_processing'
--   SELECT action_type, old_value, new_value, remarks FROM public.slot_history
--   WHERE slot_id = '<slot_id>' ORDER BY created_at DESC LIMIT 1;
--   -- Expected: action_type='import_reserved', old_value='open'|'pipeline', remarks='import_batch:<uuid>'
--
-- V4 — approve: hr_emploc.slot_id set; vacancy closed
--   SELECT public.approve_hr_emploc_import('<batch_id>');
--   SELECT slot_id FROM public.hr_emploc WHERE import_batch_id = '<batch_id>';
--   -- Expected: non-null UUID
--   SELECT status FROM public.vacancies WHERE vcode = '<vcode>';
--   -- Expected: 'Filled'
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: 'hr_processing' (not occupied — move_to_plantilla handles that)
--
-- V5 — reject (prior=open): slot restored to open
--   SELECT public.reject_hr_emploc_import('<batch_id>', 'DATA_ERROR', null);
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: 'open'
--
-- V6 — reject (prior=pipeline): slot restored to pipeline
--   -- (slot was pipeline before submit)
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: 'pipeline'
--
-- V7 — rollback: slot→open, vacancy→Open
--   SELECT public.rollback_hr_emploc_import('<batch_id>', 'Rollback test reason here');
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: 'open'
--   SELECT status FROM public.vacancies WHERE vcode = '<vcode>';
--   -- Expected: 'Open'
--   SELECT deleted_at FROM public.hr_emploc WHERE import_batch_id = '<batch_id>';
--   -- Expected: all rows have non-null deleted_at
--
-- V8 — normal applicant backout unaffected (hr_processing→open still works)
--   SELECT public.fn_set_slot_status('<hr_processing_slot_id>', 'open');
--   -- Expected: {"status":"ok","action_type":"reopened","to_status":"open",...}
--   -- (NOT "blocked" — the hr_processing→open transition is unchanged)
-- ============================================================

COMMIT;
