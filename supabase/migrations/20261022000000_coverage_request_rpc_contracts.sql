-- ============================================================
-- OHM2026_0094 — Coverage Request RPC Contracts
-- Migration: 20261022000000_coverage_request_rpc_contracts.sql
--
-- Phase 2 scope only:
--   - lifecycle RPC contracts
--   - request-type payload validation
--   - history logging for create/submit/cancel
--
-- Explicitly out of scope:
--   - Coverage Group structural mutation
--   - approval execution
--   - HC, slot, vacancy, or pipeline creation
-- ============================================================

CREATE OR REPLACE FUNCTION public._coverage_request_actor()
RETURNS TABLE (
  profile_id uuid,
  full_name text,
  role_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT
    up.id,
    up.full_name,
    COALESCE(r.role_name, up.role)
  FROM public.users_profile up
  LEFT JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid()
    AND COALESCE(up.is_active, true) = true
  LIMIT 1;
$fn$;

CREATE OR REPLACE FUNCTION public._coverage_request_uuid_array(
  p_payload jsonb,
  p_key text,
  p_required boolean DEFAULT true
)
RETURNS uuid[]
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_values uuid[];
  v_bad text;
BEGIN
  IF NOT (p_payload ? p_key) THEN
    IF p_required THEN
      RAISE EXCEPTION 'payload.% is required', p_key USING ERRCODE = '22023';
    END IF;
    RETURN ARRAY[]::uuid[];
  END IF;

  IF jsonb_typeof(p_payload -> p_key) <> 'array' THEN
    RAISE EXCEPTION 'payload.% must be an array', p_key USING ERRCODE = '22023';
  END IF;

  SELECT value #>> '{}'
  INTO v_bad
  FROM jsonb_array_elements(p_payload -> p_key) AS value
  WHERE NOT ((value #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
  LIMIT 1;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'payload.% contains an invalid uuid: %', p_key, v_bad
      USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT (value #>> '{}')::uuid), ARRAY[]::uuid[])
  INTO v_values
  FROM jsonb_array_elements(p_payload -> p_key) AS value;

  IF p_required AND COALESCE(array_length(v_values, 1), 0) = 0 THEN
    RAISE EXCEPTION 'payload.% must contain at least one id', p_key
      USING ERRCODE = '22023';
  END IF;

  RETURN v_values;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._coverage_request_payload_has_only_keys(
  p_payload jsonb,
  p_allowed_keys text[]
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_key text;
BEGIN
  SELECT key
  INTO v_key
  FROM jsonb_object_keys(p_payload) AS key
  WHERE NOT (key = ANY (p_allowed_keys))
  LIMIT 1;

  IF v_key IS NOT NULL THEN
    RAISE EXCEPTION 'payload key % is not allowed for this request_type', v_key
      USING ERRCODE = '22023';
  END IF;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._validate_coverage_request_payload(
  p_request_type public.request_type,
  p_payload jsonb,
  p_account_id uuid DEFAULT NULL,
  p_position_id uuid DEFAULT NULL,
  p_employment_type text DEFAULT NULL,
  p_target_coverage_group_id uuid DEFAULT NULL,
  p_source_coverage_group_id uuid DEFAULT NULL,
  p_destination_coverage_group_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_store_ids uuid[];
  v_anchor_store_id uuid;
  v_target_account_id uuid;
  v_source_account_id uuid;
  v_destination_account_id uuid;
  v_effective_account_id uuid;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'payload must be a json object' USING ERRCODE = '22023';
  END IF;

  IF p_payload::text ~* '"(required_hc|required_headcount|headcount|hc|slot_id|slot_ids|vacancy_id|vacancy_vcode|vcode|pipeline_id|coverage_weight|hc_share|store_count)"[[:space:]]*:' THEN
    RAISE EXCEPTION 'Coverage Request payload must remain structure-only; HC, slot, vacancy, pipeline, coverage weight, and HC share fields are not allowed'
      USING ERRCODE = '22023';
  END IF;

  IF p_target_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_target_account_id
    FROM public.coverage_groups
    WHERE id = p_target_coverage_group_id
      AND archived_at IS NULL;

    IF v_target_account_id IS NULL THEN
      RAISE EXCEPTION 'target coverage group not found or archived'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF p_source_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_source_account_id
    FROM public.coverage_groups
    WHERE id = p_source_coverage_group_id
      AND archived_at IS NULL;

    IF v_source_account_id IS NULL THEN
      RAISE EXCEPTION 'source coverage group not found or archived'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF p_destination_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_destination_account_id
    FROM public.coverage_groups
    WHERE id = p_destination_coverage_group_id
      AND archived_at IS NULL;

    IF v_destination_account_id IS NULL THEN
      RAISE EXCEPTION 'destination coverage group not found or archived'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  v_effective_account_id := COALESCE(
    p_account_id,
    v_target_account_id,
    v_source_account_id,
    v_destination_account_id
  );

  IF v_effective_account_id IS NOT NULL
     AND NOT public.i_have_full_access()
     AND NOT (v_effective_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: account is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF p_request_type = 'create_coverage_group'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload,
      ARRAY['store_ids', 'anchor_store_id', 'area_name', 'proposed_name', 'notes']
    );

    IF p_account_id IS NULL OR p_position_id IS NULL OR NULLIF(TRIM(COALESCE(p_employment_type, '')), '') IS NULL THEN
      RAISE EXCEPTION 'create_coverage_group requires account_id, position_id, and employment_type'
        USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = p_account_id) THEN
      RAISE EXCEPTION 'account not found' USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.positions WHERE id = p_position_id) THEN
      RAISE EXCEPTION 'position not found' USING ERRCODE = 'P0002';
    END IF;

    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    IF jsonb_typeof(p_payload -> 'anchor_store_id') IS DISTINCT FROM 'string'
       OR NOT ((p_payload ->> 'anchor_store_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') THEN
      RAISE EXCEPTION 'payload.anchor_store_id must be a uuid string'
        USING ERRCODE = '22023';
    END IF;

    v_anchor_store_id := (p_payload ->> 'anchor_store_id')::uuid;

    IF NOT (v_anchor_store_id = ANY (v_store_ids)) THEN
      RAISE EXCEPTION 'payload.anchor_store_id must be one of payload.store_ids'
        USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM unnest(v_store_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.stores s
        WHERE s.id = sid
          AND s.account_id = p_account_id
          AND COALESCE(s.is_active, true) = true
      )
    ) THEN
      RAISE EXCEPTION 'all payload.store_ids must be active stores under account_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'add_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'add_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    IF EXISTS (
      SELECT 1
      FROM unnest(v_store_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.stores s
        WHERE s.id = sid
          AND s.account_id = v_target_account_id
          AND COALESCE(s.is_active, true) = true
      )
    ) THEN
      RAISE EXCEPTION 'all payload.store_ids must be active stores under the target coverage group account'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'remove_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'remove_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

  ELSIF p_request_type = 'convert_stationary_to_roving'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload,
      ARRAY['store_ids', 'anchor_store_id', 'area_name', 'notes']
    );
    IF p_account_id IS NULL OR p_position_id IS NULL OR NULLIF(TRIM(COALESCE(p_employment_type, '')), '') IS NULL THEN
      RAISE EXCEPTION 'convert_stationary_to_roving requires account_id, position_id, and employment_type'
        USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = p_account_id) THEN
      RAISE EXCEPTION 'account not found' USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.positions WHERE id = p_position_id) THEN
      RAISE EXCEPTION 'position not found' USING ERRCODE = 'P0002';
    END IF;

    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

    IF jsonb_typeof(p_payload -> 'anchor_store_id') IS DISTINCT FROM 'string'
       OR NOT ((p_payload ->> 'anchor_store_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') THEN
      RAISE EXCEPTION 'payload.anchor_store_id must be a uuid string'
        USING ERRCODE = '22023';
    END IF;

    v_anchor_store_id := (p_payload ->> 'anchor_store_id')::uuid;

    IF NOT (v_anchor_store_id = ANY (v_store_ids)) THEN
      RAISE EXCEPTION 'payload.anchor_store_id must be one of payload.store_ids'
        USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM unnest(v_store_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.stores s
        WHERE s.id = sid
          AND s.account_id = p_account_id
          AND COALESCE(s.is_active, true) = true
      )
    ) THEN
      RAISE EXCEPTION 'all payload.store_ids must be active stores under account_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'convert_roving_to_stationary'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'convert_roving_to_stationary requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    v_store_ids := public._coverage_request_uuid_array(p_payload, 'store_ids', true);

  ELSIF p_request_type = 'merge_coverage_groups'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['notes']);
    IF p_source_coverage_group_id IS NULL OR p_destination_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'merge_coverage_groups requires source_coverage_group_id and destination_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    IF p_source_coverage_group_id = p_destination_coverage_group_id THEN
      RAISE EXCEPTION 'merge_coverage_groups source and destination must be different'
        USING ERRCODE = '22023';
    END IF;
    IF v_source_account_id <> v_destination_account_id THEN
      RAISE EXCEPTION 'merge_coverage_groups source and destination must belong to the same account'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'dissolve_coverage_group requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'unsupported request_type: %', p_request_type
      USING ERRCODE = '22023';
  END IF;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._log_coverage_request_history(
  p_coverage_request_id uuid,
  p_from_status public.request_status,
  p_to_status public.request_status,
  p_event_type text,
  p_event_payload jsonb DEFAULT '{}'::jsonb,
  p_actor_id uuid DEFAULT NULL,
  p_actor_name text DEFAULT NULL,
  p_actor_role text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  INSERT INTO public.coverage_request_history (
    coverage_request_id,
    from_status,
    to_status,
    event_type,
    event_payload,
    actor_id,
    actor_name,
    actor_role,
    note
  ) VALUES (
    p_coverage_request_id,
    p_from_status,
    p_to_status,
    p_event_type,
    COALESCE(p_event_payload, '{}'::jsonb),
    p_actor_id,
    p_actor_name,
    p_actor_role,
    NULLIF(TRIM(COALESCE(p_note, '')), '')
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.create_coverage_request(
  p_request_type public.request_type,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_account_id uuid DEFAULT NULL,
  p_position_id uuid DEFAULT NULL,
  p_employment_type text DEFAULT NULL,
  p_target_coverage_group_id uuid DEFAULT NULL,
  p_source_coverage_group_id uuid DEFAULT NULL,
  p_destination_coverage_group_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request_id uuid;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public._validate_coverage_request_payload(
    p_request_type,
    COALESCE(p_payload, '{}'::jsonb),
    p_account_id,
    p_position_id,
    p_employment_type,
    p_target_coverage_group_id,
    p_source_coverage_group_id,
    p_destination_coverage_group_id
  );

  INSERT INTO public.coverage_requests (
    request_type,
    status,
    account_id,
    position_id,
    employment_type,
    target_coverage_group_id,
    source_coverage_group_id,
    destination_coverage_group_id,
    payload,
    reason,
    requested_by,
    requested_by_name,
    requested_by_role,
    created_by,
    updated_by
  ) VALUES (
    p_request_type,
    'draft'::public.request_status,
    p_account_id,
    p_position_id,
    NULLIF(TRIM(COALESCE(p_employment_type, '')), ''),
    p_target_coverage_group_id,
    p_source_coverage_group_id,
    p_destination_coverage_group_id,
    COALESCE(p_payload, '{}'::jsonb),
    NULLIF(TRIM(COALESCE(p_reason, '')), ''),
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    v_actor.profile_id,
    v_actor.profile_id
  )
  RETURNING id INTO v_request_id;

  PERFORM public._log_coverage_request_history(
    v_request_id,
    NULL,
    'draft'::public.request_status,
    'created',
    jsonb_build_object('request_type', p_request_type),
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    p_reason
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'coverage_request_id', v_request_id,
    'request_status', 'draft'
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.submit_coverage_request(
  p_coverage_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'draft'::public.request_status THEN
    RAISE EXCEPTION 'coverage request can only be submitted from draft status'
      USING ERRCODE = '22023';
  END IF;

  IF v_request.requested_by <> v_actor.profile_id
     AND NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: only the requester or HA/SA can submit this draft'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public._validate_coverage_request_payload(
    v_request.request_type,
    v_request.payload,
    v_request.account_id,
    v_request.position_id,
    v_request.employment_type,
    v_request.target_coverage_group_id,
    v_request.source_coverage_group_id,
    v_request.destination_coverage_group_id
  );

  UPDATE public.coverage_requests
  SET status = 'pending'::public.request_status,
      submitted_by = v_actor.profile_id,
      submitted_by_name = v_actor.full_name,
      submitted_at = now(),
      updated_by = v_actor.profile_id,
      updated_at = now()
  WHERE id = p_coverage_request_id;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    'draft'::public.request_status,
    'pending'::public.request_status,
    'submitted',
    '{}'::jsonb,
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    NULL
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'coverage_request_id', p_coverage_request_id,
    'request_status', 'pending'
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.cancel_coverage_request(
  p_coverage_request_id uuid,
  p_cancellation_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status NOT IN ('draft'::public.request_status, 'pending'::public.request_status) THEN
    RAISE EXCEPTION 'coverage request can only be cancelled from draft or pending status'
      USING ERRCODE = '22023';
  END IF;

  IF v_request.requested_by <> v_actor.profile_id
     AND NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: only the requester or HA/SA can cancel this request'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.coverage_requests
  SET status = 'cancelled'::public.request_status,
      cancelled_by = v_actor.profile_id,
      cancelled_by_name = v_actor.full_name,
      cancelled_at = now(),
      cancellation_reason = NULLIF(TRIM(COALESCE(p_cancellation_reason, '')), ''),
      updated_by = v_actor.profile_id,
      updated_at = now()
  WHERE id = p_coverage_request_id;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    v_request.status,
    'cancelled'::public.request_status,
    'cancelled',
    '{}'::jsonb,
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    p_cancellation_reason
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'coverage_request_id', p_coverage_request_id,
    'request_status', 'cancelled'
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.review_coverage_request(
  p_coverage_request_id uuid,
  p_decision text,
  p_reviewer_remarks text DEFAULT NULL,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'forbidden: only Head Admin or Super Admin can review Coverage Requests'
      USING ERRCODE = '42501';
  END IF;

  IF lower(trim(COALESCE(p_decision, ''))) NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'review decision must be approved or rejected'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'pending'::public.request_status THEN
    RAISE EXCEPTION 'coverage request can only be reviewed from pending status'
      USING ERRCODE = '22023';
  END IF;

  PERFORM public._validate_coverage_request_payload(
    v_request.request_type,
    v_request.payload,
    v_request.account_id,
    v_request.position_id,
    v_request.employment_type,
    v_request.target_coverage_group_id,
    v_request.source_coverage_group_id,
    v_request.destination_coverage_group_id
  );

  RAISE EXCEPTION 'review_coverage_request is a Phase 2 contract stub; approval and rejection status changes are intentionally deferred'
    USING ERRCODE = '0A000';
END;
$fn$;

COMMENT ON FUNCTION public.create_coverage_request(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text) IS
  'Creates a draft Coverage Request. Structure-only contract; does not create Coverage Groups, HC, slots, vacancies, or pipeline rows.';
COMMENT ON FUNCTION public.submit_coverage_request(uuid) IS
  'Moves a Coverage Request from draft to pending after request-type payload validation.';
COMMENT ON FUNCTION public.cancel_coverage_request(uuid, text) IS
  'Moves a draft or pending Coverage Request to cancelled and logs lifecycle history.';
COMMENT ON FUNCTION public.review_coverage_request(uuid, text, text, text) IS
  'Phase 2 review contract stub. HA/SA-only validation; approval/rejection status changes are deferred.';

REVOKE EXECUTE ON FUNCTION public._coverage_request_actor() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._coverage_request_uuid_array(jsonb, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._coverage_request_payload_has_only_keys(jsonb, text[]) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._validate_coverage_request_payload(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._log_coverage_request_history(uuid, public.request_status, public.request_status, text, jsonb, uuid, text, text, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_coverage_request(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_coverage_request(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_coverage_request(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_coverage_request(uuid, text, text, text)
  TO authenticated;
