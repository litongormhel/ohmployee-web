-- ─────────────────────────────────────────────────────────────────────────────
-- OHM's Safespace: Freeze Modes Architecture (Phase 2)
-- Migration: 20260711000000_safespace_freeze_modes.sql
-- Seeds freeze controls, secures reading/updating, and prepares resolver helpers.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Seed Freeze Controls ───────────────────────────────────────────────────
-- Freeze modes are inactive (enabled = false) by default.
INSERT INTO public.governance_controls (control_key, enabled)
VALUES
  ('payroll_freeze', false),
  ('audit_freeze', false),
  ('recruitment_freeze', false),
  ('read_only_emergency', false)
ON CONFLICT (control_key) DO NOTHING;

-- ── 2. RPC public.fn_get_freeze_modes ──────────────────────────────────────────
-- Super Admin-only read of freeze controls and their last transition states.
CREATE OR REPLACE FUNCTION public.fn_get_freeze_modes()
RETURNS TABLE(
  control_key     text,
  enabled         boolean,
  updated_at      timestamptz,
  reason          text,
  updated_by_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level int;
BEGIN
  -- Enforce superAdmin-only caller
  SELECT r.role_level INTO v_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_get_freeze_modes requires superAdmin.';
  END IF;

  RETURN QUERY
  SELECT
    gc.control_key,
    gc.enabled,
    gc.updated_at,
    gc.reason,
    up.full_name AS updated_by_name
  FROM public.governance_controls gc
  LEFT JOIN public.users_profile up ON up.id = gc.updated_by
  WHERE gc.control_key IN ('payroll_freeze', 'audit_freeze', 'recruitment_freeze', 'read_only_emergency')
  ORDER BY gc.control_key;
END;
$$;

-- ── 3. RPC public.fn_update_freeze_mode ────────────────────────────────────────
-- Atomically toggles freeze controls and logs entries to audit trail.
-- Validates role checks, key guards, actor spoof prevention, and reason requirement.
CREATE OR REPLACE FUNCTION public.fn_update_freeze_mode(
  p_control_key text,
  p_enabled     boolean,
  p_reason      text,
  p_actor_id    uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before     boolean;
  v_level      int;
  v_actor_auth uuid;
BEGIN
  -- Enforce superAdmin-only caller role check
  SELECT r.role_level, up.auth_user_id INTO v_level, v_actor_auth
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.id = p_actor_id;

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_update_freeze_mode requires superAdmin.';
  END IF;

  -- Spoof guard: ensure actor corresponds to the authenticated database user
  IF v_actor_auth IS NULL OR v_actor_auth <> auth.uid() THEN
    RAISE EXCEPTION 'Access denied: Actor ID does not match authenticated user.';
  END IF;

  -- Key guard: restrict modification to freeze keys only
  IF p_control_key NOT IN ('payroll_freeze', 'audit_freeze', 'recruitment_freeze', 'read_only_emergency') THEN
    RAISE EXCEPTION 'Invalid freeze mode key: %', p_control_key;
  END IF;

  -- Mandatory reason verification
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A non-empty reason is required to activate or deactivate a freeze mode.';
  END IF;

  -- Read prior value for audit logging
  SELECT gc.enabled INTO v_before
  FROM public.governance_controls gc
  WHERE gc.control_key = p_control_key;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown governance control: %', p_control_key;
  END IF;

  -- Apply update atomically
  UPDATE public.governance_controls
  SET
    enabled    = p_enabled,
    updated_by = p_actor_id,
    updated_at = now(),
    reason     = trim(p_reason)
  WHERE control_key = p_control_key;

  -- Write append-only governance audit log entry
  INSERT INTO public.governance_audit_log (
    control_key,
    action,
    before_value,
    after_value,
    changed_by,
    reason
  ) VALUES (
    p_control_key,
    CASE WHEN p_enabled THEN 'freeze_activate' ELSE 'freeze_deactivate' END,
    jsonb_build_object('enabled', v_before),
    jsonb_build_object('enabled', p_enabled),
    p_actor_id,
    trim(p_reason)
  );
END;
$$;

-- ── 4. Future Enforcement Helper/Resolver Functions ──────────────────────────────
-- Prepares public.fn_check_freeze_active and public.fn_assert_freeze_inactive.

-- Resolver function: Returns true if the specific freeze mode or global read-only mode is active.
CREATE OR REPLACE FUNCTION public.fn_check_freeze_active(p_freeze_key text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate key
  IF p_freeze_key NOT IN ('payroll_freeze', 'audit_freeze', 'recruitment_freeze', 'read_only_emergency') THEN
    RAISE EXCEPTION 'Invalid freeze mode key: %', p_freeze_key;
  END IF;

  -- If read_only_emergency is enabled (true), it overrides everything and returns true (freeze is active)
  IF COALESCE((SELECT enabled FROM public.governance_controls WHERE control_key = 'read_only_emergency'), false) THEN
    RETURN true;
  END IF;

  -- Otherwise check specific key state
  RETURN COALESCE((SELECT enabled FROM public.governance_controls WHERE control_key = p_freeze_key), false);
END;
$$;

-- Assertion function: Raises P0001 with clear message if freeze is active. Called in gated RPCs.
CREATE OR REPLACE FUNCTION public.fn_assert_freeze_inactive(p_freeze_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.fn_check_freeze_active(p_freeze_key) THEN
    IF public.fn_check_freeze_active('read_only_emergency') THEN
      RAISE EXCEPTION 'System is in Read-Only Emergency Mode. Operations are temporarily suspended.'
        USING ERRCODE = 'P0001';
    ELSE
      RAISE EXCEPTION 'This operation is suspended due to an active %.', replace(p_freeze_key, '_', ' ')
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
END;
$$;

-- ── 5. Revoke and Grant Permissions ──────────────────────────────────────────
-- Strictly lock execution privileges so they cannot be accessed by public or anonymous roles.

REVOKE ALL ON FUNCTION public.fn_get_freeze_modes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_freeze_modes() TO authenticated;

REVOKE ALL ON FUNCTION public.fn_update_freeze_mode(text, boolean, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_update_freeze_mode(text, boolean, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_check_freeze_active(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_check_freeze_active(text) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_assert_freeze_inactive(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_assert_freeze_inactive(text) TO authenticated;

-- Comments for documentation
COMMENT ON FUNCTION public.fn_get_freeze_modes() IS
  'OHM2026_0044: Fetches all operational freeze modes with metadata. Restricted to Super Admin.';
COMMENT ON FUNCTION public.fn_update_freeze_mode(text, boolean, text, uuid) IS
  'OHM2026_0044: Atomically toggles freeze controls and logs audits. Restricted to Super Admin.';
COMMENT ON FUNCTION public.fn_check_freeze_active(text) IS
  'OHM2026_0044: Helper to verify if a freeze is active, with read-only emergency overriding all.';
COMMENT ON FUNCTION public.fn_assert_freeze_inactive(text) IS
  'OHM2026_0044: Assertion function raising P0001 if a freeze is active. Prepared for future gate enforcement.';
