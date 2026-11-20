-- Migration: 20262606000130_fix_web_hr_emploc_deployed_filter_and_vacancy_rule4.sql
-- 1. Updates list_web_hr_emplocs with p_deployed_window_days for server-side deployed pagination parity.
-- 2. Updates get_web_hr_emploc_summary to exclude deployed/transferred/backout records from active deficiency counts.
-- 3. Restores ADR-001 Rule 4 pipeline capacity (- active_applicant_count) in list_web_vacancies and get_web_vacancy_summary.

-- ============================================================================
-- 1. Update public.list_web_hr_emplocs
-- ============================================================================
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text);
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text, integer);
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs;

CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue                text    DEFAULT NULL::text,
  p_status               text    DEFAULT NULL::text,
  p_deficiency           text    DEFAULT NULL::text,
  p_sla_filter           text    DEFAULT NULL::text,
  p_account_id           uuid    DEFAULT NULL::uuid,
  p_group_id             uuid    DEFAULT NULL::uuid,
  p_search               text    DEFAULT NULL::text,
  p_limit                integer DEFAULT 50,
  p_offset               integer DEFAULT 0,
  p_sort_by              text    DEFAULT 'date_requested'::text,
  p_sort_dir             text    DEFAULT 'desc'::text,
  p_deployed_window_days integer DEFAULT NULL::integer
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
      h.correction_reason,
      h.deleted_at,
      
      -- SLA & Aging computation
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
      
      -- Deletion Overlay visibility
      EXISTS (
        SELECT 1 FROM public.hr_emploc_deletion_requests dr
        WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
      ) AS is_pending_deletion,
      
      -- UI capabilities presentation hints
      jsonb_build_object(
        'can_view_detail', true,
        'hrco_name', COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)),
        'remarks', COALESCE(h.ops_remarks, h.hr_remarks),
        'ops_remarks', h.ops_remarks,
        'hr_remarks', h.hr_remarks,
        'attachment_url', CASE
          WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
          ELSE (
            SELECT ca.storage_path
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
            ORDER BY ca.uploaded_at DESC
            LIMIT 1
          )
        END,
        'attachment_file_name', CASE
          WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
          ELSE (
            SELECT ca.original_filename
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
            ORDER BY ca.uploaded_at DESC
            LIMIT 1
          )
        END,
        'doc_count', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin() THEN 0
          ELSE (
            SELECT count(*)::int
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          )
        END,
        'attachments', CASE
          WHEN ((h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') AND NOT public.is_super_admin()) OR NOT public.can_view_hr_emploc_docs(h.id) THEN '[]'::jsonb
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
          AND (
            p_deployed_window_days IS NULL
            OR COALESCE(s.hired_date::timestamp with time zone, s.date_requested, s.created_at) >= (now() - (p_deployed_window_days || ' days')::interval)
          )
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

REVOKE ALL ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text, integer) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text, integer) TO authenticated, service_role;


-- ============================================================================
-- 2. Update public.get_web_hr_emploc_summary
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_summary(
  p_status     text DEFAULT NULL::text,
  p_deficiency text DEFAULT NULL::text,
  p_sla_filter text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id   uuid DEFAULT NULL::uuid,
  p_search     text DEFAULT NULL::text,
  p_queue      text DEFAULT NULL::text
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
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_name  text;
  v_role_level integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc summary requires a valid session'
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
    RAISE EXCEPTION 'forbidden: web hr_emploc summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.id,
      h.hr_status,
      h.status,
      h.correction_reason,
      h.deleted_at,
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval)) AND (COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))) AS sla_warning,
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status,
      h.applicant_name,
      h.employee_no,
      h.emploc_no,
      h.vcode,
      a.account_name,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.account_id,
      a.group_id
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
    count(*) FILTER (
      WHERE f.correction_reason IS NOT NULL
        AND f.status <> 'Moved to Plantilla'
        AND f.hr_status <> 'Transferred'
        AND f.status <> 'Backout'
        AND f.deleted_at IS NULL
    )::bigint AS with_deficiency_count,
    count(*) FILTER (WHERE f.hr_status = 'Pending Deletion' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_deletion_count
  FROM filtered f;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text) TO authenticated, service_role;


