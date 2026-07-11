-- ============================================================
-- OHM2026_1140 — Import Vacancy reason dropdowns + notification & escalation
-- Migration:  20260730000004_import_vacancy_reason_dropdowns_and_notifications.sql
-- Depends on: 20260730000003_add_import_vacancy_rollback.sql
-- ============================================================
-- Purpose
--   1. Reject Import Vacancy → dropdown reason + optional remarks
--      (remarks required when reason = 'other'). Stores
--      rejection_reason_code + rejection_reason_note; preserves
--      rejection_reason (composed for display backward-compat).
--   2. Rollback request → dropdown reason + required remarks ≥ 10 chars.
--      Stores rollback_reason_code + rollback_reason_note; preserves
--      rollback_reason.
--   3. Import approval notifications:
--        Encoder upload  → Head Admin (one per HA)
--        HA upload       → Super Admin (one per SA)
--        SA upload       → none
--      Deep-link: /vacancy_import/batch/<batch_id>
--   4. Approval escalation after 3 days pending approval →
--      Super Admin notified ONCE per batch (idempotent via
--      approval_escalated_at).
--   5. Rollback notifications:
--        request   → Super Admin
--        completed → original requester
--        failed    → original requester + Super Admin
--
-- Locked rules
--   - No applied migration is modified.
--   - audit_logs uses 'UPDATE' only (no new audit_action labels).
--   - Notifications use existing public.notifications table.
--     recipient_user_id = users_profile.auth_user_id; rows with no
--     linked auth user are silently skipped (consistent with
--     OHM2026_2064 deactivation notification fix).
--   - Idempotent escalation: approval_escalated_at IS NULL check.
--   - Existing rejection_reason / rollback_reason columns are preserved
--     for display compatibility (composed = "<Label> — <note>").
--
-- Sections
--   §1  Reason columns + escalation columns
--   §2  Notification helpers (HA recipients, SA recipients, requester)
--   §3  reject_vacancy_import (drop old; add reason_code + reason_note)
--   §4  request_vacancy_import_rollback (drop old; add reason_code + note)
--   §5  approve_vacancy_import_rollback — emit completion/failure notifs
--   §6  submit_vacancy_import — set approval_due_at + notify approver
--   §7  escalate_pending_vacancy_import_approvals — SA escalation RPC
--   §8  Refresh get_vacancy_import_batches to expose new fields
-- ============================================================


-- ============================================================
-- §1  Reason columns + escalation metadata
-- ============================================================

