-- Migration: 20262606000118_reset_permission_overrides_rpc.sql
-- Created: 2026-11-15T03:21:39.543Z
-- Description: reset permission overrides rpc

BEGIN;

CREATE OR REPLACE FUNCTION public.reset_permission_overrides(
  p_role_name    text,
  p_module_key   text DEFAULT NULL,
  p_resource_key text DEFAULT NULL,
  p_action_key   text DEFAULT NULL,
  p_reason       text DEFAULT 'Reset to default base permissions via Web Governance Center'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor_uid   uuid := auth.uid();
  v_actor_id    uuid;
  v_actor_name  text;
  v_role        record;
  v_override    record;
  v_count       integer := 0;
  v_results     jsonb := '[]'::jsonb;
BEGIN
  -- Guard 1: SA only.
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN: Only Super Admin may reset permission overrides'
      USING ERRCODE = '42501';
  END IF;

  SELECT up.id, COALESCE(NULLIF(TRIM(up.full_name), ''), 'Super Admin')
    INTO v_actor_id, v_actor_name
  FROM public.users_profile up
  WHERE up.auth_user_id = v_actor_uid
  LIMIT 1;

  SELECT r.id, r.role_name INTO v_role
  FROM public.roles r WHERE r.role_name = p_role_name LIMIT 1;
  IF v_role.id IS NULL THEN
    RAISE EXCEPTION 'UNKNOWN_ROLE: %', p_role_name USING ERRCODE = '22023';
  END IF;

  -- Guard 2: Super Admin rows are immutable
  IF p_role_name = 'Super Admin' THEN
    RAISE EXCEPTION 'SA_PROTECTED: Super Admin permissions cannot be modified'
      USING ERRCODE = '42501';
  END IF;

  FOR v_override IN
    SELECT o.id, o.role_id, o.permission_definition_id, o.is_allowed AS current_override,
           d.id AS def_id, d.module_key, d.resource_key, d.action_key,
           COALESCE(m.is_allowed, false) AS base_allowed
    FROM public.role_permission_overrides o
    JOIN public.role_permission_definitions d ON d.id = o.permission_definition_id
    LEFT JOIN public.role_permission_matrix m ON m.role_id = o.role_id AND m.permission_definition_id = o.permission_definition_id
    WHERE o.role_id = v_role.id
      AND (p_module_key IS NULL OR d.module_key = p_module_key)
      AND (p_resource_key IS NULL OR d.resource_key = p_resource_key)
      AND (p_action_key IS NULL OR d.action_key = p_action_key)
  LOOP
    DELETE FROM public.role_permission_overrides
    WHERE id = v_override.id;

    PERFORM public.audit_permission_change(
      v_actor_uid,
      v_actor_name,
      v_role.id,
      p_role_name,
      v_override.def_id,
      v_override.module_key,
      v_override.resource_key,
      v_override.action_key,
      v_override.current_override,
      v_override.base_allowed,
      COALESCE(p_reason, 'Reset to default permission')
    );

    v_count := v_count + 1;
    v_results := v_results || jsonb_build_object(
      'module_key', v_override.module_key,
      'resource_key', v_override.resource_key,
      'action_key', v_override.action_key,
      'reverted_to', v_override.base_allowed
    );
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'ok',
    'role_name', p_role_name,
    'reset_count', v_count,
    'reset_items', v_results
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reset_permission_overrides(text, text, text, text, text) TO authenticated;

COMMIT;
