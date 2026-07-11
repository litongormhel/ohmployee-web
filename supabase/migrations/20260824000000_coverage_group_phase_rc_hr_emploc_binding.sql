-- ============================================================
-- OHM2026_0075 — Coverage Group Phase R-C: HR Emploc-to-Coverage-Slot Binding
-- Migration:  20260824000000_coverage_group_phase_rc_hr_emploc_binding.sql
-- Plan:       docs/architecture/coverage_group_phase_rc_hr_emploc_binding_plan.md (OHM2026_0074)
-- Mirrors:    20260819000000_vcode_slot_phase_c_hr_emploc_binding.sql (stationary Phase C, OHM2026_0045)
-- Depends on:
--   20260822000006_coverage_group_ra6_binding_columns.sql
--     (hr_emploc.coverage_slot_id / coverage_group_id nullable FK, empty)
--   20260823000000_coverage_group_phase_rb_applicant_binding.sql
--     (applicants.coverage_slot_id source of truth; fn_set_coverage_slot_status
--      owns open↔pipeline ONLY; fn_release_coverage_slot)
--   20260819000000_vcode_slot_phase_c_hr_emploc_binding.sql
--     (confirm_applicant_onboard / fn_approve_emploc_deletion_request — the live
--      bodies patched here; stationary slot_id path preserved verbatim)
--   20260616000000_restore_fn_is_active_vacancy_applicant_status.sql
-- ============================================================
-- Scope: Phase R-C — make hr_emploc.coverage_slot_id the HR-side source of truth
--   for HR-processing coverage-slot ownership. The roving peer of stationary
--   Phase C, substituting coverage_slot_id for slot_id, coverage_group_id for
--   legacy_vcode/vacancy_vcode, and fn_set_coverage_slot_status for fn_set_slot_status.
--   Confirmed Onboard copies applicants.coverage_slot_id (+ coverage_group_id) onto
--   the HR Emploc row and drives pipeline→hr_processing by the EXACT slot; HR Emploc
--   backout reopens the EXACT slot hr_processing→open. (Plan OHM2026_0074 Q1–Q9.)
--
-- What this migration does:
--   RC1  Extend fn_set_coverage_slot_status — accept pipeline→hr_processing and
--        hr_processing→open; STILL refuse hr_processing→active and every closed edge
--   RC2  Structural guards: uq_hr_emploc_one_active_per_coverage_slot (partial unique)
--        + hr_emploc_slot_coverage_mutex_chk (slot_id XOR coverage_slot_id, NOT VALID)
--   RC3  fn_sync_coverage_slot_to_hr_processing — non-blocking exact-slot wrapper
--        (roving peer of fn_sync_slot_to_hr_processing)
--   RC4  fn_sync_coverage_slot_hr_processing_to_open — non-blocking exact-slot reopen
--        (roving peer of fn_sync_slot_hr_processing_to_open)
--   RC5  Replace confirm_applicant_onboard — coverage_slot_id + coverage_group_id copy
--        at HR Emploc INSERT + exact coverage slot pipeline→hr_processing
--   RC6  Replace fn_approve_emploc_deletion_request — exact coverage slot
--        hr_processing→open via v_emp.coverage_slot_id (captured pre-archive)
--   RC7  GRANTs
--   RC8  Post-migration validation queries RC1–RC12 (manual, in comments)
--
-- What this migration deliberately does NOT do (out of scope per task / plan):
--   • Modify Flutter / any client-side code or UI
--   • Modify stationary VCODE slot behavior or the stationary HR Emploc slot_id path
--     (both preserved byte-for-byte; only additive coverage branches are introduced)
--   • Implement hr_processing → active (move-to-Plantilla / plantilla.coverage_slot_id)
--     — fn_set_coverage_slot_status continues to REFUSE that edge (next seam)
--   • Implement store-link materialization (hr_emploc_store_links re-point)
--   • Migrate legacy roving_assignments rows (R-F) — legacy roving stays NULL
--     coverage_slot_id and is skipped by every coverage branch below
--   • Modify the roving shadow/card (R-D), closure fan-out (R-E), or reporting
--
-- Non-blocking discipline (load-bearing — plan Q4/Q6):
--   Coverage-slot writes inside confirm_applicant_onboard and
--   fn_approve_emploc_deletion_request are SIDE EFFECTS. A slot-write failure must
--   NEVER roll back the host workflow. The RC3/RC4 wrapper helpers NEVER RAISE into
--   their callers — blocked/no_op transitions are logged via RAISE NOTICE and the
--   helper returns the result as-is.
--
-- Lineage partition (load-bearing — plan Q3/Q7):
--   Confirmed Onboard / backout branch on the applicant's / HR Emploc row's binding
--   lineage. coverage_slot_id IS NOT NULL → coverage branch. slot_id IS NOT NULL →
--   stationary branch (UNCHANGED). Both NULL → legacy/no-slot path (UNCHANGED). The
--   mutex CHECK (RC2) keeps slot_id and coverage_slot_id mutually exclusive per row,
--   so the branches are disjoint by construction. No coverage_group_id LIMIT 1 routing.
-- ============================================================


