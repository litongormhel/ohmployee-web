-- Migration: 20262606000103_fix_get_my_allowed_accounts_union_group_scopes.sql
-- Description: Unify public.get_my_allowed_accounts() to return the additive UNION
-- of explicitly assigned accounts (user_scopes.account_id) AND accounts belonging
-- to assigned groups (user_scopes.group_id), plus users_profile fallback and temporary
-- permission overrides. Previously, an `IF v_account_count > 0` branch caused users
-- with hybrid scopes (e.g. uat1@ohmployee.com) to drop all group-assigned accounts,
-- breaking RLS checks (e.g. vacancies_read_scoped, applicants_insert_ops_only).

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

    -- 2. Accounts belonging to groups assigned in user_scopes
    SELECT DISTINCT a.account_name
    FROM public.accounts a
    JOIN public.user_scopes us ON us.group_id = a.group_id
    WHERE us.user_id = v_profile_id
      AND a.is_active = true

    UNION

    -- 3. Base profile fallback when user_scopes has no entries
    SELECT DISTINCT a.account_name
    FROM public.accounts a
    JOIN public.users_profile up ON up.id = v_profile_id
    WHERE (up.account_id = a.id OR up.group_id = a.group_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id
      )
      AND a.is_active = true

    UNION

    -- 4. Temporary permission overrides
    SELECT DISTINCT a2.account_name
    FROM public.accounts a2
    JOIN public.groups g ON g.id = a2.group_id
    JOIN public.temp_permission_overrides tpo
      ON g.group_name = ANY(tpo.additional_groups)
    WHERE tpo.user_id = v_profile_id
      AND tpo.is_active = true
      AND (tpo.expires_at IS NULL OR tpo.expires_at > now())
      AND tpo.revoked_at IS NULL
      AND a2.is_active = true
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_my_allowed_accounts() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_allowed_accounts() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_allowed_accounts() TO service_role;
