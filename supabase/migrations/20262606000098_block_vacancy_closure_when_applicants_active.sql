-- Migration: 20262606000098_block_vacancy_closure_when_applicants_active.sql
-- Description: Update public.fn_assert_vacancy_closeable to strictly block vacancy closure requests 
-- when active applicants exist in the recruitment pipeline.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_assert_vacancy_closeable(p_vcode text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status      TEXT;
  v_is_archived BOOLEAN;
  v_archived_at TIMESTAMPTZ;
BEGIN
  IF nullif(trim(p_vcode), '') IS NULL THEN
    RAISE EXCEPTION 'fn_assert_vacancy_closeable: vcode is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT status, COALESCE(is_archived, false), archived_at
    INTO v_status, v_is_archived, v_archived_at
  FROM public.vacancies
  WHERE vcode = p_vcode
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vacancy % not found or deleted', p_vcode
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Block: already archived/closed based on authoritative status
  IF v_is_archived = true OR v_status IN ('Archived', 'Closed') THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % is already archived/closed.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: vacancy already Filled
  IF v_status = 'Filled' THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % is already Filled. Cannot close a fulfilled vacancy.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: active hired applicant
  -- Excludes archived applicants, backed-out applicants (backout_date IS NOT NULL),
  -- and expired applicant rows whose hire visibility window has elapsed (hired_visible_until <= NOW()).
  IF EXISTS (
    SELECT 1 FROM public.applicants
    WHERE vacancy_vcode = p_vcode
      AND status IN ('Hired', 'Confirmed Onboard')
      AND COALESCE(is_archived, false) = false
      AND backout_date IS NULL
      AND (hired_visible_until IS NULL OR hired_visible_until > NOW())
  ) THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % has an active hired applicant. Deletion not allowed after hiring.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: active applicants in the recruitment pipeline (screening, interview, shortlisted, endorsed, etc.)
  -- Candidate must be processed, hired, or dropped/backed out before vacancy closure can be requested
  IF EXISTS (
    SELECT 1 FROM public.applicants
    WHERE vacancy_vcode = p_vcode
      AND COALESCE(is_archived, false) = false
      AND backout_date IS NULL
      AND LOWER(TRIM(REPLACE(REPLACE(COALESCE(status, ''), '-', '_'), ' ', '_'))) NOT IN (
        'failed',
        'backout',
        'rejected',
        'did_not_report',
        'rejected_by_ops',
        'withdrew',
        'withdrawn',
        'cancelled'
      )
  ) THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % has active applicants in pipeline. Process or drop candidates before requesting closure.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: active hr_emploc pipeline (not backed out, not moved to plantilla, not deleted)
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc
    WHERE vcode = p_vcode
      AND deleted_at IS NULL
      AND backout_at IS NULL
      AND status NOT IN ('Moved to Plantilla')
  ) THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % has active HR Emploc records in pipeline. Resolve pending onboarding before requesting closure.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: active plantilla headcount linked to this vcode
  IF EXISTS (
    SELECT 1 FROM public.plantilla
    WHERE vcode = p_vcode
      AND status = 'Active'
      AND separation_status IS NULL
  ) THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % has active deployed Plantilla headcount. Cannot close a vacancy with confirmed employees.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

END;
$function$;

COMMIT;
