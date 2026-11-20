-- =============================================================================
-- Migration: 20262606000127_security_hardening_rls_rpcs_views.sql
-- Purpose: Remediate Critical & High SQL/RLS/RPC/View security audit findings
--          across ohmployee-web & OHMployee with 100% View/RPC parity.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CRITICAL: Lock down storage cleanup SECURITY DEFINER RPCs to service_role
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.enqueue_hr_emploc_docs_cleanup(uuid, text, interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_hr_emploc_docs_cleanup(uuid, text, interval) TO service_role;

REVOKE ALL ON FUNCTION public.process_storage_cleanup_queue(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_storage_cleanup_queue(integer) TO service_role;

-- -----------------------------------------------------------------------------
-- 2. HIGH: Close users_profile.role & JWT user_metadata RLS bypass
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS plantilla_super_admin_select ON public.plantilla;
CREATE POLICY plantilla_super_admin_select
  ON public.plantilla
  FOR SELECT
  TO authenticated
  USING (public.is_super_admin());

DROP POLICY IF EXISTS employees_super_admin_select ON public.employees;
CREATE POLICY employees_super_admin_select
  ON public.employees
  FOR SELECT
  TO authenticated
  USING (public.is_super_admin());

CREATE OR REPLACE FUNCTION public.trg_enforce_user_hierarchy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor_level    INT;
  v_target_level   INT;
  v_new_role_level INT;
BEGIN
  -- Allow service-role operations (background jobs, migrations)
  -- auth.uid() is NULL when called via service role key
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  v_actor_level  := get_my_role_level();
  v_target_level := get_target_role_level(OLD.id);

  -- ── Self-update: only allow non-sensitive field changes ──────
  IF OLD.auth_user_id = auth.uid() THEN
    IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot change your own role.';
    END IF;
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot change your own role.';
    END IF;
    IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot change your own active status.';
    END IF;
    RETURN NEW;
  END IF;

  -- ── Editing another user: must strictly outrank target ───────
  IF v_actor_level IS NULL OR v_actor_level <= COALESCE(v_target_level, 0) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Insufficient role level to modify this user. '
      'Your level: %, Target level: %', v_actor_level, v_target_level;
  END IF;

  -- ── Role change: new role must be strictly below actor level ─
  IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
    SELECT r.role_level INTO v_new_role_level
    FROM roles r WHERE r.id = NEW.role_id;

    IF v_new_role_level >= v_actor_level THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot assign a role at or above your own level. '
        'Your level: %, Attempted: %', v_actor_level, v_new_role_level;
    END IF;
  END IF;

  -- ── Email change: Super Admin only ───────────────────────────
  IF NEW.email IS DISTINCT FROM OLD.email THEN
    IF v_actor_level < 100 THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin can change a user email.';
    END IF;
  END IF;

  -- ── Reactivation guard ────────────────────────────────────────
  IF NEW.is_active = true AND OLD.is_active = false THEN
    IF v_actor_level <= COALESCE(v_target_level, 0) THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot reactivate a user at or above your role level.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. HIGH: Authorize update_plantilla_schedule (surgical diff, same signature)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_plantilla_schedule(
  p_plantilla_id uuid,
  p_schedule_days text,
  p_schedule_time text,
  p_dayoff text,
  p_store_allocations jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

      UPDATE public.employee_store_allocations
      SET
        filled_hc = COALESCE(v_filled_hc, filled_hc),
        schedule_days = v_sched_days,
        schedule_time = v_sched_time,
        vcode = COALESCE(v_vcode, vcode)
      WHERE (plantilla_id = p_plantilla_id OR (v_emp_no IS NOT NULL AND employee_no = v_emp_no))
        AND is_active = true
        AND (
          (v_vcode IS NOT NULL AND vcode = v_vcode)
          OR (v_store_id IS NOT NULL AND store_id::text = v_store_id)
          OR (v_store_name IS NOT NULL AND store_name = v_store_name)
        );

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
$$;

REVOKE ALL ON FUNCTION public.update_plantilla_schedule(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_plantilla_schedule(uuid, text, text, text, jsonb) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4. HIGH: Restore security_invoker = true on core operational & dashboard views
--          (Recreates v_dashboard_* views if dropped during upstream CASCADE)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_dashboard_account_breakdown
  WITH (security_invoker = true)
AS
SELECT
  account,
  COUNT(*) FILTER (WHERE status = 'Active')   AS active,
  COUNT(*) FILTER (WHERE status = 'Resigned') AS resigned
FROM public.v_plantilla_safe
GROUP BY account
HAVING COUNT(*) FILTER (WHERE status IN ('Active', 'Resigned')) > 0
ORDER BY active DESC;

GRANT SELECT ON public.v_dashboard_account_breakdown TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_account_mfr_breakdown
  WITH (security_invoker = true)
AS
 WITH active_agg AS (
         SELECT v_plantilla_safe.account,
            count(*) AS active
           FROM v_plantilla_safe
          WHERE v_plantilla_safe.status = 'Active'::text AND v_plantilla_safe.account IS NOT NULL AND TRIM(BOTH FROM v_plantilla_safe.account) <> ''::text
          GROUP BY v_plantilla_safe.account
        ), pipeline_agg AS (
         SELECT hr_emploc.account,
            count(*) AS pipeline
           FROM hr_emploc
          WHERE (hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])) AND hr_emploc.deleted_at IS NULL AND hr_emploc.account IS NOT NULL AND TRIM(BOTH FROM hr_emploc.account) <> ''::text
          GROUP BY hr_emploc.account
        ), vac_agg AS (
         SELECT vw_slot_derived_vacancy_shadow.account_name AS account,
            count(*) AS vacancies
           FROM vw_slot_derived_vacancy_shadow
          WHERE (vw_slot_derived_vacancy_shadow.open_count - vw_slot_derived_vacancy_shadow.pipeline_count - vw_slot_derived_vacancy_shadow.hr_processing_count) > 0 AND vw_slot_derived_vacancy_shadow.account_name IS NOT NULL AND TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.account_name) <> ''::text
          GROUP BY vw_slot_derived_vacancy_shadow.account_name
        ), all_accounts AS (
         SELECT active_agg.account
           FROM active_agg
        UNION
         SELECT pipeline_agg.account
           FROM pipeline_agg
        UNION
         SELECT vac_agg.account
           FROM vac_agg
        )
 SELECT aa.account,
    COALESCE(a.active, 0::bigint) AS active,
    COALESCE(p.pipeline, 0::bigint) AS pipeline,
    COALESCE(v.vacancies, 0::bigint) AS vacancies,
    COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint) AS required,
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint))::numeric
            ELSE 1.0
        END AS mfr
   FROM all_accounts aa
     LEFT JOIN active_agg a ON a.account = aa.account
     LEFT JOIN pipeline_agg p ON p.account = aa.account
     LEFT JOIN vac_agg v ON v.account = aa.account
  ORDER BY (
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint))::numeric
            ELSE 1.0
        END), aa.account;

