CREATE OR REPLACE FUNCTION public.plantilla_request_deactivation(
  p_plantilla_id uuid,
  p_reason text DEFAULT NULL::text
)
RETURNS public.plantilla
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.plantilla;
  v_profile_id uuid;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'request_deact') THEN
    RAISE EXCEPTION 'forbidden: Ops role required for deactivation request'
      USING errcode = '42501';
  END IF;

  v_profile_id := public.get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'current user profile not found; cannot request deactivation'
      USING errcode = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.plantilla
  WHERE id = p_plantilla_id
    AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found';
  END IF;

  IF lower(trim(COALESCE(v_row.status, ''))) = 'active' THEN
    RAISE EXCEPTION 'cannot request deactivation for an Active employee; separate first';
  END IF;

  IF lower(trim(COALESCE(v_row.status, ''))) = 'deactivated' THEN
    RAISE EXCEPTION 'employee is already deactivated';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope'
      USING errcode = '42501';
  END IF;

  IF v_row.status = 'For Deactivation' THEN
    RETURN v_row;
  END IF;

  UPDATE public.plantilla
  SET status              = 'For Deactivation',
      for_deactivation_at = NOW(),
      for_deactivation_by = v_profile_id,
      remarks             = COALESCE(NULLIF(TRIM(p_reason), ''), remarks),
      updated_by          = v_profile_id,
      updated_at          = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  PERFORM public._log_employee_action(
    p_plantilla_id,
    'REQUEST_DEACTIVATION',
    format('Deactivation requested for %s', v_row.employee_name),
    NULL,
    jsonb_build_object('status', 'For Deactivation')
  );

  RETURN v_row;
END;
$function$;
