-- Migration: 20260608000000_fix_vcode_creation_access_ha_encoder.sql
-- Ticket:    OHM2026_#### — Fix VCODE Creation Access for Encoder and Head Admin
--
-- Root Cause:
--   assert_vacancy_edit_allowed() only allows Super Admin to bypass the vacancy
--   edit lock. When the scheduled window (Mon 17:00 – Tue 14:00 PHT) or a manual
--   lock is active, the trigger trg_fn_assert_vacancy_edit_allowed fires on every
--   INSERT/UPDATE/DELETE on public.vacancies and public.applicants, blocking
--   Head Admin and Encoder from creating VCODEs — even though:
--     • Head Admin can lock/unlock the module and has can_override=true in
--       get_vacancy_edit_lock_status().
--     • Encoder INSERTs into vacancies exclusively through SECURITY DEFINER RPCs
--       (approve_vacancy_request_auto_vcodes, create_plantilla_slot_from_request)
--       as the authorised VCODE-creation workflow.
--   The RPC-level RBAC gates already allow SA/HA/Encoder correctly. The trigger
--   is the only blocking gate.
--
-- Fix (minimum surface):
--   1. fn_assert_vacancy_edit_allowed_op(p_op text) — new op-aware helper:
--        • Super Admin  → bypass all ops (audit log preserved).
--        • Head Admin   → bypass all ops (audit log added).
--        • Encoder      → bypass INSERT only (VCODE creation).
--        • All others   → raise 42501 when locked (unchanged).
--   2. assert_vacancy_edit_allowed() (no-arg, existing) — now delegates to
--      fn_assert_vacancy_edit_allowed_op('UPDATE') so any external callers
--      keep working and remain conservatively gated.
--   3. trg_fn_assert_vacancy_edit_allowed() — passes TG_OP to the new helper
--      so trigger enforces per-operation rules.
--   4. get_vacancy_edit_lock_status() — sets can_edit=true for Head Admin
--      when locked, keeping the returned flag accurate for the frontend.
--
-- Not changed:
--   • Scheduled lock window (Mon 17:00–Tue 14:00 PHT)
--   • Manual lock/unlock RPCs or audit schema
--   • RLS policies
--   • VCODE format / generation functions
--   • Encoder UPDATE/DELETE remain blocked during lock
--   • All other roles remain blocked (unchanged)

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Operation-aware implementation helper
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_vacancy_edit_allowed_op(p_op text)
  RETURNS void
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_role    text;
  v_user_id uuid;
BEGIN
  IF NOT public.is_vacancy_edit_locked() THEN
    RETURN;
  END IF;

  v_role    := public.get_effective_role();
  v_user_id := public.get_current_profile_id();

  IF v_role = 'Super Admin' THEN
    -- Original behavior: log override and allow.
    INSERT INTO public.vacancy_edit_lock_audit (
      action_type, actor_user_id, actor_role, reason, previous_state, new_state
    ) VALUES (
      'override', v_user_id, v_role,
      'Super Admin vacancy mutation bypass during active lock (op=' || p_op || ')',
      NULL, NULL
    );
    RETURN;

  ELSIF v_role = 'Head Admin' THEN
    -- Head Admin has can_override=true and controls the lock; allow all ops.
    INSERT INTO public.vacancy_edit_lock_audit (
      action_type, actor_user_id, actor_role, reason, previous_state, new_state
    ) VALUES (
      'override', v_user_id, v_role,
      'Head Admin vacancy mutation bypass during active lock (op=' || p_op || ')',
      NULL, NULL
    );
    RETURN;

  ELSIF v_role = 'Encoder' AND p_op = 'INSERT' THEN
    -- Encoder is authorised to create VCODEs (INSERT into vacancies) via
    -- SECURITY DEFINER RPCs only. UPDATE and DELETE remain blocked.
    RETURN;

  ELSE
    RAISE EXCEPTION
      'Vacancy edits are currently locked. Only Super Admin and Head Admin may override.'
      USING ERRCODE = '42501';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_assert_vacancy_edit_allowed_op(text) TO authenticated;

COMMENT ON FUNCTION public.fn_assert_vacancy_edit_allowed_op(text) IS
  'Operation-aware vacancy edit lock enforcement. SA/HA bypass all ops; '
  'Encoder bypasses INSERT only (VCODE creation). Others raise 42501 when locked.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2: Keep existing no-arg wrapper — delegate conservatively to 'UPDATE'
--         so any external direct calls remain safe.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assert_vacancy_edit_allowed()
  RETURNS void
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.fn_assert_vacancy_edit_allowed_op('UPDATE');
END;
$$;

GRANT EXECUTE ON FUNCTION public.assert_vacancy_edit_allowed() TO authenticated;

COMMENT ON FUNCTION public.assert_vacancy_edit_allowed() IS
  'Backward-compatible wrapper — delegates to fn_assert_vacancy_edit_allowed_op(''UPDATE''). '
  'Prefer calling fn_assert_vacancy_edit_allowed_op(TG_OP) from triggers.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 3: Update trigger function to forward TG_OP
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_fn_assert_vacancy_edit_allowed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.fn_assert_vacancy_edit_allowed_op(TG_OP);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_fn_assert_vacancy_edit_allowed() IS
  'Trigger function: enforces vacancy edit lock per operation (INSERT/UPDATE/DELETE).';

