-- ============================================================
-- OHMployee - Fix Active Applicant Occupancy Enforcement
-- Prompt ID : OHM2026_2019
-- Date      : 2026-05-21
-- Scope     : Vacancy applicant slot enforcement only
-- ============================================================
-- Rules:
--   Active applicant statuses:
--     New, For Interview, For Requirements, For Onboard
--     plus lowercase/snake_case equivalents.
--   Terminal / not active:
--     Rejected, Failed, Backout, Transferred, Hired
--     and all other non-canonical statuses.
--   Open     = no active applicant.
--   Pipeline = at least one active applicant.
--   Reliever/Commando coverage is not applicant occupancy.
--
-- Data cleanup:
--   This migration does not delete or mutate applicant rows.
--   If duplicate active applicants already exist, the final
--   CREATE UNIQUE INDEX will fail. Run the duplicate report query
--   in the validation section, resolve manually, then rerun.
-- ============================================================

-- ============================================================
-- 1. Canonical active applicant predicate
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_is_active_vacancy_applicant_status(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT replace(lower(btrim(COALESCE(p_status, ''))), ' ', '_') IN (
    'new',
    'for_interview',
    'for_requirements',
    'for_onboard'
  );
$$;

COMMENT ON FUNCTION public.fn_is_active_vacancy_applicant_status(text) IS
  'OHM2026_2019 - Canonical Vacancy slot occupancy predicate. '
  'Only New, For Interview, For Requirements, and For Onboard, including lowercase/snake_case equivalents, are active.';

-- ============================================================
-- 2. Slot-check RPC used by Add Applicant guard
-- ============================================================
DROP FUNCTION IF EXISTS public.fn_check_vcode_applicant_slot(text);

CREATE OR REPLACE FUNCTION public.fn_check_vcode_applicant_slot(p_vcode text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing record;
BEGIN
  IF nullif(btrim(p_vcode), '') IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'available', false,
      'has_active_applicant', false,
      'error', 'vcode_required'
    );
  END IF;

  SELECT
    a.id,
    a.status,
    COALESCE(
      NULLIF(a.full_name, ''),
      NULLIF(btrim(concat_ws(' ', a.first_name, a.middle_name, a.last_name)), ''),
      'Unknown'
    ) AS applicant_name
  INTO v_existing
  FROM public.applicants a
  WHERE a.vacancy_vcode = p_vcode
    AND COALESCE(a.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a.status)
  ORDER BY COALESCE(a.updated_at, a.created_at) DESC NULLS LAST, a.created_at DESC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'available', false,
      'has_active_applicant', true,
      'active_applicant_id', v_existing.id,
      'active_applicant_name', v_existing.applicant_name,
      'active_applicant_status', v_existing.status,
      'message', 'VCODE already occupied'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'available', true,
    'has_active_applicant', false
  );
END;
$$;

COMMENT ON FUNCTION public.fn_check_vcode_applicant_slot(text) IS
  'OHM2026_2019 - Returns vacancy slot availability using the canonical active applicant predicate.';

GRANT EXECUTE ON FUNCTION public.fn_check_vcode_applicant_slot(text) TO authenticated, service_role;

-- ============================================================
-- 3. Repair pipeline classification/count views
-- ============================================================
CREATE OR REPLACE VIEW public.v_vacancy_pipeline_status
WITH (security_invoker = true)
AS
SELECT
  v.id      AS vacancy_id,
  v.vcode,
  v.account,
  v.status  AS vacancy_status,
  COUNT(a.id) AS active_applicant_count,
  CASE
    WHEN COUNT(a.id) > 0 THEN 'Pipeline'
    ELSE 'Open'
  END AS pipeline_classification
FROM public.vacancies v
LEFT JOIN public.applicants a
  ON a.vacancy_vcode = v.vcode
 AND COALESCE(a.is_archived, false) = false
 AND public.fn_is_active_vacancy_applicant_status(a.status)
WHERE v.deleted_at IS NULL
  AND COALESCE(v.is_archived, false) = false
GROUP BY v.id, v.vcode, v.account, v.status;

COMMENT ON VIEW public.v_vacancy_pipeline_status IS
  'OHM2026_2019 - Open/Pipeline classification from canonical active applicant statuses only.';

GRANT SELECT ON public.v_vacancy_pipeline_status TO authenticated, service_role;

