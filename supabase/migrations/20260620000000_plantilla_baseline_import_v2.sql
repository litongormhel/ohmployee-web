-- ============================================================
-- OHM2026_0053 — Plantilla Baseline Import V2
-- Migration:  20260620000000_plantilla_baseline_import_v2.sql
-- Depends on: plantilla, stores, vacancies, accounts, groups,
--             employee_store_allocations, import_roving_groups
--             (all from 20260603010000_plantilla_import_dry_run_v1.sql)
-- ============================================================
-- Purpose
--   Unified "Plantilla Baseline Import" pipeline that replaces the
--   split Store Master + Employee Plantilla import flows.
--
--   1 upload = 1 account.
--   1 VCODE = 1 employee assignment (unique per upload).
--   Same employee across multiple VCODEs (same account) = roving.
--
--   CSV contract:
--     VCODE,STORE_NAME,AREA_PROVINCE,AREA_CITY,POSITION,EMPLOYMENT_TYPE,
--     REQUIRED_HC,WITH_PENALTY,EMPLOYEE_NO,LAST_NAME,FIRST_NAME,MIDDLE_NAME
--
-- Architecture
--   Dedicated staging tables (plantilla_import_batches,
--   plantilla_import_rows) — no patching of the V1 split tables.
--   Old store_import_batches / employee_import_batches remain as
--   historical artifacts and are NOT modified here.
--
-- Commit lifecycle
--   Phase A: store upsert per distinct VCODE (valid/flagged rows).
--   Phase B: plantilla upsert + employee_store_allocations per
--            distinct employee_no (one active master row per employee).
--   Phase C: import_roving_groups for multi-store employees.
--   Rollback lineage: previous snapshots captured before each upsert.
--
-- Sections
--   §1  plantilla_import_batches table
--   §2  plantilla_import_rows table
--   §3  RLS policies
--   §4  Indexes
--   §5  submit_plantilla_baseline_import  (dry-run validation)
--   §6  get_plantilla_import_preview
--   §7  approve_plantilla_import_batch   (commit RPC)
--   §8  reject_plantilla_import_batch
--   §9  get_plantilla_import_batches / get_plantilla_import_rows
--   §10 get_plantilla_import_template_csv
--
-- Validation queries (run after applying):
--   V1  Tables:
--     SELECT tablename FROM pg_tables WHERE schemaname='public'
--       AND tablename IN ('plantilla_import_batches','plantilla_import_rows');
--   V2  RPCs:
--     SELECT proname FROM pg_proc WHERE proname IN
--       ('submit_plantilla_baseline_import','get_plantilla_import_preview',
--        'approve_plantilla_import_batch','reject_plantilla_import_batch',
--        'get_plantilla_import_batches','get_plantilla_import_rows',
--        'get_plantilla_import_template_csv');
--   V3  Template header must be the unified 12-column format:
--     SELECT csv FROM get_plantilla_import_template_csv();
--   V4  Dry-run must never write plantilla:
--     After submit, SELECT count(*) FROM plantilla
--       WHERE source_baseline_import_batch_id = <batch_id>;  -- expect 0
--   V5  VCODE uniqueness enforced:
--     Submit CSV with duplicate VCODE → both rows blocked.
--   V6  Roving detection:
--     One employee across 3 VCODEs → 3 allocation rows, filled_hc 0.3333 each.
-- ============================================================


-- ============================================================
-- §1  plantilla_import_batches
-- ============================================================

CREATE TABLE IF NOT EXISTS public.plantilla_import_batches (
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
  roving_detected          integer     NOT NULL DEFAULT 0,
  new_stores_count         integer     NOT NULL DEFAULT 0,  -- VCODEs not yet in stores
  existing_stores_count    integer     NOT NULL DEFAULT 0,  -- VCODEs already in stores (upsert)
  existing_employees_count integer     NOT NULL DEFAULT 0,  -- employee_nos already in plantilla
  cross_account_conflicts  integer     NOT NULL DEFAULT 0,
  cross_group_conflicts    integer     NOT NULL DEFAULT 0,
  over_20_store_warnings   integer     NOT NULL DEFAULT 0,
  error_summary            jsonb       NOT NULL DEFAULT '{}'::jsonb,

  -- approval
  approved_by              uuid,
  approved_at              timestamptz,
  committed_stores         integer,
  committed_employees      integer,
  rollback_ready           boolean     NOT NULL DEFAULT false,  -- true once snapshots captured

  -- rejection
  rejected_by              uuid,
  rejected_at              timestamptz,
  rejection_reason         text,

  created_at               timestamptz NOT NULL DEFAULT NOW(),
  updated_at               timestamptz NOT NULL DEFAULT NOW(),

  CONSTRAINT pib_pkey PRIMARY KEY (id),
  CONSTRAINT pib_status_check CHECK (
    status IN ('draft_uploaded','validation_failed','pending_approval','approved','rejected')
  ),
  CONSTRAINT pib_group_fkey
    FOREIGN KEY (selected_group_id) REFERENCES public.groups(id) NOT VALID,
  CONSTRAINT pib_account_fkey
    FOREIGN KEY (selected_account_id) REFERENCES public.accounts(id) NOT VALID
);

