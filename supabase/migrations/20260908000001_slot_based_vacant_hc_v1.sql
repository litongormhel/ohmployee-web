-- ============================================================================
-- OHM2026_0073 — Slot-Based Manpower Vacant HC (V1)
-- ============================================================================
-- PROBLEM:
--   All CENCOM and Plantilla "Vacant" counts used raw vacancy ROW count —
--   1 per VCODE regardless of how many HC slots that VCODE actually needs.
--
--   Example: DNF-G2-0002 (HC Needed=3, Open=2, HR Processing=1)
--     BEFORE: open_hc = 1  (one VCODE row with status='Open')
--     AFTER:  slot_vacant_hc = 2  (two open slots counted individually)
--
-- APPROVED CANONICAL DEFINITION (OHM2026_0073):
--   Vacant HC = manpower demand not yet onboarded / not yet HR Emploc
--
--   slot_status     | counts as Vacant?
--   ----------------|-----------------
--   open            | YES
--   pipeline        | YES  (applicant found, not yet onboarded to HR Emploc)
--   hr_processing   | NO   (applicant in HR Emploc — processing, not vacant)
--   occupied        | NO   (employee in Plantilla)
--   closed          | NO
--
-- FORMULA CHANGE (non-roving):
--   BEFORE: open_hc = COUNT(*) FROM vacancies WHERE status='Open'
--           → VCODE-level count (1 per VCODE, regardless of required_headcount)
--   AFTER:  slot_vacant_hc = COUNT(*) FROM plantilla_slots
--           WHERE slot_status IN ('open', 'pipeline')
--           AND is_roving = false AND legacy_vcode IS NOT NULL
--           [INNER JOIN vacancies: active, non-archived, non-pool]
--           → SLOT-level count (1 per vacant HC slot)
--
-- FORMULA CHANGE (roving):
--   BEFORE: 1 per primary VCODE (affects_required_hc=true) regardless of
--           how many stores are already filled vs still vacant
--   AFTER:  SUM(1/N) for roving slots WHERE slot_status IN ('open','pipeline')
--           N = total slots per roving group (source_hc_request_id)
--           → fractional HC: 2-store roving with 1 occupied = 0.5 vacant
--
-- REQUIRED HC CHANGE:
--   required_hc now uses slot_vacant_hc instead of open_hc.
--   This fixes the MFR denominator for multi-slot VCODEs (HC Needed > 1).
--   For HC=3, Open=2, HR=1:
--     BEFORE: required = filled(0) + hr_emploc(1) + open_vcode(1) = 2 (wrong)
--     AFTER:  required = filled(0) + hr_emploc(1) + slot_vacant(2) = 3 (correct)
--
-- VALIDATION DATA (from OHM2026_0073 approval):
--   VAC-MNL-001  occupied              → slot_vacant_hc = 0  ✓
--   VCDG2_0001   pipeline (1)          → slot_vacant_hc = 1  ✓
--   VCDG2_0002   pipeline (1)          → slot_vacant_hc = 1  ✓
--   VCDG2_0004   pipeline (1)          → slot_vacant_hc = 1  ✓
--   VCDG2_0005   hr_processing(1) + pipeline(1)
--                                      → slot_vacant_hc = 1  ✓ (only pipeline counts)
--   DNF-G2-0002  HC=3, Open=2, HR=1   → slot_vacant_hc = 2  ✓
--   DNF-G2-0003  Open=1               → slot_vacant_hc = 1  ✓
--
-- AFFECTED VIEWS:
--   v_account_allocation_kpi           MODIFIED — adds slot_vacant_hc; updates required_hc, vacancy_rate
--   v_cencom_account_allocation_kpi    inherits automatically via SELECT ak.*
--   v_cencom_group_allocation_kpi      MODIFIED — adds slot_vacant_hc; updates vacancy_rate
--   v_cencom_allocation_kpi            MODIFIED — adds slot_vacant_hc; updates vacancy_rate
--
-- BACKWARD COMPATIBILITY:
--   open_hc column is PRESERVED in all views (deprecated for Vacant display only).
--   No DROP, no CASCADE, no column-type change. ADDITIVE migration.
--
-- FLUTTER CONSUMERS (updated in same batch as this migration):
--   lib/data/services/cencom_service.dart        reads slot_vacant_hc for mfrVacant / VAC column
--   lib/data/services/plantilla_scope_service.dart  reads slot_vacant_hc for account card vacant count
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────────
-- §1  v_account_allocation_kpi
--     Add slot_vacant_hc; update required_hc and vacancy_rate to slot-based.
--     Preserve open_hc for backward compatibility.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  -- Active employee fractional HC from employee_store_allocations.
  -- Stationary = 1.0; roving = 1/N per store. SUM = 1 per employee.
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4)   AS filled_hc,
         count(DISTINCT a.employee_no)             AS actual_hc
  FROM   public.employee_store_allocations a
  WHERE  a.is_active
  GROUP  BY a.account_id
),
pipeline AS (
  -- HR Emploc rows in-process = slot_status 'hr_processing' equivalent.
  -- NOT the same as slot_status 'pipeline' (applicant in Vacancy Pipeline).
  -- Roving-safe: one master hr_emploc row per roving group (uq constraint).
  SELECT he.account_id, count(*) AS pipeline_count
  FROM   public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE  he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND  he.deleted_at IS NULL
    AND  COALESCE(v.is_archived, false) = false
    AND  COALESCE(v.is_pool_vacancy, false) = false
  GROUP  BY he.account_id
),
-- ── NEW §1a: Slot-based vacant — NON-ROVING ──────────────────────────────────
-- Counts non-roving slots with slot_status IN ('open','pipeline') linked to
-- active (non-deleted, non-archived, non-pool) vacancies.
-- Each slot = 1 HC demand unit. Replaces the 1-per-VCODE row approach.
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
-- ── NEW §1b: Slot-based vacant — ROVING (fractional) ─────────────────────────
-- 1 roving HC request → N slots (one per covered store), all sharing the same
-- source_hc_request_id. Each slot contributes 1/N HC.
-- Vacant roving HC = SUM(1/N) for slots WHERE slot_status IN ('open','pipeline').
-- Example: 2-store roving, 1 occupied + 1 open → SUM = 0 + 1/2 = 0.5 HC vacant.
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
    -- Group size per roving HC request (all stores for one roving person)
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
-- ── LEGACY: VCODE-level Open HC (preserved for backward compatibility) ────────
-- open_hc = COUNT of vacancy ROWS with status='Open'.
-- Kept so existing downstream code that references open_hc does not break.
-- DO NOT use open_hc for Vacant HC display from OHM2026_0073 forward;
-- use slot_vacant_hc instead.
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

    -- ── NEW: slot-based vacant HC (canonical Vacant metric from OHM2026_0073) ──
    round(
      COALESCE(svn.vacant_slots, 0)::numeric
    + COALESCE(svr.vacant_hc, 0)::numeric,
    4)::numeric(12,4)                        AS slot_vacant_hc,

    -- ── Required HC: now uses slot_vacant_hc (fixes multi-slot VCODE denominator) ─
    -- Before: filled + hr_emploc + open_vcode_count  (1 per VCODE row — wrong for HC>1)
    -- After:  filled + hr_emploc + slot_vacant_hc    (actual slot demand — correct)
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
  open_hc,          -- legacy VCODE-row count; preserved for backward compat
  required_hc,      -- now = filled + hr_emploc + slot_vacant_hc
  CASE WHEN required_hc = 0 THEN 1.0
       ELSE round(filled_hc / required_hc, 4) END                       AS mfr,
  CASE WHEN required_hc = 0 THEN 1.0
       ELSE round((filled_hc + pipeline_count) / required_hc, 4) END   AS projected_mfr,
  -- vacancy_rate: slot-based (matches slot_vacant_hc / required_hc)
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END                 AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END                 AS pipeline_coverage,
  CASE WHEN required_hc = 0                       THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 1.0        THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 0.9        THEN 'at_risk'::text
       ELSE                                            'critical'::text
  END                                                                   AS health_status,
  slot_vacant_hc    -- NEW: slot-based manpower demand (canonical from OHM2026_0073); appended last to preserve column ordinals
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'Allocation-based per-account KPI. OHM2026_0073: '
  'slot_vacant_hc = non-roving COUNT(slots WHERE status IN (open,pipeline)) '
  '               + roving SUM(1/N per group). '
  'open_hc kept for backward compat (deprecated for Vacant display). '
  'required_hc = filled_hc + pipeline_count(hr_emploc) + slot_vacant_hc. '
  'MFR = filled_hc / required_hc. '
  'Canonical Vacant metric: slot_vacant_hc.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;


