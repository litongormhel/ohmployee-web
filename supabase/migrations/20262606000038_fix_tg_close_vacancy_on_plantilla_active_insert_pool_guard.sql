-- ohm#5m9k2wtq: tg_close_vacancy_on_plantilla_active_insert closed vacancies
-- unconditionally against plantilla_slots only, with no awareness of
-- workforce_pool_slots. Same defect class as ohm#9k4t7wpz
-- (check_vacancy_headcount) and ohm#7q4n2wkx (move_to_plantilla pool path).
-- This trigger fires on every Active plantilla insert (stationary and pool
-- alike) with no branch split, so the guard is added unconditionally: it is
-- a no-op for non-pool vcodes, which have zero workforce_pool_slots rows.

CREATE OR REPLACE FUNCTION public.tg_close_vacancy_on_plantilla_active_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status <> 'Active' OR NEW.vcode IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.vacancies
     SET status     = 'Filled',
         updated_at = NOW()
   WHERE vcode = NEW.vcode
     AND status IN ('Open', 'For Sourcing')
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
     AND NOT EXISTS (
       SELECT 1
         FROM public.plantilla_slots ps
        WHERE ps.legacy_vcode = NEW.vcode
          AND COALESCE(ps.is_roving, false) = false
          AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
     )
     AND NOT EXISTS (
       SELECT 1
         FROM public.workforce_pool_slots wps
        WHERE wps.vcode = NEW.vcode
          AND wps.deleted_at IS NULL
          AND wps.is_active = true
          AND wps.status = 'open'
     );

  RETURN NEW;
END;
$function$