CREATE OR REPLACE VIEW public.vw_vacancy_list
WITH (security_invoker = true)
AS
WITH applicant_stats AS (
  SELECT
    a.vacancy_vcode,
    COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND public.fn_is_active_vacancy_applicant_status(a.status)
    ) AS active_applicant_count,
    COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
    ) AS confirmed_onboard_count,
    MAX(a.hired_at) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
    ) AS latest_hire_at,
    (COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
        AND COALESCE(a.hired_visible_until, a.hired_at + INTERVAL '7 days') > NOW()
    ) > 0) AS has_recent_hire
  FROM public.applicants a
  GROUP BY a.vacancy_vcode
)
SELECT
  v.id,
  v.vcode,
  v.account,
  v.account_id,
  v.store_name,
  v.store_id,
  v.area_name,
  v.area_city,
  v.position,
  v.position_id,
  v.employment_type,
  v.status,
  CASE
    WHEN (v.is_archived = true) OR (v.status = ANY (ARRAY['Closed','Archived'])) THEN 'Archived'
    WHEN v.status = 'Filled'                                                      THEN 'Hired'
    WHEN COALESCE(s.active_applicant_count, 0) > 0                                THEN 'Pipeline'
    ELSE 'Open'
  END AS derived_status,
  v.source,
  v.source_vacancy_request_id,
  v.source_plantilla_id,
  v.vacancy_type,
  v.urgency_level,
  v.target_fill_date,
  v.required_headcount AS hc_needed,
  v.triggered_by_user_id,
  v.triggered_by_name,
  v.vacant_date,
  (CURRENT_DATE - v.vacant_date) AS aging_days,
  v.created_at,
  v.created_by,
  v.updated_at,
  v.is_archived,
  v.archived_at,
  v.closure_request_status,
  v.has_pending_closure,
  COALESCE(s.active_applicant_count, 0) AS active_applicant_count,
  COALESCE(s.confirmed_onboard_count, 0) AS confirmed_onboard_count,
  s.latest_hire_at,
  v.assigned_encoder_id,
  v.group_id,
  g.group_name,
  v.hrco_user_id,
  v.hrco_name,
  COALESCE(s.has_recent_hire, false) AS has_recent_hire
FROM public.vacancies v
LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
LEFT JOIN public.groups g ON g.id = v.group_id
WHERE v.deleted_at IS NULL;

GRANT SELECT ON public.vw_vacancy_list TO authenticated, service_role;

CREATE OR REPLACE VIEW public.vw_vacancy_detail
WITH (security_invoker = true)
AS
WITH applicant_stats AS (
  SELECT
    a.vacancy_vcode,
    COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND public.fn_is_active_vacancy_applicant_status(a.status)
    ) AS active_applicant_count,
    COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
    ) AS confirmed_onboard_count,
    MAX(a.hired_at) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
    ) AS latest_hire_at,
    (COUNT(*) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND a.status = 'Confirmed Onboard'
        AND COALESCE(a.hired_visible_until, a.hired_at + INTERVAL '7 days') > NOW()
    ) > 0) AS has_recent_hire
  FROM public.applicants a
  GROUP BY a.vacancy_vcode
)
SELECT
  v.id,
  v.vcode,
  v.account,
  v.account_id,
  v.store_name,
  v.store_id,
  v.area_name,
  v.area_city,
  v.position,
  v.position_id,
  v.employment_type,
  v.status,
  CASE
    WHEN (v.is_archived = true) OR (v.status = ANY (ARRAY['Closed','Archived'])) THEN 'Archived'
    WHEN v.status = 'Filled'                                                      THEN 'Hired'
    WHEN COALESCE(s.active_applicant_count, 0) > 0                                THEN 'Pipeline'
    ELSE 'Open'
  END AS derived_status,
  v.source,
  v.source_vacancy_request_id,
  v.source_plantilla_id,
  v.vacancy_type,
  v.urgency_level,
  v.target_fill_date,
  v.required_headcount AS hc_needed,
  v.triggered_by_user_id,
  v.triggered_by_name,
  v.vacant_date,
  (CURRENT_DATE - v.vacant_date) AS aging_days,
  v.created_at,
  v.created_by,
  v.updated_at,
  v.is_archived,
  v.archived_at,
  v.closure_request_status,
  v.has_pending_closure,
  COALESCE(s.active_applicant_count, 0) AS active_applicant_count,
  COALESCE(s.confirmed_onboard_count, 0) AS confirmed_onboard_count,
  s.latest_hire_at,
  v.assigned_encoder_id,
  v.has_reliever,
  v.reliever_name,
  v.requested_by_user_id,
  v.requested_date,
  v.group_id,
  g.group_name,
  v.hrco_user_id,
  v.hrco_name,
  COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
  NULL::text AS triggered_by_role,
  vr.vacancy_type AS hc_request_type,
  vr.requested_by AS hc_request_requested_by,
  vr.requested_by_user_id AS hc_request_requested_by_user_id,
  vr.created_at AS hc_request_date_created,
  vr.no_of_slots AS hc_request_no_of_slots,
  COALESCE(s.has_recent_hire, false) AS has_recent_hire
