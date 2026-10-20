-- Migration: 20262606000047_fix_backout_workflow_and_slot_sync.sql
-- Description:
--   1. Update vw_vacancy_list and vw_vacancy_detail to robustly exclude all terminal
--      statuses ('failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew', 'confirmed_onboard')
--      from active_applicant_count regardless of casing or formatting.
--   2. Update fn_sync_vacancy_slot_open_pipeline so that when active applicant count is 0,
--      ALL unoccupied pipeline slots for that vcode transition back to 'open' (not just LIMIT 1).
--   3. Clean up active dropout records, unarchive/unlink duplicates for VCAG5_0056,
--      and restore VCAG5_0056 slots and status cleanly to 'Open' with 0 active applicants.

-- §1. Update vw_vacancy_list
CREATE OR REPLACE VIEW public.vw_vacancy_list AS
 WITH applicant_stats AS (
          SELECT a.vacancy_vcode,
            count(*) FILTER (
              WHERE COALESCE(a.is_archived, false) = false
                AND replace(replace(lower(btrim(COALESCE(a.status, ''))), ' ', '_'), '-', '_') NOT IN (
                  'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew', 'confirmed_onboard'
                )
            ) AS active_applicant_count,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS confirmed_onboard_count,
            max(a.hired_at) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text) AS latest_hire_at,
            count(*) FILTER (WHERE COALESCE(a.is_archived, false) = false AND a.status = 'Confirmed Onboard'::text AND COALESCE(a.hired_visible_until, a.hired_at + '7 days'::interval) > now()) > 0 AS has_recent_hire
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
            WHEN v.is_archived = true OR (v.status = ANY (ARRAY['Closed'::text, 'Archived'::text])) THEN 'Archived'::text
            WHEN v.status = 'Filled'::text THEN 'Hired'::text
            WHEN COALESCE(v.has_pending_closure, false) = true
                 OR LOWER(COALESCE(v.closure_request_status, '')) = 'pending'
                 OR LOWER(COALESCE(v.status, '')) IN ('closure', 'for_closure')
                 OR EXISTS (
                   SELECT 1 FROM public.vacancy_closure_requests vcr
                   WHERE vcr.vacancy_vcode = v.vcode AND LOWER(vcr.status) = 'pending'
                 ) THEN 'For Closure'::text
            WHEN COALESCE(s.active_applicant_count, 0::bigint) > 0 THEN 'Pipeline'::text
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
    CURRENT_DATE - v.vacant_date AS aging_days,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.is_archived,
    v.archived_at,
    v.closure_request_status,
    v.has_pending_closure,
    COALESCE(s.active_applicant_count, 0::bigint) AS active_applicant_count,
    COALESCE(s.confirmed_onboard_count, 0::bigint) AS confirmed_onboard_count,
    s.latest_hire_at,
    v.assigned_encoder_id,
    COALESCE(v.group_id, a.group_id) AS group_id,
    COALESCE(g.group_name, ga.group_name) AS group_name,
    v.hrco_user_id,
        CASE
            WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name
            ELSE NULL::text
        END AS hrco_name,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire
   FROM public.vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN public.accounts a ON a.id = v.account_id OR (v.account_id IS NULL AND lower(trim(a.account_name)) = lower(trim(v.account)))
     LEFT JOIN public.groups g ON g.id = v.group_id
     LEFT JOIN public.groups ga ON ga.id = a.group_id
     LEFT JOIN public.users_profile up_hrco ON up_hrco.id = v.hrco_user_id
     LEFT JOIN public.roles r_hrco ON r_hrco.id = up_hrco.role_id
  WHERE v.deleted_at IS NULL;

GRANT ALL ON public.vw_vacancy_list TO authenticated, postgres, service_role;

