-- ============================================================
-- OHM2026_0048 — VCODE ↔ Slot Phase D: Shadow View Aggregation
-- Migration: 20260820000000_vcode_slot_phase_d_shadow_aggregation.sql
--
-- Depends on:
--   20260819000000_vcode_slot_phase_c_hr_emploc_binding.sql
--     (Phase C VERIFIED GREEN — per-slot open/pipeline/hr_processing correct;
--      hr_emploc.slot_id is the HR-side source of truth)
--   20260814000001_restore_store_and_ownership_parity_shadow.sql
--     (current slot-grain shadow with store/ownership parity fields)
-- ============================================================
-- Scope: Phase D shadow view re-aggregation.
--
-- Authorising documents (locked):
--   docs/architecture/vcode_slot_bridge_redesign.md (OHM2026_0035) §3, §6, §7
--   docs/architecture/vcode_slot_phase_d_shadow_aggregation_plan.md (OHM2026_0047)
--
-- Phase D changes the grain of vw_slot_derived_vacancy_shadow from
-- slot-grain (1 row = 1 slot) to VCODE-grain (1 row = 1 legacy_vcode /
-- vacancy card). All five slot-status counts are aggregated per VCODE.
-- The vacancy_tab is derived by the Q4 priority table. Aging is the
-- oldest open-episode start among the VCODE's open slots (Q7).
--
-- A companion slot-grain detail view (vw_slot_derived_vacancy_shadow_detail)
-- is created as the drill-down seam (Q9). The UI is not wired to it in
-- Phase D; it is structural only.
--
-- Both views remain UNWIRED (shadow only). Legacy vacancies stays
-- authoritative for the UI until the flag-gated read cutover (Phase G).
--
-- What this migration does:
--   D1  DROP and recreate vw_slot_derived_vacancy_shadow — VCODE-grain
--   D2  CREATE vw_slot_derived_vacancy_shadow_detail — slot-grain companion
--   D3  Grants
--   D4  Post-migration validation queries (manual, in comments)
--
-- What this migration deliberately does NOT do:
--   • Wire any UI to the new grain
--   • Modify Flutter UI, RPCs, RLS, or lifecycle helpers
--   • Implement closure fan-out (Phase E)
--   • Modify HC request VCODE generation
--   • Modify closure fan-out, roving logic, or lifecycle helpers
--   • Recreate the blocked one-store-one-vcode migration
--   • Update module state files
-- ============================================================


-- ============================================================
-- §D1  vw_slot_derived_vacancy_shadow — VCODE-grain aggregation
--
-- Replaces the slot-grain view (1 row = 1 slot) with a VCODE-grain view
-- (1 row = 1 legacy_vcode / vacancy card).
--
-- Grain change:
--   Before: 1 row = 1 plantilla_slots.id (slot)
--   After:  1 row = 1 legacy_vcode (vacancy card)
--
-- Key design decisions (from OHM2026_0047):
--   Q1  Grouping key = legacy_vcode; one row per VCODE
--   Q2  Per-VCODE identity columns from vacancies (authoritative source),
--       store/org columns aggregated with MIN() (constant per VCODE)
--   Q3  Counts = COUNT(*) FILTER per status; required_hc = COUNT(*)
--   Q4  vacancy_tab = Q4 priority (closure override → Open → Pipeline →
--       terminal Closure → NULL/excluded)
--   Q6  active_applicant_count = pipeline_count (Phase B invariant)
--   Q7  Aging = MIN(open_episode_start) FILTER (slot_status='open');
--       NULL when no open slots or future-dated (advance vacancy)
--   Q8  has_pending_closure from vacancy_closure_requests WHERE status='Pending'
--   Q9  Roving + NULL-legacy_vcode excluded before grouping (no phantom cards)
--
-- Reconciliation invariant (locked OHM2026_0035 §6):
--   open_count + pipeline_count + hr_processing_count +
--   occupied_count + closed_count = required_hc (every row)
-- ============================================================

DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow_detail;
DROP VIEW IF EXISTS public.vw_slot_derived_vacancy_shadow;

CREATE VIEW public.vw_slot_derived_vacancy_shadow
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  -- Most recent transition INTO 'open' per slot = start of current open episode.
  -- DISTINCT ON (slot_id) DESC gives the latest 'open' history event, which is the
  -- slot's current-episode start after any reopen (reopened/resigned events also
  -- write new_value = 'open' into slot_history).
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
),
pending_closure AS (
  -- VCODEs with an active Pending closure request (VCODE-level override, Q8).
  -- Mirrors the has_pending_closure source in vw_vacancy_list.
  SELECT DISTINCT vcr.vacancy_vcode
  FROM public.vacancy_closure_requests vcr
  WHERE vcr.status = 'Pending'
)
SELECT
  -- ── VCODE key (grain) ─────────────────────────────────────────────────────
  ps.legacy_vcode,

  -- ── Identity — authoritative per-VCODE fields from vacancies ─────────────
  -- v.id is the PK; PostgreSQL detects functional dependency so all v.*
  -- columns are selectable without appearing in GROUP BY.
  v.id                                                          AS legacy_vacancy_id,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,

  -- ── Store detail (constant per VCODE; roving excluded in WHERE) ───────────
  -- UUID: MIN(uuid) does not exist in PostgreSQL; use ARRAY_AGG ordered by
  -- created_at then ps.id::text (tie-breaker) and take [1] (deterministic pick).
  (ARRAY_AGG(ps.store_id   ORDER BY ps.created_at, ps.id::text))[1] AS store_id,
  MIN(st.store_branch)                                               AS store_branch,

  -- ── Org scope (constant per VCODE) ───────────────────────────────────────
  (ARRAY_AGG(ps.account_id ORDER BY ps.created_at, ps.id::text))[1] AS account_id,
  MIN(a.account_name)                                                AS account_name,
  (ARRAY_AGG(ps.group_id   ORDER BY ps.created_at, ps.id::text))[1] AS group_id,
  MIN(g.group_name)                                                  AS group_name,

  -- ── Position definition (constant per VCODE — OHM2026_0035 §1) ──────────
  MIN(ps.position)                                              AS position,
  MIN(ps.employment_type)                                       AS employment_type,
  -- is_roving = false for every row: roving slots are excluded in WHERE
  false                                                         AS is_roving,

  -- ── HC counts (Q3 aggregation table) ─────────────────────────────────────
  -- required_hc: total slot count across ALL statuses (including closed).
  -- This is the locked counting basis (OHM2026_0035 §6: hc_needed = count of slots).
  COUNT(*)                                                      AS required_hc,
  COUNT(*) FILTER (WHERE ps.slot_status = 'open')               AS open_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')           AS pipeline_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'hr_processing')      AS hr_processing_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'occupied')           AS occupied_count,
  COUNT(*) FILTER (WHERE ps.slot_status = 'closed')             AS closed_count,

  -- active_applicant_count = pipeline_count.
  -- Equality follows from the one-active-applicant-per-slot invariant (Phase B §Q4):
  -- one pipeline slot ↔ one active applicant. Applicant-side cross-check (D4) proves
  -- they agree; the slot-side derivation is used here.
  COUNT(*) FILTER (WHERE ps.slot_status = 'pipeline')           AS active_applicant_count,

  -- ── Pending closure flag (VCODE-level — OHM2026_0035 §7) ─────────────────
  -- True when any in-flight Pending closure request exists for this VCODE.
  -- bool_or is safe: all slots in the group share the same legacy_vcode, so the
  -- LEFT JOIN result is uniform (all match or all don't).
  bool_or(pc.vacancy_vcode IS NOT NULL)                         AS has_pending_closure,

  -- ── Vacancy tab — Q4 priority (exactly one tab per VCODE) ────────────────
  -- P1: pending closure override → Closure  (decision in flight; surfaces immediately)
  -- P2: open_count > 0            → Open    (recruitable HC present)
  -- P3: pipeline_count > 0        → Pipeline (all HC sourced; applicants in flight)
  -- P4: all slots closed          → Closure  (terminal — VCODE fully retired)
  -- P5: only hr_processing / occupied remain → NULL (excluded from Vacancy list;
  --     ownership belongs to HR Emploc / Plantilla per OHM2026_0006 §2)
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

  -- ── Aging — oldest open-episode start among the VCODE's open slots (Q7) ──
  -- aging_start_at: the MIN open-episode start across slots in 'open' status.
  -- This is the slot that has been waiting the longest for fill (worst-case SLA).
  -- NULL when open_count = 0 (no open HC for this VCODE).
  MIN(COALESCE(ab.open_episode_start, ps.created_at))
    FILTER (WHERE ps.slot_status = 'open')                      AS aging_start_at,

  -- aging_days: calendar days since the oldest open slot's episode start.
  -- NULL when: (a) no open slots, or (b) the oldest episode is future-dated
  -- (advance vacancy — consistent with fn_cencom_td_aging_bucket).
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
  -- closed_at: latest closure timestamp across the VCODE's slots
  -- (NULL if no closed slots; set once any slot closes)
  MAX(ps.closed_at)                                             AS closed_at,

  -- ── HC request seed ───────────────────────────────────────────────────────
  -- source_hc_request_id: earliest HC request that seeded a slot for this VCODE.
  -- N-slot-safe: Phase F will create additional slots; [1] after ORDER BY created_at
  -- returns the seed request (UUID: MIN(uuid) does not exist in PostgreSQL).
  (ARRAY_AGG(ps.source_hc_request_id ORDER BY ps.created_at, ps.id::text))[1] AS source_hc_request_id,

  -- ── Legacy vacancy snapshot fields (parity with previous shadow view) ─────
  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name

FROM public.plantilla_slots ps

-- Open-episode aging basis (LEFT JOIN — slots with no slot_history fall back to ps.created_at)
LEFT JOIN aging_basis ab
  ON ab.slot_id = ps.id

-- Store detail (NULL-safe join; is_roving = false guaranteed by WHERE)
LEFT JOIN public.stores st
  ON st.id = ps.store_id

-- Account name
LEFT JOIN public.accounts a
  ON a.id = ps.account_id

-- Group name
LEFT JOIN public.groups g
  ON g.id = ps.group_id

-- Pending closure flag (LEFT JOIN; all slots in a VCODE group share the same match)
LEFT JOIN pending_closure pc
  ON pc.vacancy_vcode = ps.legacy_vcode

-- INNER JOIN vacancies:
--   (a) exposes v.id as legacy_vacancy_id for correct FK writes downstream
--   (b) implicitly excludes NULL-legacy_vcode slots (INNER JOIN on NULL key
--       matches nothing, filtering those rows out — D9)
--   (c) ensures only slots linked to a live (non-deleted) legacy vacancy
--       are visible in the shadow (no orphan slot cards)
INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
  AND v.deleted_at IS NULL

-- SCOPE: exclude roving slots and NULL-legacy_vcode slots before grouping
-- so no phantom cards are produced (D9). Roving VCODEs remain on the
-- legacy read path (OHM2026_0017/0037 carve-out).
WHERE ps.legacy_vcode IS NOT NULL
  AND ps.is_roving = false

-- GROUP BY: legacy_vcode is the VCODE-grain key.
-- v.id (PK of vacancies) is included so PostgreSQL can detect that all v.*
-- columns are functionally dependent on v.id and do not need to appear in
-- GROUP BY individually. All other non-aggregate SELECT expressions are either
-- aggregated (MIN/MAX/COUNT/bool_or), literals (false), or functionally
-- dependent on v.id.
GROUP BY
  ps.legacy_vcode,
  v.id;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow IS
  'SHADOW VIEW — OHM2026_0048 (Phase D). '
  'VCODE-grain: 1 row = 1 legacy_vcode / vacancy card. '
  'Replaces OHM2026_0032B slot-grain view (1 row = 1 slot). '
  'Aggregates per-slot status into per-VCODE counts: required_hc, open_count, '
  'pipeline_count, hr_processing_count, occupied_count, closed_count. '
  'vacancy_tab derived by Q4 priority (OHM2026_0047): pending-closure override → '
  'Open → Pipeline → terminal Closure → NULL (P5 excluded). '
  'Aging = oldest open-episode start among open slots (worst-case SLA, Q7). '
  'active_applicant_count = pipeline_count (Phase B one-active-per-slot invariant). '
  'Roving + NULL-legacy_vcode excluded before grouping (no phantom cards, D9). '
  'Both views remain UNWIRED — legacy vacancies is authoritative for the UI '
  'until the flag-gated read cutover (Phase G). '
  'Companion slot-grain detail view: vw_slot_derived_vacancy_shadow_detail. '
  'SECURITY INVOKER — inherits caller RLS via plantilla_slots_read_scoped policy.';


-- ============================================================
-- §D2  vw_slot_derived_vacancy_shadow_detail — slot-grain companion (Q9)
--
-- One row per slot, filtered to non-roving slot-backed VCODEs.
-- Provides the drill-down seam for future slot-level UI (deferred,
-- OHM2026_0035 §3). The list view (vw_slot_derived_vacancy_shadow) links
-- to the detail by legacy_vcode; the detail enumerates slots in
-- slot_ordinal order.
--
-- This view is UNWIRED in Phase D — no UI reads it.
-- ============================================================

CREATE VIEW public.vw_slot_derived_vacancy_shadow_detail
  WITH (security_invoker = true)
AS
WITH aging_basis AS (
  -- Same CTE as the list view: current open-episode start per slot.
  SELECT DISTINCT ON (sh.slot_id)
    sh.slot_id,
    sh.created_at AS open_episode_start
  FROM public.slot_history sh
  WHERE sh.new_value = 'open'
  ORDER BY sh.slot_id, sh.created_at DESC
)
SELECT
  -- ── Slot identity ─────────────────────────────────────────────────────────
  ps.id                                                         AS slot_id,
  ps.legacy_vcode,
  ps.slot_ordinal,
  ps.slot_status,
  ps.source_hc_request_id,

  -- ── Legacy vacancy identity ───────────────────────────────────────────────
  v.id                                                          AS legacy_vacancy_id,

  -- ── Location (vacancy snapshot values — parity with list view) ───────────
  ps.store_id,
  st.store_branch,
  v.store_name,
  v.area_city,
  v.province,
  v.area_name,

  -- ── Org scope ─────────────────────────────────────────────────────────────
  ps.account_id,
  a.account_name,
  ps.group_id,
  g.group_name,

  -- ── Position ──────────────────────────────────────────────────────────────
  ps.position,
  ps.employment_type,

  -- ── Per-slot aging (open-episode basis — same logic as pre-Phase D view) ─
  -- slot_open_since: start of this slot's current open episode.
  -- NULL for slots not in an active open episode (hr_processing, occupied, closed).
  CASE
    WHEN ps.slot_status IN ('open', 'pipeline')
      THEN COALESCE(ab.open_episode_start, ps.created_at)
    ELSE NULL
  END                                                           AS slot_open_since,

  -- aging_days per slot: NULL for non-open/pipeline statuses and advance vacancies.
  CASE
    WHEN ps.slot_status NOT IN ('open', 'pipeline')
      THEN NULL::integer
    WHEN COALESCE(ab.open_episode_start, ps.created_at)::date > CURRENT_DATE
      THEN NULL::integer
    ELSE
      (CURRENT_DATE - COALESCE(ab.open_episode_start, ps.created_at)::date)
  END                                                           AS aging_days,

  -- ── Bound applicant (Phase B: applicants.slot_id) ────────────────────────
  -- bound_applicant_id: UUID of the pipeline-active applicant bound to this slot.
  -- NULL when slot is open, hr_processing, occupied, or closed.
  bound_app.bound_applicant_id,

  -- ── Bound HR Emploc (Phase C: hr_emploc.slot_id) ─────────────────────────
  -- bound_hr_emploc_id: UUID of the active HR Emploc row bound to this slot.
  -- NULL when slot is not in hr_processing.
  bound_emp.bound_hr_emploc_id,

  -- ── Occupant link (Plantilla) ─────────────────────────────────────────────
  ps.current_occupant_plantilla_id,

  -- ── Legacy vacancy snapshot fields ───────────────────────────────────────
  v.urgency_level,
  v.hrco_name,
  v.hrco_user_id,
  v.target_fill_date,
  v.triggered_by_user_id,
  v.triggered_by_name,

  -- ── Timestamps ────────────────────────────────────────────────────────────
  ps.created_at,
  ps.updated_at,
  ps.closed_at,
  ps.closure_reason_code

FROM public.plantilla_slots ps

-- Open-episode aging basis
LEFT JOIN aging_basis ab
  ON ab.slot_id = ps.id

-- Store detail
LEFT JOIN public.stores st
  ON st.id = ps.store_id

-- Account name
LEFT JOIN public.accounts a
  ON a.id = ps.account_id

-- Group name
LEFT JOIN public.groups g
  ON g.id = ps.group_id

-- Bound active applicant (Phase B: one active applicant per pipeline slot)
LEFT JOIN LATERAL (
  SELECT app.id AS bound_applicant_id
  FROM public.applicants app
  WHERE app.slot_id = ps.id
    AND public.fn_is_active_vacancy_applicant_status(app.status) = true
    AND COALESCE(app.is_archived, false) = false
  LIMIT 1
) bound_app ON true

-- Bound active HR Emploc (Phase C: one active HR Emploc per hr_processing slot)
LEFT JOIN LATERAL (
  SELECT emp.id AS bound_hr_emploc_id
  FROM public.hr_emploc emp
  WHERE emp.slot_id = ps.id
    AND emp.deleted_at IS NULL
  LIMIT 1
) bound_emp ON true

-- INNER JOIN vacancies (same scope as list view)
INNER JOIN public.vacancies v
  ON v.vcode = ps.legacy_vcode
  AND v.deleted_at IS NULL

-- Same scope as list view: exclude roving + NULL-legacy_vcode slots
WHERE ps.legacy_vcode IS NOT NULL
  AND ps.is_roving = false

-- Enumerate slots per VCODE in slot_ordinal order (future drill-down display order)
ORDER BY ps.legacy_vcode, ps.slot_ordinal;

COMMENT ON VIEW public.vw_slot_derived_vacancy_shadow_detail IS
  'SHADOW VIEW — OHM2026_0048 (Phase D, Q9). '
  'Slot-grain companion to vw_slot_derived_vacancy_shadow. '
  'One row per slot for non-roving, slot-backed VCODEs. '
  'Provides the drill-down seam for future slot-level UI (DEFERRED — '
  'OHM2026_0035 §3). Ordered by legacy_vcode, slot_ordinal. '
  'Exposes per-slot aging, bound applicant id (Phase B), bound HR Emploc id '
  '(Phase C), and occupant link. UNWIRED in Phase D. '
  'SECURITY INVOKER — inherits caller RLS via plantilla_slots_read_scoped policy.';


-- ============================================================
-- §D3  Grants
-- ============================================================

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO service_role;

GRANT SELECT ON public.vw_slot_derived_vacancy_shadow_detail TO authenticated;
GRANT SELECT ON public.vw_slot_derived_vacancy_shadow_detail TO service_role;


-- ============================================================
-- §D4  Post-migration validation queries
--
-- Run these manually after applying the migration to verify the
-- Phase D validation checklist (D1–D12, OHM2026_0047 §Q10).
--
-- All checks must pass before Phase E (closure fan-out) is gated open.
-- ============================================================

/*
-- ── D0 Pre-gate: confirm Phase C suite still GREEN ────────────────────────

-- P-suite quick re-check (no duplicate slot ordinals per VCODE)
SELECT legacy_vcode, slot_ordinal, COUNT(*) AS n
FROM public.plantilla_slots
WHERE legacy_vcode IS NOT NULL
GROUP BY legacy_vcode, slot_ordinal
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- ── D1  One row per legacy_vcode (no duplicate vacancy cards) ─────────────

SELECT legacy_vcode, COUNT(*) AS n
FROM public.vw_slot_derived_vacancy_shadow
GROUP BY legacy_vcode
HAVING COUNT(*) > 1;
-- Expected: 0 rows (decisive check — the exact failure mode of the blocked
-- one_store_one_vcode migration)

-- ── D2  Per-row reconciliation: counts sum to required_hc ─────────────────

SELECT legacy_vcode, required_hc,
       open_count, pipeline_count, hr_processing_count, occupied_count, closed_count,
       (open_count + pipeline_count + hr_processing_count + occupied_count + closed_count) AS sum_counts
FROM public.vw_slot_derived_vacancy_shadow
WHERE (open_count + pipeline_count + hr_processing_count + occupied_count + closed_count)
      <> required_hc;
-- Expected: 0 rows (locked reconciliation invariant OHM2026_0035 §6)

-- ── D3  required_hc parity vs vacancies.required_headcount ───────────────

SELECT s.legacy_vcode, s.required_hc, v.required_headcount
FROM public.vw_slot_derived_vacancy_shadow s
JOIN public.vacancies v ON v.vcode = s.legacy_vcode
WHERE s.required_hc <> v.required_headcount;
-- Expected: 0 mismatches for slot-backed VCODEs (parity defect if any rows)

-- ── D4  active_applicant_count == pipeline_count ─────────────────────────

SELECT legacy_vcode, active_applicant_count, pipeline_count
FROM public.vw_slot_derived_vacancy_shadow
WHERE active_applicant_count <> pipeline_count;
-- Expected: 0 rows (slot-side == applicant-side invariant, Phase B §Q4)

-- Cross-check: applicant-side count vs slot-side pipeline_count
SELECT s.legacy_vcode, s.pipeline_count,
       COUNT(a.id) AS applicant_side_count
FROM public.vw_slot_derived_vacancy_shadow s
LEFT JOIN public.applicants a
  ON a.vacancy_vcode = s.legacy_vcode
  AND public.fn_is_active_vacancy_applicant_status(a.status) = true
  AND a.slot_id IS NOT NULL
  AND COALESCE(a.is_archived, false) = false
GROUP BY s.legacy_vcode, s.pipeline_count
HAVING s.pipeline_count <> COUNT(a.id);
-- Expected: 0 discrepancies

-- ── D5  One vacancy_tab per row; priority is total and deterministic ──────

SELECT legacy_vcode, vacancy_tab, COUNT(*) AS n
FROM public.vw_slot_derived_vacancy_shadow
GROUP BY legacy_vcode, vacancy_tab
HAVING COUNT(*) > 1;
-- Expected: 0 rows (one tab per card — already structurally guaranteed by D1)

-- Distribution across tabs (informational)
SELECT vacancy_tab, COUNT(*) AS card_count
FROM public.vw_slot_derived_vacancy_shadow
GROUP BY vacancy_tab
ORDER BY vacancy_tab;

-- ── D6  No P5 row mis-tabbed as Open/Pipeline/Closure ────────────────────

SELECT legacy_vcode, open_count, pipeline_count, hr_processing_count,
       occupied_count, closed_count, required_hc, vacancy_tab
FROM public.vw_slot_derived_vacancy_shadow
WHERE vacancy_tab IN ('Open', 'Pipeline', 'Closure')
  AND open_count = 0
  AND pipeline_count = 0
  AND closed_count < required_hc
  AND has_pending_closure = false;
-- Expected: 0 rows

-- ── D7  Card count parity vs legacy (slot-backed, non-roving set) ─────────

-- Shadow card count per VCODE set
SELECT COUNT(*) AS shadow_card_count
FROM public.vw_slot_derived_vacancy_shadow;

-- Legacy vacancy count for the same VCODE set
SELECT COUNT(DISTINCT v.vcode) AS legacy_vcode_count
FROM public.vacancies v
WHERE v.deleted_at IS NULL
  AND EXISTS (
    SELECT 1 FROM public.plantilla_slots ps
    WHERE ps.legacy_vcode = v.vcode
      AND ps.is_roving = false
      AND ps.legacy_vcode IS NOT NULL
  );
-- Expected: both counts equal

-- ── D8  Status-count parity vs legacy per account ────────────────────────

-- Shadow Open count per account
SELECT account_id, COUNT(*) AS shadow_open_count
FROM public.vw_slot_derived_vacancy_shadow
WHERE vacancy_tab = 'Open'
GROUP BY account_id;

-- Legacy Open count per account (for the slot-backed set)
-- Compare manually against legacy vw_vacancy_list Open tab counts.

-- ── D9  No phantom cards from roving or NULL-legacy_vcode slots ───────────

SELECT legacy_vcode
FROM public.vw_slot_derived_vacancy_shadow
WHERE legacy_vcode IS NULL;
-- Expected: 0 rows (NULL is excluded structurally by INNER JOIN + WHERE)

-- Confirm roving slots are not in the view
SELECT COUNT(*) AS roving_in_shadow
FROM public.vw_slot_derived_vacancy_shadow s
JOIN public.plantilla_slots ps ON ps.legacy_vcode = s.legacy_vcode
WHERE ps.is_roving = true;
-- Expected: 0 rows (roving excluded in WHERE before grouping)

-- ── D10  Aging = oldest open-episode start; NULL when open_count = 0 ──────

-- Any row with open_count = 0 that has a non-NULL aging_start_at is a defect
SELECT legacy_vcode, open_count, aging_start_at, aging_days
FROM public.vw_slot_derived_vacancy_shadow
WHERE open_count = 0
  AND (aging_start_at IS NOT NULL OR aging_days IS NOT NULL);
-- Expected: 0 rows

-- Spot-check: aging_start_at should equal the MIN open-episode start
-- for the VCODE's open slots
SELECT s.legacy_vcode, s.aging_start_at,
       MIN(COALESCE(sh_min.created_at, ps.created_at)) AS expected_aging_start
FROM public.vw_slot_derived_vacancy_shadow s
JOIN public.plantilla_slots ps
  ON ps.legacy_vcode = s.legacy_vcode
  AND ps.slot_status = 'open'
  AND ps.is_roving = false
LEFT JOIN LATERAL (
  SELECT sh.created_at
  FROM public.slot_history sh
  WHERE sh.slot_id = ps.id AND sh.new_value = 'open'
  ORDER BY sh.created_at DESC
  LIMIT 1
) sh_min ON true
GROUP BY s.legacy_vcode, s.aging_start_at
HAVING s.aging_start_at <> MIN(COALESCE(sh_min.created_at, ps.created_at));
-- Expected: 0 mismatches

-- ── D11  Detail view row count per VCODE == required_hc ──────────────────

SELECT s.legacy_vcode, s.required_hc, COUNT(d.slot_id) AS detail_rows
FROM public.vw_slot_derived_vacancy_shadow s
LEFT JOIN public.vw_slot_derived_vacancy_shadow_detail d
  ON d.legacy_vcode = s.legacy_vcode
GROUP BY s.legacy_vcode, s.required_hc
HAVING s.required_hc <> COUNT(d.slot_id);
-- Expected: 0 mismatches (every slot is enumerable in the detail view)

-- ── D12  C-suite + B-suite + P-suite re-run ───────────────────────────────
-- Run the full Phase C (C1–C12), Phase B (B1–B10), and P-suite (P1–P8)
-- validation queries from their respective migration files.
-- All must remain GREEN after Phase D is applied.
-- Phase D is read-only (view DDL only); it makes no writes to tables or RPCs,
-- so upstream invariants should be unaffected.

*/
