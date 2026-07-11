-- ============================================================
-- OHM2026_0069 — Coverage Group Phase R-B: Applicant-to-Coverage-Slot Binding
-- Migration:  20260823000000_coverage_group_phase_rb_applicant_binding.sql
-- Plan:       docs/architecture/coverage_group_phase_rb_applicant_binding_plan.md (OHM2026_0068)
-- Mirrors:    20260817000000_vcode_slot_phase_b_applicant_binding.sql (stationary Phase B, OHM2026_0041)
-- Depends on:
--   20260822000004_coverage_group_ra4_coverage_slots.sql   (coverage_slots + token CHECK)
--   20260822000005_coverage_group_ra5_eager_slot_emit.sql  (N open slots per group)
--   20260822000006_coverage_group_ra6_binding_columns.sql  (applicants.coverage_slot_id/group_id)
--   20260616000000_restore_fn_is_active_vacancy_applicant_status.sql (canonical active predicate)
--   20260817000000_vcode_slot_phase_b_applicant_binding.sql (fn_update_applicant_status base body)
-- ============================================================
-- Scope: Phase R-B — make applicants.coverage_slot_id the source of truth for
--   roving applicant↔slot ownership and route the open ↔ pipeline lifecycle
--   per coverage slot. The roving peer of stationary Phase B, substituting
--   coverage_slot for plantilla_slot, coverage_group_id for legacy_vcode.
--
-- What this migration does:
--   RB1  Partial unique: one active applicant per coverage_slot
--   RB2  Mutual-exclusivity CHECK: never slot_id AND coverage_slot_id together
--   RB3  fn_set_coverage_slot_status — central open↔pipeline transition helper
--   RB4  fn_release_coverage_slot   — non-blocking terminal release helper
--   RB5  fn_bind_applicant_to_coverage_group — CGCODE claim/bind RPC path
--   RB6  Patch fn_update_applicant_status — add roving terminal-release branch
--   RB7  GRANTs
--   RB8  Post-migration validation queries (RB1–RB10, manual, in comments)
--
-- What this migration deliberately does NOT do (out of scope per task / plan):
--   • Modify stationary VCODE architecture, slot binding, or shadow aggregation
--   • Modify create_applicant_and_link_to_vacancy (stationary claim path) — the
--     stationary slot_id branch of fn_update_applicant_status is preserved verbatim
--   • Modify HR Emploc binding (R-C) / hr_emploc.coverage_slot_id
--   • Modify Plantilla binding (R-C) / plantilla_slots
--   • Migrate legacy roving (roving_assignment_id) records — that is R-F
--   • Touch the roving shadow/card (R-D), closure fan-out (R-E), or UI/reporting
--   • Drive hr_processing / active / closed transitions — fn_set_coverage_slot_status
--     owns ONLY open↔pipeline; every other edge is refused here (later phases)
--
-- Legacy roving applicants (coverage_slot_id IS NULL, still on roving_assignment_id)
-- are skipped by every hook below — the roving branch no-ops on NULL coverage_slot_id,
-- exactly as the stationary branch no-ops on NULL slot_id.
--
-- ============================================================
-- §RB0 — Pre-migration gate (run MANUALLY before applying)
-- ============================================================
--
-- Gate 1: applicants.coverage_slot_id all NULL (R-A shipped the column empty).
--   SELECT COUNT(*) FROM public.applicants WHERE coverage_slot_id IS NOT NULL;
--   -- Expected: 0. Any non-zero = prior partial run; reconcile before re-applying.
--
-- Gate 2: R-A GREEN — every group has exactly required_headcount slots (eager-emit),
--         and reconciliation holds per group.
--   SELECT cg.id, cg.required_headcount, COUNT(cs.id) AS slot_count
--     FROM public.coverage_groups cg
--     LEFT JOIN public.coverage_slots cs ON cs.coverage_group_id = cg.id
--    WHERE cg.archived_at IS NULL
--    GROUP BY cg.id, cg.required_headcount
--   HAVING COUNT(cs.id) <> cg.required_headcount;
--   -- Expected: 0 rows.
--
-- Gate 3: No coverage slot is already 'pipeline' (nothing bound yet pre-R-B).
--   SELECT COUNT(*) FROM public.coverage_slots WHERE slot_status <> 'open';
--   -- Expected: 0 (R-A emits only 'open'; nothing has moved a slot yet).
-- ============================================================


