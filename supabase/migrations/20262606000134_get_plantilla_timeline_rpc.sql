-- Migration: 20262606000134_get_plantilla_timeline_rpc.sql
-- Description: Unified Plantilla Activity Timeline RPC for Mobile and Web Parity
-- Aggregates operational lifecycle mutations from audit_logs, employee_transfers,
-- employee_deactivation_requests, plantilla, and employee_activity_log.

CREATE OR REPLACE FUNCTION public.get_plantilla_timeline(p_plantilla_id uuid)
RETURNS TABLE (
  id text,
  activity_type text,
  description text,
  performed_by text,
  activity_date timestamptz,
  note text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH target_p AS (
    SELECT id, employee_no, position, date_hired, created_at, store_name, vcode, created_by
    FROM public.plantilla
    WHERE id = p_plantilla_id
  ),
  raw_events AS (
    -- 1. Status mutations from audit_logs
    SELECT
      a.id::text AS id,
      CASE
        WHEN a.new_data->>'status' = 'On Leave' THEN 'leave'
        WHEN a.new_data->>'status' = 'Active' THEN 'active'
        WHEN a.new_data->>'status' = 'Floating' THEN 'floating'
        WHEN a.new_data->>'status' IN ('Resigned', 'AWOL', 'Terminated') THEN 'separated'
        WHEN a.new_data->>'status' = 'Deactivated' THEN 'deactivated'
        ELSE 'updated'
      END AS activity_type,
      CASE
        WHEN a.new_data->>'status' = 'On Leave' THEN 'Tagged as On Leave'
        WHEN a.new_data->>'status' = 'Active' THEN 'Returned to Active'
        WHEN a.new_data->>'status' = 'Floating' THEN 'Transferred to Floating'
        WHEN a.new_data->>'status' IN ('Resigned', 'AWOL', 'Terminated') THEN 'Personnel Separated (' || (a.new_data->>'status') || ')'
        WHEN a.new_data->>'status' = 'Deactivated' THEN 'Personnel Deactivated'
        ELSE 'Status Changed: ' || (a.new_data->>'status')
      END AS description,
      COALESCE(up.full_name, up.email, a.role, 'System') AS performed_by,
      a.timestamp AS activity_date,
      CASE
        WHEN a.new_data->>'remarks' IS NOT NULL AND a.new_data->>'remarks' <> '' THEN 'Remarks: ' || (a.new_data->>'remarks')
        WHEN a.new_data->>'reason' IS NOT NULL AND a.new_data->>'reason' <> '' THEN 'Reason: ' || (a.new_data->>'reason')
        ELSE NULL
      END AS note
    FROM public.audit_logs a
    LEFT JOIN public.users_profile up ON (up.id = a.actor_id OR up.auth_user_id = a.actor_id)
    WHERE a.record_id = p_plantilla_id
      AND a.new_data->>'status' IS DISTINCT FROM a.old_data->>'status'
      AND a.new_data->>'status' IS NOT NULL

    UNION ALL

    -- 2. Schedule and rate updates from audit_logs
    SELECT
      a.id::text || '-sched' AS id,
      'schedule' AS activity_type,
      'Schedule & Allocation Updated' AS description,
      COALESCE(up.full_name, up.email, a.role, 'System') AS performed_by,
      a.timestamp AS activity_date,
      COALESCE(a.new_data->>'schedule_days', a.new_data->>'schedule', '—') || ' • ' || COALESCE(a.new_data->>'schedule_time', '08:00 AM - 05:00 PM') AS note
    FROM public.audit_logs a
    LEFT JOIN public.users_profile up ON (up.id = a.actor_id OR up.auth_user_id = a.actor_id)
    WHERE a.record_id = p_plantilla_id
      AND (
        (a.new_data->>'schedule_days' IS DISTINCT FROM a.old_data->>'schedule_days')
        OR (a.new_data->>'schedule_time' IS DISTINCT FROM a.old_data->>'schedule_time')
        OR (a.new_data->>'schedule' IS DISTINCT FROM a.old_data->>'schedule')
      )

    UNION ALL

    -- 3. Transfers from employee_transfers
    SELECT
      t.id::text AS id,
      'transfer' AS activity_type,
      'Store Transfer: ' || COALESCE(t.from_store, '—') || ' → ' || COALESCE(t.to_store, '—') AS description,
      COALESCE(up.full_name, up.email, 'Management') AS performed_by,
      t.created_at AS activity_date,
      'Status: ' || COALESCE(t.status, 'Approved') || CASE WHEN t.reason IS NOT NULL AND t.reason <> '' THEN ' • ' || t.reason ELSE '' END AS note
    FROM public.employee_transfers t
    LEFT JOIN public.users_profile up ON (up.id = t.approved_by_user_id OR up.auth_user_id = t.approved_by_user_id)
    WHERE t.plantilla_id = p_plantilla_id

    UNION ALL

    -- 4. Deactivation requests
    SELECT
      r.id::text AS id,
      'deactivated' AS activity_type,
      'Deactivation Request: ' || COALESCE(r.status, 'Submitted') AS description,
      COALESCE(up.full_name, up.email, 'HR Operations') AS performed_by,
      r.created_at AS activity_date,
      'Status: ' || COALESCE(r.status, 'Submitted') AS note
    FROM public.employee_deactivation_requests r
    LEFT JOIN public.users_profile up ON (up.id = r.requestor_profile_id OR up.auth_user_id = r.requestor_profile_id)
    WHERE r.plantilla_id = p_plantilla_id

    UNION ALL

    -- 5. Legacy activity log
    SELECT
      l.id::text AS id,
      COALESCE(l.activity_type, 'updated') AS activity_type,
      COALESCE(l.description, 'Activity Logged') AS description,
      COALESCE(l.performed_by, 'System') AS performed_by,
      COALESCE(l.activity_date, l.created_at) AS activity_date,
      NULL::text AS note
    FROM public.employee_activity_log l
    CROSS JOIN target_p p
    WHERE l.emploc_no = p.employee_no OR (p.vcode IS NOT NULL AND l.vcode = p.vcode)

    UNION ALL

    -- 6. Initial deployment / hire milestone
    SELECT
      p.id::text || '-deploy' AS id,
      'deployed' AS activity_type,
      'Personnel Deployed to Plantilla' AS description,
      COALESCE(up.full_name, up.email, 'HR Operations') AS performed_by,
      COALESCE(p.created_at, p.date_hired::timestamp with time zone) AS activity_date,
      'Store: ' || COALESCE(p.store_name, '—') || ' • Position: ' || COALESCE(p.position, '—') AS note
    FROM target_p p
    LEFT JOIN public.users_profile up ON (up.id = p.created_by OR up.auth_user_id = p.created_by)
  )
  SELECT DISTINCT ON (re.activity_type, date_trunc('minute', re.activity_date))
    re.id,
    re.activity_type,
    re.description,
    re.performed_by,
    re.activity_date,
    re.note
  FROM raw_events re
  ORDER BY re.activity_type, date_trunc('minute', re.activity_date), re.activity_date DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_plantilla_timeline(uuid) TO authenticated, anon, service_role;
