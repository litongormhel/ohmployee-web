-- =============================================================================
-- Migration: 20262606000011_fix_moses_hq_archival_cascade.sql
-- Prompt: ohm#c91k2mxa4
--
-- Enforces full cascade soft delete across Moses HQ module tables on archive.
-- Fixes Actual HC, Deployed, and Available metrics queries/views to respect
-- deleted_at IS NULL on workforce assignments, slot reviews, pool requests,
-- request items, and pool slots.
-- =============================================================================

BEGIN;

-- ── §1. fn_archive_moses_hq_data ──────────────────────────────────────────
-- Standalone Moses HQ archive function.
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

  -- 2. POOL REQUEST ITEMS
  UPDATE public.workforce_pool_request_items
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  -- 3. SLOT REVIEWS
  UPDATE public.workforce_slot_reviews
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  -- 4. POOL SLOTS
  UPDATE public.workforce_pool_slots
  SET
    is_active           = false,
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_count = ROW_COUNT;

  -- 5. POOL REQUESTS
  UPDATE public.workforce_pool_requests
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  -- 6. VACANCY COVERAGE
  UPDATE public.vacancy_coverage
  SET
    archived_at         = v_now,
    archived_by         = v_caller_id,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  -- 7. POOL VACANCIES
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


-- ── §2. fn_archive_plantilla_data ─────────────────────────────────────────
-- Plantilla archive function cascading to Moses HQ operational child data.
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
  
  -- Moses HQ cascades
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

  -- CASCADE: MOSES HQ
  -- 1. WORKFORCE ASSIGNMENTS
  UPDATE public.workforce_assignments
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  -- 2. POOL REQUEST ITEMS
  UPDATE public.workforce_pool_request_items
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  -- 3. SLOT REVIEWS
  UPDATE public.workforce_slot_reviews
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  -- 4. POOL SLOTS
  UPDATE public.workforce_pool_slots
  SET
    is_active           = false,
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

  -- 5. POOL REQUESTS
  UPDATE public.workforce_pool_requests
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  -- 6. VACANCY COVERAGE
  UPDATE public.vacancy_coverage
  SET
    archived_at         = v_now,
    archived_by         = v_caller_id,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  -- 7. POOL VACANCIES
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


-- ── §3. fn_archive_all_operational_data ───────────────────────────────────
-- QA Reset: archives ALL operational tables, including ESA, Coverage Groups, and Moses HQ.
CREATE OR REPLACE FUNCTION public.fn_archive_all_operational_data(
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id                     uuid;
  v_caller_name                   text;
  v_batch_id                      uuid := gen_random_uuid();
  v_now                           timestamptz := now();
  v_plantilla_count               integer := 0;
  v_vacancy_count                 integer := 0;
  v_hr_emploc_count               integer := 0;
  v_slots_count                   integer := 0;
  v_hc_count                      integer := 0;
  
  -- Cascades
  v_esa_count                     integer := 0;
  v_coverage_group_count          integer := 0;
  v_coverage_store_count          integer := 0;
  v_coverage_slot_count           integer := 0;
  v_coverage_applicant_count      integer := 0;
  v_hr_coverage_link_count        integer := 0;
  v_plantilla_coverage_link_count integer := 0;

  -- Moses HQ cascades
  v_assign_count                  integer := 0;
  v_slot_review_count             integer := 0;
  v_req_item_count                integer := 0;
  v_request_count                 integer := 0;
  v_coverage_count                integer := 0;
  v_pool_slot_count               integer := 0;
  v_moses_hq_count                integer := 0;
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

  -- MODULE 2: VACANCIES (regular + pool vacancies)
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
    effective_end        = v_now::date,
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

  -- MODULE 13: MOSES HQ (pool vacancies already archived in MODULE 2)
  -- 1. WORKFORCE ASSIGNMENTS
  UPDATE public.workforce_assignments
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_assign_count = ROW_COUNT;

  -- 2. POOL REQUEST ITEMS
  UPDATE public.workforce_pool_request_items
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

  -- 3. SLOT REVIEWS
  UPDATE public.workforce_slot_reviews
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

  -- 4. POOL SLOTS
  UPDATE public.workforce_pool_slots
  SET
    is_active           = false,
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

  -- 5. POOL REQUESTS
  UPDATE public.workforce_pool_requests
  SET
    deleted_at          = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_request_count = ROW_COUNT;

  -- 6. VACANCY COVERAGE
  UPDATE public.vacancy_coverage
  SET
    archived_at         = v_now,
    archived_by         = v_caller_id,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

  v_moses_hq_count := v_assign_count + v_slot_review_count + v_req_item_count
                    + v_request_count + v_coverage_count + v_pool_slot_count;

  -- Register batch in canonical registry
  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, moses_hq_count, status)
  VALUES
    (v_batch_id, 'qa_reset', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72),
     v_plantilla_count, v_vacancy_count, v_hr_emploc_count, v_moses_hq_count, 'ACTIVE');

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
       'plantilla_coverage_link_count', v_plantilla_coverage_link_count,
       'moses_hq_assignment_count', v_assign_count,
       'moses_hq_slot_review_count', v_slot_review_count,
       'moses_hq_req_item_count',    v_req_item_count,
       'moses_hq_request_count',     v_request_count,
       'moses_hq_coverage_count',    v_coverage_count,
       'moses_hq_pool_slot_count',   v_pool_slot_count,
       'moses_hq_count',             v_moses_hq_count
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
    'moses_hq_count',             v_moses_hq_count,
    'moses_hq_assignment_count',  v_assign_count,
    'moses_hq_request_count',     v_request_count,
    'moses_hq_pool_slot_count',   v_pool_slot_count,
    'executed_by',                v_caller_id,
    'executed_at',                v_now
  );
