drop policy "war_ops_select" on "public"."workforce_assignment_requests";

drop policy "wa_read_scoped" on "public"."workforce_assignments";

-- skipped: revoke delete on table "public"."active_user_sessions" from "anon";

-- skipped: revoke insert on table "public"."active_user_sessions" from "anon";

-- skipped: revoke references on table "public"."active_user_sessions" from "anon";

-- skipped: revoke select on table "public"."active_user_sessions" from "anon";

-- skipped: revoke trigger on table "public"."active_user_sessions" from "anon";

-- skipped: revoke truncate on table "public"."active_user_sessions" from "anon";

-- skipped: revoke update on table "public"."active_user_sessions" from "anon";

revoke delete on table "public"."applicant_profile_edit_history" from "anon";

revoke insert on table "public"."applicant_profile_edit_history" from "anon";

revoke references on table "public"."applicant_profile_edit_history" from "anon";

revoke select on table "public"."applicant_profile_edit_history" from "anon";

revoke trigger on table "public"."applicant_profile_edit_history" from "anon";

revoke truncate on table "public"."applicant_profile_edit_history" from "anon";

revoke update on table "public"."applicant_profile_edit_history" from "anon";

-- skipped: revoke delete on table "public"."archival_audit_logs" from "anon";

-- skipped: revoke insert on table "public"."archival_audit_logs" from "anon";

-- skipped: revoke references on table "public"."archival_audit_logs" from "anon";

-- skipped: revoke select on table "public"."archival_audit_logs" from "anon";

-- skipped: revoke trigger on table "public"."archival_audit_logs" from "anon";

-- skipped: revoke truncate on table "public"."archival_audit_logs" from "anon";

-- skipped: revoke update on table "public"."archival_audit_logs" from "anon";

revoke references on table "public"."employee_deactivation_audit_log" from "anon";

revoke select on table "public"."employee_deactivation_audit_log" from "anon";

revoke trigger on table "public"."employee_deactivation_audit_log" from "anon";

revoke truncate on table "public"."employee_deactivation_audit_log" from "anon";

revoke references on table "public"."employee_deactivation_requests" from "anon";

revoke select on table "public"."employee_deactivation_requests" from "anon";

revoke trigger on table "public"."employee_deactivation_requests" from "anon";

revoke truncate on table "public"."employee_deactivation_requests" from "anon";

revoke references on table "public"."employee_import_batches" from "anon";

revoke select on table "public"."employee_import_batches" from "anon";

revoke trigger on table "public"."employee_import_batches" from "anon";

revoke truncate on table "public"."employee_import_batches" from "anon";

revoke references on table "public"."employee_import_rows" from "anon";

revoke select on table "public"."employee_import_rows" from "anon";

revoke trigger on table "public"."employee_import_rows" from "anon";

revoke truncate on table "public"."employee_import_rows" from "anon";

revoke references on table "public"."employee_store_allocations" from "anon";

revoke select on table "public"."employee_store_allocations" from "anon";

revoke trigger on table "public"."employee_store_allocations" from "anon";

revoke truncate on table "public"."employee_store_allocations" from "anon";

revoke references on table "public"."import_roving_groups" from "anon";

revoke select on table "public"."import_roving_groups" from "anon";

revoke trigger on table "public"."import_roving_groups" from "anon";

revoke truncate on table "public"."import_roving_groups" from "anon";

revoke delete on table "public"."notification_push_dispatches" from "anon";

revoke insert on table "public"."notification_push_dispatches" from "anon";

revoke references on table "public"."notification_push_dispatches" from "anon";

revoke select on table "public"."notification_push_dispatches" from "anon";

revoke trigger on table "public"."notification_push_dispatches" from "anon";

revoke truncate on table "public"."notification_push_dispatches" from "anon";

revoke update on table "public"."notification_push_dispatches" from "anon";

revoke delete on table "public"."permission_drift_evidence" from "anon";

revoke insert on table "public"."permission_drift_evidence" from "anon";

revoke references on table "public"."permission_drift_evidence" from "anon";

revoke select on table "public"."permission_drift_evidence" from "anon";

revoke trigger on table "public"."permission_drift_evidence" from "anon";

revoke truncate on table "public"."permission_drift_evidence" from "anon";

revoke update on table "public"."permission_drift_evidence" from "anon";

revoke delete on table "public"."permission_drift_findings" from "anon";

revoke insert on table "public"."permission_drift_findings" from "anon";

revoke references on table "public"."permission_drift_findings" from "anon";

revoke select on table "public"."permission_drift_findings" from "anon";

