-- ==============================================================================
-- Migration: 20262606000141_archive_mariz_orphan_stores_and_sync_all_archived_stores.sql
-- Description:
--   1. Archive all 18 orphan test stores under MARIZ (16 Super 8 template duplicate stores
--      from import_plantilla_template (6).xlsx and 2 SM stores whose HC requests were QA-reset)
--   2. Archive the 12 template employees and 16 allocations under MARIZ batch 2e797b40...
--   3. Mark historical template batches for MARIZ as rolled_back
--   4. Global database-wide synchronization of all stores where status = 'archived' or is_active = false
--      ensuring is_archived = true and archived_at is populated
--   5. Mark all plantilla slots on archived stores as is_archived = true
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Archive MARIZ orphan stores (16 template Super 8 stores + 2 QA-reset SM stores)
-- ------------------------------------------------------------------------------
UPDATE public.stores
SET is_active = false,
    status = 'archived',
    is_archived = true,
    archived_at = now()
WHERE account_id = '81160797-d25a-4204-a981-e90ff9a58932'
  AND is_active = true;

-- ------------------------------------------------------------------------------
-- 2. Archive MARIZ template employees and deactivate allocations
-- ------------------------------------------------------------------------------
UPDATE public.employee_store_allocations
SET is_active = false
WHERE store_id IN (
  SELECT id FROM public.stores WHERE account_id = '81160797-d25a-4204-a981-e90ff9a58932'
)
AND is_active = true;

UPDATE public.plantilla
SET is_archived = true,
    archived_at = now(),
    status = 'Inactive'
WHERE (account_id = '81160797-d25a-4204-a981-e90ff9a58932' OR account = 'MARIZ')
  AND (is_archived IS NULL OR is_archived = false);

-- ------------------------------------------------------------------------------
-- 3. Mark MARIZ template batches as rolled_back
-- ------------------------------------------------------------------------------
UPDATE public.plantilla_import_batches
SET status = 'rolled_back',
    rolled_back_at = now(),
    rollback_reason = 'Template test upload - dummy stores and template employees archived'
WHERE id IN (
  '2e797b40-dd91-4caf-9ce3-c4c86f658ac5',
  '31d2258e-d85c-4330-abd2-c104c3af523c',
  '3b833d95-59cf-4999-bf78-73576671595d',
  'd0a94f74-711f-458b-af8e-9fadf0b7595a'
);

-- ------------------------------------------------------------------------------
-- 4. Global synchronization of all historically de-synced stores across database
--    (Aligning status = 'archived', is_active = false, is_archived = true)
-- ------------------------------------------------------------------------------
UPDATE public.stores
SET is_active = false,
    status = 'archived',
    is_archived = true,
    archived_at = COALESCE(archived_at, now())
WHERE (status = 'archived' OR is_active = false)
  AND (is_archived IS NULL OR is_archived = false);

-- ------------------------------------------------------------------------------
-- 5. Mark all slots on archived stores as is_archived = true
-- ------------------------------------------------------------------------------
UPDATE public.plantilla_slots
SET is_archived = true,
    archived_at = COALESCE(archived_at, now())
WHERE store_id IN (
  SELECT id FROM public.stores WHERE is_active = false AND is_archived = true
)
AND (is_archived IS NULL OR is_archived = false);
