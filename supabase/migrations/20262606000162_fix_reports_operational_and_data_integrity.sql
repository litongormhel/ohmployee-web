-- ============================================================================
-- Migration: 20262606000162_fix_reports_operational_and_data_integrity.sql
-- Description: Fix operational group reports, floating staff report, team
--              performance, and data integrity audits:
--              1. Support NULL date filters (preset "All Dates") across
--                 report_resigned_by_group, report_awol_by_group,
--                 report_time_to_fill_by_group, and report_hr_emploc_late_update_by_group.
--              2. Broaden separation status recognition to include
--                 'Resignation', 'Terminated', and 'End of Contract' alongside
--                 case-insensitive deactivation_reason checks.
--              3. Use COALESCE(date_of_separation, deactivated_at::date) fallback
--                 so records without an explicit date_of_separation are counted.
--              4. Fix report_hr_emploc_late_update_by_group SLA evaluation when
--                 p_end_date is NULL and filter affected_store_count to late stores only.
--              5. Fix fn_report_floating_employees to catch status='Floating'
--                 or separation_status='Floating' with inactive_at fallback.
--              6. Update fn_data_integrity_* and fn_team_performance_* to count
--                 all involuntary separations (Terminated, End of Contract) and
--                 use the date_of_separation/deactivated_at date fallback.
-- Invariants:
--              - Non-breaking view and RPC parameter signatures preserved.
--              - Mobile and Web compatibility intact.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. public.report_resigned_by_group
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.report_resigned_by_group(
  p_start_date date DEFAULT NULL,
  p_end_date   date DEFAULT NULL,
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
  period_end            date
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
    RAISE EXCEPTION 'unauthenticated: report_resigned_by_group requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
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
    RAISE EXCEPTION 'forbidden: report_resigned_by_group caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scope_check AS (
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
  )
  SELECT
    g.id                              AS group_id,
    g.group_name                      AS group_name,
    ac.id                             AS account_id,
    ac.account_name                   AS account_name,
    COUNT(p.id)                       AS total_count,
    COUNT(DISTINCT p.store_id)        AS affected_store_count,
    p_start_date                      AS period_start,
    p_end_date                        AS period_end
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  JOIN public.plantilla p ON p.account_id = ac.id
  WHERE p.is_deleted = FALSE
    AND (
      p.separation_status IN ('Resigned', 'Resignation')
      OR p.deactivation_reason ILIKE '%resign%'
    )
    AND COALESCE(p.date_of_separation, p.deactivated_at::date) IS NOT NULL
    AND (p_start_date IS NULL OR COALESCE(p.date_of_separation, p.deactivated_at::date) >= p_start_date)
    AND (p_end_date IS NULL OR COALESCE(p.date_of_separation, p.deactivated_at::date) <= p_end_date)
    AND ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_resigned_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_resigned_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_resigned_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_resigned_by_group(date, date, uuid, uuid) IS
  'Group-scoped resigned employees report. Filters plantilla rows where '
  'separation_status is Resigned/Resignation or deactivation_reason indicates resignation. '
  'Supports NULL date range for all-time view. Scope-safe.';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. public.report_awol_by_group
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.report_awol_by_group(
  p_start_date date DEFAULT NULL,
  p_end_date   date DEFAULT NULL,
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
  period_end            date
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
    RAISE EXCEPTION 'unauthenticated: report_awol_by_group requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
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
    RAISE EXCEPTION 'forbidden: report_awol_by_group caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scope_check AS (
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
  )
  SELECT
    g.id                              AS group_id,
    g.group_name                      AS group_name,
    ac.id                             AS account_id,
    ac.account_name                   AS account_name,
    COUNT(p.id)                       AS total_count,
    COUNT(DISTINCT p.store_id)        AS affected_store_count,
    p_start_date                      AS period_start,
    p_end_date                        AS period_end
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  JOIN public.plantilla p ON p.account_id = ac.id
  WHERE p.is_deleted = FALSE
    AND (
      p.separation_status = 'AWOL'
      OR p.deactivation_reason ILIKE '%awol%'
    )
    AND COALESCE(p.date_of_separation, p.deactivated_at::date) IS NOT NULL
    AND (p_start_date IS NULL OR COALESCE(p.date_of_separation, p.deactivated_at::date) >= p_start_date)
    AND (p_end_date IS NULL OR COALESCE(p.date_of_separation, p.deactivated_at::date) <= p_end_date)
    AND ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_awol_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_awol_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_awol_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_awol_by_group(date, date, uuid, uuid) IS
  'Group-scoped AWOL employees report. Filters plantilla rows where '
  'separation_status is AWOL or deactivation_reason indicates AWOL. '
  'Supports NULL date range for all-time view. Scope-safe.';