-- ============================================================
-- §RC0 — Pre-migration gate (run MANUALLY before applying)
-- ============================================================
--
-- Gate 1: hr_emploc.coverage_slot_id all NULL (R-A shipped the column empty).
--   SELECT COUNT(*) FROM public.hr_emploc WHERE coverage_slot_id IS NOT NULL;
--   -- Expected: 0. Any non-zero = prior partial run; reconcile before re-applying.
--
-- Gate 2: R-B GREEN — applicants.coverage_slot_id is the source of truth for
--         open↔pipeline; one active applicant per coverage slot; mutex holds.
--   -- Re-run RB1–RB10 + live smoke G1–G12 (OHM2026_0072/0073).
--
-- Gate 3: fn_set_coverage_slot_status currently owns open↔pipeline ONLY.
--   SELECT routine_name FROM information_schema.routines
--    WHERE routine_schema='public' AND routine_name='fn_set_coverage_slot_status';
--   -- Expected: 1 row (the R-B 4-param version).
--
-- Gate 4: stationary Phase C baseline GREEN (C1–C12, OHM2026_0045).
-- ============================================================


-- ============================================================
-- §RC1 — Extend fn_set_coverage_slot_status (add the two HR-side edges)
-- ============================================================
-- R-B shipped this owning ONLY open↔pipeline; every other edge returned
-- 'blocked'. R-C adds EXACTLY the two HR-side edges to the allowed set:
--   • pipeline → hr_processing  (Confirmed Onboard, RC5)
--   • hr_processing → open      (HR Emploc backout reopen, RC6)
-- It must STILL refuse hr_processing → active (forward occupy = next seam) and
-- any 'closed' edge (R-E). The helper stays the SINGLE coverage-slot transition
-- authority — no second mutator. (Plan Q5.)
--
-- Returns JSONB:
--   {status:'ok',      from, to, slot_id, slot_ordinal}  — transition applied
--   {status:'no_op',   reason, ...}                      — null slot / already in status
--   {status:'blocked', blocked_reason, ...}              — slot missing / edge not owned
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

  -- Phase R-B owned open↔pipeline; Phase R-C adds the two HR-side edges.
  -- hr_processing→active (forward occupy = next seam) and every 'closed' edge
  -- remain REFUSED here (later phases). Any other jump is invalid.
  IF NOT ( (v_cur = 'open'          AND p_new_status = 'pipeline')        -- R-B claim
        OR (v_cur = 'pipeline'      AND p_new_status = 'open')            -- R-B release
        OR (v_cur = 'pipeline'      AND p_new_status = 'hr_processing')   -- R-C onboard
        OR (v_cur = 'hr_processing' AND p_new_status = 'open') ) THEN     -- R-C backout reopen
    RETURN jsonb_build_object('status', 'blocked',
      'blocked_reason',
        format('edge %s -> %s not owned by R-C (open<->pipeline, '
               'pipeline->hr_processing, hr_processing->open only)', v_cur, p_new_status),
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
  'Phase R-C (OHM2026_0075) — central coverage-slot transition helper. Owns '
  'open<->pipeline (R-B claim/release) PLUS pipeline->hr_processing (onboard) and '
  'hr_processing->open (backout reopen). STILL refuses hr_processing->active '
  '(move-to-Plantilla = next seam) and every closed edge (R-E). Roving peer of '
  'fn_set_slot_status. Returns jsonb {status: ok|no_op|blocked}; never raises on a '
  'blocked edge.';


-- ============================================================
-- §RC2 — Structural guards (partial unique + mutex CHECK)
-- ============================================================
-- One active (non-archived) HR Emploc row per coverage slot in hr_processing —
-- the roving peer of uq_hr_emploc_one_active_per_slot. This is the "one owner"
-- guarantee that closes the R-B §Q5 Confirmed-Onboard-vs-partial-unique seam:
-- at hr_processing the slot is owned by exactly this HR Emploc row, not by the
-- pipeline-active applicant partial unique.
--
-- Validates clean against the all-NULL coverage_slot_id column (RC0 Gate 1).
-- Archived rows (deleted_at IS NOT NULL) retain coverage_slot_id for audit and
-- are excluded by the WHERE clause.

CREATE UNIQUE INDEX IF NOT EXISTS uq_hr_emploc_one_active_per_coverage_slot
  ON public.hr_emploc (coverage_slot_id)
  WHERE coverage_slot_id IS NOT NULL
    AND deleted_at IS NULL;

COMMENT ON INDEX public.uq_hr_emploc_one_active_per_coverage_slot IS
  'Phase R-C (OHM2026_0075): enforces one active (non-archived) HR Emploc row per '
  'coverage_slots row (the hr_processing owner). Archived rows retain coverage_slot_id '
  'for audit. Partial: coverage_slot_id IS NOT NULL AND deleted_at IS NULL. Roving peer '
  'of uq_hr_emploc_one_active_per_slot.';

-- Mutual exclusivity: an HR Emploc row is EITHER stationary (slot_id set,
-- coverage_slot_id NULL) OR roving (coverage_slot_id set, slot_id NULL) — never
-- both (plan Q7, RC3 check). Structural peer of applicants_slot_coverage_mutex_chk.
-- NOT VALID: coverage_slot_id is all-NULL today so every existing row already
-- satisfies it; NOT VALID still enforces the predicate on every new write, which is
-- the only place a violation could be introduced. Avoids a full-table validation
-- scan / lock on the large, actively-mutated hr_emploc table.

ALTER TABLE public.hr_emploc
  DROP CONSTRAINT IF EXISTS hr_emploc_slot_coverage_mutex_chk;

ALTER TABLE public.hr_emploc
  ADD CONSTRAINT hr_emploc_slot_coverage_mutex_chk
  CHECK (slot_id IS NULL OR coverage_slot_id IS NULL) NOT VALID;

COMMENT ON CONSTRAINT hr_emploc_slot_coverage_mutex_chk ON public.hr_emploc IS
  'Phase R-C (OHM2026_0075): stationary (slot_id) and roving (coverage_slot_id) HR '
  'Emploc binding lineages are mutually exclusive per row. NOT VALID: enforced on all '
  'new writes; existing rows are all-NULL coverage_slot_id so already satisfy it.';


-- ============================================================
-- §RC3 — fn_sync_coverage_slot_to_hr_processing (non-blocking onboard wrapper)
-- ============================================================
-- Roving peer of fn_sync_slot_to_hr_processing. Drives the EXACT coverage slot
-- pipeline → hr_processing at Confirmed Onboard. Unlike the stationary helper
-- there is NO legacy VCODE LIMIT 1 fallback — the coverage slot is always exact
-- (applicant.coverage_slot_id). A NULL slot is a no-op (legacy / stationary row).
--
-- NEVER RAISES: a blocked/no_op transition or an unexpected error is logged via
-- RAISE NOTICE and returned/swallowed. The onboard RPC must not roll back on a
-- coverage-slot side effect (plan Q4).

CREATE OR REPLACE FUNCTION public.fn_sync_coverage_slot_to_hr_processing(
  p_coverage_slot_id uuid,
  p_applicant_id     uuid    DEFAULT NULL,
  p_performed_by     uuid    DEFAULT NULL,
  p_source_fn        text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_coverage_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_coverage_slot');
  END IF;

  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => p_coverage_slot_id,
    p_new_status   => 'hr_processing',
    p_performed_by => p_performed_by,
    p_remarks      => format(
      'Phase R-C / %s / pipeline->hr_processing / coverage_slot=%s / applicant=%s',
      COALESCE(p_source_fn, 'fn_sync_coverage_slot_to_hr_processing'),
      p_coverage_slot_id, p_applicant_id
    )
  ) INTO v_result;

  IF (v_result->>'status') = 'blocked' THEN
    RAISE NOTICE
      'fn_sync_coverage_slot_to_hr_processing: blocked for coverage_slot=% applicant=% source=% — %',
      p_coverage_slot_id, p_applicant_id, p_source_fn, v_result->>'blocked_reason';
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_coverage_slot_to_hr_processing: error for coverage_slot=% applicant=% source=% — % (sqlstate=%)',
    p_coverage_slot_id, p_applicant_id, p_source_fn, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_coverage_slot_to_hr_processing(uuid, uuid, uuid, text) IS
  'Phase R-C (OHM2026_0075) — non-blocking exact coverage-slot pipeline->hr_processing '
  'sync at Confirmed Onboard. Roving peer of fn_sync_slot_to_hr_processing (no legacy '
  'VCODE LIMIT 1 fallback — coverage_slot_id is always exact). NEVER RAISES. '
  'Caller: confirm_applicant_onboard (roving coverage path only).';


-- ============================================================
-- §RC4 — fn_sync_coverage_slot_hr_processing_to_open (non-blocking backout reopen)
-- ============================================================
-- Roving peer of fn_sync_slot_hr_processing_to_open. Reopens the EXACT coverage
-- slot hr_processing → open on HR Emploc backout (slot_ordinal preserved by the
-- transition helper; aging restarts). The "no other active applicant remains"
-- guard from fn_release_coverage_slot is NOT needed here — at hr_processing the
-- slot is owned by exactly one HR Emploc row (RC2), so the reopen is unconditional
-- once that row backs out (plan Q6). NULL slot = no-op (legacy / stationary row).
--
-- NEVER RAISES: the reopen is a side effect; a failure must not roll back the
-- emploc backout (plan Q6).

CREATE OR REPLACE FUNCTION public.fn_sync_coverage_slot_hr_processing_to_open(
  p_coverage_slot_id uuid,
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
DECLARE
  v_result jsonb;
BEGIN
  IF p_coverage_slot_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_op', 'reason', 'null_coverage_slot');
  END IF;

  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => p_coverage_slot_id,
    p_new_status   => 'open',
    p_performed_by => p_performed_by,
    p_remarks      => format(
      'Phase R-C / %s / hr_processing->open (backout) / coverage_slot=%s / '
      'hr_emploc=%s / reason=%s',
      COALESCE(p_source_fn, 'fn_sync_coverage_slot_hr_processing_to_open'),
      p_coverage_slot_id, p_hr_emploc_id, p_deletion_reason
    )
  ) INTO v_result;

  IF (v_result->>'status') = 'blocked' THEN
    RAISE NOTICE
      'fn_sync_coverage_slot_hr_processing_to_open: blocked for coverage_slot=% hr_emploc=% source=% — %',
      p_coverage_slot_id, p_hr_emploc_id, p_source_fn, v_result->>'blocked_reason';
  END IF;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_coverage_slot_hr_processing_to_open: error for coverage_slot=% hr_emploc=% source=% — % (sqlstate=%)',
    p_coverage_slot_id, p_hr_emploc_id, p_source_fn, SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_coverage_slot_hr_processing_to_open(uuid, uuid, text, uuid, text) IS
  'Phase R-C (OHM2026_0075) — non-blocking exact coverage-slot hr_processing->open '
  'reopen on HR Emploc backout. Roving peer of fn_sync_slot_hr_processing_to_open. '
  'Unconditional (one HR Emploc owner per hr_processing slot — RC2); ordinal preserved; '
  'aging restarts. NEVER RAISES. Caller: fn_approve_emploc_deletion_request (Backout only).';


-- ============================================================
-- §RC5 — Replace confirm_applicant_onboard
--         (R-C: copy coverage_slot_id + coverage_group_id at INSERT + exact-slot
--          pipeline->hr_processing)
-- ============================================================
-- Source: 20260819000000_vcode_slot_phase_c_hr_emploc_binding.sql §C4b (the live body).
--
-- R-C changes (all other behavior IDENTICAL to Phase C — stationary slot_id path
-- preserved byte-for-byte):
--   1. Stationary HR Emploc INSERT (the ELSE / IF NOT FOUND branch): add
--      coverage_slot_id + coverage_group_id to the column list, set from the locked
--      applicant row (v_app.coverage_slot_id / v_app.coverage_group_id). For a genuine
--      stationary applicant both are NULL (mutex); for a coverage applicant slot_id is
--      NULL and these are set. The mutex CHECK (RC2) is satisfied either way.
--   2. Slot sync block: route by binding lineage. coverage_slot_id set → exact coverage
--      slot pipeline->hr_processing via the RC3 helper (NO coverage_group_id LIMIT 1, NO
--      stationary VCODE LIMIT 1 on the carrier VCODE). slot_id set / no slot → the
--      stationary fn_sync_slot_to_hr_processing path is UNCHANGED.
--
-- Non-blocking contract preserved: the RC3 helper NEVER raises.
-- Roving carve-out (legacy roving_assignment_id) is unchanged — those rows have NULL
-- coverage_slot_id and skip the coverage branch.

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
  -- RETURNING * captures slot_id / coverage_slot_id / coverage_group_id for the
  -- Phase C (stationary) + Phase R-C (coverage) propagation below.
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
  -- v_app.slot_id (Phase B), v_app.coverage_slot_id / coverage_group_id (Phase R-B)
  -- now reflect the bound values (or NULL). Used in propagation below.

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
    -- ── STATIONARY / COVERAGE: find or create HR Emploc ──────────────────────
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
      -- Phase R-C (OHM2026_0075): ALSO propagate applicants.coverage_slot_id +
      -- coverage_group_id (NULL for genuine stationary; set for coverage applicants,
      -- whose slot_id is NULL — the mutex CHECK keeps the two lineages disjoint).
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores,
        slot_id,            -- Phase C (OHM2026_0045): exact stationary slot; NULL for no-slot VCODEs
        coverage_slot_id,   -- Phase R-C (OHM2026_0075): exact coverage slot; NULL for stationary
        coverage_group_id   -- Phase R-C (OHM2026_0075): coverage group (query convenience); NULL for stationary
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
        v_app.slot_id,            -- Phase C: NULL when applicant has no bound stationary slot
        v_app.coverage_slot_id,   -- Phase R-C: NULL when applicant has no bound coverage slot
        v_app.coverage_group_id   -- Phase R-C: NULL when applicant has no coverage group
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

  -- ── Slot pipeline→hr_processing sync (routed by binding lineage) ──────────
  -- Phase R-C (OHM2026_0075) routes by the applicant's binding column. The mutex
  -- CHECK (RC2 / applicants_slot_coverage_mutex_chk) guarantees at most one of
  -- coverage_slot_id / slot_id is set, so the branches are disjoint.
  --
  --   coverage_slot_id IS NOT NULL → ROVING (Phase R-C): exact coverage slot
  --     pipeline→hr_processing via fn_sync_coverage_slot_to_hr_processing. NO
  --     coverage_group_id LIMIT 1, NO stationary VCODE LIMIT 1 on the carrier VCODE.
  --     Non-blocking — the helper NEVER raises (plan Q4).
  --   slot_id set / no slot (NOT v_is_roving) → STATIONARY (Phase C, UNCHANGED):
  --     fn_sync_slot_to_hr_processing with the exact slot (or legacy VCODE fallback).
  --   legacy roving (roving_assignment_id, NULL coverage_slot_id) → no slot sync
  --     (roving carve-out, unchanged).
  IF v_app.coverage_slot_id IS NOT NULL THEN
    PERFORM public.fn_sync_coverage_slot_to_hr_processing(
      p_coverage_slot_id => v_app.coverage_slot_id,
      p_applicant_id     => v_app.id,
      p_performed_by     => v_profile_id,
      p_source_fn        => 'confirm_applicant_onboard'
    );
  ELSIF NOT v_is_roving THEN
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
  'Phase R-C (OHM2026_0075): copies applicants.coverage_slot_id + coverage_group_id '
  '→ hr_emploc at INSERT and drives the exact coverage slot pipeline→hr_processing via '
  'fn_sync_coverage_slot_to_hr_processing (no coverage_group_id LIMIT 1). '
  'Phase C (OHM2026_0045): copies applicants.slot_id → hr_emploc.slot_id and syncs the '
  'exact stationary slot pipeline→hr_processing (UNCHANGED). NULL on both lineages → '
  'legacy VCODE / roving path; onboard never blocked. Slot writes are non-blocking side '
  'effects (helpers never raise).';


-- ============================================================
-- §RC6 — Replace fn_approve_emploc_deletion_request
--         (R-C: reopen exact coverage slot hr_processing→open on Backout)
-- ============================================================
-- Source: 20260819000000_vcode_slot_phase_c_hr_emploc_binding.sql §C5b (the live body).
--
-- R-C change (the ONLY change; all other behavior IDENTICAL to Phase C):
--   In the Backout hook block (IF v_req.deletion_type = 'Backout'), route by the HR
--   Emploc row's binding lineage:
--     • v_emp.coverage_slot_id IS NOT NULL → ROVING: reopen the exact coverage slot
--       hr_processing→open via fn_sync_coverage_slot_hr_processing_to_open (ordinal
--       preserved; non-blocking). NO coverage_group_id LIMIT 1.
--     • else → STATIONARY (Phase C, UNCHANGED): fn_sync_slot_hr_processing_to_open
--       with p_slot_id => v_emp.slot_id.
--   v_emp is populated by SELECT * FOR UPDATE BEFORE the archive UPDATE, so
--   v_emp.coverage_slot_id is the pre-archive value (capture-before-archive, plan Q6).
--   Duplicate Record path is untouched (not Backout) — it never touches a coverage slot.

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
  -- Phase C / Phase R-C: v_emp is populated here (before the archive UPDATE below) so
  -- that v_emp.slot_id AND v_emp.coverage_slot_id are available for the exact-slot
  -- reopen in the hook. The archive UPDATE sets deleted_at on the DB row but does NOT
  -- change the local v_emp variable — its binding columns remain the pre-archive values.
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
    -- v_emp.slot_id / v_emp.coverage_slot_id are still the pre-archive values
    -- after this UPDATE.
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

  -- ── Slot hr_processing→open reopen (Backout only, routed by lineage) ──────
  -- Phase R-C (OHM2026_0075) routes by the HR Emploc row's binding column. Only
  -- fires for Backout — Duplicate Record is data-cleanup and does not represent an
  -- HR processing abandonment, so it NEVER touches a coverage slot (plan RC9).
  --
  --   v_emp.coverage_slot_id IS NOT NULL → ROVING: reopen the exact coverage slot
  --     hr_processing→open via fn_sync_coverage_slot_hr_processing_to_open (ordinal
  --     preserved; aging restarts). NO coverage_group_id LIMIT 1. Non-blocking.
  --   else → STATIONARY (Phase C, UNCHANGED): fn_sync_slot_hr_processing_to_open
  --     with the exact slot (or legacy VCODE fallback).
  --
  -- Capture-before-archive is guaranteed: v_emp was populated by FOR UPDATE SELECT
  -- before the archive UPDATE; its binding columns are the pre-archive values and
  -- remain accessible here (plan Q6 — archive-first capture rule). Both helpers
  -- NEVER raise; a slot error will not roll back the emploc/applicant archive,
  -- vacancy reopen, request update, or activity log writes.
  IF v_req.deletion_type = 'Backout' THEN
    IF v_emp.coverage_slot_id IS NOT NULL THEN
      PERFORM public.fn_sync_coverage_slot_hr_processing_to_open(
        p_coverage_slot_id => v_emp.coverage_slot_id,
        p_hr_emploc_id     => v_req.hr_emploc_id,
        p_deletion_reason  => v_req.reason,
        p_performed_by     => public.get_my_profile_id(),
        p_source_fn        => 'fn_approve_emploc_deletion_request'
      );
    ELSE
      PERFORM public.fn_sync_slot_hr_processing_to_open(
        p_vcode           => v_req.vcode,
        p_hr_emploc_id    => v_req.hr_emploc_id,
        p_deletion_reason => v_req.reason,
        p_performed_by    => public.get_my_profile_id(),
        p_source_fn       => 'fn_approve_emploc_deletion_request',
        p_slot_id         => v_emp.slot_id   -- Phase C: exact slot; NULL → legacy path
      );
    END IF;
  END IF;

END;
$$;

COMMENT ON FUNCTION public.fn_approve_emploc_deletion_request(uuid, text) IS
  'Approves a Pending HR Emploc deletion request. Encoder (scoped) or Super Admin. '
  'Backout: archives emploc + applicant, reopens vacancy via vacancy_id FK, auto-cancels '
  'correction. Duplicate Record: archives emploc + applicant only (no vacancy reopen, no '
  'slot touch). Phase R-C (OHM2026_0075): on Backout, routes by lineage — coverage rows '
  'reopen the exact coverage slot hr_processing→open via '
  'fn_sync_coverage_slot_hr_processing_to_open (no coverage_group_id LIMIT 1); stationary '
  'rows use fn_sync_slot_hr_processing_to_open (Phase C, UNCHANGED). v_emp captured '
  'pre-archive; both helpers never raise.';


-- ============================================================
-- §RC7 — GRANTs
-- ============================================================

-- fn_set_coverage_slot_status: internal transition helper, authenticated only.
REVOKE ALL ON FUNCTION public.fn_set_coverage_slot_status(uuid, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_set_coverage_slot_status(uuid, text, uuid, text) TO authenticated;

-- fn_sync_coverage_slot_to_hr_processing: internal non-blocking wrapper.
REVOKE ALL ON FUNCTION public.fn_sync_coverage_slot_to_hr_processing(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sync_coverage_slot_to_hr_processing(uuid, uuid, uuid, text) TO authenticated;

-- fn_sync_coverage_slot_hr_processing_to_open: internal non-blocking wrapper.
REVOKE ALL ON FUNCTION public.fn_sync_coverage_slot_hr_processing_to_open(uuid, uuid, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_sync_coverage_slot_hr_processing_to_open(uuid, uuid, text, uuid, text) TO authenticated;

-- confirm_applicant_onboard / fn_approve_emploc_deletion_request: unchanged grants.
GRANT EXECUTE ON FUNCTION public.confirm_applicant_onboard(
  uuid, text, text, text, text, text, text, uuid, uuid, uuid, text, date
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_approve_emploc_deletion_request(uuid, text)
  TO authenticated;


-- ============================================================
-- §RC8 — Post-migration validation queries (run manually)
-- ============================================================
--
-- ── Structural checks ────────────────────────────────────────────────────
--
-- V1 — uq_hr_emploc_one_active_per_coverage_slot exists and is partial.
--   SELECT indexname, indexdef FROM pg_indexes
--    WHERE schemaname='public' AND tablename='hr_emploc'
--      AND indexname='uq_hr_emploc_one_active_per_coverage_slot';
--   -- Expected: 1 row; WHERE references coverage_slot_id IS NOT NULL AND deleted_at IS NULL.
--
-- V2 — hr_emploc mutex CHECK present.
--   SELECT conname FROM pg_constraint WHERE conname='hr_emploc_slot_coverage_mutex_chk';
--   -- Expected: 1 row.
--
-- V3 — The three coverage transition functions exist, all DEFINER.
--   SELECT routine_name, security_type FROM information_schema.routines
--    WHERE routine_schema='public'
--      AND routine_name IN ('fn_set_coverage_slot_status',
--                           'fn_sync_coverage_slot_to_hr_processing',
--                           'fn_sync_coverage_slot_hr_processing_to_open');
--   -- Expected: 3 rows, all DEFINER.
--
-- V4 — fn_set_coverage_slot_status accepts the two new edges and refuses active/closed.
--   -- pipeline→hr_processing and hr_processing→open return {status:ok};
--   -- hr_processing→active and any →closed return {status:blocked}.
--
-- ── Data invariant checks (RC1–RC12) ─────────────────────────────────────
--
-- RC1 — Every hr_processing coverage slot has exactly one active HR Emploc row.
--   SELECT cs.id
--     FROM public.coverage_slots cs
--    WHERE cs.slot_status = 'hr_processing'
--      AND (SELECT COUNT(*) FROM public.hr_emploc he
--            WHERE he.coverage_slot_id = cs.id AND he.deleted_at IS NULL) <> 1;
--   -- Expected: 0 rows.
--
-- RC2 — No two active HR Emploc rows share a coverage_slot_id.
--   SELECT coverage_slot_id, COUNT(*) AS cnt FROM public.hr_emploc
--    WHERE coverage_slot_id IS NOT NULL AND deleted_at IS NULL
--    GROUP BY coverage_slot_id HAVING COUNT(*) > 1;
--   -- Expected: 0 rows.
--
-- RC3 — No HR Emploc row has BOTH slot_id and coverage_slot_id.
--   SELECT COUNT(*) AS both_bound FROM public.hr_emploc
--    WHERE slot_id IS NOT NULL AND coverage_slot_id IS NOT NULL;
--   -- Expected: 0.
--
-- RC4 — Every active roving HR Emploc row has non-NULL coverage_slot_id AND coverage_group_id.
--   SELECT COUNT(*) AS bad FROM public.hr_emploc
--    WHERE coverage_slot_id IS NOT NULL AND deleted_at IS NULL
--      AND coverage_group_id IS NULL;
--   -- Expected: 0.
--
-- RC5 — Three-way group agreement: slot.coverage_group_id = hr_emploc.coverage_group_id
--       = applicant.coverage_group_id for every bound roving HR Emploc row.
--   SELECT he.id
--     FROM public.hr_emploc he
--     JOIN public.coverage_slots cs ON cs.id = he.coverage_slot_id
--     LEFT JOIN public.applicants a ON a.id = he.applicant_id
--    WHERE he.coverage_slot_id IS NOT NULL AND he.deleted_at IS NULL
--      AND ( cs.coverage_group_id <> he.coverage_group_id
--         OR (a.coverage_group_id IS NOT NULL AND a.coverage_group_id <> he.coverage_group_id) );
--   -- Expected: 0 rows.
--
-- RC6 — No HR Emploc row bound to a coverage slot NOT in hr_processing
--       (HR Emploc only owns hr_processing).
--   SELECT he.id, cs.slot_status
--     FROM public.hr_emploc he
--     JOIN public.coverage_slots cs ON cs.id = he.coverage_slot_id
--    WHERE he.coverage_slot_id IS NOT NULL AND he.deleted_at IS NULL
--      AND cs.slot_status <> 'hr_processing';
--   -- Expected: 0 rows.
--
-- RC7 — Every hr_processing coverage slot is owned by an active HR Emploc row (no orphan).
--   SELECT cs.id FROM public.coverage_slots cs
--    WHERE cs.slot_status = 'hr_processing'
--      AND NOT EXISTS (SELECT 1 FROM public.hr_emploc he
--                       WHERE he.coverage_slot_id = cs.id AND he.deleted_at IS NULL);
--   -- Expected: 0 rows.
--
-- RC8 — coverage_slot_id / coverage_group_id FK integrity (no orphans).
--   SELECT COUNT(*) FROM public.hr_emploc he
--    WHERE (he.coverage_slot_id IS NOT NULL
--           AND NOT EXISTS (SELECT 1 FROM public.coverage_slots cs WHERE cs.id = he.coverage_slot_id))
--       OR (he.coverage_group_id IS NOT NULL
--           AND NOT EXISTS (SELECT 1 FROM public.coverage_groups cg WHERE cg.id = he.coverage_group_id));
--   -- Expected: 0.
--
-- RC9 — Duplicate Record deletion does NOT touch a coverage slot (smoke):
--   -- Approve a Duplicate Record request for a coverage-bound emploc; the coverage
--   -- slot remains hr_processing (only Backout reopens). Expected: slot unchanged.
--
-- RC10 — Backout reopen preserves slot_ordinal; slot returns to open (smoke):
--   -- After fn_approve_emploc_deletion_request (Backout) on a coverage emploc:
--   SELECT slot_status, slot_ordinal FROM public.coverage_slots WHERE id = '<slot>';
--   -- Expected: slot_status='open', slot_ordinal unchanged.
--
-- RC11 — Slot-side vs HR-side count agree per CGCODE.
--   SELECT s.coverage_group_id, s.hrp_slots, h.active_hr
--     FROM (SELECT coverage_group_id, COUNT(*) AS hrp_slots
--             FROM public.coverage_slots WHERE slot_status='hr_processing'
--            GROUP BY coverage_group_id) s
--     FULL OUTER JOIN (
--       SELECT coverage_group_id, COUNT(DISTINCT coverage_slot_id) AS active_hr
--         FROM public.hr_emploc
--        WHERE coverage_slot_id IS NOT NULL AND deleted_at IS NULL
--        GROUP BY coverage_group_id) h ON h.coverage_group_id = s.coverage_group_id
--    WHERE COALESCE(s.hrp_slots,0) <> COALESCE(h.active_hr,0);
--   -- Expected: 0 rows.
--
-- RC12 — Reconciliation survives R-C + stationary isolation:
--   -- Per group: open + pipeline + hr_processing + active + closed == required_headcount.
--   SELECT cg.id FROM public.coverage_groups cg
--     JOIN (SELECT coverage_group_id, COUNT(*) AS n FROM public.coverage_slots
--            GROUP BY coverage_group_id) c ON c.coverage_group_id = cg.id
--    WHERE cg.archived_at IS NULL AND c.n <> cg.required_headcount;
--   -- Expected: 0 rows.
--   -- Stationary shadow shows no CGCODE leakage:
--   SELECT COUNT(*) AS leaked FROM public.vw_slot_derived_vacancy_shadow v
--    WHERE v.legacy_vcode LIKE 'CG-%';
--   -- Expected: 0. Re-run RB1–RB10 + stationary C1–C12 GREEN.
-- ============================================================
