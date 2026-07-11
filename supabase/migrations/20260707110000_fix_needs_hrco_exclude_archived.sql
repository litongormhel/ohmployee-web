-- Migration: 20260707110000_fix_needs_hrco_exclude_archived
-- Created: 2026-07-07
-- Prompt: ohm#7f3k2a91 (Fix HRCO Assignment Leakage + Plantilla Active Filtering)
-- Purpose: Close a data leak in the "Needs HRCO" tab RPCs where archived plantilla
--   employees (is_archived = true) still appeared because neither RPC checked
--   is_archived or the visibility-window columns (deactivated_visible_until,
--   inactive_visible_until) that v_plantilla_safe already checks for every other
--   "active employee" surface in the app.
--
-- Root cause (confirmed on staging via direct query):
--   KYLIE AQUINO PADILLA (plantilla.id 774fd565-6d83-470d-84e1-f20334e3dc71) has
--   status = 'Active', is_deleted = false, but is_archived = true. 363 plantilla
--   rows on staging share this exact leaking combination. get_plantilla_needs_hrco_
--   employees and get_plantilla_unassigned_hrco_count (20260707100002) only checked
--   is_deleted and status -- never is_archived -- so every one of those 363 rows
--   was eligible to leak into the Needs HRCO tab and badge count.
--
-- Fix: add the same three predicates v_plantilla_safe already uses:
--   COALESCE(p.is_archived, false) = false
--   AND (p.deactivated_visible_until IS NULL OR p.deactivated_visible_until > now())
--   AND (p.inactive_visible_until IS NULL OR p.inactive_visible_until > now())
--
-- Status filter is intentionally UNCHANGED (still IN ('Active','For Deactivation',
-- 'On Leave')) -- that is the existing app-wide definition of "still deployed,
-- needs an HRCO" and narrowing it to literal 'ACTIVE' only would silently drop
-- On Leave / For Deactivation employees from HRCO assignment, which is not the
-- bug being fixed here.
--
-- Smoke Tests (run after apply, capture real output before COMPLETE):
-- S1: SELECT * FROM get_plantilla_needs_hrco_employees('22501010-b8e6-4346-8cf1-923d7597e934')
--     AS a Data Team user -- confirm KYLIE AQUINO PADILLA (774fd565-6d83-470d-84e1-f20334e3dc71)
--     no longer appears.
-- S2: SELECT count(*) FROM public.plantilla WHERE is_archived = true
--       AND is_deleted = false AND status IN ('Active','For Deactivation','On Leave')
--       AND NOT EXISTS (SELECT 1 FROM plantilla_hrco_assignments a WHERE a.plantilla_id = plantilla.id AND a.is_active);
--     -- this is the exact leaking set (363 rows on staging pre-fix) -- confirm
--     -- get_plantilla_unassigned_hrco_count() no longer includes them in its count.

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
    AND COALESCE(p.is_archived, false) = false
    AND (p.deactivated_visible_until IS NULL OR p.deactivated_visible_until > now())
    AND (p.inactive_visible_until IS NULL OR p.inactive_visible_until > now())
    AND p.status IN ('Active', 'For Deactivation', 'On Leave')
    AND NOT EXISTS (
      SELECT 1 FROM public.plantilla_hrco_assignments a
       WHERE a.plantilla_id = p.id AND a.is_active
    )
  ORDER BY p.employee_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_plantilla_unassigned_hrco_count(p_account_id uuid)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT CASE WHEN public.i_am_data_team() OR public.i_have_full_access() THEN (
    SELECT count(*)::int
      FROM public.plantilla p
     WHERE p.account_id = p_account_id
       AND p.is_deleted = false
       AND COALESCE(p.is_archived, false) = false
       AND (p.deactivated_visible_until IS NULL OR p.deactivated_visible_until > now())
       AND (p.inactive_visible_until IS NULL OR p.inactive_visible_until > now())
       AND p.status IN ('Active', 'For Deactivation', 'On Leave')
       AND NOT EXISTS (
         SELECT 1 FROM public.plantilla_hrco_assignments a
          WHERE a.plantilla_id = p.id AND a.is_active
       )
  ) ELSE 0 END;
$$;

COMMIT;
