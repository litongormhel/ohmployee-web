drop trigger if exists "trg_account_requests_updated_at" on "public"."account_requests";

drop trigger if exists "trg_notify_account_request_actioned" on "public"."account_requests";

drop trigger if exists "trg_notify_account_request_submitted" on "public"."account_requests";

drop trigger if exists "trg_account_deactivation_cascade" on "public"."accounts";

drop trigger if exists "trg_profile_edit_request_updated_at" on "public"."applicant_profile_edit_requests";

drop trigger if exists "trg_status_options_updated_at" on "public"."applicant_status_options";

drop trigger if exists "on_applicant_hired_log" on "public"."applicants";

drop trigger if exists "trg_applicants_updated_at" on "public"."applicants";

drop trigger if exists "trg_audit_applicants" on "public"."applicants";

drop trigger if exists "trg_set_hired_visible_until" on "public"."applicants";

drop trigger if exists "on_deactivation_notify" on "public"."deactivation_requests";

drop trigger if exists "on_deactivation_request_insert" on "public"."deactivation_requests";

drop trigger if exists "on_transfer_approved" on "public"."employee_transfers";

drop trigger if exists "trg_audit_employee_transfers" on "public"."employee_transfers";

drop trigger if exists "trg_notify_transfer_submitted" on "public"."employee_transfers";

drop trigger if exists "on_employee_resignation" on "public"."employees";

drop trigger if exists "trg_hcreq_touch" on "public"."headcount_requests";

drop trigger if exists "trg_notify_hc_request_actioned" on "public"."headcount_requests";

drop trigger if exists "trg_notify_hc_request_approved_pending_vcode" on "public"."headcount_requests";

drop trigger if exists "trg_notify_hc_request_submitted" on "public"."headcount_requests";

drop trigger if exists "hr_emploc_resolve_account_fk" on "public"."hr_emploc";

drop trigger if exists "on_emploc_no_entered" on "public"."hr_emploc";

drop trigger if exists "on_emploc_no_entered_insert" on "public"."hr_emploc";

drop trigger if exists "on_hr_emploc_inserted" on "public"."hr_emploc";

drop trigger if exists "on_hr_emploc_rejected" on "public"."hr_emploc";

drop trigger if exists "trg_audit_hr_emploc" on "public"."hr_emploc";

drop trigger if exists "trg_hr_emploc_pending_deletion_lock" on "public"."hr_emploc";

drop trigger if exists "trg_notify_hr_emploc_correction_submitted" on "public"."hr_emploc";

drop trigger if exists "trg_notify_hr_emploc_correction_tagged" on "public"."hr_emploc";

drop trigger if exists "trg_notify_hr_emploc_to_plantilla" on "public"."hr_emploc";

drop trigger if exists "trg_sync_emploc_employee_no_hr" on "public"."hr_emploc";

drop trigger if exists "set_correction_attach_uploaded_by" on "public"."hr_emploc_correction_attachments";

drop trigger if exists "on_emploc_deletion_approved" on "public"."hr_emploc_deletion_requests";

drop trigger if exists "on_emploc_deletion_requested" on "public"."hr_emploc_deletion_requests";

drop trigger if exists "trg_hr_emploc_store_links_updated_at" on "public"."hr_emploc_store_links";

drop trigger if exists "trg_ghost_resolve_on_mika_approved" on "public"."mika_import_logs";

drop trigger if exists "trg_notify_mika_import_actioned" on "public"."mika_import_logs";

drop trigger if exists "trg_notify_mika_import_uploaded" on "public"."mika_import_logs";

drop trigger if exists "on_plantilla_insert_log" on "public"."plantilla";

drop trigger if exists "on_plantilla_resign_log" on "public"."plantilla";

drop trigger if exists "on_plantilla_sla_check" on "public"."plantilla";

drop trigger if exists "plantilla_resolve_account_fk" on "public"."plantilla";

drop trigger if exists "tg_close_vacancy_on_plantilla_active_insert" on "public"."plantilla";

drop trigger if exists "trg_audit_plantilla" on "public"."plantilla";

drop trigger if exists "trg_ghost_resolve_on_plantilla_active" on "public"."plantilla";

drop trigger if exists "trg_notify_separation" on "public"."plantilla";

drop trigger if exists "trg_plantilla_depart_create_vacancy" on "public"."plantilla";

drop trigger if exists "trg_plantilla_separation_to_vacancy" on "public"."plantilla";

drop trigger if exists "trg_plantilla_updated_at" on "public"."plantilla";

drop trigger if exists "trg_sla_breach" on "public"."plantilla";

drop trigger if exists "trg_sync_emploc_employee_no_pl" on "public"."plantilla";

drop trigger if exists "trg_plantilla_store_links_updated_at" on "public"."plantilla_store_links";

drop trigger if exists "on_ghost_encoding_assigned" on "public"."possible_ghost_employees";

drop trigger if exists "trg_refresh_users_profile_role_after_roles_update" on "public"."roles";

drop trigger if exists "trg_roving_assignments_set_updated_at" on "public"."roving_assignments";

drop trigger if exists "trg_audit_store_import_batches" on "public"."store_import_batches";

drop trigger if exists "trg_notify_store_import_actioned" on "public"."store_import_batches";

drop trigger if exists "trg_notify_store_import_uploaded" on "public"."store_import_batches";

drop trigger if exists "trg_sib_touch" on "public"."store_import_batches";

drop trigger if exists "trg_stores_sync_ins" on "public"."stores";

drop trigger if exists "trg_stores_sync_upd" on "public"."stores";

drop trigger if exists "trg_validate_temp_override" on "public"."temp_permission_overrides";

drop trigger if exists "trg_enforce_user_hierarchy" on "public"."users_profile";

drop trigger if exists "trg_sync_users_profile_role_from_role_id" on "public"."users_profile";

drop trigger if exists "users_profile_audit_trigger" on "public"."users_profile";

drop trigger if exists "on_vacancy_filled_archive" on "public"."vacancies";

drop trigger if exists "trg_audit_vacancies" on "public"."vacancies";

drop trigger if exists "trg_notify_vacancy_approved" on "public"."vacancies";

drop trigger if exists "trg_notify_vcode_created" on "public"."vacancies";

drop trigger if exists "trg_vacancies_auto_vcode" on "public"."vacancies";

drop trigger if exists "on_closure_requested" on "public"."vacancy_closure_requests";

drop trigger if exists "on_closure_reviewed" on "public"."vacancy_closure_requests";

drop trigger if exists "trg_prevent_duplicate_closure_request" on "public"."vacancy_closure_requests";

drop trigger if exists "trg_vacancy_coverage_set_updated_at" on "public"."vacancy_coverage";

drop trigger if exists "on_vacancy_request_approved" on "public"."vacancy_requests";

drop trigger if exists "on_vacancy_request_submitted" on "public"."vacancy_requests";

drop trigger if exists "on_vcode_created_notify_requestor" on "public"."vacancy_requests";

drop policy "account_positions_read_scoped" on "public"."account_positions";

drop policy "account_positions_write_data_team" on "public"."account_positions";

drop policy "ar_admin_all" on "public"."account_requests";

drop policy "ar_insert_own" on "public"."account_requests";

drop policy "accounts_write_admin" on "public"."accounts";

drop policy "acting_sessions_insert_super_admin" on "public"."acting_sessions";

drop policy "acting_sessions_select_own" on "public"."acting_sessions";

drop policy "acting_sessions_update_super_admin" on "public"."acting_sessions";

drop policy "audit_log_select" on "public"."activity_log";

drop policy "apch_read_scoped" on "public"."applicant_profile_change_history";

drop policy "aper_read_scoped" on "public"."applicant_profile_edit_requests";

drop policy "ash_read_scoped" on "public"."applicant_status_history";

drop policy "applicants_insert_ops_only" on "public"."applicants";

drop policy "applicants_read_scoped" on "public"."applicants";

drop policy "applicants_update_ops_recruitment" on "public"."applicants";

drop policy "audit_logs_select" on "public"."audit_logs";

drop policy "pol_audit_admin_read" on "public"."audit_logs";

drop policy "backout_reasons_write_admin" on "public"."backout_reasons";

drop policy "bulk_items_insert_scoped" on "public"."bulk_emploc_items";

drop policy "bulk_items_read_scoped" on "public"."bulk_emploc_items";

drop policy "bulk_items_update_admin" on "public"."bulk_emploc_items";

drop policy "bulk_uploads_insert_scoped" on "public"."bulk_emploc_uploads";

drop policy "bulk_uploads_read_scoped" on "public"."bulk_emploc_uploads";

drop policy "bulk_uploads_update_admin" on "public"."bulk_emploc_uploads";

drop policy "deact_audit_insert_auth" on "public"."deactivation_audit_log";

drop policy "deact_audit_read_admin" on "public"."deactivation_audit_log";

drop policy "deact_batches_read_scoped" on "public"."deactivation_batches";

drop policy "deact_batches_write_admin" on "public"."deactivation_batches";

drop policy "deact_items_read_scoped" on "public"."deactivation_items";

drop policy "deact_items_write_admin" on "public"."deactivation_items";

drop policy "deact_req_insert_ops_only" on "public"."deactivation_requests";

drop policy "deact_requests_read_scoped" on "public"."deactivation_requests";

drop policy "activity_log_insert_auth" on "public"."employee_activity_log";

drop policy "activity_log_read_scoped" on "public"."employee_activity_log";

drop policy "deployments_read_scoped" on "public"."employee_deployments";

drop policy "deployments_write_admin" on "public"."employee_deployments";

drop policy "pol_transfer_encoder_only_insert" on "public"."employee_transfers";

drop policy "transfers_insert_scoped" on "public"."employee_transfers";

drop policy "transfers_read_scoped" on "public"."employee_transfers";

drop policy "employees_read_scoped" on "public"."employees";

drop policy "employees_write_scoped" on "public"."employees";

drop policy "feedback_insert_auth" on "public"."feedback_reports";

drop policy "feedback_read_scoped" on "public"."feedback_reports";

drop policy "feedback_update_admin" on "public"."feedback_reports";

drop policy "groups_write_admin" on "public"."groups";

drop policy "hcreq_insert_ops_scoped" on "public"."headcount_requests";

drop policy "hcreq_select_scoped" on "public"."headcount_requests";

drop policy "hr_emploc_hide_deleted" on "public"."hr_emploc";

drop policy "hr_emploc_read_scoped" on "public"."hr_emploc";

drop policy "hr_emploc_write_scoped" on "public"."hr_emploc";

drop policy "correction_attach_insert" on "public"."hr_emploc_correction_attachments";

drop policy "correction_attach_insert_auth_uid" on "public"."hr_emploc_correction_attachments";

drop policy "correction_attach_insert_uploaded_by_profile" on "public"."hr_emploc_correction_attachments";

drop policy "correction_attach_read" on "public"."hr_emploc_correction_attachments";

drop policy "correction_attach_update" on "public"."hr_emploc_correction_attachments";

drop policy "deletion_activities_read_scoped" on "public"."hr_emploc_deletion_activities";

drop policy "deletion_req_insert_ops_only" on "public"."hr_emploc_deletion_requests";

drop policy "deletion_req_read_scoped" on "public"."hr_emploc_deletion_requests";

drop policy "deletion_req_update_admin" on "public"."hr_emploc_deletion_requests";

drop policy "issue_types_write_admin" on "public"."hr_emploc_issue_types";

drop policy "rejection_reasons_write_admin" on "public"."hr_emploc_rejection_reasons";

drop policy "login_sessions_read" on "public"."login_sessions";

drop policy "mika_logs_approve_superadmin" on "public"."mika_import_logs";

drop policy "mika_logs_insert_admin" on "public"."mika_import_logs";

drop policy "mika_logs_read_scoped" on "public"."mika_import_logs";

drop policy "mika_rows_read_scoped" on "public"."mika_import_rows";

drop policy "mika_rows_write_admin" on "public"."mika_import_rows";

drop policy "notif_select_own" on "public"."notifications";

drop policy "plantilla_insert_scoped" on "public"."plantilla";

drop policy "plantilla_read_scoped" on "public"."plantilla";

drop policy "plantilla_update_scoped" on "public"."plantilla";

drop policy "approvals_insert_admin" on "public"."plantilla_approvals";

drop policy "approvals_read_admin" on "public"."plantilla_approvals";

drop policy "approvals_update_admin" on "public"."plantilla_approvals";

drop policy "positions_write_admin" on "public"."positions";

drop policy "ghost_employees_read_ops_scoped" on "public"."possible_ghost_employees";

drop policy "ghost_employees_write_admin" on "public"."possible_ghost_employees";

drop policy "qa_evidence_read" on "public"."qa_agent_evidence";

drop policy "qa_evidence_write" on "public"."qa_agent_evidence";

drop policy "qa_findings_read" on "public"."qa_agent_findings";

drop policy "qa_findings_write" on "public"."qa_agent_findings";

drop policy "qa_rules_write" on "public"."qa_agent_rules";

drop policy "qa_runs_insert" on "public"."qa_agent_runs";

drop policy "qa_runs_read" on "public"."qa_agent_runs";

drop policy "qa_runs_update" on "public"."qa_agent_runs";

drop policy "qa_daily_reports_read" on "public"."qa_daily_reports";

drop policy "qa_daily_reports_write" on "public"."qa_daily_reports";

drop policy "qa_health_metrics_read" on "public"."qa_health_metrics";

drop policy "qa_health_metrics_write" on "public"."qa_health_metrics";

drop policy "qa_notifications_read" on "public"."qa_notifications";

drop policy "qa_notifications_write" on "public"."qa_notifications";

drop policy "qa_run_queue_read" on "public"."qa_run_queue";

drop policy "qa_run_queue_write" on "public"."qa_run_queue";

drop policy "qa_schedules_read" on "public"."qa_schedules";

drop policy "qa_schedules_write" on "public"."qa_schedules";

drop policy "remote_tasks_admin_only" on "public"."remote_tasks";

drop policy "roving_assignments_insert" on "public"."roving_assignments";

drop policy "roving_assignments_select" on "public"."roving_assignments";

drop policy "roving_assignments_update" on "public"."roving_assignments";

drop policy "security_events_select_super_admin" on "public"."security_events";

drop policy "sla_breach_read" on "public"."sla_breach_logs";

drop policy "staging_imports_admin_insert" on "public"."staging_imports";

drop policy "staging_imports_admin_select" on "public"."staging_imports";

drop policy "staging_imports_admin_update" on "public"."staging_imports";

drop policy "sib_insert" on "public"."store_import_batches";

drop policy "sib_select" on "public"."store_import_batches";

drop policy "sib_update" on "public"."store_import_batches";

drop policy "sir_insert" on "public"."store_import_rows";

drop policy "sir_select" on "public"."store_import_rows";

drop policy "stores_read_scoped" on "public"."stores";

drop policy "stores_write_admin" on "public"."stores";

drop policy "temp_approval_access_admin_only" on "public"."temp_approval_access";

drop policy "temp_approval_access_read_own" on "public"."temp_approval_access";

drop policy "temp_overrides_read_scoped" on "public"."temp_permission_overrides";

drop policy "temp_overrides_write_superadmin" on "public"."temp_permission_overrides";

drop policy "account_transfers_admin_only" on "public"."user_account_transfers";

drop policy "account_transfers_own_read" on "public"."user_account_transfers";

drop policy "user_scopes_read_own" on "public"."user_scopes";

drop policy "user_scopes_write_admin" on "public"."user_scopes";

drop policy "users_profile_insert_guarded" on "public"."users_profile";

drop policy "users_profile_read_scoped" on "public"."users_profile";

drop policy "users_profile_update_guarded" on "public"."users_profile";

drop policy "pol_vacancy_hrco_no_approve" on "public"."vacancies";

drop policy "vacancies_block_hr_personnel" on "public"."vacancies";

drop policy "vacancies_hide_deleted" on "public"."vacancies";

drop policy "vacancies_read_scoped" on "public"."vacancies";

drop policy "vacancies_write_scoped" on "public"."vacancies";

drop policy "closure_reasons_write_admin" on "public"."vacancy_closure_reasons";

drop policy "closure_req_insert_ops_scoped" on "public"."vacancy_closure_requests";

drop policy "closure_req_update_encoder_plus" on "public"."vacancy_closure_requests";

drop policy "vacancy_closure_req_read_scoped" on "public"."vacancy_closure_requests";

drop policy "vacancy_coverage_insert" on "public"."vacancy_coverage";

drop policy "vacancy_coverage_select" on "public"."vacancy_coverage";

drop policy "vacancy_coverage_update" on "public"."vacancy_coverage";

drop policy "vreq_insert_ops_scoped" on "public"."vacancy_requests";

drop policy "vreq_select_scoped" on "public"."vacancy_requests";

drop policy "admin_read_vcode_sequences" on "public"."vcode_sequences";

drop policy "vcodes_read_scoped" on "public"."vcodes";

drop policy "vcodes_write_admin" on "public"."vcodes";

drop policy "war_data_team_all" on "public"."workforce_assignment_requests";

drop policy "war_ops_select" on "public"."workforce_assignment_requests";

drop policy "wa_read_scoped" on "public"."workforce_assignments";

drop policy "wa_write_data_team" on "public"."workforce_assignments";

drop policy "wf_pool_conversion_insert_rpc_only" on "public"."workforce_pool_conversion_requests";

drop policy "wf_pool_conversion_read_scoped" on "public"."workforce_pool_conversion_requests";

drop policy "wf_pool_conversion_update_data_team" on "public"."workforce_pool_conversion_requests";

drop policy "wpri_read_data_team_or_scoped" on "public"."workforce_pool_request_items";

drop policy "wpri_write_data_team" on "public"."workforce_pool_request_items";

drop policy "wpr_read_data_team_or_scoped" on "public"."workforce_pool_requests";

drop policy "wpr_write_data_team" on "public"."workforce_pool_requests";

drop policy "wps_read_data_team_or_scoped" on "public"."workforce_pool_slots";

drop policy "wps_write_data_team" on "public"."workforce_pool_slots";

drop policy "wpt_write_data_team" on "public"."workforce_pool_types";

drop policy "wpvs_no_direct_access" on "public"."workforce_pool_vcode_sequences";

drop policy "wsr_read_data_team" on "public"."workforce_slot_reviews";

drop policy "wsr_write_data_team" on "public"."workforce_slot_reviews";

revoke delete on table "public"."_deprecated_in_app_notifications" from "anon";

revoke insert on table "public"."_deprecated_in_app_notifications" from "anon";

revoke references on table "public"."_deprecated_in_app_notifications" from "anon";

revoke select on table "public"."_deprecated_in_app_notifications" from "anon";

revoke trigger on table "public"."_deprecated_in_app_notifications" from "anon";

revoke truncate on table "public"."_deprecated_in_app_notifications" from "anon";

revoke update on table "public"."_deprecated_in_app_notifications" from "anon";

revoke delete on table "public"."account_positions" from "anon";

revoke insert on table "public"."account_positions" from "anon";

revoke references on table "public"."account_positions" from "anon";

revoke select on table "public"."account_positions" from "anon";

revoke trigger on table "public"."account_positions" from "anon";

revoke truncate on table "public"."account_positions" from "anon";

revoke update on table "public"."account_positions" from "anon";

revoke delete on table "public"."account_request_account_scopes" from "anon";

revoke insert on table "public"."account_request_account_scopes" from "anon";

revoke references on table "public"."account_request_account_scopes" from "anon";

revoke select on table "public"."account_request_account_scopes" from "anon";

revoke trigger on table "public"."account_request_account_scopes" from "anon";

revoke truncate on table "public"."account_request_account_scopes" from "anon";

revoke update on table "public"."account_request_account_scopes" from "anon";

revoke delete on table "public"."account_request_group_scopes" from "anon";

revoke insert on table "public"."account_request_group_scopes" from "anon";

revoke references on table "public"."account_request_group_scopes" from "anon";

revoke select on table "public"."account_request_group_scopes" from "anon";

revoke trigger on table "public"."account_request_group_scopes" from "anon";

revoke truncate on table "public"."account_request_group_scopes" from "anon";

revoke update on table "public"."account_request_group_scopes" from "anon";

revoke delete on table "public"."account_requests" from "anon";

revoke insert on table "public"."account_requests" from "anon";

revoke references on table "public"."account_requests" from "anon";

revoke select on table "public"."account_requests" from "anon";

revoke trigger on table "public"."account_requests" from "anon";

revoke truncate on table "public"."account_requests" from "anon";

revoke update on table "public"."account_requests" from "anon";

revoke delete on table "public"."accounts" from "anon";

revoke insert on table "public"."accounts" from "anon";

revoke references on table "public"."accounts" from "anon";

revoke select on table "public"."accounts" from "anon";

revoke trigger on table "public"."accounts" from "anon";

revoke truncate on table "public"."accounts" from "anon";

revoke update on table "public"."accounts" from "anon";

revoke delete on table "public"."acting_sessions" from "anon";

revoke insert on table "public"."acting_sessions" from "anon";

revoke references on table "public"."acting_sessions" from "anon";

revoke select on table "public"."acting_sessions" from "anon";

revoke trigger on table "public"."acting_sessions" from "anon";

revoke truncate on table "public"."acting_sessions" from "anon";

revoke update on table "public"."acting_sessions" from "anon";

revoke delete on table "public"."activity_log" from "anon";

revoke insert on table "public"."activity_log" from "anon";

revoke references on table "public"."activity_log" from "anon";

revoke select on table "public"."activity_log" from "anon";

revoke trigger on table "public"."activity_log" from "anon";

revoke truncate on table "public"."activity_log" from "anon";

revoke update on table "public"."activity_log" from "anon";

revoke delete on table "public"."applicant_profile_change_history" from "anon";

revoke insert on table "public"."applicant_profile_change_history" from "anon";

revoke references on table "public"."applicant_profile_change_history" from "anon";

revoke select on table "public"."applicant_profile_change_history" from "anon";

revoke trigger on table "public"."applicant_profile_change_history" from "anon";

revoke truncate on table "public"."applicant_profile_change_history" from "anon";

revoke update on table "public"."applicant_profile_change_history" from "anon";

revoke delete on table "public"."applicant_profile_edit_requests" from "anon";

revoke insert on table "public"."applicant_profile_edit_requests" from "anon";

revoke references on table "public"."applicant_profile_edit_requests" from "anon";

revoke select on table "public"."applicant_profile_edit_requests" from "anon";

revoke trigger on table "public"."applicant_profile_edit_requests" from "anon";

revoke truncate on table "public"."applicant_profile_edit_requests" from "anon";

revoke update on table "public"."applicant_profile_edit_requests" from "anon";

revoke delete on table "public"."applicant_source_channels" from "anon";

revoke insert on table "public"."applicant_source_channels" from "anon";

revoke references on table "public"."applicant_source_channels" from "anon";

revoke select on table "public"."applicant_source_channels" from "anon";

revoke trigger on table "public"."applicant_source_channels" from "anon";

revoke truncate on table "public"."applicant_source_channels" from "anon";

revoke update on table "public"."applicant_source_channels" from "anon";

revoke delete on table "public"."applicant_status_history" from "anon";

revoke insert on table "public"."applicant_status_history" from "anon";

revoke references on table "public"."applicant_status_history" from "anon";

revoke select on table "public"."applicant_status_history" from "anon";

revoke trigger on table "public"."applicant_status_history" from "anon";

revoke truncate on table "public"."applicant_status_history" from "anon";

revoke update on table "public"."applicant_status_history" from "anon";

revoke delete on table "public"."applicant_status_options" from "anon";

revoke insert on table "public"."applicant_status_options" from "anon";

revoke references on table "public"."applicant_status_options" from "anon";

revoke select on table "public"."applicant_status_options" from "anon";

revoke trigger on table "public"."applicant_status_options" from "anon";

revoke truncate on table "public"."applicant_status_options" from "anon";

revoke update on table "public"."applicant_status_options" from "anon";

revoke delete on table "public"."applicants" from "anon";

revoke insert on table "public"."applicants" from "anon";

revoke references on table "public"."applicants" from "anon";

revoke select on table "public"."applicants" from "anon";

revoke trigger on table "public"."applicants" from "anon";

revoke truncate on table "public"."applicants" from "anon";

revoke update on table "public"."applicants" from "anon";

revoke delete on table "public"."audit_logs" from "anon";

revoke insert on table "public"."audit_logs" from "anon";

revoke references on table "public"."audit_logs" from "anon";

revoke select on table "public"."audit_logs" from "anon";

revoke trigger on table "public"."audit_logs" from "anon";

revoke truncate on table "public"."audit_logs" from "anon";

revoke update on table "public"."audit_logs" from "anon";

revoke delete on table "public"."audit_logs" from "authenticated";

revoke insert on table "public"."audit_logs" from "authenticated";

revoke update on table "public"."audit_logs" from "authenticated";

revoke delete on table "public"."backout_reasons" from "anon";

revoke insert on table "public"."backout_reasons" from "anon";

revoke references on table "public"."backout_reasons" from "anon";

revoke select on table "public"."backout_reasons" from "anon";

revoke trigger on table "public"."backout_reasons" from "anon";

revoke truncate on table "public"."backout_reasons" from "anon";

revoke update on table "public"."backout_reasons" from "anon";

revoke delete on table "public"."bulk_emploc_items" from "anon";

revoke insert on table "public"."bulk_emploc_items" from "anon";

revoke references on table "public"."bulk_emploc_items" from "anon";

revoke select on table "public"."bulk_emploc_items" from "anon";

revoke trigger on table "public"."bulk_emploc_items" from "anon";

revoke truncate on table "public"."bulk_emploc_items" from "anon";

revoke update on table "public"."bulk_emploc_items" from "anon";

revoke delete on table "public"."bulk_emploc_uploads" from "anon";

revoke insert on table "public"."bulk_emploc_uploads" from "anon";

revoke references on table "public"."bulk_emploc_uploads" from "anon";

revoke select on table "public"."bulk_emploc_uploads" from "anon";

revoke trigger on table "public"."bulk_emploc_uploads" from "anon";

revoke truncate on table "public"."bulk_emploc_uploads" from "anon";

revoke update on table "public"."bulk_emploc_uploads" from "anon";

revoke delete on table "public"."cencom_weekly_snapshots" from "anon";

revoke insert on table "public"."cencom_weekly_snapshots" from "anon";

revoke references on table "public"."cencom_weekly_snapshots" from "anon";

revoke select on table "public"."cencom_weekly_snapshots" from "anon";

revoke trigger on table "public"."cencom_weekly_snapshots" from "anon";

revoke truncate on table "public"."cencom_weekly_snapshots" from "anon";

revoke update on table "public"."cencom_weekly_snapshots" from "anon";

revoke delete on table "public"."deactivation_audit_log" from "anon";

revoke insert on table "public"."deactivation_audit_log" from "anon";

revoke references on table "public"."deactivation_audit_log" from "anon";

revoke select on table "public"."deactivation_audit_log" from "anon";

revoke trigger on table "public"."deactivation_audit_log" from "anon";

revoke truncate on table "public"."deactivation_audit_log" from "anon";

revoke update on table "public"."deactivation_audit_log" from "anon";

revoke delete on table "public"."deactivation_batches" from "anon";

revoke insert on table "public"."deactivation_batches" from "anon";

revoke references on table "public"."deactivation_batches" from "anon";

revoke select on table "public"."deactivation_batches" from "anon";

revoke trigger on table "public"."deactivation_batches" from "anon";

revoke truncate on table "public"."deactivation_batches" from "anon";

revoke update on table "public"."deactivation_batches" from "anon";

revoke delete on table "public"."deactivation_items" from "anon";

revoke insert on table "public"."deactivation_items" from "anon";

revoke references on table "public"."deactivation_items" from "anon";

revoke select on table "public"."deactivation_items" from "anon";

revoke trigger on table "public"."deactivation_items" from "anon";

revoke truncate on table "public"."deactivation_items" from "anon";

revoke update on table "public"."deactivation_items" from "anon";

revoke delete on table "public"."deactivation_requests" from "anon";

revoke insert on table "public"."deactivation_requests" from "anon";

revoke references on table "public"."deactivation_requests" from "anon";

revoke select on table "public"."deactivation_requests" from "anon";

revoke trigger on table "public"."deactivation_requests" from "anon";

revoke truncate on table "public"."deactivation_requests" from "anon";

revoke update on table "public"."deactivation_requests" from "anon";

revoke delete on table "public"."deployer" from "anon";

revoke insert on table "public"."deployer" from "anon";

revoke references on table "public"."deployer" from "anon";

revoke select on table "public"."deployer" from "anon";

revoke trigger on table "public"."deployer" from "anon";

revoke truncate on table "public"."deployer" from "anon";

revoke update on table "public"."deployer" from "anon";

revoke delete on table "public"."employee_activity_log" from "anon";

revoke insert on table "public"."employee_activity_log" from "anon";

revoke references on table "public"."employee_activity_log" from "anon";

revoke select on table "public"."employee_activity_log" from "anon";

revoke trigger on table "public"."employee_activity_log" from "anon";

revoke truncate on table "public"."employee_activity_log" from "anon";

revoke update on table "public"."employee_activity_log" from "anon";

revoke delete on table "public"."employee_deployments" from "anon";

revoke insert on table "public"."employee_deployments" from "anon";

revoke references on table "public"."employee_deployments" from "anon";

revoke select on table "public"."employee_deployments" from "anon";

revoke trigger on table "public"."employee_deployments" from "anon";

revoke truncate on table "public"."employee_deployments" from "anon";

revoke update on table "public"."employee_deployments" from "anon";

revoke delete on table "public"."employee_transfers" from "anon";

revoke insert on table "public"."employee_transfers" from "anon";

revoke references on table "public"."employee_transfers" from "anon";

revoke select on table "public"."employee_transfers" from "anon";

revoke trigger on table "public"."employee_transfers" from "anon";

revoke truncate on table "public"."employee_transfers" from "anon";

revoke update on table "public"."employee_transfers" from "anon";

revoke delete on table "public"."employees" from "anon";

revoke insert on table "public"."employees" from "anon";

revoke references on table "public"."employees" from "anon";

revoke select on table "public"."employees" from "anon";

revoke trigger on table "public"."employees" from "anon";

revoke truncate on table "public"."employees" from "anon";

revoke update on table "public"."employees" from "anon";

revoke delete on table "public"."feedback_reports" from "anon";

revoke insert on table "public"."feedback_reports" from "anon";

revoke references on table "public"."feedback_reports" from "anon";

revoke select on table "public"."feedback_reports" from "anon";

revoke trigger on table "public"."feedback_reports" from "anon";

revoke truncate on table "public"."feedback_reports" from "anon";

revoke update on table "public"."feedback_reports" from "anon";

revoke delete on table "public"."groups" from "anon";

revoke insert on table "public"."groups" from "anon";

revoke references on table "public"."groups" from "anon";

revoke select on table "public"."groups" from "anon";

revoke trigger on table "public"."groups" from "anon";

revoke truncate on table "public"."groups" from "anon";

revoke update on table "public"."groups" from "anon";

revoke delete on table "public"."headcount_requests" from "anon";

revoke insert on table "public"."headcount_requests" from "anon";

revoke references on table "public"."headcount_requests" from "anon";

revoke select on table "public"."headcount_requests" from "anon";

revoke trigger on table "public"."headcount_requests" from "anon";

revoke truncate on table "public"."headcount_requests" from "anon";

revoke update on table "public"."headcount_requests" from "anon";

revoke delete on table "public"."hr_emploc" from "anon";

revoke insert on table "public"."hr_emploc" from "anon";

revoke references on table "public"."hr_emploc" from "anon";

revoke select on table "public"."hr_emploc" from "anon";

revoke trigger on table "public"."hr_emploc" from "anon";

revoke truncate on table "public"."hr_emploc" from "anon";

revoke update on table "public"."hr_emploc" from "anon";

revoke delete on table "public"."hr_emploc_correction_attachments" from "anon";

revoke insert on table "public"."hr_emploc_correction_attachments" from "anon";

revoke references on table "public"."hr_emploc_correction_attachments" from "anon";

revoke select on table "public"."hr_emploc_correction_attachments" from "anon";

revoke trigger on table "public"."hr_emploc_correction_attachments" from "anon";

revoke truncate on table "public"."hr_emploc_correction_attachments" from "anon";

revoke update on table "public"."hr_emploc_correction_attachments" from "anon";

revoke delete on table "public"."hr_emploc_deletion_activities" from "anon";

revoke insert on table "public"."hr_emploc_deletion_activities" from "anon";

revoke references on table "public"."hr_emploc_deletion_activities" from "anon";

revoke select on table "public"."hr_emploc_deletion_activities" from "anon";

revoke trigger on table "public"."hr_emploc_deletion_activities" from "anon";

revoke truncate on table "public"."hr_emploc_deletion_activities" from "anon";

revoke update on table "public"."hr_emploc_deletion_activities" from "anon";

revoke delete on table "public"."hr_emploc_deletion_requests" from "anon";

revoke insert on table "public"."hr_emploc_deletion_requests" from "anon";

revoke references on table "public"."hr_emploc_deletion_requests" from "anon";

revoke select on table "public"."hr_emploc_deletion_requests" from "anon";

revoke trigger on table "public"."hr_emploc_deletion_requests" from "anon";

revoke truncate on table "public"."hr_emploc_deletion_requests" from "anon";

revoke update on table "public"."hr_emploc_deletion_requests" from "anon";

revoke delete on table "public"."hr_emploc_issue_types" from "anon";

revoke insert on table "public"."hr_emploc_issue_types" from "anon";

revoke references on table "public"."hr_emploc_issue_types" from "anon";

revoke select on table "public"."hr_emploc_issue_types" from "anon";

revoke trigger on table "public"."hr_emploc_issue_types" from "anon";

revoke truncate on table "public"."hr_emploc_issue_types" from "anon";

revoke update on table "public"."hr_emploc_issue_types" from "anon";

revoke delete on table "public"."hr_emploc_rejection_reasons" from "anon";

revoke insert on table "public"."hr_emploc_rejection_reasons" from "anon";

revoke references on table "public"."hr_emploc_rejection_reasons" from "anon";

revoke select on table "public"."hr_emploc_rejection_reasons" from "anon";

revoke trigger on table "public"."hr_emploc_rejection_reasons" from "anon";

revoke truncate on table "public"."hr_emploc_rejection_reasons" from "anon";

revoke update on table "public"."hr_emploc_rejection_reasons" from "anon";

revoke delete on table "public"."hr_emploc_store_links" from "anon";

revoke insert on table "public"."hr_emploc_store_links" from "anon";

revoke references on table "public"."hr_emploc_store_links" from "anon";

revoke select on table "public"."hr_emploc_store_links" from "anon";

revoke trigger on table "public"."hr_emploc_store_links" from "anon";

revoke truncate on table "public"."hr_emploc_store_links" from "anon";

revoke update on table "public"."hr_emploc_store_links" from "anon";

revoke delete on table "public"."login_sessions" from "anon";

revoke insert on table "public"."login_sessions" from "anon";

revoke references on table "public"."login_sessions" from "anon";

revoke select on table "public"."login_sessions" from "anon";

revoke trigger on table "public"."login_sessions" from "anon";

revoke truncate on table "public"."login_sessions" from "anon";

revoke update on table "public"."login_sessions" from "anon";

revoke delete on table "public"."mika_import_logs" from "anon";

revoke insert on table "public"."mika_import_logs" from "anon";

revoke references on table "public"."mika_import_logs" from "anon";

revoke select on table "public"."mika_import_logs" from "anon";

revoke trigger on table "public"."mika_import_logs" from "anon";

revoke truncate on table "public"."mika_import_logs" from "anon";

revoke update on table "public"."mika_import_logs" from "anon";

revoke delete on table "public"."mika_import_rows" from "anon";

revoke insert on table "public"."mika_import_rows" from "anon";

revoke references on table "public"."mika_import_rows" from "anon";

revoke select on table "public"."mika_import_rows" from "anon";

revoke trigger on table "public"."mika_import_rows" from "anon";

revoke truncate on table "public"."mika_import_rows" from "anon";

revoke update on table "public"."mika_import_rows" from "anon";

revoke delete on table "public"."notifications" from "anon";

revoke insert on table "public"."notifications" from "anon";

