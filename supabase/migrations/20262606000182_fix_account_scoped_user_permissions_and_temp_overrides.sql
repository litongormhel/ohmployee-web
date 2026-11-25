-- ============================================================================
-- Migration: 20262606000182_fix_account_scoped_user_permissions_and_temp_overrides.sql
-- Description:
--   1. Fixes scope leak in public.get_my_allowed_accounts():
--      - Part 2 was joining us.group_id = a.group_id without filtering us.account_id IS NULL.
--        Any user assigned a specific account_id also matched the parent group_id, leaking
--        all sibling accounts in the group across Vacancy and HR Emploc.
--      - Added `AND us.account_id IS NULL` to Part 2 so account-specific assignments never
--        expand to full group access.
--      - Hardened Part 3 (base profile fallback) to check (up.account_id = a.id OR (up.account_id IS NULL AND up.group_id = a.group_id)).
--      - Hardened Part 4 (temp overrides) to respect account-specific overrides without group leakage.
--   2. Aligns public.get_my_allowed_account_ids() and public.get_my_scoped_accounts():
--      - Brings get_my_allowed_account_ids() into identical 4-part UNION parity, returning uuid[].
--      - Synchronizes get_my_scoped_accounts() to query against get_my_allowed_account_ids().
--   3. Hardens temp_permission_overrides and RPCs:
--      - Adds additional_accounts (uuid[]) and additional_account_names (text[]) columns.
--      - Updates grant_temp_permission_override with optional p_additional_accounts uuid[] DEFAULT NULL.
--        When specified, inserts only account-specific user_scopes rows and stores account ids/names.
--      - Updates revoke_temp_permission_override to safely clean up account-specific temp user_scopes.
--   4. Hardens upsert_user_profile_and_scopes:
--      - When specific accounts are provided (p_account_ids non-empty), avoids creating un-pruned
--        group-wide wildcard rows (account_id IS NULL) for parent groups with zero selected accounts.
-- ============================================================================

BEGIN;

-- ── 1. Schema Extensions for Temporary Permission Overrides ──────────────────
ALTER TABLE public.temp_permission_overrides
  ADD COLUMN IF NOT EXISTS additional_accounts uuid[] DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS additional_account_names text[] DEFAULT NULL;