END;
$$;


-- ── §4. fn_rollback_archive_batch ─────────────────────────────────────────
-- Batch rollback function to safely restore ESA, Coverage Groups, and Moses HQ.
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
  v_batch                         record;
  v_caller_id                     uuid;
  v_now                           timestamptz;
  v_plantilla_count               integer := 0;
  v_slots_count                   integer := 0;
  v_vacancy_count                 integer := 0;
  v_hc_count                      integer := 0;
  v_hr_emploc_count               integer := 0;
  
  -- Cascades
  v_esa_count                     integer := 0;
  v_coverage_group_count          integer := 0;
  v_coverage_store_count          integer := 0;
  v_coverage_slot_count           integer := 0;
  v_coverage_applicant_count      integer := 0;
  v_hr_coverage_link_count        integer := 0;
  v_plantilla_coverage_link_count integer := 0;

  -- Moses HQ
  v_assign_count                  integer := 0;
  v_slot_review_count             integer := 0;
  v_req_item_count                integer := 0;
  v_request_count                 integer := 0;
  v_coverage_count                integer := 0;
  v_pool_slot_count               integer := 0;
  v_pool_vacancy_count            integer := 0;
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

  -- ── RESTORE MOSES HQ (MOSES_HQ, PLANTILLA, or QA_RESET) ──────────────────
  IF v_batch.action_type IN ('moses_hq', 'plantilla', 'qa_reset') THEN
    IF v_batch.action_type = 'moses_hq' THEN
      UPDATE public.vacancies
      SET is_archived = false, archived_at = NULL, archived_by_id = NULL, archived_by = NULL,
          archive_reason = NULL, status = 'Open', restored_at = v_now, restored_by = v_caller_id,
          qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
      WHERE qa_archive_batch_id = p_batch_id AND is_pool_vacancy = true AND is_archived = true;
      GET DIAGNOSTICS v_pool_vacancy_count = ROW_COUNT;
    END IF;

    UPDATE public.workforce_pool_slots
    SET is_active = true, deleted_at = NULL, qa_archive_batch_id = NULL,
        updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id;
    GET DIAGNOSTICS v_pool_slot_count = ROW_COUNT;

    UPDATE public.vacancy_coverage
    SET archived_at = NULL, archived_by = NULL, qa_archive_batch_id = NULL,
        updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND archived_at IS NOT NULL;
    GET DIAGNOSTICS v_coverage_count = ROW_COUNT;

    UPDATE public.workforce_pool_requests
    SET deleted_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_request_count = ROW_COUNT;

    UPDATE public.workforce_pool_request_items
    SET deleted_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now
    WHERE qa_archive_batch_id = p_batch_id AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_req_item_count = ROW_COUNT;

    UPDATE public.workforce_slot_reviews
    SET deleted_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now
    WHERE qa_archive_batch_id = p_batch_id AND deleted_at IS NOT NULL;
    GET DIAGNOSTICS v_slot_review_count = ROW_COUNT;

    UPDATE public.workforce_assignments
    SET deleted_at = NULL, qa_archive_batch_id = NULL, updated_at = v_now, updated_by = v_caller_id
    WHERE qa_archive_batch_id = p_batch_id AND deleted_at IS NOT NULL;
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
       'plantilla_coverage_links_reactivated_count', v_plantilla_coverage_link_count,
       'moses_hq_assign_restored',    v_assign_count,
       'moses_hq_slot_review_restored', v_slot_review_count,
       'moses_hq_req_item_restored',  v_req_item_count,
       'moses_hq_request_restored',   v_request_count,
       'moses_hq_coverage_restored',  v_coverage_count,
       'moses_hq_pool_slot_restored', v_pool_slot_count,
       'moses_hq_pool_vacancy_restored', v_pool_vacancy_count
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
    'moses_hq_assign_restored',    v_assign_count,
    'moses_hq_request_restored',   v_request_count,
    'moses_hq_pool_slot_restored', v_pool_slot_count,
    'moses_hq_pool_vacancy_restored', v_pool_vacancy_count,
    'rolled_back_by',              v_caller_id,
    'rolled_back_at',              v_now
  );
