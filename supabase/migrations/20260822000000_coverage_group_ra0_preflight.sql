-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA0 Preflight
-- Migration:  20260822000000_coverage_group_ra0_preflight.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA0)
-- ============================================================
-- Scope: ASSERTION-ONLY. No schema change. Fails fast if any live
--   parent the RA phase depends on is missing, or if the coverage_*
--   names are already taken (clean first-apply contract).
--
--   This migration deliberately does NOT:
--     • create any table, column, function, trigger, index, or policy,
--     • touch the stationary VCODE↔Slot model (Phases A–G, GREEN),
--     • touch the Vacancy / applicant / HR Emploc lifecycle,
--     • read or mutate roving_assignments / live roving data.
--
-- Inherited locked constraints (do NOT re-open):
--   • Stationary = VCODE; roving = CGCODE. Disjoint namespaces.
--   • HC lives on the group (required_headcount); covered stores = 0 HC.
--   • Coverage groups stay carved out of vw_slot_derived_vacancy_shadow.
--   • Filled coverage-slot token = 'active' (occupied = stationary only).
-- ============================================================

DO $ra0$
DECLARE
  v_missing   text := '';
  v_taken     text := '';
  v_rel       text;
  v_fn        text;
BEGIN
  -- ── Required live parent TABLES ─────────────────────────────
  FOREACH v_rel IN ARRAY ARRAY[
    'accounts', 'positions', 'stores', 'users_profile',
    'applicants', 'hr_emploc', 'plantilla',
    'hr_emploc_store_links', 'plantilla_store_links',
    'vcode_sequences'
  ] LOOP
    IF to_regclass('public.' || v_rel) IS NULL THEN
      v_missing := v_missing || '  - table public.' || v_rel || E'\n';
    END IF;
  END LOOP;

  -- ── Required live VIEW (carve-out anchor) ───────────────────
  IF to_regclass('public.vw_slot_derived_vacancy_shadow') IS NULL THEN
    v_missing := v_missing || '  - view public.vw_slot_derived_vacancy_shadow' || E'\n';
  END IF;

  -- ── stores.account_id (needed by the cross-account guard) ───
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'stores'
      AND column_name = 'account_id'
  ) THEN
    v_missing := v_missing || '  - column public.stores.account_id' || E'\n';
  END IF;

  -- ── Required live FUNCTIONS ─────────────────────────────────
  FOREACH v_fn IN ARRAY ARRAY[
    'generate_vcode_for_account',   -- minter reference (NOT reused)
    'i_have_full_access',           -- RLS predicate
    'get_my_allowed_account_ids'    -- RLS predicate
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = v_fn
    ) THEN
      v_missing := v_missing || '  - function public.' || v_fn || '()' || E'\n';
    END IF;
  END LOOP;

  IF v_missing <> '' THEN
    RAISE EXCEPTION E'RA0 preflight FAILED — missing live dependencies:\n%', v_missing;
  END IF;

  -- ── coverage_* names must be FREE on clean first apply ──────
  --   (Supabase tracks applied migrations; RA0 never re-runs. A manual
  --    re-run on a half-applied RA set must roll back first — see RA9.)
  FOREACH v_rel IN ARRAY ARRAY[
    'coverage_groups', 'coverage_group_stores', 'coverage_slots',
    'cgcode_sequences'
  ] LOOP
    IF to_regclass('public.' || v_rel) IS NOT NULL THEN
      v_taken := v_taken || '  - public.' || v_rel || ' already exists' || E'\n';
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_generate_cgcode_for_account'
  ) THEN
    v_taken := v_taken || '  - public.fn_generate_cgcode_for_account() already exists' || E'\n';
  END IF;

  IF v_taken <> '' THEN
    RAISE EXCEPTION E'RA0 preflight FAILED — coverage_* namespace not free:\n%Roll back the RA set (see RA9) before re-applying.', v_taken;
  END IF;

  RAISE NOTICE 'RA0 preflight OK — all live parents present; coverage_* namespace free.';
END
$ra0$;
