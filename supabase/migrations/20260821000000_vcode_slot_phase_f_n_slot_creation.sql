-- ============================================================
-- OHM2026_0052 — VCODE ↔ Slot Phase F: N-Slot VCODE Creation
-- Migration: 20260821000000_vcode_slot_phase_f_n_slot_creation.sql
-- Depends on:
--   20260816000000_vcode_slot_phase_a_schema_bridge.sql
--     (plantilla_slots.slot_ordinal NOT NULL, composite unique
--      uq_plantilla_slots_legacy_vcode_ordinal, applicants.slot_id FK)
--   20260817000000_vcode_slot_phase_b_applicant_binding.sql
--     (uq_applicants_one_active_per_slot, create_applicant_and_link_to_vacancy)
--   20260819000000_vcode_slot_phase_c_hr_emploc_binding.sql
--     (uq_hr_emploc_one_active_per_slot, hr_emploc.slot_id backfilled)
--   20260820000000_vcode_slot_phase_d_shadow_aggregation.sql
--     (vw_slot_derived_vacancy_shadow, VCODE-grain aggregation, D1–D12 GREEN)
--   Pre-existing (not re-listed): Phase E closure fan-out (E1–E14 GREEN)
--   Pre-existing helpers:
--     generate_vcode_for_account(), fn_assert_freeze_inactive(),
--     i_have_full_access(), get_current_profile_id(), get_my_role()
-- ============================================================
-- Scope: Phase F — HC Request completion rewired to produce ONE VCODE
-- with N slots (slot_ordinal 1..N) instead of N VCODEs each with 1 slot.
--
-- Authorising documents (locked):
--   docs/architecture/vcode_slot_bridge_redesign.md (OHM2026_0035) §1,§2,§9
--   docs/architecture/vcode_slot_phase_f_n_slot_creation_plan.md (OHM2026_0051)
--     Q1 (N slots under 1 VCODE), Q2 (slot_ordinal MAX+1), Q4 (drop per-vcode
--     unique), Q5 (1-slot VCODEs coexist), Q7 (rollout F0→F1→F2/F3→F4)
--
-- What this migration does:
--   F1  Drop uq_applicants_one_active_per_vcode (1:1-era guard, now superseded
--       by uq_applicants_one_active_per_slot from Phase B). Gated on both
--       per-slot uniques (applicants + hr_emploc) confirmed present.
--       THIS IS THE POINT OF NO EASY RETURN (see Q4 design doc).
--   F2  Replace fn_create_slots_from_hc_request:
--       - New signature: p_vcode text (was p_vcodes text[])
--       - Assigns slot_ordinal = MAX(slot_ordinal)+1 per legacy_vcode (v_base+i)
--       - All N slots receive the same p_vcode as legacy_vcode
--   F3  Replace create_plantilla_slot_from_request:
--       - Generates exactly ONE vcode per request (not in a loop)
--       - Inserts exactly ONE vacancies row with required_headcount = v_count
--       - Loops N times for pool plantilla (VACANT SLOT) rows, all same vcode
--       - Passes single v_vcode to fn_create_slots_from_hc_request
--   F4  GRANTs
--   F5  Post-migration validation queries (manual, in comments)
--
-- What this migration deliberately does NOT do:
--   • Modify Flutter UI or any client-side code
--   • Modify shadow view aggregation (Phase D — stays unwired)
--   • Modify applicant lifecycle helpers (Phase B)
--   • Modify HR Emploc lifecycle helpers (Phase C)
--   • Modify closure fan-out (Phase E)
--   • Modify roving logic or roving slot creation
--   • Backfill or retro-merge historical 1-slot VCODEs
--   • Wire the shadow view to the UI (Phase G)
--   • Recreate or apply 20260815000000_one_store_one_vcode.sql (BLOCKED)
--
-- Key invariant after this migration:
--   HC=1  → 1 VCODE, 1 vacancy (required_headcount=1),  1 slot  (ordinal=1)
--   HC=N  → 1 VCODE, 1 vacancy (required_headcount=N),  N slots (ordinals=1..N)
--   All new N-slot VCODEs: one vacancy card in the shadow view.
--   Existing 1-slot VCODEs: unchanged (N=1 special case).
--
-- Idempotency:
--   F1  DROP INDEX IF EXISTS — no-op if already dropped.
--   F2  DROP FUNCTION IF EXISTS (old array signature) + CREATE OR REPLACE.
--   F3  CREATE OR REPLACE.
--   Per-slot idempotency for create_plantilla_slot_from_request is guaranteed
--   by the Layer-1 status guard (approved_pending_vcode) and Layer-2 EXISTS
--   check on plantilla_slots, unchanged from the pre-Phase-F version.
--
-- ============================================================
-- §F0 — Pre-gate (run MANUALLY before applying)
-- ============================================================
--
-- Gate 1: uq_applicants_one_active_per_slot exists (Phase B replacement guard).
--   SELECT indexname FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'applicants'
--       AND indexname  = 'uq_applicants_one_active_per_slot';
--   -- Expected: 1 row. STOP if missing — Phase B must be applied first.
--
-- Gate 2: uq_hr_emploc_one_active_per_slot exists (Phase C guard).
--   SELECT indexname FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'hr_emploc'
--       AND indexname  = 'uq_hr_emploc_one_active_per_slot';
--   -- Expected: 1 row. STOP if missing — Phase C must be applied first.
--
-- Gate 3: composite unique (legacy_vcode, slot_ordinal) exists (Phase A guard).
--   SELECT indexname FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'plantilla_slots'
--       AND indexname  = 'uq_plantilla_slots_legacy_vcode_ordinal';
--   -- Expected: 1 row. STOP if missing — Phase A must be applied first.
--
-- Gate 4: 1:1 baseline — all existing slots have ordinal=1, one slot per vcode.
--   SELECT legacy_vcode, COUNT(*), MAX(slot_ordinal)
--     FROM public.plantilla_slots
--     WHERE legacy_vcode IS NOT NULL
--     GROUP BY legacy_vcode
--     HAVING COUNT(*) > 1 OR MAX(slot_ordinal) > 1;
--   -- Expected: 0 rows (clean 1:1 baseline).
--
-- Gate 5: P/B/C/D suites GREEN (re-run before applying).
--   -- Run parity suites; confirm all invariants hold.
--
-- Gate 6: uq_applicants_one_active_per_vcode still exists (to be dropped in F1).
--   SELECT indexname FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'applicants'
--       AND indexname  = 'uq_applicants_one_active_per_vcode';
--   -- Expected: 1 row. If already absent, F1 is a no-op (safe to proceed).
-- ============================================================


