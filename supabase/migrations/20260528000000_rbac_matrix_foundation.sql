-- Migration: 20260528000000_rbac_matrix_foundation.sql
-- Ticket: OHM2026_1045 — Implement Read-Only RBAC Permission Matrix Backend
--
-- Creates the read-only RBAC permission registry:
--   role_permission_definitions  — catalog of every recognized capability
--   role_permission_matrix       — role × definition grid (current actual behavior)
--   role_permission_audit_logs   — empty in Phase 1, reserved for future editable phase
--
-- Adds fn_get_permission_matrix(p_role_id) — read-only RPC for the matrix screen.
--
-- Observability layer only. Existing RLS/RPC enforcement is NOT changed.
-- Registry describes authorization truth; it does NOT drive enforcement in Phase 1.
-- Reversible: drop the three tables and the RPC to remove without affecting live policies.
-- ─────────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: TABLE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE public.role_permission_definitions (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  module_key       text        NOT NULL,
  resource_key     text        NOT NULL,
  action_key       text        NOT NULL,
  scope_mode       text        NOT NULL
                               CHECK (scope_mode IN ('global','group','account','self')),
  enforcement_type text        NOT NULL
                               CHECK (enforcement_type IN ('db_rls','rpc','ui_only','planned')),
  description      text        NOT NULL DEFAULT '',
  is_sensitive     boolean     NOT NULL DEFAULT false,
  is_system_locked boolean     NOT NULL DEFAULT true,
  sort_order       integer     NOT NULL DEFAULT 0,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (module_key, resource_key, action_key, scope_mode)
);

-- Matrix: which role is allowed which definition.
-- source_type records WHERE the truth currently lives so the screen never
-- misrepresents a ui_gate row as a backend-enforced permission.
CREATE TABLE public.role_permission_matrix (
  id                       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id                  uuid        NOT NULL REFERENCES public.roles(id),
  permission_definition_id uuid        NOT NULL REFERENCES public.role_permission_definitions(id),
  is_allowed               boolean     NOT NULL DEFAULT false,
  source_type              text        NOT NULL DEFAULT 'rls_policy'
                                       CHECK (source_type IN (
                                         'rls_policy','rpc_guard','trigger','ui_gate','derived'
                                       )),
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  UNIQUE (role_id, permission_definition_id)
);

