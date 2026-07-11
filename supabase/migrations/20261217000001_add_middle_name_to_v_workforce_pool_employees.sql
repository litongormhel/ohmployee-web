-- =============================================================================
-- Migration: 20261217000001_add_middle_name_to_v_workforce_pool_employees.sql
-- Prompt: ohm#p8z2n6c4
--
-- Adds p.middle_name to v_workforce_pool_employees so the Flutter client can
-- use structured name fields (last_name, first_name, middle_name) for correct
-- "Last, First Middle" display instead of parsing the combined employee_name
-- string which is stored in FIRST MIDDLE LAST order.
-- =============================================================================

DROP VIEW IF EXISTS public.v_workforce_pool_employees;

CREATE VIEW public.v_workforce_pool_employees
WITH (security_invoker = true)
AS
SELECT
  p.id                                              AS employee_id,
  p.employee_no                                     AS employee_number,
  p.employee_name                                   AS full_name,
  p.last_name,
  p.first_name,
  p.middle_name,
  p.account                                         AS home_account,
  p.account_id                                      AS home_account_id,
  p.store_id                                        AS home_store_id,
  wps.id                                            AS pool_slot_id,
  COALESCE(wps.pool_type_id, p.pool_type_id)        AS pool_type_id,
  wpt.code                                          AS pool_type_code,
  wpt.name                                          AS pool_type_name,
  wps.group_id                                      AS tagged_group_id,
  g.group_name                                      AS tagged_group_name,
  COALESCE(agg.active_deployment_count, 0)          AS active_deployment_count,
  COALESCE(agg.active_store_count, 0)               AS active_store_count,
  CASE
    WHEN COALESCE(agg.active_deployment_count, 0) = 0             THEN 'None'
    WHEN agg.active_deployment_count BETWEEN 1  AND 5             THEN 'Low'
    WHEN agg.active_deployment_count BETWEEN 6  AND 10            THEN 'Medium'
    WHEN agg.active_deployment_count BETWEEN 11 AND 20            THEN 'High'
    ELSE 'Critical'
  END                                               AS deployment_load_indicator,
  CASE
    WHEN p.is_deleted = true
      OR p.deactivated_at IS NOT NULL
      OR p.status <> 'Active'                       THEN 'Inactive'
    WHEN pend.pending_request_id IS NOT NULL         THEN 'Reserved'
    WHEN COALESCE(agg.active_deployment_count, 0) > 0 THEN 'Deployed'
    ELSE 'Available'
  END                                               AS availability_status,
  (wps.group_id IS NULL)                            AS is_global_visible,
  (pend.pending_request_id IS NOT NULL)             AS has_pending_request,
  pend.pending_request_id,
  pend.pending_requested_account,
  pend.pending_requested_store,
  p.status                                          AS employee_status,
  p.date_hired,
  p."position",
  p.deployment_type                                 AS home_deployment_type,
  COALESCE(lt.has_longterm, false)                  AS needs_review
FROM public.plantilla p
LEFT JOIN public.workforce_pool_slots wps
       ON wps.vcode = p.vcode
      AND wps.deleted_at IS NULL
      AND wps.is_active = true
JOIN public.workforce_pool_types wpt
  ON wpt.id = COALESCE(wps.pool_type_id, p.pool_type_id)
 AND wpt.is_active = true
LEFT JOIN public.groups g ON g.id = wps.group_id
LEFT JOIN (
  SELECT
    employee_id,
    COUNT(*)                  FILTER (WHERE status IN ('Active','Approved')) AS active_deployment_count,
    COUNT(DISTINCT assigned_store_id)
                              FILTER (WHERE status IN ('Active','Approved')) AS active_store_count
  FROM public.workforce_assignments
  GROUP BY employee_id
) agg ON agg.employee_id = p.id
LEFT JOIN (
  SELECT DISTINCT employee_id, true AS has_longterm
  FROM public.workforce_assignments
  WHERE status IN ('Active','Approved')
    AND start_date <= CURRENT_DATE - INTERVAL '30 days'
) lt ON lt.employee_id = p.id
LEFT JOIN (
  SELECT
    war.employee_id,
    war.id              AS pending_request_id,
    a.account_name      AS pending_requested_account,
    s.store_name        AS pending_requested_store
  FROM public.workforce_assignment_requests war
  LEFT JOIN public.accounts a ON a.id = war.requested_account_id
  LEFT JOIN public.stores   s ON s.id = war.requested_store_id
  WHERE war.status = 'Pending'
) pend ON pend.employee_id = p.id
WHERE p.is_deleted        = false
  AND p.is_pool_employee  = true
  AND p.deactivated_at   IS NULL
  AND (
    public.get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR public.i_have_full_access()
    OR wps.group_id IS NULL
    OR EXISTS (
      SELECT 1
      FROM public.accounts a
      WHERE a.group_id = wps.group_id
        AND a.id::text = ANY (public.get_my_allowed_accounts())
    )
  );
