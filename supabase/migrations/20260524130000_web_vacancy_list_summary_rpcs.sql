-- Migration: 20260524130000_web_vacancy_list_summary_rpcs.sql
-- Ticket: OHM2026_1078 - Web Vacancy list and summary presentation RPCs
--
-- Purpose:
--   Safe, read-only OHMployee Web presentation contracts for Vacancy dense-table
--   list and summary widgets. These RPCs reuse the Mobile vacancy list view and
--   existing role/scope semantics for display only.
--
-- Security invariants:
--   - Caller identity is derived only from auth.uid().
--   - No user/profile/scope arguments are accepted.
--   - Scope is derived from users_profile + user_scopes.
--   - HR Personnel and unknown/inactive/archived users fail closed.
--   - Sensitive employee/Plantilla fields are not returned.
--   - Row capabilities are UI hints only; RLS/action RPCs remain authority.
--   - Execution is granted only to authenticated.

DROP FUNCTION IF EXISTS public.list_web_vacancies(
  text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text
);

CREATE OR REPLACE FUNCTION public.list_web_vacancies(
  p_status        text    DEFAULT NULL,
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_position      text    DEFAULT NULL,
  p_urgency       text    DEFAULT NULL,
  p_aging_bucket  text    DEFAULT NULL,
  p_search        text    DEFAULT NULL,
  p_vacant_from   date    DEFAULT NULL,
  p_vacant_to     date    DEFAULT NULL,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'vacant_date',
  p_sort_dir      text    DEFAULT 'desc'
)
RETURNS TABLE (
  vacancy_id        uuid,
  vcode             text,
  account_id        uuid,
  account_name      text,
  group_id          uuid,
  group_name        text,
  store_id          uuid,
  store_name        text,
  position_title    text,
  employment_type   text,
  vacancy_status    text,
  pipeline_status   text,
  vacant_date       date,
  aging_days        integer,
  aging_bucket      text,
  target_fill_date  date,
  urgency           text,
  penalty_exposure  numeric,
  hrco_name         text,
  row_capabilities  jsonb,
  total_count       bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'vacant_date'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'vcode',
    'account_name',
    'group_name',
    'store_name',
    'position_title',
    'vacancy_status',
    'pipeline_status',
    'vacant_date',
    'aging_days',
    'target_fill_date',
    'urgency'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by
      USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      vl.id AS vacancy_id,
      vl.vcode,
      vl.account_id,
      vl.account AS account_name,
      vl.group_id,
      vl.group_name,
      vl.store_id,
      vl.store_name,
      vl.position AS position_title,
      vl.employment_type,
      vl.status AS vacancy_status,
      vl.derived_status AS pipeline_status,
      vl.vacant_date,
      vl.aging_days::integer AS aging_days,
      CASE
        WHEN vl.aging_days IS NULL THEN 'unknown'
        WHEN vl.aging_days <= 7 THEN '0_7'
        WHEN vl.aging_days <= 14 THEN '8_14'
        WHEN vl.aging_days <= 30 THEN '15_30'
        ELSE '31_plus'
      END AS aging_bucket,
      vl.target_fill_date,
      vl.urgency_level AS urgency,
      CASE
        WHEN coalesce(v_raw.has_penalty, false)
          THEN coalesce(v_raw.penalty_amount, 0::numeric)
        ELSE 0::numeric
      END AS penalty_exposure,
      vl.hrco_name,
      jsonb_build_object(
        'can_view_detail', true,
        'can_request_closure_hint',
          coalesce(v_role_level, 0) >= 30
          AND coalesce(vl.is_archived, false) = false
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived']),
        'authority', 'rls_action_rpcs'
      ) AS row_capabilities
    FROM public.vw_vacancy_list vl
    JOIN public.vacancies v_raw ON v_raw.id = vl.id
    WHERE
      (
        coalesce(v_role_level, 0) >= 90
        OR (
          coalesce(vl.is_archived, false) = false
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
          AND (
            vl.account = ANY (public.get_my_allowed_accounts())
            OR
            EXISTS (
              SELECT 1
              FROM public.user_scopes us
              WHERE us.user_id = v_profile_id
                AND us.account_id = vl.account_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.user_scopes us
              JOIN public.accounts a ON a.id = vl.account_id
              WHERE us.user_id = v_profile_id
                AND us.account_id IS NULL
                AND us.group_id = a.group_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.users_profile up_fallback
              JOIN public.accounts a ON a.id = vl.account_id
              WHERE up_fallback.id = v_profile_id
                AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_scopes us_any
                  WHERE us_any.user_id = v_profile_id
                    AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
                )
                AND (
                  up_fallback.account_id = vl.account_id
                  OR up_fallback.group_id = a.group_id
                )
            )
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_status IS NULL OR lower(s.vacancy_status) = lower(btrim(p_status)) OR lower(s.pipeline_status) = lower(btrim(p_status)))
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_position IS NULL OR lower(s.position_title) = lower(btrim(p_position)))
      AND (p_urgency IS NULL OR lower(coalesce(s.urgency, '')) = lower(btrim(p_urgency)))
      AND (p_aging_bucket IS NULL OR s.aging_bucket = lower(btrim(p_aging_bucket)))
      AND (p_vacant_from IS NULL OR s.vacant_date >= p_vacant_from)
      AND (p_vacant_to IS NULL OR s.vacant_date <= p_vacant_to)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.group_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.store_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.vacancy_id,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.employment_type,
    c.vacancy_status,
    c.pipeline_status,
    c.vacant_date,
    c.aging_days,
    c.aging_bucket,
    c.target_fill_date,
    c.urgency,
    c.penalty_exposure,
    c.hrco_name,
    c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title'   THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title'   THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vacancy_status'   THEN c.vacancy_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vacancy_status'   THEN c.vacancy_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'pipeline_status'  THEN c.pipeline_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'pipeline_status'  THEN c.pipeline_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vacant_date'      THEN c.vacant_date END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vacant_date'      THEN c.vacant_date END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'target_fill_date' THEN c.target_fill_date END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'target_fill_date' THEN c.target_fill_date END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'urgency'          THEN c.urgency END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'urgency'          THEN c.urgency END DESC NULLS LAST,
    c.vcode ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION public.list_web_vacancies(
  text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text
) IS
  'OHM2026_1078 - Web presentation contract only. Returns scoped Vacancy dense-table rows from vw_vacancy_list with allowlisted filtering/sorting. RLS/action RPCs remain authority.';

DROP FUNCTION IF EXISTS public.get_web_vacancy_summary(
  text, uuid, uuid, text, text, text, date, date
);

CREATE OR REPLACE FUNCTION public.get_web_vacancy_summary(
  p_status        text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL,
  p_position      text DEFAULT NULL,
  p_urgency       text DEFAULT NULL,
  p_search        text DEFAULT NULL,
  p_vacant_from   date DEFAULT NULL,
  p_vacant_to     date DEFAULT NULL
)
RETURNS TABLE (
  total_open        bigint,
  with_applicant    bigint,
  rejected          bigint,
  backout           bigint,
  aging_0_7         bigint,
  aging_8_14        bigint,
  aging_15_30       bigint,
  aging_31_plus     bigint,
  aging_unknown     bigint,
  critical_urgency  bigint,
  high_urgency      bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy summary requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      vl.id AS vacancy_id,
      vl.vcode,
      vl.account_id,
      vl.account AS account_name,
      vl.group_id,
      vl.group_name,
      vl.store_name,
      vl.position AS position_title,
      vl.status AS vacancy_status,
      vl.derived_status AS pipeline_status,
      vl.vacant_date,
      vl.aging_days::integer AS aging_days,
      CASE
        WHEN vl.aging_days IS NULL THEN 'unknown'
        WHEN vl.aging_days <= 7 THEN '0_7'
        WHEN vl.aging_days <= 14 THEN '8_14'
        WHEN vl.aging_days <= 30 THEN '15_30'
        ELSE '31_plus'
      END AS aging_bucket,
      vl.urgency_level AS urgency,
      vl.active_applicant_count
    FROM public.vw_vacancy_list vl
    WHERE
      (
        coalesce(v_role_level, 0) >= 90
        OR (
          coalesce(vl.is_archived, false) = false
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
          AND (
            vl.account = ANY (public.get_my_allowed_accounts())
            OR
            EXISTS (
              SELECT 1
              FROM public.user_scopes us
              WHERE us.user_id = v_profile_id
                AND us.account_id = vl.account_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.user_scopes us
              JOIN public.accounts a ON a.id = vl.account_id
              WHERE us.user_id = v_profile_id
                AND us.account_id IS NULL
                AND us.group_id = a.group_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.users_profile up_fallback
              JOIN public.accounts a ON a.id = vl.account_id
              WHERE up_fallback.id = v_profile_id
                AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_scopes us_any
                  WHERE us_any.user_id = v_profile_id
                    AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
                )
                AND (
                  up_fallback.account_id = vl.account_id
                  OR up_fallback.group_id = a.group_id
                )
            )
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_status IS NULL OR lower(s.vacancy_status) = lower(btrim(p_status)) OR lower(s.pipeline_status) = lower(btrim(p_status)))
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_position IS NULL OR lower(s.position_title) = lower(btrim(p_position)))
      AND (p_urgency IS NULL OR lower(coalesce(s.urgency, '')) = lower(btrim(p_urgency)))
      AND (p_vacant_from IS NULL OR s.vacant_date >= p_vacant_from)
      AND (p_vacant_to IS NULL OR s.vacant_date <= p_vacant_to)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.group_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.store_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  applicant_rollup AS (
    SELECT
      f.vacancy_id,
      count(a.id) FILTER (
        WHERE COALESCE(a.is_archived, false) = false
          AND replace(lower(btrim(coalesce(a.status, ''))), ' ', '_') IN ('rejected', 'rejected_by_ops')
      ) AS rejected_count,
      count(a.id) FILTER (
        WHERE COALESCE(a.is_archived, false) = false
          AND replace(lower(btrim(coalesce(a.status, ''))), ' ', '_') = 'backout'
      ) AS backout_count
    FROM filtered f
    LEFT JOIN public.applicants a ON a.vacancy_vcode = f.vcode
    GROUP BY f.vacancy_id
  )
  SELECT
    count(*) FILTER (WHERE f.pipeline_status = 'Open')::bigint AS total_open,
    count(*) FILTER (WHERE coalesce(f.active_applicant_count, 0) > 0 OR f.pipeline_status = 'Pipeline')::bigint AS with_applicant,
    count(*) FILTER (WHERE coalesce(ar.rejected_count, 0) > 0)::bigint AS rejected,
    count(*) FILTER (WHERE coalesce(ar.backout_count, 0) > 0)::bigint AS backout,
    count(*) FILTER (WHERE f.aging_bucket = '0_7')::bigint AS aging_0_7,
    count(*) FILTER (WHERE f.aging_bucket = '8_14')::bigint AS aging_8_14,
    count(*) FILTER (WHERE f.aging_bucket = '15_30')::bigint AS aging_15_30,
    count(*) FILTER (WHERE f.aging_bucket = '31_plus')::bigint AS aging_31_plus,
    count(*) FILTER (WHERE f.aging_bucket = 'unknown')::bigint AS aging_unknown,
    count(*) FILTER (WHERE lower(coalesce(f.urgency, '')) = 'critical')::bigint AS critical_urgency,
    count(*) FILTER (WHERE lower(coalesce(f.urgency, '')) = 'high')::bigint AS high_urgency
  FROM filtered f
  LEFT JOIN applicant_rollup ar ON ar.vacancy_id = f.vacancy_id;
END;
$$;

COMMENT ON FUNCTION public.get_web_vacancy_summary(
  text, uuid, uuid, text, text, text, date, date
) IS
  'OHM2026_1078 - Web presentation contract only. Returns scoped Vacancy summary counts from vw_vacancy_list and applicant status rollups. RLS/action RPCs remain authority.';

REVOKE ALL ON FUNCTION public.list_web_vacancies(
  text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_web_vacancies(
  text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_web_vacancies(
  text, uuid, uuid, text, text, text, text, date, date, integer, integer, text, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.get_web_vacancy_summary(
  text, uuid, uuid, text, text, text, date, date
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_vacancy_summary(
  text, uuid, uuid, text, text, text, date, date
) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_vacancy_summary(
  text, uuid, uuid, text, text, text, date, date
) TO authenticated;

-- Validation notes (run in staging/dev with representative JWT sessions):
--
-- 1. Unauthenticated blocked:
--    RESET ROLE;
--    SELECT * FROM public.list_web_vacancies();
--    Expected via API: anon cannot execute. Direct SQL with auth.uid() NULL raises 42501.
--
-- 2. Sort allowlist blocks arbitrary fields:
--    SELECT * FROM public.list_web_vacancies(p_sort_by := 'created_at;drop table vacancies');
--    Expected: 22023 invalid sort field.
--
-- 3. Scoped user sees only allowed active vacancies:
--    As a scoped non-admin caller:
--    SELECT account_id, vacancy_status, pipeline_status FROM public.list_web_vacancies();
--    Expected: account_id is within caller scope; Filled/Closed/Archived/is_archived rows are excluded.
--
-- 4. Full-access users can review all non-deleted view rows:
--    As Super Admin or Head Admin:
--    SELECT count(*) FROM public.list_web_vacancies(p_limit := 200);
--    Expected: rows align to public.vw_vacancy_list visibility.
--
-- 5. Summary filters match list filters:
--    Compare public.get_web_vacancy_summary(...) counts against the same filtered
--    public.list_web_vacancies(...) result set in a disposable JWT session.
