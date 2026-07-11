-- Migration: Extend tag_backout with coverage slot reset branch
-- When a coverage HR Emploc is backed out, reset the linked coverage_slot
-- back to 'open' so it can be re-filled. Existing stationary/roving paths
-- are unchanged. Slot reset failure is non-fatal (WARNING only).

CREATE OR REPLACE FUNCTION public.tag_backout(p_id uuid, p_reason text, p_reason_code text DEFAULT NULL::text)
 RETURNS hr_emploc
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
  v_slot_result   jsonb;
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

  -- Coverage slot reset: return slot to 'open' so it can be re-filled.
  -- Non-fatal — slot reset failure must not roll back the HR Emploc backout.
  IF v_old.coverage_slot_id IS NOT NULL THEN
    BEGIN
      v_slot_result := public.fn_set_coverage_slot_status(
        p_slot_id      => v_old.coverage_slot_id,
        p_new_status   => 'open',
        p_performed_by => v_actor,
        p_remarks      => 'Backout: ' || COALESCE(p_reason, 'No reason provided')
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Coverage slot reset failed for slot %: %',
        v_old.coverage_slot_id, SQLERRM;
    END;
  END IF;

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
    'coverage_slot_id',    v_old.coverage_slot_id,
    'coverage_group_id',   v_old.coverage_group_id,
    'slot_reset_to',       CASE WHEN v_old.coverage_slot_id IS NOT NULL
                                THEN 'open' ELSE NULL END,
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
$function$;
