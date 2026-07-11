-- ============================================================
-- OHM2026_1060 — Harden Archive Restore RPC Integrity
-- Migration:  20260602000001_harden_archive_restore_rpc.sql
-- Depends on: 20260602000000_data_archival_recovery_foundation.sql
-- ============================================================

-- ── §1. Add Vacancy Pre-Archived Status Column ──────────────────────────────
ALTER TABLE public.vacancies
  ADD COLUMN IF NOT EXISTS pre_archived_status text DEFAULT NULL;

-- ── §2. Harden Audit Table Immutability ─────────────────────────────────────
-- Create a trigger function to block UPDATE or DELETE operations on archival_audit_logs.
CREATE OR REPLACE FUNCTION public.prevent_audit_log_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Access Denied: UPDATE operation is prohibited on archival_audit_logs' USING ERRCODE = '42501';
  ELSIF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Access Denied: DELETE operation is prohibited on archival_audit_logs' USING ERRCODE = '42501';
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_harden_archival_audit_logs_immutability ON public.archival_audit_logs;
CREATE TRIGGER trg_harden_archival_audit_logs_immutability
  BEFORE UPDATE OR DELETE ON public.archival_audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_audit_log_modification();


-- ── §3. Drop Legacy Restore RPC Signatures ──────────────────────────────────
-- Drop the single-parameter signatures so they are cleanly replaced.
DROP FUNCTION IF EXISTS public.restore_plantilla_record(uuid);
DROP FUNCTION IF EXISTS public.restore_vacancy_record(uuid);


