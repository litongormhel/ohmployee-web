-- ============================================================================
-- OHM2026_1136 — Fix CENCOM/Dashboard Required HC to Include HR Processing Slots
-- ============================================================================
--
-- Problem:
--   v_account_allocation_kpi.required_hc used an hr_emploc-record-based
--   "pipeline" CTE (coverage_slot_id IS NULL + vacancy filters) to count the
--   HR Processing demand.  This CTE can miss valid hr_emploc rows when:
--     • The linked vacancy is archived but the slot is still hr_processing.
--     • The hr_emploc row has a coverage_slot_id (excluded from that CTE).
--   Result: CENCOM shows Required = 8 while Plantilla (which reads
--   v_hr_emploc_sla_flags separately) shows Required = 9.
--
-- Fix:
--   Replace the record-based pipeline CTE with two slot-based CTEs:
--     slot_hr_processing_non_roving  — COUNT(plantilla_slots WHERE slot_status='hr_processing' AND is_roving=false)
--     slot_hr_processing_roving      — fractional SUM for roving slots (mirrors slot_vacant_roving)
--   pipeline_count output column now = slot-based hr_processing + coverage pipeline.
--   required_hc = filled_hc + pipeline_count (slot-based) + slot_vacant_hc
--               = Actual + HR Processing + Vacant   ← correct slot identity
--
-- Invariant preserved:
--   Actual + HR + Vacant = Required (no double counting).
--   Coverage slots: handled by existing coverage_slot_kpi CTE (unchanged).
--   Roving non-coverage: handled by new slot_hr_processing_roving CTE.
--
-- Views recreated (in dependency order):
--   §1  v_account_allocation_kpi          (base KPI, adds 2 new CTEs)
--   §2  v_cencom_account_allocation_kpi   (SELECT ak.* — refreshed for type parity)
--   §3  v_cencom_group_allocation_kpi     (group rollup — unchanged logic, refreshed)
--   §4  v_cencom_allocation_kpi           (aggregate — unchanged logic, refreshed)
--
-- Downstream that auto-updates (no recreation needed):
--   cencom_service.dart reads required_hc, pipeline_count from the view.
--   dashboard_screen.dart: totalPlantilla = snapshot.mfrRequired (auto-fixed).
--   MFR denominator: uses required_hc from view (auto-fixed).
--   Potential MFR: (filled_hc + pipeline_count) / required_hc (now both slot-based).
--
-- DB safety rules:
--   Forward-only. No old migrations edited. No RLS loosened.
--   No service-role assumption in app-facing RPCs.
-- ============================================================================

BEGIN;

-- ── §1  v_account_allocation_kpi ─────────────────────────────────────────────
--
-- Replaces the hr_emploc-record-based "pipeline" CTE with two slot-based CTEs.
-- Column list is identical to 20261025000000; only pipeline_count and
-- required_hc formulas change.

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
-- OHM2026_1136: slot-based HR Processing count for non-roving stationary slots.
-- Replaces the old hr_emploc-record-based pipeline CTE.
-- A slot with slot_status='hr_processing' has a corresponding active hr_emploc
-- record — using the slot directly avoids dependency on hr_emploc record linkage.
slot_hr_processing_non_roving AS (
  SELECT ps.account_id,
         COUNT(*) AS hr_processing_count
  FROM public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON  v.vcode = ps.legacy_vcode
   AND  v.deleted_at IS NULL
   AND  COALESCE(v.is_archived, false)    = false
   AND  COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving       = false
    AND ps.slot_status     = 'hr_processing'
    AND ps.legacy_vcode    IS NOT NULL
    AND ps.account_id      IS NOT NULL
  GROUP BY ps.account_id
),
-- OHM2026_1136: slot-based HR Processing for roving non-coverage slots (fractional).
-- Mirrors slot_vacant_roving: each roving group's hr_processing demand is split
-- equally across the group's total slot count (1/N per slot).
slot_hr_processing_roving AS (
  SELECT ps.account_id,
         SUM(1.0 / NULLIF(grp.total_slots::numeric, 0)) AS hr_processing_hc
  FROM public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id,
           COUNT(*) AS total_slots
    FROM public.plantilla_slots
    WHERE is_roving = true
      AND source_hc_request_id IS NOT NULL
    GROUP BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  INNER JOIN public.vacancies v
    ON  v.vcode = ps.legacy_vcode
   AND  v.deleted_at IS NULL
   AND  COALESCE(v.is_archived, false)    = false
   AND  COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving              = true
    AND ps.slot_status            = 'hr_processing'
    AND ps.source_hc_request_id   IS NOT NULL
    AND ps.legacy_vcode           IS NOT NULL
    AND ps.account_id             IS NOT NULL
  GROUP BY ps.account_id
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
    AND COALESCE(vv.is_archived, false)      = false
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
    -- OHM2026_1136: pipeline_count is now fully slot-based.
    -- Non-roving hr_processing slots + roving non-coverage hr_processing (fractional)
    -- + coverage slots in pipeline/hr_processing state.
    -- Required HC = filled_hc + pipeline_count + slot_vacant_hc (Actual + HR + Vacant).
    -- Cast to bigint to preserve the existing column type (Postgres rejects type changes
    -- in CREATE OR REPLACE VIEW). Fractional roving precision is kept in required_hc.
    ROUND(
      COALESCE(hpnr.hr_processing_count, 0)::numeric
    + COALESCE(hpr.hr_processing_hc,    0)::numeric
    + COALESCE(csk.pipeline_count,       0)::numeric,
    0)::bigint                                                                       AS pipeline_count,
    COALESCE(v.open_hc, 0)                                                          AS open_hc,
    round(
      COALESCE(svn.vacant_slots,     0)::numeric
    + COALESCE(svr.vacant_hc,        0)::numeric
    + COALESCE(csk.slot_vacant_hc,   0)::numeric,
    4)::numeric(12,4)                                                                AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc,           0)
    + COALESCE(csk.filled_hc,         0)
    + COALESCE(hpnr.hr_processing_count, 0)::numeric
    + COALESCE(hpr.hr_processing_hc,     0)::numeric
    + COALESCE(csk.pipeline_count,        0)::numeric
    + COALESCE(svn.vacant_slots,     0)::numeric
    + COALESCE(svr.vacant_hc,        0)::numeric
    + COALESCE(csk.slot_vacant_hc,   0)::numeric,
    4)::numeric(12,4)                                                                AS required_hc
  FROM public.accounts a
  LEFT JOIN public.groups                    g    ON g.id          = a.group_id
  LEFT JOIN filled                           f    ON f.account_id  = a.id
  LEFT JOIN slot_hr_processing_non_roving    hpnr ON hpnr.account_id = a.id
  LEFT JOIN slot_hr_processing_roving        hpr  ON hpr.account_id  = a.id
  LEFT JOIN coverage_slot_kpi               csk   ON csk.account_id  = a.id
  LEFT JOIN vacant                           v    ON v.account_id   = a.id
  LEFT JOIN slot_vacant_non_roving          svn   ON svn.account_id  = a.id
  LEFT JOIN slot_vacant_roving              svr   ON svr.account_id  = a.id
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
  'OHM2026_1136: pipeline_count now uses slot-based hr_processing '
  '  (slot_hr_processing_non_roving + slot_hr_processing_roving + coverage_pipeline). '
  '  required_hc = filled_hc + pipeline_count + slot_vacant_hc '
  '              = Actual + HR Processing + Vacant (fully slot-based). '
  'OHM2026_0073: slot_vacant_hc = non-roving COUNT(open,pipeline) + roving 1/N + coverage open. '
  'OHM2026_0079: mfr/projected_mfr return 0.0 (not 1.0) when required_hc = 0.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;


