-- ============================================================================
-- Staging Cleanup Script: Post-Verification Test Artifacts
-- Prompt ID: ohm#k6w3n8qd
-- Target Database: STAGING (qqiiznmqxfoamqytjica) ONLY
--
-- PURPOSE:
--   Returns Group 4 / APEX staging data to the exact BEFORE baseline:
--     - Stores: exactly 5 active stores (PG-2026-001 to PG-2026-005)
--     - Plantilla: exactly 5 active employees (0001-2026-0001 to 0001-2026-0005)
--     - Plantilla Slots: exactly 5 occupied slots
--     - Store Allocations: exactly 5 active allocations
--     - Plantilla Store Links: exactly 5 links
--     - Vacancies: 0 open vacancies for test stores
--     - Import Batches: 0 test batches
--
-- TRIGGER RESOLUTION (fn_trg_store_closure_cascade_vacancies):
--   The trigger 'trg_store_closure_cascade_vacancies' is defined as:
--     BEFORE UPDATE ON public.stores
--     WHEN (NEW.status = 'archived' OR NEW.is_active = false ...)
--   It fails during UPDATE because it attempts to set 'vacancies.closed_at',
--   a column that does not exist on public.vacancies.
--   HOW THIS SCRIPT AVOIDS IT WITHOUT ALTERING THE TRIGGER:
--     1. We do NOT run any UPDATE on public.stores.
--     2. We explicitly DELETE all 14 child vacancies first.
--     3. We explicitly DELETE the 14 stores directly.
--     Since trg_store_closure_cascade_vacancies only listens to UPDATE events,
--     a direct DELETE completely bypasses the trigger cleanly and safely.
-- ============================================================================

BEGIN;

-- 1. Remove Audit Logs for Test Rejection
DELETE FROM public.audit_logs
 WHERE id = 'b4d86e38-c1d2-4684-a6c9-dff719d5db1f'
    OR record_id = 'c8a07202-4bd3-4612-a116-80150a26bc56';

-- 2. Remove Plantilla Import Rows for the 3 Test Batches
DELETE FROM public.plantilla_import_rows
 WHERE batch_id IN (
   '84104869-acfb-4145-aa16-9df40fb9c5d5',
   '82ee6311-404f-4358-b4d8-3d45cf30641b',
   'c8a07202-4bd3-4612-a116-80150a26bc56'
 );

-- 3. Remove Plantilla Import Batches (3 Test Batches)
DELETE FROM public.plantilla_import_batches
 WHERE id IN (
   '84104869-acfb-4145-aa16-9df40fb9c5d5',
   '82ee6311-404f-4358-b4d8-3d45cf30641b',
   'c8a07202-4bd3-4612-a116-80150a26bc56'
 );

-- 4. Remove 14 Vacancies Spawned During Inactivation of Test Plantilla Rows
DELETE FROM public.vacancies
 WHERE id IN (
   '63600c9c-8e91-4343-aa27-0b34b12331eb', -- PG-2026-006 Puregold Marikina
   'b8117b94-a6fc-44bf-add6-59c4cd7d409d', -- PG-2026-007 Puregold Concepcion
   '1c64acf0-9ad0-4637-b9fc-b4dd799f741a', -- PG-2026-008 Puregold San Mateo
   '84bf6281-e1db-4335-abc1-1ec05bdf1f8a', -- PG-2026-009 Puregold Montalban
   '69808775-de91-4317-b6e1-6d385bf06f58', -- PG-2026-010 Puregold Nangka
   '9bad36c4-9621-4dcc-b92e-77e5aba7a382', -- PG-2026-011 Puregold Ampid
   'af5b5354-da87-49af-a482-5faee89bf193', -- PG-2026-012 Puregold Parang
   '828449f8-7f14-425c-83cb-1c158de02f3a', -- PG-2026-013 Puregold Tumana
   '01a9bdbd-4754-4867-b9cf-352458753639', -- PG-2026-014 Puregold Barangka
   'ff222278-19a4-49ca-8f18-a0638b27a25f', -- PG-2026-015 Puregold Cogeo
   'c3022440-4e01-461c-a2ac-5947f6c4d57f', -- PG-2026-016 Puregold Masinag
   'e26bc3f1-f5c0-41f8-b3f3-73027d022372', -- PG-2026-017 Puregold Antipolo
   '2af0d99b-0944-4983-bedb-84d9185df40b', -- PG-2026-018 Puregold Teresa
   '4814e413-8269-4bfe-8b39-948415530357'  -- PG-2026-019 Puregold Tanay
 );

