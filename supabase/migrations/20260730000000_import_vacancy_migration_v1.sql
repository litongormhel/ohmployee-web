-- ============================================================
-- OHM2026_1135 — Import Vacancy (one-time migration import)
-- Migration:  20260730000000_import_vacancy_migration_v1.sql
-- Depends on: vacancies, applicants, accounts, groups
--             helper fns: fn_can_upload_plantilla_import,
--             fn_can_approve_plantilla_import, i_have_full_access,
--             get_my_role, get_my_allowed_account_ids, get_current_profile_id
-- ============================================================
-- Purpose
--   Migration-only Vacancy import pipeline (More > Data Control >
--   Import Vacancy). One-time seeding of EXISTING open and pipeline
--   vacancies from Google Sheets into OHMployee, preserving the
--   official VCODEs exactly. After migration this module is hidden.
--
--   1 upload = 1 group + 1 account (selected in the UI).
--   VCODEs are preserved as-is — NO new VCODEs are generated here.
--   Active employees are NOT imported (Plantilla Import handles those).
--
--   Vacancy tab is derived automatically:
--     no applicant fields  → Open tab    (vacancy with no active applicant)
--     applicant present    → Pipeline tab (vacancy + one seeded applicant)
--   There is NO VACANCY_STATUS CSV column — state is system-derived.
--
--   CSV contract (UI selects GROUP + ACCOUNT; CSV still carries names
--   for a mandatory match check):
--     Required:
--       VCODE, GROUP_NAME, CHAIN, ACCOUNT_NAME, STORE_NAME, POSITION,
--       HC, EMPLOYMENT_TYPE, REQUEST_TYPE, VACANT_DATE, PROVINCE, CITY
--     Optional:
--       TARGET_FILL_DATE, HRCO, CONTACT_NUMBER, WITH_PENALTY,
--       APPLICANT_LAST_NAME, APPLICANT_FIRST_NAME, APPLICANT_MIDDLE_NAME,
--       APPLICANT_STATUS, APPLICANT_SOURCE, MIGRATION_SOURCE, MIGRATION_NOTES
--
-- Architecture
--   Dedicated staging tables (vacancy_import_batches,
--   vacancy_import_rows) — independent of plantilla/store import.
--   Dry-run validation never writes vacancies/applicants; commit
--   happens only on Head Admin / Super Admin approval.
--
-- RBAC
--   Upload:  Encoder / Head Admin / Super Admin  (fn_can_upload_plantilla_import)
--   Approve: Head Admin / Super Admin            (fn_can_approve_plantilla_import)
--
-- Sections
--   §1  vacancies.request_type column + provenance column
--   §2  vacancy_import_batches table
--   §3  vacancy_import_rows table
--   §4  RLS policies
--   §5  Indexes
--   §6  submit_vacancy_import        (dry-run validation)
--   §7  get_vacancy_import_batches / get_vacancy_import_rows
--   §8  approve_vacancy_import       (commit RPC)
--   §9  reject_vacancy_import
--   §10 get_vacancy_import_template_csv
--
-- Validation queries (run after applying):
--   V1  SELECT tablename FROM pg_tables WHERE schemaname='public'
--         AND tablename IN ('vacancy_import_batches','vacancy_import_rows');
--   V2  SELECT proname FROM pg_proc WHERE proname IN
--         ('submit_vacancy_import','get_vacancy_import_batches',
--          'get_vacancy_import_rows','approve_vacancy_import',
--          'reject_vacancy_import','get_vacancy_import_template_csv');
--   V3  Dry-run must never write vacancies:
--         after submit, SELECT count(*) FROM vacancies
--           WHERE source_vacancy_import_batch_id = <batch_id>;  -- expect 0
--   V4  Duplicate / existing VCODE → blocked.
--   V5  Group/account name mismatch vs UI selection → blocked.
-- ============================================================


-- ============================================================
-- §1  vacancies.request_type + provenance
-- ============================================================
-- REQUEST_TYPE exists operationally on headcount_requests; surface it on
-- vacancies for the migrated rows and Vacancy Details Overview. Canonical
-- values align with headcount_requests_request_type_check (the importer
-- normalises the ticket's "Additional HC" → "Additional Headcount").

ALTER TABLE public.vacancies
  ADD COLUMN IF NOT EXISTS request_type text;
COMMENT ON COLUMN public.vacancies.request_type IS
  'Operational request type for this vacancy (OHM2026_1135). '
  'Canonical values: Replacement / Additional Headcount / Reliever / Commando. '
  'Surfaced in Vacancy Details Overview.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vacancies_request_type_check'
  ) THEN
    ALTER TABLE public.vacancies
      ADD CONSTRAINT vacancies_request_type_check CHECK (
        request_type IS NULL OR request_type IN (
          'Replacement','Additional Headcount','Reliever','Commando'
        )
      ) NOT VALID;
  END IF;
END$$;

ALTER TABLE public.vacancies
  ADD COLUMN IF NOT EXISTS source_vacancy_import_batch_id uuid;
COMMENT ON COLUMN public.vacancies.source_vacancy_import_batch_id IS
  'vacancy_import_batches.id that seeded this vacancy via the one-time '
  'Import Vacancy migration pipeline (OHM2026_1135).';


-- ============================================================
-- §2  vacancy_import_batches
-- ============================================================