-- ── §4. Redefine Vacancy Archive RPC ────────────────────────────────────────
-- Redefine to store original status in pre_archived_status.
CREATE OR REPLACE FUNCTION public.archive_vacancy_record(
  p_vacancy_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_record record;
  v_snapshot jsonb;
BEGIN
  -- Super Admin check
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason for archival is required' USING ERRCODE = '22000';
  END IF;

  v_caller_id := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();

  -- Get and lock record
  SELECT * INTO v_record
  FROM public.vacancies
  WHERE id = p_vacancy_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record not found or already deleted' USING ERRCODE = 'P0002';
  END IF;

  IF v_record.is_archived = true THEN
    RAISE EXCEPTION 'Record is already archived' USING ERRCODE = '23505';
  END IF;

  -- Create snapshot
  v_snapshot := to_jsonb(v_record);

  -- Update Vacancy record
  UPDATE public.vacancies
  SET is_archived = true,
      archived_at = now(),
      archived_by_id = v_caller_id,
      archived_by = v_caller_name, -- synchronize legacy field
      archive_reason = p_reason,
      pre_archived_status = status, -- Store original status
      status = 'Archived', -- Maintain status for standard frontend sorting
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_vacancy_id;

  -- Insert audit log
  INSERT INTO public.archival_audit_logs (
    module,
    record_id,
    action_type,
    archived_by,
    reason,
    payload_snapshot
  ) VALUES (
    'vacancy',
    p_vacancy_id,
    'archive',
    v_caller_id,
    p_reason,
    v_snapshot
  );

  RETURN jsonb_build_object(
    'success', true,
    'vacancy_id', p_vacancy_id,
    'archived_at', now()
  );
END;
$$;


-- ── §5. Redefine Plantilla Restore RPC ──────────────────────────────────────
-- Signature now accepts required p_reason, enforces parent validation and cooldown.
CREATE OR REPLACE FUNCTION public.restore_plantilla_record(
  p_plantilla_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_record record;
  v_snapshot jsonb;
  v_conflict_id uuid;
BEGIN
  -- Super Admin check
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;

  -- Validate reason
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason for restoration is required' USING ERRCODE = '22000';
  END IF;

  v_caller_id := public.get_current_profile_id();

  -- Get and lock record
  SELECT * INTO v_record
  FROM public.plantilla
  WHERE id = p_plantilla_id AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record not found or already deleted' USING ERRCODE = 'P0002';
  END IF;

  IF v_record.is_archived = false THEN
    RAISE EXCEPTION 'Record is not currently archived' USING ERRCODE = '23505';
  END IF;

  -- Cooldown Validation: Block if archived within last 60 seconds
  IF v_record.archived_at IS NOT NULL AND v_record.archived_at > (now() - interval '60 seconds') THEN
    RAISE EXCEPTION 'Restore blocked: Cooldown active. Please wait at least 60 seconds after archiving before restoring.' USING ERRCODE = '22000';
  END IF;

  -- Parent Integrity Validation: Reject if store, position, or account are inactive or deleted
  IF v_record.store_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.stores WHERE id = v_record.store_id AND is_active = true) THEN
      RAISE EXCEPTION 'Parent validation failed: Referenced Store % is inactive or deleted', v_record.store_id USING ERRCODE = '23503';
    END IF;
  END IF;

  IF v_record.position_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.positions WHERE id = v_record.position_id AND is_active = true) THEN
      RAISE EXCEPTION 'Parent validation failed: Referenced Position % is inactive or deleted', v_record.position_id USING ERRCODE = '23503';
    END IF;
  END IF;

  IF v_record.account_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = v_record.account_id AND is_active = true) THEN
      RAISE EXCEPTION 'Parent validation failed: Referenced Account % is inactive or deleted', v_record.account_id USING ERRCODE = '23503';
    END IF;
  END IF;

  -- Validation A: Active employee number conflict (uq_plantilla_employee_no_active)
  IF v_record.employee_no IS NOT NULL AND v_record.status = ANY(ARRAY['Active', 'Pending Deactivation', 'On Leave']) THEN
    SELECT id INTO v_conflict_id
    FROM public.plantilla
    WHERE employee_no = v_record.employee_no
      AND is_deleted = false
      AND is_archived = false
      AND status = ANY(ARRAY['Active', 'Pending Deactivation', 'On Leave'])
      AND id <> p_plantilla_id
    LIMIT 1;

    IF v_conflict_id IS NOT NULL THEN
      RAISE EXCEPTION 'Conflict: Employee Number % is already active on record %', v_record.employee_no, v_conflict_id USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Validation B: Active hr_emploc_id conflict (uq_plantilla_hr_emploc_active)
  IF v_record.hr_emploc_id IS NOT NULL THEN
    SELECT id INTO v_conflict_id
    FROM public.plantilla
    WHERE hr_emploc_id = v_record.hr_emploc_id
      AND is_deleted = false
      AND is_archived = false
      AND id <> p_plantilla_id
    LIMIT 1;

    IF v_conflict_id IS NOT NULL THEN
      RAISE EXCEPTION 'Conflict: Emploc deployment record % is already active on plantilla record %', v_record.hr_emploc_id, v_conflict_id USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Create snapshot
  v_snapshot := to_jsonb(v_record);

  -- Update Plantilla record to restore
  UPDATE public.plantilla
  SET is_archived = false,
      restored_at = now(),
      restored_by = v_caller_id,
      archived_at = null,
      archived_by = null,
      archive_reason = null,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_plantilla_id;

  -- Insert audit log
  INSERT INTO public.archival_audit_logs (
    module,
    record_id,
    action_type,
    restored_by,
    reason,
    payload_snapshot
  ) VALUES (
    'plantilla',
    p_plantilla_id,
    'restore',
    v_caller_id,
    p_reason,
    v_snapshot
  );

  RETURN jsonb_build_object(
    'success', true,
    'plantilla_id', p_plantilla_id,
    'restored_at', now()
  );
END;
$$;


