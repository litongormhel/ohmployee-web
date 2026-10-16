-- Migration: 20262606000042_fix_hr_emploc_detail_scope_and_null_store.sql
-- Ticket: Fix HR Emploc Detail Drawer "Compliance Access Denied" Error in PROD
--
-- Purpose:
--   1. Align RBAC and scope authorization checks in get_web_hr_emploc_detail with list_web_hr_emplocs
--      so that any user authorized to see a record in the list is guaranteed authorization to read its detail drawer.
--   2. Ensure LEFT JOIN is used for all optional relationships (stores, vacancies, groups, positions)
--      so HQ, roving, or null-store records are never dropped.
--   3. Ensure canonical archive guards (is_archived = false / archived_at IS NULL / deleted_at IS NULL)
--      are consistent across caller profile lookup and scoped data queries.
--   4. Update get_correction_timeline scope gate so full-access callers and visible records retain full timeline history.

-- 1. get_correction_timeline update
CREATE OR REPLACE FUNCTION public.get_correction_timeline(p_correction_request_id uuid)
RETURNS TABLE (
  event_id               uuid,
  event_type             text,
  event_label            text,
  status_from            text,
  status_to              text,
  remarks                text,
  actor_id               uuid,
  actor_name             text,
  has_attachment         boolean,
  attachment_filename    text,
  attachment_size_bytes  bigint,
  created_at             timestamp with time zone
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_my_id      uuid := public.get_my_profile_id();
  v_role_level int  := public.get_my_role_level();
  v_account    text;
BEGIN
  -- ── Auth gate ────────────────────────────────────────────
  IF v_my_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  IF v_role_level < 10 THEN
    RAISE EXCEPTION 'insufficient privileges' USING ERRCODE = '42501';
  END IF;

  -- ── Scope gate ───────────────────────────────────────────
  SELECT he.account INTO v_account
  FROM public.hr_emploc he
  WHERE he.id = p_correction_request_id
    AND (public.i_have_full_access() OR he.deleted_at IS NULL);

  -- Record not found or deleted — return empty safely
  IF v_account IS NULL THEN
    RETURN;
  END IF;

  -- Scoped roles must own this account
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_account = ANY(public.get_my_allowed_accounts())) THEN
      RETURN;
    END IF;
  END IF;

  -- ── Timeline ─────────────────────────────────────────────
  RETURN QUERY
  WITH deduped_audit AS (
    SELECT DISTINCT ON (
      al.record_id,
      al.timestamp,
      al.action,
      al.new_data ->> 'hr_status'
    )
      al.id,
      al.actor_id,
      al.action::text             AS action,
      al.old_data ->> 'hr_status' AS st_from,
      al.new_data ->> 'hr_status' AS st_to,
      COALESCE(
        NULLIF(TRIM(al.new_data ->> 'hr_remarks'), ''),
        NULLIF(TRIM(al.new_data ->> 'ops_remarks'), '')
      )                            AS ev_remarks,
      al.timestamp                 AS ev_at
    FROM public.audit_logs al
    WHERE al.module ILIKE 'hr_emploc'
      AND al.record_id = p_correction_request_id
      AND al.action::text IN ('INSERT', 'UPDATE')
    ORDER BY
      al.record_id,
      al.timestamp,
      al.action,
      al.new_data ->> 'hr_status',
      al.id
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
      CASE
        WHEN da.action = 'INSERT'
          THEN 'record_created'
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
  )

  SELECT
    ae.event_id,
    ae.ev_type                                       AS event_type,
    CASE ae.ev_type
      WHEN 'record_created'        THEN 'Record Created'
      WHEN 'flagged_for_correction' THEN 'Flagged for Correction'
      WHEN 'correction_submitted'  THEN 'Correction Submitted'
      WHEN 'approved'              THEN 'Correction Approved'
      WHEN 'rejected'              THEN 'Correction Rejected'
      WHEN 'hrco_updated'          THEN 'HRCO Updated Remarks'
      ELSE                              'Status Updated'
    END                                              AS event_label,
    ae.st_from                                       AS status_from,
    ae.st_to                                         AS status_to,
    ae.ev_remarks                                    AS remarks,
    ae.actor_id,
    ae.actor_name,
    false                                            AS has_attachment,
    NULL::text                                       AS attachment_filename,
    NULL::bigint                                     AS attachment_size_bytes,
    ae.ev_at                                         AS created_at
  FROM audit_events ae

  UNION ALL

  SELECT
    aev.event_id,
    'attachment_uploaded'                            AS event_type,
    'Attachment Uploaded'                            AS event_label,
    NULL::text,
    NULL::text,
    aev.original_filename                            AS remarks,
    aev.actor_id,
    aev.actor_name,
    true                                             AS has_attachment,
    aev.original_filename                            AS attachment_filename,
    aev.size_bytes                                   AS attachment_size_bytes,
    aev.ev_at                                        AS created_at
  FROM attachment_events aev

  ORDER BY created_at ASC NULLS LAST, event_id ASC;
