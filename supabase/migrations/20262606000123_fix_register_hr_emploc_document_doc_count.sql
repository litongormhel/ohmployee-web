-- Migration: 20262606000123_fix_register_hr_emploc_document_doc_count.sql
-- Fixes v_emp.doc_count field reference and adds concurrency conflict handling in register_hr_emploc_document

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

  IF public.has_pending_deletion_request(p_hr_emploc_id) AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'ACTION_LOCKED_PENDING_DELETION: An active deletion request exists for this record.'
      USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('code', 'ACTION_LOCKED_PENDING_DELETION')::text;
  END IF;

  IF NOT public.is_super_admin() THEN
    IF v_emp.status = 'Moved to Plantilla' OR v_emp.hr_status = 'Transferred' THEN
      RAISE EXCEPTION 'INVALID_STAGE_FOR_UPLOAD: Record is already deployed to Plantilla'
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STAGE_FOR_UPLOAD')::text;
    END IF;

    IF v_emp.hr_status NOT IN ('Pending', 'For Correction') THEN
      RAISE EXCEPTION 'INVALID_STAGE_FOR_UPLOAD: Document registration is only allowed in Pending or For Correction (current hr_status: "%")', v_emp.hr_status
        USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'INVALID_STAGE_FOR_UPLOAD')::text;
    END IF;
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

  v_stage := CASE 
    WHEN v_emp.hr_status = 'For Correction' THEN 'correction' 
    ELSE 'initial_requirements' 
  END;

  -- Idempotency check: if active record exists for this path, return existing row
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

  INSERT INTO public.hr_emploc_correction_attachments (
    hr_emploc_id,
    storage_path,
    original_filename,
    mime_type,
    size_bytes,
    stage,
    uploaded_by,
    uploaded_at,
    created_at,
    is_deleted
  ) VALUES (
    p_hr_emploc_id,
    v_full_path,
    COALESCE(NULLIF(btrim(p_original_filename), ''), 'document'),
    v_mime,
    p_size_bytes,
    v_stage,
    v_profile_id,
    now(),
    now(),
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
      'original_filename', p_original_filename,
      'stage', v_stage,
      'storage_path', v_full_path,
      'uploaded_by_profile_id', v_profile_id,
      'uploaded_by_actor_name', v_actor_name
    ),
    'Attachment Uploaded: ' || p_original_filename || ' (' || v_stage || ') by ' || COALESCE(v_actor_name, 'System')
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

REVOKE ALL ON FUNCTION public.register_hr_emploc_document(uuid, text, text, text, bigint, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_hr_emploc_document(uuid, text, text, text, bigint, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
