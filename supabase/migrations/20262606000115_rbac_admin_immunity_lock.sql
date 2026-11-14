-- Migration: 20262606000115_rbac_admin_immunity_lock.sql
-- Description: Administrative Immunity Lock for Super Admin (100) and Head Admin (90)
-- Guarantees that administrative accounts never lose access to modules (Approvals, CENCOM, Plantilla, Vacancy, Users, etc.)
-- regardless of overrides, unlinked role records, or ACC V1 table mutations.

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
  v_norm_role          text;
  v_is_active          boolean;
  v_archived_at        timestamptz;
  v_status             text;
  v_has_scope_rows     boolean := false;
  v_group_scope        jsonb := '[]'::jsonb;
  v_account_scope      jsonb := '[]'::jsonb;
  v_allowed_modules    text[] := ARRAY[]::text[];
  v_capabilities       jsonb := '{}'::jsonb;
  
  -- Role Default Module Flags (strictly matching Mobile logic)
  v_can_cencom         boolean := false;
  v_can_vacancy        boolean := true;
  v_can_hr_emploc      boolean := false;
  v_can_plantilla      boolean := false;
  v_can_reports        boolean := false;
  v_can_approvals      boolean := false;
  v_can_users          boolean := false;

  -- Overrides
  v_has_override_tbl   boolean := false;
  v_override_cencom    text;
  v_override_vacancy   text;
  v_override_emploc    text;
  v_override_plantilla text;
  v_override_reports   text;
  v_override_users     text;
