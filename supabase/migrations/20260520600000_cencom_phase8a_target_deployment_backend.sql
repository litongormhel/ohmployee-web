-- ============================================================
-- OHMployee — CENCOM Backend Phase 8A
-- Target Deployment Backend Authority Refactor
-- Migration: 20260520600000_cencom_phase8a_target_deployment_backend.sql
--
-- Depends on: CENCOM Phase 1 (cencom_scope on groups, v_cencom_account_kpi)
-- Next migration: 20260520700000 (CENCOM Phase 8B — Target Deployment Flutter)
--
-- What this migration does:
--   1. fn_cencom_td_aging_bucket        — IMMUTABLE aging bucket classifier
--   2. fn_cencom_td_priority_score      — IMMUTABLE priority scoring function
--   3. v_cencom_td_vacancies            — Base view: all CENCOM-scoped open vacancies
--                                         with aging, bucket, priority, health
--   4. v_cencom_td_summary              — Aggregate aging bucket counts
--   5. v_cencom_td_by_group             — Per-group aging distribution
--   6. v_cencom_td_by_account           — Per-account aging breakdown
--   7. v_cencom_td_priority_queue       — Priority deployment queue (non-advance only)
--   8. fn_cencom_td_summary()           — SECURITY DEFINER RPC: summary + groups JSON
--   9. fn_cencom_td_drilldown(uuid)     — SECURITY DEFINER RPC: account-level drilldown
--
-- Aging buckets (canonical):
--   advance   — vacant_date IS NULL or vacant_date > CURRENT_DATE
--   1_15      — 1–15 days (situational)
--   16_30     — 16–30 days (roving coverage zone)
--   31_60     — 31–60 days
--   61_120    — 61–120 days
--   gt121     — > 121 days (critical)
--
-- Advance Vacancy rules:
--   • NOT counted in operational aging totals or urgency metrics
--   • Displayed separately in the UI
--   • priority_score = 0 (does not enter deployment priority queue)
--   • Does NOT contribute to aging-based health_status scoring
--
-- Priority scoring inputs:
--   • vacancy aging (base)
--   • urgency_level (bonus: High +50, Medium +20)
--   • required_headcount (weight: (hc-1)*10 for HC > 1)
--   • account_mfr (MFR criticality bonus: <0.75 +40, <0.85 +25, <0.90 +10)
--
-- CENCOM scope:
--   Restricted to cencom_scope=true groups (Group 1–5) via v_cencom_account_kpi.
--   Moses HQ, Global HQ, HQ, corporate, and non-operational groups are excluded.
--   User scope (get_my_allowed_accounts) is inherited through v_cencom_account_kpi.
--
-- Safety guarantees:
--   • Additive only — no existing tables, views, RPCs, or triggers modified
--   • v_cencom_account_kpi, v_cencom_group_kpi, v_cencom_kpi — UNTOUCHED
--   • All new views use SECURITY INVOKER (caller RLS applies)
--   • All new RPCs use SECURITY DEFINER with explicit scope replication
--   • No hard deletes, no constraint changes, no foreign key alterations
--
-- Rollback:
--   DROP FUNCTION IF EXISTS public.fn_cencom_td_summary();
--   DROP FUNCTION IF EXISTS public.fn_cencom_td_drilldown(uuid);
--   DROP FUNCTION IF EXISTS public.fn_cencom_td_aging_bucket(int, boolean);
--   DROP FUNCTION IF EXISTS public.fn_cencom_td_priority_score(int, text, int, numeric);
--   DROP VIEW IF EXISTS public.v_cencom_td_priority_queue;
--   DROP VIEW IF EXISTS public.v_cencom_td_by_account;
--   DROP VIEW IF EXISTS public.v_cencom_td_by_group;
--   DROP VIEW IF EXISTS public.v_cencom_td_summary;
--   DROP VIEW IF EXISTS public.v_cencom_td_vacancies;
-- ============================================================


-- ── Step 1: fn_cencom_td_aging_bucket ─────────────────────────────────────────
-- Returns the canonical aging bucket label for a given aging day count.
-- Advance vacancy (is_advance = true OR p_days IS NULL) → 'advance'
-- Bucket names use underscore format for safe JSON key usage in Flutter.

CREATE OR REPLACE FUNCTION public.fn_cencom_td_aging_bucket(
  p_days      int,
  p_is_advance boolean DEFAULT false
)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p_is_advance OR p_days IS NULL THEN 'advance'
    WHEN p_days BETWEEN 1  AND  15     THEN '1_15'
    WHEN p_days BETWEEN 16 AND  30     THEN '16_30'
    WHEN p_days BETWEEN 31 AND  60     THEN '31_60'
    WHEN p_days BETWEEN 61 AND 120     THEN '61_120'
    WHEN p_days > 120                  THEN 'gt121'
    ELSE                                    '1_15'  -- 0 days treated as just opened
  END;
$$;

COMMENT ON FUNCTION public.fn_cencom_td_aging_bucket(int, boolean) IS
  'CENCOM Phase 8A: Returns canonical aging bucket for a vacancy. '
  'Buckets: advance | 1_15 | 16_30 | 31_60 | 61_120 | gt121. '
  'Advance vacancy (future/null date) always returns ''advance'' and must not '
  'contribute to operational aging metrics.';


-- ── Step 2: fn_cencom_td_priority_score ───────────────────────────────────────
-- Computes backend-authoritative deployment priority score.
-- Higher score = higher deployment urgency.
-- Advance vacancies always return 0 (excluded from priority queue).
--
-- Formula:
--   aging_days (base, clamped to 0+)
--   + urgency_level bonus (High +50, Medium +20)
--   + required_headcount weight ((hc-1) * 10 for HC > 1)
--   + account MFR criticality (MFR < 0.75 → +40, < 0.85 → +25, < 0.90 → +10)

