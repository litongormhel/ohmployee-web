-- ============================================================
-- ohm#7k4p9xq2 — Add Moses HQ to Existing Data Archival Workflow
-- Migration: 20260701000000_moses_hq_archive_extension.sql
-- Depends on:
--   20260907000000_enterprise_data_archival_center.sql
--     (system_archive_batches, fn_archive_plantilla_data,
--      fn_archive_all_operational_data, fn_rollback_archive_batch,
--      fn_get_archive_impact_preview, fn_get_archive_batch_history)
-- ============================================================
-- Purpose:
--   Extends the Enterprise Data Archival Center to include Moses HQ
--   (Workforce Pool module) as a first-class archival module.
--
--   Changes:
--     • Adds qa_archive_batch_id column to all Moses HQ operational tables
--     • Adds deleted_at column to workforce_assignments and
--       workforce_pool_request_items (existing soft-delete pattern)
--     • Extends system_archive_batches with moses_hq_count column and
--       'moses_hq' as a valid action_type
--     • New fn_archive_moses_hq_data — standalone Moses HQ archive
--     • fn_archive_plantilla_data — cascades into Moses HQ under same batch
--     • fn_archive_all_operational_data — includes Moses HQ as Module 6
--     • fn_rollback_archive_batch — restores full Moses HQ hierarchy
--     • fn_get_archive_impact_preview — adds Moses HQ breakdown counts
--     • fn_get_archive_batch_history — adds moses_hq_count to return type
--
--   Archival scope (Moses HQ):
--     workforce_assignments, workforce_slot_reviews,
--     workforce_pool_request_items, workforce_pool_requests,
--     workforce_pool_slots, vacancy_coverage,
--     vacancies WHERE is_pool_vacancy = true
--
--   NOT archived (per requirements):
--     workforce_pool_types (master config)
--     workforce_pool_vcode_sequences (master config)
--     workforce_slot_reviews.decided_at / approval fields
--     archival_audit_logs, system_archive_batches (audit/archive history)
--
--   Execution order inside archive functions:
--     Assignments → Slot Reviews → Request Items → Requests →
--     Vacancy Coverage → Pool Slots → Pool Vacancies → Archive Log
--
--   Rollback:
--     Full hierarchy restored in reverse order under same qa_archive_batch_id.
--     Preserves IDs and relationships. Uses existing 72-active-hour window.
--
-- Sections:
--   §1  Add qa_archive_batch_id + soft-delete columns to Moses HQ tables
--   §2  Extend system_archive_batches (moses_hq_count + action_type CHECK)
--   §3  fn_get_archive_impact_preview — add Moses HQ preview counts
--   §4  fn_archive_moses_hq_data — standalone Moses HQ archive
--   §5  fn_archive_plantilla_data — cascade Moses HQ under same batch
--   §6  fn_archive_all_operational_data — QA Reset includes Moses HQ
--   §7  fn_rollback_archive_batch — restore Moses HQ hierarchy
--   §8  fn_get_archive_batch_history — add moses_hq_count to return type
-- ============================================================


-- ── §1. Add qa_archive_batch_id + soft-delete columns ─────────────────────
-- Stamp each Moses HQ operational row with the archive batch UUID for
-- batch-scoped rollback queries.  Soft-delete columns follow the existing
-- pattern used by hr_emploc (deleted_at) and workforce_pool_slots (is_active).

ALTER TABLE public.workforce_assignments
  ADD COLUMN IF NOT EXISTS deleted_at          timestamptz,
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

