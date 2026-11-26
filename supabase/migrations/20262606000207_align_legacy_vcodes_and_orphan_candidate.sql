-- Migration: 20262606000207_align_legacy_vcodes_and_orphan_candidate.sql
-- Created: 2026-11-26T14:11:23.792Z
-- Description: align legacy vcodes and orphan candidate

BEGIN;

-- 1. Ensure foreign keys on vacancies(vcode) cascade on update (NOT VALID to preserve performance and avoid rechecking legacy data)
ALTER TABLE public.applicants
  DROP CONSTRAINT IF EXISTS fk_applicants_vacancy_vcode,
  ADD CONSTRAINT fk_applicants_vacancy_vcode
    FOREIGN KEY (vacancy_vcode) REFERENCES public.vacancies(vcode) ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE public.vacancy_closure_requests
  DROP CONSTRAINT IF EXISTS vacancy_closure_requests_vacancy_vcode_fkey,
  ADD CONSTRAINT vacancy_closure_requests_vacancy_vcode_fkey
    FOREIGN KEY (vacancy_vcode) REFERENCES public.vacancies(vcode) ON UPDATE CASCADE NOT VALID;

ALTER TABLE public.headcount_requests
  DROP CONSTRAINT IF EXISTS headcount_requests_target_vcode_fkey,
  ADD CONSTRAINT headcount_requests_target_vcode_fkey
    FOREIGN KEY (target_vcode) REFERENCES public.vacancies(vcode) ON UPDATE CASCADE NOT VALID;

ALTER TABLE public.headcount_quota_revisions
  DROP CONSTRAINT IF EXISTS headcount_quota_revisions_vcode_fkey,
  ADD CONSTRAINT headcount_quota_revisions_vcode_fkey
    FOREIGN KEY (vcode) REFERENCES public.vacancies(vcode) ON UPDATE CASCADE NOT VALID;

-- 2. Archive orphan candidate Alexa B Mae (no valid vacancy / store)
UPDATE public.applicants
SET is_archived = true,
    status = 'Withdrawn',
    archived_at = COALESCE(archived_at, NOW()),
    slot_id = NULL
WHERE id = '62dedd3a-7e21-4518-b3b4-90f89f845153';

-- 3. Align CPSEJV16 (SUPER 8 ROSARIO CAVITE, store_id = '75f32a67-b626-481e-9321-1b4f7be893b7')
UPDATE public.vacancies SET vcode = 'CPSEJV16' WHERE vcode = 'VCFG1_0010';
UPDATE public.plantilla SET vcode = 'CPSEJV16' WHERE store_id = '75f32a67-b626-481e-9321-1b4f7be893b7' AND vcode = 'VCFG1_0010';
UPDATE public.hr_emploc SET vcode = 'CPSEJV16' WHERE store_id = '75f32a67-b626-481e-9321-1b4f7be893b7' AND vcode = 'VCFG1_0010';
UPDATE public.plantilla_slots
SET slot_ordinal = 2, legacy_vcode = 'CPSEJV16'
WHERE id = 'f06011fb-5c4f-446e-a5ee-c5a8a0dd5813';

-- 4. Align VCBPIG1_0252 (CALAMBA MISAMIS OCCIDENTAL, store_id = '2d7c578b-978c-4ff3-8162-f16214a06ed0')
UPDATE public.vacancies SET vcode = 'VCBPIG1_0252' WHERE vcode = 'VCAG2_0029';
UPDATE public.plantilla SET vcode = 'VCBPIG1_0252' WHERE store_id = '2d7c578b-978c-4ff3-8162-f16214a06ed0' AND vcode = 'VCAG2_0029';
UPDATE public.hr_emploc SET vcode = 'VCBPIG1_0252' WHERE store_id = '2d7c578b-978c-4ff3-8162-f16214a06ed0' AND vcode = 'VCAG2_0029';
UPDATE public.plantilla_slots
SET slot_ordinal = 2, legacy_vcode = 'VCBPIG1_0252'
WHERE id = '26de05ac-e690-4ee4-9e18-71b2313649da';