-- §2. Update vw_vacancy_detail
CREATE OR REPLACE VIEW public.vw_vacancy_detail AS
 WITH applicant_stats AS (
         SELECT a_1.vacancy_vcode,
            count(*) FILTER (
              WHERE COALESCE(a_1.is_archived, false) = false
                AND replace(replace(lower(btrim(COALESCE(a_1.status, ''))), ' ', '_'), '-', '_') NOT IN (
                  'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew', 'confirmed_onboard'
                )
            ) AS active_applicant_count,
            count(*) FILTER (WHERE ((COALESCE(a_1.is_archived, false) = false) AND (a_1.status = 'Confirmed Onboard'::text))) AS confirmed_onboard_count,
            max(a_1.hired_at) FILTER (WHERE ((COALESCE(a_1.is_archived, false) = false) AND (a_1.status = 'Confirmed Onboard'::text))) AS latest_hire_at,
            (count(*) FILTER (WHERE ((COALESCE(a_1.is_archived, false) = false) AND (a_1.status = 'Confirmed Onboard'::text) AND (COALESCE(a_1.hired_visible_until, (a_1.hired_at + '7 days'::interval)) > now()))) > 0) AS has_recent_hire
           FROM public.applicants a_1
          GROUP BY a_1.vacancy_vcode
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
    COALESCE(v.group_id, a.group_id) AS group_id,
    COALESCE(g.group_name, ga.group_name) AS group_name,
    v.hrco_user_id,
    v.hrco_name,
    COALESCE(up.full_name, v.triggered_by_name) AS triggered_by_full_name,
    NULL::text AS triggered_by_role,
    vr.vacancy_type AS hc_request_type,
    vr.requested_by AS hc_request_requested_by,
    vr.requested_by_user_id AS hc_request_requested_by_user_id,
    vr.created_at AS hc_request_date_created,
    vr.no_of_slots AS hc_request_no_of_slots,
    COALESCE(s.has_recent_hire, false) AS has_recent_hire,
    v.request_type
   FROM vacancies v
     LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
     LEFT JOIN accounts a ON (a.id = v.account_id) OR (v.account_id IS NULL AND lower(TRIM(BOTH FROM a.account_name)) = lower(TRIM(BOTH FROM v.account)))
     LEFT JOIN groups g ON g.id = v.group_id
     LEFT JOIN groups ga ON ga.id = a.group_id
     LEFT JOIN users_profile up ON up.id = v.triggered_by_user_id
     LEFT JOIN vacancy_requests vr ON vr.id = v.source_vacancy_request_id
  WHERE (v.deleted_at IS NULL);

GRANT ALL ON public.vw_vacancy_detail TO authenticated, postgres, service_role;

-- §3. Update fn_sync_vacancy_slot_open_pipeline
CREATE OR REPLACE FUNCTION public.fn_sync_vacancy_slot_open_pipeline(
  p_vcode        text,
  p_performed_by uuid DEFAULT NULL::uuid,
  p_source_fn    text DEFAULT 'unknown'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active_cnt  bigint;
  v_target      text;
  v_result      jsonb;
  r_slot        record;
BEGIN
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_vacancy_slot_open_pipeline: skipped — p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_active_cnt
  FROM public.applicants
  WHERE vacancy_vcode = p_vcode
    AND COALESCE(is_archived, false) = false
    AND replace(replace(lower(btrim(COALESCE(status, ''))), ' ', '_'), '-', '_') NOT IN (
      'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew', 'confirmed_onboard'
    );

  v_target := CASE WHEN v_active_cnt > 0 THEN 'pipeline' ELSE 'open' END;

  IF v_target = 'open' THEN
    -- Transition all unassigned pipeline slots for this vcode back to 'open'
    FOR r_slot IN
      SELECT id, slot_status
      FROM public.plantilla_slots
      WHERE legacy_vcode = p_vcode
        AND is_roving = false
        AND slot_status = 'pipeline'
        AND current_occupant_plantilla_id IS NULL
    LOOP
      PERFORM public.fn_set_slot_status(
        p_slot_id               => r_slot.id,
        p_new_status            => 'open',
        p_reason_code           => NULL,
        p_performed_by          => p_performed_by,
        p_remarks               => format('Phase 6.1 / %s / VCODE=%s / active_applicants=0 / release to open', COALESCE(p_source_fn, 'unknown'), p_vcode),
        p_occupant_plantilla_id => NULL
      );
    END LOOP;

    RETURN jsonb_build_object(
      'status', 'ok',
      'vcode', p_vcode,
      'target', 'open',
      'active_applicants', 0
    );
  ELSE
    FOR r_slot IN
      SELECT id, slot_status
      FROM public.plantilla_slots
      WHERE legacy_vcode = p_vcode
        AND is_roving = false
        AND slot_status = 'open'
      LIMIT 1
    LOOP
      SELECT public.fn_set_slot_status(
        p_slot_id               => r_slot.id,
        p_new_status            => 'pipeline',
        p_reason_code           => NULL,
        p_performed_by          => p_performed_by,
        p_remarks               => format('Phase 6.1 / %s / VCODE=%s / active_applicants=%s', COALESCE(p_source_fn, 'unknown'), p_vcode, v_active_cnt),
        p_occupant_plantilla_id => NULL
      ) INTO v_result;
      RETURN v_result;
    END LOOP;

    RETURN jsonb_build_object(
      'status', 'no_op',
      'vcode', p_vcode,
      'target', 'pipeline',
      'active_applicants', v_active_cnt
    );
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_vacancy_slot_open_pipeline: error for VCODE=% source=% — % (sqlstate=%)',
    p_vcode, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_vacancy_slot_open_pipeline(text, uuid, text) IS
  'Reconciles plantilla_slots status between open and pipeline based on active applicants, clearing all unoccupied pipeline slots when active count is zero.';

GRANT EXECUTE ON FUNCTION public.fn_sync_vacancy_slot_open_pipeline(text, uuid, text) TO authenticated, service_role;

-- §4. Clean up duplicate / unarchived dropouts across all active vacancies
UPDATE public.applicants
SET is_archived = true,
    slot_id = NULL,
    updated_at = now()
WHERE replace(replace(lower(btrim(COALESCE(status, ''))), ' ', '_'), '-', '_') IN (
  'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew'
) AND (COALESCE(is_archived, false) = false OR slot_id IS NOT NULL);

-- §5. Ensure VCAG5_0056 slots and vacancy status are cleanly reset to 'Open'
UPDATE public.plantilla_slots
SET slot_status = 'open',
    current_occupant_plantilla_id = NULL,
    updated_at = now()
WHERE legacy_vcode = 'VCAG5_0056'
  AND slot_status = 'pipeline'
  AND current_occupant_plantilla_id IS NULL;

UPDATE public.vacancies
SET status = 'Open',
    updated_at = now()
WHERE vcode = 'VCAG5_0056';

-- §6. Record history for dropouts on VCAG5_0056 if not present
INSERT INTO public.applicant_status_history (
  id, applicant_id, from_status, to_status, remarks, source_module, update_type, changed_field, old_value, new_value, changed_at
)
SELECT
  gen_random_uuid(), a.id, 'Pipeline', a.status, a.backout_reason, 'vacancy', 'status_change', 'status', 'Pipeline', a.status, COALESCE(a.updated_at, now())
FROM public.applicants a
WHERE a.vacancy_vcode = 'VCAG5_0056'
  AND a.status IN ('Backout', 'Rejected')
  AND NOT EXISTS (
    SELECT 1 FROM public.applicant_status_history ash WHERE ash.applicant_id = a.id
  );

-- §7. For older duplicate dropouts on VCAG5_0056 prior to LANDO NORRIS, clear vacancy_vcode so they don't multiply phantom rows
UPDATE public.applicants
SET vacancy_vcode = NULL,
    updated_at = now()
WHERE vacancy_vcode = 'VCAG5_0056'
  AND id IN ('c20455ac-755c-4ffa-99bb-8227346e2fa7', 'f13687d8-36ac-4392-a2c5-8ad84b045ad8', '3e47e03c-aa70-4bae-896d-15f51af0ab8f');
