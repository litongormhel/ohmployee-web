-- ============================================================
-- OHM2026_0071c — One-time data fix: Clean up duplicate Inactive rows for all affected employees
-- Migration: 20260913000002_fix_all_duplicate_inactive_cleanup.sql
-- Depends on: 20260913000001_fix_emploc_2023_09515_duplicate_inactive_cleanup.sql
-- ============================================================
-- Problem
-- -------
-- Several employees accumulated orphan Inactive plantilla rows from
-- repeated bad imports before OHM2026_0071 was applied. Each import that
-- found the employee in Inactive status missed the reconcile path and
-- inserted a new Active row, leaving the old Inactive rows behind.
--
-- Fix
-- ---
-- Soft-delete all duplicate Inactive rows for employees who currently
-- have an Active row by setting is_deleted = true.
--
-- Safety
-- ------
-- • Only targets employees who have both an Active row AND an Inactive row (is_deleted = false).
-- • Only soft-deletes the Inactive rows, leaving the Active row untouched.
-- • Writes an audit log entry for each soft-deleted duplicate row.
-- ============================================================

DO $$
DECLARE
  v_row     record;
  v_deleted int := 0;
BEGIN
  FOR v_row IN
    -- Find all duplicate Inactive rows for employees who also have a non-deleted Active row
    SELECT p_inactive.id, p_inactive.employee_no, p_inactive.status
      FROM public.plantilla p_inactive
     WHERE p_inactive.status = 'Inactive'
       AND p_inactive.is_deleted = false
       AND EXISTS (
         SELECT 1
           FROM public.plantilla p_active
          WHERE p_active.employee_no = p_inactive.employee_no
            AND p_active.status = 'Active'
            AND p_active.is_deleted = false
       )
     ORDER BY p_inactive.employee_no, p_inactive.created_at
  LOOP
    -- Soft-delete the duplicate Inactive row
    UPDATE public.plantilla
       SET is_deleted  = true,
           updated_at  = NOW()
     WHERE id = v_row.id;

    -- Audit the cleanup
    INSERT INTO public.audit_logs (actor_id, module, action, record_id, new_data)
    VALUES (
      NULL,  -- system migration, no actor
      'plantilla_import',
      'IMPORT_DUPLICATE_CLEANUP'::public.audit_action,
      v_row.id,
      jsonb_build_object(
        'employee_no',    v_row.employee_no,
        'previous_status', v_row.status,
        'reason',         'OHM2026_0071c: duplicate Inactive row from bad import before reconcile fix',
        'cleanup_at',     NOW()
      )
    );

    v_deleted := v_deleted + 1;
    RAISE NOTICE 'OHM2026_0071c: soft-deleted Inactive duplicate id=% for employee_no=%',
      v_row.id, v_row.employee_no;
  END LOOP;

  RAISE NOTICE 'OHM2026_0071c complete: % duplicate Inactive row(s) soft-deleted across all affected employees.',
    v_deleted;
END$$;
