-- ============================================================
-- OHM2026_1138 — Import Vacancy rollback (Super Admin only)
-- Migration: 20260730000003_add_import_vacancy_rollback.sql
-- Depends on: 20260730000002_fix_import_vacancy_source_constraint.sql
-- ============================================================
-- Purpose
--   Allow Super Admin to roll back an APPROVED Import Vacancy batch
--   when the wrong baseline was imported. Rollback is soft-delete only
--   (vacancies via deleted_at, applicants via is_archived). Import and
--   audit history are preserved. Re-importing the same VCODE after
--   rollback must succeed.
--
-- Locked rules
--   1  Rollback soft-deletes imported vacancies from the batch only.
--   2  Rollback soft-deletes/archives applicants seeded by the batch.
--   3  No hard deletes.
--   4  Import/audit history preserved.
--   5  Same VCODE may be re-imported after rollback (duplicate check
--      already filters deleted_at IS NULL — no change required).
--   6  Approve/execute rollback: Super Admin only.
--   7  Request rollback: Head Admin or Super Admin.
--   8  Reason required, minimum 10 characters.
--   9  audit_logs uses 'UPDATE' (no new enum labels added).
--
-- Sections
--   §1  Rollback metadata columns on vacancy_import_batches
--   §2  request_vacancy_import_rollback(batch_id, reason)
--   §3  approve_vacancy_import_rollback(batch_id)   -- SA-only, executes
--   §4  get_vacancy_import_rollback_history(batch_id)
--   §5  Refresh get_vacancy_import_batches to expose rollback fields
-- ============================================================


-- ============================================================
-- §1  Rollback metadata columns
-- ============================================================

ALTER TABLE public.vacancy_import_batches
  ADD COLUMN IF NOT EXISTS rollback_status         text,
  ADD COLUMN IF NOT EXISTS rollback_requested_by   uuid,
  ADD COLUMN IF NOT EXISTS rollback_requested_at   timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_reason         text,
  ADD COLUMN IF NOT EXISTS rollback_approved_by    uuid,
  ADD COLUMN IF NOT EXISTS rollback_approved_at    timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_completed_at   timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_error_detail   text,
  ADD COLUMN IF NOT EXISTS rollback_vacancies_count  integer,
  ADD COLUMN IF NOT EXISTS rollback_applicants_count integer;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vib_rollback_status_check'
  ) THEN
    ALTER TABLE public.vacancy_import_batches
      ADD CONSTRAINT vib_rollback_status_check CHECK (
        rollback_status IS NULL
        OR rollback_status IN ('requested','approved','completed','failed')
      );
  END IF;
END$$;

COMMENT ON COLUMN public.vacancy_import_batches.rollback_status IS
  'NULL when no rollback requested; otherwise requested → completed (or failed). '
  'OHM2026_1138.';


-- ============================================================
-- §2  request_vacancy_import_rollback
-- ============================================================
-- RBAC: Head Admin or Super Admin. Reason ≥ 10 chars.
-- Only an APPROVED batch with no active rollback can be requested.

CREATE OR REPLACE FUNCTION public.request_vacancy_import_rollback(
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
  v_reason text := COALESCE(trim(p_reason), '');
BEGIN
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required to request rollback'
      USING ERRCODE = '42501';
  END IF;

  IF length(v_reason) < 10 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rollback reason must be at least 10 characters'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch
    FROM public.vacancy_import_batches
   WHERE id = p_batch_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  IF v_batch.rollback_status IN ('requested','approved','completed') THEN
    RAISE EXCEPTION 'INVALID_STATE: rollback already % for this batch',
      v_batch.rollback_status USING ERRCODE = '22023';
  END IF;

  UPDATE public.vacancy_import_batches
     SET rollback_status        = 'requested',
         rollback_requested_by  = v_uid,
         rollback_requested_at  = now(),
         rollback_reason        = v_reason,
         rollback_approved_by   = NULL,
         rollback_approved_at   = NULL,
         rollback_completed_at  = NULL,
         rollback_error_detail  = NULL,
         updated_at             = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object(
      'event',  'rollback_requested',
      'reason', v_reason
    ));

  RETURN jsonb_build_object(
    'batch_id',        p_batch_id,
    'rollback_status', 'requested'
  );
END$func$;

