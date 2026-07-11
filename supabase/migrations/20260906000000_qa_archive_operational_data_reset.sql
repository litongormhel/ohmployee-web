-- ============================================================
-- OHM2026_0070 — QA Reset: Archive Operational Data
-- Migration:  20260906000000_qa_archive_operational_data_reset.sql
-- Depends on: 20260602000000_data_archival_recovery_foundation.sql
--             20260804000000_plantilla_slot_foundation_v1.sql
-- ============================================================
-- Purpose:
--   Provides a Super Admin-only QA batch-archive function that
--   soft-archives all active operational data from Plantilla,
--   Vacancy, HR Emploc, Plantilla Slots, and Headcount Requests
--   in a single atomic transaction.
--
--   Non-destructive:
--     • No hard deletes performed at any point
--     • All affected records carry a shared qa_archive_batch_id
--     • Full rollback via fn_qa_rollback_operational_data_reset
--     • Import history, approval logs, user profiles, and audit
--       tables are never touched
--
-- Sections:
--   §1  Schema additions — qa_archive_batch_id on affected tables
--   §2  Schema additions — hr_emploc QA audit columns
--   §3  Schema additions — archival_audit_logs.archive_batch_id
--   §4  QA_RESET reason code seed in slot_reason_codes
--   §5  fn_qa_archive_operational_data_reset (main RPC)
--   §6  fn_qa_rollback_operational_data_reset (rollback RPC)
--
-- Guards:
--   • Only public.is_super_admin() may invoke either RPC
--   • p_reason must be non-empty (rejects blank/whitespace)
--   • Returns per-module affected row counts
--
-- Validation (run after apply):
--   V1  SELECT column_name FROM information_schema.columns
--         WHERE table_schema='public' AND table_name='plantilla'
--         AND column_name='qa_archive_batch_id';
--   V2  SELECT column_name FROM information_schema.columns
--         WHERE table_schema='public' AND table_name='hr_emploc'
--         AND column_name='qa_archive_batch_id';
--   V3  SELECT proname FROM pg_proc
--         WHERE proname IN (
--           'fn_qa_archive_operational_data_reset',
--           'fn_qa_rollback_operational_data_reset'
--         );
-- ============================================================


-- ── §1. qa_archive_batch_id on affected operational tables ─────────────────
-- A shared UUID that ties every record archived in one QA reset together.
-- NULL = never QA-archived. Non-NULL = member of that batch.

ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

ALTER TABLE public.vacancies
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

ALTER TABLE public.hr_emploc
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

ALTER TABLE public.plantilla_slots
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

ALTER TABLE public.headcount_requests
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