-- ============================================================
-- §F1 — Drop uq_applicants_one_active_per_vcode
-- ============================================================
-- This is the 1:1-era guard: one active applicant per VCODE.
-- Under N-slot, a single VCODE legitimately has N active applicants
-- (one per slot) — the per-vcode unique blocks the 2nd active applicant,
-- breaking the N-slot model.
--
-- Replacement: uq_applicants_one_active_per_slot (Phase B, live since
-- OHM2026_0041) is strictly finer-grained and provides equivalent
-- protection on the existing 1:1 data. Dropping the per-vcode guard
-- loses no real protection.
--
-- THIS IS THE POINT OF NO EASY RETURN (OHM2026_0051 Q4):
-- Once a 2nd active applicant exists on a single VCODE (the first
-- genuine N-slot recruitment), this index cannot be recreated — the
-- data violates it by design. This step is deliberate and forward-only.
--
-- Note: applicant_cross_account_active_guard is a SEPARATE constraint
-- (OHM2026_0731) governing cross-account active status — NOT dropped here.
--
-- Dropped BEFORE N-slot creation is wired (§F2/F3) to ensure no window
-- where a correctly-built N-slot VCODE cannot accept its 2nd applicant.

DROP INDEX IF EXISTS public.uq_applicants_one_active_per_vcode;


-- ============================================================
-- §F2 — Replace fn_create_slots_from_hc_request
--        (p_vcode text instead of p_vcodes text[]; slot_ordinal assignment)
-- ============================================================
-- Phase F change (all other logic IDENTICAL to OHM2026_0007 version):
--   1. Signature change: p_vcodes text[] → p_vcode text (single VCODE).
--      All N slots receive the same legacy_vcode = p_vcode.
--   2. slot_ordinal assignment (wired here for the first time):
--      v_base = COALESCE(MAX(slot_ordinal), 0) over existing slots for p_vcode.
--      For a fresh VCODE (no existing slots): v_base=0, ordinals=1..N.
--      For an HC-add (future workflow): v_base=MAX(existing), ordinals=MAX+1..MAX+N.
--      Ordinals are never recycled — closed slot retains its ordinal (locked rule).
--      The composite unique (uq_plantilla_slots_legacy_vcode_ordinal, Phase A) is
--      the race backstop — a concurrent ordinal collision becomes a retry.
--   3. slot_history remarks updated to show "vcode=<v>" instead of array index.
--
-- Caller: create_plantilla_slot_from_request (§F3 below).
-- Standalone call (direct): p_vcode=NULL → legacy_vcode=NULL, v_base=0,
--   ordinals=1..N — same as a fresh roving/no-vcode batch (safe fallback).
--
-- Old signature: fn_create_slots_from_hc_request(uuid, integer, text[])
-- Must be dropped before CREATE OR REPLACE because the parameter type changes.

