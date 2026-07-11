-- Migration: 20260529000000_permission_drift_detection_foundation.sql
-- Ticket: OHM2026_1049 — Implement Permission Drift Detection Backend Foundation
--
-- Creates the read-only permission drift observability layer:
--   permission_drift_scan_runs   — log of when drift scans were performed and by whom
--   permission_drift_findings    — one row per identified authorization mismatch
--   permission_drift_evidence    — structured evidence items backing each finding
--
-- Adds two read-only RPCs:
--   fn_get_permission_drift_findings(p_status, p_severity, p_module_key) — filtered findings + evidence JSONB
--   fn_get_permission_drift_summary()                                     — aggregate severity/status counts
--
-- Seeds initial audit: one scan run (type='seeded') + F-01 through F-07 findings + evidence.
--
-- Governance observability only. This phase does NOT:
--   - modify any existing RLS policy or RPC
--   - add editable permission controls
--   - add auto-remediation or automated scanners
--   - add any Flutter UI
--
-- Reversible: drop the three tables and two RPCs to remove without affecting live enforcement.
-- ─────────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: TABLE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- Scan run log: records when a drift scan was performed and by whom.
-- Phase 1 uses scan_type = 'seeded' (manually curated findings).
-- Future phases: 'manual' (admin-triggered) or 'automated' (Edge Function / DB function).
CREATE TABLE public.permission_drift_scan_runs (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_name     text        NOT NULL,
  scan_type     text        NOT NULL
                            CHECK (scan_type IN ('seeded', 'manual', 'automated')),
  scan_status   text        NOT NULL DEFAULT 'completed'
                            CHECK (scan_status IN ('running', 'completed', 'failed')),
  findings_count integer    NOT NULL DEFAULT 0,
  triggered_by  uuid        REFERENCES public.users_profile(id),
  started_at    timestamptz NOT NULL DEFAULT now(),
  completed_at  timestamptz,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Core drift findings: one row per identified authorization mismatch.
-- finding_code is a stable human reference (e.g. 'F-01') — never reuse a code.
-- drift_category classifies the type of mismatch (see architecture §3).
-- accepted_risk_reason: populated when status = 'accepted_risk' to document justification.
-- is_seeded: true for findings inserted by migration; distinguishes from future scan output.
CREATE TABLE public.permission_drift_findings (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_run_id           uuid        NOT NULL REFERENCES public.permission_drift_scan_runs(id),
  finding_code          text        NOT NULL UNIQUE,
  drift_category        text        NOT NULL
                                    CHECK (drift_category IN (
                                      'enforcement_missing',
                                      'enforcement_exceeded',
                                      'ui_security_assumption',
                                      'rpc_no_role_guard',
                                      'rls_missing_or_broad',
                                      'ui_backend_mismatch',
                                      'ui_shows_denied_action',
                                      'role_level_mismatch'
                                    )),
  severity              text        NOT NULL
                                    CHECK (severity IN ('critical', 'high', 'medium', 'low', 'info')),
  status                text        NOT NULL DEFAULT 'open'
                                    CHECK (status IN ('open', 'accepted_risk', 'resolved', 'false_positive')),
  module_key            text        NOT NULL,
  resource_key          text        NOT NULL,
  action_key            text        NOT NULL,
  role_name             text,       -- NULL = finding is role-agnostic (affects all roles or is structural)
  expected_enforcement  text        NOT NULL,
  observed_enforcement  text        NOT NULL,
  finding_summary       text        NOT NULL,
  recommendation        text        NOT NULL,
  accepted_risk_reason  text,       -- required when status = 'accepted_risk'
  resolved_at           timestamptz,
  resolved_by           uuid        REFERENCES public.users_profile(id),
  is_seeded             boolean     NOT NULL DEFAULT false,
  created_at            timestamptz NOT NULL DEFAULT now()
);

-- Supporting evidence attached to each finding.
-- Multiple evidence items can back a single finding.
-- evidence_type classifies the source (matrix entry, RLS policy, RPC function, Flutter code, doc, audit gap).
-- evidence_key: short stable label (function name, policy name, file path segment).
-- evidence_value: the observed value or excerpt being cited.
-- file_path: code file reference (nullable — not all evidence has a file).
-- line_note: brief note on the specific location or behavior at that path.
CREATE TABLE public.permission_drift_evidence (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  finding_id     uuid        NOT NULL REFERENCES public.permission_drift_findings(id) ON DELETE CASCADE,
  evidence_type  text        NOT NULL
                             CHECK (evidence_type IN (
                               'matrix', 'rls_policy', 'rpc_function',
                               'flutter_code', 'doc_reference', 'audit_gap'
                             )),
  evidence_key   text        NOT NULL,
  evidence_value text        NOT NULL,
  file_path      text,
  line_note      text,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_pdf_severity  ON public.permission_drift_findings (severity);
CREATE INDEX idx_pdf_status    ON public.permission_drift_findings (status);
CREATE INDEX idx_pdf_module    ON public.permission_drift_findings (module_key);
CREATE INDEX idx_pdf_scan_run  ON public.permission_drift_findings (scan_run_id);
CREATE INDEX idx_pde_finding   ON public.permission_drift_evidence (finding_id);


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════════
-- Read: Super Admin and Head Admin only (role_level >= 90).
-- Write: none from client — all data inserted by migrations or future service-role scans.
-- Rationale: drift findings expose the gap between documented and actual security
-- enforcement — this information must be restricted to governance-level users.

ALTER TABLE public.permission_drift_scan_runs  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_drift_findings   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_drift_evidence   ENABLE ROW LEVEL SECURITY;

CREATE POLICY pdsr_read_governance
  ON public.permission_drift_scan_runs
  FOR SELECT
  USING (public.get_my_role_level() >= 90);

CREATE POLICY pdf_read_governance
  ON public.permission_drift_findings
  FOR SELECT
  USING (public.get_my_role_level() >= 90);

CREATE POLICY pde_read_governance
  ON public.permission_drift_evidence
  FOR SELECT
  USING (public.get_my_role_level() >= 90);

-- No INSERT / UPDATE / DELETE client policies on any of the three tables.
-- Direct client mutations are blocked by the absence of permissive write policies.


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: RPC — fn_get_permission_drift_findings
-- ═══════════════════════════════════════════════════════════════════════════
-- Auth:    role_level >= 90 (Super Admin + Head Admin only)
-- Filters: p_status, p_severity, p_module_key (all nullable — pass NULL for unfiltered)
-- Output:  findings sorted by severity rank then created_at DESC, with evidence as JSONB array.
-- No writes. No dynamic SQL. SECURITY DEFINER with fixed search_path.

CREATE OR REPLACE FUNCTION public.fn_get_permission_drift_findings(
  p_status      text DEFAULT NULL,
  p_severity    text DEFAULT NULL,
  p_module_key  text DEFAULT NULL
)
RETURNS TABLE (
  finding_id            uuid,
  finding_code          text,
  drift_category        text,
  severity              text,
  status                text,
  module_key            text,
  resource_key          text,
  action_key            text,
  role_name             text,
  expected_enforcement  text,
  observed_enforcement  text,
  finding_summary       text,
  recommendation        text,
  evidence              jsonb,
  accepted_risk_reason  text,
  created_at            timestamptz,
  resolved_at           timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Insufficient permissions to view permission drift findings'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    f.id                   AS finding_id,
    f.finding_code,
    f.drift_category,
    f.severity,
    f.status,
    f.module_key,
    f.resource_key,
    f.action_key,
    f.role_name,
    f.expected_enforcement,
    f.observed_enforcement,
    f.finding_summary,
    f.recommendation,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'evidence_type',  e.evidence_type,
            'evidence_key',   e.evidence_key,
            'evidence_value', e.evidence_value,
            'file_path',      e.file_path,
            'line_note',      e.line_note
          ) ORDER BY e.created_at
        )
        FROM public.permission_drift_evidence e
        WHERE e.finding_id = f.id
      ),
      '[]'::jsonb
    )                      AS evidence,
    f.accepted_risk_reason,
    f.created_at,
    f.resolved_at
  FROM public.permission_drift_findings f
  WHERE (p_status     IS NULL OR f.status     = p_status)
    AND (p_severity   IS NULL OR f.severity   = p_severity)
    AND (p_module_key IS NULL OR f.module_key = p_module_key)
  ORDER BY
    CASE f.severity
      WHEN 'critical' THEN 1
      WHEN 'high'     THEN 2
      WHEN 'medium'   THEN 3
      WHEN 'low'      THEN 4
      WHEN 'info'     THEN 5
      ELSE 6
    END,
    f.created_at DESC;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: RPC — fn_get_permission_drift_summary
