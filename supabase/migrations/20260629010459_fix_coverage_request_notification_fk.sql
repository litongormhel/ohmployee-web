-- Migration: 20262906000000_fix_coverage_request_notification_fk
-- Created: 2026-06-29
-- Purpose: Fix FK violation on notifications.recipient_user_id that rolls back
--          Coverage Request submissions; guard _rnw_notify_roles against stale
--          auth_user_id references; fix profile-UUID callers in SLA escalation
--          functions.
--
-- Root Cause:
--   users_profile.auth_user_id has a UNIQUE index but NO FK constraint to
--   auth.users(id). When an auth user is deleted, their users_profile row
--   is NOT cleaned up, leaving a stale auth_user_id. _rnw_notify_roles selects
--   these rows (is_active = true AND auth_user_id IS NOT NULL) and passes the
--   stale UUID directly to notify_user(), which then fails the FK constraint
--   notifications_user_id_fkey → auth.users(id) and rolls back the entire
--   submit_coverage_request transaction.
--
--   Additionally, check_closure_request_sla() and check_hc_request_sla() pass
--   requested_by_user_id (a users_profile.id / profile UUID) directly to
--   notify_user() instead of resolving it to an auth UUID first.
--
-- Changes:
--   §1  _rnw_notify_roles       — JOIN auth.users guard + DISTINCT ON dedup +
--                                  per-recipient EXCEPTION with WARNING
--   §2  trg_coverage_request_notify — EXCEPTION isolation on both notification
--                                  paths (submit + decision); WARNING includes
--                                  request_id, recipient UUID, SQLERRM
--   §3  check_closure_request_sla — fix profile-UUID callers via _rnw_auth_uid;
--                                   add JOIN auth.users guard in HA/SA loops
--   §4  check_hc_request_sla    — same treatment as §3
--
-- Smoke Tests:
-- S1: Submit an Add Store Coverage Request — no FK error, status = 'pending'
-- S2: Valid SA/HA/Encoder users receive exactly one notification row each
-- S3: No duplicate notifications for same recipient + same request
-- S4: check_closure_request_sla() and check_hc_request_sla() run without FK errors
-- S5: Save Draft (status stays 'draft') — trigger does not fire; no change
-- S6: Stale-auth users (auth.users row deleted) are silently skipped; WARNING
--     logged with their UUID so they can be found with:
--       SELECT * FROM pg_stat_activity WHERE query LIKE '%_rnw_notify_roles%';
--     or by checking Supabase logs for WARNING lines.
-- S7: Coverage Request approval/rejection still notifies the requester
--
-- Diagnostic: identify stale users_profile.auth_user_id values (read-only):
--   SELECT up.id, up.full_name, up.auth_user_id, up.is_active
--   FROM public.users_profile up
--   LEFT JOIN auth.users au ON au.id = up.auth_user_id
--   WHERE up.auth_user_id IS NOT NULL
--     AND au.id IS NULL;
-- ============================================================


-- ============================================================
-- §1  Fix _rnw_notify_roles
--     Changes:
--       a. JOIN auth.users au ON au.id = up.auth_user_id
--          Skip stale auth references before they reach notify_user()
--       b. DISTINCT ON (up.auth_user_id)
--          Deduplicate recipients when multiple profile rows share a UUID
--       c. Per-recipient EXCEPTION block
--          Absorb any residual FK/constraint error; RAISE WARNING with
--          recipient UUID, role, ref_id, and SQLERRM
-- ============================================================

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
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
$$;

REVOKE ALL ON FUNCTION public._rnw_notify_roles(text[],text,text,text,text,text,text,text)
  FROM PUBLIC, anon;


-- ============================================================
-- §2  Fix trg_coverage_request_notify
--     Changes:
--       a. Wrap _rnw_notify_roles call (draft→pending) in EXCEPTION block.
--          WARNING includes request_id + SQLERRM.
--       b. Wrap notify_user call (pending→approved/rejected) in EXCEPTION block.
--          WARNING includes request_id, resolved auth UUID, and SQLERRM.
--       Only notification code is wrapped — no business logic runs inside
--       these blocks, so genuine validation errors from submit_coverage_request
--       are never swallowed.
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_coverage_request_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_link     text := '/coverage-requests/' || NEW.id::text;
  v_kind     text;
  v_req_auth uuid;
  v_req_role text;
