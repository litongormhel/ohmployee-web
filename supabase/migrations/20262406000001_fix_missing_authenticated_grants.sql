-- Migration: 20262406000001_fix_missing_authenticated_grants
-- Created: 2026-06-24
-- Purpose: Grant SELECT on all views and tables queried directly by Flutter/Web
--          clients that were missed by 20262306000000_grant_authenticated_select_all_views.
--          Fixes: Plantilla (employee_store_allocations 42501), CENCOM allocation views,
--          and Coverage Groups (vw_coverage_group_shadow was in smoke test but not in GRANT).
--
-- Smoke Tests:
-- S1: SELECT COUNT(*) FROM information_schema.role_table_grants
--     WHERE grantee='authenticated' AND privilege_type='SELECT'
--       AND table_schema='public'
--       AND table_name IN (
--         'employee_store_allocations',
--         'v_cencom_allocation_kpi',
--         'v_cencom_group_allocation_kpi',
--         'v_cencom_account_allocation_kpi',
--         'vw_coverage_group_shadow'
--       );
--     -- expect 5
-- S2: Plantilla, CENCOM, Vacancy (Coverage Groups banner), all load without 42501 errors.

BEGIN;

-- ─── TABLE: employee_store_allocations ────────────────────────────────────────
-- Direct table query in plantilla_scope_service.dart — caused 42501 on Plantilla.
DO $$ BEGIN
  GRANT SELECT ON public.employee_store_allocations TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: employee_store_allocations not found';
END $$;

-- ─── TABLE: coverage_groups ───────────────────────────────────────────────────
DO $$ BEGIN
  GRANT SELECT ON public.coverage_groups TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: coverage_groups not found';
END $$;

-- ─── TABLE: import_roving_groups ──────────────────────────────────────────────
DO $$ BEGIN
  GRANT SELECT ON public.import_roving_groups TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: import_roving_groups not found';
END $$;

-- ─── TABLE: plantilla_store_links ─────────────────────────────────────────────
DO $$ BEGIN
  GRANT SELECT ON public.plantilla_store_links TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: plantilla_store_links not found';
END $$;

-- ─── TABLE: temp_permission_overrides ─────────────────────────────────────────
DO $$ BEGIN
  GRANT SELECT ON public.temp_permission_overrides TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: temp_permission_overrides not found';
END $$;

-- ─── TABLE: alert_flags ───────────────────────────────────────────────────────
DO $$ BEGIN
  GRANT SELECT ON public.alert_flags TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: alert_flags not found';
END $$;

-- ─── CENCOM allocation views (missed by previous migration) ───────────────────
-- Previous migration only granted v_cencom_account_kpi / v_cencom_group_kpi /
-- v_cencom_kpi. CencomService queries the *_allocation_* variants.
DO $$ BEGIN
  GRANT SELECT ON public.v_cencom_allocation_kpi TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: v_cencom_allocation_kpi not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.v_cencom_group_allocation_kpi TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: v_cencom_group_allocation_kpi not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.v_cencom_account_allocation_kpi TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: v_cencom_account_allocation_kpi not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.v_account_allocation_kpi TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: v_account_allocation_kpi not found';
END $$;

-- ─── vw_coverage_group_shadow ─────────────────────────────────────────────────
-- list_coverage_groups is SECURITY INVOKER — callers need SELECT on this view.
-- Was cited in smoke test of 20262306000000 but NOT included in its GRANT block.
DO $$ BEGIN
  GRANT SELECT ON public.vw_coverage_group_shadow TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: vw_coverage_group_shadow not found';
END $$;

-- ─── vw_slot_derived_vacancy_shadow ───────────────────────────────────────────
-- Queried directly by vacancy_service.dart for the Open/Pipeline tabs.
DO $$ BEGIN
  GRANT SELECT ON public.vw_slot_derived_vacancy_shadow TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: vw_slot_derived_vacancy_shadow not found';
END $$;

-- ─── Remaining views queried directly by Flutter services ─────────────────────
DO $$ BEGIN
  GRANT SELECT ON public.v_vacancy_deployment_indicators TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: v_vacancy_deployment_indicators not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.v_workforce_store_temporary_coverage TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: v_workforce_store_temporary_coverage not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.vw_amr_vacancy_reservation_status TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: vw_amr_vacancy_reservation_status not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.vw_applicant_backout_timeline TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: vw_applicant_backout_timeline not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.vw_archived_vacancies TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: vw_archived_vacancies not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.vw_vacancy_detail TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: vw_vacancy_detail not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.vw_active_sessions TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: vw_active_sessions not found';
END $$;

DO $$ BEGIN
  GRANT SELECT ON public.v_vacancy_pipeline_status TO authenticated;
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'SKIP: v_vacancy_pipeline_status not found';
END $$;

COMMIT;
