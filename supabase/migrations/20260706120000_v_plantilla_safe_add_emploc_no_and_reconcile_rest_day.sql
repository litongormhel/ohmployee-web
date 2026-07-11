-- Migration: 20260706120000_v_plantilla_safe_add_emploc_no_and_reconcile_rest_day
-- Created: 2026-07-06
-- Purpose: Expose plantilla.emploc_no on v_plantilla_safe (fixes PostgREST error
--   "column v_plantilla_safe.emploc_no does not exist") and reconcile the
--   undocumented rest_day column already present on PROD so STAGING and PROD
--   share one authoritative view definition.
--
-- Smoke Tests:
-- S1: select emploc_no, rest_day from v_plantilla_safe limit 5; -- no error, columns present
-- S2: select count(*) from v_plantilla_safe where emploc_no is null; -- expected, not an error condition

BEGIN;

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
  s.area_city AS area_city,
  COALESCE(s.area_province, s.province) AS area_province,
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
  p.emploc_no,
  p.rest_day
FROM public.plantilla p
LEFT JOIN public.stores s ON s.id = p.store_id
WHERE
  COALESCE(p.is_deleted, false) = false
  AND (p.is_archived = false)
  AND (p.deactivated_visible_until IS NULL OR p.deactivated_visible_until > NOW())
  AND (p.inactive_visible_until IS NULL OR p.inactive_visible_until > NOW());

COMMENT ON VIEW public.v_plantilla_safe IS
  'Safe read-only view over plantilla. Excludes deleted, archived, expired deactivated-visibility, inactive-visibility rows.';

COMMIT;
