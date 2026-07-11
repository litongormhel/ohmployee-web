-- Pre-schema shim: restore trigger function before remote_schema.sql replay.
-- 20260521062543_remote_schema.sql creates the trigger but assumes the function
-- already exists. This migration runs just before it to satisfy that dependency.
-- The function body is sourced from 20260521200000_vcode_duplicate_cleanup.sql
-- which defines the authoritative implementation.

CREATE OR REPLACE FUNCTION public.tg_close_vacancy_on_plantilla_active_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only act on Active employees with a VCODE
  IF NEW.status <> 'Active' OR NEW.vcode IS NULL THEN
    RETURN NEW;
  END IF;

  -- Close any Open/For Sourcing vacancy with the same VCODE.
  UPDATE public.vacancies
     SET status     = 'Filled',
         updated_at = NOW()
   WHERE vcode      = NEW.vcode
     AND status     IN ('Open', 'For Sourcing')
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL;

  RETURN NEW;
END;
$$;
