-- ============================================================================
-- OHM2026_0066 — Allocation-Based Fractional HC + Unified MFR (v1)
-- ============================================================================
-- ADDITIVE migration. Does NOT modify or drop any existing migration, view, or
-- RPC. Establishes `employee_store_allocations` as the single source of truth
-- for operational HC contribution, with fractional (roving-aware) Filled HC.
--
-- Operational definitions (canonical):
--   Required HC = Filled HC + pipeline + Open HC   (preserves existing additive
--                 model in v_account_kpi; no stored per-store target exists)
--   Filled HC   = SUM(active employee_store_allocations.filled_hc)
--   Actual HC   = COUNT(DISTINCT active employees)            (integer headcount)
--   Open HC     = open, non-archived, non-pool vacancies
--   MFR         = Filled HC / Required HC
--
-- Allocation rules:
--   Stationary employee → 1 active allocation, filled_hc = 1.0
--   Roving employee     → N active allocations, filled_hc = 1/N each
--   Only is_active allocations count. Inactive / archived / rolled-back /
--   vacancy-placeholder rows are excluded.
--
-- IMPORTANT — why this is additive and NOT a destructive replace of v_account_kpi:
--   v_account_kpi exposes actual_hc / required_hc as bigint (integer COUNT).
--   Fractional filled_hc requires numeric columns. PostgreSQL CREATE OR REPLACE
--   VIEW cannot change a column's type, so swapping those columns would require
--   DROP VIEW ... CASCADE across the entire CENCOM view stack
--   (v_cencom_account_kpi, v_cencom_kpi, v_cencom_group_kpi, all v_cencom_td_*),
--   plus risks breaking Flutter clients that decode bigint HC. That destructive
--   cutover is deferred to a separate, approved phase. This migration ships the
--   canonical allocation layer side-by-side under new `*_allocation_*` names.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- §1  Recompute helper — normalize an employee's active allocations to 1.0 HC
-- ----------------------------------------------------------------------------
-- Reuse for: roving store loss, rollback, reassignment, plantilla archival.
-- Equal-split V1: filled_hc = round(1/active_store_count, 4) per active row.
-- Rounding remainder (e.g. 3 stores → 0.3333*3 = 0.9999) is folded into the
-- first row so SUM(filled_hc) is EXACTLY 1.0 per active employee. This makes
-- the normalization invariant (SUM = 1) hold strictly, not just approximately.
--
-- Idempotent: running repeatedly yields the same result.
CREATE OR REPLACE FUNCTION public.fn_recompute_employee_allocation_hc(p_employee_no text)
  RETURNS numeric
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_cnt        integer;
  v_each       numeric(8,4);
  v_remainder  numeric(8,4);
  v_first_id   uuid;
  v_total      numeric;
BEGIN
  IF p_employee_no IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_cnt
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no AND is_active;

  IF v_cnt = 0 THEN
    RETURN 0;
  END IF;

  v_each      := round(1.0 / v_cnt, 4);
  v_remainder := round(1.0 - (v_each * v_cnt), 4);  -- correction folded into row 1

  SELECT id INTO v_first_id
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no AND is_active
  ORDER BY effective_start, created_at, id
  LIMIT 1;

  UPDATE public.employee_store_allocations
     SET active_store_count = v_cnt,
         filled_hc = CASE WHEN id = v_first_id THEN v_each + v_remainder ELSE v_each END
   WHERE employee_no = p_employee_no AND is_active;

  SELECT COALESCE(sum(filled_hc), 0) INTO v_total
  FROM public.employee_store_allocations
  WHERE employee_no = p_employee_no AND is_active;

  RETURN v_total;
END;
$function$;

COMMENT ON FUNCTION public.fn_recompute_employee_allocation_hc(text) IS
  'Normalizes an employee''s active allocations so SUM(filled_hc)=1.0 exactly '
  '(equal split 1/active_store_count, rounding remainder folded into first row). '
  'Idempotent. Reuse on roving change, rollback, reassignment, plantilla archival.';

