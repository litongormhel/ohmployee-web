-- ============================================================================
-- Migration: 20262606000084_hr_emploc_for_emploc_and_scoped_docs.sql
-- Purpose: Stage 2b-DB — "For Emploc" workflow status, scoped Ops document
--          upload/remove/view in private bucket 'hr-corrections', 3-day
--          post-deployment storage cleanup queue via pg_net + Vault,
--          revert-within-grace, pending-deletion locks, cross-module
--          pipeline fixes, and standardized error tokens.
-- ============================================================================

-- 1. Update hr_emploc_hr_status_check to include 'For Emploc'
ALTER TABLE public.hr_emploc DROP CONSTRAINT IF EXISTS hr_emploc_hr_status_check;
ALTER TABLE public.hr_emploc ADD CONSTRAINT hr_emploc_hr_status_check
  CHECK (hr_status = ANY (ARRAY[
    'Pending'::text,
    'For Emploc'::text,
    'Complete'::text,
    'For Correction'::text,
    'For Review'::text,
    'Transferred'::text,
    'Rejected'::text,
    'Pending Deletion'::text
  ]));

-- 2. Extend public.hr_emploc_correction_attachments in place (Decision 5)
ALTER TABLE public.hr_emploc_correction_attachments
  ADD COLUMN IF NOT EXISTS stage text NOT NULL DEFAULT 'correction'
    CHECK (stage IN ('initial_requirements', 'correction')),
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_reason text;

UPDATE public.hr_emploc_correction_attachments
SET created_at = COALESCE(uploaded_at, now())
WHERE created_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_hr_emploc_docs_active
  ON public.hr_emploc_correction_attachments (hr_emploc_id, stage)
  WHERE is_deleted = false AND deleted_at IS NULL;

-- Part 0.5: Partial unique index for idempotent registration
CREATE UNIQUE INDEX IF NOT EXISTS uq_hr_emploc_correction_attachments_active
  ON public.hr_emploc_correction_attachments (hr_emploc_id, storage_path)
  WHERE is_deleted = false AND deleted_at IS NULL;

-- 3. Create public.storage_cleanup_queue
CREATE TABLE IF NOT EXISTS public.storage_cleanup_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hr_emploc_id uuid NOT NULL REFERENCES public.hr_emploc(id) ON DELETE CASCADE,
  attachment_id uuid REFERENCES public.hr_emploc_correction_attachments(id) ON DELETE SET NULL,
  bucket_id text NOT NULL DEFAULT 'hr-corrections',
  storage_path text NOT NULL,
  reason text NOT NULL,
  due_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'dispatched', 'completed', 'cancelled', 'failed')),
  attempts integer NOT NULL DEFAULT 0,
  pg_net_request_id bigint,
  dispatched_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_reason text
);

CREATE INDEX IF NOT EXISTS idx_storage_cleanup_queue_due
  ON public.storage_cleanup_queue (status, due_at)
  WHERE status IN ('pending', 'dispatched');

CREATE INDEX IF NOT EXISTS idx_storage_cleanup_queue_emploc
  ON public.storage_cleanup_queue (hr_emploc_id, status);

ALTER TABLE public.storage_cleanup_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS storage_cleanup_queue_sa_read ON public.storage_cleanup_queue;
CREATE POLICY storage_cleanup_queue_sa_read
  ON public.storage_cleanup_queue
  FOR SELECT TO authenticated
  USING (public.is_super_admin());

REVOKE ALL ON public.storage_cleanup_queue FROM anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.storage_cleanup_queue FROM authenticated;
GRANT SELECT ON public.storage_cleanup_queue TO authenticated;

-- 4. Disable legacy cleanup_expired_correction_attachments() (2d)
CREATE OR REPLACE FUNCTION public.cleanup_expired_correction_attachments()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Disabled in Stage 2b-DB (20262606000084): superseded by public.process_storage_cleanup_queue()
  RETURN 0;
END;
$function$;

DO $$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE command ILIKE '%cleanup_expired_correction_attachments%';
  END IF;
END $$;