revoke trigger on table "public"."permission_drift_findings" from "anon";

revoke truncate on table "public"."permission_drift_findings" from "anon";

revoke update on table "public"."permission_drift_findings" from "anon";

revoke delete on table "public"."permission_drift_scan_runs" from "anon";

revoke insert on table "public"."permission_drift_scan_runs" from "anon";

revoke references on table "public"."permission_drift_scan_runs" from "anon";

revoke select on table "public"."permission_drift_scan_runs" from "anon";

revoke trigger on table "public"."permission_drift_scan_runs" from "anon";

revoke truncate on table "public"."permission_drift_scan_runs" from "anon";

revoke update on table "public"."permission_drift_scan_runs" from "anon";

revoke delete on table "public"."push_device_tokens" from "anon";

revoke insert on table "public"."push_device_tokens" from "anon";

revoke references on table "public"."push_device_tokens" from "anon";

revoke select on table "public"."push_device_tokens" from "anon";

revoke trigger on table "public"."push_device_tokens" from "anon";

revoke truncate on table "public"."push_device_tokens" from "anon";

revoke update on table "public"."push_device_tokens" from "anon";

revoke delete on table "public"."rbac_drift_scan_evidence" from "anon";

revoke insert on table "public"."rbac_drift_scan_evidence" from "anon";

revoke references on table "public"."rbac_drift_scan_evidence" from "anon";

revoke select on table "public"."rbac_drift_scan_evidence" from "anon";

revoke trigger on table "public"."rbac_drift_scan_evidence" from "anon";

revoke truncate on table "public"."rbac_drift_scan_evidence" from "anon";

revoke update on table "public"."rbac_drift_scan_evidence" from "anon";

revoke delete on table "public"."rbac_drift_scan_results" from "anon";

revoke insert on table "public"."rbac_drift_scan_results" from "anon";

revoke references on table "public"."rbac_drift_scan_results" from "anon";

revoke select on table "public"."rbac_drift_scan_results" from "anon";

revoke trigger on table "public"."rbac_drift_scan_results" from "anon";

revoke truncate on table "public"."rbac_drift_scan_results" from "anon";

revoke update on table "public"."rbac_drift_scan_results" from "anon";

revoke delete on table "public"."rbac_drift_scan_runs" from "anon";

revoke insert on table "public"."rbac_drift_scan_runs" from "anon";

revoke references on table "public"."rbac_drift_scan_runs" from "anon";

revoke select on table "public"."rbac_drift_scan_runs" from "anon";

revoke trigger on table "public"."rbac_drift_scan_runs" from "anon";

revoke truncate on table "public"."rbac_drift_scan_runs" from "anon";

revoke update on table "public"."rbac_drift_scan_runs" from "anon";

revoke delete on table "public"."rbac_drift_scanner_definitions" from "anon";

revoke insert on table "public"."rbac_drift_scanner_definitions" from "anon";

revoke references on table "public"."rbac_drift_scanner_definitions" from "anon";

revoke select on table "public"."rbac_drift_scanner_definitions" from "anon";

revoke trigger on table "public"."rbac_drift_scanner_definitions" from "anon";

revoke truncate on table "public"."rbac_drift_scanner_definitions" from "anon";

revoke update on table "public"."rbac_drift_scanner_definitions" from "anon";

revoke delete on table "public"."role_permission_audit_logs" from "anon";

revoke insert on table "public"."role_permission_audit_logs" from "anon";

revoke references on table "public"."role_permission_audit_logs" from "anon";

revoke select on table "public"."role_permission_audit_logs" from "anon";

revoke trigger on table "public"."role_permission_audit_logs" from "anon";

revoke truncate on table "public"."role_permission_audit_logs" from "anon";

revoke update on table "public"."role_permission_audit_logs" from "anon";

revoke delete on table "public"."role_permission_definitions" from "anon";

revoke insert on table "public"."role_permission_definitions" from "anon";

revoke references on table "public"."role_permission_definitions" from "anon";

revoke select on table "public"."role_permission_definitions" from "anon";

revoke trigger on table "public"."role_permission_definitions" from "anon";

revoke truncate on table "public"."role_permission_definitions" from "anon";

revoke update on table "public"."role_permission_definitions" from "anon";

revoke delete on table "public"."role_permission_matrix" from "anon";

revoke insert on table "public"."role_permission_matrix" from "anon";

revoke references on table "public"."role_permission_matrix" from "anon";

revoke select on table "public"."role_permission_matrix" from "anon";

revoke trigger on table "public"."role_permission_matrix" from "anon";

