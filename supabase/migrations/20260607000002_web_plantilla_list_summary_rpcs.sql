-- Migration: 20260607000002_web_plantilla_list_summary_rpcs.sql
-- Ticket: OHM2026_1100 - Web Plantilla list, store staffing, and summary RPCs
--
-- Purpose:
--   Safe, read-only presentation contracts for the OHMployee Web Plantilla module:
--     * list_web_plantilla_employees(...)     — scoped employee roster (dense table)
--     * list_web_plantilla_store_staffing(...) — per-store staffing / MFR operational view
--     * get_web_plantilla_summary(...)         — scoped KPI counters
--
-- Security invariants:
--   - Caller identity is derived strictly from auth.uid().
--   - Scoping is derived dynamically from users_profile + user_scopes, mirroring the
--     existing HR Emploc / Vacancy web RPCs and the Mobile scope helpers.
--   - Unauthenticated, profile-less, inactive, archived, and out-of-scope callers
--     fail closed (ERRCODE 42501). No cross-scope leakage.
--   - Reads go through v_plantilla_safe, which already excludes deleted, archived,
--     and expired visibility-window rows and masks ATM numbers.
--   - PII is excluded from the contract: no ATM numbers, no SSS/PhilHealth/Pag-IBIG,
--     no raw payroll rate, no exact birthdate, no sensitive notes, no contact details.
--     Only safe/derived presentation fields (age, tenure, masked indicators) are exposed.
--   - row_capabilities are UI hints only; action RPCs, triggers, and RLS remain authority.
--   - Viewer / HR Personnel and other non-ops roles receive view-only capability hints.
--   - Execution is granted only to authenticated. PUBLIC and anon are revoked.
--
-- Assumptions (documented):
--   - Staffing "required" headcount = active onboard count + open vacancy headcount
--     for the store. Open HC is summed from vacancies.required_headcount where the
--     vacancy is Open and not archived/deleted.
--   - Fill rate = onboard / required. Staffing risk buckets are a presentation-layer
--     derivation: required = 0 -> 'none'; fill < 0.5 -> 'critical'; fill < 0.8 ->
--     'warning'; otherwise 'healthy'. These thresholds are UI signals only and do not
--     replace any backend MFR calculation.
--   - HC-created placeholder slots (source_headcount_request_id IS NOT NULL) are
--     excluded from the employee roster and from plantilla staffing counts; their
--     open headcount is represented through the vacancies table instead.
--   - Roving = deployment_type = 'Roving' OR roving_assignment_id IS NOT NULL.

-- ============================================================================
-- 1. list_web_plantilla_employees(...)
-- ============================================================================

DROP FUNCTION IF EXISTS public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
);

