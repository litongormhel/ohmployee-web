-- Migration: 20262406000002_fix_coverage_slots_and_remaining_grants
-- Created: 2026-06-24
-- Updated: 2026-06-24 (added plantilla_slots + slot_history — found via live staging audit)
-- Purpose: Grant SELECT on tables/views still missing after 20262406000001.
--
--          Root cause of remaining staging errors:
--          1. coverage_slots — referenced by v_account_allocation_kpi (SECURITY INVOKER);
--             authenticated callers need SELECT on the underlying table.
--             Symptom: Plantilla screen snackbar "permission denied for table coverage_slots" (42501).
--             Secondary: CENCOM "Unable to load CENCOM data" (same view stack).
--          2. coverage_group_stores — referenced by vw_slot_derived_vacancy_shadow and
--             vw_coverage_group_shadow (both SECURITY INVOKER); caller needs SELECT on
--             underlying tables even when the view itself is already granted.
--             Symptom: Vacancy screen "Coverage Groups unavailable".
--          3. v_vacancy_active_coverage — direct .from('v_vacancy_active_coverage') in
--             vacancy_service.dart; was not included in either previous grant migration.
--          4. vacancy_coverage — direct .from('vacancy_coverage') in vacancy_service.dart.
--          5. deployer — direct .from('deployer') in vacancy_service.dart.
--          6. hc_request_stores — referenced by coverage / roving HC backend views.
--          7. plantilla_slots — referenced by v_account_allocation_kpi (slot_vacant_non_roving
--             and slot_vacant_roving CTEs, both SECURITY INVOKER). Missed by all prior grant
--             migrations. Confirmed missing via staging audit 2026-06-24.
--             Symptom: same 42501 — v_account_allocation_kpi fails because authenticated
--             role cannot read plantilla_slots even though coverage_slots is now granted.
--          8. slot_history — referenced by vw_slot_derived_vacancy_shadow and
--             vw_slot_derived_vacancy_shadow_detail (aging_basis CTE). Missed by all prior
--             grant migrations. Confirmed missing via staging audit 2026-06-24.
--             Symptom: vacancy shadow view fails to compute slot aging for Open/Pipeline tabs.
--
--          No destructive SQL. No DROP. No data mutation. Grants only.
--          Idempotent: each GRANT wrapped in DO $$ BEGIN ... EXCEPTION WHEN ... END $$.

BEGIN;

-- ─── TABLE: coverage_slots ────────────────────────────────────────────────────
-- Underlying table of v_account_allocation_kpi (SECURITY INVOKER).
-- Plantilla snackbar: "permission denied for table coverage_slots" (42501).
-- CENCOM: "Unable to load CENCOM data" — same allocation view stack.
DO $$ BEGIN
  GRANT SELECT ON public.coverage_slots TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: coverage_slots not found';
END $$;

-- ─── TABLE: coverage_group_stores ─────────────────────────────────────────────
-- Underlying table of vw_slot_derived_vacancy_shadow and vw_coverage_group_shadow
-- (both SECURITY INVOKER). Caller needs SELECT even after the views themselves are
-- already granted. Symptom: Vacancy "Coverage Groups unavailable".
DO $$ BEGIN
  GRANT SELECT ON public.coverage_group_stores TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: coverage_group_stores not found';
END $$;

-- ─── VIEW: v_vacancy_active_coverage ─────────────────────────────────────────
-- Direct .from('v_vacancy_active_coverage') in vacancy_service.dart.
DO $$ BEGIN
  GRANT SELECT ON public.v_vacancy_active_coverage TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: v_vacancy_active_coverage not found';
END $$;

-- ─── TABLE: vacancy_coverage ─────────────────────────────────────────────────
-- Direct .from('vacancy_coverage') in vacancy_service.dart (fetchVacancyCoverage,
-- fetchCoveredStores).
DO $$ BEGIN
  GRANT SELECT ON public.vacancy_coverage TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: vacancy_coverage not found';
END $$;

-- ─── TABLE: deployer ─────────────────────────────────────────────────────────
-- Direct .from('deployer') in vacancy_service.dart (searchDeployers).
DO $$ BEGIN
  GRANT SELECT ON public.deployer TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: deployer not found';
END $$;