CREATE INDEX IF NOT EXISTS idx_wa_qa_archive_batch_id
  ON public.workforce_assignments (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

ALTER TABLE public.workforce_pool_request_items
  ADD COLUMN IF NOT EXISTS deleted_at          timestamptz,
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

CREATE INDEX IF NOT EXISTS idx_wpri_qa_archive_batch_id
  ON public.workforce_pool_request_items (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

-- workforce_pool_slots already has deleted_at and is_active
ALTER TABLE public.workforce_pool_slots
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

CREATE INDEX IF NOT EXISTS idx_wps_qa_archive_batch_id
  ON public.workforce_pool_slots (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

-- workforce_pool_requests already has deleted_at
ALTER TABLE public.workforce_pool_requests
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

CREATE INDEX IF NOT EXISTS idx_wpr_qa_archive_batch_id
  ON public.workforce_pool_requests (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

-- vacancy_coverage already has archived_at and archived_by
ALTER TABLE public.vacancy_coverage
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

CREATE INDEX IF NOT EXISTS idx_vc_qa_archive_batch_id
  ON public.vacancy_coverage (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

-- workforce_slot_reviews already has deleted_at
ALTER TABLE public.workforce_slot_reviews
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid;

CREATE INDEX IF NOT EXISTS idx_wsr_qa_archive_batch_id
  ON public.workforce_slot_reviews (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;


-- ── §2. Extend system_archive_batches ─────────────────────────────────────
-- Add moses_hq_count and extend action_type CHECK to include 'moses_hq'.

ALTER TABLE public.system_archive_batches
  ADD COLUMN IF NOT EXISTS moses_hq_count integer NOT NULL DEFAULT 0;

-- Drop and recreate CHECK to include 'moses_hq'
ALTER TABLE public.system_archive_batches
  DROP CONSTRAINT IF EXISTS chk_sab_action_type;

ALTER TABLE public.system_archive_batches
  ADD CONSTRAINT chk_sab_action_type CHECK (
    action_type IN ('qa_reset', 'plantilla', 'vacancy', 'hr_emploc', 'moses_hq')
  );


-- ── §3. fn_get_archive_impact_preview ─────────────────────────────────────
-- Extended to include Moses HQ breakdown counts.
-- Moses HQ counts: pool_count (distinct active pool types with slots),
-- assignment_count, open_slot_count, request_count.

CREATE OR REPLACE FUNCTION public.fn_get_archive_impact_preview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_plantilla_count          integer;
  v_vacancy_count            integer;
  v_hr_emploc_count          integer;
  v_moses_hq_pool_count      integer;
  v_moses_hq_assign_count    integer;
  v_moses_hq_open_slot_count integer;
  v_moses_hq_request_count   integer;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*) INTO v_plantilla_count
  FROM public.plantilla
  WHERE is_deleted = false
    AND (is_archived = false OR is_archived IS NULL);

  SELECT COUNT(*) INTO v_vacancy_count
  FROM public.vacancies
  WHERE deleted_at IS NULL
    AND (is_archived = false OR is_archived IS NULL);

  SELECT COUNT(*) INTO v_hr_emploc_count
  FROM public.hr_emploc
  WHERE deleted_at IS NULL;

  -- Moses HQ: distinct active pool types that have open slots
  SELECT COUNT(DISTINCT pool_type_id) INTO v_moses_hq_pool_count
  FROM public.workforce_pool_slots
  WHERE is_active = true
    AND deleted_at IS NULL;

  -- Active workforce assignments (not yet soft-deleted)
  SELECT COUNT(*) INTO v_moses_hq_assign_count
  FROM public.workforce_assignments
  WHERE deleted_at IS NULL
    AND status NOT IN ('Completed', 'Ended', 'Cancelled');

  -- Open pool slots
  SELECT COUNT(*) INTO v_moses_hq_open_slot_count
  FROM public.workforce_pool_slots
  WHERE is_active = true
    AND deleted_at IS NULL;

  -- Active pool requests
  SELECT COUNT(*) INTO v_moses_hq_request_count
  FROM public.workforce_pool_requests
  WHERE deleted_at IS NULL
    AND status NOT IN ('rejected', 'cancelled');

  RETURN jsonb_build_object(
    'plantilla_count',             v_plantilla_count,
    'vacancy_count',               v_vacancy_count,
    'hr_emploc_count',             v_hr_emploc_count,
    'total_count',                 v_plantilla_count + v_vacancy_count + v_hr_emploc_count,
    'moses_hq_pool_count',         v_moses_hq_pool_count,
    'moses_hq_assignment_count',   v_moses_hq_assign_count,
    'moses_hq_open_slot_count',    v_moses_hq_open_slot_count,
    'moses_hq_request_count',      v_moses_hq_request_count
  );
END;
$$;

COMMENT ON FUNCTION public.fn_get_archive_impact_preview() IS
  'Returns counts of active records that would be affected by each module archive. '
  'Extended to include Moses HQ breakdown (pool count, assignment count, '
  'open slot count, request count). Super Admin only. No data is modified.';

REVOKE ALL ON FUNCTION public.fn_get_archive_impact_preview() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_impact_preview() TO authenticated;


-- ── §4. fn_archive_moses_hq_data ──────────────────────────────────────────
-- Standalone Moses HQ archive.
-- Archives in dependency order:
--   Assignments → Slot Reviews → Request Items → Requests →
--   Vacancy Coverage → Pool Slots → Pool Vacancies → Archive Log
-- Registers one row in system_archive_batches (action_type = 'moses_hq').

CREATE OR REPLACE FUNCTION public.fn_archive_moses_hq_data(
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id          uuid;
  v_caller_name        text;
  v_batch_id           uuid := gen_random_uuid();
  v_now                timestamptz := now();
  v_assign_count       integer := 0;
  v_slot_review_count  integer := 0;
  v_req_item_count     integer := 0;
  v_request_count      integer := 0;
  v_coverage_count     integer := 0;
  v_slot_count         integer := 0;
  v_pool_vacancy_count integer := 0;
  v_moses_hq_count     integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'archive_reason must be at least 10 characters'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();

  -- 1. WORKFORCE ASSIGNMENTS
  UPDATE public.workforce_assignments
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  -- 2. SLOT REVIEWS (Review Queue)
  UPDATE public.workforce_slot_reviews
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  -- 3. POOL REQUEST ITEMS
  UPDATE public.workforce_pool_request_items
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  -- 4. POOL REQUESTS
  UPDATE public.workforce_pool_requests
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  -- 5. VACANCY COVERAGE
  UPDATE public.vacancy_coverage
  SET
    archived_at         = v_now,
    archived_by         = v_caller_id,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  -- 6. POOL SLOTS
  UPDATE public.workforce_pool_slots
  SET
    is_active           = false,
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE is_active = true
    AND deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_count = ROW_COUNT;

  -- 7. POOL VACANCIES (vacancies WHERE is_pool_vacancy = true)
  UPDATE public.vacancies
  SET
    is_archived         = true,
    archived_at         = v_now,
    archived_by_id      = v_caller_id,
    archived_by         = v_caller_name,
    archive_reason      = p_reason,
    status              = 'Archived',
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE is_pool_vacancy = true
    AND deleted_at IS NULL
    AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_pool_vacancy_count = ROW_COUNT;

  v_moses_hq_count := v_assign_count + v_slot_review_count + v_req_item_count
                    + v_request_count + v_coverage_count + v_slot_count
                    + v_pool_vacancy_count;

  -- Register batch
  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count,
     moses_hq_count, status)
  VALUES
    (v_batch_id, 'moses_hq', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72),
     0, 0, 0, v_moses_hq_count, 'ACTIVE');

  -- Audit
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('moses_hq_archive', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id',        v_batch_id,
       'action_type',             'moses_hq',
       'executed_by',             v_caller_id,
       'executed_at',             v_now,
       'reason',                  p_reason,
       'assignment_count',        v_assign_count,
       'slot_review_count',       v_slot_review_count,
       'request_item_count',      v_req_item_count,
       'request_count',           v_request_count,
       'coverage_count',          v_coverage_count,
       'slot_count',              v_slot_count,
       'pool_vacancy_count',      v_pool_vacancy_count,
       'moses_hq_count',          v_moses_hq_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',        v_batch_id,
    'moses_hq_count',          v_moses_hq_count,
    'assignment_count',        v_assign_count,
    'slot_review_count',       v_slot_review_count,
    'request_item_count',      v_req_item_count,
    'request_count',           v_request_count,
    'coverage_count',          v_coverage_count,
    'slot_count',              v_slot_count,
    'pool_vacancy_count',      v_pool_vacancy_count,
    'executed_by',             v_caller_id,
    'executed_at',             v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_archive_moses_hq_data(text) IS
  'Standalone Moses HQ archive: soft-archives workforce_assignments, '
  'workforce_slot_reviews, workforce_pool_request_items, workforce_pool_requests, '
  'vacancy_coverage, workforce_pool_slots, and pool vacancies in dependency order. '
  'Registers one system_archive_batches row (action_type = ''moses_hq'') '
  'for 72-active-hour rollback. Super Admin only. Reason >= 10 characters required.';

REVOKE ALL ON FUNCTION public.fn_archive_moses_hq_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_moses_hq_data(text) TO authenticated;


-- ── §5. fn_archive_plantilla_data ─────────────────────────────────────────
-- Extended to cascade into Moses HQ under the same batch_id.
-- Moses HQ is an operational child of Plantilla (employees in pools
-- derived from plantilla deployment cycle).

CREATE OR REPLACE FUNCTION public.fn_archive_plantilla_data(
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id          uuid;
  v_caller_name        text;
  v_batch_id           uuid := gen_random_uuid();
  v_now                timestamptz := now();
  v_plantilla_count    integer := 0;
  v_slots_count        integer := 0;
  v_assign_count       integer := 0;
  v_slot_review_count  integer := 0;
  v_req_item_count     integer := 0;
  v_request_count      integer := 0;
  v_coverage_count     integer := 0;
  v_pool_slot_count    integer := 0;
  v_pool_vacancy_count integer := 0;
  v_moses_hq_count     integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'archive_reason must be at least 10 characters'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();

  -- Archive Plantilla rows
  UPDATE public.plantilla
  SET
    is_archived         = true,
    archived_at         = v_now,
    archived_by         = v_caller_id,
    archive_reason      = p_reason,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE is_deleted = false
    AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

  -- Close open Plantilla Slots
  UPDATE public.plantilla_slots
  SET
    slot_status         = 'closed',
    closed_at           = v_now,
    closed_by           = v_caller_id,
    closure_reason_code = 'QA_RESET',
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE slot_status <> 'closed';
  GET DIAGNOSTICS v_slots_count = ROW_COUNT;

  -- CASCADE: MOSES HQ (operational child of Plantilla)
  -- Order: Assignments → Slot Reviews → Request Items → Requests →
  --        Vacancy Coverage → Pool Slots → Pool Vacancies

  UPDATE public.workforce_assignments
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  UPDATE public.workforce_slot_reviews
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  UPDATE public.workforce_pool_request_items
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  UPDATE public.workforce_pool_requests
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  UPDATE public.vacancy_coverage
  SET
    archived_at         = v_now,
    archived_by         = v_caller_id,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  UPDATE public.workforce_pool_slots
  SET
    is_active           = false,
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE is_active = true
    AND deleted_at IS NULL;
  GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

  UPDATE public.vacancies
  SET
    is_archived         = true,
    archived_at         = v_now,
    archived_by_id      = v_caller_id,
    archived_by         = v_caller_name,
    archive_reason      = p_reason,
    status              = 'Archived',
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE is_pool_vacancy = true
    AND deleted_at IS NULL
    AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_pool_vacancy_count = ROW_COUNT;

  v_moses_hq_count := v_assign_count + v_slot_review_count + v_req_item_count
                    + v_request_count + v_coverage_count + v_pool_slot_count
                    + v_pool_vacancy_count;

  -- Register batch
  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count,
     moses_hq_count, status)
  VALUES
    (v_batch_id, 'plantilla', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72),
     v_plantilla_count, 0, 0, v_moses_hq_count, 'ACTIVE');

  -- Audit
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('plantilla_archive', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id',        v_batch_id,
       'action_type',             'plantilla',
       'executed_by',             v_caller_id,
       'executed_at',             v_now,
       'reason',                  p_reason,
       'plantilla_count',         v_plantilla_count,
       'slots_count',             v_slots_count,
       'moses_hq_cascade',        true,
       'assignment_count',        v_assign_count,
       'slot_review_count',       v_slot_review_count,
       'request_item_count',      v_req_item_count,
       'request_count',           v_request_count,
       'coverage_count',          v_coverage_count,
       'pool_slot_count',         v_pool_slot_count,
       'pool_vacancy_count',      v_pool_vacancy_count,
       'moses_hq_count',          v_moses_hq_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',        v_batch_id,
    'plantilla_count',         v_plantilla_count,
    'slots_count',             v_slots_count,
    'moses_hq_count',          v_moses_hq_count,
    'assignment_count',        v_assign_count,
    'slot_review_count',       v_slot_review_count,
    'request_item_count',      v_req_item_count,
    'request_count',           v_request_count,
    'coverage_count',          v_coverage_count,
    'pool_slot_count',         v_pool_slot_count,
    'pool_vacancy_count',      v_pool_vacancy_count,
    'executed_by',             v_caller_id,
    'executed_at',             v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_archive_plantilla_data(text) IS
  'Archives all active Plantilla rows, closes open Plantilla Slots, and cascades '
  'into Moses HQ (workforce_assignments, workforce_slot_reviews, '
  'workforce_pool_request_items, workforce_pool_requests, vacancy_coverage, '
  'workforce_pool_slots, pool vacancies) under the same batch_id. '
  'Moses HQ is an operational child of Plantilla. '
  'Registers one system_archive_batches row for rollback tracking. '
  'Super Admin only. Reason >= 10 characters required.';

REVOKE ALL ON FUNCTION public.fn_archive_plantilla_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_plantilla_data(text) TO authenticated;


-- ── §6. fn_archive_all_operational_data ───────────────────────────────────
-- QA Reset: extended to include Moses HQ as Module 6.
-- Archives ALL active operational records from Plantilla, Vacancies,
-- HR Emploc, Plantilla Slots, Headcount Requests, and Moses HQ in a single
-- atomic transaction under one shared archive_batch_id.

CREATE OR REPLACE FUNCTION public.fn_archive_all_operational_data(
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id          uuid;
  v_caller_name        text;
  v_batch_id           uuid := gen_random_uuid();
  v_now                timestamptz := now();
  v_plantilla_count    integer := 0;
  v_vacancy_count      integer := 0;
  v_hr_emploc_count    integer := 0;
  v_slots_count        integer := 0;
  v_hc_count           integer := 0;
  v_assign_count       integer := 0;
  v_slot_review_count  integer := 0;
  v_req_item_count     integer := 0;
  v_request_count      integer := 0;
  v_coverage_count     integer := 0;
  v_pool_slot_count    integer := 0;
  v_pool_vacancy_count integer := 0;
  v_moses_hq_count     integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'archive_reason must be at least 10 characters'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();

  -- MODULE 1: PLANTILLA
  UPDATE public.plantilla
  SET
    is_archived         = true,
    archived_at         = v_now,
    archived_by         = v_caller_id,
    archive_reason      = p_reason,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE is_deleted = false
    AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

  -- MODULE 2: VACANCIES (regular + pool vacancies covered here)
  UPDATE public.vacancies
  SET
    is_archived         = true,
    archived_at         = v_now,
    archived_by_id      = v_caller_id,
    archived_by         = v_caller_name,
    archive_reason      = p_reason,
    status              = 'Archived',
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL
    AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

  -- MODULE 3: HR EMPLOC
  UPDATE public.hr_emploc
  SET
    deleted_at          = v_now,
    qa_archived_at      = v_now,
    qa_archived_by      = v_caller_id,
    qa_archive_reason   = p_reason,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_hr_emploc_count = ROW_COUNT;

  -- MODULE 4: PLANTILLA SLOTS
  UPDATE public.plantilla_slots
  SET
    slot_status         = 'closed',
    closed_at           = v_now,
    closed_by           = v_caller_id,
    closure_reason_code = 'QA_RESET',
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE slot_status <> 'closed';
  GET DIAGNOSTICS v_slots_count = ROW_COUNT;

  -- MODULE 5: HEADCOUNT REQUESTS
  UPDATE public.headcount_requests
  SET
    is_archived         = true,
    archived_at         = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE is_archived = false;
  GET DIAGNOSTICS v_hc_count = ROW_COUNT;

  -- MODULE 6: MOSES HQ
  -- Order: Assignments → Slot Reviews → Request Items → Requests →
  --        Vacancy Coverage → Pool Slots
  -- (Pool vacancies already archived in MODULE 2 via full vacancy sweep)

  UPDATE public.workforce_assignments
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  UPDATE public.workforce_slot_reviews
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  UPDATE public.workforce_pool_request_items
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  UPDATE public.workforce_pool_requests
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  UPDATE public.vacancy_coverage
  SET
    archived_at         = v_now,
    archived_by         = v_caller_id,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  UPDATE public.workforce_pool_slots
  SET
    is_active           = false,
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE is_active = true
    AND deleted_at IS NULL;
  GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

  v_moses_hq_count := v_assign_count + v_slot_review_count + v_req_item_count
                    + v_request_count + v_coverage_count + v_pool_slot_count;

  -- Register batch in canonical registry
  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count,
     moses_hq_count, status)
  VALUES
    (v_batch_id, 'qa_reset', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72),
     v_plantilla_count, v_vacancy_count, v_hr_emploc_count,
     v_moses_hq_count, 'ACTIVE');

  -- Audit summary row
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('qa_reset_enterprise', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id',          v_batch_id,
       'action_type',               'qa_reset',
       'executed_by',               v_caller_id,
       'executed_at',               v_now,
       'reason',                    p_reason,
       'plantilla_count',           v_plantilla_count,
       'vacancy_count',             v_vacancy_count,
       'hr_emploc_count',           v_hr_emploc_count,
       'slots_count',               v_slots_count,
       'headcount_request_count',   v_hc_count,
       'moses_hq_assignment_count', v_assign_count,
       'moses_hq_slot_review_count',v_slot_review_count,
       'moses_hq_req_item_count',   v_req_item_count,
       'moses_hq_request_count',    v_request_count,
       'moses_hq_coverage_count',   v_coverage_count,
       'moses_hq_pool_slot_count',  v_pool_slot_count,
       'moses_hq_count',            v_moses_hq_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',           v_batch_id,
    'plantilla_count',            v_plantilla_count,
    'vacancy_count',              v_vacancy_count,
    'hr_emploc_count',            v_hr_emploc_count,
    'slots_count',                v_slots_count,
    'headcount_request_count',    v_hc_count,
    'moses_hq_count',             v_moses_hq_count,
    'moses_hq_assignment_count',  v_assign_count,
    'moses_hq_request_count',     v_request_count,
    'moses_hq_pool_slot_count',   v_pool_slot_count,
    'executed_by',                v_caller_id,
    'executed_at',                v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_archive_all_operational_data(text) IS
  'QA Reset Archive: soft-archives ALL active Plantilla, Vacancies, HR Emploc, '
  'Plantilla Slots, Headcount Requests, and Moses HQ (workforce_assignments, '
  'workforce_slot_reviews, workforce_pool_request_items, workforce_pool_requests, '
  'vacancy_coverage, workforce_pool_slots) in a single atomic transaction under one '
  'archive_batch_id. Registers in system_archive_batches for 72-active-hour rollback '
  '(Sunday excluded). No hard deletes. Super Admin only. Reason >= 10 characters required.';

REVOKE ALL ON FUNCTION public.fn_archive_all_operational_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_all_operational_data(text) TO authenticated;


-- ── §7. fn_rollback_archive_batch ─────────────────────────────────────────
-- Extended to restore Moses HQ hierarchy for action_type IN
-- ('moses_hq', 'plantilla', 'qa_reset').
-- Restoration order (reverse of archive): Pool Vacancies → Pool Slots →
-- Vacancy Coverage → Requests → Request Items → Slot Reviews → Assignments

CREATE OR REPLACE FUNCTION public.fn_rollback_archive_batch(
  p_batch_id uuid,
  p_reason   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_batch                record;
  v_caller_id            uuid;
  v_now                  timestamptz;
  v_plantilla_count      integer := 0;
  v_vacancy_count        integer := 0;
  v_hr_emploc_count      integer := 0;
  v_slots_count          integer := 0;
  v_hc_count             integer := 0;
  v_assign_count         integer := 0;
  v_slot_review_count    integer := 0;
  v_req_item_count       integer := 0;
  v_request_count        integer := 0;
  v_coverage_count       integer := 0;
  v_pool_slot_count      integer := 0;
  v_pool_vacancy_count   integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'rollback_reason is required and must not be empty'
      USING ERRCODE = '22000';
  END IF;

  -- Lock the batch row to prevent concurrent rollbacks
  SELECT * INTO v_batch
  FROM public.system_archive_batches
  WHERE archive_batch_id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Archive batch % not found', p_batch_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status = 'ROLLED_BACK' THEN
    RAISE EXCEPTION 'Archive batch has already been rolled back'
      USING ERRCODE = '55000';
  END IF;

  -- Check rollback window (72 active hours from execution, Sunday excluded)
  v_now := now();
  IF v_now > v_batch.rollback_deadline THEN
    UPDATE public.system_archive_batches
    SET status = 'EXPIRED'
    WHERE id = v_batch.id
      AND status = 'ACTIVE';

    RAISE EXCEPTION 'Rollback window has expired. This archive is now final.'
      USING ERRCODE = '55000';
  END IF;

  v_caller_id := public.get_current_profile_id();

  -- ── RESTORE PLANTILLA ───────────────────────────────────────────────────
  IF v_batch.action_type IN ('plantilla', 'qa_reset') THEN
    UPDATE public.plantilla
    SET
      is_archived         = false,
      archived_at         = NULL,
      archived_by         = NULL,
      archive_reason      = NULL,
      restored_at         = v_now,
      restored_by         = v_caller_id,
      qa_archive_batch_id = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id
      AND is_archived = true;
    GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

    -- Reopen plantilla slots closed by this batch
    UPDATE public.plantilla_slots
    SET
      slot_status         = 'open',
      closed_at           = NULL,
      closed_by           = NULL,
      closure_reason_code = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id
      AND slot_status          = 'closed'
      AND closure_reason_code  = 'QA_RESET';
    GET DIAGNOSTICS v_slots_count = ROW_COUNT;
  END IF;

  -- ── RESTORE VACANCIES ───────────────────────────────────────────────────
  IF v_batch.action_type IN ('vacancy', 'qa_reset') THEN
    UPDATE public.vacancies
    SET
      is_archived         = false,
      archived_at         = NULL,
      archived_by_id      = NULL,
      archived_by         = NULL,
      archive_reason      = NULL,
      status              = 'Open',
      restored_at         = v_now,
      restored_by         = v_caller_id,
      qa_archive_batch_id = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id
      AND is_archived = true;
    GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

    UPDATE public.headcount_requests
    SET
      is_archived         = false,
      archived_at         = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now
    WHERE qa_archive_batch_id = p_batch_id
      AND is_archived = true;
    GET DIAGNOSTICS v_hc_count = ROW_COUNT;
  END IF;

  -- ── RESTORE HR EMPLOC ───────────────────────────────────────────────────
  IF v_batch.action_type IN ('hr_emploc', 'qa_reset') THEN
    UPDATE public.hr_emploc
    SET
      deleted_at          = NULL,
      qa_archived_at      = NULL,
      qa_archived_by      = NULL,
      qa_archive_reason   = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id;
    GET DIAGNOSTICS v_hr_emploc_count = ROW_COUNT;
  END IF;

  -- ── RESTORE MOSES HQ ────────────────────────────────────────────────────
  -- Reverse order: Pool Vacancies → Pool Slots → Vacancy Coverage →
  -- Requests → Request Items → Slot Reviews → Assignments
  IF v_batch.action_type IN ('moses_hq', 'plantilla', 'qa_reset') THEN

    -- Restore pool vacancies (standalone moses_hq only; qa_reset already restored all vacancies above)
    IF v_batch.action_type = 'moses_hq' THEN
      UPDATE public.vacancies
      SET
        is_archived         = false,
        archived_at         = NULL,
        archived_by_id      = NULL,
        archived_by         = NULL,
        archive_reason      = NULL,
        status              = 'Open',
        restored_at         = v_now,
        restored_by         = v_caller_id,
        qa_archive_batch_id = NULL,
        updated_at          = v_now,
        updated_by          = v_caller_id
      WHERE qa_archive_batch_id = p_batch_id
        AND is_pool_vacancy = true
        AND is_archived = true;
      GET DIAGNOSTICS v_pool_vacancy_count = ROW_COUNT;
    END IF;

    -- Restore pool slots
    UPDATE public.workforce_pool_slots
    SET
      is_active           = true,
      deleted_at          = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id
      AND is_active = false;
    GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

    -- Restore vacancy coverage
    UPDATE public.vacancy_coverage
    SET
      archived_at         = NULL,
      archived_by         = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id
      AND archived_at IS NOT NULL;
    GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

    -- Restore pool requests
    UPDATE public.workforce_pool_requests
    SET
      deleted_at          = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id
      AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_request_count = ROW_COUNT;

    -- Restore pool request items
    UPDATE public.workforce_pool_request_items
    SET
      deleted_at          = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now
    WHERE qa_archive_batch_id = p_batch_id
      AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

    -- Restore slot reviews
    UPDATE public.workforce_slot_reviews
    SET
      deleted_at          = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now
    WHERE qa_archive_batch_id = p_batch_id
      AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

    -- Restore workforce assignments (last, most granular)
    UPDATE public.workforce_assignments
    SET
      deleted_at          = NULL,
      qa_archive_batch_id = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id
      AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  END IF;

  -- Mark batch as ROLLED_BACK
  UPDATE public.system_archive_batches
  SET
    status         = 'ROLLED_BACK',
    rolled_back_by = v_caller_id,
    rolled_back_at = v_now
  WHERE id = v_batch.id;

  -- Audit
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, restored_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('enterprise_archive_rollback', p_batch_id, 'qa_rollback', v_caller_id, p_reason, p_batch_id,
     jsonb_build_object(
       'archive_batch_id',              p_batch_id,
       'action_type',                   v_batch.action_type,
       'rolled_back_by',                v_caller_id,
       'rolled_back_at',                v_now,
       'reason',                        p_reason,
       'plantilla_restored_count',      v_plantilla_count,
       'slots_restored_count',          v_slots_count,
       'vacancy_restored_count',        v_vacancy_count,
       'hc_requests_count',             v_hc_count,
       'hr_emploc_restored_count',      v_hr_emploc_count,
       'moses_hq_assign_restored',      v_assign_count,
       'moses_hq_slot_review_restored', v_slot_review_count,
       'moses_hq_req_item_restored',    v_req_item_count,
       'moses_hq_request_restored',     v_request_count,
       'moses_hq_coverage_restored',    v_coverage_count,
       'moses_hq_pool_slot_restored',   v_pool_slot_count,
       'moses_hq_pool_vacancy_restored',v_pool_vacancy_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',                p_batch_id,
    'plantilla_restored_count',        v_plantilla_count,
    'slots_restored_count',            v_slots_count,
    'vacancy_restored_count',          v_vacancy_count,
    'hc_requests_restored_count',      v_hc_count,
    'hr_emploc_restored_count',        v_hr_emploc_count,
    'moses_hq_assign_restored',        v_assign_count,
    'moses_hq_request_restored',       v_request_count,
    'moses_hq_pool_slot_restored',     v_pool_slot_count,
    'moses_hq_pool_vacancy_restored',  v_pool_vacancy_count,
    'rolled_back_by',                  v_caller_id,
    'rolled_back_at',                  v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_rollback_archive_batch(uuid, text) IS
  'Reverses an archive batch within the 72-active-hour rollback window (Sunday excluded). '
  'Restores full Moses HQ hierarchy (pool slots, vacancy coverage, requests, '
  'request items, slot reviews, assignments) for action_type IN '
  '(''moses_hq'', ''plantilla'', ''qa_reset''). '
  'Raises ERRCODE 55000 if window expired or batch already rolled back. '
  'Only restores records carrying the specific qa_archive_batch_id. '
  'Super Admin only. Reason required.';

REVOKE ALL ON FUNCTION public.fn_rollback_archive_batch(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_rollback_archive_batch(uuid, text) TO authenticated;


-- ── §8. fn_get_archive_batch_history ──────────────────────────────────────
-- DROP required because we are adding moses_hq_count to the RETURNS TABLE.
-- Adding a column to a RETURNS TABLE signature requires DROP + CREATE.

DROP FUNCTION IF EXISTS public.fn_get_archive_batch_history();

CREATE FUNCTION public.fn_get_archive_batch_history()
RETURNS TABLE(
  id                  uuid,
  archive_batch_id    uuid,
  action_type         text,
  reason              text,
  executed_by_name    text,
  executed_at         timestamptz,
  rollback_deadline   timestamptz,
  plantilla_count     integer,
  vacancy_count       integer,
  hr_emploc_count     integer,
  moses_hq_count      integer,
  total_count         integer,
  status              text,
  rolled_back_by_name text,
  rolled_back_at      timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    b.id,
    b.archive_batch_id,
    b.action_type,
    b.reason,
    COALESCE(up.full_name, 'Unknown') AS executed_by_name,
    b.executed_at,
    b.rollback_deadline,
    b.plantilla_count,
    b.vacancy_count,
    b.hr_emploc_count,
    b.moses_hq_count,
    b.plantilla_count + b.vacancy_count + b.hr_emploc_count + b.moses_hq_count AS total_count,
    CASE
      WHEN b.status = 'ACTIVE' AND now() > b.rollback_deadline THEN 'EXPIRED'
      ELSE b.status
    END AS status,
    rb.full_name AS rolled_back_by_name,
    b.rolled_back_at
  FROM public.system_archive_batches b
  LEFT JOIN public.users_profile up ON up.id = b.executed_by
  LEFT JOIN public.users_profile rb ON rb.id = b.rolled_back_by
  ORDER BY b.executed_at DESC;
$$;

COMMENT ON FUNCTION public.fn_get_archive_batch_history() IS
  'Returns all system_archive_batches rows with resolved actor display names, '
  'EXPIRED status computed lazily, and moses_hq_count for Moses HQ batches. '
  'total_count now includes moses_hq_count. Super Admin only via RLS.';

REVOKE ALL ON FUNCTION public.fn_get_archive_batch_history() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_batch_history() TO authenticated;