COMMENT ON TABLE public.plantilla_import_batches IS
  'Unified Plantilla Baseline Import batch (OHM2026_0053). '
  'Replaces the split store_import_batches + employee_import_batches flows. '
  '1 batch = 1 account. Stages CSV rows for dry-run review; commits on approval.';

ALTER TABLE public.plantilla_import_batches ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.plantilla_import_batches FROM authenticated, anon;


-- ============================================================
-- §2  plantilla_import_rows
-- ============================================================

CREATE TABLE IF NOT EXISTS public.plantilla_import_rows (
  id                         uuid        NOT NULL DEFAULT gen_random_uuid(),
  batch_id                   uuid        NOT NULL,
  row_number                 integer     NOT NULL,
  raw_data                   jsonb       NOT NULL,

  -- Store profile (from CSV)
  vcode                      text,
  store_name                 text,
  area_province              text,
  area_city                  text,
  position                   text,
  employment_type            text,
  required_hc_raw            text,        -- raw string; informational only in V2
  with_penalty_raw           text,        -- raw string; normalised at commit

  -- Employee profile (from CSV)
  employee_no                text,
  last_name                  text,
  first_name                 text,
  middle_name                text,

  -- Resolved references (best-effort during validation)
  resolved_store_id          uuid,        -- existing store matching vcode (may be NULL for new stores)
  resolved_account_id        uuid,
  resolved_group_id          uuid,

  -- Dry-run outcome
  validation_status          text        NOT NULL,  -- valid|flagged|skipped|blocked
  validation_errors          jsonb       NOT NULL DEFAULT '[]'::jsonb,
  validation_flags           jsonb       NOT NULL DEFAULT '[]'::jsonb,
  is_roving                  boolean     NOT NULL DEFAULT false,
  roving_store_count         integer     NOT NULL DEFAULT 0,
  is_new_store               boolean     NOT NULL DEFAULT false,   -- VCODE not found in stores
  is_existing_employee       boolean     NOT NULL DEFAULT false,   -- employee_no found in active plantilla

  -- Rollback lineage (populated at commit by approve RPC)
  previous_store_snapshot    jsonb,       -- stores row before upsert (NULL if new store)
  previous_plantilla_snapshot jsonb,      -- plantilla row before upsert (NULL if new)

  created_at                 timestamptz NOT NULL DEFAULT NOW(),

  CONSTRAINT pir_pkey PRIMARY KEY (id),
  CONSTRAINT pir_status_check CHECK (
    validation_status IN ('valid','flagged','skipped','blocked')
  ),
  CONSTRAINT pir_batch_fkey
    FOREIGN KEY (batch_id) REFERENCES public.plantilla_import_batches(id) ON DELETE CASCADE NOT VALID
);

COMMENT ON TABLE public.plantilla_import_rows IS
  'Staged unified CSV rows for Plantilla Baseline Import (OHM2026_0053). '
  'Contains both store profile + employee profile per row. '
  'previous_*_snapshot fields enable future rollback without data loss.';

ALTER TABLE public.plantilla_import_rows ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.plantilla_import_rows FROM authenticated, anon;


-- ============================================================
-- §3  RLS policies
-- ============================================================
-- Full-access (HA/SA) sees all. Uploaders see their own batches.

CREATE POLICY pib_select ON public.plantilla_import_batches
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR uploaded_by = auth.uid()
  );

CREATE POLICY pir_select ON public.plantilla_import_rows
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR EXISTS (
      SELECT 1 FROM public.plantilla_import_batches b
      WHERE b.id = plantilla_import_rows.batch_id
        AND b.uploaded_by = auth.uid()
    )
  );


-- ============================================================
-- §4  Indexes
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_pib_status
  ON public.plantilla_import_batches(status);