BEGIN
  v_kind := CASE WHEN NEW.request_type::text ILIKE '%group%'
                 THEN 'Coverage Group Request' ELSE 'Coverage Request' END;

  -- Submitted: draft -> pending  →  notify all active SA/HA/Encoder approvers
  IF NEW.status::text = 'pending' AND OLD.status::text = 'draft' THEN
    BEGIN
      PERFORM public._rnw_notify_roles(
        ARRAY['Super Admin','Head Admin','Encoder'],
        'New ' || v_kind,
        COALESCE(NEW.requested_by_name, 'A user') || ' submitted a '
          || lower(v_kind) || ' for review.',
        'coverage_request', 'COVERAGE_REQUEST_SUBMITTED',
        'coverage_request', NEW.id::text, v_link
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING
        'trg_coverage_request_notify: approver notification failed — request_id: %, error: %',
        NEW.id, SQLERRM;
    END;
    RETURN NEW;
  END IF;

  -- Decision: pending -> approved | rejected  →  notify requester
  IF NEW.status IS DISTINCT FROM OLD.status
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
$$;

DROP TRIGGER IF EXISTS trg_coverage_request_notify_upd ON public.coverage_requests;
CREATE TRIGGER trg_coverage_request_notify_upd
  AFTER UPDATE OF status ON public.coverage_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_coverage_request_notify();


-- ============================================================
-- §3  Fix check_closure_request_sla
--     Bug: requested_by_user_id is a users_profile.id (profile UUID).
--          Passing it directly to notify_user() causes FK violation because
--          notify_user() expects an auth.users.id (auth UUID).
--     Fix: resolve via _rnw_auth_uid() which handles both profile_id and
--          auth_user_id. Also add JOIN auth.users guard in HA/SA loops.
-- ============================================================

CREATE OR REPLACE FUNCTION public.check_closure_request_sla()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r          RECORD;
  u          RECORD;
  lvl        SMALLINT;
  v_req_auth uuid;
  v_link     text;
BEGIN
  FOR r IN
    SELECT cr.*, v.id AS vacancy_id,
           COALESCE(a.account_name, v.account, 'Account') AS account_name
    FROM public.vacancy_closure_requests cr
    LEFT JOIN public.vacancies v ON v.vcode    = cr.vacancy_vcode
    LEFT JOIN public.accounts  a ON a.id       = v.account_id
    WHERE cr.status    = 'Pending'
      AND cr.created_at < NOW() - INTERVAL '3 days'
  LOOP
    lvl    := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    v_link := FORMAT('/vacancies/%s/closure-request/%s',
                     COALESCE(r.vacancy_id::TEXT, r.vacancy_vcode), r.id);

    IF NOT public.notification_sla_exists('vacancy_closure', r.id::TEXT, lvl) THEN
      IF lvl = 2 THEN
        -- Notify SA approvers — guard against stale auth references
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Super Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Super Admin',
            'Escalated Closure Request — ' || r.account_name,
            'Closure request for ' || r.vacancy_vcode
              || ' remains unactioned after 5 days.',
            'escalation', 'vacancy_closure', 'vacancy_closure',
            r.id::TEXT, v_link, 2);
        END LOOP;
        -- Fix: resolve profile UUID → auth UUID
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL THEN
          PERFORM public.notify_user(v_req_auth, 'Ops',
            'Your Closure Request Escalated to Super Admin',
            'Your closure request for ' || r.vacancy_vcode
              || ' has been escalated to Super Admin after 5 days of no action.',
            'escalation', 'vacancy_closure', 'vacancy_closure',
            r.id::TEXT, v_link, 2);
        END IF;
      ELSE
        -- Notify HA approvers — guard against stale auth references
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Head Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Head Admin',
            'Unactioned Closure Request — ' || r.account_name,
            'Closure request for ' || r.vacancy_vcode
              || ' has been pending for 3 days with no action from Encoder.',
            'escalation', 'vacancy_closure', 'vacancy_closure',
            r.id::TEXT, v_link, 1);
        END LOOP;
        -- Fix: resolve profile UUID → auth UUID
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL THEN
          PERFORM public.notify_user(v_req_auth, 'Ops',
            'Your Closure Request Has Been Escalated',
            'Your closure request for ' || r.vacancy_vcode
              || ' has been escalated to Head Admin.',
            'escalation', 'vacancy_closure', 'vacancy_closure',
            r.id::TEXT, v_link, 1);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$$;


-- ============================================================
-- §4  Fix check_hc_request_sla
--     Same bug and fix as §3.
--     headcount_requests.requested_by_user_id FK → users_profile(id)
--     so it is a profile UUID, not an auth UUID.
-- ============================================================

CREATE OR REPLACE FUNCTION public.check_hc_request_sla()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r          RECORD;
  u          RECORD;
  lvl        SMALLINT;
  v_req_auth uuid;
BEGIN
  FOR r IN
    SELECT h.*,
           COALESCE(h.account_name_snapshot, a.account_name, 'the account') AS account_name,
           COALESCE(h.group_name_snapshot,   g.group_name,   'Group')       AS group_name
    FROM public.headcount_requests h
    LEFT JOIN public.accounts a ON a.id = h.account_id
    LEFT JOIN public.groups   g ON g.id = COALESCE(h.group_id, a.group_id)
    WHERE LOWER(h.status) = 'pending'
      AND h.created_at    < NOW() - INTERVAL '3 days'
  LOOP
    lvl := CASE WHEN r.created_at < NOW() - INTERVAL '5 days' THEN 2 ELSE 1 END;
    IF NOT public.notification_sla_exists('hc_request', r.id::TEXT, lvl) THEN
      IF lvl = 2 THEN
        -- Notify SA approvers — guard against stale auth references
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Super Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Super Admin',
            'Escalated HC Request — ' || r.group_name,
            'An HC request for ' || r.account_name
              || ' remains unactioned after 5 days.',
            'escalation', 'hc_request', 'headcount_request',
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 2);
        END LOOP;
        -- Fix: resolve profile UUID → auth UUID
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL THEN
          PERFORM public.notify_user(v_req_auth, r.requested_by_role,
            'Your HC Request Escalated to Super Admin',
            'Your HC request for ' || r.account_name
              || ' has been escalated to Super Admin after 5 days of no action.',
            'escalation', 'hc_request', 'headcount_request',
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 2);
        END IF;
      ELSE
        -- Notify HA approvers — guard against stale auth references
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Head Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(u.auth_user_id, 'Head Admin',
            'Unactioned HC Request — ' || r.group_name,
            r.requested_by_name || '''s HC request for ' || r.account_name
              || ' has been pending for 3 days. Please review.',
            'escalation', 'hc_request', 'headcount_request',
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 1);
        END LOOP;
        -- Fix: resolve profile UUID → auth UUID
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL THEN
          PERFORM public.notify_user(v_req_auth, r.requested_by_role,
            'Your HC Request Has Been Escalated',
            'Your HC request for ' || r.account_name
              || ' has been escalated to Head Admin due to no action.',
            'escalation', 'hc_request', 'headcount_request',
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 1);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$$;