revoke references on table "public"."notifications" from "anon";

revoke select on table "public"."notifications" from "anon";

revoke trigger on table "public"."notifications" from "anon";

revoke truncate on table "public"."notifications" from "anon";

revoke update on table "public"."notifications" from "anon";

revoke delete on table "public"."plantilla" from "anon";

revoke insert on table "public"."plantilla" from "anon";

revoke references on table "public"."plantilla" from "anon";

revoke select on table "public"."plantilla" from "anon";

revoke trigger on table "public"."plantilla" from "anon";

revoke truncate on table "public"."plantilla" from "anon";

revoke update on table "public"."plantilla" from "anon";

revoke delete on table "public"."plantilla_approvals" from "anon";

revoke insert on table "public"."plantilla_approvals" from "anon";

revoke references on table "public"."plantilla_approvals" from "anon";

revoke select on table "public"."plantilla_approvals" from "anon";

revoke trigger on table "public"."plantilla_approvals" from "anon";

revoke truncate on table "public"."plantilla_approvals" from "anon";

revoke update on table "public"."plantilla_approvals" from "anon";

revoke delete on table "public"."plantilla_store_links" from "anon";

revoke insert on table "public"."plantilla_store_links" from "anon";

revoke references on table "public"."plantilla_store_links" from "anon";

revoke select on table "public"."plantilla_store_links" from "anon";

revoke trigger on table "public"."plantilla_store_links" from "anon";

revoke truncate on table "public"."plantilla_store_links" from "anon";

revoke update on table "public"."plantilla_store_links" from "anon";

revoke delete on table "public"."positions" from "anon";

revoke insert on table "public"."positions" from "anon";

revoke references on table "public"."positions" from "anon";

revoke select on table "public"."positions" from "anon";

revoke trigger on table "public"."positions" from "anon";

revoke truncate on table "public"."positions" from "anon";

revoke update on table "public"."positions" from "anon";

revoke delete on table "public"."possible_ghost_employees" from "anon";

revoke insert on table "public"."possible_ghost_employees" from "anon";

revoke references on table "public"."possible_ghost_employees" from "anon";

revoke select on table "public"."possible_ghost_employees" from "anon";

revoke trigger on table "public"."possible_ghost_employees" from "anon";

revoke truncate on table "public"."possible_ghost_employees" from "anon";

revoke update on table "public"."possible_ghost_employees" from "anon";

revoke delete on table "public"."qa_agent_evidence" from "anon";

revoke insert on table "public"."qa_agent_evidence" from "anon";

revoke references on table "public"."qa_agent_evidence" from "anon";

revoke select on table "public"."qa_agent_evidence" from "anon";

revoke trigger on table "public"."qa_agent_evidence" from "anon";

revoke truncate on table "public"."qa_agent_evidence" from "anon";

revoke update on table "public"."qa_agent_evidence" from "anon";

revoke delete on table "public"."qa_agent_findings" from "anon";

revoke insert on table "public"."qa_agent_findings" from "anon";

revoke references on table "public"."qa_agent_findings" from "anon";

revoke select on table "public"."qa_agent_findings" from "anon";

revoke trigger on table "public"."qa_agent_findings" from "anon";

revoke truncate on table "public"."qa_agent_findings" from "anon";

revoke update on table "public"."qa_agent_findings" from "anon";

revoke delete on table "public"."qa_agent_rules" from "anon";

revoke insert on table "public"."qa_agent_rules" from "anon";

revoke references on table "public"."qa_agent_rules" from "anon";

revoke select on table "public"."qa_agent_rules" from "anon";

revoke trigger on table "public"."qa_agent_rules" from "anon";

revoke truncate on table "public"."qa_agent_rules" from "anon";

revoke update on table "public"."qa_agent_rules" from "anon";

revoke delete on table "public"."qa_agent_runs" from "anon";

revoke insert on table "public"."qa_agent_runs" from "anon";

revoke references on table "public"."qa_agent_runs" from "anon";

revoke select on table "public"."qa_agent_runs" from "anon";

revoke trigger on table "public"."qa_agent_runs" from "anon";

revoke truncate on table "public"."qa_agent_runs" from "anon";

revoke update on table "public"."qa_agent_runs" from "anon";

revoke delete on table "public"."qa_daily_reports" from "anon";

revoke insert on table "public"."qa_daily_reports" from "anon";

revoke references on table "public"."qa_daily_reports" from "anon";

revoke select on table "public"."qa_daily_reports" from "anon";

revoke trigger on table "public"."qa_daily_reports" from "anon";

revoke truncate on table "public"."qa_daily_reports" from "anon";

revoke update on table "public"."qa_daily_reports" from "anon";

revoke delete on table "public"."qa_health_metrics" from "anon";

revoke insert on table "public"."qa_health_metrics" from "anon";

revoke references on table "public"."qa_health_metrics" from "anon";

revoke select on table "public"."qa_health_metrics" from "anon";

revoke trigger on table "public"."qa_health_metrics" from "anon";

revoke truncate on table "public"."qa_health_metrics" from "anon";

revoke update on table "public"."qa_health_metrics" from "anon";

revoke delete on table "public"."qa_notifications" from "anon";

revoke insert on table "public"."qa_notifications" from "anon";

revoke references on table "public"."qa_notifications" from "anon";

revoke select on table "public"."qa_notifications" from "anon";

revoke trigger on table "public"."qa_notifications" from "anon";

revoke truncate on table "public"."qa_notifications" from "anon";

revoke update on table "public"."qa_notifications" from "anon";

revoke delete on table "public"."qa_run_queue" from "anon";

revoke insert on table "public"."qa_run_queue" from "anon";

revoke references on table "public"."qa_run_queue" from "anon";

revoke select on table "public"."qa_run_queue" from "anon";

revoke trigger on table "public"."qa_run_queue" from "anon";

revoke truncate on table "public"."qa_run_queue" from "anon";

revoke update on table "public"."qa_run_queue" from "anon";

revoke delete on table "public"."qa_schedules" from "anon";

revoke insert on table "public"."qa_schedules" from "anon";

revoke references on table "public"."qa_schedules" from "anon";

revoke select on table "public"."qa_schedules" from "anon";

revoke trigger on table "public"."qa_schedules" from "anon";

revoke truncate on table "public"."qa_schedules" from "anon";

revoke update on table "public"."qa_schedules" from "anon";

revoke delete on table "public"."ref_locations" from "anon";

revoke insert on table "public"."ref_locations" from "anon";

revoke references on table "public"."ref_locations" from "anon";

revoke select on table "public"."ref_locations" from "anon";

revoke trigger on table "public"."ref_locations" from "anon";

revoke truncate on table "public"."ref_locations" from "anon";

revoke update on table "public"."ref_locations" from "anon";

revoke delete on table "public"."rejected_reasons" from "anon";

revoke insert on table "public"."rejected_reasons" from "anon";

revoke references on table "public"."rejected_reasons" from "anon";

revoke select on table "public"."rejected_reasons" from "anon";

revoke trigger on table "public"."rejected_reasons" from "anon";

revoke truncate on table "public"."rejected_reasons" from "anon";

revoke update on table "public"."rejected_reasons" from "anon";

revoke delete on table "public"."remote_tasks" from "anon";

revoke insert on table "public"."remote_tasks" from "anon";

revoke references on table "public"."remote_tasks" from "anon";

revoke select on table "public"."remote_tasks" from "anon";

revoke trigger on table "public"."remote_tasks" from "anon";

revoke truncate on table "public"."remote_tasks" from "anon";

revoke update on table "public"."remote_tasks" from "anon";

revoke delete on table "public"."roles" from "anon";

revoke insert on table "public"."roles" from "anon";

revoke references on table "public"."roles" from "anon";

revoke select on table "public"."roles" from "anon";

revoke trigger on table "public"."roles" from "anon";

revoke truncate on table "public"."roles" from "anon";

revoke update on table "public"."roles" from "anon";

revoke delete on table "public"."roving_assignments" from "anon";

revoke insert on table "public"."roving_assignments" from "anon";

revoke references on table "public"."roving_assignments" from "anon";

revoke select on table "public"."roving_assignments" from "anon";

revoke trigger on table "public"."roving_assignments" from "anon";

revoke truncate on table "public"."roving_assignments" from "anon";

revoke update on table "public"."roving_assignments" from "anon";

revoke delete on table "public"."security_events" from "anon";

revoke insert on table "public"."security_events" from "anon";

revoke references on table "public"."security_events" from "anon";

revoke select on table "public"."security_events" from "anon";

revoke trigger on table "public"."security_events" from "anon";

revoke truncate on table "public"."security_events" from "anon";

revoke update on table "public"."security_events" from "anon";

revoke delete on table "public"."sla_breach_logs" from "anon";

revoke insert on table "public"."sla_breach_logs" from "anon";

revoke references on table "public"."sla_breach_logs" from "anon";

revoke select on table "public"."sla_breach_logs" from "anon";

revoke trigger on table "public"."sla_breach_logs" from "anon";

revoke truncate on table "public"."sla_breach_logs" from "anon";

revoke update on table "public"."sla_breach_logs" from "anon";

revoke delete on table "public"."staging_imports" from "anon";

revoke insert on table "public"."staging_imports" from "anon";

revoke references on table "public"."staging_imports" from "anon";

revoke select on table "public"."staging_imports" from "anon";

revoke trigger on table "public"."staging_imports" from "anon";

revoke truncate on table "public"."staging_imports" from "anon";

revoke update on table "public"."staging_imports" from "anon";

revoke delete on table "public"."store_import_batches" from "anon";

revoke insert on table "public"."store_import_batches" from "anon";

revoke references on table "public"."store_import_batches" from "anon";

revoke select on table "public"."store_import_batches" from "anon";

revoke trigger on table "public"."store_import_batches" from "anon";

revoke truncate on table "public"."store_import_batches" from "anon";

revoke update on table "public"."store_import_batches" from "anon";

revoke delete on table "public"."store_import_rows" from "anon";

revoke insert on table "public"."store_import_rows" from "anon";

revoke references on table "public"."store_import_rows" from "anon";

revoke select on table "public"."store_import_rows" from "anon";

revoke trigger on table "public"."store_import_rows" from "anon";

revoke truncate on table "public"."store_import_rows" from "anon";

revoke update on table "public"."store_import_rows" from "anon";

revoke delete on table "public"."stores" from "anon";

revoke insert on table "public"."stores" from "anon";

revoke references on table "public"."stores" from "anon";

revoke select on table "public"."stores" from "anon";

revoke trigger on table "public"."stores" from "anon";

revoke truncate on table "public"."stores" from "anon";

revoke update on table "public"."stores" from "anon";

revoke delete on table "public"."temp_approval_access" from "anon";

revoke insert on table "public"."temp_approval_access" from "anon";

revoke references on table "public"."temp_approval_access" from "anon";

revoke select on table "public"."temp_approval_access" from "anon";

revoke trigger on table "public"."temp_approval_access" from "anon";

revoke truncate on table "public"."temp_approval_access" from "anon";

revoke update on table "public"."temp_approval_access" from "anon";

revoke delete on table "public"."temp_permission_overrides" from "anon";

revoke insert on table "public"."temp_permission_overrides" from "anon";

revoke references on table "public"."temp_permission_overrides" from "anon";

revoke select on table "public"."temp_permission_overrides" from "anon";

revoke trigger on table "public"."temp_permission_overrides" from "anon";

revoke truncate on table "public"."temp_permission_overrides" from "anon";

revoke update on table "public"."temp_permission_overrides" from "anon";

revoke delete on table "public"."user_account_transfers" from "anon";

revoke insert on table "public"."user_account_transfers" from "anon";

revoke references on table "public"."user_account_transfers" from "anon";

revoke select on table "public"."user_account_transfers" from "anon";

revoke trigger on table "public"."user_account_transfers" from "anon";

revoke truncate on table "public"."user_account_transfers" from "anon";

revoke update on table "public"."user_account_transfers" from "anon";

revoke delete on table "public"."user_scopes" from "anon";

revoke insert on table "public"."user_scopes" from "anon";

revoke references on table "public"."user_scopes" from "anon";

revoke select on table "public"."user_scopes" from "anon";

revoke trigger on table "public"."user_scopes" from "anon";

revoke truncate on table "public"."user_scopes" from "anon";

revoke update on table "public"."user_scopes" from "anon";

revoke delete on table "public"."users_profile" from "anon";

revoke insert on table "public"."users_profile" from "anon";

revoke references on table "public"."users_profile" from "anon";

revoke select on table "public"."users_profile" from "anon";

revoke trigger on table "public"."users_profile" from "anon";

revoke truncate on table "public"."users_profile" from "anon";

revoke update on table "public"."users_profile" from "anon";

revoke delete on table "public"."vacancies" from "anon";

revoke insert on table "public"."vacancies" from "anon";

revoke references on table "public"."vacancies" from "anon";

revoke select on table "public"."vacancies" from "anon";

revoke trigger on table "public"."vacancies" from "anon";

revoke truncate on table "public"."vacancies" from "anon";

revoke update on table "public"."vacancies" from "anon";

revoke delete on table "public"."vacancy_closure_reasons" from "anon";

revoke insert on table "public"."vacancy_closure_reasons" from "anon";

revoke references on table "public"."vacancy_closure_reasons" from "anon";

revoke select on table "public"."vacancy_closure_reasons" from "anon";

revoke trigger on table "public"."vacancy_closure_reasons" from "anon";

revoke truncate on table "public"."vacancy_closure_reasons" from "anon";

revoke update on table "public"."vacancy_closure_reasons" from "anon";

revoke delete on table "public"."vacancy_closure_requests" from "anon";

revoke insert on table "public"."vacancy_closure_requests" from "anon";

revoke references on table "public"."vacancy_closure_requests" from "anon";

revoke select on table "public"."vacancy_closure_requests" from "anon";

revoke trigger on table "public"."vacancy_closure_requests" from "anon";

revoke truncate on table "public"."vacancy_closure_requests" from "anon";

revoke update on table "public"."vacancy_closure_requests" from "anon";

revoke delete on table "public"."vacancy_coverage" from "anon";

revoke insert on table "public"."vacancy_coverage" from "anon";

revoke references on table "public"."vacancy_coverage" from "anon";

revoke select on table "public"."vacancy_coverage" from "anon";

revoke trigger on table "public"."vacancy_coverage" from "anon";

revoke truncate on table "public"."vacancy_coverage" from "anon";

revoke update on table "public"."vacancy_coverage" from "anon";

revoke delete on table "public"."vacancy_requests" from "anon";

revoke insert on table "public"."vacancy_requests" from "anon";

revoke references on table "public"."vacancy_requests" from "anon";

revoke select on table "public"."vacancy_requests" from "anon";

revoke trigger on table "public"."vacancy_requests" from "anon";

revoke truncate on table "public"."vacancy_requests" from "anon";

revoke update on table "public"."vacancy_requests" from "anon";

revoke delete on table "public"."vcode_sequences" from "anon";

revoke insert on table "public"."vcode_sequences" from "anon";

revoke references on table "public"."vcode_sequences" from "anon";

revoke select on table "public"."vcode_sequences" from "anon";

revoke trigger on table "public"."vcode_sequences" from "anon";

revoke truncate on table "public"."vcode_sequences" from "anon";

revoke update on table "public"."vcode_sequences" from "anon";

revoke delete on table "public"."vcodes" from "anon";

revoke insert on table "public"."vcodes" from "anon";

revoke references on table "public"."vcodes" from "anon";

revoke select on table "public"."vcodes" from "anon";

revoke trigger on table "public"."vcodes" from "anon";

revoke truncate on table "public"."vcodes" from "anon";

revoke update on table "public"."vcodes" from "anon";

revoke delete on table "public"."workforce_assignment_requests" from "anon";

revoke insert on table "public"."workforce_assignment_requests" from "anon";

revoke references on table "public"."workforce_assignment_requests" from "anon";

revoke select on table "public"."workforce_assignment_requests" from "anon";

revoke trigger on table "public"."workforce_assignment_requests" from "anon";

revoke truncate on table "public"."workforce_assignment_requests" from "anon";

revoke update on table "public"."workforce_assignment_requests" from "anon";

revoke delete on table "public"."workforce_assignments" from "anon";

revoke insert on table "public"."workforce_assignments" from "anon";

revoke references on table "public"."workforce_assignments" from "anon";

revoke select on table "public"."workforce_assignments" from "anon";

revoke trigger on table "public"."workforce_assignments" from "anon";

revoke truncate on table "public"."workforce_assignments" from "anon";

revoke update on table "public"."workforce_assignments" from "anon";

revoke delete on table "public"."workforce_pool_conversion_requests" from "anon";

revoke insert on table "public"."workforce_pool_conversion_requests" from "anon";

revoke references on table "public"."workforce_pool_conversion_requests" from "anon";

revoke select on table "public"."workforce_pool_conversion_requests" from "anon";

revoke trigger on table "public"."workforce_pool_conversion_requests" from "anon";

revoke truncate on table "public"."workforce_pool_conversion_requests" from "anon";

revoke update on table "public"."workforce_pool_conversion_requests" from "anon";

revoke delete on table "public"."workforce_pool_request_items" from "anon";

revoke insert on table "public"."workforce_pool_request_items" from "anon";

revoke references on table "public"."workforce_pool_request_items" from "anon";

revoke select on table "public"."workforce_pool_request_items" from "anon";

revoke trigger on table "public"."workforce_pool_request_items" from "anon";

revoke truncate on table "public"."workforce_pool_request_items" from "anon";

revoke update on table "public"."workforce_pool_request_items" from "anon";

revoke delete on table "public"."workforce_pool_requests" from "anon";

revoke insert on table "public"."workforce_pool_requests" from "anon";

revoke references on table "public"."workforce_pool_requests" from "anon";

revoke select on table "public"."workforce_pool_requests" from "anon";

revoke trigger on table "public"."workforce_pool_requests" from "anon";

revoke truncate on table "public"."workforce_pool_requests" from "anon";

revoke update on table "public"."workforce_pool_requests" from "anon";

revoke delete on table "public"."workforce_pool_slots" from "anon";

revoke insert on table "public"."workforce_pool_slots" from "anon";

revoke references on table "public"."workforce_pool_slots" from "anon";

revoke select on table "public"."workforce_pool_slots" from "anon";

revoke trigger on table "public"."workforce_pool_slots" from "anon";

revoke truncate on table "public"."workforce_pool_slots" from "anon";

revoke update on table "public"."workforce_pool_slots" from "anon";

revoke delete on table "public"."workforce_pool_types" from "anon";

revoke insert on table "public"."workforce_pool_types" from "anon";

revoke references on table "public"."workforce_pool_types" from "anon";

revoke select on table "public"."workforce_pool_types" from "anon";

revoke trigger on table "public"."workforce_pool_types" from "anon";

revoke truncate on table "public"."workforce_pool_types" from "anon";

revoke update on table "public"."workforce_pool_types" from "anon";

revoke delete on table "public"."workforce_pool_vcode_sequences" from "anon";

revoke insert on table "public"."workforce_pool_vcode_sequences" from "anon";

revoke references on table "public"."workforce_pool_vcode_sequences" from "anon";

revoke select on table "public"."workforce_pool_vcode_sequences" from "anon";

revoke trigger on table "public"."workforce_pool_vcode_sequences" from "anon";

revoke truncate on table "public"."workforce_pool_vcode_sequences" from "anon";

revoke update on table "public"."workforce_pool_vcode_sequences" from "anon";

revoke delete on table "public"."workforce_slot_reviews" from "anon";

revoke insert on table "public"."workforce_slot_reviews" from "anon";

revoke references on table "public"."workforce_slot_reviews" from "anon";

revoke select on table "public"."workforce_slot_reviews" from "anon";

revoke trigger on table "public"."workforce_slot_reviews" from "anon";

revoke truncate on table "public"."workforce_slot_reviews" from "anon";

revoke update on table "public"."workforce_slot_reviews" from "anon";

alter table "public"."account_positions" drop constraint "account_positions_account_id_fkey";

alter table "public"."account_positions" drop constraint "account_positions_position_id_fkey";

alter table "public"."account_request_account_scopes" drop constraint "account_request_account_scopes_account_id_fkey";

alter table "public"."account_request_account_scopes" drop constraint "account_request_account_scopes_account_request_id_fkey";

alter table "public"."account_request_group_scopes" drop constraint "account_request_group_scopes_account_request_id_fkey";

alter table "public"."account_request_group_scopes" drop constraint "account_request_group_scopes_group_id_fkey";

alter table "public"."account_requests" drop constraint "account_requests_requested_role_id_fkey";

alter table "public"."accounts" drop constraint "accounts_group_id_fkey";

alter table "public"."accounts" drop constraint "accounts_hrco_user_id_fkey";

alter table "public"."activity_log" drop constraint "activity_log_actor_id_fkey";

alter table "public"."applicant_profile_change_history" drop constraint "applicant_profile_change_history_applicant_id_fkey";

alter table "public"."applicant_profile_change_history" drop constraint "applicant_profile_change_history_approved_by_fkey";

alter table "public"."applicant_profile_change_history" drop constraint "applicant_profile_change_history_changed_by_fkey";

alter table "public"."applicant_profile_change_history" drop constraint "applicant_profile_change_history_request_id_fkey";

alter table "public"."applicant_profile_edit_requests" drop constraint "applicant_profile_edit_requests_applicant_id_fkey";

alter table "public"."applicant_profile_edit_requests" drop constraint "applicant_profile_edit_requests_requested_by_fkey";

alter table "public"."applicant_profile_edit_requests" drop constraint "applicant_profile_edit_requests_reviewed_by_fkey";

alter table "public"."applicant_status_history" drop constraint "applicant_status_history_applicant_id_fkey";

alter table "public"."applicant_status_history" drop constraint "applicant_status_history_changed_by_fkey";

alter table "public"."applicants" drop constraint "applicants_hired_by_user_id_fkey";

alter table "public"."applicants" drop constraint "applicants_recruited_by_user_id_fkey";

alter table "public"."applicants" drop constraint "applicants_roving_assignment_id_fkey";

alter table "public"."applicants" drop constraint "fk_applicants_vacancy_vcode";

alter table "public"."bulk_emploc_items" drop constraint "bulk_emploc_items_upload_id_fkey";

alter table "public"."bulk_emploc_uploads" drop constraint "bulk_emploc_uploads_uploaded_by_user_id_fkey";

alter table "public"."cencom_weekly_snapshots" drop constraint "cencom_weekly_snapshots_group_id_fkey";

alter table "public"."deactivation_audit_log" drop constraint "deactivation_audit_log_request_id_fkey";

alter table "public"."deactivation_items" drop constraint "deactivation_items_plantilla_id_fkey";

alter table "public"."deactivation_items" drop constraint "deactivation_items_request_id_fkey";

alter table "public"."employee_deployments" drop constraint "employee_deployments_employee_id_fkey";

alter table "public"."employee_deployments" drop constraint "employee_deployments_vcode_fkey";

alter table "public"."headcount_requests" drop constraint "headcount_requests_account_id_fkey";

alter table "public"."headcount_requests" drop constraint "headcount_requests_created_plantilla_id_fkey";

alter table "public"."headcount_requests" drop constraint "headcount_requests_group_id_fkey";

alter table "public"."headcount_requests" drop constraint "headcount_requests_position_id_fkey";

alter table "public"."headcount_requests" drop constraint "headcount_requests_requested_by_user_id_fkey";

alter table "public"."headcount_requests" drop constraint "headcount_requests_reviewed_by_user_id_fkey";

alter table "public"."headcount_requests" drop constraint "headcount_requests_slot_created_by_user_id_fkey";

alter table "public"."headcount_requests" drop constraint "headcount_requests_store_id_fkey";

alter table "public"."hr_emploc" drop constraint "fk_hr_emploc_vcode";

alter table "public"."hr_emploc" drop constraint "hr_emploc_account_id_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_applicant_id_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_assignment_type_consistency_chk";

alter table "public"."hr_emploc" drop constraint "hr_emploc_backout_by_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_deployer_id_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_hr_personnel_user_id_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_hr_reviewed_by_user_id_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_position_id_snapshot_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_roving_assignment_id_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_vacancy_id_fkey";

alter table "public"."hr_emploc_correction_attachments" drop constraint "hr_emploc_correction_attachments_hr_emploc_id_fkey";

alter table "public"."hr_emploc_correction_attachments" drop constraint "hr_emploc_correction_attachments_uploaded_by_fkey";

alter table "public"."hr_emploc_deletion_activities" drop constraint "hr_emploc_deletion_activities_request_fkey";

alter table "public"."hr_emploc_deletion_requests" drop constraint "hr_emploc_deletion_requests_hr_emploc_id_fkey";

alter table "public"."hr_emploc_deletion_requests" drop constraint "hr_emploc_deletion_requests_original_emploc_id_fkey";

alter table "public"."hr_emploc_store_links" drop constraint "hr_emploc_store_links_backed_out_by_fkey";

alter table "public"."hr_emploc_store_links" drop constraint "hr_emploc_store_links_confirmed_by_fkey";

alter table "public"."hr_emploc_store_links" drop constraint "hr_emploc_store_links_created_by_fkey";

alter table "public"."hr_emploc_store_links" drop constraint "hr_emploc_store_links_hr_emploc_id_fkey";

alter table "public"."hr_emploc_store_links" drop constraint "hr_emploc_store_links_resigned_by_fkey";

alter table "public"."hr_emploc_store_links" drop constraint "hr_emploc_store_links_roving_assignment_id_fkey";

alter table "public"."hr_emploc_store_links" drop constraint "hr_emploc_store_links_updated_by_fkey";

alter table "public"."hr_emploc_store_links" drop constraint "hr_emploc_store_links_vacancy_id_fkey";

alter table "public"."login_sessions" drop constraint "login_sessions_user_id_fkey";

alter table "public"."mika_import_rows" drop constraint "mika_import_rows_import_log_id_fkey";

alter table "public"."plantilla" drop constraint "fk_plantilla_vcode";

alter table "public"."plantilla" drop constraint "plantilla_account_id_fkey";

alter table "public"."plantilla" drop constraint "plantilla_deactivated_by_fkey";

alter table "public"."plantilla" drop constraint "plantilla_for_deactivation_by_fkey";

alter table "public"."plantilla" drop constraint "plantilla_hr_emploc_id_fkey";

alter table "public"."plantilla" drop constraint "plantilla_inactive_by_fkey";

alter table "public"."plantilla" drop constraint "plantilla_position_id_fkey";

alter table "public"."plantilla" drop constraint "plantilla_roving_assignment_id_fkey";

alter table "public"."plantilla" drop constraint "plantilla_source_headcount_request_fk";

alter table "public"."plantilla" drop constraint "plantilla_vacancy_id_fkey";

alter table "public"."plantilla_store_links" drop constraint "plantilla_store_links_created_by_fkey";

alter table "public"."plantilla_store_links" drop constraint "plantilla_store_links_hr_emploc_store_link_id_fkey";

alter table "public"."plantilla_store_links" drop constraint "plantilla_store_links_linked_by_fkey";

alter table "public"."plantilla_store_links" drop constraint "plantilla_store_links_plantilla_id_fkey";

alter table "public"."plantilla_store_links" drop constraint "plantilla_store_links_roving_assignment_id_fkey";

alter table "public"."plantilla_store_links" drop constraint "plantilla_store_links_unlinked_by_fkey";

alter table "public"."plantilla_store_links" drop constraint "plantilla_store_links_updated_by_fkey";

alter table "public"."plantilla_store_links" drop constraint "plantilla_store_links_vacancy_id_fkey";

alter table "public"."positions" drop constraint "positions_accounts_id_fkey";

alter table "public"."positions" drop constraint "positions_group_id_fkey";

alter table "public"."possible_ghost_employees" drop constraint "possible_ghost_employees_assigned_encoder_id_fkey";

alter table "public"."possible_ghost_employees" drop constraint "possible_ghost_employees_import_log_id_fkey";

alter table "public"."possible_ghost_employees" drop constraint "possible_ghost_employees_resolved_by_user_id_fkey";

alter table "public"."qa_agent_evidence" drop constraint "qa_agent_evidence_created_by_fkey";

alter table "public"."qa_agent_evidence" drop constraint "qa_agent_evidence_finding_id_fkey";

alter table "public"."qa_agent_findings" drop constraint "qa_agent_findings_assigned_to_fkey";

alter table "public"."qa_agent_findings" drop constraint "qa_agent_findings_resolved_by_fkey";

alter table "public"."qa_agent_findings" drop constraint "qa_agent_findings_run_id_fkey";

alter table "public"."qa_agent_rules" drop constraint "qa_agent_rules_created_by_fkey";

alter table "public"."qa_agent_rules" drop constraint "qa_agent_rules_updated_by_fkey";

alter table "public"."qa_agent_runs" drop constraint "qa_agent_runs_initiated_by_fkey";

alter table "public"."qa_daily_reports" drop constraint "qa_daily_reports_generated_by_fkey";

alter table "public"."qa_run_queue" drop constraint "qa_run_queue_run_id_fkey";

alter table "public"."qa_run_queue" drop constraint "qa_run_queue_schedule_id_fkey";

alter table "public"."qa_schedules" drop constraint "qa_schedules_created_by_fkey";

alter table "public"."qa_schedules" drop constraint "qa_schedules_updated_by_fkey";

alter table "public"."roving_assignments" drop constraint "roving_assignments_account_id_fkey";

alter table "public"."roving_assignments" drop constraint "roving_assignments_master_applicant_id_fkey";

alter table "public"."sla_breach_logs" drop constraint "sla_breach_logs_plantilla_id_fkey";

alter table "public"."staging_imports" drop constraint "staging_imports_approved_by_fkey";

alter table "public"."staging_imports" drop constraint "staging_imports_created_by_fkey";

alter table "public"."staging_imports" drop constraint "staging_imports_validated_by_fkey";

alter table "public"."store_import_batches" drop constraint "store_import_batches_selected_account_id_fkey";

alter table "public"."store_import_batches" drop constraint "store_import_batches_selected_group_id_fkey";

alter table "public"."store_import_rows" drop constraint "store_import_rows_batch_id_fkey";

alter table "public"."stores" drop constraint "stores_account_id_fkey";

alter table "public"."stores" drop constraint "stores_group_id_fkey";

alter table "public"."stores" drop constraint "stores_hrco_user_id_fkey";

alter table "public"."stores" drop constraint "stores_om_user_id_fkey";

alter table "public"."temp_approval_access" drop constraint "temp_approval_access_granted_by_fkey";

alter table "public"."temp_approval_access" drop constraint "temp_approval_access_granted_to_fkey";

alter table "public"."temp_permission_overrides" drop constraint "temp_permission_overrides_user_id_fkey";

alter table "public"."user_account_transfers" drop constraint "user_account_transfers_transferred_by_fkey";

alter table "public"."user_account_transfers" drop constraint "user_account_transfers_user_profile_id_fkey";

alter table "public"."user_scopes" drop constraint "user_scopes_account_id_fkey";

alter table "public"."user_scopes" drop constraint "user_scopes_group_id_fkey";

alter table "public"."user_scopes" drop constraint "user_scopes_user_id_fkey";

alter table "public"."users_profile" drop constraint "fk_users_profile_group";

alter table "public"."users_profile" drop constraint "users_profile_account_id_fkey";

alter table "public"."users_profile" drop constraint "users_profile_role_id_fkey";

alter table "public"."vacancies" drop constraint "fk_vacancies_store_id";

alter table "public"."vacancies" drop constraint "vacancies_account_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_assigned_encoder_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_home_account_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_pool_request_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_pool_type_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_position_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_source_headcount_request_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_source_plantilla_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_source_vacancy_request_id_fkey";

alter table "public"."vacancies" drop constraint "vacancies_triggered_by_user_id_fkey";

alter table "public"."vacancy_closure_requests" drop constraint "vacancy_closure_requests_reason_id_fkey";

alter table "public"."vacancy_closure_requests" drop constraint "vacancy_closure_requests_requested_by_user_id_fkey";

alter table "public"."vacancy_closure_requests" drop constraint "vacancy_closure_requests_vacancy_vcode_fkey";

alter table "public"."vacancy_closure_requests" drop constraint "vacancy_closure_requests_withdrawn_by_user_id_fkey";

alter table "public"."vacancy_coverage" drop constraint "vacancy_coverage_account_id_fkey";

alter table "public"."vacancy_coverage" drop constraint "vacancy_coverage_applicant_id_fkey";

alter table "public"."vacancy_coverage" drop constraint "vacancy_coverage_hr_emploc_id_fkey";

alter table "public"."vacancy_coverage" drop constraint "vacancy_coverage_vacancy_id_fkey";

alter table "public"."vacancy_requests" drop constraint "vacancy_requests_assigned_encoder_id_fkey";

alter table "public"."vacancy_requests" drop constraint "vacancy_requests_requested_by_user_id_fkey";

alter table "public"."vcodes" drop constraint "vcodes_vacancy_request_id_fkey";

alter table "public"."workforce_assignment_requests" drop constraint "workforce_assignment_requests_converted_assignment_id_fkey";

alter table "public"."workforce_assignment_requests" drop constraint "workforce_assignment_requests_employee_id_fkey";

alter table "public"."workforce_assignment_requests" drop constraint "workforce_assignment_requests_pool_type_id_fkey";

alter table "public"."workforce_assignment_requests" drop constraint "workforce_assignment_requests_requested_account_id_fkey";

alter table "public"."workforce_assignment_requests" drop constraint "workforce_assignment_requests_requested_group_id_fkey";

alter table "public"."workforce_assignment_requests" drop constraint "workforce_assignment_requests_requested_store_id_fkey";

alter table "public"."workforce_assignments" drop constraint "workforce_assignments_assigned_account_id_fkey";

alter table "public"."workforce_assignments" drop constraint "workforce_assignments_assigned_group_id_fkey";

alter table "public"."workforce_assignments" drop constraint "workforce_assignments_assigned_store_id_fkey";

alter table "public"."workforce_assignments" drop constraint "workforce_assignments_employee_id_fkey";

alter table "public"."workforce_assignments" drop constraint "workforce_assignments_pool_type_id_fkey";

alter table "public"."workforce_pool_conversion_requests" drop constraint "workforce_pool_conversion_requests_employee_id_fkey";

alter table "public"."workforce_pool_conversion_requests" drop constraint "workforce_pool_conversion_requests_pool_slot_id_fkey";

alter table "public"."workforce_pool_conversion_requests" drop constraint "workforce_pool_conversion_requests_pool_type_id_fkey";

alter table "public"."workforce_pool_conversion_requests" drop constraint "workforce_pool_conversion_requests_slot_review_id_fkey";

alter table "public"."workforce_pool_conversion_requests" drop constraint "workforce_pool_conversion_requests_target_account_id_fkey";

alter table "public"."workforce_pool_conversion_requests" drop constraint "workforce_pool_conversion_requests_target_store_id_fkey";

alter table "public"."workforce_pool_request_items" drop constraint "workforce_pool_request_items_position_id_fkey";

alter table "public"."workforce_pool_request_items" drop constraint "workforce_pool_request_items_request_id_fkey";

alter table "public"."workforce_pool_request_items" drop constraint "workforce_pool_request_items_vacancy_id_fkey";

alter table "public"."workforce_pool_requests" drop constraint "workforce_pool_requests_pool_type_id_fkey";

alter table "public"."workforce_pool_requests" drop constraint "workforce_pool_requests_requesting_account_id_fkey";

alter table "public"."workforce_pool_requests" drop constraint "workforce_pool_requests_requesting_store_id_fkey";

alter table "public"."workforce_pool_slots" drop constraint "workforce_pool_slots_account_id_fkey";

alter table "public"."workforce_pool_slots" drop constraint "workforce_pool_slots_group_id_fkey";

alter table "public"."workforce_pool_slots" drop constraint "workforce_pool_slots_pool_type_id_fkey";

alter table "public"."workforce_pool_slots" drop constraint "workforce_pool_slots_vacancy_id_fkey";

alter table "public"."workforce_slot_reviews" drop constraint "workforce_slot_reviews_pool_type_id_fkey";

alter table "public"."workforce_slot_reviews" drop constraint "workforce_slot_reviews_vacancy_id_fkey";

