-- Migration: 20262606000164_fix_account_archive_approval_and_rejection_rpcs.sql
-- Created: 2026-11-24T05:12:44.219Z
-- Description: Fix Account Archive approval and rejection via dedicated SECURITY DEFINER RPCs and align notifications RLS update policy for Super Admin

BEGIN;

-- 1. Create dedicated RPC: reject_account_archive
CREATE OR REPLACE FUNCTION public.reject_account_archive(
  p_notification_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_reviewer_id uuid;
  v_notif public.notifications;
  v_trimmed_reason text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_have_full_access() OR public.get_my_role_level() >= 100) THEN
    RAISE EXCEPTION 'Only Super Admin can reject account archive requests.' USING ERRCODE = '42501';
  END IF;

  v_trimmed_reason := TRIM(COALESCE(p_reason, ''));
  IF v_trimmed_reason = '' THEN
    RAISE EXCEPTION 'A rejection reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_notif
    FROM public.notifications
   WHERE id = p_notification_id
     AND event_type = 'account_archive_request'
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account archive request notification % not found.', p_notification_id USING ERRCODE = 'P0002';
  END IF;

  -- Update notification status to rejected
  UPDATE public.notifications
     SET is_read = true,
         is_archived = true,
         read_at = COALESCE(read_at, now()),
         message = format('[REJECTED: %s] %s', v_trimmed_reason, v_notif.message)
   WHERE id = p_notification_id;

  -- Safe profile resolution for actor
  BEGIN
    v_reviewer_id := public.get_current_profile_id();
  EXCEPTION WHEN OTHERS THEN
    v_reviewer_id := NULL;
  END;

  -- Safe audit log write
  BEGIN
    INSERT INTO public.audit_logs (
      module,
      action,
      record_id,
      actor_id,
      new_data
    ) VALUES (
      'approvals',
      'UPDATE',
      p_notification_id::text,
      v_reviewer_id,
      jsonb_build_object(
        'event', 'ACCOUNT_ARCHIVE_REJECTED',
        'notification_id', p_notification_id,
        'rejection_remarks', v_trimmed_reason,
        'account_id', v_notif.reference_id
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'notification_id', p_notification_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reject_account_archive(uuid, text) TO authenticated, service_role;

-- 2. Create dedicated RPC: approve_account_archive
CREATE OR REPLACE FUNCTION public.approve_account_archive(
  p_notification_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_reviewer_id uuid;
  v_notif public.notifications;
  v_account_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.i_have_full_access() OR public.get_my_role_level() >= 100) THEN
    RAISE EXCEPTION 'Only Super Admin can approve account archive requests.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_notif
    FROM public.notifications
   WHERE id = p_notification_id
     AND event_type = 'account_archive_request'
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account archive request notification % not found.', p_notification_id USING ERRCODE = 'P0002';
  END IF;

  v_account_id := v_notif.reference_id::uuid;

  -- Safe profile resolution for actor
  BEGIN
    v_reviewer_id := public.get_current_profile_id();
  EXCEPTION WHEN OTHERS THEN
    v_reviewer_id := NULL;
  END;

  -- Deactivate account in public.accounts (triggers trg_account_archive_cascade_stores)
  UPDATE public.accounts
     SET is_active = false,
         status = 'Inactive',
         updated_at = now(),
         updated_by = COALESCE(v_reviewer_id, updated_by)
   WHERE id = v_account_id;

  -- Update notification to approved/reviewed
  UPDATE public.notifications
     SET is_read = true,
         is_archived = true,
         read_at = COALESCE(read_at, now())
   WHERE id = p_notification_id;

  -- Safe audit log write
  BEGIN
    INSERT INTO public.audit_logs (
      module,
      action,
      record_id,
      actor_id,
      new_data
    ) VALUES (
      'plantilla',
      'UPDATE',
      v_account_id::text,
      v_reviewer_id,
      jsonb_build_object(
        'event', 'ACCOUNT_ARCHIVE_APPROVED',
        'account_id', v_account_id,
        'notification_id', p_notification_id
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'account_id', v_account_id,
    'notification_id', p_notification_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.approve_account_archive(uuid) TO authenticated, service_role;

-- 3. Align notifications UPDATE RLS policy to allow Super Admin / Full Access
DROP POLICY IF EXISTS "notif_update_own" ON public.notifications;
CREATE POLICY "notif_update_own" ON public.notifications
FOR UPDATE TO authenticated
USING (
  (recipient_user_id = auth.uid())
  OR (SELECT i_have_full_access())
)
WITH CHECK (
  (recipient_user_id = auth.uid())
  OR (SELECT i_have_full_access())
);

-- 4. Clean up existing account archive notifications so they are not user-siloed
UPDATE public.notifications
   SET recipient_user_id = NULL
 WHERE event_type = 'account_archive_request'
   AND recipient_user_id IS NOT NULL;

COMMIT;
