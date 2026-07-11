-- ============================================================
-- ohm#cgd7k2m9 — Coverage Request Draft Continuity
-- Migration: 20261239000000_coverage_request_draft_operations.sql
--
-- Adds two draft-only RPCs:
--   update_coverage_request_draft — updates all mutable fields of a draft
--   delete_coverage_request_draft — soft-archives a draft (draft-only)
--
-- ADR-001 compliance: no HC, slot, vacancy, or pipeline changes.
-- ============================================================

-- ------------------------------------------------------------
-- §1. update_coverage_request_draft
-- ------------------------------------------------------------
-- Caller: requester of the draft, OR Encoder / HA / SA
-- Draft-only — raises 22023 if status != 'draft'
-- Returns: jsonb { status, coverage_request_id, request_status }

CREATE OR REPLACE FUNCTION public.update_coverage_request_draft(
  p_coverage_request_id           uuid,
  p_request_type                  public.request_type,
  p_payload                       jsonb,
  p_account_id                    uuid    DEFAULT NULL,
  p_position_id                   uuid    DEFAULT NULL,
  p_employment_type               text    DEFAULT NULL,
  p_target_coverage_group_id      uuid    DEFAULT NULL,
  p_source_coverage_group_id      uuid    DEFAULT NULL,
  p_destination_coverage_group_id uuid    DEFAULT NULL,
  p_reason                        text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor   record;
  v_request public.coverage_requests%ROWTYPE;
BEGIN
  -- Identify caller
  SELECT * INTO v_actor FROM public._coverage_request_actor();
  IF v_actor.profile_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found'
      USING ERRCODE = '42501';
  END IF;

  -- Load the draft (with lock)
  SELECT * INTO v_request
  FROM public.coverage_requests
  WHERE id = p_coverage_request_id
    AND archived_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage request not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'draft'::public.request_status THEN
    RAISE EXCEPTION 'only draft requests can be edited (status: %)', v_request.status
      USING ERRCODE = '22023';
  END IF;

  -- Authorization: requester OR mutate-capable role
  IF v_request.requested_by <> v_actor.profile_id
     AND NOT public.fn_can_mutate_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only the requester or Encoder/HA/SA can edit this draft'
      USING ERRCODE = '42501';
  END IF;

  -- Validate payload for the new type/scope
  PERFORM public._validate_coverage_request_payload(
    p_request_type,
    p_payload,
    p_account_id,
    p_position_id,
    p_employment_type,
    p_target_coverage_group_id,
    p_source_coverage_group_id,
    p_destination_coverage_group_id
  );

  -- Apply update
  UPDATE public.coverage_requests
  SET
    request_type                  = p_request_type,
    payload                       = p_payload,
    account_id                    = p_account_id,
    position_id                   = p_position_id,
    employment_type               = p_employment_type,
    target_coverage_group_id      = p_target_coverage_group_id,
    source_coverage_group_id      = p_source_coverage_group_id,
    destination_coverage_group_id = p_destination_coverage_group_id,
    reason                        = p_reason,
    updated_by                    = v_actor.profile_id,
    updated_at                    = now()
  WHERE id = p_coverage_request_id;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    'draft'::public.request_status,
    'draft'::public.request_status,
    'draft_updated',
    jsonb_build_object('updated_by', v_actor.full_name),
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    NULL
  );

  RETURN jsonb_build_object(
    'status',               'ok',
    'coverage_request_id',  p_coverage_request_id,
    'request_status',       'draft'
  );
END;
$fn$;

COMMENT ON FUNCTION public.update_coverage_request_draft(
  uuid, public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text
) IS
  'Updates all mutable fields of a draft Coverage Request. '
  'Caller must be the requester or have Encoder/HA/SA role. Draft-only.';

-- ------------------------------------------------------------
-- §2. delete_coverage_request_draft
-- ------------------------------------------------------------
-- Caller: requester of the draft, OR HA / SA
-- Draft-only — raises 22023 if status != 'draft'
-- Soft-deletes via archived_at (archive-first invariant)
-- Returns: jsonb { status, coverage_request_id }

CREATE OR REPLACE FUNCTION public.delete_coverage_request_draft(
  p_coverage_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_actor   record;
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
    RAISE EXCEPTION 'coverage request not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'draft'::public.request_status THEN
    RAISE EXCEPTION 'only draft requests can be deleted (status: %)', v_request.status
      USING ERRCODE = '22023';
  END IF;

  -- Authorization: requester OR HA/SA (review-capable = SA/HA)
  IF v_request.requested_by <> v_actor.profile_id
     AND NOT public.fn_can_review_coverage_request() THEN
    RAISE EXCEPTION 'forbidden: only the requester or HA/SA can delete this draft'
      USING ERRCODE = '42501';
  END IF;

  -- Soft-delete
  UPDATE public.coverage_requests
  SET
    archived_at    = now(),
    archived_by    = v_actor.profile_id,
    archive_reason = 'draft_deleted',
    updated_by     = v_actor.profile_id,
    updated_at     = now()
  WHERE id = p_coverage_request_id;

  PERFORM public._log_coverage_request_history(
    p_coverage_request_id,
    'draft'::public.request_status,
    NULL,
    'draft_deleted',
    jsonb_build_object('deleted_by', v_actor.full_name),
    v_actor.profile_id,
    v_actor.full_name,
    v_actor.role_name,
    'Draft deleted by requester or administrator'
  );

  RETURN jsonb_build_object(
    'status',              'ok',
    'coverage_request_id', p_coverage_request_id
  );
END;
$fn$;

COMMENT ON FUNCTION public.delete_coverage_request_draft(uuid) IS
  'Soft-archives a draft Coverage Request. '
  'Caller must be the requester or HA/SA. Draft-only. '
  'Sets archived_at — no hard delete.';

-- ------------------------------------------------------------
-- §3. EXECUTE grants (authenticated role, RBAC inside the RPC)
-- ------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.update_coverage_request_draft(
  uuid, public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text
) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.delete_coverage_request_draft(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.update_coverage_request_draft(
  uuid, public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_coverage_request_draft(uuid)
  TO authenticated;
