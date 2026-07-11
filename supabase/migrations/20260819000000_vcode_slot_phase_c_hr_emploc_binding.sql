-- ============================================================
-- OHM2026_0045 — VCODE ↔ Slot Phase C: HR Emploc-to-Slot Binding
-- Migration: 20260819000000_vcode_slot_phase_c_hr_emploc_binding.sql
-- Depends on:
--   20260816000000_vcode_slot_phase_a_schema_bridge.sql
--     (hr_emploc.slot_id nullable FK, applicants.slot_id nullable FK)
--   20260817000000_vcode_slot_phase_b_applicant_binding.sql
--     (applicants.slot_id source of truth, uq_applicants_one_active_per_slot)
--   20260818000000_fix_create_applicant_rpc_missing_columns.sql
--     (Add Applicant RPC runtime blocker patched — Phase B GREEN)
--   20260813000002_wire_pipeline_hr_processing_slot_transition.sql
--     (fn_sync_slot_to_hr_processing, confirm_applicant_onboard Phase 6.2)
--   20260813000005_wire_hr_processing_open_slot_transition.sql
--     (fn_sync_slot_hr_processing_to_open, fn_approve_emploc_deletion_request Phase 6.5)
--   20260812000000_fn_set_slot_status.sql
--     (fn_set_slot_status — central transition helper)
--   20260616000000_restore_fn_is_active_vacancy_applicant_status.sql
--     (fn_is_active_vacancy_applicant_status — canonical active predicate)
-- ============================================================
-- Scope: Phase C HR Emploc-to-slot binding.
--
-- Authorising documents (locked):
--   docs/architecture/vcode_slot_bridge_redesign.md  (OHM2026_0035) §4, §5, §9
--   docs/architecture/vcode_slot_phase_c_hr_emploc_binding_plan.md (OHM2026_0044)
--
-- Phase C makes hr_emploc.slot_id the source of truth for HR-processing
-- slot ownership and retires all legacy_vcode-only LIMIT 1 routing on the
-- HR Emploc side. Phase A shipped the column (hr_emploc.slot_id nullable FK)
-- as empty. Phase B made applicants.slot_id the source of truth through
-- open ↔ pipeline and handed the pipeline → hr_processing boundary to
-- Phase C. Phase C fills hr_emploc.slot_id.
--
-- What this migration does:
--   C1  Backfill hr_emploc.slot_id for existing active stationary HR Emploc rows
--   C2  Partial unique: one active HR Emploc row per slot
--   C3  Reconcile slot status to HR Emploc reality (safety step, expected no-op)
--   C4a Replace fn_sync_slot_to_hr_processing — add exact p_slot_id path
--   C4b Replace confirm_applicant_onboard — slot_id propagation at INSERT
--       + exact slot pipeline→hr_processing via p_slot_id
--   C5a Replace fn_sync_slot_hr_processing_to_open — add exact p_slot_id path
--   C5b Replace fn_approve_emploc_deletion_request — exact slot hr_processing→open
--       via p_slot_id = v_emp.slot_id (captured pre-archive)
--   C6  GRANTs
--   C7  Post-migration validation queries (manual, in comments)
--
-- What this migration deliberately does NOT do:
--   • Modify Flutter UI or any client-side code
--   • Modify shadow view aggregation (Phase D)
--   • Modify HC request VCODE generation
--   • Modify transfer, closure, or roving logic
--   • Recreate or apply 20260815000000_one_store_one_vcode.sql (BLOCKED)
--   • Modify hr_processing → occupied (move-to-Plantilla / Phase 6.3)
--   • Add plantilla.slot_id (deferred per Phase A plan)
--   • Update module state files (verified stable behavior only)
--
-- Non-blocking discipline (load-bearing):
--   Slot writes inside confirm_applicant_onboard and
--   fn_approve_emploc_deletion_request are SIDE EFFECTS. A slot-write
--   failure must NEVER roll back the host workflow. The slot helper
--   functions NEVER RAISE into their callers — blocked/no_op transitions
--   are logged via RAISE NOTICE and returned as-is.
--
-- Legacy fallback (load-bearing):
--   NULL applicants.slot_id at Confirmed Onboard → hr_emploc.slot_id stays
--   NULL, slot helper falls back to legacy VCODE LIMIT 1 path. Covers
--   no-slot VCODEs, roving, and pre-backfill edge rows. Onboard is NEVER
--   blocked on a missing slot_id. (OHM2026_0044 §Q2)
--
-- Roving carve-out: roving hr_emploc rows (assignment_type = 'Roving')
--   keep slot_id = NULL; roving legacy path retained throughout.
-- ============================================================


-- ============================================================
-- §C0 — Pre-migration gate (run MANUALLY before applying)
-- ============================================================
--
-- Gate 1: hr_emploc.slot_id all NULL (Phase A shipped empty).
--   SELECT COUNT(*) FROM public.hr_emploc WHERE slot_id IS NOT NULL;
--   -- Expected: 0. Any non-zero = prior partial run; reconcile before re-applying.
--
-- Gate 2: 1:1 precondition — at most 1 non-roving slot per VCODE.
--   SELECT legacy_vcode, COUNT(*) AS slot_count
--     FROM public.plantilla_slots
--     WHERE legacy_vcode IS NOT NULL AND is_roving = false
--     GROUP BY legacy_vcode HAVING COUNT(*) > 1;
--   -- Expected: 0 rows. Phase A composite unique should guarantee this.
--
-- Gate 3: B1–B10 parity baseline GREEN (Phase B verified OHM2026_0042).
--   -- Re-run the B1–B10 + P1–P8 parity suite; confirm applicants.slot_id
--   -- is the source of truth for open ↔ pipeline and no invariant is broken.
--
-- Gate 4: fn_sync_slot_to_hr_processing old signature exists.
--   SELECT routine_name, specific_name
--     FROM information_schema.routines
--     WHERE routine_schema = 'public'
--       AND routine_name   = 'fn_sync_slot_to_hr_processing';
--   -- Expected: 1 row (the 4-param Phase 6.2 version from 20260813000002).
--
-- Gate 5: fn_sync_slot_hr_processing_to_open old signature exists.
--   SELECT routine_name, specific_name
--     FROM information_schema.routines
--     WHERE routine_schema = 'public'
--       AND routine_name   = 'fn_sync_slot_hr_processing_to_open';
--   -- Expected: 1 row (the 5-param Phase 6.5 version from 20260813000005).
-- ============================================================


-- ============================================================
-- §C1 — Backfill hr_emploc.slot_id for active stationary rows
-- ============================================================
-- Binds each active (non-archived, non-roving) HR Emploc row to the
-- single non-roving slot for its VCODE.
--
-- Data is 1:1 today (Phase A verified: every non-roving VCODE has at
-- most 1 slot, all ordinals = 1). The subquery ORDER BY is N-slot-safe:
-- it always picks slot_ordinal=1 (the only slot per VCODE today).
--
-- Roving rows (assignment_type = 'Roving'): excluded — NULL slot_id
-- preserved, legacy path retained (OHM2026_0044 carve-out).
--
-- No-slot VCODEs: excluded by the EXISTS guard — slot_id stays NULL.
--
-- Already-slot-id rows: excluded by the slot_id IS NULL guard (idempotent
-- if a prior partial run landed some rows).

UPDATE public.hr_emploc he
SET
  slot_id    = (
    SELECT ps.id
    FROM   public.plantilla_slots ps
    WHERE  ps.legacy_vcode = he.vcode
      AND  ps.is_roving    = false
    ORDER  BY ps.slot_ordinal ASC, ps.created_at ASC, ps.id ASC
    LIMIT  1
  ),
  updated_at = NOW()
