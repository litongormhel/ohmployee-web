-- OHM2026_0070 — Fix: archived vacancies appear in Vacancy Open / Pipeline tabs
-- ─────────────────────────────────────────────────────────────────────────────
-- Root cause:
--   vw_slot_derived_vacancy_shadow (Phase D / Phase 7 read path) INNER JOINs
--   vacancies with only `v.deleted_at IS NULL`. Archived vacancies — those
--   with `is_archived = true` set by handle_closure_approval (closure approval
--   trigger) or archive_vacancy_record (manual Super Admin archive) — pass
--   through that JOIN predicate and remain visible in the shadow view. Because
--   the Phase 7 Flutter path reads exclusively from this view, archived VCODEs
--   appear in the Open and Pipeline tabs despite being archived/closed.
--
-- Fix (primary):
--   Add `AND COALESCE(v.is_archived, false) = false` to the INNER JOIN
--   predicate on vacancies so archived rows are excluded at the view layer.
--   Expose `v.is_archived` in the SELECT so Flutter's _mapVacancy() can
--   populate VacancyItem.isArchived for the defensive frontend guard.
--
-- Closure approval side-effect (confirmed correct — no change needed):
--   handle_closure_approval() trigger already atomically marks the vacancy:
--     status = 'Closed', is_archived = true, archived_at = NOW()
--   After this migration the closed vacancy will also disappear from the
--   shadow view, resolving the Open-tab appearance.
--
-- Restore conflict protection (confirmed correct — no change needed):
--   restore_vacancy_record RPC already:
--     (a) blocks restore if `is_archived = false` (not archived)
--     (b) checks for Open slot conflict (same store_id + position_id)
--   VCODE uniqueness is DB-enforced (vacancies_vcode_key UNIQUE constraint),
--   so there is always exactly one vacancies row per VCODE — a "duplicate
--   active VCODE" scenario is architecturally impossible.
--
-- Scope: vw_slot_derived_vacancy_shadow (VCODE-grain, Phase D aggregation).
--   vw_slot_derived_vacancy_shadow_detail is UNWIRED and receives the same
--   guard for consistency.
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop detail view first (not a dependency of the main view but dropped to
-- allow clean recreation; it is UNWIRED — no UI reads it in Phase D).
DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow_detail;
DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow;


-- ── §1  vw_slot_derived_vacancy_shadow — VCODE-grain (Phase D) ───────────────
-- Recreated from 20260820000000_vcode_slot_phase_d_shadow_aggregation.sql §D1.
-- Change vs. previous: INNER JOIN now also filters COALESCE(v.is_archived,false)=false.
-- Change vs. previous: v.is_archived exposed in SELECT for Flutter defensive guard.

CREATE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  -- Most recent transition INTO 'open' per slot = start of current open episode.
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
),
pending_closure AS (
  -- VCODEs with an active Pending closure request (VCODE-level override, Q8).
  SELECT DISTINCT vcr.vacancy_vcode
  FROM public.vacancy_closure_requests vcr
  WHERE vcr.status = 'Pending'
)
SELECT
  -- ── VCODE key (grain) ─────────────────────────────────────────────────────
  ps.legacy_vcode,

  -- ── Identity — authoritative per-VCODE fields from vacancies ─────────────
  v.id                                                          AS legacy_vacancy_id,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,

  -- Archive state — exposed so Flutter _mapVacancy() can set VacancyItem.isArchived
  -- and _tabbedForIndex() can apply the defensive frontend guard.
  -- Will always be false for rows in this view (archived rows excluded by JOIN),
  -- but the explicit projection keeps the contract stable if the JOIN predicate
  -- is ever conditionally relaxed for audit/admin reads.
  v.is_archived,

  -- ── Store detail (constant per VCODE; roving excluded in WHERE) ───────────
  (ARRAY_AGG(ps.store_id   ORDER BY ps.created_at, ps.id::text))[1] AS store_id,
  MIN(st.store_branch)                                               AS store_branch,

  -- ── Org scope (constant per VCODE) ───────────────────────────────────────
  (ARRAY_AGG(ps.account_id ORDER BY ps.created_at, ps.id::text))[1] AS account_id,
  MIN(a.account_name)                                                AS account_name,
  (ARRAY_AGG(ps.group_id   ORDER BY ps.created_at, ps.id::text))[1] AS group_id,
  MIN(g.group_name)                                                  AS group_name,

  -- ── Position definition (constant per VCODE) ─────────────────────────────
  MIN(ps.position)                                              AS position,
  MIN(ps.employment_type)                                       AS employment_type,
  -- is_roving = false for every row: roving slots are excluded in WHERE
  false                                                         AS is_roving,

  -- ── HC counts (Q3 aggregation table) ─────────────────────────────────────
  COUNT(*)                                                      AS required_hc,
  COUNT(*) FILTER (WHERE ps.slot_status = 'open')               AS open_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')           AS pipeline_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')      AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')           AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')             AS closed_count,

  -- active_applicant_count = pipeline_count (Phase B one-active-per-slot invariant).
  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')           AS active_applicant_count,

  -- ── Pending closure flag (VCODE-level) ───────────────────────────────────
  bool_or(pc.vacancy_vcode IS NOT NULL)                         AS has_pending_closure,

  -- ── Vacancy tab — Q4 priority (exactly one tab per VCODE) ────────────────
  -- P1: pending closure override → Closure
  -- P2: open_count > 0            → Open
  -- P3: pipeline_count > 0        → Pipeline
  -- P4: all slots closed          → Closure
  -- P5: only hr_processing / occupied remain → NULL (excluded from list)
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

  -- ── Aging — oldest open-episode start among open slots (Q7) ──────────────
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

  -- ── Timestamps ────────────────────────────────────────────────────────────
  MIN(ps.created_at)                                            AS created_at,
  MAX(ps.updated_at)                                            AS updated_at,
  MAX(ps.closed_at)                                             AS closed_at,

  -- ── HC request seed ───────────────────────────────────────────────────────
  (ARRAY_AGG(ps.source_hc_request_id ORDER BY ps.created_at, ps.id::text))[1] AS source_hc_request_id,

  -- ── Legacy vacancy snapshot fields (parity with vw_vacancy_list) ─────────
  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name