drop function if exists "public"."get_approval_queue"(p_status account_request_status);

drop view if exists "public"."headcount_summary";

drop view if exists "public"."own_performance_view";

drop view if exists "public"."team_performance_view";

drop view if exists "public"."v_approval_queue";

drop view if exists "public"."v_audit_activity_feed";

drop view if exists "public"."v_cencom_group_kpi";

drop view if exists "public"."v_cencom_kpi";

drop view if exists "public"."v_cencom_td_by_account";

drop view if exists "public"."v_cencom_td_by_group";

drop view if exists "public"."v_cencom_td_priority_queue";

drop view if exists "public"."v_cencom_td_summary";

drop view if exists "public"."v_cencom_td_vacancies";

drop view if exists "public"."v_group_kpi";

drop view if exists "public"."v_hr_emploc_backout_report";

drop view if exists "public"."v_hr_emploc_sla_flags";

drop view if exists "public"."v_vacancy_active_coverage";

drop view if exists "public"."view_archived_records";

drop view if exists "public"."vw_monthly_hires";

drop view if exists "public"."vw_ready_to_plantilla";

drop view if exists "public"."vw_rejected_emploc_active";

drop view if exists "public"."vw_sla_by_group";

drop view if exists "public"."v_cencom_account_kpi";

drop view if exists "public"."v_account_kpi";

drop index if exists "public"."idx_deployer_name_trgm";

drop index if exists "public"."uq_account_requests_email_pending";

drop index if exists "public"."uq_applicants_one_active_per_vcode";

drop index if exists "public"."uq_hr_emploc_roving_assignment";

drop index if exists "public"."uq_hr_emploc_stationary_applicant_vacancy";

drop index if exists "public"."uq_vacancy_coverage_active_per_vacancy";

alter table "public"."account_requests" alter column "status" set default 'pending'::public.account_request_status;

alter table "public"."account_requests" alter column "status" set data type public.account_request_status using "status"::text::public.account_request_status;

alter table "public"."audit_logs" alter column "action" set data type public.audit_action using "action"::text::public.audit_action;

alter table "public"."hr_emploc" alter column "assignment_type" set default 'Stationary'::public.hr_emploc_assignment_type;

alter table "public"."hr_emploc" alter column "assignment_type" set data type public.hr_emploc_assignment_type using "assignment_type"::text::public.hr_emploc_assignment_type;

alter table "public"."remote_tasks" alter column "id" set default nextval('public.remote_tasks_id_seq'::regclass);

alter table "public"."staging_imports" alter column "import_type" set data type public.staging_import_type using "import_type"::text::public.staging_import_type;

alter table "public"."staging_imports" alter column "status" set default 'pending_validation'::public.staging_import_status;

alter table "public"."staging_imports" alter column "status" set data type public.staging_import_status using "status"::text::public.staging_import_status;

alter table "public"."vacancy_coverage" alter column "coverage_type" set data type public.vacancy_coverage_type using "coverage_type"::text::public.vacancy_coverage_type;

alter table "public"."vacancy_coverage" alter column "status" set default 'Active'::public.vacancy_coverage_status;

alter table "public"."vacancy_coverage" alter column "status" set data type public.vacancy_coverage_status using "status"::text::public.vacancy_coverage_status;

CREATE INDEX idx_deployer_name_trgm ON public.deployer USING gin (name extensions.gin_trgm_ops);

CREATE UNIQUE INDEX uq_account_requests_email_pending ON public.account_requests USING btree (lower(email)) WHERE (status = 'pending'::public.account_request_status);

CREATE UNIQUE INDEX uq_applicants_one_active_per_vcode ON public.applicants USING btree (vacancy_vcode) WHERE ((COALESCE(is_archived, false) = false) AND public.fn_is_active_vacancy_applicant_status(status));

CREATE UNIQUE INDEX uq_hr_emploc_roving_assignment ON public.hr_emploc USING btree (roving_assignment_id) WHERE ((assignment_type = 'Roving'::public.hr_emploc_assignment_type) AND (deleted_at IS NULL) AND (roving_assignment_id IS NOT NULL));

CREATE UNIQUE INDEX uq_hr_emploc_stationary_applicant_vacancy ON public.hr_emploc USING btree (applicant_id, vacancy_id) WHERE ((assignment_type = 'Stationary'::public.hr_emploc_assignment_type) AND (deleted_at IS NULL) AND (applicant_id IS NOT NULL) AND (vacancy_id IS NOT NULL));

CREATE UNIQUE INDEX uq_vacancy_coverage_active_per_vacancy ON public.vacancy_coverage USING btree (vacancy_id) WHERE ((status = 'Active'::public.vacancy_coverage_status) AND (archived_at IS NULL));

alter table "public"."account_positions" add constraint "account_positions_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."account_positions" validate constraint "account_positions_account_id_fkey";

alter table "public"."account_positions" add constraint "account_positions_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) ON DELETE CASCADE not valid;

alter table "public"."account_positions" validate constraint "account_positions_position_id_fkey";

alter table "public"."account_request_account_scopes" add constraint "account_request_account_scopes_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."account_request_account_scopes" validate constraint "account_request_account_scopes_account_id_fkey";

alter table "public"."account_request_account_scopes" add constraint "account_request_account_scopes_account_request_id_fkey" FOREIGN KEY (account_request_id) REFERENCES public.account_requests(id) ON DELETE CASCADE not valid;

alter table "public"."account_request_account_scopes" validate constraint "account_request_account_scopes_account_request_id_fkey";

alter table "public"."account_request_group_scopes" add constraint "account_request_group_scopes_account_request_id_fkey" FOREIGN KEY (account_request_id) REFERENCES public.account_requests(id) ON DELETE CASCADE not valid;

alter table "public"."account_request_group_scopes" validate constraint "account_request_group_scopes_account_request_id_fkey";

alter table "public"."account_request_group_scopes" add constraint "account_request_group_scopes_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE not valid;

alter table "public"."account_request_group_scopes" validate constraint "account_request_group_scopes_group_id_fkey";

alter table "public"."account_requests" add constraint "account_requests_requested_role_id_fkey" FOREIGN KEY (requested_role_id) REFERENCES public.roles(id) not valid;

alter table "public"."account_requests" validate constraint "account_requests_requested_role_id_fkey";

alter table "public"."accounts" add constraint "accounts_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE not valid;

alter table "public"."accounts" validate constraint "accounts_group_id_fkey";

alter table "public"."accounts" add constraint "accounts_hrco_user_id_fkey" FOREIGN KEY (hrco_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."accounts" validate constraint "accounts_hrco_user_id_fkey";

alter table "public"."activity_log" add constraint "activity_log_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES public.users_profile(id) ON DELETE SET NULL not valid;

alter table "public"."activity_log" validate constraint "activity_log_actor_id_fkey";

alter table "public"."applicant_profile_change_history" add constraint "applicant_profile_change_history_applicant_id_fkey" FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) ON DELETE CASCADE not valid;

alter table "public"."applicant_profile_change_history" validate constraint "applicant_profile_change_history_applicant_id_fkey";

alter table "public"."applicant_profile_change_history" add constraint "applicant_profile_change_history_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicant_profile_change_history" validate constraint "applicant_profile_change_history_approved_by_fkey";

alter table "public"."applicant_profile_change_history" add constraint "applicant_profile_change_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicant_profile_change_history" validate constraint "applicant_profile_change_history_changed_by_fkey";

alter table "public"."applicant_profile_change_history" add constraint "applicant_profile_change_history_request_id_fkey" FOREIGN KEY (request_id) REFERENCES public.applicant_profile_edit_requests(id) not valid;

alter table "public"."applicant_profile_change_history" validate constraint "applicant_profile_change_history_request_id_fkey";

alter table "public"."applicant_profile_edit_requests" add constraint "applicant_profile_edit_requests_applicant_id_fkey" FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) ON DELETE CASCADE not valid;

alter table "public"."applicant_profile_edit_requests" validate constraint "applicant_profile_edit_requests_applicant_id_fkey";

alter table "public"."applicant_profile_edit_requests" add constraint "applicant_profile_edit_requests_requested_by_fkey" FOREIGN KEY (requested_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicant_profile_edit_requests" validate constraint "applicant_profile_edit_requests_requested_by_fkey";

alter table "public"."applicant_profile_edit_requests" add constraint "applicant_profile_edit_requests_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicant_profile_edit_requests" validate constraint "applicant_profile_edit_requests_reviewed_by_fkey";

alter table "public"."applicant_status_history" add constraint "applicant_status_history_applicant_id_fkey" FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) ON DELETE CASCADE not valid;

alter table "public"."applicant_status_history" validate constraint "applicant_status_history_applicant_id_fkey";

alter table "public"."applicant_status_history" add constraint "applicant_status_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicant_status_history" validate constraint "applicant_status_history_changed_by_fkey";