GRANT SELECT ON public.v_dashboard_account_mfr_breakdown TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_hrco_breakdown
  WITH (security_invoker = true)
AS
 WITH active_agg AS (
         SELECT v_plantilla_safe.hrco_name AS hrco,
            count(*) AS active
           FROM v_plantilla_safe
          WHERE v_plantilla_safe.status = 'Active'::text AND v_plantilla_safe.hrco_name IS NOT NULL AND TRIM(BOTH FROM v_plantilla_safe.hrco_name) <> ''::text
          GROUP BY v_plantilla_safe.hrco_name
        ), pipeline_agg AS (
         SELECT hr_emploc.hrco_name AS hrco,
            count(*) AS pipeline
           FROM hr_emploc
          WHERE (hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])) AND hr_emploc.deleted_at IS NULL AND hr_emploc.hrco_name IS NOT NULL AND TRIM(BOTH FROM hr_emploc.hrco_name) <> ''::text
          GROUP BY hr_emploc.hrco_name
        ), vac_agg AS (
         SELECT COALESCE(NULLIF(TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.hrco_name), ''::text), 'Unassigned'::text) AS hrco,
            count(*) AS vacant
           FROM vw_slot_derived_vacancy_shadow
          WHERE (vw_slot_derived_vacancy_shadow.open_count - vw_slot_derived_vacancy_shadow.pipeline_count - vw_slot_derived_vacancy_shadow.hr_processing_count) > 0
          GROUP BY (COALESCE(NULLIF(TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.hrco_name), ''::text), 'Unassigned'::text))
        ), all_hrco AS (
         SELECT active_agg.hrco
           FROM active_agg
        UNION
         SELECT pipeline_agg.hrco
           FROM pipeline_agg
        UNION
         SELECT vac_agg.hrco
           FROM vac_agg
        )
 SELECT ah.hrco,
    COALESCE(v.vacant, 0::bigint) AS vacant,
    COALESCE(a.active, 0::bigint) AS active,
    COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint) AS required,
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint))::numeric
            ELSE 1.0
        END AS mfr
   FROM all_hrco ah
     LEFT JOIN active_agg a ON a.hrco = ah.hrco
     LEFT JOIN pipeline_agg p ON p.hrco = ah.hrco
     LEFT JOIN vac_agg v ON v.hrco = ah.hrco
  ORDER BY (
        CASE
            WHEN ah.hrco = 'Unassigned'::text THEN 1
            ELSE 0
        END), ah.hrco;

