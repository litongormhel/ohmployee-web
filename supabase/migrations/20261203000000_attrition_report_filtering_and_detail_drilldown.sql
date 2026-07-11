-- §1  fn_get_attrition_details
-- ============================================================
-- Returns separated employee records for selected account/group
-- within selected date range. This function is SECURITY DEFINER
-- and queries the raw plantilla table to bypass view visibility
-- boundaries, but performs scope checks to ensure security.

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
  area_province       text
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
    COALESCE(s.area_province, s.province)::text AS area_province
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


-- §2  report_attrition_by_group (Updated)
-- ============================================================
-- Modified to remove the HAVING COUNT(sep.account_id) > 0 clause
-- so all accounts/groups appear for the selected date range.

CREATE OR REPLACE FUNCTION public.report_attrition_by_group(
  p_start_date date,
  p_end_date   date,
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL
)
RETURNS TABLE (
  group_id              uuid,
  group_name            text,
  account_id            uuid,
  account_name          text,
  total_count           bigint,
  affected_store_count  bigint,
  period_start          date,
  period_end            date,
  attrition_rate        numeric
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
    RAISE EXCEPTION 'unauthenticated: report_attrition_by_group requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'p_end_date must be >= p_start_date'
      USING ERRCODE = '22000';
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
    RAISE EXCEPTION 'forbidden: report_attrition_by_group caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scope_check AS (
    -- Resolve accounts the caller may see
    SELECT ac.id AS account_id
    FROM public.accounts ac
    WHERE ac.is_active = TRUE
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
  ),
  separated AS (
    SELECT
      p.account_id,
      p.store_id,
      -- headcount active during the window for denominator
      1 AS is_active_in_period
    FROM public.plantilla p
    WHERE p.is_deleted = FALSE
      AND (
        -- separated within the window
        (p.date_of_separation IS NOT NULL AND p.date_of_separation BETWEEN p_start_date AND p_end_date)
        OR
        (p.deactivated_at IS NOT NULL AND p.deactivated_at::date BETWEEN p_start_date AND p_end_date)
      )
      AND p.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
  ),
  active_in_period AS (
    -- Employees who were active at any point during the window
    -- (hired on or before period_end AND (not separated OR separated after period_start))
    SELECT
      p.account_id,
      COUNT(*) AS headcount
    FROM public.plantilla p
    WHERE p.is_deleted = FALSE
      AND (p.date_hired IS NULL OR p.date_hired <= p_end_date)
      AND (p.date_of_separation IS NULL OR p.date_of_separation >= p_start_date)
      AND p.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
    GROUP BY p.account_id
  )
  SELECT
    g.id                                                    AS group_id,
    g.group_name                                            AS group_name,
    ac.id                                                   AS account_id,
    ac.account_name                                         AS account_name,
    COUNT(sep.account_id)                                   AS total_count,
    COUNT(DISTINCT sep.store_id)                            AS affected_store_count,
    p_start_date                                            AS period_start,
    p_end_date                                              AS period_end,
    COALESCE(
      ROUND(
        COUNT(sep.account_id)::numeric
        / NULLIF(MAX(aip.headcount), 0)
        * 100,
        2
      ),
      0.00
    )                                                       AS attrition_rate
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  LEFT JOIN separated sep ON sep.account_id = ac.id
  LEFT JOIN active_in_period aip ON aip.account_id = ac.id
  WHERE ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_attrition_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_attrition_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_attrition_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_attrition_by_group(date, date, uuid, uuid) IS
  'Group-scoped attrition report. Counts separated employees (date_of_separation or deactivated_at in range). attrition_rate = separated / active_in_period * 100. Scope-safe: callers see only their allowed accounts. Requires authenticated session.';
