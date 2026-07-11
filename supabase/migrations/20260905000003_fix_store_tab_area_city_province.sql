-- Migration: 20260905000003_fix_store_tab_area_city_province.sql
-- Ticket: OHM2026_2046 — Store Tab Area source fix
--
-- Root cause:
--   v_plantilla_safe exposes only 'area' (from plantilla.area), not split
--   city/province. get_plantilla_employees does not join the stores table,
--   so area_city / area_province are absent from the employee payload.
--   Flutter mapping had no 'area' fallback for the city field.
--
-- Fix:
--   1. v_plantilla_safe: LEFT JOIN stores to expose area_city and area_province.
--   2. get_plantilla_employees: LEFT JOIN stores; return area_city and area_province.
--
-- Preserved unchanged:
--   - All existing returned columns in both objects (existing area column kept)
--   - All existing filters, RBAC, ordering, and status logic in the RPC
--   - Security semantics (security_invoker on view, SECURITY DEFINER on RPC)
--   - RPC input signature (parameters unchanged; two columns appended to RETURNS TABLE)
--   - Source tables: no schema changes to plantilla or stores


-- ============================================================================
-- 1. v_plantilla_safe
--    Add LEFT JOIN public.stores to expose area_city and area_province.
--    New columns are appended after existing columns.
--    Existing 'area' column (from plantilla.area) is preserved unchanged.
-- ============================================================================

CREATE OR REPLACE VIEW public.v_plantilla_safe AS
SELECT
  p.id,
  p.employee_name,
  p.employee_no,
  p.account,
  p.account_id,
  p.chain_id,
  p.store_id,
  p.province_id,
  p."position",
  p.position_id,
  p.status,
  p.separation_status,
  p.date_of_separation,
  p.over_headcount,
  p.deactivated_at,
  p.deactivated_visible_until,
  p.deactivation_reason,
  p.deletion_requested_at,
  p.deletion_reason,
  p.sss_no,
  p.philhealth_no,
  p.pagibig_no,
  CASE
    WHEN p.atm_no IS NULL THEN NULL::text
    WHEN length(p.atm_no) <= 4 THEN '****'::text
    ELSE repeat('*', length(p.atm_no) - 4) || right(p.atm_no, 4)
  END AS atm_no_masked,
  p.civil_status,
  p.date_of_birth,
  CASE
    WHEN p.date_of_birth IS NOT NULL
      THEN EXTRACT(year FROM age(p.date_of_birth::timestamptz))::integer
    ELSE NULL::integer
  END AS age,
  CASE
    WHEN p.date_hired IS NOT NULL
      THEN (EXTRACT(epoch FROM age(now(), p.date_hired::timestamptz))
           / (60 * 60 * 24 * 30.4375))::integer
    ELSE NULL::integer
  END AS tenure_months,
  p.last_mika_synced_at,
  p.last_mika_synced_by,
  p.store_name,
  p.area,
  p.rate,
  p.schedule,
  p.deployment_type,
  p.has_penalty,
  p.date_hired,
  p.coordinator,
  p.hrco_name,
  p.vcode,
  p.hr_emploc_id,
  p.roving_assignment_id,
  p.created_at,
  p.updated_at,
  p.source_headcount_request_id,
  -- Computed: roving store count and store-link snapshot
  COALESCE((
    SELECT COUNT(*)
      FROM public.plantilla_store_links psl
     WHERE psl.plantilla_id = p.id
       AND psl.deleted_at IS NULL
       AND psl.status = 'Active'
  ), 0)::integer AS roving_store_count,
  (
    SELECT jsonb_agg(
      jsonb_build_object(
        'vcode',     psl.vcode,
        'store_name',psl.store_name,
        'account',   psl.account,
        'status',    psl.status,
        'linked_at', psl.linked_at
      ) ORDER BY psl.vcode
    )
      FROM public.plantilla_store_links psl
     WHERE psl.plantilla_id = p.id
       AND psl.deleted_at IS NULL
  ) AS roving_stores,
  p.inactive_visible_until,
  -- NEW: split city/province resolved from the linked store record.
  -- These are appended after all existing columns so existing column
  -- ordinal positions remain unchanged for callers using positional access.
  s.area_city                          AS area_city,
  COALESCE(s.area_province, s.province) AS area_province
FROM public.plantilla p
LEFT JOIN public.stores s ON s.id = p.store_id
WHERE
  COALESCE(p.is_deleted, false) = false
  AND (p.is_archived = false)
  AND (p.deactivated_visible_until IS NULL OR p.deactivated_visible_until > NOW())
  AND (p.inactive_visible_until IS NULL OR p.inactive_visible_until > NOW());

COMMENT ON VIEW public.v_plantilla_safe IS
  'Safe read-only view over plantilla. Excludes deleted, archived, expired deactivated-visibility, '
  'and expired inactive-visibility rows. OHM2026_2046: LEFT JOIN stores exposes area_city and '
  'area_province in addition to the existing plantilla.area column.';


-- ============================================================================
-- 2. get_plantilla_employees
--    Add LEFT JOIN public.stores; append area_city and area_province to
--    the RETURNS TABLE. All existing columns, filters, RBAC, ordering, and
--    status logic are preserved unchanged.
-- ============================================================================

