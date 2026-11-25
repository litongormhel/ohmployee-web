-- ============================================================================
-- Migration: 20262606000189_security_audit_hardening_rls_rpcs_and_slot_authority.sql
-- Created: 2026-11-25T14:43:19.000Z
-- Description:
--   Remediates SEC-01 through SEC-06 from the comprehensive security audit:
--   1. SEC-01 (High): Lock down public.get_plantilla_timeline(uuid):
--      - Revoke EXECUTE from PUBLIC and anon; grant only to authenticated, service_role.
--      - Enforce caller authentication and account scope (i_have_full_access() OR
--        get_my_allowed_accounts() / get_my_allowed_account_ids()) inside target_p CTE.
--   2. SEC-02 (High) & SEC-04 (Medium): Harden public.confirm_applicant_onboard:
--      - Enforce caller account scope against v_vac.account / v_vac.account_id for
--        Stationary and Roving requisitions (matching confirm_coverage_group_onboarding).
--      - Route Option A fast-track slot occupancy through public.fn_set_slot_status
--        (ADR-001 Rule 1 Slot Authority & slot_history audit trail).
--   3. SEC-03 (Medium): Lock down public.get_vacancy_activity_timeline(uuid):
--      - Enforce caller authentication and account scope on the initial public.vacancies
--        lookup so out-of-scope callers receive '[]'::jsonb instead of leaking cross-account
--        candidate names, contact edits, and operational remarks.
--   4. SEC-04 (Medium): Rewire direct UPDATE public.plantilla_slots in
--      public.confirm_coverage_group_onboarding and public._assign_and_deploy_emploc_core
--      through public.fn_set_slot_status (ADR-001 Rule 1 Slot Authority).
--   5. SEC-06 (Low): Least-privilege table & RPC hardening:
--      - Revoke anon SELECT and excessive table-level ALL grants on public.announcements
--        and public.announcement_acknowledgements; grant only SELECT, INSERT, UPDATE, DELETE
--        to authenticated.
--      - Add caller role/auth guard on public.check_and_notify_on_leave_edr() so unauthenticated
--        or Viewer (role_level < 30) callers cannot trigger global notification dispatches.
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. SEC-01: Harden public.get_plantilla_timeline(uuid) (Auth + Scope + Revoke anon)
--    Surgical base: 20262606000134_get_plantilla_timeline_rpc.sql
-- ────────────────────────────────────────────────────────────────────────────
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
      AND (
        auth.uid() IS NULL -- service_role / postgres internal calls
        OR public.i_have_full_access()
        OR account = ANY(public.get_my_allowed_accounts())
        OR account_id = ANY(public.get_my_allowed_account_ids())
      )
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
    JOIN target_p tp ON tp.id = a.record_id
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
    JOIN target_p tp ON tp.id = a.record_id
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
    JOIN target_p tp ON tp.id = t.plantilla_id
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
    JOIN target_p tp ON tp.id = r.plantilla_id
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