CREATE TABLE IF NOT EXISTS public.vacancy_import_batches (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  file_name                text        NOT NULL,
  uploaded_by              uuid        NOT NULL,   -- auth.uid()
  uploaded_role            text,
  selected_group_id        uuid        NOT NULL,
  selected_account_id      uuid        NOT NULL,

  -- lifecycle: draft_uploaded → validation_failed | pending_approval
  --            → approved | rejected
  status                   text        NOT NULL DEFAULT 'draft_uploaded',

  -- validation counts (populated by submit RPC)
  total_rows               integer     NOT NULL DEFAULT 0,
  valid_rows               integer     NOT NULL DEFAULT 0,
  flagged_rows             integer     NOT NULL DEFAULT 0,
  skipped_rows             integer     NOT NULL DEFAULT 0,
  blocked_rows             integer     NOT NULL DEFAULT 0,
  open_count               integer     NOT NULL DEFAULT 0,   -- rows with no applicant
  pipeline_count           integer     NOT NULL DEFAULT 0,   -- rows with applicant
  duplicate_vcode_count    integer     NOT NULL DEFAULT 0,   -- VCODEs duplicated within upload
  existing_vcode_count     integer     NOT NULL DEFAULT 0,   -- VCODEs already present in vacancies
  context_mismatch_count   integer     NOT NULL DEFAULT 0,   -- CSV group/account != UI selection
  error_summary            jsonb       NOT NULL DEFAULT '{}'::jsonb,

  -- approval
  approved_by              uuid,
  approved_at              timestamptz,
  committed_vacancies      integer,
  committed_applicants     integer,

  -- rejection
  rejected_by              uuid,
  rejected_at              timestamptz,
  rejection_reason         text,

  -- commit failure logging
  commit_error_detail      text,

  created_at               timestamptz NOT NULL DEFAULT NOW(),
  updated_at               timestamptz NOT NULL DEFAULT NOW(),

  CONSTRAINT vib_pkey PRIMARY KEY (id),
  CONSTRAINT vib_status_check CHECK (
    status IN ('draft_uploaded','validation_failed','pending_approval',
               'approved','rejected','commit_failed')
  ),
  CONSTRAINT vib_group_fkey
    FOREIGN KEY (selected_group_id) REFERENCES public.groups(id) NOT VALID,
  CONSTRAINT vib_account_fkey
    FOREIGN KEY (selected_account_id) REFERENCES public.accounts(id) NOT VALID
);

COMMENT ON TABLE public.vacancy_import_batches IS
  'One-time Import Vacancy migration batch (OHM2026_1135). '
  '1 batch = 1 group + 1 account. Stages CSV rows for dry-run review; '
  'commits vacancies (+ seeded pipeline applicants) on approval.';

ALTER TABLE public.vacancy_import_batches ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.vacancy_import_batches FROM authenticated, anon;


-- ============================================================
-- §3  vacancy_import_rows
-- ============================================================

CREATE TABLE IF NOT EXISTS public.vacancy_import_rows (
  id                         uuid        NOT NULL DEFAULT gen_random_uuid(),
  batch_id                   uuid        NOT NULL,
  row_number                 integer     NOT NULL,
  raw_data                   jsonb       NOT NULL,

  -- Vacancy profile (from CSV)
  vcode                      text,
  group_name                 text,
  chain                      text,
  account_name               text,
  store_name                 text,
  position                   text,
  hc_raw                     text,
  employment_type            text,
  request_type_raw           text,        -- as typed in CSV
  request_type_norm          text,        -- canonical normalised value
  vacant_date_raw            text,
  province                   text,
  city                       text,
  target_fill_date_raw       text,
  hrco                       text,
  contact_number             text,
  with_penalty_raw           text,
  with_penalty_norm          boolean,

  -- Applicant profile (optional — presence ⇒ Pipeline)
  applicant_last_name        text,
  applicant_first_name       text,
  applicant_middle_name      text,
  applicant_status           text,
  applicant_source           text,

  -- Migration metadata
  migration_source           text,
  migration_notes            text,

  -- Derived
  derived_tab                text,        -- 'open' | 'pipeline'

  -- Dry-run outcome
  validation_status          text        NOT NULL,  -- valid|flagged|skipped|blocked
  validation_errors          jsonb       NOT NULL DEFAULT '[]'::jsonb,
  validation_flags           jsonb       NOT NULL DEFAULT '[]'::jsonb,
  is_existing_vcode          boolean     NOT NULL DEFAULT false,

  created_at                 timestamptz NOT NULL DEFAULT NOW(),

  CONSTRAINT vir_pkey PRIMARY KEY (id),
  CONSTRAINT vir_status_check CHECK (
    validation_status IN ('valid','flagged','skipped','blocked')
  ),
  CONSTRAINT vir_tab_check CHECK (
    derived_tab IS NULL OR derived_tab IN ('open','pipeline')
  ),
  CONSTRAINT vir_batch_fkey
    FOREIGN KEY (batch_id) REFERENCES public.vacancy_import_batches(id) ON DELETE CASCADE NOT VALID
);

COMMENT ON TABLE public.vacancy_import_rows IS
  'Staged CSV rows for the one-time Import Vacancy migration (OHM2026_1135). '
  'derived_tab classifies Open vs Pipeline automatically from applicant fields.';

ALTER TABLE public.vacancy_import_rows ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.vacancy_import_rows FROM authenticated, anon;


-- ============================================================
-- §4  RLS policies
-- ============================================================
-- Full-access (HA/SA) sees all. Uploaders see their own batches.

CREATE POLICY vib_select ON public.vacancy_import_batches
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR uploaded_by = auth.uid()
  );

CREATE POLICY vir_select ON public.vacancy_import_rows
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR EXISTS (
      SELECT 1 FROM public.vacancy_import_batches b
      WHERE b.id = vacancy_import_rows.batch_id
        AND b.uploaded_by = auth.uid()
    )
  );


