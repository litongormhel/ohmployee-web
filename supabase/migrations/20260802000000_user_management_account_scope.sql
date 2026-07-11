-- ═════════════════════════════════════════════════════════════════════════════
-- OHM2026_3003 — User Management Account Scope Support
-- Migration: 20260802000000_user_management_account_scope.sql
--
-- Depends on:
--   20260714000000_safespace_risk_controls.sql
--
-- Purpose:
--   1. Replaces public.upsert_user_profile_and_scopes with a signature that
--      accepts p_account_ids UUID[] DEFAULT '{}'.
--   2. Implements per-group scope mutual exclusivity: if specific accounts under
--      a group are provided, writes only those account-level rows; otherwise,
--      writes a group-level row with NULL account_id.
--   3. Enforces that every account in p_account_ids belongs to one of the selected
--      groups in p_group_ids.
--   4. Adds fn_get_accounts_by_groups to fetch active accounts under selected groups.
-- ═════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Drop old function signature to prevent duplicate overloaded signature ────
DROP FUNCTION IF EXISTS public.upsert_user_profile_and_scopes(TEXT, TEXT, UUID, UUID[], UUID);

-- ── Recreate upsert_user_profile_and_scopes with account scopes support ──────
CREATE OR REPLACE FUNCTION public.upsert_user_profile_and_scopes(
  p_full_name   TEXT,
  p_email       TEXT,
  p_role_id     UUID,
  p_group_ids   UUID[],
  p_account_ids UUID[] DEFAULT '{}',
  p_profile_id  UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_level  INT;
  v_caller_role   TEXT;
  v_target_level  INT;
  v_target_role   TEXT;
  v_profile_id    UUID := p_profile_id;
  v_gid           UUID;
  v_old_data      jsonb;
  v_has_accounts  BOOLEAN;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  SELECT r.role_level, r.role_name
    INTO v_caller_level, v_caller_role
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard (a): Head Admin cannot create new users ─────────────────────────
  IF p_profile_id IS NULL AND v_caller_level < 100 THEN
    RAISE EXCEPTION 'only Super Admin can create new user accounts'
      USING ERRCODE = '42501';
  END IF;

  -- ── Risk Control Gate (Phase 1) ────────────────────────────────────────────
  PERFORM public.fn_assert_risk_control_enabled('risk_role_editing');

  -- ── Resolve target role ───────────────────────────────────────────────────
  SELECT role_name, role_level
    INTO v_target_role, v_target_level
    FROM public.roles
   WHERE id = p_role_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'role not found: %', p_role_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Guard (b): cannot assign a role at or above own level ─────────────────
  IF COALESCE(v_target_level, 0) >= COALESCE(v_caller_level, 0)
     AND v_caller_level < 100 THEN
    RAISE EXCEPTION 'cannot assign a role at or above your own level (your level: %, role level: %)',
      v_caller_level, v_target_level
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard (c): every account in p_account_ids must belong to selected groups ──
  IF EXISTS (
    SELECT 1 FROM public.accounts a
    WHERE a.id = ANY(p_account_ids)
      AND NOT (a.group_id = ANY(p_group_ids))
  ) THEN
    RAISE EXCEPTION 'one or more accounts do not belong to selected groups'
      USING ERRCODE = '22023';
  END IF;

  -- ── Update or insert users_profile ────────────────────────────────────────
  IF v_profile_id IS NOT NULL THEN
    SELECT to_jsonb(up.*)
      INTO v_old_data
      FROM public.users_profile up
     WHERE up.id = v_profile_id;

    UPDATE public.users_profile
       SET full_name  = p_full_name,
           email      = p_email,
           role_id    = p_role_id,
           updated_at = NOW()
     WHERE id = v_profile_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'user profile not found: %', v_profile_id
        USING ERRCODE = 'P0002';
    END IF;
  ELSE
    -- Only reachable by Super Admin (guard (a) above)
    INSERT INTO public.users_profile (full_name, email, role_id, is_active)
    VALUES (p_full_name, p_email, p_role_id, TRUE)
    RETURNING id INTO v_profile_id;
  END IF;

  -- ── Replace scopes ────────────────────────────────────────────────────────
  DELETE FROM public.user_scopes WHERE user_id = v_profile_id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    -- Check if this group has specific account restrictions in p_account_ids
    SELECT EXISTS (
      SELECT 1 FROM public.accounts WHERE id = ANY(p_account_ids) AND group_id = v_gid
    ) INTO v_has_accounts;

    IF v_has_accounts THEN
      -- Specific account scopes (no group-wide row)
      INSERT INTO public.user_scopes (user_id, group_id, account_id)
      SELECT v_profile_id, v_gid, a.id
      FROM public.accounts a
      WHERE a.id = ANY(p_account_ids) AND a.group_id = v_gid
      ON CONFLICT DO NOTHING;
    ELSE
      -- Group-level row (access to all accounts in the group)
      INSERT INTO public.user_scopes (user_id, group_id, account_id)
      VALUES (v_profile_id, v_gid, NULL)
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  -- ── Audit — explicit ::audit_action cast ──────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'User Management',
    (CASE WHEN p_profile_id IS NULL THEN 'CREATE_USER' ELSE 'UPDATE_USER_ROLE' END)::audit_action,
    v_profile_id,
    v_old_data,
    jsonb_build_object(
      'full_name', p_full_name,
      'email',     p_email,
      'role_id',   p_role_id,
      'role_name', v_target_role,
      'group_ids', p_group_ids,
      'account_ids', p_account_ids
    )
  );

  RETURN v_profile_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid[], uuid) TO authenticated;

COMMENT ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid[], uuid) IS
  'OHM2026_3003: Gated with risk_role_editing. Creates or updates a user profile and '
  'replaces group and account scopes with mutual exclusivity.';


-- ── Create fn_get_accounts_by_groups utility function ───────────────────────
CREATE OR REPLACE FUNCTION public.fn_get_accounts_by_groups(p_group_ids UUID[])
RETURNS TABLE(id UUID, account_name TEXT, group_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT a.id, a.account_name, a.group_id
  FROM public.accounts a
  WHERE a.group_id = ANY(p_group_ids)
    AND a.is_active = TRUE
    AND a.status = 'Active'
  ORDER BY a.group_id, a.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_accounts_by_groups(UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_accounts_by_groups(UUID[]) TO authenticated;

COMMENT ON FUNCTION public.fn_get_accounts_by_groups(UUID[]) IS
  'OHM2026_3003: Returns all active/Active accounts belonging to the provided group IDs, ordered by group then name.';

COMMIT;