REVOKE ALL ON FUNCTION public.get_plantilla_timeline(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_timeline(uuid) TO authenticated, service_role;


-- ────────────────────────────────────────────────────────────────────────────
-- 2. SEC-03: Harden public.get_vacancy_activity_timeline(uuid) (Account Scope Guard)
--    Surgical base: 20262606000176_clean_hc_decimals_in_vacancy_activity_timeline.sql
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_vacancy_activity_timeline(p_vacancy_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_vcode          text;
  v_store_name     text;
  v_position       text;
  v_source         text;
  v_req_hc         numeric;
  v_created_at     timestamptz;
  v_created_by_id  uuid;
  v_req_by_id      uuid;
  v_trig_by_id     uuid;
  v_trig_by_name   text;
  v_result         jsonb;
BEGIN
  SELECT
    v.vcode,
    COALESCE(NULLIF(TRIM(v.store_name), ''), NULLIF(TRIM(v.store_branch), ''), v.vcode),
    COALESCE(NULLIF(TRIM(v.position), ''), 'Position'),
    COALESCE(NULLIF(TRIM(v.source), ''), 'System'),
    COALESCE(v.required_headcount, 1),
    v.created_at,
    v.created_by_user_id,
    v.requested_by_user_id,
    v.triggered_by_user_id,
    v.triggered_by_name
  INTO
    v_vcode,
    v_store_name,
    v_position,
    v_source,
    v_req_hc,
    v_created_at,
    v_created_by_id,
    v_req_by_id,
    v_trig_by_id,
    v_trig_by_name
  FROM public.vacancies v
  WHERE v.id = p_vacancy_id
    AND (
      auth.uid() IS NULL -- service_role / postgres internal calls
      OR public.i_have_full_access()
      OR v.account = ANY(public.get_my_allowed_accounts())
      OR v.account_id = ANY(public.get_my_allowed_account_ids())
    );

  IF v_vcode IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  WITH raw_events AS (
    -- A. Vacancy Creation Milestone
    SELECT
      'vac-create-' || p_vacancy_id::text AS event_id,
      'vacancy_created'::text AS event_type,
      'Vacancy Requisition Created'::text AS event_label,
      format(
        'Opened %s requisition for %s (%s • %s HC) via %s.',
        v_position,
        v_store_name,
        v_vcode,
        trim(trailing '.' from trim(trailing '0' from round(COALESCE(v_req_hc, 1), 2)::text)),
        CASE
          WHEN lower(v_source) = 'manual' THEN 'Manual Entry'
          WHEN lower(v_source) = 'plantilla' THEN 'Plantilla Separation Backfill'
          WHEN lower(v_source) LIKE '%request%' OR lower(v_source) = 'headcount_request' THEN 'Approved Headcount Request'
          WHEN lower(v_source) LIKE '%import%' THEN 'Batch Import'
          ELSE initcap(replace(v_source, '_', ' '))
        END
      ) AS event_description,
      COALESCE(v_created_at, now()) AS created_at,
      COALESCE(
        up_creator.full_name,
        NULLIF(TRIM(v_trig_by_name), ''),
        (
          SELECT COALESCE(up_al.full_name, 'System')
          FROM public.audit_logs al_ins
          LEFT JOIN public.users_profile up_al ON (up_al.id = al_ins.actor_id OR up_al.auth_user_id = al_ins.actor_id)
          WHERE al_ins.record_id = p_vacancy_id
            AND al_ins.action::text = 'INSERT'
          ORDER BY al_ins.timestamp ASC
          LIMIT 1
        ),
        'System'
      ) AS profile_name,
      'vacancy_created:' || to_char(COALESCE(v_created_at, now()), 'YYYY-MM-DD HH24:MI') AS dedup_key
    FROM (SELECT 1) AS dummy
    LEFT JOIN public.users_profile up_creator
      ON up_creator.id = COALESCE(v_created_by_id, v_req_by_id, v_trig_by_id)
      OR up_creator.auth_user_id = COALESCE(v_created_by_id, v_req_by_id, v_trig_by_id)

    UNION ALL

    -- B. Candidate Endorsed / Added to Pipeline (from public.applicants)
    SELECT
      'app-add-' || a.id::text AS event_id,
      'applicant_added'::text AS event_type,
      'Applicant Endorsed to Pipeline'::text AS event_label,
      format(
        'Endorsed candidate %s for %s (Initial Stage: %s)%s.',
        initcap(COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), NULLIF(TRIM(a.full_name), ''), 'Candidate')),
        COALESCE(pos.position_name, v_position),
        COALESCE(NULLIF(TRIM(a.status), ''), 'New'),
        CASE
          WHEN NULLIF(TRIM(COALESCE(a.remarks, '')), '') IS NOT NULL THEN ' — Remarks: ' || TRIM(a.remarks)
          ELSE ''
        END
      ) AS event_description,
      a.created_at AS created_at,
      COALESCE(
        NULLIF(TRIM(a.recruited_by_name), ''),
        up_app.full_name,
        (
          SELECT up_al.full_name
          FROM public.audit_logs al_app
          JOIN public.users_profile up_al ON (up_al.id = al_app.actor_id OR up_al.auth_user_id = al_app.actor_id)
          WHERE al_app.record_id = a.id
            AND al_app.action::text = 'INSERT'
          LIMIT 1
        ),
        'Recruitment Team'
      ) AS profile_name,
      'app_added:' || a.id::text AS dedup_key
    FROM public.applicants a
    LEFT JOIN public.users_profile up_app
      ON up_app.id = COALESCE(a.recruited_by_user_id, a.created_by)
      OR up_app.auth_user_id = COALESCE(a.recruited_by_user_id, a.created_by)
    LEFT JOIN public.vacancy_requirements vr ON vr.id = a.vacancy_requirement_id
    LEFT JOIN public.positions pos ON pos.id = vr.position_id
    WHERE a.vacancy_vcode = v_vcode

    UNION ALL

    -- C. Structured Applicant Pipeline & Field History (from public.applicant_status_history)
    SELECT
      'ash-' || ash.id::text AS event_id,
      CASE
        WHEN ash.update_type = 'status_change' AND lower(COALESCE(ash.to_status, ash.new_value, '')) IN ('backout', 'failed', 'rejected', 'did not report', 'withdrawn')
          THEN 'applicant_dropout'
        WHEN ash.update_type = 'status_change' AND lower(COALESCE(ash.to_status, ash.new_value, '')) IN ('confirmed onboard', 'confirmed_onboard', 'hired')
          THEN 'applicant_hired'
        WHEN ash.update_type = 'status_change'
          THEN 'stage_updated'
        WHEN ash.update_type = 'follow_up_update'
          THEN 'followup_updated'
        ELSE 'remarks_updated'
      END AS event_type,
      CASE
        WHEN ash.update_type = 'status_change' AND lower(COALESCE(ash.to_status, ash.new_value, '')) IN ('backout', 'failed', 'rejected', 'did not report', 'withdrawn')
          THEN 'Candidate ' || initcap(COALESCE(ash.to_status, ash.new_value, 'Backout'))
        WHEN ash.update_type = 'status_change' AND lower(COALESCE(ash.to_status, ash.new_value, '')) IN ('confirmed onboard', 'confirmed_onboard', 'hired')
          THEN 'Candidate Confirmed Onboard'
        WHEN ash.update_type = 'status_change'
          THEN 'Pipeline Stage Advanced'
        WHEN ash.update_type = 'follow_up_update'
          THEN 'Follow-Up Date Updated'
        WHEN ash.update_type = 'recruitment_remarks_update'
          THEN 'Recruitment Remarks Updated'
        WHEN ash.update_type = 'ops_remarks_update'
          THEN 'Operations Remarks Updated'
        ELSE 'Candidate Details Updated'
      END AS event_label,
      CASE
        WHEN ash.update_type = 'status_change' THEN
          format(
            '%s moved from %s to %s%s.',
            initcap(COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), NULLIF(TRIM(a.full_name), ''), 'Candidate')),
            COALESCE(NULLIF(TRIM(ash.from_status), ''), NULLIF(TRIM(ash.old_value), ''), 'Previous Stage'),
            COALESCE(NULLIF(TRIM(ash.to_status), ''), NULLIF(TRIM(ash.new_value), ''), 'New Stage'),
            CASE
              WHEN NULLIF(TRIM(COALESCE(ash.remarks, a.backout_reason, '')), '') IS NOT NULL
                THEN ' (Reason/Remarks: ' || TRIM(COALESCE(NULLIF(TRIM(ash.remarks), ''), a.backout_reason)) || ')'
              ELSE ''
            END
          )
        WHEN ash.update_type = 'follow_up_update' THEN
          format(
            'Updated follow-up date for %s from %s to %s.',
            initcap(COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), NULLIF(TRIM(a.full_name), ''), 'Candidate')),
            COALESCE(ash.old_value, 'None'),
            COALESCE(ash.new_value, 'Cleared')
          )
        WHEN ash.update_type = 'recruitment_remarks_update' THEN
          format(
            'Updated recruitment remarks for %s: "%s".',
            initcap(COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), NULLIF(TRIM(a.full_name), ''), 'Candidate')),
            COALESCE(NULLIF(TRIM(ash.new_value), ''), 'Cleared')
          )
        WHEN ash.update_type = 'ops_remarks_update' THEN
          format(
            'Updated operations remarks for %s: "%s".',
            initcap(COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), NULLIF(TRIM(a.full_name), ''), 'Candidate')),
            COALESCE(NULLIF(TRIM(ash.new_value), ''), 'Cleared')
          )
        ELSE
          format(
            'Updated %s for %s (%s → %s).',
            replace(COALESCE(ash.changed_field, 'record'), '_', ' '),
            initcap(COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), NULLIF(TRIM(a.full_name), ''), 'Candidate')),
            COALESCE(ash.old_value, '—'),
            COALESCE(ash.new_value, '—')
          )
      END AS event_description,
      ash.changed_at AS created_at,
      COALESCE(NULLIF(TRIM(ash.changed_by_name), ''), up_ash.full_name, 'System') AS profile_name,
      'app_status:' || a.id::text || ':' || COALESCE(ash.update_type, '') || ':' || lower(COALESCE(ash.to_status, ash.new_value, '')) || ':' || to_char(ash.changed_at, 'YYYY-MM-DD HH24:MI') AS dedup_key
    FROM public.applicant_status_history ash
    JOIN public.applicants a ON a.id = ash.applicant_id
    LEFT JOIN public.users_profile up_ash ON (up_ash.id = ash.changed_by OR up_ash.auth_user_id = ash.changed_by)
    WHERE a.vacancy_vcode = v_vcode

    UNION ALL

    -- D. Candidate Profile Edits (from public.applicant_profile_edit_history)
    SELECT
      'apeh-' || apeh.id::text AS event_id,
      'applicant_profile_edited'::text AS event_type,
      'Candidate Profile Edited'::text AS event_label,
      format(
        'Updated candidate profile (%s → %s • Contact: %s → %s)%s.',
        initcap(TRIM(CONCAT_WS(' ', apeh.old_first_name, apeh.old_middle_name, apeh.old_last_name))),
        initcap(TRIM(CONCAT_WS(' ', apeh.new_first_name, apeh.new_middle_name, apeh.new_last_name))),
        COALESCE(apeh.old_contact_number, '—'),
        COALESCE(apeh.new_contact_number, '—'),
        CASE
          WHEN NULLIF(TRIM(COALESCE(apeh.reason, '')), '') IS NOT NULL THEN ' — Reason: ' || TRIM(apeh.reason)
          ELSE ''
        END
      ) AS event_description,
      apeh.edited_at AS created_at,
      COALESCE(up_ed.full_name, 'System') AS profile_name,
      'app_edit:' || apeh.applicant_id::text || ':' || to_char(apeh.edited_at, 'YYYY-MM-DD HH24:MI') AS dedup_key
    FROM public.applicant_profile_edit_history apeh
    JOIN public.applicants a ON a.id = apeh.applicant_id
    LEFT JOIN public.users_profile up_ed ON (up_ed.id = apeh.edited_by OR up_ed.auth_user_id = apeh.edited_by)
    WHERE a.vacancy_vcode = v_vcode

    UNION ALL

    -- E. Vacancy Closure Requests (Submitted, Withdrawn, Approved, Rejected)
    SELECT
      'vcr-req-' || vcr.id::text AS event_id,
      'closure_requested'::text AS event_type,
      'Vacancy Closure Requested'::text AS event_label,
      format(
        'Submitted closure clearance request for %s — Reason: %s%s.',
        v_vcode,
        COALESCE(NULLIF(TRIM(vcr.reason), ''), 'Operational Closure'),
        CASE
          WHEN NULLIF(TRIM(COALESCE(vcr.details, '')), '') IS NOT NULL AND TRIM(vcr.details) <> TRIM(COALESCE(vcr.reason, ''))
            THEN ' (' || TRIM(vcr.details) || ')'
          ELSE ''
        END
      ) AS event_description,
      vcr.created_at AS created_at,
      COALESCE(NULLIF(TRIM(vcr.requested_by), ''), up_vcr.full_name, 'Operations') AS profile_name,
      'closure_req:' || vcr.id::text AS dedup_key
    FROM public.vacancy_closure_requests vcr
    LEFT JOIN public.users_profile up_vcr ON (up_vcr.id = vcr.requested_by_user_id OR up_vcr.auth_user_id = vcr.requested_by_user_id)
    WHERE vcr.vacancy_vcode = v_vcode

    UNION ALL

    SELECT
      'vcr-wd-' || vcr.id::text AS event_id,
      'closure_withdrawn'::text AS event_type,
      'Closure Request Withdrawn'::text AS event_label,
      format('Withdrew pending closure request for %s and restored active sourcing.', v_vcode) AS event_description,
      vcr.withdrawn_at AS created_at,
      COALESCE(up_wd.full_name, NULLIF(TRIM(vcr.requested_by), ''), 'Operations') AS profile_name,
      'closure_wd:' || vcr.id::text AS dedup_key
    FROM public.vacancy_closure_requests vcr
    LEFT JOIN public.users_profile up_wd ON (up_wd.id = vcr.withdrawn_by_user_id OR up_wd.auth_user_id = vcr.withdrawn_by_user_id)
    WHERE vcr.vacancy_vcode = v_vcode
      AND vcr.withdrawn_at IS NOT NULL

    UNION ALL

    SELECT
      'vcr-rev-' || vcr.id::text AS event_id,
      CASE WHEN vcr.status = 'Approved' THEN 'closure_approved' ELSE 'closure_rejected' END AS event_type,
      CASE WHEN vcr.status = 'Approved' THEN 'Vacancy Closure Approved' ELSE 'Vacancy Closure Rejected' END AS event_label,
      format(
        '%s closure request for %s%s.',
        CASE WHEN vcr.status = 'Approved' THEN 'Approved' ELSE 'Rejected' END,
        v_vcode,
        CASE
          WHEN NULLIF(TRIM(COALESCE(vcr.reviewer_remarks, '')), '') IS NOT NULL
            THEN ' — Remarks: ' || TRIM(vcr.reviewer_remarks)
          ELSE ''
        END
      ) AS event_description,
      vcr.reviewed_at AS created_at,
      COALESCE(NULLIF(TRIM(vcr.reviewed_by), ''), NULLIF(TRIM(vcr.encoder_by), ''), 'Administrator') AS profile_name,
      'closure_rev:' || vcr.id::text AS dedup_key
    FROM public.vacancy_closure_requests vcr
    WHERE vcr.vacancy_vcode = v_vcode
      AND vcr.status IN ('Approved', 'Rejected')
      AND vcr.reviewed_at IS NOT NULL

    UNION ALL

    -- F. HR Emploc Onboarding & Plantilla Deployment Milestones (from public.hr_emploc)
    SELECT
      'hre-onb-' || he.id::text AS event_id,
      'hr_emploc_endorsed'::text AS event_type,
      'Endorsed to HR Emploc Queue'::text AS event_label,
      format(
        'Candidate %s confirmed onboard and queued in HR Emploc (%s • %s).',
        initcap(COALESCE(NULLIF(TRIM(he.applicant_name), ''), NULLIF(TRIM(he.employee_name_snapshot), ''), 'Candidate')),
        COALESCE(NULLIF(TRIM(he.position), ''), v_position),
        COALESCE(NULLIF(TRIM(he.store_name), ''), v_store_name)
      ) AS event_description,
      COALESCE(he.date_requested, he.created_at) AS created_at,
      COALESCE(up_he.full_name, he.hrco_name, 'HR Operations') AS profile_name,
      'hre_onb:' || he.id::text AS dedup_key
    FROM public.hr_emploc he
    LEFT JOIN public.users_profile up_he ON (up_he.id = COALESCE(he.deployed_by_user_id, he.created_by) OR up_he.auth_user_id = COALESCE(he.deployed_by_user_id, he.created_by))
    WHERE he.vcode = v_vcode

    UNION ALL

    SELECT
      'hre-dep-' || he.id::text AS event_id,
      'plantilla_deployed'::text AS event_type,
      'Deployed to Active Plantilla'::text AS event_label,
      format(
        'Assigned Employee ID %s to %s and deployed to Plantilla (%s).',
        COALESCE(NULLIF(TRIM(he.employee_no), ''), '—'),
        initcap(COALESCE(NULLIF(TRIM(he.applicant_name), ''), NULLIF(TRIM(he.employee_name_snapshot), ''), 'Candidate')),
        COALESCE(NULLIF(TRIM(he.store_name), ''), v_store_name)
      ) AS event_description,
      he.moved_to_plantilla_at AS created_at,
      COALESCE(up_dep.full_name, 'Encoder / HR Team') AS profile_name,
      'hre_dep:' || he.id::text AS dedup_key
    FROM public.hr_emploc he
    LEFT JOIN public.users_profile up_dep ON (up_dep.id = he.moved_to_plantilla_by OR up_dep.auth_user_id = he.moved_to_plantilla_by)
    WHERE he.vcode = v_vcode
      AND he.moved_to_plantilla_at IS NOT NULL

    UNION ALL

    -- G. Meaningful Field-Level Vacancy & Applicant Audit Logs (excluding no-op trigger syncs)
    SELECT
      'al-' || al.id::text AS event_id,
      CASE
        WHEN lower(al.module) = 'applicants' THEN 'applicant_audit'
        ELSE 'vacancy_audit'
      END AS event_type,
      CASE
        WHEN lower(al.module) = 'applicants' THEN
          CASE
            WHEN (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status') THEN
              CASE
                WHEN lower(COALESCE(al.new_data->>'status', '')) IN ('confirmed onboard', 'confirmed_onboard', 'hired')
                  THEN 'Candidate Confirmed Onboard'
                WHEN lower(COALESCE(al.new_data->>'status', '')) IN ('backout', 'failed', 'rejected', 'did not report')
                  THEN 'Candidate ' || initcap(al.new_data->>'status')
                ELSE 'Pipeline Stage Updated'
              END
            WHEN (al.new_data->>'hired_date') IS DISTINCT FROM (al.old_data->>'hired_date')
              THEN 'Onboard / Hired Date Updated'
            ELSE 'Candidate Record Updated'
          END
        ELSE
          CASE
            WHEN (al.new_data->>'required_headcount') IS DISTINCT FROM (al.old_data->>'required_headcount')
              THEN 'Headcount Quota Revised'
            WHEN (al.new_data->>'vacant_date') IS DISTINCT FROM (al.old_data->>'vacant_date')
              THEN 'Effective Vacancy Date Updated'
            WHEN (al.new_data->>'target_fill_date') IS DISTINCT FROM (al.old_data->>'target_fill_date')
              THEN 'Target Fill Date Updated'
            WHEN (al.new_data->>'urgency_level') IS DISTINCT FROM (al.old_data->>'urgency_level')
              THEN 'Urgency Level Updated'
            WHEN (al.new_data->>'hrco_name') IS DISTINCT FROM (al.old_data->>'hrco_name')
              THEN 'HR Coordinator Reassigned'
            WHEN COALESCE((al.new_data->>'is_archived')::boolean, false) = true AND COALESCE((al.old_data->>'is_archived')::boolean, false) = false
              THEN 'Vacancy Archived'
            WHEN COALESCE((al.new_data->>'is_archived')::boolean, false) = false AND COALESCE((al.old_data->>'is_archived')::boolean, false) = true
              THEN 'Vacancy Restored & Reopened'
            WHEN (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status')
              THEN 'Vacancy Status Changed to ' || initcap(COALESCE(al.new_data->>'status', 'Updated'))
            ELSE 'Vacancy Details Updated'
          END
      END AS event_label,
      CASE
        WHEN lower(al.module) = 'applicants' THEN
          CASE
            WHEN (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status') THEN
              format(
                '%s status changed from %s to %s%s.',
                initcap(COALESCE(NULLIF(TRIM(CONCAT_WS(' ', al.new_data->>'first_name', al.new_data->>'last_name')), ''), al.new_data->>'full_name', al.old_data->>'full_name', 'Candidate')),
                COALESCE(al.old_data->>'status', 'Initial'),
                COALESCE(al.new_data->>'status', 'Updated'),
                CASE
                  WHEN NULLIF(TRIM(COALESCE(al.new_data->>'backout_reason', al.new_data->>'remarks', '')), '') IS NOT NULL
                    THEN ' (Remarks: ' || TRIM(COALESCE(NULLIF(TRIM(al.new_data->>'backout_reason'), ''), al.new_data->>'remarks')) || ')'
                  ELSE ''
                END
              )
            WHEN (al.new_data->>'hired_date') IS DISTINCT FROM (al.old_data->>'hired_date') THEN
              format(
                'Updated hired/onboard date for %s from %s to %s.',
                initcap(COALESCE(al.new_data->>'full_name', al.old_data->>'full_name', 'Candidate')),
                COALESCE(al.old_data->>'hired_date', 'None'),
                COALESCE(al.new_data->>'hired_date', 'Cleared')
              )
            ELSE
              format(
                'Updated candidate record for %s.',
                initcap(COALESCE(al.new_data->>'full_name', al.old_data->>'full_name', 'Candidate'))
              )
          END
        ELSE
          CASE
            WHEN (al.new_data->>'required_headcount') IS DISTINCT FROM (al.old_data->>'required_headcount') THEN
              format(
                'Revised authorized headcount quota for %s from %s HC to %s HC.',
                v_vcode,
                CASE
                  WHEN (al.old_data->>'required_headcount') ~ '^[0-9]+(\.[0-9]+)?$'
                    THEN trim(trailing '.' from trim(trailing '0' from round((al.old_data->>'required_headcount')::numeric, 2)::text))
                  ELSE COALESCE(al.old_data->>'required_headcount', '1')
                END,
                CASE
                  WHEN (al.new_data->>'required_headcount') ~ '^[0-9]+(\.[0-9]+)?$'
                    THEN trim(trailing '.' from trim(trailing '0' from round((al.new_data->>'required_headcount')::numeric, 2)::text))
                  ELSE COALESCE(al.new_data->>'required_headcount', '1')
                END
              )
            WHEN (al.new_data->>'vacant_date') IS DISTINCT FROM (al.old_data->>'vacant_date') THEN
              format(
                'Changed effective vacancy date (Vacant Since) from %s to %s.',
                COALESCE(al.old_data->>'vacant_date', '—'),
                COALESCE(al.new_data->>'vacant_date', '—')
              )
            WHEN (al.new_data->>'target_fill_date') IS DISTINCT FROM (al.old_data->>'target_fill_date') THEN
              format(
                'Changed target fill date from %s to %s.',
                COALESCE(al.old_data->>'target_fill_date', 'Not set'),
                COALESCE(al.new_data->>'target_fill_date', 'Cleared')
              )
            WHEN (al.new_data->>'urgency_level') IS DISTINCT FROM (al.old_data->>'urgency_level') THEN
              format(
                'Changed urgency level from %s to %s.',
                COALESCE(al.old_data->>'urgency_level', 'Normal'),
                COALESCE(al.new_data->>'urgency_level', 'Normal')
              )
            WHEN (al.new_data->>'hrco_name') IS DISTINCT FROM (al.old_data->>'hrco_name') THEN
              format(
                'Assigned HR Coordinator updated from %s to %s.',
                COALESCE(NULLIF(TRIM(al.old_data->>'hrco_name'), ''), 'Unassigned'),
                COALESCE(NULLIF(TRIM(al.new_data->>'hrco_name'), ''), 'Unassigned')
              )
            WHEN COALESCE((al.new_data->>'is_archived')::boolean, false) = true AND COALESCE((al.old_data->>'is_archived')::boolean, false) = false THEN
              format(
                'Archived vacancy requisition %s%s.',
                v_vcode,
                CASE
                  WHEN NULLIF(TRIM(COALESCE(al.new_data->>'archive_reason', '')), '') IS NOT NULL
                    THEN ' (Reason: ' || TRIM(al.new_data->>'archive_reason') || ')'
                  ELSE ''
                END
              )
            WHEN COALESCE((al.new_data->>'is_archived')::boolean, false) = false AND COALESCE((al.old_data->>'is_archived')::boolean, false) = true THEN
              format('Restored and reopened vacancy requisition %s for active recruitment.', v_vcode)
            WHEN (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status') THEN
              format(
                'Vacancy status transitioned from %s to %s.',
                COALESCE(al.old_data->>'status', 'Open'),
                COALESCE(al.new_data->>'status', 'Updated')
              )
            ELSE
              format('Updated vacancy attributes for %s.', v_vcode)
          END
      END AS event_description,
      al.timestamp AS created_at,
      COALESCE(up_al.full_name, 'System') AS profile_name,
      CASE
        WHEN lower(al.module) = 'applicants' AND (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status') THEN
          'app_status:' || al.record_id::text || ':status_change:' || lower(COALESCE(al.new_data->>'status', '')) || ':' || to_char(al.timestamp, 'YYYY-MM-DD HH24:MI')
        ELSE
          'al:' || al.record_id::text || ':' || COALESCE(al.new_data->>'status', '') || ':' || COALESCE(al.new_data->>'required_headcount', '') || ':' || COALESCE(al.new_data->>'vacant_date', '') || ':' || to_char(al.timestamp, 'YYYY-MM-DD HH24:MI')
      END AS dedup_key
    FROM public.audit_logs al
    LEFT JOIN public.users_profile up_al ON (up_al.id = al.actor_id OR up_al.auth_user_id = al.actor_id)
    WHERE al.action::text = 'UPDATE'
      AND (
        (
          al.record_id = p_vacancy_id
          AND (
            (al.new_data->>'required_headcount') IS DISTINCT FROM (al.old_data->>'required_headcount')
            OR (al.new_data->>'vacant_date') IS DISTINCT FROM (al.old_data->>'vacant_date')
            OR (al.new_data->>'target_fill_date') IS DISTINCT FROM (al.old_data->>'target_fill_date')
            OR (al.new_data->>'urgency_level') IS DISTINCT FROM (al.old_data->>'urgency_level')
            OR (al.new_data->>'hrco_name') IS DISTINCT FROM (al.old_data->>'hrco_name')
            OR COALESCE((al.new_data->>'is_archived')::boolean, false) IS DISTINCT FROM COALESCE((al.old_data->>'is_archived')::boolean, false)
            OR (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status')
          )
        )
        OR (
          lower(al.module) = 'applicants'
          AND (al.new_data->>'vacancy_vcode' = v_vcode OR al.old_data->>'vacancy_vcode' = v_vcode)
          AND (
            (al.new_data->>'status') IS DISTINCT FROM (al.old_data->>'status')
            OR (al.new_data->>'hired_date') IS DISTINCT FROM (al.old_data->>'hired_date')
          )
        )
      )
  ),
  deduped AS (
    SELECT DISTINCT ON (re.dedup_key)
      re.event_id,
      re.event_type,
      re.event_label,
      re.event_description,
      re.created_at,
      re.profile_name
    FROM raw_events re
    WHERE re.created_at IS NOT NULL
    ORDER BY
      re.dedup_key,
      CASE WHEN re.event_id LIKE 'al-%' THEN 2 ELSE 1 END ASC,
      re.created_at DESC
  ),
  ordered AS (
    SELECT *
    FROM deduped
    ORDER BY created_at DESC
    LIMIT 30
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'event_id', o.event_id,
        'event_type', o.event_type,
        'event_label', o.event_label,
        'event_description', o.event_description,
        'created_at', o.created_at,
        'profile_name', o.profile_name
      )
      ORDER BY o.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM ordered o;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_vacancy_activity_timeline(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_activity_timeline(uuid) TO authenticated, service_role, postgres;


-- ────────────────────────────────────────────────────────────────────────────
-- 3. SEC-04: Rewire public.confirm_coverage_group_onboarding slot writes through fn_set_slot_status
--    Surgical base: 20262606000188_partial_roving_coverage_store_onboarding_and_agawa_backfill.sql
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_coverage_group_onboarding(
  p_applicant_id uuid,
  p_selected_store_ids uuid[],
  p_hired_by_user_id uuid DEFAULT NULL::uuid,
  p_hired_date date DEFAULT NULL::date,
  p_remarks text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role                 text    := public.get_my_role();
  v_role_level           int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id           uuid    := public.get_my_profile_id();
  v_actor_name           text    := public.get_my_full_name();
  v_app                  public.applicants%ROWTYPE;
  v_vac                  public.vacancies%ROWTYPE;
  v_group                public.coverage_groups%ROWTYPE;
  v_coverage_slot_id     uuid;
  v_hr                   public.hr_emploc%ROWTYPE;
  v_existing_plt         public.plantilla%ROWTYPE;
  v_hired_by_id          uuid;
  v_store_record         record;
  v_member_record        record;
  v_covered_json         jsonb   := '[]'::jsonb;
  v_store_id             uuid;
  v_store_names          text;
  v_first_selected_vcode text;
  v_first_selected_sid   uuid;
  v_first_selected_sname text;
  v_account_name         text;
  v_position_name        text;
  v_store_vac            public.vacancies%ROWTYPE;
  v_sibling_app_id       uuid;
  v_all_confirmed        boolean := true;
  v_target_slot          record;
BEGIN
  -- 1. RBAC Guard
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Fetch and lock applicant
  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant not found or archived' USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.status, 'New') IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops') THEN
    RAISE EXCEPTION 'cannot onboard: applicant is in terminal status %', v_app.status USING ERRCODE = '22023';
  END IF;

  -- 2b. Auto-resolve coverage_group_id and coverage_slot_id from vacancy_vcode if not yet bound
  IF v_app.vacancy_vcode IS NOT NULL THEN
    SELECT * INTO v_vac
      FROM public.vacancies
     WHERE vcode = v_app.vacancy_vcode
       AND deleted_at IS NULL
     LIMIT 1;
  END IF;

  IF v_app.coverage_group_id IS NULL THEN
    SELECT cgs.coverage_group_id INTO v_app.coverage_group_id
      FROM public.coverage_group_stores cgs
      JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
      LEFT JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.archived_at IS NULL
       AND cg.archived_at IS NULL
       AND (
         (v_vac.store_id IS NOT NULL AND cgs.store_id = v_vac.store_id)
         OR (v_app.vacancy_vcode IS NOT NULL AND upper(s.vcode) = upper(v_app.vacancy_vcode))
         OR (v_app.vacancy_vcode IS NOT NULL AND upper(cg.coverage_code) = upper(v_app.vacancy_vcode))
       )
     ORDER BY cgs.is_anchor DESC, cgs.added_at ASC
     LIMIT 1;
  END IF;

  IF v_app.coverage_group_id IS NULL THEN
    RAISE EXCEPTION 'applicant is not assigned to a coverage group slot' USING ERRCODE = '22023';
  END IF;

  -- 3. Fetch and lock coverage group
  SELECT * INTO v_group FROM public.coverage_groups WHERE id = v_app.coverage_group_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found' USING ERRCODE = 'P0002';
  END IF;

  v_coverage_slot_id := v_app.coverage_slot_id;
  IF v_coverage_slot_id IS NULL THEN
    SELECT cs.id INTO v_coverage_slot_id
      FROM public.coverage_slots cs
     WHERE cs.coverage_group_id = v_group.id
       AND COALESCE(cs.is_archived, false) = false
     ORDER BY
       CASE WHEN cs.slot_status IN ('pipeline', 'hr_processing') THEN 0 ELSE 1 END,
       cs.slot_ordinal ASC
     LIMIT 1;
  END IF;

  IF v_coverage_slot_id IS NULL THEN
    RAISE EXCEPTION 'coverage slot not found for coverage group %', v_group.coverage_code USING ERRCODE = '22023';
  END IF;

  -- 4. Scope Guard
  IF NOT public.i_have_full_access() AND NOT (v_group.account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: coverage group is outside caller scope' USING ERRCODE = '42501';
  END IF;

  IF array_length(p_selected_store_ids, 1) IS NULL OR array_length(p_selected_store_ids, 1) < 1 THEN
    RAISE EXCEPTION 'at least one store must be selected' USING ERRCODE = '22023';
  END IF;

  -- 5. Validate selected stores belong to coverage group and resolve primary selected store VCode
  FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
    SELECT s.id AS store_id, s.store_name, s.vcode, cgs.is_anchor INTO v_store_record
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.store_id = v_store_id
       AND cgs.archived_at IS NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'store % is not part of active coverage group footprint', v_store_id USING ERRCODE = '22023';
    END IF;

    IF v_first_selected_sid IS NULL OR v_store_record.is_anchor THEN
      v_first_selected_sid   := v_store_record.store_id;
      v_first_selected_sname := v_store_record.store_name;
      v_first_selected_vcode := v_store_record.vcode;
    END IF;
  END LOOP;

  SELECT account_name INTO v_account_name FROM public.accounts WHERE id = v_group.account_id;
  SELECT position_name INTO v_position_name FROM public.positions WHERE id = v_group.position_id;
  v_position_name := COALESCE(v_position_name, v_vac.position, 'MERCHANDISER');
  v_hired_by_id   := COALESCE(p_hired_by_user_id, v_profile_id);

  -- 6. Update primary applicant row (clear slot_id before setting coverage_slot_id to satisfy applicants_slot_coverage_mutex_chk)
  UPDATE public.applicants
     SET status             = 'Confirmed Onboard',
         slot_id            = NULL,
         coverage_group_id  = v_group.id,
         coverage_slot_id   = v_coverage_slot_id,
         vacancy_vcode      = COALESCE(v_first_selected_vcode, vacancy_vcode),
         hired_date         = COALESCE(p_hired_date, hired_date, CURRENT_DATE),
         hired_at           = COALESCE(hired_at, NOW()),
         hired_by           = v_actor_name,
         hired_by_team      = v_role,
         hired_by_user_id   = v_hired_by_id,
         deployed_by_user_id = v_profile_id,
         remarks            = COALESCE(p_remarks, remarks),
         updated_at         = NOW(),
         updated_by         = v_profile_id
   WHERE id = p_applicant_id
   RETURNING * INTO v_app;

  -- Also mark any sibling pipeline applicant rows on selected stores as Confirmed Onboard
  UPDATE public.applicants a
     SET status              = 'Confirmed Onboard',
         slot_id             = NULL,
         coverage_group_id   = v_group.id,
         coverage_slot_id    = v_coverage_slot_id,
         hired_date          = COALESCE(p_hired_date, a.hired_date, CURRENT_DATE),
         hired_at            = COALESCE(a.hired_at, NOW()),
         hired_by            = v_actor_name,
         hired_by_team       = v_role,
         hired_by_user_id    = v_hired_by_id,
         deployed_by_user_id = v_profile_id,
         updated_at          = NOW(),
         updated_by          = v_profile_id
   WHERE a.id <> p_applicant_id
     AND COALESCE(a.is_archived, false) = false
     AND (
       a.coverage_group_id = v_group.id
       OR LOWER(TRIM(a.full_name)) = LOWER(TRIM(v_app.full_name))
     )
     AND EXISTS (
       SELECT 1 FROM public.stores s
       WHERE s.id = ANY(p_selected_store_ids)
         AND upper(s.vcode) = upper(a.vacancy_vcode)
     );

  -- ──────────────────────────────────────────────────────────────────────────
  -- 7. OPTION A: Check if candidate is ALREADY Active in Plantilla for this Account / Coverage Group
  --    (If already on duty with an Employee #, fast-track the newly confirmed store(s) directly to Plantilla!)
  -- ──────────────────────────────────────────────────────────────────────────
  SELECT plt.* INTO v_existing_plt
    FROM public.plantilla plt
   WHERE (plt.account_id = v_group.account_id OR plt.account = v_account_name)
     AND plt.status IN ('Active', 'On Leave')
     AND COALESCE(plt.is_deleted, false) = false
     AND COALESCE(plt.is_archived, false) = false
     AND plt.employee_no IS NOT NULL
     AND (
       plt.coverage_group_id = v_group.id
       OR plt.coverage_slot_id = v_coverage_slot_id
       OR LOWER(TRIM(plt.employee_name)) = LOWER(TRIM(v_app.full_name))
     )
   ORDER BY
     CASE WHEN plt.coverage_group_id = v_group.id THEN 0 ELSE 1 END,
     plt.created_at DESC
   LIMIT 1
  FOR UPDATE;

  IF v_existing_plt.id IS NOT NULL THEN
    -- Ensure Plantilla master is bound to this coverage group as Roving
    UPDATE public.plantilla
       SET deployment_type   = 'Roving',
           coverage_group_id = COALESCE(coverage_group_id, v_group.id),
           coverage_slot_id  = CASE WHEN roving_assignment_id IS NULL THEN COALESCE(coverage_slot_id, v_coverage_slot_id) ELSE coverage_slot_id END,
           updated_at        = NOW(),
           updated_by        = v_profile_id
     WHERE id = v_existing_plt.id
     RETURNING * INTO v_existing_plt;

    -- Also ensure the employee's primary store is in plantilla_store_links if not yet linked
    IF v_existing_plt.vcode IS NOT NULL AND NOT (v_existing_plt.vcode LIKE 'CG-%') THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id, coverage_group_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_existing_plt.roving_assignment_id, v_group.id,
        v_existing_plt.vacancy_id, v_existing_plt.vcode,
        v_existing_plt.store_name, COALESCE(v_existing_plt.account, v_account_name),
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
      DO UPDATE SET
        coverage_group_id = COALESCE(public.plantilla_store_links.coverage_group_id, EXCLUDED.coverage_group_id),
        status            = 'Active',
        unlinked_at       = NULL,
        unlinked_by       = NULL,
        updated_at        = NOW(),
        updated_by        = v_profile_id;
    END IF;

    -- Link each newly confirmed store into plantilla_store_links, close its vacancy, and occupy its plantilla_slot via fn_set_slot_status
    FOR v_store_id IN SELECT DISTINCT unnest(p_selected_store_ids) LOOP
      SELECT s.id AS store_id, s.store_name, s.vcode, cgs.is_anchor INTO v_store_record
        FROM public.coverage_group_stores cgs
        JOIN public.stores s ON s.id = cgs.store_id
       WHERE cgs.coverage_group_id = v_group.id
         AND cgs.store_id = v_store_id
         AND cgs.archived_at IS NULL;

      SELECT * INTO v_store_vac
        FROM public.vacancies
       WHERE (vcode = v_store_record.vcode OR store_id = v_store_id)
         AND deleted_at IS NULL
       ORDER BY CASE WHEN vcode = v_store_record.vcode THEN 0 ELSE 1 END, created_at DESC
       LIMIT 1;

      IF v_store_record.vcode IS NOT NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, roving_assignment_id, coverage_group_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_existing_plt.id, v_existing_plt.roving_assignment_id, v_group.id,
          v_store_vac.id, v_store_record.vcode,
          v_store_record.store_name, COALESCE(v_existing_plt.account, v_account_name),
          'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
        )
        ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
        DO UPDATE SET
          coverage_group_id = COALESCE(public.plantilla_store_links.coverage_group_id, EXCLUDED.coverage_group_id),
          status            = 'Active',
          unlinked_at       = NULL,
          unlinked_by       = NULL,
          updated_at        = NOW(),
          updated_by        = v_profile_id;

        -- Occupy physical plantilla_slot for this store via ADR-001 Rule 1 Slot Authority
        FOR v_target_slot IN
          SELECT id, slot_status
            FROM public.plantilla_slots
           WHERE legacy_vcode = v_store_record.vcode
             AND closed_at IS NULL
             AND slot_status IN ('open', 'pipeline', 'hr_processing')
        LOOP
          IF v_target_slot.slot_status = 'pipeline' THEN
            PERFORM public.fn_set_slot_status(
              p_slot_id               => v_target_slot.id,
              p_new_status            => 'hr_processing',
              p_reason_code           => 'REPLACEMENT',
              p_performed_by          => v_profile_id,
              p_remarks               => 'confirm_coverage_group_onboarding: Option A fast-track pipeline->hr_processing for ' || v_store_record.vcode,
              p_occupant_plantilla_id => NULL
            );
          END IF;

          PERFORM public.fn_set_slot_status(
            p_slot_id               => v_target_slot.id,
            p_new_status            => 'occupied',
            p_reason_code           => NULL,
            p_performed_by          => v_profile_id,
            p_remarks               => 'confirm_coverage_group_onboarding: Option A fast-track occupied by plantilla ' || v_existing_plt.id::text,
            p_occupant_plantilla_id => v_existing_plt.id
          );
        END LOOP;

        -- Close vacancy for this store
        UPDATE public.vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_profile_id
         WHERE vcode = v_store_record.vcode
           AND deleted_at IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Archived');
      END IF;

      -- Update hr_emploc_store_links if an hr_emploc record exists
      IF v_existing_plt.hr_emploc_id IS NOT NULL THEN
        UPDATE public.hr_emploc_store_links
           SET status       = 'Confirmed',
               confirmed_at = COALESCE(confirmed_at, NOW()),
               confirmed_by = COALESCE(confirmed_by, v_profile_id),
               updated_at   = NOW(),
               updated_by   = v_profile_id
         WHERE hr_emploc_id = v_existing_plt.hr_emploc_id
           AND (store_id = v_store_id OR vcode = v_store_record.vcode)
           AND deleted_at IS NULL;
      END IF;
    END LOOP;

    -- Rebalance employee_store_allocations (e.g. 0.50 SMCO ONEMALL + 0.50 SSM JAZZ)
    PERFORM public.fn_sync_employee_store_allocations(v_existing_plt.employee_no);

    -- Ensure coverage slot is active and bound to occupant
    UPDATE public.coverage_slots
       SET slot_status                   = 'active',
           current_occupant_plantilla_id = v_existing_plt.id,
           updated_at                    = NOW()
     WHERE id = v_coverage_slot_id;

    RETURN jsonb_build_object(
      'ok',                true,
      'fast_tracked',      true,
      'skipped_hr_emploc', true,
      'plantilla_id',      v_existing_plt.id,
      'employee_no',       v_existing_plt.employee_no,
      'coverage_group_id', v_group.id,
      'coverage_slot_id',  v_coverage_slot_id
    );
  END IF;

  -- ──────────────────────────────────────────────────────────────────────────
  -- 8. Check if an active (non-deployed) HR Emploc record ALREADY exists for this candidate / coverage slot
  -- ──────────────────────────────────────────────────────────────────────────
  SELECT * INTO v_hr
    FROM public.hr_emploc h
   WHERE h.deleted_at IS NULL
     AND h.status NOT IN ('Moved to Plantilla', 'Backout')
     AND (
       h.coverage_slot_id = v_coverage_slot_id
       OR h.coverage_group_id = v_group.id
       OR h.applicant_id = v_app.id
       OR (
         (h.account_id = v_group.account_id OR h.account = v_account_name)
         AND LOWER(TRIM(h.applicant_name)) = LOWER(TRIM(v_app.full_name))
       )
     )
   ORDER BY
     CASE WHEN h.coverage_slot_id = v_coverage_slot_id THEN 0 ELSE 1 END,
     h.created_at DESC
   LIMIT 1
  FOR UPDATE;

  -- Detach any prior separated occupant's terminal hr_emploc from this coverage_slot_id
  UPDATE public.hr_emploc
     SET deleted_at = NOW(),
         updated_by = v_profile_id
   WHERE coverage_slot_id = v_coverage_slot_id
     AND deleted_at IS NULL
     AND status = 'Moved to Plantilla'
     AND (v_hr.id IS NULL OR id <> v_hr.id);

  IF v_hr.id IS NULL THEN
    -- Insert new Coverage HR Emploc record
    INSERT INTO public.hr_emploc (
      applicant_name, applicant_name_snapshot, applicant_id,
      vcode, vacancy_id, vacancy_code_snapshot,
      account, account_id, store_id, store_name,
      position_id_snapshot, position,
      status, hr_status, hired_date,
      deployed_by_user_id, created_by, updated_by, date_requested,
      assignment_type, roving_assignment_id, slot_id,
      coverage_group_id, coverage_slot_id, covered_stores,
      ops_remarks, contact_number_snapshot
    ) VALUES (
      v_app.full_name, v_app.full_name, v_app.id,
      v_first_selected_vcode, NULL, v_group.coverage_code,
      v_account_name, v_group.account_id, v_first_selected_sid, v_first_selected_sname,
      v_group.position_id, v_position_name,
      'Pending Emploc', 'Pending', COALESCE(p_hired_date, v_app.hired_date, CURRENT_DATE),
      v_profile_id, v_profile_id, v_profile_id, NOW(),
      'Coverage'::public.hr_emploc_assignment_type, NULL, NULL,
      v_group.id, v_coverage_slot_id, '[]'::jsonb,
      p_remarks, v_app.contact_number
    )
    RETURNING * INTO v_hr;
  ELSE
    -- Upgrade existing hr_emploc to Coverage binding if it was created as Stationary on a single member store
    UPDATE public.hr_emploc
       SET assignment_type       = 'Coverage'::public.hr_emploc_assignment_type,
           vacancy_id            = NULL,
           roving_assignment_id  = NULL,
           slot_id               = NULL,
           coverage_group_id     = v_group.id,
           coverage_slot_id      = v_coverage_slot_id,
           vcode                 = COALESCE(vcode, v_first_selected_vcode),
           vacancy_code_snapshot = v_group.coverage_code,
           ops_remarks           = COALESCE(p_remarks, ops_remarks),
           updated_at            = NOW(),
           updated_by            = v_profile_id
     WHERE id = v_hr.id
     RETURNING * INTO v_hr;
  END IF;

  -- ──────────────────────────────────────────────────────────────────────────
  -- 9. Process ALL member stores of the Coverage Group (Selected vs. Unselected)
  -- ──────────────────────────────────────────────────────────────────────────
  FOR v_member_record IN
    SELECT cgs.store_id, cgs.is_anchor, cgs.hc_share, s.store_name, s.vcode
      FROM public.coverage_group_stores cgs
      JOIN public.stores s ON s.id = cgs.store_id
     WHERE cgs.coverage_group_id = v_group.id
       AND cgs.archived_at IS NULL
     ORDER BY cgs.is_anchor DESC, s.store_name ASC
  LOOP
    SELECT * INTO v_store_vac
      FROM public.vacancies
     WHERE (vcode = v_member_record.vcode OR store_id = v_member_record.store_id)
       AND deleted_at IS NULL
     ORDER BY CASE WHEN vcode = v_member_record.vcode THEN 0 ELSE 1 END, created_at DESC
     LIMIT 1;

    IF v_member_record.store_id = ANY(p_selected_store_ids)
       OR EXISTS (
         SELECT 1 FROM public.hr_emploc_store_links hsl
         WHERE hsl.hr_emploc_id = v_hr.id
           AND hsl.store_id = v_member_record.store_id
           AND hsl.status = 'Confirmed'
           AND hsl.deleted_at IS NULL
       )
    THEN
      -- Store is CONFIRMED ONBOARD (selected now or already confirmed earlier)
      IF EXISTS (
        SELECT 1 FROM public.hr_emploc_store_links hsl
        WHERE hsl.hr_emploc_id = v_hr.id
          AND (hsl.store_id = v_member_record.store_id OR (v_member_record.vcode IS NOT NULL AND hsl.vcode = v_member_record.vcode))
          AND hsl.deleted_at IS NULL
      ) THEN
        UPDATE public.hr_emploc_store_links
           SET status            = 'Confirmed',
               coverage_group_id = v_group.id,
               coverage_slot_id  = v_coverage_slot_id,
               store_id          = v_member_record.store_id,
               vcode             = COALESCE(vcode, v_member_record.vcode),
               vacancy_id        = COALESCE(vacancy_id, v_store_vac.id),
               store_name        = v_member_record.store_name,
               confirmed_at      = COALESCE(confirmed_at, NOW()),
               confirmed_by      = COALESCE(confirmed_by, v_profile_id),
               updated_at        = NOW(),
               updated_by        = v_profile_id
         WHERE hr_emploc_id = v_hr.id
           AND (store_id = v_member_record.store_id OR (v_member_record.vcode IS NOT NULL AND vcode = v_member_record.vcode))
           AND deleted_at IS NULL;
      ELSE
        INSERT INTO public.hr_emploc_store_links (
          hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
          vacancy_id, vcode, store_name, account,
          status, confirmed_at, confirmed_by, created_by, updated_by
        ) VALUES (
          v_hr.id, v_group.id, v_coverage_slot_id, v_member_record.store_id,
          v_store_vac.id, v_member_record.vcode, v_member_record.store_name, v_hr.account,
          'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
        );
      END IF;

      -- Transition confirmed store's physical plantilla_slot to hr_processing via fn_set_slot_status
      IF v_member_record.vcode IS NOT NULL THEN
        FOR v_target_slot IN
          SELECT id
            FROM public.plantilla_slots
           WHERE legacy_vcode = v_member_record.vcode
             AND closed_at IS NULL
             AND slot_status IN ('open', 'pipeline')
        LOOP
          PERFORM public.fn_set_slot_status(
            p_slot_id               => v_target_slot.id,
            p_new_status            => 'hr_processing',
            p_reason_code           => 'REPLACEMENT',
            p_performed_by          => v_profile_id,
            p_remarks               => 'confirm_coverage_group_onboarding: store confirmed onboard for ' || v_member_record.vcode,
            p_occupant_plantilla_id => NULL
          );
        END LOOP;
      END IF;

      v_covered_json := v_covered_json || jsonb_build_object(
        'store_id',   v_member_record.store_id,
        'store_name', v_member_record.store_name,
        'vcode',      v_member_record.vcode,
        'is_anchor',  v_member_record.is_anchor,
        'status',     'Confirmed'
      );
    ELSE
      -- Store is UNSELECTED -> Keep in Pipeline ('For Requirements')!
      v_all_confirmed := false;

      IF NOT EXISTS (
        SELECT 1 FROM public.hr_emploc_store_links hsl
        WHERE hsl.hr_emploc_id = v_hr.id
          AND (hsl.store_id = v_member_record.store_id OR (v_member_record.vcode IS NOT NULL AND hsl.vcode = v_member_record.vcode))
          AND hsl.deleted_at IS NULL
      ) THEN
        INSERT INTO public.hr_emploc_store_links (
          hr_emploc_id, coverage_group_id, coverage_slot_id, store_id,
          vacancy_id, vcode, store_name, account,
          status, confirmed_at, confirmed_by, created_by, updated_by
        ) VALUES (
          v_hr.id, v_group.id, v_coverage_slot_id, v_member_record.store_id,
          v_store_vac.id, v_member_record.vcode, v_member_record.store_name, v_hr.account,
          'Pending', NULL, NULL, v_profile_id, v_profile_id
        );
      END IF;

      -- Ensure a linked pipeline applicant row ('For Requirements') exists on this remaining store's VCode
      IF v_member_record.vcode IS NOT NULL THEN
        SELECT a.id INTO v_sibling_app_id
          FROM public.applicants a
         WHERE a.vacancy_vcode = v_member_record.vcode
           AND COALESCE(a.is_archived, false) = false
           AND (
             a.coverage_group_id = v_group.id
             OR LOWER(TRIM(a.full_name)) = LOWER(TRIM(v_app.full_name))
           )
         ORDER BY a.created_at DESC
         LIMIT 1;

        IF v_sibling_app_id IS NULL THEN
          INSERT INTO public.applicants (
            vacancy_vcode,
            first_name, last_name, middle_name, full_name, full_name_snapshot,
            contact_number, status,
            coverage_group_id, coverage_slot_id,
            recruited_by_name, recruited_by_user_id,
            ops_remarks, is_archived, created_by, updated_by
          ) VALUES (
            v_member_record.vcode,
            v_app.first_name, v_app.last_name, v_app.middle_name, v_app.full_name, v_app.full_name,
            v_app.contact_number, 'For Requirements',
            v_group.id, v_coverage_slot_id,
            v_app.recruited_by_name, v_app.recruited_by_user_id,
            format('Remaining store for %s (Onboarded at %s)', v_group.coverage_code, COALESCE(v_first_selected_sname, 'Anchor Store')),
            false, v_profile_id, v_profile_id
          );
        ELSE
          UPDATE public.applicants
             SET status            = CASE WHEN status = 'Confirmed Onboard' THEN 'For Requirements' ELSE status END,
                 slot_id           = NULL,
                 coverage_group_id = v_group.id,
                 coverage_slot_id  = v_coverage_slot_id,
                 updated_at        = NOW(),
                 updated_by        = v_profile_id
           WHERE id = v_sibling_app_id;
        END IF;

        -- Keep remaining store's plantilla_slot in 'pipeline' via fn_set_slot_status
        FOR v_target_slot IN
          SELECT id
            FROM public.plantilla_slots
           WHERE legacy_vcode = v_member_record.vcode
             AND closed_at IS NULL
             AND slot_status = 'open'
        LOOP
          PERFORM public.fn_set_slot_status(
            p_slot_id               => v_target_slot.id,
            p_new_status            => 'pipeline',
            p_reason_code           => NULL,
            p_performed_by          => v_profile_id,
            p_remarks               => 'confirm_coverage_group_onboarding: remaining store kept in pipeline for ' || v_member_record.vcode,
            p_occupant_plantilla_id => NULL
          );
        END LOOP;
      END IF;

      v_covered_json := v_covered_json || jsonb_build_object(
        'store_id',   v_member_record.store_id,
        'store_name', v_member_record.store_name,
        'vcode',      v_member_record.vcode,
        'is_anchor',  v_member_record.is_anchor,
        'status',     'Pending Requirements'
      );
    END IF;
  END LOOP;

  -- Update hr_emploc covered_stores and store_name summary
  SELECT string_agg(el->>'store_name', ', ')
    INTO v_store_names
    FROM jsonb_array_elements(v_covered_json) el
   WHERE COALESCE(el->>'status', 'Confirmed') = 'Confirmed';

  UPDATE public.hr_emploc
     SET covered_stores = v_covered_json,
         store_name     = COALESCE(v_store_names, store_name),
         updated_at     = NOW(),
         updated_by     = v_profile_id
   WHERE id = v_hr.id
   RETURNING * INTO v_hr;

  -- 10. Transition coverage slot from pipeline -> hr_processing
  PERFORM public.fn_sync_coverage_slot_to_hr_processing(
    p_coverage_slot_id => v_coverage_slot_id,
    p_applicant_id     => v_app.id,
    p_performed_by     => v_profile_id,
    p_source_fn        => 'confirm_coverage_group_onboarding'
  );

  -- 11. Log activity
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    v_app.full_name,
    v_group.coverage_code,
    'confirmed_onboard',
    'Coverage applicant confirmed onboard to ' || COALESCE(v_store_names, ''),
    v_actor_name,
    jsonb_build_object(
      'applicant_id',       v_app.id,
      'hr_emploc_id',       v_hr.id,
      'coverage_group_id',  v_group.id,
      'coverage_slot_id',   v_coverage_slot_id,
      'selected_stores',    v_covered_json,
      'all_confirmed',      v_all_confirmed
    )
  );

  RETURN jsonb_build_object(
    'ok',                true,
    'hr_emploc_id',      v_hr.id,
    'coverage_group_id', v_group.id,
    'coverage_slot_id',  v_coverage_slot_id,
    'all_confirmed',     v_all_confirmed
  );
END;
$function$;


-- ────────────────────────────────────────────────────────────────────────────
-- 4. SEC-02 & SEC-04: Harden public.confirm_applicant_onboard (13-arg)
--    - Adds account scope enforcement for Stationary & Roving vacancies.
--    - Routes Option A fast-track slot occupancy through fn_set_slot_status.
--    Surgical base: 20262606000188_partial_roving_coverage_store_onboarding_and_agawa_backfill.sql
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(
  p_applicant_id uuid,
  p_last_name text DEFAULT NULL::text,
  p_first_name text DEFAULT NULL::text,
  p_middle_name text DEFAULT NULL::text,
  p_full_name text DEFAULT NULL::text,
  p_contact_number text DEFAULT NULL::text,
  p_remarks text DEFAULT NULL::text,
  p_roving_assignment_id uuid DEFAULT NULL::uuid,
  p_hired_by_user_id uuid DEFAULT NULL::uuid,
  p_endorsed_by_deployer_id uuid DEFAULT NULL::uuid,
  p_endorsed_by_name text DEFAULT NULL::text,
  p_hired_date date DEFAULT NULL::date,
  p_vacancy_requirement_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text    := public.get_my_role();
  v_role_level  int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id  uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_app         public.applicants%ROWTYPE;
  v_vac         public.vacancies%ROWTYPE;
  v_hr          public.hr_emploc%ROWTYPE;
  v_full_name   text;
  v_hired_by_id uuid;
  v_is_roving   boolean;
  v_store_link_id uuid;
  v_late_result   jsonb;
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
  v_resolved_requirement_id uuid;
  v_slot_sync_result  jsonb;
  v_cg_store_id       uuid;
  v_target_slot       record;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.status, 'New') IN (
    'Failed', 'Backout', 'Did Not Report', 'Rejected by Ops'
  ) THEN
    RAISE EXCEPTION
      'applicant % has terminal status % — cannot onboard',
      p_applicant_id, v_app.status
      USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND deleted_at IS NULL
   LIMIT 1;

  -- If applicant is bound to a Coverage Group (e.g. remaining store SSM JAZZ completing requirements),
  -- delegate directly to confirm_coverage_group_onboarding for this store!
  IF v_app.coverage_group_id IS NOT NULL THEN
    v_cg_store_id := v_vac.store_id;
    IF v_cg_store_id IS NULL AND v_app.vacancy_vcode IS NOT NULL THEN
      SELECT s.id INTO v_cg_store_id
        FROM public.stores s
       WHERE upper(s.vcode) = upper(v_app.vacancy_vcode)
       LIMIT 1;
    END IF;

    IF v_cg_store_id IS NOT NULL THEN
      RETURN public.confirm_coverage_group_onboarding(
        p_applicant_id       => p_applicant_id,
        p_selected_store_ids => ARRAY[v_cg_store_id],
        p_hired_by_user_id   => p_hired_by_user_id,
        p_hired_date         => p_hired_date,
        p_remarks            => p_remarks
      );
    END IF;
  END IF;

  IF v_vac.id IS NULL THEN
    RAISE EXCEPTION 'vacancy % not found', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  -- SEC-02 Scope Guard: verify target vacancy belongs to caller's allowed accounts
  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts()))
     AND NOT (v_vac.account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: vacancy % is outside caller account scope', v_vac.vcode
      USING ERRCODE = '42501';
  END IF;

  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  -- ── Idempotent Guard ──
  IF v_app.status = 'Confirmed Onboard' THEN
    IF v_is_roving THEN
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
         AND assignment_type = 'Roving'
         AND deleted_at IS NULL
       ORDER BY created_at ASC LIMIT 1;
    ELSE
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE deleted_at IS NULL
         AND (
           applicant_id = v_app.id
           OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
         )
       ORDER BY created_at DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
      'ok',               true,
      'applicant_id',     v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id',     v_hr.id,
      'vcode',            v_app.vacancy_vcode,
      'idempotent',       true
    );
  END IF;

  -- Resolve requirement ID
  v_resolved_requirement_id := COALESCE(p_vacancy_requirement_id, v_app.vacancy_requirement_id);

  IF v_resolved_requirement_id IS NULL AND NOT v_is_roving THEN
    SELECT vr.id INTO v_resolved_requirement_id
      FROM public.vacancy_requirements vr
     WHERE vr.vacancy_id = v_vac.id
       AND GREATEST(
             (SELECT count(*) FROM public.plantilla p
               WHERE p.vacancy_requirement_id = vr.id
                 AND p.status = 'Active'
                 AND COALESCE(p.is_deleted, false) = false),
             (SELECT count(*) FROM public.applicants a
               WHERE a.vacancy_requirement_id = vr.id
                 AND a.status = 'Confirmed Onboard'
                 AND COALESCE(a.is_archived, false) = false
                 AND a.id <> p_applicant_id)
           ) < vr.hc_needed
     ORDER BY vr.created_at
     LIMIT 1;

    IF v_resolved_requirement_id IS NULL THEN
      SELECT id INTO v_resolved_requirement_id
        FROM public.vacancy_requirements
       WHERE vacancy_id = v_vac.id
       ORDER BY created_at
       LIMIT 1;
    END IF;
  END IF;

  IF p_hired_by_user_id IS NOT NULL THEN
    v_hired_by_id := p_hired_by_user_id;
  ELSE
    v_hired_by_id := public.get_my_auth_uid();
  END IF;

  UPDATE public.applicants
     SET status               = 'Confirmed Onboard',
         last_name            = COALESCE(p_last_name,      last_name),
         first_name           = COALESCE(p_first_name,     first_name),
         middle_name          = COALESCE(p_middle_name,    middle_name),
         full_name            = COALESCE(p_full_name,      full_name),
         contact_number       = COALESCE(p_contact_number, contact_number),
         remarks              = COALESCE(p_remarks,        remarks),
         hired_date           = COALESCE(p_hired_date,     hired_date),
         hired_by             = v_hired_by_id::text,
         roving_assignment_id = COALESCE(
                                  p_roving_assignment_id,
                                  roving_assignment_id
                                ),
         vacancy_requirement_id = COALESCE(
                                    v_resolved_requirement_id,
                                    vacancy_requirement_id
                                  ),
         last_activity_at     = NOW(),
         last_activity_by     = v_profile_id,
         updated_at           = NOW()
   WHERE id = p_applicant_id;

  SELECT * INTO v_app FROM public.applicants WHERE id = p_applicant_id;

  -- Option A Fast-Track for existing Active Plantilla employee in same account
  SELECT plt.* INTO v_existing_plt
    FROM public.plantilla plt
   WHERE plt.account = v_vac.account
     AND (
       plt.employee_no ILIKE v_app.full_name
       OR LOWER(TRIM(plt.employee_name)) = LOWER(TRIM(v_app.full_name))
     )
     AND plt.status IN ('Active', 'On Leave')
     AND NOT COALESCE(plt.is_deleted, false)
     AND NOT COALESCE(plt.is_archived, false)
     AND plt.employee_no IS NOT NULL
   LIMIT 1
  FOR UPDATE;

  IF v_existing_plt.id IS NOT NULL THEN
    v_roving_id := COALESCE(v_existing_plt.roving_assignment_id, p_roving_assignment_id, v_app.roving_assignment_id);
    IF v_roving_id IS NULL AND v_existing_plt.coverage_slot_id IS NULL THEN
      INSERT INTO public.roving_assignments (
        master_applicant_id, account, account_id,
        primary_vcode, label, created_by, updated_by
      ) VALUES (
        v_app.id, v_vac.account, v_vac.account_id,
        COALESCE(v_existing_plt.vcode, v_vac.vcode),
        v_app.full_name,
        v_profile_id, v_profile_id
      )
      RETURNING id INTO v_roving_id;
    END IF;

    UPDATE public.plantilla
       SET deployment_type      = 'Roving',
           roving_assignment_id = CASE WHEN coverage_slot_id IS NULL THEN COALESCE(roving_assignment_id, v_roving_id) ELSE roving_assignment_id END,
           updated_at           = NOW(),
           updated_by           = v_profile_id
     WHERE id = v_existing_plt.id
     RETURNING * INTO v_existing_plt;

    IF v_existing_plt.vcode IS NOT NULL AND NOT (v_existing_plt.vcode LIKE 'CG-%') THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id, coverage_group_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_existing_plt.roving_assignment_id, v_existing_plt.coverage_group_id,
        v_existing_plt.vacancy_id, v_existing_plt.vcode,
        v_existing_plt.store_name, v_existing_plt.account,
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL) DO NOTHING;
    END IF;

    INSERT INTO public.plantilla_store_links (
      plantilla_id, roving_assignment_id, coverage_group_id,
      vacancy_id, vcode, store_name, account,
      status, linked_at, linked_by, created_by, updated_by
    ) VALUES (
      v_existing_plt.id, v_existing_plt.roving_assignment_id, v_existing_plt.coverage_group_id,
      v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
      'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
    )
    ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
    DO UPDATE SET
      status      = 'Active',
      unlinked_at = NULL,
      unlinked_by = NULL,
      updated_at  = NOW(),
      updated_by  = v_profile_id
    RETURNING id INTO v_plt_store_link_id;

    -- SEC-04: Route Option A fast-track slot occupancy through fn_set_slot_status (ADR-001 Rule 1)
    FOR v_target_slot IN
      SELECT id, slot_status
        FROM public.plantilla_slots
       WHERE legacy_vcode = v_vac.vcode
         AND closed_at IS NULL
         AND slot_status IN ('open', 'pipeline', 'hr_processing')
    LOOP
      IF v_target_slot.slot_status = 'pipeline' THEN
        PERFORM public.fn_set_slot_status(
          p_slot_id               => v_target_slot.id,
          p_new_status            => 'hr_processing',
          p_reason_code           => 'REPLACEMENT',
          p_performed_by          => v_profile_id,
          p_remarks               => 'confirm_applicant_onboard: Option A fast-track pipeline->hr_processing for ' || v_vac.vcode,
          p_occupant_plantilla_id => NULL
        );
      END IF;

      PERFORM public.fn_set_slot_status(
        p_slot_id               => v_target_slot.id,
        p_new_status            => 'occupied',
        p_reason_code           => NULL,
        p_performed_by          => v_profile_id,
        p_remarks               => 'confirm_applicant_onboard: Option A fast-track occupied by plantilla ' || v_existing_plt.id::text,
        p_occupant_plantilla_id => v_existing_plt.id
      );
    END LOOP;

    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_profile_id
     WHERE id = v_vac.id;

    PERFORM public.fn_sync_employee_store_allocations(v_existing_plt.employee_no);

    RETURN jsonb_build_object(
      'ok',                      true,
      'applicant_id',            v_app.id,
      'applicant_status',        v_app.status,
      'hr_emploc_id',            NULL,
      'plantilla_id',            v_existing_plt.id,
      'plantilla_store_link_id', v_plt_store_link_id,
      'vcode',                   v_vac.vcode,
      'hired_by_user_id',        v_hired_by_id,
      'is_roving',               true,
      'fast_tracked',            true,
      'skipped_hr_emploc',       true
    );
  END IF;

  SELECT * INTO v_hr
    FROM public.hr_emploc
   WHERE applicant_id = p_applicant_id
     AND deleted_at IS NULL
   LIMIT 1;

  IF v_hr.id IS NOT NULL THEN
    UPDATE public.hr_emploc
       SET hr_status              = COALESCE(hr_status, 'Pending'),
           vacancy_requirement_id = COALESCE(vacancy_requirement_id, v_resolved_requirement_id),
           updated_at             = NOW()
      WHERE id = v_hr.id
     RETURNING * INTO v_hr;
  ELSE
    IF NOT v_is_roving THEN
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores,
        vacancy_requirement_id
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb,
        v_resolved_requirement_id
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id',               v_app.id,
      'hr_emploc_id',               v_hr.id,
      'vacancy_id',                 v_vac.id,
      'role',                       v_role,
      'hired_by_user_id',           v_hired_by_id,
      'endorsed_by_deployer_id',    p_endorsed_by_deployer_id,
      'endorsed_by_name',           p_endorsed_by_name,
      'is_roving',                  v_is_roving,
      'hired_date',                 v_app.hired_date,
      'late_store_linked',          v_late_result IS NOT NULL,
      'vacancy_requirement_id',     v_resolved_requirement_id,
      'movement_at',                NOW()
    )
  );

  IF v_resolved_requirement_id IS NOT NULL THEN
    IF p_vacancy_requirement_id IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM public.vacancy_requirements vr
         WHERE vr.id = p_vacancy_requirement_id
           AND GREATEST(
                 (SELECT count(*) FROM public.plantilla p
                   WHERE p.vacancy_requirement_id = vr.id
                     AND p.status = 'Active'
                     AND COALESCE(p.is_deleted, false) = false),
                 (SELECT count(*) FROM public.applicants a
                   WHERE a.vacancy_requirement_id = vr.id
                     AND a.status = 'Confirmed Onboard'
                     AND COALESCE(a.is_archived, false) = false
                     AND a.id <> p_applicant_id)
               ) >= vr.hc_needed
      ) THEN
        RAISE EXCEPTION 'requirement_already_full'
          USING MESSAGE = 'The selected position requirement has no remaining headcount. Another hire may have filled it concurrently.',
                HINT    = 'Refresh the vacancy and select a different requirement.';
      END IF;
    END IF;
  END IF;

  IF NOT v_is_roving THEN
    v_slot_sync_result := public.fn_sync_slot_to_hr_processing(
      p_vcode        => v_vac.vcode,
      p_applicant_id => v_app.id,
      p_performed_by => v_profile_id,
      p_source_fn    => 'confirm_applicant_onboard',
      p_slot_id      => v_app.slot_id
    );

    IF v_hr.id IS NOT NULL AND (v_slot_sync_result->>'slot_id') IS NOT NULL AND v_hr.coverage_slot_id IS NULL THEN
      UPDATE public.hr_emploc
         SET slot_id = (v_slot_sync_result->>'slot_id')::uuid
       WHERE id = v_hr.id
         AND slot_id IS NULL;

      UPDATE public.applicants
         SET slot_id = (v_slot_sync_result->>'slot_id')::uuid
       WHERE id = v_app.id
         AND slot_id IS NULL
         AND coverage_slot_id IS NULL;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok',                       true,
    'applicant_id',             v_app.id,
    'applicant_status',         v_app.status,
    'hr_emploc_id',             v_hr.id,
    'vcode',                    v_vac.vcode,
    'hired_by_user_id',         v_hired_by_id,
    'hired_date',               v_app.hired_date,
    'is_roving',                v_is_roving,
    'late_store_linked',        v_late_result,
    'vacancy_requirement_id',   v_resolved_requirement_id
  );