alter table "public"."applicants" add constraint "applicants_hired_by_user_id_fkey" FOREIGN KEY (hired_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicants" validate constraint "applicants_hired_by_user_id_fkey";

alter table "public"."applicants" add constraint "applicants_recruited_by_user_id_fkey" FOREIGN KEY (recruited_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicants" validate constraint "applicants_recruited_by_user_id_fkey";

alter table "public"."applicants" add constraint "applicants_roving_assignment_id_fkey" FOREIGN KEY (roving_assignment_id) REFERENCES public.roving_assignments(id) ON DELETE SET NULL not valid;

alter table "public"."applicants" validate constraint "applicants_roving_assignment_id_fkey";

alter table "public"."applicants" add constraint "fk_applicants_vacancy_vcode" FOREIGN KEY (vacancy_vcode) REFERENCES public.vacancies(vcode) ON DELETE CASCADE not valid;

alter table "public"."applicants" validate constraint "fk_applicants_vacancy_vcode";

alter table "public"."bulk_emploc_items" add constraint "bulk_emploc_items_upload_id_fkey" FOREIGN KEY (upload_id) REFERENCES public.bulk_emploc_uploads(id) ON DELETE CASCADE not valid;

alter table "public"."bulk_emploc_items" validate constraint "bulk_emploc_items_upload_id_fkey";

alter table "public"."bulk_emploc_uploads" add constraint "bulk_emploc_uploads_uploaded_by_user_id_fkey" FOREIGN KEY (uploaded_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."bulk_emploc_uploads" validate constraint "bulk_emploc_uploads_uploaded_by_user_id_fkey";

alter table "public"."cencom_weekly_snapshots" add constraint "cencom_weekly_snapshots_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE SET NULL not valid;

alter table "public"."cencom_weekly_snapshots" validate constraint "cencom_weekly_snapshots_group_id_fkey";

alter table "public"."deactivation_audit_log" add constraint "deactivation_audit_log_request_id_fkey" FOREIGN KEY (request_id) REFERENCES public.deactivation_requests(id) not valid;

alter table "public"."deactivation_audit_log" validate constraint "deactivation_audit_log_request_id_fkey";

alter table "public"."deactivation_items" add constraint "deactivation_items_plantilla_id_fkey" FOREIGN KEY (plantilla_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."deactivation_items" validate constraint "deactivation_items_plantilla_id_fkey";

alter table "public"."deactivation_items" add constraint "deactivation_items_request_id_fkey" FOREIGN KEY (request_id) REFERENCES public.deactivation_requests(id) ON DELETE CASCADE not valid;

alter table "public"."deactivation_items" validate constraint "deactivation_items_request_id_fkey";

alter table "public"."employee_deployments" add constraint "employee_deployments_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES public.employees(id) not valid;

alter table "public"."employee_deployments" validate constraint "employee_deployments_employee_id_fkey";

alter table "public"."employee_deployments" add constraint "employee_deployments_vcode_fkey" FOREIGN KEY (vcode) REFERENCES public.vacancies(vcode) not valid;

alter table "public"."employee_deployments" validate constraint "employee_deployments_vcode_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_account_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_created_plantilla_id_fkey" FOREIGN KEY (created_plantilla_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_created_plantilla_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_group_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_position_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_requested_by_user_id_fkey" FOREIGN KEY (requested_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_requested_by_user_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_reviewed_by_user_id_fkey" FOREIGN KEY (reviewed_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_reviewed_by_user_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_slot_created_by_user_id_fkey" FOREIGN KEY (slot_created_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_slot_created_by_user_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_store_id_fkey" FOREIGN KEY (store_id) REFERENCES public.stores(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_store_id_fkey";

alter table "public"."hr_emploc" add constraint "fk_hr_emploc_vcode" FOREIGN KEY (vcode) REFERENCES public.vacancies(vcode) ON DELETE CASCADE not valid;

alter table "public"."hr_emploc" validate constraint "fk_hr_emploc_vcode";

alter table "public"."hr_emploc" add constraint "hr_emploc_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_account_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_applicant_id_fkey" FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_applicant_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_assignment_type_consistency_chk" CHECK ((((assignment_type = 'Stationary'::public.hr_emploc_assignment_type) AND (roving_assignment_id IS NULL) AND (vacancy_id IS NOT NULL)) OR ((assignment_type = 'Roving'::public.hr_emploc_assignment_type) AND (roving_assignment_id IS NOT NULL)))) NOT VALID not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_assignment_type_consistency_chk";

alter table "public"."hr_emploc" add constraint "hr_emploc_backout_by_fkey" FOREIGN KEY (backout_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_backout_by_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_deployer_id_fkey" FOREIGN KEY (deployer_id) REFERENCES public.deployer(id) ON DELETE SET NULL not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_deployer_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_hr_personnel_user_id_fkey" FOREIGN KEY (hr_personnel_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_hr_personnel_user_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_hr_reviewed_by_user_id_fkey" FOREIGN KEY (hr_reviewed_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_hr_reviewed_by_user_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_position_id_snapshot_fkey" FOREIGN KEY (position_id_snapshot) REFERENCES public.positions(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_position_id_snapshot_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_roving_assignment_id_fkey" FOREIGN KEY (roving_assignment_id) REFERENCES public.roving_assignments(id) ON DELETE SET NULL not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_roving_assignment_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_vacancy_id_fkey";

alter table "public"."hr_emploc_correction_attachments" add constraint "hr_emploc_correction_attachments_hr_emploc_id_fkey" FOREIGN KEY (hr_emploc_id) REFERENCES public.hr_emploc(id) ON DELETE CASCADE not valid;

alter table "public"."hr_emploc_correction_attachments" validate constraint "hr_emploc_correction_attachments_hr_emploc_id_fkey";

alter table "public"."hr_emploc_correction_attachments" add constraint "hr_emploc_correction_attachments_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES public.users_profile(id) ON DELETE SET NULL not valid;

alter table "public"."hr_emploc_correction_attachments" validate constraint "hr_emploc_correction_attachments_uploaded_by_fkey";

alter table "public"."hr_emploc_deletion_activities" add constraint "hr_emploc_deletion_activities_request_fkey" FOREIGN KEY (request_id) REFERENCES public.hr_emploc_deletion_requests(id) ON DELETE CASCADE not valid;

alter table "public"."hr_emploc_deletion_activities" validate constraint "hr_emploc_deletion_activities_request_fkey";

alter table "public"."hr_emploc_deletion_requests" add constraint "hr_emploc_deletion_requests_hr_emploc_id_fkey" FOREIGN KEY (hr_emploc_id) REFERENCES public.hr_emploc(id) ON DELETE SET NULL not valid;

alter table "public"."hr_emploc_deletion_requests" validate constraint "hr_emploc_deletion_requests_hr_emploc_id_fkey";

alter table "public"."hr_emploc_deletion_requests" add constraint "hr_emploc_deletion_requests_original_emploc_id_fkey" FOREIGN KEY (original_emploc_id) REFERENCES public.hr_emploc(id) ON DELETE SET NULL not valid;

alter table "public"."hr_emploc_deletion_requests" validate constraint "hr_emploc_deletion_requests_original_emploc_id_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_backed_out_by_fkey" FOREIGN KEY (backed_out_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_backed_out_by_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_confirmed_by_fkey" FOREIGN KEY (confirmed_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_confirmed_by_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_created_by_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_hr_emploc_id_fkey" FOREIGN KEY (hr_emploc_id) REFERENCES public.hr_emploc(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_hr_emploc_id_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_resigned_by_fkey" FOREIGN KEY (resigned_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_resigned_by_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_roving_assignment_id_fkey" FOREIGN KEY (roving_assignment_id) REFERENCES public.roving_assignments(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_roving_assignment_id_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_updated_by_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_vacancy_id_fkey";

alter table "public"."login_sessions" add constraint "login_sessions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users_profile(id) ON DELETE CASCADE not valid;

alter table "public"."login_sessions" validate constraint "login_sessions_user_id_fkey";

alter table "public"."mika_import_rows" add constraint "mika_import_rows_import_log_id_fkey" FOREIGN KEY (import_log_id) REFERENCES public.mika_import_logs(id) ON DELETE CASCADE not valid;

alter table "public"."mika_import_rows" validate constraint "mika_import_rows_import_log_id_fkey";

alter table "public"."plantilla" add constraint "fk_plantilla_vcode" FOREIGN KEY (vcode) REFERENCES public.vacancies(vcode) not valid;

alter table "public"."plantilla" validate constraint "fk_plantilla_vcode";

alter table "public"."plantilla" add constraint "plantilla_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."plantilla" validate constraint "plantilla_account_id_fkey";

alter table "public"."plantilla" add constraint "plantilla_deactivated_by_fkey" FOREIGN KEY (deactivated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_deactivated_by_fkey";

alter table "public"."plantilla" add constraint "plantilla_for_deactivation_by_fkey" FOREIGN KEY (for_deactivation_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_for_deactivation_by_fkey";

alter table "public"."plantilla" add constraint "plantilla_hr_emploc_id_fkey" FOREIGN KEY (hr_emploc_id) REFERENCES public.hr_emploc(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_hr_emploc_id_fkey";

alter table "public"."plantilla" add constraint "plantilla_inactive_by_fkey" FOREIGN KEY (inactive_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_inactive_by_fkey";

alter table "public"."plantilla" add constraint "plantilla_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_position_id_fkey";

alter table "public"."plantilla" add constraint "plantilla_roving_assignment_id_fkey" FOREIGN KEY (roving_assignment_id) REFERENCES public.roving_assignments(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_roving_assignment_id_fkey";

alter table "public"."plantilla" add constraint "plantilla_source_headcount_request_fk" FOREIGN KEY (source_headcount_request_id) REFERENCES public.headcount_requests(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_source_headcount_request_fk";

alter table "public"."plantilla" add constraint "plantilla_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_vacancy_id_fkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_created_by_fkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_hr_emploc_store_link_id_fkey" FOREIGN KEY (hr_emploc_store_link_id) REFERENCES public.hr_emploc_store_links(id) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_hr_emploc_store_link_id_fkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_linked_by_fkey" FOREIGN KEY (linked_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_linked_by_fkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_plantilla_id_fkey" FOREIGN KEY (plantilla_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_plantilla_id_fkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_roving_assignment_id_fkey" FOREIGN KEY (roving_assignment_id) REFERENCES public.roving_assignments(id) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_roving_assignment_id_fkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_unlinked_by_fkey" FOREIGN KEY (unlinked_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_unlinked_by_fkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_updated_by_fkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_vacancy_id_fkey";

alter table "public"."positions" add constraint "positions_accounts_id_fkey" FOREIGN KEY (accounts_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."positions" validate constraint "positions_accounts_id_fkey";

alter table "public"."positions" add constraint "positions_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."positions" validate constraint "positions_group_id_fkey";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_assigned_encoder_id_fkey" FOREIGN KEY (assigned_encoder_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."possible_ghost_employees" validate constraint "possible_ghost_employees_assigned_encoder_id_fkey";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_import_log_id_fkey" FOREIGN KEY (import_log_id) REFERENCES public.mika_import_logs(id) not valid;

alter table "public"."possible_ghost_employees" validate constraint "possible_ghost_employees_import_log_id_fkey";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_resolved_by_user_id_fkey" FOREIGN KEY (resolved_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."possible_ghost_employees" validate constraint "possible_ghost_employees_resolved_by_user_id_fkey";

alter table "public"."qa_agent_evidence" add constraint "qa_agent_evidence_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_evidence" validate constraint "qa_agent_evidence_created_by_fkey";

alter table "public"."qa_agent_evidence" add constraint "qa_agent_evidence_finding_id_fkey" FOREIGN KEY (finding_id) REFERENCES public.qa_agent_findings(id) ON DELETE CASCADE not valid;

alter table "public"."qa_agent_evidence" validate constraint "qa_agent_evidence_finding_id_fkey";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_assigned_to_fkey" FOREIGN KEY (assigned_to) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_findings" validate constraint "qa_agent_findings_assigned_to_fkey";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_resolved_by_fkey" FOREIGN KEY (resolved_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_findings" validate constraint "qa_agent_findings_resolved_by_fkey";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_run_id_fkey" FOREIGN KEY (run_id) REFERENCES public.qa_agent_runs(id) ON DELETE CASCADE not valid;

alter table "public"."qa_agent_findings" validate constraint "qa_agent_findings_run_id_fkey";

alter table "public"."qa_agent_rules" add constraint "qa_agent_rules_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_rules" validate constraint "qa_agent_rules_created_by_fkey";

alter table "public"."qa_agent_rules" add constraint "qa_agent_rules_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_rules" validate constraint "qa_agent_rules_updated_by_fkey";

alter table "public"."qa_agent_runs" add constraint "qa_agent_runs_initiated_by_fkey" FOREIGN KEY (initiated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_runs" validate constraint "qa_agent_runs_initiated_by_fkey";

alter table "public"."qa_daily_reports" add constraint "qa_daily_reports_generated_by_fkey" FOREIGN KEY (generated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_daily_reports" validate constraint "qa_daily_reports_generated_by_fkey";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_run_id_fkey" FOREIGN KEY (run_id) REFERENCES public.qa_agent_runs(id) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_run_id_fkey";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_schedule_id_fkey" FOREIGN KEY (schedule_id) REFERENCES public.qa_schedules(id) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_schedule_id_fkey";

alter table "public"."qa_schedules" add constraint "qa_schedules_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_schedules" validate constraint "qa_schedules_created_by_fkey";

alter table "public"."qa_schedules" add constraint "qa_schedules_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_schedules" validate constraint "qa_schedules_updated_by_fkey";

alter table "public"."roving_assignments" add constraint "roving_assignments_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."roving_assignments" validate constraint "roving_assignments_account_id_fkey";

alter table "public"."roving_assignments" add constraint "roving_assignments_master_applicant_id_fkey" FOREIGN KEY (master_applicant_id) REFERENCES public.applicants(id) not valid;

alter table "public"."roving_assignments" validate constraint "roving_assignments_master_applicant_id_fkey";

alter table "public"."sla_breach_logs" add constraint "sla_breach_logs_plantilla_id_fkey" FOREIGN KEY (plantilla_id) REFERENCES public.plantilla(id) ON DELETE SET NULL not valid;

alter table "public"."sla_breach_logs" validate constraint "sla_breach_logs_plantilla_id_fkey";

alter table "public"."staging_imports" add constraint "staging_imports_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."staging_imports" validate constraint "staging_imports_approved_by_fkey";

alter table "public"."staging_imports" add constraint "staging_imports_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."staging_imports" validate constraint "staging_imports_created_by_fkey";

alter table "public"."staging_imports" add constraint "staging_imports_validated_by_fkey" FOREIGN KEY (validated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."staging_imports" validate constraint "staging_imports_validated_by_fkey";

alter table "public"."store_import_batches" add constraint "store_import_batches_selected_account_id_fkey" FOREIGN KEY (selected_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."store_import_batches" validate constraint "store_import_batches_selected_account_id_fkey";

alter table "public"."store_import_batches" add constraint "store_import_batches_selected_group_id_fkey" FOREIGN KEY (selected_group_id) REFERENCES public.groups(id) not valid;

alter table "public"."store_import_batches" validate constraint "store_import_batches_selected_group_id_fkey";

alter table "public"."store_import_rows" add constraint "store_import_rows_batch_id_fkey" FOREIGN KEY (batch_id) REFERENCES public.store_import_batches(id) ON DELETE CASCADE not valid;

alter table "public"."store_import_rows" validate constraint "store_import_rows_batch_id_fkey";

alter table "public"."stores" add constraint "stores_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."stores" validate constraint "stores_account_id_fkey";

alter table "public"."stores" add constraint "stores_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) not valid;

alter table "public"."stores" validate constraint "stores_group_id_fkey";

alter table "public"."stores" add constraint "stores_hrco_user_id_fkey" FOREIGN KEY (hrco_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."stores" validate constraint "stores_hrco_user_id_fkey";

alter table "public"."stores" add constraint "stores_om_user_id_fkey" FOREIGN KEY (om_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."stores" validate constraint "stores_om_user_id_fkey";

alter table "public"."temp_approval_access" add constraint "temp_approval_access_granted_by_fkey" FOREIGN KEY (granted_by) REFERENCES public.users_profile(id) ON DELETE CASCADE not valid;

alter table "public"."temp_approval_access" validate constraint "temp_approval_access_granted_by_fkey";

alter table "public"."temp_approval_access" add constraint "temp_approval_access_granted_to_fkey" FOREIGN KEY (granted_to) REFERENCES public.users_profile(id) ON DELETE CASCADE not valid;

alter table "public"."temp_approval_access" validate constraint "temp_approval_access_granted_to_fkey";

alter table "public"."temp_permission_overrides" add constraint "temp_permission_overrides_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."temp_permission_overrides" validate constraint "temp_permission_overrides_user_id_fkey";

alter table "public"."user_account_transfers" add constraint "user_account_transfers_transferred_by_fkey" FOREIGN KEY (transferred_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."user_account_transfers" validate constraint "user_account_transfers_transferred_by_fkey";

alter table "public"."user_account_transfers" add constraint "user_account_transfers_user_profile_id_fkey" FOREIGN KEY (user_profile_id) REFERENCES public.users_profile(id) ON DELETE CASCADE not valid;

alter table "public"."user_account_transfers" validate constraint "user_account_transfers_user_profile_id_fkey";

alter table "public"."user_scopes" add constraint "user_scopes_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."user_scopes" validate constraint "user_scopes_account_id_fkey";

alter table "public"."user_scopes" add constraint "user_scopes_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE not valid;

alter table "public"."user_scopes" validate constraint "user_scopes_group_id_fkey";

alter table "public"."user_scopes" add constraint "user_scopes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users_profile(id) ON DELETE CASCADE not valid;

alter table "public"."user_scopes" validate constraint "user_scopes_user_id_fkey";

alter table "public"."users_profile" add constraint "fk_users_profile_group" FOREIGN KEY (group_id) REFERENCES public.groups(id) not valid;

alter table "public"."users_profile" validate constraint "fk_users_profile_group";

alter table "public"."users_profile" add constraint "users_profile_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE SET NULL not valid;

alter table "public"."users_profile" validate constraint "users_profile_account_id_fkey";

alter table "public"."users_profile" add constraint "users_profile_role_id_fkey" FOREIGN KEY (role_id) REFERENCES public.roles(id) not valid;

alter table "public"."users_profile" validate constraint "users_profile_role_id_fkey";

alter table "public"."vacancies" add constraint "fk_vacancies_store_id" FOREIGN KEY (store_id) REFERENCES public.stores(id) not valid;

alter table "public"."vacancies" validate constraint "fk_vacancies_store_id";

alter table "public"."vacancies" add constraint "vacancies_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."vacancies" validate constraint "vacancies_account_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_assigned_encoder_id_fkey" FOREIGN KEY (assigned_encoder_id) REFERENCES public.users_profile(id) ON DELETE SET NULL not valid;

alter table "public"."vacancies" validate constraint "vacancies_assigned_encoder_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_home_account_id_fkey" FOREIGN KEY (home_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_home_account_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_pool_request_id_fkey" FOREIGN KEY (pool_request_id) REFERENCES public.workforce_pool_requests(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_pool_request_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_pool_type_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_position_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_source_headcount_request_id_fkey" FOREIGN KEY (source_headcount_request_id) REFERENCES public.headcount_requests(id) ON DELETE SET NULL not valid;

alter table "public"."vacancies" validate constraint "vacancies_source_headcount_request_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_source_plantilla_id_fkey" FOREIGN KEY (source_plantilla_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_source_plantilla_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_source_vacancy_request_id_fkey" FOREIGN KEY (source_vacancy_request_id) REFERENCES public.vacancy_requests(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_source_vacancy_request_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_triggered_by_user_id_fkey" FOREIGN KEY (triggered_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_triggered_by_user_id_fkey";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_reason_id_fkey" FOREIGN KEY (reason_id) REFERENCES public.vacancy_closure_reasons(id) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_reason_id_fkey";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_requested_by_user_id_fkey" FOREIGN KEY (requested_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_requested_by_user_id_fkey";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_vacancy_vcode_fkey" FOREIGN KEY (vacancy_vcode) REFERENCES public.vacancies(vcode) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_vacancy_vcode_fkey";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_withdrawn_by_user_id_fkey" FOREIGN KEY (withdrawn_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_withdrawn_by_user_id_fkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_account_id_fkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_applicant_id_fkey" FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_applicant_id_fkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_hr_emploc_id_fkey" FOREIGN KEY (hr_emploc_id) REFERENCES public.hr_emploc(id) not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_hr_emploc_id_fkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) ON DELETE CASCADE not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_vacancy_id_fkey";

alter table "public"."vacancy_requests" add constraint "vacancy_requests_assigned_encoder_id_fkey" FOREIGN KEY (assigned_encoder_id) REFERENCES public.users_profile(id) ON DELETE SET NULL not valid;

alter table "public"."vacancy_requests" validate constraint "vacancy_requests_assigned_encoder_id_fkey";

alter table "public"."vacancy_requests" add constraint "vacancy_requests_requested_by_user_id_fkey" FOREIGN KEY (requested_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."vacancy_requests" validate constraint "vacancy_requests_requested_by_user_id_fkey";

alter table "public"."vcodes" add constraint "vcodes_vacancy_request_id_fkey" FOREIGN KEY (vacancy_request_id) REFERENCES public.vacancy_requests(id) not valid;

alter table "public"."vcodes" validate constraint "vcodes_vacancy_request_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_converted_assignment_id_fkey" FOREIGN KEY (converted_assignment_id) REFERENCES public.workforce_assignments(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_converted_assignment_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_employee_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_pool_type_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_requested_account_id_fkey" FOREIGN KEY (requested_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_requested_account_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_requested_group_id_fkey" FOREIGN KEY (requested_group_id) REFERENCES public.groups(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_requested_group_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_requested_store_id_fkey" FOREIGN KEY (requested_store_id) REFERENCES public.stores(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_requested_store_id_fkey";

alter table "public"."workforce_assignments" add constraint "workforce_assignments_assigned_account_id_fkey" FOREIGN KEY (assigned_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."workforce_assignments" validate constraint "workforce_assignments_assigned_account_id_fkey";

alter table "public"."workforce_assignments" add constraint "workforce_assignments_assigned_group_id_fkey" FOREIGN KEY (assigned_group_id) REFERENCES public.groups(id) not valid;

alter table "public"."workforce_assignments" validate constraint "workforce_assignments_assigned_group_id_fkey";

alter table "public"."workforce_assignments" add constraint "workforce_assignments_assigned_store_id_fkey" FOREIGN KEY (assigned_store_id) REFERENCES public.stores(id) not valid;

alter table "public"."workforce_assignments" validate constraint "workforce_assignments_assigned_store_id_fkey";

alter table "public"."workforce_assignments" add constraint "workforce_assignments_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."workforce_assignments" validate constraint "workforce_assignments_employee_id_fkey";

alter table "public"."workforce_assignments" add constraint "workforce_assignments_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_assignments" validate constraint "workforce_assignments_pool_type_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_employee_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_pool_slot_id_fkey" FOREIGN KEY (pool_slot_id) REFERENCES public.workforce_pool_slots(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_pool_slot_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_pool_type_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_slot_review_id_fkey" FOREIGN KEY (slot_review_id) REFERENCES public.workforce_slot_reviews(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_slot_review_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_target_account_id_fkey" FOREIGN KEY (target_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_target_account_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_target_store_id_fkey" FOREIGN KEY (target_store_id) REFERENCES public.stores(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_target_store_id_fkey";

alter table "public"."workforce_pool_request_items" add constraint "workforce_pool_request_items_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) not valid;

alter table "public"."workforce_pool_request_items" validate constraint "workforce_pool_request_items_position_id_fkey";

alter table "public"."workforce_pool_request_items" add constraint "workforce_pool_request_items_request_id_fkey" FOREIGN KEY (request_id) REFERENCES public.workforce_pool_requests(id) not valid;

alter table "public"."workforce_pool_request_items" validate constraint "workforce_pool_request_items_request_id_fkey";

alter table "public"."workforce_pool_request_items" add constraint "workforce_pool_request_items_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."workforce_pool_request_items" validate constraint "workforce_pool_request_items_vacancy_id_fkey";

alter table "public"."workforce_pool_requests" add constraint "workforce_pool_requests_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_pool_requests" validate constraint "workforce_pool_requests_pool_type_id_fkey";

alter table "public"."workforce_pool_requests" add constraint "workforce_pool_requests_requesting_account_id_fkey" FOREIGN KEY (requesting_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."workforce_pool_requests" validate constraint "workforce_pool_requests_requesting_account_id_fkey";

alter table "public"."workforce_pool_requests" add constraint "workforce_pool_requests_requesting_store_id_fkey" FOREIGN KEY (requesting_store_id) REFERENCES public.stores(id) not valid;

alter table "public"."workforce_pool_requests" validate constraint "workforce_pool_requests_requesting_store_id_fkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."workforce_pool_slots" validate constraint "workforce_pool_slots_account_id_fkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) not valid;

alter table "public"."workforce_pool_slots" validate constraint "workforce_pool_slots_group_id_fkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_pool_slots" validate constraint "workforce_pool_slots_pool_type_id_fkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."workforce_pool_slots" validate constraint "workforce_pool_slots_vacancy_id_fkey";

alter table "public"."workforce_slot_reviews" add constraint "workforce_slot_reviews_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_slot_reviews" validate constraint "workforce_slot_reviews_pool_type_id_fkey";

alter table "public"."workforce_slot_reviews" add constraint "workforce_slot_reviews_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."workforce_slot_reviews" validate constraint "workforce_slot_reviews_vacancy_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.add_store_import_rows(p_batch_id uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lvl       int  := public.get_my_role_level();
  v_uid       uuid := auth.uid();
  v_batch     public.store_import_batches%ROWTYPE;
  v_row       jsonb;
  v_idx       int := 0;
  v_vcode     text;
  v_name      text;
  v_prov      text;
  v_city      text;
  v_type_raw  text;
  v_type      text;
  v_pen_raw   text;
  v_pen       boolean;
  v_errs      jsonb;
  v_dup_in_csv jsonb;
  v_total     int := 0;
  v_valid     int := 0;
  v_invalid   int := 0;
  v_summary   jsonb := '{}'::jsonb;
  v_final_status text;
BEGIN
  IF v_lvl IS NULL OR v_lvl < 90 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND'; END IF;
  IF NOT (public.is_super_admin() OR v_batch.uploaded_by = v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: uploader or super admin only';
  END IF;
  IF v_batch.status NOT IN ('draft_uploaded','validation_failed') THEN
    RAISE EXCEPTION 'INVALID_STATE: batch is %', v_batch.status;
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows must be jsonb array';
  END IF;

  -- Reset prior staged rows for this batch
  DELETE FROM public.store_import_rows WHERE batch_id = p_batch_id;

  -- Build duplicate VCODE set inside payload
  v_dup_in_csv := (
    SELECT COALESCE(jsonb_agg(DISTINCT lower(trim(v))), '[]'::jsonb)
    FROM (
      SELECT (elem->>'VCODE') AS v
      FROM jsonb_array_elements(p_rows) elem
      WHERE elem->>'VCODE' IS NOT NULL AND length(trim(elem->>'VCODE')) > 0
      GROUP BY lower(trim(elem->>'VCODE'))
      HAVING count(*) > 1
    ) d
  );

FOR v_row IN
  SELECT elem.value
  FROM jsonb_array_elements(p_rows) AS elem(value)
  LOOP
    v_idx := v_idx + 1;
    v_total := v_total + 1;
    v_errs := '[]'::jsonb;

    v_vcode    := NULLIF(trim(COALESCE(v_row->>'VCODE','')), '');
    v_name     := NULLIF(trim(COALESCE(v_row->>'STORE_NAME','')), '');
    v_prov     := NULLIF(trim(COALESCE(v_row->>'AREA_PROVINCE','')), '');
    v_city     := NULLIF(trim(COALESCE(v_row->>'AREA_CITY','')), '');
    v_type_raw := lower(NULLIF(trim(COALESCE(v_row->>'TYPE','')), ''));
    v_pen_raw  := lower(NULLIF(trim(COALESCE(v_row->>'WITH_PENALTY','')), ''));

    -- Required fields
    IF v_vcode IS NULL THEN v_errs := v_errs || jsonb_build_object('field','VCODE','msg','required'); END IF;
    IF v_name  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','STORE_NAME','msg','required'); END IF;
    IF v_prov  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','AREA_PROVINCE','msg','required'); END IF;
    IF v_city  IS NULL THEN v_errs := v_errs || jsonb_build_object('field','AREA_CITY','msg','required'); END IF;

    -- TYPE
    IF v_type_raw IS NULL THEN
      v_errs := v_errs || jsonb_build_object('field','TYPE','msg','required');
      v_type := NULL;
    ELSIF v_type_raw NOT IN ('stationary','roving') THEN
      v_errs := v_errs || jsonb_build_object('field','TYPE','msg','must be stationary or roving');
      v_type := NULL;
    ELSE
      v_type := v_type_raw;
    END IF;

    -- WITH_PENALTY
    IF v_pen_raw IS NULL THEN
      v_errs := v_errs || jsonb_build_object('field','WITH_PENALTY','msg','required');
      v_pen := NULL;
    ELSIF v_pen_raw IN ('yes','y','true','1') THEN
      v_pen := true;
    ELSIF v_pen_raw IN ('no','n','false','0') THEN
      v_pen := false;
    ELSE
      v_errs := v_errs || jsonb_build_object('field','WITH_PENALTY','msg','must be yes or no');
      v_pen := NULL;
    END IF;

    -- duplicate inside CSV
    IF v_vcode IS NOT NULL AND v_dup_in_csv ? lower(v_vcode) THEN
      v_errs := v_errs || jsonb_build_object('field','VCODE','msg','duplicate within CSV');
    END IF;

    -- duplicate vs active stores
    IF v_vcode IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.stores
                   WHERE lower(vcode) = lower(v_vcode) AND status='active') THEN
      v_errs := v_errs || jsonb_build_object('field','VCODE','msg','already exists in active stores');
    END IF;

    INSERT INTO public.store_import_rows (
      batch_id, row_number, raw_data, vcode, store_name, area_province, area_city,
      type, with_penalty, validation_status, validation_errors
    ) VALUES (
      p_batch_id, v_idx, v_row, v_vcode, v_name, v_prov, v_city,
      v_type, v_pen,
      CASE WHEN jsonb_array_length(v_errs)=0 THEN 'valid' ELSE 'invalid' END,
      v_errs
    );

    IF jsonb_array_length(v_errs) = 0 THEN
      v_valid := v_valid + 1;
    ELSE
      v_invalid := v_invalid + 1;
    END IF;
  END LOOP;

-- Aggregate error summary (counts per field)
SELECT COALESCE(jsonb_object_agg(field_name, cnt), '{}'::jsonb)
INTO v_summary
FROM (
  SELECT
    field_name,
    count(*) AS cnt
  FROM (
    SELECT
      (e.value ->> 'field') AS field_name
    FROM public.store_import_rows r
    CROSS JOIN LATERAL jsonb_array_elements(r.validation_errors) AS e(value)
    WHERE r.batch_id = p_batch_id
  ) errors
  GROUP BY field_name
) s;

  v_final_status := CASE
    WHEN v_total = 0 THEN 'validation_failed'
    WHEN v_invalid > 0 THEN 'validation_failed'
    ELSE 'pending_approval'
  END;

  UPDATE public.store_import_batches
     SET total_rows    = v_total,
         valid_rows    = v_valid,
         invalid_rows  = v_invalid,
         error_summary = v_summary,
         status        = v_final_status,
         updated_at    = now()
   WHERE id = p_batch_id;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'total_rows', v_total,
    'valid_rows', v_valid,
    'invalid_rows', v_invalid,
    'status', v_final_status,
    'error_summary', v_summary
  );
END$function$
;

create or replace view "public"."applicant_statuses" as  SELECT status_code,
    label,
    is_terminal,
    allow_on_create,
    is_system_only,
    color_key,
    sort_order,
    is_active
   FROM public.applicant_status_options
  WHERE (is_active = true)
  ORDER BY sort_order;


CREATE OR REPLACE FUNCTION public.approve_correction_request(p_correction_request_id uuid, p_approved_by text DEFAULT NULL::text)
 RETURNS public.hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.hr_emploc;
BEGIN
  SELECT * INTO v_row
  FROM public.hr_emploc
  WHERE id = p_correction_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'HR Emploc record not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_row.hr_status <> 'For Review' THEN
    RAISE EXCEPTION 'Only For Review records can be approved'
      USING ERRCODE = 'P0001';
  END IF;

  IF coalesce(nullif(trim(v_row.employee_no), ''), nullif(trim(v_row.emploc_no), '')) IS NULL THEN
    RAISE EXCEPTION 'EMPLoc number required before approval'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.hr_emploc
  SET
    hr_status              = 'Complete',
    status                 = 'Ready for Plantilla',
    hr_reviewed_by         = coalesce(nullif(trim(p_approved_by), ''), get_my_full_name()),
    hr_reviewed_by_user_id = get_my_profile_id(),
    hr_reviewed_at         = now(),
    updated_at             = now(),
    updated_by             = get_my_profile_id()
  WHERE id = p_correction_request_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.assign_hr_emploc_number(p_id uuid, p_employee_no text)
 RETURNS public.hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old   public.hr_emploc;
  v_new   public.hr_emploc;
  v_clean text := nullif(btrim(p_employee_no),'');
BEGIN
  IF NOT (i_am_hr_dept() OR is_super_admin()) THEN
    RAISE EXCEPTION 'forbidden: HR Dept role required' USING ERRCODE = '42501';
  END IF;

  IF v_clean IS NULL THEN
    RAISE EXCEPTION 'employee_no is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;

  -- PENDING DELETION LOCK
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_id AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'action locked: a pending deletion request exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM hr_emploc
    WHERE employee_no = v_clean AND id <> p_id
      AND deleted_at IS NULL
      AND status NOT IN ('Backout','Moved to Plantilla')
  ) THEN
    RAISE EXCEPTION 'employee_no % already in use on active hr_emploc', v_clean USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1 FROM plantilla
    WHERE employee_no = v_clean
      AND is_deleted = false
      AND status IN ('Active','For Deactivation','On Leave')
  ) THEN
    RAISE EXCEPTION 'employee_no % already exists in active plantilla', v_clean USING ERRCODE = '23505';
  END IF;

  UPDATE hr_emploc
  SET employee_no            = v_clean,
      emploc_no              = v_clean,
      hr_status              = 'Complete',
      status                 = 'Ready for Plantilla',
      hr_reviewed_at         = now(),
      hr_reviewed_by         = get_my_full_name(),
      hr_reviewed_by_user_id = get_my_profile_id(),
      updated_at             = now(),
      updated_by             = get_my_profile_id()
  WHERE id = p_id
  RETURNING * INTO v_new;

  PERFORM log_audit_event('hr_emploc','UPDATE', p_id, to_jsonb(v_old), to_jsonb(v_new));
  RETURN v_new;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_backfill_vacancy_source_from_request(p_request_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count int;
BEGIN
  UPDATE vacancies v
  SET
    source = 'hc_request',
    source_vacancy_request_id = p_request_id,

    urgency_level = CASE
      WHEN lower(vr.urgency) = 'critical' THEN 'Critical'
      WHEN lower(vr.urgency) = 'high' THEN 'High'
      WHEN lower(vr.urgency) = 'medium' THEN 'Medium'
      WHEN lower(vr.urgency) = 'low' THEN 'Low'
      ELSE 'Medium'
    END,

    target_fill_date = vr.date_needed,
    triggered_by_user_id = vr.requested_by_user_id,
    triggered_by_name = vr.requested_by,
    updated_at = NOW()

  FROM vacancy_requests vr
  WHERE vr.id = p_request_id
    AND (
      v.vcode = vr.vcode_created
      OR v.source_vacancy_request_id = p_request_id
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_cencom_weekly_delta(p_reference_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(current_snapshot_date date, previous_snapshot_date date, snapshot_type text, group_id uuid, group_name text, group_code text, current_hc bigint, previous_hc bigint, hc_delta bigint, current_mfr numeric, previous_mfr numeric, mfr_delta numeric, current_pipeline bigint, previous_pipeline bigint, pipeline_delta bigint, current_vacant bigint, previous_vacant bigint, vacant_delta bigint, current_required bigint, previous_required bigint, required_delta bigint, current_health_status text, previous_health_status text, health_changed boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH ordered_dates AS (
    SELECT DISTINCT snapshot_date
    FROM   public.cencom_weekly_snapshots
    WHERE  snapshot_date <= p_reference_date
    ORDER  BY snapshot_date DESC
    LIMIT  2
  ),
  latest_date   AS (SELECT MAX(snapshot_date) AS d FROM ordered_dates),
  previous_date AS (SELECT MIN(snapshot_date) AS d FROM ordered_dates),
  current_snap  AS (
    SELECT * FROM public.cencom_weekly_snapshots
    WHERE  snapshot_date = (SELECT d FROM latest_date)
  ),
  previous_snap AS (
    SELECT * FROM public.cencom_weekly_snapshots
    WHERE  snapshot_date = (SELECT d FROM previous_date)
      AND  snapshot_date < (SELECT d FROM latest_date) -- guard: only if truly different
  )
  SELECT
    (SELECT d FROM latest_date)::date          AS current_snapshot_date,
    (SELECT d FROM previous_date
      WHERE d < (SELECT d FROM latest_date))::date AS previous_snapshot_date,

    c.snapshot_type,
    c.group_id,
    c.group_name,
    c.group_code,

    c.actual_hc                                AS current_hc,
    p.actual_hc                                AS previous_hc,
    c.actual_hc - COALESCE(p.actual_hc, 0)    AS hc_delta,

    c.mfr                                      AS current_mfr,
    p.mfr                                      AS previous_mfr,
    c.mfr - COALESCE(p.mfr, 0)                AS mfr_delta,

    c.pipeline_count                           AS current_pipeline,
    p.pipeline_count                           AS previous_pipeline,
    c.pipeline_count - COALESCE(p.pipeline_count, 0) AS pipeline_delta,

    c.vacant_count                             AS current_vacant,
    p.vacant_count                             AS previous_vacant,
    c.vacant_count - COALESCE(p.vacant_count, 0) AS vacant_delta,

    c.required_hc                              AS current_required,
    p.required_hc                              AS previous_required,
    c.required_hc - COALESCE(p.required_hc, 0) AS required_delta,

    c.health_status                            AS current_health_status,
    p.health_status                            AS previous_health_status,
    (c.health_status IS DISTINCT FROM p.health_status) AS health_changed

  FROM current_snap c
  LEFT JOIN previous_snap p
    ON p.group_id IS NOT DISTINCT FROM c.group_id
   AND p.snapshot_type = c.snapshot_type
  ORDER BY
    c.snapshot_type DESC,  -- 'group' before 'aggregate'? keep aggregate first
    c.group_code NULLS FIRST;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_generate_cencom_weekly_snapshot(p_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_group_rows  int := 0;
  v_agg_row     int := 0;
  v_result      jsonb;
BEGIN
  RAISE LOG '[cencom_snapshot] Starting snapshot generation for date %', p_date;

  -- ── Idempotency: clear existing rows for this date ──────────────────────
  DELETE FROM public.cencom_weekly_snapshots
  WHERE  snapshot_date = p_date;

  -- ── Build the CENCOM scoped data and insert in a single CTE-backed statement ──
  --
  -- FIX (OHM2026_2004): A PostgreSQL WITH clause is scoped to exactly one SQL
  -- statement. The previous implementation defined all CTEs (including group_agg)
  -- in a single WITH block, then used two separate INSERT statements. After the
  -- first INSERT consumed the CTE block, group_agg was no longer in scope for
  -- the second INSERT, producing:
  --   ERROR: relation "group_agg" does not exist (SQLSTATE 42P01)
  --
  -- Fix: combine both inserts into a single INSERT ... SELECT ... UNION ALL
  -- statement so the full CTE block remains in scope for both result sets.
  -- A discriminator column (row_type) routes each row to its correct snapshot_type.
  -- ---------------------------------------------------------------------------
  INSERT INTO public.cencom_weekly_snapshots (
    snapshot_date, snapshot_type,
    group_id, group_name, group_code,
    actual_hc, pipeline_count, vacant_count, required_hc,
    mfr, projected_mfr, vacancy_rate, pipeline_coverage, health_status
  )
  WITH actual AS (
    SELECT
      pl.account_id,
      count(*) FILTER (WHERE pl.status = 'Active') AS actual_hc
    FROM   public.plantilla pl
    WHERE  NOT COALESCE(pl.is_deleted, false)
    GROUP  BY pl.account_id
  ),
  pipeline AS (
    SELECT
      he.account_id,
      count(*) AS pipeline_count
    FROM   public.hr_emploc he
    WHERE  he.status NOT IN ('Moved to Plantilla', 'Backout')
      AND  he.deleted_at IS NULL
    GROUP  BY he.account_id
  ),
  vacant AS (
    SELECT
      v.account_id,
      count(*) AS vacant_count
    FROM   public.vacancies v
    WHERE  v.status = 'Open'
      AND  NOT COALESCE(v.is_archived, false)
    GROUP  BY v.account_id
  ),
  account_base AS (
    SELECT
      a.id                                   AS account_id,
      a.group_id,
      g.group_name,
      g.group_code,
      COALESCE(ac.actual_hc, 0)              AS actual_hc,
      COALESCE(p.pipeline_count, 0)          AS pipeline_count,
      COALESCE(v.vacant_count, 0)            AS vacant_count,
      COALESCE(ac.actual_hc, 0)
        + COALESCE(p.pipeline_count, 0)
        + COALESCE(v.vacant_count, 0)        AS required_hc
    FROM   public.accounts a
    JOIN   public.groups g ON g.id = a.group_id AND g.cencom_scope = true
    LEFT JOIN actual   ac ON ac.account_id = a.id
    LEFT JOIN pipeline p  ON p.account_id  = a.id
    LEFT JOIN vacant   v  ON v.account_id  = a.id
    WHERE  a.is_active = true
  ),
  group_agg AS (
    SELECT
      group_id,
      group_name,
      group_code,
      sum(actual_hc)::bigint                                           AS actual_hc,
      sum(pipeline_count)::bigint                                      AS pipeline_count,
      sum(vacant_count)::bigint                                        AS vacant_count,
      sum(required_hc)::bigint                                         AS required_hc,
      CASE WHEN sum(required_hc) = 0 THEN 1.0
           ELSE round(sum(actual_hc)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS mfr,
      CASE WHEN sum(required_hc) = 0 THEN 1.0
           ELSE round((sum(actual_hc) + sum(pipeline_count))::numeric
                      / sum(required_hc)::numeric, 4)
      END                                                              AS projected_mfr,
      CASE WHEN sum(required_hc) = 0 THEN 0.0
           ELSE round(sum(vacant_count)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS vacancy_rate,
      CASE WHEN sum(required_hc) = 0 THEN 0.0
           ELSE round(sum(pipeline_count)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS pipeline_coverage,
      CASE WHEN sum(required_hc) = 0                           THEN 'healthy'
           WHEN sum(actual_hc)::numeric
                / sum(required_hc)::numeric >= 1.0              THEN 'healthy'
           WHEN sum(actual_hc)::numeric
                / sum(required_hc)::numeric >= 0.9              THEN 'at_risk'
           ELSE                                                       'critical'
      END                                                              AS health_status
    FROM account_base
    GROUP BY group_id, group_name, group_code
  ),
  total_agg AS (
    SELECT
      sum(actual_hc)::bigint                                           AS actual_hc,
      sum(pipeline_count)::bigint                                      AS pipeline_count,
      sum(vacant_count)::bigint                                        AS vacant_count,
      sum(required_hc)::bigint                                         AS required_hc,
      CASE WHEN sum(required_hc) = 0 THEN 1.0
           ELSE round(sum(actual_hc)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS mfr,
      CASE WHEN sum(required_hc) = 0 THEN 1.0
           ELSE round((sum(actual_hc) + sum(pipeline_count))::numeric
                      / sum(required_hc)::numeric, 4)
      END                                                              AS projected_mfr,
      CASE WHEN sum(required_hc) = 0 THEN 0.0
           ELSE round(sum(vacant_count)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS vacancy_rate,
      CASE WHEN sum(required_hc) = 0 THEN 0.0
           ELSE round(sum(pipeline_count)::numeric / sum(required_hc)::numeric, 4)
      END                                                              AS pipeline_coverage,
      CASE WHEN sum(required_hc) = 0                           THEN 'healthy'
           WHEN sum(actual_hc)::numeric
                / sum(required_hc)::numeric >= 1.0              THEN 'healthy'
           WHEN sum(actual_hc)::numeric
                / sum(required_hc)::numeric >= 0.9              THEN 'at_risk'
           ELSE                                                       'critical'
      END                                                              AS health_status
    FROM account_base
  )
  -- Aggregate row first (group_id NULL), then one row per cencom_scope group.
  -- Single INSERT keeps group_agg and total_agg in the same CTE scope.
  SELECT p_date, 'aggregate', NULL, 'ALL GROUPS', 'ALL',
         actual_hc, pipeline_count, vacant_count, required_hc,
         mfr, projected_mfr, vacancy_rate, pipeline_coverage, health_status
  FROM   total_agg
  UNION ALL
  SELECT p_date, 'group', group_id, group_name, group_code,
         actual_hc, pipeline_count, vacant_count, required_hc,
         mfr, projected_mfr, vacancy_rate, pipeline_coverage, health_status
  FROM   group_agg;

  GET DIAGNOSTICS v_group_rows = ROW_COUNT;
  -- v_group_rows now holds total rows inserted (1 aggregate + N group rows).
  -- Derive the two sub-counts for the result JSON.
  v_agg_row    := LEAST(v_group_rows, 1);        -- always 1 unless table was empty
  v_group_rows := GREATEST(v_group_rows - 1, 0); -- remainder = per-group rows

  v_result := jsonb_build_object(
    'snapshot_date',  p_date,
    'aggregate_rows', v_agg_row,
    'group_rows',     v_group_rows,
    'generated_at',   now()
  );

  RAISE LOG '[cencom_snapshot] Completed for date %: % aggregate row, % group rows',
    p_date, v_agg_row, v_group_rows;

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RAISE LOG '[cencom_snapshot] ERROR for date %: % %', p_date, SQLSTATE, SQLERRM;
  RAISE;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_request_emploc_deletion(p_hr_emploc_id uuid, p_reason text, p_deletion_type text DEFAULT 'Backout'::text, p_original_emploc_id uuid DEFAULT NULL::uuid)
 RETURNS public.hr_emploc_deletion_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp         public.hr_emploc;
  v_profile     public.users_profile;
  v_req         public.hr_emploc_deletion_requests;
  v_full_name   text;
  v_last_name   text;
  v_first_name  text;
  v_store       text;
  v_name        text;
  v_parts       text[];
BEGIN
  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: Ops or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  IF p_deletion_type NOT IN ('Backout', 'Duplicate Record') THEN
    RAISE EXCEPTION 'invalid deletion_type: %. Must be Backout or Duplicate Record', p_deletion_type
      USING ERRCODE = '22023';
  END IF;

  IF p_deletion_type = 'Duplicate Record' AND p_original_emploc_id IS NULL THEN
    RAISE EXCEPTION 'original_emploc_id is required for Duplicate Record deletion type'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp
  FROM public.hr_emploc
  WHERE id = p_hr_emploc_id
  FOR UPDATE;

  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or already archived', p_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = p_hr_emploc_id
      AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'a pending deletion request already exists for this record'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_profile
  FROM public.users_profile
  WHERE id = public.get_my_profile_id();

  v_full_name := COALESCE(v_profile.full_name, public.get_my_full_name());

  v_name := COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name);

  IF v_name LIKE '%, %' THEN
    v_last_name  := BTRIM(split_part(v_name, ', ', 1));
    v_first_name := BTRIM(split_part(v_name, ', ', 2));
  ELSE
    v_parts      := regexp_split_to_array(BTRIM(v_name), '\s+');
    v_last_name  := v_parts[array_length(v_parts, 1)];
    v_first_name := BTRIM(array_to_string(v_parts[1:array_length(v_parts,1)-1], ' '));
  END IF;

  v_store := COALESCE(NULLIF(BTRIM(COALESCE(v_emp.store_name, '')), ''), v_emp.account);

  INSERT INTO public.hr_emploc_deletion_requests (
    hr_emploc_id,
    applicant_name,
    vcode,
    account,
    reason,
    requested_by,
    requested_by_role,
    requested_by_user_id,
    deletion_type,
    original_emploc_id,
    reopen_vacancy,
    original_hr_status,
    snapshot_last_name,
    snapshot_first_name,
    snapshot_position,
    snapshot_store,
    status
  ) VALUES (
    p_hr_emploc_id,
    COALESCE(v_emp.applicant_name_snapshot, v_emp.applicant_name),
    v_emp.vcode,
    v_emp.account,
    BTRIM(p_reason),
    v_full_name,
    COALESCE(v_profile.role, public.get_my_role()),
    public.get_my_profile_id(),
    p_deletion_type,
    p_original_emploc_id,
    (p_deletion_type = 'Backout'),
    v_emp.hr_status,
    v_last_name,
    v_first_name,
    v_emp.position,
    v_store,
    'Pending'
  ) RETURNING * INTO v_req;

  INSERT INTO public.hr_emploc_deletion_activities (
    request_id,
    activity_type,
    performed_by,
    performed_by_user_id,
    remarks,
    snapshot
  ) VALUES (
    v_req.id,
    'Request Submitted',
    v_full_name,
    public.get_my_profile_id(),
    BTRIM(p_reason),
    jsonb_build_object(
      'deletion_type', p_deletion_type,
      'applicant_name', v_req.applicant_name,
      'snapshot_last_name', v_last_name,
      'snapshot_first_name', v_first_name,
      'vcode', v_req.vcode,
      'account', v_req.account,
      'snapshot_position', v_emp.position,
      'snapshot_store', v_store,
      'requested_by', v_full_name,
      'requested_by_role', COALESCE(v_profile.role, public.get_my_role()),
      'original_emploc_id', p_original_emploc_id,
      'submitted_at', NOW()
    )
  );

  RETURN v_req;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_withdraw_emploc_deletion_request(p_request_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_req     public.hr_emploc_deletion_requests;
  v_profile public.users_profile;
  v_name    text;
BEGIN
  SELECT * INTO v_req
  FROM public.hr_emploc_deletion_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'deletion request % not found', p_request_id USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'withdrawal not allowed: request is already %', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR v_req.requested_by_user_id = public.get_my_profile_id()
  ) THEN
    RAISE EXCEPTION 'forbidden: only the original requestor or Super Admin can withdraw'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_profile
  FROM public.users_profile
  WHERE id = public.get_my_profile_id();

  v_name := COALESCE(v_profile.full_name, public.get_my_full_name());

  UPDATE public.hr_emploc_deletion_requests
  SET status               = 'Withdrawn',
      withdrawn_at         = NOW(),
      withdrawn_by         = v_name,
      withdrawn_by_user_id = public.get_my_profile_id()
  WHERE id = p_request_id;

  INSERT INTO public.hr_emploc_deletion_activities (
    request_id,
    activity_type,
    performed_by,
    performed_by_user_id,
    remarks,
    snapshot
  ) VALUES (
    p_request_id,
    'Request Withdrawn',
    v_name,
    public.get_my_profile_id(),
    p_reason,
    jsonb_build_object(
      'withdrawn_by', v_name,
      'withdrawn_at', NOW(),
      'withdrawal_reason', p_reason,
      'prior_status', 'Pending',
      'hr_status_restored', v_req.original_hr_status,
      'snapshot_last_name', v_req.snapshot_last_name,
      'snapshot_first_name', v_req.snapshot_first_name,
      'vcode', v_req.vcode,
      'snapshot_store', v_req.snapshot_store,
      'snapshot_position', v_req.snapshot_position,
      'reason_original', v_req.reason,
      'requested_by', v_req.requested_by
    )
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_active_acting_session()
 RETURNS public.acting_sessions
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select s.*
    from public.acting_sessions s
    where s.user_id = auth.uid()
      and s.is_active = true
      and s.expires_at > now()
    order by s.created_at desc
    limit 1;
$function$
;

create or replace view "public"."headcount_summary" as  WITH emp AS (
         SELECT plantilla.account,
            count(*) FILTER (WHERE (plantilla.status = 'Active'::text)) AS active_employees,
            count(*) FILTER (WHERE (plantilla.status = 'Resigned'::text)) AS resigned_employees
           FROM public.plantilla
          GROUP BY plantilla.account
        ), vac AS (
         SELECT vacancies.account,
            count(*) FILTER (WHERE (vacancies.status = 'Open'::text)) AS open_vacancies,
            count(*) FILTER (WHERE (vacancies.status = 'Filled'::text)) AS filled_vacancies
           FROM public.vacancies
          WHERE (vacancies.is_archived = false)
          GROUP BY vacancies.account
        ), ep AS (
         SELECT hr_emploc.account,
            count(*) FILTER (WHERE (hr_emploc.hr_status = 'Pending'::text)) AS pending_emploc
           FROM public.hr_emploc
          GROUP BY hr_emploc.account
        )
 SELECT a.account_name,
    g.group_name,
    COALESCE(emp.active_employees, (0)::bigint) AS active_employees,
    COALESCE(emp.resigned_employees, (0)::bigint) AS resigned_employees,
    COALESCE(vac.open_vacancies, (0)::bigint) AS open_vacancies,
    COALESCE(vac.filled_vacancies, (0)::bigint) AS filled_vacancies,
    COALESCE(ep.pending_emploc, (0)::bigint) AS pending_emploc
   FROM ((((public.accounts a
     LEFT JOIN public.groups g ON ((g.id = a.group_id)))
     LEFT JOIN emp ON ((emp.account = a.account_name)))
     LEFT JOIN vac ON ((vac.account = a.account_name)))
     LEFT JOIN ep ON ((ep.account = a.account_name)))
  WHERE (a.is_active = true)
  ORDER BY g.group_name, a.account_name;


CREATE OR REPLACE FUNCTION public.mark_for_correction(p_id uuid, p_issues jsonb, p_hr_remarks text DEFAULT NULL::text)
 RETURNS public.hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old     public.hr_emploc;
  v_new     public.hr_emploc;
  v_issue   jsonb;
  v_code    text;
  v_comment text;
  v_needs_comment boolean;
BEGIN
  IF NOT (i_am_hr_dept() OR i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: HR Dept role required' USING ERRCODE = '42501';
  END IF;

  IF p_issues IS NULL
     OR jsonb_typeof(p_issues) <> 'array'
     OR jsonb_array_length(p_issues) = 0 THEN
    RAISE EXCEPTION 'p_issues must be a non-empty JSONB array of {code, comment} objects'
      USING ERRCODE = '22023';
  END IF;

  FOR v_issue IN SELECT * FROM jsonb_array_elements(p_issues) LOOP
    v_code    := NULLIF(BTRIM(COALESCE(v_issue->>'code', '')), '');
    v_comment := BTRIM(COALESCE(v_issue->>'comment', ''));

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'each issue entry must include a non-empty code'
        USING ERRCODE = '22023';
    END IF;

    SELECT requires_comment
      INTO v_needs_comment
      FROM hr_emploc_issue_types
     WHERE code = v_code AND is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'unknown or inactive issue code: %', v_code
        USING ERRCODE = '22023';
    END IF;

    IF v_needs_comment AND v_comment = '' THEN
      RAISE EXCEPTION 'comment is required for issue code: %', v_code
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  SELECT * INTO v_old FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;

  UPDATE hr_emploc
     SET hr_status            = 'For Correction',
         status               = 'For Compliance',
         correction_reason    = p_issues,
         hr_remarks           = COALESCE(
                                  NULLIF(BTRIM(COALESCE(p_hr_remarks, '')), ''),
                                  hr_remarks
                                ),
         hr_reviewed_at       = now(),
         hr_reviewed_by       = get_my_full_name(),
         hr_reviewed_by_user_id = get_my_profile_id(),
         updated_at           = now(),
         updated_by           = get_my_profile_id()
   WHERE id = p_id
   RETURNING * INTO v_new;

  PERFORM log_audit_event('hr_emploc', 'UPDATE', p_id, to_jsonb(v_old), to_jsonb(v_new));
  RETURN v_new;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.move_to_plantilla(p_id uuid)
 RETURNS public.plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp             public.hr_emploc;
  v_pl              public.plantilla;
  v_actor           uuid := get_my_profile_id();
  v_is_pool         boolean := false;
  v_pool_type_id    uuid;
  v_home_account_id uuid;
  v_home_acct       public.accounts;
BEGIN
  -- Data Team = Encoder + Head Admin + Super Admin
  IF NOT (i_have_full_access() OR get_my_role() = 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % not found or archived', p_id USING ERRCODE = 'P0002';
  END IF;
  IF v_emp.status <> 'Ready for Plantilla' THEN
    RAISE EXCEPTION 'cannot move: status is "%", expected "Ready for Plantilla"', v_emp.status
      USING ERRCODE = '22023';
  END IF;
  IF v_emp.employee_no IS NULL THEN
    RAISE EXCEPTION 'cannot move: employee_no is null' USING ERRCODE = '22023';
  END IF;

  -- Guard A: hr_emploc_id already active in plantilla
  IF EXISTS (
    SELECT 1
      FROM public.plantilla
     WHERE hr_emploc_id         = p_id
       AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION 'hr_emploc % already moved to plantilla', p_id USING ERRCODE = '23505';
  END IF;

  -- Guard B: moved_to_plantilla_at already stamped
  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION
      'hr_emploc % already has moved_to_plantilla_at set', p_id USING ERRCODE = '23505';
  END IF;

  -- Detect pool vacancy
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  -- ── POOL PATH ───────────────────────────────────────────────────────────────
  IF v_is_pool THEN

    IF v_home_account_id IS NULL THEN
      RAISE EXCEPTION 'pool vacancy % has no home_account_id — cannot route to pool',
        v_emp.vcode USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'home account % not found', v_home_account_id USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE employee_no = v_emp.employee_no
         AND account_id  = v_home_account_id
         AND is_deleted  = false
         AND status IN ('Active', 'For Deactivation', 'On Leave')
    ) THEN
      RAISE EXCEPTION
        'pool plantilla already has active record for employee_no % under home account',
        v_emp.employee_no USING ERRCODE = '23505';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,
      store_id,             store_name,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      is_pool_employee,     pool_type_id,
      requesting_account,   requesting_account_id,   requesting_store_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_home_acct.account_name, v_home_acct.id,
      NULL, NULL,
      v_emp.position,           v_emp.position_id_snapshot,
      v_emp.employee_no,        v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,       v_emp.philhealth_snapshot,    v_emp.pagibig_snapshot,
      v_emp.hired_date,         v_emp.vacancy_id,             v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,          v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot,  v_emp.area_name_snapshot,
      v_emp.id,
      true,                     v_pool_type_id,
      v_emp.account,            v_emp.account_id,             v_emp.store_id,
      'Active',                 CURRENT_DATE,
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    -- Close via vacancy_id if available
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    -- ── VCODE fallback: close any remaining Open vacancy for this VCODE ──────
    -- Covers the vacancy_id=NULL gap. Idempotent when vacancy already Filled.
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

    -- Mark pool slot occupied
    UPDATE public.workforce_pool_slots
       SET status     = 'filled',
           updated_at = NOW()
     WHERE vcode      = v_emp.vcode
       AND deleted_at IS NULL;

  -- ── ROVING PATH ─────────────────────────────────────────────────────────────
  ELSIF v_emp.assignment_type = 'Roving' THEN

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE roving_assignment_id = v_emp.roving_assignment_id
         AND is_deleted = false
    ) THEN
      RAISE EXCEPTION
        'roving plantilla master already exists for roving_assignment_id %. '
        'Use link_late_store_to_plantilla for new store additions.',
        v_emp.roving_assignment_id USING ERRCODE = '23505';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM hr_emploc_store_links
       WHERE hr_emploc_id = p_id
         AND status       = 'Confirmed'
         AND deleted_at   IS NULL
    ) THEN
      RAISE EXCEPTION 'no confirmed store links found for roving hr_emploc %', p_id
        USING ERRCODE = '22023';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,           chain_id,             province_id,
      position,             position_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,         pagibig_no,
      date_hired,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      roving_assignment_id,
      deployment_type,
      status,               tagged_at,
      moved_by_user_id,     created_by,            updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account, v_emp.account_id, v_emp.chain_id, v_emp.province_id,
      v_emp.position, v_emp.position_id_snapshot,
      v_emp.employee_no, v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot, v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,
      v_emp.hrco_name, v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      v_emp.roving_assignment_id,
      'Roving',
      'Active', CURRENT_DATE,
      v_actor, v_actor, v_actor,
      NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    INSERT INTO public.plantilla_store_links (
      plantilla_id,
      roving_assignment_id,
      hr_emploc_store_link_id,
      vacancy_id,
      vcode,
      store_name,
      account,
      status,
      linked_at,
      linked_by,
      created_by,
      updated_by
    )
    SELECT
      v_pl.id,
      sl.roving_assignment_id,
      sl.id,
      sl.vacancy_id,
      sl.vcode,
      sl.store_name,
      sl.account,
      'Active',
      NOW(),
      v_actor,
      v_actor,
      v_actor
    FROM public.hr_emploc_store_links sl
    WHERE sl.hr_emploc_id = p_id
      AND sl.status       = 'Confirmed'
      AND sl.deleted_at   IS NULL;

    -- Close confirmed store vacancies via vacancy_id
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE id IN (
       SELECT vacancy_id
         FROM public.hr_emploc_store_links
        WHERE hr_emploc_id = p_id
          AND status       = 'Confirmed'
          AND deleted_at   IS NULL
          AND vacancy_id   IS NOT NULL
     )
     AND status NOT IN ('Filled', 'Closed', 'Archived');

    -- ── VCODE fallback: close any remaining Open vacancy for the roving VCODE ─
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

  -- ── STATIONARY PATH ─────────────────────────────────────────────────────────
  ELSE

    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE employee_no = v_emp.employee_no
         AND is_deleted  = false
         AND status IN ('Active', 'For Deactivation', 'On Leave')
    ) THEN
      RAISE EXCEPTION 'plantilla already has active record for employee_no %',
        v_emp.employee_no USING ERRCODE = '23505';
    END IF;

    INSERT INTO plantilla (
      account,              account_id,            chain_id,             store_id,
      store_name,           position,              position_id,
      province_id,
      employee_no,          emploc_no,
      employee_name,        employee_name_snapshot,
      civil_status,         date_of_birth,
      sss_no,               philhealth_no,          pagibig_no,
      date_hired,           vacancy_id,              vacancy_code_snapshot,
      vcode,
      hrco_name,            hrco_user_id_snapshot,
      om_user_id_snapshot,  atl_user_id_snapshot,
      area,                 area_name_snapshot,
      hr_emploc_id,
      status,               tagged_at,
      moved_by_user_id,     created_by,              updated_by,
      created_at,           updated_at
    )
    VALUES (
      v_emp.account,        v_emp.account_id,       v_emp.chain_id,       v_emp.store_id,
      v_emp.store_name,     v_emp.position,         v_emp.position_id_snapshot,
      v_emp.province_id,
      v_emp.employee_no,    v_emp.employee_no,
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      COALESCE(v_emp.employee_name_snapshot, v_emp.applicant_name),
      v_emp.civil_status_snapshot, v_emp.birthdate_snapshot,
      v_emp.sss_snapshot,   v_emp.philhealth_snapshot, v_emp.pagibig_snapshot,
      v_emp.hired_date,     v_emp.vacancy_id,        v_emp.vacancy_code_snapshot,
      v_emp.vcode,
      v_emp.hrco_name,      v_emp.hrco_user_id_snapshot,
      v_emp.om_user_id_snapshot, v_emp.atl_user_id_snapshot,
      v_emp.area_name_snapshot, v_emp.area_name_snapshot,
      v_emp.id,
      'Active',             CURRENT_DATE,
      v_actor, v_actor, v_actor, NOW(), NOW()
    )
    RETURNING * INTO v_pl;

    -- Close via vacancy_id if available
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    -- ── VCODE fallback: close any remaining Open vacancy for this VCODE ──────
    -- Covers the vacancy_id=NULL gap. Idempotent when vacancy already Filled.
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE vcode      = v_emp.vcode
       AND status     IN ('Open', 'For Sourcing')
       AND COALESCE(is_archived, false) = false
       AND deleted_at IS NULL;

  END IF;

  -- ── Common: update hr_emploc status ─────────────────────────────────────────
  UPDATE hr_emploc
     SET status                = 'Moved to Plantilla',
         hr_status             = 'Transferred',
         moved_to_plantilla_at = NOW(),
         moved_to_plantilla_by = v_actor,
         updated_at            = NOW(),
         updated_by            = v_actor
   WHERE id = p_id;

  PERFORM log_audit_event('plantilla', 'INSERT', v_pl.id, NULL, to_jsonb(v_pl));
  PERFORM log_audit_event('hr_emploc', 'UPDATE', p_id, to_jsonb(v_emp),
                          to_jsonb((SELECT h FROM hr_emploc h WHERE h.id = p_id)));
  RETURN v_pl;
END
$function$
;

CREATE OR REPLACE FUNCTION public.plantilla_request_deactivation(p_plantilla_id uuid, p_reason text)
 RETURNS public.plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.plantilla;
begin
  if not public._can_act_on_plantilla(p_plantilla_id, 'request_deact') then
    raise exception 'forbidden: Ops role required for deactivation request' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'deactivation reason is required';
  end if;

  select * into v_row
  from public.plantilla
  where id = p_plantilla_id
    and coalesce(is_deleted, false) = false
  for update;

  if not found then
    raise exception 'plantilla not found';
  end if;

  if v_row.status = 'Active' then
    raise exception 'cannot deactivate an Active employee — separate first';
  end if;

  if not public.i_have_full_access()
     and not (v_row.account = any(public.get_my_allowed_accounts())) then
    raise exception 'forbidden: account out of scope' using errcode = '42501';
  end if;

  update public.plantilla
  set deactivated_at            = now(),
      deactivated_by            = auth.uid(),
      deactivated_visible_until = now() + interval '30 days',
      deactivation_reason       = p_reason,
      updated_by                = auth.uid(),
      updated_at                = now()
  where id = p_plantilla_id
  returning * into v_row;

  return v_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.plantilla_request_deletion(p_plantilla_id uuid, p_reason text, p_remarks text DEFAULT NULL::text)
 RETURNS public.plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_row public.plantilla;
BEGIN
  IF NOT public.i_can_act_on_plantilla() THEN
    RAISE EXCEPTION 'forbidden: insufficient role for deletion request';
  END IF;
  IF p_reason NOT IN ('Store Closed','Position No Longer Needed','Duplicate','Wrong Entry') THEN
    RAISE EXCEPTION 'invalid deletion_reason: %', p_reason;
  END IF;

  SELECT * INTO v_row FROM public.plantilla
  WHERE id = p_plantilla_id AND COALESCE(is_deleted, FALSE) = FALSE
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plantilla not found'; END IF;

  IF v_row.status = 'Active' THEN
    RAISE EXCEPTION 'cannot delete an Active employee';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_row.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: account out of scope';
  END IF;

  UPDATE public.plantilla
  SET deletion_requested_at = NOW(),
      deletion_requested_by = auth.uid(),
      deletion_reason       = p_reason,
      deletion_remarks      = p_remarks,
      updated_by            = auth.uid(),
      updated_at            = NOW()
  WHERE id = p_plantilla_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.plantilla_sync_mika(p_plantilla_id uuid, p_sss text DEFAULT NULL::text, p_philhealth text DEFAULT NULL::text, p_pagibig text DEFAULT NULL::text, p_atm text DEFAULT NULL::text, p_civil_status text DEFAULT NULL::text, p_date_of_birth date DEFAULT NULL::date)
 RETURNS public.plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.plantilla;
  v_role text := public.get_my_role();
begin
  if v_role = 'Viewer' then
    raise exception 'forbidden: viewer cannot sync MIKA data' using errcode = '42501';
  end if;

  select * into v_row
  from public.plantilla
  where id = p_plantilla_id
    and coalesce(is_deleted, false) = false
  for update;

  if not found then
    raise exception 'plantilla not found';
  end if;

  if not public.i_have_full_access()
     and not (v_row.account = any(public.get_my_allowed_accounts())) then
    raise exception 'forbidden: account out of scope' using errcode = '42501';
  end if;

  if v_row.last_mika_synced_at is not null
     and v_row.last_mika_synced_at > now() - interval '5 minutes' then
    raise exception 'MIKA sync cooldown active. Try again after 5 minutes.' using errcode = '42501';
  end if;

  update public.plantilla
  set sss_no              = coalesce(p_sss,           sss_no),
      philhealth_no       = coalesce(p_philhealth,    philhealth_no),
      pagibig_no          = coalesce(p_pagibig,       pagibig_no),
      atm_no              = coalesce(p_atm,           atm_no),
      civil_status        = coalesce(p_civil_status,  civil_status),
      date_of_birth       = coalesce(p_date_of_birth, date_of_birth),
      last_mika_synced_at = now(),
      last_mika_synced_by = auth.uid(),
      updated_by          = auth.uid(),
      updated_at          = now()
  where id = p_plantilla_id
  returning * into v_row;

  perform public._log_employee_action(
    p_plantilla_id,
    'MIKA_SYNC',
    format('%s synced MIKA data', public.get_my_full_name()),
    null,
    jsonb_build_object(
      'synced_by_role', v_role,
      'synced_at', now()
    )
  );

  return v_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.plantilla_transfer(p_plantilla_id uuid, p_target_store_id uuid, p_target_position_id uuid DEFAULT NULL::uuid, p_remarks text DEFAULT NULL::text)
 RETURNS public.plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row             public.plantilla;
  v_store           public.stores;
  v_position_id_eff uuid;
  v_filled_after    int;
  v_required_max    int;
begin
  if not public._can_act_on_plantilla(p_plantilla_id, 'reassign') then
    raise exception 'forbidden: Ops role required for plantilla transfer' using errcode = '42501';
  end if;

  select * into v_row
  from public.plantilla
  where id = p_plantilla_id
    and coalesce(is_deleted, false) = false
  for update;

  if not found then
    raise exception 'plantilla not found';
  end if;

  if not public.i_have_full_access()
     and not (v_row.account = any(public.get_my_allowed_accounts())) then
    raise exception 'forbidden: account out of scope' using errcode = '42501';
  end if;

  select * into v_store
  from public.stores
  where id = p_target_store_id;

  if not found then
    raise exception 'target store not found: %', p_target_store_id;
  end if;

  if v_store.account_id is distinct from v_row.account_id then
    raise exception 'cross-account transfer is not allowed';
  end if;

  v_position_id_eff := coalesce(p_target_position_id, v_row.position_id);

  update public.plantilla
  set store_id                  = v_store.id,
      store_name                = v_store.store_name,
      area                      = coalesce(v_store.area_city, area),
      province_id               = coalesce(v_store.id, province_id),
      transferred_from_store_id = v_row.store_id,
      last_transfer_at          = now(),
      last_transfer_by          = auth.uid(),
      position_id               = v_position_id_eff,
      remarks                   = coalesce(p_remarks, remarks),
      updated_by                = auth.uid(),
      updated_at                = now()
  where id = p_plantilla_id;

  select count(*) into v_filled_after
  from public.plantilla
  where store_id = v_store.id
    and position_id = v_position_id_eff
    and status = 'Active'
    and coalesce(is_deleted, false) = false;

  select coalesce(max(required_headcount), 0) into v_required_max
  from public.vacancies
  where store_id = v_store.id
    and position_id = v_position_id_eff;

  update public.plantilla
  set over_headcount = (v_required_max > 0 and v_filled_after > v_required_max)
  where id = p_plantilla_id
  returning * into v_row;

  return v_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.plantilla_update_separation(p_plantilla_id uuid, p_separation_status text, p_effective_date date, p_remarks text DEFAULT NULL::text)
 RETURNS public.plantilla
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.plantilla;
begin
  if not public._can_act_on_plantilla(p_plantilla_id, 'separate') then
    raise exception 'forbidden: Ops role required for plantilla status update' using errcode = '42501';
  end if;

  if p_effective_date is null then
    raise exception 'effective_date is required';
  end if;

  if p_separation_status not in ('Resigned','AWOL','Terminated','End of Contract','Endo','Others') then
    raise exception 'invalid separation_status: %', p_separation_status;
  end if;

  select * into v_row
  from public.plantilla
  where id = p_plantilla_id
    and coalesce(is_deleted, false) = false
  for update;

  if not found then
    raise exception 'plantilla not found: %', p_plantilla_id;
  end if;

  if not public.i_have_full_access()
     and not (v_row.account = any(public.get_my_allowed_accounts())) then
    raise exception 'forbidden: account out of scope' using errcode = '42501';
  end if;

  update public.plantilla
  set separation_status  = p_separation_status,
      date_of_separation = p_effective_date,
      status             = 'Inactive',
      remarks            = coalesce(p_remarks, remarks),
      updated_by         = auth.uid(),
      updated_at         = now()
  where id = p_plantilla_id
  returning * into v_row;

  return v_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.submit_correction(p_id uuid, p_ops_remark text)
 RETURNS public.hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old public.hr_emploc;
  v_new public.hr_emploc;
begin
  if not (i_am_ops() or i_have_full_access()) then
    raise exception 'forbidden: Ops role required' using errcode = '42501';
  end if;

  if coalesce(btrim(p_ops_remark),'') = '' then
    raise exception 'ops remark is required' using errcode = '22023';
  end if;

  select * into v_old
  from hr_emploc
  where id = p_id
  for update;

  if not found or v_old.deleted_at is not null then
    raise exception 'hr_emploc % not found or archived', p_id using errcode = 'P0002';
  end if;

  if v_old.hr_status <> 'For Correction' then
    raise exception 'cannot submit correction: hr_status is %', v_old.hr_status using errcode = '22023';
  end if;

  update hr_emploc
     set hr_status   = 'Pending',
         status      = 'Pending Emploc',
         ops_remarks = p_ops_remark,
         last_correction_submitter_user_id = get_my_profile_id(),
         updated_at  = now(),
         updated_by  = get_my_profile_id()
   where id = p_id
   returning * into v_new;

  perform log_audit_event('hr_emploc','UPDATE', p_id, to_jsonb(v_old), to_jsonb(v_new));
  return v_new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.tag_backout(p_id uuid, p_reason text, p_reason_code text DEFAULT NULL::text)
 RETURNS public.hr_emploc
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old           public.hr_emploc;
  v_new           public.hr_emploc;
  v_actor         uuid := get_my_profile_id();
  v_actor_name    text := get_my_full_name();
  v_vacancy_ids   uuid[] := ARRAY[]::uuid[];
  v_extra_ids     uuid[];
  v_vid           uuid;
  v_audit_payload jsonb;
BEGIN
  IF NOT (i_am_ops() OR i_have_full_access()) THEN
    RAISE EXCEPTION 'forbidden: Ops role required' USING ERRCODE = '42501';
  END IF;
  IF coalesce(btrim(p_reason),'') = '' THEN
    RAISE EXCEPTION 'backout reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_old FROM hr_emploc WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'hr_emploc % not found', p_id USING ERRCODE = 'P0002';
  END IF;
  IF v_old.status = 'Backout' OR v_old.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'hr_emploc % already backed-out', p_id USING ERRCODE = '22023';
  END IF;

  -- Collect linked vacancy IDs: primary + every covered_stores entry
  IF v_old.vacancy_id IS NOT NULL THEN
    v_vacancy_ids := array_append(v_vacancy_ids, v_old.vacancy_id);
  END IF;

  IF v_old.covered_stores IS NOT NULL
     AND jsonb_typeof(v_old.covered_stores) = 'array'
     AND jsonb_array_length(v_old.covered_stores) > 0 THEN
    SELECT array_agg(DISTINCT (e->>'vacancy_id')::uuid)
      INTO v_extra_ids
      FROM jsonb_array_elements(v_old.covered_stores) e
     WHERE e ? 'vacancy_id'
       AND nullif(e->>'vacancy_id','') IS NOT NULL;

    IF v_extra_ids IS NOT NULL THEN
      v_vacancy_ids := v_vacancy_ids || v_extra_ids;
    END IF;
  END IF;

  -- Mark HR Emploc record: BACKOUT (status) + close (deleted_at) + event fields
  UPDATE hr_emploc
     SET status              = 'Backout',
         hr_status           = 'Rejected',
         backout_date        = current_date,
         backout_at          = now(),
         backout_by          = v_actor,
         backout_details     = p_reason,
         backout_reason_code = coalesce(p_reason_code, backout_reason_code),
         deleted_at          = now(),
         updated_at          = now(),
         updated_by          = v_actor
   WHERE id = p_id
   RETURNING * INTO v_new;

  -- Reopen each linked vacancy WITHOUT touching vacant_date (SLA continues)
  FOREACH v_vid IN ARRAY v_vacancy_ids LOOP
    IF v_vid IS NOT NULL THEN
      UPDATE vacancies
         SET status                 = 'Open',
             closure_request_status = 'None',
             has_pending_closure    = false,
             archived_at            = NULL,
             archived_by            = NULL,
             is_archived            = false,
             updated_at             = now(),
             updated_by             = v_actor
       WHERE id = v_vid
         AND deleted_at IS NULL;
      -- vacant_date intentionally untouched — vacancy was never truly filled
    END IF;
  END LOOP;

  -- Mirror backout signal onto applicant snapshot (no archive)
  IF v_old.applicant_id IS NOT NULL THEN
    UPDATE applicants
       SET backout_date        = current_date,
           backout_reason      = p_reason,
           backout_reason_code = coalesce(p_reason_code, backout_reason_code),
           backout_details     = p_reason,
           status              = 'Backout',
           updated_at          = now(),
           updated_by          = v_actor
     WHERE id = v_old.applicant_id
       AND is_archived = false;
  END IF;

  -- BACKOUT audit event (rich payload in new_data)
  v_audit_payload := jsonb_build_object(
    'event_type',          'BACKOUT',
    'applicant_id',        v_old.applicant_id,
    'applicant_name',      coalesce(v_old.applicant_name_snapshot, v_old.applicant_name),
    'employee_no',         v_old.employee_no,
    'vcode',               v_old.vcode,
    'account',             v_old.account,
    'account_id',          v_old.account_id,
    'store_id',            v_old.store_id,
    'store_name',          v_old.store_name,
    'position',            v_old.position,
    'assignment_type',     v_old.assignment_type::text,
    'covered_stores',      v_old.covered_stores,
    'restored_vacancy_ids',to_jsonb(v_vacancy_ids),
    'reason',              p_reason,
    'reason_code',         p_reason_code,
    'triggered_by',        v_actor,
    'triggered_by_name',   v_actor_name,
    'triggered_at',        now()
  );

  INSERT INTO audit_logs(action, module, record_id, actor_id, role, old_data, new_data)
  VALUES ('BACKOUT'::audit_action, 'hr_emploc', p_id, v_actor, get_my_role(),
          to_jsonb(v_old), v_audit_payload);

  RETURN v_new;
END
$function$
;

create or replace view "public"."team_performance_summary" as  WITH week_bounds AS (
         SELECT date_trunc('week'::text, now()) AS curr_start,
            (date_trunc('week'::text, now()) + '7 days'::interval) AS curr_end,
            (date_trunc('week'::text, now()) - '7 days'::interval) AS prev_start,
            date_trunc('week'::text, now()) AS prev_end
        ), user_base AS (
         SELECT up.id,
            up.full_name,
            up.email,
            r.role_name,
            r.role_level
           FROM (public.users_profile up
             LEFT JOIN public.roles r ON ((r.id = up.role_id)))
          WHERE (up.is_active = true)
        ), curr_metrics AS (
         SELECT v.assigned_encoder_id AS user_id,
            count(*) AS total_tasks,
            count(*) FILTER (WHERE (v.status = ANY (ARRAY['Filled'::text, 'Closed'::text]))) AS done_tasks,
            avg((EXTRACT(epoch FROM (v.updated_at - v.created_at)) / 86400.0)) FILTER (WHERE (v.status = ANY (ARRAY['Filled'::text, 'Closed'::text]))) AS avg_days
           FROM public.vacancies v,
            week_bounds wb
          WHERE ((v.assigned_encoder_id IS NOT NULL) AND (v.is_archived = false) AND (v.created_at >= wb.curr_start) AND (v.created_at < wb.curr_end))
          GROUP BY v.assigned_encoder_id
        ), prev_metrics AS (
         SELECT v.assigned_encoder_id AS user_id,
            count(*) AS total_tasks,
            count(*) FILTER (WHERE (v.status = ANY (ARRAY['Filled'::text, 'Closed'::text]))) AS done_tasks,
            avg((EXTRACT(epoch FROM (v.updated_at - v.created_at)) / 86400.0)) FILTER (WHERE (v.status = ANY (ARRAY['Filled'::text, 'Closed'::text]))) AS avg_days
           FROM public.vacancies v,
            week_bounds wb
          WHERE ((v.assigned_encoder_id IS NOT NULL) AND (v.is_archived = false) AND (v.created_at >= wb.prev_start) AND (v.created_at < wb.prev_end))
          GROUP BY v.assigned_encoder_id
        ), curr_norm AS (
         SELECT (NULLIF(max(curr_metrics.done_tasks), 0))::numeric AS max_volume,
            NULLIF(max(curr_metrics.avg_days), (0)::numeric) AS max_speed_days
           FROM curr_metrics
        ), prev_norm AS (
         SELECT (NULLIF(max(prev_metrics.done_tasks), 0))::numeric AS max_volume,
            NULLIF(max(prev_metrics.avg_days), (0)::numeric) AS max_speed_days
           FROM prev_metrics
        ), curr_scored AS (
         SELECT cm.user_id,
            cm.total_tasks,
            cm.done_tasks,
            cm.avg_days,
                CASE
                    WHEN (cm.total_tasks > 0) THEN ((cm.done_tasks)::numeric / (cm.total_tasks)::numeric)
                    ELSE (0)::numeric
                END AS completion_rate,
                CASE
                    WHEN ((cn.max_speed_days IS NULL) OR (cm.avg_days IS NULL)) THEN (0)::numeric
                    ELSE GREATEST((0)::numeric, ((1)::numeric - (cm.avg_days / cn.max_speed_days)))
                END AS speed_score,
                CASE
                    WHEN (cn.max_volume IS NULL) THEN (0)::numeric
                    ELSE ((cm.done_tasks)::numeric / cn.max_volume)
                END AS volume_score
           FROM (curr_metrics cm
             CROSS JOIN curr_norm cn)
        ), prev_scored AS (
         SELECT pm.user_id,
                CASE
                    WHEN (pm.total_tasks > 0) THEN ((pm.done_tasks)::numeric / (pm.total_tasks)::numeric)
                    ELSE (0)::numeric
                END AS completion_rate,
                CASE
                    WHEN ((pn.max_speed_days IS NULL) OR (pm.avg_days IS NULL)) THEN (0)::numeric
                    ELSE GREATEST((0)::numeric, ((1)::numeric - (pm.avg_days / pn.max_speed_days)))
                END AS speed_score,
                CASE
                    WHEN (pn.max_volume IS NULL) THEN (0)::numeric
                    ELSE ((pm.done_tasks)::numeric / pn.max_volume)
                END AS volume_score
           FROM (prev_metrics pm
             CROSS JOIN prev_norm pn)
        ), curr_wpi AS (
         SELECT curr_scored.user_id,
            curr_scored.total_tasks,
            curr_scored.done_tasks,
            curr_scored.avg_days,
            curr_scored.completion_rate,
            curr_scored.speed_score,
            curr_scored.volume_score,
            round((((curr_scored.completion_rate * 0.4) + (curr_scored.speed_score * 0.3)) + (curr_scored.volume_score * 0.3)), 4) AS wpi
           FROM curr_scored
        ), prev_wpi AS (
         SELECT prev_scored.user_id,
            round((((prev_scored.completion_rate * 0.4) + (prev_scored.speed_score * 0.3)) + (prev_scored.volume_score * 0.3)), 4) AS wpi
           FROM prev_scored
        )
 SELECT ub.id AS user_id,
    ub.full_name,
    ub.email,
    ub.role_name,
    ub.role_level,
    COALESCE(cw.total_tasks, (0)::bigint) AS total_tasks,
    COALESCE(cw.done_tasks, (0)::bigint) AS completed_tasks,
    round(COALESCE(cw.completion_rate, (0)::numeric), 4) AS completion_rate,
    round(COALESCE(cw.avg_days, (0)::numeric), 2) AS avg_completion_days,
    round(COALESCE(cw.speed_score, (0)::numeric), 4) AS speed_score,
    round(COALESCE(cw.volume_score, (0)::numeric), 4) AS volume_score,
    COALESCE(cw.wpi, (0)::numeric) AS wpi_current,
    COALESCE(pw.wpi, (0)::numeric) AS wpi_previous,
    round((COALESCE(cw.wpi, (0)::numeric) - COALESCE(pw.wpi, (0)::numeric)), 4) AS wpi_delta,
        CASE
            WHEN ((COALESCE(pw.wpi, (0)::numeric) = (0)::numeric) AND (COALESCE(cw.wpi, (0)::numeric) > 0.02)) THEN 'up'::text
            WHEN (COALESCE(pw.wpi, (0)::numeric) = (0)::numeric) THEN 'stable'::text
            WHEN (((COALESCE(cw.wpi, (0)::numeric) - pw.wpi) / pw.wpi) > 0.02) THEN 'up'::text
            WHEN (((COALESCE(cw.wpi, (0)::numeric) - pw.wpi) / pw.wpi) < '-0.02'::numeric) THEN 'down'::text
            ELSE 'stable'::text
        END AS trend
   FROM ((user_base ub
     LEFT JOIN curr_wpi cw ON ((cw.user_id = ub.id)))
     LEFT JOIN prev_wpi pw ON ((pw.user_id = ub.id)))
  WHERE ((cw.user_id IS NOT NULL) OR (pw.user_id IS NOT NULL));


create or replace view "public"."team_performance_view" as  WITH user_base AS (
         SELECT up.id AS profile_id,
            up.auth_user_id AS auth_uid,
            up.full_name,
            r.role_name AS role,
            up.group_id
           FROM (public.users_profile up
             JOIN public.roles r ON ((r.id = up.role_id)))
          WHERE ((up.is_active = true) AND (r.role_name = ANY (ARRAY['HRCO'::text, 'ATL'::text, 'TL'::text, 'Operations Manager'::text])))
        ), perf AS (
         SELECT ub.profile_id,
            ub.auth_uid,
            ub.full_name,
            ub.role,
            ub.group_id,
            (COALESCE(( SELECT sum(v.required_headcount) AS sum
                   FROM public.vacancies v
                  WHERE (((v.is_archived IS NULL) OR (v.is_archived = false)) AND (((ub.role = 'HRCO'::text) AND (v.hrco_user_id = ub.profile_id)) OR ((ub.role = 'ATL'::text) AND (v.atl_user_id = ub.profile_id)) OR ((ub.role = 'Operations Manager'::text) AND (v.om_user_id = ub.profile_id)) OR ((ub.role = 'TL'::text) AND (v.account_id IN ( SELECT us.account_id
                           FROM public.user_scopes us
                          WHERE ((us.user_id = ub.profile_id) AND (us.account_id IS NOT NULL)))))))), (0)::bigint))::integer AS required_count,
            (COALESCE(( SELECT count(*) AS count
                   FROM public.plantilla p
                  WHERE ((p.status = 'Active'::text) AND (((ub.role = 'HRCO'::text) AND (p.hrco_user_id_snapshot = ub.profile_id)) OR ((ub.role = 'ATL'::text) AND (p.atl_user_id_snapshot = ub.profile_id)) OR ((ub.role = 'Operations Manager'::text) AND (p.om_user_id_snapshot = ub.profile_id)) OR ((ub.role = 'TL'::text) AND (p.account_id IN ( SELECT us.account_id
                           FROM public.user_scopes us
                          WHERE ((us.user_id = ub.profile_id) AND (us.account_id IS NOT NULL)))))))), (0)::bigint))::integer AS actual_count,
            (COALESCE(( SELECT count(*) AS count
                   FROM public.hr_emploc he
                  WHERE ((he.status <> 'Moved to Plantilla'::text) AND (((ub.role = 'HRCO'::text) AND (he.hrco_user_id_snapshot = ub.profile_id)) OR ((ub.role = 'ATL'::text) AND (he.atl_user_id_snapshot = ub.profile_id)) OR ((ub.role = 'Operations Manager'::text) AND (he.om_user_id_snapshot = ub.profile_id)) OR ((ub.role = 'TL'::text) AND (he.account_id IN ( SELECT us.account_id
                           FROM public.user_scopes us
                          WHERE ((us.user_id = ub.profile_id) AND (us.account_id IS NOT NULL)))))))), (0)::bigint))::integer AS hr_emploc_count
           FROM user_base ub
        )
 SELECT profile_id,
    auth_uid,
    full_name,
    role,
    group_id,
    required_count,
    actual_count,
    hr_emploc_count,
    GREATEST((required_count - (actual_count + hr_emploc_count)), 0) AS vacant_count,
        CASE
            WHEN (required_count = 0) THEN NULL::numeric
            ELSE round((((actual_count)::numeric / (required_count)::numeric) * (100)::numeric), 2)
        END AS mfr,
        CASE
            WHEN (required_count = 0) THEN NULL::numeric
            ELSE round((((hr_emploc_count)::numeric / (required_count)::numeric) * (100)::numeric), 2)
        END AS pipeline_percent,
        CASE
            WHEN (required_count = 0) THEN 'No Data'::text
            WHEN (round((((actual_count)::numeric / (required_count)::numeric) * (100)::numeric), 2) >= (95)::numeric) THEN 'Excellent'::text
            WHEN (round((((actual_count)::numeric / (required_count)::numeric) * (100)::numeric), 2) >= (80)::numeric) THEN 'Needs Attention'::text
            ELSE 'Critical'::text
        END AS perf_status,
        CASE
            WHEN (required_count = 0) THEN 'No Required Set'::text
            WHEN ((round((((actual_count)::numeric / (required_count)::numeric) * (100)::numeric), 2) < (80)::numeric) AND (hr_emploc_count = 0)) THEN 'CRITICAL: No Pipeline'::text
            WHEN ((round((((actual_count)::numeric / (required_count)::numeric) * (100)::numeric), 2) < (80)::numeric) AND (hr_emploc_count > 0)) THEN 'In Progress'::text
            WHEN (GREATEST((required_count - (actual_count + hr_emploc_count)), 0) > 0) THEN 'Vacant Warning'::text
            ELSE NULL::text
        END AS alert_flag
   FROM perf;


CREATE OR REPLACE FUNCTION public.tg_hr_emploc_pending_deletion_lock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_emploc_deletion_requests
    WHERE hr_emploc_id = NEW.id
      AND status = 'Pending'
  ) THEN
    IF NEW.status = 'Moved to Plantilla'
       AND OLD.status <> 'Moved to Plantilla'
    THEN
      RAISE EXCEPTION 'cannot move to Plantilla: a pending deletion request exists for this record'
        USING ERRCODE = 'P0001';
    END IF;

    IF NEW.employee_no IS DISTINCT FROM OLD.employee_no
       AND NEW.employee_no IS NOT NULL
    THEN
      RAISE EXCEPTION 'action locked: a pending deletion request exists'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

create or replace view "public"."transfer_requests" as  SELECT id,
    emploc_no,
    employee_name,
    from_account,
    from_store,
    from_vcode,
    to_account,
    to_store,
    to_vcode,
    transfer_date,
    reason,
    requested_by,
    requested_by_role,
    status,
    reviewed_by,
    reviewed_at,
    reviewer_remarks,
    is_deleted,
    updated_at,
    created_at
   FROM public.employee_transfers
  WHERE (is_deleted = false);


create or replace view "public"."v_account_kpi" as  WITH actual AS (
         SELECT p.account_id,
            count(*) FILTER (WHERE (p.status = 'Active'::text)) AS actual_hc
           FROM public.plantilla p
          WHERE ((COALESCE(p.is_deleted, false) = false) AND (COALESCE(p.is_pool_employee, false) = false))
          GROUP BY p.account_id
        ), pipeline AS (
         SELECT he.account_id,
            count(*) AS pipeline_count
           FROM (public.hr_emploc he
             LEFT JOIN public.vacancies v ON ((v.id = he.vacancy_id)))
          WHERE ((he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])) AND (he.deleted_at IS NULL) AND (COALESCE(v.is_pool_vacancy, false) = false))
          GROUP BY he.account_id
        ), vacant AS (
         SELECT vacancies.account_id,
            count(*) AS vacant_count
           FROM public.vacancies
          WHERE ((vacancies.status = 'Open'::text) AND (COALESCE(vacancies.is_archived, false) = false) AND (COALESCE(vacancies.is_pool_vacancy, false) = false))
          GROUP BY vacancies.account_id
        ), base AS (
         SELECT a.id AS account_id,
            a.account_name,
            a.account_code,
            a.group_id,
            g.group_name,
            g.group_code,
            COALESCE(ac.actual_hc, (0)::bigint) AS actual_hc,
            COALESCE(p.pipeline_count, (0)::bigint) AS pipeline_count,
            COALESCE(v.vacant_count, (0)::bigint) AS vacant_count,
            ((COALESCE(ac.actual_hc, (0)::bigint) + COALESCE(p.pipeline_count, (0)::bigint)) + COALESCE(v.vacant_count, (0)::bigint)) AS required_hc
           FROM ((((public.accounts a
             LEFT JOIN public.groups g ON ((g.id = a.group_id)))
             LEFT JOIN actual ac ON ((ac.account_id = a.id)))
             LEFT JOIN pipeline p ON ((p.account_id = a.id)))
             LEFT JOIN vacant v ON ((v.account_id = a.id)))
          WHERE ((a.is_active = true) AND (COALESCE(a.is_pool_account, false) = false) AND (public.i_have_full_access() OR ((a.id)::text = ANY (public.get_my_allowed_accounts()))))
        )
 SELECT account_id,
    account_name,
    account_code,
    group_id,
    group_name,
    group_code,
    actual_hc,
    pipeline_count,
    vacant_count,
    required_hc,
        CASE
            WHEN (required_hc = 0) THEN 1.0
            ELSE round(((actual_hc)::numeric / (required_hc)::numeric), 4)
        END AS mfr,
        CASE
            WHEN (required_hc = 0) THEN 1.0
            ELSE round((((actual_hc + pipeline_count))::numeric / (required_hc)::numeric), 4)
        END AS projected_mfr,
        CASE
            WHEN (required_hc = 0) THEN 0.0
            ELSE round(((vacant_count)::numeric / (required_hc)::numeric), 4)
        END AS vacancy_rate,
        CASE
            WHEN (required_hc = 0) THEN 0.0
            ELSE round(((pipeline_count)::numeric / (required_hc)::numeric), 4)
        END AS pipeline_coverage,
        CASE
            WHEN (required_hc = 0) THEN 'healthy'::text
            WHEN (((actual_hc)::numeric / (required_hc)::numeric) >= 1.0) THEN 'healthy'::text
            WHEN (((actual_hc)::numeric / (required_hc)::numeric) >= 0.9) THEN 'at_risk'::text
            ELSE 'critical'::text
        END AS health_status
   FROM base;


create or replace view "public"."v_account_position_options" as  SELECT ap.account_id,
    a.account_name,
    a.group_id,
    g.group_code,
    g.group_name,
    p.id AS position_id,
    p.position_name,
    p.position_code,
    p.is_active,
    ap.created_at AS mapped_at
   FROM (((public.account_positions ap
     JOIN public.accounts a ON ((a.id = ap.account_id)))
     JOIN public.positions p ON ((p.id = ap.position_id)))
     LEFT JOIN public.groups g ON ((g.id = a.group_id)))
  WHERE ((COALESCE(p.is_active, true) = true) AND (COALESCE(a.is_active, true) = true));


create or replace view "public"."v_approval_queue" as  SELECT id,
    auth_user_id,
    email,
    full_name,
    requested_role_id,
    status,
    notes,
    reviewed_by,
    reviewed_at,
    created_at,
    updated_at,
    assigned_scope_type,
    assigned_role_id,
    approved_by,
    approved_at,
    rejected_by,
    rejected_at,
    rejection_reason,
    assigned_groups_snapshot,
    assigned_accounts_snapshot
   FROM public.account_requests ar;


create or replace view "public"."v_audit_activity_feed" as  SELECT al.id,
    al."timestamp" AS created_at,
    al.module AS table_name,
    COALESCE((al.new_data ->> 'vcode'::text), (al.old_data ->> 'vcode'::text), (al.record_id)::text) AS record_id,
    (al.action)::text AS action,
    al.actor_id,
    jsonb_build_object('before', al.old_data, 'after', al.new_data) AS changes,
    COALESCE(up.full_name, 'System'::text) AS actor_name,
    r.role_name AS actor_role,
        CASE
            WHEN (al.module = 'applicants'::text) THEN COALESCE((al.new_data ->> 'full_name'::text), NULLIF(TRIM(BOTH FROM concat_ws(' '::text, (al.new_data ->> 'first_name'::text), (al.new_data ->> 'last_name'::text))), ''::text), (al.old_data ->> 'full_name'::text), 'Applicant'::text)
            WHEN (al.module = 'vacancies'::text) THEN COALESCE((al.new_data ->> 'vcode'::text), (al.old_data ->> 'vcode'::text), (al.record_id)::text)
            WHEN (al.module = ANY (ARRAY['hr_emploc'::text, 'plantilla'::text])) THEN COALESCE((al.new_data ->> 'employee_no'::text), (al.new_data ->> 'full_name'::text), (al.new_data ->> 'vcode'::text), (al.record_id)::text)
            ELSE (al.record_id)::text
        END AS subject_label,
    (al.old_data ->> 'status'::text) AS old_status,
    (al.new_data ->> 'status'::text) AS new_status
   FROM ((public.audit_logs al
     LEFT JOIN public.users_profile up ON ((up.auth_user_id = al.actor_id)))
     LEFT JOIN public.roles r ON ((r.id = up.role_id)));


create or replace view "public"."v_cencom_account_kpi" as  SELECT ak.account_id,
    ak.account_name,
    ak.account_code,
    ak.group_id,
    ak.group_name,
    ak.group_code,
    ak.actual_hc,
    ak.pipeline_count,
    ak.vacant_count,
    ak.required_hc,
    ak.mfr,
    ak.projected_mfr,
    ak.vacancy_rate,
    ak.pipeline_coverage,
    ak.health_status
   FROM (public.v_account_kpi ak
     JOIN public.groups g ON ((g.id = ak.group_id)))
  WHERE (g.cencom_scope = true);


create or replace view "public"."v_cencom_group_kpi" as  SELECT group_id,
    group_name,
    group_code,
    (sum(actual_hc))::bigint AS actual_hc,
    (sum(pipeline_count))::bigint AS pipeline_count,
    (sum(vacant_count))::bigint AS vacant_count,
    (sum(required_hc))::bigint AS required_hc,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 1.0
            ELSE round((sum(actual_hc) / sum(required_hc)), 4)
        END AS mfr,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 1.0
            ELSE round(((sum(actual_hc) + sum(pipeline_count)) / sum(required_hc)), 4)
        END AS projected_mfr,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 0.0
            ELSE round((sum(vacant_count) / sum(required_hc)), 4)
        END AS vacancy_rate,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 0.0
            ELSE round((sum(pipeline_count) / sum(required_hc)), 4)
        END AS pipeline_coverage,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 'healthy'::text
            WHEN ((sum(actual_hc) / sum(required_hc)) >= 1.0) THEN 'healthy'::text
            WHEN ((sum(actual_hc) / sum(required_hc)) >= 0.9) THEN 'at_risk'::text
            ELSE 'critical'::text
        END AS health_status
   FROM public.v_cencom_account_kpi
  GROUP BY group_id, group_name, group_code;


create or replace view "public"."v_cencom_kpi" as  SELECT (sum(actual_hc))::bigint AS actual_hc,
    (sum(pipeline_count))::bigint AS pipeline_count,
    (sum(vacant_count))::bigint AS vacant_count,
    (sum(required_hc))::bigint AS required_hc,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 1.0
            ELSE round((sum(actual_hc) / sum(required_hc)), 4)
        END AS mfr,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 1.0
            ELSE round(((sum(actual_hc) + sum(pipeline_count)) / sum(required_hc)), 4)
        END AS projected_mfr,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 0.0
            ELSE round((sum(vacant_count) / sum(required_hc)), 4)
        END AS vacancy_rate,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 0.0
            ELSE round((sum(pipeline_count) / sum(required_hc)), 4)
        END AS pipeline_coverage,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 'healthy'::text
            WHEN ((sum(actual_hc) / sum(required_hc)) >= 1.0) THEN 'healthy'::text
            WHEN ((sum(actual_hc) / sum(required_hc)) >= 0.9) THEN 'at_risk'::text
            ELSE 'critical'::text
        END AS health_status
   FROM public.v_cencom_account_kpi;


create or replace view "public"."v_cencom_td_vacancies" as  SELECT v.id AS vacancy_id,
    v.vcode,
    v.account,
    v.account_id,
    v."position",
    COALESCE(v.area_name, v.area_city) AS area_name,
    COALESCE(v.store_name, v.store_branch) AS store_name,
    v.vacant_date,
    v.vacancy_type,
    COALESCE(v.urgency_level, 'Normal'::text) AS urgency_level,
    v.target_fill_date,
    v.required_headcount,
    v.source,
    ak.group_id,
    ak.group_name,
    ak.group_code,
    ak.mfr AS account_mfr,
    ak.actual_hc AS account_actual_hc,
    ak.required_hc AS account_required_hc,
    ak.health_status AS account_health_status,
    ((v.vacant_date IS NULL) OR (v.vacant_date > CURRENT_DATE)) AS is_advance_vacancy,
        CASE
            WHEN ((v.vacant_date IS NULL) OR (v.vacant_date > CURRENT_DATE)) THEN NULL::integer
            ELSE GREATEST(0, (CURRENT_DATE - v.vacant_date))
        END AS aging_days,
    public.fn_cencom_td_aging_bucket(
        CASE
            WHEN ((v.vacant_date IS NULL) OR (v.vacant_date > CURRENT_DATE)) THEN NULL::integer
            ELSE GREATEST(0, (CURRENT_DATE - v.vacant_date))
        END, ((v.vacant_date IS NULL) OR (v.vacant_date > CURRENT_DATE))) AS aging_bucket,
    public.fn_cencom_td_priority_score(
        CASE
            WHEN ((v.vacant_date IS NULL) OR (v.vacant_date > CURRENT_DATE)) THEN NULL::integer
            ELSE GREATEST(0, (CURRENT_DATE - v.vacant_date))
        END, COALESCE(v.urgency_level, 'Normal'::text), v.required_headcount, ak.mfr) AS priority_score,
        CASE
            WHEN (COALESCE(ak.mfr, 1.0) < 0.75) THEN 'critical'::text
            WHEN (COALESCE(ak.mfr, 1.0) < 0.85) THEN 'at_risk'::text
            WHEN (COALESCE(ak.mfr, 1.0) < 0.90) THEN 'elevated'::text
            ELSE 'healthy'::text
        END AS account_health_tier,
        CASE
            WHEN ((v.vacant_date IS NULL) OR (v.vacant_date > CURRENT_DATE)) THEN 'advance'::text
            WHEN ((GREATEST(0, (CURRENT_DATE - v.vacant_date)) >= 61) AND (COALESCE(ak.mfr, 1.0) < 0.85)) THEN 'immediate'::text
            WHEN ((GREATEST(0, (CURRENT_DATE - v.vacant_date)) >= 31) OR (COALESCE(ak.mfr, 1.0) < 0.80)) THEN 'critical'::text
            WHEN ((GREATEST(0, (CURRENT_DATE - v.vacant_date)) >= 16) OR (COALESCE(ak.mfr, 1.0) < 0.90)) THEN 'elevated'::text
            ELSE 'normal'::text
        END AS urgency_tier
   FROM (public.vacancies v
     JOIN public.v_cencom_account_kpi ak ON ((ak.account_id = v.account_id)))
  WHERE ((v.status = ANY (ARRAY['Open'::text, 'For Sourcing'::text])) AND (COALESCE(v.is_archived, false) = false) AND (v.deleted_at IS NULL));


create or replace view "public"."v_group_kpi" as  SELECT group_id,
    group_name,
    group_code,
    (sum(actual_hc))::bigint AS actual_hc,
    (sum(pipeline_count))::bigint AS pipeline_count,
    (sum(vacant_count))::bigint AS vacant_count,
    (sum(required_hc))::bigint AS required_hc,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 1.0
            ELSE round((sum(actual_hc) / sum(required_hc)), 4)
        END AS mfr,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 1.0
            ELSE round(((sum(actual_hc) + sum(pipeline_count)) / sum(required_hc)), 4)
        END AS projected_mfr,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 0.0
            ELSE round((sum(vacant_count) / sum(required_hc)), 4)
        END AS vacancy_rate,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 0.0
            ELSE round((sum(pipeline_count) / sum(required_hc)), 4)
        END AS pipeline_coverage,
        CASE
            WHEN (sum(required_hc) = (0)::numeric) THEN 'healthy'::text
            WHEN ((sum(actual_hc) / sum(required_hc)) >= 1.0) THEN 'healthy'::text
            WHEN ((sum(actual_hc) / sum(required_hc)) >= 0.9) THEN 'at_risk'::text
            ELSE 'critical'::text
        END AS health_status
   FROM public.v_account_kpi
  GROUP BY group_id, group_name, group_code;


create or replace view "public"."v_hr_emploc_backout_report" as  SELECT a.group_id,
    g.group_code,
    g.group_name,
    h.account_id,
    h.account,
    h.store_id,
    h.store_name,
    h.position_id_snapshot AS position_id,
    h."position",
    date_trunc('month'::text, h.backout_at) AS backout_month,
    count(*) AS backout_count
   FROM ((public.hr_emploc h
     LEFT JOIN public.accounts a ON ((a.id = h.account_id)))
     LEFT JOIN public.groups g ON ((g.id = a.group_id)))
  WHERE ((h.status = 'Backout'::text) AND (h.backout_at IS NOT NULL))
  GROUP BY a.group_id, g.group_code, g.group_name, h.account_id, h.account, h.store_id, h.store_name, h.position_id_snapshot, h."position", (date_trunc('month'::text, h.backout_at));


create or replace view "public"."v_hr_emploc_sla_flags" as  SELECT id,
    applicant_id,
    applicant_name,
    vcode,
    account,
    account_id,
    store_id,
    store_name,
    "position",
    status,
    hr_status,
    employee_no,
    date_requested,
    created_at,
    assignment_type,
    roving_assignment_id,
    GREATEST(0, (EXTRACT(day FROM (now() - COALESCE(date_requested, created_at))))::integer) AS aging_days,
    ((deleted_at IS NULL) AND (employee_no IS NULL) AND (status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'In Review'::text])) AND (COALESCE(date_requested, created_at) < (now() - '3 days'::interval))) AS sla_breached,
    (COALESCE(( SELECT count(*) AS count
           FROM public.hr_emploc_store_links sl
          WHERE ((sl.hr_emploc_id = h.id) AND (sl.deleted_at IS NULL))), (0)::bigint))::integer AS roving_store_count,
    (COALESCE(( SELECT count(*) AS count
           FROM public.hr_emploc_store_links sl
          WHERE ((sl.hr_emploc_id = h.id) AND (sl.deleted_at IS NULL) AND (sl.status = 'Confirmed'::text))), (0)::bigint))::integer AS roving_confirmed_count,
    ( SELECT jsonb_agg(jsonb_build_object('vcode', sl.vcode, 'store_name', sl.store_name, 'status', sl.status, 'confirmed_at', sl.confirmed_at) ORDER BY sl.vcode) AS jsonb_agg
           FROM public.hr_emploc_store_links sl
          WHERE ((sl.hr_emploc_id = h.id) AND (sl.deleted_at IS NULL))) AS roving_stores
   FROM public.hr_emploc h
  WHERE (deleted_at IS NULL);


create or replace view "public"."v_mika_import_rows_safe" as  SELECT id,
    import_log_id,
    employee_no,
    account,
    store_name,
    last_name,
    first_name,
    middle_name,
    "position",
    contact_number,
        CASE
            WHEN ((sss_no IS NULL) OR (length(regexp_replace(sss_no, '\\D'::text, ''::text, 'g'::text)) <= 4)) THEN sss_no
            ELSE (repeat('*'::text, GREATEST((length(sss_no) - 4), 0)) || "right"(sss_no, 4))
        END AS sss_no_masked,
        CASE
            WHEN ((philhealth_no IS NULL) OR (length(regexp_replace(philhealth_no, '\\D'::text, ''::text, 'g'::text)) <= 4)) THEN philhealth_no
            ELSE (repeat('*'::text, GREATEST((length(philhealth_no) - 4), 0)) || "right"(philhealth_no, 4))
        END AS philhealth_no_masked,
        CASE
            WHEN ((pagibig_no IS NULL) OR (length(regexp_replace(pagibig_no, '\\D'::text, ''::text, 'g'::text)) <= 4)) THEN pagibig_no
            ELSE (repeat('*'::text, GREATEST((length(pagibig_no) - 4), 0)) || "right"(pagibig_no, 4))
        END AS pagibig_no_masked,
        CASE
            WHEN ((tin_no IS NULL) OR (length(regexp_replace(tin_no, '\\D'::text, ''::text, 'g'::text)) <= 4)) THEN tin_no
            ELSE (repeat('*'::text, GREATEST((length(tin_no) - 4), 0)) || "right"(tin_no, 4))
        END AS tin_no_masked,
        CASE
            WHEN ((atm_no IS NULL) OR (length(regexp_replace(atm_no, '\\D'::text, ''::text, 'g'::text)) <= 4)) THEN atm_no
            ELSE (repeat('*'::text, GREATEST((length(atm_no) - 4), 0)) || "right"(atm_no, 4))
        END AS atm_no_masked,
    birthdate,
    civil_status,
    date_hired,
    flag_type,
    flag_reason,
    address,
    created_at
   FROM public.mika_import_rows;


create or replace view "public"."v_plantilla_safe" as  SELECT id,
    employee_name,
    employee_no,
    account,
    account_id,
    chain_id,
    store_id,
    province_id,
    "position",
    position_id,
    status,
    separation_status,
    date_of_separation,
    over_headcount,
    deactivated_at,
    deactivated_visible_until,
    deactivation_reason,
    deletion_requested_at,
    deletion_reason,
    sss_no,
    philhealth_no,
    pagibig_no,
        CASE
            WHEN (atm_no IS NULL) THEN NULL::text
            WHEN (length(atm_no) <= 4) THEN '****'::text
            ELSE (repeat('*'::text, (length(atm_no) - 4)) || "right"(atm_no, 4))
        END AS atm_no_masked,
    civil_status,
    date_of_birth,
        CASE
            WHEN (date_of_birth IS NOT NULL) THEN (EXTRACT(year FROM age((date_of_birth)::timestamp with time zone)))::integer
            ELSE NULL::integer
        END AS age,
        CASE
            WHEN (date_hired IS NOT NULL) THEN ((EXTRACT(epoch FROM age(now(), (date_hired)::timestamp with time zone)) / ((((60 * 60) * 24))::numeric * 30.4375)))::integer
            ELSE NULL::integer
        END AS tenure_months,
    last_mika_synced_at,
    last_mika_synced_by,
    store_name,
    area,
    rate,
    schedule,
    deployment_type,
    has_penalty,
    date_hired,
    coordinator,
    hrco_name,
    vcode,
    hr_emploc_id,
    roving_assignment_id,
    created_at,
    updated_at,
    source_headcount_request_id,
    (COALESCE(( SELECT count(*) AS count
           FROM public.plantilla_store_links psl
          WHERE ((psl.plantilla_id = p.id) AND (psl.deleted_at IS NULL) AND (psl.status = 'Active'::text))), (0)::bigint))::integer AS roving_store_count,
    ( SELECT jsonb_agg(jsonb_build_object('vcode', psl.vcode, 'store_name', psl.store_name, 'account', psl.account, 'status', psl.status, 'linked_at', psl.linked_at) ORDER BY psl.vcode) AS jsonb_agg
           FROM public.plantilla_store_links psl
          WHERE ((psl.plantilla_id = p.id) AND (psl.deleted_at IS NULL))) AS roving_stores
   FROM public.plantilla p
  WHERE ((COALESCE(is_deleted, false) = false) AND ((deactivated_visible_until IS NULL) OR (deactivated_visible_until > now())));


create or replace view "public"."v_qa_daily_reports" as  SELECT id,
    report_date,
    environment,
    total_runs,
    passed_runs,
    failed_runs,
    blocked_runs,
    cancelled_runs,
    critical_count,
    high_count,
    medium_count,
    low_count,
    top_failed_modules,
    average_runtime_seconds,
    most_unstable_workflow,
    flaky_tests,
    health_score,
    health_status,
    generated_by,
    generated_at,
    archived_at
   FROM public.qa_daily_reports
  WHERE (archived_at IS NULL)
  ORDER BY report_date DESC, generated_at DESC;


create or replace view "public"."v_qa_detection_run_summary" as  SELECT r.id,
    r.agent_name,
    r.execution_type,
    r.status,
    r.target_module,
    r.initiated_by,
    r.started_at,
    r.completed_at,
    r.summary,
    count(f.id) AS finding_count,
    count(f.id) FILTER (WHERE (f.severity = 'critical'::text)) AS critical_count,
    count(f.id) FILTER (WHERE (f.severity = 'high'::text)) AS high_count,
    count(f.id) FILTER (WHERE (f.severity = 'medium'::text)) AS medium_count,
    count(f.id) FILTER (WHERE (f.severity = 'low'::text)) AS low_count
   FROM (public.qa_agent_runs r
     LEFT JOIN public.qa_agent_findings f ON ((f.run_id = r.id)))
  GROUP BY r.id;


create or replace view "public"."v_qa_flaky_tests" as  SELECT finding_type,
    module_name,
    count(*) AS occurrence_count,
    min(created_at) AS first_seen_at,
    max(created_at) AS last_seen_at
   FROM public.qa_agent_findings
  WHERE (created_at >= (now() - '30 days'::interval))
  GROUP BY finding_type, module_name
 HAVING (count(*) >= 2)
  ORDER BY (count(*)) DESC, (max(created_at)) DESC;


create or replace view "public"."v_qa_health_metrics" as  SELECT id,
    metric_date,
    environment,
    metric_name,
    metric_value,
    metric_status,
    metadata,
    created_at
   FROM public.qa_health_metrics
  ORDER BY metric_date DESC, created_at DESC;


create or replace view "public"."v_qa_notifications" as  SELECT id,
    notification_type,
    severity,
    title,
    message,
    reference_type,
    reference_id,
    target_role,
    is_read,
    read_at,
    created_at,
    archived_at,
    metadata
   FROM public.qa_notifications
  WHERE (archived_at IS NULL)
  ORDER BY created_at DESC;


create or replace view "public"."v_qa_open_findings" as  SELECT f.id,
    f.run_id,
    f.severity,
    f.finding_type,
    f.module_name,
    f.reference_table,
    f.reference_record_id,
    f.title,
    f.details,
    f.recommendation,
    f.status,
    f.created_at,
    r.agent_name,
    r.target_module,
    r.started_at AS run_started_at
   FROM (public.qa_agent_findings f
     JOIN public.qa_agent_runs r ON ((r.id = f.run_id)))
  WHERE (f.status = 'open'::text);


create or replace view "public"."v_qa_run_queue" as  SELECT q.id,
    q.schedule_id,
    s.schedule_name,
    q.suite_name,
    q.environment,
    q.queue_status,
    q.run_id,
    q.lock_key,
    q.retry_count,
    q.max_retries,
    q.failure_type,
    q.error_message,
    q.queued_at,
    q.started_at,
    q.completed_at,
    q.lock_expires_at
   FROM (public.qa_run_queue q
     LEFT JOIN public.qa_schedules s ON ((s.id = q.schedule_id)));


create or replace view "public"."v_qa_schedules" as  SELECT id,
    schedule_name,
    suite_name,
    frequency,
    run_time,
    timezone,
    environment,
    assigned_agent_name,
    is_enabled,
    last_queued_at,
    last_run_at,
    next_run_at,
    created_at,
    updated_at
   FROM public.qa_schedules
  WHERE (archived_at IS NULL);


create or replace view "public"."v_qa_unstable_modules" as  SELECT COALESCE(module_name, 'unknown'::text) AS module_name,
    count(*) AS finding_count,
    count(*) FILTER (WHERE (severity = 'critical'::text)) AS critical_count,
    count(*) FILTER (WHERE (severity = 'high'::text)) AS high_count,
    max(created_at) AS latest_finding_at
   FROM public.qa_agent_findings f
  WHERE (created_at >= (now() - '30 days'::interval))
  GROUP BY COALESCE(module_name, 'unknown'::text)
 HAVING (count(*) > 0)
  ORDER BY (count(*) FILTER (WHERE (severity = 'critical'::text))) DESC, (count(*) FILTER (WHERE (severity = 'high'::text))) DESC, (count(*)) DESC;


create or replace view "public"."v_store_import_approval_queue" as  SELECT b.id AS batch_id,
    b.file_name,
    b.uploaded_by,
    up.full_name AS uploaded_by_name,
    b.uploaded_role,
    b.selected_group_id,
    g.group_name,
    b.selected_account_id,
    a.account_name,
    b.status,
    b.total_rows,
    b.valid_rows,
    b.invalid_rows,
    b.error_summary,
    b.created_at,
    b.updated_at,
    ((EXTRACT(epoch FROM (now() - b.created_at)))::integer / 86400) AS days_pending
   FROM (((public.store_import_batches b
     LEFT JOIN public.groups g ON ((g.id = b.selected_group_id)))
     LEFT JOIN public.accounts a ON ((a.id = b.selected_account_id)))
     LEFT JOIN public.users_profile up ON ((up.id = b.uploaded_by)))
  WHERE (b.status = ANY (ARRAY['pending_approval'::text, 'validation_failed'::text]))
  ORDER BY
        CASE b.status
            WHEN 'pending_approval'::text THEN 1
            WHEN 'validation_failed'::text THEN 2
            ELSE 3
        END, b.created_at;


create or replace view "public"."v_store_master_import_preview" as  SELECT b.id AS batch_id,
    r.id AS row_id,
    r.row_number,
    b.selected_group_id,
    b.selected_account_id,
    g.group_name,
    a.account_name,
    r.vcode,
    r.store_name,
    r.area_province,
    r.area_city,
    r.type,
    r.with_penalty,
    r.validation_status,
    r.validation_errors,
    b.status AS batch_status
   FROM (((public.store_import_rows r
     JOIN public.store_import_batches b ON ((b.id = r.batch_id)))
     LEFT JOIN public.groups g ON ((g.id = b.selected_group_id)))
     LEFT JOIN public.accounts a ON ((a.id = b.selected_account_id)));


create or replace view "public"."v_vacancy_active_coverage" as  SELECT vc.id,
    vc.vacancy_id,
    v.vcode,
    v.account,
    v.status AS vacancy_status,
    vc.coverage_type,
    vc.status AS coverage_status,
    vc.notes AS coverage_notes,
    vc.applicant_id,
    vc.covered_from,
    vc.covered_until,
    vc.archived_at,
    vc.created_at
   FROM (public.vacancy_coverage vc
     JOIN public.vacancies v ON ((v.id = vc.vacancy_id)))
  WHERE ((vc.status = 'Active'::public.vacancy_coverage_status) AND (vc.archived_at IS NULL) AND (v.deleted_at IS NULL) AND (COALESCE(v.is_archived, false) = false));


create or replace view "public"."v_vacancy_pipeline_status" as  SELECT v.id AS vacancy_id,
    v.vcode,
    v.account,
    v.status AS vacancy_status,
    count(a.id) AS active_applicant_count,
        CASE
            WHEN (count(a.id) > 0) THEN 'Pipeline'::text
            ELSE 'Open'::text
        END AS pipeline_classification
   FROM (public.vacancies v
     LEFT JOIN public.applicants a ON (((a.vacancy_vcode = v.vcode) AND (COALESCE(a.is_archived, false) = false) AND public.fn_is_active_vacancy_applicant_status(a.status))))
  WHERE ((v.deleted_at IS NULL) AND (COALESCE(v.is_archived, false) = false))
  GROUP BY v.id, v.vcode, v.account, v.status;


create or replace view "public"."v_workforce_assignment_request_queue" as  SELECT war.id AS request_id,
    war.employee_id,
    p.employee_no AS employee_number,
    p.employee_name,
    wpt.name AS pool_type,
    a.account_name AS requested_account,
    s.store_name AS requested_store,
    g.group_name AS requested_group,
    war.priority,
    war.start_date,
    war.end_date,
    war.reason,
    war.status,
    war.requested_by,
    war.rejection_reason,
    war.reviewed_by,
    war.reviewed_at,
    war.converted_assignment_id,
    war.created_at,
    (EXTRACT(day FROM (now() - war.created_at)))::integer AS request_age_days,
        CASE
            WHEN (EXTRACT(day FROM (now() - war.created_at)) < (3)::numeric) THEN 'Normal'::text
            WHEN (EXTRACT(day FROM (now() - war.created_at)) < (5)::numeric) THEN 'Notify Head Admin'::text
            WHEN (EXTRACT(day FROM (now() - war.created_at)) < (7)::numeric) THEN 'Notify OM'::text
            ELSE 'Notify Super Admin'::text
        END AS escalation_level,
        CASE
            WHEN (EXTRACT(day FROM (now() - war.created_at)) < (3)::numeric) THEN 'Head Admin'::text
            WHEN (EXTRACT(day FROM (now() - war.created_at)) < (5)::numeric) THEN 'OM'::text
            ELSE 'Super Admin'::text
        END AS notify_target_role
   FROM (((((public.workforce_assignment_requests war
     JOIN public.plantilla p ON ((p.id = war.employee_id)))
     JOIN public.workforce_pool_types wpt ON ((wpt.id = war.pool_type_id)))
     LEFT JOIN public.accounts a ON ((a.id = war.requested_account_id)))
     LEFT JOIN public.stores s ON ((s.id = war.requested_store_id)))
     LEFT JOIN public.groups g ON ((g.id = war.requested_group_id)))
  WHERE ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access() OR (war.requested_by_id = auth.uid()) OR (((war.requested_account_id)::text = ANY (public.get_my_allowed_accounts())) AND public.can_view_pool_employee(war.employee_id)));


create or replace view "public"."v_workforce_assignment_review_queue" as  SELECT wa.id AS assignment_id,
    wa.employee_id,
    p.employee_no AS employee_number,
    p.employee_name,
    wa.assigned_account_id,
    a.account_name,
    wa.assigned_store_id,
    s.store_name,
    wa.pool_type_id,
    wpt.code AS pool_type_code,
    wpt.name AS pool_type_name,
    wa.start_date,
    wa.end_date,
    wa.status,
    wa.priority,
    (wa.end_date - CURRENT_DATE) AS days_remaining,
        CASE
            WHEN ((p.is_deleted = true) OR (p.deactivated_at IS NOT NULL) OR (p.status <> 'Active'::text)) THEN 'Employee Inactive'::text
            WHEN (CURRENT_DATE > wa.end_date) THEN 'Overdue'::text
            WHEN (CURRENT_DATE = wa.end_date) THEN 'Due Today'::text
            WHEN ((wa.end_date - CURRENT_DATE) <= 3) THEN 'Nearing End Date'::text
            WHEN ((wa.end_date - wa.start_date) >= 180) THEN 'Long-Term Coverage'::text
            ELSE 'Pending Review'::text
        END AS review_label,
    wa.notes,
    wa.created_at
   FROM ((((public.workforce_assignments wa
     JOIN public.plantilla p ON ((p.id = wa.employee_id)))
     JOIN public.workforce_pool_types wpt ON ((wpt.id = wa.pool_type_id)))
     LEFT JOIN public.accounts a ON ((a.id = wa.assigned_account_id)))
     LEFT JOIN public.stores s ON ((s.id = wa.assigned_store_id)))
  WHERE ((wa.status = ANY (ARRAY['Pending'::text, 'Active'::text, 'Approved'::text])) AND ((p.is_deleted = true) OR (p.deactivated_at IS NOT NULL) OR (p.status <> 'Active'::text) OR (CURRENT_DATE > wa.end_date) OR (CURRENT_DATE = wa.end_date) OR ((wa.end_date - CURRENT_DATE) <= 3) OR ((wa.end_date - wa.start_date) >= 180) OR (wa.status = 'Pending'::text)) AND ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()));


create or replace view "public"."v_workforce_pool_conversion_requests" as  SELECT r.id AS request_id,
    r.employee_id,
    p.employee_name,
    p.employee_no AS employee_number,
    r.pool_type_id,
    wpt.name AS pool_type_name,
    wpt.code AS pool_type_code,
    r.pool_slot_id,
    r.vcode,
    r.target_account_id,
    COALESCE(r.target_account, a.account_name) AS target_account,
    r.target_store_id,
    COALESCE(r.target_store, s.store_name) AS target_store,
    r.target_position,
    r.effective_date,
    r.reason,
    r.notes,
    r.status,
    r.requested_by,
    r.requested_by_name,
    r.requested_by_role,
    r.approved_by_name,
    r.approved_at,
    r.rejected_by_name,
    r.rejected_at,
    r.rejection_reason,
    r.previous_account,
    r.previous_store,
    r.previous_position,
    r.previous_vcode,
    r.active_assignments_closed,
    r.pending_requests_cancelled,
    r.slot_review_id,
    r.created_at,
    r.updated_at,
    GREATEST((CURRENT_DATE - (r.created_at)::date), 0) AS request_age_days
   FROM ((((public.workforce_pool_conversion_requests r
     JOIN public.plantilla p ON ((p.id = r.employee_id)))
     LEFT JOIN public.workforce_pool_types wpt ON ((wpt.id = r.pool_type_id)))
     LEFT JOIN public.accounts a ON ((a.id = r.target_account_id)))
     LEFT JOIN public.stores s ON ((s.id = r.target_store_id)));


create or replace view "public"."v_workforce_pool_employees" as  SELECT p.id AS employee_id,
    p.employee_no AS employee_number,
    p.employee_name AS full_name,
    p.first_name,
    p.last_name,
    p.account AS home_account,
    p.account_id AS home_account_id,
    p.store_id AS home_store_id,
    wps.id AS pool_slot_id,
    COALESCE(wps.pool_type_id, p.pool_type_id) AS pool_type_id,
    wpt.code AS pool_type_code,
    wpt.name AS pool_type_name,
    wps.group_id AS tagged_group_id,
    g.group_name AS tagged_group_name,
    COALESCE(agg.active_deployment_count, (0)::bigint) AS active_deployment_count,
    COALESCE(agg.active_store_count, (0)::bigint) AS active_store_count,
        CASE
            WHEN (COALESCE(agg.active_deployment_count, (0)::bigint) = 0) THEN 'None'::text
            WHEN ((agg.active_deployment_count >= 1) AND (agg.active_deployment_count <= 5)) THEN 'Low'::text
            WHEN ((agg.active_deployment_count >= 6) AND (agg.active_deployment_count <= 10)) THEN 'Medium'::text
            WHEN ((agg.active_deployment_count >= 11) AND (agg.active_deployment_count <= 20)) THEN 'High'::text
            ELSE 'Critical'::text
        END AS deployment_load_indicator,
        CASE
            WHEN ((p.is_deleted = true) OR (p.deactivated_at IS NOT NULL) OR (p.status <> 'Active'::text)) THEN 'Inactive'::text
            WHEN (pend.pending_request_id IS NOT NULL) THEN 'Reserved'::text
            WHEN (COALESCE(agg.active_deployment_count, (0)::bigint) > 0) THEN 'Deployed'::text
            ELSE 'Available'::text
        END AS availability_status,
    (wps.group_id IS NULL) AS is_global_visible,
    (pend.pending_request_id IS NOT NULL) AS has_pending_request,
    pend.pending_request_id,
    pend.pending_requested_account,
    pend.pending_requested_store,
    p.status AS employee_status,
    p.date_hired,
    p."position",
    p.deployment_type AS home_deployment_type,
    COALESCE(lt.has_longterm, false) AS needs_review
   FROM ((((((public.plantilla p
     LEFT JOIN public.workforce_pool_slots wps ON (((wps.vcode = p.vcode) AND (wps.deleted_at IS NULL) AND (wps.is_active = true))))
     JOIN public.workforce_pool_types wpt ON (((wpt.id = COALESCE(wps.pool_type_id, p.pool_type_id)) AND (wpt.is_active = true))))
     LEFT JOIN public.groups g ON ((g.id = wps.group_id)))
     LEFT JOIN ( SELECT workforce_assignments.employee_id,
            count(*) FILTER (WHERE (workforce_assignments.status = ANY (ARRAY['Active'::text, 'Approved'::text]))) AS active_deployment_count,
            count(DISTINCT workforce_assignments.assigned_store_id) FILTER (WHERE (workforce_assignments.status = ANY (ARRAY['Active'::text, 'Approved'::text]))) AS active_store_count
           FROM public.workforce_assignments
          GROUP BY workforce_assignments.employee_id) agg ON ((agg.employee_id = p.id)))
     LEFT JOIN ( SELECT DISTINCT workforce_assignments.employee_id,
            true AS has_longterm
           FROM public.workforce_assignments
          WHERE ((workforce_assignments.status = ANY (ARRAY['Active'::text, 'Approved'::text])) AND (workforce_assignments.start_date <= (CURRENT_DATE - '30 days'::interval)))) lt ON ((lt.employee_id = p.id)))
     LEFT JOIN ( SELECT war.employee_id,
            war.id AS pending_request_id,
            a.account_name AS pending_requested_account,
            s.store_name AS pending_requested_store
           FROM ((public.workforce_assignment_requests war
             LEFT JOIN public.accounts a ON ((a.id = war.requested_account_id)))
             LEFT JOIN public.stores s ON ((s.id = war.requested_store_id)))
          WHERE (war.status = 'Pending'::text)) pend ON ((pend.employee_id = p.id)))
  WHERE ((p.is_deleted = false) AND (p.is_pool_employee = true) AND (p.deactivated_at IS NULL) AND ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access() OR (wps.group_id IS NULL) OR (EXISTS ( SELECT 1
           FROM public.accounts a
          WHERE ((a.group_id = wps.group_id) AND ((a.id)::text = ANY (public.get_my_allowed_accounts())))))));


create or replace view "public"."v_workforce_slot_reviews" as  SELECT sr.id AS review_id,
    sr.vcode,
    sr.pool_type_id,
    wpt.name AS pool_type_name,
    wpt.code AS pool_type_code,
    sr.trigger_event,
    sr.status,
    sr.action,
    sr.review_notes,
    sr.previous_employee_id,
    p.employee_name AS previous_employee_name,
    p.employee_no AS previous_employee_number,
    sr.decided_at,
    sr.decided_by,
    sr.created_by,
    sr.created_at,
    sr.updated_at,
    wps.id AS slot_id,
    wps.status AS slot_status,
    wps.is_active AS slot_is_active,
    GREATEST((CURRENT_DATE - (sr.created_at)::date), 0) AS review_age_days
   FROM (((public.workforce_slot_reviews sr
     LEFT JOIN public.workforce_pool_types wpt ON ((wpt.id = sr.pool_type_id)))
     LEFT JOIN public.plantilla p ON ((p.id = sr.previous_employee_id)))
     LEFT JOIN public.workforce_pool_slots wps ON (((wps.vcode = sr.vcode) AND (wps.deleted_at IS NULL))))
  ORDER BY sr.created_at DESC;


create or replace view "public"."v_workforce_store_temporary_coverage" as  SELECT wa.id AS assignment_id,
    wa.assigned_store_id AS store_id,
    wa.assigned_account_id AS account_id,
    wa.assigned_group_id AS group_id,
    wa.employee_id,
    p.employee_no AS employee_number,
    p.employee_name,
    wpt.code AS pool_type_code,
    wpt.name AS pool_type_name,
    wa.deployment_type,
    wa.priority,
    wa.is_primary,
    wa.start_date,
    wa.end_date,
    wa.status,
    wa.approved_by,
    wa.approved_at,
    a.account_name,
    s.store_name,
    s.store_branch,
    g.group_name
   FROM (((((public.workforce_assignments wa
     JOIN public.plantilla p ON (((p.id = wa.employee_id) AND (p.is_deleted = false))))
     JOIN public.workforce_pool_types wpt ON ((wpt.id = wa.pool_type_id)))
     LEFT JOIN public.accounts a ON ((a.id = wa.assigned_account_id)))
     LEFT JOIN public.stores s ON ((s.id = wa.assigned_store_id)))
     LEFT JOIN public.groups g ON ((g.id = wa.assigned_group_id)))
  WHERE ((wa.status = ANY (ARRAY['Active'::text, 'Approved'::text])) AND ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access() OR (((wa.assigned_account_id)::text = ANY (public.get_my_allowed_accounts())) AND public.can_view_pool_employee(wa.employee_id))));


create or replace view "public"."view_archived_records" as  SELECT 'vacancy'::text AS module,
    vacancies.id,
    vacancies.vcode AS reference_code,
    vacancies.account AS context,
    vacancies.status,
    vacancies.deleted_at,
    vacancies.updated_by AS deleted_by
   FROM public.vacancies
  WHERE ((vacancies.deleted_at IS NOT NULL) AND (vacancies.deleted_at >= (now() - '30 days'::interval)))
UNION ALL
 SELECT 'hr_emploc'::text AS module,
    hr_emploc.id,
    hr_emploc.vcode AS reference_code,
    hr_emploc.applicant_name AS context,
    hr_emploc.status,
    hr_emploc.deleted_at,
    hr_emploc.updated_by AS deleted_by
   FROM public.hr_emploc
  WHERE ((hr_emploc.deleted_at IS NOT NULL) AND (hr_emploc.deleted_at >= (now() - '30 days'::interval)));


create or replace view "public"."vw_account_handlers" as  SELECT a.id,
    a.account_name,
    a.group_id,
    a.is_active,
    a.status,
    a.om_user_id,
    om.full_name AS om_name,
    a.atl_user_id,
    atl.full_name AS atl_name,
    a.hrco_user_id,
    hrco.full_name AS hrco_name,
    g.group_code,
    g.group_name
   FROM ((((public.accounts a
     LEFT JOIN public.users_profile om ON ((om.id = a.om_user_id)))
     LEFT JOIN public.users_profile atl ON ((atl.id = a.atl_user_id)))
     LEFT JOIN public.users_profile hrco ON ((hrco.id = a.hrco_user_id)))
     LEFT JOIN public.groups g ON ((g.id = a.group_id)));


create or replace view "public"."vw_accounts_with_group" as  SELECT a.id AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    a.om_user_id,
    a.atl_user_id,
    a.hrco_user_id,
    a.status,
    a.is_active,
    a.created_at
   FROM (public.accounts a
     JOIN public.groups g ON ((g.id = a.group_id)))
  WHERE (a.is_active = true);


create or replace view "public"."vw_applicant_funnel" as  SELECT v.account_id,
    a.group_id,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['Sourced'::text, 'For Interview'::text, 'Hired'::text]))) AS sourced,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['Applied'::text, 'For Interview'::text, 'Hired'::text]))) AS applied,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['Screened'::text, 'For Interview'::text, 'Hired'::text]))) AS screened,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['For Interview'::text, 'Hired'::text]))) AS interview,
    count(*) FILTER (WHERE (ap.status = ANY (ARRAY['Offer'::text, 'Hired'::text]))) AS offer,
    count(*) FILTER (WHERE (ap.status = 'Hired'::text)) AS hired
   FROM ((public.applicants ap
     JOIN public.vacancies v ON ((v.vcode = ap.vacancy_vcode)))
     JOIN public.accounts a ON ((a.id = v.account_id)))
  WHERE (COALESCE(ap.is_archived, false) = false)
  GROUP BY v.account_id, a.group_id;


create or replace view "public"."vw_attrition_rate" as  SELECT account,
    (date_trunc('month'::text, (date_of_separation)::timestamp with time zone))::date AS month,
    count(*) AS separations,
    ( SELECT count(*) AS count
           FROM public.plantilla p2
          WHERE ((p2.account = p.account) AND (p2.status = 'Active'::text))) AS active_headcount,
    round((((count(*))::numeric / (NULLIF(( SELECT count(*) AS count
           FROM public.plantilla p2
          WHERE ((p2.account = p.account) AND (p2.status = 'Active'::text))), 0))::numeric) * (100)::numeric), 2) AS attrition_rate_pct
   FROM public.plantilla p
  WHERE (date_of_separation IS NOT NULL)
  GROUP BY account, (date_trunc('month'::text, (date_of_separation)::timestamp with time zone));


create or replace view "public"."vw_gap_metrics" as  SELECT p.account,
    count(p.id) AS plantilla_count,
    COALESCE(m.mika_count, (0)::bigint) AS mika_count,
    (count(p.id) - COALESCE(m.mika_count, (0)::bigint)) AS raw_gap,
    round((((abs((count(p.id) - COALESCE(m.mika_count, (0)::bigint))))::numeric / (NULLIF(count(p.id), 0))::numeric) * (100)::numeric), 2) AS gap_pct,
        CASE
            WHEN ((((abs((count(p.id) - COALESCE(m.mika_count, (0)::bigint))))::numeric / (NULLIF(count(p.id), 0))::numeric) * (100)::numeric) > (5)::numeric) THEN true
            ELSE false
        END AS gap_alert,
    ((count(p.id) - COALESCE(m.mika_count, (0)::bigint)) > 0) AS payroll_alert,
    (COALESCE(max(s.unprocessed_resignations), (0)::bigint) > 0) AS mika_alert
   FROM ((public.plantilla p
     LEFT JOIN ( SELECT mr.account,
            count(*) AS mika_count
           FROM public.mika_import_rows mr
          WHERE (mr.flag_type IS NULL)
          GROUP BY mr.account) m ON ((m.account = p.account)))
     LEFT JOIN ( SELECT plantilla.account,
            count(*) AS unprocessed_resignations
           FROM public.plantilla
          WHERE ((plantilla.status = 'Resigned'::text) AND (plantilla.date_of_separation IS NULL))
          GROUP BY plantilla.account) s ON ((s.account = p.account)))
  WHERE (p.status = 'Active'::text)
  GROUP BY p.account, m.mika_count;


create or replace view "public"."vw_ghost_cases_active" as  SELECT id,
    public.mask_name(full_name) AS masked_name,
    full_name,
    employee_no,
    vcode AS badge,
    account,
    assigned_encoder AS assignee,
    (EXTRACT(day FROM (now() - created_at)))::integer AS days_open,
    status,
    ghost_type
   FROM public.possible_ghost_employees g
  WHERE (status <> ALL (ARRAY['Resolved'::text, 'Closed'::text]))
  ORDER BY (EXTRACT(day FROM (now() - created_at))) DESC;


create or replace view "public"."vw_monthly_hires" as  SELECT (date_trunc('month'::text, (he.hired_date)::timestamp with time zone))::date AS month,
    he.account_id,
    a.group_id,
    count(*) AS hired_count
   FROM (public.hr_emploc he
     JOIN public.accounts a ON ((a.id = he.account_id)))
  WHERE (he.hired_date >= ((date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone) - '5 mons'::interval))::date)
  GROUP BY (date_trunc('month'::text, (he.hired_date)::timestamp with time zone)), he.account_id, a.group_id;


create or replace view "public"."vw_open_vacancies_by_store" as  SELECT account,
    account_id,
    store_branch,
    area_name,
    hrco_user_id,
    om_user_id,
    count(*) AS open_count,
    array_agg("position" ORDER BY "position") AS positions,
    min(vacant_date) AS earliest_vacant,
    max(created_at) AS latest_created
   FROM public.vacancies v
  WHERE ((status = 'Open'::text) AND (COALESCE(is_archived, false) = false))
  GROUP BY account, account_id, store_branch, area_name, hrco_user_id, om_user_id;


create or replace view "public"."vw_plantilla_status_counts" as  SELECT p.account_id,
    a.group_id,
    count(*) FILTER (WHERE (p.status = 'Active'::text)) AS active_count,
    count(*) FILTER (WHERE (p.status = 'On Leave'::text)) AS on_leave_count,
    count(*) FILTER (WHERE (p.status = 'Resigned'::text)) AS resigned_count
   FROM (public.plantilla p
     LEFT JOIN public.accounts a ON ((a.id = p.account_id)))
  GROUP BY p.account_id, a.group_id;


create or replace view "public"."vw_ready_to_plantilla" as  SELECT he.id,
    public.mask_name(COALESCE(he.applicant_name, he.applicant_name_snapshot, he.employee_name_snapshot)) AS masked_name,
    COALESCE(he.applicant_name, he.applicant_name_snapshot) AS full_name,
    he.account,
    he."position",
    he.employee_no,
    he.vcode,
    he.account_id,
    a.group_id,
    he.created_at
   FROM (public.hr_emploc he
     LEFT JOIN public.accounts a ON ((a.id = he.account_id)))
  WHERE ((he.employee_no IS NOT NULL) AND (he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])) AND (he.hr_status <> ALL (ARRAY['Rejected'::text, 'For Correction'::text])) AND (he.deleted_at IS NULL))
  ORDER BY he.created_at;


create or replace view "public"."vw_recruiter_sla" as  WITH assigned AS (
         SELECT v.assigned_encoder_id AS recruiter_id,
            count(*) AS assigned_count,
            count(*) FILTER (WHERE ((v.status = 'Filled'::text) AND (((v.updated_at)::date - (v.created_at)::date) <= 30))) AS on_time_count,
            count(*) FILTER (WHERE ((v.status = 'Filled'::text) AND (((v.updated_at)::date - (v.created_at)::date) > 30))) AS late_count,
            count(*) FILTER (WHERE ((v.status = 'Open'::text) AND (EXTRACT(day FROM (now() - v.created_at)) > (30)::numeric))) AS overdue_open
           FROM public.vacancies v
          WHERE ((v.assigned_encoder_id IS NOT NULL) AND (COALESCE(v.is_archived, false) = false))
          GROUP BY v.assigned_encoder_id
        )
 SELECT up.id AS recruiter_id,
    up.full_name AS recruiter_name,
    g.group_name AS region_scope,
    a.assigned_count,
    a.on_time_count,
    (a.late_count + a.overdue_open) AS late_count,
        CASE
            WHEN (a.assigned_count = 0) THEN (100)::numeric
            ELSE round(((100.0 * (a.on_time_count)::numeric) / (a.assigned_count)::numeric))
        END AS sla_pct
   FROM ((assigned a
     JOIN public.users_profile up ON ((up.id = a.recruiter_id)))
     LEFT JOIN public.groups g ON ((g.id = up.group_id)))
  ORDER BY
        CASE
            WHEN (a.assigned_count = 0) THEN (100)::numeric
            ELSE round(((100.0 * (a.on_time_count)::numeric) / (a.assigned_count)::numeric))
        END DESC NULLS LAST;


create or replace view "public"."vw_rejected_emploc_active" as  SELECT he.id,
    public.mask_name(COALESCE(he.applicant_name, he.applicant_name_snapshot)) AS masked_name,
    he.vcode,
    he.account,
    he."position",
    he.hr_rejection_reason AS reason,
        CASE
            WHEN (he.hr_rejection_reason ~~* '%tin%'::text) THEN 'Tax Info'::text
            WHEN (he.hr_rejection_reason ~~* '%sss%'::text) THEN 'SSS'::text
            WHEN (he.hr_rejection_reason ~~* '%philhealth%'::text) THEN 'PhilHealth'::text
            WHEN (he.hr_rejection_reason ~~* '%pagibig%'::text) THEN 'Pag-IBIG'::text
            WHEN (he.hr_rejection_reason ~~* '%date%'::text) THEN 'Date'::text
            WHEN (he.hr_rejection_reason ~~* '%position%'::text) THEN 'Job Info'::text
            WHEN (he.hr_rejection_reason ~~* '%address%'::text) THEN 'Address'::text
            WHEN (he.hr_rejection_reason ~~* '%name%'::text) THEN 'Identity'::text
            ELSE 'Other'::text
        END AS field_tag,
    he.hr_reviewed_by AS assignee,
    (EXTRACT(day FROM (now() - he.hr_reviewed_at)))::integer AS days_ago,
    he.account_id,
    a.group_id
   FROM (public.hr_emploc he
     LEFT JOIN public.accounts a ON ((a.id = he.account_id)))
  WHERE ((he.hr_status = 'Rejected'::text) AND (he.deleted_at IS NULL))
  ORDER BY he.hr_reviewed_at DESC NULLS LAST;


create or replace view "public"."vw_sla_breach_summary" as  SELECT account,
    count(*) AS total_breaches,
    count(*) FILTER (WHERE (breach_type = 'resignation_not_tagged'::text)) AS resignation_breaches,
    round(avg(days_elapsed), 1) AS avg_days_elapsed,
    max(created_at) AS latest_breach_at
   FROM public.sla_breach_logs s
  GROUP BY account;


create or replace view "public"."vw_sla_by_group" as  WITH vac AS (
         SELECT a.group_id,
            count(*) FILTER (WHERE ((v.status = 'Filled'::text) AND (((v.updated_at)::date - (v.created_at)::date) <= 30))) AS vacancy_on_time,
            count(*) FILTER (WHERE (v.status = 'Filled'::text)) AS vacancy_total
           FROM (public.vacancies v
             JOIN public.accounts a ON ((a.id = v.account_id)))
          WHERE (v.updated_at >= (now() - '30 days'::interval))
          GROUP BY a.group_id
        ), app AS (
         SELECT a.group_id,
            count(*) FILTER (WHERE ((ap.hired_date IS NOT NULL) AND ((ap.hired_date - (ap.created_at)::date) <= 14))) AS applicant_on_time,
            count(*) FILTER (WHERE (ap.status = 'Hired'::text)) AS applicant_total
           FROM ((public.applicants ap
             JOIN public.vacancies v ON ((v.vcode = ap.vacancy_vcode)))
             JOIN public.accounts a ON ((a.id = v.account_id)))
          WHERE (ap.hired_date >= ((now() - '30 days'::interval))::date)
          GROUP BY a.group_id
        ), pla AS (
         SELECT a.group_id,
            count(*) FILTER (WHERE ((he.moved_to_plantilla_at IS NOT NULL) AND (((he.moved_to_plantilla_at)::date - he.hired_date) <= 5))) AS plantilla_on_time,
            count(*) FILTER (WHERE (he.status = 'Moved to Plantilla'::text)) AS plantilla_total
           FROM (public.hr_emploc he
             JOIN public.accounts a ON ((a.id = he.account_id)))
          WHERE (he.moved_to_plantilla_at >= (now() - '30 days'::interval))
          GROUP BY a.group_id
        )
 SELECT g.id AS group_id,
    g.group_name,
    COALESCE(vac.vacancy_on_time, (0)::bigint) AS vacancy_n,
    COALESCE(vac.vacancy_total, (0)::bigint) AS vacancy_of,
        CASE
            WHEN (COALESCE(vac.vacancy_total, (0)::bigint) = 0) THEN NULL::numeric
            ELSE round(((100.0 * (vac.vacancy_on_time)::numeric) / (vac.vacancy_total)::numeric))
        END AS vacancy_pct,
    COALESCE(app.applicant_on_time, (0)::bigint) AS applicant_n,
    COALESCE(app.applicant_total, (0)::bigint) AS applicant_of,
        CASE
            WHEN (COALESCE(app.applicant_total, (0)::bigint) = 0) THEN NULL::numeric
            ELSE round(((100.0 * (app.applicant_on_time)::numeric) / (app.applicant_total)::numeric))
        END AS applicant_pct,
    COALESCE(pla.plantilla_on_time, (0)::bigint) AS plantilla_n,
    COALESCE(pla.plantilla_total, (0)::bigint) AS plantilla_of,
        CASE
            WHEN (COALESCE(pla.plantilla_total, (0)::bigint) = 0) THEN NULL::numeric
            ELSE round(((100.0 * (pla.plantilla_on_time)::numeric) / (pla.plantilla_total)::numeric))
        END AS plantilla_pct
   FROM (((public.groups g
     LEFT JOIN vac ON ((vac.group_id = g.id)))
     LEFT JOIN app ON ((app.group_id = g.id)))
     LEFT JOIN pla ON ((pla.group_id = g.id)));


create or replace view "public"."vw_vacancy_by_region" as  WITH base AS (
         SELECT v.id,
            v.account_id,
            v.area_name AS region,
            v.area_city AS city,
            v.status,
            v.created_at,
            v.updated_at,
            a.account_name,
            a.group_id,
            g.group_name,
            up.full_name AS recruiter_name
           FROM (((public.vacancies v
             JOIN public.accounts a ON ((a.id = v.account_id)))
             JOIN public.groups g ON ((g.id = a.group_id)))
             LEFT JOIN public.users_profile up ON ((up.id = v.assigned_encoder_id)))
          WHERE (COALESCE(v.is_archived, false) = false)
        )
 SELECT region,
    city,
    account_name,
    account_id,
    group_id,
    group_name,
    min(recruiter_name) AS recruiter_name,
    count(*) FILTER (WHERE (status = 'Open'::text)) AS open_count,
    max(
        CASE
            WHEN (status = 'Open'::text) THEN (EXTRACT(day FROM (now() - created_at)))::integer
            ELSE 0
        END) AS max_age_days,
    (round(avg(
        CASE
            WHEN (status = 'Filled'::text) THEN ((updated_at)::date - (created_at)::date)
            ELSE NULL::integer
        END)))::integer AS avg_ttf_days
   FROM base
  GROUP BY region, city, account_name, account_id, group_id, group_name;


create or replace view "public"."vw_vacancy_closure_pending" as  SELECT id,
    vcode,
    account,
    "position",
    store_name,
    status,
    closure_request_status,
    has_pending_closure,
    vacant_date,
    hrco_name,
    om_name,
    updated_at
   FROM public.vacancies v
  WHERE ((has_pending_closure = true) AND (COALESCE(is_archived, false) = false));


create or replace view "public"."vw_vacancy_detail" as  WITH applicant_stats AS (
         SELECT a.vacancy_vcode,
            count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND public.fn_is_active_vacancy_applicant_status(a.status))) AS active_applicant_count,
            count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text))) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text))) AS latest_hire_at,
            (count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text) AND (COALESCE(a.hired_visible_until, (a.hired_at + '7 days'::interval)) > now()))) > 0) AS has_recent_hire
           FROM public.applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    v.store_name,
    v.store_id,
    v.area_name,
    v.area_city,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
        CASE
            WHEN ((v.is_archived = true) OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text]))) THEN 'Archived'::text
            WHEN (v.status = 'Filled'::text) THEN 'Hired'::text
            WHEN (COALESCE(s.active_applicant_count, (0)::bigint) > 0) THEN 'Pipeline'::text
            ELSE 'Open'::text
        END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    (CURRENT_DATE - v.vacant_date) AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, (0)::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, (0)::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    v.has_reliever,
    v.reliever_name,
    v.requested_by_user_id,
    v.requested_date,
    v.group_id,
    g.group_name,
    v.hrco_user_id,
    v.hrco_name,
    COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
    NULL::text AS triggered_by_role,
    vr.vacancy_type AS hc_request_type,
    vr.requested_by AS hc_request_requested_by,
    vr.requested_by_user_id AS hc_request_requested_by_user_id,
    vr.created_at AS hc_request_date_created,
    vr.no_of_slots AS hc_request_no_of_slots,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire
   FROM ((((public.vacancies v
     LEFT JOIN applicant_stats s ON ((s.vacancy_vcode = v.vcode)))
     LEFT JOIN public.groups g ON ((g.id = v.group_id)))
     LEFT JOIN public.users_profile up ON ((up.id = v.triggered_by_user_id)))
     LEFT JOIN public.vacancy_requests vr ON ((vr.id = v.source_vacancy_request_id)))
  WHERE (v.deleted_at IS NULL);


create or replace view "public"."vw_vacancy_list" as  WITH applicant_stats AS (
         SELECT a.vacancy_vcode,
            count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND public.fn_is_active_vacancy_applicant_status(a.status))) AS active_applicant_count,
            count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text))) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text))) AS latest_hire_at,
            (count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status = 'Confirmed Onboard'::text) AND (COALESCE(a.hired_visible_until, (a.hired_at + '7 days'::interval)) > now()))) > 0) AS has_recent_hire
           FROM public.applicants a
          GROUP BY a.vacancy_vcode
        )
 SELECT v.id,
    v.vcode,
    v.account,
    v.account_id,
    v.store_name,
    v.store_id,
    v.area_name,
    v.area_city,
    v."position",
    v.position_id,
    v.employment_type,
    v.status,
        CASE
            WHEN ((v.is_archived = true) OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text]))) THEN 'Archived'::text
            WHEN (v.status = 'Filled'::text) THEN 'Hired'::text
            WHEN (COALESCE(s.active_applicant_count, (0)::bigint) > 0) THEN 'Pipeline'::text
            ELSE 'Open'::text
        END AS derived_status,
    v.source,
    v.source_vacancy_request_id,
    v.source_plantilla_id,
    v.vacancy_type,
    v.urgency_level,
    v.target_fill_date,
    v.required_headcount AS hc_needed,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.vacant_date,
    (CURRENT_DATE - v.vacant_date) AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, (0)::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, (0)::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    v.group_id,
    g.group_name,
    v.hrco_user_id,
    v.hrco_name,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire
   FROM ((public.vacancies v
     LEFT JOIN applicant_stats s ON ((s.vacancy_vcode = v.vcode)))
     LEFT JOIN public.groups g ON ((g.id = v.group_id)))
  WHERE (v.deleted_at IS NULL);


