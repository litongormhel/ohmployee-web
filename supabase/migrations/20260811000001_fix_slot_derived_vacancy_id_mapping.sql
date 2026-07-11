-- ============================================================
-- OHM2026_0031 — Fix Slot-Derived Vacancy ID Mapping
-- Migration: 20260811000001_fix_slot_derived_vacancy_id_mapping.sql
--
-- Replaces: 20260810000001_fix_slot_derived_vacancy_closure_tab.sql
--
-- ROOT CAUSE (two issues):
--
--   Issue 1 — Wrong VacancyItem.id (vacancy_coverage FK violation):
--     vw_slot_derived_vacancy_shadow exposes no `id` column (only
--     `slot_id`). _mapVacancy resolves: id = item['id'] ?? item['slot_id']
--     = slot_id (plantilla_slots.id UUID, NOT vacancies.id).
--
--     addVacancyCoverageFromDeployer passes vacancy.id as `vacancy_id`
--     to the vacancy_coverage insert. vacancy_coverage.vacancy_id is an
--     FK to vacancies.id. Inserting a slot UUID violates the FK and/or
--     RLS, causing coverage creation to fail.
--
--   Issue 2 — Empty vcode → applicants RLS 42501:
--     Slots where plantilla_slots.legacy_vcode IS NULL produce
--     VacancyItem.vcode = '' (empty string). addApplicant('', ...) then
--     inserts into applicants with vacancy_vcode = ''. The applicants
--     RLS WITH CHECK requires vacancy_vcode to exist in vacancies within
--     the user's account scope; '' matches nothing → 42501 violation.
--
-- FIX:
--   1. INNER JOIN public.vacancies v ON v.vcode = ps.legacy_vcode
--      AND v.deleted_at IS NULL
--      — The INNER JOIN filters out slots where legacy_vcode IS NULL
--        (NULL keys never match), so only properly-linked slots appear.
--      — Exposes v.id AS legacy_vacancy_id (the real vacancies.id UUID).
--
--   2. Dart _mapVacancy updated to:
--      id = item['id'] ?? item['legacy_vacancy_id'] ?? item['slot_id']
--      — Prefers legacy_vacancy_id so VacancyItem.id = vacancies.id UUID.
--      — Slot UUID is last-resort fallback only.
--
-- SECONDARY BUG INVESTIGATION (applicant update parity):
--   "Dela Cruz, Juanto" appears in multiple vacancies and updating one
--   doesn't consistently update the other. This is EXPECTED LEGACY
--   BEHAVIOR — applicants are keyed by vacancy_vcode (one row per
--   vcode), and updating one vacancy's applicant row is independent of
--   the same person's row in another vacancy. No change required.
--   Slot-derived mode preserves this behavior exactly (fetchApplicants
--   and updateApplicant both query by applicant.id / vacancy_vcode,
--   unchanged from legacy path).
--
-- SCOPE OF CHANGE:
--   — Only vw_slot_derived_vacancy_shadow is replaced.
--   — No RLS policies, tables, triggers, or RPCs are modified.
--   — No Flutter UI layout changes.
--   — Legacy vw_vacancy_list / vw_vacancy_detail are untouched.
--   — HR Emploc / Plantilla / CENCOM are untouched.
--   — Feature flag VacancyService.useSlotDerivedVacancy is unchanged.
--
-- VALIDATION QUERIES (run after applying):
--
--   V1 – legacy_vacancy_id column exists and is non-null for open slots
--     SELECT slot_id, legacy_vacancy_id, legacy_vcode
--       FROM public.vw_slot_derived_vacancy_shadow
--       WHERE slot_status = 'open'
--       LIMIT 5;
--     -- Expect: legacy_vacancy_id populated (non-null UUID) for all rows
--
--   V2 – No null legacy_vcode rows (INNER JOIN excludes them)
--     SELECT COUNT(*) FROM public.vw_slot_derived_vacancy_shadow
--       WHERE legacy_vcode IS NULL;
--     -- Expect: 0
--
--   V3 – No slot_id used as vacancy_id (confirm legacy_vacancy_id ≠ slot_id)
--     SELECT slot_id, legacy_vacancy_id
--       FROM public.vw_slot_derived_vacancy_shadow
--       WHERE slot_id = legacy_vacancy_id;
--     -- Expect: 0 rows (they are from different tables)
--
--   V4 – Closure tab (pending_closure) still works
--     SELECT legacy_vcode, vacancy_tab, has_pending_closure
--       FROM public.vw_slot_derived_vacancy_shadow
--       WHERE has_pending_closure = true
--       LIMIT 5;
--     -- Expect: vacancy_tab = 'Closure' for each row
--
--   V5 – hr_processing and occupied remain excluded
--     SELECT COUNT(*) FROM public.vw_slot_derived_vacancy_shadow sdv
--       JOIN public.plantilla_slots ps ON ps.id = sdv.slot_id
--       WHERE ps.slot_status IN ('hr_processing', 'occupied');
--     -- Expect: 0
--
--   V6 – No duplicate rows
--     SELECT slot_id, COUNT(*) AS cnt
--       FROM public.vw_slot_derived_vacancy_shadow
--       GROUP BY slot_id
--       HAVING COUNT(*) > 1;
--     -- Expect: 0 rows
--
--   V7 – Legacy views untouched
--     SELECT viewname FROM pg_views
--       WHERE schemaname = 'public'
--         AND viewname IN ('vw_vacancy_list', 'vw_vacancy_detail');
--     -- Expect: both rows present
--
-- ROLLBACK:
--   Re-apply 20260810000001_fix_slot_derived_vacancy_closure_tab.sql.
--   Or set VacancyService.useSlotDerivedVacancy = false.
-- ============================================================


