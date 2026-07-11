-- Migration: 20260707100002_get_plantilla_needs_hrco_employees
-- Created: 2026-07-07
-- Prompt: ohm#k8d2x7qf (Plantilla "Needs HRCO" tab data source — part 3 of the HRCO
--   Employee-Level Scope Isolation feature; see 20260707100000_hrco_scope_isolation_plantilla.sql)
-- Purpose: Backend-side listing RPC for the Flutter "Needs HRCO" tab. Data Team only
--   (Encoder/Head Admin/Super Admin per i_am_data_team()/i_have_full_access()) — HRCO
--   role never receives this data, matching the client-side tab-visibility gate.
--   Returns rows shaped to match the existing v_plantilla_safe-style column aliases
--   already consumed by Flutter's _employeeFromAccountRow() field-fallback mapping,
--   so no new Flutter model parsing is required.
--
-- Smoke Test:
-- S1: select * from get_plantilla_needs_hrco_employees('<account_id>') as Data Team user
--     -> only unassigned Active/On Leave/For Deactivation employees for that account
-- S2: as HRCO role -> empty result (forbidden by internal gate, not silent RLS filter)

BEGIN;

CREATE OR REPLACE FUNCTION public.get_plantilla_needs_hrco_employees(p_account_id uuid)
RETURNS TABLE(
  id uuid,
  employee_name text,
  employee_no text,
  emploc_no text,
  vcode text,
  account text,
  store_name text,
  position_name text,
  status text,
  deployment_type text,
  schedule text,
  day_off text,
  area_city text,
  area_province text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  IF NOT (public.i_am_data_team() OR public.i_have_full_access()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.employee_name,
    p.employee_no,
    p.emploc_no,
    p.vcode,
    p.account,
    p.store_name,
    p.position::text,
    p.status,
    p.deployment_type,
    p.schedule,
    p.dayoff,
    s.area_city::text,
    COALESCE(s.area_province, s.province)::text
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  WHERE p.account_id = p_account_id
    AND p.is_deleted = false
    AND p.status IN ('Active', 'For Deactivation', 'On Leave')
    AND NOT EXISTS (
      SELECT 1 FROM public.plantilla_hrco_assignments a
       WHERE a.plantilla_id = p.id AND a.is_active
    )
  ORDER BY p.employee_name;
END;
$$;

COMMIT;
