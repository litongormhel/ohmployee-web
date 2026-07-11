create extension if not exists "pg_cron" with schema "pg_catalog";

create extension if not exists "pg_trgm" with schema "extensions";

drop extension if exists "pg_net";

create extension if not exists "pg_net" with schema "public";

create type "public"."account_request_status" as enum ('pending', 'approved', 'rejected');

create type "public"."audit_action" as enum ('INSERT', 'UPDATE', 'SOFT_DELETE', 'APPROVAL', 'BACKOUT', 'START_ACTING_SESSION', 'STOP_ACTING_SESSION');

create type "public"."hr_emploc_assignment_type" as enum ('Stationary', 'Roving');

create type "public"."separation_status" as enum ('AWOL', 'Resigned', 'Endo', 'Others');

create type "public"."staging_import_status" as enum ('pending_validation', 'validated_by_head_admin', 'approved_by_super_admin', 'rejected');

create type "public"."staging_import_type" as enum ('mika', 'plantilla', 'emploc', 'vacancy');

create type "public"."transfer_status" as enum ('Pending', 'Approved', 'Rejected');

create type "public"."vacancy_coverage_status" as enum ('Active', 'Ended', 'Cancelled');

create type "public"."vacancy_coverage_type" as enum ('Reliever', 'Commando');

create type "public"."vacancy_status" as enum ('Open', 'Filled', 'Archived');

create sequence "public"."remote_tasks_id_seq";

create sequence "public"."vcode_seq";


  create table "public"."_deprecated_in_app_notifications" (
    "id" uuid not null default gen_random_uuid(),
    "recipient_role" text not null,
    "notification_type" text not null,
    "title" text not null,
    "message" text not null,
    "reference_id" text,
    "reference_type" text,
    "is_read" boolean default false,
    "created_at" timestamp with time zone default now(),
    "read_at" timestamp with time zone,
    "deep_link_route" text
      );


alter table "public"."_deprecated_in_app_notifications" enable row level security;


  create table "public"."account_positions" (
    "id" uuid not null default gen_random_uuid(),
    "account_id" uuid not null,
    "position_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."account_positions" enable row level security;


  create table "public"."account_request_account_scopes" (
    "id" uuid not null default gen_random_uuid(),
    "account_request_id" uuid not null,
    "account_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );



  create table "public"."account_request_group_scopes" (
    "id" uuid not null default gen_random_uuid(),
    "account_request_id" uuid not null,
    "group_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );



  create table "public"."account_requests" (
    "id" uuid not null default gen_random_uuid(),
    "auth_user_id" uuid,
    "email" text not null,
    "full_name" text not null,
    "requested_role_id" uuid,
    "status" public.account_request_status not null default 'pending'::public.account_request_status,
    "notes" text,
    "reviewed_by" uuid,
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "assigned_scope_type" text,
    "assigned_role_id" uuid,
    "approved_by" uuid,
    "approved_at" timestamp with time zone,
    "rejected_by" uuid,
    "rejected_at" timestamp with time zone,
    "rejection_reason" text,
    "assigned_groups_snapshot" jsonb,
    "assigned_accounts_snapshot" jsonb
      );


alter table "public"."account_requests" enable row level security;


  create table "public"."accounts" (
    "id" uuid not null default gen_random_uuid(),
    "group_id" uuid not null,
    "account_name" text not null,
    "is_active" boolean default true,
    "created_at" timestamp with time zone default now(),
    "om_user_id" uuid,
    "atl_user_id" uuid,
    "status" text not null default 'Active'::text,
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "hrco_user_id" uuid,
    "account_code" text,
    "is_pool_account" boolean not null default false
      );


alter table "public"."accounts" enable row level security;


  create table "public"."acting_sessions" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "acting_role" text not null,
    "acting_group_ids" uuid[] not null default '{}'::uuid[],
    "acting_account_ids" uuid[] not null default '{}'::uuid[],
    "reason" text,
    "is_active" boolean not null default true,
    "started_at" timestamp with time zone not null default now(),
    "expires_at" timestamp with time zone not null default (now() + '08:00:00'::interval),
    "ended_at" timestamp with time zone,
    "created_by" uuid not null,
    "ended_by" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."acting_sessions" enable row level security;


  create table "public"."activity_log" (
    "id" uuid not null default gen_random_uuid(),
    "actor_id" uuid,
    "actor_name" text,
    "actor_role" text,
    "action" text not null,
    "target_table" text not null,
    "target_id" uuid,
    "target_name" text,
    "old_value" jsonb,
    "new_value" jsonb,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."activity_log" enable row level security;


  create table "public"."applicants" (
    "id" uuid not null default gen_random_uuid(),
    "vacancy_vcode" text not null,
    "full_name" text not null,
    "contact_number" text,
    "status" text default 'New'::text,
    "backout_reason" text,
    "created_at" timestamp with time zone default now(),
    "last_name" text,
    "first_name" text,
    "middle_name" text,
    "full_name_snapshot" text,
    "hired_date" date,
    "deployed_by_user_id" uuid,
    "backout_reason_code" text,
    "backout_details" text,
    "backout_date" date,
    "remarks" text,
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "interview_date" date,
    "hired_by" text,
    "hired_by_team" text,
    "hired_at" timestamp with time zone,
    "is_archived" boolean default false,
    "archived_at" timestamp with time zone,
    "roving_assignment_id" uuid,
    "recruited_by_user_id" uuid,
    "recruited_by_name" text,
    "hired_by_user_id" uuid,
    "endorsed_by_deployer_id" uuid,
    "endorsed_by_name" text,
    "hired_visible_until" timestamp with time zone
      );


alter table "public"."applicants" enable row level security;


  create table "public"."audit_logs" (
    "id" uuid not null default gen_random_uuid(),
    "actor_id" uuid,
    "module" text not null,
    "action" public.audit_action not null,
    "record_id" uuid not null,
    "old_data" jsonb,
    "new_data" jsonb,
    "timestamp" timestamp with time zone not null default now(),
    "role" text
      );


alter table "public"."audit_logs" enable row level security;


  create table "public"."backout_reasons" (
    "id" uuid not null default gen_random_uuid(),
    "reason" text not null,
    "is_active" boolean default true,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."backout_reasons" enable row level security;


  create table "public"."bulk_emploc_items" (
    "id" uuid not null default gen_random_uuid(),
    "upload_id" uuid,
    "last_name" text not null,
    "first_name" text not null,
    "middle_name" text,
    "emploc_no" text not null,
    "matched_applicant_id" text,
    "matched_vcode" text,
    "match_status" text default 'Unmatched'::text,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."bulk_emploc_items" enable row level security;


  create table "public"."bulk_emploc_uploads" (
    "id" uuid not null default gen_random_uuid(),
    "uploaded_by" text not null,
    "file_name" text not null,
    "total_rows" integer default 0,
    "matched_rows" integer default 0,
    "unmatched_rows" integer default 0,
    "status" text default 'Pending'::text,
    "reviewed_by" text,
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone default now(),
    "uploaded_by_user_id" uuid
      );


alter table "public"."bulk_emploc_uploads" enable row level security;


  create table "public"."deactivation_audit_log" (
    "id" uuid not null default gen_random_uuid(),
    "request_id" uuid,
    "action" text not null,
    "performed_by" text not null,
    "performed_at" timestamp with time zone default now(),
    "remarks" text
      );


alter table "public"."deactivation_audit_log" enable row level security;


  create table "public"."deactivation_batches" (
    "id" uuid not null default gen_random_uuid(),
    "batch_name" text,
    "created_by" text not null,
    "created_at" timestamp with time zone default now(),
    "total_count" integer default 0,
    "completed_count" integer default 0,
    "rejected_count" integer default 0,
    "status" text default 'Pending'::text
      );


alter table "public"."deactivation_batches" enable row level security;


  create table "public"."deactivation_items" (
    "id" uuid not null default gen_random_uuid(),
    "request_id" uuid,
    "emploc_no" text not null,
    "employee_name" text not null,
    "account" text not null,
    "store_name" text,
    "position" text,
    "resignation_date" date,
    "status" text default 'Pending'::text,
    "rejection_reason" text,
    "processed_by" text,
    "processed_at" timestamp with time zone,
    "created_at" timestamp with time zone default now(),
    "plantilla_id" uuid
      );


alter table "public"."deactivation_items" enable row level security;


  create table "public"."deactivation_requests" (
    "id" uuid not null default gen_random_uuid(),
    "batch_code" text not null,
    "requested_by" text not null,
    "requested_by_role" text not null,
    "group_name" text,
    "status" text default 'Pending'::text,
    "total_employees" integer default 0,
    "deactivated_count" integer default 0,
    "rejected_count" integer default 0,
    "notes" text,
    "reviewed_by" text,
    "reviewed_at" timestamp with time zone,
    "reviewer_remarks" text,
    "download_file_url" text,
    "result_file_url" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "batch_id" text
      );


alter table "public"."deactivation_requests" enable row level security;


  create table "public"."deployer" (
    "id" uuid not null default gen_random_uuid(),
    "name" text not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."deployer" enable row level security;


  create table "public"."employee_activity_log" (
    "id" uuid not null default gen_random_uuid(),
    "emploc_no" text not null,
    "vcode" text,
    "activity_type" text not null,
    "activity_date" timestamp with time zone default now(),
    "description" text not null,
    "performed_by" text,
    "metadata" jsonb,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."employee_activity_log" enable row level security;


  create table "public"."employee_deployments" (
    "id" uuid not null default gen_random_uuid(),
    "employee_id" uuid not null,
    "vcode" text not null,
    "account" text not null,
    "store_name" text,
    "position" text not null,
    "emploc_no" text,
    "status" text not null default 'Active'::text,
    "start_date" date,
    "resignation_date" date,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now()
      );


alter table "public"."employee_deployments" enable row level security;


  create table "public"."employee_transfers" (
    "id" uuid not null default gen_random_uuid(),
    "emploc_no" text not null,
    "employee_name" text not null,
    "from_account" text not null,
    "from_store" text,
    "from_vcode" text,
    "to_account" text not null,
    "to_store" text,
    "to_vcode" text,
    "transfer_date" date default CURRENT_DATE,
    "reason" text,
    "requested_by" text not null,
    "requested_by_role" text not null,
    "status" text default 'Pending'::text,
    "reviewed_by" text,
    "reviewed_at" timestamp with time zone,
    "reviewer_remarks" text,
    "created_at" timestamp with time zone default now(),
    "is_deleted" boolean not null default false,
    "updated_at" timestamp with time zone,
    "plantilla_id" uuid,
    "target_store_id" uuid,
    "target_position_id" uuid,
    "approved_by_user_id" uuid
      );


alter table "public"."employee_transfers" enable row level security;


  create table "public"."employees" (
    "id" uuid not null default gen_random_uuid(),
    "employee_no" text,
    "last_name" text not null,
    "first_name" text not null,
    "middle_name" text,
    "full_name" text not null,
    "contact_number" text,
    "status" text not null default 'Active'::text,
    "resignation_date" date,
    "resignation_remarks" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "account" text,
    "store_name" text,
    "position" text,
    "address" text,
    "civil_status" text,
    "birthdate" date,
    "sss_no" text,
    "philhealth_no" text,
    "pagibig_no" text,
    "tin_no" text,
    "atm_no" text,
    "date_hired" date
      );


alter table "public"."employees" enable row level security;


  create table "public"."feedback_reports" (
    "id" uuid not null default gen_random_uuid(),
    "type" text not null,
    "title" text not null,
    "description" text not null,
    "submitted_by" text not null,
    "submitted_by_role" text not null,
    "module" text,
    "priority" text default 'Normal'::text,
    "status" text default 'Open'::text,
    "resolved_by" text,
    "resolved_at" timestamp with time zone,
    "resolution_notes" text,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."feedback_reports" enable row level security;


  create table "public"."groups" (
    "id" uuid not null default gen_random_uuid(),
    "group_code" text not null,
    "group_name" text not null,
    "om_name" text,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."groups" enable row level security;


  create table "public"."headcount_requests" (
    "id" uuid not null default gen_random_uuid(),
    "account_id" uuid not null,
    "store_id" uuid,
    "position_id" uuid not null,
    "employment_type" text not null,
    "area" text,
    "request_type" text not null,
    "headcount_needed" integer not null default 1,
    "vacant_date" date,
    "target_fill_date" date,
    "urgency" text not null,
    "reason" text,
    "group_id" uuid,
    "account_name_snapshot" text,
    "store_name_snapshot" text,
    "position_name_snapshot" text,
    "group_name_snapshot" text,
    "penalty_per_day" numeric,
    "status" text not null default 'pending'::text,
    "requested_by_user_id" uuid not null,
    "requested_by_name" text not null,
    "requested_by_role" text not null,
    "requested_at" timestamp with time zone not null default now(),
    "reviewed_by_user_id" uuid,
    "reviewed_by_name" text,
    "reviewed_at" timestamp with time zone,
    "reviewer_remarks" text,
    "slot_created_by_user_id" uuid,
    "slot_created_at" timestamp with time zone,
    "created_plantilla_id" uuid,
    "created_vcode" text,
    "is_archived" boolean not null default false,
    "archived_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "om_approved_by_user_id" uuid,
    "om_approved_by_name" text,
    "om_approved_at" timestamp with time zone,
    "om_remarks" text,
    "head_admin_approved_by_user_id" uuid,
    "head_admin_approved_by_name" text,
    "head_admin_approved_at" timestamp with time zone,
    "head_admin_remarks" text,
    "vacancy_created" boolean default false,
    "created_vcodes" text[]
      );


alter table "public"."headcount_requests" enable row level security;


  create table "public"."hr_emploc" (
    "id" uuid not null default gen_random_uuid(),
    "applicant_name" text not null,
    "vcode" text not null,
    "account" text not null,
    "position" text not null,
    "status" text not null default 'Pending Emploc'::text,
    "emploc_no" text,
    "created_at" timestamp with time zone default now(),
    "applicant_id" uuid,
    "vacancy_id" uuid,
    "vacancy_code_snapshot" text,
    "account_id" uuid,
    "chain_id" uuid,
    "store_id" uuid,
    "province_id" uuid,
    "area_name_snapshot" text,
    "hrco_user_id_snapshot" uuid,
    "om_user_id_snapshot" uuid,
    "atl_user_id_snapshot" uuid,
    "position_id_snapshot" uuid,
    "applicant_name_snapshot" text,
    "hired_date" date,
    "deployed_by_user_id" uuid,
    "employee_no" text,
    "employee_lookup_found" boolean not null default false,
    "employee_lookup_synced_at" timestamp with time zone,
    "employee_lookup_remarks" text,
    "employee_name_snapshot" text,
    "birthdate_snapshot" date,
    "civil_status_snapshot" text,
    "address_snapshot" text,
    "sss_snapshot" text,
    "philhealth_snapshot" text,
    "pagibig_snapshot" text,
    "contact_number_snapshot" text,
    "requirement_overall_status" text not null default 'Incomplete'::text,
    "backout_reason_code" text,
    "backout_details" text,
    "backout_date" date,
    "moved_to_plantilla_at" timestamp with time zone,
    "moved_to_plantilla_by" uuid,
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "store_name" text,
    "date_requested" timestamp with time zone default now(),
    "ops_remarks" text,
    "hr_remarks" text,
    "hr_status" text default 'Pending'::text,
    "hr_rejection_reason" text,
    "hr_reviewed_by" text,
    "hr_reviewed_at" timestamp with time zone,
    "hrco_name" text,
    "deleted_at" timestamp with time zone,
    "assignment_type" public.hr_emploc_assignment_type not null default 'Stationary'::public.hr_emploc_assignment_type,
    "roving_assignment_id" uuid,
    "covered_stores" jsonb not null default '[]'::jsonb,
    "correction_reason" jsonb,
    "backout_at" timestamp with time zone,
    "backout_by" uuid,
    "deployer_id" uuid,
    "hr_personnel_user_id" uuid,
    "hr_reviewed_by_user_id" uuid,
    "last_correction_submitter_user_id" uuid
      );


alter table "public"."hr_emploc" enable row level security;


  create table "public"."hr_emploc_correction_attachments" (
    "id" uuid not null default gen_random_uuid(),
    "hr_emploc_id" uuid not null,
    "storage_path" text not null,
    "original_filename" text not null,
    "mime_type" text not null,
    "size_bytes" bigint not null,
    "uploaded_by" uuid,
    "uploaded_at" timestamp with time zone default now(),
    "expires_at" timestamp with time zone,
    "is_deleted" boolean default false
      );


alter table "public"."hr_emploc_correction_attachments" enable row level security;


  create table "public"."hr_emploc_deletion_requests" (
    "id" uuid not null default gen_random_uuid(),
    "hr_emploc_id" uuid,
    "applicant_name" text not null,
    "vcode" text not null,
    "account" text not null,
    "reason" text not null,
    "requested_by" text not null,
    "requested_by_role" text not null,
    "status" text default 'Pending'::text,
    "reviewed_by" text,
    "reviewed_at" timestamp with time zone,
    "reviewer_remarks" text,
    "created_at" timestamp with time zone default now(),
    "reopen_vacancy" boolean default true
      );


alter table "public"."hr_emploc_deletion_requests" enable row level security;


  create table "public"."hr_emploc_issue_types" (
    "id" uuid not null default gen_random_uuid(),
    "code" text not null,
    "label" text not null,
    "requires_comment" boolean default false,
    "allows_attachment" boolean default false,
    "is_active" boolean default true,
    "sort_order" integer default 0,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."hr_emploc_issue_types" enable row level security;


  create table "public"."hr_emploc_rejection_reasons" (
    "id" uuid not null default gen_random_uuid(),
    "reason" text not null,
    "is_active" boolean default true,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."hr_emploc_rejection_reasons" enable row level security;


  create table "public"."hr_emploc_store_links" (
    "id" uuid not null default gen_random_uuid(),
    "hr_emploc_id" uuid not null,
    "roving_assignment_id" uuid not null,
    "vacancy_id" uuid,
    "vcode" text not null,
    "store_name" text,
    "account" text not null,
    "status" text not null default 'Pending'::text,
    "confirmed_at" timestamp with time zone,
    "confirmed_by" uuid,
    "backed_out_at" timestamp with time zone,
    "backed_out_by" uuid,
    "resigned_at" timestamp with time zone,
    "resigned_by" uuid,
    "created_at" timestamp with time zone not null default now(),
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "deleted_at" timestamp with time zone
      );



  create table "public"."login_sessions" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "auth_uid" uuid not null,
    "device_info" text,
    "ip_address" inet,
    "logged_in_at" timestamp with time zone not null default now(),
    "logged_out_at" timestamp with time zone,
    "is_active" boolean not null default true
      );


alter table "public"."login_sessions" enable row level security;


  create table "public"."mika_import_logs" (
    "id" uuid not null default gen_random_uuid(),
    "uploaded_by" text not null,
    "uploaded_by_role" text not null,
    "approved_by" text,
    "file_name" text not null,
    "total_rows" integer default 0,
    "clean_rows" integer default 0,
    "updated_rows" integer default 0,
    "new_rows" integer default 0,
    "type_a_flagged" integer default 0,
    "type_b_flagged" integer default 0,
    "status" text default 'Pending'::text,
    "remarks" text,
    "submitted_at" timestamp with time zone default now(),
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone default now(),
    "file_size" text,
    "total_type_a" integer default 0,
    "total_type_b" integer default 0
      );


alter table "public"."mika_import_logs" enable row level security;


  create table "public"."mika_import_rows" (
    "id" uuid not null default gen_random_uuid(),
    "import_log_id" uuid not null,
    "employee_no" text not null,
    "account" text,
    "store_name" text,
    "last_name" text,
    "first_name" text,
    "middle_name" text,
    "position" text,
    "contact_number" text,
    "sss_no" text,
    "philhealth_no" text,
    "pagibig_no" text,
    "tin_no" text,
    "atm_no" text,
    "birthdate" text,
    "civil_status" text,
    "date_hired" text,
    "flag_type" text default 'clean'::text,
    "flag_reason" text,
    "created_at" timestamp with time zone default now(),
    "address" text
      );


alter table "public"."mika_import_rows" enable row level security;


  create table "public"."notifications" (
    "id" uuid not null default gen_random_uuid(),
    "recipient_role" text not null,
    "title" text not null,
    "message" text not null,
    "reference_type" text,
    "reference_id" text,
    "is_read" boolean default false,
    "created_at" timestamp with time zone default now(),
    "read_at" timestamp with time zone,
    "deep_link_route" text,
    "recipient_user_id" uuid,
    "notification_type" text not null default 'general'::text,
    "event_type" text not null default 'general'::text,
    "sla_level" smallint,
    "is_archived" boolean not null default false,
    "archived_at" timestamp with time zone
      );


alter table "public"."notifications" enable row level security;


  create table "public"."plantilla" (
    "id" uuid not null default gen_random_uuid(),
    "employee_name" text not null,
    "employee_no" text not null,
    "account" text not null,
    "status" text not null default 'Active'::text,
    "emploc_no" text,
    "vcode" text,
    "position" text,
    "created_at" timestamp with time zone default now(),
    "hr_emploc_id" uuid,
    "vacancy_id" uuid,
    "vacancy_code_snapshot" text,
    "employee_name_snapshot" text,
    "account_id" uuid,
    "chain_id" uuid,
    "store_id" uuid,
    "province_id" uuid,
    "area_name_snapshot" text,
    "hrco_user_id_snapshot" uuid,
    "om_user_id_snapshot" uuid,
    "atl_user_id_snapshot" uuid,
    "position_id" uuid,
    "rest_day" text,
    "resignation_date" date,
    "remarks" text,
    "moved_by_user_id" uuid,
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "store_name" text,
    "area" text,
    "rate" numeric,
    "schedule" text,
    "deployment_type" text,
    "has_penalty" boolean default false,
    "date_hired" date,
    "coordinator" text,
    "hrco_name" text,
    "last_name" text,
    "first_name" text,
    "middle_name" text,
    "date_of_separation" date,
    "separation_status" text,
    "tagged_at" date,
    "inactive_at" timestamp with time zone,
    "inactive_by" uuid,
    "for_deactivation_at" timestamp with time zone,
    "for_deactivation_by" uuid,
    "deactivated_at" timestamp with time zone,
    "deactivated_by" uuid,
    "deactivated_visible_until" timestamp with time zone,
    "last_mika_synced_at" timestamp with time zone,
    "last_mika_synced_by" uuid,
    "source_headcount_request_id" uuid,
    "is_deleted" boolean not null default false,
    "over_headcount" boolean not null default false,
    "deactivation_reason" text,
    "deletion_requested_at" timestamp with time zone,
    "deletion_requested_by" uuid,
    "deletion_reason" text,
    "deletion_remarks" text,
    "deletion_approved_at" timestamp with time zone,
    "deletion_approved_by" uuid,
    "sss_no" text,
    "philhealth_no" text,
    "pagibig_no" text,
    "atm_no" text,
    "civil_status" text,
    "date_of_birth" date,
    "transferred_from_store_id" uuid,
    "last_transfer_at" timestamp with time zone,
    "last_transfer_by" uuid,
    "roving_assignment_id" uuid,
    "is_pool_employee" boolean not null default false,
    "pool_type_id" uuid,
    "requesting_account" text,
    "requesting_account_id" uuid,
    "requesting_store_id" uuid
      );


alter table "public"."plantilla" enable row level security;


  create table "public"."plantilla_approvals" (
    "id" uuid not null default gen_random_uuid(),
    "hr_emploc_id" text not null,
    "applicant_name" text not null,
    "vcode" text not null,
    "account" text not null,
    "position" text not null,
    "emploc_no" text not null,
    "requested_by" text not null,
    "status" text not null default 'Pending'::text,
    "reviewed_by" text,
    "reviewed_at" timestamp with time zone,
    "remarks" text,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."plantilla_approvals" enable row level security;


  create table "public"."plantilla_store_links" (
    "id" uuid not null default gen_random_uuid(),
    "plantilla_id" uuid not null,
    "roving_assignment_id" uuid not null,
    "hr_emploc_store_link_id" uuid,
    "vacancy_id" uuid,
    "vcode" text not null,
    "store_name" text,
    "account" text not null,
    "status" text not null default 'Active'::text,
    "linked_at" timestamp with time zone not null default now(),
    "linked_by" uuid,
    "unlinked_at" timestamp with time zone,
    "unlinked_by" uuid,
    "created_at" timestamp with time zone not null default now(),
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "deleted_at" timestamp with time zone
      );



  create table "public"."positions" (
    "id" uuid not null default gen_random_uuid(),
    "position_name" text not null,
    "is_active" boolean default true,
    "created_at" timestamp with time zone default now(),
    "position_code" text,
    "status" text not null default 'Active'::text,
    "group_id" uuid,
    "accounts_id" uuid
      );


alter table "public"."positions" enable row level security;


  create table "public"."possible_ghost_employees" (
    "id" uuid not null default gen_random_uuid(),
    "import_log_id" uuid,
    "employee_no" text not null,
    "full_name" text not null,
    "ghost_type" text not null,
    "status" text default 'Under Investigation'::text,
    "assigned_encoder" text,
    "encoding_deadline" timestamp with time zone,
    "notified_48hr" boolean default false,
    "notified_72hr" boolean default false,
    "notified_48hr_at" timestamp with time zone,
    "notified_72hr_at" timestamp with time zone,
    "resolved_by" text,
    "resolved_by_role" text,
    "resolved_at" timestamp with time zone,
    "resolution_remarks" text,
    "account" text,
    "vcode" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "store_name" text,
    "position" text,
    "resolution_type" text,
    "resolution_notes" text,
    "auto_resolved" boolean not null default false,
    "last_revalidated_at" timestamp with time zone,
    "assigned_encoder_id" uuid,
    "resolved_by_user_id" uuid
      );


alter table "public"."possible_ghost_employees" enable row level security;


  create table "public"."qa_agent_evidence" (
    "id" uuid not null default gen_random_uuid(),
    "finding_id" uuid not null,
    "evidence_type" text not null,
    "content" jsonb not null default '{}'::jsonb,
    "created_by" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."qa_agent_evidence" enable row level security;


  create table "public"."qa_agent_findings" (
    "id" uuid not null default gen_random_uuid(),
    "run_id" uuid not null,
    "severity" text not null,
    "finding_type" text not null,
    "module_name" text,
    "reference_table" text,
    "reference_record_id" uuid,
    "title" text not null,
    "details" text,
    "recommendation" text,
    "status" text not null default 'open'::text,
    "assigned_to" uuid,
    "resolved_at" timestamp with time zone,
    "resolved_by" uuid,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."qa_agent_findings" enable row level security;


  create table "public"."qa_agent_rules" (
    "id" uuid not null default gen_random_uuid(),
    "rule_code" text not null,
    "rule_name" text not null,
    "module_name" text not null,
    "description" text,
    "severity" text not null,
    "is_active" boolean not null default true,
    "config" jsonb not null default '{}'::jsonb,
    "created_by" uuid,
    "updated_by" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."qa_agent_rules" enable row level security;


  create table "public"."qa_agent_runs" (
    "id" uuid not null default gen_random_uuid(),
    "agent_name" text not null,
    "execution_type" text not null,
    "status" text not null default 'queued'::text,
    "target_module" text,
    "target_record_id" uuid,
    "initiated_by" uuid,
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "summary" text,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."qa_agent_runs" enable row level security;


  create table "public"."qa_daily_reports" (
    "id" uuid not null default gen_random_uuid(),
    "report_date" date not null,
    "environment" text not null default 'staging'::text,
    "total_runs" integer not null default 0,
    "passed_runs" integer not null default 0,
    "failed_runs" integer not null default 0,
    "blocked_runs" integer not null default 0,
    "cancelled_runs" integer not null default 0,
    "critical_count" integer not null default 0,
    "high_count" integer not null default 0,
    "medium_count" integer not null default 0,
    "low_count" integer not null default 0,
    "top_failed_modules" jsonb not null default '[]'::jsonb,
    "average_runtime_seconds" numeric,
    "most_unstable_workflow" text,
    "flaky_tests" jsonb not null default '[]'::jsonb,
    "health_score" numeric not null default 100,
    "health_status" text not null default 'stable'::text,
    "generated_by" uuid,
    "generated_at" timestamp with time zone not null default now(),
    "archived_at" timestamp with time zone
      );


alter table "public"."qa_daily_reports" enable row level security;


  create table "public"."qa_health_metrics" (
    "id" uuid not null default gen_random_uuid(),
    "metric_date" date not null default CURRENT_DATE,
    "environment" text not null default 'staging'::text,
    "metric_name" text not null,
    "metric_value" numeric not null,
    "metric_status" text not null default 'stable'::text,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."qa_health_metrics" enable row level security;


  create table "public"."qa_notifications" (
    "id" uuid not null default gen_random_uuid(),
    "notification_type" text not null,
    "severity" text not null,
    "title" text not null,
    "message" text not null,
    "reference_type" text,
    "reference_id" uuid,
    "target_role" text,
    "is_read" boolean not null default false,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "archived_at" timestamp with time zone,
    "metadata" jsonb not null default '{}'::jsonb
      );


alter table "public"."qa_notifications" enable row level security;


  create table "public"."qa_run_queue" (
    "id" uuid not null default gen_random_uuid(),
    "schedule_id" uuid,
    "suite_name" text not null default 'core_detection'::text,
    "environment" text not null default 'staging'::text,
    "queue_status" text not null default 'queued'::text,
    "run_id" uuid,
    "lock_key" text not null,
    "locked_at" timestamp with time zone,
    "lock_expires_at" timestamp with time zone,
    "retry_count" integer not null default 0,
    "max_retries" integer not null default 1,
    "failure_type" text,
    "error_message" text,
    "queued_at" timestamp with time zone not null default now(),
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "metadata" jsonb not null default '{}'::jsonb
      );


alter table "public"."qa_run_queue" enable row level security;


  create table "public"."qa_schedules" (
    "id" uuid not null default gen_random_uuid(),
    "schedule_name" text not null,
    "suite_name" text not null default 'core_detection'::text,
    "frequency" text not null default 'daily'::text,
    "run_time" time without time zone,
    "timezone" text not null default 'Asia/Manila'::text,
    "environment" text not null default 'staging'::text,
    "assigned_agent_name" text not null default 'QA_DETECTION_ENGINE'::text,
    "is_enabled" boolean not null default true,
    "last_queued_at" timestamp with time zone,
    "last_run_at" timestamp with time zone,
    "next_run_at" timestamp with time zone,
    "created_by" uuid,
    "updated_by" uuid,
    "archived_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."qa_schedules" enable row level security;


  create table "public"."ref_locations" (
    "id" uuid not null default gen_random_uuid(),
    "province" text not null,
    "city" text not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."ref_locations" enable row level security;


  create table "public"."remote_tasks" (
    "id" bigint not null default nextval('public.remote_tasks_id_seq'::regclass),
    "command" text not null,
    "status" text not null default 'pending'::text,
    "result" text,
    "error" text,
    "created_at" timestamp with time zone not null default now(),
    "started_at" timestamp with time zone,
    "finished_at" timestamp with time zone
      );


alter table "public"."remote_tasks" enable row level security;


  create table "public"."roles" (
    "id" uuid not null default gen_random_uuid(),
    "role_name" text not null,
    "description" text,
    "created_at" timestamp with time zone not null default now(),
    "role_level" integer default 10
      );


alter table "public"."roles" enable row level security;


  create table "public"."roving_assignments" (
    "id" uuid not null default gen_random_uuid(),
    "master_applicant_id" uuid not null,
    "account" text not null,
    "account_id" uuid,
    "group_id" uuid,
    "label" text,
    "notes" text,
    "primary_vcode" text,
    "created_at" timestamp with time zone not null default now(),
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "archived_at" timestamp with time zone,
    "archived_by" uuid
      );


alter table "public"."roving_assignments" enable row level security;


  create table "public"."security_events" (
    "id" uuid not null default gen_random_uuid(),
    "event_type" text not null,
    "severity" text not null,
    "actor_id" uuid,
    "target_id" uuid,
    "action" text not null,
    "details" jsonb not null default '{}'::jsonb,
    "happened_at" timestamp with time zone not null default now()
      );


alter table "public"."security_events" enable row level security;


  create table "public"."sla_breach_logs" (
    "id" uuid not null default gen_random_uuid(),
    "plantilla_id" uuid,
    "employee_no" text,
    "vcode" text,
    "account" text,
    "breach_type" text not null default 'resignation_not_tagged'::text,
    "resignation_date" date not null,
    "tagged_date" date,
    "days_elapsed" integer,
    "notified_om" boolean default false,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."sla_breach_logs" enable row level security;


  create table "public"."staging_imports" (
    "id" uuid not null default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "created_by" uuid,
    "data" jsonb not null,
    "import_type" public.staging_import_type not null,
    "status" public.staging_import_status not null default 'pending_validation'::public.staging_import_status,
    "validated_by" uuid,
    "validated_at" timestamp with time zone,
    "approved_by" uuid,
    "approved_at" timestamp with time zone,
    "remarks" text,
    "source_file" text,
    "row_count" integer
      );


alter table "public"."staging_imports" enable row level security;


  create table "public"."store_import_batches" (
    "id" uuid not null default gen_random_uuid(),
    "file_name" text not null,
    "uploaded_by" uuid not null,
    "uploaded_role" text,
    "selected_group_id" uuid not null,
    "selected_account_id" uuid not null,
    "status" text not null default 'draft_uploaded'::text,
    "total_rows" integer not null default 0,
    "valid_rows" integer not null default 0,
    "invalid_rows" integer not null default 0,
    "error_summary" jsonb not null default '{}'::jsonb,
    "approved_by" uuid,
    "approved_at" timestamp with time zone,
    "rejected_by" uuid,
    "rejected_at" timestamp with time zone,
    "rejection_reason" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."store_import_batches" enable row level security;


  create table "public"."store_import_rows" (
    "id" uuid not null default gen_random_uuid(),
    "batch_id" uuid not null,
    "row_number" integer not null,
    "raw_data" jsonb not null,
    "vcode" text,
    "store_name" text,
    "area_province" text,
    "area_city" text,
    "type" text,
    "with_penalty" boolean,
    "validation_status" text not null,
    "validation_errors" jsonb not null default '[]'::jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."store_import_rows" enable row level security;


  create table "public"."stores" (
    "id" uuid not null default gen_random_uuid(),
    "account_id" uuid,
    "store_name" text not null,
    "store_branch" text,
    "area_city" text,
    "province" text,
    "is_active" boolean default true,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "group_id" uuid,
    "hrco_user_id" uuid,
    "om_user_id" uuid,
    "vcode" text,
    "area_province" text,
    "employment_type" text,
    "with_penalty" boolean not null default false,
    "status" text not null default 'active'::text,
    "created_by" uuid,
    "updated_by" uuid,
    "approved_by" uuid,
    "approved_at" timestamp with time zone,
    "source_import_id" uuid
      );


alter table "public"."stores" enable row level security;


  create table "public"."temp_approval_access" (
    "id" uuid not null default gen_random_uuid(),
    "granted_by" uuid not null,
    "granted_to" uuid not null,
    "module" text not null default 'vacancy_approval'::text,
    "valid_from" timestamp with time zone not null default now(),
    "valid_until" timestamp with time zone not null,
    "reason" text,
    "revoked_at" timestamp with time zone,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."temp_approval_access" enable row level security;


  create table "public"."temp_permission_overrides" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "granted_by" text not null,
    "additional_groups" text[] not null default '{}'::text[],
    "reason" text,
    "expires_at" timestamp with time zone not null,
    "is_active" boolean default true,
    "notify_user" boolean default true,
    "revoked_at" timestamp with time zone,
    "revoked_by" text,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."temp_permission_overrides" enable row level security;


  create table "public"."user_account_transfers" (
    "id" uuid not null default gen_random_uuid(),
    "user_profile_id" uuid not null,
    "from_account" text not null,
    "to_account" text not null,
    "role_at_transfer" text not null,
    "transferred_by" uuid not null,
    "effective_date" date not null default CURRENT_DATE,
    "notes" text,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."user_account_transfers" enable row level security;


  create table "public"."user_scopes" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "group_id" uuid,
    "account_id" uuid,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."user_scopes" enable row level security;


  create table "public"."users_profile" (
    "id" uuid not null default gen_random_uuid(),
    "auth_user_id" uuid,
    "full_name" text not null,
    "email" text,
    "role_id" uuid not null,
    "is_active" boolean default true,
    "created_at" timestamp with time zone default now(),
    "group_id" uuid,
    "account_id" uuid,
    "role" text,
    "scope_type" text,
    "updated_at" timestamp with time zone default now()
      );


alter table "public"."users_profile" enable row level security;


  create table "public"."vacancies" (
    "id" uuid not null default gen_random_uuid(),
    "vcode" text not null,
    "account" text not null,
    "position" text not null,
    "status" text not null default 'Open'::text,
    "backout_reason" text,
    "created_at" timestamp with time zone default now(),
    "vacancy_code" text,
    "vacancy_type" text,
    "account_id" uuid,
    "chain_id" uuid,
    "store_id" uuid,
    "province_id" uuid,
    "area_name" text,
    "hrco_user_id" uuid,
    "om_user_id" uuid,
    "atl_user_id" uuid,
    "position_id" uuid,
    "vacant_date" date,
    "required_headcount" integer not null default 1,
    "has_penalty" boolean not null default false,
    "penalty_amount" numeric(12,2),
    "has_reliever" boolean not null default false,
    "reliever_name" text,
    "remarks" text,
    "requested_by_user_id" uuid,
    "requested_date" date,
    "created_by_user_id" uuid,
    "closure_request_status" text not null default 'None'::text,
    "archived_at" timestamp with time zone,
    "archived_by" text,
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "chain" text,
    "province" text,
    "store_branch" text,
    "hrco_name" text,
    "hrco_mobile" text,
    "om_name" text,
    "is_archived" boolean default false,
    "has_pending_closure" boolean default false,
    "store_name" text,
    "area_city" text,
    "penalty_aging_detail" jsonb default '[]'::jsonb,
    "assigned_encoder_id" uuid,
    "source_plantilla_id" uuid,
    "deleted_at" timestamp with time zone,
    "source" text default 'manual'::text,
    "source_vacancy_request_id" uuid,
    "urgency_level" text,
    "target_fill_date" date,
    "triggered_by_user_id" uuid,
    "triggered_by_name" text,
    "employment_type" text,
    "group_id" uuid,
    "source_headcount_request_id" uuid,
    "is_pool_vacancy" boolean default false,
    "pool_type_id" uuid,
    "home_account_id" uuid,
    "affects_required_hc" boolean default true,
    "affects_mfr" boolean default true,
    "pool_request_id" uuid
      );


alter table "public"."vacancies" enable row level security;


  create table "public"."vacancy_closure_reasons" (
    "id" uuid not null default gen_random_uuid(),
    "reason" text not null,
    "is_active" boolean default true,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."vacancy_closure_reasons" enable row level security;


  create table "public"."vacancy_closure_requests" (
    "id" uuid not null default gen_random_uuid(),
    "vacancy_vcode" text not null,
    "reason" text not null,
    "details" text,
    "requested_by" text not null,
    "status" text not null default 'Pending'::text,
    "reviewed_by" text,
    "reviewed_at" timestamp with time zone,
    "reviewer_remarks" text,
    "created_at" timestamp with time zone default now(),
    "encoder_decision" text default 'Pending'::text,
    "encoder_by" text,
    "encoder_at" timestamp with time zone,
    "requested_by_user_id" uuid,
    "reason_id" uuid,
    "withdrawn_at" timestamp with time zone,
    "withdrawn_by_user_id" uuid
      );


alter table "public"."vacancy_closure_requests" enable row level security;


  create table "public"."vacancy_coverage" (
    "id" uuid not null default gen_random_uuid(),
    "vacancy_id" uuid not null,
    "vcode" text not null,
    "applicant_id" uuid,
    "hr_emploc_id" uuid,
    "coverage_type" public.vacancy_coverage_type not null,
    "status" public.vacancy_coverage_status not null default 'Active'::public.vacancy_coverage_status,
    "covered_from" date not null default CURRENT_DATE,
    "covered_until" date,
    "account" text not null,
    "account_id" uuid,
    "group_id" uuid,
    "exempts_penalty" boolean not null default true,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "archived_at" timestamp with time zone,
    "archived_by" uuid
      );


alter table "public"."vacancy_coverage" enable row level security;


  create table "public"."vacancy_requests" (
    "id" uuid not null default gen_random_uuid(),
    "account" text not null,
    "store_name" text not null,
    "position" text not null,
    "vacancy_type" text default 'New'::text,
    "no_of_slots" integer default 1,
    "date_needed" date,
    "urgency" text default 'Normal'::text,
    "has_penalty" boolean default false,
    "notes" text,
    "requested_by" text not null,
    "requested_by_role" text not null,
    "status" text default 'Pending'::text,
    "reviewed_by" text,
    "reviewed_at" timestamp with time zone,
    "reviewer_remarks" text,
    "vcode_created" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "assigned_encoder_id" uuid,
    "requested_by_user_id" uuid,
    "employment_type" text
      );


alter table "public"."vacancy_requests" enable row level security;


  create table "public"."vcode_sequences" (
    "prefix" text not null,
    "last_seq" integer not null default 0,
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."vcode_sequences" enable row level security;


  create table "public"."vcodes" (
    "id" uuid not null default gen_random_uuid(),
    "vacancy_request_id" uuid not null,
    "account_code" text not null,
    "group_code" text not null,
    "sequence_number" integer not null,
    "vcode" text not null,
    "status" text not null default 'available'::text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."vcodes" enable row level security;


  create table "public"."workforce_assignment_requests" (
    "id" uuid not null default gen_random_uuid(),
    "employee_id" uuid not null,
    "pool_type_id" uuid,
    "requested_group_id" uuid,
    "requested_account_id" uuid,
    "requested_store_id" uuid,
    "requested_position" text,
    "priority" text not null default 'normal'::text,
    "start_date" date not null,
    "end_date" date not null,
    "reason" text,
    "status" text not null default 'Pending'::text,
    "requested_by" text,
    "requested_by_id" uuid,
    "reviewed_by" text,
    "reviewed_at" timestamp with time zone,
    "rejection_reason" text,
    "converted_assignment_id" uuid,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
      );


alter table "public"."workforce_assignment_requests" enable row level security;


  create table "public"."workforce_assignments" (
    "id" uuid not null default gen_random_uuid(),
    "employee_id" uuid not null,
    "pool_type_id" uuid,
    "assigned_group_id" uuid,
    "assigned_account_id" uuid,
    "assigned_store_id" uuid,
    "deployment_type" text,
    "priority" text not null default 'normal'::text,
    "is_primary" boolean not null default false,
    "start_date" date not null,
    "end_date" date not null,
    "status" text not null default 'Pending'::text,
    "requested_by" text,
    "approved_by" text,
    "approved_at" timestamp with time zone,
    "cancelled_by" text,
    "cancelled_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "created_by" text,
    "updated_at" timestamp with time zone,
    "updated_by" text
      );


alter table "public"."workforce_assignments" enable row level security;


  create table "public"."workforce_pool_conversion_requests" (
    "id" uuid not null default gen_random_uuid(),
    "employee_id" uuid not null,
    "pool_type_id" uuid,
    "pool_slot_id" uuid,
    "vcode" text,
    "target_account_id" uuid not null,
    "target_account" text,
    "target_store_id" uuid not null,
    "target_store" text,
    "target_position" text not null,
    "effective_date" date not null,
    "reason" text not null,
    "notes" text,
    "status" text not null default 'Pending'::text,
    "requested_by" uuid,
    "requested_by_name" text,
    "requested_by_role" text,
    "approved_by" uuid,
    "approved_by_name" text,
    "approved_at" timestamp with time zone,
    "rejected_by" uuid,
    "rejected_by_name" text,
    "rejected_at" timestamp with time zone,
    "rejection_reason" text,
    "cancelled_by" uuid,
    "cancelled_by_name" text,
    "cancelled_at" timestamp with time zone,
    "cancel_reason" text,
    "previous_account_id" uuid,
    "previous_account" text,
    "previous_store_id" uuid,
    "previous_store" text,
    "previous_position" text,
    "previous_vcode" text,
    "snapshot" jsonb not null default '{}'::jsonb,
    "active_assignments_closed" integer not null default 0,
    "pending_requests_cancelled" integer not null default 0,
    "slot_review_id" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
      );


alter table "public"."workforce_pool_conversion_requests" enable row level security;


  create table "public"."workforce_pool_request_items" (
    "id" uuid not null default gen_random_uuid(),
    "request_id" uuid not null,
    "vacancy_id" uuid,
    "vcode" text,
    "position_id" uuid,
    "status" text not null default 'open'::text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
      );


alter table "public"."workforce_pool_request_items" enable row level security;


  create table "public"."workforce_pool_requests" (
    "id" uuid not null default gen_random_uuid(),
    "pool_type_id" uuid not null,
    "requesting_account_id" uuid,
    "requesting_account" text,
    "requesting_store_id" uuid,
    "requesting_store" text,
    "headcount_needed" integer not null default 1,
    "priority" text not null default 'normal'::text,
    "reason" text,
    "status" text not null default 'pending'::text,
    "approved_by" text,
    "approved_at" timestamp with time zone,
    "rejected_by" text,
    "rejected_at" timestamp with time zone,
    "rejection_reason" text,
    "created_at" timestamp with time zone not null default now(),
    "created_by" text,
    "updated_at" timestamp with time zone,
    "updated_by" text,
    "deleted_at" timestamp with time zone
      );


alter table "public"."workforce_pool_requests" enable row level security;


  create table "public"."workforce_pool_slots" (
    "id" uuid not null default gen_random_uuid(),
    "vcode" text not null,
    "pool_type_id" uuid not null,
    "vacancy_id" uuid,
    "status" text not null default 'open'::text,
    "account" text,
    "account_id" uuid,
    "group_id" uuid,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "created_by" text,
    "updated_at" timestamp with time zone,
    "updated_by" text,
    "deleted_at" timestamp with time zone
      );


alter table "public"."workforce_pool_slots" enable row level security;


  create table "public"."workforce_pool_types" (
    "id" uuid not null default gen_random_uuid(),
    "code" text not null,
    "name" text not null,
    "vcode_prefix" text not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "created_by" text,
    "updated_at" timestamp with time zone,
    "updated_by" text,
    "sort_order" integer not null default 0
      );


alter table "public"."workforce_pool_types" enable row level security;


  create table "public"."workforce_pool_vcode_sequences" (
    "prefix" text not null,
    "last_val" bigint not null default 0
      );


alter table "public"."workforce_pool_vcode_sequences" enable row level security;


  create table "public"."workforce_slot_reviews" (
    "id" uuid not null default gen_random_uuid(),
    "vcode" text not null,
    "pool_type_id" uuid not null,
    "vacancy_id" uuid,
    "previous_employee_id" uuid,
    "trigger_event" text not null,
    "action" text,
    "review_notes" text,
    "decided_by" text,
    "decided_at" timestamp with time zone,
    "status" text not null default 'pending'::text,
    "created_at" timestamp with time zone not null default now(),
    "created_by" text,
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone
      );


alter table "public"."workforce_slot_reviews" enable row level security;

alter sequence "public"."remote_tasks_id_seq" owned by "public"."remote_tasks"."id";

CREATE UNIQUE INDEX account_positions_account_id_position_id_key ON public.account_positions USING btree (account_id, position_id);

CREATE UNIQUE INDEX account_positions_pkey ON public.account_positions USING btree (id);

CREATE UNIQUE INDEX account_request_account_scope_account_request_id_account_id_key ON public.account_request_account_scopes USING btree (account_request_id, account_id);

CREATE UNIQUE INDEX account_request_account_scopes_pkey ON public.account_request_account_scopes USING btree (id);

CREATE UNIQUE INDEX account_request_group_scopes_account_request_id_group_id_key ON public.account_request_group_scopes USING btree (account_request_id, group_id);

CREATE UNIQUE INDEX account_request_group_scopes_pkey ON public.account_request_group_scopes USING btree (id);

CREATE UNIQUE INDEX account_requests_auth_user_id_key ON public.account_requests USING btree (auth_user_id);

CREATE UNIQUE INDEX account_requests_pkey ON public.account_requests USING btree (id);

CREATE UNIQUE INDEX accounts_account_name_unique ON public.accounts USING btree (account_name);

CREATE UNIQUE INDEX accounts_group_id_account_name_key ON public.accounts USING btree (group_id, account_name);

CREATE UNIQUE INDEX accounts_pkey ON public.accounts USING btree (id);

CREATE UNIQUE INDEX acting_sessions_pkey ON public.acting_sessions USING btree (id);

CREATE UNIQUE INDEX activity_log_pkey ON public.activity_log USING btree (id);

CREATE UNIQUE INDEX applicants_pkey ON public.applicants USING btree (id);

CREATE UNIQUE INDEX audit_logs_pkey ON public.audit_logs USING btree (id);

CREATE UNIQUE INDEX backout_reasons_pkey ON public.backout_reasons USING btree (id);

CREATE UNIQUE INDEX backout_reasons_reason_key ON public.backout_reasons USING btree (reason);

CREATE UNIQUE INDEX bulk_emploc_items_pkey ON public.bulk_emploc_items USING btree (id);

CREATE UNIQUE INDEX bulk_emploc_uploads_pkey ON public.bulk_emploc_uploads USING btree (id);

CREATE UNIQUE INDEX deactivation_audit_log_pkey ON public.deactivation_audit_log USING btree (id);

CREATE UNIQUE INDEX deactivation_batches_pkey ON public.deactivation_batches USING btree (id);

CREATE UNIQUE INDEX deactivation_items_pkey ON public.deactivation_items USING btree (id);

CREATE INDEX deactivation_requests_batch_id_idx ON public.deactivation_requests USING btree (batch_id);

CREATE UNIQUE INDEX deactivation_requests_pkey ON public.deactivation_requests USING btree (id);

CREATE UNIQUE INDEX deployer_name_key ON public.deployer USING btree (name);

CREATE UNIQUE INDEX deployer_pkey ON public.deployer USING btree (id);

CREATE UNIQUE INDEX employee_activity_log_pkey ON public.employee_activity_log USING btree (id);

CREATE UNIQUE INDEX employee_deployments_pkey ON public.employee_deployments USING btree (id);

CREATE UNIQUE INDEX employee_transfers_pkey ON public.employee_transfers USING btree (id);

CREATE UNIQUE INDEX employees_employee_no_key ON public.employees USING btree (employee_no);

CREATE UNIQUE INDEX employees_pkey ON public.employees USING btree (id);

CREATE UNIQUE INDEX feedback_reports_pkey ON public.feedback_reports USING btree (id);

CREATE UNIQUE INDEX groups_group_code_key ON public.groups USING btree (group_code);

CREATE UNIQUE INDEX groups_group_name_key ON public.groups USING btree (group_name);

CREATE UNIQUE INDEX groups_pkey ON public.groups USING btree (id);

CREATE UNIQUE INDEX headcount_requests_pkey ON public.headcount_requests USING btree (id);

CREATE UNIQUE INDEX hr_emploc_applicant_vcode_unique ON public.hr_emploc USING btree (applicant_name, vcode);

CREATE UNIQUE INDEX hr_emploc_correction_attachments_pkey ON public.hr_emploc_correction_attachments USING btree (id);

CREATE UNIQUE INDEX hr_emploc_deletion_requests_pkey ON public.hr_emploc_deletion_requests USING btree (id);

CREATE UNIQUE INDEX hr_emploc_issue_types_code_key ON public.hr_emploc_issue_types USING btree (code);

CREATE UNIQUE INDEX hr_emploc_issue_types_pkey ON public.hr_emploc_issue_types USING btree (id);

CREATE UNIQUE INDEX hr_emploc_pkey ON public.hr_emploc USING btree (id);

CREATE UNIQUE INDEX hr_emploc_rejection_reasons_pkey ON public.hr_emploc_rejection_reasons USING btree (id);

CREATE UNIQUE INDEX hr_emploc_rejection_reasons_reason_key ON public.hr_emploc_rejection_reasons USING btree (reason);

CREATE UNIQUE INDEX hr_emploc_store_links_pkey ON public.hr_emploc_store_links USING btree (id);

CREATE INDEX idx_account_positions_account_id ON public.account_positions USING btree (account_id);

CREATE UNIQUE INDEX idx_account_positions_account_position_unique ON public.account_positions USING btree (account_id, position_id);

CREATE INDEX idx_account_positions_position_id ON public.account_positions USING btree (position_id);

CREATE INDEX idx_account_request_account_scopes_request ON public.account_request_account_scopes USING btree (account_request_id);

CREATE INDEX idx_account_request_group_scopes_request ON public.account_request_group_scopes USING btree (account_request_id);

CREATE INDEX idx_account_requests_auth_user ON public.account_requests USING btree (auth_user_id);

CREATE INDEX idx_account_requests_status ON public.account_requests USING btree (status);

CREATE INDEX idx_accounts_atl_user_id ON public.accounts USING btree (atl_user_id);

CREATE INDEX idx_accounts_group_id ON public.accounts USING btree (group_id);

CREATE INDEX idx_accounts_om_user_id ON public.accounts USING btree (om_user_id);

CREATE INDEX idx_acting_sessions_expires ON public.acting_sessions USING btree (expires_at);

CREATE INDEX idx_acting_sessions_user_active ON public.acting_sessions USING btree (user_id, is_active);

CREATE INDEX idx_activity_log_action ON public.activity_log USING btree (action);

CREATE INDEX idx_activity_log_actor ON public.activity_log USING btree (actor_id);

CREATE INDEX idx_activity_log_created_at ON public.activity_log USING btree (created_at DESC);

CREATE INDEX idx_activity_log_emploc ON public.employee_activity_log USING btree (emploc_no);

CREATE INDEX idx_activity_log_target ON public.activity_log USING btree (target_table, target_id);

CREATE INDEX idx_activity_log_vcode ON public.employee_activity_log USING btree (vcode);

CREATE UNIQUE INDEX idx_applicants_no_active_duplicate ON public.applicants USING btree (vacancy_vcode, lower(TRIM(BOTH FROM full_name))) WHERE (COALESCE(is_archived, false) = false);

CREATE INDEX idx_applicants_roving_assignment_id ON public.applicants USING btree (roving_assignment_id) WHERE (roving_assignment_id IS NOT NULL);

CREATE INDEX idx_applicants_status ON public.applicants USING btree (status);

CREATE INDEX idx_applicants_vacancy_vcode ON public.applicants USING btree (vacancy_vcode);

CREATE INDEX idx_audit_logs_action ON public.audit_logs USING btree (action);

CREATE INDEX idx_audit_logs_actor_id ON public.audit_logs USING btree (actor_id);

CREATE INDEX idx_audit_logs_module ON public.audit_logs USING btree (module);

CREATE INDEX idx_audit_logs_record_id ON public.audit_logs USING btree (record_id);

CREATE INDEX idx_audit_logs_timestamp ON public.audit_logs USING btree ("timestamp" DESC);

CREATE INDEX idx_audit_logs_timestamp_desc ON public.audit_logs USING btree ("timestamp" DESC);

CREATE INDEX idx_bulk_emploc_upload ON public.bulk_emploc_items USING btree (upload_id);

CREATE INDEX idx_correction_attach_emploc ON public.hr_emploc_correction_attachments USING btree (hr_emploc_id) WHERE (is_deleted = false);

CREATE INDEX idx_deac_items_emploc ON public.deactivation_items USING btree (emploc_no);

CREATE INDEX idx_deac_items_request ON public.deactivation_items USING btree (request_id);

CREATE INDEX idx_deac_request_status ON public.deactivation_requests USING btree (status);

CREATE INDEX idx_deact_item_emploc_no ON public.deactivation_items USING btree (emploc_no);

CREATE INDEX idx_deact_item_request ON public.deactivation_items USING btree (request_id);

CREATE INDEX idx_deact_item_status ON public.deactivation_items USING btree (status);

CREATE INDEX idx_deact_req_batch ON public.deactivation_requests USING btree (batch_id);

CREATE INDEX idx_deact_req_requested_by ON public.deactivation_requests USING btree (requested_by);

CREATE INDEX idx_deact_req_status ON public.deactivation_requests USING btree (status);

CREATE INDEX idx_deactivation_items_plantilla_id ON public.deactivation_items USING btree (plantilla_id);

CREATE INDEX idx_deployer_active_name ON public.deployer USING btree (is_active, name);

CREATE INDEX idx_deployer_name_trgm ON public.deployer USING gin (name extensions.gin_trgm_ops);

CREATE INDEX idx_deployments_employee_id ON public.employee_deployments USING btree (employee_id);

CREATE INDEX idx_deployments_status ON public.employee_deployments USING btree (status);

CREATE INDEX idx_deployments_vcode ON public.employee_deployments USING btree (vcode);

CREATE INDEX idx_employees_employee_no ON public.employees USING btree (employee_no);

CREATE INDEX idx_employees_full_name ON public.employees USING btree (full_name);

CREATE INDEX idx_employees_status ON public.employees USING btree (status);

CREATE INDEX idx_ghost_deadline ON public.possible_ghost_employees USING btree (encoding_deadline) WHERE (status = 'For Encoding'::text);

CREATE INDEX idx_ghost_open_for_reconciliation ON public.possible_ghost_employees USING btree (employee_no, ghost_type, account) WHERE (status <> ALL (ARRAY['Resolved'::text, 'Cleared'::text, 'Confirmed Ghost'::text, 'For Termination'::text]));

CREATE INDEX idx_ghost_status ON public.possible_ghost_employees USING btree (status);

CREATE INDEX idx_ghost_type ON public.possible_ghost_employees USING btree (ghost_type);

CREATE INDEX idx_hcreq_account ON public.headcount_requests USING btree (account_id);

CREATE INDEX idx_hcreq_group ON public.headcount_requests USING btree (group_id);

CREATE INDEX idx_hcreq_requester ON public.headcount_requests USING btree (requested_by_user_id);

CREATE INDEX idx_hcreq_status ON public.headcount_requests USING btree (status);

CREATE INDEX idx_hcreq_store ON public.headcount_requests USING btree (store_id);

CREATE INDEX idx_hr_emploc_account ON public.hr_emploc USING btree (account);

CREATE INDEX idx_hr_emploc_account_hr_status ON public.hr_emploc USING btree (account, hr_status);

CREATE INDEX idx_hr_emploc_account_id ON public.hr_emploc USING btree (account_id);

CREATE INDEX idx_hr_emploc_account_position ON public.hr_emploc USING btree (account, "position");

CREATE INDEX idx_hr_emploc_account_status ON public.hr_emploc USING btree (account, status);

CREATE INDEX idx_hr_emploc_deleted_at ON public.hr_emploc USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);

CREATE INDEX idx_hr_emploc_deletion_status ON public.hr_emploc_deletion_requests USING btree (status);

CREATE INDEX idx_hr_emploc_deployer_id ON public.hr_emploc USING btree (deployer_id);

CREATE INDEX idx_hr_emploc_employee_no ON public.hr_emploc USING btree (employee_no);

CREATE INDEX idx_hr_emploc_hired_date ON public.hr_emploc USING btree (hired_date DESC);

CREATE INDEX idx_hr_emploc_issue_types_active ON public.hr_emploc_issue_types USING btree (sort_order) WHERE (is_active = true);

CREATE INDEX idx_hr_emploc_status ON public.hr_emploc USING btree (status);

CREATE INDEX idx_hr_emploc_store_links_hr_emploc_id ON public.hr_emploc_store_links USING btree (hr_emploc_id);

CREATE INDEX idx_hr_emploc_store_links_roving_assignment_id ON public.hr_emploc_store_links USING btree (roving_assignment_id);

CREATE INDEX idx_hr_emploc_store_links_vcode ON public.hr_emploc_store_links USING btree (vcode);

CREATE INDEX idx_hr_emploc_vacancy_id ON public.hr_emploc USING btree (vacancy_id);

CREATE INDEX idx_hr_emploc_vcode ON public.hr_emploc USING btree (vcode);

CREATE INDEX idx_login_sessions_active ON public.login_sessions USING btree (is_active, logged_in_at DESC);

CREATE INDEX idx_login_sessions_user ON public.login_sessions USING btree (user_id);

CREATE INDEX idx_notifications_is_read ON public.notifications USING btree (is_read);

CREATE INDEX idx_notifications_read ON public._deprecated_in_app_notifications USING btree (is_read);

CREATE INDEX idx_notifications_role ON public._deprecated_in_app_notifications USING btree (recipient_role);

CREATE INDEX idx_plantilla_account ON public.plantilla USING btree (account);

CREATE INDEX idx_plantilla_account_id ON public.plantilla USING btree (account_id);

CREATE INDEX idx_plantilla_approvals_status ON public.plantilla_approvals USING btree (status);

CREATE INDEX idx_plantilla_chain_id ON public.plantilla USING btree (chain_id);

CREATE INDEX idx_plantilla_employee_no ON public.plantilla USING btree (employee_no);

CREATE INDEX idx_plantilla_hr_emploc_id ON public.plantilla USING btree (hr_emploc_id);

CREATE INDEX idx_plantilla_position_id ON public.plantilla USING btree (position_id);

CREATE INDEX idx_plantilla_status ON public.plantilla USING btree (status);

CREATE INDEX idx_plantilla_store_id ON public.plantilla USING btree (store_id);

CREATE INDEX idx_plantilla_store_links_plantilla_id ON public.plantilla_store_links USING btree (plantilla_id);

CREATE INDEX idx_plantilla_store_links_roving_assignment_id ON public.plantilla_store_links USING btree (roving_assignment_id);

CREATE INDEX idx_plantilla_vacancy_id ON public.plantilla USING btree (vacancy_id);

CREATE INDEX idx_possible_ghost_employees_assigned_encoder_id ON public.possible_ghost_employees USING btree (assigned_encoder_id);

CREATE INDEX idx_possible_ghost_employees_resolved_by_user_id ON public.possible_ghost_employees USING btree (resolved_by_user_id);

CREATE INDEX idx_qa_daily_reports_date ON public.qa_daily_reports USING btree (report_date DESC, environment);

CREATE INDEX idx_qa_findings_run ON public.qa_agent_findings USING btree (run_id);

CREATE INDEX idx_qa_findings_severity ON public.qa_agent_findings USING btree (severity);

CREATE INDEX idx_qa_findings_status ON public.qa_agent_findings USING btree (status);

CREATE INDEX idx_qa_notifications_unread ON public.qa_notifications USING btree (is_read, severity, created_at DESC) WHERE (archived_at IS NULL);

CREATE INDEX idx_qa_run_queue_schedule ON public.qa_run_queue USING btree (schedule_id);

CREATE INDEX idx_qa_run_queue_status ON public.qa_run_queue USING btree (queue_status, queued_at);

CREATE INDEX idx_qa_runs_agent ON public.qa_agent_runs USING btree (agent_name);

CREATE INDEX idx_qa_runs_status ON public.qa_agent_runs USING btree (status);

CREATE INDEX idx_qa_schedules_enabled_next ON public.qa_schedules USING btree (is_enabled, next_run_at) WHERE (archived_at IS NULL);

CREATE INDEX idx_remote_tasks_status_created ON public.remote_tasks USING btree (status, created_at);

CREATE INDEX idx_roving_assignments_account ON public.roving_assignments USING btree (account) WHERE (archived_at IS NULL);

CREATE INDEX idx_roving_assignments_account_id ON public.roving_assignments USING btree (account_id) WHERE ((archived_at IS NULL) AND (account_id IS NOT NULL));

CREATE INDEX idx_roving_assignments_master_applicant ON public.roving_assignments USING btree (master_applicant_id) WHERE (archived_at IS NULL);

CREATE INDEX idx_staging_imports_created_at ON public.staging_imports USING btree (created_at DESC);

CREATE INDEX idx_staging_imports_status ON public.staging_imports USING btree (status);

CREATE INDEX idx_staging_imports_type ON public.staging_imports USING btree (import_type);

CREATE INDEX idx_temp_overrides_active ON public.temp_permission_overrides USING btree (is_active, expires_at);

CREATE INDEX idx_temp_overrides_user_id ON public.temp_permission_overrides USING btree (user_id);

CREATE INDEX idx_transfers_emploc ON public.employee_transfers USING btree (emploc_no);

CREATE INDEX idx_transfers_status ON public.employee_transfers USING btree (status);

CREATE INDEX idx_user_scopes_account_id ON public.user_scopes USING btree (account_id);

CREATE INDEX idx_user_scopes_group_id ON public.user_scopes USING btree (group_id);

CREATE INDEX idx_user_scopes_user_id ON public.user_scopes USING btree (user_id);

CREATE INDEX idx_users_profile_auth_user_id ON public.users_profile USING btree (auth_user_id);

CREATE INDEX idx_users_profile_role_id ON public.users_profile USING btree (role_id);

CREATE INDEX idx_vacancies_account ON public.vacancies USING btree (account);

CREATE INDEX idx_vacancies_account_id ON public.vacancies USING btree (account_id);

CREATE INDEX idx_vacancies_account_status ON public.vacancies USING btree (account, status) WHERE (is_archived = false);

CREATE INDEX idx_vacancies_account_store_status ON public.vacancies USING btree (account, store_branch, status) WHERE (is_archived = false);

CREATE INDEX idx_vacancies_atl_user_id ON public.vacancies USING btree (atl_user_id);

CREATE INDEX idx_vacancies_chain_id ON public.vacancies USING btree (chain_id);

CREATE INDEX idx_vacancies_deleted_at ON public.vacancies USING btree (deleted_at) WHERE (deleted_at IS NOT NULL);

CREATE INDEX idx_vacancies_hrco_user_id ON public.vacancies USING btree (hrco_user_id);

CREATE INDEX idx_vacancies_om_user_id ON public.vacancies USING btree (om_user_id);

CREATE INDEX idx_vacancies_position_id ON public.vacancies USING btree (position_id);

CREATE INDEX idx_vacancies_requested_by_user_id ON public.vacancies USING btree (requested_by_user_id);

CREATE INDEX idx_vacancies_status ON public.vacancies USING btree (status);

CREATE INDEX idx_vacancies_store_id ON public.vacancies USING btree (store_id);

CREATE INDEX idx_vacancies_vacant_date ON public.vacancies USING btree (vacant_date);

CREATE INDEX idx_vacancy_closure_requests_status ON public.vacancy_closure_requests USING btree (status);

CREATE INDEX idx_vacancy_closure_requests_vcode ON public.vacancy_closure_requests USING btree (vacancy_vcode);

CREATE INDEX idx_vacancy_coverage_account ON public.vacancy_coverage USING btree (account) WHERE (archived_at IS NULL);

CREATE INDEX idx_vacancy_coverage_account_id ON public.vacancy_coverage USING btree (account_id) WHERE ((archived_at IS NULL) AND (account_id IS NOT NULL));

CREATE INDEX idx_vacancy_coverage_applicant ON public.vacancy_coverage USING btree (applicant_id) WHERE (archived_at IS NULL);

CREATE INDEX idx_vacancy_coverage_status ON public.vacancy_coverage USING btree (status) WHERE (archived_at IS NULL);

CREATE INDEX idx_vacancy_coverage_vcode ON public.vacancy_coverage USING btree (vcode) WHERE (archived_at IS NULL);

CREATE INDEX idx_vacancy_requests_account ON public.vacancy_requests USING btree (account);

CREATE INDEX idx_vacancy_requests_status ON public.vacancy_requests USING btree (status);

CREATE INDEX idx_vcodes_request ON public.vcodes USING btree (vacancy_request_id);

CREATE INDEX idx_vcodes_scope ON public.vcodes USING btree (account_code, group_code);

CREATE UNIQUE INDEX idx_vcr_one_pending_per_vcode ON public.vacancy_closure_requests USING btree (vacancy_vcode) WHERE (status = 'Pending'::text);

CREATE INDEX idx_wa_assigned_account ON public.workforce_assignments USING btree (assigned_account_id);

CREATE INDEX idx_wa_assigned_store ON public.workforce_assignments USING btree (assigned_store_id);

CREATE INDEX idx_wa_dates ON public.workforce_assignments USING btree (start_date, end_date);

CREATE INDEX idx_wa_employee_id ON public.workforce_assignments USING btree (employee_id);

CREATE INDEX idx_wa_status ON public.workforce_assignments USING btree (status);

CREATE INDEX idx_wf_pool_conversion_employee ON public.workforce_pool_conversion_requests USING btree (employee_id);

CREATE INDEX idx_wf_pool_conversion_status ON public.workforce_pool_conversion_requests USING btree (status, created_at DESC);

CREATE UNIQUE INDEX in_app_notifications_pkey ON public._deprecated_in_app_notifications USING btree (id);

CREATE UNIQUE INDEX login_sessions_pkey ON public.login_sessions USING btree (id);

CREATE UNIQUE INDEX mika_import_logs_pkey ON public.mika_import_logs USING btree (id);

CREATE INDEX mika_import_rows_import_log_id_idx ON public.mika_import_rows USING btree (import_log_id);

CREATE UNIQUE INDEX mika_import_rows_pkey ON public.mika_import_rows USING btree (id);

CREATE UNIQUE INDEX notifications_pkey ON public.notifications USING btree (id);

CREATE UNIQUE INDEX plantilla_approvals_pkey ON public.plantilla_approvals USING btree (id);

CREATE UNIQUE INDEX plantilla_pkey ON public.plantilla USING btree (id);

CREATE UNIQUE INDEX plantilla_store_links_pkey ON public.plantilla_store_links USING btree (id);

CREATE UNIQUE INDEX positions_pkey ON public.positions USING btree (id);

CREATE UNIQUE INDEX positions_position_name_key ON public.positions USING btree (position_name);

CREATE UNIQUE INDEX possible_ghost_employees_pkey ON public.possible_ghost_employees USING btree (id);

CREATE UNIQUE INDEX qa_agent_evidence_pkey ON public.qa_agent_evidence USING btree (id);

CREATE UNIQUE INDEX qa_agent_findings_pkey ON public.qa_agent_findings USING btree (id);

CREATE UNIQUE INDEX qa_agent_rules_pkey ON public.qa_agent_rules USING btree (id);

CREATE UNIQUE INDEX qa_agent_rules_rule_code_key ON public.qa_agent_rules USING btree (rule_code);

CREATE UNIQUE INDEX qa_agent_runs_pkey ON public.qa_agent_runs USING btree (id);

CREATE UNIQUE INDEX qa_daily_reports_pkey ON public.qa_daily_reports USING btree (id);

CREATE UNIQUE INDEX qa_daily_reports_report_date_environment_key ON public.qa_daily_reports USING btree (report_date, environment);

CREATE UNIQUE INDEX qa_health_metrics_metric_date_environment_metric_name_key ON public.qa_health_metrics USING btree (metric_date, environment, metric_name);

CREATE UNIQUE INDEX qa_health_metrics_pkey ON public.qa_health_metrics USING btree (id);

CREATE UNIQUE INDEX qa_notifications_pkey ON public.qa_notifications USING btree (id);

CREATE UNIQUE INDEX qa_run_queue_pkey ON public.qa_run_queue USING btree (id);

CREATE UNIQUE INDEX qa_schedules_pkey ON public.qa_schedules USING btree (id);

CREATE UNIQUE INDEX qa_schedules_schedule_name_key ON public.qa_schedules USING btree (schedule_name);

CREATE UNIQUE INDEX ref_locations_pkey ON public.ref_locations USING btree (id);

CREATE UNIQUE INDEX remote_tasks_pkey ON public.remote_tasks USING btree (id);

CREATE UNIQUE INDEX roles_pkey ON public.roles USING btree (id);

CREATE UNIQUE INDEX roving_assignments_pkey ON public.roving_assignments USING btree (id);

CREATE UNIQUE INDEX security_events_pkey ON public.security_events USING btree (id);

CREATE INDEX sib_grp_acc_idx ON public.store_import_batches USING btree (selected_group_id, selected_account_id);

CREATE INDEX sib_status_idx ON public.store_import_batches USING btree (status);

CREATE INDEX sib_uploaded_by_idx ON public.store_import_batches USING btree (uploaded_by);

CREATE INDEX sir_batch_idx ON public.store_import_rows USING btree (batch_id);

CREATE INDEX sir_status_idx ON public.store_import_rows USING btree (validation_status);

CREATE UNIQUE INDEX sla_breach_logs_pkey ON public.sla_breach_logs USING btree (id);

CREATE UNIQUE INDEX staging_imports_pkey ON public.staging_imports USING btree (id);

CREATE UNIQUE INDEX store_import_batches_pkey ON public.store_import_batches USING btree (id);

CREATE UNIQUE INDEX store_import_rows_pkey ON public.store_import_rows USING btree (id);

CREATE UNIQUE INDEX stores_pkey ON public.stores USING btree (id);

CREATE UNIQUE INDEX stores_vcode_active_uidx ON public.stores USING btree (vcode) WHERE ((status = 'active'::text) AND (vcode IS NOT NULL));

CREATE UNIQUE INDEX temp_approval_access_pkey ON public.temp_approval_access USING btree (id);

CREATE UNIQUE INDEX temp_permission_overrides_pkey ON public.temp_permission_overrides USING btree (id);

CREATE UNIQUE INDEX uniq_vacancies_open_per_slot ON public.vacancies USING btree (store_id, position_id) WHERE ((status = 'Open'::text) AND (COALESCE(is_archived, false) = false) AND (deleted_at IS NULL) AND (COALESCE(source, ''::text) IS DISTINCT FROM 'hc_request'::text));

CREATE UNIQUE INDEX uq_account_requests_email_pending ON public.account_requests USING btree (lower(email)) WHERE (status = 'pending'::public.account_request_status);

CREATE UNIQUE INDEX uq_hr_emploc_employee_no_active ON public.hr_emploc USING btree (employee_no) WHERE ((deleted_at IS NULL) AND (employee_no IS NOT NULL) AND (status <> ALL (ARRAY['Backout'::text, 'Moved to Plantilla'::text])));

CREATE UNIQUE INDEX uq_hr_emploc_roving_assignment ON public.hr_emploc USING btree (roving_assignment_id) WHERE ((assignment_type = 'Roving'::public.hr_emploc_assignment_type) AND (deleted_at IS NULL) AND (roving_assignment_id IS NOT NULL));

CREATE UNIQUE INDEX uq_hr_emploc_stationary_applicant_vacancy ON public.hr_emploc USING btree (applicant_id, vacancy_id) WHERE ((assignment_type = 'Stationary'::public.hr_emploc_assignment_type) AND (deleted_at IS NULL) AND (applicant_id IS NOT NULL) AND (vacancy_id IS NOT NULL));

CREATE UNIQUE INDEX uq_hr_emploc_store_links_emploc_vcode_active ON public.hr_emploc_store_links USING btree (hr_emploc_id, vcode) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX uq_plantilla_employee_no_active ON public.plantilla USING btree (employee_no) WHERE ((is_deleted = false) AND (status = ANY (ARRAY['Active'::text, 'For Deactivation'::text, 'On Leave'::text])));

CREATE UNIQUE INDEX uq_plantilla_hr_emploc_active ON public.plantilla USING btree (hr_emploc_id) WHERE ((hr_emploc_id IS NOT NULL) AND (COALESCE(is_deleted, false) = false));

CREATE UNIQUE INDEX uq_plantilla_store_links_plantilla_vcode_active ON public.plantilla_store_links USING btree (plantilla_id, vcode) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX uq_sla_breach_plantilla ON public.sla_breach_logs USING btree (plantilla_id);

CREATE UNIQUE INDEX uq_vacancy_coverage_active_per_vacancy ON public.vacancy_coverage USING btree (vacancy_id) WHERE ((status = 'Active'::public.vacancy_coverage_status) AND (archived_at IS NULL));

CREATE UNIQUE INDEX uq_vacancy_source_plantilla ON public.vacancies USING btree (source_plantilla_id);

CREATE UNIQUE INDEX uq_vcode_scope ON public.vcodes USING btree (account_code, group_code, sequence_number);

CREATE UNIQUE INDEX uq_vcode_unique ON public.vcodes USING btree (vcode);

CREATE UNIQUE INDEX uq_wf_pool_conversion_one_pending ON public.workforce_pool_conversion_requests USING btree (employee_id) WHERE (status = 'Pending'::text);

CREATE UNIQUE INDEX user_account_transfers_pkey ON public.user_account_transfers USING btree (id);

CREATE UNIQUE INDEX user_scopes_pkey ON public.user_scopes USING btree (id);

CREATE UNIQUE INDEX user_scopes_user_id_group_id_account_id_key ON public.user_scopes USING btree (user_id, group_id, account_id);

CREATE INDEX users_profile_account_id_idx ON public.users_profile USING btree (account_id);

CREATE UNIQUE INDEX users_profile_auth_user_id_key ON public.users_profile USING btree (auth_user_id);

CREATE UNIQUE INDEX users_profile_email_key ON public.users_profile USING btree (email);

CREATE UNIQUE INDEX users_profile_full_name_key ON public.users_profile USING btree (full_name);

CREATE INDEX users_profile_group_id_idx ON public.users_profile USING btree (group_id);

CREATE UNIQUE INDEX users_profile_pkey ON public.users_profile USING btree (id);

CREATE UNIQUE INDEX ux_qa_run_queue_active_lock ON public.qa_run_queue USING btree (lock_key) WHERE (queue_status = ANY (ARRAY['queued'::text, 'running'::text, 'blocked'::text]));

CREATE UNIQUE INDEX ux_stores_active_vcode_lower ON public.stores USING btree (lower(vcode)) WHERE (status = 'active'::text);

CREATE UNIQUE INDEX vacancies_pkey ON public.vacancies USING btree (id);

CREATE UNIQUE INDEX vacancies_vcode_key ON public.vacancies USING btree (vcode);

CREATE UNIQUE INDEX vacancy_closure_reasons_pkey ON public.vacancy_closure_reasons USING btree (id);

CREATE UNIQUE INDEX vacancy_closure_reasons_reason_key ON public.vacancy_closure_reasons USING btree (reason);

CREATE UNIQUE INDEX vacancy_closure_requests_pkey ON public.vacancy_closure_requests USING btree (id);

CREATE UNIQUE INDEX vacancy_coverage_pkey ON public.vacancy_coverage USING btree (id);

CREATE UNIQUE INDEX vacancy_requests_pkey ON public.vacancy_requests USING btree (id);

CREATE UNIQUE INDEX vcode_sequences_pkey ON public.vcode_sequences USING btree (prefix);

CREATE UNIQUE INDEX vcodes_pkey ON public.vcodes USING btree (id);

CREATE INDEX war_account_idx ON public.workforce_assignment_requests USING btree (requested_account_id);

CREATE INDEX war_employee_idx ON public.workforce_assignment_requests USING btree (employee_id);

CREATE UNIQUE INDEX war_one_pending_per_employee ON public.workforce_assignment_requests USING btree (employee_id) WHERE (status = 'Pending'::text);

CREATE INDEX war_requester_idx ON public.workforce_assignment_requests USING btree (requested_by_id);

CREATE INDEX war_status_idx ON public.workforce_assignment_requests USING btree (status);

CREATE UNIQUE INDEX workforce_assignment_requests_pkey ON public.workforce_assignment_requests USING btree (id);

CREATE UNIQUE INDEX workforce_assignments_pkey ON public.workforce_assignments USING btree (id);

CREATE UNIQUE INDEX workforce_pool_conversion_requests_pkey ON public.workforce_pool_conversion_requests USING btree (id);

CREATE UNIQUE INDEX workforce_pool_request_items_pkey ON public.workforce_pool_request_items USING btree (id);

CREATE UNIQUE INDEX workforce_pool_requests_pkey ON public.workforce_pool_requests USING btree (id);

CREATE UNIQUE INDEX workforce_pool_slots_pkey ON public.workforce_pool_slots USING btree (id);

CREATE UNIQUE INDEX workforce_pool_slots_vcode_key ON public.workforce_pool_slots USING btree (vcode);

CREATE UNIQUE INDEX workforce_pool_types_code_key ON public.workforce_pool_types USING btree (code);

CREATE UNIQUE INDEX workforce_pool_types_pkey ON public.workforce_pool_types USING btree (id);

CREATE UNIQUE INDEX workforce_pool_types_vcode_prefix_key ON public.workforce_pool_types USING btree (vcode_prefix);

CREATE UNIQUE INDEX workforce_pool_vcode_sequences_pkey ON public.workforce_pool_vcode_sequences USING btree (prefix);

CREATE UNIQUE INDEX workforce_slot_reviews_pkey ON public.workforce_slot_reviews USING btree (id);

alter table "public"."_deprecated_in_app_notifications" add constraint "in_app_notifications_pkey" PRIMARY KEY using index "in_app_notifications_pkey";

alter table "public"."account_positions" add constraint "account_positions_pkey" PRIMARY KEY using index "account_positions_pkey";

alter table "public"."account_request_account_scopes" add constraint "account_request_account_scopes_pkey" PRIMARY KEY using index "account_request_account_scopes_pkey";

alter table "public"."account_request_group_scopes" add constraint "account_request_group_scopes_pkey" PRIMARY KEY using index "account_request_group_scopes_pkey";

alter table "public"."account_requests" add constraint "account_requests_pkey" PRIMARY KEY using index "account_requests_pkey";

alter table "public"."accounts" add constraint "accounts_pkey" PRIMARY KEY using index "accounts_pkey";

alter table "public"."acting_sessions" add constraint "acting_sessions_pkey" PRIMARY KEY using index "acting_sessions_pkey";

alter table "public"."activity_log" add constraint "activity_log_pkey" PRIMARY KEY using index "activity_log_pkey";

alter table "public"."applicants" add constraint "applicants_pkey" PRIMARY KEY using index "applicants_pkey";

alter table "public"."audit_logs" add constraint "audit_logs_pkey" PRIMARY KEY using index "audit_logs_pkey";

alter table "public"."backout_reasons" add constraint "backout_reasons_pkey" PRIMARY KEY using index "backout_reasons_pkey";

alter table "public"."bulk_emploc_items" add constraint "bulk_emploc_items_pkey" PRIMARY KEY using index "bulk_emploc_items_pkey";

alter table "public"."bulk_emploc_uploads" add constraint "bulk_emploc_uploads_pkey" PRIMARY KEY using index "bulk_emploc_uploads_pkey";

alter table "public"."deactivation_audit_log" add constraint "deactivation_audit_log_pkey" PRIMARY KEY using index "deactivation_audit_log_pkey";

alter table "public"."deactivation_batches" add constraint "deactivation_batches_pkey" PRIMARY KEY using index "deactivation_batches_pkey";

alter table "public"."deactivation_items" add constraint "deactivation_items_pkey" PRIMARY KEY using index "deactivation_items_pkey";

alter table "public"."deactivation_requests" add constraint "deactivation_requests_pkey" PRIMARY KEY using index "deactivation_requests_pkey";

alter table "public"."deployer" add constraint "deployer_pkey" PRIMARY KEY using index "deployer_pkey";

alter table "public"."employee_activity_log" add constraint "employee_activity_log_pkey" PRIMARY KEY using index "employee_activity_log_pkey";

alter table "public"."employee_deployments" add constraint "employee_deployments_pkey" PRIMARY KEY using index "employee_deployments_pkey";

alter table "public"."employee_transfers" add constraint "employee_transfers_pkey" PRIMARY KEY using index "employee_transfers_pkey";

alter table "public"."employees" add constraint "employees_pkey" PRIMARY KEY using index "employees_pkey";

alter table "public"."feedback_reports" add constraint "feedback_reports_pkey" PRIMARY KEY using index "feedback_reports_pkey";

alter table "public"."groups" add constraint "groups_pkey" PRIMARY KEY using index "groups_pkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_pkey" PRIMARY KEY using index "headcount_requests_pkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_pkey" PRIMARY KEY using index "hr_emploc_pkey";

alter table "public"."hr_emploc_correction_attachments" add constraint "hr_emploc_correction_attachments_pkey" PRIMARY KEY using index "hr_emploc_correction_attachments_pkey";

alter table "public"."hr_emploc_deletion_requests" add constraint "hr_emploc_deletion_requests_pkey" PRIMARY KEY using index "hr_emploc_deletion_requests_pkey";

alter table "public"."hr_emploc_issue_types" add constraint "hr_emploc_issue_types_pkey" PRIMARY KEY using index "hr_emploc_issue_types_pkey";

alter table "public"."hr_emploc_rejection_reasons" add constraint "hr_emploc_rejection_reasons_pkey" PRIMARY KEY using index "hr_emploc_rejection_reasons_pkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_pkey" PRIMARY KEY using index "hr_emploc_store_links_pkey";

alter table "public"."login_sessions" add constraint "login_sessions_pkey" PRIMARY KEY using index "login_sessions_pkey";

alter table "public"."mika_import_logs" add constraint "mika_import_logs_pkey" PRIMARY KEY using index "mika_import_logs_pkey";

alter table "public"."mika_import_rows" add constraint "mika_import_rows_pkey" PRIMARY KEY using index "mika_import_rows_pkey";

alter table "public"."notifications" add constraint "notifications_pkey" PRIMARY KEY using index "notifications_pkey";

alter table "public"."plantilla" add constraint "plantilla_pkey" PRIMARY KEY using index "plantilla_pkey";

alter table "public"."plantilla_approvals" add constraint "plantilla_approvals_pkey" PRIMARY KEY using index "plantilla_approvals_pkey";

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_pkey" PRIMARY KEY using index "plantilla_store_links_pkey";

alter table "public"."positions" add constraint "positions_pkey" PRIMARY KEY using index "positions_pkey";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_pkey" PRIMARY KEY using index "possible_ghost_employees_pkey";

alter table "public"."qa_agent_evidence" add constraint "qa_agent_evidence_pkey" PRIMARY KEY using index "qa_agent_evidence_pkey";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_pkey" PRIMARY KEY using index "qa_agent_findings_pkey";

alter table "public"."qa_agent_rules" add constraint "qa_agent_rules_pkey" PRIMARY KEY using index "qa_agent_rules_pkey";

alter table "public"."qa_agent_runs" add constraint "qa_agent_runs_pkey" PRIMARY KEY using index "qa_agent_runs_pkey";

alter table "public"."qa_daily_reports" add constraint "qa_daily_reports_pkey" PRIMARY KEY using index "qa_daily_reports_pkey";

alter table "public"."qa_health_metrics" add constraint "qa_health_metrics_pkey" PRIMARY KEY using index "qa_health_metrics_pkey";

alter table "public"."qa_notifications" add constraint "qa_notifications_pkey" PRIMARY KEY using index "qa_notifications_pkey";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_pkey" PRIMARY KEY using index "qa_run_queue_pkey";

alter table "public"."qa_schedules" add constraint "qa_schedules_pkey" PRIMARY KEY using index "qa_schedules_pkey";

alter table "public"."ref_locations" add constraint "ref_locations_pkey" PRIMARY KEY using index "ref_locations_pkey";

alter table "public"."remote_tasks" add constraint "remote_tasks_pkey" PRIMARY KEY using index "remote_tasks_pkey";

alter table "public"."roles" add constraint "roles_pkey" PRIMARY KEY using index "roles_pkey";

alter table "public"."roving_assignments" add constraint "roving_assignments_pkey" PRIMARY KEY using index "roving_assignments_pkey";

alter table "public"."security_events" add constraint "security_events_pkey" PRIMARY KEY using index "security_events_pkey";

alter table "public"."sla_breach_logs" add constraint "sla_breach_logs_pkey" PRIMARY KEY using index "sla_breach_logs_pkey";

alter table "public"."staging_imports" add constraint "staging_imports_pkey" PRIMARY KEY using index "staging_imports_pkey";

alter table "public"."store_import_batches" add constraint "store_import_batches_pkey" PRIMARY KEY using index "store_import_batches_pkey";

alter table "public"."store_import_rows" add constraint "store_import_rows_pkey" PRIMARY KEY using index "store_import_rows_pkey";

alter table "public"."stores" add constraint "stores_pkey" PRIMARY KEY using index "stores_pkey";

alter table "public"."temp_approval_access" add constraint "temp_approval_access_pkey" PRIMARY KEY using index "temp_approval_access_pkey";

alter table "public"."temp_permission_overrides" add constraint "temp_permission_overrides_pkey" PRIMARY KEY using index "temp_permission_overrides_pkey";

alter table "public"."user_account_transfers" add constraint "user_account_transfers_pkey" PRIMARY KEY using index "user_account_transfers_pkey";

alter table "public"."user_scopes" add constraint "user_scopes_pkey" PRIMARY KEY using index "user_scopes_pkey";

alter table "public"."users_profile" add constraint "users_profile_pkey" PRIMARY KEY using index "users_profile_pkey";

alter table "public"."vacancies" add constraint "vacancies_pkey" PRIMARY KEY using index "vacancies_pkey";

alter table "public"."vacancy_closure_reasons" add constraint "vacancy_closure_reasons_pkey" PRIMARY KEY using index "vacancy_closure_reasons_pkey";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_pkey" PRIMARY KEY using index "vacancy_closure_requests_pkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_pkey" PRIMARY KEY using index "vacancy_coverage_pkey";

alter table "public"."vacancy_requests" add constraint "vacancy_requests_pkey" PRIMARY KEY using index "vacancy_requests_pkey";

alter table "public"."vcode_sequences" add constraint "vcode_sequences_pkey" PRIMARY KEY using index "vcode_sequences_pkey";

alter table "public"."vcodes" add constraint "vcodes_pkey" PRIMARY KEY using index "vcodes_pkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_pkey" PRIMARY KEY using index "workforce_assignment_requests_pkey";

alter table "public"."workforce_assignments" add constraint "workforce_assignments_pkey" PRIMARY KEY using index "workforce_assignments_pkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_pkey" PRIMARY KEY using index "workforce_pool_conversion_requests_pkey";

alter table "public"."workforce_pool_request_items" add constraint "workforce_pool_request_items_pkey" PRIMARY KEY using index "workforce_pool_request_items_pkey";

alter table "public"."workforce_pool_requests" add constraint "workforce_pool_requests_pkey" PRIMARY KEY using index "workforce_pool_requests_pkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_pkey" PRIMARY KEY using index "workforce_pool_slots_pkey";

alter table "public"."workforce_pool_types" add constraint "workforce_pool_types_pkey" PRIMARY KEY using index "workforce_pool_types_pkey";

alter table "public"."workforce_pool_vcode_sequences" add constraint "workforce_pool_vcode_sequences_pkey" PRIMARY KEY using index "workforce_pool_vcode_sequences_pkey";

alter table "public"."workforce_slot_reviews" add constraint "workforce_slot_reviews_pkey" PRIMARY KEY using index "workforce_slot_reviews_pkey";

alter table "public"."account_positions" add constraint "account_positions_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."account_positions" validate constraint "account_positions_account_id_fkey";

alter table "public"."account_positions" add constraint "account_positions_account_id_position_id_key" UNIQUE using index "account_positions_account_id_position_id_key";

alter table "public"."account_positions" add constraint "account_positions_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) ON DELETE CASCADE not valid;

alter table "public"."account_positions" validate constraint "account_positions_position_id_fkey";

alter table "public"."account_request_account_scopes" add constraint "account_request_account_scope_account_request_id_account_id_key" UNIQUE using index "account_request_account_scope_account_request_id_account_id_key";

alter table "public"."account_request_account_scopes" add constraint "account_request_account_scopes_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."account_request_account_scopes" validate constraint "account_request_account_scopes_account_id_fkey";

alter table "public"."account_request_account_scopes" add constraint "account_request_account_scopes_account_request_id_fkey" FOREIGN KEY (account_request_id) REFERENCES public.account_requests(id) ON DELETE CASCADE not valid;

alter table "public"."account_request_account_scopes" validate constraint "account_request_account_scopes_account_request_id_fkey";

alter table "public"."account_request_group_scopes" add constraint "account_request_group_scopes_account_request_id_fkey" FOREIGN KEY (account_request_id) REFERENCES public.account_requests(id) ON DELETE CASCADE not valid;

alter table "public"."account_request_group_scopes" validate constraint "account_request_group_scopes_account_request_id_fkey";

alter table "public"."account_request_group_scopes" add constraint "account_request_group_scopes_account_request_id_group_id_key" UNIQUE using index "account_request_group_scopes_account_request_id_group_id_key";

alter table "public"."account_request_group_scopes" add constraint "account_request_group_scopes_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE not valid;

alter table "public"."account_request_group_scopes" validate constraint "account_request_group_scopes_group_id_fkey";

alter table "public"."account_requests" add constraint "account_requests_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."account_requests" validate constraint "account_requests_auth_user_id_fkey";

alter table "public"."account_requests" add constraint "account_requests_auth_user_id_key" UNIQUE using index "account_requests_auth_user_id_key";

alter table "public"."account_requests" add constraint "account_requests_requested_role_id_fkey" FOREIGN KEY (requested_role_id) REFERENCES public.roles(id) not valid;

alter table "public"."account_requests" validate constraint "account_requests_requested_role_id_fkey";

alter table "public"."account_requests" add constraint "account_requests_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL not valid;

alter table "public"."account_requests" validate constraint "account_requests_reviewed_by_fkey";

alter table "public"."account_requests" add constraint "account_requests_scope_type_check" CHECK (((assigned_scope_type IS NULL) OR (assigned_scope_type = ANY (ARRAY['global'::text, 'scoped'::text, 'custom'::text])))) not valid;

alter table "public"."account_requests" validate constraint "account_requests_scope_type_check";

alter table "public"."accounts" add constraint "accounts_account_name_unique" UNIQUE using index "accounts_account_name_unique";

alter table "public"."accounts" add constraint "accounts_group_id_account_name_key" UNIQUE using index "accounts_group_id_account_name_key";

alter table "public"."accounts" add constraint "accounts_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE not valid;

alter table "public"."accounts" validate constraint "accounts_group_id_fkey";

alter table "public"."accounts" add constraint "accounts_hrco_user_id_fkey" FOREIGN KEY (hrco_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."accounts" validate constraint "accounts_hrco_user_id_fkey";

alter table "public"."accounts" add constraint "accounts_status_check" CHECK ((status = ANY (ARRAY['Active'::text, 'Inactive'::text]))) not valid;

alter table "public"."accounts" validate constraint "accounts_status_check";

alter table "public"."acting_sessions" add constraint "acting_sessions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) not valid;

alter table "public"."acting_sessions" validate constraint "acting_sessions_created_by_fkey";

alter table "public"."acting_sessions" add constraint "acting_sessions_ended_by_fkey" FOREIGN KEY (ended_by) REFERENCES auth.users(id) not valid;

alter table "public"."acting_sessions" validate constraint "acting_sessions_ended_by_fkey";

alter table "public"."acting_sessions" add constraint "acting_sessions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."acting_sessions" validate constraint "acting_sessions_user_id_fkey";

alter table "public"."activity_log" add constraint "activity_log_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES public.users_profile(id) ON DELETE SET NULL not valid;

alter table "public"."activity_log" validate constraint "activity_log_actor_id_fkey";

alter table "public"."applicants" add constraint "applicants_hired_by_user_id_fkey" FOREIGN KEY (hired_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicants" validate constraint "applicants_hired_by_user_id_fkey";

alter table "public"."applicants" add constraint "applicants_recruited_by_user_id_fkey" FOREIGN KEY (recruited_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."applicants" validate constraint "applicants_recruited_by_user_id_fkey";

alter table "public"."applicants" add constraint "applicants_roving_assignment_id_fkey" FOREIGN KEY (roving_assignment_id) REFERENCES public.roving_assignments(id) ON DELETE SET NULL not valid;

alter table "public"."applicants" validate constraint "applicants_roving_assignment_id_fkey";

alter table "public"."applicants" add constraint "chk_applicants_contact_number_format" CHECK (((contact_number IS NULL) OR (contact_number ~ '^09[0-9]{9}$'::text))) not valid;

alter table "public"."applicants" validate constraint "chk_applicants_contact_number_format";

alter table "public"."applicants" add constraint "fk_applicants_vacancy_vcode" FOREIGN KEY (vacancy_vcode) REFERENCES public.vacancies(vcode) ON DELETE CASCADE not valid;

alter table "public"."applicants" validate constraint "fk_applicants_vacancy_vcode";

alter table "public"."audit_logs" add constraint "audit_logs_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES auth.users(id) not valid;

alter table "public"."audit_logs" validate constraint "audit_logs_actor_id_fkey";

alter table "public"."backout_reasons" add constraint "backout_reasons_reason_key" UNIQUE using index "backout_reasons_reason_key";

alter table "public"."bulk_emploc_items" add constraint "bulk_emploc_items_match_status_check" CHECK ((match_status = ANY (ARRAY['Matched'::text, 'Unmatched'::text, 'Applied'::text]))) not valid;

alter table "public"."bulk_emploc_items" validate constraint "bulk_emploc_items_match_status_check";

alter table "public"."bulk_emploc_items" add constraint "bulk_emploc_items_upload_id_fkey" FOREIGN KEY (upload_id) REFERENCES public.bulk_emploc_uploads(id) ON DELETE CASCADE not valid;

alter table "public"."bulk_emploc_items" validate constraint "bulk_emploc_items_upload_id_fkey";

alter table "public"."bulk_emploc_uploads" add constraint "bulk_emploc_uploads_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text]))) not valid;

alter table "public"."bulk_emploc_uploads" validate constraint "bulk_emploc_uploads_status_check";

alter table "public"."bulk_emploc_uploads" add constraint "bulk_emploc_uploads_uploaded_by_user_id_fkey" FOREIGN KEY (uploaded_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."bulk_emploc_uploads" validate constraint "bulk_emploc_uploads_uploaded_by_user_id_fkey";

alter table "public"."deactivation_audit_log" add constraint "deactivation_audit_log_request_id_fkey" FOREIGN KEY (request_id) REFERENCES public.deactivation_requests(id) not valid;

alter table "public"."deactivation_audit_log" validate constraint "deactivation_audit_log_request_id_fkey";

alter table "public"."deactivation_items" add constraint "deactivation_items_plantilla_id_fkey" FOREIGN KEY (plantilla_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."deactivation_items" validate constraint "deactivation_items_plantilla_id_fkey";

alter table "public"."deactivation_items" add constraint "deactivation_items_request_id_fkey" FOREIGN KEY (request_id) REFERENCES public.deactivation_requests(id) ON DELETE CASCADE not valid;

alter table "public"."deactivation_items" validate constraint "deactivation_items_request_id_fkey";

alter table "public"."deactivation_items" add constraint "deactivation_items_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Deactivated'::text, 'Rejected'::text]))) not valid;

alter table "public"."deactivation_items" validate constraint "deactivation_items_status_check";

alter table "public"."deactivation_requests" add constraint "deactivation_requests_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Processing'::text, 'Completed'::text, 'Partially Completed'::text, 'Rejected'::text]))) not valid;

alter table "public"."deactivation_requests" validate constraint "deactivation_requests_status_check";

alter table "public"."deployer" add constraint "deployer_name_key" UNIQUE using index "deployer_name_key";

alter table "public"."employee_deployments" add constraint "employee_deployments_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES public.employees(id) not valid;

alter table "public"."employee_deployments" validate constraint "employee_deployments_employee_id_fkey";

alter table "public"."employee_deployments" add constraint "employee_deployments_status_check" CHECK ((status = ANY (ARRAY['Active'::text, 'Resigned'::text]))) not valid;

alter table "public"."employee_deployments" validate constraint "employee_deployments_status_check";

alter table "public"."employee_deployments" add constraint "employee_deployments_vcode_fkey" FOREIGN KEY (vcode) REFERENCES public.vacancies(vcode) not valid;

alter table "public"."employee_deployments" validate constraint "employee_deployments_vcode_fkey";

alter table "public"."employee_transfers" add constraint "chk_transfer_status" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text]))) not valid;

alter table "public"."employee_transfers" validate constraint "chk_transfer_status";

alter table "public"."employee_transfers" add constraint "employee_transfers_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text]))) not valid;

alter table "public"."employee_transfers" validate constraint "employee_transfers_status_check";

alter table "public"."employees" add constraint "employees_employee_no_key" UNIQUE using index "employees_employee_no_key";

alter table "public"."employees" add constraint "employees_status_check" CHECK ((status = ANY (ARRAY['Active'::text, 'Resigned'::text, 'Inactive'::text]))) not valid;

alter table "public"."employees" validate constraint "employees_status_check";

alter table "public"."feedback_reports" add constraint "feedback_reports_priority_check" CHECK ((priority = ANY (ARRAY['Low'::text, 'Normal'::text, 'High'::text, 'Critical'::text]))) not valid;

alter table "public"."feedback_reports" validate constraint "feedback_reports_priority_check";

alter table "public"."feedback_reports" add constraint "feedback_reports_status_check" CHECK ((status = ANY (ARRAY['Open'::text, 'In Progress'::text, 'Resolved'::text, 'Closed'::text]))) not valid;

alter table "public"."feedback_reports" validate constraint "feedback_reports_status_check";

alter table "public"."feedback_reports" add constraint "feedback_reports_type_check" CHECK ((type = ANY (ARRAY['Bug'::text, 'Suggestion'::text, 'Improvement'::text]))) not valid;

alter table "public"."feedback_reports" validate constraint "feedback_reports_type_check";

alter table "public"."groups" add constraint "groups_group_code_key" UNIQUE using index "groups_group_code_key";

alter table "public"."groups" add constraint "groups_group_name_key" UNIQUE using index "groups_group_name_key";

alter table "public"."headcount_requests" add constraint "headcount_requests_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_account_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_created_plantilla_id_fkey" FOREIGN KEY (created_plantilla_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_created_plantilla_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_employment_type_check" CHECK ((employment_type = ANY (ARRAY['Stationary'::text, 'Roving'::text]))) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_employment_type_check";

alter table "public"."headcount_requests" add constraint "headcount_requests_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_group_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_headcount_needed_check" CHECK ((headcount_needed > 0)) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_headcount_needed_check";

alter table "public"."headcount_requests" add constraint "headcount_requests_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_position_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_request_type_check" CHECK ((request_type = ANY (ARRAY['Replacement'::text, 'Additional Headcount'::text, 'Temporary'::text, 'Reliever'::text, 'Commando'::text]))) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_request_type_check";

alter table "public"."headcount_requests" add constraint "headcount_requests_requested_by_user_id_fkey" FOREIGN KEY (requested_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_requested_by_user_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_reviewed_by_user_id_fkey" FOREIGN KEY (reviewed_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_reviewed_by_user_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_slot_created_by_user_id_fkey" FOREIGN KEY (slot_created_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_slot_created_by_user_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'under_review'::text, 'approved_pending_vcode'::text, 'completed'::text, 'rejected'::text]))) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_status_check";

alter table "public"."headcount_requests" add constraint "headcount_requests_store_id_fkey" FOREIGN KEY (store_id) REFERENCES public.stores(id) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_store_id_fkey";

alter table "public"."headcount_requests" add constraint "headcount_requests_urgency_check" CHECK ((urgency = ANY (ARRAY['Low'::text, 'Medium'::text, 'High'::text, 'Critical'::text]))) not valid;

alter table "public"."headcount_requests" validate constraint "headcount_requests_urgency_check";

alter table "public"."hr_emploc" add constraint "fk_hr_emploc_vcode" FOREIGN KEY (vcode) REFERENCES public.vacancies(vcode) ON DELETE CASCADE not valid;

alter table "public"."hr_emploc" validate constraint "fk_hr_emploc_vcode";

alter table "public"."hr_emploc" add constraint "hr_emploc_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_account_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_applicant_id_fkey" FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_applicant_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_applicant_vcode_unique" UNIQUE using index "hr_emploc_applicant_vcode_unique";

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

alter table "public"."hr_emploc" add constraint "hr_emploc_hr_status_check" CHECK ((hr_status = ANY (ARRAY['Pending'::text, 'For Correction'::text, 'For Review'::text, 'Complete'::text, 'Rejected'::text, 'Transferred'::text]))) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_hr_status_check";

alter table "public"."hr_emploc" add constraint "hr_emploc_position_id_snapshot_fkey" FOREIGN KEY (position_id_snapshot) REFERENCES public.positions(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_position_id_snapshot_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_roving_assignment_id_fkey" FOREIGN KEY (roving_assignment_id) REFERENCES public.roving_assignments(id) ON DELETE SET NULL not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_roving_assignment_id_fkey";

alter table "public"."hr_emploc" add constraint "hr_emploc_status_check" CHECK ((status = ANY (ARRAY['Pending Emploc'::text, 'Pending Requirements'::text, 'For Compliance'::text, 'Ready for Plantilla'::text, 'Pending Approval'::text, 'Moved to Plantilla'::text, 'In Review'::text, 'Complete'::text, 'Ready for Deployment'::text, 'Backout'::text]))) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_status_check";

alter table "public"."hr_emploc" add constraint "hr_emploc_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_vacancy_id_fkey";

alter table "public"."hr_emploc_correction_attachments" add constraint "hr_emploc_correction_attachments_hr_emploc_id_fkey" FOREIGN KEY (hr_emploc_id) REFERENCES public.hr_emploc(id) ON DELETE CASCADE not valid;

alter table "public"."hr_emploc_correction_attachments" validate constraint "hr_emploc_correction_attachments_hr_emploc_id_fkey";

alter table "public"."hr_emploc_correction_attachments" add constraint "hr_emploc_correction_attachments_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES public.users_profile(id) ON DELETE SET NULL not valid;

alter table "public"."hr_emploc_correction_attachments" validate constraint "hr_emploc_correction_attachments_uploaded_by_fkey";

alter table "public"."hr_emploc_deletion_requests" add constraint "hr_emploc_deletion_requests_hr_emploc_id_fkey" FOREIGN KEY (hr_emploc_id) REFERENCES public.hr_emploc(id) ON DELETE SET NULL not valid;

alter table "public"."hr_emploc_deletion_requests" validate constraint "hr_emploc_deletion_requests_hr_emploc_id_fkey";

alter table "public"."hr_emploc_deletion_requests" add constraint "hr_emploc_deletion_requests_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text]))) not valid;

alter table "public"."hr_emploc_deletion_requests" validate constraint "hr_emploc_deletion_requests_status_check";

alter table "public"."hr_emploc_issue_types" add constraint "hr_emploc_issue_types_code_key" UNIQUE using index "hr_emploc_issue_types_code_key";

alter table "public"."hr_emploc_rejection_reasons" add constraint "hr_emploc_rejection_reasons_reason_key" UNIQUE using index "hr_emploc_rejection_reasons_reason_key";

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

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Confirmed'::text, 'Backed Out'::text, 'Resigned'::text]))) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_status_check";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_updated_by_fkey";

alter table "public"."hr_emploc_store_links" add constraint "hr_emploc_store_links_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."hr_emploc_store_links" validate constraint "hr_emploc_store_links_vacancy_id_fkey";

alter table "public"."login_sessions" add constraint "login_sessions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users_profile(id) ON DELETE CASCADE not valid;

alter table "public"."login_sessions" validate constraint "login_sessions_user_id_fkey";

alter table "public"."mika_import_logs" add constraint "mika_import_logs_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text]))) not valid;

alter table "public"."mika_import_logs" validate constraint "mika_import_logs_status_check";

alter table "public"."mika_import_rows" add constraint "mika_import_rows_import_log_id_fkey" FOREIGN KEY (import_log_id) REFERENCES public.mika_import_logs(id) ON DELETE CASCADE not valid;

alter table "public"."mika_import_rows" validate constraint "mika_import_rows_import_log_id_fkey";

alter table "public"."notifications" add constraint "notifications_user_id_fkey" FOREIGN KEY (recipient_user_id) REFERENCES auth.users(id) not valid;

alter table "public"."notifications" validate constraint "notifications_user_id_fkey";

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

alter table "public"."plantilla" add constraint "plantilla_last_mika_synced_by_fkey" FOREIGN KEY (last_mika_synced_by) REFERENCES auth.users(id) ON DELETE SET NULL not valid;

alter table "public"."plantilla" validate constraint "plantilla_last_mika_synced_by_fkey";

alter table "public"."plantilla" add constraint "plantilla_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_position_id_fkey";

alter table "public"."plantilla" add constraint "plantilla_roving_assignment_id_fkey" FOREIGN KEY (roving_assignment_id) REFERENCES public.roving_assignments(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_roving_assignment_id_fkey";

alter table "public"."plantilla" add constraint "plantilla_separation_status_check" CHECK ((separation_status = ANY (ARRAY['AWOL'::text, 'Resigned'::text, 'Endo'::text, 'Others'::text]))) not valid;

alter table "public"."plantilla" validate constraint "plantilla_separation_status_check";

alter table "public"."plantilla" add constraint "plantilla_source_headcount_request_fk" FOREIGN KEY (source_headcount_request_id) REFERENCES public.headcount_requests(id) not valid;

alter table "public"."plantilla" validate constraint "plantilla_source_headcount_request_fk";

alter table "public"."plantilla" add constraint "plantilla_status_check" CHECK ((status = ANY (ARRAY['Active'::text, 'Inactive'::text, 'For Deactivation'::text, 'Deactivated'::text, 'Resigned'::text, 'Transferred'::text, 'On Leave'::text]))) not valid;

alter table "public"."plantilla" validate constraint "plantilla_status_check";

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

alter table "public"."plantilla_store_links" add constraint "plantilla_store_links_status_check" CHECK ((status = ANY (ARRAY['Active'::text, 'Backed Out'::text, 'Resigned'::text]))) not valid;

alter table "public"."plantilla_store_links" validate constraint "plantilla_store_links_status_check";

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

alter table "public"."positions" add constraint "positions_position_name_key" UNIQUE using index "positions_position_name_key";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_assigned_encoder_id_fkey" FOREIGN KEY (assigned_encoder_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."possible_ghost_employees" validate constraint "possible_ghost_employees_assigned_encoder_id_fkey";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_ghost_type_check" CHECK ((ghost_type = ANY (ARRAY['Type A'::text, 'Type B'::text]))) not valid;

alter table "public"."possible_ghost_employees" validate constraint "possible_ghost_employees_ghost_type_check";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_import_log_id_fkey" FOREIGN KEY (import_log_id) REFERENCES public.mika_import_logs(id) not valid;

alter table "public"."possible_ghost_employees" validate constraint "possible_ghost_employees_import_log_id_fkey";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_resolved_by_user_id_fkey" FOREIGN KEY (resolved_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."possible_ghost_employees" validate constraint "possible_ghost_employees_resolved_by_user_id_fkey";

alter table "public"."possible_ghost_employees" add constraint "possible_ghost_employees_status_check" CHECK ((status = ANY (ARRAY['Under Investigation'::text, 'For Encoding'::text, 'Cleared'::text, 'Confirmed Ghost'::text, 'For Termination'::text, 'Resolved'::text]))) not valid;

alter table "public"."possible_ghost_employees" validate constraint "possible_ghost_employees_status_check";

alter table "public"."qa_agent_evidence" add constraint "qa_agent_evidence_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_evidence" validate constraint "qa_agent_evidence_created_by_fkey";

alter table "public"."qa_agent_evidence" add constraint "qa_agent_evidence_evidence_type_check" CHECK ((evidence_type = ANY (ARRAY['snapshot'::text, 'query_result'::text, 'rule_match'::text, 'system_event'::text, 'manual_note'::text]))) not valid;

alter table "public"."qa_agent_evidence" validate constraint "qa_agent_evidence_evidence_type_check";

alter table "public"."qa_agent_evidence" add constraint "qa_agent_evidence_finding_id_fkey" FOREIGN KEY (finding_id) REFERENCES public.qa_agent_findings(id) ON DELETE CASCADE not valid;

alter table "public"."qa_agent_evidence" validate constraint "qa_agent_evidence_finding_id_fkey";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_assigned_to_fkey" FOREIGN KEY (assigned_to) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_findings" validate constraint "qa_agent_findings_assigned_to_fkey";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_resolved_by_fkey" FOREIGN KEY (resolved_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_findings" validate constraint "qa_agent_findings_resolved_by_fkey";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_run_id_fkey" FOREIGN KEY (run_id) REFERENCES public.qa_agent_runs(id) ON DELETE CASCADE not valid;

alter table "public"."qa_agent_findings" validate constraint "qa_agent_findings_run_id_fkey";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_severity_check" CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))) not valid;

alter table "public"."qa_agent_findings" validate constraint "qa_agent_findings_severity_check";

alter table "public"."qa_agent_findings" add constraint "qa_agent_findings_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text, 'ignored'::text]))) not valid;

alter table "public"."qa_agent_findings" validate constraint "qa_agent_findings_status_check";

alter table "public"."qa_agent_rules" add constraint "qa_agent_rules_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_rules" validate constraint "qa_agent_rules_created_by_fkey";

alter table "public"."qa_agent_rules" add constraint "qa_agent_rules_rule_code_key" UNIQUE using index "qa_agent_rules_rule_code_key";

alter table "public"."qa_agent_rules" add constraint "qa_agent_rules_severity_check" CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))) not valid;

alter table "public"."qa_agent_rules" validate constraint "qa_agent_rules_severity_check";

alter table "public"."qa_agent_rules" add constraint "qa_agent_rules_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_rules" validate constraint "qa_agent_rules_updated_by_fkey";

alter table "public"."qa_agent_runs" add constraint "qa_agent_runs_execution_type_check" CHECK ((execution_type = ANY (ARRAY['manual'::text, 'scheduled'::text, 'event_driven'::text]))) not valid;

alter table "public"."qa_agent_runs" validate constraint "qa_agent_runs_execution_type_check";

alter table "public"."qa_agent_runs" add constraint "qa_agent_runs_initiated_by_fkey" FOREIGN KEY (initiated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_agent_runs" validate constraint "qa_agent_runs_initiated_by_fkey";

alter table "public"."qa_agent_runs" add constraint "qa_agent_runs_status_check" CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'completed'::text, 'failed'::text, 'cancelled'::text]))) not valid;

alter table "public"."qa_agent_runs" validate constraint "qa_agent_runs_status_check";

alter table "public"."qa_daily_reports" add constraint "qa_daily_reports_environment_check" CHECK ((environment = ANY (ARRAY['staging'::text, 'production_readonly'::text]))) not valid;

alter table "public"."qa_daily_reports" validate constraint "qa_daily_reports_environment_check";

alter table "public"."qa_daily_reports" add constraint "qa_daily_reports_generated_by_fkey" FOREIGN KEY (generated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_daily_reports" validate constraint "qa_daily_reports_generated_by_fkey";

alter table "public"."qa_daily_reports" add constraint "qa_daily_reports_health_status_check" CHECK ((health_status = ANY (ARRAY['stable'::text, 'warning'::text, 'unstable'::text, 'critical'::text]))) not valid;

alter table "public"."qa_daily_reports" validate constraint "qa_daily_reports_health_status_check";

alter table "public"."qa_daily_reports" add constraint "qa_daily_reports_report_date_environment_key" UNIQUE using index "qa_daily_reports_report_date_environment_key";

alter table "public"."qa_health_metrics" add constraint "qa_health_metrics_environment_check" CHECK ((environment = ANY (ARRAY['staging'::text, 'production_readonly'::text]))) not valid;

alter table "public"."qa_health_metrics" validate constraint "qa_health_metrics_environment_check";

alter table "public"."qa_health_metrics" add constraint "qa_health_metrics_metric_date_environment_metric_name_key" UNIQUE using index "qa_health_metrics_metric_date_environment_metric_name_key";

alter table "public"."qa_health_metrics" add constraint "qa_health_metrics_metric_status_check" CHECK ((metric_status = ANY (ARRAY['stable'::text, 'warning'::text, 'unstable'::text, 'critical'::text]))) not valid;

alter table "public"."qa_health_metrics" validate constraint "qa_health_metrics_metric_status_check";

alter table "public"."qa_notifications" add constraint "qa_notifications_notification_type_check" CHECK ((notification_type = ANY (ARRAY['immediate'::text, 'daily_digest'::text, 'weekly_digest'::text, 'system'::text]))) not valid;

alter table "public"."qa_notifications" validate constraint "qa_notifications_notification_type_check";

alter table "public"."qa_notifications" add constraint "qa_notifications_severity_check" CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))) not valid;

alter table "public"."qa_notifications" validate constraint "qa_notifications_severity_check";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_environment_check" CHECK ((environment = ANY (ARRAY['staging'::text, 'production_readonly'::text]))) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_environment_check";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_failure_type_check" CHECK (((failure_type IS NULL) OR (failure_type = ANY (ARRAY['network'::text, 'infrastructure'::text, 'timeout'::text, 'rls_security'::text, 'assertion'::text, 'unknown'::text])))) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_failure_type_check";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_max_retries_check" CHECK ((max_retries >= 0)) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_max_retries_check";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_queue_status_check" CHECK ((queue_status = ANY (ARRAY['queued'::text, 'running'::text, 'completed'::text, 'failed'::text, 'blocked'::text, 'cancelled'::text, 'expired'::text]))) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_queue_status_check";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_retry_count_check" CHECK ((retry_count >= 0)) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_retry_count_check";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_run_id_fkey" FOREIGN KEY (run_id) REFERENCES public.qa_agent_runs(id) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_run_id_fkey";

alter table "public"."qa_run_queue" add constraint "qa_run_queue_schedule_id_fkey" FOREIGN KEY (schedule_id) REFERENCES public.qa_schedules(id) not valid;

alter table "public"."qa_run_queue" validate constraint "qa_run_queue_schedule_id_fkey";

alter table "public"."qa_schedules" add constraint "qa_schedules_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_schedules" validate constraint "qa_schedules_created_by_fkey";

alter table "public"."qa_schedules" add constraint "qa_schedules_environment_check" CHECK ((environment = ANY (ARRAY['staging'::text, 'production_readonly'::text]))) not valid;

alter table "public"."qa_schedules" validate constraint "qa_schedules_environment_check";

alter table "public"."qa_schedules" add constraint "qa_schedules_frequency_check" CHECK ((frequency = ANY (ARRAY['hourly'::text, 'daily'::text, 'weekly'::text, 'monthly'::text, 'manual'::text]))) not valid;

alter table "public"."qa_schedules" validate constraint "qa_schedules_frequency_check";

alter table "public"."qa_schedules" add constraint "qa_schedules_schedule_name_key" UNIQUE using index "qa_schedules_schedule_name_key";

alter table "public"."qa_schedules" add constraint "qa_schedules_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.users_profile(id) not valid;

alter table "public"."qa_schedules" validate constraint "qa_schedules_updated_by_fkey";

alter table "public"."remote_tasks" add constraint "remote_tasks_command_whitelist" CHECK ((command = ANY (ARRAY['expire_temp_overrides'::text, 'check_ghost_deadlines'::text, 'sync_headcount'::text, 'recompute_scope'::text, 'archive_old_notifications'::text, 'cleanup_remote_tasks'::text]))) not valid;

alter table "public"."remote_tasks" validate constraint "remote_tasks_command_whitelist";

alter table "public"."roving_assignments" add constraint "roving_assignments_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."roving_assignments" validate constraint "roving_assignments_account_id_fkey";

alter table "public"."roving_assignments" add constraint "roving_assignments_master_applicant_id_fkey" FOREIGN KEY (master_applicant_id) REFERENCES public.applicants(id) not valid;

alter table "public"."roving_assignments" validate constraint "roving_assignments_master_applicant_id_fkey";

alter table "public"."sla_breach_logs" add constraint "sla_breach_logs_breach_type_check" CHECK ((breach_type = ANY (ARRAY['resignation_not_tagged'::text, 'inactive_no_deactivation_request'::text, 'deactivation_overdue'::text]))) not valid;

alter table "public"."sla_breach_logs" validate constraint "sla_breach_logs_breach_type_check";

alter table "public"."sla_breach_logs" add constraint "sla_breach_logs_plantilla_id_fkey" FOREIGN KEY (plantilla_id) REFERENCES public.plantilla(id) ON DELETE SET NULL not valid;

alter table "public"."sla_breach_logs" validate constraint "sla_breach_logs_plantilla_id_fkey";

alter table "public"."sla_breach_logs" add constraint "uq_sla_breach_plantilla" UNIQUE using index "uq_sla_breach_plantilla";

alter table "public"."staging_imports" add constraint "chk_approved_consistency" CHECK (((approved_by IS NULL) = (approved_at IS NULL))) not valid;

alter table "public"."staging_imports" validate constraint "chk_approved_consistency";

alter table "public"."staging_imports" add constraint "chk_validated_consistency" CHECK (((validated_by IS NULL) = (validated_at IS NULL))) not valid;

alter table "public"."staging_imports" validate constraint "chk_validated_consistency";

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

alter table "public"."store_import_batches" add constraint "store_import_batches_status_check" CHECK ((status = ANY (ARRAY['draft_uploaded'::text, 'validation_failed'::text, 'pending_approval'::text, 'approved'::text, 'rejected'::text, 'superseded'::text]))) not valid;

alter table "public"."store_import_batches" validate constraint "store_import_batches_status_check";

alter table "public"."store_import_rows" add constraint "store_import_rows_batch_id_fkey" FOREIGN KEY (batch_id) REFERENCES public.store_import_batches(id) ON DELETE CASCADE not valid;

alter table "public"."store_import_rows" validate constraint "store_import_rows_batch_id_fkey";

alter table "public"."store_import_rows" add constraint "store_import_rows_validation_status_check" CHECK ((validation_status = ANY (ARRAY['valid'::text, 'invalid'::text]))) not valid;

alter table "public"."store_import_rows" validate constraint "store_import_rows_validation_status_check";

alter table "public"."stores" add constraint "stores_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."stores" validate constraint "stores_account_id_fkey";

alter table "public"."stores" add constraint "stores_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) not valid;

alter table "public"."stores" validate constraint "stores_group_id_fkey";

alter table "public"."stores" add constraint "stores_hrco_user_id_fkey" FOREIGN KEY (hrco_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."stores" validate constraint "stores_hrco_user_id_fkey";

alter table "public"."stores" add constraint "stores_om_user_id_fkey" FOREIGN KEY (om_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."stores" validate constraint "stores_om_user_id_fkey";

alter table "public"."stores" add constraint "stores_status_chk" CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text]))) not valid;

alter table "public"."stores" validate constraint "stores_status_chk";

alter table "public"."stores" add constraint "stores_type_chk" CHECK (((employment_type IS NULL) OR (employment_type = ANY (ARRAY['stationary'::text, 'roving'::text])))) not valid;

alter table "public"."stores" validate constraint "stores_type_chk";

alter table "public"."temp_approval_access" add constraint "temp_approval_access_granted_by_fkey" FOREIGN KEY (granted_by) REFERENCES public.users_profile(id) ON DELETE CASCADE not valid;

alter table "public"."temp_approval_access" validate constraint "temp_approval_access_granted_by_fkey";

alter table "public"."temp_approval_access" add constraint "temp_approval_access_granted_to_fkey" FOREIGN KEY (granted_to) REFERENCES public.users_profile(id) ON DELETE CASCADE not valid;

alter table "public"."temp_approval_access" validate constraint "temp_approval_access_granted_to_fkey";

alter table "public"."temp_approval_access" add constraint "temp_approval_valid_window" CHECK ((valid_until > valid_from)) not valid;

alter table "public"."temp_approval_access" validate constraint "temp_approval_valid_window";

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

alter table "public"."user_scopes" add constraint "user_scopes_user_id_group_id_account_id_key" UNIQUE using index "user_scopes_user_id_group_id_account_id_key";

alter table "public"."users_profile" add constraint "fk_users_profile_group" FOREIGN KEY (group_id) REFERENCES public.groups(id) not valid;

alter table "public"."users_profile" validate constraint "fk_users_profile_group";

alter table "public"."users_profile" add constraint "users_profile_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE SET NULL not valid;

alter table "public"."users_profile" validate constraint "users_profile_account_id_fkey";

alter table "public"."users_profile" add constraint "users_profile_auth_user_id_key" UNIQUE using index "users_profile_auth_user_id_key";

alter table "public"."users_profile" add constraint "users_profile_email_key" UNIQUE using index "users_profile_email_key";

alter table "public"."users_profile" add constraint "users_profile_full_name_key" UNIQUE using index "users_profile_full_name_key";

alter table "public"."users_profile" add constraint "users_profile_role_id_fkey" FOREIGN KEY (role_id) REFERENCES public.roles(id) not valid;

alter table "public"."users_profile" validate constraint "users_profile_role_id_fkey";

alter table "public"."users_profile" add constraint "users_profile_scope_type_check" CHECK (((scope_type IS NULL) OR (scope_type = ANY (ARRAY['global'::text, 'scoped'::text, 'custom'::text])))) not valid;

alter table "public"."users_profile" validate constraint "users_profile_scope_type_check";

alter table "public"."vacancies" add constraint "fk_vacancies_store_id" FOREIGN KEY (store_id) REFERENCES public.stores(id) not valid;

alter table "public"."vacancies" validate constraint "fk_vacancies_store_id";

alter table "public"."vacancies" add constraint "uq_vacancy_source_plantilla" UNIQUE using index "uq_vacancy_source_plantilla";

alter table "public"."vacancies" add constraint "vacancies_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."vacancies" validate constraint "vacancies_account_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_assigned_encoder_id_fkey" FOREIGN KEY (assigned_encoder_id) REFERENCES public.users_profile(id) ON DELETE SET NULL not valid;

alter table "public"."vacancies" validate constraint "vacancies_assigned_encoder_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_closure_request_status_check" CHECK ((closure_request_status = ANY (ARRAY['None'::text, 'Pending'::text, 'Approved'::text, 'Rejected'::text, 'Processed'::text]))) not valid;

alter table "public"."vacancies" validate constraint "vacancies_closure_request_status_check";

alter table "public"."vacancies" add constraint "vacancies_home_account_id_fkey" FOREIGN KEY (home_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_home_account_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_pool_request_id_fkey" FOREIGN KEY (pool_request_id) REFERENCES public.workforce_pool_requests(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_pool_request_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_pool_type_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_position_id_fkey" FOREIGN KEY (position_id) REFERENCES public.positions(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_position_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_reliever_check" CHECK ((((has_reliever = false) AND (reliever_name IS NULL)) OR ((has_reliever = true) AND (reliever_name IS NOT NULL) AND (btrim(reliever_name) <> ''::text)))) not valid;

alter table "public"."vacancies" validate constraint "vacancies_reliever_check";

alter table "public"."vacancies" add constraint "vacancies_required_headcount_check" CHECK ((required_headcount > 0)) not valid;

alter table "public"."vacancies" validate constraint "vacancies_required_headcount_check";

alter table "public"."vacancies" add constraint "vacancies_source_check" CHECK ((source = ANY (ARRAY['hc_request'::text, 'plantilla'::text, 'manual'::text]))) not valid;

alter table "public"."vacancies" validate constraint "vacancies_source_check";

alter table "public"."vacancies" add constraint "vacancies_source_headcount_request_id_fkey" FOREIGN KEY (source_headcount_request_id) REFERENCES public.headcount_requests(id) ON DELETE SET NULL not valid;

alter table "public"."vacancies" validate constraint "vacancies_source_headcount_request_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_source_plantilla_id_fkey" FOREIGN KEY (source_plantilla_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_source_plantilla_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_source_vacancy_request_id_fkey" FOREIGN KEY (source_vacancy_request_id) REFERENCES public.vacancy_requests(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_source_vacancy_request_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_status_check" CHECK ((status = ANY (ARRAY['Open'::text, 'For Sourcing'::text, 'Filled'::text, 'Backout'::text, 'On Hold'::text, 'Closed'::text, 'Archived'::text]))) not valid;

alter table "public"."vacancies" validate constraint "vacancies_status_check";

alter table "public"."vacancies" add constraint "vacancies_triggered_by_user_id_fkey" FOREIGN KEY (triggered_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."vacancies" validate constraint "vacancies_triggered_by_user_id_fkey";

alter table "public"."vacancies" add constraint "vacancies_urgency_level_check" CHECK ((urgency_level = ANY (ARRAY['High'::text, 'Medium'::text, 'Normal'::text]))) not valid;

alter table "public"."vacancies" validate constraint "vacancies_urgency_level_check";

alter table "public"."vacancies" add constraint "vacancies_vacancy_type_check" CHECK ((vacancy_type = ANY (ARRAY['New'::text, 'Replacement'::text, 'Backfill'::text, 'Additional HC'::text]))) not valid;

alter table "public"."vacancies" validate constraint "vacancies_vacancy_type_check";

alter table "public"."vacancies" add constraint "vacancies_vcode_key" UNIQUE using index "vacancies_vcode_key";

alter table "public"."vacancy_closure_reasons" add constraint "vacancy_closure_reasons_reason_key" UNIQUE using index "vacancy_closure_reasons_reason_key";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_encoder_decision_check" CHECK ((encoder_decision = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text]))) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_encoder_decision_check";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_reason_id_fkey" FOREIGN KEY (reason_id) REFERENCES public.vacancy_closure_reasons(id) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_reason_id_fkey";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_requested_by_user_id_fkey" FOREIGN KEY (requested_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_requested_by_user_id_fkey";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text, 'Withdrawn'::text]))) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_status_check";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_vacancy_vcode_fkey" FOREIGN KEY (vacancy_vcode) REFERENCES public.vacancies(vcode) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_vacancy_vcode_fkey";

alter table "public"."vacancy_closure_requests" add constraint "vacancy_closure_requests_withdrawn_by_user_id_fkey" FOREIGN KEY (withdrawn_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."vacancy_closure_requests" validate constraint "vacancy_closure_requests_withdrawn_by_user_id_fkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_account_id_fkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_applicant_id_fkey" FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_applicant_id_fkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_dates_chk" CHECK (((covered_until IS NULL) OR (covered_until >= covered_from))) not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_dates_chk";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_hr_emploc_id_fkey" FOREIGN KEY (hr_emploc_id) REFERENCES public.hr_emploc(id) not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_hr_emploc_id_fkey";

alter table "public"."vacancy_coverage" add constraint "vacancy_coverage_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) ON DELETE CASCADE not valid;

alter table "public"."vacancy_coverage" validate constraint "vacancy_coverage_vacancy_id_fkey";

alter table "public"."vacancy_requests" add constraint "vacancy_requests_assigned_encoder_id_fkey" FOREIGN KEY (assigned_encoder_id) REFERENCES public.users_profile(id) ON DELETE SET NULL not valid;

alter table "public"."vacancy_requests" validate constraint "vacancy_requests_assigned_encoder_id_fkey";

alter table "public"."vacancy_requests" add constraint "vacancy_requests_requested_by_user_id_fkey" FOREIGN KEY (requested_by_user_id) REFERENCES public.users_profile(id) not valid;

alter table "public"."vacancy_requests" validate constraint "vacancy_requests_requested_by_user_id_fkey";

alter table "public"."vacancy_requests" add constraint "vacancy_requests_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text]))) not valid;

alter table "public"."vacancy_requests" validate constraint "vacancy_requests_status_check";

alter table "public"."vacancy_requests" add constraint "vacancy_requests_urgency_check" CHECK ((urgency = ANY (ARRAY['Urgent'::text, 'Normal'::text]))) not valid;

alter table "public"."vacancy_requests" validate constraint "vacancy_requests_urgency_check";

alter table "public"."vacancy_requests" add constraint "vacancy_requests_vacancy_type_check" CHECK ((vacancy_type = ANY (ARRAY['New'::text, 'Replacement'::text]))) not valid;

alter table "public"."vacancy_requests" validate constraint "vacancy_requests_vacancy_type_check";

alter table "public"."vcodes" add constraint "uq_vcode_scope" UNIQUE using index "uq_vcode_scope";

alter table "public"."vcodes" add constraint "uq_vcode_unique" UNIQUE using index "uq_vcode_unique";

alter table "public"."vcodes" add constraint "vcodes_group_code_check" CHECK ((group_code = ANY (ARRAY['G1'::text, 'G2'::text, 'G3'::text, 'G4'::text, 'G5'::text]))) not valid;

alter table "public"."vcodes" validate constraint "vcodes_group_code_check";

alter table "public"."vcodes" add constraint "vcodes_status_check" CHECK ((status = ANY (ARRAY['available'::text, 'deployed'::text, 'filled'::text]))) not valid;

alter table "public"."vcodes" validate constraint "vcodes_status_check";

alter table "public"."vcodes" add constraint "vcodes_vacancy_request_id_fkey" FOREIGN KEY (vacancy_request_id) REFERENCES public.vacancy_requests(id) not valid;

alter table "public"."vcodes" validate constraint "vcodes_vacancy_request_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "war_date_order" CHECK ((start_date <= end_date)) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "war_date_order";

alter table "public"."workforce_assignment_requests" add constraint "war_status_valid" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text, 'Withdrawn'::text, 'ConvertedToDeployment'::text]))) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "war_status_valid";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_converted_assignment_id_fkey" FOREIGN KEY (converted_assignment_id) REFERENCES public.workforce_assignments(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_converted_assignment_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_employee_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_pool_type_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_requested_account_id_fkey" FOREIGN KEY (requested_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_requested_account_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_requested_by_id_fkey" FOREIGN KEY (requested_by_id) REFERENCES auth.users(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_requested_by_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_requested_group_id_fkey" FOREIGN KEY (requested_group_id) REFERENCES public.groups(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_requested_group_id_fkey";

alter table "public"."workforce_assignment_requests" add constraint "workforce_assignment_requests_requested_store_id_fkey" FOREIGN KEY (requested_store_id) REFERENCES public.stores(id) not valid;

alter table "public"."workforce_assignment_requests" validate constraint "workforce_assignment_requests_requested_store_id_fkey";

alter table "public"."workforce_assignments" add constraint "wa_date_order_chk" CHECK ((start_date <= end_date)) not valid;

alter table "public"."workforce_assignments" validate constraint "wa_date_order_chk";

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

alter table "public"."workforce_assignments" add constraint "workforce_assignments_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Active'::text, 'Completed'::text, 'Rejected'::text, 'Cancelled'::text]))) not valid;

alter table "public"."workforce_assignments" validate constraint "workforce_assignments_status_check";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_employee_id_fkey" FOREIGN KEY (employee_id) REFERENCES public.plantilla(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_employee_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_pool_slot_id_fkey" FOREIGN KEY (pool_slot_id) REFERENCES public.workforce_pool_slots(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_pool_slot_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_pool_type_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_slot_review_id_fkey" FOREIGN KEY (slot_review_id) REFERENCES public.workforce_slot_reviews(id) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_slot_review_id_fkey";

alter table "public"."workforce_pool_conversion_requests" add constraint "workforce_pool_conversion_requests_status_check" CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text, 'Cancelled'::text]))) not valid;

alter table "public"."workforce_pool_conversion_requests" validate constraint "workforce_pool_conversion_requests_status_check";

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

alter table "public"."workforce_pool_request_items" add constraint "wpri_status_values" CHECK ((status = ANY (ARRAY['open'::text, 'filled'::text, 'cancelled'::text]))) not valid;

alter table "public"."workforce_pool_request_items" validate constraint "wpri_status_values";

alter table "public"."workforce_pool_requests" add constraint "workforce_pool_requests_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_pool_requests" validate constraint "workforce_pool_requests_pool_type_id_fkey";

alter table "public"."workforce_pool_requests" add constraint "workforce_pool_requests_requesting_account_id_fkey" FOREIGN KEY (requesting_account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."workforce_pool_requests" validate constraint "workforce_pool_requests_requesting_account_id_fkey";

alter table "public"."workforce_pool_requests" add constraint "workforce_pool_requests_requesting_store_id_fkey" FOREIGN KEY (requesting_store_id) REFERENCES public.stores(id) not valid;

alter table "public"."workforce_pool_requests" validate constraint "workforce_pool_requests_requesting_store_id_fkey";

alter table "public"."workforce_pool_requests" add constraint "wpr_headcount_positive" CHECK ((headcount_needed > 0)) not valid;

alter table "public"."workforce_pool_requests" validate constraint "wpr_headcount_positive";

alter table "public"."workforce_pool_requests" add constraint "wpr_priority_values" CHECK ((priority = ANY (ARRAY['normal'::text, 'urgent'::text, 'critical'::text]))) not valid;

alter table "public"."workforce_pool_requests" validate constraint "wpr_priority_values";

alter table "public"."workforce_pool_requests" add constraint "wpr_status_values" CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'fulfilled'::text, 'cancelled'::text]))) not valid;

alter table "public"."workforce_pool_requests" validate constraint "wpr_status_values";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_account_id_fkey" FOREIGN KEY (account_id) REFERENCES public.accounts(id) not valid;

alter table "public"."workforce_pool_slots" validate constraint "workforce_pool_slots_account_id_fkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_group_id_fkey" FOREIGN KEY (group_id) REFERENCES public.groups(id) not valid;

alter table "public"."workforce_pool_slots" validate constraint "workforce_pool_slots_group_id_fkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_pool_slots" validate constraint "workforce_pool_slots_pool_type_id_fkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."workforce_pool_slots" validate constraint "workforce_pool_slots_vacancy_id_fkey";

alter table "public"."workforce_pool_slots" add constraint "workforce_pool_slots_vcode_key" UNIQUE using index "workforce_pool_slots_vcode_key";

alter table "public"."workforce_pool_slots" add constraint "wps_status_values" CHECK ((status = ANY (ARRAY['open'::text, 'filled'::text, 'under_review'::text, 'closed'::text]))) not valid;

alter table "public"."workforce_pool_slots" validate constraint "wps_status_values";

alter table "public"."workforce_pool_types" add constraint "workforce_pool_types_code_key" UNIQUE using index "workforce_pool_types_code_key";

alter table "public"."workforce_pool_types" add constraint "workforce_pool_types_vcode_prefix_key" UNIQUE using index "workforce_pool_types_vcode_prefix_key";

alter table "public"."workforce_slot_reviews" add constraint "workforce_slot_reviews_pool_type_id_fkey" FOREIGN KEY (pool_type_id) REFERENCES public.workforce_pool_types(id) not valid;

alter table "public"."workforce_slot_reviews" validate constraint "workforce_slot_reviews_pool_type_id_fkey";

alter table "public"."workforce_slot_reviews" add constraint "workforce_slot_reviews_vacancy_id_fkey" FOREIGN KEY (vacancy_id) REFERENCES public.vacancies(id) not valid;

alter table "public"."workforce_slot_reviews" validate constraint "workforce_slot_reviews_vacancy_id_fkey";

alter table "public"."workforce_slot_reviews" add constraint "wsr_action_values" CHECK (((action IS NULL) OR (action = ANY (ARRAY['reopen'::text, 'close'::text])))) not valid;

alter table "public"."workforce_slot_reviews" validate constraint "wsr_action_values";

alter table "public"."workforce_slot_reviews" add constraint "wsr_status_values" CHECK ((status = ANY (ARRAY['pending'::text, 'resolved'::text]))) not valid;

alter table "public"."workforce_slot_reviews" validate constraint "wsr_status_values";

alter table "public"."workforce_slot_reviews" add constraint "wsr_trigger_values" CHECK ((trigger_event = ANY (ARRAY['resignation'::text, 'conversion'::text, 'deactivation'::text]))) not valid;

alter table "public"."workforce_slot_reviews" validate constraint "wsr_trigger_values";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public._apply_separation(p_plantilla_id uuid, p_separation_type text, p_separation_date date, p_remarks text, p_capability text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old plantilla%ROWTYPE;
  v_sep_status text;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, p_capability) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_old FROM public.plantilla WHERE id = p_plantilla_id FOR UPDATE;
  IF v_old.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','plantilla_not_found');
  END IF;
  IF v_old.status <> 'Active' THEN
    RETURN jsonb_build_object('ok',false,'error','only_active_can_be_separated','current_status',v_old.status);
  END IF;

  -- Map UI separation type to allowed separation_status check values
  v_sep_status := CASE p_separation_type
    WHEN 'Resigned'   THEN 'Resigned'
    WHEN 'Endo'       THEN 'Endo'
    WHEN 'AWOL'       THEN 'AWOL'
    WHEN 'Separated'  THEN 'Others'
    WHEN 'Terminated' THEN 'Others'
    ELSE 'Others'
  END;

  UPDATE public.plantilla
  SET status              = 'Inactive',
      inactive_at         = NOW(),
      inactive_by         = public.get_current_profile_id(),
      date_of_separation  = p_separation_date,
      resignation_date    = p_separation_date,
      separation_status   = v_sep_status,
      remarks             = COALESCE(p_remarks, remarks),
      updated_at          = NOW(),
      updated_by          = public.get_current_profile_id()
  WHERE id = p_plantilla_id;

  -- Existing trigger trg_plantilla_separation_to_vacancy fires here
  -- and creates the backfill vacancy reusing the same vcode.

  PERFORM public._log_employee_action(
    p_plantilla_id,
    'SEPARATION_'||UPPER(p_separation_type),
    format('Employee marked %s effective %s', p_separation_type, p_separation_date),
    to_jsonb(v_old),
    jsonb_build_object('separation_type',p_separation_type,'date',p_separation_date,'remarks',p_remarks)
  );

  RETURN jsonb_build_object('ok',true,'plantilla_id',p_plantilla_id,'new_status','Inactive',
                            'separation_status',v_sep_status,'vcode',v_old.vcode);
END$function$
;

CREATE OR REPLACE FUNCTION public._can_act_on_plantilla(p_plantilla_id uuid, p_required_capability text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role     text := public.get_my_role();
  v_account  text;
BEGIN
  IF public.i_have_full_access() THEN RETURN true; END IF;

  SELECT account INTO v_account FROM public.plantilla WHERE id = p_plantilla_id;
  IF v_account IS NULL THEN RETURN false; END IF;
  IF NOT (v_account = ANY (public.get_my_allowed_accounts())) THEN RETURN false; END IF;

  RETURN CASE p_required_capability
    WHEN 'reassign'      THEN v_role IN ('OM','HRCO','ATL','TL','Operations Manager')
    WHEN 'resign'        THEN v_role IN ('OM','HRCO','ATL','TL','Operations Manager')
    WHEN 'endo'          THEN v_role IN ('OM','HRCO','ATL','TL','Operations Manager')
    WHEN 'separate'      THEN v_role IN ('OM','HRCO','ATL','TL','Operations Manager')
    WHEN 'request_deact' THEN v_role IN ('OM','HRCO','ATL','TL','Operations Manager')
    WHEN 'complete_deact'THEN v_role IN ('Back Office','Backoffice','Super Admin','Head Admin')
    WHEN 'mika_sync'     THEN v_role IN ('OM','HRCO','ATL','TL','Operations Manager','Back Office','Backoffice','Super Admin','Head Admin')
    ELSE false
  END;
END$function$
;

CREATE OR REPLACE FUNCTION public._log_employee_action(p_plantilla_id uuid, p_action_type text, p_description text, p_old jsonb DEFAULT NULL::jsonb, p_new jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_emploc text; v_vcode text;
BEGIN
  SELECT emploc_no, vcode INTO v_emploc, v_vcode FROM public.plantilla WHERE id = p_plantilla_id;

  INSERT INTO public.employee_activity_log
    (emploc_no, vcode, activity_type, description, performed_by, metadata)
  VALUES
    (COALESCE(v_emploc,'(no-emploc)'), v_vcode, p_action_type, p_description,
     public.get_my_full_name(),
     jsonb_build_object('plantilla_id', p_plantilla_id, 'role', public.get_my_role(),
                        'old', p_old, 'new', p_new));

  PERFORM public.log_audit_event('Plantilla', 'UPDATE', p_plantilla_id, p_old, p_new);
END$function$
;

CREATE OR REPLACE FUNCTION public.acquire_qa_run_lock(p_queue_id uuid, p_lock_minutes integer DEFAULT 30)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_queue public.qa_run_queue%rowtype;
  v_run_id uuid;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can acquire QA run locks';
  end if;

  select * into v_queue
  from public.qa_run_queue
  where id = p_queue_id
  for update;

  if v_queue.id is null then
    raise exception 'QA queue item not found';
  end if;

  if v_queue.queue_status not in ('queued','blocked') then
    raise exception 'QA queue item is not available for lock';
  end if;

  v_run_id := public.qa_start_detection_run(
    'QA_DETECTION_ENGINE',
    v_queue.suite_name,
    jsonb_build_object('queue_id', v_queue.id, 'environment', v_queue.environment, 'scheduled', true)
  );

  update public.qa_run_queue
  set queue_status = 'running',
      run_id = v_run_id,
      locked_at = now(),
      lock_expires_at = now() + make_interval(mins => greatest(coalesce(p_lock_minutes, 30), 1)),
      started_at = now()
  where id = p_queue_id;

  return v_run_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.activate_workforce_assignment(p_assignment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_name    TEXT;
  v_current_status TEXT;
BEGIN
  IF NOT (get_my_role_level() = ANY (ARRAY[100, 90, 30]) OR i_have_full_access()) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;

  SELECT status INTO v_current_status
  FROM workforce_assignments WHERE id = p_assignment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Assignment not found.';
  END IF;
  IF v_current_status NOT IN ('Pending','Approved') THEN
    RAISE EXCEPTION 'Cannot activate: assignment is currently %. Expected Pending or Approved.', v_current_status;
  END IF;

  v_caller_name := get_my_full_name();

  UPDATE workforce_assignments SET
    status      = 'Active',
    approved_by = v_caller_name,
    approved_at = now(),
    updated_at  = now(),
    updated_by  = v_caller_name
  WHERE id = p_assignment_id;
END;
$function$
;

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

CREATE OR REPLACE FUNCTION public.admin_terminate_session(p_session_id uuid, p_target_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level    INT;
  v_actor_id UUID := auth.uid();
BEGIN
  -- ── Auth: Super Admin only ────────────────────────────────────────────────
  SELECT r.role_level
    INTO v_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = v_actor_id;

  IF COALESCE(v_level, 0) < 100 THEN
    RAISE EXCEPTION 'unauthorized: session termination requires Super Admin'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: session must exist and be active ───────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.user_sessions
     WHERE id = p_session_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'session not found or already inactive: %', p_session_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Terminate session ─────────────────────────────────────────────────────
  UPDATE public.user_sessions
     SET is_active = FALSE,
         logout_at = NOW()
   WHERE id = p_session_id;

  -- ── Log security event (inline — atomic with session update) ─────────────
  INSERT INTO public.security_events (
    event_type, severity, actor_id, target_id, action, details, happened_at
  ) VALUES (
    'session_terminated',
    'medium',
    v_actor_id,
    p_target_user_id,
    'Admin force-terminated session',
    jsonb_build_object('session_id', p_session_id, 'reason', 'admin_action'),
    NOW()
  );

  -- ── Audit ────────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, new_data)
  VALUES (
    v_actor_id,
    'Security',
    'TERMINATE_SESSION',
    p_session_id,
    jsonb_build_object(
      'session_id', p_session_id,
      'target_user_id', p_target_user_id,
      'terminated_by', v_actor_id
    )
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.approve_account_request(p_request_id uuid, p_group_id uuid, p_role_id uuid, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_request          public.account_requests%ROWTYPE;
  v_role_name        TEXT;
  v_caller_level     INT;
  v_requires_account BOOLEAN;
  v_resolved_account UUID;
  v_profile_id       UUID;
BEGIN
  -- Authorize: caller must be role_level >= 90 (SA / HA)
  SELECT r.role_level INTO v_caller_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- Lock request
  SELECT * INTO v_request
  FROM public.account_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request not found: %', p_request_id USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'pending'::account_request_status THEN
    RAISE EXCEPTION 'request already processed (status=%)', v_request.status
      USING ERRCODE = '22023';
  END IF;

  IF v_request.auth_user_id IS NULL THEN
    RAISE EXCEPTION 'request missing auth_user_id' USING ERRCODE = '23502';
  END IF;

  -- Resolve role + tagging rule
  SELECT role_name INTO v_role_name FROM public.roles WHERE id = p_role_id;
  IF v_role_name IS NULL THEN
    RAISE EXCEPTION 'role not found: %', p_role_id USING ERRCODE = 'P0002';
  END IF;

  v_requires_account := UPPER(v_role_name) IN ('ATL', 'TL', 'HRCO');

  IF v_requires_account THEN
    IF p_account_id IS NULL THEN
      RAISE EXCEPTION 'role % requires account_id assignment', v_role_name
        USING ERRCODE = '23502';
    END IF;
    v_resolved_account := p_account_id;
  ELSE
    -- Group-wide visibility for Encoder / OM / Recruitment / Viewer / etc.
    v_resolved_account := NULL;
  END IF;

  -- Upsert users_profile (tag with group_id, role_id, account_id)
  INSERT INTO public.users_profile (
    auth_user_id, full_name, email,
    role_id, group_id, account_id, is_active
  )
  VALUES (
    v_request.auth_user_id,
    v_request.full_name,
    v_request.email,
    p_role_id,
    p_group_id,
    v_resolved_account,
    TRUE
  )
  ON CONFLICT (auth_user_id) DO UPDATE SET
    role_id    = EXCLUDED.role_id,
    group_id   = EXCLUDED.group_id,
    account_id = EXCLUDED.account_id,
    is_active  = TRUE
  RETURNING id INTO v_profile_id;

  -- Mark request approved
  UPDATE public.account_requests
  SET status      = 'approved'::account_request_status,
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      updated_at  = NOW()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success',      TRUE,
    'request_id',   p_request_id,
    'profile_id',   v_profile_id,
    'auth_user_id', v_request.auth_user_id,
    'role',         v_role_name,
    'group_id',     p_group_id,
    'account_id',   v_resolved_account,
    'scope',        CASE WHEN v_resolved_account IS NULL THEN 'group_wide' ELSE 'account_scoped' END
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.approve_account_request_v2(p_request_id uuid, p_role_id uuid, p_scope_type text, p_group_ids uuid[] DEFAULT ARRAY[]::uuid[], p_account_ids uuid[] DEFAULT ARRAY[]::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
    v_request public.account_requests%ROWTYPE;
    v_profile_id uuid;
    v_role_name text;
    v_caller_role_level int;
    v_gid uuid;
    v_aid uuid;
    v_invalid_account_count int;
BEGIN
    -- Authorize approver
    SELECT r.role_level
    INTO v_caller_role_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
    WHERE up.auth_user_id = auth.uid();

    IF COALESCE(v_caller_role_level, 0) < 90 THEN
        RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
            USING ERRCODE = '42501';
    END IF;

    IF p_scope_type NOT IN ('global', 'scoped', 'custom') THEN
        RAISE EXCEPTION 'invalid scope_type: %', p_scope_type
            USING ERRCODE = '22023';
    END IF;

    IF p_scope_type = 'global' AND v_caller_role_level < 90 THEN
        RAISE EXCEPTION 'only Head Admin or Super Admin may assign global scope'
            USING ERRCODE = '42501';
    END IF;

    IF p_scope_type = 'scoped' AND COALESCE(array_length(p_group_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION 'scoped access requires at least one group'
            USING ERRCODE = '22023';
    END IF;

    SELECT COUNT(*)
    INTO v_invalid_account_count
    FROM public.accounts a
    WHERE a.id = ANY(p_account_ids)
      AND NOT (a.group_id = ANY(p_group_ids));

    IF v_invalid_account_count > 0 THEN
        RAISE EXCEPTION 'one or more accounts do not belong to selected groups'
            USING ERRCODE = '22023';
    END IF;

    SELECT role_name
    INTO v_role_name
    FROM public.roles
    WHERE id = p_role_id;

    IF v_role_name IS NULL THEN
        RAISE EXCEPTION 'role not found'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT *
    INTO v_request
    FROM public.account_requests
    WHERE id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account request not found'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_request.status <> 'pending'::account_request_status THEN
        RAISE EXCEPTION 'request already processed'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.users_profile (
        auth_user_id,
        full_name,
        email,
        role_id,
        is_active
    )
    VALUES (
        v_request.auth_user_id,
        v_request.full_name,
        v_request.email,
        p_role_id,
        true
    )
    ON CONFLICT (auth_user_id)
    DO UPDATE SET
        role_id = EXCLUDED.role_id,
        is_active = true,
        updated_at = now()
    RETURNING id INTO v_profile_id;

    DELETE FROM public.user_scopes
    WHERE user_id = v_profile_id;

    IF p_scope_type <> 'global' THEN
        FOREACH v_gid IN ARRAY p_group_ids LOOP
            INSERT INTO public.user_scopes (
                user_id,
                group_id,
                account_id
            )
            VALUES (
                v_profile_id,
                v_gid,
                NULL
            )
            ON CONFLICT DO NOTHING;
        END LOOP;

        FOREACH v_aid IN ARRAY p_account_ids LOOP
            INSERT INTO public.user_scopes (
                user_id,
                group_id,
                account_id
            )
            SELECT
                v_profile_id,
                a.group_id,
                a.id
            FROM public.accounts a
            WHERE a.id = v_aid
            ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;

    DELETE FROM public.account_request_group_scopes
    WHERE account_request_id = p_request_id;

    DELETE FROM public.account_request_account_scopes
    WHERE account_request_id = p_request_id;

    FOREACH v_gid IN ARRAY p_group_ids LOOP
        INSERT INTO public.account_request_group_scopes (
            account_request_id,
            group_id
        )
        VALUES (
            p_request_id,
            v_gid
        )
        ON CONFLICT DO NOTHING;
    END LOOP;

    FOREACH v_aid IN ARRAY p_account_ids LOOP
        INSERT INTO public.account_request_account_scopes (
            account_request_id,
            account_id
        )
        VALUES (
            p_request_id,
            v_aid
        )
        ON CONFLICT DO NOTHING;
    END LOOP;

    UPDATE public.account_requests
    SET
        status = 'approved'::account_request_status,
        approved_by = auth.uid(),
        approved_at = now(),
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        assigned_role_id = p_role_id,
        assigned_scope_type = p_scope_type,
        assigned_groups_snapshot = to_jsonb(p_group_ids),
        assigned_accounts_snapshot = to_jsonb(p_account_ids),
        updated_at = now()
    WHERE id = p_request_id;

    RETURN jsonb_build_object(
        'success', true,
        'request_id', p_request_id,
        'profile_id', v_profile_id,
        'scope_type', p_scope_type,
        'group_count', COALESCE(array_length(p_group_ids, 1), 0),
        'account_count', COALESCE(array_length(p_account_ids, 1), 0)
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.approve_all_vacancy_requests(p_request_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS TABLE(approved_count integer, skipped_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text := public.get_my_role();
  v_profile_id uuid := public.get_current_profile_id();
  v_has_temp boolean;
  v_approved int := 0;
  v_total_candidates int := 0;
begin
  select exists (
    select 1
    from public.temp_approval_access t
    where t.granted_to = v_profile_id
      and t.module = 'vacancy_approval'
      and t.valid_until > now()
      and t.revoked_at is null
  ) into v_has_temp;

  if not (
    public.i_have_full_access()
    or v_role in ('OM', 'Operations Manager')
    or v_has_temp
  ) then
    raise exception 'Access denied: only OM, designated approvers, Head Admin, or Super Admin can bulk approve.';
  end if;

  -- Count only requests the caller is actually authorized to affect.
  select count(*)
  into v_total_candidates
  from public.vacancy_requests vr
  where vr.status = 'Pending'
    and (p_request_ids is null or vr.id = any(p_request_ids))
    and (
      public.i_have_full_access()
      or vr.account = any(public.get_my_allowed_accounts())
    );

  with updated as (
    update public.vacancy_requests vr
    set status = 'Approved',
        reviewed_by = public.get_my_full_name(),
        reviewed_at = now(),
        updated_at = now()
    where vr.status = 'Pending'
      and (p_request_ids is null or vr.id = any(p_request_ids))
      and (
        public.i_have_full_access()
        or vr.account = any(public.get_my_allowed_accounts())
      )
    returning vr.id
  )
  select count(*) into v_approved from updated;

  if p_request_ids is null then
    approved_count := v_approved;
    skipped_count := 0;
  else
    approved_count := v_approved;
    skipped_count := greatest(array_length(p_request_ids, 1) - v_approved, 0);
  end if;

  return next;
end;
$function$
;

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

CREATE OR REPLACE FUNCTION public.approve_headcount_request(p_request_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_req headcount_requests%ROWTYPE;
begin
  if not public.i_have_full_access() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select * into v_req from public.headcount_requests where id = p_request_id for update;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_req.status not in ('pending', 'under_review') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status_transition', 'current', v_req.status);
  end if;

  update public.headcount_requests
  set status                         = 'approved_pending_vcode',
      head_admin_approved_by_user_id = public.get_current_profile_id(),
      head_admin_approved_by_name    = public.get_my_full_name(),
      head_admin_approved_at         = now(),
      head_admin_remarks             = p_remarks
  where id = p_request_id;

  return jsonb_build_object(
    'ok',         true,
    'request_id', p_request_id,
    'status',     'approved_pending_vcode'
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.approve_plantilla_request(p_approval_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level       INT;
  v_reviewer    TEXT;
  v_appr_rec    RECORD;
  v_hr_emploc   RECORD;
  v_result      jsonb;
BEGIN
  -- ── Auth: Data Team (encoder level 30+) or higher ────────────────────────
  SELECT r.role_level, up.full_name
    INTO v_level, v_reviewer
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_level, 0) < 30 THEN
    RAISE EXCEPTION 'unauthorized: requires Data Team or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch & lock approval record ─────────────────────────────────────────
  SELECT id, applicant_name, vcode, account, status, hr_emploc_id
    INTO v_appr_rec
    FROM public.plantilla_approvals
   WHERE id = p_approval_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval record not found: %', p_approval_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_appr_rec.status <> 'Pending' THEN
    RAISE EXCEPTION 'approval already processed (status=%)', v_appr_rec.status
      USING ERRCODE = '22023';
  END IF;

  -- ── Locate hr_emploc — try UUID first (new records), then name+vcode ─────
  BEGIN
    SELECT id INTO v_hr_emploc
      FROM public.hr_emploc
     WHERE id = v_appr_rec.hr_emploc_id::UUID
     LIMIT 1;
  EXCEPTION WHEN invalid_text_representation THEN
    v_hr_emploc := NULL;
  END;

  IF v_hr_emploc.id IS NULL THEN
    -- Fallback for legacy records that stored name_vcode instead of UUID
    SELECT id INTO v_hr_emploc
      FROM public.hr_emploc
     WHERE applicant_name = v_appr_rec.applicant_name
       AND vcode = v_appr_rec.vcode
     LIMIT 1;
  END IF;

  IF v_hr_emploc.id IS NULL THEN
    RAISE EXCEPTION 'no hr_emploc record found for approval % (name=%, vcode=%)',
      p_approval_id, v_appr_rec.applicant_name, v_appr_rec.vcode
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Update approval status ───────────────────────────────────────────────
  UPDATE public.plantilla_approvals
     SET status      = 'Approved',
         reviewed_by = v_reviewer,
         reviewed_at = NOW()
   WHERE id = p_approval_id;

  -- ── Move to Plantilla via existing RPC (preserves all existing logic) ────
  SELECT public.move_to_plantilla(v_hr_emploc.id) INTO v_result;

  -- ── Audit ────────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'Plantilla',
    'APPROVE_PLANTILLA',
    p_approval_id,
    jsonb_build_object('status', 'Pending'),
    jsonb_build_object(
      'status', 'Approved',
      'reviewed_by', v_reviewer,
      'hr_emploc_id', v_hr_emploc.id,
      'plantilla_result', v_result
    )
  );

  RETURN jsonb_build_object(
    'approval_id',  p_approval_id,
    'hr_emploc_id', v_hr_emploc.id,
    'status',       'Approved',
    'reviewed_by',  v_reviewer,
    'plantilla',    v_result
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.approve_pool_conversion(p_request_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request public.workforce_pool_conversion_requests%rowtype;
  v_employee_old public.plantilla%rowtype;
  v_employee_new public.plantilla%rowtype;
  v_slot public.workforce_pool_slots%rowtype;
  v_closed integer := 0;
  v_cancelled integer := 0;
  v_slot_review_id uuid;
  v_actor uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
BEGIN
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team approval required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request
  FROM public.workforce_pool_conversion_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  IF v_request.status <> 'Pending' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'invalid_status',
      'current', v_request.status
    );
  END IF;

  SELECT * INTO v_employee_old
  FROM public.plantilla
  WHERE id = v_request.employee_id
  FOR UPDATE;

  IF v_employee_old.id IS NULL OR COALESCE(v_employee_old.is_deleted, false) THEN
    RAISE EXCEPTION 'pool employee not found' USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_employee_old.is_pool_employee, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'employee is no longer a pool employee'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_slot
  FROM public.workforce_pool_slots
  WHERE id = v_request.pool_slot_id
     OR (v_request.pool_slot_id IS NULL AND vcode = v_request.vcode AND deleted_at IS NULL)
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  UPDATE public.workforce_assignments
  SET status = 'Completed',
      end_date = LEAST(end_date, v_request.effective_date),
      completed_at = now(),
      updated_at = now(),
      updated_by = v_actor,
      notes = CONCAT_WS(
        E'\n',
        NULLIF(notes, ''),
        'Closed automatically by pool conversion approval ' || v_request.id::text
      )
  WHERE employee_id = v_request.employee_id
    AND lower(COALESCE(status, '')) IN ('active', 'approved', 'deployed');
  GET DIAGNOSTICS v_closed = ROW_COUNT;

  UPDATE public.workforce_assignment_requests
  SET status = 'Cancelled',
      rejection_reason = COALESCE(
        rejection_reason,
        'Cancelled automatically because employee was converted to regular plantilla.'
      ),
      reviewed_at = now(),
      reviewed_by = v_actor_name,
      updated_at = now()
  WHERE employee_id = v_request.employee_id
    AND lower(COALESCE(status, '')) IN ('pending', 'for review');
  GET DIAGNOSTICS v_cancelled = ROW_COUNT;

  INSERT INTO public.workforce_slot_reviews (
    pool_type_id,
    vacancy_id,
    vcode,
    previous_employee_id,
    trigger_event,
    status,
    review_notes,
    created_by,
    created_at
  )
  VALUES (
    COALESCE(v_request.pool_type_id, v_slot.pool_type_id),
    v_slot.vacancy_id,
    COALESCE(v_request.vcode, v_slot.vcode, v_employee_old.vcode),
    v_request.employee_id,
    'pool_conversion',
    'Pending',
    'Pool employee converted to regular plantilla. Data Team must reopen VCODE or close slot.',
    v_actor,
    now()
  )
  RETURNING id INTO v_slot_review_id;

  IF v_slot.id IS NOT NULL THEN
    UPDATE public.workforce_pool_slots
    SET status = 'review',
        is_active = false,
        updated_at = now(),
        updated_by = v_actor
    WHERE id = v_slot.id;
  END IF;

  UPDATE public.plantilla
  SET account = v_request.target_account,
      account_id = v_request.target_account_id,
      store_id = v_request.target_store_id,
      store_name = v_request.target_store,
      position = v_request.target_position,
      is_pool_employee = false,
      pool_type_id = NULL,
      vcode = NULL,
      deployment_type = COALESCE(NULLIF(deployment_type, 'Pool'), 'Stationary'),
      transferred_from_store_id = v_employee_old.store_id,
      last_transfer_at = now(),
      last_transfer_by = v_actor,
      remarks = CONCAT_WS(
        E'\n',
        NULLIF(remarks, ''),
        'Converted from Moses HQ Workforce Pool effective '
          || v_request.effective_date::text
          || '. Previous VCODE: '
          || COALESCE(v_request.vcode, v_employee_old.vcode, '-')
      ),
      updated_at = now(),
      updated_by = v_actor
  WHERE id = v_request.employee_id
  RETURNING * INTO v_employee_new;

  UPDATE public.workforce_pool_conversion_requests
  SET status = 'Approved',
      approved_by = v_actor,
      approved_by_name = v_actor_name,
      approved_at = now(),
      notes = COALESCE(NULLIF(BTRIM(p_notes), ''), notes),
      active_assignments_closed = v_closed,
      pending_requests_cancelled = v_cancelled,
      slot_review_id = v_slot_review_id,
      updated_at = now()
  WHERE id = v_request.id;

  PERFORM public.log_audit_event(
    'plantilla',
    'UPDATE',
    v_employee_new.id,
    to_jsonb(v_employee_old),
    to_jsonb(v_employee_new)
  );

  PERFORM public.log_audit_event(
    'workforce_pool_conversion',
    'APPROVAL',
    v_request.id,
    to_jsonb(v_request),
    to_jsonb((SELECT r FROM public.workforce_pool_conversion_requests r WHERE r.id = v_request.id))
  );

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', v_request.id,
    'employee_id', v_request.employee_id,
    'employee_no', v_employee_new.employee_no,
    'status', 'Approved',
    'assignment_closures', v_closed,
    'pending_requests_cancelled', v_cancelled,
    'slot_review_id', v_slot_review_id
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.approve_reliever_coverage_request(p_request_id uuid, p_assigned_employee_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(request_id uuid, assignment_id uuid, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_req           RECORD;
  v_final_emp_id  UUID;
  v_new_assign_id UUID;
  v_caller_name   TEXT;
BEGIN
  -- Data Team / Head Admin / Super Admin only
  IF NOT (
    get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;

  SELECT * INTO v_req
  FROM workforce_assignment_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;
  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'Only Pending requests can be approved. Current status: %', v_req.status;
  END IF;

  v_final_emp_id := COALESCE(p_assigned_employee_id, v_req.employee_id);

  -- Active check
  IF NOT EXISTS (
    SELECT 1 FROM plantilla
    WHERE id = v_final_emp_id
      AND is_deleted = false
      AND deactivated_at IS NULL
      AND status = 'Active'
  ) THEN
    RAISE EXCEPTION 'Assigned employee not found or inactive.';
  END IF;

  -- Pool enrollment check
  IF NOT EXISTS (
    SELECT 1
    FROM workforce_pool_slots wps
    JOIN plantilla pt ON pt.vcode = wps.vcode
    WHERE pt.id = v_final_emp_id
      AND wps.is_active = true
      AND wps.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Assigned employee is not enrolled in workforce pool.';
  END IF;

  -- Group visibility check on override employee
  IF p_assigned_employee_id IS NOT NULL AND p_assigned_employee_id <> v_req.employee_id THEN
    IF NOT EXISTS (
      SELECT 1
      FROM workforce_pool_slots wps
      JOIN plantilla pt ON pt.vcode = wps.vcode
      WHERE pt.id = v_final_emp_id
        AND wps.is_active = true
        AND wps.deleted_at IS NULL
        AND (
          wps.group_id IS NULL
          OR wps.group_id = (
            SELECT wps2.group_id
            FROM workforce_pool_slots wps2
            JOIN plantilla pt2 ON pt2.vcode = wps2.vcode
            WHERE pt2.id = v_req.employee_id
              AND wps2.is_active = true
              AND wps2.deleted_at IS NULL
            LIMIT 1
          )
        )
    ) THEN
      RAISE EXCEPTION 'Override employee is not globally visible or not in the same group as the original request.';
    END IF;
  END IF;

  v_caller_name := get_my_full_name();

  INSERT INTO workforce_assignments (
    employee_id, pool_type_id,
    assigned_group_id, assigned_account_id, assigned_store_id,
    priority, start_date, end_date,
    status, requested_by, approved_by, approved_at,
    notes, created_at, created_by, updated_at, updated_by
  ) VALUES (
    v_final_emp_id, v_req.pool_type_id,
    v_req.requested_group_id, v_req.requested_account_id, v_req.requested_store_id,
    v_req.priority, v_req.start_date, v_req.end_date,
    'Approved', v_req.requested_by, v_caller_name, now(),
    COALESCE(p_notes, v_req.notes),
    now(), v_caller_name, now(), v_caller_name
  )
  RETURNING id INTO v_new_assign_id;

  UPDATE workforce_assignment_requests
  SET
    status                  = 'ConvertedToDeployment',
    converted_assignment_id = v_new_assign_id,
    reviewed_by             = v_caller_name,
    reviewed_at             = now(),
    notes                   = COALESCE(p_notes, notes),
    updated_at              = now()
  WHERE id = p_request_id;

  RETURN QUERY
  SELECT
    p_request_id,
    v_new_assign_id,
    'ConvertedToDeployment'::TEXT,
    'Request approved. Workforce assignment created.'::TEXT;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.approve_store_import_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_batch  public.store_import_batches%ROWTYPE;
  v_inserted int := 0;
  v_updated  int := 0;
  v_row    record;
  v_existing uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: super admin only';
  END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)', v_batch.status;
  END IF;
  IF v_batch.invalid_rows > 0 THEN
    RAISE EXCEPTION 'INVALID_STATE: batch contains invalid rows';
  END IF;

  FOR v_row IN
    SELECT * FROM public.store_import_rows
     WHERE batch_id = p_batch_id AND validation_status = 'valid'
     ORDER BY row_number
  LOOP
    SELECT id INTO v_existing FROM public.stores
      WHERE lower(vcode) = lower(v_row.vcode) AND status='active' LIMIT 1;

    IF v_existing IS NULL THEN
      INSERT INTO public.stores (
        vcode, store_name, area_province, area_city, type, with_penalty,
        group_id, account_id, status, created_by, updated_by,
        approved_by, approved_at, source_import_id
      ) VALUES (
        v_row.vcode, v_row.store_name, v_row.area_province, v_row.area_city,
        v_row.type, v_row.with_penalty,
        v_batch.selected_group_id, v_batch.selected_account_id, 'active',
        v_uid, v_uid, v_uid, now(), p_batch_id
      ) RETURNING id INTO v_existing;
      v_inserted := v_inserted + 1;

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'stores', 'INSERT', v_existing,
              jsonb_build_object('vcode', v_row.vcode, 'source_import_id', p_batch_id));
    ELSE
      UPDATE public.stores
         SET store_name       = v_row.store_name,
             area_province    = v_row.area_province,
             area_city        = v_row.area_city,
             type             = v_row.type,
             with_penalty     = v_row.with_penalty,
             group_id         = v_batch.selected_group_id,
             account_id       = v_batch.selected_account_id,
             status           = 'active',
             updated_by       = v_uid,
             approved_by      = v_uid,
             approved_at      = now(),
             source_import_id = p_batch_id
       WHERE id = v_existing;
      v_updated := v_updated + 1;

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'stores', 'UPDATE', v_existing,
              jsonb_build_object('vcode', v_row.vcode, 'source_import_id', p_batch_id));
    END IF;
  END LOOP;

  UPDATE public.store_import_batches
     SET status='approved', approved_by=v_uid, approved_at=now(), updated_at=now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'store_import_batches', 'APPROVAL', p_batch_id,
          jsonb_build_object('inserted', v_inserted, 'updated', v_updated));

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'status', 'approved',
    'inserted', v_inserted,
    'updated', v_updated
  );
END$function$
;

CREATE OR REPLACE FUNCTION public.approve_transfer_request(p_transfer_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_transfer public.employee_transfers%rowtype;
  v_role text := public.get_my_role();
begin
  select * into v_transfer
  from public.employee_transfers
  where id = p_transfer_id
  for update;

  if v_transfer.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_transfer.status <> 'Pending' then
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'current', v_transfer.status);
  end if;

  if not (v_role in ('Encoder','Head Admin','Super Admin')) then
    return jsonb_build_object('ok', false, 'error', 'approval_role_required');
  end if;

  update public.employee_transfers
  set status = 'Approved',
      reviewed_by = public.get_my_full_name(),
      approved_by_user_id = auth.uid(),
      updated_at = now()
  where id = p_transfer_id;

  return jsonb_build_object(
    'ok', true,
    'transfer_id', p_transfer_id,
    'status', 'Approved'
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.approve_vacancy_request_auto_vcodes(p_request_id uuid, p_reviewer_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role text := public.get_my_role();
  v_role_level int := COALESCE(public.get_my_role_level(), 0);
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
  v_request public.vacancy_requests%ROWTYPE;
  v_old jsonb;
  v_slots int;
  v_existing_vcodes int;
  v_generated jsonb := '[]'::jsonb;
  v_vcode text;
  v_vcodes text[];
  v_vacancy_ids uuid[];
  v_vacancy_id uuid;
  v_already_approved boolean;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('Encoder')
  ) THEN
    RAISE EXCEPTION 'forbidden: Super Admin, Head Admin, or Encoder required'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
    INTO v_request
    FROM public.vacancy_requests
   WHERE id = p_request_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'vacancy request % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_request.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy request is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_request.status, 'Pending') = 'Rejected' THEN
    RAISE EXCEPTION 'cannot approve rejected vacancy request %', p_request_id
      USING ERRCODE = '22023';
  END IF;

  IF COALESCE(v_request.status, 'Pending') NOT IN ('Pending', 'Approved') THEN
    RAISE EXCEPTION 'cannot approve vacancy request % from status %', p_request_id, v_request.status
      USING ERRCODE = '22023';
  END IF;

  v_already_approved := COALESCE(v_request.status, 'Pending') = 'Approved';

  v_slots := COALESCE(v_request.no_of_slots, 1);
  IF v_slots < 1 THEN
    RAISE EXCEPTION 'vacancy request % has invalid no_of_slots %', p_request_id, v_request.no_of_slots
      USING ERRCODE = '22023';
  END IF;

  SELECT COUNT(*)
    INTO v_existing_vcodes
    FROM public.vcodes
   WHERE vacancy_request_id = p_request_id;

  IF v_existing_vcodes = 0 THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY g.sequence_num), '[]'::jsonb)
      INTO v_generated
      FROM public.generate_vcodes_from_request(p_request_id) AS g;
  ELSIF v_existing_vcodes <> v_slots THEN
    RAISE EXCEPTION 'unexpected VCode count detected for request % (%/%). Resolve before approval.',
      p_request_id, v_existing_vcodes, v_slots
      USING ERRCODE = '23505';
  END IF;

  SELECT ARRAY_AGG(v.vcode ORDER BY v.sequence_number)
    INTO v_vcodes
    FROM public.vcodes v
   WHERE v.vacancy_request_id = p_request_id;

  IF COALESCE(array_length(v_vcodes, 1), 0) < v_slots THEN
    RAISE EXCEPTION 'VCode generation failed for request %', p_request_id
      USING ERRCODE = '23505';
  END IF;

  IF NOT v_already_approved THEN
    v_old := to_jsonb(v_request);

    UPDATE public.vacancy_requests
       SET status = 'Approved',
           reviewed_by = v_actor_name,
           reviewed_at = NOW(),
           reviewer_remarks = p_reviewer_remarks,
           vcode_created = v_vcodes[1],
           updated_at = NOW()
     WHERE id = p_request_id
     RETURNING * INTO v_request;
  END IF;

  FOREACH v_vcode IN ARRAY v_vcodes LOOP
    INSERT INTO public.vacancies (
      vcode,
      account,
      position,
      status,
      vacancy_type,
      store_name,
      vacant_date,
      required_headcount,
      has_penalty,
      is_archived,
      has_pending_closure
    ) VALUES (
      v_vcode,
      v_request.account,
      v_request.position,
      'Open',
      v_request.vacancy_type,
      v_request.store_name,
      v_request.date_needed,
      1,
      COALESCE(v_request.has_penalty, false),
      false,
      false
    )
    ON CONFLICT (vcode) DO UPDATE
      SET updated_at = NOW()
      WHERE public.vacancies.status = 'Open'
        AND COALESCE(public.vacancies.is_archived, false) = false
        AND public.vacancies.deleted_at IS NULL
    RETURNING id INTO v_vacancy_id;

    IF v_vacancy_id IS NULL THEN
      SELECT id INTO v_vacancy_id
        FROM public.vacancies
       WHERE vcode = v_vcode
         AND status = 'Open'
         AND COALESCE(is_archived, false) = false
         AND deleted_at IS NULL;
    END IF;

    IF v_vacancy_id IS NULL THEN
      RAISE EXCEPTION 'active vacancy could not be created or reused for VCode %', v_vcode
        USING ERRCODE = '23505';
    END IF;

    v_vacancy_ids := array_append(v_vacancy_ids, v_vacancy_id);
  END LOOP;

  IF NOT v_already_approved THEN
    PERFORM public.log_audit_event(
      'Vacancy.Request',
      'APPROVAL',
      p_request_id,
      v_old,
      jsonb_build_object(
        'status', 'Approved',
        'reviewed_by', v_actor_name,
        'reviewed_by_profile_id', v_profile_id,
        'reviewer_remarks', p_reviewer_remarks,
        'vcodes', v_vcodes,
        'vacancy_ids', v_vacancy_ids,
        'business_action', 'APPROVE_VACANCY_REQUEST_AUTO_VCODES'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'status', 'Approved',
    'reviewed_by', v_request.reviewed_by,
    'reviewed_at', v_request.reviewed_at,
    'vcodes', v_vcodes,
    'vcode_created', v_vcodes[1],
    'vacancy_ids', v_vacancy_ids,
    'generated', v_generated,
    'already_approved', v_already_approved
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.archive_expired_qa_runs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_expired_queue int := 0;
  v_archived_notifications int := 0;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can archive QA records';
  end if;

  update public.qa_run_queue
  set queue_status = 'expired',
      completed_at = now(),
      locked_at = null,
      lock_expires_at = null,
      error_message = coalesce(error_message, 'Queue lock expired')
  where queue_status = 'running'
    and lock_expires_at is not null
    and lock_expires_at < now();

  get diagnostics v_expired_queue = row_count;

  update public.qa_notifications
  set archived_at = now()
  where archived_at is null
    and created_at < now() - interval '30 days';

  get diagnostics v_archived_notifications = row_count;

  return jsonb_build_object('expired_queue_items', v_expired_queue, 'archived_notifications', v_archived_notifications);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.archive_vacancy_on_closure_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- When status changes to Approved
  IF NEW.status = 'Approved' AND OLD.status != 'Approved' THEN
    -- Archive the vacancy
    UPDATE public.vacancies
    SET
      status = 'Closed',
      archived_at = now(),
      archived_by = NEW.reviewed_by
    WHERE vcode = NEW.vacancy_vcode;
  END IF;
  RETURN NEW;
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

CREATE OR REPLACE FUNCTION public.auto_resolve_ghost_if_in_plantilla()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.possible_ghost_employees
  SET status = 'Cleared',
      resolved_at = now(),
      resolution_remarks = 'Auto-resolved: Employee found in Plantilla'
  WHERE employee_no = NEW.employee_no
    AND status IN ('Pending', 'Under Investigation');
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.build_deep_link(p_reference_type text, p_reference_id text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_reference_type
    WHEN 'vacancy_request'         THEN '/vacancy-requests/'         || p_reference_id
    WHEN 'vacancy_closure'         THEN '/vacancy-closure-requests/' || p_reference_id
    WHEN 'vacancy_closure_request' THEN '/vacancy-closure-requests/' || p_reference_id
    WHEN 'hr_emploc_deletion'      THEN '/hr-emploc-deletion-requests/' || p_reference_id
    WHEN 'hr_emploc'               THEN '/hr-emploc/'                || p_reference_id
    WHEN 'ghost_employee'          THEN '/ghost-employees/'          || p_reference_id
    WHEN 'deactivation'            THEN '/deactivation-requests/'    || p_reference_id
    WHEN 'transfer'                THEN '/transfers/'                || p_reference_id
    WHEN 'account'                 THEN '/accounts/'                 || p_reference_id
    WHEN 'closure_request'         THEN '/vacancy-closure-requests/' || p_reference_id
    ELSE NULL
  END;
$function$
;

CREATE OR REPLACE FUNCTION public.bulk_move_ready_to_plantilla()
 RETURNS TABLE(hr_emploc_id uuid, plantilla_id uuid, result text, error text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r    record;
  v_pl public.plantilla;
BEGIN
  IF NOT (i_have_full_access() OR get_my_role() = 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  FOR r IN
    SELECT id FROM hr_emploc
     WHERE status = 'Ready for Plantilla'
       AND employee_no IS NOT NULL
       AND deleted_at IS NULL
     ORDER BY hr_reviewed_at ASC NULLS LAST
  LOOP
    BEGIN
      v_pl := move_to_plantilla(r.id);
      hr_emploc_id := r.id; plantilla_id := v_pl.id; result := 'moved'; error := NULL;
      RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      hr_emploc_id := r.id; plantilla_id := NULL; result := 'skipped'; error := SQLERRM;
      RETURN NEXT;
    END;
  END LOOP;
  RETURN;
END
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_qa_health_score(p_report_date date DEFAULT CURRENT_DATE, p_environment text DEFAULT 'staging'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_critical int := 0;
  v_high int := 0;
  v_medium int := 0;
  v_low int := 0;
  v_failed int := 0;
  v_score numeric := 100;
  v_status text := 'stable';
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can calculate QA health score';
  end if;

  select
    coalesce(sum(case when f.severity = 'critical' then 1 else 0 end), 0),
    coalesce(sum(case when f.severity = 'high' then 1 else 0 end), 0),
    coalesce(sum(case when f.severity = 'medium' then 1 else 0 end), 0),
    coalesce(sum(case when f.severity = 'low' then 1 else 0 end), 0),
    coalesce(count(distinct r.id) filter (where r.status = 'failed'), 0)
  into v_critical, v_high, v_medium, v_low, v_failed
  from public.qa_agent_runs r
  left join public.qa_agent_findings f on f.run_id = r.id
  where date(coalesce(r.started_at, r.created_at) at time zone 'Asia/Manila') = p_report_date
    and coalesce(r.metadata ->> 'environment', p_environment) = p_environment;

  v_score := greatest(0, 100 - (v_critical * 40) - (v_high * 20) - (v_medium * 8) - (v_low * 2) - (v_failed * 5));

  if v_score = 100 then
    v_status := 'stable';
  elsif v_score >= 90 then
    v_status := 'warning';
  elsif v_score >= 70 then
    v_status := 'unstable';
  else
    v_status := 'critical';
  end if;

  insert into public.qa_health_metrics(metric_date, environment, metric_name, metric_value, metric_status, metadata)
  values (p_report_date, p_environment, 'qa_health_score', v_score, v_status, jsonb_build_object('critical', v_critical, 'high', v_high, 'medium', v_medium, 'low', v_low, 'failed_runs', v_failed))
  on conflict (metric_date, environment, metric_name) do update set
    metric_value = excluded.metric_value,
    metric_status = excluded.metric_status,
    metadata = excluded.metadata,
    created_at = now();

  return jsonb_build_object('health_score', v_score, 'health_status', v_status, 'critical', v_critical, 'high', v_high, 'medium', v_medium, 'low', v_low, 'failed_runs', v_failed);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_target_user(p_target_profile_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
  v_actor_level  INT;
  v_target_level INT;
BEGIN
  v_actor_level  := get_my_role_level();
  v_target_level := get_target_role_level(p_target_profile_id);

  IF v_actor_level IS NULL OR v_target_level IS NULL THEN
    RETURN FALSE;
  END IF;

  RETURN v_actor_level > v_target_level;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_pool_employee(p_employee_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Data Team (30/90/100) and full access roles: always visible
  IF get_my_role_level() = ANY(ARRAY[100, 90, 30]) OR i_have_full_access() THEN
    RETURN TRUE;
  END IF;

  -- Ops (40-70) and Viewer (10) / Recruitment (20):
  -- visible if employee has NO group tag (global) OR group tag
  -- maps to at least one of caller's allowed accounts
  RETURN EXISTS (
    SELECT 1
    FROM workforce_pool_slots wps
    JOIN plantilla pt ON pt.vcode = wps.vcode
    WHERE pt.id = p_employee_id
      AND wps.is_active = true
      AND wps.deleted_at IS NULL
      AND (
        wps.group_id IS NULL
        OR EXISTS (
          SELECT 1 FROM accounts a
          WHERE a.group_id = wps.group_id
            AND a.id::text = ANY(get_my_allowed_accounts())
        )
      )
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.cancel_workforce_assignment(p_assignment_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_name    TEXT;
  v_current_status TEXT;
BEGIN
  IF NOT (get_my_role_level() = ANY (ARRAY[100, 90, 30]) OR i_have_full_access()) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;

  SELECT status INTO v_current_status
  FROM workforce_assignments WHERE id = p_assignment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Assignment not found.';
  END IF;
  IF v_current_status IN ('Completed','Cancelled') THEN
    RAISE EXCEPTION 'Cannot cancel: assignment is already %.', v_current_status;
  END IF;

  v_caller_name := get_my_full_name();

  UPDATE workforce_assignments SET
    status       = 'Cancelled',
    cancelled_by = v_caller_name,
    cancelled_at = now(),
    notes        = COALESCE(p_reason, notes),
    updated_at   = now(),
    updated_by   = v_caller_name
  WHERE id = p_assignment_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_closure_request_sla()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  u RECORD;
  lvl SMALLINT;
BEGIN
  FOR r IN
    SELECT cr.*, v.id AS vacancy_id, COALESCE(a.account_name, v.account, 'Account') AS account_name
    FROM public.vacancy_closure_requests cr
    LEFT JOIN public.vacancies v ON v.vcode = cr.vacancy_vcode
    LEFT JOIN public.accounts a ON a.id = v.account_id
    WHERE cr.status = 'Pending'
      AND cr.created_at < NOW() - INTERVAL '3 days'
  LOOP
    lvl := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    IF NOT public.notification_sla_exists('vacancy_closure', r.id::TEXT, lvl) THEN
      IF lvl = 2 THEN
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Super Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Super Admin', 'Escalated Closure Request — ' || r.account_name, 'Closure request for ' || r.vacancy_vcode || ' remains unactioned after 5 days.', 'escalation', 'vacancy_closure', 'vacancy_closure', r.id::TEXT, FORMAT('/vacancies/%s/closure-request/%s', COALESCE(r.vacancy_id::TEXT, r.vacancy_vcode), r.id), 2);
        END LOOP;
        IF r.requested_by_user_id IS NOT NULL THEN
          PERFORM public.notify_user(r.requested_by_user_id, 'Ops', 'Your Closure Request Escalated to Super Admin', 'Your closure request for ' || r.vacancy_vcode || ' has been escalated to Super Admin after 5 days of no action.', 'escalation', 'vacancy_closure', 'vacancy_closure', r.id::TEXT, FORMAT('/vacancies/%s/closure-request/%s', COALESCE(r.vacancy_id::TEXT, r.vacancy_vcode), r.id), 2);
        END IF;
      ELSE
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Head Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Head Admin', 'Unactioned Closure Request — ' || r.account_name, 'Closure request for ' || r.vacancy_vcode || ' has been pending for 3 days with no action from Encoder.', 'escalation', 'vacancy_closure', 'vacancy_closure', r.id::TEXT, FORMAT('/vacancies/%s/closure-request/%s', COALESCE(r.vacancy_id::TEXT, r.vacancy_vcode), r.id), 1);
        END LOOP;
        IF r.requested_by_user_id IS NOT NULL THEN
          PERFORM public.notify_user(r.requested_by_user_id, 'Ops', 'Your Closure Request Has Been Escalated', 'Your closure request for ' || r.vacancy_vcode || ' has been escalated to Head Admin.', 'escalation', 'vacancy_closure', 'vacancy_closure', r.id::TEXT, FORMAT('/vacancies/%s/closure-request/%s', COALESCE(r.vacancy_id::TEXT, r.vacancy_vcode), r.id), 1);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_deactivation_sla()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  u RECORD;
  req RECORD;
  lvl SMALLINT;
BEGIN
  FOR r IN SELECT * FROM public.deactivation_requests WHERE LOWER(COALESCE(status, '')) = 'pending' AND created_at < NOW() - INTERVAL '3 days' LOOP
    lvl := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    IF NOT public.notification_sla_exists('deactivation', r.id::TEXT, lvl) THEN
      SELECT auth_user_id, role INTO req FROM public.users_profile WHERE full_name = r.requested_by AND auth_user_id IS NOT NULL LIMIT 1;
      IF lvl = 2 THEN
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Super Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Super Admin', 'Escalated Deactivation Request — ' || COALESCE(r.group_name, 'Account'), 'A deactivation request for ' || COALESCE(r.group_name, 'the account') || ' remains unactioned after 5 days.', 'escalation', 'deactivation', 'deactivation', r.id::TEXT, FORMAT('/deactivation-requests/%s', r.id), 2);
        END LOOP;
        IF req.auth_user_id IS NOT NULL THEN
          PERFORM public.notify_user(req.auth_user_id, COALESCE(req.role, r.requested_by_role), 'Your Deactivation Request Escalated to Super Admin', 'Your deactivation request for ' || COALESCE(r.group_name, 'the account') || ' has been escalated to Super Admin after 5 days of no action.', 'escalation', 'deactivation', 'deactivation', r.id::TEXT, FORMAT('/deactivation-requests/%s', r.id), 2);
        END IF;
      ELSE
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Head Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Head Admin', 'Unactioned Deactivation Request — ' || COALESCE(r.group_name, 'Account'), 'A deactivation request for ' || COALESCE(r.group_name, 'the account') || ' has been pending for 3 days with no action from Encoder.', 'escalation', 'deactivation', 'deactivation', r.id::TEXT, FORMAT('/deactivation-requests/%s', r.id), 1);
        END LOOP;
        IF req.auth_user_id IS NOT NULL THEN
          PERFORM public.notify_user(req.auth_user_id, COALESCE(req.role, r.requested_by_role), 'Your Deactivation Request Has Been Escalated', 'Your deactivation request for ' || COALESCE(r.group_name, 'the account') || ' has been escalated to Head Admin due to no action from Encoder.', 'escalation', 'deactivation', 'deactivation', r.id::TEXT, FORMAT('/deactivation-requests/%s', r.id), 1);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_emploc_deletion_sla()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  u RECORD;
  req RECORD;
  lvl SMALLINT;
BEGIN
  FOR r IN SELECT * FROM public.hr_emploc_deletion_requests WHERE status = 'Pending' AND created_at < NOW() - INTERVAL '3 days' LOOP
    lvl := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    IF NOT public.notification_sla_exists('hr_emploc_deletion', r.id::TEXT, lvl) THEN
      SELECT auth_user_id, role INTO req FROM public.users_profile WHERE full_name = r.requested_by AND auth_user_id IS NOT NULL LIMIT 1;
      IF lvl = 2 THEN
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Super Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Super Admin', 'Escalated Deletion Request — ' || r.account, 'A deletion request for ' || r.applicant_name || ' (' || r.vcode || ') remains unactioned after 5 days.', 'escalation', 'hr_emploc_deletion', 'hr_emploc_deletion', r.id::TEXT, FORMAT('/hr-emploc/deletion-requests/%s', r.id), 2);
        END LOOP;
        IF req.auth_user_id IS NOT NULL THEN
          PERFORM public.notify_user(req.auth_user_id, COALESCE(req.role, r.requested_by_role), 'Your Request Has Been Escalated to Super Admin', 'Your deletion request for ' || r.applicant_name || ' (' || r.vcode || ') has been escalated to Super Admin after 5 days of no action.', 'escalation', 'hr_emploc_deletion', 'hr_emploc_deletion', r.id::TEXT, FORMAT('/hr-emploc/deletion-requests/%s', r.id), 2);
        END IF;
      ELSE
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Head Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Head Admin', 'Unactioned Deletion Request — ' || r.account, 'A deletion request for ' || r.applicant_name || ' (' || r.vcode || ') has been pending for 3 days with no action from Encoder.', 'escalation', 'hr_emploc_deletion', 'hr_emploc_deletion', r.id::TEXT, FORMAT('/hr-emploc/deletion-requests/%s', r.id), 1);
        END LOOP;
        IF req.auth_user_id IS NOT NULL THEN
          PERFORM public.notify_user(req.auth_user_id, COALESCE(req.role, r.requested_by_role), 'Your Request Has Been Escalated', 'Your deletion request for ' || r.applicant_name || ' (' || r.vcode || ') has been escalated to Head Admin due to no action from Encoder.', 'escalation', 'hr_emploc_deletion', 'hr_emploc_deletion', r.id::TEXT, FORMAT('/hr-emploc/deletion-requests/%s', r.id), 1);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_emploc_no_sla()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  u RECORD;
  om RECORD;
  lvl SMALLINT;
BEGIN
  FOR r IN
    SELECT * FROM public.hr_emploc
    WHERE employee_no IS NULL
      AND deleted_at IS NULL
      AND status NOT IN ('Backout', 'Moved to Plantilla')
      AND COALESCE(created_at, date_requested) < NOW() - INTERVAL '5 days'
  LOOP
    lvl := CASE WHEN COALESCE(r.created_at, r.date_requested) < NOW() - INTERVAL '7 days' THEN 2 ELSE 1 END;
    IF NOT public.notification_sla_exists('emploc_sla', r.id::TEXT, lvl) THEN
      SELECT auth_user_id, role INTO om FROM public.users_profile WHERE (id = r.om_user_id_snapshot OR auth_user_id = r.om_user_id_snapshot) AND auth_user_id IS NOT NULL LIMIT 1;
      IF lvl = 2 THEN
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Head Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Head Admin', 'Escalated — No Emploc Number — ' || r.account, r.applicant_name || ' (' || r.vcode || ') has been in HR Emploc for 7 days with no emploc number assigned. OM has been notified but no resolution yet.', 'escalation', 'emploc_sla', 'hr_emploc', r.id::TEXT, FORMAT('/hr-emploc/%s', r.id), 2);
        END LOOP;
        IF om.auth_user_id IS NOT NULL THEN
          PERFORM public.notify_user(om.auth_user_id, COALESCE(om.role, 'OM'), 'Emploc SLA Escalated to Head Admin', r.applicant_name || '''s lack of emploc number has been escalated to Head Admin after 7 days of no resolution.', 'escalation', 'emploc_sla', 'hr_emploc', r.id::TEXT, FORMAT('/hr-emploc/%s', r.id), 2);
        END IF;
      ELSE
        IF om.auth_user_id IS NOT NULL THEN
          PERFORM public.notify_user(om.auth_user_id, COALESCE(om.role, 'OM'), 'No Emploc Number — ' || r.applicant_name, r.applicant_name || ' (' || r.vcode || ') has been in HR Emploc for 5 days without an assigned emploc number. Immediate follow-up required.', 'escalation', 'emploc_sla', 'hr_emploc', r.id::TEXT, FORMAT('/hr-emploc/%s', r.id), 1);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_ghost_encoding_deadlines()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE rec RECORD;
BEGIN
  FOR rec IN
    SELECT * FROM possible_ghost_employees
    WHERE status IN ('Pending','Under Investigation')
      AND resolved_at IS NULL
      AND employee_no NOT IN (
        SELECT DISTINCT employee_no FROM plantilla
        WHERE status = 'Active' AND employee_no IS NOT NULL
      )
  LOOP
    IF rec.status = 'Pending'
       AND rec.created_at < now() - INTERVAL '48 hours'
       AND NOT COALESCE(rec.notified_48hr, false) THEN
      UPDATE possible_ghost_employees
      SET status = 'Under Investigation', notified_48hr = true, notified_48hr_at = now()
      WHERE id = rec.id;
      INSERT INTO notifications
        (recipient_role, title, message, reference_type, reference_id, deep_link_route)
      VALUES ('Head Admin', '⚠️ Ghost Employee Escalated',
        rec.full_name || ' (' || rec.account || ') not resolved in 48 hours.',
        'ghost_employee', rec.id::text,
        build_deep_link('ghost_employee', rec.id::text));

    ELSIF rec.status = 'Under Investigation'
       AND rec.notified_48hr_at IS NOT NULL
       AND rec.notified_48hr_at < now() - INTERVAL '24 hours'
       AND NOT COALESCE(rec.notified_72hr, false) THEN
      UPDATE possible_ghost_employees
      SET notified_72hr = true, notified_72hr_at = now()
      WHERE id = rec.id;
      INSERT INTO notifications
        (recipient_role, title, message, reference_type, reference_id, deep_link_route)
      VALUES ('Super Admin', '🚨 Ghost Unresolved 72hrs',
        rec.full_name || ' (' || rec.account || ') unresolved for 72 hours.',
        'ghost_employee', rec.id::text,
        build_deep_link('ghost_employee', rec.id::text));
    END IF;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_hc_request_sla()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  u RECORD;
  lvl SMALLINT;
BEGIN
  FOR r IN
    SELECT h.*, COALESCE(h.account_name_snapshot, a.account_name, 'the account') AS account_name,
           COALESCE(h.group_name_snapshot, g.group_name, 'Group') AS group_name
    FROM public.headcount_requests h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.groups g ON g.id = COALESCE(h.group_id, a.group_id)
    WHERE LOWER(h.status) = 'pending'
      AND h.created_at < NOW() - INTERVAL '3 days'
  LOOP
    lvl := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    IF NOT public.notification_sla_exists('hc_request', r.id::TEXT, lvl) THEN
      IF lvl = 2 THEN
        FOR u IN SELECT auth_user_id, role FROM public.users_profile WHERE role = 'Super Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Super Admin', 'Escalated HC Request — ' || r.group_name, 'An HC request for ' || r.account_name || ' remains unactioned after 5 days.', 'escalation', 'hc_request', 'headcount_request', r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 2);
        END LOOP;
        PERFORM public.notify_user(r.requested_by_user_id, r.requested_by_role, 'Your HC Request Escalated to Super Admin', 'Your HC request for ' || r.account_name || ' has been escalated to Super Admin after 5 days of no action.', 'escalation', 'hc_request', 'headcount_request', r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 2);
      ELSE
        FOR u IN SELECT auth_user_id, role FROM public.users_profile WHERE role = 'Head Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Head Admin', 'Unactioned HC Request — ' || r.group_name, r.requested_by_name || '''s HC request for ' || r.account_name || ' has been pending for 3 days. Please review.', 'escalation', 'hc_request', 'headcount_request', r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 1);
        END LOOP;
        PERFORM public.notify_user(r.requested_by_user_id, r.requested_by_role, 'Your HC Request Has Been Escalated', 'Your HC request for ' || r.account_name || ' has been escalated to Head Admin due to no action.', 'escalation', 'hc_request', 'headcount_request', r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 1);
      END IF;
    END IF;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_plantilla_sla_breaches()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_inactive_count int := 0;
  v_deact_count    int := 0;
  r record;
BEGIN
  FOR r IN
    SELECT p.id, p.employee_name, p.emploc_no, p.vcode, p.account, p.store_name,
           p.om_user_id_snapshot, p.inactive_at,
           EXTRACT(DAY FROM NOW() - p.inactive_at)::int AS days_overdue
    FROM public.plantilla p
    WHERE p.status = 'Inactive'
      AND p.inactive_at < NOW() - INTERVAL '3 days'
      AND NOT EXISTS (
        SELECT 1 FROM public.sla_breach_logs s
        WHERE s.plantilla_id = p.id
          AND s.breach_type  = 'inactive_no_deactivation_request'
          AND s.created_at   > NOW() - INTERVAL '24 hours'
      )
  LOOP
    INSERT INTO public.sla_breach_logs
      (plantilla_id, employee_no, vcode, account, breach_type,
       resignation_date, days_elapsed, notified_om)
    VALUES
      (r.id, r.emploc_no, r.vcode, r.account, 'inactive_no_deactivation_request',
       r.inactive_at::date, r.days_overdue, true);

    v_inactive_count := v_inactive_count + 1;
  END LOOP;

  FOR r IN
    SELECT p.id, p.employee_name, p.emploc_no, p.vcode, p.account, p.store_name,
           p.om_user_id_snapshot, p.for_deactivation_at,
           EXTRACT(DAY FROM NOW() - p.for_deactivation_at)::int AS days_overdue
    FROM public.plantilla p
    WHERE p.status = 'For Deactivation'
      AND p.for_deactivation_at < NOW() - INTERVAL '3 days'
      AND NOT EXISTS (
        SELECT 1 FROM public.sla_breach_logs s
        WHERE s.plantilla_id = p.id
          AND s.breach_type  = 'deactivation_overdue'
          AND s.created_at   > NOW() - INTERVAL '24 hours'
      )
  LOOP
    INSERT INTO public.sla_breach_logs
      (plantilla_id, employee_no, vcode, account, breach_type,
       resignation_date, days_elapsed, notified_om)
    VALUES
      (r.id, r.emploc_no, r.vcode, r.account, 'deactivation_overdue',
       r.for_deactivation_at::date, r.days_overdue, true);

    v_deact_count := v_deact_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'inactive_breaches', v_inactive_count,
    'deactivation_overdue_breaches', v_deact_count,
    'checked_at', NOW()
  );
END$function$
;

CREATE OR REPLACE FUNCTION public.check_sla_breach()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT
      id, employee_no, vcode, account,
      resignation_date,
      tagged_at
    FROM plantilla
    WHERE status = 'Resigned'
      AND resignation_date IS NOT NULL
      AND (
        tagged_at IS NULL
        OR (tagged_at - resignation_date) > 3
      )
  LOOP
    INSERT INTO sla_breach_logs (
      plantilla_id, employee_no, vcode, account,
      breach_type, resignation_date, tagged_date,
      days_elapsed, notified_om, created_at
    )
    VALUES (
      rec.id,
      rec.employee_no,
      rec.vcode,
      rec.account,
      'SLA_3DAY',
      rec.resignation_date,
      rec.tagged_at,
      COALESCE(rec.tagged_at - rec.resignation_date, CURRENT_DATE - rec.resignation_date),
      FALSE,
      NOW()
    )
    ON CONFLICT (plantilla_id) DO NOTHING;

    -- Notify OM
    PERFORM fn_notify_role(
      'OM',
      'SLA Breach',
      FORMAT('Employee %s (%s) resignation not tagged within 3 days.',
             rec.employee_no, rec.account),
      'plantilla',
      rec.id::TEXT,
      FORMAT('/plantilla/%s', rec.id)
    );
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_transfer_sla()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  u RECORD;
  req RECORD;
  lvl SMALLINT;
BEGIN
  FOR r IN SELECT * FROM public.employee_transfers WHERE status = 'Pending' AND created_at < NOW() - INTERVAL '3 days' AND COALESCE(is_deleted, false) = false LOOP
    lvl := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    IF NOT public.notification_sla_exists('transfer', r.id::TEXT, lvl) THEN
      SELECT auth_user_id, role INTO req FROM public.users_profile WHERE full_name = r.requested_by AND auth_user_id IS NOT NULL LIMIT 1;
      IF lvl = 2 THEN
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Super Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Super Admin', 'Escalated Transfer Request — ' || r.to_account, 'Transfer request for ' || r.employee_name || ' remains unactioned after 5 days.', 'escalation', 'transfer', 'transfer', r.id::TEXT, FORMAT('/transfers/%s', r.id), 2);
        END LOOP;
        IF req.auth_user_id IS NOT NULL THEN
          PERFORM public.notify_user(req.auth_user_id, COALESCE(req.role, r.requested_by_role), 'Your Transfer Request Escalated to Super Admin', 'Your transfer request for ' || r.employee_name || ' has been escalated to Super Admin after 5 days of no action.', 'escalation', 'transfer', 'transfer', r.id::TEXT, FORMAT('/transfers/%s', r.id), 2);
        END IF;
      ELSE
        FOR u IN SELECT auth_user_id FROM public.users_profile WHERE role = 'Head Admin' AND is_active = true AND auth_user_id IS NOT NULL LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Head Admin', 'Unactioned Transfer Request — ' || r.to_account, 'Transfer request for ' || r.employee_name || ' has been pending for 3 days with no action from Encoder.', 'escalation', 'transfer', 'transfer', r.id::TEXT, FORMAT('/transfers/%s', r.id), 1);
        END LOOP;
        IF req.auth_user_id IS NOT NULL THEN
          PERFORM public.notify_user(req.auth_user_id, COALESCE(req.role, r.requested_by_role), 'Your Transfer Request Has Been Escalated', 'Your transfer request for ' || r.employee_name || ' has been escalated to Head Admin due to no action from Encoder.', 'escalation', 'transfer', 'transfer', r.id::TEXT, FORMAT('/transfers/%s', r.id), 1);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_user_access(p_auth_uid uuid DEFAULT auth.uid())
 RETURNS TABLE(access_granted boolean, access_state text, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_in_profile boolean;
  v_request_status public.account_request_status;
begin
  if p_auth_uid is null then
    return query select false, 'unauthenticated'::text, 'no_auth_uid'::text;
    return;
  end if;

  select exists (
    select 1
    from public.users_profile
    where auth_user_id = p_auth_uid
      and coalesce(is_active, true)
  ) into v_in_profile;

  if v_in_profile then
    return query select true, 'active'::text, 'profile_found'::text;
    return;
  end if;

  select status
  into v_request_status
  from public.account_requests
  where auth_user_id = p_auth_uid
  order by created_at desc
  limit 1;

  -- Hardened: no profile + no request is not treated as system access.
  if v_request_status is null then
    return query select false, 'unregistered'::text, 'no_profile_or_request'::text;
    return;
  end if;

  if v_request_status = 'pending' then
    return query select false, 'pending'::text, 'awaiting_approval'::text;
    return;
  end if;

  if v_request_status = 'rejected' then
    return query select false, 'rejected'::text, 'request_rejected'::text;
    return;
  end if;

  -- Kept for transient provisioning window after approval.
  return query select true, 'approved_pending_provision'::text, 'awaiting_profile_creation'::text;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.check_vacancy_headcount()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_required int;
  v_hired int;
BEGIN
  -- Get required headcount for this vacancy
  SELECT COALESCE(required_headcount, 1) INTO v_required
  FROM public.vacancies
  WHERE vcode = NEW.vcode;

  IF v_required IS NULL THEN
    RETURN NEW;
  END IF;

  -- Count all hr_emploc records for this vcode
  SELECT COUNT(*) INTO v_hired
  FROM public.hr_emploc
  WHERE vcode = NEW.vcode;

  -- If hired count meets or exceeds required, mark as Filled
  IF v_hired >= v_required THEN
    UPDATE public.vacancies
    SET status = 'Filled',
        updated_at = now()
    WHERE vcode = NEW.vcode
      AND status NOT IN ('Closed', 'Archived');
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_expired_correction_attachments()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  -- Mark as deleted (storage object must be removed separately via Edge Function)
  UPDATE hr_emploc_correction_attachments
     SET is_deleted = true
   WHERE is_deleted = false
     AND expires_at IS NOT NULL
     AND expires_at <= now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.complete_employee_deactivation(p_plantilla_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old plantilla%ROWTYPE;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'complete_deact') THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_old FROM public.plantilla WHERE id = p_plantilla_id FOR UPDATE;
  IF v_old.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','plantilla_not_found');
  END IF;
  IF v_old.status <> 'For Deactivation' THEN
    RETURN jsonb_build_object('ok',false,'error','must_be_for_deactivation','current_status',v_old.status);
  END IF;

  UPDATE public.plantilla
  SET status                    = 'Deactivated',
      deactivated_at            = NOW(),
      deactivated_by            = public.get_current_profile_id(),
      deactivated_visible_until = NOW() + INTERVAL '15 days',
      remarks                   = COALESCE(p_remarks, remarks),
      updated_at                = NOW(),
      updated_by                = public.get_current_profile_id()
  WHERE id = p_plantilla_id;

  PERFORM public._log_employee_action(
    p_plantilla_id, 'DEACTIVATION_COMPLETED',
    format('Deactivation completed for %s', v_old.employee_name),
    to_jsonb(v_old),
    jsonb_build_object('status','Deactivated','visible_until',NOW() + INTERVAL '15 days','remarks',p_remarks)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'plantilla_id', p_plantilla_id,
    'new_status', 'Deactivated',
    'visible_until', NOW() + INTERVAL '15 days'
  );
END$function$
;

CREATE OR REPLACE FUNCTION public.complete_workforce_assignment(p_assignment_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_name    TEXT;
  v_current_status TEXT;
BEGIN
  IF NOT (get_my_role_level() = ANY (ARRAY[100, 90, 30]) OR i_have_full_access()) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;

  SELECT status INTO v_current_status
  FROM workforce_assignments WHERE id = p_assignment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Assignment not found.';
  END IF;
  IF v_current_status NOT IN ('Active','Approved') THEN
    RAISE EXCEPTION 'Cannot complete: assignment is currently %. Expected Active or Approved.', v_current_status;
  END IF;

  v_caller_name := get_my_full_name();

  UPDATE workforce_assignments SET
    status       = 'Completed',
    completed_at = now(),
    notes        = COALESCE(p_notes, notes),
    updated_at   = now(),
    updated_by   = v_caller_name
  WHERE id = p_assignment_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.confirm_applicant_onboard(p_applicant_id uuid, p_last_name text DEFAULT NULL::text, p_first_name text DEFAULT NULL::text, p_middle_name text DEFAULT NULL::text, p_full_name text DEFAULT NULL::text, p_contact_number text DEFAULT NULL::text, p_remarks text DEFAULT NULL::text, p_roving_assignment_id uuid DEFAULT NULL::uuid, p_hired_by_user_id uuid DEFAULT NULL::uuid, p_endorsed_by_deployer_id uuid DEFAULT NULL::uuid, p_endorsed_by_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role        text    := public.get_my_role();
  v_role_level  int     := COALESCE(public.get_my_role_level(), 0);
  v_profile_id  uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_app         public.applicants%ROWTYPE;
  v_vac         public.vacancies%ROWTYPE;
  v_hr          public.hr_emploc%ROWTYPE;
  v_full_name   text;
  v_hired_by_id uuid;
  v_is_roving   boolean;
  v_store_link_id uuid;
  v_late_result   jsonb;
  -- fast-track vars
  v_existing_plt      public.plantilla%ROWTYPE;
  v_roving_id         uuid;
  v_new_roving        boolean := false;
  v_plt_store_link_id uuid;
  v_existing_employee_no text;
  v_roving_hr_found   boolean := false;
BEGIN
  -- RBAC
  IF NOT (
    public.i_have_full_access()
    OR v_role_level = 30
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team, Data Team, or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.status, 'New') IN (
    'Failed', 'Backout', 'Did Not Report', 'Rejected by Ops'
  ) THEN
    RAISE EXCEPTION
      'cannot confirm onboarding: applicant is in terminal status %', v_app.status
      USING ERRCODE = '22023';
  END IF;

  v_is_roving := COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL;

  IF v_app.status = 'Confirmed Onboard' THEN
    IF v_is_roving THEN
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
         AND assignment_type = 'Roving'
         AND deleted_at IS NULL
       ORDER BY created_at ASC LIMIT 1;
    ELSE
      SELECT * INTO v_hr
        FROM public.hr_emploc
       WHERE deleted_at IS NULL
         AND (
           applicant_id = v_app.id
           OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
         )
       ORDER BY created_at DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
      'ok', true,
      'applicant_id', v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id', v_hr.id,
      'vcode', v_app.vacancy_vcode,
      'idempotent', true
    );
  END IF;

  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_app.vacancy_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'active vacancy not found for vcode %', v_app.vacancy_vcode
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_vac.has_pending_closure, false) = true THEN
    RAISE EXCEPTION
      'onboarding blocked: vacancy % has a pending closure request. Withdraw the closure request first.',
      v_vac.vcode
      USING ERRCODE = '55000';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF p_contact_number IS NOT NULL AND btrim(p_contact_number) <> '' THEN
    PERFORM public.fn_validate_ph_contact_number(p_contact_number);
  END IF;

  v_full_name := COALESCE(
    NULLIF(btrim(p_full_name), ''),
    NULLIF(btrim(concat_ws(' ',
      NULLIF(p_first_name, ''),
      NULLIF(p_middle_name, ''),
      NULLIF(p_last_name, '')
    )), ''),
    v_app.full_name
  );

  v_hired_by_id := COALESCE(p_hired_by_user_id, v_profile_id);

  UPDATE public.applicants
  SET
    last_name                = COALESCE(NULLIF(p_last_name, ''), last_name),
    first_name               = COALESCE(NULLIF(p_first_name, ''), first_name),
    middle_name              = p_middle_name,
    full_name                = v_full_name,
    full_name_snapshot       = v_full_name,
    contact_number           = COALESCE(NULLIF(p_contact_number, ''), contact_number),
    remarks                  = p_remarks,
    roving_assignment_id     = COALESCE(p_roving_assignment_id, roving_assignment_id),
    status                   = 'Confirmed Onboard',
    hired_date               = COALESCE(hired_date, CURRENT_DATE),
    hired_at                 = COALESCE(hired_at, NOW()),
    hired_by                 = v_actor_name,
    hired_by_team            = v_role,
    hired_by_user_id         = v_hired_by_id,
    endorsed_by_deployer_id  = p_endorsed_by_deployer_id,
    endorsed_by_name         = p_endorsed_by_name,
    deployed_by_user_id      = v_profile_id,
    is_archived              = false,
    updated_at               = NOW(),
    updated_by               = v_profile_id
  WHERE id = p_applicant_id
  RETURNING * INTO v_app;

  SELECT * INTO v_existing_plt
    FROM public.plantilla
   WHERE account = v_vac.account
     AND status = 'Active'
     AND is_deleted = false
     AND employee_no IS NOT NULL
     AND (
       (
         COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) IS NOT NULL
         AND roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       )
       OR LOWER(TRIM(employee_name)) = LOWER(TRIM(v_full_name))
     )
   ORDER BY
     CASE
       WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
       ELSE 1
     END,
     created_at DESC
   LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    v_roving_id := COALESCE(v_existing_plt.roving_assignment_id, p_roving_assignment_id, v_app.roving_assignment_id);

    IF v_roving_id IS NULL THEN
      INSERT INTO public.roving_assignments (
        master_applicant_id, account, account_id,
        primary_vcode, label, created_by, updated_by
      ) VALUES (
        v_app.id, v_vac.account, v_vac.account_id,
        COALESCE(v_existing_plt.vcode, v_vac.vcode),
        v_full_name,
        v_profile_id, v_profile_id
      )
      RETURNING id INTO v_roving_id;

      v_new_roving := true;
    END IF;

    UPDATE public.applicants
    SET roving_assignment_id = v_roving_id, updated_at = NOW(), updated_by = v_profile_id
    WHERE id = v_app.id
    RETURNING * INTO v_app;

    UPDATE public.plantilla
    SET deployment_type = 'Roving', roving_assignment_id = v_roving_id, updated_at = NOW(), updated_by = v_profile_id
    WHERE id = v_existing_plt.id;

    IF v_existing_plt.vcode IS NOT NULL THEN
      SELECT id INTO v_plt_store_link_id
        FROM public.plantilla_store_links
       WHERE plantilla_id = v_existing_plt.id
         AND roving_assignment_id = v_roving_id
         AND (vacancy_id = v_existing_plt.vacancy_id OR vcode = v_existing_plt.vcode)
         AND deleted_at IS NULL
       LIMIT 1
      FOR UPDATE;

      IF v_plt_store_link_id IS NULL THEN
        INSERT INTO public.plantilla_store_links (
          plantilla_id, roving_assignment_id,
          vacancy_id, vcode, store_name, account,
          status, linked_at, linked_by, created_by, updated_by
        ) VALUES (
          v_existing_plt.id, v_roving_id,
          v_existing_plt.vacancy_id, v_existing_plt.vcode,
          v_existing_plt.store_name, v_existing_plt.account,
          'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    v_plt_store_link_id := NULL;

    SELECT id INTO v_plt_store_link_id
      FROM public.plantilla_store_links
     WHERE plantilla_id = v_existing_plt.id
       AND roving_assignment_id = v_roving_id
       AND (
         vacancy_id = v_vac.id
         OR vcode = v_vac.vcode
         OR (account = v_vac.account AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, ''))))
       )
       AND deleted_at IS NULL
     LIMIT 1
    FOR UPDATE;

    IF v_plt_store_link_id IS NULL THEN
      INSERT INTO public.plantilla_store_links (
        plantilla_id, roving_assignment_id,
        vacancy_id, vcode, store_name, account,
        status, linked_at, linked_by, created_by, updated_by
      ) VALUES (
        v_existing_plt.id, v_roving_id,
        v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
        'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_plt_store_link_id;

      IF v_plt_store_link_id IS NULL THEN
        SELECT id INTO v_plt_store_link_id
          FROM public.plantilla_store_links
         WHERE plantilla_id = v_existing_plt.id
           AND roving_assignment_id = v_roving_id
           AND (
             vacancy_id = v_vac.id
             OR vcode = v_vac.vcode
             OR (account = v_vac.account AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, ''))))
           )
           AND deleted_at IS NULL
         LIMIT 1;
      END IF;
    ELSE
      UPDATE public.plantilla_store_links
      SET status = 'Active', unlinked_at = NULL, unlinked_by = NULL, updated_at = NOW(), updated_by = v_profile_id
      WHERE id = v_plt_store_link_id;
    END IF;

    UPDATE public.vacancies
    SET status = 'Filled', updated_at = NOW(), updated_by = v_profile_id
    WHERE id = v_vac.id;

    INSERT INTO public.employee_activity_log (emploc_no, vcode, activity_type, description, performed_by, metadata)
    VALUES (
      COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_app.full_name),
      v_vac.vcode,
      'confirmed_onboard_fast_track',
      'Existing Plantilla employee fast-tracked to new store, bypassing HR Emploc queue for ' || v_vac.vcode,
      v_actor_name,
      jsonb_build_object(
        'applicant_id', v_app.id,
        'hr_emploc_id', NULL,
        'plantilla_id', v_existing_plt.id,
        'plantilla_store_link_id', v_plt_store_link_id,
        'vacancy_id', v_vac.id,
        'employee_no', v_existing_plt.employee_no,
        'roving_assignment_id', v_roving_id,
        'new_roving_created', v_new_roving,
        'skipped_hr_emploc', true,
        'role', v_role,
        'hired_by_user_id', v_hired_by_id,
        'movement_at', NOW()
      )
    );

    RETURN jsonb_build_object(
      'ok', true,
      'applicant_id', v_app.id,
      'applicant_status', v_app.status,
      'hr_emploc_id', NULL,
      'plantilla_id', v_existing_plt.id,
      'plantilla_store_link_id', v_plt_store_link_id,
      'vcode', v_vac.vcode,
      'hired_by_user_id', v_hired_by_id,
      'is_roving', true,
      'fast_tracked', true,
      'skipped_hr_emploc', true,
      'new_roving_created', v_new_roving
    );
  END IF;

  IF v_is_roving THEN
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
       AND assignment_type = 'Roving'
       AND deleted_at IS NULL
     ORDER BY created_at ASC LIMIT 1
    FOR UPDATE;

    v_roving_hr_found := FOUND;

    IF v_roving_hr_found THEN
      v_existing_employee_no := COALESCE(NULLIF(BTRIM(v_hr.employee_no), ''), NULLIF(BTRIM(v_hr.emploc_no), ''));

      IF v_hr.status = 'Moved to Plantilla' OR v_existing_employee_no IS NOT NULL THEN
        SELECT * INTO v_existing_plt
          FROM public.plantilla
         WHERE is_deleted = false
           AND status IN ('Active', 'For Deactivation', 'On Leave')
           AND (
             roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
             OR hr_emploc_id = v_hr.id
             OR (v_existing_employee_no IS NOT NULL AND employee_no = v_existing_employee_no AND account = v_vac.account)
           )
         ORDER BY
           CASE
             WHEN roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id) THEN 0
             WHEN hr_emploc_id = v_hr.id THEN 1
             ELSE 2
           END,
           created_at DESC
         LIMIT 1
        FOR UPDATE;

        IF FOUND THEN
          v_roving_id := COALESCE(v_existing_plt.roving_assignment_id, v_hr.roving_assignment_id, p_roving_assignment_id, v_app.roving_assignment_id);

          UPDATE public.applicants
          SET roving_assignment_id = v_roving_id, updated_at = NOW(), updated_by = v_profile_id
          WHERE id = v_app.id
          RETURNING * INTO v_app;

          UPDATE public.plantilla
          SET deployment_type = 'Roving', roving_assignment_id = v_roving_id, updated_at = NOW(), updated_by = v_profile_id
          WHERE id = v_existing_plt.id;

          SELECT id INTO v_plt_store_link_id
            FROM public.plantilla_store_links
           WHERE plantilla_id = v_existing_plt.id
             AND roving_assignment_id = v_roving_id
             AND (
               vacancy_id = v_vac.id
               OR vcode = v_vac.vcode
               OR (account = v_vac.account AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, ''))))
             )
             AND deleted_at IS NULL
           LIMIT 1
          FOR UPDATE;

          IF v_plt_store_link_id IS NULL THEN
            INSERT INTO public.plantilla_store_links (
              plantilla_id, roving_assignment_id,
              vacancy_id, vcode, store_name, account,
              status, linked_at, linked_by, created_by, updated_by
            ) VALUES (
              v_existing_plt.id, v_roving_id,
              v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
              'Active', NOW(), v_profile_id, v_profile_id, v_profile_id
            )
            ON CONFLICT DO NOTHING
            RETURNING id INTO v_plt_store_link_id;

            IF v_plt_store_link_id IS NULL THEN
              SELECT id INTO v_plt_store_link_id
                FROM public.plantilla_store_links
               WHERE plantilla_id = v_existing_plt.id
                 AND roving_assignment_id = v_roving_id
                 AND (
                   vacancy_id = v_vac.id
                   OR vcode = v_vac.vcode
                   OR (account = v_vac.account AND LOWER(TRIM(COALESCE(store_name, ''))) = LOWER(TRIM(COALESCE(v_vac.store_name, ''))))
                 )
                 AND deleted_at IS NULL
               LIMIT 1;
            END IF;
          ELSE
            UPDATE public.plantilla_store_links
            SET status = 'Active', unlinked_at = NULL, unlinked_by = NULL, updated_at = NOW(), updated_by = v_profile_id
            WHERE id = v_plt_store_link_id;
          END IF;

          UPDATE public.vacancies
          SET status = 'Filled', updated_at = NOW(), updated_by = v_profile_id
          WHERE id = v_vac.id;

          INSERT INTO public.employee_activity_log (emploc_no, vcode, activity_type, description, performed_by, metadata)
          VALUES (
            COALESCE(v_existing_plt.emploc_no, v_existing_plt.employee_no, v_existing_employee_no, v_app.full_name),
            v_vac.vcode,
            'confirmed_onboard_fast_track',
            'Existing roving employee fast-tracked to new store, bypassing duplicate HR Emploc creation for ' || v_vac.vcode,
            v_actor_name,
            jsonb_build_object(
              'applicant_id', v_app.id,
              'hr_emploc_id', v_hr.id,
              'plantilla_id', v_existing_plt.id,
              'plantilla_store_link_id', v_plt_store_link_id,
              'vacancy_id', v_vac.id,
              'employee_no', COALESCE(v_existing_plt.employee_no, v_existing_employee_no),
              'roving_assignment_id', v_roving_id,
              'skipped_hr_emploc_insert', true,
              'role', v_role,
              'hired_by_user_id', v_hired_by_id,
              'movement_at', NOW()
            )
          );

          RETURN jsonb_build_object(
            'ok', true,
            'applicant_id', v_app.id,
            'applicant_status', v_app.status,
            'hr_emploc_id', v_hr.id,
            'plantilla_id', v_existing_plt.id,
            'plantilla_store_link_id', v_plt_store_link_id,
            'vcode', v_vac.vcode,
            'hired_by_user_id', v_hired_by_id,
            'is_roving', true,
            'fast_tracked', true,
            'skipped_hr_emploc', true,
            'duplicate_roving_guard', true
          );
        END IF;
      END IF;
    END IF;

    IF NOT v_roving_hr_found THEN
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_code_snapshot,
        account, account_id, chain_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Roving'::public.hr_emploc_assignment_type,
        COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
        '[]'::jsonb
      )
      ON CONFLICT DO NOTHING
      RETURNING * INTO v_hr;

      IF v_hr.id IS NULL THEN
        SELECT * INTO v_hr
          FROM public.hr_emploc
         WHERE roving_assignment_id = COALESCE(p_roving_assignment_id, v_app.roving_assignment_id)
           AND assignment_type = 'Roving'
           AND deleted_at IS NULL
         ORDER BY created_at ASC LIMIT 1
        FOR UPDATE;
      END IF;
    END IF;

    INSERT INTO public.hr_emploc_store_links (
      hr_emploc_id, roving_assignment_id, vacancy_id, vcode,
      store_name, account, status, confirmed_at, confirmed_by,
      created_by, updated_by
    ) VALUES (
      v_hr.id,
      COALESCE(p_roving_assignment_id, v_app.roving_assignment_id),
      v_vac.id, v_vac.vcode, v_vac.store_name, v_vac.account,
      'Confirmed', NOW(), v_profile_id, v_profile_id, v_profile_id
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_store_link_id;

    IF v_hr.status = 'Moved to Plantilla' AND v_store_link_id IS NOT NULL THEN
      SELECT public.link_late_store_to_plantilla(v_store_link_id) INTO v_late_result;
    END IF;

  ELSE
    SELECT * INTO v_hr
      FROM public.hr_emploc
     WHERE deleted_at IS NULL
       AND (
         applicant_id = v_app.id
         OR (applicant_name = v_app.full_name AND vcode = v_app.vacancy_vcode)
       )
     ORDER BY created_at DESC LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.hr_emploc (
        applicant_name, applicant_name_snapshot, applicant_id,
        vcode, vacancy_id, vacancy_code_snapshot,
        account, account_id, chain_id, store_id, province_id,
        area_name_snapshot, hrco_user_id_snapshot, om_user_id_snapshot,
        atl_user_id_snapshot, position_id_snapshot, position,
        store_name, hrco_name, status, hr_status, hired_date,
        deployed_by_user_id, created_by, updated_by, date_requested,
        assignment_type, roving_assignment_id, covered_stores
      ) VALUES (
        v_app.full_name, v_app.full_name, v_app.id,
        v_vac.vcode, v_vac.id, v_vac.vcode,
        v_vac.account, v_vac.account_id, v_vac.chain_id, v_vac.store_id, v_vac.province_id,
        v_vac.area_name, v_vac.hrco_user_id, v_vac.om_user_id,
        v_vac.atl_user_id, v_vac.position_id, v_vac.position,
        v_vac.store_name, v_vac.hrco_name, 'Pending Emploc', 'Pending', v_app.hired_date,
        v_profile_id, v_profile_id, v_profile_id, NOW(),
        'Stationary'::public.hr_emploc_assignment_type,
        NULL, '[]'::jsonb
      )
      RETURNING * INTO v_hr;
    END IF;
  END IF;

  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_hr.emploc_no, v_app.full_name),
    v_vac.vcode,
    'confirmed_onboard',
    'Applicant confirmed onboard and moved to HR Emploc for ' || v_vac.vcode,
    v_actor_name,
    jsonb_build_object(
      'applicant_id', v_app.id,
      'hr_emploc_id', v_hr.id,
      'vacancy_id', v_vac.id,
      'role', v_role,
      'hired_by_user_id', v_hired_by_id,
      'endorsed_by_deployer_id', p_endorsed_by_deployer_id,
      'endorsed_by_name', p_endorsed_by_name,
      'is_roving', v_is_roving,
      'late_store_linked', v_late_result IS NOT NULL,
      'movement_at', NOW()
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'applicant_id', v_app.id,
    'applicant_status', v_app.status,
    'hr_emploc_id', v_hr.id,
    'vcode', v_vac.vcode,
    'hired_by_user_id', v_hired_by_id,
    'is_roving', v_is_roving,
    'late_store_linked', v_late_result
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_applicant_and_link_to_vacancy(p_vacancy_id uuid, p_last_name text, p_first_name text, p_middle_name text, p_contact_number text, p_application_date date, p_source_channel text DEFAULT 'Walk-in'::text, p_comment text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v      public.vacancies%ROWTYPE;
  new_id uuid;
BEGIN
  IF NOT public.i_am_ops() THEN
    RAISE EXCEPTION 'forbidden: ops only';
  END IF;

  -- Required-field guard
  IF p_last_name IS NULL OR p_first_name IS NULL OR p_middle_name IS NULL
     OR p_contact_number IS NULL OR p_application_date IS NULL THEN
    RAISE EXCEPTION 'last_name, first_name, middle_name, contact_number, application_date are required';
  END IF;

  -- Format guard
  PERFORM public.fn_validate_ph_contact_number(p_contact_number);

  SELECT * INTO v FROM public.vacancies WHERE id = p_vacancy_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'vacancy not found'; END IF;
  IF v.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'vacancy archived'; END IF;
  IF COALESCE(v.has_pending_closure, false) THEN
    RAISE EXCEPTION 'vacancy is locked pending deletion';
  END IF;
  IF NOT (v.account = ANY (public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: out of scope';
  END IF;

  INSERT INTO public.applicants (
    vacancy_vcode, last_name, first_name, middle_name, full_name,
    contact_number, application_date, source_channel, comment,
    status, created_by
  ) VALUES (
    v.vcode, p_last_name, p_first_name, p_middle_name,
    p_last_name || ', ' || p_first_name || ' ' || p_middle_name,
    p_contact_number, p_application_date, p_source_channel, p_comment,
    'New', public.get_my_profile_id()
  ) RETURNING id INTO new_id;

  -- self-master if no link provided
  UPDATE public.applicants SET master_applicant_id = new_id WHERE id = new_id;

  PERFORM public.log_audit_event(
    'vacancy_module', 'INSERT', new_id,
    NULL,
    jsonb_build_object('action', 'create_applicant', 'vacancy_id', v.id)
  );

  RETURN new_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_plantilla_slot_from_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role              text := public.get_my_role();
  v_req               public.headcount_requests%ROWTYPE;
  v_account           public.accounts%ROWTYPE;
  v_store             public.stores%ROWTYPE;
  v_position          public.positions%ROWTYPE;
  v_store_name        text;
  v_store_id          uuid;
  v_vcode             text;
  v_vcodes            text[] := ARRAY[]::text[];
  v_plantilla_id      uuid;
  v_vacancy_id        uuid;
  v_first_plantilla_id uuid;
  v_count             integer;
  i                   integer;
  v_triggered_by_id   uuid;
  v_triggered_by_name text;
  v_hrco_user_id      uuid;
  v_hrco_name         text;
  v_group_id          uuid;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_req
  FROM public.headcount_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  IF v_req.status <> 'approved_pending_vcode' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_approved', 'current', v_req.status);
  END IF;

  v_count := COALESCE(v_req.headcount_needed, 1);

  IF v_count < 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_headcount_needed');
  END IF;

  IF v_count > 20 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'headcount_limit_exceeded', 'max', 20);
  END IF;

  SELECT * INTO v_account FROM public.accounts WHERE id = v_req.account_id;
  IF v_account.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  END IF;

  SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;
  IF v_position.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  END IF;

  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
  END IF;

  v_store_name := NULLIF(TRIM(COALESCE(v_store.store_name, v_req.store_name_snapshot)), '');
  v_store_id   := v_store.id;

  IF v_store_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'store_name');
  END IF;

  v_group_id := COALESCE(v_req.group_id, v_account.group_id);

  v_triggered_by_id := public.get_current_profile_id();
  SELECT full_name INTO v_triggered_by_name
  FROM public.users_profile WHERE id = v_triggered_by_id;

  v_hrco_user_id := v_account.hrco_user_id;
  IF v_hrco_user_id IS NOT NULL THEN
    SELECT full_name INTO v_hrco_name
    FROM public.users_profile WHERE id = v_hrco_user_id;
  END IF;

  FOR i IN 1..v_count LOOP
    v_vcode := public.generate_vcode_for_account(v_account.id);
    v_vcodes := array_append(v_vcodes, v_vcode);

    INSERT INTO public.vacancies (
      vcode, account, position, status,
      account_id, store_id, position_id, group_id,
      area_name, store_name, vacant_date,
      required_headcount, source_plantilla_id,
      vacancy_type, employment_type, urgency_level,
      target_fill_date, triggered_by_user_id, triggered_by_name,
      hrco_user_id, hrco_name,
      source, source_headcount_request_id,   -- ← fixed: proper FK column
      created_by, updated_by
    ) VALUES (
      v_vcode, v_account.account_name, v_position.position_name, 'Open',
      v_account.id, v_store_id, v_position.id, v_group_id,
      v_req.area, v_store_name, COALESCE(v_req.vacant_date, CURRENT_DATE),
      1, NULL,
      CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
      v_req.employment_type, v_req.urgency, v_req.target_fill_date,
      v_triggered_by_id, v_triggered_by_name,
      v_hrco_user_id, v_hrco_name,
      'hc_request', p_request_id,            -- ← correct: headcount_requests FK
      v_triggered_by_id, v_triggered_by_id
    ) RETURNING id INTO v_vacancy_id;

    INSERT INTO public.plantilla (
      employee_name, employee_no,
      account, status, vcode, position,
      account_id, store_id, area, position_id,
      store_name, deployment_type,
      source_headcount_request_id,
      created_by, updated_by, tagged_at
    ) VALUES (
      '(VACANT SLOT)', '(PENDING)',
      v_account.account_name, 'Inactive', v_vcode, v_position.position_name,
      v_account.id, v_store_id, v_req.area, v_position.id,
      v_store_name, v_req.employment_type,
      p_request_id,
      v_triggered_by_id, v_triggered_by_id, CURRENT_DATE
    ) RETURNING id INTO v_plantilla_id;

    IF v_first_plantilla_id IS NULL THEN
      v_first_plantilla_id := v_plantilla_id;
    END IF;

    UPDATE public.vacancies
    SET source_plantilla_id = v_plantilla_id,
        updated_by = v_triggered_by_id
    WHERE id = v_vacancy_id;
  END LOOP;

  UPDATE public.headcount_requests
  SET status                   = 'completed',
      vacancy_created          = true,
      slot_created_by_user_id  = v_triggered_by_id,
      slot_created_at          = NOW(),
      created_plantilla_id     = v_first_plantilla_id,
      created_vcode            = CASE WHEN array_length(v_vcodes, 1) >= 1 THEN v_vcodes[1] ELSE NULL END,
      created_vcodes           = v_vcodes
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok',               true,
    'request_id',       p_request_id,
    'headcount_created', v_count,
    'vcode_count',      array_length(v_vcodes, 1),
    'vcodes',           v_vcodes,
    'vacancy_created',  true
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_pool_vacancy(p_pool_type_code text, p_position_id uuid, p_requesting_account_id uuid, p_requesting_store_id uuid DEFAULT NULL::uuid, p_headcount_needed integer DEFAULT 1, p_priority text DEFAULT 'normal'::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level            int;
  v_caller_name           text;
  v_pool_type_id          uuid;
  v_moses_hq_id           uuid;
  v_requesting_acct_name  text;
  v_requesting_store_name text;
  v_position_name         text;
  v_req_group_id          uuid;
  v_pool_request_id       uuid;
  v_vcode                 text;
  v_vacancy_id            uuid;
  v_created_vcodes        text[] := '{}';
  v_created_ids           uuid[] := '{}';
  i                       int;
BEGIN
  v_role_level := public.get_my_role_level();
  IF v_role_level IS NULL OR v_role_level NOT IN (100, 90, 30) THEN
    RAISE EXCEPTION 'Unauthorized: create_pool_vacancy requires Data Team access (SA/HA/Encoder)';
  END IF;

  v_caller_name := public.get_my_full_name();

  IF p_headcount_needed < 1 OR p_headcount_needed > 50 THEN
    RAISE EXCEPTION 'headcount_needed must be 1–50, got %', p_headcount_needed;
  END IF;

  IF p_priority NOT IN ('normal', 'urgent', 'critical') THEN
    RAISE EXCEPTION 'Invalid priority: %', p_priority;
  END IF;

  SELECT id INTO v_pool_type_id
  FROM public.workforce_pool_types
  WHERE code = p_pool_type_code AND is_active = true;
  IF v_pool_type_id IS NULL THEN
    RAISE EXCEPTION 'Invalid pool type code: %', p_pool_type_code;
  END IF;

  SELECT id INTO v_moses_hq_id
  FROM public.accounts
  WHERE is_pool_account = true AND is_active = true
  LIMIT 1;
  IF v_moses_hq_id IS NULL THEN
    RAISE EXCEPTION 'Moses HQ pool account not found';
  END IF;

  SELECT account_name, group_id
  INTO v_requesting_acct_name, v_req_group_id
  FROM public.accounts
  WHERE id = p_requesting_account_id AND is_active = true;
  IF v_requesting_acct_name IS NULL THEN
    RAISE EXCEPTION 'Requesting account not found or inactive';
  END IF;

  IF p_requesting_store_id IS NOT NULL THEN
    SELECT store_name INTO v_requesting_store_name
    FROM public.stores
    WHERE id = p_requesting_store_id AND is_active = true;
  END IF;

  SELECT position_name INTO v_position_name
  FROM public.positions
  WHERE id = p_position_id AND is_active = true;
  IF v_position_name IS NULL THEN
    RAISE EXCEPTION 'Position not found or inactive';
  END IF;

  INSERT INTO public.workforce_pool_requests (
    pool_type_id, requesting_account_id, requesting_account,
    requesting_store_id, requesting_store,
    headcount_needed, priority, reason,
    status, approved_by, approved_at, created_by
  ) VALUES (
    v_pool_type_id, p_requesting_account_id, v_requesting_acct_name,
    p_requesting_store_id, v_requesting_store_name,
    p_headcount_needed, p_priority, p_reason,
    'approved', v_caller_name, now(), v_caller_name
  ) RETURNING id INTO v_pool_request_id;

  FOR i IN 1..p_headcount_needed LOOP

    v_vcode := public.generate_pool_vcode(p_pool_type_code);

    INSERT INTO public.vacancies (
      vcode, account, account_id, group_id,
      position, position_id, store_id,
      status, vacant_date, required_headcount, source,
      is_pool_vacancy, pool_type_id, home_account_id,
      affects_required_hc, affects_mfr, pool_request_id,
      created_by
    ) VALUES (
      v_vcode, v_requesting_acct_name, p_requesting_account_id, v_req_group_id,
      v_position_name, p_position_id, p_requesting_store_id,
      'Open', now(), 1, 'pool',
      true, v_pool_type_id, v_moses_hq_id,
      false, false, v_pool_request_id,
      v_caller_name
    ) RETURNING id INTO v_vacancy_id;

    INSERT INTO public.workforce_pool_slots (
      vcode, pool_type_id, vacancy_id,
      status, account, account_id, group_id, created_by
    ) VALUES (
      v_vcode, v_pool_type_id, v_vacancy_id,
      'open', v_requesting_acct_name, p_requesting_account_id,
      v_req_group_id, v_caller_name
    );

    INSERT INTO public.workforce_pool_request_items (
      request_id, vacancy_id, vcode, position_id, status
    ) VALUES (
      v_pool_request_id, v_vacancy_id, v_vcode, p_position_id, 'open'
    );

    v_created_vcodes := v_created_vcodes || v_vcode;
    v_created_ids    := v_created_ids    || v_vacancy_id;

  END LOOP;

  RETURN jsonb_build_object(
    'success',           true,
    'pool_request_id',   v_pool_request_id,
    'pool_type',         p_pool_type_code,
    'headcount_created', p_headcount_needed,
    'vcodes',            v_created_vcodes,
    'vacancy_ids',       v_created_ids
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_qa_notification(p_severity text, p_title text, p_message text, p_reference_type text DEFAULT NULL::text, p_reference_id uuid DEFAULT NULL::uuid, p_target_role text DEFAULT 'Head Admin'::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_type text;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can create QA notifications';
  end if;

  if p_severity not in ('low','medium','high','critical') then
    raise exception 'Invalid QA notification severity: %', p_severity;
  end if;

  v_type := case
    when p_severity in ('critical','high') then 'immediate'
    when p_severity = 'medium' then 'daily_digest'
    else 'weekly_digest'
  end;

  insert into public.qa_notifications(notification_type, severity, title, message, reference_type, reference_id, target_role, metadata)
  values (v_type, p_severity, p_title, p_message, p_reference_type, p_reference_id, p_target_role, coalesce(p_metadata, '{}'::jsonb))
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_qa_schedule(p_schedule_name text, p_suite_name text DEFAULT 'core_detection'::text, p_frequency text DEFAULT 'daily'::text, p_run_time time without time zone DEFAULT '06:00:00'::time without time zone, p_environment text DEFAULT 'staging'::text, p_assigned_agent_name text DEFAULT 'QA_DETECTION_ENGINE'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_profile_id uuid;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can create QA schedules';
  end if;

  if p_environment = 'production_readonly' and p_suite_name <> 'core_detection' then
    raise exception 'Production monitoring is read-only and only core_detection is allowed at this phase';
  end if;

  v_profile_id := get_current_profile_id();

  insert into public.qa_schedules (
    schedule_name,
    suite_name,
    frequency,
    run_time,
    environment,
    assigned_agent_name,
    created_by,
    updated_by,
    next_run_at
  ) values (
    p_schedule_name,
    coalesce(nullif(p_suite_name, ''), 'core_detection'),
    p_frequency,
    p_run_time,
    p_environment,
    coalesce(nullif(p_assigned_agent_name, ''), 'QA_DETECTION_ENGINE'),
    v_profile_id,
    v_profile_id,
    public.qa_calculate_next_run_at(p_frequency, p_run_time, 'Asia/Manila', now())
  )
  on conflict (schedule_name) do update set
    suite_name = excluded.suite_name,
    frequency = excluded.frequency,
    run_time = excluded.run_time,
    environment = excluded.environment,
    assigned_agent_name = excluded.assigned_agent_name,
    updated_by = excluded.updated_by,
    updated_at = now(),
    next_run_at = excluded.next_run_at
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_store_import_batch(p_file_name text, p_group_id uuid, p_account_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lvl   int  := public.get_my_role_level();
  v_role  text := public.get_my_role();
  v_uid   uuid := auth.uid();
  v_id    uuid;
BEGIN
  IF v_lvl IS NULL OR v_lvl < 90 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: role_level >= 90 required';
  END IF;
  IF p_file_name IS NULL OR length(trim(p_file_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: file_name required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'INVALID_GROUP: %', p_group_id;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = p_account_id AND group_id = p_group_id) THEN
    RAISE EXCEPTION 'INVALID_ACCOUNT: account % does not belong to group %', p_account_id, p_group_id;
  END IF;

  INSERT INTO public.store_import_batches (
    file_name, uploaded_by, uploaded_role, selected_group_id, selected_account_id, status
  ) VALUES (
    p_file_name, v_uid, v_role, p_group_id, p_account_id, 'draft_uploaded'
  ) RETURNING id INTO v_id;

  RETURN v_id;
END$function$
;

CREATE OR REPLACE FUNCTION public.create_vacancy_from_headcount_request(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role       text := public.get_my_role();
  v_req        headcount_requests%ROWTYPE;
  v_account    accounts%ROWTYPE;
  v_store      stores%ROWTYPE;
  v_position   positions%ROWTYPE;
  v_store_name text;
  v_store_id   uuid;
BEGIN
  IF NOT (v_role IN ('Encoder', 'Super Admin', 'Head Admin')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_req FROM public.headcount_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;
  IF v_req.status <> 'completed' THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'request_not_completed', 'current', v_req.status
    );
  END IF;
  IF v_req.created_vcode IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_vcode_generated');
  END IF;
  IF coalesce(v_req.vacancy_created, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vacancy_already_created');
  END IF;

  SELECT * INTO v_account  FROM public.accounts  WHERE id = v_req.account_id;
  SELECT * INTO v_position FROM public.positions WHERE id = v_req.position_id;

  IF v_req.store_id IS NOT NULL THEN
    SELECT * INTO v_store FROM public.stores WHERE id = v_req.store_id;
  END IF;
  v_store_name := COALESCE(v_store.store_name, v_req.store_name_snapshot);
  v_store_id   := v_store.id;

  INSERT INTO public.vacancies (
    vcode, account, position, status,
    account_id, store_id, position_id,
    area_name, store_name, vacant_date,
    required_headcount, source_plantilla_id,
    vacancy_type, created_by
  ) VALUES (
    v_req.created_vcode, v_account.account_name, v_position.position_name, 'Open',
    v_account.id, v_store_id, v_position.id,
    v_req.area, v_store_name, COALESCE(v_req.vacant_date, CURRENT_DATE),
    v_req.headcount_needed, v_req.created_plantilla_id,
    CASE WHEN v_req.request_type = 'Replacement' THEN 'Replacement' ELSE 'New' END,
    public.get_current_profile_id()
  );

  UPDATE public.headcount_requests
  SET vacancy_created = true
  WHERE id = p_request_id;

  PERFORM public.log_audit_event(
    'Vacancy.CreatedFromHCRequest', 'INSERT', p_request_id,
    NULL,
    jsonb_build_object(
      'request_id', p_request_id,
      'vcode',      v_req.created_vcode,
      'account_id', v_req.account_id
    )
  );

  RETURN jsonb_build_object(
    'ok',              true,
    'request_id',      p_request_id,
    'vcode',           v_req.created_vcode,
    'vacancy_created', true
  );
END
$function$
;

CREATE OR REPLACE FUNCTION public.create_workforce_assignment(p_employee_id uuid, p_pool_type_id uuid, p_assigned_group_id uuid DEFAULT NULL::uuid, p_assigned_account_id uuid DEFAULT NULL::uuid, p_assigned_store_id uuid DEFAULT NULL::uuid, p_deployment_type text DEFAULT NULL::text, p_priority text DEFAULT 'normal'::text, p_is_primary boolean DEFAULT false, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_name TEXT;
  v_new_id      UUID;
BEGIN
  IF NOT (get_my_role_level() = ANY (ARRAY[100, 90, 30]) OR i_have_full_access()) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'start_date and end_date are required.';
  END IF;
  IF p_start_date > p_end_date THEN
    RAISE EXCEPTION 'start_date must be <= end_date.';
  END IF;

  -- Employee active check
  IF NOT EXISTS (
    SELECT 1 FROM plantilla
    WHERE id = p_employee_id
      AND is_deleted = false
      AND deactivated_at IS NULL
      AND status = 'Active'
  ) THEN
    RAISE EXCEPTION 'Employee not found or inactive.';
  END IF;

  -- Pool enrollment check
  IF NOT EXISTS (
    SELECT 1
    FROM workforce_pool_slots wps
    JOIN plantilla pt ON pt.vcode = wps.vcode
    WHERE pt.id = p_employee_id
      AND wps.pool_type_id = p_pool_type_id
      AND wps.is_active = true
      AND wps.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Employee is not enrolled in the specified workforce pool.';
  END IF;

  v_caller_name := get_my_full_name();

  INSERT INTO workforce_assignments (
    employee_id, pool_type_id, assigned_group_id, assigned_account_id,
    assigned_store_id, deployment_type, priority, is_primary,
    start_date, end_date, status, requested_by, notes,
    created_at, created_by, updated_at, updated_by
  ) VALUES (
    p_employee_id, p_pool_type_id, p_assigned_group_id, p_assigned_account_id,
    p_assigned_store_id, p_deployment_type, p_priority, p_is_primary,
    p_start_date, p_end_date, 'Pending', v_caller_name, p_notes,
    now(), v_caller_name, now(), v_caller_name
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.current_user_scope()
 RETURNS TABLE(user_profile_id uuid, full_name text, email text, role_id uuid, role_name text, role_level integer, group_id uuid, group_name text, account_id uuid, account_name text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    up.id, up.full_name, up.email,
    up.role_id, r.role_name, r.role_level,
    up.group_id, g.group_name,
    up.account_id, a.account_name
  FROM public.users_profile up
  LEFT JOIN public.roles r ON r.id = up.role_id
  LEFT JOIN public.groups g ON g.id = up.group_id
  LEFT JOIN public.accounts a ON a.id = up.account_id
  WHERE up.auth_user_id = auth.uid()
    AND up.is_active = TRUE
  LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.current_user_scope_v2()
 RETURNS TABLE(user_profile_id uuid, full_name text, email text, role_id uuid, role_name text, role_level integer, scope_type text, group_id uuid, group_name text, account_id uuid, account_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    with acting as (
        select *
        from public.get_active_acting_session()
    )
    select
        up.id,
        up.full_name,
        up.email,
        up.role_id,
        coalesce(act.acting_role, r.role_name) as role_name,
        case coalesce(act.acting_role, r.role_name)
            when 'Super Admin' then 100
            when 'Head Admin' then 90
            when 'Operations Manager' then 70
            when 'OM' then 70
            when 'HRCO' then 45
            when 'ATL/TL' then 40
            when 'ATL' then 42
            when 'TL' then 41
            when 'Encoder' then 30
            when 'HR Personnel' then 25
            when 'Recruitment Team' then 20
            when 'Recruitment' then 20
            when 'Back Office' then 15
            when 'Backoffice' then 15
            when 'Viewer' then 10
            else coalesce(r.role_level, 0)
        end as role_level,
        case
            when coalesce(act.acting_role, r.role_name) in ('Super Admin','Head Admin') then 'global'
            else coalesce(up.scope_type, 'scoped')
        end as scope_type,
        us.group_id,
        g.group_name,
        us.account_id,
        a.account_name
    from public.users_profile up
    left join public.roles r on r.id = up.role_id
    left join public.user_scopes us on us.user_id = up.id
    left join public.groups g on g.id = us.group_id
    left join public.accounts a on a.id = us.account_id
    left join acting act on true
    where up.auth_user_id = auth.uid()
      and up.is_active = true
      and (
        act.id is null
        or (
            (coalesce(array_length(act.acting_group_ids, 1), 0) = 0 or us.group_id = any(act.acting_group_ids))
            and
            (coalesce(array_length(act.acting_account_ids, 1), 0) = 0 or us.account_id = any(act.acting_account_ids))
        )
      );
$function$
;

CREATE OR REPLACE FUNCTION public.endo_employee(p_plantilla_id uuid, p_separation_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public._apply_separation(p_plantilla_id, 'Endo', p_separation_date, p_remarks, 'endo');
$function$
;

CREATE OR REPLACE FUNCTION public.endorse_applicant_to_ops(p_applicant_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
  v_app        public.applicants%ROWTYPE;
  v_vac        RECORD;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────────────────
  IF NOT (public.i_have_full_access() OR public.i_am_recruitment()) THEN
    RAISE EXCEPTION 'forbidden: Recruitment Team or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock applicant ─────────────────────────────────────────────
  SELECT *
    INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Status guard — must be in an active recruitment stage ────────────────
  IF COALESCE(v_app.status, 'New') IN (
    'Confirmed Onboard', 'Hired', 'Endorsed to Ops', 'Endorsed',
    'Failed', 'Backout', 'Did Not Report', 'Rejected by Ops'
  ) THEN
    RAISE EXCEPTION
      'cannot endorse applicant with status %. Valid stages: New, For Interview, For Requirements',
      v_app.status
      USING ERRCODE = '22023';
  END IF;

  -- ── Scope check ──────────────────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    SELECT vcode INTO v_vac
      FROM public.vacancies
     WHERE vcode = v_app.vacancy_vcode
       AND account = ANY(public.get_my_allowed_accounts())
       AND deleted_at IS NULL
     LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'forbidden: vacancy outside your account scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Update applicant ─────────────────────────────────────────────────────
  UPDATE public.applicants
  SET
    status      = 'Endorsed to Ops',
    remarks     = CASE
                    WHEN p_notes IS NOT NULL THEN
                      COALESCE(remarks, '') ||
                      CASE WHEN remarks IS NOT NULL THEN ' | ' ELSE '' END ||
                      '[Endorsed] ' || p_notes
                    ELSE remarks
                  END,
    updated_at  = NOW(),
    updated_by  = v_profile_id
  WHERE id = p_applicant_id
  RETURNING * INTO v_app;

  RETURN jsonb_build_object(
    'ok',           true,
    'applicant_id', v_app.id,
    'old_status',   v_app.status,
    'new_status',   'Endorsed to Ops',
    'endorsed_by',  v_actor_name
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.enqueue_scheduled_qa_run(p_schedule_id uuid, p_force boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_schedule public.qa_schedules%rowtype;
  v_queue_id uuid;
  v_lock_key text;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can enqueue QA runs';
  end if;

  select * into v_schedule
  from public.qa_schedules
  where id = p_schedule_id
    and archived_at is null;

  if v_schedule.id is null then
    raise exception 'QA schedule not found';
  end if;

  if not v_schedule.is_enabled and not p_force then
    raise exception 'QA schedule is disabled';
  end if;

  if v_schedule.next_run_at is not null and v_schedule.next_run_at > now() and not p_force then
    raise exception 'QA schedule is not due yet';
  end if;

  v_lock_key := v_schedule.environment || ':' || v_schedule.suite_name;

  insert into public.qa_run_queue (
    schedule_id,
    suite_name,
    environment,
    queue_status,
    lock_key,
    metadata
  ) values (
    v_schedule.id,
    v_schedule.suite_name,
    v_schedule.environment,
    'queued',
    v_lock_key,
    jsonb_build_object('schedule_name', v_schedule.schedule_name, 'assigned_agent_name', v_schedule.assigned_agent_name)
  )
  returning id into v_queue_id;

  update public.qa_schedules
  set last_queued_at = now(),
      next_run_at = public.qa_calculate_next_run_at(frequency, run_time, timezone, now()),
      updated_at = now()
  where id = p_schedule_id;

  return v_queue_id;
exception
  when unique_violation then
    raise exception 'A QA run for this suite/environment is already queued or running';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.expire_temp_overrides()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.temp_permission_overrides
  SET is_active = false
  WHERE is_active = true
    AND expires_at < now();
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_archive_hired_vacancies()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count int := 0;
BEGIN
  UPDATE vacancies v
  SET
    is_archived = true,
    archived_at = NOW(),
    status = 'Archived',
    updated_at = NOW()
  WHERE v.deleted_at IS NULL
    AND (v.is_archived IS NULL OR v.is_archived = false)
    AND v.status NOT IN ('Archived', 'Closed')
    AND EXISTS (
      SELECT 1 FROM applicants a
      WHERE a.vacancy_vcode = v.vcode
        AND (a.is_archived IS NULL OR a.is_archived = false)
        AND a.status = 'Confirmed Onboard'
        AND a.hired_at < NOW() - INTERVAL '7 days'
    )
    AND NOT EXISTS (
      SELECT 1 FROM applicants a
      WHERE a.vacancy_vcode = v.vcode
        AND (a.is_archived IS NULL OR a.is_archived = false)
        AND a.status NOT IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops', 'Confirmed Onboard')
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_assert_no_dup_stationary_hr_emploc(p_applicant_id uuid, p_vacancy_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_applicant_id IS NULL OR p_vacancy_id IS NULL THEN
    RAISE EXCEPTION
      'fn_assert_no_dup_stationary_hr_emploc: applicant_id and vacancy_id must be NOT NULL'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.hr_emploc
    WHERE applicant_id   = p_applicant_id
      AND vacancy_id     = p_vacancy_id
      AND assignment_type = 'Stationary'
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION
      'Duplicate Stationary HR Emploc: applicant % already linked to vacancy %',
      p_applicant_id, p_vacancy_id
      USING ERRCODE = 'unique_violation';
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_assert_vacancy_actionable(p_vacancy_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_closure_status TEXT;
  v_has_pending    BOOLEAN;
  v_is_archived    BOOLEAN;
  v_archived_at    TIMESTAMPTZ;
BEGIN
  IF p_vacancy_id IS NULL THEN
    RAISE EXCEPTION 'fn_assert_vacancy_actionable: vacancy_id must be NOT NULL'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT closure_request_status, has_pending_closure, is_archived, archived_at
    INTO v_closure_status, v_has_pending, v_is_archived, v_archived_at
  FROM public.vacancies
  WHERE id = p_vacancy_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vacancy % not found', p_vacancy_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_is_archived = TRUE OR v_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Vacancy % is archived and is read-only', p_vacancy_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_closure_status = 'Pending' OR v_has_pending = TRUE THEN
    RAISE EXCEPTION
      'Vacancy % has a pending closure request and is read-only', p_vacancy_id
      USING ERRCODE = 'check_violation';
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_assert_vacancy_closeable(p_vcode text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status      TEXT;
  v_is_archived BOOLEAN;
  v_archived_at TIMESTAMPTZ;
BEGIN
  IF nullif(trim(p_vcode), '') IS NULL THEN
    RAISE EXCEPTION 'fn_assert_vacancy_closeable: vcode is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT status, COALESCE(is_archived, false), archived_at
    INTO v_status, v_is_archived, v_archived_at
  FROM public.vacancies
  WHERE vcode = p_vcode
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vacancy % not found or deleted', p_vcode
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Block: already archived/closed
  IF v_is_archived = true OR v_archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % is already archived/closed.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: vacancy already Filled
  IF v_status = 'Filled' THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % is already Filled. Cannot close a fulfilled vacancy.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: active hired applicant
  IF EXISTS (
    SELECT 1 FROM public.applicants
    WHERE vacancy_vcode = p_vcode
      AND status IN ('Hired', 'Confirmed Onboard')
  ) THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % has an active hired applicant. Deletion not allowed after hiring.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: active hr_emploc pipeline (not backed out, not moved to plantilla, not deleted)
  IF EXISTS (
    SELECT 1 FROM public.hr_emploc
    WHERE vcode = p_vcode
      AND deleted_at IS NULL
      AND backout_at IS NULL
      AND status NOT IN ('Moved to Plantilla')
  ) THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % has active HR Emploc records in pipeline. Resolve pending onboarding before requesting closure.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: active plantilla headcount linked to this vcode
  IF EXISTS (
    SELECT 1 FROM public.plantilla
    WHERE vcode = p_vcode
      AND status = 'Active'
      AND separation_status IS NULL
  ) THEN
    RAISE EXCEPTION 'CLOSURE_BLOCKED: Vacancy % has active deployed Plantilla headcount. Cannot close a vacancy with confirmed employees.', p_vcode
      USING ERRCODE = 'check_violation';
  END IF;

END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_audit_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_action          audit_action;
  v_old_data        JSONB;
  v_new_data        JSONB;
  v_old_status      TEXT;
  v_new_status      TEXT;
  v_role            TEXT;
  v_approval_states TEXT[] := ARRAY['Hired','Approved','Filled','Closed'];
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_action   := 'INSERT';
    v_old_data := NULL;
    v_new_data := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_data := to_jsonb(OLD);
    v_new_data := to_jsonb(NEW);
    IF (v_new_data ? 'is_deleted')
       AND (v_new_data->>'is_deleted')::BOOLEAN = TRUE
       AND COALESCE((v_old_data->>'is_deleted')::BOOLEAN, FALSE) = FALSE
    THEN
      v_action := 'SOFT_DELETE';
    ELSE
      v_action := 'UPDATE';
      v_old_status := v_old_data->>'status';
      v_new_status := v_new_data->>'status';
      IF v_new_status IS DISTINCT FROM v_old_status
         AND v_new_status = ANY(v_approval_states) THEN
        v_action := 'APPROVAL';
      END IF;
    END IF;
  END IF;

  BEGIN v_role := public.get_my_role(); EXCEPTION WHEN OTHERS THEN v_role := NULL; END;

  INSERT INTO public.audit_logs (actor_id, role, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(), v_role, TG_TABLE_NAME, v_action,
    (to_jsonb(NEW)->>'id')::UUID, v_old_data, v_new_data
  );

  RETURN NEW;
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

CREATE OR REPLACE FUNCTION public.fn_mark_ghost_auto_resolved(p_ghost_id uuid, p_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.possible_ghost_employees
  SET
    status              = 'Resolved',
    resolved_by         = 'SYSTEM',
    resolved_by_role    = 'SYSTEM',
    resolved_at         = now(),
    resolution_type     = 'Auto Resolved',
    resolution_notes    = p_notes,
    resolution_remarks  = p_notes,
    auto_resolved       = true,
    last_revalidated_at = now(),
    updated_at          = now()
  WHERE id = p_ghost_id
    -- Never overwrite a manual resolution decision
    AND status NOT IN (
      'Resolved', 'Cleared', 'Confirmed Ghost', 'For Termination'
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_notify_role(p_role text, p_title text, p_message text, p_ref_type text DEFAULT NULL::text, p_ref_id text DEFAULT NULL::text, p_deep_link text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO notifications (
    recipient_role, title, message,
    reference_type, reference_id,
    deep_link_route, is_read, created_at
  )
  VALUES (
    p_role, p_title, p_message,
    p_ref_type, p_ref_id,
    p_deep_link, FALSE, NOW()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_notify_separation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.separation_status IS NOT NULL
     AND OLD.separation_status IS DISTINCT FROM NEW.separation_status
  THEN
    PERFORM fn_notify_role(
      'HRCO',
      'Employee Separated',
      FORMAT('%s (%s) separated: %s', NEW.employee_name, NEW.employee_no, NEW.separation_status),
      'plantilla',
      NEW.id::TEXT,
      FORMAT('/plantilla/%s', NEW.id)
    );
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_notify_transfer_submitted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_account RECORD;
  v_encoder RECORD;
BEGIN
  IF NEW.status = 'Pending' THEN
    SELECT a.id, a.account_name, a.group_id
    INTO v_account
    FROM public.accounts a
    WHERE a.account_name = COALESCE(NEW.to_account, NEW.from_account)
       OR a.account_name = NEW.from_account
    ORDER BY CASE WHEN a.account_name = COALESCE(NEW.to_account, NEW.from_account) THEN 0 ELSE 1 END
    LIMIT 1;

    SELECT up.auth_user_id, up.role
    INTO v_encoder
    FROM public.users_profile up
    WHERE up.role = 'Encoder'
      AND up.is_active = true
      AND up.auth_user_id IS NOT NULL
      AND up.group_id = v_account.group_id
    LIMIT 1;

    IF v_encoder.auth_user_id IS NOT NULL THEN
      PERFORM public.notify_user(
        v_encoder.auth_user_id,
        'Encoder',
        'Transfer Request — ' || COALESCE(v_account.account_name, NEW.to_account, NEW.from_account),
        NEW.requested_by || ' has requested a transfer for ' || NEW.employee_name || ' from ' || NEW.from_account || ' to ' || NEW.to_account || '. Please review.',
        'submission',
        'transfer',
        'transfer',
        NEW.id::TEXT,
        FORMAT('/transfers/%s', NEW.id),
        NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_notify_vacancy_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('Filled', 'Closed') AND OLD.status = 'Open' THEN
    PERFORM fn_notify_role(
      'Recruitment',
      'Vacancy Approved',
      FORMAT('Vacancy %s (%s) has been approved.', NEW.vcode, NEW.position),
      'vacancy',
      NEW.id::TEXT,
      FORMAT('/vacancies/%s', NEW.id)
    );
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_notify_vcode_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.vcode IS NOT NULL AND (OLD.vcode IS NULL OR OLD.vcode <> NEW.vcode) THEN
    PERFORM fn_notify_role(
      'Encoder',
      'VCode Generated',
      FORMAT('VCode %s created for %s – %s', NEW.vcode, NEW.position, NEW.account),
      'vacancy',
      NEW.id::TEXT,
      FORMAT('/vacancies/%s', NEW.id)
    );
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link        record;
  v_link_status text;
BEGIN
  IF NEW.separation_status IN ('AWOL','Resigned','Endo','Others','Terminated','End of Contract')
     AND NEW.date_of_separation IS NOT NULL
     AND (
          OLD.separation_status IS DISTINCT FROM NEW.separation_status
          OR OLD.date_of_separation IS DISTINCT FROM NEW.date_of_separation
         )
  THEN

    IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

      v_link_status := CASE
        WHEN NEW.separation_status IN ('Resigned','AWOL','Terminated','End of Contract','Endo','Others')
          THEN 'Resigned'
        ELSE 'Backed Out'
      END;

      FOR v_link IN
        SELECT psl.id, psl.vacancy_id, psl.vcode
          FROM public.plantilla_store_links psl
         WHERE psl.plantilla_id = NEW.id
           AND psl.deleted_at IS NULL
           AND psl.status = 'Active'
      LOOP
        UPDATE public.plantilla_store_links
           SET status      = v_link_status,
               unlinked_at = now(),
               updated_at  = now()
         WHERE id = v_link.id;

        -- Reopen by vacancy_id; fall back to vcode when vacancy_id is NULL.
        IF v_link.vacancy_id IS NOT NULL THEN
          UPDATE public.vacancies
             SET status              = 'Open',
                 is_archived         = false,
                 archived_at         = NULL,
                 has_pending_closure = false,
                 vacant_date         = COALESCE(NEW.date_of_separation, CURRENT_DATE),
                 updated_at          = now()
           WHERE id = v_link.vacancy_id;
        ELSE
          UPDATE public.vacancies
             SET status              = 'Open',
                 is_archived         = false,
                 archived_at         = NULL,
                 has_pending_closure = false,
                 vacant_date         = COALESCE(NEW.date_of_separation, CURRENT_DATE),
                 updated_at          = now()
           WHERE vcode      = v_link.vcode
             AND deleted_at IS NULL;
        END IF;

      END LOOP;

      RETURN NEW;
    END IF;

    -- Stationary employee: reopen or create the single linked vacancy.
    PERFORM public.reopen_or_create_vacancy_for_plantilla(
      NEW.id,
      NEW.date_of_separation,
      'Backfill'
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_reconcile_ghost_employees()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_type_a  int;
  v_type_b  int;
BEGIN
  IF NOT (
    i_have_full_access()
    OR get_my_role() = 'Encoder'
  ) THEN
    RAISE EXCEPTION 'forbidden: Data Team role required'
      USING ERRCODE = '42501';
  END IF;

  v_type_a := public.fn_reconcile_ghost_type_a();
  v_type_b := public.fn_reconcile_ghost_type_b();

  -- Stamp last_revalidated_at on ALL still-open ghosts (audit trail)
  UPDATE public.possible_ghost_employees
  SET    last_revalidated_at = now(),
         updated_at          = now()
  WHERE  status NOT IN (
           'Resolved', 'Cleared', 'Confirmed Ghost', 'For Termination'
         );

  RETURN jsonb_build_object(
    'type_a_resolved',  v_type_a,
    'type_b_resolved',  v_type_b,
    'total_resolved',   v_type_a + v_type_b,
    'reconciled_at',    now()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_reconcile_ghost_type_a(p_employee_no text DEFAULT NULL::text, p_account text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count  int := 0;
  rec      record;
BEGIN
  FOR rec IN
    SELECT g.id, g.employee_no, g.account
    FROM   public.possible_ghost_employees g
    WHERE  g.ghost_type = 'Type A'
      AND  g.status NOT IN (
             'Resolved', 'Cleared', 'Confirmed Ghost', 'For Termination'
           )
      AND  (p_employee_no IS NULL OR g.employee_no = p_employee_no)
      AND  (p_account     IS NULL OR g.account     = p_account)
      -- Condition: employee_no now exists in Active Plantilla
      AND  EXISTS (
             SELECT 1
             FROM   public.plantilla p
             WHERE  p.employee_no    = g.employee_no
               AND  p.status         = 'Active'
               AND  p.deactivated_at IS NULL
           )
  LOOP
    PERFORM public.fn_mark_ghost_auto_resolved(
      rec.id,
      'Auto Resolved: Employee ' || rec.employee_no
        || ' found in Active Plantilla'
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_reconcile_ghost_type_b(p_import_log_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count  int := 0;
  rec      record;
BEGIN
  FOR rec IN
    SELECT DISTINCT g.id, g.employee_no, g.account
    FROM   public.possible_ghost_employees g
    WHERE  g.ghost_type = 'Type B'
      AND  g.status NOT IN (
             'Resolved', 'Cleared', 'Confirmed Ghost', 'For Termination'
           )
      AND  EXISTS (
             SELECT 1
             FROM   public.mika_import_rows  mr
             JOIN   public.mika_import_logs  ml  ON ml.id = mr.import_log_id
             WHERE  mr.employee_no  = g.employee_no
               -- Account must match (employee in the right account's import)
               AND  (g.account IS NULL OR mr.account = g.account)
               AND  ml.status       = 'Approved'
               -- Only imports submitted AFTER this ghost was raised
               AND  ml.created_at   > g.created_at
               -- If called from trigger, restrict to that specific import
               AND  (p_import_log_id IS NULL OR ml.id = p_import_log_id)
           )
  LOOP
    PERFORM public.fn_mark_ghost_auto_resolved(
      rec.id,
      'Auto Resolved: Employee ' || rec.employee_no
        || ' present in approved MIKA import'
        || CASE WHEN p_import_log_id IS NOT NULL
                THEN ' (' || p_import_log_id::text || ')'
                ELSE '' END
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_stores_sync_legacy_ins()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.area_province IS NULL AND NEW.province IS NOT NULL THEN NEW.area_province := NEW.province; END IF;
  IF NEW.province IS NULL AND NEW.area_province IS NOT NULL THEN NEW.province := NEW.area_province; END IF;
  IF NEW.status IS NULL THEN NEW.status := CASE WHEN COALESCE(NEW.is_active,true) THEN 'active' ELSE 'archived' END; END IF;
  IF NEW.is_active IS NULL THEN NEW.is_active := (NEW.status = 'active'); END IF;
  RETURN NEW;
END$function$
;

CREATE OR REPLACE FUNCTION public.fn_stores_sync_legacy_upd()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.area_province IS DISTINCT FROM OLD.area_province THEN
    NEW.province := NEW.area_province;
  ELSIF NEW.province IS DISTINCT FROM OLD.province THEN
    NEW.area_province := NEW.province;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.is_active := (NEW.status = 'active');
  ELSIF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
    NEW.status := CASE WHEN NEW.is_active THEN 'active' ELSE 'archived' END;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END$function$
;

CREATE OR REPLACE FUNCTION public.fn_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN NEW.updated_at := now(); RETURN NEW; END$function$
;

CREATE OR REPLACE FUNCTION public.fn_trigger_sla_breach()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'Resigned'
     and new.resignation_date is not null
     and (
       new.tagged_at is null
       or (new.tagged_at - new.resignation_date) > 3
     )
  then
    insert into public.sla_breach_logs (
      plantilla_id, employee_no, vcode, account,
      breach_type, resignation_date, tagged_date,
      days_elapsed, notified_om, created_at
    )
    values (
      new.id,
      new.employee_no,
      new.vcode,
      new.account,
      'resignation_not_tagged',
      new.resignation_date,
      new.tagged_at,
      coalesce(new.tagged_at - new.resignation_date, current_date - new.resignation_date),
      false,
      now()
    )
    on conflict (plantilla_id) do nothing;

    perform public.fn_notify_role(
      'OM',
      'SLA Breach',
      format('Employee %s (%s) resignation not tagged within 3 days.',
             new.employee_no, new.account),
      'plantilla',
      new.id::text,
      format('/plantilla/%s', new.id)
    );
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_vacancy_summary_counts(p_account_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_open_now int := 0;
  v_open_7d int := 0;
  v_pipeline_now int := 0;
  v_pipeline_7d int := 0;
  v_hired_now int := 0;
  v_hired_7d int := 0;
  v_trend_open numeric;
  v_trend_pipeline numeric;
  v_trend_hired numeric;
BEGIN
  -- Resolve account filter: if p_account_ids is null, use caller's scoped accounts (unless full access)
  IF p_account_ids IS NULL AND NOT i_have_full_access() THEN
    p_account_ids := get_user_account_ids();
  END IF;

  -- Open now: status = 'Open', not archived, no active applicants
  SELECT COUNT(DISTINCT v.id) INTO v_open_now
  FROM vacancies v
  WHERE v.deleted_at IS NULL
    AND (v.is_archived IS NULL OR v.is_archived = false)
    AND v.status = 'Open'
    AND (p_account_ids IS NULL OR v.account_id = ANY(p_account_ids))
    AND NOT EXISTS (
      SELECT 1 FROM applicants a WHERE a.vacancy_vcode = v.vcode
        AND (a.is_archived IS NULL OR a.is_archived = false)
        AND a.status NOT IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops', 'Confirmed Onboard')
    );

  -- Open 7 days ago: vacancies created before 7 days ago that are still Open now (approximation)
  SELECT COUNT(DISTINCT v.id) INTO v_open_7d
  FROM vacancies v
  WHERE v.deleted_at IS NULL
    AND v.created_at <= NOW() - INTERVAL '7 days'
    AND v.status = 'Open'
    AND (p_account_ids IS NULL OR v.account_id = ANY(p_account_ids))
    AND NOT EXISTS (
      SELECT 1 FROM applicants a WHERE a.vacancy_vcode = v.vcode
        AND (a.is_archived IS NULL OR a.is_archived = false)
        AND a.status NOT IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops', 'Confirmed Onboard')
        AND a.created_at <= NOW() - INTERVAL '7 days'
    );

  -- Pipeline now: has at least 1 active non-terminal applicant
  SELECT COUNT(DISTINCT v.id) INTO v_pipeline_now
  FROM vacancies v
  WHERE v.deleted_at IS NULL
    AND (v.is_archived IS NULL OR v.is_archived = false)
    AND v.status = 'Open'
    AND (p_account_ids IS NULL OR v.account_id = ANY(p_account_ids))
    AND EXISTS (
      SELECT 1 FROM applicants a WHERE a.vacancy_vcode = v.vcode
        AND (a.is_archived IS NULL OR a.is_archived = false)
        AND a.status NOT IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops', 'Confirmed Onboard')
    );

  -- Pipeline 7 days ago
  SELECT COUNT(DISTINCT v.id) INTO v_pipeline_7d
  FROM vacancies v
  WHERE v.deleted_at IS NULL
    AND v.created_at <= NOW() - INTERVAL '7 days'
    AND v.status = 'Open'
    AND (p_account_ids IS NULL OR v.account_id = ANY(p_account_ids))
    AND EXISTS (
      SELECT 1 FROM applicants a WHERE a.vacancy_vcode = v.vcode
        AND (a.is_archived IS NULL OR a.is_archived = false)
        AND a.status NOT IN ('Failed', 'Backout', 'Did Not Report', 'Rejected by Ops', 'Confirmed Onboard')
        AND a.created_at <= NOW() - INTERVAL '7 days'
    );

  -- Hired now: Confirmed Onboard in last 7 days
  SELECT COUNT(DISTINCT v.id) INTO v_hired_now
  FROM vacancies v
  JOIN applicants a ON a.vacancy_vcode = v.vcode
  WHERE v.deleted_at IS NULL
    AND (a.is_archived IS NULL OR a.is_archived = false)
    AND a.status = 'Confirmed Onboard'
    AND a.hired_at >= NOW() - INTERVAL '7 days'
    AND (p_account_ids IS NULL OR v.account_id = ANY(p_account_ids));

  -- Hired 7-14 days ago (previous window for trend comparison)
  SELECT COUNT(DISTINCT v.id) INTO v_hired_7d
  FROM vacancies v
  JOIN applicants a ON a.vacancy_vcode = v.vcode
  WHERE v.deleted_at IS NULL
    AND (a.is_archived IS NULL OR a.is_archived = false)
    AND a.status = 'Confirmed Onboard'
    AND a.hired_at >= NOW() - INTERVAL '14 days'
    AND a.hired_at < NOW() - INTERVAL '7 days'
    AND (p_account_ids IS NULL OR v.account_id = ANY(p_account_ids));

  -- Compute trend percents
  v_trend_open := CASE
    WHEN v_open_7d = 0 THEN NULL
    ELSE ROUND(((v_open_now - v_open_7d)::numeric / v_open_7d) * 100, 1)
  END;
  v_trend_pipeline := CASE
    WHEN v_pipeline_7d = 0 THEN NULL
    ELSE ROUND(((v_pipeline_now - v_pipeline_7d)::numeric / v_pipeline_7d) * 100, 1)
  END;
  v_trend_hired := CASE
    WHEN v_hired_7d = 0 THEN NULL
    ELSE ROUND(((v_hired_now - v_hired_7d)::numeric / v_hired_7d) * 100, 1)
  END;

  RETURN jsonb_build_object(
    'open_count',              v_open_now,
    'open_prev_count',         v_open_7d,
    'open_trend_percent',      v_trend_open,
    'open_trend_direction',    CASE WHEN v_open_7d = 0 THEN 'flat' WHEN v_open_now > v_open_7d THEN 'up' WHEN v_open_now < v_open_7d THEN 'down' ELSE 'flat' END,
    'pipeline_count',          v_pipeline_now,
    'pipeline_prev_count',     v_pipeline_7d,
    'pipeline_trend_percent',  v_trend_pipeline,
    'pipeline_trend_direction',CASE WHEN v_pipeline_7d = 0 THEN 'flat' WHEN v_pipeline_now > v_pipeline_7d THEN 'up' WHEN v_pipeline_now < v_pipeline_7d THEN 'down' ELSE 'flat' END,
    'hired_count',             v_hired_now,
    'hired_prev_count',        v_hired_7d,
    'hired_trend_percent',     v_trend_hired,
    'hired_trend_direction',   CASE WHEN v_hired_7d = 0 THEN 'flat' WHEN v_hired_now > v_hired_7d THEN 'up' WHEN v_hired_now < v_hired_7d THEN 'down' ELSE 'flat' END
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_validate_ph_contact_number(p_contact text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF p_contact IS NULL OR btrim(p_contact) = '' THEN
    RAISE EXCEPTION 'contact_number is required'
      USING ERRCODE = '22023';
  END IF;
  IF btrim(p_contact) !~ '^09[0-9]{9}$' THEN
    RAISE EXCEPTION 'contact_number must be an 11-digit PH mobile number starting with 09 (received: %)', p_contact
      USING ERRCODE = '22023';
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_batch_code()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_year text := to_char(now(), 'YYYY');
  v_seq int;
BEGIN
  SELECT COUNT(*) + 1 INTO v_seq
  FROM public.deactivation_requests
  WHERE EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM now());

  NEW.batch_code := 'DEAC-' || v_year || '-' || LPAD(v_seq::text, 3, '0');
  RETURN NEW;
END; $function$
;

CREATE OR REPLACE FUNCTION public.generate_daily_qa_report(p_report_date date DEFAULT CURRENT_DATE, p_environment text DEFAULT 'staging'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_health jsonb;
  v_top_modules jsonb;
  v_report_id uuid;
  v_total int := 0;
  v_passed int := 0;
  v_failed int := 0;
  v_blocked int := 0;
  v_cancelled int := 0;
  v_critical int := 0;
  v_high int := 0;
  v_medium int := 0;
  v_low int := 0;
  v_avg_runtime numeric;
  v_unstable text;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can generate QA reports';
  end if;

  select
    count(*),
    count(*) filter (where status = 'completed'),
    count(*) filter (where status = 'failed'),
    count(*) filter (where status = 'blocked'),
    count(*) filter (where status = 'cancelled'),
    avg(extract(epoch from (completed_at - started_at))) filter (where completed_at is not null and started_at is not null)
  into v_total, v_passed, v_failed, v_blocked, v_cancelled, v_avg_runtime
  from public.qa_agent_runs
  where date(coalesce(started_at, created_at) at time zone 'Asia/Manila') = p_report_date;

  select
    coalesce(count(*) filter (where severity = 'critical'), 0),
    coalesce(count(*) filter (where severity = 'high'), 0),
    coalesce(count(*) filter (where severity = 'medium'), 0),
    coalesce(count(*) filter (where severity = 'low'), 0)
  into v_critical, v_high, v_medium, v_low
  from public.qa_agent_findings f
  join public.qa_agent_runs r on r.id = f.run_id
  where date(coalesce(r.started_at, r.created_at) at time zone 'Asia/Manila') = p_report_date;

  select coalesce(jsonb_agg(jsonb_build_object('module', module_name, 'count', finding_count) order by finding_count desc), '[]'::jsonb)
  into v_top_modules
  from (
    select coalesce(f.module_name, 'unknown') as module_name, count(*) as finding_count
    from public.qa_agent_findings f
    join public.qa_agent_runs r on r.id = f.run_id
    where date(coalesce(r.started_at, r.created_at) at time zone 'Asia/Manila') = p_report_date
    group by coalesce(f.module_name, 'unknown')
    order by finding_count desc
    limit 5
  ) x;

  select module_name into v_unstable
  from (
    select coalesce(f.module_name, 'unknown') as module_name, count(*) as finding_count
    from public.qa_agent_findings f
    join public.qa_agent_runs r on r.id = f.run_id
    where date(coalesce(r.started_at, r.created_at) at time zone 'Asia/Manila') = p_report_date
    group by coalesce(f.module_name, 'unknown')
    order by finding_count desc
    limit 1
  ) y;

  v_health := public.calculate_qa_health_score(p_report_date, p_environment);

  insert into public.qa_daily_reports(
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
    health_score,
    health_status,
    generated_by
  ) values (
    p_report_date,
    p_environment,
    v_total,
    v_passed,
    v_failed,
    v_blocked,
    v_cancelled,
    v_critical,
    v_high,
    v_medium,
    v_low,
    v_top_modules,
    v_avg_runtime,
    v_unstable,
    (v_health ->> 'health_score')::numeric,
    v_health ->> 'health_status',
    get_current_profile_id()
  )
  on conflict (report_date, environment) do update set
    total_runs = excluded.total_runs,
    passed_runs = excluded.passed_runs,
    failed_runs = excluded.failed_runs,
    blocked_runs = excluded.blocked_runs,
    cancelled_runs = excluded.cancelled_runs,
    critical_count = excluded.critical_count,
    high_count = excluded.high_count,
    medium_count = excluded.medium_count,
    low_count = excluded.low_count,
    top_failed_modules = excluded.top_failed_modules,
    average_runtime_seconds = excluded.average_runtime_seconds,
    most_unstable_workflow = excluded.most_unstable_workflow,
    health_score = excluded.health_score,
    health_status = excluded.health_status,
    generated_by = excluded.generated_by,
    generated_at = now()
  returning id into v_report_id;

  if v_critical > 0 then
    perform public.create_qa_notification('critical', 'Critical QA findings detected', 'Daily QA report contains critical findings.', 'qa_daily_reports', v_report_id, 'Super Admin', jsonb_build_object('report_date', p_report_date, 'environment', p_environment));
  elsif v_high > 0 then
    perform public.create_qa_notification('high', 'High severity QA findings detected', 'Daily QA report contains high severity findings.', 'qa_daily_reports', v_report_id, 'Head Admin', jsonb_build_object('report_date', p_report_date, 'environment', p_environment));
  end if;

  return jsonb_build_object('report_id', v_report_id, 'report_date', p_report_date, 'environment', p_environment, 'health', v_health, 'top_failed_modules', v_top_modules);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_pool_vcode(p_pool_type_code text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_prefix   text;
  v_next_val bigint;
  v_vcode    text;
BEGIN
  SELECT vcode_prefix INTO v_prefix
  FROM public.workforce_pool_types
  WHERE code = p_pool_type_code AND is_active = true;

  IF v_prefix IS NULL THEN
    RAISE EXCEPTION 'Invalid or inactive pool type code: %', p_pool_type_code;
  END IF;

  INSERT INTO public.workforce_pool_vcode_sequences (prefix, last_val)
  VALUES (v_prefix, 1)
  ON CONFLICT (prefix)
  DO UPDATE SET last_val = public.workforce_pool_vcode_sequences.last_val + 1
  RETURNING last_val INTO v_next_val;

  v_vcode := v_prefix || '-GHQ-' || LPAD(v_next_val::text, 5, '0');

  IF EXISTS (SELECT 1 FROM public.vacancies WHERE vcode = v_vcode) THEN
    RAISE EXCEPTION 'VCODE collision detected: %. Contact SA.', v_vcode;
  END IF;

  RETURN v_vcode;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_vcode_for_account(p_account_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_account_name text;
  v_group_code text;
  v_account_initial text;
  v_prefix text;
  v_next_seq integer;
  v_vcode text;
begin
  select a.account_name, g.group_code
  into v_account_name, v_group_code
  from public.accounts a
  join public.groups g on g.id = a.group_id
  where a.id = p_account_id;

  if v_account_name is null then
    raise exception 'account not found for account_id: %', p_account_id;
  end if;

  if nullif(trim(coalesce(v_group_code, '')), '') is null then
    raise exception 'group_code not set for account_id: %', p_account_id;
  end if;

  v_account_initial := upper(left(regexp_replace(trim(v_account_name), '[^A-Za-z0-9]', '', 'g'), 1));

  if nullif(v_account_initial, '') is null then
    raise exception 'account initial could not be generated for account_id: %', p_account_id;
  end if;

  -- Current OHMployee VCODE format without chain:
  -- VC + AccountInitial + GroupCode + _ + 4-digit sequence
  -- Example: VCAG1_0001, VCBG1_0001
  v_prefix := 'VC' || v_account_initial || upper(trim(v_group_code));

  insert into public.vcode_sequences (prefix, last_seq, updated_at)
  values (v_prefix, 1, now())
  on conflict (prefix) do update
    set last_seq = public.vcode_sequences.last_seq + 1,
        updated_at = now()
  returning last_seq into v_next_seq;

  v_vcode := v_prefix || '_' || lpad(v_next_seq::text, 4, '0');

  while exists (select 1 from public.vacancies where vcode = v_vcode) loop
    update public.vcode_sequences
    set last_seq = last_seq + 1,
        updated_at = now()
    where prefix = v_prefix
    returning last_seq into v_next_seq;

    v_vcode := v_prefix || '_' || lpad(v_next_seq::text, 4, '0');
  end loop;

  return v_vcode;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_vcodes_for_request(p_vacancy_request_id uuid, p_account_code text, p_group_code text, p_slots integer)
 RETURNS TABLE(vcode_id uuid, vcode text, sequence_num integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_prefix        TEXT;
  v_seq           INT;
  v_vcode         TEXT;
  v_id            UUID;
  v_lock_key      BIGINT;
  v_generated     INT := 0;
  v_already       INT;
BEGIN
  -- Validate group_code
  IF p_group_code NOT IN ('G1','G2','G3','G4','G5') THEN
    RAISE EXCEPTION 'Invalid group_code: %. Must be G1–G5.', p_group_code;
  END IF;

  -- Validate slots
  IF p_slots < 1 OR p_slots > 100 THEN
    RAISE EXCEPTION 'slots must be between 1 and 100.';
  END IF;

  -- Guard: already fully generated
  SELECT COUNT(*) INTO v_already
  FROM vcodes
  WHERE vacancy_request_id = p_vacancy_request_id;

  IF v_already >= p_slots THEN
    RAISE EXCEPTION 'VCodes already fully generated for this request (% / %).', v_already, p_slots;
  END IF;

  -- Advisory lock — prevents race condition per scope
  v_lock_key := hashtext(p_account_code || '::' || p_group_code);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  v_prefix := p_account_code || '-' || p_group_code;

  LOOP
    EXIT WHEN v_generated >= p_slots;

    -- Atomic increment via vcode_sequences
    INSERT INTO vcode_sequences (prefix, last_seq, updated_at)
    VALUES (v_prefix, 1, NOW())
    ON CONFLICT (prefix) DO UPDATE
      SET last_seq   = vcode_sequences.last_seq + 1,
          updated_at = NOW()
    RETURNING last_seq INTO v_seq;

    v_vcode := v_prefix || '-' || LPAD(v_seq::TEXT, 4, '0');
    v_id    := gen_random_uuid();

    INSERT INTO vcodes (
      id, vacancy_request_id, account_code,
      group_code, sequence_number, vcode, status
    ) VALUES (
      v_id, p_vacancy_request_id, p_account_code,
      p_group_code, v_seq, v_vcode, 'available'
    );

    vcode_id     := v_id;
    vcode        := v_vcode;
    sequence_num := v_seq;
    RETURN NEXT;

    v_generated := v_generated + 1;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_vcodes_from_request(p_vacancy_request_id uuid)
 RETURNS TABLE(vcode_id uuid, vcode text, sequence_num integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_account_code  TEXT;
  v_group_code    TEXT;
  v_slots         INT;
  v_account_name  TEXT;
BEGIN
  -- Pull slots + account name from vacancy_request
  SELECT no_of_slots, account
  INTO v_slots, v_account_name
  FROM vacancy_requests
  WHERE id = p_vacancy_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vacancy request not found: %', p_vacancy_request_id;
  END IF;

  IF v_slots IS NULL OR v_slots < 1 THEN
    RAISE EXCEPTION 'no_of_slots is null or invalid on this request.';
  END IF;

  -- Resolve account_code + group_code from account name
  SELECT a.account_code, g.group_code
  INTO v_account_code, v_group_code
  FROM accounts a
  JOIN groups g ON a.group_id = g.id
  WHERE LOWER(TRIM(a.account_name)) = LOWER(TRIM(v_account_name))
  LIMIT 1;

  IF v_account_code IS NULL THEN
    RAISE EXCEPTION 'Cannot resolve account_code for account: "%". Check accounts table.', v_account_name;
  END IF;

  -- Delegate to core generator
  RETURN QUERY
  SELECT r.vcode_id, r.vcode, r.sequence_num
  FROM generate_vcodes_for_request(
    p_vacancy_request_id,
    v_account_code,
    v_group_code,
    v_slots
  ) r;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_accounts_by_group(p_group_id uuid)
 RETURNS TABLE(account_id uuid, account_name text, account_code text, group_id uuid, group_name text, is_active boolean)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT a.id, a.account_name, a.account_code, a.group_id, g.group_name, a.is_active
  FROM public.accounts a
  JOIN public.groups   g ON g.id = a.group_id
  WHERE a.group_id  = p_group_id
    AND a.is_active = true
  ORDER BY a.account_name;
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

CREATE OR REPLACE FUNCTION public.get_applicant_next_destination(p_applicant_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with app as (
    select a.id, a.full_name, a.vacancy_vcode, a.roving_assignment_id
    from public.applicants a
    where a.id = p_applicant_id
      and coalesce(a.is_archived, false) = false
  ), vac as (
    select v.vcode, v.account
    from public.vacancies v
    join app on app.vacancy_vcode = v.vcode
    where v.deleted_at is null
    limit 1
  ), roving_plantilla as (
    select 1 as found
    from app
    join public.plantilla p on p.roving_assignment_id = app.roving_assignment_id
    where app.roving_assignment_id is not null
      and p.is_deleted = false
      and p.status in ('Active', 'For Deactivation', 'On Leave')
    limit 1
  ), name_plantilla as (
    select 1 as found
    from app
    left join vac on true
    join public.plantilla p on lower(trim(p.employee_name)) = lower(trim(app.full_name))
    where p.is_deleted = false
      and p.employee_no is not null
      and p.status in ('Active', 'For Deactivation', 'On Leave')
      and (vac.account is null or p.account = vac.account)
    limit 1
  )
  select case
    when exists (select 1 from roving_plantilla) then 'plantilla'
    when exists (select 1 from name_plantilla) then 'plantilla'
    else 'hr_emploc'
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_applicant_workflow_action_label(p_applicant_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case public.get_applicant_next_destination(p_applicant_id)
    when 'plantilla' then 'Deploy to Plantilla'
    else 'Transfer to HR Emploc'
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_correction_requests_scoped(p_hr_emploc_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, hr_emploc_id uuid, applicant_id uuid, applicant_name text, group_id uuid, account_id uuid, assigned_hrco_id uuid, assigned_hrco_name text, requested_by uuid, requested_by_name text, requested_at timestamp with time zone, issue_type text, hr_remarks text, additional_remarks text, hrco_notes text, ops_update_message text, status text, sla_status text, allows_attachment boolean, last_updated_at timestamp with time zone, reviewed_by uuid, reviewed_at timestamp with time zone, reopened_at timestamp with time zone, for_review_at timestamp with time zone, ready_at timestamp with time zone, attachment_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_my_id   uuid := public.get_my_profile_id();
  v_my_role text := public.get_my_role();
BEGIN
  IF v_my_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      he.*,
      CASE
        WHEN he.hr_status = 'For Correction' THEN 'for_correction'
        WHEN he.hr_status = 'For Review' THEN 'for_review'
        WHEN he.hr_status = 'Complete'
             AND (NULLIF(BTRIM(COALESCE(he.employee_no, '')), '') IS NOT NULL
                  OR NULLIF(BTRIM(COALESCE(he.emploc_no, '')), '') IS NOT NULL)
          THEN 'ready'
        WHEN he.hr_status = 'Complete' THEN 'for_review'
        ELSE 'for_review'
      END AS mapped_status
    FROM public.hr_emploc he
    WHERE he.deleted_at IS NULL
      AND he.correction_reason IS NOT NULL
  )
  SELECT
    he.id                                                              AS id,
    he.id                                                              AS hr_emploc_id,
    he.applicant_id                                                    AS applicant_id,
    COALESCE(he.applicant_name_snapshot, he.applicant_name)            AS applicant_name,
    a.group_id                                                         AS group_id,
    he.account_id                                                      AS account_id,
    he.hrco_user_id_snapshot                                           AS assigned_hrco_id,
    hrco.full_name                                                     AS assigned_hrco_name,
    he.updated_by                                                      AS requested_by,
    he.hr_reviewed_by                                                  AS requested_by_name,
    COALESCE(he.hr_reviewed_at, he.updated_at)                         AS requested_at,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN COALESCE(he.correction_reason->0->>'code', 'OTHER')
      ELSE COALESCE(he.correction_reason->>'type', 'OTHER')
    END                                                                AS issue_type,

    COALESCE(he.hr_remarks, '')                                        AS hr_remarks,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN he.correction_reason->0->>'comment'
      ELSE he.correction_reason->>'comment'
    END                                                                AS additional_remarks,

    he.ops_remarks                                                     AS hrco_notes,
    he.ops_remarks                                                     AS ops_update_message,
    he.mapped_status                                                   AS status,
    'normal'::text                                                     AS sla_status,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN EXISTS (
        SELECT 1
          FROM jsonb_array_elements(he.correction_reason) el
          JOIN public.hr_emploc_issue_types it ON it.code = el->>'code'
         WHERE it.allows_attachment = true
      )
      ELSE COALESCE(he.correction_reason->>'type', '') <> 'INVALID_BENEFITS'
    END                                                                AS allows_attachment,

    he.updated_at                                                      AS last_updated_at,
    NULL::uuid                                                         AS reviewed_by,
    NULL::timestamptz                                                  AS reviewed_at,
    NULL::timestamptz                                                  AS reopened_at,
    CASE WHEN he.mapped_status = 'for_review' THEN he.updated_at ELSE NULL::timestamptz END AS for_review_at,
    CASE WHEN he.mapped_status = 'ready' THEN he.updated_at ELSE NULL::timestamptz END      AS ready_at,

    COALESCE((
      SELECT COUNT(*)
        FROM public.hr_emploc_correction_attachments atch
       WHERE atch.hr_emploc_id = he.id AND atch.is_deleted = false
    ), 0)::bigint                                                      AS attachment_count

  FROM scoped he
  LEFT JOIN public.accounts a ON a.id = he.account_id
  LEFT JOIN public.users_profile hrco ON hrco.id = he.hrco_user_id_snapshot
  WHERE
    (v_my_role NOT IN ('hrco') OR he.hrco_user_id_snapshot = v_my_id)
    AND (p_hr_emploc_id IS NULL OR he.id = p_hr_emploc_id)
    AND (p_status IS NULL OR he.mapped_status = p_status)
  ORDER BY he.updated_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_correction_timeline(p_correction_request_id uuid)
 RETURNS TABLE(event_id uuid, event_type text, event_label text, status_from text, status_to text, remarks text, actor_id uuid, actor_name text, has_attachment boolean, attachment_filename text, attachment_size_bytes bigint, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_my_id      uuid := public.get_my_profile_id();
  v_role_level int  := public.get_my_role_level();
  v_account    text;
BEGIN
  -- ── Auth gate ────────────────────────────────────────────
  IF v_my_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  IF v_role_level < 10 THEN
    RAISE EXCEPTION 'insufficient privileges' USING ERRCODE = '42501';
  END IF;

  -- ── Scope gate ───────────────────────────────────────────
  SELECT he.account INTO v_account
  FROM public.hr_emploc he
  WHERE he.id = p_correction_request_id
    AND he.deleted_at IS NULL;

  -- Record not found or deleted — return empty safely
  IF v_account IS NULL THEN
    RETURN;
  END IF;

  -- Scoped roles must own this account
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_account = ANY(public.get_my_allowed_accounts())) THEN
      RETURN;
    END IF;
  END IF;

  -- ── Timeline ─────────────────────────────────────────────
  RETURN QUERY
  WITH deduped_audit AS (
    -- Deduplicate: audit_logs writes both 'hr_emploc' + 'HR_EMPLOC' per event
    -- Keep one row per (record_id, timestamp, action, new hr_status)
    SELECT DISTINCT ON (
      al.record_id,
      al.timestamp,
      al.action,
      al.new_data ->> 'hr_status'
    )
      al.id,
      al.actor_id,
      al.action::text           AS action,
      al.old_data ->> 'hr_status' AS st_from,
      al.new_data ->> 'hr_status' AS st_to,
      COALESCE(
        NULLIF(TRIM(al.new_data ->> 'hr_remarks'), ''),
        NULLIF(TRIM(al.new_data ->> 'ops_remarks'), '')
      )                          AS ev_remarks,
      al.timestamp               AS ev_at
    FROM public.audit_logs al
    WHERE al.module ILIKE 'hr_emploc'
      AND al.record_id = p_correction_request_id
      AND al.action::text IN ('INSERT', 'UPDATE')
    ORDER BY
      al.record_id,
      al.timestamp,
      al.action,
      al.new_data ->> 'hr_status',
      al.id  -- tiebreak by id for stability
  ),
  audit_events AS (
    SELECT
      da.id                                          AS event_id,
      da.actor_id,
      COALESCE(up.full_name, da.actor_id::text)      AS actor_name,
      da.st_from,
      da.st_to,
      da.ev_remarks,
      da.ev_at,
      CASE
        WHEN da.action = 'INSERT'
          THEN 'record_created'
        WHEN da.st_to = 'For Correction'
          AND da.st_from IS DISTINCT FROM 'For Correction'
          AND da.st_from IS DISTINCT FROM 'For Review'
          THEN 'flagged_for_correction'
        WHEN da.st_to = 'For Correction'
          AND da.st_from = 'For Review'
          THEN 'rejected'
        WHEN da.st_to = 'For Review'
          AND da.st_from = 'For Correction'
          THEN 'correction_submitted'
        WHEN da.st_to = 'Complete'
          AND da.st_from IN ('For Review', 'For Correction')
          THEN 'approved'
        WHEN da.st_to = 'For Correction'
          AND da.st_from = 'For Correction'
          THEN 'hrco_updated'
        ELSE 'status_updated'
      END                                            AS ev_type
    FROM deduped_audit da
    LEFT JOIN public.users_profile up ON up.id = da.actor_id
  ),
  attachment_events AS (
    SELECT
      ca.id                                          AS event_id,
      ca.uploaded_by                                 AS actor_id,
      COALESCE(up.full_name, ca.uploaded_by::text)   AS actor_name,
      ca.original_filename,
      ca.size_bytes,
      ca.uploaded_at                                 AS ev_at
    FROM public.hr_emploc_correction_attachments ca
    LEFT JOIN public.users_profile up ON up.id = ca.uploaded_by
    WHERE ca.hr_emploc_id = p_correction_request_id
      AND ca.is_deleted = false
  )

  -- Audit events
  SELECT
    ae.event_id,
    ae.ev_type                                       AS event_type,
    CASE ae.ev_type
      WHEN 'record_created'        THEN 'Record Created'
      WHEN 'flagged_for_correction' THEN 'Flagged for Correction'
      WHEN 'correction_submitted'  THEN 'Correction Submitted'
      WHEN 'approved'              THEN 'Correction Approved'
      WHEN 'rejected'              THEN 'Correction Rejected'
      WHEN 'hrco_updated'          THEN 'HRCO Updated Remarks'
      ELSE                              'Status Updated'
    END                                              AS event_label,
    ae.st_from                                       AS status_from,
    ae.st_to                                         AS status_to,
    ae.ev_remarks                                    AS remarks,
    ae.actor_id,
    ae.actor_name,
    false                                            AS has_attachment,
    NULL::text                                       AS attachment_filename,
    NULL::bigint                                     AS attachment_size_bytes,
    ae.ev_at                                         AS created_at
  FROM audit_events ae

  UNION ALL

  -- Attachment events
  SELECT
    aev.event_id,
    'attachment_uploaded'                            AS event_type,
    'Attachment Uploaded'                            AS event_label,
    NULL::text,
    NULL::text,
    aev.original_filename                            AS remarks,
    aev.actor_id,
    aev.actor_name,
    true                                             AS has_attachment,
    aev.original_filename                            AS attachment_filename,
    aev.size_bytes                                   AS attachment_size_bytes,
    aev.ev_at                                        AS created_at
  FROM attachment_events aev

  ORDER BY created_at ASC NULLS LAST;

END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_current_profile_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT id FROM users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true
  LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.get_current_user_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select public.get_effective_role();
$function$
;

CREATE OR REPLACE FUNCTION public.get_effective_account_ids()
 RETURNS uuid[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_session public.acting_sessions;
    v_accounts uuid[];
begin
    select * into v_session
    from public.get_active_acting_session();

    if v_session.id is not null
       and coalesce(array_length(v_session.acting_account_ids, 1), 0) > 0 then
        return v_session.acting_account_ids;
    end if;

    select coalesce(array_agg(distinct us.account_id), '{}')
    into v_accounts
    from public.user_scopes us
    join public.users_profile up on up.id = us.user_id
    where up.auth_user_id = auth.uid()
      and us.account_id is not null;

    return coalesce(v_accounts, '{}');
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_effective_group_ids()
 RETURNS uuid[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_session public.acting_sessions;
    v_groups uuid[];
begin
    select * into v_session
    from public.get_active_acting_session();

    if v_session.id is not null
       and coalesce(array_length(v_session.acting_group_ids, 1), 0) > 0 then
        return v_session.acting_group_ids;
    end if;

    select coalesce(array_agg(distinct us.group_id), '{}')
    into v_groups
    from public.user_scopes us
    join public.users_profile up on up.id = us.user_id
    where up.auth_user_id = auth.uid()
      and us.group_id is not null;

    return coalesce(v_groups, '{}');
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_effective_role()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_session public.acting_sessions;
    v_role text;
begin
    select * into v_session
    from public.get_active_acting_session();

    if v_session.id is not null then
        return v_session.acting_role;
    end if;

    select r.role_name
    into v_role
    from public.users_profile up
    left join public.roles r on r.id = up.role_id
    where up.auth_user_id = auth.uid()
      and coalesce(up.is_active, true)
    limit 1;

    return coalesce(v_role, 'Unknown');
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_hc_allowed_positions(p_account_id uuid)
 RETURNS TABLE(position_id uuid, position_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id as position_id,
         p.position_name
  from public.account_positions ap
  join public.positions p on p.id = ap.position_id
  join public.accounts a on a.id = ap.account_id
  where ap.account_id = p_account_id
    and coalesce(p.is_active, true) = true
    and coalesce(a.is_active, true) = true
  order by p.position_name;
$function$
;

CREATE OR REPLACE FUNCTION public.get_hr_emploc_filter_counts(p_account text DEFAULT NULL::text)
 RETURNS TABLE(status_label text, hr_status text, record_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT
    status || ' / ' || hr_status AS status_label,
    hr_status,
    COUNT(*) AS record_count
  FROM hr_emploc
  WHERE (p_account IS NULL OR account = p_account)
    AND account = ANY(get_my_allowed_accounts()) OR i_have_full_access()
  GROUP BY status, hr_status
  ORDER BY record_count DESC;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_allowed_accounts()
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level int;
  v_profile_id uuid;
  v_scope_type text;
  v_account_count int;
BEGIN
  v_role_level := public.get_my_role_level();
  v_profile_id := public.get_my_profile_id();
  v_scope_type := public.get_my_scope_type();

  IF v_profile_id IS NULL THEN
    RETURN ARRAY[]::text[];
  END IF;

  IF v_scope_type = 'global' OR COALESCE(v_role_level, 0) >= 90 THEN
    RETURN ARRAY(
      SELECT a.account_name
      FROM public.accounts a
      WHERE a.is_active = true
      ORDER BY a.account_name
    );
  END IF;

  SELECT COUNT(*)
  INTO v_account_count
  FROM public.user_scopes
  WHERE user_id = v_profile_id
    AND account_id IS NOT NULL;

  IF v_account_count > 0 THEN
    RETURN ARRAY(
      SELECT DISTINCT a.account_name
      FROM public.accounts a
      JOIN public.user_scopes us ON us.account_id = a.id
      WHERE us.user_id = v_profile_id
        AND a.is_active = true

      UNION

      SELECT DISTINCT a2.account_name
      FROM public.accounts a2
      JOIN public.groups g ON g.id = a2.group_id
      JOIN public.temp_permission_overrides tpo
        ON g.group_name = ANY(tpo.additional_groups)
      WHERE tpo.user_id = v_profile_id
        AND tpo.is_active = true
        AND (tpo.expires_at IS NULL OR tpo.expires_at > now())
        AND tpo.revoked_at IS NULL
        AND a2.is_active = true
    );
  END IF;

  RETURN ARRAY(
    SELECT DISTINCT a.account_name
    FROM public.accounts a
    JOIN public.user_scopes us ON us.group_id = a.group_id
    WHERE us.user_id = v_profile_id
      AND a.is_active = true

    UNION

    SELECT DISTINCT a2.account_name
    FROM public.accounts a2
    JOIN public.groups g ON g.id = a2.group_id
    JOIN public.temp_permission_overrides tpo
      ON g.group_name = ANY(tpo.additional_groups)
    WHERE tpo.user_id = v_profile_id
      AND tpo.is_active = true
      AND (tpo.expires_at IS NULL OR tpo.expires_at > now())
      AND tpo.revoked_at IS NULL
      AND a2.is_active = true
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_full_name()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT full_name FROM public.users_profile
  WHERE auth_user_id = auth.uid()
  LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_group_id()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid;
  v_group_id    uuid;
BEGIN
  v_profile_id := public.get_my_profile_id();
  IF v_profile_id IS NULL THEN RETURN NULL; END IF;

  -- Primary: user_scopes group assignment
  SELECT us.group_id INTO v_group_id
  FROM public.user_scopes us
  WHERE us.user_id = v_profile_id
    AND us.group_id IS NOT NULL
  LIMIT 1;

  IF v_group_id IS NOT NULL THEN RETURN v_group_id; END IF;

  -- Fallback: users_profile.group_id
  SELECT up.group_id INTO v_group_id
  FROM public.users_profile up
  WHERE up.id = v_profile_id;

  RETURN v_group_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_profile_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT id FROM public.users_profile
  WHERE auth_user_id = auth.uid()
  LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_role()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    return public.get_effective_role();
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_role_level()
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
begin
  v_role := public.get_my_role();

  return case v_role
    when 'Super Admin'       then 100
    when 'Head Admin'        then 90
    when 'Operations Manager'then 70
    when 'OM'                then 70
    when 'HRCO'              then 45
    when 'ATL/TL'            then 40
    when 'ATL'               then 42
    when 'TL'                then 41
    when 'Encoder'           then 30
    when 'HR Personnel'      then 25   -- FIXED: was 60, inside ops range 40-70
    when 'Recruitment Team'  then 20   -- ADDED: was missing (returned 0)
    when 'Recruitment'       then 20   -- legacy alias
    when 'Back Office'       then 15
    when 'Backoffice'        then 15
    when 'Viewer'            then 10
    else 0
  end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_scope_type()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_scope_type text;
  v_role_level int;
BEGIN
  SELECT up.scope_type, r.role_level
  INTO v_scope_type, v_role_level
  FROM public.users_profile up
  LEFT JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid()
    AND up.is_active = true
  LIMIT 1;

  IF COALESCE(v_role_level, 0) >= 90 THEN
    RETURN 'global';
  END IF;

  RETURN COALESCE(v_scope_type, 'scoped');
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_scoped_accounts()
 RETURNS TABLE(account_id uuid, account_name text, account_code text, group_id uuid, group_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_role_level int;
    v_scope_type text;
    v_effective_accounts uuid[];
    v_effective_groups uuid[];
begin
    v_role_level := public.get_my_role_level();
    v_scope_type := public.get_my_scope_type();
    v_effective_accounts := public.get_effective_account_ids();
    v_effective_groups := public.get_effective_group_ids();

    if v_scope_type = 'global' or coalesce(v_role_level, 0) >= 90 then
        return query
        select distinct
            a.id,
            a.account_name,
            a.account_code,
            a.group_id,
            g.group_name
        from public.accounts a
        join public.groups g on g.id = a.group_id
        where a.is_active = true
        order by g.group_name, a.account_name;
        return;
    end if;

    if coalesce(array_length(v_effective_accounts, 1), 0) > 0 then
        return query
        select distinct
            a.id,
            a.account_name,
            a.account_code,
            a.group_id,
            g.group_name
        from public.accounts a
        join public.groups g on g.id = a.group_id
        where a.id = any(v_effective_accounts)
          and a.is_active = true
        order by g.group_name, a.account_name;
        return;
    end if;

    return query
    select distinct
        a.id,
        a.account_name,
        a.account_code,
        a.group_id,
        g.group_name
    from public.accounts a
    join public.groups g on g.id = a.group_id
    where a.group_id = any(v_effective_groups)
      and a.is_active = true
    order by g.group_name, a.account_name;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_scoped_vcodes()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT ARRAY(
    SELECT v.vcode
    FROM public.vacancies v
    WHERE v.account = ANY(public.get_my_allowed_accounts())
      AND v.deleted_at IS NULL
    -- NOTE: intentionally includes is_archived=true, status=Filled/Closed/Archived
    -- so hired applicants remain visible after vacancy auto-archival
  );
$function$
;

CREATE OR REPLACE FUNCTION public.get_plantilla_employees(p_store_id uuid, p_status_filter text DEFAULT 'all'::text)
 RETURNS TABLE(id uuid, employee_name text, employee_no text, emploc_no text, vcode text, position_name text, deployment_type text, account text, store_name text, status text, separation_status text, inactive_at timestamp with time zone, for_deactivation_at timestamp with time zone, deactivated_at timestamp with time zone, deactivated_visible_until timestamp with time zone, sla_status text, sla_due_date date, can_reassign_store boolean, can_resign boolean, can_endo boolean, can_separate boolean, can_request_deactivation boolean, can_complete_deactivation boolean, can_view_benefits boolean, can_sync_mika boolean, can_reveal_benefits boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role          text    := public.get_my_role();
  v_is_ops        boolean := public.i_am_ops();
  v_is_full       boolean := public.i_have_full_access();
  v_is_backoffice boolean := v_role IN ('Back Office', 'Backoffice');
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.employee_name,
    p.employee_no,
    p.emploc_no,
    p.vcode,
    p.position::text,
    p.deployment_type,
    p.account,
    p.store_name,
    p.status,
    p.separation_status,
    p.inactive_at,
    p.for_deactivation_at,
    p.deactivated_at,
    p.deactivated_visible_until,
    CASE
      WHEN p.status = 'Inactive' AND p.inactive_at < NOW() - INTERVAL '3 days'
        THEN 'breach_inactive_no_request'
      WHEN p.status = 'For Deactivation' AND p.for_deactivation_at < NOW() - INTERVAL '3 days'
        THEN 'breach_deactivation_overdue'
      WHEN p.status IN ('Inactive', 'For Deactivation') THEN 'within_sla'
      ELSE NULL
    END,
    CASE
      WHEN p.status = 'Inactive'         THEN (p.inactive_at + INTERVAL '3 days')::date
      WHEN p.status = 'For Deactivation' THEN (p.for_deactivation_at + INTERVAL '3 days')::date
      ELSE NULL
    END,
    (v_is_full OR (v_is_ops AND p.status = 'Active')),
    (v_is_full OR (v_is_ops AND p.status = 'Active')),
    (v_is_full OR (v_is_ops AND p.status = 'Active')),
    (v_is_full OR (v_is_ops AND p.status = 'Active')),
    (v_is_full OR (v_is_ops AND p.status = 'Inactive')),
    ((v_is_backoffice OR v_is_full) AND p.status = 'For Deactivation'),
    true,
    (v_is_full OR v_is_ops OR v_is_backoffice),
    (v_is_full OR v_is_ops OR v_is_backoffice)
  FROM public.plantilla p
  WHERE p.store_id = p_store_id
    AND (
      v_is_full
      OR p.account = ANY (public.get_my_allowed_accounts())
    )
    AND (
      CASE LOWER(p_status_filter)
        WHEN 'all'              THEN p.status IN ('Active', 'Inactive', 'For Deactivation', 'Deactivated')
                                     AND (p.status <> 'Deactivated'
                                          OR p.deactivated_visible_until > NOW())
        WHEN 'active'           THEN p.status = 'Active'
        WHEN 'inactive'         THEN p.status = 'Inactive'
                                     AND p.source_headcount_request_id IS NULL
        WHEN 'for_deactivation' THEN p.status = 'For Deactivation'
        WHEN 'deactivated'      THEN p.status = 'Deactivated'
                                     AND p.deactivated_visible_until > NOW()
        ELSE true
      END
    )
  ORDER BY
    CASE p.status
      WHEN 'Active'          THEN 1
      WHEN 'Inactive'        THEN 2
      WHEN 'For Deactivation' THEN 3
      WHEN 'Deactivated'     THEN 4
      ELSE 5
    END,
    p.employee_name;
END$function$
;

CREATE OR REPLACE FUNCTION public.get_plantilla_scope_menu()
 RETURNS TABLE(scope_type text, scope_id uuid, label text, sort_order integer, can_view boolean, can_manage boolean, can_view_only boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role          text := public.get_my_role();
  v_profile_id    uuid := public.get_current_profile_id();
  v_acct_count    int;
  v_can_manage    boolean;
  v_can_view_only boolean;
BEGIN
  v_can_manage    := v_role IN ('Super Admin','Head Admin','HRCO','ATL','TL','Operations Manager','OM');
  v_can_view_only := NOT v_can_manage
                     AND v_role NOT IN ('Recruitment','Recruitment Team','HR Dept','HR Department','HR Personnel');

  -- Super Admin / Head Admin
  IF public.i_have_full_access() THEN
    RETURN QUERY
      SELECT 'group'::text, g.id, g.group_name,
             ROW_NUMBER() OVER (ORDER BY g.group_code)::int,
             true, true, false
      FROM public.groups g ORDER BY g.group_code;
    RETURN;
  END IF;

  -- Recruitment / HR Dept: no access
  IF public.i_am_recruitment() OR public.i_am_hr_dept() THEN
    RETURN;
  END IF;

  -- OM / Operations Manager: scoped groups
  IF v_role IN ('OM','Operations Manager') THEN
    RETURN QUERY
      SELECT 'group'::text, g.id, g.group_name,
             ROW_NUMBER() OVER (ORDER BY g.group_code)::int,
             true, true, false
      FROM public.user_scopes us
      JOIN public.groups g ON g.id = us.group_id
      WHERE us.user_id = v_profile_id AND us.group_id IS NOT NULL
      ORDER BY g.group_code;
    RETURN;
  END IF;

  -- All other roles (Encoder, HRCO/ATL/TL scoped, Viewer, Back Office)
  SELECT COUNT(*) INTO v_acct_count
  FROM public.user_scopes
  WHERE user_id = v_profile_id AND account_id IS NOT NULL;

  IF v_acct_count > 0 THEN
    RETURN QUERY
      SELECT 'account'::text, a.id, a.account_name,
             ROW_NUMBER() OVER (ORDER BY a.account_name)::int,
             true, v_can_manage, v_can_view_only
      FROM public.user_scopes us
      JOIN public.accounts a ON a.id = us.account_id
      WHERE us.user_id = v_profile_id AND us.account_id IS NOT NULL AND a.is_active = true
      ORDER BY a.account_name;
  ELSE
    RETURN QUERY
      SELECT 'account'::text, a.id, a.account_name,
             ROW_NUMBER() OVER (ORDER BY a.account_name)::int,
             true, v_can_manage, v_can_view_only
      FROM public.user_scopes us
      JOIN public.accounts a ON a.group_id = us.group_id
      WHERE us.user_id = v_profile_id AND us.group_id IS NOT NULL
        AND us.account_id IS NULL AND a.is_active = true
      ORDER BY a.account_name;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_plantilla_store_cards(p_scope_type text, p_scope_id uuid)
 RETURNS TABLE(store_id uuid, store_name text, account text, group_name text, active_count integer, total_count integer, inactive_count integer, for_deactivation_count integer, deactivated_visible_count integer, vacancy_count integer, mfr_percentage numeric, mfr_status text, can_open boolean, can_request_headcount boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_role text := public.get_my_role();
BEGIN
  RETURN QUERY
  WITH base_stores AS (
    SELECT s.id AS s_id, s.store_name AS s_name, a.account_name AS acc_name, g.group_name AS grp_name
    FROM public.stores s
    JOIN public.accounts a ON a.id = s.account_id
    JOIN public.groups   g ON g.id = a.group_id
    WHERE
      CASE p_scope_type
        WHEN 'group'   THEN a.group_id = p_scope_id
        WHEN 'account' THEN s.account_id = p_scope_id
        WHEN 'store'   THEN s.id        = p_scope_id
        ELSE true
      END
      AND (
        public.i_have_full_access()
        OR a.account_name = ANY (public.get_my_allowed_accounts())
      )
  ),
  agg AS (
    SELECT
      bs.s_id, bs.s_name, bs.acc_name, bs.grp_name,
      COUNT(*) FILTER (WHERE p.status = 'Active')                  AS active_cnt,
      COUNT(*) FILTER (WHERE p.status = 'Inactive')                AS inactive_cnt,
      COUNT(*) FILTER (WHERE p.status = 'For Deactivation')        AS for_deact_cnt,
      COUNT(*) FILTER (WHERE p.status = 'Deactivated'
                          AND p.deactivated_visible_until > NOW()) AS deact_visible_cnt,
      COUNT(*) FILTER (WHERE p.status IN
        ('Active','Inactive','For Deactivation'))                  AS slot_total
    FROM base_stores bs
    LEFT JOIN public.plantilla p ON p.store_id = bs.s_id
    GROUP BY bs.s_id, bs.s_name, bs.acc_name, bs.grp_name
  ),
  vacs AS (
    SELECT v.store_id, COUNT(*)::int AS vac_cnt
    FROM public.vacancies v
    WHERE v.status = 'Open' AND COALESCE(v.is_archived,false)=false AND v.deleted_at IS NULL
    GROUP BY v.store_id
  )
  SELECT
    a.s_id,
    a.s_name,
    a.acc_name,
    a.grp_name,
    a.active_cnt::int,
    a.slot_total::int,
    a.inactive_cnt::int,
    a.for_deact_cnt::int,
    a.deact_visible_cnt::int,
    COALESCE(v.vac_cnt, 0),
    CASE WHEN a.slot_total = 0 THEN 0
         ELSE ROUND((a.active_cnt::numeric / a.slot_total) * 100, 2) END,
    CASE WHEN a.slot_total = 0 THEN 'red'
         WHEN (a.active_cnt::numeric/a.slot_total) >= 0.85 THEN 'green'
         WHEN (a.active_cnt::numeric/a.slot_total) >= 0.70 THEN 'amber'
         ELSE 'red' END,
    true,
    (v_role IN ('OM','Operations Manager','HRCO','ATL','TL','Super Admin','Head Admin'))
  FROM agg a
  LEFT JOIN vacs v ON v.store_id = a.s_id
  ORDER BY a.acc_name, a.s_name;
END$function$
;

CREATE OR REPLACE FUNCTION public.get_positions_by_account(p_account_id uuid)
 RETURNS TABLE(position_id uuid, position_name text, position_code text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select
    v.position_id,
    v.position_name,
    v.position_code
  from public.v_account_position_options v
  where v.account_id = p_account_id
  order by v.position_name;
$function$
;

CREATE OR REPLACE FUNCTION public.get_recent_activity_feed(p_limit integer DEFAULT 10)
 RETURNS TABLE(id uuid, actor_id uuid, actor_name text, actor_role text, avatar_url text, action text, target_table text, target_id uuid, target_name text, old_value jsonb, new_value jsonb, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    al.id,
    al.actor_id,
    COALESCE(up.full_name, al.actor_name) AS actor_name,
    COALESCE(r.role_name,  al.actor_role) AS actor_role,
    NULL::text                            AS avatar_url,
    al.action,
    al.target_table,
    al.target_id,
    al.target_name,
    al.old_value,
    al.new_value,
    al.created_at
  FROM public.activity_log al
  LEFT JOIN public.users_profile up ON up.id = al.actor_id
  LEFT JOIN public.roles         r  ON r.id  = up.role_id
  ORDER BY al.created_at DESC
  LIMIT GREATEST(1, COALESCE(p_limit, 10));
$function$
;

CREATE OR REPLACE FUNCTION public.get_reliever_request_conflict(p_employee_id uuid)
 RETURNS TABLE(has_pending_request boolean, pending_request_id uuid, requested_account text, requested_store text, requested_by text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    TRUE                      AS has_pending_request,
    war.id                    AS pending_request_id,
    a.account_name            AS requested_account,
    s.store_name              AS requested_store,
    war.requested_by          AS requested_by,
    war.created_at            AS created_at
  FROM workforce_assignment_requests war
  LEFT JOIN accounts a ON a.id = war.requested_account_id
  LEFT JOIN stores   s ON s.id = war.requested_store_id
  WHERE war.employee_id = p_employee_id
    AND war.status = 'Pending'
  LIMIT 1;

  -- Return empty row with false if no conflict
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TIMESTAMPTZ;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_store_import_approval_queue()
 RETURNS TABLE(batch_id uuid, file_name text, uploaded_by uuid, uploaded_by_name text, uploaded_role text, selected_group_id uuid, group_name text, selected_account_id uuid, account_name text, status text, total_rows integer, valid_rows integer, invalid_rows integer, error_summary jsonb, created_at timestamp with time zone, updated_at timestamp with time zone, days_pending integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: super admin only';
  END IF;
  RETURN QUERY
  SELECT b.id, b.file_name, b.uploaded_by, up.full_name,
         b.uploaded_role, b.selected_group_id, g.group_name,
         b.selected_account_id, a.account_name, b.status,
         b.total_rows, b.valid_rows, b.invalid_rows, b.error_summary,
         b.created_at, b.updated_at,
         ((EXTRACT(epoch FROM (now() - b.created_at)))::int / 86400)
  FROM public.store_import_batches b
  LEFT JOIN public.groups        g  ON g.id = b.selected_group_id
  LEFT JOIN public.accounts      a  ON a.id = b.selected_account_id
  LEFT JOIN public.users_profile up ON up.id = b.uploaded_by
  WHERE b.status IN ('pending_approval','validation_failed')
  ORDER BY
    CASE b.status WHEN 'pending_approval' THEN 1 WHEN 'validation_failed' THEN 2 ELSE 3 END,
    b.created_at ASC;
END$function$
;

CREATE OR REPLACE FUNCTION public.get_store_import_batches()
 RETURNS TABLE(id uuid, file_name text, uploaded_by uuid, uploaded_role text, selected_group_id uuid, selected_account_id uuid, group_name text, account_name text, status text, total_rows integer, valid_rows integer, invalid_rows integer, error_summary jsonb, approved_by uuid, approved_at timestamp with time zone, rejected_by uuid, rejected_at timestamp with time zone, rejection_reason text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lvl int := public.get_my_role_level();
  v_uid uuid := auth.uid();
BEGIN
  IF v_lvl IS NULL OR v_lvl < 90 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT b.id, b.file_name, b.uploaded_by, b.uploaded_role,
         b.selected_group_id, b.selected_account_id,
         g.group_name, a.account_name,
         b.status, b.total_rows, b.valid_rows, b.invalid_rows,
         b.error_summary, b.approved_by, b.approved_at,
         b.rejected_by, b.rejected_at, b.rejection_reason,
         b.created_at, b.updated_at
  FROM public.store_import_batches b
  LEFT JOIN public.groups   g ON g.id = b.selected_group_id
  LEFT JOIN public.accounts a ON a.id = b.selected_account_id
  WHERE public.is_super_admin() OR b.uploaded_by = v_uid
  ORDER BY b.created_at DESC;
END$function$
;

CREATE OR REPLACE FUNCTION public.get_store_import_dashboard()
 RETURNS TABLE(pending_approval_count integer, validation_failed_count integer, draft_uploaded_count integer, approved_count integer, rejected_count integer, my_active_batch_id uuid, my_active_status text, total_active_stores integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lvl  int  := public.get_my_role_level();
  v_uid  uuid := auth.uid();
BEGIN
  IF v_lvl IS NULL OR v_lvl < 90 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: role_level >= 90 required';
  END IF;
  RETURN QUERY
  WITH counts AS (
    SELECT
      count(*) FILTER (WHERE status='pending_approval')::int  AS pending_approval_count,
      count(*) FILTER (WHERE status='validation_failed')::int AS validation_failed_count,
      count(*) FILTER (WHERE status='draft_uploaded')::int    AS draft_uploaded_count,
      count(*) FILTER (WHERE status='approved')::int          AS approved_count,
      count(*) FILTER (WHERE status='rejected')::int          AS rejected_count
    FROM public.store_import_batches
    WHERE public.is_super_admin() OR uploaded_by = v_uid
  ),
  mine AS (
    SELECT id AS my_active_batch_id, status AS my_active_status
    FROM public.store_import_batches
    WHERE uploaded_by = v_uid
      AND status IN ('draft_uploaded','validation_failed','pending_approval')
    ORDER BY created_at DESC
    LIMIT 1
  ),
  store_total AS (
    SELECT count(*)::int AS total_active_stores FROM public.stores WHERE status='active'
  )
  SELECT c.pending_approval_count, c.validation_failed_count, c.draft_uploaded_count,
         c.approved_count, c.rejected_count,
         m.my_active_batch_id, m.my_active_status,
         st.total_active_stores
  FROM counts c
  LEFT JOIN mine m       ON true
  CROSS JOIN store_total st;
END$function$
;

CREATE OR REPLACE FUNCTION public.get_store_import_rows(p_batch_id uuid)
 RETURNS TABLE(id uuid, batch_id uuid, row_number integer, vcode text, store_name text, area_province text, area_city text, type text, with_penalty boolean, validation_status text, validation_errors jsonb, raw_data jsonb, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lvl int := public.get_my_role_level();
  v_uid uuid := auth.uid();
  v_owner uuid;
BEGIN
  IF v_lvl IS NULL OR v_lvl < 90 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  SELECT uploaded_by INTO v_owner FROM public.store_import_batches WHERE id = p_batch_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'BATCH_NOT_FOUND'; END IF;
  IF NOT (public.is_super_admin() OR v_owner = v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT r.id, r.batch_id, r.row_number, r.vcode, r.store_name,
         r.area_province, r.area_city, r.type, r.with_penalty,
         r.validation_status, r.validation_errors, r.raw_data, r.created_at
  FROM public.store_import_rows r
  WHERE r.batch_id = p_batch_id
  ORDER BY r.row_number;
END$function$
;

CREATE OR REPLACE FUNCTION public.get_store_import_template_csv()
 RETURNS TABLE(file_name text, content_type text, csv text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lvl int := public.get_my_role_level();
BEGIN
  IF v_lvl IS NULL OR v_lvl < 90 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: role_level >= 90 required';
  END IF;

  RETURN QUERY SELECT
    'import_plantilla_store_master_template.csv'::text,
    'text/csv'::text,
    'VCODE,STORE_NAME,AREA_PROVINCE,AREA_CITY,TYPE,WITH_PENALTY' || E'\n' ||
    'PG-DAU-001,Super 8 Dau,Pampanga,Angeles,stationary,yes' || E'\n' ||
    'PG-SF-001,Puregold San Fernando,Pampanga,San Fernando,stationary,no' || E'\n';
END$function$
;

CREATE OR REPLACE FUNCTION public.get_target_role_level(p_profile_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT r.role_level
  FROM users_profile up
  JOIN roles r ON r.id = up.role_id
  WHERE up.id = p_profile_id
  LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.get_team_performance(p_role text DEFAULT NULL::text, p_group_id uuid DEFAULT NULL::uuid, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(profile_id uuid, auth_uid uuid, full_name text, role text, group_id uuid, required_count integer, actual_count integer, hr_emploc_count integer, vacant_count integer, mfr numeric, pipeline_percent numeric, perf_status text, alert_flag text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
  v_caller_auth uuid := auth.uid();
  v_caller_role text;
  v_caller_pid  uuid;
BEGIN
  SELECT r.role_name, up.id
    INTO v_caller_role, v_caller_pid
  FROM users_profile up
  JOIN roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_caller_auth AND up.is_active = true
  LIMIT 1;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION 'User not found or inactive';
  END IF;

  IF v_caller_role IN ('HRCO', 'ATL', 'TL', 'Encoder', 'Recruitment Team', 'Viewer') THEN
    RAISE EXCEPTION 'Access denied: insufficient role';
  END IF;

  RETURN QUERY
  SELECT
    tp.profile_id, tp.auth_uid, tp.full_name, tp.role, tp.group_id,
    tp.required_count, tp.actual_count, tp.hr_emploc_count, tp.vacant_count,
    tp.mfr, tp.pipeline_percent, tp.perf_status, tp.alert_flag
  FROM team_performance_view tp
  WHERE (
    v_caller_role IN ('Super Admin', 'Head Admin')
    OR (
      v_caller_role = 'Operations Manager'
      AND EXISTS (
        SELECT 1 FROM vacancies v
        WHERE v.om_user_id = v_caller_auth
          AND (v.hrco_user_id = tp.auth_uid OR v.atl_user_id = tp.auth_uid)
          AND (v.is_archived IS NULL OR v.is_archived = false)
      )
    )
  )
  AND (p_role       IS NULL OR tp.role     = p_role)
  AND (p_group_id   IS NULL OR tp.group_id = p_group_id)
  AND (p_account_id IS NULL OR EXISTS (
    SELECT 1 FROM user_scopes us
    WHERE us.user_id = tp.profile_id AND us.account_id = p_account_id
  ))
  ORDER BY COALESCE(tp.mfr, 0) ASC NULLS LAST;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_team_performance_summary(p_role text DEFAULT NULL::text, p_group_id uuid DEFAULT NULL::uuid, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(avg_mfr numeric, best_performer_name text, best_performer_mfr numeric, worst_performer_name text, worst_performer_mfr numeric, count_critical integer, total_hr_emploc integer, total_vacant integer, total_required integer, total_actual integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  WITH filtered AS (
    SELECT * FROM get_team_performance(p_role, p_group_id, p_account_id)
    WHERE mfr IS NOT NULL
  )
  SELECT
    ROUND(AVG(f.mfr), 2),
    (SELECT f2.full_name FROM filtered f2 ORDER BY f2.mfr DESC LIMIT 1),
    (SELECT f2.mfr       FROM filtered f2 ORDER BY f2.mfr DESC LIMIT 1),
    (SELECT f2.full_name FROM filtered f2 ORDER BY f2.mfr ASC  LIMIT 1),
    (SELECT f2.mfr       FROM filtered f2 ORDER BY f2.mfr ASC  LIMIT 1),
    SUM(CASE WHEN f.mfr < 80 THEN 1 ELSE 0 END)::int,
    SUM(f.hr_emploc_count)::int,
    SUM(f.vacant_count)::int,
    SUM(f.required_count)::int,
    SUM(f.actual_count)::int
  FROM filtered f;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_unread_notification_count()
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
  v_my_role TEXT;
  v_count   INT;
BEGIN
  v_my_role := get_my_role();
  SELECT COUNT(*) INTO v_count
  FROM notifications
  WHERE recipient_role = v_my_role AND read_at IS NULL;
  RETURN COALESCE(v_count, 0);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_user_drilldown(p_target_profile_id uuid)
 RETURNS TABLE(section text, record_id uuid, label text, status text, age_days integer, account_name text, store_name text, extra_info text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
  v_caller_role text;
  v_target_auth uuid;
BEGIN
  v_caller_role := get_current_user_role();

  IF v_caller_role NOT IN ('Super Admin', 'Head Admin', 'Operations Manager') THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  SELECT auth_user_id INTO v_target_auth
  FROM users_profile WHERE id = p_target_profile_id;

  RETURN QUERY
  SELECT
    'Vacancy'::text,
    v.id,
    v.position || ' (' || v.vcode || ')',
    v.status,
    EXTRACT(DAY FROM now() - v.created_at)::int,
    v.account,
    v.store_name,
    'Required: ' || v.required_headcount::text
  FROM vacancies v
  WHERE (v.is_archived IS NULL OR v.is_archived = false)
    AND (v.hrco_user_id = v_target_auth OR v.atl_user_id = v_target_auth OR v.om_user_id = v_target_auth)

  UNION ALL

  SELECT
    'HR Emploc'::text,
    he.id,
    he.applicant_name,
    he.status,
    EXTRACT(DAY FROM now() - he.created_at)::int,
    he.account,
    he.store_name,
    'Hired: ' || COALESCE(he.hired_date::text, 'N/A')
  FROM hr_emploc he
  WHERE he.status != 'Moved to Plantilla'
    AND (he.hrco_user_id_snapshot = v_target_auth OR he.atl_user_id_snapshot = v_target_auth OR he.om_user_id_snapshot = v_target_auth)

  ORDER BY section, age_days DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_closure_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_vacancy RECORD;
  v_requestor RECORD;
  v_type TEXT;
BEGIN
  IF NEW.status = 'Approved' AND OLD.status = 'Pending' THEN
    PERFORM public.fn_assert_vacancy_closeable(NEW.vacancy_vcode);

    UPDATE public.vacancies
    SET status = 'Closed',
        is_archived = true,
        archived_at = NOW(),
        archived_by = NEW.reviewed_by,
        has_pending_closure = false,
        closure_request_status = 'Approved',
        updated_at = NOW()
    WHERE vcode = NEW.vacancy_vcode;
  END IF;

  IF NEW.status = 'Rejected' AND OLD.status = 'Pending' THEN
    UPDATE public.vacancies
    SET has_pending_closure = false,
        closure_request_status = 'Rejected',
        updated_at = NOW()
    WHERE vcode = NEW.vacancy_vcode;
  END IF;

  IF NEW.status IN ('Approved', 'Rejected') AND OLD.status IS DISTINCT FROM NEW.status THEN
    SELECT v.id AS vacancy_id,
           COALESCE(a.account_name, v.account) AS account_name
    INTO v_vacancy
    FROM public.vacancies v
    LEFT JOIN public.accounts a ON a.id = v.account_id
    WHERE v.vcode = NEW.vacancy_vcode
    LIMIT 1;

    SELECT up.auth_user_id, up.role
    INTO v_requestor
    FROM public.users_profile up
    WHERE up.auth_user_id = NEW.requested_by_user_id
       OR up.id = NEW.requested_by_user_id
    LIMIT 1;

    v_type := CASE WHEN NEW.status = 'Approved' THEN 'approval' ELSE 'rejection' END;

    IF COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id) IS NOT NULL THEN
      PERFORM public.notify_user(
        COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id),
        COALESCE(v_requestor.role, 'Ops'),
        CASE WHEN NEW.status = 'Approved' THEN 'Vacancy Closure Approved' ELSE 'Vacancy Closure Rejected' END,
        CASE WHEN NEW.status = 'Approved'
          THEN 'Your closure request for ' || NEW.vacancy_vcode || ' (' || COALESCE(v_vacancy.account_name, 'Account') || ') has been approved by ' || COALESCE(NEW.reviewed_by, NEW.encoder_by, 'Encoder') || '.'
          ELSE 'Your closure request for ' || NEW.vacancy_vcode || ' (' || COALESCE(v_vacancy.account_name, 'Account') || ') was rejected by ' || COALESCE(NEW.reviewed_by, NEW.encoder_by, 'Encoder') || '. Reason: ' || COALESCE(NEW.reviewer_remarks, NEW.details, NEW.reason, 'No reason provided') || '.'
        END,
        v_type,
        'vacancy_closure',
        'vacancy_closure',
        NEW.id::TEXT,
        FORMAT('/vacancies/%s/closure-request/%s', COALESCE(v_vacancy.vacancy_id::TEXT, NEW.vacancy_vcode), NEW.id),
        NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_closure_requested()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_vacancy RECORD;
  v_encoder RECORD;
BEGIN
  UPDATE public.vacancies
  SET has_pending_closure = true,
      closure_request_status = 'Pending',
      updated_at = NOW()
  WHERE vcode = NEW.vacancy_vcode;

  SELECT v.id AS vacancy_id,
         COALESCE(a.account_name, v.account) AS account_name,
         COALESCE(a.group_id, v.group_id) AS group_id
  INTO v_vacancy
  FROM public.vacancies v
  LEFT JOIN public.accounts a ON a.id = v.account_id
  WHERE v.vcode = NEW.vacancy_vcode
  LIMIT 1;

  SELECT up.auth_user_id, up.role
  INTO v_encoder
  FROM public.users_profile up
  WHERE up.role = 'Encoder'
    AND up.is_active = true
    AND up.auth_user_id IS NOT NULL
    AND up.group_id = v_vacancy.group_id
  LIMIT 1;

  IF v_encoder.auth_user_id IS NOT NULL THEN
    PERFORM public.notify_user(
      v_encoder.auth_user_id,
      'Encoder',
      'Vacancy Closure Request — ' || COALESCE(v_vacancy.account_name, 'Account'),
      COALESCE(NEW.requested_by, 'Ops') || ' has requested to close vacancy ' || NEW.vacancy_vcode || ' for ' || COALESCE(v_vacancy.account_name, 'the account') || '. Please review.',
      'submission',
      'vacancy_closure',
      'vacancy_closure',
      NEW.id::TEXT,
      FORMAT('/vacancies/%s/closure-request/%s', COALESCE(v_vacancy.vacancy_id::TEXT, NEW.vacancy_vcode), NEW.id),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_emploc_deletion_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_vcode text;
  v_required int;
  v_hired int;
  v_requestor RECORD;
  v_type TEXT;
BEGIN
  IF NEW.status = 'Approved' AND OLD.status = 'Pending' THEN
    v_vcode := NEW.vcode;

    IF NEW.hr_emploc_id IS NOT NULL THEN
      DELETE FROM public.hr_emploc WHERE id = NEW.hr_emploc_id;
    END IF;

    UPDATE public.applicants
    SET is_archived = true,
        archived_at = now()
    WHERE full_name = NEW.applicant_name
      AND vacancy_vcode = v_vcode
      AND status IN ('Hired', 'For Onboarding');

    IF COALESCE(NEW.reopen_vacancy, true) THEN
      SELECT required_headcount INTO v_required
      FROM public.vacancies WHERE vcode = v_vcode;

      SELECT COUNT(*) INTO v_hired
      FROM public.hr_emploc WHERE vcode = v_vcode;

      IF v_hired < COALESCE(v_required, 1) THEN
        UPDATE public.vacancies
        SET status = 'Open', updated_at = now()
        WHERE vcode = v_vcode
          AND status NOT IN ('Closed', 'Archived');
      END IF;
    END IF;
  END IF;

  IF NEW.status IN ('Approved', 'Rejected') AND OLD.status IS DISTINCT FROM NEW.status THEN
    SELECT up.auth_user_id, up.role
    INTO v_requestor
    FROM public.users_profile up
    WHERE up.full_name = NEW.requested_by
      AND up.auth_user_id IS NOT NULL
    LIMIT 1;

    v_type := CASE WHEN NEW.status = 'Approved' THEN 'approval' ELSE 'rejection' END;

    IF v_requestor.auth_user_id IS NOT NULL THEN
      PERFORM public.notify_user(
        v_requestor.auth_user_id,
        COALESCE(v_requestor.role, NEW.requested_by_role),
        CASE WHEN NEW.status = 'Approved' THEN 'Deletion Request Approved' ELSE 'Deletion Request Rejected' END,
        CASE WHEN NEW.status = 'Approved'
          THEN 'Your deletion request for ' || NEW.applicant_name || ' (' || NEW.vcode || ') has been approved by ' || COALESCE(NEW.reviewed_by, 'Encoder') || '.'
          ELSE 'Your deletion request for ' || NEW.applicant_name || ' (' || NEW.vcode || ') was rejected by ' || COALESCE(NEW.reviewed_by, 'Encoder') || '. Reason: ' || COALESCE(NEW.reviewer_remarks, 'No reason provided') || '.'
        END,
        v_type,
        'hr_emploc_deletion',
        'hr_emploc_deletion',
        NEW.id::TEXT,
        FORMAT('/hr-emploc/deletion-requests/%s', NEW.id),
        NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_emploc_deletion_requested()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_account RECORD;
  v_encoder RECORD;
BEGIN
  SELECT a.id, a.account_name, a.group_id
  INTO v_account
  FROM public.hr_emploc he
  LEFT JOIN public.accounts a ON a.id = he.account_id OR a.account_name = he.account
  WHERE he.id = NEW.hr_emploc_id
  LIMIT 1;

  IF v_account.group_id IS NULL THEN
    SELECT a.id, a.account_name, a.group_id
    INTO v_account
    FROM public.accounts a
    WHERE a.account_name = NEW.account
    LIMIT 1;
  END IF;

  SELECT up.auth_user_id, up.role
  INTO v_encoder
  FROM public.users_profile up
  WHERE up.role = 'Encoder'
    AND up.is_active = true
    AND up.auth_user_id IS NOT NULL
    AND up.group_id = v_account.group_id
  LIMIT 1;

  IF v_encoder.auth_user_id IS NOT NULL THEN
    PERFORM public.notify_user(
      v_encoder.auth_user_id,
      'Encoder',
      'Deletion Request — ' || COALESCE(v_account.account_name, NEW.account),
      NEW.requested_by || ' has requested to delete HR Emploc record for ' || NEW.applicant_name || ' (' || NEW.vcode || '). Please review.',
      'submission',
      'hr_emploc_deletion',
      'hr_emploc_deletion',
      NEW.id::TEXT,
      FORMAT('/hr-emploc/deletion-requests/%s', NEW.id),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_emploc_no_entered()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Promote to Complete when emploc_no is first set
  IF NEW.emploc_no IS NOT NULL AND TRIM(NEW.emploc_no) != '' THEN
    IF TG_OP = 'INSERT'
       OR (OLD.emploc_no IS NULL OR TRIM(OLD.emploc_no) = '') THEN
      IF NEW.hr_status IS NULL OR NEW.hr_status = 'Pending' THEN
        NEW.hr_status := 'Complete';
      END IF;
    END IF;
  END IF;

  -- Revert to Pending when emploc_no is cleared (UPDATE only)
  IF TG_OP = 'UPDATE'
     AND (NEW.emploc_no IS NULL OR TRIM(NEW.emploc_no) = '')
     AND (OLD.emploc_no IS NOT NULL AND TRIM(OLD.emploc_no) != '')
     AND NEW.hr_status = 'Complete' THEN
    NEW.hr_status := 'Pending';
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_employee_resignation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'Resigned' AND OLD.status = 'Active' THEN
    -- Reopen vacancies from plantilla vcodes
    UPDATE public.vacancies
    SET status = 'Open',
        has_pending_closure = false,
        updated_at = now()
    WHERE vcode IN (
      SELECT vcode FROM public.plantilla
      WHERE employee_no = NEW.employee_no
        AND status = 'Active'
    )
    AND status NOT IN ('Closed', 'Archived');

    -- Resign plantilla records
    UPDATE public.plantilla
    SET status = 'Resigned',
        resignation_date = COALESCE(NEW.resignation_date, CURRENT_DATE),
        updated_at = now()
    WHERE employee_no = NEW.employee_no
      AND status = 'Active';
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_ghost_encoding_assigned()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  IF NEW.status = 'For Encoding' AND OLD.status != 'For Encoding' THEN
    NEW.encoding_deadline := now() + INTERVAL '48 hours';
    NEW.updated_at := now();
    INSERT INTO notifications
      (recipient_role, title, message, reference_type, reference_id, deep_link_route)
    VALUES (
      'Encoder',
      '📋 For Encoding — Action Required',
      'Possible Ghost Employee: ' || NEW.employee_no || ' ' || NEW.full_name
        || '. Please add to Vacancy within 48 hours. Deadline: '
        || TO_CHAR(now() + INTERVAL '48 hours', 'Mon DD, YYYY HH:MI AM'),
      'ghost_employee', NEW.id::text,
      build_deep_link('ghost_employee', NEW.id::text)
    );
  END IF;

  IF NEW.status IN ('Cleared','Confirmed Ghost','For Termination')
     AND OLD.status NOT IN ('Cleared','Confirmed Ghost','For Termination') THEN
    NEW.resolved_at := now();
    NEW.updated_at  := now();
    IF NEW.status IN ('Confirmed Ghost','For Termination') THEN
      INSERT INTO notifications
        (recipient_role, title, message, reference_type, reference_id, deep_link_route)
      VALUES (
        'Super Admin',
        '🚨 ' || NEW.status || ' — ' || NEW.employee_no,
        NEW.full_name || ' has been marked as ' || NEW.status
          || ' by ' || COALESCE(NEW.resolved_by, 'Unknown')
          || '. Immediate action may be required.',
        'ghost_employee', NEW.id::text,
        build_deep_link('ghost_employee', NEW.id::text)
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_hr_emploc_rejected()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hrco RECORD;
BEGIN
  IF NEW.hr_status = 'Rejected' AND OLD.hr_status IS DISTINCT FROM 'Rejected' THEN
    SELECT up.auth_user_id, up.role
    INTO v_hrco
    FROM public.users_profile up
    WHERE (up.id = NEW.hrco_user_id_snapshot OR up.auth_user_id = NEW.hrco_user_id_snapshot)
      AND up.auth_user_id IS NOT NULL
    LIMIT 1;

    IF v_hrco.auth_user_id IS NOT NULL THEN
      PERFORM public.notify_user(
        v_hrco.auth_user_id,
        COALESCE(v_hrco.role, 'HRCO'),
        'HR Emploc Rejected — ' || NEW.applicant_name,
        NEW.applicant_name || ' (' || NEW.vcode || ') was rejected by HR.' ||
          CASE WHEN NEW.hr_rejection_reason IS NOT NULL THEN ' Reason: ' || NEW.hr_rejection_reason || '.' ELSE '' END ||
          CASE WHEN NEW.hr_remarks IS NOT NULL THEN ' Remarks: ' || NEW.hr_remarks ELSE '' END,
        'rejection',
        'correction',
        'hr_emploc',
        NEW.id::TEXT,
        FORMAT('/hr-emploc/%s/correction', NEW.id),
        NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Idempotency guard (no duplicates)
  IF EXISTS (
    SELECT 1 FROM public.account_requests WHERE auth_user_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.account_requests (
    auth_user_id,
    email,
    full_name,
    status
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(
      NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
      'No Name'
    ),
    'pending'::public.account_request_status
  );

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    -- Surface failure loudly (no silent fail). Re-raise to block orphan auth users.
    RAISE WARNING
      'handle_new_auth_user FAILED | user=% email=% sqlstate=% msg=%',
      NEW.id, NEW.email, SQLSTATE, SQLERRM;
    RAISE;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_separation_create_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.date_of_separation IS NOT NULL
     AND OLD.date_of_separation IS DISTINCT FROM NEW.date_of_separation
  THEN

    IF NEW.separation_status IS NULL AND NEW.status = 'Resigned' THEN
      NEW.separation_status := 'Resigned';
    END IF;

    PERFORM public.reopen_or_create_vacancy_for_plantilla(
      NEW.id,
      NEW.date_of_separation,
      'Backfill'
    );

    INSERT INTO public.activity_log
      (
        actor_id,
        actor_name,
        actor_role,
        action,
        target_table,
        target_id,
        target_name,
        new_value
      )
    VALUES
      (
        get_current_profile_id(),
        get_my_full_name(),
        get_my_role(),
        'SEPARATION_VACANCY_REOPENED',
        'plantilla',
        NEW.id,
        NEW.employee_name || ' (' || NEW.emploc_no || ')',
        jsonb_build_object(
          'date_of_separation', NEW.date_of_separation,
          'separation_status', NEW.separation_status,
          'vcode', NEW.vcode
        )
      );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_sla_breach_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_days_elapsed INT;
  v_breach_id    UUID;
BEGIN
  -- Fire only when separation_status is newly set to 'Resigned'
  IF NEW.separation_status = 'Resigned'
     AND OLD.separation_status IS DISTINCT FROM 'Resigned'
     AND NEW.date_of_separation IS NOT NULL
  THEN
    v_days_elapsed := (CURRENT_DATE - NEW.date_of_separation)::INT;

    IF v_days_elapsed > 3 THEN

      -- Guard: skip if breach already logged for this plantilla record
      IF NOT EXISTS (
        SELECT 1 FROM public.sla_breach_logs
        WHERE plantilla_id = NEW.id
          AND breach_type = 'resignation_not_tagged'
      ) THEN

        INSERT INTO public.sla_breach_logs
          (plantilla_id, employee_no, vcode, account,
           breach_type, resignation_date, tagged_date, days_elapsed, notified_om)
        VALUES
          (NEW.id, NEW.emploc_no, NEW.vcode, NEW.account,
           'resignation_not_tagged', NEW.date_of_separation, CURRENT_DATE,
           v_days_elapsed, TRUE)
        RETURNING id INTO v_breach_id;

        -- Notify all OM users in scope
        INSERT INTO public.notifications
          (recipient_role, title, message, reference_type, reference_id, deep_link_route)
        VALUES
          ('OM',
           '⚠️ SLA BREACH: Resignation Not Tagged On Time',
           'Employee ' || NEW.employee_name || ' (' || NEW.emploc_no || ') at '
             || NEW.account || ' was tagged as resigned ' || v_days_elapsed
             || ' days after separation date (' || NEW.date_of_separation || '). SLA = 3 days.',
           'sla_breach', v_breach_id::text,
           build_deep_link('sla_breach', v_breach_id::text));

        -- Log
        INSERT INTO public.activity_log
          (actor_id, actor_name, actor_role, action, target_table, target_id, target_name, new_value)
        VALUES
          (get_current_profile_id(), get_my_full_name(), get_my_role(),
           'SLA_BREACH_LOGGED', 'plantilla', NEW.id,
           NEW.employee_name,
           jsonb_build_object(
             'breach_type', 'resignation_not_tagged',
             'days_elapsed', v_days_elapsed,
             'resignation_date', NEW.date_of_separation
           ));
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_transfer_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old public.plantilla%rowtype;
  v_store public.stores%rowtype;
  v_account public.accounts%rowtype;
  v_position_id_eff uuid;
  v_requestor RECORD;
BEGIN
  IF new.status = 'Approved' AND old.status = 'Pending' THEN
    IF new.plantilla_id IS NULL OR new.target_store_id IS NULL THEN
      RAISE EXCEPTION 'transfer request missing plantilla_id or target_store_id';
    END IF;

    SELECT * INTO v_old
    FROM public.plantilla
    WHERE id = new.plantilla_id
      AND COALESCE(is_deleted, false) = false
    FOR UPDATE;

    IF v_old.id IS NULL THEN
      RAISE EXCEPTION 'plantilla not found for transfer request %', new.id;
    END IF;

    IF v_old.status <> 'Active' THEN
      RAISE EXCEPTION 'only active plantilla can be transferred';
    END IF;

    SELECT * INTO v_store
    FROM public.stores
    WHERE id = new.target_store_id;

    IF v_store.id IS NULL THEN
      RAISE EXCEPTION 'target store not found for transfer request %', new.id;
    END IF;

    SELECT * INTO v_account
    FROM public.accounts
    WHERE id = v_store.account_id;

    IF v_account.id IS NULL THEN
      RAISE EXCEPTION 'target account not found for transfer request %', new.id;
    END IF;

    v_position_id_eff := COALESCE(new.target_position_id, v_old.position_id);

    UPDATE public.plantilla
    SET account = v_account.account_name,
        account_id = v_account.id,
        store_id = v_store.id,
        store_name = v_store.store_name,
        area = COALESCE(v_store.area_city, area),
        transferred_from_store_id = v_old.store_id,
        last_transfer_at = now(),
        last_transfer_by = new.approved_by_user_id,
        position_id = v_position_id_eff,
        remarks = COALESCE('[Transfer Approved] ' || new.reason, remarks),
        updated_by = new.approved_by_user_id,
        updated_at = now()
    WHERE id = new.plantilla_id;

    INSERT INTO public.employee_activity_log
      (emploc_no, vcode, activity_type, description, performed_by)
    VALUES (
      new.emploc_no,
      new.from_vcode,
      'transferred',
      'Transferred from ' || COALESCE(new.from_store, new.from_account) || ' to ' || COALESCE(new.to_store, new.to_account),
      new.reviewed_by
    );

    SELECT up.auth_user_id, up.role
    INTO v_requestor
    FROM public.users_profile up
    WHERE up.full_name = new.requested_by
      AND up.auth_user_id IS NOT NULL
    LIMIT 1;

    IF v_requestor.auth_user_id IS NOT NULL THEN
      PERFORM public.notify_user(
        v_requestor.auth_user_id,
        COALESCE(v_requestor.role, new.requested_by_role),
        'Transfer Request Approved',
        'Transfer request for ' || new.employee_name || ' to ' || COALESCE(new.to_store, new.to_account) || ' has been approved by ' || COALESCE(new.reviewed_by, 'Encoder') || '.',
        'approval',
        'transfer',
        'transfer',
        new.id::TEXT,
        FORMAT('/transfers/%s', new.id),
        NULL
      );
    END IF;
  END IF;

  RETURN new;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_vacancy_filled_archive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'Filled' AND COALESCE(OLD.status, '') <> 'Filled' THEN
    NEW.is_archived  := TRUE;
    NEW.archived_at  := COALESCE(NEW.archived_at, NOW());
    NEW.archived_by  := COALESCE(NEW.archived_by, get_my_full_name());

    INSERT INTO public.activity_log
      (actor_id, actor_name, actor_role, action, target_table, target_id, target_name)
    VALUES
      (get_current_profile_id(), get_my_full_name(), get_my_role(),
       'AUTO_ARCHIVED_FILLED', 'vacancies', NEW.id,
       NEW.vcode || ' — ' || NEW.position || ' @ ' || NEW.account);
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_vacancy_request_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_encoder_profile_id UUID;
  v_encoder_name       TEXT;
BEGIN
  IF NEW.status = 'Approved' AND OLD.status <> 'Approved' THEN

    -- Resolve assigned encoder identity
    SELECT up.id, up.full_name
    INTO v_encoder_profile_id, v_encoder_name
    FROM public.users_profile up
    WHERE up.id = NEW.assigned_encoder_id
    LIMIT 1;

    IF v_encoder_profile_id IS NOT NULL THEN
      -- Notify by role scoped to encoder name in message
      INSERT INTO public.notifications
        (recipient_role, title, message, reference_type, reference_id, deep_link_route)
      VALUES
        ('Encoder',
         '✅ Vacancy Approved — VCode Needed',
         'Vacancy request for ' || NEW.position || ' at ' || NEW.store_name
           || ' (' || NEW.account || ') has been approved. Please create the VCode.',
         'vacancy_request', NEW.id::text,
         build_deep_link('vacancy_request', NEW.id::text));
    ELSE
      -- Fallback: notify all encoders if none assigned
      INSERT INTO public.notifications
        (recipient_role, title, message, reference_type, reference_id, deep_link_route)
      VALUES
        ('Encoder',
         '✅ Vacancy Approved — VCode Needed',
         'Vacancy request for ' || NEW.position || ' at ' || NEW.store_name
           || ' (' || NEW.account || ') has been approved. Please create the VCode.',
         'vacancy_request', NEW.id::text,
         build_deep_link('vacancy_request', NEW.id::text));
    END IF;

    -- Log to activity_log
    INSERT INTO public.activity_log
      (actor_id, actor_name, actor_role, action, target_table, target_id, target_name)
    VALUES
      (get_current_profile_id(), get_my_full_name(), get_my_role(),
       'APPROVED_VACANCY_REQUEST', 'vacancy_requests', NEW.id,
       NEW.position || ' @ ' || NEW.store_name);
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_vacancy_request_submitted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Notify OM for approval
  INSERT INTO public.notifications
    (recipient_role, title, message, reference_type, reference_id, deep_link_route)
  VALUES
    ('OM',
     CASE WHEN NEW.urgency = 'Urgent' THEN '🚨 Urgent Vacancy Request Needs Approval'
          ELSE '📋 New Vacancy Request Needs Approval' END,
     NEW.requested_by || ' (' || NEW.requested_by_role || ') submitted a vacancy request for '
       || NEW.store_name || ' (' || NEW.account || ') — ' || NEW.position
       || '. Slots: ' || NEW.no_of_slots || '. Urgency: ' || NEW.urgency || '.',
     'vacancy_request', NEW.id::text,
     build_deep_link('vacancy_request', NEW.id::text)),
  -- Head Admin visibility (not Super Admin per rules)
    ('Head Admin',
     CASE WHEN NEW.urgency = 'Urgent' THEN '🚨 Urgent Vacancy Request'
          ELSE '📋 New Vacancy Request' END,
     NEW.requested_by || ' (' || NEW.requested_by_role || ') submitted a vacancy request for '
       || NEW.store_name || ' (' || NEW.account || ') — ' || NEW.position
       || '. Slots: ' || NEW.no_of_slots || '. Urgency: ' || NEW.urgency || '.',
     'vacancy_request', NEW.id::text,
     build_deep_link('vacancy_request', NEW.id::text));
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_vcode_created_notify_requestor()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_requestor_role TEXT;
  v_req_id         UUID;
BEGIN
  -- VCode just got assigned (was NULL, now has value)
  IF NEW.vcode_created IS NOT NULL AND OLD.vcode_created IS NULL THEN

    -- Get requestor role from the request record
    SELECT requested_by_role, id
    INTO v_requestor_role, v_req_id
    FROM public.vacancy_requests
    WHERE id = NEW.id
    LIMIT 1;

    IF v_requestor_role IS NOT NULL THEN
      INSERT INTO public.notifications
        (recipient_role, title, message, reference_type, reference_id, deep_link_route)
      VALUES
        (v_requestor_role,
         '🎟️ VCode Created for Your Vacancy Request',
         'Your vacancy request for ' || NEW.position || ' at ' || NEW.store_name
           || ' (' || NEW.account || ') now has a VCode: ' || COALESCE(NEW.vcode_created, '—') || '.',
         'vacancy_request', NEW.id::text,
         build_deep_link('vacancy_request', NEW.id::text));
    END IF;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.has_open_slot_for(p_store_id uuid, p_position_id uuid, p_employment_type text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    -- An open vacancy already covers this slot
    SELECT 1 FROM vacancies v
    WHERE v.store_id    = p_store_id
      AND v.position_id = p_position_id
      AND v.status = 'Open'
      AND COALESCE(v.is_archived,false) = false
      AND v.deleted_at IS NULL
  ) OR EXISTS (
    -- A plantilla slot exists in non-final state for same definition
    SELECT 1 FROM plantilla p
    WHERE p.store_id = p_store_id
      AND p.position_id = p_position_id
      AND COALESCE(p.deployment_type,'') = COALESCE(p_employment_type,'')
      AND p.status IN ('Inactive','For Deactivation')
  );
$function$
;

CREATE OR REPLACE FUNCTION public.has_open_slot_scoped(p_account_id uuid, p_store_name text, p_position_id uuid, p_employment_type text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.vacancies v
    WHERE v.account_id  = p_account_id
      AND lower(trim(v.store_name))  = lower(trim(p_store_name))
      AND v.position_id = p_position_id
      AND v.status      = 'Open'
      AND coalesce(v.is_archived, false) = false
      AND v.deleted_at IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.plantilla p
    WHERE p.account_id = p_account_id
      AND lower(trim(p.store_name))  = lower(trim(p_store_name))
      AND p.position_id = p_position_id
      AND coalesce(p.deployment_type, '') = coalesce(p_employment_type, '')
      AND p.status IN ('Inactive', 'For Deactivation')
  );
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


CREATE OR REPLACE FUNCTION public.i_am_hr_dept()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(public.get_my_role(), '') IN (
    'HR Dept', 'HR Department', 'hr_dept', 'HR Personnel'
  );
$function$
;

CREATE OR REPLACE FUNCTION public.i_am_ops()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
  RETURN get_my_role_level() BETWEEN 40 AND 70;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.i_am_recruitment()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(public.get_my_role(), '') IN ('Recruitment', 'Recruitment Team');
$function$
;

CREATE OR REPLACE FUNCTION public.i_am_super_admin()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
  RETURN get_my_role_level() = 100;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.i_can_act_on_plantilla()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT public.i_have_full_access()
      OR ( COALESCE(public.get_my_role_level(),0) >= 60
           AND NOT public.i_am_recruitment()
           AND NOT public.i_am_hr_dept() );
$function$
;

CREATE OR REPLACE FUNCTION public.i_can_view_plantilla()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT public.i_have_full_access()
      OR (NOT public.i_am_recruitment() AND NOT public.i_am_hr_dept());
$function$
;

CREATE OR REPLACE FUNCTION public.i_have_full_access()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
begin
  v_role := public.get_my_role();

  return v_role in ('Super Admin', 'Head Admin');
end;
$function$
;

CREATE OR REPLACE FUNCTION public.is_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT COALESCE(get_my_role_level() >= 100, FALSE);
$function$
;

CREATE OR REPLACE FUNCTION public.is_super_admin_excluded_action(p_action_type text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT p_action_type = ANY(ARRAY[
    'vacancy_closure_request',
    'hr_emploc_deletion',
    'vacancy_request'
  ]);
$function$
;

CREATE OR REPLACE FUNCTION public.link_late_store_to_plantilla(p_hr_emploc_store_link_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor   uuid := get_my_profile_id();
  v_link    public.hr_emploc_store_links%ROWTYPE;
  v_emp     public.hr_emploc%ROWTYPE;
  v_pl      public.plantilla%ROWTYPE;
  v_pl_link public.plantilla_store_links%ROWTYPE;
BEGIN
  -- ── Fetch store link ─────────────────────────────────────────────────────
  SELECT * INTO v_link
    FROM public.hr_emploc_store_links
   WHERE id = p_hr_emploc_store_link_id
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'hr_emploc_store_link % not found', p_hr_emploc_store_link_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_link.status <> 'Confirmed' THEN
    RAISE EXCEPTION 'store link must be Confirmed before linking to plantilla (current: %)', v_link.status
      USING ERRCODE = '22023';
  END IF;

  -- ── Fetch hr_emploc master ───────────────────────────────────────────────
  SELECT * INTO v_emp
    FROM public.hr_emploc
   WHERE id = v_link.hr_emploc_id
     AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'hr_emploc master not found for store link %', p_hr_emploc_store_link_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_emp.status <> 'Moved to Plantilla' THEN
    RAISE EXCEPTION 'hr_emploc master is not yet in Plantilla (status: %). Assign emploc number first.', v_emp.status
      USING ERRCODE = '22023';
  END IF;

  IF v_emp.employee_no IS NULL THEN
    RAISE EXCEPTION 'employee_no missing on hr_emploc master'
      USING ERRCODE = '22023';
  END IF;

  -- ── Fetch existing plantilla master ──────────────────────────────────────
  SELECT * INTO v_pl
    FROM public.plantilla
   WHERE roving_assignment_id = v_emp.roving_assignment_id
     AND is_deleted = false
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla master not found for roving_assignment_id %', v_emp.roving_assignment_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Insert plantilla_store_link (idempotent) ─────────────────────────────
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
  ) VALUES (
    v_pl.id,
    v_emp.roving_assignment_id,
    v_link.id,
    v_link.vacancy_id,
    v_link.vcode,
    v_link.store_name,
    v_link.account,
    'Active',
    NOW(),
    v_actor,
    v_actor,
    v_actor
  )
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_pl_link;

  -- ── Close the vacancy ────────────────────────────────────────────────────
  IF v_link.vacancy_id IS NOT NULL THEN
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_actor
     WHERE id = v_link.vacancy_id
       AND status NOT IN ('Filled', 'Closed', 'Archived');
  END IF;

  -- ── Audit ────────────────────────────────────────────────────────────────
  PERFORM public.log_audit_event(
    'plantilla_store_links', 'INSERT',
    v_pl_link.id,
    NULL,
    jsonb_build_object(
      'plantilla_id',              v_pl.id,
      'hr_emploc_store_link_id',   v_link.id,
      'vcode',                     v_link.vcode,
      'store_name',                v_link.store_name,
      'trigger',                   'late_store_confirmation'
    )
  );

  RETURN jsonb_build_object(
    'ok',                        true,
    'plantilla_id',              v_pl.id,
    'plantilla_store_link_id',   v_pl_link.id,
    'vcode',                     v_link.vcode,
    'store_name',                v_link.store_name,
    'vacancy_closed',            v_link.vacancy_id IS NOT NULL
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.log_applicant_hired()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'Hired' AND OLD.status != 'Hired' THEN
    INSERT INTO public.employee_activity_log (emploc_no, vcode, activity_type, description, performed_by)
    VALUES (NEW.full_name, NEW.vacancy_vcode, 'hired',
      'Applicant marked as Hired for ' || NEW.vacancy_vcode,
      COALESCE(NEW.hired_by, 'System'));
  END IF;
  RETURN NEW;
END; $function$
;

CREATE OR REPLACE FUNCTION public.log_audit_event(p_module text, p_action text, p_record_id uuid, p_old_data jsonb DEFAULT NULL::jsonb, p_new_data jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_id uuid;
  v_actor_role text;
  v_log_id uuid;
begin
  v_actor_id := auth.uid();

  select r.role_name
  into v_actor_role
  from public.users_profile up
  left join public.roles r on r.id = up.role_id
  where up.auth_user_id = v_actor_id
  limit 1;

  insert into public.audit_logs (
    actor_id,
    module,
    action,
    record_id,
    old_data,
    new_data,
    timestamp,
    role
  ) values (
    v_actor_id,
    upper(trim(p_module)),
    upper(trim(p_action))::audit_action,
    p_record_id,
    p_old_data,
    p_new_data,
    now(),
    v_actor_role
  )
  returning id into v_log_id;

  return v_log_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.log_employee_benefit_reveal(p_plantilla_id uuid, p_benefit_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_p plantilla%ROWTYPE;
BEGIN
  IF p_benefit_type NOT IN ('SSS','PhilHealth','Pag-IBIG','TIN') THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_benefit_type');
  END IF;
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'mika_sync') THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  SELECT * INTO v_p FROM public.plantilla WHERE id = p_plantilla_id;
  IF v_p.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','plantilla_not_found');
  END IF;

  PERFORM public._log_employee_action(
    p_plantilla_id, 'BENEFIT_REVEAL',
    format('%s revealed %s for %s', public.get_my_full_name(), p_benefit_type, v_p.employee_name),
    NULL,
    jsonb_build_object('benefit_type', p_benefit_type, 'role', public.get_my_role(),
                       'revealed_at', NOW())
  );

  RETURN jsonb_build_object('ok',true,'logged_at',NOW());
END$function$
;

CREATE OR REPLACE FUNCTION public.log_employee_resigned()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'Resigned' AND OLD.status = 'Active' THEN
    INSERT INTO public.employee_activity_log (emploc_no, vcode, activity_type, description)
    VALUES (NEW.emploc_no, NEW.vcode, 'resigned',
      'Employee resigned from ' || COALESCE(NEW.store_name, NEW.account)
      || CASE WHEN NEW.remarks IS NOT NULL THEN ' — ' || NEW.remarks ELSE '' END);
  END IF;
  RETURN NEW;
END; $function$
;

CREATE OR REPLACE FUNCTION public.log_moved_to_plantilla()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Only log when an actual emploc_no exists.
  -- Vacant slot placeholders (emploc_no IS NULL) are intentionally skipped.
  IF TG_OP = 'INSERT' AND COALESCE(NEW.emploc_no, '') <> '' THEN
    INSERT INTO public.employee_activity_log (emploc_no, vcode, activity_type, description)
    VALUES (
      NEW.emploc_no,
      NEW.vcode,
      'deployed',
      'Employee deployed to Plantilla — ' || COALESCE(NEW.store_name, NEW.account)
    );
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.log_users_profile_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    INSERT INTO activity_log (
      target_table, target_id, target_name,
      action, old_value, new_value
    ) VALUES (
      'users_profile',
      NEW.id,
      NEW.full_name,
      CASE
        WHEN OLD.is_active = true  AND NEW.is_active = false THEN 'DEACTIVATE_USER'
        WHEN OLD.is_active = false AND NEW.is_active = true  THEN 'ACTIVATE_USER'
        WHEN OLD.role_id != NEW.role_id                      THEN 'ROLE_CHANGE'
        ELSE 'UPDATE_USER'
      END,
      jsonb_build_object(
        'full_name', OLD.full_name,
        'email',     OLD.email,
        'role_id',   OLD.role_id,
        'is_active', OLD.is_active
      ),
      jsonb_build_object(
        'full_name', NEW.full_name,
        'email',     NEW.email,
        'role_id',   NEW.role_id,
        'is_active', NEW.is_active
      )
    );
  ELSIF TG_OP = 'INSERT' THEN
    INSERT INTO activity_log (
      target_table, target_id, target_name,
      action, new_value
    ) VALUES (
      'users_profile',
      NEW.id,
      NEW.full_name,
      'CREATE_USER',
      jsonb_build_object(
        'full_name', NEW.full_name,
        'email',     NEW.email,
        'role_id',   NEW.role_id,
        'is_active', NEW.is_active
      )
    );
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT;
BEGIN
  UPDATE public.notifications
  SET is_read = true, read_at = NOW()
  WHERE recipient_user_id = auth.uid()
    AND read_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$
;

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

CREATE OR REPLACE FUNCTION public.mark_headcount_request_under_review(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_req headcount_requests%ROWTYPE;
begin
  if not public.i_have_full_access() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select * into v_req from public.headcount_requests where id = p_request_id for update;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_req.status <> 'pending' then
    return jsonb_build_object('ok', false, 'error', 'invalid_status_transition', 'current', v_req.status);
  end if;

  update public.headcount_requests
  set status              = 'under_review',
      reviewed_by_user_id = public.get_current_profile_id(),
      reviewed_by_name    = public.get_my_full_name(),
      reviewed_at         = now()
  where id = p_request_id;

  return jsonb_build_object(
    'ok',         true,
    'request_id', p_request_id,
    'status',     'under_review'
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.notifications
  SET is_read = true, read_at = NOW()
  WHERE id = p_notification_id
    AND recipient_user_id = auth.uid()
    AND read_at IS NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.mask_name(p_name text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  parts TEXT[];
  first_initial TEXT;
  last_word TEXT;
BEGIN
  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN RETURN '—'; END IF;
  parts := regexp_split_to_array(trim(p_name), '\s+');
  first_initial := upper(substr(parts[1], 1, 1));
  last_word := parts[array_length(parts, 1)];
  IF length(last_word) <= 2 THEN
    RETURN first_initial || '. ' || left(last_word, 1) || '***';
  END IF;
  RETURN first_initial || '. ' || upper(left(last_word, 1)) || '***' || right(last_word, 1);
END $function$
;

CREATE OR REPLACE FUNCTION public.merge_as_roving_emploc(p_master_hr_emploc_id uuid, p_duplicate_hr_emploc_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor       uuid := public.get_my_profile_id();
  v_actor_name  text := public.get_my_full_name();
  v_master      public.hr_emploc%ROWTYPE;
  v_dup         public.hr_emploc%ROWTYPE;
  v_roving_id   uuid;
  v_vac         public.vacancies%ROWTYPE;
BEGIN
  -- ── Auth: Data Team only ──────────────────────────────────────────────────
  IF NOT (public.i_have_full_access() OR public.get_my_role() = 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock both records ───────────────────────────────────────────
  SELECT * INTO v_master
    FROM public.hr_emploc
   WHERE id = p_master_hr_emploc_id
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'master hr_emploc % not found or already deleted', p_master_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_dup
    FROM public.hr_emploc
   WHERE id = p_duplicate_hr_emploc_id
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'duplicate hr_emploc % not found or already deleted', p_duplicate_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Guard: same person ────────────────────────────────────────────────────
  IF v_master.applicant_name <> v_dup.applicant_name THEN
    RAISE EXCEPTION 'cannot merge: different applicant names (% vs %)',
      v_master.applicant_name, v_dup.applicant_name
      USING ERRCODE = '22023';
  END IF;

  -- ── Guard: same account ───────────────────────────────────────────────────
  IF v_master.account <> v_dup.account THEN
    RAISE EXCEPTION 'cannot merge: different accounts (% vs %)',
      v_master.account, v_dup.account
      USING ERRCODE = '22023';
  END IF;

  -- ── Guard: neither already in Plantilla ──────────────────────────────────
  IF v_master.status = 'Moved to Plantilla' OR v_dup.status = 'Moved to Plantilla' THEN
    RAISE EXCEPTION 'cannot merge: one or both records already moved to Plantilla'
      USING ERRCODE = '22023';
  END IF;

  -- ── Guard: master must not already be a different roving group ────────────
  IF v_master.roving_assignment_id IS NOT NULL
     AND v_dup.roving_assignment_id IS NOT NULL
     AND v_master.roving_assignment_id <> v_dup.roving_assignment_id THEN
    RAISE EXCEPTION 'cannot merge: records belong to different roving groups'
      USING ERRCODE = '22023';
  END IF;

  -- ── Resolve or create roving_assignment_id ────────────────────────────────
  v_roving_id := COALESCE(
    v_master.roving_assignment_id,
    v_dup.roving_assignment_id
  );

  IF v_roving_id IS NULL THEN
    -- Neither has a roving group yet — create one
    INSERT INTO public.roving_assignments (
      id, master_applicant_id, account, account_id,
      group_id, label, primary_vcode, created_at, updated_at
    )
    SELECT
      gen_random_uuid(),
      v_master.applicant_id,
      v_master.account,
      v_master.account_id,
      a.group_id,
      v_master.applicant_name || ' — Roving',
      v_master.vcode,
      NOW(), NOW()
    FROM public.accounts a
    WHERE a.id = v_master.account_id
    RETURNING id INTO v_roving_id;
  END IF;

  -- ── Update both applicants → set roving_assignment_id ────────────────────
  UPDATE public.applicants
     SET roving_assignment_id = v_roving_id,
         updated_at           = NOW()
   WHERE id IN (v_master.applicant_id, v_dup.applicant_id);

  -- ── Convert master → Roving ───────────────────────────────────────────────
  UPDATE public.hr_emploc
     SET assignment_type      = 'Roving'::public.hr_emploc_assignment_type,
         roving_assignment_id = v_roving_id,
         vacancy_id           = NULL,
         store_id             = NULL,
         store_name           = NULL,
         updated_at           = NOW(),
         updated_by           = v_actor
   WHERE id = p_master_hr_emploc_id;

  -- ── Insert store link for master's store (if not already exists) ──────────
  INSERT INTO public.hr_emploc_store_links (
    hr_emploc_id, roving_assignment_id,
    vacancy_id, vcode, store_name, account,
    status, confirmed_at, created_by, updated_by,
    created_at, updated_at
  )
  SELECT
    p_master_hr_emploc_id,
    v_roving_id,
    v.id,
    v_master.vcode,
    v.store_name,
    v_master.account,
    'Confirmed',
    NOW(),
    v_actor, v_actor,
    NOW(), NOW()
  FROM public.vacancies v
  WHERE v.vcode = v_master.vcode
  ON CONFLICT DO NOTHING;

  -- ── Insert store link for duplicate's store ───────────────────────────────
  INSERT INTO public.hr_emploc_store_links (
    hr_emploc_id, roving_assignment_id,
    vacancy_id, vcode, store_name, account,
    status, confirmed_at, created_by, updated_by,
    created_at, updated_at
  )
  SELECT
    p_master_hr_emploc_id,
    v_roving_id,
    v.id,
    v_dup.vcode,
    v.store_name,
    v_dup.account,
    'Confirmed',
    NOW(),
    v_actor, v_actor,
    NOW(), NOW()
  FROM public.vacancies v
  WHERE v.vcode = v_dup.vcode
  ON CONFLICT DO NOTHING;

  -- ── Soft-delete the duplicate master ─────────────────────────────────────
  UPDATE public.hr_emploc
     SET deleted_at = NOW(),
         updated_at = NOW(),
         updated_by = v_actor
   WHERE id = p_duplicate_hr_emploc_id;

  -- ── Audit ─────────────────────────────────────────────────────────────────
  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    COALESCE(v_master.employee_no, v_master.applicant_name),
    v_master.vcode,
    'merged_as_roving',
    'Duplicate HR Emploc merged into roving master by ' || v_actor_name,
    v_actor_name,
    jsonb_build_object(
      'master_hr_emploc_id',    p_master_hr_emploc_id,
      'duplicate_hr_emploc_id', p_duplicate_hr_emploc_id,
      'roving_assignment_id',   v_roving_id,
      'master_vcode',           v_master.vcode,
      'duplicate_vcode',        v_dup.vcode,
      'merged_by',              v_actor_name,
      'merged_at',              NOW()
    )
  );

  RETURN jsonb_build_object(
    'ok',                      true,
    'master_hr_emploc_id',     p_master_hr_emploc_id,
    'duplicate_hr_emploc_id',  p_duplicate_hr_emploc_id,
    'roving_assignment_id',    v_roving_id,
    'master_vcode',            v_master.vcode,
    'duplicate_vcode',         v_dup.vcode,
    'store_links_created',     2,
    'duplicate_deleted',       true
  );
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
  -- pool routing
  v_is_pool         boolean := false;
  v_pool_type_id    uuid;
  v_home_account_id uuid;
  v_home_acct       public.accounts;
BEGIN
  -- Data Team = Encoder (30) + Head Admin (90) + Super Admin (100)
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

  -- ── NEW A: Guard — hr_emploc_id already active in plantilla ───────────────
  -- Primary duplicate check. Covers all three paths (pool, roving, stationary).
  -- Catches re-moves even when employee_no was changed between attempts, which
  -- the existing employee_no-based guards in each path cannot detect.
  -- ERRCODE '23505' matches unique_violation so callers (frontend + bulk_move)
  -- can detect and handle it uniformly.
  IF EXISTS (
    SELECT 1
      FROM public.plantilla
     WHERE hr_emploc_id         = p_id
       AND COALESCE(is_deleted, false) = false
  ) THEN
    RAISE EXCEPTION
      'hr_emploc % already moved to plantilla',
      p_id
      USING ERRCODE = '23505';
  END IF;

  -- ── NEW B: Guard — moved_to_plantilla_at already stamped ─────────────────
  -- Belt-and-suspenders. The hr_emploc row itself records a completed move.
  -- Catches the edge case where plantilla row was soft-deleted but the
  -- hr_emploc timestamp was already written (should not occur normally).
  IF v_emp.moved_to_plantilla_at IS NOT NULL THEN
    RAISE EXCEPTION
      'hr_emploc % already has moved_to_plantilla_at set',
      p_id
      USING ERRCODE = '23505';
  END IF;

  -- ── Detect pool vacancy ───────────────────────────────────────────────────
  -- Roving HR Emploc has vacancy_id IS NULL; pool HR Emploc is stationary-type
  -- with a vacancy_id pointing to a pool vacancy.
  IF v_emp.vacancy_id IS NOT NULL THEN
    SELECT v.is_pool_vacancy, v.pool_type_id, v.home_account_id
      INTO v_is_pool, v_pool_type_id, v_home_account_id
      FROM vacancies v
     WHERE v.id = v_emp.vacancy_id;
  END IF;
  v_is_pool := COALESCE(v_is_pool, false);

  -- ── POOL PATH ─────────────────────────────────────────────────────────────
  IF v_is_pool THEN

    -- home_account_id is mandatory for pool routing
    IF v_home_account_id IS NULL THEN
      RAISE EXCEPTION 'pool vacancy % has no home_account_id — cannot route to pool', v_emp.vcode
        USING ERRCODE = '22023';
    END IF;

    -- Resolve Moses HQ account record
    SELECT * INTO v_home_acct FROM accounts WHERE id = v_home_account_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'home account % not found', v_home_account_id
        USING ERRCODE = 'P0002';
    END IF;

    -- Existing guard: employee must not already be active under Moses HQ pool
    -- (retained from previous migration — covers employee_no collision)
    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE employee_no = v_emp.employee_no
         AND account_id  = v_home_account_id
         AND is_deleted  = false
         AND status IN ('Active', 'For Deactivation', 'On Leave')
    ) THEN
      RAISE EXCEPTION
        'pool plantilla already has active record for employee_no % under home account',
        v_emp.employee_no
        USING ERRCODE = '23505';
    END IF;

    -- Insert under Moses HQ; no store or chain assignment
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

    -- Mark pool vacancy Filled (VCODE is preserved on the vacancy row)
    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

    -- Mark pool slot occupied; keep is_active=true so employee appears in
    -- v_workforce_pool_employees as Available (no active deployment yet)
    UPDATE public.workforce_pool_slots
       SET status     = 'filled',
           updated_at = NOW()
     WHERE vcode      = v_emp.vcode
       AND deleted_at IS NULL;

  -- ── ROVING PATH ───────────────────────────────────────────────────────────
  ELSIF v_emp.assignment_type = 'Roving' THEN

    -- Guard: plantilla master must not already exist for this roving group
    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE roving_assignment_id = v_emp.roving_assignment_id
         AND is_deleted = false
    ) THEN
      RAISE EXCEPTION
        'roving plantilla master already exists for roving_assignment_id %. Use link_late_store_to_plantilla for new store additions.',
        v_emp.roving_assignment_id
        USING ERRCODE = '23505';
    END IF;

    -- Guard: must have at least one confirmed store link
    IF NOT EXISTS (
      SELECT 1 FROM hr_emploc_store_links
       WHERE hr_emploc_id = p_id
         AND status = 'Confirmed'
         AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'no confirmed store links found for roving hr_emploc %', p_id
        USING ERRCODE = '22023';
    END IF;

    -- Create plantilla MASTER (person-level, no single store)
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

    -- Insert plantilla_store_links for all confirmed store links
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
      AND sl.status = 'Confirmed'
      AND sl.deleted_at IS NULL;

    -- Close all confirmed vacancies
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

  -- ── STATIONARY PATH (unchanged) ───────────────────────────────────────────
  ELSE

    -- Existing guard: employee must not already be active in any plantilla
    -- (retained from previous migration — covers employee_no collision)
    IF EXISTS (
      SELECT 1 FROM plantilla
       WHERE employee_no = v_emp.employee_no
         AND is_deleted  = false
         AND status IN ('Active', 'For Deactivation', 'On Leave')
    ) THEN
      RAISE EXCEPTION 'plantilla already has active record for employee_no %', v_emp.employee_no
        USING ERRCODE = '23505';
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

    IF v_emp.vacancy_id IS NOT NULL THEN
      UPDATE vacancies
         SET status     = 'Filled',
             updated_at = NOW(),
             updated_by = v_actor
       WHERE id = v_emp.vacancy_id;
    END IF;

  END IF;

  -- ── Common: update hr_emploc status ──────────────────────────────────────
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

CREATE OR REPLACE FUNCTION public.notification_sla_exists(p_event_type text, p_reference_id text, p_sla_level smallint)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.event_type = p_event_type
      AND n.reference_id = p_reference_id
      AND n.sla_level = p_sla_level
  );
$function$
;

CREATE OR REPLACE FUNCTION public.notify_account_request_actioned()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
  v_ha RECORD;
  v_recipient uuid;
BEGIN
  v_status := LOWER(NEW.status::TEXT);

  IF v_status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  v_recipient := NEW.auth_user_id;

  IF v_recipient IS NULL THEN
    SELECT auth_user_id INTO v_recipient
    FROM public.users_profile
    WHERE email = NEW.email OR full_name = NEW.full_name
    LIMIT 1;
  END IF;

  SELECT full_name INTO v_ha
  FROM public.users_profile
  WHERE id = COALESCE(NEW.approved_by, NEW.rejected_by, NEW.reviewed_by)
     OR auth_user_id = COALESCE(NEW.approved_by, NEW.rejected_by, NEW.reviewed_by)
  LIMIT 1;

  IF v_recipient IS NOT NULL THEN
    PERFORM public.notify_user(
      v_recipient,
      'Requestor',
      CASE WHEN v_status = 'approved' THEN 'Account Request Approved' ELSE 'Account Request Rejected' END,
      CASE WHEN v_status = 'approved'
        THEN 'Your account request has been approved by ' || COALESCE(v_ha.full_name, 'Head Admin') || '. You can now log in to OHMployee.'
        ELSE 'Your account request was rejected by ' || COALESCE(v_ha.full_name, 'Head Admin') || '. Reason: ' || COALESCE(NEW.rejection_reason, NEW.notes, 'No reason provided') || '.'
      END,
      CASE WHEN v_status = 'approved' THEN 'approval' ELSE 'rejection' END,
      'account_request',
      'account_request',
      NEW.id::TEXT,
      CASE WHEN v_status = 'approved' THEN '/login' ELSE FORMAT('/account-requests/%s', NEW.id) END,
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_account_request_submitted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ha RECORD;
  v_role_name TEXT;
  v_scope TEXT;
BEGIN
  SELECT role_name INTO v_role_name
  FROM public.roles
  WHERE id = NEW.requested_role_id
  LIMIT 1;

  v_scope := COALESCE(NEW.assigned_scope_type, NEW.email);

  FOR v_ha IN
    SELECT auth_user_id, role
    FROM public.users_profile
    WHERE role = 'Head Admin'
      AND is_active = true
      AND auth_user_id IS NOT NULL
  LOOP
    PERFORM public.notify_user(
      v_ha.auth_user_id,
      'Head Admin',
      'New Account Request',
      NEW.full_name || ' has submitted an account request for the role of ' || COALESCE(v_role_name, 'user') || ' under ' || v_scope || '. Please review.',
      'submission',
      'account_request',
      'account_request',
      NEW.id::TEXT,
      FORMAT('/account-requests/%s', NEW.id),
      NULL
    );
  END LOOP;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_deactivation_submitted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_requestor RECORD;
  v_group_id uuid;
  v_encoder RECORD;
BEGIN
  SELECT up.group_id
  INTO v_requestor
  FROM public.users_profile up
  WHERE up.full_name = NEW.requested_by
  LIMIT 1;

  v_group_id := v_requestor.group_id;

  IF v_group_id IS NULL AND NEW.group_name IS NOT NULL THEN
    SELECT g.id INTO v_group_id
    FROM public.groups g
    WHERE g.group_name = NEW.group_name
    LIMIT 1;
  END IF;

  SELECT up.auth_user_id, up.role
  INTO v_encoder
  FROM public.users_profile up
  WHERE up.role = 'Encoder'
    AND up.is_active = true
    AND up.auth_user_id IS NOT NULL
    AND up.group_id = v_group_id
  LIMIT 1;

  IF v_encoder.auth_user_id IS NOT NULL THEN
    PERFORM public.notify_user(
      v_encoder.auth_user_id,
      'Encoder',
      'Deactivation Request — ' || COALESCE(NEW.group_name, 'Account'),
      NEW.requested_by || ' has submitted a deactivation request for ' || COALESCE(NEW.total_employees, 0)::TEXT || ' employee/s under ' || COALESCE(NEW.group_name, 'the account') || '. Please review.',
      'submission',
      'deactivation',
      'deactivation',
      NEW.id::TEXT,
      FORMAT('/deactivation-requests/%s', NEW.id),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_hc_request_actioned()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_requestor RECORD;
  v_status TEXT;
  v_vcode TEXT;
BEGIN
  v_status := LOWER(NEW.status);

  SELECT auth_user_id, role
  INTO v_requestor
  FROM public.users_profile
  WHERE auth_user_id = NEW.requested_by_user_id OR id = NEW.requested_by_user_id
  LIMIT 1;

  IF COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id) IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_status IN ('approved', 'head admin approved', 'ha approved') THEN
    PERFORM public.notify_user(
      COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id),
      COALESCE(v_requestor.role, NEW.requested_by_role),
      'HC Request Approved',
      'Your headcount request for ' || COALESCE(NEW.account_name_snapshot, 'the account') || ' has been approved. Vcode creation is in progress.',
      'approval',
      'hc_request',
      'headcount_request',
      NEW.id::TEXT,
      FORMAT('/headcount-requests/%s', NEW.id),
      NULL
    );
  ELSIF v_status = 'rejected' THEN
    PERFORM public.notify_user(
      COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id),
      COALESCE(v_requestor.role, NEW.requested_by_role),
      'HC Request Rejected',
      'Your headcount request for ' || COALESCE(NEW.account_name_snapshot, 'the account') || ' was rejected by ' || COALESCE(NEW.reviewed_by_name, NEW.head_admin_approved_by_name, 'Head Admin') || '. Reason: ' || COALESCE(NEW.reviewer_remarks, NEW.head_admin_remarks, 'No reason provided') || '.',
      'rejection',
      'hc_request',
      'headcount_request',
      NEW.id::TEXT,
      FORMAT('/headcount-requests/%s', NEW.id),
      NULL
    );
  END IF;

  IF COALESCE(NEW.created_vcode, '') <> '' AND NEW.created_vcode IS DISTINCT FROM OLD.created_vcode THEN
    v_vcode := NEW.created_vcode;
  ELSIF NEW.created_vcodes IS NOT NULL AND NEW.created_vcodes IS DISTINCT FROM OLD.created_vcodes THEN
    v_vcode := NEW.created_vcodes[1];
  END IF;

  IF v_vcode IS NOT NULL THEN
    PERFORM public.notify_user(
      COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id),
      COALESCE(v_requestor.role, NEW.requested_by_role),
      'Vcode Created',
      'Vcode ' || v_vcode || ' has been created for your headcount request under ' || COALESCE(NEW.account_name_snapshot, 'the account') || '.',
      'approval',
      'hc_request',
      'vacancy',
      v_vcode,
      FORMAT('/vacancies/%s', v_vcode),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_hc_request_approved_pending_vcode()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_encoder record;
  v_notified_count integer := 0;
begin
  if not (
    old.status is distinct from new.status
    and new.status = 'approved_pending_vcode'
  ) then
    return new;
  end if;

  for v_encoder in
    select distinct up.auth_user_id, up.role
    from public.users_profile up
    where up.role = 'Encoder'
      and up.is_active = true
      and up.auth_user_id is not null
      and (
        coalesce(up.scope_type, 'scoped') = 'global'
        or up.group_id = new.group_id
        or up.account_id = new.account_id
        or exists (
          select 1
          from public.user_scopes us
          where us.user_id = up.id
            and (
              (new.group_id is not null and us.group_id = new.group_id)
              or (new.account_id is not null and us.account_id = new.account_id)
            )
        )
      )
  loop
    perform public.notify_user(
      v_encoder.auth_user_id,
      'Encoder',
      'HC Request Approved — VCODE Needed',
      coalesce(new.head_admin_approved_by_name, 'Head Admin')
        || ' approved a headcount request for '
        || coalesce(new.account_name_snapshot, 'the account')
        || ' (' || coalesce(new.position_name_snapshot, 'Position')
        || ', ' || coalesce(new.headcount_needed, 1)::text
        || ' slot/s). Please create the VCODE and plantilla slot.',
      'approval',
      'hc_request',
      'headcount_request',
      new.id::text,
      format('/headcount-requests/%s', new.id),
      null
    );

    v_notified_count := v_notified_count + 1;
  end loop;

  if v_notified_count = 0 then
    perform public.log_audit_event(
      'HeadcountRequest.ApprovedPendingVcode.NoEncoderRecipient',
      'UPDATE',
      new.id,
      to_jsonb(old),
      jsonb_build_object(
        'request_id', new.id,
        'group_id', new.group_id,
        'account_id', new.account_id,
        'status', new.status,
        'reason', 'No active scoped Encoder auth_user_id found'
      )
    );
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_hc_request_submitted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ha RECORD;
BEGIN
  FOR v_ha IN
    SELECT auth_user_id, role
    FROM public.users_profile
    WHERE role = 'Head Admin'
      AND is_active = true
      AND auth_user_id IS NOT NULL
  LOOP
    PERFORM public.notify_user(
      v_ha.auth_user_id,
      'Head Admin',
      'New HC Request — ' || COALESCE(NEW.group_name_snapshot, 'Group'),
      NEW.requested_by_name || ' submitted a headcount request for ' || COALESCE(NEW.account_name_snapshot, 'the account') || ' (' || COALESCE(NEW.position_name_snapshot, 'Position') || ', ' || NEW.headcount_needed::TEXT || ' slot/s). Please review.',
      'submission',
      'hc_request',
      'headcount_request',
      NEW.id::TEXT,
      FORMAT('/headcount-requests/%s', NEW.id),
      NULL
    );
  END LOOP;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_hr_emploc_correction_submitted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hr_personnel RECORD;
  v_hrco RECORD;
BEGIN
  IF NEW.hr_status = 'For Review' AND OLD.hr_status = 'For Correction' THEN
    SELECT auth_user_id, role
    INTO v_hr_personnel
    FROM public.users_profile
    WHERE (id = NEW.hr_personnel_user_id OR auth_user_id = NEW.hr_personnel_user_id)
      AND auth_user_id IS NOT NULL
    LIMIT 1;

    SELECT full_name
    INTO v_hrco
    FROM public.users_profile
    WHERE id = NEW.hrco_user_id_snapshot OR auth_user_id = NEW.hrco_user_id_snapshot
    LIMIT 1;

    IF v_hr_personnel.auth_user_id IS NOT NULL THEN
      PERFORM public.notify_user(
        v_hr_personnel.auth_user_id,
        COALESCE(v_hr_personnel.role, 'HR Personnel'),
        'HR Emploc Correction Submitted',
        COALESCE(v_hrco.full_name, 'HRCO') || ' has submitted the required corrections for ' || NEW.applicant_name || '''s HR Emploc record. Please verify and mark as resolved.',
        'correction',
        'correction',
        'hr_emploc',
        NEW.id::TEXT,
        FORMAT('/hr-emploc/%s/correction', NEW.id),
        NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_hr_emploc_correction_tagged()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_hrco record;
  v_hr_personnel record;
  v_requestor record;
  v_labels text;
  v_hr_personnel_id uuid;
begin
  if new.hr_status = 'For Correction'
     and old.hr_status is distinct from 'For Correction' then

    v_hr_personnel_id := coalesce(new.hr_personnel_user_id, public.get_my_profile_id());

    if new.hr_personnel_user_id is null and v_hr_personnel_id is not null then
      update public.hr_emploc
      set hr_personnel_user_id = v_hr_personnel_id
      where id = new.id;
    end if;

    select auth_user_id, role, full_name
    into v_requestor
    from public.users_profile
    where (
      id = new.last_correction_submitter_user_id
      or auth_user_id = new.last_correction_submitter_user_id
    )
      and auth_user_id is not null
    limit 1;

    if v_requestor.auth_user_id is null then
      select auth_user_id, role, full_name
      into v_requestor
      from public.users_profile
      where (
        id = new.deployed_by_user_id
        or auth_user_id = new.deployed_by_user_id
      )
        and auth_user_id is not null
      limit 1;
    end if;

    select auth_user_id, role
    into v_hrco
    from public.users_profile
    where (id = new.hrco_user_id_snapshot or auth_user_id = new.hrco_user_id_snapshot)
      and auth_user_id is not null
    limit 1;

    select full_name
    into v_hr_personnel
    from public.users_profile
    where id = v_hr_personnel_id or auth_user_id = v_hr_personnel_id
    limit 1;

    select string_agg(
      case value
        when 'INVALID_SSS' then 'Invalid SSS'
        when 'INVALID_PHILHEALTH' then 'Invalid PhilHealth'
        when 'INVALID_PAGIBIG' then 'Invalid Pag-Ibig'
        when 'INCOMPLETE_INFO' then 'Incomplete Info'
        when 'INCOMPLETE_REQUIREMENT' then 'Incomplete Requirement'
        else value
      end,
      ', '
    ) into v_labels
    from jsonb_array_elements_text(coalesce(new.correction_reason, '[]'::jsonb));

    if v_requestor.auth_user_id is not null then
      perform public.notify_user(
        v_requestor.auth_user_id,
        coalesce(v_requestor.role, 'HRCO'),
        'HR Emploc Requires Correction — ' || new.account,
        coalesce(v_hr_personnel.full_name, 'HR Personnel')
          || ' flagged '
          || new.applicant_name
          || '''s HR Emploc record for correction. Issue/s: '
          || coalesce(v_labels, 'Unspecified')
          || '. Please review and update.',
        'correction',
        'correction',
        'hr_emploc',
        new.id::text,
        format('/hr-emploc/%s/correction', new.id),
        null
      );
    end if;

    if v_hrco.auth_user_id is not null
       and v_hrco.auth_user_id is distinct from v_requestor.auth_user_id then
      perform public.notify_user(
        v_hrco.auth_user_id,
        coalesce(v_hrco.role, 'HRCO'),
        'HR Emploc Requires Correction — ' || new.account,
        coalesce(v_hr_personnel.full_name, 'HR Personnel')
          || ' flagged '
          || new.applicant_name
          || '''s HR Emploc record for correction. Issue/s: '
          || coalesce(v_labels, 'Unspecified')
          || '. Please review and update.',
        'correction',
        'correction',
        'hr_emploc',
        new.id::text,
        format('/hr-emploc/%s/correction', new.id),
        null
      );
    end if;
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_hr_emploc_to_plantilla()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hrco RECORD;
  v_encoder RECORD;
  v_plantilla_id uuid;
BEGIN
  IF NEW.status = 'Moved to Plantilla' AND OLD.status IS DISTINCT FROM 'Moved to Plantilla' THEN
    SELECT auth_user_id, role
    INTO v_hrco
    FROM public.users_profile
    WHERE (id = NEW.hrco_user_id_snapshot OR auth_user_id = NEW.hrco_user_id_snapshot)
      AND auth_user_id IS NOT NULL
    LIMIT 1;

    SELECT full_name
    INTO v_encoder
    FROM public.users_profile
    WHERE id = NEW.moved_to_plantilla_by OR auth_user_id = NEW.moved_to_plantilla_by
    LIMIT 1;

    SELECT id INTO v_plantilla_id
    FROM public.plantilla
    WHERE hr_emploc_id = NEW.id
       OR (emploc_no IS NOT NULL AND emploc_no = NEW.emploc_no)
       OR (employee_no IS NOT NULL AND employee_no = NEW.employee_no)
    ORDER BY created_at DESC NULLS LAST
    LIMIT 1;

    IF v_hrco.auth_user_id IS NOT NULL THEN
      PERFORM public.notify_user(
        v_hrco.auth_user_id,
        COALESCE(v_hrco.role, 'HRCO'),
        'Employee Moved to Plantilla — ' || NEW.account,
        NEW.applicant_name || ' (' || NEW.vcode || ') has been successfully moved to Plantilla by ' || COALESCE(v_encoder.full_name, 'Encoder') || '.',
        'plantilla',
        'correction',
        'plantilla',
        COALESCE(v_plantilla_id::TEXT, NEW.id::TEXT),
        CASE WHEN v_plantilla_id IS NOT NULL THEN FORMAT('/plantilla/%s', v_plantilla_id) ELSE FORMAT('/hr-emploc/%s', NEW.id) END,
        NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_mika_import_actioned()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uploader RECORD;
  v_status TEXT;
BEGIN
  v_status := LOWER(COALESCE(NEW.status, ''));

  IF v_status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT auth_user_id, role
  INTO v_uploader
  FROM public.users_profile
  WHERE full_name = NEW.uploaded_by
    AND auth_user_id IS NOT NULL
  LIMIT 1;

  IF v_uploader.auth_user_id IS NOT NULL THEN
    PERFORM public.notify_user(
      v_uploader.auth_user_id,
      COALESCE(v_uploader.role, 'Head Admin'),
      CASE WHEN v_status = 'approved' THEN 'MIKA Import Approved' ELSE 'MIKA Import Rejected' END,
      CASE WHEN v_status = 'approved'
        THEN 'Your MIKA import (' || NEW.file_name || ') has been approved by ' || COALESCE(NEW.approved_by, 'Super Admin') || '. Data sync is now in progress.'
        ELSE 'Your MIKA import (' || NEW.file_name || ') was rejected by ' || COALESCE(NEW.approved_by, 'Super Admin') || '. Reason: ' || COALESCE(NEW.remarks, 'No reason provided') || '.'
      END,
      CASE WHEN v_status = 'approved' THEN 'approval' ELSE 'rejection' END,
      'mika_import',
      'mika_import',
      NEW.id::TEXT,
      FORMAT('/mika-import/%s', NEW.id),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_mika_import_uploaded()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sa RECORD;
BEGIN
  FOR v_sa IN
    SELECT auth_user_id, role
    FROM public.users_profile
    WHERE role = 'Super Admin'
      AND is_active = true
      AND auth_user_id IS NOT NULL
  LOOP
    PERFORM public.notify_user(
      v_sa.auth_user_id,
      'Super Admin',
      'New MIKA Import — ' || NEW.file_name,
      NEW.uploaded_by || ' uploaded a MIKA file (' || COALESCE(NEW.total_rows, 0)::TEXT || ' rows) for review. Please approve or reject.',
      'submission',
      'mika_import',
      'mika_import',
      NEW.id::TEXT,
      FORMAT('/mika-import/%s', NEW.id),
      NULL
    );
  END LOOP;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_store_import_actioned()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uploader RECORD;
  v_reviewer RECORD;
  v_group_name TEXT;
  v_status TEXT;
BEGIN
  v_status := LOWER(COALESCE(NEW.status, ''));

  IF v_status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT auth_user_id, role
  INTO v_uploader
  FROM public.users_profile
  WHERE id = NEW.uploaded_by OR auth_user_id = NEW.uploaded_by
  LIMIT 1;

  SELECT full_name
  INTO v_reviewer
  FROM public.users_profile
  WHERE id = COALESCE(NEW.approved_by, NEW.rejected_by) OR auth_user_id = COALESCE(NEW.approved_by, NEW.rejected_by)
  LIMIT 1;

  SELECT group_name INTO v_group_name
  FROM public.groups
  WHERE id = NEW.selected_group_id
  LIMIT 1;

  IF v_uploader.auth_user_id IS NOT NULL THEN
    PERFORM public.notify_user(
      v_uploader.auth_user_id,
      COALESCE(v_uploader.role, 'Encoder'),
      CASE WHEN v_status = 'approved' THEN 'Store Import Approved' ELSE 'Store Import Rejected' END,
      CASE WHEN v_status = 'approved'
        THEN 'Your store import for ' || COALESCE(v_group_name, 'the group') || ' has been approved by ' || COALESCE(v_reviewer.full_name, 'Head Admin') || '.'
        ELSE 'Your store import for ' || COALESCE(v_group_name, 'the group') || ' was rejected by ' || COALESCE(v_reviewer.full_name, 'Head Admin') || '. Reason: ' || COALESCE(NEW.rejection_reason, 'No reason provided') || '.'
      END,
      CASE WHEN v_status = 'approved' THEN 'approval' ELSE 'rejection' END,
      'store_import',
      'store_import',
      NEW.id::TEXT,
      FORMAT('/store-import/%s', NEW.id),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_store_import_uploaded()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ha RECORD;
  v_encoder RECORD;
  v_group_name TEXT;
BEGIN
  SELECT full_name INTO v_encoder
  FROM public.users_profile
  WHERE id = NEW.uploaded_by OR auth_user_id = NEW.uploaded_by
  LIMIT 1;

  SELECT group_name INTO v_group_name
  FROM public.groups
  WHERE id = NEW.selected_group_id
  LIMIT 1;

  FOR v_ha IN
    SELECT auth_user_id, role
    FROM public.users_profile
    WHERE role = 'Head Admin'
      AND is_active = true
      AND auth_user_id IS NOT NULL
      AND group_id = NEW.selected_group_id
  LOOP
    PERFORM public.notify_user(
      v_ha.auth_user_id,
      'Head Admin',
      'New Store Import — ' || COALESCE(v_group_name, 'Group'),
      COALESCE(v_encoder.full_name, 'Encoder') || ' uploaded a store master file (' || NEW.total_rows::TEXT || ' rows) for ' || COALESCE(v_group_name, 'the group') || '. Please review.',
      'submission',
      'store_import',
      'store_import',
      NEW.id::TEXT,
      FORMAT('/store-import/%s', NEW.id),
      NULL
    );
  END LOOP;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_user(p_recipient_user_id uuid, p_recipient_role text, p_title text, p_message text, p_notification_type text, p_event_type text, p_reference_type text, p_reference_id text, p_deep_link_route text, p_sla_level smallint DEFAULT NULL::smallint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.notifications (
    recipient_user_id,
    recipient_role,
    title,
    message,
    notification_type,
    event_type,
    reference_type,
    reference_id,
    deep_link_route,
    sla_level,
    is_read,
    created_at
  ) VALUES (
    p_recipient_user_id,
    p_recipient_role,
    p_title,
    p_message,
    p_notification_type,
    p_event_type,
    p_reference_type,
    p_reference_id,
    p_deep_link_route,
    p_sla_level,
    FALSE,
    NOW()
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.plantilla_get_atm(p_plantilla_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_atm text;
  v_account text;
  v_role text := public.get_my_role();
begin
  if v_role = 'Viewer' then
    raise exception 'forbidden: viewer cannot reveal ATM information' using errcode = '42501';
  end if;

  select atm_no, account
  into v_atm, v_account
  from public.plantilla
  where id = p_plantilla_id
    and coalesce(is_deleted, false) = false;

  if not found then
    raise exception 'plantilla not found';
  end if;

  if not public.i_have_full_access()
     and not (v_account = any(public.get_my_allowed_accounts())) then
    raise exception 'forbidden: account out of scope' using errcode = '42501';
  end if;

  perform public._log_employee_action(
    p_plantilla_id,
    'ATM_REVEAL',
    format('%s revealed ATM info', public.get_my_full_name()),
    null,
    jsonb_build_object(
      'revealed_by_role', v_role,
      'revealed_at', now()
    )
  );

  return v_atm;
end;
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

CREATE OR REPLACE FUNCTION public.qa_calculate_next_run_at(p_frequency text, p_run_time time without time zone, p_timezone text DEFAULT 'Asia/Manila'::text, p_from timestamp with time zone DEFAULT now())
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_local_now timestamp;
  v_candidate timestamp;
begin
  v_local_now := p_from at time zone coalesce(p_timezone, 'Asia/Manila');

  if p_frequency = 'hourly' then
    return date_trunc('hour', p_from) + interval '1 hour';
  elsif p_frequency = 'daily' then
    v_candidate := date_trunc('day', v_local_now) + coalesce(p_run_time, '06:00'::time);
    if v_candidate <= v_local_now then
      v_candidate := v_candidate + interval '1 day';
    end if;
    return v_candidate at time zone coalesce(p_timezone, 'Asia/Manila');
  elsif p_frequency = 'weekly' then
    v_candidate := date_trunc('day', v_local_now) + coalesce(p_run_time, '06:00'::time);
    if v_candidate <= v_local_now then
      v_candidate := v_candidate + interval '7 days';
    end if;
    return v_candidate at time zone coalesce(p_timezone, 'Asia/Manila');
  elsif p_frequency = 'monthly' then
    v_candidate := date_trunc('day', v_local_now) + coalesce(p_run_time, '06:00'::time);
    if v_candidate <= v_local_now then
      v_candidate := v_candidate + interval '1 month';
    end if;
    return v_candidate at time zone coalesce(p_timezone, 'Asia/Manila');
  else
    return null;
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_complete_detection_run(p_run_id uuid, p_summary text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_counts jsonb;
  v_total int;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can complete QA detection runs';
  end if;

  select jsonb_build_object(
    'critical', count(*) filter (where severity = 'critical'),
    'high', count(*) filter (where severity = 'high'),
    'medium', count(*) filter (where severity = 'medium'),
    'low', count(*) filter (where severity = 'low'),
    'total', count(*)
  )
  into v_counts
  from public.qa_agent_findings
  where run_id = p_run_id;

  v_total := coalesce((v_counts ->> 'total')::int, 0);

  update public.qa_agent_runs
  set status = case when v_total > 0 then 'failed' else 'completed' end,
      completed_at = now(),
      summary = coalesce(p_summary, case when v_total > 0 then 'Detection completed with findings.' else 'Detection completed with no findings.' end),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('finding_counts', v_counts)
  where id = p_run_id;

  return v_counts;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_detect_duplicate_active_employee_numbers(p_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run_id uuid;
  v_count int := 0;
  r record;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can run QA detection';
  end if;

  v_run_id := coalesce(p_run_id, public.qa_start_detection_run('QA_DETECTION_ENGINE', 'employees', '{"check":"duplicate_active_employee_numbers"}'::jsonb));

  for r in
    select employee_no, count(*) as duplicate_count, array_agg(id) as record_ids
    from public.employees
    where employee_no is not null
      and btrim(employee_no) <> ''
      and status = 'Active'
    group by employee_no
    having count(*) > 1
  loop
    v_count := v_count + 1;
    perform public.qa_log_detection_finding(
      v_run_id,
      'critical',
      'duplicate_active_employee_number',
      'employees',
      'employees',
      null,
      'Duplicate active employee number detected: ' || r.employee_no,
      'Employee number appears on ' || r.duplicate_count || ' active employee records.',
      'Review employee master records and merge/archive duplicates. Do not hard delete.',
      jsonb_build_object('employee_no', r.employee_no, 'duplicate_count', r.duplicate_count, 'record_ids', r.record_ids)
    );
  end loop;

  return jsonb_build_object('run_id', v_run_id, 'findings_created', v_count);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_detect_duplicate_active_vcodes(p_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run_id uuid;
  v_count int := 0;
  r record;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can run QA detection';
  end if;

  v_run_id := coalesce(p_run_id, public.qa_start_detection_run('QA_DETECTION_ENGINE', 'vacancies', '{"check":"duplicate_active_vcodes"}'::jsonb));

  for r in
    select vcode, count(*) as duplicate_count, array_agg(id) as record_ids
    from public.vacancies
    where vcode is not null
      and btrim(vcode) <> ''
      and coalesce(is_archived, false) = false
      and deleted_at is null
      and status not in ('Closed','Archived')
    group by vcode
    having count(*) > 1
  loop
    v_count := v_count + 1;
    perform public.qa_log_detection_finding(
      v_run_id,
      'critical',
      'duplicate_active_vcode',
      'vacancies',
      'vacancies',
      null,
      'Duplicate active VCODE detected: ' || r.vcode,
      'VCODE appears on ' || r.duplicate_count || ' active vacancy records.',
      'Review VCODE generation and active vacancy lifecycle. Do not hard delete.',
      jsonb_build_object('vcode', r.vcode, 'duplicate_count', r.duplicate_count, 'record_ids', r.record_ids)
    );
  end loop;

  return jsonb_build_object('run_id', v_run_id, 'findings_created', v_count);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_detect_orphan_hr_emploc(p_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run_id uuid;
  v_count int := 0;
  r record;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can run QA detection';
  end if;

  v_run_id := coalesce(p_run_id, public.qa_start_detection_run('QA_DETECTION_ENGINE', 'hr_emploc', '{"check":"orphan_hr_emploc"}'::jsonb));

  for r in
    select h.id, h.applicant_name, h.vcode, h.vacancy_id, h.applicant_id
    from public.hr_emploc h
    left join public.vacancies v on v.id = h.vacancy_id
    left join public.applicants a on a.id = h.applicant_id
    where h.deleted_at is null
      and (
        (h.vacancy_id is not null and v.id is null)
        or (h.applicant_id is not null and a.id is null)
        or (h.vcode is not null and not exists (select 1 from public.vacancies vx where vx.vcode = h.vcode))
      )
  loop
    v_count := v_count + 1;
    perform public.qa_log_detection_finding(
      v_run_id,
      'high',
      'orphan_hr_emploc_record',
      'hr_emploc',
      'hr_emploc',
      r.id,
      'Orphan HR Emploc record detected',
      'HR Emploc record has missing applicant, vacancy, or VCODE linkage.',
      'Review Vacancy → HR Emploc linkage and repair references through approved workflow.',
      jsonb_build_object('hr_emploc_id', r.id, 'applicant_name', r.applicant_name, 'vcode', r.vcode, 'vacancy_id', r.vacancy_id, 'applicant_id', r.applicant_id)
    );
  end loop;

  return jsonb_build_object('run_id', v_run_id, 'findings_created', v_count);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_detect_orphan_plantilla(p_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run_id uuid;
  v_count int := 0;
  r record;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can run QA detection';
  end if;

  v_run_id := coalesce(p_run_id, public.qa_start_detection_run('QA_DETECTION_ENGINE', 'plantilla', '{"check":"orphan_plantilla"}'::jsonb));

  for r in
    select p.id, p.employee_name, p.employee_no, p.vcode, p.hr_emploc_id, p.vacancy_id
    from public.plantilla p
    left join public.hr_emploc h on h.id = p.hr_emploc_id
    left join public.vacancies v on v.id = p.vacancy_id
    where coalesce(p.is_deleted, false) = false
      and (
        (p.hr_emploc_id is not null and h.id is null)
        or (p.vacancy_id is not null and v.id is null)
        or (p.vcode is not null and not exists (select 1 from public.vacancies vx where vx.vcode = p.vcode))
      )
  loop
    v_count := v_count + 1;
    perform public.qa_log_detection_finding(
      v_run_id,
      'high',
      'orphan_plantilla_record',
      'plantilla',
      'plantilla',
      r.id,
      'Orphan Plantilla record detected',
      'Plantilla record has missing HR Emploc, vacancy, or VCODE linkage.',
      'Review HR Emploc → Plantilla transition and repair references through approved workflow.',
      jsonb_build_object('plantilla_id', r.id, 'employee_name', r.employee_name, 'employee_no', r.employee_no, 'vcode', r.vcode, 'hr_emploc_id', r.hr_emploc_id, 'vacancy_id', r.vacancy_id)
    );
  end loop;

  return jsonb_build_object('run_id', v_run_id, 'findings_created', v_count);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_detect_workflow_status_mismatch(p_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run_id uuid;
  v_count int := 0;
  r record;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can run QA detection';
  end if;

  v_run_id := coalesce(p_run_id, public.qa_start_detection_run('QA_DETECTION_ENGINE', 'workflow', '{"check":"workflow_status_mismatch"}'::jsonb));

  for r in
    select h.id, h.applicant_name, h.vcode, h.status as hr_status, p.id as plantilla_id, p.status as plantilla_status
    from public.hr_emploc h
    join public.plantilla p on p.hr_emploc_id = h.id
    where h.deleted_at is null
      and coalesce(p.is_deleted, false) = false
      and h.status <> 'Moved to Plantilla'
  loop
    v_count := v_count + 1;
    perform public.qa_log_detection_finding(
      v_run_id,
      'medium',
      'hr_emploc_plantilla_status_mismatch',
      'workflow',
      'hr_emploc',
      r.id,
      'HR Emploc status mismatch after Plantilla move',
      'A Plantilla record exists but HR Emploc status is not Moved to Plantilla.',
      'Review transition logic that moves HR Emploc records into Plantilla.',
      jsonb_build_object('hr_emploc_id', r.id, 'plantilla_id', r.plantilla_id, 'vcode', r.vcode, 'hr_status', r.hr_status, 'plantilla_status', r.plantilla_status)
    );
  end loop;

  return jsonb_build_object('run_id', v_run_id, 'findings_created', v_count);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_log_detection_finding(p_run_id uuid, p_severity text, p_finding_type text, p_module_name text, p_reference_table text, p_reference_record_id uuid, p_title text, p_details text DEFAULT NULL::text, p_recommendation text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_finding_id uuid;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can log QA findings';
  end if;

  if p_severity not in ('low','medium','high','critical') then
    raise exception 'Invalid QA severity: %', p_severity;
  end if;

  insert into public.qa_agent_findings (
    run_id,
    severity,
    finding_type,
    module_name,
    reference_table,
    reference_record_id,
    title,
    details,
    recommendation,
    status,
    metadata
  ) values (
    p_run_id,
    p_severity,
    p_finding_type,
    p_module_name,
    p_reference_table,
    p_reference_record_id,
    p_title,
    p_details,
    p_recommendation,
    'open',
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_finding_id;

  return v_finding_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_run_core_detection_suite()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run_id uuid;
  v_result jsonb := '{}'::jsonb;
  v_counts jsonb;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can run QA detection suite';
  end if;

  v_run_id := public.qa_start_detection_run(
    'QA_DETECTION_ENGINE',
    'core_workflow',
    '{"suite":"core_detection","phase":"qa_detection_rpc_layer"}'::jsonb
  );

  v_result := v_result || jsonb_build_object('duplicate_active_employee_numbers', public.qa_detect_duplicate_active_employee_numbers(v_run_id));
  v_result := v_result || jsonb_build_object('duplicate_active_vcodes', public.qa_detect_duplicate_active_vcodes(v_run_id));
  v_result := v_result || jsonb_build_object('orphan_hr_emploc', public.qa_detect_orphan_hr_emploc(v_run_id));
  v_result := v_result || jsonb_build_object('orphan_plantilla', public.qa_detect_orphan_plantilla(v_run_id));
  v_result := v_result || jsonb_build_object('workflow_status_mismatch', public.qa_detect_workflow_status_mismatch(v_run_id));

  v_counts := public.qa_complete_detection_run(v_run_id, 'Core QA detection suite completed.');

  return jsonb_build_object(
    'run_id', v_run_id,
    'checks', v_result,
    'finding_counts', v_counts
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.qa_start_detection_run(p_agent_name text DEFAULT 'QA_DETECTION_ENGINE'::text, p_target_module text DEFAULT 'system'::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run_id uuid;
  v_profile_id uuid;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can start QA detection runs';
  end if;

  v_profile_id := get_current_profile_id();

  insert into public.qa_agent_runs (
    agent_name,
    execution_type,
    status,
    target_module,
    initiated_by,
    started_at,
    metadata
  ) values (
    coalesce(nullif(p_agent_name, ''), 'QA_DETECTION_ENGINE'),
    'manual',
    'running',
    coalesce(nullif(p_target_module, ''), 'system'),
    v_profile_id,
    now(),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_run_id;

  return v_run_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.reassign_store(p_plantilla_id uuid, p_new_store_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old plantilla%ROWTYPE;
  v_new_store stores%ROWTYPE;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'reassign') THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_old FROM public.plantilla WHERE id = p_plantilla_id;
  IF v_old.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','plantilla_not_found');
  END IF;
  IF v_old.status <> 'Active' THEN
    RETURN jsonb_build_object('ok',false,'error','only_active_can_be_reassigned');
  END IF;

  SELECT * INTO v_new_store FROM public.stores WHERE id = p_new_store_id;
  IF v_new_store.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','target_store_not_found');
  END IF;

  UPDATE public.plantilla
  SET store_id   = p_new_store_id,
      store_name = v_new_store.store_name,
      remarks    = COALESCE('[Reassigned] '||p_reason, remarks),
      updated_at = NOW(),
      updated_by = public.get_current_profile_id()
  WHERE id = p_plantilla_id;

  PERFORM public._log_employee_action(
    p_plantilla_id, 'REASSIGN_STORE',
    format('Reassigned to %s', v_new_store.store_name),
    to_jsonb(v_old), jsonb_build_object('store_id',p_new_store_id,'store_name',v_new_store.store_name,'reason',p_reason)
  );

  RETURN jsonb_build_object('ok',true,'plantilla_id',p_plantilla_id,'new_store',v_new_store.store_name);
END$function$
;

CREATE OR REPLACE FUNCTION public.record_login_session(p_device_info text DEFAULT NULL::text, p_ip_address text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_profile_id UUID;
  v_session_id UUID;
BEGIN
  SELECT id INTO v_profile_id
  FROM users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true
  LIMIT 1;

  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_ERROR: No active profile for this user.';
  END IF;

  INSERT INTO login_sessions (user_id, auth_uid, device_info, ip_address)
  VALUES (v_profile_id, auth.uid(), p_device_info, p_ip_address::INET)
  RETURNING id INTO v_session_id;

  RETURN v_session_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_users_profile_role_after_roles_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.users_profile
  set role = new.role_name
  where role_id = new.id;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.reject_account_request(p_request_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_request      public.account_requests%ROWTYPE;
  v_caller_level INT;
BEGIN
  SELECT r.role_level INTO v_caller_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request
  FROM public.account_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request not found: %', p_request_id USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'pending'::account_request_status THEN
    RAISE EXCEPTION 'request already processed (status=%)', v_request.status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.account_requests
  SET status      = 'rejected'::account_request_status,
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      notes       = COALESCE(p_notes, notes),
      updated_at  = NOW()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success',    TRUE,
    'request_id', p_request_id,
    'status',     'rejected'
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reject_correction_request(p_correction_request_id uuid, p_hr_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row   public.hr_emploc%rowtype;
  v_actor public.users_profile%rowtype;
  v_actor_role text;
BEGIN
  SELECT * INTO v_actor
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true
  LIMIT 1;

  v_actor_role := coalesce(v_actor.role, '');

  IF v_actor.id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: active user profile not found';
  END IF;

  IF v_actor_role NOT IN ('Super Admin', 'HR Personnel') THEN
    RAISE EXCEPTION 'Unauthorized: only Super Admin or HR Personnel can reject correction review';
  END IF;

  SELECT * INTO v_row
  FROM public.hr_emploc
  WHERE id = p_correction_request_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'HR Emploc correction request not found';
  END IF;

  IF coalesce(v_row.hr_status, '') <> 'For Review' THEN
    RAISE EXCEPTION 'Only For Review correction requests can be rejected back to For Correction. Current status: %',
      coalesce(v_row.hr_status, 'NULL');
  END IF;

  UPDATE public.hr_emploc
  SET
    hr_status              = 'For Correction',
    status                 = CASE
                               WHEN status = 'Ready for Plantilla' AND emploc_no IS NULL
                               THEN 'Pending Requirements'
                               ELSE status
                             END,
    hr_remarks             = nullif(trim(coalesce(p_hr_remarks, '')), ''),
    hr_rejection_reason    = nullif(trim(coalesce(p_hr_remarks, '')), ''),
    hr_reviewed_by         = coalesce(v_actor.full_name, v_actor.email, auth.uid()::text),
    hr_reviewed_by_user_id = v_actor.id,
    hr_reviewed_at         = now(),
    updated_by             = v_actor.id,
    updated_at             = now()
  WHERE id = p_correction_request_id
  RETURNING * INTO v_row;

  INSERT INTO public.activity_log (
    actor_id, actor_name, actor_role, action,
    target_table, target_id, target_name,
    old_value, new_value, created_at
  ) VALUES (
    v_actor.id,
    coalesce(v_actor.full_name, v_actor.email),
    v_actor_role,
    'HR Emploc correction rejected to For Correction',
    'hr_emploc',
    v_row.id,
    v_row.applicant_name,
    jsonb_build_object('hr_status', 'For Review'),
    jsonb_build_object('hr_status', v_row.hr_status, 'hr_remarks', v_row.hr_remarks),
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'id', v_row.id,
    'hr_status', v_row.hr_status,
    'status', v_row.status,
    'message', 'Correction request returned to For Correction.'
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reject_headcount_request(p_request_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_req headcount_requests%ROWTYPE;
begin
  if not public.i_have_full_access() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select * into v_req from public.headcount_requests where id = p_request_id for update;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_req.status not in ('pending', 'under_review') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status_transition', 'current', v_req.status);
  end if;

  update public.headcount_requests
  set status              = 'rejected',
      reviewed_by_user_id = public.get_current_profile_id(),
      reviewed_by_name    = public.get_my_full_name(),
      reviewed_at         = now(),
      reviewer_remarks    = p_remarks
  where id = p_request_id;

  return jsonb_build_object(
    'ok',         true,
    'request_id', p_request_id,
    'status',     'rejected'
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.reject_plantilla_request(p_approval_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_level     INT;
  v_reviewer  TEXT;
  v_appr_rec  RECORD;
BEGIN
  -- ── Auth ────────────────────────────────────────────────────────────────
  SELECT r.role_level, up.full_name
    INTO v_level, v_reviewer
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_level, 0) < 30 THEN
    RAISE EXCEPTION 'unauthorized: requires Data Team or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch & lock approval record ─────────────────────────────────────────
  SELECT id, applicant_name, vcode, status
    INTO v_appr_rec
    FROM public.plantilla_approvals
   WHERE id = p_approval_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval record not found: %', p_approval_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_appr_rec.status <> 'Pending' THEN
    RAISE EXCEPTION 'approval already processed (status=%)', v_appr_rec.status
      USING ERRCODE = '22023';
  END IF;

  -- ── Update approval to Rejected ──────────────────────────────────────────
  UPDATE public.plantilla_approvals
     SET status      = 'Rejected',
         reviewed_by = v_reviewer,
         reviewed_at = NOW(),
         remarks     = p_remarks
   WHERE id = p_approval_id;

  -- ── Revert hr_emploc back to Ready for Plantilla ─────────────────────────
  -- Try UUID lookup first (new records), fall back to name+vcode
  UPDATE public.hr_emploc
     SET status = 'Ready for Plantilla'
   WHERE id = (
     SELECT CASE
       WHEN (SELECT hr_emploc_id FROM public.plantilla_approvals WHERE id = p_approval_id)
            ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       THEN (SELECT hr_emploc_id::UUID FROM public.plantilla_approvals WHERE id = p_approval_id)
       ELSE (
         SELECT h.id FROM public.hr_emploc h
          WHERE h.applicant_name = v_appr_rec.applicant_name
            AND h.vcode = v_appr_rec.vcode
          LIMIT 1
       )
     END
   );

  -- ── Audit ────────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'Plantilla',
    'REJECT_PLANTILLA',
    p_approval_id,
    jsonb_build_object('status', 'Pending'),
    jsonb_build_object(
      'status', 'Rejected',
      'reviewed_by', v_reviewer,
      'remarks', p_remarks,
      'hr_emploc_reverted_to', 'Ready for Plantilla'
    )
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reject_pool_conversion(p_request_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request public.workforce_pool_conversion_requests%rowtype;
  v_actor uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
BEGIN
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team approval required'
      USING ERRCODE = '42501';
  END IF;

  IF NULLIF(BTRIM(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'rejection reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_request
  FROM public.workforce_pool_conversion_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  IF v_request.status <> 'Pending' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'invalid_status',
      'current', v_request.status
    );
  END IF;

  UPDATE public.workforce_pool_conversion_requests
  SET status = 'Rejected',
      rejected_by = v_actor,
      rejected_by_name = v_actor_name,
      rejected_at = now(),
      rejection_reason = BTRIM(p_reason),
      updated_at = now()
  WHERE id = v_request.id;

  PERFORM public.log_audit_event(
    'workforce_pool_conversion',
    'UPDATE',
    v_request.id,
    to_jsonb(v_request),
    to_jsonb((SELECT r FROM public.workforce_pool_conversion_requests r WHERE r.id = v_request.id))
  );

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', v_request.id,
    'status', 'Rejected'
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reject_reliever_coverage_request(p_request_id uuid, p_rejection_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_req RECORD;
BEGIN
  IF NOT (
    get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;

  SELECT * INTO v_req
  FROM workforce_assignment_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'Only Pending requests can be rejected. Current status: %', v_req.status;
  END IF;

  IF p_rejection_reason IS NULL OR trim(p_rejection_reason) = '' THEN
    RAISE EXCEPTION 'rejection_reason is required.';
  END IF;

  UPDATE workforce_assignment_requests
  SET
    status           = 'Rejected',
    rejection_reason = p_rejection_reason,
    reviewed_by      = get_my_full_name(),
    reviewed_at      = now(),
    updated_at       = now()
  WHERE id = p_request_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reject_store_import_batch(p_batch_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_batch public.store_import_batches%ROWTYPE;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: super admin only';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required';
  END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status;
  END IF;

  UPDATE public.store_import_batches
     SET status='rejected', rejected_by=v_uid, rejected_at=now(),
         rejection_reason=p_reason, updated_at=now()
   WHERE id=p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'store_import_batches', 'APPROVAL', p_batch_id,
          jsonb_build_object('decision','rejected','reason',p_reason));

  RETURN jsonb_build_object('batch_id',p_batch_id,'status','rejected');
END$function$
;

CREATE OR REPLACE FUNCTION public.release_qa_run_lock(p_queue_id uuid, p_queue_status text DEFAULT 'completed'::text, p_error_message text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_run_id uuid;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can release QA run locks';
  end if;

  if p_queue_status not in ('completed','failed','blocked','cancelled','expired') then
    raise exception 'Invalid queue release status: %', p_queue_status;
  end if;

  update public.qa_run_queue
  set queue_status = p_queue_status,
      error_message = p_error_message,
      completed_at = case when p_queue_status in ('completed','failed','cancelled','expired') then now() else completed_at end,
      locked_at = null,
      lock_expires_at = null
  where id = p_queue_id
  returning run_id into v_run_id;

  if v_run_id is not null and p_queue_status in ('completed','failed') then
    perform public.qa_complete_detection_run(v_run_id, 'Scheduled QA queue item released as ' || p_queue_status || '.');
  end if;

  return p_queue_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.reopen_correction_request(p_correction_request_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.hr_emploc
  SET
    hr_status = 'For Correction',
    updated_at = now()
  WHERE id = p_correction_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Correction request not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reopen_or_create_vacancy_for_plantilla(p_plantilla_id uuid, p_effective_date date, p_vacancy_type text DEFAULT 'Backfill'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plantilla public.plantilla;
  v_vacancy_id uuid;
BEGIN
  SELECT *
    INTO v_plantilla
  FROM public.plantilla
  WHERE id = p_plantilla_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found: %', p_plantilla_id;
  END IF;

  -- VCODE is the manpower slot identity.
  -- Reopen/reactivate existing slot first.
  SELECT id
    INTO v_vacancy_id
  FROM public.vacancies
  WHERE vcode = v_plantilla.vcode
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_vacancy_id IS NOT NULL THEN

    UPDATE public.vacancies
    SET
      status = 'Open',
      vacancy_type = COALESCE(p_vacancy_type, vacancy_type, 'Backfill'),
      vacant_date = p_effective_date,
      source_plantilla_id = v_plantilla.id,
      account = v_plantilla.account,
      account_id = v_plantilla.account_id,
      chain_id = v_plantilla.chain_id,
      store_id = v_plantilla.store_id,
      province_id = v_plantilla.province_id,
      position = v_plantilla.position,
      position_id = v_plantilla.position_id,
      area_name = COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      store_name = v_plantilla.store_name,
      is_archived = FALSE,
      archived_at = NULL,
      deleted_at = NULL,
      has_pending_closure = FALSE,
      updated_at = NOW(),
      updated_by = auth.uid()
    WHERE id = v_vacancy_id;

    RETURN v_vacancy_id;
  END IF;

  INSERT INTO public.vacancies (
    vcode,
    account,
    position,
    account_id,
    chain_id,
    store_id,
    province_id,
    area_name,
    position_id,
    vacant_date,
    vacancy_type,
    status,
    source_plantilla_id,
    store_name,
    created_at,
    updated_at,
    created_by,
    updated_by,
    required_headcount
  )
  VALUES (
    v_plantilla.vcode,
    v_plantilla.account,
    v_plantilla.position,
    v_plantilla.account_id,
    v_plantilla.chain_id,
    v_plantilla.store_id,
    v_plantilla.province_id,
    COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
    v_plantilla.position_id,
    p_effective_date,
    COALESCE(p_vacancy_type, 'Backfill'),
    'Open',
    v_plantilla.id,
    v_plantilla.store_name,
    NOW(),
    NOW(),
    auth.uid(),
    auth.uid(),
    1
  )
  RETURNING id INTO v_vacancy_id;

  RETURN v_vacancy_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.request_employee_deactivation(p_plantilla_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old plantilla%ROWTYPE;
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'request_deact') THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_old FROM public.plantilla WHERE id = p_plantilla_id FOR UPDATE;
  IF v_old.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','plantilla_not_found');
  END IF;
  IF v_old.status <> 'Inactive' THEN
    RETURN jsonb_build_object('ok',false,'error','must_be_inactive_first','current_status',v_old.status);
  END IF;

  UPDATE public.plantilla
  SET status              = 'For Deactivation',
      for_deactivation_at = NOW(),
      for_deactivation_by = public.get_current_profile_id(),
      remarks             = COALESCE(p_remarks, remarks),
      updated_at          = NOW(),
      updated_by          = public.get_current_profile_id()
  WHERE id = p_plantilla_id;

  PERFORM public._log_employee_action(
    p_plantilla_id, 'REQUEST_DEACTIVATION',
    format('Deactivation requested for %s', v_old.employee_name),
    to_jsonb(v_old),
    jsonb_build_object('status','For Deactivation','remarks',p_remarks)
  );

  RETURN jsonb_build_object('ok',true,'plantilla_id',p_plantilla_id,'new_status','For Deactivation');
END$function$
;

CREATE OR REPLACE FUNCTION public.request_plantilla_approval(p_hr_emploc_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id  UUID;
  v_level       INT;
  v_requester   TEXT;
  v_hr_rec      RECORD;
  v_approval_id UUID;
BEGIN
  -- ── Auth ────────────────────────────────────────────────────────────────
  SELECT up.id, r.role_level, up.full_name
    INTO v_profile_id, v_level, v_requester
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = auth.uid();

  IF v_profile_id IS NULL OR COALESCE(v_level, 0) < 10 THEN
    RAISE EXCEPTION 'unauthorized: authenticated staff required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch & lock hr_emploc ───────────────────────────────────────────────
  SELECT id, applicant_name, applicant_name_snapshot, vcode, account, position,
         emploc_no, employee_no, status, hr_status
    INTO v_hr_rec
    FROM public.hr_emploc
   WHERE id = p_hr_emploc_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'hr_emploc record not found: %', p_hr_emploc_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Status guard ─────────────────────────────────────────────────────────
  -- Only allow requests for records that are ready or already pending
  -- (idempotent guard for retries)
  IF v_hr_rec.status NOT IN ('Ready for Plantilla', 'Pending Approval', 'Complete') THEN
    RAISE EXCEPTION 'hr_emploc must be Ready for Plantilla to request approval (current: %)',
      v_hr_rec.status
      USING ERRCODE = '22023';
  END IF;

  -- ── Duplicate guard ──────────────────────────────────────────────────────
  IF EXISTS (
    SELECT 1
      FROM public.plantilla_approvals
     WHERE hr_emploc_id = p_hr_emploc_id::TEXT
       AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'a pending approval already exists for this hr_emploc record'
      USING ERRCODE = '23505';
  END IF;

  -- ── Insert approval request ──────────────────────────────────────────────
  -- hr_emploc_id now stores the actual UUID (fixing the name_vcode FK bug)
  INSERT INTO public.plantilla_approvals (
    hr_emploc_id,
    applicant_name,
    vcode,
    account,
    position,
    emploc_no,
    requested_by,
    status
  ) VALUES (
    p_hr_emploc_id::TEXT,                          -- actual UUID, not name_vcode
    COALESCE(v_hr_rec.applicant_name_snapshot, v_hr_rec.applicant_name),
    v_hr_rec.vcode,
    v_hr_rec.account,
    v_hr_rec.position,
    COALESCE(NULLIF(v_hr_rec.emploc_no, ''), v_hr_rec.employee_no, ''),
    v_requester,
    'Pending'
  )
  RETURNING id INTO v_approval_id;

  -- ── Update hr_emploc status ──────────────────────────────────────────────
  UPDATE public.hr_emploc
     SET status = 'Pending Approval'
   WHERE id = p_hr_emploc_id;

  -- ── Audit ────────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'HR Emploc',
    'REQUEST_PLANTILLA_APPROVAL',
    p_hr_emploc_id,
    jsonb_build_object('status', v_hr_rec.status),
    jsonb_build_object(
      'status', 'Pending Approval',
      'approval_id', v_approval_id,
      'requested_by', v_requester
    )
  );

  RETURN jsonb_build_object(
    'approval_id', v_approval_id,
    'hr_emploc_id', p_hr_emploc_id,
    'status', 'Pending'
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.request_pool_conversion(p_employee_id uuid, p_target_account_id uuid, p_target_store_id uuid, p_position text, p_effective_date date, p_reason text, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(request_id uuid, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_employee public.plantilla%rowtype;
  v_slot public.workforce_pool_slots%rowtype;
  v_account public.accounts%rowtype;
  v_store public.stores%rowtype;
  v_request_id uuid;
  v_actor uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
  v_role text := public.get_my_role();
BEGIN
  IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'forbidden: Ops can request conversion; Data Team approves'
      USING ERRCODE = '42501';
  END IF;

  IF public.get_my_role_level() = 20 THEN
    RAISE EXCEPTION 'forbidden: Recruitment cannot request pool conversion'
      USING ERRCODE = '42501';
  END IF;

  IF p_employee_id IS NULL
     OR p_target_account_id IS NULL
     OR p_target_store_id IS NULL
     OR NULLIF(BTRIM(p_position), '') IS NULL
     OR p_effective_date IS NULL
     OR NULLIF(BTRIM(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'employee, target account, target store, position, effective date, and reason are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_employee
  FROM public.plantilla
  WHERE id = p_employee_id
  FOR UPDATE;

  IF v_employee.id IS NULL OR COALESCE(v_employee.is_deleted, false) THEN
    RAISE EXCEPTION 'pool employee not found' USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_employee.is_pool_employee, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'employee is not a Moses HQ Workforce Pool employee'
      USING ERRCODE = '22023';
  END IF;

  IF v_employee.status <> 'Active' THEN
    RAISE EXCEPTION 'only active pool employees can be converted'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_account
  FROM public.accounts
  WHERE id = p_target_account_id;

  IF v_account.id IS NULL OR COALESCE(v_account.is_pool_account, false) THEN
    RAISE EXCEPTION 'target account must be a regular store account'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_store
  FROM public.stores
  WHERE id = p_target_store_id
    AND account_id = p_target_account_id;

  IF v_store.id IS NULL THEN
    RAISE EXCEPTION 'target store does not belong to target account'
      USING ERRCODE = '22023';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT EXISTS (
       SELECT 1
       FROM public.get_my_scoped_accounts() scoped
       WHERE scoped.account_id = p_target_account_id
     ) THEN
    RAISE EXCEPTION 'forbidden: target account is outside your scope'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_slot
  FROM public.workforce_pool_slots
  WHERE vcode = v_employee.vcode
    AND deleted_at IS NULL
  LIMIT 1;

  IF EXISTS (
    SELECT 1
    FROM public.workforce_pool_conversion_requests
    WHERE employee_id = p_employee_id
      AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'pending conversion request already exists for this employee'
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.workforce_pool_conversion_requests (
    employee_id,
    pool_type_id,
    pool_slot_id,
    vcode,
    target_account_id,
    target_account,
    target_store_id,
    target_store,
    target_position,
    effective_date,
    reason,
    notes,
    requested_by,
    requested_by_name,
    requested_by_role,
    previous_account_id,
    previous_account,
    previous_store_id,
    previous_store,
    previous_position,
    previous_vcode,
    snapshot
  )
  VALUES (
    v_employee.id,
    v_employee.pool_type_id,
    v_slot.id,
    v_employee.vcode,
    v_account.id,
    v_account.account_name,
    v_store.id,
    v_store.store_name,
    BTRIM(p_position),
    p_effective_date,
    BTRIM(p_reason),
    NULLIF(BTRIM(COALESCE(p_notes, '')), ''),
    v_actor,
    v_actor_name,
    v_role,
    v_employee.account_id,
    v_employee.account,
    v_employee.store_id,
    v_employee.store_name,
    v_employee.position,
    v_employee.vcode,
    jsonb_build_object(
      'employee', to_jsonb(v_employee),
      'active_deployments', (
        SELECT COALESCE(jsonb_agg(to_jsonb(wa)), '[]'::jsonb)
        FROM public.workforce_assignments wa
        WHERE wa.employee_id = v_employee.id
          AND lower(COALESCE(wa.status, '')) IN ('active', 'approved', 'deployed')
      )
    )
  )
  RETURNING id INTO v_request_id;

  PERFORM public.log_audit_event(
    'workforce_pool_conversion',
    'INSERT',
    v_request_id,
    NULL,
    to_jsonb((SELECT r FROM public.workforce_pool_conversion_requests r WHERE r.id = v_request_id))
  );

  RETURN QUERY SELECT
    v_request_id,
    'Pending'::text,
    'Conversion request submitted. Waiting for Data Team approval.'::text;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.request_reliever_coverage(p_employee_id uuid, p_pool_type_id uuid, p_requested_group_id uuid DEFAULT NULL::uuid, p_requested_account_id uuid DEFAULT NULL::uuid, p_requested_store_id uuid DEFAULT NULL::uuid, p_requested_position text DEFAULT NULL::text, p_priority text DEFAULT 'normal'::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date, p_reason text DEFAULT NULL::text)
 RETURNS TABLE(request_id uuid, employee_id uuid, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_name  TEXT;
  v_caller_id    UUID;
  v_new_id       UUID;
BEGIN
  -- Role check: Ops (40–70) or Data Team
  IF NOT (
    (get_my_role_level() BETWEEN 40 AND 70)
    OR get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'Access denied: Ops role or above required.';
  END IF;

  -- Dates required
  IF p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'start_date and end_date are required.';
  END IF;
  IF p_start_date > p_end_date THEN
    RAISE EXCEPTION 'start_date must be <= end_date.';
  END IF;

  -- Employee must be active
  IF NOT EXISTS (
    SELECT 1 FROM plantilla
    WHERE id = p_employee_id
      AND is_deleted = false
      AND deactivated_at IS NULL
      AND status = 'Active'
  ) THEN
    RAISE EXCEPTION 'Employee not found or inactive.';
  END IF;

  -- Employee must be in pool AND visible to caller
  -- Global (no group tag) = visible to all. Tagged = only caller's accounts in that group.
  IF NOT EXISTS (
    SELECT 1
    FROM workforce_pool_slots wps
    JOIN plantilla pt ON pt.vcode = wps.vcode
    WHERE pt.id = p_employee_id
      AND wps.is_active = true
      AND wps.deleted_at IS NULL
      AND (
        wps.group_id IS NULL
        OR EXISTS (
          SELECT 1 FROM accounts a
          WHERE a.group_id = wps.group_id
            AND a.id::text = ANY(get_my_allowed_accounts())
        )
      )
  ) THEN
    RAISE EXCEPTION 'Pool employee not visible to your scope or not enrolled in pool.';
  END IF;

  -- Reservation lock check
  IF EXISTS (
    SELECT 1 FROM workforce_assignment_requests
    WHERE employee_id = p_employee_id
      AND status = 'Pending'
  ) THEN
    RETURN QUERY
    SELECT
      NULL::UUID,
      p_employee_id,
      'Unavailable'::TEXT,
      'Pending deployment request exists for this reliever. Available again after approval or withdrawal.'::TEXT;
    RETURN;
  END IF;

  v_caller_name := get_my_full_name();
  v_caller_id   := auth.uid();

  INSERT INTO workforce_assignment_requests (
    employee_id, pool_type_id,
    requested_group_id, requested_account_id, requested_store_id,
    requested_position, priority,
    start_date, end_date, reason,
    status, requested_by, requested_by_id,
    created_at, updated_at
  ) VALUES (
    p_employee_id, p_pool_type_id,
    p_requested_group_id, p_requested_account_id, p_requested_store_id,
    p_requested_position, p_priority,
    p_start_date, p_end_date, p_reason,
    'Pending', v_caller_name, v_caller_id,
    now(), now()
  )
  RETURNING id INTO v_new_id;

  RETURN QUERY
  SELECT
    v_new_id,
    p_employee_id,
    'Pending'::TEXT,
    'Reliever coverage request submitted successfully.'::TEXT;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.resign_employee(p_plantilla_id uuid, p_separation_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public._apply_separation(p_plantilla_id, 'Resigned', p_separation_date, p_remarks, 'resign');
$function$
;

CREATE OR REPLACE FUNCTION public.resign_plantilla_employee(p_employee_no text, p_resignation_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text, p_separation_status text DEFAULT 'Resigned'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Validate separation status
  IF p_separation_status NOT IN ('Resigned', 'AWOL', 'Endo', 'Others') THEN
    RAISE EXCEPTION 'Invalid separation_status: %. Must be Resigned|AWOL|Endo|Others.',
      p_separation_status;
  END IF;

  -- Reopen linked vacancies (preserve existing logic)
  UPDATE vacancies
  SET
    status              = 'Open',
    has_pending_closure = FALSE,
    updated_at          = NOW()
  WHERE vcode IN (
    SELECT vcode FROM plantilla
    WHERE emploc_no = p_employee_no AND status = 'Active'
  )
  AND status NOT IN ('Closed', 'Archived');

  -- Resign plantilla record + set separation fields
  UPDATE plantilla
  SET
    status              = 'Resigned',
    resignation_date    = p_resignation_date,
    date_of_separation  = p_resignation_date,
    separation_status   = p_separation_status,
    remarks             = p_remarks,
    updated_at          = NOW()
  WHERE emploc_no = p_employee_no
    AND status = 'Active';

  -- Downstream triggers fire automatically:
  --   trg_plantilla_separation_to_vacancy  → creates backfill vacancy
  --   trg_sla_breach                       → logs SLA if untagged after 3 days
  --   trg_notify_separation                → notifies HRCO
  --   trg_audit_plantilla                  → audit log entry
END;
$function$
;

CREATE OR REPLACE FUNCTION public.resign_roving_employee(p_plantilla_id uuid, p_separation_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor       uuid    := public.get_my_profile_id();
  v_actor_name  text    := public.get_my_full_name();
  v_pl          public.plantilla%ROWTYPE;
  v_emp         public.hr_emploc%ROWTYPE;
  v_store_count int     := 0;
  v_vac_count   int     := 0;
BEGIN
  -- ── Auth ─────────────────────────────────────────────────────────────────
  IF NOT (public.i_have_full_access() OR public.get_my_role() = 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch and lock plantilla master ─────────────────────────────────────
  SELECT * INTO v_pl
    FROM public.plantilla
   WHERE id = p_plantilla_id
     AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla % not found or already deleted', p_plantilla_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Roving guard ─────────────────────────────────────────────────────────
  IF COALESCE(v_pl.deployment_type, '') <> 'Roving'
     OR v_pl.roving_assignment_id IS NULL THEN
    RAISE EXCEPTION 'plantilla % is not a roving record. Use resign_employee instead.', p_plantilla_id
      USING ERRCODE = '22023';
  END IF;

  -- ── Status guard ─────────────────────────────────────────────────────────
  IF v_pl.status <> 'Active' THEN
    RAISE EXCEPTION 'cannot resign: plantilla status is %, expected Active', v_pl.status
      USING ERRCODE = '22023';
  END IF;

  -- ── 1. Reopen all linked vacancies (via plantilla_store_links) ───────────
  UPDATE public.vacancies v
     SET status              = 'Open',
         vacancy_type        = 'Backfill',
         has_pending_closure = false,
         source_plantilla_id = v_pl.id,
         is_archived         = false,
         archived_at         = NULL,
         deleted_at          = NULL,
         updated_at          = NOW(),
         updated_by          = v_actor
    FROM public.plantilla_store_links psl
   WHERE psl.plantilla_id = p_plantilla_id
     AND psl.deleted_at IS NULL
     AND psl.status = 'Active'
     AND v.vcode = psl.vcode
     AND v.status NOT IN ('Closed');

  GET DIAGNOSTICS v_vac_count = ROW_COUNT;

  -- ── 2. Mark all plantilla_store_links → Resigned ─────────────────────────
  UPDATE public.plantilla_store_links
     SET status       = 'Resigned',
         unlinked_at  = NOW(),
         unlinked_by  = v_actor,
         updated_at   = NOW(),
         updated_by   = v_actor
   WHERE plantilla_id = p_plantilla_id
     AND deleted_at IS NULL
     AND status = 'Active';

  GET DIAGNOSTICS v_store_count = ROW_COUNT;

  -- ── 3. Mark plantilla master → Inactive ──────────────────────────────────
  -- Trigger fn_plantilla_separation_to_vacancy is guarded for Roving — safe
  UPDATE public.plantilla
     SET status             = 'Inactive',
         inactive_at        = NOW(),
         inactive_by        = v_actor,
         date_of_separation = p_separation_date,
         resignation_date   = p_separation_date,
         separation_status  = 'Resigned',
         remarks            = COALESCE(p_remarks, remarks),
         updated_at         = NOW(),
         updated_by         = v_actor
   WHERE id = p_plantilla_id;

  -- ── 4. Fetch hr_emploc master via roving_assignment_id ───────────────────
  SELECT * INTO v_emp
    FROM public.hr_emploc
   WHERE roving_assignment_id = v_pl.roving_assignment_id
     AND assignment_type = 'Roving'
     AND deleted_at IS NULL
   ORDER BY created_at ASC
   LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    -- ── 5. Mark all hr_emploc_store_links → Resigned ─────────────────────
    UPDATE public.hr_emploc_store_links
       SET status       = 'Resigned',
           resigned_at  = NOW(),
           resigned_by  = v_actor,
           updated_at   = NOW(),
           updated_by   = v_actor
     WHERE hr_emploc_id = v_emp.id
       AND deleted_at IS NULL
       AND status IN ('Confirmed', 'Pending');

    -- ── 6. Soft-delete hr_emploc master ──────────────────────────────────
    UPDATE public.hr_emploc
       SET deleted_at  = NOW(),
           updated_at  = NOW(),
           updated_by  = v_actor
     WHERE id = v_emp.id;
  END IF;

  -- ── 7. Audit ──────────────────────────────────────────────────────────────
  PERFORM public.log_audit_event(
    'plantilla', 'RESIGN_ROVING',
    p_plantilla_id,
    to_jsonb(v_pl),
    jsonb_build_object(
      'separation_date',       p_separation_date,
      'separation_status',     'Resigned',
      'stores_resigned',       v_store_count,
      'vacancies_reopened',    v_vac_count,
      'hr_emploc_id',          v_emp.id,
      'roving_assignment_id',  v_pl.roving_assignment_id,
      'actor',                 v_actor_name
    )
  );

  INSERT INTO public.employee_activity_log (
    emploc_no, vcode, activity_type, description, performed_by, metadata
  ) VALUES (
    v_pl.employee_no,
    NULL,
    'resigned',
    'Roving employee resigned — ' || v_store_count::text || ' store(s) unlinked, '
      || v_vac_count::text || ' vacancy(ies) reopened',
    v_actor_name,
    jsonb_build_object(
      'plantilla_id',          p_plantilla_id,
      'roving_assignment_id',  v_pl.roving_assignment_id,
      'stores_resigned',       v_store_count,
      'vacancies_reopened',    v_vac_count,
      'separation_date',       p_separation_date
    )
  );

  RETURN jsonb_build_object(
    'ok',                    true,
    'plantilla_id',          p_plantilla_id,
    'new_status',            'Inactive',
    'separation_status',     'Resigned',
    'roving_assignment_id',  v_pl.roving_assignment_id,
    'stores_resigned',       v_store_count,
    'vacancies_reopened',    v_vac_count,
    'hr_emploc_archived',    v_emp.id IS NOT NULL
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.retry_qa_run_if_allowed(p_queue_id uuid, p_failure_type text, p_error_message text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_queue public.qa_run_queue%rowtype;
  v_allowed boolean := false;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can retry QA runs';
  end if;

  select * into v_queue
  from public.qa_run_queue
  where id = p_queue_id
  for update;

  if v_queue.id is null then
    raise exception 'QA queue item not found';
  end if;

  v_allowed := p_failure_type in ('network','infrastructure')
    or (p_failure_type = 'timeout' and v_queue.retry_count < 1);

  if p_failure_type in ('rls_security','assertion') then
    v_allowed := false;
  end if;

  if v_allowed and v_queue.retry_count < v_queue.max_retries then
    update public.qa_run_queue
    set queue_status = 'queued',
        retry_count = retry_count + 1,
        failure_type = p_failure_type,
        error_message = p_error_message,
        locked_at = null,
        lock_expires_at = null,
        completed_at = null
    where id = p_queue_id;

    return jsonb_build_object('retry_allowed', true, 'queue_id', p_queue_id, 'retry_count', v_queue.retry_count + 1);
  end if;

  update public.qa_run_queue
  set queue_status = 'failed',
      failure_type = p_failure_type,
      error_message = p_error_message,
      completed_at = now(),
      locked_at = null,
      lock_expires_at = null
  where id = p_queue_id;

  return jsonb_build_object('retry_allowed', false, 'queue_id', p_queue_id, 'failure_type', p_failure_type);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_submit_vacancy_closure_request(p_vacancy_vcode text, p_reason text, p_details text DEFAULT NULL::text, p_requested_by text DEFAULT NULL::text, p_requested_by_role text DEFAULT 'Ops'::text, p_requested_by_user_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request_id uuid;
BEGIN
  IF nullif(trim(p_vacancy_vcode), '') IS NULL THEN
    RAISE EXCEPTION 'Vacancy vcode is required';
  END IF;

  IF nullif(trim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Closure reason is required';
  END IF;

  -- T0004: fulfillment guard (Layer 1)
  PERFORM public.fn_assert_vacancy_closeable(p_vacancy_vcode);

  IF EXISTS (
    SELECT 1 FROM public.vacancy_closure_requests
    WHERE vacancy_vcode = p_vacancy_vcode
      AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'Pending closure request already exists';
  END IF;

  INSERT INTO public.vacancy_closure_requests (
    vacancy_vcode,
    reason,
    details,
    requested_by,
    requested_by_user_id,
    status,
    encoder_decision
  )
  VALUES (
    p_vacancy_vcode,
    trim(p_reason),
    nullif(trim(p_details), ''),
    COALESCE(nullif(trim(p_requested_by), ''), nullif(trim(p_requested_by_role), ''), 'Ops'),
    p_requested_by_user_id,
    'Pending',
    'Pending'
  )
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.separate_employee(p_plantilla_id uuid, p_separation_date date DEFAULT CURRENT_DATE, p_separation_type text DEFAULT 'Separated'::text, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_separation_type NOT IN ('AWOL','Separated','Terminated','Others') THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_separation_type',
                              'allowed', ARRAY['AWOL','Separated','Terminated','Others']);
  END IF;
  RETURN public._apply_separation(p_plantilla_id, p_separation_type, p_separation_date, p_remarks, 'separate');
END$function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_user_active(p_profile_id uuid, p_is_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_level INT;
  v_target_name  TEXT;
  v_target_role  TEXT;
  v_old_state    BOOLEAN;
BEGIN
  -- ── Auth ────────────────────────────────────────────────────────────────
  SELECT r.role_level
    INTO v_caller_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch target ─────────────────────────────────────────────────────────
  SELECT up.full_name, r.role_name, up.is_active
    INTO v_target_name, v_target_role, v_old_state
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.id = p_profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user profile not found: %', p_profile_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Guard: cannot deactivate the last active Super Admin ────────────────
  IF NOT p_is_active AND v_target_role IN ('Super Admin', 'superAdmin', 'super_admin') THEN
    IF (
      SELECT COUNT(*) FROM public.users_profile up2
      JOIN public.roles r2 ON r2.id = up2.role_id
      WHERE r2.role_name IN ('Super Admin', 'superAdmin', 'super_admin')
        AND up2.is_active = TRUE
        AND up2.id <> p_profile_id
    ) = 0 THEN
      RAISE EXCEPTION 'cannot deactivate the last active Super Admin'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── Guard: Head Admin cannot deactivate Super Admin ──────────────────────
  IF NOT p_is_active
     AND v_target_role IN ('Super Admin', 'superAdmin', 'super_admin')
     AND COALESCE(v_caller_level, 0) < 100 THEN
    RAISE EXCEPTION 'only Super Admin can deactivate another Super Admin'
      USING ERRCODE = '42501';
  END IF;

  -- ── Apply ────────────────────────────────────────────────────────────────
  UPDATE public.users_profile
     SET is_active  = p_is_active,
         updated_at = NOW()
   WHERE id = p_profile_id;

  -- ── Audit ────────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'User Access',
    CASE WHEN p_is_active THEN 'ACTIVATE_USER' ELSE 'DEACTIVATE_USER' END,
    p_profile_id,
    jsonb_build_object('is_active', v_old_state, 'full_name', v_target_name),
    jsonb_build_object('is_active', p_is_active, 'full_name', v_target_name)
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.start_acting_session(p_acting_role text, p_group_ids uuid[] DEFAULT '{}'::uuid[], p_account_ids uuid[] DEFAULT '{}'::uuid[], p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_session_id uuid;
begin
    if not public.is_super_admin() then
        raise exception 'Only Super Admin can start acting sessions';
    end if;

    update public.acting_sessions
    set
        is_active = false,
        ended_at = now(),
        ended_by = auth.uid(),
        updated_at = now()
    where user_id = auth.uid()
      and is_active = true;

    insert into public.acting_sessions (
        user_id,
        acting_role,
        acting_group_ids,
        acting_account_ids,
        reason,
        created_by
    )
    values (
        auth.uid(),
        p_acting_role,
        coalesce(p_group_ids, '{}'),
        coalesce(p_account_ids, '{}'),
        p_reason,
        auth.uid()
    )
    returning id into v_session_id;

    perform public.log_audit_event(
        'Switch Role',
        'START_ACTING_SESSION',
        v_session_id,
        null,
        jsonb_build_object(
            'acting_role', p_acting_role,
            'group_count', coalesce(array_length(p_group_ids, 1), 0),
            'account_count', coalesce(array_length(p_account_ids, 1), 0),
            'reason', p_reason
        )
    );

    return v_session_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.stop_acting_session()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_session_id uuid;
begin
    update public.acting_sessions
    set
        is_active = false,
        ended_at = now(),
        ended_by = auth.uid(),
        updated_at = now()
    where user_id = auth.uid()
      and is_active = true
    returning id into v_session_id;

    if v_session_id is not null then
        perform public.log_audit_event(
            'Switch Role',
            'STOP_ACTING_SESSION',
            v_session_id,
            null,
            jsonb_build_object(
                'stopped_by', auth.uid()
            )
        );

        return true;
    end if;

    return false;
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

CREATE OR REPLACE FUNCTION public.submit_headcount_request(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role         text := public.get_my_role();
  v_account      accounts%ROWTYPE;
  v_store        stores%ROWTYPE;
  v_position     positions%ROWTYPE;
  v_group        groups%ROWTYPE;
  v_request_id   uuid;
  v_account_id   uuid;
  v_store_id     uuid;
  v_position_id  uuid;
  v_store_name   text;
begin
  if not (public.i_have_full_access() or public.i_am_ops()) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  begin
    v_account_id  := (p_input->>'account_id')::uuid;
    v_store_id    := nullif(trim(coalesce(p_input->>'store_id', '')), '')::uuid;
    v_position_id := (p_input->>'position_id')::uuid;
  exception
    when invalid_text_representation then
      return jsonb_build_object(
        'ok',    false,
        'error', 'invalid_reference',
        'field', 'uuid_cast',
        'detail', sqlerrm
      );
  end;

  v_store_name := nullif(trim(coalesce(
    p_input->>'store_name',
    p_input->>'store_name_snapshot',
    ''
  )), '');
  if v_store_name is null then
    return jsonb_build_object('ok', false, 'error', 'store_name_required', 'field', 'store_name');
  end if;

  select * into v_account from public.accounts where id = v_account_id;
  if v_account.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'account_id');
  end if;

  if v_store_id is not null then
    select * into v_store from public.stores where id = v_store_id;
    if v_store.id is not null then
      v_store_name := v_store.store_name;
    end if;
  end if;

  select * into v_position from public.positions where id = v_position_id;
  if v_position.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_reference', 'field', 'position_id');
  end if;

  if not public.i_have_full_access()
     and not (v_account.account_name = any(public.get_my_allowed_accounts())) then
    return jsonb_build_object('ok', false, 'error', 'out_of_scope');
  end if;

  select * into v_group from public.groups where id = v_account.group_id;

  insert into public.headcount_requests (
    account_id, store_id, position_id,
    employment_type, area, request_type,
    headcount_needed, vacant_date, target_fill_date,
    urgency, reason,
    status,
    group_id, account_name_snapshot, store_name_snapshot,
    position_name_snapshot, group_name_snapshot,
    requested_by_user_id, requested_by_name, requested_by_role
  ) values (
    v_account_id, v_store_id, v_position_id,
    coalesce(p_input->>'employment_type', 'Stationary'),
    p_input->>'area',
    coalesce(p_input->>'request_type', 'Replacement'),
    coalesce((p_input->>'headcount_needed')::int, 1),
    nullif(p_input->>'vacant_date', '')::date,
    nullif(p_input->>'target_fill_date', '')::date,
    coalesce(p_input->>'urgency', 'Medium'),
    p_input->>'reason',
    'pending',
    v_account.group_id, v_account.account_name, v_store_name,
    v_position.position_name, v_group.group_name,
    public.get_current_profile_id(), public.get_my_full_name(), v_role
  ) returning id into v_request_id;

  return jsonb_build_object(
    'ok',         true,
    'request_id', v_request_id,
    'status',     'pending'
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.submit_hrco_correction_update(p_correction_request_id uuid, p_hrco_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update public.hr_emploc
  set
    ops_remarks = nullif(trim(p_hrco_notes), ''),
    hr_status = 'For Review',
    updated_at = now()
  where id = p_correction_request_id
    and hr_status = 'For Correction';

  if not found then
    raise exception 'Correction request not found or not in For Correction status'
      using errcode = 'P0002';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.submit_store_import_v2(p_file_name text, p_group_id uuid, p_account_id uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_batch_id uuid;
  v_result   jsonb;
BEGIN
  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows must be a jsonb array';
  END IF;
  IF jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: p_rows is empty';
  END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN
    RAISE EXCEPTION 'INVALID_INPUT: max 5000 rows per batch';
  END IF;

  v_batch_id := public.create_store_import_batch(p_file_name, p_group_id, p_account_id);
  v_result   := public.add_store_import_rows(v_batch_id, p_rows);

  RETURN v_result;  -- already includes batch_id, totals, status, error_summary
END$function$
;

CREATE OR REPLACE FUNCTION public.sync_employee_mika_benefits(p_plantilla_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p plantilla%ROWTYPE;
  v_e employees%ROWTYPE;
  v_latest_mika RECORD;
  v_now timestamptz := NOW();
BEGIN
  IF NOT public._can_act_on_plantilla(p_plantilla_id, 'mika_sync') THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT * INTO v_p FROM public.plantilla WHERE id = p_plantilla_id;
  IF v_p.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','plantilla_not_found');
  END IF;

  SELECT * INTO v_e FROM public.employees
  WHERE employee_no = v_p.employee_no OR employee_no = v_p.emploc_no
  LIMIT 1;

  IF v_e.id IS NULL THEN
    SELECT mr.sss_no, mr.philhealth_no, mr.pagibig_no, mr.tin_no, mr.atm_no, ml.submitted_at
    INTO   v_latest_mika
    FROM   public.mika_import_rows mr
    JOIN   public.mika_import_logs ml ON ml.id = mr.import_log_id
    WHERE  mr.employee_no IN (v_p.employee_no, v_p.emploc_no)
      AND  ml.status IN ('Approved','approved_by_super_admin')
    ORDER BY ml.submitted_at DESC
    LIMIT 1;
  END IF;

  UPDATE public.plantilla
  SET last_mika_synced_at = v_now,
      last_mika_synced_by = public.get_current_profile_id()
  WHERE id = p_plantilla_id;

  PERFORM public._log_employee_action(
    p_plantilla_id, 'MIKA_SYNC',
    format('MIKA benefits synced by %s', public.get_my_full_name()),
    NULL,
    jsonb_build_object('synced_at', v_now, 'role', public.get_my_role())
  );

  RETURN jsonb_build_object(
    'ok', true,
    'plantilla_id', p_plantilla_id,
    'last_synced_at', v_now,
    'synced_by', public.get_my_full_name(),
    'benefits', jsonb_build_object(
      'sss',        COALESCE(v_e.sss_no,        v_latest_mika.sss_no),
      'philhealth', COALESCE(v_e.philhealth_no, v_latest_mika.philhealth_no),
      'pagibig',    COALESCE(v_e.pagibig_no,    v_latest_mika.pagibig_no),
      'tin',        COALESCE(v_e.tin_no,        v_latest_mika.tin_no)
    ),
    'source', CASE WHEN v_e.id IS NOT NULL THEN 'employees' ELSE 'mika_import_rows' END
  );
END$function$
;

CREATE OR REPLACE FUNCTION public.sync_users_profile_role_from_role_id()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.role_id is null then
    new.role := null;
  else
    select r.role_name
    into new.role
    from public.roles r
    where r.id = new.role_id;
  end if;

  return new;
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


CREATE OR REPLACE FUNCTION public.tg_hr_emploc_resolve_account_fk()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.account IS NOT NULL AND NEW.account_id IS NULL THEN
    SELECT a.id INTO NEW.account_id
    FROM public.accounts a
    WHERE a.account_name = NEW.account AND a.is_active = true
    LIMIT 1;
  END IF;
  IF NEW.account_id IS NOT NULL AND NEW.account IS NULL THEN
    SELECT a.account_name INTO NEW.account
    FROM public.accounts a WHERE a.id = NEW.account_id LIMIT 1;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.tg_plantilla_resolve_account_fk()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.account IS NOT NULL AND NEW.account_id IS NULL THEN
    SELECT a.id INTO NEW.account_id
    FROM public.accounts a
    WHERE a.account_name = NEW.account
      AND a.is_active = true
    LIMIT 1;
  END IF;

  IF NEW.account_id IS NOT NULL AND NEW.account IS NULL THEN
    SELECT a.account_name INTO NEW.account
    FROM public.accounts a
    WHERE a.id = NEW.account_id
    LIMIT 1;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.tg_sync_emploc_employee_no()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.employee_no IS NOT NULL AND NEW.emploc_no IS DISTINCT FROM NEW.employee_no THEN
    NEW.emploc_no := NEW.employee_no;
  ELSIF NEW.employee_no IS NULL AND NEW.emploc_no IS NOT NULL THEN
    NEW.employee_no := NEW.emploc_no;
  END IF;
  RETURN NEW;
END
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


CREATE OR REPLACE FUNCTION public.trg_account_deactivation_cascade()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_open_count INT;
BEGIN
  IF NEW.is_active = false AND OLD.is_active = true THEN
    -- Count open vacancies about to be put on hold
    SELECT COUNT(*) INTO v_open_count
    FROM vacancies
    WHERE account = OLD.account_name
      AND status IN ('Open', 'For Sourcing')
      AND COALESCE(is_archived, false) = false;

    -- Put all open vacancies on hold
    UPDATE vacancies
    SET status = 'On Hold',
        updated_at = NOW()
    WHERE account = OLD.account_name
      AND status IN ('Open', 'For Sourcing')
      AND COALESCE(is_archived, false) = false;

    -- Notify admins if any vacancies were affected
    IF v_open_count > 0 THEN
      INSERT INTO notifications (recipient_role, title, message, reference_type, reference_id)
      VALUES
        ('Head Admin',
         '⚠️ Account Deactivated — Vacancies On Hold',
         'Account "' || OLD.account_name || '" was deactivated. '
           || v_open_count || ' open vacancy/vacancies have been put On Hold.',
         'account', OLD.id::text),
        ('Super Admin',
         '⚠️ Account Deactivated — Vacancies On Hold',
         'Account "' || OLD.account_name || '" was deactivated. '
           || v_open_count || ' open vacancy/vacancies have been put On Hold.',
         'account', OLD.id::text);
    END IF;
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_auto_assign_vcode()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF (NEW.vcode IS NULL OR TRIM(NEW.vcode) = '') AND NEW.account_id IS NOT NULL THEN
    NEW.vcode := generate_vcode_for_account(NEW.account_id);
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_enforce_user_hierarchy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_actor_level    INT;
  v_target_level   INT;
  v_new_role_level INT;
BEGIN
  -- Allow service-role operations (background jobs, migrations)
  -- auth.uid() is NULL when called via service role key
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  v_actor_level  := get_my_role_level();
  v_target_level := get_target_role_level(OLD.id);

  -- ── Self-update: only allow non-sensitive field changes ──────
  IF OLD.auth_user_id = auth.uid() THEN
    IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot change your own role.';
    END IF;
    IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot change your own active status.';
    END IF;
    RETURN NEW;
  END IF;

  -- ── Editing another user: must strictly outrank target ───────
  IF v_actor_level IS NULL OR v_actor_level <= COALESCE(v_target_level, 0) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Insufficient role level to modify this user. '
      'Your level: %, Target level: %', v_actor_level, v_target_level;
  END IF;

  -- ── Role change: new role must be strictly below actor level ─
  IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
    SELECT r.role_level INTO v_new_role_level
    FROM roles r WHERE r.id = NEW.role_id;

    IF v_new_role_level >= v_actor_level THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot assign a role at or above your own level. '
        'Your level: %, Attempted: %', v_actor_level, v_new_role_level;
    END IF;
  END IF;

  -- ── Email change: Super Admin only ───────────────────────────
  IF NEW.email IS DISTINCT FROM OLD.email THEN
    IF v_actor_level < 100 THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin can change a user email.';
    END IF;
  END IF;

  -- ── Reactivation guard ────────────────────────────────────────
  IF NEW.is_active = true AND OLD.is_active = false THEN
    IF v_actor_level <= COALESCE(v_target_level, 0) THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot reactivate a user at or above your role level.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_fn_ghost_resolve_on_mika_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'Approved'
     AND (OLD.status IS DISTINCT FROM 'Approved') THEN
    PERFORM public.fn_reconcile_ghost_type_b(NEW.id);
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_fn_ghost_resolve_on_plantilla_active()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.employee_no IS NOT NULL THEN
    PERFORM public.fn_reconcile_ghost_type_a(NEW.employee_no, NEW.account);
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_fn_plantilla_depart_create_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Legacy compatibility trigger.
  -- Vacancy lifecycle is now centralized in:
  -- public.reopen_or_create_vacancy_for_plantilla()
  --
  -- Intentionally NO-OP to prevent:
  --   * duplicate vacancy generation
  --   * random replacement VCODE creation
  --   * ghost vacancy rows
  --
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_fn_set_hired_visible_until()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.status = 'Confirmed Onboard'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'Confirmed Onboard')
  THEN
    NEW.hired_visible_until := COALESCE(NEW.hired_at, NOW()) + INTERVAL '7 days';
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_prevent_duplicate_closure_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Duplicate pending closure check
  IF EXISTS (
    SELECT 1 FROM public.vacancies
    WHERE vcode = NEW.vacancy_vcode AND has_pending_closure = true
  ) THEN
    RAISE EXCEPTION 'DUPLICATE_REQUEST: This vacancy already has a pending closure request.';
  END IF;

  -- T0004: fulfillment guard at DB layer (Layer 2)
  PERFORM public.fn_assert_vacancy_closeable(NEW.vacancy_vcode);

  IF NEW.requested_by_user_id IS NULL THEN
    NEW.requested_by_user_id := public.get_my_profile_id();
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_set_correction_attach_uploaded_by()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.uploaded_by := public.get_my_profile_id();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_validate_temp_override()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Cannot grant override to yourself
  IF NEW.user_id = get_my_profile_id() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot grant a permission override to yourself.';
  END IF;

  -- Cannot grant override to a user at or above your level
  IF NOT is_super_admin() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin can grant permission overrides.';
  END IF;

  -- Expiry cap: maximum 30 days from now
  IF NEW.expires_at > NOW() + INTERVAL '30 days' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Override expiry cannot exceed 30 days from now.';
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_qa_schedule(p_schedule_id uuid, p_is_enabled boolean DEFAULT NULL::boolean, p_frequency text DEFAULT NULL::text, p_run_time time without time zone DEFAULT NULL::time without time zone, p_environment text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_frequency text;
  v_run_time time;
  v_environment text;
begin
  if not (i_have_full_access() or get_my_role_level() >= 90) then
    raise exception 'Only Head Admin or Super Admin can update QA schedules';
  end if;

  select
    coalesce(p_frequency, frequency),
    coalesce(p_run_time, run_time),
    coalesce(p_environment, environment)
  into v_frequency, v_run_time, v_environment
  from public.qa_schedules
  where id = p_schedule_id
    and archived_at is null;

  if v_frequency is null then
    raise exception 'QA schedule not found';
  end if;

  update public.qa_schedules
  set is_enabled = coalesce(p_is_enabled, is_enabled),
      frequency = v_frequency,
      run_time = v_run_time,
      environment = v_environment,
      updated_by = get_current_profile_id(),
      updated_at = now(),
      next_run_at = public.qa_calculate_next_run_at(v_frequency, v_run_time, timezone, now())
  where id = p_schedule_id;

  return p_schedule_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.update_workforce_assignment_dates(p_assignment_id uuid, p_start_date date, p_end_date date, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_name    TEXT;
  v_current_status TEXT;
BEGIN
  IF NOT (get_my_role_level() = ANY (ARRAY[100, 90, 30]) OR i_have_full_access()) THEN
    RAISE EXCEPTION 'Access denied: Data Team or above required.';
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'Both start_date and end_date are required.';
  END IF;
  IF p_start_date > p_end_date THEN
    RAISE EXCEPTION 'start_date must be <= end_date.';
  END IF;

  SELECT status INTO v_current_status
  FROM workforce_assignments WHERE id = p_assignment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Assignment not found.';
  END IF;
  IF v_current_status IN ('Completed','Cancelled','Rejected') THEN
    RAISE EXCEPTION 'Cannot update dates on a % assignment.', v_current_status;
  END IF;

  v_caller_name := get_my_full_name();

  UPDATE workforce_assignments SET
    start_date = p_start_date,
    end_date   = p_end_date,
    notes      = COALESCE(p_notes, notes),
    updated_at = now(),
    updated_by = v_caller_name
  WHERE id = p_assignment_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.upsert_user_profile_and_scopes(p_full_name text, p_email text, p_role_id uuid, p_group_ids uuid[], p_profile_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_level INT;
  v_caller_role  TEXT;
  v_target_role  TEXT;
  v_profile_id   UUID := p_profile_id;
  v_gid          UUID;
  v_old_data     jsonb;
BEGIN
  -- ── Auth ────────────────────────────────────────────────────────────────
  SELECT r.role_level, r.role_name
    INTO v_caller_level, v_caller_role
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: Head Admin cannot assign Super Admin role ─────────────────────
  SELECT role_name INTO v_target_role FROM public.roles WHERE id = p_role_id;

  IF v_target_role IN ('Super Admin', 'superAdmin', 'super_admin')
     AND COALESCE(v_caller_level, 0) < 100 THEN
    RAISE EXCEPTION 'only Super Admin can assign the Super Admin role'
      USING ERRCODE = '42501';
  END IF;

  -- ── Update or insert users_profile ───────────────────────────────────────
  IF v_profile_id IS NOT NULL THEN
    -- Capture old state for audit
    SELECT to_jsonb(up.*) INTO v_old_data
      FROM public.users_profile up
     WHERE up.id = v_profile_id;

    UPDATE public.users_profile
       SET full_name  = p_full_name,
           email      = p_email,
           role_id    = p_role_id,
           updated_at = NOW()
     WHERE id = v_profile_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'user profile not found: %', v_profile_id
        USING ERRCODE = 'P0002';
    END IF;
  ELSE
    INSERT INTO public.users_profile (full_name, email, role_id, is_active)
    VALUES (p_full_name, p_email, p_role_id, TRUE)
    RETURNING id INTO v_profile_id;
  END IF;

  -- ── Replace scopes (delete + insert) ─────────────────────────────────────
  -- Note: archive-first principle applies to data entities, not to
  -- many-to-many join tables. Scope replacement is intentional.
  -- Future: add a user_scope_history table for change tracking.
  DELETE FROM public.user_scopes WHERE user_id = v_profile_id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    INSERT INTO public.user_scopes (user_id, group_id)
    VALUES (v_profile_id, v_gid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- ── Audit ────────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'User Access',
    CASE WHEN p_profile_id IS NULL THEN 'CREATE_USER' ELSE 'UPDATE_USER_ROLE' END,
    v_profile_id,
    v_old_data,
    jsonb_build_object(
      'full_name', p_full_name,
      'email', p_email,
      'role_id', p_role_id,
      'role_name', v_target_role,
      'group_ids', p_group_ids
    )
  );

  RETURN v_profile_id;
END;
$function$
;

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


create or replace view "public"."v_approval_queue" as  SELECT ar.id,
    ar.auth_user_id,
    ar.email,
    ar.full_name,
    ar.status,
    ar.notes,
    ar.requested_role_id,
    r.role_name AS requested_role_name,
    r.role_level AS requested_role_level,
    ar.reviewed_by,
    ar.reviewed_at,
    ar.created_at,
    ar.updated_at,
    ((EXTRACT(epoch FROM (now() - ar.created_at)))::integer / 86400) AS days_pending
   FROM (public.account_requests ar
     LEFT JOIN public.roles r ON ((r.id = ar.requested_role_id)))
  ORDER BY
        CASE ar.status
            WHEN 'pending'::public.account_request_status THEN 1
            WHEN 'rejected'::public.account_request_status THEN 2
            WHEN 'approved'::public.account_request_status THEN 3
            ELSE NULL::integer
        END, ar.created_at DESC;

        CREATE OR REPLACE FUNCTION public.get_approval_queue(
  p_status public.account_request_status DEFAULT 'pending'::public.account_request_status
)
RETURNS SETOF public.v_approval_queue
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT *
  FROM public.v_approval_queue
  WHERE status = p_status;
$function$;


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
   FROM public.v_account_kpi;


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
            count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status <> ALL (ARRAY['Failed'::text, 'Backout'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Confirmed Onboard'::text])))) AS active_applicant_count,
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
            count(*) FILTER (WHERE ((COALESCE(a.is_archived, false) = false) AND (a.status <> ALL (ARRAY['Failed'::text, 'Backout'::text, 'Did Not Report'::text, 'Rejected by Ops'::text, 'Confirmed Onboard'::text])))) AS active_applicant_count,
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


CREATE OR REPLACE FUNCTION public.withdraw_reliever_coverage_request(p_request_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_req       RECORD;
  v_caller_id UUID;
BEGIN
  v_caller_id := auth.uid();

  SELECT * INTO v_req
  FROM workforce_assignment_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found.';
  END IF;

  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'Only Pending requests can be withdrawn. Current status: %', v_req.status;
  END IF;

  -- Requester, Head Admin, Super Admin, or Data Team
  IF NOT (
    v_req.requested_by_id = v_caller_id
    OR get_my_role_level() = ANY (ARRAY[100, 90, 30])
    OR i_have_full_access()
  ) THEN
    RAISE EXCEPTION 'Access denied: only the requester or Data Team can withdraw this request.';
  END IF;

  UPDATE workforce_assignment_requests
  SET
    status     = 'Withdrawn',
    notes      = COALESCE(p_reason, notes),
    reviewed_by  = get_my_full_name(),
    reviewed_at  = now(),
    updated_at   = now()
  WHERE id = p_request_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.withdraw_vacancy_closure_request(p_vcode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profile_id uuid := public.get_my_profile_id();
  v_actor_name text := public.get_my_full_name();
  v_req        RECORD;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────────────────
  IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
    RAISE EXCEPTION 'forbidden: Ops Team or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- ── Validate and lock pending request ───────────────────────────────────
  SELECT *
    INTO v_req
    FROM public.vacancy_closure_requests
   WHERE vacancy_vcode = p_vcode
     AND status = 'Pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no pending closure request found for vacancy %', p_vcode
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Scope check for Ops ─────────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    -- Allow if requester owns the request OR vacancy is in their account scope
    IF v_req.requested_by_user_id IS DISTINCT FROM v_profile_id THEN
      IF NOT EXISTS (
        SELECT 1
          FROM public.vacancies v
         WHERE v.vcode = p_vcode
           AND v.account = ANY(public.get_my_allowed_accounts())
           AND v.deleted_at IS NULL
      ) THEN
        RAISE EXCEPTION 'forbidden: vacancy is outside your scope'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;

  -- ── Update closure request ───────────────────────────────────────────────
  UPDATE public.vacancy_closure_requests
  SET
    status                = 'Withdrawn',
    withdrawn_at          = NOW(),
    withdrawn_by_user_id  = v_profile_id,
    reviewed_by           = v_actor_name,
    reviewed_at           = NOW(),
    reviewer_remarks      = COALESCE(reviewer_remarks, '') ||
                            CASE WHEN reviewer_remarks IS NOT NULL THEN ' | ' ELSE '' END ||
                            'Withdrawn by ' || v_actor_name || ' at ' || NOW()::text
  WHERE id = v_req.id;

  -- ── Reset vacancy to operational ─────────────────────────────────────────
  UPDATE public.vacancies
  SET
    has_pending_closure    = false,
    closure_request_status = 'None',
    updated_at             = NOW()
  WHERE vcode = p_vcode
    AND deleted_at IS NULL;

  RETURN jsonb_build_object(
    'ok',                  true,
    'vcode',               p_vcode,
    'closure_request_id',  v_req.id,
    'withdrawn_by',        v_actor_name,
    'withdrawn_at',        NOW()
  );
END;
$function$
;

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


grant delete on table "public"."_deprecated_in_app_notifications" to "authenticated";

grant insert on table "public"."_deprecated_in_app_notifications" to "authenticated";

grant references on table "public"."_deprecated_in_app_notifications" to "authenticated";

grant select on table "public"."_deprecated_in_app_notifications" to "authenticated";

grant trigger on table "public"."_deprecated_in_app_notifications" to "authenticated";

grant truncate on table "public"."_deprecated_in_app_notifications" to "authenticated";

grant update on table "public"."_deprecated_in_app_notifications" to "authenticated";

grant delete on table "public"."_deprecated_in_app_notifications" to "service_role";

grant insert on table "public"."_deprecated_in_app_notifications" to "service_role";

grant references on table "public"."_deprecated_in_app_notifications" to "service_role";

grant select on table "public"."_deprecated_in_app_notifications" to "service_role";

grant trigger on table "public"."_deprecated_in_app_notifications" to "service_role";

grant truncate on table "public"."_deprecated_in_app_notifications" to "service_role";

grant update on table "public"."_deprecated_in_app_notifications" to "service_role";

grant delete on table "public"."account_positions" to "authenticated";

grant insert on table "public"."account_positions" to "authenticated";

grant references on table "public"."account_positions" to "authenticated";

grant select on table "public"."account_positions" to "authenticated";

grant trigger on table "public"."account_positions" to "authenticated";

grant truncate on table "public"."account_positions" to "authenticated";

grant update on table "public"."account_positions" to "authenticated";

grant delete on table "public"."account_positions" to "service_role";

grant insert on table "public"."account_positions" to "service_role";

grant references on table "public"."account_positions" to "service_role";

grant select on table "public"."account_positions" to "service_role";

grant trigger on table "public"."account_positions" to "service_role";

grant truncate on table "public"."account_positions" to "service_role";

grant update on table "public"."account_positions" to "service_role";

grant delete on table "public"."account_request_account_scopes" to "authenticated";

grant insert on table "public"."account_request_account_scopes" to "authenticated";

grant references on table "public"."account_request_account_scopes" to "authenticated";

grant select on table "public"."account_request_account_scopes" to "authenticated";

grant trigger on table "public"."account_request_account_scopes" to "authenticated";

grant truncate on table "public"."account_request_account_scopes" to "authenticated";

grant update on table "public"."account_request_account_scopes" to "authenticated";

grant delete on table "public"."account_request_account_scopes" to "service_role";

grant insert on table "public"."account_request_account_scopes" to "service_role";

grant references on table "public"."account_request_account_scopes" to "service_role";

grant select on table "public"."account_request_account_scopes" to "service_role";

grant trigger on table "public"."account_request_account_scopes" to "service_role";

grant truncate on table "public"."account_request_account_scopes" to "service_role";

grant update on table "public"."account_request_account_scopes" to "service_role";

grant delete on table "public"."account_request_group_scopes" to "authenticated";

grant insert on table "public"."account_request_group_scopes" to "authenticated";

grant references on table "public"."account_request_group_scopes" to "authenticated";

grant select on table "public"."account_request_group_scopes" to "authenticated";

grant trigger on table "public"."account_request_group_scopes" to "authenticated";

grant truncate on table "public"."account_request_group_scopes" to "authenticated";

grant update on table "public"."account_request_group_scopes" to "authenticated";

grant delete on table "public"."account_request_group_scopes" to "service_role";

grant insert on table "public"."account_request_group_scopes" to "service_role";

grant references on table "public"."account_request_group_scopes" to "service_role";

grant select on table "public"."account_request_group_scopes" to "service_role";

grant trigger on table "public"."account_request_group_scopes" to "service_role";

grant truncate on table "public"."account_request_group_scopes" to "service_role";

grant update on table "public"."account_request_group_scopes" to "service_role";

grant delete on table "public"."account_requests" to "authenticated";

grant insert on table "public"."account_requests" to "authenticated";

grant references on table "public"."account_requests" to "authenticated";

grant select on table "public"."account_requests" to "authenticated";

grant trigger on table "public"."account_requests" to "authenticated";

grant truncate on table "public"."account_requests" to "authenticated";

grant update on table "public"."account_requests" to "authenticated";

grant delete on table "public"."account_requests" to "service_role";

grant insert on table "public"."account_requests" to "service_role";

grant references on table "public"."account_requests" to "service_role";

grant select on table "public"."account_requests" to "service_role";

grant trigger on table "public"."account_requests" to "service_role";

grant truncate on table "public"."account_requests" to "service_role";

grant update on table "public"."account_requests" to "service_role";

grant insert on table "public"."account_requests" to "supabase_auth_admin";

grant select on table "public"."account_requests" to "supabase_auth_admin";

grant delete on table "public"."accounts" to "authenticated";

grant insert on table "public"."accounts" to "authenticated";

grant references on table "public"."accounts" to "authenticated";

grant select on table "public"."accounts" to "authenticated";

grant trigger on table "public"."accounts" to "authenticated";

grant truncate on table "public"."accounts" to "authenticated";

grant update on table "public"."accounts" to "authenticated";

grant delete on table "public"."accounts" to "service_role";

grant insert on table "public"."accounts" to "service_role";

grant references on table "public"."accounts" to "service_role";

grant select on table "public"."accounts" to "service_role";

grant trigger on table "public"."accounts" to "service_role";

grant truncate on table "public"."accounts" to "service_role";

grant update on table "public"."accounts" to "service_role";

grant delete on table "public"."acting_sessions" to "authenticated";

grant insert on table "public"."acting_sessions" to "authenticated";

grant references on table "public"."acting_sessions" to "authenticated";

grant select on table "public"."acting_sessions" to "authenticated";

grant trigger on table "public"."acting_sessions" to "authenticated";

grant truncate on table "public"."acting_sessions" to "authenticated";

grant update on table "public"."acting_sessions" to "authenticated";

grant delete on table "public"."acting_sessions" to "service_role";

grant insert on table "public"."acting_sessions" to "service_role";

grant references on table "public"."acting_sessions" to "service_role";

grant select on table "public"."acting_sessions" to "service_role";

grant trigger on table "public"."acting_sessions" to "service_role";

grant truncate on table "public"."acting_sessions" to "service_role";

grant update on table "public"."acting_sessions" to "service_role";

grant delete on table "public"."activity_log" to "authenticated";

grant insert on table "public"."activity_log" to "authenticated";

grant references on table "public"."activity_log" to "authenticated";

grant select on table "public"."activity_log" to "authenticated";

grant trigger on table "public"."activity_log" to "authenticated";

grant truncate on table "public"."activity_log" to "authenticated";

grant update on table "public"."activity_log" to "authenticated";

grant delete on table "public"."activity_log" to "service_role";

grant insert on table "public"."activity_log" to "service_role";

grant references on table "public"."activity_log" to "service_role";

grant select on table "public"."activity_log" to "service_role";

grant trigger on table "public"."activity_log" to "service_role";

grant truncate on table "public"."activity_log" to "service_role";

grant update on table "public"."activity_log" to "service_role";

grant delete on table "public"."applicants" to "authenticated";

grant insert on table "public"."applicants" to "authenticated";

grant references on table "public"."applicants" to "authenticated";

grant select on table "public"."applicants" to "authenticated";

grant trigger on table "public"."applicants" to "authenticated";

grant truncate on table "public"."applicants" to "authenticated";

grant update on table "public"."applicants" to "authenticated";

grant delete on table "public"."applicants" to "service_role";

grant insert on table "public"."applicants" to "service_role";

grant references on table "public"."applicants" to "service_role";

grant select on table "public"."applicants" to "service_role";

grant trigger on table "public"."applicants" to "service_role";

grant truncate on table "public"."applicants" to "service_role";

grant update on table "public"."applicants" to "service_role";

grant references on table "public"."audit_logs" to "authenticated";

grant select on table "public"."audit_logs" to "authenticated";

grant trigger on table "public"."audit_logs" to "authenticated";

grant truncate on table "public"."audit_logs" to "authenticated";

grant delete on table "public"."audit_logs" to "service_role";

grant insert on table "public"."audit_logs" to "service_role";

grant references on table "public"."audit_logs" to "service_role";

grant select on table "public"."audit_logs" to "service_role";

grant trigger on table "public"."audit_logs" to "service_role";

grant truncate on table "public"."audit_logs" to "service_role";

grant update on table "public"."audit_logs" to "service_role";

grant delete on table "public"."backout_reasons" to "authenticated";

grant insert on table "public"."backout_reasons" to "authenticated";

grant references on table "public"."backout_reasons" to "authenticated";

grant select on table "public"."backout_reasons" to "authenticated";

grant trigger on table "public"."backout_reasons" to "authenticated";

grant truncate on table "public"."backout_reasons" to "authenticated";

grant update on table "public"."backout_reasons" to "authenticated";

grant delete on table "public"."backout_reasons" to "service_role";

grant insert on table "public"."backout_reasons" to "service_role";

grant references on table "public"."backout_reasons" to "service_role";

grant select on table "public"."backout_reasons" to "service_role";

grant trigger on table "public"."backout_reasons" to "service_role";

grant truncate on table "public"."backout_reasons" to "service_role";

grant update on table "public"."backout_reasons" to "service_role";

grant delete on table "public"."bulk_emploc_items" to "authenticated";

grant insert on table "public"."bulk_emploc_items" to "authenticated";

grant references on table "public"."bulk_emploc_items" to "authenticated";

grant select on table "public"."bulk_emploc_items" to "authenticated";

grant trigger on table "public"."bulk_emploc_items" to "authenticated";

grant truncate on table "public"."bulk_emploc_items" to "authenticated";

grant update on table "public"."bulk_emploc_items" to "authenticated";

grant delete on table "public"."bulk_emploc_items" to "service_role";

grant insert on table "public"."bulk_emploc_items" to "service_role";

grant references on table "public"."bulk_emploc_items" to "service_role";

grant select on table "public"."bulk_emploc_items" to "service_role";

grant trigger on table "public"."bulk_emploc_items" to "service_role";

grant truncate on table "public"."bulk_emploc_items" to "service_role";

grant update on table "public"."bulk_emploc_items" to "service_role";

grant delete on table "public"."bulk_emploc_uploads" to "authenticated";

grant insert on table "public"."bulk_emploc_uploads" to "authenticated";

grant references on table "public"."bulk_emploc_uploads" to "authenticated";

grant select on table "public"."bulk_emploc_uploads" to "authenticated";

grant trigger on table "public"."bulk_emploc_uploads" to "authenticated";

grant truncate on table "public"."bulk_emploc_uploads" to "authenticated";

grant update on table "public"."bulk_emploc_uploads" to "authenticated";

grant delete on table "public"."bulk_emploc_uploads" to "service_role";

grant insert on table "public"."bulk_emploc_uploads" to "service_role";

grant references on table "public"."bulk_emploc_uploads" to "service_role";

grant select on table "public"."bulk_emploc_uploads" to "service_role";

grant trigger on table "public"."bulk_emploc_uploads" to "service_role";

grant truncate on table "public"."bulk_emploc_uploads" to "service_role";

grant update on table "public"."bulk_emploc_uploads" to "service_role";

grant delete on table "public"."deactivation_audit_log" to "authenticated";

grant insert on table "public"."deactivation_audit_log" to "authenticated";

grant references on table "public"."deactivation_audit_log" to "authenticated";

grant select on table "public"."deactivation_audit_log" to "authenticated";

grant trigger on table "public"."deactivation_audit_log" to "authenticated";

grant truncate on table "public"."deactivation_audit_log" to "authenticated";

grant update on table "public"."deactivation_audit_log" to "authenticated";

grant delete on table "public"."deactivation_audit_log" to "service_role";

grant insert on table "public"."deactivation_audit_log" to "service_role";

grant references on table "public"."deactivation_audit_log" to "service_role";

grant select on table "public"."deactivation_audit_log" to "service_role";

grant trigger on table "public"."deactivation_audit_log" to "service_role";

grant truncate on table "public"."deactivation_audit_log" to "service_role";

grant update on table "public"."deactivation_audit_log" to "service_role";

grant delete on table "public"."deactivation_batches" to "authenticated";

grant insert on table "public"."deactivation_batches" to "authenticated";

grant references on table "public"."deactivation_batches" to "authenticated";

grant select on table "public"."deactivation_batches" to "authenticated";

grant trigger on table "public"."deactivation_batches" to "authenticated";

grant truncate on table "public"."deactivation_batches" to "authenticated";

grant update on table "public"."deactivation_batches" to "authenticated";

grant delete on table "public"."deactivation_batches" to "service_role";

grant insert on table "public"."deactivation_batches" to "service_role";

grant references on table "public"."deactivation_batches" to "service_role";

grant select on table "public"."deactivation_batches" to "service_role";

grant trigger on table "public"."deactivation_batches" to "service_role";

grant truncate on table "public"."deactivation_batches" to "service_role";

grant update on table "public"."deactivation_batches" to "service_role";

grant delete on table "public"."deactivation_items" to "authenticated";

grant insert on table "public"."deactivation_items" to "authenticated";

grant references on table "public"."deactivation_items" to "authenticated";

grant select on table "public"."deactivation_items" to "authenticated";

grant trigger on table "public"."deactivation_items" to "authenticated";

grant truncate on table "public"."deactivation_items" to "authenticated";

grant update on table "public"."deactivation_items" to "authenticated";

grant delete on table "public"."deactivation_items" to "service_role";

grant insert on table "public"."deactivation_items" to "service_role";

grant references on table "public"."deactivation_items" to "service_role";

grant select on table "public"."deactivation_items" to "service_role";

grant trigger on table "public"."deactivation_items" to "service_role";

grant truncate on table "public"."deactivation_items" to "service_role";

grant update on table "public"."deactivation_items" to "service_role";

grant delete on table "public"."deactivation_requests" to "authenticated";

grant insert on table "public"."deactivation_requests" to "authenticated";

grant references on table "public"."deactivation_requests" to "authenticated";

grant select on table "public"."deactivation_requests" to "authenticated";

grant trigger on table "public"."deactivation_requests" to "authenticated";

grant truncate on table "public"."deactivation_requests" to "authenticated";

grant update on table "public"."deactivation_requests" to "authenticated";

grant delete on table "public"."deactivation_requests" to "service_role";

grant insert on table "public"."deactivation_requests" to "service_role";

grant references on table "public"."deactivation_requests" to "service_role";

grant select on table "public"."deactivation_requests" to "service_role";

grant trigger on table "public"."deactivation_requests" to "service_role";

grant truncate on table "public"."deactivation_requests" to "service_role";

grant update on table "public"."deactivation_requests" to "service_role";

grant delete on table "public"."deployer" to "authenticated";

grant insert on table "public"."deployer" to "authenticated";

grant references on table "public"."deployer" to "authenticated";

grant select on table "public"."deployer" to "authenticated";

grant trigger on table "public"."deployer" to "authenticated";

grant truncate on table "public"."deployer" to "authenticated";

grant update on table "public"."deployer" to "authenticated";

grant delete on table "public"."deployer" to "service_role";

grant insert on table "public"."deployer" to "service_role";

grant references on table "public"."deployer" to "service_role";

grant select on table "public"."deployer" to "service_role";

grant trigger on table "public"."deployer" to "service_role";

grant truncate on table "public"."deployer" to "service_role";

grant update on table "public"."deployer" to "service_role";

grant delete on table "public"."employee_activity_log" to "authenticated";

grant insert on table "public"."employee_activity_log" to "authenticated";

grant references on table "public"."employee_activity_log" to "authenticated";

grant select on table "public"."employee_activity_log" to "authenticated";

grant trigger on table "public"."employee_activity_log" to "authenticated";

grant truncate on table "public"."employee_activity_log" to "authenticated";

grant update on table "public"."employee_activity_log" to "authenticated";

grant delete on table "public"."employee_activity_log" to "service_role";

grant insert on table "public"."employee_activity_log" to "service_role";

grant references on table "public"."employee_activity_log" to "service_role";

grant select on table "public"."employee_activity_log" to "service_role";

grant trigger on table "public"."employee_activity_log" to "service_role";

grant truncate on table "public"."employee_activity_log" to "service_role";

grant update on table "public"."employee_activity_log" to "service_role";

grant delete on table "public"."employee_deployments" to "authenticated";

grant insert on table "public"."employee_deployments" to "authenticated";

grant references on table "public"."employee_deployments" to "authenticated";

grant select on table "public"."employee_deployments" to "authenticated";

grant trigger on table "public"."employee_deployments" to "authenticated";

grant truncate on table "public"."employee_deployments" to "authenticated";

grant update on table "public"."employee_deployments" to "authenticated";

grant delete on table "public"."employee_deployments" to "service_role";

grant insert on table "public"."employee_deployments" to "service_role";

grant references on table "public"."employee_deployments" to "service_role";

grant select on table "public"."employee_deployments" to "service_role";

grant trigger on table "public"."employee_deployments" to "service_role";

grant truncate on table "public"."employee_deployments" to "service_role";

grant update on table "public"."employee_deployments" to "service_role";

grant delete on table "public"."employee_transfers" to "authenticated";

grant insert on table "public"."employee_transfers" to "authenticated";

grant references on table "public"."employee_transfers" to "authenticated";

grant select on table "public"."employee_transfers" to "authenticated";

grant trigger on table "public"."employee_transfers" to "authenticated";

grant truncate on table "public"."employee_transfers" to "authenticated";

grant update on table "public"."employee_transfers" to "authenticated";

grant delete on table "public"."employee_transfers" to "service_role";

grant insert on table "public"."employee_transfers" to "service_role";

grant references on table "public"."employee_transfers" to "service_role";

grant select on table "public"."employee_transfers" to "service_role";

grant trigger on table "public"."employee_transfers" to "service_role";

grant truncate on table "public"."employee_transfers" to "service_role";

grant update on table "public"."employee_transfers" to "service_role";

grant delete on table "public"."employees" to "authenticated";

grant insert on table "public"."employees" to "authenticated";

grant references on table "public"."employees" to "authenticated";

grant select on table "public"."employees" to "authenticated";

grant trigger on table "public"."employees" to "authenticated";

grant truncate on table "public"."employees" to "authenticated";

grant update on table "public"."employees" to "authenticated";

grant delete on table "public"."employees" to "service_role";

grant insert on table "public"."employees" to "service_role";

grant references on table "public"."employees" to "service_role";

grant select on table "public"."employees" to "service_role";

grant trigger on table "public"."employees" to "service_role";

grant truncate on table "public"."employees" to "service_role";

grant update on table "public"."employees" to "service_role";

grant delete on table "public"."feedback_reports" to "authenticated";

grant insert on table "public"."feedback_reports" to "authenticated";

grant references on table "public"."feedback_reports" to "authenticated";

grant select on table "public"."feedback_reports" to "authenticated";

grant trigger on table "public"."feedback_reports" to "authenticated";

grant truncate on table "public"."feedback_reports" to "authenticated";

grant update on table "public"."feedback_reports" to "authenticated";

grant delete on table "public"."feedback_reports" to "service_role";

grant insert on table "public"."feedback_reports" to "service_role";

grant references on table "public"."feedback_reports" to "service_role";

grant select on table "public"."feedback_reports" to "service_role";

grant trigger on table "public"."feedback_reports" to "service_role";

grant truncate on table "public"."feedback_reports" to "service_role";

grant update on table "public"."feedback_reports" to "service_role";

grant delete on table "public"."groups" to "authenticated";

grant insert on table "public"."groups" to "authenticated";

grant references on table "public"."groups" to "authenticated";

grant select on table "public"."groups" to "authenticated";

grant trigger on table "public"."groups" to "authenticated";

grant truncate on table "public"."groups" to "authenticated";

grant update on table "public"."groups" to "authenticated";

grant delete on table "public"."groups" to "service_role";

grant insert on table "public"."groups" to "service_role";

grant references on table "public"."groups" to "service_role";

grant select on table "public"."groups" to "service_role";

grant trigger on table "public"."groups" to "service_role";

grant truncate on table "public"."groups" to "service_role";

grant update on table "public"."groups" to "service_role";

grant delete on table "public"."headcount_requests" to "authenticated";

grant insert on table "public"."headcount_requests" to "authenticated";

grant references on table "public"."headcount_requests" to "authenticated";

grant select on table "public"."headcount_requests" to "authenticated";

grant trigger on table "public"."headcount_requests" to "authenticated";

grant truncate on table "public"."headcount_requests" to "authenticated";

grant update on table "public"."headcount_requests" to "authenticated";

grant delete on table "public"."headcount_requests" to "service_role";

grant insert on table "public"."headcount_requests" to "service_role";

grant references on table "public"."headcount_requests" to "service_role";

grant select on table "public"."headcount_requests" to "service_role";

grant trigger on table "public"."headcount_requests" to "service_role";

grant truncate on table "public"."headcount_requests" to "service_role";

grant update on table "public"."headcount_requests" to "service_role";

grant delete on table "public"."hr_emploc" to "authenticated";

grant insert on table "public"."hr_emploc" to "authenticated";

grant references on table "public"."hr_emploc" to "authenticated";

grant select on table "public"."hr_emploc" to "authenticated";

grant trigger on table "public"."hr_emploc" to "authenticated";

grant truncate on table "public"."hr_emploc" to "authenticated";

grant update on table "public"."hr_emploc" to "authenticated";

grant delete on table "public"."hr_emploc" to "service_role";

grant insert on table "public"."hr_emploc" to "service_role";

grant references on table "public"."hr_emploc" to "service_role";

grant select on table "public"."hr_emploc" to "service_role";

grant trigger on table "public"."hr_emploc" to "service_role";

grant truncate on table "public"."hr_emploc" to "service_role";

grant update on table "public"."hr_emploc" to "service_role";

grant delete on table "public"."hr_emploc_correction_attachments" to "authenticated";

grant insert on table "public"."hr_emploc_correction_attachments" to "authenticated";

grant references on table "public"."hr_emploc_correction_attachments" to "authenticated";

grant select on table "public"."hr_emploc_correction_attachments" to "authenticated";

grant trigger on table "public"."hr_emploc_correction_attachments" to "authenticated";

grant truncate on table "public"."hr_emploc_correction_attachments" to "authenticated";

grant update on table "public"."hr_emploc_correction_attachments" to "authenticated";

grant delete on table "public"."hr_emploc_correction_attachments" to "service_role";

grant insert on table "public"."hr_emploc_correction_attachments" to "service_role";

grant references on table "public"."hr_emploc_correction_attachments" to "service_role";

grant select on table "public"."hr_emploc_correction_attachments" to "service_role";

grant trigger on table "public"."hr_emploc_correction_attachments" to "service_role";

grant truncate on table "public"."hr_emploc_correction_attachments" to "service_role";

grant update on table "public"."hr_emploc_correction_attachments" to "service_role";

grant delete on table "public"."hr_emploc_deletion_requests" to "authenticated";

grant insert on table "public"."hr_emploc_deletion_requests" to "authenticated";

grant references on table "public"."hr_emploc_deletion_requests" to "authenticated";

grant select on table "public"."hr_emploc_deletion_requests" to "authenticated";

grant trigger on table "public"."hr_emploc_deletion_requests" to "authenticated";

grant truncate on table "public"."hr_emploc_deletion_requests" to "authenticated";

grant update on table "public"."hr_emploc_deletion_requests" to "authenticated";

grant delete on table "public"."hr_emploc_deletion_requests" to "service_role";

grant insert on table "public"."hr_emploc_deletion_requests" to "service_role";

grant references on table "public"."hr_emploc_deletion_requests" to "service_role";

grant select on table "public"."hr_emploc_deletion_requests" to "service_role";

grant trigger on table "public"."hr_emploc_deletion_requests" to "service_role";

grant truncate on table "public"."hr_emploc_deletion_requests" to "service_role";

grant update on table "public"."hr_emploc_deletion_requests" to "service_role";

grant delete on table "public"."hr_emploc_issue_types" to "authenticated";

grant insert on table "public"."hr_emploc_issue_types" to "authenticated";

grant references on table "public"."hr_emploc_issue_types" to "authenticated";

grant select on table "public"."hr_emploc_issue_types" to "authenticated";

grant trigger on table "public"."hr_emploc_issue_types" to "authenticated";

grant truncate on table "public"."hr_emploc_issue_types" to "authenticated";

grant update on table "public"."hr_emploc_issue_types" to "authenticated";

grant delete on table "public"."hr_emploc_issue_types" to "service_role";

grant insert on table "public"."hr_emploc_issue_types" to "service_role";

grant references on table "public"."hr_emploc_issue_types" to "service_role";

grant select on table "public"."hr_emploc_issue_types" to "service_role";

grant trigger on table "public"."hr_emploc_issue_types" to "service_role";

grant truncate on table "public"."hr_emploc_issue_types" to "service_role";

grant update on table "public"."hr_emploc_issue_types" to "service_role";

grant delete on table "public"."hr_emploc_rejection_reasons" to "authenticated";

grant insert on table "public"."hr_emploc_rejection_reasons" to "authenticated";

grant references on table "public"."hr_emploc_rejection_reasons" to "authenticated";

grant select on table "public"."hr_emploc_rejection_reasons" to "authenticated";

grant trigger on table "public"."hr_emploc_rejection_reasons" to "authenticated";

grant truncate on table "public"."hr_emploc_rejection_reasons" to "authenticated";

grant update on table "public"."hr_emploc_rejection_reasons" to "authenticated";

grant delete on table "public"."hr_emploc_rejection_reasons" to "service_role";

grant insert on table "public"."hr_emploc_rejection_reasons" to "service_role";

grant references on table "public"."hr_emploc_rejection_reasons" to "service_role";

grant select on table "public"."hr_emploc_rejection_reasons" to "service_role";

grant trigger on table "public"."hr_emploc_rejection_reasons" to "service_role";

grant truncate on table "public"."hr_emploc_rejection_reasons" to "service_role";

grant update on table "public"."hr_emploc_rejection_reasons" to "service_role";

grant delete on table "public"."hr_emploc_store_links" to "authenticated";

grant insert on table "public"."hr_emploc_store_links" to "authenticated";

grant references on table "public"."hr_emploc_store_links" to "authenticated";

grant select on table "public"."hr_emploc_store_links" to "authenticated";

grant trigger on table "public"."hr_emploc_store_links" to "authenticated";

grant truncate on table "public"."hr_emploc_store_links" to "authenticated";

grant update on table "public"."hr_emploc_store_links" to "authenticated";

grant delete on table "public"."hr_emploc_store_links" to "service_role";

grant insert on table "public"."hr_emploc_store_links" to "service_role";

grant references on table "public"."hr_emploc_store_links" to "service_role";

grant select on table "public"."hr_emploc_store_links" to "service_role";

grant trigger on table "public"."hr_emploc_store_links" to "service_role";

grant truncate on table "public"."hr_emploc_store_links" to "service_role";

grant update on table "public"."hr_emploc_store_links" to "service_role";

grant delete on table "public"."login_sessions" to "authenticated";

grant insert on table "public"."login_sessions" to "authenticated";

grant references on table "public"."login_sessions" to "authenticated";

grant select on table "public"."login_sessions" to "authenticated";

grant trigger on table "public"."login_sessions" to "authenticated";

grant truncate on table "public"."login_sessions" to "authenticated";

grant update on table "public"."login_sessions" to "authenticated";

grant delete on table "public"."login_sessions" to "service_role";

grant insert on table "public"."login_sessions" to "service_role";

grant references on table "public"."login_sessions" to "service_role";

grant select on table "public"."login_sessions" to "service_role";

grant trigger on table "public"."login_sessions" to "service_role";

grant truncate on table "public"."login_sessions" to "service_role";

grant update on table "public"."login_sessions" to "service_role";

grant delete on table "public"."mika_import_logs" to "authenticated";

grant insert on table "public"."mika_import_logs" to "authenticated";

grant references on table "public"."mika_import_logs" to "authenticated";

grant select on table "public"."mika_import_logs" to "authenticated";

grant trigger on table "public"."mika_import_logs" to "authenticated";

grant truncate on table "public"."mika_import_logs" to "authenticated";

grant update on table "public"."mika_import_logs" to "authenticated";

grant delete on table "public"."mika_import_logs" to "service_role";

grant insert on table "public"."mika_import_logs" to "service_role";

grant references on table "public"."mika_import_logs" to "service_role";

grant select on table "public"."mika_import_logs" to "service_role";

grant trigger on table "public"."mika_import_logs" to "service_role";

grant truncate on table "public"."mika_import_logs" to "service_role";

grant update on table "public"."mika_import_logs" to "service_role";

grant delete on table "public"."mika_import_rows" to "authenticated";

grant insert on table "public"."mika_import_rows" to "authenticated";

grant references on table "public"."mika_import_rows" to "authenticated";

grant select on table "public"."mika_import_rows" to "authenticated";

grant trigger on table "public"."mika_import_rows" to "authenticated";

grant truncate on table "public"."mika_import_rows" to "authenticated";

grant update on table "public"."mika_import_rows" to "authenticated";

grant delete on table "public"."mika_import_rows" to "service_role";

grant insert on table "public"."mika_import_rows" to "service_role";

grant references on table "public"."mika_import_rows" to "service_role";

grant select on table "public"."mika_import_rows" to "service_role";

grant trigger on table "public"."mika_import_rows" to "service_role";

grant truncate on table "public"."mika_import_rows" to "service_role";

grant update on table "public"."mika_import_rows" to "service_role";

grant delete on table "public"."notifications" to "authenticated";

grant insert on table "public"."notifications" to "authenticated";

grant references on table "public"."notifications" to "authenticated";

grant select on table "public"."notifications" to "authenticated";

grant trigger on table "public"."notifications" to "authenticated";

grant truncate on table "public"."notifications" to "authenticated";

grant update on table "public"."notifications" to "authenticated";

grant delete on table "public"."notifications" to "service_role";

grant insert on table "public"."notifications" to "service_role";

grant references on table "public"."notifications" to "service_role";

grant select on table "public"."notifications" to "service_role";

grant trigger on table "public"."notifications" to "service_role";

grant truncate on table "public"."notifications" to "service_role";

grant update on table "public"."notifications" to "service_role";

grant delete on table "public"."plantilla" to "authenticated";

grant insert on table "public"."plantilla" to "authenticated";

grant references on table "public"."plantilla" to "authenticated";

grant select on table "public"."plantilla" to "authenticated";

grant trigger on table "public"."plantilla" to "authenticated";

grant truncate on table "public"."plantilla" to "authenticated";

grant update on table "public"."plantilla" to "authenticated";

grant delete on table "public"."plantilla" to "service_role";

grant insert on table "public"."plantilla" to "service_role";

grant references on table "public"."plantilla" to "service_role";

grant select on table "public"."plantilla" to "service_role";

grant trigger on table "public"."plantilla" to "service_role";

grant truncate on table "public"."plantilla" to "service_role";

grant update on table "public"."plantilla" to "service_role";

grant delete on table "public"."plantilla_approvals" to "authenticated";

grant insert on table "public"."plantilla_approvals" to "authenticated";

grant references on table "public"."plantilla_approvals" to "authenticated";

grant select on table "public"."plantilla_approvals" to "authenticated";

grant trigger on table "public"."plantilla_approvals" to "authenticated";

grant truncate on table "public"."plantilla_approvals" to "authenticated";

grant update on table "public"."plantilla_approvals" to "authenticated";

grant delete on table "public"."plantilla_approvals" to "service_role";

grant insert on table "public"."plantilla_approvals" to "service_role";

grant references on table "public"."plantilla_approvals" to "service_role";

grant select on table "public"."plantilla_approvals" to "service_role";

grant trigger on table "public"."plantilla_approvals" to "service_role";

grant truncate on table "public"."plantilla_approvals" to "service_role";

grant update on table "public"."plantilla_approvals" to "service_role";

grant delete on table "public"."plantilla_store_links" to "authenticated";

grant insert on table "public"."plantilla_store_links" to "authenticated";

grant references on table "public"."plantilla_store_links" to "authenticated";

grant select on table "public"."plantilla_store_links" to "authenticated";

grant trigger on table "public"."plantilla_store_links" to "authenticated";

grant truncate on table "public"."plantilla_store_links" to "authenticated";

grant update on table "public"."plantilla_store_links" to "authenticated";

grant delete on table "public"."plantilla_store_links" to "service_role";

grant insert on table "public"."plantilla_store_links" to "service_role";

grant references on table "public"."plantilla_store_links" to "service_role";

grant select on table "public"."plantilla_store_links" to "service_role";

grant trigger on table "public"."plantilla_store_links" to "service_role";

grant truncate on table "public"."plantilla_store_links" to "service_role";

grant update on table "public"."plantilla_store_links" to "service_role";

grant delete on table "public"."positions" to "authenticated";

grant insert on table "public"."positions" to "authenticated";

grant references on table "public"."positions" to "authenticated";

grant select on table "public"."positions" to "authenticated";

grant trigger on table "public"."positions" to "authenticated";

grant truncate on table "public"."positions" to "authenticated";

grant update on table "public"."positions" to "authenticated";

grant delete on table "public"."positions" to "service_role";

grant insert on table "public"."positions" to "service_role";

grant references on table "public"."positions" to "service_role";

grant select on table "public"."positions" to "service_role";

grant trigger on table "public"."positions" to "service_role";

grant truncate on table "public"."positions" to "service_role";

grant update on table "public"."positions" to "service_role";

grant delete on table "public"."possible_ghost_employees" to "authenticated";

grant insert on table "public"."possible_ghost_employees" to "authenticated";

grant references on table "public"."possible_ghost_employees" to "authenticated";

grant select on table "public"."possible_ghost_employees" to "authenticated";

grant trigger on table "public"."possible_ghost_employees" to "authenticated";

grant truncate on table "public"."possible_ghost_employees" to "authenticated";

grant update on table "public"."possible_ghost_employees" to "authenticated";

grant delete on table "public"."possible_ghost_employees" to "service_role";

grant insert on table "public"."possible_ghost_employees" to "service_role";

grant references on table "public"."possible_ghost_employees" to "service_role";

grant select on table "public"."possible_ghost_employees" to "service_role";

grant trigger on table "public"."possible_ghost_employees" to "service_role";

grant truncate on table "public"."possible_ghost_employees" to "service_role";

grant update on table "public"."possible_ghost_employees" to "service_role";

grant delete on table "public"."qa_agent_evidence" to "authenticated";

grant insert on table "public"."qa_agent_evidence" to "authenticated";

grant references on table "public"."qa_agent_evidence" to "authenticated";

grant select on table "public"."qa_agent_evidence" to "authenticated";

grant trigger on table "public"."qa_agent_evidence" to "authenticated";

grant truncate on table "public"."qa_agent_evidence" to "authenticated";

grant update on table "public"."qa_agent_evidence" to "authenticated";

grant delete on table "public"."qa_agent_evidence" to "service_role";

grant insert on table "public"."qa_agent_evidence" to "service_role";

grant references on table "public"."qa_agent_evidence" to "service_role";

grant select on table "public"."qa_agent_evidence" to "service_role";

grant trigger on table "public"."qa_agent_evidence" to "service_role";

grant truncate on table "public"."qa_agent_evidence" to "service_role";

grant update on table "public"."qa_agent_evidence" to "service_role";

grant delete on table "public"."qa_agent_findings" to "authenticated";

grant insert on table "public"."qa_agent_findings" to "authenticated";

grant references on table "public"."qa_agent_findings" to "authenticated";

grant select on table "public"."qa_agent_findings" to "authenticated";

grant trigger on table "public"."qa_agent_findings" to "authenticated";

grant truncate on table "public"."qa_agent_findings" to "authenticated";

grant update on table "public"."qa_agent_findings" to "authenticated";

grant delete on table "public"."qa_agent_findings" to "service_role";

grant insert on table "public"."qa_agent_findings" to "service_role";

grant references on table "public"."qa_agent_findings" to "service_role";

grant select on table "public"."qa_agent_findings" to "service_role";

grant trigger on table "public"."qa_agent_findings" to "service_role";

grant truncate on table "public"."qa_agent_findings" to "service_role";

grant update on table "public"."qa_agent_findings" to "service_role";

grant delete on table "public"."qa_agent_rules" to "authenticated";

grant insert on table "public"."qa_agent_rules" to "authenticated";

grant references on table "public"."qa_agent_rules" to "authenticated";

grant select on table "public"."qa_agent_rules" to "authenticated";

grant trigger on table "public"."qa_agent_rules" to "authenticated";

grant truncate on table "public"."qa_agent_rules" to "authenticated";

grant update on table "public"."qa_agent_rules" to "authenticated";

grant delete on table "public"."qa_agent_rules" to "service_role";

grant insert on table "public"."qa_agent_rules" to "service_role";

grant references on table "public"."qa_agent_rules" to "service_role";

grant select on table "public"."qa_agent_rules" to "service_role";

grant trigger on table "public"."qa_agent_rules" to "service_role";

grant truncate on table "public"."qa_agent_rules" to "service_role";

grant update on table "public"."qa_agent_rules" to "service_role";

grant delete on table "public"."qa_agent_runs" to "authenticated";

grant insert on table "public"."qa_agent_runs" to "authenticated";

grant references on table "public"."qa_agent_runs" to "authenticated";

grant select on table "public"."qa_agent_runs" to "authenticated";

grant trigger on table "public"."qa_agent_runs" to "authenticated";

grant truncate on table "public"."qa_agent_runs" to "authenticated";

grant update on table "public"."qa_agent_runs" to "authenticated";

grant delete on table "public"."qa_agent_runs" to "service_role";

grant insert on table "public"."qa_agent_runs" to "service_role";

grant references on table "public"."qa_agent_runs" to "service_role";

grant select on table "public"."qa_agent_runs" to "service_role";

grant trigger on table "public"."qa_agent_runs" to "service_role";

grant truncate on table "public"."qa_agent_runs" to "service_role";

grant update on table "public"."qa_agent_runs" to "service_role";

grant delete on table "public"."qa_daily_reports" to "authenticated";

grant insert on table "public"."qa_daily_reports" to "authenticated";

grant references on table "public"."qa_daily_reports" to "authenticated";

grant select on table "public"."qa_daily_reports" to "authenticated";

grant trigger on table "public"."qa_daily_reports" to "authenticated";

grant truncate on table "public"."qa_daily_reports" to "authenticated";

grant update on table "public"."qa_daily_reports" to "authenticated";

grant delete on table "public"."qa_daily_reports" to "service_role";

grant insert on table "public"."qa_daily_reports" to "service_role";

grant references on table "public"."qa_daily_reports" to "service_role";

grant select on table "public"."qa_daily_reports" to "service_role";

grant trigger on table "public"."qa_daily_reports" to "service_role";

grant truncate on table "public"."qa_daily_reports" to "service_role";

grant update on table "public"."qa_daily_reports" to "service_role";

grant delete on table "public"."qa_health_metrics" to "authenticated";

grant insert on table "public"."qa_health_metrics" to "authenticated";

grant references on table "public"."qa_health_metrics" to "authenticated";

grant select on table "public"."qa_health_metrics" to "authenticated";

grant trigger on table "public"."qa_health_metrics" to "authenticated";

grant truncate on table "public"."qa_health_metrics" to "authenticated";

grant update on table "public"."qa_health_metrics" to "authenticated";

grant delete on table "public"."qa_health_metrics" to "service_role";

grant insert on table "public"."qa_health_metrics" to "service_role";

grant references on table "public"."qa_health_metrics" to "service_role";

grant select on table "public"."qa_health_metrics" to "service_role";

grant trigger on table "public"."qa_health_metrics" to "service_role";

grant truncate on table "public"."qa_health_metrics" to "service_role";

grant update on table "public"."qa_health_metrics" to "service_role";

grant delete on table "public"."qa_notifications" to "authenticated";

grant insert on table "public"."qa_notifications" to "authenticated";

grant references on table "public"."qa_notifications" to "authenticated";

grant select on table "public"."qa_notifications" to "authenticated";

grant trigger on table "public"."qa_notifications" to "authenticated";

grant truncate on table "public"."qa_notifications" to "authenticated";

grant update on table "public"."qa_notifications" to "authenticated";

grant delete on table "public"."qa_notifications" to "service_role";

grant insert on table "public"."qa_notifications" to "service_role";

grant references on table "public"."qa_notifications" to "service_role";

grant select on table "public"."qa_notifications" to "service_role";

grant trigger on table "public"."qa_notifications" to "service_role";

grant truncate on table "public"."qa_notifications" to "service_role";

grant update on table "public"."qa_notifications" to "service_role";

grant delete on table "public"."qa_run_queue" to "authenticated";

grant insert on table "public"."qa_run_queue" to "authenticated";

grant references on table "public"."qa_run_queue" to "authenticated";

grant select on table "public"."qa_run_queue" to "authenticated";

grant trigger on table "public"."qa_run_queue" to "authenticated";

grant truncate on table "public"."qa_run_queue" to "authenticated";

grant update on table "public"."qa_run_queue" to "authenticated";

grant delete on table "public"."qa_run_queue" to "service_role";

grant insert on table "public"."qa_run_queue" to "service_role";

grant references on table "public"."qa_run_queue" to "service_role";

grant select on table "public"."qa_run_queue" to "service_role";

grant trigger on table "public"."qa_run_queue" to "service_role";

grant truncate on table "public"."qa_run_queue" to "service_role";

grant update on table "public"."qa_run_queue" to "service_role";

grant delete on table "public"."qa_schedules" to "authenticated";

grant insert on table "public"."qa_schedules" to "authenticated";

grant references on table "public"."qa_schedules" to "authenticated";

grant select on table "public"."qa_schedules" to "authenticated";

grant trigger on table "public"."qa_schedules" to "authenticated";

grant truncate on table "public"."qa_schedules" to "authenticated";

grant update on table "public"."qa_schedules" to "authenticated";

grant delete on table "public"."qa_schedules" to "service_role";

grant insert on table "public"."qa_schedules" to "service_role";

grant references on table "public"."qa_schedules" to "service_role";

grant select on table "public"."qa_schedules" to "service_role";

grant trigger on table "public"."qa_schedules" to "service_role";

grant truncate on table "public"."qa_schedules" to "service_role";

grant update on table "public"."qa_schedules" to "service_role";

grant delete on table "public"."ref_locations" to "authenticated";

grant insert on table "public"."ref_locations" to "authenticated";

grant references on table "public"."ref_locations" to "authenticated";

grant select on table "public"."ref_locations" to "authenticated";

grant trigger on table "public"."ref_locations" to "authenticated";

grant truncate on table "public"."ref_locations" to "authenticated";

grant update on table "public"."ref_locations" to "authenticated";

grant delete on table "public"."ref_locations" to "service_role";

grant insert on table "public"."ref_locations" to "service_role";

grant references on table "public"."ref_locations" to "service_role";

grant select on table "public"."ref_locations" to "service_role";

grant trigger on table "public"."ref_locations" to "service_role";

grant truncate on table "public"."ref_locations" to "service_role";

grant update on table "public"."ref_locations" to "service_role";

grant delete on table "public"."remote_tasks" to "authenticated";

grant insert on table "public"."remote_tasks" to "authenticated";

grant references on table "public"."remote_tasks" to "authenticated";

grant select on table "public"."remote_tasks" to "authenticated";

grant trigger on table "public"."remote_tasks" to "authenticated";

grant truncate on table "public"."remote_tasks" to "authenticated";

grant update on table "public"."remote_tasks" to "authenticated";

grant delete on table "public"."remote_tasks" to "service_role";

grant insert on table "public"."remote_tasks" to "service_role";

grant references on table "public"."remote_tasks" to "service_role";

grant select on table "public"."remote_tasks" to "service_role";

grant trigger on table "public"."remote_tasks" to "service_role";

grant truncate on table "public"."remote_tasks" to "service_role";

grant update on table "public"."remote_tasks" to "service_role";

grant delete on table "public"."roles" to "authenticated";

grant insert on table "public"."roles" to "authenticated";

grant references on table "public"."roles" to "authenticated";

grant select on table "public"."roles" to "authenticated";

grant trigger on table "public"."roles" to "authenticated";

grant truncate on table "public"."roles" to "authenticated";

grant update on table "public"."roles" to "authenticated";

grant delete on table "public"."roles" to "service_role";

grant insert on table "public"."roles" to "service_role";

grant references on table "public"."roles" to "service_role";

grant select on table "public"."roles" to "service_role";

grant trigger on table "public"."roles" to "service_role";

grant truncate on table "public"."roles" to "service_role";

grant update on table "public"."roles" to "service_role";

grant delete on table "public"."roving_assignments" to "authenticated";

grant insert on table "public"."roving_assignments" to "authenticated";

grant references on table "public"."roving_assignments" to "authenticated";

grant select on table "public"."roving_assignments" to "authenticated";

grant trigger on table "public"."roving_assignments" to "authenticated";

grant truncate on table "public"."roving_assignments" to "authenticated";

grant update on table "public"."roving_assignments" to "authenticated";

grant delete on table "public"."roving_assignments" to "service_role";

grant insert on table "public"."roving_assignments" to "service_role";

grant references on table "public"."roving_assignments" to "service_role";

grant select on table "public"."roving_assignments" to "service_role";

grant trigger on table "public"."roving_assignments" to "service_role";

grant truncate on table "public"."roving_assignments" to "service_role";

grant update on table "public"."roving_assignments" to "service_role";

grant delete on table "public"."security_events" to "authenticated";

grant insert on table "public"."security_events" to "authenticated";

grant references on table "public"."security_events" to "authenticated";

grant select on table "public"."security_events" to "authenticated";

grant trigger on table "public"."security_events" to "authenticated";

grant truncate on table "public"."security_events" to "authenticated";

grant update on table "public"."security_events" to "authenticated";

grant delete on table "public"."security_events" to "service_role";

grant insert on table "public"."security_events" to "service_role";

grant references on table "public"."security_events" to "service_role";

grant select on table "public"."security_events" to "service_role";

grant trigger on table "public"."security_events" to "service_role";

grant truncate on table "public"."security_events" to "service_role";

grant update on table "public"."security_events" to "service_role";

grant delete on table "public"."sla_breach_logs" to "authenticated";

grant insert on table "public"."sla_breach_logs" to "authenticated";

grant references on table "public"."sla_breach_logs" to "authenticated";

grant select on table "public"."sla_breach_logs" to "authenticated";

grant trigger on table "public"."sla_breach_logs" to "authenticated";

grant truncate on table "public"."sla_breach_logs" to "authenticated";

grant update on table "public"."sla_breach_logs" to "authenticated";

grant delete on table "public"."sla_breach_logs" to "service_role";

grant insert on table "public"."sla_breach_logs" to "service_role";

grant references on table "public"."sla_breach_logs" to "service_role";

grant select on table "public"."sla_breach_logs" to "service_role";

grant trigger on table "public"."sla_breach_logs" to "service_role";

grant truncate on table "public"."sla_breach_logs" to "service_role";

grant update on table "public"."sla_breach_logs" to "service_role";

grant delete on table "public"."staging_imports" to "authenticated";

grant insert on table "public"."staging_imports" to "authenticated";

grant references on table "public"."staging_imports" to "authenticated";

grant select on table "public"."staging_imports" to "authenticated";

grant trigger on table "public"."staging_imports" to "authenticated";

grant truncate on table "public"."staging_imports" to "authenticated";

grant update on table "public"."staging_imports" to "authenticated";

grant delete on table "public"."staging_imports" to "service_role";

grant insert on table "public"."staging_imports" to "service_role";

grant references on table "public"."staging_imports" to "service_role";

grant select on table "public"."staging_imports" to "service_role";

grant trigger on table "public"."staging_imports" to "service_role";

grant truncate on table "public"."staging_imports" to "service_role";

grant update on table "public"."staging_imports" to "service_role";

grant delete on table "public"."store_import_batches" to "authenticated";

grant insert on table "public"."store_import_batches" to "authenticated";

grant references on table "public"."store_import_batches" to "authenticated";

grant select on table "public"."store_import_batches" to "authenticated";

grant trigger on table "public"."store_import_batches" to "authenticated";

grant truncate on table "public"."store_import_batches" to "authenticated";

grant update on table "public"."store_import_batches" to "authenticated";

grant delete on table "public"."store_import_batches" to "service_role";

grant insert on table "public"."store_import_batches" to "service_role";

grant references on table "public"."store_import_batches" to "service_role";

grant select on table "public"."store_import_batches" to "service_role";

grant trigger on table "public"."store_import_batches" to "service_role";

grant truncate on table "public"."store_import_batches" to "service_role";

grant update on table "public"."store_import_batches" to "service_role";

grant delete on table "public"."store_import_rows" to "authenticated";

grant insert on table "public"."store_import_rows" to "authenticated";

grant references on table "public"."store_import_rows" to "authenticated";

grant select on table "public"."store_import_rows" to "authenticated";

grant trigger on table "public"."store_import_rows" to "authenticated";

grant truncate on table "public"."store_import_rows" to "authenticated";

grant update on table "public"."store_import_rows" to "authenticated";

grant delete on table "public"."store_import_rows" to "service_role";

grant insert on table "public"."store_import_rows" to "service_role";

grant references on table "public"."store_import_rows" to "service_role";

grant select on table "public"."store_import_rows" to "service_role";

grant trigger on table "public"."store_import_rows" to "service_role";

grant truncate on table "public"."store_import_rows" to "service_role";

grant update on table "public"."store_import_rows" to "service_role";

grant delete on table "public"."stores" to "authenticated";

grant insert on table "public"."stores" to "authenticated";

grant references on table "public"."stores" to "authenticated";

grant select on table "public"."stores" to "authenticated";

grant trigger on table "public"."stores" to "authenticated";

grant truncate on table "public"."stores" to "authenticated";

grant update on table "public"."stores" to "authenticated";

grant delete on table "public"."stores" to "service_role";

grant insert on table "public"."stores" to "service_role";

grant references on table "public"."stores" to "service_role";

grant select on table "public"."stores" to "service_role";

grant trigger on table "public"."stores" to "service_role";

grant truncate on table "public"."stores" to "service_role";

grant update on table "public"."stores" to "service_role";

grant delete on table "public"."temp_approval_access" to "authenticated";

grant insert on table "public"."temp_approval_access" to "authenticated";

grant references on table "public"."temp_approval_access" to "authenticated";

grant select on table "public"."temp_approval_access" to "authenticated";

grant trigger on table "public"."temp_approval_access" to "authenticated";

grant truncate on table "public"."temp_approval_access" to "authenticated";

grant update on table "public"."temp_approval_access" to "authenticated";

grant delete on table "public"."temp_approval_access" to "service_role";

grant insert on table "public"."temp_approval_access" to "service_role";

grant references on table "public"."temp_approval_access" to "service_role";

grant select on table "public"."temp_approval_access" to "service_role";

grant trigger on table "public"."temp_approval_access" to "service_role";

grant truncate on table "public"."temp_approval_access" to "service_role";

grant update on table "public"."temp_approval_access" to "service_role";

grant delete on table "public"."temp_permission_overrides" to "authenticated";

grant insert on table "public"."temp_permission_overrides" to "authenticated";

grant references on table "public"."temp_permission_overrides" to "authenticated";

grant select on table "public"."temp_permission_overrides" to "authenticated";

grant trigger on table "public"."temp_permission_overrides" to "authenticated";

grant truncate on table "public"."temp_permission_overrides" to "authenticated";

grant update on table "public"."temp_permission_overrides" to "authenticated";

grant delete on table "public"."temp_permission_overrides" to "service_role";

grant insert on table "public"."temp_permission_overrides" to "service_role";

grant references on table "public"."temp_permission_overrides" to "service_role";

grant select on table "public"."temp_permission_overrides" to "service_role";

grant trigger on table "public"."temp_permission_overrides" to "service_role";

grant truncate on table "public"."temp_permission_overrides" to "service_role";

grant update on table "public"."temp_permission_overrides" to "service_role";

grant delete on table "public"."user_account_transfers" to "authenticated";

grant insert on table "public"."user_account_transfers" to "authenticated";

grant references on table "public"."user_account_transfers" to "authenticated";

grant select on table "public"."user_account_transfers" to "authenticated";

grant trigger on table "public"."user_account_transfers" to "authenticated";

grant truncate on table "public"."user_account_transfers" to "authenticated";

grant update on table "public"."user_account_transfers" to "authenticated";

grant delete on table "public"."user_account_transfers" to "service_role";

grant insert on table "public"."user_account_transfers" to "service_role";

grant references on table "public"."user_account_transfers" to "service_role";

grant select on table "public"."user_account_transfers" to "service_role";

grant trigger on table "public"."user_account_transfers" to "service_role";

grant truncate on table "public"."user_account_transfers" to "service_role";

grant update on table "public"."user_account_transfers" to "service_role";

grant delete on table "public"."user_scopes" to "authenticated";

grant insert on table "public"."user_scopes" to "authenticated";

grant references on table "public"."user_scopes" to "authenticated";

grant select on table "public"."user_scopes" to "authenticated";

grant trigger on table "public"."user_scopes" to "authenticated";

grant truncate on table "public"."user_scopes" to "authenticated";

grant update on table "public"."user_scopes" to "authenticated";

grant delete on table "public"."user_scopes" to "service_role";

grant insert on table "public"."user_scopes" to "service_role";

grant references on table "public"."user_scopes" to "service_role";

grant select on table "public"."user_scopes" to "service_role";

grant trigger on table "public"."user_scopes" to "service_role";

grant truncate on table "public"."user_scopes" to "service_role";

grant update on table "public"."user_scopes" to "service_role";

grant delete on table "public"."users_profile" to "authenticated";

grant insert on table "public"."users_profile" to "authenticated";

grant references on table "public"."users_profile" to "authenticated";

grant select on table "public"."users_profile" to "authenticated";

grant trigger on table "public"."users_profile" to "authenticated";

grant truncate on table "public"."users_profile" to "authenticated";

grant update on table "public"."users_profile" to "authenticated";

grant delete on table "public"."users_profile" to "service_role";

grant insert on table "public"."users_profile" to "service_role";

grant references on table "public"."users_profile" to "service_role";

grant select on table "public"."users_profile" to "service_role";

grant trigger on table "public"."users_profile" to "service_role";

grant truncate on table "public"."users_profile" to "service_role";

grant update on table "public"."users_profile" to "service_role";

grant delete on table "public"."vacancies" to "authenticated";

grant insert on table "public"."vacancies" to "authenticated";

grant references on table "public"."vacancies" to "authenticated";

grant select on table "public"."vacancies" to "authenticated";

grant trigger on table "public"."vacancies" to "authenticated";

grant truncate on table "public"."vacancies" to "authenticated";

grant update on table "public"."vacancies" to "authenticated";

grant delete on table "public"."vacancies" to "service_role";

grant insert on table "public"."vacancies" to "service_role";

grant references on table "public"."vacancies" to "service_role";

grant select on table "public"."vacancies" to "service_role";

grant trigger on table "public"."vacancies" to "service_role";

grant truncate on table "public"."vacancies" to "service_role";

grant update on table "public"."vacancies" to "service_role";

grant delete on table "public"."vacancy_closure_reasons" to "authenticated";

grant insert on table "public"."vacancy_closure_reasons" to "authenticated";

grant references on table "public"."vacancy_closure_reasons" to "authenticated";

grant select on table "public"."vacancy_closure_reasons" to "authenticated";

grant trigger on table "public"."vacancy_closure_reasons" to "authenticated";

grant truncate on table "public"."vacancy_closure_reasons" to "authenticated";

grant update on table "public"."vacancy_closure_reasons" to "authenticated";

grant delete on table "public"."vacancy_closure_reasons" to "service_role";

grant insert on table "public"."vacancy_closure_reasons" to "service_role";

grant references on table "public"."vacancy_closure_reasons" to "service_role";

grant select on table "public"."vacancy_closure_reasons" to "service_role";

grant trigger on table "public"."vacancy_closure_reasons" to "service_role";

grant truncate on table "public"."vacancy_closure_reasons" to "service_role";

grant update on table "public"."vacancy_closure_reasons" to "service_role";

grant delete on table "public"."vacancy_closure_requests" to "authenticated";

grant insert on table "public"."vacancy_closure_requests" to "authenticated";

grant references on table "public"."vacancy_closure_requests" to "authenticated";

grant select on table "public"."vacancy_closure_requests" to "authenticated";

grant trigger on table "public"."vacancy_closure_requests" to "authenticated";

grant truncate on table "public"."vacancy_closure_requests" to "authenticated";

grant update on table "public"."vacancy_closure_requests" to "authenticated";

grant delete on table "public"."vacancy_closure_requests" to "service_role";

grant insert on table "public"."vacancy_closure_requests" to "service_role";

grant references on table "public"."vacancy_closure_requests" to "service_role";

grant select on table "public"."vacancy_closure_requests" to "service_role";

grant trigger on table "public"."vacancy_closure_requests" to "service_role";

grant truncate on table "public"."vacancy_closure_requests" to "service_role";

grant update on table "public"."vacancy_closure_requests" to "service_role";

grant delete on table "public"."vacancy_coverage" to "authenticated";

grant insert on table "public"."vacancy_coverage" to "authenticated";

grant references on table "public"."vacancy_coverage" to "authenticated";

grant select on table "public"."vacancy_coverage" to "authenticated";

grant trigger on table "public"."vacancy_coverage" to "authenticated";

grant truncate on table "public"."vacancy_coverage" to "authenticated";

grant update on table "public"."vacancy_coverage" to "authenticated";

grant delete on table "public"."vacancy_coverage" to "service_role";

grant insert on table "public"."vacancy_coverage" to "service_role";

grant references on table "public"."vacancy_coverage" to "service_role";

grant select on table "public"."vacancy_coverage" to "service_role";

grant trigger on table "public"."vacancy_coverage" to "service_role";

grant truncate on table "public"."vacancy_coverage" to "service_role";

grant update on table "public"."vacancy_coverage" to "service_role";

grant delete on table "public"."vacancy_requests" to "authenticated";

grant insert on table "public"."vacancy_requests" to "authenticated";

grant references on table "public"."vacancy_requests" to "authenticated";

grant select on table "public"."vacancy_requests" to "authenticated";

grant trigger on table "public"."vacancy_requests" to "authenticated";

grant truncate on table "public"."vacancy_requests" to "authenticated";

grant update on table "public"."vacancy_requests" to "authenticated";

grant delete on table "public"."vacancy_requests" to "service_role";

grant insert on table "public"."vacancy_requests" to "service_role";

grant references on table "public"."vacancy_requests" to "service_role";

grant select on table "public"."vacancy_requests" to "service_role";

grant trigger on table "public"."vacancy_requests" to "service_role";

grant truncate on table "public"."vacancy_requests" to "service_role";

grant update on table "public"."vacancy_requests" to "service_role";

grant delete on table "public"."vcode_sequences" to "authenticated";

grant insert on table "public"."vcode_sequences" to "authenticated";

grant references on table "public"."vcode_sequences" to "authenticated";

grant select on table "public"."vcode_sequences" to "authenticated";

grant trigger on table "public"."vcode_sequences" to "authenticated";

grant truncate on table "public"."vcode_sequences" to "authenticated";

grant update on table "public"."vcode_sequences" to "authenticated";

grant delete on table "public"."vcode_sequences" to "service_role";

grant insert on table "public"."vcode_sequences" to "service_role";

grant references on table "public"."vcode_sequences" to "service_role";

grant select on table "public"."vcode_sequences" to "service_role";

grant trigger on table "public"."vcode_sequences" to "service_role";

grant truncate on table "public"."vcode_sequences" to "service_role";

grant update on table "public"."vcode_sequences" to "service_role";

grant delete on table "public"."vcodes" to "authenticated";

grant insert on table "public"."vcodes" to "authenticated";

grant references on table "public"."vcodes" to "authenticated";

grant select on table "public"."vcodes" to "authenticated";

grant trigger on table "public"."vcodes" to "authenticated";

grant truncate on table "public"."vcodes" to "authenticated";

grant update on table "public"."vcodes" to "authenticated";

grant delete on table "public"."vcodes" to "service_role";

grant insert on table "public"."vcodes" to "service_role";

grant references on table "public"."vcodes" to "service_role";

grant select on table "public"."vcodes" to "service_role";

grant trigger on table "public"."vcodes" to "service_role";

grant truncate on table "public"."vcodes" to "service_role";

grant update on table "public"."vcodes" to "service_role";

grant delete on table "public"."workforce_assignment_requests" to "authenticated";

grant insert on table "public"."workforce_assignment_requests" to "authenticated";

grant references on table "public"."workforce_assignment_requests" to "authenticated";

grant select on table "public"."workforce_assignment_requests" to "authenticated";

grant trigger on table "public"."workforce_assignment_requests" to "authenticated";

grant truncate on table "public"."workforce_assignment_requests" to "authenticated";

grant update on table "public"."workforce_assignment_requests" to "authenticated";

grant delete on table "public"."workforce_assignment_requests" to "service_role";

grant insert on table "public"."workforce_assignment_requests" to "service_role";

grant references on table "public"."workforce_assignment_requests" to "service_role";

grant select on table "public"."workforce_assignment_requests" to "service_role";

grant trigger on table "public"."workforce_assignment_requests" to "service_role";

grant truncate on table "public"."workforce_assignment_requests" to "service_role";

grant update on table "public"."workforce_assignment_requests" to "service_role";

grant delete on table "public"."workforce_assignments" to "authenticated";

grant insert on table "public"."workforce_assignments" to "authenticated";

grant references on table "public"."workforce_assignments" to "authenticated";

grant select on table "public"."workforce_assignments" to "authenticated";

grant trigger on table "public"."workforce_assignments" to "authenticated";

grant truncate on table "public"."workforce_assignments" to "authenticated";

grant update on table "public"."workforce_assignments" to "authenticated";

grant delete on table "public"."workforce_assignments" to "service_role";

grant insert on table "public"."workforce_assignments" to "service_role";

grant references on table "public"."workforce_assignments" to "service_role";

grant select on table "public"."workforce_assignments" to "service_role";

grant trigger on table "public"."workforce_assignments" to "service_role";

grant truncate on table "public"."workforce_assignments" to "service_role";

grant update on table "public"."workforce_assignments" to "service_role";

grant delete on table "public"."workforce_pool_conversion_requests" to "authenticated";

grant insert on table "public"."workforce_pool_conversion_requests" to "authenticated";

grant references on table "public"."workforce_pool_conversion_requests" to "authenticated";

grant select on table "public"."workforce_pool_conversion_requests" to "authenticated";

grant trigger on table "public"."workforce_pool_conversion_requests" to "authenticated";

grant truncate on table "public"."workforce_pool_conversion_requests" to "authenticated";

grant update on table "public"."workforce_pool_conversion_requests" to "authenticated";

grant delete on table "public"."workforce_pool_conversion_requests" to "service_role";

grant insert on table "public"."workforce_pool_conversion_requests" to "service_role";

grant references on table "public"."workforce_pool_conversion_requests" to "service_role";

grant select on table "public"."workforce_pool_conversion_requests" to "service_role";

grant trigger on table "public"."workforce_pool_conversion_requests" to "service_role";

grant truncate on table "public"."workforce_pool_conversion_requests" to "service_role";

grant update on table "public"."workforce_pool_conversion_requests" to "service_role";

grant delete on table "public"."workforce_pool_request_items" to "authenticated";

grant insert on table "public"."workforce_pool_request_items" to "authenticated";

grant references on table "public"."workforce_pool_request_items" to "authenticated";

grant select on table "public"."workforce_pool_request_items" to "authenticated";

grant trigger on table "public"."workforce_pool_request_items" to "authenticated";

grant truncate on table "public"."workforce_pool_request_items" to "authenticated";

grant update on table "public"."workforce_pool_request_items" to "authenticated";

grant delete on table "public"."workforce_pool_request_items" to "service_role";

grant insert on table "public"."workforce_pool_request_items" to "service_role";

grant references on table "public"."workforce_pool_request_items" to "service_role";

grant select on table "public"."workforce_pool_request_items" to "service_role";

grant trigger on table "public"."workforce_pool_request_items" to "service_role";

grant truncate on table "public"."workforce_pool_request_items" to "service_role";

grant update on table "public"."workforce_pool_request_items" to "service_role";

grant delete on table "public"."workforce_pool_requests" to "authenticated";

grant insert on table "public"."workforce_pool_requests" to "authenticated";

grant references on table "public"."workforce_pool_requests" to "authenticated";

grant select on table "public"."workforce_pool_requests" to "authenticated";

grant trigger on table "public"."workforce_pool_requests" to "authenticated";

grant truncate on table "public"."workforce_pool_requests" to "authenticated";

grant update on table "public"."workforce_pool_requests" to "authenticated";

grant delete on table "public"."workforce_pool_requests" to "service_role";

grant insert on table "public"."workforce_pool_requests" to "service_role";

grant references on table "public"."workforce_pool_requests" to "service_role";

grant select on table "public"."workforce_pool_requests" to "service_role";

grant trigger on table "public"."workforce_pool_requests" to "service_role";

grant truncate on table "public"."workforce_pool_requests" to "service_role";

grant update on table "public"."workforce_pool_requests" to "service_role";

grant delete on table "public"."workforce_pool_slots" to "authenticated";

grant insert on table "public"."workforce_pool_slots" to "authenticated";

grant references on table "public"."workforce_pool_slots" to "authenticated";

grant select on table "public"."workforce_pool_slots" to "authenticated";

grant trigger on table "public"."workforce_pool_slots" to "authenticated";

grant truncate on table "public"."workforce_pool_slots" to "authenticated";

grant update on table "public"."workforce_pool_slots" to "authenticated";

grant delete on table "public"."workforce_pool_slots" to "service_role";

grant insert on table "public"."workforce_pool_slots" to "service_role";

grant references on table "public"."workforce_pool_slots" to "service_role";

grant select on table "public"."workforce_pool_slots" to "service_role";

grant trigger on table "public"."workforce_pool_slots" to "service_role";

grant truncate on table "public"."workforce_pool_slots" to "service_role";

grant update on table "public"."workforce_pool_slots" to "service_role";

grant delete on table "public"."workforce_pool_types" to "authenticated";

grant insert on table "public"."workforce_pool_types" to "authenticated";

grant references on table "public"."workforce_pool_types" to "authenticated";

grant select on table "public"."workforce_pool_types" to "authenticated";

grant trigger on table "public"."workforce_pool_types" to "authenticated";

grant truncate on table "public"."workforce_pool_types" to "authenticated";

grant update on table "public"."workforce_pool_types" to "authenticated";

grant delete on table "public"."workforce_pool_types" to "service_role";

grant insert on table "public"."workforce_pool_types" to "service_role";

grant references on table "public"."workforce_pool_types" to "service_role";

grant select on table "public"."workforce_pool_types" to "service_role";

grant trigger on table "public"."workforce_pool_types" to "service_role";

grant truncate on table "public"."workforce_pool_types" to "service_role";

grant update on table "public"."workforce_pool_types" to "service_role";

grant delete on table "public"."workforce_pool_vcode_sequences" to "authenticated";

grant insert on table "public"."workforce_pool_vcode_sequences" to "authenticated";

grant references on table "public"."workforce_pool_vcode_sequences" to "authenticated";

grant select on table "public"."workforce_pool_vcode_sequences" to "authenticated";

grant trigger on table "public"."workforce_pool_vcode_sequences" to "authenticated";

grant truncate on table "public"."workforce_pool_vcode_sequences" to "authenticated";

grant update on table "public"."workforce_pool_vcode_sequences" to "authenticated";

grant delete on table "public"."workforce_pool_vcode_sequences" to "service_role";

grant insert on table "public"."workforce_pool_vcode_sequences" to "service_role";

grant references on table "public"."workforce_pool_vcode_sequences" to "service_role";

grant select on table "public"."workforce_pool_vcode_sequences" to "service_role";

grant trigger on table "public"."workforce_pool_vcode_sequences" to "service_role";

grant truncate on table "public"."workforce_pool_vcode_sequences" to "service_role";

grant update on table "public"."workforce_pool_vcode_sequences" to "service_role";

grant delete on table "public"."workforce_slot_reviews" to "authenticated";

grant insert on table "public"."workforce_slot_reviews" to "authenticated";

grant references on table "public"."workforce_slot_reviews" to "authenticated";

grant select on table "public"."workforce_slot_reviews" to "authenticated";

grant trigger on table "public"."workforce_slot_reviews" to "authenticated";

grant truncate on table "public"."workforce_slot_reviews" to "authenticated";

grant update on table "public"."workforce_slot_reviews" to "authenticated";

grant delete on table "public"."workforce_slot_reviews" to "service_role";

grant insert on table "public"."workforce_slot_reviews" to "service_role";

grant references on table "public"."workforce_slot_reviews" to "service_role";

grant select on table "public"."workforce_slot_reviews" to "service_role";

grant trigger on table "public"."workforce_slot_reviews" to "service_role";

grant truncate on table "public"."workforce_slot_reviews" to "service_role";

grant update on table "public"."workforce_slot_reviews" to "service_role";


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



  create policy "ar_select_own"
  on "public"."account_requests"
  as permissive
  for select
  to authenticated
using ((auth_user_id = auth.uid()));



  create policy "accounts_read_all"
  on "public"."accounts"
  as permissive
  for select
  to public
using ((is_active = true));



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



  create policy "audit_log_insert"
  on "public"."activity_log"
  as permissive
  for insert
  to public
with check ((auth.role() = 'authenticated'::text));



  create policy "audit_log_select"
  on "public"."activity_log"
  as permissive
  for select
  to public
using (public.i_have_full_access());



  create policy "applicants_delete_blocked"
  on "public"."applicants"
  as permissive
  for delete
  to public
using (false);



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



  create policy "audit_logs_block_delete"
  on "public"."audit_logs"
  as permissive
  for delete
  to authenticated
using (false);



  create policy "audit_logs_block_insert"
  on "public"."audit_logs"
  as permissive
  for insert
  to authenticated
with check (false);



  create policy "audit_logs_block_update"
  on "public"."audit_logs"
  as permissive
  for update
  to authenticated
using (false)
with check (false);



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



  create policy "backout_reasons_read_all"
  on "public"."backout_reasons"
  as permissive
  for select
  to authenticated
using ((is_active = true));



  create policy "backout_reasons_write_admin"
  on "public"."backout_reasons"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "bulk_items_delete_blocked"
  on "public"."bulk_emploc_items"
  as permissive
  for delete
  to public
using (false);



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



  create policy "bulk_uploads_delete_blocked"
  on "public"."bulk_emploc_uploads"
  as permissive
  for delete
  to public
using (false);



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



  create policy "deact_req_delete_blocked"
  on "public"."deactivation_requests"
  as permissive
  for delete
  to public
using (false);



  create policy "deact_req_insert_ops_only"
  on "public"."deactivation_requests"
  as permissive
  for insert
  to public
with check ((public.i_have_full_access() OR (public.i_am_ops() AND (requested_by = public.get_my_full_name()))));



  create policy "deact_req_update_blocked_direct"
  on "public"."deactivation_requests"
  as permissive
  for update
  to authenticated
using (false)
with check (false);



  create policy "deact_requests_read_scoped"
  on "public"."deactivation_requests"
  as permissive
  for select
  to authenticated
using ((public.i_have_full_access() OR (requested_by = public.get_my_full_name())));



  create policy "authenticated_can_read"
  on "public"."deployer"
  as permissive
  for select
  to authenticated
using (true);



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



  create policy "transfers_delete_blocked"
  on "public"."employee_transfers"
  as permissive
  for delete
  to public
using (false);



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



  create policy "transfers_update_blocked_direct"
  on "public"."employee_transfers"
  as permissive
  for update
  to authenticated
using (false)
with check (false);



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



  create policy "groups_read_all"
  on "public"."groups"
  as permissive
  for select
  to public
using (true);



  create policy "groups_write_admin"
  on "public"."groups"
  as permissive
  for all
  to public
using (public.i_have_full_access());



  create policy "hcreq_delete_blocked"
  on "public"."headcount_requests"
  as permissive
  for delete
  to public
using (false);



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



  create policy "hcreq_update_blocked_direct"
  on "public"."headcount_requests"
  as permissive
  for update
  to authenticated
using (false)
with check (false);



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



  create policy "deletion_req_delete_blocked"
  on "public"."hr_emploc_deletion_requests"
  as permissive
  for delete
  to public
using (false);



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



  create policy "issue_types_read_active"
  on "public"."hr_emploc_issue_types"
  as permissive
  for select
  to authenticated
using ((is_active = true));



  create policy "issue_types_write_admin"
  on "public"."hr_emploc_issue_types"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access())
with check (public.i_have_full_access());



  create policy "rejection_reasons_read_all"
  on "public"."hr_emploc_rejection_reasons"
  as permissive
  for select
  to authenticated
using ((is_active = true));



  create policy "rejection_reasons_write_admin"
  on "public"."hr_emploc_rejection_reasons"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "login_sessions_insert"
  on "public"."login_sessions"
  as permissive
  for insert
  to public
with check ((auth_uid = auth.uid()));



  create policy "login_sessions_no_delete"
  on "public"."login_sessions"
  as permissive
  for delete
  to public
using (false);



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



  create policy "notif_insert_system"
  on "public"."notifications"
  as permissive
  for insert
  to public
with check (true);



  create policy "notif_select_own"
  on "public"."notifications"
  as permissive
  for select
  to public
using (((recipient_user_id = auth.uid()) OR public.i_have_full_access()));



  create policy "notif_update_own"
  on "public"."notifications"
  as permissive
  for update
  to public
using ((recipient_user_id = auth.uid()));



  create policy "plantilla_delete_blocked"
  on "public"."plantilla"
  as permissive
  for delete
  to public
using (false);



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



  create policy "positions_read_all"
  on "public"."positions"
  as permissive
  for select
  to public
using ((is_active = true));



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



  create policy "qa_rules_read"
  on "public"."qa_agent_rules"
  as permissive
  for select
  to public
using (true);



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



  create policy "Authenticated users can read active locations"
  on "public"."ref_locations"
  as permissive
  for select
  to authenticated
using ((is_active = true));



  create policy "remote_tasks_admin_only"
  on "public"."remote_tasks"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "roles_read_authenticated"
  on "public"."roles"
  as permissive
  for select
  to authenticated
using (true);



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



  create policy "sla_breach_insert_service"
  on "public"."sla_breach_logs"
  as permissive
  for insert
  to public
with check (true);



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



  create policy "closure_reasons_read_all"
  on "public"."vacancy_closure_reasons"
  as permissive
  for select
  to authenticated
using ((is_active = true));



  create policy "closure_reasons_write_admin"
  on "public"."vacancy_closure_reasons"
  as permissive
  for all
  to authenticated
using (public.i_have_full_access());



  create policy "closure_req_delete_blocked"
  on "public"."vacancy_closure_requests"
  as permissive
  for delete
  to public
using (false);



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



  create policy "vreq_delete_blocked"
  on "public"."vacancy_requests"
  as permissive
  for delete
  to public
using (false);



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



  create policy "vreq_update_blocked_direct"
  on "public"."vacancy_requests"
  as permissive
  for update
  to authenticated
using (false)
with check (false);



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



  create policy "wf_pool_conversion_delete_blocked"
  on "public"."workforce_pool_conversion_requests"
  as permissive
  for delete
  to authenticated
using (false);



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



  create policy "wpt_read_all_authenticated"
  on "public"."workforce_pool_types"
  as permissive
  for select
  to authenticated
using ((is_active = true));



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

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();


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