WHERE he.slot_id IS NULL
  AND he.deleted_at IS NULL
  AND he.assignment_type = 'Stationary'
  AND EXISTS (
    SELECT 1
    FROM   public.plantilla_slots ps
    WHERE  ps.legacy_vcode = he.vcode
      AND  ps.is_roving    = false
  );


-- ============================================================
-- §C2 — Partial unique: one active HR Emploc row per slot
-- ============================================================
-- Structural guard for the invariant "at most one active (non-archived)
-- HR Emploc row owns a given slot at any moment."
--
-- Archived rows (deleted_at IS NOT NULL) retain slot_id for audit trail
-- and are excluded by the WHERE clause.
--
-- Built AFTER §C1 so the index validates the backfill is clean.

CREATE UNIQUE INDEX IF NOT EXISTS uq_hr_emploc_one_active_per_slot
  ON public.hr_emploc (slot_id)
  WHERE slot_id IS NOT NULL
    AND deleted_at IS NULL;

COMMENT ON INDEX public.uq_hr_emploc_one_active_per_slot IS
  'Phase C (OHM2026_0045): enforces one active (non-archived) HR Emploc row '
  'per plantilla_slots row. Archived rows retain slot_id for audit. '
  'Partial: slot_id IS NOT NULL AND deleted_at IS NULL. '
  'See OHM2026_0044 §Q5/Q6 (C2).';


-- ============================================================
-- §C3 — Reconcile slot status to HR Emploc reality (safety step)
-- ============================================================
-- After §C1 backfill, slot status and HR Emploc binding should already
-- be in lockstep (Phase 6.2/6.5 maintained this). This DO block catches
-- any pre-existing drift and corrects it via fn_set_slot_status (which
-- writes slot_history for auditability).
--
-- Expected: both loops execute zero iterations on clean data.
-- Any RAISE NOTICE output signals a pre-existing discrepancy that was
-- corrected — review the slot_history rows written by this reconcile.
--
-- Non-blocking: fn_set_slot_status returns no_op for same-state calls;
-- the entire DO block is a safety net, not authoritative business logic.

DO $$
DECLARE
  v_slot   record;
  v_result jsonb;
BEGIN
  -- Case A: hr_processing slot with no active HR Emploc row bound to it
  --         → reopen slot (hr_processing → open)
  FOR v_slot IN
    SELECT ps.id, ps.legacy_vcode, ps.slot_ordinal
    FROM   public.plantilla_slots ps
    WHERE  ps.slot_status = 'hr_processing'
      AND  ps.is_roving   = false
      AND  NOT EXISTS (
             SELECT 1 FROM public.hr_emploc he
             WHERE  he.slot_id    = ps.id
               AND  he.deleted_at IS NULL
           )
  LOOP
    v_result := public.fn_set_slot_status(
      p_slot_id    => v_slot.id,
      p_new_status => 'open',
      p_remarks    => format(
        'Phase C §C3 reconcile: hr_processing slot with no active HR Emploc / '
        'legacy_vcode=%s slot_ordinal=%s',
        v_slot.legacy_vcode, v_slot.slot_ordinal
      )
    );
    RAISE NOTICE
      'C3 reconcile (hr_processing→open): slot=% vcode=% ordinal=% result=%',
      v_slot.id, v_slot.legacy_vcode, v_slot.slot_ordinal, v_result;
  END LOOP;

  -- Case B: active HR Emploc row with a bound slot_id that is NOT
  --         in hr_processing → correct slot to hr_processing
  FOR v_slot IN
    SELECT DISTINCT ps.id, ps.legacy_vcode, ps.slot_ordinal
    FROM   public.hr_emploc he
    JOIN   public.plantilla_slots ps ON ps.id = he.slot_id
    WHERE  he.deleted_at    IS NULL
      AND  he.slot_id       IS NOT NULL
      AND  ps.slot_status   != 'hr_processing'
      AND  ps.is_roving      = false
  LOOP
    v_result := public.fn_set_slot_status(
      p_slot_id    => v_slot.id,
      p_new_status => 'hr_processing',
      p_remarks    => format(
        'Phase C §C3 reconcile: active HR Emploc bound to non-hr_processing slot / '
        'legacy_vcode=%s slot_ordinal=%s',
        v_slot.legacy_vcode, v_slot.slot_ordinal
      )
    );
    RAISE NOTICE
      'C3 reconcile (→hr_processing): slot=% vcode=% ordinal=% result=%',
      v_slot.id, v_slot.legacy_vcode, v_slot.slot_ordinal, v_result;
  END LOOP;
END;
$$;


-- ============================================================
-- §C4a — Replace fn_sync_slot_to_hr_processing
--         (add exact p_slot_id path; retire VCODE LIMIT 1 for slot-aware callers)
-- ============================================================
-- Phase 6.2 (OHM2026_0020) created this helper with a VCODE-only lookup.
-- Phase C adds p_slot_id (uuid DEFAULT NULL) as the 5th parameter:
--   • p_slot_id IS NOT NULL → use exact slot directly (no legacy_vcode lookup)
--   • p_slot_id IS NULL     → fall back to legacy VCODE LIMIT 1 path
--                             (no-slot VCODEs, roving, pre-backfill edge rows)
--
-- The old 4-parameter signature is dropped and replaced with the 5-parameter
-- signature. confirm_applicant_onboard (§C4b) is updated in this migration
-- to call the new signature. No other callers exist.
--
-- Non-blocking contract: NEVER RAISES into the host RPC.

DROP FUNCTION IF EXISTS public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text);

CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_hr_processing(
  p_vcode        text,
  p_applicant_id uuid DEFAULT NULL,
  p_performed_by uuid DEFAULT NULL,
  p_source_fn    text DEFAULT NULL,
  p_slot_id      uuid DEFAULT NULL    -- Phase C: exact slot (preferred over VCODE lookup)
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Phase C upgrade — non-blocking pipeline→hr_processing slot sync (OHM2026_0045).

  Phase C adds p_slot_id: when non-NULL, the exact slot is used directly —
  no legacy_vcode LIMIT 1 lookup, no slot ambiguity under N-slot VCODEs.
  When NULL (no-slot VCODE, roving, pre-backfill edge row), falls back to
  the Phase 6.2 VCODE LIMIT 1 legacy path.

  Asymmetry vs Phase B (deliberate, per OHM2026_0044 §Q3):
    • Phase B create_applicant_and_link_to_vacancy: slot transition is the
      PRIMARY operation → blocked transition rolls back the insert.
    • Here (Confirmed Onboard): slot transition is a DOWNSTREAM SIDE EFFECT
      of an already-authorised workflow hand-off → blocked/no_op transitions
      are logged via RAISE NOTICE, never raised into the host RPC.

  Reason code: REPLACEMENT (task-specified for the pipeline→hr_processing
  transition, per OHM2026_0020/0045).
*/
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN

  -- ── Phase C: exact slot_id path ─────────────────────────────────────────
  IF p_slot_id IS NOT NULL THEN
    SELECT public.fn_set_slot_status(
      p_slot_id               => p_slot_id,
      p_new_status            => 'hr_processing',
      p_reason_code           => 'REPLACEMENT',
      p_performed_by          => p_performed_by,
      p_remarks               => format(
        'Phase C / %s / VCODE=%s / applicant_id=%s / slot_id=%s',
        COALESCE(p_source_fn,    'unknown'),
        COALESCE(p_vcode,        'unknown'),
        COALESCE(p_applicant_id::text, 'null'),
        p_slot_id
      ),
      p_occupant_plantilla_id => NULL
    ) INTO v_result;

    IF (v_result->>'status') IN ('blocked', 'no_op') THEN
      RAISE NOTICE
        'fn_sync_slot_to_hr_processing (exact): % for slot_id=% VCODE=% source=% — %',
        v_result->>'status',
        p_slot_id,
        COALESCE(p_vcode, 'unknown'),
        COALESCE(p_source_fn, 'unknown'),
        COALESCE(v_result->>'blocked_reason', 'same-state no_op');
    END IF;

    RETURN v_result;
  END IF;

  -- ── Legacy path: VCODE LIMIT 1 (Phase 6.2 — no-slot VCODEs, roving) ────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_slot_to_hr_processing: skipped — p_vcode null/empty '
      'and p_slot_id null (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- Locate slot via legacy_vcode bridge (non-roving only).
  SELECT id INTO v_slot_id
  FROM   public.plantilla_slots
  WHERE  legacy_vcode = p_vcode
    AND  is_roving    = false
  LIMIT  1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'hr_processing',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
      'Phase 6.2 (legacy vcode path) / %s / VCODE=%s / applicant_id=%s',
      COALESCE(p_source_fn,    'unknown'),
      p_vcode,
      COALESCE(p_applicant_id::text, 'null')
    ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_hr_processing (legacy): % for slot_id=% VCODE=% source=% — %',
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
    'fn_sync_slot_to_hr_processing: error for VCODE=% slot_id=% source=% — % (sqlstate=%)',
    COALESCE(p_vcode, 'null'),
    COALESCE(p_slot_id::text, 'null'),
    COALESCE(p_source_fn, 'unknown'),
    SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text, uuid) IS
  'Phase C (OHM2026_0045) upgrade of Phase 6.2 (OHM2026_0020) helper. '
  'Non-blocking pipeline→hr_processing slot sync. '
  'p_slot_id IS NOT NULL → exact slot used directly (no VCODE LIMIT 1 lookup); '
  'p_slot_id IS NULL → legacy VCODE LIMIT 1 fallback for no-slot VCODEs / roving. '
  'NEVER raises. Blocked/no_op results are RAISE NOTICEd and returned. '
  'Callers: confirm_applicant_onboard (stationary non-fast-track path only). '
  'Reason code: REPLACEMENT. See OHM2026_0044 §Q4.';