END;
$function$;


-- ────────────────────────────────────────────────────────────────────────────
-- 5. SEC-04: Rewire public._assign_and_deploy_emploc_core Coverage Group slot writes
--    through public.fn_set_slot_status (ADR-001 Rule 1 Slot Authority)
--    Surgical base: 20262606000188_partial_roving_coverage_store_onboarding_and_agawa_backfill.sql
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._assign_and_deploy_emploc_core(
  p_hr_emploc_id uuid,
  p_employee_no text,
  p_confirm_reuse boolean DEFAULT false,
  p_reuse_reason text DEFAULT NULL::text,
  p_actor_profile_id uuid DEFAULT NULL::uuid,
  p_source_fn text DEFAULT 'assign_and_deploy_core'::text
)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_profile_id uuid := COALESCE(p_actor_profile_id, public.get_my_profile_id());
  v_actor_name       text := public.get_my_full_name();
  v_clean_id         text := btrim(COALESCE(p_employee_no, ''));
  v_emp              public.hr_emploc;
  v_app              public.applicants;
  v_pl               public.plantilla;
  v_existing_pl      public.plantilla;
  v_slot_id          uuid := NULL;
  v_slot_auth        jsonb;
  v_pool_slot_id     uuid := NULL;
  v_is_pool          boolean := false;
  v_pool_type_id     uuid;
  v_home_account_id  uuid;
  v_home_acct        public.accounts;
  v_formatted_name   text;
  v_norm_name        text;
  v_reg              public.employee_number_registry;
  v_match            jsonb;
  v_is_rehire        boolean := false;
  v_dup_reg          public.employee_number_registry;
  v_dup_match        jsonb;
  r_cand             RECORD;
  r_link             RECORD;
  v_target_slot      RECORD;
