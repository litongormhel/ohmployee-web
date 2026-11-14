-- Migration: fix_fn_get_hired_applicants_scope_leak
-- Prompt: ohm#a36isorp — Fix cross-account data leak in fn_get_hired_applicants (Production)
--
-- Context:
-- Prod's fn_get_hired_applicants(text) has no scope guard, leaking hired-applicant
-- records across accounts to any authenticated caller. Staging already carries the
-- fix (verified live, byte-for-byte identical apart from this guard). This migration
-- ports staging's exact WHERE-clause guard to close the gap on Production.
--
-- IMPORTANT — this is a REASSERT migration, not a net-new fix:
-- The guard was already authored in `20260703000003_add_scope_filter_fn_get_hired_applicants.sql`
-- and Production's schema_migrations already records that version as applied. But the live
-- function body on prod does NOT contain the guard (verified via pg_get_functiondef) — same
-- "history row present, body never executed" pattern documented in .ai/briefing.md for
-- 20260701000001-000006 (ohm#e91c2b7a). Re-running 20260703000003 verbatim will not
-- re-execute since its version is already marked applied, so this migration re-asserts the
-- same CREATE OR REPLACE body under a new version, following the same fix-forward precedent
-- as `20262606000008_reassert_function_bodies.sql`.
--
-- Filename note: versioned 20262606000017 (not today's real-date timestamp) to sort after
-- the latest locally-applied migration (20262606000016) and avoid an out-of-order push
-- rejection under this repo's existing (non-standard) 2026-26-06-prefixed sequence.
--
-- Verified before authoring:
-- - Live prod vs staging definitions compared via pg_get_functiondef on both projects
--   (rwxelulyapjgaarlwkus / qqiiznmqxfoamqytjica) — the only diff is the added guard line.
-- - get_my_allowed_accounts() already resolves group-scope membership and
--   temp_permission_overrides (covers Roving Merchandiser / cross-store elevated access),
--   so the guard does not drop legitimate cross-store visibility for roles that should have it.
-- - i_have_full_access() = role_level >= 90 (superAdmin/headAdmin), unchanged full-access bypass.

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
