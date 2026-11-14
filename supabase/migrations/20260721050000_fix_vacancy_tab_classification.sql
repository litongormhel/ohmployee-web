-- Migration: 20260721050000_fix_vacancy_tab_classification.sql
-- Prompt ID: ohm#7f2c9d1a
-- Title: Fix Vacancy Tab Classification Using Derived Open Count (Post-Derivation Regression)
--
-- Problem:
--   SM Tabuk (hc_needed=3, pipeline=2, hired=0, open_count=1) is missing from the Open tab
--   despite open_count = 1. The previous migration (20260721040000) still included a residual
--   slot-status-based clause in the Pipeline WHEN branch:
--     OR COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline') > 0
--   This violates the HARD RULE that vacancy_tab must NEVER depend on slot.status.
--
-- Root Cause:
--   The Pipeline WHEN branch in vacancy_tab retained a slot-based check:
--     WHEN COALESCE(MAX(ac.pipeline_count), 0) > 0
--       OR COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline') > 0  ← VIOLATION
--     THEN 'Pipeline'
--   Even though this branch evaluates AFTER the Open check (so open_count > 0 cases
--   should be caught first), any edge case where the slot statuses don't reflect
--   applicant-derived counts can produce incorrect classification.
--
-- Fix:
--   vacancy_tab is now derived EXCLUSIVELY from open_count:
--     CASE
--       WHEN pending_closure        → 'Closure'
--       WHEN open_count > 0         → 'Open'       (capacity remains)
--       WHEN pipeline_count > 0     → 'Pipeline'   (applicant-derived only, NO slot check)
--       WHEN hired_count >= hc_need → 'Closure'    (fully hired)
--       ELSE 'Open'                                (zero-activity default)
--     END
--
-- HARD RULE (enforced in this migration):
--   vacancy_tab MUST be derived ONLY from open_count / pipeline_count / hired_count.
--   NEVER from slot.status, slot.slot_status, or raw slot counts.
--
-- Validation SQL (run after applying):
--   -- SM Tabuk must show open_count=1, vacancy_tab='Open'
--   SELECT location, required_headcount, pipeline_count, hired_count, open_count, vacancy_tab
--   FROM vw_slot_derived_vacancy_shadow
--   WHERE store_name ILIKE '%Tabuk%';
--
--   -- Zero-tolerance check: no row can have open_count > 0 with vacancy_tab != 'Open'
--   SELECT COUNT(*) AS violations
--   FROM vw_slot_derived_vacancy_shadow
--   WHERE open_count > 0 AND vacancy_tab <> 'Open';
--   -- Expected: 0
--
--   -- Edge case A: hc=3, pipeline=3 → open=0, NOT in Open
--   -- Edge case B: hc=3, pipeline=5 → open=0 (GREATEST clamps), NOT in Open
--   -- Edge case C: hc=3, pipeline=2 → open=1, MUST be in Open
--
-- Idempotent: DROP VIEW IF EXISTS CASCADE + CREATE OR REPLACE VIEW.

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

  -- open_count: derived as GREATEST(0, hc_needed - pipeline - hired).
  -- This is the canonical formula. vacancy_tab uses the IDENTICAL expression
  -- (no divergence). NEVER sourced from slot.status.
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

  -- ─────────────────────────────────────────────────────────────────────────
  -- vacancy_tab: HARD RULE — derived ONLY from open_count / pipeline_count /
  -- hired_count. NEVER from slot.status or raw slot counts.
  --
  -- Priority order (ADR-001 compliant):
  --   1. Closure  — pending closure request (highest priority)
  --   2. Open     — open_count > 0 (capacity remains, regardless of pipeline)
  --   3. Pipeline — pipeline_count > 0 (all capacity consumed by applicants)
  --   4. Closure  — hired_count >= hc_needed (fully hired)
  --   5. Open     — default for zero-activity vacancies
  --
  -- The GREATEST(0, hc - pipeline - hired) expression below is byte-identical
  -- to the open_count column above — zero divergence by construction.
  -- ─────────────────────────────────────────────────────────────────────────
  CASE
    -- Priority 1: Pending closure request overrides everything.
    WHEN bool_or(pc.vacancy_vcode IS NOT NULL)
      THEN 'Closure'

    -- Priority 2: Any remaining open capacity → Open tab.
    -- open_count > 0 MUST always route here before Pipeline is evaluated.
    WHEN GREATEST(
           0::bigint,
           COALESCE(v.required_headcount::bigint, COUNT(*))
           - COALESCE(MAX(ac.pipeline_count), 0::bigint)
           - COALESCE(MAX(ac.hired_count), 0::bigint)
         ) > 0
      THEN 'Open'

    -- Priority 3: No open capacity, but applicants in pipeline.
    -- NOTE: ONLY applicant-derived pipeline_count — NO slot.status check.
    WHEN COALESCE(MAX(ac.pipeline_count), 0::bigint) > 0
      THEN 'Pipeline'

    -- Priority 4: Fully hired (hired_count covers all required headcount).
    WHEN COALESCE(MAX(ac.hired_count), 0::bigint)
         >= COALESCE(v.required_headcount::bigint, COUNT(*))
      THEN 'Closure'

    -- Priority 5: Default — zero-activity vacancy is Open.
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
  'Slot-derived Vacancy read model. '
  'HARD RULE: vacancy_tab and open_count are derived ONLY from applicant-based counts '
  '(open = GREATEST(0, hc_needed - pipeline - hired)). '
  'NO slot.status dependency in vacancy_tab. '
  'Priority: Closure (pending) > Open (capacity > 0) > Pipeline (applicants) > Closure (fully hired) > Open (default). '
  'Prompt: ohm#7f2c9d1a.';

-- ─────────────────────────────────────────────────────────────────────────────
-- PROOF QUERIES — Run these immediately after applying to validate correctness.
-- ─────────────────────────────────────────────────────────────────────────────

-- Q1: SM Tabuk proof (primary success criterion)
-- Expected: open_count = 1, vacancy_tab = 'Open'
-- SELECT
--   store_name   AS location,
--   required_headcount,
--   pipeline_count,
--   hired_count,
--   open_count,
--   vacancy_tab
-- FROM public.vw_slot_derived_vacancy_shadow
-- WHERE store_name ILIKE '%Tabuk%';

-- Q2: Zero-tolerance violation check (must return 0)
-- SELECT COUNT(*) AS violations
-- FROM public.vw_slot_derived_vacancy_shadow
-- WHERE open_count > 0 AND vacancy_tab <> 'Open';

-- Q3: Edge case distribution (spot-check)
-- SELECT
--   CASE
--     WHEN open_count > 0 THEN 'Has open capacity'
--     WHEN pipeline_count > 0 THEN 'Full pipeline'
--     WHEN hired_count >= required_headcount THEN 'Fully hired'
--     ELSE 'Zero activity'
--   END AS scenario,
--   vacancy_tab,
--   COUNT(*) AS cnt
-- FROM public.vw_slot_derived_vacancy_shadow
-- GROUP BY 1, 2
-- ORDER BY 1, 2;

-- Q4: NULL vacancy_tab check (must return 0)
-- SELECT COUNT(*) AS null_tabs
-- FROM public.vw_slot_derived_vacancy_shadow
-- WHERE vacancy_tab IS NULL;

COMMIT;
