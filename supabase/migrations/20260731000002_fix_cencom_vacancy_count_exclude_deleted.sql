-- ============================================================================
-- OHM2026_1155 — Fix CENCOM Vacancy Count: Exclude Soft-Deleted Vacancies
-- ============================================================================
-- PROBLEM:
--   The `vacant` CTE in `v_account_allocation_kpi` (OHM2026_0070) was missing
--   `AND vv.deleted_at IS NULL`. Soft-deleted vacancies (deleted_at IS NOT NULL
--   from Import Vacancy rollbacks) retained status='Open', and were therefore
--   counted as open HC in all CENCOM allocation KPI views.
--
--   Example: MORE account had 21 Import Vacancy rollback rows with
--   status='Open' AND deleted_at IS NOT NULL that inflated its open_hc by 21.
--
-- CANONICAL ACTIVE-VACANCY RULE (enforced from this migration forward):
--   A vacancy counts as open HC only when ALL of the following are true:
--     status = 'Open'
--     deleted_at IS NULL                    ← was missing; added by this fix
--     COALESCE(is_archived, false) = false
--     COALESCE(is_pool_vacancy, false) = false
--     COALESCE(affects_required_hc, true) = true  (roving-aware; from OHM2026_0070)
--
-- SCOPE:
--   Only `v_account_allocation_kpi` is changed (the `vacant` CTE only).
--   CENCOM rollup views (`v_cencom_account_allocation_kpi`,
--   `v_cencom_group_allocation_kpi`, `v_cencom_allocation_kpi`) inherit the
--   fix automatically — no body change needed there.
--   `v_cencom_td_vacancies` (Phase 8A) already had `v.deleted_at IS NULL`
--   and is untouched.
--   No Flutter, no RLS, no trigger, no workflow changes.
--
-- ADDITIVE: No DROP, no CASCADE, no column-type change.
-- ============================================================================

BEGIN;

-- ── Validation: per-account vacancy discrepancy before fix ────────────────────
-- Run the queries below in the Supabase SQL Editor before and after applying
-- to confirm the MORE account (and any others) drop to correct open_hc values.
--
-- V1 — raw vs active vs deleted open count per account:
--   SELECT
--     a.account_name,
--     COUNT(v.id)                                                    AS raw_open,
--     COUNT(v.id) FILTER (WHERE v.deleted_at IS NULL
--                            AND COALESCE(v.is_archived,false)=false)  AS active_open,
--     COUNT(v.id) FILTER (WHERE v.deleted_at IS NOT NULL)             AS deleted_open,
--     COUNT(v.id) FILTER (WHERE COALESCE(v.is_archived,false)=true)   AS archived_open
--   FROM public.vacancies v
--   JOIN public.accounts a ON a.id = v.account_id
--   WHERE v.status = 'Open'
--   GROUP BY a.account_name
--   ORDER BY deleted_open DESC, a.account_name;
--
-- V2 — group totals from the allocation view (run after applying):
--   SELECT group_name, open_hc, required_hc, mfr
--   FROM public.v_cencom_group_allocation_kpi
--   ORDER BY group_name;
-- ─────────────────────────────────────────────────────────────────────────────

-- Recreate base allocation KPI view with the deleted_at guard added to vacant CTE.
-- Body is identical to OHM2026_0070 except the single added predicate on line ~209.
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
  -- Roving-safe by construction: hr_emploc holds ONE master row per roving
  -- group (uq_hr_emploc_roving_assignment), so each roving applicant counts as
  -- 1 pipeline HC — never per store link.
  SELECT he.account_id, count(*) AS pipeline_count
  FROM   public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE  he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND  he.deleted_at IS NULL
    AND  COALESCE(v.is_archived, false) = false
    AND  COALESCE(v.is_pool_vacancy, false) = false
  GROUP  BY he.account_id
),
vacant AS (
  -- Canonical active-vacancy predicate (see migration header for the full rule).
  -- deleted_at IS NULL added by OHM2026_1155 to exclude soft-deleted rows.
  SELECT vv.account_id, count(*) AS open_hc
  FROM   public.vacancies vv
  WHERE  vv.status = 'Open'
    AND  vv.deleted_at IS NULL                                         -- ← fix
    AND  COALESCE(vv.is_archived, false) = false
    AND  COALESCE(vv.is_pool_vacancy, false) = false
    AND  COALESCE(vv.affects_required_hc, true) = true   -- roving-aware: satellites excluded
  GROUP  BY vv.account_id
),
base AS (
  SELECT
    a.id                                  AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    COALESCE(f.filled_hc, 0)::numeric(12,4)   AS filled_hc,
    COALESCE(f.actual_hc, 0)                  AS actual_hc,
    COALESCE(p.pipeline_count, 0)             AS pipeline_count,
    COALESCE(v.open_hc, 0)                    AS open_hc,
    round(COALESCE(f.filled_hc, 0)
        + COALESCE(p.pipeline_count, 0)
        + COALESCE(v.open_hc, 0), 4)::numeric(12,4) AS required_hc
  FROM   public.accounts a
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN filled   f ON f.account_id = a.id
  LEFT JOIN pipeline p ON p.account_id = a.id
  LEFT JOIN vacant   v ON v.account_id = a.id
  WHERE  a.is_active = true
    AND  COALESCE(a.is_pool_account, false) = false
    AND  (public.i_have_full_access()
          OR a.id = ANY (public.get_my_allowed_account_ids()))
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc, actual_hc, pipeline_count, open_hc, required_hc,
  CASE WHEN required_hc = 0 THEN 1.0
       ELSE round(filled_hc / required_hc, 4) END                 AS mfr,
  CASE WHEN required_hc = 0 THEN 1.0
       ELSE round((filled_hc + pipeline_count) / required_hc, 4) END AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(open_hc / required_hc, 4) END                   AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END            AS pipeline_coverage,
  CASE WHEN required_hc = 0                       THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 1.0        THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 0.9        THEN 'at_risk'::text
       ELSE                                            'critical'::text
  END                                                             AS health_status
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'Allocation-based per-account KPI. Filled HC = SUM(active filled_hc); '
  'Open HC = open non-deleted non-archived non-pool vacancies WHERE affects_required_hc=true '
  '(deleted_at IS NULL — OHM2026_1155; roving satellites excluded — OHM2026_0070); '
  'Required HC = Filled+pipeline+Open; MFR = Filled HC / Required HC. '
  'Companion to v_account_kpi (integer COUNT).';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

-- CENCOM rollup views (v_cencom_account_allocation_kpi, v_cencom_group_allocation_kpi,
-- v_cencom_allocation_kpi) derive open_hc by reference/SUM from this base view.
-- They inherit the corrected count automatically — no body change required.

COMMIT;
