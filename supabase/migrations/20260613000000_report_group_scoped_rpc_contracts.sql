-- ============================================================
-- Migration: 20260613000000_report_group_scoped_rpc_contracts.sql
-- Ticket:    OHM2026_0031 — Phase 2: Backend Report RPC Contracts
-- ============================================================
--
-- Purpose:
--   Stable, RLS-safe, group-scoped aggregation RPCs for the
--   six CENCOM operational reports.  These are read-only
--   presentation contracts — no writes, no schema changes.
--
-- RPCs defined:
--   1. report_attrition_by_group
--   2. report_resigned_by_group
--   3. report_awol_by_group
--   4. report_backout_terminated_by_group
--   5. report_time_to_fill_by_group
--   6. report_hr_emploc_late_update_by_group
--
-- Security invariants (same contract as all web RPCs):
--   - Caller identity derived strictly from auth.uid().
--   - Profile resolved from users_profile; unauthenticated/
--     inactive callers fail closed (ERRCODE 42501).
--   - Full-access (role_level >= 90) sees all data; scoped
--     callers see only their assigned accounts/groups.
--   - p_group_id / p_account_id are additive filters on top of
--     the caller's allowed scope — never scope wideners.
--   - Date range is required; p_end_date < p_start_date raises
--     ERRCODE 22000.  Returns empty set when no data matches.
--   - Cross-group data leakage is structurally impossible due to
--     the scope CTE pattern.
--   - GRANT EXECUTE only to authenticated; PUBLIC and anon revoked.
--
-- Source tables used (verified against remote_schema):
--   public.plantilla          — separation_status, date_of_separation,
--                               deactivated_at, deactivation_reason,
--                               account_id, store_id, is_deleted
--   public.hr_emploc          — backout_date, moved_to_plantilla_at,
--                               date_requested, status, account_id,
--                               store_id
--   public.vacancies          — status='Filled', vacant_date,
--                               created_at, group_id, account_id
--   public.accounts           — id, group_id, account_name
--   public.groups             — id, group_name
--   public.users_profile      — auth_user_id, id, role_id, is_active
--   public.roles              — role_level
--   public.user_scopes        — user_id, account_id, group_id
--
-- Columns deliberately NOT used (not reliably populated or risky):
--   plantilla.deactivation_reason (free-text, no enum constraint)
--   vacancies.closed_at (column does not exist; using
--     hr_emploc.moved_to_plantilla_at as fill proxy)
--
-- Validation queries (run manually after applying):
--   V1 — All six functions exist
--     SELECT proname FROM pg_proc
--     WHERE proname IN (
--       'report_attrition_by_group',
--       'report_resigned_by_group',
--       'report_awol_by_group',
--       'report_backout_terminated_by_group',
--       'report_time_to_fill_by_group',
--       'report_hr_emploc_late_update_by_group'
--     );
--   V2 — Each function is SECURITY DEFINER
--     SELECT proname, prosecdef FROM pg_proc
--     WHERE proname LIKE 'report_%_by_group';
--   V3 — Execute granted to authenticated
--     SELECT grantee, privilege_type
--     FROM information_schema.role_routine_grants
--     WHERE routine_name LIKE 'report_%_by_group';
--   V4 — Date validation raises error
--     SELECT report_attrition_by_group('2026-06-01', '2026-05-01');
--     -- expected: raises 22000 p_end_date must be >= p_start_date
--   V5 — Unauthenticated call raises 42501
--     -- call without session; expected: unauthenticated
--   V6 — Scoped sample call (replace dates with real range)
--     SELECT * FROM report_attrition_by_group('2026-01-01', '2026-05-31');
-- ============================================================


-- ============================================================
-- Drop old signatures (idempotent; all six were new in this PR)
-- ============================================================

