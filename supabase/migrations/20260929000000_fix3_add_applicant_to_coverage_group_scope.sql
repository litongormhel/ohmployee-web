-- ============================================================
-- OHM2026_0086C_FIX3 — Fix Coverage Applicant Add Account Scope
-- Migration: 20260929000000_fix3_add_applicant_to_coverage_group_scope.sql
--
-- Bug: Super Admin / Head Admin still get permission denied when adding
--      applicants to Coverage Groups.
--
-- Likely cause: Role guard was updated in FIX1, but the account scope check
--               and internal fn_bind_applicant_to_coverage_group role/scope
--               checks still block non-Ops / full-access callers.
--
-- Fixes:
--   §1 Patched add_applicant_to_coverage_group:
--        - Wrap account scope check so it only applies when NOT i_have_full_access()
--        - Set clear error message: "forbidden: coverage group account outside caller scope"
--   §2 Patched fn_bind_applicant_to_coverage_group:
--        - Widened RBAC role guard to allow i_have_full_access() OR i_am_ops() OR i_am_recruitment()
--        - Wrap account scope check so it only applies when NOT i_have_full_access()
--        - Set clear error message: "forbidden: coverage group account outside caller scope"
-- ============================================================


-- ============================================================
-- §1 Patched add_applicant_to_coverage_group
-- ============================================================

