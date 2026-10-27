-- Migration: 20261027120000_fix_hrco_all_scope_hr_emploc_correction_rpc
-- Description: Fix role/scope visibility bug for HRCO role with "All Scope" access across Correction, Review, and Ready statuses.
--
-- Root Cause:
--   1. get_correction_requests_scoped strictly enforced:
--        (v_my_role NOT IN ('hrco') OR he.hrco_user_id_snapshot = v_my_id)
--      which completely excluded HRCO users with "All Scope" (scope_type = 'global' or hrco_global_visibility = true)
--      from viewing any records where hrco_user_id_snapshot was null or assigned to another user.
--   2. list_web_hr_emplocs, get_web_hr_emploc_summary, and get_web_hr_emploc_detail relied solely on role_level >= 90
--      for global scoping bypass, which excluded HRCOs (level 45) unless their account name strictly matched get_my_allowed_accounts().
--
-- Solution:
--   1. Update public.get_correction_requests_scoped to check public.get_my_scope_type() = 'global',
--      public.i_have_hrco_global_visibility(), public.i_have_full_access(), he.account = ANY(get_my_allowed_accounts()),
--      or he.hrco_user_id_snapshot = v_my_id.
--   2. Update public.list_web_hr_emplocs, public.get_web_hr_emploc_summary, and public.get_web_hr_emploc_detail
--      to explicitly allow callers with global scope (get_my_scope_type() = 'global' or hrco_global_visibility = true).

BEGIN;

