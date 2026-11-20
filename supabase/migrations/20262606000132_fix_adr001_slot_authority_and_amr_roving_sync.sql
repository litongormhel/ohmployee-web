-- Migration: 20262606000131_fix_adr001_slot_authority_and_amr_roving_sync.sql
-- 1. Hardens revert_hr_emploc_to_pending to use public.fn_set_slot_status (ADR-001 Rule 1) and cleans hr_emploc_store_links.
-- 2. Aligns public.vw_vacancy_list to derive 'Hired' status strictly from active plantilla (ADR-001 Rule 2).
-- 3. Enables roving slot selection in public.fn_amr_execute_transfer.
-- 4. Enables roving slot synchronization in public.fn_sync_vacancy_slot_open_pipeline.

-- ============================================================================
-- 1. Update public.revert_hr_emploc_to_pending
-- ============================================================================
CREATE OR REPLACE FUNCTION public.revert_hr_emploc_to_pending(
  p_hr_emploc_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_profile_id uuid := public.get_my_profile_id();
  v_actor_name       text := public.get_my_full_name();
  v_reason           text := btrim(coalesce(p_reason, ''));
  v_emp              public.hr_emploc;
  v_pl               public.plantilla;
  v_vcode            text;
  v_active_docs      bigint := 0;
  v_restored_status  text := 'Pending';
  v_slot_rec         record;
BEGIN
  IF v_reason = '' THEN
    RAISE EXCEPTION 'FIELD_REQUIRED_MISSING: Reason for revert is required'
      USING ERRCODE = '22023', DETAIL = jsonb_build_object('code', 'FIELD_REQUIRED_MISSING', 'field', 'reason')::text;
  END IF;

  -- Gate: Data Team (Encoder, Head Admin) or Super Admin ONLY (Decision 7)
  IF NOT public.can_edit_deployed_hr_emploc() THEN
    RAISE EXCEPTION 'FORBIDDEN_ROLE_OR_SCOPE: Data Team (Encoder, Head Admin) or Super Admin required'
      USING ERRCODE = '42501', DETAIL = jsonb_build_object('code', 'FORBIDDEN_ROLE_OR_SCOPE')::text;
  END IF;

  SELECT * INTO v_emp FROM public.hr_emploc WHERE id = p_hr_emploc_id FOR UPDATE;
  IF NOT FOUND OR v_emp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'RECORD_NOT_FOUND: Record not found or archived'
      USING ERRCODE = 'P0002', DETAIL = jsonb_build_object('code', 'RECORD_NOT_FOUND')::text;
  END IF;

  v_vcode := v_emp.vcode;

  -- 1. Soft-delete Plantilla row
  SELECT * INTO v_pl FROM public.plantilla
  WHERE hr_emploc_id = p_hr_emploc_id AND coalesce(is_deleted, false) = false
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.plantilla
    SET is_deleted = true,
        status     = 'Deactivated',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE id = v_pl.id;

    UPDATE public.plantilla_store_links
    SET status      = 'Backed Out',
        unlinked_at = now(),
        unlinked_by = v_actor_profile_id,
        updated_at  = now(),
        updated_by  = v_actor_profile_id
    WHERE plantilla_id = v_pl.id;

    -- Re-open slot via ADR-001 fn_set_slot_status authority (Rule 1)
    FOR v_slot_rec IN (
      SELECT id FROM public.plantilla_slots
      WHERE current_occupant_plantilla_id = v_pl.id
         OR (v_emp.slot_id IS NOT NULL AND id = v_emp.slot_id)
    ) LOOP
      PERFORM public.fn_set_slot_status(
        p_slot_id               => v_slot_rec.id,
        p_new_status            => 'open',
        p_reason_code           => 'BACKOUT',
        p_performed_by          => v_actor_profile_id,
        p_remarks               => format('Reverted from HR Emploc deployment: %s', v_reason),
        p_occupant_plantilla_id => NULL
      );
    END LOOP;
  ELSIF v_emp.slot_id IS NOT NULL THEN
    -- Fallback for unlinked slots
    PERFORM public.fn_set_slot_status(
      p_slot_id               => v_emp.slot_id,
      p_new_status            => 'open',
      p_reason_code           => 'BACKOUT',
      p_performed_by          => v_actor_profile_id,
      p_remarks               => format('Reverted from HR Emploc deployment: %s', v_reason),
      p_occupant_plantilla_id => NULL
    );
  END IF;

  -- Clean up hr_emploc store links
  UPDATE public.hr_emploc_store_links
  SET status     = 'Reverted',
      updated_at = now()
  WHERE hr_emploc_id = p_hr_emploc_id;

  -- Reconcile Vacancy if needed
  IF v_vcode IS NOT NULL THEN
    UPDATE public.vacancies
    SET status     = 'Open',
        updated_at = now(),
        updated_by = v_actor_profile_id
    WHERE vcode = v_vcode
      AND status IN ('Filled', 'Closed')
      AND coalesce(is_archived, false) = false
      AND deleted_at IS NULL;
  END IF;

  -- Decision 1: Keep number reserved to this person & source_hr_emploc_id in registry
  IF v_emp.employee_no IS NOT NULL AND btrim(v_emp.employee_no) <> '' THEN
    UPDATE public.employee_number_registry
    SET updated_at = now(),
        history = history || jsonb_build_object(
          'action', 'revert_to_pending',
          'actor', v_actor_profile_id,
          'timestamp', now(),
          'reason', v_reason
        )
    WHERE emploc_no = btrim(v_emp.employee_no);
  END IF;

  -- Decision 6: Cancel queued purge; if unpurged docs remain, restore hr_status = 'For Emploc'; else 'Pending'
  UPDATE public.storage_cleanup_queue
  SET status           = 'cancelled',
      cancelled_at     = now(),
      cancelled_reason = 'reverted_to_pending: ' || v_reason
  WHERE hr_emploc_id = p_hr_emploc_id
    AND status IN ('pending', 'dispatched');

  SELECT count(*) INTO v_active_docs
  FROM public.hr_emploc_correction_attachments ca
  WHERE ca.hr_emploc_id = p_hr_emploc_id
    AND ca.is_deleted = false
    AND ca.deleted_at IS NULL;

  v_restored_status := CASE WHEN v_active_docs > 0 THEN 'For Emploc' ELSE 'Pending' END;

  -- Revert hr_emploc record to Pending Emploc (with hr_status = For Emploc or Pending)
  UPDATE public.hr_emploc
  SET employee_no           = NULL,
      emploc_no             = NULL,
      status                = 'Pending Emploc',
      hr_status             = v_restored_status,
      moved_to_plantilla_at = NULL,
      moved_to_plantilla_by = NULL,
      updated_at            = now(),
      updated_by            = v_actor_profile_id
  WHERE id = p_hr_emploc_id;

  PERFORM public.log_audit_event(
    'hr_emploc',
    'UPDATE',
    p_hr_emploc_id,
    jsonb_build_object('status', v_emp.status, 'hr_status', v_emp.hr_status, 'employee_no', v_emp.employee_no),
    jsonb_build_object(
      'action', 'revert_to_pending',
      'reason', v_reason,
      'restored_hr_status', v_restored_status,
      'active_doc_count', v_active_docs,
      'log_message', format('Reverted record to %s (Reason: %s) by %s', v_restored_status, v_reason, v_actor_name)
    )
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'hr_emploc_id', p_hr_emploc_id,
    'restored_hr_status', v_restored_status,
    'active_doc_count', v_active_docs,
    'message', format('Record reverted to %s', v_restored_status)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.revert_hr_emploc_to_pending(uuid, text) TO authenticated, service_role;


-- ============================================================================
-- 2. Update public.vw_vacancy_list (ADR-001 Rule 2 Alignment)
-- ============================================================================
CREATE OR REPLACE VIEW public.vw_vacancy_list AS
WITH applicant_stats AS (
  SELECT a_1.vacancy_vcode,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND (
          replace(replace(lower(btrim(COALESCE(a_1.status, ''::text))), ' '::text, '_'::text), '-'::text, '_'::text)
          <> ALL (ARRAY['failed'::text, 'backout'::text, 'rejected'::text, 'did_not_report'::text, 'rejected_by_ops'::text, 'withdrew'::text, 'confirmed_onboard'::text])
        )
    ) AS active_applicant_count,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
    ) AS confirmed_onboard_count,
    max(a_1.hired_at) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
    ) AS latest_hire_at,
    count(*) FILTER (
      WHERE COALESCE(a_1.is_archived, false) = false
        AND a_1.status = 'Confirmed Onboard'::text
        AND COALESCE(a_1.hired_visible_until, a_1.hired_at + '7 days'::interval) > now()
    ) > 0 AS has_recent_hire
  FROM public.applicants a_1
  GROUP BY a_1.vacancy_vcode
),
plantilla_stats AS (
  SELECT p.vcode,
    count(*) FILTER (
      WHERE p.status = 'Active'::text
        AND COALESCE(p.is_deleted, false) = false
        AND COALESCE(p.is_archived, false) = false
    ) AS active_plantilla_count
  FROM public.plantilla p
  WHERE p.vcode IS NOT NULL
  GROUP BY p.vcode
),
slot_stats AS (
  SELECT ps.legacy_vcode AS vcode,
    count(*) FILTER (
      WHERE ps.slot_status = 'hr_processing'::text
        AND ps.closed_at IS NULL
    ) AS hr_processing_count
  FROM public.plantilla_slots ps
  WHERE ps.legacy_vcode IS NOT NULL
    AND ps.is_roving = false
  GROUP BY ps.legacy_vcode
)
SELECT v.id,
  v.vcode,
  v.account,
  v.account_id,
  COALESCE(
    NULLIF(btrim(v.store_name), ''::text),
    NULLIF(btrim(v.store_branch), ''::text),
    CASE
      WHEN v.is_pool_vacancy = true
        OR v.source = 'pool'::text
        OR v.vcode ~~ '%GHQ%'::text
        OR lower(btrim(COALESCE(v.account, ''::text))) = 'moses hq'::text
        OR lower(btrim(COALESCE(a.account_name, ''::text))) = 'moses hq'::text
        OR lower(btrim(COALESCE(g.group_name, ga.group_name, ''::text))) = 'global hq'::text
        OR v.home_account_id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152'::uuid
      THEN 'Moses HQ'::text
      ELSE NULL::text
    END
  ) AS store_name,
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
    -- ADR-001 Rule 2: Derive Hired count strictly from active plantilla
    WHEN COALESCE(pls.active_plantilla_count, 0::bigint)::numeric >= GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric) THEN 'Hired'::text
    WHEN COALESCE(v.has_pending_closure, false) = true
      OR lower(COALESCE(v.closure_request_status, ''::text)) = 'pending'::text
      OR (lower(COALESCE(v.status, ''::text)) = ANY (ARRAY['closure'::text, 'for_closure'::text]))
      OR (
        EXISTS (
          SELECT 1
          FROM public.vacancy_closure_requests vcr
          WHERE vcr.vacancy_vcode = v.vcode
            AND lower(vcr.status) = 'pending'::text
        )
      ) THEN 'For Closure'::text
    WHEN (COALESCE(s.confirmed_onboard_count, 0::bigint) + COALESCE(s.active_applicant_count, 0::bigint))::numeric < GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric) THEN 'Open'::text
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
  -- 1. HRCO User ID (User Management as authoritative Source of Truth)
  COALESCE(
    (
      SELECT us_acc.user_id
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = COALESCE(v.account_id, a.id)
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT us_grp.user_id
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id)
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    v.hrco_user_id,
    st.hrco_user_id,
    a.hrco_user_id
  ) AS hrco_user_id,
  -- 2. HRCO Name (User Management as authoritative Source of Truth)
  COALESCE(
    (
      SELECT up_sc.full_name
      FROM public.user_scopes us_acc
      JOIN public.users_profile up_sc ON up_sc.id = us_acc.user_id
      JOIN public.roles r_sc ON r_sc.id = up_sc.role_id
      WHERE us_acc.account_id = COALESCE(v.account_id, a.id)
        AND r_sc.role_name = 'HRCO'::text
        AND up_sc.is_active = true
        AND up_sc.archived_at IS NULL
      ORDER BY us_acc.created_at
      LIMIT 1
    ),
    (
      SELECT up_scg.full_name
      FROM public.user_scopes us_grp
      JOIN public.users_profile up_scg ON up_scg.id = us_grp.user_id
      JOIN public.roles r_scg ON r_scg.id = up_scg.role_id
      WHERE us_grp.group_id = COALESCE(v.group_id, a.group_id)
        AND us_grp.account_id IS NULL
        AND r_scg.role_name = 'HRCO'::text
        AND up_scg.is_active = true
        AND up_scg.archived_at IS NULL
      ORDER BY us_grp.created_at
      LIMIT 1
    ),
    CASE
      WHEN up_hrco.is_active = true AND r_hrco.role_name = 'HRCO'::text THEN up_hrco.full_name
      ELSE NULL::text
    END,
    CASE
      WHEN up_st_hrco.is_active = true AND r_st_hrco.role_name = 'HRCO'::text THEN up_st_hrco.full_name
      ELSE NULL::text
    END,
    CASE
      WHEN up_a_hrco.is_active = true AND r_a_hrco.role_name = 'HRCO'::text THEN up_a_hrco.full_name
      ELSE NULL::text
    END,
    NULLIF(btrim(v.hrco_name), ''::text)
  ) AS hrco_name,
  COALESCE(s.has_recent_hire, false) AS has_recent_hire,
  COALESCE(pls.active_plantilla_count, 0::bigint)::integer AS hc_filled,
  GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer AS hc_total,
  format(
    '%s/%s'::text,
    COALESCE(pls.active_plantilla_count, 0::bigint),
    GREATEST(COALESCE(v.required_headcount, 1::numeric), 1::numeric)::integer
  ) AS hc_display,
  COALESCE(ss.hr_processing_count, 0::bigint)::integer AS hr_processing_count,
  COALESCE(v.is_pool_vacancy, false) AS is_pool_vacancy,
  COALESCE(v.affects_required_hc, true) AS affects_required_hc
