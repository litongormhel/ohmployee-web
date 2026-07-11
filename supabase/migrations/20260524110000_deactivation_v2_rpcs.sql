-- ============================================================
-- OHM2026_2058 — Deactivation Request v2 — RPCs + View
-- Migration:  20260524110000_deactivation_v2_rpcs.sql
-- Depends on: 20260524100000_deactivation_v2_foundation.sql
-- ============================================================
-- Sections:
--   §1  v_deactivation_requests view
--   §2  create_deactivation_request RPC
--   §3  approve_deactivation_requests_batch RPC
--   §4  reject_deactivation_requests_batch RPC
--   §5  resubmit_deactivation_request RPC
--   §6  archive_processed_deactivations RPC
--   §7  GRANT / REVOKE
--
-- Notification contract (notifications table):
--   recipient_role        — caller's role name (denormalized for display)
--   recipient_user_id     — requestor_profile_id
--   notification_type     — 'deactivation'
--   event_type            — 'DEACTIVATION_PROCESSED'
--   title                 — 'Deactivation Requests Processed'
--   message               — '{N} deactivation request(s) have been approved/rejected.'
--   deep_link_route       — '/deactivation/my-requests'
--   reference_type        — 'deactivation_batch'
--   reference_id          — batch_id::text
--
-- Validation Queries (run manually after applying):
--   V1 – View returns correct columns
--     SELECT column_name FROM information_schema.columns
--     WHERE table_name = 'v_deactivation_requests'
--     ORDER BY ordinal_position;
--   V2 – All 5 RPCs exist
--     SELECT proname FROM pg_proc
--     WHERE pronamespace = 'public'::regnamespace
--       AND proname IN (
--         'create_deactivation_request',
--         'approve_deactivation_requests_batch',
--         'reject_deactivation_requests_batch',
--         'resubmit_deactivation_request',
--         'archive_processed_deactivations'
--       )
--     ORDER BY proname;
--   V3 – create_deactivation_request: requires Ops caller
--     -- (invoke as non-ops user, expect 42501 error)
--   V4 – Duplicate prevention: second call for same plantilla_id returns existing
--     -- (invoke twice, expect same request_id returned on second call)
--   V5 – approve batch: batch_id shared across all rows in one call
--     SELECT batch_id, COUNT(*) FROM employee_deactivation_requests
--     WHERE status = 'Approved' GROUP BY batch_id;
--   V6 – Notification: exactly one row per unique requestor after batch approve
--     SELECT recipient_user_id, COUNT(*) FROM notifications
--     WHERE notification_type = 'deactivation' GROUP BY recipient_user_id;
--   V7 – resubmit: increments resubmit_count
--     SELECT resubmit_count FROM employee_deactivation_requests
--     WHERE plantilla_id = '<test_id>' ORDER BY created_at DESC LIMIT 1;
--   V8 – archive sweep: plantilla rows soft-deleted after 15d
--     SELECT COUNT(*) FROM plantilla WHERE is_deleted = true AND deactivated_at < NOW() - INTERVAL '15 days';
-- ============================================================


-- ============================================================
-- §1  v_deactivation_requests view
-- ============================================================
-- Query surface for Backoffice module (global queue) and Ops
-- My Requests screen. Filtered to non-archived rows only.
-- RLS on the underlying table still applies — Ops users see
-- only their own rows; Backoffice sees all.

DROP VIEW IF EXISTS public.v_deactivation_requests;

CREATE VIEW public.v_deactivation_requests AS
SELECT
  r.id,
  r.plantilla_id,
  r.employee_name,
  r.employee_no,
  r.account_name,
  r.account_id,
  g.group_name,
  r.group_id,
  r.status,
  r.batch_id,
  r.resubmit_count,
  r.created_at,
  r.processed_at,
  r.is_archived,
  -- Requestor display name: "Last, First" format
  CASE
    WHEN req.last_name IS NOT NULL AND req.first_name IS NOT NULL
      THEN req.last_name || ', ' || req.first_name
    ELSE COALESCE(req.full_name, 'Unknown')
  END AS requestor_display_name,
  r.requestor_profile_id,
  -- Processor display name: nullable
  CASE
    WHEN proc.last_name IS NOT NULL AND proc.first_name IS NOT NULL
      THEN proc.last_name || ', ' || proc.first_name
    WHEN proc.full_name IS NOT NULL
      THEN proc.full_name
    ELSE NULL
  END AS processor_display_name,
  r.processed_by_profile_id