REVOKE ALL ON FUNCTION public.fn_recompute_employee_allocation_hc(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_recompute_employee_allocation_hc(text) TO service_role;

-- ----------------------------------------------------------------------------
-- §2  Store / VCODE-level allocation HC (canonical Filled HC source of truth)
-- ----------------------------------------------------------------------------
-- RLS: security_invoker → inherits esa_select policy on employee_store_allocations
-- (i_have_full_access() OR account_id = ANY(get_my_allowed_account_ids())).
CREATE OR REPLACE VIEW public.v_store_allocation_hc
  WITH (security_invoker = true)
AS
SELECT
  a.store_id,
  a.vcode,
  max(a.store_name)                                              AS store_name,
  a.account_id,
  a.group_id,
  round(COALESCE(sum(a.filled_hc), 0), 4)                        AS filled_hc,
  count(DISTINCT a.employee_no)                                  AS actual_hc,
  round(COALESCE(sum(a.filled_hc) FILTER (WHERE a.active_store_count > 1), 0), 4)
                                                                 AS roving_hc,
  round(COALESCE(sum(a.filled_hc) FILTER (WHERE a.active_store_count = 1), 0), 4)
                                                                 AS stationary_hc
FROM public.employee_store_allocations a
WHERE a.is_active
GROUP BY a.store_id, a.vcode, a.account_id, a.group_id;

ALTER VIEW public.v_store_allocation_hc OWNER TO postgres;
COMMENT ON VIEW public.v_store_allocation_hc IS
  'Canonical per-store Filled HC from active employee_store_allocations. '
  'filled_hc = SUM(active filled_hc); actual_hc = distinct active employees. '
  'Roving employees contribute fractionally, never double-counted.';
GRANT SELECT ON public.v_store_allocation_hc TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- §3  Account-level allocation KPI (Filled HC / Required HC / MFR)
-- ----------------------------------------------------------------------------
-- Mirrors v_account_kpi semantics but Filled HC replaces the raw active COUNT.
-- pipeline / open vacancy predicates match v_account_kpi exactly.
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
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM   public.vacancies vv
  WHERE  vv.status = 'Open'
    AND  COALESCE(vv.is_archived, false) = false
    AND  COALESCE(vv.is_pool_vacancy, false) = false
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
  'Required HC = Filled HC + pipeline + Open HC; MFR = Filled HC / Required HC. '
  'Canonical allocation-aware companion to v_account_kpi (which keeps integer COUNT).';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- §4  CENCOM-scoped account allocation KPI (Group 1–5 only)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_cencom_account_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT ak.*
FROM   public.v_account_allocation_kpi ak
JOIN   public.groups g ON g.id = ak.group_id
WHERE  g.cencom_scope = true;

ALTER VIEW public.v_cencom_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_account_allocation_kpi IS
  'Allocation-based per-account KPI restricted to CENCOM groups (cencom_scope=true).';
GRANT SELECT ON public.v_cencom_account_allocation_kpi TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- §5  CENCOM per-group + aggregate allocation rollups
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_cencom_group_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  group_id, group_name, group_code,
  round(sum(filled_hc), 4)        AS filled_hc,
  sum(actual_hc)::bigint          AS actual_hc,
  sum(pipeline_count)::bigint     AS pipeline_count,
  sum(open_hc)::bigint            AS open_hc,
  round(sum(required_hc), 4)      AS required_hc,
  CASE WHEN sum(required_hc) = 0 THEN 1.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 1.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(open_hc) / sum(required_hc), 4) END                 AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                          THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0      THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9      THEN 'at_risk'::text
       ELSE                                                    'critical'::text
  END                                                                     AS health_status
FROM public.v_cencom_account_allocation_kpi
GROUP BY group_id, group_name, group_code;

ALTER VIEW public.v_cencom_group_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_group_allocation_kpi IS
  'Allocation-based per-group CENCOM KPI (Group 1–5). Filled HC drives MFR.';
GRANT SELECT ON public.v_cencom_group_allocation_kpi TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_cencom_allocation_kpi
  WITH (security_invoker = true)
AS
SELECT
  round(sum(filled_hc), 4)        AS filled_hc,
  sum(actual_hc)::bigint          AS actual_hc,
  sum(pipeline_count)::bigint     AS pipeline_count,
  sum(open_hc)::bigint            AS open_hc,
  round(sum(required_hc), 4)      AS required_hc,
  CASE WHEN sum(required_hc) = 0 THEN 1.0
       ELSE round(sum(filled_hc) / sum(required_hc), 4) END               AS mfr,
  CASE WHEN sum(required_hc) = 0 THEN 1.0
       ELSE round((sum(filled_hc) + sum(pipeline_count)) / sum(required_hc), 4) END AS projected_mfr,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(open_hc) / sum(required_hc), 4) END                 AS vacancy_rate,
  CASE WHEN sum(required_hc) = 0 THEN 0.0
       ELSE round(sum(pipeline_count) / sum(required_hc), 4) END          AS pipeline_coverage,
  CASE WHEN sum(required_hc) = 0                          THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 1.0      THEN 'healthy'::text
       WHEN sum(filled_hc) / sum(required_hc) >= 0.9      THEN 'at_risk'::text
       ELSE                                                    'critical'::text
  END                                                                     AS health_status
FROM public.v_cencom_account_allocation_kpi;

ALTER VIEW public.v_cencom_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_cencom_allocation_kpi IS
  'Allocation-based aggregate CENCOM KPI (Group 1–5). Single source of truth for '
  'unified allocation-aware MFR. Companion to v_cencom_kpi (integer COUNT).';
GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated, service_role;

COMMIT;