CREATE OR REPLACE FUNCTION public.list_web_plantilla_employees(
  p_search            text    DEFAULT NULL,
  p_account_id        uuid    DEFAULT NULL,
  p_group_id          uuid    DEFAULT NULL,
  p_store_id          uuid    DEFAULT NULL,
  p_employment_status text    DEFAULT NULL,
  p_deployment        text    DEFAULT NULL,
  p_active_state      text    DEFAULT NULL,
  p_limit             integer DEFAULT 50,
  p_offset            integer DEFAULT 0,
  p_sort_by           text    DEFAULT 'employee_name',
  p_sort_dir          text    DEFAULT 'asc'
)
RETURNS TABLE (
  plantilla_id            uuid,
  employee_name           text,
  employee_no             text,
  account_id              uuid,
  account_name            text,
  group_id                uuid,
  group_name              text,
  store_id                uuid,
  store_name              text,
  province_id             uuid,
  position_title          text,
  status                  text,
  deployment_type         text,
  is_roving               boolean,
  roving_store_count      integer,
  vcode                   text,
  hr_emploc_id            uuid,
  date_hired              date,
  tenure_months           integer,
  age                     integer,
  has_penalty             boolean,
  separation_status       text,
  date_of_separation      date,
  is_active               boolean,
  is_inactive             boolean,
  is_pending_deactivation boolean,
  is_deactivated          boolean,
  onboarding_linked       boolean,
  has_masked_fields       boolean,
  masked_fields           jsonb,
  deactivation_overlay    jsonb,
  row_capabilities        jsonb,
  total_count             bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_name  text;
  v_role_level integer;
  v_sort_by    text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'employee_name'));
  v_sort_dir   text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'asc'));
  v_limit      integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset     integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla list requires a valid session'
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
    RAISE EXCEPTION 'forbidden: web plantilla list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'employee_name', 'employee_no', 'account_name', 'group_name', 'store_name',
    'position_title', 'status', 'date_hired', 'tenure_months', 'created_at'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      p.id AS plantilla_id,
      p.employee_name,
      p.employee_no,
      p.account_id,
      a.account_name,
      a.group_id,
      g.group_name,
      p.store_id,
      p.store_name,
      p.province_id,
      p."position" AS position_title,
      p.status,
      p.deployment_type,
      (COALESCE(p.deployment_type, '') = 'Roving' OR p.roving_assignment_id IS NOT NULL) AS is_roving,
      COALESCE(p.roving_store_count, 0) AS roving_store_count,
      p.vcode,
      p.hr_emploc_id,
      p.date_hired,
      p.tenure_months,
      p.age,
      COALESCE(p.has_penalty, FALSE) AS has_penalty,
      p.separation_status,
      p.date_of_separation,
      p.created_at,
      (p.status = 'Active') AS is_active,
      (p.status <> 'Active') AS is_inactive,
      (p.status IN ('Pending Deactivation', 'For Deactivation')) AS is_pending_deactivation,
      (p.status = 'Deactivated') AS is_deactivated,
      (p.hr_emploc_id IS NOT NULL) AS onboarding_linked,
      (p.sss_no IS NOT NULL OR p.philhealth_no IS NOT NULL
        OR p.pagibig_no IS NOT NULL OR p.atm_no_masked IS NOT NULL) AS has_masked_fields,
      (
        '[]'::jsonb
        || CASE WHEN p.atm_no_masked IS NOT NULL THEN '["atm_no"]'::jsonb ELSE '[]'::jsonb END
        || CASE WHEN p.sss_no IS NOT NULL THEN '["sss_no"]'::jsonb ELSE '[]'::jsonb END
        || CASE WHEN p.philhealth_no IS NOT NULL THEN '["philhealth_no"]'::jsonb ELSE '[]'::jsonb END
        || CASE WHEN p.pagibig_no IS NOT NULL THEN '["pagibig_no"]'::jsonb ELSE '[]'::jsonb END
      ) AS masked_fields,
      jsonb_build_object(
        'is_pending', (p.status IN ('Pending Deactivation', 'For Deactivation')),
        'is_rejected', (p.status = 'Rejected Deactivation'),
        'is_deactivated', (p.status = 'Deactivated'),
        'deactivated_at', p.deactivated_at,
        'deactivation_reason', p.deactivation_reason,
        'display_label', CASE
          WHEN p.status IN ('Pending Deactivation', 'For Deactivation', 'Pending') THEN 'Pending Deactivation'
          WHEN p.status IN ('Rejected Deactivation', 'Rejected') THEN 'Rejected Deactivation'
          WHEN p.status IN ('Deactivated', 'Approved') THEN 'Deactivated'
          ELSE NULL
        END
      ) AS deactivation_overlay,
      jsonb_build_object(
        'can_view_detail', TRUE,
        'can_request_deactivation', (
          p.status NOT IN ('Pending Deactivation', 'For Deactivation', 'Deactivated')
          AND (public.i_have_full_access() OR public.i_am_ops())
        ),
        'can_transfer', (
          p.status = 'Active'
          AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        ),
        'can_request_deletion', (
          p.status = 'Active'
          AND (public.i_have_full_access() OR public.i_am_ops())
        ),
        'can_update_employment_status', (
          p.status = 'Active'
          AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
        ),
        'can_archive', (COALESCE(v_role_level, 0) >= 100)
      ) AS row_capabilities
    FROM public.v_plantilla_safe p
    LEFT JOIN public.accounts a ON a.id = p.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
    WHERE
      p.source_headcount_request_id IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = p.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = p.account_id
          WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_store_id IS NULL OR s.store_id = p_store_id)
      AND (p_employment_status IS NULL OR s.status = p_employment_status)
      AND (
        p_deployment IS NULL
        OR (lower(p_deployment) = 'roving' AND s.is_roving)
        OR (lower(p_deployment) = 'stationary' AND NOT s.is_roving)
      )
      AND (
        p_active_state IS NULL
        OR (lower(p_active_state) = 'active' AND s.is_active)
        OR (lower(p_active_state) = 'inactive' AND s.is_inactive)
      )
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.employee_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.plantilla_id, c.employee_name, c.employee_no, c.account_id, c.account_name,
    c.group_id, c.group_name, c.store_id, c.store_name, c.province_id,
    c.position_title, c.status, c.deployment_type, c.is_roving, c.roving_store_count,
    c.vcode, c.hr_emploc_id, c.date_hired, c.tenure_months, c.age, c.has_penalty,
    c.separation_status, c.date_of_separation, c.is_active, c.is_inactive,
    c.is_pending_deactivation, c.is_deactivated, c.onboarding_linked,
    c.has_masked_fields, c.masked_fields, c.deactivation_overlay, c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_name'  THEN c.employee_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_name'  THEN c.employee_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'employee_no'    THEN c.employee_no END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'employee_no'    THEN c.employee_no END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'   THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'   THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'     THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'     THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'     THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'     THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position_title' THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position_title' THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'status'         THEN c.status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'status'         THEN c.status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'date_hired'     THEN c.date_hired END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'date_hired'     THEN c.date_hired END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'tenure_months'  THEN c.tenure_months END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'tenure_months'  THEN c.tenure_months END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'created_at'     THEN c.created_at END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'created_at'     THEN c.created_at END DESC NULLS LAST,
    c.employee_name ASC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) IS
  'OHM2026_1100 - Web presentation contract only. Returns scoped, PII-safe Plantilla employee roster rows from v_plantilla_safe with allowlisted filtering/sorting. RLS/action RPCs remain authority.';


