-- ============================================================
-- OHM2026_0094 - Fix Archive All ESA Leak Using Real Schema
-- Migration:  20261029000000_fix_archive_all_esa_leak.sql
-- Depends on: 20261028000000_fix_archive_all_data_leakage.sql
-- ============================================================

BEGIN;

-- ── §1. fn_archive_all_operational_data ───────────────────────────────────
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
  v_esa_count          integer := 0;
  v_coverage_group_count      integer := 0;
  v_coverage_store_count      integer := 0;
  v_coverage_slot_count       integer := 0;
  v_coverage_applicant_count  integer := 0;
  v_hr_coverage_link_count    integer := 0;
  v_plantilla_coverage_link_count integer := 0;
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

  -- MODULE 2: VACANCIES
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

  -- MODULE 6: EMPLOYEE STORE ALLOCATIONS (ESA)
  UPDATE public.employee_store_allocations
  SET
    is_active            = false,
    effective_end        = current_date,
    qa_archive_batch_id  = v_batch_id
  WHERE is_active = true;
  GET DIAGNOSTICS v_esa_count = ROW_COUNT;

  -- MODULE 7: COVERAGE GROUPS
  UPDATE public.coverage_groups
  SET
    archived_at         = v_now,
    archived_by         = v_caller_id,
    archive_reason      = p_reason,
    qa_archive_batch_id = v_batch_id,
    status              = 'archived'
  WHERE archived_at IS NULL
    OR lower(COALESCE(status, '')) <> 'archived';
  GET DIAGNOSTICS v_coverage_group_count = ROW_COUNT;

  -- MODULE 8: COVERAGE GROUP STORES
  UPDATE public.coverage_group_stores
  SET
    archived_at         = v_now,
    archived_by         = v_caller_id,
    qa_archive_batch_id = v_batch_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_store_count = ROW_COUNT;

  -- MODULE 9: COVERAGE SLOTS
  UPDATE public.coverage_slots
  SET
    slot_status                               = 'closed',
    qa_archive_previous_status                = COALESCE(qa_archive_previous_status, slot_status),
    qa_archive_previous_occupant_plantilla_id = COALESCE(
                                                  qa_archive_previous_occupant_plantilla_id,
                                                  current_occupant_plantilla_id
                                                ),
    current_occupant_plantilla_id             = NULL,
    qa_archive_batch_id                       = v_batch_id,
    updated_at                                = v_now
  WHERE slot_status <> 'closed';
  GET DIAGNOSTICS v_coverage_slot_count = ROW_COUNT;

  -- MODULE 10: APPLICANTS (COVERAGE-BOUND)
  UPDATE public.applicants
  SET
    is_archived         = true,
    qa_archive_batch_id = COALESCE(qa_archive_batch_id, v_batch_id)
  WHERE COALESCE(is_archived, false) = false
    AND coverage_group_id IS NOT NULL;
  GET DIAGNOSTICS v_coverage_applicant_count = ROW_COUNT;

  -- MODULE 11: HR EMPLOC STORE LINKS
  UPDATE public.hr_emploc_store_links
  SET
    deleted_at          = v_now,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL
    AND coverage_group_id IS NOT NULL;
  GET DIAGNOSTICS v_hr_coverage_link_count = ROW_COUNT;

  -- MODULE 12: PLANTILLA STORE LINKS
  UPDATE public.plantilla_store_links
  SET
    deleted_at          = v_now,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL
    AND coverage_group_id IS NOT NULL;
  GET DIAGNOSTICS v_plantilla_coverage_link_count = ROW_COUNT;

  -- Register batch in canonical registry
  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, status)
  VALUES
    (v_batch_id, 'qa_reset', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72),
     v_plantilla_count, v_vacancy_count, v_hr_emploc_count, 'ACTIVE');

  -- Audit summary row
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('qa_reset_enterprise', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id',           v_batch_id,
       'action_type',                'qa_reset',
       'executed_by',                v_caller_id,
       'executed_at',                v_now,
       'reason',                     p_reason,
       'plantilla_count',            v_plantilla_count,
       'vacancy_count',              v_vacancy_count,
       'hr_emploc_count',            v_hr_emploc_count,
       'slots_count',                v_slots_count,
       'headcount_request_count',    v_hc_count,
       'esa_count',                  v_esa_count,
       'coverage_group_count',       v_coverage_group_count,
       'coverage_group_store_count', v_coverage_store_count,
       'coverage_slot_count',        v_coverage_slot_count,
       'coverage_applicant_count',   v_coverage_applicant_count,
       'hr_coverage_link_count',     v_hr_coverage_link_count,
       'plantilla_coverage_link_count', v_plantilla_coverage_link_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',           v_batch_id,
    'plantilla_count',            v_plantilla_count,
    'vacancy_count',              v_vacancy_count,
    'hr_emploc_count',            v_hr_emploc_count,
    'slots_count',                v_slots_count,
    'headcount_request_count',    v_hc_count,
    'esa_deactivated_count',      v_esa_count,
    'coverage_groups_archived_count', v_coverage_group_count,
    'coverage_group_stores_archived_count', v_coverage_store_count,
    'coverage_slots_closed_count', v_coverage_slot_count,
    'coverage_applicants_archived_count', v_coverage_applicant_count,
    'hr_coverage_links_deactivated_count', v_hr_coverage_link_count,
    'plantilla_coverage_links_deactivated_count', v_plantilla_coverage_link_count,
    'executed_by',                v_caller_id,
    'executed_at',                v_now
  );
