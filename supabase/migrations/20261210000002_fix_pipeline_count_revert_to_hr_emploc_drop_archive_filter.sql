-- ============================================================================
-- OHM2026_1136 §3 — Revert pipeline_count to hr_emploc source; drop archive filter
-- ============================================================================
--
-- Why the slot-based approach (§1 / §2) did not fix CENCOM Required=8:
--   plantilla_slots.slot_status is NOT reliably updated to 'hr_processing'
--   when an hr_emploc record is created — in particular for applicants whose
--   vacancy was processed before slot-state tracking was implemented, or where
--   the workflow transition did not fire the slot-status update.
--   The slot query therefore returns 0 for the affected account even after
--   removing the vacancy join in §2.
--
-- Why Dashboard showed 9 but CENCOM showed 8:
--   dashboard_screen.dart computes Required = Actual + HR + Vacant via DIRECT
--   queries (hr_emploc count has no archive filter). CENCOM reads
--   v_cencom_allocation_kpi.required_hc from the view chain, which did not
--   count the 1 hr_emploc record whose linked vacancy was archived.
--
-- Fix:
--   Revert pipeline_count to hr_emploc-based counting (authoritative source)
--   and drop ONLY the archive filter that caused Required=8.
--   Keep coverage_slot_id IS NULL to avoid double-counting with csk.pipeline_count.
--   Keep is_pool_vacancy filter.
--
-- Retained from slot-based migrations:
--   coverage_slot_kpi  — unchanged (counts coverage positions in pipeline/hr_processing)
--   slot_vacant_*      — unchanged (slot-based vacancy is correct and working)
--   ROUND(...)::bigint — pipeline_count remains bigint (preserves column type)
--
-- Views recreated (dependency order):
--   §1  v_account_allocation_kpi
--   §2  v_cencom_account_allocation_kpi
--   §3  v_cencom_group_allocation_kpi
--   §4  v_cencom_allocation_kpi
-- ============================================================================

BEGIN;

-- ── §1  v_account_allocation_kpi ─────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4) AS filled_hc,
         count(DISTINCT a.employee_no)            AS actual_hc
  FROM public.employee_store_allocations a
  WHERE a.is_active
  GROUP BY a.account_id
),
-- OHM2026_1136 §3: hr_emploc-based pipeline count (authoritative source).
-- Restored from pre-§1 approach. Archive filter intentionally removed:
-- an active hr_emploc record IS pipeline demand regardless of vacancy archive status.
-- coverage_slot_id IS NULL: coverage-linked hr_emploc records are counted by
-- coverage_slot_kpi.pipeline_count instead to avoid double-counting.
pipeline AS (
  SELECT he.account_id,
         count(*) AS pipeline_count
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.coverage_slot_id IS NULL
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
    COUNT(*) FILTER (WHERE cs.slot_status IN ('pipeline', 'hr_processing')) AS pipeline_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'open')::numeric                AS slot_vacant_hc
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
      CASE WHEN ps.slot_status IN ('open', 'pipeline')
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
    round(COALESCE(f.filled_hc, 0) + COALESCE(csk.filled_hc, 0), 4)::numeric(12,4) AS filled_hc,
    COALESCE(f.actual_hc, 0)  + COALESCE(csk.actual_hc, 0)                          AS actual_hc,
    -- Cast to bigint to preserve existing view column type.
    (COALESCE(p.pipeline_count, 0) + COALESCE(csk.pipeline_count, 0))::bigint       AS pipeline_count,
    COALESCE(v.open_hc, 0)                                                           AS open_hc,
    round(
      COALESCE(svn.vacant_slots,   0)::numeric
    + COALESCE(svr.vacant_hc,      0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    4)::numeric(12,4)                                                                AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc,          0)
    + COALESCE(csk.filled_hc,        0)
    + COALESCE(p.pipeline_count,     0)
    + COALESCE(csk.pipeline_count,   0)
    + COALESCE(svn.vacant_slots,     0)::numeric
    + COALESCE(svr.vacant_hc,        0)::numeric
    + COALESCE(csk.slot_vacant_hc,   0)::numeric,
    4)::numeric(12,4)                                                                AS required_hc
  FROM public.accounts a
  LEFT JOIN public.groups          g    ON g.id          = a.group_id
  LEFT JOIN filled                 f    ON f.account_id  = a.id
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
       ELSE round(filled_hc / required_hc, 4) END                          AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round((filled_hc + pipeline_count) / required_hc, 4) END       AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END                     AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END                     AS pipeline_coverage,
  CASE WHEN required_hc = 0              THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 1.0 THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 0.9 THEN 'at_risk'::text
       ELSE                                   'critical'::text
  END                                                                       AS health_status,
  slot_vacant_hc
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'Allocation-based per-account KPI. '
  'OHM2026_1136 §3: pipeline_count reverted to hr_emploc source (slot_status not reliably '
  '  updated for pre-slot-tracking records). Archive filter removed: active hr_emploc IS demand. '
  'OHM2026_0073: slot_vacant_hc = non-roving COUNT(open,pipeline) + roving 1/N + coverage open. '
  'OHM2026_0079: mfr/projected_mfr return 0.0 (not 1.0) when required_hc = 0.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;