-- ============================================================
-- §C4b — Replace confirm_applicant_onboard
--         (Phase C: copy slot_id at stationary INSERT + pass p_slot_id)
-- ============================================================
-- Source: 20260813000002_wire_pipeline_hr_processing_slot_transition.sql §2
--         (Phase 6.2 version — the basis patched here).
--
-- Phase C changes (all other behavior IDENTICAL to Phase 6.2):
--   1. Stationary HR Emploc INSERT (inside the ELSE / IF NOT FOUND branch):
--      • Add slot_id to the column list.
--      • Set slot_id = v_app.slot_id (direct copy from the locked applicant row).
--      • v_app.slot_id is available from the RETURNING * of the applicant UPDATE
--        performed earlier in this function; it is NULL for no-slot VCODEs and
--        roving (those rows remain NULL).
--   2. The Phase 6.2 fn_sync_slot_to_hr_processing call (inside IF NOT v_is_roving):
--      • Add p_slot_id => v_app.slot_id.
--      • When v_app.slot_id IS NOT NULL → exact slot path in the helper.
--      • When v_app.slot_id IS NULL → helper falls back to VCODE LIMIT 1 (legacy).
--
-- Non-blocking contract preserved: fn_sync_slot_to_hr_processing NEVER raises;
-- a slot-write failure will not roll back the applicant update, HR Emploc
-- creation, or audit log.
--
-- Return shape, RBAC, idempotency guard, fast-track branches (both),
-- roving/stationary HR Emploc creation, store-link management, audit log,
-- SECURITY DEFINER, GRANT: all IDENTICAL to Phase 6.2.

CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(
  p_applicant_id             uuid,
  p_last_name                text    DEFAULT NULL::text,
  p_first_name               text    DEFAULT NULL::text,
  p_middle_name              text    DEFAULT NULL::text,
  p_full_name                text    DEFAULT NULL::text,
  p_contact_number           text    DEFAULT NULL::text,
  p_remarks                  text    DEFAULT NULL::text,
  p_roving_assignment_id     uuid    DEFAULT NULL::uuid,
  p_hired_by_user_id         uuid    DEFAULT NULL::uuid,
  p_endorsed_by_deployer_id  uuid    DEFAULT NULL::uuid,
  p_endorsed_by_name         text    DEFAULT NULL::text,
  p_hired_date               date    DEFAULT NULL::date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text    := public.get_my_role();
  v_role_level  int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id  uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_app         public.applicants%ROWTYPE;
  v_vac         public.vacancies%ROWTYPE;
  v_hr          public.hr_emploc%ROWTYPE;
  v_full_name   text;
  v_hired_by_id uuid;
  v_is_roving   boolean;
  v_store_link_id uuid;
  v_late_result   jsonb;
  -- fast-track vars
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────────────────
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock applicant ─────────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.status, 'New') IN (
    'Failed', 'Backout', 'Did Not Report', 'Rejected by Ops'
  ) THEN
    RAISE EXCEPTION
      'cannot confirm onboarding: applicant is in terminal status %', v_app.status
      USING ERRCODE = '22023';
  END IF;

  -- ── Resolve roving flag ───────────────────────────────────────────────────
  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  -- ── Idempotent guard ─────────────────────────────────────────────────────
  IF v_app.status = 'Confirmed Onboard' THEN
    IF v_is_roving THEN
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
         AND assignment_type = 'Roving'
         AND deleted_at IS NULL
       ORDER BY created_at ASC LIMIT 1;
    ELSE
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE deleted_at IS NULL
         AND (
           applicant_id = v_app.id
           OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
         )
       ORDER BY created_at DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
      'ok',               true,
      'applicant_id',     v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id',     v_hr.id,
      'vcode',            v_app.vacancy_vcode,
      'idempotent',       true
    );
  END IF;

  -- ── Fetch and lock vacancy ────────────────────────────────────────────────
  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'active vacancy not found for vcode %', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_vac.has_pending_closure, false) = true THEN
    RAISE EXCEPTION
      'onboarding blocked: vacancy % has a pending closure request. Withdraw the closure request first.',
      v_vac.vcode
      USING ERRCODE = '55000';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF p_contact_number IS NOT NULL AND btrim(p_contact_number) <> '' THEN
    PERFORM public.fn_validate_ph_contact_number(p_contact_number);
  END IF;

  -- ── Resolve full name ─────────────────────────────────────────────────────
  v_full_name := COALESCE(
    NULLIF(btrim(p_full_name), ''),
    NULLIF(btrim(concat_ws(' ',
      NULLIF(p_first_name, ''),
      NULLIF(p_middle_name, ''),
      NULLIF(p_last_name, '')
    )), ''),
    v_app.full_name
  );

  v_hired_by_id := COALESCE(p_hired_by_user_id, v_profile_id);

  -- ── Update applicant ─────────────────────────────────────────────────────
  -- p_hired_date (caller-supplied) takes precedence over any existing
  -- hired_date; falls back to CURRENT_DATE only when both are absent.
  -- RETURNING * captures slot_id (Phase B-backfilled) for Phase C propagation.
  UPDATE public.applicants
  SET
    last_name                = COALESCE(NULLIF(p_last_name, ''),    last_name),
    first_name               = COALESCE(NULLIF(p_first_name, ''),   first_name),
    middle_name              = p_middle_name,
    full_name                = v_full_name,
    full_name_snapshot       = v_full_name,
    contact_number           = COALESCE(NULLIF(p_contact_number, ''), contact_number),
    remarks                  = p_remarks,
    roving_assignment_id     = COALESCE(p_roving_assignment_id, roving_assignment_id),
    status                   = 'Confirmed Onboard',
    hired_date               = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
    hired_at                 = COALESCE(hired_at, NOW()),
    hired_by                 = v_actor_name,
    hired_by_team            = v_role,
    hired_by_user_id         = v_hired_by_id,
    endorsed_by_deployer_id  = p_endorsed_by_deployer_id,
    endorsed_by_name         = p_endorsed_by_name,
    deployed_by_user_id      = v_profile_id,
    is_archived              = false,
    updated_at               = NOW(),
    updated_by               = v_profile_id
  WHERE id = p_applicant_id
  RETURNING * INTO v_app;
  -- v_app.slot_id now reflects the Phase B-backfilled value (or NULL for
  -- no-slot VCODEs / roving). Used in Phase C propagation below.

  -- ── Existing employee fast-track ──────────────────────────────────────────
  -- Employee numbers already in active Plantilla do not go back through HR
  -- Emploc. For roving/multi-store approvals, reuse the existing Plantilla
  -- employee and add/activate only the missing store assignment.
  SELECT * INTO v_existing_plt
    FROM public.plantilla
   WHERE account = v_vac.account
     AND status = 'Active'
     AND is_deleted = false
     AND employee_no IS NOT NULL
     AND (
       (
         COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL
         AND roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       )
       OR LOWER(TRIM(employee_name)) = LOWER(TRIM(v_full_name))
     )
   ORDER BY
     CASE
       WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
       ELSE 1
     END,
     created_at DESC
   LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    v_roving_id := COALESCE(
      v_existing_plt.roving_assignment_id,
      p_roving_assignment_id,
      v_app.roving_assignment_id
    );

    IF v_roving_id IS NULL THEN
      INSERT INTO public.roving_assignments (
        master_applicant_id, account, account_id,
        primary_vcode, label, created_by, updated_by
      ) VALUES (
        v_app.id, v_vac.account, v_vac.account_id,
        COALESCE(v_existing_plt.vcode, v_vac.vcode),
        v_full_name,
        v_profile_id, v_profile_id
      )
      RETURNING id INTO v_roving_id;

      v_new_roving := true;
    END IF;

    UPDATE public.applicants
    SET
      roving_assignment_id = v_roving_id,
      updated_at = NOW(),
      updated_by = v_profile_id
    WHERE id = v_app.id
    RETURNING * INTO v_app;

    UPDATE public.plantilla
    SET
      deployment_type      = 'Roving',
      roving_assignment_id = v_roving_id,
      updated_at           = NOW(),
      updated_by           = v_profile_id
    WHERE id = v_existing_plt.id;

    IF v_existing_plt.vcode IS NOT NULL THEN
      SELECT id INTO v_plt_store_link_id
        FROM public.plantilla_store_links
       WHERE plantilla_id = v_existing_plt.id
         AND roving_assignment_id = v_roving_id
         AND (vacancy_id = v_existing_plt.vacancy_id OR vcode = v_existing_plt.vcode)
         AND deleted_at IS NULL
       LIMIT 1
      FOR UPDATE;

      IF v_plt_store_link_id IS NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, roving_assignment_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_existing_plt.id, v_roving_id,
          v_existing_plt.vacancy_id, v_existing_plt.vcode,
          v_existing_plt.store_name, v_existing_plt.account,
          'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    v_plt_store_link_id := NULL;

    SELECT id INTO v_plt_store_link_id
      FROM public.plantilla_store_links
     WHERE plantilla_id = v_existing_plt.id
       AND roving_assignment_id = v_roving_id
       AND (
         vacancy_id = v_vac.id
         OR vcode = v_vac.vcode
         OR (
           account = v_vac.account
           AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
         )
       )
       AND deleted_at IS NULL
     LIMIT 1
    FOR UPDATE;

    IF v_plt_store_link_id IS NULL THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_roving_id,
        v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_plt_store_link_id;

      IF v_plt_store_link_id IS NULL THEN
        SELECT id INTO v_plt_store_link_id
         FROM public.plantilla_store_links
         WHERE plantilla_id = v_existing_plt.id
           AND roving_assignment_id = v_roving_id
           AND (
             vacancy_id = v_vac.id
             OR vcode = v_vac.vcode
             OR (
               account = v_vac.account
               AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
             )
           )
           AND deleted_at IS NULL
         LIMIT 1;
      END IF;
    ELSE
      UPDATE public.plantilla_store_links
      SET
        status      = 'Active',
        unlinked_at = NULL,
        unlinked_by = NULL,
        updated_at  = NOW(),
        updated_by  = v_profile_id
      WHERE id = v_plt_store_link_id;
    END IF;

    UPDATE public.vacancies
    SET
      status     = 'Filled',
      updated_at = NOW(),
      updated_by = v_profile_id
    WHERE id = v_vac.id;

    INSERT INTO public.employee_activity_log (
      emploc_no, vcode, activity_type, description, performed_by, metadata
    ) VALUES (
      COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_app.full_name),
      v_vac.vcode,
      'confirmed_onboard_fast_track',
      'Existing Plantilla employee fast-tracked to new store, bypassing HR Emploc queue for ' || v_vac.vcode,
      v_actor_name,
      jsonb_build_object(
        'applicant_id',              v_app.id,
        'hr_emploc_id',              NULL,
        'plantilla_id',              v_existing_plt.id,
        'plantilla_store_link_id',   v_plt_store_link_id,
        'vacancy_id',                v_vac.id,
        'employee_no',               v_existing_plt.employee_no,
        'roving_assignment_id',      v_roving_id,
        'new_roving_created',        v_new_roving,
        'skipped_hr_emploc',         true,
        'role',                      v_role,
        'hired_by_user_id',          v_hired_by_id,
        'hired_date',                v_app.hired_date,
        'movement_at',               NOW()
      )
    );

    -- Fast-track: existing Plantilla employee bypasses HR Emploc entirely.
    -- No slot sync here — this path skips the hr_processing state and goes
    -- directly to occupied (handled by Phase 6.3 in move_to_plantilla).
    RETURN jsonb_build_object(
      'ok',                       true,
      'applicant_id',             v_app.id,
      'applicant_status',         v_app.status,
      'hr_emploc_id',             NULL,
      'plantilla_id',             v_existing_plt.id,
      'plantilla_store_link_id',  v_plt_store_link_id,
      'vcode',                    v_vac.vcode,
      'hired_by_user_id',         v_hired_by_id,
      'hired_date',               v_app.hired_date,
      'is_roving',                true,
      'fast_tracked',             true,
      'skipped_hr_emploc',        true,
      'new_roving_created',       v_new_roving
    );
  END IF;

  -- ── Find or create HR Emploc ──────────────────────────────────────────────
  IF v_is_roving THEN
    -- ROVING: look for existing master by roving_assignment_id
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       AND assignment_type = 'Roving'
       AND deleted_at IS NULL
     ORDER BY created_at ASC LIMIT 1
    FOR UPDATE;

    v_roving_hr_found := FOUND;

    IF v_roving_hr_found THEN
      v_existing_employee_no := COALESCE(
        NULLIF(BTRIM(v_hr.employee_no), ''),
        NULLIF(BTRIM(v_hr.emploc_no), '')
      );

      IF v_hr.status = 'Moved to Plantilla' OR v_existing_employee_no IS NOT NULL THEN
        SELECT * INTO v_existing_plt
          FROM public.plantilla
         WHERE is_deleted = false
           AND status IN ('Active', 'For Deactivation', 'On Leave')
           AND (
             roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
             OR hr_emploc_id = v_hr.id
             OR (
               v_existing_employee_no IS NOT NULL
               AND employee_no = v_existing_employee_no
               AND account = v_vac.account
             )
           )
         ORDER BY
           CASE
             WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
             WHEN hr_emploc_id = v_hr.id THEN 1
             ELSE 2
           END,
           created_at DESC
         LIMIT 1
        FOR UPDATE;

        IF FOUND THEN
          v_roving_id := COALESCE(
            v_existing_plt.roving_assignment_id,
            v_hr.roving_assignment_id,
            p_roving_assignment_id,
            v_app.roving_assignment_id
          );

          UPDATE public.applicants
          SET
            roving_assignment_id = v_roving_id,
            updated_at = NOW(),
            updated_by = v_profile_id
          WHERE id = v_app.id
          RETURNING * INTO v_app;

          UPDATE public.plantilla
          SET
            deployment_type      = 'Roving',
            roving_assignment_id = v_roving_id,
            updated_at           = NOW(),
            updated_by           = v_profile_id
          WHERE id = v_existing_plt.id;

          SELECT id INTO v_plt_store_link_id
            FROM public.plantilla_store_links
           WHERE plantilla_id = v_existing_plt.id
             AND roving_assignment_id = v_roving_id
             AND (
               vacancy_id = v_vac.id
               OR vcode = v_vac.vcode
               OR (
                 account = v_vac.account
                 AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
               )
             )
             AND deleted_at IS NULL
           LIMIT 1
          FOR UPDATE;

          IF v_plt_store_link_id IS NULL THEN
            INSERT INTO public.plantilla_store_links (
              plantilla_id, roving_assignment_id,
              vacancy_id, vcode, store_name, account,
              status, linked_at, linked_by, created_by, updated_by
            ) VALUES (
              v_existing_plt.id, v_roving_id,
              v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
              'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
            )
            ON CONFLICT DO NOTHING
            RETURNING id INTO v_plt_store_link_id;

            IF v_plt_store_link_id IS NULL THEN
              SELECT id INTO v_plt_store_link_id
                FROM public.plantilla_store_links
               WHERE plantilla_id = v_existing_plt.id
                 AND roving_assignment_id = v_roving_id
                 AND (
                   vacancy_id = v_vac.id
                   OR vcode = v_vac.vcode
                   OR (
                     account = v_vac.account
                     AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, '')))
                   )
                 )
                 AND deleted_at IS NULL
               LIMIT 1;
            END IF;
          ELSE
            UPDATE public.plantilla_store_links
            SET
              status      = 'Active',
              unlinked_at = NULL,
              unlinked_by = NULL,
              updated_at  = NOW(),
              updated_by  = v_profile_id
            WHERE id = v_plt_store_link_id;
          END IF;

          UPDATE public.vacancies
          SET
            status     = 'Filled',
            updated_at = NOW(),
            updated_by = v_profile_id
          WHERE id = v_vac.id;

          INSERT INTO public.employee_activity_log (
            emploc_no, vcode, activity_type, description, performed_by, metadata
          ) VALUES (
            COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_existing_employee_no, v_app.full_name),
            v_vac.vcode,
            'confirmed_onboard_fast_track',
            'Existing roving employee fast-tracked to new store, bypassing duplicate HR Emploc creation for ' || v_vac.vcode,
            v_actor_name,
            jsonb_build_object(
              'applicant_id',              v_app.id,
              'hr_emploc_id',              v_hr.id,
              'plantilla_id',              v_existing_plt.id,
              'plantilla_store_link_id',   v_plt_store_link_id,
              'vacancy_id',                v_vac.id,
              'employee_no',               COALESCE(v_existing_plt.employee_no, v_existing_employee_no),
              'roving_assignment_id',      v_roving_id,
              'skipped_hr_emploc_insert',  true,
              'role',                      v_role,
              'hired_by_user_id',          v_hired_by_id,
              'hired_date',                v_app.hired_date,
              'movement_at',               NOW()
            )
          );

          -- Roving fast-track duplicate guard: no slot sync (roving carve-out).
          RETURN jsonb_build_object(
            'ok',                       true,
            'applicant_id',             v_app.id,
            'applicant_status',         v_app.status,
            'hr_emploc_id',             v_hr.id,
            'plantilla_id',             v_existing_plt.id,
            'plantilla_store_link_id',  v_plt_store_link_id,
            'vcode',                    v_vac.vcode,
            'hired_by_user_id',         v_hired_by_id,
            'hired_date',               v_app.hired_date,
            'is_roving',                true,
            'fast_tracked',             true,
            'skipped_hr_emploc',        true,
            'duplicate_roving_guard',   true
          );
        END IF;
      END IF;
    END IF;

    IF NOT v_roving_hr_found THEN
      -- First store: create roving master.
      -- Roving INSERT: no slot_id (roving carve-out — OHM2026_0044).
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_code_snapshot,
        account, account_id, chain_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Roving'::public.hr_emploc_assignment_type,
        COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
        '[]'::jsonb
      )
      ON CONFLICT DO NOTHING
      RETURNING * INTO v_hr;

      IF v_hr.id IS NULL THEN
        SELECT * INTO v_hr
          FROM public.hr_emploc
         WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
           AND assignment_type = 'Roving'
           AND deleted_at IS NULL
         ORDER BY created_at ASC LIMIT 1
        FOR UPDATE;
      END IF;
    END IF;

    -- Insert store link (idempotent)
    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, roving_assignment_id, vacancy_id, vcode,
      store_name, account, status, confirmed_at, confirmed_by,
      created_by, updated_by
    ) VALUES (
      v_hr.id,
      COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
      v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_store_link_id;

    -- ── Late store auto-link ─────────────────────────────────────────────
    IF v_hr.status = 'Moved to Plantilla' AND v_store_link_id IS NOT NULL THEN
      SELECT public.link_late_store_to_plantilla(v_store_link_id) INTO v_late_result;
    END IF;

  ELSE
    -- ── STATIONARY: find or create HR Emploc ────────────────────────────────
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE deleted_at IS NULL
       AND (
         applicant_id = v_app.id
         OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
       )
     ORDER BY created_at DESC LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      -- Phase C: propagate applicants.slot_id into hr_emploc.slot_id at INSERT.
      -- v_app.slot_id is the Phase B-backfilled exact slot (NULL for no-slot
      -- VCODEs and roving — those rows have NULL assignment_type='Stationary'
      -- only when there is genuinely no slot for the VCODE).
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores,
        slot_id   -- Phase C (OHM2026_0045): exact slot from applicant; NULL for no-slot VCODEs
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb,
        v_app.slot_id   -- Phase C: NULL when applicant has no bound slot
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  -- ── Audit log ────────────────────────────────────────────────────────────
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id',            v_app.id,
      'hr_emploc_id',            v_hr.id,
      'vacancy_id',              v_vac.id,
      'role',                    v_role,
      'hired_by_user_id',        v_hired_by_id,
      'endorsed_by_deployer_id', p_endorsed_by_deployer_id,
      'endorsed_by_name',        p_endorsed_by_name,
      'is_roving',               v_is_roving,
      'hired_date',              v_app.hired_date,
      'late_store_linked',       v_late_result IS NOT NULL,
      'movement_at',             NOW()
    )
  );

  -- ── Phase C: non-blocking slot pipeline→hr_processing sync ───────────────
  -- Phase C upgrade of Phase 6.2 hook (OHM2026_0020/0045).
  -- Only fires for stationary (non-roving) applicants; roving slots remain
  -- deferred (OHM2026_0017/0044 roving carve-out).
  --
  -- v_app.slot_id IS NOT NULL → fn_sync_slot_to_hr_processing uses the exact
  --   slot (p_slot_id path); no VCODE LIMIT 1 lookup; no slot ambiguity under
  --   N-slot VCODEs.
  -- v_app.slot_id IS NULL → helper falls back to legacy VCODE LIMIT 1 path
  --   (no-slot VCODEs / pre-backfill edge rows). Onboard is NEVER blocked.
  --
  -- Non-blocking: fn_sync_slot_to_hr_processing NEVER raises; a slot error
  -- will not roll back this function's HR Emploc creation, audit log, or
  -- applicant writes. (OHM2026_0044 §Q3)
  IF NOT v_is_roving THEN
    PERFORM public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard',
      p_slot_id      => v_app.slot_id   -- Phase C: exact slot; NULL → legacy path
    );
  END IF;

  RETURN jsonb_build_object(
    'ok',               true,
    'applicant_id',     v_app.id,
    'applicant_status', v_app.status,
    'hr_emploc_id',     v_hr.id,
    'vcode',            v_vac.vcode,
    'hired_by_user_id', v_hired_by_id,
    'hired_date',       v_app.hired_date,
    'is_roving',        v_is_roving,
    'late_store_linked', v_late_result
  );
