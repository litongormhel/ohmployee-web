-- Migration: 20260702000001_notify_user_auth_guard
-- Created: 2026-07-02
-- Purpose: Add a global auth.users existence guard inside notify_user() so a stale or
--          deleted recipient auth UUID is warned and skipped instead of raising a
--          notifications FK violation that rolls back the entire calling transaction.
--
-- Context (ohm#e91c2b7a — Deployment Condition Resolution):
--   The ohm#d4a9c7f2 deployment audit flagged that notification FK hardening was
--   per-call-site only (_rnw_notify_roles, trg_hc_request_notify, SLA checkers, NSR
--   paths — 20262906000000 / 20260629020000 / 20260701000001). notify_user() itself
--   had NO guard, so any UNPATCHED caller passing a stale auth UUID (e.g. the 31
--   orphaned users_profile.auth_user_id values present on staging after a
--   prod→staging reseed, or any future prod orphan) still rolled back its caller.
--   This makes the guard global at the single choke point every path INSERTs through.
--
-- Behavior change is deliberately minimal:
--   • recipient exists in auth.users        → unchanged, notification row inserted
--   • recipient IS NULL                     → unchanged (passes through as before;
--                                             column-level constraints still apply)
--   • recipient NOT NULL but not in auth.users → RAISE WARNING + skip (no insert,
--                                             no exception) — NOT a silent failure
--
-- Smoke Tests:
-- S1: SELECT public.notify_user('00000000-0000-0000-0000-000000000000'::uuid, 'viewer',
--       't', 'm', 'system', 'TEST', 'test', '1', '/x', NULL::smallint);
--     → completes without error, emits WARNING, inserts no notifications row.
-- S2: notify_user with a valid auth user id still inserts exactly one notifications row.
-- S3: pg_get_functiondef of public.notify_user contains 'auth.users' (guard present).

BEGIN;

CREATE OR REPLACE FUNCTION public.notify_user(
  p_recipient_user_id uuid,
  p_recipient_role    text,
  p_title             text,
  p_message           text,
  p_notification_type text,
  p_event_type        text,
  p_reference_type    text,
  p_reference_id      text,
  p_deep_link_route   text,
  p_sla_level         smallint DEFAULT NULL::smallint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Global stale-recipient guard (ohm#e91c2b7a): a recipient auth UUID that no longer
  -- exists in auth.users would violate the notifications recipient FK and roll back
  -- the CALLING transaction (HC submit, coverage approval, etc.). Warn and skip
  -- instead — never silently: the WARNING carries recipient + title for triage.
  IF p_recipient_user_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM auth.users au WHERE au.id = p_recipient_user_id) THEN
    RAISE WARNING
      'notify_user: recipient % not found in auth.users — notification skipped (title: %)',
      p_recipient_user_id, p_title;
    RETURN;
  END IF;

  INSERT INTO public.notifications (
    recipient_user_id,
    recipient_role,
    title,
    message,
    notification_type,
    event_type,
    reference_type,
    reference_id,
    deep_link_route,
    sla_level,
    is_read,
    created_at
  ) VALUES (
    p_recipient_user_id,
    p_recipient_role,
    p_title,
    p_message,
    p_notification_type,
    p_event_type,
    p_reference_type,
    p_reference_id,
    p_deep_link_route,
    p_sla_level,
    FALSE,
    NOW()
  );
END;
$function$;

COMMIT;
