-- ============================================================
-- OHM2026_0086 — Coverage Group Phase RE: Roving Shadow Read Model
-- Migration: 20260826000000_coverage_group_phase_re_shadow_read_model.sql
--
-- Authorising document:
--   docs/architecture/coverage_group_phase_re_shadow_read_model_plan.md
--   (OHM2026_0085) — full design, field table, validation checklist RE1–RE12
--
-- Depends on (all GREEN per OHM2026_0082/0083):
--   20260825000000_coverage_group_phase_rd_plantilla_active_transition.sql
--     (Phase R-D — PASS=16 FAIL=0)
--   coverage_groups, coverage_slots, coverage_group_stores,
--   accounts, groups, positions, stores
-- ============================================================
-- Scope: CREATE OR REPLACE VIEW public.vw_coverage_group_shadow
--
--   Phase RE re-aggregates the per-slot 'active' truth produced by R-D into
--   a CGCODE-grain count strip — the roving peer of
--   vw_slot_derived_vacancy_shadow. One row per active (non-archived)
--   Coverage Group (CGCODE).
--
--   VIEW DDL ONLY. No table changes, no constraint changes, no RPC changes,
--   no modifications to vw_slot_derived_vacancy_shadow or any stationary
--   object (OHM2026_0058 GREEN — stationary architecture is locked).
--
-- Sections:
--   §RE1  vw_coverage_group_shadow — CGCODE-grain shadow view
--   §RE2  COMMENT ON VIEW
--   §RE3  Grants
--   §RE4  Validation queries (commented — run manually after applying)
--
-- What this migration deliberately does NOT do:
--   • Modify Flutter, Next.js, or any client code
--   • Modify vw_slot_derived_vacancy_shadow or any stationary object
--   • Create tables, add constraints, or add triggers
--   • Implement group closure (R-E), separation/transfer (R-F), or reopen
--   • Create vw_coverage_group_shadow_detail (companion; deferred)
--   • Wire any UI to this view (shadow only — Flutter/web wiring is a
--     separate implementation task per OHM2026_0085 §Rollout)
--
-- Isolation guarantee (OHM2026_0085 §7):
--   vw_coverage_group_shadow joins ONLY:
--     coverage_groups, coverage_slots, coverage_group_stores,
--     accounts, groups, positions, stores.
--   It does NOT join: vacancies, plantilla_slots, or
--     vw_slot_derived_vacancy_shadow. Mixing these grains re-introduces
--     the phantom-card / HC-inflation bug this redesign exists to fix.
--
-- CGCODE isolation checks (RE8, RE9 — hard-block before UI wiring):
--   RE8: SELECT COUNT(*) FROM vw_slot_derived_vacancy_shadow
--          WHERE legacy_vcode LIKE 'CG-%';  -- must be 0
--   RE9: SELECT coverage_code FROM vw_coverage_group_shadow
--          WHERE coverage_code NOT LIKE 'CG-%';  -- must be 0 rows
--
-- Reconciliation invariant (per group — RE3 hard-block):
--   open_count + pipeline_count + hr_processing_count +
--   active_count + closed_count = required_hc (= slot_total)
-- ============================================================


-- ============================================================
-- §RE1  vw_coverage_group_shadow — CGCODE-grain shadow
--
-- Grain:    1 row per active (non-archived) Coverage Group (CGCODE).
-- Source:   coverage_groups, coverage_slots, coverage_group_stores,
--           accounts, groups, positions, stores.
-- Security: SECURITY INVOKER — RLS on coverage_groups
--           (coverage_groups_read_scoped: i_have_full_access() OR
--            account_id = ANY(get_my_allowed_account_ids())) is the
--           authoritative scope gate; the view inherits it automatically.
--
-- Slot counts are computed via a LATERAL subquery (no GROUP BY on the
-- main query), keeping the grain cleanly 1-row-per-group without
-- accidental fan-out from the store footprint join.
--
-- Store footprint is also a LATERAL subquery; it aggregates
-- coverage_group_stores for each group independently.
-- ============================================================

