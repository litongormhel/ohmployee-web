-- ============================================================
-- OHMployee — Migration: Relax Applicant Status Transition Rules
-- Prompt ID : OHM2026_2025
-- Date      : 2026-05-21
-- ============================================================
-- ROOT CAUSE:
--   fn_update_applicant_status (20260520700000) enforced a rigid
--   sequential transition map:
--     new → for_interview | rejected  (only)
--     for_interview → for_requirements | rejected
--     for_requirements → for_onboard | backout | rejected
--     for_onboard → transferred
--
--   This caused: invalid transition: "new" → "for_onboard" is not allowed
--
-- BUSINESS RULE (corrected):
--   From any active status the user may jump to any active or
--   manually-settable terminal status. The workflow is not forced
--   to be sequential.
--
-- CHANGES IN THIS MIGRATION (ALL ADDITIVE / REPLACE-OR-UPDATE ONLY):
--   1. applicant_status_options: mark did_not_report and
--      rejected_by_ops as is_system_only=true (set by ops RPCs,
--      not manual status updates).
--   2. applicant_status_options: ensure failed is is_system_only=false
--      and is_terminal=true (valid manual terminal).
--   3. fn_update_applicant_status: replace static c_transitions map
--      with dynamic rule: from any active status, any non-system-only
--      is_active target is allowed. Terminal guard preserved.
--   4. fn_get_applicant_status_options: add p_exclude_system_only
--      parameter (default false, backward compatible) so the
--      status-update dialog can request only manually editable options.
--
-- NO CHANGES TO:
--   - Open/Pipeline classification logic
--   - fn_is_active_vacancy_applicant_status
--   - fn_check_vcode_applicant_slot (slot availability / Add Applicant guard)
--   - uq_applicants_one_active_per_vcode (terminal statuses remain excluded)
--   - confirm_applicant_onboard / endorse_applicant_to_ops
--   - Existing RPC contracts for vacancy module
--   - RLS policies
-- ============================================================

-- ============================================================
-- §1  FIX SYSTEM-ONLY FLAGS ON LEGACY STATUS OPTIONS
-- ============================================================

-- did_not_report and rejected_by_ops are written exclusively by
-- ops-workflow RPCs (confirm_applicant_onboard, rejected_by_ops path).
-- They must never appear in the manual status-update dropdown.
UPDATE public.applicant_status_options
SET    is_system_only = true,
       updated_at     = now()
WHERE  status_code IN ('did_not_report', 'rejected_by_ops')
  AND  is_system_only = false;   -- idempotent: only applies if not already set

-- failed is a valid manual terminal status (documented as legacy but
-- allowed for manual closure). Ensure correct flags.
UPDATE public.applicant_status_options
SET    is_system_only = false,
       is_terminal    = true,
       updated_at     = now()
WHERE  status_code = 'failed'
  AND  (is_system_only = true OR is_terminal = false);   -- idempotent

-- ============================================================
-- §2  PATCH fn_get_applicant_status_options
--     Adds p_exclude_system_only (default false, backward-compatible).
--     When true, returns only non-system-only statuses — the exact
--     set valid for the manual status-update dialog:
--       New, For Interview, For Requirements, For Onboard,
--       Backout, Rejected, Failed
--     Excluded when p_exclude_system_only = true:
--       Transferred, Endorsed to Ops, Confirmed Onboard,
--       Did Not Report, Rejected by Ops
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_get_applicant_status_options(
  p_include_inactive    boolean DEFAULT false,
  p_exclude_system_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'status_code',     s.status_code,
        'label',           s.label,
        'is_terminal',     s.is_terminal,
        'allow_on_create', s.allow_on_create,
        'is_system_only',  s.is_system_only,
        'color_key',       s.color_key,
        'sort_order',      s.sort_order,
        'is_active',       s.is_active
      ) ORDER BY s.sort_order
    ), '[]'::jsonb)
    FROM public.applicant_status_options s
    WHERE (p_include_inactive OR s.is_active = true)
      AND (NOT p_exclude_system_only OR s.is_system_only = false)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_applicant_status_options(boolean, boolean)
  TO authenticated, service_role;

