-- Migration: fix_get_my_scope_type_acting_session_aware
-- Prompt: ohm#9m4k7wln
-- Purpose: get_my_scope_type() ignored active acting sessions, always reading the
-- real (SA) profile's scope_type/role_level. This made get_my_allowed_accounts()/
-- get_my_scoped_accounts() short-circuit to "all active accounts" for the entire
-- duration of any acting session, regardless of the acted role. Mirrors the
-- get_active_acting_session()-first pattern already used by get_effective_role().
-- Acting sessions have no acting_scope_type column and no target-profile id, only
-- acting_role (text) + explicit acting_account_ids/acting_group_ids, so the acted
-- scope_type is derived from the acted role's role_level (>=90 -> 'global', else
-- 'scoped') rather than copied from any per-user override row.
-- No-session branch is byte-identical to the pre-fix function body.

CREATE OR REPLACE FUNCTION public.get_my_scope_type()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_session public.acting_sessions;
  v_scope_type text;
  v_role_level int;
BEGIN
  SELECT * INTO v_session FROM public.get_active_acting_session();

  IF v_session.id IS NOT NULL THEN
    SELECT r.role_level INTO v_role_level
    FROM public.roles r
    WHERE r.role_name = v_session.acting_role
    LIMIT 1;

    IF COALESCE(v_role_level, 0) >= 90 THEN
      RETURN 'global';
    END IF;

    RETURN 'scoped';
  END IF;

  SELECT up.scope_type, r.role_level
  INTO v_scope_type, v_role_level
  FROM public.users_profile up
  LEFT JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid()
    AND up.is_active = true
  LIMIT 1;

  IF COALESCE(v_role_level, 0) >= 90 THEN
    RETURN 'global';
  END IF;

  RETURN COALESCE(v_scope_type, 'scoped');
END;
$function$;
