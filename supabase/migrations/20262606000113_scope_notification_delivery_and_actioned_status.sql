-- Migration: 20262606000113_scope_notification_delivery_and_actioned_status.sql
-- Description:
--   1. Scope public.notify_hc_request_submitted() to group/account via public.user_scopes (prevent global fanout)
--      and notify scoped Encoders upon submission.
--   2. Update public.notify_hc_request_actioned() approval check to include 'approved_pending_vcode'.
--   3. Overload public._rnw_notify_roles() with group/account scoping and update public.trg_coverage_request_notify().

BEGIN;

-- ============================================================
-- §1  Update notify_hc_request_submitted()
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_hc_request_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_recip    RECORD;
  v_group_id uuid;
BEGIN
  -- Resolve group_id defensively if NULL on NEW
  v_group_id := NEW.group_id;
  IF v_group_id IS NULL AND NEW.account_id IS NOT NULL THEN
    SELECT a.group_id INTO v_group_id
    FROM public.accounts a
    WHERE a.id = NEW.account_id;
  END IF;

  BEGIN
    FOR v_recip IN
      SELECT DISTINCT ON (up.auth_user_id) up.auth_user_id, up.role
      FROM public.users_profile up
      JOIN auth.users au ON au.id = up.auth_user_id  -- skip stale/deleted auth users
      WHERE up.role IN ('Head Admin', 'Encoder')
        AND up.is_active = true
        AND up.auth_user_id IS NOT NULL
        AND (
          COALESCE(up.scope_type, 'scoped') = 'global'
          OR (NEW.account_id IS NOT NULL AND up.account_id = NEW.account_id)
          OR (v_group_id IS NOT NULL AND up.group_id = v_group_id AND up.account_id IS NULL)
          OR EXISTS (
            SELECT 1
            FROM public.user_scopes us
            WHERE us.user_id = up.id
              AND (
                (NEW.account_id IS NOT NULL AND us.account_id = NEW.account_id)
                OR (v_group_id IS NOT NULL AND us.group_id = v_group_id AND us.account_id IS NULL)
              )
          )
        )
      ORDER BY up.auth_user_id
    LOOP
      BEGIN
        PERFORM public.notify_user(
          v_recip.auth_user_id,
          v_recip.role,
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
          v_recip.auth_user_id, NEW.id, SQLERRM;
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
-- §2  Update notify_hc_request_actioned()
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
    IF v_status IN ('approved', 'head admin approved', 'ha approved', 'approved_pending_vcode') THEN
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
-- §3  Update _rnw_notify_roles() with group/account scoping
-- ============================================================

CREATE OR REPLACE FUNCTION public._rnw_notify_roles(
  p_roles      text[],
  p_title      text,
  p_message    text,
  p_notif_type text,
  p_event_type text,
  p_ref_type   text,
  p_ref_id     text,
  p_deep_link  text,
  p_group_id   uuid,
  p_account_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN
    SELECT DISTINCT ON (up.auth_user_id) up.auth_user_id, ro.role_name
    FROM public.users_profile up
    JOIN public.roles ro         ON ro.id  = up.role_id
    JOIN auth.users   au         ON au.id  = up.auth_user_id  -- skip stale/deleted auth users
    WHERE up.is_active      = true
      AND up.auth_user_id  IS NOT NULL
      AND ro.role_name      = ANY (p_roles)
      AND (
        -- If no scope filter is provided, keep legacy behavior (unscoped fanout)
        (p_group_id IS NULL AND p_account_id IS NULL)
        -- Super Admin is always global
        OR ro.role_name = 'Super Admin'
        OR COALESCE(up.scope_type, 'scoped') = 'global'
        -- Direct profile scope match
        OR (p_account_id IS NOT NULL AND up.account_id = p_account_id)
        OR (p_group_id IS NOT NULL AND up.group_id = p_group_id AND up.account_id IS NULL)
        -- user_scopes table match
        OR EXISTS (
          SELECT 1
          FROM public.user_scopes us
          WHERE us.user_id = up.id
            AND (
              (p_account_id IS NOT NULL AND us.account_id = p_account_id)
              OR (p_group_id IS NOT NULL AND us.group_id = p_group_id AND us.account_id IS NULL)
            )
        )
      )
    ORDER BY up.auth_user_id
  LOOP
    BEGIN
      PERFORM public.notify_user(
        r.auth_user_id, r.role_name, p_title, p_message,
        p_notif_type, p_event_type, p_ref_type, p_ref_id, p_deep_link, NULL
      );
      n := n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        '_rnw_notify_roles: skipped recipient %, role %, ref_id %, error: %',
        r.auth_user_id, r.role_name, p_ref_id, SQLERRM;
    END;
  END LOOP;
  RETURN n;
END;
$function$;

CREATE OR REPLACE FUNCTION public._rnw_notify_roles(
  p_roles      text[],
  p_title      text,
  p_message    text,
  p_notif_type text,
  p_event_type text,
  p_ref_type   text,
  p_ref_id     text,
  p_deep_link  text
)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public._rnw_notify_roles(
    p_roles, p_title, p_message, p_notif_type, p_event_type, p_ref_type, p_ref_id, p_deep_link, NULL, NULL
  );
$function$;

REVOKE ALL ON FUNCTION public._rnw_notify_roles(text[],text,text,text,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._rnw_notify_roles(text[],text,text,text,text,text,text,text,uuid,uuid) FROM PUBLIC, anon;

-- ============================================================
-- §4  Update trg_coverage_request_notify()
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_coverage_request_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_link       text := '/coverage-requests/' || NEW.id::text;
  v_kind       text;
  v_req_auth   uuid;
  v_req_role   text;
  v_account_id uuid;
  v_group_id   uuid;
BEGIN
  v_kind := CASE WHEN NEW.request_type::text ILIKE '%group%'
                 THEN 'Coverage Group Request' ELSE 'Coverage Request' END;

  -- Resolve account_id and group_id for scoping
  v_account_id := NEW.account_id;
  IF v_account_id IS NULL THEN
    SELECT cg.account_id INTO v_account_id
    FROM public.coverage_groups cg
    WHERE cg.id = COALESCE(
      NEW.target_coverage_group_id,
      NEW.source_coverage_group_id,
      NEW.destination_coverage_group_id
    )
    LIMIT 1;
  END IF;

  IF v_account_id IS NOT NULL THEN
    SELECT a.group_id INTO v_group_id
    FROM public.accounts a
    WHERE a.id = v_account_id;
  END IF;

  -- Submitted: draft -> pending (or direct pending insert) → notify all active SA/HA/Encoder approvers (scoped)
  IF (TG_OP = 'INSERT' AND NEW.status::text = 'pending')
     OR (TG_OP = 'UPDATE' AND NEW.status::text = 'pending' AND OLD.status::text = 'draft') THEN
    BEGIN
      PERFORM public._rnw_notify_roles(
        ARRAY['Super Admin','Head Admin','Encoder'],
        'New ' || v_kind,
        COALESCE(NEW.requested_by_name, 'A user') || ' submitted a '
          || lower(v_kind) || ' for review.',
        'coverage_request', 'COVERAGE_REQUEST_SUBMITTED',
        'coverage_request', NEW.id::text, v_link,
        v_group_id, v_account_id
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'trg_coverage_request_notify: approver notification failed — request_id: %, error: %',
        NEW.id, SQLERRM;
    END;
    RETURN NEW;
  END IF;

  -- Decision: pending -> approved | rejected → notify requester
  IF TG_OP = 'UPDATE'
     AND NEW.status IS DISTINCT FROM OLD.status
     AND OLD.status::text = 'pending'
     AND NEW.status::text IN ('approved','rejected') THEN

    v_req_auth := public._rnw_auth_uid(NEW.requested_by);
    IF v_req_auth IS NOT NULL THEN
      BEGIN
        SELECT ro.role_name INTO v_req_role
        FROM public.users_profile up
        JOIN public.roles ro ON ro.id = up.role_id
        WHERE up.auth_user_id = v_req_auth
        LIMIT 1;

        PERFORM public.notify_user(
          v_req_auth, COALESCE(v_req_role, NEW.requested_by_role, 'ops'),
          v_kind || ' ' || initcap(NEW.status::text),
          'Your ' || lower(v_kind) || ' was ' || NEW.status::text
            || COALESCE('. Reason: ' || NULLIF(NEW.rejection_reason, ''), '') || '.',
          'coverage_request',
          CASE WHEN NEW.status::text = 'approved'
               THEN 'COVERAGE_REQUEST_APPROVED' ELSE 'COVERAGE_REQUEST_REJECTED' END,
          'coverage_request', NEW.id::text, v_link, NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING
          'trg_coverage_request_notify: requester notification failed — request_id: %, recipient: %, error: %',
          NEW.id, v_req_auth, SQLERRM;
      END;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

COMMIT;
