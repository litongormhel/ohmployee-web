-- ============================================================================
-- OHM2026_0074 — Workforce Allocation Health Report RPC
-- ============================================================================
-- Read-only diagnostics for Super Admin / Head Admin visibility.
-- No allocation sync, MFR formula, import, or vacancy workflow mutation.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_workforce_allocation_health_report()
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED'
      USING ERRCODE = '42501',
            MESSAGE = 'Only Super Admin and Head Admin can view allocation health.';
  END IF;

  WITH
  active_allocations AS (
    SELECT *
    FROM public.employee_store_allocations
    WHERE is_active
  ),
  roving_employees AS (
    SELECT
      employee_no,
      count(*) AS active_allocations,
      round(sum(filled_hc), 4) AS total_hc
    FROM active_allocations
    GROUP BY employee_no
    HAVING count(*) > 1
  ),
  normalization_issues AS (
    SELECT
      employee_no,
      count(*) AS active_allocations,
      round(sum(filled_hc), 4) AS total_hc
    FROM active_allocations
    GROUP BY employee_no
    HAVING round(sum(filled_hc), 4) <> 1.0000
  ),
  duplicate_active_footprints AS (
    SELECT
      employee_no,
      plantilla_id,
      upper(COALESCE(vcode, '')) AS vcode,
      count(*) AS duplicate_count
    FROM active_allocations
    GROUP BY employee_no, plantilla_id, upper(COALESCE(vcode, ''))
    HAVING count(*) > 1
  ),
  roving_members AS (
    SELECT
      ra.id AS roving_assignment_id,
      COALESCE(
        ra.primary_vcode,
        (
          SELECT min(vcode)
          FROM (
            SELECT vcode
            FROM public.hr_emploc_store_links
            WHERE roving_assignment_id = ra.id
              AND deleted_at IS NULL
            UNION
            SELECT vcode
            FROM public.plantilla_store_links
            WHERE roving_assignment_id = ra.id
              AND deleted_at IS NULL
          ) s
          WHERE vcode IS NOT NULL
        )
      ) AS primary_vcode,
      m.vcode
    FROM public.roving_assignments ra
    JOIN LATERAL (
      SELECT vcode
      FROM public.hr_emploc_store_links
      WHERE roving_assignment_id = ra.id
        AND deleted_at IS NULL
      UNION
      SELECT vcode
      FROM public.plantilla_store_links
      WHERE roving_assignment_id = ra.id
        AND deleted_at IS NULL
      UNION
      SELECT ra.primary_vcode
    ) m ON true
    WHERE ra.archived_at IS NULL
      AND m.vcode IS NOT NULL
  ),
  roving_satellite_hc_issues AS (
    SELECT DISTINCT
      rm.roving_assignment_id,
      vv.vcode,
      vv.account,
      vv.store_name,
      COALESCE(vv.affects_required_hc, true) AS affects_required_hc,
      COALESCE(vv.affects_mfr, true) AS affects_mfr
    FROM roving_members rm
    JOIN public.vacancies vv ON vv.vcode = rm.vcode
    WHERE vv.vcode IS DISTINCT FROM rm.primary_vcode
      AND COALESCE(vv.is_pool_vacancy, false) = false
      AND (
        COALESCE(vv.affects_required_hc, true) = true
        OR COALESCE(vv.affects_mfr, true) = true
      )
  ),
  import_allocation_drift AS (
    SELECT
      COALESCE(imported.employee_no, live.employee_no) AS employee_no,
      COALESCE(imported.plantilla_id, live.plantilla_id) AS plantilla_id,
      upper(COALESCE(imported.vcode, live.vcode, '')) AS vcode,
      imported.source_import_batch_id,
      b.status AS batch_status,
      CASE
        WHEN live.id IS NOT NULL THEN 'live_duplicate_of_import_allocation'
        WHEN imported.is_active = false THEN 'import_allocation_inactive_without_batch_rollback'
        ELSE 'import_allocation_check'
      END AS issue
    FROM public.employee_store_allocations imported
    LEFT JOIN public.plantilla_import_batches b
      ON b.id = imported.source_import_batch_id
    LEFT JOIN public.employee_store_allocations live
      ON live.is_active
     AND live.source_import_batch_id IS NULL
     AND live.employee_no = imported.employee_no
     AND live.plantilla_id = imported.plantilla_id
     AND upper(COALESCE(live.vcode, '')) = upper(COALESCE(imported.vcode, ''))
    WHERE imported.source_import_batch_id IS NOT NULL
      AND (
        live.id IS NOT NULL
        OR (
          imported.is_active = false
          AND COALESCE(b.status, '') NOT IN ('rolled_back', 'rollback_pending')
        )
      )
  ),
  cencom_groups AS (
    SELECT
      group_name,
      group_code,
      filled_hc,
      actual_hc,
      required_hc,
      open_hc,
      mfr,
      health_status
    FROM public.v_cencom_group_allocation_kpi
    ORDER BY group_code NULLS LAST, group_name
  ),
  cencom_accounts AS (
    SELECT
      account_name,
      group_name,
      filled_hc,
      actual_hc,
      required_hc,
      open_hc,
      mfr,
      health_status
    FROM public.v_cencom_account_allocation_kpi
    ORDER BY open_hc DESC, mfr ASC, account_name
    LIMIT 25
  ),
  cencom_aggregate AS (
    SELECT
      filled_hc,
      actual_hc,
      required_hc,
      open_hc,
      mfr,
      health_status
    FROM public.v_cencom_allocation_kpi
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'summary', jsonb_build_object(
      'active_allocations', (SELECT count(*) FROM active_allocations),
      'roving_employees', (SELECT count(*) FROM roving_employees),
      'normalization_issues', (SELECT count(*) FROM normalization_issues),
      'duplicate_active_footprints', (SELECT count(*) FROM duplicate_active_footprints),
      'roving_satellite_hc_issues', (SELECT count(*) FROM roving_satellite_hc_issues),
      'import_allocation_drift', (SELECT count(*) FROM import_allocation_drift)
    ),
    'normalization_issues', COALESCE((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.active_allocations DESC, t.employee_no)
      FROM (SELECT * FROM normalization_issues LIMIT 50) t
    ), '[]'::jsonb),
    'duplicate_active_footprints', COALESCE((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.duplicate_count DESC, t.employee_no)
      FROM (SELECT * FROM duplicate_active_footprints LIMIT 50) t
    ), '[]'::jsonb),
    'roving_satellite_hc_issues', COALESCE((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.account, t.vcode)
      FROM (SELECT * FROM roving_satellite_hc_issues LIMIT 50) t
    ), '[]'::jsonb),
    'import_allocation_drift', COALESCE((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.employee_no, t.vcode)
      FROM (SELECT * FROM import_allocation_drift LIMIT 50) t
    ), '[]'::jsonb),
    'cencom_snapshot', jsonb_build_object(
      'aggregate', COALESCE((SELECT to_jsonb(cencom_aggregate) FROM cencom_aggregate), '{}'::jsonb),
      'groups', COALESCE((SELECT jsonb_agg(to_jsonb(cencom_groups)) FROM cencom_groups), '[]'::jsonb),
      'accounts', COALESCE((SELECT jsonb_agg(to_jsonb(cencom_accounts)) FROM cencom_accounts), '[]'::jsonb)
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_workforce_allocation_health_report() IS
  'OHM2026_0074: read-only Workforce Allocation Health diagnostics for Super Admin / Head Admin. '
  'Summarizes active allocations, roving normalization, duplicate active footprints, roving satellite HC flags, '
  'import allocation drift indicators, and CENCOM allocation KPI snapshot.';

REVOKE ALL ON FUNCTION public.get_workforce_allocation_health_report() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_workforce_allocation_health_report() TO authenticated;

-- Wrapper alias function for public.get_workforce_allocation_health_report
CREATE OR REPLACE FUNCTION public.get_workforce_allocation_health()
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
BEGIN
  RETURN public.get_workforce_allocation_health_report();
END;
$function$;

COMMENT ON FUNCTION public.get_workforce_allocation_health() IS
  'Wrapper alias calling public.get_workforce_allocation_health_report().';

REVOKE ALL ON FUNCTION public.get_workforce_allocation_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_workforce_allocation_health() TO authenticated;

COMMIT;