DROP FUNCTION IF EXISTS public.fn_create_slots_from_hc_request(uuid, integer, text[]);

CREATE OR REPLACE FUNCTION public.fn_create_slots_from_hc_request(
  p_request_id uuid,
  p_quantity   integer DEFAULT NULL,
  p_vcode      text    DEFAULT NULL    -- Phase F: single VCODE for all N slots
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
/*
  Phase F (OHM2026_0052) — creates N plantilla_slots rows under ONE VCODE.

  Phase F changes from OHM2026_0007:
    • p_vcodes text[] (N-element array) replaced by p_vcode text (single value).
    • slot_ordinal is now explicitly assigned: v_base + i where
      v_base = COALESCE(MAX(slot_ordinal), 0) over existing slots for p_vcode.
      For a fresh vcode: v_base=0, ordinals=1..N.
      For HC-add (future): v_base=MAX(existing), ordinals=MAX+1..MAX+N.
    • All N slots receive legacy_vcode = p_vcode (same VCODE, not per-slot).

  All other logic — RBAC, HC request validation, account/store/group/position
  resolution, is_roving, slot_history creation, return shape — is IDENTICAL
  to the OHM2026_0007 version.
*/
DECLARE
  v_role            text    := public.get_my_role();
  v_caller_id       uuid    := public.get_current_profile_id();
  v_req             public.headcount_requests%ROWTYPE;
  v_account         public.accounts%ROWTYPE;
  v_store           public.stores%ROWTYPE;
  v_group           public.groups%ROWTYPE;
  v_position        public.positions%ROWTYPE;
  v_qty             integer;
  v_slot_id         uuid;
  v_slot_ids        uuid[]  := ARRAY[]::uuid[];
  v_is_roving       boolean;
  v_employment_type text;
  v_position_name   text;
  v_group_id        uuid;
  v_base            smallint;    -- Phase F: ordinal base for this batch
  i                 integer;
BEGIN
  -- ── RBAC: Data Team (Encoder) and full-access roles ───────────────────────
  IF v_role NOT IN ('Encoder', 'Head Admin', 'Super Admin') THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'forbidden',
      'hint',  'requires Encoder, Head Admin, or Super Admin'
    );
  END IF;

  -- ── Fetch and pessimistically lock the HC request ─────────────────────────
  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  -- ── Guard: only approved requests are eligible for slot creation ──────────
  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object(
      'ok',      false,
      'error',   'request_not_in_approved_state',
      'current', v_req.status,
      'expected','approved_pending_vcode'
    );
  END IF;

  -- ── Resolve quantity ──────────────────────────────────────────────────────
  v_qty := COALESCE(p_quantity, v_req.headcount_needed, 1);

  IF v_qty < 1 THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'invalid_quantity',
      'hint',  'quantity must be greater than 0'
    );
  END IF;

  -- ── Validate account (required) ───────────────────────────────────────────
  IF v_req.account_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'missing_account_id',
      'hint',  'headcount_requests.account_id is required for slot creation'
    );
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_req.account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'invalid_reference',
      'field', 'account_id'
    );
  END IF;

  -- ── Validate store (when present on the request) ──────────────────────────
  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
    IF v_store.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'store_id'
      );
    END IF;
  END IF;

  -- ── Resolve and validate group_id ─────────────────────────────────────────
  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  IF v_group_id IS NOT NULL THEN
    SELECT * INTO v_group FROM public.groups WHERE id = v_group_id;
    IF v_group.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'group_id'
      );
    END IF;
  END IF;

  -- ── Resolve position name ─────────────────────────────────────────────────
  IF v_req.position_id IS NOT NULL THEN
    SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;
    IF v_position.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'position_id'
      );
    END IF;
    v_position_name := v_position.position_name;
  ELSE
    v_position_name := v_req.position_name_snapshot;
  END IF;

  IF v_position_name IS NULL OR TRIM(v_position_name) = '' THEN
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'missing_position',
      'hint',  'no resolvable position on HC request'
    );
  END IF;

  -- ── Resolve employment_type and roving flag ───────────────────────────────
  v_employment_type := v_req.employment_type;
  v_is_roving := (v_employment_type = 'Roving');

  -- ── Phase F: compute ordinal base for this batch ──────────────────────────
  -- v_base = highest existing slot_ordinal for p_vcode (or 0 if none).
  -- Fresh VCODE (initial create): v_base=0 → ordinals=1..N.
  -- HC-add (future): v_base=MAX(existing) → ordinals=MAX+1..MAX+N.
  -- Closed ordinals are included (never recycled — monotonic rule).
  -- NULL p_vcode (standalone/roving): v_base=0, ordinals start at 1.
  -- The composite unique (uq_plantilla_slots_legacy_vcode_ordinal, Phase A)
  -- is the race backstop — a concurrent ordinal collision → retry.
  IF p_vcode IS NOT NULL THEN
    SELECT COALESCE(MAX(slot_ordinal), 0)::smallint INTO v_base
    FROM public.plantilla_slots
    WHERE legacy_vcode = p_vcode;
  ELSE
    v_base := 0;
  END IF;

  -- ── Create one slot + one history row per HC unit ─────────────────────────
  FOR i IN 1..v_qty LOOP

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,        -- Phase F: assigned monotonically (v_base + i)
      source_hc_request_id,
      legacy_vcode,        -- Phase F: same vcode for all N slots
      created_by,
      updated_by
    ) VALUES (
      v_store.id,
      v_account.id,
      v_group_id,
      v_position_name,
      v_employment_type,
      v_is_roving,
      'open',
      (v_base + i)::smallint,  -- Phase F: ordinal 1..N (or MAX+1..MAX+N for HC-add)
      p_request_id,
      p_vcode,             -- Phase F: same vcode for all slots; NULL for roving/standalone
      v_caller_id,
      v_caller_id
    )
    RETURNING id INTO v_slot_id;

    v_slot_ids := array_append(v_slot_ids, v_slot_id);

    INSERT INTO public.slot_history (
      slot_id,
      account_id,
      action_type,
      new_value,
      reason_code,
      performed_by,
      remarks
    ) VALUES (
      v_slot_id,
      v_account.id,
      'created',
      'open',
      'HC_ADD',
      v_caller_id,
      format(
        'Phase F slot %s of %s (ordinal=%s) from HC request %s — %s %s%s',
        i, v_qty,
        (v_base + i),
        p_request_id::text,
        v_employment_type,
        v_position_name,
        CASE WHEN p_vcode IS NOT NULL
             THEN ' [vcode=' || p_vcode || ']'
             ELSE '' END
      )
    );

  END LOOP;

  RETURN jsonb_build_object(
    'ok',            true,
    'request_id',    p_request_id,
    'slots_created', v_qty,
    'slot_ids',      v_slot_ids,
    'vcode',         p_vcode,
    'ordinal_range', jsonb_build_object('from', v_base + 1, 'to', v_base + v_qty)
  );

