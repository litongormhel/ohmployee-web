-- ============================================================
-- OHM2026_0086C_FIX2 — Fix add_applicant_to_coverage_group INSERT
-- Migration: 20260928000000_fix2_add_applicant_to_coverage_group.sql
--
-- Bug: PostgrestException code 42703 — column "source_channel" does not exist
--      Root cause 1: applicants.source_channel column never exists in schema;
--                    the INSERT referenced a non-existent column.
--      Root cause 2: applicants.vacancy_vcode is NOT NULL with no default,
--                    but CG applicants are intentionally inserted without a vcode.
--                    This would surface as a NOT NULL violation after fix 1.
--
-- Fixes:
--   §1  ALTER TABLE: make vacancy_vcode nullable
--         CG applicants are bound via coverage_slot_id / coverage_group_id;
--         vacancy_vcode being NULL is valid and by design for this path.
--   §2  CREATE OR REPLACE FUNCTION: remove source_channel from INSERT column list
--         p_source_channel parameter is KEPT for API/client compatibility
--         but is silently ignored (no applicants column to receive it).
--
-- Preserves:
--   - coverage_group_id / coverage_slot_id binding
--   - duplicate identity guard (cross-CG, cross-VCODE)
--   - slot open → pipeline transition via fn_bind_applicant_to_coverage_group
--   - RBAC fix from FIX1 (i_have_full_access OR i_am_ops OR i_am_recruitment)
--   - Grants (authenticated role)
--   - All normal VCODE Add Applicant paths unaffected
-- ============================================================


-- ============================================================
-- §1  Make vacancy_vcode nullable
--     Coverage group applicants have no vcode by design.
-- ============================================================

ALTER TABLE public.applicants
  ALTER COLUMN vacancy_vcode DROP NOT NULL;


-- ============================================================
-- §2  Patched add_applicant_to_coverage_group
--     Removes source_channel from INSERT; keeps p_source_channel param.
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
  -- vacancy_vcode is now nullable (see §1 ALTER TABLE above).
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
  'OHM2026_0086C_FIX2: Removed source_channel from INSERT (column does not exist). '
  'vacancy_vcode made nullable via ALTER TABLE (CG applicants have no vcode by design). '
  'p_source_channel param kept for API/client compatibility but is not stored. '
  'RBAC: i_have_full_access() OR i_am_ops() OR i_am_recruitment() (from FIX1). '
  'Creates applicant and binds to lowest-ordinal open coverage slot '
  '(FOR UPDATE SKIP LOCKED via fn_bind_applicant_to_coverage_group). '
  'Enforces: scope, open-slot pre-check, duplicate identity guard (cross-CG and cross-VCODE). '
  'Sets applicants.coverage_slot_id and coverage_group_id; transitions slot open→pipeline.';


-- ============================================================
-- §3  Grants (unchanged — authenticated role)
-- ============================================================

REVOKE ALL ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text)
  TO authenticated;


-- ============================================================
-- §4  Post-migration validation (run manually)
-- ============================================================
--
-- V1 — vacancy_vcode is now nullable.
--   SELECT is_nullable FROM information_schema.columns
--    WHERE table_schema='public' AND table_name='applicants'
--      AND column_name='vacancy_vcode';
--   -- Expected: 'YES'
--
-- V2 — Add applicant to coverage group succeeds end-to-end.
--   (Call add_applicant_to_coverage_group for a group with ≥1 open slot.)
--   -- Expected: JSONB with applicant_id, coverage_group_id, coverage_slot_id, slot_ordinal.
--
-- V3 — Applicant row has coverage_group_id and coverage_slot_id set, vacancy_vcode NULL.
--   SELECT vacancy_vcode, coverage_slot_id, coverage_group_id
--     FROM public.applicants WHERE id = '<id>';
--   -- Expected: vacancy_vcode=NULL, coverage_slot_id≠NULL, coverage_group_id≠NULL.
--
-- V4 — Slot transitions open → pipeline.
--   SELECT slot_status FROM public.coverage_slots WHERE id = '<coverage_slot_id>';
--   -- Expected: 'pipeline'.
--
-- V5 — Normal VCODE Add Applicant still works (regression).
--   (Use the normal addApplicant Flutter path for a VCODE vacancy.)
--   -- Expected: applicant created with vacancy_vcode set; coverage_slot_id NULL.
--
-- V6 — No open slot → friendly P0001 with 'no_open_coverage_slot'.
--
-- V7 — Duplicate identity → friendly P0001 with 'duplicate_applicant_identity'.
--
-- V8 — Unauthorized role → 42501 'forbidden: insufficient role'.
-- ============================================================