-- ═══════════════════════════════════════════════════════════════════════════
-- Auth:   role_level >= 90 (Super Admin + Head Admin only)
-- Output: aggregate counts by status and severity for summary chips.
-- No writes. No dynamic SQL. SECURITY DEFINER with fixed search_path.

CREATE OR REPLACE FUNCTION public.fn_get_permission_drift_summary()
RETURNS TABLE (
  total_findings      integer,
  open_count          integer,
  accepted_risk_count integer,
  resolved_count      integer,
  critical_count      integer,
  high_count          integer,
  medium_count        integer,
  low_count           integer,
  info_count          integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Insufficient permissions to view permission drift summary'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    COUNT(*)::integer                                                 AS total_findings,
    COUNT(*) FILTER (WHERE f.status = 'open')::integer               AS open_count,
    COUNT(*) FILTER (WHERE f.status = 'accepted_risk')::integer      AS accepted_risk_count,
    COUNT(*) FILTER (WHERE f.status = 'resolved')::integer           AS resolved_count,
    COUNT(*) FILTER (WHERE f.severity = 'critical')::integer         AS critical_count,
    COUNT(*) FILTER (WHERE f.severity = 'high')::integer             AS high_count,
    COUNT(*) FILTER (WHERE f.severity = 'medium')::integer           AS medium_count,
    COUNT(*) FILTER (WHERE f.severity = 'low')::integer              AS low_count,
    COUNT(*) FILTER (WHERE f.severity = 'info')::integer             AS info_count
  FROM public.permission_drift_findings f;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: SEED DATA — Initial RBAC Governance Audit
-- ═══════════════════════════════════════════════════════════════════════════
-- Derived from the architectural gap audit accumulated during OHM2026_1043–1047.
-- Scan type: 'seeded' — triggered_by = NULL (system seed, no human actor).
-- Findings F-01 through F-07 correspond to gaps G3–G7 and two additional findings.
-- All findings have is_seeded = true to distinguish from future automated scan output.

DO $$
DECLARE
  v_scan_id  uuid;
  v_f01_id   uuid;
  v_f02_id   uuid;
  v_f03_id   uuid;
  v_f04_id   uuid;
  v_f05_id   uuid;
  v_f06_id   uuid;
  v_f07_id   uuid;
BEGIN

  -- ── Scan Run ──────────────────────────────────────────────────────────────
  INSERT INTO public.permission_drift_scan_runs (
    scan_name,
    scan_type,
    scan_status,
    findings_count,
    triggered_by,
    started_at,
    completed_at,
    notes
  ) VALUES (
    'Initial RBAC Governance Audit',
    'seeded',
    'completed',
    7,
    NULL,
    now(),
    now(),
    'Curated findings derived from architectural gap audit OHM2026_1043–1047. '
    'Covers gaps G3–G7 from rbac_permission_matrix.md plus HA security dashboard '
    'override path (F-06) and governance screen gate mismatch (F-07).'
  )
  RETURNING id INTO v_scan_id;


  -- ── F-01: Role Identity String-Matched in Backend Helpers ─────────────────
  -- Severity: High | Status: Open | Category: role_level_mismatch
  -- Gap: G3 from rbac_permission_matrix.md §5
  INSERT INTO public.permission_drift_findings (
    scan_run_id,
    finding_code,
    drift_category,
    severity,
    status,
    module_key,
    resource_key,
    action_key,
    role_name,
    expected_enforcement,
    observed_enforcement,
    finding_summary,
    recommendation,
    accepted_risk_reason,
    is_seeded
  ) VALUES (
    v_scan_id,
    'F-01',
    'role_level_mismatch',
    'high',
    'open',
    'user_management',
    'user_profile',
    'edit',
    NULL,
    'Role authorization should be level-based for robustness. '
    'A rename of any canonical roles row should not affect authorization outcomes.',
    'i_have_full_access() and AppRole._normalize() branch on role_name string literals. '
    'A rename of any roles row silently drops that role to level 0, breaking all '
    'authorization checks that depend on string identity rather than role_level.',
    'Role identity is string-matched in i_have_full_access() and AppRole._normalize(). '
    'Any rename of a canonical roles row silently reduces that role to authorization level 0, '
    'breaking all downstream permission checks that rely on string identity.',
    'Treat roles rows as system-locked. Add a DB-level trigger or constraint that blocks '
    'role_name updates on the canonical role set. Document explicitly that roles.role_name '
    'is an immutable identifier, not an editable label.',
    NULL,
    true
  )
  RETURNING id INTO v_f01_id;

  INSERT INTO public.permission_drift_evidence (finding_id, evidence_type, evidence_key, evidence_value, file_path, line_note) VALUES
    (v_f01_id, 'rpc_function', 'i_have_full_access()',
     'role_name IN (''Super Admin'',''Head Admin'') — string-literal match, not level-based',
     NULL,
     'Rename of either role name silently drops full-access recognition'),
    (v_f01_id, 'flutter_code', 'AppRole._normalize()',
     'AppRole._normalize() branches on hardcoded role name string literals to resolve enum variants',
     'lib/core/constants/role_constants.dart',
     'String match branches — rename breaks normalization silently'),
    (v_f01_id, 'audit_gap', 'rename_risk_undocumented',
     'Mapping survives G1/G2 fix but rename risk remains undocumented and unguarded at DB level',
     NULL,
     'No DB trigger or constraint currently prevents roles.role_name updates');


  -- ── F-02: Client/Server hasFullAccess Rule Divergence ─────────────────────
  -- Severity: Medium | Status: Open | Category: ui_backend_mismatch
  -- Gap: G4 from rbac_permission_matrix.md §5
  INSERT INTO public.permission_drift_findings (
    scan_run_id,
    finding_code,
    drift_category,
    severity,
    status,
    module_key,
    resource_key,
    action_key,
    role_name,
    expected_enforcement,
    observed_enforcement,
    finding_summary,
    recommendation,
    accepted_risk_reason,
    is_seeded
  ) VALUES (
    v_scan_id,
    'F-02',
    'ui_backend_mismatch',
    'medium',
    'open',
    'user_management',
    'user_profile',
    'edit',
    'Head Admin',
    'Flutter and backend agree on who hasFullAccess. The same mechanism and threshold '
    'should be used on both sides so a future role addition cannot create a silent divergence.',
    'Flutter: hasFullAccess = roleLevel >= 90 (numeric level threshold). '
    'Backend i_have_full_access(): role_name IN (''Super Admin'',''Head Admin'') (string match). '
    'Mechanisms differ. Today they produce the same result, but could diverge if a new role '
    'at level >= 90 is added without updating the string list in the backend function.',
    'hasFullAccess is computed differently in Flutter (roleLevel >= 90 numeric threshold) vs '
    'backend i_have_full_access() (role_name string match). Both agree today but could diverge '
    'silently if a new role at level >= 90 is ever introduced.',
    'Align both sides on the same mechanism. Preferred: backend exposes a pre-computed '
    'has_full_access boolean in the user context RPC; Flutter reads the result rather than '
    'recomputing it. Alternative: document and enforce the invariant that no role other than '
    'Super Admin or Head Admin will ever reach level >= 90.',
    NULL,
    true
  )
  RETURNING id INTO v_f02_id;

  INSERT INTO public.permission_drift_evidence (finding_id, evidence_type, evidence_key, evidence_value, file_path, line_note) VALUES
    (v_f02_id, 'flutter_code', 'auth_service.dart:35',
     'hasFullAccess getter: roleLevel >= 90 — numeric threshold against roles.role_level',
     'lib/core/auth/auth_service.dart',
     'Line ~35: hasFullAccess getter uses numeric threshold'),
    (v_f02_id, 'rpc_function', 'i_have_full_access()',
     'role_name IN (''Super Admin'',''Head Admin'') — string match, not level-based',
     NULL,
     'Mechanism differs from Flutter getter; divergence risk on new role addition'),
    (v_f02_id, 'doc_reference', 'rbac_permission_matrix.md §5 G4',
     'G4 gap cross-reference: Client/server rule drift — Flutter numeric vs backend string match',
     NULL,
     'Formally catalogued as gap G4 in architecture gap audit');


  -- ── F-03: More Screen Module Visibility is UI-Only (Not a Security Gate) ──
  -- Severity: Medium | Status: Open | Category: ui_security_assumption
  -- Gap: G5 from rbac_permission_matrix.md §5
  INSERT INTO public.permission_drift_findings (
    scan_run_id,
    finding_code,
    drift_category,
    severity,
    status,
    module_key,
    resource_key,
    action_key,
    role_name,
    expected_enforcement,
    observed_enforcement,
    finding_summary,
    recommendation,
    accepted_risk_reason,
    is_seeded
  ) VALUES (
    v_scan_id,
    'F-03',
    'ui_security_assumption',
    'medium',
    'open',
    'more',
    'module_visibility',
    'view',
    NULL,
    'ui_only enforcement — More screen role filter is convenience visibility, not a security boundary. '
    'The actual security gates are the individual screens and their backing RPC/RLS policies.',
    'MoreMenuItemConfig.allowedRoles in more_screen.dart filters menu entries for Governance, '
    'Access Management, and Data Control. No matching RLS policy or RPC guard exists for these '
    'navigation routes. A role not in allowedRoles could still navigate to those screens by '
    'constructing the route directly or bypassing the More menu.',
    'More screen allowedRoles filter is UI-only. No backend RLS or RPC guard prevents direct '
    'route navigation to Governance, Access Management, or Data Control screens by unauthorized '
    'roles. The filter prevents accidental navigation but is not a security boundary.',
    'Explicitly document in screen-level comments that allowedRoles is UX-only. For screens '
    'that touch sensitive operations (Security Dashboard, User Management, Governance), ensure '
    'the screen itself and its RPC/RLS are the real security gate. Never rely on allowedRoles '
    'as the only access control for sensitive functionality.',
    NULL,
    true
  )
  RETURNING id INTO v_f03_id;

  INSERT INTO public.permission_drift_evidence (finding_id, evidence_type, evidence_key, evidence_value, file_path, line_note) VALUES
    (v_f03_id, 'flutter_code', 'more_screen.dart _canSeeItem',
     '_canSeeItem checks MoreMenuItemConfig.allowedRoles — no backing RLS or RPC route guard exists',
     'lib/features/more/more_screen.dart',
     '_canSeeItem / allowedRoles: UX filter only, not a security boundary'),
    (v_f03_id, 'matrix', 'source_type=ui_gate',
     'Multiple governance and access entries in role_permission_matrix carry source_type = ''ui_gate'' — explicit documentation that these are UI-visibility only',
     NULL,
     'ui_gate source_type confirms no backend enforcement backing'),
    (v_f03_id, 'doc_reference', 'rbac_permission_matrix.md §5 G5',
     'G5 gap cross-reference: Module visibility is UI-only — hiding does not equal blocking',
     NULL,
     'Formally catalogued as gap G5 in architecture gap audit');


  -- ── F-04: Backoffice Role Under-Modeled in Flutter ────────────────────────
  -- Severity: Low | Status: Open | Category: ui_backend_mismatch
  -- Gap: G6 from rbac_permission_matrix.md §5
  INSERT INTO public.permission_drift_findings (
    scan_run_id,
    finding_code,
    drift_category,
    severity,
    status,
    module_key,
    resource_key,
    action_key,
    role_name,
    expected_enforcement,
    observed_enforcement,
    finding_summary,
    recommendation,
    accepted_risk_reason,
    is_seeded
  ) VALUES (
    v_scan_id,
    'F-04',
    'ui_backend_mismatch',
    'low',
    'open',
    'deactivation',
    'deactivation_request',
    'process',
    'Backoffice Personnel',
    'backofficePersonnel has a visible client-side capability definition in RolePermissions. '
    'The UI should be able to show or hide relevant actions using a standard can* getter '
    'without resorting to direct role name checks.',
    'backofficePersonnel is absent from the RolePermissions helpers in role_constants.dart and '
    'from several can* getters. The role relies entirely on the backend RPC guard for '
    'deactivation-process access. No Flutter visibility helper exists — the UI cannot '
    'show/hide relevant actions for backoffice users without checking the role name directly, '
    'bypassing the standard capability model.',
    'Backoffice Personnel role is absent from Flutter RolePermissions helpers and can* getters. '
    'The UI cannot show or hide deactivation-process actions using the standard capability model '
    'and must fall back to direct role name checks. Backend enforcement is correct; '
    'the gap is client-side modeling only.',
    'Add backofficePersonnel to RolePermissions with at minimum a canProcessDeactivation getter. '
    'Backoffice is a legitimate operational role and should be first-class in the client model '
    'to avoid role-name-string checks scattered across the UI.',
    NULL,
    true
  )
  RETURNING id INTO v_f04_id;

  INSERT INTO public.permission_drift_evidence (finding_id, evidence_type, evidence_key, evidence_value, file_path, line_note) VALUES
    (v_f04_id, 'flutter_code', 'role_constants.dart RolePermissions',
     'RolePermissions class is missing backofficePersonnel entries and canProcessDeactivation getter',
     'lib/core/constants/role_constants.dart',
     'RolePermissions class — backofficePersonnel not modeled as a first-class capability set'),
    (v_f04_id, 'matrix', 'Backoffice Personnel matrix row',
     'Matrix seeds Backoffice Personnel with: dashboard view + vacancy view + deactivation process only',
     NULL,
     'Backend correctly scopes the role; Flutter client model is incomplete'),
    (v_f04_id, 'doc_reference', 'rbac_permission_matrix.md §5 G6',
     'G6 gap cross-reference: Backoffice role under-modeled client-side',
     NULL,
     'Formally catalogued as gap G6 in architecture gap audit');


  -- ── F-05: Viewer Plantilla/CENCOM Gating Asymmetry ───────────────────────
  -- Severity: Low | Status: Open | Category: ui_backend_mismatch
  -- Gap: G7 from rbac_permission_matrix.md §5
  INSERT INTO public.permission_drift_findings (
    scan_run_id,
    finding_code,
    drift_category,
    severity,
    status,
    module_key,
    resource_key,
    action_key,
    role_name,
    expected_enforcement,
    observed_enforcement,
    finding_summary,
    recommendation,
    accepted_risk_reason,
    is_seeded
  ) VALUES (
    v_scan_id,
    'F-05',
    'ui_backend_mismatch',
    'low',
    'open',
    'plantilla',
    'plantilla_slot',
    'view',
    'Viewer',
    'Viewer plantilla, dashboard, and CENCOM visibility should be consistent across all '
    'client-side capability helpers. canViewPlantilla and canSeePlantilla should produce '
    'the same result for the same role.',
    'RolePermissions.canViewPlantilla allows Viewer, but LoggedInUser.canSeePlantilla requires '
    'hasFullAccess OR canViewPlantilla — these produce different results when evaluated '
    'independently for a Viewer user. Additionally, Viewer dashboard/CENCOM gating differs '
    'across modules: CENCOM is denied to Viewer in the matrix but client-side visibility logic '
    'may not consistently reflect this across all relevant screens.',
    'Viewer plantilla visibility is inconsistent between can* helpers: canViewPlantilla allows '
    'Viewer but canSeePlantilla introduces an extra hasFullAccess gate. CENCOM is denied to '
    'Viewer in the matrix but client-side gating may not be consistently enforced across modules.',
    'Audit all Viewer-gated can* helpers for consistency. Ensure canSeePlantilla delegates '
    'directly to canViewPlantilla without introducing an additional full-access gate. '
    'Cross-check CENCOM module RLS policies against the Viewer role_level (10) to confirm '
    'backend correctly denies CENCOM access for Viewer.',
    NULL,
    true
  )
  RETURNING id INTO v_f05_id;

  INSERT INTO public.permission_drift_evidence (finding_id, evidence_type, evidence_key, evidence_value, file_path, line_note) VALUES
    (v_f05_id, 'flutter_code', 'role_constants.dart canViewPlantilla vs canSeePlantilla',
     'canViewPlantilla: allows Viewer. canSeePlantilla: requires hasFullAccess OR canViewPlantilla — extra gate for same intent',
     'lib/core/constants/role_constants.dart',
     'Two helpers for the same capability produce different results for Viewer'),
    (v_f05_id, 'matrix', 'Viewer plantilla and cencom entries',
     'Matrix: plantilla_slot.view = allowed for Viewer; cencom_data.view = denied for Viewer',
     NULL,
     'Matrix is clear; client-side helpers may not consistently reflect CENCOM denial'),
    (v_f05_id, 'doc_reference', 'rbac_permission_matrix.md §5 G7',
     'G7 gap cross-reference: Viewer plantilla asymmetry — verify per-module RLS',
     NULL,
     'Formally catalogued as gap G7 in architecture gap audit');


  -- ── F-06: Head Admin Security Dashboard Access Is Override-Path Only ──────
  -- Severity: Info | Status: Accepted Risk | Category: enforcement_exceeded
  -- Note: intentional, backend-enforced, auditable bypass — not a security defect.
  INSERT INTO public.permission_drift_findings (
    scan_run_id,
    finding_code,
    drift_category,
    severity,
    status,
    module_key,
    resource_key,
    action_key,
    role_name,
    expected_enforcement,
    observed_enforcement,
    finding_summary,
    recommendation,
    accepted_risk_reason,
    is_seeded
  ) VALUES (
    v_scan_id,
    'F-06',
    'enforcement_exceeded',
    'info',
    'accepted_risk',
    'access_management',
    'security_event',
    'view',
    'Head Admin',
    'Matrix: is_allowed = false for Head Admin by default. '
    'Head Admin requires an explicit backend RBAC override to access the security dashboard.',
    'The override mechanism (SecurityDashboardService.canViewSecurityDashboard) is correctly '
    'backend-driven and not hardcoded client-side. The existence of this bypass path means '
    'Head Admin can access the security dashboard under certain conditions, making the '
    'effective permission exceed the matrix default of false.',
    'Head Admin can access the security dashboard via a documented backend override path. '
    'The matrix shows FALSE by default, which is correct. The override is intentional, '
    'backend-enforced, and auditable. Recorded as accepted_risk to acknowledge the bypass '
    'path exists and is controlled.',
    'No action required. Override is documented, backend-enforced, and intentional. '
    'Ensure the override RPC that grants Head Admin access writes an entry to audit_logs '
    'so the grant is traceable.',
    'Override mechanism is correctly backend-driven via SecurityDashboardService.canViewSecurityDashboard. '
    'Not hardcoded client-side. This is an intentional and auditable bypass path, not a security defect. '
    'Matrix default of FALSE is preserved; override requires explicit backend grant.',
    true
  )
  RETURNING id INTO v_f06_id;

  INSERT INTO public.permission_drift_evidence (finding_id, evidence_type, evidence_key, evidence_value, file_path, line_note) VALUES
    (v_f06_id, 'flutter_code', 'security_dashboard_service.dart canViewSecurityDashboard',
     'canViewSecurityDashboard delegates to backend RPC — not hardcoded; correctly backend-driven',
     'lib/data/services/security_dashboard_service.dart',
     'Backend-driven check — no client-side hardcoded elevation'),
    (v_f06_id, 'matrix', 'Head Admin x access_management.security_event.view',
     'is_allowed = false — default correct state. Override path is intentional and separate.',
     NULL,
     'Matrix default is FALSE; override path is a controlled exception'),
    (v_f06_id, 'doc_reference', 'rbac.md and rbac_permission_matrix.md §4 footnote',
     'HA override documented in RBAC architecture doc and matrix footnote on security dashboard access',
     NULL,
     'Override path is formally documented — not an undiscovered bypass');


  -- ── F-07: Governance Screen Flutter Gate More Restrictive Than Backend RPC ─
  -- Severity: Info | Status: Open | Category: ui_backend_mismatch
  -- Note: safe asymmetry (UI more restrictive than backend) but still a documented mismatch.
  INSERT INTO public.permission_drift_findings (
    scan_run_id,
    finding_code,
    drift_category,
    severity,
    status,
    module_key,
    resource_key,
    action_key,
    role_name,
    expected_enforcement,
    observed_enforcement,
    finding_summary,
    recommendation,
    accepted_risk_reason,
    is_seeded
  ) VALUES (
    v_scan_id,
    'F-07',
    'ui_backend_mismatch',
    'info',
    'open',
    'governance',
    'role_permission_matrix',
    'view',
    'Encoder',
    'Backend RPC fn_get_permission_matrix permits role_level >= 30 (Encoder and above). '
    'The Flutter screen gate should either match the RPC threshold or the RPC should be '
    'tightened to match the Flutter gate — based on product intent.',
    'Flutter RolePermissionsScreen._canAccess gate restricts to isSuperAdmin || isHeadAdmin only. '
    'Encoder (level 30) can call fn_get_permission_matrix directly from a DB client or API '
    'client but cannot access the UI screen. A safe asymmetry (UI more restrictive than backend) '
    'but still a documented mismatch between screen gate and RPC authorization threshold.',
    'Flutter governance screen gate (SA/HA only) is more restrictive than the backend RPC guard '
    '(role_level >= 30 / Encoder+). Encoder can call fn_get_permission_matrix directly but '
    'the UI screen blocks them. A safe asymmetry with no immediate security impact.',
    'Either: (a) extend the Flutter gate to role_level >= 30 to match the RPC, giving Data Team '
    'read visibility of the permission matrix (aligns with matrix documentation intent); '
    'or (b) tighten the RPC to role_level >= 90 to match the Flutter gate (restricts matrix '
    'visibility to governance-only). Decision should be driven by product intent.',
    NULL,
    true
  )
  RETURNING id INTO v_f07_id;

  INSERT INTO public.permission_drift_evidence (finding_id, evidence_type, evidence_key, evidence_value, file_path, line_note) VALUES
    (v_f07_id, 'flutter_code', 'role_permissions_screen.dart:43 _canAccess',
     '_canAccess = isSuperAdmin || isHeadAdmin — more restrictive than the RPC auth threshold',
     'lib/features/governance/role_permissions_screen.dart',
     'Line ~43: _canAccess gate restricts screen to SA and HA only'),
    (v_f07_id, 'rpc_function', 'fn_get_permission_matrix',
     'get_my_role_level() < 30 guard — Encoder (level 30) and above can call RPC directly',
     NULL,
     'RPC allows Data Team+ access; Flutter screen does not'),
    (v_f07_id, 'matrix', 'Encoder governance.role_permission_matrix.view',
     'is_allowed = true, source_type = derived — matrix says Encoder is allowed to view',
     NULL,
     'Matrix intent supports Encoder access; Flutter screen and RPC are misaligned');

END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: VALIDATION NOTES
-- ═══════════════════════════════════════════════════════════════════════════
-- After applying this migration, verify:
--
-- 1. Tables created:
--    SELECT table_name FROM information_schema.tables
--    WHERE table_schema = 'public'
--      AND table_name IN (
--        'permission_drift_scan_runs',
--        'permission_drift_findings',
--        'permission_drift_evidence'
--      );
--    → Must return 3 rows.
--
-- 2. Seed findings inserted:
--    SELECT finding_code, severity, status, drift_category
--    FROM public.permission_drift_findings
--    ORDER BY finding_code;
--    → Must return F-01 through F-07.
--
-- 3. Evidence rows present:
--    SELECT f.finding_code, COUNT(e.id) AS evidence_count
--    FROM public.permission_drift_findings f
--    JOIN public.permission_drift_evidence e ON e.finding_id = f.id
--    GROUP BY f.finding_code
--    ORDER BY f.finding_code;
--    → Must return 3 evidence rows per finding (F-01 through F-07).
--
-- 4. RPC output shape (requires role_level >= 90):
--    SELECT finding_code, severity, status, jsonb_array_length(evidence) AS ev_count
--    FROM public.fn_get_permission_drift_findings();
--    → Must return 7 rows; ev_count = 3 for each.
--
-- 5. Summary RPC:
--    SELECT * FROM public.fn_get_permission_drift_summary();
--    → total_findings = 7; accepted_risk_count = 1 (F-06); open_count = 6.
--    → high_count = 1 (F-01); medium_count = 2 (F-02, F-03);
--      low_count = 2 (F-04, F-05); info_count = 2 (F-06, F-07).
--
-- 6. Unauthorized access denied:
--    -- Connect as a non-SA/HA role (level < 90) and execute:
--    SELECT * FROM public.fn_get_permission_drift_findings();
--    → Must raise SQLSTATE 42501.
--    SELECT * FROM public.fn_get_permission_drift_summary();
--    → Must raise SQLSTATE 42501.
--    SELECT * FROM public.permission_drift_findings;
--    → Must return 0 rows (RLS blocks non-governance roles).
--
-- 7. Evidence JSON structure:
--    SELECT jsonb_array_elements(evidence) AS ev
--    FROM public.fn_get_permission_drift_findings()
--    LIMIT 5;
--    → Each element must contain keys: evidence_type, evidence_key,
--      evidence_value, file_path, line_note.