-- Note: triggers themselves (trg_assert_vacancy_edit_allowed on vacancies,
-- trg_assert_applicant_edit_allowed on applicants) reference this function by
-- name and do not need to be recreated.

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 4: Update get_vacancy_edit_lock_status() — correct can_edit for HA
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_vacancy_edit_lock_status()
  RETURNS TABLE(
    is_locked         boolean,
    mode              text,
    reason            text,
    locked_by_name    text,
    locked_at         timestamp with time zone,
    can_override      boolean,
    can_edit          boolean,
    schedule_description text
  )
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_manual_locked      boolean;
  v_manual_reason      text;
  v_manual_locked_by   uuid;
  v_manual_by_name     text;
  v_manual_locked_at   timestamp with time zone;

  v_sched_active       boolean;
  v_final_locked       boolean;
  v_final_mode         text;
  v_final_reason       text;
  v_final_by_name      text;
  v_final_at           timestamp with time zone;

  v_role               text;
  v_can_override       boolean;
  v_can_edit           boolean;
BEGIN
  SELECT l.is_locked, l.reason, l.locked_by, up.full_name, l.locked_at
  INTO v_manual_locked, v_manual_reason, v_manual_locked_by, v_manual_by_name, v_manual_locked_at
  FROM public.vacancy_edit_locks l
  LEFT JOIN public.users_profile up ON up.id = l.locked_by
  WHERE l.id = 1;

  v_manual_locked  := COALESCE(v_manual_locked, false);
  v_sched_active   := public.is_scheduled_lock_active();
  v_final_locked   := v_manual_locked OR v_sched_active;

  IF v_manual_locked THEN
    v_final_mode    := 'manual';
    v_final_reason  := COALESCE(v_manual_reason, 'Manual lock active');
    v_final_by_name := COALESCE(v_manual_by_name, 'Unknown Admin');
    v_final_at      := v_manual_locked_at;
  ELSIF v_sched_active THEN
    v_final_mode    := 'scheduled';
    v_final_reason  := 'Weekly scheduled lock window';
    v_final_by_name := 'System';
    v_final_at      := timezone('Asia/Manila',
                         date_trunc('week', timezone('Asia/Manila', now()))
                         + interval '17 hours');
  ELSE
    v_final_mode    := NULL;
    v_final_reason  := NULL;
    v_final_by_name := NULL;
    v_final_at      := NULL;
  END IF;

  v_role         := public.get_effective_role();
  v_can_override := v_role IN ('Super Admin', 'Head Admin');
  -- Head Admin now also has bypass capability; reflect this in can_edit.
  v_can_edit     := NOT v_final_locked OR v_role IN ('Super Admin', 'Head Admin');

  RETURN QUERY SELECT
    v_final_locked,
    v_final_mode,
    v_final_reason,
    v_final_by_name,
    v_final_at,
    v_can_override,
    v_can_edit,
    'Monday 5:00 PM to Tuesday 2:00 PM'::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_vacancy_edit_lock_status() TO authenticated;

COMMENT ON FUNCTION public.get_vacancy_edit_lock_status() IS
  'Returns vacancy edit lock status. can_edit=true for SA and HA even when locked.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Validation queries (run against staging before prod)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- 1. Confirm helper exists with correct signature:
--    SELECT proname, pronargs FROM pg_proc
--    WHERE proname IN ('fn_assert_vacancy_edit_allowed_op',
--                      'assert_vacancy_edit_allowed',
--                      'trg_fn_assert_vacancy_edit_allowed')
--      AND pronamespace = 'public'::regnamespace;
--    Expected: 3 rows; fn_assert_vacancy_edit_allowed_op has pronargs=1.
--
-- 2. Confirm trigger functions on both tables reference the updated body:
--    SELECT tgname, tgrelid::regclass
--    FROM pg_trigger
--    WHERE tgfoid = 'public.trg_fn_assert_vacancy_edit_allowed'::regproc;
--    Expected: trg_assert_vacancy_edit_allowed (vacancies),
--              trg_assert_applicant_edit_allowed (applicants).
--
-- 3. Verify role bypass matrix (requires active lock — run during Mon 17:00–Tue 14:00
--    or after manually locking via lock_vacancy_editing):
--
--    -- As Super Admin:
--    SELECT public.fn_assert_vacancy_edit_allowed_op('INSERT');  -- should return void (no error)
--    SELECT public.fn_assert_vacancy_edit_allowed_op('UPDATE');  -- should return void (no error)
--
--    -- As Head Admin:
--    SELECT public.fn_assert_vacancy_edit_allowed_op('INSERT');  -- should return void (no error)
--    SELECT public.fn_assert_vacancy_edit_allowed_op('UPDATE');  -- should return void (no error)
--
--    -- As Encoder:
--    SELECT public.fn_assert_vacancy_edit_allowed_op('INSERT');  -- should return void (no error)
--    SELECT public.fn_assert_vacancy_edit_allowed_op('UPDATE');  -- should raise 42501
--
--    -- As HRCO / Recruitment / Viewer:
--    SELECT public.fn_assert_vacancy_edit_allowed_op('INSERT');  -- should raise 42501
--
-- 4. Confirm get_vacancy_edit_lock_status() returns can_edit=true for HA when locked:
--    -- As Head Admin while locked:
--    SELECT can_edit FROM public.get_vacancy_edit_lock_status();
--    Expected: true
--
-- 5. Smoke-test full VCODE creation path (staging):
--    -- As Encoder: call approve_vacancy_request_auto_vcodes(<pending_request_id>)
--    -- Expected: succeeds, new vacancy row created, vcode_created populated.
--    -- As Head Admin: same call.
--    -- Expected: succeeds.
