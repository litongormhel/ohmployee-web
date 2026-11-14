-- ============================================================================
-- Migration: 20260820100000_add_vw_slot_derived_vacancy_cg_covered_shadow.sql
-- Prompt:    ohm#4w9k2tpv (follow-up) — CG-covered open vacancies invisible
--            everywhere in the app (VCTG2_0004/VCTG2_0005, account THREE)
-- Date:      2026-08-20
--
-- Purpose:
--   vw_slot_derived_vacancy_shadow deliberately excludes stationary slots for
--   stores that belong to an active Coverage Group (NOT EXISTS coverage_group
--   footprint check, see 20260702000003_fix_coverage_group_vacancy_duplication_
--   second_level.sql). That exclusion is confirmed intentional for the Vacancy
--   module's Open/Pipeline tabs and is NOT touched by this migration.
--
--   Investigation (ohm#4w9k2tpv) found the same suppressed view is also the
--   sole source for Plantilla's Vacancy Tab (fetchVacanciesForAccount) and
--   CENCOM — so a CG-covered legacy vacancy such as VCTG2_0004/VCTG2_0005
--   currently has NO visibility anywhere in the app, not even as an
--   informational badge.
--
--   This migration adds a new, purely additive, read-only view —
--   vw_slot_derived_vacancy_cg_covered_shadow — that surfaces exactly the
--   complement population vw_slot_derived_vacancy_shadow excludes: stationary
--   slots whose store belongs to an active Coverage Group. Same CTEs/joins/
--   derivation as the original view (hc_needed, hired_count, open_count,
--   vacancy_tab classification all computed identically, per ADR-001 Rules
--   2/4), plus coverage_group_id/cg_code so the Flutter badge can say which
--   CG absorbed the store.
--
--   Not touched: vw_slot_derived_vacancy_shadow (verbatim, unchanged), any
--   table, any RLS policy, any RPC. This is a single CREATE VIEW statement.
-- ============================================================================

CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_cg_covered_shadow
WITH (security_invoker = true) AS
 WITH aging_basis AS (
         SELECT DISTINCT ON (sh.slot_id) sh.slot_id,
            sh.created_at AS open_episode_start
           FROM slot_history sh
          WHERE sh.new_value = 'open'::text
          ORDER BY sh.slot_id, sh.created_at DESC
        ), pending_closure AS (
         SELECT DISTINCT vcr.vacancy_vcode
           FROM vacancy_closure_requests vcr
             JOIN vacancies v_1 ON v_1.vcode = vcr.vacancy_vcode AND v_1.deleted_at IS NULL AND COALESCE(v_1.is_archived, false) = false
          WHERE vcr.status = 'Pending'::text
        ), applicant_counts AS (
         SELECT a_1.vacancy_vcode,
            count(DISTINCT a_1.id) FILTER (WHERE COALESCE(a_1.is_archived, false) = false AND fn_is_active_vacancy_applicant_status(a_1.status)) AS pipeline_count
           FROM applicants a_1
          WHERE a_1.vacancy_vcode IS NOT NULL
          GROUP BY a_1.vacancy_vcode
        ), plantilla_counts AS (
         SELECT p.vcode,
            count(DISTINCT p.id) FILTER (WHERE COALESCE(p.is_deleted, false) = false AND p.status = 'Active'::text) AS active_emp_count
           FROM plantilla p
          WHERE p.vcode IS NOT NULL
          GROUP BY p.vcode
        ), req_counts AS (
         SELECT vr.vacancy_id,
            sum(vr.hc_needed) AS req_hc_needed
           FROM vacancy_requirements vr
          GROUP BY vr.vacancy_id
        )
 SELECT ps.legacy_vcode,
    ps.legacy_vcode AS vacancy_id,
    v.id AS legacy_vacancy_id,
    v.store_name,
    v.area_city,
    v.province,
    v.area_name,
    v.required_headcount,
    (array_agg(ps.store_id ORDER BY ps.created_at, (ps.id::text)))[1] AS store_id,
    min(st.store_branch) AS store_branch,
    (array_agg(ps.account_id ORDER BY ps.created_at, (ps.id::text)))[1] AS account_id,
    min(a.account_name) AS account_name,
    (array_agg(ps.group_id ORDER BY ps.created_at, (ps.id::text)))[1] AS group_id,
    min(g.group_name) AS group_name,
    min(ps."position") AS "position",
    min(ps.employment_type) AS employment_type,
    false AS is_roving,
    count(*) AS required_hc,
    COALESCE(rc.req_hc_needed, count(*)) AS hc_needed,
    COALESCE(max(plc.active_emp_count), 0::bigint) AS hired_count,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM plantilla_slots ps_closed
              WHERE ps_closed.legacy_vcode = ps.legacy_vcode AND ps_closed.slot_status = 'closed'::text)) THEN 0::bigint
            ELSE GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint))
        END AS open_count,
    count(*) FILTER (WHERE ps.slot_status = 'hr_processing'::text) AS hr_processing_count,
    count(*) FILTER (WHERE ps.slot_status = 'occupied'::text) AS occupied_count,
    count(*) FILTER (WHERE ps.slot_status = 'closed'::text) AS closed_count,
    COALESCE(max(ac.pipeline_count), 0::bigint) AS active_applicant_count,
    bool_or(pc.vacancy_vcode IS NOT NULL) AS has_pending_closure,
        CASE
            WHEN bool_or(pc.vacancy_vcode IS NOT NULL) OR (EXISTS ( SELECT 1
               FROM plantilla_slots ps_closed
              WHERE ps_closed.legacy_vcode = ps.legacy_vcode AND ps_closed.slot_status = 'closed'::text)) THEN 'Closure'::text
            WHEN COALESCE(max(ac.pipeline_count), 0::bigint) > 0 THEN 'Pipeline'::text
            WHEN GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint)) > 0 THEN 'Open'::text
            WHEN COALESCE(max(plc.active_emp_count), 0::bigint) >= COALESCE(rc.req_hc_needed, count(*)) THEN 'Hired'::text
            ELSE 'Open'::text
        END AS vacancy_tab,
    min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text) AS aging_start_at,
        CASE
            WHEN GREATEST(0::bigint, COALESCE(rc.req_hc_needed, count(*)) - COALESCE(max(plc.active_emp_count), 0::bigint)) = 0 THEN NULL::integer
            WHEN min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text)::date > CURRENT_DATE THEN NULL::integer
            ELSE CURRENT_DATE - min(COALESCE(ab.open_episode_start, ps.created_at)) FILTER (WHERE ps.slot_status = 'open'::text)::date
        END AS aging_days,
    min(ps.created_at) AS created_at,
    max(ps.updated_at) AS updated_at,
    max(ps.closed_at) AS closed_at,
    (array_agg(ps.source_hc_request_id ORDER BY ps.created_at, (ps.id::text)))[1] AS source_hc_request_id,
    v.urgency_level,
    v.hrco_name,
    v.hrco_user_id,
    v.target_fill_date,
    v.triggered_by_user_id,
    v.triggered_by_name,
    cg.id AS coverage_group_id,
    cg.coverage_code AS cg_code
   FROM plantilla_slots ps
     LEFT JOIN aging_basis ab ON ab.slot_id = ps.id
     LEFT JOIN stores st ON st.id = ps.store_id
     LEFT JOIN accounts a ON a.id = ps.account_id
     LEFT JOIN groups g ON g.id = ps.group_id
     LEFT JOIN pending_closure pc ON pc.vacancy_vcode = ps.legacy_vcode
     LEFT JOIN applicant_counts ac ON ac.vacancy_vcode = ps.legacy_vcode
     LEFT JOIN plantilla_counts plc ON plc.vcode = ps.legacy_vcode
     JOIN vacancies v ON v.vcode = ps.legacy_vcode AND v.deleted_at IS NULL AND COALESCE(v.is_archived, false) = false AND v.status <> 'Archived'::text
     LEFT JOIN req_counts rc ON rc.vacancy_id = v.id
     JOIN coverage_group_stores cgs ON cgs.store_id = ps.store_id AND cgs.archived_at IS NULL
     JOIN coverage_groups cg ON cg.id = cgs.coverage_group_id AND cg.archived_at IS NULL
  WHERE ps.legacy_vcode IS NOT NULL AND ps.is_roving = false
  GROUP BY ps.legacy_vcode, v.id, rc.req_hc_needed, cg.id, cg.coverage_code;

COMMENT ON VIEW public.vw_slot_derived_vacancy_cg_covered_shadow IS
  'ohm#4w9k2tpv: complement of vw_slot_derived_vacancy_shadow — surfaces '
  'stationary legacy-VCode slots whose store belongs to an active Coverage '
  'Group (the population the main shadow view intentionally excludes), so '
  'Plantilla''s Vacancy Tab can show a read-only "Covered by Coverage Group" '
  'informational section. Never feeds open_count/pipeline_count/hc math '
  'anywhere — display only.';

GRANT SELECT ON public.vw_slot_derived_vacancy_cg_covered_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_cg_covered_shadow TO service_role;
