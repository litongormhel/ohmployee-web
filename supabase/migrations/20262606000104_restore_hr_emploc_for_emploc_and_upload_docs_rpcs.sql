-- ============================================================================
-- Migration: 20262606000104_restore_hr_emploc_for_emploc_and_upload_docs_rpcs.sql
-- Purpose: Restore HR Emploc 5-queue architecture (Pending -> For Emploc ->
--          Correction -> Review -> Deployed) and expose scoped upload/view
--          capabilities in list_web_hr_emplocs, get_web_hr_emploc_summary,
--          and get_web_hr_emploc_detail.
-- Context:
--   When Stage 2b-Web was closed (ohm#q3v8n2kd), migration 84 on disk was
--   updated but version 20262606000084 was already recorded in schema_migrations,
--   leaving Staging running the older migration 83 versions of these 3 query RPCs.
--   This migration authoritatively reapplies the Stage 2b RPC definitions so that:
--     1. Ops in scope & Super Admin receive 'can_upload_docs': true and
--        'can_submit_requirements': true on Pending records, surfacing the
--        "Upload Docs" action button.
--     2. p_queue = 'for_emploc' and 'deployed' are properly filtered.
--     3. get_web_hr_emploc_summary exposes for_emploc_count for tab badge parity.
--     4. get_web_hr_emploc_detail exposes scoped attachments, stage, and capabilities.
-- ============================================================================

-- ── 1. Update public.list_web_hr_emplocs ─────────────────────────────────────
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text);
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs;

CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue        text    DEFAULT NULL::text,
  p_status       text    DEFAULT NULL::text,
  p_deficiency   text    DEFAULT NULL::text,
  p_sla_filter   text    DEFAULT NULL::text,
  p_account_id   uuid    DEFAULT NULL::uuid,
  p_group_id     uuid    DEFAULT NULL::uuid,
  p_search       text    DEFAULT NULL::text,
  p_limit        integer DEFAULT 50,
  p_offset       integer DEFAULT 0,
  p_sort_by      text    DEFAULT 'date_requested'::text,
  p_sort_dir     text    DEFAULT 'desc'::text
)
RETURNS TABLE(
  hr_emploc_id         uuid,
  applicant_name       text,
  vcode                text,
  account_id           uuid,
  account_name         text,
  group_id             uuid,
  group_name           text,
  store_id             uuid,
  store_name           text,
  position_title       text,
  hr_status            text,
  status               text,
  emploc_no            text,
  employee_no          text,
  date_requested       timestamp with time zone,
  created_at           timestamp with time zone,
  hired_date           date,
  assignment_type      text,
  roving_assignment_id uuid,
  aging_days           integer,
  sla_breached         boolean,
  sla_status           text,
  sla_deadline         timestamp with time zone,
  deficiency_summary   jsonb,
  is_pending_deletion  boolean,
  row_capabilities     jsonb,
  total_count          bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'date_requested'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(public.get_my_role(), r.role_name), COALESCE(public.get_my_role_level(), r.role_level)
  INTO   v_profile_id, v_role_name, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active = TRUE
    AND  up.archived_at IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'vcode',
    'applicant_name',
    'account_name',
    'group_name',
    'store_name',
    'position_title',
    'hr_status',
    'status',
    'emploc_no',
    'employee_no',
    'date_requested',
    'created_at',
    'aging_days'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by
      USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.id AS hr_emploc_id,
      h.applicant_name,
      h.vcode,
      h.account_id,
      a.account_name,
      a.group_id,
      g.group_name,
      h.store_id,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.hr_status,
      h.status,
      h.emploc_no,
      h.employee_no,
      h.date_requested,
      h.created_at,
      h.hired_date,
      h.assignment_type::text AS assignment_type,
      h.roving_assignment_id,
      h.deleted_at,
      h.moved_to_plantilla_at,
      
      GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(h.date_requested, h.created_at))))::integer) AS aging_days,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status,
      
      (COALESCE(h.date_requested, h.created_at) + INTERVAL '3 days') AS sla_deadline,
      
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
      
      EXISTS (
        SELECT 1 FROM public.hr_emploc_deletion_requests dr
        WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
      ) AS is_pending_deletion,
      
      jsonb_build_object(
        'can_view_detail', true,
        'hrco_name', COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)),
        'remarks', COALESCE(h.ops_remarks, h.hr_remarks),
        'ops_remarks', h.ops_remarks,
        'hr_remarks', h.hr_remarks,
        'attachment_url', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
          ELSE (
            SELECT ca.storage_path
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
            ORDER BY ca.uploaded_at DESC
            LIMIT 1
          )
        END,
        'attachment_file_name', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
          ELSE (
            SELECT ca.original_filename
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
            ORDER BY ca.uploaded_at DESC
            LIMIT 1
          )
        END,
        'doc_count', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') THEN 0
          ELSE (
            SELECT count(*)::int
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          )
        END,
        'attachments', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') OR NOT public.can_view_hr_emploc_docs(h.id) THEN '[]'::jsonb
          ELSE COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', ca.id,
                'original_filename', ca.original_filename,
                'mime_type', ca.mime_type,
                'size_bytes', ca.size_bytes,
                'stage', ca.stage,
                'storage_path', ca.storage_path,
                'object_path', regexp_replace(ca.storage_path, '^hr-corrections/', ''),
                'uploaded_by', ca.uploaded_by,
                'uploaded_at', ca.uploaded_at,
                'created_at', ca.created_at,
                'can_remove', (
                  public.can_upload_hr_emploc_docs(h.id)
                  AND (public.is_super_admin() OR ca.uploaded_by = v_profile_id)
                )
              ) ORDER BY ca.uploaded_at DESC
            )
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          ), '[]'::jsonb)
        END,
        'can_upload_docs', public.can_upload_hr_emploc_docs(h.id),
        'can_submit_requirements', (
          public.can_upload_hr_emploc_docs(h.id)
          AND h.hr_status = 'Pending'
        ),
        'can_view_docs', public.can_view_hr_emploc_docs(h.id),
        'can_edit_emploc', (
          public.can_edit_deployed_hr_emploc()
          AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
        ),
        'can_revert_to_pending', (
          public.can_edit_deployed_hr_emploc()
          AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
        ),
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
        'can_review_deletion', (
          (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
          AND EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_approve_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_revert_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_review_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        ),
        'can_submit_correction', (
          public.can_upload_hr_emploc_docs(h.id)
          AND h.hr_status = 'For Correction'
        ),
        'can_move_to_plantilla', false,
        'can_tag_deficiency', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Emploc'
          AND h.status <> 'Moved to Plantilla'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        ),
        'can_assign_employee_no', (
          public.can_assign_pending_hr_emploc()
          AND COALESCE(h.employee_no, '') = ''
          AND h.status <> 'Moved to Plantilla'
          AND (
            h.hr_status = 'For Emploc'
            OR (h.hr_status = 'Pending' AND public.is_super_admin())
          )
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        )
      ) AS row_capabilities
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
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
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Queue Filter (including 'for_emploc', 'deployed', etc.)
      (p_queue IS NULL
       OR (p_queue = 'pending' AND s.hr_status = 'Pending' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'for_emploc' AND s.hr_status = 'For Emploc' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'correction' AND s.hr_status = 'For Correction' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'review' AND s.hr_status = 'For Review' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue IN ('deployed', 'transferred') AND (
            s.status = 'Moved to Plantilla'
            OR s.hr_status = 'Transferred'
          )
          AND s.status <> 'Backout'
          AND s.deleted_at IS NULL
       )
       OR (p_queue = 'rejected' AND s.hr_status = 'Rejected' AND s.deleted_at IS NULL)
      )
      AND (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.deficiency_summary->'active_count' > '0'::jsonb)
       OR (p_deficiency = 'none' AND s.deficiency_summary->'active_count' = '0'::jsonb)
       OR (
         s.deficiency_summary->'active_count' > '0'::jsonb AND EXISTS (
           SELECT 1 FROM jsonb_array_elements(s.deficiency_summary->'issues') el
           WHERE el->>'code' = p_deficiency
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_status IS NULL OR s.status = p_status)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.applicant_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.emploc_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.hrco_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.hr_emploc_id,
    c.applicant_name,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.hr_status,
    c.status,
    c.emploc_no,
    c.employee_no,
    c.date_requested,
    c.created_at,
    c.hired_date,
    c.assignment_type,
    c.roving_assignment_id,
    c.aging_days,
    c.sla_breached,
    c.sla_status,
    c.sla_deadline,
    c.deficiency_summary,
    c.is_pending_deletion,
    c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'applicant_name'   THEN c.applicant_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'applicant_name'   THEN c.applicant_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title'   THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title'   THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'hr_status'        THEN c.hr_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'hr_status'        THEN c.hr_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'status'           THEN c.status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'status'           THEN c.status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'emploc_no'        THEN c.emploc_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'emploc_no'        THEN c.emploc_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_no'      THEN c.employee_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_no'      THEN c.employee_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'date_requested'   THEN c.date_requested END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'date_requested'   THEN c.date_requested END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'created_at'       THEN c.created_at END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'created_at'       THEN c.created_at END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    c.created_at DESC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) TO authenticated, service_role;