FROM public.vacancies v
LEFT JOIN applicant_stats s ON s.vacancy_vcode = v.vcode
LEFT JOIN plantilla_stats pls ON pls.vcode = v.vcode
LEFT JOIN slot_stats ss ON ss.vcode = v.vcode
LEFT JOIN public.accounts a ON a.id = v.account_id
LEFT JOIN public.stores st ON st.id = v.store_id
LEFT JOIN public.groups g ON g.id = v.group_id
LEFT JOIN public.groups ga ON ga.id = a.group_id
LEFT JOIN public.users_profile up_hrco ON up_hrco.id = v.hrco_user_id
LEFT JOIN public.roles r_hrco ON r_hrco.id = up_hrco.role_id
LEFT JOIN public.users_profile up_st_hrco ON up_st_hrco.id = st.hrco_user_id
LEFT JOIN public.roles r_st_hrco ON r_st_hrco.id = up_st_hrco.role_id
LEFT JOIN public.users_profile up_a_hrco ON up_a_hrco.id = a.hrco_user_id
LEFT JOIN public.roles r_a_hrco ON r_a_hrco.id = up_a_hrco.role_id
WHERE v.deleted_at IS NULL;

ALTER VIEW public.vw_vacancy_list OWNER TO postgres;
GRANT SELECT ON public.vw_vacancy_list TO authenticated, service_role;


