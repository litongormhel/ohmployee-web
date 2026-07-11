-- Migration: 20262906000001_fix_sla_notify_user_smallint_cast
-- Created: 2026-06-29
-- Purpose: Fix type-resolution failure in check_closure_request_sla and
--          check_hc_request_sla — notify_user's p_sla_level is smallint but
--          the SLA level literals (1, 2) resolve as integer, causing overload
--          resolution to fail when real qualifying rows exist. Add explicit
--          ::smallint casts. Pre-existing bug surfaced by executing the function
--          against actual data in staging.
--
-- Smoke Tests:
-- S1: SELECT public.check_hc_request_sla(); returns void with no FK/overload error
-- S2: SELECT public.check_closure_request_sla(); returns void (consistent fix)
-- ============================================================


-- ============================================================
-- §1  Fix check_closure_request_sla — cast SLA level literals to smallint
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
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Super Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(
            u.auth_user_id, 'Super Admin'::text,
            'Escalated Closure Request — ' || r.account_name,
            'Closure request for ' || r.vacancy_vcode
              || ' remains unactioned after 5 days.',
            'escalation'::text, 'vacancy_closure'::text, 'vacancy_closure'::text,
            r.id::TEXT, v_link, 2::smallint);
        END LOOP;
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL THEN
          PERFORM public.notify_user(
            v_req_auth, 'Ops'::text,
            'Your Closure Request Escalated to Super Admin',
            'Your closure request for ' || r.vacancy_vcode
              || ' has been escalated to Super Admin after 5 days of no action.',
            'escalation'::text, 'vacancy_closure'::text, 'vacancy_closure'::text,
            r.id::TEXT, v_link, 2::smallint);
        END IF;
      ELSE
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Head Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(
            u.auth_user_id, 'Head Admin'::text,
            'Unactioned Closure Request — ' || r.account_name,
            'Closure request for ' || r.vacancy_vcode
              || ' has been pending for 3 days with no action from Encoder.',
            'escalation'::text, 'vacancy_closure'::text, 'vacancy_closure'::text,
            r.id::TEXT, v_link, 1::smallint);
        END LOOP;
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL THEN
          PERFORM public.notify_user(
            v_req_auth, 'Ops'::text,
            'Your Closure Request Has Been Escalated',
            'Your closure request for ' || r.vacancy_vcode
              || ' has been escalated to Head Admin.',
            'escalation'::text, 'vacancy_closure'::text, 'vacancy_closure'::text,
            r.id::TEXT, v_link, 1::smallint);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$$;


-- ============================================================
-- §2  Fix check_hc_request_sla — same ::smallint and ::text casts
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
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Super Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(
            u.auth_user_id, 'Super Admin'::text,
            'Escalated HC Request — ' || r.group_name,
            'An HC request for ' || r.account_name
              || ' remains unactioned after 5 days.',
            'escalation'::text, 'hc_request'::text, 'headcount_request'::text,
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 2::smallint);
        END LOOP;
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL THEN
          PERFORM public.notify_user(
            v_req_auth, r.requested_by_role::text,
            'Your HC Request Escalated to Super Admin',
            'Your HC request for ' || r.account_name
              || ' has been escalated to Super Admin after 5 days of no action.',
            'escalation'::text, 'hc_request'::text, 'headcount_request'::text,
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 2::smallint);
        END IF;
      ELSE
        FOR u IN
          SELECT up.auth_user_id
          FROM public.users_profile up
          JOIN auth.users au ON au.id = up.auth_user_id
          WHERE up.role = 'Head Admin' AND up.is_active = true
            AND up.auth_user_id IS NOT NULL
        LOOP
          PERFORM public.notify_user(
            u.auth_user_id, 'Head Admin'::text,
            'Unactioned HC Request — ' || r.group_name,
            r.requested_by_name || '''s HC request for ' || r.account_name
              || ' has been pending for 3 days. Please review.',
            'escalation'::text, 'hc_request'::text, 'headcount_request'::text,
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 1::smallint);
        END LOOP;
        v_req_auth := public._rnw_auth_uid(r.requested_by_user_id);
        IF v_req_auth IS NOT NULL THEN
          PERFORM public.notify_user(
            v_req_auth, r.requested_by_role::text,
            'Your HC Request Has Been Escalated',
            'Your HC request for ' || r.account_name
              || ' has been escalated to Head Admin due to no action.',
            'escalation'::text, 'hc_request'::text, 'headcount_request'::text,
            r.id::TEXT, FORMAT('/headcount-requests/%s', r.id), 1::smallint);
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$$;