END;
$$;

COMMENT ON FUNCTION public.fn_create_slots_from_hc_request(uuid, integer, text) IS
  'Phase F (OHM2026_0052): creates N plantilla_slots rows, all under ONE VCODE. '
  'p_vcode (single text, was text[] in OHM2026_0007): the single legacy_vcode '
  'assigned to all N slots. NULL → legacy_vcode stays NULL (roving/standalone). '
  'slot_ordinal = MAX(existing)+i (monotonic, never recycled, race-safe via '
  'uq_plantilla_slots_legacy_vcode_ordinal backstop). '
  'Fresh VCODE: ordinals 1..N. HC-add: MAX+1..MAX+N. '
  'RBAC: Encoder | Head Admin | Super Admin. '
  'HC request status must be approved_pending_vcode. '
  'Called from create_plantilla_slot_from_request (OHM2026_0052 dual-write). '
  'See OHM2026_0051 Q1/Q2 for design rationale.';

REVOKE ALL ON FUNCTION public.fn_create_slots_from_hc_request(uuid, integer, text)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_create_slots_from_hc_request(uuid, integer, text)
  TO authenticated;


-- ============================================================
-- §F3 — Replace create_plantilla_slot_from_request
--        (single VCODE, one vacancy, N pool plantilla, N slots)
-- ============================================================
-- Phase F change (all other logic IDENTICAL to OHM2026_0007 version):
--   1. generate_vcode_for_account: called ONCE (not in the loop).
--      HC=1: no observable change. HC=N: 1 vcode instead of N vcodes.
--   2. vacancies INSERT: moved outside the loop, required_headcount=v_count
--      (was 1 per row; Phase D §D3 cross-check requires this to match N slots).
--      One vacancy row per request regardless of v_count.
--   3. plantilla loop: still runs N times (one pool plantilla per HC unit),
--      but all rows share the single v_vcode. Preserves dual-write HC
--      arithmetic during the transition era (N VACANT SLOT rows under one
--      vcode). Pool collapse is deferred to Phase G.
--   4. source_plantilla_id: vacancy linked to the first pool plantilla only
--      (v_first_plantilla_id, same as before for HC=1; for HC>1 uses first).
--   5. fn_create_slots_from_hc_request: called with v_vcode (text, single)
--      instead of v_vcodes (text[], N-element).
--   6. created_vcode / created_vcodes: headcount_requests updated to reflect
--      the single vcode; created_vcodes is now a 1-element array for all
--      requests (including HC>1). Downstream consumers should handle a
--      single-element array (flagged in OHM2026_0051 risk register).
--
-- Return shape: preserved except vcode_count is always 1 and vcodes is
-- a 1-element array. The 'slot_result' field still carries the dual-write
-- outcome from fn_create_slots_from_hc_request.

CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
/*
  Phase F (OHM2026_0052) — HC Request completion: one VCODE, N slots.

  Phase F changes from OHM2026_0007:
    • generate_vcode_for_account called ONCE before the plantilla loop.
    • vacancies INSERT: outside the loop, required_headcount = v_count.
    • plantilla loop creates N VACANT SLOT rows, all with the same v_vcode.
    • fn_create_slots_from_hc_request receives v_vcode (single text).
    • created_vcodes = ARRAY[v_vcode] (1-element array for all requests).

  Recruitment freeze guard, RBAC, idempotency (Layer-1 status guard +
  Layer-2 slot EXISTS check), account/store/position lookups, pool
  plantilla creation, request status update: all IDENTICAL to OHM2026_0007.
*/
DECLARE
  v_role               text := public.get_my_role();
  v_req                public.headcount_requests%ROWTYPE;
  v_account            public.accounts%ROWTYPE;
  v_store              public.stores%ROWTYPE;
  v_position           public.positions%ROWTYPE;
  v_store_name         text;
  v_store_id           uuid;
  v_vcode              text;              -- Phase F: single vcode for all slots
  v_vcodes             text[];            -- Phase F: 1-element array [v_vcode]
  v_plantilla_id       uuid;
  v_vacancy_id         uuid;
  v_first_plantilla_id uuid;
  v_count              integer;
  i                    integer;
  v_triggered_by_id    uuid;
  v_triggered_by_name  text;
  v_hrco_user_id       uuid;
  v_hrco_name          text;
  v_group_id           uuid;
  v_group_name         text;
  v_slot_result        jsonb;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  -- Enforce Recruitment Freeze (unchanged)
  PERFORM public.fn_assert_freeze_inactive('recruitment_freeze');

  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  -- Layer-1 idempotency guard: only approved_pending_vcode proceeds.
  -- Once status becomes 'completed', all subsequent calls are blocked here.
  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_approved', 'current', v_req.status);
  END IF;

  v_count := COALESCE(v_req.headcount_needed, 1);

  IF v_count < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  IF v_count > 20 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'headcount_limit_exceeded', 'max', 20);
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_req.account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  END IF;

  SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;
  IF v_position.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  END IF;

  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
  END IF;

  v_store_name := NULLIF(TRIM(COALESCE(v_store.store_name, v_req.store_name_snapshot)), '');
  v_store_id   := v_store.id;

  IF v_store_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_name');
  END IF;

  v_group_id := COALESCE(v_req.group_id, v_account.group_id);
  SELECT group_name INTO v_group_name FROM public.groups WHERE id = v_group_id;

  v_triggered_by_id := public.get_current_profile_id();
  SELECT full_name INTO v_triggered_by_name
  FROM public.users_profile WHERE id = v_triggered_by_id;

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  -- ── Phase F: generate ONE vcode for this request ─────────────────────────
  -- Called once (not in a loop). HC=N → one vcode shared by all N slots.
  -- HC=1: no observable difference from the old per-iteration behavior.
  v_vcode  := public.generate_vcode_for_account(v_account.id);
  v_vcodes := ARRAY[v_vcode];
  -- ──────────────────────────────────────────────────────────────────────────

  -- ── Phase F: insert ONE vacancy with required_headcount = v_count ─────────
  -- Old code: one vacancy per HC unit (required_headcount=1 each).
  -- Phase F: one vacancy per request, required_headcount=N.
  -- This makes Phase D §D3 cross-check hold:
  --   COUNT(slots) = required_hc = vacancies.required_headcount.
  INSERT INTO public.vacancies (
    vcode, account, position, status,
    account_id, store_id, position_id, group_id,
    area_name, store_name, vacant_date,
    required_headcount, source_plantilla_id,
    vacancy_type, employment_type, urgency_level,
    target_fill_date, triggered_by_user_id, triggered_by_name,
    hrco_user_id, hrco_name,
    source, source_headcount_request_id,
    area_city, province, store_branch,
    chain, chain_id,
    created_by, updated_by
  ) VALUES (
    v_vcode, v_account.account_name, v_position.position_name, 'Open',
    v_account.id, v_store_id, v_position.id, v_group_id,
    COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
    v_store_name,
    COALESCE(v_req.vacant_date, CURRENT_DATE),
    v_count,   -- Phase F: required_headcount = N (was 1 per row)
    NULL,      -- source_plantilla_id patched below after pool plantilla loop
    CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
    v_req.employment_type, v_req.urgency, v_req.target_fill_date,
    v_triggered_by_id, v_triggered_by_name,
    v_hrco_user_id, v_hrco_name,
    'hc_request', p_request_id,
    COALESCE(v_store.area_city, v_req.city_municipality),
    COALESCE(v_store.province, NULLIF(TRIM(v_req.area), '')),
    v_store.store_branch,
    v_group_name, v_group_id,
    v_triggered_by_id, v_triggered_by_id
  ) RETURNING id INTO v_vacancy_id;
  -- ──────────────────────────────────────────────────────────────────────────

  -- ── Phase F: pool plantilla loop — N rows, all under the single vcode ─────
  -- Old code: one vacancy + one plantilla per iteration.
  -- Phase F: vacancy created above; loop only inserts pool plantilla rows.
  -- N VACANT SLOT rows share v_vcode during the dual-write era (legacy HC
  -- arithmetic unchanged; pool collapse is deferred to Phase G).
  FOR i IN 1..v_count LOOP
    INSERT INTO public.plantilla (
      employee_name, employee_no,
      account, status, vcode, position,
      account_id, store_id, area, position_id,
      store_name, deployment_type,
      source_headcount_request_id,
      chain_id,
      created_by, updated_by, tagged_at
    ) VALUES (
      '(VACANT SLOT)', '(PENDING)',
      v_account.account_name, 'Inactive', v_vcode, v_position.position_name,
      v_account.id, v_store_id,
      COALESCE(NULLIF(TRIM(v_req.area), ''), v_store.province, v_store.area_province),
      v_position.id,
      v_store_name, v_req.employment_type,
      p_request_id,
      v_group_id,
      v_triggered_by_id, v_triggered_by_id, CURRENT_DATE
    ) RETURNING id INTO v_plantilla_id;

    IF v_first_plantilla_id IS NULL THEN
      v_first_plantilla_id := v_plantilla_id;
    END IF;
  END LOOP;
  -- ── End pool plantilla loop ───────────────────────────────────────────────

  -- Link the single vacancy to the first pool plantilla row (unchanged semantics)
  UPDATE public.vacancies
  SET source_plantilla_id = v_first_plantilla_id,
      updated_by          = v_triggered_by_id
  WHERE id = v_vacancy_id;

  -- ── TRANSITIONAL DUAL-WRITE: create matching plantilla_slots ─────────────
  -- Layer-2 idempotency guard: if slots already exist for this request,
  -- skip slot creation. Under normal flow the status guard (Layer 1)
  -- guarantees this check is always false at this point.
  IF NOT EXISTS (
    SELECT 1 FROM public.plantilla_slots
    WHERE source_hc_request_id = p_request_id
    LIMIT 1
  ) THEN
    -- Phase F: pass single v_vcode (text) instead of v_vcodes (text[]).
    -- fn_create_slots_from_hc_request creates N slots, each with
    -- legacy_vcode=v_vcode and slot_ordinal=1..N.
    v_slot_result := public.fn_create_slots_from_hc_request(p_request_id, v_count, v_vcode);
  ELSE
    v_slot_result := jsonb_build_object(
      'ok',    false,
      'error', 'slots_already_existed',
      'hint',  'plantilla_slots were already present for this request; skipped dual-write'
    );
  END IF;
  -- ── End transitional dual-write ───────────────────────────────────────────

  -- Phase F: created_vcodes is now a 1-element array for all HC requests.
  -- Downstream consumers (Flutter/web) must handle a single-element array
  -- for multi-HC requests — flagged in OHM2026_0051 risk register.
  UPDATE public.headcount_requests
  SET status                   = 'completed',
      vacancy_created          = true,
      slot_created_by_user_id  = v_triggered_by_id,
      slot_created_at          = NOW(),
      created_plantilla_id     = v_first_plantilla_id,
      created_vcode            = v_vcode,        -- single vcode (unchanged field meaning)
      created_vcodes           = v_vcodes         -- Phase F: 1-element array [v_vcode]
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',                true,
    'request_id',        p_request_id,
    'headcount_created', v_count,
    'vcode_count',       1,            -- Phase F: always 1 (one VCODE per request)
    'vcodes',            v_vcodes,     -- Phase F: 1-element array [v_vcode]
    'vacancy_created',   true,
    'slot_result',       v_slot_result
  );
