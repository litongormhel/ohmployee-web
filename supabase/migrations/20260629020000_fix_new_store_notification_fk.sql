-- Migration: 20260629020000_fix_new_store_notification_fk
-- Created: 2026-06-29
-- Purpose: Fix notifications_user_id_fkey FK violations when submitting,
--          approving, or rejecting new store requests in environments with
--          stale user profiles (like UAT).
--
-- Root Cause:
--   When users are deleted from auth.users (common in UAT cleanup), their
--   corresponding public.users_profile rows are not deleted, leaving stale
--   auth_user_id references. Fanning out notifications to HA/SA or notifying
--   the requester triggers notifications_user_id_fkey FK violation, which
--   aborts/rolls back the entire new store request transaction.
--
-- Fix:
--   1. submit_new_store_request: Join auth.users to verify active HA/SA recipients
--      exist, deduplicate them using DISTINCT ON, and wrap the notification INSERT
--      in an EXCEPTION block to swallow residual errors safely.
--   2. approve_new_store_request / reject_new_store_request: Verify requester auth
--      ID exists in auth.users before inserting, and wrap the INSERT in an EXCEPTION
--      block.
-- ============================================================


-- ============================================================
-- §1  Update submit_new_store_request
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_new_store_request(
  p_input jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id           uuid;
  v_caller_name         text;
  v_caller_role         text;
  -- input fields
  v_store_name          text;
  v_province            text;
  v_city                text;
  v_account_id          uuid;
  v_account_name        text;
  v_group_id            uuid;
  v_position            text;
  v_requested_hc        integer;
  v_reason              text;
  -- outcome
  v_new_req_id          uuid;
  v_notif_rec           RECORD;
  v_notifications_sent  int := 0;
BEGIN
  -- ── Auth guard ────────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- Ops roles (hrco/atl/tl/om, level 40-70) OR HA/SA (full access).
  -- Recruitment, Encoder, Viewer are implicitly blocked because neither
  -- i_am_ops() nor i_have_full_access() returns true for them.
  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Ops or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Parse input ───────────────────────────────────────────────
  v_store_name   := TRIM(p_input ->> 'store_name');
  v_province     := TRIM(p_input ->> 'province');
  v_city         := TRIM(p_input ->> 'city');
  v_account_id   := (p_input ->> 'account_id')::uuid;
  v_account_name := TRIM(p_input ->> 'account_name');
  v_reason       := TRIM(p_input ->> 'reason');
  v_position     := NULLIF(TRIM(COALESCE(p_input ->> 'position', '')), '');
  v_requested_hc := NULLIF(p_input ->> 'requested_hc', '')::integer;
  v_group_id     := NULLIF(p_input ->> 'group_id', '')::uuid;

  -- Required field validation
  IF v_store_name  IS NULL OR v_store_name  = '' THEN
    RAISE EXCEPTION 'store_name is required'   USING ERRCODE = '22023';
  END IF;
  IF v_province    IS NULL OR v_province    = '' THEN
    RAISE EXCEPTION 'province is required'     USING ERRCODE = '22023';
  END IF;
  IF v_city        IS NULL OR v_city        = '' THEN
    RAISE EXCEPTION 'city is required'         USING ERRCODE = '22023';
  END IF;
  IF v_account_id  IS NULL THEN
    RAISE EXCEPTION 'account_id is required'   USING ERRCODE = '22023';
  END IF;
  IF v_account_name IS NULL OR v_account_name = '' THEN
    RAISE EXCEPTION 'account_name is required' USING ERRCODE = '22023';
  END IF;
  IF v_reason      IS NULL OR v_reason      = '' THEN
    RAISE EXCEPTION 'reason is required'       USING ERRCODE = '22023';
  END IF;

  -- ── Resolve caller display name and role ──────────────────────
  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'ops')
  INTO v_caller_name, v_caller_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_caller_id;

  -- ── Layer A: exact active store exists ────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.stores
    WHERE account_id = v_account_id
      AND LOWER(TRIM(store_name)) = LOWER(v_store_name)
      AND LOWER(TRIM(area_city))  = LOWER(v_city)
      AND LOWER(TRIM(province))   = LOWER(v_province)
      AND is_active = true AND status = 'active'
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'An active store with this name already exists in the selected account and location.'
      USING ERRCODE = 'P0001', HINT = 'STORE_ALREADY_EXISTS';
  END IF;

  -- ── Layer B: exact pending request exists ─────────────────────
  IF EXISTS (
    SELECT 1 FROM public.new_store_requests
    WHERE account_id = v_account_id
      AND LOWER(TRIM(store_name)) = LOWER(v_store_name)
      AND LOWER(TRIM(city))       = LOWER(v_city)
      AND LOWER(TRIM(province))   = LOWER(v_province)
      AND status = 'pending' AND is_archived = false
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'A pending request for this store already exists.'
      USING ERRCODE = 'P0001', HINT = 'DUPLICATE_PENDING_REQUEST';
  END IF;

  -- ── Insert request ────────────────────────────────────────────
  INSERT INTO public.new_store_requests (
    store_name,
    province,
    city,
    account_id,
    account_name,
    group_id,
    position,
    requested_hc,
    reason,
    requested_by,
    requested_by_name
  ) VALUES (
    v_store_name,
    v_province,
    v_city,
    v_account_id,
    v_account_name,
    v_group_id,
    v_position,
    v_requested_hc,
    v_reason,
    v_caller_id,
    v_caller_name
  )
  RETURNING id INTO v_new_req_id;

  -- ── Notify all HA/SA ──────────────────────────────────────────
  FOR v_notif_rec IN
    SELECT DISTINCT ON (up.auth_user_id)
      up.auth_user_id,
      ro.role_name
    FROM public.users_profile up
    JOIN public.roles ro         ON ro.id = up.role_id
    JOIN auth.users au           ON au.id = up.auth_user_id  -- skip stale/deleted auth users
    WHERE up.is_active = true
      AND up.auth_user_id IS NOT NULL
      AND ro.role_name IN ('Super Admin', 'Head Admin')
    ORDER BY up.auth_user_id
  LOOP
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_notif_rec.role_name,
        v_notif_rec.auth_user_id,
        'new_store_request',
        'NEW_STORE_REQUEST_SUBMITTED',
        'New Store Request',
        v_caller_name || ' requested to add ' || v_store_name ||
          ' (' || v_city || ', ' || v_province || ') under ' || v_account_name || '.',
        '/new_store_request/' || v_new_req_id::text,
        'new_store_request',
        v_new_req_id::text
      );
      v_notifications_sent := v_notifications_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'submit_new_store_request: skipped recipient %, role %, request_id %, error: %',
        v_notif_rec.auth_user_id, v_notif_rec.role_name, v_new_req_id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'request_id',          v_new_req_id,
    'status',              'pending',
    'notifications_sent',  v_notifications_sent
  );