END;
$$;

-- 2. get_web_hr_emploc_detail update
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
  INTO   v_profile_id, v_role_name, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active = TRUE
    AND  up.archived_at IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- Validate record existence and scoped visibility aligned with list_web_hr_emplocs
  IF NOT EXISTS (
    SELECT 1 FROM public.hr_emploc h
    WHERE h.id = p_hr_emploc_id
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.deleted_at IS NULL
          AND (
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
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc detail record is not found or caller has insufficient access'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    h.id AS hr_emploc_id,
    COALESCE(h.applicant_name, h.applicant_name_snapshot, 'Anonymous') AS applicant_name,
    COALESCE(h.vcode, v.vcode, 'Uncoded') AS vcode,
    COALESCE(h.vacancy_id, v.id) AS vacancy_id,
    COALESCE(h.vacancy_code_snapshot, v.vcode) AS vacancy_code_snapshot,
    COALESCE(h.position_id_snapshot, v.position_id) AS position_id_snapshot,
    COALESCE(h.position, p.position_name) AS position_title,
    h.assignment_type::text AS assignment_type,
    h.roving_assignment_id,
    COALESCE(h.covered_stores, '[]'::jsonb) AS covered_stores,
    COALESCE(h.account_id, a.id, v.account_id) AS account_id,
    COALESCE(a.account_name, h.account) AS account_name,
    COALESCE(a.group_id, g.id, v.group_id) AS group_id,
    COALESCE(g.group_name, g2.group_name) AS group_name,
    COALESCE(h.store_id, st.id, v.store_id) AS store_id,
    COALESCE(h.store_name, st.store_name) AS store_name,
    h.hr_status,
    h.status,
    h.emploc_no,
    h.employee_no,
    h.date_requested,
    h.created_at,
    h.hired_date,
    h.deployed_by_user_id,
    h.hrco_user_id_snapshot,
    COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
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

    -- Correction Attachments
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
    ((h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,

    CASE
      WHEN ((h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
        THEN 'breached'
      WHEN ((h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
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
      'hrco_name', COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)),
      'can_request_deletion', (
        h.status <> 'Moved to Plantilla'
        AND h.hr_status <> 'Pending Deletion'
        AND NOT EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
        AND (v_role_level >= 70 OR v_role_name IN ('OM', 'HRCO', 'ATL', 'TL', 'ATL/TL') OR public.i_am_ops() OR public.i_have_full_access())
      ),
      'can_withdraw_deletion_request', (
        EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
        AND (
          public.i_have_full_access()
          OR EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending' AND dr.requested_by_user_id = v_profile_id
          )
        )
      ),
      'can_approve_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      ),
      'can_reject_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      ),
      'can_approve_correction', (
        h.hr_status = 'For Review'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_revert_correction', (
        h.hr_status = 'For Review'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_review_correction', (
        (public.i_am_hr_dept() OR public.i_have_full_access())
        AND h.hr_status = 'For Review'
        AND h.status = 'Pending Emploc'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_submit_correction', (
        h.hr_status = 'For Correction'
        AND (public.i_have_full_access() OR v_role_name = 'HRCO' OR h.hrco_user_id_snapshot = v_profile_id)
      ),
      'can_move_to_plantilla', (
        h.hr_status = 'Complete'
        AND COALESCE(h.employee_no, '') <> ''
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_tag_deficiency', (
        (public.i_am_hr_dept() OR public.i_have_full_access())
        AND h.status <> 'Moved to Plantilla'
        AND h.hr_status <> 'Complete'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_assign_employee_no', (
        (v_role_name = 'Encoder' OR v_role_level = 30 OR v_role_level >= 100)
        AND h.hr_status = 'Complete'
        AND COALESCE(h.employee_no, '') = ''
        AND h.status = 'Pending Emploc'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_review_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      )
    ) AS row_capabilities
  FROM public.hr_emploc h
  LEFT JOIN public.accounts a ON a.id = h.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN public.stores st ON st.id = h.store_id
  LEFT JOIN public.vacancies v ON v.id = h.vacancy_id
  LEFT JOIN public.groups g2 ON g2.id = v.group_id
  LEFT JOIN public.positions p ON p.id = COALESCE(h.position_id_snapshot, v.position_id)
  WHERE h.id = p_hr_emploc_id
    AND (
      COALESCE(v_role_level, 0) >= 90
      OR (
        h.deleted_at IS NULL
        AND (
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
    );
END;
$$;

COMMENT ON FUNCTION public.get_web_hr_emploc_detail(uuid) IS
  'Web presentation detail contract. Aligns scope and RBAC authorization with list_web_hr_emplocs and uses LEFT JOINs for optional relations (stores, vacancies, groups, positions).';

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_detail(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_hr_emploc_detail(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_detail(uuid) TO authenticated;
