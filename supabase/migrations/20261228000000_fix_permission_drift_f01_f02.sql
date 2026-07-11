-- Migration: 20261228000000_fix_permission_drift_f01_f02.sql
-- Description: Align i_have_full_access() to level-based authorization and protect canonical roles from renaming

-- 1. Redefine i_have_full_access() to use public.get_my_role_level() >= 90
CREATE OR REPLACE FUNCTION public.i_have_full_access()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 AS $function$
begin
  return public.get_my_role_level() >= 90;
end;
$function$;

-- 2. Add database protection to prevent renaming canonical roles
CREATE OR REPLACE FUNCTION public.tg_prevent_canonical_role_rename()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.role_name IN (
    'Super Admin', 'Head Admin',
    'Operations Manager', 'OM',
    'HRCO',
    'ATL/TL', 'ATL', 'TL',
    'Encoder',
    'HR Personnel',
    'Recruitment Team', 'Recruitment',
    'Back Office', 'Backoffice', 'Backoffice Personnel',
    'Viewer'
  ) AND NEW.role_name IS DISTINCT FROM OLD.role_name THEN
    RAISE EXCEPTION
      'Renaming of canonical role ''%'' is protected and not allowed.',
      OLD.role_name
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_canonical_role_rename ON public.roles;

CREATE TRIGGER trg_prevent_canonical_role_rename
  BEFORE UPDATE ON public.roles
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_prevent_canonical_role_rename();

-- 3. Update F-01 and F-02 findings to 'resolved' and set resolved_at
UPDATE public.permission_drift_findings
SET status = 'resolved',
    resolved_at = now()
WHERE finding_code IN ('F-01', 'F-02');

-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
