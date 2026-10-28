-- Migration: 20262606000075_friendly_hr_emploc_activity_timeline.sql
-- Purpose:
--   Make the HR Emploc Activity History Trail human readable (who / what / when).
--   * Every audit event now returns a full sentence in `remarks`, actor name first.
--   * Duplicate / no-op audit rows (lowercase+uppercase module pairs, unchanged updates)
--     no longer appear as generic "Status Updated / Action recorded by ..." entries.
--   * Employee ID edits and Revert to Pending (log_audit_event rows with log_message) get
--     their own labelled events.
--   * Deletion requests (requested / withdrawn / approved / rejected) are read from
--     public.hr_emploc_deletion_requests and shown in the trail.
--   Function signature (RETURNS TABLE) is unchanged, so get_web_hr_emploc_detail keeps working.

CREATE OR REPLACE FUNCTION public.get_correction_timeline(p_correction_request_id uuid)
RETURNS TABLE(
  event_id uuid,
  event_type text,
  event_label text,
  status_from text,
  status_to text,
  remarks text,
  actor_id uuid,
  actor_name text,
  has_attachment boolean,
  attachment_filename text,
  attachment_size_bytes bigint,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_my_id      uuid := public.get_my_profile_id();
  v_role_level int  := public.get_my_role_level();
  v_account    text;
  v_applicant  text;
BEGIN
  -- Auth gate
  IF v_my_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  IF v_role_level < 10 THEN
    RAISE EXCEPTION 'insufficient privileges' USING ERRCODE = '42501';
  END IF;

  -- Scope gate
  SELECT he.account, initcap(he.applicant_name)
  INTO v_account, v_applicant
  FROM public.hr_emploc he
  WHERE he.id = p_correction_request_id
    AND he.deleted_at IS NULL;

  -- Record not found or deleted: return empty safely
  IF v_account IS NULL THEN
    RETURN;
  END IF;

  -- Scoped roles must own this account
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_account = ANY(public.get_my_allowed_accounts())) THEN
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  WITH raw_audit AS (
    -- audit_logs writes both 'hr_emploc' and 'HR_EMPLOC' rows per event; de-duplicate
    SELECT DISTINCT ON (
      al.record_id,
      al.timestamp,
      al.action,
      al.new_data ->> 'hr_status',
      al.new_data ->> 'log_message'
    )
      al.id,
      al.actor_id,
      al.action::text                      AS action,
      al.timestamp                         AS ev_at,
      al.old_data ->> 'hr_status'          AS st_from,
      al.new_data ->> 'hr_status'          AS st_to,
      al.old_data ->> 'status'             AS dep_from,
      al.new_data ->> 'status'             AS dep_to,
      al.old_data ->> 'employee_no'        AS emp_from,
      al.new_data ->> 'employee_no'        AS emp_to,
      al.new_data ->> 'log_message'        AS log_message,
      al.new_data ->> 'reason'             AS log_reason,
      COALESCE(
        NULLIF(TRIM(al.new_data ->> 'hr_remarks'), ''),
        NULLIF(TRIM(al.new_data ->> 'ops_remarks'), '')
      )                                    AS ev_remarks,
      (
        COALESCE(al.new_data ->> 'hr_remarks', '')  IS DISTINCT FROM COALESCE(al.old_data ->> 'hr_remarks', '')
        OR COALESCE(al.new_data ->> 'ops_remarks', '') IS DISTINCT FROM COALESCE(al.old_data ->> 'ops_remarks', '')
      )                                    AS remarks_changed
    FROM public.audit_logs al
    WHERE al.module ILIKE 'hr_emploc'
      AND al.record_id = p_correction_request_id
      AND al.action::text IN ('INSERT', 'UPDATE')
    ORDER BY
      al.record_id,
      al.timestamp,
      al.action,
      al.new_data ->> 'hr_status',
      al.new_data ->> 'log_message',
      al.id
  ),
  logged_ts AS (
    SELECT DISTINCT ra.ev_at FROM raw_audit ra WHERE ra.log_message IS NOT NULL
  ),
  deduped_audit AS (
    SELECT ra.*
    FROM raw_audit ra
    WHERE ra.action = 'INSERT'
       OR ra.log_message IS NOT NULL
       OR (
         NOT EXISTS (SELECT 1 FROM logged_ts lt WHERE lt.ev_at = ra.ev_at)
         AND (
           ra.st_to  IS DISTINCT FROM ra.st_from
           OR ra.dep_to IS DISTINCT FROM ra.dep_from
           OR ra.emp_to IS DISTINCT FROM ra.emp_from
           OR ra.remarks_changed
         )
       )
  ),
  audit_events AS (
    SELECT
      da.id                                          AS event_id,
      da.actor_id,
      COALESCE(up.full_name, da.actor_id::text)      AS actor_name,
      da.st_from,
      da.st_to,
      da.ev_remarks,
      da.ev_at,
      da.action,
      da.log_message,
      da.log_reason,
      da.dep_from,
      da.dep_to,
      da.emp_from,
      da.emp_to,
      CASE
        WHEN da.action = 'INSERT'
          THEN 'record_created'
        WHEN da.log_message ILIKE 'Updated Employee ID%'
          THEN 'employee_id_updated'
        WHEN da.log_message ILIKE 'Reverted from Deployed%'
          THEN 'reverted_to_pending'
        WHEN da.log_message IS NOT NULL
          THEN 'activity'
        WHEN da.emp_to IS NOT NULL AND da.emp_from IS NULL
          AND da.dep_to IS DISTINCT FROM 'Moved to Plantilla'
          THEN 'employee_id_assigned'
        WHEN da.dep_to = 'Moved to Plantilla' AND da.dep_from IS DISTINCT FROM 'Moved to Plantilla'
          THEN 'deployed'
        WHEN da.st_to = 'For Correction'
          AND da.st_from IS DISTINCT FROM 'For Correction'
          AND da.st_from IS DISTINCT FROM 'For Review'
          THEN 'flagged_for_correction'
        WHEN da.st_to = 'For Correction'
          AND da.st_from = 'For Review'
          THEN 'rejected'
        WHEN da.st_to = 'For Review'
          AND da.st_from = 'For Correction'
          THEN 'correction_submitted'
        WHEN da.st_to = 'Complete'
          AND da.st_from IN ('For Review', 'For Correction')
          THEN 'approved'
        WHEN da.st_to = 'For Correction'
          AND da.st_from = 'For Correction'
          THEN 'hrco_updated'
        ELSE 'status_updated'
      END                                            AS ev_type
    FROM deduped_audit da
    LEFT JOIN public.users_profile up ON (up.auth_user_id = da.actor_id OR up.id = da.actor_id)
  ),
  attachment_events AS (
    SELECT
      ca.id                                          AS event_id,
      ca.uploaded_by                                 AS actor_id,
      COALESCE(up.full_name, ca.uploaded_by::text)   AS actor_name,
      ca.original_filename,
      ca.size_bytes,
      ca.uploaded_at                                 AS ev_at
    FROM public.hr_emploc_correction_attachments ca
    LEFT JOIN public.users_profile up ON (up.auth_user_id = ca.uploaded_by OR up.id = ca.uploaded_by)
    WHERE ca.hr_emploc_id = p_correction_request_id
      AND ca.is_deleted = false
  ),
  deletion_events AS (
    -- Request submitted
    SELECT
      dr.id                                          AS event_id,
      'deletion_requested'::text                     AS event_type,
      'Deletion Request'::text                       AS event_label,
      format('%s requested deletion of %s due to %s.',
             COALESCE(dr.requested_by, 'Unknown user'), v_applicant, COALESCE(dr.reason, 'no reason given')) AS remarks,
      dr.requested_by_user_id                        AS actor_id,
      COALESCE(dr.requested_by, 'Unknown user')      AS actor_name,
      dr.created_at                                  AS ev_at
    FROM public.hr_emploc_deletion_requests dr
    WHERE dr.hr_emploc_id = p_correction_request_id

    UNION ALL

    -- Request withdrawn
    SELECT
      md5(dr.id::text || ':withdrawn')::uuid,
      'deletion_withdrawn',
      'Deletion Request Withdrawn',
      format('%s withdrew the deletion request for %s.',
             COALESCE(dr.withdrawn_by, 'Unknown user'), v_applicant),
      dr.withdrawn_by_user_id,
      COALESCE(dr.withdrawn_by, 'Unknown user'),
      dr.withdrawn_at
    FROM public.hr_emploc_deletion_requests dr
    WHERE dr.hr_emploc_id = p_correction_request_id
      AND dr.withdrawn_at IS NOT NULL

    UNION ALL

    -- Request approved / rejected
    SELECT
      md5(dr.id::text || ':reviewed')::uuid,
      CASE WHEN dr.status = 'Approved' THEN 'deletion_approved' ELSE 'deletion_rejected' END,
      CASE WHEN dr.status = 'Approved' THEN 'Deletion Request Approved' ELSE 'Deletion Request Rejected' END,
      format('%s %s the deletion request for %s%s',
             COALESCE(dr.reviewed_by, 'Unknown user'),
             CASE WHEN dr.status = 'Approved' THEN 'approved' ELSE 'rejected' END,
             v_applicant,
             CASE WHEN NULLIF(BTRIM(COALESCE(dr.reviewer_remarks, '')), '') IS NOT NULL
                  THEN ' (' || BTRIM(dr.reviewer_remarks) || ').' ELSE '.' END),
      dr.approved_by_user_id,
      COALESCE(dr.reviewed_by, 'Unknown user'),
      dr.reviewed_at
    FROM public.hr_emploc_deletion_requests dr
    WHERE dr.hr_emploc_id = p_correction_request_id
      AND dr.status IN ('Approved', 'Rejected')
      AND dr.reviewed_at IS NOT NULL
  )

  -- Audit events (human-readable sentence in remarks)
  SELECT
    ae.event_id,
    ae.ev_type                                       AS event_type,
    CASE ae.ev_type
      WHEN 'record_created'        THEN 'Record Created'
      WHEN 'employee_id_updated'   THEN 'Employee ID Updated'
      WHEN 'reverted_to_pending'   THEN 'Reverted to Pending'
      WHEN 'employee_id_assigned'  THEN 'Employee ID Assigned'
      WHEN 'deployed'              THEN 'Deployed to Plantilla'
      WHEN 'flagged_for_correction' THEN 'Flagged for Correction'
      WHEN 'correction_submitted'  THEN 'Correction Submitted'
      WHEN 'approved'              THEN 'Correction Approved'
      WHEN 'rejected'              THEN 'Correction Rejected'
      WHEN 'hrco_updated'          THEN 'HRCO Updated Remarks'
      WHEN 'activity'              THEN 'Activity'
      ELSE                              'Status Updated'
    END                                              AS event_label,
    ae.st_from                                       AS status_from,
    ae.st_to                                         AS status_to,
    CASE ae.ev_type
      WHEN 'record_created' THEN ae.ev_remarks
      WHEN 'employee_id_updated' THEN
        format('%s updated the Employee ID of %s from %s to %s%s',
               ae.actor_name, v_applicant,
               COALESCE(ae.emp_from, '--'), COALESCE(ae.emp_to, '--'),
               CASE WHEN NULLIF(BTRIM(COALESCE(ae.log_reason, '')), '') IS NOT NULL
                    THEN ' (Reason: ' || BTRIM(ae.log_reason) || ').' ELSE '.' END)
      WHEN 'reverted_to_pending' THEN
        format('%s reverted %s from Deployed to Pending and removed the record from Plantilla%s',
               ae.actor_name, v_applicant,
               CASE WHEN NULLIF(BTRIM(COALESCE(ae.log_reason, '')), '') IS NOT NULL
                    THEN ' (Reason: ' || BTRIM(ae.log_reason) || ').' ELSE '.' END)
      WHEN 'activity' THEN
        ae.actor_name || ': ' || ae.log_message
      WHEN 'employee_id_assigned' THEN
        format('%s assigned Employee ID %s to %s.', ae.actor_name, ae.emp_to, v_applicant)
      WHEN 'deployed' THEN
        format('%s deployed %s to Plantilla%s.', ae.actor_name, v_applicant,
               CASE WHEN ae.emp_to IS NOT NULL THEN ' (Employee ID ' || ae.emp_to || ')' ELSE '' END)
      WHEN 'flagged_for_correction' THEN
        format('%s flagged %s for correction%s', ae.actor_name, v_applicant,
               CASE WHEN ae.ev_remarks IS NOT NULL THEN ': ' || ae.ev_remarks || '.' ELSE '.' END)
      WHEN 'rejected' THEN
        format('%s sent %s back for correction%s', ae.actor_name, v_applicant,
               CASE WHEN ae.ev_remarks IS NOT NULL THEN ': ' || ae.ev_remarks || '.' ELSE '.' END)
      WHEN 'correction_submitted' THEN
        format('%s submitted the correction of %s for review%s', ae.actor_name, v_applicant,
               CASE WHEN ae.ev_remarks IS NOT NULL THEN ': ' || ae.ev_remarks || '.' ELSE '.' END)
      WHEN 'approved' THEN
        format('%s approved the correction of %s.', ae.actor_name, v_applicant)
      WHEN 'hrco_updated' THEN
        format('%s updated the correction remarks of %s%s', ae.actor_name, v_applicant,
               CASE WHEN ae.ev_remarks IS NOT NULL THEN ': ' || ae.ev_remarks || '.' ELSE '.' END)
      ELSE
        format('%s changed the status of %s from %s to %s.', ae.actor_name, v_applicant,
               COALESCE(ae.dep_from, ae.st_from, '--'), COALESCE(ae.dep_to, ae.st_to, '--'))
    END                                              AS remarks,
    ae.actor_id,
    ae.actor_name,
    false                                            AS has_attachment,
    NULL::text                                       AS attachment_filename,
    NULL::bigint                                     AS attachment_size_bytes,
    ae.ev_at                                         AS created_at
  FROM audit_events ae

  UNION ALL

  -- Attachment events
  SELECT
    aev.event_id,
    'attachment_uploaded'                            AS event_type,
    'Attachment Uploaded'                            AS event_label,
    NULL::text,
    NULL::text,
    format('%s uploaded %s for %s.', aev.actor_name, aev.original_filename, v_applicant) AS remarks,
    aev.actor_id,
    aev.actor_name,
    true                                             AS has_attachment,
    aev.original_filename                            AS attachment_filename,
    aev.size_bytes                                   AS attachment_size_bytes,
    aev.ev_at                                        AS created_at
  FROM attachment_events aev

  UNION ALL

  -- Deletion request lifecycle events
  SELECT
    de.event_id,
    de.event_type,
    de.event_label,
    NULL::text,
    NULL::text,
    de.remarks,
    de.actor_id,
    de.actor_name,
    false,
    NULL::text,
    NULL::bigint,
    de.ev_at
  FROM deletion_events de

  ORDER BY created_at ASC NULLS LAST, event_id ASC;
END;
$function$;