-- ============================================================================
-- 3. Update public.fn_amr_execute_transfer (Roving Slot Support)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_amr_execute_transfer(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_req     public.applicant_movement_requests%ROWTYPE;
  v_src_status text;
  v_tgt_status text;
  v_tgt_open_count int;
  v_blocked_statuses text[] := ARRAY['Confirmed Onboard', 'Hired'];
  v_actor_name text;
  v_src_slot_id uuid;
  v_tgt_slot_id uuid;
  v_actor_auth_user_id uuid;
BEGIN
  SELECT * INTO v_req
  FROM public.applicant_movement_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_NOT_FOUND: Request % not found', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Revalidate source applicant
  SELECT status, slot_id INTO v_src_status, v_src_slot_id
  FROM public.applicants
  WHERE id = v_req.source_applicant_id;

  IF v_src_status = ANY(v_blocked_statuses) THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Source applicant is in a terminal status (%)', v_src_status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Revalidate target vacancy is still open and not reserved by another request
  SELECT
    COALESCE(open_count, 0)
  INTO v_tgt_open_count
  FROM public.vw_slot_derived_vacancy_shadow
  WHERE legacy_vcode = v_req.target_vacancy_vcode;

  -- Fallback to vacancies table if shadow view not available
  IF NOT FOUND THEN
    SELECT CASE WHEN status = 'Open' THEN 1 ELSE 0 END
    INTO v_tgt_open_count
    FROM public.vacancies
    WHERE vcode = v_req.target_vacancy_vcode
      AND deleted_at IS NULL;
  END IF;

  IF COALESCE(v_tgt_open_count, 0) < 1 THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Target vacancy % has no open slots at time of execution', v_req.target_vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Find open slot: prefer stationary slots, but support roving slots if target vacancy is roving
  SELECT id INTO v_tgt_slot_id
  FROM public.plantilla_slots
  WHERE legacy_vcode = v_req.target_vacancy_vcode
    AND slot_status = 'open'
    AND (
      COALESCE(is_roving, false) = false
      OR NOT EXISTS (
        SELECT 1 FROM public.plantilla_slots ps_stat
        WHERE ps_stat.legacy_vcode = v_req.target_vacancy_vcode
          AND ps_stat.slot_status = 'open'
          AND COALESCE(ps_stat.is_roving, false) = false
      )
    )
  ORDER BY
    CASE WHEN COALESCE(is_roving, false) = false THEN 0 ELSE 1 END,
    slot_ordinal NULLS LAST,
    created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  -- Check for competing reservation from another request
  IF EXISTS (
    SELECT 1
    FROM public.applicant_movement_reservations res
    JOIN public.applicant_movement_requests r2 ON r2.id = res.request_id
    WHERE res.reserved_vcode = v_req.target_vacancy_vcode
      AND res.released_at IS NULL
      AND res.request_id <> p_request_id
      AND r2.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Target vacancy % is reserved by another pending request', v_req.target_vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Execute: move applicant to target vacancy
  UPDATE public.applicants
  SET
    vacancy_vcode   = v_req.target_vacancy_vcode,
    slot_id         = COALESCE(v_tgt_slot_id, slot_id),
    updated_at      = now()
  WHERE id = v_req.source_applicant_id;

  IF v_src_slot_id IS NOT NULL THEN
    PERFORM public.fn_release_applicant_slot(v_src_slot_id, COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by));
  ELSE
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v_req.source_vacancy_vcode,
      p_performed_by => COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
      p_source_fn    => 'fn_amr_execute_transfer.source'
    );
  END IF;

  IF v_tgt_slot_id IS NOT NULL THEN
    PERFORM public.fn_set_slot_status(
      p_slot_id      => v_tgt_slot_id,
      p_new_status   => 'pipeline',
      p_reason_code  => NULL,
      p_performed_by => COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
      p_remarks      => 'Applicant Movement Request ' || v_req.request_number || ': target vacancy claimed'
    );
  ELSE
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v_req.target_vacancy_vcode,
      p_performed_by => COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
      p_source_fn    => 'fn_amr_execute_transfer.target'
    );
  END IF;

  SELECT auth_user_id, full_name INTO v_actor_auth_user_id, v_actor_name
  FROM public.users_profile
  WHERE id = COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by);

  INSERT INTO public.applicant_status_history (
    applicant_id, from_status, to_status, remarks, changed_by, changed_at,
    source_module, update_type, changed_field, old_value, new_value,
    changed_by_name
  ) VALUES (
    v_req.source_applicant_id,
    v_src_status,
    v_src_status,
    'Applicant Movement Request ' || v_req.request_number || ': Transfer ' ||
      v_req.source_vacancy_vcode || ' → ' || v_req.target_vacancy_vcode ||
      '. Reason: ' || v_req.reason,
    COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
    now(),
    'vacancy',
    'status_change',
    'vacancy_vcode',
    v_req.source_vacancy_vcode,
    v_req.target_vacancy_vcode,
    COALESCE(v_actor_name, 'System')
  );

  INSERT INTO public.audit_logs (
    actor_id, module, action, record_id, old_data, new_data, role
  ) VALUES (
    COALESCE(v_actor_auth_user_id, auth.uid()),
    'Applicant Movement',
    'UPDATE',
    p_request_id,
    jsonb_build_object(
      'applicant_id', v_req.source_applicant_id,
      'source_vcode', v_req.source_vacancy_vcode
    ),
    jsonb_build_object(
      'request_number', v_req.request_number,
      'movement_type', 'TRANSFER',
      'applicant_id', v_req.source_applicant_id,
      'target_vcode', v_req.target_vacancy_vcode,
      'requested_by', v_req.requested_by_name,
      'reason', v_req.reason
    ),
    COALESCE(v_req.requested_by_role, 'Applicant Movement')
  );

  -- Stamp execution time
  UPDATE public.applicant_movement_requests
  SET executed_at = now(),
      updated_at  = now()
  WHERE id = p_request_id;
