-- ============================================================
-- OHM2026_1136 — CENCOM Data Integrity Report (Phase 1)
-- ============================================================
-- Executive operational audit report surfacing workforce data
-- integrity issues and delayed operational updates.
--
-- Sections:
--   1. Late HR Updates        (Medium)
--   2. Vacancy Creation Delay (High)
--   3. Ghost Occupancy        (Critical)
--   4. Pipeline Without Vacancy (High)
--
-- RPCs:
--   fn_data_integrity_summary              — landing KPIs + section summaries
--   fn_data_integrity_late_hr_detail       — Late HR Updates drilldown
--   fn_data_integrity_vacancy_delay_detail — Vacancy Creation Delay drilldown
--   fn_data_integrity_ghost_occupancy_detail — Ghost Occupancy drilldown
--   fn_data_integrity_pipeline_no_vacancy_detail — Pipeline Without Vacancy drilldown
--
-- All RPCs: SECURITY DEFINER, scope-safe, read-only, authenticated only.
-- No schema changes. No workflow changes. Reporting layer only.
-- ============================================================


-- ─── §1  fn_data_integrity_summary ───────────────────────────────────────────
-- Returns JSONB with 4 KPI totals and per-section summaries.
-- Scope: caller's allowed accounts (or full access for SA/HA).
-- Default lookback: 365 days for delay sections, current state for ghost/pipeline.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.fn_data_integrity_summary(uuid, uuid);

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
  -- Plantilla separations where encoding delay > 7 days (SLA).
  -- delay_days = updated_at::date - date_of_separation
  SELECT
    COUNT(*)::bigint,
    COUNT(DISTINCT p.store_id)::bigint,
    COALESCE(MAX((p.updated_at::date - p.date_of_separation)::integer), 0)
  INTO v_late_hr_count, v_late_hr_stores, v_late_hr_worst
  FROM public.plantilla p
  WHERE p.is_deleted = FALSE
    AND p.date_of_separation IS NOT NULL
    AND p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others')
    AND (p.updated_at::date - p.date_of_separation) > 7
    AND p.date_of_separation >= CURRENT_DATE - INTERVAL '365 days'
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
  -- For each separation, find the earliest vacancy opened at the same store
  -- after the departure. If delay > 7 days, it is a finding.
  SELECT
    COUNT(*)::bigint,
    COUNT(DISTINCT sub.store_id)::bigint,
    COALESCE(MAX(sub.delay_days), 0)
  INTO v_vac_delay_count, v_vac_delay_stores, v_vac_delay_worst
  FROM (
    SELECT DISTINCT ON (p.id)
      p.id,
      p.store_id,
      (v.created_at::date - p.date_of_separation)::integer AS delay_days
    FROM public.plantilla p
    JOIN public.vacancies v
      ON v.store_id = p.store_id
     AND v.created_at > p.date_of_separation::timestamptz
     AND v.deleted_at IS NULL
     AND COALESCE(v.is_archived, false) = false
    WHERE p.is_deleted = FALSE
      AND p.date_of_separation IS NOT NULL
      AND p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others')
      AND p.date_of_separation >= CURRENT_DATE - INTERVAL '180 days'
      AND (v.created_at::date - p.date_of_separation) > 7
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
  -- Stationary slots (is_roving = false) with slot_status = 'occupied' but:
  --   a) current_occupant_plantilla_id IS NULL (orphaned), OR
  --   b) occupant has separation signals (resigned, deactivated, etc.)
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
  -- Active-pipeline applicants linked to a non-open vacancy.
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
      AND p.date_of_separation IS NOT NULL
      AND p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others')
      AND (p.updated_at::date - p.date_of_separation) > 7
      AND p.date_of_separation >= CURRENT_DATE - INTERVAL '365 days'
      AND (p_account_id IS NULL OR p.account_id = p_account_id)
      AND (p_group_id IS NULL OR EXISTS (
        SELECT 1 FROM public.accounts ac2 WHERE ac2.id = p.account_id AND ac2.group_id = p_group_id
      ))
      AND p.account_id IN (SELECT ac.id FROM public.accounts ac WHERE ac.is_active = TRUE AND (COALESCE(v_role_level,0)>=90 OR ac.account_name=ANY(public.get_my_allowed_accounts()) OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id=ac.id) OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id IS NULL AND us.group_id=ac.group_id) OR NOT EXISTS(SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id=v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))))
    UNION
    SELECT ps.store_id
    FROM public.plantilla_slots ps
    WHERE ps.slot_status = 'occupied' AND COALESCE(ps.is_roving,false)=false
      AND (p_account_id IS NULL OR ps.account_id = p_account_id)
      AND (p_group_id IS NULL OR ps.group_id = p_group_id)
      AND ps.account_id IN (SELECT ac.id FROM public.accounts ac WHERE ac.is_active=TRUE AND (COALESCE(v_role_level,0)>=90 OR ac.account_name=ANY(public.get_my_allowed_accounts()) OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id=ac.id) OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id IS NULL AND us.group_id=ac.group_id) OR NOT EXISTS(SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id=v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))))
      AND (ps.current_occupant_plantilla_id IS NULL OR EXISTS(SELECT 1 FROM public.plantilla p WHERE p.id=ps.current_occupant_plantilla_id AND p.is_deleted=FALSE AND (p.status NOT IN('Active','On Leave') OR p.date_of_separation IS NOT NULL OR p.deactivated_at IS NOT NULL)))
    UNION
    SELECT v.store_id
    FROM public.applicants a
    JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
    WHERE COALESCE(a.is_archived,false)=false AND public.fn_is_active_vacancy_applicant_status(a.status)=true
      AND v.status NOT IN('Open','For Sourcing') AND v.deleted_at IS NULL AND COALESCE(v.is_archived,false)=false
      AND (p_account_id IS NULL OR v.account_id=p_account_id)
      AND (p_group_id IS NULL OR EXISTS(SELECT 1 FROM public.accounts ac2 WHERE ac2.id=v.account_id AND ac2.group_id=p_group_id))
      AND v.account_id IN (SELECT ac.id FROM public.accounts ac WHERE ac.is_active=TRUE AND (COALESCE(v_role_level,0)>=90 OR ac.account_name=ANY(public.get_my_allowed_accounts()) OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id=ac.id) OR EXISTS(SELECT 1 FROM public.user_scopes us WHERE us.user_id=v_profile_id AND us.account_id IS NULL AND us.group_id=ac.group_id) OR NOT EXISTS(SELECT 1 FROM public.user_scopes us_any WHERE us_any.user_id=v_profile_id AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL))))
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