BEGIN
  -- Unauthenticated check
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

  -- Profile lookup
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

  -- Administrative Emergency Recovery: Super Admin email always remains active & level 100
  IF lower(trim(coalesce(v_email, ''))) = 'ohmpayatt@proton.me' THEN
    v_role_level := 100;
    v_role_name := 'Super Admin';
    v_is_active := TRUE;
    v_archived_at := NULL;
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
  v_norm_role := lower(regexp_replace(v_role_name, '[^a-zA-Z0-9]+', '_', 'g'));

  -- Scope evaluation
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

  -- --------------------------------------------------------------------------
  -- Strict Mobile RBAC Defaults
  -- --------------------------------------------------------------------------
  -- 1. Vacancy: All roles
  v_can_vacancy := true;

  -- 2. CENCOM: Super Admin, Head Admin, Encoder, OM, TL, ATL, Viewer.
  --    Strictly DENIED to HRCO, Recruitment, HR Personnel, Backoffice Personnel.
  v_can_cencom := (
    v_role_level >= 90 OR
    v_norm_role IN ('om', 'operations_manager', 'tl', 'atl', 'encoder', 'viewer')
  );

  -- 3. Reports: Always follows CENCOM
  v_can_reports := v_can_cencom;

  -- 4. HR Emploc: RolePermissions.canViewHrEmploc (Denied to Recruitment & Viewer; Allowed for all others)
  v_can_hr_emploc := (
    v_norm_role NOT IN ('recruitment', 'recruitment_team', 'viewer') AND
    v_role_level NOT IN (10, 20)
  );

  -- 5. Plantilla: RolePermissions.canViewPlantilla (hasFullAccess || isOpsTeam || isDataTeam || viewer)
  --    Allowed: SA, HA, OM, HRCO, ATL, TL, Encoder, Viewer.
  --    Denied: Recruitment, HR Personnel, Backoffice Personnel.
  v_can_plantilla := (
    v_role_level >= 90 OR
    v_norm_role IN ('om', 'operations_manager', 'hrco', 'atl', 'tl', 'encoder', 'viewer')
  );

  -- 6. Approvals Review Hub: Strictly limited to roles that review queues
  --    Allowed: Super Admin, Head Admin, Encoder, Backoffice Personnel (deactivations).
  --    Denied: OM, HRCO, ATL, TL, HR Personnel, Recruitment, Viewer.
  v_can_approvals := (
    v_role_level >= 90 OR
    v_norm_role IN ('encoder', 'backoffice', 'back_office', 'backoffice_personnel')
  );

  -- 7. User Management: SA & HA (v_role_level >= 90)
  v_can_users := (v_role_level >= 90);

  -- --------------------------------------------------------------------------
  -- Layer Access Control Center V1 (module_visibility_overrides) if present
  -- NOTE: Administrative Immunity Lock ensures SA (100) and HA (90) bypass overrides
  -- --------------------------------------------------------------------------
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'module_visibility_overrides'
  ) INTO v_has_override_tbl;

  IF v_has_override_tbl AND v_role_level < 90 AND lower(trim(coalesce(v_email, ''))) != 'ohmpayatt@proton.me' THEN
    SELECT
      max(CASE WHEN permission_key = 'cencom.view' THEN override_state END),
      max(CASE WHEN permission_key = 'vacancy.view' THEN override_state END),
      max(CASE WHEN permission_key = 'hr_emploc.view' THEN override_state END),
      max(CASE WHEN permission_key = 'plantilla.view' THEN override_state END),
      max(CASE WHEN permission_key = 'reports.view' THEN override_state END),
      max(CASE WHEN permission_key = 'user_management.view' THEN override_state END)
    INTO
      v_override_cencom,
      v_override_vacancy,
      v_override_emploc,
      v_override_plantilla,
      v_override_reports,
      v_override_users
    FROM public.module_visibility_overrides
    WHERE user_id = v_profile_id;

    IF v_override_cencom = 'allow' THEN v_can_cencom := true;
    ELSIF v_override_cencom = 'deny' THEN v_can_cencom := false; END IF;

    IF v_override_vacancy = 'allow' THEN v_can_vacancy := true;
    ELSIF v_override_vacancy = 'deny' THEN v_can_vacancy := false; END IF;

    IF v_override_emploc = 'allow' THEN v_can_hr_emploc := true;
    ELSIF v_override_emploc = 'deny' THEN v_can_hr_emploc := false; END IF;

    IF v_override_plantilla = 'allow' THEN v_can_plantilla := true;
    ELSIF v_override_plantilla = 'deny' THEN v_can_plantilla := false; END IF;

    IF v_override_reports = 'allow' THEN v_can_reports := true;
    ELSIF v_override_reports = 'deny' THEN v_can_reports := false;
    ELSE v_can_reports := v_can_cencom; END IF;

    IF v_override_users = 'allow' THEN v_can_users := true;
    ELSIF v_override_users = 'deny' THEN v_can_users := false; END IF;
  END IF;

  -- --------------------------------------------------------------------------
  -- Administrative Immunity Lock:
  -- Super Admin (100) and Head Admin (90) unconditionally own all modules
  -- --------------------------------------------------------------------------
  IF v_role_level >= 90 OR lower(trim(coalesce(v_email, ''))) = 'ohmpayatt@proton.me' THEN
    v_can_cencom := true;
    v_can_vacancy := true;
    v_can_hr_emploc := true;
    v_can_plantilla := true;
    v_can_approvals := true;
    v_can_users := true;
    v_can_reports := true;
  END IF;

  -- --------------------------------------------------------------------------
  -- Assemble Allowed Module Keys in Canonical Presentation Order
  -- --------------------------------------------------------------------------
  v_allowed_modules := ARRAY['dashboard']::text[];

  IF v_can_cencom THEN
    v_allowed_modules := array_append(v_allowed_modules, 'cencom');
  END IF;

  IF v_can_vacancy THEN
    v_allowed_modules := array_append(v_allowed_modules, 'vacancy');
  END IF;

  IF v_can_hr_emploc THEN
    v_allowed_modules := array_append(v_allowed_modules, 'hr_emploc');
  END IF;

  IF v_can_plantilla THEN
    v_allowed_modules := array_append(v_allowed_modules, 'plantilla');
  END IF;

  IF v_can_approvals THEN
    v_allowed_modules := array_append(v_allowed_modules, 'approvals');
  END IF;

  IF v_can_users THEN
    v_allowed_modules := array_append(v_allowed_modules, 'users');
  END IF;

  -- Team Directory allowed for all authenticated roles (role_level >= 10)
  IF v_role_level >= 10 THEN
    v_allowed_modules := array_append(v_allowed_modules, 'team_directory');
  END IF;

  v_allowed_modules := array_append(v_allowed_modules, 'notifications');

  IF v_can_reports THEN
    v_allowed_modules := array_append(v_allowed_modules, 'reports');
  END IF;

  v_allowed_modules := array_append(v_allowed_modules, 'settings');
  v_allowed_modules := array_append(v_allowed_modules, 'more');

  -- --------------------------------------------------------------------------
  -- Capability Snapshot (Preserve detailed RPC capabilities without leaking)
  -- --------------------------------------------------------------------------
  WITH web_capabilities AS (
    SELECT
      CASE d.module_key
        WHEN 'dashboard' THEN 'dashboard'
        WHEN 'cencom' THEN 'cencom'
        WHEN 'vacancy' THEN
          CASE
            -- Only map approve_closure to approvals if user is an authorized reviewer
            WHEN d.action_key IN ('approve_closure') AND v_can_approvals THEN 'approvals'
            ELSE 'vacancy'
          END
        WHEN 'hr_emploc' THEN 'hr_emploc'
        WHEN 'plantilla' THEN 'plantilla'
        WHEN 'deactivation' THEN
          -- Strictly deactivation process/review maps to approvals, NEVER request create
          CASE
            WHEN d.action_key = 'process' AND v_can_approvals THEN 'approvals'
            ELSE 'plantilla'
          END
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
  filtered_capabilities AS (
    SELECT web_module_key, capability
    FROM web_capabilities
    WHERE web_module_key = ANY(v_allowed_modules)
  ),
  module_payload AS (
    SELECT web_module_key, jsonb_agg(capability ORDER BY capability->>'resource_key', capability->>'action_key') AS capabilities
    FROM filtered_capabilities
    GROUP BY web_module_key
  )
  SELECT
    COALESCE(jsonb_object_agg(web_module_key, capabilities), '{}'::jsonb)
  INTO v_capabilities
  FROM module_payload;

  RETURN QUERY
  SELECT
    v_auth_uid,
    v_profile_id,
    v_email,
    v_full_name,
    v_norm_role,
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
  'Provides safe, read-only current-user context for the OHMployee Web presentation shell with 100% Mobile RBAC parity and administrative immunity.';

REVOKE ALL ON FUNCTION public.get_web_current_user_context() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_current_user_context() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_current_user_context() TO authenticated;
