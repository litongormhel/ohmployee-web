-- ============================================================
-- OHM2026_0071d — One-time data fix: Clean up duplicate Inactive rows for employee 2023-10978
-- Migration: 20260913000003_fix_emploc_2023_10978_duplicate_inactive_cleanup.sql
-- Depends on: 20260913000002_fix_all_duplicate_inactive_cleanup.sql
-- ============================================================
-- Problem
-- -------
-- Employee 2023-10978 has 4 duplicate Inactive plantilla records and no Active
-- record. These were created due to repeated bad imports before OHM2026_0071 reconcile fix.
--
-- Fix
-- ---
-- Keep the most recent Inactive record (id: a7cab3f7-6535-4225-8f93-281dcd9e67b4, created at 07:53)
-- and soft-delete the 3 older ones by setting is_deleted = true.
--
-- Safety
-- ------
-- • Only targets employee_no = '2023-10978' with status = 'Inactive' and is_deleted = false.
-- • Preserves the canonical latest Inactive record.
-- • Writes an audit log entry for each soft-deleted row.
-- ============================================================

DO $$
DECLARE
  v_row     record;
  v_deleted int := 0;
BEGIN
  -- We query all rows for 2023-10978 except the latest one by ordering by created_at desc
  -- and skipping the first row (OFFSET 1).
  FOR v_row IN
    SELECT id, status
      FROM public.plantilla
     WHERE employee_no = '2023-10978'
       AND status = 'Inactive'
       AND is_deleted = false
     ORDER BY created_at DESC
     OFFSET 1
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
        'employee_no',    '2023-10978',
        'previous_status', v_row.status,
        'reason',         'OHM2026_0071d: duplicate Inactive row from bad import before reconcile fix',
        'cleanup_at',     NOW()
      )
    );

    v_deleted := v_deleted + 1;
    RAISE NOTICE 'OHM2026_0071d: soft-deleted Inactive duplicate id=% for employee_no=2023-10978',
      v_row.id;
  END LOOP;

  RAISE NOTICE 'OHM2026_0071d complete: % duplicate Inactive row(s) soft-deleted for employee_no=2023-10978.',
    v_deleted;
END$$;
