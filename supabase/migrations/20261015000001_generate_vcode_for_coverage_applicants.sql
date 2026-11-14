-- ============================================================
-- OHM2026_0086E — Generate VCODE for CG-Roving/Coverage Applicants
-- Migration: 20261015000000_generate_vcode_for_coverage_applicants.sql
-- ============================================================

-- §1. Drop the foreign key constraint that requires vacancy_vcode to exist in vacancies
ALTER TABLE public.applicants DROP CONSTRAINT IF EXISTS fk_applicants_vacancy_vcode;

-- §2. Trigger function to ensure VCODE is never null/empty if coverage group/slot is set
CREATE OR REPLACE FUNCTION public.fn_trg_ensure_applicant_vcode()
RETURNS trigger AS $$
DECLARE
  v_account_id uuid;
BEGIN
  IF NEW.vacancy_vcode IS NULL OR TRIM(NEW.vacancy_vcode) = '' THEN
    -- 1. Try to resolve account_id from coverage group
    IF NEW.coverage_group_id IS NOT NULL THEN
      SELECT account_id INTO v_account_id
      FROM public.coverage_groups
      WHERE id = NEW.coverage_group_id;
    -- 2. Try to resolve account_id from plantilla slot
    ELSIF NEW.slot_id IS NOT NULL THEN
      SELECT v.account_id INTO v_account_id
      FROM public.plantilla_slots s
      JOIN public.vacancies v ON v.vcode = s.vcode
      WHERE s.id = NEW.slot_id;
    END IF;

    -- Generate and assign VCODE if account was resolved
    IF v_account_id IS NOT NULL THEN
      NEW.vacancy_vcode := public.generate_vcode_for_account(v_account_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- §3. Attach trigger to public.applicants table
DROP TRIGGER IF EXISTS trg_applicants_ensure_vcode ON public.applicants;
CREATE TRIGGER trg_applicants_ensure_vcode
  BEFORE INSERT OR UPDATE ON public.applicants
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_ensure_applicant_vcode();

-- §4. Patched add_applicant_to_coverage_group with direct VCODE generation
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
  v_vcode       text;
  v_bind_result jsonb;
BEGIN
  -- ── RBAC ─────────────────────────────────────────────────────────────────
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

  -- ── Generate VCODE for the account ────────────────────────────────────────
  v_vcode := public.generate_vcode_for_account(v_grp.account_id);

  -- ── Create applicant row ──────────────────────────────────────────────────
  INSERT INTO public.applicants (
    last_name,
    first_name,
    middle_name,
    full_name,
    contact_number,
    status,
    remarks,
    is_archived,
    vacancy_vcode
  ) VALUES (
    TRIM(p_last_name),
    TRIM(p_first_name),
    v_middle,
    v_full_name,
    TRIM(p_contact_number),
    v_status_opt.label,
    NULLIF(TRIM(COALESCE(p_remarks, '')), ''),
    false,
    v_vcode
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
      'slot_ordinal',      v_bind_result->>'slot_ordinal',
      'vacancy_vcode',     v_vcode
    )
  );

  RETURN jsonb_build_object(
    'applicant_id',      v_app_id,
    'coverage_group_id', p_coverage_group_id,
    'coverage_slot_id',  (v_bind_result->>'coverage_slot_id')::uuid,
    'slot_ordinal',      (v_bind_result->>'slot_ordinal')::integer,
    'vacancy_vcode',     v_vcode
  );
END;
$$;

COMMENT ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text) IS
  'OHM2026_0086E: Generates VCODE for applicant on insert. Removed source_channel from INSERT. vacancy_vcode made nullable via ALTER TABLE. p_source_channel param kept for API/client compatibility but is not stored. RBAC: i_have_full_access() OR i_am_ops() OR i_am_recruitment(). Creates applicant and binds to lowest-ordinal open coverage slot.';

GRANT EXECUTE ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text)
  TO authenticated;


-- §5. Backfill existing NULL vacancy_vcode records for coverage group applicants
DO $$
DECLARE
  r RECORD;
  v_account_id uuid;
  v_vcode text;
  v_count integer := 0;
BEGIN
  FOR r IN 
    SELECT id, coverage_group_id 
    FROM public.applicants 
    WHERE coverage_group_id IS NOT NULL 
      AND (vacancy_vcode IS NULL OR TRIM(vacancy_vcode) = '')
  LOOP
    SELECT account_id INTO v_account_id
    FROM public.coverage_groups
    WHERE id = r.coverage_group_id;

    IF v_account_id IS NOT NULL THEN
      v_vcode := public.generate_vcode_for_account(v_account_id);
      
      UPDATE public.applicants
      SET vacancy_vcode = v_vcode
      WHERE id = r.id;
      
      v_count := v_count + 1;
    END IF;
  END LOOP;
  
  RAISE NOTICE 'Backfilled % coverage group applicants with generated VCODEs.', v_count;
END;
$$;
