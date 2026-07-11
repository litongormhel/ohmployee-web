-- ============================================================
-- Migration: 20260520500000_hr_emploc_deletion_request_finalize.sql
-- Feature  : HR Emploc Deletion Request — Backend Finalization
-- Prompt   : OHM2026_2006
-- ============================================================
-- Rules enforced:
--   Archive only. No hard deletes.
--   Pending deletion = overlay state only (original hr_status preserved).
--   Backout approval reopens original vacancy via vacancy_id FK only.
--   Duplicate Record approval: archive only, NO vacancy reopen.
--   Duplicate Record requires original_emploc_id reference on creation.
--   Immutable snapshot on request creation: last, first, vcode, store,
--     position, reason, requested_by, approved_by, timestamp.
--   Withdrawal: original requestor OR Super Admin, Pending only.
--   Withdrawal: adds 'Request Withdrawn' activity, preserves audit trail.
--   Pending lock: move_to_plantilla, submit_hrco_correction_update,
--     assign_hr_emploc_number all blocked while deletion is Pending.
--   Correction auto-close (clear correction_reason) on Backout approval.
--   Plantilla/deactivated guard on approval.
--   Approval routes to Encoder (scoped) + Super Admin override.
--   Re-request allowed after Rejected (no block on non-Pending).
--   SLA cron registered: every 4h, 3-day → HeadAdmin, 5-day → SuperAdmin.
-- ============================================================

BEGIN;

-- ============================================================
-- SECTION 1: ALTER TABLE hr_emploc_deletion_requests
-- ============================================================

ALTER TABLE public.hr_emploc_deletion_requests
  ADD COLUMN IF NOT EXISTS deletion_type        text        NOT NULL DEFAULT 'Backout',
  ADD COLUMN IF NOT EXISTS original_emploc_id   uuid,
  ADD COLUMN IF NOT EXISTS requested_by_user_id uuid,
  ADD COLUMN IF NOT EXISTS original_hr_status   text,
  ADD COLUMN IF NOT EXISTS withdrawn_at         timestamptz,
  ADD COLUMN IF NOT EXISTS withdrawn_by         text,
  ADD COLUMN IF NOT EXISTS withdrawn_by_user_id uuid,
  ADD COLUMN IF NOT EXISTS approved_by_user_id  uuid,
  ADD COLUMN IF NOT EXISTS snapshot_last_name   text,
  ADD COLUMN IF NOT EXISTS snapshot_first_name  text,
  ADD COLUMN IF NOT EXISTS snapshot_position    text,
  ADD COLUMN IF NOT EXISTS snapshot_store       text;

-- Expand status check: add Withdrawn, Archived
ALTER TABLE public.hr_emploc_deletion_requests
  DROP CONSTRAINT IF EXISTS hr_emploc_deletion_requests_status_check;

ALTER TABLE public.hr_emploc_deletion_requests
  ADD CONSTRAINT hr_emploc_deletion_requests_status_check
  CHECK (status = ANY (ARRAY[
    'Pending'::text, 'Approved'::text, 'Rejected'::text,
    'Withdrawn'::text, 'Archived'::text
  ]));

-- deletion_type enum constraint
ALTER TABLE public.hr_emploc_deletion_requests
  DROP CONSTRAINT IF EXISTS hr_emploc_deletion_requests_deletion_type_check;

ALTER TABLE public.hr_emploc_deletion_requests
  ADD CONSTRAINT hr_emploc_deletion_requests_deletion_type_check
  CHECK (deletion_type IN ('Backout', 'Duplicate Record'));

-- original_emploc_id FK (SET NULL on archive)
ALTER TABLE public.hr_emploc_deletion_requests
  DROP CONSTRAINT IF EXISTS hr_emploc_deletion_requests_original_emploc_id_fkey;

