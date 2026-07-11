-- ============================================================
-- OHM2026_0054 — Plantilla Import: Validation Finalization + Commit Lifecycle
-- Migration:  20260621000000_plantilla_import_validation_commit_finalize.sql
-- Depends on: 20260620000000_plantilla_baseline_import_v2.sql
--             20260603010000_plantilla_import_dry_run_v1.sql
-- ============================================================
-- Purpose
--   Finalizes the Plantilla Baseline Import pipeline (OHM2026_0053):
--   • Adds commit_failed batch state + error capture column
--   • Adds missing_from_upload_count batch column
--   • Creates plantilla_import_commit_snapshots for rollback preparation
--   • Adds performance indexes (vcode active-owner, group/account active-emp)
--   • Replaces submit_plantilla_baseline_import with finalized validation:
--       – VCODE already actively assigned to a different employee → blocked
--       – Employee with active allocations in a different group → blocked
--       – Employee exists in plantilla under a different account → blocked
--       – HC mismatch per (store_name, position) → flagged (post-loop)
--       – Existing active employees not in upload → missing_from_upload_count
--   • Replaces approve_plantilla_import_batch with:
--       – Inner BEGIN..EXCEPTION → commit_failed on error, no partial commit
--       – Scope-limited allocation supersede (account-scoped, not global)
--       – Centralized commit snapshots in plantilla_import_commit_snapshots
--       – Pre-commit committable-row guard
--
-- Replay safety
--   All DDL uses IF NOT EXISTS / OR REPLACE. Idempotent on re-apply.
--   approved batch cannot re-commit (status guard).
--   commit_failed batch can be inspected; re-approval requires manual reset.
--
-- Sections
--   §1  Batch table: extend status constraint + add columns
--   §2  plantilla_import_commit_snapshots table + RLS
--   §3  Additional performance indexes
--   §4  submit_plantilla_baseline_import  (finalized)
--   §5  approve_plantilla_import_batch    (commit_failed + snapshots)
--
-- Validation checklist (run after applying)
--   V1  Status constraint includes commit_failed:
--         SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--           WHERE conname = 'pib_status_check';
--   V2  Columns added:
--         SELECT column_name FROM information_schema.columns
--           WHERE table_name='plantilla_import_batches'
--           AND column_name IN ('commit_error_detail','missing_from_upload_count');
--   V3  Snapshot table exists:
--         SELECT tablename FROM pg_tables WHERE tablename='plantilla_import_commit_snapshots';
--   V4  RPCs replaced (check signature):
--         SELECT proname, prosrc IS NOT NULL FROM pg_proc
--           WHERE proname IN ('submit_plantilla_baseline_import','approve_plantilla_import_batch');
--   V5  Duplicate VCODE blocked:
--         Submit CSV with two rows sharing same VCODE → both rows = blocked.
--   V6  VCODE already-assigned blocked:
--         If employee_store_allocations has active VCODE X for EMP-A, submitting
--         EMP-B with VCODE X → blocked with "VCODE already actively assigned..."
--   V7  Cross-group employee blocked:
--         Employee with active allocation in group G1, upload to group G2 → blocked.
--   V8  Roving fractional HC:
--         One employee across 3 VCODEs → 3 allocation rows, filled_hc=0.3333 each.
--   V9  Approval cannot double commit:
--         approve on approved batch → INVALID_STATE exception.
--   V10 commit_failed on forced error:
--         (Trigger FK violation during commit) → batch.status=commit_failed,
--         commit_error_detail populated, no partial stores/plantilla written.
-- ============================================================


-- ============================================================
-- §1  plantilla_import_batches: status constraint + new columns
-- ============================================================

-- Extend status values to include commit_failed
ALTER TABLE public.plantilla_import_batches
  DROP CONSTRAINT IF EXISTS pib_status_check;

ALTER TABLE public.plantilla_import_batches
  ADD CONSTRAINT pib_status_check CHECK (
    status IN (
      'draft_uploaded',
      'validation_failed',
      'pending_approval',
      'approved',
      'rejected',
      'commit_failed'
    )
  );

