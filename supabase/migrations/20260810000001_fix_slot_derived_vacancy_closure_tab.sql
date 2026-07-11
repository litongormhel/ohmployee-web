-- ============================================================
-- OHM2026_0030 — Fix Slot-Derived Vacancy Closure Tab Mapping
-- Migration: 20260810000000_fix_slot_derived_vacancy_closure_tab.sql
--
-- Replaces: 20260809000000_vw_slot_derived_vacancy_shadow.sql
--
-- ROOT CAUSE:
--   The original vw_slot_derived_vacancy_shadow only mapped
--   slot_status = 'closed' → 'Closure'. It did NOT join
--   vacancy_closure_requests, so the has_pending_closure column
--   was absent from every slot-derived row. The Flutter vacancy
--   screen classifies Closure tab membership exclusively by
--   VacancyItem.hasPendingClosure (from item['has_pending_closure']),
--   which defaulted to false for all slot rows. A vacancy with an
--   active pending closure request kept slot_status = 'open' or
--   'pipeline', so it never appeared in the Closure tab.
--
-- FIX:
--   1. Add a pending_closure CTE that collects all legacy_vcodes
--      with an active (status = 'Pending') closure request.
--   2. LEFT JOIN the CTE into the view on legacy_vcode.
--   3. Expose has_pending_closure (boolean) — mirrors the field
--      exposed by vw_vacancy_list so the Flutter client's
--      _mapVacancy() can read it unchanged.
--   4. Override vacancy_tab to 'Closure' when a pending closure
--      request exists, regardless of slot_status — matches legacy
--      vw_vacancy_list behavior where a pending closure request on
--      an Open vacancy causes it to appear in the Closure tab.
--
-- MAPPING RULE (priority order):
--   has_pending_closure (status='Pending' request) → 'Closure'
--   slot_status = 'pipeline'                       → 'Pipeline'
--   slot_status = 'open'                           → 'Open'
--   slot_status = 'closed'                         → 'Closure'
--   (hr_processing / occupied remain excluded)
--
-- NO BEHAVIOR CHANGE outside Closure tab:
--   Open and Pipeline tab rows are unchanged unless they carry a
--   pending closure request. No legacy views, tables, or RPCs
--   are modified. The feature flag in vacancy_service.dart is
--   unchanged.
--
-- VALIDATION QUERIES (run manually after applying):
--
--   V1 – View replaces correctly
--     SELECT viewname FROM pg_views
--       WHERE schemaname = 'public'
--         AND viewname = 'vw_slot_derived_vacancy_shadow';
--     -- Expect: 1 row
--
--   V2 – has_pending_closure column exists
--     SELECT column_name FROM information_schema.columns
--       WHERE table_schema = 'public'
--         AND table_name   = 'vw_slot_derived_vacancy_shadow'
--         AND column_name  = 'has_pending_closure';
--     -- Expect: 1 row
--
--   V3 – Pending closure vacancies map to Closure tab
--     SELECT ps.legacy_vcode, sdv.vacancy_tab, sdv.has_pending_closure
--       FROM public.vw_slot_derived_vacancy_shadow sdv
--       JOIN public.vacancy_closure_requests vcr
--         ON vcr.vacancy_vcode = sdv.legacy_vcode
--            AND vcr.status = 'Pending'
--       JOIN public.plantilla_slots ps ON ps.id = sdv.slot_id;
--     -- Expect: vacancy_tab = 'Closure', has_pending_closure = true
--       for every row with a pending request
--
--   V4 – Open/Pipeline rows without pending requests are unchanged
--     SELECT vacancy_tab, COUNT(*)
--       FROM public.vw_slot_derived_vacancy_shadow
--       WHERE has_pending_closure = false
--       GROUP BY vacancy_tab;
--     -- Expect: Open, Pipeline, Closure (for closed slots)
--       counts unchanged vs previous view definition
--
--   V5 – hr_processing and occupied remain excluded
--     SELECT COUNT(*) FROM public.vw_slot_derived_vacancy_shadow sdv
--       JOIN public.plantilla_slots ps ON ps.id = sdv.slot_id
--       WHERE ps.slot_status IN ('hr_processing', 'occupied');
--     -- Expect: 0
--
--   V6 – No duplicate rows (one row per slot_id)
--     SELECT slot_id, COUNT(*) AS cnt
--       FROM public.vw_slot_derived_vacancy_shadow
--       GROUP BY slot_id
--       HAVING COUNT(*) > 1;
--     -- Expect: 0 rows
--
--   V7 – Legacy views are untouched
--     SELECT viewname FROM pg_views
--       WHERE schemaname = 'public'
--         AND viewname IN ('vw_vacancy_list','vw_vacancy_detail');
--     -- Expect: both present, definitions unchanged
-- ============================================================


-- ============================================================
-- §1  vw_slot_derived_vacancy_shadow (replacement)
-- ============================================================
-- SHADOW ONLY — not consumed by any UI except behind the
-- VacancyService.useSlotDerivedVacancy feature flag.
-- Legacy vw_vacancy_list / vw_vacancy_detail remain authoritative.

DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow;

