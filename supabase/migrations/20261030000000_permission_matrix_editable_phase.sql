-- Migration: 20261030000000_permission_matrix_editable_phase.sql
-- Ticket: OHM2026_0089 — Full Permission Matrix Admin Tool With SA Editable RBAC Enforcement
--
-- Editable phase of the RBAC Permission Matrix (foundation: 20260528000000_rbac_matrix_foundation).
--
-- Adds:
--   role_permission_overrides            — SA-managed per-role permission overrides
--   role_permission_audit_logs (extend)  — denormalized audit columns required by OHM2026_0089
--   get_effective_permission_matrix(p_role_name)  — SA-only effective grid (base + overrides)
--   get_my_effective_permissions()                — caller's own effective permissions (any authenticated role)
--   upsert_permission_override(...)               — SA-only single override mutation (guards + audit)
--   apply_permission_overrides(p_changes, p_reason) — SA-only atomic batch save
--   audit_permission_change(...)                  — internal audit writer (not client-executable)
--   fn_check_role_permission(...) / fn_current_user_can(...) — effective-permission consumers for backend guards
--
-- Enforcement model:
--   effective = COALESCE(active override, base matrix row). Backend guards may consume
--   fn_current_user_can(); existing hardcoded role checks remain as migration fallback.
--   A database deny can never be bypassed by frontend role checks.
--
-- Safety guards (backend-enforced, cannot be bypassed by UI):
--   1. Super Admin rows are immutable — no override may target the 'Super Admin' role.
--      SA can therefore never lose Admin Tools / Permission Matrix / recovery access,
--      and the last-administrator capability cannot be removed.
--   2. is_system_locked definitions reject overrides for every role (domain invariants:
--      session termination, user creation, security dashboard, admin tools, workflow handoffs).
--   3. All mutations are SA-only (is_super_admin()), SECURITY DEFINER, audited.
--
-- Additive + reversible. Rollback script at end of file (commented).
-- ─────────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: EXTEND AUDIT LOG (denormalized fields required by OHM2026_0089)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.role_permission_audit_logs
  ADD COLUMN IF NOT EXISTS actor_name   text,
  ADD COLUMN IF NOT EXISTS role_name    text,
  ADD COLUMN IF NOT EXISTS module_key   text,
  ADD COLUMN IF NOT EXISTS resource_key text,
  ADD COLUMN IF NOT EXISTS action_key   text;

CREATE INDEX IF NOT EXISTS idx_rpal_created_at
  ON public.role_permission_audit_logs (created_at DESC);


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: OVERRIDES TABLE
-- ═══════════════════════════════════════════════════════════════════════════
-- One active override per role × definition. Updated in place; full change
-- history lives in role_permission_audit_logs (archive-first: no hard deletes,
-- toggling back to the base value keeps the override row as an explicit pin).

CREATE TABLE IF NOT EXISTS public.role_permission_overrides (
  id                       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id                  uuid        NOT NULL REFERENCES public.roles(id),
  permission_definition_id uuid        NOT NULL REFERENCES public.role_permission_definitions(id),
  is_allowed               boolean     NOT NULL,
  reason                   text,
  is_active                boolean     NOT NULL DEFAULT true,
  created_by               uuid        REFERENCES public.users_profile(id),
  updated_by               uuid        REFERENCES public.users_profile(id),
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  UNIQUE (role_id, permission_definition_id)
);

CREATE INDEX IF NOT EXISTS idx_rpo_role_id ON public.role_permission_overrides (role_id);
CREATE INDEX IF NOT EXISTS idx_rpo_def_id  ON public.role_permission_overrides (permission_definition_id);

ALTER TABLE public.role_permission_overrides ENABLE ROW LEVEL SECURITY;

-- SA read only. No client write policies — all mutations through SECURITY DEFINER RPCs.
DROP POLICY IF EXISTS rpo_read_super_admin ON public.role_permission_overrides;
CREATE POLICY rpo_read_super_admin
  ON public.role_permission_overrides
  FOR SELECT
  USING (public.is_super_admin());


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: DEFINITION SEED — Admin Tools module + missing operational actions
-- ═══════════════════════════════════════════════════════════════════════════
-- Admin Tools definitions are is_system_locked = true (never editable — SA recovery path).
-- New operational definitions are is_system_locked = false (editable via overrides).