-- ────────────────────────────────────────────────────────────────────────────
-- 3. public.report_time_to_fill_by_group
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.report_time_to_fill_by_group(
  p_start_date date DEFAULT NULL,
  p_end_date   date DEFAULT NULL,
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
  avg_days_to_fill      numeric
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
    RAISE EXCEPTION 'unauthenticated: report_time_to_fill_by_group requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
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
    RAISE EXCEPTION 'forbidden: report_time_to_fill_by_group caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scope_check AS (
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
  filled AS (
    SELECT
      h.account_id,
      h.store_id,
      GREATEST(0,
        EXTRACT(day FROM (
          h.moved_to_plantilla_at
          - COALESCE(v.vacant_date, v.created_at::date)::timestamptz
        ))
      )::integer AS days_to_fill
    FROM public.hr_emploc h
    JOIN public.vacancies v ON v.id = h.vacancy_id
    WHERE h.deleted_at IS NULL
      AND h.moved_to_plantilla_at IS NOT NULL
      AND (p_start_date IS NULL OR h.moved_to_plantilla_at::date >= p_start_date)
      AND (p_end_date IS NULL OR h.moved_to_plantilla_at::date <= p_end_date)
      AND v.status = 'Filled'
      AND h.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR h.account_id = p_account_id)
  )
  SELECT
    g.id                              AS group_id,
    g.group_name                      AS group_name,
    ac.id                             AS account_id,
    ac.account_name                   AS account_name,
    COUNT(f.account_id)               AS total_count,
    COUNT(DISTINCT f.store_id)        AS affected_store_count,
    p_start_date                      AS period_start,
    p_end_date                        AS period_end,
    ROUND(AVG(f.days_to_fill), 1)     AS avg_days_to_fill
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  LEFT JOIN filled f ON f.account_id = ac.id
  WHERE ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  HAVING COUNT(f.account_id) > 0
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_time_to_fill_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_time_to_fill_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_time_to_fill_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_time_to_fill_by_group(date, date, uuid, uuid) IS
  'Group-scoped Time to Fill report. Counts vacancies moved to Plantilla in the period. '
  'Supports NULL date range for all-time view. Scope-safe.';

-- ────────────────────────────────────────────────────────────────────────────
-- 4. public.report_hr_emploc_late_update_by_group
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.report_hr_emploc_late_update_by_group(
  p_start_date date DEFAULT NULL,
  p_end_date   date DEFAULT NULL,
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
  late_count            bigint
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
    RAISE EXCEPTION 'unauthenticated: report_hr_emploc_late_update_by_group requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
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
    RAISE EXCEPTION 'forbidden: report_hr_emploc_late_update_by_group caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scope_check AS (
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
  emplocs AS (
    SELECT
      h.account_id,
      h.store_id,
      CASE
        WHEN h.status <> 'Moved to Plantilla'
          AND COALESCE(h.date_requested, h.created_at) < (COALESCE(p_end_date, CURRENT_DATE)::timestamptz - INTERVAL '3 days')
          THEN TRUE
        WHEN h.status = 'Moved to Plantilla'
          AND h.moved_to_plantilla_at IS NOT NULL
          AND (h.moved_to_plantilla_at::date - COALESCE(h.date_requested, h.created_at)::date) > 3
          THEN TRUE
        ELSE FALSE
      END AS is_late
    FROM public.hr_emploc h
    WHERE h.deleted_at IS NULL
      AND (p_start_date IS NULL OR COALESCE(h.date_requested, h.created_at)::date >= p_start_date)
      AND (p_end_date IS NULL OR COALESCE(h.date_requested, h.created_at)::date <= p_end_date)
      AND h.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR h.account_id = p_account_id)
  )
  SELECT
    g.id                                              AS group_id,
    g.group_name                                      AS group_name,
    ac.id                                             AS account_id,
    ac.account_name                                   AS account_name,
    COUNT(e.account_id)                               AS total_count,
    COUNT(DISTINCT e.store_id) FILTER (WHERE e.is_late) AS affected_store_count,
    p_start_date                                      AS period_start,
    p_end_date                                        AS period_end,
    COUNT(e.account_id) FILTER (WHERE e.is_late)      AS late_count
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  LEFT JOIN emplocs e ON e.account_id = ac.id
  WHERE ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  HAVING COUNT(e.account_id) > 0
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_hr_emploc_late_update_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_hr_emploc_late_update_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_hr_emploc_late_update_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_hr_emploc_late_update_by_group(date, date, uuid, uuid) IS
  'Group-scoped HR Emploc Late Update report. Counts records with date_requested in '
  'the period; late_count = SLA-breached rows (> 3 days). Supports NULL dates. Scope-safe.';

