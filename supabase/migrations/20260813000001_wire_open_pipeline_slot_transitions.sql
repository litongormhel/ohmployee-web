-- ============================================================
-- OHM2026_0019 — Phase 6.1: Wire Vacancy Open ↔ Pipeline Slot Transitions
-- Migration: 20260813000001_wire_open_pipeline_slot_transitions.sql
-- Depends on: 20260812000000_fn_set_slot_status.sql (Phase 6.0 — fn_set_slot_status)
--             20260521900000_fix_applicant_status_transition_rules.sql
--               (fn_update_applicant_status — latest live version)
--             20260520012857_remote_schema.sql
--               (create_applicant_and_link_to_vacancy — latest live version)
-- ============================================================
-- Phase 6.1 of slot_lifecycle_automation_plan.md (OHM2026_0017).
--
-- SCOPE: Wire open ↔ pipeline slot transitions into the two existing
-- RPCs that govern applicant lifecycle for vacancies. No other workflow,
-- vacancy/applicant behavior, UI, or migration is changed.
--
-- Hook points (confirmed against live function bodies):
--   1. fn_update_applicant_status — called when an applicant status changes
--      (e.g., New→For Interview, any active→Backout/Rejected/Failed).
--      After each applicants.status write, re-counts active applicants
--      for the vacancy VCODE and calls fn_set_slot_status to sync the
--      slot to pipeline (count ≥ 1) or open (count = 0).
--
--   2. create_applicant_and_link_to_vacancy — called when a new applicant
--      (status = 'New') is added to a vacancy. After the INSERT the
--      active count is always ≥ 1, so the slot transitions open → pipeline.
--
-- Non-blocking contract (hard requirement — OHM2026_0017 Q1):
--   A slot sync error must NEVER roll back or alter the host RPC's
--   transaction. fn_sync_vacancy_slot_open_pipeline (§1) catches ALL
--   exceptions internally and emits RAISE NOTICE only.
--
-- Slot lookup: plantilla_slots.legacy_vcode = vacancy.vcode (1:1 bridge,
--   per OHM2026_0017 Q6). Relies on the partial-unique index on legacy_vcode
--   established in 20260807000000_plantilla_slots_legacy_vcode_link.sql.
--
-- Roving slots (is_roving = true) are skipped unconditionally — no reliable
--   1:1 VCODE→slot mapping until the deferred coverage model lands.
--
-- VCODEs with no matching slot (pre-slot-era legacy vacancies) are silently
--   skipped; the reconciliation report surfaces them, not this function.
--
-- Edit-lock safety: edit-lock triggers on applicants already block the host
--   RPC when the lock is active, so the slot sync only runs after a successful
--   applicant write — no additional lock check required here.
--
-- Sections:
--   §1  fn_sync_vacancy_slot_open_pipeline  (internal non-blocking helper)
--   §2  Patch fn_update_applicant_status    (slot sync hook)
--   §3  Patch create_applicant_and_link_to_vacancy  (slot sync hook)
--   §4  GRANT
-- ============================================================


-- ============================================================
-- §1  fn_sync_vacancy_slot_open_pipeline
-- ============================================================
-- Non-blocking internal helper that syncs a vacancy slot's status
-- to open or pipeline based on the current active-applicant count.
--
-- Called AFTER the host RPC has already written its applicant row /
-- status update, so the count reflects the new state.
--
-- Arguments
-- ---------
--   p_vcode        — Vacancy VCODE (applicants.vacancy_vcode / vacancies.vcode).
--   p_performed_by — Acting user UUID for slot_history.performed_by (nullable).
--   p_source_fn    — Calling function name; written to slot_history.remarks.
--
-- Returns: JSONB from fn_set_slot_status (ok / no_op / blocked), or NULL
--          when skipped (roving, no slot, null vcode, or any error).
-- NEVER RAISES.