GRANT SELECT ON public.v_dashboard_hrco_breakdown TO authenticated, service_role;

ALTER VIEW public.vw_vacancy_list SET (security_invoker = true);
ALTER VIEW public.v_plantilla_safe SET (security_invoker = true);
ALTER VIEW public.vw_vacancy_detail SET (security_invoker = true);
ALTER VIEW IF EXISTS public.v_dashboard_hrco_breakdown SET (security_invoker = true);
ALTER VIEW public.headcount_summary SET (security_invoker = true);

-- -----------------------------------------------------------------------------
-- 5. HIGH: Revoke anon access on employee_number_registry & archive history
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS p_select_employee_number_registry ON public.employee_number_registry;
CREATE POLICY p_select_employee_number_registry
  ON public.employee_number_registry
  FOR SELECT
  TO authenticated
  USING (true);

REVOKE SELECT ON public.employee_number_registry FROM anon;

CREATE OR REPLACE FUNCTION public.fn_get_archive_batch_history()
 RETURNS TABLE(id uuid, archive_batch_id uuid, action_type text, reason text, executed_by_name text, executed_at timestamp with time zone, rollback_deadline timestamp with time zone, plantilla_count integer, vacancy_count integer, hr_emploc_count integer, moses_hq_count integer, total_count integer, status text, rolled_back_by_name text, rolled_back_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    b.id, b.archive_batch_id, b.action_type, b.reason,
    COALESCE(up.full_name, 'Unknown') AS executed_by_name,
    b.executed_at, b.rollback_deadline,
    b.plantilla_count, b.vacancy_count, b.hr_emploc_count, b.moses_hq_count,
    b.plantilla_count + b.vacancy_count + b.hr_emploc_count + b.moses_hq_count AS total_count,
    CASE WHEN b.status = 'ACTIVE' AND now() > b.rollback_deadline THEN 'EXPIRED' ELSE b.status END AS status,
    rb.full_name AS rolled_back_by_name,
    b.rolled_back_at
  FROM public.system_archive_batches b
  LEFT JOIN public.users_profile up ON up.id = b.executed_by
  LEFT JOIN public.users_profile rb ON rb.id = b.rolled_back_by
  WHERE public.is_super_admin() OR COALESCE(public.get_my_role_level(), 0) >= 90
  ORDER BY b.executed_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.fn_get_archive_batch_history() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_archive_batch_history() TO authenticated;

-- -----------------------------------------------------------------------------
-- 6. HIGH: Tighten hr_emploc_write_scoped & idempotently drop vacancies_write_scoped
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS hr_emploc_write_scoped ON public.hr_emploc;

DROP POLICY IF EXISTS hr_emploc_insert_scoped ON public.hr_emploc;
CREATE POLICY hr_emploc_insert_scoped
  ON public.hr_emploc
  FOR INSERT
  TO authenticated
  WITH CHECK (
    COALESCE((select public.get_my_role_level()), 0) >= 25
    AND (
      (select public.i_have_full_access())
      OR (account = ANY((select public.get_my_allowed_accounts())::text[]))
    )
  );

DROP POLICY IF EXISTS hr_emploc_update_scoped ON public.hr_emploc;
CREATE POLICY hr_emploc_update_scoped
  ON public.hr_emploc
  FOR UPDATE
  TO authenticated
  USING (
    COALESCE((select public.get_my_role_level()), 0) >= 25
    AND (
      (select public.i_have_full_access())
      OR (account = ANY((select public.get_my_allowed_accounts())::text[]))
    )
  )
  WITH CHECK (
    COALESCE((select public.get_my_role_level()), 0) >= 25
    AND (
      (select public.i_have_full_access())
      OR (account = ANY((select public.get_my_allowed_accounts())::text[]))
    )
  );

DROP POLICY IF EXISTS hr_emploc_delete_super_admin_only ON public.hr_emploc;
CREATE POLICY hr_emploc_delete_super_admin_only
  ON public.hr_emploc
  FOR DELETE
  TO authenticated
  USING ((select public.is_super_admin()));

DROP POLICY IF EXISTS vacancies_write_scoped ON public.vacancies;

-- -----------------------------------------------------------------------------
-- 7. HARDENING: Fix search_path on legacy SECURITY DEFINER vcode helpers
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.generate_vcodes_for_request(uuid, text, text, integer) SET search_path = public;
ALTER FUNCTION public.generate_vcodes_from_request(uuid) SET search_path = public;