BEGIN
  -- 1. Format validation (rejects empty, spaces, (PENDING), invalid chars)
  IF v_clean_id = '' OR upper(v_clean_id) = '(PENDING)' OR v_clean_id !~ '^[A-Za-z0-9._-]+$' THEN
    RAISE EXCEPTION 'EMPLOYEE_NO_FORMAT_INVALID: Employee number "%" is invalid. Allowed: alphanumeric, dots, underscores, dashes.', v_clean_id
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'EMPLOYEE_NO_FORMAT_INVALID')::text;
  END IF;

  -- 2. Pending deletion lock
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  -- 3. Lock hr_emploc record
  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record % not found or archived', p_hr_emploc_id
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  -- 3b. Stage gate for Add Emploc (assign_hr_emploc_number):
  IF p_source_fn = 'assign_hr_emploc_number' THEN
    IF v_emp.hr_status = 'Pending' THEN
      IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'INVALID_STATE_FOR_ASSIGN: Record must be in "For Emploc" status before assigning an Employee ID (current hr_status: "Pending"). Ops must upload and submit requirements first.'
          USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE_FOR_ASSIGN')::text;
      END IF;
    ELSIF v_emp.hr_status NOT IN ('For Emploc', 'Complete') AND v_emp.status <> 'Moved to Plantilla' THEN
      RAISE EXCEPTION 'INVALID_STATE_FOR_ASSIGN: Cannot assign Employee ID from hr_status "%". Expected "For Emploc".', v_emp.hr_status
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE_FOR_ASSIGN')::text;
    END IF;
  END IF;

  -- Safe idempotent no-op check: already moved with same number
  IF v_emp.status = 'Moved to Plantilla' AND v_emp.employee_no = v_clean_id THEN
    SELECT * INTO v_existing_pl
    FROM public.plantilla
    WHERE hr_emploc_id = p_hr_emploc_id
      AND COALESCE(is_deleted, false) = false
    LIMIT 1;
    IF FOUND THEN
      RETURN v_existing_pl;
    END IF;
  END IF;

  -- Fetch structured applicant data
  IF v_emp.applicant_id IS NOT NULL THEN
    SELECT * INTO v_app FROM public.applicants WHERE id = v_emp.applicant_id;
  END IF;

  -- 4. REQUIRED PLANTILLA FIELDS VALIDATION (NO SILENT DEFAULTS)
  IF v_emp.hired_date IS NULL THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: hired_date is required before deployment to Plantilla'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'hired_date')::text;
  END IF;

  IF (v_app.first_name IS NULL OR btrim(v_app.first_name) = '') OR
     (v_app.last_name IS NULL OR btrim(v_app.last_name) = '') THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: applicant first_name and last_name are required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'applicant_name')::text;
  END IF;

  IF v_emp.account_id IS NULL AND (v_emp.account IS NULL OR btrim(v_emp.account) = '') THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: account is required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'account')::text;
  END IF;

  IF v_emp.position IS NULL OR btrim(v_emp.position) = '' THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: position is required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'position')::text;
  END IF;

  IF COALESCE(v_emp.assignment_type::text, 'Stationary') NOT IN ('Roving', 'Coverage') AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.store_id IS NULL AND (v_emp.store_name IS NULL OR btrim(v_emp.store_name) = '') THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: store is required for stationary deployment'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'store')::text;
    END IF;
    IF v_emp.store_id IS NULL THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: store_id is required for stationary deployment'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'store_id')::text;
    END IF;
  END IF;

  -- Resolve canonical formatted name and normalized name
  v_formatted_name := v_app.last_name || ', ' || v_app.first_name || COALESCE(' ' || NULLIF(btrim(v_app.middle_name), ''), '');
  v_norm_name      := public.fn_normalize_person_name(v_app.first_name, v_app.middle_name, v_app.last_name, NULL, NULL);

  -- 5. REGISTRY RACE-SAFE CHECK UNDER FOR UPDATE LOCK
  SELECT * INTO v_reg
  FROM public.employee_number_registry
  WHERE emploc_no = v_clean_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_reg.status IN ('assigned', 'rehire_reused') THEN
      v_match := public.fn_match_person_name(v_reg.normalized_name, v_norm_name);

      IF (v_match->>'match')::boolean = false THEN
        RAISE EXCEPTION 'EMPLOYEE_NO_ALREADY_ASSIGNED: Employee number % is permanently registered to %',
          v_clean_id, v_reg.display_name
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_NO_ALREADY_ASSIGNED',
                  'employee_no', v_clean_id,
                  'registered_to', v_reg.display_name,
                  'registered_norm', v_reg.normalized_name,
                  'incoming_name', v_formatted_name,
                  'reason', v_match->>'reason'
                )::text;
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE (p.employee_no = v_clean_id OR p.emploc_no = v_clean_id)
          AND p.status IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation')
          AND COALESCE(p.is_deleted, false) = false
          AND (p.hr_emploc_id IS NULL OR p.hr_emploc_id <> p_hr_emploc_id)
      ) OR EXISTS (
        SELECT 1 FROM public.hr_emploc h
        WHERE (h.employee_no = v_clean_id OR h.emploc_no = v_clean_id)
          AND h.status NOT IN ('Backout', 'Moved to Plantilla')
          AND h.id <> p_hr_emploc_id
          AND h.deleted_at IS NULL
      ) THEN
        RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active placement or active Plantilla record with number %',
          v_formatted_name, v_clean_id
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_ALREADY_ACTIVE',
                  'employee_no', v_clean_id,
                  'person', v_formatted_name
                )::text;
      END IF;

      IF (v_match->>'type') = 'WARNING_MISSING_MIDDLE' THEN
        IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
          RAISE EXCEPTION 'MIDDLE_NAME_CONFIRM_REQUIRED: % matches % on first and last name, but one record is missing a middle name. Confirm with reason.',
            v_formatted_name, v_reg.display_name
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'MIDDLE_NAME_CONFIRM_REQUIRED',
                    'employee_no', v_clean_id,
                    'registered_to', v_reg.display_name,
                    'incoming_name', v_formatted_name,
                    'reason', v_match->>'reason'
                  )::text;
        END IF;
      END IF;

      IF v_reg.source_hr_emploc_id IS DISTINCT FROM p_hr_emploc_id THEN
        IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
          RAISE EXCEPTION 'REHIRE_CONFIRM_REQUIRED: % was previously assigned number %. Confirm rehire reuse with reason.',
            v_formatted_name, v_clean_id
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'REHIRE_CONFIRM_REQUIRED',
                    'employee_no', v_clean_id,
                    'display_name', v_reg.display_name,
                    'first_assigned_at', v_reg.first_assigned_at,
                    'status', v_reg.status
                  )::text;
        END IF;
        v_is_rehire := true;
      END IF;
    END IF;
  END IF;

  FOR r_cand IN (
    SELECT *
    FROM public.employee_number_registry reg
    WHERE reg.emploc_no <> v_clean_id
      AND reg.status IN ('assigned', 'rehire_reused')
      AND (
        split_part(reg.normalized_name, '|', 1) = split_part(v_norm_name, '|', 1)
        OR (split_part(reg.normalized_name, '|', 1) IN ('HAUTEA', 'HUATEA') AND split_part(v_norm_name, '|', 1) IN ('HAUTEA', 'HUATEA'))
        OR EXISTS (
          SELECT 1 FROM public.registry_name_aliases rna
          WHERE rna.normalized_name = reg.normalized_name OR rna.alias_normalized_name = reg.normalized_name
        )
      )
  ) LOOP
    v_dup_match := public.fn_match_person_name(r_cand.normalized_name, v_norm_name);
    IF (v_dup_match->>'match')::boolean = true THEN
      IF (v_dup_match->>'type') <> 'WARNING_MISSING_MIDDLE' AND (
        EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE (p.employee_no = r_cand.emploc_no OR p.emploc_no = r_cand.emploc_no)
            AND p.status IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation')
            AND COALESCE(p.is_deleted, false) = false
            AND (p.hr_emploc_id IS NULL OR p.hr_emploc_id <> p_hr_emploc_id)
        ) OR EXISTS (
          SELECT 1 FROM public.hr_emploc h
          WHERE (h.employee_no = r_cand.emploc_no OR h.emploc_no = r_cand.emploc_no)
            AND h.status NOT IN ('Backout', 'Moved to Plantilla')
            AND h.id <> p_hr_emploc_id
            AND h.deleted_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active placement or active Plantilla record under Employee number %',
          v_formatted_name, r_cand.emploc_no
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_ALREADY_ACTIVE',
                  'employee_no', r_cand.emploc_no,
                  'person', v_formatted_name
                )::text;
      END IF;

      IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
        IF (v_dup_match->>'type') = 'WARNING_MISSING_MIDDLE' THEN
          RAISE EXCEPTION 'MIDDLE_NAME_CONFIRM_REQUIRED (POSSIBLE_DUPLICATE_PERSON): % matches % (Employee number %) on first and last name with one side missing middle name. Confirm with reason.',
            v_formatted_name, r_cand.display_name, r_cand.emploc_no
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'MIDDLE_NAME_CONFIRM_REQUIRED',
                    'secondary_code', 'POSSIBLE_DUPLICATE_PERSON',
                    'new_employee_no', v_clean_id,
                    'existing_employee_no', r_cand.emploc_no,
                    'display_name', r_cand.display_name
                  )::text;
        ELSE
          RAISE EXCEPTION 'POSSIBLE_DUPLICATE_PERSON: % is already registered with Employee number %. Confirm duplicate assignment with reason.',
            v_formatted_name, r_cand.emploc_no
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'POSSIBLE_DUPLICATE_PERSON',
                    'new_employee_no', v_clean_id,
                    'existing_employee_no', r_cand.emploc_no,
                    'display_name', r_cand.display_name,
                    'match_type', v_dup_match->>'type'
                  )::text;
        END IF;
      END IF;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM public.hr_emploc h
    LEFT JOIN public.applicants a ON a.id = h.applicant_id
    WHERE h.id <> p_hr_emploc_id
      AND h.deleted_at IS NULL
      AND h.status NOT IN ('Backout', 'Moved to Plantilla')
      AND h.employee_no IS NOT NULL AND btrim(h.employee_no) <> ''
      AND (public.fn_match_person_name(
            public.fn_normalize_person_name(a.first_name, a.middle_name, a.last_name, NULL, coalesce(h.employee_name_snapshot, h.applicant_name)),
            v_norm_name
          )->>'match')::boolean = true
      AND (public.fn_match_person_name(
            public.fn_normalize_person_name(a.first_name, a.middle_name, a.last_name, NULL, coalesce(h.employee_name_snapshot, h.applicant_name)),
            v_norm_name
          )->>'type') <> 'WARNING_MISSING_MIDDLE'
  ) THEN
    RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active hr_emploc record',
      v_formatted_name
      USING ERRCODE = '23505',
            DETAIL = jsonb_build_object(
              'code', 'EMPLOYEE_ALREADY_ACTIVE',
              'person', v_formatted_name
            )::text;
  END IF;

  -- 6. SLOT SELECTION AND RESERVATION (Stationary non-pool non-roving)
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type::text, 'Stationary') NOT IN ('Roving', 'Coverage') AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.slot_id IS NOT NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE id = v_emp.slot_id
        AND slot_status IN ('open', 'hr_processing')
      FOR UPDATE SKIP LOCKED;
    END IF;

    IF v_slot_id IS NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_emp.vcode
        AND slot_status = 'open'
      ORDER BY created_at ASC
      LIMIT 1
      FOR UPDATE SKIP LOCKED;
    END IF;

    IF v_slot_id IS NULL THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: No available headcount slot for VCode %', v_emp.vcode
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'vcode', v_emp.vcode)::text;
    END IF;

    v_slot_auth := public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_reason_code  => NULL,
      p_performed_by => v_actor_profile_id,
      p_remarks      => 'auto_move_to_plantilla: reserved for hr_emploc ' || p_hr_emploc_id::text
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: Slot % reservation blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'slot_id', v_slot_id, 'blocked_reason', v_slot_auth->>'blocked_reason')::text;
    END IF;
  END IF;

  -- 7. INSERT INTO PLANTILLA
  IF v_is_pool THEN
    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;

    INSERT INTO plantilla (
      account,              account_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,             last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      is_pool_employee,     pool_type_id,
      requesting_account,   requesting_account_id,   requesting_store_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_home_acct.account_name, v_home_acct.id,
      NULL, NULL,
      v_emp.position,           v_emp.position_id_snapshot,
      v_clean_id,               v_clean_id,
      v_formatted_name,         v_formatted_name,
      v_app.first_name,         v_app.middle_name,       v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,       v_emp.philhealth_snapshot,    v_emp.pagibig_snapshot,
      v_emp.hired_date,         v_emp.vacancy_id,             v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,          v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot,  v_emp.area_name_snapshot,
      v_emp.id,
      true,                     v_pool_type_id,
      v_emp.account,            v_emp.account_id,             v_emp.store_id,
      'Active',                 CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

  ELSIF v_emp.coverage_slot_id IS NOT NULL OR COALESCE(v_emp.assignment_type::text, 'Stationary') = 'Coverage' THEN
    -- Coverage Group deployment path (respects plantilla_roving_coverage_mutex_chk: roving_assignment_id IS NULL)
    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,          last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,         pagibig_no,
      date_hired,           vacancy_id,            vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      coverage_slot_id,     coverage_group_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,            updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
      v_emp.store_id, v_emp.store_name,
      v_emp.position, v_emp.position_id_snapshot,
      v_clean_id, v_clean_id,
      v_formatted_name, v_formatted_name,
      v_app.first_name, v_app.middle_name, v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date, v_emp.vacancy_id, v_emp.vacancy_code_snapshot,
      COALESCE(v_emp.vcode, v_emp.vacancy_code_snapshot),
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.coverage_slot_id, v_emp.coverage_group_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    -- Link all currently Confirmed stores from hr_emploc_store_links into plantilla_store_links
    FOR r_link IN
      SELECT hsl.id, hsl.store_id, hsl.vacancy_id, COALESCE(hsl.vcode, s.vcode) AS resolved_vcode,
             COALESCE(hsl.store_name, s.store_name) AS resolved_store_name
        FROM public.hr_emploc_store_links hsl
        LEFT JOIN public.stores s ON s.id = hsl.store_id
       WHERE hsl.hr_emploc_id = v_emp.id
         AND hsl.status = 'Confirmed'
         AND hsl.deleted_at IS NULL
    LOOP
      IF r_link.resolved_vcode IS NOT NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, coverage_group_id, hr_emploc_store_link_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_pl.id, v_emp.coverage_group_id, r_link.id,
          r_link.vacancy_id, r_link.resolved_vcode, r_link.resolved_store_name, v_emp.account,
          'Active', NOW(), v_actor_profile_id, v_actor_profile_id, v_actor_profile_id
        )
        ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL)
        DO UPDATE SET
          coverage_group_id = COALESCE(public.plantilla_store_links.coverage_group_id, EXCLUDED.coverage_group_id),
          status            = 'Active',
          updated_at        = NOW(),
          updated_by        = v_actor_profile_id;

        -- SEC-04: Route Coverage Group store slot occupancy through fn_set_slot_status (ADR-001 Rule 1)
        FOR v_target_slot IN
          SELECT id, slot_status
            FROM public.plantilla_slots
           WHERE legacy_vcode = r_link.resolved_vcode
             AND closed_at IS NULL
             AND slot_status IN ('open', 'pipeline', 'hr_processing')
        LOOP
          IF v_target_slot.slot_status = 'pipeline' THEN
            PERFORM public.fn_set_slot_status(
              p_slot_id               => v_target_slot.id,
              p_new_status            => 'hr_processing',
              p_reason_code           => 'REPLACEMENT',
              p_performed_by          => v_actor_profile_id,
              p_remarks               => 'assign_and_deploy_core: Coverage store pipeline->hr_processing for ' || r_link.resolved_vcode,
              p_occupant_plantilla_id => NULL
            );
          END IF;

          PERFORM public.fn_set_slot_status(
            p_slot_id               => v_target_slot.id,
            p_new_status            => 'occupied',
            p_reason_code           => NULL,
            p_performed_by          => v_actor_profile_id,
            p_remarks               => 'assign_and_deploy_core: Coverage store slot occupied by plantilla ' || v_pl.id::text,
            p_occupant_plantilla_id => v_pl.id
          );
        END LOOP;

        UPDATE public.vacancies
           SET status     = 'Filled',
               updated_at = NOW(),
               updated_by = v_actor_profile_id
         WHERE vcode = r_link.resolved_vcode
           AND deleted_at IS NULL
           AND status NOT IN ('Filled', 'Closed', 'Archived');
      END IF;
    END LOOP;

    IF v_emp.coverage_slot_id IS NOT NULL THEN
      PERFORM public.fn_sync_coverage_slot_to_active(
        p_coverage_slot_id => v_emp.coverage_slot_id,
        p_plantilla_id     => v_pl.id,
        p_performed_by     => v_actor_profile_id,
        p_source_fn        => p_source_fn
      );
    END IF;

    PERFORM public.fn_sync_employee_store_allocations(v_clean_id);

  ELSIF COALESCE(v_emp.assignment_type::text, 'Stationary') = 'Roving' THEN
    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,          last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,         pagibig_no,
      date_hired,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      roving_assignment_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,            updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
      v_emp.position, v_emp.position_id_snapshot,
      v_clean_id, v_clean_id,
      v_formatted_name, v_formatted_name,
      v_app.first_name, v_app.middle_name, v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.roving_assignment_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    INSERT INTO public.plantilla_store_links (
      plantilla_id, roving_assignment_id, hr_emploc_store_link_id,
      vacancy_id, vcode, store_name, account,
      status, linked_at, linked_by, created_by, updated_by
    )
    SELECT
      v_pl.id, sl.roving_assignment_id, sl.id,
      sl.vacancy_id, sl.vcode, sl.store_name, sl.account,
      'Active', NOW(), v_actor_profile_id, v_actor_profile_id, v_actor_profile_id
    FROM public.hr_emploc_store_links sl
    WHERE sl.hr_emploc_id = v_emp.id
      AND sl.status = 'Confirmed'
      AND sl.deleted_at IS NULL
      AND sl.vcode IS NOT NULL
    ON CONFLICT (plantilla_id, vcode) WHERE (deleted_at IS NULL) DO NOTHING;

    PERFORM public.fn_sync_employee_store_allocations(v_clean_id);

  ELSE
    -- Pure stationary path
    INSERT INTO plantilla (
      account,              account_id,            chain_id,             store_id,
      store_name,           position,              position_id,
      province_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,           last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account,        v_emp.account_id,       v_emp.chain_id,       v_emp.store_id,
      v_emp.store_name,     v_emp.position,         v_emp.position_id_snapshot,
      v_emp.province_id,
      v_clean_id,           v_clean_id,
      v_formatted_name,     v_formatted_name,
      v_app.first_name,     v_app.middle_name,      v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,   v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,     v_emp.vacancy_id,        v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,      v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      'Active',             CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id, NOW(), NOW()
    )
    RETURNING * INTO v_pl;
  END IF;

  -- 8. FINALIZE SLOT AS 'occupied' (RECONCILED VALUE)
  IF v_slot_id IS NOT NULL THEN
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id               => v_slot_id,
      p_new_status            => 'occupied',
      p_reason_code           => NULL,
      p_performed_by          => v_actor_profile_id,
      p_remarks               => 'auto_move_to_plantilla: slot occupied by plantilla ' || v_pl.id::text,
      p_occupant_plantilla_id => v_pl.id
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: Slot % occupancy blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'slot_id', v_slot_id, 'blocked_reason', v_slot_auth->>'blocked_reason')::text;
    END IF;
  END IF;

  -- 9. VACANCY CLOSURE (if all slots filled)
  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type::text, 'Stationary') NOT IN ('Roving', 'Coverage') AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor_profile_id
       WHERE id = v_emp.vacancy_id
         AND NOT EXISTS (
           SELECT 1 FROM public.plantilla_slots ps
           WHERE ps.legacy_vcode = v_emp.vcode
             AND ps.is_roving    = false
             AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
         );
    END IF;

    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor_profile_id
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.plantilla_slots ps
         WHERE ps.legacy_vcode = v_emp.vcode
           AND ps.is_roving    = false
           AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
       );
  END IF;

  -- 10. STAMP REGISTRY BEFORE HR_EMPLOC UPDATE (so trigger sees registered entry)
  INSERT INTO public.employee_number_registry (
    emploc_no, normalized_name, display_name, status,
    first_assigned_at, first_assigned_by, last_assigned_at, last_assigned_by,
    source_hr_emploc_id, source_plantilla_id,
    history
  ) VALUES (
    v_clean_id, v_norm_name, v_formatted_name,
    CASE WHEN v_is_rehire THEN 'rehire_reused' ELSE 'assigned' END,
    NOW(), v_actor_profile_id, NOW(), v_actor_profile_id,
    p_hr_emploc_id, v_pl.id,
    jsonb_build_array(
      jsonb_build_object(
        'action', CASE WHEN v_is_rehire THEN 'rehire_reuse' ELSE 'initial_assignment' END,
        'actor', v_actor_profile_id,
        'timestamp', now(),
        'source', p_source_fn,
        'reuse_reason', p_reuse_reason
      )
    )
  )
  ON CONFLICT (emploc_no) DO UPDATE SET
    normalized_name     = EXCLUDED.normalized_name,
    display_name        = EXCLUDED.display_name,
    status              = EXCLUDED.status,
    last_assigned_at    = NOW(),
    last_assigned_by    = v_actor_profile_id,
    source_hr_emploc_id = p_hr_emploc_id,
    source_plantilla_id = v_pl.id,
    history             = public.employee_number_registry.history || EXCLUDED.history;

  -- 11. UPDATE HR_EMPLOC STATUS (Final: Moved to Plantilla / Transferred)
  UPDATE public.hr_emploc
     SET employee_no           = v_clean_id,
         emploc_no             = v_clean_id,
         status                = 'Moved to Plantilla',
         hr_status             = 'Transferred',
         moved_to_plantilla_at = NOW(),
         moved_to_plantilla_by = v_actor_profile_id,
         updated_at            = NOW(),
         updated_by            = v_actor_profile_id
   WHERE id = p_hr_emploc_id;

  -- 11b. ENQUEUE 3-DAY DOCUMENT PURGE (never rolls back deployment on error)
  BEGIN
    PERFORM public.enqueue_hr_emploc_docs_cleanup(p_hr_emploc_id, 'deployed_3day_ttl', interval '3 days');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- 12. SINGLE AUDIT / TIMELINE LOG ENTRY
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_emp),
    jsonb_build_object(
      'action', 'assign_and_move_to_plantilla',
      'employee_no', v_clean_id,
      'plantilla_id', v_pl.id,
      'actor_name', v_actor_name,
      'actor_id', v_actor_profile_id,
      'source', p_source_fn,
      'log_message', format('Assigned Employee ID %s and automatically moved to Plantilla (Slot %s) by %s', v_clean_id, coalesce(v_slot_id::text, v_emp.coverage_slot_id::text, 'Pool/Roving'), v_actor_name)
    )
  );

  RETURN v_pl;
