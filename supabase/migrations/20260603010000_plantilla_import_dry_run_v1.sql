-- ============================================================
-- OHM2026_0030 — Plantilla Import Dry Run V1
-- Migration:  20260603010000_plantilla_import_dry_run_v1.sql
-- Depends on: existing store_import_batches / store_import_rows /
--             plantilla / stores / vacancies / accounts / groups /
--             positions / audit_logs  (already deployed)
-- ============================================================
-- Purpose
--   Backend architecture for the Plantilla Import Dry Run:
--     CSV upload → staging rows → validation → preview →
--     HA/SA approval → commit RPC → active Plantilla.
--
--   Imports NEVER write directly to active Plantilla. All writes
--   are staged, validated (dry-run), previewed, and only committed
--   by an authorized approver through a SECURITY DEFINER RPC.
--
-- Scope decisions (confirmed with product owner)
--   1. Store Master import already exists (store_import_batches/
--      store_import_rows + create/add/approve/reject RPCs). Those
--      stable RPCs are LEFT UNTOUCHED. This migration adds new
--      RBAC-aligned wrappers so Encoder can upload and HA/SA can
--      approve, sharing one RBAC model with the Employee import.
--   2. Fractional HC is PERSISTED + exposed through a NEW view only.
--      Existing MFR views (v_workforce_health_summary, v_account_kpi)
--      are NOT modified in V1.
--   3. Roving allocation history lives in a NEW dedicated table
--      (employee_store_allocations) with effective start/end dates.
--      Import roving grouping is self-contained (import_roving_groups)
--      and does NOT mutate the applicant-based roving_assignments
--      stable flow.
--
-- RBAC
--   Uploaders : Encoder, Head Admin, Super Admin
--   Approvers : Head Admin, Super Admin  ( == i_have_full_access() )
--
-- Sections
--   §1  RBAC helpers (upload/approve gates)
--   §2  import_roving_groups table
--   §3  employee_store_allocations table
--   §4  employee_import_batches table
--   §5  employee_import_rows table
--   §6  RLS policies
--   §7  Indexes
--   §8  submit_employee_import_v1  (upload + dry-run validation)
--   §9  get_employee_import_preview (preview counts/conflicts)
--   §10 approve_employee_import_batch (commit RPC)
--   §11 reject_employee_import_batch
--   §12 get_employee_import_batches / get_employee_import_rows
--   §13 v_store_fractional_hc view (fractional HC per store)
--   §14 RBAC-aligned Store Master wrappers
--   §15 Store Master template CSV (GROUP/ACCOUNT removed)
--
-- Validation Queries (run manually after applying):
--   V1  Tables exist
--     SELECT tablename FROM pg_tables WHERE schemaname='public'
--       AND tablename IN ('employee_import_batches','employee_import_rows',
--         'employee_store_allocations','import_roving_groups');
--   V2  RLS enabled
--     SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public'
--       AND tablename IN ('employee_import_batches','employee_import_rows',
--         'employee_store_allocations','import_roving_groups');
--   V3  RPCs exist
--     SELECT proname FROM pg_proc WHERE proname IN
--       ('submit_employee_import_v1','get_employee_import_preview',
--        'approve_employee_import_batch','reject_employee_import_batch',
--        'get_employee_import_batches','get_employee_import_rows',
--        'submit_store_import_rbac','approve_store_import_batch_rbac',
--        'reject_store_import_batch_rbac','get_store_import_template_csv');
--   V6  Store Master template header carries no GROUP/ACCOUNT:
--     SELECT csv FROM get_store_import_template_csv();  -- header begins with VCODE,STORE_NAME,...
--   V4  Dry-run never writes plantilla: after submit_employee_import_v1,
--       SELECT count(*) FROM plantilla WHERE source_employee_import_batch_id = <batch>;  -- expect 0
--   V5  Equal-split allocation: an EMP across 3 stores → 3 allocation rows
--       each filled_hc = round(1/3,4) after approve.
-- ============================================================


-- ============================================================
-- §1  RBAC helpers
-- ============================================================
-- Approvers reuse the canonical i_have_full_access() (SA OR HA).
-- Uploaders add Encoder on top.

-- Safe Encoder predicate. Defined here (idempotent CREATE OR REPLACE) so this
-- migration does not depend on legacy unversioned drift for i_am_encoder().
-- Mirrors the canonical role naming returned by get_my_role().
CREATE OR REPLACE FUNCTION public.i_am_encoder()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.get_my_role() = 'Encoder';
$$;

REVOKE ALL ON FUNCTION public.i_am_encoder() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.i_am_encoder() TO authenticated;

COMMENT ON FUNCTION public.i_am_encoder() IS
  'TRUE when the caller role is Encoder (per get_my_role()). Safe re-definition to avoid legacy drift dependency.';

CREATE OR REPLACE FUNCTION public.fn_can_upload_plantilla_import()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.i_have_full_access() OR public.i_am_encoder();
$$;

REVOKE ALL ON FUNCTION public.fn_can_upload_plantilla_import() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_can_upload_plantilla_import() TO authenticated;

COMMENT ON FUNCTION public.fn_can_upload_plantilla_import() IS
  'TRUE for Encoder, Head Admin, or Super Admin. Upload gate for plantilla/store import batches.';

CREATE OR REPLACE FUNCTION public.fn_can_approve_plantilla_import()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.i_have_full_access();
$$;

REVOKE ALL ON FUNCTION public.fn_can_approve_plantilla_import() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_can_approve_plantilla_import() TO authenticated;

COMMENT ON FUNCTION public.fn_can_approve_plantilla_import() IS
  'TRUE for Head Admin or Super Admin (i_have_full_access). Approval gate for import commit/reject.';

-- Allowed account UUIDs for the caller (wraps the canonical get_my_scoped_accounts()).
-- Returns an empty array for full-access callers (they bypass scope filters via i_have_full_access()).
CREATE OR REPLACE FUNCTION public.get_my_allowed_account_ids()
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(array_agg(account_id), ARRAY[]::uuid[])
  FROM public.get_my_scoped_accounts();
$$;

REVOKE ALL ON FUNCTION public.get_my_allowed_account_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_allowed_account_ids() TO authenticated;

COMMENT ON FUNCTION public.get_my_allowed_account_ids() IS
  'Account UUIDs in the caller scope, derived from get_my_scoped_accounts(). Used by import RLS and scope guards.';


-- ============================================================
-- §2  import_roving_groups
-- ============================================================
-- Self-contained roving grouping for the import domain. Auto-created
-- when an employee is detected across >1 active store. Kept separate
-- from the applicant-based roving_assignments table to avoid mutating
-- the stable applicant→hr_emploc roving flow.

