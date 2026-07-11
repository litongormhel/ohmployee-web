-- ============================================================
-- ohm#7k9m2q4x — Fix HC Request Notification FK Failure
-- Migration: 20260701000001_fix_hc_request_notification_fk.sql
-- Created: 2026-07-01
-- ============================================================
-- Root Cause:
--   notify_hc_request_submitted(), notify_hc_request_actioned(), and
--   notify_hc_request_approved_pending_vcode() all query users_profile for
--   recipient auth_user_ids WITHOUT a JOIN to auth.users. When an auth user is
--   deleted, their users_profile row persists (is_active = true,
--   auth_user_id IS NOT NULL) with a stale UUID. Passing that stale UUID to
--   notify_user() fails the notifications.user_id FK constraint
--   (→ auth.users(id)), rolling back the entire submit_headcount_request
--   transaction.
--
--   Known orphan:  59917295-9844-47d4-bcd9-03742b1c9c8d
--   Found in:      users_profile WHERE role = 'Head Admin' AND is_active = true
--   Missing from:  auth.users
--
-- Changes:
--   §1  notify_hc_request_submitted
--         — JOIN auth.users guard: skip stale/deleted auth recipients
--         — Per-recipient EXCEPTION block: absorb residual FK errors, RAISE WARNING
--         — Trigger-level EXCEPTION block: submission always succeeds
--
--   §2  notify_hc_request_actioned
--         — Replace unsafe COALESCE(auth_user_id, profile_uuid) fallback
--           with _rnw_auth_uid() resolver (profile→auth UUID)
--         — JOIN auth.users guard on the resolver query
--         — Wrap each notify_user() call in EXCEPTION block
--
--   §3  notify_hc_request_approved_pending_vcode
--         — JOIN auth.users guard on Encoder loop
--         — Per-recipient EXCEPTION block with WARNING
--
--   §4  trg_hc_request_notify (from pending 20261220000000)
--         — Harden INSERT path: wrap _rnw_notify_roles call in EXCEPTION block
--         — Harden UPDATE path: wrap notify_user call in EXCEPTION block
--         — Safe as CREATE OR REPLACE: no-op if function already has guards;
--           applies safeguard when 20261220000000 is eventually applied
--
-- Safety:
--   - No schema changes. No data modifications. No approval workflow changes.
--   - Stale-UUID recipients are silently skipped with a WARNING logged.
--   - HC Request submission always succeeds, even if all approver recipients
--     are orphaned.
--   - Idempotent: CREATE OR REPLACE FUNCTION only.
--
-- Preflight (read-only — run before applying to confirm orphan source):
--   SELECT up.id, up.full_name, up.auth_user_id, up.role, up.is_active
--   FROM public.users_profile up
--   LEFT JOIN auth.users au ON au.id = up.auth_user_id
--   WHERE up.auth_user_id IS NOT NULL
--     AND au.id IS NULL
--     AND up.role IN ('Head Admin', 'Super Admin', 'Encoder')
--   ORDER BY up.role, up.full_name;
--   -- Expect: at least one row with auth_user_id = 59917295-9844-47d4-bcd9-03742b1c9c8d
--
-- Postflight (read-only — run after applying):
--   -- 1. Verify notify_hc_request_submitted now contains 'auth.users':
--   SELECT prosrc LIKE '%auth.users%' AS has_auth_guard
--   FROM pg_proc WHERE proname = 'notify_hc_request_submitted';
--   -- Expect: true
--
--   -- 2. Confirm no future FK-violation risk from current stale recipients:
--   SELECT COUNT(*) AS orphan_ha_recipients
--   FROM public.users_profile up
--   LEFT JOIN auth.users au ON au.id = up.auth_user_id
--   WHERE up.is_active = true
--     AND up.auth_user_id IS NOT NULL
--     AND au.id IS NULL
--     AND up.role IN ('Head Admin', 'Super Admin', 'Encoder');
--   -- These rows exist but will now be silently skipped by the guard.
-- ============================================================