create or replace view "public"."own_performance_view" as  SELECT profile_id,
    auth_uid,
    full_name,
    role,
    group_id,
    required_count,
    actual_count,
    hr_emploc_count,
    vacant_count,
    mfr,
    pipeline_percent,
    perf_status,
    alert_flag,
    rank() OVER (PARTITION BY role ORDER BY COALESCE(mfr, (0)::numeric) DESC) AS rank_within_role,
    count(*) OVER (PARTITION BY role) AS total_in_role
   FROM public.team_performance_view tp
  WHERE (auth_uid = auth.uid());


create or replace view "public"."v_cencom_td_by_account" as  SELECT account_id,
    account,
    group_id,
    group_name,
    group_code,
    account_mfr,
    account_health_tier,
    account_health_status,
    count(*) FILTER (WHERE (NOT is_advance_vacancy)) AS operational_total,
    count(*) FILTER (WHERE is_advance_vacancy) AS advance_count,
    count(*) AS grand_total,
    count(*) FILTER (WHERE (aging_bucket = '1_15'::text)) AS bucket_1_15,
    count(*) FILTER (WHERE (aging_bucket = '16_30'::text)) AS bucket_16_30,
    count(*) FILTER (WHERE (aging_bucket = '31_60'::text)) AS bucket_31_60,
    count(*) FILTER (WHERE (aging_bucket = '61_120'::text)) AS bucket_61_120,
    count(*) FILTER (WHERE (aging_bucket = 'gt121'::text)) AS bucket_gt121,
    max(aging_days) AS max_aging_days,
    round(avg(aging_days), 1) AS avg_aging_days,
    max(priority_score) FILTER (WHERE (NOT is_advance_vacancy)) AS max_priority_score,
    count(*) FILTER (WHERE (urgency_tier = ANY (ARRAY['immediate'::text, 'critical'::text]))) AS urgent_count
   FROM public.v_cencom_td_vacancies
  GROUP BY account_id, account, group_id, group_name, group_code, account_mfr, account_health_tier, account_health_status
  ORDER BY (max(priority_score) FILTER (WHERE (NOT is_advance_vacancy))) DESC NULLS LAST;