-- Audit log: empty in Phase 1 (no mutations). Schema reserved so the change
-- trail exists from day one when the editable phase arrives.
CREATE TABLE public.role_permission_audit_logs (
  id                       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  changed_by               uuid        REFERENCES auth.users(id),
  role_id                  uuid        REFERENCES public.roles(id),
  permission_definition_id uuid        REFERENCES public.role_permission_definitions(id),
  old_value                boolean,
  new_value                boolean,
  reason                   text,
  created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_rpm_role_id  ON public.role_permission_matrix (role_id);
CREATE INDEX idx_rpm_def_id   ON public.role_permission_matrix (permission_definition_id);
CREATE INDEX idx_rpd_module   ON public.role_permission_definitions (module_key, sort_order);


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.role_permission_definitions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permission_matrix        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permission_audit_logs    ENABLE ROW LEVEL SECURITY;

-- Definitions: Data Team and above (role_level >= 30 = Encoder) may read.
-- Seeded by migration only — no direct client write policies exist.
CREATE POLICY rpd_read_data_team
  ON public.role_permission_definitions
  FOR SELECT
  USING (public.get_my_role_level() >= 30);

-- Matrix: Data Team and above may read.
CREATE POLICY rpm_read_data_team
  ON public.role_permission_matrix
  FOR SELECT
  USING (public.get_my_role_level() >= 30);

-- Audit log: Super Admin read only. No client write policy (append-only via future RPC).
CREATE POLICY rpal_read_super_admin
  ON public.role_permission_audit_logs
  FOR SELECT
  USING (public.is_super_admin());

-- No INSERT / UPDATE / DELETE policies on any of the three tables.
-- Direct client mutations are blocked by the absence of permissive write policies.


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: READ RPC — fn_get_permission_matrix
-- ═══════════════════════════════════════════════════════════════════════════
-- Auth: role_level >= 30 (governance visibility; not edit).
-- If p_role_id IS NULL → returns the full grid for every role.
-- SECURITY DEFINER + SET search_path — no user-supplied dynamic SQL.

CREATE OR REPLACE FUNCTION public.fn_get_permission_matrix(
  p_role_id uuid DEFAULT NULL
)
RETURNS TABLE (
  role_name        text,
  role_level       integer,
  module_key       text,
  resource_key     text,
  action_key       text,
  scope_mode       text,
  enforcement_type text,
  is_allowed       boolean,
  source_type      text,
  is_sensitive     boolean,
  is_system_locked boolean,
  description      text,
  sort_order       integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.get_my_role_level() < 30 THEN
    RAISE EXCEPTION 'Insufficient permissions to view role permission matrix'
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
    d.enforcement_type,
    m.is_allowed,
    m.source_type,
    d.is_sensitive,
    d.is_system_locked,
    d.description,
    d.sort_order
  FROM public.role_permission_matrix m
  JOIN public.role_permission_definitions d ON d.id = m.permission_definition_id
  JOIN public.roles r                        ON r.id = m.role_id
  WHERE (p_role_id IS NULL OR m.role_id = p_role_id)
  ORDER BY r.role_level DESC, d.module_key, d.sort_order, d.resource_key, d.action_key;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: SEED PERMISSION DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- Enforcement classification:
--   db_rls   — a RLS policy alone controls access at the row level
--   rpc      — action only possible through a SECURITY DEFINER RPC with an internal guard
--   ui_only  — gated purely by Flutter can* checks; NO backend block (non-security)
--   planned  — named in domain spec but not yet enforced anywhere

INSERT INTO public.role_permission_definitions
  (module_key, resource_key, action_key, scope_mode, enforcement_type,
   description, is_sensitive, is_system_locked, sort_order)
VALUES

  -- ── Dashboard ──────────────────────────────────────────────────────────
  ('dashboard', 'dashboard_summary', 'view', 'account', 'db_rls',
   'View dashboard KPIs and summary metrics within assigned scope',
   false, true, 10),

  -- ── CENCOM ─────────────────────────────────────────────────────────────
  ('cencom', 'cencom_data', 'view', 'account', 'db_rls',
   'View CENCOM operational workforce data within assigned scope',
   false, true, 10),

  -- ── Vacancy ────────────────────────────────────────────────────────────
  ('vacancy', 'vacancy', 'view',            'account', 'db_rls',
   'View vacancy listings within assigned scope',
   false, true, 10),
  ('vacancy', 'vacancy', 'create',          'account', 'rpc',
   'Create new vacancies',
   false, true, 20),
  ('vacancy', 'vacancy', 'edit',            'account', 'rpc',
   'Edit vacancy details',
   false, true, 30),
  ('vacancy', 'vacancy', 'approve_closure', 'account', 'rpc',
   'Approve vacancy closure requests',
   true, true, 40),
  ('vacancy', 'vacancy', 'archive',         'account', 'rpc',
   'Soft-archive vacancies (no hard delete)',
   true, true, 50),
  ('vacancy', 'applicant', 'create',          'account', 'db_rls',
   'Add applicants to the vacancy pipeline',
   false, true, 60),
  ('vacancy', 'applicant', 'endorse_to_ops',  'account', 'rpc',
   'Endorse applicants to the Operations workflow stage',
   true, true, 70),
  ('vacancy', 'applicant', 'confirm_onboard', 'account', 'rpc',
   'Confirm applicant onboarding and trigger automatic HR Emploc creation',
   true, true, 80),

  -- ── HR Emploc ──────────────────────────────────────────────────────────
  ('hr_emploc', 'hr_emploc', 'view', 'account', 'db_rls',
   'View HR Emploc records within assigned scope',
   false, true, 10),
  ('hr_emploc', 'hr_emploc', 'edit', 'account', 'rpc',
   'Edit HR Emploc onboarding requirements, deficiency remarks, and deployment readiness',
   false, true, 20),

  -- ── Plantilla ──────────────────────────────────────────────────────────
  ('plantilla', 'plantilla_slot', 'view',     'account', 'db_rls',
   'View Plantilla headcount records within assigned scope',
   false, true, 10),
  ('plantilla', 'plantilla_slot', 'transfer', 'account', 'rpc',
   'Transfer employee from HR Emploc to active Plantilla',
   true, true, 20),

  -- ── Deactivation ───────────────────────────────────────────────────────
  ('deactivation', 'deactivation_request', 'create',  'account', 'rpc',
   'Submit deactivation request for an employee',
   true, true, 10),
  ('deactivation', 'deactivation_request', 'process', 'account', 'rpc',
   'Process and finalize approved deactivation requests (Backoffice)',
   true, true, 20),

  -- ── User Management ────────────────────────────────────────────────────
  ('user_management', 'user_profile', 'view',   'global', 'db_rls',
   'View user profiles in User Management module (HA excludes Super Admin rows)',
   false, true, 10),
  ('user_management', 'user_profile', 'create', 'global', 'rpc',
   'Create new user accounts (Super Admin only)',
   true, true, 20),
  ('user_management', 'user_profile', 'edit',   'global', 'rpc',
   'Edit user roles, group/account scopes, and profile details',
   true, true, 30),
  ('user_management', 'user_session', 'terminate', 'global', 'rpc',
   'Terminate active user sessions (Super Admin only)',
   true, true, 40),

  -- ── Access Management ──────────────────────────────────────────────────
  ('access_management', 'security_event',  'view',  'global', 'rpc',
   'View security dashboard, events, and audit timeline (SA; HA via backend override only)',
   true, true, 10),
  ('access_management', 'temp_permission', 'grant', 'global', 'rpc',
   'Grant temporary elevated permissions to users',
   true, true, 20),

  -- ── Governance ─────────────────────────────────────────────────────────
  ('governance', 'audit_log',              'view', 'global', 'db_rls',
   'View audit logs in Governance module (role_level >= 30)',
   false, true, 10),
  ('governance', 'role_permission_matrix', 'view', 'global', 'db_rls',
   'View read-only RBAC role permission matrix (role_level >= 30)',
   false, true, 20)

ON CONFLICT (module_key, resource_key, action_key, scope_mode) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: SEED MATRIX — ALLOWED (TRUE) ROWS
-- ═══════════════════════════════════════════════════════════════════════════
-- source_type values:
--   rls_policy  — permission is allowed via a RLS SELECT/INSERT policy
--   rpc_guard   — permission is allowed through a SECURITY DEFINER RPC guard
--   trigger     — enforced by a BEFORE UPDATE trigger
--   ui_gate     — gated by Flutter can* checks only (not a security control)
--   derived     — derived from role_level threshold (e.g. level >= 30 for governance)
--
-- Matrix reflects current actual behavior, not desired future behavior.
-- Roles not found in public.roles are silently skipped (safe JOIN, not error).
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.role_permission_matrix
  (role_id, permission_definition_id, is_allowed, source_type)
SELECT
  r.id        AS role_id,
  d.id        AS permission_definition_id,
  true        AS is_allowed,
  seed.src    AS source_type
FROM (VALUES

  -- ── Super Admin (level 100) — full unrestricted access ───────────────────
  ('Super Admin', 'dashboard',         'dashboard_summary',     'view',            'account', 'rls_policy'),
  ('Super Admin', 'cencom',            'cencom_data',           'view',            'account', 'rls_policy'),
  ('Super Admin', 'vacancy',           'vacancy',               'view',            'account', 'rls_policy'),
  ('Super Admin', 'vacancy',           'vacancy',               'create',          'account', 'rpc_guard'),
  ('Super Admin', 'vacancy',           'vacancy',               'edit',            'account', 'rpc_guard'),
  ('Super Admin', 'vacancy',           'vacancy',               'approve_closure', 'account', 'rpc_guard'),
  ('Super Admin', 'vacancy',           'vacancy',               'archive',         'account', 'rpc_guard'),
  ('Super Admin', 'vacancy',           'applicant',             'create',          'account', 'rls_policy'),
  ('Super Admin', 'vacancy',           'applicant',             'endorse_to_ops',  'account', 'rpc_guard'),
  ('Super Admin', 'vacancy',           'applicant',             'confirm_onboard', 'account', 'rpc_guard'),
  ('Super Admin', 'hr_emploc',         'hr_emploc',             'view',            'account', 'rls_policy'),
  ('Super Admin', 'hr_emploc',         'hr_emploc',             'edit',            'account', 'rpc_guard'),
  ('Super Admin', 'plantilla',         'plantilla_slot',        'view',            'account', 'rls_policy'),
  ('Super Admin', 'plantilla',         'plantilla_slot',        'transfer',        'account', 'rpc_guard'),
  ('Super Admin', 'deactivation',      'deactivation_request',  'create',          'account', 'rpc_guard'),
  ('Super Admin', 'deactivation',      'deactivation_request',  'process',         'account', 'rpc_guard'),
  ('Super Admin', 'user_management',   'user_profile',          'view',            'global',  'rls_policy'),
  ('Super Admin', 'user_management',   'user_profile',          'create',          'global',  'rpc_guard'),
  ('Super Admin', 'user_management',   'user_profile',          'edit',            'global',  'rpc_guard'),
  ('Super Admin', 'user_management',   'user_session',          'terminate',       'global',  'rpc_guard'),
  ('Super Admin', 'access_management', 'security_event',        'view',            'global',  'rpc_guard'),
  ('Super Admin', 'access_management', 'temp_permission',       'grant',           'global',  'rpc_guard'),
  ('Super Admin', 'governance',        'audit_log',             'view',            'global',  'derived'),
  ('Super Admin', 'governance',        'role_permission_matrix','view',            'global',  'derived'),

  -- ── Head Admin (level 90) ────────────────────────────────────────────────
  -- Excluded: user_profile.create, user_session.terminate (SA-only RPCs),
  --           security_event.view (requires explicit backend RBAC override)
  ('Head Admin',  'dashboard',         'dashboard_summary',     'view',            'account', 'rls_policy'),
  ('Head Admin',  'cencom',            'cencom_data',           'view',            'account', 'rls_policy'),
  ('Head Admin',  'vacancy',           'vacancy',               'view',            'account', 'rls_policy'),
  ('Head Admin',  'vacancy',           'vacancy',               'create',          'account', 'rpc_guard'),
  ('Head Admin',  'vacancy',           'vacancy',               'edit',            'account', 'rpc_guard'),
  ('Head Admin',  'vacancy',           'vacancy',               'approve_closure', 'account', 'rpc_guard'),
  ('Head Admin',  'vacancy',           'vacancy',               'archive',         'account', 'rpc_guard'),
  ('Head Admin',  'vacancy',           'applicant',             'create',          'account', 'rls_policy'),
  ('Head Admin',  'vacancy',           'applicant',             'confirm_onboard', 'account', 'rpc_guard'),
  ('Head Admin',  'hr_emploc',         'hr_emploc',             'view',            'account', 'rls_policy'),
  ('Head Admin',  'hr_emploc',         'hr_emploc',             'edit',            'account', 'rpc_guard'),
  ('Head Admin',  'plantilla',         'plantilla_slot',        'view',            'account', 'rls_policy'),
  ('Head Admin',  'plantilla',         'plantilla_slot',        'transfer',        'account', 'rpc_guard'),
  ('Head Admin',  'deactivation',      'deactivation_request',  'create',          'account', 'rpc_guard'),
  ('Head Admin',  'deactivation',      'deactivation_request',  'process',         'account', 'rpc_guard'),
  ('Head Admin',  'user_management',   'user_profile',          'view',            'global',  'rls_policy'),
  ('Head Admin',  'user_management',   'user_profile',          'edit',            'global',  'rpc_guard'),
  ('Head Admin',  'access_management', 'temp_permission',       'grant',           'global',  'rpc_guard'),
  ('Head Admin',  'governance',        'audit_log',             'view',            'global',  'derived'),
  ('Head Admin',  'governance',        'role_permission_matrix','view',            'global',  'derived'),

  -- ── Operations Manager (level 70) ────────────────────────────────────────
  ('Operations Manager', 'dashboard',    'dashboard_summary',    'view',            'account', 'rls_policy'),
  ('Operations Manager', 'cencom',       'cencom_data',          'view',            'account', 'rls_policy'),
  ('Operations Manager', 'vacancy',      'vacancy',              'view',            'account', 'rls_policy'),
  ('Operations Manager', 'vacancy',      'vacancy',              'approve_closure', 'account', 'rpc_guard'),
  ('Operations Manager', 'vacancy',      'applicant',            'create',          'account', 'rls_policy'),
  ('Operations Manager', 'vacancy',      'applicant',            'confirm_onboard', 'account', 'rpc_guard'),
  ('Operations Manager', 'hr_emploc',    'hr_emploc',            'view',            'account', 'rls_policy'),
  ('Operations Manager', 'plantilla',    'plantilla_slot',       'view',            'account', 'rls_policy'),
  ('Operations Manager', 'deactivation', 'deactivation_request', 'create',          'account', 'rpc_guard'),

  -- ── OM (alias for Operations Manager) ────────────────────────────────────
  ('OM', 'dashboard',    'dashboard_summary',    'view',            'account', 'rls_policy'),
  ('OM', 'cencom',       'cencom_data',          'view',            'account', 'rls_policy'),
  ('OM', 'vacancy',      'vacancy',              'view',            'account', 'rls_policy'),
  ('OM', 'vacancy',      'vacancy',              'approve_closure', 'account', 'rpc_guard'),
  ('OM', 'vacancy',      'applicant',            'create',          'account', 'rls_policy'),
  ('OM', 'vacancy',      'applicant',            'confirm_onboard', 'account', 'rpc_guard'),
  ('OM', 'hr_emploc',    'hr_emploc',            'view',            'account', 'rls_policy'),
  ('OM', 'plantilla',    'plantilla_slot',       'view',            'account', 'rls_policy'),
  ('OM', 'deactivation', 'deactivation_request', 'create',          'account', 'rpc_guard'),

  -- ── HRCO (level 45) ──────────────────────────────────────────────────────
  ('HRCO', 'dashboard',    'dashboard_summary',    'view',            'account', 'rls_policy'),
  ('HRCO', 'cencom',       'cencom_data',          'view',            'account', 'rls_policy'),
  ('HRCO', 'vacancy',      'vacancy',              'view',            'account', 'rls_policy'),
  ('HRCO', 'vacancy',      'vacancy',              'create',          'account', 'rpc_guard'),
  ('HRCO', 'vacancy',      'vacancy',              'edit',            'account', 'rpc_guard'),
  ('HRCO', 'vacancy',      'applicant',            'create',          'account', 'rls_policy'),
  ('HRCO', 'vacancy',      'applicant',            'confirm_onboard', 'account', 'rpc_guard'),
  ('HRCO', 'hr_emploc',    'hr_emploc',            'view',            'account', 'rls_policy'),
  ('HRCO', 'hr_emploc',    'hr_emploc',            'edit',            'account', 'rpc_guard'),
  ('HRCO', 'plantilla',    'plantilla_slot',       'view',            'account', 'rls_policy'),
  ('HRCO', 'deactivation', 'deactivation_request', 'create',          'account', 'rpc_guard'),

  -- ── ATL (level 42) ───────────────────────────────────────────────────────
  ('ATL', 'dashboard', 'dashboard_summary', 'view',            'account', 'rls_policy'),
  ('ATL', 'cencom',    'cencom_data',       'view',            'account', 'rls_policy'),
  ('ATL', 'vacancy',   'vacancy',           'view',            'account', 'rls_policy'),
  ('ATL', 'vacancy',   'applicant',         'create',          'account', 'rls_policy'),
  ('ATL', 'vacancy',   'applicant',         'confirm_onboard', 'account', 'rpc_guard'),
  ('ATL', 'hr_emploc', 'hr_emploc',         'view',            'account', 'rls_policy'),
  ('ATL', 'plantilla', 'plantilla_slot',    'view',            'account', 'rls_policy'),

  -- ── TL (level 41) ────────────────────────────────────────────────────────
  ('TL', 'dashboard', 'dashboard_summary', 'view',            'account', 'rls_policy'),
  ('TL', 'cencom',    'cencom_data',       'view',            'account', 'rls_policy'),
  ('TL', 'vacancy',   'vacancy',           'view',            'account', 'rls_policy'),
  ('TL', 'vacancy',   'applicant',         'create',          'account', 'rls_policy'),
  ('TL', 'vacancy',   'applicant',         'confirm_onboard', 'account', 'rpc_guard'),
  ('TL', 'hr_emploc', 'hr_emploc',         'view',            'account', 'rls_policy'),
  ('TL', 'plantilla', 'plantilla_slot',    'view',            'account', 'rls_policy'),

  -- ── ATL/TL (level 40, legacy composite) ──────────────────────────────────
  ('ATL/TL', 'dashboard', 'dashboard_summary', 'view',            'account', 'rls_policy'),
  ('ATL/TL', 'cencom',    'cencom_data',       'view',            'account', 'rls_policy'),
  ('ATL/TL', 'vacancy',   'vacancy',           'view',            'account', 'rls_policy'),
  ('ATL/TL', 'vacancy',   'applicant',         'create',          'account', 'rls_policy'),
  ('ATL/TL', 'vacancy',   'applicant',         'confirm_onboard', 'account', 'rpc_guard'),
  ('ATL/TL', 'hr_emploc', 'hr_emploc',         'view',            'account', 'rls_policy'),
  ('ATL/TL', 'plantilla', 'plantilla_slot',    'view',            'account', 'rls_policy'),

  -- ── Encoder (level 30) ───────────────────────────────────────────────────
  ('Encoder', 'dashboard',    'dashboard_summary',     'view',            'account', 'rls_policy'),
  ('Encoder', 'cencom',       'cencom_data',           'view',            'account', 'rls_policy'),
  ('Encoder', 'vacancy',      'vacancy',               'view',            'account', 'rls_policy'),
  ('Encoder', 'vacancy',      'applicant',             'create',          'account', 'rls_policy'),
  ('Encoder', 'vacancy',      'applicant',             'endorse_to_ops',  'account', 'rpc_guard'),
  ('Encoder', 'vacancy',      'applicant',             'confirm_onboard', 'account', 'rpc_guard'),
  ('Encoder', 'hr_emploc',    'hr_emploc',             'view',            'account', 'rls_policy'),
  ('Encoder', 'plantilla',    'plantilla_slot',        'view',            'account', 'rls_policy'),
  ('Encoder', 'plantilla',    'plantilla_slot',        'transfer',        'account', 'rpc_guard'),
  ('Encoder', 'deactivation', 'deactivation_request',  'create',          'account', 'rpc_guard'),
  ('Encoder', 'governance',   'audit_log',             'view',            'global',  'derived'),
  ('Encoder', 'governance',   'role_permission_matrix','view',            'global',  'derived'),

  -- ── HR Personnel (level 25) ──────────────────────────────────────────────
  ('HR Personnel', 'dashboard', 'dashboard_summary', 'view',   'account', 'rls_policy'),
  ('HR Personnel', 'vacancy',   'vacancy',           'view',   'account', 'rls_policy'),
  ('HR Personnel', 'vacancy',   'applicant',         'create', 'account', 'rls_policy'),
  ('HR Personnel', 'hr_emploc', 'hr_emploc',         'view',   'account', 'rls_policy'),
  ('HR Personnel', 'hr_emploc', 'hr_emploc',         'edit',   'account', 'rpc_guard'),

  -- ── Recruitment Team (level 20) ──────────────────────────────────────────
  ('Recruitment Team', 'dashboard', 'dashboard_summary', 'view',           'account', 'rls_policy'),
  ('Recruitment Team', 'vacancy',   'vacancy',           'view',           'account', 'rls_policy'),
  ('Recruitment Team', 'vacancy',   'applicant',         'create',         'account', 'rls_policy'),
  ('Recruitment Team', 'vacancy',   'applicant',         'endorse_to_ops', 'account', 'rpc_guard'),

  -- ── Recruitment (alias, level 20) ────────────────────────────────────────
  ('Recruitment', 'dashboard', 'dashboard_summary', 'view',           'account', 'rls_policy'),
  ('Recruitment', 'vacancy',   'vacancy',           'view',           'account', 'rls_policy'),
  ('Recruitment', 'vacancy',   'applicant',         'create',         'account', 'rls_policy'),
  ('Recruitment', 'vacancy',   'applicant',         'endorse_to_ops', 'account', 'rpc_guard'),

  -- ── Back Office (level 15) ───────────────────────────────────────────────
  ('Back Office', 'dashboard',    'dashboard_summary',    'view',    'account', 'rls_policy'),
  ('Back Office', 'vacancy',      'vacancy',              'view',    'account', 'rls_policy'),
  ('Back Office', 'deactivation', 'deactivation_request', 'process', 'account', 'rpc_guard'),

  -- ── Backoffice (alias, level 15) ─────────────────────────────────────────
  ('Backoffice', 'dashboard',    'dashboard_summary',    'view',    'account', 'rls_policy'),
  ('Backoffice', 'vacancy',      'vacancy',              'view',    'account', 'rls_policy'),
  ('Backoffice', 'deactivation', 'deactivation_request', 'process', 'account', 'rpc_guard'),

  -- ── Backoffice Personnel (alias, level 15) ───────────────────────────────
  ('Backoffice Personnel', 'dashboard',    'dashboard_summary',    'view',    'account', 'rls_policy'),
  ('Backoffice Personnel', 'vacancy',      'vacancy',              'view',    'account', 'rls_policy'),
  ('Backoffice Personnel', 'deactivation', 'deactivation_request', 'process', 'account', 'rpc_guard'),

  -- ── Viewer (level 10) ────────────────────────────────────────────────────
  ('Viewer', 'dashboard', 'dashboard_summary', 'view', 'account', 'rls_policy'),
  ('Viewer', 'vacancy',   'vacancy',           'view', 'account', 'rls_policy'),
  ('Viewer', 'plantilla', 'plantilla_slot',    'view', 'account', 'rls_policy')

) AS seed(role_name, module_key, resource_key, action_key, scope_mode, src)
JOIN public.roles r ON r.role_name = seed.role_name
JOIN public.role_permission_definitions d
  ON  d.module_key   = seed.module_key
  AND d.resource_key = seed.resource_key
  AND d.action_key   = seed.action_key
  AND d.scope_mode   = seed.scope_mode
ON CONFLICT (role_id, permission_definition_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: SEED MATRIX — DENIED (FALSE) ROWS FOR ALL KNOWN ROLES
-- ═══════════════════════════════════════════════════════════════════════════
-- Full cross-join of every known role × every definition.
-- ON CONFLICT DO NOTHING skips the allowed rows already inserted above.
-- source_type is derived from enforcement_type so denied rows accurately
-- show WHERE the denial is enforced (rls_policy, rpc_guard, or ui_gate).

INSERT INTO public.role_permission_matrix
  (role_id, permission_definition_id, is_allowed, source_type)
SELECT
  r.id,
  d.id,
  false,
  CASE d.enforcement_type
    WHEN 'db_rls'   THEN 'rls_policy'
    WHEN 'rpc'      THEN 'rpc_guard'
    WHEN 'ui_only'  THEN 'ui_gate'
    ELSE 'rls_policy'
  END
FROM public.roles r
CROSS JOIN public.role_permission_definitions d
WHERE r.role_name IN (
  'Super Admin', 'Head Admin',
  'Operations Manager', 'OM',
  'HRCO',
  'ATL', 'TL', 'ATL/TL',
  'Encoder',
  'HR Personnel',
  'Recruitment Team', 'Recruitment',
  'Back Office', 'Backoffice', 'Backoffice Personnel',
  'Viewer'
)
ON CONFLICT (role_id, permission_definition_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATION NOTES (run against staging/dev before prod deploy)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Verify all three tables exist:
--    SELECT table_name FROM information_schema.tables
--    WHERE table_schema = 'public'
--      AND table_name IN (
--        'role_permission_definitions',
--        'role_permission_matrix',
--        'role_permission_audit_logs'
--      );
--    Expected: 3 rows

-- 2. Verify definition seed count:
--    SELECT count(*) FROM public.role_permission_definitions;
--    Expected: 24 rows

-- 3. Verify per-role allowed counts (spot check):
--    SELECT r.role_name, count(*) AS allowed
--    FROM public.role_permission_matrix m
--    JOIN public.roles r ON r.id = m.role_id
--    WHERE m.is_allowed = true
--    GROUP BY r.role_name
--    ORDER BY max(r.role_level) DESC;
--
--    Expected (approx):
--      Super Admin           → 24
--      Head Admin            → 20  (no user_create, no session_terminate, no security_view)
--      Operations Manager/OM →  9
--      HRCO                  → 11
--      ATL/TL/ATL/TL         →  7
--      Encoder               → 12
--      HR Personnel          →  5
--      Recruitment Team/Recruitment → 4
--      Back Office/Backoffice/Backoffice Personnel → 3
--      Viewer                →  3

-- 4. Verify Viewer allowed set is exactly {dashboard_view, vacancy_view, plantilla_view}:
--    SELECT d.module_key, d.resource_key, d.action_key
--    FROM public.role_permission_matrix m
--    JOIN public.roles r ON r.id = m.role_id
--    JOIN public.role_permission_definitions d ON d.id = m.permission_definition_id
--    WHERE r.role_name = 'Viewer' AND m.is_allowed = true;

-- 5. Verify RPC access for Encoder (role_level = 30):
--    -- (authenticated as Encoder-level user)
--    SELECT count(*) FROM public.fn_get_permission_matrix();
--    Expected: non-zero — Encoder can read the full grid

-- 6. Verify RLS blocks Viewer (role_level = 10) on direct table reads:
--    -- (authenticated as Viewer-level user)
--    SELECT count(*) FROM public.role_permission_definitions;
--    Expected: 0 rows (RLS denies level < 30)

-- 7. Verify fn_get_permission_matrix rejects Viewer at the RPC level:
--    -- (authenticated as Viewer-level user)
--    SELECT * FROM public.fn_get_permission_matrix();
--    Expected: ERROR 42501 — Insufficient permissions

-- 8. Verify audit log blocks direct client writes:
--    INSERT INTO public.role_permission_audit_logs (old_value, new_value) VALUES (true, false);
--    Expected: ERROR — no permissive INSERT policy

-- 9. Verify no direct mutation is possible on definitions or matrix:
--    UPDATE public.role_permission_matrix SET is_allowed = true WHERE ...;
--    Expected: ERROR — no permissive UPDATE policy