END;
$function$;

COMMENT ON FUNCTION public.confirm_applicant_onboard(uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date) IS
  'Confirms an applicant for onboarding and creates the HR Emploc record. '
  'Phase C (OHM2026_0045): copies applicants.slot_id → hr_emploc.slot_id at '
  'stationary INSERT; passes exact p_slot_id to fn_sync_slot_to_hr_processing '
  'so pipeline→hr_processing targets the exact slot (no VCODE LIMIT 1). '
  'NULL slot_id (no-slot VCODE / roving) → hr_emploc.slot_id stays NULL, '
  'helper falls back to legacy VCODE path; onboard never blocked. '
  'Phase 6.2 (OHM2026_0020): syncs pipeline→hr_processing after audit log, '
  'stationary non-fast-track path only. Roving excluded (carve-out).';


-- ============================================================
-- §C5a — Replace fn_sync_slot_hr_processing_to_open
--         (add exact p_slot_id path; retire VCODE LIMIT 1 for slot-aware callers)
-- ============================================================
-- Phase 6.5 (OHM2026_0023) created this helper with a VCODE-only lookup.
-- Phase C adds p_slot_id (uuid DEFAULT NULL) as the 6th parameter:
--   • p_slot_id IS NOT NULL → use exact slot directly (capture-before-archive
--     pattern: v_emp.slot_id read before the archive UPDATE in the host RPC)
--   • p_slot_id IS NULL     → fall back to legacy VCODE LIMIT 1 path
--
-- The old 5-parameter signature is dropped and replaced with the 6-parameter
-- signature. fn_approve_emploc_deletion_request (§C5b) is updated in this
-- migration to call the new signature. No other callers exist.
--
-- Non-blocking contract: NEVER RAISES into the host RPC.
-- Aging: hr_processing → open writes new_value='open' → aging restarts.

