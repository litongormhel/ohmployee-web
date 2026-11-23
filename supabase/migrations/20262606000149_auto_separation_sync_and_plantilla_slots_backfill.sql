-- Migration: 20262606000149_auto_separation_sync_and_plantilla_slots_backfill.sql
-- Purpose:
-- 1. ADR-001 Invariant 19: Automatic Inactive Status on Effective Date of Separation.
--    Trigger trg_plantilla_auto_separation_sync sets status = 'Inactive' when date_of_separation <= CURRENT_DATE.
--    Trigger trg_plantilla_vacate_slot_on_inactive vacates any occupied slot in plantilla_slots upon deactivation/inactivation.
-- 2. ADR-002 Invariant 1 & 5: 1:1 Headcount to Physical Slot Identity.
--    Backfill missing occupied plantilla_slots rows for active/on-leave personnel (including legacy baseline stores TEST001..TEST008).
-- 3. Data alignment for Super 9 (TEST009):
--    Transition Kimi Antonelli (date_of_separation = 2026-10-27) to Inactive.
--    Reopen Super 9 vacancy in public.vacancies and vacate slot in public.plantilla_slots.

-- §1 Trigger: Auto-Inactive on Effective Separation Date
CREATE OR REPLACE FUNCTION public.fn_trg_plantilla_auto_separation_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.date_of_separation IS NOT NULL 
     AND NEW.date_of_separation <= CURRENT_DATE 
     AND (NEW.status IS NULL OR NEW.status NOT IN ('Inactive', 'Deactivated')) THEN
    NEW.status := 'Inactive';
    IF NEW.inactive_at IS NULL THEN
      NEW.inactive_at := now();
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_plantilla_auto_separation_sync ON public.plantilla;
CREATE TRIGGER trg_plantilla_auto_separation_sync
  BEFORE INSERT OR UPDATE OF date_of_separation, status
  ON public.plantilla
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_plantilla_auto_separation_sync();

-- §2 Trigger: Vacate Slot upon Inactive / Deactivated Transition
CREATE OR REPLACE FUNCTION public.fn_trg_plantilla_vacate_slot_on_inactive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (NEW.status IN ('Inactive', 'Deactivated')) AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    UPDATE public.plantilla_slots
       SET slot_status = 'open',
           current_occupant_plantilla_id = NULL,
           updated_at = now()
     WHERE current_occupant_plantilla_id = NEW.id
       AND slot_status IN ('occupied', 'filled');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_plantilla_vacate_slot_on_inactive ON public.plantilla;
CREATE TRIGGER trg_plantilla_vacate_slot_on_inactive
  AFTER UPDATE OF status
  ON public.plantilla
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_plantilla_vacate_slot_on_inactive();

-- §3 Data Alignment & Backfill with Trigger Guards
ALTER TABLE public.plantilla DISABLE TRIGGER trg_plantilla_separation_to_vacancy;
ALTER TABLE public.vacancies DISABLE TRIGGER trg_assert_vacancy_edit_allowed;

-- Transition existing employees with past date_of_separation to Inactive
UPDATE public.plantilla
   SET status = 'Inactive',
       inactive_at = COALESCE(inactive_at, now()),
       updated_at = now()
 WHERE date_of_separation IS NOT NULL
   AND date_of_separation <= CURRENT_DATE
   AND status = 'Active';

-- Reopen Super 9 (TEST009) Vacancy & Vacate Slot
UPDATE public.vacancies
   SET status = 'Open',
       required_headcount = 1.0,
       updated_at = now()
 WHERE vcode = 'TEST009';

UPDATE public.plantilla_slots
   SET slot_status = 'open',
       current_occupant_plantilla_id = NULL,
       updated_at = now()
 WHERE legacy_vcode = 'TEST009'
   AND is_roving = false;

-- §4 ADR-002 1:1 Headcount to Physical Slot Identity Backfill
DO $$
DECLARE
  r RECORD;
  v_next_ordinal smallint;
BEGIN
  FOR r IN (
    SELECT 
      p.id as plantilla_id,
      p.store_id,
      p.account_id,
      COALESCE(s.group_id, (SELECT group_id FROM public.stores WHERE id = p.store_id)) as group_id,
      COALESCE(p.position, 'Merchandiser') as pos,
      COALESCE(p.vcode, s.vcode) as vcode
    FROM public.plantilla p
    JOIN public.stores s ON s.id = p.store_id OR (p.store_id IS NULL AND s.vcode = p.vcode)
    WHERE p.status IN ('Active', 'On Leave')
      AND p.is_archived = false
      AND (p.is_deleted IS NULL OR p.is_deleted = false)
      AND NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots ps
        WHERE ps.current_occupant_plantilla_id = p.id
      )
    ORDER BY p.created_at ASC
  ) LOOP
    SELECT COALESCE(MAX(slot_ordinal), 0) + 1
      INTO v_next_ordinal
      FROM public.plantilla_slots
     WHERE legacy_vcode = r.vcode;

    INSERT INTO public.plantilla_slots (
      id,
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,
      legacy_vcode,
      current_occupant_plantilla_id,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      r.store_id,
      r.account_id,
      r.group_id,
      r.pos,
      'Stationary',
      false,
      'occupied',
      v_next_ordinal,
      r.vcode,
      r.plantilla_id,
      now(),
      now()
    );
  END LOOP;
END $$;

ALTER TABLE public.vacancies ENABLE TRIGGER trg_assert_vacancy_edit_allowed;
ALTER TABLE public.plantilla ENABLE TRIGGER trg_plantilla_separation_to_vacancy;
