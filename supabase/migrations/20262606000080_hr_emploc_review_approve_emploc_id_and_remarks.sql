-- Migration: 20262606000080_hr_emploc_review_approve_emploc_id_and_remarks.sql
-- Prompt ID: ohm#7k4w9xqn
-- Purpose:
--   1. Create internal core function _assign_hr_emploc_number_core (no role gate, private execution)
--      reusing the validation and assignment logic of assign_hr_emploc_number.
--   2. Update review_web_hr_emploc_correction to accept p_employee_no, delegating to the core
--      function on approve, keeping role gate (i_am_hr_dept() OR i_have_full_access()).
--   3. Add 'ops_remarks', h.ops_remarks to row_capabilities in list_web_hr_emplocs.

-- ====================================================================
-- SECTION 1: Internal Core Function for Emploc ID Assignment
-- ====================================================================

CREATE OR REPLACE FUNCTION public._assign_hr_emploc_number_core(
  p_id          uuid,
  p_employee_no text
)
RETURNS public.hr_emploc
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_old   public.hr_emploc;
  v_new   public.hr_emploc;
  v_clean text := nullif(btrim(p_employee_no), '');
BEGIN
  -- 1. Empty check (22023)
  IF v_clean IS NULL THEN
    RAISE EXCEPTION 'employee_no is required' USING ERRCODE = '22023';
  END IF;

  -- 2. Lock record & not found / archived check (P0002)
  SELECT * INTO v_old FROM public.hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;

  -- 3. Pending deletion lock (P0001)
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  -- 4. Duplicate in active hr_emploc check (23505)
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc
    WHERE employee_no = v_clean AND id <> p_id
      AND deleted_at IS NULL
      AND status NOT IN ('Backout', 'Moved to Plantilla')
  ) THEN
    RAISE EXCEPTION 'employee_no % already in use on active hr_emploc', v_clean USING ERRCODE = '23505';
  END IF;

  -- 5. Duplicate in active plantilla check (23505)
  IF EXISTS (
    SELECT 1 FROM public.plantilla
    WHERE employee_no = v_clean
      AND is_deleted = false
      AND status IN ('Active', 'For Deactivation', 'On Leave')
  ) THEN
    RAISE EXCEPTION 'employee_no % already exists in active plantilla', v_clean USING ERRCODE = '23505';
  END IF;

  -- 6. Canonical state update
  UPDATE public.hr_emploc
  SET employee_no            = v_clean,
      emploc_no              = v_clean,
      hr_status              = 'Complete',
      status                 = 'Ready for Plantilla',
      hr_reviewed_at         = now(),
      hr_reviewed_by         = public.get_my_full_name(),
      hr_reviewed_by_user_id = public.get_my_profile_id(),
      updated_at             = now(),
      updated_by             = public.get_my_profile_id()
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM public.log_audit_event('hr_emploc', 'UPDATE', p_id, to_jsonb(v_old), to_jsonb(v_new));
  RETURN v_new;
END;
$$;

