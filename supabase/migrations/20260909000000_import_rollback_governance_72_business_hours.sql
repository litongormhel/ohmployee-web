-- ============================================================
-- OHM2026_0075 — Import rollback governance window
-- Migration: 20260909000000_import_rollback_governance_72_business_hours.sql
-- ============================================================
-- Scope:
--   Import Plantilla and Import Vacancy rollback governance only.
--   Audit logs, approval history, security events, import batch history, and
--   rollback history remain immutable and are never rolled back.
-- ============================================================

-- Sundays are excluded because OHMployee treats the rollback review period as
-- active business time: no governance countdown should be consumed on Sunday.
CREATE OR REPLACE FUNCTION public.fn_import_rollback_deadline(
  p_start timestamptz,
  p_active_hours integer DEFAULT 72
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $func$
DECLARE
  v_cursor timestamptz := p_start;
  v_left numeric := GREATEST(COALESCE(p_active_hours, 72), 0);
  v_next timestamptz;
  v_step numeric;
BEGIN
  WHILE v_left > 0 LOOP
    IF EXTRACT(DOW FROM v_cursor AT TIME ZONE 'UTC') = 0 THEN
      v_cursor := date_trunc('day', v_cursor AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
                  + interval '1 day';
      CONTINUE;
    END IF;

    v_next := date_trunc('day', v_cursor AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
              + interval '1 day';
    v_step := LEAST(v_left, EXTRACT(EPOCH FROM (v_next - v_cursor)) / 3600.0);
    v_cursor := v_cursor + make_interval(secs => (v_step * 3600)::int);
    v_left := v_left - v_step;
  END LOOP;

  RETURN v_cursor;
END;
$func$;

COMMENT ON FUNCTION public.fn_import_rollback_deadline(timestamptz, integer) IS
  'Computes the 72 business-hour import rollback deadline; Sundays count as 0 active hours.';

ALTER TABLE public.plantilla_import_batches
  ADD COLUMN IF NOT EXISTS rollback_window_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_finalized_at timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_block_reason text,
  ADD COLUMN IF NOT EXISTS emergency_rollback_by uuid,
  ADD COLUMN IF NOT EXISTS emergency_rollback_at timestamptz,
  ADD COLUMN IF NOT EXISTS emergency_rollback_reason text;

ALTER TABLE public.vacancy_import_batches
  ADD COLUMN IF NOT EXISTS rollback_window_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_finalized_at timestamptz,
  ADD COLUMN IF NOT EXISTS rollback_block_reason text,
  ADD COLUMN IF NOT EXISTS emergency_rollback_by uuid,
  ADD COLUMN IF NOT EXISTS emergency_rollback_at timestamptz,
  ADD COLUMN IF NOT EXISTS emergency_rollback_reason text;

COMMENT ON COLUMN public.plantilla_import_batches.rollback_expires_at IS
  'Backend-computed 72 business-hour rollback deadline from approval/commit timestamp; Sunday excluded.';
COMMENT ON COLUMN public.vacancy_import_batches.rollback_expires_at IS
  'Backend-computed 72 business-hour rollback deadline from approval/commit timestamp; Sunday excluded.';
COMMENT ON COLUMN public.plantilla_import_batches.rollback_block_reason IS
  'Clear user-facing block reason, e.g. Records modified after import approval.';
COMMENT ON COLUMN public.vacancy_import_batches.rollback_block_reason IS
  'Clear user-facing block reason, e.g. Records modified after import approval.';
COMMENT ON COLUMN public.plantilla_import_batches.emergency_rollback_reason IS
  'Mandatory Super Admin emergency rollback reason. Audit logs are immutable and record the override event.';
COMMENT ON COLUMN public.vacancy_import_batches.emergency_rollback_reason IS
  'Mandatory Super Admin emergency rollback reason. Audit logs are immutable and record the override event.';

DO $$
BEGIN
  ALTER TABLE public.plantilla_import_batches DROP CONSTRAINT IF EXISTS pib_status_check;
  ALTER TABLE public.plantilla_import_batches DROP CONSTRAINT IF EXISTS plantilla_import_batches_status_check;
  ALTER TABLE public.plantilla_import_batches
    ADD CONSTRAINT pib_status_check CHECK (
      status IN (
        'uploaded','validated','approved','observation_period',
        'rollback_requested','rolled_back','finalized',
        'draft_uploaded','validation_failed','pending_approval','rejected',
        'commit_failed','rollback_pending','rollback_failed','failed_after_processing'
      )
    );

  ALTER TABLE public.vacancy_import_batches DROP CONSTRAINT IF EXISTS vib_status_check;
  ALTER TABLE public.vacancy_import_batches
    ADD CONSTRAINT vib_status_check CHECK (
      status IN (
        'uploaded','validated','approved','observation_period',
        'rollback_requested','rolled_back','finalized',
        'draft_uploaded','validation_failed','pending_approval','rejected',
        'commit_failed'
      )
    );

  ALTER TABLE public.plantilla_import_batches DROP CONSTRAINT IF EXISTS pib_rollback_status_check;
  ALTER TABLE public.plantilla_import_batches
    ADD CONSTRAINT pib_rollback_status_check CHECK (
      rollback_status IS NULL OR rollback_status IN ('requested','approved','completed','failed')
    );

  ALTER TABLE public.vacancy_import_batches DROP CONSTRAINT IF EXISTS vib_rollback_status_check;
  ALTER TABLE public.vacancy_import_batches
    ADD CONSTRAINT vib_rollback_status_check CHECK (
      rollback_status IS NULL OR rollback_status IN ('requested','approved','completed','failed')
    );
END$$;

UPDATE public.plantilla_import_batches
   SET rollback_window_started_at = COALESCE(rollback_window_started_at, approved_at),
       rollback_expires_at = COALESCE(
         rollback_expires_at,
         public.fn_import_rollback_deadline(approved_at, 72)
       )
 WHERE approved_at IS NOT NULL
   AND status IN ('approved','rollback_requested','observation_period');

UPDATE public.vacancy_import_batches
   SET rollback_window_started_at = COALESCE(rollback_window_started_at, approved_at),
       rollback_expires_at = COALESCE(
         rollback_expires_at,
         public.fn_import_rollback_deadline(approved_at, 72)
       )
 WHERE approved_at IS NOT NULL
   AND status IN ('approved','rollback_requested','observation_period');

CREATE OR REPLACE FUNCTION public._import_actor_can_request_rollback()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT public.is_super_admin()
      OR public.i_have_full_access()
      OR COALESCE(public.get_my_role_level(), 0) = 30;
$func$;

COMMENT ON FUNCTION public._import_actor_can_request_rollback() IS
  'Data Team/Encoder (role_level = 30), Head Admin, and Super Admin may request import rollback.';

CREATE OR REPLACE FUNCTION public._import_records_modified_after_approval(
  p_module text,
  p_batch_id uuid,
  p_approved_at timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  IF p_approved_at IS NULL THEN
    RETURN false;
  END IF;

  IF p_module = 'plantilla' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.plantilla p
       WHERE p.source_baseline_import_batch_id = p_batch_id
         AND p.updated_at > p_approved_at
    ) OR EXISTS (
      SELECT 1 FROM public.stores s
       WHERE s.source_import_batch_id = p_batch_id
         AND s.updated_at > p_approved_at
    ) OR EXISTS (
      SELECT 1 FROM public.employee_store_allocations a
       WHERE a.source_import_batch_id = p_batch_id
         AND a.updated_at > p_approved_at
    );
  END IF;

  IF p_module = 'vacancy' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.vacancies v
       WHERE v.source_vacancy_import_batch_id = p_batch_id
         AND v.updated_at > p_approved_at
    );
  END IF;

  RETURN false;
END;
$func$;

COMMENT ON FUNCTION public._import_records_modified_after_approval(text, uuid, timestamptz) IS
  'Rollback is blocked after post-import edits because restoring old snapshots could clobber approved operational changes.';

CREATE OR REPLACE FUNCTION public._assert_import_rollback_allowed(
  p_module text,
  p_batch_id uuid,
  p_approved_at timestamptz,
  p_expires_at timestamptz,
  p_emergency boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  IF public._import_records_modified_after_approval(p_module, p_batch_id, p_approved_at) THEN
    RAISE EXCEPTION 'Records modified after import approval.' USING ERRCODE = '22023';
  END IF;

  IF NOT COALESCE(p_emergency, false) AND now() > p_expires_at THEN
    RAISE EXCEPTION 'ROLLBACK_WINDOW_EXPIRED: rollback window expired'
      USING ERRCODE = '22023';
  END IF;
END;
$func$;

CREATE OR REPLACE FUNCTION public._plantilla_import_rollback_governance_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_emergency boolean := COALESCE(current_setting('ohm.import_emergency_rollback', true), '') = 'on';
BEGIN
  IF NEW.approved_at IS NOT NULL AND NEW.rollback_expires_at IS NULL THEN
    NEW.rollback_window_started_at := COALESCE(NEW.rollback_window_started_at, NEW.approved_at);
    NEW.rollback_expires_at := public.fn_import_rollback_deadline(NEW.approved_at, 72);
  END IF;

  IF (
       NEW.rollback_status = 'requested'
       AND COALESCE(OLD.rollback_status, '') IS DISTINCT FROM COALESCE(NEW.rollback_status, '')
     ) OR (
       NEW.status = 'rollback_pending'
       AND COALESCE(OLD.status, '') IS DISTINCT FROM COALESCE(NEW.status, '')
     ) THEN
    PERFORM public._assert_import_rollback_allowed(
      'plantilla',
      NEW.id,
      NEW.approved_at,
      COALESCE(NEW.rollback_expires_at, public.fn_import_rollback_deadline(NEW.approved_at, 72)),
      v_emergency
    );
    NEW.rollback_block_reason := NULL;
  END IF;

  RETURN NEW;
EXCEPTION WHEN others THEN
  NEW.rollback_block_reason := SQLERRM;
  RAISE;
END;
$func$;

CREATE OR REPLACE FUNCTION public._vacancy_import_rollback_governance_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_emergency boolean := COALESCE(current_setting('ohm.import_emergency_rollback', true), '') = 'on';
BEGIN
  IF NEW.approved_at IS NOT NULL AND NEW.rollback_expires_at IS NULL THEN
    NEW.rollback_window_started_at := COALESCE(NEW.rollback_window_started_at, NEW.approved_at);
    NEW.rollback_expires_at := public.fn_import_rollback_deadline(NEW.approved_at, 72);
  END IF;

  IF NEW.rollback_status = 'requested'
     AND COALESCE(OLD.rollback_status, '') IS DISTINCT FROM COALESCE(NEW.rollback_status, '') THEN
    PERFORM public._assert_import_rollback_allowed(
      'vacancy',
      NEW.id,
      NEW.approved_at,
      COALESCE(NEW.rollback_expires_at, public.fn_import_rollback_deadline(NEW.approved_at, 72)),
      v_emergency
    );
    NEW.rollback_block_reason := NULL;
  END IF;

  RETURN NEW;
EXCEPTION WHEN others THEN
  NEW.rollback_block_reason := SQLERRM;
  RAISE;
END;
$func$;

DROP TRIGGER IF EXISTS trg_plantilla_import_rollback_governance ON public.plantilla_import_batches;
CREATE TRIGGER trg_plantilla_import_rollback_governance
  BEFORE UPDATE ON public.plantilla_import_batches
  FOR EACH ROW EXECUTE FUNCTION public._plantilla_import_rollback_governance_trg();

DROP TRIGGER IF EXISTS trg_vacancy_import_rollback_governance ON public.vacancy_import_batches;
CREATE TRIGGER trg_vacancy_import_rollback_governance
  BEFORE UPDATE ON public.vacancy_import_batches
  FOR EACH ROW EXECUTE FUNCTION public._vacancy_import_rollback_governance_trg();

CREATE OR REPLACE FUNCTION public.finalize_expired_import_rollback_windows()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_plantilla int := 0;
  v_vacancy int := 0;
BEGIN
  UPDATE public.plantilla_import_batches
     SET status = 'finalized',
         rollback_finalized_at = now(),
         rollback_block_reason = 'Rollback window expired',
         updated_at = now()
   WHERE status IN ('approved','observation_period','rollback_requested')
     AND rollback_status IS DISTINCT FROM 'completed'
     AND COALESCE(rollback_expires_at, public.fn_import_rollback_deadline(approved_at, 72)) < now();
  GET DIAGNOSTICS v_plantilla = ROW_COUNT;

  UPDATE public.vacancy_import_batches
     SET status = 'finalized',
         rollback_finalized_at = now(),
         rollback_block_reason = 'Rollback window expired',
         updated_at = now()
   WHERE status IN ('approved','observation_period','rollback_requested')
     AND rollback_status IS DISTINCT FROM 'completed'
     AND COALESCE(rollback_expires_at, public.fn_import_rollback_deadline(approved_at, 72)) < now();
  GET DIAGNOSTICS v_vacancy = ROW_COUNT;

  RETURN jsonb_build_object('plantilla_finalized', v_plantilla, 'vacancy_finalized', v_vacancy);
END;
$func$;

GRANT EXECUTE ON FUNCTION public.finalize_expired_import_rollback_windows() TO authenticated;

-- Data Team/Encoder and above may request Import Vacancy rollback; execution still requires Super Admin.
CREATE OR REPLACE FUNCTION public.request_vacancy_import_rollback(
  p_batch_id uuid,
  p_reason_code text,
  p_reason_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid uuid := auth.uid();
  v_batch public.vacancy_import_batches%ROWTYPE;
  v_code text := COALESCE(lower(trim(p_reason_code)), '');
  v_note text := COALESCE(trim(p_reason_note), '');
  v_label text;
  v_display text;
  v_notified int := 0;
BEGIN
  IF COALESCE(current_setting('ohm.import_emergency_rollback', true), '') <> 'on' THEN
    PERFORM public.finalize_expired_import_rollback_windows();
  END IF;

  IF NOT public._import_actor_can_request_rollback() THEN
    RAISE EXCEPTION 'forbidden: Data Team, Head Admin, or Super Admin required to request rollback'
      USING ERRCODE = '42501';
  END IF;

  v_label := CASE v_code
    WHEN 'wrong_batch' THEN 'Wrong batch imported'
    WHEN 'wrong_group_account' THEN 'Wrong Group/Account'
    WHEN 'wrong_vcode_list' THEN 'Wrong VCODE list'
    WHEN 'wrong_applicant_pipeline' THEN 'Wrong applicant pipeline data'
    WHEN 'duplicate_migration_correction' THEN 'Duplicate/migration correction'
    WHEN 'uploaded_by_mistake' THEN 'Uploaded by mistake'
    WHEN 'other' THEN 'Other'
    ELSE NULL
  END;
  IF v_label IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: rollback reason is required' USING ERRCODE = '22023';
  END IF;
  IF length(v_note) < 10 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rollback remarks must be at least 10 characters'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_batch FROM public.vacancy_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;
  IF v_batch.status <> 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATE: only approved batches can be rolled back (current=%)',
      v_batch.status USING ERRCODE = '22023';
  END IF;
  IF v_batch.rollback_status IN ('requested','approved','completed') THEN
    RAISE EXCEPTION 'INVALID_STATE: rollback already % for this batch',
      v_batch.rollback_status USING ERRCODE = '22023';
  END IF;

  PERFORM public._assert_import_rollback_allowed(
    'vacancy',
    p_batch_id,
    v_batch.approved_at,
    COALESCE(v_batch.rollback_expires_at, public.fn_import_rollback_deadline(v_batch.approved_at, 72)),
    false
  );

  v_display := v_label || ' - ' || v_note;

  UPDATE public.vacancy_import_batches
     SET rollback_status = 'requested',
         rollback_requested_by = v_uid,
         rollback_requested_at = now(),
         rollback_reason_code = v_code,
         rollback_reason_note = v_note,
         rollback_reason = v_display,
         rollback_approved_by = NULL,
         rollback_approved_at = NULL,
         rollback_completed_at = NULL,
         rollback_error_detail = NULL,
         rollback_block_reason = NULL,
         updated_at = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('event','rollback_requested','reason_code',v_code,'reason_note',v_note));

  IF to_regprocedure('public._notify_vacancy_import_role(text[],text,text,text,text,text,text)') IS NOT NULL THEN
    v_notified := public._notify_vacancy_import_role(
      ARRAY['Super Admin','superAdmin','super_admin'],
      'Super Admin',
      'Import Vacancy Rollback Requested',
      'A rollback request was submitted for an approved Import Vacancy batch and requires Super Admin review.',
      'VACANCY_IMPORT_ROLLBACK_REQUESTED',
      '/vacancy_import/batch/' || p_batch_id::text || '/rollback',
      p_batch_id::text
    );
  END IF;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'rollback_status', 'requested',
    'rollback_reason_code', v_code,
    'rollback_reason_note', v_note,
    'notifications_sent', v_notified
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.request_vacancy_import_rollback(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_vacancy_import_rollback(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.approve_vacancy_import_rollback(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid uuid := auth.uid();
  v_batch public.vacancy_import_batches%ROWTYPE;
  v_vac_count int := 0;
  v_app_count int := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin required to approve/execute rollback'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(current_setting('ohm.import_emergency_rollback', true), '') <> 'on' THEN
    PERFORM public.finalize_expired_import_rollback_windows();
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

  PERFORM public._assert_import_rollback_allowed(
    'vacancy',
    p_batch_id,
    v_batch.approved_at,
    COALESCE(v_batch.rollback_expires_at, public.fn_import_rollback_deadline(v_batch.approved_at, 72)),
    COALESCE(current_setting('ohm.import_emergency_rollback', true), '') = 'on'
  );

  -- Vacancy rollback is scoped to imported Open/Pipeline vacancy records owned by
  -- the batch. Audit/user/import/rollback histories are immutable and untouched.
  WITH batch_vcodes AS (
    SELECT vcode FROM public.vacancies
     WHERE source_vacancy_import_batch_id = p_batch_id
       AND vcode IS NOT NULL
       AND status IN ('Open','Pipeline','open','pipeline')
  ),
  updated_apps AS (
    UPDATE public.applicants a
       SET is_archived = true,
           updated_by = public.get_current_profile_id(),
           updated_at = now()
      FROM batch_vcodes b
     WHERE a.vacancy_vcode = b.vcode
       AND COALESCE(a.is_archived, false) = false
    RETURNING a.id
  )
  SELECT count(*) INTO v_app_count FROM updated_apps;

  WITH updated_vacs AS (
    UPDATE public.vacancies v
       SET deleted_at = now(),
           updated_at = now()
     WHERE v.source_vacancy_import_batch_id = p_batch_id
       AND v.deleted_at IS NULL
       AND v.status IN ('Open','Pipeline','open','pipeline')
    RETURNING v.id
  )
  SELECT count(*) INTO v_vac_count FROM updated_vacs;

  UPDATE public.vacancy_import_batches
     SET status = 'rolled_back',
         rollback_status = 'completed',
         rollback_approved_by = v_uid,
         rollback_approved_at = now(),
         rollback_completed_at = now(),
         rollback_vacancies_count = v_vac_count,
         rollback_applicants_count = v_app_count,
         rollback_error_detail = NULL,
         rollback_block_reason = NULL,
         updated_at = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object(
      'event','rollback_completed',
      'vacancies',v_vac_count,
      'applicants',v_app_count
    ));

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'rollback_status', 'completed',
    'status', 'rolled_back',
    'vacancies_rolled_back', v_vac_count,
    'applicants_rolled_back', v_app_count
  );
EXCEPTION WHEN others THEN
  UPDATE public.vacancy_import_batches
     SET rollback_status = 'failed',
         rollback_error_detail = SQLERRM,
         rollback_block_reason = SQLERRM,
         updated_at = now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('event','rollback_failed','error',SQLERRM));

  RAISE EXCEPTION 'ROLLBACK_FAILED: %', SQLERRM USING ERRCODE = '22000';
END;
$func$;

REVOKE ALL ON FUNCTION public.approve_vacancy_import_rollback(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_vacancy_import_rollback(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.emergency_rollback_plantilla_import(
  p_batch_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid uuid := auth.uid();
  v_reason text := COALESCE(trim(p_reason), '');
  v_result jsonb;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin required for emergency rollback override'
      USING ERRCODE = '42501';
  END IF;
  IF length(v_reason) < 50 THEN
    RAISE EXCEPTION 'INVALID_INPUT: emergency rollback reason must be at least 50 characters'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public.finalize_expired_import_rollback_windows();
  PERFORM 1 FROM public.plantilla_import_batches
   WHERE id = p_batch_id AND status = 'finalized' AND COALESCE(rollback_ready, false)
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATE: emergency rollback is only available for finalized rollback-ready Import Plantilla batches'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public._assert_import_rollback_allowed(
    'plantilla',
    p_batch_id,
    (SELECT approved_at FROM public.plantilla_import_batches WHERE id = p_batch_id),
    now(),
    true
  );

  PERFORM set_config('ohm.import_emergency_rollback', 'on', true);
  UPDATE public.plantilla_import_batches
     SET status = 'approved',
         rollback_status = 'requested',
         rollback_requested_by = v_uid,
         rollback_requested_at = now(),
         rollback_reason = v_reason,
         emergency_rollback_by = v_uid,
         emergency_rollback_at = now(),
         emergency_rollback_reason = v_reason,
         updated_at = now()
   WHERE id = p_batch_id;

  v_result := public.approve_plantilla_import_rollback(p_batch_id);

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'plantilla_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('event','emergency_rollback_override','reason',v_reason));

  RETURN v_result || jsonb_build_object('emergency_override', true);
END;
$func$;

CREATE OR REPLACE FUNCTION public.emergency_rollback_vacancy_import(
  p_batch_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_uid uuid := auth.uid();
  v_reason text := COALESCE(trim(p_reason), '');
  v_result jsonb;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden: Super Admin required for emergency rollback override'
      USING ERRCODE = '42501';
  END IF;
  IF length(v_reason) < 50 THEN
    RAISE EXCEPTION 'INVALID_INPUT: emergency rollback reason must be at least 50 characters'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public.finalize_expired_import_rollback_windows();
  PERFORM 1 FROM public.vacancy_import_batches
   WHERE id = p_batch_id AND status = 'finalized'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATE: emergency rollback is only available for finalized Import Vacancy batches'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public._assert_import_rollback_allowed(
    'vacancy',
    p_batch_id,
    (SELECT approved_at FROM public.vacancy_import_batches WHERE id = p_batch_id),
    now(),
    true
  );

  PERFORM set_config('ohm.import_emergency_rollback', 'on', true);
  UPDATE public.vacancy_import_batches
     SET status = 'approved',
         rollback_status = 'requested',
         rollback_requested_by = v_uid,
         rollback_requested_at = now(),
         rollback_reason = v_reason,
         emergency_rollback_by = v_uid,
         emergency_rollback_at = now(),
         emergency_rollback_reason = v_reason,
         updated_at = now()
   WHERE id = p_batch_id;

  v_result := public.approve_vacancy_import_rollback(p_batch_id);

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'vacancy_import_batches', 'UPDATE', p_batch_id,
    jsonb_build_object('event','emergency_rollback_override','reason',v_reason));

  RETURN v_result || jsonb_build_object('emergency_override', true);
END;
$func$;

REVOKE ALL ON FUNCTION public.emergency_rollback_plantilla_import(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.emergency_rollback_plantilla_import(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.emergency_rollback_vacancy_import(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.emergency_rollback_vacancy_import(uuid,text) TO authenticated;

COMMENT ON FUNCTION public.emergency_rollback_plantilla_import(uuid,text) IS
  'Super Admin emergency rollback after finalized state. Requires reason >= 50 chars and writes immutable audit log.';
COMMENT ON FUNCTION public.emergency_rollback_vacancy_import(uuid,text) IS
  'Super Admin emergency rollback after finalized state. Requires reason >= 50 chars and writes immutable audit log.';

CREATE OR REPLACE FUNCTION public._import_rollback_ui_state(
  p_status text,
  p_rollback_status text,
  p_block_reason text,
  p_expires_at timestamptz
)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $func$
  SELECT CASE
    WHEN p_status = 'rolled_back' OR p_rollback_status = 'completed' THEN 'rolled_back'
    WHEN p_status = 'finalized' THEN 'finalized'
    WHEN p_block_reason IS NOT NULL AND p_block_reason <> '' THEN 'blocked'
    WHEN p_rollback_status = 'requested' THEN 'rollback_requested'
    WHEN p_status = 'approved' AND p_expires_at >= now() THEN 'rollback_allowed'
    WHEN p_status = 'approved' AND p_expires_at < now() THEN 'finalized'
    ELSE COALESCE(NULLIF(p_status, ''), 'uploaded')
  END;
$func$;

-- Refresh Import Plantilla listing with backend-computed rollback eligibility.
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
  rolled_back_at             timestamptz,
  rollback_window_started_at timestamptz,
  rollback_expires_at        timestamptz,
  rollback_remaining_seconds integer,
  rollback_allowed           boolean,
  rollback_ui_state          text,
  rollback_block_reason      text,
  can_emergency_rollback     boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  PERFORM public.finalize_expired_import_rollback_windows();

  RETURN QUERY
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
    b.rolled_back_at,
    b.rollback_window_started_at,
    b.rollback_expires_at,
    GREATEST(0, EXTRACT(EPOCH FROM (b.rollback_expires_at - now()))::int),
    b.status = 'approved'
      AND b.rollback_status IS NULL
      AND COALESCE(b.rollback_ready, false)
      AND b.rollback_expires_at >= now()
      AND NOT public._import_records_modified_after_approval('plantilla', b.id, b.approved_at),
    public._import_rollback_ui_state(
      b.status,
      b.rollback_status,
      CASE
        WHEN public._import_records_modified_after_approval('plantilla', b.id, b.approved_at)
          THEN 'Records modified after import approval.'
        ELSE b.rollback_block_reason
      END,
      b.rollback_expires_at
    ),
    CASE
      WHEN public._import_records_modified_after_approval('plantilla', b.id, b.approved_at)
        THEN 'Records modified after import approval.'
      ELSE b.rollback_block_reason
    END,
    public.is_super_admin() AND b.status = 'finalized' AND COALESCE(b.rollback_ready, false)
  FROM public.plantilla_import_batches b
  LEFT JOIN public.groups        g   ON g.id = b.selected_group_id
  LEFT JOIN public.accounts      a   ON a.id = b.selected_account_id
  LEFT JOIN LATERAL (
    SELECT up2.full_name
      FROM public.users_profile up2
     WHERE up2.auth_user_id = b.uploaded_by OR up2.id = b.uploaded_by
     ORDER BY CASE WHEN up2.auth_user_id = b.uploaded_by THEN 0 ELSE 1 END
     LIMIT 1
  ) up ON true
  LEFT JOIN public.users_profile rrp ON rrp.auth_user_id = b.rollback_requested_by
  LEFT JOIN public.users_profile rap ON rap.auth_user_id = b.rollback_approved_by
  WHERE (public.i_have_full_access() OR b.uploaded_by = auth.uid())
    AND (p_status IS NULL OR b.status = p_status)
  ORDER BY b.created_at DESC;
END;
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_batches(text) TO authenticated;

-- Refresh Import Vacancy listing with backend-computed rollback eligibility.
DROP FUNCTION IF EXISTS public.get_vacancy_import_batches(text);

CREATE OR REPLACE FUNCTION public.get_vacancy_import_batches(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  id                            uuid,
  file_name                     text,
  status                        text,
  selected_group_id             uuid,
  selected_account_id           uuid,
  group_name                    text,
  account_name                  text,
  uploaded_by                   uuid,
  uploaded_role                 text,
  uploaded_at                   timestamptz,
  approved_by                   uuid,
  approved_by_name              text,
  approved_at                   timestamptz,
  rejected_by                   uuid,
  rejected_by_name              text,
  rejected_at                   timestamptz,
  rejection_reason              text,
  rejection_reason_code         text,
  rejection_reason_note         text,
  commit_error_detail           text,
  total_rows                    integer,
  valid_rows                    integer,
  flagged_rows                  integer,
  skipped_rows                  integer,
  blocked_rows                  integer,
  open_count                    integer,
  pipeline_count                integer,
  duplicate_vcode_count         integer,
  existing_vcode_count          integer,
  context_mismatch_count        integer,
  cross_account_applicant_count integer,
  committed_vacancies           integer,
  committed_applicants          integer,
  error_summary                 jsonb,
  approval_due_at               timestamptz,
  approval_escalated_at         timestamptz,
  approval_notified_at          timestamptz,
  rollback_status               text,
  rollback_reason               text,
  rollback_reason_code          text,
  rollback_reason_note          text,
  rollback_requested_by         uuid,
  rollback_requested_by_name    text,
  rollback_requested_at         timestamptz,
  rollback_approved_by          uuid,
  rollback_approved_by_name     text,
  rollback_approved_at          timestamptz,
  rollback_completed_at         timestamptz,
  rollback_error_detail         text,
  rollback_vacancies_count      integer,
  rollback_applicants_count     integer,
  rollback_window_started_at    timestamptz,
  rollback_expires_at           timestamptz,
  rollback_remaining_seconds    integer,
  rollback_allowed              boolean,
  rollback_ui_state             text,
  rollback_block_reason         text,
  can_emergency_rollback        boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
BEGIN
  PERFORM public.finalize_expired_import_rollback_windows();

  RETURN QUERY
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
    b.cross_account_applicant_count,
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
    b.rollback_applicants_count,
    b.rollback_window_started_at,
    b.rollback_expires_at,
    GREATEST(0, EXTRACT(EPOCH FROM (b.rollback_expires_at - now()))::int),
    b.status = 'approved'
      AND b.rollback_status IS NULL
      AND b.rollback_expires_at >= now()
      AND NOT public._import_records_modified_after_approval('vacancy', b.id, b.approved_at),
    public._import_rollback_ui_state(
      b.status,
      b.rollback_status,
      CASE
        WHEN public._import_records_modified_after_approval('vacancy', b.id, b.approved_at)
          THEN 'Records modified after import approval.'
        ELSE b.rollback_block_reason
      END,
      b.rollback_expires_at
    ),
    CASE
      WHEN public._import_records_modified_after_approval('vacancy', b.id, b.approved_at)
        THEN 'Records modified after import approval.'
      ELSE b.rollback_block_reason
    END,
    public.is_super_admin() AND b.status = 'finalized'
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
END;
$func$;

REVOKE ALL ON FUNCTION public.get_vacancy_import_batches(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_vacancy_import_batches(text) TO authenticated;
