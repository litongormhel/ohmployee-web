-- Migration: 20262606000200_allow_ops_revise_headcount_quota.sql
-- Created: 2026-11-26T04:06:50.631Z
-- Description: Allow Ops roles (OM, TL, ATL, HRCO) to revise headcount quota in revise_vcode_headcount_quota

BEGIN;

CREATE OR REPLACE FUNCTION public.revise_vcode_headcount_quota(
  p_vcode             text,
  p_new_target        integer,
  p_justification     text,
  p_source_request_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_role        text := public.get_my_role();
  v_caller_id          uuid := public.get_current_profile_id();
  v_vacancy            public.vacancies%ROWTYPE;
  v_position_id        uuid;
  v_current_quota      integer;
  v_delta              integer;
  v_occupied_count     integer := 0;
  v_hr_proc_count      integer := 0;
  v_pipeline_count     integer := 0;
  v_safety_floor       integer := 0;
  v_open_slots         uuid[];
  v_slot_id            uuid;
  v_new_slot_id        uuid;
  v_max_ordinal        smallint := 0;
  v_res                jsonb;
  i                    integer;
BEGIN
  -- 1. Resolve Profile and RBAC Guard (Allowed: Super Admin, Head Admin, Encoder, OM, TL, ATL, HRCO)
  IF v_caller_id IS NULL THEN
    v_caller_id := public.get_my_profile_id();
  END IF;

  IF v_caller_role IS NULL THEN
    SELECT up.role, up.id INTO v_caller_role, v_caller_id
    FROM public.users_profile up
    WHERE up.auth_user_id = auth.uid()
      AND up.is_active = true
    LIMIT 1;
  END IF;

  IF v_caller_role NOT IN ('Super Admin', 'Head Admin', 'Encoder', 'Operations Manager', 'OM', 'TL', 'ATL', 'HRCO') THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only Ops, Data Team, and Admin roles may revise headcount quota.'
      USING ERRCODE = '42501';
  END IF;

  IF v_caller_id IS NULL THEN
    SELECT id INTO v_caller_id
    FROM public.users_profile
    WHERE role IN ('Super Admin', 'Head Admin', 'Encoder', 'Operations Manager', 'OM', 'TL', 'ATL', 'HRCO')
      AND is_active = true
    ORDER BY role_level DESC
    LIMIT 1;
  END IF;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: No active profile found for revision audit.'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Input Validation
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE EXCEPTION 'VCODE_REQUIRED: VCode must be provided.'
      USING ERRCODE = '22023';
  END IF;

  IF p_new_target < 1 THEN
    RAISE EXCEPTION 'INVALID_TARGET: Target quota must be at least 1.'
      USING ERRCODE = '22023';
  END IF;

  IF p_justification IS NULL OR length(btrim(p_justification)) < 5 THEN
    RAISE EXCEPTION 'JUSTIFICATION_REQUIRED: A valid justification (minimum 5 characters) is required for quota revisions.'
      USING ERRCODE = '22023';
  END IF;

  -- 3. Lock and retrieve target vacancy
  SELECT * INTO v_vacancy
  FROM public.vacancies
  WHERE vcode = p_vcode
    AND deleted_at IS NULL
  FOR UPDATE;

  IF v_vacancy.id IS NULL THEN
    RAISE EXCEPTION 'VACANCY_NOT_FOUND: VCode % does not exist.', p_vcode
      USING ERRCODE = 'P0002';
  END IF;

  v_current_quota := COALESCE(v_vacancy.required_headcount, 1);
  v_delta := p_new_target - v_current_quota;

  -- 4. Calculate Current Load & Non-Negotiable Safety Floor
  SELECT 
    COUNT(*) FILTER (WHERE slot_status IN ('occupied', 'filled')),
    COUNT(*) FILTER (WHERE slot_status = 'hr_processing'),
    COUNT(*) FILTER (WHERE slot_status = 'pipeline')
  INTO v_occupied_count, v_hr_proc_count, v_pipeline_count
  FROM public.plantilla_slots
  WHERE legacy_vcode = p_vcode;

  v_safety_floor := v_occupied_count + v_hr_proc_count + v_pipeline_count;

  -- Safety Floor check: New target cannot be lower than occupied and processing commitments.
  IF p_new_target < v_safety_floor THEN
    RAISE EXCEPTION 'QUOTA_REDUCTION_BLOCKED: New target cannot be lower than occupied and processing commitments (Floor: %, Target: %, Occupied: %, HR Processing: %, Pipeline: %)',
      v_safety_floor, p_new_target, v_occupied_count, v_hr_proc_count, v_pipeline_count
      USING ERRCODE = '22023';
  END IF;

  -- 5. Reductions (new < current)
  IF v_delta < 0 THEN
    SELECT ARRAY(
      SELECT id FROM public.plantilla_slots
      WHERE legacy_vcode = p_vcode
        AND slot_status = 'open'
      ORDER BY slot_ordinal DESC, created_at DESC
      LIMIT abs(v_delta)
      FOR UPDATE
    ) INTO v_open_slots;

    IF COALESCE(array_length(v_open_slots, 1), 0) < abs(v_delta) THEN
      RAISE EXCEPTION 'INSUFFICIENT_OPEN_SLOTS: Needed % open slots to reduce, but found %.',
        abs(v_delta), COALESCE(array_length(v_open_slots, 1), 0)
        USING ERRCODE = '22023';
    END IF;

    FOREACH v_slot_id IN ARRAY v_open_slots LOOP
      v_res := public.fn_set_slot_status(
        v_slot_id,
        'hc_reduced',
        'HC_REDUCTION',
        v_caller_id,
        format('Quota revised from %s to %s. Justification: %s', v_current_quota, p_new_target, btrim(p_justification))
      );
      IF (v_res->>'status') = 'blocked' THEN
        RAISE EXCEPTION 'SLOT_REDUCTION_BLOCKED: Slot % could not be reduced: %',
          v_slot_id, (v_res->>'blocked_reason')
          USING ERRCODE = '22023';
      END IF;
    END LOOP;
  END IF;

  -- 6. Additions (new > current)
  IF v_delta > 0 THEN
    SELECT COALESCE(MAX(slot_ordinal), 0)::smallint INTO v_max_ordinal
    FROM public.plantilla_slots
    WHERE legacy_vcode = p_vcode;

    FOR i IN 1..v_delta LOOP
      INSERT INTO public.plantilla_slots (
        store_id, account_id, group_id, position, employment_type,
        is_roving, slot_status, slot_ordinal, legacy_vcode,
        source_hc_request_id, created_by, updated_by
      ) VALUES (
        v_vacancy.store_id, v_vacancy.account_id, v_vacancy.group_id,
        COALESCE(v_vacancy.position, ''), COALESCE(v_vacancy.employment_type, 'stationary'),
        false, 'open', (v_max_ordinal + i)::smallint, p_vcode,
        COALESCE(p_source_request_id, v_vacancy.source_headcount_request_id),
        v_caller_id, v_caller_id
      ) RETURNING id INTO v_new_slot_id;

      INSERT INTO public.slot_history (
        slot_id, account_id, action_type, old_value, new_value,
        reason_code, performed_by, remarks
      ) VALUES (
        v_new_slot_id, v_vacancy.account_id, 'created', NULL, 'open',
        'HC_READD', v_caller_id,
        format('Quota expanded from %s to %s. Justification: %s', v_current_quota, p_new_target, btrim(p_justification))
      );
    END LOOP;
  END IF;

  -- 7. Target Sync
  UPDATE public.vacancies
  SET required_headcount = p_new_target,
      status = CASE
        WHEN status = 'Filled' AND p_new_target > v_current_quota THEN 'Open'
        ELSE status
      END,
      is_archived = CASE
        WHEN status = 'Filled' AND p_new_target > v_current_quota THEN false
        ELSE is_archived
      END,
      updated_by = v_caller_id,
      updated_at = now()
  WHERE id = v_vacancy.id;

  UPDATE public.vacancy_requirements
  SET hc_needed = p_new_target
  WHERE vacancy_id = v_vacancy.id;

  -- 8. Resolve position_id for audit logging
  v_position_id := v_vacancy.position_id;
  IF v_position_id IS NULL THEN
    SELECT vr.position_id INTO v_position_id
    FROM public.vacancy_requirements vr
    WHERE vr.vacancy_id = v_vacancy.id
    LIMIT 1;
  END IF;
  IF v_position_id IS NULL AND v_vacancy.position IS NOT NULL THEN
    SELECT p.id INTO v_position_id
    FROM public.positions p
    WHERE lower(trim(p.position_name)) = lower(trim(v_vacancy.position))
    LIMIT 1;
  END IF;
  IF v_position_id IS NULL THEN
    RAISE EXCEPTION 'POSITION_NOT_RESOLVED: Vacancy % position could not be mapped to a valid position ID.', p_vcode
      USING ERRCODE = '22023';
  END IF;

  -- 9. Audit Log
  IF v_delta <> 0 THEN
    INSERT INTO public.headcount_quota_revisions (
      vcode, account_id, store_id, position_id, previous_quota,
      new_quota, delta, revision_type, source_request_id,
      justification, revised_by
    ) VALUES (
      p_vcode, v_vacancy.account_id, v_vacancy.store_id, v_position_id,
      v_current_quota, p_new_target, v_delta,
      CASE WHEN p_source_request_id IS NOT NULL THEN 'REQUEST_AMENDMENT' ELSE 'DIRECT_OVERRIDE' END,
      p_source_request_id, btrim(p_justification), v_caller_id
    );
  END IF;

  -- 10. Return JSON summary
  RETURN jsonb_build_object(
    'success', true,
    'ok', true,
    'vcode', p_vcode,
    'previous_quota', v_current_quota,
    'new_quota', p_new_target,
    'delta', v_delta
  );
END;
$function$;

COMMENT ON FUNCTION public.revise_vcode_headcount_quota IS
  'Authoritative headcount quota revision mutation for existing store VCodes, supporting Data Team, Ops (OM, TL, ATL, HRCO), and Super Admin roles with strict safety floor enforcement.';

GRANT EXECUTE ON FUNCTION public.revise_vcode_headcount_quota(text, integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revise_vcode_headcount_quota(text, integer, text, uuid) TO service_role;

COMMIT;
