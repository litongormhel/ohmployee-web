-- ============================================================
-- OHM2026_0066 — Coverage Group Phase R-A — RA8 validation harness
-- Migration:  20260822000008_coverage_group_ra8_validation_harness.sql
-- Plan:       docs/architecture/coverage_group_phase_ra_schema_plan.md (§RA8, §10)
-- Depends on: RA1–RA7.
-- ============================================================
-- Scope: READ-ONLY structural assertion harness — the RA peer of the
--   Phase A–G validation queries. No business logic, no writes. Implements
--   the schema-only half of the §10 suite (catalog shape, carved-out-of-
--   shadow, binding-columns-empty). Lifecycle assertions (reconciliation
--   under transitions, no-forbidden-jumps) attach at R-B…R-G.
--
--   fn_coverage_ra_validate() returns one row per check:
--     (check_name text, passed boolean, detail text)
--   RA is structurally GREEN when every row has passed = true.
--
--   The CONSTRAINT-ENFORCEMENT probes (insert two same-code rows → rejected,
--   occupied token → rejected, cross-account store → rejected, two anchors →
--   rejected) are inherently writes; run them MANUALLY inside a rolled-back
--   transaction. Template (does NOT persist):
--
--     BEGIN;
--       SAVEPOINT p;
--       -- expect 'CG-…' :
--       SELECT public.fn_generate_cgcode_for_account('<account uuid>');
--       -- expect ERROR (bad prefix CHECK):
--       INSERT INTO public.coverage_groups
--         (coverage_code, account_id, position_id, employment_type, required_headcount)
--         VALUES ('BAD-001', '<acct>', '<pos>', 'regular', 1);
--       ROLLBACK TO p;
--       -- expect ERROR (required_headcount >= 1):
--       INSERT INTO public.coverage_groups
--         (coverage_code, account_id, position_id, employment_type, required_headcount)
--         VALUES ('CG-X-0001', '<acct>', '<pos>', 'regular', 0);
--       ROLLBACK TO p;
--       -- expect ERROR (slot token: 'occupied' not allowed):
--       -- insert a valid group, then UPDATE a slot to 'occupied' → rejected.
--     ROLLBACK;
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_coverage_ra_validate()
  RETURNS TABLE (check_name text, passed boolean, detail text)
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
AS $val$
DECLARE
  v_shadow_def text;
  v_bound_count bigint;