END;
$$;


-- ── §5. Redefining Views ───────────────────────────────────────────────────

DROP VIEW IF EXISTS public.v_workforce_pool_employees CASCADE;
CREATE VIEW public.v_workforce_pool_employees
WITH (security_invoker = true)
AS
SELECT
  p.id                                              AS employee_id,
  p.employee_no                                     AS employee_number,
  p.employee_name                                   AS full_name,
  p.last_name,
  p.first_name,
  p.middle_name,
  p.account                                         AS home_account,
  p.account_id                                      AS home_account_id,
  p.store_id                                        AS home_store_id,
  wps.id                                            AS pool_slot_id,
  COALESCE(wps.pool_type_id, p.pool_type_id)        AS pool_type_id,
  wpt.code                                          AS pool_type_code,
  wpt.name                                          AS pool_type_name,
  wps.group_id                                      AS tagged_group_id,
  g.group_name                                      AS tagged_group_name,
  COALESCE(agg.active_deployment_count, 0)          AS active_deployment_count,
  COALESCE(agg.active_store_count, 0)               AS active_store_count,
  CASE
    WHEN COALESCE(agg.active_deployment_count, 0) = 0             THEN 'None'
    WHEN agg.active_deployment_count BETWEEN 1  AND 5             THEN 'Low'
    WHEN agg.active_deployment_count BETWEEN 6  AND 10            THEN 'Medium'
    WHEN agg.active_deployment_count BETWEEN 11 AND 20            THEN 'High'
    ELSE 'Critical'
  END                                               AS deployment_load_indicator,
  CASE
    WHEN p.is_deleted = true
      OR p.deactivated_at IS NOT NULL
      OR p.status <> 'Active'                       THEN 'Inactive'
    WHEN pend.pending_request_id IS NOT NULL         THEN 'Reserved'
    WHEN COALESCE(agg.active_deployment_count, 0) > 0 THEN 'Deployed'
    ELSE 'Available'
  END                                               AS availability_status,
  (wps.group_id IS NULL)                            AS is_global_visible,
  (pend.pending_request_id IS NOT NULL)             AS has_pending_request,
  pend.pending_request_id,
  pend.pending_requested_account,
  pend.pending_requested_store,
  p.status                                          AS employee_status,
  p.date_hired,
  p."position",
  p.deployment_type                                 AS home_deployment_type,
  COALESCE(lt.has_longterm, false)                  AS needs_review
FROM public.plantilla p
JOIN public.workforce_pool_slots wps
  ON wps.vcode = p.vcode
 AND wps.deleted_at IS NULL
JOIN public.workforce_pool_types wpt
  ON wpt.id = COALESCE(wps.pool_type_id, p.pool_type_id)
 AND wpt.is_active = true