REVOKE ALL ON FUNCTION public.request_vacancy_import_rollback(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_vacancy_import_rollback(uuid,text) TO authenticated;

COMMENT ON FUNCTION public.request_vacancy_import_rollback IS
  'Request rollback of an APPROVED Import Vacancy batch (OHM2026_1138). '
  'Reason ≥ 10 chars. RBAC: Head Admin / Super Admin.';


-- ============================================================
-- §3  approve_vacancy_import_rollback (SA only, executes rollback)
-- ============================================================
-- Soft-deletes vacancies created by the batch (deleted_at = now()) and
-- archives applicants seeded by the batch (is_archived = true). Records
-- counts + completion timestamp on the batch. Logs UPDATE audit row.

CREATE OR REPLACE FUNCTION public.approve_vacancy_import_rollback(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid       uuid := auth.uid();
  v_batch     public.vacancy_import_batches%ROWTYPE;
  v_vac_count int  := 0;
  v_app_count int  := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin required to approve/execute rollback'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.vacancy_import_batches
   WHERE id = p_batch_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;

  IF v_batch.rollback_status IS DISTINCT FROM 'requested' THEN
    RAISE EXCEPTION 'INVALID_STATE: rollback must be in "requested" state (current=%)',
      COALESCE(v_batch.rollback_status, 'none') USING ERRCODE = '22023';
  END IF;

  -- ── Archive applicants seeded by this batch ──────────────────────────────
  -- Applicants do not have deleted_at; archive via is_archived = true and
  -- match on vcode owned by this batch's vacancies.
  WITH batch_vcodes AS (
    SELECT vcode FROM public.vacancies
     WHERE source_vacancy_import_batch_id = p_batch_id
       AND vcode IS NOT NULL
  ),
  updated_apps AS (
    UPDATE public.applicants a
       SET is_archived = true,
           updated_by  = public.get_current_profile_id(),
           updated_at  = now()
      FROM batch_vcodes b
     WHERE a.vacancy_vcode = b.vcode
       AND COALESCE(a.is_archived, false) = false
    RETURNING a.id
  )
  SELECT count(*) INTO v_app_count FROM updated_apps;

  -- ── Soft-delete vacancies created by this batch ──────────────────────────
  WITH updated_vacs AS (
    UPDATE public.vacancies v
       SET deleted_at = now(),
           updated_at = now()
     WHERE v.source_vacancy_import_batch_id = p_batch_id
       AND v.deleted_at IS NULL
    RETURNING v.id
  )
  SELECT count(*) INTO v_vac_count FROM updated_vacs;

  -- ── Finalise batch ───────────────────────────────────────────────────────
  UPDATE public.vacancy_import_batches
     SET rollback_status           = 'completed',
         rollback_approved_by      = v_uid,
         rollback_approved_at      = now(),
         rollback_completed_at     = now(),
         rollback_vacancies_count  = v_vac_count,
         rollback_applicants_count = v_app_count,
         rollback_error_detail     = NULL,
         updated_at                = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object(
      'event',      'rollback_completed',
      'vacancies',  v_vac_count,
      'applicants', v_app_count
    ));

  RETURN jsonb_build_object(
    'batch_id',         p_batch_id,
    'rollback_status',  'completed',
    'vacancies_rolled_back',  v_vac_count,
    'applicants_rolled_back', v_app_count
  );
EXCEPTION WHEN others THEN
  -- Record human-readable failure and re-raise.
  UPDATE public.vacancy_import_batches
     SET rollback_status       = 'failed',
         rollback_error_detail = SQLERRM,
         updated_at            = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('event','rollback_failed','error', SQLERRM));

  RAISE EXCEPTION 'ROLLBACK_FAILED: %', SQLERRM USING ERRCODE = '22000';
END$func$;

