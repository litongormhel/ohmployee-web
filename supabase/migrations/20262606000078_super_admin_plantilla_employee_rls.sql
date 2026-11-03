-- Migration: 20262606000078_super_admin_plantilla_employee_rls.sql
-- Description: Ensure authenticated users with the "Super Admin" role have full SELECT access to plantilla and employees tables, and update get_web_plantilla_detail to allow Super Admin direct access.

-- 1. Ensure RLS is active on both tables
ALTER TABLE public.plantilla ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2. PLANTILLA TABLE: Dedicated Super Admin Full SELECT Policy
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "plantilla_super_admin_select" ON public.plantilla;

CREATE POLICY "plantilla_super_admin_select"
ON public.plantilla
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
  -- Check 1: Canonical roles table lookup via users_profile
  EXISTS (
    SELECT 1
    FROM public.users_profile up
    LEFT JOIN public.roles r ON r.id = up.role_id
    WHERE up.auth_user_id = auth.uid()
      AND COALESCE(up.is_active, true) = true
      AND up.archived_at IS NULL
      AND (
        r.role_name = 'Super Admin'
        OR up.role = 'Super Admin'
        OR COALESCE(r.role_level, 0) >= 100
      )
  )
  -- Check 2: System level helper function
  OR public.i_have_full_access()
  -- Check 3: Custom JWT claims / Supabase app_metadata fallback
  OR (COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') ILIKE '%super%admin%')
  OR (COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', '') ILIKE '%super%admin%')
  OR (auth.jwt() ->> 'role' = 'service_role')
);

-- ----------------------------------------------------------------------------
-- 3. EMPLOYEES TABLE: Dedicated Super Admin Full SELECT Policy
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "employees_super_admin_select" ON public.employees;

CREATE POLICY "employees_super_admin_select"
ON public.employees
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
  -- Check 1: Canonical roles table lookup via users_profile
  EXISTS (
    SELECT 1
    FROM public.users_profile up
    LEFT JOIN public.roles r ON r.id = up.role_id
    WHERE up.auth_user_id = auth.uid()
      AND COALESCE(up.is_active, true) = true
      AND up.archived_at IS NULL
      AND (
        r.role_name = 'Super Admin'
        OR up.role = 'Super Admin'
        OR COALESCE(r.role_level, 0) >= 100
      )
  )
  -- Check 2: System level helper function
  OR public.i_have_full_access()
  -- Check 3: Custom JWT claims / Supabase app_metadata fallback
  OR (COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') ILIKE '%super%admin%')
  OR (COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', '') ILIKE '%super%admin%')
  OR (auth.jwt() ->> 'role' = 'service_role')
);

-- ----------------------------------------------------------------------------
-- 4. RPC: get_web_plantilla_detail Super Admin & Direct Table Fallback
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_web_plantilla_detail(p_employee_id uuid)
RETURNS TABLE (
  plantilla_id                uuid,
  employee_name               text,
  employee_no                 text,
  last_name                   text,
  first_name                  text,
  middle_name                 text,
  emploc_no                   text,
  account_id                  uuid,
  account_name                text,
  group_id                    uuid,
  group_name                  text,
  store_id                    uuid,
  store_name                  text,
  primary_store_name          text,
  area                        text,
  province_id                 uuid,
  chain_id                    uuid,
  position_title              text,
  position_id                 uuid,
  deployment_type             text,
  is_roving                   boolean,
  roving_assignment_id        uuid,
  roving_store_count          integer,
  roving_stores               jsonb,
  covered_stores              jsonb,
  schedule                    text,
  rest_day                    text,
  status                      text,
  is_active                   boolean,
  is_inactive                 boolean,
  is_pending_deactivation     boolean,
  is_deactivated              boolean,
  date_hired                  date,
  date_deployed               date,
  tenure_months               integer,
  age                         integer,
  separation_status           text,
  date_of_separation          date,
  over_headcount              boolean,
  hr_emploc_id                uuid,
  onboarding_linked           boolean,
  vcode                       text,
  vacancy_id                  uuid,
  vacancy_code_snapshot       text,
  employee_name_snapshot      text,
  hrco_user_id_snapshot       uuid,
  hrco_name                   text,
  deactivation_overlay        jsonb,
  inactive_at                 timestamp with time zone,
  for_deactivation_at         timestamp with time zone,
  deactivated_at              timestamp with time zone,
  transfer_overlay            jsonb,
  source_headcount_request_id uuid,
  is_hc_placeholder           boolean,
  has_masked_fields           boolean,
  masked_fields               jsonb,
  base_rate_masked            text,
  residential_address         text,
  contact_number              text,
  has_penalty                 boolean,
  row_capabilities            jsonb,
  created_at                  timestamp with time zone,
  updated_at                  timestamp with time zone,
  moved_by_user_id            uuid,
  last_mika_synced_at         timestamp with time zone,
  last_mika_synced_by         uuid
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
  v_cov_stores jsonb;
  v_is_super_admin boolean := false;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla detail requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  -- 1. Check Super Admin via helper or JWT first
  IF public.i_have_full_access()
     OR (COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') ILIKE '%super%admin%')
     OR (COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', '') ILIKE '%super%admin%') THEN
    v_is_super_admin := true;
    v_role_level := 100;
    v_role_name := 'Super Admin';
  END IF;

  -- 2. Lookup caller profile
  SELECT up.id, COALESCE(r.role_name, up.role), COALESCE(r.role_level, 0)
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  LEFT JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND COALESCE(up.is_active, TRUE) = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF (v_profile_id IS NULL OR COALESCE(v_role_level, 0) <= 0) AND NOT v_is_super_admin THEN
    RAISE EXCEPTION 'forbidden: web plantilla detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_role_level, 0) >= 90 THEN
    v_is_super_admin := true;
  END IF;

  -- 3. Verify record exists and caller is authorized
  -- Super Admins query directly against public.plantilla pl so archived/unjoined records load
  IF NOT v_is_super_admin AND NOT EXISTS (
    SELECT 1 FROM public.v_plantilla_safe p
    WHERE p.id = p_employee_id
      AND (
        p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = p.account_id
        )
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: web plantilla detail record is not found or caller has insufficient access'
      USING ERRCODE = '42501';
  END IF;

  -- Build covered stores
  SELECT COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'stable_key', esa.id,
          'store_name', esa.store_name,
          'vcode', esa.vcode,
          'is_primary', (esa.vcode = pl.vcode OR esa.store_id = pl.store_id),
          'allocation_percent', round(esa.filled_hc * 100)
        ) ORDER BY esa.created_at ASC
      )
      FROM public.employee_store_allocations esa
      WHERE (esa.plantilla_id = pl.id OR esa.employee_no = pl.employee_no) AND esa.is_active = true
    ),
    '[]'::jsonb
  ) INTO v_cov_stores
  FROM public.plantilla pl
  WHERE pl.id = p_employee_id;

  -- Return plantilla record (FROM public.plantilla pl with LEFT JOIN to v_plantilla_safe)
  RETURN QUERY
  SELECT
    pl.id                                                                      AS plantilla_id,
    COALESCE(p.employee_name, TRIM(CONCAT(pl.first_name, ' ', pl.middle_name, ' ', pl.last_name))) AS employee_name,
    pl.employee_no,
    pl.last_name,
    pl.first_name,
    pl.middle_name,
    pl.emploc_no,
    COALESCE(p.account_id, pl.account_id)                                      AS account_id,
    COALESCE(a.account_name, pl.account)                                       AS account_name,
    a.group_id,
    g.group_name,
    COALESCE(p.store_id, pl.store_id)                                         AS store_id,
    COALESCE(p.store_name, pl.store_name)                                     AS store_name,
    COALESCE(p.store_name, pl.store_name, (SELECT esa.store_name FROM public.employee_store_allocations esa WHERE (esa.plantilla_id = pl.id OR esa.employee_no = pl.employee_no) AND esa.is_active ORDER BY esa.created_at LIMIT 1)) AS primary_store_name,
    COALESCE(p.area, pl.area)                                                 AS area,
    pl.province_id,
    pl.chain_id,
    COALESCE(p."position", pl."position")                                      AS position_title,
    pl.position_id,
    COALESCE(p.deployment_type, pl.deployment_type, 'Stationary')             AS deployment_type,
    (COALESCE(pl.deployment_type, '') = 'Roving' OR pl.roving_assignment_id IS NOT NULL OR jsonb_array_length(v_cov_stores) > 1) AS is_roving,
    pl.roving_assignment_id,
    GREATEST(COALESCE(p.roving_store_count, 0), jsonb_array_length(v_cov_stores))::integer AS roving_store_count,
    COALESCE(p.roving_stores, '[]'::jsonb)                                     AS roving_stores,
    v_cov_stores                                                               AS covered_stores,
    COALESCE(p.schedule, pl.schedule)                                         AS schedule,
    pl.rest_day,
    COALESCE(p.status, pl.status, 'Active')                                    AS status,
    (COALESCE(pl.status, 'Active') = 'Active')                                 AS is_active,
    (COALESCE(pl.status, 'Active') <> 'Active')                                AS is_inactive,
    (pl.status IN ('Pending Deactivation', 'For Deactivation'))                AS is_pending_deactivation,
    (pl.status = 'Deactivated')                                                AS is_deactivated,
    COALESCE(p.date_hired, pl.date_hired)                                      AS date_hired,
    COALESCE(p.date_hired, pl.date_hired)                                      AS date_deployed,
    COALESCE(p.tenure_months, 0)                                               AS tenure_months,
    COALESCE(p.age, 0)                                                         AS age,
    pl.separation_status,
    pl.date_of_separation,
    COALESCE(pl.over_headcount, FALSE)                                         AS over_headcount,
    pl.hr_emploc_id,
    (pl.hr_emploc_id IS NOT NULL)                                              AS onboarding_linked,
    COALESCE(p.vcode, pl.vcode)                                                AS vcode,
    pl.vacancy_id,
    pl.vacancy_code_snapshot,
    pl.employee_name_snapshot,
    pl.hrco_user_id_snapshot,
    COALESCE(p.hrco_name, pl.hrco_name)                                       AS hrco_name,
    jsonb_build_object(
      'is_pending',         (pl.status IN ('Pending Deactivation', 'For Deactivation')),
      'is_rejected',        (pl.status = 'Rejected Deactivation'),
      'is_deactivated',     (pl.status = 'Deactivated'),
      'deactivated_at',     pl.deactivated_at,
      'deactivation_reason', pl.deactivation_reason
    )                                                                          AS deactivation_overlay,
    pl.inactive_at,
    pl.for_deactivation_at,
    pl.deactivated_at,
    jsonb_build_object(
      'has_transfer_history',      (pl.transferred_from_store_id IS NOT NULL),
      'transferred_from_store_id', pl.transferred_from_store_id,
      'transferred_from_store_name', ts.store_name,
      'last_transfer_at',          pl.last_transfer_at
    )                                                                          AS transfer_overlay,
    pl.source_headcount_request_id,
    (pl.source_headcount_request_id IS NOT NULL)                               AS is_hc_placeholder,
    (pl.sss_no IS NOT NULL OR pl.philhealth_no IS NOT NULL OR pl.pagibig_no IS NOT NULL OR pl.atm_no IS NOT NULL) AS has_masked_fields,
    '[]'::jsonb                                                                AS masked_fields,
    CASE
      WHEN pl.rate IS NOT NULL THEN '₱' || to_char(pl.rate, 'FM999,999,990.00')
      WHEN pl.daily_rate IS NOT NULL THEN '₱' || to_char(pl.daily_rate, 'FM999,999,990.00')
      ELSE NULL
    END                                                                        AS base_rate_masked,
    COALESCE(pl.address, pl.area)                                              AS residential_address,
    pl.contact_no                                                              AS contact_number,
    COALESCE(pl.has_penalty, FALSE)                                            AS has_penalty,
    jsonb_build_object(
      'can_view_detail',              TRUE,
      'can_request_deactivation',     TRUE,
      'can_resubmit_deactivation',    TRUE,
      'can_transfer',                 TRUE,
      'can_request_deletion',         TRUE,
      'can_update_employment_status', TRUE,
      'can_archive',                  TRUE
    )                                                                          AS row_capabilities,
    pl.created_at,
    pl.updated_at,
    pl.moved_by_user_id,
    pl.last_mika_synced_at,
    pl.last_mika_synced_by
  FROM public.plantilla pl
  LEFT JOIN public.v_plantilla_safe p ON p.id = pl.id
  LEFT JOIN public.accounts a ON a.id = COALESCE(p.account_id, pl.account_id)
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN public.stores ts ON ts.id = pl.transferred_from_store_id
  WHERE pl.id = p_employee_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_web_plantilla_detail(uuid) TO authenticated;
