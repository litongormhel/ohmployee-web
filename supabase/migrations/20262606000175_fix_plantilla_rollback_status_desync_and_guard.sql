-- Migration: 20262606000175_fix_plantilla_rollback_status_desync_and_guard.sql
-- Created: 2026-11-24T13:20:37.715Z
-- Description: Fix plantilla rollback status desync, idempotent guard for already rolled-back batches, and prevent recurring ZERO_EDIT_LOCK loops

BEGIN;

-- ── 1. CONSTRAINT ALIGNMENT ───────────────────────────────────────────────────
-- Ensure 'rejected' is permitted in rollback_status check constraints across both tables.
ALTER TABLE public.plantilla_import_batches DROP CONSTRAINT IF EXISTS pib_rollback_status_check;
ALTER TABLE public.plantilla_import_batches
  ADD CONSTRAINT pib_rollback_status_check CHECK (
    rollback_status IS NULL OR rollback_status IN ('requested','approved','completed','failed','rejected')
  );

ALTER TABLE public.vacancy_import_batches DROP CONSTRAINT IF EXISTS vib_rollback_status_check;
ALTER TABLE public.vacancy_import_batches
  ADD CONSTRAINT vib_rollback_status_check CHECK (
    rollback_status IS NULL OR rollback_status IN ('requested','approved','completed','failed','rejected')
  );

-- ── 2. HISTORICAL DATA RECONCILIATION ─────────────────────────────────────────
-- Batch aa79f9c7-9d44-4f35-9224-8c701534cee7 and similar historical batches had status = 'rolled_back'
-- but rollback_status was left desynchronized as 'requested', causing them to linger in the Pending
-- Approvals queue and repeatedly trigger ZERO_EDIT_LOCK exceptions on post-approval edits.

UPDATE public.plantilla_import_batches
   SET rollback_status       = 'completed',
       rollback_completed_at = COALESCE(rollback_completed_at, updated_at, now()),
       updated_at            = now()
 WHERE status = 'rolled_back'
   AND rollback_status IS DISTINCT FROM 'completed';

UPDATE public.vacancy_import_batches
   SET rollback_status       = 'completed',
       rollback_completed_at = COALESCE(rollback_completed_at, updated_at, now()),
       updated_at            = now()
 WHERE status = 'rolled_back'
   AND rollback_status IS DISTINCT FROM 'completed';

-- Stale requested rollbacks on finalized batches where window has long expired
UPDATE public.vacancy_import_batches
   SET rollback_status      = 'rejected',
       rollback_reason_note = COALESCE(rollback_reason_note, '') || ' [Auto-Rejected: Batch finalized / rollback window expired]',
       updated_at           = now()
 WHERE status = 'finalized'
   AND rollback_status = 'requested';

-- ── 3. RPC HARDENING: public.approve_plantilla_import_rollback ─────────────────
-- Surgical update based on Migration 064:
-- 1. Idempotent check: If batch is already rolled back, auto-complete rollback_status and return cleanly.
-- 2. State validation: Only 'approved' batches can be processed for rollback.
-- 3. Strict Zero-Edit Lock check remains enforced for approved batches.

CREATE OR REPLACE FUNCTION public.approve_plantilla_import_rollback(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_actor     uuid := public.get_current_profile_id();
  v_user_name text;
  v_batch     public.plantilla_import_batches%ROWTYPE;
  v_modified  jsonb;
  v_res       jsonb;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- Guard 1: Idempotent return if already rolled back
  IF v_batch.status = 'rolled_back' THEN
    IF v_batch.rollback_status IS DISTINCT FROM 'completed' THEN
      UPDATE public.plantilla_import_batches
         SET rollback_status       = 'completed',
             rollback_completed_at = COALESCE(rollback_completed_at, now()),
             updated_at            = now()
       WHERE id = p_batch_id;
    END IF;

    RETURN jsonb_build_object(
      'batch_id', p_batch_id,
      'status', 'rolled_back',
      'rollback_status', 'completed',
      'message', 'Batch is already rolled back.'
    );
  END IF;

  -- Guard 2: Only approved batches can be rolled back
  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)', v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT full_name INTO v_user_name FROM public.users_profile WHERE id = v_actor;

  -- Strict Zero-Edit Lock Check
  v_modified := public.get_plantilla_import_first_modified_record(p_batch_id, v_batch.approved_at);
  IF v_modified IS NOT NULL THEN
    RAISE EXCEPTION 'ZERO_EDIT_LOCK: Batch records have been modified post-approval. Employee % (%) was edited on %. Rollback is hard-blocked.',
      v_modified->>'employee_no', v_modified->>'employee_name', v_modified->>'updated_at'
      USING ERRCODE = '40001';
  END IF;

  -- Execute rollback
  v_res := public.rollback_plantilla_import_batch(p_batch_id, COALESCE(v_batch.rollback_reason_note, 'Approved by admin'));

  UPDATE public.plantilla_import_batches
     SET rollback_status      = 'completed',
         rollback_approved_by = v_uid,
         rollback_approved_at = now(),
         approved_by_name     = v_user_name,
         updated_at           = now()
   WHERE id = p_batch_id;

  RETURN v_res;
END$function$
;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_rollback(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_rollback(uuid) TO authenticated, service_role;
ALTER FUNCTION public.approve_plantilla_import_rollback(uuid) SET statement_timeout = '60s';

COMMIT;