-- ── 1. Recreate get_correction_requests_scoped ────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_correction_requests_scoped(
  p_hr_emploc_id uuid DEFAULT NULL::uuid,
  p_status text DEFAULT NULL::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  hr_emploc_id uuid,
  applicant_id uuid,
  applicant_name text,
  group_id uuid,
  account_id uuid,
  assigned_hrco_id uuid,
  assigned_hrco_name text,
  requested_by uuid,
  requested_by_name text,
  requested_at timestamp with time zone,
  issue_type text,
  hr_remarks text,
  additional_remarks text,
  hrco_notes text,
  ops_update_message text,
  status text,
  sla_status text,
  allows_attachment boolean,
  last_updated_at timestamp with time zone,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  reopened_at timestamp with time zone,
  for_review_at timestamp with time zone,
  ready_at timestamp with time zone,
  attachment_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_my_id   uuid := public.get_my_profile_id();
  v_my_role text := public.get_my_role();
BEGIN
  IF v_my_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      he.*,
      CASE
        WHEN he.hr_status = 'For Correction' THEN 'for_correction'
        WHEN he.hr_status = 'For Review' THEN 'for_review'
        WHEN he.hr_status = 'Complete'
             AND (NULLIF(BTRIM(COALESCE(he.employee_no, '')), '') IS NOT NULL
                  OR NULLIF(BTRIM(COALESCE(he.emploc_no, '')), '') IS NOT NULL)
          THEN 'ready'
        WHEN he.hr_status = 'Complete' THEN 'for_review'
        ELSE 'for_review'
      END AS mapped_status
    FROM public.hr_emploc he
    WHERE he.deleted_at IS NULL
      AND he.correction_reason IS NOT NULL
  )
  SELECT
    he.id                                                              AS id,
    he.id                                                              AS hr_emploc_id,
    he.applicant_id                                                    AS applicant_id,
    COALESCE(he.applicant_name_snapshot, he.applicant_name)            AS applicant_name,
    a.group_id                                                         AS group_id,
    he.account_id                                                      AS account_id,
    he.hrco_user_id_snapshot                                           AS assigned_hrco_id,
    hrco.full_name                                                     AS assigned_hrco_name,
    he.updated_by                                                      AS requested_by,
    he.hr_reviewed_by                                                  AS requested_by_name,
    COALESCE(he.hr_reviewed_at, he.updated_at)                         AS requested_at,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN COALESCE(he.correction_reason->0->>'code', 'OTHER')
      ELSE COALESCE(he.correction_reason->>'type', 'OTHER')
    END                                                                AS issue_type,

    COALESCE(he.hr_remarks, '')                                        AS hr_remarks,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN he.correction_reason->0->>'comment'
      ELSE he.correction_reason->>'comment'
    END                                                                AS additional_remarks,

    he.ops_remarks                                                     AS hrco_notes,
    he.ops_remarks                                                     AS ops_update_message,
    he.mapped_status                                                   AS status,
    'normal'::text                                                     AS sla_status,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN EXISTS (
        SELECT 1
          FROM jsonb_array_elements(he.correction_reason) el
          JOIN public.hr_emploc_issue_types it ON it.code = el->>'code'
         WHERE it.allows_attachment = true
      )
      ELSE COALESCE(he.correction_reason->>'type', '') <> 'INVALID_BENEFITS'
    END                                                                AS allows_attachment,

    he.updated_at                                                      AS last_updated_at,
    NULL::uuid                                                         AS reviewed_by,
    NULL::timestamptz                                                  AS reviewed_at,
    NULL::timestamptz                                                  AS reopened_at,
    CASE WHEN he.mapped_status = 'for_review' THEN he.updated_at ELSE NULL::timestamptz END AS for_review_at,
    CASE WHEN he.mapped_status = 'ready' THEN he.updated_at ELSE NULL::timestamptz END      AS ready_at,

    COALESCE((
      SELECT COUNT(*)
        FROM public.hr_emploc_correction_attachments atch
       WHERE atch.hr_emploc_id = he.id AND atch.is_deleted = false
    ), 0)::bigint                                                      AS attachment_count

  FROM scoped he
  LEFT JOIN public.accounts a ON a.id = he.account_id
  LEFT JOIN public.users_profile hrco ON hrco.id = he.hrco_user_id_snapshot
  WHERE
    (
      v_my_role NOT IN ('hrco')
      OR public.i_have_full_access()
      OR public.get_my_scope_type() = 'global'
      OR public.i_have_hrco_global_visibility()
      OR he.hrco_user_id_snapshot = v_my_id
      OR he.account = ANY (public.get_my_allowed_accounts())
      OR (he.account_id IS NOT NULL AND he.account_id IN (
        SELECT acc.id FROM public.accounts acc WHERE acc.account_name = ANY (public.get_my_allowed_accounts())
      ))
    )
    AND (p_hr_emploc_id IS NULL OR he.id = p_hr_emploc_id)
    AND (p_status IS NULL OR he.mapped_status = p_status)
  ORDER BY he.updated_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- ── 2. Recreate list_web_hr_emplocs ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue         text DEFAULT NULL,
  p_status        text DEFAULT NULL,
  p_deficiency    text DEFAULT NULL,
  p_sla_filter    text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL,
  p_search        text DEFAULT NULL,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text DEFAULT 'date_requested',
  p_sort_dir      text DEFAULT 'desc'
)
RETURNS TABLE (
  hr_emploc_id          uuid,
  applicant_name        text,
  vcode                 text,
  account_id            uuid,
  account_name          text,
  group_id              uuid,
  group_name            text,
  store_id              uuid,
  store_name            text,
  position_title        text,
  hr_status             text,
  status                text,
  emploc_no             text,
  employee_no           text,
  date_requested        timestamp with time zone,
  created_at            timestamp with time zone,
  hired_date            date,
  assignment_type       text,
  roving_assignment_id  uuid,
  aging_days            integer,
  sla_breached          boolean,
  sla_status            text,
  sla_deadline          timestamp with time zone,
  deficiency_summary    jsonb,
  is_pending_deletion   boolean,
  row_capabilities      jsonb,
  total_count           bigint
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
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'date_requested'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc list requires a valid session'
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
    WHERE
      -- Strict Soft-Delete Enforcement (always mandatory, never bypassed by role level)
      h.deleted_at IS NULL
      -- Scoped Visibility Enforcements (role_level >= 90 or global scope bypasses account scoping)
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR public.i_have_full_access()
        OR public.get_my_scope_type() = 'global'
        OR public.i_have_hrco_global_visibility()
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
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Queue Filter (Aligned with Mobile tabs and correction workflow)
      (p_queue IS NULL
       OR (p_queue = 'pending' AND s.hr_status = 'Pending')
       OR (p_queue = 'correction' AND s.hr_status = 'For Correction')
       OR (
         p_queue = 'review' AND (
           s.hr_status = 'For Review'
           OR (
             s.correction_reason IS NOT NULL
             AND s.hr_status NOT IN ('For Correction', 'Pending')
             AND NOT (s.hr_status = 'Complete' AND (NULLIF(BTRIM(COALESCE(s.employee_no, '')), '') IS NOT NULL OR NULLIF(BTRIM(COALESCE(s.emploc_no, '')), '') IS NOT NULL))
           )
         )
       )
       OR (
         p_queue = 'ready' AND (
           s.hr_status = 'Complete'
           AND s.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
           AND NOT EXISTS (SELECT 1 FROM public.plantilla p WHERE p.hr_emploc_id = s.hr_emploc_id)
         )
       )
       OR (p_queue = 'transferred' AND s.hr_status = 'Transferred')
       OR (p_queue = 'rejected' AND s.hr_status = 'Rejected')
      )
      
      -- Deficiency Filter
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
      
      -- SLA Filter
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      
      -- Status Filter
      AND (p_status IS NULL OR s.status = p_status)
      
      -- Scope Filters
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      
      -- Search Filter
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
  ),
  counted AS (
    SELECT count(*)::bigint AS cnt FROM filtered
  )
  SELECT
    f.hr_emploc_id,
    f.applicant_name,
    f.vcode,
    f.account_id,
    f.account_name,
    f.group_id,
    f.group_name,
    f.store_id,
    f.store_name,
    f.position_title,
    f.hr_status,
    f.status,
    f.emploc_no,
    f.employee_no,
    f.date_requested,
    f.created_at,
    f.hired_date,
    f.assignment_type,
    f.roving_assignment_id,
    f.aging_days,
    f.sla_breached,
    f.sla_status,
    f.sla_deadline,
    f.deficiency_summary,
    f.is_pending_deletion,
    f.row_capabilities,
    c.cnt AS total_count
  FROM filtered f
  CROSS JOIN counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'vcode' THEN f.vcode END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode' THEN f.vcode END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'applicant_name' THEN f.applicant_name END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'applicant_name' THEN f.applicant_name END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'account_name' THEN f.account_name END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name' THEN f.account_name END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'group_name' THEN f.group_name END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name' THEN f.group_name END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'store_name' THEN f.store_name END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name' THEN f.store_name END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'position_title' THEN f.position_title END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title' THEN f.position_title END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'hr_status' THEN f.hr_status END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'hr_status' THEN f.hr_status END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'status' THEN f.status END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'status' THEN f.status END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'emploc_no' THEN f.emploc_no END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'emploc_no' THEN f.emploc_no END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'employee_no' THEN f.employee_no END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_no' THEN f.employee_no END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'aging_days' THEN f.aging_days END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days' THEN f.aging_days END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'date_requested' THEN f.date_requested END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'date_requested' THEN f.date_requested END DESC,
    CASE WHEN v_sort_dir = 'asc' AND v_sort_by = 'created_at' THEN f.created_at END ASC,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'created_at' THEN f.created_at END DESC,
    f.created_at DESC
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

