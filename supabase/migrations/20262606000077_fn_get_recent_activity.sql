-- Migration: 20262606000077_fn_get_recent_activity.sql
-- Purpose: Scoped Recent Activity Feed RPC (Phase 2B-1)
-- Returns whitelisted operational activity events strictly scoped to caller's allowed modules and jurisdictions.

CREATE OR REPLACE FUNCTION public.fn_get_recent_activity(
  p_group_id   uuid DEFAULT NULL::uuid,
  p_account_id uuid DEFAULT NULL::uuid,
  p_limit      integer DEFAULT 10
)
RETURNS TABLE (
  id          uuid,
  "timestamp" timestamp with time zone,
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
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_uid          uuid := auth.uid();
  v_caller_pid          uuid;
  v_role_level          int;
  v_norm_role           text;
  v_is_admin            boolean;
  v_is_data_team        boolean;
  v_has_scopes          boolean;
  v_allowed_groups      uuid[];
  v_allowed_accounts    uuid[];
  v_target_account_ids  uuid[];
  v_allowed_modules     text[];
  v_limit               int := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 10);
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

  -- 3. Resolve target account scope (fail-closed if non-admin has no active scopes)
  IF v_is_admin THEN
    IF p_account_id IS NOT NULL THEN
      v_target_account_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(a.id) INTO v_target_account_ids
      FROM public.accounts a
      WHERE a.group_id = p_group_id;
    ELSE
      v_target_account_ids := NULL; -- Admin global unscoped
    END IF;
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

    -- Non-admin accounts strictly within caller jurisdiction:
    SELECT array_agg(a.id) INTO v_target_account_ids
    FROM public.accounts a
    WHERE (p_group_id IS NULL OR a.group_id = p_group_id)
      AND (p_account_id IS NULL OR a.id = p_account_id)
      AND (
        (a.group_id IS NOT NULL AND a.group_id = ANY(v_allowed_groups))
        OR (a.id = ANY(v_allowed_accounts))
      )
      AND COALESCE(a.is_pool_account, FALSE) = FALSE; -- Non-admins never see pool accounts

    IF v_target_account_ids IS NULL OR array_length(v_target_account_ids, 1) = 0 THEN
      -- If caller is Data Team/Encoder, they may still see unscoped User Management approvals if no filters are applied
      IF NOT (v_is_data_team AND p_group_id IS NULL AND p_account_id IS NULL) THEN
        RETURN;
      END IF;
    END IF;
  END IF;

  -- 4. Execute query with early-stopping ordered index scan (30-day window)
  RETURN QUERY
  WITH candidates AS (
    SELECT
      al.id,
      al.timestamp,
      al.module,
      al.action::text,
      d.event_type,
      al.record_id::text,
      al.actor_id,
      al.new_data,
      al.old_data,
      CASE
        WHEN (al.new_data->>'account_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (al.new_data->>'account_id')::uuid
        WHEN (al.old_data->>'account_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (al.old_data->>'account_id')::uuid
        ELSE NULL
      END AS parsed_account_id,
      CASE
        WHEN (al.new_data->>'store_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (al.new_data->>'store_id')::uuid
        WHEN (al.old_data->>'store_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (al.old_data->>'store_id')::uuid
        ELSE NULL
      END AS parsed_store_id
    FROM public.audit_logs al
    CROSS JOIN LATERAL (
      SELECT CASE
        -- Module: User Management
        WHEN al.module = 'User Management' AND al.action::text IN ('CREATE_USER', 'approved new user') THEN 'user_approved'
        WHEN al.module = 'User Management' AND al.action::text = 'UPDATE_USER_ROLE' THEN
          CASE
            WHEN al.old_data->>'role' IS NULL OR al.old_data->>'role_id' IS NULL THEN 'user_approved'
            ELSE 'user_role_updated'
          END
        WHEN al.module = 'User Management' AND al.action::text IN ('rejected user', 'REJECT_USER', 'REJECT_REQUEST') THEN 'user_rejected'
        WHEN al.module = 'User Management' AND al.action::text = 'ARCHIVE_USER' THEN 'user_archived'

        -- Module: plantilla
        WHEN al.module = 'plantilla' AND al.action::text = 'INSERT' THEN 'plantilla_deployed'
        WHEN al.module = 'plantilla' AND al.action::text = 'SOFT_DELETE' THEN 'plantilla_deactivated'
        WHEN al.module = 'plantilla' AND al.action::text = 'UPDATE' THEN
          CASE
            WHEN al.new_data->>'status' IN ('Inactive', 'Deactivated') AND COALESCE(al.old_data->>'status', '') NOT IN ('Inactive', 'Deactivated') THEN 'plantilla_separation'
            WHEN al.new_data->>'status' = 'On Leave' AND COALESCE(al.old_data->>'status', '') <> 'On Leave' THEN 'plantilla_on_leave'
            WHEN al.new_data->>'status' = 'Pending Deactivation' AND COALESCE(al.old_data->>'status', '') <> 'Pending Deactivation' THEN 'plantilla_deactivation_requested'
            ELSE NULL
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
            ELSE NULL
          END

        ELSE NULL
      END AS event_type
    ) d
    WHERE al.timestamp >= (now() - interval '30 days')
      AND al.module IN ('plantilla', 'vacancies', 'hr_emploc', 'User Management')
      AND d.event_type IS NOT NULL
      -- Canonical module access gate
      AND (
        (al.module = 'plantilla' AND 'plantilla' = ANY(v_allowed_modules))
        OR (al.module = 'hr_emploc' AND 'hr_emploc' = ANY(v_allowed_modules))
        OR (al.module = 'vacancies' AND 'vacancy' = ANY(v_allowed_modules))
        OR (al.module = 'User Management' AND (v_is_data_team OR 'users' = ANY(v_allowed_modules)))
      )
      -- Jurisdictional filtering:
      AND (
        -- User Management: Data team only, unscoped
        (
          al.module = 'User Management'
          AND v_is_data_team
          AND p_group_id IS NULL
          AND p_account_id IS NULL
        )
        OR
        -- Operational / Scoped events:
        (
          al.module != 'User Management'
          AND (
            v_target_account_ids IS NULL
            OR (
              (CASE
                WHEN (al.new_data->>'account_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN (al.new_data->>'account_id')::uuid
                WHEN (al.old_data->>'account_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN (al.old_data->>'account_id')::uuid
                ELSE NULL
              END) = ANY(v_target_account_ids)
            )
          )
        )
      )
    ORDER BY al.timestamp DESC
    LIMIT v_limit
  )
  SELECT
    c.id,
    c.timestamp,
    c.module,
    c.action,
    c.event_type,
    c.record_id,
    COALESCE(up.full_name, 'System') AS actor_name,
    COALESCE(r.role_name, 'System') AS actor_role,
    jsonb_build_object(
      'subject', COALESCE(c.new_data->>'full_name', c.new_data->>'employee_name', c.new_data->>'applicant_name', c.old_data->>'full_name'),
      'employee_no', COALESCE(c.new_data->>'employee_no', c.new_data->>'emploc_no', c.old_data->>'employee_no'),
      'account_name', a.account_name,
      'store_name', s.store_name,
      'position', COALESCE(c.new_data->>'position', c.old_data->>'position'),
      'vcode', COALESCE(c.new_data->>'vcode', c.old_data->>'vcode'),
      'target_role', COALESCE(c.new_data->>'role_name', c.old_data->>'role'),
      'is_pool', COALESCE(a.is_pool_account, FALSE)
    ) AS details
  FROM candidates c
  LEFT JOIN public.users_profile up ON up.auth_user_id = c.actor_id
  LEFT JOIN public.roles r ON r.id = up.role_id
  LEFT JOIN public.accounts a ON a.id = c.parsed_account_id
  LEFT JOIN public.stores s ON s.id = c.parsed_store_id
  ORDER BY c.timestamp DESC;
END;
$function$;
