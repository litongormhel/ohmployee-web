-- Migration: 20262606000159_clean_vacancy_dirty_data_system_wide.sql
-- Description: Clean system-wide dirty data across Vacancies, Applicants, and HR Emploc:
-- 1. MARIZ: Archive 10 leftover open template vacancies (account active stores/plantilla = 0).
-- 2. FOREVER OFFICE: Auto-provision slot ordinal 1 ('open') for CPPGJV19 and CPSAJV27 (1:1 slot parity).
-- 3. Vacancies status alignment: Update status = 'Archived' for vacancies where is_archived = true OR deleted_at IS NOT NULL.
-- 4. Historical applicants: Mark abandoned test applicants on closed/archived vacancies as 'Backout'.
-- 5. HR Emploc & Applicants: Clean up separated former employees lingering in active status.

-- Enable temporary override for scheduled vacancy edit lock during migration
UPDATE public.vacancy_edit_locks SET is_override_active = true WHERE id = 1;

DO $$
BEGIN
  -- -------------------------------------------------------------------------
  -- 1. MARIZ: Archive 10 leftover open vacancies from rolled-back template
  -- -------------------------------------------------------------------------
  UPDATE public.vacancies
  SET status = 'Archived',
      is_archived = true,
      archived_at = NOW(),
      archive_reason = 'Template batch rollback cleanup',
      updated_at = NOW()
  WHERE account_id = '81160797-d25a-4204-a981-e90ff9a58932' -- MARIZ
    AND status = 'Open'
    AND is_archived = false;

  -- -------------------------------------------------------------------------
  -- 2. FOREVER OFFICE: Auto-provision physical slot ordinal 1 ('open')
  -- -------------------------------------------------------------------------
  INSERT INTO public.plantilla_slots (
    store_id,
    account_id,
    group_id,
    position,
    employment_type,
    is_roving,
    slot_status,
    slot_ordinal,
    legacy_vcode,
    created_at,
    created_by
  )
  SELECT
    v.store_id,
    v.account_id,
    v.group_id,
    v.position,
    'stationary',
    false,
    'open',
    1,
    v.vcode,
    NOW(),
    'b865eef6-ebac-4bd3-84b5-482c00774565'::uuid
  FROM public.vacancies v
  WHERE v.vcode IN ('CPPGJV19', 'CPSAJV27')
    AND NOT EXISTS (
      SELECT 1 FROM public.plantilla_slots ps WHERE ps.legacy_vcode = v.vcode
    );

  -- -------------------------------------------------------------------------
  -- 3. Align status for Soft-Deleted or Archived Vacancies
  -- -------------------------------------------------------------------------
  UPDATE public.vacancies
  SET status = 'Archived',
      updated_at = NOW()
  WHERE status = 'Open'
    AND (is_archived = true OR deleted_at IS NOT NULL);

  -- -------------------------------------------------------------------------
  -- 4. Abandoned Historical Applicants on Closed/Archived Vacancies
  -- -------------------------------------------------------------------------
  UPDATE public.applicants
  SET status = 'Backout',
      backout_reason = 'Requisition closed/archived (historical cleanup)',
      is_archived = true,
      archived_at = NOW(),
      updated_at = NOW()
  WHERE status NOT IN ('Backout', 'Failed', 'Rejected', 'Did Not Report', 'Hired')
    AND vacancy_vcode IN (
      SELECT v.vcode FROM public.vacancies v
      WHERE (v.status = 'Closed' OR v.is_archived = true OR v.deleted_at IS NOT NULL)
    );

  -- -------------------------------------------------------------------------
  -- 5. HR Emploc & Applicants: Align separated former employees
  -- -------------------------------------------------------------------------
  UPDATE public.hr_emploc
  SET status = 'Backout',
      deleted_at = NOW(),
      updated_at = NOW()
  WHERE id IN (
    '8e2d7a23-ad9e-4005-b857-ea12d2a492b5', -- Jun Jay Dela Cruz (separated 2026-11-23)
    '1913c6cf-b191-422b-9717-009b5f9e562e', -- Jayden Dela Fuente (separated 2026-11-05)
    '6aeace79-fc3f-46b8-87b1-25bbed6d096a'  -- Juan Santos Dela Cruz (separated 2026-11-05)
  );

  UPDATE public.applicants
  SET status = 'Backout',
      backout_reason = 'Employee separated from plantilla',
      is_archived = true,
      archived_at = NOW(),
      updated_at = NOW()
  WHERE id IN (
    '93df5681-8ec7-4dbe-8f4f-6c20d8ee11f2', -- Jayson Santos (ACT-G5-002, deactivated/deleted in plantilla)
    '71d72242-62be-4e06-8251-c8e19cb839c6'  -- Jun Jay Dela Cruz (ACT-G5-008, separated 2026-11-23)
  );

END $$;

-- Restore scheduled vacancy edit lock override
UPDATE public.vacancy_edit_locks SET is_override_active = false WHERE id = 1;