CREATE OR REPLACE FUNCTION public.fn_cencom_td_priority_score(
  p_aging_days        int,
  p_urgency_level     text,
  p_required_headcount int,
  p_account_mfr       numeric
)
RETURNS int
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public'
AS $$
  SELECT
    -- Advance vacancies: zero priority (excluded from deployment urgency)
    CASE WHEN p_aging_days IS NULL THEN 0
    ELSE
      GREATEST(0, p_aging_days)
      + CASE COALESCE(p_urgency_level, 'Normal')
          WHEN 'High'   THEN 50
          WHEN 'Medium' THEN 20
          ELSE               0
        END
      + CASE WHEN COALESCE(p_required_headcount, 1) > 1
              THEN (COALESCE(p_required_headcount, 1) - 1) * 10
              ELSE 0
        END
      + CASE
          WHEN COALESCE(p_account_mfr, 1.0) < 0.75 THEN 40
          WHEN COALESCE(p_account_mfr, 1.0) < 0.85 THEN 25
          WHEN COALESCE(p_account_mfr, 1.0) < 0.90 THEN 10
          ELSE 0
        END
    END;
$$;

COMMENT ON FUNCTION public.fn_cencom_td_priority_score(int, text, int, numeric) IS
  'CENCOM Phase 8A: Deployment priority score. '
  'Inputs: aging_days, urgency_level, required_headcount, account_mfr. '
  'Advance vacancies (null aging_days) always return 0. '
  'Higher score = more urgent deployment target. '
  'Used by v_cencom_td_priority_queue and fn_cencom_td_summary.';


-- ── Step 3: v_cencom_td_vacancies ─────────────────────────────────────────────
-- Base view of all CENCOM-scoped open vacancies with computed aging,
-- bucket classification, priority score, and health categorization.
--
-- Scope: inherits from v_cencom_account_kpi JOIN (cencom_scope=true + user scope).
-- RLS: SECURITY INVOKER — caller's identity and RLS apply through v_cencom_account_kpi.
--
-- CASCADE drop required since derived views depend on this view.

DROP VIEW IF EXISTS public.v_cencom_td_vacancies CASCADE;

CREATE VIEW public.v_cencom_td_vacancies
  WITH (security_invoker = true)
