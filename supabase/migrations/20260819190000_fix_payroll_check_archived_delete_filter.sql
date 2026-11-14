-- Migration: 20260819190000_fix_payroll_check_archived_delete_filter.sql
-- ohm#9k4wtq2v (2026-08-19) — BUG-05: Import Payroll "Active Plantilla" count
-- includes archived/deleted rows (100 vs 26 expected), inflating "Missing in
-- Payroll" to 99.
-- ============================================================
-- Root cause
-- ----------
-- get_global_plantilla_for_payroll_check() (20260604000003) queries
-- public.plantilla directly (not through v_plantilla_safe) and its WHERE
-- clause never filters p.is_archived / p.is_deleted. Its is_active flag is
-- derived only from p.status / p.separation_status text, so an archived row
-- with status='Active' is still returned with is_active=true and counted as
-- a real active employee by the Dart reconciliation (payroll_check_service.dart),
-- which correctly filters on is_active but can only trust what the RPC sends.
--
-- Same bug class as 20262606000040 (v_plantilla_safe lost its archive/delete
-- filter) — that fix's own notes flagged get_plantilla_employees() as a
-- separate occurrence of the identical class for querying plantilla directly;
-- this RPC is a second, distinct occurrence of that same class.
--
-- Fix (additive only)
-- --------------------
-- Adds `AND p.is_deleted = false AND (p.is_archived = false OR p.is_archived
-- IS NULL)` to the base WHERE clause, matching v_plantilla_safe's predicate
-- verbatim. No column, join, return shape, grant, or RLS change. is_active
-- derivation logic (status/separation_status) untouched — archived rows are
-- now excluded from the result set entirely rather than mis-flagged.
--
-- Smoke test (read-only, run after apply):
-- S1: SELECT count(*) FROM get_global_plantilla_for_payroll_check();
--     -- expect ~26 (was ~100 before fix)
-- S2: SELECT count(*) FROM get_global_plantilla_for_payroll_check() WHERE is_active;
--     -- expect same as S1 minus any inactive-but-not-archived rows

CREATE OR REPLACE FUNCTION public.get_global_plantilla_for_payroll_check()
RETURNS TABLE (
  plantilla_id  uuid,
  employee_no   text,
  last_name     text,
  first_name    text,
  middle_name   text,
  account_name  text,
  group_name    text,
  is_active     boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Access denied — HA/SA only'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id                                                              AS plantilla_id,
    COALESCE(btrim(p.employee_no), '')                               AS employee_no,
    COALESCE(btrim(p.last_name),   '')                               AS last_name,
    COALESCE(btrim(p.first_name),  '')                               AS first_name,
    COALESCE(btrim(p.middle_name), '')                               AS middle_name,
    COALESCE(btrim(a.account_name), '')                              AS account_name,
    COALESCE(btrim(g.group_name),   '')                              AS group_name,
    (
      lower(COALESCE(NULLIF(btrim(p.status), ''), 'active'))
        NOT IN ('deactivated', 'archived', 'inactive')
      AND lower(COALESCE(NULLIF(btrim(p.separation_status), ''), ''))
        NOT IN ('deactivated', 'terminated', 'resigned', 'awol')
    )                                                                 AS is_active
  FROM  public.plantilla p
  JOIN  public.accounts  a ON a.id = p.account_id
  JOIN  public.groups    g ON g.id = a.group_id
  WHERE COALESCE(p.is_pool_employee, false) = false
    AND p.employee_no IS NOT NULL
    AND btrim(p.employee_no) <> ''
    AND p.is_deleted = false
    AND (p.is_archived = false OR p.is_archived IS NULL)
  ORDER BY p.employee_no;
END;
$$;

GRANT EXECUTE
  ON FUNCTION public.get_global_plantilla_for_payroll_check()
  TO authenticated;