LEFT JOIN public.groups g ON g.id = wps.group_id
LEFT JOIN (
  SELECT
    employee_id,
    COUNT(*)                  FILTER (WHERE status IN ('Active','Approved') AND deleted_at IS NULL) AS active_deployment_count,
    COUNT(DISTINCT assigned_store_id)
                              FILTER (WHERE status IN ('Active','Approved') AND deleted_at IS NULL) AS active_store_count
  FROM public.workforce_assignments
  GROUP BY employee_id
) agg ON agg.employee_id = p.id
LEFT JOIN (
  SELECT DISTINCT employee_id, true AS has_longterm
  FROM public.workforce_assignments
  WHERE status IN ('Active','Approved')
    AND start_date <= CURRENT_DATE - INTERVAL '30 days'
    AND deleted_at IS NULL
) lt ON lt.employee_id = p.id
LEFT JOIN (
  SELECT
    war.employee_id,
    war.id              AS pending_request_id,
    a.account_name      AS pending_requested_account,
    s.store_name        AS pending_requested_store
  FROM public.workforce_assignment_requests war
  LEFT JOIN public.accounts a ON a.id = war.requested_account_id
  LEFT JOIN public.stores   s ON s.id = war.requested_store_id
  WHERE war.status = 'Pending'
) pend ON pend.employee_id = p.id
WHERE p.is_deleted        = false
  AND p.is_pool_employee  = true
  AND p.deactivated_at   IS NULL
  AND (
    public.get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR public.i_have_full_access()
    OR wps.group_id IS NULL
    OR EXISTS (
      SELECT 1
      FROM public.accounts a
      WHERE a.group_id = wps.group_id
        AND a.id::text = ANY (public.get_my_allowed_accounts())
    )
  );


DROP VIEW IF EXISTS public.v_workforce_store_temporary_coverage CASCADE;
CREATE VIEW public.v_workforce_store_temporary_coverage
WITH (security_invoker = true)
AS
SELECT
  wa.id                  AS assignment_id,
  wa.assigned_store_id   AS store_id,
  wa.assigned_account_id AS account_id,
  wa.assigned_group_id   AS group_id,
  wa.employee_id,
  p.employee_no          AS employee_number,
  p.employee_name,
  wpt.code               AS pool_type_code,
  wpt.name               AS pool_type_name,
  wa.deployment_type,
  wa.priority,
  wa.is_primary,
  wa.start_date,
  wa.end_date,
  wa.status,
  wa.approved_by,
  wa.approved_at,
  a.account_name,
  s.store_name,
  s.store_branch,
  g.group_name,
  wa.covered_plantilla_id
FROM public.workforce_assignments wa
JOIN  public.plantilla           p   ON (p.id = wa.employee_id AND p.is_deleted = false)
JOIN  public.workforce_pool_types wpt ON wpt.id = wa.pool_type_id
LEFT JOIN public.accounts          a   ON a.id = wa.assigned_account_id
LEFT JOIN public.stores             s   ON s.id = wa.assigned_store_id
LEFT JOIN public.groups             g   ON g.id = wa.assigned_group_id
WHERE wa.status = ANY (ARRAY['Active'::text, 'Approved'::text])
  AND wa.deleted_at IS NULL
  AND (
    public.get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR public.i_have_full_access()
    OR (
      (wa.assigned_account_id = ANY (public.get_my_allowed_account_ids()))
      AND public.can_view_pool_employee(wa.employee_id)
    )
  );

COMMENT ON VIEW public.v_workforce_store_temporary_coverage IS
  'Active/Approved workforce assignments with covered_plantilla_id column added. Respects soft delete deleted_at IS NULL.';

GRANT SELECT ON public.v_workforce_store_temporary_coverage TO authenticated;


DROP VIEW IF EXISTS public.v_workforce_assignment_review_queue CASCADE;
CREATE VIEW public.v_workforce_assignment_review_queue
WITH (security_invoker = true)
AS
SELECT wa.id AS assignment_id,
    wa.employee_id,
    p.employee_no AS employee_number,
    p.employee_name,
    wa.assigned_account_id,
    a.account_name,
    wa.assigned_store_id,
    s.store_name,
    wa.pool_type_id,
    wpt.code AS pool_type_code,
    wpt.name AS pool_type_name,
    wa.start_date,
    wa.end_date,
    wa.status,
    wa.priority,
    (wa.end_date - CURRENT_DATE) AS days_remaining,
        CASE
            WHEN ((p.is_deleted = true) OR (p.deactivated_at IS NOT NULL) OR (p.status <> 'Active'::text)) THEN 'Employee Inactive'::text
            WHEN (CURRENT_DATE > wa.end_date) THEN 'Overdue'::text
            WHEN (CURRENT_DATE = wa.end_date) THEN 'Due Today'::text
            WHEN ((wa.end_date - CURRENT_DATE) <= 3) THEN 'Nearing End Date'::text
            WHEN ((wa.end_date - wa.start_date) >= 180) THEN 'Long-Term Coverage'::text
            ELSE 'Pending Review'::text
        END AS review_label,
    wa.notes,
    wa.created_at
   FROM ((((public.workforce_assignments wa
     JOIN public.plantilla p ON ((p.id = wa.employee_id)))
     JOIN public.workforce_pool_types wpt ON ((wpt.id = wa.pool_type_id)))
     LEFT JOIN public.accounts a ON ((a.id = wa.assigned_account_id)))
     LEFT JOIN public.stores s ON ((s.id = wa.assigned_store_id)))
  WHERE ((wa.status = ANY (ARRAY['Pending'::text, 'Active'::text, 'Approved'::text]))
    AND wa.deleted_at IS NULL
    AND ((p.is_deleted = true) OR (p.deactivated_at IS NOT NULL) OR (p.status <> 'Active'::text) OR (CURRENT_DATE > wa.end_date) OR (CURRENT_DATE = wa.end_date) OR ((wa.end_date - CURRENT_DATE) <= 3) OR ((wa.end_date - wa.start_date) >= 180) OR (wa.status = 'Pending'::text))
    AND ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()));