-- ── §6. Redefine Vacancy Restore RPC ────────────────────────────────────────
-- Signature now accepts required p_reason, recovers pre-archived status, enforces parent validation and cooldown.
CREATE OR REPLACE FUNCTION public.restore_vacancy_record(
  p_vacancy_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id uuid;
  v_record record;
  v_snapshot jsonb;
  v_conflict_id uuid;
  v_target_status text;
BEGIN
  -- Super Admin check
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
  END IF;

  -- Validate reason
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason for restoration is required' USING ERRCODE = '22000';
  END IF;

  v_caller_id := public.get_current_profile_id();

  -- Get and lock record
  SELECT * INTO v_record
  FROM public.vacancies
  WHERE id = p_vacancy_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record not found or already deleted' USING ERRCODE = 'P0002';
  END IF;

  IF v_record.is_archived = false THEN
    RAISE EXCEPTION 'Record is not currently archived' USING ERRCODE = '23505';
  END IF;

  -- Cooldown Validation: Block if archived within last 60 seconds
  IF v_record.archived_at IS NOT NULL AND v_record.archived_at > (now() - interval '60 seconds') THEN
    RAISE EXCEPTION 'Restore blocked: Cooldown active. Please wait at least 60 seconds after archiving before restoring.' USING ERRCODE = '22000';
  END IF;

  -- Parent Integrity Validation: Reject if store, position, or account are inactive or deleted
  IF v_record.store_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.stores WHERE id = v_record.store_id AND is_active = true) THEN
      RAISE EXCEPTION 'Parent validation failed: Referenced Store % is inactive or deleted', v_record.store_id USING ERRCODE = '23503';
    END IF;
  END IF;

  IF v_record.position_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.positions WHERE id = v_record.position_id AND is_active = true) THEN
      RAISE EXCEPTION 'Parent validation failed: Referenced Position % is inactive or deleted', v_record.position_id USING ERRCODE = '23503';
    END IF;
  END IF;

  IF v_record.account_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = v_record.account_id AND is_active = true) THEN
      RAISE EXCEPTION 'Parent validation failed: Referenced Account % is inactive or deleted', v_record.account_id USING ERRCODE = '23503';
    END IF;
  END IF;

  -- Resolve restoration target status safely (cannot restore into 'Archived')
  v_target_status := CASE 
    WHEN v_record.pre_archived_status IS NULL OR v_record.pre_archived_status = 'Archived' THEN 'Open' 
    ELSE v_record.pre_archived_status 
  END;

  -- Validation: Slot conflict for Open vacancies (uniq_vacancies_open_per_slot)
  IF v_target_status = 'Open' AND COALESCE(v_record.source, '') IS DISTINCT FROM 'hc_request' THEN
    SELECT id INTO v_conflict_id
    FROM public.vacancies
    WHERE store_id = v_record.store_id
      AND position_id = v_record.position_id
      AND status = 'Open'
      AND COALESCE(is_archived, false) = false
      AND deleted_at IS NULL
      AND COALESCE(source, '') IS DISTINCT FROM 'hc_request'
      AND id <> p_vacancy_id
    LIMIT 1;

    IF v_conflict_id IS NOT NULL THEN
      RAISE EXCEPTION 'Conflict: There is already an active Open vacancy for this store and position slot (Vacancy ID: %)', v_conflict_id USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Create snapshot
  v_snapshot := to_jsonb(v_record);

  -- Update Vacancy record to restore
  UPDATE public.vacancies
  SET is_archived = false,
      restored_at = now(),
      restored_by = v_caller_id,
      archived_at = null,
      archived_by_id = null,
      archived_by = null, -- clear legacy field
      archive_reason = null,
      pre_archived_status = null, -- clear preserved status
      status = v_target_status,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_vacancy_id;

  -- Insert audit log
  INSERT INTO public.archival_audit_logs (
    module,
    record_id,
    action_type,
    restored_by,
    reason,
    payload_snapshot
  ) VALUES (
    'vacancy',
    p_vacancy_id,
    'restore',
    v_caller_id,
    p_reason,
    v_snapshot
  );

  RETURN jsonb_build_object(
    'success', true,
    'vacancy_id', p_vacancy_id,
    'restored_at', now()
  );
END;
$$;