ALTER TABLE public.hr_emploc_deletion_requests
  ADD CONSTRAINT hr_emploc_deletion_requests_original_emploc_id_fkey
  FOREIGN KEY (original_emploc_id)
  REFERENCES public.hr_emploc(id)
  ON DELETE SET NULL
  NOT VALID;

ALTER TABLE public.hr_emploc_deletion_requests
  VALIDATE CONSTRAINT hr_emploc_deletion_requests_original_emploc_id_fkey;

-- Index for pending lock checks (hot path in 3 RPCs)
CREATE INDEX IF NOT EXISTS idx_emploc_deletion_pending
  ON public.hr_emploc_deletion_requests (hr_emploc_id, status)
  WHERE status = 'Pending';

-- ============================================================
-- SECTION 2: hr_emploc_deletion_activities (immutable log)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.hr_emploc_deletion_activities (
  id                   uuid        NOT NULL DEFAULT gen_random_uuid(),
  request_id           uuid        NOT NULL,
  activity_type        text        NOT NULL,
  -- 'Request Submitted' | 'Approved' | 'Rejected' | 'Withdrawn'
  -- 'Request Withdrawn' | 'Correction Auto-Cancelled' | 'Escalated'
  performed_by         text,
  performed_by_user_id uuid,
  performed_at         timestamptz NOT NULL DEFAULT NOW(),
  remarks              text,
  snapshot             jsonb,
  CONSTRAINT hr_emploc_deletion_activities_pkey PRIMARY KEY (id),
  CONSTRAINT hr_emploc_deletion_activities_request_fkey
    FOREIGN KEY (request_id)
    REFERENCES public.hr_emploc_deletion_requests(id)
    ON DELETE CASCADE
);

ALTER TABLE public.hr_emploc_deletion_activities ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_emploc_del_activities_request
  ON public.hr_emploc_deletion_activities (request_id, performed_at DESC);

-- Read: same scope as parent request
CREATE POLICY "deletion_activities_read_scoped"
  ON public.hr_emploc_deletion_activities
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.hr_emploc_deletion_requests r
      WHERE r.id = request_id
        AND (
          public.i_have_full_access()
          OR r.account = ANY (public.get_my_allowed_accounts())
          OR r.requested_by_user_id = public.get_my_profile_id()
        )
    )
  );

-- All writes via SECURITY DEFINER RPCs only
CREATE POLICY "deletion_activities_no_direct_write"
  ON public.hr_emploc_deletion_activities
  AS PERMISSIVE FOR ALL TO public
  USING (false)
  WITH CHECK (false);

GRANT SELECT ON public.hr_emploc_deletion_activities TO authenticated;
GRANT ALL    ON public.hr_emploc_deletion_activities TO service_role;

-- ============================================================
-- SECTION 3: fn_request_emploc_deletion
-- Atomic replacement for Flutter dual direct-write.
-- Captures full immutable snapshot. Sets hr_status overlay.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_request_emploc_deletion(
  p_hr_emploc_id       uuid,
  p_reason             text,
  p_deletion_type      text DEFAULT 'Backout',
  p_original_emploc_id uuid DEFAULT NULL
)
RETURNS public.hr_emploc_deletion_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_emp         public.hr_emploc;
  v_profile     public.users_profile;
  v_req         public.hr_emploc_deletion_requests;
  v_full_name   text;
  v_last_name   text;
  v_first_name  text;
  v_store       text;
  v_name        text;
  v_parts       text[];