FROM public.employee_deactivation_requests r
LEFT JOIN public.groups g
  ON g.id = r.group_id
LEFT JOIN public.users_profile req
  ON req.id = r.requestor_profile_id
LEFT JOIN public.users_profile proc
  ON proc.id = r.processed_by_profile_id
WHERE r.is_archived = false;

COMMENT ON VIEW public.v_deactivation_requests IS
  'Non-archived deactivation request rows with resolved display names. '
  'RLS on employee_deactivation_requests applies to all queries through this view.';


-- ============================================================
-- §2  create_deactivation_request
-- ============================================================
-- Called by Flutter when an Ops user tags an employee inactive.
-- Idempotent: if a Pending request already exists for this
-- plantilla_id, returns the existing row without creating a
-- duplicate (the unique partial index enforces this invariant).

CREATE OR REPLACE FUNCTION public.create_deactivation_request(
  p_plantilla_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id         uuid;
  v_row               public.plantilla;
  v_existing_req_id   uuid;
  v_new_req_id        uuid;
  v_group_id          uuid;
BEGIN
  -- ── Auth guard ───────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Ops role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Lock and load plantilla row ──────────────────────────────
  SELECT * INTO v_row
    FROM public.plantilla
   WHERE id = p_plantilla_id
     AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plantilla row not found or already deleted: %', p_plantilla_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Scope check ──────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_row.account_id::text = ANY(public.get_my_allowed_accounts())) THEN
      RAISE EXCEPTION 'Account not in caller scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Status check ─────────────────────────────────────────────
  -- Idempotent: if already Pending Deactivation, return existing request
  IF v_row.status = 'Pending Deactivation' THEN
    SELECT id INTO v_existing_req_id
      FROM public.employee_deactivation_requests
     WHERE plantilla_id = p_plantilla_id
       AND status = 'Pending'
       AND is_archived = false
     LIMIT 1;

    RETURN jsonb_build_object(
      'request_id',  v_existing_req_id,
      'plantilla_id', p_plantilla_id,
      'status', 'Pending',
      'idempotent', true
    );
  END IF;

  -- Handle legacy 'For Deactivation' gracefully before data migration
  IF v_row.status = 'For Deactivation' THEN
    RETURN jsonb_build_object(
      'request_id',  NULL,
      'plantilla_id', p_plantilla_id,
      'status', 'Pending',
      'idempotent', true,
      'note', 'Legacy For Deactivation row — awaiting data migration'
    );
  END IF;

  -- Allow Inactive (first-time request) and Rejected Deactivation (resubmission).
  -- Block Deactivated, Active, and any other status.
  IF v_row.status NOT IN ('Inactive', 'Rejected Deactivation') THEN
    RAISE EXCEPTION 'Employee must be Inactive or Rejected Deactivation to request deactivation. Current status: %',
      v_row.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Resolve group_id ─────────────────────────────────────────
  SELECT group_id INTO v_group_id
    FROM public.user_scopes
   WHERE user_id = v_caller_id
   LIMIT 1;

  -- ── Idempotent check: abort early if a Pending request exists ─
  -- uq_deact_req_pending_per_employee is a partial unique INDEX, not a
  -- named table constraint, so ON CONFLICT ON CONSTRAINT cannot reference
  -- it. Use an explicit pre-insert SELECT instead; the partial index
  -- remains as a race-condition safety net (caught by EXCEPTION WHEN
  -- unique_violation below).
  SELECT id INTO v_existing_req_id
    FROM public.employee_deactivation_requests
   WHERE plantilla_id = p_plantilla_id
     AND status = 'Pending'
     AND is_archived = false
   LIMIT 1;

  IF v_existing_req_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'request_id',   v_existing_req_id,
      'plantilla_id', p_plantilla_id,
      'status',       'Pending',
      'idempotent',   true
    );
  END IF;

  -- ── Create request ───────────────────────────────────────────
  INSERT INTO public.employee_deactivation_requests (
    plantilla_id,
    requestor_profile_id,
    group_id,
    account_id,
    employee_name,
    employee_no,
    account_name,
    status
  ) VALUES (
    p_plantilla_id,
    v_caller_id,
    v_group_id,
    v_row.account_id,
    v_row.employee_name,
    v_row.employee_no,
    v_row.account,
    'Pending'
  )
  RETURNING id INTO v_new_req_id;

  -- ── Update plantilla status ──────────────────────────────────
  UPDATE public.plantilla SET
    status                = 'Pending Deactivation',
    inactive_visible_until = NOW() + INTERVAL '30 days',
    updated_at            = NOW()
  WHERE id = p_plantilla_id;

  -- ── Audit log ────────────────────────────────────────────────
  INSERT INTO public.employee_deactivation_audit_log (
    request_id,
    plantilla_id,
    action,
    performed_by_profile_id,
    metadata
  ) VALUES (
    v_new_req_id,
    p_plantilla_id,
    'REQUEST_CREATED',
    v_caller_id,
    jsonb_build_object('employee_name', v_row.employee_name)
  );

  RETURN jsonb_build_object(
    'request_id',  v_new_req_id,
    'plantilla_id', p_plantilla_id,
    'status', 'Pending',
    'idempotent', false
  );

