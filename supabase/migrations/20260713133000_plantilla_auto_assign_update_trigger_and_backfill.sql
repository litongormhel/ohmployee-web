-- Migration: 20260713133000_plantilla_auto_assign_update_trigger_and_backfill
-- Created: 2026-07-13
-- Purpose: Auto-assign sole HRCO on status update to 'Active' and backfill existing unassigned active employees.

BEGIN;

-- 1. Re-create the trigger to run on INSERT or UPDATE OF status on public.plantilla
DROP TRIGGER IF EXISTS trg_plantilla_auto_assign_sole_hrco ON public.plantilla;

CREATE TRIGGER trg_plantilla_auto_assign_sole_hrco
  AFTER INSERT OR UPDATE OF status ON public.plantilla
  FOR EACH ROW EXECUTE FUNCTION public.trg_auto_assign_sole_hrco();

-- 2. Backfill existing active unassigned employees for accounts that have exactly 1 active HRCO
WITH sole_hrcos AS (
  -- Accounts with exactly 1 active HRCO
  SELECT a.id AS account_id, up.auth_user_id AS hrco_user_id, up.id AS hrco_profile_id, up.email, up.full_name
  FROM public.accounts a
  CROSS JOIN LATERAL (
    SELECT up.auth_user_id, up.id, up.email, up.full_name
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE r.role_name = 'HRCO'
      AND COALESCE(up.is_active, true)
      AND EXISTS (
        SELECT 1 FROM public.user_scopes us
        WHERE us.user_id = up.id
          AND COALESCE(us.is_active, true)
          AND (
            us.account_id = a.id
            OR us.group_id = a.group_id
          )
      )
  ) up
  WHERE (
    SELECT count(DISTINCT up2.auth_user_id)
    FROM public.users_profile up2
    JOIN public.roles r2 ON r2.id = up2.role_id
    WHERE r2.role_name = 'HRCO'
      AND COALESCE(up2.is_active, true)
      AND EXISTS (
        SELECT 1 FROM public.user_scopes us2
        WHERE us2.user_id = up2.id
          AND COALESCE(us2.is_active, true)
          AND (
            us2.account_id = a.id
            OR us2.group_id = a.group_id
          )
      )
  ) = 1
)
INSERT INTO public.plantilla_hrco_assignments (
  plantilla_id, employee_no, account_id, hrco_user_id,
  hrco_email_snapshot, hrco_name_snapshot,
  assigned_by, assignment_source
)
SELECT p.id, p.employee_no, p.account_id, sh.hrco_user_id,
       sh.email, sh.full_name,
       sh.hrco_profile_id, 'auto_single_hrco'
FROM public.plantilla p
JOIN sole_hrcos sh ON sh.account_id = p.account_id
WHERE p.status = 'Active'
  AND (p.is_deleted IS NOT TRUE)
  AND NOT EXISTS (
    SELECT 1 FROM public.plantilla_hrco_assignments pha
     WHERE pha.plantilla_id = p.id AND pha.is_active
  );

COMMIT;