CREATE TABLE IF NOT EXISTS public.import_roving_groups (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  employee_no              text        NOT NULL,
  account_id               uuid,
  group_id                 uuid,
  account_name             text,
  label                    text,
  active_store_count       integer     NOT NULL DEFAULT 0,
  filled_hc_per_store      numeric(8,4) NOT NULL DEFAULT 0,
  source_import_batch_id   uuid,
  plantilla_id             uuid,
  created_at               timestamptz NOT NULL DEFAULT NOW(),
  created_by               uuid,
  updated_at               timestamptz NOT NULL DEFAULT NOW(),
  archived_at              timestamptz,

  CONSTRAINT import_roving_groups_pkey PRIMARY KEY (id),
  CONSTRAINT import_roving_groups_account_fkey
    FOREIGN KEY (account_id) REFERENCES public.accounts(id) NOT VALID,
  CONSTRAINT import_roving_groups_group_fkey
    FOREIGN KEY (group_id) REFERENCES public.groups(id) NOT VALID
);

COMMENT ON TABLE public.import_roving_groups IS
  'Auto-created roving grouping for imported employees deployed across >1 active store. '
  'filled_hc_per_store = 1 / active_store_count (V1 equal-split). Separate from applicant-based roving_assignments.';

ALTER TABLE public.import_roving_groups ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.import_roving_groups FROM authenticated, anon;


-- ============================================================
-- §3  employee_store_allocations
-- ============================================================
-- Fractional HC allocation history with effective dates. One row per
-- (employee, store) deployment. Single-store employees get filled_hc=1.
-- Roving employees get filled_hc = 1/active_store_count per store.

CREATE TABLE IF NOT EXISTS public.employee_store_allocations (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  plantilla_id             uuid        NOT NULL,
  employee_no              text        NOT NULL,
  roving_group_id          uuid,                 -- NULL for single-store
  store_id                 uuid,
  vcode                    text,
  store_name               text,
  account_id               uuid,
  group_id                 uuid,
  filled_hc                numeric(8,4) NOT NULL DEFAULT 1,
  active_store_count       integer     NOT NULL DEFAULT 1,
  effective_start          date        NOT NULL DEFAULT CURRENT_DATE,
  effective_end            date,                 -- NULL = currently active
  is_active                boolean     NOT NULL DEFAULT true,
  source_import_batch_id   uuid,
  created_at               timestamptz NOT NULL DEFAULT NOW(),
  created_by               uuid,

  CONSTRAINT employee_store_allocations_pkey PRIMARY KEY (id),
  CONSTRAINT employee_store_allocations_filled_hc_check
    CHECK (filled_hc >= 0 AND filled_hc <= 1),
  CONSTRAINT employee_store_allocations_plantilla_fkey
    FOREIGN KEY (plantilla_id) REFERENCES public.plantilla(id) NOT VALID,
  CONSTRAINT employee_store_allocations_roving_group_fkey
    FOREIGN KEY (roving_group_id) REFERENCES public.import_roving_groups(id) NOT VALID
);

COMMENT ON TABLE public.employee_store_allocations IS
  'Fractional HC allocation history per (employee, store) with effective dates. '
  'filled_hc=1 for single-store; 1/active_store_count for roving. is_active=false + effective_end set on supersede.';

COMMENT ON COLUMN public.employee_store_allocations.filled_hc IS
  'Fractional headcount this employee contributes to the store. Equal-split V1: 1/active_store_count.';

ALTER TABLE public.employee_store_allocations ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.employee_store_allocations FROM authenticated, anon;


-- ============================================================
-- §4  employee_import_batches
-- ============================================================

CREATE TABLE IF NOT EXISTS public.employee_import_batches (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  file_name                text        NOT NULL,
  uploaded_by              uuid        NOT NULL,
  uploaded_role            text,
  selected_group_id        uuid        NOT NULL,
  selected_account_id      uuid        NOT NULL,
  status                   text        NOT NULL DEFAULT 'draft_uploaded',

  -- Preview counts (populated by validation)
  total_rows               integer     NOT NULL DEFAULT 0,
  valid_rows               integer     NOT NULL DEFAULT 0,
  skipped_duplicate_rows   integer     NOT NULL DEFAULT 0,
  blocked_rows             integer     NOT NULL DEFAULT 0,
  flagged_rows             integer     NOT NULL DEFAULT 0,
  roving_detected          integer     NOT NULL DEFAULT 0,
  cross_account_conflicts  integer     NOT NULL DEFAULT 0,
  cross_group_conflicts    integer     NOT NULL DEFAULT 0,
  over_20_store_warnings   integer     NOT NULL DEFAULT 0,

  error_summary            jsonb       NOT NULL DEFAULT '{}'::jsonb,

  -- Approval / rejection
  approved_by              uuid,
  approved_at              timestamptz,
  committed_rows           integer,
  rejected_by              uuid,
  rejected_at              timestamptz,
  rejection_reason         text,

  created_at               timestamptz NOT NULL DEFAULT NOW(),
  updated_at               timestamptz NOT NULL DEFAULT NOW(),

  CONSTRAINT employee_import_batches_pkey PRIMARY KEY (id),
  CONSTRAINT employee_import_batches_status_check
    CHECK (status IN ('draft_uploaded','validation_failed','pending_approval','approved','rejected')),
  CONSTRAINT employee_import_batches_group_fkey
    FOREIGN KEY (selected_group_id) REFERENCES public.groups(id) NOT VALID,
  CONSTRAINT employee_import_batches_account_fkey
    FOREIGN KEY (selected_account_id) REFERENCES public.accounts(id) NOT VALID
);

COMMENT ON TABLE public.employee_import_batches IS
  'Employee Plantilla import batch. Staging-only until approved. '
  'status: draft_uploaded → validation_failed | pending_approval → approved | rejected.';

ALTER TABLE public.employee_import_batches ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.employee_import_batches FROM authenticated, anon;


-- ============================================================
-- §5  employee_import_rows
-- ============================================================