-- ── 2. Harden grant_temp_permission_override RPC ────────────────────────────
CREATE OR REPLACE FUNCTION public.grant_temp_permission_override(
  p_user_id             uuid,
  p_additional_groups   text[],
  p_expires_at          timestamptz,
  p_reason              text      DEFAULT NULL,
  p_notify_user         boolean   DEFAULT true,
  p_granted_by          text      DEFAULT NULL,
  p_additional_accounts uuid[]    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_override_id  uuid;
  v_group_name   text;
  v_group_id     uuid;
  v_acc_names    text[];
  v_has_accounts boolean;
BEGIN
  -- Auth: only SA or HA may call this RPC (trigger also validates on INSERT)
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin or Head Admin can grant permission overrides.';
  END IF;

  IF p_user_id = public.get_my_profile_id() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot grant a permission override to yourself.';
  END IF;

  IF p_expires_at IS NULL OR p_expires_at <= NOW() THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: expires_at must be a future timestamp.';
  END IF;

  v_has_accounts := COALESCE(array_length(p_additional_accounts, 1), 0) > 0;

  IF v_has_accounts THEN
    SELECT COALESCE(array_agg(a.account_name ORDER BY a.account_name), '{}'::text[])
      INTO v_acc_names
      FROM public.accounts a
     WHERE a.id = ANY(p_additional_accounts);
  END IF;

  -- Insert the override record (trigger re-validates before row is written)
  INSERT INTO public.temp_permission_overrides (
    user_id,
    granted_by,
    additional_groups,
    additional_accounts,
    additional_account_names,
    reason,
    expires_at,
    is_active,
    notify_user
  ) VALUES (
    p_user_id,
    COALESCE(p_granted_by, public.get_my_profile_id()::text),
    p_additional_groups,
    CASE WHEN v_has_accounts THEN p_additional_accounts ELSE NULL END,
    CASE WHEN v_has_accounts THEN v_acc_names ELSE NULL END,
    NULLIF(TRIM(COALESCE(p_reason, '')), ''),
    p_expires_at,
    true,
    COALESCE(p_notify_user, true)
  )
  RETURNING id INTO v_override_id;

  -- Upsert user_scopes
  IF v_has_accounts THEN
    -- Account-specific override: insert ONLY the specified account scopes
    INSERT INTO public.user_scopes (user_id, group_id, account_id)
    SELECT p_user_id, a.group_id, a.id
      FROM public.accounts a
     WHERE a.id = ANY(p_additional_accounts)
    ON CONFLICT (user_id, group_id, account_id) DO NOTHING;
  ELSE
    -- Group-wide override: insert user_scopes for each additional group with account_id = NULL
    FOREACH v_group_name IN ARRAY p_additional_groups LOOP
      SELECT id INTO v_group_id
        FROM public.groups
       WHERE group_name = v_group_name
       LIMIT 1;

      IF v_group_id IS NOT NULL THEN
        INSERT INTO public.user_scopes (user_id, group_id, account_id)
        VALUES (p_user_id, v_group_id, NULL)
        ON CONFLICT (user_id, group_id, account_id) DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  -- In-app notification to the recipient
  IF COALESCE(p_notify_user, true) THEN
    INSERT INTO public.notifications (
      recipient_role,
      title,
      message,
      reference_type,
      reference_id
    ) VALUES (
      'Encoder',
      '🔑 Temporary Access Granted',
      COALESCE(p_granted_by, 'An admin') || ' granted you temporary access to: '
        || CASE
             WHEN v_has_accounts THEN array_to_string(v_acc_names, ', ')
             ELSE array_to_string(p_additional_groups, ', ')
           END
        || '. Expires: ' || to_char(p_expires_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') || '.',
      'temp_permission',
      p_user_id
    );
  END IF;

  RETURN v_override_id;
END;
$$;

-- ── 3. Harden revoke_temp_permission_override RPC ──────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_temp_permission_override(
  p_override_id uuid,
  p_revoked_by  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_target_user_id      uuid;
  v_additional_groups   text[];
  v_additional_accounts uuid[];
  v_override_created     timestamptz;
  v_group_name           text;
  v_group_id             uuid;
  v_acc_id               uuid;
  v_covered_by_other     boolean;
BEGIN
  -- Auth: only SA or HA may revoke
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin or Head Admin can revoke permission overrides.';
  END IF;

  -- Fetch override (must exist and be active)
  SELECT user_id, additional_groups, additional_accounts, created_at
    INTO v_target_user_id, v_additional_groups, v_additional_accounts, v_override_created
    FROM public.temp_permission_overrides
   WHERE id = p_override_id
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Override not found or already revoked.';
  END IF;

  -- Mark the override as revoked
  UPDATE public.temp_permission_overrides
     SET is_active   = false,
         revoked_at  = NOW(),
         revoked_by  = COALESCE(p_revoked_by, public.get_my_profile_id()::text)
   WHERE id = p_override_id;

  -- If account-specific override was granted:
  IF COALESCE(array_length(v_additional_accounts, 1), 0) > 0 THEN
    FOREACH v_acc_id IN ARRAY v_additional_accounts LOOP
      -- Safety check: only delete if NOT covered by another active override
      SELECT EXISTS (
        SELECT 1
          FROM public.temp_permission_overrides t
         WHERE t.user_id = v_target_user_id
           AND t.id <> p_override_id
           AND t.is_active = true
           AND (t.expires_at IS NULL OR t.expires_at > NOW())
           AND t.revoked_at IS NULL
           AND v_acc_id = ANY(t.additional_accounts)
      ) INTO v_covered_by_other;

      IF NOT v_covered_by_other THEN
        DELETE FROM public.user_scopes
         WHERE user_id    = v_target_user_id
           AND account_id = v_acc_id
           AND created_at >= v_override_created;
      END IF;
    END LOOP;
  ELSE
    -- Group-wide override cleanup
    FOREACH v_group_name IN ARRAY v_additional_groups LOOP
      SELECT id INTO v_group_id
        FROM public.groups
       WHERE group_name = v_group_name
       LIMIT 1;

      CONTINUE WHEN v_group_id IS NULL;

      SELECT EXISTS (
        SELECT 1
          FROM public.temp_permission_overrides t
         WHERE t.user_id = v_target_user_id
           AND t.id <> p_override_id
           AND t.is_active = true
           AND (t.expires_at IS NULL OR t.expires_at > NOW())
           AND t.revoked_at IS NULL
           AND (t.additional_accounts IS NULL OR array_length(t.additional_accounts, 1) = 0)
           AND v_group_name = ANY(t.additional_groups)
      ) INTO v_covered_by_other;

      IF NOT v_covered_by_other THEN
        DELETE FROM public.user_scopes
         WHERE user_id    = v_target_user_id
           AND group_id   = v_group_id
           AND account_id IS NULL
           AND created_at >= v_override_created;
      END IF;
    END LOOP;
  END IF;
END;
$$;

-- ── 4. Harden public.get_my_allowed_accounts() ──────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_allowed_accounts()
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level int;
  v_profile_id uuid;
  v_scope_type text;
BEGIN
  v_role_level := public.get_my_role_level();
  v_profile_id := public.get_my_profile_id();
  v_scope_type := public.get_my_scope_type();

  IF v_profile_id IS NULL THEN
    RETURN ARRAY[]::text[];
  END IF;

  IF v_scope_type = 'global' OR COALESCE(v_role_level, 0) >= 90 THEN
    RETURN ARRAY(
      SELECT a.account_name
      FROM public.accounts a
      WHERE a.is_active = true
      ORDER BY a.account_name
    );
  END IF;

  RETURN ARRAY(
    -- 1. Explicitly assigned accounts in user_scopes
    SELECT DISTINCT a.account_name
    FROM public.accounts a
    JOIN public.user_scopes us ON us.account_id = a.id
    WHERE us.user_id = v_profile_id
      AND a.is_active = true

    UNION

    -- 2. Accounts belonging to groups assigned in user_scopes (group-wide scopes ONLY, no account_id restriction)
    SELECT DISTINCT a.account_name
    FROM public.accounts a
    JOIN public.user_scopes us ON us.group_id = a.group_id
    WHERE us.user_id = v_profile_id
      AND us.account_id IS NULL
      AND a.is_active = true

    UNION

    -- 3. Base profile fallback when user_scopes has no entries
    SELECT DISTINCT a.account_name
    FROM public.accounts a
    JOIN public.users_profile up ON up.id = v_profile_id
    WHERE (
        (up.account_id IS NOT NULL AND up.account_id = a.id)
        OR
        (up.account_id IS NULL AND up.group_id IS NOT NULL AND up.group_id = a.group_id)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id
      )
      AND a.is_active = true

    UNION

    -- 4. Temporary permission overrides
    -- (a) Account-specific temporary overrides
    SELECT DISTINCT a.account_name
    FROM public.accounts a
    JOIN public.temp_permission_overrides tpo
      ON a.id = ANY(tpo.additional_accounts)
    WHERE tpo.user_id = v_profile_id
      AND tpo.is_active = true
      AND (tpo.expires_at IS NULL OR tpo.expires_at > now())
      AND tpo.revoked_at IS NULL
      AND a.is_active = true

    UNION

    -- (b) Group-wide temporary overrides (only when no specific accounts were targeted)
    SELECT DISTINCT a2.account_name
    FROM public.accounts a2
    JOIN public.groups g ON g.id = a2.group_id
    JOIN public.temp_permission_overrides tpo
      ON g.group_name = ANY(tpo.additional_groups)
    WHERE tpo.user_id = v_profile_id
      AND (tpo.additional_accounts IS NULL OR array_length(tpo.additional_accounts, 1) = 0)
      AND tpo.is_active = true
      AND (tpo.expires_at IS NULL OR tpo.expires_at > now())
      AND tpo.revoked_at IS NULL
      AND a2.is_active = true
  );
END;
$function$;

-- ── 5. Harden public.get_my_allowed_account_ids() ───────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_allowed_account_ids()
 RETURNS uuid[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level int;
  v_profile_id uuid;
  v_scope_type text;
BEGIN
  v_role_level := public.get_my_role_level();
  v_profile_id := public.get_my_profile_id();
  v_scope_type := public.get_my_scope_type();

  IF v_profile_id IS NULL THEN
    RETURN ARRAY[]::uuid[];
  END IF;

  IF v_scope_type = 'global' OR COALESCE(v_role_level, 0) >= 90 THEN
    RETURN ARRAY(
      SELECT a.id
      FROM public.accounts a
      WHERE a.is_active = true
      ORDER BY a.account_name
    );
  END IF;

  RETURN ARRAY(
    -- 1. Explicitly assigned accounts in user_scopes
    SELECT DISTINCT a.id
    FROM public.accounts a
    JOIN public.user_scopes us ON us.account_id = a.id
    WHERE us.user_id = v_profile_id
      AND a.is_active = true

    UNION

    -- 2. Accounts belonging to groups assigned in user_scopes (group-wide scopes ONLY, no account_id restriction)
    SELECT DISTINCT a.id
    FROM public.accounts a
    JOIN public.user_scopes us ON us.group_id = a.group_id
    WHERE us.user_id = v_profile_id
      AND us.account_id IS NULL
      AND a.is_active = true

    UNION

    -- 3. Base profile fallback when user_scopes has no entries
    SELECT DISTINCT a.id
    FROM public.accounts a
    JOIN public.users_profile up ON up.id = v_profile_id
    WHERE (
        (up.account_id IS NOT NULL AND up.account_id = a.id)
        OR
        (up.account_id IS NULL AND up.group_id IS NOT NULL AND up.group_id = a.group_id)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id
      )
      AND a.is_active = true

    UNION

    -- 4. Temporary permission overrides
    -- (a) Account-specific temporary overrides
    SELECT DISTINCT a.id
    FROM public.accounts a
    JOIN public.temp_permission_overrides tpo
      ON a.id = ANY(tpo.additional_accounts)
    WHERE tpo.user_id = v_profile_id
      AND tpo.is_active = true
      AND (tpo.expires_at IS NULL OR tpo.expires_at > now())
      AND tpo.revoked_at IS NULL
      AND a.is_active = true

    UNION

    -- (b) Group-wide temporary overrides (only when no specific accounts were targeted)
    SELECT DISTINCT a2.id
    FROM public.accounts a2
    JOIN public.groups g ON g.id = a2.group_id
    JOIN public.temp_permission_overrides tpo
      ON g.group_name = ANY(tpo.additional_groups)
    WHERE tpo.user_id = v_profile_id
      AND (tpo.additional_accounts IS NULL OR array_length(tpo.additional_accounts, 1) = 0)
      AND tpo.is_active = true
      AND (tpo.expires_at IS NULL OR tpo.expires_at > now())
      AND tpo.revoked_at IS NULL
      AND a2.is_active = true
  );
END;
$function$;

-- ── 6. Synchronize public.get_my_scoped_accounts() ──────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_scoped_accounts()
 RETURNS TABLE(account_id uuid, account_name text, account_code text, group_id uuid, group_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level int;
  v_scope_type text;
  v_allowed_ids uuid[];
BEGIN
  v_role_level := public.get_my_role_level();
  v_scope_type := public.get_my_scope_type();

  IF v_scope_type = 'global' OR COALESCE(v_role_level, 0) >= 90 THEN
    RETURN QUERY
    SELECT DISTINCT
      a.id,
      a.account_name,
      a.account_code,
      a.group_id,
      g.group_name
    FROM public.accounts a
    JOIN public.groups g ON g.id = a.group_id
    WHERE a.is_active = true
    ORDER BY g.group_name, a.account_name;
    RETURN;
  END IF;

  v_allowed_ids := public.get_my_allowed_account_ids();

  RETURN QUERY
  SELECT DISTINCT
    a.id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name
  FROM public.accounts a
  JOIN public.groups g ON g.id = a.group_id
  WHERE a.id = ANY(v_allowed_ids)
    AND a.is_active = true
  ORDER BY g.group_name, a.account_name;
END;
$function$;

-- ── 7. Harden public.upsert_user_profile_and_scopes ─────────────────────────
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
      -- Only create group-level row if NO specific accounts were provided across the entire payload.
      -- If specific accounts WERE provided, do NOT create an un-pruned group-wide wildcard row!
      IF COALESCE(array_length(p_account_ids, 1), 0) = 0 THEN
        INSERT INTO public.user_scopes (user_id, group_id, account_id)
        VALUES (v_profile_id, v_gid, NULL)
        ON CONFLICT DO NOTHING;
      END IF;
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

-- ── 8. Permissions & Grants ─────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.get_my_allowed_accounts() TO PUBLIC, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_allowed_account_ids() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_scoped_accounts() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.grant_temp_permission_override(uuid, text[], timestamptz, text, boolean, text, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.grant_temp_permission_override(uuid, text[], timestamptz, text, boolean, text, uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION public.revoke_temp_permission_override(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_temp_permission_override(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_user_profile_and_scopes(text, text, uuid, uuid[], uuid[], uuid) TO authenticated;

COMMIT;
