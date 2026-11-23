-- Migration: 20262606000148_cleanup_banko_orphan_coverage_groups.sql
-- Purpose: Data cleanup for test coverage groups in BANKO and store headcount alignment
-- 1. Archive test coverage groups CG-BG1-0002 and CG-BG1-0003 (created with 0 required headcount during UAT)
-- 2. Archive associated coverage_group_stores
-- 3. Align TEST011 (SUPER 11) required_headcount from 2.0000 back to canonical 1.0000
-- 4. Mark TEST009 (SUPER 9) vacancy as 'Filled' since active employee (Kimi Antonelli) is already deployed

-- 1. Archive orphan coverage groups in BANKO
UPDATE public.coverage_groups
SET 
  status = 'archived',
  is_archived = true,
  archived_at = COALESCE(archived_at, now()),
  archive_reason = 'Cleanup test coverage group with 0 required headcount'
WHERE account_id = 'f26cc270-bac3-4a5b-b656-1bad68619a73'
  AND coverage_code IN ('CG-BG1-0002', 'CG-BG1-0003');

-- 2. Archive member stores in coverage_group_stores
UPDATE public.coverage_group_stores
SET 
  is_archived = true,
  archived_at = COALESCE(archived_at, now())
WHERE coverage_group_id IN (
  SELECT id FROM public.coverage_groups
  WHERE account_id = 'f26cc270-bac3-4a5b-b656-1bad68619a73'
    AND coverage_code IN ('CG-BG1-0002', 'CG-BG1-0003')
);

-- Temporarily bypass vacancy lock trigger for administrative alignment
ALTER TABLE public.vacancies DISABLE TRIGGER trg_assert_vacancy_edit_allowed;

-- 3. Align TEST011 (SUPER 11) required_headcount to 1.0000
UPDATE public.vacancies
SET required_headcount = 1.0000
WHERE vcode = 'TEST011'
  AND account_id = 'f26cc270-bac3-4a5b-b656-1bad68619a73'
  AND required_headcount = 2.0000;

-- 4. Mark TEST009 (SUPER 9) vacancy as 'Filled' (active employee Kimi Antonelli is deployed)
UPDATE public.vacancies
SET status = 'Filled'
WHERE id = 'b4598967-892d-4916-ad30-e1e3dbe31197'
  AND vcode = 'TEST009'
  AND account_id = 'f26cc270-bac3-4a5b-b656-1bad68619a73'
  AND status = 'Open';

ALTER TABLE public.vacancies ENABLE TRIGGER trg_assert_vacancy_edit_allowed;