-- Error detail captured by the approve exception handler
ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS commit_error_detail text;

-- Informational: active employees in the target account absent from this upload
ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS missing_from_upload_count integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.plantilla_import_batches.commit_error_detail IS
  'Populated when status=commit_failed: SQL error message from the approve RPC exception handler.';
COMMENT ON COLUMN public.plantilla_import_batches.missing_from_upload_count IS
  'Active employees in the target account that were not included in this upload (informational only).';


-- ============================================================
-- §2  plantilla_import_commit_snapshots
-- ============================================================
-- Centralised rollback lineage table.
-- Supplements the row-level previous_*_snapshot fields in plantilla_import_rows.
-- One row per entity mutated during an approved commit.

CREATE TABLE IF NOT EXISTS public.plantilla_import_commit_snapshots (
  id                uuid        NOT NULL DEFAULT gen_random_uuid(),
  batch_id          uuid        NOT NULL,
  import_row_id     uuid,                  -- plantilla_import_rows.id; NULL for batch-level entries
  entity_type       text        NOT NULL,  -- 'store' | 'plantilla' | 'allocation'
  entity_id         uuid,                  -- PK of the mutated row after upsert
  action            text        NOT NULL,  -- 'insert' | 'update'
  previous_snapshot jsonb,                 -- row state before mutation (NULL for new inserts)
  committed_by      uuid,
  committed_at      timestamptz NOT NULL DEFAULT NOW(),

  CONSTRAINT pics_pkey         PRIMARY KEY (id),
  CONSTRAINT pics_entity_check CHECK (entity_type IN ('store','plantilla','allocation')),
  CONSTRAINT pics_action_check CHECK (action IN ('insert','update')),
  CONSTRAINT pics_batch_fkey
    FOREIGN KEY (batch_id)
    REFERENCES public.plantilla_import_batches(id) ON DELETE CASCADE NOT VALID
);

COMMENT ON TABLE public.plantilla_import_commit_snapshots IS
  'Rollback lineage for Plantilla Baseline Import commits (OHM2026_0054). '
  'One row per entity mutated (store/plantilla/allocation). '
  'previous_snapshot is NULL for new inserts. Enables a future rollback RPC.';

ALTER TABLE public.plantilla_import_commit_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.plantilla_import_commit_snapshots FROM authenticated, anon;

DROP POLICY IF EXISTS pics_select ON public.plantilla_import_commit_snapshots;
CREATE POLICY pics_select ON public.plantilla_import_commit_snapshots
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR EXISTS (
      SELECT 1 FROM public.plantilla_import_batches b
      WHERE b.id = plantilla_import_commit_snapshots.batch_id
        AND b.uploaded_by = auth.uid()
    )
  );


-- ============================================================
-- §3  Additional performance indexes
-- ============================================================

-- VCODE → active owner lookup (used in validation: "VCODE already assigned")
CREATE INDEX IF NOT EXISTS idx_esa_vcode_active
  ON public.employee_store_allocations(vcode)
  WHERE (is_active AND vcode IS NOT NULL);

-- Employee + group active (cross-group validation)
CREATE INDEX IF NOT EXISTS idx_esa_emp_group_active
  ON public.employee_store_allocations(employee_no, group_id)
  WHERE is_active;

-- Employee + account active (cross-account validation — fast path)
CREATE INDEX IF NOT EXISTS idx_esa_emp_account_active
  ON public.employee_store_allocations(employee_no, account_id)
  WHERE is_active;

-- Source import batch on allocations (lineage traversal)
CREATE INDEX IF NOT EXISTS idx_esa_source_batch
  ON public.employee_store_allocations(source_import_batch_id)
  WHERE source_import_batch_id IS NOT NULL;

-- Batch group filter
CREATE INDEX IF NOT EXISTS idx_pib_group
  ON public.plantilla_import_batches(selected_group_id);

