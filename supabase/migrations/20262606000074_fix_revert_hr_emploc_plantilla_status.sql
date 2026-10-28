-- Fix: revert_hr_emploc_to_pending wrote plantilla.status = 'Separated', which violates
-- plantilla_status_check (allowed: Active, Inactive, Pending Deactivation,
-- Rejected Deactivation, Deactivated, On Leave). Use 'Deactivated' instead.
-- The row is also soft-deleted (is_deleted = true), so it is excluded from
-- uq_plantilla_employee_no_active and the employee ID is freed.

CREATE OR REPLACE FUNCTION public.revert_hr_emploc_to_pending(
  p_hr_emploc_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_profile_id uuid := public.get_my_profile_id();
  v_actor_name       text := public.get_my_full_name();
  v_reason           text := btrim(coalesce(p_reason, ''));
  v_emp              public.hr_emploc;
  v_pl               public.plantilla;
  v_old_employee_no  text;
  v_vacancy_id       uuid;
  v_vcode            text;
  v_active_plantilla_count int;
  v_req_headcount    int;
BEGIN
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Reason for revert is required' USING ERRCODE = '22023';
  END IF;

  IF NOT (public.i_have_full_access() OR public.get_my_role() = 'Encoder' OR public.i_am_hr_dept()) THEN
    RAISE EXCEPTION 'forbidden: Super Admin, Data Team, or HR Personnel required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Record not found or archived' USING ERRCODE = 'P0002';
  END IF;

  v_old_employee_no := v_emp.employee_no;
  v_vacancy_id      := v_emp.vacancy_id;
  v_vcode           := v_emp.vcode;

  -- 1. Unlink and remove from active Plantilla
  SELECT * INTO v_pl FROM public.plantilla
  WHERE hr_emploc_id = p_hr_emploc_id
     OR (v_old_employee_no IS NOT NULL AND employee_no = v_old_employee_no)
  LIMIT 1;

  IF v_pl.id IS NOT NULL THEN
    -- Soft-delete / unlink the plantilla row
    UPDATE public.plantilla
    SET is_deleted = true,
        status     = 'Deactivated',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE id = v_pl.id;

    -- If roving store links exist, mark deleted
    UPDATE public.plantilla_store_links
    SET status = 'Deleted',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE plantilla_id = v_pl.id;

    -- If slot was occupied by this plantilla row, reset slot to open/pipeline
    UPDATE public.plantilla_slots
    SET slot_status = 'open',
        occupied_by_plantilla_id = NULL,
        hr_emploc_id = NULL,
        updated_at = now()
    WHERE occupied_by_plantilla_id = v_pl.id;
  END IF;

  -- 2. Vacancy Status Reconciliation
  -- If this vacancy was marked 'Filled', check if active plantilla count is now below required headcount
  IF v_vcode IS NOT NULL THEN
    SELECT required_headcount INTO v_req_headcount
    FROM public.vacancies
    WHERE vcode = v_vcode AND deleted_at IS NULL
    LIMIT 1;

    SELECT count(*) INTO v_active_plantilla_count
    FROM public.plantilla
    WHERE vcode = v_vcode
      AND coalesce(is_deleted, false) = false
      AND status IN ('Active', 'On Leave');

    IF v_req_headcount IS NOT NULL AND coalesce(v_active_plantilla_count, 0) < v_req_headcount THEN
      -- Reopen the vacancy
      UPDATE public.vacancies
      SET status = 'Open',
          updated_at = now(),
          updated_by = v_actor_profile_id
      WHERE vcode = v_vcode
        AND status IN ('Filled', 'Closed')
        AND coalesce(is_archived, false) = false
        AND deleted_at IS NULL;
    END IF;
  END IF;

  -- 3. Hard-clear employee_no and revert hr_emploc status
  UPDATE public.hr_emploc
  SET employee_no            = NULL,
      emploc_no              = NULL,
      status                 = 'Pending Emploc',
      hr_status              = 'Pending',
      moved_to_plantilla_at  = NULL,
      moved_to_plantilla_by  = NULL,
      updated_at             = now(),
      updated_by             = v_actor_profile_id
  WHERE id = p_hr_emploc_id;

  -- 4. Activity Log Entry
  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    jsonb_build_object('status', 'Moved to Plantilla', 'employee_no', v_old_employee_no),
    jsonb_build_object(
      'status', 'Pending Emploc',
      'employee_no', NULL,
      'reason', v_reason,
      'log_message', format('Reverted from Deployed to Pending and removed from Plantilla (Reason: %s) by %s', v_reason, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'freed_employee_id', v_old_employee_no,
    'message', format('Reverted from Deployed to Pending and removed from Plantilla. Employee ID %s is now freed.', coalesce(v_old_employee_no, ''))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) TO authenticated;
