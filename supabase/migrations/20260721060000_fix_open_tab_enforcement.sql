-- Migration: 20260721060000_fix_open_tab_enforcement.sql
-- Prompt ID: ohm#c8a4f2d1
-- Title: Enforce Open Tab Inclusion for Partially Filled Vacancies (Strict Open Count Authority)
--
-- Problem:
--   SM Tabuk (hc_needed=3, pipeline=2, hired=0) has open_count=1 but is NOT appearing in
--   the Open tab. Root cause investigation identified four possible failure modes:
--     1. open_count computed incorrectly (double-counting via non-DISTINCT aggregation)
--     2. vacancy_tab logic bypassed or overridden by residual slot-status clause
--     3. pipeline_count or hired_count inflated by bad status mapping or join fan-out
--     4. GROUP BY / aggregation inconsistency distorting counts
--
--   Migration 20260721050000 (ohm#7f2c9d1a) removed the slot-status clause from the
--   Pipeline branch but was NEVER APPLIED to staging (status: PENDING APPLY).
--   This migration supersedes it with additional hardening.
--
-- HARD RULES (non-negotiable, enforced in this definition):
--   1. vacancy_tab is derived ONLY from open_count / pipeline_count / hired_count.
--      NEVER from ps.slot_status, raw slot counts, or COUNT(*) FILTER (WHERE slot_status ...).
--   2. Priority is STRICT:
--        WHEN pending_closure   → 'Closure'
--        WHEN open_count > 0   → 'Open'     ← ABSOLUTE PRIORITY, no override possible
--        WHEN pipeline_count > 0 → 'Pipeline'
--        ELSE 'Open'           (zero-activity default — also catches fully-hired edge)
--   3. pipeline_count and hired_count use COUNT(DISTINCT applicant_id) to prevent
--      fan-out double-counting from any upstream join or duplicate applicant rows.
--   4. No COUNT(*) FILTER (WHERE ps.slot_status ...) anywhere in SELECT/CASE/HAVING.
--      (hr_processing_count / occupied_count / closed_count are diagnostic-only and
--       are NOT referenced in vacancy_tab or open_count.)
--
-- open_count formula (canonical, invariant):
--   open_count = GREATEST(0, hc_needed - pipeline_count - hired_count)
--   where:
--     hc_needed      = v.required_headcount (cast to bigint; fallback COUNT(*) slots)
--     pipeline_count = COUNT(DISTINCT applicant_id) WHERE status IN valid pipeline statuses
--     hired_count    = COUNT(DISTINCT applicant_id) WHERE status = 'Confirmed Onboard'
--
-- Debug columns added (required for validation):
--   hc_needed, pipeline_count, hired_count, open_count — all present and alias-named
--   so validation queries can confirm arithmetic independently.
--
-- Validation (run immediately after applying):
--   -- A. Core invariant: must return 0 rows
--   SELECT vacancy_id, store_name, hc_needed, pipeline_count, hired_count, open_count, vacancy_tab
--   FROM vw_slot_derived_vacancy_shadow
--   WHERE open_count > 0 AND vacancy_tab <> 'Open';
--
--   -- B. SM Tabuk: must show open_count>=1, vacancy_tab='Open'
--   SELECT legacy_vcode, store_name, hc_needed, pipeline_count, hired_count, open_count, vacancy_tab
--   FROM vw_slot_derived_vacancy_shadow
--   WHERE store_name ILIKE '%tabuk%';
--
--   -- C. No NULL vacancy_tab: must return 0
--   SELECT COUNT(*) FROM vw_slot_derived_vacancy_shadow WHERE vacancy_tab IS NULL;
--
-- Idempotent: DROP VIEW IF EXISTS CASCADE + CREATE OR REPLACE VIEW.

BEGIN;

DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow CASCADE;

CREATE OR REPLACE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS

-- ─────────────────────────────────────────────────────────────────────────────
-- CTE 1: aging_basis
-- Last 'open' transition timestamp per slot for aging calculation.
-- Unrelated to vacancy_tab classification — do NOT derive tab logic here.
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
-- VCodes with a currently-pending closure request. Feeds has_pending_closure
-- and the Priority-1 Closure branch of vacancy_tab.
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
-- HARD RULES:
--   a. COUNT(DISTINCT a.id) — prevents double-counting if any upstream join
--      creates fan-out or if an applicant has duplicate rows.
--   b. Only valid pipeline statuses are counted. Status strings are exact-match
--      (both 'New' and 'new' included for legacy data compatibility).
--   c. 'Confirmed Onboard' is the ONLY hired status — not 'Hired', not 'Onboard'.
--   d. No slot-table join here. This CTE is purely from public.applicants.
--   e. vacancy_vcode IS NOT NULL filter avoids including orphaned applicants.
--
-- Pipeline statuses (inclusive set — add new statuses here if onboarding flow expands):
--   'New', 'new'           — newly submitted applicants (legacy mixed-case)
--   'For Interview'        — scheduled for interview
--   'For Requirements'     — documents phase
--   'For Onboard'          — pre-onboarding pending
--
-- Hired status:
--   'Confirmed Onboard'    — applicant is now an employee; occupies headcount
-- ─────────────────────────────────────────────────────────────────────────────
applicant_counts AS (
  SELECT
    a.vacancy_vcode,

    -- DISTINCT: each applicant counted once regardless of join fan-out
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
  v.id                                                           AS legacy_vacancy_id,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,
  v.required_headcount                                           AS required_headcount,

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

  -- ─────────────────────────────────────────────────────────────────────────
  -- DEBUG / VALIDATION COLUMNS
  -- These expose the intermediate values used by open_count and vacancy_tab
  -- so validation queries can independently confirm the arithmetic.
  -- ─────────────────────────────────────────────────────────────────────────

  -- hc_needed: authoritative headcount requirement from vacancies table.
  -- Falls back to COUNT(*) slots when v.required_headcount is NULL (edge case).
  COALESCE(v.required_headcount::bigint, COUNT(*))              AS hc_needed,

  -- pipeline_count: applicant-derived ONLY. COUNT(DISTINCT) prevents double-count.
  -- NEVER from slot.status.
  COALESCE(MAX(ac.pipeline_count), 0::bigint)::bigint           AS pipeline_count,

  -- hired_count: applicant-derived ONLY. COUNT(DISTINCT) prevents double-count.
  COALESCE(MAX(ac.hired_count), 0::bigint)::bigint              AS hired_count,

  -- open_count: canonical formula.
  -- INVARIANT: if open_count > 0 then vacancy_tab MUST be 'Open'.
  -- This expression is byte-identical to the Priority-2 WHEN branch below.
  GREATEST(
    0::bigint,
    COALESCE(v.required_headcount::bigint, COUNT(*))
    - COALESCE(MAX(ac.pipeline_count), 0::bigint)
    - COALESCE(MAX(ac.hired_count),    0::bigint)
  )::bigint                                                      AS open_count,

  -- ─────────────────────────────────────────────────────────────────────────
  -- Slot-status diagnostic columns (INFORMATIONAL ONLY)
  -- These are NEVER referenced in vacancy_tab or open_count.
  -- They exist solely for operational diagnostics (slot health dashboards, etc.).
  -- ─────────────────────────────────────────────────────────────────────────
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')      AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')           AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')             AS closed_count,

  -- active_applicant_count: alias of pipeline_count for backward compatibility.
  COALESCE(MAX(ac.pipeline_count), 0::bigint)::bigint           AS active_applicant_count,

  bool_or(pc.vacancy_vcode IS NOT NULL)                         AS has_pending_closure,

  -- ─────────────────────────────────────────────────────────────────────────
  -- vacancy_tab: STRICT PRIORITY CLASSIFICATION
  --
  -- HARD RULE: derived EXCLUSIVELY from open_count / pipeline_count / hired_count.
  -- NEVER from ps.slot_status, COUNT(*) FILTER (WHERE slot_status ...), or any
  -- slot-table derived expression.
  --
  -- Priority order (non-negotiable):
  --   1. Closure  — pending closure request overrides all other states.
  --   2. Open     — ANY remaining open capacity → ABSOLUTE PRIORITY over Pipeline.
  --                 No other branch may override this when open_count > 0.
  --   3. Pipeline — all capacity consumed by pipeline applicants, none hired yet.
  --   4. Open     — default for zero-activity or fully-hired vacancies.
  --                 (Fully-hired → all slots occupied, no open capacity,
  --                  no pipeline — falls through to ELSE 'Open' which is
  --                  overridden by the Closure check for the fully-hired sub-case
  --                  via Priority 4 below.)
  --
  -- Note on fully-hired classification:
  --   When hired_count >= hc_needed AND pipeline_count = 0 AND open_count = 0,
  --   open_count = GREATEST(0, hc_needed - hc_needed - 0) = 0, so Priority 2
  --   is NOT triggered. Pipeline is 0, so Priority 3 is NOT triggered. The
  --   vacancy falls to ELSE 'Open' — which is correct (open for new replacement
  --   hiring) unless there is a pending closure request (Priority 1 fires).
  --   If a separate 'Closed' state is needed for fully-hired, it belongs in a
  --   subsequent migration with explicit business-rule confirmation.
  -- ─────────────────────────────────────────────────────────────────────────
  CASE
    -- Priority 1: Pending closure request overrides everything.
    WHEN bool_or(pc.vacancy_vcode IS NOT NULL)
      THEN 'Closure'

    -- Priority 2: ANY remaining capacity → Open tab.
    -- The GREATEST(0, ...) expression is byte-identical to open_count above.
    -- If open_count > 0, this branch ALWAYS fires before Pipeline is checked.
    WHEN GREATEST(
           0::bigint,
           COALESCE(v.required_headcount::bigint, COUNT(*))
           - COALESCE(MAX(ac.pipeline_count), 0::bigint)
           - COALESCE(MAX(ac.hired_count),    0::bigint)
         ) > 0
      THEN 'Open'

    -- Priority 3: All capacity consumed by pipeline applicants.
    -- NOTE: ONLY applicant-derived pipeline_count — NO slot.status check.
    -- The OR COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline') > 0 clause
    -- that existed in migration 040000 is explicitly REMOVED here.
    WHEN COALESCE(MAX(ac.pipeline_count), 0::bigint) > 0
      THEN 'Pipeline'

    -- Priority 4 (default): Zero-activity vacancy is Open.
    -- Also catches the fully-hired case (no closure request, open_count=0, pipeline=0).
    ELSE 'Open'
  END                                                            AS vacancy_tab,

  -- ─────────────────────────────────────────────────────────────────────────
  -- Aging: how many days has the vacancy been open?
  -- Uses slot history timestamps (aging_basis) — INFORMATIONAL ONLY.
  -- ─────────────────────────────────────────────────────────────────────────
  MIN(COALESCE(ab.open_episode_start, ps.created_at))
    FILTER (WHERE ps.slot_status = 'open')                      AS aging_start_at,

  CASE
    WHEN GREATEST(
      0::bigint,
      COALESCE(v.required_headcount::bigint, COUNT(*))
      - COALESCE(MAX(ac.pipeline_count), 0::bigint)
      - COALESCE(MAX(ac.hired_count),    0::bigint)
    ) = 0 THEN NULL::integer
    WHEN (MIN(COALESCE(ab.open_episode_start, ps.created_at))
          FILTER (WHERE ps.slot_status = 'open'))::date > CURRENT_DATE
      THEN NULL::integer
    ELSE (
      CURRENT_DATE -
      (MIN(COALESCE(ab.open_episode_start, ps.created_at))
       FILTER (WHERE ps.slot_status = 'open'))::date
    )
  END                                                            AS aging_days,

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
  -- Suppress per-store vacancies for stores that belong to active Coverage Groups.
  -- Coverage Group vacancies are served by vw_coverage_group_shadow, not this view.
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Grants (identical to all prior migrations on this view)
-- ─────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- View comment
-- ─────────────────────────────────────────────────────────────────────────────
COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'Slot-derived Vacancy read model. '
  'HARD RULE: vacancy_tab and open_count are derived EXCLUSIVELY from applicant-based counts '
  '(pipeline_count = COUNT(DISTINCT applicant_id) for pipeline statuses; '
  'hired_count = COUNT(DISTINCT applicant_id) for Confirmed Onboard; '
  'open_count = GREATEST(0, hc_needed - pipeline_count - hired_count)). '
  'NO slot.status dependency in vacancy_tab or open_count. '
  'Strict priority: Closure (pending) > Open (open_count > 0) > Pipeline > Open (default). '
  'Debug columns hc_needed/pipeline_count/hired_count/open_count always present for validation. '
  'Prompt: ohm#c8a4f2d1.';

-- ─────────────────────────────────────────────────────────────────────────────
-- VALIDATION QUERIES
-- Run these immediately after applying to confirm correctness.
-- ALL must return the expected results before marking this migration COMPLETE.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── A. Core invariant check ──────────────────────────────────────────────────
-- EXPECT: 0 rows.
-- If ANY row is returned, the implementation is INVALID.
-- SELECT legacy_vcode, store_name, hc_needed, pipeline_count, hired_count, open_count, vacancy_tab
-- FROM public.vw_slot_derived_vacancy_shadow
-- WHERE open_count > 0
--   AND vacancy_tab <> 'Open';

-- ── B. SM Tabuk verification ─────────────────────────────────────────────────
-- EXPECT: open_count >= 1, vacancy_tab = 'Open'
-- SELECT legacy_vcode, store_name, hc_needed, pipeline_count, hired_count, open_count, vacancy_tab
-- FROM public.vw_slot_derived_vacancy_shadow
-- WHERE store_name ILIKE '%tabuk%';

-- ── C. NULL vacancy_tab check ────────────────────────────────────────────────
-- EXPECT: 0 rows. ELSE 'Open' default ensures this can never happen.
-- SELECT COUNT(*) AS null_tab_count
-- FROM public.vw_slot_derived_vacancy_shadow
-- WHERE vacancy_tab IS NULL;

-- ── D. Edge case distribution ────────────────────────────────────────────────
-- Spot-check: verify scenario → tab mapping matches business rules.
-- SELECT
--   CASE
--     WHEN open_count > 0              THEN 'Has open capacity'
--     WHEN pipeline_count > 0          THEN 'Full pipeline (no open capacity)'
--     WHEN hired_count >= hc_needed    THEN 'Fully hired'
--     ELSE                                  'Zero activity'
--   END AS scenario,
--   vacancy_tab,
--   COUNT(*) AS cnt
-- FROM public.vw_slot_derived_vacancy_shadow
-- GROUP BY 1, 2
-- ORDER BY 1, 2;

-- ── E. Tab distribution summary ──────────────────────────────────────────────
-- Useful for before/after comparison.
-- SELECT vacancy_tab, COUNT(*) AS cnt
-- FROM public.vw_slot_derived_vacancy_shadow
-- GROUP BY vacancy_tab
-- ORDER BY cnt DESC;

COMMIT;
