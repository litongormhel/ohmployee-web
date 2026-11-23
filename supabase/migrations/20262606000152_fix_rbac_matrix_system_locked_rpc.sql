-- Migration: 20262606000152_fix_rbac_matrix_system_locked_rpc.sql
-- Description: Fix get_all_roles_effective_permission_matrix to return definition-level is_system_locked directly,
-- preventing Super Admin role protection lock from bleeding into and falsely disabling operational permission toggles across all roles.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_all_roles_effective_permission_matrix()
RETURNS TABLE (
  role_id             uuid,
  role_name           text,
  role_level          integer,
  module_key          text,
  resource_key        text,
  action_key          text,
  scope_mode          text,
  enforcement_tier    text,
  base_allowed        boolean,
  override_allowed    boolean,
  is_allowed          boolean,
  source_type         text,
  has_override        boolean,
  is_sensitive        boolean,
  is_system_locked    boolean,
  description         text,
  sort_order          integer,
  override_reason     text,
  override_updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN: Only Super Admin may view the effective permission matrix'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    r.id AS role_id,
    r.role_name,
    r.role_level,
    d.module_key,
    d.resource_key,
    d.action_key,
    d.scope_mode,
    d.enforcement_type AS enforcement_tier,
    COALESCE(m.is_allowed, false) AS base_allowed,
    o.is_allowed AS override_allowed,
    CASE 
      WHEN r.role_name = 'Super Admin' THEN true
      ELSE COALESCE(o.is_allowed, m.is_allowed, false)
    END AS is_allowed,
    d.enforcement_type AS source_type,
    (o.id IS NOT NULL AND o.is_active = true) AS has_override,
    d.is_sensitive,
    d.is_system_locked,
    d.description,
    d.sort_order,
    o.reason AS override_reason,
    o.updated_at AS override_updated_at
  FROM public.roles r
  CROSS JOIN public.role_permission_definitions d
  LEFT JOIN public.role_permission_matrix m
    ON  m.role_id = r.id
    AND m.permission_definition_id = d.id
  LEFT JOIN public.role_permission_overrides o
    ON  o.role_id = r.id
    AND o.permission_definition_id = d.id
    AND o.is_active = true
  WHERE r.role_level >= 10
  ORDER BY d.module_key, d.sort_order, r.role_level DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_all_roles_effective_permission_matrix() TO authenticated;

COMMIT;