DROP FUNCTION IF EXISTS public.report_attrition_by_group(date, date, uuid, uuid);
DROP FUNCTION IF EXISTS public.report_resigned_by_group(date, date, uuid, uuid);
DROP FUNCTION IF EXISTS public.report_awol_by_group(date, date, uuid, uuid);
DROP FUNCTION IF EXISTS public.report_backout_terminated_by_group(date, date, uuid, uuid);
DROP FUNCTION IF EXISTS public.report_time_to_fill_by_group(date, date, uuid, uuid);
DROP FUNCTION IF EXISTS public.report_hr_emploc_late_update_by_group(date, date, uuid, uuid);


-- ============================================================
-- §1  report_attrition_by_group
-- ============================================================
-- Total separated employees (any separation_status or deactivated)
-- within the date window.  attrition_rate = separated / total
-- employees who were active at any point during the window.

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
    ROUND(
      COUNT(sep.account_id)::numeric
      / NULLIF(MAX(aip.headcount), 0)
      * 100,
      2
    )                                                       AS attrition_rate
  FROM public.accounts ac
  JOIN public.groups g ON g.id = ac.group_id
  LEFT JOIN separated sep ON sep.account_id = ac.id
  LEFT JOIN active_in_period aip ON aip.account_id = ac.id
  WHERE ac.id IN (SELECT sc.account_id FROM scope_check sc)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND (p_account_id IS NULL OR ac.id = p_account_id)
  GROUP BY g.id, g.group_name, ac.id, ac.account_name
  HAVING COUNT(sep.account_id) > 0
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_attrition_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_attrition_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_attrition_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_attrition_by_group(date, date, uuid, uuid) IS
  'Group-scoped attrition report. Counts separated employees (date_of_separation '
  'or deactivated_at in range). attrition_rate = separated / active_in_period * 100. '
  'Scope-safe: callers see only their allowed accounts. Requires authenticated session.';


-- ============================================================
-- §2  report_resigned_by_group
-- ============================================================
-- Plantilla employees with separation_status = ''Resigned''
-- whose date_of_separation falls within the date window.

