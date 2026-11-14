-- Migration: 20260721070000_fix_open_count_ignore_pipeline.sql
-- Prompt ID: ohm#3f91b2c7
-- Title: Fix Regression — Open Tab Must Ignore Pipeline in Capacity While Preserving Dedup Integrity
--
-- Problem:
--   Previous migration (20260721060000) incorrectly deducted pipeline_count from open_count capacity calculation:
--     open_count = GREATEST(0, hc_needed - pipeline_count - hired_count)
--   This caused vacancies with remaining hiring capacity (such as SM Tabuk VCAG2_0025: 3 HC, 2 hired, 1 pipeline)
--   to compute open_count = 0 and be hidden from the Open tab (improperly classified under Pipeline).
--
-- Solution:
--   1. Restore correct capacity formula:
--        open_count = GREATEST(0, hc_needed - hired_count)
--   2. Preserve deduplication:
--        COUNT(DISTINCT a.id) in applicant_counts CTE
--   3. Maintain exact 3-branch vacancy_tab classification:
--        CASE
--          WHEN open_count > 0 THEN 'Open'
--          WHEN pipeline_count > 0 THEN 'Pipeline'
--          ELSE 'Closed'
--        END
--   4. Preserve invariant: open_count > 0 ALWAYS forces 'Open'.
--   5. Maintain debug columns: hc_needed, hired_count, pipeline_count, open_count, and vacancy_id alias.

BEGIN;

DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow CASCADE;

CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS

-- ─────────────────────────────────────────────────────────────────────────────
-- CTE 1: aging_basis
-- ─────────────────────────────────────────────────────────────────────────────
WITH aging_basis AS (
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
),

-- ─────────────────────────────────────────────────────────────────────────────
-- CTE 2: pending_closure
-- ─────────────────────────────────────────────────────────────────────────────
pending_closure AS (
  SELECT DISTINCT vcr.vacancy_vcode
  FROM public.vacancy_closure_requests vcr
  JOIN public.vacancies v
    ON v.vcode = vcr.vacancy_vcode
   AND v.deleted_at IS NULL
   AND COALESCE(v.is_archived, false) = false
  WHERE vcr.status = 'Pending'
),

-- ─────────────────────────────────────────────────────────────────────────────
-- CTE 3: applicant_counts
-- COUNT(DISTINCT a.id) prevents fan-out double counting.
-- ─────────────────────────────────────────────────────────────────────────────
applicant_counts AS (
  SELECT
    a.vacancy_vcode,

    COUNT(DISTINCT a.id) FILTER (
      WHERE a.status IN (
        'New',
        'new',
        'For Interview',
        'For Requirements',
        'For Onboard'
      )
    ) AS pipeline_count,

    COUNT(DISTINCT a.id) FILTER (
      WHERE a.status = 'Confirmed Onboard'
    ) AS hired_count

  FROM public.applicants a
  WHERE a.vacancy_vcode IS NOT NULL
  GROUP BY a.vacancy_vcode
)

-- ─────────────────────────────────────────────────────────────────────────────
-- MAIN SELECT
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  ps.legacy_vcode,
  ps.legacy_vcode                                               AS vacancy_id,
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

  MIN(ps.position)                                              AS position,
  MIN(ps.employment_type)                                       AS employment_type,
  false                                                         AS is_roving,

  COUNT(*)                                                      AS required_hc,

  -- Debug / Verification columns
  COALESCE(v.required_headcount::bigint, COUNT(*))              AS hc_needed,
  COALESCE(MAX(ac.pipeline_count), 0::bigint)::bigint           AS pipeline_count,
  COALESCE(MAX(ac.hired_count), 0::bigint)::bigint              AS hired_count,

  -- open_count: capacity formula (ignores pipeline)
  GREATEST(
    0::bigint,
    COALESCE(v.required_headcount::bigint, COUNT(*))
    - COALESCE(MAX(ac.hired_count), 0::bigint)
  )::bigint                                                     AS open_count,

  -- Diagnostic columns
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')      AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')           AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')             AS closed_count,
  COALESCE(MAX(ac.pipeline_count), 0::bigint)::bigint           AS active_applicant_count,
  bool_or(pc.vacancy_vcode IS NOT NULL)                         AS has_pending_closure,

  -- vacancy_tab: strict priority classification
  CASE
    WHEN GREATEST(
           0::bigint,
           COALESCE(v.required_headcount::bigint, COUNT(*))
           - COALESCE(MAX(ac.hired_count), 0::bigint)
         ) > 0
      THEN 'Open'

    WHEN COALESCE(MAX(ac.pipeline_count), 0::bigint) > 0
      THEN 'Pipeline'

    ELSE 'Closed'
  END                                                           AS vacancy_tab,

  -- Aging calculation
  MIN(COALESCE(ab.open_episode_start, ps.created_at))
    FILTER (WHERE ps.slot_status = 'open')                      AS aging_start_at,

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
  END                                                           AS aging_days,

  MIN(ps.created_at)                                            AS created_at,
  MAX(ps.updated_at)                                            AS updated_at,
  MAX(ps.closed_at)                                             AS closed_at,

  (ARRAY_AGG(ps.source_hc_request_id ORDER BY ps.created_at, ps.id::text))[1]
                                                                AS source_hc_request_id,

  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name

FROM public.plantilla_slots ps
LEFT JOIN aging_basis ab            ON ab.slot_id   = ps.id
LEFT JOIN public.stores st          ON st.id        = ps.store_id
LEFT JOIN public.accounts a         ON a.id         = ps.account_id
LEFT JOIN public.groups g           ON g.id         = ps.group_id
LEFT JOIN pending_closure pc        ON pc.vacancy_vcode = ps.legacy_vcode
LEFT JOIN applicant_counts ac       ON ac.vacancy_vcode = ps.legacy_vcode
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
    WHERE cgs.store_id   = ps.store_id
      AND cgs.archived_at IS NULL
      AND cg.archived_at  IS NULL
  )

GROUP BY
  ps.legacy_vcode,
  v.id,
  v.required_headcount;

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'Slot-derived Vacancy read model. open_count = GREATEST(0, hc_needed - hired_count). Prompt: ohm#3f91b2c7.';

COMMIT;
