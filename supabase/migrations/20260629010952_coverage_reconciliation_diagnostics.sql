-- Migration: 20260629010952_coverage_reconciliation_diagnostics.sql
-- Description: Split reconciliation diagnostics into dedicated diagnostic functions.
--              Includes per-CG and all-CG anomaly scans without modifying data.
--              Maintains business logic security and ADR-001 integrity.

BEGIN;

-- ============================================================================
-- §1  fn_coverage_group_diagnostics(p_coverage_group_id uuid)
--     Returns detailed anomaly rows for a single Coverage Group:
--       - Inactive or soft-deleted employees who still have active store links here.
--       - Active employees with active store links for this CG but master is not linked or not Roving.
--       - Active slot-occupant mismatches (occupant has mismatching group/slot/deployment).
--     Returns empty JSON array if no anomalies found.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_coverage_group_diagnostics(p_coverage_group_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_cg               record;
  v_anomaly          record;
  v_diagnostics      jsonb := '[]'::jsonb;
BEGIN
  -- Fetch CG details
  SELECT cg.*, a.account_name
  INTO v_cg
  FROM public.coverage_groups cg
  JOIN public.accounts a ON a.id = cg.account_id
  WHERE cg.id = p_coverage_group_id
    AND cg.archived_at IS NULL;

  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  -- 1. Inactive or soft-deleted employees who still have active store links here
  FOR v_anomaly IN (
    SELECT DISTINCT psl.plantilla_id, pl.employee_no, pl.status, pl.is_deleted, pl.is_archived
    FROM public.plantilla_store_links psl
    JOIN public.plantilla pl ON pl.id = psl.plantilla_id
    WHERE psl.coverage_group_id = p_coverage_group_id
      AND psl.deleted_at IS NULL
      AND (pl.status <> 'Active' OR pl.is_deleted = true OR pl.is_archived = true)
  ) LOOP
    v_diagnostics := v_diagnostics || jsonb_build_object(
      'type', 'inactive_employee_retained_store_links',
      'employee_no', v_anomaly.employee_no,
      'plantilla_id', v_anomaly.plantilla_id,
      'status', v_anomaly.status,
      'is_deleted', v_anomaly.is_deleted,
      'is_archived', v_anomaly.is_archived,
      'coverage_group_id', p_coverage_group_id,
      'coverage_code', v_cg.coverage_code
    );
  END LOOP;

  -- 2. Employees with active store links for this CG but master is not linked or not Roving
  FOR v_anomaly IN (
    SELECT DISTINCT psl.plantilla_id, pl.employee_no, pl.deployment_type, pl.coverage_group_id
    FROM public.plantilla_store_links psl
    JOIN public.plantilla pl ON pl.id = psl.plantilla_id
    WHERE psl.coverage_group_id = p_coverage_group_id
      AND psl.deleted_at IS NULL
      AND pl.status = 'Active'
      AND COALESCE(pl.is_deleted, false) = false
      AND COALESCE(pl.is_archived, false) = false
      AND (pl.coverage_group_id IS DISTINCT FROM p_coverage_group_id OR COALESCE(pl.deployment_type, '') <> 'Roving')
  ) LOOP
    v_diagnostics := v_diagnostics || jsonb_build_object(
      'type', 'plantilla_store_links_deployment_mismatch',
      'employee_no', v_anomaly.employee_no,
      'plantilla_id', v_anomaly.plantilla_id,
      'deployment_type', v_anomaly.deployment_type,
      'current_coverage_group_id', v_anomaly.coverage_group_id,
      'coverage_group_id', p_coverage_group_id,
      'coverage_code', v_cg.coverage_code
    );
  END LOOP;

  -- 3. Slot-level occupant anomalies (slot occupant mismatch)
  FOR v_anomaly IN (
    SELECT DISTINCT cs.id AS slot_id, cs.slot_ordinal, cs.current_occupant_plantilla_id, pl.employee_no, pl.deployment_type, pl.coverage_group_id, pl.coverage_slot_id
    FROM public.coverage_slots cs
    JOIN public.plantilla pl ON pl.id = cs.current_occupant_plantilla_id
    WHERE cs.coverage_group_id = p_coverage_group_id
      AND cs.slot_status = 'active'
      AND (pl.coverage_group_id IS DISTINCT FROM p_coverage_group_id OR pl.coverage_slot_id IS DISTINCT FROM cs.id OR COALESCE(pl.deployment_type, '') <> 'Roving')
  ) LOOP
    v_diagnostics := v_diagnostics || jsonb_build_object(
      'type', 'coverage_slot_occupant_mismatch',
      'slot_id', v_anomaly.slot_id,
      'slot_ordinal', v_anomaly.slot_ordinal,
      'employee_no', v_anomaly.employee_no,
      'plantilla_id', v_anomaly.current_occupant_plantilla_id,
      'plantilla_coverage_group_id', v_anomaly.coverage_group_id,
      'plantilla_coverage_slot_id', v_anomaly.coverage_slot_id,
      'plantilla_deployment_type', v_anomaly.deployment_type,
      'coverage_group_id', p_coverage_group_id,
      'coverage_code', v_cg.coverage_code
    );
  END LOOP;

  RETURN v_diagnostics;
END;
$fn$;

COMMENT ON FUNCTION public.fn_coverage_group_diagnostics(uuid) IS
  'ohm#4q8z2m7a: Detailed non-modifying diagnostics for a single Coverage Group. '
  'Returns a JSONB array of anomalies representing slot, link, or deployment drifts. '
  'Safe to call anytime — read-only.';

GRANT EXECUTE ON FUNCTION public.fn_coverage_group_diagnostics(uuid) TO service_role;


-- ============================================================================
-- §2  fn_all_coverage_groups_diagnostics()
--     Iterates all active (non-archived) Coverage Groups and aggregates
--     the detailed diagnostics from each.
--     Returns a unified JSONB array of all anomalies found.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_all_coverage_groups_diagnostics()
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_cg            record;
  v_result        jsonb;
  v_diagnostics   jsonb := '[]'::jsonb;
BEGIN
  FOR v_cg IN (
    SELECT id
    FROM public.coverage_groups
    WHERE archived_at IS NULL
    ORDER BY created_at
  ) LOOP
    v_result := public.fn_coverage_group_diagnostics(v_cg.id);
    IF jsonb_array_length(v_result) > 0 THEN
      v_diagnostics := v_diagnostics || v_result;
    END IF;
  END LOOP;

  RETURN v_diagnostics;
END;
$fn$;

COMMENT ON FUNCTION public.fn_all_coverage_groups_diagnostics() IS
  'ohm#4q8z2m7a: Unified detailed non-modifying diagnostics across all active Coverage Groups. '
  'Iterates over all non-archived groups and aggregates their diagnostics. '
  'Safe to call anytime — read-only.';

GRANT EXECUTE ON FUNCTION public.fn_all_coverage_groups_diagnostics() TO service_role;


-- ============================================================================
-- §3  Automatic Diagnostic Run on Apply
-- ============================================================================

DO $$
DECLARE
  v_result jsonb;
BEGIN
  RAISE NOTICE '══════════════════════════════════════════════════════════════';
  RAISE NOTICE 'ohm#4q8z2m7a — Coverage Reconciliation Diagnostics';
  RAISE NOTICE 'RUNNING DIAGNOSTICS CHECK...';
  RAISE NOTICE '══════════════════════════════════════════════════════════════';
  
  v_result := public.fn_all_coverage_groups_diagnostics();
  
  RAISE NOTICE 'Diagnostic check completed. Anomalies detected: %', jsonb_array_length(v_result);
  IF jsonb_array_length(v_result) > 0 THEN
    RAISE NOTICE 'Anomaly list: %', v_result;
  ELSE
    RAISE NOTICE 'Diagnostics clean. Zero anomalies found. ✓';
  END IF;
  RAISE NOTICE '══════════════════════════════════════════════════════════════';
END;
$$;


COMMIT;
