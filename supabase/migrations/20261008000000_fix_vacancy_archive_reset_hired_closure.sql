-- ============================================================
-- OHM2026_0078 - Vacancy Archive Reset Hired/Closure Leak Fix
-- Migration: 20261008000000_fix_vacancy_archive_reset_hired_closure.sql
-- ============================================================
-- Purpose:
--   Ensure Vacancy archive/reset removes all active Vacancy tab data:
--   Open=0, Pipeline=0, Hired=0, Closure=0 after an all-module reset.
--
-- Root causes:
--   1. fn_get_hired_applicants read directly from applicants and joined
--      vacancies without excluding archived vacancies.
--   2. QA/enterprise archive functions archived vacancies but did not
--      archive linked applicants, so hired applicants retained active hire
--      markers and remained visible in the Hired tab.
--   3. The latest slot-derived Vacancy shadow view joined vacancies only
--      on deleted_at IS NULL, so archived vacancies with QA-closed slots
--      could still map into Closure.
--   4. Pending vacancy_closure_requests linked to an archived vacancy could
--      still be treated as active closure source state.
--
-- Scope:
--   - No UI/RBAC/RLS changes.
--   - No VCode generation or duplicate behavior changes.
--   - No hard deletes.
--   - Rollback restores only rows tagged by the same QA archive batch.
-- ============================================================

BEGIN;

-- Section 1. Trace archive-reset membership on linked Vacancy children.

