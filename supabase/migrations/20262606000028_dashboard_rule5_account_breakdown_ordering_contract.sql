-- Migration: 20262606000028_dashboard_rule5_account_breakdown_ordering_contract
-- (Filename timestamp follows this repo's existing malformed-but-consistent
-- migration-numbering scheme so it sorts after 20262606000027 on remote;
-- actually authored 2026-08-04, not 2026-06-26.)
-- Created: 2026-08-04
-- Purpose: ADR-001 Rule 5 (Ordering Contract) — site 2 of 5 remaining Dashboard
--          sites (ohm#q7z2j9wm investigation). Adds a security_invoker view
--          aggregating v_plantilla_safe by account (Active/Resigned counts)
--          so Dashboard's accountBreakdown can consume a DB-enforced order
--          instead of Dart-side rows.sort() in dashboard_screen.dart.
--
-- Smoke Tests:
-- S1: SELECT account, active, resigned FROM v_dashboard_account_breakdown;
--     rows must come back ordered by active DESC — verify against a manual
--     ORDER BY on the same aggregate.
-- S2: An account with only non-Active/non-Resigned plantilla rows (e.g. all
--     'Terminated') must NOT appear in the view output — matches the
--     existing client-side zero-filter behavior being replaced.
-- S3: SELECT * FROM v_plantilla_safe; must be unchanged — this migration
--     only adds a new wrapper view, no base table/view is modified.

CREATE OR REPLACE VIEW public.v_dashboard_account_breakdown
  WITH (security_invoker = true)
AS
SELECT
  account,
  COUNT(*) FILTER (WHERE status = 'Active')   AS active,
  COUNT(*) FILTER (WHERE status = 'Resigned') AS resigned
FROM public.v_plantilla_safe
GROUP BY account
HAVING COUNT(*) FILTER (WHERE status IN ('Active', 'Resigned')) > 0
ORDER BY active DESC;

ALTER VIEW public.v_dashboard_account_breakdown OWNER TO postgres;
COMMENT ON VIEW public.v_dashboard_account_breakdown IS
  'Dashboard-scoped aggregate of v_plantilla_safe by account (Active/Resigned '
  'counts). Enforces Rule 5 in-DB ordering for the Dashboard accountBreakdown '
  'card: ORDER BY active DESC. Accounts with no Active/Resigned rows are '
  'excluded, matching the prior client-side filter. security_invoker means '
  'it runs under the querying user''s RLS, same scope as v_plantilla_safe.';
GRANT SELECT ON public.v_dashboard_account_breakdown TO authenticated, service_role;