-- ── 3. Recreate get_web_hr_emploc_summary ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_summary(
  p_queue         text DEFAULT NULL,
  p_status        text DEFAULT NULL,
  p_deficiency    text DEFAULT NULL,
  p_sla_filter    text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL,
  p_search        text DEFAULT NULL
)
RETURNS TABLE (
  pending_count          bigint,
  correction_count       bigint,
  review_count           bigint,
  ready_count            bigint,
  sla_breached_count     bigint,
  sla_warning_count      bigint,
  with_deficiency_count  bigint,
  pending_deletion_count bigint
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
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc summary requires a valid session'
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
    RAISE EXCEPTION 'forbidden: web hr_emploc summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.id AS hr_emploc_id,
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
      
      -- SLA status determinations
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
      -- Strict Soft-Delete Enforcement (always mandatory, never bypassed by role level)
      h.deleted_at IS NULL
      -- Scoped Visibility Enforcements (role_level >= 90 or global scope bypasses account scoping)
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR public.i_have_full_access()
        OR public.get_my_scope_type() = 'global'
        OR public.i_have_hrco_global_visibility()
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
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Deficiency Filter
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
      
      -- SLA Filter
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      
      -- Status Filter
      AND (p_status IS NULL OR s.status = p_status)
      
      -- Scope Filters
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      
      -- Search Filter
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
    count(*) FILTER (WHERE f.hr_status = 'Pending')::bigint AS pending_count,
    count(*) FILTER (WHERE f.hr_status = 'For Correction')::bigint AS correction_count,
    count(*) FILTER (
      WHERE f.hr_status = 'For Review'
         OR (
           f.correction_reason IS NOT NULL
           AND f.hr_status NOT IN ('For Correction', 'Pending')
           AND NOT (f.hr_status = 'Complete' AND (NULLIF(BTRIM(COALESCE(f.employee_no, '')), '') IS NOT NULL OR NULLIF(BTRIM(COALESCE(f.emploc_no, '')), '') IS NOT NULL))
         )
    )::bigint AS review_count,
    count(*) FILTER (
      WHERE f.hr_status = 'Complete'
        AND f.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
        AND NOT EXISTS (SELECT 1 FROM public.plantilla p WHERE p.hr_emploc_id = f.hr_emploc_id)
    )::bigint AS ready_count,
    count(*) FILTER (WHERE f.sla_breached = true)::bigint AS sla_breached_count,
    count(*) FILTER (WHERE f.sla_warning = true)::bigint AS sla_warning_count,
    count(*) FILTER (WHERE f.correction_reason IS NOT NULL)::bigint AS with_deficiency_count,
    count(*) FILTER (WHERE f.hr_status = 'Pending Deletion')::bigint AS pending_deletion_count
  FROM filtered f;
END;
$$;

-- ── 4. Recreate get_web_hr_emploc_detail ──────────────────────────────────────
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
  sla_breached               boolean,
  sla_status                 text,
  sla_deadline               timestamp with time zone,
  aging_days                 integer,
  employee_name_snapshot     text,
  birthdate_snapshot         date,
  civil_status_snapshot      text,
  address_snapshot           text,
  contact_number_snapshot    text,
  sss_snapshot               text,
  philhealth_snapshot        text,
  pagibig_snapshot           text,
  requirement_overall_status text,
  hrco_user_id_snapshot      uuid,
  hrco_name                  text,
  hr_reviewed_by             text,
  hr_reviewed_at             timestamp with time zone,
  hr_remarks                 text,
  ops_remarks                text,
  hr_rejection_reason        text,
  deficiency_summary         jsonb,
  correction_reason          jsonb,
  correction_attachments     jsonb,
  deletion_request           jsonb,
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
      AND h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR public.i_have_full_access()
        OR public.get_my_scope_type() = 'global'
        OR public.i_have_hrco_global_visibility()
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
    
    -- Covered Stores normalized array
    CASE
      WHEN h.assignment_type = 'Roving'::public.hr_emploc_assignment_type THEN (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'store_id', s.id,
            'store_name', s.store_name,
            'address', s.address
          )
        ), '[]'::jsonb)
        FROM public.hr_emploc_store_links hsl
        JOIN public.stores s ON s.id = hsl.store_id
        WHERE hsl.hr_emploc_id = h.id
      )
      ELSE '[]'::jsonb
    END AS covered_stores,

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

    -- SLA computations
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

    -- Snapshots
    h.employee_name_snapshot,
    h.birthdate_snapshot,
    h.civil_status_snapshot,
    h.address_snapshot,
    h.contact_number_snapshot,
    h.sss_snapshot,
    h.philhealth_snapshot,
    h.pagibig_snapshot,
    h.requirement_overall_status,
    h.hrco_user_id_snapshot,
    COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
    h.hr_reviewed_by,
    h.hr_reviewed_at,
    h.hr_remarks,
    h.ops_remarks,
    h.hr_rejection_reason,

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
              OR public.i_have_full_access()
              OR public.get_my_scope_type() = 'global'
              OR public.i_have_hrco_global_visibility()
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
        'requested_at', dr.created_at,
        'reviewed_by', dr.reviewed_by,
        'reviewed_at', dr.reviewed_at,
        'review_remarks', dr.review_remarks,
        'deletion_type', dr.deletion_type,
        'original_emploc_id', dr.original_emploc_id
      )
      FROM public.hr_emploc_deletion_requests dr
      WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
      ORDER BY dr.created_at DESC
      LIMIT 1
    ) AS deletion_request,

    -- Unified Audit / History Timeline
    (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'event_id', t.id,
          'event_label', t.event_label,
          'remarks', t.remarks,
          'created_at', t.created_at,
          'actor_name', t.actor_name,
          'actor_role', t.actor_role
        ) ORDER BY t.created_at DESC
      ), '[]'::jsonb)
      FROM (
        SELECT
          al.id,
          al.action AS event_label,
          COALESCE(al.new_data->>'remarks', al.new_data->>'notes', al.action) AS remarks,
          al.timestamp AS created_at,
          up_act.full_name AS actor_name,
          r_act.role_name AS actor_role
        FROM public.audit_logs al
        LEFT JOIN public.users_profile up_act ON up_act.id = al.actor_id
        LEFT JOIN public.roles r_act ON r_act.id = up_act.role_id
        WHERE al.module = 'hr_emploc' AND al.record_id = h.id::text
        UNION ALL
        SELECT
          dr.id,
          'Deletion Request: ' || dr.status AS event_label,
          dr.reason AS remarks,
          dr.created_at,
          dr.requested_by AS actor_name,
          dr.requested_by_role AS actor_role
        FROM public.hr_emploc_deletion_requests dr
        WHERE dr.hr_emploc_id = h.id
      ) t
    ) AS timeline,

    -- UI Row / Detail Capabilities
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
  WHERE h.id = p_hr_emploc_id;