-- 5. Align VCAG5_0068 (SM AURORA, store_id = '71178681-9782-42cc-80e6-a4901d78f542')
UPDATE public.vacancies SET vcode = 'VCAG5_0068' WHERE vcode = 'VCAG5_0056';
UPDATE public.plantilla SET vcode = 'VCAG5_0068' WHERE store_id = '71178681-9782-42cc-80e6-a4901d78f542' AND vcode = 'VCAG5_0056';
UPDATE public.hr_emploc SET vcode = 'VCAG5_0068' WHERE store_id = '71178681-9782-42cc-80e6-a4901d78f542' AND vcode = 'VCAG5_0056';
UPDATE public.plantilla_slots
SET legacy_vcode = 'VCAG5_0068'
WHERE store_id = '71178681-9782-42cc-80e6-a4901d78f542' AND legacy_vcode = 'VCAG5_0056';

-- 6. Merge VCBG4_0001 -> VBFG5_0009 (GERONA & CONCEPCION-9, store_id = '43fe9bc5-4127-42ab-82c0-1e54bdfbae6b')
UPDATE public.applicants SET vacancy_vcode = 'VBFG5_0009' WHERE vacancy_vcode = 'VCBG4_0001';
UPDATE public.plantilla_slots
SET slot_ordinal = 4, legacy_vcode = 'VBFG5_0009'
WHERE id = 'c878a9f8-ae46-4a0f-a900-a6734ca8591a';
UPDATE public.plantilla_slots
SET slot_ordinal = 5, legacy_vcode = 'VBFG5_0009'
WHERE id = '24cb9101-f605-4b4d-84f8-9cdc7edcf2a0';
UPDATE public.plantilla SET vcode = 'VBFG5_0009', vacancy_id = '2b09a152-0975-4e52-9035-2d8bbff75bac' WHERE store_id = '43fe9bc5-4127-42ab-82c0-1e54bdfbae6b' AND vcode = 'VCBG4_0001';
UPDATE public.hr_emploc SET vcode = 'VBFG5_0009', vacancy_id = '2b09a152-0975-4e52-9035-2d8bbff75bac' WHERE vacancy_id = 'eec7b57c-a564-449c-8735-041671af035c';
UPDATE public.vacancies
SET status = 'Open',
    is_archived = false,
    required_headcount = 2.0000
WHERE id = '2b09a152-0975-4e52-9035-2d8bbff75bac';
DELETE FROM public.vacancies WHERE id = 'eec7b57c-a564-449c-8735-041671af035c';

-- 7. Merge VCTG2_0006 -> VCAPG2_0010 (ASENSO PINOY HEAD OFFICE, store_id = '0664a588-a00f-41d8-9db4-414c04d14c64')
UPDATE public.applicants SET vacancy_vcode = 'VCAPG2_0010' WHERE vacancy_vcode = 'VCTG2_0006';
UPDATE public.plantilla_slots
SET slot_ordinal = 2, legacy_vcode = 'VCAPG2_0010'
WHERE id = 'd5f7fabb-7148-4593-8e59-ddb54d397d99';
UPDATE public.plantilla_slots
SET slot_ordinal = 3, legacy_vcode = 'VCAPG2_0010'
WHERE id = '067f9047-a765-455d-ba0c-812358c0b650';
UPDATE public.plantilla_slots
SET slot_ordinal = 4, legacy_vcode = 'VCAPG2_0010'
WHERE id = '0d815bf2-2501-4e2d-a2c3-cff3ad045606';
UPDATE public.plantilla SET vcode = 'VCAPG2_0010', vacancy_id = '13b8da5f-698b-467e-8e6e-ae8c7eb472f4' WHERE store_id = '0664a588-a00f-41d8-9db4-414c04d14c64' AND vcode = 'VCTG2_0006';
UPDATE public.hr_emploc SET vcode = 'VCAPG2_0010', vacancy_id = '13b8da5f-698b-467e-8e6e-ae8c7eb472f4' WHERE vacancy_id = 'f29987a9-25e5-432a-8c62-72d8ca768719';
UPDATE public.vacancies
SET status = 'Open',
    is_archived = false,
    required_headcount = 3.0000
WHERE id = '13b8da5f-698b-467e-8e6e-ae8c7eb472f4';
DELETE FROM public.vacancies WHERE id = 'f29987a9-25e5-432a-8c62-72d8ca768719';

COMMIT;
