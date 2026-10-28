BEGIN;

-- ============================================================================
-- Part 3 (Step 6 Code Fix) — ohm#4x7n2k9w (Phase 5 REVISED)
-- 1. fn_set_slot_status:
--    - Clear closed_at, closed_by, and closure_reason_code to NULL whenever
--      p_new_status = 'open' (e.g. reopened from closed/hc_reduced via
--      HC_READD / COVERAGE_STORE_REMOVED / COVERAGE_GROUP_DISSOLVED, or
--      released back to open).
--    - Do NOT clear qa_archive_batch_id (read by fn_qa_rollback_operational_data_reset
--      and fn_rollback_archive_batch).
-- 2. fn_sync_vacancy_slot_open_pipeline:
--    - Add AND closed_at IS NULL on both the 'open' release loop and the
--      'pipeline' claim loop.
--    - Add deterministic ORDER BY slot_ordinal ASC, created_at ASC, id ASC
--      on the 'open' -> 'pipeline' claim loop.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_set_slot_status(
  p_slot_id uuid,
  p_new_status text,
  p_reason_code text DEFAULT NULL::text,
  p_performed_by uuid DEFAULT NULL::uuid,
  p_remarks text DEFAULT NULL::text,
  p_occupant_plantilla_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_slot           record;
  v_from_status    text;
  v_action_type    text;
  v_history_id     uuid;
  v_transition_ok  boolean := false;
  v_blocked_reason text;
BEGIN
  IF p_slot_id IS NULL THEN
    RAISE EXCEPTION 'fn_set_slot_status: p_slot_id is required';
  END IF;

  IF p_new_status NOT IN (
    'open', 'pipeline', 'hr_processing', 'occupied', 'filled', 'closed', 'hc_reduced'
  ) THEN
    RAISE EXCEPTION 'fn_set_slot_status: unknown status value ''%''', p_new_status;
  END IF;

  SELECT * INTO v_slot
  FROM public.plantilla_slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_set_slot_status: slot % not found', p_slot_id;
  END IF;

  v_from_status := v_slot.slot_status;

  IF v_from_status = p_new_status THEN
    RETURN jsonb_build_object(
      'status',      'no_op',
      'slot_id',     p_slot_id,
      'from_status', v_from_status,
      'to_status',   p_new_status
    );
  END IF;

  -- Transition matrix
  -- ohm#7k2d9f4a: terminal states may be re-opened ONLY through an explicit,
  -- named re-add / coverage-conversion workflow (reason-code gated).
  IF v_from_status IN ('closed', 'hc_reduced') AND p_new_status = 'open'
     AND p_reason_code IN ('HC_READD', 'COVERAGE_STORE_REMOVED', 'COVERAGE_GROUP_DISSOLVED') THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status IN ('closed', 'hc_reduced') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      '%s is terminal under automation; re-opening a slot requires an HC re-add workflow',
      v_from_status
    );

  ELSIF v_from_status = 'open' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'pipeline';

  ELSIF v_from_status = 'open' AND p_new_status IN ('occupied', 'filled') THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := format('%s→%s (transfer-in) requires p_occupant_plantilla_id', v_from_status, p_new_status);
    ELSE
      v_transition_ok := true;
      v_action_type   := 'transfer_in';
    END IF;

  ELSIF v_from_status = 'open' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'open' AND p_new_status = 'hc_reduced' THEN
    v_transition_ok := true;
    v_action_type   := 'hc_reduced';

  ELSIF v_from_status = 'open' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'import_reserved';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'hr_processing' THEN
    v_transition_ok := true;
    v_action_type   := 'hr_processing';

  ELSIF v_from_status = 'pipeline' AND p_new_status IN ('occupied', 'filled') THEN
    v_transition_ok  := false;
    v_blocked_reason := 'pipeline→occupied is blocked: slot must pass through hr_processing first';

  ELSIF v_from_status = 'pipeline' AND p_new_status = 'closed' THEN
    v_transition_ok := true;
    v_action_type   := 'closed';

  ELSIF v_from_status = 'hr_processing' AND p_new_status IN ('occupied', 'filled') THEN
    IF p_occupant_plantilla_id IS NULL THEN
      v_transition_ok  := false;
      v_blocked_reason := format('%s→%s requires p_occupant_plantilla_id', v_from_status, p_new_status);
    ELSE
      v_transition_ok := true;
      v_action_type   := 'occupied';
    END IF;

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := 'reopened';

  ELSIF v_from_status = 'hr_processing' AND p_new_status = 'pipeline' THEN
    v_transition_ok := true;
    v_action_type   := 'import_rejected';

  ELSIF v_from_status IN ('occupied', 'filled') AND p_new_status = 'open' THEN
    v_transition_ok := true;
    v_action_type   := CASE p_reason_code
                          WHEN 'TRANSFER_OUT' THEN 'transfer_out'
                          WHEN 'BACKOUT' THEN 'backout_released'
                          WHEN 'COVERAGE_GROUP_CREATED' THEN 'employee_separated'
                          WHEN 'COVERAGE_STORE_REMOVED' THEN 'coverage_store_removed'
                          ELSE 'resigned'
                        END;

  ELSIF v_from_status IN ('occupied', 'filled') AND p_new_status IN ('pipeline', 'hr_processing') THEN
    v_transition_ok  := false;
    v_blocked_reason := format(
      '%s→%s is blocked: occupant must separate first (%s→open), '
      'then the slot re-enters recruitment', v_from_status, p_new_status, v_from_status
    );

  ELSE
    v_transition_ok  := false;
    v_blocked_reason := format('%s→%s is not a supported transition', v_from_status, p_new_status);
  END IF;

  IF NOT v_transition_ok THEN
    RETURN jsonb_build_object(
      'status',         'blocked',
      'slot_id',        p_slot_id,
      'from_status',    v_from_status,
      'to_status',      p_new_status,
      'blocked_reason', v_blocked_reason
    );
  END IF;

  -- Apply transition
  UPDATE public.plantilla_slots
  SET
    slot_status                   = p_new_status,
    current_occupant_plantilla_id = CASE
      WHEN p_new_status IN ('occupied', 'filled') THEN p_occupant_plantilla_id
      WHEN p_new_status IN ('open', 'closed', 'hc_reduced') THEN NULL
      ELSE current_occupant_plantilla_id
    END,
    closed_at                     = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN now()
      WHEN p_new_status = 'open' THEN NULL
      ELSE closed_at
    END,
    closed_by                     = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN p_performed_by
      WHEN p_new_status = 'open' THEN NULL
      ELSE closed_by
    END,
    closure_reason_code           = CASE
      WHEN p_new_status IN ('closed', 'hc_reduced') THEN p_reason_code
      WHEN p_new_status = 'open' THEN NULL
      ELSE closure_reason_code
    END,
    updated_at                    = now(),
    updated_by                    = p_performed_by
  WHERE id = p_slot_id;

  INSERT INTO public.slot_history (
    slot_id,
    account_id,
    action_type,
    old_value,
    new_value,
    reason_code,
    performed_by,
    remarks
  ) VALUES (
    p_slot_id,
    v_slot.account_id,
    v_action_type,
    v_from_status,
    p_new_status,
    p_reason_code,
    p_performed_by,
    p_remarks
  )
  RETURNING id INTO v_history_id;

  RETURN jsonb_build_object(
    'status',      'ok',
    'slot_id',     p_slot_id,
    'from_status', v_from_status,
    'to_status',   p_new_status,
    'action_type', v_action_type,
    'reason_code', p_reason_code,
    'history_id',  v_history_id
  );
END;
$function$;


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
        AND is_roving = false
        AND slot_status = 'pipeline'
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
        AND is_roving = false
        AND slot_status = 'open'
        AND closed_at IS NULL
      ORDER BY slot_ordinal ASC, created_at ASC, id ASC
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

COMMIT;