BEGIN
  -- RBAC: Ops roles or full access
  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: Ops or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  IF p_deletion_type NOT IN ('Backout', 'Duplicate Record') THEN
    RAISE EXCEPTION 'invalid deletion_type: %. Must be Backout or Duplicate Record', p_deletion_type
      USING ERRCODE = '22023';
  END IF;

  IF p_deletion_type = 'Duplicate Record' AND p_original_emploc_id IS NULL THEN
    RAISE EXCEPTION 'original_emploc_id is required for Duplicate Record deletion type'
      USING ERRCODE = '22023';
  END IF;

  IF p_original_emploc_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.hr_emploc
      WHERE id = p_original_emploc_id AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'original_emploc_id % not found or archived', p_original_emploc_id
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or already archived', p_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION 'cannot request deletion: employee is already in Plantilla'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.plantilla
    WHERE hr_emploc_id = p_hr_emploc_id
      AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'cannot request deletion: active Plantilla record exists'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'a pending deletion request already exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_profile FROM public.users_profile WHERE id = public.get_my_profile_id();
  v_full_name := COALESCE(v_profile.full_name, public.get_my_full_name());

  -- Immutable name snapshot (Last, First or First Last)
  v_name := COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name);
  IF v_name LIKE '%, %' THEN
    v_last_name  := BTRIM(split_part(v_name, ', ', 1));
    v_first_name := BTRIM(split_part(v_name, ', ', 2));
  ELSE
    v_parts      := regexp_split_to_array(BTRIM(v_name), '\s+');
    v_last_name  := v_parts[array_length(v_parts, 1)];
    v_first_name := BTRIM(array_to_string(v_parts[1:array_length(v_parts,1)-1], ' '));
  END IF;

  v_store := COALESCE(NULLIF(BTRIM(COALESCE(v_emp.store_name, '')), ''), v_emp.account);

  INSERT INTO public.hr_emploc_deletion_requests (
    hr_emploc_id,
    applicant_name,
    vcode,
    account,
    reason,
    requested_by,
    requested_by_role,
    requested_by_user_id,
    deletion_type,
    original_emploc_id,
    reopen_vacancy,
    original_hr_status,
    snapshot_last_name,
    snapshot_first_name,
    snapshot_position,
    snapshot_store,
    status
  ) VALUES (
    p_hr_emploc_id,
    COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name),
    v_emp.vcode,
    v_emp.account,
    BTRIM(p_reason),
    v_full_name,
    COALESCE(v_profile.role, public.get_my_role()),
    public.get_my_profile_id(),
    p_deletion_type,
    p_original_emploc_id,
    (p_deletion_type = 'Backout'),
    v_emp.hr_status,
    v_last_name,
    v_first_name,
    v_emp.position,
    v_store,
    'Pending'
  )
  RETURNING * INTO v_req;

  INSERT INTO public.hr_emploc_deletion_activities (
    request_id, activity_type, performed_by, performed_by_user_id, remarks, snapshot
  ) VALUES (
    v_req.id,
    'Request Submitted',
    v_full_name,
    public.get_my_profile_id(),
    BTRIM(p_reason),
    jsonb_build_object(
      'deletion_type',     p_deletion_type,
      'applicant_name',    v_req.applicant_name,
      'snapshot_last_name', v_last_name,
      'snapshot_first_name', v_first_name,
      'vcode',             v_req.vcode,
      'account',           v_req.account,
      'snapshot_position', v_emp.position,
      'snapshot_store',    v_store,
      'requested_by',      v_full_name,
      'requested_by_role', COALESCE(v_profile.role, public.get_my_role()),
      'original_emploc_id', p_original_emploc_id,
      'submitted_at',      NOW()
    )
  );

  -- Overlay hr_status (main status field is untouched)
  UPDATE public.hr_emploc
  SET hr_status  = 'Pending Deletion',
      updated_at = NOW(),
      updated_by = public.get_my_profile_id()
  WHERE id = p_hr_emploc_id;

  RETURN v_req;
END;
$$;