END;
$$;

-- ── 5. Permissions & Grants ───────────────────────────────────────────────────
COMMENT ON FUNCTION public.get_correction_requests_scoped(uuid, text, integer, integer) IS
  'Scoped correction requests fetcher for HR Emploc module. Supports HRCO users with All Scope, global visibility, or allowed accounts.';

COMMENT ON FUNCTION public.list_web_hr_emplocs IS
  'Web presentation list query for HR Emploc module. Strictly enforces deleted_at IS NULL, aligns queue filtering with Mobile, and honors global scope / hrco_global_visibility.';

COMMENT ON FUNCTION public.get_web_hr_emploc_summary IS
  'Web presentation summary counters for HR Emploc module. Strictly enforces deleted_at IS NULL, aligns queue counting with Mobile, and honors global scope / hrco_global_visibility.';

COMMENT ON FUNCTION public.get_web_hr_emploc_detail(uuid) IS
  'Web presentation detail query for HR Emploc module. Strictly enforces deleted_at IS NULL, aligns authorization with list_web_hr_emplocs, and honors global scope / hrco_global_visibility.';

REVOKE ALL ON FUNCTION public.get_correction_requests_scoped(uuid, text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_correction_requests_scoped(uuid, text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_correction_requests_scoped(uuid, text, integer, integer) TO authenticated;

REVOKE ALL ON FUNCTION public.list_web_hr_emplocs FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_web_hr_emplocs FROM anon;
GRANT EXECUTE ON FUNCTION public.list_web_hr_emplocs TO authenticated;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_summary TO authenticated;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_detail(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_hr_emploc_detail(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_detail(uuid) TO authenticated;

COMMIT;
