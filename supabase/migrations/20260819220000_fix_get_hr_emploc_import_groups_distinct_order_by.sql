-- Migration: 20260819220000_fix_get_hr_emploc_import_groups_distinct_order_by.sql
-- Module: HR Emploc Import
-- Prompt: ohm#3wv7n2kx (BUG-04 follow-up)
--
-- Discovered while verifying 20260819200000 (the i_am_data_team() gate swap):
-- get_hr_emploc_import_groups()'s scoped-user (non-full-access) branch used
--   SELECT DISTINCT g.id, g.group_name, ROW_NUMBER() OVER (ORDER BY g.group_code)::INTEGER
--   FROM ... ORDER BY g.group_code;
-- Postgres rejects a SELECT DISTINCT whose trailing ORDER BY references a
-- column (g.group_code) not present in the select list. This bug predates
-- this session — it was simply unreachable, because every non-full-access
-- caller (Encoder included) was always blocked by the old
-- `get_my_role_level() < 50` gate before ever reaching this query. Migration
-- 20260819200000 correctly let Encoder past the gate, which unmasked this
-- pre-existing defect: Encoder now failed with a genuine SQL error instead
-- of a permission error, still unable to load groups.
--
-- Fix: restructure so DISTINCT applies to the raw columns in a subquery,
-- then ROW_NUMBER()/ORDER BY happen in the outer query where group_code is
-- in scope. Same dedup semantics as before — a given group_id always maps to
-- exactly one group_code/group_name, so DISTINCT on the 3-tuple is
-- equivalent to the prior DISTINCT-on-id intent (multiple user_scopes rows
-- can join the same group more than once; this collapses those duplicates
-- identically to before). Verified live in a rolled-back transaction against
-- a real scoped Encoder before writing this file: returns the correct 3
-- groups (previously errored).
--
-- Only the scoped-user branch's query is restructured. The gate
-- (i_am_data_team(), from 20260819200000) and the full-access branch are
-- untouched.

CREATE OR REPLACE FUNCTION public.get_hr_emploc_import_groups()
RETURNS TABLE (
  group_id   UUID,
  group_name TEXT,
  sort_order INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
  END IF;
  IF NOT i_am_data_team() THEN
    RAISE EXCEPTION 'Insufficient permissions' USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := get_current_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found. Please contact admin.' USING ERRCODE = 'P0001';
  END IF;

  IF i_have_full_access() THEN
    RETURN QUERY
    SELECT
      g.id,
      g.group_name,
      ROW_NUMBER() OVER (ORDER BY g.group_code)::INTEGER
    FROM public.groups g
    WHERE COALESCE(g.cencom_scope, false) = true
    ORDER BY g.group_code;
    RETURN;
  END IF;

  -- Scoped users: their assigned groups that are operational.
  -- DISTINCT applied on raw columns in the subquery; ROW_NUMBER/ORDER BY
  -- happen outside where group_code is available (fix for the
  -- SELECT DISTINCT + ORDER BY-not-in-select-list error).
  RETURN QUERY
  SELECT
    g.id,
    g.group_name,
    ROW_NUMBER() OVER (ORDER BY g.group_code)::INTEGER
  FROM (
    SELECT DISTINCT g2.id, g2.group_code, g2.group_name
    FROM public.user_scopes us
    JOIN public.groups g2 ON g2.id = us.group_id
    WHERE us.user_id = v_profile_id
      AND COALESCE(g2.cencom_scope, false) = true
  ) g
  ORDER BY g.group_code;
END;
$$;