CREATE OR REPLACE FUNCTION public.add_applicant_to_coverage_group(
  p_coverage_group_id  uuid,
  p_last_name          text,
  p_first_name         text,
  p_contact_number     text,
  p_middle_name        text    DEFAULT NULL,
  p_status             text    DEFAULT 'new',
  p_remarks            text    DEFAULT NULL,
  p_source_channel     text    DEFAULT NULL  -- accepted for API compatibility; not stored (no column)
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
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_grp.account_id = ANY (public.get_my_allowed_account_ids())) THEN
      RAISE EXCEPTION 'forbidden: coverage group account outside caller scope'
        USING ERRCODE = '42501';
    END IF;
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
  -- p_source_channel is accepted by the function signature but not stored
  -- (applicants table has no source_channel column).
  INSERT INTO public.applicants (
    last_name,
    first_name,
    middle_name,
    full_name,
    contact_number,
    status,
    remarks,
    is_archived
  ) VALUES (
    TRIM(p_last_name),
    TRIM(p_first_name),
    v_middle,
    v_full_name,
    TRIM(p_contact_number),
    v_status_opt.label,
    NULLIF(TRIM(COALESCE(p_remarks, '')), ''),
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
  'OHM2026_0086C_FIX3: Wrap account scope check to only apply when NOT i_have_full_access(). '
  'vacancy_vcode made nullable via ALTER TABLE. '
  'p_source_channel param kept for API/client compatibility but is not stored. '
  'RBAC: i_have_full_access() OR i_am_ops() OR i_am_recruitment(). '
  'Creates applicant and binds to lowest-ordinal open coverage slot. '
  'Enforces: scope, open-slot pre-check, duplicate identity guard. '
  'Sets applicants.coverage_slot_id and coverage_group_id; transitions slot open→pipeline.';


-- ============================================================
-- §2 Patched fn_bind_applicant_to_coverage_group
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_bind_applicant_to_coverage_group(
  p_applicant_id      uuid,
  p_coverage_group_id uuid,
  p_performed_by      uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_app          public.applicants%ROWTYPE;
  v_grp          public.coverage_groups%ROWTYPE;
  v_claimed_slot uuid;
  v_claimed_ord  integer;
  v_open_cnt     bigint;
  v_actor        uuid := COALESCE(p_performed_by, public.get_my_profile_id());
  v_slot_result  jsonb;
BEGIN
  -- Allow: Super Admin, Head Admin (i_have_full_access),
  --        Ops roles om/hrco/atl/tl (i_am_ops),
  --        Recruitment / Recruitment Team (i_am_recruitment).
  IF NOT (
    public.i_have_full_access()
    OR public.i_am_ops()
    OR public.i_am_recruitment()
  ) THEN
    RAISE EXCEPTION 'forbidden: insufficient role to bind applicants' USING ERRCODE = '42501';
  END IF;

  -- ── Resolve + scope the coverage group ────────────────────────────────────
  SELECT * INTO v_grp
    FROM public.coverage_groups
   WHERE id = p_coverage_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_grp.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'coverage group is archived' USING ERRCODE = 'P0001';
  END IF;

  -- ── Scope check ───────────────────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_grp.account_id = ANY (public.get_my_allowed_account_ids())) THEN
      RAISE EXCEPTION 'forbidden: coverage group account outside caller scope' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Lock + validate the applicant ─────────────────────────────────────────
  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
     AND COALESCE(is_archived, false) = false
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Mutual exclusivity (plan Q9): a stationary applicant cannot take a coverage slot.
  IF v_app.slot_id IS NOT NULL THEN
    RAISE EXCEPTION
      'applicant % is stationary (slot_id set) — cannot bind to a coverage slot',
      p_applicant_id USING ERRCODE = 'P0001';
  END IF;
  IF v_app.coverage_slot_id IS NOT NULL THEN
    RAISE EXCEPTION
      'applicant % is already bound to coverage_slot %',
      p_applicant_id, v_app.coverage_slot_id USING ERRCODE = 'P0001';
  END IF;

  -- ── Claim the lowest-ordinal open coverage slot (Q1/Q2/Q3) ────────────────
  SELECT id, slot_ordinal
    INTO v_claimed_slot, v_claimed_ord
    FROM public.coverage_slots
   WHERE coverage_group_id = v_grp.id
     AND slot_status       = 'open'
   ORDER BY slot_ordinal ASC, created_at ASC, id ASC
   LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_claimed_slot IS NULL THEN
    SELECT COUNT(*) INTO v_open_cnt
      FROM public.coverage_slots
     WHERE coverage_group_id = v_grp.id;
    RAISE EXCEPTION
      'no_open_coverage_slot: CGCODE % has % slot(s) but none are open. '
      'All headcount is in pipeline, processing, filled, or closed. '
      'Increase required headcount before adding another applicant.',
      v_grp.coverage_code, v_open_cnt
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Bind BOTH FK columns in one statement (Q1) ────────────────────────────
  UPDATE public.applicants
     SET coverage_slot_id  = v_claimed_slot,
         coverage_group_id = v_grp.id,
         updated_at        = now(),
         updated_by        = v_actor
   WHERE id = p_applicant_id;

  -- ── Transition the exact claimed slot open → pipeline (blocking) ──────────
  SELECT public.fn_set_coverage_slot_status(
    p_slot_id      => v_claimed_slot,
    p_new_status   => 'pipeline',
    p_performed_by => v_actor,
    p_remarks      => format(
      'Phase R-B / fn_bind_applicant_to_coverage_group / CGCODE=%s / '
      'applicant=%s / slot_ordinal=%s',
      v_grp.coverage_code, p_applicant_id, v_claimed_ord
    )
  ) INTO v_slot_result;

  IF (v_slot_result->>'status') = 'blocked' THEN
    RAISE EXCEPTION
      'coverage_slot_transition_blocked: claimed slot % could not transition to '
      'pipeline — %. Resolve coverage slot status before binding.',
      v_claimed_slot, v_slot_result->>'blocked_reason'
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.log_audit_event(
    'vacancy_module', 'UPDATE', p_applicant_id,
    NULL,
    jsonb_build_object(
      'action',            'bind_applicant_to_coverage_group',
      'coverage_group_id', v_grp.id,
      'coverage_code',     v_grp.coverage_code,
      'coverage_slot_id',  v_claimed_slot,
      'slot_ordinal',      v_claimed_ord
    )
  );

  RETURN jsonb_build_object(
    'status',            'ok',
    'applicant_id',      p_applicant_id,
    'coverage_group_id', v_grp.id,
    'coverage_slot_id',  v_claimed_slot,
    'slot_ordinal',      v_claimed_ord
  );
END;
$$;

COMMENT ON FUNCTION public.fn_bind_applicant_to_coverage_group(uuid, uuid, uuid) IS
  'OHM2026_0086C_FIX3 — CGCODE applicant claim/bind. '
  'RBAC Widened: i_have_full_access() OR i_am_ops() OR i_am_recruitment(). '
  'Scope check: only applies when NOT i_have_full_access(). '
  'Binds an existing applicant to the lowest-ordinal open coverage slot, '
  'sets coverage_slot_id + coverage_group_id, transitions slot open→pipeline.';


-- ============================================================
-- §3 Grants (unchanged)
-- ============================================================

REVOKE ALL ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text)
  TO authenticated;

REVOKE ALL ON FUNCTION public.fn_bind_applicant_to_coverage_group(uuid, uuid, uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_bind_applicant_to_coverage_group(uuid, uuid, uuid)
  TO authenticated;