-- ──────────────────────────────────────────────────────────────────────────────
-- §2  v_cencom_account_allocation_kpi
--     Re-issue SELECT ak.* to re-expand the wildcard against the updated base
--     view (PostgreSQL does not auto-propagate new base-view columns to
--     wildcard-select child views). This appends slot_vacant_hc as column 17,
--     matching the new trailing position in v_account_allocation_kpi.
-- ──────────────────────────────────────────────────────────────────────────────

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
  'OHM2026_0073: slot_vacant_hc inherited as trailing column via SELECT ak.*.';
GRANT SELECT ON public.v_cencom_account_allocation_kpi TO authenticated, service_role;


-- ──────────────────────────────────────────────────────────────────────────────
-- §3  v_cencom_group_allocation_kpi
--     Add slot_vacant_hc; update vacancy_rate to slot-based.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_cencom_group_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  group_id, group_name, group_code,
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  sum(pipeline_count)::bigint            AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,           -- preserved; backward compat
  round(sum(required_hc), 4)            AS required_hc,        -- inherits slot-based denominator
  CASE WHEN sum(required_hc) = 0 THEN 1.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 1.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  -- vacancy_rate: slot-based (was sum(open_hc)/sum(required_hc))
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                          THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0      THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9      THEN 'at_risk'::text
       ELSE                                                    'critical'::text
  END                                                                     AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc     -- NEW, appended last to preserve column ordinals