CREATE TABLE IF NOT EXISTS public.employee_import_rows (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  batch_id                 uuid        NOT NULL,
  row_number               integer     NOT NULL,
  raw_data                 jsonb       NOT NULL,

  -- Parsed CSV fields (EMPLOYEE_NO,LAST_NAME,FIRST_NAME,MIDDLE_NAME,VCODE)
  employee_no              text,
  last_name                text,
  first_name               text,
  middle_name              text,
  vcode                    text,

  -- Resolved references (best-effort during validation)
  resolved_store_id        uuid,
  resolved_store_name      text,
  resolved_account_id      uuid,
  resolved_group_id        uuid,
  resolved_position        text,

  -- Dry-run outcome
  validation_status        text        NOT NULL,   -- valid | flagged | skipped | blocked
  validation_errors        jsonb       NOT NULL DEFAULT '[]'::jsonb,
  validation_flags         jsonb       NOT NULL DEFAULT '[]'::jsonb,
  is_roving                boolean     NOT NULL DEFAULT false,
  roving_store_count       integer     NOT NULL DEFAULT 0,

  created_at               timestamptz NOT NULL DEFAULT NOW(),

  CONSTRAINT employee_import_rows_pkey PRIMARY KEY (id),
  CONSTRAINT employee_import_rows_status_check
    CHECK (validation_status IN ('valid','flagged','skipped','blocked')),
  CONSTRAINT employee_import_rows_batch_fkey
    FOREIGN KEY (batch_id) REFERENCES public.employee_import_batches(id) ON DELETE CASCADE NOT VALID
);

COMMENT ON TABLE public.employee_import_rows IS
  'Staged employee import rows. validation_status: '
  'valid (commit-eligible) | flagged (commit-eligible + warnings) | '
  'skipped (duplicate emp+vcode, not committed) | blocked (cannot commit, stays in staging).';

ALTER TABLE public.employee_import_rows ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.employee_import_rows FROM authenticated, anon;


-- ============================================================
-- §6  RLS policies (SELECT only — all mutations via RPC)
-- ============================================================
-- Full-access (HA/SA) sees all. Encoders see batches they uploaded.

CREATE POLICY eib_select ON public.employee_import_batches
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR uploaded_by = auth.uid()
  );

CREATE POLICY eir_select ON public.employee_import_rows
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR EXISTS (
      SELECT 1 FROM public.employee_import_batches b
      WHERE b.id = employee_import_rows.batch_id
        AND b.uploaded_by = auth.uid()
    )
  );

-- Allocations / roving groups: full-access OR account-scoped users.
CREATE POLICY esa_select ON public.employee_store_allocations
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR account_id = ANY (public.get_my_allowed_account_ids())
  );

CREATE POLICY irg_select ON public.import_roving_groups
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR account_id = ANY (public.get_my_allowed_account_ids())
  );