-- ============================================================
-- §1  Fix notify_hc_request_submitted
--     Fires AFTER INSERT on headcount_requests.
--     Notifies all active Head Admin recipients about a new HC Request.
--
--     Changes:
--       a. JOIN auth.users au ON au.id = up.auth_user_id
--          Filters out stale/deleted auth references before notify_user()
--       b. Per-recipient EXCEPTION WHEN OTHERS block
--          Absorbs any residual FK/constraint error; RAISE WARNING with UUID
--       c. Outer EXCEPTION WHEN OTHERS on entire notification block
--          Ensures trigger never propagates an error to the submit transaction
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_hc_request_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ha RECORD;
BEGIN
  BEGIN
    FOR v_ha IN
      SELECT up.auth_user_id, up.role
      FROM public.users_profile up
      JOIN auth.users au ON au.id = up.auth_user_id  -- skip stale/deleted auth users
      WHERE up.role = 'Head Admin'
        AND up.is_active = true
        AND up.auth_user_id IS NOT NULL
    LOOP
      BEGIN
        PERFORM public.notify_user(
          v_ha.auth_user_id,
          'Head Admin',
          'New HC Request — ' || COALESCE(NEW.group_name_snapshot, 'Group'),
          NEW.requested_by_name
            || ' submitted a headcount request for '
            || COALESCE(NEW.account_name_snapshot, 'the account')
            || ' (' || COALESCE(NEW.position_name_snapshot, 'Position')
            || ', ' || NEW.headcount_needed::TEXT || ' slot/s). Please review.',
          'submission',
          'hc_request',
          'headcount_request',
          NEW.id::TEXT,
          FORMAT('/headcount-requests/%s', NEW.id),
          NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'notify_hc_request_submitted: skipped recipient %, request_id %, error: %',
          v_ha.auth_user_id, NEW.id, SQLERRM;
      END;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING
      'notify_hc_request_submitted: notification block failed — request_id: %, error: %',
      NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;


-- ============================================================
-- §2  Fix notify_hc_request_actioned
--     Fires AFTER UPDATE on headcount_requests when status/vcode changes.
--     Notifies the requestor on approval, rejection, or VCODE creation.
--
--     Changes:
--       a. Replace COALESCE(auth_user_id, NEW.requested_by_user_id) — the
--          fallback was a profile UUID (FK → users_profile.id), not an auth
--          UUID; passing it to notify_user() causes a FK violation.
--          Now uses _rnw_auth_uid() which resolves profile→auth UUID safely
--          and returns NULL for orphaned/missing profiles.
--       b. JOIN auth.users au ON au.id = up.auth_user_id in the SELECT
--          (inside _rnw_auth_uid) already guards stale UUIDs.
--       c. Each notify_user() call is wrapped in EXCEPTION WHEN OTHERS.
--       d. Outer EXCEPTION block ensures trigger never breaks the caller.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_hc_request_actioned()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_req_auth uuid;
  v_req_role text;
  v_status   text;
  v_vcode    text;
BEGIN
  v_status := LOWER(NEW.status);

  -- Resolve requestor's auth UUID safely (handles both profile UUID and auth UUID input)
  v_req_auth := public._rnw_auth_uid(NEW.requested_by_user_id);

  -- Skip entirely if requestor cannot be resolved to a valid auth.users entry
  IF v_req_auth IS NULL THEN
    RAISE WARNING
      'notify_hc_request_actioned: could not resolve auth UUID for requested_by_user_id %, request_id %; notification skipped.',
      NEW.requested_by_user_id, NEW.id;
    RETURN NEW;
  END IF;

  -- Resolve role for the notification
  SELECT ro.role_name INTO v_req_role
  FROM public.users_profile up
  JOIN public.roles ro ON ro.id = up.role_id
  WHERE up.auth_user_id = v_req_auth
  LIMIT 1;

  BEGIN
    IF v_status IN ('approved', 'head admin approved', 'ha approved') THEN
      BEGIN
        PERFORM public.notify_user(
          v_req_auth,
          COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
          'HC Request Approved',
          'Your headcount request for '
            || COALESCE(NEW.account_name_snapshot, 'the account')
            || ' has been approved. Vcode creation is in progress.',
          'approval',
          'hc_request',
          'headcount_request',
          NEW.id::TEXT,
          FORMAT('/headcount-requests/%s', NEW.id),
          NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'notify_hc_request_actioned: approval notify failed — request_id: %, recipient: %, error: %',
          NEW.id, v_req_auth, SQLERRM;
      END;

    ELSIF v_status = 'rejected' THEN
      BEGIN
        PERFORM public.notify_user(
          v_req_auth,
          COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
          'HC Request Rejected',
          'Your headcount request for '
            || COALESCE(NEW.account_name_snapshot, 'the account')
            || ' was rejected by '
            || COALESCE(NEW.reviewed_by_name, NEW.head_admin_approved_by_name, 'Head Admin')
            || '. Reason: '
            || COALESCE(NEW.reviewer_remarks, NEW.head_admin_remarks, 'No reason provided') || '.',
          'rejection',
          'hc_request',
          'headcount_request',
          NEW.id::TEXT,
          FORMAT('/headcount-requests/%s', NEW.id),
          NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'notify_hc_request_actioned: rejection notify failed — request_id: %, recipient: %, error: %',
          NEW.id, v_req_auth, SQLERRM;
      END;
    END IF;

    -- VCODE notification (on created_vcode or created_vcodes change)
    IF COALESCE(NEW.created_vcode, '') <> ''
       AND NEW.created_vcode IS DISTINCT FROM OLD.created_vcode THEN
      v_vcode := NEW.created_vcode;
    ELSIF NEW.created_vcodes IS NOT NULL
       AND NEW.created_vcodes IS DISTINCT FROM OLD.created_vcodes THEN
      v_vcode := NEW.created_vcodes[1];
    END IF;

    IF v_vcode IS NOT NULL THEN
      BEGIN
        PERFORM public.notify_user(
          v_req_auth,
          COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
          'Vcode Created',
          'Vcode ' || v_vcode
            || ' has been created for your headcount request under '
            || COALESCE(NEW.account_name_snapshot, 'the account') || '.',
          'approval',
          'hc_request',
          'vacancy',
          v_vcode,
          FORMAT('/vacancies/%s', v_vcode),
          NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'notify_hc_request_actioned: vcode notify failed — request_id: %, vcode: %, recipient: %, error: %',
          NEW.id, v_vcode, v_req_auth, SQLERRM;
      END;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING
      'notify_hc_request_actioned: notification block failed — request_id: %, error: %',
      NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;


-- ============================================================
-- §3  Fix notify_hc_request_approved_pending_vcode
--     Fires AFTER UPDATE OF status when status = 'approved_pending_vcode'.
--     Notifies scoped Encoders that a VCODE must be created.
--
--     Changes:
--       a. JOIN auth.users au ON au.id = up.auth_user_id
--          Filters out stale/deleted Encoder auth references
--       b. Per-recipient EXCEPTION WHEN OTHERS block with WARNING
--       c. Outer EXCEPTION block prevents trigger from breaking the caller
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_hc_request_approved_pending_vcode()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_encoder         record;
  v_notified_count  integer := 0;
BEGIN
  IF NOT (
    OLD.status IS DISTINCT FROM NEW.status
    AND NEW.status = 'approved_pending_vcode'
  ) THEN
    RETURN NEW;
  END IF;

  BEGIN
    FOR v_encoder IN
      SELECT DISTINCT ON (up.auth_user_id) up.auth_user_id, up.role
      FROM public.users_profile up
      JOIN auth.users au ON au.id = up.auth_user_id  -- skip stale/deleted auth users
      WHERE up.role = 'Encoder'
        AND up.is_active = true
        AND up.auth_user_id IS NOT NULL
        AND (
          COALESCE(up.scope_type, 'scoped') = 'global'
          OR up.group_id   = NEW.group_id
          OR up.account_id = NEW.account_id
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = up.id
              AND (
                (NEW.group_id   IS NOT NULL AND us.group_id   = NEW.group_id)
                OR (NEW.account_id IS NOT NULL AND us.account_id = NEW.account_id)
              )
          )
        )
      ORDER BY up.auth_user_id
    LOOP
      BEGIN
        PERFORM public.notify_user(
          v_encoder.auth_user_id,
          'Encoder',
          'HC Request Approved — VCODE Needed',
          COALESCE(NEW.head_admin_approved_by_name, 'Head Admin')
            || ' approved a headcount request for '
            || COALESCE(NEW.account_name_snapshot, 'the account')
            || ' (' || COALESCE(NEW.position_name_snapshot, 'Position')
            || ', ' || COALESCE(NEW.headcount_needed, 1)::text
            || ' slot/s). Please create the VCODE and plantilla slot.',
          'approval',
          'hc_request',
          'headcount_request',
          NEW.id::text,
          FORMAT('/headcount-requests/%s', NEW.id),
          NULL
        );
        v_notified_count := v_notified_count + 1;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'notify_hc_request_approved_pending_vcode: skipped recipient %, request_id %, error: %',
          v_encoder.auth_user_id, NEW.id, SQLERRM;
      END;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING
      'notify_hc_request_approved_pending_vcode: notification block failed — request_id: %, error: %',
      NEW.id, SQLERRM;
  END;

  IF v_notified_count = 0 THEN
    PERFORM public.log_audit_event(
      'HeadcountRequest.ApprovedPendingVcode.NoEncoderRecipient',
      'UPDATE',
      NEW.id,
      to_jsonb(OLD),
      jsonb_build_object(
        'request_id',  NEW.id,
        'group_id',    NEW.group_id,
        'account_id',  NEW.account_id,
        'status',      NEW.status,
        'reason',      'No active scoped Encoder with valid auth_user_id found'
      )
    );
  END IF;

  RETURN NEW;
END;
$function$;


-- ============================================================
-- §4  Harden trg_hc_request_notify (from pending 20261220000000)
--     This is a proactive guard: if 20261220000000 has been applied
--     (or when it is applied in the future), this CREATE OR REPLACE
--     adds EXCEPTION isolation to both the INSERT and UPDATE paths
--     so that any per-recipient failure never rolls back the caller.
--
--     The underlying _rnw_notify_roles (fixed in 20262906000000) already
--     has per-recipient EXCEPTION blocks — this adds a trigger-level outer
--     guard as defense-in-depth.
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_hc_request_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_link     text := '/headcount-requests/' || NEW.id::text;
  v_label    text;
  v_req_auth uuid;
  v_req_role text;
BEGIN
  v_label := COALESCE(NEW.position_name_snapshot, 'Headcount')
           || ' ×' || COALESCE(NEW.headcount_needed, 1)::text
           || ' @ ' || COALESCE(NULLIF(NEW.store_name_snapshot, ''),
                                NULLIF(NEW.account_name_snapshot, ''), 'store');

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'Pending Approval' THEN
      BEGIN
        PERFORM public._rnw_notify_roles(
          ARRAY['Super Admin','Head Admin','Encoder'],
          'New Headcount Request',
          COALESCE(NEW.requested_by_name, 'A user') || ' submitted an HC request: ' || v_label || '.',
          'headcount_request', 'HC_REQUEST_SUBMITTED',
          'headcount_request', NEW.id::text, v_link
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'trg_hc_request_notify: approver notification failed — request_id: %, error: %',
          NEW.id, SQLERRM;
      END;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE OF status: notify requestor on Approved / Rejected / Slot Created
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('Approved','Rejected','Slot Created') THEN

    v_req_auth := public._rnw_auth_uid(NEW.requested_by_user_id);
    IF v_req_auth IS NOT NULL THEN
      BEGIN
        SELECT ro.role_name INTO v_req_role
        FROM public.users_profile up
        JOIN public.roles ro ON ro.id = up.role_id
        WHERE up.auth_user_id = v_req_auth
        LIMIT 1;

        PERFORM public.notify_user(
          v_req_auth, COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
          CASE NEW.status
            WHEN 'Approved'     THEN 'Headcount Request Approved'
            WHEN 'Rejected'     THEN 'Headcount Request Rejected'
            ELSE                     'Headcount Request Fulfilled'
          END,
          'Your headcount request ' || v_label || ' is now "' || NEW.status || '".',
          'headcount_request',
          CASE NEW.status
            WHEN 'Approved'     THEN 'HC_REQUEST_APPROVED'
            WHEN 'Rejected'     THEN 'HC_REQUEST_REJECTED'
            ELSE                     'HC_REQUEST_COMPLETED'
          END,
          'headcount_request', NEW.id::text, v_link, NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'trg_hc_request_notify: requester notification failed — request_id: %, recipient: %, error: %',
          NEW.id, v_req_auth, SQLERRM;
      END;
    ELSE
      RAISE WARNING
        'trg_hc_request_notify: could not resolve auth UUID for requested_by_user_id %, request_id %; notification skipped.',
        NEW.requested_by_user_id, NEW.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Note: trg_hc_request_notify_ins / trg_hc_request_notify_upd triggers are
-- created by 20261220000000. We do not recreate them here; this migration only
-- hardens the function body. If 20261220000000 is not yet applied, these
-- triggers don't exist and this §4 is a no-op guard for when it is.
