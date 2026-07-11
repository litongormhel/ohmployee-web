-- ============================================================
-- OHM2026_0010 — Shadow Slot-Derived Vacancy View
-- Migration: 20260809000000_vw_slot_derived_vacancy_shadow.sql
-- Depends on:
--   20260804000000_plantilla_slot_foundation_v1.sql
--     (plantilla_slots, slot_history, slot_reason_codes)
--   20260805000000_fn_create_slots_from_hc_request.sql
--   20260806000000_wire_slot_creation_into_hc_completion.sql
--     (source_hc_request_id on plantilla_slots)
--   20260807000000_plantilla_slots_legacy_vcode_link.sql
--     (legacy_vcode on plantilla_slots)
--   20260808000000_drop_obsolete_2arg_slot_rpc.sql
--   Pre-existing: stores, accounts, groups
-- ============================================================
-- SHADOW VIEW — READ ONLY, NOT WIRED TO ANY UI.
--
--   This migration creates a single SQL view:
--     public.vw_slot_derived_vacancy_shadow
--
--   PURPOSE:
--     Reconciliation and validation artifact that exposes the
--     slot-derived equivalent of the Vacancy module's Open /
--     Pipeline / Closure tabs, reading exclusively from
--     plantilla_slots and slot_history.
--
--   WHAT THIS IS NOT:
--     • NOT the current Vacancy UI read source.
--     • NOT a replacement for vw_vacancy_list / vw_vacancy_detail.
--     • NOT consumed by any Flutter or Next.js screen.
--     • NOT a materialized view.
--     • Legacy vacancies remain the AUTHORITATIVE read source for
--       all UI through Phase 6 of the read-model adoption sequence
--       (see docs/architecture/slot_derived_vacancy_read_model.md §9).
--
--   NO BEHAVIOR CHANGE:
--     No existing table, view, RPC, trigger, index, or RLS policy
--     is modified. No existing UI behavior changes. This migration
--     is additive and creates only a new view.
--
--   SLOT STATUS → VACANCY TAB MAPPING:
--     open        → 'Open'
--     pipeline    → 'Pipeline'
--     closed      → 'Closure'
--     hr_processing → EXCLUDED (HR Emploc module owns this state)
--     occupied      → EXCLUDED (Plantilla module owns this state)
--
--   AGING BASIS:
--     Aging is a slot property, continuous within an open episode.
--     The open-episode start is the most recent slot_history row
--     with new_value = 'open' (covers the initial 'created' event
--     and future 'reopened' / 'resigned' reopen events).
--     Fallback: plantilla_slots.created_at.
--     Advance vacancies (future-dated open episode start) yield
--     aging_days = NULL, consistent with fn_cencom_td_aging_bucket.
--
--   SECURITY:
--     SECURITY INVOKER — the caller's identity and RLS apply.
--     plantilla_slots RLS (plantilla_slots_read_scoped) enforces
--     full-access OR account_id = ANY(get_my_allowed_account_ids())
--     on every row returned, so scope isolation is automatic.
--
--   GRANTS:
--     Consistent with CENCOM phase-8a view pattern.
--
-- Sections:
--   §1  vw_slot_derived_vacancy_shadow
--   §2  Grants
--
-- Validation Queries (run manually after applying):
--   V1 – View exists
--     SELECT viewname FROM pg_views
--       WHERE schemaname = 'public'
--         AND viewname   = 'vw_slot_derived_vacancy_shadow';
--
--   V2 – Returns current slot rows (will be 0 if no slots yet)
--     SELECT COUNT(*) FROM public.vw_slot_derived_vacancy_shadow;
--
--   V3 – hr_processing and occupied are excluded
--     SELECT COUNT(*) FROM public.vw_slot_derived_vacancy_shadow
--       WHERE slot_status IN ('hr_processing', 'occupied');
--     -- Expect: 0 rows
--
--   V4 – vacancy_tab mapping is correct
--     SELECT slot_status, vacancy_tab, COUNT(*)
--       FROM public.vw_slot_derived_vacancy_shadow
--       GROUP BY slot_status, vacancy_tab
--       ORDER BY slot_status;
--     -- Expect: open→Open, pipeline→Pipeline, closed→Closure
--
--   V5 – No legacy views or tables were modified
--     SELECT viewname FROM pg_views
--       WHERE schemaname = 'public'
--         AND viewname IN ('vw_vacancy_list','vw_vacancy_detail');
--     -- Expect: both still present, definitions unchanged
--
--   V6 – Reconciliation: slot-derived vs legacy vacancy counts per account
--     SELECT
--       shadow.account_id,
--       shadow.vacancy_tab,
--       COUNT(*) AS slot_count
--     FROM public.vw_slot_derived_vacancy_shadow shadow
--     GROUP BY shadow.account_id, shadow.vacancy_tab
--     ORDER BY shadow.account_id, shadow.vacancy_tab;
--     -- Compare against legacy:
--     SELECT account_id, derived_status, COUNT(*)
--       FROM public.vw_vacancy_list
--       WHERE derived_status IN ('Open','Pipeline')
--       GROUP BY account_id, derived_status;
--
--   V7 – Slot-to-legacy 1:1 reconciliation via legacy_vcode
--     SELECT
--       ps.id          AS slot_id,
--       ps.legacy_vcode,
--       v.vcode        AS legacy_vcode_match,
--       ps.slot_status,
--       v.status       AS legacy_status
--     FROM public.vw_slot_derived_vacancy_shadow ps
--     LEFT JOIN public.vacancies v ON v.vcode = ps.legacy_vcode
--     WHERE ps.legacy_vcode IS NOT NULL
--     ORDER BY ps.created_at DESC
--     LIMIT 50;
--     -- Expect: legacy_vcode = vcode for all rows created via HC request
--       --       after migration 20260807000000 was applied.
-- ============================================================


