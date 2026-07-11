-- ============================================================
-- OHM2026_0023 — Phase 6.5: Wire HR Processing → Open Slot Transition
-- Migration: 20260813000005_wire_hr_processing_open_slot_transition.sql
-- Depends on: 20260812000000_fn_set_slot_status.sql        (Phase 6.0)
--             20260813000001_wire_open_pipeline_slot_transitions.sql (Phase 6.1)
--             20260813000002_wire_pipeline_hr_processing_slot_transition.sql (Phase 6.2)
--             20260813000003_wire_hr_processing_occupied_slot_transition.sql (Phase 6.3)
--             20260813000004_wire_occupied_open_slot_transition.sql (Phase 6.4)
--             20260520500000_hr_emploc_deletion_request_finalize.sql
--               (fn_approve_emploc_deletion_request — latest live version)
-- ============================================================
-- Phase 6.5 of slot_lifecycle_automation_plan.md (OHM2026_0017).
--
-- SCOPE: Wire the hr_processing → open slot transition into
-- fn_approve_emploc_deletion_request — the only existing RPC that finalizes
-- an HR Emploc backout/deletion request. Only the 'Backout' deletion type
-- triggers the slot reopen: a Backout represents an HR processing abandonment
-- (the applicant returns to Vacancy). 'Duplicate Record' is a data-cleanup
-- operation and does NOT move the slot.
--
-- Hook point:
--   fn_approve_emploc_deletion_request — after the approval activity INSERT
--   (all main writes committed: emploc archive, applicant archive, vacancy
--   reopen, request status update), guarded by
--   v_req.deletion_type = 'Backout'. Fires only for stationary non-roving
--   slots; roving slots have no reliable 1:1 VCODE→slot mapping (deferred
--   to the roving coverage model, OHM2026_0017 Q6).
--
-- Slot lookup: plantilla_slots.legacy_vcode = v_req.vcode (1:1 bridge,
--   per OHM2026_0017 Q6). Partial-unique index on legacy_vcode guarantees
--   at most one match. Roving filter is_roving = false applied. If no slot
--   is found (pre-slot-era legacy vacancy or roving), the helper silently
--   returns NULL — no error, no impact on host RPC.
--
-- Reason code: REPLACEMENT (task-specified for Phase 6.5) — records that
--   the backout restored the slot to open for the next candidate.
--
-- Non-blocking contract (hard requirement — OHM2026_0017 Q1):
--   A slot sync error must NEVER roll back or alter the host RPC's
--   transaction. fn_sync_slot_hr_processing_to_open (§1) catches ALL
--   exceptions internally and emits RAISE NOTICE only.
--   PERFORM (not SELECT INTO) is used in the host RPC so the return
--   value is discarded — no error path from the caller side.
--
-- Roving carve-out:
--   Roving slots (is_roving = true) are skipped unconditionally at the
--   helper level (is_roving = false filter on slot lookup). No reliable
--   1:1 VCODE→slot until the deferred coverage model lands.
--
-- Sections:
--   §1  fn_sync_slot_hr_processing_to_open  (internal non-blocking helper)
--   §2  Patch fn_approve_emploc_deletion_request (slot sync hook added)
--   §3  GRANT
-- ============================================================


-- ============================================================
-- §1  fn_sync_slot_hr_processing_to_open
-- ============================================================
-- Non-blocking internal helper that transitions a vacancy slot from
-- hr_processing to open when a Backout deletion request is approved.
--
-- Called AFTER fn_approve_emploc_deletion_request has written all main
-- state changes (emploc archive, applicant archive, vacancy reopen,
-- request Approved, activity log) — the transition represents confirmed,
-- committed state.
--
-- Arguments
-- ---------
--   p_vcode           — Vacancy VCODE (hr_emploc_deletion_requests.vcode).
--   p_hr_emploc_id    — hr_emploc.id; written to slot_history.remarks.
--   p_deletion_reason — Deletion/backout reason; written to remarks.
--   p_performed_by    — Acting user UUID for slot_history.performed_by.
--   p_source_fn       — Calling function name; written to slot_history.remarks.
--
-- Returns: JSONB from fn_set_slot_status (ok / no_op / blocked), or NULL
--          when skipped (null vcode, no slot found, roving, or any error).
-- NEVER RAISES.

