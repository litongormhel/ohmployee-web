-- Migration: 20262606000077_fn_get_recent_activity.sql
-- Purpose: Scoped Recent Activity Feed RPC (Phase 2B-1)
-- Returns allow-listed operational activity events strictly scoped to caller's allowed modules and jurisdictions,
-- with per-transaction entity deduplication, 5-minute window batching, and Option A account_requests union.

-- Performance index for account-scoped audit log scans
CREATE INDEX IF NOT EXISTS idx_audit_logs_account_ts ON public.audit_logs USING btree ((((new_data ->> 'account_id'::text))::uuid), "timestamp" DESC) WHERE ((new_data ->> 'account_id'::text) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::text);

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
  v_limit               int := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 50);
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
  WITH audit_events AS (
    SELECT
      al.id,
      al.timestamp,
      al.module,
      al.action::text,
      d.event_type,
      d.priority,
      al.record_id::text,
      al.actor_id,
      al.new_data,
      al.old_data,
      COALESCE(
        NULLIF(TRIM(al.new_data->>'vcode'), ''),
        NULLIF(TRIM(al.old_data->>'vcode'), ''),
        NULLIF(TRIM(al.new_data->>'employee_no'), ''),
        NULLIF(TRIM(al.old_data->>'employee_no'), ''),
        NULLIF(TRIM(al.new_data->>'full_name'), ''),
        NULLIF(TRIM(al.old_data->>'full_name'), ''),
        al.record_id::text
      ) AS entity_key,
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
      SELECT
        CASE
          -- Module: User Management (audit_logs stream: user creation, role updates, archives)
          WHEN al.module = 'User Management' AND al.action::text IN ('APPROVE_REQUEST', 'APPROVE_USER_REQUEST', 'approved new user') THEN 'user_approved'
          WHEN al.module = 'User Management' AND al.action::text = 'CREATE_USER' THEN 'user_created'
          WHEN al.module = 'User Management' AND al.action::text = 'UPDATE_USER_ROLE' THEN 'user_role_updated'
          WHEN al.module = 'User Management' AND al.action::text IN ('REJECT_REQUEST', 'REJECT_USER', 'rejected user') THEN 'user_rejected'
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
              WHEN (al.new_data->>'status' = 'Moved to Plantilla' OR al.new_data->>'hr_status' = 'Transferred') AND COALESCE(al.old_data->>'status', '') <> 'Moved to Plantilla' THEN 'plantilla_deployed'
              WHEN al.old_data->>'status' = 'Moved to Plantilla' AND al.new_data->>'status' = 'Pending Emploc' THEN 'emploc_reverted'
              ELSE NULL
            END

          ELSE NULL
        END AS event_type,

        CASE
          WHEN al.module = 'plantilla' AND al.action::text = 'INSERT' THEN 1
          WHEN al.module = 'hr_emploc' AND (al.new_data->>'status' = 'Moved to Plantilla' OR al.new_data->>'hr_status' = 'Transferred') THEN 1
          WHEN al.module = 'plantilla' AND (al.action::text = 'SOFT_DELETE' OR (al.action::text = 'UPDATE' AND al.new_data->>'status' IN ('Inactive', 'Deactivated'))) THEN 2
          WHEN al.module = 'vacancies' AND (al.action::text = 'APPROVAL' OR (al.action::text = 'UPDATE' AND al.new_data->>'status' = 'Filled')) THEN 3
          WHEN al.module = 'hr_emploc' AND al.new_data->>'hr_status' = 'Complete' THEN 4
          WHEN al.module = 'hr_emploc' AND al.new_data->>'hr_status' IN ('For Review', 'For Correction') THEN 5
          WHEN al.module = 'hr_emploc' AND al.old_data->>'status' = 'Moved to Plantilla' AND al.new_data->>'status' = 'Pending Emploc' THEN 6
          WHEN al.module = 'vacancies' THEN 7
          WHEN al.module = 'plantilla' THEN 8
          WHEN al.module = 'hr_emploc' THEN 9
          WHEN al.module = 'User Management' THEN 10
          ELSE 99
        END AS priority
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
        -- User Management: Approvals visible to Data Team + Encoder; Role changes and archives visible to SA/HA only
        (
          al.module = 'User Management'
          AND p_group_id IS NULL
          AND p_account_id IS NULL
          AND (
            (d.event_type = 'user_approved' AND v_is_data_team)
            OR
            (d.event_type IN ('user_role_updated', 'user_archived', 'user_created', 'user_rejected') AND v_is_admin)
          )
        )
        OR
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
  ),
  account_request_events AS (
    SELECT
      ar.id,
      ar.approved_at AS "timestamp",
      'User Management'::text AS module,
      'APPROVE_REQUEST'::text AS action,
      'user_approved'::text AS event_type,
      10::integer AS priority,
      ar.id::text AS record_id,
      ar.approved_by AS actor_id,
      jsonb_build_object(
        'full_name', ar.full_name,
        'role_name', r.role_name
      ) AS new_data,
      '{}'::jsonb AS old_data,
      ar.full_name AS entity_key,
      CASE
        WHEN jsonb_typeof(ar.assigned_accounts_snapshot) = 'array'
             AND jsonb_array_length(ar.assigned_accounts_snapshot) > 0
             AND (ar.assigned_accounts_snapshot->>0) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (ar.assigned_accounts_snapshot->>0)::uuid
        ELSE NULL
      END AS parsed_account_id,
      NULL::uuid AS parsed_store_id
    FROM public.account_requests ar
    LEFT JOIN public.roles r ON r.id = ar.assigned_role_id
    WHERE v_is_data_team
      AND ar.status = 'approved'
      AND ar.approved_at >= (now() - interval '30 days')
      AND (
        p_group_id IS NULL
        OR (
          jsonb_typeof(ar.assigned_groups_snapshot) = 'array'
          AND ar.assigned_groups_snapshot ? p_group_id::text
        )
      )
      AND (
        p_account_id IS NULL
        OR (
          jsonb_typeof(ar.assigned_accounts_snapshot) = 'array'
          AND ar.assigned_accounts_snapshot ? p_account_id::text
        )
      )
      AND (
        v_is_admin
        OR (
          p_group_id IS NOT NULL
          OR p_account_id IS NOT NULL
          OR (
            jsonb_typeof(ar.assigned_groups_snapshot) = 'array'
            AND EXISTS (
              SELECT 1
              FROM jsonb_array_elements_text(ar.assigned_groups_snapshot) g_id
              WHERE g_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                AND g_id::uuid = ANY(v_allowed_groups)
            )
          )
          OR (
            jsonb_typeof(ar.assigned_accounts_snapshot) = 'array'
            AND EXISTS (
              SELECT 1
              FROM jsonb_array_elements_text(ar.assigned_accounts_snapshot) acc_id
              WHERE acc_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                AND acc_id::uuid = ANY(v_allowed_accounts)
            )
          )
        )
      )
  ),
  parsed_events AS (
    SELECT * FROM audit_events
    UNION ALL
    SELECT * FROM account_request_events
  ),
  deduped AS (
    SELECT
      pe.id,
      pe.timestamp,
      pe.module,
      pe.action,
      pe.event_type,
      pe.priority,
      pe.record_id,
      pe.actor_id,
      pe.new_data,
      pe.old_data,
      pe.parsed_account_id,
      pe.parsed_store_id,
      pe.entity_key,
      ROW_NUMBER() OVER (
        PARTITION BY pe.timestamp, pe.entity_key
        ORDER BY
          pe.priority ASC,
          (CASE WHEN pe.module = 'plantilla' THEN 0 ELSE 1 END) ASC,
          pe.id ASC
      ) AS rn
    FROM parsed_events pe
  ),
  bucketed AS (
    SELECT
      dd.id,
      dd.timestamp,
      dd.module,
      dd.action,
      dd.event_type,
      dd.record_id,
      dd.actor_id,
      dd.new_data,
      dd.old_data,
      dd.parsed_account_id,
      dd.parsed_store_id,
      -- Employee subjects (do NOT put vacancy position in subject_name)
      CASE
        WHEN dd.module = 'vacancies' THEN NULL
        ELSE COALESCE(
          NULLIF(TRIM(dd.new_data->>'full_name'), ''),
          NULLIF(TRIM(dd.new_data->>'employee_name'), ''),
          NULLIF(TRIM(dd.new_data->>'applicant_name'), ''),
          NULLIF(TRIM(dd.old_data->>'full_name'), '')
        )
      END AS subject_name,
      CASE
        WHEN dd.module = 'vacancies' THEN NULL
        ELSE COALESCE(
          NULLIF(TRIM(dd.new_data->>'employee_no'), ''),
          NULLIF(TRIM(dd.new_data->>'emploc_no'), ''),
          NULLIF(TRIM(dd.old_data->>'employee_no'), '')
        )
      END AS subject_employee_no,
      -- Vacancy specific fields
      CASE
        WHEN dd.module = 'vacancies' THEN COALESCE(NULLIF(TRIM(dd.new_data->>'vcode'), ''), NULLIF(TRIM(dd.old_data->>'vcode'), ''))
        ELSE NULL
      END AS vacancy_vcode,
      CASE
        WHEN dd.module = 'vacancies' THEN COALESCE(NULLIF(TRIM(dd.new_data->>'position'), ''), NULLIF(TRIM(dd.old_data->>'position'), ''))
        ELSE NULL
      END AS vacancy_position,
      CASE
        WHEN dd.module = 'vacancies' THEN COALESCE(NULLIF(TRIM(dd.new_data->>'store_name'), ''), NULLIF(TRIM(dd.old_data->>'store_name'), ''))
        ELSE NULL
      END AS vacancy_store,
      date_bin(interval '5 minutes', dd.timestamp, timestamptz '2000-01-01 00:00:00Z') AS time_bucket,
      ROW_NUMBER() OVER (
        PARTITION BY
          dd.actor_id,
          dd.event_type,
          dd.parsed_account_id,
          date_bin(interval '5 minutes', dd.timestamp, timestamptz '2000-01-01 00:00:00Z')
        ORDER BY dd.timestamp DESC, dd.id DESC
      ) AS sample_rn
    FROM deduped dd
    WHERE dd.rn = 1
  ),
  batched AS (
    SELECT
      (array_agg(b.id ORDER BY b.timestamp DESC, b.id DESC))[1] AS id,
      MAX(b.timestamp) AS timestamp,
      (array_agg(b.module ORDER BY b.timestamp DESC, b.id DESC))[1] AS module,
      (array_agg(b.action ORDER BY b.timestamp DESC, b.id DESC))[1] AS action,
      b.event_type,
      (array_agg(b.record_id ORDER BY b.timestamp DESC, b.id DESC))[1] AS record_id,
      b.actor_id,
      b.parsed_account_id,
      (array_agg(b.parsed_store_id ORDER BY b.timestamp DESC, b.id DESC))[1] AS parsed_store_id,
      (array_agg(b.new_data ORDER BY b.timestamp DESC, b.id DESC))[1] AS rep_new_data,
      (array_agg(b.old_data ORDER BY b.timestamp DESC, b.id DESC))[1] AS rep_old_data,
      COUNT(*)::integer AS batch_count,
      jsonb_agg(
        CASE
          WHEN b.module = 'vacancies' THEN
            jsonb_build_object(
              'vcode', b.vacancy_vcode,
              'position', b.vacancy_position,
              'store_name', b.vacancy_store
            )
          ELSE
            jsonb_build_object(
              'name', b.subject_name,
              'employee_no', b.subject_employee_no
            )
        END
        ORDER BY b.timestamp DESC, b.id DESC
      ) FILTER (WHERE b.sample_rn <= 3 AND (b.subject_name IS NOT NULL OR b.vacancy_vcode IS NOT NULL)) AS samples
    FROM bucketed b
    GROUP BY
      b.actor_id,
      b.event_type,
      b.parsed_account_id,
      b.time_bucket
  ),
  candidates AS (
    SELECT bt.*
    FROM batched bt
    ORDER BY bt.timestamp DESC
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
      'subject', COALESCE(c.rep_new_data->>'full_name', c.rep_new_data->>'employee_name', c.rep_new_data->>'applicant_name', c.rep_old_data->>'full_name'),
      'employee_no', COALESCE(c.rep_new_data->>'employee_no', c.rep_new_data->>'emploc_no', c.rep_old_data->>'employee_no'),
      'account_name', a.account_name,
      'store_name', COALESCE(c.rep_new_data->>'store_name', c.rep_old_data->>'store_name', s.store_name),
      'position', COALESCE(c.rep_new_data->>'position', c.rep_old_data->>'position'),
      'vcode', COALESCE(c.rep_new_data->>'vcode', c.rep_old_data->>'vcode'),
      'target_role', COALESCE(c.rep_new_data->>'role_name', c.rep_old_data->>'role'),
      'is_pool', COALESCE(a.is_pool_account, FALSE),
      'batch_count', c.batch_count,
      'samples', COALESCE(c.samples, '[]'::jsonb)
    ) AS details
  FROM candidates c
  LEFT JOIN public.users_profile up ON up.auth_user_id = c.actor_id
  LEFT JOIN public.roles r ON r.id = up.role_id
  LEFT JOIN public.accounts a ON a.id = c.parsed_account_id
  LEFT JOIN public.stores s ON s.id = c.parsed_store_id
  ORDER BY c.timestamp DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_get_recent_activity(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_recent_activity(uuid, uuid, integer) TO authenticated;