CREATE OR REPLACE FUNCTION public.fn_sync_vacancy_slot_open_pipeline(
  p_vcode        text,
  p_performed_by uuid DEFAULT NULL,
  p_source_fn    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Phase 6.1 — non-blocking open↔pipeline slot sync (OHM2026_0019).

  Active-applicant predicate mirrors vw_vacancy_list:
    fn_is_active_vacancy_applicant_status → new, for_interview,
    for_requirements, for_onboard.

  Reason code is NULL for both open→pipeline and pipeline→open:
  these transitions have no matching reason code in the design matrix
  (slot_lifecycle_automation_plan.md Q2/Q3 — "(none)").
  Context is fully captured in p_remarks via source function + VCODE + count.
*/
DECLARE
  v_slot_id    uuid;
  v_active_cnt bigint;
  v_target     text;
  v_result     jsonb;
BEGIN
  -- ── Guard: VCODE required ───────────────────────────────────────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_vacancy_slot_open_pipeline: skipped — p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- ── Locate slot via legacy_vcode bridge ──────────────────────────
  -- Partial-unique index on legacy_vcode guarantees at most one match.
  -- Roving slots excluded: no reliable 1:1 VCODE→slot until coverage model.
  SELECT id INTO v_slot_id
  FROM public.plantilla_slots
  WHERE legacy_vcode = p_vcode
    AND is_roving = false
  LIMIT 1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  -- ── Count active applicants for this VCODE (post-host-write) ────
  SELECT count(*) INTO v_active_cnt
  FROM public.applicants
  WHERE vacancy_vcode = p_vcode
    AND public.fn_is_active_vacancy_applicant_status(status)
    AND COALESCE(is_archived, false) = false;

  -- ── Derive target slot status ────────────────────────────────────
  v_target := CASE WHEN v_active_cnt > 0 THEN 'pipeline' ELSE 'open' END;

  -- ── Delegate to central transition helper ───────────────────────
  -- fn_set_slot_status handles: same-state no-op, matrix validation,
  -- slot row update (slot_status + updated_at/by), and slot_history append.
  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => v_target,
    p_reason_code           => NULL,
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'Phase 6.1 / %s / VCODE=%s / active_applicants=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_vcode,
                                 v_active_cnt
                               ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  -- Non-blocking contract: log and skip. Host RPC transaction continues.
  RAISE NOTICE
    'fn_sync_vacancy_slot_open_pipeline: error for VCODE=% source=% — % (sqlstate=%)',
    p_vcode, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_vacancy_slot_open_pipeline(text, uuid, text) IS
  'Phase 6.1 — non-blocking open↔pipeline slot sync helper (OHM2026_0019). '
  'Called after any write that may change the active-applicant count for a VCODE. '
  'Counts non-archived active applicants, derives open or pipeline status, '
  'calls fn_set_slot_status. Skips roving slots and VCODEs with no slot. '
  'NEVER raises. '
  'Callers: fn_update_applicant_status, create_applicant_and_link_to_vacancy.';


-- ============================================================
-- §2  Patch fn_update_applicant_status (Phase 6.1 slot sync hook)
-- ============================================================
-- Source: 20260521900000_fix_applicant_status_transition_rules.sql §3.
-- Change: ONE addition — fn_sync_vacancy_slot_open_pipeline call appended
--         after the applicant_status_history INSERT.
-- All existing behavior, RBAC, scope checks, and history writes are
-- preserved IDENTICALLY. No parameter or return type changes.

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
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_app        public.applicants%ROWTYPE;
  v_to_opt     public.applicant_status_options%ROWTYPE;
  v_from_code  text;
  v_old_status text;
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

  -- ── Phase 6.1: non-blocking slot open↔pipeline sync ───────────
  -- Syncs the matching plantilla slot to pipeline (active count ≥ 1)
  -- or open (active count = 0) after the status write above.
  -- fn_sync_vacancy_slot_open_pipeline NEVER raises; a slot error will
  -- not roll back this function's applicant or history writes.
  PERFORM public.fn_sync_vacancy_slot_open_pipeline(
    p_vcode        => v_app.vacancy_vcode,
    p_performed_by => v_profile_id,
    p_source_fn    => 'fn_update_applicant_status'
  );

END;
$$;

COMMENT ON FUNCTION public.fn_update_applicant_status(uuid, text, text, uuid, text) IS
  'Updates an applicant status with RBAC, scope, and history enforcement. '
  'Phase 6.1 (OHM2026_0019): also syncs the matching plantilla slot open↔pipeline '
  'after each write via fn_sync_vacancy_slot_open_pipeline (non-blocking).';


-- ============================================================
-- §3  Patch create_applicant_and_link_to_vacancy (Phase 6.1 slot sync hook)
-- ============================================================
-- Source: 20260520012857_remote_schema.sql (only definition in migrations).
-- Change: ONE addition — fn_sync_vacancy_slot_open_pipeline call appended
--         after log_audit_event and before RETURN new_id.
-- New applicants start at status = 'New' (active), so active count is
-- always ≥ 1 after the INSERT; the slot transitions open → pipeline.
-- All existing behavior is preserved IDENTICALLY.

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
  v      public.vacancies%ROWTYPE;
  new_id uuid;
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

  INSERT INTO public.applicants (
    vacancy_vcode, last_name, first_name, middle_name, full_name,
    contact_number, application_date, source_channel, comment,
    status, created_by
  ) VALUES (
    v.vcode, p_last_name, p_first_name, p_middle_name,
    p_last_name || ', ' || p_first_name || ' ' || p_middle_name,
    p_contact_number, p_application_date, p_source_channel, p_comment,
    'New', public.get_my_profile_id()
  ) RETURNING id INTO new_id;

  -- self-master if no link provided
  UPDATE public.applicants SET master_applicant_id = new_id WHERE id = new_id;

  PERFORM public.log_audit_event(
    'vacancy_module', 'INSERT', new_id,
    NULL,
    jsonb_build_object('action', 'create_applicant', 'vacancy_id', v.id)
  );

  -- Phase 6.1: non-blocking slot open→pipeline sync.
  -- A new 'New' applicant is always active; the slot moves open→pipeline.
  -- fn_sync_vacancy_slot_open_pipeline NEVER raises; a slot error will
  -- not roll back this function's applicant insert.
  PERFORM public.fn_sync_vacancy_slot_open_pipeline(
    p_vcode        => v.vcode,
    p_performed_by => public.get_my_profile_id(),
    p_source_fn    => 'create_applicant_and_link_to_vacancy'
  );

  RETURN new_id;
END;
$$;

COMMENT ON FUNCTION public.create_applicant_and_link_to_vacancy(uuid, text, text, text, text, date, text, text) IS
  'Creates and links a new applicant to a vacancy. '
  'Phase 6.1 (OHM2026_0019): also syncs the matching plantilla slot open→pipeline '
  'after the INSERT via fn_sync_vacancy_slot_open_pipeline (non-blocking).';


-- ============================================================
-- §4  GRANT
-- ============================================================
-- fn_sync_vacancy_slot_open_pipeline is an internal helper called
-- only from SECURITY DEFINER RPCs; restrict to authenticated.

REVOKE ALL ON FUNCTION public.fn_sync_vacancy_slot_open_pipeline(text, uuid, text)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_sync_vacancy_slot_open_pipeline(text, uuid, text)
  TO authenticated;

-- Existing GRANT on fn_update_applicant_status (unchanged from 20260521900000):
GRANT EXECUTE ON FUNCTION public.fn_update_applicant_status(uuid, text, text, uuid, text)
  TO authenticated;

-- Existing GRANT on create_applicant_and_link_to_vacancy is inherited from
-- remote_schema; no change required.


-- ============================================================
-- Validation Queries (run manually after applying)
-- ============================================================
--
-- V1 — Helper function exists with correct signature
--   SELECT routine_name, routine_type, security_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public'
--     AND routine_name = 'fn_sync_vacancy_slot_open_pipeline';
--   -- Expected: 1 row, FUNCTION, DEFINER
--
-- V2 — fn_update_applicant_status body includes Phase 6.1 hook
--   SELECT prosrc LIKE '%fn_sync_vacancy_slot_open_pipeline%'
--   FROM pg_proc
--   WHERE proname = 'fn_update_applicant_status'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: true
--
-- V3 — create_applicant_and_link_to_vacancy body includes Phase 6.1 hook
--   SELECT prosrc LIKE '%fn_sync_vacancy_slot_open_pipeline%'
--   FROM pg_proc
--   WHERE proname = 'create_applicant_and_link_to_vacancy'
--     AND pronamespace = 'public'::regnamespace;
--   -- Expected: true
--
-- V4 — Applicant assignment moves slot open → pipeline
--   (After adding a first active applicant to a VCODE that has a slot)
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'pipeline'
--
--   SELECT action_type, old_value, new_value, remarks
--   FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--   ORDER BY created_at DESC LIMIT 3;
--   -- Expected: one row with action_type='pipeline', old_value='open', new_value='pipeline'
--   --           remarks includes 'Phase 6.1 / fn_update_applicant_status / VCODE=...'
--
-- V5 — Last active applicant terminal moves slot pipeline → open
--   (After setting the only active applicant to backout/rejected/failed)
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE legacy_vcode = '<test_vcode>';
--   -- Expected: 'open'
--
--   SELECT action_type, old_value, new_value, remarks
--   FROM public.slot_history
--   WHERE slot_id = (SELECT id FROM public.plantilla_slots WHERE legacy_vcode = '<test_vcode>')
--   ORDER BY created_at DESC LIMIT 3;
--   -- Expected: one row with action_type='reopened', old_value='pipeline', new_value='open'
--
-- V6 — Existing vacancy count unchanged (no behavior change)
--   SELECT count(*) FROM public.vacancies WHERE status NOT IN ('Filled','Cancelled');
--   -- Compare to pre-migration count; must be identical.
--
-- V7 — slot_history written only on successful transitions (not blocked/no-op)
--   SELECT count(*) FROM public.slot_history
--   WHERE remarks LIKE 'Phase 6.1%'
--     AND action_type NOT IN ('pipeline', 'reopened');
--   -- Expected: 0 (only pipeline and reopened action_types written by Phase 6.1)
--
-- V8 — Roving slots NOT touched by Phase 6.1 sync
--   SELECT slot_status FROM public.plantilla_slots
--   WHERE is_roving = true;
--   -- Status must match pre-migration snapshot (Phase 6.1 never writes roving slots)
--
-- V9 — P1–P8 reconciliation still green (run OHM2026_0016 parity suite)
--   (Re-run the validation queries from 20260811000000_fix_backfill_parity_d1_d2.sql)
-- ============================================================