-- ============================================================
-- §5  Indexes
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_vib_status
  ON public.vacancy_import_batches(status);
CREATE INDEX IF NOT EXISTS idx_vib_uploaded_by
  ON public.vacancy_import_batches(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_vib_account
  ON public.vacancy_import_batches(selected_account_id);
CREATE INDEX IF NOT EXISTS idx_vib_created_at
  ON public.vacancy_import_batches(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_vir_batch
  ON public.vacancy_import_rows(batch_id);
CREATE INDEX IF NOT EXISTS idx_vir_batch_status
  ON public.vacancy_import_rows(batch_id, validation_status);
CREATE INDEX IF NOT EXISTS idx_vir_vcode
  ON public.vacancy_import_rows(vcode);


-- ============================================================
-- §6  submit_vacancy_import  (dry-run validation)
-- ============================================================
-- Creates a batch + validates rows. NEVER writes to vacancies/applicants.
-- Each call creates a fresh batch — re-uploads are safe.
--
-- Validation rules per spec:
--   Missing required field (VCODE, GROUP_NAME, CHAIN, ACCOUNT_NAME,
--     STORE_NAME, POSITION, HC, EMPLOYMENT_TYPE, REQUEST_TYPE,
--     VACANT_DATE, PROVINCE, CITY)                         → blocked
--   CSV GROUP_NAME   != selected group name                → blocked
--   CSV ACCOUNT_NAME != selected account name              → blocked
--   HC blank, non-numeric, <= 0, or > 1                    → blocked
--     (locked rule: 1 VCODE = 1 manpower slot, so HC must equal 1)
--   REQUEST_TYPE not an allowed value                      → blocked
--   VACANT_DATE not a valid date                           → blocked
--   Duplicate VCODE within this upload                     → blocked (all)
--   VCODE already present in vacancies (active)            → blocked
--   WITH_PENALTY unrecognised token                        → flagged (defaults false)
--   TARGET_FILL_DATE unparseable                           → flagged (ignored)
--   Applicant present                                      → derived_tab = pipeline

CREATE OR REPLACE FUNCTION public.submit_vacancy_import(
  p_file_name  text,
  p_group_id   uuid,
  p_account_id uuid,
  p_rows       jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid         uuid := auth.uid();
  v_role        text := public.get_my_role();
  v_batch_id    uuid;
  v_acct_group  uuid;
  v_acct_name   text;
  v_group_name  text;

  v_row         jsonb;
  v_idx         int := 0;

  -- Parsed CSV fields
  v_vcode       text;
  v_csv_group   text;
  v_chain       text;
  v_csv_acct    text;
  v_store_nm    text;
  v_position    text;
  v_hc_raw      text;
  v_emp_type    text;
  v_req_raw     text;
  v_req_norm    text;
  v_vacant_raw  text;
  v_vacant_dt   date;
  v_prov        text;
  v_city        text;
  v_tfd_raw     text;
  v_hrco        text;
  v_contact     text;
  v_pen_raw     text;
  v_pen_norm    boolean;
  v_app_last    text;
  v_app_first   text;
  v_app_mid     text;
  v_app_status  text;
  v_app_source  text;
  v_mig_source  text;
  v_mig_notes   text;

  -- Per-row state
  v_errs        jsonb;
  v_flags       jsonb;
  v_status      text;
  v_tab         text;
  v_is_existing boolean;
  v_has_app     boolean;

  -- Batch counters
  v_total       int := 0;
  v_valid       int := 0;
  v_flagged     int := 0;
  v_skipped     int := 0;
  v_blocked     int := 0;
  v_open        int := 0;
  v_pipeline    int := 0;
  v_dup_vcode   int := 0;
  v_exist_vcode int := 0;
  v_ctx_mismatch int := 0;

  v_summary     jsonb;
  v_final       text;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Input validation ─────────────────────────────────────────────────────
  IF p_file_name IS NULL OR length(trim(p_file_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: file_name required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows must be a jsonb array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows is empty' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN
    RAISE EXCEPTION 'INVALID_INPUT: max 5000 rows per batch' USING ERRCODE = '22023';
  END IF;

  -- ── Scope validation ─────────────────────────────────────────────────────
  SELECT group_name INTO v_group_name FROM public.groups WHERE id = p_group_id;
  IF v_group_name IS NULL THEN
    RAISE EXCEPTION 'INVALID_GROUP: %', p_group_id USING ERRCODE = '23503';
  END IF;
  SELECT group_id, account_name INTO v_acct_group, v_acct_name
    FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: %', p_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %',
      p_account_id, p_group_id USING ERRCODE = '23503';
  END IF;
  IF NOT public.i_have_full_access()
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  -- ── Create batch ─────────────────────────────────────────────────────────
  INSERT INTO public.vacancy_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- ── Pre-pass: VCODEs duplicated within this upload ────────────────────────
  DROP TABLE IF EXISTS _vib_dup_vcodes;
  CREATE TEMP TABLE _vib_dup_vcodes ON COMMIT DROP AS
  SELECT upper(trim(elem->>'VCODE')) AS vcode
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1 HAVING count(*) > 1;

  -- ── Row loop ─────────────────────────────────────────────────────────────
  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx       := v_idx + 1;
    v_total     := v_total + 1;
    v_errs      := '[]'::jsonb;
    v_flags     := '[]'::jsonb;
    v_is_existing := false;
    v_req_norm  := NULL;
    v_vacant_dt := NULL;
    v_pen_norm  := false;

    -- Parse CSV fields
    v_vcode      := upper(NULLIF(trim(COALESCE(v_row->>'VCODE','')), ''));
    v_csv_group  := NULLIF(trim(COALESCE(v_row->>'GROUP_NAME','')), '');
    v_chain      := NULLIF(trim(COALESCE(v_row->>'CHAIN','')), '');
    v_csv_acct   := NULLIF(trim(COALESCE(v_row->>'ACCOUNT_NAME','')), '');
    v_store_nm   := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')), '');
    v_position   := NULLIF(trim(COALESCE(v_row->>'POSITION','')), '');
    v_hc_raw     := NULLIF(trim(COALESCE(v_row->>'HC','')), '');
    v_emp_type   := NULLIF(trim(COALESCE(v_row->>'EMPLOYMENT_TYPE','')), '');
    v_req_raw    := NULLIF(trim(COALESCE(v_row->>'REQUEST_TYPE','')), '');
    v_vacant_raw := NULLIF(trim(COALESCE(v_row->>'VACANT_DATE','')), '');
    v_prov       := NULLIF(trim(COALESCE(v_row->>'PROVINCE','')), '');
    v_city       := NULLIF(trim(COALESCE(v_row->>'CITY','')), '');
    v_tfd_raw    := NULLIF(trim(COALESCE(v_row->>'TARGET_FILL_DATE','')), '');
    v_hrco       := NULLIF(trim(COALESCE(v_row->>'HRCO','')), '');
    v_contact    := NULLIF(trim(COALESCE(v_row->>'CONTACT_NUMBER','')), '');
    v_pen_raw    := NULLIF(trim(COALESCE(v_row->>'WITH_PENALTY','')), '');
    v_app_last   := NULLIF(trim(COALESCE(v_row->>'APPLICANT_LAST_NAME','')), '');
    v_app_first  := NULLIF(trim(COALESCE(v_row->>'APPLICANT_FIRST_NAME','')), '');
    v_app_mid    := NULLIF(trim(COALESCE(v_row->>'APPLICANT_MIDDLE_NAME','')), '');
    v_app_status := NULLIF(trim(COALESCE(v_row->>'APPLICANT_STATUS','')), '');
    v_app_source := NULLIF(trim(COALESCE(v_row->>'APPLICANT_SOURCE','')), '');
    v_mig_source := NULLIF(trim(COALESCE(v_row->>'MIGRATION_SOURCE','')), '');
    v_mig_notes  := NULLIF(trim(COALESCE(v_row->>'MIGRATION_NOTES','')), '');

    -- Required field checks (blocking)
    IF v_vcode    IS NULL THEN v_errs := v_errs || '[{"field":"VCODE","msg":"required"}]'::jsonb; END IF;
    IF v_csv_group IS NULL THEN v_errs := v_errs || '[{"field":"GROUP_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_chain    IS NULL THEN v_errs := v_errs || '[{"field":"CHAIN","msg":"required"}]'::jsonb; END IF;
    IF v_csv_acct IS NULL THEN v_errs := v_errs || '[{"field":"ACCOUNT_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_store_nm IS NULL THEN v_errs := v_errs || '[{"field":"STORE_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_position IS NULL THEN v_errs := v_errs || '[{"field":"POSITION","msg":"required"}]'::jsonb; END IF;
    IF v_hc_raw   IS NULL THEN v_errs := v_errs || '[{"field":"HC","msg":"required"}]'::jsonb; END IF;
    IF v_emp_type IS NULL THEN v_errs := v_errs || '[{"field":"EMPLOYMENT_TYPE","msg":"required"}]'::jsonb; END IF;
    IF v_req_raw  IS NULL THEN v_errs := v_errs || '[{"field":"REQUEST_TYPE","msg":"required"}]'::jsonb; END IF;
    IF v_vacant_raw IS NULL THEN v_errs := v_errs || '[{"field":"VACANT_DATE","msg":"required"}]'::jsonb; END IF;
    IF v_prov     IS NULL THEN v_errs := v_errs || '[{"field":"PROVINCE","msg":"required"}]'::jsonb; END IF;
    IF v_city     IS NULL THEN v_errs := v_errs || '[{"field":"CITY","msg":"required"}]'::jsonb; END IF;

    -- Group / account context match vs UI selection
    IF v_csv_group IS NOT NULL AND lower(v_csv_group) <> lower(v_group_name) THEN
      v_errs := v_errs || jsonb_build_array(jsonb_build_object(
        'field','GROUP_NAME',
        'msg', format('CSV group "%s" does not match selected group "%s"',
                      v_csv_group, v_group_name)));
      v_ctx_mismatch := v_ctx_mismatch + 1;
    END IF;
    IF v_csv_acct IS NOT NULL AND lower(v_csv_acct) <> lower(v_acct_name) THEN
      v_errs := v_errs || jsonb_build_array(jsonb_build_object(
        'field','ACCOUNT_NAME',
        'msg', format('CSV account "%s" does not match selected account "%s"',
                      v_csv_acct, v_acct_name)));
      v_ctx_mismatch := v_ctx_mismatch + 1;
    END IF;

    -- HC must equal exactly 1 (locked rule: 1 VCODE = 1 manpower slot).
    -- Blank is caught by the required-field check above; reject any other
    -- value (non-numeric, <= 0, or > 1) here.
    IF v_hc_raw IS NOT NULL THEN
      IF v_hc_raw !~ '^\d+$' OR v_hc_raw::int <> 1 THEN
        v_errs := v_errs || '[{"field":"HC","msg":"HC must be exactly 1 (1 VCODE = 1 manpower slot)"}]'::jsonb;
      END IF;
    END IF;

    -- REQUEST_TYPE normalisation + allowed-value check
    IF v_req_raw IS NOT NULL THEN
      v_req_norm := CASE lower(v_req_raw)
        WHEN 'replacement'         THEN 'Replacement'
        WHEN 'additional hc'       THEN 'Additional Headcount'
        WHEN 'additional headcount' THEN 'Additional Headcount'
        WHEN 'reliever'            THEN 'Reliever'
        WHEN 'commando'            THEN 'Commando'
        ELSE NULL
      END;
      IF v_req_norm IS NULL THEN
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field','REQUEST_TYPE',
          'msg', format('"%s" is not allowed (Replacement, Additional HC, Reliever, Commando)',
                        v_req_raw)));
      END IF;
    END IF;

    -- VACANT_DATE must parse
    IF v_vacant_raw IS NOT NULL THEN
      BEGIN
        v_vacant_dt := v_vacant_raw::date;
      EXCEPTION WHEN others THEN
        v_vacant_dt := NULL;
        v_errs := v_errs || jsonb_build_array(jsonb_build_object(
          'field','VACANT_DATE',
          'msg', format('"%s" is not a valid date (use YYYY-MM-DD)', v_vacant_raw)));
      END;
    END IF;

    -- WITH_PENALTY normalisation (optional)
    IF v_pen_raw IS NOT NULL THEN
      v_pen_norm := CASE lower(v_pen_raw)
        WHEN 'yes' THEN true  WHEN 'y' THEN true
        WHEN 'true' THEN true WHEN '1' THEN true
        WHEN 'no' THEN false  WHEN 'n' THEN false
        WHEN 'false' THEN false WHEN '0' THEN false
        ELSE NULL
      END;
      IF v_pen_norm IS NULL THEN
        v_pen_norm := false;
        v_flags := v_flags || jsonb_build_array(jsonb_build_object(
          'flag','with_penalty_unrecognised',
          'msg', format('WITH_PENALTY "%s" not recognised — defaulted to No', v_pen_raw)));
      END IF;
    END IF;

    -- TARGET_FILL_DATE optional parse (flag only)
    IF v_tfd_raw IS NOT NULL THEN
      BEGIN
        PERFORM v_tfd_raw::date;
      EXCEPTION WHEN others THEN
        v_flags := v_flags || jsonb_build_array(jsonb_build_object(
          'flag','target_fill_date_invalid',
          'msg', format('TARGET_FILL_DATE "%s" ignored (unparseable)', v_tfd_raw)));
        v_tfd_raw := NULL;
      END;
    END IF;

    -- Duplicate VCODE within upload → block
    IF v_vcode IS NOT NULL AND EXISTS (SELECT 1 FROM _vib_dup_vcodes WHERE vcode = v_vcode) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"duplicate VCODE in upload — each VCODE must appear exactly once"}]'::jsonb;
    END IF;

    -- VCODE already present in vacancies (active) → block (preserve integrity)
    IF v_vcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.vacancies vv
      WHERE upper(vv.vcode) = v_vcode
        AND COALESCE(vv.is_archived, false) = false
        AND vv.deleted_at IS NULL
    ) THEN
      v_is_existing := true;
      v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE already exists in OHMployee — migration import is for new VCODEs only"}]'::jsonb;
      v_exist_vcode := v_exist_vcode + 1;
    END IF;

    -- Derive Open vs Pipeline from applicant fields
    v_has_app := (v_app_last IS NOT NULL OR v_app_first IS NOT NULL);
    v_tab := CASE WHEN v_has_app THEN 'pipeline' ELSE 'open' END;

    -- Status determination
    IF jsonb_array_length(v_errs) > 0 THEN
      v_status := 'blocked';
    ELSIF jsonb_array_length(v_flags) > 0 THEN
      v_status := 'flagged';
    ELSE
      v_status := 'valid';
    END IF;

    INSERT INTO public.vacancy_import_rows (
      batch_id, row_number, raw_data,
      vcode, group_name, chain, account_name, store_name, position,
      hc_raw, employment_type, request_type_raw, request_type_norm,
      vacant_date_raw, province, city, target_fill_date_raw, hrco, contact_number,
      with_penalty_raw, with_penalty_norm,
      applicant_last_name, applicant_first_name, applicant_middle_name,
      applicant_status, applicant_source,
      migration_source, migration_notes,
      derived_tab, validation_status, validation_errors, validation_flags,
      is_existing_vcode
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_vcode, v_csv_group, v_chain, v_csv_acct, v_store_nm, v_position,
      v_hc_raw, v_emp_type, v_req_raw, v_req_norm,
      v_vacant_raw, v_prov, v_city, v_tfd_raw, v_hrco, v_contact,
      v_pen_raw, v_pen_norm,
      v_app_last, v_app_first, v_app_mid,
      v_app_status, v_app_source,
      v_mig_source, v_mig_notes,
      v_tab, v_status, v_errs, v_flags,
      v_is_existing
    );

    -- Counters
    CASE v_status
      WHEN 'valid'   THEN v_valid   := v_valid   + 1;
      WHEN 'flagged' THEN v_flagged := v_flagged + 1;
      WHEN 'skipped' THEN v_skipped := v_skipped + 1;
      WHEN 'blocked' THEN v_blocked := v_blocked + 1;
      ELSE NULL;
    END CASE;
    IF v_status IN ('valid','flagged') THEN
      IF v_tab = 'pipeline' THEN v_pipeline := v_pipeline + 1;
      ELSE v_open := v_open + 1;
      END IF;
    END IF;
  END LOOP;

  -- Distinct VCODEs duplicated within upload
  SELECT count(*) INTO v_dup_vcode FROM _vib_dup_vcodes;

  -- Aggregate blocking error summary
  SELECT COALESCE(jsonb_object_agg(field_name, cnt), '{}'::jsonb) INTO v_summary
    FROM (
      SELECT (e.value->>'field') AS field_name, count(*) AS cnt
        FROM public.vacancy_import_rows r
        CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
       WHERE r.batch_id = v_batch_id
       GROUP BY 1
    ) s;

  v_final := CASE
    WHEN (v_valid + v_flagged) = 0 THEN 'validation_failed'
    ELSE 'pending_approval'
  END;

  UPDATE public.vacancy_import_batches
     SET total_rows             = v_total,
         valid_rows             = v_valid,
         flagged_rows           = v_flagged,
         skipped_rows           = v_skipped,
         blocked_rows           = v_blocked,
         open_count             = v_open,
         pipeline_count         = v_pipeline,
         duplicate_vcode_count  = v_dup_vcode,
         existing_vcode_count   = v_exist_vcode,
         context_mismatch_count = v_ctx_mismatch,
         error_summary          = v_summary,
         status                 = v_final,
         updated_at             = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id',               v_batch_id,
    'status',                 v_final,
    'total_rows',             v_total,
    'valid_rows',             v_valid,
    'flagged_rows',           v_flagged,
    'skipped_rows',           v_skipped,
    'blocked_rows',           v_blocked,
    'open_count',             v_open,
    'pipeline_count',         v_pipeline,
    'duplicate_vcode_count',  v_dup_vcode,
    'existing_vcode_count',   v_exist_vcode,
    'context_mismatch_count', v_ctx_mismatch,
    'error_summary',          v_summary
  );
END$func$;

REVOKE ALL ON FUNCTION public.submit_vacancy_import(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_vacancy_import(text,uuid,uuid,jsonb) TO authenticated;

COMMENT ON FUNCTION public.submit_vacancy_import IS
  'Dry-run validation for the one-time Import Vacancy migration (OHM2026_1135). '
  'Creates a batch + staged rows; never writes to vacancies or applicants. '
  'RBAC: Encoder / Head Admin / Super Admin.';


-- ============================================================
-- §7  get_vacancy_import_batches / get_vacancy_import_rows
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_vacancy_import_batches(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                     uuid,
  file_name              text,
  status                 text,
  selected_group_id      uuid,
  selected_account_id    uuid,
  group_name             text,
  account_name           text,
  uploaded_by            uuid,
  uploaded_role          text,
  uploaded_at            timestamptz,
  approved_at            timestamptz,
  rejected_at            timestamptz,
  rejection_reason       text,
  commit_error_detail    text,
  total_rows             integer,
  valid_rows             integer,
  flagged_rows           integer,
  skipped_rows           integer,
  blocked_rows           integer,
  open_count             integer,
  pipeline_count         integer,
  duplicate_vcode_count  integer,
  existing_vcode_count   integer,
  context_mismatch_count integer,
  committed_vacancies    integer,
  committed_applicants   integer,
  error_summary          jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT
    b.id, b.file_name, b.status,
    b.selected_group_id, b.selected_account_id,
    g.group_name, a.account_name,
    b.uploaded_by, b.uploaded_role, b.created_at AS uploaded_at,
    b.approved_at, b.rejected_at, b.rejection_reason, b.commit_error_detail,
    b.total_rows, b.valid_rows, b.flagged_rows, b.skipped_rows, b.blocked_rows,
    b.open_count, b.pipeline_count, b.duplicate_vcode_count,
    b.existing_vcode_count, b.context_mismatch_count,
    b.committed_vacancies, b.committed_applicants, b.error_summary
  FROM public.vacancy_import_batches b
  LEFT JOIN public.groups   g ON g.id = b.selected_group_id
  LEFT JOIN public.accounts a ON a.id = b.selected_account_id
  WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
    AND (p_status IS NULL OR b.status = p_status)
  ORDER BY b.created_at DESC;
$func$;

REVOKE ALL ON FUNCTION public.get_vacancy_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_import_batches(text) TO authenticated;


CREATE OR REPLACE FUNCTION public.get_vacancy_import_rows(p_batch_id uuid)
RETURNS SETOF public.vacancy_import_rows
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT r.*
    FROM public.vacancy_import_rows r
   WHERE r.batch_id = p_batch_id
     AND (
       public.i_have_full_access()
       OR EXISTS (
         SELECT 1 FROM public.vacancy_import_batches b
          WHERE b.id = r.batch_id AND b.uploaded_by = auth.uid()
       )
     )
   ORDER BY r.row_number;
$func$;

REVOKE ALL ON FUNCTION public.get_vacancy_import_rows(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_import_rows(uuid) TO authenticated;


-- ============================================================
-- §8  approve_vacancy_import  (commit RPC)
-- ============================================================
-- Inserts vacancies (preserving VCODE) for every valid/flagged row.
-- Pipeline rows additionally seed one applicant. Open rows seed none.
-- Re-checks duplicate VCODE at commit time (defence-in-depth).
-- RBAC: Head Admin / Super Admin only.

CREATE OR REPLACE FUNCTION public.approve_vacancy_import(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_batch      public.vacancy_import_batches%ROWTYPE;
  v_acct_name  text;
  v_grp_name   text;

  v_r          record;
  v_vac_id     uuid;
  v_vac_done   int := 0;
  v_app_done   int := 0;
  v_app_name   text;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.vacancy_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;
  SELECT group_name INTO v_grp_name
    FROM public.groups WHERE id = v_batch.selected_group_id;

  -- ── Commit rows ───────────────────────────────────────────────────────────
  FOR v_r IN
    SELECT *
      FROM public.vacancy_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND vcode IS NOT NULL
     ORDER BY row_number
  LOOP
    -- Defence-in-depth: never duplicate an existing official VCODE.
    IF EXISTS (
      SELECT 1 FROM public.vacancies vv
      WHERE upper(vv.vcode) = upper(v_r.vcode)
        AND COALESCE(vv.is_archived, false) = false
        AND vv.deleted_at IS NULL
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.vacancies (
      vcode, account, position, status,
      account_id, group_id,
      chain, province, store_name, area_city,
      employment_type, request_type, vacancy_type,
      vacant_date, target_fill_date,
      required_headcount, has_penalty,
      hrco_name, hrco_mobile,
      source, source_vacancy_import_batch_id,
      created_by, created_by_user_id, is_archived, has_pending_closure
    ) VALUES (
      v_r.vcode, v_acct_name, v_r.position, 'Open',
      v_batch.selected_account_id, v_batch.selected_group_id,
      v_r.chain, v_r.province, v_r.store_name, v_r.city,
      v_r.employment_type, v_r.request_type_norm,
      CASE WHEN v_r.request_type_norm = 'Replacement' THEN 'Replacement' ELSE 'New' END,
      v_r.vacant_date_raw::date,
      NULLIF(v_r.target_fill_date_raw,'')::date,
      COALESCE(v_r.hc_raw::int, 1), COALESCE(v_r.with_penalty_norm, false),
      v_r.hrco, v_r.contact_number,
      'migration', p_batch_id,
      v_actor, v_actor, false, false
    ) RETURNING id INTO v_vac_id;
    v_vac_done := v_vac_done + 1;

    -- Pipeline rows seed one applicant (presence of applicant ⇒ Pipeline tab)
    IF v_r.derived_tab = 'pipeline' THEN
      v_app_name := trim(
        COALESCE(v_r.applicant_last_name,'') ||
        CASE WHEN v_r.applicant_first_name IS NOT NULL
             THEN ', ' || v_r.applicant_first_name ELSE '' END ||
        CASE WHEN v_r.applicant_middle_name IS NOT NULL
             THEN ' ' || v_r.applicant_middle_name ELSE '' END);
      IF v_app_name = '' OR v_app_name = ',' THEN
        v_app_name := COALESCE(v_r.applicant_first_name, v_r.applicant_last_name, 'Applicant');
      END IF;

      INSERT INTO public.applicants (
        vacancy_vcode, full_name, full_name_snapshot,
        last_name, first_name, middle_name,
        contact_number, status, created_by, updated_by
      ) VALUES (
        v_r.vcode, v_app_name, v_app_name,
        v_r.applicant_last_name, v_r.applicant_first_name, v_r.applicant_middle_name,
        v_r.contact_number, COALESCE(v_r.applicant_status, 'New'),
        v_actor, v_actor
      );
      v_app_done := v_app_done + 1;
    END IF;
  END LOOP;

  -- ── Finalise batch ────────────────────────────────────────────────────────
  UPDATE public.vacancy_import_batches
     SET status               = 'approved',
         approved_by          = v_uid,
         approved_at          = now(),
         committed_vacancies  = v_vac_done,
         committed_applicants = v_app_done,
         updated_at           = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'APPROVAL', p_batch_id,
    jsonb_build_object(
      'vacancies',  v_vac_done,
      'applicants', v_app_done,
      'group',      v_grp_name,
      'account',    v_acct_name
    ));

  RETURN jsonb_build_object(
    'batch_id',             p_batch_id,
    'status',               'approved',
    'vacancies_committed',  v_vac_done,
    'applicants_committed', v_app_done
  );
EXCEPTION WHEN others THEN
  -- Commit failure logging — surface a human-readable failure on the batch.
  UPDATE public.vacancy_import_batches
     SET status              = 'commit_failed',
         commit_error_detail = SQLERRM,
         updated_at          = now()
   WHERE id = p_batch_id;
  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'COMMIT_FAILED', p_batch_id,
    jsonb_build_object('error', SQLERRM));
  RAISE EXCEPTION 'COMMIT_FAILED: %', SQLERRM USING ERRCODE = '22000';
END$func$;

REVOKE ALL ON FUNCTION public.approve_vacancy_import(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_vacancy_import(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_vacancy_import IS
  'Commit RPC for the one-time Import Vacancy migration (OHM2026_1135). '
  'Inserts vacancies preserving VCODEs; pipeline rows seed one applicant. '
  'Records commit failures on the batch. RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §9  reject_vacancy_import
-- ============================================================

CREATE OR REPLACE FUNCTION public.reject_vacancy_import(
  p_batch_id uuid,
  p_reason   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid   uuid := auth.uid();
  v_batch public.vacancy_import_batches%ROWTYPE;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch
    FROM public.vacancy_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed','draft_uploaded') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.vacancy_import_batches
     SET status           = 'rejected',
         rejected_by      = v_uid,
         rejected_at      = now(),
         rejection_reason = p_reason,
         updated_at       = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'REJECTION', p_batch_id,
    jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('batch_id', p_batch_id, 'status', 'rejected');
END$func$;

REVOKE ALL ON FUNCTION public.reject_vacancy_import(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_vacancy_import(uuid,text) TO authenticated;


-- ============================================================
-- §10  get_vacancy_import_template_csv
-- ============================================================
-- GROUP and ACCOUNT are selected in the UI; the CSV still carries
-- GROUP_NAME / ACCOUNT_NAME for the mandatory context-match check.

CREATE OR REPLACE FUNCTION public.get_vacancy_import_template_csv()
RETURNS TABLE(file_name text, content_type text, csv text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY SELECT
    'import_vacancy_template.csv'::text,
    'text/csv'::text,
    E'VCODE,GROUP_NAME,CHAIN,ACCOUNT_NAME,STORE_NAME,POSITION,HC,EMPLOYMENT_TYPE,REQUEST_TYPE,VACANT_DATE,PROVINCE,CITY,TARGET_FILL_DATE,HRCO,CONTACT_NUMBER,WITH_PENALTY,APPLICANT_LAST_NAME,APPLICANT_FIRST_NAME,APPLICANT_MIDDLE_NAME,APPLICANT_STATUS,APPLICANT_SOURCE,MIGRATION_SOURCE,MIGRATION_NOTES\n'
    'PG-DAU-001,Group 2,Super 8,Super 8 Dau,Super 8 Dau,Merchandiser,1,Stationary,Replacement,2026-05-01,Pampanga,Angeles,2026-06-01,Juan HRCO,09171234567,No,,,,,,Google Sheets,Open vacancy migrated\n'
    'PG-DAU-002,Group 2,Super 8,Super 8 Dau,Super 8 Dau,Promoter,1,Stationary,Additional HC,2026-05-03,Pampanga,Angeles,,Juan HRCO,09171234567,Yes,DELA CRUZ,JUAN,SANTOS,For Interview,Walk-in,Google Sheets,Pipeline vacancy with applicant\n';
END$func$;

REVOKE ALL ON FUNCTION public.get_vacancy_import_template_csv() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_import_template_csv() TO authenticated;

COMMENT ON FUNCTION public.get_vacancy_import_template_csv IS
  'Returns the Import Vacancy migration CSV template (OHM2026_1135). '
  'GROUP/ACCOUNT are selected in the UI; GROUP_NAME/ACCOUNT_NAME columns '
  'remain for the mandatory context-match check. HC must always be 1 '
  '(1 VCODE = 1 manpower slot). RBAC: Encoder / HA / SA.';


-- ============================================================
-- §11  Surface request_type in vw_vacancy_detail
-- ============================================================
-- The Vacancy Details Overview reads vw_vacancy_detail first. Recreate the
-- view with request_type APPENDED (CREATE OR REPLACE VIEW only permits new
-- trailing columns) so migrated vacancies show their Request Type.

DROP VIEW IF EXISTS public.vw_vacancy_detail;

CREATE VIEW public.vw_vacancy_detail
WITH (security_invoker = true)
AS
WITH applicant_stats AS (
  SELECT
    a.vacancy_vcode,
    COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status NOT IN ('Failed','Backout','Did Not Report','Rejected by Ops','Confirmed Onboard')
    ) AS active_applicant_count,
    COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
    ) AS confirmed_onboard_count,
    MAX(a.hired_at) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
    ) AS latest_hire_at,
    (COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
        AND COALESCE(a.hired_visible_until, a.hired_at + INTERVAL '7 days') > NOW()
    ) > 0) AS has_recent_hire
  FROM public.applicants a
  GROUP BY a.vacancy_vcode
)
SELECT
  v.id,
  v.vcode,
  v.account,
  v.account_id,
  v.store_name,
  v.store_id,
  v.area_name,
  v.area_city,
  v.position,
  v.position_id,
  v.employment_type,
  v.status,
  CASE
    WHEN (v.is_archived = true) OR (v.status = ANY (ARRAY['Closed','Archived'])) THEN 'Archived'
    WHEN v.status = 'Filled'                                                      THEN 'Hired'
    WHEN COALESCE(s.active_applicant_count, 0) > 0                               THEN 'Pipeline'
    ELSE 'Open'
  END AS derived_status,
  v.source,
  v.source_vacancy_request_id,
  v.source_plantilla_id,
  v.vacancy_type,
  v.urgency_level,
  v.target_fill_date,
  v.required_headcount AS hc_needed,
  v.triggered_by_user_id,
  v.triggered_by_name,
  v.vacant_date,
  (CURRENT_DATE - v.vacant_date) AS aging_days,
  v.created_at,
  v.created_by,
  v.updated_at,
  v.is_archived,
  v.archived_at,
  v.closure_request_status,
  v.has_pending_closure,
  COALESCE(s.active_applicant_count,  0) AS active_applicant_count,
  COALESCE(s.confirmed_onboard_count, 0) AS confirmed_onboard_count,
  s.latest_hire_at,
  v.assigned_encoder_id,
  v.has_reliever,
  v.reliever_name,
  v.requested_by_user_id,
  v.requested_date,
  v.group_id,
  g.group_name,
  v.hrco_user_id,
  v.hrco_name,
  COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
  NULL::text AS triggered_by_role,
  vr.vacancy_type         AS hc_request_type,
  vr.requested_by         AS hc_request_requested_by,
  vr.requested_by_user_id AS hc_request_requested_by_user_id,
  vr.created_at           AS hc_request_date_created,
  vr.no_of_slots          AS hc_request_no_of_slots,
  COALESCE(s.has_recent_hire, false) AS has_recent_hire,
  v.request_type
FROM public.vacancies v
LEFT JOIN applicant_stats          s  ON s.vacancy_vcode   = v.vcode
LEFT JOIN public.groups            g  ON g.id              = v.group_id
LEFT JOIN public.users_profile     up ON up.id             = v.triggered_by_user_id
LEFT JOIN public.vacancy_requests  vr ON vr.id             = v.source_vacancy_request_id
WHERE v.deleted_at IS NULL;