CREATE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  -- Most recent transition INTO open per slot.
  -- new_value = 'open' covers the initial 'created' event and future
  -- 'reopened' / 'resigned' reopen events. One row per slot.
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
),
pending_closure AS (
  -- legacy_vcodes that have at least one active Pending closure request.
  -- Used to mirror the has_pending_closure flag from vw_vacancy_list so
  -- the Flutter Closure tab (which is gated exclusively on this boolean)
  -- correctly shows open/pipeline slots awaiting closure approval.
  SELECT DISTINCT vcr.vacancy_vcode
  FROM public.vacancy_closure_requests vcr
  WHERE vcr.status = 'Pending'
)
SELECT
  -- ── Identity ───────────────────────────────────────────────────────────────
  ps.id                                                    AS slot_id,
  ps.legacy_vcode,
  ps.source_hc_request_id,

  -- ── Location ───────────────────────────────────────────────────────────────
  ps.store_id,
  st.store_name,
  st.store_branch,
  st.area_city,
  st.province,

  -- ── Org scope ──────────────────────────────────────────────────────────────
  ps.account_id,
  a.account_name,
  ps.group_id,
  g.group_name,

  -- ── Position definition ────────────────────────────────────────────────────
  ps.position,
  ps.employment_type,
  ps.is_roving,

  -- ── Lifecycle state ────────────────────────────────────────────────────────
  ps.slot_status,

  -- has_pending_closure: mirrors the vw_vacancy_list field of the same name.
  -- True when the slot's legacy vacancy has an active Pending closure request.
  -- The Flutter vacancy screen uses this boolean as the sole gate for Closure
  -- tab membership (VacancyItem.hasPendingClosure in _tabbedForIndex index 3).
  (pc.vacancy_vcode IS NOT NULL)                           AS has_pending_closure,

  -- vacancy_tab: the Vacancy module tab this slot maps to.
  --
  -- Priority:
  --   1. Pending closure request → 'Closure'   (overrides slot status)
  --   2. slot_status = 'pipeline' → 'Pipeline'
  --   3. slot_status = 'open'     → 'Open'
  --   4. slot_status = 'closed'   → 'Closure'
  --
  -- A pending closure request takes priority over slot status so that an Open
  -- or Pipeline vacancy with an in-flight closure request immediately leaves
  -- the Open / Pipeline tab and appears in the Closure tab — matching the
  -- legacy vw_vacancy_list behaviour where has_pending_closure = true drives
  -- the Closure tab filter in _tabbedForIndex.
  --
  -- hr_processing and occupied are excluded by the WHERE clause below.
  CASE
    WHEN pc.vacancy_vcode IS NOT NULL THEN 'Closure'
    WHEN ps.slot_status = 'pipeline'  THEN 'Pipeline'
    WHEN ps.slot_status = 'open'      THEN 'Open'
    WHEN ps.slot_status = 'closed'    THEN 'Closure'
  END                                                      AS vacancy_tab,

  -- ── Timestamps ─────────────────────────────────────────────────────────────
  ps.created_at,
  ps.updated_at,
  ps.closed_at,
  ps.closure_reason_code,

  -- ── Aging (open-episode basis) ─────────────────────────────────────────────
  -- aging_start_at: start of the slot's current open episode.
  -- NULL for closed slots (no active open episode).
  CASE
    WHEN ps.slot_status IN ('open', 'pipeline')
      THEN COALESCE(ab.open_episode_start, ps.created_at)
    ELSE NULL
  END                                                      AS aging_start_at,

  -- aging_days: NULL for closed slots and advance vacancies (future-dated
  -- open episode start), consistent with fn_cencom_td_aging_bucket.
  CASE
    WHEN ps.slot_status NOT IN ('open', 'pipeline')        THEN NULL
    WHEN COALESCE(ab.open_episode_start, ps.created_at)::date > CURRENT_DATE
                                                           THEN NULL
    ELSE (CURRENT_DATE - COALESCE(ab.open_episode_start, ps.created_at)::date)
  END                                                      AS aging_days,

  -- ── Occupant ───────────────────────────────────────────────────────────────
  -- Always NULL for open/pipeline/closed slots in the current lifecycle.
  -- Occupied slots are excluded by the WHERE clause.
  ps.current_occupant_plantilla_id

FROM public.plantilla_slots ps
-- Open-episode aging basis
LEFT JOIN aging_basis ab
  ON ab.slot_id = ps.id
-- Store details (NULL-safe: roving slots have store_id = NULL)
LEFT JOIN public.stores st
  ON st.id = ps.store_id
-- Account name for display
LEFT JOIN public.accounts a
  ON a.id = ps.account_id
-- Group name for display
LEFT JOIN public.groups g
  ON g.id = ps.group_id
-- Pending closure requests via legacy_vcode bridge
LEFT JOIN pending_closure pc
  ON pc.vacancy_vcode = ps.legacy_vcode

-- SHADOW VIEW SCOPE: Vacancy module tabs only.
-- hr_processing and occupied are excluded — they belong to HR Emploc and
-- Plantilla respectively and must not appear in the Vacancy read model.
WHERE ps.slot_status IN ('open', 'pipeline', 'closed');

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'SHADOW VIEW — OHM2026_0030 (replaces OHM2026_0010). '
  'Read-only, not wired to any UI except behind VacancyService.useSlotDerivedVacancy flag. '
  'Exposes plantilla_slots rows in Open / Pipeline / Closure tabs with has_pending_closure '
  'and vacancy_tab correctly derived from vacancy_closure_requests. '
  'Pending closure requests override slot_status for vacancy_tab so that open/pipeline '
  'slots with in-flight closure requests appear in the Closure tab, matching legacy '
  'vw_vacancy_list behaviour. '
  'Excludes hr_processing and occupied slots (HR Emploc and Plantilla owners). '
  'SECURITY INVOKER — inherits caller RLS via plantilla_slots_read_scoped policy.';


-- ============================================================
-- §2  Grants
-- ============================================================

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;
