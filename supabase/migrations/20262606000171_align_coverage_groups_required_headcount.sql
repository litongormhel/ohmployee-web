-- Migration: 20262606000171_align_coverage_groups_required_headcount.sql
-- Created: 2026-11-24T10:44:20.601Z
-- Description: Align coverage groups required headcount from 0 to canonical 1 for active/open roving groups

BEGIN;

-- 1. Align active and open coverage groups with 0 required_headcount to canonical minimum of 1
UPDATE public.coverage_groups
SET required_headcount = 1
WHERE required_headcount = 0
  AND status IN ('open', 'filled');

-- 2. Explicitly ensure CG-FG1-0005 has required_headcount = 1 and status = 'open'
UPDATE public.coverage_groups
SET required_headcount = 1,
    status = 'open'
WHERE id = 'e29f9754-2ba2-42ee-a492-c295a2e15f45';

-- 3. Ensure member store plantilla slots are tagged as roving
UPDATE public.plantilla_slots
SET is_roving = true,
    employment_type = 'Roving',
    updated_at = now()
WHERE store_id IN (
  '1af2ef9f-0f34-4f3b-a24d-29ef160a7251',
  '3aa03441-9f15-4ff4-98a2-9be43fe65d2a'
)
AND (is_roving IS NOT TRUE OR employment_type <> 'Roving');

COMMIT;