GRANT SELECT ON public.v_workforce_assignment_review_queue TO authenticated;


DROP VIEW IF EXISTS public.v_workforce_slot_reviews CASCADE;
CREATE VIEW public.v_workforce_slot_reviews
WITH (security_invoker = true)
AS
SELECT sr.id AS review_id,
    sr.vcode,
    sr.pool_type_id,
    wpt.name AS pool_type_name,
    wpt.code AS pool_type_code,
    sr.trigger_event,
    sr.status,
    sr.action,
    sr.review_notes,
    sr.previous_employee_id,
    p.employee_name AS previous_employee_name,
    p.employee_no AS previous_employee_number,
    sr.decided_at,
    sr.decided_by,
    sr.created_by,
    sr.created_at,
    sr.updated_at,
    wps.id AS slot_id,
    wps.status AS slot_status,
    wps.is_active AS slot_is_active,
    GREATEST(CURRENT_DATE - sr.created_at::date, 0) AS review_age_days
   FROM workforce_slot_reviews sr
     LEFT JOIN workforce_pool_types wpt ON wpt.id = sr.pool_type_id
     LEFT JOIN plantilla p ON p.id = sr.previous_employee_id
     LEFT JOIN workforce_pool_slots wps ON wps.vcode = sr.vcode AND wps.deleted_at IS NULL
  WHERE sr.deleted_at IS NULL
  ORDER BY sr.created_at DESC;

GRANT SELECT ON public.v_workforce_slot_reviews TO authenticated;


DROP VIEW IF EXISTS public.v_vacancy_deployment_indicators CASCADE;
CREATE VIEW public.v_vacancy_deployment_indicators
WITH (security_invoker = true)
AS
SELECT v.id AS vacancy_id,
    COALESCE(bool_or(vc.id IS NOT NULL AND lower(vc.coverage_type::text) !~~ '%commando%'::text OR wa.id IS NOT NULL AND NOT (lower(COALESCE(wa.deployment_type, ''::text)) ~~ '%commando%'::text OR lower(COALESCE(wpt.name, ''::text)) ~~ '%commando%'::text OR lower(COALESCE(wpt.code, ''::text)) ~~ '%commando%'::text)), false) AS has_reliever,
    COALESCE(bool_or(vc.id IS NOT NULL AND lower(vc.coverage_type::text) ~~ '%commando%'::text OR wa.id IS NOT NULL AND (lower(COALESCE(wa.deployment_type, ''::text)) ~~ '%commando%'::text OR lower(COALESCE(wpt.name, ''::text)) ~~ '%commando%'::text OR lower(COALESCE(wpt.code, ''::text)) ~~ '%commando%'::text)), false) AS has_commando
   FROM vacancies v
     LEFT JOIN vacancy_coverage vc ON (vc.vacancy_id IS NOT NULL AND vc.vacancy_id = v.id OR vc.vacancy_id IS NULL AND vc.vcode = v.vcode) AND vc.archived_at IS NULL AND vc.status = 'Active'::vacancy_coverage_status
     LEFT JOIN workforce_assignments wa ON wa.assigned_store_id = v.store_id AND wa.deleted_at IS NULL AND (wa.status = ANY (ARRAY['Approved'::text, 'Deployed'::text, 'Active'::text, 'In Progress'::text]))
     LEFT JOIN workforce_pool_types wpt ON wpt.id = wa.pool_type_id
  WHERE i_have_full_access() OR (v.account = ANY (get_my_allowed_accounts())) AND (v.status <> ALL (ARRAY['Filled'::text, 'Closed'::text, 'Archived'::text])) AND COALESCE(v.is_archived, false) = false AND (NOT COALESCE(v.is_pool_vacancy, false) OR COALESCE(v.is_ops_request, false) = true) OR COALESCE(v.is_pool_vacancy, false) = true AND (get_my_role_level() = 20 OR get_my_role_level() = 30 OR get_my_role_level() >= 90)
  GROUP BY v.id;