-- ── 2. Update public.get_web_hr_emploc_summary ──────────────────────────────
DROP FUNCTION IF EXISTS public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text);
DROP FUNCTION IF EXISTS public.get_web_hr_emploc_summary;

CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_summary(
  p_queue        text DEFAULT NULL::text,
  p_status       text DEFAULT NULL::text,
  p_deficiency   text DEFAULT NULL::text,
  p_sla_filter   text DEFAULT NULL::text,
  p_account_id   uuid DEFAULT NULL::uuid,
  p_group_id     uuid DEFAULT NULL::uuid,
  p_search       text DEFAULT NULL::text
)
RETURNS TABLE(
  pending_count          bigint,
  for_emploc_count       bigint,
  correction_count       bigint,
  review_count           bigint,
  ready_count            bigint,
  sla_breached_count     bigint,
  sla_warning_count      bigint,
  with_deficiency_count  bigint,
  pending_deletion_count bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc summary requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(public.get_my_role(), r.role_name), COALESCE(public.get_my_role_level(), r.role_level)
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.hr_status,
      h.status,
      h.account_id,
      a.account_name,
      a.group_id,
      h.applicant_name,
      h.vcode,
      h.employee_no,
      h.emploc_no,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.correction_reason,
      h.deleted_at,
      h.moved_to_plantilla_at,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval)) AS sla_warning,
      
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
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
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.correction_reason IS NOT NULL)
       OR (p_deficiency = 'none' AND s.correction_reason IS NULL)
       OR (
         s.correction_reason IS NOT NULL AND (
           (jsonb_typeof(s.correction_reason) = 'array' AND EXISTS (
             SELECT 1 FROM jsonb_array_elements(s.correction_reason) el
             WHERE el->>'code' = p_deficiency
           ))
           OR
           (jsonb_typeof(s.correction_reason) = 'object' AND s.correction_reason->>'type' = p_deficiency)
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_status IS NULL OR s.status = p_status)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.applicant_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.emploc_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.hrco_name ILIKE '%' || btrim(p_search) || '%'
        OR s.hr_status ILIKE '%' || btrim(p_search) || '%'
        OR s.status ILIKE '%' || btrim(p_search) || '%'
      )
  )
  SELECT
    count(*) FILTER (WHERE f.hr_status = 'Pending' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_count,
    count(*) FILTER (WHERE f.hr_status = 'For Emploc' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS for_emploc_count,
    count(*) FILTER (WHERE f.hr_status = 'For Correction' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS correction_count,
    count(*) FILTER (WHERE f.hr_status = 'For Review' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS review_count,
    count(*) FILTER (WHERE (
      f.status = 'Moved to Plantilla'
      OR f.hr_status = 'Transferred'
    ) AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS ready_count,
    count(*) FILTER (WHERE f.sla_breached = true)::bigint AS sla_breached_count,
    count(*) FILTER (WHERE f.sla_warning = true)::bigint AS sla_warning_count,
    count(*) FILTER (WHERE f.correction_reason IS NOT NULL)::bigint AS with_deficiency_count,
    count(*) FILTER (WHERE f.hr_status = 'Pending Deletion' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_deletion_count
  FROM filtered f;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) TO authenticated, service_role;


-- ── 3. Update public.get_web_hr_emploc_detail ───────────────────────────────
DROP FUNCTION IF EXISTS public.get_web_hr_emploc_detail(uuid);
DROP FUNCTION IF EXISTS public.get_web_hr_emploc_detail;

CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_detail(p_hr_emploc_id uuid)
RETURNS TABLE(
  hr_emploc_id              uuid,
  applicant_name            text,
  vcode                     text,
  vacancy_id                uuid,
  vacancy_code_snapshot     text,
  position_id_snapshot      uuid,
  position_title            text,
  assignment_type           text,
  roving_assignment_id      uuid,
  covered_stores            jsonb,
  account_id                uuid,
  account_name              text,
  group_id                  uuid,
  group_name                text,
  store_id                  uuid,
  store_name                text,
  hr_status                 text,
  status                    text,
  emploc_no                 text,
  employee_no               text,
  date_requested            timestamp with time zone,
  created_at                timestamp with time zone,
  hired_date                date,
  deployed_by_user_id       uuid,
  hrco_user_id_snapshot     uuid,
  hrco_name                 text,
  employee_lookup_found     boolean,
  employee_lookup_synced_at timestamp with time zone,
  employee_lookup_remarks   text,
  employee_name_snapshot    text,
  birthdate_snapshot        date,
  civil_status_snapshot     text,
  requirement_overall_status text,
  ops_remarks               text,
  hr_remarks                text,
  hr_rejection_reason       text,
  hr_reviewed_by            text,
  hr_reviewed_at            timestamp with time zone,
  deficiency_summary        jsonb,
  correction_reason         jsonb,
  correction_attachments    jsonb,
  deletion_request          jsonb,
  sla_breached              boolean,
  sla_status                text,
  sla_deadline              timestamp with time zone,
  aging_days                integer,
  timeline                  jsonb,
  row_capabilities          jsonb
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(public.get_my_role(), r.role_name), COALESCE(public.get_my_role_level(), r.role_level)
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

    -- Correction / Requirement Attachments
    CASE
      WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') OR NOT public.can_view_hr_emploc_docs(h.id) THEN '[]'::jsonb
      ELSE (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'id', ca.id,
            'original_filename', ca.original_filename,
            'mime_type', ca.mime_type,
            'size_bytes', ca.size_bytes,
            'stage', ca.stage,
            'uploaded_by', ca.uploaded_by,
            'uploaded_at', ca.uploaded_at,
            'created_at', ca.created_at,
            'storage_path', ca.storage_path,
            'object_path', regexp_replace(ca.storage_path, '^hr-corrections/', ''),
            'can_remove', (
              public.can_upload_hr_emploc_docs(h.id)
              AND (public.is_super_admin() OR ca.uploaded_by = v_profile_id)
            )
          ) ORDER BY ca.uploaded_at DESC
        ), '[]'::jsonb)
        FROM public.hr_emploc_correction_attachments ca
        WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
      )
    END AS correction_attachments,

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
      'can_edit_emploc', (
        public.can_edit_deployed_hr_emploc()
        AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
      ),
      'can_revert_to_pending', (
        public.can_edit_deployed_hr_emploc()
        AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
      ),
      'can_approve_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_revert_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_review_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_upload_docs', public.can_upload_hr_emploc_docs(h.id),
      'can_submit_requirements', (
        public.can_upload_hr_emploc_docs(h.id)
        AND h.hr_status = 'Pending'
      ),
      'can_view_docs', public.can_view_hr_emploc_docs(h.id),
      'can_submit_correction', (
        public.can_upload_hr_emploc_docs(h.id)
        AND h.hr_status = 'For Correction'
      ),
      'can_move_to_plantilla', false,
      'can_tag_deficiency', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Emploc'
        AND h.status <> 'Moved to Plantilla'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_assign_employee_no', (
        public.can_assign_pending_hr_emploc()
        AND COALESCE(h.employee_no, '') = ''
        AND h.status <> 'Moved to Plantilla'
        AND (
          h.hr_status = 'For Emploc'
          OR (h.hr_status = 'Pending' AND public.is_super_admin())
        )
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
  WHERE h.id = p_hr_emploc_id
    AND h.deleted_at IS NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_detail(uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_detail(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