EXCEPTION
  WHEN unique_violation THEN
    -- Race condition safety net: unique index blocked the insert
    SELECT id INTO v_existing_req_id
      FROM public.employee_deactivation_requests
     WHERE plantilla_id = p_plantilla_id
       AND status = 'Pending'
       AND is_archived = false
     LIMIT 1;

    RETURN jsonb_build_object(
      'request_id',  v_existing_req_id,
      'plantilla_id', p_plantilla_id,
      'status', 'Pending',
      'idempotent', true
    );
END;
$$;


-- ============================================================
-- §3  approve_deactivation_requests_batch
-- ============================================================
-- Atomic batch approval. Fails entire batch if any request_id
-- is invalid or not in Pending status (no partial success).

CREATE OR REPLACE FUNCTION public.approve_deactivation_requests_batch(
  p_request_ids   uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_processor_id      uuid;
  v_batch_id          uuid;
  v_valid_count       int;
  v_input_count       int;
  v_invalid_ids       uuid[];
  v_requestor_rec     RECORD;
  v_notifications_sent int := 0;
  v_approved_count    int;
BEGIN
  -- ── Auth guard ───────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_am_backoffice() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Backoffice role required'
      USING ERRCODE = '42501';
  END IF;

  v_processor_id := public.get_current_profile_id();
  IF v_processor_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Input validation ─────────────────────────────────────────
  v_input_count := array_length(p_request_ids, 1);

  IF v_input_count IS NULL OR v_input_count = 0 THEN
    RAISE EXCEPTION 'p_request_ids must be a non-empty array'
      USING ERRCODE = '22023';
  END IF;

  -- Verify all IDs exist AND are Pending — fail whole batch if any invalid
  SELECT COUNT(*) INTO v_valid_count
    FROM public.employee_deactivation_requests
   WHERE id = ANY(p_request_ids)
     AND status = 'Pending'
     AND is_archived = false;

  IF v_valid_count <> v_input_count THEN
    -- Identify which IDs are invalid for a useful error message
    SELECT array_agg(unnested) INTO v_invalid_ids
    FROM unnest(p_request_ids) AS unnested
    WHERE unnested NOT IN (
      SELECT id FROM public.employee_deactivation_requests
       WHERE id = ANY(p_request_ids)
         AND status = 'Pending'
         AND is_archived = false
    );

    RAISE EXCEPTION 'Batch validation failed: % of % request(s) are not in Pending status or do not exist. Invalid IDs: %',
      (v_input_count - v_valid_count), v_input_count, v_invalid_ids
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Generate shared batch_id ─────────────────────────────────
  v_batch_id := gen_random_uuid();

  -- ── Approve all requests ─────────────────────────────────────
  UPDATE public.employee_deactivation_requests SET
    status                    = 'Approved',
    batch_id                  = v_batch_id,
    processed_by_profile_id   = v_processor_id,
    processed_at              = NOW(),
    updated_at                = NOW()
  WHERE id = ANY(p_request_ids);

  GET DIAGNOSTICS v_approved_count = ROW_COUNT;

  -- ── Update plantilla rows ────────────────────────────────────
  UPDATE public.plantilla p SET
    status                    = 'Deactivated',
    deactivated_at            = NOW(),
    deactivated_by            = v_processor_id,
    deactivated_visible_until = NOW() + INTERVAL '15 days',
    inactive_visible_until    = NULL,
    updated_at                = NOW()
  FROM public.employee_deactivation_requests r
  WHERE r.id = ANY(p_request_ids)
    AND p.id = r.plantilla_id;

  -- ── Audit log — one row per approved request ─────────────────
  INSERT INTO public.employee_deactivation_audit_log (
    request_id,
    plantilla_id,
    action,
    performed_by_profile_id,
    metadata
  )
  SELECT
    r.id,
    r.plantilla_id,
    'APPROVED',
    v_processor_id,
    jsonb_build_object(
      'batch_size',   v_approved_count,
      'batch_id',     v_batch_id
    )
  FROM public.employee_deactivation_requests r
  WHERE r.id = ANY(p_request_ids);

  -- ── Notifications — one per unique requestor ──────────────────
  -- Group approved requests by requestor_profile_id, then insert
  -- exactly one notification per requestor (no employee-level spam).
  -- recipient_user_id references auth.users(id) via users_profile.auth_user_id.
  -- Profiles with no linked auth user are skipped silently so a missing
  -- linkage never aborts the whole approval batch.
  FOR v_requestor_rec IN
    SELECT
      r.requestor_profile_id,
      COUNT(*)::int AS request_count,
      COALESCE(ro.role_name, 'ops') AS requestor_role,
      up.auth_user_id AS requestor_auth_user_id
    FROM public.employee_deactivation_requests r
    LEFT JOIN public.users_profile up ON up.id = r.requestor_profile_id
    LEFT JOIN public.roles ro ON ro.id = up.role_id
    WHERE r.id = ANY(p_request_ids)
    GROUP BY r.requestor_profile_id, ro.role_name, up.auth_user_id
  LOOP
    IF v_requestor_rec.requestor_auth_user_id IS NULL THEN
      CONTINUE;
    END IF;

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
      COALESCE(v_requestor_rec.requestor_role, 'ops'),
      v_requestor_rec.requestor_auth_user_id,
      'deactivation',
      'DEACTIVATION_PROCESSED',
      'Deactivation Requests Processed',
      v_requestor_rec.request_count || ' deactivation request(s) have been approved.',
      '/deactivation/my-requests',
      'deactivation_batch',
      v_batch_id::text
    );

    v_notifications_sent := v_notifications_sent + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'approved',           v_approved_count,
    'batch_id',           v_batch_id,
    'notifications_sent', v_notifications_sent
  );
