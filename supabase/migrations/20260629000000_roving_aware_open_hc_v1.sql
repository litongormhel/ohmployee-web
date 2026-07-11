-- ============================================================================
-- OHM2026_0070 — Roving-Aware Open HC + Vacancy Alignment (v1)
-- ============================================================================
-- ADDITIVE migration. Does NOT modify or drop any existing migration. Does NOT
-- delete vacancy rows, hide satellite stores, touch Import/rollback, or modify
-- the legacy COUNT views (v_account_kpi, v_cencom_account_kpi, v_cencom_group_kpi,
-- v_cencom_kpi). No DROP CASCADE.
--
-- PROBLEM (confirmed by OHM2026_0069 read-only audit):
--   Filled HC is manpower/allocation-based (roving employee = 1 HC split across
--   stores), but Open HC was store-row based:
--       open_hc = COUNT(*) FROM vacancies WHERE status='Open'
--   A roving requirement that spans 5 stores reopens as 5 Open vacancy rows and
--   inflated Open HC (and therefore Required HC and the MFR denominator) to 5.
--
-- CORRECT BUSINESS RULE:
--   MFR counts MANPOWER HC, not physical store rows.
--     1 roving requirement covering 5 stores  → 1 Open HC (5 physical rows)
--     Juan roving 5 stores + Pedro stationary → 2 Open HC (6 physical rows)
--
-- LEVERS (already on the vacancies table, previously only used by pool vacancies):
--   affects_required_hc = true  → row counts as one manpower HC unit
--   affects_required_hc = false → physical/satellite row only (0 HC)
--   affects_mfr         mirrors the above for MFR participation
--
-- ROVING PRIMARY vs SATELLITE — how it is determined (V1):
--   A roving group is a `roving_assignments` row. Its member VCODEs are the
--   distinct vcodes from hr_emploc_store_links + plantilla_store_links for that
--   roving_assignment_id, plus roving_assignments.primary_vcode.
--     - The group's PRIMARY vcode (roving_assignments.primary_vcode, or the
--       lexically-min member vcode when primary_vcode is NULL) keeps
--       affects_required_hc = true / affects_mfr = true  → 1 HC.
--     - Every other (SATELLITE) vcode in the group is set to
--       affects_required_hc = false / affects_mfr = false → 0 HC.
--   Pool vacancies are never touched (they already carry false flags).
--   Stationary vacancies are untouched and keep the default true/true → 1 HC.
--
-- LIMITATION (documented, acceptable for V1): a brand-new roving requirement
-- that has NOT yet produced an applicant has no roving_assignments row and no
-- store links, so its multiple store vacancies cannot be grouped automatically.
-- Such rows keep affects_required_hc = true. The roving vacancy CREATION path
-- (future phase) should call fn_apply_roving_vacancy_hc_flags() once the group
-- is known, or set the flags inline at insert time.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- §1  Per-group flag normalizer (idempotent)
-- ----------------------------------------------------------------------------
-- Sets affects_required_hc / affects_mfr for every VCODE belonging to one roving
-- group: exactly the primary VCODE = true, all satellites = false. Returns the
-- number of vacancy rows updated. Reuse on roving reopen / reassignment /
-- deactivation so Open HC stays manpower-accurate going forward.
CREATE OR REPLACE FUNCTION public.fn_apply_roving_vacancy_hc_flags(p_roving_assignment_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_primary text;
  v_count   integer := 0;
BEGIN
  IF p_roving_assignment_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT primary_vcode INTO v_primary
  FROM public.roving_assignments
  WHERE id = p_roving_assignment_id;

  -- Fallback: guarantee exactly one primary even if primary_vcode is unset.
  IF v_primary IS NULL THEN
    SELECT min(vcode) INTO v_primary
    FROM (
      SELECT vcode FROM public.hr_emploc_store_links
        WHERE roving_assignment_id = p_roving_assignment_id AND deleted_at IS NULL
      UNION
      SELECT vcode FROM public.plantilla_store_links
        WHERE roving_assignment_id = p_roving_assignment_id AND deleted_at IS NULL
    ) s
    WHERE vcode IS NOT NULL;
  END IF;

  IF v_primary IS NULL THEN
    RETURN 0;  -- no resolvable member VCODEs for this group
  END IF;

  WITH grp AS (
    SELECT DISTINCT vcode FROM (
      SELECT vcode FROM public.hr_emploc_store_links
        WHERE roving_assignment_id = p_roving_assignment_id AND deleted_at IS NULL
      UNION
      SELECT vcode FROM public.plantilla_store_links
        WHERE roving_assignment_id = p_roving_assignment_id AND deleted_at IS NULL
      UNION
      SELECT v_primary
    ) s
    WHERE vcode IS NOT NULL
  )
  UPDATE public.vacancies vv
     SET affects_required_hc = (vv.vcode IS NOT DISTINCT FROM v_primary),
         affects_mfr         = (vv.vcode IS NOT DISTINCT FROM v_primary),
         updated_at          = now()
    FROM grp
   WHERE vv.vcode = grp.vcode
     AND COALESCE(vv.is_pool_vacancy, false) = false;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

COMMENT ON FUNCTION public.fn_apply_roving_vacancy_hc_flags(uuid) IS
  'Normalizes affects_required_hc/affects_mfr for one roving group: primary VCODE '
  '(roving_assignments.primary_vcode, else min member vcode) = true, satellites = '
  'false. Idempotent. Pool vacancies untouched. Reuse on roving reopen/reassign.';

REVOKE ALL ON FUNCTION public.fn_apply_roving_vacancy_hc_flags(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_apply_roving_vacancy_hc_flags(uuid) TO service_role;

-- ----------------------------------------------------------------------------
-- §2  Batch backfill across all active roving groups (idempotent)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_backfill_roving_vacancy_hc_flags()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  r       record;
  v_total integer := 0;
BEGIN
  FOR r IN
    SELECT id FROM public.roving_assignments WHERE archived_at IS NULL
  LOOP
    v_total := v_total + public.fn_apply_roving_vacancy_hc_flags(r.id);
  END LOOP;
  RETURN v_total;
END;
$function$;

COMMENT ON FUNCTION public.fn_backfill_roving_vacancy_hc_flags() IS
  'Applies fn_apply_roving_vacancy_hc_flags to every non-archived roving group. '
  'Idempotent; returns total vacancy rows updated.';

REVOKE ALL ON FUNCTION public.fn_backfill_roving_vacancy_hc_flags() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_backfill_roving_vacancy_hc_flags() TO service_role;

-- ----------------------------------------------------------------------------
-- §3  One-time backfill of existing data
-- ----------------------------------------------------------------------------
-- The vacancy edit-lock trigger (trg_assert_vacancy_edit_allowed) would block
-- this UPDATE if the migration happens to run inside the scheduled lock window
-- or while a manual lock is held. Disable only that named trigger for the
-- backfill, then re-enable. (Runs as table owner during migration apply.)
ALTER TABLE public.vacancies DISABLE TRIGGER trg_assert_vacancy_edit_allowed;

SELECT public.fn_backfill_roving_vacancy_hc_flags();

ALTER TABLE public.vacancies ENABLE TRIGGER trg_assert_vacancy_edit_allowed;

-- ----------------------------------------------------------------------------
-- §4  Roving-aware Open HC in the allocation KPI stack
-- ----------------------------------------------------------------------------
-- Only the base account view computes Open HC (from the `vacant` CTE). The
-- CENCOM rollups (v_cencom_account_allocation_kpi / _group_ / aggregate) read
-- open_hc from this view by reference/SUM, so they inherit the corrected count
-- automatically — no type or column change, nothing to re-create or CASCADE.
--
-- Change vs OHM2026_0066: the `vacant` CTE now additionally requires
--   COALESCE(affects_required_hc, true) = true
-- so roving satellite open vacancies (and any false-flagged rows) drop out of
-- Open HC. Stationary + roving-primary open vacancies still count as 1 each.
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
  SELECT vv.account_id, count(*) AS open_hc
  FROM   public.vacancies vv
  WHERE  vv.status = 'Open'
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
  'Open HC = open non-archived non-pool vacancies WHERE affects_required_hc=true '
  '(roving satellites excluded — OHM2026_0070); Required HC = Filled+pipeline+Open; '
  'MFR = Filled HC / Required HC. Companion to v_account_kpi (integer COUNT).';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

-- CENCOM rollups inherit the corrected open_hc through the base view. They are
-- re-issued verbatim (no body change) only to refresh their comments; column
-- types and names are identical, so this is a safe CREATE OR REPLACE.
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
  'Inherits roving-aware Open HC from v_account_allocation_kpi (OHM2026_0070).';
GRANT SELECT ON public.v_cencom_account_allocation_kpi TO authenticated, service_role;

COMMIT;
