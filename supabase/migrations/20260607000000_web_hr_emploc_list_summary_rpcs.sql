-- Migration: 20260607000000_web_hr_emploc_list_summary_rpcs.sql
-- Ticket: OHM2026_1092 - Web HR Emploc list and summary presentation RPCs
--
-- Purpose:
--   Safe, read-only presentation contracts for HR Emploc dense-table list and
--   summary widgets on the OHMployee Web Dashboard.
--
-- Security invariants:
--   - Caller identity is derived strictly from auth.uid().
--   - Scoping is derived dynamically from users_profile + user_scopes.
--   - Unauthenticated, inactive, unauthorized, and out-of-scope callers fail closed.
--   - Outbound PII (contact numbers, email, addresses, exact birthdate) is excluded.
--   - Sensitive fields (SSS, PhilHealth, Pag-IBIG) are completely omitted.
--   - Row capabilities are UI hints only; action-specific RPCs and triggers remain authority.
--   - Execution is granted only to authenticated users. Public and anon are revoked.

DROP FUNCTION IF EXISTS public.list_web_hr_emplocs(
  text, text, text, text, uuid, uuid, text, integer, integer, text, text
);

CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue         text    DEFAULT NULL,
  p_status        text    DEFAULT NULL,
  p_deficiency    text    DEFAULT NULL,
  p_sla_filter    text    DEFAULT NULL,
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_search        text    DEFAULT NULL,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'date_requested',
  p_sort_dir      text    DEFAULT 'desc'
)
RETURNS TABLE (
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
  -- Direct SQL/anon safety. Fail closed if unauthenticated.
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc list requires a valid session'
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
    RAISE EXCEPTION 'forbidden: web hr_emploc list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- Validate sorting column whitelist
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

  -- Validate sorting direction
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
      h.hr_status,
      h.status,
      h.emploc_no,
      h.employee_no,
      h.date_requested,
      h.created_at,
      h.hired_date,
      h.assignment_type::text AS assignment_type,
      h.roving_assignment_id,
      
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
      COALESCE(h.hr_status = 'Pending Deletion', false) AS is_pending_deletion,
      
      -- UI capabilities presentation hints
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
    WHERE
      -- Scoped Visibility Enforcements
      (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.deleted_at IS NULL
          AND (
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
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Queue Filter
      (p_queue IS NULL
       OR (p_queue = 'pending' AND s.hr_status = 'Pending')
       OR (p_queue = 'correction' AND s.hr_status = 'For Correction')
       OR (p_queue = 'review' AND s.hr_status = 'For Review')
       OR (p_queue = 'ready' AND s.hr_status = 'Complete')
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
$$;

COMMENT ON FUNCTION public.list_web_hr_emplocs(
  text, text, text, text, uuid, uuid, text, integer, integer, text, text
) IS
  'OHM2026_1092 - Web presentation contract only. Returns scoped dense-table rows from public.hr_emploc with allowlisted filtering/sorting. RLS/action RPCs remain authority.';


DROP FUNCTION IF EXISTS public.get_web_hr_emploc_summary(
  text, text, text, text, uuid, uuid, text
);

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
  -- Direct SQL/anon safety. Fail closed if unauthenticated.
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
      h.hr_status,
      h.status,
      h.account_id,
      a.group_id,
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
      -- Scoped Visibility Enforcements
      (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.deleted_at IS NULL
          AND (
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
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Queue Filter
      (p_queue IS NULL
       OR (p_queue = 'pending' AND s.hr_status = 'Pending')
       OR (p_queue = 'correction' AND s.hr_status = 'For Correction')
       OR (p_queue = 'review' AND s.hr_status = 'For Review')
       OR (p_queue = 'ready' AND s.hr_status = 'Complete')
       OR (p_queue = 'transferred' AND s.hr_status = 'Transferred')
       OR (p_queue = 'rejected' AND s.hr_status = 'Rejected')
      )
      
      -- Deficiency Filter
      AND (p_deficiency IS NULL
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
        OR s.hr_status ILIKE '%' || btrim(p_search) || '%'
        OR s.status ILIKE '%' || btrim(p_search) || '%'
      )
  )
  SELECT
    count(*) FILTER (WHERE f.hr_status = 'Pending')::bigint AS pending_count,
    count(*) FILTER (WHERE f.hr_status = 'For Correction')::bigint AS correction_count,
    count(*) FILTER (WHERE f.hr_status = 'For Review')::bigint AS review_count,
    count(*) FILTER (WHERE f.hr_status = 'Complete')::bigint AS ready_count,
    count(*) FILTER (WHERE f.sla_breached = true)::bigint AS sla_breached_count,
    count(*) FILTER (WHERE f.sla_warning = true)::bigint AS sla_warning_count,
    count(*) FILTER (WHERE f.correction_reason IS NOT NULL)::bigint AS with_deficiency_count,
    count(*) FILTER (WHERE f.hr_status = 'Pending Deletion')::bigint AS pending_deletion_count
  FROM filtered f;
END;
$$;

COMMENT ON FUNCTION public.get_web_hr_emploc_summary(
  text, text, text, text, uuid, uuid, text
) IS
  'OHM2026_1092 - Web presentation contract only. Returns scoped summary counts from public.hr_emploc and active correction reasons. RLS/action RPCs remain authority.';


REVOKE ALL ON FUNCTION public.list_web_hr_emplocs(
  text, text, text, text, uuid, uuid, text, integer, integer, text, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_web_hr_emplocs(
  text, text, text, text, uuid, uuid, text, integer, integer, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_web_hr_emplocs(
  text, text, text, text, uuid, uuid, text, integer, integer, text, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary(
  text, text, text, text, uuid, uuid, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_hr_emploc_summary(
  text, text, text, text, uuid, uuid, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_hr_emploc_summary(
  text, text, text, text, uuid, uuid, text
) TO authenticated;
