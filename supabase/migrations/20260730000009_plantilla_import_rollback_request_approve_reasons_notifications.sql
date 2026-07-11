-- ============================================================
-- OHM2026_1146 — Plantilla Import: rollback request/approve split,
--                 reject + rollback reason dropdowns, notifications,
--                 approval escalation. Mirrors Import Vacancy
--                 OHM2026_1138/1140 patterns for UX parity.
--
-- Migration:  20260730000009_plantilla_import_rollback_request_approve_reasons_notifications.sql
-- Depends on: 20260626000000_plantilla_import_rollback_v1.sql
--             20260624000000_fix_plantilla_import_audit_action.sql
--             20260730000008_fix_plantilla_import_audit_action_refix.sql
-- ============================================================
-- Purpose
--   1. Reject Import Plantilla → dropdown reason code + optional remarks
--      (remarks REQUIRED when reason_code = 'other'). Preserves the legacy
--      rejection_reason text column ("<Label> — <note>") for display
--      backward compatibility.
--   2. Replace the single-shot rollback executor with a two-step flow:
--        request_plantilla_import_rollback  → Encoder/HA/SA
--        approve_plantilla_import_rollback  → SA only (executes)
--      Reason dropdown required for the request; remarks ≥ 10 chars.
--   3. Upload notifications:
--        Encoder upload   → all Head Admins
--        Head Admin upload → all Super Admins
--        Super Admin upload → none
--      Deep-link: /plantilla_import/batch/<batch_id>
--   4. Rollback notifications:
--        request   → Super Admin
--        completed → original requester
--        failed    → original requester + Super Admin
--   5. Approval escalation after 3 days pending approval → Super Admin
--      notified ONCE per batch (idempotent via approval_escalated_at).
--
-- Locked rules (per behavior.md + system.md)
--   - No applied migration is modified.
--   - audit_logs uses APPROVAL / UPDATE / INSERT only (no new enum labels).
--   - Notifications use existing public.notifications table; recipient_user_id
--     = users_profile.auth_user_id; profiles with NULL auth_user_id are
--     silently skipped (matches OHM2026_2064 deactivation notif behaviour
--     used by OHM2026_1140 for Import Vacancy).
--   - No hard deletes; rollback executor (rollback_plantilla_import_batch)
--     is REUSED unchanged — soft-delete / restore semantics preserved.
--   - Rollback approval/execution: Super Admin only.
--   - Rollback request: Encoder, Head Admin, or Super Admin.
--   - rejection_reason and rollback_reason text columns are preserved
--     ("<Label> — <note>" composed for display).
--
-- Sections
--   §1  Reason + escalation columns + rollback_status column on
--       plantilla_import_batches
--   §2  Notification helpers (_notify_plantilla_import_role / _user)
--   §3  reject_plantilla_import_batch — dropdown reason code + note
--   §4  request_plantilla_import_rollback — Encoder/HA/SA request
--   §5  approve_plantilla_import_rollback — SA-only executor wrapper
--   §6  Trigger: stamp approval_due_at + notify approver on upload
--   §7  escalate_pending_plantilla_import_approvals — SA escalation
--   §8  Refresh get_plantilla_import_batches listing RPC
--   §9  get_plantilla_import_rollback_history per-batch RPC
--
-- Validation queries (run after applying)
--   V1  Required columns exist:
--         SELECT column_name FROM information_schema.columns
--          WHERE table_schema='public' AND table_name='plantilla_import_batches'
--            AND column_name IN ('rejection_reason_code','rejection_reason_note',
--                'rollback_reason_code','rollback_reason_note','rollback_status',
--                'rollback_requested_by','rollback_requested_at',
--                'rollback_approved_by','rollback_approved_at','rollback_completed_at',
--                'approval_due_at','approval_escalated_at','approval_notified_at');
--   V2  RPC signatures:
--         SELECT pg_get_function_identity_arguments(p.oid), p.proname
--           FROM pg_proc p WHERE p.proname IN
--             ('reject_plantilla_import_batch','request_plantilla_import_rollback',
--              'approve_plantilla_import_rollback',
--              'escalate_pending_plantilla_import_approvals',
--              'get_plantilla_import_rollback_history');
--   V3  Trigger present:
--         SELECT tgname FROM pg_trigger WHERE tgname='trg_plantilla_import_notify_approver';
--   V4  Reject 'Other' without remarks raises 22023:
--         SELECT reject_plantilla_import_batch('<batch-uuid>'::uuid, 'other', NULL);
--   V5  Idempotent escalation drops to 0 on 2nd call:
--         SELECT escalate_pending_plantilla_import_approvals();
-- ============================================================