revoke truncate on table "public"."role_permission_matrix" from "anon";

revoke update on table "public"."role_permission_matrix" from "anon";

revoke delete on table "public"."security_audit_logs" from "anon";

revoke insert on table "public"."security_audit_logs" from "anon";

revoke references on table "public"."security_audit_logs" from "anon";

revoke select on table "public"."security_audit_logs" from "anon";

revoke trigger on table "public"."security_audit_logs" from "anon";

revoke truncate on table "public"."security_audit_logs" from "anon";

revoke update on table "public"."security_audit_logs" from "anon";

revoke delete on table "public"."user_settings" from "anon";

revoke insert on table "public"."user_settings" from "anon";

revoke references on table "public"."user_settings" from "anon";

revoke select on table "public"."user_settings" from "anon";

revoke trigger on table "public"."user_settings" from "anon";

revoke truncate on table "public"."user_settings" from "anon";

revoke update on table "public"."user_settings" from "anon";

revoke delete on table "public"."vacancy_edit_lock_audit" from "anon";

revoke insert on table "public"."vacancy_edit_lock_audit" from "anon";

revoke references on table "public"."vacancy_edit_lock_audit" from "anon";

revoke select on table "public"."vacancy_edit_lock_audit" from "anon";

revoke trigger on table "public"."vacancy_edit_lock_audit" from "anon";

revoke truncate on table "public"."vacancy_edit_lock_audit" from "anon";

revoke update on table "public"."vacancy_edit_lock_audit" from "anon";

revoke delete on table "public"."vacancy_edit_locks" from "anon";

revoke insert on table "public"."vacancy_edit_locks" from "anon";

revoke references on table "public"."vacancy_edit_locks" from "anon";

revoke select on table "public"."vacancy_edit_locks" from "anon";

revoke trigger on table "public"."vacancy_edit_locks" from "anon";

revoke truncate on table "public"."vacancy_edit_locks" from "anon";

revoke update on table "public"."vacancy_edit_locks" from "anon";

alter table "public"."plantilla" drop constraint "plantilla_archived_by_fkey";

alter table "public"."plantilla" drop constraint "plantilla_restored_by_fkey";

alter table "public"."vacancies" drop constraint "vacancies_restored_by_fkey";

alter table "public"."hr_emploc" drop constraint "hr_emploc_assignment_type_consistency_chk";

alter table "public"."plantilla" drop constraint "plantilla_status_check";

alter table "public"."user_scopes" drop constraint "user_scopes_user_id_group_id_account_id_key";

drop function if exists "public"."confirm_applicant_onboard"(p_applicant_id uuid, p_last_name text, p_first_name text, p_middle_name text, p_full_name text, p_contact_number text, p_remarks text, p_roving_assignment_id uuid, p_hired_by_user_id uuid, p_endorsed_by_deployer_id uuid, p_endorsed_by_name text);

drop view if exists "public"."headcount_summary";

drop view if exists "public"."own_performance_view";

drop view if exists "public"."team_performance_summary";

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

drop view if exists "public"."v_deactivation_requests";

drop view if exists "public"."v_group_kpi";

drop view if exists "public"."v_store_import_approval_queue";

drop view if exists "public"."v_vacancy_active_coverage";

drop view if exists "public"."v_vacancy_pipeline_status";

drop view if exists "public"."view_archived_records";

drop view if exists "public"."vw_account_handlers";

drop view if exists "public"."vw_applicant_funnel";

drop view if exists "public"."vw_archived_plantilla";

drop view if exists "public"."vw_archived_vacancies";

drop view if exists "public"."vw_open_vacancies_by_store";

drop view if exists "public"."vw_recruiter_sla";

drop view if exists "public"."vw_sla_by_group";

drop view if exists "public"."vw_vacancy_by_region";

drop view if exists "public"."vw_vacancy_closure_pending";

drop view if exists "public"."vw_vacancy_detail";

drop view if exists "public"."vw_vacancy_list";

drop view if exists "public"."v_cencom_account_kpi";

drop view if exists "public"."v_account_kpi";

drop index if exists "public"."idx_account_requests_full_name_search";

drop index if exists "public"."idx_users_profile_full_name_search";

drop index if exists "public"."user_scopes_user_id_group_id_account_id_key";

CREATE INDEX idx_account_requests_full_name_search ON public.account_requests USING gin (full_name_search extensions.gin_trgm_ops) WHERE (full_name_search IS NOT NULL);

CREATE INDEX idx_users_profile_full_name_search ON public.users_profile USING gin (full_name_search extensions.gin_trgm_ops) WHERE (full_name_search IS NOT NULL);