create or replace view "public"."v_cencom_td_by_group" as  SELECT group_id,
    group_name,
    group_code,
    count(*) FILTER (WHERE (NOT is_advance_vacancy)) AS operational_total,
    count(*) FILTER (WHERE is_advance_vacancy) AS advance_count,
    count(*) AS grand_total,
    count(*) FILTER (WHERE (aging_bucket = '1_15'::text)) AS bucket_1_15,
    count(*) FILTER (WHERE (aging_bucket = '16_30'::text)) AS bucket_16_30,
    count(*) FILTER (WHERE (aging_bucket = '31_60'::text)) AS bucket_31_60,
    count(*) FILTER (WHERE (aging_bucket = '61_120'::text)) AS bucket_61_120,
    count(*) FILTER (WHERE (aging_bucket = 'gt121'::text)) AS bucket_gt121,
    count(*) FILTER (WHERE (urgency_tier = 'immediate'::text)) AS urgency_immediate,
    count(*) FILTER (WHERE (urgency_tier = 'critical'::text)) AS urgency_critical,
    count(*) FILTER (WHERE (urgency_tier = 'elevated'::text)) AS urgency_elevated,
    max(aging_days) AS max_aging_days,
    round(avg(aging_days), 1) AS avg_aging_days,
    max(priority_score) FILTER (WHERE (NOT is_advance_vacancy)) AS max_priority_score,
        CASE
            WHEN (count(*) FILTER (WHERE ((NOT is_advance_vacancy) AND (account_health_tier = 'critical'::text))) > 0) THEN 'critical'::text
            WHEN (count(*) FILTER (WHERE ((NOT is_advance_vacancy) AND (account_health_tier = 'at_risk'::text))) > 0) THEN 'at_risk'::text
            ELSE 'healthy'::text
        END AS group_health_status
   FROM public.v_cencom_td_vacancies
  GROUP BY group_id, group_name, group_code
  ORDER BY group_code;


