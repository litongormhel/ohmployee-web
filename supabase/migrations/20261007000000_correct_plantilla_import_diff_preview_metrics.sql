-- ============================================================
-- OHM2026_0067 - Correct Plantilla Import Diff Preview Metrics
-- Migration: 20261007000000_correct_plantilla_import_diff_preview_metrics.sql
-- ============================================================
-- Purpose:
--   Refines Plantilla Baseline Import validation metrics:
--   1. Calculates Employees Create/Update based on distinct employee_key.
--   2. Normalizes employee_key as emploc + normalized first name + normalized last name.
--   3. Calculates distinct roving employees.
--   4. Adds stationary_employees metric for employees not roving.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_plantilla_import_diff_preview(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_batch public.plantilla_import_batches%ROWTYPE;
  v_rows jsonb;
  v_summary jsonb;
BEGIN
  SELECT * INTO v_batch
    FROM public.plantilla_import_batches
   WHERE id = p_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (public.i_have_full_access() OR v_batch.uploaded_by = auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  WITH diff_base AS (
    SELECT
      r.id,
      r.row_number,
      r.validation_status,
      r.vcode,
      r.store_name,
      r.employee_no,
      NULLIF(trim(concat_ws(' ', r.last_name, r.first_name, r.middle_name)), '') AS employee_name,
      r.position,
      r.employment_type,
      r.required_hc_raw,
      r.with_penalty_raw,
      r.is_roving,
      r.validation_errors,
      r.validation_flags,
      st.id AS current_store_id,
      st.store_name AS current_store_name,
      st.area_province AS current_store_area_province,
      st.area_city AS current_store_area_city,
      st.employment_type AS current_store_employment_type,
      st.with_penalty AS current_store_with_penalty,
      p.id AS current_plantilla_id,
      p.employee_name AS current_employee_name,
      p.status AS current_employee_status,
      p.account AS current_employee_account,
      p.position AS current_employee_position,
      p.deployment_type AS current_employee_deployment_type,
      p.store_name AS current_employee_store_name,
      p.vcode AS current_employee_vcode,
      a.id AS current_allocation_id,
      a.store_id AS current_allocation_store_id,
      a.vcode AS current_allocation_vcode,
      a.store_name AS current_allocation_store_name,
      a.filled_hc AS current_allocation_filled_hc,
      a.active_store_count AS current_allocation_active_store_count,
      EXISTS (
        SELECT 1
          FROM public.employee_store_allocations aa
         WHERE aa.employee_no = r.employee_no
           AND aa.account_id = v_batch.selected_account_id
           AND aa.is_active
      ) AS has_active_account_allocation,
      EXISTS (
        SELECT 1
          FROM public.employee_store_allocations aa
         WHERE aa.employee_no = r.employee_no
           AND upper(aa.vcode) = upper(r.vcode)
           AND aa.account_id = v_batch.selected_account_id
           AND aa.is_active
      ) AS has_same_active_allocation,
      COALESCE(trim(r.employee_no), '') ||
      regexp_replace(upper(trim(COALESCE(r.first_name, ''))), '\s+', ' ', 'g') ||
      regexp_replace(upper(trim(COALESCE(r.last_name, ''))), '\s+', ' ', 'g') AS employee_key
    FROM public.plantilla_import_rows r
    LEFT JOIN public.stores st
      ON upper(st.vcode) = upper(r.vcode)
     AND st.status = 'active'
    LEFT JOIN LATERAL (
      SELECT p1.*
        FROM public.plantilla p1
       WHERE p1.employee_no = r.employee_no
         AND p1.status IN ('Active','For Deactivation','On Leave','Pending Deactivation')
       ORDER BY p1.created_at DESC
       LIMIT 1
    ) p ON true
    LEFT JOIN LATERAL (
      SELECT a1.*
        FROM public.employee_store_allocations a1
       WHERE a1.employee_no = r.employee_no
         AND a1.account_id = v_batch.selected_account_id
         AND a1.is_active
       ORDER BY
         CASE WHEN upper(a1.vcode) = upper(r.vcode) THEN 0 ELSE 1 END,
         a1.created_at DESC
       LIMIT 1
    ) a ON true
    WHERE r.batch_id = p_batch_id
  ),
  categorized AS (
    SELECT
      d.*,
      ARRAY_REMOVE(ARRAY[
        CASE WHEN d.validation_status <> 'blocked'
               AND d.current_store_id IS NULL
             THEN 'store_create' END,
        CASE WHEN d.validation_status <> 'blocked'
               AND d.current_store_id IS NOT NULL
             THEN 'store_update' END,
        CASE WHEN d.validation_status IN ('valid','flagged')
               AND d.current_plantilla_id IS NULL
             THEN 'employee_create' END,
        CASE WHEN d.validation_status IN ('valid','flagged')
               AND d.current_plantilla_id IS NOT NULL
             THEN 'employee_update' END,
        CASE WHEN d.validation_status IN ('valid','flagged')
               AND NOT d.has_same_active_allocation
             THEN 'allocation_create' END,
        CASE WHEN d.validation_status IN ('valid','flagged')
               AND d.has_active_account_allocation
             THEN 'allocation_replace' END,
        CASE WHEN d.is_roving THEN 'roving' END,
        CASE WHEN d.validation_status = 'blocked' THEN 'blocked' END,
        CASE WHEN d.validation_status = 'skipped' THEN 'skipped' END,
        CASE WHEN d.validation_status = 'flagged' THEN 'flagged' END
      ], NULL) AS diff_categories
    FROM diff_base d
  )
  SELECT
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'row_number', c.row_number,
        'validation_status', c.validation_status,
        'vcode', c.vcode,
        'store_name', c.store_name,
        'employee_no', c.employee_no,
        'employee_name', c.employee_name,
        'position', c.position,
        'employment_type', c.employment_type,
        'required_hc', c.required_hc_raw,
        'with_penalty', c.with_penalty_raw,
        'diff_categories', to_jsonb(c.diff_categories),
        'current_store_snapshot',
          CASE WHEN c.current_store_id IS NULL THEN NULL ELSE jsonb_strip_nulls(jsonb_build_object(
            'id', c.current_store_id,
            'vcode', c.vcode,
            'store_name', c.current_store_name,
            'area_province', c.current_store_area_province,
            'area_city', c.current_store_area_city,
            'employment_type', c.current_store_employment_type,
            'with_penalty', c.current_store_with_penalty
          )) END,
        'current_employee_snapshot',
          CASE WHEN c.current_plantilla_id IS NULL THEN NULL ELSE jsonb_strip_nulls(jsonb_build_object(
            'id', c.current_plantilla_id,
            'employee_no', c.employee_no,
            'employee_name', c.current_employee_name,
            'status', c.current_employee_status,
            'account', c.current_employee_account,
            'position', c.current_employee_position,
            'deployment_type', c.current_employee_deployment_type,
            'store_name', c.current_employee_store_name,
            'vcode', c.current_employee_vcode
          )) END,
        'current_allocation_snapshot',
          CASE WHEN c.current_allocation_id IS NULL THEN NULL ELSE jsonb_strip_nulls(jsonb_build_object(
            'id', c.current_allocation_id,
            'store_id', c.current_allocation_store_id,
            'vcode', c.current_allocation_vcode,
            'store_name', c.current_allocation_store_name,
            'filled_hc', c.current_allocation_filled_hc,
            'active_store_count', c.current_allocation_active_store_count
          )) END,
        'messages',
          COALESCE(c.validation_errors, '[]'::jsonb)
          || COALESCE(c.validation_flags, '[]'::jsonb)
      )
      ORDER BY c.row_number
    ), '[]'::jsonb),
    jsonb_build_object(
      'stores_to_create', count(*) FILTER (WHERE 'store_create' = ANY(c.diff_categories)),
      'stores_to_update', count(*) FILTER (WHERE 'store_update' = ANY(c.diff_categories)),
      'employees_to_create', count(DISTINCT c.employee_key) FILTER (WHERE 'employee_create' = ANY(c.diff_categories)),
      'employees_to_update', count(DISTINCT c.employee_key) FILTER (WHERE 'employee_update' = ANY(c.diff_categories)),
      'allocations_to_create', count(*) FILTER (WHERE 'allocation_create' = ANY(c.diff_categories)),
      'roving_employees', count(DISTINCT c.employee_key) FILTER (WHERE 'roving' = ANY(c.diff_categories)),
      'stationary_employees', count(DISTINCT c.employee_key) FILTER (WHERE NOT coalesce('roving' = any(c.diff_categories), false)),
      'blocked_rows', count(*) FILTER (WHERE 'blocked' = ANY(c.diff_categories)),
      'skipped_rows', count(*) FILTER (WHERE 'skipped' = ANY(c.diff_categories)),
      'flagged_rows', count(*) FILTER (WHERE 'flagged' = ANY(c.diff_categories))
    )
  INTO v_rows, v_summary
  FROM categorized c;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'summary', COALESCE(v_summary, jsonb_build_object(
      'stores_to_create', 0,
      'stores_to_update', 0,
      'employees_to_create', 0,
      'employees_to_update', 0,
      'allocations_to_create', 0,
      'roving_employees', 0,
      'stationary_employees', 0,
      'blocked_rows', 0,
      'skipped_rows', 0,
      'flagged_rows', 0
    )),
    'rows', COALESCE(v_rows, '[]'::jsonb)
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_diff_preview(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_plantilla_import_diff_preview(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_import_diff_preview(uuid) IS
  'Read-only Import Plantilla approval diff preview. Returns summary counts, row categories, safe current store/employee/allocation snapshots, and validation messages.';