FROM public.v_cencom_account_allocation_kpi
GROUP BY group_id, group_name, group_code;

ALTER VIEW public.v_cencom_group_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_group_allocation_kpi IS
  'Allocation-based per-group CENCOM KPI (Group 1–5). OHM2026_0073: '
  'slot_vacant_hc added; required_hc slot-based; vacancy_rate slot-based.';
GRANT SELECT ON public.v_cencom_group_allocation_kpi TO authenticated, service_role;


-- ──────────────────────────────────────────────────────────────────────────────
-- §4  v_cencom_allocation_kpi
--     Add slot_vacant_hc; update vacancy_rate to slot-based.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_cencom_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  round(sum(filled_hc), 4)               AS filled_hc,
  sum(actual_hc)::bigint                 AS actual_hc,
  sum(pipeline_count)::bigint            AS pipeline_count,
  sum(open_hc)::bigint                   AS open_hc,           -- preserved; backward compat
  round(sum(required_hc), 4)            AS required_hc,        -- inherits slot-based denominator
  CASE WHEN sum(required_hc) = 0 THEN 1.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 1.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  -- vacancy_rate: slot-based (was sum(open_hc)/sum(required_hc))
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(slot_vacant_hc) / sum(required_hc), 4) END          AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                          THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0      THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9      THEN 'at_risk'::text
       ELSE                                                    'critical'::text
  END                                                                     AS health_status,
  round(sum(slot_vacant_hc), 4)          AS slot_vacant_hc     -- NEW, appended last to preserve column ordinals
FROM public.v_cencom_account_allocation_kpi;

ALTER VIEW public.v_cencom_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_allocation_kpi IS
  'Allocation-based aggregate CENCOM KPI (Group 1–5). OHM2026_0073: '
  'slot_vacant_hc added; required_hc slot-based; vacancy_rate slot-based.';
GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated, service_role;


COMMIT;


-- ============================================================================
-- SMOKE TEST VALIDATION QUERIES (run manually after applying migration)
-- ============================================================================

