-- Migration: 20262701000005_plantilla_transfer_slot_gate_and_atomic_swap.sql
-- Prompt ID: ohm#plantilla-transfer-slot-gate-and-atomic-swap
-- Description:
--   1. Seed 'TRANSFER_IN' and 'SWAP' into public.slot_reason_codes.
--   2. Surgically extend public.fn_set_slot_status to support atomic occupied->occupied
--      'SWAP' occupant exchange without firing trg_reopen_vacancy_on_slot_open.
--   3. Create public.get_transfer_eligible_stores(p_account_id, p_exclude_store_id)
--      returning only active stationary stores with genuinely available open slots
--      (Avail > 0, zero competing pipeline/hr_emploc candidates, zero pending closures).
--   4. Create public.get_swap_eligible_employees(p_plantilla_id) returning active
--      stationary swap partners within the same account at distinct stores.
--   5. Harden public.plantilla_transfer:
--      - Enforce stationary-only scope (blocks roving employees & roving stores).
--      - Enforce strict slot gate + Avail > 0 lock (no over-headcount bypass).
--      - Rebind plantilla.vcode = target store's permanent vcode (Anti-VCode Migration Lock).
--      - Preserve employee position (Option 2C) and sync claimed slot position snapshot.
--      - Release source slot (TRANSFER_OUT) and ensure/reopen source store Open Vacancy.
--      - Claim target slot (TRANSFER_IN) and mark target vacancy Filled when 0 open slots remain.
--      - Supersede employee_store_allocations preserving employee work schedule.
--   6. Create public.plantilla_swap for atomic same-account stationary employee swap:
--      - Swaps store_id, store_name, vcode, area, occupied plantilla_slots ('SWAP'),
--        employee_store_allocations, and work schedules (schedule_days, schedule_time, dayoff, rest_day)
--        while preserving each employee's position and opening zero false vacancies.
--   7. Idempotently repair any drifted Active stationary vcode/slot/allocation records
--      (including 2019-14008 Abrogar and 2019-13652 Acibo).

-- ============================================================================
-- 1. Seed slot_reason_codes for TRANSFER_IN and SWAP
-- ============================================================================
INSERT INTO public.slot_reason_codes (code, label, description, is_active, sort_order)
VALUES
  ('TRANSFER_IN', 'Transfer In',   'Active employee transferred into an open store slot.', true, 35),
  ('SWAP',        'Employee Swap', 'Two active employees exchanged stores atomically.',    true, 36)
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- 2. Surgically extend public.fn_set_slot_status with atomic SWAP transition
--    (Base: 20262606000019_slot_authority_lockdown.sql)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_set_slot_status(
  p_slot_id uuid,
  p_new_status text,
  p_reason_code text DEFAULT NULL::text,
  p_performed_by uuid DEFAULT NULL::uuid,
  p_remarks text DEFAULT NULL::text,
  p_occupant_plantilla_id uuid DEFAULT NULL::uuid
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slot           record;
  v_from_status    text;
  v_action_type    text;
  v_history_id     uuid;
  v_transition_ok  boolean := false;
  v_blocked_reason text;
BEGIN
  IF p_slot_id IS NULL THEN
    RAISE EXCEPTION 'fn_set_slot_status: p_slot_id is required';
  END IF;

  IF p_new_status NOT IN (
    'open', 'pipeline', 'hr_processing', 'occupied', 'filled', 'closed', 'hc_reduced'
  ) THEN
    RAISE EXCEPTION 'fn_set_slot_status: unknown status value ''%''', p_new_status;
  END IF;

  SELECT * INTO v_slot
  FROM public.plantilla_slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_set_slot_status: slot % not found', p_slot_id;
  END IF;

  v_from_status := v_slot.slot_status;

  -- Atomic SWAP transition: occupied/filled -> occupied with a distinct occupant
  -- Never transitions through 'open', so trg_reopen_vacancy_on_slot_open is NOT fired.
  IF v_from_status IN ('occupied', 'filled')
     AND p_new_status = 'occupied'
     AND p_reason_code = 'SWAP'
     AND p_occupant_plantilla_id IS NOT NULL
     AND p_occupant_plantilla_id IS DISTINCT FROM v_slot.current_occupant_plantilla_id THEN
    v_transition_ok := true;
    v_action_type   := 'swap';

  ELSIF v_from_status = p_new_status THEN
    RETURN jsonb_build_object(
      'status',      'no_op',
      'slot_id',     p_slot_id,
      'from_status', v_from_status,
      'to_status',   p_new_status
    );

  -- Transition matrix
  -- ohm#7k2d9f4a: terminal states may be re-opened ONLY through an explicit,
  -- named re-add / coverage-conversion workflow (reason-code gated).
  ELSIF v_from_status IN ('closed', 'hc_reduced') AND p_new_status = 'open'
     AND p_reason_code IN ('HC_READD', 'COVERAGE_STORE_REMOVED', 'COVERAGE_GROUP_DISSOLVED') THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status IN ('closed', 'hc_reduced') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      '%s is terminal under automation; re-opening a slot requires an HC re-add workflow',
      v_from_status
    );

  ELSIF v_from_status = 'open' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'pipeline';

  ELSIF v_from_status = 'open' AND p_new_status IN ('occupied', 'filled') THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := format('%s→%s (transfer-in) requires p_occupant_plantilla_id', v_from_status, p_new_status);
    ELSE
      v_transition_ok := true;
      v_action_type   := 'transfer_in';
    END IF;

  ELSIF v_from_status = 'open' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'open' AND p_new_status = 'hc_reduced' THEN
    v_transition_ok := true;
    v_action_type   := 'hc_reduced';

  ELSIF v_from_status = 'open' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'import_reserved';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'hr_processing';

  ELSIF v_from_status = 'pipeline' AND p_new_status IN ('occupied', 'filled') THEN
    v_transition_ok  := false;
    v_blocked_reason := 'pipeline→occupied is blocked: slot must pass through hr_processing first';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'hr_processing' AND p_new_status IN ('occupied', 'filled') THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := format('%s→%s requires p_occupant_plantilla_id', v_from_status, p_new_status);
    ELSE
      v_transition_ok := true;
      v_action_type   := 'occupied';
    END IF;

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'import_rejected';

  ELSIF v_from_status IN ('occupied', 'filled') AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := CASE p_reason_code
                          WHEN 'TRANSFER_OUT' THEN 'transfer_out'
                          WHEN 'BACKOUT' THEN 'backout_released'
                          WHEN 'COVERAGE_GROUP_CREATED' THEN 'employee_separated'
                          WHEN 'COVERAGE_STORE_REMOVED' THEN 'coverage_store_removed'
                          ELSE 'resigned'
                        END;

  ELSIF v_from_status IN ('occupied', 'filled') AND p_new_status IN ('pipeline', 'hr_processing') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      '%s→%s is blocked: occupant must separate first (%s→open), '
      'then the slot re-enters recruitment', v_from_status, p_new_status, v_from_status
    );

  ELSE
    v_transition_ok  := false;
    v_blocked_reason := format('%s→%s is not a supported transition', v_from_status, p_new_status);
  END IF;

  IF NOT v_transition_ok THEN
    RETURN jsonb_build_object(
      'status',         'blocked',
      'slot_id',        p_slot_id,
      'from_status',    v_from_status,
      'to_status',      p_new_status,
      'blocked_reason', v_blocked_reason
    );
  END IF;

  -- Apply transition
  UPDATE public.plantilla_slots
  SET
    slot_status                   = p_new_status,
    current_occupant_plantilla_id = CASE
      WHEN p_new_status IN ('occupied', 'filled') THEN p_occupant_plantilla_id
      WHEN p_new_status IN ('open', 'closed', 'hc_reduced') THEN NULL
      ELSE current_occupant_plantilla_id
    END,
    closed_at                     = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN now()
      ELSE closed_at
    END,
    closed_by                     = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN p_performed_by
      ELSE closed_by
    END,
    closure_reason_code           = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN p_reason_code
      ELSE closure_reason_code
    END,
    updated_at                    = now(),
    updated_by                    = p_performed_by
  WHERE id = p_slot_id;

  INSERT INTO public.slot_history (
    slot_id,
    account_id,
    action_type,
    old_value,
    new_value,
    reason_code,
    performed_by,
    remarks
  ) VALUES (
    p_slot_id,
    v_slot.account_id,
    v_action_type,
    v_from_status,
    p_new_status,
    p_reason_code,
    p_performed_by,
    p_remarks
  )
  RETURNING id INTO v_history_id;

  RETURN jsonb_build_object(
    'status',      'ok',
    'slot_id',     p_slot_id,
    'from_status', v_from_status,
    'to_status',   p_new_status,
    'action_type', v_action_type,
    'reason_code', p_reason_code,
    'history_id',  v_history_id
  );