-- ============================================================
-- §1  vw_slot_derived_vacancy_shadow
-- ============================================================
-- SHADOW ONLY — not consumed by any UI.
-- Legacy vw_vacancy_list / vw_vacancy_detail remain authoritative.
-- No behavior change. See file header for full context.

DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow;

CREATE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  -- Most recent transition INTO open per slot.
  -- new_value = 'open' covers both the initial 'created' event and future
  -- 'reopened' / 'resigned' reopen events (a resignation that reopens a slot
  -- starts a new open episode and resets aging per the locked architecture).
  -- Rows are deduplicated to one per slot (most recent wins).
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
)
SELECT
  -- ── Identity ───────────────────────────────────────────────────────────────
  ps.id                                               AS slot_id,
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

  -- ── Position definition ─────────────────────────────────────────────────────
  ps.position,
  ps.employment_type,
  ps.is_roving,

  -- ── Lifecycle state ─────────────────────────────────────────────────────────
  ps.slot_status,

  -- vacancy_tab: the Vacancy module tab this slot maps to.
  -- hr_processing and occupied are excluded at the WHERE clause below.
  CASE ps.slot_status
    WHEN 'open'     THEN 'Open'
    WHEN 'pipeline' THEN 'Pipeline'
    WHEN 'closed'   THEN 'Closure'
  END                                                 AS vacancy_tab,

  -- ── Timestamps ─────────────────────────────────────────────────────────────
  ps.created_at,
  ps.updated_at,
  ps.closed_at,
  ps.closure_reason_code,

  -- ── Aging (open-episode basis) ─────────────────────────────────────────────
  -- aging_start_at: start of the slot's current open episode for open and
  -- pipeline slots. NULL for closed slots (no active open episode).
  -- Source: most recent slot_history row with new_value = 'open'; falls back
  -- to plantilla_slots.created_at when slot_history has no 'open' transition.
  CASE
    WHEN ps.slot_status IN ('open', 'pipeline')
      THEN COALESCE(ab.open_episode_start, ps.created_at)
    ELSE NULL
  END                                                 AS aging_start_at,

  -- aging_days: NULL when slot is closed, NULL for advance vacancies
  -- (open_episode_start is in the future), consistent with CENCOM aging.
  CASE
    WHEN ps.slot_status NOT IN ('open', 'pipeline')   THEN NULL
    WHEN COALESCE(ab.open_episode_start, ps.created_at)::date > CURRENT_DATE
                                                       THEN NULL
    ELSE (CURRENT_DATE - COALESCE(ab.open_episode_start, ps.created_at)::date)
  END                                                 AS aging_days,

  -- ── Occupant ───────────────────────────────────────────────────────────────
  -- current_occupant_plantilla_id is always NULL for open/pipeline/closed
  -- slots in the current lifecycle (occupied slots are excluded by the WHERE
  -- clause). Included for schema completeness and future consistency.
  ps.current_occupant_plantilla_id

FROM public.plantilla_slots ps
-- open-episode aging basis
LEFT JOIN aging_basis ab
  ON ab.slot_id = ps.id
-- store details (NULL-safe: roving slots have store_id = NULL)
LEFT JOIN public.stores st
  ON st.id = ps.store_id
-- account name for display
LEFT JOIN public.accounts a
  ON a.id = ps.account_id
-- group name for display
LEFT JOIN public.groups g
  ON g.id = ps.group_id

-- SHADOW VIEW SCOPE: Vacancy module tabs only.
-- hr_processing and occupied are excluded — they belong to HR Emploc and
-- Plantilla respectively and must not appear in the Vacancy read model.
WHERE ps.slot_status IN ('open', 'pipeline', 'closed');

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'SHADOW VIEW — OHM2026_0010. Read-only, not wired to any UI. '
  'Exposes plantilla_slots rows in the Vacancy module''s Open / Pipeline / Closure '
  'tabs for reconciliation against the legacy vw_vacancy_list / vw_vacancy_detail. '
  'Excludes hr_processing and occupied slots (HR Emploc and Plantilla owners). '
  'Legacy vacancies remain the authoritative UI read source through the full '
  'slot-derived Vacancy read model transition (see slot_derived_vacancy_read_model.md). '
  'SECURITY INVOKER — inherits caller RLS via plantilla_slots_read_scoped policy.';


-- ============================================================
-- §2  Grants
-- ============================================================
-- Consistent with CENCOM phase-8a view grant pattern
-- (20260520600000_cencom_phase8a_target_deployment_backend.sql).

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;