-- ============================================================
-- §RB1 — Partial unique: one active applicant per coverage slot
-- ============================================================
-- Structural guard for "at most one pipeline-active applicant owns a given
-- coverage slot at any moment" — the roving peer of
-- uq_applicants_one_active_per_slot. Terminal applicants RETAIN coverage_slot_id
-- for audit and are excluded by the WHERE clause (an open coverage slot may be
-- re-bound by a later applicant; many historical rows per slot are allowed).
--
-- Validates clean against the all-NULL coverage_slot_id column (RB0 Gate 1).
-- Uses the SAME active-status predicate pattern as stationary Phase B.

CREATE UNIQUE INDEX IF NOT EXISTS uq_applicants_one_active_per_coverage_slot
  ON public.applicants (coverage_slot_id)
  WHERE coverage_slot_id IS NOT NULL
    AND COALESCE(is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(status);

COMMENT ON INDEX public.uq_applicants_one_active_per_coverage_slot IS
  'Phase R-B (OHM2026_0069): enforces one active (pipeline-active) applicant '
  'per coverage_slots row. Terminal applicants retain coverage_slot_id for audit. '
  'Partial: coverage_slot_id IS NOT NULL AND is_archived=false AND active status. '
  'Roving peer of uq_applicants_one_active_per_slot.';


-- ============================================================
-- §RB2 — Mutual-exclusivity CHECK: stationary XOR roving binding
-- ============================================================
-- An applicant is EITHER stationary (slot_id set, coverage_slot_id NULL) OR
-- roving (coverage_slot_id set, slot_id NULL) — never both (plan Q9 / RB9).
-- R-A §2 deferred this to the binding phase; R-B owns it.
--
-- Added NOT VALID (same low-lock pattern as the RA6 FKs): the column is all-NULL
-- today so every existing row already satisfies it, and NOT VALID still enforces
-- the predicate on every INSERT/UPDATE going forward — which is the only place a
-- violation could be introduced. Avoids a full-table validation scan / lock on
-- the large, actively-mutated applicants table.

ALTER TABLE public.applicants
  DROP CONSTRAINT IF EXISTS applicants_slot_coverage_mutex_chk;

ALTER TABLE public.applicants
  ADD CONSTRAINT applicants_slot_coverage_mutex_chk
  CHECK (slot_id IS NULL OR coverage_slot_id IS NULL) NOT VALID;

COMMENT ON CONSTRAINT applicants_slot_coverage_mutex_chk ON public.applicants IS
  'Phase R-B (OHM2026_0069): stationary (slot_id) and roving (coverage_slot_id) '
  'binding lineages are mutually exclusive per applicant. NOT VALID: enforced on '
  'all new writes; existing rows are all-NULL coverage_slot_id so already satisfy it.';


-- ============================================================
-- §RB3 — fn_set_coverage_slot_status (central open↔pipeline helper)
-- ============================================================
-- The roving peer of fn_set_slot_status, scoped to the ONLY edges Phase R-B
-- owns: open → pipeline (claim) and pipeline → open (release). Every other
-- edge (hr_processing / active / closed) is REFUSED here and left to later
-- phases (R-C/R-E/R-F) — R-B must never drive a slot past pipeline.
--
-- Returns JSONB:
--   {status:'ok',      from, to, slot_id, slot_ordinal}        — transition applied
--   {status:'no_op',   reason, ...}                            — null slot / already in status
--   {status:'blocked', blocked_reason, ...}                   — slot missing / edge not owned by R-B
--
-- Does NOT raise on a blocked edge — the caller decides whether to escalate.

CREATE OR REPLACE FUNCTION public.fn_set_coverage_slot_status(
  p_slot_id      uuid,
  p_new_status   text,
  p_performed_by uuid DEFAULT NULL,
  p_remarks      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cur text;
  v_ord integer;
BEGIN
  IF p_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_slot');
  END IF;

  -- Lock the exact slot row for the duration of the transition.
  SELECT slot_status, slot_ordinal
    INTO v_cur, v_ord
    FROM public.coverage_slots
   WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason', 'slot_not_found', 'slot_id', p_slot_id);
  END IF;

  IF v_cur = p_new_status THEN
    RETURN jsonb_build_object('status', 'no_op',
      'reason', 'already_in_status', 'slot_id', p_slot_id, 'slot_status', v_cur);
  END IF;

  -- Phase R-B owns ONLY open↔pipeline. Refuse everything else.
  IF NOT ( (v_cur = 'open'     AND p_new_status = 'pipeline')
        OR (v_cur = 'pipeline' AND p_new_status = 'open') ) THEN
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason',
        format('edge %s -> %s not owned by R-B (open<->pipeline only)', v_cur, p_new_status),
      'slot_id', p_slot_id);
  END IF;

  UPDATE public.coverage_slots
     SET slot_status = p_new_status,
         updated_at  = now()
   WHERE id = p_slot_id;

  RETURN jsonb_build_object('status', 'ok',
    'slot_id', p_slot_id, 'from', v_cur, 'to', p_new_status, 'slot_ordinal', v_ord);
END;
$$;

COMMENT ON FUNCTION public.fn_set_coverage_slot_status(uuid, text, uuid, text) IS
  'Phase R-B (OHM2026_0069) — central coverage-slot transition helper. Owns ONLY '
  'open↔pipeline (claim / release); refuses hr_processing/active/closed (later phases). '
  'Roving peer of fn_set_slot_status. Returns jsonb {status: ok|no_op|blocked}.';


-- ============================================================
-- §RB4 — fn_release_coverage_slot (non-blocking terminal release)
-- ============================================================
-- Called after a bound roving applicant goes terminal. If no other active
-- applicant still holds the EXACT coverage slot, transitions it pipeline → open
-- (slot_ordinal preserved — the locked reopen rule, plan Q7).
--
-- Non-blocking: NEVER RAISES. A slot-release failure must not roll back the host
-- applicant status change. Reads the active count AFTER the host status write,
-- so the departing applicant is already excluded.
--
-- Mirrors stationary fn_release_applicant_slot exactly (coverage_slot_id grain).

CREATE OR REPLACE FUNCTION public.fn_release_coverage_slot(
  p_slot_id      uuid,
  p_performed_by uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active_cnt bigint;
  v_result     jsonb;
BEGIN
  IF p_slot_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COUNT(*) INTO v_active_cnt
  FROM   public.applicants
  WHERE  coverage_slot_id = p_slot_id
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

  -- No remaining active applicant — release the EXACT slot: pipeline → open.
  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => p_slot_id,
    p_new_status   => 'open',
    p_performed_by => p_performed_by,
    p_remarks      => format(
      'Phase R-B release / last active applicant went terminal / coverage_slot=%s',
      p_slot_id
    )
  ) INTO v_result;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_release_coverage_slot: error for slot=% — % (sqlstate=%)',
    p_slot_id, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_release_coverage_slot(uuid, uuid) IS
  'Phase R-B (OHM2026_0069) — non-blocking coverage-slot release on applicant '
  'terminal. If no other active applicant remains bound to p_slot_id, transitions '
  'pipeline → open (ordinal preserved). NEVER RAISES. Roving peer of '
  'fn_release_applicant_slot. Caller: fn_update_applicant_status (terminal path).';


-- ============================================================
-- §RB5 — fn_bind_applicant_to_coverage_group (CGCODE claim/bind RPC)
-- ============================================================
-- The roving claim path (plan Q1–Q4). Binds an EXISTING applicant row to the
-- lowest-ordinal open coverage slot of a CGCODE and moves that slot open→pipeline,
-- all in one transaction. Operates on an already-created applicant so it does not
-- depend on the stationary insert path (create_applicant_and_link_to_vacancy is
-- untouched) and does not require a vacancy_vcode shim — R-B owns the BINDING.
--
-- Steps:
--   1. RBAC (ops) + scope (group's account) — mirrors stationary create.
--   2. Lock applicant; reject if stationary (slot_id set) or already bound (mutex).
--   3. Claim lowest open slot: ORDER BY slot_ordinal, created_at, id
--      LIMIT 1 FOR UPDATE SKIP LOCKED (concurrent adds take distinct slots;
--      uq_applicants_one_active_per_coverage_slot is the backstop).
--   4. No open slot → hard reject (SQLSTATE P0001, plan Q4).
--   5. Set BOTH coverage_slot_id + coverage_group_id; open→pipeline (same txn).
--
-- Returns JSONB describing the bind.

CREATE OR REPLACE FUNCTION public.fn_bind_applicant_to_coverage_group(
  p_applicant_id      uuid,
  p_coverage_group_id uuid,
  p_performed_by      uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_app          public.applicants%ROWTYPE;
  v_grp          public.coverage_groups%ROWTYPE;
  v_claimed_slot uuid;
  v_claimed_ord  integer;
  v_open_cnt     bigint;
  v_actor        uuid := COALESCE(p_performed_by, public.get_my_profile_id());
  v_slot_result  jsonb;
BEGIN
  IF NOT public.i_am_ops() THEN
    RAISE EXCEPTION 'forbidden: ops only' USING ERRCODE = '42501';
  END IF;

  -- ── Resolve + scope the coverage group ────────────────────────────────────
  SELECT * INTO v_grp
    FROM public.coverage_groups
   WHERE id = p_coverage_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_grp.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'coverage group is archived' USING ERRCODE = 'P0001';
  END IF;
  IF NOT public.i_have_full_access()
     AND NOT (v_grp.account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: out of scope' USING ERRCODE = '42501';
  END IF;

  -- ── Lock + validate the applicant ─────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Mutual exclusivity (plan Q9): a stationary applicant cannot take a coverage slot.
  IF v_app.slot_id IS NOT NULL THEN
    RAISE EXCEPTION
      'applicant % is stationary (slot_id set) — cannot bind to a coverage slot',
      p_applicant_id USING ERRCODE = 'P0001';
  END IF;
  IF v_app.coverage_slot_id IS NOT NULL THEN
    RAISE EXCEPTION
      'applicant % is already bound to coverage_slot %',
      p_applicant_id, v_app.coverage_slot_id USING ERRCODE = 'P0001';
  END IF;

  -- ── Claim the lowest-ordinal open coverage slot (Q1/Q2/Q3) ────────────────
  SELECT id, slot_ordinal
    INTO v_claimed_slot, v_claimed_ord
    FROM public.coverage_slots
   WHERE coverage_group_id = v_grp.id
     AND slot_status       = 'open'
   ORDER BY slot_ordinal ASC, created_at ASC, id ASC
   LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_claimed_slot IS NULL THEN
    SELECT COUNT(*) INTO v_open_cnt
      FROM public.coverage_slots
     WHERE coverage_group_id = v_grp.id;
    RAISE EXCEPTION
      'no_open_coverage_slot: CGCODE % has % slot(s) but none are open. '
      'All headcount is in pipeline, processing, filled, or closed. '
      'Increase required headcount before adding another applicant.',
      v_grp.coverage_code, v_open_cnt
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Bind BOTH FK columns in one statement (Q1) ────────────────────────────
  UPDATE public.applicants
     SET coverage_slot_id  = v_claimed_slot,
         coverage_group_id = v_grp.id,
         updated_at        = now(),
         updated_by        = v_actor
   WHERE id = p_applicant_id;

  -- ── Transition the exact claimed slot open → pipeline (blocking) ──────────
  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => v_claimed_slot,
    p_new_status   => 'pipeline',
    p_performed_by => v_actor,
    p_remarks      => format(
      'Phase R-B / fn_bind_applicant_to_coverage_group / CGCODE=%s / '
      'applicant=%s / slot_ordinal=%s',
      v_grp.coverage_code, p_applicant_id, v_claimed_ord
    )
  ) INTO v_slot_result;

  IF (v_slot_result->>'status') = 'blocked' THEN
    RAISE EXCEPTION
      'coverage_slot_transition_blocked: claimed slot % could not transition to '
      'pipeline — %. Resolve coverage slot status before binding.',
      v_claimed_slot, v_slot_result->>'blocked_reason'
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.log_audit_event(
    'vacancy_module', 'UPDATE', p_applicant_id,
    NULL,
    jsonb_build_object(
      'action',            'bind_applicant_to_coverage_group',
      'coverage_group_id', v_grp.id,
      'coverage_code',     v_grp.coverage_code,
      'coverage_slot_id',  v_claimed_slot,
      'slot_ordinal',      v_claimed_ord
    )
  );

  RETURN jsonb_build_object(
    'status',            'ok',
    'applicant_id',      p_applicant_id,
    'coverage_group_id', v_grp.id,
    'coverage_slot_id',  v_claimed_slot,
    'slot_ordinal',      v_claimed_ord
  );
END;
$$;

COMMENT ON FUNCTION public.fn_bind_applicant_to_coverage_group(uuid, uuid, uuid) IS
  'Phase R-B (OHM2026_0069) — CGCODE applicant claim/bind. Binds an existing '
  'applicant to the lowest-ordinal open coverage slot (FOR UPDATE SKIP LOCKED), '
  'sets coverage_slot_id + coverage_group_id, transitions the slot open→pipeline '
  '(one txn). Rejects (P0001) if no open coverage slot exists. Roving peer of the '
  'stationary slot-claim block in create_applicant_and_link_to_vacancy.';


-- ============================================================
-- §RB6 — Patch fn_update_applicant_status (roving terminal-release branch)
-- ============================================================
-- Source body: 20260817000000_vcode_slot_phase_b_applicant_binding.sql §B6.
-- Phase R-B adds ONE additional branch and changes nothing else:
--   • slot_id IS NOT NULL                       → stationary branch (UNCHANGED, verbatim)
--   • slot_id IS NULL, coverage_slot_id NOT NULL → ROVING branch (NEW):
--       terminal status → fn_release_coverage_slot(coverage_slot_id) (exact slot,
--       pipeline→open, non-blocking). Non-terminal roving → no slot change.
--   • both NULL (legacy/unbound)                 → legacy fn_sync (UNCHANGED)
-- Mutual exclusivity (RB2) guarantees slot_id and coverage_slot_id are never both
-- set, so the ELSIF cleanly partitions stationary vs roving. The stationary path
-- is byte-for-byte identical — "preserve stationary path" (requirement 5).

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

  -- ── Slot-aware open↔pipeline sync (stationary + roving + legacy) ──────────
  -- Routed by binding column. Mutual exclusivity (RB2) guarantees at most one
  -- of slot_id / coverage_slot_id is set, so the branches are disjoint.
  IF v_app.slot_id IS NOT NULL THEN
    -- ── STATIONARY (Phase B, UNCHANGED) ──────────────────────────────────
    IF COALESCE(v_to_opt.is_terminal, false) THEN
      -- Terminal transition: release the specific bound stationary slot.
      PERFORM public.fn_release_applicant_slot(
        p_slot_id      => v_app.slot_id,
        p_performed_by => v_profile_id
      );
    END IF;
    -- Non-terminal with bound slot: no slot status change (Phase 6.2 owns
    -- pipeline→hr_processing via confirm_applicant_onboard).
  ELSIF v_app.coverage_slot_id IS NOT NULL THEN
    -- ── ROVING (Phase R-B, NEW) ──────────────────────────────────────────
    -- Direct FK dereference — act on THAT specific coverage slot, never a
    -- group-only LIMIT 1 lookup (plan Q7).
    IF COALESCE(v_to_opt.is_terminal, false) THEN
      -- Terminal transition: release the exact coverage slot (pipeline→open
      -- if no other active applicant remains). NEVER RAISES.
      PERFORM public.fn_release_coverage_slot(
        p_slot_id      => v_app.coverage_slot_id,
        p_performed_by => v_profile_id
      );
    END IF;
    -- Non-terminal with bound coverage slot: no slot status change. Confirmed
    -- Onboard (pipeline→hr_processing) is R-C, not wired here.
  ELSE
    -- ── LEGACY / UNBOUND (Phase 6.1, UNCHANGED) ──────────────────────────
    -- No-slot VCODE, legacy roving (roving_assignment_id), or pre-backfill row.
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
  'Phase B: stationary terminal release by applicants.slot_id (UNCHANGED). '
  'Phase R-B (OHM2026_0069): roving terminal release by applicants.coverage_slot_id '
  'via fn_release_coverage_slot (exact slot, pipeline→open, non-blocking). '
  'Unbound applicants fall back to the Phase 6.1 fn_sync_vacancy_slot_open_pipeline '
  'legacy path. Binding columns are mutually exclusive (applicants_slot_coverage_mutex_chk).';


-- ============================================================
-- §RB7 — GRANTs
-- ============================================================

-- fn_set_coverage_slot_status: internal transition helper, authenticated only.
REVOKE ALL ON FUNCTION public.fn_set_coverage_slot_status(uuid, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_set_coverage_slot_status(uuid, text, uuid, text) TO authenticated;

-- fn_release_coverage_slot: internal helper, authenticated only.
REVOKE ALL ON FUNCTION public.fn_release_coverage_slot(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_release_coverage_slot(uuid, uuid) TO authenticated;

-- fn_bind_applicant_to_coverage_group: roving claim RPC, authenticated (ops-gated inside).
REVOKE ALL ON FUNCTION public.fn_bind_applicant_to_coverage_group(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_bind_applicant_to_coverage_group(uuid, uuid, uuid) TO authenticated;

-- fn_update_applicant_status: unchanged grant.
GRANT EXECUTE ON FUNCTION public.fn_update_applicant_status(uuid, text, text, uuid, text) TO authenticated;


-- ============================================================
-- §RB8 — Post-migration validation queries (run manually)
-- ============================================================
--
-- ── Structural checks ────────────────────────────────────────────────────
--
-- V1 — uq_applicants_one_active_per_coverage_slot exists and is partial.
--   SELECT indexname, indexdef FROM pg_indexes
--    WHERE schemaname='public' AND tablename='applicants'
--      AND indexname='uq_applicants_one_active_per_coverage_slot';
--   -- Expected: 1 row; WHERE clause references coverage_slot_id IS NOT NULL,
--   --           is_archived, fn_is_active_vacancy_applicant_status.
--
-- V2 — Mutual-exclusivity CHECK present.
--   SELECT conname FROM pg_constraint
--    WHERE conname='applicants_slot_coverage_mutex_chk';
--   -- Expected: 1 row.
--
-- V3 — The three R-B functions exist with correct security.
--   SELECT routine_name, security_type FROM information_schema.routines
--    WHERE routine_schema='public'
--      AND routine_name IN ('fn_set_coverage_slot_status','fn_release_coverage_slot',
--                           'fn_bind_applicant_to_coverage_group');
--   -- Expected: 3 rows, all DEFINER.
--
-- ── Data invariant checks (RB1–RB10 parity) ─────────────────────────────
--
-- RB1 — No coverage slot has >1 active applicant.
--   SELECT coverage_slot_id, COUNT(*) AS cnt
--     FROM public.applicants
--    WHERE coverage_slot_id IS NOT NULL
--      AND COALESCE(is_archived,false)=false
--      AND public.fn_is_active_vacancy_applicant_status(status)
--    GROUP BY coverage_slot_id HAVING COUNT(*)>1;
--   -- Expected: 0 rows.
--
-- RB2 — Multiple active applicants under one CGCODE via DIFFERENT slots is allowed
--       (positive smoke): for an N>1 group, bind two applicants; both succeed and
--       land on distinct slot_ordinals.
--   SELECT coverage_group_id, COUNT(*) AS active, COUNT(DISTINCT coverage_slot_id) AS slots
--     FROM public.applicants
--    WHERE coverage_group_id IS NOT NULL
--      AND COALESCE(is_archived,false)=false
--      AND public.fn_is_active_vacancy_applicant_status(status)
--    GROUP BY coverage_group_id;
--   -- Expected: for every group, active == slots (no two actives share a slot).
--
-- RB3 — No active applicant has BOTH slot_id and coverage_slot_id.
--   SELECT COUNT(*) AS both_bound FROM public.applicants
--    WHERE slot_id IS NOT NULL AND coverage_slot_id IS NOT NULL;
--   -- Expected: 0.
--
-- RB4 — Every active roving applicant has non-NULL coverage_slot_id AND coverage_group_id.
--   SELECT COUNT(*) AS bad FROM public.applicants
--    WHERE coverage_group_id IS NOT NULL
--      AND COALESCE(is_archived,false)=false
--      AND public.fn_is_active_vacancy_applicant_status(status)
--      AND (coverage_slot_id IS NULL);
--   -- Expected: 0.
--   -- Binding matches CGCODE (slot's group == applicant's group):
--   SELECT COUNT(*) AS mismatched FROM public.applicants a
--     JOIN public.coverage_slots cs ON cs.id = a.coverage_slot_id
--    WHERE cs.coverage_group_id <> a.coverage_group_id;
--   -- Expected: 0.
--
-- RB5 — Lowest open ordinal claimed first (smoke):
--   (For a group with open ordinals 1,2,3, call fn_bind_applicant_to_coverage_group.)
--   -- Expected: returned slot_ordinal = 1; that slot is now 'pipeline'; 2,3 stay 'open'.
--
-- RB6 — No-open-slot rejects clearly (smoke):
--   (Bind until every slot of a group is non-open, then bind once more.)
--   -- Expected: RAISE EXCEPTION, SQLSTATE P0001, message contains 'no_open_coverage_slot'.
--
-- RB7 — Terminal applicant reopens the EXACT same coverage slot (smoke):
--   (Set the RB5 applicant to backout/failed via fn_update_applicant_status.)
--   SELECT slot_status, slot_ordinal FROM public.coverage_slots WHERE id='<slot>';
--   -- Expected: slot_status='open', slot_ordinal unchanged (same ordinal preserved).
--
-- RB8 — CGCODE pipeline count == count of coverage_slots in 'pipeline'.
--   SELECT s.coverage_group_id, s.pipeline_slots, a.active_applicants
--     FROM (
--       SELECT coverage_group_id, COUNT(*) AS pipeline_slots
--         FROM public.coverage_slots WHERE slot_status='pipeline'
--        GROUP BY coverage_group_id
--     ) s
--     FULL OUTER JOIN (
--       SELECT coverage_group_id, COUNT(DISTINCT coverage_slot_id) AS active_applicants
--         FROM public.applicants
--        WHERE coverage_slot_id IS NOT NULL
--          AND COALESCE(is_archived,false)=false
--          AND public.fn_is_active_vacancy_applicant_status(status)
--        GROUP BY coverage_group_id
--     ) a ON a.coverage_group_id = s.coverage_group_id
--    WHERE COALESCE(s.pipeline_slots,0) <> COALESCE(a.active_applicants,0);
--   -- Expected: 0 rows.
--
-- RB9 — Stationary VCODE applicant flow still works (smoke):
--   (Run a stationary create_applicant_and_link_to_vacancy + a terminal release.)
--   -- Expected: plantilla_slots open↔pipeline behave exactly as Phase B; no coverage
--   --           function touched; slot_id path unchanged.
--
-- RB10 — Coverage tables stay isolated from vw_slot_derived_vacancy_shadow.
--   SELECT COUNT(*) AS leaked FROM public.vw_slot_derived_vacancy_shadow v
--    WHERE v.legacy_vcode LIKE 'CG-%'
--       OR EXISTS (SELECT 1 FROM public.coverage_groups cg
--                   WHERE cg.coverage_code = v.legacy_vcode);
--   -- Expected: 0 (the stationary shadow is keyed on legacy_vcode and never sees a CGCODE).
-- ============================================================