INSERT INTO public.role_permission_definitions
  (module_key, resource_key, action_key, scope_mode, enforcement_type,
   description, is_sensitive, is_system_locked, sort_order)
VALUES
  -- ── Admin Tools (SA recovery surface — locked) ───────────────────────────
  ('admin_tools', 'admin_tools',       'view',    'global', 'rpc',
   'Open the Admin Tools section (Super Admin owner surface)', true, true, 10),
  ('admin_tools', 'permission_matrix', 'view',    'global', 'rpc',
   'View the editable Permission Matrix admin tool',           true, true, 20),
  ('admin_tools', 'permission_matrix', 'edit',    'global', 'rpc',
   'Edit permissions and save permission overrides',           true, true, 30),
  ('admin_tools', 'archive_all',       'execute', 'global', 'rpc',
   'Execute Archive All operational data (Data Archival Center)', true, true, 40),

  -- ── Plantilla (editable operational permissions) ─────────────────────────
  ('plantilla', 'plantilla',      'import',        'global',  'rpc',
   'Upload and stage Plantilla baseline imports',              true,  false, 30),
  ('plantilla', 'plantilla_slot', 'add_applicant', 'account', 'rpc',
   'Add an applicant into a Plantilla slot (Move to Plantilla)', false, false, 40),

  -- ── Vacancy (editable operational permissions) ───────────────────────────
  ('vacancy', 'vacancy',   'import',   'global',  'rpc',
   'Upload and stage Vacancy imports',                         true,  false, 90),
  ('vacancy', 'applicant', 'transfer', 'account', 'rpc',
   'Transfer or swap applicants between vacancies (Applicant Movement)', false, false, 100),
  ('vacancy', 'vacancy',   'close',    'account', 'rpc',
   'Close a vacancy through the closure workflow',             false, false, 110),

  -- ── HR Emploc (editable operational permission) ──────────────────────────
  ('hr_emploc', 'hr_emploc', 'create', 'account', 'rpc',
   'Create HR Emploc records',                                 false, false, 30)
ON CONFLICT (module_key, resource_key, action_key, scope_mode) DO NOTHING;

-- Unlock existing operational definitions for the editable phase.
-- Invariant-critical definitions stay locked: user_management.*, access_management.*,
-- governance.*, applicant endorse_to_ops / confirm_onboard (workflow stage ownership).
UPDATE public.role_permission_definitions
SET is_system_locked = false
WHERE (module_key, resource_key, action_key) IN (
  ('dashboard',    'dashboard_summary',    'view'),
  ('cencom',       'cencom_data',          'view'),
  ('vacancy',      'vacancy',              'view'),
  ('vacancy',      'vacancy',              'create'),
  ('vacancy',      'vacancy',              'edit'),
  ('vacancy',      'vacancy',              'approve_closure'),
  ('vacancy',      'vacancy',              'archive'),
  ('vacancy',      'applicant',            'create'),
  ('hr_emploc',    'hr_emploc',            'view'),
  ('hr_emploc',    'hr_emploc',            'edit'),
  ('plantilla',    'plantilla_slot',       'view'),
  ('plantilla',    'plantilla_slot',       'transfer'),
  ('deactivation', 'deactivation_request', 'create'),
  ('deactivation', 'deactivation_request', 'process')
);

-- Base matrix seed for the new definitions (allowed rows reflect current behavior).
INSERT INTO public.role_permission_matrix
  (role_id, permission_definition_id, is_allowed, source_type)