-- ─── TABLE: hc_request_stores ────────────────────────────────────────────────
-- Referenced by backend views used in roving HC request and coverage group flows.
DO $$ BEGIN
  GRANT SELECT ON public.hc_request_stores TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: hc_request_stores not found';
END $$;

-- ─── TABLE: plantilla_slots ───────────────────────────────────────────────────
-- Referenced by v_account_allocation_kpi (slot_vacant_non_roving + slot_vacant_roving
-- CTEs). Both CTEs are inside a SECURITY INVOKER view — authenticated callers need
-- SELECT on the underlying table. Missing this grant means the entire allocation KPI
-- view chain fails even after coverage_slots is granted.
-- Confirmed missing via staging grant audit 2026-06-24 (ohm#f6t9v2k8).
DO $$ BEGIN
  GRANT SELECT ON public.plantilla_slots TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: plantilla_slots not found';
END $$;

-- ─── TABLE: slot_history ─────────────────────────────────────────────────────
-- Referenced by vw_slot_derived_vacancy_shadow and vw_slot_derived_vacancy_shadow_detail
-- (aging_basis CTE reads slot_history to compute open-episode start date for vacancy aging).
-- Both views are SECURITY INVOKER. Missing grant breaks slot aging on Open/Pipeline tabs.
-- Confirmed missing via staging grant audit 2026-06-24 (ohm#f6t9v2k8).
DO $$ BEGIN
  GRANT SELECT ON public.slot_history TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: slot_history not found';
END $$;

COMMIT;

-- ─── SMOKE TEST QUERIES ───────────────────────────────────────────────────────
-- Run these as the authenticated role (via Supabase SQL Editor with app JWT) after push.
--
-- S1: Verify coverage_slots grant (Plantilla / CENCOM path dependency)
--   SELECT COUNT(*) FROM public.coverage_slots;
--   -- expect: integer >= 0 (no 42501 error)
--
-- S2: Load CENCOM KPI views (CENCOM "Unable to load CENCOM data" fix)
--   SELECT COUNT(*) FROM public.v_cencom_allocation_kpi;
--   SELECT COUNT(*) FROM public.v_cencom_group_allocation_kpi;
--   SELECT COUNT(*) FROM public.v_cencom_account_allocation_kpi;
--   -- expect: integer >= 0 (no 42501 error)
--
-- S3: Load Vacancy with coverage groups (Vacancy "Coverage Groups unavailable" fix)
--   SELECT COUNT(*) FROM public.vw_coverage_group_shadow;
--   SELECT COUNT(*) FROM public.vw_slot_derived_vacancy_shadow;
--   -- expect: integer >= 0 (no 42501 error)
--
-- S4: Load Plantilla account list (coverage_slots path)
--   SELECT COUNT(*) FROM public.v_account_allocation_kpi;
--   -- expect: integer >= 0 (no 42501 error)
--
-- S5: Verify remaining direct table/view grants
--   SELECT COUNT(*) FROM public.v_vacancy_active_coverage;
--   SELECT COUNT(*) FROM public.vacancy_coverage;
--   SELECT COUNT(*) FROM public.deployer WHERE is_active = true;
--   SELECT COUNT(*) FROM public.hc_request_stores;
--   -- expect: integer >= 0 (no 42501 error)
--
-- Full grant inventory check:
--   SELECT table_name
--   FROM information_schema.role_table_grants
--   WHERE grantee = 'authenticated'
--     AND privilege_type = 'SELECT'
--     AND table_schema = 'public'
--     AND table_name IN (
--       'coverage_slots', 'coverage_group_stores',
--       'v_vacancy_active_coverage', 'vacancy_coverage',
--       'deployer', 'hc_request_stores',
--       'plantilla_slots', 'slot_history'
--     )
--   ORDER BY table_name;
--   -- expect: 8 rows
--
-- S6: Verify v_account_allocation_kpi resolves (plantilla_slots fix)
--   SELECT COUNT(*) FROM public.v_account_allocation_kpi;
--   -- expect: integer >= 0 (no 42501 error)
--
-- S7: Verify vw_slot_derived_vacancy_shadow resolves (slot_history fix)
--   SELECT COUNT(*) FROM public.vw_slot_derived_vacancy_shadow;
--   -- expect: integer >= 0 (no 42501 error)