-- 5. Pending-deletion helper & Scoped RBAC Helpers (2a, Decisions 1-4)
CREATE OR REPLACE FUNCTION public.has_pending_deletion_request(p_hr_emploc_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.hr_emploc_deletion_requests dr
    WHERE dr.hr_emploc_id = p_hr_emploc_id
      AND dr.status = 'Pending'
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_hr_emploc_in_my_scope(p_hr_emploc_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_level integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RETURN false;
  END IF;

  SELECT up.id, COALESCE(public.get_my_role_level(), r.role_level)
  INTO v_profile_id, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR COALESCE(v_role_level, 0) <= 0 THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.hr_emploc h
    WHERE h.id = p_hr_emploc_id
      AND h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR public.i_have_full_access()
        OR public.get_my_scope_type() = 'global'
        OR public.i_have_hrco_global_visibility()
        OR h.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          JOIN public.accounts ac ON ac.id = h.account_id
          WHERE us.user_id = v_profile_id
            AND us.account_id IS NULL
            AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fallback
          JOIN public.accounts ac ON ac.id = h.account_id
          WHERE up_fallback.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
        )
      )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_add_emploc()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN public.can_assign_pending_hr_emploc();
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_upload_hr_emploc_docs(p_hr_emploc_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_emp public.hr_emploc;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  SELECT * INTO v_emp
  FROM public.hr_emploc
  WHERE id = p_hr_emploc_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_emp.status = 'Moved to Plantilla' OR v_emp.hr_status = 'Transferred' THEN
    RETURN false;
  END IF;

  IF v_emp.hr_status NOT IN ('Pending', 'For Correction') THEN
    RETURN false;
  END IF;

  IF public.has_pending_deletion_request(p_hr_emploc_id) THEN
    RETURN false;
  END IF;

  IF public.is_super_admin() THEN
    RETURN true;
  END IF;

  -- Ops roles ONLY (OM 70, HRCO 45, ATL 42, TL 41). Excludes HA 90, Encoder 30, HR Personnel 25.
  IF NOT public.can_submit_hr_emploc_correction() THEN
    RETURN false;
  END IF;

  RETURN public.is_hr_emploc_in_my_scope(p_hr_emploc_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_view_hr_emploc_docs(p_hr_emploc_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_emp public.hr_emploc;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  SELECT * INTO v_emp
  FROM public.hr_emploc
  WHERE id = p_hr_emploc_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- Viewing documents strictly BLOCKED once record is deployed
  IF v_emp.status = 'Moved to Plantilla' OR v_emp.hr_status = 'Transferred' THEN
    RETURN false;
  END IF;

  IF public.is_super_admin() THEN
    RETURN true;
  END IF;

  -- HR Personnel (25), Head Admin (90), Encoder (30) have read access across records
  IF public.can_assign_pending_hr_emploc()
    OR public.can_tag_or_review_hr_emploc()
    OR COALESCE(public.get_my_role(), '') = 'Encoder'
    OR public.can_submit_hr_emploc_correction()
  THEN
    -- For Ops coordinators (OM, TL, ATL, HRCO), must be within account/store scope
    IF public.can_submit_hr_emploc_correction()
      AND NOT public.can_assign_pending_hr_emploc()
      AND NOT public.can_tag_or_review_hr_emploc()
      AND COALESCE(public.get_my_role(), '') <> 'Encoder'
    THEN
      RETURN public.is_hr_emploc_in_my_scope(p_hr_emploc_id);
    END IF;

    RETURN true;
  END IF;

  RETURN false;
END;
$function$;

-- 6. Configure storage bucket hr-corrections & policies (2b, 2c)
UPDATE storage.buckets
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
WHERE id = 'hr-corrections';

DROP POLICY IF EXISTS emploc_docs_storage_insert ON storage.objects;
DROP POLICY IF EXISTS emploc_docs_storage_select ON storage.objects;
DROP POLICY IF EXISTS emploc_docs_storage_delete ON storage.objects;
DROP POLICY IF EXISTS hr_corrections_insert ON storage.objects;
DROP POLICY IF EXISTS hr_corrections_select ON storage.objects;
DROP POLICY IF EXISTS hr_corrections_delete ON storage.objects;
DROP POLICY IF EXISTS hr_corrections_upload_policy ON storage.objects;
DROP POLICY IF EXISTS hr_corrections_select_policy ON storage.objects;
DROP POLICY IF EXISTS hr_corrections_delete_policy ON storage.objects;

CREATE POLICY emploc_docs_storage_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'hr-corrections' AND (
      public.is_super_admin()
      OR (
        name LIKE 'emploc-docs/%/%'
        AND public.can_upload_hr_emploc_docs((split_part(name, '/', 2))::uuid)
      )
    )
  );

CREATE POLICY emploc_docs_storage_select
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'hr-corrections' AND (
      public.is_super_admin()
      OR (
        name LIKE 'emploc-docs/%/%'
        AND public.can_view_hr_emploc_docs((split_part(name, '/', 2))::uuid)
      )
      OR EXISTS (
        SELECT 1
        FROM public.hr_emploc_correction_attachments ca
        WHERE ca.is_deleted = false
          AND ca.deleted_at IS NULL
          AND (ca.storage_path = name OR ca.storage_path = ('hr-corrections/' || name))
          AND public.can_view_hr_emploc_docs(ca.hr_emploc_id)
      )
    )
  );

-- 7. Attachment table RLS policies
DROP POLICY IF EXISTS emploc_docs_scoped_read ON public.hr_emploc_correction_attachments;
DROP POLICY IF EXISTS correction_attach_insert ON public.hr_emploc_correction_attachments;
DROP POLICY IF EXISTS correction_attach_insert_auth_uid ON public.hr_emploc_correction_attachments;
DROP POLICY IF EXISTS correction_attach_insert_uploaded_by_profile ON public.hr_emploc_correction_attachments;
DROP POLICY IF EXISTS correction_attach_read ON public.hr_emploc_correction_attachments;
DROP POLICY IF EXISTS correction_attach_update ON public.hr_emploc_correction_attachments;

CREATE POLICY emploc_docs_scoped_read
  ON public.hr_emploc_correction_attachments
  FOR SELECT TO authenticated
  USING (
    is_deleted = false
    AND deleted_at IS NULL
    AND public.can_view_hr_emploc_docs(hr_emploc_id)
  );

-- 8. Document Upload / Register / Remove / Submit Requirements RPCs
CREATE OR REPLACE FUNCTION public.authorize_hr_emploc_doc_upload(
  p_hr_emploc_id uuid,
  p_file_name text,
  p_mime_type text,
  p_size_bytes bigint
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_emp       public.hr_emploc;
  v_clean_fn  text;
  v_mime      text := lower(btrim(COALESCE(p_mime_type, '')));
  v_stage     text;
  v_ts_ms     bigint;
  v_obj_path  text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: document upload requires a valid session'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'UNAUTHENTICATED')::text;
  END IF;

  SELECT * INTO v_emp
  FROM public.hr_emploc
  WHERE id = p_hr_emploc_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record % not found or archived', p_hr_emploc_id
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  IF public.has_pending_deletion_request(p_hr_emploc_id) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF v_emp.status = 'Moved to Plantilla' OR v_emp.hr_status = 'Transferred' THEN
    RAISE EXCEPTION 'INVALID_STAGE_FOR_UPLOAD: Record is already deployed to Plantilla'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STAGE_FOR_UPLOAD')::text;
  END IF;

  IF v_emp.hr_status NOT IN ('Pending', 'For Correction') THEN
    RAISE EXCEPTION 'INVALID_STAGE_FOR_UPLOAD: Document uploads are only allowed in Pending or For Correction (current hr_status: "%")', v_emp.hr_status
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STAGE_FOR_UPLOAD')::text;
  END IF;

  IF NOT public.can_upload_hr_emploc_docs(p_hr_emploc_id) THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: only Ops roles (OM, TL, ATL, HRCO) within scope or Super Admin may upload documents'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  IF v_mime NOT IN ('image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/pdf') THEN
    RAISE EXCEPTION 'INVALID_MIME_TYPE: Unsupported file type "%". Allowed: JPEG, PNG, WEBP, PDF.', p_mime_type
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_MIME_TYPE')::text;
  END IF;

  IF COALESCE(p_size_bytes, 0) <= 0 OR p_size_bytes > 10485760 THEN
    RAISE EXCEPTION 'FILE_TOO_LARGE: File size (% bytes) must be between 1 byte and 10 MB (10485760 bytes).', COALESCE(p_size_bytes, 0)
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FILE_TOO_LARGE')::text;
  END IF;

  v_clean_fn := regexp_replace(COALESCE(NULLIF(btrim(p_file_name), ''), 'document'), '[^A-Za-z0-9._-]', '_', 'g');
  v_stage    := CASE WHEN v_emp.hr_status = 'Pending' THEN 'initial_requirements' ELSE 'correction' END;
  v_ts_ms    := (EXTRACT(epoch FROM clock_timestamp()) * 1000)::bigint;
  v_obj_path := format('emploc-docs/%s/%s_%s', p_hr_emploc_id::text, v_ts_ms::text, v_clean_fn);

  RETURN jsonb_build_object(
    'bucket_id', 'hr-corrections',
    'object_path', v_obj_path,
    'storage_path', 'hr-corrections/' || v_obj_path,
    'sanitized_file_name', v_clean_fn,
    'stage', v_stage,
    'max_size_bytes', 10485760
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_hr_emploc_document(
  p_hr_emploc_id uuid,
  p_storage_path text,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_stage text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_emp        public.hr_emploc;
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
  v_mime       text := lower(btrim(COALESCE(p_mime_type, '')));
  v_rel_path   text;
  v_full_path  text;
  v_stage      text;
  v_att        public.hr_emploc_correction_attachments;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: document registration requires a valid session'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'UNAUTHENTICATED')::text;
  END IF;

  SELECT * INTO v_emp
  FROM public.hr_emploc
  WHERE id = p_hr_emploc_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record % not found or archived', p_hr_emploc_id
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  IF public.has_pending_deletion_request(p_hr_emploc_id) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF v_emp.status = 'Moved to Plantilla' OR v_emp.hr_status = 'Transferred' THEN
    RAISE EXCEPTION 'INVALID_STAGE_FOR_UPLOAD: Record is already deployed to Plantilla'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STAGE_FOR_UPLOAD')::text;
  END IF;

  IF v_emp.hr_status NOT IN ('Pending', 'For Correction') THEN
    RAISE EXCEPTION 'INVALID_STAGE_FOR_UPLOAD: Document registration is only allowed in Pending or For Correction (current hr_status: "%")', v_emp.hr_status
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STAGE_FOR_UPLOAD')::text;
  END IF;

  IF NOT public.can_upload_hr_emploc_docs(p_hr_emploc_id) THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: only Ops roles (OM, TL, ATL, HRCO) within scope or Super Admin may register documents'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  IF v_mime NOT IN ('image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/pdf') THEN
    RAISE EXCEPTION 'INVALID_MIME_TYPE: Unsupported file type "%". Allowed: JPEG, PNG, WEBP, PDF.', p_mime_type
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_MIME_TYPE')::text;
  END IF;

  IF COALESCE(p_size_bytes, 0) <= 0 OR p_size_bytes > 10485760 THEN
    RAISE EXCEPTION 'FILE_TOO_LARGE: File size (% bytes) must be between 1 byte and 10 MB (10485760 bytes).', COALESCE(p_size_bytes, 0)
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FILE_TOO_LARGE')::text;
  END IF;

  v_rel_path  := regexp_replace(btrim(COALESCE(p_storage_path, '')), '^hr-corrections/', '');
  v_full_path := 'hr-corrections/' || v_rel_path;

  IF v_rel_path NOT LIKE ('emploc-docs/' || p_hr_emploc_id::text || '/%') THEN
    RAISE EXCEPTION 'INVALID_STORAGE_PATH: Storage path "%" must start with emploc-docs/%/', v_rel_path, p_hr_emploc_id
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STORAGE_PATH')::text;
  END IF;

  -- Part 0.5: Server strictly derives and validates stage from record state
  v_stage := CASE WHEN v_emp.hr_status = 'Pending' THEN 'initial_requirements' ELSE 'correction' END;

  -- Part 0.5: Idempotency check: if active record exists for this path, return existing row
  SELECT * INTO v_att
  FROM public.hr_emploc_correction_attachments
  WHERE hr_emploc_id = p_hr_emploc_id
    AND (storage_path = v_full_path OR storage_path = v_rel_path)
    AND is_deleted = false
    AND deleted_at IS NULL
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'id', v_att.id,
      'hr_emploc_id', v_att.hr_emploc_id,
      'storage_path', v_att.storage_path,
      'object_path', v_rel_path,
      'original_filename', v_att.original_filename,
      'mime_type', v_att.mime_type,
      'size_bytes', v_att.size_bytes,
      'stage', v_att.stage,
      'uploaded_by', v_att.uploaded_by,
      'uploaded_at', v_att.uploaded_at,
      'created_at', v_att.created_at,
      'is_duplicate', true
    );
  END IF;

  -- Concurrency-safe insert using partial unique index
  INSERT INTO public.hr_emploc_correction_attachments (
    hr_emploc_id,
    storage_path,
    original_filename,
    mime_type,
    size_bytes,
    uploaded_by,
    uploaded_at,
    created_at,
    stage,
    is_deleted
  ) VALUES (
    p_hr_emploc_id,
    v_full_path,
    COALESCE(NULLIF(btrim(p_original_filename), ''), 'document'),
    v_mime,
    p_size_bytes,
    v_profile_id,
    now(),
    now(),
    v_stage,
    false
  )
  ON CONFLICT (hr_emploc_id, storage_path) WHERE (is_deleted = false AND deleted_at IS NULL)
  DO UPDATE SET hr_emploc_id = EXCLUDED.hr_emploc_id
  RETURNING * INTO v_att;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    jsonb_build_object('hr_status', v_emp.hr_status),
    jsonb_build_object(
      'action', 'upload_document',
      'attachment_id', v_att.id,
      'file_name', v_att.original_filename,
      'size_bytes', v_att.size_bytes,
      'stage', v_att.stage,
      'actor_name', v_actor_name,
      'actor_id', v_profile_id,
      'log_message', format('Uploaded document "%s" (%s) by %s', v_att.original_filename, v_att.stage, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'id', v_att.id,
    'hr_emploc_id', v_att.hr_emploc_id,
    'storage_path', v_att.storage_path,
    'object_path', v_rel_path,
    'original_filename', v_att.original_filename,
    'mime_type', v_att.mime_type,
    'size_bytes', v_att.size_bytes,
    'stage', v_att.stage,
    'uploaded_by', v_att.uploaded_by,
    'uploaded_at', v_att.uploaded_at,
    'created_at', v_att.created_at,
    'is_duplicate', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_hr_emploc_document(p_attachment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_att        public.hr_emploc_correction_attachments;
  v_emp        public.hr_emploc;
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
  v_rel_path   text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: document removal requires a valid session'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'UNAUTHENTICATED')::text;
  END IF;

  SELECT * INTO v_att
  FROM public.hr_emploc_correction_attachments
  WHERE id = p_attachment_id
  FOR UPDATE;

  IF NOT FOUND OR v_att.is_deleted = true OR v_att.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: Document % not found or already removed', p_attachment_id
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  SELECT * INTO v_emp
  FROM public.hr_emploc
  WHERE id = v_att.hr_emploc_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record % not found or archived', v_att.hr_emploc_id
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  IF public.has_pending_deletion_request(v_emp.id) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF v_emp.hr_status NOT IN ('Pending', 'For Correction') OR v_emp.status = 'Moved to Plantilla' THEN
    RAISE EXCEPTION 'INVALID_STAGE_FOR_REMOVE: Documents can only be removed while record is in Pending or For Correction (current hr_status: "%")', v_emp.hr_status
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STAGE_FOR_REMOVE')::text;
  END IF;

  IF NOT public.can_upload_hr_emploc_docs(v_emp.id) THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: only Ops roles within scope or Super Admin may remove documents'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  IF NOT public.is_super_admin() AND v_att.uploaded_by IS DISTINCT FROM v_profile_id THEN
    RAISE EXCEPTION 'FORBIDDEN_NOT_UPLOADER: You may only remove documents that you uploaded yourself.'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_NOT_UPLOADER')::text;
  END IF;

  UPDATE public.hr_emploc_correction_attachments
  SET is_deleted     = true,
      deleted_at     = now(),
      deleted_reason = 'removed_by_uploader'
  WHERE id = p_attachment_id;

  v_rel_path := regexp_replace(v_att.storage_path, '^hr-corrections/', '');

  INSERT INTO public.storage_cleanup_queue (
    hr_emploc_id,
    attachment_id,
    bucket_id,
    storage_path,
    reason,
    due_at,
    status
  ) VALUES (
    v_emp.id,
    v_att.id,
    'hr-corrections',
    v_rel_path,
    'manual_remove',
    now(),
    'pending'
  );

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    v_emp.id,
    jsonb_build_object('attachment_id', v_att.id, 'file_name', v_att.original_filename),
    jsonb_build_object(
      'action', 'remove_document',
      'attachment_id', v_att.id,
      'file_name', v_att.original_filename,
      'actor_name', v_actor_name,
      'actor_id', v_profile_id,
      'log_message', format('Removed document "%s" by %s', v_att.original_filename, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'attachment_id', v_att.id,
    'hr_emploc_id', v_emp.id,
    'deleted_reason', 'removed_by_uploader'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_hr_emploc_requirements(
  p_hr_emploc_id uuid,
  p_remarks text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_emp        public.hr_emploc;
  v_new        public.hr_emploc;
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
  v_doc_count  bigint := 0;
  v_clean_rem  text := NULLIF(btrim(COALESCE(p_remarks, '')), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: submitting requirements requires a valid session'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'UNAUTHENTICATED')::text;
  END IF;

  SELECT * INTO v_emp
  FROM public.hr_emploc
  WHERE id = p_hr_emploc_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record % not found or archived', p_hr_emploc_id
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  IF public.has_pending_deletion_request(p_hr_emploc_id) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF v_emp.status = 'Moved to Plantilla' OR v_emp.hr_status = 'Transferred' THEN
    RAISE EXCEPTION 'INVALID_STATE: Record is already deployed to Plantilla'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE')::text;
  END IF;

  IF v_emp.hr_status <> 'Pending' THEN
    RAISE EXCEPTION 'INVALID_STATE: Record hr_status is "%", expected "Pending"', v_emp.hr_status
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE')::text;
  END IF;

  IF NOT public.can_upload_hr_emploc_docs(p_hr_emploc_id) THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: only Ops roles (OM, TL, ATL, HRCO) within scope or Super Admin may submit requirements'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  SELECT count(*) INTO v_doc_count
  FROM public.hr_emploc_correction_attachments ca
  WHERE ca.hr_emploc_id = p_hr_emploc_id
    AND ca.is_deleted = false
    AND ca.deleted_at IS NULL;

  IF v_doc_count <= 0 THEN
    RAISE EXCEPTION 'REQUIREMENTS_DOCS_MISSING: At least one requirement document must be uploaded before moving to For Emploc.'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'REQUIREMENTS_DOCS_MISSING')::text;
  END IF;

  UPDATE public.hr_emploc
  SET hr_status   = 'For Emploc',
      ops_remarks = COALESCE(v_clean_rem, ops_remarks),
      updated_at  = now(),
      updated_by  = v_profile_id
  WHERE id = p_hr_emploc_id
  RETURNING * INTO v_new;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_emp),
    jsonb_build_object(
      'action', 'submit_requirements',
      'status_from', v_emp.hr_status,
      'status_to', v_new.hr_status,
      'doc_count', v_doc_count,
      'ops_remarks', v_new.ops_remarks,
      'actor_name', v_actor_name,
      'actor_id', v_profile_id,
      'log_message', format('Submitted %s requirement document(s) and moved to For Emploc by %s', v_doc_count, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'hr_emploc_id', p_hr_emploc_id,
    'hr_status', v_new.hr_status,
    'emploc_status', v_new.status,
    'doc_count', v_doc_count,
    'ops_remarks', v_new.ops_remarks
  );
END;
$function$;

-- 9. Storage Cleanup Enqueue, Trigger, Orphan Sweeper (2e), and Purge Executor (2f)
CREATE OR REPLACE FUNCTION public.enqueue_hr_emploc_docs_cleanup(
  p_hr_emploc_id uuid,
  p_reason text,
  p_delay interval DEFAULT interval '3 days'
)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count integer := 0;
  v_rec   record;
  v_due   timestamptz := now() + p_delay;
BEGIN
  FOR v_rec IN
    SELECT ca.id AS attachment_id,
           regexp_replace(ca.storage_path, '^hr-corrections/', '') AS rel_path
    FROM public.hr_emploc_correction_attachments ca
    WHERE ca.hr_emploc_id = p_hr_emploc_id
      AND ca.is_deleted = false
      AND ca.deleted_at IS NULL
  LOOP
    INSERT INTO public.storage_cleanup_queue (
      hr_emploc_id,
      attachment_id,
      bucket_id,
      storage_path,
      reason,
      due_at,
      status
    ) VALUES (
      p_hr_emploc_id,
      v_rec.attachment_id,
      'hr-corrections',
      v_rec.rel_path,
      p_reason,
      v_due,
      'pending'
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.tg_enqueue_emploc_docs_cleanup_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF (NEW.status = 'Moved to Plantilla' OR NEW.hr_status = 'Transferred')
     AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.hr_status IS DISTINCT FROM NEW.hr_status)
  THEN
    PERFORM public.enqueue_hr_emploc_docs_cleanup(NEW.id, 'deployed_3day_ttl', interval '3 days');
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_enqueue_emploc_docs_cleanup ON public.hr_emploc;
CREATE TRIGGER trg_enqueue_emploc_docs_cleanup
  AFTER UPDATE OF status, hr_status ON public.hr_emploc
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_enqueue_emploc_docs_cleanup_fn();

-- 2e. Report-only Orphan Sweeper (NEVER deletes or enqueues in this stage)
CREATE OR REPLACE FUNCTION public.sweep_orphan_emploc_storage_objects()
 RETURNS TABLE(
   object_id uuid,
   object_name text,
   created_at timestamptz,
   owner uuid,
   size_bytes bigint,
   mime_type text,
   classification text
 )
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    so.id AS object_id,
    so.name AS object_name,
    so.created_at,
    so.owner,
    (so.metadata->>'size')::bigint AS size_bytes,
    so.metadata->>'mimetype' AS mime_type,
    CASE
      WHEN split_part(so.name, '/', 1) = 'emploc-docs' THEN 'unreferenced_emploc_docs_prefix'
      ELSE 'unreferenced_legacy_root_object'
    END AS classification
  FROM storage.objects so
  WHERE so.bucket_id = 'hr-corrections'
    AND NOT EXISTS (
      SELECT 1
      FROM public.hr_emploc_correction_attachments ca
      WHERE ca.storage_path = so.name
         OR ca.storage_path = ('hr-corrections/' || so.name)
    )
  ORDER BY so.created_at ASC;
$function$;

CREATE OR REPLACE FUNCTION public.process_storage_cleanup_queue(p_batch_size integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rec           record;
  v_processed     integer := 0;
  v_failed        integer := 0;
  v_proj_url      text;
  v_anon_or_srv   text;
  v_req_id        bigint;
  v_target_url    text;
BEGIN
  SELECT decrypted_secret INTO v_proj_url
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_project_url'
  LIMIT 1;

  IF v_proj_url IS NULL OR v_proj_url = '' THEN
    SELECT decrypted_secret INTO v_proj_url
    FROM vault.decrypted_secrets
    WHERE name = 'project_url'
    LIMIT 1;
  END IF;

  IF v_proj_url IS NULL OR v_proj_url = '' THEN
    v_proj_url := current_setting('app.settings.project_url', true);
  END IF;

  SELECT decrypted_secret INTO v_anon_or_srv
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_service_role_key'
  LIMIT 1;

  IF v_anon_or_srv IS NULL OR v_anon_or_srv = '' THEN
    SELECT decrypted_secret INTO v_anon_or_srv
    FROM vault.decrypted_secrets
    WHERE name = 'service_role_key'
    LIMIT 1;
  END IF;

  IF v_anon_or_srv IS NULL OR v_anon_or_srv = '' THEN
    v_anon_or_srv := current_setting('app.settings.service_role_key', true);
  END IF;

  IF v_proj_url IS NULL OR v_proj_url = '' OR v_anon_or_srv IS NULL OR v_anon_or_srv = '' THEN
    RETURN jsonb_build_object(
      'status', 'skipped',
      'reason', 'Vault secrets supabase_project_url or supabase_service_role_key not configured'
    );
  END IF;

  v_proj_url := rtrim(v_proj_url, '/');

  FOR v_rec IN
    SELECT q.id, q.hr_emploc_id, q.attachment_id, q.bucket_id, q.storage_path, q.attempts
    FROM public.storage_cleanup_queue q
    WHERE q.status = 'pending'
      AND q.due_at <= now()
    ORDER BY q.due_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      v_target_url := format('%s/storage/v1/object/%s/%s', v_proj_url, v_rec.bucket_id, v_rec.storage_path);

      SELECT net.http_delete(
        url := v_target_url,
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_anon_or_srv,
          'apikey', v_anon_or_srv
        )
      ) INTO v_req_id;

      UPDATE public.storage_cleanup_queue
      SET status            = 'completed',
          processed_at      = now(),
          dispatched_at     = now(),
          pg_net_request_id = v_req_id,
          attempts          = v_rec.attempts + 1
      WHERE id = v_rec.id;

      IF v_rec.attachment_id IS NOT NULL THEN
        UPDATE public.hr_emploc_correction_attachments
        SET is_deleted     = true,
            deleted_at     = now(),
            deleted_reason = 'purged_by_cleanup_queue'
        WHERE id = v_rec.attachment_id;
      END IF;

      v_processed := v_processed + 1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.storage_cleanup_queue
      SET attempts   = v_rec.attempts + 1,
          status     = CASE WHEN (v_rec.attempts + 1) >= 5 THEN 'failed' ELSE 'pending' END,
          last_error = SQLERRM
      WHERE id = v_rec.id;
      v_failed := v_failed + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'ok',
    'processed', v_processed,
    'failed', v_failed
  );
END;
$function$;

DO $$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'process_storage_cleanup_queue';

    PERFORM cron.schedule(
      'process_storage_cleanup_queue',
      '*/15 * * * *',
      'SELECT public.process_storage_cleanup_queue(50);'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- 10. Modified workflow RPCs & helpers
CREATE OR REPLACE FUNCTION public._assign_and_deploy_emploc_core(p_hr_emploc_id uuid, p_employee_no text, p_confirm_reuse boolean DEFAULT false, p_reuse_reason text DEFAULT NULL::text, p_actor_profile_id uuid DEFAULT NULL::uuid, p_source_fn text DEFAULT 'assign_and_deploy_core'::text)
 RETURNS plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_profile_id uuid := COALESCE(p_actor_profile_id, public.get_my_profile_id());
  v_actor_name       text := public.get_my_full_name();
  v_clean_id         text := btrim(COALESCE(p_employee_no, ''));
  v_emp              public.hr_emploc;
  v_app              public.applicants;
  v_pl               public.plantilla;
  v_existing_pl      public.plantilla;
  v_slot_id          uuid := NULL;
  v_slot_auth        jsonb;
  v_pool_slot_id     uuid := NULL;
  v_is_pool          boolean := false;
  v_pool_type_id     uuid;
  v_home_account_id  uuid;
  v_home_acct        public.accounts;
  v_formatted_name   text;
  v_norm_name        text;
  v_reg              public.employee_number_registry;
  v_match            jsonb;
  v_is_rehire        boolean := false;
  v_dup_reg          public.employee_number_registry;
  v_dup_match        jsonb;
  r_cand             RECORD;
BEGIN
  -- 1. Format validation (rejects empty, spaces, (PENDING), invalid chars)
  IF v_clean_id = '' OR upper(v_clean_id) = '(PENDING)' OR v_clean_id !~ '^[A-Za-z0-9._-]+$' THEN
    RAISE EXCEPTION 'EMPLOYEE_NO_FORMAT_INVALID: Employee number "%" is invalid. Allowed: alphanumeric, dots, underscores, dashes.', v_clean_id
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'EMPLOYEE_NO_FORMAT_INVALID')::text;
  END IF;

  -- 2. Pending deletion lock
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  -- 3. Lock hr_emploc record
  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record % not found or archived', p_hr_emploc_id
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  -- 3b. Stage gate for Add Emploc (assign_hr_emploc_number):
  -- Decision 3: Assign from Pending is allowed ONLY for Super Admin (override); everyone else must wait for hr_status = 'For Emploc'.
  IF p_source_fn = 'assign_hr_emploc_number' THEN
    IF v_emp.hr_status = 'Pending' THEN
      IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'INVALID_STATE_FOR_ASSIGN: Record must be in "For Emploc" status before assigning an Employee ID (current hr_status: "Pending"). Ops must upload and submit requirements first.'
          USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE_FOR_ASSIGN')::text;
      END IF;
    ELSIF v_emp.hr_status NOT IN ('For Emploc', 'Complete') AND v_emp.status <> 'Moved to Plantilla' THEN
      RAISE EXCEPTION 'INVALID_STATE_FOR_ASSIGN: Cannot assign Employee ID from hr_status "%". Expected "For Emploc".', v_emp.hr_status
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE_FOR_ASSIGN')::text;
    END IF;
  END IF;

  -- Safe idempotent no-op check: already moved with same number
  IF v_emp.status = 'Moved to Plantilla' AND v_emp.employee_no = v_clean_id THEN
    SELECT * INTO v_existing_pl
    FROM public.plantilla
    WHERE hr_emploc_id = p_hr_emploc_id
      AND COALESCE(is_deleted, false) = false
    LIMIT 1;
    IF FOUND THEN
      RETURN v_existing_pl;
    END IF;
  END IF;

  -- Fetch structured applicant data
  IF v_emp.applicant_id IS NOT NULL THEN
    SELECT * INTO v_app FROM public.applicants WHERE id = v_emp.applicant_id;
  END IF;

  -- 4. REQUIRED PLANTILLA FIELDS VALIDATION (NO SILENT DEFAULTS)
  IF v_emp.hired_date IS NULL THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: hired_date is required before deployment to Plantilla'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'hired_date')::text;
  END IF;

  IF (v_app.first_name IS NULL OR btrim(v_app.first_name) = '') OR
     (v_app.last_name IS NULL OR btrim(v_app.last_name) = '') THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: applicant first_name and last_name are required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'applicant_name')::text;
  END IF;

  IF v_emp.account_id IS NULL AND (v_emp.account IS NULL OR btrim(v_emp.account) = '') THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: account is required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'account')::text;
  END IF;

  IF v_emp.position IS NULL OR btrim(v_emp.position) = '' THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: position is required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'position')::text;
  END IF;

  IF COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.store_id IS NULL AND (v_emp.store_name IS NULL OR btrim(v_emp.store_name) = '') THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: store is required for stationary deployment'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'store')::text;
    END IF;
    IF v_emp.store_id IS NULL THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: store_id is required for stationary deployment'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'store_id')::text;
    END IF;
  END IF;

  -- Resolve canonical formatted name and normalized name
  v_formatted_name := v_app.last_name || ', ' || v_app.first_name || COALESCE(' ' || NULLIF(btrim(v_app.middle_name), ''), '');
  v_norm_name      := public.fn_normalize_person_name(v_app.first_name, v_app.middle_name, v_app.last_name, NULL, NULL);

  -- 5. REGISTRY RACE-SAFE CHECK UNDER FOR UPDATE LOCK
  SELECT * INTO v_reg
  FROM public.employee_number_registry
  WHERE emploc_no = v_clean_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_reg.status IN ('assigned', 'rehire_reused') THEN
      v_match := public.fn_match_person_name(v_reg.normalized_name, v_norm_name);

      -- Rule a: Number registered to a different person -> HARD BLOCK
      IF (v_match->>'match')::boolean = false THEN
        RAISE EXCEPTION 'EMPLOYEE_NO_ALREADY_ASSIGNED: Employee number % is permanently registered to %',
          v_clean_id, v_reg.display_name
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_NO_ALREADY_ASSIGNED',
                  'employee_no', v_clean_id,
                  'registered_to', v_reg.display_name,
                  'registered_norm', v_reg.normalized_name,
                  'incoming_name', v_formatted_name,
                  'reason', v_match->>'reason'
                )::text;
      END IF;

      -- Rule b: Same person/number, but prior row is ACTIVE -> HARD BLOCK
      IF EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE (p.employee_no = v_clean_id OR p.emploc_no = v_clean_id)
          AND p.status IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation')
          AND COALESCE(p.is_deleted, false) = false
          AND (p.hr_emploc_id IS NULL OR p.hr_emploc_id <> p_hr_emploc_id)
      ) OR EXISTS (
        SELECT 1 FROM public.hr_emploc h
        WHERE (h.employee_no = v_clean_id OR h.emploc_no = v_clean_id)
          AND h.status NOT IN ('Backout', 'Moved to Plantilla')
          AND h.id <> p_hr_emploc_id
          AND h.deleted_at IS NULL
      ) THEN
        RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active placement or active Plantilla record with number %',
          v_formatted_name, v_clean_id
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_ALREADY_ACTIVE',
                  'employee_no', v_clean_id,
                  'person', v_formatted_name
                )::text;
      END IF;

      -- Middle-name warning check (one side missing middle name)
      IF (v_match->>'type') = 'WARNING_MISSING_MIDDLE' THEN
        IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
          RAISE EXCEPTION 'MIDDLE_NAME_CONFIRM_REQUIRED: % matches % on first and last name, but one record is missing a middle name. Confirm with reason.',
            v_formatted_name, v_reg.display_name
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'MIDDLE_NAME_CONFIRM_REQUIRED',
                    'employee_no', v_clean_id,
                    'registered_to', v_reg.display_name,
                    'incoming_name', v_formatted_name,
                    'reason', v_match->>'reason'
                  )::text;
        END IF;
      END IF;

      -- Rule c & Decision 1:
      -- If v_reg.source_hr_emploc_id = p_hr_emploc_id (same hr_emploc record re-assigning its own number after Revert to Pending),
      -- NO rehire confirm is required!
      -- Otherwise (a NEW hr_emploc record for a person who previously owned the number), require confirm + reason.
      IF v_reg.source_hr_emploc_id IS DISTINCT FROM p_hr_emploc_id THEN
        IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
          RAISE EXCEPTION 'REHIRE_CONFIRM_REQUIRED: % was previously assigned number %. Confirm rehire reuse with reason.',
            v_formatted_name, v_clean_id
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'REHIRE_CONFIRM_REQUIRED',
                    'employee_no', v_clean_id,
                    'display_name', v_reg.display_name,
                    'first_assigned_at', v_reg.first_assigned_at,
                    'status', v_reg.status
                  )::text;
        END IF;
        v_is_rehire := true;
      END IF;
    END IF;
  END IF;

  -- Rule b (person-wide active check across any other number) & Rule d (person already owns another number in registry)
  FOR r_cand IN (
    SELECT *
    FROM public.employee_number_registry reg
    WHERE reg.emploc_no <> v_clean_id
      AND reg.status IN ('assigned', 'rehire_reused')
      AND (
        split_part(reg.normalized_name, '|', 1) = split_part(v_norm_name, '|', 1)
        OR (split_part(reg.normalized_name, '|', 1) IN ('HAUTEA', 'HUATEA') AND split_part(v_norm_name, '|', 1) IN ('HAUTEA', 'HUATEA'))
        OR EXISTS (
          SELECT 1 FROM public.registry_name_aliases rna
          WHERE rna.normalized_name = reg.normalized_name OR rna.alias_normalized_name = reg.normalized_name
        )
      )
  ) LOOP
    v_dup_match := public.fn_match_person_name(r_cand.normalized_name, v_norm_name);
    IF (v_dup_match->>'match')::boolean = true THEN
      -- First check Rule b: if this same person has an active Plantilla or active hr_emploc under r_cand.emploc_no, HARD BLOCK!
      IF (v_dup_match->>'type') <> 'WARNING_MISSING_MIDDLE' AND (
        EXISTS (
          SELECT 1 FROM public.plantilla p
          WHERE (p.employee_no = r_cand.emploc_no OR p.emploc_no = r_cand.emploc_no)
            AND p.status IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation')
            AND COALESCE(p.is_deleted, false) = false
            AND (p.hr_emploc_id IS NULL OR p.hr_emploc_id <> p_hr_emploc_id)
        ) OR EXISTS (
          SELECT 1 FROM public.hr_emploc h
          WHERE (h.employee_no = r_cand.emploc_no OR h.emploc_no = r_cand.emploc_no)
            AND h.status NOT IN ('Backout', 'Moved to Plantilla')
            AND h.id <> p_hr_emploc_id
            AND h.deleted_at IS NULL
        )
      ) THEN
        RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active placement or active Plantilla record under Employee number %',
          v_formatted_name, r_cand.emploc_no
          USING ERRCODE = '23505',
                DETAIL = jsonb_build_object(
                  'code', 'EMPLOYEE_ALREADY_ACTIVE',
                  'employee_no', r_cand.emploc_no,
                  'person', v_formatted_name
                )::text;
      END IF;

      -- Rule d: Person owns another number (inactive) -> require confirmation + reason
      IF NOT p_confirm_reuse OR coalesce(btrim(p_reuse_reason), '') = '' THEN
        IF (v_dup_match->>'type') = 'WARNING_MISSING_MIDDLE' THEN
          RAISE EXCEPTION 'MIDDLE_NAME_CONFIRM_REQUIRED (POSSIBLE_DUPLICATE_PERSON): % matches % (Employee number %) on first and last name with one side missing middle name. Confirm with reason.',
            v_formatted_name, r_cand.display_name, r_cand.emploc_no
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'MIDDLE_NAME_CONFIRM_REQUIRED',
                    'secondary_code', 'POSSIBLE_DUPLICATE_PERSON',
                    'new_employee_no', v_clean_id,
                    'existing_employee_no', r_cand.emploc_no,
                    'display_name', r_cand.display_name
                  )::text;
        ELSE
          RAISE EXCEPTION 'POSSIBLE_DUPLICATE_PERSON: % is already registered with Employee number %. Confirm duplicate assignment with reason.',
            v_formatted_name, r_cand.emploc_no
            USING ERRCODE = '23505',
                  DETAIL = jsonb_build_object(
                    'code', 'POSSIBLE_DUPLICATE_PERSON',
                    'new_employee_no', v_clean_id,
                    'existing_employee_no', r_cand.emploc_no,
                    'display_name', r_cand.display_name,
                    'match_type', v_dup_match->>'type'
                  )::text;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- Also check Rule b against any active un-registered hr_emploc for the same person
  IF EXISTS (
    SELECT 1
    FROM public.hr_emploc h
    LEFT JOIN public.applicants a ON a.id = h.applicant_id
    WHERE h.id <> p_hr_emploc_id
      AND h.deleted_at IS NULL
      AND h.status NOT IN ('Backout', 'Moved to Plantilla')
      AND h.employee_no IS NOT NULL AND btrim(h.employee_no) <> ''
      AND (public.fn_match_person_name(
            public.fn_normalize_person_name(a.first_name, a.middle_name, a.last_name, NULL, coalesce(h.employee_name_snapshot, h.applicant_name)),
            v_norm_name
          )->>'match')::boolean = true
      AND (public.fn_match_person_name(
            public.fn_normalize_person_name(a.first_name, a.middle_name, a.last_name, NULL, coalesce(h.employee_name_snapshot, h.applicant_name)),
            v_norm_name
          )->>'type') <> 'WARNING_MISSING_MIDDLE'
  ) THEN
    RAISE EXCEPTION 'EMPLOYEE_ALREADY_ACTIVE: % already has an active hr_emploc record',
      v_formatted_name
      USING ERRCODE = '23505',
            DETAIL = jsonb_build_object(
              'code', 'EMPLOYEE_ALREADY_ACTIVE',
              'person', v_formatted_name
            )::text;
  END IF;

  -- 6. SLOT SELECTION AND RESERVATION (Stationary non-pool non-roving)
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    -- Prefer v_emp.slot_id first if already bound and open/hr_processing
    IF v_emp.slot_id IS NOT NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE id = v_emp.slot_id
        AND slot_status IN ('open', 'hr_processing')
      FOR UPDATE SKIP LOCKED;
    END IF;

    IF v_slot_id IS NULL THEN
      SELECT id INTO v_slot_id
      FROM public.plantilla_slots
      WHERE legacy_vcode = v_emp.vcode
        AND slot_status = 'open'
      ORDER BY created_at ASC
      LIMIT 1
      FOR UPDATE SKIP LOCKED;
    END IF;

    IF v_slot_id IS NULL THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: No available headcount slot for VCode %', v_emp.vcode
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'vcode', v_emp.vcode)::text;
    END IF;

    -- Reserve slot first
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id      => v_slot_id,
      p_new_status   => 'hr_processing',
      p_reason_code  => NULL,
      p_performed_by => v_actor_profile_id,
      p_remarks      => 'auto_move_to_plantilla: reserved for hr_emploc ' || p_hr_emploc_id::text
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: Slot % reservation blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'slot_id', v_slot_id, 'blocked_reason', v_slot_auth->>'blocked_reason')::text;
    END IF;
  END IF;

  -- 7. INSERT INTO PLANTILLA
  IF v_is_pool THEN
    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;

    INSERT INTO plantilla (
      account,              account_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,             last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      is_pool_employee,     pool_type_id,
      requesting_account,   requesting_account_id,   requesting_store_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_home_acct.account_name, v_home_acct.id,
      NULL, NULL,
      v_emp.position,           v_emp.position_id_snapshot,
      v_clean_id,               v_clean_id,
      v_formatted_name,         v_formatted_name,
      v_app.first_name,         v_app.middle_name,       v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,       v_emp.philhealth_snapshot,    v_emp.pagibig_snapshot,
      v_emp.hired_date,         v_emp.vacancy_id,             v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,          v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot,  v_emp.area_name_snapshot,
      v_emp.id,
      true,                     v_pool_type_id,
      v_emp.account,            v_emp.account_id,             v_emp.store_id,
      'Active',                 CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

  ELSIF COALESCE(v_emp.assignment_type, 'Stationary') = 'Roving' THEN
    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,          last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,         pagibig_no,
      date_hired,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      roving_assignment_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,            updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
      v_emp.position, v_emp.position_id_snapshot,
      v_clean_id, v_clean_id,
      v_formatted_name, v_formatted_name,
      v_app.first_name, v_app.middle_name, v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.roving_assignment_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

  ELSE
    -- Pure stationary path
    INSERT INTO plantilla (
      account,              account_id,            chain_id,             store_id,
      store_name,           position,              position_id,
      province_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      first_name,           middle_name,           last_name,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account,        v_emp.account_id,       v_emp.chain_id,       v_emp.store_id,
      v_emp.store_name,     v_emp.position,         v_emp.position_id_snapshot,
      v_emp.province_id,
      v_clean_id,           v_clean_id,
      v_formatted_name,     v_formatted_name,
      v_app.first_name,     v_app.middle_name,      v_app.last_name,
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,   v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,     v_emp.vacancy_id,        v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,      v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      'Active',             CURRENT_DATE,
      v_actor_profile_id, v_actor_profile_id, v_actor_profile_id, NOW(), NOW()
    )
    RETURNING * INTO v_pl;
  END IF;

  -- 8. FINALIZE SLOT AS 'occupied' (RECONCILED VALUE)
  IF v_slot_id IS NOT NULL THEN
    v_slot_auth := public.fn_set_slot_status(
      p_slot_id               => v_slot_id,
      p_new_status            => 'occupied',
      p_reason_code           => NULL,
      p_performed_by          => v_actor_profile_id,
      p_remarks               => 'auto_move_to_plantilla: slot occupied by plantilla ' || v_pl.id::text,
      p_occupant_plantilla_id => v_pl.id
    );
    IF (v_slot_auth->>'status') NOT IN ('ok', 'no_op') THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE: Slot % occupancy blocked: %',
        v_slot_id, COALESCE(v_slot_auth->>'blocked_reason', 'unknown')
        USING ERRCODE = '22023',
              DETAIL = jsonb_build_object('code', 'SLOT_UNAVAILABLE', 'slot_id', v_slot_id, 'blocked_reason', v_slot_auth->>'blocked_reason')::text;
    END IF;
  END IF;

  -- 9. VACANCY CLOSURE (if all slots filled)
  IF NOT v_is_pool AND COALESCE(v_emp.assignment_type, 'Stationary') <> 'Roving' AND v_emp.coverage_slot_id IS NULL THEN
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE public.vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor_profile_id
       WHERE id = v_emp.vacancy_id
         AND NOT EXISTS (
           SELECT 1 FROM public.plantilla_slots ps
           WHERE ps.legacy_vcode = v_emp.vcode
             AND ps.is_roving    = false
             AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
         );
    END IF;

    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor_profile_id
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.plantilla_slots ps
         WHERE ps.legacy_vcode = v_emp.vcode
           AND ps.is_roving    = false
           AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
       );
  END IF;

  -- 10. STAMP REGISTRY BEFORE HR_EMPLOC UPDATE (so trigger sees registered entry)
  INSERT INTO public.employee_number_registry (
    emploc_no, normalized_name, display_name, status,
    first_assigned_at, first_assigned_by, last_assigned_at, last_assigned_by,
    source_hr_emploc_id, source_plantilla_id,
    history
  ) VALUES (
    v_clean_id, v_norm_name, v_formatted_name,
    CASE WHEN v_is_rehire THEN 'rehire_reused' ELSE 'assigned' END,
    NOW(), v_actor_profile_id, NOW(), v_actor_profile_id,
    p_hr_emploc_id, v_pl.id,
    jsonb_build_array(
      jsonb_build_object(
        'action', CASE WHEN v_is_rehire THEN 'rehire_reuse' ELSE 'initial_assignment' END,
        'actor', v_actor_profile_id,
        'timestamp', now(),
        'source', p_source_fn,
        'reuse_reason', p_reuse_reason
      )
    )
  )
  ON CONFLICT (emploc_no) DO UPDATE SET
    normalized_name     = EXCLUDED.normalized_name,
    display_name        = EXCLUDED.display_name,
    status              = EXCLUDED.status,
    last_assigned_at    = NOW(),
    last_assigned_by    = v_actor_profile_id,
    source_hr_emploc_id = p_hr_emploc_id,
    source_plantilla_id = v_pl.id,
    history             = public.employee_number_registry.history || EXCLUDED.history;

  -- 11. UPDATE HR_EMPLOC STATUS (Final: Moved to Plantilla / Transferred)
  UPDATE public.hr_emploc
     SET employee_no           = v_clean_id,
         emploc_no             = v_clean_id,
         status                = 'Moved to Plantilla',
         hr_status             = 'Transferred',
         moved_to_plantilla_at = NOW(),
         moved_to_plantilla_by = v_actor_profile_id,
         updated_at            = NOW(),
         updated_by            = v_actor_profile_id
   WHERE id = p_hr_emploc_id;

  -- 11b. ENQUEUE 3-DAY DOCUMENT PURGE (never rolls back deployment on error)
  BEGIN
    PERFORM public.enqueue_hr_emploc_docs_cleanup(p_hr_emploc_id, 'deployed_3day_ttl', interval '3 days');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- 12. SINGLE AUDIT / TIMELINE LOG ENTRY
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_emp),
    jsonb_build_object(
      'action', 'assign_and_move_to_plantilla',
      'employee_no', v_clean_id,
      'plantilla_id', v_pl.id,
      'actor_name', v_actor_name,
      'actor_id', v_actor_profile_id,
      'source', p_source_fn,
      'log_message', format('Assigned Employee ID %s and automatically moved to Plantilla (Slot %s) by %s', v_clean_id, coalesce(v_slot_id::text, 'Pool/Roving'), v_actor_name)
    )
  );

  RETURN v_pl;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.tag_web_hr_emploc_deficiency(p_hr_emploc_id uuid, p_deficiencies jsonb, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid      uuid    := auth.uid();
  v_profile_id    uuid    := public.get_my_profile_id();
  v_actor_name    text    := public.get_my_full_name();
  v_old           public.hr_emploc;
  v_new           public.hr_emploc;
  v_issue         jsonb;
  v_code          text;
  v_comment       text;
  v_needs_comment boolean;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: deficiency tagging requires a valid session'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'UNAUTHENTICATED')::text;
  END IF;

  -- Gate: HR Personnel (+SA) ONLY. Head Admin and Encoder NOT allowed.
  IF NOT public.can_tag_or_review_hr_emploc() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: HR Personnel or Super Admin role required for deficiency tagging'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  IF p_deficiencies IS NULL
     OR jsonb_typeof(p_deficiencies) <> 'array'
     OR jsonb_array_length(p_deficiencies) = 0 THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: p_deficiencies must be a non-empty JSONB array of {code, comment} objects'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'deficiencies')::text;
  END IF;

  FOR v_issue IN SELECT * FROM jsonb_array_elements(p_deficiencies) LOOP
    v_code    := NULLIF(BTRIM(COALESCE(v_issue->>'code', '')), '');
    v_comment := BTRIM(COALESCE(v_issue->>'comment', ''));

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: each deficiency must contain a non-empty code'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'deficiency_code')::text;
    END IF;

    SELECT it.requires_comment INTO v_needs_comment
    FROM   public.hr_emploc_issue_types it
    WHERE  it.code = v_code AND it.is_active = TRUE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'INVALID_DEFICIENCY_CODE: unknown or inactive deficiency code: %', v_code
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_DEFICIENCY_CODE')::text;
    END IF;

    IF v_needs_comment AND (v_comment IS NULL OR v_comment = '') THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: deficiency code % requires a non-empty comment', v_code
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'comment', 'deficiency_code', v_code)::text;
    END IF;
  END LOOP;

  SELECT * INTO v_old
  FROM   public.hr_emploc
  WHERE  id = p_hr_emploc_id
  FOR UPDATE;

  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record not found or archived'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests dr
    WHERE dr.hr_emploc_id = p_hr_emploc_id AND dr.status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF v_old.status = 'Moved to Plantilla' OR v_old.hr_status = 'Transferred' THEN
    RAISE EXCEPTION 'INVALID_STATE_FOR_DEFICIENCY: cannot tag deficiency on record already deployed to Plantilla'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE_FOR_DEFICIENCY')::text;
  END IF;

  IF v_old.hr_status <> 'For Emploc' THEN
    RAISE EXCEPTION 'INVALID_STATE_FOR_DEFICIENCY: deficiency tagging requires hr_status = "For Emploc" (current: "%")', v_old.hr_status
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE_FOR_DEFICIENCY')::text;
  END IF;

  UPDATE public.hr_emploc
  SET    hr_status              = 'For Correction',
         correction_reason      = p_deficiencies,
         hr_remarks             = NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
         hr_reviewed_at         = now(),
         hr_reviewed_by         = v_actor_name,
         hr_reviewed_by_user_id = v_profile_id,
         updated_at             = now(),
         updated_by             = v_profile_id
  WHERE  id = p_hr_emploc_id
  RETURNING * INTO v_new;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    to_jsonb(v_old),
    jsonb_build_object(
      'action', 'tag_deficiency',
      'deficiencies', p_deficiencies,
      'remarks', p_remarks,
      'actor_name', v_actor_name,
      'actor_id', v_profile_id,
      'log_message', format('Tagged %s deficiency items by %s', jsonb_array_length(p_deficiencies), v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'hr_emploc_id', p_hr_emploc_id,
    'hr_status', v_new.hr_status,
    'correction_reason', v_new.correction_reason
  );
END;
$function$

;

CREATE OR REPLACE FUNCTION public.submit_correction(p_id uuid, p_ops_remark text)
 RETURNS hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_old public.hr_emploc;
  v_new public.hr_emploc;
BEGIN
  -- Gate: Ops only: OM, TL, ATL, HRCO (+SA). HA, Encoder, HR Personnel NOT allowed.
  IF NOT public.can_submit_hr_emploc_correction() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: Ops role required' USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  IF coalesce(btrim(p_ops_remark), '') = '' THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: ops remark is required' USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'ops_remark')::text;
  END IF;

  SELECT * INTO v_old FROM public.hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  IF public.has_pending_deletion_request(p_id) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF NOT public.is_super_admin() AND NOT public.is_hr_emploc_in_my_scope(p_id) THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: record is outside your assigned account/group scope'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  IF v_old.hr_status <> 'For Correction' THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot submit correction: hr_status is %', v_old.hr_status USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE')::text;
  END IF;

  UPDATE public.hr_emploc
     SET hr_status   = 'For Review',
         ops_remarks = btrim(p_ops_remark),
         updated_at  = now(),
         updated_by  = public.get_my_profile_id()
   WHERE id = p_id
   RETURNING * INTO v_new;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_id,
    to_jsonb(v_old),
    jsonb_build_object(
      'action', 'submit_correction',
      'ops_remarks', btrim(p_ops_remark),
      'actor_name', public.get_my_full_name(),
      'actor_id', public.get_my_profile_id(),
      'log_message', format('Ops submitted correction update: %s', btrim(p_ops_remark))
    )
  );

  RETURN v_new;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.submit_hrco_correction_update(p_correction_request_id uuid, p_hrco_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Gate: Ops only: OM, TL, ATL, HRCO (+SA). HA, Encoder, HR Personnel NOT allowed.
  IF NOT public.can_submit_hr_emploc_correction() THEN
    RAISE EXCEPTION 'forbidden: Ops role (OM, HRCO, ATL, TL) required' USING ERRCODE = '42501';
  END IF;

  IF public.has_pending_deletion_request(p_correction_request_id) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF NOT public.is_super_admin() AND NOT public.is_hr_emploc_in_my_scope(p_correction_request_id) THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: record is outside your assigned account/group scope'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  UPDATE public.hr_emploc
  SET ops_remarks = nullif(trim(p_hrco_notes), ''),
      hr_status   = 'For Review',
      updated_at  = now(),
      updated_by  = public.get_my_profile_id()
  WHERE id = p_correction_request_id
    AND hr_status = 'For Correction';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Correction request not found or not in For Correction status'
      USING ERRCODE = 'P0002';
  END IF;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.reject_correction_request(p_correction_request_id uuid, p_hr_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_row   public.hr_emploc%rowtype;
  v_actor public.users_profile%rowtype;
  v_actor_role text;
BEGIN
  IF NOT public.can_tag_or_review_hr_emploc() THEN
    RAISE EXCEPTION 'Unauthorized: only Super Admin or HR Personnel can reject correction review'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_actor
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true
  LIMIT 1;

  v_actor_role := coalesce(public.get_my_role(), v_actor.role, '');

  IF v_actor.id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: active user profile not found'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.hr_emploc
  WHERE id = p_correction_request_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: HR Emploc correction request not found'
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  IF public.has_pending_deletion_request(p_correction_request_id) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF coalesce(v_row.hr_status, '') <> 'For Review' THEN
    RAISE EXCEPTION 'Only For Review correction requests can be rejected back to For Correction. Current status: %',
      coalesce(v_row.hr_status, 'NULL')
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.hr_emploc
  SET
    hr_status              = 'For Correction',
    status                 = CASE
                               WHEN status = 'Ready for Plantilla' AND emploc_no IS NULL
                               THEN 'Pending Requirements'
                               ELSE status
                             END,
    hr_remarks             = nullif(trim(coalesce(p_hr_remarks, '')), ''),
    hr_rejection_reason    = nullif(trim(coalesce(p_hr_remarks, '')), ''),
    hr_reviewed_by         = coalesce(v_actor.full_name, v_actor.email, auth.uid()::text),
    hr_reviewed_by_user_id = v_actor.id,
    hr_reviewed_at         = now(),
    updated_by             = v_actor.id,
    updated_at             = now()
  WHERE id = p_correction_request_id
  RETURNING * INTO v_row;

  INSERT INTO public.activity_log (
    actor_id, actor_name, actor_role, action,
    target_table, target_id, target_name,
    old_value, new_value, created_at
  ) VALUES (
    v_actor.id,
    coalesce(v_actor.full_name, v_actor.email),
    v_actor_role,
    'HR Emploc correction rejected to For Correction',
    'hr_emploc',
    v_row.id,
    v_row.applicant_name,
    jsonb_build_object('hr_status', 'For Review'),
    jsonb_build_object('hr_status', v_row.hr_status, 'hr_remarks', v_row.hr_remarks),
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'id', v_row.id,
    'hr_status', v_row.hr_status,
    'status', v_row.status,
    'message', 'Correction request returned to For Correction.'
  );
END;
$function$

;

CREATE OR REPLACE FUNCTION public.reopen_correction_request(p_correction_request_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.can_tag_or_review_hr_emploc() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: HR Personnel or Super Admin required'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  IF public.has_pending_deletion_request(p_correction_request_id) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  UPDATE public.hr_emploc
  SET
    hr_status = 'For Correction',
    updated_at = now()
  WHERE id = p_correction_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Correction request not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.revert_hr_emploc_to_pending(p_hr_emploc_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_profile_id uuid := public.get_my_profile_id();
  v_actor_name       text := public.get_my_full_name();
  v_reason           text := btrim(coalesce(p_reason, ''));
  v_emp              public.hr_emploc;
  v_pl               public.plantilla;
  v_vcode            text;
  v_active_docs      bigint := 0;
  v_restored_status  text := 'Pending';
BEGIN
  IF v_reason = '' THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: Reason for revert is required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'reason')::text;
  END IF;

  -- Gate: Data Team (Encoder, Head Admin) or Super Admin ONLY (Decision 7)
  IF NOT public.can_edit_deployed_hr_emploc() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: Data Team (Encoder, Head Admin) or Super Admin required'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: Record not found or archived'
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  v_vcode := v_emp.vcode;

  -- 1. Soft-delete Plantilla row
  SELECT * INTO v_pl FROM public.plantilla
  WHERE hr_emploc_id = p_hr_emploc_id AND coalesce(is_deleted, false) = false
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.plantilla
    SET is_deleted = true,
        status     = 'Deactivated',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE id = v_pl.id;

    UPDATE public.plantilla_store_links
    SET status      = 'Backed Out',
        unlinked_at = now(),
        unlinked_by = v_actor_profile_id,
        updated_at  = now(),
        updated_by  = v_actor_profile_id
    WHERE plantilla_id = v_pl.id;

    -- Re-open slot
    UPDATE public.plantilla_slots
    SET slot_status                   = 'open',
        current_occupant_plantilla_id = NULL,
        updated_at                    = now(),
        updated_by                    = v_actor_profile_id
    WHERE current_occupant_plantilla_id = v_pl.id;
  END IF;

  -- Reconcile Vacancy if needed
  IF v_vcode IS NOT NULL THEN
    UPDATE public.vacancies
    SET status     = 'Open',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE vcode = v_vcode
      AND status IN ('Filled', 'Closed')
      AND coalesce(is_archived, false) = false
      AND deleted_at IS NULL;
  END IF;

  -- Decision 1: Keep number reserved to this person & source_hr_emploc_id in registry
  -- (status stays 'assigned' so another person cannot steal it, while the same hr_emploc + same person
  -- can re-assign the same number without REHIRE_CONFIRM_REQUIRED).
  IF v_emp.employee_no IS NOT NULL AND btrim(v_emp.employee_no) <> '' THEN
    UPDATE public.employee_number_registry
    SET updated_at = now(),
        history = history || jsonb_build_object(
          'action', 'revert_to_pending',
          'actor', v_actor_profile_id,
          'timestamp', now(),
          'reason', v_reason
        )
    WHERE emploc_no = btrim(v_emp.employee_no);
  END IF;

  -- Decision 6: Cancel queued purge; if unpurged docs remain, restore hr_status = 'For Emploc'; else 'Pending'
  UPDATE public.storage_cleanup_queue
  SET status           = 'cancelled',
      cancelled_at     = now(),
      cancelled_reason = 'reverted_to_pending: ' || v_reason
  WHERE hr_emploc_id = p_hr_emploc_id
    AND status IN ('pending', 'dispatched');

  SELECT count(*) INTO v_active_docs
  FROM public.hr_emploc_correction_attachments ca
  WHERE ca.hr_emploc_id = p_hr_emploc_id
    AND ca.is_deleted = false
    AND ca.deleted_at IS NULL;

  v_restored_status := CASE WHEN v_active_docs > 0 THEN 'For Emploc' ELSE 'Pending' END;

  -- Revert hr_emploc record to Pending Emploc (with hr_status = For Emploc or Pending)
  UPDATE public.hr_emploc
  SET employee_no           = NULL,
      emploc_no             = NULL,
      status                = 'Pending Emploc',
      hr_status             = v_restored_status,
      moved_to_plantilla_at = NULL,
      moved_to_plantilla_by = NULL,
      updated_at            = now(),
      updated_by            = v_actor_profile_id
  WHERE id = p_hr_emploc_id;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    jsonb_build_object('status', v_emp.status, 'hr_status', v_emp.hr_status, 'employee_no', v_emp.employee_no),
    jsonb_build_object(
      'action', 'revert_to_pending',
      'reason', v_reason,
      'restored_hr_status', v_restored_status,
      'active_doc_count', v_active_docs,
      'log_message', format('Reverted record to %s (Reason: %s) by %s', v_restored_status, v_reason, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'hr_emploc_id', p_hr_emploc_id,
    'restored_hr_status', v_restored_status,
    'active_doc_count', v_active_docs,
    'message', format('Record reverted to %s', v_restored_status)
  );
END;
$function$

;

CREATE OR REPLACE FUNCTION public.review_web_hr_emploc_correction(p_hr_emploc_id uuid, p_decision text, p_resolved_keys jsonb DEFAULT NULL::jsonb, p_remarks text DEFAULT NULL::text, p_employee_no text DEFAULT NULL::text, p_confirm_reuse boolean DEFAULT false, p_reuse_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid          uuid := auth.uid();
  v_profile_id        uuid := public.get_my_profile_id();
  v_actor_name        text := public.get_my_full_name();
  v_old               public.hr_emploc;
  v_new               public.hr_emploc;
  v_decision          text;
  v_clean_remarks     text;
  v_clean_employee_no text;
  v_pl                public.plantilla;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: correction review requires a valid session'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'UNAUTHENTICATED')::text;
  END IF;

  -- Gate: HR Personnel (+SA) ONLY. Head Admin and Encoder NOT allowed.
  IF NOT public.can_tag_or_review_hr_emploc() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: HR Personnel or Super Admin role required for correction review'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  v_decision := lower(btrim(coalesce(p_decision, '')));
  IF v_decision NOT IN ('approve', 'return') THEN
    RAISE EXCEPTION 'INVALID_DECISION: invalid decision: must be "approve" or "return"'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_DECISION')::text;
  END IF;

  SELECT * INTO v_old FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: hr_emploc record not found or archived'
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  -- Pending deletion lock
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests dr
    WHERE dr.hr_emploc_id = p_hr_emploc_id AND dr.status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF v_old.hr_status <> 'For Review' THEN
    RAISE EXCEPTION 'INVALID_STATE: record hr_status is "%", expected "For Review"', v_old.hr_status
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STATE')::text;
  END IF;

  v_clean_remarks := NULLIF(btrim(coalesce(p_remarks, '')), '');

  IF v_decision = 'approve' THEN
    v_clean_employee_no := NULLIF(btrim(coalesce(p_employee_no, '')), '');
    IF v_clean_employee_no IS NULL THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: Employee ID is required to approve correction and deploy to Plantilla'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'employee_no')::text;
    END IF;

    -- Clear deficiencies and update review metadata
    UPDATE public.hr_emploc
       SET correction_reason      = NULL,
           hr_remarks             = v_clean_remarks,
           hr_reviewed_at         = now(),
           hr_reviewed_by         = v_actor_name,
           hr_reviewed_by_user_id = v_profile_id,
           updated_at             = now(),
           updated_by             = v_profile_id
     WHERE id = p_hr_emploc_id;

    -- Delegate to core: validates format, registry, required Plantilla fields, slot, and deploys atomically
    v_pl := public._assign_and_deploy_emploc_core(
      p_hr_emploc_id     => p_hr_emploc_id,
      p_employee_no      => v_clean_employee_no,
      p_confirm_reuse    => p_confirm_reuse,
      p_reuse_reason     => p_reuse_reason,
      p_actor_profile_id => v_profile_id,
      p_source_fn        => 'review_web_hr_emploc_correction_approve'
    );

    SELECT * INTO v_new FROM public.hr_emploc WHERE id = p_hr_emploc_id;

    RETURN jsonb_build_object(
      'status', 'ok',
      'decision', 'approve',
      'hr_emploc_id', p_hr_emploc_id,
      'hr_status', v_new.hr_status,
      'deployment_status', v_new.status,
      'employee_no', v_new.employee_no,
      'plantilla_id', v_pl.id
    );

  ELSE -- decision = 'return'
    IF v_clean_remarks IS NULL THEN
      RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: remarks are required when returning a correction'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'remarks')::text;
    END IF;

    UPDATE public.hr_emploc
       SET hr_status              = 'For Correction',
           hr_remarks             = v_clean_remarks,
           hr_reviewed_at         = now(),
           hr_reviewed_by         = v_actor_name,
           hr_reviewed_by_user_id = v_profile_id,
           updated_at             = now(),
           updated_by             = v_profile_id
     WHERE id = p_hr_emploc_id
     RETURNING * INTO v_new;

    PERFORM public.log_audit_event(
      'hr_emploc',
      'UPDATE',
      p_hr_emploc_id,
      to_jsonb(v_old),
      jsonb_build_object(
        'action', 'return_to_correction',
        'actor_name', v_actor_name,
        'actor_id', v_profile_id,
        'remarks', v_clean_remarks,
        'log_message', format('Returned correction to Ops with remarks: %s', v_clean_remarks)
      )
    );

    RETURN jsonb_build_object(
      'status', 'ok',
      'decision', 'return',
      'hr_emploc_id', p_hr_emploc_id,
      'hr_status', v_new.hr_status,
      'deployment_status', v_new.status
    );
  END IF;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.assign_hr_emploc_number(p_id uuid, p_employee_no text, p_confirm_reuse boolean DEFAULT false, p_reuse_reason text DEFAULT NULL::text)
 RETURNS hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_res public.hr_emploc;
BEGIN
  -- Gate: HR Personnel, Head Admin, Encoder, Super Admin
  IF NOT public.can_assign_pending_hr_emploc() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: HR Personnel, Head Admin, Encoder, or Super Admin role required'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  PERFORM public._assign_and_deploy_emploc_core(
    p_hr_emploc_id     => p_id,
    p_employee_no      => p_employee_no,
    p_confirm_reuse    => p_confirm_reuse,
    p_reuse_reason     => p_reuse_reason,
    p_actor_profile_id => public.get_my_profile_id(),
    p_source_fn        => 'assign_hr_emploc_number'
  );

  SELECT * INTO v_res FROM public.hr_emploc WHERE id = p_id;
  RETURN v_res;
END;
$function$

;

-- 11. View & Summary RPCs
CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(p_queue text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_deficiency text DEFAULT NULL::text, p_sla_filter text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_sort_by text DEFAULT 'date_requested'::text, p_sort_dir text DEFAULT 'desc'::text)
 RETURNS TABLE(hr_emploc_id uuid, applicant_name text, vcode text, account_id uuid, account_name text, group_id uuid, group_name text, store_id uuid, store_name text, position_title text, hr_status text, status text, emploc_no text, employee_no text, date_requested timestamp with time zone, created_at timestamp with time zone, hired_date date, assignment_type text, roving_assignment_id uuid, aging_days integer, sla_breached boolean, sla_status text, sla_deadline timestamp with time zone, deficiency_summary jsonb, is_pending_deletion boolean, row_capabilities jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'date_requested'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(public.get_my_role(), r.role_name), COALESCE(public.get_my_role_level(), r.role_level)
  INTO   v_profile_id, v_role_name, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active = TRUE
    AND  up.archived_at IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.id AS hr_emploc_id,
      h.applicant_name,
      h.vcode,
      h.account_id,
      a.account_name,
      a.group_id,
      g.group_name,
      h.store_id,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.hr_status,
      h.status,
      h.emploc_no,
      h.employee_no,
      h.date_requested,
      h.created_at,
      h.hired_date,
      h.assignment_type::text AS assignment_type,
      h.roving_assignment_id,
      h.deleted_at,
      h.moved_to_plantilla_at,
      
      GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(h.date_requested, h.created_at))))::integer) AS aging_days,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status,
      
      (COALESCE(h.date_requested, h.created_at) + INTERVAL '3 days') AS sla_deadline,
      
      CASE
        WHEN h.correction_reason IS NULL THEN jsonb_build_object('active_count', 0, 'issues', '[]'::jsonb)
        ELSE jsonb_build_object(
          'active_count', CASE WHEN jsonb_typeof(h.correction_reason) = 'array' THEN jsonb_array_length(h.correction_reason) ELSE 1 END,
          'issues', CASE
            WHEN jsonb_typeof(h.correction_reason) = 'array' THEN (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'code', el->>'code',
                  'comment', el->>'comment',
                  'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = el->>'code'), el->>'code')
                )
              )
              FROM jsonb_array_elements(h.correction_reason) el
            )
            ELSE jsonb_build_array(
              jsonb_build_object(
                'code', h.correction_reason->>'type',
                'comment', h.correction_reason->>'comment',
                'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = h.correction_reason->>'type'), h.correction_reason->>'type')
              )
            )
          END
        )
      END AS deficiency_summary,
      
      EXISTS (
        SELECT 1 FROM public.hr_emploc_deletion_requests dr
        WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
      ) AS is_pending_deletion,
      
      jsonb_build_object(
        'can_view_detail', true,
        'hrco_name', COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)),
        'remarks', COALESCE(h.ops_remarks, h.hr_remarks),
        'ops_remarks', h.ops_remarks,
        'hr_remarks', h.hr_remarks,
        'attachment_url', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
          ELSE (
            SELECT ca.storage_path
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
            ORDER BY ca.uploaded_at DESC
            LIMIT 1
          )
        END,
        'attachment_file_name', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') OR NOT public.can_view_hr_emploc_docs(h.id) THEN NULL
          ELSE (
            SELECT ca.original_filename
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
            ORDER BY ca.uploaded_at DESC
            LIMIT 1
          )
        END,
        'doc_count', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') THEN 0
          ELSE (
            SELECT count(*)::int
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          )
        END,
        'attachments', CASE
          WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') OR NOT public.can_view_hr_emploc_docs(h.id) THEN '[]'::jsonb
          ELSE COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', ca.id,
                'original_filename', ca.original_filename,
                'mime_type', ca.mime_type,
                'size_bytes', ca.size_bytes,
                'stage', ca.stage,
                'storage_path', ca.storage_path,
                'object_path', regexp_replace(ca.storage_path, '^hr-corrections/', ''),
                'uploaded_by', ca.uploaded_by,
                'uploaded_at', ca.uploaded_at,
                'created_at', ca.created_at,
                'can_remove', (
                  public.can_upload_hr_emploc_docs(h.id)
                  AND (public.is_super_admin() OR ca.uploaded_by = v_profile_id)
                )
              ) ORDER BY ca.uploaded_at DESC
            )
            FROM public.hr_emploc_correction_attachments ca
            WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
          ), '[]'::jsonb)
        END,
        'can_upload_docs', public.can_upload_hr_emploc_docs(h.id),
        'can_submit_requirements', (
          public.can_upload_hr_emploc_docs(h.id)
          AND h.hr_status = 'Pending'
        ),
        'can_view_docs', public.can_view_hr_emploc_docs(h.id),
        'can_edit_emploc', (
          public.can_edit_deployed_hr_emploc()
          AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
        ),
        'can_revert_to_pending', (
          public.can_edit_deployed_hr_emploc()
          AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
        ),
        'can_request_deletion', (
          h.status <> 'Moved to Plantilla'
          AND h.hr_status <> 'Pending Deletion'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
          AND (v_role_level >= 70 OR v_role_name IN ('OM', 'HRCO', 'ATL', 'TL', 'ATL/TL') OR public.i_am_ops() OR public.i_have_full_access())
        ),
        'can_withdraw_deletion_request', (
          EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
          AND (
            public.i_have_full_access()
            OR EXISTS (
              SELECT 1 FROM public.hr_emploc_deletion_requests dr
              WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending' AND dr.requested_by_user_id = v_profile_id
            )
          )
        ),
        'can_review_deletion', (
          (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
          AND EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_approve_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_revert_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
          )
        ),
        'can_review_correction', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Review'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        ),
        'can_submit_correction', (
          public.can_upload_hr_emploc_docs(h.id)
          AND h.hr_status = 'For Correction'
        ),
        'can_move_to_plantilla', false,
        'can_tag_deficiency', (
          public.can_tag_or_review_hr_emploc()
          AND h.hr_status = 'For Emploc'
          AND h.status <> 'Moved to Plantilla'
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        ),
        'can_assign_employee_no', (
          public.can_assign_pending_hr_emploc()
          AND COALESCE(h.employee_no, '') = ''
          AND h.status <> 'Moved to Plantilla'
          AND (
            h.hr_status = 'For Emploc'
            OR (h.hr_status = 'Pending' AND public.is_super_admin())
          )
          AND NOT EXISTS (
            SELECT 1
            FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id
              AND dr.status = 'Pending'
          )
        )
      ) AS row_capabilities
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      -- Queue Filter (including 'for_emploc', 'deployed', etc.)
      (p_queue IS NULL
       OR (p_queue = 'pending' AND s.hr_status = 'Pending' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'for_emploc' AND s.hr_status = 'For Emploc' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'correction' AND s.hr_status = 'For Correction' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue = 'review' AND s.hr_status = 'For Review' AND s.status <> 'Backout' AND s.deleted_at IS NULL)
       OR (p_queue IN ('deployed', 'transferred') AND (
            s.status = 'Moved to Plantilla'
            OR s.hr_status = 'Transferred'
          )
          AND s.status <> 'Backout'
          AND s.deleted_at IS NULL
       )
       OR (p_queue = 'rejected' AND s.hr_status = 'Rejected' AND s.deleted_at IS NULL)
      )
      AND (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.deficiency_summary->'active_count' > '0'::jsonb)
       OR (p_deficiency = 'none' AND s.deficiency_summary->'active_count' = '0'::jsonb)
       OR (
         s.deficiency_summary->'active_count' > '0'::jsonb AND EXISTS (
           SELECT 1 FROM jsonb_array_elements(s.deficiency_summary->'issues') el
           WHERE el->>'code' = p_deficiency
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_status IS NULL OR s.status = p_status)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.applicant_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.emploc_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.hrco_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.hr_emploc_id,
    c.applicant_name,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.hr_status,
    c.status,
    c.emploc_no,
    c.employee_no,
    c.date_requested,
    c.created_at,
    c.hired_date,
    c.assignment_type,
    c.roving_assignment_id,
    c.aging_days,
    c.sla_breached,
    c.sla_status,
    c.sla_deadline,
    c.deficiency_summary,
    c.is_pending_deletion,
    c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'applicant_name'   THEN c.applicant_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'applicant_name'   THEN c.applicant_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title'   THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title'   THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'hr_status'        THEN c.hr_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'hr_status'        THEN c.hr_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'status'           THEN c.status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'status'           THEN c.status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'emploc_no'        THEN c.emploc_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'emploc_no'        THEN c.emploc_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_no'      THEN c.employee_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_no'      THEN c.employee_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'date_requested'   THEN c.date_requested END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'date_requested'   THEN c.date_requested END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'created_at'       THEN c.created_at END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'created_at'       THEN c.created_at END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    c.created_at DESC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_detail(p_hr_emploc_id uuid)
 RETURNS TABLE(hr_emploc_id uuid, applicant_name text, vcode text, vacancy_id uuid, vacancy_code_snapshot text, position_id_snapshot uuid, position_title text, assignment_type text, roving_assignment_id uuid, covered_stores jsonb, account_id uuid, account_name text, group_id uuid, group_name text, store_id uuid, store_name text, hr_status text, status text, emploc_no text, employee_no text, date_requested timestamp with time zone, created_at timestamp with time zone, hired_date date, deployed_by_user_id uuid, hrco_user_id_snapshot uuid, hrco_name text, employee_lookup_found boolean, employee_lookup_synced_at timestamp with time zone, employee_lookup_remarks text, employee_name_snapshot text, birthdate_snapshot date, civil_status_snapshot text, requirement_overall_status text, ops_remarks text, hr_remarks text, hr_rejection_reason text, hr_reviewed_by text, hr_reviewed_at timestamp with time zone, deficiency_summary jsonb, correction_reason jsonb, correction_attachments jsonb, deletion_request jsonb, sla_breached boolean, sla_status text, sla_deadline timestamp with time zone, aging_days integer, timeline jsonb, row_capabilities jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  -- Direct SQL/anon safety. Fail closed if unauthenticated.
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(public.get_my_role(), r.role_name), COALESCE(public.get_my_role_level(), r.role_level)
  INTO   v_profile_id, v_role_name, v_role_level
  FROM   public.users_profile up
  JOIN   public.roles r ON r.id = up.role_id
  WHERE  up.auth_user_id = v_auth_uid
    AND  up.is_active = TRUE
    AND  up.archived_at IS NULL
  ORDER  BY up.created_at DESC
  LIMIT  1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- Validate record existence and scoped visibility
  IF NOT EXISTS (
    SELECT 1 FROM public.hr_emploc h
    WHERE h.id = p_hr_emploc_id
      AND h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc detail record is not found or caller has insufficient access'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    h.id AS hr_emploc_id,
    h.applicant_name,
    h.vcode,
    h.vacancy_id,
    h.vacancy_code_snapshot,
    h.position_id_snapshot,
    h.position AS position_title,
    h.assignment_type::text AS assignment_type,
    h.roving_assignment_id,
    h.covered_stores,
    h.account_id,
    a.account_name,
    a.group_id,
    g.group_name,
    h.store_id,
    h.store_name,
    h.hr_status,
    h.status,
    h.emploc_no,
    h.employee_no,
    h.date_requested,
    h.created_at,
    h.hired_date,
    h.deployed_by_user_id,
    h.hrco_user_id_snapshot,
    h.hrco_name,
    h.employee_lookup_found,
    h.employee_lookup_synced_at,
    h.employee_lookup_remarks,
    h.employee_name_snapshot,
    h.birthdate_snapshot,
    h.civil_status_snapshot,
    h.requirement_overall_status,
    h.ops_remarks,
    h.hr_remarks,
    h.hr_rejection_reason,
    h.hr_reviewed_by,
    h.hr_reviewed_at,

    -- Deficiency Summary
    CASE
      WHEN h.correction_reason IS NULL THEN jsonb_build_object('active_count', 0, 'issues', '[]'::jsonb)
      ELSE jsonb_build_object(
        'active_count', CASE WHEN jsonb_typeof(h.correction_reason) = 'array' THEN jsonb_array_length(h.correction_reason) ELSE 1 END,
        'issues', CASE
          WHEN jsonb_typeof(h.correction_reason) = 'array' THEN (
            SELECT jsonb_agg(
              jsonb_build_object(
                'code', el->>'code',
                'comment', el->>'comment',
                'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = el->>'code'), el->>'code')
              )
            )
            FROM jsonb_array_elements(h.correction_reason) el
          )
          ELSE jsonb_build_array(
            jsonb_build_object(
              'code', h.correction_reason->>'type',
              'comment', h.correction_reason->>'comment',
              'label', COALESCE((SELECT it.label FROM public.hr_emploc_issue_types it WHERE it.code = h.correction_reason->>'type'), h.correction_reason->>'type')
            )
          )
        END
      )
    END AS deficiency_summary,

    h.correction_reason,

    -- Correction / Requirement Attachments (2h: null/empty once deployed; scoped via can_view_hr_emploc_docs)
    CASE
      WHEN (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred') OR NOT public.can_view_hr_emploc_docs(h.id) THEN '[]'::jsonb
      ELSE (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'id', ca.id,
            'original_filename', ca.original_filename,
            'mime_type', ca.mime_type,
            'size_bytes', ca.size_bytes,
            'stage', ca.stage,
            'uploaded_by', ca.uploaded_by,
            'uploaded_at', ca.uploaded_at,
            'created_at', ca.created_at,
            'storage_path', ca.storage_path,
            'object_path', regexp_replace(ca.storage_path, '^hr-corrections/', ''),
            'can_remove', (
              public.can_upload_hr_emploc_docs(h.id)
              AND (public.is_super_admin() OR ca.uploaded_by = v_profile_id)
            )
          ) ORDER BY ca.uploaded_at DESC
        ), '[]'::jsonb)
        FROM public.hr_emploc_correction_attachments ca
        WHERE ca.hr_emploc_id = h.id AND ca.is_deleted = false AND ca.deleted_at IS NULL
      )
    END AS correction_attachments,

    -- Deletion Request Overlay Details
    (
      SELECT jsonb_build_object(
        'id', dr.id,
        'status', dr.status,
        'reason', dr.reason,
        'requested_by', dr.requested_by,
        'requested_by_role', dr.requested_by_role,
        'requested_by_user_id', dr.requested_by_user_id,
        'created_at', dr.created_at,
        'deletion_type', dr.deletion_type,
        'original_emploc_id', dr.original_emploc_id,
        'original_hr_status', dr.original_hr_status,
        'reviewed_by', dr.reviewed_by,
        'reviewed_at', dr.reviewed_at,
        'reviewer_remarks', dr.reviewer_remarks,
        'activities', (
          SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
              'id', act.id,
              'activity_type', act.activity_type,
              'performed_by', act.performed_by,
              'performed_by_user_id', act.performed_by_user_id,
              'performed_at', act.performed_at,
              'remarks', act.remarks
            ) ORDER BY act.performed_at DESC
          ), '[]'::jsonb)
          FROM public.hr_emploc_deletion_activities act
          WHERE act.request_id = dr.id
        )
      )
      FROM public.hr_emploc_deletion_requests dr
      WHERE dr.hr_emploc_id = h.id
      ORDER BY dr.created_at DESC
      LIMIT 1
    ) AS deletion_request,

    -- SLA & Aging Computations
    ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,

    CASE
      WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
        THEN 'breached'
      WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
        THEN 'warning'
      ELSE 'normal'
    END AS sla_status,

    (COALESCE(h.date_requested, h.created_at) + INTERVAL '3 days') AS sla_deadline,
    GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(h.date_requested, h.created_at))))::integer) AS aging_days,

    -- Chronological Correction / Action Timeline History
    (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'event_id', t.event_id,
          'event_type', t.event_type,
          'event_label', t.event_label,
          'status_from', t.status_from,
          'status_to', t.status_to,
          'remarks', t.remarks,
          'actor_id', t.actor_id,
          'actor_name', t.actor_name,
          'has_attachment', t.has_attachment,
          'attachment_filename', t.attachment_filename,
          'attachment_size_bytes', t.attachment_size_bytes,
          'created_at', t.created_at
        ) ORDER BY t.created_at ASC
      ), '[]'::jsonb)
      FROM public.get_correction_timeline(h.id) t
    ) AS timeline,

    -- Row action capability presentation UI hints
    jsonb_build_object(
      'can_view_detail', true,
      'can_request_deletion', (
        h.status <> 'Moved to Plantilla'
        AND h.hr_status <> 'Pending Deletion'
        AND NOT EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
        AND (v_role_level >= 70 OR v_role_name IN ('OM', 'HRCO', 'ATL', 'TL', 'ATL/TL') OR public.i_am_ops() OR public.i_have_full_access())
      ),
      'can_withdraw_deletion_request', (
        EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
        AND (
          public.i_have_full_access()
          OR EXISTS (
            SELECT 1 FROM public.hr_emploc_deletion_requests dr
            WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending' AND dr.requested_by_user_id = v_profile_id
          )
        )
      ),
      'can_approve_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      ),
      'can_reject_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      ),
      'can_edit_emploc', (
        public.can_edit_deployed_hr_emploc()
        AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
      ),
      'can_revert_to_pending', (
        public.can_edit_deployed_hr_emploc()
        AND (h.status = 'Moved to Plantilla' OR h.hr_status = 'Transferred')
      ),
      'can_approve_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_revert_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_review_correction', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Review'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_upload_docs', public.can_upload_hr_emploc_docs(h.id),
      'can_submit_requirements', (
        public.can_upload_hr_emploc_docs(h.id)
        AND h.hr_status = 'Pending'
      ),
      'can_view_docs', public.can_view_hr_emploc_docs(h.id),
      'can_submit_correction', (
        public.can_upload_hr_emploc_docs(h.id)
        AND h.hr_status = 'For Correction'
      ),
      'can_move_to_plantilla', false,
      'can_tag_deficiency', (
        public.can_tag_or_review_hr_emploc()
        AND h.hr_status = 'For Emploc'
        AND h.status <> 'Moved to Plantilla'
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_assign_employee_no', (
        public.can_assign_pending_hr_emploc()
        AND COALESCE(h.employee_no, '') = ''
        AND h.status <> 'Moved to Plantilla'
        AND (
          h.hr_status = 'For Emploc'
          OR (h.hr_status = 'Pending' AND public.is_super_admin())
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id
            AND dr.status = 'Pending'
        )
      ),
      'can_review_deletion', (
        (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        AND EXISTS (
          SELECT 1 FROM public.hr_emploc_deletion_requests dr
          WHERE dr.hr_emploc_id = h.id AND dr.status = 'Pending'
        )
      )
    ) AS row_capabilities
  FROM public.hr_emploc h
  LEFT JOIN public.accounts a ON a.id = h.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE h.id = p_hr_emploc_id
    AND h.deleted_at IS NULL;
END;
$function$

;

DROP FUNCTION IF EXISTS public.get_web_hr_emploc_summary(text, text, text, text, uuid, uuid, text);
CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_summary(p_queue text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_deficiency text DEFAULT NULL::text, p_sla_filter text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text)
 RETURNS TABLE(pending_count bigint, for_emploc_count bigint, correction_count bigint, review_count bigint, ready_count bigint, sla_breached_count bigint, sla_warning_count bigint, with_deficiency_count bigint, pending_deletion_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web hr_emploc summary requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(public.get_my_role(), r.role_name), COALESCE(public.get_my_role_level(), r.role_level)
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web hr_emploc summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      h.hr_status,
      h.status,
      h.account_id,
      a.account_name,
      a.group_id,
      h.applicant_name,
      h.vcode,
      h.employee_no,
      h.emploc_no,
      h.store_name,
      h.position AS position_title,
      COALESCE(h.hrco_name, (SELECT up2.full_name FROM public.users_profile up2 WHERE up2.id = h.hrco_user_id_snapshot)) AS hrco_name,
      h.correction_reason,
      h.deleted_at,
      h.moved_to_plantilla_at,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))) AS sla_breached,
      
      ((h.deleted_at IS NULL) AND (h.employee_no IS NULL OR h.employee_no = '') AND (h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval)) AS sla_warning,
      
      CASE
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) < (now() - '3 days'::interval))
          THEN 'breached'
        WHEN (h.deleted_at IS NULL AND (h.employee_no IS NULL OR h.employee_no = '') AND h.status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text]) AND COALESCE(h.date_requested, h.created_at) >= (now() - '3 days'::interval) AND COALESCE(h.date_requested, h.created_at) < (now() - '2 days'::interval))
          THEN 'warning'
        ELSE 'normal'
      END AS sla_status
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    WHERE
      h.deleted_at IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR (
          h.account = ANY (public.get_my_allowed_accounts())
          OR
          EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = h.account_id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR EXISTS (
            SELECT 1 FROM public.users_profile up_fallback JOIN public.accounts ac ON ac.id = h.account_id
            WHERE up_fallback.id = v_profile_id
              AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
              AND (up_fallback.account_id = h.account_id OR up_fallback.group_id = ac.group_id)
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_deficiency IS NULL
       OR (p_deficiency = 'any' AND s.correction_reason IS NOT NULL)
       OR (p_deficiency = 'none' AND s.correction_reason IS NULL)
       OR (
         s.correction_reason IS NOT NULL AND (
           (jsonb_typeof(s.correction_reason) = 'array' AND EXISTS (
             SELECT 1 FROM jsonb_array_elements(s.correction_reason) el
             WHERE el->>'code' = p_deficiency
           ))
           OR
           (jsonb_typeof(s.correction_reason) = 'object' AND s.correction_reason->>'type' = p_deficiency)
         )
       )
      )
      AND (p_sla_filter IS NULL OR s.sla_status = p_sla_filter)
      AND (p_status IS NULL OR s.status = p_status)
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.applicant_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.emploc_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.hrco_name ILIKE '%' || btrim(p_search) || '%'
        OR s.hr_status ILIKE '%' || btrim(p_search) || '%'
        OR s.status ILIKE '%' || btrim(p_search) || '%'
      )
  )
  SELECT
    count(*) FILTER (WHERE f.hr_status = 'Pending' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_count,
    count(*) FILTER (WHERE f.hr_status = 'For Emploc' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS for_emploc_count,
    count(*) FILTER (WHERE f.hr_status = 'For Correction' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS correction_count,
    count(*) FILTER (WHERE f.hr_status = 'For Review' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS review_count,
    count(*) FILTER (WHERE (
      f.status = 'Moved to Plantilla'
      OR f.hr_status = 'Transferred'
    ) AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS ready_count,
    count(*) FILTER (WHERE f.sla_breached = true)::bigint AS sla_breached_count,
    count(*) FILTER (WHERE f.sla_warning = true)::bigint AS sla_warning_count,
    count(*) FILTER (WHERE f.correction_reason IS NOT NULL)::bigint AS with_deficiency_count,
    count(*) FILTER (WHERE f.hr_status = 'Pending Deletion' AND f.status <> 'Backout' AND f.deleted_at IS NULL)::bigint AS pending_deletion_count
  FROM filtered f;
END;
$function$

;

-- 12. Cross-Module Pipeline Fixes (2g: add 'For Emploc' wherever hr_status is enumerated)
CREATE OR REPLACE FUNCTION public.fn_dashboard_metrics(p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid            uuid := auth.uid();
  v_role_level          integer;
  v_is_admin            boolean;
  v_allowed_acc_ids     uuid[];

  v_open_vacancies      bigint := 0;
  v_emploc_pending      bigint := 0;
  v_active_plantilla    bigint := 0;
  v_understaffed_stores bigint := 0;
  v_active_sla_breaches bigint := 0;
  v_pending_approvals   bigint := NULL;
  v_admin_approvals     bigint := NULL;
  v_security_event_count bigint := NULL;
  v_ghost_employee_count bigint := 0;
  v_unassigned_vacancies bigint := 0;
  v_assigned_vacancies   bigint := 0;
BEGIN
  IF v_auth_uid IS NULL THEN
    IF (auth.jwt() ->> 'role') = 'service_role' OR session_user = 'postgres' THEN
      v_is_admin := true;
    ELSE
      RAISE EXCEPTION 'unauthenticated: dashboard metrics requires a valid session'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    v_role_level := COALESCE(public.get_my_role_level(), 0);
    v_is_admin := (v_role_level >= 90);

    IF NOT EXISTS (
      SELECT 1 FROM public.users_profile
      WHERE auth_user_id = v_auth_uid
        AND is_active = true
        AND archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: dashboard caller is not authorized'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Determine account filtering scope
  IF v_is_admin THEN
    IF p_account_id IS NOT NULL THEN
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(id) INTO v_allowed_acc_ids
      FROM public.accounts
      WHERE group_id = p_group_id AND is_active = true;
    ELSE
      v_allowed_acc_ids := NULL; -- All accounts
    END IF;
  ELSE
    v_allowed_acc_ids := public.get_my_allowed_account_ids();
    IF p_account_id IS NOT NULL THEN
      IF NOT (p_account_id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]))) THEN
        RAISE EXCEPTION 'forbidden: account is out of scope' USING ERRCODE = '42501';
      END IF;
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(a.id) INTO v_allowed_acc_ids
      FROM public.accounts a
      WHERE a.group_id = p_group_id
        AND a.is_active = true
        AND a.id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]));
    END IF;
  END IF;

  -- 1. Open Vacancies
  SELECT count(*)::bigint INTO v_open_vacancies
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  -- 1b. Unassigned vs Assigned Vacancies
  SELECT count(*)::bigint INTO v_unassigned_vacancies
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v.hrco_name IS NULL OR TRIM(v.hrco_name) = '')
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  v_assigned_vacancies := GREATEST(0, v_open_vacancies - v_unassigned_vacancies);

  -- 2. HR Emploc Pending
  SELECT count(*)::bigint INTO v_emploc_pending
  FROM public.hr_emploc h
  WHERE h.deleted_at IS NULL
    AND h.hr_status IN ('Pending', 'For Emploc', 'For Correction', 'For Review')
    AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids));

  -- 3. Active Plantilla
  SELECT count(*)::bigint INTO v_active_plantilla
  FROM public.plantilla p
  WHERE p.status = 'Active'
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  -- 4. Under-Staffed Stores (stores with open vacancies)
  SELECT count(DISTINCT v.store_id)::bigint INTO v_understaffed_stores
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND v.store_id IS NOT NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  -- 5. Active SLA Breaches
  IF v_allowed_acc_ids IS NULL THEN
    SELECT count(*)::bigint INTO v_active_sla_breaches
    FROM public.sla_breach_logs;
  ELSE
    SELECT count(*)::bigint INTO v_active_sla_breaches
    FROM public.sla_breach_logs s
    WHERE s.account = ANY(public.get_my_allowed_accounts());
  END IF;

  -- 6. Approvals & Security KPIs
  IF v_is_admin THEN
    -- Total operational + administrative pending approvals (all 11 queues)
    SELECT (
      COALESCE((SELECT count(*) FROM public.new_store_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.headcount_requests WHERE is_archived = false AND (status::text ILIKE 'pending' OR status::text ILIKE 'under_review')), 0) +
      COALESCE((SELECT count(*) FROM public.plantilla_approvals WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.account_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.coverage_requests WHERE archived_at IS NULL AND status::text IN ('pending', 'draft')), 0) +
      COALESCE((SELECT count(*) FROM public.v_workforce_assignment_request_queue WHERE status::text ILIKE 'pending' OR status::text ILIKE 'for review'), 0) +
      COALESCE((SELECT count(*) FROM public.vacancy_closure_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.hr_emploc_deletion_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.deactivation_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.applicant_movement_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.account_group_transfer_requests WHERE status::text ILIKE 'pending'), 0)
    )::bigint INTO v_pending_approvals;

    -- Security-only approvals (access provisioning & security exceptions)
    SELECT (
      COALESCE((SELECT count(*) FROM public.account_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.applicant_movement_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.coverage_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.deactivation_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.hr_emploc_deletion_requests WHERE status::text ILIKE 'pending'), 0)
    )::bigint INTO v_admin_approvals;

    SELECT (
      COALESCE((SELECT count(*) FROM public.security_audit_logs WHERE created_at >= CURRENT_DATE), 0) +
      COALESCE((SELECT count(*) FROM public.security_events WHERE happened_at >= CURRENT_DATE), 0)
    )::bigint INTO v_security_event_count;

    SELECT count(*)::bigint INTO v_ghost_employee_count
    FROM public.possible_ghost_employees
    WHERE status NOT IN ('Cleared', 'For Termination');
  ELSE
    v_pending_approvals := NULL;
    v_admin_approvals := NULL;
    v_security_event_count := NULL;
    v_ghost_employee_count := 0;
  END IF;

  RETURN jsonb_build_object(
    'total_open_vacancies', v_open_vacancies,
    'unassigned_vacancies', v_unassigned_vacancies,
    'assigned_vacancies', v_assigned_vacancies,
    'total_hr_emploc_pending', v_emploc_pending,
    'total_active_plantilla', v_active_plantilla,
    'understaffed_stores', v_understaffed_stores,
    'active_sla_breaches', v_active_sla_breaches,
    'pending_approvals', v_pending_approvals,
    'admin_security_approvals', v_admin_approvals,
    'security_event_count', v_security_event_count,
    'ghost_employee_count', v_ghost_employee_count
  );