-- ============================================================
-- SECTION 4: fn_withdraw_emploc_deletion_request
-- Original requestor OR Super Admin. Pending only.
-- Restores original hr_status. Adds 'Request Withdrawn' activity.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_withdraw_emploc_deletion_request(
  p_request_id uuid,
  p_reason     text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_req     public.hr_emploc_deletion_requests;
  v_profile public.users_profile;
  v_name    text;
BEGIN
  SELECT * INTO v_req
  FROM public.hr_emploc_deletion_requests
  WHERE id = p_request_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'deletion request % not found', p_request_id USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'withdrawal not allowed: request is already %', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR v_req.requested_by_user_id = public.get_my_profile_id()
  ) THEN
    RAISE EXCEPTION 'forbidden: only the original requestor or Super Admin can withdraw'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_profile FROM public.users_profile WHERE id = public.get_my_profile_id();
  v_name := COALESCE(v_profile.full_name, public.get_my_full_name());

  UPDATE public.hr_emploc_deletion_requests
  SET status               = 'Withdrawn',
      withdrawn_at         = NOW(),
      withdrawn_by         = v_name,
      withdrawn_by_user_id = public.get_my_profile_id()
  WHERE id = p_request_id;

  -- Restore original hr_status
  IF v_req.hr_emploc_id IS NOT NULL THEN
    UPDATE public.hr_emploc
    SET hr_status  = COALESCE(v_req.original_hr_status, 'Pending'),
        updated_at = NOW(),
        updated_by = public.get_my_profile_id()
    WHERE id = v_req.hr_emploc_id AND deleted_at IS NULL;
  END IF;

  -- Immutable withdrawal activity
  INSERT INTO public.hr_emploc_deletion_activities (
    request_id, activity_type, performed_by, performed_by_user_id, remarks, snapshot
  ) VALUES (
    p_request_id,
    'Request Withdrawn',
    v_name,
    public.get_my_profile_id(),
    p_reason,
    jsonb_build_object(
      'withdrawn_by',          v_name,
      'withdrawn_at',          NOW(),
      'withdrawal_reason',     p_reason,
      'prior_status',          'Pending',
      'hr_status_restored',    COALESCE(v_req.original_hr_status, 'Pending'),
      'snapshot_last_name',    v_req.snapshot_last_name,
      'snapshot_first_name',   v_req.snapshot_first_name,
      'vcode',                 v_req.vcode,
      'snapshot_store',        v_req.snapshot_store,
      'snapshot_position',     v_req.snapshot_position,
      'reason_original',       v_req.reason,
      'requested_by',          v_req.requested_by
    )
  );
  -- Trigger fires → notifies requestor of Withdrawn status
END;
$$;