END;
$$;

-- ── §2. fn_rollback_archive_batch ─────────────────────────────────────────
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
  v_batch           record;
  v_caller_id       uuid;
  v_now             timestamptz;
  v_plantilla_count integer := 0;
  v_vacancy_count   integer := 0;
  v_hr_emploc_count integer := 0;
  v_slots_count     integer := 0;
  v_hc_count        integer := 0;
  
  -- Cascades
  v_esa_count        integer := 0;
  v_coverage_group_count      integer := 0;
  v_coverage_store_count      integer := 0;
  v_coverage_slot_count       integer := 0;
  v_coverage_applicant_count  integer := 0;
  v_hr_coverage_link_count    integer := 0;
  v_plantilla_coverage_link_count integer := 0;
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
    -- Mark as EXPIRED before raising
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

    -- Reopen slots closed by this batch
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

  -- ── RESTORE CASCADES (QA_RESET ONLY) ────────────────────────────────────
  IF v_batch.action_type = 'qa_reset' THEN
    -- MODULE 6: EMPLOYEE STORE ALLOCATIONS (ESA)
    UPDATE public.employee_store_allocations
    SET
      is_active            = true,
      effective_end        = NULL,
      qa_archive_batch_id  = NULL
    WHERE qa_archive_batch_id = p_batch_id;
    GET DIAGNOSTICS v_esa_count = ROW_COUNT;

    -- MODULE 7: COVERAGE GROUPS
    UPDATE public.coverage_groups
    SET
      archived_at         = NULL,
      archived_by         = NULL,
      archive_reason      = NULL,
      qa_archive_batch_id = NULL,
      status              = 'active'
    WHERE qa_archive_batch_id = p_batch_id;
    GET DIAGNOSTICS v_coverage_group_count = ROW_COUNT;

    -- MODULE 8: COVERAGE GROUP STORES
    UPDATE public.coverage_group_stores
    SET
      archived_at         = NULL,
      archived_by         = NULL,
      qa_archive_batch_id = NULL
    WHERE qa_archive_batch_id = p_batch_id;
    GET DIAGNOSTICS v_coverage_store_count = ROW_COUNT;

    -- MODULE 9: COVERAGE SLOTS
    UPDATE public.coverage_slots
    SET
      slot_status                               = qa_archive_previous_status,
      current_occupant_plantilla_id             = qa_archive_previous_occupant_plantilla_id,
      qa_archive_previous_status                = NULL,
      qa_archive_previous_occupant_plantilla_id = NULL,
      qa_archive_batch_id                       = NULL,
      updated_at                                = v_now
    WHERE qa_archive_batch_id = p_batch_id;
    GET DIAGNOSTICS v_coverage_slot_count = ROW_COUNT;

    -- MODULE 10: APPLICANTS
    UPDATE public.applicants
    SET
      is_archived         = false,
      qa_archive_batch_id = NULL
    WHERE qa_archive_batch_id = p_batch_id
      AND is_archived = true;
    GET DIAGNOSTICS v_coverage_applicant_count = ROW_COUNT;

    -- MODULE 11: HR EMPLOC STORE LINKS
    UPDATE public.hr_emploc_store_links
    SET
      deleted_at          = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE deleted_at = v_batch.executed_at
      AND coverage_group_id IN (
        SELECT id FROM public.coverage_groups WHERE qa_archive_batch_id = p_batch_id OR (archived_at IS NULL AND status = 'active')
      );
    GET DIAGNOSTICS v_hr_coverage_link_count = ROW_COUNT;

    -- MODULE 12: PLANTILLA STORE LINKS
    UPDATE public.plantilla_store_links
    SET
      deleted_at          = NULL,
      updated_at          = v_now,
      updated_by          = v_caller_id
    WHERE deleted_at = v_batch.executed_at
      AND coverage_group_id IN (
        SELECT id FROM public.coverage_groups WHERE qa_archive_batch_id = p_batch_id OR (archived_at IS NULL AND status = 'active')
      );
    GET DIAGNOSTICS v_plantilla_coverage_link_count = ROW_COUNT;
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
       'archive_batch_id',            p_batch_id,
       'action_type',                 v_batch.action_type,
       'rolled_back_by',              v_caller_id,
       'rolled_back_at',              v_now,
       'reason',                      p_reason,
       'plantilla_restored_count',    v_plantilla_count,
       'slots_restored_count',        v_slots_count,
       'vacancy_restored_count',      v_vacancy_count,
       'hc_requests_count',           v_hc_count,
       'hr_emploc_restored_count',    v_hr_emploc_count,
       'esa_restored_count',          v_esa_count,
       'coverage_groups_restored_count', v_coverage_group_count,
       'coverage_group_stores_restored_count', v_coverage_store_count,
       'coverage_slots_reopened_count', v_coverage_slot_count,
       'coverage_applicants_restored_count', v_coverage_applicant_count,
       'hr_coverage_links_reactivated_count', v_hr_coverage_link_count,
       'plantilla_coverage_links_reactivated_count', v_plantilla_coverage_link_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',            p_batch_id,
    'plantilla_restored_count',    v_plantilla_count,
    'slots_restored_count',        v_slots_count,
    'vacancy_restored_count',      v_vacancy_count,
    'hc_requests_restored_count',  v_hc_count,
    'hr_emploc_restored_count',    v_hr_emploc_count,
    'esa_restored_count',          v_esa_count,
    'coverage_groups_restored_count', v_coverage_group_count,
    'coverage_group_stores_restored_count', v_coverage_store_count,
    'coverage_slots_reopened_count', v_coverage_slot_count,
    'coverage_applicants_restored_count', v_coverage_applicant_count,
    'hr_coverage_links_reactivated_count', v_hr_coverage_link_count,
    'plantilla_coverage_links_reactivated_count', v_plantilla_coverage_link_count,
    'rolled_back_by',              v_caller_id,
    'rolled_back_at',              v_now
  );