-- ============================================================
-- §7  Indexes
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_eib_status        ON public.employee_import_batches(status);
CREATE INDEX IF NOT EXISTS idx_eib_uploaded_by   ON public.employee_import_batches(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_eib_account       ON public.employee_import_batches(selected_account_id);

CREATE INDEX IF NOT EXISTS idx_eir_batch         ON public.employee_import_rows(batch_id);
CREATE INDEX IF NOT EXISTS idx_eir_batch_status  ON public.employee_import_rows(batch_id, validation_status);
CREATE INDEX IF NOT EXISTS idx_eir_employee_no   ON public.employee_import_rows(employee_no);

CREATE INDEX IF NOT EXISTS idx_esa_plantilla     ON public.employee_store_allocations(plantilla_id);
CREATE INDEX IF NOT EXISTS idx_esa_store_active  ON public.employee_store_allocations(store_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_esa_employee_active ON public.employee_store_allocations(employee_no) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_esa_roving_group  ON public.employee_store_allocations(roving_group_id);

CREATE INDEX IF NOT EXISTS idx_irg_employee      ON public.import_roving_groups(employee_no) WHERE archived_at IS NULL;

-- Provenance on plantilla (best-effort; column may already be absent)
ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS source_employee_import_batch_id uuid;
COMMENT ON COLUMN public.plantilla.source_employee_import_batch_id IS
  'employee_import_batches.id that committed this plantilla row, if any.';


-- ============================================================
-- §8  submit_employee_import_v1  (upload + dry-run validation)
-- ============================================================
-- Creates a batch and validates rows. NEVER writes to plantilla.
-- Returns preview counts. Idempotent re-validation: existing draft
-- rows are not mutated — each call creates a fresh batch.

CREATE OR REPLACE FUNCTION public.submit_employee_import_v1(
  p_file_name  text,
  p_group_id   uuid,
  p_account_id uuid,
  p_rows       jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_role       text := public.get_my_role();
  v_batch_id   uuid;
  v_acct_group uuid;

  v_row        jsonb;
  v_idx        int := 0;
  v_emp        text;
  v_last       text;
  v_first      text;
  v_middle     text;
  v_vcode      text;

  v_store_id   uuid;
  v_store_name text;
  v_store_acct uuid;
  v_store_grp  uuid;
  v_position   text;

  v_errs       jsonb;
  v_flags      jsonb;
  v_status     text;
  v_is_roving  boolean;
  v_store_cnt  int;

  v_total      int := 0;
  v_valid      int := 0;
  v_flagged    int := 0;
  v_skipped    int := 0;
  v_blocked    int := 0;
  v_roving     int := 0;
  v_xacct      int := 0;
  v_xgroup     int := 0;
  v_over20     int := 0;
  v_summary    jsonb;
  v_final      text;
BEGIN
  -- ── Auth: uploader gate ──────────────────────────────────────────────────
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

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

  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'INVALID_GROUP: %', p_group_id USING ERRCODE = '23503';
  END IF;
  SELECT group_id INTO v_acct_group FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: %', p_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %', p_account_id, p_group_id
      USING ERRCODE = '23503';
  END IF;

  -- Non-full-access uploaders must own the target account scope.
  IF NOT public.i_have_full_access()
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account is outside caller scope' USING ERRCODE = '42501';
  END IF;

  -- ── Create batch ─────────────────────────────────────────────────────────
  INSERT INTO public.employee_import_batches (
    file_name, uploaded_by, uploaded_role, selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_batch_id;

  -- ── Pre-compute per-employee store coverage WITHIN this CSV ──────────────
  -- distinct (emp -> vcode) pairs; coverage = distinct vcode count per emp.
  DROP TABLE IF EXISTS _emp_cov;
  DROP TABLE IF EXISTS _seen_pairs;
  CREATE TEMP TABLE _emp_cov ON COMMIT DROP AS
  SELECT
    upper(trim(elem->>'EMPLOYEE_NO'))                 AS emp,
    count(DISTINCT upper(trim(elem->>'VCODE')))       AS store_count
  FROM jsonb_array_elements(p_rows) elem
  WHERE NULLIF(trim(elem->>'EMPLOYEE_NO'),'') IS NOT NULL
    AND NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
  GROUP BY 1;

  -- Distinct (emp,vcode) seen so far → drives duplicate skip detection.
  CREATE TEMP TABLE _seen_pairs (emp text, vcode text) ON COMMIT DROP;

  -- ── Row loop ─────────────────────────────────────────────────────────────
  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx   := v_idx + 1;
    v_total := v_total + 1;
    v_errs  := '[]'::jsonb;
    v_flags := '[]'::jsonb;
    v_is_roving := false;
    v_store_cnt := 0;
    v_store_id := NULL; v_store_name := NULL; v_store_acct := NULL; v_store_grp := NULL; v_position := NULL;

    v_emp    := upper(NULLIF(trim(COALESCE(v_row->>'EMPLOYEE_NO','')), ''));
    v_last   := NULLIF(trim(COALESCE(v_row->>'LAST_NAME','')), '');
    v_first  := NULLIF(trim(COALESCE(v_row->>'FIRST_NAME','')), '');
    v_middle := NULLIF(trim(COALESCE(v_row->>'MIDDLE_NAME','')), '');
    v_vcode  := upper(NULLIF(trim(COALESCE(v_row->>'VCODE','')), ''));

    -- Required fields (employee_no == hr_emploc_no, same identifier)
    IF v_emp   IS NULL THEN v_errs := v_errs || jsonb_build_object('field','EMPLOYEE_NO','msg','required'); END IF;
    IF v_last  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','LAST_NAME','msg','required'); END IF;
    IF v_first IS NULL THEN v_errs := v_errs || jsonb_build_object('field','FIRST_NAME','msg','required'); END IF;
    IF v_vcode IS NULL THEN v_errs := v_errs || jsonb_build_object('field','VCODE','msg','required'); END IF;

    -- Resolve store by VCODE (active stores only)
    IF v_vcode IS NOT NULL THEN
      SELECT s.id, s.store_name, s.account_id, s.group_id
        INTO v_store_id, v_store_name, v_store_acct, v_store_grp
        FROM public.stores s
       WHERE upper(s.vcode) = v_vcode AND s.status = 'active'
       ORDER BY s.created_at
       LIMIT 1;

      IF v_store_id IS NULL THEN
        v_errs := v_errs || jsonb_build_object('field','VCODE','msg','no active store found for vcode');
      ELSE
        -- Derive position from a matching vacancy if available.
        SELECT v.position INTO v_position
          FROM public.vacancies v
         WHERE upper(v.vcode) = v_vcode AND NOT COALESCE(v.is_archived,false)
         ORDER BY v.created_at LIMIT 1;
      END IF;
    END IF;

    -- Roving coverage (within CSV) for this employee
    IF v_emp IS NOT NULL THEN
      SELECT store_count INTO v_store_cnt FROM _emp_cov WHERE emp = v_emp;
      v_store_cnt := COALESCE(v_store_cnt, 0);
      IF v_store_cnt > 1 THEN
        v_is_roving := true;
      END IF;
      IF v_store_cnt > 20 THEN
        v_flags := v_flags || jsonb_build_object('flag','over_20_stores','msg', v_store_cnt || ' stores (>20 allowed but flagged)');
      END IF;
    END IF;

    -- Duplicate (same emp + same vcode) → skip
    IF v_emp IS NOT NULL AND v_vcode IS NOT NULL
       AND EXISTS (SELECT 1 FROM _seen_pairs sp WHERE sp.emp = v_emp AND sp.vcode = v_vcode) THEN
      v_status := 'skipped';
      v_flags := v_flags || jsonb_build_object('flag','duplicate_emp_vcode','msg','duplicate employee+vcode within CSV — skipped');
    ELSE
      -- Cross-account / cross-group detection across the resolved stores of this emp.
      -- Account set = stores resolved in CSV (via _emp_cov vcodes) + existing active allocations.
      IF v_emp IS NOT NULL AND v_store_id IS NOT NULL THEN
        -- group conflict: resolved store group differs from batch group → not allowed
        IF v_store_grp IS NOT NULL AND v_store_grp <> p_group_id THEN
          v_errs := v_errs || jsonb_build_object('field','VCODE','msg','cross-group: store group differs from batch group');
        END IF;

        -- account conflict: emp resolves to >1 distinct account across CSV vcodes
        IF (
          SELECT count(DISTINCT s2.account_id)
          FROM jsonb_array_elements(p_rows) AS e2(value)
          JOIN public.stores s2 ON upper(s2.vcode) = upper(trim(e2.value->>'VCODE')) AND s2.status='active'
          WHERE upper(trim(e2.value->>'EMPLOYEE_NO')) = v_emp
        ) > 1 THEN
          v_errs := v_errs || jsonb_build_object('field','EMPLOYEE_NO','msg','cross-account: same employee across multiple accounts — blocked');
          v_flags := v_flags || jsonb_build_object('flag','cross_account','msg','review by Encoder / Head Admin');
        END IF;

        -- existing active allocation in a different account → cross-account
        IF EXISTS (
          SELECT 1 FROM public.employee_store_allocations a
          WHERE a.employee_no = v_emp AND a.is_active
            AND a.account_id IS NOT NULL AND a.account_id <> v_store_acct
        ) THEN
          v_errs := v_errs || jsonb_build_object('field','EMPLOYEE_NO','msg','cross-account: employee already deployed in another account');
          v_flags := v_flags || jsonb_build_object('flag','cross_account','msg','review by Encoder / Head Admin');
        END IF;
      END IF;

      IF jsonb_array_length(v_errs) > 0 THEN
        v_status := 'blocked';
      ELSIF jsonb_array_length(v_flags) > 0 THEN
        v_status := 'flagged';
      ELSE
        v_status := 'valid';
      END IF;

      -- record the pair as seen (only for non-skipped rows)
      IF v_emp IS NOT NULL AND v_vcode IS NOT NULL THEN
        INSERT INTO _seen_pairs(emp, vcode) VALUES (v_emp, v_vcode);
      END IF;
    END IF;

    INSERT INTO public.employee_import_rows (
      batch_id, row_number, raw_data,
      employee_no, last_name, first_name, middle_name, vcode,
      resolved_store_id, resolved_store_name, resolved_account_id, resolved_group_id, resolved_position,
      validation_status, validation_errors, validation_flags, is_roving, roving_store_count
    ) VALUES (
      v_batch_id, v_idx, v_row,
      v_emp, v_last, v_first, v_middle, v_vcode,
      v_store_id, v_store_name, v_store_acct, v_store_grp, v_position,
      v_status, v_errs, v_flags, v_is_roving, v_store_cnt
    );

    -- counters
    CASE v_status
      WHEN 'valid'   THEN v_valid := v_valid + 1;
      WHEN 'flagged' THEN v_flagged := v_flagged + 1;
      WHEN 'skipped' THEN v_skipped := v_skipped + 1;
      WHEN 'blocked' THEN v_blocked := v_blocked + 1;
      ELSE NULL;
    END CASE;

    IF v_flags @> '[{"flag":"over_20_stores"}]'::jsonb THEN v_over20 := v_over20 + 1; END IF;
    IF v_status <> 'skipped' AND v_flags @> '[{"flag":"cross_account"}]'::jsonb THEN
      v_xacct := v_xacct + 1;
    END IF;
    IF v_status = 'blocked'
       AND v_errs @> '[{"msg":"cross-group: store group differs from batch group"}]'::jsonb THEN
      v_xgroup := v_xgroup + 1;
    END IF;
  END LOOP;

  -- distinct roving employees detected (>1 store, with at least one committable row)
  SELECT count(*) INTO v_roving FROM _emp_cov WHERE store_count > 1;

  -- aggregate blocking-error summary (counts per field)
  SELECT COALESCE(jsonb_object_agg(field_name, cnt), '{}'::jsonb) INTO v_summary
  FROM (
    SELECT (e.value->>'field') AS field_name, count(*) AS cnt
    FROM public.employee_import_rows r
    CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
    WHERE r.batch_id = v_batch_id
    GROUP BY 1
  ) s;

  -- A batch is committable when at least one valid/flagged row exists.
  v_final := CASE
    WHEN (v_valid + v_flagged) = 0 THEN 'validation_failed'
    ELSE 'pending_approval'
  END;

  UPDATE public.employee_import_batches
     SET total_rows              = v_total,
         valid_rows              = v_valid,
         flagged_rows            = v_flagged,
         skipped_duplicate_rows  = v_skipped,
         blocked_rows            = v_blocked,
         roving_detected         = v_roving,
         cross_account_conflicts = v_xacct,
         cross_group_conflicts   = v_xgroup,
         over_20_store_warnings  = v_over20,
         error_summary           = v_summary,
         status                  = v_final,
         updated_at              = now()
   WHERE id = v_batch_id;

  RETURN jsonb_build_object(
    'batch_id', v_batch_id,
    'status', v_final,
    'total_rows', v_total,
    'valid_rows', v_valid,
    'flagged_rows', v_flagged,
    'skipped_duplicate_rows', v_skipped,
    'blocked_rows', v_blocked,
    'roving_detected', v_roving,
    'cross_account_conflicts', v_xacct,
    'cross_group_conflicts', v_xgroup,
    'over_20_store_warnings', v_over20,
    'error_summary', v_summary
  );
END$function$;

REVOKE ALL ON FUNCTION public.submit_employee_import_v1(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_employee_import_v1(text,uuid,uuid,jsonb) TO authenticated;


-- ============================================================
-- §9  get_employee_import_preview
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_employee_import_preview(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_batch public.employee_import_batches%ROWTYPE;
BEGIN
  SELECT * INTO v_batch FROM public.employee_import_batches WHERE id = p_batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  IF NOT (public.i_have_full_access() OR v_batch.uploaded_by = auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'batch_id', v_batch.id,
    'file_name', v_batch.file_name,
    'status', v_batch.status,
    'selected_group_id', v_batch.selected_group_id,
    'selected_account_id', v_batch.selected_account_id,
    'counts', jsonb_build_object(
      'total_rows', v_batch.total_rows,
      'valid_rows', v_batch.valid_rows,
      'flagged_rows', v_batch.flagged_rows,
      'skipped_duplicate_rows', v_batch.skipped_duplicate_rows,
      'blocked_rows', v_batch.blocked_rows,
      'roving_detected', v_batch.roving_detected,
      'cross_account_conflicts', v_batch.cross_account_conflicts,
      'cross_group_conflicts', v_batch.cross_group_conflicts,
      'over_20_store_warnings', v_batch.over_20_store_warnings
    ),
    'error_summary', v_batch.error_summary,
    'detected_roving', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'employee_no', t.employee_no, 'store_count', t.cnt,
        'filled_hc_per_store', round(1.0 / t.cnt, 4))), '[]'::jsonb)
      FROM (
        SELECT employee_no, count(DISTINCT vcode) AS cnt
        FROM public.employee_import_rows
        WHERE batch_id = p_batch_id AND validation_status IN ('valid','flagged')
          AND employee_no IS NOT NULL
        GROUP BY employee_no HAVING count(DISTINCT vcode) > 1
      ) t
    ),
    'blocked_preview', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'row_number', r.row_number, 'employee_no', r.employee_no,
        'vcode', r.vcode, 'errors', r.validation_errors)), '[]'::jsonb)
      FROM public.employee_import_rows r
      WHERE r.batch_id = p_batch_id AND r.validation_status = 'blocked'
    )
  );
