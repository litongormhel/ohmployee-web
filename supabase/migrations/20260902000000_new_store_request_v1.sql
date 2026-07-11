-- ============================================================
-- OHM2026_0117 — New Store Request Backend v1
-- Migration:  20260902000000_new_store_request_v1.sql
-- Depends on: 20260830000003_fix_enforcement_fn_override_bypass.sql
-- ============================================================
-- Sections:
--   §1  new_store_requests table + indexes
--   §2  RLS — SELECT only; all writes via SECURITY DEFINER RPCs
--   §3  check_new_store_duplicate RPC
--   §4  submit_new_store_request RPC
--   §5  approve_new_store_request RPC
--   §6  reject_new_store_request RPC
--   §7  get_new_store_requests RPC
--   §8  GRANT / REVOKE
--
-- Role model:
--   submit  : i_am_ops() OR i_have_full_access()    (hrco/atl/tl/om/ha/sa)
--   approve/
--   reject  : i_have_full_access()                   (ha/sa only)
--   list    : i_have_full_access() → all rows
--             else             → own rows (requested_by = caller)
--   blocked : Recruitment, Encoder, Viewer (role_level not in ops/full-access)
--
-- Notification contract (notifications table):
--   On submit  → to all HA/SA:
--     notification_type = 'new_store_request'
--     event_type        = 'NEW_STORE_REQUEST_SUBMITTED'
--     title             = 'New Store Request'
--     message           = '{name} requested to add {store} ({city}, {province}) under {account}.'
--     deep_link_route   = '/new_store_request/{id}'
--     reference_type    = 'new_store_request'
--     reference_id      = request_id::text
--   On approve → to requester:
--     event_type = 'NEW_STORE_REQUEST_APPROVED'
--     title      = 'Store Request Approved'
--     message    = 'Your request for {store} has been approved and added to the store registry.'
--   On reject  → to requester:
--     event_type = 'NEW_STORE_REQUEST_REJECTED'
--     title      = 'Store Request Rejected'
--     message    = 'Your request for {store} was rejected. Reason: {reason}.'
--
-- Validation queries (run manually after applying):
--   V01 – table exists
--     SELECT 1 FROM information_schema.tables
--     WHERE table_schema = 'public' AND table_name = 'new_store_requests';
--   V02 – all 5 RPCs exist
--     SELECT proname FROM pg_proc
--     WHERE pronamespace = 'public'::regnamespace
--       AND proname IN (
--         'check_new_store_duplicate','submit_new_store_request',
--         'approve_new_store_request','reject_new_store_request',
--         'get_new_store_requests'
--       )
--     ORDER BY proname;
--   V03 – duplicate active store blocked (STORE_ALREADY_EXISTS)
--     SELECT public.submit_new_store_request('{...}')
--     -- submit for a store_name/city/province/account_id that already
--     -- exists in stores; expect ERRCODE P0001 with hint STORE_ALREADY_EXISTS
--   V04 – duplicate pending request blocked (DUPLICATE_PENDING_REQUEST)
--     -- submit same request twice; second call raises DUPLICATE_PENDING_REQUEST
--   V05 – submit role guard: Recruitment caller blocked (ERRCODE 42501)
--     -- invoke as a recruitment-role user; expect permission error
--   V06 – HA/SA approve works and creates active store
--     SELECT id, store_name, is_active, status, approved_by, approved_at
--     FROM stores WHERE id = (
--       SELECT created_store_id FROM new_store_requests WHERE id = '<uuid>'
--     );
--   V07 – approve sets created_store_id on request row
--     SELECT created_store_id FROM new_store_requests WHERE id = '<uuid>';
--   V08 – reject stores review_reason
--     SELECT review_reason, status FROM new_store_requests WHERE id = '<uuid>';
--   V09 – requester can see own row (RLS)
--     -- invoke get_new_store_requests() as requester; row count = own rows only
--   V10 – HA/SA sees all rows
--     -- invoke get_new_store_requests() as HA; row count = total rows
--   V11 – direct INSERT blocked
--     INSERT INTO public.new_store_requests (...) VALUES (...);
--     -- expect permission denied (42501)
--   V12 – approved store searchable in stores table
--     SELECT id, store_name FROM stores
--     WHERE account_id = '<account_uuid>' AND status = 'active';
-- ============================================================