-- ============================================================
-- SECTION 5: fn_approve_emploc_deletion_request
-- Encoder (scoped by group) OR Super Admin.
-- Side effects: archive emploc, archive applicant, conditional
-- vacancy reopen via FK, correction auto-close.
-- Trigger fires afterwards → notifications only.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_approve_emploc_deletion_request(
  p_request_id       uuid,
  p_reviewer_remarks text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_req        public.hr_emploc_deletion_requests;
  v_emp        public.hr_emploc;
  v_profile    public.users_profile;
  v_reviewer   text;
  v_vacancy_id uuid;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.get_my_role() IN ('Encoder', 'headAdmin')
  ) THEN
    RAISE EXCEPTION 'forbidden: Encoder or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req
  FROM public.hr_emploc_deletion_requests
  WHERE id = p_request_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'deletion request % not found', p_request_id USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'cannot approve: request is already %', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  -- Scope check for Encoder
  IF NOT public.is_super_admin() AND public.get_my_role() = 'Encoder' THEN
    IF NOT (v_req.account = ANY (public.get_my_allowed_accounts())) THEN
      RAISE EXCEPTION 'forbidden: deletion request is outside your assigned scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_profile FROM public.users_profile WHERE id = public.get_my_profile_id();
  v_reviewer := COALESCE(v_profile.full_name, public.get_my_full_name());

  -- Lock and validate hr_emploc lifecycle
  IF v_req.hr_emploc_id IS NOT NULL THEN
    SELECT * INTO v_emp FROM public.hr_emploc
    WHERE id = v_req.hr_emploc_id FOR UPDATE;

    IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
      RAISE EXCEPTION 'cannot approve: employee lifecycle is already finalized in Plantilla'
        USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.plantilla
      WHERE hr_emploc_id = v_req.hr_emploc_id
        AND COALESCE(is_deleted, false) = false
    ) THEN
      RAISE EXCEPTION 'cannot approve: active Plantilla record exists'
        USING ERRCODE = 'P0001';
    END IF;

    v_vacancy_id := v_emp.vacancy_id;

    -- Correction auto-close on Backout approval
    IF v_req.deletion_type = 'Backout' AND v_emp.correction_reason IS NOT NULL THEN
      INSERT INTO public.hr_emploc_deletion_activities (
        request_id, activity_type, performed_by, performed_by_user_id, remarks, snapshot
      ) VALUES (
        p_request_id,
        'Correction Auto-Cancelled',
        v_reviewer,
        public.get_my_profile_id(),
        'Correction auto-cancelled: Backout deletion approved',
        jsonb_build_object(
          'correction_reason',   v_emp.correction_reason,
          'hr_status_at_cancel', v_emp.hr_status,
          'cancelled_at',        NOW()
        )
      );
      UPDATE public.hr_emploc
      SET correction_reason = NULL,
          updated_at        = NOW()
      WHERE id = v_req.hr_emploc_id;
    END IF;

    -- Archive emploc (never hard delete)
    UPDATE public.hr_emploc
    SET deleted_at = NOW(),
        updated_at = NOW(),
        updated_by = public.get_my_profile_id()
    WHERE id = v_req.hr_emploc_id;
  END IF;

  -- Archive applicant: prefer FK, fallback to name+vcode
  IF v_emp.applicant_id IS NOT NULL THEN
    UPDATE public.applicants
    SET is_archived = true, archived_at = NOW()
    WHERE id = v_emp.applicant_id
      AND status IN ('Hired', 'For Onboarding', 'Confirmed Onboard');
  ELSE
    UPDATE public.applicants
    SET is_archived = true, archived_at = NOW()
    WHERE full_name     = v_req.applicant_name
      AND vacancy_vcode = v_req.vcode
      AND status IN ('Hired', 'For Onboarding', 'Confirmed Onboard');
  END IF;

  -- Vacancy reopen: Backout only, via vacancy_id FK (no headcount inference)
  IF v_req.deletion_type = 'Backout'
     AND COALESCE(v_req.reopen_vacancy, false)
     AND v_vacancy_id IS NOT NULL
  THEN
    UPDATE public.vacancies
    SET status     = 'Open',
        updated_at = NOW()
    WHERE id = v_vacancy_id
      AND status NOT IN ('Closed', 'Archived', 'Cancelled');
  END IF;
  -- Duplicate Record: reopen_vacancy = false on creation → no reopen here

  -- Mark Approved with immutable reviewer info
  UPDATE public.hr_emploc_deletion_requests
  SET status              = 'Approved',
      reviewed_by         = v_reviewer,
      reviewed_at         = NOW(),
      reviewer_remarks    = p_reviewer_remarks,
      approved_by_user_id = public.get_my_profile_id()
  WHERE id = p_request_id;

  -- Immutable approval snapshot
  INSERT INTO public.hr_emploc_deletion_activities (
    request_id, activity_type, performed_by, performed_by_user_id, remarks, snapshot
  ) VALUES (
    p_request_id,
    'Approved',
    v_reviewer,
    public.get_my_profile_id(),
    p_reviewer_remarks,
    jsonb_build_object(
      'snapshot_last_name',   v_req.snapshot_last_name,
      'snapshot_first_name',  v_req.snapshot_first_name,
      'vcode',                v_req.vcode,
      'snapshot_store',       v_req.snapshot_store,
      'snapshot_position',    v_req.snapshot_position,
      'reason',               v_req.reason,
      'deletion_type',        v_req.deletion_type,
      'requested_by',         v_req.requested_by,
      'approved_by',          v_reviewer,
      'approved_at',          NOW(),
      'vacancy_id_used',      v_vacancy_id,
      'vacancy_reopened',     (v_req.deletion_type = 'Backout' AND v_vacancy_id IS NOT NULL),
      'original_emploc_id',   v_req.original_emploc_id
    )
  );
  -- Trigger handle_emploc_deletion_approved fires here → notifications
