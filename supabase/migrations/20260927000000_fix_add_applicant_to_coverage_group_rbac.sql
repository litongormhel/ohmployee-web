-- ============================================================
-- OHM2026_0086C_FIX1 — Fix add_applicant_to_coverage_group RBAC
-- Migration: 20260927000000_fix_add_applicant_to_coverage_group_rbac.sql
--
-- Bug: The original RPC guard used only i_am_ops() (role_level 40-70),
--      blocking Super Admin (level 100), Head Admin (level 90), and
--      Recruitment (role-name-based) even though all three are authorised.
--
-- Fix: Replace the single i_am_ops() guard with the canonical three-way check:
--        i_am_ops() OR i_have_full_access() OR i_am_recruitment()
--
--   i_have_full_access() → Super Admin + Head Admin
--   i_am_ops()           → om / hrco / atl / tl (level 40-70)
--   i_am_recruitment()   → Recruitment / Recruitment Team
--
-- No other logic is changed:
--   - Account scope validation is preserved.
--   - Slot lifecycle is unchanged.
--   - Applicant duplicate guard is unchanged.
--   - Grants are unchanged (authenticated role).
-- ============================================================


-- ============================================================
-- §1  Patched add_applicant_to_coverage_group
-- ============================================================

CREATE OR REPLACE FUNCTION public.add_applicant_to_coverage_group(
  p_coverage_group_id  uuid,
  p_last_name          text,
  p_first_name         text,
  p_contact_number     text,
  p_middle_name        text    DEFAULT NULL,
  p_status             text    DEFAULT 'new',
  p_remarks            text    DEFAULT NULL,
  p_source_channel     text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor       uuid;
  v_grp         public.coverage_groups%ROWTYPE;
  v_status_opt  public.applicant_status_options%ROWTYPE;
  v_app_id      uuid;
  v_full_name   text;
  v_middle      text;
  v_bind_result jsonb;
BEGIN
  -- ── RBAC ─────────────────────────────────────────────────────────────────
  -- Allowed: Super Admin, Head Admin (i_have_full_access),
  --          Ops roles om/hrco/atl/tl (i_am_ops),
  --          Recruitment / Recruitment Team (i_am_recruitment).
  IF NOT (
    public.i_have_full_access()
    OR public.i_am_ops()
    OR public.i_am_recruitment()
  ) THEN
    RAISE EXCEPTION 'forbidden: insufficient role to add applicants to a coverage group'
      USING ERRCODE = '42501';
  END IF;

  v_actor := public.get_my_profile_id();

  -- ── Validate coverage group ───────────────────────────────────────────────
  SELECT * INTO v_grp
    FROM public.coverage_groups
   WHERE id = p_coverage_group_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_grp.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'coverage group % is archived', v_grp.coverage_code
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Scope check ───────────────────────────────────────────────────────────
  IF NOT public.i_have_full_access()
     AND NOT (v_grp.account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: coverage group account is outside your scope'
      USING ERRCODE = '42501';
  END IF;

  -- ── Validate status (must be allow_on_create) ─────────────────────────────
  SELECT * INTO v_status_opt
    FROM public.applicant_status_options
   WHERE status_code = p_status
     AND is_active   = true
     AND allow_on_create = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid or non-createable status_code: %', p_status
      USING ERRCODE = '22023';
  END IF;

  -- ── Open slot pre-check (friendly early error) ────────────────────────────
  -- fn_bind_applicant_to_coverage_group will also check, but doing it here
  -- gives a cleaner error before we even create the applicant row.
  IF NOT EXISTS (
    SELECT 1 FROM public.coverage_slots
     WHERE coverage_group_id = p_coverage_group_id
       AND slot_status = 'open'
     LIMIT 1
  ) THEN
    RAISE EXCEPTION
      'no_open_coverage_slot: % has no open slots. '
      'All required headcount is currently in pipeline or filled. '
      'Contact your Admin to increase required headcount before adding another applicant.',
      v_grp.coverage_code
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Duplicate identity guard ──────────────────────────────────────────────
  -- Blocks: same normalized identity active in a DIFFERENT coverage group
  --         or in a normal VCODE vacancy (not a CG applicant).
  -- Allows: same identity in the SAME coverage group (multi-HC scenario;
  --         uq_applicants_one_active_per_coverage_slot prevents slot double-booking).
  IF EXISTS (
    SELECT 1 FROM public.applicants a
     WHERE LOWER(TRIM(a.contact_number)) = LOWER(TRIM(p_contact_number))
       AND LOWER(TRIM(a.last_name))      = LOWER(TRIM(p_last_name))
       AND LOWER(TRIM(a.first_name))     = LOWER(TRIM(p_first_name))
       AND (
             p_middle_name IS NULL
             OR TRIM(COALESCE(p_middle_name, '')) = ''
             OR LOWER(TRIM(a.middle_name)) = LOWER(TRIM(p_middle_name))
           )
       AND public.fn_is_active_vacancy_applicant_status(a.status)
       AND COALESCE(a.is_archived, false) = false
       AND (
             -- Different coverage group
             (a.coverage_group_id IS NOT NULL
              AND a.coverage_group_id <> p_coverage_group_id)
             OR
             -- Normal VCODE vacancy applicant (not a CG-bound applicant)
             (a.coverage_slot_id IS NULL
              AND a.vacancy_vcode IS NOT NULL)
           )
  ) THEN
    RAISE EXCEPTION
      'duplicate_applicant_identity: An active applicant with the same name and '
      'contact number already exists in another vacancy or coverage group. '
      'Back out or archive the existing applicant record before adding a new one.'
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Build display fields ──────────────────────────────────────────────────
  v_middle    := NULLIF(TRIM(COALESCE(p_middle_name, '')), '');
  v_full_name := TRIM(p_last_name) || ', ' || TRIM(p_first_name)
    || CASE WHEN v_middle IS NOT NULL THEN ' ' || v_middle ELSE '' END;

  -- ── Create applicant row ──────────────────────────────────────────────────
  -- vacancy_vcode is intentionally NULL: CG applicants are bound via
  -- coverage_slot_id / coverage_group_id, not via a VCODE.
  INSERT INTO public.applicants (
    last_name,
    first_name,
    middle_name,
    full_name,
    contact_number,
    status,
    remarks,
    source_channel,
    is_archived
  ) VALUES (
    TRIM(p_last_name),
    TRIM(p_first_name),
    v_middle,
    v_full_name,
    TRIM(p_contact_number),
    v_status_opt.label,
    NULLIF(TRIM(COALESCE(p_remarks, '')), ''),
    NULLIF(TRIM(COALESCE(p_source_channel, '')), ''),
    false
  )
  RETURNING id INTO v_app_id;

  -- ── Bind applicant to coverage group slot (open → pipeline) ──────────────
  SELECT public.fn_bind_applicant_to_coverage_group(
    p_applicant_id      => v_app_id,
    p_coverage_group_id => p_coverage_group_id,
    p_performed_by      => v_actor
  ) INTO v_bind_result;

  IF (v_bind_result->>'status') <> 'ok' THEN
    RAISE EXCEPTION
      'coverage_slot_bind_failed: slot transition blocked — %. '
      'The open slot may have been claimed concurrently. Please try again.',
      COALESCE(v_bind_result->>'blocked_reason', 'unknown')
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Audit ─────────────────────────────────────────────────────────────────
  PERFORM public.log_audit_event(
    'vacancy_module', 'INSERT', v_app_id,
    NULL,
    jsonb_build_object(
      'action',            'add_applicant_to_coverage_group',
      'coverage_group_id', p_coverage_group_id,
      'coverage_code',     v_grp.coverage_code,
      'coverage_slot_id',  v_bind_result->>'coverage_slot_id',
      'slot_ordinal',      v_bind_result->>'slot_ordinal'
    )
  );

  RETURN jsonb_build_object(
    'applicant_id',      v_app_id,
    'coverage_group_id', p_coverage_group_id,
    'coverage_slot_id',  (v_bind_result->>'coverage_slot_id')::uuid,
    'slot_ordinal',      (v_bind_result->>'slot_ordinal')::integer
  );
END;
$$;

COMMENT ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text) IS
  'OHM2026_0086C_FIX1: RBAC widened to i_have_full_access() OR i_am_ops() OR i_am_recruitment(). '
  'Creates an applicant and binds them to the lowest-ordinal open coverage slot '
  '(FOR UPDATE SKIP LOCKED via fn_bind_applicant_to_coverage_group). '
  'Enforces: scope, open-slot pre-check, duplicate identity guard (cross-CG and cross-VCODE). '
  'Sets applicants.coverage_slot_id and coverage_group_id; transitions slot open→pipeline. '
  'vacancy_vcode is intentionally NULL for CG applicants.';


-- ============================================================
-- §2  Grants (unchanged — authenticated role)
-- ============================================================

REVOKE ALL ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text)
  TO authenticated;


-- ============================================================
-- §3  Post-migration validation (run manually)
-- ============================================================
--
-- V1 — Super Admin can add applicant (was blocked before this fix).
--   (Log in as SA user, call RPC from Flutter or SQL — expect success.)
--
-- V2 — Head Admin can add applicant.
--   (Log in as HA user — expect success.)
--
-- V3 — Recruitment can add applicant.
--   (Log in as Recruitment user — expect success.)
--
-- V4 — Ops (om/hrco/atl/tl) can add applicant (regression guard).
--   (Log in as Ops user — expect success.)
--
-- V5 — Unauthorized role (e.g. Viewer, HR Personnel) is still blocked.
--   (Log in as Viewer — expect 42501 'forbidden: insufficient role'.)
--
-- V6 — Slot changes open → pipeline after successful add.
--   SELECT slot_status FROM public.coverage_slots WHERE id = '<slot_id>';
--   -- Expected: 'pipeline'.
--
-- V7 — Applicant row has both coverage_group_id and coverage_slot_id set.
--   SELECT coverage_slot_id, coverage_group_id FROM public.applicants WHERE id = '<id>';
--   -- Expected: both non-NULL.
-- ============================================================
