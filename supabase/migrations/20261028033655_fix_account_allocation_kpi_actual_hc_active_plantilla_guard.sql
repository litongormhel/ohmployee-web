-- Migration: 20261028033655_fix_account_allocation_kpi_actual_hc_active_plantilla_guard.sql
-- Description: Guard filled CTE in v_account_allocation_kpi by joining active plantilla records to prevent inactive parent allocations from leaking into actual_hc

CREATE OR REPLACE VIEW public.v_account_allocation_kpi
WITH (security_invoker = true) AS
 WITH filled AS (
         SELECT a.account_id,
            round(COALESCE(sum(a.filled_hc), 0::numeric), 4) AS filled_hc,
            count(DISTINCT a.employee_no) AS actual_hc
           FROM employee_store_allocations a
           JOIN plantilla p ON p.id = a.plantilla_id
          WHERE a.is_active
            AND p.status IN ('Active', 'For Deactivation', 'On Leave')
            AND NOT p.is_deleted
            AND NOT p.is_archived
          GROUP BY a.account_id
        ), pipeline AS (
         SELECT he.account_id,
            count(*) AS pipeline_count
           FROM hr_emploc he
             LEFT JOIN vacancies v ON v.id = he.vacancy_id
          WHERE (he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])) AND he.deleted_at IS NULL AND he.coverage_slot_id IS NULL AND COALESCE(v.is_pool_vacancy, false) = false
          GROUP BY he.account_id
        ), coverage_slot_kpi AS (
         SELECT cg.account_id,
            count(*) FILTER (WHERE cs.slot_status = 'active'::text)::numeric AS filled_hc,
                CASE
                    WHEN count(DISTINCT cs.current_occupant_plantilla_id) FILTER (WHERE cs.slot_status = 'active'::text AND cs.current_occupant_plantilla_id IS NOT NULL) > 0 THEN count(DISTINCT cs.current_occupant_plantilla_id) FILTER (WHERE cs.slot_status = 'active'::text AND cs.current_occupant_plantilla_id IS NOT NULL)
                    ELSE count(*) FILTER (WHERE cs.slot_status = 'active'::text)
                END AS actual_hc,
            count(*) FILTER (WHERE cs.slot_status = ANY (ARRAY['pipeline'::text, 'hr_processing'::text])) AS pipeline_count,
            count(*) FILTER (WHERE cs.slot_status = 'open'::text)::numeric AS slot_vacant_hc
           FROM coverage_slots cs
             JOIN coverage_groups cg ON cg.id = cs.coverage_group_id
          WHERE cg.archived_at IS NULL
          GROUP BY cg.account_id
        ), slot_vacant_non_roving AS (
         SELECT ps.account_id,
            count(*) FILTER (WHERE (ps.slot_status = ANY (ARRAY['open'::text, 'pipeline'::text])) AND ps.closed_at IS NULL) AS vacant_slots
           FROM plantilla_slots ps
             JOIN vacancies v ON v.vcode = ps.legacy_vcode AND v.deleted_at IS NULL AND COALESCE(v.is_archived, false) = false AND COALESCE(v.is_pool_vacancy, false) = false
          WHERE ps.is_roving = false AND ps.closed_at IS NULL AND ps.legacy_vcode IS NOT NULL AND ps.account_id IS NOT NULL AND NOT (EXISTS ( SELECT 1
                   FROM coverage_group_stores cgs
                     JOIN coverage_groups cg ON cg.id = cgs.coverage_group_id
                  WHERE cgs.store_id = ps.store_id AND cgs.archived_at IS NULL AND cg.archived_at IS NULL))
          GROUP BY ps.account_id
        ), slot_vacant_roving AS (
         SELECT ps.account_id,
            sum(
                CASE
                    WHEN (ps.slot_status = ANY (ARRAY['open'::text, 'pipeline'::text])) AND ps.closed_at IS NULL THEN 1.0 / NULLIF(grp.total_slots::numeric, 0::numeric)
                    ELSE 0.0
                END) AS vacant_hc
           FROM plantilla_slots ps
             JOIN ( SELECT plantilla_slots.source_hc_request_id,
                    count(*) AS total_slots
                   FROM plantilla_slots
                  WHERE plantilla_slots.is_roving = true AND plantilla_slots.closed_at IS NULL AND plantilla_slots.source_hc_request_id IS NOT NULL
                  GROUP BY plantilla_slots.source_hc_request_id) grp ON grp.source_hc_request_id = ps.source_hc_request_id
          WHERE ps.is_roving = true AND ps.closed_at IS NULL AND ps.source_hc_request_id IS NOT NULL AND ps.account_id IS NOT NULL
          GROUP BY ps.account_id
        ), vacant AS (
         SELECT vv.account_id,
            count(*) AS open_hc
           FROM vacancies vv
          WHERE vv.status = 'Open'::text AND vv.deleted_at IS NULL AND COALESCE(vv.is_archived, false) = false AND COALESCE(vv.is_pool_vacancy, false) = false AND COALESCE(vv.affects_required_hc, true) = true
          GROUP BY vv.account_id
        ), base AS (
         SELECT a.id AS account_id,
            a.account_name,
            a.account_code,
            a.group_id,
            g.group_name,
            g.group_code,
            round(COALESCE(f.filled_hc, 0::numeric) + COALESCE(csk.filled_hc, 0::numeric), 4)::numeric(12,4) AS filled_hc,
            COALESCE(f.actual_hc, 0::bigint) + COALESCE(csk.actual_hc, 0::bigint) AS actual_hc,
            COALESCE(p.pipeline_count, 0::bigint) + COALESCE(csk.pipeline_count, 0::bigint) AS pipeline_count,
            COALESCE(v.open_hc, 0::bigint) AS open_hc,
            round(COALESCE(svn.vacant_slots, 0::bigint)::numeric + COALESCE(svr.vacant_hc, 0::numeric) + COALESCE(csk.slot_vacant_hc, 0::numeric), 4)::numeric(12,4) AS slot_vacant_hc,
            round(COALESCE(f.filled_hc, 0::numeric) + COALESCE(csk.filled_hc, 0::numeric) + COALESCE(p.pipeline_count, 0::bigint)::numeric + COALESCE(csk.pipeline_count, 0::bigint)::numeric + COALESCE(svn.vacant_slots, 0::bigint)::numeric + COALESCE(svr.vacant_hc, 0::numeric) + COALESCE(csk.slot_vacant_hc, 0::numeric), 4)::numeric(12,4) AS required_hc
           FROM accounts a
             LEFT JOIN groups g ON g.id = a.group_id
             LEFT JOIN filled f ON f.account_id = a.id
             LEFT JOIN pipeline p ON p.account_id = a.id
             LEFT JOIN coverage_slot_kpi csk ON csk.account_id = a.id
             LEFT JOIN vacant v ON v.account_id = a.id
             LEFT JOIN slot_vacant_non_roving svn ON svn.account_id = a.id
             LEFT JOIN slot_vacant_roving svr ON svr.account_id = a.id
          WHERE a.is_active = true AND COALESCE(a.is_pool_account, false) = false AND (i_have_full_access() OR (a.id = ANY (get_my_allowed_account_ids())))
        )
 SELECT account_id,
    account_name,
    account_code,
    group_id,
    group_name,
    group_code,
    filled_hc,
    actual_hc,
    pipeline_count,
    open_hc,
    required_hc,
        CASE
            WHEN required_hc = 0::numeric THEN 0.0
            ELSE round(filled_hc / required_hc, 4)
        END AS mfr,
        CASE
            WHEN required_hc = 0::numeric THEN 0.0
            ELSE round((filled_hc + pipeline_count::numeric) / required_hc, 4)
        END AS projected_mfr,
        CASE
            WHEN required_hc = 0::numeric THEN 0.0
            ELSE round(slot_vacant_hc / required_hc, 4)
        END AS vacancy_rate,
        CASE
            WHEN required_hc = 0::numeric THEN 0.0
            ELSE round(pipeline_count::numeric / required_hc, 4)
        END AS pipeline_coverage,
        CASE
            WHEN required_hc = 0::numeric THEN 'healthy'::text
            WHEN (filled_hc / required_hc) >= 1.0 THEN 'healthy'::text
            WHEN (filled_hc / required_hc) >= 0.9 THEN 'at_risk'::text
            ELSE 'critical'::text
        END AS health_status,
    slot_vacant_hc
   FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;