ALTER TABLE public.vacancy_import_batches
  ADD COLUMN IF NOT EXISTS rejection_reason_code text,
  ADD COLUMN IF NOT EXISTS rejection_reason_note text,
  ADD COLUMN IF NOT EXISTS rollback_reason_code  text,
  ADD COLUMN IF NOT EXISTS rollback_reason_note  text,
  ADD COLUMN IF NOT EXISTS approval_due_at       timestamptz,
  ADD COLUMN IF NOT EXISTS approval_escalated_at timestamptz,
  ADD COLUMN IF NOT EXISTS approval_notified_at  timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vib_rejection_reason_code_check'
  ) THEN
    ALTER TABLE public.vacancy_import_batches
      ADD CONSTRAINT vib_rejection_reason_code_check CHECK (
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
    SELECT 1 FROM pg_constraint WHERE conname = 'vib_rollback_reason_code_check'
  ) THEN
    ALTER TABLE public.vacancy_import_batches
      ADD CONSTRAINT vib_rollback_reason_code_check CHECK (
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
END$$;

COMMENT ON COLUMN public.vacancy_import_batches.rejection_reason_code IS
  'Canonical reject reason code (OHM2026_1140).';
COMMENT ON COLUMN public.vacancy_import_batches.rejection_reason_note IS
  'Optional remarks; REQUIRED when rejection_reason_code = ''other'' (OHM2026_1140).';
COMMENT ON COLUMN public.vacancy_import_batches.rollback_reason_code IS
  'Canonical rollback reason code (OHM2026_1140).';
COMMENT ON COLUMN public.vacancy_import_batches.rollback_reason_note IS
  'Required remarks for rollback (≥ 10 chars) (OHM2026_1140).';
COMMENT ON COLUMN public.vacancy_import_batches.approval_due_at IS
  'When this batch becomes overdue (created_at + 3 days). OHM2026_1140.';
COMMENT ON COLUMN public.vacancy_import_batches.approval_escalated_at IS
  'When the SA escalation notification was sent (idempotency guard). OHM2026_1140.';
COMMENT ON COLUMN public.vacancy_import_batches.approval_notified_at IS
  'When the upload-time approver notification was emitted. OHM2026_1140.';


-- ============================================================
-- §2  Notification helper — internal use only
-- ============================================================
-- Inserts one notification per active recipient role; skips profiles
-- with no linked auth_user_id (mirrors OHM2026_2064 deactivation fix).

CREATE OR REPLACE FUNCTION public._notify_vacancy_import_role(
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
      'vacancy_import', p_event_type,
      p_title, p_message,
      p_deep_link, 'vacancy_import_batch', p_reference_id
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END$func$;

REVOKE ALL ON FUNCTION public._notify_vacancy_import_role(text[],text,text,text,text,text,text)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._notify_vacancy_import_role IS
  'Internal Import Vacancy notification fan-out per role alias set (OHM2026_1140). '
  'Skips users with NULL auth_user_id.';


-- Convenience wrappers (kept inline as anonymous helpers via DO; instead
-- expose two thin SECURITY DEFINER helpers used by RPCs below).

CREATE OR REPLACE FUNCTION public._notify_vacancy_import_user(
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
    'vacancy_import', p_event_type,
    p_title, p_message,
    p_deep_link, 'vacancy_import_batch', p_reference_id
  );
  RETURN true;
END$func$;

REVOKE ALL ON FUNCTION public._notify_vacancy_import_user(uuid,text,text,text,text,text,text)
  FROM PUBLIC, anon, authenticated;


-- ============================================================
-- §3  reject_vacancy_import — dropdown reason + optional note
-- ============================================================
-- Drops the legacy (uuid, text) signature and replaces it with
-- (uuid, text, text). reason_code is required; note is required when
-- reason_code = 'other'. rejection_reason is composed for display
-- backward-compat ("<Label> — <note>").

DROP FUNCTION IF EXISTS public.reject_vacancy_import(uuid, text);

CREATE OR REPLACE FUNCTION public.reject_vacancy_import(
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
  v_batch   public.vacancy_import_batches%ROWTYPE;
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
    FROM public.vacancy_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed','draft_uploaded') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status
      USING ERRCODE = '22023';
  END IF;

  v_display := CASE WHEN v_note IS NULL THEN v_label
                    ELSE v_label || ' — ' || v_note END;

  UPDATE public.vacancy_import_batches
     SET status                = 'rejected',
         rejected_by           = v_uid,
         rejected_at           = now(),
         rejection_reason_code = v_code,
         rejection_reason_note = v_note,
         rejection_reason      = v_display,
         updated_at            = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object(
      'event',       'rejected',
      'reason_code', v_code,
      'reason_note', v_note
    ));

  RETURN jsonb_build_object(
    'batch_id',             p_batch_id,
    'status',               'rejected',
    'rejection_reason_code', v_code,
    'rejection_reason_note', v_note
  );
END$func$;

REVOKE ALL ON FUNCTION public.reject_vacancy_import(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_vacancy_import(uuid,text,text) TO authenticated;

COMMENT ON FUNCTION public.reject_vacancy_import(uuid,text,text) IS
  'Reject Import Vacancy batch with required reason code + optional note '
  '(remarks required for "other"). Audit uses UPDATE. RBAC: HA/SA. OHM2026_1140.';


-- ============================================================
-- §4  request_vacancy_import_rollback — dropdown reason + required note
-- ============================================================
-- Drops the legacy (uuid, text) signature and replaces it with
-- (uuid, text, text). reason_code is required; note is required and
-- must be ≥ 10 characters. rollback_reason preserved for display.

DROP FUNCTION IF EXISTS public.request_vacancy_import_rollback(uuid, text);

CREATE OR REPLACE FUNCTION public.request_vacancy_import_rollback(
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
  v_uid     uuid := auth.uid();
  v_batch   public.vacancy_import_batches%ROWTYPE;
  v_code    text := COALESCE(lower(trim(p_reason_code)), '');
  v_note    text := COALESCE(trim(p_reason_note), '');
  v_label   text;
  v_display text;
  v_notified int;
BEGIN
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required to request rollback'
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
    FROM public.vacancy_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;
  IF v_batch.rollback_status IN ('requested','approved','completed') THEN
    RAISE EXCEPTION 'INVALID_STATE: rollback already % for this batch',
      v_batch.rollback_status USING ERRCODE = '22023';
  END IF;

  v_display := v_label || ' — ' || v_note;

  UPDATE public.vacancy_import_batches
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
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object(
      'event',       'rollback_requested',
      'reason_code', v_code,
      'reason_note', v_note
    ));

  -- Notify Super Admin (rollback always requires SA approval)
  v_notified := public._notify_vacancy_import_role(
    ARRAY['Super Admin','superAdmin','super_admin'],
    'Super Admin',
    'Import Vacancy Rollback Requested',
    'A rollback request was submitted for an approved Import Vacancy batch and requires Super Admin review.',
    'VACANCY_IMPORT_ROLLBACK_REQUESTED',
    '/vacancy_import/batch/' || p_batch_id::text || '/rollback',
    p_batch_id::text
  );

  RETURN jsonb_build_object(
    'batch_id',            p_batch_id,
    'rollback_status',     'requested',
    'rollback_reason_code', v_code,
    'rollback_reason_note', v_note,
    'notifications_sent',  v_notified
  );
END$func$;

REVOKE ALL ON FUNCTION public.request_vacancy_import_rollback(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_vacancy_import_rollback(uuid,text,text) TO authenticated;

COMMENT ON FUNCTION public.request_vacancy_import_rollback(uuid,text,text) IS
  'Request rollback with dropdown reason code + required note (≥ 10 chars). '
  'Notifies Super Admin. Audit uses UPDATE. RBAC: HA/SA. OHM2026_1140.';


-- ============================================================
-- §5  approve_vacancy_import_rollback — emit completion/failure notifs
-- ============================================================
-- Keeps SA-only RBAC; same soft-delete behaviour; adds:
--   completion → notify original requester
--   failure    → notify original requester + Super Admin

CREATE OR REPLACE FUNCTION public.approve_vacancy_import_rollback(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid          uuid := auth.uid();
  v_batch        public.vacancy_import_batches%ROWTYPE;
  v_vac_count    int  := 0;
  v_app_count    int  := 0;
  v_requester_auth uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin required to approve/execute rollback'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_batch
    FROM public.vacancy_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;
  IF v_batch.rollback_status IS DISTINCT FROM 'requested' THEN
    RAISE EXCEPTION 'INVALID_STATE: rollback must be in "requested" state (current=%)',
      COALESCE(v_batch.rollback_status, 'none') USING ERRCODE = '22023';
  END IF;

  -- Requester's auth_user_id (may be NULL if linkage missing).
  -- rollback_requested_by is already auth.uid() per §4 / migration 3.
  v_requester_auth := v_batch.rollback_requested_by;

  -- Archive applicants seeded by this batch
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

  -- Soft-delete vacancies created by this batch
  WITH updated_vacs AS (
    UPDATE public.vacancies v
       SET deleted_at = now(),
           updated_at = now()
     WHERE v.source_vacancy_import_batch_id = p_batch_id
       AND v.deleted_at IS NULL
    RETURNING v.id
  )
  SELECT count(*) INTO v_vac_count FROM updated_vacs;

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

  -- Notify the original rollback requester (silent skip if no auth link)
  PERFORM public._notify_vacancy_import_user(
    v_requester_auth,
    'Head Admin',
    'Import Vacancy Rollback Completed',
    format('Rollback executed: %s vacancies soft-deleted, %s applicants archived.',
           v_vac_count, v_app_count),
    'VACANCY_IMPORT_ROLLBACK_COMPLETED',
    '/vacancy_import/batch/' || p_batch_id::text || '/rollback',
    p_batch_id::text
  );

  RETURN jsonb_build_object(
    'batch_id',         p_batch_id,
    'rollback_status',  'completed',
    'vacancies_rolled_back',  v_vac_count,
    'applicants_rolled_back', v_app_count
  );
EXCEPTION WHEN others THEN
  UPDATE public.vacancy_import_batches
     SET rollback_status       = 'failed',
         rollback_error_detail = SQLERRM,
         updated_at            = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('event','rollback_failed','error', SQLERRM));

  -- Notify requester + Super Admins of failure
  PERFORM public._notify_vacancy_import_user(
    v_requester_auth,
    'Head Admin',
    'Import Vacancy Rollback Failed',
    'Rollback execution failed: ' || SQLERRM,
    'VACANCY_IMPORT_ROLLBACK_FAILED',
    '/vacancy_import/batch/' || p_batch_id::text || '/rollback',
    p_batch_id::text
  );
  PERFORM public._notify_vacancy_import_role(
    ARRAY['Super Admin','superAdmin','super_admin'],
    'Super Admin',
    'Import Vacancy Rollback Failed',
    'Rollback execution failed: ' || SQLERRM,
    'VACANCY_IMPORT_ROLLBACK_FAILED',
    '/vacancy_import/batch/' || p_batch_id::text || '/rollback',
    p_batch_id::text
  );

  RAISE EXCEPTION 'ROLLBACK_FAILED: %', SQLERRM USING ERRCODE = '22000';
END$func$;

REVOKE ALL ON FUNCTION public.approve_vacancy_import_rollback(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_vacancy_import_rollback(uuid) TO authenticated;

COMMENT ON FUNCTION public.approve_vacancy_import_rollback(uuid) IS
  'Execute rollback (SA only). On completion notifies the original requester; '
  'on failure notifies requester + Super Admin. OHM2026_1140.';


-- ============================================================
-- §6  submit_vacancy_import — set approval_due_at + notify approver
-- ============================================================
-- Wraps the existing submit RPC behaviour by appending a post-pass:
--   - When the resulting batch status is 'pending_approval',
--     stamp approval_due_at = created_at + 3 days.
--   - Send the upload-time approver notification based on the
--     uploader's role:
--         encoder    → all Head Admins
--         headAdmin  → all Super Admins
--         superAdmin → none
--   - approval_notified_at marks that the notification was sent
--     (avoid re-sending if submit is somehow retried for the
--      same batch id, although submit creates a new batch each call).
--
-- Implementation: AFTER UPDATE trigger on vacancy_import_batches that
-- fires on the transition into pending_approval (no rewrite of the
-- 380-line submit RPC). This is the minimal surface change.

CREATE OR REPLACE FUNCTION public._trg_vacancy_import_notify_approver()
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

  -- Stamp approval_due_at and clear stale escalation marker for fresh
  -- transitions into pending_approval.
  NEW.approval_due_at       := COALESCE(NEW.approval_due_at, NEW.created_at + INTERVAL '3 days');
  NEW.approval_escalated_at := NULL;

  -- Idempotency: only emit notifications once per batch.
  IF NEW.approval_notified_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_role := lower(replace(COALESCE(NEW.uploaded_role,''), ' ', ''));

  IF v_role IN ('encoder') THEN
    PERFORM public._notify_vacancy_import_role(
      ARRAY['Head Admin','headAdmin','head_admin'],
      'Head Admin',
      'Import Vacancy Batch Awaiting Approval',
      'A new Import Vacancy batch was uploaded by Encoder and is awaiting Head Admin approval.',
      'VACANCY_IMPORT_PENDING_APPROVAL',
      '/vacancy_import/batch/' || NEW.id::text,
      NEW.id::text
    );
    NEW.approval_notified_at := now();
  ELSIF v_role IN ('headadmin','head_admin') THEN
    PERFORM public._notify_vacancy_import_role(
      ARRAY['Super Admin','superAdmin','super_admin'],
      'Super Admin',
      'Import Vacancy Batch Awaiting Approval',
      'A new Import Vacancy batch was uploaded by Head Admin and is awaiting Super Admin approval.',
      'VACANCY_IMPORT_PENDING_APPROVAL',
      '/vacancy_import/batch/' || NEW.id::text,
      NEW.id::text
    );
    NEW.approval_notified_at := now();
  ELSE
    -- superadmin or unknown role → no immediate approval notification
    NEW.approval_notified_at := now();
  END IF;

  RETURN NEW;
END$func$;

DROP TRIGGER IF EXISTS trg_vacancy_import_notify_approver
  ON public.vacancy_import_batches;

CREATE TRIGGER trg_vacancy_import_notify_approver
  BEFORE UPDATE OF status ON public.vacancy_import_batches
  FOR EACH ROW
  WHEN (NEW.status = 'pending_approval' AND OLD.status IS DISTINCT FROM 'pending_approval')
  EXECUTE FUNCTION public._trg_vacancy_import_notify_approver();

COMMENT ON FUNCTION public._trg_vacancy_import_notify_approver() IS
  'Stamps approval_due_at and emits the upload-time approver notification '
  'based on uploaded_role (encoder→HA, HA→SA, SA→none). OHM2026_1140.';


-- ============================================================
-- §7  escalate_pending_vacancy_import_approvals — SA escalation RPC
-- ============================================================
-- Idempotent. Finds all batches in pending_approval whose
-- approval_due_at < now() AND approval_escalated_at IS NULL.
-- For each: emit one SA-fan-out notification + stamp
-- approval_escalated_at. Logs UPDATE audit row per escalated batch.
-- RBAC: superAdmin OR service_role. Safe to invoke repeatedly.

CREATE OR REPLACE FUNCTION public.escalate_pending_vacancy_import_approvals()
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
  -- Allow super admins OR Supabase service role (cron / edge functions).
  IF NOT (public.is_super_admin() OR COALESCE(v_role_label,'') = 'service_role') THEN
    RAISE EXCEPTION 'forbidden: Super Admin or service_role required'
      USING ERRCODE = '42501';
  END IF;

  FOR v_b IN
    SELECT id
      FROM public.vacancy_import_batches
     WHERE status = 'pending_approval'
       AND approval_due_at IS NOT NULL
       AND approval_due_at < now()
       AND approval_escalated_at IS NULL
     FOR UPDATE SKIP LOCKED
  LOOP
    v_sent := v_sent + public._notify_vacancy_import_role(
      ARRAY['Super Admin','superAdmin','super_admin'],
      'Super Admin',
      'Import Vacancy Batch Overdue',
      'An Import Vacancy batch has been pending approval for more than 3 days and requires Super Admin review.',
      'VACANCY_IMPORT_APPROVAL_OVERDUE',
      '/vacancy_import/batch/' || v_b.id::text,
      v_b.id::text
    );

    UPDATE public.vacancy_import_batches
       SET approval_escalated_at = now(),
           updated_at = now()
     WHERE id = v_b.id;

    INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
    VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', v_b.id,
      jsonb_build_object('event','approval_escalated_super_admin'));

    v_escalated := v_escalated + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'batches_escalated', v_escalated,
    'notifications_sent', v_sent
  );
END$func$;

REVOKE ALL ON FUNCTION public.escalate_pending_vacancy_import_approvals()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.escalate_pending_vacancy_import_approvals()
  TO authenticated, service_role;

COMMENT ON FUNCTION public.escalate_pending_vacancy_import_approvals() IS
  'Idempotent SA escalation for Import Vacancy batches pending > 3 days. '
  'Stamps approval_escalated_at to avoid duplicate sends. OHM2026_1140.';


-- ============================================================
-- §8  Refresh get_vacancy_import_batches to expose new fields
-- ============================================================
-- Adds rejection_reason_code/note, rollback_reason_code/note,
-- approval_due_at, approval_escalated_at, approval_notified_at.
-- All existing columns are preserved in the same order so client
-- decoders that rely on existing keys keep working.

DROP FUNCTION IF EXISTS public.get_vacancy_import_batches(text);

CREATE OR REPLACE FUNCTION public.get_vacancy_import_batches(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                         uuid,
  file_name                  text,
  status                     text,
  selected_group_id          uuid,
  selected_account_id        uuid,
  group_name                 text,
  account_name               text,
  uploaded_by                uuid,
  uploaded_role              text,
  uploaded_at                timestamptz,
  approved_by                uuid,
  approved_by_name           text,
  approved_at                timestamptz,
  rejected_by                uuid,
  rejected_by_name           text,
  rejected_at                timestamptz,
  rejection_reason           text,
  rejection_reason_code      text,
  rejection_reason_note      text,
  commit_error_detail        text,
  total_rows                 integer,
  valid_rows                 integer,
  flagged_rows               integer,
  skipped_rows               integer,
  blocked_rows               integer,
  open_count                 integer,
  pipeline_count             integer,
  duplicate_vcode_count      integer,
  existing_vcode_count       integer,
  context_mismatch_count     integer,
  committed_vacancies        integer,
  committed_applicants       integer,
  error_summary              jsonb,
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
  rollback_vacancies_count   integer,
  rollback_applicants_count  integer
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
    b.rejection_reason, b.rejection_reason_code, b.rejection_reason_note,
    b.commit_error_detail,
    b.total_rows, b.valid_rows, b.flagged_rows, b.skipped_rows, b.blocked_rows,
    b.open_count, b.pipeline_count, b.duplicate_vcode_count,
    b.existing_vcode_count, b.context_mismatch_count,
    b.committed_vacancies, b.committed_applicants, b.error_summary,
    b.approval_due_at, b.approval_escalated_at, b.approval_notified_at,
    b.rollback_status, b.rollback_reason,
    b.rollback_reason_code, b.rollback_reason_note,
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

COMMENT ON FUNCTION public.get_vacancy_import_batches(text) IS
  'Import Vacancy batches listing — includes reason codes/notes, approval '
  'escalation timestamps, and rollback reason codes (OHM2026_1140).';


-- Refresh rollback history RPC to surface reason code/note too.
DROP FUNCTION IF EXISTS public.get_vacancy_import_rollback_history(uuid);

CREATE OR REPLACE FUNCTION public.get_vacancy_import_rollback_history(
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
  rollback_vacancies_count   integer,
  rollback_applicants_count  integer
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

COMMENT ON FUNCTION public.get_vacancy_import_rollback_history(uuid) IS
  'Per-batch rollback timeline including reason code + note (OHM2026_1140).';


-- ============================================================
-- Validation queries (run after applying)
-- ============================================================
-- V1  Required columns exist
--   SELECT column_name FROM information_schema.columns
--    WHERE table_schema='public' AND table_name='vacancy_import_batches'
--      AND column_name IN ('rejection_reason_code','rejection_reason_note',
--          'rollback_reason_code','rollback_reason_note',
--          'approval_due_at','approval_escalated_at','approval_notified_at');
--
-- V2  RPC signatures
--   SELECT pg_get_function_identity_arguments(p.oid), p.proname
--     FROM pg_proc p WHERE p.proname IN
--       ('reject_vacancy_import','request_vacancy_import_rollback',
--        'approve_vacancy_import_rollback',
--        'escalate_pending_vacancy_import_approvals');
--
-- V3  Trigger present
--   SELECT tgname FROM pg_trigger WHERE tgname='trg_vacancy_import_notify_approver';
--
-- V4  Idempotent escalation
--   SELECT escalate_pending_vacancy_import_approvals();
--   -- expect batches_escalated drops to 0 on the 2nd call.
--
-- V5  Reject "Other" without remarks raises 22023:
--   SELECT reject_vacancy_import('<batch-uuid>'::uuid, 'other', NULL);
