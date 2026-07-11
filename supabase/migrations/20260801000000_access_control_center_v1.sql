-- ============================================================================
-- OHM2026_3001 — Access Control Center V1 (Module Visibility Overrides Only)
-- ============================================================================
-- PURPOSE:
--   Introduce a controlled, Super-Admin-only override layer for MODULE
--   NAVIGATION VISIBILITY only. This is NOT a replacement for existing RBAC.
--   Existing RLS, RPC authorization, workflow transitions, approvals, and data
--   scope remain the single source of truth and are NOT touched here.
--
-- RESOLUTION ORDER (enforced in the client nav layer, data provided here):
--     1. User Override  (allow | deny)
--     2. Role Default   (existing RBAC getter)
--     3. Deny
--   "Inherit" == no override row exists (row absence). Restore Default DELETEs
--   the row, returning the user to their role default. No role mutation occurs.
--
-- PHASE 1 PERMISSION KEYS (visibility only):
--   cencom.view, vacancy.view, hr_emploc.view, plantilla.view,
--   reports.view, user_management.view, imports.view, security.view
--
-- SECURITY:
--   - Reuses public.is_super_admin(), public.get_my_profile_id().
--   - All mutations go through a Super-Admin-gated SECURITY DEFINER RPC that
--     always writes an audit row (changed_by, target_user, permission_key,
--     previous_value, new_value, reason, created_at).
--   - A user may read ONLY their own overrides (for nav resolution); Super
--     Admin may read all overrides and the full audit history.
--
-- ADDITIVE: No DROP of existing objects, no CASCADE, no column-type change.
-- ============================================================================

BEGIN;

-- ── Canonical Phase 1 permission key set ──────────────────────────────────────
-- Centralised so the CHECK constraint and the RPC validation agree.
CREATE OR REPLACE FUNCTION public.acc_v1_module_keys()
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
AS $function$
  SELECT ARRAY[
    'cencom.view',
    'vacancy.view',
    'hr_emploc.view',
    'plantilla.view',
    'reports.view',
    'user_management.view',
    'imports.view',
    'security.view'
  ];
$function$;

