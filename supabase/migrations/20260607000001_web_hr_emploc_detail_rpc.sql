-- Migration: 20260607000001_web_hr_emploc_detail_rpc.sql
-- Ticket: OHM2026_1093 - Web HR Emploc detail presentation RPC
--
-- Purpose:
--   Safe, read-only presentation contract for fetching comprehensive detail
--   fields of a single HR Emploc record on the OHMployee Web Dashboard.
--
-- Security invariants:
--   - Caller identity is derived strictly from auth.uid().
--   - Outbound PII (contact numbers, email, addresses, exact birthdate) is excluded.
--   - Sensitive fields (SSS, PhilHealth, Pag-IBIG) are completely omitted.
--   - Unauthenticated, inactive, unauthorized, and out-of-scope callers fail closed.
--   - Row capabilities are UI hints only; action-specific RPCs and triggers remain authority.
--   - Execution is granted only to authenticated users. Public and anon are revoked.

DROP FUNCTION IF EXISTS public.get_web_hr_emploc_detail(uuid);

CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_detail(p_hr_emploc_id uuid)
RETURNS TABLE (
  hr_emploc_id               uuid,
  applicant_name             text,
  vcode                      text,
  vacancy_id                 uuid,
  vacancy_code_snapshot      text,
  position_id_snapshot       uuid,
  position_title             text,
  assignment_type            text,
  roving_assignment_id       uuid,
  covered_stores             jsonb,
  account_id                 uuid,
  account_name               text,
  group_id                   uuid,
  group_name                 text,
  store_id                   uuid,
  store_name                 text,
  hr_status                  text,
  status                     text,
  emploc_no                  text,
  employee_no                text,
  date_requested             timestamp with time zone,
  created_at                 timestamp with time zone,
  hired_date                 date,
  deployed_by_user_id        uuid,
  hrco_user_id_snapshot      uuid,
  hrco_name                  text,
  employee_lookup_found      boolean,
  employee_lookup_synced_at  timestamp with time zone,
  employee_lookup_remarks    text,
  employee_name_snapshot     text,
  birthdate_snapshot         date,
  civil_status_snapshot      text,
  requirement_overall_status text,
  ops_remarks                text,
  hr_remarks                 text,
  hr_rejection_reason        text,
  hr_reviewed_by             text,
  hr_reviewed_at             timestamp with time zone,
  deficiency_summary         jsonb,
  correction_reason          jsonb,
  correction_attachments     jsonb,
  deletion_request           jsonb,
  sla_breached               boolean,
  sla_status                 text,
  sla_deadline               timestamp with time zone,
  aging_days                 integer,
  timeline                   jsonb,
  row_capabilities           jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  -- Direct SQL/anon safety. Fail closed if unauthenticated.
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- Validate record existence and scoped visibility
  IF NOT EXISTS (
    SELECT 1 FROM public.hr_emploc h
    WHERE h.id = p_hr_emploc_id
      AND h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc detail record is not found or caller has insufficient access'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    h.id AS hr_emploc_id,
    h.applicant_name,
    h.vcode,
    h.vacancy_id,
    h.vacancy_code_snapshot,
    h.position_id_snapshot,
    h.position AS position_title,
    h.assignment_type::text AS assignment_type,
    h.roving_assignment_id,
    h.covered_stores,
    h.account_id,
    a.account_name,
    a.group_id,
    g.group_name,
    h.store_id,
    h.store_name,
    h.hr_status,
    h.status,
    h.emploc_no,
    h.employee_no,
    h.date_requested,
    h.created_at,
    h.hired_date,
    h.deployed_by_user_id,
    h.hrco_user_id_snapshot,
    h.hrco_name,
    h.employee_lookup_found,
    h.employee_lookup_synced_at,
    h.employee_lookup_remarks,
    h.employee_name_snapshot,
    h.birthdate_snapshot,
    h.civil_status_snapshot,
    h.requirement_overall_status,
    h.ops_remarks,
    h.hr_remarks,
    h.hr_rejection_reason,
    h.hr_reviewed_by,
    h.hr_reviewed_at,
    
    -- Deficiency Summary
    CASE
      WHEN h.correction_reason IS NULL THEN jsonb_build_object('active_count', 0, 'issues', '[]'::jsonb)
      ELSE jsonb_build_object(
        'active_count', CASE WHEN jsonb_typeof(h.correction_reason) = 'array' THEN jsonb_array_length(h.correction_reason) ELSE 1 END,
        'issues', CASE
          WHEN jsonb_typeof(h.correction_reason) = 'array' THEN (
            SELECT jsonb_agg(
              jsonb_build_object(
                'code', el->>'code',
                'comment', el->>'comment',
                'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = el->>'code'), el->>'code')
              )
            )
            FROM jsonb_array_elements(h.correction_reason) el
          )
          ELSE jsonb_build_array(
            jsonb_build_object(
              'code', h.correction_reason->>'type',
              'comment', h.correction_reason->>'comment',
              'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = h.correction_reason->>'type'), h.correction_reason->>'type')
            )
          )
        END
      )
    END AS deficiency_summary,

    h.correction_reason,

    -- Correction Attachments (exposes private supabse storage paths only if caller is safe)
    (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'id', ca.id,
          'original_filename', ca.original_filename,
          'mime_type', ca.mime_type,
          'size_bytes', ca.size_bytes,
          'uploaded_by', ca.uploaded_by,
          'uploaded_at', ca.uploaded_at,
          'storage_path', CASE
            WHEN (
              v_role_level >= 90
              OR ca.uploaded_by = v_profile_id
              OR h.hrco_user_id_snapshot = v_profile_id
            ) THEN ca.storage_path
            ELSE NULL
          END
        )
      ), '[]'::jsonb)
      FROM public.hr_emploc_correction_attachments ca
      WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false
    ) AS correction_attachments,

    -- Deletion Request Overlay Details
    (
      SELECT jsonb_build_object(
        'id', dr.id,
        'status', dr.status,
        'reason', dr.reason,
        'requested_by', dr.requested_by,
        'requested_by_role', dr.requested_by_role,
        'requested_by_user_id', dr.requested_by_user_id,
        'created_at', dr.created_at,
        'deletion_type', dr.deletion_type,
        'original_emploc_id', dr.original_emploc_id,
        'original_hr_status', dr.original_hr_status,
        'reviewed_by', dr.reviewed_by,
        'reviewed_at', dr.reviewed_at,
        'reviewer_remarks', dr.reviewer_remarks,
        'activities', (
          SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
              'id', act.id,
              'activity_type', act.activity_type,
              'performed_by', act.performed_by,
              'performed_by_user_id', act.performed_by_user_id,
              'performed_at', act.performed_at,
              'remarks', act.remarks
            ) ORDER BY act.performed_at DESC
          ), '[]'::jsonb)
          FROM public.hr_emploc_deletion_activities act
          WHERE act.request_id = dr.id
        )
      )
      FROM public.hr_emploc_deletion_requests dr
      WHERE dr.hr_emploc_id = h.id
      ORDER BY dr.created_at DESC
      LIMIT 1
    ) AS deletion_request,

    -- SLA & Aging Computations
    ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
    
    CASE
      WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
        THEN 'breached'
      WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
        THEN 'warning'
      ELSE 'normal'
    END AS sla_status,
    
    (COALESCE(h.date_requested, h.created_at) + INTERVAL '3 days') AS sla_deadline,
    GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(h.date_requested, h.created_at))))::integer) AS aging_days,

    -- Chronological Correction / Action Timeline History
    (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'event_id', t.event_id,
          'event_type', t.event_type,
          'event_label', t.event_label,
          'status_from', t.status_from,
          'status_to', t.status_to,
          'remarks', t.remarks,
          'actor_id', t.actor_id,
          'actor_name', t.actor_name,
          'has_attachment', t.has_attachment,
          'attachment_filename', t.attachment_filename,
          'attachment_size_bytes', t.attachment_size_bytes,
          'created_at', t.created_at
        ) ORDER BY t.created_at ASC
      ), '[]'::jsonb)
      FROM public.get_correction_timeline(h.id) t
    ) AS timeline,

    -- Row action capability presentation UI hints
    jsonb_build_object(
      'can_view_detail', true,
      'can_request_deletion', (
        h.status <> 'Moved to Plantilla'
        AND h.hr_status <> 'Pending Deletion'
        AND (v_role_level >= 70 OR v_role_name IN ('OM', 'HRCO', 'ATL', 'TL', 'ATL/TL') OR public.i_am_ops() OR public.i_have_full_access())
      ),
      'can_withdraw_deletion_request', (
        h.hr_status = 'Pending Deletion'
        AND (
          public.i_have_full_access()
          OR EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending' AND dr.requested_by_user_id = v_profile_id
          )
        )
      ),
      'can_approve_deletion', (
        h.hr_status = 'Pending Deletion'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_reject_deletion', (
        h.hr_status = 'Pending Deletion'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_approve_correction', (
        h.hr_status = 'For Review'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_revert_correction', (
        h.hr_status = 'For Review'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_submit_correction', (
        h.hr_status = 'For Correction'
        AND (public.i_have_full_access() OR v_role_name = 'HRCO' OR h.hrco_user_id_snapshot = v_profile_id)
      ),
      'can_move_to_plantilla', (
        h.hr_status = 'Complete'
        AND COALESCE(h.employee_no, '') <> ''
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      )
    ) AS row_capabilities
  FROM public.hr_emploc h
  LEFT JOIN public.accounts a ON a.id = h.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE h.id = p_hr_emploc_id
    AND h.deleted_at IS NULL;
END;
$$;

COMMENT ON FUNCTION public.get_web_hr_emploc_detail(uuid) IS
  'OHM2026_1093 - Web presentation detail contract only. Returns safe presentation detail fields for a single public.hr_emploc record by ID. RLS/action RPCs remain authority.';

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_detail(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_hr_emploc_detail(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_detail(uuid) TO authenticated;
