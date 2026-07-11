-- OHM2026_0071 — Import Payroll reconciliation checker backend.
--
-- Provides get_global_plantilla_for_payroll_check(): SECURITY DEFINER,
-- HA/SA only. Returns all non-pool plantilla rows globally so the Dart
-- client can do a full payroll vs plantilla diff without scope filters.
--
-- No staging table, no mutation RPC, no import log.

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
  ORDER BY p.employee_no;
END;
$$;

GRANT EXECUTE
  ON FUNCTION public.get_global_plantilla_for_payroll_check()
  TO authenticated;
