-- Migration: 20262606000077_fn_get_recent_activity.sql
-- Purpose: Scoped Recent Activity Feed RPC (Phase 2B-1)
-- Returns whitelisted operational activity events strictly scoped to caller's allowed modules and jurisdictions.

CREATE OR REPLACE FUNCTION public.fn_get_recent_activity(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL,
  p_limit      int  DEFAULT 10
)
RETURNS TABLE (
  id          uuid,
  "timestamp" timestamptz,
  module      text,
  action      text,
  event_type  text,
  record_id   text,
  actor_name  text,
  actor_role  text,
  details     jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_uid       uuid := auth.uid();
  v_caller_pid       uuid;
  v_role_level       int;
  v_norm_role        text;
  v_is_admin         boolean;
  v_is_data_team     boolean;
  v_has_scopes       boolean;
  v_allowed_groups   uuid[];
  v_allowed_accounts uuid[];
  v_allowed_modules  text[];
  v_limit            int := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 10);
BEGIN
  -- 1. Authenticate caller
  IF v_caller_uid IS NULL THEN
    RETURN;
  END IF;

  SELECT
    up.id,
    r.role_level,
    lower(regexp_replace(r.role_name, '[^a-zA-Z0-9]+', '_', 'g'))
  INTO
    v_caller_pid,
    v_role_level,
    v_norm_role
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_caller_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_caller_pid IS NULL OR v_role_level IS NULL THEN
    RETURN;
  END IF;

  v_is_admin := (v_role_level >= 90 OR public.i_have_full_access());
  v_is_data_team := (v_norm_role IN ('encoder', 'head_admin', 'super_admin'));

  -- 2. Derive allowed modules canonically from get_web_current_user_context
  SELECT allowed_module_keys INTO v_allowed_modules
  FROM public.get_web_current_user_context();

  -- 3. Resolve caller scopes (fail-closed if non-admin has no active scopes)
  IF v_is_admin THEN
    SELECT array_agg(g.id) INTO v_allowed_groups FROM public.groups g;
    SELECT array_agg(a.id) INTO v_allowed_accounts FROM public.accounts a;
  ELSE
    SELECT
      EXISTS(SELECT 1 FROM public.user_scopes WHERE user_id = v_caller_pid AND is_active = TRUE),
      array_agg(DISTINCT us.group_id) FILTER (WHERE us.group_id IS NOT NULL),
      array_agg(DISTINCT us.account_id) FILTER (WHERE us.account_id IS NOT NULL)
    INTO
      v_has_scopes,
      v_allowed_groups,
      v_allowed_accounts
    FROM public.user_scopes us
    WHERE us.user_id = v_caller_pid
      AND us.is_active = TRUE;

    IF NOT COALESCE(v_has_scopes, FALSE) THEN
      RETURN; -- Fail closed: non-admin without active scopes sees nothing
    END IF;
  END IF;

  -- 4. Execute query with pre-limit indexed scan (30-day window) and per-module allow-list
  RETURN QUERY
  WITH scoped_raw AS (
    SELECT
      al.id,
      al.timestamp,
      al.module,
      al.action::text,
      al.record_id::text,
      al.actor_id,
      al.new_data,
      al.old_data,
      -- Determine normalized event_type based on allow-list
      CASE
        -- Module: User Management (CREATE_USER or UPDATE_USER_ROLE)
        WHEN al.module = 'User Management' AND al.action::text IN ('CREATE_USER', 'UPDATE_USER_ROLE') THEN
          CASE
            WHEN al.old_data->>'role' IS NULL OR al.old_data->>'role_id' IS NULL THEN 'user_approved'
            ELSE 'user_role_updated'
          END
        WHEN al.module = 'User Management' AND al.action::text = 'ARCHIVE_USER' THEN 'user_archived'

        -- Module: plantilla
        WHEN al.module = 'plantilla' AND al.action::text = 'INSERT' THEN 'plantilla_deployed'
        WHEN al.module = 'plantilla' AND al.action::text = 'SOFT_DELETE' THEN 'plantilla_deactivated'
        WHEN al.module = 'plantilla' AND al.action::text = 'UPDATE' THEN
          CASE
            WHEN al.new_data->>'status' IN ('Inactive', 'Deactivated') AND COALESCE(al.old_data->>'status', '') NOT IN ('Inactive', 'Deactivated') THEN 'plantilla_separation'
            WHEN al.new_data->>'status' = 'On Leave' AND COALESCE(al.old_data->>'status', '') <> 'On Leave' THEN 'plantilla_on_leave'
            WHEN al.new_data->>'status' = 'Pending Deactivation' AND COALESCE(al.old_data->>'status', '') <> 'Pending Deactivation' THEN 'plantilla_deactivation_requested'
            ELSE NULL -- Exclude unmapped / noisy plantilla updates
          END

        -- Module: vacancies
        WHEN al.module = 'vacancies' AND al.action::text = 'INSERT' THEN 'vacancy_opened'
        WHEN al.module = 'vacancies' AND (al.action::text = 'APPROVAL' OR (al.action::text = 'UPDATE' AND al.new_data->>'status' = 'Filled' AND COALESCE(al.old_data->>'status', '') <> 'Filled')) THEN 'vacancy_filled'
        WHEN al.module = 'vacancies' AND al.action::text = 'UPDATE' AND al.new_data->>'status' IN ('Closed', 'Archived') AND COALESCE(al.old_data->>'status', '') NOT IN ('Closed', 'Archived') THEN 'vacancy_closed'
        WHEN al.module = 'vacancies' AND al.action::text = 'UPDATE' AND al.new_data->>'status' = 'Open' AND al.old_data->>'status' IN ('Filled', 'Closed', 'Archived') THEN 'vacancy_reopened'

        -- Module: hr_emploc
        WHEN al.module = 'hr_emploc' AND al.action::text = 'INSERT' THEN 'emploc_created'
        WHEN al.module = 'hr_emploc' AND al.action::text = 'UPDATE' THEN
          CASE
            WHEN al.new_data->>'hr_status' = 'For Correction' AND COALESCE(al.old_data->>'hr_status', '') <> 'For Correction' THEN 'emploc_for_correction'
            WHEN al.new_data->>'hr_status' = 'For Review' AND COALESCE(al.old_data->>'hr_status', '') <> 'For Review' THEN 'emploc_for_review'
            WHEN al.new_data->>'hr_status' = 'Complete' AND COALESCE(al.old_data->>'hr_status', '') <> 'Complete' THEN 'emploc_approved'
            WHEN (al.new_data->>'status' = 'Moved to Plantilla' OR al.new_data->>'hr_status' = 'Transferred') AND COALESCE(al.old_data->>'status', '') <> 'Moved to Plantilla' THEN 'emploc_deployed'
            WHEN al.old_data->>'status' = 'Moved to Plantilla' AND al.new_data->>'status' = 'Pending Emploc' THEN 'emploc_reverted'
            ELSE NULL -- Exclude unmapped updates
          END

        ELSE NULL -- Fail closed for all other unmapped module/action pairs
      END AS derived_event_type,

      -- Safe JSONB UUID parsing for account_id
      CASE
        WHEN (al.new_data->>'account_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (al.new_data->>'account_id')::uuid
        WHEN (al.old_data->>'account_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (al.old_data->>'account_id')::uuid
        ELSE COALESCE(p.account_id, v.account_id, he.account_id)
      END AS derived_account_id,

      -- Safe JSONB UUID parsing for store_id
      CASE
        WHEN (al.new_data->>'store_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (al.new_data->>'store_id')::uuid
        WHEN (al.old_data->>'store_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (al.old_data->>'store_id')::uuid
        ELSE COALESCE(v.store_id, p.store_id)
      END AS derived_store_id
    FROM public.audit_logs al
    LEFT JOIN public.plantilla p ON (al.module = 'plantilla' AND p.id = al.record_id)
    LEFT JOIN public.vacancies v ON (al.module = 'vacancies' AND v.id = al.record_id)
    LEFT JOIN public.hr_emploc he ON (al.module = 'hr_emploc' AND he.id = al.record_id)
    WHERE al.timestamp >= (now() - interval '30 days')
      AND al.module IN ('plantilla', 'vacancies', 'hr_emploc', 'User Management')
      -- Authoritative canonical module access gate:
      AND (
        (al.module = 'plantilla' AND 'plantilla' = ANY(v_allowed_modules))
        OR (al.module = 'hr_emploc' AND 'hr_emploc' = ANY(v_allowed_modules))
        OR (al.module = 'vacancies' AND 'vacancy' = ANY(v_allowed_modules))
        OR (al.module = 'User Management' AND (v_is_data_team OR 'users' = ANY(v_allowed_modules)))
      )
  ),
  allow_listed AS (
    SELECT * FROM scoped_raw
    WHERE derived_event_type IS NOT NULL -- Drops unmapped actions completely
  ),
  enriched AS (
    SELECT
      alw.id,
      alw.timestamp,
      alw.module,
      alw.action,
      alw.derived_event_type AS event_type,
      alw.record_id,
      COALESCE(up.full_name, 'System') AS actor_name,
      COALESCE(r.role_name, 'System') AS actor_role,
      alw.derived_account_id,
      COALESCE(s.group_id, a.group_id) AS derived_group_id,
      a.account_name,
      s.store_name,
      COALESCE(a.is_pool_account, FALSE) AS is_pool,
      alw.new_data,
      alw.old_data
    FROM allow_listed alw
    LEFT JOIN public.users_profile up ON up.auth_user_id = alw.actor_id
    LEFT JOIN public.roles r ON r.id = up.role_id
    LEFT JOIN public.accounts a ON a.id = alw.derived_account_id
    LEFT JOIN public.stores s ON s.id = alw.derived_store_id
  )
  SELECT
    e.id,
    e.timestamp,
    e.module,
    e.action,
    e.event_type,
    e.record_id,
    e.actor_name,
    e.actor_role,
    jsonb_build_object(
      'subject', COALESCE(e.new_data->>'full_name', e.new_data->>'employee_name', e.new_data->>'applicant_name', e.old_data->>'full_name'),
      'employee_no', COALESCE(e.new_data->>'employee_no', e.new_data->>'emploc_no', e.old_data->>'employee_no'),
      'account_name', e.account_name,
      'store_name', e.store_name,
      'position', COALESCE(e.new_data->>'position', e.old_data->>'position'),
      'vcode', COALESCE(e.new_data->>'vcode', e.old_data->>'vcode'),
      'target_role', COALESCE(e.new_data->>'role_name', e.old_data->>'role'),
      'is_pool', e.is_pool
    ) AS details
  FROM enriched e
  WHERE
    -- 1. User Management approvals/role updates: Data Team & Encoder only
    -- If a specific group/account is filtered in Scope dropdown, user approvals disappear (expected)
    (
      e.module = 'User Management'
      AND v_is_data_team
      AND p_group_id IS NULL
      AND p_account_id IS NULL
    )
    OR
    -- 2. Pool / Moses HQ events: SA/HA only
    (
      e.is_pool = TRUE
      AND v_is_admin
      AND (p_group_id IS NULL OR e.derived_group_id = p_group_id)
      AND (p_account_id IS NULL OR e.derived_account_id = p_account_id)
    )
    OR
    -- 3. Operational events: scoped to user's assigned groups or accounts
    (
      e.module != 'User Management'
      AND e.is_pool = FALSE
      AND (
        v_is_admin
        OR (e.derived_group_id IS NOT NULL AND e.derived_group_id = ANY(v_allowed_groups))
        OR (e.derived_account_id IS NOT NULL AND e.derived_account_id = ANY(v_allowed_accounts))
      )
      AND (p_group_id IS NULL OR e.derived_group_id = p_group_id)
      AND (p_account_id IS NULL OR e.derived_account_id = p_account_id)
    )
  ORDER BY e.timestamp DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_recent_activity(uuid, uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_recent_activity(uuid, uuid, int) TO authenticated;