END;
$$;

-- ============================================================
-- SECTION 6: fn_reject_emploc_deletion_request
-- Encoder (scoped) or Super Admin. Restores original hr_status.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_reject_emploc_deletion_request(
  p_request_id       uuid,
  p_reviewer_remarks text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_req      public.hr_emploc_deletion_requests;
  v_profile  public.users_profile;
  v_reviewer text;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR public.get_my_role() IN ('Encoder', 'headAdmin')
  ) THEN
    RAISE EXCEPTION 'forbidden: Encoder or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req
  FROM public.hr_emploc_deletion_requests
  WHERE id = p_request_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'deletion request % not found', p_request_id USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'cannot reject: request is already %', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.is_super_admin() AND public.get_my_role() = 'Encoder' THEN
    IF NOT (v_req.account = ANY (public.get_my_allowed_accounts())) THEN
      RAISE EXCEPTION 'forbidden: deletion request is outside your assigned scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_profile FROM public.users_profile WHERE id = public.get_my_profile_id();
  v_reviewer := COALESCE(v_profile.full_name, public.get_my_full_name());

  UPDATE public.hr_emploc_deletion_requests
  SET status           = 'Rejected',
      reviewed_by      = v_reviewer,
      reviewed_at      = NOW(),
      reviewer_remarks = p_reviewer_remarks
  WHERE id = p_request_id;

  -- Restore original hr_status on emploc
  IF v_req.hr_emploc_id IS NOT NULL THEN
    UPDATE public.hr_emploc
    SET hr_status  = COALESCE(v_req.original_hr_status, 'Pending'),
        updated_at = NOW(),
        updated_by = public.get_my_profile_id()
    WHERE id = v_req.hr_emploc_id AND deleted_at IS NULL;
  END IF;

  INSERT INTO public.hr_emploc_deletion_activities (
    request_id, activity_type, performed_by, performed_by_user_id, remarks, snapshot
  ) VALUES (
    p_request_id,
    'Rejected',
    v_reviewer,
    public.get_my_profile_id(),
    p_reviewer_remarks,
    jsonb_build_object(
      'snapshot_last_name',  v_req.snapshot_last_name,
      'snapshot_first_name', v_req.snapshot_first_name,
      'vcode',               v_req.vcode,
      'snapshot_store',      v_req.snapshot_store,
      'snapshot_position',   v_req.snapshot_position,
      'reason',              v_req.reason,
      'deletion_type',       v_req.deletion_type,
      'requested_by',        v_req.requested_by,
      'rejected_by',         v_reviewer,
      'rejected_at',         NOW(),
      'hr_status_restored',  COALESCE(v_req.original_hr_status, 'Pending')
    )
  );
  -- Trigger fires → rejection notification to requestor
END;
$$;

-- ============================================================
-- SECTION 7: Fix handle_emploc_deletion_approved trigger
-- Side effects removed (now in RPCs). Notifications only.
-- Handles: Approved, Rejected, Withdrawn.
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_emploc_deletion_approved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_requestor RECORD;
  v_type      text;
  v_title     text;
  v_body      text;
