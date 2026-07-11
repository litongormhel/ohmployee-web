-- ============================================================
-- OHM2026_0079 — Fix Orphaned ESA + MFR Safe-Zero (Ordered Fix)
-- Migration:  20261010000000_fix_orphaned_esa_mfr_safe_zero_v2.sql
-- Depends on: 20260908000001_slot_based_vacant_hc_v1.sql (must already be applied)
-- Supersedes: 20260608100000_fix_orphaned_esa_and_mfr_safe_zero.sql
--             (that migration had a 20260608 prefix so it ran BEFORE 20260908000001
--              and its THEN 0.0 fix was silently overwritten by THEN 1.0 in
--              20260908000001. This migration re-applies the correct values.)
-- ============================================================
-- Root causes addressed:
--
-- §1  Orphaned employee_store_allocations rows from QA archive reset.
--     fn_qa_archive_operational_data_reset archived Plantilla but did NOT
--     deactivate the linked ESA rows. These orphaned rows cause
--     v_cencom_allocation_kpi to report:
--       required_hc = actual_hc = N (e.g. 13)  (should be 0 post-reset)
--       mfr = N/N+open_hc (e.g. 76.5%)         (should be 0%)
--
-- §2  v_account_allocation_kpi MFR safe-zero.
--     20260908000001 uses THEN 1.0 when required_hc = 0.
--     Correct value is 0.0 (an empty system has 0% MFR, not 100%).
--
-- §3  v_cencom_group_allocation_kpi — same safe-zero fix.
-- §4  v_cencom_allocation_kpi — same safe-zero fix.
-- §5  Smoke test assertions.
-- ============================================================

BEGIN;

-- ── §1. Deactivate orphaned active ESA rows ───────────────────────────────────
-- An ESA row is orphaned when its employee has no live (non-archived,
-- non-deleted) plantilla record. This is invariantly wrong — ESA is an active
-- deployment ledger and must stay in sync with Plantilla status.
-- After QA archive reset every active ESA row is orphaned by definition.
-- Idempotent: rows that already have is_active = false are untouched.

DO $$
DECLARE
  v_deactivated integer;
BEGIN
  UPDATE public.employee_store_allocations esa
  SET
    is_active     = false,
    effective_end = CURRENT_DATE
  WHERE esa.is_active = true
    AND NOT EXISTS (
      SELECT 1
      FROM   public.plantilla p
      WHERE  p.employee_no             = esa.employee_no
        AND  COALESCE(p.is_archived, false) = false
        AND  COALESCE(p.is_deleted,  false) = false
    );

  GET DIAGNOSTICS v_deactivated = ROW_COUNT;

  RAISE NOTICE '§1 orphaned ESA rows deactivated: %', v_deactivated;
END;
$$;


-- ── §2. v_account_allocation_kpi — mfr/projected_mfr safe-zero ───────────────
-- Identical to 20260908000001 except THEN 1.0 → THEN 0.0 for mfr/projected_mfr.

CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4)   AS filled_hc,
         count(DISTINCT a.employee_no)             AS actual_hc
  FROM   public.employee_store_allocations a
  WHERE  a.is_active
  GROUP  BY a.account_id
),
pipeline AS (
  SELECT he.account_id, count(*) AS pipeline_count
  FROM   public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE  he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND  he.deleted_at IS NULL
    AND  COALESCE(v.is_archived, false) = false
    AND  COALESCE(v.is_pool_vacancy, false) = false
  GROUP  BY he.account_id
),
slot_vacant_non_roving AS (
  SELECT
    ps.account_id,
    COUNT(*) FILTER (WHERE ps.slot_status IN ('open', 'pipeline')) AS vacant_slots
  FROM   public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON  v.vcode = ps.legacy_vcode
    AND v.deleted_at IS NULL
    AND COALESCE(v.is_archived, false) = false
    AND COALESCE(v.is_pool_vacancy, false) = false
  WHERE  ps.is_roving    = false
    AND  ps.legacy_vcode IS NOT NULL
    AND  ps.account_id   IS NOT NULL
  GROUP  BY ps.account_id
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
  FROM   public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id, COUNT(*) AS total_slots
    FROM   public.plantilla_slots
    WHERE  is_roving = true
      AND  source_hc_request_id IS NOT NULL
    GROUP  BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  WHERE  ps.is_roving            = true
    AND  ps.source_hc_request_id IS NOT NULL
    AND  ps.account_id           IS NOT NULL
  GROUP  BY ps.account_id
),
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM   public.vacancies vv
  WHERE  vv.status = 'Open'
    AND  vv.deleted_at IS NULL
    AND  COALESCE(vv.is_archived, false) = false
    AND  COALESCE(vv.is_pool_vacancy, false) = false
    AND  COALESCE(vv.affects_required_hc, true) = true
  GROUP  BY vv.account_id
),
base AS (
  SELECT
    a.id                                     AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    COALESCE(f.filled_hc,  0)::numeric(12,4) AS filled_hc,
    COALESCE(f.actual_hc,  0)                AS actual_hc,
    COALESCE(p.pipeline_count, 0)            AS pipeline_count,
    COALESCE(v.open_hc, 0)                   AS open_hc,  -- kept; deprecated for Vacant display
    round(
      COALESCE(svn.vacant_slots, 0)::numeric
    + COALESCE(svr.vacant_hc, 0)::numeric,
    4)::numeric(12,4)                        AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc, 0)
    + COALESCE(p.pipeline_count, 0)
    + COALESCE(svn.vacant_slots, 0)::numeric
    + COALESCE(svr.vacant_hc, 0)::numeric,
    4)::numeric(12,4)                        AS required_hc
  FROM   public.accounts a
  LEFT JOIN public.groups                 g   ON g.id   = a.group_id
  LEFT JOIN filled                        f   ON f.account_id   = a.id
  LEFT JOIN pipeline                      p   ON p.account_id   = a.id
  LEFT JOIN vacant                        v   ON v.account_id   = a.id
  LEFT JOIN slot_vacant_non_roving        svn ON svn.account_id = a.id
  LEFT JOIN slot_vacant_roving            svr ON svr.account_id = a.id
  WHERE  a.is_active = true
    AND  COALESCE(a.is_pool_account, false) = false
    AND  (public.i_have_full_access()
          OR a.id = ANY (public.get_my_allowed_account_ids()))
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc, actual_hc, pipeline_count,
  open_hc,
  required_hc,
  -- FIX OHM2026_0079: THEN 0.0 (was 1.0) — safe empty-state MFR
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(filled_hc / required_hc, 4) END                       AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round((filled_hc + pipeline_count) / required_hc, 4) END   AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END                 AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END                 AS pipeline_coverage,
  CASE WHEN required_hc = 0                       THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 1.0        THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 0.9        THEN 'at_risk'::text
       ELSE                                            'critical'::text
  END                                                                   AS health_status,
  slot_vacant_hc
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'Allocation-based per-account KPI. OHM2026_0073: '
  'slot_vacant_hc = non-roving COUNT(slots WHERE status IN (open,pipeline)) '
  '               + roving SUM(1/N per group). '
  'open_hc kept for backward compat (deprecated for Vacant display). '
  'required_hc = filled_hc + pipeline_count(hr_emploc) + slot_vacant_hc. '
  'MFR = filled_hc / required_hc. '
  'OHM2026_0079: mfr/projected_mfr return 0.0 (not 1.0) when required_hc = 0.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;