CREATE UNIQUE INDEX user_scopes_user_id_group_id_account_id_key ON public.user_scopes USING btree (user_id, group_id, account_id) NULLS NOT DISTINCT;

alter table "public"."hr_emploc" add constraint "hr_emploc_assignment_type_consistency_chk" CHECK ((((assignment_type = 'Stationary'::public.hr_emploc_assignment_type) AND (roving_assignment_id IS NULL) AND (vacancy_id IS NOT NULL)) OR ((assignment_type = 'Roving'::public.hr_emploc_assignment_type) AND (roving_assignment_id IS NOT NULL)))) NOT VALID not valid;

alter table "public"."hr_emploc" validate constraint "hr_emploc_assignment_type_consistency_chk";

alter table "public"."plantilla" add constraint "plantilla_status_check" CHECK ((status = ANY (ARRAY['Active'::text, 'Inactive'::text, 'Pending Deactivation'::text, 'Rejected Deactivation'::text, 'Deactivated'::text]))) not valid;

alter table "public"."plantilla" validate constraint "plantilla_status_check";

alter table "public"."user_scopes" add constraint "user_scopes_user_id_group_id_account_id_key" UNIQUE using index "user_scopes_user_id_group_id_account_id_key";

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

CREATE OR REPLACE FUNCTION public.get_request_account_signup_options()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_roles jsonb;
  v_groups jsonb;
  v_accounts jsonb;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object('id', r.id, 'role_name', r.role_name)
    ORDER BY r.role_name
  )
  INTO v_roles
  FROM public.roles r
  WHERE r.role_name IN (
    'Operations Manager',
    'OM',
    'Encoder',
    'Recruitment Team',
    'HRCO',
    'ATL',
    'TL'
  );

  SELECT jsonb_agg(
    jsonb_build_object('id', g.id, 'group_name', g.group_name)
    ORDER BY g.group_name
  )
  INTO v_groups
  FROM public.groups g;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', a.id,
      'account_name', a.account_name,
      'group_id', a.group_id
    )
    ORDER BY a.account_name
  )
  INTO v_accounts
  FROM public.accounts a
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false;

  RETURN jsonb_build_object(
    'roles', COALESCE(v_roles, '[]'::jsonb),
    'groups', COALESCE(v_groups, '[]'::jsonb),
    'accounts', COALESCE(v_accounts, '[]'::jsonb)
  );
END;
$function$
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