FROM public.vacancies v
LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
LEFT JOIN public.groups g ON g.id = v.group_id
LEFT JOIN public.users_profile up ON up.id = v.triggered_by_user_id
LEFT JOIN public.vacancy_requests vr ON vr.id = v.source_vacancy_request_id
WHERE v.deleted_at IS NULL;

GRANT SELECT ON public.vw_vacancy_detail TO authenticated, service_role;

-- ============================================================
-- 4. Enforce one active applicant per VCODE
-- ============================================================
DROP INDEX IF EXISTS public.uq_applicants_one_active_per_vcode;

CREATE UNIQUE INDEX uq_applicants_one_active_per_vcode
  ON public.applicants (vacancy_vcode)
  WHERE (
    COALESCE(is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(status)
  );

COMMENT ON INDEX public.uq_applicants_one_active_per_vcode IS
  'OHM2026_2019 - Enforces at most one canonical active applicant per vacancy_vcode. '
  'Active statuses: New, For Interview, For Requirements, For Onboard, including lowercase/snake_case equivalents.';

-- ============================================================
-- 5. Validation SQL / manual duplicate report
-- ============================================================
-- Active applicant count for smoke-test VCODE:
-- SELECT
--   a.vacancy_vcode,
--   COUNT(*) FILTER (
--     WHERE COALESCE(a.is_archived, false) = false
--       AND public.fn_is_active_vacancy_applicant_status(a.status)
--   ) AS active_applicant_count,
--   jsonb_agg(jsonb_build_object(
--     'id', a.id,
--     'name', COALESCE(a.full_name, btrim(concat_ws(' ', a.first_name, a.middle_name, a.last_name))),
--     'status', a.status,
--     'is_archived', a.is_archived
--   ) ORDER BY a.created_at) AS applicants
-- FROM public.applicants a
-- WHERE a.vacancy_vcode = 'VCAG5_0009'
-- GROUP BY a.vacancy_vcode;
--
-- Duplicate active applicant report:
-- SELECT
--   a.vacancy_vcode,
--   COUNT(*) AS active_count,
--   jsonb_agg(jsonb_build_object(
--     'id', a.id,
--     'name', COALESCE(a.full_name, btrim(concat_ws(' ', a.first_name, a.middle_name, a.last_name))),
--     'status', a.status,
--     'created_at', a.created_at,
--     'updated_at', a.updated_at
--   ) ORDER BY COALESCE(a.updated_at, a.created_at) DESC NULLS LAST) AS active_applicants
-- FROM public.applicants a
-- WHERE COALESCE(a.is_archived, false) = false
--   AND public.fn_is_active_vacancy_applicant_status(a.status)
-- GROUP BY a.vacancy_vcode
-- HAVING COUNT(*) > 1
-- ORDER BY active_count DESC, a.vacancy_vcode;
--
-- Open/Pipeline spot checks:
-- SELECT vcode, active_applicant_count, pipeline_classification
-- FROM public.v_vacancy_pipeline_status
-- WHERE vcode IN ('VCAG5_0009', '<HC_REQUEST_NO_APPLICANT_VCODE>', '<ACTIVE_APPLICANT_VCODE>', '<TERMINAL_ONLY_VCODE>')
-- ORDER BY vcode;
--
-- Terminal-only check:
-- SELECT
--   a.vacancy_vcode,
--   COUNT(*) FILTER (
--     WHERE COALESCE(a.is_archived, false) = false
--       AND public.fn_is_active_vacancy_applicant_status(a.status)
--   ) AS active_applicant_count
-- FROM public.applicants a
-- WHERE a.status IN ('Failed', 'Rejected', 'Backout', 'failed', 'rejected', 'backout')
-- GROUP BY a.vacancy_vcode
-- HAVING COUNT(*) FILTER (
--   WHERE COALESCE(a.is_archived, false) = false
--     AND public.fn_is_active_vacancy_applicant_status(a.status)
-- ) = 0;
--
-- Second active insert should fail after duplicates are resolved and the index exists:
-- INSERT INTO public.applicants (vacancy_vcode, first_name, last_name, full_name, status, is_archived)
-- VALUES ('<ACTIVE_APPLICANT_VCODE>', 'Slot', 'Test', 'Slot Test', 'New', false);
-- Expected: duplicate key violates uq_applicants_one_active_per_vcode.
-- ============================================================
