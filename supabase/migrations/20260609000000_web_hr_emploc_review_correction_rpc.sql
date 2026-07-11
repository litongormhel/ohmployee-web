-- Migration: 20260609000000_web_hr_emploc_review_correction_rpc.sql
-- Ticket: OHM2026_1111 — Web HR Emploc correction review mutation RPC
--
-- Purpose:
--   Mutation contract for the OHMployee Web Dashboard to review a submitted
--   HR Emploc correction. Transitions hr_status from 'For Review' to either
--   'Complete' (approve) or 'For Correction' (return), based on p_decision.
--   Uses p_resolved_keys to track which correction codes have been addressed.
--
-- Security invariants:
--   - Caller identity derived strictly from auth.uid(). No parameter injection.
--   - RBAC: HR Personnel (hrPersonnel) and Admin roles (headAdmin, superAdmin) only.
--   - Scope-gated: non-global callers must be within their assigned accounts/groups.
--   - Fail closed: unauthenticated, inactive, unauthorized, or out-of-scope callers
--     raise SQLSTATE 42501 with no information disclosure.
--   - Terminal guard: blocks records already moved to Plantilla.
--   - Pending deletion lock: raises P0001 if a pending deletion request exists.
--   - State guard: requires hr_status = 'For Review' AND status = 'Pending Emploc'.
--   - No PII emitted in error messages.
--   - Execution granted to authenticated only. PUBLIC and anon are revoked.
--
-- Decision rules:
--   approve: p_resolved_keys must cover all existing correction codes.
--            Sets hr_status = 'Complete'. Clears correction_reason. No employee number.
--   return:  Requires residual/unresolved codes OR non-empty p_remarks.
--            Sets hr_status = 'For Correction'. Keeps residual correction reason.
--
-- Does NOT implement:
--   - Employee number assignment
--   - Plantilla movement
--   - Correction upload / submission
--   - Frontend code

DROP FUNCTION IF EXISTS public.review_web_hr_emploc_correction(uuid, text, jsonb, text);

CREATE OR REPLACE FUNCTION public.review_web_hr_emploc_correction(
  p_hr_emploc_id  uuid,
  p_decision      text,
  p_resolved_keys jsonb,
  p_remarks       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
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
  --    Identical pattern to tag_web_hr_emploc_deficiency and the
  --    read RPCs for consistency.
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
  --    Records already moved to Plantilla must never be modified.
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
  --    Mirrors tag_web_hr_emploc_deficiency and existing correction RPCs.
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
  --     correction_reason is a JSONB array of {code, comment} objects
  --     (Web format set by tag_web_hr_emploc_deficiency).
  --     Old-format objects (non-array) yield no extractable codes.
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

    UPDATE public.hr_emploc
    SET    hr_status         = 'Complete',
           correction_reason = NULL,
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
      'decision',      'approve',
      'hr_status',     v_new.hr_status,
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

COMMENT ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text) IS
  'OHM2026_1111 — Web mutation contract for correction review on a single HR Emploc record. '
  'RBAC: HR Personnel (hrPersonnel) + Admin (headAdmin, superAdmin) only. '
  'Scope-gated. Blocks terminal (Moved to Plantilla), pending-deletion states. '
  'Guards: hr_status = ''For Review'', status = ''Pending Emploc''. '
  'approve: all correction keys must be resolved; sets hr_status = ''Complete''; clears correction_reason. '
  'return: requires residual keys or remark; sets hr_status = ''For Correction''; keeps residual correction_reason. '
  'Audit-safe via log_audit_event. Returns JSONB envelope '
  '{status, hr_emploc_id, decision, hr_status, resolved_keys, residual_keys, reviewed_by, reviewed_at}.';

REVOKE ALL    ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text) FROM PUBLIC;
REVOKE ALL    ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text) TO authenticated;
