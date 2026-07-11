-- ============================================================
-- OHM2026_0148 — Split Back-Out / Terminated Into Separate RPCs
-- ============================================================
-- Business decision: Back-Out is NOT Attrition.
--   Attrition  = active workforce loss after onboarding (plantilla).
--   Back-Out   = applicant/candidate leakage before becoming workforce (hr_emploc).
--
-- This migration creates two focused RPCs that replace the combined
-- report_backout_terminated_by_group for new UI report routes:
--
--   report_terminated_by_group   — plantilla separation_status IN ('Endo','Others')
--   report_backout_by_group      — hr_emploc rows where backout_date IS NOT NULL
--
-- report_backout_terminated_by_group is preserved unchanged for backward compat.
-- Attrition RPCs (report_attrition_by_group, fn_get_attrition_details) are
-- NOT changed — audit confirmed Back-Out was never counted in attrition.
-- ============================================================


-- ─── §1  report_terminated_by_group ───────────────────────────────────────────
-- Plantilla employees separated with separation_status IN ('Endo', 'Others').
-- These are active workforce terminations (employment contract ended / cause).
-- Does NOT include: Resigned, AWOL, or any hr_emploc back-out records.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.report_terminated_by_group(date, date, uuid, uuid);

CREATE OR REPLACE FUNCTION public.report_terminated_by_group(
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
    RAISE EXCEPTION 'unauthenticated: report_terminated_by_group requires a valid session'
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
      AND p.separation_status IN ('Endo', 'Others')
      AND p.date_of_separation IS NOT NULL
      AND p.date_of_separation BETWEEN p_start_date AND p_end_date
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
  'separation_status IN (''Endo'', ''Others'') within the date window. '
  'Does NOT include Resigned, AWOL, or HR Emploc back-outs. '
  'Scope-safe: callers see only their allowed accounts. Requires authenticated session.';


-- ─── §2  report_backout_by_group ──────────────────────────────────────────────
-- HR Emploc records where backout_date IS NOT NULL within the date window.
-- These are candidate/applicant back-outs before becoming active workforce.
-- Source: hr_emploc table (NOT plantilla).
-- Does NOT count against attrition — purely recruitment leakage.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.report_backout_by_group(date, date, uuid, uuid);

CREATE OR REPLACE FUNCTION public.report_backout_by_group(
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
    RAISE EXCEPTION 'unauthenticated: report_backout_by_group requires a valid session'
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
    SELECT
      h.account_id,
      h.store_id
    FROM public.hr_emploc h
    WHERE h.deleted_at IS NULL
      AND h.backout_date IS NOT NULL
      AND h.backout_date BETWEEN p_start_date AND p_end_date
      AND h.account_id IN (SELECT sc.account_id FROM scope_check sc)
      AND (p_account_id IS NULL OR h.account_id = p_account_id)
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
  'Group-scoped Back-Out (recruitment leakage) report. Counts HR Emploc records '
  'where backout_date falls within the date window. Source is hr_emploc (NOT plantilla). '
  'These are candidate back-outs before active workforce entry — do NOT count as attrition. '
  'Scope-safe: callers see only their allowed accounts. Requires authenticated session.';


-- ─── Smoke Queries ────────────────────────────────────────────────────────────
-- §S1: Verify terminated report callable (returns rows or empty, no error)
-- SELECT * FROM report_terminated_by_group('2026-01-01', '2026-12-31');
--
-- §S2: Verify backout report callable (returns rows or empty, no error)
-- SELECT * FROM report_backout_by_group('2026-01-01', '2026-12-31');
--
-- §S3: Verify attrition report unchanged (no Back-Out leakage)
-- SELECT * FROM report_attrition_by_group('2026-01-01', '2026-12-31');
--
-- §S4: Confirm combined RPC still works (backward compat)
-- SELECT * FROM report_backout_terminated_by_group('2026-01-01', '2026-12-31');
-- ─────────────────────────────────────────────────────────────────────────────
