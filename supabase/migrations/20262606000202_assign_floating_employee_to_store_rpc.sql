-- Migration: 20262606000202_assign_floating_employee_to_store_rpc.sql
-- Description: Create assign_floating_employee_to_store RPC enforcing Ops capability checks (OM, HRCO, ATL, TL),
--              Rule 1 (Slot Authority), Rule 7 (Floating to Active Transition), and Mobile/ADR Roving Route conflict parity.

CREATE OR REPLACE FUNCTION public.assign_floating_employee_to_store(
  p_plantilla_id uuid,
  p_target_store_id uuid,
  p_assignment_type text DEFAULT 'Stationary'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_emp                public.plantilla%ROWTYPE;
  v_store              public.stores%ROWTYPE;
  v_slot               public.plantilla_slots%ROWTYPE;
  v_vac                public.vacancies%ROWTYPE;
  v_is_roving_conflict boolean := false;
  v_active_alloc_count int := 0;
  v_cg_count           int := 0;
  v_slot_result        jsonb;
BEGIN
  -- ── 1. Authentication & Capability Guard ─────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- Allow Ops (OM, HRCO, ATL, TL via _can_act_on_plantilla) or Super Admin / Head Admin
  IF NOT (public.i_have_full_access() OR public._can_act_on_plantilla(p_plantilla_id, 'reassign')) THEN
    RAISE EXCEPTION 'forbidden: Ops or Data Team role required to assign store to floating personnel'
      USING ERRCODE = '42501';
  END IF;

  -- ── 2. Fetch Employee With Lock ──────────────────────────────────────────
  SELECT * INTO v_emp
  FROM public.plantilla
  WHERE id = p_plantilla_id
    AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla employee not found: %', p_plantilla_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Check account scope
  IF NOT public.i_have_full_access()
     AND NOT (v_emp.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: employee account out of scope'
      USING ERRCODE = '42501';
  END IF;

  -- ── 3. Fetch Target Store ────────────────────────────────────────────────
  SELECT * INTO v_store
  FROM public.stores
  WHERE id = p_target_store_id
    AND COALESCE(is_active, true) = true
    AND COALESCE(status, 'active') <> 'archived';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'target store not found or inactive: %', p_target_store_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Cross-account assignment prohibition
  IF v_store.account_id IS DISTINCT FROM v_emp.account_id THEN
    RAISE EXCEPTION 'cross-account store assignment is not permitted'
      USING ERRCODE = '22023';
  END IF;

  -- ── 4. Roving Route & Coverage Group Conflict Guard (Mobile Parity) ───────
  -- Floating deployment is strictly Stationary (Rule 7). Roving routes cannot take stationary floating personnel.
  SELECT COUNT(*) INTO v_cg_count
  FROM public.coverage_group_stores cgs
  WHERE cgs.store_id = v_store.id
    AND cgs.archived_at IS NULL;

  IF v_cg_count > 0 OR v_store.vcode ILIKE '%CG%' OR v_store.vcode ILIKE 'VCAG%' THEN
    v_is_roving_conflict := true;
  END IF;

  IF NOT v_is_roving_conflict THEN
    SELECT COUNT(*) INTO v_active_alloc_count
    FROM public.employee_store_allocations esa
    WHERE (esa.store_id = v_store.id OR LOWER(TRIM(esa.store_name)) = LOWER(TRIM(v_store.store_name)))
      AND esa.is_active = true
      AND esa.filled_hc > 0
      AND esa.filled_hc < 1.0;

    IF v_active_alloc_count > 0 THEN
      v_is_roving_conflict := true;
    END IF;
  END IF;

  IF v_is_roving_conflict THEN
    RAISE EXCEPTION 'Cannot assign stationary floating personnel to a roving coverage route store branch'
      USING ERRCODE = '22023';
  END IF;

  -- ── 5. Slot Authority: Claim Open Slot (Rule 1) ──────────────────────────
  SELECT * INTO v_slot
  FROM public.plantilla_slots
  WHERE store_id = v_store.id
    AND slot_status = 'open'
  ORDER BY slot_number ASC
  LIMIT 1
  FOR UPDATE;

  IF v_slot.id IS NOT NULL THEN
    v_slot_result := public.fn_set_slot_status(
      v_slot.id,
      'occupied',
      'REPLACEMENT',
      auth.uid(),
      'Floating employee assigned to store',
      p_plantilla_id
    );

    IF (v_slot_result->>'status') = 'blocked' THEN
      RAISE EXCEPTION 'Slot transition blocked: %', (v_slot_result->>'blocked_reason')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── 6. Transition Employee: Floating -> Active Stationary (Rule 7) ────────
  UPDATE public.plantilla
  SET
    store_id            = v_store.id,
    store_name          = v_store.store_name,
    area                = COALESCE(v_store.area_city, v_store.area_province, area),
    province_id         = COALESCE(v_store.id, province_id),
    deployment_type     = 'Stationary',
    status              = 'Active',
    vcode               = COALESCE(v_store.vcode, vcode),
    separation_status   = NULL,
    inactive_at         = NULL,
    inactive_by         = NULL,
    date_of_separation  = NULL,
    resignation_date    = NULL,
    remarks             = NULL,
    deactivation_reason = NULL,
    for_deactivation_at = NULL,
    for_deactivation_by = NULL,
    deactivated_at      = NULL,
    deactivated_by      = NULL,
    updated_at          = NOW(),
    updated_by          = auth.uid()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_emp;

  -- ── 7. Synchronize Open Vacancy (if any) ──────────────────────────────────
  SELECT * INTO v_vac
  FROM public.vacancies
  WHERE (store_id = v_store.id OR (v_store.vcode IS NOT NULL AND vcode = v_store.vcode))
    AND LOWER(status) = 'open'
  LIMIT 1;

  IF v_vac.id IS NOT NULL THEN
    UPDATE public.vacancies
    SET status = 'hired', updated_at = NOW()
    WHERE id = v_vac.id;
  END IF;

  -- ── 8. Return Confirmation Payload ───────────────────────────────────────
  RETURN jsonb_build_object(
    'success', true,
    'id', v_emp.id,
    'employee_name', v_emp.employee_name,
    'employee_no', v_emp.employee_no,
    'store_id', v_store.id,
    'store_name', v_store.store_name,
    'vcode', v_emp.vcode,
    'status', v_emp.status,
    'deployment_type', v_emp.deployment_type,
    'slot_id', v_slot.id
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.assign_floating_employee_to_store(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_floating_employee_to_store(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_floating_employee_to_store(uuid, uuid, text) TO service_role;
