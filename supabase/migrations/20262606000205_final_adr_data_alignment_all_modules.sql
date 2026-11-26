-- Migration: 20262606000205_final_adr_data_alignment_all_modules.sql
-- Description: Final ADR Data Alignment across All Modules (ADR-001, ADR-002, ADR-003, ADR-004)
-- Enforces 100% resolution of remaining data alignment items.

-- ==================================================================
-- 1. PLANTILLA: Disambiguate Generic Store Names to enforce 1 Store = 1 VCODE (ADR-001 Invariant 2)
-- ==================================================================
-- Generic names (e.g. 'WAREHOUSE', 'ADDITIONAL', 'SAN PABLO') shared by multiple distinct VCodes
-- within the same account violate 1 Store = 1 VCODE. Disambiguate with canonical (VCODE) suffix.
WITH ranked_stores AS (
  SELECT id, account_id, store_name, vcode,
         ROW_NUMBER() OVER (PARTITION BY account_id, store_name ORDER BY created_at ASC, id ASC) as rn
  FROM public.stores
  WHERE is_archived = false OR is_archived IS NULL
)
UPDATE public.stores st
SET store_name = st.store_name || ' (' || st.vcode || ')',
    updated_at = NOW()
FROM ranked_stores r
WHERE st.id = r.id AND r.rn > 1;

-- ==================================================================
-- 2. VACANCY & SLOTS: Close Excess Open Slots on Filled/Archived Vacancies (ADR-002)
-- ==================================================================
-- A. Close open slots on ACT-G5-002 (Filled & Archived requisition)
UPDATE public.plantilla_slots
SET slot_status = 'closed',
    closed_at = NOW(),
    closure_reason_code = 'HC_REDUCTION',
    updated_at = NOW()
WHERE id IN ('8f7b289c-780b-433c-a7c0-01a9837eef26', 'bb6bbac5-e1dd-4356-8b90-0e3088779e19', '3a8a9cc6-b8ac-4de2-8e12-a8a6179f48e9')
  AND slot_status = 'open';

-- B. Close excess open slots on TEST001 and VPSMG3_0004 (required_headcount = 1)
UPDATE public.plantilla_slots
SET slot_status = 'closed',
    closed_at = NOW(),
    closure_reason_code = 'HC_REDUCTION',
    updated_at = NOW()
WHERE id IN ('06d5012d-7f62-4b0a-9b92-519223175e76', 'a2443bd5-1e3d-421d-9ffe-e3bec87661ba')
  AND slot_status = 'open';

-- C. Close 3 open slots on archived store Ali Mall (ACT-G5-008)
UPDATE public.plantilla_slots
SET slot_status = 'closed',
    closed_at = NOW(),
    closure_reason_code = 'STORE_CLOSED',
    updated_at = NOW()
WHERE store_id = '20bbbb33-3cf4-41c8-82fd-a4d71f6779b9'
  AND slot_status = 'open';

-- D. Transition Confirmed Onboard candidates who are active in Plantilla to 'Hired' status
UPDATE public.applicants a
SET status = 'Hired',
    updated_at = NOW()
FROM public.plantilla p
WHERE p.employee_name = a.full_name
  AND p.status = 'Active'
  AND a.status = 'Confirmed Onboard'
  AND a.is_archived = false;

-- ==================================================================
-- 3. HR EMPLOC: Provision & Link Slot for Victor Moritte Sterling (ADR-003)
-- ==================================================================
DO $$
DECLARE
  v_store_id uuid;
  v_account_id uuid;
  v_slot_id uuid;
  v_max_ordinal integer;
BEGIN
  SELECT id, account_id INTO v_store_id, v_account_id
  FROM public.stores
  WHERE vcode = 'VDRG4_0002'
  LIMIT 1;

  IF v_store_id IS NOT NULL THEN
    -- Check if an open slot exists
    SELECT id INTO v_slot_id
    FROM public.plantilla_slots
    WHERE store_id = v_store_id AND slot_status = 'open'
    ORDER BY slot_ordinal ASC
    LIMIT 1;

    -- If no open slot, provision one
    IF v_slot_id IS NULL THEN
      SELECT COALESCE(MAX(slot_ordinal), 0) INTO v_max_ordinal
      FROM public.plantilla_slots
      WHERE store_id = v_store_id;

      INSERT INTO public.plantilla_slots (
        store_id, account_id, position, employment_type, is_roving,
        slot_status, slot_ordinal, created_at, updated_at
      ) VALUES (
        v_store_id,
        v_account_id,
        'Merchandiser',
        'stationary',
        false,
        'open',
        v_max_ordinal + 1,
        NOW(),
        NOW()
      ) RETURNING id INTO v_slot_id;
    END IF;

    -- Link Victor to this slot
    UPDATE public.hr_emploc
    SET slot_id = v_slot_id,
        store_id = v_store_id,
        updated_at = NOW()
    WHERE id = '2c36af9d-d231-400c-a298-6f8f09d75b89';
  END IF;
END $$;