FROM public.plantilla_slots ps

LEFT JOIN aging_basis ab
  ON ab.slot_id = ps.id

LEFT JOIN public.stores st
  ON st.id = ps.store_id

LEFT JOIN public.accounts a
  ON a.id = ps.account_id

LEFT JOIN public.groups g
  ON g.id = ps.group_id

LEFT JOIN pending_closure pc
  ON pc.vacancy_vcode = ps.legacy_vcode

-- INNER JOIN vacancies:
--   (a) exposes v.id as legacy_vacancy_id for correct FK writes downstream
--   (b) implicitly excludes NULL-legacy_vcode slots (INNER JOIN on NULL key
--       matches nothing, filtering those rows out)
--   (c) ensures only slots linked to a live, non-deleted, non-archived vacancy
--       are visible — archived vacancies (is_archived = true) are excluded here
INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
  AND v.deleted_at IS NULL
  AND COALESCE(v.is_archived, false) = false  -- PRIMARY FIX: exclude archived vacancies

-- SCOPE: exclude roving slots and NULL-legacy_vcode slots
WHERE ps.legacy_vcode IS NOT NULL
  AND ps.is_roving = false

-- GROUP BY: legacy_vcode is the VCODE-grain key.
-- v.id in GROUP BY allows all v.* columns to be selected without enumeration
-- (PostgreSQL detects functional dependency on the PK).
GROUP BY
  ps.legacy_vcode,
  v.id;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'SHADOW VIEW — OHM2026_0070 (archived exclusion fix). '
  'Based on Phase D aggregation (20260820000000). '
  'VCODE-grain: 1 row = 1 legacy_vcode / vacancy card. '
  'Aggregates per-slot status into per-VCODE counts: required_hc, open_count, '
  'pipeline_count, hr_processing_count, occupied_count, closed_count. '
  'vacancy_tab derived by Q4 priority. '
  'Archived vacancies excluded: COALESCE(v.is_archived, false) = false in JOIN. '
  'v.is_archived exposed in SELECT for Flutter defensive isArchived guard. '
  'Roving + NULL-legacy_vcode excluded before grouping. '
  'SECURITY INVOKER — inherits caller RLS via plantilla_slots_read_scoped policy.';


-- ── §2  vw_slot_derived_vacancy_shadow_detail — slot-grain companion ──────────
-- UNWIRED in Phase D (no UI reads it directly). Receives the same is_archived
-- guard for consistency. Recreated from 20260820000000 §D2 with guard added.

CREATE VIEW public.vw_slot_derived_vacancy_shadow_detail
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
)
SELECT
  ps.id                                                         AS slot_id,
  ps.legacy_vcode,
  ps.slot_ordinal,
  ps.slot_status,
  ps.source_hc_request_id,
  v.id                                                          AS legacy_vacancy_id,
  v.is_archived,
  ps.store_id,
  st.store_branch,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,
  ps.account_id,
  a.account_name,
  ps.group_id,
  g.group_name,
  ps.position,
  ps.employment_type,
  false                                                         AS is_roving,
  ps.created_at,
  ps.updated_at,
  ps.closed_at,
  COALESCE(ab.open_episode_start, ps.created_at)               AS aging_start_at,
  CASE
    WHEN COALESCE(ab.open_episode_start, ps.created_at)::date > CURRENT_DATE
      THEN NULL::integer
    ELSE (CURRENT_DATE - COALESCE(ab.open_episode_start, ps.created_at)::date)
  END                                                           AS aging_days,
  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name

FROM public.plantilla_slots ps

LEFT JOIN aging_basis ab
  ON ab.slot_id = ps.id

LEFT JOIN public.stores st
  ON st.id = ps.store_id

LEFT JOIN public.accounts a
  ON a.id = ps.account_id

LEFT JOIN public.groups g
  ON g.id = ps.group_id

INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
  AND v.deleted_at IS NULL
  AND COALESCE(v.is_archived, false) = false  -- same guard as list view

WHERE ps.legacy_vcode IS NOT NULL
  AND ps.is_roving = false;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow_detail IS
  'SLOT-GRAIN COMPANION — OHM2026_0070 (archived exclusion fix). '
  'UNWIRED in Phase D. Slot-grain drill-down for vw_slot_derived_vacancy_shadow. '
  'Receives same is_archived guard for consistency.';


-- ── §3  Grants ────────────────────────────────────────────────────────────────

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow_detail TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow_detail TO service_role;