-- ============================================================
-- §1  new_store_requests table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.new_store_requests (
  id                  uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  -- Store details (required)
  store_name          text        NOT NULL,
  province            text        NOT NULL,
  city                text        NOT NULL,
  account_id          uuid        NOT NULL REFERENCES public.accounts(id),
  account_name        text        NOT NULL,       -- snapshot at submission
  group_id            uuid        REFERENCES public.groups(id),
  -- Optional fields
  position            text,
  requested_hc        integer,
  -- Reason
  reason              text        NOT NULL,
  -- Status lifecycle
  status              text        NOT NULL DEFAULT 'pending'
                        CONSTRAINT nsr_status_chk CHECK (status IN ('pending','approved','rejected')),
  -- Requester audit
  requested_by        uuid        NOT NULL REFERENCES public.users_profile(id),
  requested_by_name   text        NOT NULL,       -- snapshot at submission
  requested_at        timestamptz NOT NULL DEFAULT now(),
  -- Reviewer audit (HA/SA)
  reviewed_by         uuid        REFERENCES public.users_profile(id),
  reviewed_by_name    text,
  reviewed_at         timestamptz,
  review_reason       text,
  -- Approval outcome
  created_store_id    uuid        REFERENCES public.stores(id),
  -- Soft delete
  is_archived         boolean     NOT NULL DEFAULT false,
  archived_at         timestamptz,
  archived_by         uuid        REFERENCES public.users_profile(id),
  -- Timestamps
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- DB-level hard block: no two pending requests for same store+city+province+account
CREATE UNIQUE INDEX IF NOT EXISTS uq_nsr_pending_per_store
  ON public.new_store_requests (
    account_id,
    LOWER(TRIM(store_name)),
    LOWER(TRIM(city)),
    LOWER(TRIM(province))
  )
  WHERE status = 'pending' AND is_archived = false;

CREATE INDEX IF NOT EXISTS idx_nsr_requested_by
  ON public.new_store_requests (requested_by)
  WHERE is_archived = false;

CREATE INDEX IF NOT EXISTS idx_nsr_status
  ON public.new_store_requests (status)
  WHERE is_archived = false;

CREATE INDEX IF NOT EXISTS idx_nsr_account
  ON public.new_store_requests (account_id)
  WHERE is_archived = false;

COMMENT ON TABLE public.new_store_requests IS
  'Tracks requests to add a new store to the store registry. '
  'All writes are performed exclusively through SECURITY DEFINER RPCs.';


-- ============================================================
-- §2  RLS — SELECT only; INSERT/UPDATE/DELETE blocked for all
-- ============================================================

ALTER TABLE public.new_store_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.new_store_requests FORCE ROW LEVEL SECURITY;

-- Revoke direct table access; reads come through SELECT policy below.
REVOKE ALL ON public.new_store_requests FROM anon, authenticated;

-- Grant SELECT so the policy below can apply.
GRANT SELECT ON public.new_store_requests TO authenticated;

-- SELECT: HA/SA see all; requesters see only their own rows.
DROP POLICY IF EXISTS nsr_select ON public.new_store_requests;
CREATE POLICY nsr_select ON public.new_store_requests
  FOR SELECT TO authenticated
  USING (
    public.i_have_full_access()
    OR requested_by = public.get_current_profile_id()
  );

-- No INSERT / UPDATE / DELETE policies — SECURITY DEFINER RPCs own all writes.


-- ============================================================
-- §3  check_new_store_duplicate
-- ============================================================
-- Pre-submission fuzzy check (non-blocking).
-- Returns similar active stores and similar pending requests
-- as a warning surface for the Flutter form.

DROP FUNCTION IF EXISTS public.check_new_store_duplicate(text, text, text, uuid);

CREATE OR REPLACE FUNCTION public.check_new_store_duplicate(
  p_store_name  text,
  p_city        text,
  p_province    text,
  p_account_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_similar_stores  jsonb;
  v_similar_pending jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- Fuzzy match: existing active stores in same account
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id',         s.id,
      'store_name', s.store_name,
      'area_city',  s.area_city,
      'province',   s.province
    )
  ), '[]'::jsonb)
  INTO v_similar_stores
  FROM public.stores s
  WHERE s.account_id = p_account_id
    AND s.is_active  = true
    AND s.status     = 'active'
    AND (
      s.store_name  ILIKE '%' || TRIM(p_store_name) || '%'
      OR TRIM(p_store_name) ILIKE '%' || s.store_name || '%'
    );

  -- Fuzzy match: existing pending requests in same account
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id',             r.id,
      'store_name',     r.store_name,
      'city',           r.city,
      'province',       r.province,
      'requested_by',   r.requested_by_name,
      'requested_at',   r.requested_at
    )
  ), '[]'::jsonb)
  INTO v_similar_pending
  FROM public.new_store_requests r
  WHERE r.account_id   = p_account_id
    AND r.status       = 'pending'
    AND r.is_archived  = false
    AND (
      r.store_name ILIKE '%' || TRIM(p_store_name) || '%'
      OR TRIM(p_store_name) ILIKE '%' || r.store_name || '%'
    );

  RETURN jsonb_build_object(
    'similar_active_stores',   v_similar_stores,
    'similar_pending_requests', v_similar_pending
  );