BEGIN
  -- 1. Three new tables + sequence store exist
  RETURN QUERY SELECT
    'tables_exist',
    (to_regclass('public.coverage_groups') IS NOT NULL
     AND to_regclass('public.coverage_group_stores') IS NOT NULL
     AND to_regclass('public.coverage_slots') IS NOT NULL
     AND to_regclass('public.cgcode_sequences') IS NOT NULL),
    'coverage_groups, coverage_group_stores, coverage_slots, cgcode_sequences';

  -- 2. CGCODE minter exists, granted to service_role only
  RETURN QUERY SELECT
    'cgcode_minter_present',
    EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fn_generate_cgcode_for_account'
    ),
    'fn_generate_cgcode_for_account(uuid) SECURITY DEFINER';

  -- 3. CHECK constraints present
  RETURN QUERY SELECT
    'checks_present',
    (EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coverage_groups_required_hc_check')
     AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coverage_groups_code_prefix_check')
     AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coverage_slots_status_check')
     AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coverage_slots_ordinal_check')),
    'required_hc>=1, code LIKE CG-%, slot token set, slot_ordinal>=1';

  -- 4. Slot token CHECK encodes 'active' (not 'occupied')
  RETURN QUERY SELECT
    'slot_token_is_active',
    EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'coverage_slots_status_check'
        AND pg_get_constraintdef(oid) LIKE '%active%'
        AND pg_get_constraintdef(oid) NOT LIKE '%occupied%'
    ),
    'coverage_slots_status_check contains active, excludes occupied (OHM2026_0064)';

  -- 5. Partial unique constraints present
  RETURN QUERY SELECT
    'partial_uniques_present',
    (to_regclass('public.uq_coverage_groups_account_code_active') IS NOT NULL
     AND to_regclass('public.uq_coverage_group_stores_active_edge') IS NOT NULL
     AND to_regclass('public.uq_coverage_group_stores_active_anchor') IS NOT NULL
     AND to_regclass('public.uq_coverage_slots_group_ordinal') IS NOT NULL),
    'per-account CGCODE, active edge, active anchor, ordinal-per-group';

  -- 6. FK set present (group/store/slot parents)
  RETURN QUERY SELECT
    'fk_set_present',
    (EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coverage_groups_account_fkey')
     AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coverage_group_stores_group_fkey')
     AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coverage_slots_group_fkey')),
    'coverage_groups→accounts/positions, footprint→group/store, slot→group';

  -- 7. Eager slot-emit trigger present
  RETURN QUERY SELECT
    'eager_emit_trigger_present',
    EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = 'trg_emit_coverage_slots' AND NOT tgisinternal
    ),
    'AFTER INSERT on coverage_groups → fn_emit_coverage_slots';

  -- 8. Cross-account footprint guard present
  RETURN QUERY SELECT
    'xaccount_guard_present',
    EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = 'trg_assert_coverage_store_same_account' AND NOT tgisinternal
    ),
    'BEFORE INSERT/UPDATE on coverage_group_stores → same-account assert';

  -- 9. Binding columns exist and are nullable on all 5 record/link tables
  RETURN QUERY SELECT
    'binding_columns_nullable',
    NOT EXISTS (
      SELECT 1 FROM (VALUES
        ('applicants','coverage_slot_id'), ('applicants','coverage_group_id'),
        ('hr_emploc','coverage_slot_id'),  ('hr_emploc','coverage_group_id'),
        ('plantilla','coverage_slot_id'),  ('plantilla','coverage_group_id'),
        ('hr_emploc_store_links','coverage_group_id'),
        ('plantilla_store_links','coverage_group_id')
      ) AS want(tbl, col)
      LEFT JOIN information_schema.columns c
        ON c.table_schema = 'public' AND c.table_name = want.tbl AND c.column_name = want.col
      WHERE c.column_name IS NULL OR c.is_nullable <> 'YES'
    ),
    'coverage_slot_id/coverage_group_id present + nullable everywhere';

  -- 10. Binding columns EMPTY (zero stationary rows touched)
  SELECT
    (SELECT count(*) FROM public.applicants WHERE coverage_slot_id IS NOT NULL OR coverage_group_id IS NOT NULL)
  + (SELECT count(*) FROM public.hr_emploc  WHERE coverage_slot_id IS NOT NULL OR coverage_group_id IS NOT NULL)
  + (SELECT count(*) FROM public.plantilla  WHERE coverage_slot_id IS NOT NULL OR coverage_group_id IS NOT NULL)
  + (SELECT count(*) FROM public.hr_emploc_store_links WHERE coverage_group_id IS NOT NULL)
  + (SELECT count(*) FROM public.plantilla_store_links WHERE coverage_group_id IS NOT NULL)
  INTO v_bound_count;

  RETURN QUERY SELECT
    'binding_columns_empty',
    (v_bound_count = 0),
    format('non-null coverage bindings across record/link tables = %s (want 0)', v_bound_count);

  -- 11. Carved out of the stationary shadow (view does not reference coverage_*)
  v_shadow_def := pg_get_viewdef('public.vw_slot_derived_vacancy_shadow'::regclass, true);
  RETURN QUERY SELECT
    'carved_out_of_shadow',
    (v_shadow_def NOT ILIKE '%coverage_group%' AND v_shadow_def NOT ILIKE '%coverage_slot%'),
    'vw_slot_derived_vacancy_shadow definition references no coverage_* object';

  RETURN;
END
$val$;

COMMENT ON FUNCTION public.fn_coverage_ra_validate() IS
  'Read-only RA structural validation harness (plan §RA8/§10). One row per '
  'check; RA is structurally GREEN when all passed = true. Enforcement probes '
  '(negative inserts) are run manually in a rolled-back txn — see migration header.';

REVOKE ALL ON FUNCTION public.fn_coverage_ra_validate() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_coverage_ra_validate() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_coverage_ra_validate() TO service_role;

-- Acceptance probe (run after apply): every row should read passed = true.
--   SELECT * FROM public.fn_coverage_ra_validate() ORDER BY check_name;