ALTER TABLE public.applicants
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_applicants_qa_archive_batch
  ON public.applicants (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

ALTER TABLE public.vacancy_closure_requests
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS qa_archive_previous_status text DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_vcr_qa_archive_batch
  ON public.vacancy_closure_requests (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;


-- Section 2. Vacancy archive/rollback cascade for linked tab sources.

CREATE OR REPLACE FUNCTION public.trg_fn_vacancy_archive_reset_cascade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_batch_id uuid;
  v_actor_id uuid;
BEGIN
  v_batch_id := COALESCE(NEW.qa_archive_batch_id, OLD.qa_archive_batch_id);
  v_actor_id := COALESCE(NEW.archived_by_id, NEW.updated_by, OLD.updated_by);

  -- Archive path: hide all applicant-grain Vacancy sources, including Hired.
  IF COALESCE(NEW.is_archived, false) = true
     AND COALESCE(OLD.is_archived, false) = false THEN
    UPDATE public.applicants a
    SET
      is_archived = true,
      qa_archive_batch_id = v_batch_id,
      updated_at = now()
    WHERE a.vacancy_vcode = NEW.vcode
      AND COALESCE(a.is_archived, false) = false;

    -- Pending closure requests are active workflow state. Withdraw only those
    -- linked to this archive event; preserve their original status for rollback.
    UPDATE public.vacancy_closure_requests vcr
    SET
      qa_archive_previous_status = COALESCE(vcr.qa_archive_previous_status, vcr.status),
      qa_archive_batch_id = v_batch_id,
      status = 'Withdrawn',
      withdrawn_at = COALESCE(vcr.withdrawn_at, now()),
      withdrawn_by_user_id = COALESCE(vcr.withdrawn_by_user_id, v_actor_id)
    WHERE vcr.vacancy_vcode = NEW.vcode
      AND vcr.status = 'Pending';

    RETURN NEW;
  END IF;

  -- Rollback path: restore only children that were archived by this same batch.
  IF COALESCE(NEW.is_archived, false) = false
     AND COALESCE(OLD.is_archived, false) = true
     AND OLD.qa_archive_batch_id IS NOT NULL THEN
    UPDATE public.applicants a
    SET
      is_archived = false,
      qa_archive_batch_id = NULL,
      updated_at = now()
    WHERE a.vacancy_vcode = NEW.vcode
      AND a.qa_archive_batch_id = OLD.qa_archive_batch_id
      AND COALESCE(a.is_archived, false) = true;

    UPDATE public.vacancy_closure_requests vcr
    SET
      status = COALESCE(vcr.qa_archive_previous_status, 'Pending'),
      qa_archive_previous_status = NULL,
      qa_archive_batch_id = NULL,
      withdrawn_at = NULL,
      withdrawn_by_user_id = NULL
    WHERE vcr.vacancy_vcode = NEW.vcode
      AND vcr.qa_archive_batch_id = OLD.qa_archive_batch_id
      AND vcr.status = 'Withdrawn';

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vacancy_archive_reset_cascade ON public.vacancies;
CREATE TRIGGER trg_vacancy_archive_reset_cascade
  AFTER UPDATE OF is_archived, qa_archive_batch_id ON public.vacancies
  FOR EACH ROW
  WHEN (
    COALESCE(NEW.is_archived, false) IS DISTINCT FROM COALESCE(OLD.is_archived, false)
  )
  EXECUTE FUNCTION public.trg_fn_vacancy_archive_reset_cascade();


-- Section 3. Backfill currently archived vacancies from a prior reset/apply gap.

UPDATE public.applicants a
SET
  is_archived = true,
  qa_archive_batch_id = COALESCE(a.qa_archive_batch_id, v.qa_archive_batch_id),
  updated_at = now()
FROM public.vacancies v
WHERE a.vacancy_vcode = v.vcode
  AND COALESCE(v.is_archived, false) = true
  AND COALESCE(a.is_archived, false) = false;

UPDATE public.vacancy_closure_requests vcr
SET
  qa_archive_previous_status = COALESCE(vcr.qa_archive_previous_status, vcr.status),
  qa_archive_batch_id = COALESCE(vcr.qa_archive_batch_id, v.qa_archive_batch_id),
  status = 'Withdrawn',
  withdrawn_at = COALESCE(vcr.withdrawn_at, now()),
  withdrawn_by_user_id = COALESCE(vcr.withdrawn_by_user_id, v.archived_by_id, v.updated_by)
FROM public.vacancies v
WHERE vcr.vacancy_vcode = v.vcode
  AND COALESCE(v.is_archived, false) = true
  AND vcr.status = 'Pending';


-- Section 4. Hired tab source: exclude archived/inactive vacancy parents.

CREATE OR REPLACE FUNCTION public.fn_get_hired_applicants(p_vcode text DEFAULT NULL)
RETURNS TABLE (
  id                  uuid,
  vacancy_vcode       text,
  full_name           text,
  last_name           text,
  first_name          text,
  middle_name         text,
  contact_number      text,
  status              text,
  hired_date          date,
  hired_by            text,
  hired_by_team       text,
  hired_at            timestamp with time zone,
  hired_visible_until timestamp with time zone,
  days_remaining      integer,
  group_name          text,
  account             text,
  position_name       text,
  state               text
)
LANGUAGE plpgsql
SECURITY DEFINER
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
  ORDER BY a.hired_at DESC NULLS LAST, a.hired_date DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_hired_applicants(text)
  TO anon, authenticated, service_role;


-- Section 5. Closure/Open/Pipeline source: exclude archived vacancy parents.

DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow;

CREATE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
),
pending_closure AS (
  SELECT DISTINCT vcr.vacancy_vcode
  FROM public.vacancy_closure_requests vcr
  JOIN public.vacancies v
    ON v.vcode = vcr.vacancy_vcode
   AND v.deleted_at IS NULL
   AND COALESCE(v.is_archived, false) = false
  WHERE vcr.status = 'Pending'
)
SELECT
  ps.legacy_vcode,
  v.id                                                          AS legacy_vacancy_id,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,
  v.required_headcount                                          AS required_headcount,

  (ARRAY_AGG(ps.store_id   ORDER BY ps.created_at, ps.id::text))[1] AS store_id,
  MIN(st.store_branch)                                               AS store_branch,

  (ARRAY_AGG(ps.account_id ORDER BY ps.created_at, ps.id::text))[1] AS account_id,
  MIN(a.account_name)                                                AS account_name,
  (ARRAY_AGG(ps.group_id   ORDER BY ps.created_at, ps.id::text))[1] AS group_id,
  MIN(g.group_name)                                                  AS group_name,

  MIN(ps.position)                                             AS position,
  MIN(ps.employment_type)                                      AS employment_type,
  false                                                        AS is_roving,

  COUNT(*)                                                     AS required_hc,
  COUNT(*) FILTER (WHERE ps.slot_status = 'open')              AS open_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')          AS pipeline_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')     AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')          AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')            AS closed_count,

  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')          AS active_applicant_count,
  bool_or(pc.vacancy_vcode IS NOT NULL)                        AS has_pending_closure,

  CASE
    WHEN bool_or(pc.vacancy_vcode IS NOT NULL) THEN 'Closure'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'open') > 0 THEN 'Open'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline') > 0 THEN 'Pipeline'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'closed') = COUNT(*) AND COUNT(*) > 0
      THEN 'Closure'
    ELSE NULL
  END                                                          AS vacancy_tab,

  MIN(COALESCE(ab.open_episode_start, ps.created_at))
    FILTER (WHERE ps.slot_status = 'open')                     AS aging_start_at,

  CASE
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'open') = 0 THEN NULL::integer
    WHEN (MIN(COALESCE(ab.open_episode_start, ps.created_at))
          FILTER (WHERE ps.slot_status = 'open'))::date > CURRENT_DATE
      THEN NULL::integer
    ELSE (
      CURRENT_DATE -
      (MIN(COALESCE(ab.open_episode_start, ps.created_at))
       FILTER (WHERE ps.slot_status = 'open'))::date
    )
  END                                                          AS aging_days,

  MIN(ps.created_at)                                           AS created_at,
  MAX(ps.updated_at)                                           AS updated_at,
  MAX(ps.closed_at)                                            AS closed_at,

  (ARRAY_AGG(ps.source_hc_request_id ORDER BY ps.created_at, ps.id::text))[1] AS source_hc_request_id,

  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name