-- Batch queue filter: status + account
CREATE INDEX IF NOT EXISTS idx_pib_status_acct
  ON public.plantilla_import_batches(status, selected_account_id);

-- Commit snapshot batch lookup
CREATE INDEX IF NOT EXISTS idx_pics_batch
  ON public.plantilla_import_commit_snapshots(batch_id);

-- Commit snapshot entity lookup (for rollback by entity)
CREATE INDEX IF NOT EXISTS idx_pics_entity
  ON public.plantilla_import_commit_snapshots(entity_type, entity_id)
  WHERE entity_id IS NOT NULL;


-- ============================================================
-- §4  submit_plantilla_baseline_import  (finalized validation)
-- ============================================================
-- Replaces the OHM2026_0053 version with all missing validation rules:
--
--   NEW rules added vs OHM2026_0053:
--   • VCODE already actively assigned to a different employee → blocked
--   • Employee has active allocations in a different group → blocked
--   • Employee exists in plantilla under a different account → blocked
--   • HC mismatch per (store_name, position) → flagged (post-loop sweep)
--   • missing_from_upload_count stored on batch

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
  v_errs            jsonb;
  v_flags           jsonb;
  v_status          text;
  v_is_roving       boolean;
  v_store_cnt       int;
  v_is_new_store    boolean;
  v_is_existing_emp boolean;
  v_existing_pid    uuid;

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
  v_missing    int := 0;

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

  -- [A] Duplicate VCODEs within this upload (all occurrences will be blocked)
  DROP TABLE IF EXISTS _pib_dup_vcodes;
  CREATE TEMP TABLE _pib_dup_vcodes ON COMMIT DROP AS
  SELECT upper(trim(elem->>'VCODE')) AS vcode
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1 HAVING count(*) > 1;

  -- [B] Employee → store coverage (roving detection)
  DROP TABLE IF EXISTS _pib_emp_cov;
  CREATE TEMP TABLE _pib_emp_cov ON COMMIT DROP AS
  SELECT
    upper(trim(elem->>'EMPLOYEE_NO')) AS emp,
    count(DISTINCT upper(trim(elem->>'VCODE'))) AS store_count
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'EMPLOYEE_NO'),'') IS NOT NULL
    AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1;

  -- [C] Already-seen (employee_no, vcode) pairs for exact-duplicate skip detection
  DROP TABLE IF EXISTS _pib_seen_pairs;
  CREATE TEMP TABLE _pib_seen_pairs (emp text, vcode text) ON COMMIT DROP;

  -- [D] VCODEs actively assigned in the live system: vcode → employee_no
  --     Used to detect "VCODE already assigned to a different employee" (new rule).
  DROP TABLE IF EXISTS _pib_active_vcode_owners;
  CREATE TEMP TABLE _pib_active_vcode_owners ON COMMIT DROP AS
  SELECT upper(trim(a.vcode)) AS vcode,
         upper(trim(a.employee_no)) AS employee_no
    FROM public.employee_store_allocations a
   WHERE a.is_active
     AND a.vcode IS NOT NULL
     AND a.employee_no IS NOT NULL;

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

    -- ── Blocking: required fields ─────────────────────────────────────────
    IF v_vcode    IS NULL THEN v_errs := v_errs || '[{"field":"VCODE","msg":"required"}]'::jsonb; END IF;
    IF v_store_nm IS NULL THEN v_errs := v_errs || '[{"field":"STORE_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_prov     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_PROVINCE","msg":"required"}]'::jsonb; END IF;
    IF v_city     IS NULL THEN v_errs := v_errs || '[{"field":"AREA_CITY","msg":"required"}]'::jsonb; END IF;
    IF v_emp      IS NULL THEN v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"required"}]'::jsonb; END IF;
    IF v_last     IS NULL THEN v_errs := v_errs || '[{"field":"LAST_NAME","msg":"required"}]'::jsonb; END IF;
    IF v_first    IS NULL THEN v_errs := v_errs || '[{"field":"FIRST_NAME","msg":"required"}]'::jsonb; END IF;

    -- Store row without employee: VCODE present but EMPLOYEE_NO absent → block
    IF v_vcode IS NOT NULL AND v_store_nm IS NOT NULL AND v_emp IS NULL THEN
      v_errs := v_errs || '[{"field":"EMPLOYEE_NO","msg":"store row has no employee — every VCODE must have an assigned employee"}]'::jsonb;
    END IF;

    -- Duplicate VCODE within upload → block
    IF v_vcode IS NOT NULL AND EXISTS (SELECT 1 FROM _pib_dup_vcodes WHERE vcode = v_vcode) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"duplicate VCODE in upload — each VCODE must appear exactly once"}]'::jsonb;
    END IF;

    -- VCODE already actively assigned to a different employee → block (new rule)
    IF v_vcode IS NOT NULL AND v_emp IS NOT NULL AND EXISTS (
      SELECT 1 FROM _pib_active_vcode_owners
      WHERE vcode = v_vcode AND employee_no <> v_emp
    ) THEN
      v_errs := v_errs || '[{"field":"VCODE","msg":"VCODE already actively assigned to a different employee"}]'::jsonb;
    END IF;

    -- Optional field flag
    IF v_req_hc IS NULL THEN
      v_flags := v_flags || '[{"flag":"missing_required_hc","msg":"REQUIRED_HC not provided"}]'::jsonb;
    END IF;

    -- Exact duplicate (same emp + same VCODE already seen in this upload) → skip
    IF v_emp IS NOT NULL AND v_vcode IS NOT NULL
       AND EXISTS (SELECT 1 FROM _pib_seen_pairs WHERE emp = v_emp AND vcode = v_vcode)
    THEN
      v_status := 'skipped';
      v_flags  := v_flags || '[{"flag":"duplicate_emp_vcode","msg":"same employee+VCODE already processed — skipped"}]'::jsonb;
    ELSE

      -- ── Resolve existing store by VCODE ──────────────────────────────────
      IF v_vcode IS NOT NULL THEN
        SELECT s.id, s.account_id, s.group_id
          INTO v_store_id, v_store_acct, v_store_grp
          FROM public.stores s
         WHERE upper(s.vcode) = v_vcode AND s.status = 'active'
         ORDER BY s.created_at LIMIT 1;
      END IF;
      v_is_new_store := (v_store_id IS NULL);

      -- Cross-group VCODE: existing store belongs to a different group → block
      IF v_store_id IS NOT NULL AND v_store_grp IS NOT NULL
         AND v_store_grp <> p_group_id THEN
        v_errs   := v_errs   || '[{"field":"VCODE","msg":"cross-group: store VCODE belongs to a different group"}]'::jsonb;
        v_xgroup := v_xgroup + 1;
      END IF;

      -- Cross-account employee: active allocations in a different account → block
      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.employee_store_allocations a
        WHERE upper(trim(a.employee_no)) = v_emp AND a.is_active
          AND a.account_id IS NOT NULL AND a.account_id <> p_account_id
      ) THEN
        v_errs  := v_errs  || '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee already deployed in another account"}]'::jsonb;
        v_xacct := v_xacct + 1;
      END IF;

      -- Cross-group employee: active allocations in a different group → block (new rule)
      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.employee_store_allocations a
        WHERE upper(trim(a.employee_no)) = v_emp AND a.is_active
          AND a.group_id IS NOT NULL AND a.group_id <> p_group_id
      ) THEN
        v_errs   := v_errs   || '[{"field":"EMPLOYEE_NO","msg":"cross-group: employee already deployed in another group"}]'::jsonb;
        v_xgroup := v_xgroup + 1;
      END IF;

      -- Existing employee_no in plantilla under a different account → block (new rule)
      IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE p.employee_no = v_emp
          AND p.is_deleted = false
          AND p.account_id IS NOT NULL
          AND p.account_id <> p_account_id
          AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
      ) THEN
        v_errs  := v_errs  || '[{"field":"EMPLOYEE_NO","msg":"cross-account: employee exists in plantilla under a different account"}]'::jsonb;
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

      -- Existing employee in active plantilla (same account) → upsert on commit, flag only
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

      -- Track seen pair (committable rows only — blocked must not claim the pair)
      IF v_emp IS NOT NULL AND v_vcode IS NOT NULL AND v_status IN ('valid', 'flagged') THEN
        INSERT INTO _pib_seen_pairs(emp, vcode) VALUES (v_emp, v_vcode);
      END IF;

      -- Track store novelty (per distinct VCODE, committable rows only)
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

    CASE v_status
      WHEN 'valid'   THEN v_valid    := v_valid    + 1;
      WHEN 'flagged' THEN v_flagged  := v_flagged  + 1;
      WHEN 'skipped' THEN v_skipped  := v_skipped  + 1;
      WHEN 'blocked' THEN v_blocked  := v_blocked  + 1;
      ELSE NULL;
    END CASE;

  END LOOP;

  -- ── Post-loop: HC mismatch sweep ─────────────────────────────────────────
  -- For each (store_name, position) group: flag rows where uploaded employee count
  -- does not match the sum of REQUIRED_HC across committable rows in that group.
  -- Both under-staffed (hc_under_required) and over-staffed (hc_over_required) are flagged.
  UPDATE public.plantilla_import_rows AS r
     SET validation_flags  = r.validation_flags || jsonb_build_array(
           jsonb_build_object(
             'flag', CASE WHEN hc.uploaded_count < hc.total_req
                          THEN 'hc_under_required'
                          ELSE 'hc_over_required'
                     END,
             'msg',  format('%s employee(s) uploaded for "%s / %s" but REQUIRED_HC sums to %s',
                            hc.uploaded_count, hc.store_nm, hc.pos, hc.total_req)
           )
         ),
         validation_status = CASE
           WHEN r.validation_status = 'valid' THEN 'flagged'
           ELSE r.validation_status
         END
    FROM (
      SELECT
        store_name  AS store_nm,
        position    AS pos,
        count(*)    AS uploaded_count,
        sum(
          COALESCE(
            NULLIF(regexp_replace(COALESCE(required_hc_raw,''),'[^0-9]','','g'), '')::int,
            0
          )
        )           AS total_req
      FROM public.plantilla_import_rows
     WHERE batch_id = v_batch_id
       AND validation_status IN ('valid','flagged')
       AND store_name IS NOT NULL
       AND position   IS NOT NULL
     GROUP BY store_name, position
    HAVING count(*) <>
           sum(COALESCE(
             NULLIF(regexp_replace(COALESCE(required_hc_raw,''),'[^0-9]','','g'), '')::int,
             0
           ))
    ) AS hc
   WHERE r.batch_id      = v_batch_id
     AND r.store_name    = hc.store_nm
     AND r.position      = hc.pos
     AND r.validation_status IN ('valid','flagged');

  -- Re-sync valid/flagged counters after HC sweep
  SELECT count(*) FILTER (WHERE validation_status = 'valid')
    INTO v_valid
    FROM public.plantilla_import_rows WHERE batch_id = v_batch_id;

  SELECT count(*) FILTER (WHERE validation_status = 'flagged')
    INTO v_flagged
    FROM public.plantilla_import_rows WHERE batch_id = v_batch_id;

  -- ── Post-loop: roving dedup ───────────────────────────────────────────────
  SELECT count(*) INTO v_roving
    FROM _pib_emp_cov WHERE store_count > 1;

  SELECT count(DISTINCT employee_no) INTO v_ex_emps
    FROM public.plantilla_import_rows r
   WHERE r.batch_id = v_batch_id
     AND r.validation_status IN ('valid','flagged')
     AND r.is_existing_employee;

  -- ── Post-loop: missing from upload ───────────────────────────────────────
  -- Employees active in the target account but absent from this upload (informational).
  SELECT count(*) INTO v_missing
    FROM public.plantilla p
   WHERE p.account_id = p_account_id
     AND p.is_deleted = false
     AND p.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
     AND NOT EXISTS (
       SELECT 1 FROM public.plantilla_import_rows r
        WHERE r.batch_id = v_batch_id
          AND r.employee_no = p.employee_no
          AND r.validation_status IN ('valid','flagged')
     );

  -- ── Aggregate error summary ───────────────────────────────────────────────
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
     SET total_rows                = v_total,
         valid_rows                = v_valid,
         flagged_rows              = v_flagged,
         skipped_rows              = v_skipped,
         blocked_rows              = v_blocked,
         roving_detected           = v_roving,
         new_stores_count          = v_new_stores,
         existing_stores_count     = v_ex_stores,
         existing_employees_count  = v_ex_emps,
         cross_account_conflicts   = v_xacct,
         cross_group_conflicts     = v_xgroup,
         over_20_store_warnings    = v_over20,
         missing_from_upload_count = v_missing,
         error_summary             = v_summary,
         status                    = v_final,
         updated_at                = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id',                   v_batch_id,
    'status',                     v_final,
    'total_rows',                 v_total,
    'valid_rows',                 v_valid,
    'flagged_rows',               v_flagged,
    'skipped_rows',               v_skipped,
    'blocked_rows',               v_blocked,
    'roving_detected',            v_roving,
    'new_stores_count',           v_new_stores,
    'existing_stores_count',      v_ex_stores,
    'existing_employees_count',   v_ex_emps,
    'cross_account_conflicts',    v_xacct,
    'cross_group_conflicts',      v_xgroup,
    'over_20_store_warnings',     v_over20,
    'missing_from_upload_count',  v_missing,
    'error_summary',              v_summary
  );
