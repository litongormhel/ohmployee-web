-- =============================================================================
-- OHMployee Database Migration: 20262606000194_restore_vw_plantilla_inactive_tab_isolation.sql
-- Module: Plantilla / Workforce Status Isolation (Bugs 12 & 13)
--
-- Purpose:
--   Restores proper status isolation for public.vw_plantilla_inactive.
--   Migration 20262606000151 inadvertently simplified the WHERE predicate to
--   only `vps.status <> 'Active'`, causing 'On Leave' and 'Floating' employees
--   to leak into the Inactive tab.
--
--   This migration restores strict exclusions:
--     • status <> 'Active'
--     • status <> 'On Leave'
--     • status <> 'Floating'
--     • COALESCE(separation_status, '') <> 'Floating'
--     • source_headcount_request_id IS NULL
--   Preserves in-DB ADR-001 Rule 5 ordering:
--     ORDER BY date_of_separation DESC NULLS LAST, employee_name ASC
-- =============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.vw_plantilla_inactive
WITH (security_invoker = true) AS
SELECT vps.*
FROM public.v_plantilla_safe vps
WHERE vps.status <> 'Active'
  AND vps.status <> 'On Leave'
  AND vps.status <> 'Floating'
  AND COALESCE(vps.separation_status, '') <> 'Floating'
  AND vps.source_headcount_request_id IS NULL
ORDER BY vps.date_of_separation DESC NULLS LAST,
         vps.employee_name ASC;

COMMENT ON VIEW public.vw_plantilla_inactive IS
  'Plantilla Inactive tab view with strict status isolation (excludes Active, On Leave, and Floating) and ADR-001 Rule 5 in-DB ordering contract (date_of_separation DESC NULLS LAST, employee_name ASC).';

GRANT SELECT ON public.vw_plantilla_inactive TO authenticated, service_role;

COMMIT;