DROP VIEW IF EXISTS public.vw_coverage_group_shadow;

CREATE VIEW public.vw_coverage_group_shadow
  WITH (security_invoker = true)
AS
SELECT

  -- ── Identity ───────────────────────────────────────────────────────────────
  cg.id                  AS coverage_group_id,
  cg.coverage_code,                              -- CGCODE; always 'CG-' prefix

  -- Account scope
  cg.account_id,
  a.account_name,

  -- Group scope (coverage_groups → accounts → groups)
  a.group_id,
  g.group_name,

  -- Position
  cg.position_id,
  p.position_name,

  -- Classification
  cg.employment_type,
  cg.area_name,                                  -- nullable reporting area

  -- Cached group status (authoritative status is slot-count-derived; this is
  -- the list-query cache column per OHM2026_0066 RA1)
  cg.status              AS group_status,
  cg.created_at,                                 -- vacancy aging basis

  -- ── Required headcount (HC anchor; MFR denominator) ───────────────────────
  cg.required_headcount  AS required_hc,

  -- ── Count strip — all sourced from coverage_slots.slot_status ─────────────
  -- Counts are zero when no slots exist (COUNT returns 0 for empty input).
  sc.open_count,
  sc.pipeline_count,
  sc.hr_processing_count,
  sc.active_count,
  sc.closed_count,
  -- slot_total: convenience reconciliation field; must equal required_hc (RE3).
  -- Not rendered in card UI — used for the RE3 validation check only.
  sc.slot_total,

  -- ── MFR fields ─────────────────────────────────────────────────────────────
  -- filled_hc: explicit alias of active_count for MFR consumers.
  -- Filled token for coverage_slots is 'active' (LOCKED — OHM2026_0064).
  -- 'occupied' is reserved exclusively for stationary plantilla_slots.
  -- UI label is "Filled" for both; only the DB token differs.
  sc.active_count        AS filled_hc,

  -- mfr_pct: group-grain MFR percentage (numeric, 2 dp).
  -- Denominator = required_headcount (NEVER store count).
  -- Numerator   = active slot count  (NEVER 1/active_store_count fraction).
  -- 0 when required_headcount = 0 (degenerate guard; CHECK ensures >= 1 at
  -- write time, but the view is defensive).
  CASE
    WHEN cg.required_headcount > 0
      THEN ROUND(
             sc.active_count::numeric / cg.required_headcount * 100,
             2
           )
    ELSE 0::numeric
  END                    AS mfr_pct,

  -- is_mfr_met: quick MFR-met flag for list filtering.
  (sc.active_count >= cg.required_headcount)
                         AS is_mfr_met,

  -- ── Tab routing (roving peer of stationary Phase D vacancy_tab) ───────────
  -- Priority order — first matching rule wins (OHM2026_0085 §vacancy_tab):
  --   1. open_count > 0                    → 'open'
  --   2. pipeline_count > 0                → 'pipeline'
  --   3. hr_processing_count > 0           → 'hr_processing'
  --   4. active fills all, none open/etc.  → 'filled'
  --   5. closed_count = required_hc        → 'closed'
  --   fallback                             → 'open'
  CASE
    WHEN sc.open_count > 0
      THEN 'open'
    WHEN sc.pipeline_count > 0
      THEN 'pipeline'
    WHEN sc.hr_processing_count > 0
      THEN 'hr_processing'
    WHEN sc.active_count > 0
         AND sc.open_count = 0
         AND sc.pipeline_count = 0
         AND sc.hr_processing_count = 0
      THEN 'filled'
    WHEN sc.closed_count = cg.required_headcount
         AND cg.required_headcount > 0
      THEN 'closed'
    ELSE 'open'           -- fallback: degenerate state (zero-slot group guard)
  END                    AS vacancy_tab,

  -- ── Store footprint ────────────────────────────────────────────────────────
  -- Sourced from coverage_group_stores (active rows only: archived_at IS NULL).
  -- Covered stores contribute 0 HC — store count is a footprint annotation,
  -- not an HC source. Fractional 1/active_store_count is a store-grain
  -- reporting lens only and never enters integer HC or MFR (locked OHM2026_0062).
  sf.active_store_count, -- integer; number of currently covered stores
  sf.anchor_store_id,    -- uuid; the one store where is_anchor = true
  sf.anchor_store_name,  -- text; card title/location display
  sf.store_preview,      -- text; anchor first, ≤3 names, "+N more" if > 3
  sf.store_ids           -- uuid[]; client-side filtering + future drill-down

