BEGIN;

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
  WHERE vcr.status = 'Pending'
)
SELECT
  ps.legacy_vcode,
  v.id                                                          AS legacy_vacancy_id,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,
  v.required_headcount                                          AS required_headcount, -- true numeric required_headcount

  (ARRAY_AGG(ps.store_id   ORDER BY ps.created_at, ps.id::text))[1] AS store_id,
  MIN(st.store_branch)                                               AS store_branch,

  (ARRAY_AGG(ps.account_id ORDER BY ps.created_at, ps.id::text))[1] AS account_id,
  MIN(a.account_name)                                                AS account_name,
  (ARRAY_AGG(ps.group_id   ORDER BY ps.created_at, ps.id::text))[1] AS group_id,
  MIN(g.group_name)                                                  AS group_name,

  MIN(ps.position)                                              AS position,
  MIN(ps.employment_type)                                       AS employment_type,
  false                                                         AS is_roving,

  COUNT(*)                                                      AS required_hc,
  COUNT(*) FILTER (WHERE ps.slot_status = 'open')               AS open_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')           AS pipeline_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')      AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')           AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')             AS closed_count,

  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')           AS active_applicant_count,
  bool_or(pc.vacancy_vcode IS NOT NULL)                         AS has_pending_closure,

  CASE
    WHEN bool_or(pc.vacancy_vcode IS NOT NULL)
      THEN 'Closure'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'open') > 0
      THEN 'Open'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline') > 0
      THEN 'Pipeline'
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'closed') = COUNT(*)
         AND COUNT(*) > 0
      THEN 'Closure'
    ELSE NULL
  END                                                           AS vacancy_tab,

  MIN(COALESCE(ab.open_episode_start, ps.created_at))
    FILTER (WHERE ps.slot_status = 'open')                      AS aging_start_at,

  CASE
    WHEN COUNT(*) FILTER (WHERE ps.slot_status = 'open') = 0
      THEN NULL::integer
    WHEN (MIN(COALESCE(ab.open_episode_start, ps.created_at))
          FILTER (WHERE ps.slot_status = 'open'))::date > CURRENT_DATE
      THEN NULL::integer
    ELSE
      (CURRENT_DATE -
       (MIN(COALESCE(ab.open_episode_start, ps.created_at))
        FILTER (WHERE ps.slot_status = 'open'))::date
      )
  END                                                           AS aging_days,

  MIN(ps.created_at)                                            AS created_at,
  MAX(ps.updated_at)                                            AS updated_at,
  MAX(ps.closed_at)                                             AS closed_at,

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
INNER JOIN public.vacancies v ON v.vcode = ps.legacy_vcode AND v.deleted_at IS NULL
WHERE ps.legacy_vcode IS NOT NULL AND ps.is_roving = false
GROUP BY ps.legacy_vcode, v.id;

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;

COMMIT;
