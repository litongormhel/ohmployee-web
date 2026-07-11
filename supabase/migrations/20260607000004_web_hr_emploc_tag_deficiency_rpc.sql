-- Migration: 20260607000004_web_hr_emploc_tag_deficiency_rpc.sql
-- Ticket: OHM2026_1108 — Web HR Emploc deficiency tagging mutation RPC
--
-- Purpose:
--   Mutation contract for the OHMployee Web Dashboard to tag deficiencies
--   on a single HR Emploc record. Writes correction_reason (JSONB array of
--   issue codes), sets hr_status = 'For Correction', and emits an audit row.
--
-- Security invariants:
--   - Caller identity derived strictly from auth.uid(). No parameter injection.
--   - RBAC: HR Personnel (hrPersonnel) and Admin roles (headAdmin, superAdmin) only.
--   - Scope-gated: non-global callers must be within their assigned accounts/groups.
--   - Fail closed: unauthenticated, inactive, unauthorized, or out-of-scope callers
--     raise SQLSTATE 42501 with no information disclosure.
--   - Pending deletion lock: raises P0001 if a pending deletion request exists.
--   - State guard: blocks terminal records (moved to Plantilla) and Complete state.
--   - Deficiency codes validated against public.hr_emploc_issue_types (active only).
--   - No PII emitted in error messages.
--   - Execution granted to authenticated only. PUBLIC and anon are revoked.
--
-- Does NOT implement:
--   - Correction review / approval workflow
--   - Employee number assignment
--   - Frontend code

DROP FUNCTION IF EXISTS public.tag_web_hr_emploc_deficiency(uuid, jsonb, text);