END;
$$;


-- ============================================================================
-- 4. Update public.fn_sync_vacancy_slot_open_pipeline (Roving Support)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_sync_vacancy_slot_open_pipeline(
  p_vcode text,
  p_performed_by uuid DEFAULT NULL::uuid,
  p_source_fn text DEFAULT 'unknown'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
    -- Transition all unassigned non-closed pipeline slots for this vcode back to 'open'
    FOR r_slot IN
      SELECT id, slot_status
      FROM public.plantilla_slots
      WHERE legacy_vcode = p_vcode
        AND (
          is_roving = false
          OR NOT EXISTS (
            SELECT 1 FROM public.plantilla_slots ps_stat
            WHERE ps_stat.legacy_vcode = p_vcode AND ps_stat.is_roving = false
          )
        )
        AND slot_status = 'pipeline'
        AND slot_status NOT IN ('hr_processing', 'occupied', 'filled')
        AND current_occupant_plantilla_id IS NULL
        AND closed_at IS NULL
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
        AND (
          is_roving = false
          OR NOT EXISTS (
            SELECT 1 FROM public.plantilla_slots ps_stat
            WHERE ps_stat.legacy_vcode = p_vcode AND ps_stat.is_roving = false
          )
        )
        AND slot_status = 'open'
        AND slot_status NOT IN ('hr_processing', 'occupied', 'filled')
        AND closed_at IS NULL
      ORDER BY
        CASE WHEN is_roving = false THEN 0 ELSE 1 END,
        slot_ordinal ASC, created_at ASC, id ASC
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
$function$;

NOTIFY pgrst, 'reload schema';
