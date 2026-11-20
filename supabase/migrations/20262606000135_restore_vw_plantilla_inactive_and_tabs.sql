-- ============================================================================
-- Migration: 20262606000135_restore_vw_plantilla_inactive_and_tabs.sql
-- Prompt ID: ohm#p1k8m4vx (Plantilla Inactive View Restoration & Tabs)
-- Date:      2026-11-20
-- Purpose:   (1) Restore public.vw_plantilla_inactive view dropped via CASCADE
--                in migration 20262606000096, enforcing ADR-001 Rule 5 ordering.
--            (2) Add 'on_leave' and 'floating' filters to get_plantilla_employees
--                and refine 'active' and 'inactive' filters to separate On-Leave
--                and Floating employees into their dedicated tabs.
-- ============================================================================

-- 1. Recreate public.vw_plantilla_inactive with security_invoker = true
--    Excludes 'Active', 'On Leave', and 'Floating' (which now have their own tabs).
CREATE OR REPLACE VIEW public.vw_plantilla_inactive
WITH (security_invoker = true) AS
SELECT vps.*
FROM public.v_plantilla_safe vps
WHERE vps.status <> 'Active'
  AND vps.status <> 'On Leave'
  AND COALESCE(vps.separation_status, '') <> 'Floating'
  AND vps.status <> 'Floating'
  AND vps.source_headcount_request_id IS NULL
ORDER BY vps.date_of_separation DESC NULLS LAST,
         vps.employee_name ASC;

COMMENT ON VIEW public.vw_plantilla_inactive IS
  'Plantilla Inactive tab population with ADR-001 audit CASE 4 ordering contract enforced in-DB (date_of_separation DESC NULLS LAST, employee_name ASC). Restored after v_plantilla_safe CASCADE drop.';

GRANT SELECT ON public.vw_plantilla_inactive TO authenticated;
GRANT SELECT ON public.vw_plantilla_inactive TO service_role;

-- 2. Update get_plantilla_employees to support dedicated 'active', 'on_leave',
--    'floating', and 'inactive' filters.
CREATE OR REPLACE FUNCTION public.get_plantilla_employees(p_store_id uuid, p_status_filter text DEFAULT 'all'::text)
 RETURNS TABLE(
   id uuid,
   employee_name text,
   employee_no text,
   emploc_no text,
   vcode text,
   position_name text,
   deployment_type text,
   account text,
   store_name text,
   status text,
   separation_status text,
   inactive_at timestamp with time zone,
   for_deactivation_at timestamp with time zone,
   deactivated_at timestamp with time zone,
   deactivated_visible_until timestamp with time zone,
   sla_status text,
   sla_due_date date,
   can_reassign_store boolean,
   can_resign boolean,
   can_endo boolean,
   can_separate boolean,
   can_request_deactivation boolean,
   can_complete_deactivation boolean,
   can_view_benefits boolean,
   can_sync_mika boolean,
   can_reveal_benefits boolean,
   area_city text,
   area_province text,
   derived_employment_type text,
   assigned_hrco_user_id uuid,
   assigned_hrco_name text,
   assigned_hrco_email text,
   assigned_hrco_date timestamp with time zone
 )
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role          text    := public.get_my_role();
  v_is_ops        boolean := public.i_am_ops();
  v_is_full       boolean := public.i_have_full_access();
  v_is_backoffice boolean := v_role IN ('Back Office', 'Backoffice');
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.employee_name,
    p.employee_no,
    p.emploc_no,
    p.vcode,
    p.position::text,
    p.deployment_type,
    p.account,
    p.store_name,
    p.status,
    p.separation_status,
    p.inactive_at,
    p.for_deactivation_at,
    p.deactivated_at,
    p.deactivated_visible_until,
    -- SLA status
    CASE
      WHEN p.status = 'Inactive' AND p.inactive_at < NOW() - INTERVAL '3 days'
        THEN 'breach_inactive_no_request'
      WHEN p.status = 'For Deactivation' AND p.for_deactivation_at < NOW() - INTERVAL '3 days'
        THEN 'breach_deactivation_overdue'
      WHEN p.status IN ('Inactive', 'For Deactivation') THEN 'within_sla'
      ELSE NULL
    END,
    -- SLA due date
    CASE
      WHEN p.status = 'Inactive'         THEN (p.inactive_at + INTERVAL '3 days')::date
      WHEN p.status = 'For Deactivation' THEN (p.for_deactivation_at + INTERVAL '3 days')::date
      ELSE NULL
    END,
    -- can_reassign_store: Active and On Leave employees
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_resign
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_endo
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_separate
    (v_is_full OR (v_is_ops AND p.status IN ('Active', 'On Leave'))),
    -- can_request_deactivation: Inactive employees
    (v_is_full OR (v_is_ops AND p.status = 'Inactive')),
    -- can_complete_deactivation: Backoffice for For Deactivation
    ((v_is_backoffice OR v_is_full) AND p.status = 'For Deactivation'),
    true,
    (v_is_full OR v_is_ops OR v_is_backoffice),
    (v_is_full OR v_is_ops OR v_is_backoffice),
    s.area_city::text,
    COALESCE(s.area_province, s.province)::text,
    CASE
      WHEN (
        SELECT COUNT(*)
          FROM public.plantilla_store_links psl
         WHERE psl.plantilla_id = p.id
           AND psl.deleted_at IS NULL
           AND psl.status = 'Active'
      ) > 1
      THEN 'Roving'
      ELSE COALESCE(p.deployment_type, 'Stationary')
    END AS derived_employment_type,
    -- Assigned HRCO fields
    pha.hrco_user_id AS assigned_hrco_user_id,
    pha.hrco_name_snapshot AS assigned_hrco_name,
    pha.hrco_email_snapshot AS assigned_hrco_email,
    pha.effective_start AS assigned_hrco_date
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  LEFT JOIN public.plantilla_hrco_assignments pha ON pha.plantilla_id = p.id AND pha.is_active
  WHERE p.store_id = p_store_id
    AND (
      v_is_full
      OR p.account = ANY (public.get_my_allowed_accounts())
    )
    AND (
      CASE LOWER(p_status_filter)
        WHEN 'all'              THEN p.status IN ('Active', 'On Leave', 'Inactive', 'For Deactivation', 'Deactivated')
                                     AND (p.status <> 'Deactivated'
                                          OR p.deactivated_visible_until > NOW())
        WHEN 'active'           THEN p.status = 'Active'
        WHEN 'on_leave'         THEN p.status = 'On Leave'
        WHEN 'on leave'         THEN p.status = 'On Leave'
        WHEN 'floating'         THEN (p.status = 'Floating' OR p.separation_status = 'Floating')
                                     AND p.source_headcount_request_id IS NULL
        WHEN 'inactive'         THEN p.status IN ('Inactive', 'For Deactivation', 'Deactivated')
                                     AND COALESCE(p.separation_status, '') <> 'Floating'
                                     AND p.status <> 'Floating'
                                     AND p.source_headcount_request_id IS NULL
        WHEN 'for_deactivation' THEN p.status = 'For Deactivation'
        WHEN 'deactivated'      THEN p.status = 'Deactivated'
                                     AND p.deactivated_visible_until > NOW()
        ELSE true
      END
    )
  ORDER BY
    CASE p.status
      WHEN 'Active'             THEN 1
      WHEN 'On Leave'           THEN 2
      WHEN 'Inactive'           THEN 3
      WHEN 'For Deactivation'   THEN 4
      WHEN 'Deactivated'        THEN 5
      ELSE 6
    END,
    p.employee_name;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_plantilla_employees(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_plantilla_employees(uuid, text) TO service_role;
