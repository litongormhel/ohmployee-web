-- Migration: 20262606000029_dashboard_rule5_aging_list_ordering_contract
-- (Filename timestamp follows this repo's existing malformed-but-consistent
-- migration-numbering scheme so it sorts after 20262606000028 on remote;
-- actually authored 2026-08-04, not 2026-06-26.)
-- Created: 2026-08-04
-- Purpose: ADR-001 Rule 5 (Ordering Contract) — site 1 of the remaining
--          Dashboard sites (ohm#q7z2j9wm investigation). Adds a
--          security_invoker view over vw_slot_derived_vacancy_shadow that
--          applies the Rule 4 remaining-open formula (open_count -
--          pipeline_count - hr_processing_count > 0), the >=30-day aging
--          gate, and ORDER BY days_open DESC in-DB — so Dashboard's
--          agingList can consume a DB-enforced order instead of Dart-side
--          rows.sort() in dashboard_screen.dart. Reuses the base view's
--          existing aging_days column rather than recomputing elapsed days.
--
-- Smoke Tests:
-- S1: SELECT vcode, days_open FROM v_dashboard_aging_vacancies;
--     rows must come back ordered by days_open DESC — verify against a
--     manual ORDER BY on the same filtered set.
-- S2: A vacancy row with hr_processing_count >= open_count - pipeline_count
--     (i.e. Rule 4 remaining_open <= 0) must NOT appear in the view output,
--     even if its raw open_count > 0.
-- S3: A vacancy row with days_open < 30 (or NULL, i.e. not currently open)
--     must NOT appear in the view output.
-- S4: SELECT * FROM vw_slot_derived_vacancy_shadow; must be unchanged —
--     this migration only adds a new wrapper view, no base view is modified.

CREATE OR REPLACE VIEW public.v_dashboard_aging_vacancies
  WITH (security_invoker = true)
AS
SELECT
  legacy_vcode          AS vcode,
  vacancy_tab            AS status,
  account_name,
  hrco_name,
  open_count,
  pipeline_count,
  hr_processing_count,
  aging_start_at,
  created_at,
  aging_days              AS days_open
FROM public.vw_slot_derived_vacancy_shadow
WHERE (open_count - pipeline_count - hr_processing_count) > 0
  AND aging_days IS NOT NULL
  AND aging_days >= 30
ORDER BY days_open DESC;

ALTER VIEW public.v_dashboard_aging_vacancies OWNER TO postgres;
COMMENT ON VIEW public.v_dashboard_aging_vacancies IS
  'Dashboard-scoped view of aging open vacancies from '
  'vw_slot_derived_vacancy_shadow, gated on the Rule 4 remaining-open '
  'formula (open_count - pipeline_count - hr_processing_count > 0) and '
  'days_open >= 30. Enforces Rule 5 in-DB ordering for the Dashboard '
  'agingList card: ORDER BY days_open DESC. security_invoker means it runs '
  'under the querying user''s RLS, same scope as vw_slot_derived_vacancy_shadow.';
GRANT SELECT ON public.v_dashboard_aging_vacancies TO authenticated, service_role;