-- Indexes to support batch rollback queries.
CREATE INDEX IF NOT EXISTS idx_plantilla_qa_batch
  ON public.plantilla (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_vacancies_qa_batch
  ON public.vacancies (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_hr_emploc_qa_batch
  ON public.hr_emploc (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_plantilla_slots_qa_batch
  ON public.plantilla_slots (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_headcount_requests_qa_batch
  ON public.headcount_requests (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;


-- ── §2. hr_emploc QA audit columns ─────────────────────────────────────────
-- hr_emploc has no standard archival columns (only deleted_at exists).
-- The QA reset uses deleted_at as the exclusion mechanism (already filtered
-- by all active queries) and these columns for full audit traceability.

ALTER TABLE public.hr_emploc
  ADD COLUMN IF NOT EXISTS qa_archived_at    timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS qa_archived_by    uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS qa_archive_reason text        DEFAULT NULL;


-- ── §3. archive_batch_id on archival_audit_logs ─────────────────────────────
-- Links individual archival audit rows to the originating QA batch.

ALTER TABLE public.archival_audit_logs
  ADD COLUMN IF NOT EXISTS archive_batch_id uuid DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_archival_audit_logs_batch_id
  ON public.archival_audit_logs (archive_batch_id)
  WHERE archive_batch_id IS NOT NULL;


-- ── §4. QA_RESET reason code seed ──────────────────────────────────────────
-- slot_reason_codes has a FK reference from plantilla_slots.closure_reason_code.
-- Add the QA_RESET reason so plantilla_slots can be closed with a valid FK value.

INSERT INTO public.slot_reason_codes (code, label, description, sort_order)
VALUES (
  'QA_RESET',
  'QA Data Reset',
  'Slot closed as part of a Super Admin QA data archival reset. Reversible via batch rollback.',
  99
)
ON CONFLICT (code) DO NOTHING;


-- ── §5. fn_qa_archive_operational_data_reset ───────────────────────────────

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
  -- Archive all non-deleted, non-already-archived plantilla rows.
  -- Relies on v_plantilla_safe's existing is_archived = false filter.
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
  -- Archive all non-archived, non-deleted vacancies.
  -- vw_slot_derived_vacancy_shadow already excludes is_archived = true,
  -- so Open/Pipeline tabs will become empty once this executes.
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.vacancies
  SET
    is_archived          = true,
    archived_at          = v_now,
    archived_by_id       = v_caller_id,
    archived_by          = v_caller_name,  -- sync legacy text field
    archive_reason       = p_reason,
    status               = 'Archived',     -- consistent with archive_vacancy_record
    qa_archive_batch_id  = v_batch_id,
    updated_at           = v_now,
    updated_by           = v_caller_id
  WHERE
    deleted_at  IS NULL
    AND (is_archived = false OR is_archived IS NULL);

  GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

  -- ════════════════════════════════════════════════════════════════════════
  -- MODULE 3: HR EMPLOC
  -- hr_emploc has no is_archived column; deleted_at IS NULL is the active
  -- query predicate used throughout the system.  Setting deleted_at hides
  -- the record from all active screens immediately.
  -- QA columns preserve full auditability without altering stable queries.
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
  -- Close all non-closed slots.  'closed' is the archive-first terminal
  -- state per the slot lifecycle contract (OHM2026_0002).
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
  -- Archive active HC requests (pipeline vacancy representation).
  -- is_archived = true is already the standard mechanism used by the
  -- hc_request_archive_super_admin_policy migration.
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
  -- AUDIT: one summary row per module in archival_audit_logs
  -- ════════════════════════════════════════════════════════════════════════
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    (
      'qa_reset_summary',
      v_batch_id,               -- batch_id doubles as the summary record_id
      'qa_archive',
      v_caller_id,
      p_reason,
      v_batch_id,
      jsonb_build_object(
        'archive_batch_id',       v_batch_id,
        'executed_by',            v_caller_id,
        'executed_at',            v_now,
        'reason',                 p_reason,
        'plantilla_count',        v_plantilla_count,
        'vacancy_count',          v_vacancy_count,
        'hr_emploc_count',        v_hr_emploc_count,
        'slots_count',            v_slots_count,
        'headcount_request_count', v_hc_request_count
      )
    );

  -- ════════════════════════════════════════════════════════════════════════
  -- RESULT
  -- ════════════════════════════════════════════════════════════════════════
  RETURN jsonb_build_object(
    'archive_batch_id',          v_batch_id,
    'plantilla_archived_count',  v_plantilla_count,
    'vacancy_archived_count',    v_vacancy_count,
    'slots_archived_count',      v_slots_count,
    'hr_emploc_archived_count',  v_hr_emploc_count,
    'hc_requests_archived_count', v_hc_request_count,
    'executed_by',               v_caller_id,
    'executed_at',               v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_qa_archive_operational_data_reset(text) IS
  'QA-only Super Admin batch archive. Soft-archives all active Plantilla, '
  'Vacancy, HR Emploc, Plantilla Slots, and Headcount Request records in a '
  'single transaction. Returns per-module affected row counts and a shared '
  'archive_batch_id for audit and rollback. No hard deletes. '
  'Rollback: fn_qa_rollback_operational_data_reset(batch_id, reason).';

REVOKE ALL ON FUNCTION public.fn_qa_archive_operational_data_reset(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_qa_archive_operational_data_reset(text) TO authenticated;


-- ── §6. fn_qa_rollback_operational_data_reset ──────────────────────────────

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
  -- Restore to 'Open' (previous status was overwritten to 'Archived').
  -- Slot uniqueness constraints (uniq_vacancies_open_per_slot) may prevent
  -- restoration if conflicting open vacancies were created post-archive.
  -- This is intentional: the caller must resolve conflicts before rollback.
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
  -- Clear deleted_at to restore the record to all active queries.
  -- ════════════════════════════════════════════════════════════════════════
  -- Only records archived by this batch have qa_archive_batch_id set;
  -- we never set qa_archive_batch_id on pre-existing deleted rows, so this
  -- condition is safe and sufficient without a deleted_at guard.
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
  -- Reopen closed slots that belong to this batch.
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
        'archive_batch_id',          p_batch_id,
        'rolled_back_by',            v_caller_id,
        'rolled_back_at',            v_now,
        'reason',                    p_reason,
        'plantilla_restored_count',  v_plantilla_count,
        'vacancy_restored_count',    v_vacancy_count,
        'hr_emploc_restored_count',  v_hr_emploc_count,
        'slots_restored_count',      v_slots_count,
        'hc_requests_restored_count', v_hc_request_count
      )
    );

  RETURN jsonb_build_object(
    'archive_batch_id',             p_batch_id,
    'plantilla_restored_count',     v_plantilla_count,
    'vacancy_restored_count',       v_vacancy_count,
    'slots_restored_count',         v_slots_count,
    'hr_emploc_restored_count',     v_hr_emploc_count,
    'hc_requests_restored_count',   v_hc_request_count,
    'rolled_back_by',               v_caller_id,
    'rolled_back_at',               v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_qa_rollback_operational_data_reset(uuid, text) IS
  'Reverses a prior fn_qa_archive_operational_data_reset call identified by '
  'p_batch_id. Restores Plantilla (is_archived), Vacancies (is_archived + '
  'status → Open), HR Emploc (deleted_at → NULL), Plantilla Slots '
  '(slot_status → open), and Headcount Requests (is_archived). '
  'Only records that were archived by this specific batch are touched. '
  'Super Admin only. Reason required.';

REVOKE ALL ON FUNCTION public.fn_qa_rollback_operational_data_reset(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_qa_rollback_operational_data_reset(uuid, text) TO authenticated;