END;
$function$;


-- ────────────────────────────────────────────────────────────────────────────
-- 6. SEC-06: Least-Privilege Table Grants on announcements & Role Guard on check_and_notify_on_leave_edr()
--    Surgical base: 20262606000180 & 20262606000184
-- ────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON TABLE public.announcements FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.announcement_acknowledgements FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.announcements TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.announcement_acknowledgements TO authenticated;
GRANT ALL ON TABLE public.announcements TO service_role;
GRANT ALL ON TABLE public.announcement_acknowledgements TO service_role;

CREATE OR REPLACE FUNCTION public.check_and_notify_on_leave_edr()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rec               record;
  v_edr_str           text;
  v_edr_date          date;
  v_days_lapsed       integer;
  v_hrco_id           uuid;
  v_om_id             uuid;
  v_notifs_sent       integer := 0;
  v_today             date := CURRENT_DATE;
BEGIN
  -- SEC-06 Caller Guard: allow service_role / pg_cron (auth.uid() IS NULL) or authorized operational roles (role_level >= 30)
  IF auth.uid() IS NOT NULL AND NOT (public.i_have_full_access() OR COALESCE(public.get_my_role_level(), 0) >= 30) THEN
    RETURN jsonb_build_object(
      'status', 'skipped_insufficient_role',
      'notifications_dispatched', 0,
      'evaluated_at', NOW()
    );
  END IF;

  FOR v_rec IN
    SELECT p.id, p.account_id, p.employee_no, p.first_name, p.last_name, p.store_name, p.remarks
    FROM public.plantilla p
    WHERE p.status IN ('On Leave', 'on_leave')
      AND COALESCE(p.is_deleted, false) = false
      AND COALESCE(p.is_archived, false) = false
      AND p.remarks ILIKE '%EDR:%'
  LOOP
    -- Extract EDR (format YYYY-MM-DD) from remarks
    v_edr_str := substring(v_rec.remarks from 'EDR:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})');
    
    IF v_edr_str IS NOT NULL THEN
      BEGIN
        v_edr_date := v_edr_str::date;
      EXCEPTION WHEN OTHERS THEN
        v_edr_date := NULL;
      END;

      IF v_edr_date IS NOT NULL AND v_today >= v_edr_date THEN
        v_days_lapsed := v_today - v_edr_date;

        -- Resolve HRCO for this account
        SELECT up.id INTO v_hrco_id
        FROM public.user_scopes us
        JOIN public.users_profile up ON up.id = us.user_id
        JOIN public.roles r ON r.id = up.role_id
        WHERE us.account_id = v_rec.account_id
          AND r.role_name = 'HRCO'
          AND up.is_active = true
          AND up.archived_at IS NULL
        LIMIT 1;

        -- Resolve OM for this account or account group
        SELECT up.id INTO v_om_id
        FROM public.user_scopes us
        JOIN public.users_profile up ON up.id = us.user_id
        JOIN public.roles r ON r.id = up.role_id
        JOIN public.accounts acc ON acc.id = v_rec.account_id
        WHERE (us.account_id = v_rec.account_id OR us.group_id = acc.group_id)
          AND r.role_name IN ('Operations Manager', 'OM')
          AND up.is_active = true
          AND up.archived_at IS NULL
        LIMIT 1;

        -- 1. Due Today (CURRENT_DATE = EDR): Notify HRCO
        IF v_days_lapsed = 0 THEN
          IF v_hrco_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.notifications n
            WHERE n.user_id = v_hrco_id
              AND n.type = 'LEAVE_RETURN_DUE'
              AND n.target_entity_id = v_rec.id
              AND n.created_at::date = v_today
          ) THEN
            INSERT INTO public.notifications (
              user_id, type, title, message, priority, target_entity_id, deep_link, created_at
            ) VALUES (
              v_hrco_id,
              'LEAVE_RETURN_DUE',
              'Employee Due to Return from Leave Today',
              format('%s %s (%s) at %s is scheduled to return today (%s). Please verify return or update leave status.',
                     v_rec.first_name, v_rec.last_name, v_rec.employee_no, COALESCE(v_rec.store_name, 'Unassigned Store'), v_edr_str),
              'normal',
              v_rec.id,
              format('/plantilla?accountId=%s&status=on_leave', v_rec.account_id),
              NOW()
            );
            v_notifs_sent := v_notifs_sent + 1;
          END IF;

        -- 2. Breach (CURRENT_DATE > EDR): Notify OM and HRCO
        ELSIF v_days_lapsed > 0 THEN
          -- Notify OM
          IF v_om_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.notifications n
            WHERE n.user_id = v_om_id
              AND n.type = 'LEAVE_RETURN_BREACH'
              AND n.target_entity_id = v_rec.id
              AND n.created_at::date = v_today
          ) THEN
            INSERT INTO public.notifications (
              user_id, type, title, message, priority, target_entity_id, deep_link, created_at
            ) VALUES (
              v_om_id,
              'LEAVE_RETURN_BREACH',
              'On-Leave SLA Breach: Overdue Return',
              format('SLA Breach: %s %s (%s) at %s exceeded EDR (%s) by %s day(s) without returning to Active duty.',
                     v_rec.first_name, v_rec.last_name, v_rec.employee_no, COALESCE(v_rec.store_name, 'Unassigned Store'), v_edr_str, v_days_lapsed),
              'urgent',
              v_rec.id,
              format('/plantilla?accountId=%s&status=on_leave', v_rec.account_id),
              NOW()
            );
            v_notifs_sent := v_notifs_sent + 1;
          END IF;

          -- Notify HRCO as well
          IF v_hrco_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.notifications n
            WHERE n.user_id = v_hrco_id
              AND n.type = 'LEAVE_RETURN_BREACH'
              AND n.target_entity_id = v_rec.id
              AND n.created_at::date = v_today
          ) THEN
            INSERT INTO public.notifications (
              user_id, type, title, message, priority, target_entity_id, deep_link, created_at
            ) VALUES (
              v_hrco_id,
              'LEAVE_RETURN_BREACH',
              'On-Leave SLA Breach: Overdue Return',
              format('SLA Breach: %s %s (%s) at %s is %s day(s) past scheduled EDR (%s). Action required to confirm return or extend leave.',
                     v_rec.first_name, v_rec.last_name, v_rec.employee_no, COALESCE(v_rec.store_name, 'Unassigned Store'), v_days_lapsed, v_edr_str),
              'urgent',
              v_rec.id,
              format('/plantilla?accountId=%s&status=on_leave', v_rec.account_id),
              NOW()
            );
            v_notifs_sent := v_notifs_sent + 1;
          END IF;
        END IF;

      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'ok',
    'notifications_dispatched', v_notifs_sent,
    'evaluated_at', NOW()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.check_and_notify_on_leave_edr() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_and_notify_on_leave_edr() TO authenticated, service_role;

COMMIT;
