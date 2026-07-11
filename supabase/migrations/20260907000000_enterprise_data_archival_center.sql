-- ============================================================
-- OHM2026_0071 — Enterprise Data Archival Center
-- Migration: 20260907000000_enterprise_data_archival_center.sql
-- Depends on:
--   20260906000000_qa_archive_operational_data_reset.sql
--     (qa_archive_batch_id columns on plantilla, vacancies,
--      hr_emploc, plantilla_slots, headcount_requests;
--      archival_audit_logs.archive_batch_id;
--      QA_RESET slot_reason_code)
--   20260602000000_data_archival_recovery_foundation.sql
--     (archival_audit_logs table)
--   20260804000000_plantilla_slot_foundation_v1.sql
--     (plantilla_slots table)
-- ============================================================
-- Purpose:
--   Enterprise-grade archival framework exposing individual
--   module archives (Plantilla, Vacancy, HR Emploc) and a
--   full QA Reset Archive, all registered in the
--   system_archive_batches batch registry with 72-active-hour
--   rollback windows (Sunday excluded).
--
--   Non-destructive:
--     • No hard deletes at any point
--     • All records recoverable within the rollback window
--     • Import history, approval logs, user profiles, and
--       audit tables are never touched
--
-- Sections:
--   §1  system_archive_batches table + RLS + indexes
--   §2  fn_get_archive_impact_preview — pre-archive counts
--   §3  fn_archive_plantilla_data — archive Plantilla only
--   §4  fn_archive_vacancy_data — archive Vacancy only
--   §5  fn_archive_hr_emploc_data — archive HR Emploc only
--   §6  fn_archive_all_operational_data — QA Reset (all modules)
--   §7  fn_rollback_archive_batch — 72-active-hour rollback with window check (Sunday excluded)
--   §8  fn_get_archive_batch_history — history for Admin UI
--
-- Guards:
--   • Only public.is_super_admin() may invoke any RPC
--   • p_reason must be ≥ 10 non-whitespace characters
--   • Rollback window is 72 active hours (Sunday excluded) from archive
--   • Rollback after active-hour expiry raises ERRCODE 55000
--   • Rollback of already-rolled-back batch raises ERRCODE 55000
--
-- Validation (run after apply):
--   V1  SELECT table_name FROM information_schema.tables
--         WHERE table_schema='public' AND table_name='system_archive_batches';
--   V2  SELECT proname FROM pg_proc
--         WHERE proname IN (
--           'fn_get_archive_impact_preview',
--           'fn_archive_plantilla_data',
--           'fn_archive_vacancy_data',
--           'fn_archive_hr_emploc_data',
--           'fn_archive_all_operational_data',
--           'fn_rollback_archive_batch',
--           'fn_get_archive_batch_history'
--         );
-- ============================================================


-- ── §1. system_archive_batches ─────────────────────────────────────────────
-- Canonical batch registry for enterprise archival operations.
-- archive_batch_id is the UUID written into qa_archive_batch_id on affected
-- operational tables, enabling batch-scoped rollback queries.

CREATE TABLE IF NOT EXISTS public.system_archive_batches (
  id                uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  archive_batch_id  uuid        UNIQUE NOT NULL DEFAULT gen_random_uuid(),

  -- What was archived
  action_type       text        NOT NULL,
  reason            text        NOT NULL,

  -- Who and when
  executed_by       uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL,
  executed_at       timestamptz NOT NULL DEFAULT now(),

  -- Rollback window: 72 active hours (Sunday excluded) from execution
  rollback_deadline timestamptz NOT NULL,

  -- Affected counts (populated at archive time)
  plantilla_count   integer     NOT NULL DEFAULT 0,
  vacancy_count     integer     NOT NULL DEFAULT 0,
  hr_emploc_count   integer     NOT NULL DEFAULT 0,

  -- Lifecycle
  status            text        NOT NULL DEFAULT 'ACTIVE',

  -- Rollback actor (populated on rollback)
  rolled_back_by    uuid        REFERENCES public.users_profile(id) ON DELETE SET NULL,
  rolled_back_at    timestamptz,

  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT chk_sab_action_type CHECK (
    action_type IN ('qa_reset', 'plantilla', 'vacancy', 'hr_emploc')
  ),
  CONSTRAINT chk_sab_status CHECK (
    status IN ('ACTIVE', 'ROLLED_BACK', 'EXPIRED')
  )
);

COMMENT ON TABLE public.system_archive_batches IS
  'Canonical batch registry for enterprise archival operations. '
  'Each row represents one archive operation executed by Super Admin. '
  'archive_batch_id matches qa_archive_batch_id on affected operational tables.';

