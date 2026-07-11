-- ============================================================
-- OHMployee — CENCOM Backend Phase 1
-- Scope: Restrict CENCOM backend to Group 1–5 operational groups.
--        Exclude Moses HQ, Global HQ, HQ, corporate, plantilla-only.
--
-- What this migration does:
--   1. Adds `cencom_scope` boolean column to `groups`.
--   2. Seeds Group 1–5 as cencom_scope = TRUE via pattern match.
--   3. Creates `v_cencom_account_kpi` — RLS-respecting base view
--      filtered to cencom_scope groups.
--   4. Replaces `v_cencom_kpi` — now aggregates cencom_scope only.
--   5. Creates `v_cencom_group_kpi` — per-group CENCOM breakdown.
--
-- Rollback:
--   DROP VIEW IF EXISTS public.v_cencom_group_kpi;
--   CREATE OR REPLACE VIEW public.v_cencom_kpi AS
--     SELECT ... FROM public.v_account_kpi; (restore original)
--   DROP VIEW IF EXISTS public.v_cencom_account_kpi;
--   ALTER TABLE public.groups DROP COLUMN IF EXISTS cencom_scope;
--
-- v_account_kpi and v_group_kpi are NOT modified (they remain
-- general-purpose views used by dashboards and other modules).
-- ============================================================

-- ── Step 1: Add cencom_scope to groups ────────────────────────────────────────
ALTER TABLE public.groups
  ADD COLUMN IF NOT EXISTS cencom_scope boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.groups.cencom_scope IS
  'TRUE = operational group included in all CENCOM metrics, snapshots, and reports (Group 1–5). '
  'FALSE = excluded (Moses HQ, Global HQ, HQ, corporate, plantilla-only reporting). '
  'Managed by Data Team / Super Admin only.';

-- ── Step 2: Seed Group 1–5 ───────────────────────────────────────────────────
-- Seeds based on group_name pattern. Matches "Group 1" through "Group 5"
-- (case-insensitive, with optional whitespace) and excludes any name that
-- contains HQ, Headquarters, Corporate, Moses, or Global.
--
-- ⚠ VERIFY before relying on data:
--   SELECT id, group_code, group_name, cencom_scope FROM groups ORDER BY group_name;
--
UPDATE public.groups
SET    cencom_scope = true
WHERE  group_name ~* '^group\s*[1-5](\s|$)'
  AND  group_name !~* 'hq|headquarters|corporate|moses|global|plantilla';

-- ── Step 3: v_cencom_account_kpi ─────────────────────────────────────────────
-- CENCOM-scoped per-account KPI view.
-- Inherits the full RLS logic of v_account_kpi (i_have_full_access OR
-- get_my_allowed_accounts) and additionally restricts to cencom_scope groups.
-- This is the authoritative base for all CENCOM aggregations.

DROP VIEW IF EXISTS public.v_cencom_account_kpi;

CREATE VIEW public.v_cencom_account_kpi
  WITH (security_invoker = true)
AS
SELECT
  ak.account_id,
  ak.account_name,
  ak.account_code,
  ak.group_id,
  ak.group_name,
  ak.group_code,
  ak.actual_hc,
  ak.pipeline_count,
  ak.vacant_count,
  ak.required_hc,
  ak.mfr,
  ak.projected_mfr,
  ak.vacancy_rate,
  ak.pipeline_coverage,
  ak.health_status
FROM   public.v_account_kpi ak
JOIN   public.groups g ON g.id = ak.group_id
WHERE  g.cencom_scope = true;

ALTER VIEW public.v_cencom_account_kpi OWNER TO postgres;

COMMENT ON VIEW public.v_cencom_account_kpi IS
  'Per-account KPI restricted to CENCOM operational groups (cencom_scope = true). '
  'Inherits RLS from v_account_kpi. Base view for v_cencom_kpi and v_cencom_group_kpi.';

GRANT SELECT ON public.v_cencom_account_kpi TO authenticated;
GRANT SELECT ON public.v_cencom_account_kpi TO service_role;

-- ── Step 4: Replace v_cencom_kpi ─────────────────────────────────────────────
-- Now aggregates only cencom_scope groups via v_cencom_account_kpi.
-- Signature unchanged — existing consumers are unaffected.

CREATE OR REPLACE VIEW public.v_cencom_kpi
  WITH (security_invoker = true)
