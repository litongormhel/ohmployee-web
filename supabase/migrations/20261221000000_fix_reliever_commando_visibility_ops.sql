-- Migration: 20261221000000_fix_reliever_commando_visibility_ops.sql
-- Ticket: ohm#rci001 — Fix Reliever/Commando Indicator Visibility for Ops Roles
--
-- Wires scope checks in can_view_pool_employee, wa_read_scoped RLS, and
-- v_workforce_store_temporary_coverage using get_my_allowed_account_ids()
-- instead of get_my_allowed_accounts() to match UUID types correctly.

-- 1. Redefine can_view_pool_employee to compare account UUID against get_my_allowed_account_ids()
CREATE OR REPLACE FUNCTION public.can_view_pool_employee(p_employee_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 AS $function$
BEGIN
  -- Data Team (30/90/100) and full access roles: always visible
  IF get_my_role_level() = ANY(ARRAY[100, 90, 30]) OR i_have_full_access() THEN
    RETURN TRUE;
  END IF;

  -- Ops (40-70) and Viewer (10) / Recruitment (20):
  -- visible if employee has NO group tag (global) OR group tag
  -- maps to at least one of caller's allowed accounts
  RETURN EXISTS (
    SELECT 1
    FROM workforce_pool_slots wps
    JOIN plantilla pt ON pt.vcode = wps.vcode
    WHERE pt.id = p_employee_id
      AND wps.is_active = true
      AND wps.deleted_at IS NULL
      AND (
        wps.group_id IS NULL
        OR EXISTS (
          SELECT 1 FROM accounts a
          WHERE a.group_id = wps.group_id
            AND a.id = ANY(get_my_allowed_account_ids())
        )
      )
  );
END;
$function$;

-- 2. Drop and recreate wa_read_scoped policy on workforce_assignments
DROP POLICY IF EXISTS "wa_read_scoped" ON public.workforce_assignments;

CREATE POLICY "wa_read_scoped" ON "public"."workforce_assignments"
AS permissive
FOR SELECT
TO authenticated
USING (
  public.get_my_role_level() = ANY (ARRAY[100, 90, 30])
  OR public.i_have_full_access()
  OR (
    (public.get_my_role_level() >= 40 AND public.get_my_role_level() <= 70)
    AND assigned_account_id = ANY (public.get_my_allowed_account_ids())
    AND public.can_view_pool_employee(employee_id)
  )
);

-- 3. Update view v_workforce_store_temporary_coverage
CREATE OR REPLACE VIEW public.v_workforce_store_temporary_coverage AS
SELECT
  wa.id                  AS assignment_id,
  wa.assigned_store_id   AS store_id,
  wa.assigned_account_id AS account_id,
  wa.assigned_group_id   AS group_id,
  wa.employee_id,
  p.employee_no          AS employee_number,
  p.employee_name,
  wpt.code               AS pool_type_code,
  wpt.name               AS pool_type_name,
  wa.deployment_type,
  wa.priority,
  wa.is_primary,
  wa.start_date,
  wa.end_date,
  wa.status,
  wa.approved_by,
  wa.approved_at,
  a.account_name,
  s.store_name,
  s.store_branch,
  g.group_name,
  wa.covered_plantilla_id
FROM public.workforce_assignments wa
JOIN  public.plantilla           p   ON (p.id = wa.employee_id AND p.is_deleted = false)
JOIN  public.workforce_pool_types wpt ON wpt.id = wa.pool_type_id
LEFT JOIN public.accounts          a   ON a.id = wa.assigned_account_id
LEFT JOIN public.stores             s   ON s.id = wa.assigned_store_id
LEFT JOIN public.groups             g   ON g.id = wa.assigned_group_id
WHERE wa.status = ANY (ARRAY['Active'::text, 'Approved'::text])
  AND (
    get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR public.i_have_full_access()
    OR (
      (wa.assigned_account_id = ANY (public.get_my_allowed_account_ids()))
      AND public.can_view_pool_employee(wa.employee_id)
    )
  );

GRANT SELECT ON public.v_workforce_store_temporary_coverage TO authenticated;
REVOKE ALL  ON public.v_workforce_store_temporary_coverage FROM anon;

COMMENT ON VIEW public.v_workforce_store_temporary_coverage IS
  'ohm#k3p8w6z1: Active/Approved workforce assignments with covered_plantilla_id column added. '
  'employee_id = the reliever/commando. covered_plantilla_id = the on-leave employee being covered.';