-- ============================================================
-- §1  Reason columns + escalation metadata + rollback_status
-- ============================================================

ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS rejection_reason_code  text,
  ADD COLUMN IF NOT EXISTS rejection_reason_note  text,
  ADD COLUMN IF NOT EXISTS rollback_reason_code   text,
  ADD COLUMN IF NOT EXISTS rollback_reason_note   text,
  ADD COLUMN IF NOT EXISTS rollback_status        text,
  ADD COLUMN IF NOT EXISTS rollback_requested_by  uuid,
  ADD COLUMN IF NOT EXISTS rollback_requested_at  timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_approved_by   uuid,
  ADD COLUMN IF NOT EXISTS rollback_approved_at   timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_completed_at  timestamptz,
  ADD COLUMN IF NOT EXISTS approval_due_at        timestamptz,
  ADD COLUMN IF NOT EXISTS approval_escalated_at  timestamptz,
  ADD COLUMN IF NOT EXISTS approval_notified_at   timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'pib_rejection_reason_code_check'
  ) THEN
    ALTER TABLE public.plantilla_import_batches
      ADD CONSTRAINT pib_rejection_reason_code_check CHECK (
        rejection_reason_code IS NULL OR rejection_reason_code IN (
          'wrong_group_account',
          'invalid_csv',
          'duplicate_vcode',
          'invalid_vacancy_data',
          'applicant_data_incomplete',
          'uploaded_by_mistake',
          'other'
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'pib_rollback_reason_code_check'
  ) THEN
    ALTER TABLE public.plantilla_import_batches
      ADD CONSTRAINT pib_rollback_reason_code_check CHECK (
        rollback_reason_code IS NULL OR rollback_reason_code IN (
          'wrong_batch',
          'wrong_group_account',
          'wrong_vcode_list',
          'wrong_applicant_pipeline',
          'duplicate_migration_correction',
          'uploaded_by_mistake',
          'other'
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'pib_rollback_status_check'
  ) THEN
    ALTER TABLE public.plantilla_import_batches
      ADD CONSTRAINT pib_rollback_status_check CHECK (
        rollback_status IS NULL
        OR rollback_status IN ('requested','approved','completed','failed')
      );
  END IF;
END$$;

COMMENT ON COLUMN public.plantilla_import_batches.rejection_reason_code IS
  'Canonical reject reason code (OHM2026_1146).';
COMMENT ON COLUMN public.plantilla_import_batches.rejection_reason_note IS
  'Optional remarks; REQUIRED when rejection_reason_code = ''other'' (OHM2026_1146).';
COMMENT ON COLUMN public.plantilla_import_batches.rollback_reason_code IS
  'Canonical rollback reason code (OHM2026_1146).';
COMMENT ON COLUMN public.plantilla_import_batches.rollback_reason_note IS
  'Required remarks for rollback (≥ 10 chars) (OHM2026_1146).';
COMMENT ON COLUMN public.plantilla_import_batches.rollback_status IS
  'Two-step rollback lifecycle: requested → completed/failed. NULL when no '
  'rollback requested. The legacy batch.status (rolled_back / rollback_failed) '
  'is still set by rollback_plantilla_import_batch on execute (OHM2026_1146).';
COMMENT ON COLUMN public.plantilla_import_batches.approval_due_at IS
  'When this batch becomes overdue (created_at + 3 days). OHM2026_1146.';
COMMENT ON COLUMN public.plantilla_import_batches.approval_escalated_at IS
  'When the SA escalation notification was sent (idempotency guard). OHM2026_1146.';
COMMENT ON COLUMN public.plantilla_import_batches.approval_notified_at IS
  'When the upload-time approver notification was emitted. OHM2026_1146.';


-- ============================================================
-- §2  Notification helpers — internal use only
-- ============================================================

CREATE OR REPLACE FUNCTION public._notify_plantilla_import_role(
  p_role_aliases   text[],
  p_recipient_role text,
  p_title          text,
  p_message        text,
  p_event_type     text,
  p_deep_link      text,
  p_reference_id   text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_rec   record;
  v_count int := 0;
BEGIN
  FOR v_rec IN
    SELECT DISTINCT up.auth_user_id
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.is_active = true
      AND up.auth_user_id IS NOT NULL
      AND r.role_name = ANY (p_role_aliases)
  LOOP
    INSERT INTO public.notifications (
      recipient_role, recipient_user_id,
      notification_type, event_type,
      title, message,
      deep_link_route, reference_type, reference_id
    ) VALUES (
      p_recipient_role, v_rec.auth_user_id,
      'plantilla_import', p_event_type,
      p_title, p_message,
      p_deep_link, 'plantilla_import_batch', p_reference_id
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END$func$;

REVOKE ALL ON FUNCTION public._notify_plantilla_import_role(text[],text,text,text,text,text,text)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._notify_plantilla_import_role IS
  'Internal Import Plantilla notification fan-out per role alias set (OHM2026_1146). '
  'Skips users with NULL auth_user_id.';


CREATE OR REPLACE FUNCTION public._notify_plantilla_import_user(
  p_auth_user_id   uuid,
  p_recipient_role text,
  p_title          text,
  p_message        text,
  p_event_type     text,
  p_deep_link      text,
  p_reference_id   text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  IF p_auth_user_id IS NULL THEN RETURN false; END IF;
  INSERT INTO public.notifications (
    recipient_role, recipient_user_id,
    notification_type, event_type,
    title, message,
    deep_link_route, reference_type, reference_id
  ) VALUES (
    COALESCE(p_recipient_role, 'general'), p_auth_user_id,
    'plantilla_import', p_event_type,
    p_title, p_message,
    p_deep_link, 'plantilla_import_batch', p_reference_id
  );
  RETURN true;
END$func$;

REVOKE ALL ON FUNCTION public._notify_plantilla_import_user(uuid,text,text,text,text,text,text)
  FROM PUBLIC, anon, authenticated;


-- ============================================================
-- §3  reject_plantilla_import_batch — dropdown reason + optional note
-- ============================================================
-- Drops the legacy (uuid, text) signature and replaces it with
-- (uuid, text, text). reason_code is required; note is required when
-- reason_code = 'other'. rejection_reason is composed for display
-- backward-compat ("<Label> — <note>").

DROP FUNCTION IF EXISTS public.reject_plantilla_import_batch(uuid, text);

CREATE OR REPLACE FUNCTION public.reject_plantilla_import_batch(
  p_batch_id    uuid,
  p_reason_code text,
  p_reason_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid     uuid := auth.uid();
  v_batch   public.plantilla_import_batches%ROWTYPE;
  v_code    text := COALESCE(lower(trim(p_reason_code)), '');
  v_note    text := NULLIF(trim(COALESCE(p_reason_note,'')), '');
  v_label   text;
  v_display text;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  IF v_code = '' THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason is required'
      USING ERRCODE = '22023';
  END IF;

  v_label := CASE v_code
    WHEN 'wrong_group_account'       THEN 'Wrong Group/Account selected'
    WHEN 'invalid_csv'               THEN 'Invalid CSV / wrong template'
    WHEN 'duplicate_vcode'           THEN 'Duplicate VCODE issue'
    WHEN 'invalid_vacancy_data'      THEN 'Invalid vacancy data'
    WHEN 'applicant_data_incomplete' THEN 'Applicant data incomplete'
    WHEN 'uploaded_by_mistake'       THEN 'Uploaded by mistake'
    WHEN 'other'                     THEN 'Other'
    ELSE NULL
  END;
  IF v_label IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: unsupported rejection reason "%"', p_reason_code
      USING ERRCODE = '22023';
  END IF;

  IF v_code = 'other' AND v_note IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: remarks are required when reason is "Other"'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed','draft_uploaded') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status
      USING ERRCODE = '22023';
  END IF;

  v_display := CASE WHEN v_note IS NULL THEN v_label
                    ELSE v_label || ' — ' || v_note END;

  UPDATE public.plantilla_import_batches
     SET status                = 'rejected',
         rejected_by           = v_uid,
         rejected_at           = now(),
         rejection_reason_code = v_code,
         rejection_reason_note = v_note,
         rejection_reason      = v_display,
         updated_at            = now()
   WHERE id = p_batch_id;

  -- Audit uses UPDATE (no new audit_action enum labels — OHM2026_1146).
  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object(
      'event',       'rejected',
      'reason_code', v_code,
      'reason_note', v_note,
      'new_status',  'rejected'
    ));

  RETURN jsonb_build_object(
    'batch_id',              p_batch_id,
    'status',                'rejected',
    'rejection_reason_code', v_code,
    'rejection_reason_note', v_note
  );
END$func$;

REVOKE ALL ON FUNCTION public.reject_plantilla_import_batch(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_plantilla_import_batch(uuid,text,text) TO authenticated;

COMMENT ON FUNCTION public.reject_plantilla_import_batch(uuid,text,text) IS
  'Reject Import Plantilla batch with required reason code + optional note '
  '(remarks required for "other"). Audit uses UPDATE. RBAC: HA/SA. OHM2026_1146.';


-- ============================================================
-- §4  request_plantilla_import_rollback — Encoder/HA/SA request
-- ============================================================
-- Reason code required; remarks required and must be ≥ 10 chars.
-- Notifies Super Admin. Only approved batches with rollback_ready may be
-- requested. The legacy batch.status remains 'approved' until SA executes.

CREATE OR REPLACE FUNCTION public.request_plantilla_import_rollback(
  p_batch_id    uuid,
  p_reason_code text,
  p_reason_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid      uuid := auth.uid();
  v_batch    public.plantilla_import_batches%ROWTYPE;
  v_code     text := COALESCE(lower(trim(p_reason_code)), '');
  v_note     text := COALESCE(trim(p_reason_note), '');
  v_label    text;
  v_display  text;
  v_notified int;
BEGIN
  -- Encoder, Head Admin, or Super Admin may REQUEST a rollback.
  IF NOT public.fn_can_upload_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Encoder, Head Admin, or Super Admin required to request rollback'
      USING ERRCODE = '42501';
  END IF;

  IF v_code = '' THEN
    RAISE EXCEPTION 'INVALID_INPUT: rollback reason is required'
      USING ERRCODE = '22023';
  END IF;

  v_label := CASE v_code
    WHEN 'wrong_batch'                    THEN 'Wrong batch imported'
    WHEN 'wrong_group_account'            THEN 'Wrong Group/Account'
    WHEN 'wrong_vcode_list'               THEN 'Wrong VCODE list'
    WHEN 'wrong_applicant_pipeline'       THEN 'Wrong applicant pipeline data'
    WHEN 'duplicate_migration_correction' THEN 'Duplicate/migration correction'
    WHEN 'uploaded_by_mistake'            THEN 'Uploaded by mistake'
    WHEN 'other'                          THEN 'Other'
    ELSE NULL
  END;
  IF v_label IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: unsupported rollback reason "%"', p_reason_code
      USING ERRCODE = '22023';
  END IF;

  IF length(v_note) < 10 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rollback remarks must be at least 10 characters'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;
  IF NOT COALESCE(v_batch.rollback_ready, false) THEN
    RAISE EXCEPTION 'ROLLBACK_NOT_READY: batch has no completed rollback lineage'
      USING ERRCODE = '22023';
  END IF;
  IF v_batch.rollback_status IN ('requested','approved','completed') THEN
    RAISE EXCEPTION 'INVALID_STATE: rollback already % for this batch',
      v_batch.rollback_status USING ERRCODE = '22023';
  END IF;

  v_display := v_label || ' — ' || v_note;

  UPDATE public.plantilla_import_batches
     SET rollback_status       = 'requested',
         rollback_requested_by = v_uid,
         rollback_requested_at = now(),
         rollback_reason_code  = v_code,
         rollback_reason_note  = v_note,
         rollback_reason       = v_display,
         rollback_approved_by  = NULL,
         rollback_approved_at  = NULL,
         rollback_completed_at = NULL,
         rollback_error_detail = NULL,
         updated_at            = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object(
      'event',       'rollback_requested',
      'reason_code', v_code,
      'reason_note', v_note
    ));

  v_notified := public._notify_plantilla_import_role(
    ARRAY['Super Admin','superAdmin','super_admin'],
    'Super Admin',
    'Import Plantilla Rollback Requested',
    'A rollback request was submitted for an approved Import Plantilla batch and requires Super Admin review.',
    'PLANTILLA_IMPORT_ROLLBACK_REQUESTED',
    '/plantilla_import/batch/' || p_batch_id::text || '/rollback',
    p_batch_id::text
  );

  RETURN jsonb_build_object(
    'batch_id',             p_batch_id,
    'rollback_status',      'requested',
    'rollback_reason_code', v_code,
    'rollback_reason_note', v_note,
    'notifications_sent',   v_notified
  );
END$func$;

REVOKE ALL ON FUNCTION public.request_plantilla_import_rollback(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_plantilla_import_rollback(uuid,text,text) TO authenticated;

COMMENT ON FUNCTION public.request_plantilla_import_rollback(uuid,text,text) IS
  'Request rollback of an APPROVED Import Plantilla batch (OHM2026_1146). '
  'Reason dropdown code + required note (≥ 10 chars). Notifies Super Admin. '
  'RBAC: Encoder / Head Admin / Super Admin (the actual execution requires SA).';


-- ============================================================
-- §5  approve_plantilla_import_rollback — SA-only executor wrapper
-- ============================================================
-- Wraps the existing rollback_plantilla_import_batch executor (OHM2026_0063):
--   - Requires rollback_status = 'requested'.
--   - Calls the executor (which performs all soft-delete / restore work,
--     sets batch.status to rolled_back/rollback_failed and writes its own
--     audit row).
--   - On success: stamps rollback_approved_*/rollback_completed_at,
--     rollback_status='completed', notifies the requester.
--   - On failure: stamps rollback_status='failed' + error detail,
--     notifies requester + Super Admin, re-raises.
--
-- RBAC: Super Admin only. The wrapper enforces this explicitly because
-- the legacy executor is HA/SA-gated.

CREATE OR REPLACE FUNCTION public.approve_plantilla_import_rollback(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid            uuid := auth.uid();
  v_batch          public.plantilla_import_batches%ROWTYPE;
  v_requester_auth uuid;
  v_exec_reason    text;
  v_exec_result    jsonb;
  v_exec_status    text;
  v_plantilla_restored int;
  v_plantilla_archived int;
  v_stores_restored    int;
  v_stores_deactivated int;
  v_allocations_restored    int;
  v_allocations_deactivated int;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin required to approve/execute rollback'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.plantilla_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;
  IF v_batch.rollback_status IS DISTINCT FROM 'requested' THEN
    RAISE EXCEPTION 'INVALID_STATE: rollback must be in "requested" state (current=%)',
      COALESCE(v_batch.rollback_status, 'none') USING ERRCODE = '22023';
  END IF;

  v_requester_auth := v_batch.rollback_requested_by;
  v_exec_reason    := COALESCE(v_batch.rollback_reason,
                               v_batch.rollback_reason_note,
                               v_batch.rollback_reason_code);

  -- Call the legacy single-shot executor. It performs all entity DML,
  -- writes its own audit row, and updates batch.status. It also catches
  -- internal failures and returns a JSON object with status='rollback_failed'.
  v_exec_result := public.rollback_plantilla_import_batch(p_batch_id, v_exec_reason);
  v_exec_status := v_exec_result ->> 'status';

  IF v_exec_status = 'rolled_back' THEN
    v_plantilla_restored      := COALESCE((v_exec_result->>'plantilla_restored')::int, 0);
    v_plantilla_archived      := COALESCE((v_exec_result->>'plantilla_archived')::int, 0);
    v_stores_restored         := COALESCE((v_exec_result->>'stores_restored')::int, 0);
    v_stores_deactivated      := COALESCE((v_exec_result->>'stores_deactivated')::int, 0);
    v_allocations_restored    := COALESCE((v_exec_result->>'allocations_restored')::int, 0);
    v_allocations_deactivated := COALESCE((v_exec_result->>'allocations_deactivated')::int, 0);

    UPDATE public.plantilla_import_batches
       SET rollback_status       = 'completed',
           rollback_approved_by  = v_uid,
           rollback_approved_at  = now(),
           rollback_completed_at = now(),
           rollback_error_detail = NULL,
           updated_at            = now()
     WHERE id = p_batch_id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'plantilla_import_batches', 'UPDATE', p_batch_id,
      jsonb_build_object(
        'event',                'rollback_completed',
        'plantilla_restored',   v_plantilla_restored,
        'plantilla_archived',   v_plantilla_archived,
        'stores_restored',      v_stores_restored,
        'stores_deactivated',   v_stores_deactivated,
        'allocations_restored', v_allocations_restored,
        'allocations_deactivated', v_allocations_deactivated
      ));

    PERFORM public._notify_plantilla_import_user(
      v_requester_auth,
      'Head Admin',
      'Import Plantilla Rollback Completed',
      format('Rollback executed: %s plantilla restored, %s archived; %s stores restored.',
             v_plantilla_restored, v_plantilla_archived, v_stores_restored),
      'PLANTILLA_IMPORT_ROLLBACK_COMPLETED',
      '/plantilla_import/batch/' || p_batch_id::text || '/rollback',
      p_batch_id::text
    );

    RETURN jsonb_build_object(
      'batch_id',                p_batch_id,
      'rollback_status',         'completed',
      'plantilla_restored',      v_plantilla_restored,
      'plantilla_archived',      v_plantilla_archived,
      'stores_restored',         v_stores_restored,
      'stores_deactivated',      v_stores_deactivated,
      'allocations_restored',    v_allocations_restored,
      'allocations_deactivated', v_allocations_deactivated
    );
  ELSE
    -- Executor handled its own EXCEPTION block and returned a failure body.
    UPDATE public.plantilla_import_batches
       SET rollback_status       = 'failed',
           rollback_approved_by  = v_uid,
           rollback_approved_at  = now(),
           rollback_error_detail = COALESCE(v_exec_result->>'error', rollback_error_detail),
           updated_at            = now()
     WHERE id = p_batch_id;

    PERFORM public._notify_plantilla_import_user(
      v_requester_auth,
      'Head Admin',
      'Import Plantilla Rollback Failed',
      'Rollback execution failed: ' || COALESCE(v_exec_result->>'error', 'unknown error'),
      'PLANTILLA_IMPORT_ROLLBACK_FAILED',
      '/plantilla_import/batch/' || p_batch_id::text || '/rollback',
      p_batch_id::text
    );
    PERFORM public._notify_plantilla_import_role(
      ARRAY['Super Admin','superAdmin','super_admin'],
      'Super Admin',
      'Import Plantilla Rollback Failed',
      'Rollback execution failed: ' || COALESCE(v_exec_result->>'error', 'unknown error'),
      'PLANTILLA_IMPORT_ROLLBACK_FAILED',
      '/plantilla_import/batch/' || p_batch_id::text || '/rollback',
      p_batch_id::text
    );

    RAISE EXCEPTION 'ROLLBACK_FAILED: %', COALESCE(v_exec_result->>'error', 'unknown error')
      USING ERRCODE = '22000';
  END IF;
END$func$;

REVOKE ALL ON FUNCTION public.approve_plantilla_import_rollback(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_plantilla_import_rollback(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_plantilla_import_rollback(uuid) IS
  'Approve & execute rollback for a requested Import Plantilla batch (OHM2026_1146). '
  'Wraps the legacy rollback_plantilla_import_batch executor. RBAC: Super Admin only.';


-- ============================================================
-- §6  Trigger: stamp approval_due_at + notify approver on upload
-- ============================================================
-- Mirrors the Import Vacancy approach. On transition into pending_approval:
--   - stamp approval_due_at = created_at + 3 days
--   - fan out one notification based on uploaded_role:
--       encoder    → all Head Admins
--       headAdmin  → all Super Admins
--       superAdmin → none
-- Idempotent via approval_notified_at.

CREATE OR REPLACE FUNCTION public._trg_plantilla_import_notify_approver()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_role text;
BEGIN
  IF NEW.status <> 'pending_approval'
     OR COALESCE(OLD.status,'') = 'pending_approval' THEN
    RETURN NEW;
  END IF;

  NEW.approval_due_at       := COALESCE(NEW.approval_due_at, NEW.created_at + INTERVAL '3 days');
  NEW.approval_escalated_at := NULL;

  IF NEW.approval_notified_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_role := lower(replace(COALESCE(NEW.uploaded_role,''), ' ', ''));

  IF v_role IN ('encoder') THEN
    PERFORM public._notify_plantilla_import_role(
      ARRAY['Head Admin','headAdmin','head_admin'],
      'Head Admin',
      'Import Plantilla Batch Awaiting Approval',
      'A new Import Plantilla batch was uploaded by Encoder and is awaiting Head Admin approval.',
      'PLANTILLA_IMPORT_PENDING_APPROVAL',
      '/plantilla_import/batch/' || NEW.id::text,
      NEW.id::text
    );
    NEW.approval_notified_at := now();
  ELSIF v_role IN ('headadmin','head_admin') THEN
    PERFORM public._notify_plantilla_import_role(
      ARRAY['Super Admin','superAdmin','super_admin'],
      'Super Admin',
      'Import Plantilla Batch Awaiting Approval',
      'A new Import Plantilla batch was uploaded by Head Admin and is awaiting Super Admin approval.',
      'PLANTILLA_IMPORT_PENDING_APPROVAL',
      '/plantilla_import/batch/' || NEW.id::text,
      NEW.id::text
    );
    NEW.approval_notified_at := now();
  ELSE
    NEW.approval_notified_at := now();
  END IF;

  RETURN NEW;
END$func$;

DROP TRIGGER IF EXISTS trg_plantilla_import_notify_approver
  ON public.plantilla_import_batches;

CREATE TRIGGER trg_plantilla_import_notify_approver
  BEFORE UPDATE OF status ON public.plantilla_import_batches
  FOR EACH ROW
  WHEN (NEW.status = 'pending_approval' AND OLD.status IS DISTINCT FROM 'pending_approval')
  EXECUTE FUNCTION public._trg_plantilla_import_notify_approver();

COMMENT ON FUNCTION public._trg_plantilla_import_notify_approver() IS
  'Stamps approval_due_at and emits the upload-time approver notification '
  'based on uploaded_role (encoder→HA, HA→SA, SA→none). OHM2026_1146.';


-- ============================================================
-- §7  escalate_pending_plantilla_import_approvals — SA escalation RPC
-- ============================================================
-- Idempotent. Finds pending_approval batches whose approval_due_at < now()
-- AND approval_escalated_at IS NULL. Sends one SA fan-out per batch and
-- stamps approval_escalated_at. RBAC: superAdmin OR service_role.

CREATE OR REPLACE FUNCTION public.escalate_pending_plantilla_import_approvals()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_role_label text := current_setting('request.jwt.claims', true)::jsonb ->> 'role';
  v_uid        uuid := auth.uid();
  v_b          record;
  v_escalated  int := 0;
  v_sent       int := 0;
BEGIN
  IF NOT (public.is_super_admin() OR COALESCE(v_role_label,'') = 'service_role') THEN
    RAISE EXCEPTION 'forbidden: Super Admin or service_role required'
      USING ERRCODE = '42501';
  END IF;

  FOR v_b IN
    SELECT id
      FROM public.plantilla_import_batches
     WHERE status = 'pending_approval'
       AND approval_due_at IS NOT NULL
       AND approval_due_at < now()
       AND approval_escalated_at IS NULL
     FOR UPDATE SKIP LOCKED
  LOOP
    v_sent := v_sent + public._notify_plantilla_import_role(
      ARRAY['Super Admin','superAdmin','super_admin'],
      'Super Admin',
      'Import Plantilla Batch Overdue',
      'An Import Plantilla batch has been pending approval for more than 3 days and requires Super Admin review.',
      'PLANTILLA_IMPORT_APPROVAL_OVERDUE',
      '/plantilla_import/batch/' || v_b.id::text,
      v_b.id::text
    );

    UPDATE public.plantilla_import_batches
       SET approval_escalated_at = now(),
           updated_at = now()
     WHERE id = v_b.id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'plantilla_import_batches', 'UPDATE', v_b.id,
      jsonb_build_object('event','approval_escalated_super_admin'));

    v_escalated := v_escalated + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'batches_escalated',  v_escalated,
    'notifications_sent', v_sent
  );
END$func$;

REVOKE ALL ON FUNCTION public.escalate_pending_plantilla_import_approvals()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_pending_plantilla_import_approvals()
  TO authenticated, service_role;

COMMENT ON FUNCTION public.escalate_pending_plantilla_import_approvals() IS
  'Idempotent SA escalation for Import Plantilla batches pending > 3 days. '
  'Stamps approval_escalated_at to avoid duplicate sends. OHM2026_1146.';


-- ============================================================
-- §8  Refresh get_plantilla_import_batches listing RPC
-- ============================================================
-- Appends the new reason / rollback / escalation columns. All existing
-- columns are preserved in their original order for client decoders.

DROP FUNCTION IF EXISTS public.get_plantilla_import_batches(text);

CREATE OR REPLACE FUNCTION public.get_plantilla_import_batches(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                         uuid,
  file_name                  text,
  uploaded_by                uuid,
  uploader_name              text,
  uploaded_by_name           text,
  uploaded_role              text,
  selected_group_id          uuid,
  selected_account_id        uuid,
  group_name                 text,
  account_name               text,
  status                     text,
  total_rows                 integer,
  valid_rows                 integer,
  flagged_rows               integer,
  skipped_rows               integer,
  blocked_rows               integer,
  roving_detected            integer,
  new_stores_count           integer,
  existing_stores_count      integer,
  existing_employees_count   integer,
  cross_account_conflicts    integer,
  cross_group_conflicts      integer,
  over_20_store_warnings     integer,
  missing_from_upload_count  integer,
  error_summary              jsonb,
  commit_error_detail        text,
  approved_by                uuid,
  approved_at                timestamptz,
  committed_stores           integer,
  committed_employees        integer,
  rollback_ready             boolean,
  rejected_by                uuid,
  rejected_at                timestamptz,
  rejection_reason           text,
  rejection_reason_code      text,
  rejection_reason_note      text,
  created_at                 timestamptz,
  updated_at                 timestamptz,
  approval_due_at            timestamptz,
  approval_escalated_at      timestamptz,
  approval_notified_at       timestamptz,
  rollback_status            text,
  rollback_reason            text,
  rollback_reason_code       text,
  rollback_reason_note       text,
  rollback_requested_by      uuid,
  rollback_requested_by_name text,
  rollback_requested_at      timestamptz,
  rollback_approved_by       uuid,
  rollback_approved_by_name  text,
  rollback_approved_at       timestamptz,
  rollback_completed_at      timestamptz,
  rollback_error_detail      text,
  rolled_back_by             uuid,
  rolled_back_at             timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT
    b.id,
    b.file_name,
    b.uploaded_by,
    up.full_name AS uploader_name,
    up.full_name AS uploaded_by_name,
    b.uploaded_role,
    b.selected_group_id,
    b.selected_account_id,
    g.group_name,
    a.account_name,
    b.status,
    b.total_rows,
    b.valid_rows,
    b.flagged_rows,
    b.skipped_rows,
    b.blocked_rows,
    b.roving_detected,
    b.new_stores_count,
    b.existing_stores_count,
    b.existing_employees_count,
    b.cross_account_conflicts,
    b.cross_group_conflicts,
    b.over_20_store_warnings,
    b.missing_from_upload_count,
    b.error_summary,
    b.commit_error_detail,
    b.approved_by,
    b.approved_at,
    b.committed_stores,
    b.committed_employees,
    b.rollback_ready,
    b.rejected_by,
    b.rejected_at,
    b.rejection_reason,
    b.rejection_reason_code,
    b.rejection_reason_note,
    b.created_at,
    b.updated_at,
    b.approval_due_at,
    b.approval_escalated_at,
    b.approval_notified_at,
    b.rollback_status,
    b.rollback_reason,
    b.rollback_reason_code,
    b.rollback_reason_note,
    b.rollback_requested_by,
    COALESCE(rrp.full_name, rrp.email, b.rollback_requested_by::text),
    b.rollback_requested_at,
    b.rollback_approved_by,
    COALESCE(rap.full_name, rap.email, b.rollback_approved_by::text),
    b.rollback_approved_at,
    b.rollback_completed_at,
    b.rollback_error_detail,
    b.rolled_back_by,
    b.rolled_back_at
  FROM public.plantilla_import_batches b
  LEFT JOIN public.groups        g   ON g.id = b.selected_group_id
  LEFT JOIN public.accounts      a   ON a.id = b.selected_account_id
  LEFT JOIN LATERAL (
    SELECT up.full_name
      FROM public.users_profile up
     WHERE up.auth_user_id = b.uploaded_by OR up.id = b.uploaded_by
     ORDER BY CASE WHEN up.auth_user_id = b.uploaded_by THEN 0 ELSE 1 END
     LIMIT 1
  ) up ON true
  LEFT JOIN public.users_profile rrp ON rrp.auth_user_id = b.rollback_requested_by
  LEFT JOIN public.users_profile rap ON rap.auth_user_id = b.rollback_approved_by
  WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
    AND (p_status IS NULL OR b.status = p_status)
  ORDER BY b.created_at DESC;
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_batches(text) TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_import_batches(text) IS
  'Import Plantilla batches listing — adds reason codes/notes, approval '
  'escalation timestamps, and two-step rollback fields (OHM2026_1146).';


-- ============================================================
-- §9  get_plantilla_import_rollback_history per-batch RPC
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_plantilla_import_rollback_history(
  p_batch_id uuid
)
RETURNS TABLE (
  batch_id                   uuid,
  rollback_status            text,
  rollback_reason            text,
  rollback_reason_code       text,
  rollback_reason_note       text,
  rollback_requested_by      uuid,
  rollback_requested_by_name text,
  rollback_requested_at      timestamptz,
  rollback_approved_by       uuid,
  rollback_approved_by_name  text,
  rollback_approved_at       timestamptz,
  rollback_completed_at      timestamptz,
  rollback_error_detail      text,
  rolled_back_by             uuid,
  rolled_back_at             timestamptz
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
    b.rollback_reason_code,
    b.rollback_reason_note,
    b.rollback_requested_by,
    COALESCE(rp.full_name, rp.email, b.rollback_requested_by::text),
    b.rollback_requested_at,
    b.rollback_approved_by,
    COALESCE(ap.full_name, ap.email, b.rollback_approved_by::text),
    b.rollback_approved_at,
    b.rollback_completed_at,
    b.rollback_error_detail,
    b.rolled_back_by,
    b.rolled_back_at
  FROM public.plantilla_import_batches b
  LEFT JOIN public.users_profile rp ON rp.auth_user_id = b.rollback_requested_by
  LEFT JOIN public.users_profile ap ON ap.auth_user_id = b.rollback_approved_by
  WHERE b.id = p_batch_id
    AND (public.i_have_full_access() OR b.uploaded_by = auth.uid());
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_rollback_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_rollback_history(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_import_rollback_history(uuid) IS
  'Per-batch rollback timeline with reason code/note + actor display names (OHM2026_1146).';