AS
SELECT
  sum(actual_hc)::bigint                                                                AS actual_hc,
  sum(pipeline_count)::bigint                                                           AS pipeline_count,
  sum(vacant_count)::bigint                                                             AS vacant_count,
  sum(required_hc)::bigint                                                              AS required_hc,
  CASE
    WHEN sum(required_hc) = 0 THEN 1.0
    ELSE round(sum(actual_hc) / sum(required_hc), 4)
  END                                                                                   AS mfr,
  CASE
    WHEN sum(required_hc) = 0 THEN 1.0
    ELSE round((sum(actual_hc) + sum(pipeline_count)) / sum(required_hc), 4)
  END                                                                                   AS projected_mfr,
  CASE
    WHEN sum(required_hc) = 0 THEN 0.0
    ELSE round(sum(vacant_count) / sum(required_hc), 4)
  END                                                                                   AS vacancy_rate,
  CASE
    WHEN sum(required_hc) = 0 THEN 0.0
    ELSE round(sum(pipeline_count) / sum(required_hc), 4)
  END                                                                                   AS pipeline_coverage,
  CASE
    WHEN sum(required_hc) = 0                              THEN 'healthy'::text
    WHEN sum(actual_hc) / sum(required_hc) >= 1.0          THEN 'healthy'::text
    WHEN sum(actual_hc) / sum(required_hc) >= 0.9          THEN 'at_risk'::text
    ELSE                                                        'critical'::text
  END                                                                                   AS health_status
FROM public.v_cencom_account_kpi;

ALTER VIEW public.v_cencom_kpi OWNER TO postgres;

COMMENT ON VIEW public.v_cencom_kpi IS
  'Aggregate CENCOM KPI — Group 1–5 operational groups only (cencom_scope = true). '
  'Moses HQ, Global HQ, HQ, corporate, and plantilla-only groups are excluded. '
  'Phase 1 — Backend scope restriction.';

GRANT SELECT ON public.v_cencom_kpi TO authenticated;
GRANT SELECT ON public.v_cencom_kpi TO service_role;

-- ── Step 5: Create v_cencom_group_kpi ─────────────────────────────────────────
-- Per-group CENCOM breakdown (Group 1–5 only).
-- Distinct from v_group_kpi which remains unfiltered for general use.

DROP VIEW IF EXISTS public.v_cencom_group_kpi;

CREATE VIEW public.v_cencom_group_kpi
  WITH (security_invoker = true)
AS
SELECT
  group_id,
  group_name,
  group_code,
  sum(actual_hc)::bigint                                                                AS actual_hc,
  sum(pipeline_count)::bigint                                                           AS pipeline_count,
  sum(vacant_count)::bigint                                                             AS vacant_count,
  sum(required_hc)::bigint                                                              AS required_hc,
  CASE
    WHEN sum(required_hc) = 0 THEN 1.0
    ELSE round(sum(actual_hc) / sum(required_hc), 4)
  END                                                                                   AS mfr,
  CASE
    WHEN sum(required_hc) = 0 THEN 1.0
    ELSE round((sum(actual_hc) + sum(pipeline_count)) / sum(required_hc), 4)
  END                                                                                   AS projected_mfr,
  CASE
    WHEN sum(required_hc) = 0 THEN 0.0
    ELSE round(sum(vacant_count) / sum(required_hc), 4)
  END                                                                                   AS vacancy_rate,
  CASE
    WHEN sum(required_hc) = 0 THEN 0.0
    ELSE round(sum(pipeline_count) / sum(required_hc), 4)
  END                                                                                   AS pipeline_coverage,
  CASE
    WHEN sum(required_hc) = 0                              THEN 'healthy'::text
    WHEN sum(actual_hc) / sum(required_hc) >= 1.0          THEN 'healthy'::text
    WHEN sum(actual_hc) / sum(required_hc) >= 0.9          THEN 'at_risk'::text
    ELSE                                                        'critical'::text
  END                                                                                   AS health_status
FROM public.v_cencom_account_kpi
GROUP BY group_id, group_name, group_code;

ALTER VIEW public.v_cencom_group_kpi OWNER TO postgres;

COMMENT ON VIEW public.v_cencom_group_kpi IS
  'Per-group CENCOM KPI for Group 1–5 operational groups only. '
  'Use this for CENCOM group breakdowns — NOT v_group_kpi (which is unfiltered). '
  'Phase 1 — Backend scope restriction.';

GRANT SELECT ON public.v_cencom_group_kpi TO authenticated;
GRANT SELECT ON public.v_cencom_group_kpi TO service_role;