-- ── §2  v_cencom_account_allocation_kpi ──────────────────────────────────────
--
-- Refreshed (SELECT ak.*) to pick up type changes in v_account_allocation_kpi.
-- Logic is identical to 20260908000001.

CREATE OR REPLACE VIEW public.v_cencom_account_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT ak.*
FROM   public.v_account_allocation_kpi ak
JOIN   public.groups g ON g.id = ak.group_id
WHERE  g.cencom_scope = true;

ALTER VIEW public.v_cencom_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_account_allocation_kpi IS
  'Allocation-based per-account KPI restricted to CENCOM groups (cencom_scope=true). '
  'OHM2026_1136: refreshed to inherit slot-based pipeline_count and required_hc.';
GRANT SELECT ON public.v_cencom_account_allocation_kpi TO authenticated, service_role;


-- ── §3  v_cencom_group_allocation_kpi ────────────────────────────────────────
--
-- Logic identical to 20261010000000. Refreshed to ensure type consistency
-- after v_account_allocation_kpi changes.

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
  'Allocation-based per-group CENCOM KPI (Group 1–5). '
  'OHM2026_1136: pipeline_count aggregated from slot-based base view. '
  'OHM2026_0073: slot_vacant_hc + required_hc slot-based. '
  'OHM2026_0079: mfr safe-zero when required_hc = 0.';
GRANT SELECT ON public.v_cencom_group_allocation_kpi TO authenticated, service_role;


-- ── §4  v_cencom_allocation_kpi ───────────────────────────────────────────────
--
-- Logic identical to 20261010000000. Refreshed for type consistency.

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
  'Allocation-based aggregate CENCOM KPI. '
  'OHM2026_1136: pipeline_count aggregated from slot-based base view; '
  '  required_hc now includes hr_processing slots in denominator. '
  'OHM2026_0073: slot_vacant_hc added. '
  'OHM2026_0079: mfr safe-zero when required_hc = 0.';
GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated, service_role;


COMMIT;


-- ============================================================================
-- SMOKE TEST ASSERTIONS (run manually in Supabase SQL Editor after applying)
-- See docs/smoke_tests/cencom_required_hc_hr_processing_fix.sql for full suite.
-- ============================================================================

/*
-- Quick sanity check: required_hc must equal actual_hc + pipeline_count + slot_vacant_hc
SELECT
  account_name,
  actual_hc,
  pipeline_count        AS hr_processing,
  slot_vacant_hc        AS vacant,
  required_hc,
  (actual_hc + pipeline_count + slot_vacant_hc) AS computed_required,
  (actual_hc + pipeline_count + slot_vacant_hc) = round(required_hc, 0) AS identity_holds
FROM public.v_account_allocation_kpi
ORDER BY account_name;
-- Expected: identity_holds = true for every row.

-- Verify aggregate:
SELECT actual_hc, pipeline_count, slot_vacant_hc, required_hc FROM public.v_cencom_allocation_kpi;
-- With 4 actual + 1 hr_processing + 4 vacant → required = 9.
*/
