-- §1  fn_get_attrition_details
-- ============================================================
-- Returns separated employee records for selected account/group
-- within selected date range. This function is SECURITY DEFINER
-- and queries the raw plantilla table to bypass view visibility
-- boundaries, but performs scope checks to ensure security.
-- Updated to return employee_no for fallback UI formatting.

DROP FUNCTION IF EXISTS public.fn_get_attrition_details(uuid, date, date);

CREATE OR REPLACE FUNCTION public.fn_get_attrition_details(
  p_account_id uuid,
  p_start_date date,
  p_end_date   date
)
RETURNS TABLE (
  id                  uuid,
  employee_name       text,
  store_name          text,
  "position"          text,
  date_of_separation  date,
  deactivation_reason text,
  deactivated_at      timestamp with time zone,
  area_city           text,
  area_province       text,
  employee_no         text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_level integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: fn_get_attrition_details requires a valid session'
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

  IF v_profile_id IS NULL OR COALESCE(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: fn_get_attrition_details caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- Scope check to ensure user has access to this account
  IF NOT EXISTS (
    SELECT 1
    FROM public.accounts ac
    WHERE ac.id = p_account_id
      AND ac.is_active = TRUE
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR ac.account_name = ANY(public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = ac.id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id
            AND us.account_id IS NULL
            AND us.group_id = ac.group_id
        )
        OR NOT EXISTS (
          SELECT 1 FROM public.user_scopes us_any
          WHERE us_any.user_id = v_profile_id
            AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
        )
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: fn_get_attrition_details scope check failed for account'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.employee_name::text,
    p.store_name::text,
    p.position::text,
    p.date_of_separation,
    p.deactivation_reason::text,
    p.deactivated_at,
    s.area_city::text,
    COALESCE(s.area_province, s.province)::text AS area_province,
    p.employee_no::text
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  WHERE p.is_deleted = FALSE
    AND p.account_id = p_account_id
    AND (
      (p.date_of_separation IS NOT NULL AND p.date_of_separation BETWEEN p_start_date AND p_end_date)
      OR
      (p.deactivated_at IS NOT NULL AND p.deactivated_at::date BETWEEN p_start_date AND p_end_date)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_attrition_details(uuid, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_get_attrition_details(uuid, date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_get_attrition_details(uuid, date, date) TO authenticated;

COMMENT ON FUNCTION public.fn_get_attrition_details(uuid, date, date) IS
  'Fetches separated employee detail records for the selected account in the specified date range. Enforces scope access checks.';