END;
$$;


-- ============================================================
-- §4  reject_deactivation_requests_batch
-- ============================================================
-- Atomic batch rejection. Same all-or-nothing semantics as approve.
-- Rejected employees return to Inactive tab for Ops resubmission.

CREATE OR REPLACE FUNCTION public.reject_deactivation_requests_batch(
  p_request_ids   uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_processor_id        uuid;
  v_batch_id            uuid;
  v_valid_count         int;
  v_input_count         int;
  v_invalid_ids         uuid[];
  v_requestor_rec       RECORD;
  v_notifications_sent  int := 0;
  v_rejected_count      int;
BEGIN
  -- ── Auth guard ───────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_am_backoffice() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Backoffice role required'
      USING ERRCODE = '42501';
  END IF;

  v_processor_id := public.get_current_profile_id();
  IF v_processor_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Input validation ─────────────────────────────────────────
  v_input_count := array_length(p_request_ids, 1);

  IF v_input_count IS NULL OR v_input_count = 0 THEN
    RAISE EXCEPTION 'p_request_ids must be a non-empty array'
      USING ERRCODE = '22023';
  END IF;

  SELECT COUNT(*) INTO v_valid_count
    FROM public.employee_deactivation_requests
   WHERE id = ANY(p_request_ids)
     AND status = 'Pending'
     AND is_archived = false;

  IF v_valid_count <> v_input_count THEN
    SELECT array_agg(unnested) INTO v_invalid_ids
    FROM unnest(p_request_ids) AS unnested
    WHERE unnested NOT IN (
      SELECT id FROM public.employee_deactivation_requests
       WHERE id = ANY(p_request_ids)
         AND status = 'Pending'
         AND is_archived = false
    );

    RAISE EXCEPTION 'Batch validation failed: % of % request(s) are not in Pending status or do not exist. Invalid IDs: %',
      (v_input_count - v_valid_count), v_input_count, v_invalid_ids
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Generate shared batch_id ─────────────────────────────────
  v_batch_id := gen_random_uuid();

  -- ── Reject all requests ──────────────────────────────────────
  UPDATE public.employee_deactivation_requests SET
    status                    = 'Rejected',
    batch_id                  = v_batch_id,
    processed_by_profile_id   = v_processor_id,
    processed_at              = NOW(),
    updated_at                = NOW()
  WHERE id = ANY(p_request_ids);

  GET DIAGNOSTICS v_rejected_count = ROW_COUNT;

  -- ── Update plantilla rows — reset to Rejected Deactivation ───
  -- Employee stays visible in Inactive tab; Ops may resubmit.
  UPDATE public.plantilla p SET
    status                  = 'Rejected Deactivation',
    inactive_visible_until  = NOW() + INTERVAL '30 days',
    updated_at              = NOW()
  FROM public.employee_deactivation_requests r
  WHERE r.id = ANY(p_request_ids)
    AND p.id = r.plantilla_id;

  -- ── Audit log ────────────────────────────────────────────────
  INSERT INTO public.employee_deactivation_audit_log (
    request_id,
    plantilla_id,
    action,
    performed_by_profile_id,
    metadata
  )
  SELECT
    r.id,
    r.plantilla_id,
    'REJECTED',
    v_processor_id,
    jsonb_build_object(
      'batch_size', v_rejected_count,
      'batch_id',   v_batch_id
    )
  FROM public.employee_deactivation_requests r
  WHERE r.id = ANY(p_request_ids);

  -- ── Notifications — one per unique requestor ──────────────────
  -- recipient_user_id references auth.users(id) via users_profile.auth_user_id.
  -- Profiles with no linked auth user are skipped silently so a missing
  -- linkage never aborts the whole rejection batch.
  FOR v_requestor_rec IN
    SELECT
      r.requestor_profile_id,
      COUNT(*)::int AS request_count,
      COALESCE(ro.role_name, 'ops') AS requestor_role,
      up.auth_user_id AS requestor_auth_user_id
    FROM public.employee_deactivation_requests r
    LEFT JOIN public.users_profile up ON up.id = r.requestor_profile_id
    LEFT JOIN public.roles ro ON ro.id = up.role_id
    WHERE r.id = ANY(p_request_ids)
    GROUP BY r.requestor_profile_id, ro.role_name, up.auth_user_id
  LOOP
    IF v_requestor_rec.requestor_auth_user_id IS NULL THEN
      CONTINUE;
    END IF;

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
      COALESCE(v_requestor_rec.requestor_role, 'ops'),
      v_requestor_rec.requestor_auth_user_id,
      'deactivation',
      'DEACTIVATION_PROCESSED',
      'Deactivation Requests Processed',
      v_requestor_rec.request_count || ' deactivation request(s) have been rejected.',
      '/deactivation/my-requests',
      'deactivation_batch',
      v_batch_id::text
    );

    v_notifications_sent := v_notifications_sent + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'rejected',           v_rejected_count,
    'batch_id',           v_batch_id,
    'notifications_sent', v_notifications_sent
  );
