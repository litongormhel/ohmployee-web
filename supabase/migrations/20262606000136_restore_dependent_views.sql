-- ============================================================================
-- Migration: 20262606000136_restore_dependent_views.sql
-- Description: Restores vw_plantilla_inactive and v_dashboard_* views that were
--              cascaded when v_plantilla_safe was refreshed.
-- ============================================================================

CREATE OR REPLACE VIEW public.vw_plantilla_inactive
WITH (security_invoker = true) AS
SELECT vps.*
FROM public.v_plantilla_safe vps
WHERE vps.status <> 'Active'
  AND vps.source_headcount_request_id IS NULL
ORDER BY vps.date_of_separation DESC NULLS LAST,
         vps.employee_name ASC;

GRANT SELECT ON public.vw_plantilla_inactive TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_account_breakdown
  WITH (security_invoker = true)
AS
SELECT
  account,
  COUNT(*) FILTER (WHERE status = 'Active')   AS active,
  COUNT(*) FILTER (WHERE status = 'Resigned') AS resigned
FROM public.v_plantilla_safe
GROUP BY account
HAVING COUNT(*) FILTER (WHERE status IN ('Active', 'Resigned')) > 0
ORDER BY active DESC;

GRANT SELECT ON public.v_dashboard_account_breakdown TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_account_mfr_breakdown
  WITH (security_invoker = true)
AS
 WITH active_agg AS (
         SELECT v_plantilla_safe.account,
            count(*) AS active
           FROM v_plantilla_safe
          WHERE v_plantilla_safe.status = 'Active'::text AND v_plantilla_safe.account IS NOT NULL AND TRIM(BOTH FROM v_plantilla_safe.account) <> ''::text
          GROUP BY v_plantilla_safe.account
        ), pipeline_agg AS (
         SELECT hr_emploc.account,
            count(*) AS pipeline
           FROM hr_emploc
          WHERE (hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])) AND hr_emploc.deleted_at IS NULL AND hr_emploc.account IS NOT NULL AND TRIM(BOTH FROM hr_emploc.account) <> ''::text
          GROUP BY hr_emploc.account
        ), vac_agg AS (
         SELECT vw_slot_derived_vacancy_shadow.account_name AS account,
            count(*) AS vacancies
           FROM vw_slot_derived_vacancy_shadow
          WHERE (vw_slot_derived_vacancy_shadow.open_count - vw_slot_derived_vacancy_shadow.pipeline_count - vw_slot_derived_vacancy_shadow.hr_processing_count) > 0 AND vw_slot_derived_vacancy_shadow.account_name IS NOT NULL AND TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.account_name) <> ''::text
          GROUP BY vw_slot_derived_vacancy_shadow.account_name
        ), all_accounts AS (
         SELECT active_agg.account
           FROM active_agg
        UNION
         SELECT pipeline_agg.account
           FROM pipeline_agg
        UNION
         SELECT vac_agg.account
           FROM vac_agg
        )
 SELECT aa.account,
    COALESCE(a.active, 0::bigint) AS active,
    COALESCE(p.pipeline, 0::bigint) AS pipeline,
    COALESCE(v.vacancies, 0::bigint) AS vacancies,
    COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint) AS required,
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint))::numeric
            ELSE 1.0
        END AS mfr
   FROM all_accounts aa
     LEFT JOIN active_agg a ON a.account = aa.account
     LEFT JOIN pipeline_agg p ON p.account = aa.account
     LEFT JOIN vac_agg v ON v.account = aa.account
  ORDER BY (
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacancies, 0::bigint))::numeric
            ELSE 1.0
        END), aa.account;

GRANT SELECT ON public.v_dashboard_account_mfr_breakdown TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_dashboard_hrco_breakdown
  WITH (security_invoker = true)
AS
 WITH active_agg AS (
         SELECT v_plantilla_safe.hrco_name AS hrco,
            count(*) AS active
           FROM v_plantilla_safe
          WHERE v_plantilla_safe.status = 'Active'::text AND v_plantilla_safe.hrco_name IS NOT NULL AND TRIM(BOTH FROM v_plantilla_safe.hrco_name) <> ''::text
          GROUP BY v_plantilla_safe.hrco_name
        ), pipeline_agg AS (
         SELECT hr_emploc.hrco_name AS hrco,
            count(*) AS pipeline
           FROM hr_emploc
          WHERE (hr_emploc.hr_status = ANY (ARRAY['Pending'::text, 'For Emploc'::text, 'Complete'::text])) AND hr_emploc.deleted_at IS NULL AND hr_emploc.hrco_name IS NOT NULL AND TRIM(BOTH FROM hr_emploc.hrco_name) <> ''::text
          GROUP BY hr_emploc.hrco_name
        ), vac_agg AS (
         SELECT COALESCE(NULLIF(TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.hrco_name), ''::text), 'Unassigned'::text) AS hrco,
            count(*) AS vacant
           FROM vw_slot_derived_vacancy_shadow
          WHERE (vw_slot_derived_vacancy_shadow.open_count - vw_slot_derived_vacancy_shadow.pipeline_count - vw_slot_derived_vacancy_shadow.hr_processing_count) > 0
          GROUP BY (COALESCE(NULLIF(TRIM(BOTH FROM vw_slot_derived_vacancy_shadow.hrco_name), ''::text), 'Unassigned'::text))
        ), all_hrco AS (
         SELECT active_agg.hrco
           FROM active_agg
        UNION
         SELECT pipeline_agg.hrco
           FROM pipeline_agg
        UNION
         SELECT vac_agg.hrco
           FROM vac_agg
        )
 SELECT ah.hrco,
    COALESCE(v.vacant, 0::bigint) AS vacant,
    COALESCE(a.active, 0::bigint) AS active,
    COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint) AS required,
        CASE
            WHEN (COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint)) > 0 THEN (COALESCE(a.active, 0::bigint) + COALESCE(p.pipeline, 0::bigint))::numeric / (COALESCE(a.active, 0::bigint) + COALESCE(v.vacant, 0::bigint))::numeric
            ELSE 1.0
        END AS mfr
   FROM all_hrco ah
     LEFT JOIN active_agg a ON a.hrco = ah.hrco
     LEFT JOIN pipeline_agg p ON p.hrco = ah.hrco
     LEFT JOIN vac_agg v ON v.hrco = ah.hrco
  ORDER BY (
        CASE
            WHEN ah.hrco = 'Unassigned'::text THEN 1
            ELSE 0
        END), ah.hrco;

GRANT SELECT ON public.v_dashboard_hrco_breakdown TO authenticated, service_role;
