-- ============================================================
-- OHM2026_1068 — Persistent Vacancy Edit Lock Backend Enforcement
-- Migration:  20260604000000_vacancy_edit_lock_backend.sql
-- ============================================================

-- ── §1. Persistent Lock State Table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.vacancy_edit_locks (
  id integer PRIMARY KEY DEFAULT 1 CONSTRAINT single_row CHECK (id = 1),
  is_locked boolean NOT NULL DEFAULT false,
  lock_mode text NOT NULL DEFAULT 'scheduled' CONSTRAINT chk_lock_mode CHECK (lock_mode IN ('manual', 'scheduled')),
  reason text,
  locked_by uuid REFERENCES public.users_profile(id),
  locked_at timestamp with time zone,
  unlocked_by uuid REFERENCES public.users_profile(id),
  unlocked_at timestamp with time zone,
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Seed initial row if not exists
INSERT INTO public.vacancy_edit_locks (id, is_locked, lock_mode, reason)
VALUES (1, false, 'scheduled', 'Initial state')
ON CONFLICT (id) DO NOTHING;

-- ── §2. Persistent Lock Audit / History Table ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.vacancy_edit_lock_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action_type text NOT NULL CONSTRAINT chk_action_type CHECK (action_type IN ('lock', 'unlock', 'override')),
  actor_user_id uuid REFERENCES public.users_profile(id),
  actor_role text,
  reason text,
  previous_state jsonb,
  new_state jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- ── §3. Time & Lock Helpers ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_scheduled_lock_active()
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_now_pht timestamp;
  v_dow int;
  v_time time;
BEGIN
  v_now_pht := timezone('Asia/Manila', now());
  v_dow := EXTRACT(ISODOW FROM v_now_pht); -- Monday is 1, Tuesday is 2
  v_time := v_now_pht::time;

  RETURN (v_dow = 1 AND v_time >= '17:00:00') OR (v_dow = 2 AND v_time < '14:00:00');
END;
$$;

CREATE OR REPLACE FUNCTION public.is_vacancy_edit_locked()
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_manual_locked boolean;
BEGIN
  SELECT is_locked INTO v_manual_locked
  FROM public.vacancy_edit_locks
  WHERE id = 1;

  RETURN COALESCE(v_manual_locked, false) OR public.is_scheduled_lock_active();
END;
$$;

-- ── §4. Central Enforcement helper ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assert_vacancy_edit_allowed()
  RETURNS void
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_is_locked boolean;
  v_role text;
  v_user_id uuid;
BEGIN
  v_is_locked := public.is_vacancy_edit_locked();
  IF v_is_locked THEN
    v_role := public.get_effective_role();
    v_user_id := public.get_current_profile_id();

    IF v_role = 'Super Admin' THEN
      -- Log the override action for audit-ready compliance
      INSERT INTO public.vacancy_edit_lock_audit (
        action_type,
        actor_user_id,
        actor_role,
        reason,
        previous_state,
        new_state
      ) VALUES (
        'override',
        v_user_id,
        v_role,
        'Super Admin vacancy mutation bypass during active lock',
        NULL,
        NULL
      );
      RETURN;
    ELSE
      RAISE EXCEPTION 'Vacancy edits are currently locked (Active Lock Mode). Non-Super Admin edits are prohibited.' USING ERRCODE = '42501';
    END IF;
  END IF;
END;
$$;

-- ── §5. Frontend & Admin RPCs ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_vacancy_edit_lock_status()
  RETURNS TABLE(
    is_locked boolean,
    mode text,
    reason text,
    locked_by_name text,
    locked_at timestamp with time zone,
    can_override boolean,
    can_edit boolean,
    schedule_description text
  )
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_manual_locked boolean;
  v_manual_reason text;
  v_manual_locked_by uuid;
  v_manual_locked_by_name text;
  v_manual_locked_at timestamp with time zone;
  
  v_sched_active boolean;
  v_final_locked boolean;
  v_final_mode text;
  v_final_reason text;
  v_final_by_name text;
  v_final_at timestamp with time zone;
  
  v_role text;
  v_can_override boolean;
  v_can_edit boolean;
BEGIN
  -- Get manual lock details
  SELECT l.is_locked, l.reason, l.locked_by, up.full_name, l.locked_at
  INTO v_manual_locked, v_manual_reason, v_manual_locked_by, v_manual_locked_by_name, v_manual_locked_at
  FROM public.vacancy_edit_locks l
  LEFT JOIN public.users_profile up ON up.id = l.locked_by
  WHERE l.id = 1;
  
  v_manual_locked := COALESCE(v_manual_locked, false);
  v_sched_active := public.is_scheduled_lock_active();
  v_final_locked := v_manual_locked OR v_sched_active;
  
  -- Resolve final mode, reason, locked_by, locked_at
  IF v_manual_locked THEN
    v_final_mode := 'manual';
    v_final_reason := COALESCE(v_manual_reason, 'Manual lock active');
    v_final_by_name := COALESCE(v_manual_locked_by_name, 'Unknown Admin');
    v_final_at := v_manual_locked_at;
  ELSIF v_sched_active THEN
    v_final_mode := 'scheduled';
    v_final_reason := 'Weekly scheduled lock window';
    v_final_by_name := 'System';
    -- Calculate start of current week's Monday 5:00 PM in Asia/Manila
    v_final_at := timezone('Asia/Manila', (date_trunc('week', timezone('Asia/Manila', now())) + interval '17 hours'));
  ELSE
    v_final_mode := NULL;
    v_final_reason := NULL;
    v_final_by_name := NULL;
    v_final_at := NULL;
  END IF;
  
  -- Permissions
  v_role := public.get_effective_role();
  v_can_override := v_role IN ('Super Admin', 'Head Admin');
  v_can_edit := NOT v_final_locked OR (v_role = 'Super Admin');
  
  RETURN QUERY SELECT
    v_final_locked AS is_locked,
    v_final_mode AS mode,
    v_final_reason AS reason,
    v_final_by_name AS locked_by_name,
    v_final_at AS locked_at,
    v_can_override AS can_override,
    v_can_edit AS can_edit,
    'Monday 5:00 PM to Tuesday 2:00 PM'::text AS schedule_description;
END;
$$;

CREATE OR REPLACE FUNCTION public.lock_vacancy_editing(p_reason text)
  RETURNS jsonb
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_role text;
  v_user_id uuid;
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
  FROM public.vacancy_edit_locks l
  WHERE l.id = 1;

  UPDATE public.vacancy_edit_locks
  SET is_locked = true,
      lock_mode = 'manual',
      reason = p_reason,
      locked_by = v_user_id,
      locked_at = now(),
      unlocked_by = NULL,
      unlocked_at = NULL,
      updated_at = now()
  WHERE id = 1;

  SELECT to_jsonb(l.*) INTO v_new_state
  FROM public.vacancy_edit_locks l
  WHERE l.id = 1;

  INSERT INTO public.vacancy_edit_lock_audit (
    action_type,
    actor_user_id,
    actor_role,
    reason,
    previous_state,
    new_state
  ) VALUES (
    'lock',
    v_user_id,
    v_role,
    p_reason,
    v_old_state,
    v_new_state
  );

  RETURN jsonb_build_object(
    'success', true,
    'is_locked', true,
    'locked_at', now()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.unlock_vacancy_editing(p_reason text)
  RETURNS jsonb
  LANGUAGE plpgsql
  VOLATILE SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_role text;
  v_user_id uuid;
  v_old_state jsonb;
  v_new_state jsonb;
BEGIN
  v_role := public.get_effective_role();
  IF v_role NOT IN ('Super Admin', 'Head Admin') THEN
    RAISE EXCEPTION 'Access Denied: Head Admin or Super Admin only' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason is required for manual unlock' USING ERRCODE = '22000';
  END IF;

  v_user_id := public.get_current_profile_id();

  SELECT to_jsonb(l.*) INTO v_old_state
  FROM public.vacancy_edit_locks l
  WHERE l.id = 1;

  UPDATE public.vacancy_edit_locks
  SET is_locked = false,
      unlocked_by = v_user_id,
      unlocked_at = now(),
      reason = p_reason,
      updated_at = now()
  WHERE id = 1;

  SELECT to_jsonb(l.*) INTO v_new_state
  FROM public.vacancy_edit_locks l
  WHERE l.id = 1;

  INSERT INTO public.vacancy_edit_lock_audit (
    action_type,
    actor_user_id,
    actor_role,
    reason,
    previous_state,
    new_state
  ) VALUES (
    'unlock',
    v_user_id,
    v_role,
    p_reason,
    v_old_state,
    v_new_state
  );

  RETURN jsonb_build_object(
    'success', true,
    'is_locked', false,
    'unlocked_at', now()
  );
END;
$$;

-- ── §6. Table Mutation Triggers ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_fn_assert_vacancy_edit_allowed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.assert_vacancy_edit_allowed();
  
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assert_vacancy_edit_allowed ON public.vacancies;
CREATE TRIGGER trg_assert_vacancy_edit_allowed
  BEFORE INSERT OR UPDATE OR DELETE ON public.vacancies
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_assert_vacancy_edit_allowed();

DROP TRIGGER IF EXISTS trg_assert_applicant_edit_allowed ON public.applicants;
CREATE TRIGGER trg_assert_applicant_edit_allowed
  BEFORE INSERT OR UPDATE OR DELETE ON public.applicants
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_assert_vacancy_edit_allowed();

-- ── §7. RLS Least-Privilege Policies ─────────────────────────────────────────
ALTER TABLE public.vacancy_edit_locks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vacancy_edit_lock_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated read on vacancy_edit_locks" ON public.vacancy_edit_locks;
CREATE POLICY "Allow authenticated read on vacancy_edit_locks"
  ON public.vacancy_edit_locks
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Allow SA and HA to read vacancy_edit_lock_audit" ON public.vacancy_edit_lock_audit;
CREATE POLICY "Allow SA and HA to read vacancy_edit_lock_audit"
  ON public.vacancy_edit_lock_audit
  FOR SELECT
  TO authenticated
  USING (public.get_my_role() IN ('Super Admin', 'Head Admin'));

-- Grant execute rights
GRANT EXECUTE ON FUNCTION public.get_vacancy_edit_lock_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.lock_vacancy_editing(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unlock_vacancy_editing(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_vacancy_edit_locked() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_scheduled_lock_active() TO authenticated;
