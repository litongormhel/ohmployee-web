-- Migration: 20261028033015_fix_sync_closed_slot_to_vacancy_multi_slot_guard.sql
-- Function public.fn_sync_closed_slot_to_vacancy was previously unversioned in the database.
-- Fixes closed-slot -> vacancy sync for multi-slot vacancies:
-- Vacancy is closed ONLY when no OTHER live slot remains for that legacy_vcode.

CREATE OR REPLACE FUNCTION public.fn_sync_closed_slot_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.slot_status = 'closed' AND (TG_OP = 'INSERT' OR OLD.slot_status IS DISTINCT FROM NEW.slot_status) THEN
    IF NEW.legacy_vcode IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.plantilla_slots
        WHERE legacy_vcode = NEW.legacy_vcode
          AND id <> NEW.id
          AND slot_status NOT IN ('closed', 'hc_reduced')
          AND closed_at IS NULL
      ) THEN
        UPDATE public.vacancies
        SET status = 'Closed',
            updated_at = NOW()
        WHERE vcode = NEW.legacy_vcode
          AND status NOT IN ('Closed', 'Archived')
          AND COALESCE(is_archived, false) = false;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