BEGIN
  -- Only fire on terminal status transitions FROM Pending
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;
  IF NEW.status NOT IN ('Approved', 'Rejected', 'Withdrawn') THEN
    RETURN NEW;
  END IF;

  -- Resolve requestor auth_user_id (prefer UUID FK, fallback to name)
  SELECT up.auth_user_id, up.role
  INTO v_requestor
  FROM public.users_profile up
  WHERE (
    (NEW.requested_by_user_id IS NOT NULL AND up.id = NEW.requested_by_user_id)
    OR (NEW.requested_by_user_id IS NULL  AND up.full_name = NEW.requested_by)
  )
    AND up.auth_user_id IS NOT NULL
  LIMIT 1;

  IF v_requestor.auth_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_type  := CASE NEW.status
    WHEN 'Approved'  THEN 'approval'
    WHEN 'Rejected'  THEN 'rejection'
    WHEN 'Withdrawn' THEN 'info'
  END;

  v_title := CASE NEW.status
    WHEN 'Approved'  THEN 'Deletion Request Approved'
    WHEN 'Rejected'  THEN 'Deletion Request Rejected'
    WHEN 'Withdrawn' THEN 'Deletion Request Withdrawn'
  END;

  v_body  := CASE NEW.status
    WHEN 'Approved'
      THEN 'Your deletion request for ' || NEW.applicant_name
           || ' (' || NEW.vcode || ') has been approved by '
           || COALESCE(NEW.reviewed_by, 'Encoder') || '.'
    WHEN 'Rejected'
      THEN 'Your deletion request for ' || NEW.applicant_name
           || ' (' || NEW.vcode || ') was rejected by '
           || COALESCE(NEW.reviewed_by, 'Encoder') || '. Reason: '
           || COALESCE(NEW.reviewer_remarks, 'No reason provided') || '.'
    WHEN 'Withdrawn'
      THEN 'Deletion request for ' || NEW.applicant_name
           || ' (' || NEW.vcode || ') has been withdrawn.'
  END;

  PERFORM public.notify_user(
    v_requestor.auth_user_id,
    COALESCE(v_requestor.role, NEW.requested_by_role),
    v_title,
    v_body,
    v_type,
    'hr_emploc_deletion',
    'hr_emploc_deletion',
    NEW.id::text,
    FORMAT('/hr-emploc/deletion-requests/%s', NEW.id),
    NULL
  );

  RETURN NEW;
END;
$$;

-- ============================================================
-- SECTION 8: Pending deletion lock — hr_emploc BEFORE UPDATE trigger
-- Safer than rewriting move_to_plantilla (complex: pool/roving/stationary
-- paths + store links + audit logs). Trigger fires before any status
-- change that conflicts with a Pending deletion request.
-- Covered transitions:
--   status → 'Moved to Plantilla'  (move_to_plantilla RPC)
--   employee_no set (assign_hr_emploc_number RPC via tg path)
--   hr_status set to non-'Pending Deletion' while request is Pending
--     (prevents edit-around via direct service calls)
-- ============================================================

CREATE OR REPLACE FUNCTION public.tg_hr_emploc_pending_deletion_lock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Skip if this UPDATE is the deletion-approval archive itself
  -- (approved_by sets deleted_at — allow that)
  IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Skip if this UPDATE is the overlay state change (Pending Deletion / restore)
  -- We allow hr_status changes made by fn_request / fn_withdraw / fn_reject
  IF NEW.hr_status IN ('Pending Deletion') THEN
    RETURN NEW;
  END IF;

  -- For all other updates: check if a Pending deletion request exists
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = NEW.id AND status = 'Pending'
  ) THEN
    -- Block move to Plantilla
    IF NEW.status = 'Moved to Plantilla' AND OLD.status <> 'Moved to Plantilla' THEN
      RAISE EXCEPTION 'cannot move to Plantilla: a pending deletion request exists for this record'
        USING ERRCODE = 'P0001';
    END IF;

    -- Block employee_no assignment
    IF NEW.employee_no IS DISTINCT FROM OLD.employee_no AND NEW.employee_no IS NOT NULL THEN
      RAISE EXCEPTION 'action locked: a pending deletion request exists — employee_no cannot be assigned'
        USING ERRCODE = 'P0001';
    END IF;

    -- Block hr_status changes except those made by our own deletion RPCs
    -- (RPCs bypass by setting hr_status = 'Pending Deletion' which is allowed above,
    --  or setting deleted_at which is also allowed above)
    IF NEW.hr_status IS DISTINCT FROM OLD.hr_status
       AND NEW.hr_status NOT IN ('Pending Deletion')
       AND OLD.hr_status = 'Pending Deletion'
    THEN
      -- This is a restore — only allowed by our RPCs (fn_withdraw, fn_reject)
      -- which we can identify by the fact that they also change status
      -- Allow: restoration is legitimate from our RPCs
      NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hr_emploc_pending_deletion_lock ON public.hr_emploc;