DROP FUNCTION IF EXISTS public.fn_sync_slot_hr_processing_to_open(text, uuid, text, uuid, text);

CREATE OR REPLACE FUNCTION public.fn_sync_slot_hr_processing_to_open(
  p_vcode            text,
  p_hr_emploc_id     uuid    DEFAULT NULL,
  p_deletion_reason  text    DEFAULT NULL,
  p_performed_by     uuid    DEFAULT NULL,
  p_source_fn        text    DEFAULT NULL,
  p_slot_id          uuid    DEFAULT NULL    -- Phase C: exact slot (preferred over VCODE lookup)
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Phase C upgrade — non-blocking hr_processing→open slot sync (OHM2026_0045).

  Phase C adds p_slot_id: when non-NULL (v_emp.slot_id captured before the
  emploc archive in fn_approve_emploc_deletion_request), the exact slot is
  used directly — no legacy_vcode LIMIT 1 lookup, slot_ordinal preserved,
  aging restarts correctly (OHM2026_0044 §Q5).
  When NULL (legacy no-slot HR Emploc row / roving / hr_emploc_id was NULL),
  falls back to the Phase 6.5 VCODE LIMIT 1 legacy path.

  Called only for Backout deletion type — Duplicate Record is excluded by the
  host RPC guard (IF v_req.deletion_type = 'Backout').

  Reason code: REPLACEMENT (task-specified for Phase 6.5/C, per OHM2026_0023/0045).
  new_value='open' written to slot_history → aging episode restarts.
*/
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN

  -- ── Phase C: exact slot_id path ─────────────────────────────────────────
  IF p_slot_id IS NOT NULL THEN
    SELECT public.fn_set_slot_status(
      p_slot_id               => p_slot_id,
      p_new_status            => 'open',
      p_reason_code           => 'REPLACEMENT',
      p_performed_by          => p_performed_by,
      p_remarks               => format(
        'Phase C / %s / VCODE=%s / hr_emploc_id=%s / reason=%s / slot_id=%s',
        COALESCE(p_source_fn,       'unknown'),
        COALESCE(p_vcode,           'unknown'),
        COALESCE(p_hr_emploc_id::text, 'null'),
        COALESCE(p_deletion_reason, 'null'),
        p_slot_id
      ),
      p_occupant_plantilla_id => NULL
    ) INTO v_result;

    IF (v_result->>'status') IN ('blocked', 'no_op') THEN
      RAISE NOTICE
        'fn_sync_slot_hr_processing_to_open (exact): % for slot_id=% VCODE=% source=% — %',
        v_result->>'status',
        p_slot_id,
        COALESCE(p_vcode, 'unknown'),
        COALESCE(p_source_fn, 'unknown'),
        COALESCE(v_result->>'blocked_reason', 'same-state no_op');
    END IF;

    RETURN v_result;
  END IF;

  -- ── Legacy path: VCODE LIMIT 1 (Phase 6.5 — no-slot VCODEs, roving) ────
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_slot_hr_processing_to_open: skipped — p_vcode null/empty '
      'and p_slot_id null (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  -- Locate slot via legacy_vcode bridge (non-roving only).
  SELECT id INTO v_slot_id
  FROM   public.plantilla_slots
  WHERE  legacy_vcode = p_vcode
    AND  is_roving    = false
  LIMIT  1;

  IF v_slot_id IS NULL THEN
    -- No slot for this VCODE (pre-slot-era legacy vacancy or roving) — skip.
    RETURN NULL;
  END IF;

  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'open',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
      'Phase 6.5 (legacy vcode path) / %s / VCODE=%s / hr_emploc_id=%s / reason=%s',
      COALESCE(p_source_fn,       'unknown'),
      p_vcode,
      COALESCE(p_hr_emploc_id::text, 'null'),
      COALESCE(p_deletion_reason, 'null')
    ),
    p_occupant_plantilla_id => NULL
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_hr_processing_to_open (legacy): % for slot_id=% VCODE=% source=% — %',
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
    'fn_sync_slot_hr_processing_to_open: error for VCODE=% slot_id=% source=% — % (sqlstate=%)',
    COALESCE(p_vcode, 'null'),
    COALESCE(p_slot_id::text, 'null'),
    COALESCE(p_source_fn, 'unknown'),
    SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_slot_hr_processing_to_open(text, uuid, text, uuid, text, uuid) IS
  'Phase C (OHM2026_0045) upgrade of Phase 6.5 (OHM2026_0023) helper. '
  'Non-blocking hr_processing→open slot sync on HR Emploc Backout approval. '
  'p_slot_id IS NOT NULL → exact slot used directly (capture-before-archive); '
  'p_slot_id IS NULL → legacy VCODE LIMIT 1 fallback for no-slot VCODEs / roving. '
  'NEVER raises. Blocked/no_op results are RAISE NOTICEd and returned. '
  'new_value=open in slot_history → aging episode restarts. '
  'Callers: fn_approve_emploc_deletion_request (Backout deletion type only). '
  'Reason code: REPLACEMENT. See OHM2026_0044 §Q5.';