create or replace view "public"."v_cencom_td_priority_queue" as  SELECT vacancy_id,
    vcode,
    account,
    account_id,
    group_name,
    group_code,
    "position",
    area_name,
    store_name,
    vacant_date,
    vacancy_type,
    urgency_level,
    target_fill_date,
    required_headcount,
    aging_days,
    aging_bucket,
    priority_score,
    account_mfr,
    account_health_tier,
    urgency_tier
   FROM public.v_cencom_td_vacancies
  WHERE (NOT is_advance_vacancy)
  ORDER BY priority_score DESC, aging_days DESC NULLS LAST, vcode;


create or replace view "public"."v_cencom_td_summary" as  SELECT count(*) FILTER (WHERE (NOT is_advance_vacancy)) AS operational_total,
    count(*) FILTER (WHERE is_advance_vacancy) AS advance_count,
    count(*) AS grand_total,
    count(*) FILTER (WHERE (aging_bucket = '1_15'::text)) AS bucket_1_15,
    count(*) FILTER (WHERE (aging_bucket = '16_30'::text)) AS bucket_16_30,
    count(*) FILTER (WHERE (aging_bucket = '31_60'::text)) AS bucket_31_60,
    count(*) FILTER (WHERE (aging_bucket = '61_120'::text)) AS bucket_61_120,
    count(*) FILTER (WHERE (aging_bucket = 'gt121'::text)) AS bucket_gt121,
    count(*) FILTER (WHERE (urgency_tier = 'immediate'::text)) AS urgency_immediate,
    count(*) FILTER (WHERE (urgency_tier = 'critical'::text)) AS urgency_critical,
    count(*) FILTER (WHERE (urgency_tier = 'elevated'::text)) AS urgency_elevated,
    count(*) FILTER (WHERE (urgency_tier = 'normal'::text)) AS urgency_normal,
    count(*) FILTER (WHERE ((NOT is_advance_vacancy) AND (account_health_tier = 'critical'::text))) AS health_critical_count,
    count(*) FILTER (WHERE ((NOT is_advance_vacancy) AND (account_health_tier = 'at_risk'::text))) AS health_at_risk_count,
    count(*) FILTER (WHERE ((NOT is_advance_vacancy) AND (account_health_tier = ANY (ARRAY['elevated'::text, 'healthy'::text])))) AS health_ok_count,
    max(aging_days) AS max_aging_days,
    round(avg(aging_days), 1) AS avg_aging_days,
    round((((count(*) FILTER (WHERE ((NOT is_advance_vacancy) AND (COALESCE(aging_days, 0) >= 31))))::numeric * 100.0) / (NULLIF(count(*) FILTER (WHERE (NOT is_advance_vacancy)), 0))::numeric), 1) AS pct_critical_aging,
    now() AS computed_at
   FROM public.v_cencom_td_vacancies;



  create policy "account_positions_read_scoped"
  on "public"."account_positions"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account_id IN ( SELECT accounts.id
   FROM public.accounts
  WHERE (accounts.account_code = ANY (public.get_my_allowed_accounts()))))));



  create policy "account_positions_write_data_team"
  on "public"."account_positions"
  as permissive
  for all
  to authenticated
using ((public.get_my_role_level() >= 30))
with check ((public.get_my_role_level() >= 30));



  create policy "ar_admin_all"
  on "public"."account_requests"
  as permissive
  for all
  to authenticated
using ((EXISTS ( SELECT 1
   FROM (public.users_profile up
     JOIN public.roles r ON ((r.id = up.role_id)))
  WHERE ((up.auth_user_id = auth.uid()) AND (r.role_level >= 90)))))
with check ((EXISTS ( SELECT 1
   FROM (public.users_profile up
     JOIN public.roles r ON ((r.id = up.role_id)))
  WHERE ((up.auth_user_id = auth.uid()) AND (r.role_level >= 90)))));



  create policy "ar_insert_own"
  on "public"."account_requests"
  as permissive
  for insert
  to authenticated
with check (((auth_user_id = auth.uid()) AND (status = 'pending'::public.account_request_status)));



  create policy "accounts_write_admin"
  on "public"."accounts"
  as permissive
  for all
  to public
using (public.i_have_full_access());



  create policy "acting_sessions_insert_super_admin"
  on "public"."acting_sessions"
  as permissive
  for insert
  to authenticated
with check (public.is_super_admin());



  create policy "acting_sessions_select_own"
  on "public"."acting_sessions"
  as permissive
  for select
  to authenticated
using (((auth.uid() = user_id) OR public.is_super_admin()));



  create policy "acting_sessions_update_super_admin"
  on "public"."acting_sessions"
  as permissive
  for update
  to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());



  create policy "audit_log_select"
  on "public"."activity_log"
  as permissive
  for select
  to public
using (public.i_have_full_access());



  create policy "apch_read_scoped"
  on "public"."applicant_profile_change_history"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (public.get_my_role_level() = 30) OR (EXISTS ( SELECT 1
   FROM (public.applicants a
     JOIN public.vacancies v ON ((v.vcode = a.vacancy_vcode)))
  WHERE ((a.id = applicant_profile_change_history.applicant_id) AND (v.account = ANY (public.get_my_allowed_accounts())))))));



  create policy "aper_read_scoped"
  on "public"."applicant_profile_edit_requests"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (public.get_my_role_level() = 30) OR (requested_by = public.get_my_profile_id()) OR (EXISTS ( SELECT 1
   FROM (public.applicants a
     JOIN public.vacancies v ON ((v.vcode = a.vacancy_vcode)))
  WHERE ((a.id = applicant_profile_edit_requests.applicant_id) AND (v.account = ANY (public.get_my_allowed_accounts())))))));



  create policy "ash_read_scoped"
  on "public"."applicant_status_history"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (public.get_my_role_level() = 30) OR (EXISTS ( SELECT 1
   FROM (public.applicants a
     JOIN public.vacancies v ON ((v.vcode = a.vacancy_vcode)))
  WHERE ((a.id = applicant_status_history.applicant_id) AND (v.account = ANY (public.get_my_allowed_accounts())) AND (v.deleted_at IS NULL))))));



  create policy "applicants_insert_ops_only"
  on "public"."applicants"
  as permissive
  for insert
  to public
with check (((public.i_have_full_access() OR ((public.i_am_ops() OR public.i_am_recruitment()) AND (vacancy_vcode IN ( SELECT vacancies.vcode
   FROM public.vacancies
  WHERE ((vacancies.account = ANY (public.get_my_allowed_accounts())) AND (vacancies.deleted_at IS NULL)))))) AND (NOT (EXISTS ( SELECT 1
   FROM public.vacancies v
  WHERE ((v.vcode = applicants.vacancy_vcode) AND (v.has_pending_closure = true) AND (v.deleted_at IS NULL)))))));



  create policy "applicants_read_scoped"
  on "public"."applicants"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (vacancy_vcode = ANY (public.get_my_scoped_vcodes()))));



  create policy "applicants_update_ops_recruitment"
  on "public"."applicants"
  as permissive
  for update
  to public
using ((public.i_have_full_access() OR ((public.i_am_ops() OR public.i_am_recruitment()) AND (vacancy_vcode IN ( SELECT vacancies.vcode
   FROM public.vacancies
  WHERE (vacancies.account = ANY (public.get_my_allowed_accounts())))))));



  create policy "audit_logs_select"
  on "public"."audit_logs"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM (public.users_profile up
     JOIN public.roles r ON ((r.id = up.role_id)))
  WHERE ((up.auth_user_id = auth.uid()) AND (r.role_level >= 30)))));



  create policy "pol_audit_admin_read"
  on "public"."audit_logs"
  as permissive
  for select
  to authenticated
using (public.i_have_full_access());



  create policy "backout_reasons_write_admin"
  on "public"."backout_reasons"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "bulk_items_insert_scoped"
  on "public"."bulk_emploc_items"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (upload_id IN ( SELECT bulk_emploc_uploads.id
   FROM public.bulk_emploc_uploads
  WHERE (bulk_emploc_uploads.uploaded_by_user_id = public.get_my_profile_id())))));



  create policy "bulk_items_read_scoped"
  on "public"."bulk_emploc_items"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (upload_id IN ( SELECT bulk_emploc_uploads.id
   FROM public.bulk_emploc_uploads
  WHERE ((bulk_emploc_uploads.uploaded_by_user_id = public.get_my_profile_id()) OR ((bulk_emploc_uploads.uploaded_by_user_id IS NULL) AND (bulk_emploc_uploads.uploaded_by = public.get_my_full_name())))))));



  create policy "bulk_items_update_admin"
  on "public"."bulk_emploc_items"
  as permissive
  for update
  to public
using (public.i_have_full_access());



  create policy "bulk_uploads_insert_scoped"
  on "public"."bulk_emploc_uploads"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (uploaded_by_user_id = public.get_my_profile_id())));



  create policy "bulk_uploads_read_scoped"
  on "public"."bulk_emploc_uploads"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (uploaded_by_user_id = public.get_my_profile_id()) OR ((uploaded_by_user_id IS NULL) AND (uploaded_by = public.get_my_full_name()))));



  create policy "bulk_uploads_update_admin"
  on "public"."bulk_emploc_uploads"
  as permissive
  for update
  to public
using (public.i_have_full_access());



  create policy "deact_audit_insert_auth"
  on "public"."deactivation_audit_log"
  as permissive
  for insert
  to authenticated
with check ((performed_by = public.get_my_full_name()));



  create policy "deact_audit_read_admin"
  on "public"."deactivation_audit_log"
  as permissive
  for select
  to authenticated
using (public.i_have_full_access());



  create policy "deact_batches_read_scoped"
  on "public"."deactivation_batches"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (created_by = public.get_my_full_name())));



  create policy "deact_batches_write_admin"
  on "public"."deactivation_batches"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "deact_items_read_scoped"
  on "public"."deactivation_items"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "deact_items_write_admin"
  on "public"."deactivation_items"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "deact_req_insert_ops_only"
  on "public"."deactivation_requests"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (public.i_am_ops() AND (requested_by = public.get_my_full_name()))));



  create policy "deact_requests_read_scoped"
  on "public"."deactivation_requests"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (requested_by = public.get_my_full_name())));



  create policy "activity_log_insert_auth"
  on "public"."employee_activity_log"
  as permissive
  for insert
  to authenticated
with check ((performed_by = public.get_my_full_name()));



  create policy "activity_log_read_scoped"
  on "public"."employee_activity_log"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (vcode IN ( SELECT v.vcode
   FROM public.vacancies v
  WHERE (v.account = ANY (public.get_my_allowed_accounts()))))));



  create policy "deployments_read_scoped"
  on "public"."employee_deployments"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "deployments_write_admin"
  on "public"."employee_deployments"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "pol_transfer_encoder_only_insert"
  on "public"."employee_transfers"
  as restrictive
  for insert
  to authenticated
with check ((public.get_my_role() = ANY (ARRAY['Encoder'::text, 'Super Admin'::text, 'Head Admin'::text, 'OM'::text, 'HRCO'::text, 'Recruitment'::text])));



  create policy "transfers_insert_scoped"
  on "public"."employee_transfers"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (requested_by = public.get_my_full_name())));



  create policy "transfers_read_scoped"
  on "public"."employee_transfers"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (requested_by = public.get_my_full_name())));



  create policy "employees_read_scoped"
  on "public"."employees"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "employees_write_scoped"
  on "public"."employees"
  as permissive
  for all
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "feedback_insert_auth"
  on "public"."feedback_reports"
  as permissive
  for insert
  to authenticated
with check ((submitted_by = public.get_my_full_name()));



  create policy "feedback_read_scoped"
  on "public"."feedback_reports"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (submitted_by = public.get_my_full_name())));



  create policy "feedback_update_admin"
  on "public"."feedback_reports"
  as permissive
  for update
  to authenticated
using (public.i_have_full_access());



  create policy "groups_write_admin"
  on "public"."groups"
  as permissive
  for all
  to public
using (public.i_have_full_access());



  create policy "hcreq_insert_ops_scoped"
  on "public"."headcount_requests"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (public.i_am_ops() AND (account_name_snapshot = ANY (public.get_my_allowed_accounts())))));



  create policy "hcreq_select_scoped"
  on "public"."headcount_requests"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (account_name_snapshot = ANY (public.get_my_allowed_accounts())) OR (requested_by_user_id = public.get_current_profile_id())));



  create policy "hr_emploc_hide_deleted"
  on "public"."hr_emploc"
  as restrictive
  for select
  to authenticated
using (((deleted_at IS NULL) OR public.i_have_full_access()));



  create policy "hr_emploc_read_scoped"
  on "public"."hr_emploc"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "hr_emploc_write_scoped"
  on "public"."hr_emploc"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "correction_attach_insert"
  on "public"."hr_emploc_correction_attachments"
  as permissive
  for insert
  to authenticated
with check ((public.i_have_full_access() OR (EXISTS ( SELECT 1
   FROM public.users_profile up
  WHERE ((up.is_active = true) AND (up.id = public.get_my_profile_id()) AND (replace(lower(COALESCE(up.role, ''::text)), '_'::text, ' '::text) = 'hrco'::text))))));



  create policy "correction_attach_insert_auth_uid"
  on "public"."hr_emploc_correction_attachments"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.users_profile up
  WHERE ((up.is_active = true) AND (up.auth_user_id = auth.uid()) AND (replace(lower(COALESCE(up.role, ''::text)), '_'::text, ' '::text) = ANY (ARRAY['super admin'::text, 'hrco'::text]))))));



  create policy "correction_attach_insert_uploaded_by_profile"
  on "public"."hr_emploc_correction_attachments"
  as permissive
  for insert
  to authenticated
