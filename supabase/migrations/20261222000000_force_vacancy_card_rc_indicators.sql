-- Migration: 20261222000000_force_vacancy_card_rc_indicators.sql
-- Ticket: ohm#rci002 — Force Vacancy Card R/C Indicator From Scoped Coverage Data
--
-- Creates a secure, scoped security barrier view (runs with owner privileges)
-- that returns the has_reliever and has_commando status for active/approved coverages,
-- filtered only to the vacancies that the calling user is scoped to see.

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
  ON (vc.vacancy_id = v.id OR vc.vcode = v.vcode) AND vc.archived_at IS NULL
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