-- ============================================================================
-- 3. Update public.list_web_vacancies (ADR-001 Rule 4 Restoration)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.list_web_vacancies(
  p_status text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id uuid DEFAULT NULL::uuid,
  p_position text DEFAULT NULL::text,
  p_urgency text DEFAULT NULL::text,
  p_aging_bucket text DEFAULT NULL::text,
  p_search text DEFAULT NULL::text,
  p_vacant_from date DEFAULT NULL::date,
  p_vacant_to date DEFAULT NULL::date,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_sort_by text DEFAULT 'vacant_date'::text,
  p_sort_dir text DEFAULT 'desc'::text
)
RETURNS TABLE(
  vacancy_id uuid,
  vcode text,
  account_id uuid,
  account_name text,
  group_id uuid,
  group_name text,
  store_id uuid,
  store_name text,
  position_title text,
  employment_type text,
  vacancy_status text,
  pipeline_status text,
  vacant_date date,
  aging_days integer,
  aging_bucket text,
  target_fill_date date,
  urgency text,
  penalty_exposure numeric,
  hrco_name text,
  row_capabilities jsonb,
  total_count bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'vacant_date'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy list requires a valid session'
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
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'vcode',
    'account_name',
    'group_name',
    'store_name',
    'position_title',
    'vacancy_status',
    'pipeline_status',
    'vacant_date',
    'aging_days',
    'target_fill_date',
    'urgency'
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
      vl.id AS vacancy_id,
      vl.vcode,
      vl.account_id,
      vl.account AS account_name,
      vl.group_id,
      vl.group_name,
      vl.store_id,
      vl.store_name,
      vl.position AS position_title,
      vl.employment_type,
      vl.status AS vacancy_status,
      vl.derived_status AS pipeline_status,
      coalesce(vl.has_pending_closure, v_raw.has_pending_closure, false) AS has_pending_closure,
      coalesce(vl.closure_request_status, v_raw.closure_request_status) AS closure_request_status,
      vl.vacant_date,
      vl.aging_days::integer AS aging_days,
      CASE
        WHEN vl.aging_days IS NULL THEN 'unknown'
        WHEN vl.aging_days <= 7 THEN '0_7'
        WHEN vl.aging_days <= 14 THEN '8_14'
        WHEN vl.aging_days <= 30 THEN '15_30'
        ELSE '31_plus'
      END AS aging_bucket,
      vl.target_fill_date,
      vl.urgency_level AS urgency,
      CASE
        WHEN coalesce(v_raw.has_penalty, false)
          THEN coalesce(v_raw.penalty_amount, 0::numeric)
        ELSE 0::numeric
      END AS penalty_exposure,
      vl.hrco_name,
      vl.active_applicant_count,
      vl.hr_processing_count,
      vl.hc_filled,
      vl.hc_total,
      jsonb_build_object(
        'can_view_detail', true,
        'hc_filled', vl.hc_filled,
        'hc_total', vl.hc_total,
        'hc_display', vl.hc_display,
        'hr_processing_count', vl.hr_processing_count,
        'is_pool_vacancy', vl.is_pool_vacancy,
        'can_request_closure_hint',
          coalesce(v_role_level, 0) >= 30
          AND coalesce(vl.is_archived, false) = false
          AND vl.archived_at IS NULL
          AND coalesce(vl.has_pending_closure, v_raw.has_pending_closure, false) = false
          AND coalesce(vl.closure_request_status, v_raw.closure_request_status, '') <> 'Pending'
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived', 'closure', 'for_closure']),
        'authority', 'rls_action_rpcs'
      ) AS row_capabilities
    FROM public.vw_vacancy_list vl
    JOIN public.vacancies v_raw ON v_raw.id = vl.id
    WHERE
      coalesce(vl.is_archived, false) = false
      AND vl.archived_at IS NULL
      AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
      AND (
        coalesce(v_role_level, 0) >= 90
        OR (
          vl.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = v_profile_id
              AND us.account_id = vl.account_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            JOIN public.accounts a ON a.id = vl.account_id
            WHERE us.user_id = v_profile_id
              AND us.account_id IS NULL
              AND us.group_id = a.group_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.users_profile up_fallback
            JOIN public.accounts a ON a.id = vl.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (
                SELECT 1
                FROM public.user_scopes us_any
                WHERE us_any.user_id = v_profile_id
                  AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
              )
              AND (
                up_fallback.account_id = vl.account_id
                OR up_fallback.group_id = a.group_id
              )
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (
        p_status IS NULL
        OR CASE
             WHEN lower(btrim(p_status)) = 'open' THEN 
               (
                 -- ADR-001 Rule 4: Open capacity: visible iff unfulfilled capacity exists:
                 -- (s.hc_total - s.hc_filled - s.hr_processing_count - s.active_applicant_count) > 0
                 (s.hc_total - s.hc_filled - s.hr_processing_count - s.active_applicant_count) > 0
                 OR lower(s.pipeline_status) = 'open'
               )
               AND lower(s.pipeline_status) <> 'hired'
               AND s.vacancy_status <> 'Filled'
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
             WHEN lower(btrim(p_status)) = 'pipeline' THEN 
               (
                 s.active_applicant_count > 0
                 OR lower(s.pipeline_status) = 'pipeline'
               )
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
             WHEN lower(btrim(p_status)) IN ('closure', 'for_closure', 'closed') THEN
               lower(s.pipeline_status) IN ('closure', 'for closure')
               OR s.has_pending_closure = true
               OR lower(coalesce(s.closure_request_status, '')) = 'pending'
               OR lower(coalesce(s.vacancy_status, '')) IN ('closure', 'for_closure')
             ELSE (lower(s.vacancy_status) = lower(btrim(p_status)) OR lower(s.pipeline_status) = lower(btrim(p_status)))
           END
      )
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_position IS NULL OR lower(s.position_title) = lower(btrim(p_position)))
      AND (p_urgency IS NULL OR lower(coalesce(s.urgency, '')) = lower(btrim(p_urgency)))
      AND (p_aging_bucket IS NULL OR s.aging_bucket = lower(btrim(p_aging_bucket)))
      AND (p_vacant_from IS NULL OR s.vacant_date >= p_vacant_from)
      AND (p_vacant_to IS NULL OR s.vacant_date <= p_vacant_to)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.hrco_name, '') ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT count(*)::bigint AS cnt FROM filtered
  )
  SELECT
    f.vacancy_id,
    f.vcode,
    f.account_id,
    f.account_name,
    f.group_id,
    f.group_name,
    f.store_id,
    f.store_name,
    f.position_title,
    f.employment_type,
    f.vacancy_status,
    f.pipeline_status,
    f.vacant_date,
    f.aging_days,
    f.aging_bucket,
    f.target_fill_date,
    f.urgency,
    f.penalty_exposure,
    f.hrco_name,
    f.row_capabilities,
    c.cnt AS total_count
  FROM filtered f
  CROSS JOIN counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc' THEN
      CASE v_sort_by
        WHEN 'vcode' THEN f.vcode
        WHEN 'account_name' THEN f.account_name
        WHEN 'group_name' THEN f.group_name
        WHEN 'store_name' THEN f.store_name
        WHEN 'position_title' THEN f.position_title
        WHEN 'vacancy_status' THEN f.vacancy_status
        WHEN 'pipeline_status' THEN f.pipeline_status
        WHEN 'urgency' THEN f.urgency
        ELSE NULL
      END
    END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' THEN
      CASE v_sort_by
        WHEN 'vcode' THEN f.vcode
        WHEN 'account_name' THEN f.account_name
        WHEN 'group_name' THEN f.group_name
        WHEN 'store_name' THEN f.store_name
        WHEN 'position_title' THEN f.position_title
        WHEN 'vacancy_status' THEN f.vacancy_status
        WHEN 'pipeline_status' THEN f.pipeline_status
        WHEN 'urgency' THEN f.urgency
        ELSE NULL
      END
    END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc' THEN
      CASE v_sort_by
        WHEN 'vacant_date' THEN f.vacant_date
        WHEN 'target_fill_date' THEN f.target_fill_date
        ELSE NULL
      END
    END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' THEN
      CASE v_sort_by
        WHEN 'vacant_date' THEN f.vacant_date
        WHEN 'target_fill_date' THEN f.target_fill_date
        ELSE NULL
      END
    END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'aging_days' THEN f.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days' THEN f.aging_days END DESC NULLS LAST,
    f.vacant_date DESC NULLS LAST,
    f.vacancy_id ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_web_vacancies(text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_web_vacancies(text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text) TO authenticated, service_role, postgres;


-- ============================================================================
-- 4. Update public.get_web_vacancy_summary (ADR-001 Rule 4 Restoration)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_web_vacancy_summary(
  p_status text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id uuid DEFAULT NULL::uuid,
  p_position text DEFAULT NULL::text,
  p_urgency text DEFAULT NULL::text,
  p_search text DEFAULT NULL::text,
  p_vacant_from date DEFAULT NULL::date,
  p_vacant_to date DEFAULT NULL::date
)
RETURNS TABLE(
  total_open bigint,
  with_applicant bigint,
  rejected bigint,
  backout bigint,
  aging_0_7 bigint,
  aging_8_14 bigint,
  aging_15_30 bigint,
  aging_31_plus bigint,
  aging_unknown bigint,
  critical_urgency bigint,
  high_urgency bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy summary requires a valid session'
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
    RAISE EXCEPTION 'forbidden: web vacancy summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      vl.id AS vacancy_id,
      vl.vcode,
      vl.account_id,
      vl.account AS account_name,
      vl.group_id,
      vl.group_name,
      vl.store_name,
      vl.position AS position_title,
      vl.status AS vacancy_status,
      vl.derived_status AS pipeline_status,
      coalesce(vl.has_pending_closure, v_raw.has_pending_closure, false) AS has_pending_closure,
      coalesce(vl.closure_request_status, v_raw.closure_request_status) AS closure_request_status,
      vl.vacant_date,
      vl.aging_days::integer AS aging_days,
      CASE
        WHEN vl.aging_days IS NULL THEN 'unknown'
        WHEN vl.aging_days <= 7 THEN '0_7'
        WHEN vl.aging_days <= 14 THEN '8_14'
        WHEN vl.aging_days <= 30 THEN '15_30'
        ELSE '31_plus'
      END AS aging_bucket,
      vl.urgency_level AS urgency,
      vl.active_applicant_count,
      vl.hc_filled,
      vl.hc_total,
      vl.hr_processing_count
    FROM public.vw_vacancy_list vl
    JOIN public.vacancies v_raw ON v_raw.id = vl.id
    WHERE
      coalesce(vl.is_archived, false) = false
      AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
      AND (
        coalesce(v_role_level, 0) >= 90
        OR (
          vl.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = v_profile_id
              AND us.account_id = vl.account_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            JOIN public.accounts a ON a.id = vl.account_id
            WHERE us.user_id = v_profile_id
              AND us.account_id IS NULL
              AND us.group_id = a.group_id
          )
          OR EXISTS (
            SELECT 1
            FROM public.users_profile up_fallback
            JOIN public.accounts a ON a.id = vl.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (
                SELECT 1
                FROM public.user_scopes us_any
                WHERE us_any.user_id = v_profile_id
                  AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
              )
              AND (
                up_fallback.account_id = vl.account_id
                OR up_fallback.group_id = a.group_id
              )
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (
        p_status IS NULL
        OR CASE
             WHEN lower(btrim(p_status)) = 'open' THEN 
               (
                 -- ADR-001 Rule 4: Open capacity: visible iff unfulfilled capacity exists:
                 -- (s.hc_total - s.hc_filled - s.hr_processing_count - s.active_applicant_count) > 0
                 (s.hc_total - s.hc_filled - s.hr_processing_count - s.active_applicant_count) > 0
                 OR lower(s.pipeline_status) = 'open'
               )
               AND lower(s.pipeline_status) <> 'hired'
               AND s.vacancy_status <> 'Filled'
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
             WHEN lower(btrim(p_status)) = 'pipeline' THEN 
               (
                 s.active_applicant_count > 0
                 OR lower(s.pipeline_status) = 'pipeline'
               )
               AND s.has_pending_closure = false
               AND lower(coalesce(s.closure_request_status, '')) <> 'pending'
               AND lower(coalesce(s.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
             WHEN lower(btrim(p_status)) IN ('closure', 'for_closure', 'closed') THEN
               lower(s.pipeline_status) IN ('closure', 'for closure')
               OR s.has_pending_closure = true
               OR lower(coalesce(s.closure_request_status, '')) = 'pending'
               OR lower(coalesce(s.vacancy_status, '')) IN ('closure', 'for_closure')
             ELSE (lower(s.vacancy_status) = lower(btrim(p_status)) OR lower(s.pipeline_status) = lower(btrim(p_status)))
           END
      )
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_position IS NULL OR lower(s.position_title) = lower(btrim(p_position)))
      AND (p_urgency IS NULL OR lower(coalesce(s.urgency, '')) = lower(btrim(p_urgency)))
      AND (p_vacant_from IS NULL OR s.vacant_date >= p_vacant_from)
      AND (p_vacant_to IS NULL OR s.vacant_date <= p_vacant_to)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.group_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.store_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  applicant_rollup AS (
    SELECT
      f.vacancy_id,
      count(a.id) FILTER (
        WHERE COALESCE(a.is_archived, false) = false
          AND replace(lower(btrim(coalesce(a.status, ''))), ' ', '_') IN ('rejected', 'rejected_by_ops')
      ) AS rejected_count,
      count(a.id) FILTER (
        WHERE COALESCE(a.is_archived, false) = false
          AND replace(lower(btrim(coalesce(a.status, ''))), ' ', '_') IN ('backout', 'failed', 'did_not_report')
      ) AS backout_count
    FROM filtered f
    LEFT JOIN public.applicants a ON a.vacancy_vcode = f.vcode
    GROUP BY f.vacancy_id
  )
  SELECT
    count(*) FILTER (
      WHERE (
        (f.hc_total - f.hc_filled - f.hr_processing_count - f.active_applicant_count) > 0
        OR f.pipeline_status = 'Open'
      )
        AND lower(f.pipeline_status) <> 'hired'
        AND f.vacancy_status <> 'Filled'
        AND f.has_pending_closure = false
        AND lower(coalesce(f.closure_request_status, '')) <> 'pending'
        AND lower(coalesce(f.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
    )::bigint AS total_open,
    count(*) FILTER (
      WHERE (
        f.active_applicant_count > 0
        OR f.pipeline_status = 'Pipeline'
      )
        AND f.has_pending_closure = false
        AND lower(coalesce(f.closure_request_status, '')) <> 'pending'
        AND lower(coalesce(f.vacancy_status, '')) NOT IN ('closure', 'for_closure', 'closed', 'archived')
    )::bigint AS with_applicant,
    count(*) FILTER (WHERE coalesce(ar.rejected_count, 0) > 0)::bigint AS rejected,
    count(*) FILTER (WHERE coalesce(ar.backout_count, 0) > 0)::bigint AS backout,
    count(*) FILTER (WHERE f.aging_bucket = '0_7')::bigint AS aging_0_7,
    count(*) FILTER (WHERE f.aging_bucket = '8_14')::bigint AS aging_8_14,
    count(*) FILTER (WHERE f.aging_bucket = '15_30')::bigint AS aging_15_30,
    count(*) FILTER (WHERE f.aging_bucket = '31_plus')::bigint AS aging_31_plus,
    count(*) FILTER (WHERE f.aging_bucket = 'unknown')::bigint AS aging_unknown,
    count(*) FILTER (WHERE lower(coalesce(f.urgency, '')) = 'critical')::bigint AS critical_urgency,
    count(*) FILTER (WHERE lower(coalesce(f.urgency, '')) = 'high')::bigint AS high_urgency
  FROM filtered f
  LEFT JOIN applicant_rollup ar ON ar.vacancy_id = f.vacancy_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_vacancy_summary(text, uuid, uuid, text, text, text, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_vacancy_summary(text, uuid, uuid, text, text, text, date, date) TO authenticated, service_role, postgres;

NOTIFY pgrst, 'reload schema';