CREATE INDEX IF NOT EXISTS idx_pib_uploaded_by
  ON public.plantilla_import_batches(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_pib_account
  ON public.plantilla_import_batches(selected_account_id);
CREATE INDEX IF NOT EXISTS idx_pib_created_at
  ON public.plantilla_import_batches(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pir_batch
  ON public.plantilla_import_rows(batch_id);
CREATE INDEX IF NOT EXISTS idx_pir_batch_status
  ON public.plantilla_import_rows(batch_id, validation_status);
CREATE INDEX IF NOT EXISTS idx_pir_employee_no
  ON public.plantilla_import_rows(employee_no);
CREATE INDEX IF NOT EXISTS idx_pir_vcode
  ON public.plantilla_import_rows(vcode);


-- Provenance column on plantilla for the unified import batch.
-- Kept separate from source_employee_import_batch_id (references old pipeline).
ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS source_baseline_import_batch_id uuid;
COMMENT ON COLUMN public.plantilla.source_baseline_import_batch_id IS
  'plantilla_import_batches.id that committed this plantilla row via the '
  'unified Plantilla Baseline Import pipeline (OHM2026_0053).';


-- ============================================================
-- §5  submit_plantilla_baseline_import  (dry-run validation)
-- ============================================================
-- Creates a batch + validates rows. NEVER writes to stores or plantilla.
-- Each call creates a fresh batch — re-uploads are safe.
--
-- Validation rules applied per spec:
--   Missing VCODE          → blocked
--   Missing STORE_NAME     → blocked
--   Missing AREA_PROVINCE  → blocked
--   Missing AREA_CITY      → blocked
--   Missing EMPLOYEE_NO    → blocked
--   Missing LAST_NAME      → blocked
--   Missing FIRST_NAME     → blocked
--   Duplicate VCODE in upload  → blocked (all rows with that VCODE)
--   Cross-group VCODE (existing store belongs to different group) → blocked
--   Cross-account employee (active allocation in different account) → blocked
--   Same emp + same VCODE  → skipped
--   Same emp across VCODEs → roving (valid/flagged, not blocked)
--   >20 stores             → flagged (allowed but warned)
--   Existing employee_no   → flagged (upsert on commit — not a blocker)
--   Required HC missing    → flagged

CREATE OR REPLACE FUNCTION public.submit_plantilla_baseline_import(
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
  v_uid        uuid := auth.uid();
  v_role       text := public.get_my_role();
  v_batch_id   uuid;
  v_acct_group uuid;
  v_acct_name  text;

  v_row        jsonb;
  v_idx        int := 0;

  -- Parsed CSV fields
  v_vcode      text;
  v_store_nm   text;
  v_prov       text;
  v_city       text;
  v_position   text;
  v_emp_type   text;
  v_req_hc     text;
  v_pen_raw    text;
  v_emp        text;
  v_last       text;
  v_first      text;
  v_middle     text;

  -- Resolved references
  v_store_id   uuid;
  v_store_acct uuid;
  v_store_grp  uuid;

  -- Per-row state
  v_errs       jsonb;
  v_flags      jsonb;
  v_status     text;
  v_is_roving  boolean;
  v_store_cnt  int;
  v_is_new_store        boolean;
  v_is_existing_emp     boolean;
  v_existing_pid        uuid;

  -- Batch counters
  v_total      int := 0;
  v_valid      int := 0;
  v_flagged    int := 0;
  v_skipped    int := 0;
  v_blocked    int := 0;
  v_roving     int := 0;
  v_new_stores int := 0;
  v_ex_stores  int := 0;
  v_ex_emps    int := 0;
  v_xacct      int := 0;
  v_xgroup     int := 0;
  v_over20     int := 0;

  v_summary    jsonb;
  v_final      text;
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
  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id) THEN
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
  INSERT INTO public.plantilla_import_batches (
    file_name, uploaded_by, uploaded_role,
    selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- ── Pre-passes ───────────────────────────────────────────────────────────

  -- VCODEs that appear more than once in this upload → will block all occurrences.
  DROP TABLE IF EXISTS _pib_dup_vcodes;
  CREATE TEMP TABLE _pib_dup_vcodes ON COMMIT DROP AS
  SELECT upper(trim(elem->>'VCODE')) AS vcode
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1 HAVING count(*) > 1;

  -- Employee→store coverage: how many distinct VCODEs appear per employee_no.
  DROP TABLE IF EXISTS _pib_emp_cov;
  CREATE TEMP TABLE _pib_emp_cov ON COMMIT DROP AS
  SELECT
    upper(trim(elem->>'EMPLOYEE_NO')) AS emp,
    count(DISTINCT upper(trim(elem->>'VCODE'))) AS store_count
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'EMPLOYEE_NO'),'') IS NOT NULL
    AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1;

  -- Seen (employee_no, vcode) pairs for duplicate-skip detection.
  DROP TABLE IF EXISTS _pib_seen_pairs;
  CREATE TEMP TABLE _pib_seen_pairs (emp text, vcode text) ON COMMIT DROP;

  -- ── Row loop ─────────────────────────────────────────────────────────────
  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx      := v_idx + 1;
    v_total    := v_total + 1;
    v_errs     := '[]'::jsonb;
    v_flags    := '[]'::jsonb;
    v_is_roving     := false;
    v_store_cnt     := 0;
    v_is_new_store  := false;
    v_is_existing_emp := false;
    v_store_id := NULL; v_store_acct := NULL; v_store_grp := NULL;
    v_existing_pid := NULL;

    -- Parse CSV fields
    v_vcode    := upper(NULLIF(trim(COALESCE(v_row->>'VCODE','')), ''));
    v_store_nm := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')), '');
    v_prov     := NULLIF(trim(COALESCE(v_row->>'AREA_PROVINCE','')), '');
    v_city     := NULLIF(trim(COALESCE(v_row->>'AREA_CITY','')), '');
    v_position := NULLIF(trim(COALESCE(v_row->>'POSITION','')), '');
    v_emp_type := NULLIF(trim(COALESCE(v_row->>'EMPLOYMENT_TYPE','')), '');
    v_req_hc   := NULLIF(trim(COALESCE(v_row->>'REQUIRED_HC','')), '');
    v_pen_raw  := NULLIF(trim(COALESCE(v_row->>'WITH_PENALTY','')), '');
    v_emp      := upper(NULLIF(trim(COALESCE(v_row->>'EMPLOYEE_NO','')), ''));
    v_last     := NULLIF(trim(COALESCE(v_row->>'LAST_NAME','')), '');
    v_first    := NULLIF(trim(COALESCE(v_row->>'FIRST_NAME','')), '');
    v_middle   := NULLIF(trim(COALESCE(v_row->>'MIDDLE_NAME','')), '');

    -- Required field checks (blocking)
    IF v_vcode    IS NULL THEN v_errs := v_errs || '[{"field":"VCODE","msg":"required"}]'::jsonb; END IF;
    IF v_store_nm IS NULL THEN v_errs := v_errs || '[{"field":"STORE_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_prov     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_PROVINCE","msg":"required"}]'::jsonb; END IF;
    IF v_city     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_CITY","msg":"required"}]'::jsonb; END IF;
    IF v_emp      IS NULL THEN v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"required"}]'::jsonb; END IF;
    IF v_last     IS NULL THEN v_errs := v_errs || '[{"field":"LAST_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_first    IS NULL THEN v_errs := v_errs || '[{"field":"FIRST_NAME","msg":"required"}]'::jsonb; END IF;

    -- Duplicate VCODE within upload → block
    IF v_vcode IS NOT NULL AND EXISTS (SELECT 1 FROM _pib_dup_vcodes WHERE vcode = v_vcode) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"duplicate VCODE in upload — each VCODE must appear exactly once"}]'::jsonb;
    END IF;

    -- Optional field flags
    IF v_req_hc IS NULL THEN
      v_flags := v_flags || '[{"flag":"missing_required_hc","msg":"REQUIRED_HC not provided"}]'::jsonb;
    END IF;

    -- Duplicate (same emp + same vcode already in this upload) → skip
    IF v_emp IS NOT NULL AND v_vcode IS NOT NULL
       AND EXISTS (SELECT 1 FROM _pib_seen_pairs WHERE emp = v_emp AND vcode = v_vcode)
    THEN
      v_status := 'skipped';
      v_flags  := v_flags || '[{"flag":"duplicate_emp_vcode","msg":"same employee+VCODE already processed — skipped"}]'::jsonb;
    ELSE

      -- Resolve existing store by VCODE
      IF v_vcode IS NOT NULL THEN
        SELECT s.id, s.account_id, s.group_id
          INTO v_store_id, v_store_acct, v_store_grp
          FROM public.stores s
         WHERE upper(s.vcode) = v_vcode AND s.status = 'active'
         ORDER BY s.created_at LIMIT 1;
      END IF;
      v_is_new_store := (v_store_id IS NULL);

      -- Cross-group: existing store belongs to a different group → blocked
      IF v_store_id IS NOT NULL AND v_store_grp IS NOT NULL
         AND v_store_grp <> p_group_id THEN
        v_errs := v_errs || '[{"field":"VCODE","msg":"cross-group: store belongs to a different group"}]'::jsonb;
        v_xgroup := v_xgroup + 1;
      END IF;

      -- Cross-account: employee already has active allocations in a different account
      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.employee_store_allocations a
        WHERE a.employee_no = v_emp AND a.is_active
          AND a.account_id IS NOT NULL AND a.account_id <> p_account_id
      ) THEN
        v_errs  := v_errs  || '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee already deployed in another account — blocked"}]'::jsonb;
        v_flags := v_flags || '[{"flag":"cross_account","msg":"review by Encoder / Head Admin"}]'::jsonb;
        v_xacct := v_xacct + 1;
      END IF;

      -- Roving detection (employee appears across multiple VCODEs in this upload)
      IF v_emp IS NOT NULL THEN
        SELECT store_count INTO v_store_cnt FROM _pib_emp_cov WHERE emp = v_emp;
        v_store_cnt := COALESCE(v_store_cnt, 0);
        IF v_store_cnt > 1 THEN
          v_is_roving := true;
          v_flags := v_flags || jsonb_build_array(
            jsonb_build_object('flag','roving','msg',
              'roving employee: ' || v_store_cnt || ' stores')
          );
        END IF;
        IF v_store_cnt > 20 THEN
          v_flags := v_flags || jsonb_build_array(
            jsonb_build_object('flag','over_20_stores','msg',
              v_store_cnt || ' stores (>20 allowed but flagged)')
          );
          v_over20 := v_over20 + 1;
        END IF;
      END IF;

      -- Existing employee detection (informational flag — not a blocker)
      IF v_emp IS NOT NULL THEN
        SELECT id INTO v_existing_pid
          FROM public.plantilla
         WHERE employee_no = v_emp
           AND is_deleted = false
           AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
         LIMIT 1;
        v_is_existing_emp := (v_existing_pid IS NOT NULL);
        IF v_is_existing_emp THEN
          v_flags := v_flags || '[{"flag":"existing_employee","msg":"employee_no already in active plantilla — will upsert on commit"}]'::jsonb;
          v_ex_emps := v_ex_emps + 1;
        END IF;
      END IF;

      -- Status determination
      IF jsonb_array_length(v_errs) > 0 THEN
        v_status := 'blocked';
      ELSIF jsonb_array_length(v_flags) > 0 THEN
        v_status := 'flagged';
      ELSE
        v_status := 'valid';
      END IF;

      -- Track seen pair
      IF v_emp IS NOT NULL AND v_vcode IS NOT NULL THEN
        INSERT INTO _pib_seen_pairs(emp, vcode) VALUES (v_emp, v_vcode);
      END IF;

      -- Track store novelty counters (per distinct VCODE, only once per upload)
      IF v_vcode IS NOT NULL AND v_status <> 'blocked' THEN
        IF v_is_new_store THEN v_new_stores := v_new_stores + 1;
        ELSE v_ex_stores := v_ex_stores + 1;
        END IF;
      END IF;

    END IF; -- end non-skip branch

    INSERT INTO public.plantilla_import_rows (
      batch_id, row_number, raw_data,
      vcode, store_name, area_province, area_city, position, employment_type,
        required_hc_raw, with_penalty_raw,
      employee_no, last_name, first_name, middle_name,
      resolved_store_id, resolved_account_id, resolved_group_id,
      validation_status, validation_errors, validation_flags,
      is_roving, roving_store_count, is_new_store, is_existing_employee
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_vcode, v_store_nm, v_prov, v_city, v_position, v_emp_type,
        v_req_hc, v_pen_raw,
      v_emp, v_last, v_first, v_middle,
      v_store_id, v_store_acct, v_store_grp,
      v_status, v_errs, v_flags,
      v_is_roving, v_store_cnt, v_is_new_store, v_is_existing_emp
    );

    -- Counters
    CASE v_status
      WHEN 'valid'   THEN v_valid    := v_valid    + 1;
      WHEN 'flagged' THEN v_flagged  := v_flagged  + 1;
      WHEN 'skipped' THEN v_skipped  := v_skipped  + 1;
      WHEN 'blocked' THEN v_blocked  := v_blocked  + 1;
      ELSE NULL;
    END CASE;

  END LOOP;

  -- Distinct roving employees (>1 store, with at least one committable row)
  SELECT count(*) INTO v_roving
    FROM _pib_emp_cov WHERE store_count > 1;

  -- Deduplicate store novelty (counted once per VCODE above — correct as-is)
  -- Correct existing_employees: was incremented once per row; deduplicate by emp
  SELECT count(DISTINCT employee_no) INTO v_ex_emps
    FROM public.plantilla_import_rows r
   WHERE r.batch_id = v_batch_id
     AND r.validation_status IN ('valid','flagged')
     AND r.is_existing_employee;

  -- Aggregate blocking error summary
  SELECT COALESCE(jsonb_object_agg(field_name, cnt), '{}'::jsonb) INTO v_summary
    FROM (
      SELECT (e.value->>'field') AS field_name, count(*) AS cnt
        FROM public.plantilla_import_rows r
        CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
       WHERE r.batch_id = v_batch_id
       GROUP BY 1
    ) s;

  v_final := CASE
    WHEN (v_valid + v_flagged) = 0 THEN 'validation_failed'
    ELSE 'pending_approval'
  END;

  UPDATE public.plantilla_import_batches
     SET total_rows               = v_total,
         valid_rows               = v_valid,
         flagged_rows             = v_flagged,
         skipped_rows             = v_skipped,
         blocked_rows             = v_blocked,
         roving_detected          = v_roving,
         new_stores_count         = v_new_stores,
         existing_stores_count    = v_ex_stores,
         existing_employees_count = v_ex_emps,
         cross_account_conflicts  = v_xacct,
         cross_group_conflicts    = v_xgroup,
         over_20_store_warnings   = v_over20,
         error_summary            = v_summary,
         status                   = v_final,
         updated_at               = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id',                v_batch_id,
    'status',                  v_final,
    'total_rows',              v_total,
    'valid_rows',              v_valid,
    'flagged_rows',            v_flagged,
    'skipped_rows',            v_skipped,
    'blocked_rows',            v_blocked,
    'roving_detected',         v_roving,
    'new_stores_count',        v_new_stores,
    'existing_stores_count',   v_ex_stores,
    'existing_employees_count',v_ex_emps,
    'cross_account_conflicts', v_xacct,
    'cross_group_conflicts',   v_xgroup,
    'over_20_store_warnings',  v_over20,
    'error_summary',           v_summary
  );
