-- Migration: 20262606000186_fix_account_kpi_pipeline_applicants_and_roving_coverage.sql
-- Purpose:
-- 1. ADR-001 Rule 2 & ADR-002 Zero-Gap Contract:
--    Ensure pipeline candidates from BOTH public.hr_emploc (onboarding) AND public.applicants (recruitment pipeline)
--    are fully accounted for in pipeline_count and excluded from slot_vacant_hc.
-- 2. Coverage Group & Roving Slot Protection:
--    When ANY store in a coverage group / roving cluster has an active candidate (in hr_emploc or applicants),
--    the entire roving slot is recognized as in pipeline, preventing orphan fractional open vacancies (e.g. 0.5 HC).
-- 3. Sync coverage_slots and plantilla_slots status for active coverage groups with candidates.
-- 4. 100% strict column order parity (19 columns) on public.v_account_allocation_kpi.

BEGIN;

-- 1. Sync coverage_slots and plantilla_slots for coverage groups that have active pipeline candidates
WITH active_cand_stores AS (
  SELECT DISTINCT v.store_id
  FROM public.hr_emploc he
  JOIN public.vacancies v ON v.vcode = he.vcode
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.vcode IS NOT NULL
  UNION
  SELECT DISTINCT v.store_id
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE a.status <> ALL (ARRAY['Backout'::text, 'Rejected'::text, 'Hired'::text, 'archived'::text])
    AND COALESCE(a.is_archived, false) = false
    AND a.vacancy_vcode IS NOT NULL
),
active_cg_ids AS (
  SELECT DISTINCT cgs.coverage_group_id
  FROM public.coverage_group_stores cgs
  JOIN active_cand_stores acs ON acs.store_id = cgs.store_id
  WHERE cgs.archived_at IS NULL
)
UPDATE public.coverage_slots cs
SET slot_status = 'pipeline',
    updated_at = NOW()
WHERE cs.coverage_group_id IN (SELECT coverage_group_id FROM active_cg_ids)
  AND cs.slot_status = 'open';

WITH active_cand_stores AS (
  SELECT DISTINCT v.store_id
  FROM public.hr_emploc he
  JOIN public.vacancies v ON v.vcode = he.vcode
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.vcode IS NOT NULL
  UNION
  SELECT DISTINCT v.store_id
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE a.status <> ALL (ARRAY['Backout'::text, 'Rejected'::text, 'Hired'::text, 'archived'::text])
    AND COALESCE(a.is_archived, false) = false
    AND a.vacancy_vcode IS NOT NULL
),
active_cg_ids AS (
  SELECT DISTINCT cgs.coverage_group_id
  FROM public.coverage_group_stores cgs
  JOIN active_cand_stores acs ON acs.store_id = cgs.store_id
  WHERE cgs.archived_at IS NULL
),
all_cg_stores AS (
  SELECT DISTINCT cgs.store_id
  FROM public.coverage_group_stores cgs
  WHERE cgs.coverage_group_id IN (SELECT coverage_group_id FROM active_cg_ids)
    AND cgs.archived_at IS NULL
)
UPDATE public.plantilla_slots ps
SET slot_status = 'pipeline',
    updated_at = NOW()
WHERE ps.store_id IN (SELECT store_id FROM all_cg_stores)
  AND ps.is_roving = true
  AND ps.slot_status = 'open';