-- ────────────────────────────────────────────────────────────────────────────
-- 5. public.fn_report_floating_employees
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_report_floating_employees(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL
)
RETURNS TABLE (
  plantilla_id    uuid,
  employee_no     text,
  employee_name   text,
  position_title  text,
  account_id      uuid,
  account_name    text,
  group_id        uuid,
  group_name      text,
  store_name      text,
  floating_since  date,
  days_floating   integer,
  employment_type text,
  status          text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_auth_uid   uuid    := auth.uid();
  v_profile_id uuid;
  v_role_level integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: fn_report_floating_employees requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_level
    INTO v_profile_id, v_role_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = v_auth_uid
     AND up.is_active    = TRUE
     AND up.archived_at  IS NULL
   ORDER BY up.created_at DESC
   LIMIT 1;

  IF v_profile_id IS NULL OR COALESCE(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: fn_report_floating_employees caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scope AS (
    SELECT ac.id AS account_id, ac.group_id
      FROM public.accounts ac
     WHERE ac.is_active = TRUE
       AND (
         COALESCE(v_role_level, 0) >= 90
         OR EXISTS (
           SELECT 1 FROM public.user_scopes us
            WHERE us.user_id    = v_profile_id
              AND us.account_id = ac.id
         )
         OR EXISTS (
           SELECT 1 FROM public.user_scopes us
            WHERE us.user_id    = v_profile_id
              AND us.account_id IS NULL
              AND us.group_id   = ac.group_id
         )
         OR NOT EXISTS (
           SELECT 1 FROM public.user_scopes us_any
            WHERE us_any.user_id = v_profile_id
              AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
         )
       )
  )
  SELECT
    p.id,
    p.employee_no,
    p.employee_name,
    COALESCE(p."position", '')            AS position_title,
    a.id                                  AS account_id,
    a.account_name,
    g.id                                  AS group_id,
    COALESCE(g.group_name, '')            AS group_name,
    COALESCE(p.store_name, '')            AS store_name,
    COALESCE(p.inactive_at::date, p.updated_at::date, CURRENT_DATE) AS floating_since,
    (CURRENT_DATE - COALESCE(p.inactive_at::date, p.updated_at::date, CURRENT_DATE))::integer AS days_floating,
    COALESCE(p.deployment_type, 'Stationary') AS employment_type,
    'Floating'::text                      AS status
  FROM public.plantilla p
  JOIN public.accounts  a ON a.id = p.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE (p.status = 'Floating' OR p.separation_status = 'Floating')
    AND p.status <> 'Active'
    AND COALESCE(p.is_deleted, false) = false
    AND p.account_id IN (SELECT sc.account_id FROM scope sc)
    AND (p_account_id IS NULL OR p.account_id = p_account_id)
    AND (p_group_id   IS NULL OR a.group_id   = p_group_id)
  ORDER BY
    a.account_name ASC,
    (CURRENT_DATE - COALESCE(p.inactive_at::date, p.updated_at::date, CURRENT_DATE)) DESC,
    p.employee_name ASC;
END;
$func$;

REVOKE ALL ON FUNCTION public.fn_report_floating_employees(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_report_floating_employees(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_report_floating_employees(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.fn_report_floating_employees(uuid, uuid) IS
  'Floating Employees Report RPC. Filters plantilla where status=Floating or '
  'separation_status=Floating, with fallback on inactive_at or updated_at date. Scope-safe.';

-- ────────────────────────────────────────────────────────────────────────────
-- 6. public.fn_data_integrity_summary
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_data_integrity_summary(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_level integer;

  v_late_hr_count    bigint  := 0;
  v_late_hr_stores   bigint  := 0;
  v_late_hr_worst    integer := 0;

  v_vac_delay_count  bigint  := 0;
  v_vac_delay_stores bigint  := 0;
  v_vac_delay_worst  integer := 0;

  v_ghost_count      bigint  := 0;
  v_ghost_stores     bigint  := 0;

  v_pipeline_count   bigint  := 0;
  v_pipeline_stores  bigint  := 0;

  v_total_stores     bigint  := 0;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: fn_data_integrity_summary requires a valid session'
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
    RAISE EXCEPTION 'forbidden: fn_data_integrity_summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- ─── §1a Late HR Updates ────────────────────────────────────────────────────
  SELECT
    COUNT(*)::bigint,
    COUNT(DISTINCT p.store_id)::bigint,
    COALESCE(MAX((p.updated_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date))::integer), 0)
  INTO v_late_hr_count, v_late_hr_stores, v_late_hr_worst
  FROM public.plantilla p
  WHERE p.is_deleted = FALSE
    AND COALESCE(p.date_of_separation, p.deactivated_at::date) IS NOT NULL
    AND (
      p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others', 'Terminated', 'End of Contract')
      OR p.deactivation_reason ILIKE '%terminat%'
      OR p.deactivation_reason ILIKE '%resign%'
      OR p.deactivation_reason ILIKE '%awol%'
    )
    AND (p.updated_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date)) > 7
    AND COALESCE(p.date_of_separation, p.deactivated_at::date) >= CURRENT_DATE - INTERVAL '365 days'
    AND (p_account_id IS NULL OR p.account_id = p_account_id)
    AND (p_group_id IS NULL OR EXISTS (
      SELECT 1 FROM public.accounts ac2
      WHERE ac2.id = p.account_id AND ac2.group_id = p_group_id
    ))
    AND p.account_id IN (
      SELECT ac.id FROM public.accounts ac
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
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR NOT EXISTS (
            SELECT 1 FROM public.user_scopes us_any
            WHERE us_any.user_id = v_profile_id
              AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
          )
        )
    );

  -- ─── §1b Vacancy Creation Delay ─────────────────────────────────────────────
  SELECT
    COUNT(*)::bigint,
    COUNT(DISTINCT sub.store_id)::bigint,
    COALESCE(MAX(sub.delay_days), 0)
  INTO v_vac_delay_count, v_vac_delay_stores, v_vac_delay_worst
  FROM (
    SELECT DISTINCT ON (p.id)
      p.id,
      p.store_id,
      (v.created_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date))::integer AS delay_days
    FROM public.plantilla p
    JOIN public.vacancies v
      ON v.store_id = p.store_id
     AND v.created_at > COALESCE(p.date_of_separation, p.deactivated_at::date)::timestamptz
     AND v.deleted_at IS NULL
     AND COALESCE(v.is_archived, false) = false
    WHERE p.is_deleted = FALSE
      AND COALESCE(p.date_of_separation, p.deactivated_at::date) IS NOT NULL
      AND (
        p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others', 'Terminated', 'End of Contract')
        OR p.deactivation_reason ILIKE '%terminat%'
        OR p.deactivation_reason ILIKE '%resign%'
        OR p.deactivation_reason ILIKE '%awol%'
      )
      AND COALESCE(p.date_of_separation, p.deactivated_at::date) >= CURRENT_DATE - INTERVAL '180 days'
      AND (v.created_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date)) > 7
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
      AND (p_group_id IS NULL OR EXISTS (
        SELECT 1 FROM public.accounts ac2
        WHERE ac2.id = p.account_id AND ac2.group_id = p_group_id
      ))
      AND p.account_id IN (
        SELECT ac.id FROM public.accounts ac
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
              WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
            )
            OR NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
          )
      )
    ORDER BY p.id, v.created_at
  ) sub;

  -- ─── §1c Ghost Occupancy ────────────────────────────────────────────────────
  SELECT
    COUNT(*)::bigint,
    COUNT(DISTINCT ps.store_id)::bigint
  INTO v_ghost_count, v_ghost_stores
  FROM public.plantilla_slots ps
  WHERE ps.slot_status = 'occupied'
    AND COALESCE(ps.is_roving, false) = false
    AND (p_account_id IS NULL OR ps.account_id = p_account_id)
    AND (p_group_id IS NULL OR ps.group_id = p_group_id)
    AND ps.account_id IN (
      SELECT ac.id FROM public.accounts ac
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
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR NOT EXISTS (
            SELECT 1 FROM public.user_scopes us_any
            WHERE us_any.user_id = v_profile_id
              AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
          )
        )
    )
    AND (
      ps.current_occupant_plantilla_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE p.id = ps.current_occupant_plantilla_id
          AND p.is_deleted = FALSE
          AND (
            p.status NOT IN ('Active', 'On Leave')
            OR p.date_of_separation IS NOT NULL
            OR p.deactivated_at IS NOT NULL
          )
      )
    );

  -- ─── §1d Pipeline Without Vacancy ───────────────────────────────────────────
  SELECT
    COUNT(*)::bigint,
    COUNT(DISTINCT v.store_id)::bigint
  INTO v_pipeline_count, v_pipeline_stores
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE COALESCE(a.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a.status) = true
    AND v.status NOT IN ('Open', 'For Sourcing')
    AND v.deleted_at IS NULL
    AND COALESCE(v.is_archived, false) = false
    AND (p_account_id IS NULL OR v.account_id = p_account_id)
    AND (p_group_id IS NULL OR EXISTS (
      SELECT 1 FROM public.accounts ac2
      WHERE ac2.id = v.account_id AND ac2.group_id = p_group_id
    ))
    AND v.account_id IN (
      SELECT ac.id FROM public.accounts ac
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
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
          )
          OR NOT EXISTS (
            SELECT 1 FROM public.user_scopes us_any
            WHERE us_any.user_id = v_profile_id
              AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
          )
        )
    );

  -- ─── §1e Total Affected Stores (union across all sections) ──────────────────
  SELECT COUNT(DISTINCT all_stores.store_id)
  INTO v_total_stores
  FROM (
    SELECT p.store_id
    FROM public.plantilla p
    WHERE p.is_deleted = FALSE
      AND COALESCE(p.date_of_separation, p.deactivated_at::date) IS NOT NULL
      AND (
        p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others', 'Terminated', 'End of Contract')
        OR p.deactivation_reason ILIKE '%terminat%'
        OR p.deactivation_reason ILIKE '%resign%'
        OR p.deactivation_reason ILIKE '%awol%'
      )
      AND (p.updated_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date)) > 7
      AND COALESCE(p.date_of_separation, p.deactivated_at::date) >= CURRENT_DATE - INTERVAL '365 days'
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
      AND (p_group_id IS NULL OR EXISTS (
        SELECT 1 FROM public.accounts ac2 WHERE ac2.id = p.account_id AND ac2.group_id = p_group_id
      ))
      AND p.account_id IN (
        SELECT ac.id FROM public.accounts ac WHERE ac.is_active = TRUE
          AND (COALESCE(v_role_level,0)>=90 OR ac.account_name=ANY(public.get_my_allowed_accounts())
            OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id=ac.id)
            OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id IS NULL AND us.group_id=ac.group_id)
            OR NOT EXISTS(SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id=v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)))
      )
    UNION
    SELECT ps.store_id
    FROM public.plantilla_slots ps
    WHERE ps.slot_status = 'occupied' AND COALESCE(ps.is_roving,false)=false
      AND (p_account_id IS NULL OR ps.account_id = p_account_id)
      AND (p_group_id IS NULL OR ps.group_id = p_group_id)
      AND ps.account_id IN (
        SELECT ac.id FROM public.accounts ac WHERE ac.is_active=TRUE
          AND (COALESCE(v_role_level,0)>=90 OR ac.account_name=ANY(public.get_my_allowed_accounts())
            OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id=ac.id)
            OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id IS NULL AND us.group_id=ac.group_id)
            OR NOT EXISTS(SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id=v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)))
      )
      AND (ps.current_occupant_plantilla_id IS NULL OR EXISTS(
        SELECT 1 FROM public.plantilla p WHERE p.id=ps.current_occupant_plantilla_id AND p.is_deleted=FALSE
          AND (p.status NOT IN('Active','On Leave') OR p.date_of_separation IS NOT NULL OR p.deactivated_at IS NOT NULL)
      ))
    UNION
    SELECT v.store_id
    FROM public.applicants a
    JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
    WHERE COALESCE(a.is_archived,false)=false AND public.fn_is_active_vacancy_applicant_status(a.status)=true
      AND v.status NOT IN('Open','For Sourcing') AND v.deleted_at IS NULL AND COALESCE(v.is_archived,false)=false
      AND (p_account_id IS NULL OR v.account_id=p_account_id)
      AND (p_group_id IS NULL OR EXISTS(SELECT 1 FROM public.accounts ac2 WHERE ac2.id=v.account_id AND ac2.group_id=p_group_id))
      AND v.account_id IN (
        SELECT ac.id FROM public.accounts ac WHERE ac.is_active=TRUE
          AND (COALESCE(v_role_level,0)>=90 OR ac.account_name=ANY(public.get_my_allowed_accounts())
            OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id=ac.id)
            OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id IS NULL AND us.group_id=ac.group_id)
            OR NOT EXISTS(SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id=v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)))
      )
  ) all_stores
  WHERE all_stores.store_id IS NOT NULL;

  RETURN jsonb_build_object(
    'kpis', jsonb_build_object(
      'critical_issues',  v_ghost_count,
      'high_risk_issues', v_pipeline_count + v_vac_delay_count,
      'total_findings',   v_ghost_count + v_pipeline_count + v_vac_delay_count + v_late_hr_count,
      'affected_stores',  v_total_stores
    ),
    'late_hr_updates', jsonb_build_object(
      'affected_stores',    v_late_hr_stores,
      'affected_employees', v_late_hr_count,
      'worst_delay',        v_late_hr_worst,
      'total_findings',     v_late_hr_count
    ),
    'vacancy_creation_delay', jsonb_build_object(
      'affected_stores',    v_vac_delay_stores,
      'affected_employees', v_vac_delay_count,
      'worst_delay',        v_vac_delay_worst,
      'total_findings',     v_vac_delay_count
    ),
    'ghost_occupancy', jsonb_build_object(
      'affected_stores',   v_ghost_stores,
      'critical_findings', v_ghost_count,
      'total_findings',    v_ghost_count
    ),
    'pipeline_no_vacancy', jsonb_build_object(
      'active_findings', v_pipeline_count,
      'affected_stores', v_pipeline_stores,
      'total_findings',  v_pipeline_count
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_data_integrity_summary(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_data_integrity_summary(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_data_integrity_summary(uuid, uuid) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 7. public.fn_data_integrity_late_hr_detail
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_data_integrity_late_hr_detail(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL,
  p_sla_days   integer DEFAULT 7,
  p_page       integer DEFAULT 0,
  p_page_size  integer DEFAULT 50
)
RETURNS TABLE (
  store_name    text,
  account_name  text,
  group_name    text,
  employee_name text,
  employee_no   text,
  "position"    text,
  effective_date date,
  recorded_date  date,
  delay_days     integer,
  issue_type     text,
  detected_date  date
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
    RAISE EXCEPTION 'unauthenticated: fn_data_integrity_late_hr_detail requires a valid session'
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
    RAISE EXCEPTION 'forbidden: fn_data_integrity_late_hr_detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.store_name::text,
    ac.account_name::text,
    g.group_name::text,
    p.employee_name::text,
    p.employee_no::text,
    p.position::text,
    COALESCE(p.date_of_separation, p.deactivated_at::date) AS effective_date,
    p.updated_at::date                 AS recorded_date,
    (p.updated_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date))::integer AS delay_days,
    p.separation_status::text          AS issue_type,
    CURRENT_DATE                       AS detected_date
  FROM public.plantilla p
  JOIN public.accounts ac ON ac.id = p.account_id
  JOIN public.groups g    ON g.id  = ac.group_id
  WHERE p.is_deleted = FALSE
    AND COALESCE(p.date_of_separation, p.deactivated_at::date) IS NOT NULL
    AND (
      p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others', 'Terminated', 'End of Contract')
      OR p.deactivation_reason ILIKE '%terminat%'
      OR p.deactivation_reason ILIKE '%resign%'
      OR p.deactivation_reason ILIKE '%awol%'
    )
    AND (p.updated_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date)) > p_sla_days
    AND COALESCE(p.date_of_separation, p.deactivated_at::date) >= CURRENT_DATE - INTERVAL '365 days'
    AND (p_account_id IS NULL OR p.account_id = p_account_id)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND p.account_id IN (
      SELECT ac2.id FROM public.accounts ac2
      WHERE ac2.is_active = TRUE
        AND (
          COALESCE(v_role_level, 0) >= 90
          OR ac2.account_name = ANY(public.get_my_allowed_accounts())
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id = ac2.id
          )
          OR EXISTS (
            SELECT 1 FROM public.user_scopes us
            WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac2.group_id
          )
          OR NOT EXISTS (
            SELECT 1 FROM public.user_scopes us_any
            WHERE us_any.user_id = v_profile_id
              AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
          )
        )
    )
  ORDER BY delay_days DESC, COALESCE(p.date_of_separation, p.deactivated_at::date) DESC
  LIMIT p_page_size OFFSET (p_page * p_page_size);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_data_integrity_late_hr_detail(uuid, uuid, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_data_integrity_late_hr_detail(uuid, uuid, integer, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_data_integrity_late_hr_detail(uuid, uuid, integer, integer, integer) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 8. public.fn_data_integrity_vacancy_delay_detail
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_data_integrity_vacancy_delay_detail(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL,
  p_sla_days   integer DEFAULT 7,
  p_page       integer DEFAULT 0,
  p_page_size  integer DEFAULT 50
)
RETURNS TABLE (
  store_name              text,
  account_name            text,
  group_name              text,
  employee_name           text,
  "position"              text,
  effective_departure_date date,
  vacancy_created_date    date,
  delay_days              integer,
  vcode                   text,
  detected_date           date
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
    RAISE EXCEPTION 'unauthenticated: fn_data_integrity_vacancy_delay_detail requires a valid session'
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
    RAISE EXCEPTION 'forbidden: fn_data_integrity_vacancy_delay_detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped_accounts AS (
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
          WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
        )
        OR NOT EXISTS (
          SELECT 1 FROM public.user_scopes us_any
          WHERE us_any.user_id = v_profile_id
            AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
        )
      )
  ),
  ranked AS (
    SELECT
      p.store_name,
      ac.account_name,
      g.group_name,
      p.employee_name,
      p.position,
      COALESCE(p.date_of_separation, p.deactivated_at::date) AS date_of_separation,
      v.created_at::date                              AS vacancy_created_date,
      (v.created_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date))::integer AS delay_days,
      v.vcode,
      ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY v.created_at) AS rn
    FROM public.plantilla p
    JOIN public.accounts ac ON ac.id = p.account_id
    JOIN public.groups g    ON g.id  = ac.group_id
    JOIN public.vacancies v
      ON v.store_id = p.store_id
     AND v.created_at > COALESCE(p.date_of_separation, p.deactivated_at::date)::timestamptz
     AND v.deleted_at IS NULL
     AND COALESCE(v.is_archived, false) = false
    WHERE p.is_deleted = FALSE
      AND COALESCE(p.date_of_separation, p.deactivated_at::date) IS NOT NULL
      AND (
        p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others', 'Terminated', 'End of Contract')
        OR p.deactivation_reason ILIKE '%terminat%'
        OR p.deactivation_reason ILIKE '%resign%'
        OR p.deactivation_reason ILIKE '%awol%'
      )
      AND COALESCE(p.date_of_separation, p.deactivated_at::date) >= CURRENT_DATE - INTERVAL '180 days'
      AND (v.created_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date)) > p_sla_days
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
      AND (p_group_id IS NULL OR ac.group_id = p_group_id)
      AND p.account_id IN (SELECT sa.account_id FROM scoped_accounts sa)
  )
  SELECT
    r.store_name::text,
    r.account_name::text,
    r.group_name::text,
    r.employee_name::text,
    r.position::text,
    r.date_of_separation       AS effective_departure_date,
    r.vacancy_created_date,
    r.delay_days,
    r.vcode::text,
    CURRENT_DATE               AS detected_date
  FROM ranked r
  WHERE r.rn = 1
  ORDER BY r.delay_days DESC, r.date_of_separation DESC
  LIMIT p_page_size OFFSET (p_page * p_page_size);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_data_integrity_vacancy_delay_detail(uuid, uuid, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_data_integrity_vacancy_delay_detail(uuid, uuid, integer, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_data_integrity_vacancy_delay_detail(uuid, uuid, integer, integer, integer) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 9. public.fn_team_performance_summary & public.fn_team_performance_detail
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_team_performance_summary(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authenticated access required';
  END IF;

  WITH
  base_accounts AS (
    SELECT
      a.id           AS account_id,
      a.account_name,
      g.id           AS group_id,
      g.group_name,
      (
        SELECT up.full_name
        FROM users_profile up
        WHERE up.id = a.hrco_user_id
        LIMIT 1
      ) AS hrco_name
    FROM accounts a
    JOIN groups g ON g.id = a.group_id
    WHERE
      (p_group_id   IS NULL OR g.id = p_group_id)
      AND (p_account_id IS NULL OR a.id = p_account_id)
      AND (
        i_have_full_access()
        OR a.account_name = ANY(get_my_allowed_accounts())
      )
  ),

  actual_hc AS (
    SELECT account_id, COUNT(*) AS hc
    FROM plantilla
    WHERE status IN ('Active', 'On Leave')
      AND is_deleted = false
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  vacant_hc AS (
    SELECT account_id, COUNT(*) AS hc
    FROM vacancies
    WHERE status = 'Open'
      AND deleted_at IS NULL
      AND archived_at IS NULL
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  aged_vac AS (
    SELECT account_id, COUNT(*) AS cnt
    FROM vacancies
    WHERE status = 'Open'
      AND deleted_at IS NULL
      AND archived_at IS NULL
      AND COALESCE(vacant_date, created_at)::date < CURRENT_DATE - INTERVAL '30 days'
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  late_hr AS (
    SELECT account_id, COUNT(*) AS cnt
    FROM plantilla
    WHERE COALESCE(date_of_separation, deactivated_at::date) IS NOT NULL
      AND is_deleted = false
      AND (updated_at::date - COALESCE(date_of_separation, deactivated_at::date)) > 7
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  metrics AS (
    SELECT
      ba.account_id,
      ba.account_name,
      ba.group_id,
      ba.group_name,
      ba.hrco_name,
      COALESCE(ah.hc, 0)   AS actual_hc,
      COALESCE(vh.hc, 0)   AS vacant_hc,
      (COALESCE(ah.hc, 0) + COALESCE(vh.hc, 0)) AS required_hc,
      COALESCE(av.cnt, 0)  AS aged_vacancies,
      COALESCE(lh.cnt, 0)  AS late_hr_updates,
      CASE
        WHEN (COALESCE(ah.hc, 0) + COALESCE(vh.hc, 0)) = 0 THEN 1.0
        ELSE ROUND(COALESCE(ah.hc, 0)::numeric / (COALESCE(ah.hc, 0) + COALESCE(vh.hc, 0)), 4)
      END AS mfr,
      GREATEST(0.0, LEAST(100.0,
        ROUND(
          (
            CASE
              WHEN (COALESCE(ah.hc, 0) + COALESCE(vh.hc, 0)) = 0 THEN 1.0
              ELSE COALESCE(ah.hc, 0)::numeric / (COALESCE(ah.hc, 0) + COALESCE(vh.hc, 0))
            END * 60
          )
          + (GREATEST(0, 10 - COALESCE(av.cnt, 0))::numeric / 10 * 20)
          + (GREATEST(0, 10 - COALESCE(lh.cnt, 0))::numeric / 10 * 20),
          1
        )
      )) AS score
    FROM base_accounts ba
    LEFT JOIN actual_hc ah ON ah.account_id = ba.account_id
    LEFT JOIN vacant_hc vh ON vh.account_id = ba.account_id
    LEFT JOIN aged_vac  av ON av.account_id = ba.account_id
    LEFT JOIN late_hr   lh ON lh.account_id = ba.account_id
  ),

  leaderboard AS (
    SELECT
      m.account_id,
      m.account_name,
      m.group_id,
      m.group_name,
      m.hrco_name,
      m.actual_hc,
      m.vacant_hc,
      m.required_hc,
      m.aged_vacancies,
      m.late_hr_updates,
      m.mfr,
      m.score
    FROM metrics m
    ORDER BY m.score DESC, m.account_name ASC
  ),

  summary_kpis AS (
    SELECT
      (SELECT group_name FROM metrics ORDER BY score DESC, group_name ASC LIMIT 1) AS best_group,
      (SELECT score FROM metrics ORDER BY score DESC LIMIT 1) AS best_group_score,
      (SELECT group_name FROM metrics ORDER BY score ASC, group_name ASC LIMIT 1)  AS lowest_group,
      (SELECT score FROM metrics ORDER BY score ASC LIMIT 1)  AS lowest_group_score,
      COALESCE(ROUND(AVG(score), 1), 0.0) AS average_score,
      COUNT(*) FILTER (WHERE score < 70)  AS critical_count
    FROM metrics
  )

  SELECT jsonb_build_object(
    'kpis', (
      SELECT jsonb_build_object(
        'best_group',        best_group,
        'best_group_score',  best_group_score,
        'lowest_group',       lowest_group,
        'lowest_group_score', lowest_group_score,
        'average_score',     average_score,
        'critical_count',    critical_count
      )
      FROM summary_kpis
    ),
    'leaderboard', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'account_id',      account_id,
          'account_name',    account_name,
          'group_id',        group_id,
          'group_name',      group_name,
          'hrco_name',       hrco_name,
          'actual_hc',       actual_hc,
          'vacant_hc',       vacant_hc,
          'required_hc',     required_hc,
          'aged_vacancies',  aged_vacancies,
          'late_hr_updates', late_hr_updates,
          'mfr',             mfr,
          'score',           score
        )
      )
      FROM leaderboard
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_team_performance_summary(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_team_performance_summary(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_team_performance_summary(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_team_performance_detail(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL
)
RETURNS TABLE (
  account_id     uuid,
  account_name   text,
  group_id       uuid,
  group_name     text,
  hrco_name      text,
  issue_category text,
  issue_label    text,
  issue_detail   text,
  days_impacted  int,
  store_name     text,
  employee_name  text,
  vcode          text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authenticated access required';
  END IF;

  RETURN QUERY
  WITH
  base_accounts AS (
    SELECT
      a.id           AS acct_id,
      a.account_name AS acct_name,
      g.id           AS grp_id,
      g.group_name   AS grp_name,
      (
        SELECT up.full_name FROM users_profile up
        WHERE up.id = a.hrco_user_id LIMIT 1
      ) AS hrco
    FROM accounts a
    JOIN groups g ON g.id = a.group_id
    WHERE
      (p_group_id   IS NULL OR g.id = p_group_id)
      AND (p_account_id IS NULL OR a.id = p_account_id)
      AND (
        i_have_full_access()
        OR a.account_name = ANY(get_my_allowed_accounts())
      )
  ),

  aged_issues AS (
    SELECT
      ba.acct_id,
      ba.acct_name,
      ba.grp_id,
      ba.grp_name,
      ba.hrco,
      'aged_vacancy'::text                    AS cat,
      'Aged Vacancy'::text                    AS lbl,
      'Open vacancy older than 30 days'::text AS dtl,
      (CURRENT_DATE - COALESCE(v.vacant_date, v.created_at)::date)::int AS days,
      COALESCE(v.store_name, v.account)::text AS store,
      NULL::text                              AS emp,
      v.vcode::text                           AS vc
    FROM vacancies v
    JOIN base_accounts ba ON ba.acct_id = v.account_id
    WHERE v.status = 'Open'
      AND v.deleted_at IS NULL
      AND v.archived_at IS NULL
      AND COALESCE(v.vacant_date, v.created_at)::date < CURRENT_DATE - INTERVAL '30 days'
  ),

  late_hr_issues AS (
    SELECT
      ba.acct_id,
      ba.acct_name,
      ba.grp_id,
      ba.grp_name,
      ba.hrco,
      'late_hr'::text                                                   AS cat,
      'Late HR Update'::text                                            AS lbl,
      'Separation recorded more than 7 days after effective date'::text AS dtl,
      (p.updated_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date))::int AS days,
      COALESCE(p.store_name, '')::text                                  AS store,
      COALESCE(p.employee_name, '')::text                               AS emp,
      NULL::text                                                        AS vc
    FROM plantilla p
    JOIN base_accounts ba ON ba.acct_id = p.account_id
    WHERE COALESCE(p.date_of_separation, p.deactivated_at::date) IS NOT NULL
      AND p.is_deleted = false
      AND (p.updated_at::date - COALESCE(p.date_of_separation, p.deactivated_at::date)) > 7
  )

  SELECT acct_id, acct_name, grp_id, grp_name, hrco, cat, lbl, dtl, days, store, emp, vc
  FROM aged_issues
  UNION ALL
  SELECT acct_id, acct_name, grp_id, grp_name, hrco, cat, lbl, dtl, days, store, emp, vc
  FROM late_hr_issues
  ORDER BY acct_name, cat, days DESC NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_team_performance_detail(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_team_performance_detail(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_team_performance_detail(uuid, uuid) TO authenticated;
