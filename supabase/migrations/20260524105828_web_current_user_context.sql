-- Migration: 20260524105828_web_current_user_context.sql
-- Ticket: OHM2026_1073 - Web current-user presentation context RPC
--
-- Adds public.get_web_current_user_context()
--
-- Purpose:
--   Safe, read-only current-user context for the OHMployee Web presentation
--   shell. This RPC is intentionally scoped to navigation/profile context only.
--   It does NOT replace RLS/RPC enforcement for business actions, workflow
--   mutations, approvals, user administration, or any sensitive HR surface.
--
-- Security invariants:
--   - Caller identity is derived only from auth.uid().
--   - No user/profile/scope arguments are accepted.
--   - No service-role-only data or service keys are exposed.
--   - Employee/Plantilla-sensitive fields are not returned.
--   - Blocked states return a denied context with empty scope/module payloads.
--   - Execution is granted only to authenticated.

DROP FUNCTION IF EXISTS public.get_web_current_user_context();

CREATE OR REPLACE FUNCTION public.get_web_current_user_context()
RETURNS TABLE (
  auth_user_id        uuid,
  profile_id          uuid,
  email               text,
  full_name           text,
  role_key            text,
  role_name           text,
  is_active           boolean,
  status              text,
  group_scope         jsonb,
  account_scope       jsonb,
  allowed_module_keys text[],
  module_capabilities jsonb,
  access_status       text,
  failure_reason      text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid           uuid := auth.uid();
  v_profile_id         uuid;
  v_email              text;
  v_full_name          text;
  v_role_name          text;
  v_role_level         integer;
  v_is_active          boolean;
  v_archived_at        timestamptz;
  v_status             text;
  v_has_scope_rows     boolean := false;
  v_group_scope        jsonb := '[]'::jsonb;
  v_account_scope      jsonb := '[]'::jsonb;
  v_allowed_modules    text[] := ARRAY[]::text[];
  v_capabilities       jsonb := '{}'::jsonb;
BEGIN
  -- Direct SQL/anon safety. The function is not granted to anon, but keep the
  -- guard here so the contract fails closed independent of grants.
  IF v_auth_uid IS NULL THEN
    RETURN QUERY
    SELECT
      NULL::uuid,
      NULL::uuid,
      NULL::text,
      NULL::text,
      NULL::text,
      NULL::text,
      FALSE,
      'unauthenticated'::text,
      '[]'::jsonb,
      '[]'::jsonb,
      ARRAY[]::text[],
      '{}'::jsonb,
      'denied'::text,
      'unauthenticated'::text;
    RETURN;
  END IF;

  SELECT
    up.id,
    up.email,
    up.full_name,
    r.role_name,
    r.role_level,
    COALESCE(up.is_active, FALSE),
    up.archived_at
  INTO
    v_profile_id,
    v_email,
    v_full_name,
    v_role_name,
    v_role_level,
    v_is_active,
    v_archived_at
  FROM public.users_profile up
  LEFT JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL THEN
    RETURN QUERY
    SELECT
      v_auth_uid,
      NULL::uuid,
      NULL::text,
      NULL::text,
      NULL::text,
      NULL::text,
      FALSE,
      'missing_profile'::text,
      '[]'::jsonb,
      '[]'::jsonb,
      ARRAY[]::text[],
      '{}'::jsonb,
      'denied'::text,
      'missing_profile'::text;
    RETURN;
  END IF;

  IF NOT v_is_active THEN
    RETURN QUERY
    SELECT
      v_auth_uid,
      v_profile_id,
      v_email,
      v_full_name,
      NULL::text,
      NULL::text,
      FALSE,
      'inactive'::text,
      '[]'::jsonb,
      '[]'::jsonb,
      ARRAY[]::text[],
      '{}'::jsonb,
      'denied'::text,
      'inactive_user'::text;
    RETURN;
  END IF;

  IF v_archived_at IS NOT NULL THEN
    RETURN QUERY
    SELECT
      v_auth_uid,
      v_profile_id,
      v_email,
      v_full_name,
      NULL::text,
      NULL::text,
      FALSE,
      'archived'::text,
      '[]'::jsonb,
      '[]'::jsonb,
      ARRAY[]::text[],
      '{}'::jsonb,
      'denied'::text,
      'archived_user'::text;
    RETURN;
  END IF;

  IF COALESCE(v_role_level, 0) <= 0 OR COALESCE(v_role_name, 'Unknown') = 'Unknown' THEN
    RETURN QUERY
    SELECT
      v_auth_uid,
      v_profile_id,
      v_email,
      v_full_name,
      NULL::text,
      NULL::text,
      TRUE,
      'unauthorized'::text,
      '[]'::jsonb,
      '[]'::jsonb,
      ARRAY[]::text[],
      '{}'::jsonb,
      'denied'::text,
      'unauthorized_role'::text;
    RETURN;
  END IF;

  v_status := 'active';

  SELECT EXISTS (
    SELECT 1
    FROM public.user_scopes us
    WHERE us.user_id = v_profile_id
      AND (us.group_id IS NOT NULL OR us.account_id IS NOT NULL)
  )
  INTO v_has_scope_rows;

  IF v_role_level >= 90 THEN
    v_group_scope := jsonb_build_object(
      'mode', 'global',
      'groups', '[]'::jsonb
    );
    v_account_scope := jsonb_build_object(
      'mode', 'global',
      'accounts', '[]'::jsonb
    );
  ELSE
    WITH scoped_groups AS (
      SELECT DISTINCT g.id, g.group_code, g.group_name
      FROM public.user_scopes us
      JOIN public.groups g ON g.id = us.group_id
      WHERE us.user_id = v_profile_id

      UNION

      SELECT g.id, g.group_code, g.group_name
      FROM public.users_profile up
      JOIN public.groups g ON g.id = up.group_id
      WHERE up.id = v_profile_id
        AND NOT v_has_scope_rows
        AND up.group_id IS NOT NULL
    )
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'group_id', id,
          'group_code', group_code,
          'group_name', group_name
        )
        ORDER BY group_name
      ),
      '[]'::jsonb
    )
    INTO v_group_scope
    FROM scoped_groups;

    WITH account_rows AS (
      SELECT DISTINCT
        a.id AS account_id,
        a.account_name,
        g.id AS group_id,
        g.group_name
      FROM public.user_scopes us
      JOIN public.accounts a ON a.id = us.account_id
      LEFT JOIN public.groups g ON g.id = a.group_id
      WHERE us.user_id = v_profile_id
        AND us.account_id IS NOT NULL
        AND COALESCE(a.is_active, TRUE)

      UNION

      SELECT
        up.account_id,
        a.account_name,
        g.id AS group_id,
        g.group_name
      FROM public.users_profile up
      JOIN public.accounts a ON a.id = up.account_id
      LEFT JOIN public.groups g ON g.id = a.group_id
      WHERE up.id = v_profile_id
        AND NOT v_has_scope_rows
        AND up.account_id IS NOT NULL
        AND COALESCE(a.is_active, TRUE)
    )
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'account_id', account_id,
          'account_name', account_name,
          'group_id', group_id,
          'group_name', group_name
        )
        ORDER BY account_name
      ),
      '[]'::jsonb
    )
    INTO v_account_scope
    FROM account_rows;

    v_group_scope := jsonb_build_object(
      'mode', CASE WHEN jsonb_array_length(v_group_scope) > 0 THEN 'scoped' ELSE 'none' END,
      'groups', v_group_scope
    );

    v_account_scope := jsonb_build_object(
      'mode',
        CASE
          WHEN jsonb_array_length(v_account_scope) > 0 THEN 'account'
          WHEN EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = v_profile_id
              AND us.group_id IS NOT NULL
              AND us.account_id IS NULL
          ) THEN 'group_all_accounts'
          ELSE 'none'
        END,
      'accounts', v_account_scope
    );
  END IF;

  -- Convert the Mobile RBAC registry into the Web module registry. This is a
  -- presentation capability snapshot only; action RPCs and RLS remain final.
  WITH web_capabilities AS (
    SELECT
      CASE d.module_key
        WHEN 'dashboard' THEN 'dashboard'
        WHEN 'cencom' THEN 'cencom'
        WHEN 'vacancy' THEN
          CASE
            WHEN d.action_key IN ('approve_closure') THEN 'approvals'
            ELSE 'vacancy'
          END
        WHEN 'hr_emploc' THEN 'hr_emploc'
        WHEN 'plantilla' THEN 'plantilla'
        WHEN 'deactivation' THEN 'approvals'
        WHEN 'user_management' THEN 'users'
        WHEN 'access_management' THEN
          CASE
            WHEN d.resource_key = 'security_event' THEN 'reports'
            ELSE 'settings'
          END
        WHEN 'governance' THEN 'reports'
        ELSE NULL
      END AS web_module_key,
      jsonb_build_object(
        'module_key', d.module_key,
        'resource_key', d.resource_key,
        'action_key', d.action_key,
        'scope_mode', d.scope_mode,
        'enforcement_type', d.enforcement_type,
        'source_type', m.source_type,
        'is_sensitive', d.is_sensitive
      ) AS capability
    FROM public.role_permission_matrix m
    JOIN public.role_permission_definitions d ON d.id = m.permission_definition_id
    JOIN public.roles r ON r.id = m.role_id
    WHERE r.role_name = v_role_name
      AND m.is_allowed = TRUE
  ),
  base_capabilities AS (
    SELECT 'settings' AS web_module_key,
           jsonb_build_object(
             'module_key', 'settings',
             'resource_key', 'own_settings',
             'action_key', 'view',
             'scope_mode', 'self',
             'enforcement_type', 'db_rls',
             'source_type', 'derived',
             'is_sensitive', false
           ) AS capability
    UNION ALL
    SELECT 'notifications',
           jsonb_build_object(
             'module_key', 'notifications',
             'resource_key', 'own_notifications',
             'action_key', 'view',
             'scope_mode', 'self',
             'enforcement_type', 'db_rls',
             'source_type', 'derived',
             'is_sensitive', false
           )
    UNION ALL
    SELECT 'more',
           jsonb_build_object(
             'module_key', 'more',
             'resource_key', 'navigation_hub',
             'action_key', 'view',
             'scope_mode', 'self',
             'enforcement_type', 'ui_only',
             'source_type', 'derived',
             'is_sensitive', false
           )
    UNION ALL
    SELECT 'team_directory',
           jsonb_build_object(
             'module_key', 'team_directory',
             'resource_key', 'team_directory',
             'action_key', 'view',
             'scope_mode', CASE WHEN v_role_level >= 90 THEN 'global' ELSE 'group' END,
             'enforcement_type', 'rpc',
             'source_type', 'derived',
             'is_sensitive', false
           )
    WHERE v_role_level > 10
  ),
  all_capabilities AS (
    SELECT web_module_key, capability
    FROM web_capabilities
    WHERE web_module_key IN (
      'dashboard',
      'cencom',
      'vacancy',
      'hr_emploc',
      'plantilla',
      'approvals',
      'users',
      'team_directory',
      'notifications',
      'reports',
      'settings',
      'more'
    )
    UNION ALL
    SELECT web_module_key, capability
    FROM base_capabilities
  ),
  module_payload AS (
    SELECT web_module_key, jsonb_agg(capability ORDER BY capability->>'resource_key', capability->>'action_key') AS capabilities
    FROM all_capabilities
    GROUP BY web_module_key
  )
  SELECT
    COALESCE(array_agg(web_module_key ORDER BY array_position(
      ARRAY[
        'dashboard',
        'cencom',
        'vacancy',
        'hr_emploc',
        'plantilla',
        'approvals',
        'users',
        'team_directory',
        'notifications',
        'reports',
        'settings',
        'more'
      ],
      web_module_key
    )), ARRAY[]::text[]),
    COALESCE(jsonb_object_agg(web_module_key, capabilities), '{}'::jsonb)
  INTO v_allowed_modules, v_capabilities
  FROM module_payload;

  RETURN QUERY
  SELECT
    v_auth_uid,
    v_profile_id,
    v_email,
    v_full_name,
    lower(regexp_replace(v_role_name, '[^a-zA-Z0-9]+', '_', 'g')),
    v_role_name,
    v_is_active,
    v_status,
    v_group_scope,
    v_account_scope,
    v_allowed_modules,
    v_capabilities,
    'allowed'::text,
    NULL::text;