END$func$;

REVOKE ALL ON FUNCTION public.submit_plantilla_baseline_import(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_plantilla_baseline_import(text,uuid,uuid,jsonb) TO authenticated;

COMMENT ON FUNCTION public.submit_plantilla_baseline_import IS
  'Finalized dry-run validation for Plantilla Baseline Import (OHM2026_0054). '
  'Adds: VCODE-already-assigned block, cross-group employee block, cross-account plantilla block, '
  'HC mismatch flag (per store+position), missing_from_upload_count. '
  'Never writes to stores or plantilla. RBAC: Encoder / Head Admin / Super Admin.';


-- ============================================================
-- §5  approve_plantilla_import_batch  (commit_failed + snapshots)
-- ============================================================
-- Replaces the OHM2026_0053 version.
--
-- Key changes vs OHM2026_0053:
--   • Inner BEGIN..EXCEPTION block — on any error: ALL commit DML rolls back
--     atomically; batch status set to commit_failed; error detail captured.
--   • Pre-commit guard: at least one committable row must exist.
--   • Allocation supersede scoped to selected_account_id (not global-employee).
--   • plantilla_import_commit_snapshots populated for stores, plantilla,
--     and existing allocations (rollback lineage).
--   • Roving group creation handles re-import (new group per commit; old groups
--     remain as history — do not delete allocation history).
--
-- Replay safety:
--   • status = pending_approval guard prevents double commit.
--   • commit_failed batch preserves error detail; requires manual investigation.
--   • Snapshot table retains pre-mutation state for each entity.

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
  v_srow               record;
  v_existing_store_id  uuid;
  v_new_store_id       uuid;
  v_old_store_snap     jsonb;
  v_pen_bool           boolean;
  v_emp_type_norm      text;
  v_stores_done        int := 0;
  v_rep_row_id         uuid;

  -- Phase B locals
  v_emp_rec        record;
  v_store_rec      record;
  v_plantilla_id   uuid;
  v_roving_id      uuid;
  v_store_cnt      int;
  v_filled         numeric(8,4);
  v_emp_name       text;
  v_old_plant_snap jsonb;
  v_employees_done int := 0;
  v_alloc_done     int := 0;

  -- Commit counts
  v_committable int;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Lock + state check ───────────────────────────────────────────────────
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  -- ── Pre-commit guard ─────────────────────────────────────────────────────
  SELECT count(*) INTO v_committable
    FROM public.plantilla_import_rows
   WHERE batch_id = p_batch_id
     AND validation_status IN ('valid','flagged')
     AND employee_no IS NOT NULL
     AND vcode IS NOT NULL;

  IF v_committable = 0 THEN
    RAISE EXCEPTION 'COMMIT_EMPTY: no committable rows in batch (valid+flagged with employee_no and vcode)'
      USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name
    FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- ── Temp store commit map ─────────────────────────────────────────────────
  DROP TABLE IF EXISTS _pib_store_map;
  CREATE TEMP TABLE _pib_store_map (
    vcode    text,
    store_id uuid,
    is_new   boolean
  ) ON COMMIT DROP;

  -- ── Inner exception block — all commit DML is atomic ─────────────────────
  -- If any exception occurs here, ALL DML within this block is rolled back.
  -- The EXCEPTION handler then records commit_failed on the batch.
  BEGIN

    -- ── Phase A: Store upsert ───────────────────────────────────────────────
    FOR v_srow IN
      SELECT DISTINCT ON (vcode)
             vcode, store_name, area_province, area_city,
             employment_type, with_penalty_raw, row_number, id AS row_id
        FROM public.plantilla_import_rows
       WHERE batch_id = p_batch_id
         AND validation_status IN ('valid','flagged')
         AND vcode IS NOT NULL
       ORDER BY vcode, row_number
    LOOP
      v_emp_type_norm := CASE
        WHEN lower(COALESCE(v_srow.employment_type,'')) IN ('stationary','roving')
          THEN lower(v_srow.employment_type)
        ELSE NULL
      END;

      v_pen_bool := CASE
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('yes','y','true','1')  THEN true
        WHEN lower(COALESCE(v_srow.with_penalty_raw,'')) IN ('no','n','false','0') THEN false
        ELSE NULL
      END;

      -- Capture pre-commit store snapshot for rollback lineage
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

        -- Commit snapshot: new store
        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_new_store_id, 'insert', NULL, v_uid);

      ELSE
        -- Existing store: update
        v_existing_store_id := (v_old_store_snap->>'id')::uuid;

        UPDATE public.stores
           SET store_name      = v_srow.store_name,
               area_province   = v_srow.area_province,
               area_city       = v_srow.area_city,
               employment_type = COALESCE(v_emp_type_norm, employment_type),
               with_penalty    = COALESCE(v_pen_bool, with_penalty),
               updated_by      = v_uid,
               approved_by     = v_uid,
               approved_at     = now(),
               source_import_id = p_batch_id
         WHERE id = v_existing_store_id;

        INSERT INTO _pib_store_map VALUES (upper(v_srow.vcode), v_existing_store_id, false);

        -- Commit snapshot: store before update (rollback restore target)
        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, import_row_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, v_srow.row_id, 'store', v_existing_store_id, 'update', v_old_store_snap, v_uid);
      END IF;

      -- Write row-level rollback snapshot
      UPDATE public.plantilla_import_rows
         SET previous_store_snapshot = v_old_store_snap
       WHERE batch_id = p_batch_id
         AND upper(vcode) = upper(v_srow.vcode)
         AND validation_status IN ('valid','flagged');

      v_stores_done := v_stores_done + 1;
    END LOOP;

    -- ── Phase B: Employee / plantilla upsert ────────────────────────────────
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

      -- Resolve existing active plantilla master row for this employee
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
        -- New employee: insert plantilla master
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
          -- Single-store: pin store/VCODE; roving: master VCODE/store is NULL
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

        -- Commit snapshot: new plantilla insert (no previous state)
        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'insert', NULL, v_uid);

      ELSE
        -- Existing employee: refresh name + import linkage
        UPDATE public.plantilla
           SET employee_name = v_emp_name,
               last_name     = v_emp_rec.last_name,
               first_name    = v_emp_rec.first_name,
               middle_name   = v_emp_rec.middle_name,
               updated_at    = now(),
               source_baseline_import_batch_id = p_batch_id
         WHERE id = v_plantilla_id;

        -- Commit snapshot: plantilla before update
        INSERT INTO public.plantilla_import_commit_snapshots
          (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
        VALUES (p_batch_id, 'plantilla', v_plantilla_id, 'update', v_old_plant_snap, v_uid);
      END IF;

      -- Link roving group to plantilla master
      IF v_roving_id IS NOT NULL THEN
        UPDATE public.import_roving_groups SET plantilla_id = v_plantilla_id
         WHERE id = v_roving_id;
      END IF;

      -- Write row-level plantilla snapshot
      UPDATE public.plantilla_import_rows
         SET previous_plantilla_snapshot = v_old_plant_snap
       WHERE batch_id = p_batch_id
         AND employee_no = v_emp_rec.employee_no
         AND validation_status IN ('valid','flagged');

      -- Snapshot existing active allocations before superseding (rollback lineage)
      -- Scoped to selected_account_id — does not disturb other accounts' allocations.
      INSERT INTO public.plantilla_import_commit_snapshots
        (batch_id, entity_type, entity_id, action, previous_snapshot, committed_by)
      SELECT
        p_batch_id, 'allocation', a.id, 'update', to_jsonb(a.*), v_uid
        FROM public.employee_store_allocations a
       WHERE a.employee_no = v_emp_rec.employee_no
         AND a.is_active
         AND a.account_id = v_batch.selected_account_id;

      -- Supersede prior active allocations for this employee in this account
      UPDATE public.employee_store_allocations
         SET is_active = false, effective_end = CURRENT_DATE
       WHERE employee_no = v_emp_rec.employee_no
         AND is_active
         AND account_id = v_batch.selected_account_id;

      -- Create one active allocation row per distinct VCODE for this employee
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
          'employee_no',         v_emp_rec.employee_no,
          'store_count',         v_store_cnt,
          'filled_hc_per_store', v_filled,
          'roving',              (v_roving_id IS NOT NULL),
          'batch_id',            p_batch_id
        ));
    END LOOP;

    -- ── Finalise batch ──────────────────────────────────────────────────────
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
        'stores',      v_stores_done,
        'employees',   v_employees_done,
        'allocations', v_alloc_done
      ));

    RETURN jsonb_build_object(
      'batch_id',            p_batch_id,
      'status',              'approved',
      'stores_committed',    v_stores_done,
      'employees_committed', v_employees_done,
      'allocations_created', v_alloc_done
    );

  EXCEPTION WHEN OTHERS THEN
    -- All Phase A + B DML rolled back by this point (subtransaction).
    -- Record commit_failed on the batch in the outer transaction context.
    UPDATE public.plantilla_import_batches
       SET status              = 'commit_failed',
           commit_error_detail = format('[%s] %s', SQLSTATE, SQLERRM),
           updated_at          = now()
     WHERE id = p_batch_id;

    RETURN jsonb_build_object(
      'batch_id', p_batch_id,
      'status',   'commit_failed',
      'error',    format('[%s] %s', SQLSTATE, SQLERRM)
    );
  END; -- end inner exception block

END$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_batch(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_plantilla_import_batch IS
  'Commit RPC for Plantilla Baseline Import (OHM2026_0054 finalized). '
  'Atomic two-phase commit via inner BEGIN..EXCEPTION: on any error ALL DML rolls '
  'back and batch status = commit_failed with error detail. '
  'Phase A upserts stores + commit snapshots; Phase B upserts plantilla + '
  'account-scoped allocation supersede + allocation snapshots + roving groups. '
  'Blocked rows never commit. Replay-safe: approved batch rejects re-approval. '
  'RBAC: Head Admin / Super Admin only.';
