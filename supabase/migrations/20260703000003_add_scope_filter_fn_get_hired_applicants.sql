-- ============================================================
-- ohm#3d9qxr6v — Phase 2 / Step 6 Follow-up
-- Add account/group scope filter to fn_get_hired_applicants(p_vcode text)
-- ============================================================
-- CONTEXT:
--   ohm#7v2vm5be (grant-only pass) restricted EXECUTE to authenticated
--   but flagged a separate gap: the function body has no
--   get_my_allowed_accounts() scope filter, so any authenticated caller
--   sees hired applicants across ALL accounts/groups, not just their
--   own scope. This violates the standing RBAC rule that non-admin
--   roles are scoped to their assigned accounts.
--
-- REFERENCE PATTERN (used verbatim, not invented):
--   `vacancies_read_scoped` RLS policy on public.vacancies
--   (20260520012857_remote_schema.sql):
--     public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))
--   Same pattern already used for pool-vacancy Ops scoping
--   (applicants_insert_ops_only, ohm#rlsrel06): v.account = ANY (public.get_my_allowed_accounts())
--
-- SCOPE BOUNDARY: account-level, matching vacancies_read_scoped exactly
--   (fn_get_hired_applicants already joins vacancies v and reads v.account
--   for display — the same v.account is now used for the scope filter).
--   Full-access roles (Super Admin / Head Admin, i_have_full_access())
--   bypass the filter per standing RBAC rule.
--
-- LOGIC-ONLY CHANGE: adds one AND condition to the existing WHERE clause.
--   No signature change, no grant change (already authenticated-only
--   from ohm#7v2vm5be), no other function touched.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_get_hired_applicants(p_vcode text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, vacancy_vcode text, full_name text, last_name text, first_name text, middle_name text, contact_number text, status text, hired_date date, hired_by text, hired_by_team text, hired_at timestamp with time zone, hired_visible_until timestamp with time zone, days_remaining integer, group_name text, account text, position_name text, state text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    a.id,
    a.vacancy_vcode,
    a.full_name,
    a.last_name,
    a.first_name,
    a.middle_name,
    a.contact_number,
    a.status,
    a.hired_date,
    a.hired_by,
    a.hired_by_team,
    a.hired_at,
    a.hired_visible_until,
    GREATEST(
      0,
      CEIL(EXTRACT(EPOCH FROM (a.hired_visible_until - NOW())) / 86400)::integer
    ) AS days_remaining,
    COALESCE(g.group_name, 'Group') AS group_name,
    v.account,
    v.position AS position_name,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM public.plantilla p
        WHERE (p.hr_emploc_id = he.id
            OR (p.vcode = a.vacancy_vcode AND p.employee_name = a.full_name))
          AND COALESCE(p.is_archived, false) = false
          AND COALESCE(p.is_deleted, false) = false
      ) THEN 'Plantilla'
      WHEN he.id IS NOT NULL THEN 'HR Emploc'
      ELSE 'Vacancy / Pending HR Emploc'
    END AS state
  FROM public.applicants a
  JOIN public.vacancies v
    ON v.vcode = a.vacancy_vcode
   AND v.deleted_at IS NULL
   AND COALESCE(v.is_archived, false) = false
   AND v.status <> 'Archived'
  LEFT JOIN public.groups g ON g.id = v.group_id
  LEFT JOIN public.hr_emploc he
    ON he.applicant_id = a.id
   AND he.deleted_at IS NULL
  WHERE COALESCE(a.is_archived, false) = false
    AND (a.hired_at IS NOT NULL OR a.hired_date IS NOT NULL)
    AND a.hired_visible_until > NOW()
    AND (p_vcode IS NULL OR a.vacancy_vcode = p_vcode)
    AND (public.i_have_full_access() OR v.account = ANY (public.get_my_allowed_accounts()))
  ORDER BY a.hired_at DESC NULLS LAST, a.hired_date DESC NULLS LAST;
END;
$function$;