EXCEPTION
  WHEN unique_violation THEN
    -- Race condition: the partial unique index blocked the insert
    RAISE EXCEPTION 'A pending request for this store already exists (race condition).'
      USING ERRCODE = 'P0001', HINT = 'DUPLICATE_PENDING_REQUEST';
END;
$$;


-- ============================================================
-- §2  Update approve_new_store_request
-- ============================================================
CREATE OR REPLACE FUNCTION public.approve_new_store_request(
  p_request_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_reviewer_id     uuid;
  v_reviewer_name   text;
  v_reviewer_role   text;
  v_req             public.new_store_requests;
  v_new_store_id    uuid;
  v_requester_auth  uuid;
  v_requester_role  text;
BEGIN
  -- ── Auth guard ────────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Insufficient permissions — Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  v_reviewer_id := public.get_current_profile_id();
  IF v_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Resolve reviewer display name ─────────────────────────────
  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'admin')
  INTO v_reviewer_name, v_reviewer_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_reviewer_id;

  -- ── Lock and load request row ─────────────────────────────────
  SELECT * INTO v_req
  FROM public.new_store_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'New store request not found: %', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is not in pending status (current: %)', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Insert active store into registry ─────────────────────────
  INSERT INTO public.stores (
    account_id,
    group_id,
    store_name,
    area_city,
    province,
    is_active,
    status,
    created_by,
    approved_by,
    approved_at
  ) VALUES (
    v_req.account_id,
    v_req.group_id,
    v_req.store_name,
    v_req.city,
    v_req.province,
    true,
    'active',
    v_reviewer_id,
    v_reviewer_id,
    now()
  )
  RETURNING id INTO v_new_store_id;

  -- ── Mark request approved ─────────────────────────────────────
  UPDATE public.new_store_requests SET
    status           = 'approved',
    reviewed_by      = v_reviewer_id,
    reviewed_by_name = v_reviewer_name,
    reviewed_at      = now(),
    created_store_id = v_new_store_id,
    updated_at       = now()
  WHERE id = p_request_id;

  -- ── Notify requester ──────────────────────────────────────────
  SELECT up.auth_user_id, COALESCE(ro.role_name, 'ops')
  INTO v_requester_auth, v_requester_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_req.requested_by;

  IF v_requester_auth IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users WHERE id = v_requester_auth) THEN
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_requester_role,
        v_requester_auth,
        'new_store_request',
        'NEW_STORE_REQUEST_APPROVED',
        'Store Request Approved',
        'Your request for ' || v_req.store_name ||
          ' has been approved and added to the store registry.',
        '/new_store_request/' || p_request_id::text,
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'approve_new_store_request: skipped requester %, role %, request_id %, error: %',
        v_requester_auth, v_requester_role, p_request_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'request_id',    p_request_id,
    'store_id',      v_new_store_id,
    'status',        'approved'
  );
