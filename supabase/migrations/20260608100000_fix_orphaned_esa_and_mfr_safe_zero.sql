-- ============================================================
-- OHM2026_0067 — Fix Orphaned ESA After QA Reset + MFR Safe-Zero
-- Migration:  20260608100000_fix_orphaned_esa_and_mfr_safe_zero.sql
-- Depends on: 20260628000000_allocation_based_mfr_v1.sql
--             20260908000001_slot_based_vacant_hc_v1.sql
--             20260910000000_esa_cascade_qa_archive_reset.sql (may not be applied)
-- ============================================================
-- Problem 1 — Orphaned ESA rows after QA reset:
--   fn_qa_archive_operational_data_reset (migration 20260906000000) did NOT
--   deactivate employee_store_allocations rows. Migration 20260910000000 was
--   authored to fix this for FUTURE resets, but if the QA reset ran before
--   20260910000000 was applied, the existing ESA rows remain is_active = true.
--   These orphaned rows cause v_cencom_allocation_kpi to report required_hc =
--   actual_hc = 309 even though all Plantilla and HR Emploc are archived/deleted.
--
-- Problem 2 — MFR safe-zero when required_hc = 0:
--   After ESA is cleared, required_hc = 0. All three allocation KPI views return
--   mfr = 1.0 (CASE WHEN required_hc = 0 THEN 1.0) — showing "100% MFR" on an
--   entirely empty operational system. The safe value is 0.0.
--
-- Sections:
--   §1  One-time cleanup — deactivate orphaned active ESA rows
--       (active rows with no corresponding non-archived, non-deleted plantilla)
--   §2  v_account_allocation_kpi   — mfr/projected_mfr THEN 0.0 when required=0
--   §3  v_cencom_group_allocation_kpi — same
--   §4  v_cencom_allocation_kpi    — same
--   §5  Smoke test RAISE NOTICE assertions
--
-- No CENCOM screen, no Dashboard screen, no workflow changes.
-- v_cencom_account_allocation_kpi (SELECT ak.*) picks up §2 automatically.
-- ============================================================

BEGIN;

-- ── §1. One-time orphaned ESA deactivation ────────────────────────────────────
-- An active ESA row is orphaned when the employee has no live (non-archived,
-- non-deleted) plantilla record. This is invariantly wrong: ESA is an active
-- deployment ledger and must stay in sync with Plantilla status.
--
-- After a QA archive reset (which sets plantilla.is_archived = true for all rows)
-- every active ESA row is orphaned by definition.
--
-- Idempotent: rows that already have is_active = false are untouched.
-- Does not set qa_archive_batch_id because this is a schema-repair sweep, not a
-- QA batch event. Any future QA reset via fn_qa_archive_operational_data_reset
-- (updated by 20260910000000) will set the batch id correctly.

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
-- Full view redefinition from 20260908000001 (slot_based_vacant_hc_v1).
-- Only change: THEN 1.0 → THEN 0.0 for mfr and projected_mfr.

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
    COALESCE(v.open_hc, 0)                   AS open_hc,
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
  -- FIX OHM2026_0067: THEN 0.0 (was 1.0) — safe empty-state MFR
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
  'OHM2026_0067: mfr/projected_mfr return 0.0 (not 1.0) when required_hc = 0.';
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
  -- FIX OHM2026_0067: THEN 0.0 (was 1.0)
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
  'OHM2026_0067: mfr/projected_mfr return 0.0 (not 1.0) when required_hc = 0.';
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
  -- FIX OHM2026_0067: THEN 0.0 (was 1.0)
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
  'OHM2026_0067: mfr/projected_mfr return 0.0 (not 1.0) when required_hc = 0.';
GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated, service_role;


-- ── §5. Smoke test assertions ─────────────────────────────────────────────────

DO $$
DECLARE
  v_orphaned_esa  integer;
  v_active_esa    integer;
BEGIN
  -- Check 1: no more orphaned active ESA rows
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

  -- Check 2: total active ESA count (informational)
  SELECT COUNT(*) INTO v_active_esa
  FROM   public.employee_store_allocations
  WHERE  is_active = true;

  RAISE NOTICE '=== OHM2026_0067 SMOKE TEST ===';
  RAISE NOTICE 'Orphaned active ESA rows (expect 0): %', v_orphaned_esa;
  RAISE NOTICE 'Total active ESA rows remaining: %', v_active_esa;

  IF v_orphaned_esa > 0 THEN
    RAISE WARNING 'SMOKE FAIL: % orphaned active ESA rows still exist after §1 deactivation', v_orphaned_esa;
  ELSE
    RAISE NOTICE 'SMOKE PASS: no orphaned ESA rows';
  END IF;

  RAISE NOTICE '=== POST-APPLY SQL CHECKS (run manually in Supabase SQL Editor) ===';
  RAISE NOTICE 'SELECT required_hc, actual_hc, filled_hc, mfr FROM v_cencom_allocation_kpi;';
  RAISE NOTICE '-- expect: required_hc=0, actual_hc=0, filled_hc=0, mfr=0.0 after QA reset';
  RAISE NOTICE 'SELECT COUNT(*) FROM employee_store_allocations WHERE is_active = true;';
  RAISE NOTICE '-- expect: 0 (or only rows for employees with non-archived plantilla)';
END;
$$;

COMMIT;
