-- Migration: 20262606000060_fix_needs_hrco_role_access.sql
-- Description: Fix get_plantilla_unassigned_hrco_count and get_plantilla_needs_hrco_employees:
--   1. Remove restrictive data-team-only guard so all authorized callers (e.g. Operations Managers)
--      can see unassigned HRCO counts and employees.
--   2. When an account has no assigned HRCO (accounts.hrco_user_id IS NULL), all active employees
--      under that account are returned as needing HRCO.
--   3. When an account has an assigned HRCO, returns 0 / empty set.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_plantilla_unassigned_hrco_count(p_account_id uuid)
RETURNS integer
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_has_hrco   boolean;
  v_count      integer := 0;
BEGIN
  -- Check if account already has an assigned HRCO
  SELECT (a.hrco_user_id IS NOT NULL)
    INTO v_has_hrco
    FROM public.accounts a
   WHERE a.id = p_account_id;

  IF COALESCE(v_has_hrco, false) THEN
    RETURN 0;
  END IF;

  -- If account has no HRCO, all active employees under this account need an HRCO
  SELECT count(*)::int
    INTO v_count
    FROM public.plantilla p
   WHERE p.account_id = p_account_id
     AND p.is_deleted = false
     AND COALESCE(p.is_archived, false) = false
     AND (p.deactivated_visible_until IS NULL OR p.deactivated_visible_until > now())
     AND (p.inactive_visible_until IS NULL OR p.inactive_visible_until > now())
     AND p.status IN ('Active', 'For Deactivation', 'On Leave');

  RETURN COALESCE(v_count, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.get_plantilla_unassigned_hrco_count(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_unassigned_hrco_count(uuid) TO authenticated;

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
DECLARE
  v_has_hrco boolean;
BEGIN
  -- If the account already has an assigned HRCO, no employees need an HRCO
  SELECT (a.hrco_user_id IS NOT NULL)
    INTO v_has_hrco
    FROM public.accounts a
   WHERE a.id = p_account_id;

  IF COALESCE(v_has_hrco, false) THEN
    RETURN;
  END IF;

  -- If account has no HRCO, all active employees under this account need HRCO
  RETURN QUERY
  SELECT
    p.id,
    p.employee_name,
    p.employee_no,
    p.emploc_no,
    p.vcode,
    p.account,
    p.store_name,
    p.position::text AS position_name,
    p.status,
    p.deployment_type,
    p.schedule,
    p.dayoff AS day_off,
    s.area_city::text,
    COALESCE(s.area_province, s.province)::text AS area_province
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  WHERE p.account_id = p_account_id
    AND p.is_deleted = false
    AND COALESCE(p.is_archived, false) = false
    AND (p.deactivated_visible_until IS NULL OR p.deactivated_visible_until > now())
    AND (p.inactive_visible_until IS NULL OR p.inactive_visible_until > now())
    AND p.status IN ('Active', 'For Deactivation', 'On Leave')
  ORDER BY p.employee_name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_plantilla_needs_hrco_employees(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_needs_hrco_employees(uuid) TO authenticated;

COMMIT;