-- RLS: Super Admin only
ALTER TABLE public.system_archive_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY sab_super_admin_all ON public.system_archive_batches
  FOR ALL
  USING (public.is_super_admin());

CREATE INDEX IF NOT EXISTS idx_sab_status
  ON public.system_archive_batches (status);

CREATE INDEX IF NOT EXISTS idx_sab_executed_at
  ON public.system_archive_batches (executed_at DESC);

CREATE INDEX IF NOT EXISTS idx_sab_archive_batch_id
  ON public.system_archive_batches (archive_batch_id);


-- ── §2. fn_get_archive_impact_preview ─────────────────────────────────────
-- Returns the count of active operational records that would be archived by
-- each module archive function.  Called from the Admin UI Step 1 preview.

CREATE OR REPLACE FUNCTION public.fn_get_archive_impact_preview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_plantilla_count  integer;
  v_vacancy_count    integer;
  v_hr_emploc_count  integer;
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

  RETURN jsonb_build_object(
    'plantilla_count',  v_plantilla_count,
    'vacancy_count',    v_vacancy_count,
    'hr_emploc_count',  v_hr_emploc_count,
    'total_count',      v_plantilla_count + v_vacancy_count + v_hr_emploc_count
  );
END;
$$;

COMMENT ON FUNCTION public.fn_get_archive_impact_preview() IS
  'Returns counts of active records that would be affected by each module archive. '
  'Super Admin only. No data is modified.';

REVOKE ALL ON FUNCTION public.fn_get_archive_impact_preview() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_impact_preview() TO authenticated;


-- ── §2.5. fn_compute_rollback_deadline ───────────────────────────────────
-- Computes the rollback deadline by counting p_active_hours of non-Sunday
-- time starting from p_start.  Sunday (UTC DOW = 0) contributes 0 hours to
-- the countdown; the window simply pauses and resumes at Monday 00:00 UTC.
--
-- Examples:
--   Friday  14:00 UTC + 72 active hours → Monday   14:00 UTC
--   Saturday 14:00 UTC + 72 active hours → Tuesday  14:00 UTC
--   Thursday 18:00 UTC + 72 active hours → Monday   18:00 UTC
--     (Sun is skipped; 72 non-Sunday hours expire on Monday)

CREATE OR REPLACE FUNCTION public.fn_compute_rollback_deadline(
  p_start        timestamptz,
  p_active_hours integer
)
RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_remaining numeric   := p_active_hours;
  v_current   timestamp := p_start AT TIME ZONE 'UTC';  -- work in plain UTC
  v_day_end   timestamp;
  v_available numeric;
BEGIN
  LOOP
    -- DOW 0 = Sunday.  Skip to Monday 00:00 UTC without consuming any hours.
    IF EXTRACT(DOW FROM v_current) = 0 THEN
      v_current := date_trunc('day', v_current) + INTERVAL '1 day';
      CONTINUE;
    END IF;

    -- Hours available until the next midnight (UTC)
    v_day_end   := date_trunc('day', v_current) + INTERVAL '1 day';
    v_available := EXTRACT(EPOCH FROM (v_day_end - v_current)) / 3600.0;

    IF v_available >= v_remaining THEN
      -- Deadline falls within this non-Sunday day
      RETURN (v_current + v_remaining * INTERVAL '1 hour') AT TIME ZONE 'UTC';
    END IF;

    v_remaining := v_remaining - v_available;
    v_current   := v_day_end;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.fn_compute_rollback_deadline(timestamptz, integer) IS
  'Returns the timestamp that is p_active_hours of non-Sunday time after p_start. '
  'Sunday (UTC DOW=0) contributes 0 hours; the window skips to Monday 00:00 UTC. '
  'Used to compute rollback_deadline for every archive batch.';

