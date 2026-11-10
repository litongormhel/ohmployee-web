-- ============================================================
-- Migration: 20262606000089_update_plantilla_schedule_rpc.sql
-- Description: Authoritative SECURITY DEFINER RPC to update employee schedule,
-- rest days, and per-store schedule allocations across plantilla and employee_store_allocations.
-- ============================================================

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
  IF p_plantilla_id IS NULL THEN
    RAISE EXCEPTION 'plantilla_id cannot be null' USING ERRCODE = '22004';
  END IF;

  -- Verify employee exists and get employee_no
  SELECT employee_no INTO v_emp_no
  FROM public.plantilla
  WHERE id = p_plantilla_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla record not found for id %', p_plantilla_id USING ERRCODE = 'P0002';
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

-- Grant execution to authenticated role
REVOKE ALL ON FUNCTION public.update_plantilla_schedule(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_plantilla_schedule(uuid, text, text, text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.update_plantilla_schedule(uuid, text, text, text, jsonb) IS
'Authoritative RPC to update schedule days, shift hours, designated rest days, and per-store allocation schedules across plantilla and employee_store_allocations.';
