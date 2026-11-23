-- Migration: 20262606000150_update_fn_archive_hired_vacancies_to_30_days.sql
-- Description: Align fn_archive_hired_vacancies auto-archive interval from 7 days to 30 days per ADR-001 Vacancy Governance.

CREATE OR REPLACE FUNCTION public.fn_archive_hired_vacancies()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count int := 0;
BEGIN
  UPDATE vacancies v
  SET
    is_archived = true,
    archived_at = NOW(),
    status = 'Archived',
    updated_at = NOW()
  WHERE v.deleted_at IS NULL
    AND (v.is_archived IS NULL OR v.is_archived = false)
    AND v.status NOT IN ('Archived', 'Closed')
    AND EXISTS (
      SELECT 1 FROM applicants a
      WHERE a.vacancy_vcode = v.vcode
        AND (a.is_archived IS NULL OR a.is_archived = false)
        AND a.status = 'Confirmed Onboard'
        AND a.hired_at < NOW() - INTERVAL '30 days'
    )
    AND NOT EXISTS (
      SELECT 1 FROM applicants a
      WHERE a.vacancy_vcode = v.vcode
        AND (a.is_archived IS NULL OR a.is_archived = false)
        AND a.status NOT IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops', 'Confirmed Onboard')
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;