-- ── §2  v_cencom_account_allocation_kpi ──────────────────────────────────────

CREATE OR REPLACE VIEW public.v_cencom_account_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT ak.*
FROM   public.v_account_allocation_kpi ak
JOIN   public.groups g ON g.id = ak.group_id
WHERE  g.cencom_scope = true;

ALTER VIEW public.v_cencom_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_account_allocation_kpi IS
  'Per-account KPI restricted to CENCOM groups (cencom_scope=true). '
  'OHM2026_1136 §3: refreshed to inherit hr_emploc-based pipeline_count fix.';
GRANT SELECT ON public.v_cencom_account_allocation_kpi TO authenticated, service_role;


-- ── §3  v_cencom_group_allocation_kpi ────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_cencom_group_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  group_id, group_name, group_code,
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  round(sum(pipeline_count), 0)::bigint  AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,
  round(sum(required_hc), 4)             AS required_hc,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                         THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0     THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9     THEN 'at_risk'::text
       ELSE                                                   'critical'::text
  END                                                                      AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc
FROM public.v_cencom_account_allocation_kpi
GROUP BY group_id, group_name, group_code;

ALTER VIEW public.v_cencom_group_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_group_allocation_kpi IS
  'Per-group CENCOM KPI. OHM2026_1136 §3: refreshed to inherit hr_emploc pipeline fix.';
GRANT SELECT ON public.v_cencom_group_allocation_kpi TO authenticated, service_role;


-- ── §4  v_cencom_allocation_kpi ──────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_cencom_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  round(sum(pipeline_count), 0)::bigint  AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,
  round(sum(required_hc), 4)             AS required_hc,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                         THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0     THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9     THEN 'at_risk'::text
       ELSE                                                   'critical'::text
  END                                                                      AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc
FROM public.v_cencom_account_allocation_kpi;

ALTER VIEW public.v_cencom_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_allocation_kpi IS
  'Aggregate CENCOM KPI. OHM2026_1136 §3: pipeline_count via hr_emploc (archive filter removed). '
  'required_hc = filled_hc + pipeline_count(hr_emploc) + slot_vacant_hc.';
GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated, service_role;


COMMIT;


-- ============================================================================
-- VERIFICATION QUERY (run in Supabase SQL Editor after applying)
-- ============================================================================

/*
-- 1. Confirm the specific account now shows pipeline_count = 1, required_hc = 9:
SELECT account_name, actual_hc, pipeline_count AS hr_processing,
       slot_vacant_hc AS vacant, required_hc, mfr, projected_mfr
FROM public.v_account_allocation_kpi
ORDER BY account_name;

-- 2. Confirm CENCOM aggregate also shows required_hc = 9:
SELECT actual_hc, pipeline_count AS hr_processing,
       slot_vacant_hc AS vacant, required_hc, mfr
FROM public.v_cencom_allocation_kpi;

-- 3. Cross-check pipeline_count against direct hr_emploc count:
SELECT
  kpi.account_name,
  kpi.pipeline_count AS kpi_pipeline,
  he_count.cnt       AS direct_hr_emploc_count
FROM public.v_account_allocation_kpi kpi
JOIN (
  SELECT he.account_id, count(*) AS cnt
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.coverage_slot_id IS NULL
    AND COALESCE(v.is_pool_vacancy, false) = false
  GROUP BY he.account_id
) he_count ON he_count.account_id = kpi.account_id
ORDER BY kpi.account_name;
-- Expected: kpi_pipeline = direct_hr_emploc_count for every row.
-- (kpi_pipeline may be higher when coverage positions also have pipeline/hr_processing slots.)
*/