-- ============================================================
-- §1  vw_slot_derived_vacancy_shadow (replacement)
-- ============================================================

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
  -- Mirrors the has_pending_closure flag from vw_vacancy_list so the
  -- Flutter Closure tab correctly shows open/pipeline slots awaiting
  -- closure approval.
  SELECT DISTINCT vcr.vacancy_vcode
  FROM public.vacancy_closure_requests vcr
  WHERE vcr.status = 'Pending'
)
SELECT
  -- ── Identity ───────────────────────────────────────────────────────────────
  ps.id                                                    AS slot_id,
  ps.legacy_vcode,
  ps.source_hc_request_id,

  -- legacy_vacancy_id: the vacancies.id UUID for the linked legacy vacancy.
  -- _mapVacancy prefers this for VacancyItem.id so downstream writes
  -- (addVacancyCoverageFromDeployer → vacancy_coverage.vacancy_id FK) pass
  -- the correct legacy UUID instead of the slot UUID. Also fixes the RLS
  -- path for applicants.insert where vacancy scope is verified via vacancies.id.
  v.id                                                     AS legacy_vacancy_id,

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

  -- has_pending_closure: mirrors vw_vacancy_list field of the same name.
  -- True when the slot's legacy vacancy has an active Pending closure request.
  (pc.vacancy_vcode IS NOT NULL)                           AS has_pending_closure,

  -- vacancy_tab: Vacancy module tab this slot maps to.
  -- Priority:
  --   1. Pending closure request → 'Closure'   (overrides slot status)
  --   2. slot_status = 'pipeline' → 'Pipeline'
  --   3. slot_status = 'open'     → 'Open'
  --   4. slot_status = 'closed'   → 'Closure'
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
-- INNER JOIN vacancies to:
--   (a) expose v.id as legacy_vacancy_id for correct FK writes downstream
--   (b) implicitly exclude slots where legacy_vcode IS NULL (INNER JOIN
--       on a NULL key matches nothing, filtering those rows out)
--   (c) ensure only slots linked to a live (non-deleted) legacy vacancy
--       are visible in the Vacancy module
INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
  AND v.deleted_at IS NULL

-- SHADOW VIEW SCOPE: Vacancy module tabs only.
-- hr_processing and occupied are excluded — they belong to HR Emploc and
-- Plantilla respectively and must not appear in the Vacancy read model.
WHERE ps.slot_status IN ('open', 'pipeline', 'closed');

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'SHADOW VIEW — OHM2026_0031 (replaces OHM2026_0030). '
  'Read-only, not wired to any UI except behind VacancyService.useSlotDerivedVacancy flag. '
  'INNER JOIN vacancies on legacy_vcode ensures: (1) slots with null legacy_vcode are '
  'excluded (prevents empty-vcode RLS failures on applicants.insert), (2) legacy_vacancy_id '
  '(= vacancies.id UUID) is always populated so _mapVacancy sets VacancyItem.id correctly '
  'for vacancy_coverage FK writes. Closure tab fix from OHM2026_0030 (has_pending_closure, '
  'vacancy_tab priority rule) is preserved. '
  'Excludes hr_processing and occupied slots (HR Emploc and Plantilla owners). '
  'SECURITY INVOKER — inherits caller RLS via plantilla_slots_read_scoped policy.';


-- ============================================================
-- §2  Grants
-- ============================================================

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;
