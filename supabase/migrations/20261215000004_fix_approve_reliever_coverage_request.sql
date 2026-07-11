-- Fix approve_reliever_coverage_request function column reference ambiguity and status mapping.
-- Resolves "column reference 'status' is ambiguous" error.

CREATE OR REPLACE FUNCTION public.approve_reliever_coverage_request(p_request_id uuid, p_assigned_employee_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(request_id uuid, assignment_id uuid, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_req           RECORD;
  v_final_emp_id  UUID;
  v_new_assign_id UUID;
  v_caller_name   TEXT;
BEGIN
  -- Data Team / Head Admin / Super Admin only
  IF NOT (
    get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;

  SELECT * INTO v_req
  FROM workforce_assignment_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;
  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'Only Pending requests can be approved. Current status: %', v_req.status;
  END IF;

  v_final_emp_id := COALESCE(p_assigned_employee_id, v_req.employee_id);

  -- Active check
  IF NOT EXISTS (
    SELECT 1 FROM plantilla
    WHERE id = v_final_emp_id
      AND is_deleted = false
      AND deactivated_at IS NULL
      AND plantilla.status = 'Active' -- FIXED: qualified status column to avoid ambiguity with output table status column
  ) THEN
    RAISE EXCEPTION 'Assigned employee not found or inactive.';
  END IF;

  -- Pool enrollment check
  IF NOT EXISTS (
    SELECT 1
    FROM workforce_pool_slots wps
    JOIN plantilla pt ON pt.vcode = wps.vcode
    WHERE pt.id = v_final_emp_id
      AND wps.is_active = true
      AND wps.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Assigned employee is not enrolled in workforce pool.';
  END IF;

  -- Group visibility check on override employee
  IF p_assigned_employee_id IS NOT NULL AND p_assigned_employee_id <> v_req.employee_id THEN
    IF NOT EXISTS (
      SELECT 1
      FROM workforce_pool_slots wps
      JOIN plantilla pt ON pt.vcode = wps.vcode
      WHERE pt.id = v_final_emp_id
        AND wps.is_active = true
        AND wps.deleted_at IS NULL
        AND (
          wps.group_id IS NULL
          OR wps.group_id = (
            SELECT wps2.group_id
            FROM workforce_pool_slots wps2
            JOIN plantilla pt2 ON pt2.vcode = wps2.vcode
            WHERE pt2.id = v_req.employee_id
              AND wps2.is_active = true
              AND wps2.deleted_at IS NULL
            LIMIT 1
          )
        )
    ) THEN
      RAISE EXCEPTION 'Override employee is not globally visible or not in the same group as the original request.';
    END IF;
  END IF;

  v_caller_name := get_my_full_name();

  INSERT INTO workforce_assignments (
    employee_id, pool_type_id,
    assigned_group_id, assigned_account_id, assigned_store_id,
    priority, start_date, end_date,
    status, requested_by, approved_by, approved_at,
    notes, created_at, created_by, updated_at, updated_by
  ) VALUES (
    v_final_emp_id, v_req.pool_type_id,
    v_req.requested_group_id, v_req.requested_account_id, v_req.requested_store_id,
    v_req.priority, v_req.start_date, v_req.end_date,
    'Approved', v_req.requested_by, v_caller_name, now(),
    COALESCE(p_notes, v_req.notes),
    now(), v_caller_name, now(), v_caller_name
  )
  RETURNING id INTO v_new_assign_id;

  UPDATE workforce_assignment_requests
  SET
    status                  = 'Approved', -- UPDATED: status becomes 'Approved' instead of 'ConvertedToDeployment'
    converted_assignment_id = v_new_assign_id,
    reviewed_by             = v_caller_name,
    reviewed_at             = now(),
    notes                   = COALESCE(p_notes, notes),
    updated_at              = now()
  WHERE id = p_request_id;

  RETURN QUERY
  SELECT
    p_request_id,
    v_new_assign_id,
    'Approved'::TEXT, -- UPDATED: returns 'Approved' instead of 'ConvertedToDeployment'
    'Request approved. Workforce assignment created.'::TEXT;
END;
$function$
;
