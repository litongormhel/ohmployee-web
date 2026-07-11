-- ============================================================
-- OHM2026_0098 - ADR-001 roving pipeline reporting fix
--
-- Fix:
--   Coverage Group slots in `pipeline` are still vacant HC under the
--   canonical slot-status contract. Only `hr_processing` contributes to the
--   in-flight pipeline metric in allocation reporting.
--
-- Preserved:
--   - HC remains people only.
--   - Coverage Group store footprint never creates HC.
--   - Coverage Group legacy required_headcount remains ignored.
--   - CENCOM rollups inherit this through v_cencom_account_allocation_kpi.
-- ============================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4) AS filled_hc,
         count(DISTINCT a.employee_no) AS actual_hc
  FROM public.employee_store_allocations a
  WHERE a.is_active
  GROUP BY a.account_id
),
pipeline AS (
  SELECT he.account_id, count(*) AS pipeline_count
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.coverage_slot_id IS NULL
    AND COALESCE(v.is_archived, false) = false
    AND COALESCE(v.is_pool_vacancy, false) = false
  GROUP BY he.account_id
),
coverage_slot_kpi AS (
  SELECT
    cg.account_id,
    COUNT(*) FILTER (WHERE cs.slot_status = 'active')::numeric AS filled_hc,
    CASE
      WHEN COUNT(DISTINCT cs.current_occupant_plantilla_id)
           FILTER (WHERE cs.slot_status = 'active'
                   AND cs.current_occupant_plantilla_id IS NOT NULL) > 0
        THEN COUNT(DISTINCT cs.current_occupant_plantilla_id)
             FILTER (WHERE cs.slot_status = 'active'
                     AND cs.current_occupant_plantilla_id IS NOT NULL)
      ELSE COUNT(*) FILTER (WHERE cs.slot_status = 'active')
    END AS actual_hc,
    COUNT(*) FILTER (WHERE cs.slot_status = 'hr_processing') AS pipeline_count,
    COUNT(*) FILTER (WHERE cs.slot_status IN ('open', 'pipeline'))::numeric AS slot_vacant_hc
  FROM public.coverage_slots cs
  JOIN public.coverage_groups cg ON cg.id = cs.coverage_group_id
  WHERE cg.archived_at IS NULL
  GROUP BY cg.account_id
),
slot_vacant_non_roving AS (
  SELECT
    ps.account_id,
    COUNT(*) FILTER (WHERE ps.slot_status IN ('open', 'pipeline')) AS vacant_slots
  FROM public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON v.vcode = ps.legacy_vcode
   AND v.deleted_at IS NULL
   AND COALESCE(v.is_archived, false) = false
   AND COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving = false
    AND ps.legacy_vcode IS NOT NULL
    AND ps.account_id IS NOT NULL
  GROUP BY ps.account_id
),
slot_vacant_roving AS (
  SELECT
    ps.account_id,
    SUM(
      CASE WHEN ps.slot_status IN ('open', 'pipeline')
           THEN 1.0 / NULLIF(grp.total_slots::numeric, 0)
           ELSE 0.0
      END
    ) AS vacant_hc
  FROM public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id, COUNT(*) AS total_slots
    FROM public.plantilla_slots
    WHERE is_roving = true
      AND source_hc_request_id IS NOT NULL
    GROUP BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  WHERE ps.is_roving = true
    AND ps.source_hc_request_id IS NOT NULL
    AND ps.account_id IS NOT NULL
  GROUP BY ps.account_id
),
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM public.vacancies vv
  WHERE vv.status = 'Open'
    AND vv.deleted_at IS NULL
    AND COALESCE(vv.is_archived, false) = false
    AND COALESCE(vv.is_pool_vacancy, false) = false
    AND COALESCE(vv.affects_required_hc, true) = true
  GROUP BY vv.account_id
),
base AS (
  SELECT
    a.id AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    round(COALESCE(f.filled_hc, 0) + COALESCE(csk.filled_hc, 0), 4)::numeric(12,4) AS filled_hc,
    COALESCE(f.actual_hc, 0) + COALESCE(csk.actual_hc, 0) AS actual_hc,
    COALESCE(p.pipeline_count, 0) + COALESCE(csk.pipeline_count, 0) AS pipeline_count,
    COALESCE(v.open_hc, 0) AS open_hc,
    round(
      COALESCE(svn.vacant_slots, 0)::numeric
    + COALESCE(svr.vacant_hc, 0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    4)::numeric(12,4) AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc, 0)
    + COALESCE(csk.filled_hc, 0)
    + COALESCE(p.pipeline_count, 0)
    + COALESCE(csk.pipeline_count, 0)
    + COALESCE(svn.vacant_slots, 0)::numeric
    + COALESCE(svr.vacant_hc, 0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    4)::numeric(12,4) AS required_hc
  FROM public.accounts a
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN filled f ON f.account_id = a.id
  LEFT JOIN pipeline p ON p.account_id = a.id
  LEFT JOIN coverage_slot_kpi csk ON csk.account_id = a.id
  LEFT JOIN vacant v ON v.account_id = a.id
  LEFT JOIN slot_vacant_non_roving svn ON svn.account_id = a.id
  LEFT JOIN slot_vacant_roving svr ON svr.account_id = a.id
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false
    AND (public.i_have_full_access()
         OR a.id = ANY (public.get_my_allowed_account_ids()))
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc, actual_hc, pipeline_count,
  open_hc,
  required_hc,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(filled_hc / required_hc, 4) END AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round((filled_hc + pipeline_count) / required_hc, 4) END AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END AS pipeline_coverage,
  CASE WHEN required_hc = 0 THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 1.0 THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 0.9 THEN 'at_risk'::text
       ELSE 'critical'::text
  END AS health_status,
  slot_vacant_hc
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'OHM2026_0098: Allocation KPI includes approved roving HC Request demand from coverage_slots. Coverage pipeline slots count as vacant HC; coverage hr_processing slots count as pipeline/in-flight. Coverage Group store footprint and required_headcount are not HC sources.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

COMMIT;
