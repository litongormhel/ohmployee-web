-- ============================================================================
-- Migration: 20262606000022_vw_plantilla_inactive_ordering.sql
-- Prompt ID: ohm#7k2d9f4a (SA-3 — Views/Smoke)
-- Date:      2026-08-03
-- Purpose:   ADR-001 database-level enforcement — audit CASE 4 ordering
--            contract for the Plantilla Inactive tab.
--
-- Background:
--   No '%inactive%' view existed in public schema (live-verified on staging).
--   The Flutter Plantilla Inactive tab (_fetchInactiveTabEmployees in
--   lib/features/plantilla/plantilla_screen.dart) queries v_plantilla_safe
--   directly with:
--       .neq('status', 'Active')
--       .isFilter('source_headcount_request_id', null)
--   and then sorts CLIENT-SIDE. The ordering contract must live in the DB.
--
-- This view:
--   * Thin wrapper over public.v_plantilla_safe replicating exactly the
--     Flutter inactive-tab predicate:
--         status <> 'Active'  (PostgREST neq semantics: NULL status excluded)
--         AND source_headcount_request_id IS NULL
--   * ORDER BY date_of_separation DESC NULLS LAST inside the view
--     (secondary key employee_name ASC for deterministic ties).
--   * security_invoker = true, so selecting from this wrapper is
--     semantically identical to the client querying v_plantilla_safe
--     directly (v_plantilla_safe remains the underlying definer-style view).
--
-- Column-name note (discrepancy vs prompt):
--   The prompt referenced `resignation_date`. The plantilla table has BOTH
--   `resignation_date` (date) and `date_of_separation` (date), but
--   v_plantilla_safe exposes ONLY `date_of_separation`. `date_of_separation`
--   is the column the docs and the safe view use as the separation date, so
--   the ordering contract is defined on `date_of_separation`.
--
-- Flutter follow-up (do NOT do in this prompt):
--   plantilla_screen.dart's client-side sort in _fetchInactiveTabEmployees
--   becomes redundant; a later Flutter prompt should repoint
--   _fetchInactiveTabEmployees to select from vw_plantilla_inactive and
--   drop the client-side .order('employee_name') sort.
--
-- Idempotent: CREATE OR REPLACE VIEW.
-- ============================================================================

CREATE OR REPLACE VIEW public.vw_plantilla_inactive
WITH (security_invoker = true) AS
SELECT vps.*
FROM public.v_plantilla_safe vps
WHERE vps.status <> 'Active'
  AND vps.source_headcount_request_id IS NULL
ORDER BY vps.date_of_separation DESC NULLS LAST,
         vps.employee_name ASC;

COMMENT ON VIEW public.vw_plantilla_inactive IS
  'ohm#7k2d9f4a (2026-08-03): Plantilla Inactive tab population with the '
  'audit CASE 4 ordering contract enforced in-DB (date_of_separation DESC '
  'NULLS LAST, employee_name ASC). Thin security_invoker wrapper over '
  'v_plantilla_safe; predicate replicates Flutter _fetchInactiveTabEmployees '
  '(status <> ''Active'' AND source_headcount_request_id IS NULL). Scope '
  'filters (store_id / account) remain caller-supplied.';

GRANT SELECT ON public.vw_plantilla_inactive TO authenticated;
GRANT SELECT ON public.vw_plantilla_inactive TO service_role;
