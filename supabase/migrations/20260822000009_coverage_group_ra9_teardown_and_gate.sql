-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA9 teardown + gate
-- Migration:  20260822000009_coverage_group_ra9_teardown_and_gate.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA9, §9)
-- Depends on: RA1–RA8.
-- ============================================================
-- Scope: Rollback gate + consolidated RA validation gate. Ships:
--   • fn_coverage_ra_assert_empty()  — refuses teardown if any coverage_*
--                                       table holds rows (archive-first).
--   • fn_coverage_ra_gate()          — runs fn_coverage_ra_validate() and
--                                       raises if any check fails.
--   • Documented reverse-order teardown script (COMMENTED — not executed).
--
--   ROLLBACK STRATEGY (plan §9):
--   • Forward is additive only — new tables, nullable columns, functions,
--     triggers, constraints, indexes. No existing column altered; no live
--     row written. Clean reverse-order drop is safe ONLY while the new
--     tables are empty and no R-B+ code references them.
--   • After population: rollback must ARCHIVE (archived_at), not drop, per
--     the archive-first invariant. Full teardown then needs a separate,
--     explicitly-approved data-destruction step.
--   • POINT OF NO RETURN: once R-F backfills live roving into these tables,
--     RA is no longer cleanly reversible — rollback is a data-loss op
--     requiring elevated approval. fn_coverage_ra_assert_empty() is the gate.
-- ============================================================

-- ── Teardown emptiness gate ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_coverage_ra_assert_empty()
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
AS $empty$
DECLARE
  v_groups bigint := 0;
  v_stores bigint := 0;
  v_slots  bigint := 0;
BEGIN
  IF to_regclass('public.coverage_groups')       IS NOT NULL THEN
    SELECT count(*) INTO v_groups FROM public.coverage_groups;
  END IF;
  IF to_regclass('public.coverage_group_stores') IS NOT NULL THEN
    SELECT count(*) INTO v_stores FROM public.coverage_group_stores;
  END IF;
  IF to_regclass('public.coverage_slots')        IS NOT NULL THEN
    SELECT count(*) INTO v_slots  FROM public.coverage_slots;
  END IF;

  IF (v_groups + v_stores + v_slots) > 0 THEN
    RAISE EXCEPTION
      'RA teardown REFUSED — coverage_* tables not empty (groups=%, stores=%, slots=%). '
      'Archive-first: rollback past population requires a separately-approved '
      'data-destruction step.', v_groups, v_stores, v_slots
      USING ERRCODE = 'check_violation';
  END IF;

  RAISE NOTICE 'RA teardown gate OK — coverage_* tables empty; clean reverse-order drop is safe.';
END
$empty$;

COMMENT ON FUNCTION public.fn_coverage_ra_assert_empty() IS
  'Teardown gate (plan §RA9/§9). Raises unless all coverage_* tables are empty. '
  'Call before running the reverse-order drop script in this migration header.';

-- ── Consolidated RA validation gate ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_coverage_ra_gate()
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
AS $gate$
DECLARE
  v_failed text;
BEGIN
  SELECT string_agg(check_name || ': ' || detail, E'\n  ')
    INTO v_failed
  FROM public.fn_coverage_ra_validate()
  WHERE passed = false;

  IF v_failed IS NOT NULL THEN
    RAISE EXCEPTION E'RA validation gate FAILED:\n  %', v_failed;
  END IF;

  RAISE NOTICE 'RA validation gate GREEN — all structural checks passed.';
END
$gate$;

COMMENT ON FUNCTION public.fn_coverage_ra_gate() IS
  'Consolidated RA gate — raises if any fn_coverage_ra_validate() check fails. '
  'Run after RA8 as the RA acceptance probe.';

REVOKE ALL ON FUNCTION public.fn_coverage_ra_assert_empty() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_coverage_ra_assert_empty() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_coverage_ra_assert_empty() TO service_role;

REVOKE ALL ON FUNCTION public.fn_coverage_ra_gate() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_coverage_ra_gate() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_coverage_ra_gate() TO service_role;

-- Run the gate now (final acceptance — raises if RA is not structurally GREEN).
SELECT public.fn_coverage_ra_gate();

-- ============================================================
-- REVERSE-ORDER TEARDOWN SCRIPT (DOCUMENTED — DO NOT UNCOMMENT BLINDLY)
-- Run only after fn_coverage_ra_assert_empty() succeeds. Drops in strict
-- reverse FK order. Each step is the inverse of RA7→RA1.
-- ============================================================
--
--   SELECT public.fn_coverage_ra_assert_empty();   -- gate; aborts if rows exist
--
--   -- RA7 store-link re-point columns
--   ALTER TABLE public.plantilla_store_links DROP CONSTRAINT IF EXISTS plantilla_store_links_coverage_group_fkey;
--   ALTER TABLE public.plantilla_store_links DROP COLUMN IF EXISTS coverage_group_id;
--   ALTER TABLE public.hr_emploc_store_links DROP CONSTRAINT IF EXISTS hr_emploc_store_links_coverage_group_fkey;
--   ALTER TABLE public.hr_emploc_store_links DROP COLUMN IF EXISTS coverage_group_id;
--
--   -- RA6 binding columns
--   ALTER TABLE public.plantilla  DROP CONSTRAINT IF EXISTS plantilla_coverage_slot_fkey,
--                                 DROP CONSTRAINT IF EXISTS plantilla_coverage_group_fkey;
--   ALTER TABLE public.plantilla  DROP COLUMN IF EXISTS coverage_slot_id, DROP COLUMN IF EXISTS coverage_group_id;
--   ALTER TABLE public.hr_emploc  DROP CONSTRAINT IF EXISTS hr_emploc_coverage_slot_fkey,
--                                 DROP CONSTRAINT IF EXISTS hr_emploc_coverage_group_fkey;
--   ALTER TABLE public.hr_emploc  DROP COLUMN IF EXISTS coverage_slot_id, DROP COLUMN IF EXISTS coverage_group_id;
--   ALTER TABLE public.applicants DROP CONSTRAINT IF EXISTS applicants_coverage_slot_fkey,
--                                 DROP CONSTRAINT IF EXISTS applicants_coverage_group_fkey;
--   ALTER TABLE public.applicants DROP COLUMN IF EXISTS coverage_slot_id, DROP COLUMN IF EXISTS coverage_group_id;
--
--   -- RA5 eager-emit
--   DROP TRIGGER IF EXISTS trg_emit_coverage_slots ON public.coverage_groups;
--   DROP FUNCTION IF EXISTS public.fn_emit_coverage_slots();
--
--   -- RA4 / RA3 / RA1 tables (slots & footprint reference the group)
--   DROP TABLE IF EXISTS public.coverage_slots;
--   DROP TRIGGER IF EXISTS trg_assert_coverage_store_same_account ON public.coverage_group_stores;
--   DROP FUNCTION IF EXISTS public.fn_assert_coverage_store_same_account();
--   DROP TABLE IF EXISTS public.coverage_group_stores;
--   DROP TABLE IF EXISTS public.coverage_groups;
--
--   -- RA2 minter + sequence store
--   DROP FUNCTION IF EXISTS public.fn_generate_cgcode_for_account(uuid);
--   DROP TABLE IF EXISTS public.cgcode_sequences;
--
--   -- RA8 / RA9 harness
--   DROP FUNCTION IF EXISTS public.fn_coverage_ra_validate();
--   DROP FUNCTION IF EXISTS public.fn_coverage_ra_gate();
--   DROP FUNCTION IF EXISTS public.fn_coverage_ra_assert_empty();
-- ============================================================
