# Migration File Reconciliation Audit

**Date:** 2026-10-26
**Audited Inputs:** `docs/audit/migration_history_prod.txt` (authoritative production baseline export, exported by Ohm from production `rwxelulyapjgaarlwkus`), production sequence directives from Ohm, and `supabase/migrations/`.
**Scope:** Local migration file naming reconciliation only. Zero SQL content modified. Zero database access performed.

---

## 1. Summary of Reconciliation

- **Total Production Migrations Audited:** 104
- **Exact Matches (DB version & name == Repo file):** 100
- **Renamed to match Production Version (`git mv`):** 2
  1. `20262606000066_relax_store_name_multivcode_rule.sql` &rarr; `20262606000072_relax_store_name_multivcode_rule.sql`
  2. `20262606000067_fix_plantilla_import_role_check_parity.sql` &rarr; `20262606000073_fix_plantilla_import_role_check_parity.sql`
- **Collisions Encountered:** 0 (neither target filename existed in repo prior to rename)
- **Production Migrations Missing in Repo:** 2 (documented; not recreated)
  1. `20262606000066_wrap_get_my_scoped_vcodes_initplan`
  2. `20262606000067_restore_security_invoker_vw_slot_derived_vacancy_shadow`
- **Extra Migrations in Repo (Not in Prod 104 Baseline):** 376 (preserved as local development migrations; not modified or deleted)

---

## 2. Production Migrations vs Repo Files

| # | Production DB Version | Migration Name | Repo Filename | Reconciliation Status |
|---|---|---|---|---|
| 1 | `20260520012746` | `remote_schema` | `20260520012746_remote_schema.sql` | **Match** |
| 2 | `20260520012857` | `remote_schema` | `20260520012857_remote_schema.sql` | **Match** |
| 3 | `20260520100000` | `cencom_phase1_scope_restriction` | `20260520100000_cencom_phase1_scope_restriction.sql` | **Match** |
| 4 | `20260520200000` | `cencom_phase2_weekly_snapshots` | `20260520200000_cencom_phase2_weekly_snapshots.sql` | **Match** |
| 5 | `20260520300000` | `cencom_phase3_snapshot_rpc_delta` | `20260520300000_cencom_phase3_snapshot_rpc_delta.sql` | **Match** |
| 6 | `20260520500000` | `hr_emploc_deletion_request_finalize` | `20260520500000_hr_emploc_deletion_request_finalize.sql` | **Match** |
| 7 | `20260520600000` | `cencom_phase8a_target_deployment_backend` | `20260520600000_cencom_phase8a_target_deployment_backend.sql` | **Match** |
| 8 | `20260520700000` | `applicant_backend_infra` | `20260520700000_applicant_backend_infra.sql` | **Match** |
| 9 | `20260521062541` | `restore_tg_close_vacancy_on_plantilla_active_insert` | `20260521062541_restore_tg_close_vacancy_on_plantilla_active_insert.sql` | **Match** |
| 10 | `20260521062542` | `restore_fn_is_active_vacancy_applicant_status` | `20260521062542_restore_fn_is_active_vacancy_applicant_status.sql` | **Match** |
| 11 | `20260521062543` | `remote_schema` | `20260521062543_remote_schema.sql` | **Match** |
| 12 | `20260521110000` | `fix_active_applicant_occupancy` | `20260521110000_fix_active_applicant_occupancy.sql` | **Match** |
| 13 | `20260521200000` | `vcode_duplicate_cleanup` | `20260521200000_vcode_duplicate_cleanup.sql` | **Match** |
| 14 | `20260521900000` | `fix_applicant_status_transition_rules` | `20260521900000_fix_applicant_status_transition_rules.sql` | **Match** |
| 15 | `20260521950000` | `fix_fn_get_applicant_status_options_overload` | `20260521950000_fix_fn_get_applicant_status_options_overload.sql` | **Match** |
| 16 | `20260521990000` | `fix_hc_request_area_carry_over` | `20260521990000_fix_hc_request_area_carry_over.sql` | **Match** |
| 17 | `20260521990100` | `fix_hc_request_area_ingestion` | `20260521990100_fix_hc_request_area_ingestion.sql` | **Match** |
| 18 | `20260522000000` | `applicant_profile_once_edit` | `20260522000000_applicant_profile_once_edit.sql` | **Match** |
| 19 | `20260522010000` | `fix_applicant_profile_once_rbac` | `20260522010000_fix_applicant_profile_once_rbac.sql` | **Match** |
| 20 | `20260522020000` | `add_fn_get_hired_applicants` | `20260522020000_add_fn_get_hired_applicants.sql` | **Match** |
| 21 | `20260522030000` | `fix_fn_get_hired_applicants_source` | `20260522030000_fix_fn_get_hired_applicants_source.sql` | **Match** |
| 22 | `20260522040000` | `add_hired_date_to_confirm_applicant_onboard` | `20260522040000_add_hired_date_to_confirm_applicant_onboard.sql` | **Match** |
| 23 | `20260522100000` | `fix_hc_request_city_municipality` | `20260522100000_fix_hc_request_city_municipality.sql` | **Match** |
| 24 | `20260522113223` | `fix_plantilla_request_deactivation_profile_fk` | `20260522113223_fix_plantilla_request_deactivation_profile_fk.sql` | **Match** |
| 25 | `20260522200000` | `account_request_identity_v1_1` | `20260522200000_account_request_identity_v1_1.sql` | **Match** |
| 26 | `20260522210000` | `request_account_signup_options_rpc` | `20260522210000_request_account_signup_options_rpc.sql` | **Match** |
| 27 | `20260522220000` | `team_directory_backend_v1` | `20260522220000_team_directory_backend_v1.sql` | **Match** |
| 28 | `20260523000000` | `approval_queue_scope_hydration` | `20260523000000_approval_queue_scope_hydration.sql` | **Match** |
| 29 | `20260523001000` | `fix_approval_queue_scope_ids` | `20260523001000_fix_approval_queue_scope_ids.sql` | **Match** |
| 30 | `20260523100000` | `fix_user_management_backend` | `20260523100000_fix_user_management_backend.sql` | **Match** |
| 31 | `20260523110000` | `fix_team_directory_account_scope_filter` | `20260523110000_fix_team_directory_account_scope_filter.sql` | **Match** |
| 32 | `20260524100000` | `deactivation_v2_foundation` | `20260524100000_deactivation_v2_foundation.sql` | **Match** |
| 33 | `20260524105828` | `web_current_user_context` | `20260524105828_web_current_user_context.sql` | **Match** |
| 34 | `20260524110000` | `deactivation_v2_rpcs` | `20260524110000_deactivation_v2_rpcs.sql` | **Match** |
| 35 | `20260524115000` | `fix_deactivation_request_rpc_conflict` | `20260524115000_fix_deactivation_request_rpc_conflict.sql` | **Match** |
| 36 | `20260524116000` | `fix_deactivation_notification_user_id` | `20260524116000_fix_deactivation_notification_user_id.sql` | **Match** |
| 37 | `20260524117000` | `fix_deactivation_allow_rejected_resubmit` | `20260524117000_fix_deactivation_allow_rejected_resubmit.sql` | **Match** |
| 38 | `20260524120000` | `deactivation_v2_data_migration` | `20260524120000_deactivation_v2_data_migration.sql` | **Match** |
| 39 | `20260524130000` | `web_vacancy_list_summary_rpcs` | `20260524130000_web_vacancy_list_summary_rpcs.sql` | **Match** |
| 40 | `20260525000000` | `self_service_profile` | `20260525000000_self_service_profile.sql` | **Match** |
| 41 | `20260525120000` | `workforce_push_provider_integration` | `20260525120000_workforce_push_provider_integration.sql` | **Match** |
| 42 | `20260526100000` | `fix_vacancy_hrco_name_live_lookup` | `20260526100000_fix_vacancy_hrco_name_live_lookup.sql` | **Match** |
| 43 | `20260526114430` | `stub_employee_import_batches` | `20260526114430_stub_employee_import_batches.sql` | **Match** |
| 44 | `20260526114431` | `remote_schema` | `20260526114431_remote_schema.sql` | **Match** |
| 45 | `20260527000000` | `unify_role_level_source` | `20260527000000_unify_role_level_source.sql` | **Match** |
| 46 | `20260527080231` | `add_civil_status_import_mapping` | `20260527080231_add_civil_status_import_mapping.sql` | **Match** |
| 47 | `20260528000000` | `rbac_matrix_foundation` | `20260528000000_rbac_matrix_foundation.sql` | **Match** |
| 48 | `20260528000100` | `vacancy_applicant_scope_hardening` | `20260528000100_vacancy_applicant_scope_hardening.sql` | **Match** |
| 49 | `20260529000000` | `permission_drift_detection_foundation` | `20260529000000_permission_drift_detection_foundation.sql` | **Match** |
| 50 | `20260530000000` | `assisted_rbac_drift_scanner_foundation` | `20260530000000_assisted_rbac_drift_scanner_foundation.sql` | **Match** |
| 51 | `20260531000000` | `app_settings_phase3_backend` | `20260531000000_app_settings_phase3_backend.sql` | **Match** |
| 52 | `20260601000000` | `security_center_phase4_backend` | `20260601000000_security_center_phase4_backend.sql` | **Match** |
| 53 | `20260602000000` | `data_archival_recovery_foundation` | `20260602000000_data_archival_recovery_foundation.sql` | **Match** |
| 54 | `20260602000001` | `harden_archive_restore_rpc` | `20260602000001_harden_archive_restore_rpc.sql` | **Match** |
| 55 | `20260602000002` | `fix_vacancy_state_slot_sync_seam2` | `20260602000002_fix_vacancy_state_slot_sync_seam2.sql` | **Match** |
| 56 | `20260602000003` | `fix_applicant_slot_sync_on_insert` | `20260602000003_fix_applicant_slot_sync_on_insert.sql` | **Match** |
| 57 | `20260603000000` | `fix_mobile_number_constraints` | `20260603000000_fix_mobile_number_constraints.sql` | **Match** |
| 58 | `20260603000001` | `security_advisor_phase1_low_risk` | `20260603000001_security_advisor_phase1_low_risk.sql` | **Match** |
| 59 | `20260603000002` | `fix_vcode_import_duplicate_check_and_roving_type` | `20260603000002_fix_vcode_import_duplicate_check_and_roving_type.sql` | **Match** |
| 60 | `20260603010000` | `plantilla_import_dry_run_v1` | `20260603010000_plantilla_import_dry_run_v1.sql` | **Match** |
| 61 | `20260603155645` | `fix_global_search_ambiguous_columns` | `20260603155645_fix_global_search_ambiguous_columns.sql` | **Match** |
| 62 | `20260603155906` | `fix_global_search_result_shape` | `20260603155906_fix_global_search_result_shape.sql` | **Match** |
| 63 | `20260604000000` | `vacancy_edit_lock_backend` | `20260604000000_vacancy_edit_lock_backend.sql` | **Match** |
| 64 | `20260604000001` | `fix_shadow_view_exclude_archived` | `20260604000001_fix_shadow_view_exclude_archived.sql` | **Match** |
| 65 | `20260604000002` | `pipeline_sla_aging_for_pipeline_slots` | `20260604000002_pipeline_sla_aging_for_pipeline_slots.sql` | **Match** |
| 66 | `20260604000003` | `get_global_plantilla_for_payroll_check` | `20260604000003_get_global_plantilla_for_payroll_check.sql` | **Match** |
| 67 | `20260604000004` | `payroll_review_center` | `20260604000004_payroll_review_center.sql` | **Match** |
| 68 | `20260605000000` | `add_font_family_to_user_settings` | `20260605000000_add_font_family_to_user_settings.sql` | **Match** |
| 69 | `20260606000000` | `web_vacancy_detail_rpc` | `20260606000000_web_vacancy_detail_rpc.sql` | **Match** |
| 70 | `20260607000000` | `web_hr_emploc_list_summary_rpcs` | `20260607000000_web_hr_emploc_list_summary_rpcs.sql` | **Match** |
| 71 | `20260607000001` | `web_hr_emploc_detail_rpc` | `20260607000001_web_hr_emploc_detail_rpc.sql` | **Match** |
| 72 | `20260607000002` | `web_plantilla_list_summary_rpcs` | `20260607000002_web_plantilla_list_summary_rpcs.sql` | **Match** |
| 73 | `20260607000003` | `web_plantilla_detail_rpc` | `20260607000003_web_plantilla_detail_rpc.sql` | **Match** |
| 74 | `20260607000004` | `web_hr_emploc_tag_deficiency_rpc` | `20260607000004_web_hr_emploc_tag_deficiency_rpc.sql` | **Match** |
| 75 | `20260608000000` | `fix_vcode_creation_access_ha_encoder` | `20260608000000_fix_vcode_creation_access_ha_encoder.sql` | **Match** |
| 76 | `20260608030000` | `tag_backout_coverage_branch` | `20260608030000_tag_backout_coverage_branch.sql` | **Match** |
| 77 | `20260608040000` | `deletion_request_vcode_nullable` | `20260608040000_deletion_request_vcode_nullable.sql` | **Match** |
| 78 | `20260608060000` | `fix_coverage_onboarding_rpc` | `20260608060000_fix_coverage_onboarding_rpc.sql` | **Match** |
| 79 | `20260608090000` | `sla_flags_add_vacancy_code_snapshot` | `20260608090000_sla_flags_add_vacancy_code_snapshot.sql` | **Match** |
| 80 | `20260608100000` | `fix_orphaned_esa_and_mfr_safe_zero` | `20260608100000_fix_orphaned_esa_and_mfr_safe_zero.sql` | **Match** |
| 81 | `20260609000000` | `web_hr_emploc_review_correction_rpc` | `20260609000000_web_hr_emploc_review_correction_rpc.sql` | **Match** |
| 82 | `20260609000001` | `web_hr_emploc_detail_can_review_correction` | `20260609000001_web_hr_emploc_detail_can_review_correction.sql` | **Match** |
| 83 | `20260610000000` | `fix_web_plantilla_rpc_runtime_columns` | `20260610000000_fix_web_plantilla_rpc_runtime_columns.sql` | **Match** |
| 84 | `20260611000000` | `fix_web_plantilla_uuid_aggregates_active_all` | `20260611000000_fix_web_plantilla_uuid_aggregates_active_all.sql` | **Match** |
| 85 | `20260612000000` | `fix_web_plantilla_rpc_output_safe_view` | `20260612000000_fix_web_plantilla_rpc_output_safe_view.sql` | **Match** |
| 86 | `20260613000000` | `report_group_scoped_rpc_contracts` | `20260613000000_report_group_scoped_rpc_contracts.sql` | **Match** |
| 87 | `20260614000000` | `fix_temp_permission_override_rbac_and_revoke` | `20260614000000_fix_temp_permission_override_rbac_and_revoke.sql` | **Match** |
| 88 | `20260614000001` | `web_vacancy_applicant_freeze_enforcement` | `20260614000001_web_vacancy_applicant_freeze_enforcement.sql` | **Match** |
| 89 | `20260614000002` | `coverage_group_vacancy_footprint_fix` | `20260614000002_coverage_group_vacancy_footprint_fix.sql` | **Match** |
| 90 | `20260614000003` | `coverage_group_demand_ownership` | `20260614000003_coverage_group_demand_ownership.sql` | **Match** |
| 91 | `20260614000004` | `coverage_group_retroactive_repair` | `20260614000004_coverage_group_retroactive_repair.sql` | **Match** |
| 92 | `20260615000000` | `fix_store_import_approval_employment_type` | `20260615000000_fix_store_import_approval_employment_type.sql` | **Match** |
| 93 | `20260615000001` | `close_workforce_assignment` | `20260615000001_close_workforce_assignment.sql` | **Match** |
| 94 | `20260615000002` | `reopen_pool_slot_vacancy_cascade` | `20260615000002_reopen_pool_slot_vacancy_cascade.sql` | **Match** |
| 95 | `20260616000000` | `restore_fn_is_active_vacancy_applicant_status` | `20260616000000_restore_fn_is_active_vacancy_applicant_status.sql` | **Match** |
| 96 | `20260620000000` | `plantilla_baseline_import_v2` | `20260620000000_plantilla_baseline_import_v2.sql` | **Match** |
| 97 | `20260621000000` | `plantilla_import_validation_commit_finalize` | `20260621000000_plantilla_import_validation_commit_finalize.sql` | **Match** |
| 98 | `20260622000000` | `fix_plantilla_import_commit_fk_order` | `20260622000000_fix_plantilla_import_commit_fk_order.sql` | **Match** |
| 99 | `20260624000000` | `fix_plantilla_import_audit_action` | `20260624000000_fix_plantilla_import_audit_action.sql` | **Match** |
| 100 | `20260625000000` | `hydrate_plantilla_from_baseline_import` | `20260625000000_hydrate_plantilla_from_baseline_import.sql` | **Match** |
| 101 | `20262606000066` | `wrap_get_my_scoped_vcodes_initplan` | `—` | **Missing in repo** |
| 102 | `20262606000067` | `restore_security_invoker_vw_slot_derived_vacancy_shadow` | `—` | **Missing in repo** |
| 103 | `20262606000072` | `relax_store_name_multivcode_rule` | `20262606000072_relax_store_name_multivcode_rule.sql` | **Renamed** |
| 104 | `20262606000073` | `fix_plantilla_import_role_check_parity` | `20262606000073_fix_plantilla_import_role_check_parity.sql` | **Renamed** |