END;
$function$;

COMMENT ON FUNCTION public.create_plantilla_slot_from_request(uuid) IS
  'Phase F (OHM2026_0052): HC Request completion producing one VCODE per request. '
  'generate_vcode_for_account called once; one vacancies row with '
  'required_headcount=N; N pool plantilla VACANT SLOT rows under the single vcode; '
  'fn_create_slots_from_hc_request(request_id, N, vcode) creates N slots with '
  'slot_ordinal=1..N, all bound to the same legacy_vcode. '
  'HC=1: identical outcome to pre-Phase-F (one vcode, one vacancy, one slot). '
  'HC=N: one vcode, one vacancy (required_headcount=N), N slots (ordinals 1..N). '
  'created_vcodes is now a 1-element array for all requests. '
  'Pool plantilla collapse to slot-derived is deferred to Phase G. '
  'Existing 1-slot VCODEs untouched. Shadow view stays unwired until Phase G. '
  'Phase OHM2026_0007 (legacy): N vcodes, N vacancies (required_headcount=1 each). '
  'See OHM2026_0051 Q1/Q2/Q5/Q7 for design rationale.';


-- ============================================================
-- §F4 — GRANTs
-- ============================================================

REVOKE ALL ON FUNCTION public.create_plantilla_slot_from_request(uuid)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_plantilla_slot_from_request(uuid)
  TO authenticated;


