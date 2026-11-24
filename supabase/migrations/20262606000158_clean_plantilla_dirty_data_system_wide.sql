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
DECLARE
  v_rommel_id uuid;
  v_batac_store_id uuid;
  v_alturas_acc_id uuid;
  v_alturas_grp_id uuid;
  v_created_by uuid;
BEGIN
  -- -------------------------------------------------------------------------
  -- 1. ALTURAS: Align Batac Ilocos (VCBPIG1_0165) & Rommel Abogado (2023-20605)
  -- -------------------------------------------------------------------------
  -- Dynamically resolve Rommel Abogado by employee_no (surrogate IDs vary across Staging and Prod)
  SELECT id INTO v_rommel_id FROM public.plantilla WHERE employee_no = '2023-20605' LIMIT 1;
  SELECT id, account_id, group_id INTO v_batac_store_id, v_alturas_acc_id, v_alturas_grp_id
  FROM public.stores WHERE vcode = 'VCBPIG1_0165' LIMIT 1;
  SELECT id INTO v_created_by FROM public.users_profile LIMIT 1;

  IF v_batac_store_id IS NOT NULL THEN
    -- Remove duplicate slot ordinal > 1 FIRST to avoid uq_plantilla_slots_active_occupant conflict
    DELETE FROM public.slot_history
    WHERE slot_id IN (
      SELECT id FROM public.plantilla_slots
      WHERE store_id = v_batac_store_id AND slot_ordinal > 1
    );

    DELETE FROM public.plantilla_slots
    WHERE store_id = v_batac_store_id AND slot_ordinal > 1;

    -- Bind slot ordinal 1 to Rommel Abogado if Rommel exists
    IF v_rommel_id IS NOT NULL THEN
      UPDATE public.plantilla_slots
      SET slot_status = 'occupied',
          current_occupant_plantilla_id = v_rommel_id,
          updated_at = NOW()
      WHERE store_id = v_batac_store_id AND slot_ordinal = 1;

      -- Insert the active store allocation for Rommel Abogado on Batac Ilocos if not already active
      IF NOT EXISTS (
        SELECT 1 FROM public.employee_store_allocations
        WHERE plantilla_id = v_rommel_id
          AND store_id = v_batac_store_id
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
          v_rommel_id,
          '2023-20605',
          NULL,
          v_batac_store_id,
          'VCBPIG1_0165',
          'BATAC ILOCOS',
          v_alturas_acc_id,
          v_alturas_grp_id,
          1.0000,
          1,
          '2026-11-05',
          NULL,
          true,
          'MON-SAT',
          '08:00 AM - 05:00 PM',
          NOW(),
          v_created_by
        );
      END IF;
    END IF;
  END IF;

  -- -------------------------------------------------------------------------
  -- 2. ACTISERVE: Super 8 Dau (VAC-MNL-099) & Festival Mall (ACT-G5-010)
  -- -------------------------------------------------------------------------
  -- Standardize Super 8 Dau slot status from 'filled' to 'occupied' (ADR-001/002)
  UPDATE public.plantilla_slots
  SET slot_status = 'occupied',
      updated_at = NOW()
  WHERE (legacy_vcode = 'VAC-MNL-099' OR store_id = (SELECT id FROM public.stores WHERE vcode = 'VAC-MNL-099' LIMIT 1))
    AND slot_status = 'filled';

  -- Back out ghost UAT candidate DELA CRUZ, JOHN PAUL DELOS REYES on Festival Mall
  UPDATE public.hr_emploc
  SET status = 'Backout',
      updated_at = NOW()
  WHERE (vcode = 'ACT-G5-010' AND applicant_name ILIKE '%DELA CRUZ%')
     OR id = '33da0ac2-8ad8-4d41-b806-41d0ec1c24ae';

  UPDATE public.applicants
  SET status = 'Backout',
      backout_reason = 'UAT test data cleanup (vacancy closed & archived)',
      updated_at = NOW()
  WHERE (vacancy_vcode = 'ACT-G5-010' AND last_name ILIKE '%DELA CRUZ%')
     OR id = 'b14c2abc-c3f6-4c3f-a561-22ba2c7128ca';

  -- Close slot ordinal 1 on ACT-G5-010 (Festival Mall is closed and archived)
  UPDATE public.plantilla_slots
  SET slot_status = 'closed',
      closed_at = NOW(),
      closure_reason_code = 'HC_REDUCTION',
      updated_at = NOW()
  WHERE (legacy_vcode = 'ACT-G5-010' OR store_id = (SELECT id FROM public.stores WHERE vcode = 'ACT-G5-010' LIMIT 1))
    AND slot_status != 'closed';

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
