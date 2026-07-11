-- OHM2026_0024 - Workforce Pool Push Notification Provider Integration
--
-- Backend-owned push delivery support for Workforce Pool notifications.
-- Preserves notifications table, RLS, and existing pg_notify architecture.

CREATE TABLE IF NOT EXISTS public.push_device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'fcm',
  token text NOT NULL,
  platform text NOT NULL DEFAULT 'unknown',
  is_active boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(provider, token)
);

ALTER TABLE public.push_device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS push_device_tokens_own_select ON public.push_device_tokens;
CREATE POLICY push_device_tokens_own_select
  ON public.push_device_tokens
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid() OR public.i_have_full_access());

CREATE OR REPLACE FUNCTION public.register_push_device_token(
  p_token text,
  p_provider text DEFAULT 'fcm',
  p_platform text DEFAULT 'unknown'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  IF NULLIF(BTRIM(p_token), '') IS NULL THEN
    RAISE EXCEPTION 'Push token is required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.push_device_tokens (
    user_id,
    provider,
    token,
    platform,
    is_active,
    last_seen_at,
    updated_at
  ) VALUES (
    auth.uid(),
    LOWER(COALESCE(NULLIF(BTRIM(p_provider), ''), 'fcm')),
    BTRIM(p_token),
    LOWER(COALESCE(NULLIF(BTRIM(p_platform), ''), 'unknown')),
    true,
    now(),
    now()
  )
  ON CONFLICT (provider, token)
  DO UPDATE SET
    user_id = EXCLUDED.user_id,
    platform = EXCLUDED.platform,
    is_active = true,
    last_seen_at = now(),
    updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_device_token(
  p_token text,
  p_provider text DEFAULT 'fcm'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;

  UPDATE public.push_device_tokens
  SET is_active = false,
      updated_at = now()
  WHERE user_id = auth.uid()
    AND provider = LOWER(COALESCE(NULLIF(BTRIM(p_provider), ''), 'fcm'))
    AND token = BTRIM(COALESCE(p_token, ''));
END;
$$;

CREATE TABLE IF NOT EXISTS public.notification_push_dispatches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  device_token_id uuid NOT NULL REFERENCES public.push_device_tokens(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'fcm',
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_attempt_at timestamptz,
  delivered_at timestamptz,
  error_code text,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(notification_id, device_token_id)
);

ALTER TABLE public.notification_push_dispatches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_push_dispatches_admin_select ON public.notification_push_dispatches;
CREATE POLICY notification_push_dispatches_admin_select
  ON public.notification_push_dispatches
  FOR SELECT
  TO authenticated
  USING (public.i_have_full_access());

CREATE OR REPLACE FUNCTION public.create_workforce_notification(
  p_user_profile_id uuid,
  p_recipient_role text,
  p_title text,
  p_message text,
  p_reference_id text,
  p_reference_type text,
  p_deep_link_route text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid uuid;
  v_notif_id uuid;
  v_action_label text;
BEGIN
  SELECT auth_user_id INTO v_auth_uid
  FROM public.users_profile
  WHERE id = p_user_profile_id
    AND is_active = true
  LIMIT 1;

  IF v_auth_uid IS NULL THEN RETURN; END IF;

  v_action_label := CASE p_reference_type
    WHEN 'workforce_request' THEN 'Open Assignment Request'
    WHEN 'workforce_conversion' THEN 'Open Conversion Review'
    WHEN 'workforce_slot_review' THEN 'Open Slot Review'
    WHEN 'workforce_escalation' THEN 'Review SLA Escalation'
    WHEN 'workforce_assignment' THEN 'Open Pool Employee'
    ELSE 'Open Notification'
  END;

  INSERT INTO public.notifications (
    recipient_role,
    recipient_user_id,
    notification_type,
    event_type,
    title,
    message,
    reference_type,
    reference_id,
    deep_link_route
  ) VALUES (
    p_recipient_role,
    v_auth_uid,
    'workforce_pool',
    COALESCE(NULLIF(p_reference_type, ''), 'workforce_pool'),
    p_title,
    p_message,
    p_reference_type,
    p_reference_id,
    p_deep_link_route
  )
  RETURNING id INTO v_notif_id;

  PERFORM pg_notify(
    'workforce_notification',
    jsonb_build_object(
      'notification_id', v_notif_id,
      'recipient_user_id', v_auth_uid,
      'reference_type', p_reference_type,
      'reference_id', p_reference_id,
      'title', p_title,
      'message', p_message,
      'deep_link_route', p_deep_link_route,
      'action_label', v_action_label
    )::text
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_workforce_push_payload(
  p_notification_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_note record;
  v_context jsonb := '{}'::jsonb;
  v_route text;
BEGIN
  SELECT *
  INTO v_note
  FROM public.notifications
  WHERE id = p_notification_id
    AND notification_type = 'workforce_pool'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'notification_not_found');
  END IF;

  IF NULLIF(v_note.reference_type, '') IS NULL
     OR NULLIF(v_note.reference_id, '') IS NULL
     OR NULLIF(v_note.deep_link_route, '') IS NULL
     OR v_note.recipient_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_payload');
  END IF;

  IF v_note.reference_type IN ('workforce_request', 'workforce_escalation') THEN
    SELECT jsonb_build_object(
      'employee_name', p.employee_name,
      'account_name', a.account_name,
      'store_name', s.store_name,
      'group_name', g.group_name,
      'action_label', CASE
        WHEN v_note.reference_type = 'workforce_escalation' THEN 'Review SLA Escalation'
        ELSE 'Open Assignment Request'
      END
    )
    INTO v_context
    FROM public.workforce_assignment_requests war
    LEFT JOIN public.plantilla p ON p.id = war.employee_id
    LEFT JOIN public.accounts a ON a.id = war.requested_account_id
    LEFT JOIN public.stores s ON s.id = war.requested_store_id
    LEFT JOIN public.groups g ON g.id = war.requested_group_id
    WHERE war.id::text = v_note.reference_id
    LIMIT 1;
  ELSIF v_note.reference_type = 'workforce_conversion' THEN
    SELECT jsonb_build_object(
      'employee_name', employee_name,
      'account_name', COALESCE(target_account, previous_account),
      'store_name', COALESCE(target_store, previous_store),
      'action_label', 'Open Conversion Review'
    )
    INTO v_context
    FROM public.v_workforce_pool_conversion_requests
    WHERE request_id::text = v_note.reference_id
    LIMIT 1;
  ELSIF v_note.reference_type = 'workforce_slot_review' THEN
    SELECT jsonb_build_object(
      'employee_name', previous_employee_name,
      'account_name', NULL,
      'store_name', vcode,
      'action_label', 'Open Slot Review'
    )
    INTO v_context
    FROM public.v_workforce_slot_reviews
    WHERE review_id::text = v_note.reference_id
    LIMIT 1;
  ELSIF v_note.reference_type = 'workforce_assignment' THEN
    SELECT jsonb_build_object(
      'employee_name', p.employee_name,
      'account_name', a.account_name,
      'store_name', s.store_name,
      'action_label', 'Open Pool Employee'
    )
    INTO v_context
    FROM public.workforce_assignments wa
    LEFT JOIN public.plantilla p ON p.id = wa.employee_id
    LEFT JOIN public.accounts a ON a.id = wa.assigned_account_id
    LEFT JOIN public.stores s ON s.id = wa.assigned_store_id
    WHERE wa.id::text = v_note.reference_id
    LIMIT 1;
  END IF;

  v_context := COALESCE(v_context, '{}'::jsonb);
  v_route := v_note.deep_link_route;

  RETURN jsonb_build_object(
    'ok', true,
    'notification_id', v_note.id,
    'recipient_user_id', v_note.recipient_user_id,
    'title', v_note.title,
    'message', v_note.message,
    'reference_type', v_note.reference_type,
    'reference_id', v_note.reference_id,
    'deep_link_route', v_route,
    'employee_name', COALESCE(v_context->>'employee_name', 'Employee'),
    'account_name', COALESCE(v_context->>'account_name', ''),
    'store_name', COALESCE(v_context->>'store_name', ''),
    'group_name', COALESCE(v_context->>'group_name', ''),
    'action_label', COALESCE(v_context->>'action_label', 'Open Notification')
  );
END;
$$;

COMMENT ON FUNCTION public.get_workforce_push_payload(uuid)
  IS 'Normalizes Workforce Pool notification payloads for provider push delivery and fails safely for invalid/missing notification references.';

CREATE OR REPLACE FUNCTION public.record_push_dispatch_attempt(
  p_notification_id uuid,
  p_device_token_id uuid,
  p_status text,
  p_error_message text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.notification_push_dispatches
  SET status = p_status,
      attempts = attempts + 1,
      last_attempt_at = now(),
      delivered_at = CASE WHEN p_status = 'delivered' THEN now() ELSE delivered_at END,
      error_message = p_error_message,
      updated_at = now()
  WHERE notification_id = p_notification_id
    AND device_token_id = p_device_token_id;
END;
$$;