END$function$;

REVOKE ALL ON FUNCTION public.get_employee_import_preview(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_import_preview(uuid) TO authenticated;


-- ============================================================
-- §10  approve_employee_import_batch  (commit RPC)
-- ============================================================
-- Commits valid + flagged rows only. Blocked/skipped rows stay in
-- staging. Roving employees get one plantilla master row + fractional
-- per-store allocation rows. Approval gate: HA / SA.

CREATE OR REPLACE FUNCTION public.approve_employee_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_actor     uuid := public.get_current_profile_id();
  v_batch     public.employee_import_batches%ROWTYPE;
  v_acct_name text;
  v_emp_rec   record;
  v_store_rec record;
  v_plantilla_id uuid;
  v_roving_id uuid;
  v_store_cnt int;
  v_filled    numeric(8,4);
  v_emp_name  text;
  v_committed int := 0;
  v_emp_count int := 0;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch FROM public.employee_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)', v_batch.status
      USING ERRCODE = '22023';
  END IF;

  SELECT account_name INTO v_acct_name FROM public.accounts WHERE id = v_batch.selected_account_id;

  -- One iteration per committable employee in the batch.
  FOR v_emp_rec IN
    SELECT employee_no,
           count(DISTINCT vcode) AS store_count,
           (array_agg(last_name))[1]   AS last_name,
           (array_agg(first_name))[1]  AS first_name,
           (array_agg(middle_name))[1] AS middle_name
      FROM public.employee_import_rows
     WHERE batch_id = p_batch_id
       AND validation_status IN ('valid','flagged')
       AND employee_no IS NOT NULL
     GROUP BY employee_no
  LOOP
    v_emp_count := v_emp_count + 1;
    v_store_cnt := v_emp_rec.store_count;
    v_filled    := round(1.0 / GREATEST(v_store_cnt, 1), 4);

    -- Display name: "Last, First Middle"
    v_emp_name := v_emp_rec.last_name || ', ' || v_emp_rec.first_name
                  || COALESCE(' ' || v_emp_rec.middle_name, '');

    -- Resolve/auto-create roving group for multi-store employees.
    v_roving_id := NULL;
    IF v_store_cnt > 1 THEN
      INSERT INTO public.import_roving_groups (
        employee_no, account_id, group_id, account_name, label,
        active_store_count, filled_hc_per_store, source_import_batch_id, created_by
      ) VALUES (
        v_emp_rec.employee_no, v_batch.selected_account_id, v_batch.selected_group_id,
        v_acct_name, v_emp_name || ' — Roving',
        v_store_cnt, v_filled, p_batch_id, v_actor
      ) RETURNING id INTO v_roving_id;
    END IF;

    -- Upsert active plantilla master (1 row per employee — "1 employee total").
    -- Match the active unique index coverage (uq_plantilla_employee_no_active):
    -- status IN ('Active','For Deactivation','On Leave'). Checking only 'Active'
    -- would miss an existing live row and cause the INSERT below to violate the
    -- unique index for employees in 'For Deactivation'/'On Leave'.
    SELECT id INTO v_plantilla_id
      FROM public.plantilla
     WHERE employee_no = v_emp_rec.employee_no
       AND is_deleted = false
       AND status IN ('Active','For Deactivation','On Leave')
     LIMIT 1;

    IF v_plantilla_id IS NULL THEN
      INSERT INTO public.plantilla (
        employee_name, employee_no, emploc_no, account, status,
        account_id, last_name, first_name, middle_name,
        roving_assignment_id, is_pool_employee,
        vcode, store_id, store_name,
        source_employee_import_batch_id, created_by, moved_by_user_id
      )
      SELECT
        v_emp_name, v_emp_rec.employee_no, v_emp_rec.employee_no, v_acct_name, 'Active',
        v_batch.selected_account_id,
        v_emp_rec.last_name, v_emp_rec.first_name, v_emp_rec.middle_name,
        NULL, false,
        -- single-store: pin store; roving: leave master store NULL
        CASE WHEN v_store_cnt = 1 THEN r.vcode ELSE NULL END,
        CASE WHEN v_store_cnt = 1 THEN r.resolved_store_id ELSE NULL END,
        CASE WHEN v_store_cnt = 1 THEN r.resolved_store_name ELSE NULL END,
        p_batch_id, v_actor, v_actor
      FROM (
        SELECT vcode, resolved_store_id, resolved_store_name
        FROM public.employee_import_rows
        WHERE batch_id = p_batch_id AND employee_no = v_emp_rec.employee_no
          AND validation_status IN ('valid','flagged')
        ORDER BY row_number LIMIT 1
      ) r
      RETURNING id INTO v_plantilla_id;
    ELSE
      -- Already active — refresh names/roving linkage, do not duplicate.
      UPDATE public.plantilla
         SET employee_name = v_emp_name,
             last_name = v_emp_rec.last_name,
             first_name = v_emp_rec.first_name,
             middle_name = v_emp_rec.middle_name,
             updated_at = now(),
             updated_by = v_actor,
             source_employee_import_batch_id = p_batch_id
       WHERE id = v_plantilla_id;
    END IF;

    IF v_roving_id IS NOT NULL THEN
      UPDATE public.import_roving_groups SET plantilla_id = v_plantilla_id WHERE id = v_roving_id;
    END IF;

    -- Supersede any prior active allocations for this employee (effective dating).
    UPDATE public.employee_store_allocations
       SET is_active = false, effective_end = CURRENT_DATE
     WHERE employee_no = v_emp_rec.employee_no AND is_active;

    -- One allocation row per distinct committable store (fractional HC).
    FOR v_store_rec IN
      SELECT DISTINCT ON (vcode)
             vcode, resolved_store_id, resolved_store_name,
             resolved_account_id, resolved_group_id
        FROM public.employee_import_rows
       WHERE batch_id = p_batch_id AND employee_no = v_emp_rec.employee_no
         AND validation_status IN ('valid','flagged')
       ORDER BY vcode, row_number
    LOOP
      INSERT INTO public.employee_store_allocations (
        plantilla_id, employee_no, roving_group_id, store_id, vcode, store_name,
        account_id, group_id, filled_hc, active_store_count,
        effective_start, is_active, source_import_batch_id, created_by
      ) VALUES (
        v_plantilla_id, v_emp_rec.employee_no, v_roving_id,
        v_store_rec.resolved_store_id, v_store_rec.vcode, v_store_rec.resolved_store_name,
        COALESCE(v_store_rec.resolved_account_id, v_batch.selected_account_id),
        COALESCE(v_store_rec.resolved_group_id, v_batch.selected_group_id),
        v_filled, v_store_cnt, CURRENT_DATE, true, p_batch_id, v_actor
      );
      v_committed := v_committed + 1;
    END LOOP;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'employee_import', 'INSERT', v_plantilla_id,
            jsonb_build_object('employee_no', v_emp_rec.employee_no,
                               'store_count', v_store_cnt,
                               'filled_hc_per_store', v_filled,
                               'roving', (v_roving_id IS NOT NULL),
                               'source_import_batch_id', p_batch_id));
  END LOOP;

  UPDATE public.employee_import_batches
     SET status = 'approved', approved_by = v_uid, approved_at = now(),
         committed_rows = v_committed, updated_at = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'employee_import_batches', 'APPROVAL', p_batch_id,
          jsonb_build_object('employees', v_emp_count, 'allocations', v_committed));

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'status', 'approved',
    'employees_committed', v_emp_count,
    'allocations_created', v_committed
  );
