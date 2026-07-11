-- ============================================================
-- OHM2026_0077 — ESA Cascade: QA Archive Reset
-- Migration:  20260910000000_esa_cascade_qa_archive_reset.sql
-- Depends on: 20260906000000_qa_archive_operational_data_reset.sql
-- ============================================================
-- Purpose:
--   Extends the QA archive/rollback functions to include
--   employee_store_allocations (ESA).
--
--   Root cause: After a QA reset, Plantilla/HR/Vacancy showed zero
--   records but CENCOM still showed Required=300, Actual=300, MFR=100%
--   because v_cencom_allocation_kpi reads directly from
--   `employee_store_allocations WHERE is_active = true`, and the
--   existing QA archive function did not deactivate ESA rows.
--
-- Sections:
--   §1  Schema — qa_archive_batch_id on employee_store_allocations
--   §2  fn_qa_archive_operational_data_reset (updated — adds ESA)
--   §3  fn_qa_rollback_operational_data_reset (updated — restores ESA)
--
-- No CENCOM views are changed in this migration.
-- ============================================================


-- ── §1. qa_archive_batch_id on employee_store_allocations ──────────────────
-- Links deactivated ESA rows to the originating QA batch for rollback.

ALTER TABLE public.employee_store_allocations
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_esa_qa_batch
  ON public.employee_store_allocations (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;


-- ── §2. fn_qa_archive_operational_data_reset (updated) ────────────────────

CREATE OR REPLACE FUNCTION public.fn_qa_archive_operational_data_reset(
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
  v_batch_id           uuid;
  v_now                timestamptz;

  v_plantilla_count    integer := 0;
  v_vacancy_count      integer := 0;
  v_hr_emploc_count    integer := 0;
  v_slots_count        integer := 0;
  v_hc_request_count   integer := 0;
  v_esa_count          integer := 0;
BEGIN
  -- ── Guard: Super Admin only ──────────────────────────────────────────────
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: reason must not be blank ─────────────────────────────────────
  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'archive_reason is required and must not be empty'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id   := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();
  v_batch_id    := gen_random_uuid();
  v_now         := now();

  -- ════════════════════════════════════════════════════════════════════════
  -- MODULE 1: PLANTILLA
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.plantilla
  SET
    is_archived          = true,
    archived_at          = v_now,
    archived_by          = v_caller_id,
    archive_reason       = p_reason,
    qa_archive_batch_id  = v_batch_id,
    updated_at           = v_now,
    updated_by           = v_caller_id
  WHERE
    is_deleted  = false
    AND (is_archived = false OR is_archived IS NULL);

  GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- MODULE 2: VACANCIES
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.vacancies
  SET
    is_archived          = true,
    archived_at          = v_now,
    archived_by_id       = v_caller_id,
    archived_by          = v_caller_name,
    archive_reason       = p_reason,
    status               = 'Archived',
    qa_archive_batch_id  = v_batch_id,
    updated_at           = v_now,
    updated_by           = v_caller_id
  WHERE
    deleted_at  IS NULL
    AND (is_archived = false OR is_archived IS NULL);

  GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- MODULE 3: HR EMPLOC
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.hr_emploc
  SET
    deleted_at           = v_now,
    qa_archived_at       = v_now,
    qa_archived_by       = v_caller_id,
    qa_archive_reason    = p_reason,
    qa_archive_batch_id  = v_batch_id,
    updated_at           = v_now,
    updated_by           = v_caller_id
  WHERE
    deleted_at IS NULL;

  GET DIAGNOSTICS v_hr_emploc_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- MODULE 4: PLANTILLA SLOTS
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.plantilla_slots
  SET
    slot_status          = 'closed',
    closed_at            = v_now,
    closed_by            = v_caller_id,
    closure_reason_code  = 'QA_RESET',
    qa_archive_batch_id  = v_batch_id,
    updated_at           = v_now,
    updated_by           = v_caller_id
  WHERE
    slot_status <> 'closed';

  GET DIAGNOSTICS v_slots_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- MODULE 5: HEADCOUNT REQUESTS
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.headcount_requests
  SET
    is_archived          = true,
    archived_at          = v_now,
    qa_archive_batch_id  = v_batch_id,
    updated_at           = v_now
  WHERE
    is_archived = false;

  GET DIAGNOSTICS v_hc_request_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- MODULE 6: EMPLOYEE STORE ALLOCATIONS
  -- Deactivate all active ESA rows so CENCOM filled_hc drops to zero.
  -- effective_end is set to today (v_now::date) as the terminal date.
  -- qa_archive_batch_id links rows to this batch for rollback.
  -- ESA has no updated_at/updated_by columns — ledger is append-only.
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.employee_store_allocations
  SET
    is_active            = false,
    effective_end        = v_now::date,
    qa_archive_batch_id  = v_batch_id
  WHERE
    is_active = true;

  GET DIAGNOSTICS v_esa_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- AUDIT
  -- ════════════════════════════════════════════════════════════════════════
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    (
      'qa_reset_summary',
      v_batch_id,
      'qa_archive',
      v_caller_id,
      p_reason,
      v_batch_id,
      jsonb_build_object(
        'archive_batch_id',            v_batch_id,
        'executed_by',                 v_caller_id,
        'executed_at',                 v_now,
        'reason',                      p_reason,
        'plantilla_count',             v_plantilla_count,
        'vacancy_count',               v_vacancy_count,
        'hr_emploc_count',             v_hr_emploc_count,
        'slots_count',                 v_slots_count,
        'headcount_request_count',     v_hc_request_count,
        'esa_count',                   v_esa_count
      )
    );

  -- ════════════════════════════════════════════════════════════════════════
  -- RESULT
  -- ════════════════════════════════════════════════════════════════════════
  RETURN jsonb_build_object(
    'archive_batch_id',              v_batch_id,
    'plantilla_archived_count',      v_plantilla_count,
    'vacancy_archived_count',        v_vacancy_count,
    'slots_archived_count',          v_slots_count,
    'hr_emploc_archived_count',      v_hr_emploc_count,
    'hc_requests_archived_count',    v_hc_request_count,
    'esa_deactivated_count',         v_esa_count,
    'executed_by',                   v_caller_id,
    'executed_at',                   v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_qa_archive_operational_data_reset(text) IS
  'QA-only Super Admin batch archive. Soft-archives all active Plantilla, '
  'Vacancy, HR Emploc, Plantilla Slots, Headcount Requests, and '
  'employee_store_allocations in a single transaction. ESA rows are deactivated '
  '(is_active=false, effective_end=today) so CENCOM KPI views clear to zero. '
  'Returns per-module affected row counts and a shared archive_batch_id for '
  'audit and rollback. No hard deletes. '
  'Rollback: fn_qa_rollback_operational_data_reset(batch_id, reason).';

REVOKE ALL ON FUNCTION public.fn_qa_archive_operational_data_reset(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_qa_archive_operational_data_reset(text) TO authenticated;


-- ── §3. fn_qa_rollback_operational_data_reset (updated) ───────────────────

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
  v_esa_count        integer := 0;
BEGIN
  -- ── Guard: Super Admin only ──────────────────────────────────────────────
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: reason must not be blank ─────────────────────────────────────
  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'rollback_reason is required and must not be empty'
      USING ERRCODE = '22000';
  END IF;

  -- ── Guard: batch must exist ──────────────────────────────────────────────
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

  -- ════════════════════════════════════════════════════════════════════════
  -- ROLLBACK: PLANTILLA
  -- ════════════════════════════════════════════════════════════════════════
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
  WHERE
    qa_archive_batch_id = p_batch_id
    AND is_archived     = true;

  GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- ROLLBACK: VACANCIES
  -- ════════════════════════════════════════════════════════════════════════
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
  WHERE
    qa_archive_batch_id = p_batch_id
    AND is_archived     = true;

  GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- ROLLBACK: HR EMPLOC
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.hr_emploc
  SET
    deleted_at          = NULL,
    qa_archived_at      = NULL,
    qa_archived_by      = NULL,
    qa_archive_reason   = NULL,
    qa_archive_batch_id = NULL,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE
    qa_archive_batch_id = p_batch_id;

  GET DIAGNOSTICS v_hr_emploc_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- ROLLBACK: PLANTILLA SLOTS
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.plantilla_slots
  SET
    slot_status         = 'open',
    closed_at           = NULL,
    closed_by           = NULL,
    closure_reason_code = NULL,
    qa_archive_batch_id = NULL,
    updated_at          = v_now,
    updated_by          = v_caller_id
  WHERE
    qa_archive_batch_id = p_batch_id
    AND slot_status     = 'closed'
    AND closure_reason_code = 'QA_RESET';

  GET DIAGNOSTICS v_slots_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- ROLLBACK: HEADCOUNT REQUESTS
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.headcount_requests
  SET
    is_archived         = false,
    archived_at         = NULL,
    qa_archive_batch_id = NULL,
    updated_at          = v_now
  WHERE
    qa_archive_batch_id = p_batch_id
    AND is_archived     = true;

  GET DIAGNOSTICS v_hc_request_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- ROLLBACK: EMPLOYEE STORE ALLOCATIONS
  -- Restore deactivated ESA rows from this batch back to active.
  -- Clears is_active, effective_end, and qa_archive_batch_id.
  -- ESA has no updated_at/updated_by columns.
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.employee_store_allocations
  SET
    is_active            = true,
    effective_end        = NULL,
    qa_archive_batch_id  = NULL
  WHERE
    qa_archive_batch_id = p_batch_id
    AND is_active       = false;

  GET DIAGNOSTICS v_esa_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- AUDIT
  -- ════════════════════════════════════════════════════════════════════════
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
        'esa_restored_count',            v_esa_count
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
    'rolled_back_by',                v_caller_id,
    'rolled_back_at',                v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_qa_rollback_operational_data_reset(uuid, text) IS
  'Reverses a prior fn_qa_archive_operational_data_reset call identified by '
  'p_batch_id. Restores Plantilla (is_archived), Vacancies (is_archived + '
  'status → Open), HR Emploc (deleted_at → NULL), Plantilla Slots '
  '(slot_status → open), Headcount Requests (is_archived), and '
  'employee_store_allocations (is_active=true, effective_end=NULL). '
  'Only records archived by this specific batch are touched. '
  'Super Admin only. Reason required.';

REVOKE ALL ON FUNCTION public.fn_qa_rollback_operational_data_reset(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_qa_rollback_operational_data_reset(uuid, text) TO authenticated;
