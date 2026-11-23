-- ==============================================================================
-- Migration: 20262606000139_account_archive_cascade_and_orphan_stores_cleanup.sql
-- Description:
--   1. Adds trigger trg_account_archive_cascade_stores on public.accounts so that
--      when an account is marked inactive/archived, its child stores are cascade-deactivated.
--   2. Cleans up historical orphan stores and batches resulting from legacy failed rollbacks:
--      - ALING NENA STORE: orphan store ALING NENA
--      - MARIZ: batch a1bf2b5e-2e8e-40f1-93e0-c730a626b452 (4 stores + 2 plantilla)
--      - ZEBRA: batches 29f1c261-39ea-4cc7-9b1e-681ccb55c7c9 & a79f1571-4ee4-48db-9aa6-d2a66f08a347
--      - ALTURAS: batch 0071cb78-c960-46b7-a5dd-dbce08335449
--      - APEX: batch 82ee6311-404f-4358-b4d8-3d45cf30641b (14 stores + 4 plantilla)
--      - ONE: batches 1d7ffc3f-a5b0-468f-bb39-689e3189428d & e9102051-c6cf-4057-8eee-8896d3fe6846
-- ==============================================================================

-- 1. Create account archival cascade trigger function
CREATE OR REPLACE FUNCTION public.fn_trg_account_archive_cascade_stores()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid;
BEGIN
  -- Safe actor resolution
  BEGIN
    v_actor := public.get_current_profile_id();
  EXCEPTION WHEN OTHERS THEN
    v_actor := NULL;
  END;

  -- Cascade deactivation/archival to all child stores under this account
  UPDATE public.stores
     SET is_active   = false,
         status      = 'archived',
         is_archived = true,
         archived_at = COALESCE(archived_at, now()),
         updated_at  = now(),
         updated_by  = COALESCE(v_actor, updated_by)
   WHERE account_id = NEW.id
     AND is_active = true;

  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_trg_account_archive_cascade_stores() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_account_archive_cascade_stores ON public.accounts;
CREATE TRIGGER trg_account_archive_cascade_stores
AFTER UPDATE OF is_active, is_archived, status ON public.accounts
FOR EACH ROW
WHEN (
  (NEW.is_active = false AND OLD.is_active = true) OR
  (NEW.is_archived = true AND COALESCE(OLD.is_archived, false) = false) OR
  (NEW.status = 'Inactive' AND COALESCE(OLD.status, '') != 'Inactive')
)
EXECUTE FUNCTION public.fn_trg_account_archive_cascade_stores();

-- 2. Data Cleanup: Deactivate orphan store of inactive account ALING NENA STORE
UPDATE public.stores
   SET is_active   = false,
       status      = 'archived',
       is_archived = true,
       archived_at = COALESCE(archived_at, now()),
       updated_at  = now()
 WHERE id = '518bdc0c-118a-42d3-9140-e99b501fcb21'
   AND is_active = true;

-- 3. Data Cleanup: MARIZ batch a1bf2b5e-2e8e-40f1-93e0-c730a626b452
-- 3a. Archive the 4 orphan stores created by this batch
UPDATE public.stores
   SET is_active   = false,
       status      = 'archived',
       is_archived = true,
       archived_at = COALESCE(archived_at, now()),
       updated_at  = now()
 WHERE source_import_id = 'a1bf2b5e-2e8e-40f1-93e0-c730a626b452'
   AND is_active = true;

-- 3b. Archive the 2 active plantilla rows created by this batch
UPDATE public.plantilla
   SET is_archived    = true,
       archived_at    = COALESCE(archived_at, now()),
       archive_reason = 'Failed rollback orphan cleanup',
       status         = 'Inactive',
       updated_at     = now()
 WHERE source_baseline_import_batch_id = 'a1bf2b5e-2e8e-40f1-93e0-c730a626b452'
   AND COALESCE(is_archived, false) = false;

-- 3c. Mark the batch as rolled_back
UPDATE public.plantilla_import_batches
   SET status                = 'rolled_back',
       rollback_status       = 'completed',
       rolled_back_at        = COALESCE(rolled_back_at, now()),
       rollback_error_detail = NULL,
       updated_at            = now()
 WHERE id = 'a1bf2b5e-2e8e-40f1-93e0-c730a626b452';

