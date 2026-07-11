-- ohm#f4k9p2q8 - Floating Employees Report RPC
-- Migration: 20261219000000_floating_employees_report.sql
--
-- Floating definition:
--   plantilla.status = 'Inactive' AND plantilla.separation_status = 'Floating'
--   (set by set_plantilla_floating RPC, migration 20261007000001)
--   floating_since = inactive_at::date
--   days_floating  = CURRENT_DATE - inactive_at::date
--
-- Scope: SECURITY DEFINER; full-access callers (role_level >= 90) see all;
-- scoped callers see only their assigned accounts/groups via user_scopes.
-- p_group_id / p_account_id are additive filters, never scope wideners.
--
-- Validation:
--   V1: SELECT proname FROM pg_proc WHERE proname = 'fn_report_floating_employees';
--   V2: SELECT COUNT(*) FROM fn_report_floating_employees() WHERE status <> 'Floating';
--       -- expected: 0
--   V3: SELECT COUNT(*) FROM fn_report_floating_employees() WHERE days_floating < 0;
--       -- expected: 0

DROP FUNCTION IF EXISTS public.fn_report_floating_employees(uuid, uuid);

CREATE OR REPLACE FUNCTION public.fn_report_floating_employees(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL
)
RETURNS TABLE (
  plantilla_id    uuid,
  employee_no     text,
  employee_name   text,
  position_title  text,
  account_id      uuid,
  account_name    text,
  group_id        uuid,
  group_name      text,
  store_name      text,
  floating_since  date,
  days_floating   integer,
  employment_type text,
  status          text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE
  v_auth_uid   uuid    := auth.uid();
  v_profile_id uuid;
  v_role_level integer;
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: fn_report_floating_employees requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_level
    INTO v_profile_id, v_role_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = v_auth_uid
     AND up.is_active    = TRUE
     AND up.archived_at  IS NULL
   ORDER BY up.created_at DESC
   LIMIT 1;

  IF v_profile_id IS NULL OR COALESCE(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: fn_report_floating_employees caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scope AS (
    SELECT ac.id AS account_id, ac.group_id
      FROM public.accounts ac
     WHERE ac.is_active = TRUE
       AND (
         COALESCE(v_role_level, 0) >= 90
         OR EXISTS (
           SELECT 1 FROM public.user_scopes us
            WHERE us.user_id    = v_profile_id
              AND us.account_id = ac.id
         )
         OR EXISTS (
           SELECT 1 FROM public.user_scopes us
            WHERE us.user_id    = v_profile_id
              AND us.account_id IS NULL
              AND us.group_id   = ac.group_id
         )
         OR NOT EXISTS (
           SELECT 1 FROM public.user_scopes us_any
            WHERE us_any.user_id = v_profile_id
              AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
         )
       )
  )
  SELECT
    p.id,
    p.employee_no,
    p.employee_name,
    COALESCE(p."position", '')            AS position_title,
    a.id                                  AS account_id,
    a.account_name,
    g.id                                  AS group_id,
    COALESCE(g.group_name, '')            AS group_name,
    COALESCE(p.store_name, '')            AS store_name,
    p.inactive_at::date                   AS floating_since,
    (CURRENT_DATE - p.inactive_at::date)::integer AS days_floating,
    COALESCE(p.deployment_type, 'Stationary')     AS employment_type,
    'Floating'::text                      AS status
  FROM public.plantilla p
  JOIN public.accounts  a ON a.id = p.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE p.status            = 'Inactive'
    AND p.separation_status = 'Floating'
    AND COALESCE(p.is_deleted, false) = false
    AND p.inactive_at IS NOT NULL
    AND p.account_id IN (SELECT sc.account_id FROM scope sc)
    AND (p_account_id IS NULL OR p.account_id = p_account_id)
    AND (p_group_id   IS NULL OR a.group_id   = p_group_id)
  ORDER BY
    a.account_name ASC,
    (CURRENT_DATE - p.inactive_at::date) DESC,
    p.employee_name ASC;
END;
$func$;

GRANT EXECUTE ON FUNCTION public.fn_report_floating_employees(uuid, uuid)
  TO authenticated;

REVOKE EXECUTE ON FUNCTION public.fn_report_floating_employees(uuid, uuid)
  FROM anon;

COMMENT ON FUNCTION public.fn_report_floating_employees(uuid, uuid) IS
  'ohm#f4k9p2q8 - Scope-safe floating employees report. '
  'Filter: status=Inactive AND separation_status=Floating. '
  'floating_since=inactive_at::date; days_floating=CURRENT_DATE-floating_since.';