END;
$$;


-- ============================================================
-- §5  resubmit_deactivation_request
-- ============================================================
-- Ops resubmission after a rejection. Creates a new request row
-- (incrementing resubmit_count relative to the prior rejected row)
-- and transitions plantilla back to Pending Deactivation.

CREATE OR REPLACE FUNCTION public.resubmit_deactivation_request(
  p_plantilla_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id       uuid;
  v_row             public.plantilla;
  v_prior_count     int;
  v_new_req_id      uuid;
  v_group_id        uuid;
BEGIN
  -- ── Auth guard ───────────────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_am_ops() OR public.i_have_full_access()) THEN
    RAISE EXCEPTION 'Insufficient permissions — Ops role required'
      USING ERRCODE = '42501';
  END IF;

  v_caller_id := public.get_current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'No active profile found for authenticated user'
      USING ERRCODE = '42501';
  END IF;

  -- ── Lock and load plantilla row ──────────────────────────────
  SELECT * INTO v_row
    FROM public.plantilla
   WHERE id = p_plantilla_id
     AND COALESCE(is_deleted, false) = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plantilla row not found or already deleted: %', p_plantilla_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Scope check ──────────────────────────────────────────────
  IF NOT public.i_have_full_access() THEN
    IF NOT (v_row.account_id::text = ANY(public.get_my_allowed_accounts())) THEN
      RAISE EXCEPTION 'Account not in caller scope'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Status check ─────────────────────────────────────────────
  IF v_row.status <> 'Rejected Deactivation' THEN
    RAISE EXCEPTION 'Employee must be in Rejected Deactivation status to resubmit. Current status: %',
      v_row.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ── Resolve resubmit_count from prior rejected rows ──────────
  SELECT COUNT(*) INTO v_prior_count
    FROM public.employee_deactivation_requests
   WHERE plantilla_id = p_plantilla_id
     AND status = 'Rejected';

  -- ── Resolve group_id ─────────────────────────────────────────
  SELECT group_id INTO v_group_id
    FROM public.user_scopes
   WHERE user_id = v_caller_id
   LIMIT 1;

  -- ── Insert new request row ───────────────────────────────────
  -- Unique index uq_deact_req_pending_per_employee prevents duplicates.
  INSERT INTO public.employee_deactivation_requests (
    plantilla_id,
    requestor_profile_id,
    group_id,
    account_id,
    employee_name,
    employee_no,
    account_name,
    status,
    resubmit_count
  ) VALUES (
    p_plantilla_id,
    v_caller_id,
    v_group_id,
    v_row.account_id,
    v_row.employee_name,
    v_row.employee_no,
    v_row.account,
    'Pending',
    v_prior_count  -- equals number of prior rejection cycles
  )
  RETURNING id INTO v_new_req_id;

  -- ── Update plantilla ─────────────────────────────────────────
  UPDATE public.plantilla SET
    status                  = 'Pending Deactivation',
    inactive_visible_until  = NOW() + INTERVAL '30 days',
    updated_at              = NOW()
  WHERE id = p_plantilla_id;

  -- ── Audit log ────────────────────────────────────────────────
  INSERT INTO public.employee_deactivation_audit_log (
    request_id,
    plantilla_id,
    action,
    performed_by_profile_id,
    metadata
  ) VALUES (
    v_new_req_id,
    p_plantilla_id,
    'RESUBMITTED',
    v_caller_id,
    jsonb_build_object(
      'resubmit_count',  v_prior_count,
      'employee_name',   v_row.employee_name
    )
  );

  RETURN jsonb_build_object(
    'request_id',     v_new_req_id,
    'plantilla_id',   p_plantilla_id,
    'status',         'Pending',
    'resubmit_count', v_prior_count
  );

