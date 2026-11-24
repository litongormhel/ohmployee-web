-- Migration: 20262606000161_fix_reports_attrition_terminated_backout.sql
-- Created: 2026-11-24T03:38:56.001Z
-- Purpose: Remediate 4 reported defects in Reports Engine:
--   1. Attrition report reason/details not specified:
--      fn_get_attrition_details now falls back from deactivation_reason to remarks,
--      separation_status, and 'Separated', returns separation_status & remarks columns,
--      and handles null date filters safely without returning 0 rows.
--   2. Terminated staff not appearing:
--      report_terminated_by_group now includes 'Terminated' and 'End of Contract'
--      alongside 'Endo' and 'Others', evaluates deactivated_at fallback, and supports null dates.
--   3. Back-out candidates not appearing:
--      report_backout_by_group now captures hr_emploc backouts without false deleted_at filtering
--      and includes pre-onboarding applicant backouts from the vacancy pipeline, deduplicated.
--   4. Back-out & terminated combined failing to load report data:
--      report_backout_terminated_by_group fixes the ambiguous 'account_id' PL/pgSQL variable collision,
--      incorporates the updated backouts & terminated definitions, and supports null date filters.

-- ============================================================
-- §1  fn_get_attrition_details — Reason Resolution & Null-Safe Dates
-- ============================================================

DROP FUNCTION IF EXISTS public.fn_get_attrition_details(uuid, date, date);