END;
$function$

;

CREATE OR REPLACE FUNCTION public.fn_dashboard_operational_analytics(p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid            uuid := auth.uid();
  v_role_level          integer;
  v_is_admin            boolean;
  v_allowed_acc_ids     uuid[];

  v_pipeline_total      bigint := 0;
  v_hires_this_month    bigint := 0;
  v_separations_month   bigint := 0;
  v_actual_hc           numeric := 0;
  v_hr_pipeline         numeric := 0;
  v_vacant_hc           numeric := 0;
  v_denominator         numeric := 0;
  v_avg_fill_rate       numeric := NULL;
BEGIN
  IF v_auth_uid IS NULL THEN
    IF (auth.jwt() ->> 'role') = 'service_role' OR session_user = 'postgres' THEN
      v_is_admin := true;
    ELSE
      RAISE EXCEPTION 'unauthenticated: dashboard operational analytics requires a valid session'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    v_role_level := COALESCE(public.get_my_role_level(), 0);
    v_is_admin := (v_role_level >= 90);

    IF NOT EXISTS (
      SELECT 1 FROM public.users_profile
      WHERE auth_user_id = v_auth_uid
        AND is_active = true
        AND archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: dashboard caller is not authorized'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Determine account filtering scope
  IF v_is_admin THEN
    IF p_account_id IS NOT NULL THEN
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(id) INTO v_allowed_acc_ids
      FROM public.accounts
      WHERE group_id = p_group_id AND is_active = true;
    ELSE
      v_allowed_acc_ids := NULL; -- All accounts
    END IF;
  ELSE
    v_allowed_acc_ids := public.get_my_allowed_account_ids();
    IF p_account_id IS NOT NULL THEN
      IF NOT (p_account_id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]))) THEN
        RAISE EXCEPTION 'forbidden: account is out of scope' USING ERRCODE = '42501';
      END IF;
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(a.id) INTO v_allowed_acc_ids
      FROM public.accounts a
      WHERE a.group_id = p_group_id
        AND a.is_active = true
        AND a.id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]));
    END IF;
  END IF;

  -- 1. Pipeline Total (Active applicants in pipeline + pending HR Emploc)
  SELECT (
    COALESCE((
      SELECT count(*)
      FROM public.applicants ap
      WHERE COALESCE(ap.is_archived, false) = false
        AND public.fn_is_active_vacancy_applicant_status(ap.status)
        AND (
          v_allowed_acc_ids IS NULL
          OR EXISTS (
            SELECT 1 FROM public.vacancies v
            WHERE v.vcode = ap.vacancy_vcode
              AND v.account_id = ANY(v_allowed_acc_ids)
          )
        )
    ), 0) +
    COALESCE((
      SELECT count(*)
      FROM public.hr_emploc h
      WHERE h.deleted_at IS NULL
        AND h.hr_status IN ('Pending', 'For Emploc', 'For Correction', 'For Review')
        AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids))
    ), 0)
  )::bigint INTO v_pipeline_total;

  -- 2. Hires This Month
  SELECT (
    COALESCE((
      SELECT count(*)
      FROM public.applicants ap
      WHERE ap.hired_date IS NOT NULL
        AND date_trunc('month', ap.hired_date::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
        AND (
          v_allowed_acc_ids IS NULL
          OR EXISTS (
            SELECT 1 FROM public.vacancies v
            WHERE v.vcode = ap.vacancy_vcode
              AND v.account_id = ANY(v_allowed_acc_ids)
          )
        )
    ), 0) +
    COALESCE((
      SELECT count(*)
      FROM public.hr_emploc h
      WHERE h.hired_date IS NOT NULL
        AND date_trunc('month', h.hired_date::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
        AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids))
    ), 0)
  )::bigint INTO v_hires_this_month;

  -- 3. Separations This Month
  SELECT count(*)::bigint INTO v_separations_month
  FROM public.plantilla p
  WHERE p.date_of_separation IS NOT NULL
    AND date_trunc('month', p.date_of_separation::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  -- 4. Avg Fill Rate: Actual / (Actual + HR Pipeline + Vacancy)
  SELECT count(*)::numeric INTO v_actual_hc
  FROM public.plantilla p
  WHERE p.status = 'Active'
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  SELECT count(*)::numeric INTO v_hr_pipeline
  FROM public.hr_emploc h
  WHERE h.deleted_at IS NULL
    AND h.hr_status = ANY(ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])
    AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids));

  SELECT count(*)::numeric INTO v_vacant_hc
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  v_denominator := v_actual_hc + v_hr_pipeline + v_vacant_hc;

  IF v_denominator = 0 THEN
    v_avg_fill_rate := 1.0;
  ELSE
    v_avg_fill_rate := round(v_actual_hc / v_denominator, 4);
  END IF;

  RETURN jsonb_build_object(
    'pipeline_total', v_pipeline_total,
    'hires_this_month', v_hires_this_month,
    'separations_this_month', v_separations_month,
    'avg_fill_rate', v_avg_fill_rate
  );
