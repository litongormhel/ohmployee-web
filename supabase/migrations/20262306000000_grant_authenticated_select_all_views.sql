-- Migration: 20262306000000_grant_authenticated_select_all_views
-- Created: 2026-06-23
-- Purpose: Grant SELECT on all public views to the authenticated role so Flutter clients can query them.
--
-- Smoke Tests:
-- S1: SELECT COUNT(*) FROM information_schema.role_table_grants WHERE grantee='authenticated' AND privilege_type='SELECT' AND table_schema='public' AND table_name IN ('v_plantilla_safe','v_hr_emploc_sla_flags','vw_coverage_group_shadow'); -- expect 3
-- S2: HR Emploc, CENCOM, and Coverage Groups load without permission errors in the Flutter app.

BEGIN;

GRANT SELECT ON
  public.headcount_summary,
  public.team_performance_summary,
  public.transfer_requests,
  public.v_account_kpi,
  public.v_account_position_options,
  public.v_approval_queue,
  public.v_audit_activity_feed,
  public.v_cencom_account_kpi,
  public.v_cencom_group_kpi,
  public.v_cencom_kpi,
  public.v_deactivation_requests,
  public.v_group_kpi,
  public.v_hr_emploc_backout_report,
  public.v_hr_emploc_sla_flags,
  public.v_mika_import_rows_safe,
  public.v_plantilla_safe,
  public.v_qa_daily_reports,
  public.v_qa_detection_run_summary,
  public.v_qa_flaky_tests,
  public.v_qa_health_metrics,
  public.v_qa_notifications,
  public.v_qa_open_findings,
  public.v_qa_run_queue,
  public.v_qa_schedules,
  public.v_qa_unstable_modules,
  public.v_store_import_approval_queue,
  public.v_store_master_import_preview,
  public.v_vacancy_active_coverage,
  public.v_workforce_assignment_request_queue,
  public.v_workforce_assignment_review_queue,
  public.v_workforce_pool_conversion_requests,
  public.v_workforce_pool_employees,
  public.v_workforce_slot_reviews,
  public.view_archived_records,
  public.vw_account_handlers,
  public.vw_accounts_with_group,
  public.vw_applicant_funnel,
  public.vw_archived_plantilla,
  public.vw_attrition_rate,
  public.vw_gap_metrics,
  public.vw_ghost_cases_active,
  public.vw_monthly_hires,
  public.vw_open_vacancies_by_store,
  public.vw_plantilla_status_counts,
  public.vw_ready_to_plantilla,
  public.vw_recruiter_sla,
  public.vw_rejected_emploc_active,
  public.vw_sla_breach_summary,
  public.vw_sla_by_group,
  public.vw_vacancy_by_region,
  public.vw_vacancy_closure_pending
TO authenticated;

COMMIT;