END$func$;

REVOKE ALL ON FUNCTION public.submit_plantilla_baseline_import(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_plantilla_baseline_import(text,uuid,uuid,jsonb) TO authenticated;

COMMENT ON FUNCTION public.submit_plantilla_baseline_import IS
  'Unified dry-run validation for Plantilla Baseline Import. '
  'Creates a batch + staged rows; never writes to stores or plantilla. '
  'RBAC: Encoder / Head Admin / Super Admin.';


-- ============================================================
-- §6  get_plantilla_import_preview
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_plantilla_import_preview(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_batch public.plantilla_import_batches%ROWTYPE;
BEGIN
  SELECT * INTO v_batch FROM public.plantilla_import_batches WHERE id = p_batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  IF NOT (public.i_have_full_access() OR v_batch.uploaded_by = auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'batch_id',                v_batch.id,
    'file_name',               v_batch.file_name,
    'status',                  v_batch.status,
    'selected_group_id',       v_batch.selected_group_id,
    'selected_account_id',     v_batch.selected_account_id,
    'counts', jsonb_build_object(
      'total_rows',              v_batch.total_rows,
      'valid_rows',              v_batch.valid_rows,
      'flagged_rows',            v_batch.flagged_rows,
      'skipped_rows',            v_batch.skipped_rows,
      'blocked_rows',            v_batch.blocked_rows,
      'roving_detected',         v_batch.roving_detected,
      'new_stores_count',        v_batch.new_stores_count,
      'existing_stores_count',   v_batch.existing_stores_count,
      'existing_employees_count',v_batch.existing_employees_count,
      'cross_account_conflicts', v_batch.cross_account_conflicts,
      'cross_group_conflicts',   v_batch.cross_group_conflicts,
      'over_20_store_warnings',  v_batch.over_20_store_warnings
    ),
    'error_summary', v_batch.error_summary,
    'detected_roving', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'employee_no', t.emp,
        'store_count', t.cnt,
        'filled_hc_per_store', round(1.0 / t.cnt, 4)
      )), '[]'::jsonb)
      FROM (
        SELECT employee_no AS emp, count(DISTINCT vcode) AS cnt
          FROM public.plantilla_import_rows
         WHERE batch_id = p_batch_id
           AND validation_status IN ('valid','flagged')
           AND employee_no IS NOT NULL
         GROUP BY employee_no HAVING count(DISTINCT vcode) > 1
      ) t
    ),
    'blocked_preview', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'row_number',  r.row_number,
        'employee_no', r.employee_no,
        'vcode',       r.vcode,
        'store_name',  r.store_name,
        'errors',      r.validation_errors
      )), '[]'::jsonb)
      FROM public.plantilla_import_rows r
      WHERE r.batch_id = p_batch_id AND r.validation_status = 'blocked'
    ),
    'store_summary', jsonb_build_object(
      'new_stores',      v_batch.new_stores_count,
      'existing_stores', v_batch.existing_stores_count
    )
  );