-- ── Table: module_visibility_overrides ────────────────────────────────────────
-- One row per (user, permission_key) that has an active override. Absence of a
-- row == Inherit. override_state is constrained to allow|deny only; inherit is
-- never persisted (it is represented by deleting the row).
CREATE TABLE IF NOT EXISTS public.module_visibility_overrides (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.users_profile(id) ON DELETE CASCADE,
  permission_key text NOT NULL,
  override_state text NOT NULL,
  reason         text NOT NULL,
  created_by     uuid REFERENCES public.users_profile(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT module_visibility_overrides_state_chk
    CHECK (override_state IN ('allow', 'deny')),
  CONSTRAINT module_visibility_overrides_key_chk
    CHECK (permission_key = ANY (public.acc_v1_module_keys())),
  CONSTRAINT module_visibility_overrides_unique
    UNIQUE (user_id, permission_key)
);

CREATE INDEX IF NOT EXISTS idx_module_visibility_overrides_user
  ON public.module_visibility_overrides (user_id);

COMMENT ON TABLE public.module_visibility_overrides IS
  'OHM2026_3001 ACC V1: per-user module navigation visibility overrides (allow/deny). Row absence = inherit role default. Visibility only — does not affect RLS/RPC/workflow.';

-- ── Table: module_visibility_override_audit ──────────────────────────────────
-- Append-only history of every override change (including Restore Default).
CREATE TABLE IF NOT EXISTS public.module_visibility_override_audit (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  changed_by     uuid REFERENCES public.users_profile(id),
  target_user    uuid NOT NULL REFERENCES public.users_profile(id) ON DELETE CASCADE,
  permission_key text NOT NULL,
  previous_value text NOT NULL,
  new_value      text NOT NULL,
  reason         text NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_module_visibility_override_audit_target
  ON public.module_visibility_override_audit (target_user, created_at DESC);

COMMENT ON TABLE public.module_visibility_override_audit IS
  'OHM2026_3001 ACC V1: append-only audit of module visibility override changes.';

-- ── Row Level Security ────────────────────────────────────────────────────────
ALTER TABLE public.module_visibility_overrides       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.module_visibility_override_audit  ENABLE ROW LEVEL SECURITY;

-- overrides: a user may read their OWN overrides (for nav resolution); Super
-- Admin may read all. Writes are restricted to Super Admin (normally performed
-- through the SECURITY DEFINER RPC below).
DROP POLICY IF EXISTS module_visibility_overrides_select ON public.module_visibility_overrides;
CREATE POLICY module_visibility_overrides_select
  ON public.module_visibility_overrides
  FOR SELECT
  USING (user_id = public.get_my_profile_id() OR public.is_super_admin());

DROP POLICY IF EXISTS module_visibility_overrides_write ON public.module_visibility_overrides;
CREATE POLICY module_visibility_overrides_write
  ON public.module_visibility_overrides
  FOR ALL
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

-- audit: Super Admin read-only. Inserts happen via SECURITY DEFINER RPC.
DROP POLICY IF EXISTS module_visibility_override_audit_select ON public.module_visibility_override_audit;
CREATE POLICY module_visibility_override_audit_select
  ON public.module_visibility_override_audit
  FOR SELECT
  USING (public.is_super_admin());

-- ── RPC: set / clear an override (Super Admin only) ───────────────────────────
-- p_new_state: 'allow' | 'deny' | 'inherit'. 'inherit' == Restore Default
-- (deletes any existing row). Always writes an audit row.
CREATE OR REPLACE FUNCTION public.fn_set_module_visibility_override(
  p_target_user   uuid,
  p_permission_key text,
  p_new_state     text,
  p_reason        text
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_actor    uuid := public.get_my_profile_id();
  v_previous text;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: only Super Admin may change module visibility overrides'
      USING ERRCODE = '42501';
  END IF;

  IF p_target_user IS NULL THEN
    RAISE EXCEPTION 'target user is required' USING ERRCODE = '22023';
  END IF;

  IF p_permission_key IS NULL
     OR NOT (p_permission_key = ANY (public.acc_v1_module_keys())) THEN
    RAISE EXCEPTION 'invalid permission_key "%": not a Phase 1 module key', p_permission_key
      USING ERRCODE = '22023';
  END IF;

  IF p_new_state IS NULL OR p_new_state NOT IN ('allow', 'deny', 'inherit') THEN
    RAISE EXCEPTION 'invalid override state "%": expected allow|deny|inherit', p_new_state
      USING ERRCODE = '22023';
  END IF;

  IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'a reason is required for every override change' USING ERRCODE = '22023';
  END IF;

  -- Confirm target exists.
  IF NOT EXISTS (SELECT 1 FROM public.users_profile WHERE id = p_target_user) THEN
    RAISE EXCEPTION 'target user not found' USING ERRCODE = '22023';
  END IF;

  -- Resolve previous value (row absence == inherit).
  SELECT override_state INTO v_previous
  FROM public.module_visibility_overrides
  WHERE user_id = p_target_user AND permission_key = p_permission_key;
  v_previous := COALESCE(v_previous, 'inherit');

  -- No-op guard: nothing to audit if value is unchanged.
  IF v_previous = p_new_state THEN
    RETURN;
  END IF;

  IF p_new_state = 'inherit' THEN
    -- Restore Default: delete the override row.
    DELETE FROM public.module_visibility_overrides
    WHERE user_id = p_target_user AND permission_key = p_permission_key;
  ELSE
    INSERT INTO public.module_visibility_overrides
      (user_id, permission_key, override_state, reason, created_by, created_at, updated_at)
    VALUES
      (p_target_user, p_permission_key, p_new_state, btrim(p_reason), v_actor, now(), now())
    ON CONFLICT (user_id, permission_key) DO UPDATE
      SET override_state = EXCLUDED.override_state,
          reason         = EXCLUDED.reason,
          created_by     = EXCLUDED.created_by,
          updated_at     = now();
  END IF;

  INSERT INTO public.module_visibility_override_audit
    (changed_by, target_user, permission_key, previous_value, new_value, reason, created_at)
  VALUES
    (v_actor, p_target_user, p_permission_key, v_previous, p_new_state, btrim(p_reason), now());
END;
$function$;

-- ── RPC: read a single user's overrides (Super Admin only) ────────────────────
CREATE OR REPLACE FUNCTION public.fn_get_module_overrides_for_user(
  p_target_user uuid
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin only' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_object_agg(permission_key, override_state), '{}'::jsonb)
  INTO v_result
  FROM public.module_visibility_overrides
  WHERE user_id = p_target_user;

  RETURN v_result;
END;
$function$;

-- ── RPC: read the CALLER's own overrides (used by nav resolver) ───────────────
CREATE OR REPLACE FUNCTION public.fn_get_my_module_overrides()
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_me     uuid := public.get_my_profile_id();
  v_result jsonb;
BEGIN
  IF v_me IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_object_agg(permission_key, override_state), '{}'::jsonb)
  INTO v_result
  FROM public.module_visibility_overrides
  WHERE user_id = v_me;

  RETURN v_result;
END;
$function$;

-- ── RPC: read recent audit rows for a user (Super Admin only) ─────────────────
CREATE OR REPLACE FUNCTION public.fn_module_override_audit(
  p_target_user uuid,
  p_limit       int DEFAULT 50
) RETURNS TABLE (
  id             uuid,
  changed_by     uuid,
  changed_by_name text,
  target_user    uuid,
  permission_key text,
  previous_value text,
  new_value      text,
  reason         text,
  created_at     timestamptz
)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin only' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT a.id,
         a.changed_by,
         up.full_name AS changed_by_name,
         a.target_user,
         a.permission_key,
         a.previous_value,
         a.new_value,
         a.reason,
         a.created_at
  FROM public.module_visibility_override_audit a
  LEFT JOIN public.users_profile up ON up.id = a.changed_by
  WHERE a.target_user = p_target_user
  ORDER BY a.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 500));
END;
$function$;

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.fn_set_module_visibility_override(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_get_module_overrides_for_user(uuid)                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_get_my_module_overrides()                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_module_override_audit(uuid, int)                        TO authenticated;
GRANT EXECUTE ON FUNCTION public.acc_v1_module_keys()                                       TO authenticated;

COMMIT;

-- ============================================================================
-- POST-APPLY VALIDATION (run manually in the Supabase SQL editor)
-- ============================================================================
-- 1. Tables + RLS present:
--      SELECT relname, relrowsecurity FROM pg_class
--      WHERE relname IN ('module_visibility_overrides','module_visibility_override_audit');
-- 2. As Super Admin: grant CENCOM to an HRCO user, expect 1 audit row:
--      SELECT public.fn_set_module_visibility_override(
--        '<hrco_user_id>', 'cencom.view', 'allow', 'temp coverage for cencom review');
--      SELECT * FROM public.fn_module_override_audit('<hrco_user_id>', 10);
-- 3. As that HRCO user: SELECT public.fn_get_my_module_overrides();  -- {"cencom.view":"allow"}
-- 4. Restore default (deletes row, writes audit):
--      SELECT public.fn_set_module_visibility_override(
--        '<hrco_user_id>', 'cencom.view', 'inherit', 'coverage ended');
-- 5. As a non-Super-Admin: fn_set_module_visibility_override(...) must raise 42501.
-- ============================================================================