-- ── §3. v_cencom_group_allocation_kpi — mfr/projected_mfr safe-zero ──────────

CREATE OR REPLACE VIEW public.v_cencom_group_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  group_id, group_name, group_code,
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  sum(pipeline_count)::bigint            AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,
  round(sum(required_hc), 4)             AS required_hc,
  -- FIX OHM2026_0079: THEN 0.0 (was 1.0)
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                          THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0      THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9      THEN 'at_risk'::text
       ELSE                                                    'critical'::text
  END                                                                     AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc
FROM public.v_cencom_account_allocation_kpi
GROUP BY group_id, group_name, group_code;

ALTER VIEW public.v_cencom_group_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_group_allocation_kpi IS
  'Allocation-based per-group CENCOM KPI (Group 1–5). OHM2026_0073: '
  'slot_vacant_hc added; required_hc slot-based; vacancy_rate slot-based. '
  'OHM2026_0079: mfr/projected_mfr return 0.0 (not 1.0) when required_hc = 0.';
GRANT SELECT ON public.v_cencom_group_allocation_kpi TO authenticated, service_role;


-- ── §4. v_cencom_allocation_kpi — mfr/projected_mfr safe-zero ────────────────

CREATE OR REPLACE VIEW public.v_cencom_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  sum(pipeline_count)::bigint            AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,
  round(sum(required_hc), 4)             AS required_hc,
  -- FIX OHM2026_0079: THEN 0.0 (was 1.0)
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                          THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0      THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9      THEN 'at_risk'::text
       ELSE                                                    'critical'::text
  END                                                                     AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc
FROM public.v_cencom_account_allocation_kpi;

ALTER VIEW public.v_cencom_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_allocation_kpi IS
  'Allocation-based aggregate CENCOM KPI (Group 1–5). OHM2026_0073: '
  'slot_vacant_hc added; required_hc slot-based; vacancy_rate slot-based. '
  'OHM2026_0079: mfr/projected_mfr return 0.0 (not 1.0) when required_hc = 0.';
GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated, service_role;


-- ── §5. Smoke test assertions ─────────────────────────────────────────────────

DO $$
DECLARE
  v_orphaned_esa  integer;
  v_active_esa    integer;
BEGIN
  SELECT COUNT(*) INTO v_orphaned_esa
  FROM   public.employee_store_allocations esa
  WHERE  esa.is_active = true
    AND  NOT EXISTS (
      SELECT 1
      FROM   public.plantilla p
      WHERE  p.employee_no             = esa.employee_no
        AND  COALESCE(p.is_archived, false) = false
        AND  COALESCE(p.is_deleted,  false) = false
    );

  SELECT COUNT(*) INTO v_active_esa
  FROM   public.employee_store_allocations
  WHERE  is_active = true;

  RAISE NOTICE '=== OHM2026_0079 SMOKE TEST ===';
  RAISE NOTICE 'Orphaned active ESA rows (expect 0): %', v_orphaned_esa;
  RAISE NOTICE 'Total active ESA rows remaining: %', v_active_esa;

  IF v_orphaned_esa > 0 THEN
    RAISE WARNING 'SMOKE FAIL: % orphaned active ESA rows still exist after §1 deactivation', v_orphaned_esa;
  ELSE
    RAISE NOTICE 'SMOKE PASS: no orphaned ESA rows';
  END IF;

  RAISE NOTICE '=== POST-APPLY SQL CHECKS (run manually in Supabase SQL Editor) ===';
  RAISE NOTICE 'SELECT required_hc, actual_hc, filled_hc, slot_vacant_hc, mfr FROM v_cencom_allocation_kpi;';
  RAISE NOTICE '-- After QA reset + 2 open slots: expect required_hc=2, actual_hc=0, filled_hc=0, slot_vacant_hc=2, mfr=0.0';
END;
$$;

COMMIT;