-- 5. Remove 28 Employee Store Allocations Created for the 4 Test Employees
DELETE FROM public.employee_store_allocations
 WHERE plantilla_id IN (
   '5f112278-9f3e-4614-8816-1f4274dad2ba', -- 0001-2026-0006 ROSALES
   '920a3000-c795-469a-aa83-93ee69833ae0', -- 0001-2026-0008 MENDOZA
   '8614041e-572a-489b-b0d4-1cfc57a48fa7', -- 0001-2026-0009 DELA CRUZ
   'fa2a1b73-23d5-432b-927c-44445ddbb7d8'  -- 0001-2026-0010 GARCIA
 );

-- 6. Remove 14 Plantilla Store Links for the 4 Test Employees
DELETE FROM public.plantilla_store_links
 WHERE plantilla_id IN (
   '5f112278-9f3e-4614-8816-1f4274dad2ba',
   '920a3000-c795-469a-aa83-93ee69833ae0',
   '8614041e-572a-489b-b0d4-1cfc57a48fa7',
   'fa2a1b73-23d5-432b-927c-44445ddbb7d8'
 );

-- 7. Remove Slot History for the 14 Test Store Slots
DELETE FROM public.slot_history
 WHERE slot_id IN (
   'bab87db4-b622-42b1-9c8b-47f748f3be54', -- PG-2026-006 Puregold Marikina
   '2d105ada-e45c-4a11-9bc1-4a10793ee3e7', -- PG-2026-007 Puregold Concepcion
   'bcbff80c-6600-4675-9185-518f3e7c7c1d', -- PG-2026-008 Puregold San Mateo
   'f346ce21-9cf1-4d2b-8704-652daec09b3b', -- PG-2026-009 Puregold Montalban
   '28ff30e5-bd74-44af-8b09-d36077101ac4', -- PG-2026-010 Puregold Nangka
   'a8489240-de78-4f0e-a8d9-3b39d20906e1', -- PG-2026-011 Puregold Ampid
   '3e3a0317-217b-4cfc-9699-399f8f66f8f0', -- PG-2026-012 Puregold Parang
   '67a653d6-9d64-4f4d-af2f-5e0460c3731d', -- PG-2026-013 Puregold Tumana
   '9c2baa98-ee90-4934-b2c6-d2ddc33386e2', -- PG-2026-014 Puregold Barangka
   'c4bd3c8f-623c-4cd0-b167-5faa20174c61', -- PG-2026-015 Puregold Cogeo
   'db5dadec-10ab-47a4-8dbe-9b57f54d0a54', -- PG-2026-016 Puregold Masinag
   '29cc7e74-ceef-44cf-a25f-108572547f24', -- PG-2026-017 Puregold Antipolo
   '0d16cf7b-54ac-4a1e-a5bb-ab1cc7580b38', -- PG-2026-018 Puregold Teresa
   '391644ff-7eaa-45ab-8d7d-0ca35578e07d'  -- PG-2026-019 Puregold Tanay
 );

-- 8. Remove the 14 Plantilla Slots for the Test Stores
DELETE FROM public.plantilla_slots
 WHERE id IN (
   'bab87db4-b622-42b1-9c8b-47f748f3be54',
   '2d105ada-e45c-4a11-9bc1-4a10793ee3e7',
   'bcbff80c-6600-4675-9185-518f3e7c7c1d',
   'f346ce21-9cf1-4d2b-8704-652daec09b3b',
   '28ff30e5-bd74-44af-8b09-d36077101ac4',
   'a8489240-de78-4f0e-a8d9-3b39d20906e1',
   '3e3a0317-217b-4cfc-9699-399f8f66f8f0',
   '67a653d6-9d64-4f4d-af2f-5e0460c3731d',
   '9c2baa98-ee90-4934-b2c6-d2ddc33386e2',
   'c4bd3c8f-623c-4cd0-b167-5faa20174c61',
   'db5dadec-10ab-47a4-8dbe-9b57f54d0a54',
   '29cc7e74-ceef-44cf-a25f-108572547f24',
   '0d16cf7b-54ac-4a1e-a5bb-ab1cc7580b38',
   '391644ff-7eaa-45ab-8d7d-0ca35578e07d'
 );

