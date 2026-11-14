-- Migration: 20262606000109_reconcile_forever_office_borillo_slot.sql
-- Description: Reconcile VCode, slot occupancy, and store allocation for Fred Richard Borillo (2021-11468)
--              deployed to SMCO KAWIT under FOREVER OFFICE account.
--              Resolves discrepancy between Account Card (7 vacant) and Inside Tab 3 (6 vacant)
--              by aligning Borillo's vcode from CPRVJV13 to CPSMJV21, binding 1 SMCO KAWIT slot,
--              and restoring visibility of DIVIMART GENERAL TRIAS (CPRVJV13) in Tab 3 Vacancy.

DO $$
BEGIN
  -- 1. Reconcile employee Borillo's vcode in public.plantilla
  UPDATE public.plantilla
  SET vcode = 'CPSMJV21',
      updated_at = now()
  WHERE id = '9d908f13-2496-41f1-a881-d5a2a0ec7057'
    AND employee_no = '2021-11468';

  -- 2. Bind SMCO KAWIT slot 1 in public.plantilla_slots to Borillo
  UPDATE public.plantilla_slots
  SET slot_status = 'occupied',
      current_occupant_plantilla_id = '9d908f13-2496-41f1-a881-d5a2a0ec7057',
      updated_at = now()
  WHERE id = 'ee1cb318-c3d2-4232-9979-2378a005cd8e'
    AND legacy_vcode = 'CPSMJV21'
    AND slot_status = 'open';

  -- 3. Insert active allocation in employee_store_allocations for SMCO KAWIT if not existing
  IF NOT EXISTS (
    SELECT 1 FROM public.employee_store_allocations
    WHERE plantilla_id = '9d908f13-2496-41f1-a881-d5a2a0ec7057'
      AND store_id = '6c367b89-494d-4918-83b5-8c4d151b1f54'
      AND is_active = true
  ) THEN
    INSERT INTO public.employee_store_allocations (
      plantilla_id,
      employee_no,
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
      created_at
    ) VALUES (
      '9d908f13-2496-41f1-a881-d5a2a0ec7057',
      '2021-11468',
      '6c367b89-494d-4918-83b5-8c4d151b1f54',
      'CPSMJV21',
      'SMCO KAWIT',
      'd0533fbc-3cce-4d0a-a619-ad0539dbc66d',
      '4de2971c-49fb-45be-98c8-4fe1246382b3',
      1.0000,
      1,
      '2026-11-06',
      NULL,
      true,
      'MON-SAT',
      '08:00 AM - 05:00 PM',
      now()
    );
  END IF;
END $$;
