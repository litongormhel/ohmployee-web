-- ==============================================================================
-- Migration: 20262606000163_clean_hard_delete_aling_nena_store.sql
-- Description:
--   Hard delete inactive test account 'ALING NENA STORE' and its associated
--   child artifacts (5 rejected test import batches, 25 import rows, 1 approved
--   new store request, and 1 archived store).
-- Target:
--   Account: 'ALING NENA STORE' (id: f60c15d4-5611-4632-b82b-802c81aec713)
--   Store:   'ALING NENA'       (id: 518bdc0c-118a-42d3-9140-e99b501fcb21)
-- ==============================================================================

-- §1. Delete child plantilla import rows for the rejected batches of ALING NENA STORE
DELETE FROM public.plantilla_import_rows
WHERE batch_id IN (
  SELECT id FROM public.plantilla_import_batches
  WHERE selected_account_id = 'f60c15d4-5611-4632-b82b-802c81aec713'
     OR selected_account_id IN (SELECT id FROM public.accounts WHERE account_name ILIKE '%ALING NENA%')
);

-- §2. Delete rejected plantilla import batches for ALING NENA STORE
DELETE FROM public.plantilla_import_batches
WHERE selected_account_id = 'f60c15d4-5611-4632-b82b-802c81aec713'
   OR selected_account_id IN (SELECT id FROM public.accounts WHERE account_name ILIKE '%ALING NENA%');

-- §3. Delete new store requests referencing ALING NENA STORE or its store
DELETE FROM public.new_store_requests
WHERE account_id = 'f60c15d4-5611-4632-b82b-802c81aec713'
   OR created_store_id = '518bdc0c-118a-42d3-9140-e99b501fcb21'
   OR account_id IN (SELECT id FROM public.accounts WHERE account_name ILIKE '%ALING NENA%')
   OR created_store_id IN (SELECT id FROM public.stores WHERE store_name ILIKE '%ALING NENA%');

-- §4. Delete child stores belonging to ALING NENA STORE
DELETE FROM public.stores
WHERE id = '518bdc0c-118a-42d3-9140-e99b501fcb21'
   OR account_id = 'f60c15d4-5611-4632-b82b-802c81aec713'
   OR account_id IN (SELECT id FROM public.accounts WHERE account_name ILIKE '%ALING NENA%');

-- §5. Hard delete the account ALING NENA STORE
DELETE FROM public.accounts
WHERE id = 'f60c15d4-5611-4632-b82b-802c81aec713'
   OR account_name ILIKE '%ALING NENA%';