END;
$$;


-- ============================================================
-- §4  submit_new_store_request
-- ============================================================
-- Callers: Ops roles (hrco/atl/tl/om) + HA/SA.
-- Blocked: Recruitment, Encoder, Viewer (role not in ops or full-access).
-- Hard-blocks duplicate active store and duplicate pending request.
-- Notifies all HA/SA on successful submission.

DROP FUNCTION IF EXISTS public.submit_new_store_request(jsonb);

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
    SELECT
      up.auth_user_id,
      ro.role_name
    FROM public.users_profile up
    LEFT JOIN public.roles ro ON ro.id = up.role_id
    WHERE up.is_active = true
      AND up.auth_user_id IS NOT NULL
      AND ro.role_name IN ('Super Admin', 'Head Admin')
  LOOP
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
-- §5  approve_new_store_request
-- ============================================================
-- HA/SA only. Atomic:
--   1. Lock request row FOR UPDATE
--   2. Assert pending
--   3. INSERT active store into public.stores
--   4. UPDATE request: approved + created_store_id
--   5. Notify requester

DROP FUNCTION IF EXISTS public.approve_new_store_request(uuid);

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

  IF v_requester_auth IS NOT NULL THEN
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
  END IF;

  RETURN jsonb_build_object(
    'request_id',    p_request_id,
    'store_id',      v_new_store_id,
    'status',        'approved'
  );
END;
$$;


-- ============================================================
-- §6  reject_new_store_request
-- ============================================================
-- HA/SA only. Requires a non-empty reason. Notifies requester.

DROP FUNCTION IF EXISTS public.reject_new_store_request(uuid, text);

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

  IF v_requester_auth IS NOT NULL THEN
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
  END IF;

  RETURN jsonb_build_object(
    'request_id', p_request_id,
    'status',     'rejected'
  );
END;
$$;


-- ============================================================
-- §7  get_new_store_requests
-- ============================================================
-- Scoped list for Request Center.
--   HA/SA: all rows, optionally filtered by status.
--   Others: own rows only (requested_by = caller).
-- RLS on the table enforces the row-level rule; this RPC adds
-- the status filter and returns a clean jsonb payload.

DROP FUNCTION IF EXISTS public.get_new_store_requests(text);

CREATE OR REPLACE FUNCTION public.get_new_store_requests(
  p_status  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id  uuid;
  v_rows       jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();

  SELECT COALESCE(jsonb_agg(row_to_json(r.*) ORDER BY r.requested_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM public.new_store_requests r
  WHERE r.is_archived = false
    AND (p_status IS NULL OR r.status = p_status)
    AND (
      public.i_have_full_access()
      OR r.requested_by = v_caller_id
    );

  RETURN v_rows;
END;
$$;


-- ============================================================
-- §8  GRANT / REVOKE
-- ============================================================

-- Grant RPC execute to authenticated users (RLS + internal role
-- guards inside each function restrict access further).
GRANT EXECUTE ON FUNCTION public.check_new_store_duplicate(text, text, text, uuid)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.submit_new_store_request(jsonb)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.approve_new_store_request(uuid)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.reject_new_store_request(uuid, text)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_new_store_requests(text)
  TO authenticated;

-- Revoke direct table writes from authenticated users.
-- Reads are permitted via the nsr_select RLS policy above.
REVOKE INSERT, UPDATE, DELETE ON public.new_store_requests FROM authenticated;