-- ============================================================
-- §C5b — Replace fn_approve_emploc_deletion_request
--         (Phase C: pass p_slot_id = v_emp.slot_id to reopen exact slot)
-- ============================================================
-- Source: 20260813000005_wire_hr_processing_open_slot_transition.sql §2
--         (Phase 6.5 version — the basis patched here).
--
-- Phase C change (the ONLY change; all other behavior IDENTICAL to Phase 6.5):
--   In the Phase 6.5 hook block (IF v_req.deletion_type = 'Backout'):
--     • Add p_slot_id => v_emp.slot_id to the fn_sync_slot_hr_processing_to_open call.
--     • v_emp is populated from SELECT * FOR UPDATE on public.hr_emploc earlier in
--       this function (BEFORE the archive UPDATE that sets deleted_at), so
--       v_emp.slot_id is the Phase C-backfilled value at the time of backout.
--     • When v_emp.slot_id IS NOT NULL → helper uses exact slot (no VCODE LIMIT 1).
--     • When v_emp.slot_id IS NULL (no-slot / roving / hr_emploc_id was NULL) →
--       helper falls back to legacy VCODE LIMIT 1 path.
--
-- Capture-before-archive is guaranteed: v_emp is populated by the FOR UPDATE
-- SELECT well before the archive UPDATE — v_emp.slot_id is never null-out by
-- the archive (which only sets deleted_at). (OHM2026_0044 §Q5/Q7)
--
-- Return type (void), RBAC, scope check, emploc lifecycle validation,
-- correction auto-close, emploc archive, applicant archive, vacancy reopen,
-- request status update, approval snapshot, trigger notifications: all
-- IDENTICAL to Phase 6.5.

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

  -- Lock and validate hr_emploc lifecycle.
  -- Phase C: v_emp is populated here (before the archive UPDATE below) so that
  -- v_emp.slot_id is available for the exact-slot reopen in the Phase C hook.
  -- The archive UPDATE sets deleted_at on the DB row but does NOT change the
  -- local v_emp variable — v_emp.slot_id remains the captured pre-archive value.
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

    -- Archive emploc (never hard delete — archive-first invariant).
    -- v_emp.slot_id is still the pre-archive value after this UPDATE.
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

  -- ── Phase C: non-blocking slot hr_processing→open reopen ──────────────────
  -- Phase C upgrade of Phase 6.5 hook (OHM2026_0023/0045).
  -- Only fires for Backout type — Duplicate Record is data-cleanup and does not
  -- represent an HR processing abandonment.
  --
  -- v_emp.slot_id IS NOT NULL → fn_sync_slot_hr_processing_to_open uses the exact
  --   slot (p_slot_id path); slot_ordinal preserved; no VCODE LIMIT 1 ambiguity.
  -- v_emp.slot_id IS NULL (no-slot / roving / hr_emploc_id was NULL) → helper
  --   falls back to legacy VCODE LIMIT 1 path.
  --
  -- Capture-before-archive is guaranteed: v_emp was populated by FOR UPDATE SELECT
  -- before the archive UPDATE; v_emp.slot_id is the pre-archive value and remains
  -- accessible here. (OHM2026_0044 §Q5 — archive-first capture rule)
  --
  -- Non-blocking: fn_sync_slot_hr_processing_to_open NEVER raises; a slot error
  -- will not roll back emploc archive, applicant archive, vacancy reopen,
  -- request update, or activity log writes.
  IF v_req.deletion_type = 'Backout' THEN
    PERFORM public.fn_sync_slot_hr_processing_to_open(
      p_vcode           => v_req.vcode,
      p_hr_emploc_id    => v_req.hr_emploc_id,
      p_deletion_reason => v_req.reason,
      p_performed_by    => public.get_my_profile_id(),
      p_source_fn       => 'fn_approve_emploc_deletion_request',
      p_slot_id         => v_emp.slot_id   -- Phase C: exact slot; NULL → legacy path
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
  'Phase C (OHM2026_0045): passes v_emp.slot_id (captured pre-archive) to '
  'fn_sync_slot_hr_processing_to_open so the exact slot is reopened '
  'hr_processing→open (no VCODE LIMIT 1). NULL slot_id → legacy VCODE path. '
  'Phase 6.5 (OHM2026_0023): hr_processing→open slot reopen after approval '
  'activity write, Backout path only, via fn_sync_slot_hr_processing_to_open.';


-- ============================================================
-- §C6 — GRANTs
-- ============================================================

-- fn_sync_slot_to_hr_processing: new 5-param signature.
-- Old 4-param was dropped in §C4a; revoke/grant on new signature.
REVOKE ALL ON FUNCTION public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text, uuid)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_sync_slot_to_hr_processing(text, uuid, uuid, text, uuid)
  TO authenticated;

-- fn_sync_slot_hr_processing_to_open: new 6-param signature.
-- Old 5-param was dropped in §C5a; revoke/grant on new signature.
REVOKE ALL ON FUNCTION public.fn_sync_slot_hr_processing_to_open(text, uuid, text, uuid, text, uuid)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_sync_slot_hr_processing_to_open(text, uuid, text, uuid, text, uuid)
  TO authenticated;

