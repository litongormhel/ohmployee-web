-- Migration: 20262606000131_direct_account_group_transfer.sql
-- Created: 2026-11-20T04:48:23.117Z
-- Description: direct account group transfer for Head Admin and Super Admin with audit logs

BEGIN;

CREATE OR REPLACE FUNCTION public.transfer_account_group_direct(
  p_account_id   uuid,
  p_to_group_id  uuid,
  p_reason       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_caller_role_lvl  integer;

  v_current_group_id uuid;
  v_from_group_name  text;
  v_to_group_name    text;
  v_account_name     text;
BEGIN
  -- Authenticate and get caller info
  SELECT id, full_name, public.get_my_role_level()
    INTO v_caller_id, v_caller_name, v_caller_role_lvl
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  -- Role guard: Only Head Admin (>=90) and Super Admin (>=100) may perform direct group transfers
  IF v_caller_role_lvl < 90 THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin role required' USING ERRCODE = '42501';
  END IF;

  -- Validate source account
  SELECT a.group_id, a.account_name, g.group_name
    INTO v_current_group_id, v_account_name, v_from_group_name
  FROM public.accounts a
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE a.id = p_account_id;

  IF v_current_group_id IS NULL THEN
    RAISE EXCEPTION 'account not found' USING ERRCODE = 'P0002';
  END IF;

  -- Validate destination group
  SELECT group_name INTO v_to_group_name
  FROM public.groups
  WHERE id = p_to_group_id;

  IF v_to_group_name IS NULL THEN
    RAISE EXCEPTION 'Destination group not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_current_group_id = p_to_group_id THEN
    RAISE EXCEPTION 'Account is already assigned to this group' USING ERRCODE = 'P0001';
  END IF;

  -- 1. Update account group ownership
  UPDATE public.accounts
  SET group_id = p_to_group_id,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_account_id;

  -- 2. Update stores group ownership
  UPDATE public.stores
  SET group_id = p_to_group_id,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE account_id = p_account_id;

  -- 3. Resolve any pending legacy approval requests for this account
  UPDATE public.account_group_transfer_requests
  SET status = 'approved',
      reviewed_by = v_caller_id,
      reviewed_by_name = v_caller_name,
      reviewed_at = now(),
      updated_at = now()
  WHERE account_id = p_account_id
    AND status = 'pending';

  -- 4. Mandatory audit trail logging
  INSERT INTO public.audit_logs (
    actor_id,
    module,
    action,
    record_id,
    old_data,
    new_data
  ) VALUES (
    auth.uid(),
    'account_group_transfer',
    'UPDATE'::public.audit_action,
    p_account_id,
    jsonb_build_object(
      'account_id', p_account_id,
      'account_name', v_account_name,
      'from_group_id', v_current_group_id,
      'from_group_name', v_from_group_name
    ),
    jsonb_build_object(
      'account_id', p_account_id,
      'account_name', v_account_name,
      'to_group_id', p_to_group_id,
      'to_group_name', v_to_group_name,
      'reason', COALESCE(p_reason, 'Direct group transfer executed by admin'),
      'transferred_by', v_caller_name,
      'transferred_by_role_level', v_caller_role_lvl,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'account_id', p_account_id,
    'account_name', v_account_name,
    'from_group_id', v_current_group_id,
    'from_group_name', v_from_group_name,
    'to_group_id', p_to_group_id,
    'to_group_name', v_to_group_name
  );
END;
$$;

COMMENT ON FUNCTION public.transfer_account_group_direct(uuid, uuid, text) IS
  'Directly reassigns an account and its doors to another group without approval queues. Strictly restricted to Head Admin (90) and Super Admin (100) with audit logging.';

GRANT EXECUTE ON FUNCTION public.transfer_account_group_direct(uuid, uuid, text) TO authenticated;

COMMIT;