-- 9. Remove the 4 Test Employees from Public Plantilla
DELETE FROM public.plantilla
 WHERE id IN (
   '5f112278-9f3e-4614-8816-1f4274dad2ba', -- 0001-2026-0006
   '920a3000-c795-469a-aa83-93ee69833ae0', -- 0001-2026-0008
   '8614041e-572a-489b-b0d4-1cfc57a48fa7', -- 0001-2026-0009
   'fa2a1b73-23d5-432b-927c-44445ddbb7d8'  -- 0001-2026-0010
 );

-- 10. Remove the 14 Stores Directly (Bypasses trg_store_closure_cascade_vacancies)
DELETE FROM public.stores
 WHERE id IN (
   '0f65a5f4-31b3-4dfa-b980-0f988cbc20ca', -- PG-2026-006 Puregold Marikina
   'afca6519-9339-4456-8165-e6813c8d7c62', -- PG-2026-007 Puregold Concepcion
   'e291bc10-36ea-4107-a4a5-ff4fc896610f', -- PG-2026-008 Puregold San Mateo
   '9b96d306-3639-4662-8b7c-e0188701e487', -- PG-2026-009 Puregold Montalban
   '4f62ec44-cae5-4b93-8df2-fdda62ca987e', -- PG-2026-010 Puregold Nangka
   'c07cbe6f-0510-4634-bad8-6ec685631312', -- PG-2026-011 Puregold Ampid
   '178d59b5-0e47-4c69-9fd9-219448a2506a', -- PG-2026-012 Puregold Parang
   'aa8d940f-cc5b-44dd-bbd5-628b0779e831', -- PG-2026-013 Puregold Tumana
   'd5fc3d6a-2084-4229-b936-1ac471513660', -- PG-2026-014 Puregold Barangka
   '6fa88d8a-ebcb-411a-be70-f0b42e289408', -- PG-2026-015 Puregold Cogeo
   'b8f39701-f6a8-4f85-8bb3-6e814a610df2', -- PG-2026-016 Puregold Masinag
   'b0b7c76d-b6d5-473a-9ac0-ec048bc8405e', -- PG-2026-017 Puregold Antipolo
   '23214d0a-b91c-4d59-b346-c6ab0ea457f6', -- PG-2026-018 Puregold Teresa
   '08d8cde1-1c07-4736-b75f-2af73dce2b22'  -- PG-2026-019 Puregold Tanay
 );

-- ----------------------------------------------------------------------------
-- Verification SELECT: Confirm All Counts Exactly Match the BEFORE Baseline
-- ----------------------------------------------------------------------------
SELECT 
  (SELECT count(*) FROM public.stores WHERE account_id = '42a3cec9-a5eb-4c90-ac45-45669c212b12') AS stores_count,
  (SELECT count(*) FROM public.plantilla WHERE account_id = '42a3cec9-a5eb-4c90-ac45-45669c212b12') AS plantilla_count,
  (SELECT count(*) FROM public.plantilla_slots WHERE account_id = '42a3cec9-a5eb-4c90-ac45-45669c212b12') AS slots_count,
  (SELECT count(*) FROM public.employee_store_allocations esa JOIN public.plantilla p ON p.id = esa.plantilla_id WHERE p.account_id = '42a3cec9-a5eb-4c90-ac45-45669c212b12') AS allocations_count,
  (SELECT count(*) FROM public.plantilla_store_links psl JOIN public.plantilla p ON p.id = psl.plantilla_id WHERE p.account_id = '42a3cec9-a5eb-4c90-ac45-45669c212b12') AS links_count,
  (SELECT count(*) FROM public.vacancies v JOIN public.stores s ON s.id = v.store_id WHERE s.account_id = '42a3cec9-a5eb-4c90-ac45-45669c212b12') AS vacancies_count;
-- Expected output:
--   stores_count      : 5
--   plantilla_count   : 5
--   slots_count       : 5
--   allocations_count : 5
--   links_count       : 5
--   vacancies_count   : 0

COMMIT;