END;
$$;


-- ============================================================
-- §3  Update reject_new_store_request
-- ============================================================
CREATE OR REPLACE FUNCTION public.reject_new_store_request(
  p_request_id  uuid,
  p_reason      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_reviewer_id     uuid;
  v_reviewer_name   text;
  v_reviewer_role   text;
  v_req             public.new_store_requests;
  v_requester_auth  uuid;
  v_requester_role  text;
BEGIN
  -- ── Auth guard ────────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'Insufficient permissions — Head Admin or Super Admin required'
      USING ERRCODE = '42501';
  END IF;

  -- Reason is mandatory for rejection
  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'Rejection reason is required'
      USING ERRCODE = '22023';
  END IF;

  v_reviewer_id := public.get_current_profile_id();
  IF v_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Resolve reviewer display name ─────────────────────────────
  SELECT
    COALESCE(
      NULLIF(TRIM(COALESCE(up.last_name,'') || ', ' || COALESCE(up.first_name,'')), ', '),
      up.full_name,
      'Unknown'
    ),
    COALESCE(ro.role_name, 'admin')
  INTO v_reviewer_name, v_reviewer_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_reviewer_id;

  -- ── Lock and load request row ─────────────────────────────────
  SELECT * INTO v_req
  FROM public.new_store_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'New store request not found: %', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Request is not in pending status (current: %)', v_req.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Mark rejected ─────────────────────────────────────────────
  UPDATE public.new_store_requests SET
    status           = 'rejected',
    reviewed_by      = v_reviewer_id,
    reviewed_by_name = v_reviewer_name,
    reviewed_at      = now(),
    review_reason    = TRIM(p_reason),
    updated_at       = now()
  WHERE id = p_request_id;

  -- ── Notify requester ──────────────────────────────────────────
  SELECT up.auth_user_id, COALESCE(ro.role_name, 'ops')
  INTO v_requester_auth, v_requester_role
  FROM public.users_profile up
  LEFT JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.id = v_req.requested_by;

  IF v_requester_auth IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users WHERE id = v_requester_auth) THEN
    BEGIN
      INSERT INTO public.notifications (
        recipient_role,
        recipient_user_id,
        notification_type,
        event_type,
        title,
        message,
        deep_link_route,
        reference_type,
        reference_id
      ) VALUES (
        v_requester_role,
        v_requester_auth,
        'new_store_request',
        'NEW_STORE_REQUEST_REJECTED',
        'Store Request Rejected',
        'Your request for ' || v_req.store_name ||
          ' was rejected. Reason: ' || TRIM(p_reason) || '.',
        '/new_store_request/' || p_request_id::text,
        'new_store_request',
        p_request_id::text
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'reject_new_store_request: skipped requester %, role %, request_id %, error: %',
        v_requester_auth, v_requester_role, p_request_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'request_id', p_request_id,
    'status',     'rejected'
  );
END;
$$;


-- ============================================================
-- §4  Grants
-- ============================================================
GRANT EXECUTE ON FUNCTION public.submit_new_store_request(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_new_store_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_new_store_request(uuid, text) TO authenticated;