-- ============================================================================
-- 2. list_web_plantilla_store_staffing(...)
-- ============================================================================

DROP FUNCTION IF EXISTS public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
);

CREATE OR REPLACE FUNCTION public.list_web_plantilla_store_staffing(
  p_search        text    DEFAULT NULL,
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_risk_filter   text    DEFAULT NULL,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'store_name',
  p_sort_dir      text    DEFAULT 'asc'
)
RETURNS TABLE (
  store_id                  uuid,
  store_name                text,
  account_id                uuid,
  account_name              text,
  group_id                  uuid,
  group_name                text,
  province_id               uuid,
  onboard_count             bigint,
  inactive_count            bigint,
  roving_count              bigint,
  stationary_count          bigint,
  pending_deactivation_count bigint,
  open_vacancy_count        bigint,
  open_headcount            bigint,
  required_headcount        bigint,
  fill_rate                 numeric,
  staffing_risk             text,
  row_capabilities          jsonb,
  total_count               bigint
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
  v_sort_by    text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'store_name'));
  v_sort_dir   text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'asc'));
  v_limit      integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset     integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla staffing requires a valid session'
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

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web plantilla staffing caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'store_name', 'account_name', 'group_name', 'onboard_count',
    'open_headcount', 'required_headcount', 'fill_rate'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH plantilla_scoped AS (
    SELECT
      p.store_id, p.store_name, p.account_id, p.account, p.province_id,
      p.status, p.deployment_type, p.roving_assignment_id
    FROM public.v_plantilla_safe p
    WHERE
      p.source_headcount_request_id IS NULL
      AND p.store_id IS NOT NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = p.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = p.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  vacancies_scoped AS (
    SELECT v.store_id, v.store_name, v.account_id, v.account, v.province_id, v.vcode, v.required_headcount
    FROM public.vacancies v
    WHERE
      v.deleted_at IS NULL
      AND COALESCE(v.is_archived, FALSE) = FALSE
      AND v.status = 'Open'
      AND v.store_id IS NOT NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR v.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = v.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = v.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = v.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = v.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  store_keys AS (
    SELECT
      store_id,
      max(store_name) AS store_name,
      max(account_id) AS account_id,
      max(account)    AS account_name,
      max(province_id) AS province_id
    FROM (
      SELECT store_id, store_name, account_id, account, province_id FROM plantilla_scoped
      UNION ALL
      SELECT store_id, store_name, account_id, account, province_id FROM vacancies_scoped
    ) u
    GROUP BY store_id
  ),
  p_agg AS (
    SELECT
      store_id,
      count(*) FILTER (WHERE status = 'Active') AS onboard_count,
      count(*) FILTER (WHERE status <> 'Active') AS inactive_count,
      count(*) FILTER (WHERE status = 'Active' AND (COALESCE(deployment_type, '') = 'Roving' OR roving_assignment_id IS NOT NULL)) AS roving_count,
      count(*) FILTER (WHERE status = 'Active' AND NOT (COALESCE(deployment_type, '') = 'Roving' OR roving_assignment_id IS NOT NULL)) AS stationary_count,
      count(*) FILTER (WHERE status IN ('Pending Deactivation', 'For Deactivation')) AS pending_deactivation_count
    FROM plantilla_scoped
    GROUP BY store_id
  ),
  v_agg AS (
    SELECT store_id, count(DISTINCT vcode) AS open_vacancy_count, COALESCE(sum(required_headcount), 0) AS open_headcount
    FROM vacancies_scoped
    GROUP BY store_id
  ),
  combined AS (
    SELECT
      sk.store_id,
      sk.store_name,
      sk.account_id,
      sk.account_name,
      a.group_id,
      g.group_name,
      sk.province_id,
      COALESCE(pa.onboard_count, 0)::bigint AS onboard_count,
      COALESCE(pa.inactive_count, 0)::bigint AS inactive_count,
      COALESCE(pa.roving_count, 0)::bigint AS roving_count,
      COALESCE(pa.stationary_count, 0)::bigint AS stationary_count,
      COALESCE(pa.pending_deactivation_count, 0)::bigint AS pending_deactivation_count,
      COALESCE(va.open_vacancy_count, 0)::bigint AS open_vacancy_count,
      COALESCE(va.open_headcount, 0)::bigint AS open_headcount,
      (COALESCE(pa.onboard_count, 0) + COALESCE(va.open_headcount, 0))::bigint AS required_headcount
    FROM store_keys sk
    LEFT JOIN p_agg pa ON pa.store_id = sk.store_id
    LEFT JOIN v_agg va ON va.store_id = sk.store_id
    LEFT JOIN public.accounts a ON a.id = sk.account_id
    LEFT JOIN public.groups g ON g.id = a.group_id
  ),
  risk_scored AS (
    SELECT
      c.*,
      CASE WHEN c.required_headcount = 0 THEN NULL
           ELSE round(c.onboard_count::numeric / c.required_headcount::numeric, 4)
      END AS fill_rate,
      CASE
        WHEN c.required_headcount = 0 THEN 'none'
        WHEN c.onboard_count::numeric / c.required_headcount::numeric < 0.5 THEN 'critical'
        WHEN c.onboard_count::numeric / c.required_headcount::numeric < 0.8 THEN 'warning'
        ELSE 'healthy'
      END AS staffing_risk
    FROM combined c
  ),
  filtered AS (
    SELECT r.*
    FROM risk_scored r
    WHERE
      (p_account_id IS NULL OR r.account_id = p_account_id)
      AND (p_group_id IS NULL OR r.group_id = p_group_id)
      AND (
        p_risk_filter IS NULL
        OR r.staffing_risk = lower(p_risk_filter)
        OR (lower(p_risk_filter) = 'at_risk' AND r.staffing_risk IN ('critical', 'warning'))
      )
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR r.store_name ILIKE '%' || btrim(p_search) || '%'
        OR r.account_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.store_id, c.store_name, c.account_id, c.account_name, c.group_id, c.group_name,
    c.province_id, c.onboard_count, c.inactive_count, c.roving_count, c.stationary_count,
    c.pending_deactivation_count, c.open_vacancy_count, c.open_headcount, c.required_headcount,
    c.fill_rate, c.staffing_risk,
    jsonb_build_object(
      'can_view_store_roster', TRUE,
      'is_at_risk', (c.staffing_risk IN ('critical', 'warning')),
      'has_open_headcount', (c.open_headcount > 0)
    ) AS row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'         THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'         THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'       THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'       THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'         THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'         THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'onboard_count'      THEN c.onboard_count END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'onboard_count'      THEN c.onboard_count END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'open_headcount'     THEN c.open_headcount END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'open_headcount'     THEN c.open_headcount END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'required_headcount' THEN c.required_headcount END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'required_headcount' THEN c.required_headcount END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'fill_rate'          THEN c.fill_rate END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'fill_rate'          THEN c.fill_rate END DESC NULLS LAST,
    c.store_name ASC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
) IS
  'OHM2026_1100 - Web presentation contract only. Returns scoped per-store staffing/MFR operational rows (onboard vs open headcount, fill rate, staffing risk). Thresholds are UI signals; RLS/action RPCs remain authority.';


-- ============================================================================
-- 3. get_web_plantilla_summary(...)
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_web_plantilla_summary(text, uuid, uuid);

CREATE OR REPLACE FUNCTION public.get_web_plantilla_summary(
  p_search     text DEFAULT NULL,
  p_account_id uuid DEFAULT NULL,
  p_group_id   uuid DEFAULT NULL
)
RETURNS TABLE (
  active_employees          bigint,
  inactive_employees        bigint,
  roving_count              bigint,
  stationary_count          bigint,
  onboarding_pipeline_count bigint,
  pending_deactivation_count bigint,
  staffing_risk_count       bigint,
  open_headcount_count      bigint
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
    RAISE EXCEPTION 'unauthenticated: web plantilla summary requires a valid session'
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

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web plantilla summary caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH plantilla_scoped AS (
    SELECT
      p.account_id, a.group_id, p.status, p.store_id, p.deployment_type, p.roving_assignment_id,
      p.employee_name, p.employee_no, p.store_name
    FROM public.v_plantilla_safe p
    LEFT JOIN public.accounts a ON a.id = p.account_id
    WHERE
      p.source_headcount_request_id IS NULL
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = p.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = p.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  plantilla_filtered AS (
    SELECT s.*
    FROM plantilla_scoped s
    WHERE (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.employee_name ILIKE '%' || btrim(p_search) || '%'
        OR s.employee_no ILIKE '%' || btrim(p_search) || '%'
        OR s.store_name ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  vacancies_scoped AS (
    SELECT v.account_id, a.group_id, v.required_headcount, v.store_id
    FROM public.vacancies v
    LEFT JOIN public.accounts a ON a.id = v.account_id
    WHERE
      v.deleted_at IS NULL
      AND COALESCE(v.is_archived, FALSE) = FALSE
      AND v.status = 'Open'
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR v.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = v.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = v.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = v.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = v.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  vacancies_filtered AS (
    SELECT v.*
    FROM vacancies_scoped v
    WHERE (p_account_id IS NULL OR v.account_id = p_account_id)
      AND (p_group_id IS NULL OR v.group_id = p_group_id)
  ),
  hr_pipeline AS (
    SELECT count(*)::bigint AS pipeline_count
    FROM public.hr_emploc h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    WHERE
      h.deleted_at IS NULL
      AND h.hr_status IN ('Pending', 'Complete')
      AND (h.employee_no IS NULL OR h.employee_no = '')
      AND (p_account_id IS NULL OR h.account_id = p_account_id)
      AND (p_group_id IS NULL OR a.group_id = p_group_id)
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR h.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (SELECT 1 FROM public.user_scopes us WHERE us.user_id = v_profile_id AND us.account_id = h.account_id)
        OR EXISTS (SELECT 1 FROM public.user_scopes us JOIN public.accounts ac ON ac.id = h.account_id WHERE us.user_id = v_profile_id AND us.account_id IS NULL AND us.group_id = ac.group_id)
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb JOIN public.accounts ac ON ac.id = h.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id = v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))
            AND (up_fb.account_id = h.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ),
  store_staffing AS (
    SELECT
      sk.store_id,
      COALESCE((SELECT count(*) FROM plantilla_filtered pf WHERE pf.store_id = sk.store_id AND pf.status = 'Active'), 0) AS onboard_count,
      COALESCE((SELECT sum(vf.required_headcount) FROM vacancies_filtered vf WHERE vf.store_id = sk.store_id), 0) AS open_headcount
    FROM (
      SELECT store_id FROM plantilla_filtered WHERE store_id IS NOT NULL
      UNION
      SELECT store_id FROM vacancies_filtered WHERE store_id IS NOT NULL
    ) sk
  )
  SELECT
    count(*) FILTER (WHERE pf.status = 'Active')::bigint AS active_employees,
    count(*) FILTER (WHERE pf.status <> 'Active')::bigint AS inactive_employees,
    count(*) FILTER (WHERE pf.status = 'Active' AND (COALESCE(pf.deployment_type, '') = 'Roving' OR pf.roving_assignment_id IS NOT NULL))::bigint AS roving_count,
    count(*) FILTER (WHERE pf.status = 'Active' AND NOT (COALESCE(pf.deployment_type, '') = 'Roving' OR pf.roving_assignment_id IS NOT NULL))::bigint AS stationary_count,
    (SELECT pipeline_count FROM hr_pipeline) AS onboarding_pipeline_count,
    count(*) FILTER (WHERE pf.status IN ('Pending Deactivation', 'For Deactivation'))::bigint AS pending_deactivation_count,
    (
      SELECT count(*)::bigint
      FROM store_staffing ss
      WHERE (ss.onboard_count + ss.open_headcount) > 0
        AND ss.onboard_count::numeric / (ss.onboard_count + ss.open_headcount)::numeric < 0.8
    ) AS staffing_risk_count,
    (SELECT COALESCE(sum(vf.required_headcount), 0)::bigint FROM vacancies_filtered vf) AS open_headcount_count
  FROM plantilla_filtered pf;
END;
$$;

COMMENT ON FUNCTION public.get_web_plantilla_summary(text, uuid, uuid) IS
  'OHM2026_1100 - Web presentation contract only. Returns scoped Plantilla KPI counters (active/inactive, roving/stationary, onboarding pipeline, pending deactivation, staffing risk stores, open headcount). RLS/action RPCs remain authority.';


-- ============================================================================
-- Grants
-- ============================================================================

REVOKE ALL ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.get_web_plantilla_summary(text, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_web_plantilla_summary(text, uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_web_plantilla_summary(text, uuid, uuid) TO authenticated;

-- Validation notes (run in staging/dev with representative JWT sessions):
--
-- 1. Unauthenticated / anon blocked:
--    anon has no execute grant; direct SQL with auth.uid() NULL raises 42501.
--
-- 2. Scoped roving/account user:
--    SELECT account_id, store_id, status FROM public.list_web_plantilla_employees();
--    Expected: only accounts/groups assigned through user_scopes (or legacy
--    users_profile fallback). No cross-scope rows.
--
-- 3. PII safety:
--    The list contract returns age/tenure/masked indicators only. ATM, SSS,
--    PhilHealth, Pag-IBIG, raw rate, exact birthdate, and notes are never selected.
--
-- 4. Staffing view:
--    SELECT store_name, onboard_count, open_headcount, required_headcount, fill_rate,
--      staffing_risk FROM public.list_web_plantilla_store_staffing(p_risk_filter => 'at_risk');
--    Expected: only stores with fill_rate < 0.8.
--
-- 5. Summary counters:
--    SELECT * FROM public.get_web_plantilla_summary();
--    Expected: active/inactive/roving/stationary/pipeline/pending-deactivation/
--    staffing-risk/open-headcount counts consistent with the scoped list contracts.