REVOKE ALL ON FUNCTION public.fn_compute_rollback_deadline(timestamptz, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_compute_rollback_deadline(timestamptz, integer) TO authenticated;


-- ── §3. fn_archive_plantilla_data ─────────────────────────────────────────
-- Archives all active Plantilla rows and closes open Plantilla Slots.
-- Registers one row in system_archive_batches (action_type = 'plantilla').

CREATE OR REPLACE FUNCTION public.fn_archive_plantilla_data(
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id       uuid;
  v_batch_id        uuid := gen_random_uuid();
  v_now             timestamptz := now();
  v_plantilla_count integer := 0;
  v_slots_count     integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'archive_reason must be at least 10 characters'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id := public.get_current_profile_id();

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

  -- Register batch
  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, status)
  VALUES
    (v_batch_id, 'plantilla', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72), v_plantilla_count, 0, 0, 'ACTIVE');

  -- Audit
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('plantilla_archive', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id',   v_batch_id,
       'action_type',        'plantilla',
       'executed_by',        v_caller_id,
       'executed_at',        v_now,
       'reason',             p_reason,
       'plantilla_count',    v_plantilla_count,
       'slots_count',        v_slots_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',  v_batch_id,
    'plantilla_count',   v_plantilla_count,
    'slots_count',       v_slots_count,
    'executed_by',       v_caller_id,
    'executed_at',       v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_archive_plantilla_data(text) IS
  'Archives all active Plantilla rows and closes open Plantilla Slots. '
  'Registers one system_archive_batches row for rollback tracking. '
  'Super Admin only. Reason ≥ 10 characters required.';

REVOKE ALL ON FUNCTION public.fn_archive_plantilla_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_plantilla_data(text) TO authenticated;


-- ── §4. fn_archive_vacancy_data ───────────────────────────────────────────
-- Archives all active Vacancies and Headcount Requests (pipeline slots).
-- Registers one row in system_archive_batches (action_type = 'vacancy').

CREATE OR REPLACE FUNCTION public.fn_archive_vacancy_data(
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id       uuid;
  v_caller_name     text;
  v_batch_id        uuid := gen_random_uuid();
  v_now             timestamptz := now();
  v_vacancy_count   integer := 0;
  v_hc_count        integer := 0;
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

  -- Archive Vacancies
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

  -- Archive Headcount Requests (pipeline vacancy representation)
  UPDATE public.headcount_requests
  SET
    is_archived         = true,
    archived_at         = v_now,
    qa_archive_batch_id = v_batch_id,
    updated_at          = v_now
  WHERE is_archived = false;
  GET DIAGNOSTICS v_hc_count = ROW_COUNT;

  -- Register batch
  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, status)
  VALUES
    (v_batch_id, 'vacancy', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72), 0, v_vacancy_count, 0, 'ACTIVE');

  -- Audit
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('vacancy_archive', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id',        v_batch_id,
       'action_type',             'vacancy',
       'executed_by',             v_caller_id,
       'executed_at',             v_now,
       'reason',                  p_reason,
       'vacancy_count',           v_vacancy_count,
       'headcount_request_count', v_hc_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',          v_batch_id,
    'vacancy_count',             v_vacancy_count,
    'headcount_request_count',   v_hc_count,
    'executed_by',               v_caller_id,
    'executed_at',               v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_archive_vacancy_data(text) IS
  'Archives all active Vacancies and Headcount Requests. '
  'Registers one system_archive_batches row for rollback tracking. '
  'Super Admin only. Reason ≥ 10 characters required.';

REVOKE ALL ON FUNCTION public.fn_archive_vacancy_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_vacancy_data(text) TO authenticated;


-- ── §5. fn_archive_hr_emploc_data ─────────────────────────────────────────
-- Archives all active HR Emploc rows by setting deleted_at.
-- hr_emploc has no is_archived column; deleted_at IS NULL is the active
-- predicate used by all HR Emploc queries.
-- Registers one row in system_archive_batches (action_type = 'hr_emploc').

CREATE OR REPLACE FUNCTION public.fn_archive_hr_emploc_data(
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id      uuid;
  v_batch_id       uuid := gen_random_uuid();
  v_now            timestamptz := now();
  v_hr_emploc_count integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'archive_reason must be at least 10 characters'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id := public.get_current_profile_id();

  -- Archive HR Emploc rows (uses deleted_at as the exclusion mechanism)
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

  -- Register batch
  INSERT INTO public.system_archive_batches
    (archive_batch_id, action_type, reason, executed_by, executed_at,
     rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, status)
  VALUES
    (v_batch_id, 'hr_emploc', p_reason, v_caller_id, v_now,
     public.fn_compute_rollback_deadline(v_now, 72), 0, 0, v_hr_emploc_count, 'ACTIVE');

  -- Audit
  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    ('hr_emploc_archive', v_batch_id, 'qa_archive', v_caller_id, p_reason, v_batch_id,
     jsonb_build_object(
       'archive_batch_id',   v_batch_id,
       'action_type',        'hr_emploc',
       'executed_by',        v_caller_id,
       'executed_at',        v_now,
       'reason',             p_reason,
       'hr_emploc_count',    v_hr_emploc_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',   v_batch_id,
    'hr_emploc_count',    v_hr_emploc_count,
    'executed_by',        v_caller_id,
    'executed_at',        v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_archive_hr_emploc_data(text) IS
  'Archives all active HR Emploc rows (sets deleted_at). '
  'Registers one system_archive_batches row for rollback tracking. '
  'Super Admin only. Reason ≥ 10 characters required.';

REVOKE ALL ON FUNCTION public.fn_archive_hr_emploc_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_hr_emploc_data(text) TO authenticated;


-- ── §6. fn_archive_all_operational_data ───────────────────────────────────
-- QA Reset Archive: archives ALL active operational records from Plantilla,
-- Vacancies, HR Emploc, Plantilla Slots, and Headcount Requests in a single
-- atomic transaction under one shared archive_batch_id.
--
-- This is the enterprise successor to fn_qa_archive_operational_data_reset
-- and additionally registers in system_archive_batches for full batch
-- lifecycle tracking and rollback window enforcement.

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
       'archive_batch_id',          v_batch_id,
       'action_type',               'qa_reset',
       'executed_by',               v_caller_id,
       'executed_at',               v_now,
       'reason',                    p_reason,
       'plantilla_count',           v_plantilla_count,
       'vacancy_count',             v_vacancy_count,
       'hr_emploc_count',           v_hr_emploc_count,
       'slots_count',               v_slots_count,
       'headcount_request_count',   v_hc_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',           v_batch_id,
    'plantilla_count',            v_plantilla_count,
    'vacancy_count',              v_vacancy_count,
    'hr_emploc_count',            v_hr_emploc_count,
    'slots_count',                v_slots_count,
    'headcount_request_count',    v_hc_count,
    'executed_by',                v_caller_id,
    'executed_at',                v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_archive_all_operational_data(text) IS
  'QA Reset Archive: soft-archives ALL active Plantilla, Vacancies, HR Emploc, '
  'Plantilla Slots, and Headcount Requests in a single transaction under one '
  'archive_batch_id. Registers in system_archive_batches for 72-active-hour rollback (Sunday excluded). '
  'No hard deletes. Super Admin only. Reason ≥ 10 characters required.';

REVOKE ALL ON FUNCTION public.fn_archive_all_operational_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_all_operational_data(text) TO authenticated;


-- ── §7. fn_rollback_archive_batch ─────────────────────────────────────────
-- Reverses an archive batch identified by archive_batch_id.
-- Enforces 72-active-hour rollback window (Sunday excluded).
-- Restores only the records that were archived by the specific batch.

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
  -- Restored to 'Open'. Conflict protection: if a new vacancy was created for
  -- the same VCODE after the archive, the UNIQUE constraint will raise and the
  -- caller must resolve before retrying.
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
       'archive_batch_id',          p_batch_id,
       'action_type',               v_batch.action_type,
       'rolled_back_by',            v_caller_id,
       'rolled_back_at',            v_now,
       'reason',                    p_reason,
       'plantilla_restored_count',  v_plantilla_count,
       'slots_restored_count',      v_slots_count,
       'vacancy_restored_count',    v_vacancy_count,
       'hc_requests_count',         v_hc_count,
       'hr_emploc_restored_count',  v_hr_emploc_count
     ));

  RETURN jsonb_build_object(
    'archive_batch_id',            p_batch_id,
    'plantilla_restored_count',    v_plantilla_count,
    'slots_restored_count',        v_slots_count,
    'vacancy_restored_count',      v_vacancy_count,
    'hc_requests_restored_count',  v_hc_count,
    'hr_emploc_restored_count',    v_hr_emploc_count,
    'rolled_back_by',              v_caller_id,
    'rolled_back_at',              v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_rollback_archive_batch(uuid, text) IS
  'Reverses an archive batch within the 72-active-hour rollback window (Sunday excluded). '
  'Raises ERRCODE 55000 if the window has expired or the batch is already rolled back. '
  'Only restores records that carry the specific qa_archive_batch_id. '
  'Super Admin only. Reason required.';

REVOKE ALL ON FUNCTION public.fn_rollback_archive_batch(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_rollback_archive_batch(uuid, text) TO authenticated;


-- ── §8. fn_get_archive_batch_history ──────────────────────────────────────
-- Returns the full system_archive_batches registry with resolved actor names
-- and computed EXPIRED status.  Used by the Archive History screen.

CREATE OR REPLACE FUNCTION public.fn_get_archive_batch_history()
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
    b.plantilla_count + b.vacancy_count + b.hr_emploc_count AS total_count,
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
  'Returns all system_archive_batches rows with resolved actor display names '
  'and EXPIRED status computed lazily. Super Admin only via RLS.';

REVOKE ALL ON FUNCTION public.fn_get_archive_batch_history() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_batch_history() TO authenticated;
