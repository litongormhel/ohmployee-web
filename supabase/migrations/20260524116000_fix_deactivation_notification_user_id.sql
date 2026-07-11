-- ============================================================
-- OHM2026_2064 — Fix deactivation notification recipient_user_id FK
-- Migration:  20260524116000_fix_deactivation_notification_user_id.sql
-- Depends on: 20260524110000_deactivation_v2_rpcs.sql
-- ============================================================
-- Root cause:
--   approve_deactivation_requests_batch and
--   reject_deactivation_requests_batch both inserted notifications with:
--
--     recipient_user_id = r.requestor_profile_id
--
--   requestor_profile_id is a FK to users_profile(id).
--   notifications.recipient_user_id has constraint notifications_user_id_fkey
--   which references auth.users(id) — a different UUID namespace.
--   The insert therefore raised:
--
--     insert or update on table "notifications" violates foreign key
--     constraint "notifications_user_id_fkey"
--
-- Fix:
--   Resolve the linked auth user from users_profile.auth_user_id before
--   inserting the notification. If a requestor profile has no linked
--   auth user (auth_user_id IS NULL), skip the notification silently
--   and continue processing the remaining requestors. This prevents a
--   missing auth linkage from aborting an otherwise valid batch approval
--   or rejection.
--
-- Preserved behaviour:
--   - One notification per unique requestor per batch (grouped by
--     requestor_profile_id + auth_user_id).
--   - processed_by retains the logged-in Backoffice profile id.
--   - processed_at timestamp is unchanged.
--   - Entire batch approval/rejection succeeds before notification loop.
--   - Notification skip is silent (no exception raised).
--
-- Validation Queries (run manually after applying):
--   V1 – Both RPCs still exist
--     SELECT proname FROM pg_proc
--     WHERE pronamespace = 'public'::regnamespace
--       AND proname IN (
--         'approve_deactivation_requests_batch',
--         'reject_deactivation_requests_batch'
--       )
--     ORDER BY proname;
--
--   V2 – Batch approve succeeds and notification row uses auth user id
--     SELECT n.recipient_user_id, u.id AS auth_user_id
--     FROM public.notifications n
--     JOIN auth.users u ON u.id = n.recipient_user_id
--     WHERE n.notification_type = 'deactivation'
--     ORDER BY n.created_at DESC
--     LIMIT 5;
--
--   V3 – Exactly one notification per requestor after a batch approve
--     SELECT recipient_user_id, COUNT(*)
--     FROM public.notifications
--     WHERE notification_type = 'deactivation'
--       AND event_type = 'DEACTIVATION_PROCESSED'
--     GROUP BY recipient_user_id
--     HAVING COUNT(*) > 1;
--     -- Expected: 0 rows per unique batch call (one notif per requestor).
--
--   V4 – No FK violation on approve (invoke with valid pending ids)
--     SELECT approve_deactivation_requests_batch(ARRAY['<pending-request-uuid>']);
--
--   V5 – No FK violation on reject (invoke with valid pending ids)
--     SELECT reject_deactivation_requests_batch(ARRAY['<pending-request-uuid>']);
-- ============================================================


-- ============================================================
-- §1  approve_deactivation_requests_batch — fixed notification loop
-- ============================================================

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
-- §2  reject_deactivation_requests_batch — fixed notification loop
-- ============================================================

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
-- §3  Re-assert grants
-- ============================================================

REVOKE ALL ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION public.reject_deactivation_requests_batch(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_deactivation_requests_batch(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_deactivation_requests_batch(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.approve_deactivation_requests_batch(uuid[]) IS
  'Atomically approves a batch of Pending deactivation requests. '
  'Fails entire batch if any request is invalid. '
  'Sends one notification per unique requestor using auth.users.id '
  'resolved from users_profile.auth_user_id. '
  'OHM2026_2064: fixed notifications_user_id_fkey violation — '
  'was using requestor_profile_id instead of auth_user_id.';

COMMENT ON FUNCTION public.reject_deactivation_requests_batch(uuid[]) IS
  'Atomically rejects a batch of Pending deactivation requests. '
  'Fails entire batch if any request is invalid. '
  'Employees return to Inactive tab for Ops resubmission. '
  'OHM2026_2064: fixed notifications_user_id_fkey violation — '
  'was using requestor_profile_id instead of auth_user_id.';
