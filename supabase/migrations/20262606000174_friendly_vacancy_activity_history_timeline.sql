-- Migration: 20262606000174_friendly_vacancy_activity_history_timeline.sql
-- Purpose:
--   Make the Vacancy Activity History timeline genuinely detailed and human-readable
--   (What happened, Who performed it, When it happened, and relevant context/reason).
--   1. Creates helper RPC `public.get_vacancy_activity_timeline(p_vacancy_id uuid)`
--      that aggregates and deduplicates chronological events across:
--      - Vacancy creation & attribute changes (`public.vacancies` & `public.audit_logs`)
--      - Candidate endorsements (`public.applicants`)
--      - Candidate pipeline stage progressions, follow-up date updates, and remarks (`public.applicant_status_history` & `public.audit_logs`)
--      - Candidate profile edits (`public.applicant_profile_edit_history`)
--      - Vacancy closure requests, withdrawals, approvals, and rejections (`public.vacancy_closure_requests`)
--      - HR Emploc onboarding endorsements & Plantilla deployments (`public.hr_emploc`)
--   2. Surgically updates `public.get_web_vacancy_detail(p_vacancy_id uuid)` (keeping the exact
--      30-column signature from `20262606000117`) so `activity_history` returns the rich timeline JSONB.

BEGIN;

-- ============================================================================
-- 1. Create public.get_vacancy_activity_timeline(p_vacancy_id uuid)
-- ============================================================================
DROP FUNCTION IF EXISTS public.get_vacancy_activity_timeline(uuid);
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
  v_req_hc         integer;
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
  WHERE v.id = p_vacancy_id;

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
        v_req_hc,
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
                COALESCE(al.old_data->>'required_headcount', '1'),
                COALESCE(al.new_data->>'required_headcount', '1')
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
      -- Prefer structured table logs over generic audit_logs when timestamps & keys collide
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