END;
$function$

;

CREATE OR REPLACE FUNCTION public.get_web_plantilla_summary(p_search text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(active_employees bigint, inactive_employees bigint, roving_count bigint, stationary_count bigint, onboarding_pipeline_count bigint, pending_deactivation_count bigint, staffing_risk_count bigint, open_headcount_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_level integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla summary requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_level
  INTO v_profile_id, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web plantilla summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH plantilla_scoped AS (
    SELECT
      p.account_id, a.group_id, p.status, p.store_id, p.deployment_type, p.roving_assignment_id,
      p.employee_name, p.employee_no, p.store_name
    FROM public.v_plantilla_safe p
    LEFT JOIN public.accounts a ON a.id = p.account_id
    WHERE
      p.source_headcount_request_id IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = p.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = p.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  plantilla_filtered AS (
    SELECT s.*
    FROM plantilla_scoped s
    WHERE (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.employee_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  hr_pipeline_all AS (
    SELECT
      h.id,
      h.account_id,
      a.group_id,
      h.slot_id,
      h.coverage_slot_id,
      h.vcode,
      h.store_id
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.vacancies v
      ON v.id = COALESCE(
        h.vacancy_id,
        (
          SELECT v2.id
          FROM public.vacancies v2
          WHERE v2.vcode = h.vcode
            AND v2.deleted_at IS NULL
          ORDER BY v2.created_at DESC
          LIMIT 1
        )
      )
    WHERE
      h.deleted_at IS NULL
      AND h.hr_status IN ('Pending', 'For Emploc', 'Complete')
      AND (h.employee_no IS NULL OR h.employee_no = '')
      AND COALESCE(v.is_pool_vacancy, FALSE) = FALSE
      AND COALESCE(v.affects_required_hc, TRUE) = TRUE
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR h.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = h.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = h.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = h.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  hr_pipeline AS (
    SELECT count(*)::bigint AS pipeline_count
    FROM hr_pipeline_all hp
    WHERE (p_account_id IS NULL OR hp.account_id = p_account_id)
      AND (p_group_id IS NULL OR hp.group_id = p_group_id)
  ),
  roving_slot_totals AS (
    SELECT
      ps2.source_hc_request_id,
      ps2.slot_ordinal,
      count(*) AS total_slots
    FROM public.plantilla_slots ps2
    WHERE ps2.is_roving = TRUE
      AND ps2.source_hc_request_id IS NOT NULL
      AND ps2.slot_status <> 'closed'
      AND ps2.closed_at IS NULL
    GROUP BY ps2.source_hc_request_id, ps2.slot_ordinal
  ),
  vacant_plantilla_slots_scoped AS (
    SELECT
      v.account_id,
      a.group_id,
      COALESCE(ps.store_id, v.store_id) AS store_id,
      CASE
        WHEN ps.is_roving = TRUE THEN COALESCE(1.0 / NULLIF(rst.total_slots, 0)::numeric, 0::numeric)
        ELSE 1.0::numeric
      END AS slot_hc
    FROM public.plantilla_slots ps
    JOIN public.vacancies v
      ON v.vcode = ps.legacy_vcode
     AND v.deleted_at IS NULL
     AND COALESCE(v.is_archived, FALSE) = FALSE
     AND COALESCE(v.is_pool_vacancy, FALSE) = FALSE
     AND COALESCE(v.affects_required_hc, TRUE) = TRUE
    LEFT JOIN public.accounts a ON a.id = v.account_id
    LEFT JOIN roving_slot_totals rst
      ON ps.is_roving = TRUE
     AND rst.source_hc_request_id = ps.source_hc_request_id
     AND rst.slot_ordinal = ps.slot_ordinal
    WHERE
      ps.closed_at IS NULL
      AND ps.slot_status IN ('open', 'pipeline')
      AND NOT EXISTS (
        SELECT 1 FROM hr_pipeline_all hp WHERE hp.slot_id = ps.id
      )
      AND (
        ps.is_roving = TRUE
        OR COALESCE(ps.store_id, v.store_id) IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM public.coverage_group_stores cgs
          JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
          WHERE cgs.store_id = COALESCE(ps.store_id, v.store_id)
            AND cgs.archived_at IS NULL
            AND cg.archived_at IS NULL
        )
      )
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR v.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = v.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = v.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = v.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = v.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  vacant_plantilla_slots_filtered AS (
    SELECT vs.*
    FROM vacant_plantilla_slots_scoped vs
    WHERE (p_account_id IS NULL OR vs.account_id = p_account_id)
      AND (p_group_id IS NULL OR vs.group_id = p_group_id)
  ),
  vacant_coverage_slots_filtered AS (
    SELECT
      cg.account_id,
      a.group_id,
      1.0::numeric AS slot_hc
    FROM public.coverage_slots cs
    JOIN public.coverage_groups cg
      ON cg.id = cs.coverage_group_id
     AND cg.archived_at IS NULL
    LEFT JOIN public.accounts a ON a.id = cg.account_id
    WHERE
      cs.slot_status = 'open'
      AND NOT EXISTS (
        SELECT 1 FROM hr_pipeline_all hp WHERE hp.coverage_slot_id = cs.id
      )
      AND (p_account_id IS NULL OR cg.account_id = p_account_id)
      AND (p_group_id IS NULL OR a.group_id = p_group_id)
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR a.account_name = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = cg.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = cg.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = cg.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = cg.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  store_staffing AS (
    SELECT
      sk.store_id,
      COALESCE((SELECT count(*) FROM plantilla_filtered pf WHERE pf.store_id = sk.store_id AND pf.status = 'Active'), 0) AS onboard_count,
      COALESCE((SELECT round(sum(vf.slot_hc)) FROM vacant_plantilla_slots_filtered vf WHERE vf.store_id = sk.store_id), 0) AS open_headcount
    FROM (
      SELECT store_id FROM plantilla_filtered WHERE store_id IS NOT NULL
      UNION
      SELECT store_id FROM vacant_plantilla_slots_filtered WHERE store_id IS NOT NULL
    ) sk
  )
  SELECT
    count(*) FILTER (WHERE pf.status = 'Active')::bigint AS active_employees,
    count(*) FILTER (WHERE pf.status <> 'Active')::bigint AS inactive_employees,
    count(*) FILTER (WHERE pf.status = 'Active' AND (COALESCE(pf.deployment_type, '') = 'Roving' OR pf.roving_assignment_id IS NOT NULL))::bigint AS roving_count,
    count(*) FILTER (WHERE pf.status = 'Active' AND NOT (COALESCE(pf.deployment_type, '') = 'Roving' OR pf.roving_assignment_id IS NOT NULL))::bigint AS stationary_count,
    (SELECT pipeline_count FROM hr_pipeline) AS onboarding_pipeline_count,
    count(*) FILTER (WHERE pf.status IN ('Pending Deactivation', 'For Deactivation'))::bigint AS pending_deactivation_count,
    (
      SELECT count(*)::bigint
      FROM store_staffing ss
      WHERE (ss.onboard_count + ss.open_headcount) > 0
        AND ss.onboard_count::numeric / (ss.onboard_count + ss.open_headcount)::numeric < 0.8
    ) AS staffing_risk_count,
    round(
      COALESCE((SELECT sum(vf.slot_hc) FROM vacant_plantilla_slots_filtered vf), 0)
      + COALESCE((SELECT sum(vc.slot_hc) FROM vacant_coverage_slots_filtered vc), 0)
    )::bigint AS open_headcount_count
  FROM plantilla_filtered pf;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.list_web_plantilla_store_staffing(p_search text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid, p_risk_filter text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_sort_by text DEFAULT 'store_name'::text, p_sort_dir text DEFAULT 'asc'::text)
 RETURNS TABLE(store_id uuid, store_name text, account_id uuid, account_name text, group_id uuid, group_name text, province_id uuid, onboard_count bigint, inactive_count bigint, roving_count bigint, stationary_count bigint, pending_deactivation_count bigint, open_vacancy_count bigint, open_headcount bigint, required_headcount bigint, fill_rate numeric, staffing_risk text, row_capabilities jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_level integer;
  v_sort_by    text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'store_name'));
  v_sort_dir   text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'asc'));
  v_limit      integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset     integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla staffing requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_level
  INTO v_profile_id, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web plantilla staffing caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'store_name', 'account_name', 'group_name', 'onboard_count',
    'open_headcount', 'required_headcount', 'fill_rate'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH plantilla_scoped AS (
    SELECT
      p.store_id,
      p.store_name,
      p.account_id,
      p.account,
      p.province_id,
      p.status,
      p.separation_status,
      p.date_of_separation,
      p.deactivated_at,
      p.deployment_type,
      p.roving_assignment_id,
      (
        p.deactivated_at IS NULL
        AND p.date_of_separation IS NULL
        AND lower(coalesce(nullif(btrim(p.status), ''), 'active')) NOT IN (
          'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
        )
        AND lower(coalesce(nullif(btrim(p.separation_status), ''), '')) NOT IN (
          'inactive', 'deactivated', 'resigned', 'separated', 'endo', 'terminated'
        )
      ) AS is_onboard
    FROM public.v_plantilla_safe p
    WHERE
      p.source_headcount_request_id IS NULL
      AND p.store_id IS NOT NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = p.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = p.account_id
          WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  hr_pipeline_slots AS (
    SELECT h.slot_id
    FROM public.hr_emploc h
    LEFT JOIN public.vacancies v
      ON v.id = COALESCE(
        h.vacancy_id,
        (
          SELECT v2.id
          FROM public.vacancies v2
          WHERE v2.vcode = h.vcode
            AND v2.deleted_at IS NULL
          ORDER BY v2.created_at DESC
          LIMIT 1
        )
      )
    WHERE h.deleted_at IS NULL
      AND h.hr_status IN ('Pending', 'For Emploc', 'Complete')
      AND (h.employee_no IS NULL OR h.employee_no = '')
      AND COALESCE(v.is_pool_vacancy, FALSE) = FALSE
      AND COALESCE(v.affects_required_hc, TRUE) = TRUE
      AND h.slot_id IS NOT NULL
  ),
  roving_slot_totals AS (
    SELECT
      ps2.source_hc_request_id,
      ps2.slot_ordinal,
      count(*) AS total_slots
    FROM public.plantilla_slots ps2
    WHERE ps2.is_roving = TRUE
      AND ps2.source_hc_request_id IS NOT NULL
      AND ps2.slot_status <> 'closed'
      AND ps2.closed_at IS NULL
    GROUP BY ps2.source_hc_request_id, ps2.slot_ordinal
  ),
  vacancies_scoped AS (
    SELECT
      COALESCE(ps.store_id, v.store_id) AS store_id,
      v.store_name,
      v.account_id,
      v.account,
      v.province_id,
      v.vcode,
      CASE
        WHEN ps.is_roving = TRUE THEN COALESCE(1.0 / NULLIF(rst.total_slots, 0)::numeric, 0::numeric)
        ELSE 1.0::numeric
      END AS slot_hc
    FROM public.plantilla_slots ps
    JOIN public.vacancies v
      ON v.vcode = ps.legacy_vcode
     AND v.deleted_at IS NULL
     AND COALESCE(v.is_archived, FALSE) = FALSE
     AND COALESCE(v.is_pool_vacancy, FALSE) = FALSE
     AND COALESCE(v.affects_required_hc, TRUE) = TRUE
    LEFT JOIN roving_slot_totals rst
      ON ps.is_roving = TRUE
     AND rst.source_hc_request_id = ps.source_hc_request_id
     AND rst.slot_ordinal = ps.slot_ordinal
    WHERE
      ps.closed_at IS NULL
      AND ps.slot_status IN ('open', 'pipeline')
      AND COALESCE(ps.store_id, v.store_id) IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM hr_pipeline_slots hps WHERE hps.slot_id = ps.id
      )
      AND (
        ps.is_roving = TRUE
        OR NOT EXISTS (
          SELECT 1
          FROM public.coverage_group_stores cgs
          JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
          WHERE cgs.store_id = COALESCE(ps.store_id, v.store_id)
            AND cgs.archived_at IS NULL
            AND cg.archived_at IS NULL
        )
      )
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR v.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = v.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = v.account_id
          WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = v.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fb.account_id = v.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  store_keys AS (
    SELECT
      u.store_id,
      max(u.store_name)                                                    AS store_name,
      (array_agg(u.account_id ORDER BY u.account_id::text) FILTER (WHERE u.account_id IS NOT NULL))[1] AS account_id,
      max(u.account)                                                       AS account_name,
      (array_agg(u.province_id ORDER BY u.province_id::text) FILTER (WHERE u.province_id IS NOT NULL))[1] AS province_id
    FROM (
      SELECT ps.store_id, ps.store_name, ps.account_id, ps.account, ps.province_id
      FROM plantilla_scoped ps
      UNION ALL
      SELECT vs.store_id, vs.store_name, vs.account_id, vs.account, vs.province_id
      FROM vacancies_scoped vs
    ) u
    GROUP BY u.store_id
  ),
  p_agg AS (
    SELECT
      ps.store_id,
      count(*) FILTER (WHERE ps.is_onboard)                                                                           AS onboard_count,
      count(*) FILTER (WHERE NOT ps.is_onboard)                                                                       AS inactive_count,
      count(*) FILTER (WHERE ps.is_onboard AND (COALESCE(ps.deployment_type, '') = 'Roving' OR ps.roving_assignment_id IS NOT NULL)) AS roving_count,
      count(*) FILTER (WHERE ps.is_onboard AND NOT (COALESCE(ps.deployment_type, '') = 'Roving' OR ps.roving_assignment_id IS NOT NULL)) AS stationary_count,
      count(*) FILTER (WHERE ps.status IN ('Pending Deactivation', 'For Deactivation'))                               AS pending_deactivation_count
    FROM plantilla_scoped ps
    GROUP BY ps.store_id
  ),
  v_agg AS (
    SELECT
      vs.store_id,
      count(DISTINCT vs.vcode)              AS open_vacancy_count,
      COALESCE(round(sum(vs.slot_hc)), 0)   AS open_headcount
    FROM vacancies_scoped vs
    GROUP BY vs.store_id
  ),
  combined AS (
    SELECT
      sk.store_id,
      sk.store_name,
      sk.account_id,
      sk.account_name,
      a.group_id,
      g.group_name,
      sk.province_id,
      COALESCE(pa.onboard_count, 0)::bigint              AS onboard_count,
      COALESCE(pa.inactive_count, 0)::bigint             AS inactive_count,
      COALESCE(pa.roving_count, 0)::bigint               AS roving_count,
      COALESCE(pa.stationary_count, 0)::bigint           AS stationary_count,
      COALESCE(pa.pending_deactivation_count, 0)::bigint AS pending_deactivation_count,
      COALESCE(va.open_vacancy_count, 0)::bigint         AS open_vacancy_count,
      COALESCE(va.open_headcount, 0)::bigint             AS open_headcount,
      (COALESCE(pa.onboard_count, 0) + COALESCE(va.open_headcount, 0))::bigint AS required_headcount
    FROM store_keys sk
    LEFT JOIN p_agg pa ON pa.store_id = sk.store_id
    LEFT JOIN v_agg va ON va.store_id = sk.store_id
    LEFT JOIN public.accounts a ON a.id = sk.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
  ),
  risk_scored AS (
    SELECT
      c.*,
      CASE WHEN c.required_headcount = 0 THEN NULL
           ELSE round(c.onboard_count::numeric / c.required_headcount::numeric, 4)
      END AS fill_rate,
      CASE
        WHEN c.required_headcount = 0 THEN 'none'
        WHEN c.onboard_count::numeric / c.required_headcount::numeric < 0.5 THEN 'critical'
        WHEN c.onboard_count::numeric / c.required_headcount::numeric < 0.8 THEN 'warning'
        ELSE 'healthy'
      END AS staffing_risk
    FROM combined c
  ),
  filtered AS (
    SELECT r.*
    FROM risk_scored r
    WHERE
      (p_account_id IS NULL OR r.account_id = p_account_id)
      AND (p_group_id IS NULL OR r.group_id = p_group_id)
      AND (
        p_risk_filter IS NULL
        OR r.staffing_risk = lower(p_risk_filter)
        OR (lower(p_risk_filter) = 'at_risk' AND r.staffing_risk IN ('critical', 'warning'))
      )
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR r.store_name ILIKE '%' || btrim(p_search) || '%'
        OR r.account_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.store_id, c.store_name, c.account_id, c.account_name, c.group_id, c.group_name,
    c.province_id, c.onboard_count, c.inactive_count, c.roving_count, c.stationary_count,
    c.pending_deactivation_count, c.open_vacancy_count, c.open_headcount, c.required_headcount,
    c.fill_rate, c.staffing_risk,
    jsonb_build_object(
      'can_view_store_roster', TRUE,
      'is_at_risk', (c.staffing_risk IN ('critical', 'warning')),
      'has_open_headcount', (c.open_headcount > 0)
    ) AS row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'         THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'         THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'       THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'       THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'         THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'         THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'onboard_count'      THEN c.onboard_count END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'onboard_count'      THEN c.onboard_count END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'open_headcount'     THEN c.open_headcount END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'open_headcount'     THEN c.open_headcount END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'required_headcount' THEN c.required_headcount END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'required_headcount' THEN c.required_headcount END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'fill_rate'          THEN c.fill_rate END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'fill_rate'          THEN c.fill_rate END DESC NULLS LAST,
    c.store_name ASC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$

;

CREATE OR REPLACE VIEW public.v_dashboard_account_mfr_breakdown AS
 WITH active_agg AS (
         SELECT v_plantilla_safe.account,
            count(*) AS active
           FROM v_plantilla_safe
          WHERE v_plantilla_safe.status = 'Active'::text AND v_plantilla_safe.account IS NOT NULL AND TRIM(BOTH FROM v_plantilla_safe.account) <> ''::text
          GROUP BY v_plantilla_safe.account
        ), pipeline_agg AS (
         SELECT hr_emploc.account,
            count(*) AS pipeline
           FROM hr_emploc
          WHERE (hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])) AND hr_emploc.deleted_at IS NULL AND hr_emploc.account IS NOT NULL AND TRIM(BOTH FROM hr_emploc.account) <> ''::text
          GROUP BY hr_emploc.account
        ), vac_agg AS (
         SELECT vw_slot_derived_vacancy_shadow.account_name AS account,
            count(*) AS vacancies
           FROM vw_slot_derived_vacancy_shadow
          WHERE (vw_slot_derived_vacancy_shadow.open_count - vw_slot_derived_vacancy_shadow.pipeline_count - vw_slot_derived_vacancy_shadow.hr_processing_count) > 0 AND vw_slot_derived_vacancy_shadow.account_name IS NOT NULL AND TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.account_name) <> ''::text
          GROUP BY vw_slot_derived_vacancy_shadow.account_name
        ), all_accounts AS (
         SELECT active_agg.account
           FROM active_agg
        UNION
         SELECT pipeline_agg.account
           FROM pipeline_agg
        UNION
         SELECT vac_agg.account
           FROM vac_agg
        )
 SELECT aa.account,
    COALESCE(a.active, 0::bigint) AS active,
    COALESCE(p.pipeline, 0::bigint) AS pipeline,
    COALESCE(v.vacancies, 0::bigint) AS vacancies,
    COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint) AS required,
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint))::numeric
            ELSE 1.0
        END AS mfr
   FROM all_accounts aa
     LEFT JOIN active_agg a ON a.account = aa.account
     LEFT JOIN pipeline_agg p ON p.account = aa.account
     LEFT JOIN vac_agg v ON v.account = aa.account
  ORDER BY (
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint))::numeric
            ELSE 1.0
        END), aa.account;