-- Drop first: PostgreSQL cannot replace a function when the RETURNS TABLE
-- signature changes (SQLSTATE 42P13). The function is recreated immediately
-- below with the two new columns appended.
DROP FUNCTION IF EXISTS public.get_plantilla_employees(uuid, text);

CREATE OR REPLACE FUNCTION public.get_plantilla_employees(
  p_store_id      uuid,
  p_status_filter text DEFAULT 'all'::text
)
RETURNS TABLE(
  id                        uuid,
  employee_name             text,
  employee_no               text,
  emploc_no                 text,
  vcode                     text,
  position_name             text,
  deployment_type           text,
  account                   text,
  store_name                text,
  status                    text,
  separation_status         text,
  inactive_at               timestamp with time zone,
  for_deactivation_at       timestamp with time zone,
  deactivated_at            timestamp with time zone,
  deactivated_visible_until timestamp with time zone,
  sla_status                text,
  sla_due_date              date,
  can_reassign_store        boolean,
  can_resign                boolean,
  can_endo                  boolean,
  can_separate              boolean,
  can_request_deactivation  boolean,
  can_complete_deactivation boolean,
  can_view_benefits         boolean,
  can_sync_mika             boolean,
  can_reveal_benefits       boolean,
  -- NEW columns appended at end of signature
  area_city                 text,
  area_province             text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
    p."position"::text,
    p.deployment_type,
    p.account,
    p.store_name,
    p.status,
    p.separation_status,
    p.inactive_at,
    p.for_deactivation_at,
    p.deactivated_at,
    p.deactivated_visible_until,
    CASE
      WHEN p.status = 'Inactive' AND p.inactive_at < NOW() - INTERVAL '3 days'
        THEN 'breach_inactive_no_request'
      WHEN p.status = 'For Deactivation' AND p.for_deactivation_at < NOW() - INTERVAL '3 days'
        THEN 'breach_deactivation_overdue'
      WHEN p.status IN ('Inactive', 'For Deactivation') THEN 'within_sla'
      ELSE NULL
    END AS sla_status,
    CASE
      WHEN p.status = 'Inactive'         THEN (p.inactive_at + INTERVAL '3 days')::date
      WHEN p.status = 'For Deactivation' THEN (p.for_deactivation_at + INTERVAL '3 days')::date
      ELSE NULL
    END AS sla_due_date,
    (v_is_full OR (v_is_ops AND p.status = 'Active'))  AS can_reassign_store,
    (v_is_full OR (v_is_ops AND p.status = 'Active'))  AS can_resign,
    (v_is_full OR (v_is_ops AND p.status = 'Active'))  AS can_endo,
    (v_is_full OR (v_is_ops AND p.status = 'Active'))  AS can_separate,
    (v_is_full OR (v_is_ops AND p.status = 'Inactive')) AS can_request_deactivation,
    ((v_is_backoffice OR v_is_full) AND p.status = 'For Deactivation') AS can_complete_deactivation,
    true                                                AS can_view_benefits,
    (v_is_full OR v_is_ops OR v_is_backoffice)         AS can_sync_mika,
    (v_is_full OR v_is_ops OR v_is_backoffice)         AS can_reveal_benefits,
    -- NEW: store-level city/province
    s.area_city::text                                   AS area_city,
    COALESCE(s.area_province, s.province)::text         AS area_province
  FROM public.plantilla p
  LEFT JOIN public.stores s ON s.id = p.store_id
  WHERE p.store_id = p_store_id
    AND (
      v_is_full
      OR p.account = ANY (public.get_my_allowed_accounts())
    )
    AND (
      CASE LOWER(p_status_filter)
        WHEN 'all'              THEN p.status IN ('Active', 'Inactive', 'For Deactivation', 'Deactivated')
                                     AND (p.status <> 'Deactivated'
                                          OR p.deactivated_visible_until > NOW())
        WHEN 'active'           THEN p.status = 'Active'
        -- Exclude vacancy slots: records from create_plantilla_slot_from_request
        -- have source_headcount_request_id set and belong to the Vacancy tab.
        WHEN 'inactive'         THEN p.status = 'Inactive'
                                     AND p.source_headcount_request_id IS NULL
        WHEN 'for_deactivation' THEN p.status = 'For Deactivation'
        WHEN 'deactivated'      THEN p.status = 'Deactivated'
                                     AND p.deactivated_visible_until > NOW()
        ELSE true
      END
    )
  ORDER BY
    CASE p.status
      WHEN 'Active'           THEN 1
      WHEN 'Inactive'         THEN 2
      WHEN 'For Deactivation' THEN 3
      WHEN 'Deactivated'      THEN 4
      ELSE 5
    END,
    p.employee_name;
END$$;

COMMENT ON FUNCTION public.get_plantilla_employees(uuid, text) IS
  'OHM2026_2046: LEFT JOIN stores appends area_city and area_province to the '
  'return payload. All existing filters, RBAC, status logic, and column order preserved.';

REVOKE ALL ON FUNCTION public.get_plantilla_employees(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_plantilla_employees(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_employees(uuid, text) TO authenticated;