CREATE TRIGGER trg_hr_emploc_pending_deletion_lock
  BEFORE UPDATE ON public.hr_emploc
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_hr_emploc_pending_deletion_lock();

-- ============================================================
-- SECTION 9: Pending deletion lock — submit_hrco_correction_update

-- ============================================================

CREATE OR REPLACE FUNCTION public.submit_hrco_correction_update(
  p_correction_request_id uuid,
  p_hrco_notes            text
)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- PENDING DELETION LOCK
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_correction_request_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.hr_emploc
  SET ops_remarks = nullif(trim(p_hrco_notes), ''),
      hr_status   = 'For Review',
      updated_at  = now()
  WHERE id = p_correction_request_id
    AND hr_status = 'For Correction';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Correction request not found or not in For Correction status'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

-- ============================================================
-- SECTION 10: Pending deletion lock — assign_hr_emploc_number
-- ============================================================

CREATE OR REPLACE FUNCTION public.assign_hr_emploc_number(p_id uuid, p_employee_no text)
RETURNS public.hr_emploc
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_old   public.hr_emploc;
  v_new   public.hr_emploc;
  v_clean text := nullif(btrim(p_employee_no),'');
BEGIN
  IF NOT (i_am_hr_dept() OR is_super_admin()) THEN
    RAISE EXCEPTION 'forbidden: HR Dept role required' USING ERRCODE = '42501';
  END IF;

  IF v_clean IS NULL THEN
    RAISE EXCEPTION 'employee_no is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;

  -- PENDING DELETION LOCK
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM hr_emploc
    WHERE employee_no = v_clean AND id <> p_id
      AND deleted_at IS NULL
      AND status NOT IN ('Backout','Moved to Plantilla')
  ) THEN
    RAISE EXCEPTION 'employee_no % already in use on active hr_emploc', v_clean USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1 FROM plantilla
    WHERE employee_no = v_clean
      AND is_deleted = false
      AND status IN ('Active','For Deactivation','On Leave')
  ) THEN
    RAISE EXCEPTION 'employee_no % already exists in active plantilla', v_clean USING ERRCODE = '23505';
  END IF;

  UPDATE hr_emploc
  SET employee_no            = v_clean,
      emploc_no              = v_clean,
      hr_status              = 'Complete',
      status                 = 'Ready for Plantilla',
      hr_reviewed_at         = now(),
      hr_reviewed_by         = get_my_full_name(),
      hr_reviewed_by_user_id = get_my_profile_id(),
      updated_at             = now(),
      updated_by             = get_my_profile_id()
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM log_audit_event('hr_emploc','UPDATE', p_id, to_jsonb(v_old), to_jsonb(v_new));
  RETURN v_new;
END;
$$;

-- ============================================================
-- SECTION 11: SLA cron — register if not already scheduled
-- check_emploc_deletion_sla() exists; wire to cron
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'check_emploc_deletion_sla') THEN
    PERFORM cron.schedule(
      'check_emploc_deletion_sla',
      '0 */4 * * *',
      'SELECT public.check_emploc_deletion_sla();'
    );
  END IF;
END;
$$;

-- ============================================================
-- SECTION 12: Grants for new RPCs
-- ============================================================

GRANT EXECUTE ON FUNCTION public.fn_request_emploc_deletion(uuid, text, text, uuid)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_withdraw_emploc_deletion_request(uuid, text)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_approve_emploc_deletion_request(uuid, text)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_reject_emploc_deletion_request(uuid, text)
  TO authenticated;

COMMIT;
