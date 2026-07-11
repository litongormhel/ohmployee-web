-- ============================================================================
-- OHM2026_1136 §2 — Drop vacancy join from slot_hr_processing CTEs
-- ============================================================================
--
-- Root cause:
--   20261210000000 replaced the hr_emploc-based pipeline CTE with slot-based
--   CTEs but kept INNER JOIN vacancies ... AND COALESCE(v.is_archived, false) = false
--   on both slot_hr_processing_non_roving and slot_hr_processing_roving.
--   A plantilla_slot with slot_status='hr_processing' whose legacy_vcode links
--   to an archived vacancy (is_archived = true) is silently excluded by the
--   INNER JOIN — the same archive-filter defect as the old hr_emploc CTE.
--
-- Fix:
--   slot_status = 'hr_processing' is the authoritative slot-state signal.
--   Remove the vacancy join from both HR-processing CTEs entirely.
--   Pool-vacancy or archive status of the linked vacancy is irrelevant:
--   if the slot says hr_processing, it IS hr_processing demand.
--
-- Identity preserved:
--   required_hc = filled_hc + pipeline_count + slot_vacant_hc
--              = Actual + HR Processing + Vacant (fully slot-based, no vacancy-status gaps)
--
-- Column types unchanged (all same as 20261025000000 and 20261210000000):
--   pipeline_count → bigint   (ROUND(...,0)::bigint preserved)
--   required_hc   → numeric(12,4)
--   filled_hc     → numeric(12,4)
--   slot_vacant_hc→ numeric(12,4)
--   actual_hc     → bigint
--   open_hc       → bigint
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
-- Slot-based HR Processing for non-roving stationary slots.
-- vacancy join intentionally removed: slot_status='hr_processing' is the
-- authoritative signal — the linked vacancy's archive status is irrelevant.
slot_hr_processing_non_roving AS (
  SELECT ps.account_id,
         COUNT(*) AS hr_processing_count
  FROM public.plantilla_slots ps
  WHERE ps.is_roving    = false
    AND ps.slot_status  = 'hr_processing'
    AND ps.account_id   IS NOT NULL
  GROUP BY ps.account_id
),
-- Slot-based HR Processing for roving non-coverage slots (fractional 1/N).
-- vacancy join intentionally removed for the same reason as above.
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
  WHERE ps.is_roving              = true
    AND ps.slot_status            = 'hr_processing'
    AND ps.source_hc_request_id   IS NOT NULL
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
    -- pipeline_count: slot-based HR Processing (no vacancy-archive gaps) + coverage pipeline.
    -- Cast to bigint to preserve existing view column type.
    -- Fractional roving precision is retained in required_hc at full numeric resolution.
    ROUND(
      COALESCE(hpnr.hr_processing_count, 0)::numeric
    + COALESCE(hpr.hr_processing_hc,    0)::numeric
    + COALESCE(csk.pipeline_count,       0)::numeric,
    0)::bigint                                                                       AS pipeline_count,
    COALESCE(v.open_hc, 0)                                                          AS open_hc,
    round(
      COALESCE(svn.vacant_slots,   0)::numeric
    + COALESCE(svr.vacant_hc,      0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    4)::numeric(12,4)                                                                AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc,              0)
    + COALESCE(csk.filled_hc,            0)
    + COALESCE(hpnr.hr_processing_count, 0)::numeric
    + COALESCE(hpr.hr_processing_hc,     0)::numeric
    + COALESCE(csk.pipeline_count,       0)::numeric
    + COALESCE(svn.vacant_slots,         0)::numeric
    + COALESCE(svr.vacant_hc,            0)::numeric
    + COALESCE(csk.slot_vacant_hc,       0)::numeric,
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
  'OHM2026_1136 §2: slot_hr_processing CTEs no longer join vacancies — '
  '  slot_status=hr_processing is the authoritative signal regardless of vacancy archive status. '
  'OHM2026_1136: pipeline_count uses slot-based hr_processing (non-roving + roving + coverage). '
  '  required_hc = filled_hc + pipeline_count + slot_vacant_hc = Actual + HR + Vacant. '
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
  'Allocation-based per-account KPI restricted to CENCOM groups (cencom_scope=true). '
  'OHM2026_1136 §2: refreshed to inherit vacancy-join-free slot_hr_processing fix.';
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
  'Allocation-based per-group CENCOM KPI (Group 1–5). '
  'OHM2026_1136 §2: refreshed to inherit vacancy-join-free slot_hr_processing fix. '
  'OHM2026_0073: slot_vacant_hc + required_hc slot-based. '
  'OHM2026_0079: mfr safe-zero when required_hc = 0.';
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
  'Allocation-based aggregate CENCOM KPI. '
  'OHM2026_1136 §2: refreshed to inherit vacancy-join-free slot_hr_processing fix; '
  '  required_hc now correctly includes all hr_processing slots regardless of vacancy archive status. '
  'OHM2026_0073: slot_vacant_hc added. '
  'OHM2026_0079: mfr safe-zero when required_hc = 0.';
GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated, service_role;


COMMIT;


-- ============================================================================
-- SMOKE TEST (run in Supabase SQL Editor after applying)
-- ============================================================================

/*
-- Slot identity: actual + pipeline_count + slot_vacant_hc ≈ required_hc
SELECT
  account_name,
  actual_hc,
  pipeline_count        AS hr_processing,
  slot_vacant_hc        AS vacant,
  required_hc,
  round(actual_hc::numeric + pipeline_count + slot_vacant_hc, 0) AS computed_required,
  ABS(round(actual_hc::numeric + pipeline_count + slot_vacant_hc, 0) - round(required_hc, 0)) <= 1
    AS identity_holds
FROM public.v_account_allocation_kpi
ORDER BY account_name;
-- Expected: identity_holds = true for every row.
-- Reference account (4 actual, 1 hr_processing, 4 vacant): required_hc = 9.

-- CENCOM aggregate must also show 9 for that account scope:
SELECT actual_hc, pipeline_count AS hr_processing, slot_vacant_hc AS vacant, required_hc
FROM public.v_cencom_allocation_kpi;
*/