-- ============================================================
-- §F5 — Post-migration validation queries (run manually)
-- ============================================================
--
-- ── Structural checks ─────────────────────────────────────────────────────
--
-- V1 — uq_applicants_one_active_per_vcode dropped.
--   SELECT indexname FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename  = 'applicants'
--       AND indexname  = 'uq_applicants_one_active_per_vcode';
--   -- Expected: 0 rows (dropped in §F1).
--
-- V2 — Per-slot uniques still present.
--   SELECT indexname FROM pg_indexes
--     WHERE schemaname = 'public'
--       AND tablename IN ('applicants', 'hr_emploc')
--       AND indexname IN (
--         'uq_applicants_one_active_per_slot',
--         'uq_hr_emploc_one_active_per_slot'
--       );
--   -- Expected: 2 rows.
--
-- V3 — fn_create_slots_from_hc_request new signature (text, not text[]).
--   SELECT pg_get_function_arguments(oid) AS args
--     FROM pg_proc
--     WHERE proname      = 'fn_create_slots_from_hc_request'
--       AND pronamespace = 'public'::regnamespace;
--   -- Expected: 1 row with args containing 'text' (not 'text[]').
--
-- V4 — create_plantilla_slot_from_request body reflects Phase F.
--   SELECT prosrc LIKE '%required_headcount%v_count%'
--          OR prosrc LIKE '%v_count%required_headcount%'
--     FROM pg_proc
--     WHERE proname      = 'create_plantilla_slot_from_request'
--       AND pronamespace = 'public'::regnamespace;
--   -- Expected: true (single-vacancy with required_headcount=N present).
--
-- ── Functional validation (run against test data) ────────────────────────
--
-- F1 — HC=1 request: creates 1 VCODE + 1 vacancy (required_headcount=1)
--      + 1 pool plantilla + 1 slot (ordinal=1).
--   SELECT vcode, required_headcount FROM public.vacancies
--     WHERE source_headcount_request_id = '<hc_request_id_1>';
--   -- Expected: 1 row, required_headcount=1.
--   SELECT slot_ordinal, slot_status, legacy_vcode FROM public.plantilla_slots
--     WHERE source_hc_request_id = '<hc_request_id_1>';
--   -- Expected: 1 row, slot_ordinal=1, slot_status='open'.
--
-- F2 — HC=5 request: creates 1 VCODE + 1 vacancy (required_headcount=5)
--      + 5 pool plantilla + 5 slots (ordinals=1..5).
--   SELECT vcode, required_headcount FROM public.vacancies
--     WHERE source_headcount_request_id = '<hc_request_id_5>';
--   -- Expected: 1 row, required_headcount=5.
--   SELECT slot_ordinal, slot_status, legacy_vcode FROM public.plantilla_slots
--     WHERE source_hc_request_id = '<hc_request_id_5>'
--     ORDER BY slot_ordinal;
--   -- Expected: 5 rows, ordinals 1–5, all slot_status='open',
--   --   all legacy_vcode = same vcode as the vacancy above.
--
-- F3 — Shadow renders one card for the 5-slot VCODE.
--   SELECT legacy_vcode, required_hc, open_count, pipeline_count,
--          hr_processing_count, occupied_count, closed_count
--     FROM public.vw_slot_derived_vacancy_shadow
--     WHERE legacy_vcode = '<new_vcode_from_F2>';
--   -- Expected: 1 row, required_hc=5, open_count=5, all others=0.
--   -- Reconciliation: open+pipeline+hr_processing+occupied+closed = 5.
--
-- F4 — Add Applicant binds to slot_ordinal=1 first.
--   -- After adding applicant 1 to the 5-slot VCODE:
--   SELECT a.slot_id, ps.slot_ordinal, ps.slot_status
--     FROM public.applicants a
--     JOIN public.plantilla_slots ps ON ps.id = a.slot_id
--     WHERE a.vacancy_vcode = '<new_vcode_from_F2>' AND a.is_archived = false
--     ORDER BY ps.slot_ordinal;
--   -- Expected: slot_ordinal=1, slot_status='pipeline'.
--   -- Shadow: open_count=4, pipeline_count=1 for that VCODE.
--
-- F5 — N active applicants coexist on one VCODE (dropped guard).
--   -- After adding applicants 1–5 to the 5-slot VCODE:
--   SELECT COUNT(*) AS active_applicants
--     FROM public.applicants a
--     WHERE a.vacancy_vcode = '<new_vcode_from_F2>'
--       AND public.fn_is_active_vacancy_applicant_status(a.status)
--       AND COALESCE(a.is_archived, false) = false;
--   -- Expected: 5 (no uq_applicants_one_active_per_vcode violation).
--
-- F6 — (N+1)-th Add Applicant rejected (no open slot).
--   -- After all 5 slots are in pipeline/hr_processing/occupied:
--   -- Attempting a 6th create_applicant_and_link_to_vacancy call should
--   -- raise SQLSTATE P0001 'no_open_slot'.
--
-- F7 — HC-add ordinal assignment (future workflow gate):
--   -- After adding an HC-add to an existing N-slot VCODE:
--   SELECT MAX(slot_ordinal) FROM public.plantilla_slots
--     WHERE legacy_vcode = '<existing_vcode>';
--   -- Expected: MAX = N + (added HC), no gaps reused.
--
-- F8 — Reconciliation invariant holds for N-slot VCODE.
--   SELECT legacy_vcode,
--          open_count + pipeline_count + hr_processing_count
--          + occupied_count + closed_count AS total,
--          required_hc
--     FROM public.vw_slot_derived_vacancy_shadow
--     WHERE legacy_vcode = '<new_vcode_from_F2>'
--       AND open_count + pipeline_count + hr_processing_count
--           + occupied_count + closed_count != required_hc;
--   -- Expected: 0 rows (reconciliation holds).
--
-- F9 — Existing 1-slot VCODEs unchanged.
--   SELECT COUNT(*) AS multi_slot_legacy_vcodes
--     FROM public.plantilla_slots
--     WHERE source_hc_request_id NOT IN (
--       -- exclude requests completed after Phase F was applied
--       SELECT id FROM public.headcount_requests
--       WHERE slot_created_at >= '<phase_f_applied_at>'
--     )
--     AND legacy_vcode IS NOT NULL
--     GROUP BY legacy_vcode
--     HAVING COUNT(*) > 1;
--   -- Expected: 0 rows (no retro-merge of historical VCODEs).
--
-- F10 — P/B/C/D suites re-run GREEN (run all parity suites after applying).
-- ============================================================