-- 4. Data Cleanup: ZEBRA batches 29f1c261-39ea-4cc7-9b1e-681ccb55c7c9 & a79f1571-4ee4-48db-9aa6-d2a66f08a347
-- 4a. Archive stores with 0 active allocations
UPDATE public.stores
   SET is_active   = false,
       status      = 'archived',
       is_archived = true,
       archived_at = COALESCE(archived_at, now()),
       updated_at  = now()
 WHERE source_import_id IN ('29f1c261-39ea-4cc7-9b1e-681ccb55c7c9', 'a79f1571-4ee4-48db-9aa6-d2a66f08a347')
   AND is_active = true
   AND NOT EXISTS (
     SELECT 1 FROM public.employee_store_allocations esa
      WHERE esa.store_id = stores.id AND esa.is_active = true
   );

-- 4b. Close any vacancies on these stores
UPDATE public.vacancies
   SET status      = 'Closed',
       is_archived = true,
       archived_at = COALESCE(archived_at, now()),
       closed_at   = COALESCE(closed_at, now()),
       updated_at  = now()
 WHERE store_id IN (
   SELECT id FROM public.stores
    WHERE source_import_id IN ('29f1c261-39ea-4cc7-9b1e-681ccb55c7c9', 'a79f1571-4ee4-48db-9aa6-d2a66f08a347')
 )
 AND status = 'Open';

-- 4c. Close plantilla slots on these stores
UPDATE public.plantilla_slots
   SET slot_status = 'closed',
       updated_at  = now()
 WHERE store_id IN (
   SELECT id FROM public.stores
    WHERE source_import_id IN ('29f1c261-39ea-4cc7-9b1e-681ccb55c7c9', 'a79f1571-4ee4-48db-9aa6-d2a66f08a347')
 )
 AND slot_status != 'closed';

-- 4d. Mark batch records completed
UPDATE public.plantilla_import_batches
   SET status          = 'rolled_back',
       rollback_status = 'completed',
       rolled_back_at  = COALESCE(rolled_back_at, now()),
       updated_at      = now()
 WHERE id IN ('29f1c261-39ea-4cc7-9b1e-681ccb55c7c9', 'a79f1571-4ee4-48db-9aa6-d2a66f08a347');

-- 5. Data Cleanup: ALTURAS batch 0071cb78-c960-46b7-a5dd-dbce08335449
UPDATE public.stores
   SET is_active   = false,
       status      = 'archived',
       is_archived = true,
       archived_at = COALESCE(archived_at, now()),
       updated_at  = now()
 WHERE source_import_id = '0071cb78-c960-46b7-a5dd-dbce08335449'
   AND is_active = true
   AND NOT EXISTS (
     SELECT 1 FROM public.employee_store_allocations esa
      WHERE esa.store_id = stores.id AND esa.is_active = true
   );

UPDATE public.plantilla_import_batches
   SET status          = 'rolled_back',
       rollback_status = 'completed',
       rolled_back_at  = COALESCE(rolled_back_at, now()),
       updated_at      = now()
 WHERE id = '0071cb78-c960-46b7-a5dd-dbce08335449';

-- 6. Data Cleanup: APEX batch 82ee6311-404f-4358-b4d8-3d45cf30641b
UPDATE public.stores
   SET is_active   = false,
       status      = 'archived',
       is_archived = true,
       archived_at = COALESCE(archived_at, now()),
       updated_at  = now()
 WHERE source_import_id = '82ee6311-404f-4358-b4d8-3d45cf30641b'
   AND is_active = true
   AND NOT EXISTS (
     SELECT 1 FROM public.employee_store_allocations esa
      WHERE esa.store_id = stores.id AND esa.is_active = true
   );

UPDATE public.plantilla
   SET is_archived    = true,
       archived_at    = COALESCE(archived_at, now()),
       archive_reason = 'Rejected batch cleanup',
       status         = 'Inactive',
       updated_at     = now()
 WHERE source_baseline_import_batch_id = '82ee6311-404f-4358-b4d8-3d45cf30641b'
   AND COALESCE(is_archived, false) = false;

UPDATE public.plantilla_import_batches
   SET rollback_status = 'completed',
       rolled_back_at  = COALESCE(rolled_back_at, now()),
       updated_at      = now()
 WHERE id = '82ee6311-404f-4358-b4d8-3d45cf30641b';

-- 7. Data Cleanup: ONE batches 1d7ffc3f-a5b0-468f-bb39-689e3189428d & e9102051-c6cf-4057-8eee-8896d3fe6846
UPDATE public.plantilla_import_batches
   SET status                = 'rolled_back',
       rollback_status       = 'completed',
       rolled_back_at        = COALESCE(rolled_back_at, now()),
       rollback_error_detail = NULL,
       updated_at            = now()
 WHERE id IN ('1d7ffc3f-a5b0-468f-bb39-689e3189428d', 'e9102051-c6cf-4057-8eee-8896d3fe6846');