END;
$function$;

-- ============================================================================
-- 3. Authoritative RPC: get_transfer_eligible_stores (Shared by Web & Mobile)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_transfer_eligible_stores(
  p_account_id uuid,
  p_exclude_store_id uuid DEFAULT NULL::uuid
)
 RETURNS TABLE (
   store_id uuid,
   store_name text,
   vcode text,
   account_id uuid,
   account_name text,
   group_id uuid,
   group_name text,
   area_city text,
   province text,
   area_province text,
   island_group text,
   is_active boolean,
   open_slots_count integer,
   avail_slots_count integer,
   total_slots_count integer,
   occupied_slots_count integer
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_account_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_account_id IS NULL THEN
    RETURN;
  END IF;

  SELECT a.account_name INTO v_account_name
  FROM public.accounts a
  WHERE a.id = p_account_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_account_name = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH store_slot_stats AS (
    SELECT
      ps.store_id,
      COUNT(*) FILTER (WHERE ps.slot_status = 'open' AND COALESCE(ps.is_roving, false) = false)::int AS open_cnt,
      COUNT(*) FILTER (WHERE ps.slot_status IN ('occupied', 'filled') AND COALESCE(ps.is_roving, false) = false)::int AS occ_cnt,
      COUNT(*) FILTER (WHERE ps.slot_status NOT IN ('closed', 'hc_reduced') AND COALESCE(ps.is_roving, false) = false)::int AS total_cnt
    FROM public.plantilla_slots ps
    WHERE ps.account_id = p_account_id
      AND ps.store_id IS NOT NULL
    GROUP BY ps.store_id
  ),
  applicant_stats AS (
    SELECT
      a.vacancy_vcode AS vcode,
      COUNT(*)::int AS active_app_cnt
    FROM public.applicants a
    WHERE COALESCE(a.is_archived, false) = false
      AND a.vacancy_vcode IS NOT NULL
      AND replace(replace(lower(btrim(COALESCE(a.status, ''))), ' ', '_'), '-', '_') NOT IN (
        'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops',
        'withdrew', 'withdrawn', 'hired', 'confirmed_onboard'
      )
    GROUP BY a.vacancy_vcode
  ),
  hr_emploc_stats AS (
    SELECT
      h.store_id,
      h.vcode,
      COUNT(*)::int AS active_hr_cnt
    FROM public.hr_emploc h
    WHERE h.deleted_at IS NULL
      AND h.account_id = p_account_id
      AND replace(replace(lower(btrim(COALESCE(h.status, ''))), ' ', '_'), '-', '_') NOT IN (
        'moved_to_plantilla', 'backout', 'cancelled', 'rejected', 'archived', 'separated', 'inactive'
      )
    GROUP BY h.store_id, h.vcode
  )
  SELECT
    s.id AS store_id,
    s.store_name,
    s.vcode,
    s.account_id,
    acc.account_name,
    s.group_id,
    grp.group_name,
    s.area_city,
    s.province,
    s.area_province,
    s.island_group,
    COALESCE(s.is_active, true) AS is_active,
    COALESCE(ss.open_cnt, 0) AS open_slots_count,
    GREATEST(
      0,
      COALESCE(ss.open_cnt, 0)
      - COALESCE(app.active_app_cnt, 0)
      - COALESCE((
          SELECT SUM(he.active_hr_cnt)::int
          FROM hr_emploc_stats he
          WHERE he.store_id = s.id
             OR (s.vcode IS NOT NULL AND he.vcode = s.vcode)
        ), 0)
    )::int AS avail_slots_count,
    COALESCE(ss.total_cnt, 0) AS total_slots_count,
    COALESCE(ss.occ_cnt, 0) AS occupied_slots_count
  FROM public.stores s
  JOIN public.accounts acc ON acc.id = s.account_id
  LEFT JOIN public.groups grp ON grp.id = s.group_id
  JOIN store_slot_stats ss ON ss.store_id = s.id
  LEFT JOIN applicant_stats app ON s.vcode IS NOT NULL AND app.vcode = s.vcode
  WHERE s.account_id = p_account_id
    AND COALESCE(s.is_active, true) = true
    AND COALESCE(s.status, 'active') <> 'archived'
    AND COALESCE(s.is_archived, false) = false
    AND (p_exclude_store_id IS NULL OR s.id <> p_exclude_store_id)
    -- Stationary-only guard: exclude roving coverage group stores
    AND NOT EXISTS (
      SELECT 1 FROM public.coverage_group_stores cgs
      WHERE cgs.store_id = s.id AND cgs.archived_at IS NULL
    )
    AND COALESCE(s.vcode, '') NOT ILIKE '%CG%'
    AND COALESCE(s.vcode, '') NOT ILIKE 'VCAG%'
    AND NOT EXISTS (
      SELECT 1 FROM public.employee_store_allocations esa
      WHERE esa.store_id = s.id
        AND esa.is_active = true
        AND esa.filled_hc > 0
        AND esa.filled_hc < 1.0
    )
    -- Pending closure lock
    AND NOT EXISTS (
      SELECT 1 FROM public.vacancies v
      WHERE (v.store_id = s.id OR (s.vcode IS NOT NULL AND v.vcode = s.vcode))
        AND COALESCE(v.is_archived, false) = false
        AND (
          COALESCE(v.has_pending_closure, false) = true
          OR LOWER(COALESCE(v.closure_request_status, '')) = 'pending'
          OR LOWER(COALESCE(v.status, '')) IN ('closure', 'for_closure')
        )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.vacancy_closure_requests vcr
      WHERE s.vcode IS NOT NULL
        AND vcr.vacancy_vcode = s.vcode
        AND LOWER(COALESCE(vcr.status, '')) = 'pending'
    )
    -- Must have open slots AND zero-applicant Avail > 0
    AND COALESCE(ss.open_cnt, 0) > 0
    AND GREATEST(
      0,
      COALESCE(ss.open_cnt, 0)
      - COALESCE(app.active_app_cnt, 0)
      - COALESCE((
          SELECT SUM(he.active_hr_cnt)::int
          FROM hr_emploc_stats he
          WHERE he.store_id = s.id
             OR (s.vcode IS NOT NULL AND he.vcode = s.vcode)
        ), 0)
    ) > 0
  ORDER BY s.store_name ASC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_transfer_eligible_stores(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_transfer_eligible_stores(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_transfer_eligible_stores(uuid, uuid) TO service_role;

-- ============================================================================
-- 4. Authoritative RPC: get_swap_eligible_employees (Shared by Web & Mobile)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_swap_eligible_employees(
  p_plantilla_id uuid
)
 RETURNS TABLE (
   plantilla_id uuid,
   employee_no text,
   employee_name text,
   "position" text,
   position_id uuid,
   store_id uuid,
   store_name text,
   vcode text,
   area_city text,
   province text,
   schedule_days text,
   schedule_time text,
   dayoff text
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_src public.plantilla%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_src
  FROM public.plantilla p
  WHERE p.id = p_plantilla_id
    AND COALESCE(p.is_deleted, false) = false;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_src.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope' USING ERRCODE = '42501';
  END IF;

  -- If source employee is roving or not Active stationary, return empty
  IF LOWER(COALESCE(v_src.status, '')) <> 'active'
     OR LOWER(COALESCE(v_src.deployment_type, 'stationary')) = 'roving'
     OR v_src.coverage_group_id IS NOT NULL
     OR v_src.store_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id AS plantilla_id,
    p.employee_no,
    p.employee_name,
    COALESCE(pos.position_name, p."position") AS "position",
    p.position_id,
    s.id AS store_id,
    s.store_name,
    COALESCE(s.vcode, p.vcode) AS vcode,
    s.area_city,
    COALESCE(s.province, s.area_province) AS province,
    COALESCE(esa_top.schedule_days, p.schedule_days) AS schedule_days,
    COALESCE(esa_top.schedule_time, p.schedule_time) AS schedule_time,
    COALESCE(p.dayoff, p.rest_day) AS dayoff
  FROM public.plantilla p
  JOIN public.stores s ON s.id = p.store_id
  LEFT JOIN public.positions pos ON pos.id = p.position_id
  LEFT JOIN LATERAL (
    SELECT e.schedule_days, e.schedule_time
    FROM public.employee_store_allocations e
    WHERE e.plantilla_id = p.id
      AND e.is_active = true
    ORDER BY e.created_at DESC
    LIMIT 1
  ) esa_top ON true
  WHERE p.account_id = v_src.account_id
    AND p.id <> v_src.id
    AND p.store_id IS NOT NULL
    AND p.store_id <> v_src.store_id
    AND p.status = 'Active'
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
    AND COALESCE(p.is_pool_employee, false) = false
    -- Stationary-only guard on candidate employee
    AND LOWER(COALESCE(p.deployment_type, 'stationary')) <> 'roving'
    AND p.coverage_group_id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.employee_store_allocations e_rov
      WHERE e_rov.plantilla_id = p.id
        AND e_rov.is_active = true
        AND (e_rov.filled_hc < 1.0 OR e_rov.active_store_count > 1)
    )
    -- Stationary-only guard on candidate store
    AND COALESCE(s.is_active, true) = true
    AND COALESCE(s.status, 'active') <> 'archived'
    AND COALESCE(s.is_archived, false) = false
    AND NOT EXISTS (
      SELECT 1 FROM public.coverage_group_stores cgs
      WHERE cgs.store_id = s.id AND cgs.archived_at IS NULL
    )
    AND COALESCE(s.vcode, '') NOT ILIKE '%CG%'
    AND COALESCE(s.vcode, '') NOT ILIKE 'VCAG%'
  ORDER BY p.employee_name ASC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_swap_eligible_employees(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_swap_eligible_employees(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_swap_eligible_employees(uuid) TO service_role;

-- ============================================================================
-- 5. Hardened public.plantilla_transfer (Slot-Gated + VCode Rebind + Source Vacancy)
--    Drop old 4-param overload so 3/4/5-param calls resolve unambiguously.
-- ============================================================================
DROP FUNCTION IF EXISTS public.plantilla_transfer(uuid, uuid, uuid, text);

CREATE OR REPLACE FUNCTION public.plantilla_transfer(
  p_plantilla_id uuid,
  p_target_store_id uuid,
  p_target_position_id uuid DEFAULT NULL::uuid,
  p_remarks text DEFAULT NULL::text,
  p_effective_date date DEFAULT CURRENT_DATE
)
 RETURNS public.plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row                 public.plantilla;
  v_old_store           public.stores;
  v_store               public.stores;
  v_source_slot         public.plantilla_slots;
  v_target_slot         public.plantilla_slots;
  v_slot_res            jsonb;
  v_actor               uuid;
  v_actor_name          text;
  v_eff_date            date := COALESCE(p_effective_date, CURRENT_DATE);
  v_position_id_eff     uuid;
  v_position_name_eff   text;
  v_open_slots          int := 0;
  v_active_applicants   int := 0;
  v_active_hr_emploc    int := 0;
  v_old_store_total_hc  int := 1;
  v_old_vcode           text;
  v_old_vac_id          uuid;
  v_hrco_user_id        uuid;
  v_hrco_name           text;
  v_group_id            uuid;
  v_group_name          text;
  v_sched_days          text;
  v_sched_time          text;
  v_is_roving_emp       boolean := false;
  v_is_roving_store     boolean := false;
BEGIN
  -- ── 1. Auth & Capability Guard ────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_have_full_access() OR public._can_act_on_plantilla(p_plantilla_id, 'reassign')) THEN
    RAISE EXCEPTION 'forbidden: Ops role required for plantilla transfer' USING ERRCODE = '42501';
  END IF;

  -- Safe users_profile actor resolution (Rule #2)
  SELECT up.id, COALESCE(up.full_name, NULLIF(TRIM(COALESCE(up.first_name,'') || ' ' || COALESCE(up.last_name,'')), ''))
  INTO v_actor, v_actor_name
  FROM public.users_profile up
  WHERE up.id = COALESCE(public.get_current_profile_id(), auth.uid())
  LIMIT 1;

  -- ── 2. Lock Employee Row & Validate Active Stationary ─────────────────────
  SELECT * INTO v_row
  FROM public.plantilla
  WHERE id = p_plantilla_id
    AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope' USING ERRCODE = '42501';
  END IF;

  IF LOWER(COALESCE(v_row.status, '')) <> 'active' THEN
    RAISE EXCEPTION 'Only Active employees can be transferred (current status: %)', v_row.status
      USING ERRCODE = '22023';
  END IF;

  IF LOWER(COALESCE(v_row.deployment_type, 'stationary')) = 'roving'
     OR v_row.coverage_group_id IS NOT NULL THEN
    v_is_roving_emp := true;
  ELSIF EXISTS (
    SELECT 1 FROM public.employee_store_allocations esa
    WHERE esa.plantilla_id = p_plantilla_id
      AND esa.is_active = true
      AND (esa.filled_hc < 1.0 OR esa.active_store_count > 1)
  ) THEN
    v_is_roving_emp := true;
  END IF;

  IF v_is_roving_emp THEN
    RAISE EXCEPTION 'Roving employees cannot be transferred individually. Use Coverage Group Management instead.'
      USING ERRCODE = '22023';
  END IF;

  -- ── 3. Validate Target Store (Active, Same Account, Distinct, Non-Roving) ─
  SELECT * INTO v_store
  FROM public.stores
  WHERE id = p_target_store_id
    AND COALESCE(is_active, true) = true
    AND COALESCE(status, 'active') <> 'archived'
    AND COALESCE(is_archived, false) = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target store not found or inactive: %', p_target_store_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_store.account_id IS DISTINCT FROM v_row.account_id THEN
    RAISE EXCEPTION 'Cross-account transfer is not allowed' USING ERRCODE = '22023';
  END IF;

  IF v_store.id = v_row.store_id THEN
    RAISE EXCEPTION 'Employee is already assigned to this store' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.coverage_group_stores cgs
    WHERE cgs.store_id = v_store.id AND cgs.archived_at IS NULL
  ) OR COALESCE(v_store.vcode, '') ILIKE '%CG%'
    OR COALESCE(v_store.vcode, '') ILIKE 'VCAG%'
    OR EXISTS (
      SELECT 1 FROM public.employee_store_allocations esa
      WHERE esa.store_id = v_store.id
        AND esa.is_active = true
        AND esa.filled_hc > 0
        AND esa.filled_hc < 1.0
    ) THEN
    v_is_roving_store := true;
  END IF;

  IF v_is_roving_store THEN
    RAISE EXCEPTION 'Cannot transfer a stationary employee into a roving coverage group store.'
      USING ERRCODE = '22023';
  END IF;

  -- ── 4. Strict Slot Gate & Zero-Applicant Avail Lock (ADR Rule 3A) ─────────
  IF EXISTS (
    SELECT 1 FROM public.vacancies v
    WHERE (v.store_id = v_store.id OR (v_store.vcode IS NOT NULL AND v.vcode = v_store.vcode))
      AND COALESCE(v.is_archived, false) = false
      AND (
        COALESCE(v.has_pending_closure, false) = true
        OR LOWER(COALESCE(v.closure_request_status, '')) = 'pending'
        OR LOWER(COALESCE(v.status, '')) IN ('closure', 'for_closure')
      )
  ) OR EXISTS (
    SELECT 1 FROM public.vacancy_closure_requests vcr
    WHERE v_store.vcode IS NOT NULL
      AND vcr.vacancy_vcode = v_store.vcode
      AND LOWER(COALESCE(vcr.status, '')) = 'pending'
  ) THEN
    RAISE EXCEPTION 'Target store has a pending vacancy closure request and cannot accept transfers.'
      USING ERRCODE = '22023';
  END IF;

  SELECT COUNT(*)::int INTO v_open_slots
  FROM public.plantilla_slots ps
  WHERE ps.store_id = v_store.id
    AND ps.slot_status = 'open'
    AND COALESCE(ps.is_roving, false) = false;

  IF v_open_slots <= 0 THEN
    RAISE EXCEPTION 'Transfer blocked: target store "%" has no available open slots. Use Swap if exchanging two occupied stores.', v_store.store_name
      USING ERRCODE = '22023';
  END IF;

  IF v_store.vcode IS NOT NULL THEN
    SELECT COUNT(*)::int INTO v_active_applicants
    FROM public.applicants a
    WHERE a.vacancy_vcode = v_store.vcode
      AND COALESCE(a.is_archived, false) = false
      AND replace(replace(lower(btrim(COALESCE(a.status, ''))), ' ', '_'), '-', '_') NOT IN (
        'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops',
        'withdrew', 'withdrawn', 'hired', 'confirmed_onboard'
      );
  END IF;

  SELECT COUNT(*)::int INTO v_active_hr_emploc
  FROM public.hr_emploc h
  WHERE h.deleted_at IS NULL
    AND h.account_id = v_store.account_id
    AND (h.store_id = v_store.id OR (v_store.vcode IS NOT NULL AND h.vcode = v_store.vcode))
    AND replace(replace(lower(btrim(COALESCE(h.status, ''))), ' ', '_'), '-', '_') NOT IN (
      'moved_to_plantilla', 'backout', 'cancelled', 'rejected', 'archived', 'separated', 'inactive'
    );

  IF (v_open_slots - v_active_applicants - v_active_hr_emploc) <= 0 THEN
    RAISE EXCEPTION 'Transfer blocked: open slot at "%" is currently reserved by an active pipeline or onboarding candidate.', v_store.store_name
      USING ERRCODE = '22023';
  END IF;

  -- Lock the claimable open slot at target store
  SELECT * INTO v_target_slot
  FROM public.plantilla_slots ps
  WHERE ps.store_id = v_store.id
    AND ps.slot_status = 'open'
    AND COALESCE(ps.is_roving, false) = false
  ORDER BY ps.slot_ordinal ASC NULLS LAST, ps.created_at ASC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer blocked: no open slot could be locked at "%".', v_store.store_name
      USING ERRCODE = '22023';
  END IF;

  -- Lock source store & employee's current occupied slot
  IF v_row.store_id IS NOT NULL THEN
    SELECT * INTO v_old_store FROM public.stores WHERE id = v_row.store_id;
  END IF;

  SELECT * INTO v_source_slot
  FROM public.plantilla_slots ps
  WHERE ps.current_occupant_plantilla_id = p_plantilla_id
    AND ps.slot_status IN ('occupied', 'filled')
    AND COALESCE(ps.is_roving, false) = false
  ORDER BY (ps.store_id = v_row.store_id) DESC, ps.slot_ordinal ASC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  -- ── 5. Slot Authority Transitions (Core Rule 1) ───────────────────────────
  -- Release source slot -> open (TRANSFER_OUT)
  IF v_source_slot.id IS NOT NULL THEN
    v_slot_res := public.fn_set_slot_status(
      v_source_slot.id,
      'open',
      'TRANSFER_OUT',
      v_actor,
      COALESCE(p_remarks, format('Transferred to %s (%s)', v_store.store_name, COALESCE(v_store.vcode, 'N/A'))),
      NULL
    );
    IF (v_slot_res->>'status') = 'blocked' THEN
      RAISE EXCEPTION 'Source slot release blocked: %', (v_slot_res->>'blocked_reason')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- Claim target slot -> occupied (TRANSFER_IN)
  v_slot_res := public.fn_set_slot_status(
    v_target_slot.id,
    'occupied',
    'TRANSFER_IN',
    v_actor,
    COALESCE(p_remarks, format('Transferred from %s (%s)', COALESCE(v_old_store.store_name, v_row.store_name, 'Unknown'), COALESCE(v_old_store.vcode, v_row.vcode, 'N/A'))),
    p_plantilla_id
  );
  IF (v_slot_res->>'status') = 'blocked' THEN
    RAISE EXCEPTION 'Target slot claim blocked: %', (v_slot_res->>'blocked_reason')
      USING ERRCODE = '22023';
  END IF;

  -- ── 6. Position Retention (Option 2C) & Target Slot Position Sync ─────────
  v_position_id_eff := COALESCE(p_target_position_id, v_row.position_id);
  IF v_position_id_eff IS NOT NULL THEN
    SELECT pos.position_name INTO v_position_name_eff
    FROM public.positions pos
    WHERE pos.id = v_position_id_eff;
  END IF;
  v_position_name_eff := COALESCE(v_position_name_eff, v_row."position");

  IF v_position_name_eff IS NOT NULL AND v_position_name_eff IS DISTINCT FROM v_target_slot."position" THEN
    UPDATE public.plantilla_slots
    SET "position" = v_position_name_eff,
        updated_at = now(),
        updated_by = v_actor
    WHERE id = v_target_slot.id;
  END IF;

  -- ── 7. Capture Schedule & Supersede employee_store_allocations ────────────
  SELECT esa.schedule_days, esa.schedule_time
  INTO v_sched_days, v_sched_time
  FROM public.employee_store_allocations esa
  WHERE esa.plantilla_id = p_plantilla_id
    AND esa.is_active = true
  ORDER BY esa.created_at DESC
  LIMIT 1;

  v_sched_days := COALESCE(v_sched_days, v_row.schedule_days);
  v_sched_time := COALESCE(v_sched_time, v_row.schedule_time);

  UPDATE public.employee_store_allocations
  SET is_active     = false,
      effective_end = v_eff_date
  WHERE plantilla_id = p_plantilla_id
    AND is_active = true;

  INSERT INTO public.employee_store_allocations (
    plantilla_id,
    employee_no,
    account_id,
    group_id,
    store_id,
    vcode,
    store_name,
    filled_hc,
    active_store_count,
    effective_start,
    is_active,
    schedule_days,
    schedule_time,
    created_by
  ) VALUES (
    p_plantilla_id,
    COALESCE(v_row.employee_no, ''),
    v_store.account_id,
    v_store.group_id,
    v_store.id,
    v_store.vcode,
    v_store.store_name,
    1.0000,
    1,
    v_eff_date,
    true,
    v_sched_days,
    v_sched_time,
    v_actor
  );

  -- ── 8. Update public.plantilla (VCode Rebind Lock!) ───────────────────────
  UPDATE public.plantilla
  SET store_id                  = v_store.id,
      store_name                = v_store.store_name,
      vcode                     = COALESCE(v_store.vcode, vcode),
      area                      = COALESCE(v_store.area_city, v_store.area_province, area),
      transferred_from_store_id = v_row.store_id,
      last_transfer_at          = now(),
      last_transfer_by          = auth.uid(),
      position_id               = v_position_id_eff,
      "position"                = COALESCE(v_position_name_eff, "position"),
      over_headcount            = false,
      remarks                   = COALESCE(p_remarks, remarks),
      updated_by                = auth.uid(),
      updated_at                = now()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  -- ── 9. Ensure Source Store Enters Open Vacancy ────────────────────────────
  v_old_vcode := COALESCE(v_old_store.vcode, v_source_slot.legacy_vcode);

  IF v_old_store.id IS NOT NULL AND v_old_vcode IS NOT NULL THEN
    SELECT GREATEST(COUNT(*)::int, 1) INTO v_old_store_total_hc
    FROM public.plantilla_slots ps
    WHERE ps.store_id = v_old_store.id
      AND ps.slot_status NOT IN ('closed', 'hc_reduced')
      AND COALESCE(ps.is_roving, false) = false;

    SELECT a.group_id, g.group_name, a.hrco_user_id
    INTO v_group_id, v_group_name, v_hrco_user_id
    FROM public.accounts a
    LEFT JOIN public.groups g ON g.id = COALESCE(v_old_store.group_id, a.group_id)
    WHERE a.id = v_old_store.account_id;

    v_hrco_user_id := COALESCE(v_old_store.hrco_user_id, v_hrco_user_id);
    IF v_hrco_user_id IS NOT NULL THEN
      SELECT full_name INTO v_hrco_name FROM public.users_profile WHERE id = v_hrco_user_id;
    END IF;

    SELECT v.id INTO v_old_vac_id
    FROM public.vacancies v
    WHERE v.vcode = v_old_vcode
    LIMIT 1;

    IF v_old_vac_id IS NOT NULL THEN
      UPDATE public.vacancies
      SET status               = 'Open',
          is_archived          = false,
          archived_at          = NULL,
          archived_by          = NULL,
          vacant_date          = v_eff_date,
          vacancy_type         = 'Replacement',
          required_headcount   = GREATEST(COALESCE(required_headcount, 1), v_old_store_total_hc),
          triggered_by_user_id = COALESCE(v_actor, triggered_by_user_id),
          triggered_by_name    = COALESCE(v_actor_name, triggered_by_name),
          updated_at           = now(),
          updated_by           = COALESCE(v_actor, updated_by)
      WHERE id = v_old_vac_id;
    ELSE
      INSERT INTO public.vacancies (
        vcode, account, "position", status,
        account_id, store_id, position_id, group_id,
        area_name, store_name, vacant_date,
        required_headcount, source_plantilla_id,
        vacancy_type, employment_type, urgency_level,
        triggered_by_user_id, triggered_by_name,
        hrco_user_id, hrco_name,
        source, area_city, province,
        chain, chain_id,
        created_by, updated_by
      ) VALUES (
        v_old_vcode,
        v_row.account,
        COALESCE(v_source_slot."position", v_position_name_eff, 'Merchandiser'),
        'Open',
        v_old_store.account_id,
        v_old_store.id,
        v_position_id_eff,
        COALESCE(v_old_store.group_id, v_group_id),
        COALESCE(v_old_store.area_province, v_old_store.province, v_old_store.area_city),
        v_old_store.store_name,
        v_eff_date,
        v_old_store_total_hc,
        p_plantilla_id,
        'Replacement',
        'Stationary',
        'Medium',
        v_actor,
        v_actor_name,
        v_hrco_user_id,
        v_hrco_name,
        'plantilla',
        v_old_store.area_city,
        COALESCE(v_old_store.province, v_old_store.area_province),
        v_group_name,
        COALESCE(v_old_store.group_id, v_group_id),
        v_actor,
        v_actor
      );
    END IF;
  END IF;

  -- ── 10. Sync Target Store Vacancy Status to 'Filled' if 0 open slots left ─
  IF NOT EXISTS (
    SELECT 1 FROM public.plantilla_slots ps
    WHERE ps.store_id = v_store.id
      AND ps.slot_status = 'open'
      AND COALESCE(ps.is_roving, false) = false
  ) THEN
    UPDATE public.vacancies
    SET status     = 'Filled',
        updated_at = now(),
        updated_by = COALESCE(v_actor, updated_by)
    WHERE (store_id = v_store.id OR (v_store.vcode IS NOT NULL AND vcode = v_store.vcode))
      AND LOWER(COALESCE(status, '')) = 'open'
      AND COALESCE(is_archived, false) = false;
  END IF;

  RETURN v_row;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.plantilla_transfer(uuid, uuid, uuid, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.plantilla_transfer(uuid, uuid, uuid, text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.plantilla_transfer(uuid, uuid, uuid, text, date) TO service_role;

-- ============================================================================
-- 6. New Atomic RPC: public.plantilla_swap (Shared by Web & Mobile)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.plantilla_swap(
  p_plantilla_id_a uuid,
  p_plantilla_id_b uuid,
  p_remarks text DEFAULT NULL::text,
  p_effective_date date DEFAULT CURRENT_DATE
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_a             public.plantilla;
  v_b             public.plantilla;
  v_store_a       public.stores;
  v_store_b       public.stores;
  v_slot_a        public.plantilla_slots;
  v_slot_b        public.plantilla_slots;
  v_slot_res      jsonb;
  v_actor         uuid;
  v_eff_date      date := COALESCE(p_effective_date, CURRENT_DATE);
  v_sched_days_a  text;
  v_sched_time_a  text;
  v_dayoff_a      text;
  v_rest_day_a    text;
  v_sched_days_b  text;
  v_sched_time_b  text;
  v_dayoff_b      text;
  v_rest_day_b    text;
  v_first_id      uuid;
  v_second_id     uuid;
BEGIN
  -- ── 1. Auth & Capability Guard ────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_plantilla_id_a IS NULL OR p_plantilla_id_b IS NULL THEN
    RAISE EXCEPTION 'Both employees must be specified for a store swap.' USING ERRCODE = '22023';
  END IF;

  IF p_plantilla_id_a = p_plantilla_id_b THEN
    RAISE EXCEPTION 'Cannot swap an employee with themselves.' USING ERRCODE = '22023';
  END IF;

  IF NOT (
    public.i_have_full_access()
    OR (
      public._can_act_on_plantilla(p_plantilla_id_a, 'reassign')
      AND public._can_act_on_plantilla(p_plantilla_id_b, 'reassign')
    )
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops role required for plantilla swap' USING ERRCODE = '42501';
  END IF;

  SELECT up.id INTO v_actor
  FROM public.users_profile up
  WHERE up.id = COALESCE(public.get_current_profile_id(), auth.uid())
  LIMIT 1;

  -- ── 2. Deadlock-Safe Locking of Both Plantilla Rows ───────────────────────
  IF p_plantilla_id_a::text < p_plantilla_id_b::text THEN
    v_first_id  := p_plantilla_id_a;
    v_second_id := p_plantilla_id_b;
  ELSE
    v_first_id  := p_plantilla_id_b;
    v_second_id := p_plantilla_id_a;
  END IF;

  PERFORM 1 FROM public.plantilla WHERE id = v_first_id FOR UPDATE;
  PERFORM 1 FROM public.plantilla WHERE id = v_second_id FOR UPDATE;

  SELECT * INTO v_a FROM public.plantilla WHERE id = p_plantilla_id_a AND COALESCE(is_deleted, false) = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source employee not found: %', p_plantilla_id_a USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_b FROM public.plantilla WHERE id = p_plantilla_id_b AND COALESCE(is_deleted, false) = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target swap employee not found: %', p_plantilla_id_b USING ERRCODE = 'P0002';
  END IF;

  -- Scope & Same-Account check
  IF NOT public.i_have_full_access()
     AND NOT (
       v_a.account = ANY(public.get_my_allowed_accounts())
       AND v_b.account = ANY(public.get_my_allowed_accounts())
     ) THEN
    RAISE EXCEPTION 'forbidden: account out of scope' USING ERRCODE = '42501';
  END IF;

  IF v_a.account_id IS DISTINCT FROM v_b.account_id THEN
    RAISE EXCEPTION 'Cross-account employee swap is not allowed.' USING ERRCODE = '22023';
  END IF;

  -- Active-only check
  IF LOWER(COALESCE(v_a.status, '')) <> 'active' OR LOWER(COALESCE(v_b.status, '')) <> 'active' THEN
    RAISE EXCEPTION 'Both employees must be Active to execute a store swap.' USING ERRCODE = '22023';
  END IF;

  -- Distinct assigned stores check
  IF v_a.store_id IS NULL OR v_b.store_id IS NULL THEN
    RAISE EXCEPTION 'Both employees must have an assigned store to swap.' USING ERRCODE = '22023';
  END IF;

  IF v_a.store_id = v_b.store_id THEN
    RAISE EXCEPTION 'Both employees are already assigned to the same store.' USING ERRCODE = '22023';
  END IF;

  -- ── 3. Stationary-Only Guards (Option 1A) ─────────────────────────────────
  IF LOWER(COALESCE(v_a.deployment_type, 'stationary')) = 'roving'
     OR v_a.coverage_group_id IS NOT NULL
     OR LOWER(COALESCE(v_b.deployment_type, 'stationary')) = 'roving'
     OR v_b.coverage_group_id IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM public.employee_store_allocations esa
       WHERE esa.plantilla_id IN (v_a.id, v_b.id)
         AND esa.is_active = true
         AND (esa.filled_hc < 1.0 OR esa.active_store_count > 1)
     ) THEN
    RAISE EXCEPTION 'Roving employees cannot use stationary store swap. Use Coverage Group Management instead.'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_store_a FROM public.stores WHERE id = v_a.store_id AND COALESCE(is_active, true) = true AND COALESCE(status, 'active') <> 'archived' AND COALESCE(is_archived, false) = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Source store is inactive or not found.' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_store_b FROM public.stores WHERE id = v_b.store_id AND COALESCE(is_active, true) = true AND COALESCE(status, 'active') <> 'archived' AND COALESCE(is_archived, false) = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target store is inactive or not found.' USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.coverage_group_stores cgs
    WHERE cgs.store_id IN (v_store_a.id, v_store_b.id) AND cgs.archived_at IS NULL
  ) OR COALESCE(v_store_a.vcode, '') ILIKE '%CG%' OR COALESCE(v_store_a.vcode, '') ILIKE 'VCAG%'
    OR COALESCE(v_store_b.vcode, '') ILIKE '%CG%' OR COALESCE(v_store_b.vcode, '') ILIKE 'VCAG%' THEN
    RAISE EXCEPTION 'Stores belonging to a roving coverage group cannot participate in stationary swap.'
      USING ERRCODE = '22023';
  END IF;

  -- ── 4. Lock Occupied Slots & Exchange Occupants via fn_set_slot_status ────
  SELECT * INTO v_slot_a
  FROM public.plantilla_slots ps
  WHERE ps.current_occupant_plantilla_id = v_a.id
    AND ps.slot_status IN ('occupied', 'filled')
    AND COALESCE(ps.is_roving, false) = false
  ORDER BY (ps.store_id = v_store_a.id) DESC, ps.slot_ordinal ASC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  SELECT * INTO v_slot_b
  FROM public.plantilla_slots ps
  WHERE ps.current_occupant_plantilla_id = v_b.id
    AND ps.slot_status IN ('occupied', 'filled')
    AND COALESCE(ps.is_roving, false) = false
  ORDER BY (ps.store_id = v_store_b.id) DESC, ps.slot_ordinal ASC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  -- Swap Slot A occupant -> Employee B (no open transition, zero false vacancy!)
  IF v_slot_a.id IS NOT NULL THEN
    v_slot_res := public.fn_set_slot_status(
      v_slot_a.id,
      'occupied',
      'SWAP',
      v_actor,
      COALESCE(p_remarks, format('Swapped %s <-> %s', v_a.employee_name, v_b.employee_name)),
      v_b.id
    );
    IF (v_slot_res->>'status') = 'blocked' THEN
      RAISE EXCEPTION 'Slot swap blocked on %: %', v_store_a.store_name, (v_slot_res->>'blocked_reason')
        USING ERRCODE = '22023';
    END IF;
    -- Align slot position snapshot to new occupant's position (Option 2C)
    IF v_b."position" IS NOT NULL AND v_b."position" IS DISTINCT FROM v_slot_a."position" THEN
      UPDATE public.plantilla_slots
      SET "position" = v_b."position", updated_at = now(), updated_by = v_actor
      WHERE id = v_slot_a.id;
    END IF;
  END IF;

  -- Swap Slot B occupant -> Employee A
  IF v_slot_b.id IS NOT NULL THEN
    v_slot_res := public.fn_set_slot_status(
      v_slot_b.id,
      'occupied',
      'SWAP',
      v_actor,
      COALESCE(p_remarks, format('Swapped %s <-> %s', v_a.employee_name, v_b.employee_name)),
      v_a.id
    );
    IF (v_slot_res->>'status') = 'blocked' THEN
      RAISE EXCEPTION 'Slot swap blocked on %: %', v_store_b.store_name, (v_slot_res->>'blocked_reason')
        USING ERRCODE = '22023';
    END IF;
    IF v_a."position" IS NOT NULL AND v_a."position" IS DISTINCT FROM v_slot_b."position" THEN
      UPDATE public.plantilla_slots
      SET "position" = v_a."position", updated_at = now(), updated_by = v_actor
      WHERE id = v_slot_b.id;
    END IF;
  END IF;

  -- ── 5. Capture Work Schedules for Swap (Option 4B) ────────────────────────
  SELECT esa.schedule_days, esa.schedule_time INTO v_sched_days_a, v_sched_time_a
  FROM public.employee_store_allocations esa
  WHERE esa.plantilla_id = v_a.id AND esa.is_active = true
  ORDER BY esa.created_at DESC LIMIT 1;

  v_sched_days_a := COALESCE(v_sched_days_a, v_a.schedule_days);
  v_sched_time_a := COALESCE(v_sched_time_a, v_a.schedule_time);
  v_dayoff_a     := v_a.dayoff;
  v_rest_day_a   := v_a.rest_day;

  SELECT esa.schedule_days, esa.schedule_time INTO v_sched_days_b, v_sched_time_b
  FROM public.employee_store_allocations esa
  WHERE esa.plantilla_id = v_b.id AND esa.is_active = true
  ORDER BY esa.created_at DESC LIMIT 1;

  v_sched_days_b := COALESCE(v_sched_days_b, v_b.schedule_days);
  v_sched_time_b := COALESCE(v_sched_time_b, v_b.schedule_time);
  v_dayoff_b     := v_b.dayoff;
  v_rest_day_b   := v_b.rest_day;

  -- ── 6. Update Both Plantilla Rows (Store + VCode + Schedule Swap; Keep Position) ──
  UPDATE public.plantilla
  SET store_id                  = v_store_b.id,
      store_name                = v_store_b.store_name,
      vcode                     = COALESCE(v_store_b.vcode, vcode),
      area                      = COALESCE(v_store_b.area_city, v_store_b.area_province, area),
      transferred_from_store_id = v_store_a.id,
      last_transfer_at          = now(),
      last_transfer_by          = auth.uid(),
      schedule_days             = v_sched_days_b,
      schedule_time             = v_sched_time_b,
      dayoff                    = v_dayoff_b,
      rest_day                  = v_rest_day_b,
      over_headcount            = false,
      remarks                   = COALESCE(p_remarks, remarks),
      updated_by                = auth.uid(),
      updated_at                = now()
  WHERE id = v_a.id;

  UPDATE public.plantilla
  SET store_id                  = v_store_a.id,
      store_name                = v_store_a.store_name,
      vcode                     = COALESCE(v_store_a.vcode, vcode),
      area                      = COALESCE(v_store_a.area_city, v_store_a.area_province, area),
      transferred_from_store_id = v_store_b.id,
      last_transfer_at          = now(),
      last_transfer_by          = auth.uid(),
      schedule_days             = v_sched_days_a,
      schedule_time             = v_sched_time_a,
      dayoff                    = v_dayoff_a,
      rest_day                  = v_rest_day_a,
      over_headcount            = false,
      remarks                   = COALESCE(p_remarks, remarks),
      updated_by                = auth.uid(),
      updated_at                = now()
  WHERE id = v_b.id;

  -- ── 7. Supersede employee_store_allocations for Both Employees ────────────
  UPDATE public.employee_store_allocations
  SET is_active     = false,
      effective_end = v_eff_date
  WHERE plantilla_id IN (v_a.id, v_b.id)
    AND is_active = true;

  INSERT INTO public.employee_store_allocations (
    plantilla_id, employee_no, account_id, group_id,
    store_id, vcode, store_name,
    filled_hc, active_store_count, effective_start, is_active,
    schedule_days, schedule_time, created_by
  ) VALUES
  (
    v_a.id, COALESCE(v_a.employee_no, ''), v_store_b.account_id, v_store_b.group_id,
    v_store_b.id, v_store_b.vcode, v_store_b.store_name,
    1.0000, 1, v_eff_date, true,
    v_sched_days_b, v_sched_time_b, v_actor
  ),
  (
    v_b.id, COALESCE(v_b.employee_no, ''), v_store_a.account_id, v_store_a.group_id,
    v_store_a.id, v_store_a.vcode, v_store_a.store_name,
    1.0000, 1, v_eff_date, true,
    v_sched_days_a, v_sched_time_a, v_actor
  );

  RETURN jsonb_build_object(
    'success', true,
    'effective_date', v_eff_date,
    'employee_a', jsonb_build_object(
      'id', v_a.id,
      'employee_no', v_a.employee_no,
      'employee_name', v_a.employee_name,
      'new_store_id', v_store_b.id,
      'new_store_name', v_store_b.store_name,
      'new_vcode', v_store_b.vcode
    ),
    'employee_b', jsonb_build_object(
      'id', v_b.id,
      'employee_no', v_b.employee_no,
      'employee_name', v_b.employee_name,
      'new_store_id', v_store_a.id,
      'new_store_name', v_store_a.store_name,
      'new_vcode', v_store_a.vcode
    )
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.plantilla_swap(uuid, uuid, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.plantilla_swap(uuid, uuid, text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.plantilla_swap(uuid, uuid, text, date) TO service_role;

-- ============================================================================
-- 7. Idempotent Data Repair: Reconcile Drifted VCodes, Slots & Allocations
--    (Fixes 2019-14008 Abrogar & 2019-13652 Acibo + any prior legacy transfers)
-- ============================================================================
DO $$
DECLARE
  v_rec           record;
  v_target_slot   uuid;
  v_old_slot      uuid;
BEGIN
  -- 7A. Align plantilla.vcode to stores.vcode for Active stationary employees whose vcode drifted
  FOR v_rec IN
    SELECT p.id AS plantilla_id, p.store_id, s.store_name, s.vcode AS store_vcode, p.vcode AS old_vcode,
           p.account_id, s.group_id, p.employee_no, p.schedule_days, p.schedule_time, p."position"
    FROM public.plantilla p
    JOIN public.stores s ON s.id = p.store_id
    WHERE p.status = 'Active'
      AND COALESCE(p.is_deleted, false) = false
      AND COALESCE(p.is_archived, false) = false
      AND LOWER(COALESCE(p.deployment_type, 'stationary')) <> 'roving'
      AND p.coverage_group_id IS NULL
      AND s.vcode IS NOT NULL
      AND UPPER(TRIM(COALESCE(p.vcode, ''))) IS DISTINCT FROM UPPER(TRIM(s.vcode))
  LOOP
    -- Sync plantilla.vcode and store_name
    UPDATE public.plantilla
    SET vcode      = v_rec.store_vcode,
        store_name = v_rec.store_name,
        updated_at = now()
    WHERE id = v_rec.plantilla_id;

    -- Sync active employee_store_allocations to current store & vcode
    IF EXISTS (
      SELECT 1 FROM public.employee_store_allocations
      WHERE plantilla_id = v_rec.plantilla_id AND is_active = true
    ) THEN
      UPDATE public.employee_store_allocations
      SET store_id   = v_rec.store_id,
          store_name = v_rec.store_name,
          vcode      = v_rec.store_vcode
      WHERE plantilla_id = v_rec.plantilla_id
        AND is_active = true;
    ELSE
      INSERT INTO public.employee_store_allocations (
        plantilla_id, employee_no, account_id, group_id,
        store_id, vcode, store_name, filled_hc, active_store_count,
        effective_start, is_active, schedule_days, schedule_time
      ) VALUES (
        v_rec.plantilla_id, COALESCE(v_rec.employee_no, ''), v_rec.account_id, v_rec.group_id,
        v_rec.store_id, v_rec.store_vcode, v_rec.store_name, 1.0000, 1,
        CURRENT_DATE, true, v_rec.schedule_days, v_rec.schedule_time
      );
    END IF;
  END LOOP;

  -- 7B. Reconcile mismatched plantilla_slots where an Active stationary employee
  --     occupies a slot at a DIFFERENT store than their current plantilla.store_id
  FOR v_rec IN
    SELECT p.id AS plantilla_id, p.store_id AS curr_store_id, p."position",
           ps_old.id AS old_slot_id, ps_old.store_id AS old_slot_store_id
    FROM public.plantilla p
    JOIN public.plantilla_slots ps_old
      ON ps_old.current_occupant_plantilla_id = p.id
     AND ps_old.slot_status IN ('occupied', 'filled')
     AND COALESCE(ps_old.is_roving, false) = false
    WHERE p.status = 'Active'
      AND COALESCE(p.is_deleted, false) = false
      AND COALESCE(p.is_archived, false) = false
      AND LOWER(COALESCE(p.deployment_type, 'stationary')) <> 'roving'
      AND p.coverage_group_id IS NULL
      AND p.store_id IS NOT NULL
      AND ps_old.store_id IS DISTINCT FROM p.store_id
  LOOP
    -- Find a slot at the employee's current store that is either open OR currently
    -- pointing at someone else who is no longer at curr_store_id (e.g., mutual swap repair)
    SELECT ps.id INTO v_target_slot
    FROM public.plantilla_slots ps
    WHERE ps.store_id = v_rec.curr_store_id
      AND COALESCE(ps.is_roving, false) = false
      AND (
        ps.slot_status = 'open'
        OR (
          ps.slot_status IN ('occupied', 'filled')
          AND NOT EXISTS (
            SELECT 1 FROM public.plantilla p_occ
            WHERE p_occ.id = ps.current_occupant_plantilla_id
              AND p_occ.store_id = v_rec.curr_store_id
              AND p_occ.status = 'Active'
              AND COALESCE(p_occ.is_deleted, false) = false
          )
        )
      )
    ORDER BY (ps.slot_status = 'open') DESC, ps.slot_ordinal ASC NULLS LAST
    LIMIT 1;

    IF v_target_slot IS NOT NULL THEN
      -- Assign target slot to current employee via direct SWAP/transfer repair
      UPDATE public.plantilla_slots
      SET slot_status = 'occupied',
          current_occupant_plantilla_id = v_rec.plantilla_id,
          "position" = COALESCE(v_rec."position", "position"),
          updated_at = now()
      WHERE id = v_target_slot;

      -- Clear old slot ONLY if it still points to v_rec.plantilla_id
      UPDATE public.plantilla_slots
      SET slot_status = 'open',
          current_occupant_plantilla_id = NULL,
          updated_at = now()
      WHERE id = v_rec.old_slot_id
        AND current_occupant_plantilla_id = v_rec.plantilla_id;

      -- Ensure fully occupied target store does not stay spuriously 'Open' in vacancies
      IF NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots ps_chk
        WHERE ps_chk.store_id = v_rec.curr_store_id
          AND ps_chk.slot_status = 'open'
          AND COALESCE(ps_chk.is_roving, false) = false
      ) THEN
        UPDATE public.vacancies
        SET status = 'Filled', updated_at = now()
        WHERE store_id = v_rec.curr_store_id
          AND LOWER(COALESCE(status, '')) = 'open'
          AND COALESCE(is_archived, false) = false;
      END IF;
    END IF;
  END LOOP;
END $$;