END$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_preview(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_preview(uuid) TO authenticated;


-- ============================================================
-- §7  approve_plantilla_import_batch  (commit RPC)
-- ============================================================
-- Phase A: upsert stores per distinct committable VCODE.
--          Captures pre-commit snapshot for rollback lineage.
-- Phase B: upsert plantilla + employee_store_allocations per
--          distinct employee_no. Roving employees get fractional HC.
-- RBAC: Head Admin / Super Admin only.

CREATE OR REPLACE FUNCTION public.approve_plantilla_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid := public.get_current_profile_id();
  v_batch      public.plantilla_import_batches%ROWTYPE;
  v_acct_name  text;

  -- Phase A locals
  v_srow       record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_emp_type_norm      text;
  v_stores_done        int := 0;

  -- Phase B locals
  v_emp_rec       record;
  v_store_rec     record;
  v_plantilla_id  uuid;
  v_roving_id     uuid;
  v_store_cnt     int;
  v_filled        numeric(8,4);
  v_emp_name      text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- ── Temp store commit map ─────────────────────────────────────────────────
  -- Maps each committed VCODE → its store_id (used in Phase B allocation rows).
  DROP TABLE IF EXISTS _pib_store_map;
  CREATE TEMP TABLE _pib_store_map (
    vcode    text,
    store_id uuid,
    is_new   boolean
  ) ON COMMIT DROP;

  -- ── Phase A: Store upsert ─────────────────────────────────────────────────
  FOR v_srow IN
    SELECT DISTINCT ON (vcode)
           vcode, store_name, area_province, area_city,
           employment_type, with_penalty_raw, row_number
      FROM public.plantilla_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND vcode IS NOT NULL
     ORDER BY vcode, row_number
  LOOP
    -- Resolve employment type
    v_emp_type_norm := CASE
      WHEN lower(COALESCE(v_srow.employment_type,'')) IN ('stationary','roving')
        THEN lower(v_srow.employment_type)
      ELSE NULL
    END;

    -- Resolve penalty
    v_pen_bool := CASE
      WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1') THEN true
      WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('no','n','false','0') THEN false
      ELSE NULL
    END;

    -- Capture existing snapshot before any mutation
    SELECT to_jsonb(s.*) INTO v_old_store_snap
      FROM public.stores s
     WHERE upper(s.vcode) = upper(v_srow.vcode) AND s.status = 'active'
     ORDER BY s.created_at LIMIT 1;

    IF v_old_store_snap IS NULL THEN
      -- New store: insert
      INSERT INTO public.stores (
        vcode, store_name, area_province, area_city,
        employment_type, with_penalty,
        group_id, account_id, status,
        created_by, updated_by, approved_by, approved_at, source_import_id
      ) VALUES (
        v_srow.vcode, v_srow.store_name, v_srow.area_province, v_srow.area_city,
        v_emp_type_norm, v_pen_bool,
        v_batch.selected_group_id, v_batch.selected_account_id, 'active',
        v_uid, v_uid, v_uid, now(), p_batch_id
      ) RETURNING id INTO v_new_store_id;

      INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_new_store_id, true);
    ELSE
      -- Existing store: update store profile
      v_existing_store_id := (v_old_store_snap->>'id')::uuid;
      UPDATE public.stores
         SET store_name     = v_srow.store_name,
             area_province  = v_srow.area_province,
             area_city      = v_srow.area_city,
             employment_type = COALESCE(v_emp_type_norm, employment_type),
             with_penalty    = COALESCE(v_pen_bool, with_penalty),
             updated_by     = v_uid,
             approved_by    = v_uid,
             approved_at    = now(),
             source_import_id = p_batch_id
       WHERE id = v_existing_store_id;

      INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_existing_store_id, false);
    END IF;

    -- Write rollback snapshot into every matching row
    UPDATE public.plantilla_import_rows
       SET previous_store_snapshot = v_old_store_snap
     WHERE batch_id = p_batch_id
       AND upper(vcode) = upper(v_srow.vcode)
       AND validation_status IN ('valid','flagged');

    v_stores_done := v_stores_done + 1;
  END LOOP;

  -- ── Phase B: Employee / plantilla upsert ─────────────────────────────────
  FOR v_emp_rec IN
    SELECT employee_no,
           count(DISTINCT vcode)        AS store_count,
           (array_agg(last_name))[1]    AS last_name,
           (array_agg(first_name))[1]   AS first_name,
           (array_agg(middle_name))[1]  AS middle_name
      FROM public.plantilla_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND employee_no IS NOT NULL
     GROUP BY employee_no
  LOOP
    v_employees_done := v_employees_done + 1;
    v_store_cnt := v_emp_rec.store_count;
    v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);
    v_emp_name  := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                   || COALESCE(' ' || v_emp_rec.middle_name, '');

    -- Roving group for multi-store employees
    v_roving_id := NULL;
    IF v_store_cnt > 1 THEN
      INSERT INTO public.import_roving_groups (
        employee_no, account_id, group_id, account_name, label,
        active_store_count, filled_hc_per_store, source_import_batch_id, created_by
      ) VALUES (
        v_emp_rec.employee_no,
        v_batch.selected_account_id, v_batch.selected_group_id,
        v_acct_name, v_emp_name || ' — Roving',
        v_store_cnt, v_filled, p_batch_id, v_actor
      ) RETURNING id INTO v_roving_id;
    END IF;

    -- Upsert plantilla master row (one active row per employee)
    SELECT id INTO v_plantilla_id
      FROM public.plantilla
     WHERE employee_no = v_emp_rec.employee_no
       AND is_deleted = false
       AND status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
     LIMIT 1;

    -- Capture pre-commit plantilla snapshot for rollback
    SELECT to_jsonb(p.*) INTO v_old_plant_snap
      FROM public.plantilla p WHERE id = v_plantilla_id;

    IF v_plantilla_id IS NULL THEN
      -- New employee: insert
      INSERT INTO public.plantilla (
        employee_name, employee_no, emploc_no, account, status,
        account_id, last_name, first_name, middle_name,
        roving_assignment_id, is_pool_employee,
        vcode, store_id, store_name,
        source_baseline_import_batch_id, created_by, moved_by_user_id
      )
      SELECT
        v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no,
        v_acct_name, 'Active',
        v_batch.selected_account_id,
        v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
        NULL, false,
        -- Single-store: pin store; roving: master store is NULL
        CASE WHEN v_store_cnt = 1 THEN r.vcode ELSE NULL END,
        CASE WHEN v_store_cnt = 1 THEN sm.store_id ELSE NULL END,
        CASE WHEN v_store_cnt = 1 THEN r.store_name ELSE NULL END,
        p_batch_id, v_actor, v_actor
      FROM (
        SELECT vcode, store_name
          FROM public.plantilla_import_rows
         WHERE batch_id = p_batch_id AND employee_no = v_emp_rec.employee_no
           AND validation_status IN ('valid','flagged')
         ORDER BY row_number LIMIT 1
      ) r
      LEFT JOIN _pib_store_map sm ON sm.vcode = upper(r.vcode)
      RETURNING id INTO v_plantilla_id;
    ELSE
      -- Existing employee: refresh name/linkage
      UPDATE public.plantilla
         SET employee_name = v_emp_name,
             last_name     = v_emp_rec.last_name,
             first_name    = v_emp_rec.first_name,
             middle_name   = v_emp_rec.middle_name,
             updated_at    = now(),
             source_baseline_import_batch_id = p_batch_id
       WHERE id = v_plantilla_id;
    END IF;

    -- Link roving group to plantilla
    IF v_roving_id IS NOT NULL THEN
      UPDATE public.import_roving_groups SET plantilla_id = v_plantilla_id
       WHERE id = v_roving_id;
    END IF;

    -- Write plantilla snapshot into matching rows
    UPDATE public.plantilla_import_rows
       SET previous_plantilla_snapshot = v_old_plant_snap
     WHERE batch_id = p_batch_id
       AND employee_no = v_emp_rec.employee_no
       AND validation_status IN ('valid','flagged');

    -- Supersede prior active allocations (effective dating)
    UPDATE public.employee_store_allocations
       SET is_active = false, effective_end = CURRENT_DATE
     WHERE employee_no = v_emp_rec.employee_no AND is_active;

    -- Create one allocation row per distinct VCODE for this employee
    FOR v_store_rec IN
      SELECT DISTINCT ON (pir.vcode)
             pir.vcode, sm.store_id,
             pir.store_name, pir.resolved_account_id, pir.resolved_group_id
        FROM public.plantilla_import_rows pir
        LEFT JOIN _pib_store_map sm ON sm.vcode = upper(pir.vcode)
       WHERE pir.batch_id = p_batch_id
         AND pir.employee_no = v_emp_rec.employee_no
         AND pir.validation_status IN ('valid','flagged')
       ORDER BY pir.vcode, pir.row_number
    LOOP
      INSERT INTO public.employee_store_allocations (
        plantilla_id, employee_no, roving_group_id,
        store_id, vcode, store_name,
        account_id, group_id,
        filled_hc, active_store_count,
        effective_start, is_active,
        source_import_batch_id, created_by
      ) VALUES (
        v_plantilla_id, v_emp_rec.employee_no, v_roving_id,
        v_store_rec.store_id, v_store_rec.vcode, v_store_rec.store_name,
        COALESCE(v_store_rec.resolved_account_id, v_batch.selected_account_id),
        COALESCE(v_store_rec.resolved_group_id,   v_batch.selected_group_id),
        v_filled, v_store_cnt,
        CURRENT_DATE, true,
        p_batch_id, v_actor
      );
      v_alloc_done := v_alloc_done + 1;
    END LOOP;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'plantilla_import', 'COMMIT', v_plantilla_id,
      jsonb_build_object(
        'employee_no',        v_emp_rec.employee_no,
        'store_count',        v_store_cnt,
        'filled_hc_per_store',v_filled,
        'roving',             (v_roving_id IS NOT NULL),
        'batch_id',           p_batch_id
      ));
  END LOOP;

  -- ── Finalise batch ────────────────────────────────────────────────────────
  UPDATE public.plantilla_import_batches
     SET status             = 'approved',
         approved_by        = v_uid,
         approved_at        = now(),
         committed_stores   = v_stores_done,
         committed_employees= v_employees_done,
         rollback_ready     = true,
         updated_at         = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_batches', 'APPROVAL', p_batch_id,
    jsonb_build_object(
      'stores',    v_stores_done,
      'employees', v_employees_done,
      'allocations', v_alloc_done
    ));

  RETURN jsonb_build_object(
    'batch_id',           p_batch_id,
    'status',             'approved',
    'stores_committed',   v_stores_done,
    'employees_committed',v_employees_done,
    'allocations_created',v_alloc_done
  );
