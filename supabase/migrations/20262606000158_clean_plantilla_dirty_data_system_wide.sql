-- Migration: 20262606000158_clean_plantilla_dirty_data_system_wide.sql
-- Description: Clean system-wide dirty data across Plantilla, Slots, Vacancies, and Stores.
-- 1. ALTURAS: Insert missing active allocation for Rommel Abogado (BATAC ILOCOS, VCBPIG1_0165),
--    remove duplicate slot ordinal 2, and bind slot ordinal 1 to Rommel.
-- 2. ACTISERVE: Standardize VAC-MNL-099 (Super 8 Dau) slot status to 'occupied'.
--    Back out ghost UAT candidate DELA CRUZ, JOHN PAUL DELOS REYES on archived vacancy ACT-G5-010 (Festival Mall)
--    and close slot ordinal 1.
-- 3. FOREVER OFFICE & ALTURAS: Close orphan open slots on fulfilled/rolled-back stores (CPSAJV31, VCBPIG1_0849, VCBPIG1_0850).
-- 4. Clean up 33 empty orphan test stores (0 allocations, 0 slots, 0 vacancies).

-- Enable temporary override for scheduled vacancy edit lock during migration
UPDATE public.vacancy_edit_locks SET is_override_active = true WHERE id = 1;

DO $$
BEGIN
  -- -------------------------------------------------------------------------
  -- 1. ALTURAS: Align Batac Ilocos (VCBPIG1_0165) & Rommel Abogado (2023-20605)
  -- -------------------------------------------------------------------------
  -- Remove duplicate slot ordinal 2 FIRST to avoid uq_plantilla_slots_active_occupant conflict
  DELETE FROM public.slot_history WHERE slot_id = '298e075f-285b-4e68-8d98-f045f6e884b8';
  DELETE FROM public.plantilla_slots WHERE id = '298e075f-285b-4e68-8d98-f045f6e884b8';

  -- Bind slot ordinal 1 to Rommel Abogado
  UPDATE public.plantilla_slots
  SET slot_status = 'occupied',
      current_occupant_plantilla_id = 'ae65a38a-34a5-46f9-b8fb-f7bcadaf8fd1',
      updated_at = NOW()
  WHERE id = 'd0af1a89-3e02-41b6-9580-c5fd50cc65fa';

  -- Insert the active store allocation for Rommel Abogado on Batac Ilocos if not already active
  IF NOT EXISTS (
    SELECT 1 FROM public.employee_store_allocations
    WHERE plantilla_id = 'ae65a38a-34a5-46f9-b8fb-f7bcadaf8fd1'
      AND store_id = '3ce6612b-a866-4ac3-b7f9-cae509ba3d87'
      AND is_active = true
  ) THEN
    INSERT INTO public.employee_store_allocations (
      plantilla_id,
      employee_no,
      roving_group_id,
      store_id,
      vcode,
      store_name,
      account_id,
      group_id,
      filled_hc,
      active_store_count,
      effective_start,
      effective_end,
      is_active,
      schedule_days,
      schedule_time,
      created_at,
      created_by
    ) VALUES (
      'ae65a38a-34a5-46f9-b8fb-f7bcadaf8fd1',
      '2023-20605',
      NULL,
      '3ce6612b-a866-4ac3-b7f9-cae509ba3d87',
      'VCBPIG1_0165',
      'BATAC ILOCOS',
      '3126b9a8-29a6-4917-8b49-82e937d7cf88',
      '638c038a-ba76-484f-aff8-1947c9a6b0b7',
      1.0000,
      1,
      '2026-11-05',
      NULL,
      true,
      'MON-SAT',
      '08:00 AM - 05:00 PM',
      NOW(),
      'b865eef6-ebac-4bd3-84b5-482c00774565'
    );
  END IF;

  -- -------------------------------------------------------------------------
  -- 2. ACTISERVE: Super 8 Dau (VAC-MNL-099) & Festival Mall (ACT-G5-010)
  -- -------------------------------------------------------------------------
  -- Standardize Super 8 Dau slot status from 'filled' to 'occupied' (ADR-001/002)
  UPDATE public.plantilla_slots
  SET slot_status = 'occupied',
      updated_at = NOW()
  WHERE id = '3a8a9cc6-b8ac-4de2-8e12-a8a6179f48e9';

  -- Back out ghost UAT candidate DELA CRUZ, JOHN PAUL DELOS REYES on Festival Mall
  UPDATE public.hr_emploc
  SET status = 'Backout',
      updated_at = NOW()
  WHERE id = '33da0ac2-8ad8-4d41-b806-41d0ec1c24ae';

  UPDATE public.applicants
  SET status = 'Backout',
      backout_reason = 'UAT test data cleanup (vacancy closed & archived)',
      updated_at = NOW()
  WHERE id = 'b14c2abc-c3f6-4c3f-a561-22ba2c7128ca';

  -- Close slot ordinal 1 on ACT-G5-010 (Festival Mall is closed and archived)
  UPDATE public.plantilla_slots
  SET slot_status = 'closed',
      closed_at = NOW(),
      closure_reason_code = 'HC_REDUCTION',
      updated_at = NOW()
  WHERE id = '8eb14b17-b2e2-42c5-8aba-4b93782c08a3';

  -- -------------------------------------------------------------------------
  -- 3. Leftover Slots: Rolled-back batch slots & fulfilled coverage store slot
  -- -------------------------------------------------------------------------
  -- Close leftover open slots from rolled-back batch OHM2026_0075 smoke test
  UPDATE public.plantilla_slots
  SET slot_status = 'closed',
      closed_at = NOW(),
      closure_reason_code = 'IMPORT_ROLLBACK',
      is_archived = true,
      archived_at = NOW(),
      updated_at = NOW()
  WHERE legacy_vcode IN ('VCBPIG1_0849', 'VCBPIG1_0850')
    AND slot_status = 'open'
    AND current_occupant_plantilla_id IS NULL;

  -- Close open slot for Emilus Rosario (CPSAJV31), fulfilled by coverage group CG-FG1-0004
  UPDATE public.plantilla_slots
  SET slot_status = 'closed',
      closed_at = NOW(),
      closure_reason_code = 'COVERAGE_STORE_ADDED',
      updated_at = NOW()
  WHERE legacy_vcode = 'CPSAJV31'
    AND slot_status = 'open'
    AND current_occupant_plantilla_id IS NULL;

  -- -------------------------------------------------------------------------
  -- 4. Clean up 33 Empty Test Stores (0 allocations, 0 slots, 0 vacancies)
  -- -------------------------------------------------------------------------
  UPDATE public.stores
  SET is_active = false,
      is_archived = true,
      archived_at = NOW(),
      updated_at = NOW()
  WHERE is_active = true
    AND NOT EXISTS (
      SELECT 1 FROM public.employee_store_allocations esa WHERE esa.store_id = stores.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.plantilla_slots ps WHERE ps.store_id = stores.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.vacancies v WHERE v.vcode = stores.vcode AND v.deleted_at IS NULL
    );

END $$;

-- Restore scheduled vacancy edit lock override
UPDATE public.vacancy_edit_locks SET is_override_active = false WHERE id = 1;