SELECT r.id, d.id, true, seed.src
FROM (VALUES
  ('Super Admin', 'admin_tools', 'admin_tools',       'view',          'rpc_guard'),
  ('Super Admin', 'admin_tools', 'permission_matrix', 'view',          'rpc_guard'),
  ('Super Admin', 'admin_tools', 'permission_matrix', 'edit',          'rpc_guard'),
  ('Super Admin', 'admin_tools', 'archive_all',       'execute',       'rpc_guard'),
  ('Super Admin', 'plantilla',   'plantilla',         'import',        'rpc_guard'),
  ('Super Admin', 'plantilla',   'plantilla_slot',    'add_applicant', 'rpc_guard'),
  ('Super Admin', 'vacancy',     'vacancy',           'import',        'rpc_guard'),
  ('Super Admin', 'vacancy',     'applicant',         'transfer',      'rpc_guard'),
  ('Super Admin', 'vacancy',     'vacancy',           'close',         'rpc_guard'),
  ('Super Admin', 'hr_emploc',   'hr_emploc',         'create',        'rpc_guard'),

  ('Head Admin',  'plantilla',   'plantilla',         'import',        'rpc_guard'),
  ('Head Admin',  'plantilla',   'plantilla_slot',    'add_applicant', 'rpc_guard'),
  ('Head Admin',  'vacancy',     'vacancy',           'import',        'rpc_guard'),
  ('Head Admin',  'vacancy',     'applicant',         'transfer',      'rpc_guard'),
  ('Head Admin',  'vacancy',     'vacancy',           'close',         'rpc_guard'),
  ('Head Admin',  'hr_emploc',   'hr_emploc',         'create',        'rpc_guard'),

  ('Encoder',     'plantilla',   'plantilla',         'import',        'rpc_guard'),
  ('Encoder',     'plantilla',   'plantilla_slot',    'add_applicant', 'rpc_guard'),
  ('Encoder',     'vacancy',     'applicant',         'transfer',      'rpc_guard'),

  ('HRCO',        'hr_emploc',   'hr_emploc',         'create',        'rpc_guard'),
  ('HRCO',        'vacancy',     'vacancy',           'close',         'rpc_guard'),
  ('HR Personnel','hr_emploc',   'hr_emploc',         'create',        'rpc_guard')
) AS seed(role_name, module_key, resource_key, action_key, src)
JOIN public.roles r ON r.role_name = seed.role_name
JOIN public.role_permission_definitions d
  ON  d.module_key   = seed.module_key
  AND d.resource_key = seed.resource_key
  AND d.action_key   = seed.action_key
ON CONFLICT (role_id, permission_definition_id) DO NOTHING;

-- Deny-fill: every known role × every definition (skips rows already present).
INSERT INTO public.role_permission_matrix
  (role_id, permission_definition_id, is_allowed, source_type)
SELECT r.id, d.id, false,
  CASE d.enforcement_type
    WHEN 'db_rls'  THEN 'rls_policy'
    WHEN 'rpc'     THEN 'rpc_guard'
    WHEN 'ui_only' THEN 'ui_gate'
    ELSE 'rls_policy'
  END