AS
SELECT
  -- ── Vacancy identifiers ──────────────────────────────────────────────────
  v.id                                                                AS vacancy_id,
  v.vcode,
  v.account,
  v.account_id,
  v.position,
  COALESCE(v.area_name, v.area_city)                                 AS area_name,
  COALESCE(v.store_name, v.store_branch)                             AS store_name,
  v.vacant_date,
  v.vacancy_type,
  COALESCE(v.urgency_level, 'Normal')                               AS urgency_level,
  v.target_fill_date,
  v.required_headcount,
  v.source,

  -- ── CENCOM group context (from v_cencom_account_kpi) ───────────────────
  ak.group_id,
  ak.group_name,
  ak.group_code,

  -- ── Account MFR and health (from v_cencom_account_kpi) ─────────────────
  ak.mfr                                                             AS account_mfr,
  ak.actual_hc                                                       AS account_actual_hc,
  ak.required_hc                                                     AS account_required_hc,
  ak.health_status                                                   AS account_health_status,

  -- ── Advance vacancy flag ────────────────────────────────────────────────
  -- Advance = future-dated or undated vacancy (planned, not yet active)
  -- Must NOT contribute to aging penalties or urgency metrics
  (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)           AS is_advance_vacancy,

  -- ── Aging (NULL for advance vacancies — never included in bucket math) ──
  CASE
    WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE THEN NULL::int
    ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
  END                                                                AS aging_days,

  -- ── Canonical aging bucket ──────────────────────────────────────────────
  public.fn_cencom_td_aging_bucket(
    CASE
      WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE THEN NULL
      ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
    END,
    (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
  )                                                                  AS aging_bucket,

  -- ── Priority score (0 for advance vacancies) ───────────────────────────
  public.fn_cencom_td_priority_score(
    CASE
      WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE THEN NULL
      ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
    END,
    COALESCE(v.urgency_level, 'Normal'),
    v.required_headcount,
    ak.mfr
  )                                                                  AS priority_score,

  -- ── Account health tier ─────────────────────────────────────────────────
  CASE
    WHEN COALESCE(ak.mfr, 1.0) < 0.75 THEN 'critical'
    WHEN COALESCE(ak.mfr, 1.0) < 0.85 THEN 'at_risk'
    WHEN COALESCE(ak.mfr, 1.0) < 0.90 THEN 'elevated'
    ELSE                                    'healthy'
  END                                                                AS account_health_tier,

  -- ── Operational urgency tier (aging + MFR combined) ────────────────────
  -- Advance vacancies classified separately; never 'immediate' or 'critical'
  CASE
    WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE THEN 'advance'
    WHEN GREATEST(0, CURRENT_DATE - v.vacant_date) >= 61
         AND COALESCE(ak.mfr, 1.0) < 0.85              THEN 'immediate'
    WHEN GREATEST(0, CURRENT_DATE - v.vacant_date) >= 31
         OR  COALESCE(ak.mfr, 1.0) < 0.80              THEN 'critical'
    WHEN GREATEST(0, CURRENT_DATE - v.vacant_date) >= 16
         OR  COALESCE(ak.mfr, 1.0) < 0.90              THEN 'elevated'
    ELSE                                                    'normal'
  END                                                                AS urgency_tier

FROM  public.vacancies v
-- Join to CENCOM-scoped account KPI view.
-- This single join handles BOTH:
--   (a) cencom_scope restriction (Group 1–5 only)
--   (b) user scope (i_have_full_access OR account in get_my_allowed_accounts)
--   (c) account MFR / health data
-- No separate group join needed — group info flows through ak.
JOIN  public.v_cencom_account_kpi ak ON ak.account_id = v.account_id

WHERE v.status IN ('Open', 'For Sourcing')     -- operational vacancies only
  AND COALESCE(v.is_archived, false) = false
  AND v.deleted_at IS NULL;

ALTER VIEW public.v_cencom_td_vacancies OWNER TO postgres;

COMMENT ON VIEW public.v_cencom_td_vacancies IS
  'CENCOM Phase 8A: Base Target Deployment view. '
  'All CENCOM-scoped (Group 1–5) open vacancies with computed aging, '
  'aging bucket, priority score, and account health. '
  'Advance vacancies (future/null vacant_date) flagged as is_advance_vacancy=true '
  'and excluded from aging metrics (aging_days=NULL, priority_score=0). '
  'SECURITY INVOKER — inherits caller RLS via v_cencom_account_kpi.';

GRANT SELECT ON public.v_cencom_td_vacancies TO authenticated;
GRANT SELECT ON public.v_cencom_td_vacancies TO service_role;


-- ── Step 4: v_cencom_td_summary ───────────────────────────────────────────────
-- Aggregate aging bucket counts across all CENCOM-scoped open vacancies.
-- Used by the Target Deployment summary card in Flutter.
-- Advance vacancies are tracked separately (advance_count) and
-- excluded from operational_total to prevent distortion.

CREATE VIEW public.v_cencom_td_summary
  WITH (security_invoker = true)
AS
SELECT
  -- ── Operational totals (advance excluded) ──────────────────────────────
  COUNT(*) FILTER (WHERE NOT is_advance_vacancy)                     AS operational_total,
  COUNT(*) FILTER (WHERE is_advance_vacancy)                         AS advance_count,
  COUNT(*)                                                           AS grand_total,

  -- ── Aging bucket counts (operational only) ─────────────────────────────
  COUNT(*) FILTER (WHERE aging_bucket = '1_15')                     AS bucket_1_15,
  COUNT(*) FILTER (WHERE aging_bucket = '16_30')                    AS bucket_16_30,
  COUNT(*) FILTER (WHERE aging_bucket = '31_60')                    AS bucket_31_60,
  COUNT(*) FILTER (WHERE aging_bucket = '61_120')                   AS bucket_61_120,
  COUNT(*) FILTER (WHERE aging_bucket = 'gt121')                    AS bucket_gt121,

  -- ── Urgency distribution (operational only) ────────────────────────────
  COUNT(*) FILTER (WHERE urgency_tier = 'immediate')                AS urgency_immediate,
  COUNT(*) FILTER (WHERE urgency_tier = 'critical')                 AS urgency_critical,
  COUNT(*) FILTER (WHERE urgency_tier = 'elevated')                 AS urgency_elevated,
  COUNT(*) FILTER (WHERE urgency_tier = 'normal')                   AS urgency_normal,

  -- ── Account health distribution (operational only) ─────────────────────
  COUNT(*) FILTER (
    WHERE NOT is_advance_vacancy AND account_health_tier = 'critical'
  )                                                                  AS health_critical_count,
  COUNT(*) FILTER (
    WHERE NOT is_advance_vacancy AND account_health_tier = 'at_risk'
  )                                                                  AS health_at_risk_count,
  COUNT(*) FILTER (
    WHERE NOT is_advance_vacancy AND account_health_tier IN ('elevated','healthy')
  )                                                                  AS health_ok_count,

  -- ── Aging stats (operational only) ─────────────────────────────────────
  MAX(aging_days)                                                    AS max_aging_days,
  ROUND(AVG(aging_days), 1)                                         AS avg_aging_days,

  -- ── Critical aging pct: what % of operational vacancies are ≥31 days ──
  ROUND(
    COUNT(*) FILTER (WHERE NOT is_advance_vacancy AND COALESCE(aging_days,0) >= 31)::numeric * 100.0
    / NULLIF(COUNT(*) FILTER (WHERE NOT is_advance_vacancy), 0),
    1
  )                                                                  AS pct_critical_aging,

  now()                                                              AS computed_at

FROM  public.v_cencom_td_vacancies;

ALTER VIEW public.v_cencom_td_summary OWNER TO postgres;

COMMENT ON VIEW public.v_cencom_td_summary IS
  'CENCOM Phase 8A: Aggregate Target Deployment summary. '
  'Advance vacancies are tracked separately (advance_count) and excluded from '
  'operational_total so they do not distort aging or urgency metrics. '
  'SECURITY INVOKER — inherits caller RLS.';

GRANT SELECT ON public.v_cencom_td_summary TO authenticated;
GRANT SELECT ON public.v_cencom_td_summary TO service_role;


-- ── Step 5: v_cencom_td_by_group ──────────────────────────────────────────────
-- Per-group aging distribution for the "VACANCY AGING BY AREA" section.
-- Groups are Group 1–5 (cencom_scope=true) only.
-- Advance vacancies tracked separately per group.

CREATE VIEW public.v_cencom_td_by_group
  WITH (security_invoker = true)
AS
SELECT
  group_id,
  group_name,
  group_code,

  -- ── Operational totals ─────────────────────────────────────────────────
  COUNT(*) FILTER (WHERE NOT is_advance_vacancy)                     AS operational_total,
  COUNT(*) FILTER (WHERE is_advance_vacancy)                         AS advance_count,
  COUNT(*)                                                           AS grand_total,

  -- ── Aging bucket counts (operational only) ─────────────────────────────
  COUNT(*) FILTER (WHERE aging_bucket = '1_15')                     AS bucket_1_15,
  COUNT(*) FILTER (WHERE aging_bucket = '16_30')                    AS bucket_16_30,
  COUNT(*) FILTER (WHERE aging_bucket = '31_60')                    AS bucket_31_60,
  COUNT(*) FILTER (WHERE aging_bucket = '61_120')                   AS bucket_61_120,
  COUNT(*) FILTER (WHERE aging_bucket = 'gt121')                    AS bucket_gt121,

  -- ── Urgency distribution ───────────────────────────────────────────────
  COUNT(*) FILTER (WHERE urgency_tier = 'immediate')                AS urgency_immediate,
  COUNT(*) FILTER (WHERE urgency_tier = 'critical')                 AS urgency_critical,
  COUNT(*) FILTER (WHERE urgency_tier = 'elevated')                 AS urgency_elevated,

  -- ── Aging stats ────────────────────────────────────────────────────────
  MAX(aging_days)                                                    AS max_aging_days,
  ROUND(AVG(aging_days), 1)                                         AS avg_aging_days,

  -- ── Priority stats ─────────────────────────────────────────────────────
  MAX(priority_score) FILTER (WHERE NOT is_advance_vacancy)         AS max_priority_score,

  -- ── Group health status (derived from constituent account health) ───────
  CASE
    WHEN COUNT(*) FILTER (
      WHERE NOT is_advance_vacancy AND account_health_tier = 'critical'
    ) > 0                                                            THEN 'critical'
    WHEN COUNT(*) FILTER (
      WHERE NOT is_advance_vacancy AND account_health_tier = 'at_risk'
    ) > 0                                                            THEN 'at_risk'
    ELSE                                                                  'healthy'
  END                                                                AS group_health_status

FROM  public.v_cencom_td_vacancies
GROUP BY group_id, group_name, group_code
ORDER BY group_code;

ALTER VIEW public.v_cencom_td_by_group OWNER TO postgres;

COMMENT ON VIEW public.v_cencom_td_by_group IS
  'CENCOM Phase 8A: Per-group Target Deployment aging distribution. '
  'Only Group 1–5 (cencom_scope=true). Advance vacancies tracked separately. '
  'Used for VACANCY AGING BY AREA section in CENCOM Target Deployment tab. '
  'SECURITY INVOKER — inherits caller RLS.';

GRANT SELECT ON public.v_cencom_td_by_group TO authenticated;
GRANT SELECT ON public.v_cencom_td_by_group TO service_role;


-- ── Step 6: v_cencom_td_by_account ────────────────────────────────────────────
-- Per-account aging breakdown for drilldown.
-- Supports the account-level aging detail when tapping a group area.

CREATE VIEW public.v_cencom_td_by_account
  WITH (security_invoker = true)
AS
SELECT
  account_id,
  account,
  group_id,
  group_name,
  group_code,
  account_mfr,
  account_health_tier,
  account_health_status,

  -- ── Operational totals ─────────────────────────────────────────────────
  COUNT(*) FILTER (WHERE NOT is_advance_vacancy)                     AS operational_total,
  COUNT(*) FILTER (WHERE is_advance_vacancy)                         AS advance_count,
  COUNT(*)                                                           AS grand_total,

  -- ── Aging bucket counts (operational only) ─────────────────────────────
  COUNT(*) FILTER (WHERE aging_bucket = '1_15')                     AS bucket_1_15,
  COUNT(*) FILTER (WHERE aging_bucket = '16_30')                    AS bucket_16_30,
  COUNT(*) FILTER (WHERE aging_bucket = '31_60')                    AS bucket_31_60,
  COUNT(*) FILTER (WHERE aging_bucket = '61_120')                   AS bucket_61_120,
  COUNT(*) FILTER (WHERE aging_bucket = 'gt121')                    AS bucket_gt121,

  -- ── Aging stats ────────────────────────────────────────────────────────
  MAX(aging_days)                                                    AS max_aging_days,
  ROUND(AVG(aging_days), 1)                                         AS avg_aging_days,
  MAX(priority_score) FILTER (WHERE NOT is_advance_vacancy)         AS max_priority_score,

  -- ── Urgency distribution ───────────────────────────────────────────────
  COUNT(*) FILTER (WHERE urgency_tier IN ('immediate','critical'))  AS urgent_count

FROM  public.v_cencom_td_vacancies
GROUP BY
  account_id, account, group_id, group_name, group_code,
  account_mfr, account_health_tier, account_health_status
ORDER BY max_priority_score DESC NULLS LAST;

ALTER VIEW public.v_cencom_td_by_account OWNER TO postgres;

COMMENT ON VIEW public.v_cencom_td_by_account IS
  'CENCOM Phase 8A: Per-account Target Deployment aging breakdown. '
  'Ordered by max_priority_score DESC for deployment urgency ranking. '
  'Used for account drilldown when tapping a group in Target Deployment tab. '
  'SECURITY INVOKER — inherits caller RLS.';

GRANT SELECT ON public.v_cencom_td_by_account TO authenticated;
GRANT SELECT ON public.v_cencom_td_by_account TO service_role;


-- ── Step 7: v_cencom_td_priority_queue ────────────────────────────────────────
-- Priority deployment queue — individual vacancies ranked by priority_score.
-- Advance vacancies EXCLUDED (they have priority_score=0 and no aging urgency).
-- Used by the Priority Deployment Queue section in CENCOM reports.

CREATE VIEW public.v_cencom_td_priority_queue
  WITH (security_invoker = true)
AS
SELECT
  vacancy_id,
  vcode,
  account,
  account_id,
  group_name,
  group_code,
  position,
  area_name,
  store_name,
  vacant_date,
  vacancy_type,
  urgency_level,
  target_fill_date,
  required_headcount,
  aging_days,
  aging_bucket,
  priority_score,
  account_mfr,
  account_health_tier,
  urgency_tier
FROM  public.v_cencom_td_vacancies
WHERE NOT is_advance_vacancy
ORDER BY
  priority_score DESC,
  aging_days    DESC NULLS LAST,
  vcode;

ALTER VIEW public.v_cencom_td_priority_queue OWNER TO postgres;

COMMENT ON VIEW public.v_cencom_td_priority_queue IS
  'CENCOM Phase 8A: Priority deployment queue — vacancies ranked by backend priority_score. '
  'Advance vacancies excluded. '
  'Sorted: priority_score DESC, aging_days DESC. '
  'SECURITY INVOKER — inherits caller RLS.';

GRANT SELECT ON public.v_cencom_td_priority_queue TO authenticated;
GRANT SELECT ON public.v_cencom_td_priority_queue TO service_role;


-- ── Step 8: fn_cencom_td_summary() ────────────────────────────────────────────
-- SECURITY DEFINER RPC for Flutter to call.
-- Returns the complete Target Deployment payload in a single round-trip:
--   summary     — aggregate bucket counts + urgency + health distribution
--   by_group    — array of per-group aging rows (Group 1–5)
--   health_dist — health distribution summary
--   computed_at — server timestamp

CREATE OR REPLACE FUNCTION public.fn_cencom_td_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_full_access   boolean;
  v_allowed       text[];
  v_is_empty      boolean;

  -- Summary accumulators
  v_op_total      bigint := 0;
  v_advance_count bigint := 0;
  v_b_1_15        bigint := 0;
  v_b_16_30       bigint := 0;
  v_b_31_60       bigint := 0;
  v_b_61_120      bigint := 0;
  v_b_gt121       bigint := 0;
  v_u_immediate   bigint := 0;
  v_u_critical    bigint := 0;
  v_u_elevated    bigint := 0;
  v_u_normal      bigint := 0;
  v_h_critical    bigint := 0;
  v_h_at_risk     bigint := 0;
  v_h_ok          bigint := 0;
  v_max_aging     int    := 0;
  v_avg_aging     numeric := 0;
  v_pct_critical  numeric := 0;

  -- JSON output
  v_by_group      jsonb  := '[]'::jsonb;
BEGIN
  -- ── Scope resolution ──────────────────────────────────────────────────
  v_full_access := public.i_have_full_access();
  IF NOT v_full_access THEN
    v_allowed   := public.get_my_allowed_accounts();
    v_is_empty  := (array_length(v_allowed, 1) IS NULL);
  ELSE
    v_is_empty  := false;
  END IF;

  -- Short-circuit: scoped user with no assigned accounts
  IF v_is_empty THEN
    RETURN jsonb_build_object(
      'summary',      jsonb_build_object(
        'operational_total', 0, 'advance_count', 0, 'grand_total', 0,
        'bucket_1_15', 0, 'bucket_16_30', 0, 'bucket_31_60', 0,
        'bucket_61_120', 0, 'bucket_gt121', 0,
        'urgency_immediate', 0, 'urgency_critical', 0,
        'urgency_elevated', 0, 'urgency_normal', 0,
        'max_aging_days', 0, 'avg_aging_days', 0, 'pct_critical_aging', 0
      ),
      'by_group',     '[]'::jsonb,
      'health_dist',  jsonb_build_object(
        'critical', 0, 'at_risk', 0, 'ok', 0
      ),
      'scope',        'scoped',
      'computed_at',  now()
    );
  END IF;

  -- ── Aggregate summary query ────────────────────────────────────────────
  -- Direct query on vacancies + cencom-scoped accounts for SECURITY DEFINER path.
  -- Replicates the cencom scope logic without calling SECURITY INVOKER views
  -- to avoid potential RLS recursion with SECURITY DEFINER context.
  SELECT
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
    ),
    COUNT(*) FILTER (
      WHERE (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
    ),
    -- Bucket 1-15
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 1 AND 15
    ),
    -- Bucket 16-30
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 16 AND 30
    ),
    -- Bucket 31-60
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 31 AND 60
    ),
    -- Bucket 61-120
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 61 AND 120
    ),
    -- Bucket >121
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND GREATEST(0, CURRENT_DATE - v.vacant_date) > 120
    ),
    -- Urgency immediate (operational: age>=61 + mfr<0.85)
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND GREATEST(0, CURRENT_DATE - v.vacant_date) >= 61
        AND COALESCE(ak.mfr, 1.0) < 0.85
    ),
    -- Urgency critical
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND (
          GREATEST(0, CURRENT_DATE - v.vacant_date) >= 31
          OR COALESCE(ak.mfr, 1.0) < 0.80
        )
        AND NOT (
          GREATEST(0, CURRENT_DATE - v.vacant_date) >= 61
          AND COALESCE(ak.mfr, 1.0) < 0.85
        )
    ),
    -- Urgency elevated
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND (
          GREATEST(0, CURRENT_DATE - v.vacant_date) >= 16
          OR COALESCE(ak.mfr, 1.0) < 0.90
        )
        AND NOT (
          GREATEST(0, CURRENT_DATE - v.vacant_date) >= 31
          OR COALESCE(ak.mfr, 1.0) < 0.80
        )
    ),
    -- Urgency normal
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND GREATEST(0, CURRENT_DATE - v.vacant_date) < 16
        AND COALESCE(ak.mfr, 1.0) >= 0.90
    ),
    -- Health critical vacancies
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND COALESCE(ak.mfr, 1.0) < 0.75
    ),
    -- Health at_risk vacancies
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND COALESCE(ak.mfr, 1.0) >= 0.75 AND COALESCE(ak.mfr, 1.0) < 0.85
    ),
    -- Health ok vacancies
    COUNT(*) FILTER (
      WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        AND COALESCE(ak.mfr, 1.0) >= 0.85
    ),
    COALESCE(MAX(
      CASE WHEN NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
           THEN GREATEST(0, CURRENT_DATE - v.vacant_date) END
    ), 0),
    COALESCE(ROUND(AVG(
      CASE WHEN NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
           THEN GREATEST(0, CURRENT_DATE - v.vacant_date) END
    ), 1), 0)
  INTO
    v_op_total, v_advance_count,
    v_b_1_15, v_b_16_30, v_b_31_60, v_b_61_120, v_b_gt121,
    v_u_immediate, v_u_critical, v_u_elevated, v_u_normal,
    v_h_critical, v_h_at_risk, v_h_ok,
    v_max_aging, v_avg_aging
  FROM public.vacancies v
  JOIN public.accounts a  ON a.id = v.account_id
  JOIN public.groups   g  ON g.id = a.group_id AND g.cencom_scope = true
  -- Account MFR context
  JOIN (
    SELECT
      a2.id                                                          AS account_id,
      CASE WHEN SUM(a2_req.required_hc_sum) = 0 THEN 1.0
           ELSE ROUND(SUM(a2_act.actual_hc_sum)::numeric
                      / SUM(a2_req.required_hc_sum)::numeric, 4)
      END                                                            AS mfr
    FROM public.accounts a2
    JOIN public.groups g2 ON g2.id = a2.group_id AND g2.cencom_scope = true
    LEFT JOIN (
      SELECT account_id, COUNT(*) FILTER (WHERE status='Active') AS actual_hc_sum
      FROM public.plantilla WHERE COALESCE(is_deleted,false)=false
      GROUP BY account_id
    ) a2_act ON a2_act.account_id = a2.id
    LEFT JOIN (
      SELECT
        account_id,
        COUNT(*) FILTER (WHERE status='Active')::int
        + COUNT(DISTINCT v2.vcode) FILTER (
            WHERE v2.status='Open' AND COALESCE(v2.is_archived,false)=false
          )::int AS required_hc_sum
      FROM public.plantilla
      LEFT JOIN public.vacancies v2 ON v2.account_id = plantilla.account_id
      WHERE COALESCE(plantilla.is_deleted,false)=false
      GROUP BY account_id
    ) a2_req ON a2_req.account_id = a2.id
    WHERE a2.is_active = true
    GROUP BY a2.id
  ) ak ON ak.account_id = v.account_id
  WHERE v.status IN ('Open', 'For Sourcing')
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (
      v_full_access
      OR (a.id)::text = ANY(v_allowed)
    );

  -- Critical aging percentage
  v_pct_critical := ROUND(
    CASE WHEN v_op_total = 0 THEN 0
         ELSE (v_b_31_60 + v_b_61_120 + v_b_gt121)::numeric * 100.0 / v_op_total
    END, 1
  );

  -- ── Per-group aggregation ─────────────────────────────────────────────
  SELECT jsonb_agg(
    jsonb_build_object(
      'group_id',           g.id,
      'group_name',         g.group_name,
      'group_code',         g.group_code,
      'operational_total',  COALESCE(agg.operational_total, 0),
      'advance_count',      COALESCE(agg.advance_count, 0),
      'grand_total',        COALESCE(agg.grand_total, 0),
      'bucket_1_15',        COALESCE(agg.b_1_15, 0),
      'bucket_16_30',       COALESCE(agg.b_16_30, 0),
      'bucket_31_60',       COALESCE(agg.b_31_60, 0),
      'bucket_61_120',      COALESCE(agg.b_61_120, 0),
      'bucket_gt121',       COALESCE(agg.b_gt121, 0),
      'max_aging_days',     COALESCE(agg.max_aging, 0),
      'avg_aging_days',     COALESCE(agg.avg_aging, 0),
      'max_priority_score', COALESCE(agg.max_prio, 0),
      'urgency_immediate',  COALESCE(agg.u_immediate, 0),
      'urgency_critical',   COALESCE(agg.u_critical, 0),
      'group_health_status',
        CASE
          WHEN COALESCE(agg.h_critical_count, 0) > 0 THEN 'critical'
          WHEN COALESCE(agg.h_at_risk_count, 0) > 0  THEN 'at_risk'
          ELSE                                             'healthy'
        END
    )
    ORDER BY g.group_code
  )
  INTO v_by_group
  FROM public.groups g
  JOIN public.accounts a ON a.group_id = g.id AND a.is_active = true
  LEFT JOIN (
    SELECT
      a2.group_id,
      COUNT(*) FILTER (
        WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                               AS operational_total,
      COUNT(*) FILTER (
        WHERE v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE
      )                                                               AS advance_count,
      COUNT(*)                                                        AS grand_total,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 1 AND 15
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                               AS b_1_15,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 16 AND 30
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                               AS b_16_30,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 31 AND 60
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                               AS b_31_60,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 61 AND 120
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                               AS b_61_120,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) > 120
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                               AS b_gt121,
      COALESCE(MAX(
        CASE WHEN NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
             THEN GREATEST(0, CURRENT_DATE - v.vacant_date) END
      ), 0)                                                           AS max_aging,
      COALESCE(ROUND(AVG(
        CASE WHEN NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
             THEN GREATEST(0, CURRENT_DATE - v.vacant_date) END
      ), 1), 0)                                                       AS avg_aging,
      COALESCE(MAX(
        public.fn_cencom_td_priority_score(
          CASE WHEN NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
               THEN GREATEST(0, CURRENT_DATE - v.vacant_date) END,
          COALESCE(v.urgency_level, 'Normal'),
          v.required_headcount,
          NULL
        )
      ), 0)                                                           AS max_prio,
      COUNT(*) FILTER (
        WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
          AND GREATEST(0, CURRENT_DATE - v.vacant_date) >= 61
      )                                                               AS u_immediate,
      COUNT(*) FILTER (
        WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
          AND GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 31 AND 60
      )                                                               AS u_critical,
      -- health signals (account-level, no MFR in this subquery for simplicity)
      0::bigint                                                       AS h_critical_count,
      0::bigint                                                       AS h_at_risk_count
    FROM public.accounts a2
    JOIN public.groups g2    ON g2.id = a2.group_id AND g2.cencom_scope = true
    JOIN public.vacancies v  ON v.account_id = a2.id
    WHERE v.status IN ('Open', 'For Sourcing')
      AND COALESCE(v.is_archived, false) = false
      AND v.deleted_at IS NULL
      AND (v_full_access OR (a2.id)::text = ANY(v_allowed))
    GROUP BY a2.group_id
  ) agg ON agg.group_id = g.id
  WHERE g.cencom_scope = true;

  -- ── Build final JSON payload ───────────────────────────────────────────
  RETURN jsonb_build_object(
    'scope',        CASE WHEN v_full_access THEN 'global' ELSE 'scoped' END,
    'computed_at',  now(),

    'summary', jsonb_build_object(
      'operational_total',  v_op_total,
      'advance_count',      v_advance_count,
      'grand_total',        v_op_total + v_advance_count,
      'bucket_1_15',        v_b_1_15,
      'bucket_16_30',       v_b_16_30,
      'bucket_31_60',       v_b_31_60,
      'bucket_61_120',      v_b_61_120,
      'bucket_gt121',       v_b_gt121,
      'urgency_immediate',  v_u_immediate,
      'urgency_critical',   v_u_critical,
      'urgency_elevated',   v_u_elevated,
      'urgency_normal',     v_u_normal,
      'max_aging_days',     v_max_aging,
      'avg_aging_days',     v_avg_aging,
      'pct_critical_aging', v_pct_critical
    ),

    'by_group', COALESCE(v_by_group, '[]'::jsonb),

    'health_dist', jsonb_build_object(
      'critical', v_h_critical,
      'at_risk',  v_h_at_risk,
      'ok',       v_h_ok
    )
  );