CREATE OR REPLACE FUNCTION public.fn_sync_slot_hr_processing_to_open(
  p_vcode            text,
  p_hr_emploc_id     uuid    DEFAULT NULL,
  p_deletion_reason  text    DEFAULT NULL,
  p_performed_by     uuid    DEFAULT NULL,
  p_source_fn        text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Phase 6.5 — non-blocking hr_processing→open slot sync (OHM2026_0023).

  Locates the slot by legacy_vcode (1:1 bridge, non-roving only).
  Delegates to fn_set_slot_status with:
    p_new_status  = 'open'
    p_reason_code = 'REPLACEMENT'   (OHM2026_0023 task spec)

  Called only for Backout deletions — Duplicate Record is excluded (host
  RPC guard: IF v_req.deletion_type = 'Backout').

  Blocked or no_op results from fn_set_slot_status are logged via
  RAISE NOTICE and returned as-is — they never raise into the host RPC.
*/
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN
  -- ── Guard: VCODE required ───────────────────────────────────────────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_slot_hr_processing_to_open: skipped — p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Locate slot via legacy_vcode bridge ──────────────────────────────
  -- Partial-unique index on legacy_vcode guarantees at most one match.
  -- Roving slots excluded: no reliable 1:1 VCODE→slot until coverage model.
  SELECT id INTO v_slot_id
  FROM public.plantilla_slots
  WHERE legacy_vcode = p_vcode
    AND is_roving    = false
  LIMIT 1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  -- ── Delegate to central transition helper ────────────────────────────
  -- fn_set_slot_status handles: same-state no_op, matrix validation,
  -- slot row update (slot_status = 'open', current_occupant cleared,
  -- updated_at/by), and slot_history append.
  -- Reason code REPLACEMENT is task-specified for Phase 6.5.
  -- new_value='open' written to slot_history starts a new open episode
  -- for the shadow view's aging basis (OHM2026_0017 Q5).
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'open',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.5 / %s / VCODE=%s / hr_emploc_id=%s / reason=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_vcode,
                                 COALESCE(p_hr_emploc_id::text, 'null'),
                                 COALESCE(p_deletion_reason, 'null')
                               ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  -- Log blocked/no_op outcomes for observability; never raise.
  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_hr_processing_to_open: % for slot_id=% VCODE=% source=% — %',
      v_result->>'status',
      v_slot_id,
      p_vcode,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_slot_hr_processing_to_open: error for VCODE=% source=% — % (sqlstate=%)',
    p_vcode, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_slot_hr_processing_to_open(text, uuid, text, uuid, text) IS
  'Phase 6.5 — non-blocking hr_processing→open slot sync helper (OHM2026_0023). '
  'Called after fn_approve_emploc_deletion_request succeeds on the Backout deletion path. '
  'Locates slot by legacy_vcode (non-roving only), calls fn_set_slot_status with '
  'p_new_status=open and p_reason_code=REPLACEMENT. '
  'NEVER raises. Blocked/no_op results are RAISE NOTICEd and returned. '
  'Callers: fn_approve_emploc_deletion_request (Backout deletion type only).';


-- ============================================================
-- §2  Patch fn_approve_emploc_deletion_request (Phase 6.5 slot sync hook)
-- ============================================================
-- Source: 20260520500000_hr_emploc_deletion_request_finalize.sql
-- Change: ONE addition — fn_sync_slot_hr_processing_to_open call inserted
--         after the approval activity INSERT and before the implicit END.
--         The hook is guarded with IF v_req.deletion_type = 'Backout' so
--         Duplicate Record approvals are never touched.
-- All existing behavior — RBAC, scope check, emploc lifecycle validation,
-- correction auto-close, emploc archive, applicant archive, vacancy reopen
-- (FK-based), request status update, approval snapshot activity, trigger
-- (handle_emploc_deletion_approved), return void, SECURITY DEFINER,
-- GRANT — is preserved IDENTICALLY.
-- No parameter or return type changes.

CREATE OR REPLACE FUNCTION public.fn_approve_emploc_deletion_request(
  p_request_id       uuid,
  p_reviewer_remarks text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_req        public.hr_emploc_deletion_requests;
  v_emp        public.hr_emploc;
  v_profile    public.users_profile;
  v_reviewer   text;
  v_vacancy_id uuid;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.get_my_role() IN ('Encoder', 'headAdmin')
  ) THEN
    RAISE EXCEPTION 'forbidden: Encoder or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req
  FROM public.hr_emploc_deletion_requests
  WHERE id = p_request_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'deletion request % not found', p_request_id USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'cannot approve: request is already %', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  -- Scope check for Encoder
  IF NOT public.is_super_admin() AND public.get_my_role() = 'Encoder' THEN
    IF NOT (v_req.account = ANY (public.get_my_allowed_accounts())) THEN
      RAISE EXCEPTION 'forbidden: deletion request is outside your assigned scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_profile FROM public.users_profile WHERE id = public.get_my_profile_id();
  v_reviewer := COALESCE(v_profile.full_name, public.get_my_full_name());

  -- Lock and validate hr_emploc lifecycle
  IF v_req.hr_emploc_id IS NOT NULL THEN
    SELECT * INTO v_emp FROM public.hr_emploc
    WHERE id = v_req.hr_emploc_id FOR UPDATE;

    IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
      RAISE EXCEPTION 'cannot approve: employee lifecycle is already finalized in Plantilla'
        USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.plantilla
      WHERE hr_emploc_id = v_req.hr_emploc_id
        AND COALESCE(is_deleted, false) = false
    ) THEN
      RAISE EXCEPTION 'cannot approve: active Plantilla record exists'
        USING ERRCODE = 'P0001';
    END IF;

    v_vacancy_id := v_emp.vacancy_id;

    -- Correction auto-close on Backout approval
    IF v_req.deletion_type = 'Backout' AND v_emp.correction_reason IS NOT NULL THEN
      INSERT INTO public.hr_emploc_deletion_activities (
        request_id, activity_type, performed_by, performed_by_user_id, remarks, snapshot
      ) VALUES (
        p_request_id,
        'Correction Auto-Cancelled',
        v_reviewer,
        public.get_my_profile_id(),
        'Correction auto-cancelled: Backout deletion approved',
        jsonb_build_object(
          'correction_reason',   v_emp.correction_reason,
          'hr_status_at_cancel', v_emp.hr_status,
          'cancelled_at',        NOW()
        )
      );
      UPDATE public.hr_emploc
      SET correction_reason = NULL,
          updated_at        = NOW()
      WHERE id = v_req.hr_emploc_id;
    END IF;

    -- Archive emploc (never hard delete)
    UPDATE public.hr_emploc
    SET deleted_at = NOW(),
        updated_at = NOW(),
        updated_by = public.get_my_profile_id()
    WHERE id = v_req.hr_emploc_id;
  END IF;

  -- Archive applicant: prefer FK, fallback to name+vcode
  IF v_emp.applicant_id IS NOT NULL THEN
    UPDATE public.applicants
    SET is_archived = true, archived_at = NOW()
    WHERE id = v_emp.applicant_id
      AND status IN ('Hired', 'For Onboarding', 'Confirmed Onboard');
  ELSE
    UPDATE public.applicants
    SET is_archived = true, archived_at = NOW()
    WHERE full_name     = v_req.applicant_name
      AND vacancy_vcode = v_req.vcode
      AND status IN ('Hired', 'For Onboarding', 'Confirmed Onboard');
  END IF;

  -- Vacancy reopen: Backout only, via vacancy_id FK (no headcount inference)
  IF v_req.deletion_type = 'Backout'
     AND COALESCE(v_req.reopen_vacancy, false)
     AND v_vacancy_id IS NOT NULL
  THEN
    UPDATE public.vacancies
    SET status     = 'Open',
        updated_at = NOW()
    WHERE id = v_vacancy_id
      AND status NOT IN ('Closed', 'Archived', 'Cancelled');
  END IF;
  -- Duplicate Record: reopen_vacancy = false on creation → no reopen here

  -- Mark Approved with immutable reviewer info
  UPDATE public.hr_emploc_deletion_requests
  SET status              = 'Approved',
      reviewed_by         = v_reviewer,
      reviewed_at         = NOW(),
      reviewer_remarks    = p_reviewer_remarks,
      approved_by_user_id = public.get_my_profile_id()
  WHERE id = p_request_id;

  -- Immutable approval snapshot
  INSERT INTO public.hr_emploc_deletion_activities (
    request_id, activity_type, performed_by, performed_by_user_id, remarks, snapshot
  ) VALUES (
    p_request_id,
    'Approved',
    v_reviewer,
    public.get_my_profile_id(),
    p_reviewer_remarks,
    jsonb_build_object(
      'snapshot_last_name',   v_req.snapshot_last_name,
      'snapshot_first_name',  v_req.snapshot_first_name,
      'vcode',                v_req.vcode,
      'snapshot_store',       v_req.snapshot_store,
      'snapshot_position',    v_req.snapshot_position,
      'reason',               v_req.reason,
      'deletion_type',        v_req.deletion_type,
      'requested_by',         v_req.requested_by,
      'approved_by',          v_reviewer,
      'approved_at',          NOW(),
      'vacancy_id_used',      v_vacancy_id,
      'vacancy_reopened',     (v_req.deletion_type = 'Backout' AND v_vacancy_id IS NOT NULL),
      'original_emploc_id',   v_req.original_emploc_id
    )
  );
  -- Trigger handle_emploc_deletion_approved fires here → notifications

  -- ── Phase 6.5: non-blocking slot hr_processing→open sync ──────────────
  -- Wires the HR Emploc backout approval into the slot lifecycle model so
  -- the matching plantilla slot reopens (hr_processing→open). Only fires
  -- for Backout type — Duplicate Record is data-cleanup and does not
  -- represent an HR processing abandonment. Slot is located via legacy_vcode
  -- (1:1 VCODE bridge, non-roving only per OHM2026_0017 Q6).
  -- fn_sync_slot_hr_processing_to_open NEVER raises; a slot error will not
  -- roll back this function's emploc archive, applicant archive, vacancy
  -- reopen, request update, or activity log writes.
  IF v_req.deletion_type = 'Backout' THEN
    PERFORM public.fn_sync_slot_hr_processing_to_open(
      p_vcode           => v_req.vcode,
      p_hr_emploc_id    => v_req.hr_emploc_id,
      p_deletion_reason => v_req.reason,
      p_performed_by    => public.get_my_profile_id(),
      p_source_fn       => 'fn_approve_emploc_deletion_request'
    );
  END IF;