CREATE OR REPLACE FUNCTION public.list_web_vacancies(p_status text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid, p_position text DEFAULT NULL::text, p_urgency text DEFAULT NULL::text, p_aging_bucket text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_vacant_from date DEFAULT NULL::date, p_vacant_to date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_sort_by text DEFAULT 'vacant_date'::text, p_sort_dir text DEFAULT 'desc'::text)
 RETURNS TABLE(vacancy_id uuid, vcode text, account_id uuid, account_name text, group_id uuid, group_name text, store_id uuid, store_name text, position_title text, employment_type text, vacancy_status text, pipeline_status text, vacant_date date, aging_days integer, aging_bucket text, target_fill_date date, urgency text, penalty_exposure numeric, hrco_name text, row_capabilities jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid     uuid := auth.uid();
  v_profile_id   uuid;
  v_role_name    text;
  v_role_level   integer;
  v_sort_by      text := lower(coalesce(nullif(btrim(p_sort_by), ''), 'vacant_date'));
  v_sort_dir     text := lower(coalesce(nullif(btrim(p_sort_dir), ''), 'desc'));
  v_limit        integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset       integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: web vacancy list requires a valid session'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, r.role_name, r.role_level
  INTO v_profile_id, v_role_name, v_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = v_auth_uid
    AND up.is_active = TRUE
    AND up.archived_at IS NULL
  ORDER BY up.created_at DESC
  LIMIT 1;

  IF v_profile_id IS NULL OR coalesce(v_role_level, 0) <= 0 THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF coalesce(v_role_name, '') = 'HR Personnel' THEN
    RAISE EXCEPTION 'forbidden: web vacancy list caller is not allowed'
      USING ERRCODE = '42501';
  END IF;

  IF v_sort_by <> ALL (ARRAY[
    'vcode',
    'account_name',
    'group_name',
    'store_name',
    'position',
    'vacancy_status',
    'pipeline_status',
    'vacant_date',
    'aging_days',
    'target_fill_date',
    'urgency'
  ]) THEN
    RAISE EXCEPTION 'invalid sort field: %', p_sort_by
      USING ERRCODE = '22023';
  END IF;

  IF v_sort_dir <> ALL (ARRAY['asc', 'desc']) THEN
    RAISE EXCEPTION 'invalid sort direction: %', p_sort_dir
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      vl.id AS vacancy_id,
      vl.vcode,
      vl.account_id,
      vl.account AS account_name,
      vl.group_id,
      vl.group_name,
      vl.store_id,
      vl.store_name,
      vl.position AS position_title,
      vl.employment_type,
      vl.status AS vacancy_status,
      vl.derived_status AS pipeline_status,
      vl.vacant_date,
      vl.aging_days::integer AS aging_days,
      CASE
        WHEN vl.aging_days IS NULL THEN 'unknown'
        WHEN vl.aging_days <= 7 THEN '0_7'
        WHEN vl.aging_days <= 14 THEN '8_14'
        WHEN vl.aging_days <= 30 THEN '15_30'
        ELSE '31_plus'
      END AS aging_bucket,
      vl.target_fill_date,
      vl.urgency_level AS urgency,
      CASE
        WHEN coalesce(v_raw.has_penalty, false)
          THEN coalesce(v_raw.penalty_amount, 0::numeric)
        ELSE 0::numeric
      END AS penalty_exposure,
      vl.hrco_name,
      jsonb_build_object(
        'can_view_detail', true,
        'can_request_closure_hint',
          coalesce(v_role_level, 0) >= 30
          AND coalesce(vl.is_archived, false) = false
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived']),
        'authority', 'rls_action_rpcs'
      ) AS row_capabilities
    FROM public.vw_vacancy_list vl
    JOIN public.vacancies v_raw ON v_raw.id = vl.id
    WHERE
      (
        coalesce(v_role_level, 0) >= 90
        OR (
          coalesce(vl.is_archived, false) = false
          AND vl.status <> ALL (ARRAY['Filled', 'Closed', 'Archived'])
          AND (
            vl.account = ANY (public.get_my_allowed_accounts())
            OR
            EXISTS (
              SELECT 1
              FROM public.user_scopes us
              WHERE us.user_id = v_profile_id
                AND us.account_id = vl.account_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.user_scopes us
              JOIN public.accounts a ON a.id = vl.account_id
              WHERE us.user_id = v_profile_id
                AND us.account_id IS NULL
                AND us.group_id = a.group_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.users_profile up_fallback
              JOIN public.accounts a ON a.id = vl.account_id
              WHERE up_fallback.id = v_profile_id
                AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_scopes us_any
                  WHERE us_any.user_id = v_profile_id
                    AND (us_any.group_id IS NOT NULL OR us_any.account_id IS NOT NULL)
                )
                AND (
                  up_fallback.account_id = vl.account_id
                  OR up_fallback.group_id = a.group_id
                )
            )
          )
        )
      )
  ),
  filtered AS (
    SELECT s.*
    FROM scoped s
    WHERE
      (p_status IS NULL OR lower(s.vacancy_status) = lower(btrim(p_status)) OR lower(s.pipeline_status) = lower(btrim(p_status)))
      AND (p_account_id IS NULL OR s.account_id = p_account_id)
      AND (p_group_id IS NULL OR s.group_id = p_group_id)
      AND (p_position IS NULL OR lower(s.position_title) = lower(btrim(p_position)))
      AND (p_urgency IS NULL OR lower(coalesce(s.urgency, '')) = lower(btrim(p_urgency)))
      AND (p_aging_bucket IS NULL OR s.aging_bucket = lower(btrim(p_aging_bucket)))
      AND (p_vacant_from IS NULL OR s.vacant_date >= p_vacant_from)
      AND (p_vacant_to IS NULL OR s.vacant_date <= p_vacant_to)
      AND (
        p_search IS NULL
        OR nullif(btrim(p_search), '') IS NULL
        OR s.vcode ILIKE '%' || btrim(p_search) || '%'
        OR s.account_name ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.group_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR coalesce(s.store_name, '') ILIKE '%' || btrim(p_search) || '%'
        OR s.position_title ILIKE '%' || btrim(p_search) || '%'
      )
  ),
  counted AS (
    SELECT f.*, count(*) OVER () AS total_count
    FROM filtered f
  )
  SELECT
    c.vacancy_id,
    c.vcode,
    c.account_id,
    c.account_name,
    c.group_id,
    c.group_name,
    c.store_id,
    c.store_name,
    c.position_title,
    c.employment_type,
    c.vacancy_status,
    c.pipeline_status,
    c.vacant_date,
    c.aging_days,
    c.aging_bucket,
    c.target_fill_date,
    c.urgency,
    c.penalty_exposure,
    c.hrco_name,
    c.row_capabilities,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vcode'            THEN c.vcode END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vcode'            THEN c.vcode END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'account_name'     THEN c.account_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'account_name'     THEN c.account_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'group_name'       THEN c.group_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'group_name'       THEN c.group_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'store_name'       THEN c.store_name END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'store_name'       THEN c.store_name END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'position'         THEN c.position_title END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'position'         THEN c.position_title END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vacancy_status'   THEN c.vacancy_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vacancy_status'   THEN c.vacancy_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'pipeline_status'  THEN c.pipeline_status END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'pipeline_status'  THEN c.pipeline_status END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'vacant_date'      THEN c.vacant_date END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'vacant_date'      THEN c.vacant_date END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'aging_days'       THEN c.aging_days END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'aging_days'       THEN c.aging_days END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'target_fill_date' THEN c.target_fill_date END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'target_fill_date' THEN c.target_fill_date END DESC NULLS LAST,
    CASE WHEN v_sort_dir = 'asc'  AND v_sort_by = 'urgency'          THEN c.urgency END ASC NULLS LAST,
    CASE WHEN v_sort_dir = 'desc' AND v_sort_by = 'urgency'          THEN c.urgency END DESC NULLS LAST,
    c.vcode ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
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


