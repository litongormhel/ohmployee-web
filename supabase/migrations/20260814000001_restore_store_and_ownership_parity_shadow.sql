-- ============================================================
-- OHM2026_0032B — Restore Store and Ownership Parity in Slot Derived Vacancy View
-- Migration: 20260814000001_restore_store_and_ownership_parity_shadow.sql
--
-- Replaces: 20260814000000_restore_shadow_view_parity_fields.sql
--
-- PURPOSE:
--   Restore store_name, area_city, province, area_name,
--   triggered_by_user_id, and triggered_by_name fields
--   projected from the legacy vacancies snapshot to provide
--   perfect alignment in slot-derived mode.
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

  -- ── Location (Vacancy snapshot values mapped for store and area parity) ──
  ps.store_id,
  v.store_name,
  st.store_branch,
  v.area_city,
  v.province,
  v.area_name,

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
  ps.current_occupant_plantilla_id,

  -- ── Legacy Vacancy Detail Parity Fields (OHM2026_0032A & OHM2026_0032B) ────
  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name

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
  'SHADOW VIEW — OHM2026_0032B (replaces OHM2026_0032A). '
  'Read-only, not wired to any UI except behind VacancyService.useSlotDerivedVacancy flag. '
  'INNER JOIN vacancies on legacy_vcode ensures: (1) slots with null legacy_vcode are '
  'excluded (prevents empty-vcode RLS failures on applicants.insert), (2) legacy_vacancy_id '
  '(= vacancies.id UUID) is always populated so _mapVacancy sets VacancyItem.id correctly '
  'for vacancy_coverage FK writes. Closure tab fix from OHM2026_0030 (has_pending_closure, '
  'vacancy_tab priority rule) is preserved. Projects urgency_level, hrco_name, hrco_user_id, '
  'and target_fill_date for legacy parity. Projects store_name, area_city, province, '
  'and area_name FROM vacancies table snapshot values (v.*) instead of store (st.*), '
  'and exposes triggered_by_user_id and triggered_by_name for full parity. '
  'Excludes hr_processing and occupied slots (HR Emploc and Plantilla owners). '
  'SECURITY INVOKER — inherits caller RLS via plantilla_slots_read_scoped policy.';


-- ============================================================
-- §2  Grants
-- ============================================================

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;
