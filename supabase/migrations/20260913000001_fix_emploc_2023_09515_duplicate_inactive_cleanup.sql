-- ============================================================
-- OHM2026_0071b — One-time data fix: Remove duplicate Inactive rows for Emploc# 2023-09515
-- Migration: 20260913000001_fix_emploc_2023_09515_duplicate_inactive_cleanup.sql
-- Depends on: 20260913000000_fix_import_inactive_reconcile_and_slot_occupancy.sql
-- ============================================================
-- Problem
-- -------
-- Emploc# 2023-09515 accumulated 3 orphan Inactive plantilla rows from
-- repeated bad imports before OHM2026_0071 was applied. Each import that
-- found the employee in Inactive status missed the reconcile path and
-- inserted a new Active row, leaving the old Inactive rows behind.
--
-- Current state (verified 2026-06-05):
--   id=08aee5f5  status=Inactive  vcode=NULL  created 07:25
--   id=48694798  status=Inactive  vcode=NULL  created 07:43
--   id=abf112aa  status=Inactive  vcode=NULL  created 07:48  (inactive_at set)
--   id=5f022b52  status=Active    vcode=NULL  created 07:53  ← KEEP (canonical row)
--
-- Fix
-- ---
-- Soft-delete all 3 Inactive rows for employee_no = '2023-09515' by setting
-- is_deleted = true. The Active row (5f022b52) is preserved as the canonical
-- lifecycle row.
--
-- Safety
-- ------
-- • Only targets employee_no = '2023-09515' with status = 'Inactive'
-- • Excludes the Active row (status filter ensures it is untouched)
-- • is_deleted = true is the project's standard soft-delete pattern
-- • employee_store_allocations for the deleted rows have already had
--   is_active = false set by the import commit (allocation cleanup is idempotent)
-- • No plantilla_slots rows exist for these vcode=NULL rows (confirmed by backfill:
--   slot creation requires vcode IS NOT NULL)
-- • Audit log written for each soft-deleted row
-- ============================================================

DO $$
DECLARE
  v_row     record;
  v_deleted int := 0;
BEGIN
  FOR v_row IN
    SELECT id, status, created_at
      FROM public.plantilla
     WHERE employee_no = '2023-09515'
       AND status = 'Inactive'
       AND is_deleted = false
     ORDER BY created_at
  LOOP
    -- Soft-delete the orphan Inactive row
    UPDATE public.plantilla
       SET is_deleted  = true,
           updated_at  = NOW()
     WHERE id = v_row.id;

    -- Audit the cleanup
    INSERT INTO public.audit_logs (actor_id, module, action, record_id, new_data)
    VALUES (
      NULL,  -- system migration, no actor
      'plantilla_import',
      'IMPORT_DUPLICATE_CLEANUP',
      v_row.id,
      jsonb_build_object(
        'employee_no',    '2023-09515',
        'previous_status', v_row.status,
        'reason',         'OHM2026_0071b: duplicate Inactive row from bad import before reconcile fix',
        'cleanup_at',     NOW()
      )
    );

    v_deleted := v_deleted + 1;
    RAISE NOTICE 'OHM2026_0071b: soft-deleted Inactive duplicate id=% for employee_no=2023-09515',
      v_row.id;
  END LOOP;

  RAISE NOTICE 'OHM2026_0071b complete: % duplicate Inactive row(s) soft-deleted for employee_no=2023-09515.',
    v_deleted;
END$$;

-- Validation query (run manually after applying):
-- T1 — Only one non-deleted row remains for 2023-09515
--   SELECT status, count(*) FROM plantilla
--   WHERE employee_no = '2023-09515' AND is_deleted = false
--   GROUP BY status;
--   -- Expected: 1 row, status = 'Active', cnt = 1
--
-- T2 — Deleted rows are now is_deleted = true
--   SELECT id, status, is_deleted FROM plantilla
--   WHERE employee_no = '2023-09515';
--   -- Expected: 3 rows with is_deleted=true (Inactive), 1 with is_deleted=false (Active)
--
-- T3 — Audit log entries written
--   SELECT record_id, action, new_data->>'reason' FROM audit_logs
--   WHERE module = 'plantilla_import' AND action = 'IMPORT_DUPLICATE_CLEANUP'
--   ORDER BY created_at;
--   -- Expected: 3 rows, one per deleted Inactive row
