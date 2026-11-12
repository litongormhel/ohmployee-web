-- ============================================================================
-- Migration: 20262606000102_harden_user_management_activation_and_hrco_sync.sql
-- Description:
--   1. Hardens upsert_user_profile_and_scopes:
--      - Automatically activates and unarchives a user profile (is_active = TRUE,
--        archived_at = NULL, archived_by = NULL) when an Admin updates their role/scopes.
--      - Automatically invokes fn_reevaluate_hrco_auto_tags for affected accounts
--        when an HRCO's scopes or role are assigned/updated, syncing accounts.hrco_user_id.
--   2. Hardens set_user_active:
--      - Clears archived_at and archived_by when p_is_active is TRUE.
--      - Invokes fn_reevaluate_hrco_auto_tags for accounts scoped to the user if HRCO.
--   3. Reactivates Alvin Rey (885810b8-7b62-4eb6-8b2c-2db77a0e7289) and runs
--      fn_reevaluate_hrco_auto_tags for APEX (42a3cec9-a5eb-4c90-ac45-45669c212b12).
-- ============================================================================

BEGIN;

-- ── 1. Update public.upsert_user_profile_and_scopes ─────────────────────────
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
  v_sync_acc      RECORD;
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

    -- When updating user role/scopes, restore active status and clear archived flags
    UPDATE public.users_profile
       SET full_name   = p_full_name,
           email       = p_email,
           role_id     = p_role_id,
           is_active   = TRUE,
           archived_at = NULL,
           archived_by = NULL,
           updated_at  = NOW()
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

  -- ── Re-evaluate HRCO auto tags for affected accounts ───────────────────────
  FOR v_sync_acc IN
    SELECT DISTINCT a.id AS account_id
      FROM public.accounts a
     WHERE (a.id = ANY(p_account_ids))
        OR (a.group_id = ANY(p_group_ids))
  LOOP
    PERFORM public.fn_reevaluate_hrco_auto_tags(v_sync_acc.account_id);
  END LOOP;

  RETURN v_profile_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid[], uuid) TO authenticated;

-- ── 2. Update public.set_user_active ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_user_active(p_profile_id uuid, p_is_active boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id    UUID;
  v_caller_level INT;
  v_target_name  TEXT;
  v_target_role  TEXT;
  v_old_state    BOOLEAN;
  v_sync_acc     RECORD;
BEGIN
  v_caller_id := auth.uid();

  -- ── Auth ──────────────────────────────────────────────────────────────────
  SELECT r.role_level
    INTO v_caller_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = v_caller_id;

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch target ──────────────────────────────────────────────────────────
  SELECT up.full_name, r.role_name, up.is_active
    INTO v_target_name, v_target_role, v_old_state
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.id = p_profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user profile not found: %', p_profile_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Guard: self-action blocked ─────────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.users_profile
     WHERE id = p_profile_id AND auth_user_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'cannot change your own active status'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: Head Admin cannot deactivate a Super Admin ─────────────────────
  IF NOT p_is_active
     AND v_target_role IN ('Super Admin', 'superAdmin', 'super_admin')
     AND COALESCE(v_caller_level, 0) < 100 THEN
    RAISE EXCEPTION 'only Super Admin can deactivate another Super Admin'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: cannot deactivate the last active Super Admin ──────────────────
  IF NOT p_is_active AND v_target_role IN ('Super Admin', 'superAdmin', 'super_admin') THEN
    IF (
      SELECT COUNT(*) FROM public.users_profile up2
      JOIN public.roles r2 ON r2.id = up2.role_id
      WHERE r2.role_name IN ('Super Admin', 'superAdmin', 'super_admin')
        AND up2.is_active = TRUE
        AND up2.id <> p_profile_id
    ) = 0 THEN
      RAISE EXCEPTION 'cannot deactivate the last active Super Admin'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── Apply ─────────────────────────────────────────────────────────────────
  UPDATE public.users_profile
     SET is_active   = p_is_active,
         archived_at = CASE WHEN p_is_active THEN NULL ELSE archived_at END,
         archived_by = CASE WHEN p_is_active THEN NULL ELSE archived_by END,
         updated_at  = NOW()
   WHERE id = p_profile_id;

  -- ── Audit — fixed: explicit ::audit_action cast ───────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    v_caller_id,
    'User Management',
    (CASE WHEN p_is_active THEN 'ACTIVATE_USER' ELSE 'DEACTIVATE_USER' END)::audit_action,
    p_profile_id,
    jsonb_build_object('is_active', v_old_state, 'full_name', v_target_name),
    jsonb_build_object('is_active', p_is_active, 'full_name', v_target_name)
  );

  -- ── Re-evaluate HRCO auto tags if target was/is HRCO ─────────────────────
  IF v_target_role = 'HRCO' THEN
    FOR v_sync_acc IN
      SELECT DISTINCT a.id AS account_id
        FROM public.user_scopes us
        JOIN public.accounts a ON (a.id = us.account_id OR (us.account_id IS NULL AND a.group_id = us.group_id))
       WHERE us.user_id = p_profile_id
    LOOP
      PERFORM public.fn_reevaluate_hrco_auto_tags(v_sync_acc.account_id);
    END LOOP;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.set_user_active(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_user_active(uuid, boolean) TO authenticated;

-- ── 3. Reactivate Alvin Rey & sync APEX account on Staging ─────────────────
UPDATE public.users_profile
   SET is_active   = TRUE,
       archived_at = NULL,
       archived_by = NULL,
       updated_at  = NOW()
 WHERE id = '885810b8-7b62-4eb6-8b2c-2db77a0e7289';

-- Auto-sync APEX HRCO tag
SELECT public.fn_reevaluate_hrco_auto_tags('42a3cec9-a5eb-4c90-ac45-45669c212b12');

COMMIT;