FROM public.coverage_groups cg

-- Account and group lookups
LEFT JOIN public.accounts  a ON a.id = cg.account_id
LEFT JOIN public.groups    g ON g.id = a.group_id
LEFT JOIN public.positions p ON p.id = cg.position_id

-- ── Slot counts (LATERAL aggregation per group) ────────────────────────────
-- Always returns exactly one row per group (aggregate over empty set = 0s).
-- No GROUP BY on the main query is needed because this lateral handles the
-- aggregation independently. Grain remains 1 row per coverage_group.
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) FILTER (WHERE cs.slot_status = 'open')           AS open_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'pipeline')       AS pipeline_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'hr_processing')  AS hr_processing_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'active')         AS active_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'closed')         AS closed_count,
    COUNT(*)                                                   AS slot_total
  FROM public.coverage_slots cs
  WHERE cs.coverage_group_id = cg.id
) sc ON true

-- ── Store footprint (LATERAL aggregation per group) ───────────────────────
-- active_store_count: integer; COUNT over active coverage_group_stores edges.
-- anchor_store_id / anchor_store_name: exactly one active anchor per group
--   guaranteed by uq_coverage_group_stores_active_anchor (partial unique);
--   MAX(... FILTER (WHERE is_anchor)) is safe and returns the single value.
-- store_ids: uuid[] ordered anchor-first for client-side "which groups cover
--   store X" filtering and future footprint drill-down panel (deferred).
-- store_preview: anchor first, up to 3 store names, then "+N more" suffix
--   when active_store_count > 3 — bounds the string for list-view performance
--   (Risk #6, OHM2026_0085). Built with ARRAY_AGG slice [1:3] to avoid a
--   nested correlated subquery.
LEFT JOIN LATERAL (
  SELECT
    COUNT(*)
                                                              AS active_store_count,
    (ARRAY_AGG(cgs.store_id) FILTER (WHERE cgs.is_anchor))[1] AS anchor_store_id,
    MAX(s.store_name)   FILTER (WHERE cgs.is_anchor)         AS anchor_store_name,
    ARRAY_AGG(cgs.store_id
              ORDER BY cgs.is_anchor DESC, cgs.added_at ASC) AS store_ids,

    -- store_preview: anchor listed first (is_anchor DESC puts it at [1]),
    -- then added_at ASC for remaining stores.
    -- Bounded to ≤3 names with "+N more" suffix for large footprints.
    CASE
      WHEN COUNT(*) = 0
        THEN NULL

      WHEN COUNT(*) <= 3
        THEN string_agg(
               s.store_name, ', '
               ORDER BY cgs.is_anchor DESC, cgs.added_at ASC
             )

      ELSE
        -- Slice ARRAY_AGG to first 3 names instead of a nested subquery.
        array_to_string(
          (ARRAY_AGG(s.store_name
                     ORDER BY cgs.is_anchor DESC, cgs.added_at ASC))[1:3],
          ', '
        ) || ' +' || (COUNT(*) - 3)::text || ' more'
    END                                                       AS store_preview

  FROM public.coverage_group_stores cgs
  JOIN public.stores s ON s.id = cgs.store_id
  WHERE cgs.coverage_group_id = cg.id
    AND cgs.archived_at IS NULL
) sf ON true

-- ── Base predicate ─────────────────────────────────────────────────────────
-- Exclude archived coverage groups (same posture as stationary shadow which
-- excludes vacancies with deleted_at IS NOT NULL).
-- coverage_code LIKE 'CG-%' is guaranteed by coverage_groups_code_prefix_check
-- at write time; stated explicitly here as belt-and-suspenders for RE9.
WHERE cg.archived_at IS NULL
  AND cg.coverage_code LIKE 'CG-%';


-- ============================================================
-- §RE2  COMMENT ON VIEW
-- ============================================================

COMMENT ON VIEW public.vw_coverage_group_shadow IS
  'SHADOW VIEW — OHM2026_0086 (Phase RE). Read-only; not wired to any UI. '
  'CGCODE-grain: 1 row = 1 active (non-archived) Coverage Group. '
  'Roving peer of vw_slot_derived_vacancy_shadow — NEVER merged, joined, '
  'or unioned with it (mixing grains re-introduces phantom-card / HC-inflation). '
  'Aggregates coverage_slots.slot_status into group-grain counts: '
  'required_hc, open_count, pipeline_count, hr_processing_count, active_count, closed_count. '
  'filled_hc = active_count (filled token is ''active''; LOCKED OHM2026_0064 — '
  '''occupied'' is reserved for stationary plantilla_slots). '
  'mfr_pct = ROUND(active_count / required_hc * 100, 2) — integer group grain; '
  '1/active_store_count fractional per-store lens NEVER enters MFR. '
  'vacancy_tab priority: open → pipeline → hr_processing → filled → closed → open. '
  'Store footprint: active_store_count (int), anchor_store_id (uuid), '
  'anchor_store_name (text), store_preview (≤3 names + "+N more"), store_ids (uuid[]). '
  'SECURITY INVOKER — inherits caller RLS via coverage_groups_read_scoped policy '
  '(i_have_full_access() OR account_id = ANY(get_my_allowed_account_ids())). '
  'RE1–RE12 hard-block checks before UI wiring: RE3 (slot reconciliation), '
  'RE4 (active_count vs plantilla), RE8 (0 CG-% in stationary shadow), '
  'RE9 (0 non-CG rows here). Validation queries in migration §RE4. '
  'Companion slot-grain detail view (vw_coverage_group_shadow_detail) designed '
  'but deferred (OHM2026_0085 §Companion Detail View).';


-- ============================================================
-- §RE3  Grants
-- ============================================================
-- Matches the stationary shadow grant pattern (Phase D / Phase 8a).

GRANT SELECT ON public.vw_coverage_group_shadow TO authenticated;
GRANT SELECT ON public.vw_coverage_group_shadow TO service_role;


-- ============================================================
-- §RE4  Post-apply validation queries (run manually after applying)
--
-- All RE1–RE12 checks plus vacancy_tab and filled_hc assertions.
-- Hard-block checks (RE3, RE4, RE8, RE9) must return 0 before this
-- view is wired to any Flutter or Next.js consumer.
-- Also re-run the full RD1–RD12 and stationary A–G regression.
-- ============================================================

/*

-- ── RE0  Pre-gate: confirm RD1–RD12 GREEN and stationary baseline GREEN ─────

-- RD12b re-assertion: 0 CG-% rows in stationary shadow (must be GREEN before RE)
SELECT COUNT(*) AS cg_rows_in_stationary_pre_re
FROM public.vw_slot_derived_vacancy_shadow
WHERE legacy_vcode LIKE 'CG-%';
-- Expected: 0

-- View exists
SELECT viewname
FROM pg_views
WHERE schemaname = 'public'
  AND viewname = 'vw_coverage_group_shadow';
-- Expected: 1 row


-- ── RE1  One row per CGCODE; no duplicate group cards (RS1) ──────────────────

SELECT coverage_group_id, COUNT(*) AS n
FROM public.vw_coverage_group_shadow
GROUP BY coverage_group_id
HAVING COUNT(*) > 1;
-- Expected: 0 rows


-- ── RE2  required_hc matches coverage_groups.required_headcount (RS9) ────────

SELECT
  shadow.coverage_code,
  shadow.required_hc,
  cg.required_headcount
FROM public.vw_coverage_group_shadow shadow
JOIN public.coverage_groups cg ON cg.id = shadow.coverage_group_id
WHERE shadow.required_hc != cg.required_headcount;
-- Expected: 0 mismatches


-- ── RE3  Slot count reconciliation — HARD-BLOCK (RS2) ────────────────────────
-- open + pipeline + hr_processing + active + closed = required_hc = slot_total

SELECT
  coverage_code,
  required_hc,
  slot_total,
  open_count,
  pipeline_count,
  hr_processing_count,
  active_count,
  closed_count,
  (open_count + pipeline_count + hr_processing_count + active_count + closed_count) AS sum_counts
FROM public.vw_coverage_group_shadow
WHERE slot_total != required_hc
   OR (open_count + pipeline_count + hr_processing_count + active_count + closed_count)
      != required_hc;
-- Expected: 0 violations


-- ── RE3b  filled_hc = active_count (RS3) ─────────────────────────────────────

SELECT coverage_code, filled_hc, active_count
FROM public.vw_coverage_group_shadow
WHERE filled_hc != active_count;
-- Expected: 0 rows


-- ── RE4  active_count == plantilla-side active count per CGCODE (HARD-BLOCK) ─
-- Peers RD9b. Plantilla-side is validation cross-check only (not a view field).
-- A mismatch indicates slot/plantilla binding desync — resolve before wiring UI.

SELECT
  shadow.coverage_code,
  shadow.active_count AS slot_side_active,
  COUNT(pl.id)        AS plantilla_side_active
FROM public.vw_coverage_group_shadow shadow
LEFT JOIN public.plantilla pl
  ON pl.coverage_group_id = shadow.coverage_group_id
 AND COALESCE(pl.is_deleted, false) = false
 AND pl.status = 'Active'
 AND pl.coverage_slot_id IS NOT NULL
GROUP BY shadow.coverage_code, shadow.active_count
HAVING shadow.active_count != COUNT(pl.id);
-- Expected: 0 mismatches


-- ── RE5  No row with required_hc <= 0 ────────────────────────────────────────

SELECT coverage_code, required_hc
FROM public.vw_coverage_group_shadow
WHERE required_hc <= 0;
-- Expected: 0 rows (CHECK constraint enforces >= 1 at write time; view confirms)


-- ── RE6  Every row with active_store_count > 0 has anchor_store_name ─────────
-- A NULL anchor indicates a data-entry gap (no is_anchor row despite footprint).

SELECT coverage_code, active_store_count, anchor_store_name
FROM public.vw_coverage_group_shadow
WHERE active_store_count > 0
  AND anchor_store_name IS NULL;
-- Expected: 0 rows (RS5: store footprint correctness)


-- ── RE7  mfr_pct is arithmetically correct (RS4) ─────────────────────────────

SELECT
  coverage_code,
  mfr_pct,
  ROUND(active_count::numeric / NULLIF(required_hc, 0) * 100, 2) AS expected_mfr_pct
FROM public.vw_coverage_group_shadow
WHERE mfr_pct IS DISTINCT FROM
      ROUND(active_count::numeric / NULLIF(required_hc, 0) * 100, 2);
-- Expected: 0 mismatches


-- ── RE8  0 CGCODE rows leak into vw_slot_derived_vacancy_shadow (HARD-BLOCK) ─
-- RS6: no CGCODE leakage into stationary shadow. Re-asserts RD12b at RE level.

SELECT COUNT(*) AS cg_rows_in_stationary_shadow
FROM public.vw_slot_derived_vacancy_shadow
WHERE legacy_vcode LIKE 'CG-%';
-- Expected: 0


-- ── RE9  0 non-CGCODE rows in vw_coverage_group_shadow (HARD-BLOCK) ──────────
-- RS7: no VCODE leakage into roving shadow.

SELECT coverage_code
FROM public.vw_coverage_group_shadow
WHERE coverage_code NOT LIKE 'CG-%';
-- Expected: 0 rows


-- ── RE10  Archived groups excluded from the shadow ────────────────────────────

SELECT COUNT(*) AS archived_in_shadow
FROM public.vw_coverage_group_shadow shadow
JOIN public.coverage_groups cg ON cg.id = shadow.coverage_group_id
WHERE cg.archived_at IS NOT NULL;
-- Expected: 0


-- ── RE11  store_preview starts with anchor store name (RS5) ──────────────────

SELECT coverage_code, anchor_store_name, store_preview
FROM public.vw_coverage_group_shadow
WHERE active_store_count >= 1
  AND store_preview NOT LIKE (anchor_store_name || '%');
-- Expected: 0 mismatches


-- ── RE12  account_id in shadow matches coverage_groups.account_id ─────────────
-- Guards against cross-account leakage through store joins.

SELECT shadow.coverage_code, shadow.account_id, cg.account_id AS cg_account_id
FROM public.vw_coverage_group_shadow shadow
JOIN public.coverage_groups cg ON cg.id = shadow.coverage_group_id
WHERE shadow.account_id != cg.account_id;
-- Expected: 0 mismatches (RS8: plantilla cross-check + RS12: account_id agreement)


-- ── vacancy_tab correctness (RS10) ───────────────────────────────────────────

SELECT
  coverage_code,
  open_count, pipeline_count, hr_processing_count, active_count, closed_count,
  required_hc,
  vacancy_tab
FROM public.vw_coverage_group_shadow
WHERE
  -- open rule: open_count > 0 must map to 'open'
  (open_count > 0 AND vacancy_tab != 'open')
  OR
  -- pipeline rule: no open, some pipeline
  (open_count = 0 AND pipeline_count > 0 AND vacancy_tab != 'pipeline')
  OR
  -- hr_processing rule
  (open_count = 0 AND pipeline_count = 0 AND hr_processing_count > 0
   AND vacancy_tab != 'hr_processing')
  OR
  -- filled rule
  (open_count = 0 AND pipeline_count = 0 AND hr_processing_count = 0
   AND active_count > 0 AND closed_count < required_hc
   AND vacancy_tab != 'filled')
  OR
  -- closed rule: all slots closed
  (closed_count = required_hc AND required_hc > 0
   AND open_count = 0 AND pipeline_count = 0 AND hr_processing_count = 0
   AND active_count = 0 AND vacancy_tab != 'closed');
-- Expected: 0 rows (RS10)


-- ── CENCOM cross-shadow sum (RS11: plantilla cross-check + CENCOM consistency)
-- Never union or join the two shadows in SQL.
-- Sum at the aggregation layer to verify system-level HC arithmetic.

SELECT
  'stationary' AS shadow_type,
  COUNT(*)                           AS card_count,
  SUM(required_hc)                   AS total_required_hc,
  SUM(open_count)                    AS total_open,
  SUM(pipeline_count)                AS total_pipeline,
  SUM(hr_processing_count)           AS total_hr_processing,
  SUM(occupied_count)                AS total_filled
FROM public.vw_slot_derived_vacancy_shadow

UNION ALL

SELECT
  'roving' AS shadow_type,
  COUNT(*)                           AS card_count,
  SUM(required_hc)                   AS total_required_hc,
  SUM(open_count)                    AS total_open,
  SUM(pipeline_count)                AS total_pipeline,
  SUM(hr_processing_count)           AS total_hr_processing,
  SUM(active_count)                  AS total_filled
FROM public.vw_coverage_group_shadow;
-- Compare both rows; never sum them in SQL for real-time HC (Flutter/JS layer sums)
-- System Required HC = stationary.total_required_hc + roving.total_required_hc
-- System Filled HC   = stationary.total_filled       + roving.total_filled


-- ── Full regression: RD1–RD12 + stationary A–G ───────────────────────────────
-- Re-run RD1–RD12 validation queries from
--   20260825000000_coverage_group_phase_rd_plantilla_active_transition.sql §RD4
-- Re-run stationary Phase D (D1–D12) from
--   20260820000000_vcode_slot_phase_d_shadow_aggregation.sql §D4
-- All must remain GREEN — Phase RE is view DDL only and writes nothing to
-- tables or RPCs, so upstream invariants should be unaffected.

*/