END;
$$;

COMMENT ON FUNCTION public.fn_approve_emploc_deletion_request(uuid, text) IS
  'Approves a Pending HR Emploc deletion request. '
  'Encoder (scoped by account) or Super Admin. '
  'Backout: archives emploc + applicant, reopens vacancy via vacancy_id FK, '
  'auto-cancels correction if present. '
  'Duplicate Record: archives emploc + applicant only (no vacancy reopen). '
  'Phase 6.5 (OHM2026_0023): also syncs the matching plantilla slot '
  'hr_processing→open after the approval activity write, on the Backout '
  'path only, via fn_sync_slot_hr_processing_to_open (non-blocking). '
  'Roving slots excluded (carve-out: no reliable 1:1 VCODE→slot until coverage model).';


-- ============================================================
-- §3  GRANT
-- ============================================================
-- fn_sync_slot_hr_processing_to_open is an internal helper called
-- only from SECURITY DEFINER RPCs; restrict to authenticated.

REVOKE ALL ON FUNCTION public.fn_sync_slot_hr_processing_to_open(text, uuid, text, uuid, text)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_sync_slot_hr_processing_to_open(text, uuid, text, uuid, text)
  TO authenticated;

-- Preserve existing GRANT on fn_approve_emploc_deletion_request (unchanged from 20260520500000).
GRANT EXECUTE ON FUNCTION public.fn_approve_emploc_deletion_request(uuid, text)
  TO authenticated;


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — Helper function exists with correct signature
--   SELECT routine_name, routine_type, security_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public'
--     AND routine_name = 'fn_sync_slot_hr_processing_to_open';
--   -- Expected: 1 row, FUNCTION, DEFINER
--
-- V2 — fn_approve_emploc_deletion_request body includes Phase 6.5 hook
--   SELECT prosrc LIKE '%fn_sync_slot_hr_processing_to_open%'
--   FROM pg_proc
--   WHERE proname = 'fn_approve_emploc_deletion_request'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: true
--
-- V3 — Slot moves hr_processing → open on Backout deletion approval
--   (After approving a Backout deletion request for a stationary emploc
--    whose slot is currently in hr_processing status)
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'open'
--
--   SELECT action_type, old_value, new_value, reason_code, remarks
--   FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--   ORDER BY created_at DESC LIMIT 5;
--   -- Expected: one row with action_type='reopened', old_value='hr_processing',
--   --           new_value='open', reason_code='REPLACEMENT',
--   --           remarks includes 'Phase 6.5 / fn_approve_emploc_deletion_request / VCODE=...'
--
-- V4 — slot_history new_value='open' (aging episode restarts)
--   SELECT new_value, created_at FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--     AND action_type = 'reopened'
--   ORDER BY created_at DESC LIMIT 1;
--   -- Expected: new_value='open' (shadow view aging episode restarts from this row)
--
-- V5 — Reopened slot appears in vw_slot_derived_vacancy_shadow
--   SELECT vcode, slot_status, derived_status
--   FROM public.vw_slot_derived_vacancy_shadow
--   WHERE vcode = '<test_vcode>';
--   -- Expected: 1 row with slot_status='open' (shadow projects open/pipeline/closed)
--
-- V6 — Duplicate Record approval does NOT move the slot
--   (After approving a Duplicate Record deletion request)
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE legacy_vcode = '<duplicate_test_vcode>';
--   -- Expected: unchanged from pre-approval (no slot transition for Duplicate Record)
--
--   SELECT count(*) FROM public.slot_history
--   WHERE remarks LIKE 'Phase 6.5%'
--     AND slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<duplicate_test_vcode>');
--   -- Expected: 0 (Phase 6.5 hook does not fire for Duplicate Record)
--
-- V7 — fn_approve_emploc_deletion_request still works end-to-end
--   (Backout approval: emploc deleted_at set, applicant archived,
--    vacancy reopened to Open, request status = Approved)
--   SELECT deleted_at IS NOT NULL FROM public.hr_emploc WHERE id = '<hr_emploc_id>';
--   -- Expected: true
--   SELECT status FROM public.hr_emploc_deletion_requests WHERE id = '<request_id>';
--   -- Expected: 'Approved'
--   SELECT status FROM public.vacancies WHERE id = '<vacancy_id>';
--   -- Expected: 'Open'
--
-- V8 — Roving paths NOT touched by Phase 6.5 sync
--   SELECT slot_status FROM public.plantilla_slots WHERE is_roving = true;
--   -- Status must match pre-migration snapshot (Phase 6.5 never writes roving slots)
--
-- V9 — No Vacancy UI read-source behavior changed
--   SELECT count(*) FROM public.vacancies WHERE status NOT IN ('Filled', 'Cancelled');
--   -- Compare to pre-migration count; must be identical (vacancies table not touched
--   -- by fn_sync_slot_hr_processing_to_open).
--
-- V10 — REPLACEMENT reason code is valid in slot_reason_codes
--   SELECT code, label FROM public.slot_reason_codes WHERE code = 'REPLACEMENT';
--   -- Expected: 1 row (defined in 20260804000000_plantilla_slot_foundation_v1.sql)
--
-- V11 — P1–P8 reconciliation after Phase 6.5
--   (Re-run the parity suite from OHM2026_0016 / 20260811000000_fix_backfill_parity_d1_d2.sql)
--   NOTE: slots that backed out of HR Emploc now move to open in the shadow view.
--   They appear in both legacy (vacancy reopened as Open) and shadow (slot_status='open').
--   This is correct expected behavior — aging episode restarts. Any slot still in
--   hr_processing (not yet backed out) remains excluded from the shadow view —
--   unchanged from Phase 6.2.
-- ============================================================