create or replace view "public"."v_account_kpi" as  WITH actual AS (
         SELECT p.account_id,
            count(*) FILTER (WHERE (p.status = 'Active'::text)) AS actual_hc
           FROM public.plantilla p
          WHERE ((COALESCE(p.is_deleted, false) = false) AND (COALESCE(p.is_archived, false) = false) AND (COALESCE(p.is_pool_employee, false) = false))
          GROUP BY p.account_id
        ), pipeline AS (
         SELECT he.account_id,
            count(*) AS pipeline_count
           FROM (public.hr_emploc he
             LEFT JOIN public.vacancies v ON ((v.id = he.vacancy_id)))
          WHERE ((he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])) AND (he.deleted_at IS NULL) AND (COALESCE(v.is_archived, false) = false) AND (COALESCE(v.is_pool_vacancy, false) = false))
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


create or replace view "public"."v_approval_queue" as  SELECT ar.id,
    ar.auth_user_id,
    ar.email,
    ar.full_name,
    ar.last_name,
    ar.first_name,
    ar.middle_name,
    ar.mobile_number,
    ar.full_name_search,
    ar.status,
    ar.notes,
    ar.requested_role_id,
    req_r.role_name AS requested_role_name,
    req_r.role_level AS requested_role_level,
    ar.assigned_role_id,
    asgn_r.role_name AS assigned_role_name,
    asgn_r.role_level AS assigned_role_level,
    ar.assigned_scope_type,
    ar.assigned_groups_snapshot,
    ar.assigned_accounts_snapshot,
    ar.reviewed_by,
    ar.reviewed_at,
    ar.rejection_reason,
    ar.rejected_at,
    ar.created_at,
    ar.updated_at,
    reviewer_up.full_name AS reviewer_display_name,
    COALESCE(( SELECT array_agg(rgs.group_id ORDER BY g.group_name) AS array_agg
           FROM (public.account_request_group_scopes rgs
             JOIN public.groups g ON ((g.id = rgs.group_id)))
          WHERE (rgs.account_request_id = ar.id)), ARRAY[]::uuid[]) AS requested_group_ids,
    COALESCE(( SELECT array_agg(g.group_name ORDER BY g.group_name) AS array_agg
           FROM (public.account_request_group_scopes rgs
             JOIN public.groups g ON ((g.id = rgs.group_id)))
          WHERE (rgs.account_request_id = ar.id)), ARRAY[]::text[]) AS requested_group_names,
    COALESCE(( SELECT array_agg(ras.account_id ORDER BY a.account_name) AS array_agg
           FROM (public.account_request_account_scopes ras
             JOIN public.accounts a ON ((a.id = ras.account_id)))
          WHERE (ras.account_request_id = ar.id)), ARRAY[]::uuid[]) AS requested_account_ids,
    COALESCE(( SELECT array_agg(a.account_name ORDER BY a.account_name) AS array_agg
           FROM (public.account_request_account_scopes ras
             JOIN public.accounts a ON ((a.id = ras.account_id)))
          WHERE (ras.account_request_id = ar.id)), ARRAY[]::text[]) AS requested_account_names,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM public.account_request_group_scopes rgs
              WHERE (rgs.account_request_id = ar.id))) THEN 'scoped'::text
            WHEN (ar.assigned_scope_type IS NOT NULL) THEN ar.assigned_scope_type
            ELSE 'global'::text
        END AS requested_scope_type,
    ((EXTRACT(epoch FROM (now() - ar.created_at)))::integer / 86400) AS days_pending
   FROM (((public.account_requests ar
     LEFT JOIN public.roles req_r ON ((req_r.id = ar.requested_role_id)))
     LEFT JOIN public.roles asgn_r ON ((asgn_r.id = ar.assigned_role_id)))
     LEFT JOIN public.users_profile reviewer_up ON ((reviewer_up.auth_user_id = ar.reviewed_by)))
  ORDER BY
        CASE ar.status
            WHEN 'pending'::public.account_request_status THEN 1
            WHEN 'rejected'::public.account_request_status THEN 2
            WHEN 'approved'::public.account_request_status THEN 3
            ELSE NULL::integer
        END, ar.created_at DESC;


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


