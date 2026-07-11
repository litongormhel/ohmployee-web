-- ============================================================
-- OHM2026_0041 — Vacancy Edit Lock Override Enforcement
-- Migration: 20260608000000_vacancy_edit_lock_override.sql
--
-- Depends on: 20260604000000_vacancy_edit_lock_backend.sql
--
-- Changes:
--   §0  Add override columns to vacancy_edit_locks
--   §1  fn_assert_vacancy_edit_allowed_op(p_op text) — op-aware enforcement
--         SA: bypass all ops (audit logged)
--         HA: bypass all ops (audit logged)
--         Encoder: bypass INSERT only
--         Others: raise 42501 while locked
--   §2  assert_vacancy_edit_allowed() — backward-compat wrapper → delegates to §1
--   §3  Trigger trg_fn_assert_vacancy_edit_allowed — forward TG_OP to §1
--   §4  lock_vacancy_editing — clear override state on manual lock
--   §5  unlock_vacancy_editing — set override flag when scheduled window active
--   §6  get_vacancy_edit_lock_status — add override fields, fix can_edit for HA
--   §7  Grants
-- ============================================================

-- ── §0. Schema: override columns ──────────────────────────────────────────────
ALTER TABLE public.vacancy_edit_locks
  ADD COLUMN IF NOT EXISTS is_override_active boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS override_by uuid REFERENCES public.users_profile(id),
  ADD COLUMN IF NOT EXISTS override_until timestamptz;

-- ── §1. Op-aware enforcement helper ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_vacancy_edit_allowed_op(p_op text)
  RETURNS void
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_is_locked boolean;
  v_role      text;
  v_user_id   uuid;
BEGIN
  v_is_locked := public.is_vacancy_edit_locked();
  IF NOT v_is_locked THEN
    RETURN; -- system is open — allow all
  END IF;

  v_role    := public.get_effective_role();
  v_user_id := public.get_current_profile_id();

  -- Super Admin and Head Admin bypass all operations while locked
  IF v_role IN ('Super Admin', 'Head Admin') THEN
    INSERT INTO public.vacancy_edit_lock_audit (
      action_type, actor_user_id, actor_role, reason, previous_state, new_state
    ) VALUES (
      'override',
      v_user_id,
      v_role,
      v_role || ' mutation bypass during active lock (op=' || p_op || ')',
      NULL,
      NULL
    );
    RETURN;
  END IF;

  -- Encoder bypasses INSERT only (VCODE creation via SECURITY DEFINER RPCs)
  IF v_role = 'Encoder' AND p_op = 'INSERT' THEN
    RETURN;
  END IF;

  -- All other roles / operations blocked
  RAISE EXCEPTION 'Vacancy edits are currently locked. Non-admin edits are prohibited.'
    USING ERRCODE = '42501';
END;
$$;

-- ── §2. Backward-compat wrapper ───────────────────────────────────────────────
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

-- ── §3. Trigger function — forward TG_OP ──────────────────────────────────────
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

-- ── §4. lock_vacancy_editing — clear override state on manual lock ─────────────
CREATE OR REPLACE FUNCTION public.lock_vacancy_editing(p_reason text)
  RETURNS jsonb
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_role      text;
  v_user_id   uuid;
  v_old_state jsonb;
  v_new_state jsonb;
BEGIN
  v_role := public.get_effective_role();
  IF v_role NOT IN ('Super Admin', 'Head Admin') THEN
    RAISE EXCEPTION 'Access Denied: Head Admin or Super Admin only' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason is required for manual lock' USING ERRCODE = '22000';
  END IF;

  v_user_id := public.get_current_profile_id();

  SELECT to_jsonb(l.*) INTO v_old_state
  FROM public.vacancy_edit_locks l WHERE l.id = 1;

  UPDATE public.vacancy_edit_locks
  SET is_locked         = true,
      lock_mode         = 'manual',
      is_override_active = false,
      override_by       = NULL,
      override_until    = NULL,
      reason            = p_reason,
      locked_by         = v_user_id,
      locked_at         = now(),
      unlocked_by       = NULL,
      unlocked_at       = NULL,
      updated_at        = now()
  WHERE id = 1;

  SELECT to_jsonb(l.*) INTO v_new_state
  FROM public.vacancy_edit_locks l WHERE l.id = 1;

  INSERT INTO public.vacancy_edit_lock_audit (
    action_type, actor_user_id, actor_role, reason, previous_state, new_state
  ) VALUES ('lock', v_user_id, v_role, p_reason, v_old_state, v_new_state);

  RETURN jsonb_build_object('success', true, 'is_locked', true, 'locked_at', now());
END;
$$;

-- ── §5. unlock_vacancy_editing — override flag when scheduled window active ─────
CREATE OR REPLACE FUNCTION public.unlock_vacancy_editing(p_reason text)
  RETURNS jsonb
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_role        text;
  v_user_id     uuid;
  v_sched       boolean;
  v_old_state   jsonb;
  v_new_state   jsonb;
  v_action_type text;
