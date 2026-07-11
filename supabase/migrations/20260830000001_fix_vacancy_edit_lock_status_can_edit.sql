-- ============================================================
-- OHM2026_0042-FIX — Correct can_edit in get_vacancy_edit_lock_status
-- Migration: 20260830000001_fix_vacancy_edit_lock_status_can_edit.sql
--
-- Bug: can_edit was computed without checking v_override_effective,
--      so non-SA/HA roles got can_edit=false even when is_override_active=true.
--
-- Fix: can_edit = true when:
--   (a) system is fully unlocked, OR
--   (b) override is effective (lock bypassed for all roles; normal RBAC applies), OR
--   (c) caller is Super Admin or Head Admin (always bypass)
--
-- fn_assert_vacancy_edit_allowed_op is NOT changed — it already returns early
-- when is_override_active=true, leaving normal RLS/RBAC as the only gate.
-- ============================================================

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
  -- AND no manual lock was placed on top (manual lock clears the override).
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

  -- FIX: include v_override_effective so non-SA/HA roles get can_edit=true
  -- during an active override.  The lock itself is the only thing being bypassed;
  -- normal RLS policies on the vacancies table remain the actual permission gate.
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

GRANT EXECUTE ON FUNCTION public.get_vacancy_edit_lock_status() TO authenticated;