FROM public.roles r
CROSS JOIN public.role_permission_definitions d
WHERE r.role_name IN (
  'Super Admin', 'Head Admin', 'Operations Manager', 'OM', 'HRCO',
  'ATL', 'TL', 'ATL/TL', 'Encoder', 'HR Personnel',
  'Recruitment Team', 'Recruitment',
  'Back Office', 'Backoffice', 'Backoffice Personnel', 'Viewer'
)
ON CONFLICT (role_id, permission_definition_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: EFFECTIVE PERMISSION CONSUMERS (for backend guards)
-- ═══════════════════════════════════════════════════════════════════════════

-- Effective check for an arbitrary role. Registered permissions only:
-- unknown role/permission → false. Super Admin → always true (recovery invariant).
CREATE OR REPLACE FUNCTION public.fn_check_role_permission(
  p_role_name    text,
  p_module_key   text,
  p_resource_key text,
  p_action_key   text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_effective boolean;
BEGIN
  IF p_role_name = 'Super Admin' THEN
    RETURN true;
  END IF;

  SELECT COALESCE(o.is_allowed, m.is_allowed)
    INTO v_effective
  FROM public.role_permission_matrix m
  JOIN public.roles r ON r.id = m.role_id
  JOIN public.role_permission_definitions d ON d.id = m.permission_definition_id
  LEFT JOIN public.role_permission_overrides o
    ON  o.role_id = m.role_id
    AND o.permission_definition_id = m.permission_definition_id
    AND o.is_active = true
  WHERE r.role_name   = p_role_name
    AND d.module_key  = p_module_key
    AND d.resource_key = p_resource_key
    AND d.action_key  = p_action_key
  LIMIT 1;

  RETURN COALESCE(v_effective, false);
END;
$$;

-- Effective check for the calling user (acting-session aware via get_effective_role()).
-- Backend guards consume this; a matrix deny is authoritative and cannot be
-- bypassed by frontend role checks. Hardcoded guards remain as migration fallback.
CREATE OR REPLACE FUNCTION public.fn_current_user_can(
  p_module_key   text,
  p_resource_key text,
  p_action_key   text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.fn_check_role_permission(
    public.get_effective_role(), p_module_key, p_resource_key, p_action_key
  );
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: READ RPCS
-- ═══════════════════════════════════════════════════════════════════════════

-- SA-only effective grid for the Permission Matrix admin tool.
CREATE OR REPLACE FUNCTION public.get_effective_permission_matrix(
  p_role_name text
)
RETURNS TABLE (
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
    RAISE EXCEPTION 'Only Super Admin may view the effective permission matrix'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    r.role_name,
    r.role_level,
    d.module_key,
    d.resource_key,
    d.action_key,
    d.scope_mode,
    d.enforcement_type                          AS enforcement_tier,
    m.is_allowed                                AS base_allowed,
    o.is_allowed                                AS override_allowed,
    COALESCE(o.is_allowed, m.is_allowed)        AS is_allowed,
    CASE WHEN o.id IS NOT NULL THEN 'override' ELSE m.source_type END AS source_type,
    (o.id IS NOT NULL)                          AS has_override,
    d.is_sensitive,
    d.is_system_locked,
    d.description,
    d.sort_order,
    o.reason                                    AS override_reason,
    o.updated_at                                AS override_updated_at
  FROM public.role_permission_matrix m
  JOIN public.roles r ON r.id = m.role_id
  JOIN public.role_permission_definitions d ON d.id = m.permission_definition_id
  LEFT JOIN public.role_permission_overrides o
    ON  o.role_id = m.role_id
    AND o.permission_definition_id = m.permission_definition_id
    AND o.is_active = true
  WHERE r.role_name = p_role_name
  ORDER BY d.module_key, d.sort_order, d.resource_key, d.action_key;
END;
$$;

-- Caller's own effective permissions — powers frontend gate refresh after save
-- (no logout / restart required). Any authenticated role with a known level.
CREATE OR REPLACE FUNCTION public.get_my_effective_permissions()
RETURNS TABLE (
  module_key   text,
  resource_key text,
  action_key   text,
  is_allowed   boolean,
  source_type  text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role text := public.get_effective_role();
BEGIN
  IF public.get_my_role_level() <= 0 THEN
    RAISE EXCEPTION 'Unknown or inactive role' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    d.module_key,
    d.resource_key,
    d.action_key,
    COALESCE(o.is_allowed, m.is_allowed) AS is_allowed,
    CASE WHEN o.id IS NOT NULL THEN 'override' ELSE m.source_type END AS source_type
  FROM public.role_permission_matrix m
  JOIN public.roles r ON r.id = m.role_id
  JOIN public.role_permission_definitions d ON d.id = m.permission_definition_id
  LEFT JOIN public.role_permission_overrides o
    ON  o.role_id = m.role_id
    AND o.permission_definition_id = m.permission_definition_id
    AND o.is_active = true
  WHERE r.role_name = v_role;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: AUDIT WRITER (internal — not client-executable)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.audit_permission_change(
  p_actor_id      uuid,
  p_actor_name    text,
  p_role_id       uuid,
  p_role_name     text,
  p_definition_id uuid,
  p_module_key    text,
  p_resource_key  text,
  p_action_key    text,
  p_old_value     boolean,
  p_new_value     boolean,
  p_reason        text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO public.role_permission_audit_logs
    (changed_by, actor_name, role_id, role_name, permission_definition_id,
     module_key, resource_key, action_key, old_value, new_value, reason)
  VALUES
    (p_actor_id, p_actor_name, p_role_id, p_role_name, p_definition_id,
     p_module_key, p_resource_key, p_action_key, p_old_value, p_new_value, p_reason);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.audit_permission_change(
  uuid, text, uuid, text, uuid, text, text, text, boolean, boolean, text
) FROM PUBLIC, anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7: MUTATION RPCS (SA only)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.upsert_permission_override(
  p_role_name    text,
  p_module_key   text,
  p_resource_key text,
  p_action_key   text,
  p_is_allowed   boolean,
  p_reason       text DEFAULT NULL
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
  v_def         record;
  v_old_value   boolean;
BEGIN
  -- Guard 1: SA only.
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN: Only Super Admin may edit the permission matrix'
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

  -- Guard 2: Super Admin rows are immutable (no SA lockout, ever).
  IF p_role_name = 'Super Admin' THEN
    RAISE EXCEPTION 'SA_PROTECTED: Super Admin permissions cannot be modified'
      USING ERRCODE = '42501';
  END IF;

  SELECT d.id, d.module_key, d.resource_key, d.action_key,
         d.is_system_locked, d.is_sensitive
    INTO v_def
  FROM public.role_permission_definitions d
  WHERE d.module_key   = p_module_key
    AND d.resource_key = p_resource_key
    AND d.action_key   = p_action_key
  LIMIT 1;
  IF v_def.id IS NULL THEN
    RAISE EXCEPTION 'UNKNOWN_PERMISSION: %.%.%', p_module_key, p_resource_key, p_action_key
      USING ERRCODE = '22023';
  END IF;

  -- Guard 3: system-locked definitions reject overrides (domain invariants,
  -- admin recovery surface, workflow stage ownership).
  IF v_def.is_system_locked THEN
    RAISE EXCEPTION 'SYSTEM_LOCKED: %.%.% cannot be overridden',
      p_module_key, p_resource_key, p_action_key
      USING ERRCODE = '42501';
  END IF;

  -- Current effective value (old_value for audit).
  SELECT COALESCE(o.is_allowed, m.is_allowed)
    INTO v_old_value
  FROM public.role_permission_matrix m
  LEFT JOIN public.role_permission_overrides o
    ON  o.role_id = m.role_id
    AND o.permission_definition_id = m.permission_definition_id
    AND o.is_active = true
  WHERE m.role_id = v_role.id
    AND m.permission_definition_id = v_def.id
  LIMIT 1;

  INSERT INTO public.role_permission_overrides
    (role_id, permission_definition_id, is_allowed, reason, is_active, created_by, updated_by)
  VALUES
    (v_role.id, v_def.id, p_is_allowed, p_reason, true, v_actor_id, v_actor_id)
  ON CONFLICT (role_id, permission_definition_id) DO UPDATE SET
    is_allowed = EXCLUDED.is_allowed,
    reason     = EXCLUDED.reason,
    is_active  = true,
    updated_by = EXCLUDED.updated_by,
    updated_at = now();

  PERFORM public.audit_permission_change(
    v_actor_uid, v_actor_name, v_role.id, p_role_name, v_def.id,
    p_module_key, p_resource_key, p_action_key,
    v_old_value, p_is_allowed, p_reason
  );

  RETURN jsonb_build_object(
    'status', 'ok',
    'role_name', p_role_name,
    'module_key', p_module_key,
    'resource_key', p_resource_key,
    'action_key', p_action_key,
    'old_value', v_old_value,
    'new_value', p_is_allowed
  );
END;
$$;

-- Atomic batch save for staged changes. p_changes is a jsonb array of
-- {role_name, module_key, resource_key, action_key, is_allowed}.
-- Any guard failure aborts the entire batch (single transaction).
CREATE OR REPLACE FUNCTION public.apply_permission_overrides(
  p_changes jsonb,
  p_reason  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_change  jsonb;
  v_results jsonb := '[]'::jsonb;
  v_count   integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN: Only Super Admin may edit the permission matrix'
      USING ERRCODE = '42501';
  END IF;

  IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'array'
     OR jsonb_array_length(p_changes) = 0 THEN
    RAISE EXCEPTION 'EMPTY_CHANGESET: no permission changes provided'
      USING ERRCODE = '22023';
  END IF;

  FOR v_change IN SELECT * FROM jsonb_array_elements(p_changes)
  LOOP
    v_results := v_results || public.upsert_permission_override(
      v_change->>'role_name',
      v_change->>'module_key',
      v_change->>'resource_key',
      v_change->>'action_key',
      (v_change->>'is_allowed')::boolean,
      p_reason
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('status', 'ok', 'applied', v_count, 'changes', v_results);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATION NOTES (run against staging/dev before prod deploy)
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. SELECT count(*) FROM role_permission_definitions;            -- 24 base + 10 new = 34
-- 2. As SA: SELECT count(*) FROM get_effective_permission_matrix('Encoder');   -- 34
-- 3. As SA: SELECT upsert_permission_override('Encoder','plantilla','plantilla','import',false,'test');
--    Then: SELECT is_allowed, source_type FROM get_effective_permission_matrix('Encoder')
--          WHERE module_key='plantilla' AND action_key='import';  -- false / override
--    And:  SELECT count(*) FROM role_permission_audit_logs;       -- +1 with denormalized keys
-- 4. As SA: SELECT upsert_permission_override('Super Admin','vacancy','vacancy','view',false,null);
--    Expected: ERROR SA_PROTECTED
-- 5. As SA: SELECT upsert_permission_override('Head Admin','admin_tools','permission_matrix','edit',true,null);
--    Expected: ERROR SYSTEM_LOCKED
-- 6. As non-SA: SELECT * FROM get_effective_permission_matrix('Viewer');
--    Expected: ERROR 42501
-- 7. As any role: SELECT count(*) FROM get_my_effective_permissions();   -- > 0
-- 8. SELECT fn_check_role_permission('Encoder','plantilla','plantilla','import');  -- reflects override
-- 9. SELECT fn_check_role_permission('Super Admin','admin_tools','permission_matrix','edit'); -- true always

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK (manual, reversible — run only to fully remove the editable phase)
-- ═══════════════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS public.apply_permission_overrides(jsonb, text);
-- DROP FUNCTION IF EXISTS public.upsert_permission_override(text, text, text, text, boolean, text);
-- DROP FUNCTION IF EXISTS public.audit_permission_change(uuid, text, uuid, text, uuid, text, text, text, boolean, boolean, text);
-- DROP FUNCTION IF EXISTS public.get_my_effective_permissions();
-- DROP FUNCTION IF EXISTS public.get_effective_permission_matrix(text);
-- DROP FUNCTION IF EXISTS public.fn_current_user_can(text, text, text);
-- DROP FUNCTION IF EXISTS public.fn_check_role_permission(text, text, text, text);
-- DROP TABLE IF EXISTS public.role_permission_overrides;
-- DELETE FROM public.role_permission_matrix m USING public.role_permission_definitions d
--   WHERE m.permission_definition_id = d.id AND d.module_key = 'admin_tools';
-- DELETE FROM public.role_permission_definitions WHERE module_key = 'admin_tools';
-- -- (New operational definitions and the is_system_locked unlocks may remain; they are inert
-- --  without the override table. To fully revert: re-set is_system_locked = true on the
-- --  14 definitions listed in PART 3 and delete the 6 new operational definitions.)
-- ALTER TABLE public.role_permission_audit_logs
--   DROP COLUMN IF EXISTS actor_name, DROP COLUMN IF EXISTS role_name,
--   DROP COLUMN IF EXISTS module_key, DROP COLUMN IF EXISTS resource_key,
--   DROP COLUMN IF EXISTS action_key;