-- ============================================================
-- §3  PATCH fn_update_applicant_status
--     Replaces the static sequential c_transitions map with a
--     dynamic rule: from any active (non-terminal) status, any
--     non-system-only, is_active target is permitted.
--
--     PRESERVED UNCHANGED:
--       - RBAC minimum level check
--       - p_reason_type validation
--       - target status resolution (must exist in status_options)
--       - system-only block (only Super Admin can set system-only status)
--       - terminal source guard (only Super Admin can move FROM terminal)
--       - scope check
--       - applicants.status UPDATE (writes label)
--       - applicant_status_history INSERT
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_update_applicant_status(
  p_applicant_id uuid,
  p_new_status   text,        -- status_code from applicant_status_options
  p_remarks      text DEFAULT NULL,
  p_reason_id    uuid DEFAULT NULL,    -- FK to backout_reasons or rejected_reasons
  p_reason_type  text DEFAULT NULL     -- 'backout' | 'rejected' | 'other'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level      int  := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_app        public.applicants%ROWTYPE;
  v_to_opt     public.applicant_status_options%ROWTYPE;
  v_from_code  text;
  v_old_status text;
  v_from_terminal boolean;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────
  IF v_level = 0 THEN
    RAISE EXCEPTION 'forbidden: authenticated user with a recognized role required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Validate reason_type ─────────────────────────────────────
  IF p_reason_type IS NOT NULL
     AND p_reason_type NOT IN ('backout', 'rejected', 'other') THEN
    RAISE EXCEPTION 'invalid reason_type: %. Must be backout | rejected | other', p_reason_type
      USING ERRCODE = '22023';
  END IF;

  -- ── Resolve target status option ─────────────────────────────
  SELECT * INTO v_to_opt
    FROM public.applicant_status_options
   WHERE status_code = p_new_status
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid or inactive status_code: %', p_new_status
      USING ERRCODE = '22023';
  END IF;

  -- ── Block system-only targets for non-Super Admin ────────────
  IF v_to_opt.is_system_only AND v_level != 100 THEN
    RAISE EXCEPTION 'status % is system-only and cannot be set manually', p_new_status
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock applicant ──────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  v_old_status := COALESCE(v_app.status, 'New');

  -- ── Resolve current status_code from stored label ────────────
  -- Falls back to 'new' for unknown/legacy labels (safe default).
  SELECT status_code INTO v_from_code
    FROM public.applicant_status_options
   WHERE label = v_old_status
  LIMIT 1;

  IF v_from_code IS NULL THEN
    v_from_code := 'new';
  END IF;

  -- ── Terminal source guard ─────────────────────────────────────
  -- Only Super Admin may transition FROM a terminal status.
  -- This preserves historical integrity while allowing override authority.
  SELECT is_terminal INTO v_from_terminal
    FROM public.applicant_status_options
   WHERE status_code = v_from_code;

  IF COALESCE(v_from_terminal, false) THEN
    IF v_level != 100 THEN
      RAISE EXCEPTION
        'cannot transition from terminal status "%" without Super Admin authority',
        v_old_status
        USING ERRCODE = '22023';
    END IF;
    -- Super Admin override — no further transition validation needed.
  ELSE
    -- ── RELAXED TRANSITION RULE ───────────────────────────────
    -- From any active (non-terminal) status, any non-system-only,
    -- active target is allowed. No sequential ordering enforced.
    --
    -- Effectively allowed targets for normal users:
    --   new, for_interview, for_requirements, for_onboard  (active)
    --   rejected, failed, backout                          (terminal, non-system)
    --
    -- Blocked by the system-only guard above:
    --   transferred, endorsed, confirmed_onboard,
    --   did_not_report, rejected_by_ops
    --
    -- The target has already been confirmed is_system_only=false
    -- and is_active=true by the guards above — nothing more needed.
    NULL;
  END IF;

  -- ── Scope check ───────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE v.vcode = v_app.vacancy_vcode
        AND v.account = ANY(public.get_my_allowed_accounts())
        AND v.deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: applicant is outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Apply status update ───────────────────────────────────────
  -- Writes the label value into applicants.status for DB consistency
  -- with existing legacy RPCs that also write label strings.
  UPDATE public.applicants
  SET
    status     = v_to_opt.label,
    updated_at = NOW(),
    updated_by = v_profile_id
  WHERE id = p_applicant_id;

  -- ── Write immutable status history ────────────────────────────
  INSERT INTO public.applicant_status_history (
    applicant_id,
    from_status,
    to_status,
    reason_id,
    reason_type,
    remarks,
    changed_by,
    changed_at,
    source_module
  ) VALUES (
    p_applicant_id,
    v_old_status,
    v_to_opt.label,
    p_reason_id,
    p_reason_type,
    p_remarks,
    v_profile_id,
    NOW(),
    'vacancy'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_update_applicant_status(uuid, text, text, uuid, text)
  TO authenticated;

-- ============================================================
-- §4  VALIDATION QUERIES
--     Run these in Supabase SQL Editor after applying migration.
--     All rely on existing seed data; no test applicant required
--     for the status-option checks.
-- ============================================================

-- V1: Confirm system-only flags are correct after patch
-- SELECT status_code, label, is_terminal, is_system_only
--   FROM public.applicant_status_options
--   ORDER BY sort_order;
--
-- Expected system-only=true:
--   transferred, endorsed, confirmed_onboard, did_not_report, rejected_by_ops
-- Expected is_system_only=false + is_terminal=true (manual terminal):
--   backout, rejected, failed
-- Expected is_system_only=false + is_terminal=false (active):
--   new, for_interview, for_requirements, for_onboard

-- V2: Confirm fn_get_applicant_status_options with p_exclude_system_only
-- SELECT jsonb_array_elements(
--   public.fn_get_applicant_status_options(false, true)
-- ) -> 'status_code';
--
-- Expected codes (7 rows):
--   new, for_interview, for_requirements, for_onboard, backout, rejected, failed
--
-- Must NOT include:
--   transferred, endorsed, confirmed_onboard, did_not_report, rejected_by_ops

-- V3: Transition validation — run against a real applicant in 'New' status
-- SELECT public.fn_update_applicant_status('<applicant_uuid>', 'for_onboard');
-- Expected: success (no exception)
--
-- SELECT public.fn_update_applicant_status('<applicant_uuid>', 'for_requirements');
-- Expected: success
--
-- SELECT public.fn_update_applicant_status('<applicant_uuid>', 'rejected');
-- Expected: success
--
-- SELECT public.fn_update_applicant_status('<applicant_uuid>', 'backout');
-- Expected: success
--
-- SELECT public.fn_update_applicant_status('<applicant_uuid>', 'failed');
-- Expected: success

-- V4: Terminal guard — from 'Rejected' status, non-Super Admin must fail
-- (Test with a rejected applicant; should raise 22023 for non-Super Admin)

-- V5: System-only guard — transferred must still be blocked for non-Super Admin
-- SELECT public.fn_update_applicant_status('<applicant_uuid>', 'transferred');
-- Expected: 42501 forbidden

-- V6: Active applicant occupancy — terminal status releases slot
-- After setting an applicant to 'rejected' or 'backout':
-- SELECT * FROM public.fn_check_vcode_applicant_slot('<vcode>');
-- Expected: is_slot_available = true

-- V7: Pipeline reclassification after terminal
-- SELECT pipeline_classification FROM public.v_vacancy_pipeline_status
--   WHERE vcode = '<vcode>';
-- Expected: 'Open' (if the only applicant moved to terminal status)

-- V8: Add Applicant allowed after terminal
-- The uq_applicants_one_active_per_vcode partial index only fires on
-- canonical active statuses. After rejection/backout the constraint
-- is released and a new applicant insert succeeds.
-- (Verified by fn_check_vcode_applicant_slot returning is_slot_available=true)