create or replace view "public"."v_deactivation_requests" as  SELECT r.id,
    r.plantilla_id,
    r.employee_name,
    r.employee_no,
    r.account_name,
    r.account_id,
    g.group_name,
    r.group_id,
    r.status,
    r.batch_id,
    r.resubmit_count,
    r.created_at,
    r.processed_at,
    r.is_archived,
        CASE
            WHEN ((req.last_name IS NOT NULL) AND (req.first_name IS NOT NULL)) THEN ((req.last_name || ', '::text) || req.first_name)
            ELSE COALESCE(req.full_name, 'Unknown'::text)
        END AS requestor_display_name,
    r.requestor_profile_id,
        CASE
            WHEN ((proc.last_name IS NOT NULL) AND (proc.first_name IS NOT NULL)) THEN ((proc.last_name || ', '::text) || proc.first_name)
            WHEN (proc.full_name IS NOT NULL) THEN proc.full_name
            ELSE NULL::text
        END AS processor_display_name,
    r.processed_by_profile_id
   FROM (((public.employee_deactivation_requests r
     LEFT JOIN public.groups g ON ((g.id = r.group_id)))
     LEFT JOIN public.users_profile req ON ((req.id = r.requestor_profile_id)))
     LEFT JOIN public.users_profile proc ON ((proc.id = r.processed_by_profile_id)))
  WHERE (r.is_archived = false);


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


create or replace view "public"."vw_archived_plantilla" as  SELECT p.id,
    p.employee_name,
    p.employee_no,
    p.account,
    p.status,
    p.emploc_no,
    p.vcode,
    p."position",
    p.created_at,
    p.hr_emploc_id,
    p.vacancy_id,
    p.vacancy_code_snapshot,
    p.employee_name_snapshot,
    p.account_id,
    p.chain_id,
    p.store_id,
    p.province_id,
    p.area_name_snapshot,
    p.hrco_user_id_snapshot,
    p.om_user_id_snapshot,
    p.atl_user_id_snapshot,
    p.position_id,
    p.rest_day,
    p.resignation_date,
    p.remarks,
    p.moved_by_user_id,
    p.created_by,
    p.updated_at,
    p.updated_by,
    p.store_name,
    p.area,
    p.rate,
    p.schedule,
    p.deployment_type,
    p.has_penalty,
    p.date_hired,
    p.coordinator,
    p.hrco_name,
    p.last_name,
    p.first_name,
    p.middle_name,
    p.date_of_separation,
    p.separation_status,
    p.tagged_at,
    p.inactive_at,
    p.inactive_by,
    p.for_deactivation_at,
    p.for_deactivation_by,
    p.deactivated_at,
    p.deactivated_by,
    p.deactivated_visible_until,
    p.last_mika_synced_at,
    p.last_mika_synced_by,
    p.source_headcount_request_id,
    p.is_deleted,
    p.over_headcount,
    p.deactivation_reason,
    p.deletion_requested_at,
    p.deletion_requested_by,
    p.deletion_reason,
    p.deletion_remarks,
    p.deletion_approved_at,
    p.deletion_approved_by,
    p.sss_no,
    p.philhealth_no,
    p.pagibig_no,
    p.atm_no,
    p.civil_status,
    p.date_of_birth,
    p.transferred_from_store_id,
    p.last_transfer_at,
    p.last_transfer_by,
    p.roving_assignment_id,
    p.is_pool_employee,
    p.pool_type_id,
    p.requesting_account,
    p.requesting_account_id,
    p.requesting_store_id,
    p.inactive_visible_until,
    p.is_archived,
    p.archived_at,
    p.archived_by,
    p.archive_reason,
    p.restored_at,
    p.restored_by,
    up_arc.full_name AS archived_by_name,
    up_rst.full_name AS restored_by_name
   FROM ((public.plantilla p
     LEFT JOIN public.users_profile up_arc ON ((up_arc.id = p.archived_by)))
     LEFT JOIN public.users_profile up_rst ON ((up_rst.id = p.restored_by)))
  WHERE (p.is_archived = true);


