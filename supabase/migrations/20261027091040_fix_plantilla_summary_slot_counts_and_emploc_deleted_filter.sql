-- =============================================================================
-- Migration: 20261027190000_fix_plantilla_summary_slot_counts_and_emploc_deleted_filter.sql
-- Prompt ID: ohm#4x7n2k9w (Phase 2 — Step 1: 1A + 1B)
--
-- Scope (Step 1 ONLY):
--   1A (RC-5): Enforce h.deleted_at IS NULL outside the role_level >= 90 bypass
--      in public.get_web_hr_emploc_summary and public.list_web_hr_emplocs so
--      soft-deleted HR Emploc records never leak to Super Admins (Golden Rule).
--   1B (RC-1 + RC-3): Update public.get_web_plantilla_summary and
--      public.list_web_plantilla_store_staffing to:
--        - Exclude pool vacancies (COALESCE(v.is_pool_vacancy, false) = false
--          AND COALESCE(v.affects_required_hc, true) = true) in BOTH vacant
--          and hrProcess terms.
--        - Replace SUM(vacancies.required_headcount) WHERE status = 'Open' with
--          slot-based vacant capacity from public.plantilla_slots
--          (slot_status IN ('open', 'pipeline') AND closed_at IS NULL) plus
--          open public.coverage_slots, excluding any slot already counted in
--          hrProcess so each slot is counted at most once.
--        - Preserve exact RPC parameter signatures and return column names/types.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1A-1. public.get_web_hr_emploc_summary
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_summary(
  p_queue      text DEFAULT NULL::text,
  p_status     text DEFAULT NULL::text,
  p_deficiency text DEFAULT NULL::text,
  p_sla_filter text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id   uuid DEFAULT NULL::uuid,
  p_search     text DEFAULT NULL::text
)
RETURNS TABLE(
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
AS $function$
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
      -- Golden Rule: soft-deleted rows are never visible, regardless of role_level
      h.deleted_at IS NULL
      -- Scoped Visibility Enforcements
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
$function$;


-- =============================================================================
-- 1A-2. public.list_web_hr_emplocs
-- =============================================================================
CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue      text DEFAULT NULL::text,
  p_status     text DEFAULT NULL::text,
  p_deficiency text DEFAULT NULL::text,
  p_sla_filter text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id   uuid DEFAULT NULL::uuid,
  p_search     text DEFAULT NULL::text,
  p_limit      integer DEFAULT 50,
  p_offset     integer DEFAULT 0,
  p_sort_by    text DEFAULT 'date_requested'::text,
  p_sort_dir   text DEFAULT 'desc'::text
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
STABLE
SECURITY DEFINER
SET search_path TO 'public'
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
  -- Direct SQL/anon safety. Fail closed if unauthenticated.
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
      EXISTS (
        SELECT 1 FROM public.hr_emploc_deletion_requests dr
        WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
      ) AS is_pending_deletion,

      -- UI capabilities presentation hints
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
      -- Golden Rule: soft-deleted rows are never visible, regardless of role_level
      h.deleted_at IS NULL
      -- Scoped Visibility Enforcements
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
$function$;


-- =============================================================================
-- 1B-1. public.get_web_plantilla_summary
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_web_plantilla_summary(
  p_search     text DEFAULT NULL::text,
  p_account_id uuid DEFAULT NULL::uuid,
  p_group_id   uuid DEFAULT NULL::uuid
)
RETURNS TABLE(
  active_employees           bigint,
  inactive_employees         bigint,
  roving_count               bigint,
  stationary_count           bigint,
  onboarding_pipeline_count  bigint,
  pending_deactivation_count bigint,
  staffing_risk_count        bigint,
  open_headcount_count       bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_level integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla summary requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_level
  INTO v_profile_id, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web plantilla summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH plantilla_scoped AS (
    SELECT
      p.account_id, a.group_id, p.status, p.store_id, p.deployment_type, p.roving_assignment_id,
      p.employee_name, p.employee_no, p.store_name
    FROM public.v_plantilla_safe p
    LEFT JOIN public.accounts a ON a.id = p.account_id
    WHERE
      p.source_headcount_request_id IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = p.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = p.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  plantilla_filtered AS (
    SELECT s.*
    FROM plantilla_scoped s
    WHERE (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.employee_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  -- All non-deleted hr_emploc rows in Pending/Complete onboarding (excluding pool vacancies)
  hr_pipeline_all AS (
    SELECT
      h.id,
      h.account_id,
      a.group_id,
      h.slot_id,
      h.coverage_slot_id,
      h.vcode,
      h.store_id
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.vacancies v
      ON v.id = COALESCE(
        h.vacancy_id,
        (
          SELECT v2.id
          FROM public.vacancies v2
          WHERE v2.vcode = h.vcode
            AND v2.deleted_at IS NULL
          ORDER BY v2.created_at DESC
          LIMIT 1
        )
      )
    WHERE
      h.deleted_at IS NULL
      AND h.hr_status IN ('Pending', 'Complete')
      AND (h.employee_no IS NULL OR h.employee_no = '')
      AND COALESCE(v.is_pool_vacancy, FALSE) = FALSE
      AND COALESCE(v.affects_required_hc, TRUE) = TRUE
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR h.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = h.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = h.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = h.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  hr_pipeline AS (
    SELECT count(*)::bigint AS pipeline_count
    FROM hr_pipeline_all hp
    WHERE (p_account_id IS NULL OR hp.account_id = p_account_id)
      AND (p_group_id IS NULL OR hp.group_id = p_group_id)
  ),
  -- Slot-based vacant capacity (stationary + roving plantilla_slots + open coverage_slots),
  -- excluding pool vacancies and any slot already counted in hr_pipeline_all.
  roving_slot_totals AS (
    SELECT
      ps2.source_hc_request_id,
      ps2.slot_ordinal,
      count(*) AS total_slots
    FROM public.plantilla_slots ps2
    WHERE ps2.is_roving = TRUE
      AND ps2.source_hc_request_id IS NOT NULL
      AND ps2.slot_status <> 'closed'
      AND ps2.closed_at IS NULL
    GROUP BY ps2.source_hc_request_id, ps2.slot_ordinal
  ),
  vacant_plantilla_slots_scoped AS (
    SELECT
      v.account_id,
      a.group_id,
      COALESCE(ps.store_id, v.store_id) AS store_id,
      CASE
        WHEN ps.is_roving = TRUE THEN COALESCE(1.0 / NULLIF(rst.total_slots, 0)::numeric, 0::numeric)
        ELSE 1.0::numeric
      END AS slot_hc
    FROM public.plantilla_slots ps
    JOIN public.vacancies v
      ON v.vcode = ps.legacy_vcode
     AND v.deleted_at IS NULL
     AND COALESCE(v.is_archived, FALSE) = FALSE
     AND COALESCE(v.is_pool_vacancy, FALSE) = FALSE
     AND COALESCE(v.affects_required_hc, TRUE) = TRUE
    LEFT JOIN public.accounts a ON a.id = v.account_id
    LEFT JOIN roving_slot_totals rst
      ON ps.is_roving = TRUE
     AND rst.source_hc_request_id = ps.source_hc_request_id
     AND rst.slot_ordinal = ps.slot_ordinal
    WHERE
      ps.closed_at IS NULL
      AND ps.slot_status IN ('open', 'pipeline')
      AND NOT EXISTS (
        SELECT 1 FROM hr_pipeline_all hp WHERE hp.slot_id = ps.id
      )
      AND (
        ps.is_roving = TRUE
        OR COALESCE(ps.store_id, v.store_id) IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM public.coverage_group_stores cgs
          JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
          WHERE cgs.store_id = COALESCE(ps.store_id, v.store_id)
            AND cgs.archived_at IS NULL
            AND cg.archived_at IS NULL
        )
      )
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR v.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = v.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = v.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = v.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = v.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  vacant_plantilla_slots_filtered AS (
    SELECT vs.*
    FROM vacant_plantilla_slots_scoped vs
    WHERE (p_account_id IS NULL OR vs.account_id = p_account_id)
      AND (p_group_id IS NULL OR vs.group_id = p_group_id)
  ),
  vacant_coverage_slots_filtered AS (
    SELECT
      cg.account_id,
      a.group_id,
      1.0::numeric AS slot_hc
    FROM public.coverage_slots cs
    JOIN public.coverage_groups cg
      ON cg.id = cs.coverage_group_id
     AND cg.archived_at IS NULL
    LEFT JOIN public.accounts a ON a.id = cg.account_id
    WHERE
      cs.slot_status = 'open'
      AND NOT EXISTS (
        SELECT 1 FROM hr_pipeline_all hp WHERE hp.coverage_slot_id = cs.id
      )
      AND (p_account_id IS NULL OR cg.account_id = p_account_id)
      AND (p_group_id IS NULL OR a.group_id = p_group_id)
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR a.account_name = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = cg.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = cg.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = cg.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = cg.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  store_staffing AS (
    SELECT
      sk.store_id,
      COALESCE((SELECT count(*) FROM plantilla_filtered pf WHERE pf.store_id = sk.store_id AND pf.status = 'Active'), 0) AS onboard_count,
      COALESCE((SELECT round(sum(vf.slot_hc)) FROM vacant_plantilla_slots_filtered vf WHERE vf.store_id = sk.store_id), 0) AS open_headcount
    FROM (
      SELECT store_id FROM plantilla_filtered WHERE store_id IS NOT NULL
      UNION
      SELECT store_id FROM vacant_plantilla_slots_filtered WHERE store_id IS NOT NULL
    ) sk
  )
  SELECT
    count(*) FILTER (WHERE pf.status = 'Active')::bigint AS active_employees,
    count(*) FILTER (WHERE pf.status <> 'Active')::bigint AS inactive_employees,
    count(*) FILTER (WHERE pf.status = 'Active' AND (COALESCE(pf.deployment_type, '') = 'Roving' OR pf.roving_assignment_id IS NOT NULL))::bigint AS roving_count,
    count(*) FILTER (WHERE pf.status = 'Active' AND NOT (COALESCE(pf.deployment_type, '') = 'Roving' OR pf.roving_assignment_id IS NOT NULL))::bigint AS stationary_count,
    (SELECT pipeline_count FROM hr_pipeline) AS onboarding_pipeline_count,
    count(*) FILTER (WHERE pf.status IN ('Pending Deactivation', 'For Deactivation'))::bigint AS pending_deactivation_count,
    (
      SELECT count(*)::bigint
      FROM store_staffing ss
      WHERE (ss.onboard_count + ss.open_headcount) > 0
        AND ss.onboard_count::numeric / (ss.onboard_count + ss.open_headcount)::numeric < 0.8
    ) AS staffing_risk_count,
    round(
      COALESCE((SELECT sum(vf.slot_hc) FROM vacant_plantilla_slots_filtered vf), 0)
      + COALESCE((SELECT sum(vc.slot_hc) FROM vacant_coverage_slots_filtered vc), 0)
    )::bigint AS open_headcount_count
  FROM plantilla_filtered pf;
END;
$function$;


-- =============================================================================
-- 1B-2. public.list_web_plantilla_store_staffing
-- =============================================================================
CREATE OR REPLACE FUNCTION public.list_web_plantilla_store_staffing(
  p_search      text DEFAULT NULL::text,
  p_account_id  uuid DEFAULT NULL::uuid,
  p_group_id    uuid DEFAULT NULL::uuid,
  p_risk_filter text DEFAULT NULL::text,
  p_limit       integer DEFAULT 50,
  p_offset      integer DEFAULT 0,
  p_sort_by     text DEFAULT 'store_name'::text,
  p_sort_dir    text DEFAULT 'asc'::text
)
RETURNS TABLE(
  store_id                   uuid,
  store_name                 text,
  account_id                 uuid,
  account_name               text,
  group_id                   uuid,
  group_name                 text,
  province_id                uuid,
  onboard_count              bigint,
  inactive_count             bigint,
  roving_count               bigint,
  stationary_count           bigint,
  pending_deactivation_count bigint,
  open_vacancy_count         bigint,
  open_headcount             bigint,
  required_headcount         bigint,
  fill_rate                  numeric,
  staffing_risk              text,
  row_capabilities           jsonb,
  total_count                bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_level integer;
  v_sort_by    text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'store_name'));
  v_sort_dir   text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'asc'));
  v_limit      integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset     integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla staffing requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_level
  INTO v_profile_id, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web plantilla staffing caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'store_name', 'account_name', 'group_name', 'onboard_count',
    'open_headcount', 'required_headcount', 'fill_rate'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH plantilla_scoped AS (
    SELECT
      p.store_id,
      p.store_name,
      p.account_id,
      p.account,
      p.province_id,
      p.status,
      p.separation_status,
      p.date_of_separation,
      p.deactivated_at,
      p.deployment_type,
      p.roving_assignment_id,
      (
        p.deactivated_at IS NULL
        AND p.date_of_separation IS NULL
        AND lower(coalesce(nullif(btrim(p.status), ''), 'active')) NOT IN (
          'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
        )
        AND lower(coalesce(nullif(btrim(p.separation_status), ''), '')) NOT IN (
          'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
        )
      ) AS is_onboard
    FROM public.v_plantilla_safe p
    WHERE
      p.source_headcount_request_id IS NULL
      AND p.store_id IS NOT NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = p.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = p.account_id
          WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  hr_pipeline_slots AS (
    SELECT h.slot_id
    FROM public.hr_emploc h
    LEFT JOIN public.vacancies v
      ON v.id = COALESCE(
        h.vacancy_id,
        (
          SELECT v2.id
          FROM public.vacancies v2
          WHERE v2.vcode = h.vcode
            AND v2.deleted_at IS NULL
          ORDER BY v2.created_at DESC
          LIMIT 1
        )
      )
    WHERE h.deleted_at IS NULL
      AND h.hr_status IN ('Pending', 'Complete')
      AND (h.employee_no IS NULL OR h.employee_no = '')
      AND COALESCE(v.is_pool_vacancy, FALSE) = FALSE
      AND COALESCE(v.affects_required_hc, TRUE) = TRUE
      AND h.slot_id IS NOT NULL
  ),
  roving_slot_totals AS (
    SELECT
      ps2.source_hc_request_id,
      ps2.slot_ordinal,
      count(*) AS total_slots
    FROM public.plantilla_slots ps2
    WHERE ps2.is_roving = TRUE
      AND ps2.source_hc_request_id IS NOT NULL
      AND ps2.slot_status <> 'closed'
      AND ps2.closed_at IS NULL
    GROUP BY ps2.source_hc_request_id, ps2.slot_ordinal
  ),
  vacancies_scoped AS (
    SELECT
      COALESCE(ps.store_id, v.store_id) AS store_id,
      v.store_name,
      v.account_id,
      v.account,
      v.province_id,
      v.vcode,
      CASE
        WHEN ps.is_roving = TRUE THEN COALESCE(1.0 / NULLIF(rst.total_slots, 0)::numeric, 0::numeric)
        ELSE 1.0::numeric
      END AS slot_hc
    FROM public.plantilla_slots ps
    JOIN public.vacancies v
      ON v.vcode = ps.legacy_vcode
     AND v.deleted_at IS NULL
     AND COALESCE(v.is_archived, FALSE) = FALSE
     AND COALESCE(v.is_pool_vacancy, FALSE) = FALSE
     AND COALESCE(v.affects_required_hc, TRUE) = TRUE
    LEFT JOIN roving_slot_totals rst
      ON ps.is_roving = TRUE
     AND rst.source_hc_request_id = ps.source_hc_request_id
     AND rst.slot_ordinal = ps.slot_ordinal
    WHERE
      ps.closed_at IS NULL
      AND ps.slot_status IN ('open', 'pipeline')
      AND COALESCE(ps.store_id, v.store_id) IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM hr_pipeline_slots hps WHERE hps.slot_id = ps.id
      )
      AND (
        ps.is_roving = TRUE
        OR NOT EXISTS (
          SELECT 1
          FROM public.coverage_group_stores cgs
          JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
          WHERE cgs.store_id = COALESCE(ps.store_id, v.store_id)
            AND cgs.archived_at IS NULL
            AND cg.archived_at IS NULL
        )
      )
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR v.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = v.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = v.account_id
          WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = v.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fb.account_id = v.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  store_keys AS (
    SELECT
      u.store_id,
      max(u.store_name)                                                    AS store_name,
      (array_agg(u.account_id ORDER BY u.account_id::text) FILTER (WHERE u.account_id IS NOT NULL))[1] AS account_id,
      max(u.account)                                                       AS account_name,
      (array_agg(u.province_id ORDER BY u.province_id::text) FILTER (WHERE u.province_id IS NOT NULL))[1] AS province_id
    FROM (
      SELECT ps.store_id, ps.store_name, ps.account_id, ps.account, ps.province_id
      FROM plantilla_scoped ps
      UNION ALL
      SELECT vs.store_id, vs.store_name, vs.account_id, vs.account, vs.province_id
      FROM vacancies_scoped vs
    ) u
    GROUP BY u.store_id
  ),
  p_agg AS (
    SELECT
      ps.store_id,
      count(*) FILTER (WHERE ps.is_onboard)                                                                           AS onboard_count,
      count(*) FILTER (WHERE NOT ps.is_onboard)                                                                       AS inactive_count,
      count(*) FILTER (WHERE ps.is_onboard AND (COALESCE(ps.deployment_type, '') = 'Roving' OR ps.roving_assignment_id IS NOT NULL)) AS roving_count,
      count(*) FILTER (WHERE ps.is_onboard AND NOT (COALESCE(ps.deployment_type, '') = 'Roving' OR ps.roving_assignment_id IS NOT NULL)) AS stationary_count,
      count(*) FILTER (WHERE ps.status IN ('Pending Deactivation', 'For Deactivation'))                               AS pending_deactivation_count
    FROM plantilla_scoped ps
    GROUP BY ps.store_id
  ),
  v_agg AS (
    SELECT
      vs.store_id,
      count(DISTINCT vs.vcode)              AS open_vacancy_count,
      COALESCE(round(sum(vs.slot_hc)), 0)   AS open_headcount
    FROM vacancies_scoped vs
    GROUP BY vs.store_id
  ),
  combined AS (
    SELECT
      sk.store_id,
      sk.store_name,
      sk.account_id,
      sk.account_name,
      a.group_id,
      g.group_name,
      sk.province_id,
      COALESCE(pa.onboard_count, 0)::bigint              AS onboard_count,
      COALESCE(pa.inactive_count, 0)::bigint             AS inactive_count,
      COALESCE(pa.roving_count, 0)::bigint               AS roving_count,
      COALESCE(pa.stationary_count, 0)::bigint           AS stationary_count,
      COALESCE(pa.pending_deactivation_count, 0)::bigint AS pending_deactivation_count,
      COALESCE(va.open_vacancy_count, 0)::bigint         AS open_vacancy_count,
      COALESCE(va.open_headcount, 0)::bigint             AS open_headcount,
      (COALESCE(pa.onboard_count, 0) + COALESCE(va.open_headcount, 0))::bigint AS required_headcount
    FROM store_keys sk
    LEFT JOIN p_agg pa ON pa.store_id = sk.store_id
    LEFT JOIN v_agg va ON va.store_id = sk.store_id
    LEFT JOIN public.accounts a ON a.id = sk.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
  ),
  risk_scored AS (
    SELECT
      c.*,
      CASE WHEN c.required_headcount = 0 THEN NULL
           ELSE round(c.onboard_count::numeric / c.required_headcount::numeric, 4)
      END AS fill_rate,
      CASE
        WHEN c.required_headcount = 0 THEN 'none'
        WHEN c.onboard_count::numeric / c.required_headcount::numeric < 0.5 THEN 'critical'
        WHEN c.onboard_count::numeric / c.required_headcount::numeric < 0.8 THEN 'warning'
        ELSE 'healthy'
      END AS staffing_risk
    FROM combined c
  ),
  filtered AS (
    SELECT r.*
    FROM risk_scored r
    WHERE
      (p_account_id IS NULL OR r.account_id = p_account_id)
      AND (p_group_id IS NULL OR r.group_id = p_group_id)
      AND (
        p_risk_filter IS NULL
        OR r.staffing_risk = lower(p_risk_filter)
        OR (lower(p_risk_filter) = 'at_risk' AND r.staffing_risk IN ('critical', 'warning'))
      )
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR r.store_name ILIKE '%' || btrim(p_search) || '%'
        OR r.account_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.store_id, c.store_name, c.account_id, c.account_name, c.group_id, c.group_name,
    c.province_id, c.onboard_count, c.inactive_count, c.roving_count, c.stationary_count,
    c.pending_deactivation_count, c.open_vacancy_count, c.open_headcount, c.required_headcount,
    c.fill_rate, c.staffing_risk,
    jsonb_build_object(
      'can_view_store_roster', TRUE,
      'is_at_risk', (c.staffing_risk IN ('critical', 'warning')),
      'has_open_headcount', (c.open_headcount > 0)
    ) AS row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'         THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'         THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'       THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'       THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'         THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'         THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'onboard_count'      THEN c.onboard_count END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'onboard_count'      THEN c.onboard_count END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'open_headcount'     THEN c.open_headcount END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'open_headcount'     THEN c.open_headcount END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'required_headcount' THEN c.required_headcount END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'required_headcount' THEN c.required_headcount END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'fill_rate'          THEN c.fill_rate END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'fill_rate'          THEN c.fill_rate END DESC NULLS LAST,
    c.store_name ASC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

COMMIT;