EXCEPTION
  WHEN unique_violation THEN
    -- Another Pending row already exists — return it
    DECLARE v_existing_id uuid;
    BEGIN
      SELECT id INTO v_existing_id
        FROM public.employee_deactivation_requests
       WHERE plantilla_id = p_plantilla_id
         AND status = 'Pending'
         AND is_archived = false
       LIMIT 1;

      RETURN jsonb_build_object(
        'request_id',   v_existing_id,
        'plantilla_id', p_plantilla_id,
        'status',       'Pending',
        'idempotent',   true
      );
    END;
END;
$$;


-- ============================================================
-- §6  archive_processed_deactivations
-- ============================================================
-- System / Edge Function cron — runs daily (service role).
-- Two sweeps:
--   A) Approved requests older than 15 days → soft-delete plantilla
--   B) Inactive employees whose visibility window has expired → soft-delete
--
-- Caller: service role (Edge Function).
-- Not exposed to authenticated users directly.

CREATE OR REPLACE FUNCTION public.archive_processed_deactivations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_system_profile_id         uuid;
  v_archived_deactivated      int := 0;
  v_archived_inactive_expired int := 0;
  v_req                       RECORD;
BEGIN
  -- Attempt to resolve a system profile for audit attribution.
  -- Falls back to NULL if no system user exists; audit log will record
  -- performed_by_profile_id = NULL for cron-driven actions.
  SELECT id INTO v_system_profile_id
    FROM public.users_profile
   WHERE full_name ILIKE '%system%'
      OR full_name ILIKE '%cron%'
   LIMIT 1;

  -- ── Sweep A: Approved requests older than 15 days ────────────
  FOR v_req IN
    SELECT r.id AS request_id, r.plantilla_id
      FROM public.employee_deactivation_requests r
     WHERE r.status = 'Approved'
       AND r.is_archived = false
       AND r.processed_at < NOW() - INTERVAL '15 days'
  LOOP
    -- Archive the request row
    UPDATE public.employee_deactivation_requests SET
      is_archived         = true,
      archived_at         = NOW(),
      archived_by_system  = true,
      updated_at          = NOW()
    WHERE id = v_req.request_id;

    -- Soft-delete the plantilla row
    UPDATE public.plantilla SET
      is_deleted  = true,
      updated_at  = NOW()
    WHERE id = v_req.plantilla_id
      AND COALESCE(is_deleted, false) = false;

    -- Audit the archive action
    INSERT INTO public.employee_deactivation_audit_log (
      request_id,
      plantilla_id,
      action,
      performed_by_profile_id,
      metadata
    ) VALUES (
      v_req.request_id,
      v_req.plantilla_id,
      'ARCHIVED',
      COALESCE(v_system_profile_id, '00000000-0000-0000-0000-000000000000'::uuid),
      jsonb_build_object('sweep', 'approved_15d', 'archived_at', NOW())
    );

    v_archived_deactivated := v_archived_deactivated + 1;
  END LOOP;

  -- ── Sweep B: Inactive tab visibility window expired ──────────
  -- Employees in Pending Deactivation or Rejected Deactivation
  -- whose 30-day inactive_visible_until has passed are soft-deleted
  -- from the Inactive tab (hidden from all views).
  UPDATE public.plantilla SET
    is_deleted  = true,
    updated_at  = NOW()
  WHERE status IN ('Pending Deactivation', 'Rejected Deactivation')
    AND inactive_visible_until IS NOT NULL
    AND inactive_visible_until < NOW()
    AND COALESCE(is_deleted, false) = false;

  GET DIAGNOSTICS v_archived_inactive_expired = ROW_COUNT;

  RETURN jsonb_build_object(
    'archived_deactivated',      v_archived_deactivated,
    'archived_inactive_expired', v_archived_inactive_expired,
    'swept_at',                  NOW()
  );
