-- Migration: 20262606000206_align_final_slot_and_vacancy_states.sql
-- Description: Align Final Slot and Vacancy States (ADR-001, ADR-002, ADR-003)

-- 1. Set Victor Moritte Sterling's slot on VDRG4_0002 to 'hr_processing' (Slot-First Rule 3)
UPDATE public.plantilla_slots
SET slot_status = 'hr_processing',
    updated_at = NOW()
WHERE id = 'c8618941-2b72-4349-b33f-07bcd08ef426';

-- 2. Archive Vacancy for Ali Mall (ACT-G5-008) whose store is archived and slots closed
UPDATE public.vacancies
SET status = 'Archived',
    is_archived = true,
    updated_at = NOW()
WHERE vcode = 'ACT-G5-008'
  AND (is_archived = false OR is_archived IS NULL);