with check ((EXISTS ( SELECT 1
   FROM public.users_profile up
  WHERE ((up.is_active = true) AND (up.id = hr_emploc_correction_attachments.uploaded_by) AND (replace(lower(COALESCE(up.role, ''::text)), '_'::text, ' '::text) = ANY (ARRAY['super admin'::text, 'hrco'::text]))))));



  create policy "correction_attach_read"
  on "public"."hr_emploc_correction_attachments"
  as permissive
  for select
  to authenticated
using (((is_deleted = false) AND (public.i_have_full_access() OR public.i_am_hr_dept() OR (EXISTS ( SELECT 1
   FROM public.hr_emploc he
  WHERE ((he.id = hr_emploc_correction_attachments.hr_emploc_id) AND (he.hrco_user_id_snapshot = public.get_my_profile_id())))))));



  create policy "correction_attach_update"
  on "public"."hr_emploc_correction_attachments"
  as permissive
  for update
  to authenticated
using ((public.i_have_full_access() OR (EXISTS ( SELECT 1
   FROM public.hr_emploc he
  WHERE ((he.id = hr_emploc_correction_attachments.hr_emploc_id) AND (he.hrco_user_id_snapshot = public.get_my_profile_id()) AND (he.deleted_at IS NULL))))))
with check (true);



  create policy "deletion_activities_read_scoped"
  on "public"."hr_emploc_deletion_activities"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM public.hr_emploc_deletion_requests r
  WHERE ((r.id = hr_emploc_deletion_activities.request_id) AND (public.i_have_full_access() OR (r.account = ANY (public.get_my_allowed_accounts())) OR (r.requested_by_user_id = public.get_my_profile_id()))))));



  create policy "deletion_req_insert_ops_only"
  on "public"."hr_emploc_deletion_requests"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (public.i_am_ops() AND (account = ANY (public.get_my_allowed_accounts())))));



  create policy "deletion_req_read_scoped"
  on "public"."hr_emploc_deletion_requests"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts())) OR (requested_by = public.get_my_full_name())));



  create policy "deletion_req_update_admin"
  on "public"."hr_emploc_deletion_requests"
  as permissive
  for update
  to public
using (public.i_have_full_access());



  create policy "issue_types_write_admin"
  on "public"."hr_emploc_issue_types"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access())
with check (public.i_have_full_access());



  create policy "rejection_reasons_write_admin"
  on "public"."hr_emploc_rejection_reasons"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "login_sessions_read"
  on "public"."login_sessions"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (auth_uid = auth.uid())));



  create policy "mika_logs_approve_superadmin"
  on "public"."mika_import_logs"
  as permissive
  for update
  to public
using (public.i_am_super_admin());



  create policy "mika_logs_insert_admin"
  on "public"."mika_import_logs"
  as permissive
  for insert
  to public
with check (public.i_have_full_access());



  create policy "mika_logs_read_scoped"
  on "public"."mika_import_logs"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (uploaded_by = public.get_my_full_name())));



  create policy "mika_rows_read_scoped"
  on "public"."mika_import_rows"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "mika_rows_write_admin"
  on "public"."mika_import_rows"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "notif_select_own"
  on "public"."notifications"
  as permissive
  for select
  to public
using (((recipient_user_id = auth.uid()) OR public.i_have_full_access()));



  create policy "plantilla_insert_scoped"
  on "public"."plantilla"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR ((NOT public.i_am_recruitment()) AND (NOT public.i_am_hr_dept()) AND (account = ANY (public.get_my_allowed_accounts())))));



  create policy "plantilla_read_scoped"
  on "public"."plantilla"
  as permissive
  for select
  to public
using ((public.i_can_view_plantilla() AND (public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))) AND (COALESCE(is_deleted, false) = false) AND ((deactivated_visible_until IS NULL) OR (deactivated_visible_until > now()))));



  create policy "plantilla_update_scoped"
  on "public"."plantilla"
  as permissive
  for update
  to public
using ((public.i_have_full_access() OR (public.i_can_act_on_plantilla() AND (account = ANY (public.get_my_allowed_accounts())))))
with check ((public.i_have_full_access() OR (public.i_can_act_on_plantilla() AND (account = ANY (public.get_my_allowed_accounts())))));



  create policy "approvals_insert_admin"
  on "public"."plantilla_approvals"
  as permissive
  for insert
  to public
with check (public.i_have_full_access());



  create policy "approvals_read_admin"
  on "public"."plantilla_approvals"
  as permissive
  for select
  to public
using (public.i_have_full_access());



  create policy "approvals_update_admin"
  on "public"."plantilla_approvals"
  as permissive
  for update
  to public
using (public.i_have_full_access());



  create policy "positions_write_admin"
  on "public"."positions"
  as permissive
  for all
  to public
using (public.i_have_full_access());



  create policy "ghost_employees_read_ops_scoped"
  on "public"."possible_ghost_employees"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (public.i_am_ops() AND (account = ANY (public.get_my_allowed_accounts())))));



  create policy "ghost_employees_write_admin"
  on "public"."possible_ghost_employees"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR ((public.get_my_role_level() = 30) AND (account = ANY (public.get_my_allowed_accounts())))));



  create policy "qa_evidence_read"
  on "public"."qa_agent_evidence"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_evidence_write"
  on "public"."qa_agent_evidence"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_findings_read"
  on "public"."qa_agent_findings"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_findings_write"
  on "public"."qa_agent_findings"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_rules_write"
  on "public"."qa_agent_rules"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_runs_insert"
  on "public"."qa_agent_runs"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_runs_read"
  on "public"."qa_agent_runs"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (initiated_by = public.get_current_profile_id())));



  create policy "qa_runs_update"
  on "public"."qa_agent_runs"
  as permissive
  for update
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_daily_reports_read"
  on "public"."qa_daily_reports"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_daily_reports_write"
  on "public"."qa_daily_reports"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_health_metrics_read"
  on "public"."qa_health_metrics"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_health_metrics_write"
  on "public"."qa_health_metrics"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_notifications_read"
  on "public"."qa_notifications"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_notifications_write"
  on "public"."qa_notifications"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_run_queue_read"
  on "public"."qa_run_queue"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_run_queue_write"
  on "public"."qa_run_queue"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_schedules_read"
  on "public"."qa_schedules"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "qa_schedules_write"
  on "public"."qa_schedules"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() >= 90)));



  create policy "remote_tasks_admin_only"
  on "public"."remote_tasks"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "roving_assignments_insert"
  on "public"."roving_assignments"
  as permissive
  for insert
  to authenticated
with check ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "roving_assignments_select"
  on "public"."roving_assignments"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "roving_assignments_update"
  on "public"."roving_assignments"
  as permissive
  for update
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))))
with check ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "security_events_select_super_admin"
  on "public"."security_events"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM (public.users_profile up
     JOIN public.roles r ON ((r.id = up.role_id)))
  WHERE ((up.auth_user_id = auth.uid()) AND (r.role_level >= 100)))));



  create policy "sla_breach_read"
  on "public"."sla_breach_logs"
  as permissive
  for select
  to public
using ((public.get_my_role() = ANY (ARRAY['Super Admin'::text, 'Head Admin'::text, 'OM'::text])));



  create policy "staging_imports_admin_insert"
  on "public"."staging_imports"
  as permissive
  for insert
  to authenticated
with check (public.i_have_full_access());



  create policy "staging_imports_admin_select"
  on "public"."staging_imports"
  as permissive
  for select
  to authenticated
using (public.i_have_full_access());



  create policy "staging_imports_admin_update"
  on "public"."staging_imports"
  as permissive
  for update
  to authenticated
using (public.i_have_full_access())
with check (public.i_have_full_access());



  create policy "sib_insert"
  on "public"."store_import_batches"
  as permissive
  for insert
  to public
with check (((public.get_my_role_level() >= 90) AND (uploaded_by = auth.uid())));



  create policy "sib_select"
  on "public"."store_import_batches"
  as permissive
  for select
  to authenticated
using ((public.is_super_admin() OR ((public.get_my_role_level() >= 90) AND (uploaded_by = auth.uid()))));



  create policy "sib_update"
  on "public"."store_import_batches"
  as permissive
  for update
  to authenticated
using ((public.is_super_admin() OR ((public.get_my_role_level() >= 90) AND (uploaded_by = auth.uid()))))
with check ((public.is_super_admin() OR ((public.get_my_role_level() >= 90) AND (uploaded_by = auth.uid()))));



  create policy "sir_insert"
  on "public"."store_import_rows"
  as permissive
  for insert
  to public
with check ((EXISTS ( SELECT 1
   FROM public.store_import_batches b
  WHERE ((b.id = store_import_rows.batch_id) AND (public.is_super_admin() OR ((public.get_my_role_level() = 90) AND (b.uploaded_by = auth.uid())))))));



  create policy "sir_select"
  on "public"."store_import_rows"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM public.store_import_batches b
  WHERE ((b.id = store_import_rows.batch_id) AND (public.is_super_admin() OR ((public.get_my_role_level() >= 90) AND (b.uploaded_by = auth.uid())))))));



  create policy "stores_read_scoped"
  on "public"."stores"
  as permissive
  for select
  to authenticated
using (((is_active = true) AND (public.i_have_full_access() OR (account_id IN ( SELECT a.id
   FROM public.accounts a
  WHERE (a.account_name = ANY (public.get_my_allowed_accounts())))))));



  create policy "stores_write_admin"
  on "public"."stores"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access())
with check (public.i_have_full_access());



  create policy "temp_approval_access_admin_only"
  on "public"."temp_approval_access"
  as permissive
  for all
  to public
using (public.i_have_full_access())
with check (public.i_have_full_access());



  create policy "temp_approval_access_read_own"
  on "public"."temp_approval_access"
  as permissive
  for select
  to public
using (((granted_to = public.get_current_profile_id()) AND (revoked_at IS NULL) AND (valid_until > now())));



  create policy "temp_overrides_read_scoped"
  on "public"."temp_permission_overrides"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (user_id = public.get_my_profile_id())));



  create policy "temp_overrides_write_superadmin"
  on "public"."temp_permission_overrides"
  as permissive
  for all
  to public
using (public.is_super_admin());



  create policy "account_transfers_admin_only"
  on "public"."user_account_transfers"
  as permissive
  for all
  to public
using (public.i_have_full_access())
with check (public.i_have_full_access());



  create policy "account_transfers_own_read"
  on "public"."user_account_transfers"
  as permissive
  for select
  to public
using ((user_profile_id = public.get_current_profile_id()));



  create policy "user_scopes_read_own"
  on "public"."user_scopes"
  as permissive
  for select
  to public
using (((user_id = public.get_my_profile_id()) OR public.i_have_full_access()));



  create policy "user_scopes_write_admin"
  on "public"."user_scopes"
  as permissive
  for all
  to public
using (public.i_have_full_access());



  create policy "users_profile_insert_guarded"
  on "public"."users_profile"
  as permissive
  for insert
  to public
with check (((public.is_super_admin() AND (( SELECT r.role_level
   FROM public.roles r
  WHERE (r.id = users_profile.role_id)) < 100)) OR ((public.get_my_role_level() = 90) AND (( SELECT r.role_level
   FROM public.roles r
  WHERE (r.id = users_profile.role_id)) < 90))));



  create policy "users_profile_read_scoped"
  on "public"."users_profile"
  as permissive
  for select
  to public
using (((auth_user_id = auth.uid()) OR public.is_super_admin() OR ((public.get_my_role_level() = 90) AND (( SELECT r.role_level
   FROM public.roles r
  WHERE (r.id = users_profile.role_id)) < 100))));



  create policy "users_profile_update_guarded"
  on "public"."users_profile"
  as permissive
  for update
  to public
using (((auth_user_id = auth.uid()) OR public.can_manage_target_user(id)));



  create policy "pol_vacancy_hrco_no_approve"
  on "public"."vacancies"
  as restrictive
  for update
  to authenticated
using (true)
with check ((NOT ((public.get_my_role() = 'HRCO'::text) AND (status = ANY (ARRAY['Filled'::text, 'Closed'::text, 'Archived'::text])))));



  create policy "vacancies_block_hr_personnel"
  on "public"."vacancies"
  as restrictive
  for all
  to authenticated
using ((COALESCE(public.get_my_role(), ''::text) <> 'HR Personnel'::text))
with check ((COALESCE(public.get_my_role(), ''::text) <> 'HR Personnel'::text));



  create policy "vacancies_hide_deleted"
  on "public"."vacancies"
  as restrictive
  for select
  to authenticated
using (((deleted_at IS NULL) OR public.i_have_full_access()));



  create policy "vacancies_read_scoped"
  on "public"."vacancies"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR ((account = ANY (public.get_my_allowed_accounts())) AND (status <> ALL (ARRAY['Filled'::text, 'Closed'::text, 'Archived'::text])) AND (COALESCE(is_archived, false) = false))));



  create policy "vacancies_write_scoped"
  on "public"."vacancies"
  as permissive
  for all
  to public
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "closure_reasons_write_admin"
  on "public"."vacancy_closure_reasons"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "closure_req_insert_ops_scoped"
  on "public"."vacancy_closure_requests"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (public.i_am_ops() AND (vacancy_vcode IN ( SELECT vacancies.vcode
   FROM public.vacancies
  WHERE (vacancies.account = ANY (public.get_my_allowed_accounts())))))));



  create policy "closure_req_update_encoder_plus"
  on "public"."vacancy_closure_requests"
  as permissive
  for update
  to public
using ((public.i_have_full_access() OR ((public.get_my_role_level() = 30) AND (vacancy_vcode IN ( SELECT v.vcode
   FROM public.vacancies v
  WHERE (v.account = ANY (public.get_my_allowed_accounts())))))));



  create policy "vacancy_closure_req_read_scoped"
  on "public"."vacancy_closure_requests"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (requested_by = public.get_my_full_name()) OR (requested_by_user_id = public.get_my_profile_id()) OR (vacancy_vcode IN ( SELECT v.vcode
   FROM public.vacancies v
  WHERE (v.account = ANY (public.get_my_allowed_accounts()))))));



  create policy "vacancy_coverage_insert"
  on "public"."vacancy_coverage"
  as permissive
  for insert
  to authenticated
with check ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "vacancy_coverage_select"
  on "public"."vacancy_coverage"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "vacancy_coverage_update"
  on "public"."vacancy_coverage"
  as permissive
  for update
  to authenticated
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))))
with check ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts()))));



  create policy "vreq_insert_ops_scoped"
  on "public"."vacancy_requests"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (public.i_am_ops() AND (account = ANY (public.get_my_allowed_accounts())))));



  create policy "vreq_select_scoped"
  on "public"."vacancy_requests"
  as permissive
  for select
  to public
using ((public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts())) OR (requested_by = public.get_my_full_name())));



  create policy "admin_read_vcode_sequences"
  on "public"."vcode_sequences"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM (public.users_profile up
     JOIN public.roles r ON ((r.id = up.role_id)))
  WHERE ((up.auth_user_id = auth.uid()) AND (r.role_level >= 90)))));



  create policy "vcodes_read_scoped"
  on "public"."vcodes"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (account_code = ANY (public.get_my_allowed_accounts()))));



  create policy "vcodes_write_admin"
  on "public"."vcodes"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access())
with check (public.i_have_full_access());



  create policy "war_data_team_all"
  on "public"."workforce_assignment_requests"
  as permissive
  for all
  to authenticated
using (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()))
with check (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()));



  create policy "war_ops_select"
  on "public"."workforce_assignment_requests"
  as permissive
  for select
  to authenticated
using ((((public.get_my_role_level() >= 40) AND (public.get_my_role_level() <= 70)) AND ((requested_by_id = auth.uid()) OR ((requested_account_id)::text = ANY (public.get_my_allowed_accounts())))));



  create policy "wa_read_scoped"
  on "public"."workforce_assignments"
  as permissive
  for select
  to authenticated
using (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access() OR (((public.get_my_role_level() >= 40) AND (public.get_my_role_level() <= 70)) AND ((assigned_account_id)::text = ANY (public.get_my_allowed_accounts())) AND public.can_view_pool_employee(employee_id))));



  create policy "wa_write_data_team"
  on "public"."workforce_assignments"
  as permissive
  for all
  to authenticated
using (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()))
with check (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()));



  create policy "wf_pool_conversion_insert_rpc_only"
  on "public"."workforce_pool_conversion_requests"
  as permissive
  for insert
  to authenticated
with check ((public.i_have_full_access() OR (public.i_am_ops() AND (requested_by = public.get_my_profile_id()) AND (target_account_id IN ( SELECT get_my_scoped_accounts.account_id
   FROM public.get_my_scoped_accounts() get_my_scoped_accounts(account_id, account_name, account_code, group_id, group_name))))));



  create policy "wf_pool_conversion_read_scoped"
  on "public"."workforce_pool_conversion_requests"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (public.get_my_role_level() = 30) OR (requested_by = public.get_my_profile_id()) OR (target_account_id IN ( SELECT get_my_scoped_accounts.account_id
   FROM public.get_my_scoped_accounts() get_my_scoped_accounts(account_id, account_name, account_code, group_id, group_name)))));



  create policy "wf_pool_conversion_update_data_team"
  on "public"."workforce_pool_conversion_requests"
  as permissive
  for update
  to authenticated
using ((public.i_have_full_access() OR (public.get_my_role_level() = 30)))
with check ((public.i_have_full_access() OR (public.get_my_role_level() = 30)));



  create policy "wpri_read_data_team_or_scoped"
  on "public"."workforce_pool_request_items"
  as permissive
  for select
  to authenticated
using (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access() OR (EXISTS ( SELECT 1
   FROM public.workforce_pool_requests r
  WHERE ((r.id = workforce_pool_request_items.request_id) AND (r.deleted_at IS NULL) AND (r.requesting_account = ANY (public.get_my_allowed_accounts())))))));



  create policy "wpri_write_data_team"
  on "public"."workforce_pool_request_items"
  as permissive
  for all
  to authenticated
using (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()))
with check (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()));



  create policy "wpr_read_data_team_or_scoped"
  on "public"."workforce_pool_requests"
  as permissive
  for select
  to authenticated
using (((deleted_at IS NULL) AND ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access() OR (requesting_account = ANY (public.get_my_allowed_accounts())))));



  create policy "wpr_write_data_team"
  on "public"."workforce_pool_requests"
  as permissive
  for all
  to authenticated
using (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()))
with check (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()));



  create policy "wps_read_data_team_or_scoped"
  on "public"."workforce_pool_slots"
  as permissive
  for select
  to authenticated
using (((deleted_at IS NULL) AND ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access() OR (account = ANY (public.get_my_allowed_accounts())))));



  create policy "wps_write_data_team"
  on "public"."workforce_pool_slots"
  as permissive
  for all
  to authenticated
using (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()))
with check (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()));



  create policy "wpt_write_data_team"
  on "public"."workforce_pool_types"
  as permissive
  for all
  to authenticated
using ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])))
with check ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])));



  create policy "wpvs_no_direct_access"
  on "public"."workforce_pool_vcode_sequences"
  as permissive
  for all
  to authenticated
using ((public.get_my_role_level() = 100));



  create policy "wsr_read_data_team"
  on "public"."workforce_slot_reviews"
  as permissive
  for select
  to authenticated
using (((deleted_at IS NULL) AND ((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access())));



  create policy "wsr_write_data_team"
  on "public"."workforce_slot_reviews"
  as permissive
  for all
  to authenticated
using (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()))
with check (((public.get_my_role_level() = ANY (ARRAY[100, 90, 30])) OR public.i_have_full_access()));


CREATE TRIGGER trg_account_requests_updated_at BEFORE UPDATE ON public.account_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_notify_account_request_actioned AFTER UPDATE ON public.account_requests FOR EACH ROW WHEN (((new.status)::text IS DISTINCT FROM (old.status)::text)) EXECUTE FUNCTION public.notify_account_request_actioned();

CREATE TRIGGER trg_notify_account_request_submitted AFTER INSERT ON public.account_requests FOR EACH ROW EXECUTE FUNCTION public.notify_account_request_submitted();

CREATE TRIGGER trg_account_deactivation_cascade AFTER UPDATE ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.trg_account_deactivation_cascade();

CREATE TRIGGER trg_profile_edit_request_updated_at BEFORE UPDATE ON public.applicant_profile_edit_requests FOR EACH ROW EXECUTE FUNCTION public.trg_fn_profile_edit_request_updated_at();

CREATE TRIGGER trg_status_options_updated_at BEFORE UPDATE ON public.applicant_status_options FOR EACH ROW EXECUTE FUNCTION public.trg_fn_status_options_updated_at();

CREATE TRIGGER on_applicant_hired_log AFTER UPDATE ON public.applicants FOR EACH ROW EXECUTE FUNCTION public.log_applicant_hired();

CREATE TRIGGER trg_applicants_updated_at BEFORE UPDATE ON public.applicants FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_audit_applicants AFTER INSERT OR UPDATE ON public.applicants FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();

CREATE TRIGGER trg_set_hired_visible_until BEFORE INSERT OR UPDATE ON public.applicants FOR EACH ROW EXECUTE FUNCTION public.trg_fn_set_hired_visible_until();

CREATE TRIGGER on_deactivation_notify AFTER INSERT ON public.deactivation_requests FOR EACH ROW EXECUTE FUNCTION public.notify_deactivation_submitted();

CREATE TRIGGER on_deactivation_request_insert BEFORE INSERT ON public.deactivation_requests FOR EACH ROW EXECUTE FUNCTION public.generate_batch_code();

CREATE TRIGGER on_transfer_approved AFTER UPDATE ON public.employee_transfers FOR EACH ROW EXECUTE FUNCTION public.handle_transfer_approved();

CREATE TRIGGER trg_audit_employee_transfers AFTER INSERT OR UPDATE ON public.employee_transfers FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();

CREATE TRIGGER trg_notify_transfer_submitted AFTER INSERT ON public.employee_transfers FOR EACH ROW EXECUTE FUNCTION public.fn_notify_transfer_submitted();

CREATE TRIGGER on_employee_resignation AFTER UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.handle_employee_resignation();

CREATE TRIGGER trg_hcreq_touch BEFORE UPDATE ON public.headcount_requests FOR EACH ROW EXECUTE FUNCTION public.fn_touch_updated_at();

CREATE TRIGGER trg_notify_hc_request_actioned AFTER UPDATE ON public.headcount_requests FOR EACH ROW WHEN (((new.status IS DISTINCT FROM old.status) OR (new.created_vcode IS DISTINCT FROM old.created_vcode) OR (new.created_vcodes IS DISTINCT FROM old.created_vcodes))) EXECUTE FUNCTION public.notify_hc_request_actioned();

CREATE TRIGGER trg_notify_hc_request_approved_pending_vcode AFTER UPDATE OF status ON public.headcount_requests FOR EACH ROW WHEN (((old.status IS DISTINCT FROM new.status) AND (new.status = 'approved_pending_vcode'::text))) EXECUTE FUNCTION public.notify_hc_request_approved_pending_vcode();

CREATE TRIGGER trg_notify_hc_request_submitted AFTER INSERT ON public.headcount_requests FOR EACH ROW EXECUTE FUNCTION public.notify_hc_request_submitted();

CREATE TRIGGER hr_emploc_resolve_account_fk BEFORE INSERT OR UPDATE OF account, account_id ON public.hr_emploc FOR EACH ROW EXECUTE FUNCTION public.tg_hr_emploc_resolve_account_fk();

CREATE TRIGGER on_emploc_no_entered BEFORE UPDATE ON public.hr_emploc FOR EACH ROW EXECUTE FUNCTION public.handle_emploc_no_entered();

CREATE TRIGGER on_emploc_no_entered_insert BEFORE INSERT ON public.hr_emploc FOR EACH ROW EXECUTE FUNCTION public.handle_emploc_no_entered();

CREATE TRIGGER on_hr_emploc_inserted AFTER INSERT ON public.hr_emploc FOR EACH ROW EXECUTE FUNCTION public.check_vacancy_headcount();

CREATE TRIGGER on_hr_emploc_rejected AFTER UPDATE ON public.hr_emploc FOR EACH ROW EXECUTE FUNCTION public.handle_hr_emploc_rejected();

CREATE TRIGGER trg_audit_hr_emploc AFTER INSERT OR UPDATE ON public.hr_emploc FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();

CREATE TRIGGER trg_hr_emploc_pending_deletion_lock BEFORE UPDATE ON public.hr_emploc FOR EACH ROW EXECUTE FUNCTION public.tg_hr_emploc_pending_deletion_lock();

CREATE TRIGGER trg_notify_hr_emploc_correction_submitted AFTER UPDATE ON public.hr_emploc FOR EACH ROW WHEN (((new.hr_status = 'For Review'::text) AND (old.hr_status = 'For Correction'::text))) EXECUTE FUNCTION public.notify_hr_emploc_correction_submitted();

CREATE TRIGGER trg_notify_hr_emploc_correction_tagged AFTER UPDATE ON public.hr_emploc FOR EACH ROW WHEN (((new.hr_status = 'For Correction'::text) AND (old.hr_status IS DISTINCT FROM 'For Correction'::text))) EXECUTE FUNCTION public.notify_hr_emploc_correction_tagged();

CREATE TRIGGER trg_notify_hr_emploc_to_plantilla AFTER UPDATE ON public.hr_emploc FOR EACH ROW WHEN (((new.status = 'Moved to Plantilla'::text) AND (old.status IS DISTINCT FROM 'Moved to Plantilla'::text))) EXECUTE FUNCTION public.notify_hr_emploc_to_plantilla();

CREATE TRIGGER trg_sync_emploc_employee_no_hr BEFORE INSERT OR UPDATE OF employee_no, emploc_no ON public.hr_emploc FOR EACH ROW EXECUTE FUNCTION public.tg_sync_emploc_employee_no();

CREATE TRIGGER set_correction_attach_uploaded_by BEFORE INSERT ON public.hr_emploc_correction_attachments FOR EACH ROW EXECUTE FUNCTION public.trg_set_correction_attach_uploaded_by();

CREATE TRIGGER on_emploc_deletion_approved AFTER UPDATE ON public.hr_emploc_deletion_requests FOR EACH ROW EXECUTE FUNCTION public.handle_emploc_deletion_approved();

CREATE TRIGGER on_emploc_deletion_requested AFTER INSERT ON public.hr_emploc_deletion_requests FOR EACH ROW EXECUTE FUNCTION public.handle_emploc_deletion_requested();

CREATE TRIGGER trg_hr_emploc_store_links_updated_at BEFORE UPDATE ON public.hr_emploc_store_links FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER trg_ghost_resolve_on_mika_approved AFTER UPDATE OF status ON public.mika_import_logs FOR EACH ROW EXECUTE FUNCTION public.trg_fn_ghost_resolve_on_mika_approved();

CREATE TRIGGER trg_notify_mika_import_actioned AFTER UPDATE ON public.mika_import_logs FOR EACH ROW WHEN ((new.status IS DISTINCT FROM old.status)) EXECUTE FUNCTION public.notify_mika_import_actioned();

CREATE TRIGGER trg_notify_mika_import_uploaded AFTER INSERT ON public.mika_import_logs FOR EACH ROW EXECUTE FUNCTION public.notify_mika_import_uploaded();

CREATE TRIGGER on_plantilla_insert_log AFTER INSERT ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.log_moved_to_plantilla();

CREATE TRIGGER on_plantilla_resign_log AFTER UPDATE ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.log_employee_resigned();

CREATE TRIGGER on_plantilla_sla_check AFTER UPDATE ON public.plantilla FOR EACH ROW WHEN (((new.separation_status = 'Resigned'::text) AND (old.separation_status IS DISTINCT FROM 'Resigned'::text))) EXECUTE FUNCTION public.handle_sla_breach_check();

CREATE TRIGGER plantilla_resolve_account_fk BEFORE INSERT OR UPDATE OF account, account_id ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.tg_plantilla_resolve_account_fk();

CREATE TRIGGER tg_close_vacancy_on_plantilla_active_insert AFTER INSERT ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.tg_close_vacancy_on_plantilla_active_insert();

CREATE TRIGGER trg_audit_plantilla AFTER INSERT OR UPDATE ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();

CREATE TRIGGER trg_ghost_resolve_on_plantilla_active AFTER INSERT OR UPDATE OF status, employee_no ON public.plantilla FOR EACH ROW WHEN (((new.status = 'Active'::text) AND (new.employee_no IS NOT NULL))) EXECUTE FUNCTION public.trg_fn_ghost_resolve_on_plantilla_active();

CREATE TRIGGER trg_notify_separation AFTER UPDATE ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.fn_notify_separation();

CREATE TRIGGER trg_plantilla_depart_create_vacancy AFTER UPDATE OF separation_status ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.trg_fn_plantilla_depart_create_vacancy();

CREATE TRIGGER trg_plantilla_separation_to_vacancy AFTER UPDATE ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.fn_plantilla_separation_to_vacancy();

CREATE TRIGGER trg_plantilla_updated_at BEFORE UPDATE ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_sla_breach AFTER UPDATE ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.fn_trigger_sla_breach();

CREATE TRIGGER trg_sync_emploc_employee_no_pl BEFORE INSERT OR UPDATE OF employee_no, emploc_no ON public.plantilla FOR EACH ROW EXECUTE FUNCTION public.tg_sync_emploc_employee_no();

CREATE TRIGGER trg_plantilla_store_links_updated_at BEFORE UPDATE ON public.plantilla_store_links FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER on_ghost_encoding_assigned BEFORE UPDATE ON public.possible_ghost_employees FOR EACH ROW EXECUTE FUNCTION public.handle_ghost_encoding_assigned();

CREATE TRIGGER trg_refresh_users_profile_role_after_roles_update AFTER UPDATE OF role_name ON public.roles FOR EACH ROW EXECUTE FUNCTION public.refresh_users_profile_role_after_roles_update();

CREATE TRIGGER trg_roving_assignments_set_updated_at BEFORE UPDATE ON public.roving_assignments FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER trg_audit_store_import_batches AFTER INSERT OR DELETE OR UPDATE ON public.store_import_batches FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();

CREATE TRIGGER trg_notify_store_import_actioned AFTER UPDATE ON public.store_import_batches FOR EACH ROW WHEN ((new.status IS DISTINCT FROM old.status)) EXECUTE FUNCTION public.notify_store_import_actioned();

CREATE TRIGGER trg_notify_store_import_uploaded AFTER INSERT ON public.store_import_batches FOR EACH ROW EXECUTE FUNCTION public.notify_store_import_uploaded();

CREATE TRIGGER trg_sib_touch BEFORE UPDATE ON public.store_import_batches FOR EACH ROW EXECUTE FUNCTION public.fn_touch_updated_at();

CREATE TRIGGER trg_stores_sync_ins BEFORE INSERT ON public.stores FOR EACH ROW EXECUTE FUNCTION public.fn_stores_sync_legacy_ins();

CREATE TRIGGER trg_stores_sync_upd BEFORE UPDATE ON public.stores FOR EACH ROW EXECUTE FUNCTION public.fn_stores_sync_legacy_upd();

CREATE TRIGGER trg_validate_temp_override BEFORE INSERT OR UPDATE ON public.temp_permission_overrides FOR EACH ROW EXECUTE FUNCTION public.trg_validate_temp_override();

CREATE TRIGGER trg_enforce_user_hierarchy BEFORE UPDATE ON public.users_profile FOR EACH ROW EXECUTE FUNCTION public.trg_enforce_user_hierarchy();

CREATE TRIGGER trg_sync_users_profile_role_from_role_id BEFORE INSERT OR UPDATE OF role_id ON public.users_profile FOR EACH ROW EXECUTE FUNCTION public.sync_users_profile_role_from_role_id();

CREATE TRIGGER users_profile_audit_trigger AFTER INSERT OR UPDATE ON public.users_profile FOR EACH ROW EXECUTE FUNCTION public.log_users_profile_changes();

CREATE TRIGGER on_vacancy_filled_archive BEFORE UPDATE ON public.vacancies FOR EACH ROW WHEN (((new.status = 'Filled'::text) AND (COALESCE(old.status, ''::text) IS DISTINCT FROM 'Filled'::text))) EXECUTE FUNCTION public.handle_vacancy_filled_archive();

CREATE TRIGGER trg_audit_vacancies AFTER INSERT OR UPDATE ON public.vacancies FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();

CREATE TRIGGER trg_notify_vacancy_approved AFTER UPDATE ON public.vacancies FOR EACH ROW EXECUTE FUNCTION public.fn_notify_vacancy_approved();

CREATE TRIGGER trg_notify_vcode_created AFTER UPDATE ON public.vacancies FOR EACH ROW EXECUTE FUNCTION public.fn_notify_vcode_created();

CREATE TRIGGER trg_vacancies_auto_vcode BEFORE INSERT ON public.vacancies FOR EACH ROW EXECUTE FUNCTION public.trg_auto_assign_vcode();

CREATE TRIGGER on_closure_requested AFTER INSERT ON public.vacancy_closure_requests FOR EACH ROW EXECUTE FUNCTION public.handle_closure_requested();

CREATE TRIGGER on_closure_reviewed AFTER UPDATE ON public.vacancy_closure_requests FOR EACH ROW EXECUTE FUNCTION public.handle_closure_approval();

CREATE TRIGGER trg_prevent_duplicate_closure_request BEFORE INSERT ON public.vacancy_closure_requests FOR EACH ROW EXECUTE FUNCTION public.trg_prevent_duplicate_closure_request();

CREATE TRIGGER trg_vacancy_coverage_set_updated_at BEFORE UPDATE ON public.vacancy_coverage FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER on_vacancy_request_approved AFTER UPDATE ON public.vacancy_requests FOR EACH ROW WHEN (((new.status = 'Approved'::text) AND (old.status IS DISTINCT FROM 'Approved'::text))) EXECUTE FUNCTION public.handle_vacancy_request_approved();

CREATE TRIGGER on_vacancy_request_submitted AFTER INSERT ON public.vacancy_requests FOR EACH ROW EXECUTE FUNCTION public.handle_vacancy_request_submitted();

CREATE TRIGGER on_vcode_created_notify_requestor AFTER UPDATE ON public.vacancy_requests FOR EACH ROW WHEN (((new.vcode_created IS NOT NULL) AND (old.vcode_created IS DISTINCT FROM new.vcode_created))) EXECUTE FUNCTION public.handle_vcode_created_notify_requestor();

drop trigger if exists "on_auth_user_created" on "auth"."users";

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

drop policy "hr_corrections_select_policy" on "storage"."objects";

drop policy "hr_corrections_upload_policy" on "storage"."objects";

drop policy "hr_emploc_attachments_upload_super_admin_hrco" on "storage"."objects";

drop policy "imports_delete" on "storage"."objects";

drop policy "imports_insert" on "storage"."objects";

drop policy "imports_select" on "storage"."objects";


  create policy "hr_corrections_select_policy"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((bucket_id = 'hr-corrections'::text) AND (EXISTS ( SELECT 1
   FROM public.users_profile up
  WHERE ((up.is_active = true) AND ((up.auth_user_id = auth.uid()) OR (up.id = auth.uid())) AND (replace(lower(COALESCE(up.role, ''::text)), '_'::text, ' '::text) = ANY (ARRAY['super admin'::text, 'hrco'::text])))))));



  create policy "hr_corrections_upload_policy"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'hr-corrections'::text) AND (EXISTS ( SELECT 1
   FROM public.users_profile up
  WHERE ((up.is_active = true) AND ((up.auth_user_id = auth.uid()) OR (up.id = auth.uid())) AND (replace(lower(COALESCE(up.role, ''::text)), '_'::text, ' '::text) = ANY (ARRAY['super admin'::text, 'hrco'::text])))))));



  create policy "hr_emploc_attachments_upload_super_admin_hrco"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'hr-emploc-attachments'::text) AND (EXISTS ( SELECT 1
   FROM public.users_profile up
  WHERE ((up.id = auth.uid()) AND (lower(up.role) = ANY (ARRAY['super_admin'::text, 'hrco'::text])))))));



  create policy "imports_delete"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((bucket_id = 'imports'::text) AND public.is_super_admin()));



  create policy "imports_insert"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'imports'::text) AND (public.get_my_role_level() >= 90)));



  create policy "imports_select"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((bucket_id = 'imports'::text) AND (public.get_my_role_level() >= 90)));