create or replace view "public"."vw_archived_vacancies" as  SELECT v.id,
    v.vcode,
    v.account,
    v."position",
    v.status,
    v.backout_reason,
    v.created_at,
    v.vacancy_code,
    v.vacancy_type,
    v.account_id,
    v.chain_id,
    v.store_id,
    v.province_id,
    v.area_name,
    v.hrco_user_id,
    v.om_user_id,
    v.atl_user_id,
    v.position_id,
    v.vacant_date,
    v.required_headcount,
    v.has_penalty,
    v.penalty_amount,
    v.has_reliever,
    v.reliever_name,
    v.remarks,
    v.requested_by_user_id,
    v.requested_date,
    v.created_by_user_id,
    v.closure_request_status,
    v.archived_at,
    v.archived_by,
    v.created_by,
    v.updated_at,
    v.updated_by,
    v.chain,
    v.province,
    v.store_branch,
    v.hrco_name,
    v.hrco_mobile,
    v.om_name,
    v.is_archived,
    v.has_pending_closure,
    v.store_name,
    v.area_city,
    v.penalty_aging_detail,
    v.assigned_encoder_id,
    v.source_plantilla_id,
    v.deleted_at,
    v.source,
    v.source_vacancy_request_id,
    v.urgency_level,
    v.target_fill_date,
    v.triggered_by_user_id,
    v.triggered_by_name,
    v.employment_type,
    v.group_id,
    v.source_headcount_request_id,
    v.is_pool_vacancy,
    v.pool_type_id,
    v.home_account_id,
    v.affects_required_hc,
    v.affects_mfr,
    v.pool_request_id,
    v.archive_reason,
    v.restored_at,
    v.restored_by,
    v.archived_by_id,
    up_arc.full_name AS archived_by_name,
    up_rst.full_name AS restored_by_name
   FROM ((public.vacancies v
     LEFT JOIN public.users_profile up_arc ON ((up_arc.id = v.archived_by_id)))
     LEFT JOIN public.users_profile up_rst ON ((up_rst.id = v.restored_by)))
  WHERE (v.is_archived = true);


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
    v.province,
    v.store_branch,
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
        CASE
            WHEN ((up_hrco.is_active = true) AND (r_hrco.role_name = 'HRCO'::text)) THEN up_hrco.full_name
            ELSE NULL::text
        END AS hrco_name,
    COALESCE(up_trig.full_name, v.triggered_by_name) AS triggered_by_full_name,
    NULL::text AS triggered_by_role,
    vr.vacancy_type AS hc_request_type,
    vr.requested_by AS hc_request_requested_by,
    vr.requested_by_user_id AS hc_request_requested_by_user_id,
    vr.created_at AS hc_request_date_created,
    vr.no_of_slots AS hc_request_no_of_slots,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire
   FROM ((((((public.vacancies v
     LEFT JOIN applicant_stats s ON ((s.vacancy_vcode = v.vcode)))
     LEFT JOIN public.groups g ON ((g.id = v.group_id)))
     LEFT JOIN public.users_profile up_trig ON ((up_trig.id = v.triggered_by_user_id)))
     LEFT JOIN public.users_profile up_hrco ON ((up_hrco.id = v.hrco_user_id)))
     LEFT JOIN public.roles r_hrco ON ((r_hrco.id = up_hrco.role_id)))
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
    v.province,
    v.store_branch,
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
        CASE
            WHEN ((up_hrco.is_active = true) AND (r_hrco.role_name = 'HRCO'::text)) THEN up_hrco.full_name
            ELSE NULL::text
        END AS hrco_name,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire
   FROM ((((public.vacancies v
     LEFT JOIN applicant_stats s ON ((s.vacancy_vcode = v.vcode)))
     LEFT JOIN public.groups g ON ((g.id = v.group_id)))
     LEFT JOIN public.users_profile up_hrco ON ((up_hrco.id = v.hrco_user_id)))
     LEFT JOIN public.roles r_hrco ON ((r_hrco.id = up_hrco.role_id)))
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