---

## 3. Production Migrations Missing in Repo

| Production DB Version | Migration Name | Status / Action |
|---|---|---|
| `20262606000066` | `wrap_get_my_scoped_vcodes_initplan` | Missing in repo; not recreated as per policy. |
| `20262606000067` | `restore_security_invoker_vw_slot_derived_vacancy_shadow` | Missing in repo; not recreated as per policy. |

---

## 4. Renamed Migration Files (`git mv`)

| Previous Repo Filename | Reconciled Filename (Matching Prod) | Target Collision? | SQL Content Changed? |
|---|---|---|---|
| `20262606000066_relax_store_name_multivcode_rule.sql` | `20262606000072_relax_store_name_multivcode_rule.sql` | No (Clean `git mv`) | No (0 bytes changed) |
| `20262606000067_fix_plantilla_import_role_check_parity.sql` | `20262606000073_fix_plantilla_import_role_check_parity.sql` | No (Clean `git mv`) | No (0 bytes changed) |

---

## 5. Extra Migration Files in Repo (376 Files)

These migrations exist in `supabase/migrations/` as part of ongoing feature development, hardening, and local migrations. As per directive, they are listed here without alteration or deletion.

<details>
<summary>Click to expand all 376 repo-only migrations</summary>

| # | Version | Migration Name | Filename |
|---|---|---|---|
| 1 | `20260626000000` | `plantilla_import_rollback_v1` | `20260626000000_plantilla_import_rollback_v1.sql` |
| 2 | `20260627000000` | `plantilla_import_diff_preview` | `20260627000000_plantilla_import_diff_preview.sql` |
| 3 | `20260628000000` | `allocation_based_mfr_v1` | `20260628000000_allocation_based_mfr_v1.sql` |
| 4 | `20260629000000` | `roving_aware_open_hc_v1` | `20260629000000_roving_aware_open_hc_v1.sql` |
| 5 | `20260629010459` | `fix_coverage_request_notification_fk` | `20260629010459_fix_coverage_request_notification_fk.sql` |
| 6 | `20260629010804` | `fix_sla_notify_user_smallint_cast` | `20260629010804_fix_sla_notify_user_smallint_cast.sql` |
| 7 | `20260629010950` | `fix_sla_requester_auth_guard` | `20260629010950_fix_sla_requester_auth_guard.sql` |
| 8 | `20260629010951` | `coverage_add_store_propagation_fix` | `20260629010951_coverage_add_store_propagation_fix.sql` |
| 9 | `20260629010952` | `coverage_reconciliation_diagnostics` | `20260629010952_coverage_reconciliation_diagnostics.sql` |
| 10 | `20260629020000` | `fix_new_store_notification_fk` | `20260629020000_fix_new_store_notification_fk.sql` |
| 11 | `20260629030000` | `fix_vacancy_store_mismatch_coverage` | `20260629030000_fix_vacancy_store_mismatch_coverage.sql` |
| 12 | `20260629040000` | `repair_remaining_orphan_plantilla_slots` | `20260629040000_repair_remaining_orphan_plantilla_slots.sql` |
| 13 | `20260629050000` | `fix_sm_calookohan_coverage_picker_prod` | `20260629050000_fix_sm_calookohan_coverage_picker_prod.sql` |
| 14 | `20260629060000` | `coverage_add_store_promotion` | `20260629060000_coverage_add_store_promotion.sql` |
| 15 | `20260629070000` | `fix_coverage_dissolve_province_id` | `20260629070000_fix_coverage_dissolve_province_id.sql` |
| 16 | `20260629080000` | `fix_coverage_cg_vacancy_slot_guard` | `20260629080000_fix_coverage_cg_vacancy_slot_guard.sql` |
| 17 | `20260630000000` | `roving_vacancy_creation_hc_flags` | `20260630000000_roving_vacancy_creation_hc_flags.sql` |
| 18 | `20260630000001` | `fix_remove_store_vacancy_uuid_cast` | `20260630000001_fix_remove_store_vacancy_uuid_cast.sql` |
| 19 | `20260630000002` | `coverage_request_one_pending_per_group` | `20260630000002_coverage_request_one_pending_per_group.sql` |
| 20 | `20260630091756` | `moses_hq_archive_extension` | `20260630091756_moses_hq_archive_extension.sql` |
| 21 | `20260630092333` | `fix_cg_pending_guard_approval_block` | `20260630092333_fix_cg_pending_guard_approval_block.sql` |
| 22 | `20260630092424` | `fix_coverage_review_artifacts_cte_scope` | `20260630092424_fix_coverage_review_artifacts_cte_scope.sql` |
| 23 | `20260630092439` | `fix_remove_store_filled_to_open_transition` | `20260630092439_fix_remove_store_filled_to_open_transition.sql` |
| 24 | `20260701000000` | `live_allocation_sync_v1` | `20260701000000_live_allocation_sync_v1.sql` |
| 25 | `20260701000001` | `fix_hc_request_notification_fk` | `20260701000001_fix_hc_request_notification_fk.sql` |
| 26 | `20260701000002` | `fix_merge_coverage_group_execution` | `20260701000002_fix_merge_coverage_group_execution.sql` |
| 27 | `20260701000003` | `fix_hc_request_nsr_duplicate_guard` | `20260701000003_fix_hc_request_nsr_duplicate_guard.sql` |
| 28 | `20260701000004` | `reapply_vcode_generation_account_code_fallback` | `20260701000004_reapply_vcode_generation_account_code_fallback.sql` |
| 29 | `20260701000005` | `fix_dissolve_review_artifacts_archived_at_regression` | `20260701000005_fix_dissolve_review_artifacts_archived_at_regression.sql` |
| 30 | `20260701000006` | `fix_esa_sync_roving_group_id` | `20260701000006_fix_esa_sync_roving_group_id.sql` |
| 31 | `20260702000000` | `workforce_allocation_health_report` | `20260702000000_workforce_allocation_health_report.sql` |
| 32 | `20260702000001` | `notify_user_auth_guard` | `20260702000001_notify_user_auth_guard.sql` |
| 33 | `20260702000002` | `fix_merge_coverage_group_vacancy_cleanup` | `20260702000002_fix_merge_coverage_group_vacancy_cleanup.sql` |
| 34 | `20260702000003` | `fix_coverage_group_vacancy_duplication_second_level` | `20260702000003_fix_coverage_group_vacancy_duplication_second_level.sql` |
| 35 | `20260702000004` | `fix_unscoped_insert_rls_policies` | `20260702000004_fix_unscoped_insert_rls_policies.sql` |
| 36 | `20260702000005` | `fix_revoke_public_execute_sla_functions` | `20260702000005_fix_revoke_public_execute_sla_functions.sql` |
| 37 | `20260703000000` | `enrich_plantilla_import_validation_conflicts` | `20260703000000_enrich_plantilla_import_validation_conflicts.sql` |
| 38 | `20260703000001` | `fix_search_path_critical_security_definer_functions` | `20260703000001_fix_search_path_critical_security_definer_functions.sql` |
| 39 | `20260703000002` | `restrict_fn_get_hired_applicants_to_authenticated` | `20260703000002_restrict_fn_get_hired_applicants_to_authenticated.sql` |
| 40 | `20260703000003` | `add_scope_filter_fn_get_hired_applicants` | `20260703000003_add_scope_filter_fn_get_hired_applicants.sql` |
| 41 | `20260703000004` | `fix_return_type_fn_get_archive_batch_history` | `20260703000004_fix_return_type_fn_get_archive_batch_history.sql` |
| 42 | `20260703000005` | `restore_moses_hq_archive_functions` | `20260703000005_restore_moses_hq_archive_functions.sql` |
| 43 | `20260704000000` | `plantilla_import_operational_safeguards` | `20260704000000_plantilla_import_operational_safeguards.sql` |
| 44 | `20260705000000` | `plantilla_import_incident_monitoring` | `20260705000000_plantilla_import_incident_monitoring.sql` |
| 45 | `20260706000000` | `patch_import_optional_employee_fields` | `20260706000000_patch_import_optional_employee_fields.sql` |
| 46 | `20260706000010` | `fix_prod_regression_missing_deleted_at` | `20260706000010_fix_prod_regression_missing_deleted_at.sql` |
| 47 | `20260706000011` | `fix_moses_hq_archival_cascade` | `20260706000011_fix_moses_hq_archival_cascade.sql` |
| 48 | `20260706000012` | `fix_coverage_slots_single_row_and_position_inheritance` | `20260706000012_fix_coverage_slots_single_row_and_position_inheritance.sql` |
| 49 | `20260706000013` | `fix_anchor_position_id_resolution_source` | `20260706000013_fix_anchor_position_id_resolution_source.sql` |
| 50 | `20260706000014` | `remove_dead_position_id_coalesce_carryover` | `20260706000014_remove_dead_position_id_coalesce_carryover.sql` |
| 51 | `20260706053649` | `fix_coverage_hire_store_links_and_contact_propagation` | `20260706053649_fix_coverage_hire_store_links_and_contact_propagation.sql` |
| 52 | `20260706112405` | `reassert_generate_vcode_for_account` | `20260706112405_reassert_generate_vcode_for_account.sql` |
| 53 | `20260706120000` | `v_plantilla_safe_add_emploc_no_and_reconcile_rest_day` | `20260706120000_v_plantilla_safe_add_emploc_no_and_reconcile_rest_day.sql` |
| 54 | `20260706130000` | `fix_prod_vcode_generation_ghost_drift` | `20260706130000_fix_prod_vcode_generation_ghost_drift.sql` |
| 55 | `20260707000000` | `governance_controls_foundation` | `20260707000000_governance_controls_foundation.sql` |
| 56 | `20260707090000` | `fix_history_store_uuid_resolution` | `20260707090000_fix_history_store_uuid_resolution.sql` |
| 57 | `20260707095959` | `add_user_scopes_is_active` | `20260707095959_add_user_scopes_is_active.sql` |
| 58 | `20260707100000` | `hrco_scope_isolation_plantilla` | `20260707100000_hrco_scope_isolation_plantilla.sql` |
| 59 | `20260707100001` | `hrco_email_import_validation` | `20260707100001_hrco_email_import_validation.sql` |
| 60 | `20260707100002` | `get_plantilla_needs_hrco_employees` | `20260707100002_get_plantilla_needs_hrco_employees.sql` |
| 61 | `20260707100003` | `hrco_validation_enforce_active_scope` | `20260707100003_hrco_validation_enforce_active_scope.sql` |
| 62 | `20260707110000` | `fix_needs_hrco_exclude_archived` | `20260707110000_fix_needs_hrco_exclude_archived.sql` |
| 63 | `20260707110001` | `hrco_auto_assign_sole_hrco` | `20260707110001_hrco_auto_assign_sole_hrco.sql` |
| 64 | `20260707120000` | `hrco_global_visibility` | `20260707120000_hrco_global_visibility.sql` |
| 65 | `20260707130000` | `plantilla_import_require_date_hired` | `20260707130000_plantilla_import_require_date_hired.sql` |
| 66 | `20260707140000` | `fix_plantilla_import_middle_name_loss` | `20260707140000_fix_plantilla_import_middle_name_loss.sql` |
| 67 | `20260708000000` | `wire_governance_control_enforcement` | `20260708000000_wire_governance_control_enforcement.sql` |
| 68 | `20260708012728` | `add_vacancy_requirements_normalization` | `20260708012728_add_vacancy_requirements_normalization.sql` |
| 69 | `20260708140000` | `assignment_hc_sync` | `20260708140000_assignment_hc_sync.sql` |
| 70 | `20260708150000` | `vacancy_requirement_hardening_phase1` | `20260708150000_vacancy_requirement_hardening_phase1.sql` |
| 71 | `20260708160000` | `hybrid_requirement_stabilization` | `20260708160000_hybrid_requirement_stabilization.sql` |
| 72 | `20260708170000` | `applicant_vacancy_requirement_linkage` | `20260708170000_applicant_vacancy_requirement_linkage.sql` |
| 73 | `20260708180000` | `sync_hc_request_vacancy_requirements` | `20260708180000_sync_hc_request_vacancy_requirements.sql` |
| 74 | `20260708190000` | `backfill_vcag2_0025_vacancy_requirements` | `20260708190000_backfill_vcag2_0025_vacancy_requirements.sql` |
| 75 | `20260708200000` | `fix_confirm_applicant_onboard_is_roving` | `20260708200000_fix_confirm_applicant_onboard_is_roving.sql` |
| 76 | `20260708210000` | `fix_move_to_plantilla_requirement_id` | `20260708210000_fix_move_to_plantilla_requirement_id.sql` |
| 77 | `20260708220000` | `fix_vacancy_insert_missing_position` | `20260708220000_fix_vacancy_insert_missing_position.sql` |
| 78 | `20260709000000` | `global_search_index` | `20260709000000_global_search_index.sql` |
| 79 | `20260709013328` | `fix_plantilla_separation_is_roving_regression` | `20260709013328_fix_plantilla_separation_is_roving_regression.sql` |
| 80 | `20260709023900` | `fix_plantilla_separation_store_links_schema` | `20260709023900_fix_plantilla_separation_store_links_schema.sql` |
| 81 | `20260709030000` | `fix_resignation_trigger_coverage_slot_vacancy_fallback_store_name` | `20260709030000_fix_resignation_trigger_coverage_slot_vacancy_fallback_store_name.sql` |
| 82 | `20260709060355` | `fix_plantilla_import_position_id_resolution` | `20260709060355_fix_plantilla_import_position_id_resolution.sql` |
| 83 | `20260709060413` | `fix_sync_vacancy_slot_open_pipeline_occupied_guard` | `20260709060413_fix_sync_vacancy_slot_open_pipeline_occupied_guard.sql` |
| 84 | `20260709070000` | `scope_position_id_guard_legacy_null_bypass` | `20260709070000_scope_position_id_guard_legacy_null_bypass.sql` |
| 85 | `20260709071000` | `scope_reopen_vacancy_position_id_guard_legacy_null_bypass` | `20260709071000_scope_reopen_vacancy_position_id_guard_legacy_null_bypass.sql` |
| 86 | `20260709071500` | `fix_approve_plantilla_import_batch_status_constraint_violation` | `20260709071500_fix_approve_plantilla_import_batch_status_constraint_violation.sql` |
| 87 | `20260709073000` | `add_log_import_commit_failure_rpc` | `20260709073000_add_log_import_commit_failure_rpc.sql` |
| 88 | `20260709080000` | `fix_backfill_plantilla_position_ids_assertion` | `20260709080000_fix_backfill_plantilla_position_ids_assertion.sql` |
| 89 | `20260709090000` | `plantilla_hrco_transfer_and_visibility` | `20260709090000_plantilla_hrco_transfer_and_visibility.sql` |
| 90 | `20260709091500` | `grant_select_v_plantilla_safe` | `20260709091500_grant_select_v_plantilla_safe.sql` |
| 91 | `20260710000000` | `governance_audit_logs_viewer` | `20260710000000_governance_audit_logs_viewer.sql` |
| 92 | `20260711000000` | `safespace_freeze_modes` | `20260711000000_safespace_freeze_modes.sql` |
| 93 | `20260712000000` | `enforce_recruitment_freeze` | `20260712000000_enforce_recruitment_freeze.sql` |
| 94 | `20260713000000` | `enforce_audit_freeze` | `20260713000000_enforce_audit_freeze.sql` |
| 95 | `20260714000000` | `safespace_risk_controls` | `20260714000000_safespace_risk_controls.sql` |
| 96 | `20260730000000` | `import_vacancy_migration_v1` | `20260730000000_import_vacancy_migration_v1.sql` |
| 97 | `20260730000001` | `fix_import_vacancy_audit_action_enum` | `20260730000001_fix_import_vacancy_audit_action_enum.sql` |
| 98 | `20260730000002` | `fix_import_vacancy_source_constraint` | `20260730000002_fix_import_vacancy_source_constraint.sql` |
| 99 | `20260730000003` | `add_import_vacancy_rollback` | `20260730000003_add_import_vacancy_rollback.sql` |
| 100 | `20260730000004` | `import_vacancy_reason_dropdowns_and_notifications` | `20260730000004_import_vacancy_reason_dropdowns_and_notifications.sql` |
| 101 | `20260730000006` | `fix_import_vacancy_reimport_restore` | `20260730000006_fix_import_vacancy_reimport_restore.sql` |
| 102 | `20260730000007` | `remove_fk_plantilla_vcode_active_uniqueness` | `20260730000007_remove_fk_plantilla_vcode_active_uniqueness.sql` |
| 103 | `20260730000008` | `fix_plantilla_import_audit_action_refix` | `20260730000008_fix_plantilla_import_audit_action_refix.sql` |
| 104 | `20260730000009` | `plantilla_import_rollback_request_approve_reasons_notifications` | `20260730000009_plantilla_import_rollback_request_approve_reasons_notifications.sql` |
| 105 | `20260731000000` | `applicant_cross_account_active_guard` | `20260731000000_applicant_cross_account_active_guard.sql` |
| 106 | `20260731000001` | `import_vacancy_cross_account_applicant_precheck` | `20260731000001_import_vacancy_cross_account_applicant_precheck.sql` |
| 107 | `20260731000002` | `fix_cencom_vacancy_count_exclude_deleted` | `20260731000002_fix_cencom_vacancy_count_exclude_deleted.sql` |
| 108 | `20260731100000` | `backfill_plantilla_position_ids` | `20260731100000_backfill_plantilla_position_ids.sql` |
| 109 | `20260801000000` | `access_control_center_v1` | `20260801000000_access_control_center_v1.sql` |
| 110 | `20260802000000` | `user_management_account_scope` | `20260802000000_user_management_account_scope.sql` |
| 111 | `20260803000000` | `fix_plantilla_import_profile_field_hydration` | `20260803000000_fix_plantilla_import_profile_field_hydration.sql` |
| 112 | `20260804000000` | `plantilla_slot_foundation_v1` | `20260804000000_plantilla_slot_foundation_v1.sql` |
| 113 | `20260805000000` | `fn_create_slots_from_hc_request` | `20260805000000_fn_create_slots_from_hc_request.sql` |
| 114 | `20260806000000` | `wire_slot_creation_into_hc_completion` | `20260806000000_wire_slot_creation_into_hc_completion.sql` |
| 115 | `20260807000000` | `plantilla_slots_legacy_vcode_link` | `20260807000000_plantilla_slots_legacy_vcode_link.sql` |
| 116 | `20260808000000` | `drop_obsolete_2arg_slot_rpc` | `20260808000000_drop_obsolete_2arg_slot_rpc.sql` |
| 117 | `20260809000000` | `vw_slot_derived_vacancy_shadow` | `20260809000000_vw_slot_derived_vacancy_shadow.sql` |
| 118 | `20260810000000` | `backfill_historical_vacancy_slots` | `20260810000000_backfill_historical_vacancy_slots.sql` |
| 119 | `20260810000001` | `fix_slot_derived_vacancy_closure_tab` | `20260810000001_fix_slot_derived_vacancy_closure_tab.sql` |
| 120 | `20260811000000` | `fix_backfill_parity_d1_d2` | `20260811000000_fix_backfill_parity_d1_d2.sql` |
| 121 | `20260811000001` | `fix_slot_derived_vacancy_id_mapping` | `20260811000001_fix_slot_derived_vacancy_id_mapping.sql` |
| 122 | `20260812000000` | `fn_set_slot_status` | `20260812000000_fn_set_slot_status.sql` |
| 123 | `20260813000001` | `wire_open_pipeline_slot_transitions` | `20260813000001_wire_open_pipeline_slot_transitions.sql` |
| 124 | `20260813000002` | `wire_pipeline_hr_processing_slot_transition` | `20260813000002_wire_pipeline_hr_processing_slot_transition.sql` |
| 125 | `20260813000003` | `wire_hr_processing_occupied_slot_transition` | `20260813000003_wire_hr_processing_occupied_slot_transition.sql` |
| 126 | `20260813000004` | `wire_occupied_open_slot_transition` | `20260813000004_wire_occupied_open_slot_transition.sql` |
| 127 | `20260813000005` | `wire_hr_processing_open_slot_transition` | `20260813000005_wire_hr_processing_open_slot_transition.sql` |
| 128 | `20260814000000` | `restore_shadow_view_parity_fields` | `20260814000000_restore_shadow_view_parity_fields.sql` |
| 129 | `20260814000001` | `restore_store_and_ownership_parity_shadow` | `20260814000001_restore_store_and_ownership_parity_shadow.sql` |
| 130 | `20260816000000` | `vcode_slot_phase_a_schema_bridge` | `20260816000000_vcode_slot_phase_a_schema_bridge.sql` |
| 131 | `20260817000000` | `vcode_slot_phase_b_applicant_binding` | `20260817000000_vcode_slot_phase_b_applicant_binding.sql` |
| 132 | `20260817000001` | `fix_applicant_slot_sync_on_insert` | `20260817000001_fix_applicant_slot_sync_on_insert.sql` |
| 133 | `20260818000000` | `fix_create_applicant_rpc_missing_columns` | `20260818000000_fix_create_applicant_rpc_missing_columns.sql` |
| 134 | `20260819000000` | `vcode_slot_phase_c_hr_emploc_binding` | `20260819000000_vcode_slot_phase_c_hr_emploc_binding.sql` |
| 135 | `20260820000000` | `vcode_slot_phase_d_shadow_aggregation` | `20260820000000_vcode_slot_phase_d_shadow_aggregation.sql` |
| 136 | `20260821000000` | `vcode_slot_phase_f_n_slot_creation` | `20260821000000_vcode_slot_phase_f_n_slot_creation.sql` |
| 137 | `20260822000000` | `coverage_group_ra0_preflight` | `20260822000000_coverage_group_ra0_preflight.sql` |
| 138 | `20260822000001` | `coverage_group_ra1_coverage_groups` | `20260822000001_coverage_group_ra1_coverage_groups.sql` |
| 139 | `20260822000002` | `coverage_group_ra2_cgcode_minter` | `20260822000002_coverage_group_ra2_cgcode_minter.sql` |
| 140 | `20260822000003` | `coverage_group_ra3_coverage_group_stores` | `20260822000003_coverage_group_ra3_coverage_group_stores.sql` |
| 141 | `20260822000004` | `coverage_group_ra4_coverage_slots` | `20260822000004_coverage_group_ra4_coverage_slots.sql` |
| 142 | `20260822000005` | `coverage_group_ra5_eager_slot_emit` | `20260822000005_coverage_group_ra5_eager_slot_emit.sql` |
| 143 | `20260822000006` | `coverage_group_ra6_binding_columns` | `20260822000006_coverage_group_ra6_binding_columns.sql` |
| 144 | `20260822000007` | `coverage_group_ra7_store_link_repoint` | `20260822000007_coverage_group_ra7_store_link_repoint.sql` |
| 145 | `20260822000008` | `coverage_group_ra8_validation_harness` | `20260822000008_coverage_group_ra8_validation_harness.sql` |
| 146 | `20260822000009` | `coverage_group_ra9_teardown_and_gate` | `20260822000009_coverage_group_ra9_teardown_and_gate.sql` |
| 147 | `20260823000000` | `coverage_group_phase_rb_applicant_binding` | `20260823000000_coverage_group_phase_rb_applicant_binding.sql` |
| 148 | `20260824000000` | `coverage_group_phase_rc_hr_emploc_binding` | `20260824000000_coverage_group_phase_rc_hr_emploc_binding.sql` |
| 149 | `20260825000000` | `coverage_group_phase_rd_plantilla_active_transition` | `20260825000000_coverage_group_phase_rd_plantilla_active_transition.sql` |
| 150 | `20260826000000` | `coverage_group_phase_re_shadow_read_model` | `20260826000000_coverage_group_phase_re_shadow_read_model.sql` |
| 151 | `20260827000000` | `applicant_pipeline_status_seed_seam1` | `20260827000000_applicant_pipeline_status_seed_seam1.sql` |
| 152 | `20260828000000` | `applicant_pipeline_seam2_rpcs` | `20260828000000_applicant_pipeline_seam2_rpcs.sql` |
| 153 | `20260828000001` | `fix_vacancy_state_slot_sync_seam2` | `20260828000001_fix_vacancy_state_slot_sync_seam2.sql` |
| 154 | `20260829000000` | `applicant_pipeline_seam2_addendum` | `20260829000000_applicant_pipeline_seam2_addendum.sql` |
| 155 | `20260830000000` | `vacancy_edit_lock_override` | `20260830000000_vacancy_edit_lock_override.sql` |
| 156 | `20260830000001` | `fix_vacancy_edit_lock_status_can_edit` | `20260830000001_fix_vacancy_edit_lock_status_can_edit.sql` |
| 157 | `20260830000002` | `fix_vacancy_override_can_edit` | `20260830000002_fix_vacancy_override_can_edit.sql` |
| 158 | `20260830000003` | `fix_enforcement_fn_override_bypass` | `20260830000003_fix_enforcement_fn_override_bypass.sql` |
| 159 | `20260831000000` | `fix_vcode_generation_account_code_fallback` | `20260831000000_fix_vcode_generation_account_code_fallback.sql` |
| 160 | `20260901000000` | `cencom_deployment_summary_and_vacant_fix` | `20260901000000_cencom_deployment_summary_and_vacant_fix.sql` |
| 161 | `20260902000000` | `new_store_request_v1` | `20260902000000_new_store_request_v1.sql` |
| 162 | `20260903000000` | `team_directory_uat_fix_pack` | `20260903000000_team_directory_uat_fix_pack.sql` |
| 163 | `20260904000000` | `hc_request_archive_super_admin_policy` | `20260904000000_hc_request_archive_super_admin_policy.sql` |
| 164 | `20260905000000` | `fix_pipeline_approval_source_agnostic` | `20260905000000_fix_pipeline_approval_source_agnostic.sql` |
| 165 | `20260905000001` | `fix_global_search_ambiguous_columns` | `20260905000001_fix_global_search_ambiguous_columns.sql` |
| 166 | `20260905000002` | `fix_global_search_result_shape` | `20260905000002_fix_global_search_result_shape.sql` |
| 167 | `20260905000003` | `fix_store_tab_area_city_province` | `20260905000003_fix_store_tab_area_city_province.sql` |
| 168 | `20260906000000` | `qa_archive_operational_data_reset` | `20260906000000_qa_archive_operational_data_reset.sql` |
| 169 | `20260907000000` | `enterprise_data_archival_center` | `20260907000000_enterprise_data_archival_center.sql` |
| 170 | `20260908000000` | `add_mika_import_audit_counts` | `20260908000000_add_mika_import_audit_counts.sql` |
| 171 | `20260908000001` | `slot_based_vacant_hc_v1` | `20260908000001_slot_based_vacant_hc_v1.sql` |
| 172 | `20260909000000` | `import_rollback_governance_72_business_hours` | `20260909000000_import_rollback_governance_72_business_hours.sql` |
| 173 | `20260909000001` | `fix_import_batch_finalized_status_constraints` | `20260909000001_fix_import_batch_finalized_status_constraints.sql` |
| 174 | `20260910000000` | `esa_cascade_qa_archive_reset` | `20260910000000_esa_cascade_qa_archive_reset.sql` |
| 175 | `20260911000000` | `fix_plantilla_import_source_column_and_finalized_constraint` | `20260911000000_fix_plantilla_import_source_column_and_finalized_constraint.sql` |
| 176 | `20260911000001` | `fix_esa_branch_created_at` | `20260911000001_fix_esa_branch_created_at.sql` |
| 177 | `20260911000002` | `fix_rollback_plantilla_import_batch_stores_type_column` | `20260911000002_fix_rollback_plantilla_import_batch_stores_type_column.sql` |
| 178 | `20260912000000` | `backfill_gap_vacancy_slots_and_trigger` | `20260912000000_backfill_gap_vacancy_slots_and_trigger.sql` |
| 179 | `20260913000000` | `fix_import_inactive_reconcile_and_slot_occupancy` | `20260913000000_fix_import_inactive_reconcile_and_slot_occupancy.sql` |
| 180 | `20260913000001` | `fix_emploc_2023_09515_duplicate_inactive_cleanup` | `20260913000001_fix_emploc_2023_09515_duplicate_inactive_cleanup.sql` |
| 181 | `20260913000002` | `fix_all_duplicate_inactive_cleanup` | `20260913000002_fix_all_duplicate_inactive_cleanup.sql` |
| 182 | `20260913000003` | `fix_emploc_2023_10978_duplicate_inactive_cleanup` | `20260913000003_fix_emploc_2023_10978_duplicate_inactive_cleanup.sql` |
| 183 | `20260913000004` | `fix_plantilla_update_separation_slot_sync` | `20260913000004_fix_plantilla_update_separation_slot_sync.sql` |
| 184 | `20260914000000` | `fix_roving_employee_vacancy_reopen` | `20260914000000_fix_roving_employee_vacancy_reopen.sql` |
| 185 | `20260915000000` | `fix_slot_history_performer_uuid` | `20260915000000_fix_slot_history_performer_uuid.sql` |
| 186 | `20260916000000` | `fix_fractional_hc_vacancy_and_inactive_esa_cleanup` | `20260916000000_fix_fractional_hc_vacancy_and_inactive_esa_cleanup.sql` |
| 187 | `20260917000000` | `fix_slot_derived_vacancy_shadow_required_headcount` | `20260917000000_fix_slot_derived_vacancy_shadow_required_headcount.sql` |
| 188 | `20260920000000` | `coverage_group_rpcs` | `20260920000000_coverage_group_rpcs.sql` |
| 189 | `20260921000000` | `coverage_group_account_active_guard` | `20260921000000_coverage_group_account_active_guard.sql` |
| 190 | `20260922000000` | `coverage_group_active_store_guard` | `20260922000000_coverage_group_active_store_guard.sql` |
| 191 | `20260923000000` | `coverage_group_plantilla_footprint_guard` | `20260923000000_coverage_group_plantilla_footprint_guard.sql` |
| 192 | `20260924000000` | `coverage_group_overlap_guard` | `20260924000000_coverage_group_overlap_guard.sql` |
| 193 | `20260925000000` | `coverage_group_account_store_footprint_fix` | `20260925000000_coverage_group_account_store_footprint_fix.sql` |
| 194 | `20260926000000` | `add_applicant_to_coverage_group` | `20260926000000_add_applicant_to_coverage_group.sql` |
| 195 | `20260927000000` | `fix_add_applicant_to_coverage_group_rbac` | `20260927000000_fix_add_applicant_to_coverage_group_rbac.sql` |
| 196 | `20260928000000` | `fix2_add_applicant_to_coverage_group` | `20260928000000_fix2_add_applicant_to_coverage_group.sql` |
| 197 | `20260929000000` | `fix3_add_applicant_to_coverage_group_scope` | `20260929000000_fix3_add_applicant_to_coverage_group_scope.sql` |
| 198 | `20261001000000` | `expand_active_applicant_statuses` | `20261001000000_expand_active_applicant_statuses.sql` |
| 199 | `20261002000000` | `coverage_group_onboarding_rpc` | `20261002000000_coverage_group_onboarding_rpc.sql` |
| 200 | `20261003000000` | `add_coverage_hr_emploc_assignment_type` | `20261003000000_add_coverage_hr_emploc_assignment_type.sql` |
| 201 | `20261003000001` | `fix_coverage_group_emploc_assignment_type` | `20261003000001_fix_coverage_group_emploc_assignment_type.sql` |
| 202 | `20261004000000` | `coverage_slot_id_to_store_links` | `20261004000000_coverage_slot_id_to_store_links.sql` |
| 203 | `20261005000000` | `fix_coverage_group_detail_store_location` | `20261005000000_fix_coverage_group_detail_store_location.sql` |
| 204 | `20261006000000` | `enforce_archived_vcode_conflict_blocking` | `20261006000000_enforce_archived_vcode_conflict_blocking.sql` |
| 205 | `20261007000000` | `correct_plantilla_import_diff_preview_metrics` | `20261007000000_correct_plantilla_import_diff_preview_metrics.sql` |
| 206 | `20261007000001` | `on_leave_floating_status` | `20261007000001_on_leave_floating_status.sql` |
| 207 | `20261008000000` | `fix_vacancy_archive_reset_hired_closure` | `20261008000000_fix_vacancy_archive_reset_hired_closure.sql` |
| 208 | `20261009000000` | `align_plantilla_import_review_approve_validation` | `20261009000000_align_plantilla_import_review_approve_validation.sql` |
| 209 | `20261010000000` | `fix_orphaned_esa_mfr_safe_zero_v2` | `20261010000000_fix_orphaned_esa_mfr_safe_zero_v2.sql` |
| 210 | `20261011000000` | `fix_duplicate_slot_creation_from_hc_request` | `20261011000000_fix_duplicate_slot_creation_from_hc_request.sql` |
| 211 | `20261012000000` | `fix_multi_slot_vacancy_premature_fill` | `20261012000000_fix_multi_slot_vacancy_premature_fill.sql` |
| 212 | `20261013000000` | `block_inactive_plantilla_on_import` | `20261013000000_block_inactive_plantilla_on_import.sql` |
| 213 | `20261013000000` | `fix_vacancy_tab_counts_and_canonical_archive_filter` | `20261013000000_fix_vacancy_tab_counts_and_canonical_archive_filter.sql` |
| 214 | `20261014000000` | `plantilla_applicant_additional_store` | `20261014000000_plantilla_applicant_additional_store.sql` |
| 215 | `20261014193500` | `fix_vacancy_closure_lifecycle_and_tab_filtering` | `20261014193500_fix_vacancy_closure_lifecycle_and_tab_filtering.sql` |
| 216 | `20261015000000` | `fix_plantilla_import_rollback_modified_guard` | `20261015000000_fix_plantilla_import_rollback_modified_guard.sql` |
| 217 | `20261016000000` | `fix_plantilla_additional_store_rbac_guard` | `20261016000000_fix_plantilla_additional_store_rbac_guard.sql` |
| 218 | `20261017000000` | `fix_plantilla_import_rollback_reupload_commit` | `20261017000000_fix_plantilla_import_rollback_reupload_commit.sql` |
| 219 | `20261018000000` | `fix_vacancy_import_applicant_contact_normalization` | `20261018000000_fix_vacancy_import_applicant_contact_normalization.sql` |
| 220 | `20261019000000` | `fix_additional_store_multislot_and_applicant_contact` | `20261019000000_fix_additional_store_multislot_and_applicant_contact.sql` |
| 221 | `20261020000000` | `fix_plantilla_additional_store_audit_actor` | `20261020000000_fix_plantilla_additional_store_audit_actor.sql` |
| 222 | `20261021000000` | `coverage_request_foundation` | `20261021000000_coverage_request_foundation.sql` |
| 223 | `20261022000000` | `coverage_request_rpc_contracts` | `20261022000000_coverage_request_rpc_contracts.sql` |
| 224 | `20261023000000` | `coverage_request_approval_engine` | `20261023000000_coverage_request_approval_engine.sql` |
| 225 | `20261024000000` | `hc_request_workforce_type_coverage_group` | `20261024000000_hc_request_workforce_type_coverage_group.sql` |
| 226 | `20261025000000` | `coverage_architecture_phase5_cleanup` | `20261025000000_coverage_architecture_phase5_cleanup.sql` |
| 227 | `20261026000000` | `coverage_request_rbac_hardening` | `20261026000000_coverage_request_rbac_hardening.sql` |
| 228 | `20261027000000` | `coverage_group_global_archive_invisibility` | `20261027000000_coverage_group_global_archive_invisibility.sql` |
| 229 | `20261027000001` | `fix_adr001_roving_pipeline_reporting` | `20261027000001_fix_adr001_roving_pipeline_reporting.sql` |
| 230 | `20261028000000` | `fix_archive_all_data_leakage` | `20261028000000_fix_archive_all_data_leakage.sql` |
| 231 | `20261029000000` | `fix_archive_all_esa_leak` | `20261029000000_fix_archive_all_esa_leak.sql` |
| 232 | `20261030000000` | `permission_matrix_editable_phase` | `20261030000000_permission_matrix_editable_phase.sql` |
| 233 | `20261031000000` | `applicant_movement_request_foundation` | `20261031000000_applicant_movement_request_foundation.sql` |
| 234 | `20261031000001` | `amr_active_target_vacancy_filter` | `20261031000001_amr_active_target_vacancy_filter.sql` |
| 235 | `20261101000000` | `add_hired_date_to_v_hr_emploc_sla_flags` | `20261101000000_add_hired_date_to_v_hr_emploc_sla_flags.sql` |
| 236 | `20261102000000` | `fix_vacancy_import_slot_creation` | `20261102000000_fix_vacancy_import_slot_creation.sql` |
| 237 | `20261103000000` | `coverage_request_execution_engine` | `20261103000000_coverage_request_execution_engine.sql` |
| 238 | `20261104000000` | `fix_plantilla_transfer_grant` | `20261104000000_fix_plantilla_transfer_grant.sql` |
| 239 | `20261105000000` | `fix_plantilla_transfer_slot_vacancy_sync` | `20261105000000_fix_plantilla_transfer_slot_vacancy_sync.sql` |
| 240 | `20261106000000` | `deny_ha_applicant_status_update` | `20261106000000_deny_ha_applicant_status_update.sql` |
| 241 | `20261107000000` | `correct_applicant_rbac_matrix` | `20261107000000_correct_applicant_rbac_matrix.sql` |
| 242 | `20261108000000` | `fn_resolve_user_names` | `20261108000000_fn_resolve_user_names.sql` |
| 243 | `20261108010000` | `fix_multi_slot_pipeline_sync` | `20261108010000_fix_multi_slot_pipeline_sync.sql` |
| 244 | `20261109000000` | `add_rest_day_to_plantilla_views` | `20261109000000_add_rest_day_to_plantilla_views.sql` |
| 245 | `20261109010000` | `amr_scope_and_rejection_hardening` | `20261109010000_amr_scope_and_rejection_hardening.sql` |
| 246 | `20261109020000` | `fix_null_slot_vcode_duplicate_guard` | `20261109020000_fix_null_slot_vcode_duplicate_guard.sql` |
| 247 | `20261110000000` | `fix_stale_hr_emploc_after_plantilla` | `20261110000000_fix_stale_hr_emploc_after_plantilla.sql` |
| 248 | `20261111000000` | `add_name_fields_to_v_hr_emploc_sla_flags` | `20261111000000_add_name_fields_to_v_hr_emploc_sla_flags.sql` |
| 249 | `20261112000000` | `fix_sync_slot_to_hr_processing_legacy_path` | `20261112000000_fix_sync_slot_to_hr_processing_legacy_path.sql` |
| 250 | `20261113000000` | `security_definer_search_path_phase2a` | `20261113000000_security_definer_search_path_phase2a.sql` |
| 251 | `20261114000000` | `security_definer_search_path_phase2b_corrective` | `20261114000000_security_definer_search_path_phase2b_corrective.sql` |
| 252 | `20261115000000` | `security_invoker_phase3a_safe_reporting_views` | `20261115000000_security_invoker_phase3a_safe_reporting_views.sql` |
| 253 | `20261116000000` | `security_invoker_phase3a_corrective` | `20261116000000_security_invoker_phase3a_corrective.sql` |
| 254 | `20261117000000` | `security_invoker_batch4_v_plantilla_safe` | `20261117000000_security_invoker_batch4_v_plantilla_safe.sql` |
| 255 | `20261118000000` | `security_invoker_batch5b_approval_queue_amr_list` | `20261118000000_security_invoker_batch5b_approval_queue_amr_list.sql` |
| 256 | `20261119000000` | `vacancies_read_hired_scoped_batch5a_prereq` | `20261119000000_vacancies_read_hired_scoped_batch5a_prereq.sql` |
| 257 | `20261120000000` | `security_invoker_batch5a_vacancy_views` | `20261120000000_security_invoker_batch5a_vacancy_views.sql` |
| 258 | `20261121000000` | `soft_delete_terminal_hr_emploc_rows` | `20261121000000_soft_delete_terminal_hr_emploc_rows.sql` |
| 259 | `20261200000000` | `fix_i_have_full_access_role_level` | `20261200000000_fix_i_have_full_access_role_level.sql` |
| 260 | `20261201000000` | `tighten_permission_matrix_super_admin_only` | `20261201000000_tighten_permission_matrix_super_admin_only.sql` |
| 261 | `20261202000000` | `fix_web_plantilla_mfr_hr_pipeline_denominator` | `20261202000000_fix_web_plantilla_mfr_hr_pipeline_denominator.sql` |
| 262 | `20261203000000` | `attrition_report_filtering_and_detail_drilldown` | `20261203000000_attrition_report_filtering_and_detail_drilldown.sql` |
| 263 | `20261204000000` | `fix_attrition_detail_date_mapping_and_dnf_empty_state` | `20261204000000_fix_attrition_detail_date_mapping_and_dnf_empty_state.sql` |
| 264 | `20261205000000` | `split_backout_terminated_reports` | `20261205000000_split_backout_terminated_reports.sql` |
| 265 | `20261206000000` | `data_integrity_report` | `20261206000000_data_integrity_report.sql` |
| 266 | `20261207000000` | `team_performance_report` | `20261207000000_team_performance_report.sql` |
| 267 | `20261208000000` | `fix_team_performance_report_rpc` | `20261208000000_fix_team_performance_report_rpc.sql` |
| 268 | `20261209000000` | `fix_team_performance_rpc_role_level` | `20261209000000_fix_team_performance_rpc_role_level.sql` |
| 269 | `20261210000000` | `fix_cencom_required_hc_include_hr_processing` | `20261210000000_fix_cencom_required_hc_include_hr_processing.sql` |
| 270 | `20261210000001` | `fix_slot_hr_processing_drop_vacancy_join` | `20261210000001_fix_slot_hr_processing_drop_vacancy_join.sql` |
| 271 | `20261210000002` | `fix_pipeline_count_revert_to_hr_emploc_drop_archive_filter` | `20261210000002_fix_pipeline_count_revert_to_hr_emploc_drop_archive_filter.sql` |
| 272 | `20261215000000` | `smoke_test_vacancy_open_count_coverage_group` | `20261215000000_smoke_test_vacancy_open_count_coverage_group.sql` |
| 273 | `20261215000001` | `fix_create_pool_vacancy_created_by_uuid` | `20261215000001_fix_create_pool_vacancy_created_by_uuid.sql` |
| 274 | `20261215000002` | `add_pool_to_vacancies_source_check` | `20261215000002_add_pool_to_vacancies_source_check.sql` |
| 275 | `20261215000003` | `drop_old_request_reliever_coverage_overload` | `20261215000003_drop_old_request_reliever_coverage_overload.sql` |
| 276 | `20261215000004` | `fix_approve_reliever_coverage_request` | `20261215000004_fix_approve_reliever_coverage_request.sql` |
| 277 | `20261215000005` | `moses_hq_workforce_request_approval` | `20261215000005_moses_hq_workforce_request_approval.sql` |
| 278 | `20261215000006` | `fix_workforce_pool_encoder_visibility` | `20261215000006_fix_workforce_pool_encoder_visibility.sql` |
| 279 | `20261215000007` | `workforce_pool_positions_and_request_type` | `20261215000007_workforce_pool_positions_and_request_type.sql` |
| 280 | `20261215000008` | `bundler_pool_and_ops_global_visibility` | `20261215000008_bundler_pool_and_ops_global_visibility.sql` |
| 281 | `20261215000009` | `one_vcode_per_pool_request` | `20261215000009_one_vcode_per_pool_request.sql` |
| 282 | `20261215000010` | `drop_workforce_pool_slots_vcode_unique` | `20261215000010_drop_workforce_pool_slots_vcode_unique.sql` |
| 283 | `20261215000011` | `fix_plantilla_import_large_batch_support` | `20261215000011_fix_plantilla_import_large_batch_support.sql` |
| 284 | `20261215000012` | `get_plantilla_account_status_counts` | `20261215000012_get_plantilla_account_status_counts.sql` |
| 285 | `20261215000013` | `fix_pool_request_om_scope` | `20261215000013_fix_pool_request_om_scope.sql` |
| 286 | `20261215000014` | `pool_request_operational_scope` | `20261215000014_pool_request_operational_scope.sql` |
| 287 | `20261215000015` | `pool_request_province_city` | `20261215000015_pool_request_province_city.sql` |
| 288 | `20261216000000` | `fix_hc_request_duplicate_vcode_per_store` | `20261216000000_fix_hc_request_duplicate_vcode_per_store.sql` |
| 289 | `20261217000000` | `smoke_test_hc_request_reuse_flow` | `20261217000000_smoke_test_hc_request_reuse_flow.sql` |
| 290 | `20261217000001` | `add_middle_name_to_v_workforce_pool_employees` | `20261217000001_add_middle_name_to_v_workforce_pool_employees.sql` |
| 291 | `20261218000001` | `set_plantilla_active_rpc` | `20261218000001_set_plantilla_active_rpc.sql` |
| 292 | `20261218000002` | `add_covered_plantilla_id_to_workforce_assignments` | `20261218000002_add_covered_plantilla_id_to_workforce_assignments.sql` |
| 293 | `20261219000000` | `floating_employees_report` | `20261219000000_floating_employees_report.sql` |
| 294 | `20261219000001` | `allow_floating_separation_status` | `20261219000001_allow_floating_separation_status.sql` |
| 295 | `20261219000002` | `add_attrition_reason_to_detail_rpc` | `20261219000002_add_attrition_reason_to_detail_rpc.sql` |
| 296 | `20261219000003` | `fix_attrition_null_date_predicates` | `20261219000003_fix_attrition_null_date_predicates.sql` |
| 297 | `20261219000004` | `drop_reject_amr_overload` | `20261219000004_drop_reject_amr_overload.sql` |
| 298 | `20261219000005` | `fix_amr_audit_logs_fk` | `20261219000005_fix_amr_audit_logs_fk.sql` |
| 299 | `20261220000000` | `request_notification_wiring` | `20261220000000_request_notification_wiring.sql` |
| 300 | `20261221000000` | `fix_reliever_commando_visibility_ops` | `20261221000000_fix_reliever_commando_visibility_ops.sql` |
| 301 | `20261222000000` | `force_vacancy_card_rc_indicators` | `20261222000000_force_vacancy_card_rc_indicators.sql` |
| 302 | `20261223000000` | `fix_vacancy_deployment_indicators_status_gate` | `20261223000000_fix_vacancy_deployment_indicators_status_gate.sql` |
| 303 | `20261224000000` | `auto_close_coverage_on_slot_occupied` | `20261224000000_auto_close_coverage_on_slot_occupied.sql` |
| 304 | `20261225000000` | `fix_applicants_rls_rel_workforce_insert` | `20261225000000_fix_applicants_rls_rel_workforce_insert.sql` |
| 305 | `20261226000000` | `hc_reduction_workflow` | `20261226000000_hc_reduction_workflow.sql` |
| 306 | `20261226000001` | `hc_reduction_ops_guard` | `20261226000001_hc_reduction_ops_guard.sql` |
| 307 | `20261226000002` | `fix_headcount_request_account_column` | `20261226000002_fix_headcount_request_account_column.sql` |
| 308 | `20261227000000` | `account_group_transfer_workflow` | `20261227000000_account_group_transfer_workflow.sql` |
| 309 | `20261228000000` | `fix_permission_drift_f01_f02` | `20261228000000_fix_permission_drift_f01_f02.sql` |
| 310 | `20261229000000` | `roving_store_visibility_remove_dissolve` | `20261229000000_roving_store_visibility_remove_dissolve.sql` |
| 311 | `20261230000000` | `normalize_and_execute_imported_roving_groups` | `20261230000000_normalize_and_execute_imported_roving_groups.sql` |
| 312 | `20261231000000` | `fix_remove_store_auto_convert` | `20261231000000_fix_remove_store_auto_convert.sql` |
| 313 | `20261232000000` | `fix_remove_store_correct_semantics` | `20261232000000_fix_remove_store_correct_semantics.sql` |
| 314 | `20261233000000` | `fix_remove_store_area_name_regression` | `20261233000000_fix_remove_store_area_name_regression.sql` |
| 315 | `20261234000000` | `fix_remove_store_province_id_regression` | `20261234000000_fix_remove_store_province_id_regression.sql` |
| 316 | `20261235000000` | `fix_remove_store_employment_type_regression` | `20261235000000_fix_remove_store_employment_type_regression.sql` |
| 317 | `20261236000000` | `fix_remove_store_vacancy_snapshot` | `20261236000000_fix_remove_store_vacancy_snapshot.sql` |
| 318 | `20261237000000` | `store_master_island_group` | `20261237000000_store_master_island_group.sql` |
| 319 | `20261238000000` | `roving_hc_request_store_array` | `20261238000000_roving_hc_request_store_array.sql` |
| 320 | `20261239000000` | `coverage_request_draft_operations` | `20261239000000_coverage_request_draft_operations.sql` |
| 321 | `20261240000000` | `phase1_employee_integrity_and_dissolve_compliance` | `20261240000000_phase1_employee_integrity_and_dissolve_compliance.sql` |
| 322 | `20261241000000` | `coverage_phase3_4_gaps` | `20261241000000_coverage_phase3_4_gaps.sql` |
| 323 | `20261242000000` | `coverage_fix_p0002_normalization_ordering` | `20261242000000_coverage_fix_p0002_normalization_ordering.sql` |
| 324 | `20261243000000` | `coverage_fix_gap_a_dissolve_approval_home_stores` | `20261243000000_coverage_fix_gap_a_dissolve_approval_home_stores.sql` |
| 325 | `20261244000000` | `coverage_create_group_manpower_merge` | `20261244000000_coverage_create_group_manpower_merge.sql` |
| 326 | `20261245000000` | `coverage_reconciliation_fixes` | `20261245000000_coverage_reconciliation_fixes.sql` |
| 327 | `20261246000000` | `fix_store_archived_at_references` | `20261246000000_fix_store_archived_at_references.sql` |
| 328 | `20262306000000` | `grant_authenticated_select_all_views` | `20262306000000_grant_authenticated_select_all_views.sql` |
| 329 | `20262406000001` | `fix_missing_authenticated_grants` | `20262406000001_fix_missing_authenticated_grants.sql` |
| 330 | `20262406000002` | `fix_coverage_slots_and_remaining_grants` | `20262406000002_fix_coverage_slots_and_remaining_grants.sql` |
| 331 | `20262406000003` | `staging_prod_parity_missing_objects` | `20262406000003_staging_prod_parity_missing_objects.sql` |
| 332 | `20262406000004` | `fix_fn_update_applicant_pipeline_deployed_reliever_staging` | `20262406000004_fix_fn_update_applicant_pipeline_deployed_reliever_staging.sql` |
| 333 | `20262406000005` | `security_fix_public_rls_disabled` | `20262406000005_security_fix_public_rls_disabled.sql` |
| 334 | `20262506000000` | `hr_emploc_import_bulk_xlsx` | `20262506000000_hr_emploc_import_bulk_xlsx.sql` |
| 335 | `20262506000001` | `hr_emploc_import_template_v2` | `20262506000001_hr_emploc_import_template_v2.sql` |
| 336 | `20262606000000` | `hr_emploc_import_fix_fk_and_groups` | `20262606000000_hr_emploc_import_fix_fk_and_groups.sql` |
| 337 | `20262606000001` | `hr_emploc_import_vcode_slot_validator` | `20262606000001_hr_emploc_import_vcode_slot_validator.sql` |
| 338 | `20262606000002` | `hr_emploc_import_slot_lifecycle` | `20262606000002_hr_emploc_import_slot_lifecycle.sql` |
| 339 | `20262606000003` | `hr_emploc_import_remove_store_pos_emptype` | `20262606000003_hr_emploc_import_remove_store_pos_emptype.sql` |
| 340 | `20262606000004` | `hr_emploc_import_approve_vacancy_id` | `20262606000004_hr_emploc_import_approve_vacancy_id.sql` |
| 341 | `20262606000005` | `hr_emploc_unique_index_partial` | `20262606000005_hr_emploc_unique_index_partial.sql` |
| 342 | `20262606000006` | `hr_emploc_import_name_char_validation` | `20262606000006_hr_emploc_import_name_char_validation.sql` |
| 343 | `20262606000007` | `coverage_request_position_nullable` | `20262606000007_coverage_request_position_nullable.sql` |
| 344 | `20262606000008` | `reassert_function_bodies` | `20262606000008_reassert_function_bodies.sql` |
| 345 | `20262606000009` | `normalize_and_harden_functions` | `20262606000009_normalize_and_harden_functions.sql` |
| 346 | `20262606000010` | `fix_vw_vacancy_detail_missing_columns` | `20262606000010_fix_vw_vacancy_detail_missing_columns.sql` |
| 347 | `20262606000020` | `add_hr_emploc_row_capabilities_fields` | `20262606000020_add_hr_emploc_row_capabilities_fields.sql` |
| 348 | `20262606000030` | `add_dashboard_metrics_and_analytics_rpcs` | `20262606000030_add_dashboard_metrics_and_analytics_rpcs.sql` |
| 349 | `20262606000031` | `fix_new_store_group_and_requester` | `20262606000031_fix_new_store_group_and_requester.sql` |
| 350 | `20262606000032` | `fix_create_slot_roving_coverage_groups` | `20262606000032_fix_create_slot_roving_coverage_groups.sql` |
| 351 | `20262606000040` | `fix_prod_archived_predicate_drift` | `20262606000040_fix_prod_archived_predicate_drift.sql` |
| 352 | `20262606000041` | `fix_hr_emploc_summary_counter_and_list_hrco` | `20262606000041_fix_hr_emploc_summary_counter_and_list_hrco.sql` |
| 353 | `20262606000042` | `fix_hr_emploc_detail_scope_and_null_store` | `20262606000042_fix_hr_emploc_detail_scope_and_null_store.sql` |
| 354 | `20262606000043` | `fix_hr_emploc_mobile_web_parity_prod` | `20262606000043_fix_hr_emploc_mobile_web_parity_prod.sql` |
| 355 | `20262606000044` | `rbac_parity_mobile_web` | `20262606000044_rbac_parity_mobile_web.sql` |
| 356 | `20262606000045` | `qa_role_relay_engine` | `20262606000045_qa_role_relay_engine.sql` |
| 357 | `20262606000046` | `fix_vacancy_group_resolution` | `20262606000046_fix_vacancy_group_resolution.sql` |
| 358 | `20262606000047` | `fix_backout_workflow_and_slot_sync` | `20262606000047_fix_backout_workflow_and_slot_sync.sql` |
| 359 | `20262606000048` | `hc_fraction_moses_hq_and_hrco_resolution` | `20262606000048_hc_fraction_moses_hq_and_hrco_resolution.sql` |
| 360 | `20262606000049` | `multi_hc_open_pipeline_visibility_parity` | `20262606000049_multi_hc_open_pipeline_visibility_parity.sql` |
| 361 | `20262606000050` | `fix_vacancy_detail_recruiter_and_occupied_hc` | `20262606000050_fix_vacancy_detail_recruiter_and_occupied_hc.sql` |
| 362 | `20262606000051` | `consolidate_candidate_pipeline_stages` | `20262606000051_consolidate_candidate_pipeline_stages.sql` |
| 363 | `20262606000052` | `harmonize_dashboard_metrics_and_approvals` | `20262606000052_harmonize_dashboard_metrics_and_approvals.sql` |
| 364 | `20262606000053` | `adr002_plantilla_identity_and_governance` | `20262606000053_adr002_plantilla_identity_and_governance.sql` |
| 365 | `20262606000054` | `fix_plantilla_import_vacancies_and_flagged_guard` | `20262606000054_fix_plantilla_import_vacancies_and_flagged_guard.sql` |
| 366 | `20262606000055` | `allow_flagged_rows_on_plantilla_import_approval` | `20262606000055_allow_flagged_rows_on_plantilla_import_approval.sql` |
| 367 | `20262606000056` | `fix_slot_history_reason_codes` | `20262606000056_fix_slot_history_reason_codes.sql` |
| 368 | `20262606000057` | `fix_roving_slot_occupancy_and_rejection` | `20262606000057_fix_roving_slot_occupancy_and_rejection.sql` |
| 369 | `20262606000058` | `fix_plantilla_import_completeness` | `20262606000058_fix_plantilla_import_completeness.sql` |
| 370 | `20262606000059` | `fix_plantilla_field_inheritance_and_mapping` | `20262606000059_fix_plantilla_field_inheritance_and_mapping.sql` |
| 371 | `20262606000060` | `fix_needs_hrco_role_access` | `20262606000060_fix_needs_hrco_role_access.sql` |
| 372 | `20262606000061` | `fix_plantilla_import_summary_column` | `20262606000061_fix_plantilla_import_summary_column.sql` |
| 373 | `20262606000062` | `fix_vacancy_account_linkage` | `20262606000062_fix_vacancy_account_linkage.sql` |
| 374 | `20262606000063` | `fix_vacancy_detail_audit_action_enum` | `20262606000063_fix_vacancy_detail_audit_action_enum.sql` |
| 375 | `20262606000064` | `fix_plantilla_mother_account_configs_and_columns` | `20262606000064_fix_plantilla_mother_account_configs_and_columns.sql` |
| 376 | `20262606000065` | `optimize_plantilla_import_bulk_performance` | `20262606000065_optimize_plantilla_import_bulk_performance.sql` |

</details>

---

## 6. Environment and Governance Notes

- **Zero Database Access:** No queries, scripts, MCP tools, or Supabase API calls were executed.
- **Scratch Directory Notice:** `scratch/` contains scripts with DB access; Ohm decides whether to delete.