-- Security: Internal core function — zero external access
REVOKE ALL ON FUNCTION public._assign_hr_emploc_number_core(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._assign_hr_emploc_number_core(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public._assign_hr_emploc_number_core(uuid, text) FROM authenticated;

-- ====================================================================
-- SECTION 2: Update review_web_hr_emploc_correction (5-arg signature)
-- ====================================================================

DROP FUNCTION IF EXISTS public.review_web_hr_emploc_correction(uuid, text, jsonb, text);

CREATE OR REPLACE FUNCTION public.review_web_hr_emploc_correction(
  p_hr_emploc_id  uuid,
  p_decision      text,
  p_resolved_keys jsonb,
  p_remarks       text DEFAULT NULL::text,
  p_employee_no   text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid                   uuid    := auth.uid();
  v_profile_id                 uuid;
  v_role_level                 integer;
  v_old                        public.hr_emploc;
  v_new                        public.hr_emploc;
  v_existing_codes             text[];
  v_resolved_codes             text[];
  v_residual_codes             text[];
  v_residual_correction_reason jsonb;
BEGIN

  -- ----------------------------------------------------------------
  -- 1. Auth guard — fail closed, no session = no access
  -- ----------------------------------------------------------------
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: correction review requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 2. Profile resolution — active, non-archived profile + role level
  -- ----------------------------------------------------------------
  SELECT up.id, r.role_level
  INTO   v_profile_id, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active    = TRUE
    AND  up.archived_at  IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR COALESCE(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: caller profile is inactive or not found'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 3. RBAC capability guard
  --    Mirrors approve_correction_request: HR Dept (hrPersonnel) or
  --    full access (headAdmin / superAdmin). All other roles denied.
  -- ----------------------------------------------------------------
  IF NOT (public.i_am_hr_dept() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: HR Personnel or Admin role required for correction review'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 4. Decision validation
  -- ----------------------------------------------------------------
  IF p_decision NOT IN ('approve', 'return') THEN
    RAISE EXCEPTION 'invalid decision: must be ''approve'' or ''return'''
      USING ERRCODE = '22023';
  END IF;

  -- ----------------------------------------------------------------
  -- 5. Lock and fetch the record
  --    FOR UPDATE prevents concurrent state changes during validation.
  -- ----------------------------------------------------------------
  SELECT * INTO v_old
  FROM   public.hr_emploc
  WHERE  id = p_hr_emploc_id
  FOR    UPDATE;

  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'forbidden: hr_emploc record not found or archived'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 6. Scope gate — non-global callers (role_level < 90) must have
  --    an account/group assignment that covers the record's account.
  -- ----------------------------------------------------------------
  IF COALESCE(v_role_level, 0) < 90 THEN
    IF NOT (
      v_old.account = ANY (public.get_my_allowed_accounts())
      OR EXISTS (
        SELECT 1 FROM public.user_scopes us
        WHERE  us.user_id    = v_profile_id
          AND  us.account_id = v_old.account_id
      )
      OR EXISTS (
        SELECT 1
        FROM   public.user_scopes us
        JOIN   public.accounts   ac ON ac.id = v_old.account_id
        WHERE  us.user_id    = v_profile_id
          AND  us.account_id IS NULL
          AND  us.group_id   = ac.group_id
      )
      OR EXISTS (
        SELECT 1
        FROM   public.users_profile up_f
        JOIN   public.accounts      ac ON ac.id = v_old.account_id
        WHERE  up_f.id = v_profile_id
          AND  NOT EXISTS (
            SELECT 1 FROM public.user_scopes us_any
            WHERE  us_any.user_id = v_profile_id
              AND  (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
          )
          AND  (up_f.account_id = v_old.account_id OR up_f.group_id = ac.group_id)
      )
    ) THEN
      RAISE EXCEPTION 'forbidden: hr_emploc record is outside your assigned scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ----------------------------------------------------------------
  -- 7. Terminal state guard
  -- ----------------------------------------------------------------
  IF v_old.moved_to_plantilla_at IS NOT NULL
     OR v_old.status    = 'Moved to Plantilla'
     OR v_old.hr_status = 'Transferred'
  THEN
    RAISE EXCEPTION 'action not allowed: employee has already been moved to Plantilla'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 8. Pending deletion lock
  -- ----------------------------------------------------------------
  IF EXISTS (
    SELECT 1
    FROM   public.hr_emploc_deletion_requests
    WHERE  hr_emploc_id = p_hr_emploc_id
      AND  status       = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 9. hr_status guard — must be in For Review
  -- ----------------------------------------------------------------
  IF v_old.hr_status <> 'For Review' THEN
    RAISE EXCEPTION 'action not allowed: hr_status is "%" — expected "For Review"',
      v_old.hr_status
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 10. status guard — must be Pending Emploc
  -- ----------------------------------------------------------------
  IF v_old.status <> 'Pending Emploc' THEN
    RAISE EXCEPTION 'action not allowed: status is "%" — expected "Pending Emploc"',
      v_old.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 11. Compute existing, resolved, and residual correction codes
  -- ----------------------------------------------------------------
  SELECT COALESCE(array_agg(elem->>'code'), '{}')
  INTO   v_existing_codes
  FROM   jsonb_array_elements(
           CASE WHEN jsonb_typeof(v_old.correction_reason) = 'array'
                THEN v_old.correction_reason
                ELSE '[]'::jsonb
           END
         ) elem
  WHERE  NULLIF(elem->>'code', '') IS NOT NULL;

  SELECT COALESCE(array_agg(v), '{}')
  INTO   v_resolved_codes
  FROM   jsonb_array_elements_text(COALESCE(p_resolved_keys, '[]'::jsonb)) v;

  SELECT COALESCE(array_agg(c), '{}')
  INTO   v_residual_codes
  FROM   unnest(v_existing_codes) c
  WHERE  NOT (c = ANY(v_resolved_codes));

  -- ----------------------------------------------------------------
  -- 12a. APPROVE path
  -- ----------------------------------------------------------------
  IF p_decision = 'approve' THEN

    -- All existing correction codes must appear in p_resolved_keys.
    IF COALESCE(array_length(v_residual_codes, 1), 0) > 0 THEN
      RAISE EXCEPTION
        'approve requires all existing correction keys to be resolved; % unresolved key(s) remain: %',
        COALESCE(array_length(v_residual_codes, 1), 0),
        array_to_string(v_residual_codes, ', ')
        USING ERRCODE = 'P0001';
    END IF;

    -- Update correction_reason to NULL and record optional approval remarks
    UPDATE public.hr_emploc
    SET    correction_reason = NULL,
           hr_remarks        = COALESCE(
                                 NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
                                 hr_remarks
                               )
    WHERE  id = p_hr_emploc_id;

    -- Delegate validation and assignment to internal core function
    v_new := public._assign_hr_emploc_number_core(p_hr_emploc_id, p_employee_no);

    RETURN jsonb_build_object(
      'status',        'ok',
      'hr_emploc_id',  v_new.id,
      'decision',      'approve',
      'hr_status',     v_new.hr_status,
      'employee_no',   v_new.employee_no,
      'resolved_keys', to_jsonb(v_resolved_codes),
      'residual_keys', to_jsonb(ARRAY[]::text[]),
      'reviewed_by',   public.get_my_full_name(),
      'reviewed_at',   now()
    );

  END IF;

  -- ----------------------------------------------------------------
  -- 12b. RETURN path
  -- ----------------------------------------------------------------

  -- Require at least one residual key or a non-empty remark.
  IF COALESCE(array_length(v_residual_codes, 1), 0) = 0
     AND NULLIF(BTRIM(COALESCE(p_remarks, '')), '') IS NULL
  THEN
    RAISE EXCEPTION
      'return requires at least one unresolved correction key or a non-empty remark'
      USING ERRCODE = '22023';
  END IF;

  -- Build residual correction_reason: keep only items whose code is unresolved.
  IF COALESCE(array_length(v_residual_codes, 1), 0) > 0 THEN
    SELECT jsonb_agg(elem)
    INTO   v_residual_correction_reason
    FROM   jsonb_array_elements(
             CASE WHEN jsonb_typeof(v_old.correction_reason) = 'array'
                  THEN v_old.correction_reason
                  ELSE '[]'::jsonb
             END
           ) elem
    WHERE  elem->>'code' = ANY(v_residual_codes);
  ELSE
    -- All codes resolved but remark present: correction reason is cleared.
    v_residual_correction_reason := NULL;
  END IF;

  UPDATE public.hr_emploc
  SET    hr_status         = 'For Correction',
         correction_reason = v_residual_correction_reason,
         hr_remarks        = COALESCE(
                               NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
                               hr_remarks
                             ),
         hr_reviewed_by    = public.get_my_full_name(),
         hr_reviewed_at    = now(),
         updated_at        = now(),
         updated_by        = v_profile_id
  WHERE  id = p_hr_emploc_id
  RETURNING * INTO v_new;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  RETURN jsonb_build_object(
    'status',        'ok',
    'hr_emploc_id',  v_new.id,
    'decision',      'return',
    'hr_status',     v_new.hr_status,
    'resolved_keys', to_jsonb(v_resolved_codes),
    'residual_keys', to_jsonb(v_residual_codes),
    'reviewed_by',   public.get_my_full_name(),
    'reviewed_at',   now()
  );

END;
$$;

REVOKE ALL    ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text, text) FROM PUBLIC;
REVOKE ALL    ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text, text) TO authenticated;

-- ====================================================================
-- SECTION 3: Update list_web_hr_emplocs to expose ops_remarks
-- ====================================================================

DROP FUNCTION IF EXISTS public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text);
DROP FUNCTION IF EXISTS public.list_web_hr_emplocs;
CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(p_queue text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_deficiency text DEFAULT NULL::text, p_sla_filter text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_sort_by text DEFAULT 'date_requested'::text, p_sort_dir text DEFAULT 'desc'::text)
 RETURNS TABLE(hr_emploc_id uuid, applicant_name text, vcode text, account_id uuid, account_name text, group_id uuid, group_name text, store_id uuid, store_name text, position_title text, hr_status text, status text, emploc_no text, employee_no text, date_requested timestamp with time zone, created_at timestamp with time zone, hired_date date, assignment_type text, roving_assignment_id uuid, aging_days integer, sla_breached boolean, sla_status text, sla_deadline timestamp with time zone, deficiency_summary jsonb, is_pending_deletion boolean, row_capabilities jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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
        'remarks', COALESCE(h.ops_remarks, h.hr_remarks),
        'ops_remarks', h.ops_remarks,
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
$function$;

REVOKE ALL    ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) FROM PUBLIC;
REVOKE ALL    ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.list_web_hr_emplocs(text, text, text, text, uuid, uuid, text, integer, integer, text, text) TO authenticated;