BEGIN
  v_role := public.get_effective_role();
  IF v_role NOT IN ('Super Admin', 'Head Admin') THEN
    RAISE EXCEPTION 'Access Denied: Head Admin or Super Admin only' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason is required for manual unlock' USING ERRCODE = '22000';
  END IF;

  v_user_id := public.get_current_profile_id();
  v_sched   := public.is_scheduled_lock_active();

  SELECT to_jsonb(l.*) INTO v_old_state
  FROM public.vacancy_edit_locks l WHERE l.id = 1;

  IF v_sched THEN
    -- Scheduled window is active: record as an explicit admin override.
    -- is_locked stays false; non-admin users remain blocked by the scheduled
    -- lock; SA/HA bypass it via fn_assert_vacancy_edit_allowed_op.
    v_action_type := 'override';
    UPDATE public.vacancy_edit_locks
    SET is_locked          = false,
        is_override_active = true,
        override_by        = v_user_id,
        override_until     = NULL,   -- active until next manual lock or window end
        reason             = p_reason,
        unlocked_by        = v_user_id,
        unlocked_at        = now(),
        updated_at         = now()
    WHERE id = 1;
  ELSE
    -- Normal unlock outside scheduled window
    v_action_type := 'unlock';
    UPDATE public.vacancy_edit_locks
    SET is_locked          = false,
        is_override_active = false,
        override_by        = NULL,
        override_until     = NULL,
        reason             = p_reason,
        unlocked_by        = v_user_id,
        unlocked_at        = now(),
        updated_at         = now()
    WHERE id = 1;
  END IF;

  SELECT to_jsonb(l.*) INTO v_new_state
  FROM public.vacancy_edit_locks l WHERE l.id = 1;

  INSERT INTO public.vacancy_edit_lock_audit (
    action_type, actor_user_id, actor_role, reason, previous_state, new_state
  ) VALUES (v_action_type, v_user_id, v_role, p_reason, v_old_state, v_new_state);

  RETURN jsonb_build_object(
    'success',           true,
    'is_locked',         false,
    'is_override_active', v_sched,
    'unlocked_at',       now()
  );
END;
$$;

-- ── §6. get_vacancy_edit_lock_status — extended return shape ──────────────────
-- Drop the existing function first because the RETURNS TABLE definition changes.
DROP FUNCTION IF EXISTS public.get_vacancy_edit_lock_status();

CREATE FUNCTION public.get_vacancy_edit_lock_status()
  RETURNS TABLE(
    is_locked         boolean,
    mode              text,
    reason            text,
    locked_by_name    text,
    locked_at         timestamp with time zone,
    can_override      boolean,
    can_edit          boolean,
    schedule_description text,
    is_override_active boolean,
    override_by_name  text,
    override_until    timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_manual_locked    boolean;
  v_manual_reason    text;
  v_manual_locked_by uuid;
  v_manual_locked_by_name text;
  v_manual_locked_at timestamp with time zone;
  v_override_stored  boolean;
  v_override_by_id   uuid;
  v_override_by_name text;
  v_override_until   timestamp with time zone;

  v_sched_active  boolean;
  v_final_locked  boolean;
  v_final_mode    text;
  v_final_reason  text;
  v_final_by_name text;
  v_final_at      timestamp with time zone;

  v_override_effective boolean;
  v_role        text;
  v_can_override boolean;
  v_can_edit    boolean;
BEGIN
  -- Read lock state
  SELECT l.is_locked, l.reason, l.locked_by, up.full_name, l.locked_at,
         l.is_override_active, l.override_by, l.override_until
  INTO   v_manual_locked, v_manual_reason, v_manual_locked_by,
         v_manual_locked_by_name, v_manual_locked_at,
         v_override_stored, v_override_by_id, v_override_until
  FROM public.vacancy_edit_locks l
  LEFT JOIN public.users_profile up ON up.id = l.locked_by
  WHERE l.id = 1;

  v_manual_locked  := COALESCE(v_manual_locked, false);
  v_override_stored := COALESCE(v_override_stored, false);
  v_sched_active   := public.is_scheduled_lock_active();
  v_final_locked   := v_manual_locked OR v_sched_active;

  -- Override is effective when: stored AND scheduled window active AND no manual lock on top
  v_override_effective := v_override_stored AND v_sched_active AND NOT v_manual_locked;

  -- Resolve locked-by name for override
  IF v_override_stored AND v_override_by_id IS NOT NULL THEN
    SELECT full_name INTO v_override_by_name
    FROM public.users_profile
    WHERE id = v_override_by_id;
  END IF;

  -- Resolve mode/reason/by/at
  IF v_manual_locked THEN
    v_final_mode    := 'manual';
    v_final_reason  := COALESCE(v_manual_reason, 'Manual lock active');
    v_final_by_name := COALESCE(v_manual_locked_by_name, 'Unknown Admin');
    v_final_at      := v_manual_locked_at;
  ELSIF v_override_effective THEN
    v_final_mode    := 'override';
    v_final_reason  := COALESCE(v_manual_reason, 'Admin override during scheduled lock');
    v_final_by_name := 'System (Scheduled)';
    v_final_at      := timezone('Asia/Manila',
                         date_trunc('week', timezone('Asia/Manila', now()))
                         + interval '17 hours');
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

  -- Caller permissions
  v_role         := public.get_effective_role();
  v_can_override := v_role IN ('Super Admin', 'Head Admin');
  -- SA and HA can always edit (they bypass the lock in the enforcement function)
  v_can_edit     := NOT v_final_locked OR v_role IN ('Super Admin', 'Head Admin');

  RETURN QUERY SELECT
    v_final_locked                  AS is_locked,
    v_final_mode                    AS mode,
    v_final_reason                  AS reason,
    v_final_by_name                 AS locked_by_name,
    v_final_at                      AS locked_at,
    v_can_override                  AS can_override,
    v_can_edit                      AS can_edit,
    'Monday 5:00 PM to Tuesday 2:00 PM'::text AS schedule_description,
    v_override_effective            AS is_override_active,
    v_override_by_name              AS override_by_name,
    v_override_until                AS override_until;
END;
$$;

-- ── §7. Grants ─────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.fn_assert_vacancy_edit_allowed_op(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_vacancy_edit_lock_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.lock_vacancy_editing(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unlock_vacancy_editing(text) TO authenticated;
