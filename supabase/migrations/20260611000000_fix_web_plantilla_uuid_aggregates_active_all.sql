-- Migration: 20260611000000_fix_web_plantilla_uuid_aggregates_active_all.sql
-- Ticket: OHM2026_1119 - Fix Plantilla Web RPC UUID aggregation and active roster filtering
--
-- Purpose:
--   Patch only the Web Plantilla read RPC bodies affected by runtime behavior:
--     * list_web_plantilla_employees(...)
--     * list_web_plantilla_store_staffing(...)
--
-- Notes:
--   - PostgreSQL has no max(uuid), so UUID representative values must not use max().
--   - Employee active-state filtering treats NULL, blank, and 'all' as no active-state
--     filter. 'active' and 'inactive' still use the lifecycle derivation from status,
--     separation_status, date_of_separation, and deactivated_at.

DO $migration$
DECLARE
  v_sql text;
  v_old text := $old$
        p_active_state IS NULL
        OR (lower(p_active_state) = 'active' AND s.is_active)
        OR (lower(p_active_state) = 'inactive' AND s.is_inactive)$old$;
  v_new text := $new$
        p_active_state IS NULL
        OR nullif(btrim(p_active_state), '') IS NULL
        OR lower(btrim(p_active_state)) = 'all'
        OR (lower(btrim(p_active_state)) = 'active' AND s.is_active)
        OR (lower(btrim(p_active_state)) = 'inactive' AND s.is_inactive)$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.list_web_plantilla_employees(text, uuid, uuid, uuid, text, text, text, integer, integer, text, text)'::regprocedure
  )
  INTO v_sql;

  IF position(v_old IN v_sql) = 0 THEN
    RAISE EXCEPTION 'list_web_plantilla_employees active-state filter patch target not found'
      USING ERRCODE = 'P0001';
  END IF;

  v_sql := replace(v_sql, v_old, v_new);
  EXECUTE v_sql;
END;
$migration$;

COMMENT ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) IS
  'OHM2026_1119 - Web presentation contract only. Treats NULL/blank/all active-state filters as unfiltered and derives active/inactive from v_plantilla_safe lifecycle/status columns.';

DO $migration$
DECLARE
  v_sql text;
  v_old_account text := '      max(u.account_id) AS account_id,';
  v_new_account text := '      (array_agg(u.account_id ORDER BY u.account_id::text))[1] AS account_id,';
  v_old_province text := '      max(u.province_id) AS province_id';
  v_new_province text := '      (array_agg(u.province_id ORDER BY u.province_id::text))[1] AS province_id';
BEGIN
  SELECT pg_get_functiondef(
    'public.list_web_plantilla_store_staffing(text, uuid, uuid, text, integer, integer, text, text)'::regprocedure
  )
  INTO v_sql;

  IF position(v_old_account IN v_sql) = 0 THEN
    RAISE EXCEPTION 'list_web_plantilla_store_staffing account_id UUID aggregate patch target not found'
      USING ERRCODE = 'P0001';
  END IF;

  IF position(v_old_province IN v_sql) = 0 THEN
    RAISE EXCEPTION 'list_web_plantilla_store_staffing province_id UUID aggregate patch target not found'
      USING ERRCODE = 'P0001';
  END IF;

  v_sql := replace(v_sql, v_old_account, v_new_account);
  v_sql := replace(v_sql, v_old_province, v_new_province);
  EXECUTE v_sql;
END;
$migration$;

COMMENT ON FUNCTION public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
) IS
  'OHM2026_1119 - Web presentation contract only. Avoids max(uuid) in store staffing aggregation by using deterministic ordered array selection for UUID representative values.';

REVOKE ALL ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_web_plantilla_employees(
  text, uuid, uuid, uuid, text, text, text, integer, integer, text, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_web_plantilla_store_staffing(
  text, uuid, uuid, text, integer, integer, text, text
) TO authenticated;
