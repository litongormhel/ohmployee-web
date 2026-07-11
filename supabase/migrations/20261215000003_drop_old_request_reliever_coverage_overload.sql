-- Drop old un-hardened request_reliever_coverage overload to avoid ambiguity.
DROP FUNCTION IF EXISTS public.request_reliever_coverage(uuid, uuid, uuid, uuid, uuid, text, text, date, date, text);

-- Update request_reliever_coverage to insert auth.uid() instead of public.get_my_profile_id() into requested_by_id.
CREATE OR REPLACE FUNCTION public.request_reliever_coverage(
  p_employee_id uuid,
  p_pool_type_id uuid,
  p_requested_account_id uuid DEFAULT NULL::uuid,
  p_requested_group_id uuid DEFAULT NULL::uuid,
  p_requested_store_id uuid DEFAULT NULL::uuid,
  p_start_date date DEFAULT CURRENT_DATE,
  p_end_date date DEFAULT CURRENT_DATE,
  p_priority text DEFAULT 'Normal'::text,
  p_reason text DEFAULT NULL::text,
  p_requested_position text DEFAULT NULL::text
)
 RETURNS TABLE(request_id uuid, employee_id uuid, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid(); -- FIXED: Use auth.uid() to refer to auth.users(id) and satisfy FK constraint
  v_actor_name text := public.get_my_full_name();
  v_employee public.plantilla%rowtype;
  v_request_id uuid;
  -- Single friendly message for every duplicate-pending path. Contains
  -- 'pending' so the Flutter _friendlyPostgrestMessage maps it to the reliever
  -- reservation copy; never leaks the raw unique_violation / constraint name.
  v_dup_message constant text :=
    'A pending coverage request already exists for this reliever.';
BEGIN
  IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'forbidden: Ops role required to request coverage'
      USING ERRCODE = '42501';
  END IF;

  IF p_employee_id IS NULL OR p_pool_type_id IS NULL THEN
    RAISE EXCEPTION 'employee and pool type are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_requested_account_id IS NULL OR p_requested_store_id IS NULL THEN
    RAISE EXCEPTION 'requested account and store are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_start_date > p_end_date THEN
    RAISE EXCEPTION 'start_date must be on or before end_date'
      USING ERRCODE = '22007';
  END IF;

  IF NOT public.fn_wf_account_in_scope(p_requested_account_id) THEN
    RAISE EXCEPTION 'forbidden: requested account outside user scope'
      USING ERRCODE = '42501';
  END IF;

  -- Serialize concurrent callers on the same reliever.
  SELECT *
    INTO v_employee
    FROM public.plantilla
   WHERE id = p_employee_id
   FOR UPDATE;

  IF NOT FOUND
     OR COALESCE(v_employee.is_deleted, false)
     OR COALESCE(v_employee.is_pool_employee, false) = false THEN
    RAISE EXCEPTION 'employee is not requestable'
      USING ERRCODE = '22023';
  END IF;

  IF v_employee.deactivated_at IS NOT NULL
     OR v_employee.status IS DISTINCT FROM 'Active' THEN
    RAISE EXCEPTION 'inactive employee cannot be requested for coverage'
      USING ERRCODE = '22023';
  END IF;

  -- Pre-check: friendly rejection for an already-pending reservation.
  IF EXISTS (
    SELECT 1
      FROM public.workforce_assignment_requests war
     WHERE war.employee_id = p_employee_id
       AND war.status = 'Pending'
  ) THEN
    RAISE EXCEPTION '%', v_dup_message
      USING ERRCODE = '23505';
  END IF;

  -- Insert; if a concurrent caller won the race, the partial unique index raises
  -- unique_violation. Catch it and re-raise the SAME friendly message so the
  -- client never sees the raw constraint detail.
  BEGIN
    INSERT INTO public.workforce_assignment_requests (
      employee_id,
      pool_type_id,
      requested_account_id,
      requested_group_id,
      requested_store_id,
      requested_position,
      requested_by,
      requested_by_id,
      start_date,
      end_date,
      priority,
      reason,
      status,
      created_at,
      updated_at
    )
    VALUES (
      p_employee_id,
      p_pool_type_id,
      p_requested_account_id,
      p_requested_group_id,
      p_requested_store_id,
      NULLIF(BTRIM(COALESCE(p_requested_position, '')), ''),
      v_actor_name,
      v_actor,
      p_start_date,
      p_end_date,
      COALESCE(NULLIF(BTRIM(p_priority), ''), 'Normal'),
      NULLIF(BTRIM(COALESCE(p_reason, '')), ''),
      'Pending',
      NOW(),
      NOW()
    )
    RETURNING id INTO v_request_id;
  EXCEPTION
    WHEN unique_violation THEN
      RAISE EXCEPTION '%', v_dup_message
        USING ERRCODE = '23505';
  END;

  RETURN QUERY
  SELECT
    v_request_id,
    p_employee_id,
    'Pending'::text,
    'Coverage request submitted. Waiting for Data Team approval.'::text;
END;
$function$;