/*
-- ── V1: Total slot_vacant_hc by account ──────────────────────────────────────
-- Confirms slot-based vacant replaces VCODE row count.
-- Compare open_hc (old) vs slot_vacant_hc (new) side by side.
SELECT
  account_name,
  open_hc          AS old_vcode_vacant,
  slot_vacant_hc   AS new_slot_vacant,
  (slot_vacant_hc - open_hc) AS diff,  -- positive = more accurate (multi-slot VCODEs)
  required_hc,
  mfr
FROM public.v_account_allocation_kpi
WHERE slot_vacant_hc > 0 OR open_hc > 0
ORDER BY diff DESC, account_name;
-- Expected: accounts with multi-slot VCODEs show positive diff.
-- Accounts with HC Needed=1 everywhere show diff=0.

-- ── V2: DNF VCODE detail — slot status breakdown per VCODE ───────────────────
-- Validates slot_vacant_hc at VCODE grain via the shadow view.
SELECT
  s.legacy_vcode,
  s.required_hc          AS hc_needed,
  s.open_count,
  s.pipeline_count,
  s.hr_processing_count,
  s.occupied_count,
  s.closed_count,
  (s.open_count + s.pipeline_count) AS slot_vacant_hc_expected,
  a.account_name
FROM public.vw_slot_derived_vacancy_shadow s
LEFT JOIN public.accounts a ON a.id = s.account_id
WHERE s.legacy_vcode LIKE 'VCDG2%'
   OR s.legacy_vcode LIKE 'DNF%'
   OR s.legacy_vcode = 'VAC-MNL-001'
ORDER BY s.legacy_vcode;
-- Expected per OHM2026_0073 approval:
--   VAC-MNL-001  occupied(1)               → slot_vacant_hc_expected = 0
--   VCDG2_0001   pipeline(1)               → slot_vacant_hc_expected = 1
--   VCDG2_0002   pipeline(1)               → slot_vacant_hc_expected = 1
--   VCDG2_0004   pipeline(1)               → slot_vacant_hc_expected = 1
--   VCDG2_0005   hr_processing(1)+pipe(1)  → slot_vacant_hc_expected = 1
--   DNF-G2-0002  open(2)+hr_proc(1)        → slot_vacant_hc_expected = 2
--   DNF-G2-0003  open(1)                   → slot_vacant_hc_expected = 1

-- ── V3: CENCOM vs Plantilla reconciliation ────────────────────────────────────
-- CENCOM aggregate slot_vacant_hc vs per-account sum from base view.
SELECT
  (SELECT round(sum(slot_vacant_hc), 4) FROM public.v_cencom_allocation_kpi) AS cencom_total,
  (SELECT round(sum(slot_vacant_hc), 4) FROM public.v_cencom_account_allocation_kpi) AS account_sum;
-- Expected: cencom_total = account_sum (rollup is consistent).

-- ── V4: required_hc reconciliation — confirms slot-based denominator ──────────
-- For accounts where HC > 1 per VCODE, required_hc should be higher than before.
SELECT
  account_name,
  required_hc AS new_required_hc,
  filled_hc,
  pipeline_count AS hr_emploc_count,
  slot_vacant_hc,
  round(filled_hc + pipeline_count + slot_vacant_hc, 4) AS computed_required_hc
FROM public.v_account_allocation_kpi
WHERE slot_vacant_hc > 0
ORDER BY slot_vacant_hc DESC
LIMIT 20;
-- Expected: required_hc = filled_hc + pipeline_count + slot_vacant_hc (exactly).

-- ── V5: Roving fractional HC validation (run only if roving slots exist) ──────
SELECT
  ps.account_id,
  ps.source_hc_request_id,
  COUNT(*) AS total_slots,
  COUNT(*) FILTER (WHERE ps.slot_status IN ('open', 'pipeline')) AS vacant_slots,
  round(
    COUNT(*) FILTER (WHERE ps.slot_status IN ('open','pipeline'))::numeric
    / NULLIF(COUNT(*)::numeric, 0), 4
  ) AS roving_vacant_fraction
FROM public.plantilla_slots ps
WHERE ps.is_roving = true
  AND ps.source_hc_request_id IS NOT NULL
GROUP BY ps.account_id, ps.source_hc_request_id
ORDER BY roving_vacant_fraction DESC;
-- Expected (2-store roving, 1 occupied + 1 open): total=2, vacant=1, fraction=0.5
-- If no roving slots exist yet: 0 rows returned (acceptable for V1).

-- ── V6: Backward compat — open_hc still populated ────────────────────────────
SELECT
  account_name, open_hc, slot_vacant_hc
FROM public.v_account_allocation_kpi
WHERE open_hc > 0 OR slot_vacant_hc > 0
LIMIT 10;
-- Expected: open_hc still non-zero for accounts with Open vacancies.
-- slot_vacant_hc >= open_hc (slot count >= VCODE count for HC>=1 accounts).
*/