END;
$$;


-- ============================================================
-- §7  GRANT / REVOKE
-- ============================================================

-- create_deactivation_request — Ops + full-access only
REVOKE ALL ON FUNCTION public.create_deactivation_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_deactivation_request(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_deactivation_request(uuid) TO authenticated;

-- approve_deactivation_requests_batch — Backoffice + full-access only
REVOKE ALL ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) TO authenticated;

-- reject_deactivation_requests_batch — Backoffice + full-access only
REVOKE ALL ON FUNCTION public.reject_deactivation_requests_batch(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_deactivation_requests_batch(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_deactivation_requests_batch(uuid[]) TO authenticated;

-- resubmit_deactivation_request — Ops + full-access only
REVOKE ALL ON FUNCTION public.resubmit_deactivation_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resubmit_deactivation_request(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.resubmit_deactivation_request(uuid) TO authenticated;

-- archive_processed_deactivations — service role / cron only
-- Authenticated access intentionally excluded; invoked via Edge Function.
REVOKE ALL ON FUNCTION public.archive_processed_deactivations() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.archive_processed_deactivations() FROM anon;
REVOKE ALL ON FUNCTION public.archive_processed_deactivations() FROM authenticated;
-- Service role retains execute via superuser path in Edge Function.

COMMENT ON FUNCTION public.create_deactivation_request(uuid) IS
  'Creates a v2 deactivation request for an Inactive or Rejected Deactivation employee. '
  'Idempotent — returns existing Pending row if duplicate. '
  'Caller must be Ops or full-access and within account scope.';

COMMENT ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) IS
  'Atomically approves a batch of Pending deactivation requests. '
  'Fails entire batch if any request is invalid. '
  'Sends one notification per unique requestor.';

COMMENT ON FUNCTION public.reject_deactivation_requests_batch(uuid[]) IS
  'Atomically rejects a batch of Pending deactivation requests. '
  'Fails entire batch if any request is invalid. '
  'Employees return to Inactive tab for Ops resubmission.';

COMMENT ON FUNCTION public.resubmit_deactivation_request(uuid) IS
  'Ops resubmission after a Backoffice rejection. '
  'Creates a new request row; increments resubmit_count.';

COMMENT ON FUNCTION public.archive_processed_deactivations() IS
  'System cron: soft-deletes plantilla rows 15d after approval and '
  'expires Inactive tab visibility windows. Run via Edge Function daily.';