GRANT SELECT ON public.v_vacancy_deployment_indicators TO authenticated;


-- ── §6. fn_workforce_pool_overview ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_workforce_pool_overview(p_account_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_totals jsonb;
  v_by_pool_type jsonb;
  v_long_term int;
  v_pending_req int;
BEGIN
  IF NOT public.fn_wf_account_in_scope(p_account_id) THEN
    RAISE EXCEPTION 'forbidden: analytics account outside user scope'
      USING ERRCODE = '42501';
  END IF;

  WITH visible_pool AS (
    SELECT pe.*
    FROM public.v_workforce_pool_employees pe
    WHERE public.i_have_full_access()
       OR pe.is_global_visible = true
       OR EXISTS (
         SELECT 1
         FROM public.accounts a
         WHERE a.group_id = pe.tagged_group_id
           AND a.id::text = ANY(public.get_my_allowed_accounts())
       )
  )
  SELECT jsonb_build_object(
    'total', COUNT(*),
    'available', COUNT(*) FILTER (WHERE lower(availability_status) = 'available'),
    'deployed', COUNT(*) FILTER (WHERE lower(availability_status) = 'deployed'),
    'reserved', COUNT(*) FILTER (WHERE has_pending_request = true),
    'in_review', COUNT(*) FILTER (WHERE needs_review = true OR lower(availability_status) = 'review'),
    'inactive', COUNT(*) FILTER (WHERE lower(availability_status) IN ('inactive','resigned','terminated','awol','suspended','on leave'))
  )
  INTO v_totals
  FROM visible_pool;

  SELECT COUNT(DISTINCT employee_id)
  INTO v_long_term
  FROM public.workforce_assignments
  WHERE status IN ('Active','Approved')
    AND deleted_at IS NULL
    AND start_date <= CURRENT_DATE - INTERVAL '30 days'
    AND (
      public.i_have_full_access()
      OR assigned_account_id::text = ANY(public.get_my_allowed_accounts())
    )
    AND (p_account_id IS NULL OR assigned_account_id = p_account_id);

  SELECT COUNT(*)
  INTO v_pending_req
  FROM public.workforce_assignment_requests
  WHERE lower(status) IN ('pending','for review')
    AND (
      public.i_have_full_access()
      OR requested_by_id = public.get_my_profile_id()
      OR requested_account_id::text = ANY(public.get_my_allowed_accounts())
    )
    AND (p_account_id IS NULL OR requested_account_id = p_account_id);

  WITH visible_pool AS (
    SELECT pe.*
    FROM public.v_workforce_pool_employees pe
    WHERE public.i_have_full_access()
       OR pe.is_global_visible = true
       OR EXISTS (
         SELECT 1
         FROM public.accounts a
         WHERE a.group_id = pe.tagged_group_id
           AND a.id::text = ANY(public.get_my_allowed_accounts())
       )
  ),
  grouped AS (
    SELECT
      pool_type_id,
      pool_type_name,
      pool_type_code,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE lower(availability_status) = 'available') AS available,
      COUNT(*) FILTER (WHERE lower(availability_status) = 'deployed') AS deployed,
      COUNT(*) FILTER (WHERE needs_review = true OR lower(availability_status) = 'review') AS in_review,
      COUNT(*) FILTER (WHERE lower(availability_status) IN ('inactive','resigned','terminated','awol','suspended','on leave')) AS inactive
    FROM visible_pool
    GROUP BY pool_type_id, pool_type_name, pool_type_code
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'pool_type_id', pool_type_id,
      'pool_type_name', pool_type_name,
      'pool_type_code', pool_type_code,
      'total', total,
      'available', available,
      'deployed', deployed,
      'in_review', in_review,
      'inactive', inactive
    )
    ORDER BY pool_type_name
  )
  INTO v_by_pool_type
  FROM grouped;

  RETURN jsonb_build_object(
    'totals', COALESCE(v_totals, '{}'::jsonb) || jsonb_build_object(
      'long_term_deployments', COALESCE(v_long_term, 0),
      'pending_coverage_requests', COALESCE(v_pending_req, 0)
    ),
    'by_pool_type', COALESCE(v_by_pool_type, '[]'::jsonb)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_workforce_pool_overview(uuid) TO authenticated;

COMMIT;