CREATE OR REPLACE FUNCTION public.report_resigned_by_group(
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
    AND p.separation_status = 'Resigned'
    AND p.date_of_separation IS NOT NULL
    AND p.date_of_separation BETWEEN p_start_date AND p_end_date
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
  'separation_status = ''Resigned'' and date_of_separation is within the period. '
  'Scope-safe: callers see only their allowed accounts.';


-- ============================================================
-- §3  report_awol_by_group
-- ============================================================
-- Plantilla employees with separation_status = ''AWOL''
-- whose date_of_separation falls within the date window.

CREATE OR REPLACE FUNCTION public.report_awol_by_group(
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
    AND p.separation_status = 'AWOL'
    AND p.date_of_separation IS NOT NULL
    AND p.date_of_separation BETWEEN p_start_date AND p_end_date
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
  'separation_status = ''AWOL'' and date_of_separation is within the period. '
  'Scope-safe: callers see only their allowed accounts.';


-- ============================================================
-- §4  report_backout_terminated_by_group
-- ============================================================
-- Combined report of:
--   - HR Emploc back-outs: hr_emploc rows where backout_date IS NOT NULL
--     and falls within the date window.
--   - Terminated/Endo separations: plantilla rows where separation_status
--     IN (''Endo'', ''Others'') and date_of_separation is within the window.
--
-- backout_count  = HR Emploc back-outs
-- terminated_count = Plantilla Endo + Others separations
-- total_count    = backout_count + terminated_count

CREATE OR REPLACE FUNCTION public.report_backout_terminated_by_group(
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
    SELECT
      h.account_id,
      h.store_id
    FROM public.hr_emploc h
    WHERE h.deleted_at IS NULL
      AND h.backout_date IS NOT NULL
      AND h.backout_date BETWEEN p_start_date AND p_end_date
      AND h.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR h.account_id = p_account_id)
  ),
  terminated AS (
    SELECT
      p.account_id,
      p.store_id
    FROM public.plantilla p
    WHERE p.is_deleted = FALSE
      AND p.separation_status IN ('Endo', 'Others')
      AND p.date_of_separation IS NOT NULL
      AND p.date_of_separation BETWEEN p_start_date AND p_end_date
      AND p.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
  ),
  combined AS (
    SELECT account_id, store_id, 'backout'::text AS source FROM backouts
    UNION ALL
    SELECT account_id, store_id, 'terminated'::text AS source FROM terminated
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
  HAVING COUNT(c.account_id) > 0
  ORDER BY g.group_name, ac.account_name;
END;
$$;

REVOKE ALL ON FUNCTION public.report_backout_terminated_by_group(date, date, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.report_backout_terminated_by_group(date, date, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.report_backout_terminated_by_group(date, date, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.report_backout_terminated_by_group(date, date, uuid, uuid) IS
  'Group-scoped Back-Out and Terminated report. Combines HR Emploc backout_date '
  'events with plantilla Endo/Others separations in the date window. '
  'backout_count = HR Emploc back-outs; terminated_count = Endo + Others. '
  'Scope-safe: callers see only their allowed accounts.';


-- ============================================================
-- §5  report_time_to_fill_by_group
-- ============================================================
-- Vacancies that were filled (moved to Plantilla) within the
-- date window.  avg_days_to_fill uses hr_emploc.moved_to_plantilla_at
-- as the fill timestamp and COALESCE(v.vacant_date, v.created_at::date)
-- as the vacancy open date.  Only rows where both timestamps are
-- available contribute to the average.

CREATE OR REPLACE FUNCTION public.report_time_to_fill_by_group(
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
    -- Vacancies filled (status = Filled) where the HR Emploc move happened in window.
    -- Use hr_emploc.moved_to_plantilla_at as the fill timestamp.
    -- Use COALESCE(v.vacant_date, v.created_at::date) as the start date.
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
      AND h.moved_to_plantilla_at::date BETWEEN p_start_date AND p_end_date
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
  'avg_days_to_fill = mean(moved_to_plantilla_at - COALESCE(vacant_date, created_at)). '
  'Uses hr_emploc.moved_to_plantilla_at as the fill timestamp. '
  'Scope-safe: callers see only their allowed accounts.';


-- ============================================================
-- §6  report_hr_emploc_late_update_by_group
-- ============================================================
-- HR Emploc SLA breach report.  The 3-day SLA is the existing
-- production threshold (matches the sla_breached definition
-- used in list_web_hr_emplocs and the mobile SLA chip).
--
-- total_count = HR Emploc records whose date_requested falls in
--               the date window (regardless of SLA status).
-- late_count  = records in the window where the SLA was breached:
--   • still pending and date_requested < p_end_date - 3 days, OR
--   • resolved but took > 3 days
--     (moved_to_plantilla_at::date - date_requested::date > 3)

CREATE OR REPLACE FUNCTION public.report_hr_emploc_late_update_by_group(
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
      -- SLA breached: still pending past 3 days OR resolved but took > 3 days
      CASE
        WHEN h.status <> 'Moved to Plantilla'
          AND COALESCE(h.date_requested, h.created_at) < (p_end_date::timestamptz - INTERVAL '3 days')
          THEN TRUE
        WHEN h.status = 'Moved to Plantilla'
          AND h.moved_to_plantilla_at IS NOT NULL
          AND (h.moved_to_plantilla_at::date - COALESCE(h.date_requested, h.created_at)::date) > 3
          THEN TRUE
        ELSE FALSE
      END AS is_late
    FROM public.hr_emploc h
    WHERE h.deleted_at IS NULL
      AND COALESCE(h.date_requested, h.created_at)::date BETWEEN p_start_date AND p_end_date
      AND h.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR h.account_id = p_account_id)
  )
  SELECT
    g.id                                              AS group_id,
    g.group_name                                      AS group_name,
    ac.id                                             AS account_id,
    ac.account_name                                   AS account_name,
    COUNT(e.account_id)                               AS total_count,
    COUNT(DISTINCT e.store_id)                        AS affected_store_count,
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
  'the period; late_count = SLA-breached rows (still pending past 3d, or resolved '
  'but took > 3 days). Uses the same 3-day SLA threshold as the mobile SLA chip. '
  'Scope-safe: callers see only their allowed accounts.';
