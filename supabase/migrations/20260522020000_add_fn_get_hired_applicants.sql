-- ============================================================
-- OHM2026_2043 — Wire Existing Vacancy Hired Tab as 100% Read-Only
-- ============================================================
-- Adds fn_get_hired_applicants(p_vcode text DEFAULT NULL)
-- Return hired applicants within their visibility window.
-- 100% read-only monitoring view.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_get_hired_applicants(p_vcode text DEFAULT NULL)
RETURNS TABLE (
  id uuid,
  vacancy_vcode text,
  full_name text,
  last_name text,
  first_name text,
  middle_name text,
  contact_number text,
  status text,
  hired_date date,
  hired_by text,
  hired_by_team text,
  hired_at timestamp with time zone,
  hired_visible_until timestamp with time zone,
  days_remaining integer,
  group_name text,
  account text,
  position_name text,
  state text
) LANGUAGE plpgsql SECURITY DEFINER 
SET search_path = public
AS $$
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
    GREATEST(0, CEIL(EXTRACT(EPOCH FROM (COALESCE(a.hired_visible_until, a.hired_at + INTERVAL '7 days') - NOW())) / 86400)::integer) AS days_remaining,
    COALESCE(g.group_name, 'Group') AS group_name,
    v.account,
    v.position AS position_name,
    CASE 
      WHEN EXISTS (
        SELECT 1 FROM public.plantilla p 
        WHERE p.hr_emploc_id = he.id 
           OR (p.vcode = a.vacancy_vcode AND p.employee_name = a.full_name)
      ) THEN 'Plantilla'
      WHEN he.id IS NOT NULL THEN 'HR Emploc'
      ELSE 'Vacancy / Pending HR Emploc'
    END AS state
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  LEFT JOIN public.groups g ON g.id = v.group_id
  LEFT JOIN public.hr_emploc he ON he.applicant_id = a.id
  WHERE (COALESCE(a.is_archived, false) = false)
    AND a.status = 'Confirmed Onboard'
    AND COALESCE(a.hired_visible_until, a.hired_at + INTERVAL '7 days') > NOW()
    AND (p_vcode IS NULL OR a.vacancy_vcode = p_vcode)
  ORDER BY a.hired_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_hired_applicants(text) TO anon, authenticated, service_role;