FROM public.plantilla_slots ps
LEFT JOIN aging_basis ab ON ab.slot_id = ps.id
LEFT JOIN public.stores st ON st.id = ps.store_id
LEFT JOIN public.accounts a ON a.id = ps.account_id
LEFT JOIN public.groups g ON g.id = ps.group_id
LEFT JOIN pending_closure pc ON pc.vacancy_vcode = ps.legacy_vcode
INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
 AND v.deleted_at IS NULL
 AND COALESCE(v.is_archived, false) = false
 AND v.status <> 'Archived'
WHERE ps.legacy_vcode IS NOT NULL
  AND ps.is_roving = false
GROUP BY ps.legacy_vcode, v.id;

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'Slot-derived Vacancy read model. OHM2026_0078 restores the active parent guard: '
  'deleted_at IS NULL, is_archived=false, and status<>Archived. Archived/reset '
  'vacancies cannot appear in Open, Pipeline, Hired, or Closure tab sources.';


-- Section 6. Smoke checks as notices for SQL Editor validation.

DO $$
DECLARE
  v_hired_leaks integer;
  v_shadow_leaks integer;
  v_pending_closure_leaks integer;
BEGIN
  SELECT COUNT(*) INTO v_hired_leaks
  FROM public.applicants a
  JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE COALESCE(v.is_archived, false) = true
    AND COALESCE(a.is_archived, false) = false
    AND (a.hired_at IS NOT NULL OR a.hired_date IS NOT NULL);

  SELECT COUNT(*) INTO v_shadow_leaks
  FROM public.vw_slot_derived_vacancy_shadow s
  JOIN public.vacancies v ON v.vcode = s.legacy_vcode
  WHERE COALESCE(v.is_archived, false) = true;

  SELECT COUNT(*) INTO v_pending_closure_leaks
  FROM public.vacancy_closure_requests vcr
  JOIN public.vacancies v ON v.vcode = vcr.vacancy_vcode
  WHERE COALESCE(v.is_archived, false) = true
    AND vcr.status = 'Pending';

  RAISE NOTICE 'OHM2026_0078 smoke: hired_leaks=%, shadow_leaks=%, pending_closure_leaks=%',
    v_hired_leaks, v_shadow_leaks, v_pending_closure_leaks;
END;
$$;

COMMIT;