COMMENT ON FUNCTION public.fn_data_integrity_summary(uuid, uuid) IS
  'OHM2026_1136 Data Integrity Report — landing KPI summary. Returns JSONB with '
  'critical_issues (Ghost Occupancy), high_risk_issues (Pipeline+VacDelay), '
  'total_findings, affected_stores, and per-section summaries. '
  'SECURITY DEFINER; read-only; scope-safe. Requires authenticated session.';


-- ─── §2  fn_data_integrity_late_hr_detail ────────────────────────────────────
-- Paginated Late HR Updates detail rows.
-- delay_days = updated_at::date - date_of_separation; filter > p_sla_days.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.fn_data_integrity_late_hr_detail(uuid, uuid, integer, integer, integer);

CREATE OR REPLACE FUNCTION public.fn_data_integrity_late_hr_detail(
  p_group_id   uuid    DEFAULT NULL,
  p_account_id uuid    DEFAULT NULL,
  p_sla_days   integer DEFAULT 7,
  p_page       integer DEFAULT 0,
  p_page_size  integer DEFAULT 25
)
RETURNS TABLE (
  store_name     text,
  account_name   text,
  group_name     text,
  employee_name  text,
  employee_no    text,
  "position"     text,
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
    p.date_of_separation               AS effective_date,
    p.updated_at::date                 AS recorded_date,
    (p.updated_at::date - p.date_of_separation)::integer AS delay_days,
    p.separation_status::text          AS issue_type,
    CURRENT_DATE                       AS detected_date
  FROM public.plantilla p
  JOIN public.accounts ac ON ac.id = p.account_id
  JOIN public.groups g    ON g.id  = ac.group_id
  WHERE p.is_deleted = FALSE
    AND p.date_of_separation IS NOT NULL
    AND p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others')
    AND (p.updated_at::date - p.date_of_separation) > p_sla_days
    AND p.date_of_separation >= CURRENT_DATE - INTERVAL '365 days'
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
  ORDER BY delay_days DESC, p.date_of_separation DESC
  LIMIT p_page_size OFFSET (p_page * p_page_size);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_data_integrity_late_hr_detail(uuid, uuid, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_data_integrity_late_hr_detail(uuid, uuid, integer, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_data_integrity_late_hr_detail(uuid, uuid, integer, integer, integer) TO authenticated;

COMMENT ON FUNCTION public.fn_data_integrity_late_hr_detail(uuid, uuid, integer, integer, integer) IS
  'OHM2026_1136 — Paginated Late HR Updates detail. Returns plantilla separations '
  'where updated_at - date_of_separation > p_sla_days. Ordered by delay DESC. '
  'SECURITY DEFINER; scope-safe. Requires authenticated session.';


-- ─── §3  fn_data_integrity_vacancy_delay_detail ──────────────────────────────
-- Paginated Vacancy Creation Delay detail rows.
-- Links each separation to the earliest replacement vacancy at the same store.
-- Shows only separations where the delay > p_sla_days.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.fn_data_integrity_vacancy_delay_detail(uuid, uuid, integer, integer, integer);

CREATE OR REPLACE FUNCTION public.fn_data_integrity_vacancy_delay_detail(
  p_group_id   uuid    DEFAULT NULL,
  p_account_id uuid    DEFAULT NULL,
  p_sla_days   integer DEFAULT 7,
  p_page       integer DEFAULT 0,
  p_page_size  integer DEFAULT 25
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
      p.date_of_separation,
      v.created_at::date                              AS vacancy_created_date,
      (v.created_at::date - p.date_of_separation)::integer AS delay_days,
      v.vcode,
      ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY v.created_at) AS rn
    FROM public.plantilla p
    JOIN public.accounts ac ON ac.id = p.account_id
    JOIN public.groups g    ON g.id  = ac.group_id
    JOIN public.vacancies v
      ON v.store_id = p.store_id
     AND v.created_at > p.date_of_separation::timestamptz
     AND v.deleted_at IS NULL
     AND COALESCE(v.is_archived, false) = false
    WHERE p.is_deleted = FALSE
      AND p.date_of_separation IS NOT NULL
      AND p.separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others')
      AND p.date_of_separation >= CURRENT_DATE - INTERVAL '180 days'
      AND (v.created_at::date - p.date_of_separation) > p_sla_days
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

COMMENT ON FUNCTION public.fn_data_integrity_vacancy_delay_detail(uuid, uuid, integer, integer, integer) IS
  'OHM2026_1136 — Paginated Vacancy Creation Delay detail. For each separation, '
  'finds the earliest replacement vacancy at the same store created after departure. '
  'Reports delay > p_sla_days. Ordered by delay DESC. SECURITY DEFINER; scope-safe.';


-- ─── §4  fn_data_integrity_ghost_occupancy_detail ────────────────────────────
-- Paginated Ghost Occupancy detail rows.
-- Stationary slots (is_roving=false) with slot_status='occupied' but:
--   - No occupant reference (current_occupant_plantilla_id IS NULL), OR
--   - Occupant has separation signal (not Active/On Leave, or has departure date).
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.fn_data_integrity_ghost_occupancy_detail(uuid, uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.fn_data_integrity_ghost_occupancy_detail(
  p_group_id   uuid    DEFAULT NULL,
  p_account_id uuid    DEFAULT NULL,
  p_page       integer DEFAULT 0,
  p_page_size  integer DEFAULT 25
)
RETURNS TABLE (
  store_name    text,
  account_name  text,
  group_name    text,
  slot_id       uuid,
  employee_name text,
  "position"    text,
  issue_type    text,
  detected_date date
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
    RAISE EXCEPTION 'unauthenticated: fn_data_integrity_ghost_occupancy_detail requires a valid session'
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
    RAISE EXCEPTION 'forbidden: fn_data_integrity_ghost_occupancy_detail caller is not allowed'
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
  ghost_slots AS (
    SELECT
      ps.id          AS slot_id,
      ps.store_id,
      ps.account_id,
      ps.position,
      ps.current_occupant_plantilla_id,
      CASE
        WHEN ps.current_occupant_plantilla_id IS NULL
          THEN 'No Active Employee Allocation'
        ELSE (
          SELECT
            CASE
              WHEN p.date_of_separation IS NOT NULL THEN 'Employee Separated'
              WHEN p.deactivated_at IS NOT NULL      THEN 'Employee Deactivated'
              ELSE 'Employee Inactive'
            END
          FROM public.plantilla p
          WHERE p.id = ps.current_occupant_plantilla_id
            AND p.is_deleted = FALSE
          LIMIT 1
        )
      END AS issue_type
    FROM public.plantilla_slots ps
    WHERE ps.slot_status = 'occupied'
      AND COALESCE(ps.is_roving, false) = false
      AND (p_account_id IS NULL OR ps.account_id = p_account_id)
      AND (p_group_id IS NULL OR ps.group_id = p_group_id)
      AND ps.account_id IN (SELECT sa.account_id FROM scoped_accounts sa)
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
      )
  )
  SELECT
    COALESCE(st.store_name, '—')::text        AS store_name,
    ac.account_name::text,
    g.group_name::text,
    gs.slot_id,
    COALESCE(
      (SELECT p.employee_name FROM public.plantilla p WHERE p.id = gs.current_occupant_plantilla_id AND p.is_deleted = FALSE LIMIT 1),
      '—'
    )::text                                    AS employee_name,
    gs.position::text,
    gs.issue_type::text,
    CURRENT_DATE                               AS detected_date
  FROM ghost_slots gs
  JOIN public.accounts ac ON ac.id = gs.account_id
  JOIN public.groups g    ON g.id  = ac.group_id
  LEFT JOIN public.stores st ON st.id = gs.store_id
  ORDER BY gs.issue_type, ac.account_name, store_name
  LIMIT p_page_size OFFSET (p_page * p_page_size);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_data_integrity_ghost_occupancy_detail(uuid, uuid, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_data_integrity_ghost_occupancy_detail(uuid, uuid, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_data_integrity_ghost_occupancy_detail(uuid, uuid, integer, integer) TO authenticated;

COMMENT ON FUNCTION public.fn_data_integrity_ghost_occupancy_detail(uuid, uuid, integer, integer) IS
  'OHM2026_1136 — Paginated Ghost Occupancy detail. Finds stationary plantilla slots '
  'with slot_status=occupied but no valid active occupant. Excludes roving slots to '
  'avoid false positives on coverage-group allocations. SECURITY DEFINER; scope-safe.';


-- ─── §5  fn_data_integrity_pipeline_no_vacancy_detail ───────────────────────
-- Paginated Pipeline Without Vacancy detail rows.
-- Active-pipeline applicants whose linked vacancy is not Open/For Sourcing.
-- Excludes: Closed, Hired, Archived, Withdrawn, Rejected statuses.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.fn_data_integrity_pipeline_no_vacancy_detail(uuid, uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.fn_data_integrity_pipeline_no_vacancy_detail(
  p_group_id   uuid    DEFAULT NULL,
  p_account_id uuid    DEFAULT NULL,
  p_page       integer DEFAULT 0,
  p_page_size  integer DEFAULT 25
)
RETURNS TABLE (
  vcode          text,
  applicant_name text,
  store_name     text,
  account_name   text,
  group_name     text,
  current_status text,
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
    RAISE EXCEPTION 'unauthenticated: fn_data_integrity_pipeline_no_vacancy_detail requires a valid session'
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
    RAISE EXCEPTION 'forbidden: fn_data_integrity_pipeline_no_vacancy_detail caller is not allowed'
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
  )
  SELECT
    a.vacancy_vcode::text                     AS vcode,
    COALESCE(a.full_name, a.applicant_name)::text AS applicant_name,
    COALESCE(v.store_name, '—')::text         AS store_name,
    ac.account_name::text,
    g.group_name::text,
    a.status::text                            AS current_status,
    ('Vacancy ' || v.status || ' — active applicant')::text AS issue_type,
    CURRENT_DATE                              AS detected_date
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  JOIN public.accounts ac ON ac.id = v.account_id
  JOIN public.groups g    ON g.id  = ac.group_id
  WHERE COALESCE(a.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a.status) = true
    AND v.status NOT IN ('Open', 'For Sourcing')
    AND v.deleted_at IS NULL
    AND COALESCE(v.is_archived, false) = false
    AND (p_account_id IS NULL OR v.account_id = p_account_id)
    AND (p_group_id IS NULL OR ac.group_id = p_group_id)
    AND v.account_id IN (SELECT sa.account_id FROM scoped_accounts sa)
  ORDER BY a.status, ac.account_name, v.store_name
  LIMIT p_page_size OFFSET (p_page * p_page_size);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_data_integrity_pipeline_no_vacancy_detail(uuid, uuid, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_data_integrity_pipeline_no_vacancy_detail(uuid, uuid, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_data_integrity_pipeline_no_vacancy_detail(uuid, uuid, integer, integer) TO authenticated;

COMMENT ON FUNCTION public.fn_data_integrity_pipeline_no_vacancy_detail(uuid, uuid, integer, integer) IS
  'OHM2026_1136 — Paginated Pipeline Without Vacancy detail. Finds active-pipeline '
  'applicants whose linked vacancy is not Open or For Sourcing. Uses fn_is_active_vacancy_applicant_status. '
  'Excludes closed/hired/archived/withdrawn/rejected. SECURITY DEFINER; scope-safe.';


-- ─── §S Smoke Queries ────────────────────────────────────────────────────────
-- §S1: Summary (full access)
-- SELECT fn_data_integrity_summary();
--
-- §S2: Summary scoped to a group
-- SELECT fn_data_integrity_summary(p_group_id := '<group_uuid>');
--
-- §S3: Late HR Updates detail, page 0
-- SELECT * FROM fn_data_integrity_late_hr_detail(p_sla_days := 7, p_page := 0, p_page_size := 25);
--
-- §S4: Vacancy Delay detail
-- SELECT * FROM fn_data_integrity_vacancy_delay_detail(p_sla_days := 7, p_page := 0, p_page_size := 25);
--
-- §S5: Ghost Occupancy detail
-- SELECT * FROM fn_data_integrity_ghost_occupancy_detail(p_page := 0, p_page_size := 25);
--
-- §S6: Pipeline Without Vacancy detail
-- SELECT * FROM fn_data_integrity_pipeline_no_vacancy_detail(p_page := 0, p_page_size := 25);
-- ─────────────────────────────────────────────────────────────────────────────
