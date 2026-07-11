-- ============================================================
-- OHM2026_0044 — Fix Enforcement Function Override Bypass
-- Migration: 20260830000003_fix_enforcement_fn_override_bypass.sql
--
-- Depends on: 20260830000000_vacancy_edit_lock_override.sql
--
-- Root Cause:
--   The committed version of 20260830000000 updated get_vacancy_edit_lock_status
--   and unlock_vacancy_editing to populate is_override_active=true in the lock
--   table, but did NOT update fn_assert_vacancy_edit_allowed_op to read and
--   respect that flag. The mutation trigger therefore continued to raise 42501
--   for HRCO / Recruitment / OM even when Override Active was displayed in the UI.
--
-- Fix:
--   §1  fn_assert_vacancy_edit_allowed_op — add is_override_active bypass BEFORE
--       the role-based block. When is_override_active=true the lock enforcement
--       is skipped entirely; normal Vacancy RBAC (RLS + RPC guards) applies.
--   §2  get_vacancy_edit_lock_status — correct can_edit to include
--       v_override_effective so non-SA/HA roles get can_edit=true in the UI
--       during an active override. Supersedes 20260830000001 and 20260830000002.
--   §3  Grants
--
-- Acceptance:
--   Override Active:
--     HRCO     → INSERT into applicants succeeds (trigger bypassed)
--     Recrmnt  → INSERT into applicants succeeds (trigger bypassed)
--     Encoder  → INSERT into applicants succeeds (trigger bypassed)
--     Viewer   → blocked by normal RLS / RPC RBAC (not by the lock)
--   After Lock Now (manual lock):
--     HRCO     → 42501 raised again (is_override_active cleared to false)
-- ============================================================

-- ── §1. Enforcement helper — add is_override_active bypass ────────────────────
CREATE OR REPLACE FUNCTION public.fn_assert_vacancy_edit_allowed_op(p_op text)
  RETURNS void
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_is_locked       boolean;
  v_override_active boolean;
  v_role            text;
  v_user_id         uuid;
BEGIN
  v_is_locked := public.is_vacancy_edit_locked();
  IF NOT v_is_locked THEN
    RETURN; -- system is fully open — allow all
  END IF;

  -- When an admin override is active the scheduled lock window is lifted for
  -- ALL roles. Normal Vacancy RBAC (RLS + mutating RPC guards) remains the only
  -- gate. The lock itself must not be the barrier.
  SELECT COALESCE(l.is_override_active, false)
  INTO   v_override_active
  FROM   public.vacancy_edit_locks l
  WHERE  l.id = 1;

  IF v_override_active THEN
    RETURN; -- override active: lock enforcement bypassed, normal RBAC applies
  END IF;

  -- Lock is active and no override — apply role-based rules.
  v_role    := public.get_effective_role();
  v_user_id := public.get_current_profile_id();

  -- Super Admin and Head Admin bypass all operations (audit logged).
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

  -- Encoder bypasses INSERT only (VCODE creation via SECURITY DEFINER RPCs).
  IF v_role = 'Encoder' AND p_op = 'INSERT' THEN
    RETURN;
  END IF;

  -- All other roles / operations are blocked while locked.
  RAISE EXCEPTION 'Vacancy edits are currently locked. Non-admin edits are prohibited.'
    USING ERRCODE = '42501';
END;
$$;

-- ── §2. get_vacancy_edit_lock_status — correct can_edit for override ──────────
-- Supersedes 20260830000001 and 20260830000002 (identical, only touched status RPC).
DROP FUNCTION IF EXISTS public.get_vacancy_edit_lock_status();

CREATE FUNCTION public.get_vacancy_edit_lock_status()
  RETURNS TABLE(
    is_locked          boolean,
    mode               text,
    reason             text,
    locked_by_name     text,
    locked_at          timestamp with time zone,
    can_override       boolean,
    can_edit           boolean,
    schedule_description text,
    is_override_active boolean,
    override_by_name   text,
    override_until     timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_manual_locked         boolean;
  v_manual_reason         text;
  v_manual_locked_by      uuid;
  v_manual_locked_by_name text;
  v_manual_locked_at      timestamp with time zone;
  v_override_stored       boolean;
  v_override_by_id        uuid;
  v_override_by_name      text;
  v_override_until        timestamp with time zone;

  v_sched_active       boolean;
  v_final_locked       boolean;
  v_final_mode         text;
  v_final_reason       text;
  v_final_by_name      text;
  v_final_at           timestamp with time zone;

  v_override_effective boolean;
  v_role               text;
  v_can_override       boolean;
  v_can_edit           boolean;
BEGIN
  SELECT l.is_locked, l.reason, l.locked_by, up.full_name, l.locked_at,
         l.is_override_active, l.override_by, l.override_until
  INTO   v_manual_locked, v_manual_reason, v_manual_locked_by,
         v_manual_locked_by_name, v_manual_locked_at,
         v_override_stored, v_override_by_id, v_override_until
  FROM public.vacancy_edit_locks l
  LEFT JOIN public.users_profile up ON up.id = l.locked_by
  WHERE l.id = 1;

  v_manual_locked   := COALESCE(v_manual_locked, false);
  v_override_stored := COALESCE(v_override_stored, false);
  v_sched_active    := public.is_scheduled_lock_active();
  v_final_locked    := v_manual_locked OR v_sched_active;

  -- Override is effective when: stored flag set AND scheduled window still active
  -- AND no manual lock placed on top (lock_vacancy_editing clears the override).
  v_override_effective := v_override_stored AND v_sched_active AND NOT v_manual_locked;

  IF v_override_stored AND v_override_by_id IS NOT NULL THEN
    SELECT full_name INTO v_override_by_name
    FROM public.users_profile
    WHERE id = v_override_by_id;
  END IF;

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

  v_role         := public.get_effective_role();
  v_can_override := v_role IN ('Super Admin', 'Head Admin');

  -- can_edit = true when:
  --   (a) system fully unlocked (no manual lock, no scheduled window), OR
  --   (b) override is effective — lock bypassed for ALL roles, normal RBAC gates, OR
  --   (c) caller is SA/HA — always bypass regardless of lock state.
  -- Do NOT conflate can_override with can_edit.
  v_can_edit := NOT v_final_locked
                OR v_override_effective
                OR v_role IN ('Super Admin', 'Head Admin');

  RETURN QUERY SELECT
    v_final_locked                         AS is_locked,
    v_final_mode                           AS mode,
    v_final_reason                         AS reason,
    v_final_by_name                        AS locked_by_name,
    v_final_at                             AS locked_at,
    v_can_override                         AS can_override,
    v_can_edit                             AS can_edit,
    'Monday 5:00 PM to Tuesday 2:00 PM'::text AS schedule_description,
    v_override_effective                   AS is_override_active,
    v_override_by_name                     AS override_by_name,
    v_override_until                       AS override_until;
END;
$$;

-- ── §3. Grants ─────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.fn_assert_vacancy_edit_allowed_op(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_vacancy_edit_lock_status() TO authenticated;
