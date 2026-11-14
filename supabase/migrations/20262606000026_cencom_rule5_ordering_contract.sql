-- ============================================================
-- OHMployee — CENCOM Rule 5 (Ordering Contract) Enforcement
-- Migration: 20262606000026_cencom_rule5_ordering_contract.sql
-- Prompt ID: ohm#c9x4t2wm
--
-- What this migration does:
--   1. vw_cencom_operational_vacancies — Security-invoker view over
--      vw_slot_derived_vacancy_shadow enforcing canonical DB-level ordering:
--      ORDER BY aging_days DESC NULLS LAST, area_name ASC, store_name ASC, account_name ASC.
--   2. v_cencom_account_allocation_kpi — Re-asserts view with explicit in-DB
--      ORDER BY slot_vacant_hc DESC, mfr ASC, account_name ASC.
--   3. v_cencom_group_allocation_kpi — Re-asserts view with explicit in-DB
--      ORDER BY group_code ASC.
--   4. fn_get_attrition_details — Enforces in-DB ORDER BY on separated employee
--      records (date_of_separation DESC NULLS LAST, employee_name ASC).
-- ============================================================

-- ── §1. vw_cencom_operational_vacancies ─────────────────────────────────────

CREATE OR REPLACE VIEW public.vw_cencom_operational_vacancies
  WITH (security_invoker = true)
AS
SELECT v.*
FROM public.vw_slot_derived_vacancy_shadow v
WHERE COALESCE(v.vacancy_tab, '') <> 'Closure'
  AND COALESCE(v.has_pending_closure, false) = false
ORDER BY
  v.aging_days DESC NULLS LAST,
  COALESCE(v.area_name, v.area_city, '') ASC,
  COALESCE(v.store_name, v.store_branch, '') ASC,
  COALESCE(v.account_name, '') ASC;

ALTER VIEW public.vw_cencom_operational_vacancies OWNER TO postgres;
COMMENT ON VIEW public.vw_cencom_operational_vacancies IS
  'CENCOM operational vacancies with canonical Rule 5 in-DB ordering. '
  'ORDER BY aging_days DESC NULLS LAST, area_name ASC, store_name ASC, account_name ASC.';
GRANT SELECT ON public.vw_cencom_operational_vacancies TO authenticated, service_role;


-- ── §2. v_cencom_account_allocation_kpi ─────────────────────────────────────

CREATE OR REPLACE VIEW public.v_cencom_account_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT ak.*
FROM   public.v_account_allocation_kpi ak
JOIN   public.groups g ON g.id = ak.group_id
WHERE  g.cencom_scope = true
ORDER BY ak.slot_vacant_hc DESC, ak.mfr ASC, ak.account_name ASC;

ALTER VIEW public.v_cencom_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_account_allocation_kpi IS
  'Per-account KPI restricted to CENCOM groups (cencom_scope=true). '
  'Enforces Rule 5 in-DB ordering: ORDER BY slot_vacant_hc DESC, mfr ASC, account_name ASC.';
GRANT SELECT ON public.v_cencom_account_allocation_kpi TO authenticated, service_role;


-- ── §3. v_cencom_group_allocation_kpi ───────────────────────────────────────

CREATE OR REPLACE VIEW public.v_cencom_group_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  group_id, group_name, group_code,
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  round(sum(pipeline_count), 0)::bigint  AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,
  round(sum(required_hc), 4)             AS required_hc,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                         THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0     THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9     THEN 'at_risk'::text
       ELSE                                                   'critical'::text
  END                                                                      AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc
FROM public.v_cencom_account_allocation_kpi
GROUP BY group_id, group_name, group_code
ORDER BY group_code ASC;

ALTER VIEW public.v_cencom_group_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_group_allocation_kpi IS
  'Per-group CENCOM allocation breakdown. '
  'Enforces Rule 5 in-DB ordering: ORDER BY group_code ASC.';
GRANT SELECT ON public.v_cencom_group_allocation_kpi TO authenticated, service_role;


-- ── §4. fn_get_attrition_details ─────────────────────────────────────────────

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
    )
  ORDER BY COALESCE(p.date_of_separation, p.deactivated_at::date) DESC NULLS LAST, p.employee_name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_attrition_details(uuid, date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_get_attrition_details(uuid, date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_get_attrition_details(uuid, date, date) TO authenticated;
COMMENT ON FUNCTION public.fn_get_attrition_details(uuid, date, date) IS
  'Returns separated employee records for selected account/group within selected date range. '
  'Enforces Rule 5 in-DB ordering: ORDER BY date_of_separation DESC NULLS LAST, employee_name ASC.';