REVOKE ALL ON FUNCTION public.approve_vacancy_import_rollback(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_vacancy_import_rollback(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_vacancy_import_rollback IS
  'Approve and execute rollback of an Import Vacancy batch (OHM2026_1138). '
  'Soft-deletes imported vacancies (deleted_at) and archives seeded applicants '
  '(is_archived = true). RBAC: Super Admin only.';


-- ============================================================
-- §4  get_vacancy_import_rollback_history
-- ============================================================
-- Returns one row per batch with rollback fields + actor display names
-- (full_name from users_profile when available, falls back to email/uid).

CREATE OR REPLACE FUNCTION public.get_vacancy_import_rollback_history(
  p_batch_id uuid
)
RETURNS TABLE (
  batch_id                  uuid,
  rollback_status           text,
  rollback_reason           text,
  rollback_requested_by     uuid,
  rollback_requested_by_name text,
  rollback_requested_at     timestamptz,
  rollback_approved_by      uuid,
  rollback_approved_by_name text,
  rollback_approved_at      timestamptz,
  rollback_completed_at     timestamptz,
  rollback_error_detail     text,
  rollback_vacancies_count  integer,
  rollback_applicants_count integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT
    b.id,
    b.rollback_status,
    b.rollback_reason,
    b.rollback_requested_by,
    COALESCE(rp.full_name, rp.email, b.rollback_requested_by::text),
    b.rollback_requested_at,
    b.rollback_approved_by,
    COALESCE(ap.full_name, ap.email, b.rollback_approved_by::text),
    b.rollback_approved_at,
    b.rollback_completed_at,
    b.rollback_error_detail,
    b.rollback_vacancies_count,
    b.rollback_applicants_count
  FROM public.vacancy_import_batches b
  LEFT JOIN public.users_profile rp ON rp.auth_user_id = b.rollback_requested_by
  LEFT JOIN public.users_profile ap ON ap.auth_user_id = b.rollback_approved_by
  WHERE b.id = p_batch_id
    AND (public.i_have_full_access() OR b.uploaded_by = auth.uid());
$func$;

REVOKE ALL ON FUNCTION public.get_vacancy_import_rollback_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_import_rollback_history(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_vacancy_import_rollback_history IS
  'Per-batch rollback timeline with actor display names (OHM2026_1138).';


-- ============================================================
-- §5  Refresh get_vacancy_import_batches to expose rollback fields
-- ============================================================
-- Adds rollback_* columns (and approver display info) to the listing
-- so the History list can show approved/rejected by + timestamp +
-- rejection reason without per-row hydration.

DROP FUNCTION IF EXISTS public.get_vacancy_import_batches(text);

CREATE OR REPLACE FUNCTION public.get_vacancy_import_batches(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                       uuid,
  file_name                text,
  status                   text,
  selected_group_id        uuid,
  selected_account_id      uuid,
  group_name               text,
  account_name             text,
  uploaded_by              uuid,
  uploaded_role            text,
  uploaded_at              timestamptz,
  approved_by              uuid,
  approved_by_name         text,
  approved_at              timestamptz,
  rejected_by              uuid,
  rejected_by_name         text,
  rejected_at              timestamptz,
  rejection_reason         text,
  commit_error_detail      text,
  total_rows               integer,
  valid_rows               integer,
  flagged_rows             integer,
  skipped_rows             integer,
  blocked_rows             integer,
  open_count               integer,
  pipeline_count           integer,
  duplicate_vcode_count    integer,
  existing_vcode_count     integer,
  context_mismatch_count   integer,
  committed_vacancies      integer,
  committed_applicants     integer,
  error_summary            jsonb,
  rollback_status          text,
  rollback_reason          text,
  rollback_requested_by    uuid,
  rollback_requested_by_name text,
  rollback_requested_at    timestamptz,
  rollback_approved_by     uuid,
  rollback_approved_by_name text,
  rollback_approved_at     timestamptz,
  rollback_completed_at    timestamptz,
  rollback_error_detail    text,
  rollback_vacancies_count  integer,
  rollback_applicants_count integer
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
    b.approved_by,
    COALESCE(ap.full_name, ap.email, b.approved_by::text),
    b.approved_at,
    b.rejected_by,
    COALESCE(rp.full_name, rp.email, b.rejected_by::text),
    b.rejected_at,
    b.rejection_reason, b.commit_error_detail,
    b.total_rows, b.valid_rows, b.flagged_rows, b.skipped_rows, b.blocked_rows,
    b.open_count, b.pipeline_count, b.duplicate_vcode_count,
    b.existing_vcode_count, b.context_mismatch_count,
    b.committed_vacancies, b.committed_applicants, b.error_summary,
    b.rollback_status, b.rollback_reason,
    b.rollback_requested_by,
    COALESCE(rrp.full_name, rrp.email, b.rollback_requested_by::text),
    b.rollback_requested_at,
    b.rollback_approved_by,
    COALESCE(rap.full_name, rap.email, b.rollback_approved_by::text),
    b.rollback_approved_at,
    b.rollback_completed_at,
    b.rollback_error_detail,
    b.rollback_vacancies_count,
    b.rollback_applicants_count
  FROM public.vacancy_import_batches b
  LEFT JOIN public.groups        g   ON g.id  = b.selected_group_id
  LEFT JOIN public.accounts      a   ON a.id  = b.selected_account_id
  LEFT JOIN public.users_profile ap  ON ap.auth_user_id  = b.approved_by
  LEFT JOIN public.users_profile rp  ON rp.auth_user_id  = b.rejected_by
  LEFT JOIN public.users_profile rrp ON rrp.auth_user_id = b.rollback_requested_by
  LEFT JOIN public.users_profile rap ON rap.auth_user_id = b.rollback_approved_by
  WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
    AND (p_status IS NULL OR b.status = p_status)
  ORDER BY b.created_at DESC;
$func$;

REVOKE ALL ON FUNCTION public.get_vacancy_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_import_batches(text) TO authenticated;

COMMENT ON FUNCTION public.get_vacancy_import_batches IS
  'Listing of Import Vacancy batches with rollback fields and resolved actor '
  'display names (OHM2026_1138).';