CREATE OR REPLACE FUNCTION public.fn_get_attrition_details(
  p_account_id uuid,
  p_start_date date DEFAULT NULL,
  p_end_date   date DEFAULT NULL
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
  employee_no         text,
  separation_status   text,
  remarks             text
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

  -- Validate date ordering when both are supplied
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
    RAISE EXCEPTION 'forbidden: fn_get_attrition_details caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  -- Scope check to ensure caller has access to target account
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
    COALESCE(p.date_of_separation, p.deactivated_at::date) AS date_of_separation,
    COALESCE(NULLIF(TRIM(p.deactivation_reason), ''), NULLIF(TRIM(p.remarks), ''), p.separation_status, 'Separated')::text AS deactivation_reason,
    p.deactivated_at,
    s.area_city::text,
    COALESCE(s.area_province, s.province)::text AS area_province,
    p.employee_no::text,
    p.separation_status::text,
    p.remarks::text
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  WHERE p.is_deleted = FALSE
    AND p.account_id = p_account_id
    AND (
      (
        p.date_of_separation IS NOT NULL
        AND (p_start_date IS NULL OR p.date_of_separation >= p_start_date)
        AND (p_end_date   IS NULL OR p.date_of_separation <= p_end_date)
      )
      OR
      (
        p.deactivated_at IS NOT NULL
        AND (p_start_date IS NULL OR p.deactivated_at::date >= p_start_date)
        AND (p_end_date   IS NULL OR p.deactivated_at::date <= p_end_date)
      )
      OR
      (
        p_start_date IS NULL AND p_end_date IS NULL
        AND (p.status IN ('Inactive', 'Deactivated') OR p.separation_status IS NOT NULL)
      )
    )
  ORDER BY COALESCE(p.date_of_separation, p.deactivated_at::date) DESC NULLS LAST, p.employee_name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_attrition_details(uuid, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_get_attrition_details(uuid, date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_get_attrition_details(uuid, date, date) TO authenticated;

COMMENT ON FUNCTION public.fn_get_attrition_details(uuid, date, date) IS
  'Returns separated employee records for selected account within date range (null dates = all separations). '
  'Resolves reason from deactivation_reason -> remarks -> separation_status -> Separated. '
  'Enforces Rule 5 in-DB ordering: ORDER BY date_of_separation DESC NULLS LAST, employee_name ASC.';


-- ============================================================
-- §2  report_terminated_by_group — Include Terminated & Null Dates
-- ============================================================

DROP FUNCTION IF EXISTS public.report_terminated_by_group(date, date, uuid, uuid);

CREATE OR REPLACE FUNCTION public.report_terminated_by_group(
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
    RAISE EXCEPTION 'unauthenticated: report_terminated_by_group requires a valid session'
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
    RAISE EXCEPTION 'forbidden: report_terminated_by_group caller is not allowed'
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
  terminated AS (
    SELECT
      p.account_id,
      p.store_id
    FROM public.plantilla p
    WHERE p.is_deleted = FALSE
      AND (
        p.separation_status IN ('Terminated', 'End of Contract', 'Endo', 'Others')
        OR p.separation_status ILIKE '%term%'
      )
      AND (
        (
          p.date_of_separation IS NOT NULL
          AND (p_start_date IS NULL OR p.date_of_separation >= p_start_date)
          AND (p_end_date   IS NULL OR p.date_of_separation <= p_end_date)
        )
        OR
        (
          p.deactivated_at IS NOT NULL
          AND (p_start_date IS NULL OR p.deactivated_at::date >= p_start_date)
          AND (p_end_date   IS NULL OR p.deactivated_at::date <= p_end_date)
        )
        OR
        (
          p_start_date IS NULL AND p_end_date IS NULL
        )
      )
      AND p.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
  )
  SELECT
    g.id                                  AS group_id,
    g.group_name                          AS group_name,
    ac.id                                 AS account_id,
    ac.account_name                       AS account_name,
    COUNT(t.account_id)                   AS total_count,
    COUNT(DISTINCT t.store_id)            AS affected_store_count,
    p_start_date                          AS period_start,
    p_end_date                            AS period_end
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  LEFT JOIN terminated t ON t.account_id = ac.id
  WHERE ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_terminated_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_terminated_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_terminated_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_terminated_by_group(date, date, uuid, uuid) IS
  'Group-scoped Terminated report. Counts plantilla employees separated with '
  'separation_status IN (''Terminated'', ''End of Contract'', ''Endo'', ''Others'') within date window. '
  'Supports null dates for all-time view. Scope-safe: callers see only allowed accounts.';


-- ============================================================
-- §3  report_backout_by_group — Include HR Emploc + Applicants & Null Dates
-- ============================================================

DROP FUNCTION IF EXISTS public.report_backout_by_group(date, date, uuid, uuid);

CREATE OR REPLACE FUNCTION public.report_backout_by_group(
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
    RAISE EXCEPTION 'unauthenticated: report_backout_by_group requires a valid session'
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
    RAISE EXCEPTION 'forbidden: report_backout_by_group caller is not allowed'
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
  backouts AS (
    -- 1. HR Emploc back-outs
    SELECT
      h.account_id,
      h.store_id
    FROM public.hr_emploc h
    WHERE (h.status = 'Backout' OR h.backout_date IS NOT NULL OR h.backout_at IS NOT NULL)
      AND (
        p_start_date IS NULL
        OR COALESCE(h.backout_date, h.backout_at::date, h.deleted_at::date, h.updated_at::date, h.created_at::date) >= p_start_date
      )
      AND (
        p_end_date IS NULL
        OR COALESCE(h.backout_date, h.backout_at::date, h.deleted_at::date, h.updated_at::date, h.created_at::date) <= p_end_date
      )
      AND h.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR h.account_id = p_account_id)
    UNION ALL
    -- 2. Vacancy pipeline applicant back-outs (deduplicated against hr_emploc.applicant_id)
    SELECT
      v.account_id,
      v.store_id
    FROM public.applicants a
    JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
    WHERE (a.status ILIKE '%backout%' OR a.backout_date IS NOT NULL)
      AND (
        p_start_date IS NULL
        OR COALESCE(a.backout_date, a.updated_at::date, a.created_at::date) >= p_start_date
      )
      AND (
        p_end_date IS NULL
        OR COALESCE(a.backout_date, a.updated_at::date, a.created_at::date) <= p_end_date
      )
      AND v.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR v.account_id = p_account_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_emploc h2
        WHERE h2.applicant_id = a.id
          AND (h2.status = 'Backout' OR h2.backout_date IS NOT NULL OR h2.backout_at IS NOT NULL)
      )
  )
  SELECT
    g.id                                  AS group_id,
    g.group_name                          AS group_name,
    ac.id                                 AS account_id,
    ac.account_name                       AS account_name,
    COUNT(b.account_id)                   AS total_count,
    COUNT(DISTINCT b.store_id)            AS affected_store_count,
    p_start_date                          AS period_start,
    p_end_date                            AS period_end
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  LEFT JOIN backouts b ON b.account_id = ac.id
  WHERE ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_backout_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_backout_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_backout_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_backout_by_group(date, date, uuid, uuid) IS
  'Group-scoped Back-Out report. Captures HR Emploc candidate back-outs and vacancy pipeline '
  'applicant dropouts within the date window (null dates = all-time). Deduplicates across stages. '
  'Scope-safe: callers see only allowed accounts.';


-- ============================================================
-- §4  report_backout_terminated_by_group — Fix Ambiguity & Align Logic
-- ============================================================

DROP FUNCTION IF EXISTS public.report_backout_terminated_by_group(date, date, uuid, uuid);

CREATE OR REPLACE FUNCTION public.report_backout_terminated_by_group(
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
  backout_count         bigint,
  terminated_count      bigint
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
    RAISE EXCEPTION 'unauthenticated: report_backout_terminated_by_group requires a valid session'
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
    RAISE EXCEPTION 'forbidden: report_backout_terminated_by_group caller is not allowed'
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
  backouts AS (
    -- 1. HR Emploc back-outs
    SELECT
      h.account_id,
      h.store_id
    FROM public.hr_emploc h
    WHERE (h.status = 'Backout' OR h.backout_date IS NOT NULL OR h.backout_at IS NOT NULL)
      AND (
        p_start_date IS NULL
        OR COALESCE(h.backout_date, h.backout_at::date, h.deleted_at::date, h.updated_at::date, h.created_at::date) >= p_start_date
      )
      AND (
        p_end_date IS NULL
        OR COALESCE(h.backout_date, h.backout_at::date, h.deleted_at::date, h.updated_at::date, h.created_at::date) <= p_end_date
      )
      AND h.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR h.account_id = p_account_id)
    UNION ALL
    -- 2. Vacancy pipeline applicant back-outs (deduplicated against hr_emploc.applicant_id)
    SELECT
      v.account_id,
      v.store_id
    FROM public.applicants a
    JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
    WHERE (a.status ILIKE '%backout%' OR a.backout_date IS NOT NULL)
      AND (
        p_start_date IS NULL
        OR COALESCE(a.backout_date, a.updated_at::date, a.created_at::date) >= p_start_date
      )
      AND (
        p_end_date IS NULL
        OR COALESCE(a.backout_date, a.updated_at::date, a.created_at::date) <= p_end_date
      )
      AND v.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR v.account_id = p_account_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.hr_emploc h2
        WHERE h2.applicant_id = a.id
          AND (h2.status = 'Backout' OR h2.backout_date IS NOT NULL OR h2.backout_at IS NOT NULL)
      )
  ),
  terminated AS (
    SELECT
      p.account_id,
      p.store_id
    FROM public.plantilla p
    WHERE p.is_deleted = FALSE
      AND (
        p.separation_status IN ('Terminated', 'End of Contract', 'Endo', 'Others')
        OR p.separation_status ILIKE '%term%'
      )
      AND (
        (
          p.date_of_separation IS NOT NULL
          AND (p_start_date IS NULL OR p.date_of_separation >= p_start_date)
          AND (p_end_date   IS NULL OR p.date_of_separation <= p_end_date)
        )
        OR
        (
          p.deactivated_at IS NOT NULL
          AND (p_start_date IS NULL OR p.deactivated_at::date >= p_start_date)
          AND (p_end_date   IS NULL OR p.deactivated_at::date <= p_end_date)
        )
        OR
        (
          p_start_date IS NULL AND p_end_date IS NULL
        )
      )
      AND p.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
  ),
  combined AS (
    SELECT b.account_id, b.store_id, 'backout'::text AS source FROM backouts b
    UNION ALL
    SELECT t.account_id, t.store_id, 'terminated'::text AS source FROM terminated t
  )
  SELECT
    g.id                                                         AS group_id,
    g.group_name                                                 AS group_name,
    ac.id                                                        AS account_id,
    ac.account_name                                              AS account_name,
    COUNT(c.account_id)                                          AS total_count,
    COUNT(DISTINCT c.store_id)                                   AS affected_store_count,
    p_start_date                                                 AS period_start,
    p_end_date                                                   AS period_end,
    COUNT(c.account_id) FILTER (WHERE c.source = 'backout')     AS backout_count,
    COUNT(c.account_id) FILTER (WHERE c.source = 'terminated')  AS terminated_count
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  LEFT JOIN combined c ON c.account_id = ac.id
  WHERE ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_backout_terminated_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_backout_terminated_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_backout_terminated_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_backout_terminated_by_group(date, date, uuid, uuid) IS
  'Group-scoped Back-Out and Terminated combined report. Combines candidate backouts '
  'with plantilla Terminated/End of Contract/Endo/Others separations in the date window (or all-time). '
  'Fixes ambiguous account_id collision. Scope-safe: callers see only allowed accounts.';