-- ============================================================================
-- 2. Surgically update public.get_web_vacancy_detail to use get_vacancy_activity_timeline
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_web_vacancy_detail(p_vacancy_id uuid)
RETURNS TABLE(
  vacancy_id uuid,
  vcode text,
  position_title text,
  employment_type text,
  vacancy_type text,
  account_id uuid,
  account_name text,
  group_id uuid,
  group_name text,
  store_id uuid,
  store_name text,
  store_branch text,
  area_name text,
  area_city text,
  province text,
  vacancy_status text,
  pipeline_status text,
  vacant_date date,
  target_fill_date date,
  aging_days integer,
  aging_bucket text,
  urgency text,
  penalty_exposure numeric,
  hrco_name text,
  recruiter_name text,
  requester_name text,
  triggered_by_name text,
  pipeline_summary jsonb,
  activity_history jsonb,
  row_capabilities jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_is_active    boolean;
  v_in_scope     boolean := false;
BEGIN
  -- 1. Authentication Check
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Fetch User Profile and Role Context
  SELECT up.id, r.role_name, r.role_level, up.is_active
  INTO v_profile_id, v_role_name, v_role_level, v_is_active
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  -- 3. Fail closed if unauthenticated, inactive, missing profile, or unauthorized role
  IF v_profile_id IS NULL OR NOT coalesce(v_is_active, FALSE) OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- 4. Scope and Vacancy Existence Check
  SELECT EXISTS (
    SELECT 1
    FROM public.vw_vacancy_detail vd
    WHERE vd.id = p_vacancy_id
      AND coalesce(vd.is_archived, false) = false
      AND vd.archived_at IS NULL
      AND vd.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
      AND (
        v_role_level >= 90
        OR (
          vd.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = v_profile_id
              AND us.account_id = vd.account_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            JOIN public.accounts a ON a.id = vd.account_id
            WHERE us.user_id = v_profile_id
              AND us.account_id IS NULL
              AND us.group_id = a.group_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.users_profile up_fallback
            JOIN public.accounts a ON a.id = vd.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (
                SELECT 1
                FROM public.user_scopes us_any
                WHERE us_any.user_id = v_profile_id
                  AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
              )
              AND (
                up_fallback.account_id = vd.account_id
                OR up_fallback.group_id = a.group_id
              )
          )
        )
      )
  ) INTO v_in_scope;

  IF NOT v_in_scope THEN
    RAISE EXCEPTION 'forbidden: vacancy is out of scope or does not exist'
      USING ERRCODE = '42501';
  END IF;

  -- 5. Return the detail record
  RETURN QUERY
  SELECT
    vd.id AS vacancy_id,
    vd.vcode,
    vd.position AS position_title,
    vd.employment_type,
    vd.vacancy_type,
    
    vd.account_id,
    vd.account AS account_name,
    vd.group_id,
    vd.group_name,
    vd.store_id,
    vd.store_name,
    vd.store_branch,
    vd.area_name,
    vd.area_city,
    vd.province,
    
    vd.status AS vacancy_status,
    vd.derived_status AS pipeline_status,
    
    vd.vacant_date,
    vd.target_fill_date,
    vd.aging_days::integer AS aging_days,
    CASE
      WHEN vd.aging_days IS NULL THEN 'unknown'
      WHEN vd.aging_days <= 7 THEN '0_7'
      WHEN vd.aging_days <= 14 THEN '8_14'
      WHEN vd.aging_days <= 30 THEN '15_30'
      ELSE '31_plus'
    END AS aging_bucket,
    
    vd.urgency_level AS urgency,
    CASE
      WHEN coalesce(v_raw.has_penalty, false)
        THEN coalesce(v_raw.penalty_amount, 0::numeric)
      ELSE 0::numeric
    END AS penalty_exposure,
    
    vd.hrco_name,
    up_rec.full_name AS recruiter_name,
    coalesce(up_req.full_name, vd.hc_request_requested_by) AS requester_name,
    vd.triggered_by_full_name AS triggered_by_name,
    
    -- Aggregated applicant/pipeline summary with complete candidate identity and contact info
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'applicant_id', a.id,
            'first_name', a.first_name,
            'last_name', a.last_name,
            'middle_name', a.middle_name,
            'full_name', a.full_name,
            'display_name', COALESCE(NULLIF(TRIM(CONCAT_WS(' ', a.first_name, a.last_name)), ''), a.full_name, 'Anonymous'),
            'contact_number', a.contact_number,
            'status', a.status,
            'status_label', a.status,
            'onboard_date', a.hired_at::date,
            'created_at', a.created_at,
            'updated_at', a.updated_at,
            'recruiter_name', up_a_rec.full_name,
            'deployed_by_name', up_a_dep.full_name,
            'profile_edit_count', COALESCE(a.profile_edit_count, 0)
          )
          ORDER BY a.created_at ASC
        )
        FROM public.applicants a
        LEFT JOIN public.users_profile up_a_rec ON up_a_rec.id = COALESCE(a.created_by, v_raw.assigned_encoder_id)
        LEFT JOIN public.users_profile up_a_dep ON up_a_dep.id = a.deployed_by_user_id
        WHERE a.vacancy_vcode = vd.vcode
          AND coalesce(a.is_archived, false) = false
      ),
      '[]'::jsonb
    ) AS pipeline_summary,
    
    -- Comprehensive, human-readable Vacancy Activity History Timeline (What, Who, When)
    public.get_vacancy_activity_timeline(vd.id) AS activity_history,
    
    -- Row Capabilities strictly reflecting user authority and accurate headcount quota
    jsonb_build_object(
      'can_view_detail', true,
      'can_approve', (v_role_level >= 90),
      'can_update_applicant_status', (v_role_level >= 30),
      'can_request_closure', (
        v_role_level >= 30
        AND vd.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
        AND coalesce(vd.has_pending_closure, false) = false
      ),
      'has_pending_closure', coalesce(vd.has_pending_closure, false),
      'closure_request_status', vd.closure_request_status,
      'hc_filled', coalesce(vl.hc_filled, 0),
      'hc_total', coalesce(vl.hc_total, vd.hc_needed, 1),
      'hc_display', coalesce(vl.hc_display, (coalesce(vl.hc_filled, 0) || '/' || coalesce(vl.hc_total, vd.hc_needed, 1))),
      'active_applicant_count', coalesce(vl.active_applicant_count, 0),
      'confirmed_onboard_count', coalesce(vl.confirmed_onboard_count, 0),
      'hr_processing_count', coalesce(vl.hr_processing_count, 0),
      'is_pool_vacancy', coalesce(vl.is_pool_vacancy, false),
      'authority', 'rls_action_rpcs'
    ) AS row_capabilities

  FROM public.vw_vacancy_detail vd
  JOIN public.vacancies v_raw ON v_raw.id = vd.id
  LEFT JOIN public.vw_vacancy_list vl ON vl.id = vd.id
  LEFT JOIN public.users_profile up_rec ON up_rec.id = v_raw.assigned_encoder_id
  LEFT JOIN public.users_profile up_req ON up_req.id = v_raw.requested_by_user_id
  WHERE vd.id = p_vacancy_id
  LIMIT 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_vacancy_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_web_vacancy_detail(uuid) TO authenticated, service_role, postgres;

COMMIT;