;

CREATE OR REPLACE VIEW public.v_dashboard_hrco_breakdown AS
 WITH active_agg AS (
         SELECT v_plantilla_safe.hrco_name AS hrco,
            count(*) AS active
           FROM v_plantilla_safe
          WHERE v_plantilla_safe.status = 'Active'::text AND v_plantilla_safe.hrco_name IS NOT NULL AND TRIM(BOTH FROM v_plantilla_safe.hrco_name) <> ''::text
          GROUP BY v_plantilla_safe.hrco_name
        ), pipeline_agg AS (
         SELECT hr_emploc.hrco_name AS hrco,
            count(*) AS pipeline
           FROM hr_emploc
          WHERE (hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])) AND hr_emploc.deleted_at IS NULL AND hr_emploc.hrco_name IS NOT NULL AND TRIM(BOTH FROM hr_emploc.hrco_name) <> ''::text
          GROUP BY hr_emploc.hrco_name
        ), vac_agg AS (
         SELECT COALESCE(NULLIF(TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.hrco_name), ''::text), 'Unassigned'::text) AS hrco,
            count(*) AS vacant
           FROM vw_slot_derived_vacancy_shadow
          WHERE (vw_slot_derived_vacancy_shadow.open_count - vw_slot_derived_vacancy_shadow.pipeline_count - vw_slot_derived_vacancy_shadow.hr_processing_count) > 0
          GROUP BY (COALESCE(NULLIF(TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.hrco_name), ''::text), 'Unassigned'::text))
        ), all_hrco AS (
         SELECT active_agg.hrco
           FROM active_agg
        UNION
         SELECT pipeline_agg.hrco
           FROM pipeline_agg
        UNION
         SELECT vac_agg.hrco
           FROM vac_agg
        )
 SELECT ah.hrco,
    COALESCE(v.vacant, 0::bigint) AS vacant,
    COALESCE(a.active, 0::bigint) AS active,
    COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint) AS required,
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint))::numeric
            ELSE 1.0
        END AS mfr
   FROM all_hrco ah
     LEFT JOIN active_agg a ON a.hrco = ah.hrco
     LEFT JOIN pipeline_agg p ON p.hrco = ah.hrco
     LEFT JOIN vac_agg v ON v.hrco = ah.hrco
  ORDER BY (
        CASE
            WHEN ah.hrco = 'Unassigned'::text THEN 1
            ELSE 0
        END), ah.hrco;
