-- Migration: 20262606000133_project_store_schedule_in_plantilla_detail.sql
-- Description: Project store_id, schedule_days, schedule_time, and filled_hc in get_web_plantilla_detail
--              and harden update_plantilla_schedule to reactivate/insert allocation rows per store.

-- -----------------------------------------------------------------------------
-- 1. RPC: get_web_plantilla_detail (Project store-level schedule & allocations)
-- -----------------------------------------------------------------------------
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
  schedule                    text,
  rest_day                    text,
  status                      text,
  is_active                   boolean,
  is_inactive                 boolean,
  is_pending_deactivation     boolean,
  is_deactivated              boolean,
  date_hired                  date,
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
AS $function$
DECLARE
  v_auth_uid   uuid := auth.uid();
  v_profile_id uuid;
  v_role_name  text;
  v_role_level integer;
  v_cov_stores jsonb;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web plantilla detail requires a valid session'
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
    RAISE EXCEPTION 'forbidden: web plantilla detail caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.v_plantilla_safe p
    WHERE p.id = p_employee_id
      AND (
        COALESCE(v_role_level, 0) >= 90
        OR p.account = ANY (public.get_my_allowed_accounts())
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          WHERE us.user_id = v_profile_id AND us.account_id = p.account_id
        )
        OR EXISTS (
          SELECT 1 FROM public.user_scopes us
          JOIN public.accounts ac ON ac.id = p.account_id
          WHERE us.user_id = v_profile_id
            AND us.account_id IS NULL
            AND us.group_id = ac.group_id
        )
        OR EXISTS (
          SELECT 1 FROM public.users_profile up_fb
          JOIN public.accounts ac ON ac.id = p.account_id
          WHERE up_fb.id = v_profile_id
            AND NOT EXISTS (
              SELECT 1 FROM public.user_scopes us_any
              WHERE us_any.user_id = v_profile_id
                AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
            )
            AND (up_fb.account_id = p.account_id OR up_fb.group_id = ac.group_id)
        )
      )
  ) THEN
    RAISE EXCEPTION 'forbidden: web plantilla detail record is not found or caller has insufficient access'
      USING ERRCODE = '42501';
  END IF;

  -- Build covered stores prioritizing active employee_store_allocations
  -- Project store_id, schedule_days, schedule_time, and filled_hc
  SELECT COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'stable_key', esa.id,
          'store_id', esa.store_id,
          'store_name', esa.store_name,
          'vcode', esa.vcode,
          'is_primary', (esa.vcode = pl.vcode OR esa.store_id = pl.store_id),
          'allocation_percent', round(esa.filled_hc * 100),
          'filled_hc', esa.filled_hc,
          'schedule_days', esa.schedule_days,
          'schedule_time', esa.schedule_time
        ) ORDER BY (CASE WHEN (esa.vcode = pl.vcode OR esa.store_id = pl.store_id) THEN 0 ELSE 1 END), esa.created_at ASC
      )
      FROM public.employee_store_allocations esa
      WHERE (esa.plantilla_id = p.id OR (pl.employee_no IS NOT NULL AND esa.employee_no = pl.employee_no))
        AND esa.is_active = true
    ),
    p.roving_stores,
    '[]'::jsonb
  ) INTO v_cov_stores
  FROM public.v_plantilla_safe p
  JOIN public.plantilla pl ON pl.id = p.id
  WHERE p.id = p_employee_id;

  RETURN QUERY
  SELECT
    p.id                                                                       AS plantilla_id,
    p.employee_name,
    p.employee_no,
    pl.last_name,
    pl.first_name,
    pl.middle_name,
    pl.emploc_no,
    p.account_id,
    a.account_name,
    a.group_id,
    g.group_name,
    COALESCE(p.store_id, pl.store_id)                                         AS store_id,
    COALESCE(p.store_name, pl.store_name, (SELECT esa.store_name FROM public.employee_store_allocations esa WHERE esa.plantilla_id = p.id AND esa.is_active ORDER BY esa.created_at LIMIT 1)) AS store_name,
    p.area,
    p.province_id,
    p.chain_id,
    p."position"                                                               AS position_title,
    p.position_id,
    p.deployment_type,
    (COALESCE(p.deployment_type, '') = 'Roving' OR p.roving_assignment_id IS NOT NULL OR jsonb_array_length(v_cov_stores) > 1) AS is_roving,
    p.roving_assignment_id,
    GREATEST(COALESCE(p.roving_store_count, 0), jsonb_array_length(v_cov_stores))::integer AS roving_store_count,
    v_cov_stores                                                               AS roving_stores,
    p.schedule,
    pl.rest_day,
    p.status,
    (p.status = 'Active')                                                      AS is_active,
    (p.status <> 'Active')                                                     AS is_inactive,
    (p.status IN ('Pending Deactivation', 'For Deactivation'))                 AS is_pending_deactivation,
    (p.status = 'Deactivated')                                                 AS is_deactivated,
    COALESCE(p.date_hired, pl.date_hired)                                      AS date_hired,
    p.tenure_months,
    p.age,
    p.separation_status,
    p.date_of_separation,
    COALESCE(p.over_headcount, FALSE)                                          AS over_headcount,
    p.hr_emploc_id,
    (p.hr_emploc_id IS NOT NULL)                                               AS onboarding_linked,
    COALESCE(p.vcode, pl.vcode)                                                AS vcode,
    pl.vacancy_id,
    pl.vacancy_code_snapshot,
    pl.employee_name_snapshot,
    pl.hrco_user_id_snapshot,
    p.hrco_name,
    jsonb_build_object(
      'is_pending',         (p.status IN ('Pending Deactivation', 'For Deactivation')),
      'is_rejected',        (p.status = 'Rejected Deactivation'),
      'is_deactivated',     (p.status = 'Deactivated'),
      'deactivated_at',     p.deactivated_at,
      'deactivation_reason', p.deactivation_reason,
      'display_label', CASE
        WHEN p.status IN ('Pending Deactivation', 'For Deactivation', 'Pending') THEN 'Pending Deactivation'
        WHEN p.status IN ('Rejected Deactivation', 'Rejected') THEN 'Rejected Deactivation'
        WHEN p.status IN ('Deactivated', 'Approved') THEN 'Deactivated'
        ELSE NULL
      END
    )                                                                          AS deactivation_overlay,
    pl.inactive_at,
    pl.for_deactivation_at,
    p.deactivated_at,
    jsonb_build_object(
      'has_transfer_history',      (pl.transferred_from_store_id IS NOT NULL),
      'transferred_from_store_id', pl.transferred_from_store_id,
      'transferred_from_store_name', ts.store_name,
      'last_transfer_at',          pl.last_transfer_at
    )                                                                          AS transfer_overlay,
    p.source_headcount_request_id,
    (p.source_headcount_request_id IS NOT NULL)                                AS is_hc_placeholder,
    (p.sss_no IS NOT NULL OR p.philhealth_no IS NOT NULL OR p.pagibig_no IS NOT NULL OR p.atm_no_masked IS NOT NULL) AS has_masked_fields,
    jsonb_build_object(
      'base_rate_masked', CASE
        WHEN pl.rate IS NOT NULL THEN '₱' || to_char(pl.rate, 'FM999,999,990.00')
        WHEN pl.daily_rate IS NOT NULL THEN '₱' || to_char(pl.daily_rate, 'FM999,999,990.00')
        ELSE NULL
      END,
      'residential_address', COALESCE(pl.address, p.area),
      'contact_number', pl.contact_no,
      'primary_store_name', COALESCE(p.store_name, pl.store_name, (SELECT esa.store_name FROM public.employee_store_allocations esa WHERE esa.plantilla_id = p.id AND esa.is_active ORDER BY esa.created_at LIMIT 1)),
      'date_deployed', COALESCE(p.date_hired, pl.date_hired),
      'atm_no', p.atm_no_masked,
      'sss_no', p.sss_no,
      'philhealth_no', p.philhealth_no,
      'pagibig_no', p.pagibig_no
    )                                                                          AS masked_fields,
    COALESCE(p.has_penalty, FALSE)                                             AS has_penalty,
    jsonb_build_object(
      'can_view_detail',              TRUE,
      'can_request_deactivation',     (
        p.status NOT IN ('Pending Deactivation', 'For Deactivation', 'Deactivated')
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_resubmit_deactivation',    (
        p.status = 'Rejected Deactivation'
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_transfer',                 (
        p.status = 'Active'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_request_deletion',         (
        p.status = 'Active'
        AND (public.i_have_full_access() OR public.i_am_ops())
      ),
      'can_update_employment_status', (
        p.status = 'Active'
        AND (public.i_have_full_access() OR v_role_name = 'Encoder' OR v_role_level = 30)
      ),
      'can_archive',                  (COALESCE(v_role_level, 0) >= 100)
    )                                                                          AS row_capabilities,
    p.created_at,
    p.updated_at,
    pl.moved_by_user_id,
    p.last_mika_synced_at,
    p.last_mika_synced_by
  FROM public.v_plantilla_safe p
  JOIN public.plantilla pl ON pl.id = p.id
  LEFT JOIN public.accounts a ON a.id = p.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN public.stores ts ON ts.id = pl.transferred_from_store_id
  WHERE p.id = p_employee_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_web_plantilla_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_web_plantilla_detail(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. RPC: update_plantilla_schedule (Support active, inactive reactivation & insert)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_plantilla_schedule(
  p_plantilla_id uuid,
  p_schedule_days text,
  p_schedule_time text,
  p_dayoff text,
  p_store_allocations jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_emp_no text;
  v_account text;
  v_alloc_count int := 0;
  elem jsonb;
  v_store_id text;
  v_store_name text;
  v_vcode text;
  v_sched_days text;
  v_sched_time text;
  v_percent numeric;
  v_filled_hc numeric;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: Authentication required.' USING ERRCODE = '42501';
  END IF;

  IF COALESCE(public.get_my_role_level(), 0) < 25 THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Insufficient role level to update plantilla schedule.' USING ERRCODE = '42501';
  END IF;

  IF p_plantilla_id IS NULL THEN
    RAISE EXCEPTION 'plantilla_id cannot be null' USING ERRCODE = '22004';
  END IF;

  -- Verify employee exists and get employee_no + account
  SELECT employee_no, account INTO v_emp_no, v_account
  FROM public.plantilla
  WHERE id = p_plantilla_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla record not found for id %', p_plantilla_id USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.i_have_full_access() AND NOT (v_account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Target employee is outside your assigned account scope.' USING ERRCODE = '42501';
  END IF;

  -- 1. Update public.plantilla record
  UPDATE public.plantilla
  SET
    schedule_days = COALESCE(p_schedule_days, schedule_days),
    schedule = COALESCE(p_schedule_days, schedule),
    schedule_time = COALESCE(p_schedule_time, schedule_time),
    dayoff = COALESCE(p_dayoff, dayoff),
    rest_day = COALESCE(p_dayoff, rest_day),
    deployment_type = CASE
      WHEN p_store_allocations IS NOT NULL AND jsonb_array_length(p_store_allocations) > 1 THEN 'Roving'
      WHEN p_store_allocations IS NOT NULL AND jsonb_array_length(p_store_allocations) = 1 THEN 'Stationary'
      ELSE deployment_type
    END,
    updated_at = NOW()
  WHERE id = p_plantilla_id;

  -- 2. Update public.employee_store_allocations
  IF p_store_allocations IS NOT NULL AND jsonb_array_length(p_store_allocations) > 0 THEN
    FOR elem IN SELECT * FROM jsonb_array_elements(p_store_allocations)
    LOOP
      v_store_id := NULLIF(TRIM(COALESCE(elem->>'storeId', elem->>'store_id', '')), '');
      v_store_name := NULLIF(TRIM(COALESCE(elem->>'storeName', elem->>'store_name', '')), '');
      v_vcode := NULLIF(TRIM(COALESCE(elem->>'vcode', elem->>'store_code', '')), '');
      v_sched_days := COALESCE(elem->>'scheduleDays', elem->>'schedule_days', p_schedule_days);
      v_sched_time := COALESCE(elem->>'scheduleTime', elem->>'schedule_time', p_schedule_time);
      v_percent := COALESCE((elem->>'allocationPercent')::numeric, (elem->>'allocation_percent')::numeric, 100);
      v_filled_hc := ROUND(v_percent / 100.0, 4);

      -- Step 2a: Update existing active allocation row
      UPDATE public.employee_store_allocations
      SET
        filled_hc = COALESCE(v_filled_hc, filled_hc),
        schedule_days = v_sched_days,
        schedule_time = v_sched_time,
        vcode = COALESCE(v_vcode, vcode),
        store_id = CASE WHEN v_store_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN v_store_id::uuid ELSE store_id END
      WHERE (plantilla_id = p_plantilla_id OR (v_emp_no IS NOT NULL AND employee_no = v_emp_no))
        AND is_active = true
        AND (
          (v_vcode IS NOT NULL AND vcode = v_vcode)
          OR (v_store_id IS NOT NULL AND store_id::text = v_store_id)
          OR (v_store_name IS NOT NULL AND store_name = v_store_name)
        );

      -- Step 2b: If no active row existed for this store, reactivate the latest inactive row
      IF NOT FOUND THEN
        UPDATE public.employee_store_allocations
        SET
          filled_hc = COALESCE(v_filled_hc, filled_hc),
          schedule_days = v_sched_days,
          schedule_time = v_sched_time,
          vcode = COALESCE(v_vcode, vcode),
          store_id = CASE WHEN v_store_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN v_store_id::uuid ELSE store_id END,
          is_active = true,
          effective_end = NULL
        WHERE id = (
          SELECT id FROM public.employee_store_allocations
          WHERE (plantilla_id = p_plantilla_id OR (v_emp_no IS NOT NULL AND employee_no = v_emp_no))
            AND (
              (v_vcode IS NOT NULL AND vcode = v_vcode)
              OR (v_store_id IS NOT NULL AND store_id::text = v_store_id)
              OR (v_store_name IS NOT NULL AND store_name = v_store_name)
            )
          ORDER BY created_at DESC
          LIMIT 1
        );
      END IF;

      -- Step 2c: If still not found, insert fresh allocation row
      IF NOT FOUND THEN
        INSERT INTO public.employee_store_allocations (
          plantilla_id,
          employee_no,
          store_id,
          store_name,
          vcode,
          filled_hc,
          schedule_days,
          schedule_time,
          is_active
        ) VALUES (
          p_plantilla_id,
          v_emp_no,
          CASE WHEN v_store_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN v_store_id::uuid ELSE NULL END,
          v_store_name,
          v_vcode,
          COALESCE(v_filled_hc, 1.0),
          v_sched_days,
          v_sched_time,
          true
        );
      END IF;

      v_alloc_count := v_alloc_count + 1;
    END LOOP;
  ELSE
    -- If no array of store allocations provided, update any active allocation rows with global schedule
    UPDATE public.employee_store_allocations
    SET
      schedule_days = COALESCE(p_schedule_days, schedule_days),
      schedule_time = COALESCE(p_schedule_time, schedule_time)
    WHERE (plantilla_id = p_plantilla_id OR (v_emp_no IS NOT NULL AND employee_no = v_emp_no))
      AND is_active = true;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'plantilla_id', p_plantilla_id,
    'employee_no', v_emp_no,
    'updated_allocations', v_alloc_count
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.update_plantilla_schedule(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_plantilla_schedule(uuid, text, text, text, jsonb) TO authenticated;
