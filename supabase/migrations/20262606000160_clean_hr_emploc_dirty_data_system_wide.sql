-- ============================================================
-- Migration: 20262606000160_clean_hr_emploc_dirty_data_system_wide.sql
-- Description: System-Wide HR Emploc Dirty Data Cleanup
--
-- Actions:
--   1. Fix Queue Leak for Backout Candidate:
--      Set hr_status = 'Rejected' on DELA CRUZ, JOHN PAUL DELOS REYES
--      (ACTISERVE, ACT-G5-010) whose status is 'Backout' so they no longer
--      clog the operational Correction queue.
--
--   2. Align Slot Status for Active Onboarding:
--      Update slot (FOREVER OFFICE, CPSAJV27) from 'open' to 'hr_processing',
--      matching the active onboarding state of candidate AL, JAMES N/A.
--
--   3. Provision Roving Slots for Active Roving Candidates with NULL slot_id:
--      Per ADR-003 Rule 3, every HR Emploc record must link to a valid Plantilla Slot.
--      Provision physical roving slots (store_id IS NULL, is_roving = true, slot_status = 'hr_processing')
--      and link them dynamically:
--        a. CHI, JOHN REY LIM (BOUNTY, COM-00005, COMMANDO)
--        b. UY, ANNA ROLDAN (ACTISERVE, BUN-GHQ-00015, Bundler)
--        c. REID, JAMES CRUZ (Moses HQ, SEA-00006, RELIEVER)
-- ============================================================

DO $$
DECLARE
  v_slot_bounty uuid;
  v_slot_actiserve uuid;
  v_slot_moses uuid;
  v_bounty_acc uuid;
  v_bounty_grp uuid;
  v_actiserve_acc uuid;
  v_actiserve_grp uuid;
  v_moses_acc uuid;
  v_moses_grp uuid;
  v_ord int;
BEGIN
  -- Dynamically resolve account and group IDs by natural name or fallback ID
  SELECT id, group_id INTO v_bounty_acc, v_bounty_grp 
  FROM public.accounts 
  WHERE account_name = 'BOUNTY' OR id = '0079b8d2-6f09-4508-85cf-5c510ea145a9' 
  LIMIT 1;

  SELECT id, group_id INTO v_actiserve_acc, v_actiserve_grp 
  FROM public.accounts 
  WHERE account_name = 'ACTISERVE' OR id = '4fba7c47-f19e-47fb-9074-6acab754721f' 
  LIMIT 1;

  SELECT id, group_id INTO v_moses_acc, v_moses_grp 
  FROM public.accounts 
  WHERE account_name ILIKE '%Moses%' OR id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152' 
  LIMIT 1;

  -- 1. Fix Queue Leak: Set hr_status = 'Rejected' on backed-out candidate
  UPDATE public.hr_emploc
  SET hr_status = 'Rejected',
      updated_at = now()
  WHERE (id = '33da0ac2-8ad8-4d41-b806-41d0ec1c24ae' OR (vcode = 'ACT-G5-010' AND applicant_name ILIKE '%DELA CRUZ%'))
    AND status = 'Backout'
    AND hr_status = 'For Correction';

  -- 2. Align Slot Status for Active Onboarding in FOREVER OFFICE
  UPDATE public.plantilla_slots
  SET slot_status = 'hr_processing',
      updated_at = now()
  WHERE (id = '09b9192d-f6c9-489e-b5d8-7b9957d1d9dd' OR legacy_vcode = 'CPSAJV27')
    AND slot_status = 'open';

  -- 3. Provision roving slot for BOUNTY (COM-00005, John Rey Lim Chi)
  IF EXISTS (SELECT 1 FROM public.hr_emploc WHERE (id = '8dbe41ad-67e3-4873-92cd-b46645c568e4' OR vcode = 'COM-00005') AND slot_id IS NULL AND deleted_at IS NULL) THEN
    SELECT coalesce(max(slot_ordinal), 0) + 1 INTO v_ord
    FROM public.plantilla_slots
    WHERE account_id = v_bounty_acc AND store_id IS NULL;

    INSERT INTO public.plantilla_slots (
      account_id,
      group_id,
      store_id,
      position,
      employment_type,
      is_roving,
      slot_ordinal,
      slot_status,
      created_at,
      updated_at
    ) VALUES (
      v_bounty_acc,
      v_bounty_grp,
      NULL,
      'COMMANDO',
      'commando',
      true,
      v_ord,
      'hr_processing',
      now(),
      now()
    ) RETURNING id INTO v_slot_bounty;

    UPDATE public.hr_emploc
    SET slot_id = v_slot_bounty,
        updated_at = now()
    WHERE (id = '8dbe41ad-67e3-4873-92cd-b46645c568e4' OR vcode = 'COM-00005')
      AND slot_id IS NULL;
  END IF;

  -- 4. Provision roving slot for ACTISERVE (BUN-GHQ-00015, Anna Roldan Uy)
  IF EXISTS (SELECT 1 FROM public.hr_emploc WHERE (id = 'dac23e41-e6d3-452d-8aa9-7d9193954520' OR vcode = 'BUN-GHQ-00015') AND slot_id IS NULL AND deleted_at IS NULL) THEN
    SELECT coalesce(max(slot_ordinal), 0) + 1 INTO v_ord
    FROM public.plantilla_slots
    WHERE account_id = v_actiserve_acc AND store_id IS NULL;

    INSERT INTO public.plantilla_slots (
      account_id,
      group_id,
      store_id,
      position,
      employment_type,
      is_roving,
      slot_ordinal,
      slot_status,
      created_at,
      updated_at
    ) VALUES (
      v_actiserve_acc,
      v_actiserve_grp,
      NULL,
      'Bundler',
      'roving',
      true,
      v_ord,
      'hr_processing',
      now(),
      now()
    ) RETURNING id INTO v_slot_actiserve;

    UPDATE public.hr_emploc
    SET slot_id = v_slot_actiserve,
        updated_at = now()
    WHERE (id = 'dac23e41-e6d3-452d-8aa9-7d9193954520' OR vcode = 'BUN-GHQ-00015')
      AND slot_id IS NULL;
  END IF;

  -- 5. Provision roving slot for Moses HQ (SEA-00006, James Cruz Reid)
  IF EXISTS (SELECT 1 FROM public.hr_emploc WHERE (id = '075f7248-5c76-4e1a-90ab-738724637461' OR vcode = 'SEA-00006') AND slot_id IS NULL AND deleted_at IS NULL) THEN
    SELECT coalesce(max(slot_ordinal), 0) + 1 INTO v_ord
    FROM public.plantilla_slots
    WHERE account_id = v_moses_acc AND store_id IS NULL;

    INSERT INTO public.plantilla_slots (
      account_id,
      group_id,
      store_id,
      position,
      employment_type,
      is_roving,
      slot_ordinal,
      slot_status,
      created_at,
      updated_at
    ) VALUES (
      v_moses_acc,
      v_moses_grp,
      NULL,
      'RELIEVER',
      'roving',
      true,
      v_ord,
      'hr_processing',
      now(),
      now()
    ) RETURNING id INTO v_slot_moses;

    UPDATE public.hr_emploc
    SET slot_id = v_slot_moses,
        updated_at = now()
    WHERE (id = '075f7248-5c76-4e1a-90ab-738724637461' OR vcode = 'SEA-00006')
      AND slot_id IS NULL;
  END IF;

END $$;