END$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_plantilla_import_batch IS
  'Commit RPC for Plantilla Baseline Import. '
  'Phase A upserts stores; Phase B upserts plantilla + allocations. '
  'Rollback snapshots written before each upsert for future reversal. '
  'RBAC: Head Admin / Super Admin only.';


-- ============================================================
-- §8  reject_plantilla_import_batch
-- ============================================================

CREATE OR REPLACE FUNCTION public.reject_plantilla_import_batch(
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
  v_batch public.plantilla_import_batches%ROWTYPE;
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
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed','draft_uploaded') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.plantilla_import_batches
     SET status           = 'rejected',
         rejected_by      = v_uid,
         rejected_at      = now(),
         rejection_reason = p_reason,
         updated_at       = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_batches', 'REJECTION', p_batch_id,
    jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('batch_id', p_batch_id, 'status', 'rejected');
END$func$;

REVOKE ALL ON FUNCTION public.reject_plantilla_import_batch(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_plantilla_import_batch(uuid,text) TO authenticated;


-- ============================================================
-- §9  get_plantilla_import_batches / get_plantilla_import_rows
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_plantilla_import_batches(
  p_status text DEFAULT NULL
)
RETURNS SETOF public.plantilla_import_batches
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT b.*
    FROM public.plantilla_import_batches b
   WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
     AND (p_status IS NULL OR b.status = p_status)
   ORDER BY b.created_at DESC;
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_batches(text) TO authenticated;


CREATE OR REPLACE FUNCTION public.get_plantilla_import_rows(p_batch_id uuid)
RETURNS SETOF public.plantilla_import_rows
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT r.*
    FROM public.plantilla_import_rows r
   WHERE r.batch_id = p_batch_id
     AND (
       public.i_have_full_access()
       OR EXISTS (
         SELECT 1 FROM public.plantilla_import_batches b
          WHERE b.id = r.batch_id AND b.uploaded_by = auth.uid()
       )
     )
   ORDER BY r.row_number;
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_rows(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_rows(uuid) TO authenticated;


-- ============================================================
-- §10  get_plantilla_import_template_csv
-- ============================================================
-- Unified 12-column template. GROUP and ACCOUNT are NOT in the CSV;
-- they are selected in the UI and derived server-side.

CREATE OR REPLACE FUNCTION public.get_plantilla_import_template_csv()
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
    'import_plantilla_baseline_template.csv'::text,
    'text/csv'::text,
    E'VCODE,STORE_NAME,AREA_PROVINCE,AREA_CITY,POSITION,EMPLOYMENT_TYPE,REQUIRED_HC,WITH_PENALTY,EMPLOYEE_NO,LAST_NAME,FIRST_NAME,MIDDLE_NAME\n'
    'PG-DAU-001,Super 8 Dau,Pampanga,Angeles,Merchandiser,stationary,1,yes,10001,DELA CRUZ,JUAN,SANTOS\n'
    'PG-DAU-002,Super 8 Dau,Pampanga,Angeles,Promoter,stationary,1,no,10002,REYES,MARIA,\n'
    'PG-SF-001,Puregold San Fernando,Pampanga,San Fernando,Merchandiser,stationary,1,yes,10003,SANTOS,JOSE,CRUZ\n';
END$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_template_csv() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_template_csv() TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_import_template_csv IS
  'Returns the unified Plantilla Baseline Import CSV template (12 columns). '
  'GROUP and ACCOUNT are NOT in the CSV — they are selected in the UI. '
  'RBAC: Encoder / Head Admin / Super Admin.';