END;
$$;

COMMENT ON FUNCTION public.get_web_current_user_context() IS
  'Safe current-user presentation context for OHMployee Web. Uses auth.uid() only and returns profile identity, role, safe scope summary, and module capability hints. This does not replace RLS or action-specific RPC authorization.';

REVOKE ALL ON FUNCTION public.get_web_current_user_context() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_current_user_context() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_current_user_context() TO authenticated;

-- Validation notes (run in staging/dev with representative JWT sessions):
--
-- 1. Unauthenticated blocked:
--    RESET ROLE;
--    SELECT * FROM public.get_web_current_user_context();
--    Expected via API: anon cannot execute. Direct SQL with auth.uid() NULL returns
--    access_status='denied', failure_reason='unauthenticated'.
--
-- 2. Missing profile blocked:
--    As authenticated auth.uid() with no users_profile row:
--    SELECT access_status, failure_reason FROM public.get_web_current_user_context();
--    Expected: denied / missing_profile.
--
-- 3. Inactive or archived user blocked:
--    Temporarily set users_profile.is_active=false or archived_at=now() for the
--    caller profile in a disposable database, then call the RPC.
--    Expected: denied / inactive_user or archived_user with empty module arrays.
--
-- 4. Normal scoped user returns limited modules:
--    As a non-admin role with user_scopes rows:
--    SELECT role_name, group_scope, account_scope, allowed_module_keys
--    FROM public.get_web_current_user_context();
--    Expected: scopes reflect only assigned groups/accounts; module keys align to
--    the Web registry and exclude admin-only modules such as users when not allowed.
--
-- 5. Super Admin / Head Admin returns expected admin modules:
--    As Super Admin or Head Admin:
--    SELECT role_name, group_scope->>'mode', account_scope->>'mode', allowed_module_keys
--    FROM public.get_web_current_user_context();
--    Expected: global scope modes; users/settings/reports/admin-appropriate modules
--    present according to the existing Mobile RBAC registry.
