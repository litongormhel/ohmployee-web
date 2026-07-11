-- Fix AMR audit logs actor ID foreign key constraint error.
--
-- audit_logs.actor_id references auth.users(id), while applicant_movement_requests
-- approval/requester columns store the application profile id (users_profile.id).
-- We look up users_profile.auth_user_id using the profile id and insert that into audit_logs.actor_id.
--
-- Also adds re-execution capability to approve_applicant_movement_request for already approved requests with execution errors.

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

  SELECT id INTO v_tgt_slot_id
  FROM public.plantilla_slots
  WHERE legacy_vcode = v_req.target_vacancy_vcode
    AND slot_status = 'open'
    AND COALESCE(is_roving, false) = false
  ORDER BY slot_ordinal NULLS LAST, created_at
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
    v_actor_name
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


CREATE OR REPLACE FUNCTION public.fn_amr_execute_swap(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_req          public.applicant_movement_requests%ROWTYPE;
  v_src_status   text;
  v_tgt_status   text;
  v_blocked_statuses text[] := ARRAY['Confirmed Onboard', 'Hired'];
  v_actor_id     uuid;
  v_actor_name   text;
  v_src_slot_id  uuid;
  v_tgt_slot_id  uuid;
  v_actor_auth_user_id uuid;
BEGIN
  SELECT * INTO v_req
  FROM public.applicant_movement_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_NOT_FOUND: Request % not found', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_req.target_applicant_id IS NULL THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: SWAP request % has no target applicant', p_request_id
      USING ERRCODE = 'check_violation';
  END IF;

  -- Revalidate both applicants
  SELECT status, slot_id INTO v_src_status, v_src_slot_id
  FROM public.applicants WHERE id = v_req.source_applicant_id;

  SELECT status, slot_id INTO v_tgt_status, v_tgt_slot_id
  FROM public.applicants WHERE id = v_req.target_applicant_id;

  IF v_src_status = ANY(v_blocked_statuses) THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Source applicant is in a terminal status (%)', v_src_status
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_tgt_status = ANY(v_blocked_statuses) THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Target applicant is in a terminal status (%)', v_tgt_status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Execute: atomic swap (temp VCODE to avoid constraint conflicts)
  UPDATE public.applicants
  SET vacancy_vcode = '_amr_swap_temp_' || p_request_id::text,
      slot_id       = NULL,
      updated_at    = now()
  WHERE id = v_req.source_applicant_id;

  UPDATE public.applicants
  SET vacancy_vcode = v_req.source_vacancy_vcode,
      slot_id       = v_src_slot_id,
      updated_at    = now()
  WHERE id = v_req.target_applicant_id;

  UPDATE public.applicants
  SET vacancy_vcode = v_req.target_vacancy_vcode,
      slot_id       = v_tgt_slot_id,
      updated_at    = now()
  WHERE id = v_req.source_applicant_id;

  v_actor_id := COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by);
  SELECT auth_user_id, full_name INTO v_actor_auth_user_id, v_actor_name
  FROM public.users_profile
  WHERE id = v_actor_id;

  INSERT INTO public.applicant_status_history (
    applicant_id, from_status, to_status, remarks, changed_by, changed_at,
    source_module, update_type, changed_field, old_value, new_value,
    changed_by_name
  ) VALUES
  (
    v_req.source_applicant_id,
    v_src_status,
    v_src_status,
    'Applicant Movement Request ' || v_req.request_number || ': Swap ' ||
      v_req.source_vacancy_vcode || ' ↔ ' || v_req.target_vacancy_vcode ||
      '. Reason: ' || v_req.reason,
    v_actor_id,
    now(),
    'vacancy',
    'status_change',
    'vacancy_vcode',
    v_req.source_vacancy_vcode,
    v_req.target_vacancy_vcode,
    v_actor_name
  ),
  (
    v_req.target_applicant_id,
    v_tgt_status,
    v_tgt_status,
    'Applicant Movement Request ' || v_req.request_number || ': Swap ' ||
      v_req.target_vacancy_vcode || ' ↔ ' || v_req.source_vacancy_vcode ||
      '. Reason: ' || v_req.reason,
    v_actor_id,
    now(),
    'vacancy',
    'status_change',
    'vacancy_vcode',
    v_req.target_vacancy_vcode,
    v_req.source_vacancy_vcode,
    v_actor_name
  );

  INSERT INTO public.audit_logs (
    actor_id, module, action, record_id, old_data, new_data, role
  ) VALUES (
    COALESCE(v_actor_auth_user_id, auth.uid()),
    'Applicant Movement',
    'UPDATE',
    p_request_id,
    jsonb_build_object(
      'source_applicant_id', v_req.source_applicant_id,
      'source_vcode', v_req.source_vacancy_vcode,
      'target_applicant_id', v_req.target_applicant_id,
      'target_vcode', v_req.target_vacancy_vcode
    ),
    jsonb_build_object(
      'request_number', v_req.request_number,
      'movement_type', 'SWAP',
      'source_applicant_id', v_req.source_applicant_id,
      'source_new_vcode', v_req.target_vacancy_vcode,
      'target_applicant_id', v_req.target_applicant_id,
      'target_new_vcode', v_req.source_vacancy_vcode,
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


CREATE OR REPLACE FUNCTION public.approve_applicant_movement_request(
  p_request_id uuid,
  p_note       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me              public.users_profile%ROWTYPE;
  v_me_role_level   int;
  v_req             public.applicant_movement_requests%ROWTYPE;
  v_stages          text[];
  v_current_idx     int;
  v_next_stage      text;
  v_is_final        bool;
  v_next_approver   public.users_profile%ROWTYPE;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────
  SELECT * INTO v_me FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_FORBIDDEN: User not found' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_level INTO v_me_role_level
  FROM public.roles r WHERE r.id = v_me.role_id;

  -- ── Fetch request ─────────────────────────────────────────
  SELECT * INTO v_req FROM public.applicant_movement_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_NOT_FOUND: Request % not found', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- ── Support Re-execution of Failed Approved Requests ──────
  IF v_req.status = 'approved' AND v_req.execution_error IS NOT NULL THEN
    IF NOT (
      i_have_full_access()
      OR v_me.id = COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by)
    ) THEN
      RAISE EXCEPTION 'AMR_FORBIDDEN: Only SA/HA or the original approver can re-execute'
        USING ERRCODE = '42501';
    END IF;

    -- Clear error first
    UPDATE public.applicant_movement_requests
    SET execution_error = NULL, updated_at = now()
    WHERE id = p_request_id;

    BEGIN
      IF v_req.movement_type = 'TRANSFER' THEN
        PERFORM public.fn_amr_execute_transfer(p_request_id);
      ELSE
        PERFORM public.fn_amr_execute_swap(p_request_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Log execution failure but don't roll back approval
      UPDATE public.applicant_movement_requests
      SET execution_error = SQLERRM, updated_at = now()
      WHERE id = p_request_id;

      INSERT INTO public.applicant_movement_request_history (
        request_id, from_status, to_status, action,
        actor_id, actor_name, note
      ) VALUES (
        p_request_id, 'approved', 'approved', 'execution_failed',
        v_me.id, v_me.full_name,
        'Re-execution failed: ' || SQLERRM
      );
    END;

    -- Release reservation (idempotent)
    PERFORM public.fn_amr_release_reservation(p_request_id, 'approved');

    RETURN jsonb_build_object(
      'request_id',   p_request_id,
      'status',       'approved',
      'next_stage',   NULL,
      'is_final',     true,
      're_executed',  true
    );
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'AMR_INVALID: Request is not in pending status (current: %)', v_req.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- ── Authorize current approver ────────────────────────────
  CASE v_req.approval_stage
    WHEN 'encoder' THEN
      IF v_me_role_level <> 30 THEN
        IF NOT i_have_full_access() THEN
          RAISE EXCEPTION 'AMR_FORBIDDEN: Encoder stage requires Encoder role (or SA/HA override)'
            USING ERRCODE = '42501';
        END IF;
      END IF;
    WHEN 'ha' THEN
      IF NOT i_have_full_access() THEN
        RAISE EXCEPTION 'AMR_FORBIDDEN: HA stage requires Head Admin or Super Admin'
          USING ERRCODE = '42501';
      END IF;
    WHEN 'sa' THEN
      IF NOT (v_me_role_level >= 100) THEN
        RAISE EXCEPTION 'AMR_FORBIDDEN: SA stage requires Super Admin'
          USING ERRCODE = '42501';
      END IF;
    ELSE
      -- NULL (direct) — requester was SA/HA/same-account Encoder
      -- Only SA/HA can approve a "direct" request
      IF NOT i_have_full_access() THEN
        RAISE EXCEPTION 'AMR_FORBIDDEN: This request was submitted as direct approval — only SA/HA can confirm'
          USING ERRCODE = '42501';
      END IF;
  END CASE;

  -- ── Recalculate stages to find next ───────────────────────
  v_stages := public.fn_amr_determine_stages(
    v_req.requested_by_role_level,
    v_req.source_group_id,
    v_req.target_group_id,
    v_req.source_account_id,
    v_req.target_account_id
  );

  -- Find current index
  v_current_idx := array_position(v_stages, v_req.approval_stage);

  -- Next stage (if any)
  IF v_current_idx IS NULL OR v_current_idx >= array_length(v_stages, 1) THEN
    v_next_stage := NULL;
    v_is_final   := true;
  ELSE
    v_next_stage := v_stages[v_current_idx + 1];
    v_is_final   := false;
  END IF;

  -- If no stages array at all (direct), treat as final
  IF array_length(v_stages, 1) IS NULL THEN
    v_next_stage := NULL;
    v_is_final   := true;
  END IF;

  -- ── Stamp current stage approval ──────────────────────────
  UPDATE public.applicant_movement_requests
  SET
    approval_stage           = v_next_stage,
    status                   = CASE WHEN v_is_final THEN 'approved' ELSE 'pending' END,
    encoder_approved_by      = CASE WHEN v_req.approval_stage = 'encoder' THEN v_me.id ELSE encoder_approved_by END,
    encoder_approved_at      = CASE WHEN v_req.approval_stage = 'encoder' THEN now() ELSE encoder_approved_at END,
    ha_approved_by           = CASE WHEN v_req.approval_stage = 'ha' OR (v_req.approval_stage IS NULL AND i_have_full_access() AND NOT (v_me_role_level >= 100)) THEN v_me.id ELSE ha_approved_by END,
    ha_approved_at           = CASE WHEN v_req.approval_stage = 'ha' OR (v_req.approval_stage IS NULL AND i_have_full_access() AND NOT (v_me_role_level >= 100)) THEN now() ELSE ha_approved_at END,
    sa_approved_by           = CASE WHEN v_req.approval_stage = 'sa' OR (v_req.approval_stage IS NULL AND v_me_role_level >= 100) THEN v_me.id ELSE sa_approved_by END,
    sa_approved_at           = CASE WHEN v_req.approval_stage = 'sa' OR (v_req.approval_stage IS NULL AND v_me_role_level >= 100) THEN now() ELSE sa_approved_at END,
    updated_at               = now()
  WHERE id = p_request_id;

  -- ── Write history ─────────────────────────────────────────
  INSERT INTO public.applicant_movement_request_history (
    request_id, from_status, to_status, from_stage, to_stage,
    action, actor_id, actor_name, actor_role, actor_role_level, note
  ) VALUES (
    p_request_id,
    'pending',
    CASE WHEN v_is_final THEN 'approved' ELSE 'pending' END,
    v_req.approval_stage,
    v_next_stage,
    CASE WHEN v_is_final THEN 'approved_final' ELSE 'approved_stage' END,
    v_me.id,
    v_me.full_name,
    (SELECT role_name FROM public.roles WHERE id = v_me.role_id),
    v_me_role_level,
    COALESCE(p_note, 'Stage approved by ' || v_me.full_name)
  );

  -- ── Execute movement if final approval ────────────────────
  IF v_is_final THEN
    BEGIN
      IF v_req.movement_type = 'TRANSFER' THEN
        PERFORM public.fn_amr_execute_transfer(p_request_id);
      ELSE
        PERFORM public.fn_amr_execute_swap(p_request_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Log execution failure but don't roll back approval
      UPDATE public.applicant_movement_requests
      SET execution_error = SQLERRM, updated_at = now()
      WHERE id = p_request_id;

      INSERT INTO public.applicant_movement_request_history (
        request_id, from_status, to_status, action,
        actor_id, actor_name, note
      ) VALUES (
        p_request_id, 'approved', 'approved', 'execution_failed',
        v_me.id, v_me.full_name,
        'Execution failed: ' || SQLERRM
      );
    END;

    -- Release reservation
    PERFORM public.fn_amr_release_reservation(p_request_id, 'approved');

    -- Notify requester of approval
    PERFORM public.notify_user(
      (SELECT auth_user_id FROM public.users_profile WHERE id = v_req.requested_by),
      v_req.requested_by_role,
      'Applicant Movement Request Approved — ' || v_req.request_number,
      'Your ' || v_req.movement_type || ' request for vacancy ' || v_req.target_vacancy_vcode || ' has been approved and executed.',
      'approved',
      'applicant_movement',
      'applicant_movement',
      p_request_id::text,
      '/requests/applicant-movement/' || p_request_id::text,
      NULL
    );

  ELSE
    -- Notify next stage approver
    DECLARE
      v_next_role text := CASE v_next_stage
        WHEN 'encoder' THEN 'Encoder'
        WHEN 'ha'      THEN 'Head Admin'
        WHEN 'sa'      THEN 'Super Admin'
      END;
    BEGIN
      FOR v_next_approver IN
        SELECT up.* FROM public.users_profile up
        JOIN public.roles r ON r.id = up.role_id
        WHERE r.role_name = v_next_role
          AND up.is_active = true
          AND up.auth_user_id IS NOT NULL
          AND (v_next_role NOT IN ('Encoder') OR (
            up.group_id = v_req.source_group_id
            OR up.group_id = v_req.target_group_id
          ))
      LOOP
        PERFORM public.notify_user(
          v_next_approver.auth_user_id,
          v_next_role,
          'Action Required: Applicant Movement Request — ' || v_req.request_number,
          'Encoder has approved stage. Your review is now required for ' || v_req.movement_type || ' request.',
          'approval_required',
          'applicant_movement',
          'applicant_movement',
          p_request_id::text,
          '/requests/applicant-movement/' || p_request_id::text,
          NULL
        );
      END LOOP;
    END;
  END IF;

  RETURN jsonb_build_object(
    'request_id',   p_request_id,
    'status',       CASE WHEN v_is_final THEN 'approved' ELSE 'pending' END,
    'next_stage',   v_next_stage,
    'is_final',     v_is_final
  );
END;
$$;
