-- Migration: 20262606000027_dashboard_rule5_group_ordering_contract
-- (Filename timestamp follows this repo's existing malformed-but-consistent
-- migration-numbering scheme so it sorts after 20262606000026 on remote;
-- actually authored 2026-08-04, not 2026-06-26.)
-- Created: 2026-08-04
-- Purpose: ADR-001 Rule 5 (Ordering Contract) — add a Dashboard-scoped wrapper
--          view over the existing, CENCOM-owned v_cencom_group_allocation_kpi
--          so the Dashboard Operations Summary group breakdown can consume a
--          DB-enforced order instead of Dart-side rows.sort() in
--          dashboard_screen.dart's _buildOperationsGroups. The base
--          v_cencom_group_allocation_kpi view (and its group_code ASC order,
--          relied on by CENCOM) is not modified.
--
-- Smoke Tests:
-- S1: SELECT group_name, mfr, slot_vacant_hc FROM v_dashboard_group_allocation_kpi;
--     rows must come back ordered by mfr ASC, then slot_vacant_hc DESC, then
--     group_name ASC — verify against a manual ORDER BY on the base view.
-- S2: SELECT group_name, mfr, slot_vacant_hc FROM v_cencom_group_allocation_kpi;
--     must be unchanged (still group_code ASC) — confirms CENCOM's Rule 5
--     compliance (ohm#c9x4t2wm) is untouched by this migration.

CREATE OR REPLACE VIEW public.v_dashboard_group_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT g.*
FROM public.v_cencom_group_allocation_kpi g
ORDER BY g.mfr ASC, g.slot_vacant_hc DESC, g.group_name ASC;

ALTER VIEW public.v_dashboard_group_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_dashboard_group_allocation_kpi IS
  'Dashboard-scoped read of v_cencom_group_allocation_kpi (unmodified). '
  'Enforces Rule 5 in-DB ordering for the Dashboard Operations Summary group '
  'breakdown: ORDER BY mfr ASC, slot_vacant_hc DESC, group_name ASC. '
  'Does not alter v_cencom_group_allocation_kpi or its group_code ASC order, '
  'which CENCOM continues to rely on.';
GRANT SELECT ON public.v_dashboard_group_allocation_kpi TO authenticated, service_role;