CREATE OR REPLACE FUNCTION public.tag_web_hr_emploc_deficiency(
  p_hr_emploc_id uuid,
  p_deficiencies jsonb,
  p_remarks      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid      uuid    := auth.uid();
  v_profile_id    uuid;
  v_role_name     text;
  v_role_level    integer;
  v_old           public.hr_emploc;
  v_new           public.hr_emploc;
  v_issue         jsonb;
  v_code          text;
  v_comment       text;
  v_needs_comment boolean;
BEGIN

  -- ----------------------------------------------------------------
  -- 1. Auth guard — fail closed, no session = no access
  -- ----------------------------------------------------------------
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: deficiency tagging requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 2. Profile resolution — active, non-archived profile + role
  -- ----------------------------------------------------------------
  SELECT up.id, r.role_name, r.role_level
  INTO   v_profile_id, v_role_name, v_role_level
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
  --    Mirrors mark_for_correction: HR Dept (hrPersonnel) or full access
  --    (headAdmin / superAdmin). All other roles are denied.
  -- ----------------------------------------------------------------
  IF NOT (public.i_am_hr_dept() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: HR Personnel or Admin role required for deficiency tagging'
      USING ERRCODE = '42501';
  END IF;

  -- ----------------------------------------------------------------
  -- 4. Validate deficiencies input
  --    Must be a non-empty JSONB array of {code, comment} objects.
  --    Every code must exist and be active in hr_emploc_issue_types.
  --    Codes that require_comment must supply a non-empty comment.
  -- ----------------------------------------------------------------
  IF p_deficiencies IS NULL
     OR jsonb_typeof(p_deficiencies) <> 'array'
     OR jsonb_array_length(p_deficiencies) = 0
  THEN
    RAISE EXCEPTION 'p_deficiencies must be a non-empty JSONB array of {code, comment} objects'
      USING ERRCODE = '22023';
  END IF;

  FOR v_issue IN SELECT * FROM jsonb_array_elements(p_deficiencies) LOOP
    v_code    := NULLIF(BTRIM(COALESCE(v_issue->>'code',    '')), '');
    v_comment :=        BTRIM(COALESCE(v_issue->>'comment', ''));

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'each deficiency entry must include a non-empty code'
        USING ERRCODE = '22023';
    END IF;

    SELECT requires_comment
    INTO   v_needs_comment
    FROM   public.hr_emploc_issue_types
    WHERE  code      = v_code
      AND  is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'unknown or inactive deficiency code: %', v_code
        USING ERRCODE = '22023';
    END IF;

    IF v_needs_comment AND v_comment = '' THEN
      RAISE EXCEPTION 'comment is required for deficiency code: %', v_code
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

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
  --    Mirrors scoping logic from list_web_hr_emplocs and
  --    get_web_hr_emploc_detail for consistency.
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
     OR v_old.status = 'Moved to Plantilla'
  THEN
    RAISE EXCEPTION 'action not allowed: employee has already been moved to Plantilla'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 8. Pending deletion lock
  --    Mirrors trg_hr_emploc_pending_deletion_lock and the explicit
  --    guard in assign_hr_emploc_number / submit_hrco_correction_update.
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
  -- 9. Complete state guard
  --    Complete = employee number assigned and ready for Plantilla.
  --    Deficiency tagging on a Complete record is a logical conflict.
  -- ----------------------------------------------------------------
  IF v_old.hr_status = 'Complete' THEN
    RAISE EXCEPTION 'action not allowed: hr_emploc is already in Complete state (employee number assigned)'
      USING ERRCODE = 'P0001';
  END IF;

  -- ----------------------------------------------------------------
  -- 10. Apply deficiency tagging
  --     Mirrors mark_for_correction semantics:
  --       correction_reason ← p_deficiencies (JSONB array)
  --       hr_status         ← 'For Correction'
  --       status            ← 'For Compliance'
  --       hr_remarks        ← p_remarks if non-empty, else preserve existing
  --       audit fields      ← stamped
  -- ----------------------------------------------------------------
  UPDATE public.hr_emploc
  SET    correction_reason = p_deficiencies,
         hr_status         = 'For Correction',
         status            = 'For Compliance',
         hr_remarks        = COALESCE(
                               NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
                               hr_remarks
                             ),
         hr_reviewed_at    = now(),
         hr_reviewed_by    = public.get_my_full_name(),
         updated_at        = now(),
         updated_by        = v_profile_id
  WHERE  id = p_hr_emploc_id
  RETURNING * INTO v_new;

  -- ----------------------------------------------------------------
  -- 11. Audit trail via existing log_audit_event helper
  -- ----------------------------------------------------------------
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_old),
    to_jsonb(v_new)
  );

  -- ----------------------------------------------------------------
  -- 12. Return JSONB result envelope
  -- ----------------------------------------------------------------
  RETURN jsonb_build_object(
    'status',           'ok',
    'hr_emploc_id',     v_new.id,
    'hr_status',        v_new.hr_status,
    'deficiency_count', jsonb_array_length(p_deficiencies),
    'tagged_by',        public.get_my_full_name(),
    'tagged_at',        now()
  );

END;
$$;

COMMENT ON FUNCTION public.tag_web_hr_emploc_deficiency(uuid, jsonb, text) IS
  'OHM2026_1108 — Web mutation contract for deficiency tagging on a single HR Emploc record. '
  'Validates deficiency codes against hr_emploc_issue_types (active). '
  'RBAC: HR Personnel (hrPersonnel) + Admin (headAdmin, superAdmin) only. '
  'Scope-gated. Blocks terminal (Moved to Plantilla), pending-deletion, and Complete states. '
  'Sets hr_status = ''For Correction'', status = ''For Compliance''. '
  'Audit-safe via log_audit_event. Returns JSONB envelope {status, hr_emploc_id, hr_status, deficiency_count, tagged_by, tagged_at}.';

REVOKE ALL   ON FUNCTION public.tag_web_hr_emploc_deficiency(uuid, jsonb, text) FROM PUBLIC;
REVOKE ALL   ON FUNCTION public.tag_web_hr_emploc_deficiency(uuid, jsonb, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.tag_web_hr_emploc_deficiency(uuid, jsonb, text) TO authenticated;