;

CREATE OR REPLACE VIEW public.headcount_summary AS
 WITH emp AS (
         SELECT plantilla.account,
            count(*) FILTER (WHERE plantilla.status = 'Active'::text) AS active_employees,
            count(*) FILTER (WHERE plantilla.status = 'Resigned'::text) AS resigned_employees
           FROM plantilla
          GROUP BY plantilla.account
        ), vac AS (
         SELECT vacancies.account,
            count(*) FILTER (WHERE vacancies.status = 'Open'::text) AS open_vacancies,
            count(*) FILTER (WHERE vacancies.status = 'Filled'::text) AS filled_vacancies
           FROM vacancies
          WHERE vacancies.is_archived = false
          GROUP BY vacancies.account
        ), ep AS (
         SELECT hr_emploc.account,
            count(*) FILTER (WHERE hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text])) AS pending_emploc
           FROM hr_emploc
          GROUP BY hr_emploc.account
        )
 SELECT a.account_name,
    g.group_name,
    COALESCE(emp.active_employees, 0::bigint) AS active_employees,
    COALESCE(emp.resigned_employees, 0::bigint) AS resigned_employees,
    COALESCE(vac.open_vacancies, 0::bigint) AS open_vacancies,
    COALESCE(vac.filled_vacancies, 0::bigint) AS filled_vacancies,
    COALESCE(ep.pending_emploc, 0::bigint) AS pending_emploc
   FROM accounts a
     LEFT JOIN groups g ON g.id = a.group_id
     LEFT JOIN emp ON emp.account = a.account_name
     LEFT JOIN vac ON vac.account = a.account_name
     LEFT JOIN ep ON ep.account = a.account_name
  WHERE a.is_active = true
  ORDER BY g.group_name, a.account_name;
;

-- 13. Grants & Schema Reload
GRANT EXECUTE ON FUNCTION public.has_pending_deletion_request(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_hr_emploc_in_my_scope(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_add_emploc() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_upload_hr_emploc_docs(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_hr_emploc_docs(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_hr_emploc_doc_upload(uuid, text, text, bigint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_hr_emploc_document(uuid, text, text, text, bigint, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.remove_hr_emploc_document(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_hr_emploc_requirements(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_hr_emploc_docs_cleanup(uuid, text, interval) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tg_enqueue_emploc_docs_cleanup_fn() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sweep_orphan_emploc_storage_objects() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_storage_cleanup_queue(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.review_web_hr_emploc_correction(uuid, text, jsonb, text, text, boolean, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assign_hr_emploc_number(uuid, text, boolean, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