-- Preserve existing GRANTs on patched host RPCs (unchanged from Phase 6.2/6.5).
GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(
  uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_approve_emploc_deletion_request(uuid, text)
  TO authenticated;


-- ============================================================
-- §C7 — Post-migration validation queries (run manually)
-- ============================================================
--
-- ── Structural checks ────────────────────────────────────────────────────
--
-- V1 — uq_hr_emploc_one_active_per_slot index exists and is partial.
--   SELECT indexname, indexdef
--     FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'hr_emploc'
--       AND indexname  = 'uq_hr_emploc_one_active_per_slot';
--   -- Expected: 1 row; indexdef contains WHERE slot_id IS NOT NULL AND deleted_at IS NULL.
--
-- V2 — fn_sync_slot_to_hr_processing exists with new 5-param signature.
--   SELECT specific_name, routine_type, security_type
--     FROM information_schema.routines
--     WHERE routine_schema = 'public'
--       AND routine_name   = 'fn_sync_slot_to_hr_processing';
--   -- Expected: 1 row (5-param version only; old 4-param was dropped).
--
-- V3 — fn_sync_slot_hr_processing_to_open exists with new 6-param signature.
--   SELECT specific_name, routine_type, security_type
--     FROM information_schema.routines
--     WHERE routine_schema = 'public'
--       AND routine_name   = 'fn_sync_slot_hr_processing_to_open';
--   -- Expected: 1 row (6-param version only; old 5-param was dropped).
--
-- V4 — confirm_applicant_onboard body includes Phase C changes.
--   SELECT prosrc LIKE '%v_app.slot_id%'
--     FROM pg_proc
--     WHERE proname      = 'confirm_applicant_onboard'
--       AND pronamespace = 'public'::regnamespace;
--   -- Expected: true (slot_id propagation present).
--
-- V5 — fn_approve_emploc_deletion_request body includes Phase C change.
--   SELECT prosrc LIKE '%v_emp.slot_id%'
--     FROM pg_proc
--     WHERE proname      = 'fn_approve_emploc_deletion_request'
--       AND pronamespace = 'public'::regnamespace;
--   -- Expected: true (exact slot reopen via v_emp.slot_id present).
--
-- ── Data invariant checks (C1–C12 parity) ───────────────────────────────
--
-- C1 — Every hr_processing non-roving slot has exactly one active HR Emploc row.
--   SELECT ps.id, ps.legacy_vcode,
--          COUNT(he.id) AS active_emploc_rows
--     FROM public.plantilla_slots ps
--     LEFT JOIN public.hr_emploc he
--       ON he.slot_id = ps.id AND he.deleted_at IS NULL
--     WHERE ps.slot_status = 'hr_processing'
--       AND ps.is_roving   = false
--     GROUP BY ps.id, ps.legacy_vcode
--     HAVING COUNT(he.id) != 1;
--   -- Expected: 0 rows.
--
-- C2 — No two active HR Emploc rows share the same slot_id.
--   SELECT slot_id, COUNT(*) AS cnt
--     FROM public.hr_emploc
--     WHERE slot_id IS NOT NULL AND deleted_at IS NULL
--     GROUP BY slot_id HAVING COUNT(*) > 1;
--   -- Expected: 0 rows.
--
-- C3 — Every active stationary HR Emploc row on a slot-backed VCODE
--      has a non-NULL slot_id.
--   SELECT COUNT(*) AS unbound_active
--     FROM public.hr_emploc he
--     WHERE he.slot_id IS NULL
--       AND he.deleted_at IS NULL
--       AND he.assignment_type = 'Stationary'
--       AND EXISTS (
--         SELECT 1 FROM public.plantilla_slots ps
--         WHERE ps.legacy_vcode = he.vcode AND ps.is_roving = false
--       );
--   -- Expected: 0.
--
-- C4 — Binding matches VCODE (slot.legacy_vcode = hr_emploc.vcode).
--   SELECT COUNT(*) AS mismatched
--     FROM public.hr_emploc he
--     JOIN public.plantilla_slots ps ON ps.id = he.slot_id
--     WHERE ps.legacy_vcode != he.vcode;
--   -- Expected: 0.
--
-- C5 — At Confirmed Onboard, hr_emploc.slot_id == applicants.slot_id.
--   SELECT COUNT(*) AS propagation_mismatch
--     FROM public.hr_emploc he
--     JOIN public.applicants a ON a.id = he.applicant_id
--     WHERE he.deleted_at IS NULL
--       AND he.assignment_type = 'Stationary'
--       AND he.slot_id IS NOT NULL
--       AND a.slot_id IS NOT NULL
--       AND he.slot_id != a.slot_id;
--   -- Expected: 0.
--
-- C6 — No active HR Emploc row bound to an open/pipeline/closed slot.
--   SELECT he.id, he.vcode, ps.slot_status
--     FROM public.hr_emploc he
--     JOIN public.plantilla_slots ps ON ps.id = he.slot_id
--     WHERE he.deleted_at IS NULL
--       AND ps.slot_status NOT IN ('hr_processing', 'occupied');
--   -- Expected: 0 rows.
--
-- C7 — Every non-roving slot in hr_processing is owned by active HR Emploc.
--   SELECT ps.id, ps.legacy_vcode
--     FROM public.plantilla_slots ps
--     WHERE ps.slot_status = 'hr_processing'
--       AND ps.is_roving   = false
--       AND NOT EXISTS (
--         SELECT 1 FROM public.hr_emploc he
--         WHERE he.slot_id = ps.id AND he.deleted_at IS NULL
--       );
--   -- Expected: 0 rows (no orphan hr_processing slots).
--
-- C8 — FK integrity: no orphan slot_id in hr_emploc.
--   SELECT COUNT(*) AS orphans
--     FROM public.hr_emploc he
--     LEFT JOIN public.plantilla_slots ps ON ps.id = he.slot_id
--     WHERE he.slot_id IS NOT NULL AND ps.id IS NULL;
--   -- Expected: 0.
--
-- C9 — Roving HR Emploc rows have NULL slot_id.
--   SELECT COUNT(*) AS roving_with_slot
--     FROM public.hr_emploc
--     WHERE assignment_type = 'Roving' AND slot_id IS NOT NULL;
--   -- Expected: 0.
--
-- C10 — Backout reopen: exact slot_ordinal preserved.
--   (After approving a Backout deletion request for a stationary HR Emploc
--    whose slot was in hr_processing)
--   SELECT ps.slot_status, ps.slot_ordinal,
--          sh.action_type, sh.new_value, sh.reason_code, sh.remarks
--     FROM public.plantilla_slots ps
--     JOIN public.slot_history sh ON sh.slot_id = ps.id
--     WHERE ps.legacy_vcode = '<test_vcode>'
--     ORDER BY sh.created_at DESC LIMIT 3;
--   -- Expected latest row: action_type='reopened', new_value='open',
--   --   reason_code='REPLACEMENT', remarks includes 'Phase C'.
--   -- slot_ordinal is unchanged from before the backout (ordinal preserved).
--
-- C11 — Slot-side vs HR-side hr_processing counts agree per VCODE.
--   SELECT
--     slot_side.legacy_vcode,
--     slot_side.hr_processing_slots,
--     hr_side.active_emploc_rows
--   FROM (
--     SELECT legacy_vcode, COUNT(*) AS hr_processing_slots
--       FROM public.plantilla_slots
--       WHERE slot_status = 'hr_processing' AND is_roving = false
--       GROUP BY legacy_vcode
--   ) slot_side
--   FULL OUTER JOIN (
--     SELECT vcode, COUNT(*) AS active_emploc_rows
--       FROM public.hr_emploc
--       WHERE slot_id IS NOT NULL AND deleted_at IS NULL
--       GROUP BY vcode
--   ) hr_side ON hr_side.vcode = slot_side.legacy_vcode
--   WHERE COALESCE(slot_side.hr_processing_slots, 0)
--      != COALESCE(hr_side.active_emploc_rows, 0);
--   -- Expected: 0 rows.
--
-- C12 — P1–P8 (OHM2026_0016/0039) + B1–B10 (OHM2026_0042) re-run GREEN.
--   -- Re-run both parity suites. Only intended pipeline↔hr_processing↔open
--   -- moves should differ (if §C3 corrected any discrepancy).
--   -- open and pipeline counts must match Phase B baseline (unchanged by Phase C).
--
-- ── Functional smoke tests ──────────────────────────────────────────────
--
-- S1 — Confirmed Onboard copies slot_id and moves slot to hr_processing.
--   (Confirm a stationary applicant whose slot_id IS NOT NULL)
--   SELECT slot_id FROM public.hr_emploc WHERE id = '<new_hr_emploc_id>';
--   -- Expected: non-NULL uuid matching the applicant's slot_id.
--   SELECT slot_status FROM public.plantilla_slots WHERE id = '<slot_id>';
--   -- Expected: 'hr_processing'.
--   SELECT action_type, new_value, remarks FROM public.slot_history
--     WHERE slot_id = '<slot_id>' ORDER BY created_at DESC LIMIT 1;
--   -- Expected: action_type='hr_processing', new_value='hr_processing',
--   --   remarks includes 'Phase C / confirm_applicant_onboard'.
--
-- S2 — Confirmed Onboard for no-slot VCODE: hr_emploc.slot_id stays NULL,
--      legacy path runs, onboard completes normally.
--   SELECT slot_id FROM public.hr_emploc WHERE id = '<hr_emploc_id_no_slot>';
--   -- Expected: NULL.
--
-- S3 — HR Emploc Backout reopens exact slot.
--   (Approve a Backout deletion request for HR Emploc whose slot was hr_processing)
--   SELECT slot_status FROM public.plantilla_slots WHERE id = '<slot_id>';
--   -- Expected: 'open'.
--   SELECT action_type, new_value, remarks FROM public.slot_history
--     WHERE slot_id = '<slot_id>' ORDER BY created_at DESC LIMIT 1;
--   -- Expected: action_type='reopened', new_value='open',
--   --   remarks includes 'Phase C / fn_approve_emploc_deletion_request'.
--   SELECT slot_ordinal FROM public.plantilla_slots WHERE id = '<slot_id>';
--   -- Expected: same ordinal as before backout (ordinal preserved).
--
-- S4 — Duplicate Record deletion does NOT move the slot.
--   (Approve a Duplicate Record deletion request)
--   SELECT slot_status FROM public.plantilla_slots WHERE legacy_vcode = '<vcode>';
--   -- Expected: unchanged from pre-approval.
--
-- S5 — Return shape of confirm_applicant_onboard unchanged.
--   (Call with a valid stationary applicant)
--   -- Expected JSONB: {ok:true, applicant_id, applicant_status:'Confirmed Onboard',
--   --   hr_emploc_id, vcode, hired_by_user_id, hired_date, is_roving:false,
--   --   late_store_linked} — shape identical to Phase 6.2.
-- ============================================================
