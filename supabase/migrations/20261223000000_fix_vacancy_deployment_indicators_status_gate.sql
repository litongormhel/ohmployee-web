-- Migration: 20261223000000_fix_vacancy_deployment_indicators_status_gate.sql
-- Ticket: ohm#rci003 — Fix False R Indicator on Pipeline Applicant Without Active Coverage
-- Ticket: ohm#rci004 — Fix workforce_assignments.vacancy_id does not exist
--
-- Redefines public.v_vacancy_deployment_indicators to filter only active/approved vacancy coverages
-- (matching the status constraints of the detail tab) and to link workforce assignments to store footprints
-- (as workforce_assignments does not have a vacancy_id column).

CREATE OR REPLACE VIEW public.v_vacancy_deployment_indicators AS
SELECT
  v.id AS vacancy_id,
  COALESCE(bool_or(
    (vc.id IS NOT NULL AND lower(vc.coverage_type::text) NOT LIKE '%commando%')
    OR (wa.id IS NOT NULL AND NOT (lower(coalesce(wa.deployment_type, '')) LIKE '%commando%' OR lower(coalesce(wpt.name, '')) LIKE '%commando%' OR lower(coalesce(wpt.code, '')) LIKE '%commando%'))
  ), false) AS has_reliever,
  COALESCE(bool_or(
    (vc.id IS NOT NULL AND lower(vc.coverage_type::text) LIKE '%commando%')
    OR (wa.id IS NOT NULL AND (lower(coalesce(wa.deployment_type, '')) LIKE '%commando%' OR lower(coalesce(wpt.name, '')) LIKE '%commando%' OR lower(coalesce(wpt.code, '')) LIKE '%commando%'))
  ), false) AS has_commando
FROM public.vacancies v
LEFT JOIN public.vacancy_coverage vc 
  ON (
    (vc.vacancy_id IS NOT NULL AND vc.vacancy_id = v.id)
    OR
    (vc.vacancy_id IS NULL AND vc.vcode = v.vcode)
  ) 
  AND vc.archived_at IS NULL
  AND vc.status = 'Active'::public.vacancy_coverage_status
LEFT JOIN public.workforce_assignments wa 
  ON wa.assigned_store_id = v.store_id 
  AND wa.status = ANY (ARRAY['Approved', 'Deployed', 'Active', 'In Progress'])
LEFT JOIN public.workforce_pool_types wpt 
  ON wpt.id = wa.pool_type_id
WHERE
  (
    public.i_have_full_access()
    OR (
      v.account = ANY (public.get_my_allowed_accounts())
      AND (v.status <> ALL (ARRAY['Filled'::text, 'Closed'::text, 'Archived'::text]))
      AND (COALESCE(v.is_archived, false) = false)
      AND (
        NOT COALESCE(v.is_pool_vacancy, false)
        OR COALESCE(v.is_ops_request, false) = true
      )
    )
    OR (
      COALESCE(v.is_pool_vacancy, false) = true
      AND (
        public.get_my_role_level() = 20
        OR public.get_my_role_level() = 30
        OR public.get_my_role_level() >= 90
      )
    )
  )
GROUP BY v.id;

GRANT SELECT ON public.v_vacancy_deployment_indicators TO authenticated;
