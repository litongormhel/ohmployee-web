-- ============================================================
-- Migration: 20262606000031_fix_new_store_group_and_requester.sql
-- Description:
--   1. Update submit_new_store_request to derive group_id from accounts
--      if omitted and cleanly resolve caller display name from full_name/email.
--   2. Backfill existing new_store_requests with missing group_id and
--      repair corrupt requested_by_name (empty comma ',').
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
  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Ops or Admin role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL AND (p_input ->> 'p_requested_by') IS NOT NULL THEN
    SELECT id INTO v_caller_id
    FROM public.users_profile
    WHERE auth_user_id = (p_input ->> 'p_requested_by')::uuid
       OR id = (p_input ->> 'p_requested_by')::uuid
    LIMIT 1;
  END IF;

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

  -- ── Derive group_id from accounts if not supplied ─────────────
  IF v_group_id IS NULL AND v_account_id IS NOT NULL THEN
    SELECT group_id INTO v_group_id
    FROM public.accounts
    WHERE id = v_account_id;
  END IF;

  -- ── Resolve caller display name and role ──────────────────────
  SELECT
    COALESCE(
      NULLIF(TRIM(
        COALESCE(NULLIF(TRIM(up.last_name), ''), '') ||
        CASE WHEN NULLIF(TRIM(up.last_name), '') IS NOT NULL AND NULLIF(TRIM(up.first_name), '') IS NOT NULL THEN ', ' ELSE '' END ||
        COALESCE(NULLIF(TRIM(up.first_name), ''), '')
      ), ''),
      NULLIF(TRIM(up.full_name), ''),
      NULLIF(TRIM(split_part(up.email, '@', 1)), ''),
      'Admin / Ops'
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
    JOIN auth.users au           ON au.id = up.auth_user_id
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
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_new_store_request(jsonb) TO authenticated;

-- ── Repair existing new_store_requests ─────────────────────────
-- 1. Populate missing group_id from accounts
UPDATE public.new_store_requests nsr
SET group_id = a.group_id
FROM public.accounts a
WHERE nsr.account_id = a.id
  AND nsr.group_id IS NULL
  AND a.group_id IS NOT NULL;

-- 2. Repair empty/corrupted requested_by_name (',', empty, etc.)
UPDATE public.new_store_requests nsr
SET requested_by_name = COALESCE(
  NULLIF(TRIM(
    COALESCE(NULLIF(TRIM(up.last_name), ''), '') ||
    CASE WHEN NULLIF(TRIM(up.last_name), '') IS NOT NULL AND NULLIF(TRIM(up.first_name), '') IS NOT NULL THEN ', ' ELSE '' END ||
    COALESCE(NULLIF(TRIM(up.first_name), ''), '')
  ), ''),
  NULLIF(TRIM(up.full_name), ''),
  NULLIF(TRIM(split_part(up.email, '@', 1)), ''),
  'Admin / Ops'
)
FROM public.users_profile up
WHERE nsr.requested_by = up.id
  AND (nsr.requested_by_name IS NULL OR TRIM(nsr.requested_by_name) IN ('', ',', ', '));