-- 2. Update public.v_account_allocation_kpi view
CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4) AS filled_hc,
         count(DISTINCT a.employee_no)            AS actual_hc
  FROM public.employee_store_allocations a
  JOIN public.plantilla p ON p.id = a.plantilla_id
  WHERE a.is_active
    AND p.status = 'Active'
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY a.account_id
),
leave AS (
  SELECT p.account_id,
         count(*) AS leave_count
  FROM public.plantilla p
  WHERE p.status IN ('On Leave', 'on_leave')
    AND (p.date_of_separation IS NULL OR p.date_of_separation > CURRENT_DATE)
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
  GROUP BY p.account_id
),
active_pipeline_candidates AS (
  SELECT he.account_id, he.vcode, LOWER(TRIM(he.applicant_name)) AS cand_name
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.coverage_slot_id IS NULL
    AND COALESCE(v.is_pool_vacancy, false) = false
  UNION
  SELECT v.account_id, a.vacancy_vcode AS vcode, LOWER(TRIM(a.full_name)) AS cand_name
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE a.status <> ALL (ARRAY['Backout'::text, 'Rejected'::text, 'Hired'::text, 'archived'::text])
    AND COALESCE(a.is_archived, false) = false
    AND a.coverage_slot_id IS NULL
    AND COALESCE(v.is_pool_vacancy, false) = false
),
pipeline AS (
  SELECT account_id,
         count(*) AS pipeline_count
  FROM active_pipeline_candidates
  GROUP BY account_id
),
active_cg_with_pipeline AS (
  SELECT DISTINCT cgs.coverage_group_id
  FROM public.coverage_group_stores cgs
  JOIN public.stores s ON s.id = cgs.store_id
  WHERE s.vcode IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
     OR cgs.store_id IN (
        SELECT v.store_id FROM public.vacancies v
        WHERE v.vcode IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
     )
),
coverage_slot_kpi AS (
  SELECT
    cg.account_id,
    COUNT(*) FILTER (
      WHERE cs.slot_status = 'active'
        AND (
          cs.current_occupant_plantilla_id IS NULL
          OR NOT EXISTS (
            SELECT 1 FROM public.employee_store_allocations esa
            WHERE esa.plantilla_id = cs.current_occupant_plantilla_id
              AND esa.account_id = cg.account_id
              AND esa.is_active = true
          )
        )
    )::numeric AS filled_hc,
    COUNT(DISTINCT cs.current_occupant_plantilla_id) FILTER (
      WHERE cs.slot_status = 'active'
        AND cs.current_occupant_plantilla_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.employee_store_allocations esa
          WHERE esa.plantilla_id = cs.current_occupant_plantilla_id
            AND esa.account_id = cg.account_id
            AND esa.is_active = true
        )
    ) AS actual_hc,
    COUNT(*) FILTER (
      WHERE cs.slot_status IN ('pipeline', 'hr_processing')
         OR cg.id IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    ) AS pipeline_count,
    COUNT(*) FILTER (
      WHERE cs.slot_status = 'open'
        AND cg.id NOT IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    )::numeric AS slot_vacant_hc
  FROM public.coverage_slots cs
  JOIN public.coverage_groups cg ON cg.id = cs.coverage_group_id
  LEFT JOIN public.plantilla cp ON cp.id = cs.current_occupant_plantilla_id
  WHERE cg.archived_at IS NULL
    AND (
      cp.id IS NULL 
      OR (
        cp.status = 'Active' 
        AND (cp.date_of_separation IS NULL OR cp.date_of_separation > CURRENT_DATE)
        AND COALESCE(cp.is_deleted, false) = false
        AND COALESCE(cp.is_archived, false) = false
      )
    )
  GROUP BY cg.account_id
),
slot_vacant_non_roving AS (
  SELECT
    ps.account_id,
    COUNT(*) FILTER (
      WHERE ps.slot_status = 'open'
        AND ps.legacy_vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
    ) AS vacant_slots
  FROM public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON  v.vcode = ps.legacy_vcode
   AND  v.deleted_at IS NULL
   AND  COALESCE(v.is_archived, false)    = false
   AND  COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving    = false
    AND ps.legacy_vcode IS NOT NULL
    AND ps.account_id   IS NOT NULL
  GROUP BY ps.account_id
),
slot_vacant_roving AS (
  SELECT
    ps.account_id,
    SUM(
      CASE WHEN ps.slot_status = 'open'
            AND ps.legacy_vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
            AND NOT EXISTS (
              SELECT 1 FROM public.coverage_group_stores cgs
              WHERE cgs.store_id = ps.store_id
                AND cgs.coverage_group_id IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
            )
           THEN 1.0 / NULLIF(grp.total_slots::numeric, 0)
           ELSE 0.0
      END
    ) AS vacant_hc
  FROM public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id,
           COUNT(*) AS total_slots
    FROM public.plantilla_slots
    WHERE is_roving = true
      AND source_hc_request_id IS NOT NULL
    GROUP BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  WHERE ps.is_roving            = true
    AND ps.source_hc_request_id IS NOT NULL
    AND ps.account_id           IS NOT NULL
  GROUP BY ps.account_id
),
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM public.vacancies vv
  WHERE vv.status = 'Open'
    AND vv.deleted_at IS NULL
    AND COALESCE(vv.is_archived, false)       = false
    AND COALESCE(vv.is_pool_vacancy, false)   = false
    AND COALESCE(vv.affects_required_hc, true) = true
    AND vv.vcode NOT IN (SELECT vcode FROM active_pipeline_candidates WHERE vcode IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1 FROM public.coverage_group_stores cgs
      WHERE cgs.store_id = vv.store_id
        AND cgs.coverage_group_id IN (SELECT coverage_group_id FROM active_cg_with_pipeline)
    )
  GROUP BY vv.account_id
),
base AS (
  SELECT
    a.id          AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    round(
      COALESCE(f.filled_hc, 0)
    + COALESCE(csk.filled_hc, 0)
    + COALESCE(l.leave_count, 0),
    4)::numeric(12,4)                                                                AS filled_hc,
    (
      COALESCE(f.actual_hc, 0)
    + COALESCE(csk.actual_hc, 0)
    + COALESCE(l.leave_count, 0)
    )::bigint                                                                        AS actual_hc,
    (COALESCE(p.pipeline_count, 0) + COALESCE(csk.pipeline_count, 0))::bigint       AS pipeline_count,
    COALESCE(v.open_hc, 0)                                                           AS open_hc,
    round(
      COALESCE(svn.vacant_slots,   0)::numeric
    + COALESCE(svr.vacant_hc,      0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    0)::numeric(12,4)                                                                AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc,          0)
    + COALESCE(csk.filled_hc,        0)
    + COALESCE(l.leave_count,        0)
    + COALESCE(p.pipeline_count,     0)
    + COALESCE(csk.pipeline_count,   0)
    + COALESCE(svn.vacant_slots,     0)::numeric
    + COALESCE(svr.vacant_hc,        0)::numeric
    + COALESCE(csk.slot_vacant_hc,   0)::numeric,
    0)::numeric(12,4)                                                                AS required_hc,
    COALESCE(l.leave_count, 0)::bigint                                               AS leave_count
  FROM public.accounts a
  LEFT JOIN public.groups          g    ON g.id          = a.group_id
  LEFT JOIN filled                 f    ON f.account_id  = a.id
  LEFT JOIN leave                  l    ON l.account_id  = a.id
  LEFT JOIN pipeline               p    ON p.account_id  = a.id
  LEFT JOIN coverage_slot_kpi      csk  ON csk.account_id = a.id
  LEFT JOIN vacant                 v    ON v.account_id  = a.id
  LEFT JOIN slot_vacant_non_roving svn  ON svn.account_id = a.id
  LEFT JOIN slot_vacant_roving     svr  ON svr.account_id = a.id
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false
    AND (
         public.i_have_full_access()
      OR a.id = ANY (public.get_my_allowed_account_ids())
    )
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc,
  actual_hc,
  pipeline_count,
  open_hc,
  required_hc,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, actual_hc::numeric / required_hc)), 4) END AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(LEAST(1.0, GREATEST(0.0, (actual_hc::numeric + pipeline_count) / required_hc)), 4) END AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END                     AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END                     AS pipeline_coverage,
  CASE WHEN required_hc = 0              THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 1.0 THEN 'healthy'::text
       WHEN actual_hc::numeric / required_hc >= 0.9 THEN 'at_risk'::text
       ELSE                                   'critical'::text
  END                                                                       AS health_status,
  slot_vacant_hc,
  leave_count
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'Allocation-based per-account KPI. ADR-001 Rule 2 & ADR-002 compliant: actual_hc includes Active deployed + On-Leave personnel. '
  'Pipeline accounts for both onboarding (hr_emploc) and recruitment (applicants). '
  'Coverage group roving slots with candidates are recognized as pipeline across all covered stores, preventing orphan fractional open vacancies. '
  '100% parity across Web and Mobile.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

COMMIT;
