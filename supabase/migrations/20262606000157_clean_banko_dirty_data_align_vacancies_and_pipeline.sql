-- Migration: 20262606000157_clean_banko_dirty_data_align_vacancies_and_pipeline.sql
-- Purpose: Remediate BANKO dirty data, align pipeline and vacant counters per Option 1:
-- 1. Back out ghost test applicant Cruz, James Paul (UAT Test 3 remnant) in hr_emploc & applicants.
-- 2. Release slot ordinal 1 on TEST011 (SUPER 11) from hr_processing to open.
-- 3. Delete orphan duplicate slot ordinal 2 on TEST011 (SUPER 11) and its slot_history entries.
-- 4. Unarchive and reopen TEST011 (SUPER 11) vacancy (is_archived = false, status = 'Open').
-- 5. Unarchive and reopen TEST009 (SUPER 9) vacancy (is_archived = false, status = 'Open').
-- 6. Safely archive 6 empty orphan test stores in BANKO having 0 allocations, 0 slots, and 0 vacancies.

-- Temporarily enable admin lock override to permit data alignment during scheduled lock window
UPDATE public.vacancy_edit_locks
SET is_override_active = true
WHERE id = 1;

-- §1. Back out ghost test applicant Cruz, James Paul on TEST011 (SUPER 11)
UPDATE public.hr_emploc
SET
  status = 'Backout',
  deleted_at = now(),
  backout_at = now(),
  backout_reason_code = 'UAT_CLEANUP',
  backout_details = 'UAT test data cleanup per Option 1',
  updated_at = now()
WHERE id = '9179d135-aa30-4bc5-8748-59bf3e2756e3'
  AND account_id = 'f26cc270-bac3-4a5b-b656-1bad68619a73';

UPDATE public.applicants
SET
  status = 'Backout',
  backout_date = CURRENT_DATE,
  backout_reason_code = 'UAT_CLEANUP',
  backout_details = 'UAT test data cleanup per Option 1',
  updated_at = now()
WHERE id = '0f7188f3-1061-4bdb-8ba4-7595d6ea0acb';

-- §2. Release slot ordinal 1 on TEST011 (SUPER 11) from hr_processing to open
UPDATE public.plantilla_slots
SET
  slot_status = 'open',
  current_occupant_plantilla_id = NULL,
  updated_at = now()
WHERE id = 'feb12c22-8bab-4937-a7c7-27551fabab89'
  AND legacy_vcode = 'TEST011'
  AND slot_ordinal = 1;

-- §3. Remove orphan duplicate slot ordinal 2 on TEST011 (SUPER 11) and its slot_history entries
DELETE FROM public.slot_history
WHERE slot_id = '07996fd0-cd2a-41ad-9f9a-b724dcae48e7';

DELETE FROM public.plantilla_slots
WHERE id = '07996fd0-cd2a-41ad-9f9a-b724dcae48e7'
  AND legacy_vcode = 'TEST011'
  AND slot_ordinal = 2;

-- §4. Unarchive and reopen TEST011 (SUPER 11) vacancy
UPDATE public.vacancies
SET
  status = 'Open',
  is_archived = false,
  archived_at = NULL,
  archive_reason = NULL,
  required_headcount = 1.0000,
  updated_at = now()
WHERE id = '13616e2a-ff30-4f42-99bd-4ab8354a83d8'
  AND vcode = 'TEST011'
  AND account_id = 'f26cc270-bac3-4a5b-b656-1bad68619a73';

-- §5. Unarchive and reopen TEST009 (SUPER 9) vacancy
UPDATE public.vacancies
SET
  status = 'Open',
  is_archived = false,
  archived_at = NULL,
  archive_reason = NULL,
  required_headcount = 1.0000,
  updated_at = now()
WHERE id = 'b4598967-892d-4916-ad30-e1e3dbe31197'
  AND vcode = 'TEST009'
  AND account_id = 'f26cc270-bac3-4a5b-b656-1bad68619a73';

-- §6. Safely archive 6 empty orphan test stores in BANKO
UPDATE public.stores
SET
  is_active = false,
  status = 'archived',
  is_archived = true,
  archived_at = COALESCE(archived_at, now()),
  updated_at = now()
WHERE account_id = 'f26cc270-bac3-4a5b-b656-1bad68619a73'
  AND id IN (
    '0e265f68-d096-4cf6-89a2-bec73eb83d40', -- PG-DAU-001 (SUPER 8 DAU)
    'f93aac10-7093-480d-82c8-7a92ac3628bd', -- PG-SF-001 (PUREGOLD SAN FERNANDO)
    '3a9d495b-6ffc-4858-9472-a8d0eea01b08', -- PG-SF-002 (SM DAU)
    '6bae01bd-f506-4257-a75a-2aff048bd4de', -- PG-SF-003 (SM DAU 2)
    'a479330f-91d6-41a3-b136-133a5a7e84b9', -- SM BALBALAN
    '80b68666-7ac6-496b-a458-26dea4cc1770'  -- SM TABUK
  );

-- Restore vacancy edit lock override state
UPDATE public.vacancy_edit_locks
SET is_override_active = false
WHERE id = 1;
