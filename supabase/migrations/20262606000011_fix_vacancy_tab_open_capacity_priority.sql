-- Prompt ID: ohm#7c2a9f1d
-- Fix: Vacancy Open Tab Classification Priority
--
-- A vacancy with remaining open capacity (open_count > 0) must remain in the
-- Open tab whenever pipeline applicants do not fully cover the total required
-- headcount (pipeline_count < hc_needed). This ensures partially-filled or
-- multi-HC vacancies (e.g. SM Tabuk: 3 HC, 2 hired, 0 pipeline -> open_count 1)
-- stay visible in the Open tab after applicant backout, while single-HC
-- vacancies with an active pipeline candidate (e.g. SM Lala: 1 HC, 1 pipeline ->
-- fully covered) move strictly to the Pipeline tab.

BEGIN;

CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_shadow
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
),
applicant_counts AS (
  SELECT
    a.vacancy_vcode,
    COUNT(DISTINCT a.id) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND public.fn_is_active_vacancy_applicant_status(a.status)
    ) AS pipeline_count,
    COUNT(DISTINCT a.id) FILTER (
      WHERE COALESCE(a.is_archived, false) = false
        AND replace(lower(btrim(COALESCE(a.status, ''))), ' ', '_') = 'confirmed_onboard'
    ) AS hired_count
  FROM public.applicants a
  WHERE a.vacancy_vcode IS NOT NULL
  GROUP BY a.vacancy_vcode
)
SELECT
  ps.legacy_vcode,
  ps.legacy_vcode                                              AS vacancy_id,
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
  COALESCE(v.required_headcount::bigint, COUNT(*))             AS hc_needed,
  COALESCE(MAX(ac.pipeline_count), 0::bigint)                  AS pipeline_count,
  COALESCE(MAX(ac.hired_count), 0::bigint)                     AS hired_count,
  GREATEST(
    0::bigint,
    COALESCE(v.required_headcount::bigint, COUNT(*))
    - COALESCE(MAX(ac.hired_count), 0::bigint)
  )                                                             AS open_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')     AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')          AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')            AS closed_count,

  COALESCE(MAX(ac.pipeline_count), 0::bigint)                  AS active_applicant_count,
  bool_or(pc.vacancy_vcode IS NOT NULL)                        AS has_pending_closure,

  CASE
    WHEN GREATEST(
      0::bigint,
      COALESCE(v.required_headcount::bigint, COUNT(*))
      - COALESCE(MAX(ac.hired_count), 0::bigint)
    ) > 0
    AND COALESCE(MAX(ac.pipeline_count), 0::bigint) < COALESCE(v.required_headcount::bigint, COUNT(*))
    THEN 'Open'
    WHEN COALESCE(MAX(ac.pipeline_count), 0::bigint) > 0 THEN 'Pipeline'
    ELSE 'Closed'
  END                                                          AS vacancy_tab,

  MIN(COALESCE(ab.open_episode_start, ps.created_at))
    FILTER (WHERE ps.slot_status = 'open')                     AS aging_start_at,

  CASE
    WHEN GREATEST(
      0::bigint,
      COALESCE(v.required_headcount::bigint, COUNT(*))
      - COALESCE(MAX(ac.hired_count), 0::bigint)
    ) = 0 THEN NULL::integer
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
LEFT JOIN applicant_counts ac ON ac.vacancy_vcode = ps.legacy_vcode
INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
 AND v.deleted_at IS NULL
 AND COALESCE(v.is_archived, false) = false
 AND v.status <> 'Archived'
WHERE ps.legacy_vcode IS NOT NULL
  AND ps.is_roving = false
  AND NOT EXISTS (
    SELECT 1
    FROM public.coverage_group_stores cgs
    JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
    WHERE cgs.store_id = ps.store_id
      AND cgs.archived_at IS NULL
      AND cg.archived_at IS NULL
  )
GROUP BY ps.legacy_vcode, v.id;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'Slot-derived Vacancy read model. Open requires remaining open capacity (open_count > 0) with pipeline applicants strictly less than required headcount.';

COMMIT;