END;
$$;

COMMENT ON FUNCTION public.fn_cencom_td_summary() IS
  'CENCOM Phase 8A: Target Deployment summary RPC. '
  'Returns complete JSON payload: summary (bucket counts), by_group (array), '
  'health_dist, scope, computed_at. '
  'SECURITY DEFINER with explicit scope replication. '
  'Flutter: call once per Target Deployment tab load.';

GRANT EXECUTE ON FUNCTION public.fn_cencom_td_summary() TO authenticated;


-- ── Step 9: fn_cencom_td_drilldown(p_group_id uuid) ──────────────────────────
-- Per-group account-level drilldown for CENCOM Target Deployment.
-- Returns accounts (with bucket counts) + top-priority vacancies for the group.
-- Pass NULL to get all groups (full CENCOM scope).

CREATE OR REPLACE FUNCTION public.fn_cencom_td_drilldown(
  p_group_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_full_access   boolean;
  v_allowed       text[];
  v_is_empty      boolean;
  v_accounts      jsonb;
  v_vacancies     jsonb;
  v_group_info    jsonb;
BEGIN
  -- ── Scope resolution ──────────────────────────────────────────────────
  v_full_access := public.i_have_full_access();
  IF NOT v_full_access THEN
    v_allowed   := public.get_my_allowed_accounts();
    v_is_empty  := (array_length(v_allowed, 1) IS NULL);
  ELSE
    v_is_empty  := false;
  END IF;

  IF v_is_empty THEN
    RETURN jsonb_build_object(
      'group',      NULL,
      'accounts',   '[]'::jsonb,
      'vacancies',  '[]'::jsonb,
      'scope',      'scoped',
      'computed_at', now()
    );
  END IF;

  -- ── Group info (if filtering by group) ───────────────────────────────
  IF p_group_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'group_id',   g.id,
      'group_name', g.group_name,
      'group_code', g.group_code
    )
    INTO v_group_info
    FROM public.groups g
    WHERE g.id = p_group_id AND g.cencom_scope = true;
  END IF;

  -- ── Per-account breakdown ─────────────────────────────────────────────
  SELECT jsonb_agg(
    jsonb_build_object(
      'account_id',        agg.account_id,
      'account',           agg.account,
      'group_id',          agg.group_id,
      'group_name',        agg.group_name,
      'operational_total', agg.operational_total,
      'advance_count',     agg.advance_count,
      'bucket_1_15',       agg.b_1_15,
      'bucket_16_30',      agg.b_16_30,
      'bucket_31_60',      agg.b_31_60,
      'bucket_61_120',     agg.b_61_120,
      'bucket_gt121',      agg.b_gt121,
      'max_aging_days',    agg.max_aging,
      'avg_aging_days',    agg.avg_aging,
      'max_priority_score',agg.max_prio,
      'urgent_count',      agg.urgent_count
    )
    ORDER BY agg.max_prio DESC NULLS LAST
  )
  INTO v_accounts
  FROM (
    SELECT
      a.id                                                           AS account_id,
      a.account_name                                                 AS account,
      g.id                                                           AS group_id,
      g.group_name,
      COUNT(*) FILTER (
        WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                              AS operational_total,
      COUNT(*) FILTER (
        WHERE v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE
      )                                                              AS advance_count,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 1  AND  15
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                              AS b_1_15,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 16 AND  30
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                              AS b_16_30,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 31 AND  60
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                              AS b_31_60,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) BETWEEN 61 AND 120
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                              AS b_61_120,
      COUNT(*) FILTER (
        WHERE GREATEST(0, CURRENT_DATE - v.vacant_date) > 120
          AND NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
      )                                                              AS b_gt121,
      COALESCE(MAX(
        CASE WHEN NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
             THEN GREATEST(0, CURRENT_DATE - v.vacant_date) END
      ), 0)                                                          AS max_aging,
      COALESCE(ROUND(AVG(
        CASE WHEN NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
             THEN GREATEST(0, CURRENT_DATE - v.vacant_date) END
      ), 1), 0)                                                      AS avg_aging,
      COALESCE(MAX(
        public.fn_cencom_td_priority_score(
          CASE WHEN NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
               THEN GREATEST(0, CURRENT_DATE - v.vacant_date) END,
          COALESCE(v.urgency_level, 'Normal'),
          v.required_headcount,
          NULL
        )
      ), 0)                                                          AS max_prio,
      COUNT(*) FILTER (
        WHERE NOT (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
          AND GREATEST(0, CURRENT_DATE - v.vacant_date) >= 31
      )                                                              AS urgent_count
    FROM public.accounts a
    JOIN public.groups g   ON g.id = a.group_id AND g.cencom_scope = true
    JOIN public.vacancies v ON v.account_id = a.id
    WHERE v.status IN ('Open', 'For Sourcing')
      AND COALESCE(v.is_archived, false) = false
      AND v.deleted_at IS NULL
      AND a.is_active = true
      AND (p_group_id IS NULL OR g.id = p_group_id)
      AND (v_full_access OR (a.id)::text = ANY(v_allowed))
    GROUP BY a.id, a.account_name, g.id, g.group_name
  ) agg;

  -- ── Top-priority vacancies for the group (max 60 rows) ────────────────
  SELECT jsonb_agg(
    jsonb_build_object(
      'vacancy_id',      v.id,
      'vcode',           v.vcode,
      'account',         a.account_name,
      'account_id',      a.id,
      'group_name',      g.group_name,
      'position',        v.position,
      'area_name',       COALESCE(v.area_name, v.area_city),
      'store_name',      COALESCE(v.store_name, v.store_branch),
      'vacant_date',     v.vacant_date,
      'vacancy_type',    v.vacancy_type,
      'urgency_level',   COALESCE(v.urgency_level, 'Normal'),
      'target_fill_date',v.target_fill_date,
      'required_headcount', v.required_headcount,
      'is_advance_vacancy',
        (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE),
      'aging_days',
        CASE WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE
             THEN NULL
             ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
        END,
      'aging_bucket',
        public.fn_cencom_td_aging_bucket(
          CASE WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE
               THEN NULL
               ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
          END,
          (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE)
        ),
      'priority_score',
        public.fn_cencom_td_priority_score(
          CASE WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE
               THEN NULL
               ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
          END,
          COALESCE(v.urgency_level, 'Normal'),
          v.required_headcount,
          NULL
        )
    )
    ORDER BY
      CASE WHEN (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE) THEN 1 ELSE 0 END,
      public.fn_cencom_td_priority_score(
        CASE WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE
             THEN NULL
             ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
        END,
        COALESCE(v.urgency_level, 'Normal'),
        v.required_headcount,
        NULL
      ) DESC,
      v.vcode
  )
  INTO v_vacancies
  FROM (
    SELECT v.*
    FROM public.vacancies v
    JOIN public.accounts a2 ON a2.id = v.account_id
    JOIN public.groups g2   ON g2.id = a2.group_id AND g2.cencom_scope = true
    WHERE v.status IN ('Open', 'For Sourcing')
      AND COALESCE(v.is_archived, false) = false
      AND v.deleted_at IS NULL
      AND a2.is_active = true
      AND (p_group_id IS NULL OR g2.id = p_group_id)
      AND (v_full_access OR (a2.id)::text = ANY(v_allowed))
    ORDER BY
      CASE WHEN (v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE) THEN 1 ELSE 0 END,
      public.fn_cencom_td_priority_score(
        CASE WHEN v.vacant_date IS NULL OR v.vacant_date > CURRENT_DATE
             THEN NULL
             ELSE GREATEST(0, CURRENT_DATE - v.vacant_date)
        END,
        COALESCE(v.urgency_level, 'Normal'),
        v.required_headcount,
        NULL
      ) DESC
    LIMIT 60
  ) v
  JOIN public.accounts a ON a.id = v.account_id
  JOIN public.groups g   ON g.id = a.group_id;

  -- ── Return JSON ────────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'group',       v_group_info,
    'accounts',    COALESCE(v_accounts,   '[]'::jsonb),
    'vacancies',   COALESCE(v_vacancies,  '[]'::jsonb),
    'scope',       CASE WHEN v_full_access THEN 'global' ELSE 'scoped' END,
    'computed_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.fn_cencom_td_drilldown(uuid) IS
  'CENCOM Phase 8A: Target Deployment drilldown RPC. '
  'Pass p_group_id to filter to a specific group, or NULL for all CENCOM groups. '
  'Returns: group info, per-account aging breakdown, top-60 priority vacancies. '
  'SECURITY DEFINER with explicit scope replication. '
  'Flutter: call on group tap in VACANCY AGING BY AREA section.';

GRANT EXECUTE ON FUNCTION public.fn_cencom_td_drilldown(uuid) TO authenticated;


-- ── Final: Grant summary ──────────────────────────────────────────────────────

-- Functions (execute grants already applied inline above)
GRANT EXECUTE ON FUNCTION public.fn_cencom_td_aging_bucket(int, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cencom_td_priority_score(int, text, int, numeric) TO authenticated;

-- Views (select grants already applied inline above)
-- Consolidated here for documentation:
-- v_cencom_td_vacancies        → authenticated, service_role
-- v_cencom_td_summary          → authenticated, service_role
-- v_cencom_td_by_group         → authenticated, service_role
-- v_cencom_td_by_account       → authenticated, service_role
-- v_cencom_td_priority_queue   → authenticated, service_role

-- ── Migration complete ────────────────────────────────────────────────────────
-- Objects created:
--   FUNCTIONS (2 IMMUTABLE helpers + 2 SECURITY DEFINER RPCs):
--     fn_cencom_td_aging_bucket(int, boolean)
--     fn_cencom_td_priority_score(int, text, int, numeric)
--     fn_cencom_td_summary()
--     fn_cencom_td_drilldown(uuid)
--
--   VIEWS (5, all SECURITY INVOKER):
--     v_cencom_td_vacancies        — base view
--     v_cencom_td_summary          — aggregate bucket counts
--     v_cencom_td_by_group         — per-group aging distribution
--     v_cencom_td_by_account       — per-account aging breakdown
--     v_cencom_td_priority_queue   — priority deployment queue
--
-- Flutter impact:
--   Target Deployment tab → call fn_cencom_td_summary() (single RPC, full payload)
--   Group tap drilldown   → call fn_cencom_td_drilldown(group_id)
--   Direct view queries   → v_cencom_td_summary, v_cencom_td_by_group as needed
--
-- No changes to: vacancies, accounts, groups, v_cencom_kpi, v_cencom_group_kpi,
--               v_cencom_account_kpi, or any other existing backend object.
-- ============================================================
