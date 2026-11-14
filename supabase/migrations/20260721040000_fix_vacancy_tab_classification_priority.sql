-- Migration: 20260721040000_fix_vacancy_tab_classification_priority.sql
-- Prompt ID: ohm#5d2b8f71
-- Description: Fix Vacancy Tab Classification Priority (Restore Open Visibility with Derived Counts)
--
-- Problem: vacancy_tab CASE priority incorrectly placed pipeline check before open check.
-- Records with open_count > 0 AND pipeline_count > 0 were classified as 'Pipeline'
-- instead of 'Open', making valid open vacancies invisible in the Open tab.
--
-- Business Rule (ADR-001):
--   If a vacancy still has capacity (open_count > 0), it MUST appear in the Open tab
--   regardless of pipeline activity.
--
-- Priority order (corrected):
--   1. Closure (pending closure request) — highest priority
--   2. Open — if open_count > 0 (capacity remains)
--   3. Pipeline — if pipeline_count > 0 (all slots filled by pipeline, no open capacity)
--   4. Closure — if hired_count >= required_headcount (fully hired)
--   5. Open (default) — vacancies with no activity are Open
--
-- Derived expression for vacancy_tab is kept identical to open_count derivation (no divergence).
--
-- Idempotent: DROP VIEW IF EXISTS + CREATE OR REPLACE ensures safe re-apply.

BEGIN;

DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow CASCADE;

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
    COUNT(*) FILTER (
      WHERE a.status IN (
        'New',
        'new',
        'For Interview',
        'For Requirements',
        'For Onboard'
      )
    ) AS pipeline_count,
    COUNT(*) FILTER (
      WHERE a.status = 'Confirmed Onboard'
    ) AS hired_count
  FROM public.applicants a
  WHERE a.vacancy_vcode IS NOT NULL
  GROUP BY a.vacancy_vcode
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
  GREATEST(
    0::bigint,
    COALESCE(v.required_headcount::bigint, COUNT(*))
    - COALESCE(MAX(ac.pipeline_count), 0::bigint)
    - COALESCE(MAX(ac.hired_count), 0::bigint)
  )::bigint                                                    AS open_count,
  COALESCE(MAX(ac.pipeline_count), 0::bigint)::bigint          AS pipeline_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')     AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')          AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')            AS closed_count,
  COALESCE(MAX(ac.hired_count), 0::bigint)::bigint             AS hired_count,

  COALESCE(MAX(ac.pipeline_count), 0::bigint)::bigint          AS active_applicant_count,
  bool_or(pc.vacancy_vcode IS NOT NULL)                        AS has_pending_closure,

  -- vacancy_tab: priority-correct classification aligned with derived open_count.
  -- Rule: Open capacity takes precedence over Pipeline activity.
  -- Uses the SAME derived expression as open_count — no divergence.
  CASE
    WHEN bool_or(pc.vacancy_vcode IS NOT NULL)
      THEN 'Closure'

    WHEN GREATEST(
           0::bigint,
           COALESCE(v.required_headcount::bigint, COUNT(*))
           - COALESCE(MAX(ac.pipeline_count), 0::bigint)
           - COALESCE(MAX(ac.hired_count), 0::bigint)
         ) > 0
      THEN 'Open'

    WHEN COALESCE(MAX(ac.pipeline_count), 0::bigint) > 0
      OR COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline') > 0
      THEN 'Pipeline'

    WHEN COALESCE(MAX(ac.hired_count), 0::bigint)
         >= COALESCE(v.required_headcount::bigint, COUNT(*))
      THEN 'Closure'

    ELSE 'Open'
  END                                                          AS vacancy_tab,

  MIN(COALESCE(ab.open_episode_start, ps.created_at))
    FILTER (WHERE ps.slot_status = 'open')                     AS aging_start_at,

  CASE
    WHEN GREATEST(
      0::bigint,
      COALESCE(v.required_headcount::bigint, COUNT(*))
      - COALESCE(MAX(ac.pipeline_count), 0::bigint)
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
  -- Suppress vacancies for stores that belong to active Coverage Groups.
  AND NOT EXISTS (
    SELECT 1 FROM public.coverage_group_stores cgs
    JOIN public.coverage_groups cg ON cg.id = cgs.coverage_group_id
    WHERE cgs.store_id = ps.store_id
      AND cgs.archived_at IS NULL
      AND cg.archived_at IS NULL
  )
GROUP BY ps.legacy_vcode, v.id, v.required_headcount;

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'Slot-derived Vacancy read model. open_count and vacancy_tab use identical derived formula: GREATEST(0, hc_needed - pipeline - hired). Priority: Closure > Open (capacity > 0) > Pipeline > Closure (fully hired) > Open (default).';

COMMIT;