END;
$$;

-- ── §3. fn_qa_rollback_operational_data_reset ─────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_qa_rollback_operational_data_reset(
  p_batch_id uuid,
  p_reason   text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id        uuid;
  v_now              timestamptz;
  v_batch_exists     boolean;

  v_plantilla_count  integer := 0;
  v_vacancy_count    integer := 0;
  v_hr_emploc_count  integer := 0;
  v_slots_count      integer := 0;
  v_hc_request_count integer := 0;
  
  -- Cascades
  v_esa_count        integer := 0;
  v_coverage_group_count      integer := 0;
  v_coverage_store_count      integer := 0;
  v_coverage_slot_count       integer := 0;
  v_coverage_applicant_count  integer := 0;
  v_hr_coverage_link_count    integer := 0;
  v_plantilla_coverage_link_count integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'rollback_reason is required and must not be empty'
      USING ERRCODE = '22000';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.archival_audit_logs
    WHERE archive_batch_id = p_batch_id
      AND action_type = 'qa_archive'
  ) INTO v_batch_exists;

  IF NOT v_batch_exists THEN
    RAISE EXCEPTION 'QA archive batch % not found', p_batch_id
      USING ERRCODE = 'P0002';
  END IF;

  v_caller_id := public.get_current_profile_id();
  v_now       := now();

  -- ROLLBACK: PLANTILLA
  UPDATE public.plantilla
  SET
    is_archived         = false,
    restored_at         = v_now,
    restored_by         = v_caller_id,
    archived_at         = NULL,
    archived_by         = NULL,
    archive_reason      = NULL,
    qa_archive_batch_id = NULL,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE qa_archive_batch_id = p_batch_id
    AND is_archived     = true;
  GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

  -- ROLLBACK: VACANCIES
  UPDATE public.vacancies
  SET
    is_archived         = false,
    restored_at         = v_now,
    restored_by         = v_caller_id,
    archived_at         = NULL,
    archived_by_id      = NULL,
    archived_by         = NULL,
    archive_reason      = NULL,
    status              = 'Open',
    qa_archive_batch_id = NULL,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE qa_archive_batch_id = p_batch_id
    AND is_archived     = true;
  GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

  -- ROLLBACK: HR EMPLOC
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

  -- ROLLBACK: PLANTILLA SLOTS
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
    AND slot_status     = 'closed'
    AND closure_reason_code = 'QA_RESET';
  GET DIAGNOSTICS v_slots_count = ROW_COUNT;

  -- ROLLBACK: HEADCOUNT REQUESTS
  UPDATE public.headcount_requests
  SET
    is_archived         = false,
    archived_at         = NULL,
    qa_archive_batch_id = NULL,
    updated_at          = v_now
  WHERE qa_archive_batch_id = p_batch_id
    AND is_archived     = true;
  GET DIAGNOSTICS v_hc_request_count = ROW_COUNT;

  -- ROLLBACK: EMPLOYEE STORE ALLOCATIONS (ESA)
  UPDATE public.employee_store_allocations
  SET
    is_active            = true,
    effective_end        = NULL,
    qa_archive_batch_id  = NULL
  WHERE qa_archive_batch_id = p_batch_id;
  GET DIAGNOSTICS v_esa_count = ROW_COUNT;

  -- ROLLBACK: COVERAGE GROUPS
  UPDATE public.coverage_groups
  SET
    archived_at         = NULL,
    archived_by         = NULL,
    archive_reason      = NULL,
    qa_archive_batch_id = NULL,
    status              = 'active'
  WHERE qa_archive_batch_id = p_batch_id;
  GET DIAGNOSTICS v_coverage_group_count = ROW_COUNT;

  -- ROLLBACK: COVERAGE GROUP STORES
  UPDATE public.coverage_group_stores
  SET
    archived_at         = NULL,
    archived_by         = NULL,
    qa_archive_batch_id = NULL
  WHERE qa_archive_batch_id = p_batch_id;
  GET DIAGNOSTICS v_coverage_store_count = ROW_COUNT;

  -- ROLLBACK: COVERAGE SLOTS
  UPDATE public.coverage_slots
  SET
    slot_status                               = qa_archive_previous_status,
    current_occupant_plantilla_id             = qa_archive_previous_occupant_plantilla_id,
    qa_archive_previous_status                = NULL,
    qa_archive_previous_occupant_plantilla_id = NULL,
    qa_archive_batch_id                       = NULL,
    updated_at                                = v_now
  WHERE qa_archive_batch_id = p_batch_id;
  GET DIAGNOSTICS v_coverage_slot_count = ROW_COUNT;

  -- ROLLBACK: APPLICANTS
  UPDATE public.applicants
  SET
    is_archived         = false,
    qa_archive_batch_id = NULL
  WHERE qa_archive_batch_id = p_batch_id
    AND is_archived = true;
  GET DIAGNOSTICS v_coverage_applicant_count = ROW_COUNT;

  -- ROLLBACK: HR EMPLOC STORE LINKS
  UPDATE public.hr_emploc_store_links
  SET
    deleted_at          = NULL,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NOT NULL
    AND coverage_group_id IN (
      SELECT id FROM public.coverage_groups WHERE qa_archive_batch_id = p_batch_id OR (archived_at IS NULL AND status = 'active')
    );
  GET DIAGNOSTICS v_hr_coverage_link_count = ROW_COUNT;

  -- ROLLBACK: PLANTILLA STORE LINKS
  UPDATE public.plantilla_store_links
  SET
    deleted_at          = NULL,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NOT NULL
    AND coverage_group_id IN (
      SELECT id FROM public.coverage_groups WHERE qa_archive_batch_id = p_batch_id OR (archived_at IS NULL AND status = 'active')
    );
  GET DIAGNOSTICS v_plantilla_coverage_link_count = ROW_COUNT;

  -- AUDIT
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, restored_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    (
      'qa_reset_summary',
      p_batch_id,
      'qa_rollback',
      v_caller_id,
      p_reason,
      p_batch_id,
      jsonb_build_object(
        'archive_batch_id',              p_batch_id,
        'rolled_back_by',                v_caller_id,
        'rolled_back_at',                v_now,
        'reason',                        p_reason,
        'plantilla_restored_count',      v_plantilla_count,
        'vacancy_restored_count',        v_vacancy_count,
        'hr_emploc_restored_count',      v_hr_emploc_count,
        'slots_restored_count',          v_slots_count,
        'hc_requests_restored_count',    v_hc_request_count,
        'esa_restored_count',            v_esa_count,
        'coverage_groups_restored_count', v_coverage_group_count,
        'coverage_group_stores_restored_count', v_coverage_store_count,
        'coverage_slots_reopened_count', v_coverage_slot_count,
        'coverage_applicants_restored_count', v_coverage_applicant_count,
        'hr_coverage_links_reactivated_count', v_hr_coverage_link_count,
        'plantilla_coverage_links_reactivated_count', v_plantilla_coverage_link_count
      )
    );

  RETURN jsonb_build_object(
    'archive_batch_id',              p_batch_id,
    'plantilla_restored_count',      v_plantilla_count,
    'vacancy_restored_count',        v_vacancy_count,
    'slots_restored_count',          v_slots_count,
    'hr_emploc_restored_count',      v_hr_emploc_count,
    'hc_requests_restored_count',    v_hc_request_count,
    'esa_restored_count',            v_esa_count,
    'coverage_groups_restored_count', v_coverage_group_count,
    'coverage_group_stores_restored_count', v_coverage_store_count,
    'coverage_slots_reopened_count', v_coverage_slot_count,
    'coverage_applicants_restored_count', v_coverage_applicant_count,
    'hr_coverage_links_reactivated_count', v_hr_coverage_link_count,
    'plantilla_coverage_links_reactivated_count', v_plantilla_coverage_link_count,
    'rolled_back_by',                v_caller_id,
    'rolled_back_at',                v_now
  );
END;
$$;

COMMIT;
