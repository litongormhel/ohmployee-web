-- Migration: 20262606000033_dashboard_rule5_hrco_breakdown_ordering_contract
-- (Filename timestamp follows this repo's existing malformed-but-consistent
-- migration-numbering scheme so it sorts after 20262606000032 on remote;
-- actually authored 2026-08-05, not 2026-06-26.)
-- Created: 2026-08-05
-- Purpose: ADR-001 Rule 5 (Ordering Contract) — Dashboard Group D, site 5 of
--          6 (final Dashboard Rule 5 item, ohm#d4w7k2ml). Adds a
--          security_invoker view that 3-way-aggregates v_plantilla_safe,
--          hr_emploc, and vw_slot_derived_vacancy_shadow by hrco_name,
--          computes MFR, and orders name ASC with 'Unassigned' pinned last
--          in-DB — replacing the client-side hrcoMap aggregation + .sort()
--          in dashboard_screen.dart.
--          Also fixes a latent correctness bug in the same diff: the prior
--          Dart vacancy loop read v['status'], which does not exist in
--          vacQ's select (vw_slot_derived_vacancy_shadow only has
--          vacancy_tab) — so the vacant component of omHrcoBreakdown was
--          silently always 0, and the 'Unassigned' bucket (only ever
--          created by that dead loop) never appeared despite the
--          pinned-last sort logic already existing for it.
--          This view uses the Rule 4 remaining-capacity formula (open_count
--          - pipeline_count - hr_processing_count > 0), same gate as
--          v_dashboard_aging_vacancies / v_dashboard_store_aging /
--          v_dashboard_account_mfr_breakdown (20262606000032).
--
-- Smoke Tests:
-- S1: SELECT hrco, vacant, active, required, mfr
--     FROM v_dashboard_hrco_breakdown;
--     rows must come back ordered by hrco_name ASC, with any 'Unassigned'
--     row sorted after every named HRCO regardless of alphabetical order.
-- S2: A vacancy row (Rule 4 remaining_open > 0) with a NULL or blank
--     hrco_name must be bucketed under 'Unassigned', with vacant > 0 and
--     active = 0, pipeline = 0 (plantilla/hr_emploc rows with blank
--     hrco_name are excluded from their aggregates entirely, never bucketed
--     as 'Unassigned' — matches the prior client-side
--     `if (hrco.isEmpty) continue;` behavior for those two sources only).
-- S3: A named HRCO with active plantilla headcount but zero open vacancies
--     must appear with vacant = 0, not be excluded from the output.
-- S4: SELECT * FROM v_plantilla_safe / hr_emploc / vw_slot_derived_vacancy_shadow;
--     must be unchanged — this migration only adds a new wrapper view, no
--     base table/view is modified.

CREATE OR REPLACE VIEW public.v_dashboard_hrco_breakdown
  WITH (security_invoker = true)
AS
WITH active_agg AS (
  SELECT hrco_name AS hrco, COUNT(*) AS active
  FROM public.v_plantilla_safe
  WHERE status = 'Active'
    AND hrco_name IS NOT NULL AND TRIM(hrco_name) <> ''
  GROUP BY hrco_name
),
pipeline_agg AS (
  SELECT hrco_name AS hrco, COUNT(*) AS pipeline
  FROM public.hr_emploc
  WHERE hr_status IN ('Pending', 'Complete')
    AND deleted_at IS NULL
    AND hrco_name IS NOT NULL AND TRIM(hrco_name) <> ''
  GROUP BY hrco_name
),
vac_agg AS (
  SELECT COALESCE(NULLIF(TRIM(hrco_name), ''), 'Unassigned') AS hrco, COUNT(*) AS vacant
  FROM public.vw_slot_derived_vacancy_shadow
  WHERE (open_count - pipeline_count - hr_processing_count) > 0
  GROUP BY COALESCE(NULLIF(TRIM(hrco_name), ''), 'Unassigned')
),
all_hrco AS (
  SELECT hrco FROM active_agg
  UNION
  SELECT hrco FROM pipeline_agg
  UNION
  SELECT hrco FROM vac_agg
)
SELECT
  ah.hrco,
  COALESCE(v.vacant, 0) AS vacant,
  COALESCE(a.active, 0) AS active,
  COALESCE(a.active, 0) + COALESCE(v.vacant, 0) AS required,
  CASE
    WHEN COALESCE(a.active, 0) + COALESCE(v.vacant, 0) > 0
      THEN (COALESCE(a.active, 0) + COALESCE(p.pipeline, 0))::numeric
           / (COALESCE(a.active, 0) + COALESCE(v.vacant, 0))
    ELSE 1.0
  END AS mfr
FROM all_hrco ah
LEFT JOIN active_agg a ON a.hrco = ah.hrco
LEFT JOIN pipeline_agg p ON p.hrco = ah.hrco
LEFT JOIN vac_agg v ON v.hrco = ah.hrco
ORDER BY (CASE WHEN ah.hrco = 'Unassigned' THEN 1 ELSE 0 END) ASC, ah.hrco ASC;

ALTER VIEW public.v_dashboard_hrco_breakdown OWNER TO postgres;
COMMENT ON VIEW public.v_dashboard_hrco_breakdown IS
  'Dashboard-scoped 3-way aggregate (v_plantilla_safe active count, '
  'hr_emploc pipeline count, vw_slot_derived_vacancy_shadow Rule-4 '
  'remaining-open count) grouped by hrco_name, with computed MFR. Blank/'
  'null hrco_name on open vacancies buckets into ''Unassigned''; blank/null '
  'hrco_name on plantilla/hr_emploc rows is excluded from those aggregates '
  'entirely (matches prior Dart behavior). Enforces Rule 5 in-DB ordering '
  'for the Dashboard omHrcoBreakdown card: hrco_name ASC with ''Unassigned'' '
  'pinned last. security_invoker means it runs under the querying user''s '
  'RLS, same scope as its three source tables/views.';
GRANT SELECT ON public.v_dashboard_hrco_breakdown TO authenticated, service_role;