END$function$;

REVOKE ALL ON FUNCTION public.approve_employee_import_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_employee_import_batch(uuid) TO authenticated;


-- ============================================================
-- §11  reject_employee_import_batch
-- ============================================================

CREATE OR REPLACE FUNCTION public.reject_employee_import_batch(p_batch_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_batch public.employee_import_batches%ROWTYPE;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch FROM public.employee_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status USING ERRCODE = '22023';
  END IF;

  UPDATE public.employee_import_batches
     SET status='rejected', rejected_by=v_uid, rejected_at=now(),
         rejection_reason=p_reason, updated_at=now()
   WHERE id=p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'employee_import_batches', 'APPROVAL', p_batch_id,
          jsonb_build_object('decision','rejected','reason',p_reason));

  RETURN jsonb_build_object('batch_id', p_batch_id, 'status', 'rejected');
END$function$;

REVOKE ALL ON FUNCTION public.reject_employee_import_batch(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_employee_import_batch(uuid,text) TO authenticated;


-- ============================================================
-- §12  get_employee_import_batches / get_employee_import_rows
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_employee_import_batches(p_status text DEFAULT NULL)
RETURNS SETOF public.employee_import_batches
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT b.* FROM public.employee_import_batches b
  WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
    AND (p_status IS NULL OR b.status = p_status)
  ORDER BY b.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_import_batches(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_employee_import_rows(p_batch_id uuid)
RETURNS SETOF public.employee_import_rows
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT r.* FROM public.employee_import_rows r
  WHERE r.batch_id = p_batch_id
    AND (
      public.i_have_full_access()
      OR EXISTS (SELECT 1 FROM public.employee_import_batches b
                 WHERE b.id = r.batch_id AND b.uploaded_by = auth.uid())
    )
  ORDER BY r.row_number;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_import_rows(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_import_rows(uuid) TO authenticated;


-- ============================================================
-- §13  v_store_fractional_hc  (fractional HC per store)
-- ============================================================
-- Sums active fractional allocations per store. Exposed for future MFR
-- integration WITHOUT modifying the existing MFR views in V1.
-- Vacancy count rule: a roving employee counts as 1 employee total
-- (distinct plantilla_id), while filled HC is fractional per store.

CREATE OR REPLACE VIEW public.v_store_fractional_hc AS
SELECT
  a.store_id,
  a.vcode,
  a.store_name,
  a.account_id,
  a.group_id,
  count(DISTINCT a.plantilla_id)               AS employee_count,   -- roving = 1 each
  round(sum(a.filled_hc), 4)                   AS filled_hc,         -- fractional total
  count(*) FILTER (WHERE a.roving_group_id IS NOT NULL) AS roving_allocations
FROM public.employee_store_allocations a
WHERE a.is_active
GROUP BY a.store_id, a.vcode, a.store_name, a.account_id, a.group_id;

COMMENT ON VIEW public.v_store_fractional_hc IS
  'Active fractional HC per store from employee_store_allocations. '
  'employee_count counts each (roving) employee once; filled_hc is the fractional sum. '
  'Not wired into v_workforce_health_summary / v_account_kpi in V1 (next-step integration).';

GRANT SELECT ON public.v_store_fractional_hc TO authenticated;


-- ============================================================
-- §14  RBAC-aligned Store Master wrappers
-- ============================================================
-- New RPCs ONLY. Existing store import RPCs are untouched. These allow
-- Encoder upload (validation) and HA/SA approval, sharing the import
-- RBAC model. Validation mirrors add_store_import_rows but without the
-- role_level>=90 gate so Encoders can stage Store Master imports.

CREATE OR REPLACE FUNCTION public.submit_store_import_rbac(
  p_file_name text, p_group_id uuid, p_account_id uuid, p_rows jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_role  text := public.get_my_role();
  v_bid   uuid;
  v_acct_group uuid;
  v_row   jsonb; v_idx int := 0;
  v_vcode text; v_name text; v_prov text; v_city text; v_type text; v_type_raw text;
  v_pen boolean; v_pen_raw text; v_errs jsonb;
  v_dup jsonb; v_total int := 0; v_valid int := 0; v_invalid int := 0;
  v_summary jsonb; v_final text;
BEGIN
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE='42501';
  END IF;
  IF p_file_name IS NULL OR length(trim(p_file_name))=0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: file_name required' USING ERRCODE='22023'; END IF;
  IF jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows)=0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows must be a non-empty array' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN
    RAISE EXCEPTION 'INVALID_INPUT: max 5000 rows per batch' USING ERRCODE='22023'; END IF;

  SELECT group_id INTO v_acct_group FROM public.accounts WHERE id = p_account_id;
  IF v_acct_group IS NULL OR v_acct_group <> p_group_id THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % not in group %', p_account_id, p_group_id USING ERRCODE='23503'; END IF;
  IF NOT public.i_have_full_access() AND NOT (p_account_id = ANY(public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: target account outside caller scope' USING ERRCODE='42501'; END IF;

  INSERT INTO public.store_import_batches (
    file_name, uploaded_by, uploaded_role, selected_group_id, selected_account_id, status
  ) VALUES (p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded')
  RETURNING id INTO v_bid;

  v_dup := (
    SELECT COALESCE(jsonb_agg(d.v), '[]'::jsonb) FROM (
      SELECT lower(trim(elem->>'VCODE')) AS v
      FROM jsonb_array_elements(p_rows) elem
      WHERE NULLIF(trim(elem->>'VCODE'),'') IS NOT NULL
      GROUP BY 1 HAVING count(*) > 1
    ) d
  );

  FOR v_row IN SELECT elem.value FROM jsonb_array_elements(p_rows) AS elem(value) LOOP
    v_idx := v_idx + 1; v_total := v_total + 1; v_errs := '[]'::jsonb;
    v_vcode := NULLIF(trim(COALESCE(v_row->>'VCODE','')),'');
    v_name  := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')),'');
    v_prov  := NULLIF(trim(COALESCE(v_row->>'AREA_PROVINCE','')),'');
    v_city  := NULLIF(trim(COALESCE(v_row->>'AREA_CITY','')),'');
    v_type_raw := lower(NULLIF(trim(COALESCE(v_row->>'EMPLOYMENT_TYPE', v_row->>'TYPE','')),''));
    v_pen_raw  := lower(NULLIF(trim(COALESCE(v_row->>'WITH_PENALTY','')),''));

    IF v_vcode IS NULL THEN v_errs := v_errs || jsonb_build_object('field','VCODE','msg','required'); END IF;
    IF v_name  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','STORE_NAME','msg','required'); END IF;
    IF v_prov  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','AREA_PROVINCE','msg','required'); END IF;
    IF v_city  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','AREA_CITY','msg','required'); END IF;

    IF v_type_raw IS NULL THEN v_type := NULL;
    ELSIF v_type_raw IN ('stationary','roving') THEN v_type := v_type_raw;
    ELSE v_errs := v_errs || jsonb_build_object('field','EMPLOYMENT_TYPE','msg','must be stationary or roving'); v_type := NULL; END IF;

    IF v_pen_raw IS NULL THEN v_pen := NULL;
    ELSIF v_pen_raw IN ('yes','y','true','1') THEN v_pen := true;
    ELSIF v_pen_raw IN ('no','n','false','0') THEN v_pen := false;
    ELSE v_errs := v_errs || jsonb_build_object('field','WITH_PENALTY','msg','must be yes or no'); v_pen := NULL; END IF;

    IF v_vcode IS NOT NULL AND v_dup ? lower(v_vcode) THEN
      v_errs := v_errs || jsonb_build_object('field','VCODE','msg','duplicate within CSV'); END IF;
    IF v_vcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.stores WHERE lower(vcode)=lower(v_vcode) AND status='active') THEN
      v_errs := v_errs || jsonb_build_object('field','VCODE','msg','already exists in active stores'); END IF;

    INSERT INTO public.store_import_rows (
      batch_id,row_number,raw_data,vcode,store_name,area_province,area_city,type,with_penalty,validation_status,validation_errors
    ) VALUES (
      v_bid, v_idx, v_row, v_vcode, v_name, v_prov, v_city, v_type, v_pen,
      CASE WHEN jsonb_array_length(v_errs)=0 THEN 'valid' ELSE 'invalid' END, v_errs
    );
    IF jsonb_array_length(v_errs)=0 THEN v_valid := v_valid+1; ELSE v_invalid := v_invalid+1; END IF;
  END LOOP;

  SELECT COALESCE(jsonb_object_agg(field_name,cnt),'{}'::jsonb) INTO v_summary FROM (
    SELECT (e.value->>'field') AS field_name, count(*) AS cnt
    FROM public.store_import_rows r CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
    WHERE r.batch_id=v_bid GROUP BY 1
  ) s;

  v_final := CASE WHEN v_total=0 OR v_invalid>0 THEN 'validation_failed' ELSE 'pending_approval' END;
  UPDATE public.store_import_batches
     SET total_rows=v_total, valid_rows=v_valid, invalid_rows=v_invalid,
         error_summary=v_summary, status=v_final, updated_at=now()
   WHERE id=v_bid;

  RETURN jsonb_build_object('batch_id',v_bid,'status',v_final,'total_rows',v_total,
    'valid_rows',v_valid,'invalid_rows',v_invalid,'error_summary',v_summary);
END$function$;

REVOKE ALL ON FUNCTION public.submit_store_import_rbac(text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_store_import_rbac(text,uuid,uuid,jsonb) TO authenticated;


CREATE OR REPLACE FUNCTION public.approve_store_import_batch_rbac(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_batch public.store_import_batches%ROWTYPE;
  v_row record; v_existing uuid; v_inserted int := 0; v_updated int := 0;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)', v_batch.status USING ERRCODE='22023'; END IF;
  IF v_batch.invalid_rows > 0 THEN
    RAISE EXCEPTION 'INVALID_STATE: batch contains invalid rows' USING ERRCODE='22023'; END IF;

  FOR v_row IN SELECT * FROM public.store_import_rows
    WHERE batch_id=p_batch_id AND validation_status='valid' ORDER BY row_number
  LOOP
    SELECT id INTO v_existing FROM public.stores
     WHERE lower(vcode)=lower(v_row.vcode) AND status='active' LIMIT 1;
    IF v_existing IS NULL THEN
      INSERT INTO public.stores (vcode,store_name,area_province,area_city,employment_type,with_penalty,
        group_id,account_id,status,created_by,updated_by,approved_by,approved_at,source_import_id)
      VALUES (v_row.vcode,v_row.store_name,v_row.area_province,v_row.area_city,v_row.type,v_row.with_penalty,
        v_batch.selected_group_id,v_batch.selected_account_id,'active',v_uid,v_uid,v_uid,now(),p_batch_id)
      RETURNING id INTO v_existing;
      v_inserted := v_inserted+1;
    ELSE
      UPDATE public.stores SET store_name=v_row.store_name,area_province=v_row.area_province,
        area_city=v_row.area_city,employment_type=v_row.type,with_penalty=v_row.with_penalty,
        group_id=v_batch.selected_group_id,account_id=v_batch.selected_account_id,status='active',
        updated_by=v_uid,approved_by=v_uid,approved_at=now(),source_import_id=p_batch_id
      WHERE id=v_existing;
      v_updated := v_updated+1;
    END IF;
  END LOOP;

  UPDATE public.store_import_batches
     SET status='approved',approved_by=v_uid,approved_at=now(),updated_at=now()
   WHERE id=p_batch_id;

  INSERT INTO public.audit_logs(actor_id,module,action,record_id,new_data)
  VALUES (v_uid,'store_import_batches','APPROVAL',p_batch_id,
          jsonb_build_object('inserted',v_inserted,'updated',v_updated,'rbac','ha_sa'));

  RETURN jsonb_build_object('batch_id',p_batch_id,'status','approved','inserted',v_inserted,'updated',v_updated);
END$function$;

REVOKE ALL ON FUNCTION public.approve_store_import_batch_rbac(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_store_import_batch_rbac(uuid) TO authenticated;


CREATE OR REPLACE FUNCTION public.reject_store_import_batch_rbac(p_batch_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_batch public.store_import_batches%ROWTYPE;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE='42501'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason))=0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required' USING ERRCODE='22023'; END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed','draft_uploaded') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status USING ERRCODE='22023'; END IF;

  UPDATE public.store_import_batches
     SET status='rejected',rejected_by=v_uid,rejected_at=now(),rejection_reason=p_reason,updated_at=now()
   WHERE id=p_batch_id;

  INSERT INTO public.audit_logs(actor_id,module,action,record_id,new_data)
  VALUES (v_uid,'store_import_batches','APPROVAL',p_batch_id,
          jsonb_build_object('decision','rejected','reason',p_reason,'rbac','ha_sa'));

  RETURN jsonb_build_object('batch_id',p_batch_id,'status','rejected');
END$function$;

REVOKE ALL ON FUNCTION public.reject_store_import_batch_rbac(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_store_import_batch_rbac(uuid,text) TO authenticated;


-- ============================================================
-- §15  Store Master template CSV — GROUP/ACCOUNT removed
-- ============================================================
-- The Store Master CSV contract no longer carries GROUP/ACCOUNT.
-- Group and account are selected in the UI and derived server-side
-- from the batch's selected_group_id/selected_account_id, so the
-- template must not invite uploaders to supply (untrusted) group or
-- account columns. submit_store_import_rbac never reads GROUP/ACCOUNT
-- from rows. Gate aligned to the import upload RBAC (Encoder/HA/SA)
-- so encoders can download the template they are allowed to upload.
CREATE OR REPLACE FUNCTION public.get_store_import_template_csv()
 RETURNS TABLE(file_name text, content_type text, csv text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required' USING ERRCODE='42501';
  END IF;

  RETURN QUERY SELECT
    'import_plantilla_store_master_template.csv'::text,
    'text/csv'::text,
    'VCODE,STORE_NAME,AREA_PROVINCE,AREA_CITY,POSITION,EMPLOYMENT_TYPE,REQUIRED_HC,WITH_PENALTY' || E'\n' ||
    'PG-DAU-001,Super 8 Dau,Pampanga,Angeles,Merchandiser,stationary,1,yes' || E'\n' ||
    'PG-SF-001,Puregold San Fernando,Pampanga,San Fernando,Merchandiser,stationary,1,no' || E'\n';
END$function$;

REVOKE ALL ON FUNCTION public.get_store_import_template_csv() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_store_import_template_csv() TO authenticated;
