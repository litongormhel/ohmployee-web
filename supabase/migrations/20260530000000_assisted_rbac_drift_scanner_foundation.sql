-- Migration: 20260530000000_assisted_rbac_drift_scanner_foundation.sql
-- Ticket: OHM2026_1052 — Implement Assisted RBAC Drift Scanner Backend Foundation
--
-- Creates the assisted scanner infrastructure layer:
--   rbac_drift_scanner_definitions  — catalog of known scanners (S-01 through S-07)
--   rbac_drift_scan_runs            — log of assisted scan executions
--   rbac_drift_scan_results         — per-finding outputs from each scan run
--   rbac_drift_scan_evidence        — structured evidence items backing each result
--
-- Adds read-only RPCs:
--   fn_get_rbac_drift_scanners()                         — scanner registry list
--   fn_get_rbac_drift_scan_runs()                        — recent scan run history
--   fn_get_rbac_drift_scan_results(p_scan_run_id)        — results with inlined evidence
--
-- Adds controlled mutation RPC:
--   fn_record_assisted_rbac_drift_scan(...)              — record external scanner outputs
--
-- This migration does NOT:
--   - Modify any existing RLS policy, RPC, trigger, or authorization helper
--   - Add cron jobs, Edge Function schedules, or CI build gates
--   - Add auto-remediation or automatic scan execution
--   - Add editable permission controls or Flutter UI
--   - Modify the existing permission_drift_* tables
--   - Change production authorization behavior in any way
--
-- This is assisted scanner infrastructure: it accepts and records scanner
-- outputs provided externally (Claude / Codex / manual audit) via the
-- fn_record_assisted_rbac_drift_scan RPC only.
--
-- Reversible: drop the four new tables and four new RPCs to remove this
-- layer entirely without affecting live enforcement or existing drift findings.
-- ─────────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: SCANNER REGISTRY TABLE
-- ═══════════════════════════════════════════════════════════════════════════

-- Catalog of known scanner modules. One row per scanner (S-01 through S-07).
-- is_automated = false for all Phase 2 scanners — assisted mode only.
-- requires_flutter_snapshot = true for scanners that need the CI-generated
-- JSONB payload (S-03, S-06, S-07) to evaluate Flutter-side drift.
CREATE TABLE public.rbac_drift_scanner_definitions (
  id                        uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  scanner_code              text        NOT NULL UNIQUE,           -- e.g. 'S-01'
  scanner_name              text        NOT NULL,
  scanner_category          text        NOT NULL,
  description               text        NOT NULL,
  default_severity          text        NOT NULL
                                        CHECK (default_severity IN ('critical', 'high', 'medium', 'low', 'info')),
  is_enabled                boolean     NOT NULL DEFAULT true,
  is_automated              boolean     NOT NULL DEFAULT false,    -- always false in Phase 2
  requires_flutter_snapshot boolean     NOT NULL DEFAULT false,
  sort_order                integer     NOT NULL DEFAULT 0,
  created_at                timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.rbac_drift_scanner_definitions IS
  'Registry of RBAC drift scanner modules. Phase 2: assisted / externally-driven only. '
  'is_automated remains false until Phase 3 (semi-automated) is approved.';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: SEED SCANNER DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.rbac_drift_scanner_definitions
  (scanner_code, scanner_name, scanner_category, description,
   default_severity, is_enabled, is_automated, requires_flutter_snapshot, sort_order)
VALUES
  (
    'S-01', 'RLS Coverage Scanner', 'backend',
    'Audits tables declared with enforcement_type = db_rls in role_permission_definitions '
    'to verify a corresponding RLS policy exists in information_schema.policies. '
    'Detects missing, overly permissive (USING TRUE), or scope-blind policies on sensitive tables.',
    'high', true, false, false, 10
  ),
  (
    'S-02', 'RPC Guard Scanner', 'backend',
    'Audits SECURITY DEFINER functions declared with enforcement_type = rpc in the registry '
    'to verify their body contains a get_my_role_level() call and a denial RAISE with ERRCODE 42501. '
    'Detects RPCs with no role guard, no denial path, and phantom registry references.',
    'medium', true, false, false, 20
  ),
  (
    'S-03', 'Flutter Visibility Drift Scanner', 'flutter',
    'Audits Flutter client-side capability checks (can* getters in LoggedInUser, '
    'RolePermissions static helpers, allowedRoles in MoreMenuItemConfig) against '
    'the role_permission_matrix. Detects UI/backend mismatches and invisible gaps. '
    'Requires a pre-computed Flutter snapshot JSONB payload.',
    'medium', true, false, true, 30
  ),
  (
    'S-04', 'Permission Registry Coverage Scanner', 'backend',
    'Audits whether every SECURITY DEFINER RPC in pg_proc and every RLS-enabled table '
    'in information_schema.tables has a corresponding entry in role_permission_definitions. '
    'Detects authorization behavior that is not reflected in the permission registry.',
    'medium', true, false, false, 40
  ),
  (
    'S-05', 'Role Hierarchy Consistency Scanner', 'backend',
    'Audits that roles.role_level in the database agrees with every numeric level '
    'reference used in RPC guards, and that the get_my_role_level() function body '
    'contains no hardcoded CASE branches (regression guard for G1/G2 closure). '
    'Also detects duplicate role_level values and orphaned roles.',
    'medium', true, false, false, 50
  ),
  (
    'S-06', 'UI Security Assumption Scanner', 'flutter',
    'Audits that no ui_only enforcement entry in the matrix is being treated as a '
    'security boundary. Detects sensitive permissions protected only by a UI gate '
    'with no corresponding RLS policy or SECURITY DEFINER RPC. '
    'Requires a pre-computed Flutter snapshot JSONB payload.',
    'high', true, false, true, 60
  ),
  (
    'S-07', 'Unauthorized Navigation Exposure Scanner', 'flutter',
    'Audits that every navigable route to a sensitive screen has a backend guard '
    'at or before the data access point — not only a UI visibility gate. '
    'Detects screens protected only by allowedRoles or isSuperAdmin checks '
    'without a matching RPC or RLS guard. '
    'Requires a pre-computed Flutter snapshot JSONB payload.',
    'high', true, false, true, 70
  );


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: SCAN EXECUTION TABLE
-- ═══════════════════════════════════════════════════════════════════════════

-- Records each assisted scan run — who triggered it, which scanners ran,
-- optional scope filter, optional Flutter snapshot, and aggregate counts.
-- scan_mode = 'manual' is the only valid mode in Phase 2.
-- triggered_by references auth.users (not users_profile) to remain valid
-- even if the profile row is archived.
CREATE TABLE public.rbac_drift_scan_runs (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_name       text        NOT NULL,
  scan_mode       text        NOT NULL DEFAULT 'manual'
                              CHECK (scan_mode IN ('manual', 'assisted', 'automated')),
  scan_status     text        NOT NULL DEFAULT 'completed'
                              CHECK (scan_status IN ('running', 'completed', 'failed')),
  triggered_by    uuid        REFERENCES auth.users(id),
  scanner_codes   text[]      NOT NULL DEFAULT '{}',
  module_filter   text,
  flutter_snapshot jsonb,
  started_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz,
  total_results   integer     NOT NULL DEFAULT 0,
  critical_count  integer     NOT NULL DEFAULT 0,
  high_count      integer     NOT NULL DEFAULT 0,
  medium_count    integer     NOT NULL DEFAULT 0,
  low_count       integer     NOT NULL DEFAULT 0,
  info_count      integer     NOT NULL DEFAULT 0,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.rbac_drift_scan_runs IS
  'Execution log for assisted RBAC drift scan runs. '
  'Phase 2: scan_mode = manual only. Automated modes reserved for Phase 3+.';

CREATE INDEX idx_rbac_scan_runs_started_at    ON public.rbac_drift_scan_runs (started_at DESC);
CREATE INDEX idx_rbac_scan_runs_triggered_by  ON public.rbac_drift_scan_runs (triggered_by);


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: SCAN RESULT TABLE
-- ═══════════════════════════════════════════════════════════════════════════

-- One row per finding emitted by a scanner run.
-- fingerprint is the deduplication hash: hash(scanner_code || module_key || resource_key || action_key || role_name)
-- The (scan_run_id, fingerprint) unique constraint prevents duplicate findings within the same run.
-- status defaults to 'detected' — SA/HA must triage before acting.
CREATE TABLE public.rbac_drift_scan_results (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_run_id      uuid        NOT NULL REFERENCES public.rbac_drift_scan_runs(id) ON DELETE CASCADE,
  scanner_code     text        NOT NULL REFERENCES public.rbac_drift_scanner_definitions(scanner_code),
  finding_code     text,
  fingerprint      text        NOT NULL,
  severity         text        NOT NULL
                               CHECK (severity IN ('critical', 'high', 'medium', 'low', 'info')),
  status           text        NOT NULL DEFAULT 'detected'
                               CHECK (status IN ('detected', 'triaged', 'accepted_risk', 'false_positive', 'resolved')),
  module_key       text,
  resource_key     text,
  action_key       text,
  role_name        text,
  expected_rule    text,
  observed_rule    text,
  result_summary   text        NOT NULL,
  recommendation   text,
  confidence_score numeric(5,2) NOT NULL DEFAULT 0.80
                               CHECK (confidence_score >= 0 AND confidence_score <= 1),
  is_regression    boolean     NOT NULL DEFAULT false,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scan_run_id, fingerprint)
);

COMMENT ON TABLE public.rbac_drift_scan_results IS
  'Per-finding outputs from assisted RBAC drift scan runs. '
  'Mutations only via fn_record_assisted_rbac_drift_scan. No direct client writes.';

CREATE INDEX idx_rbac_scan_results_run_id      ON public.rbac_drift_scan_results (scan_run_id);
CREATE INDEX idx_rbac_scan_results_scanner     ON public.rbac_drift_scan_results (scanner_code);
CREATE INDEX idx_rbac_scan_results_severity    ON public.rbac_drift_scan_results (severity);
CREATE INDEX idx_rbac_scan_results_status      ON public.rbac_drift_scan_results (status);
CREATE INDEX idx_rbac_scan_results_fingerprint ON public.rbac_drift_scan_results (fingerprint);


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: SCAN EVIDENCE TABLE
-- ═══════════════════════════════════════════════════════════════════════════

-- Structured evidence items backing each scan result.
-- Multiple evidence rows can back a single result.
-- evidence_payload carries scanner-specific structured data not covered by named columns.
CREATE TABLE public.rbac_drift_scan_evidence (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  result_id        uuid        NOT NULL REFERENCES public.rbac_drift_scan_results(id) ON DELETE CASCADE,
  evidence_type    text        NOT NULL
                               CHECK (evidence_type IN (
                                 'matrix', 'rls_policy', 'rpc_function',
                                 'flutter_code', 'doc_reference', 'audit_gap'
                               )),
  reference_path   text,       -- file path or DB object path (e.g. 'lib/core/constants/role_constants.dart')
  reference_name   text,       -- short label: function name, policy name, table name, file key
  line_note        text,       -- specific location note: "Line ~43: gate checks isSuperAdmin only"
  matched_pattern  text,       -- regex or text pattern the scanner matched or failed to find
  expected_value   text,       -- what the scanner expected to observe
  observed_value   text,       -- what the scanner actually observed
  evidence_payload jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.rbac_drift_scan_evidence IS
  'Structured evidence backing each rbac_drift_scan_results row. '
  'Cascades on result deletion. No direct client writes.';

CREATE INDEX idx_rbac_scan_evidence_result_id ON public.rbac_drift_scan_evidence (result_id);


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.rbac_drift_scanner_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rbac_drift_scan_runs           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rbac_drift_scan_results        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rbac_drift_scan_evidence       ENABLE ROW LEVEL SECURITY;

-- rbac_drift_scanner_definitions: SA + HA read; no direct client writes.
CREATE POLICY rbac_scanner_defs_select
  ON public.rbac_drift_scanner_definitions
  FOR SELECT
  USING (public.get_my_role_level() >= 90);

-- rbac_drift_scan_runs: SA + HA read; no direct client writes.
CREATE POLICY rbac_scan_runs_select
  ON public.rbac_drift_scan_runs
  FOR SELECT
  USING (public.get_my_role_level() >= 90);

-- rbac_drift_scan_results: SA + HA read; no direct client writes.
CREATE POLICY rbac_scan_results_select
  ON public.rbac_drift_scan_results
  FOR SELECT
  USING (public.get_my_role_level() >= 90);

-- rbac_drift_scan_evidence: SA + HA read; no direct client writes.
CREATE POLICY rbac_scan_evidence_select
  ON public.rbac_drift_scan_evidence
  FOR SELECT
  USING (public.get_my_role_level() >= 90);

-- No INSERT / UPDATE / DELETE policies on any of the four tables.
-- All mutations flow exclusively through fn_record_assisted_rbac_drift_scan
-- which is SECURITY DEFINER and bypasses RLS for controlled writes.


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7: READ RPC — fn_get_rbac_drift_scanners
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_get_rbac_drift_scanners()
RETURNS TABLE (
  scanner_code              text,
  scanner_name              text,
  scanner_category          text,
  description               text,
  default_severity          text,
  is_enabled                boolean,
  is_automated              boolean,
  requires_flutter_snapshot boolean,
  sort_order                integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Insufficient permissions to view RBAC drift scanner definitions'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    d.scanner_code,
    d.scanner_name,
    d.scanner_category,
    d.description,
    d.default_severity,
    d.is_enabled,
    d.is_automated,
    d.requires_flutter_snapshot,
    d.sort_order
  FROM public.rbac_drift_scanner_definitions d
  ORDER BY d.sort_order, d.scanner_code;
END;
$$;

COMMENT ON FUNCTION public.fn_get_rbac_drift_scanners() IS
  'Returns the full scanner registry. Auth: role_level >= 90 (SA + HA only). Read-only.';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 8: READ RPC — fn_get_rbac_drift_scan_runs
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_get_rbac_drift_scan_runs()
RETURNS TABLE (
  scan_run_id     uuid,
  scan_name       text,
  scan_mode       text,
  scan_status     text,
  scanner_codes   text[],
  module_filter   text,
  total_results   integer,
  critical_count  integer,
  high_count      integer,
  medium_count    integer,
  low_count       integer,
  info_count      integer,
  started_at      timestamptz,
  completed_at    timestamptz,
  notes           text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Insufficient permissions to view RBAC drift scan runs'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    r.id              AS scan_run_id,
    r.scan_name,
    r.scan_mode,
    r.scan_status,
    r.scanner_codes,
    r.module_filter,
    r.total_results,
    r.critical_count,
    r.high_count,
    r.medium_count,
    r.low_count,
    r.info_count,
    r.started_at,
    r.completed_at,
    r.notes
  FROM public.rbac_drift_scan_runs r
  ORDER BY r.started_at DESC;
END;
$$;

COMMENT ON FUNCTION public.fn_get_rbac_drift_scan_runs() IS
  'Returns scan run history ordered by started_at DESC. Auth: role_level >= 90 (SA + HA only). Read-only.';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 9: READ RPC — fn_get_rbac_drift_scan_results
-- ═══════════════════════════════════════════════════════════════════════════

-- Returns scan results with evidence inlined as a JSONB array.
-- p_scan_run_id = NULL returns results from the most recent completed run.
CREATE OR REPLACE FUNCTION public.fn_get_rbac_drift_scan_results(
  p_scan_run_id uuid DEFAULT NULL
)
RETURNS TABLE (
  result_id        uuid,
  scan_run_id      uuid,
  scanner_code     text,
  finding_code     text,
  severity         text,
  status           text,
  module_key       text,
  resource_key     text,
  action_key       text,
  role_name        text,
  expected_rule    text,
  observed_rule    text,
  result_summary   text,
  recommendation   text,
  confidence_score numeric,
  is_regression    boolean,
  evidence         jsonb,
  created_at       timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_run_id uuid;
BEGIN
  IF public.get_my_role_level() < 90 THEN
    RAISE EXCEPTION 'Insufficient permissions to view RBAC drift scan results'
      USING ERRCODE = '42501';
  END IF;

  -- Resolve run ID: use provided value or fall back to the most recent completed run.
  IF p_scan_run_id IS NOT NULL THEN
    v_run_id := p_scan_run_id;
  ELSE
    SELECT r.id INTO v_run_id
    FROM public.rbac_drift_scan_runs r
    WHERE r.scan_status = 'completed'
    ORDER BY r.started_at DESC
    LIMIT 1;
  END IF;

  RETURN QUERY
  SELECT
    sr.id                AS result_id,
    sr.scan_run_id,
    sr.scanner_code,
    sr.finding_code,
    sr.severity,
    sr.status,
    sr.module_key,
    sr.resource_key,
    sr.action_key,
    sr.role_name,
    sr.expected_rule,
    sr.observed_rule,
    sr.result_summary,
    sr.recommendation,
    sr.confidence_score,
    sr.is_regression,
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
          'evidence_type',    e.evidence_type,
          'reference_path',   e.reference_path,
          'reference_name',   e.reference_name,
          'line_note',        e.line_note,
          'matched_pattern',  e.matched_pattern,
          'expected_value',   e.expected_value,
          'observed_value',   e.observed_value,
          'evidence_payload', e.evidence_payload
        ) ORDER BY e.created_at)
       FROM public.rbac_drift_scan_evidence e
       WHERE e.result_id = sr.id),
      '[]'::jsonb
    )                    AS evidence,
    sr.created_at
  FROM public.rbac_drift_scan_results sr
  WHERE (v_run_id IS NULL OR sr.scan_run_id = v_run_id)
  ORDER BY
    CASE sr.severity
      WHEN 'critical' THEN 1
      WHEN 'high'     THEN 2
      WHEN 'medium'   THEN 3
      WHEN 'low'      THEN 4
      WHEN 'info'     THEN 5
    END,
    sr.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.fn_get_rbac_drift_scan_results(uuid) IS
  'Returns scan results with evidence inlined as JSONB. '
  'p_scan_run_id = NULL uses the most recent completed run. '
  'Auth: role_level >= 90 (SA + HA only). Read-only.';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 10: CONTROLLED MUTATION RPC — fn_record_assisted_rbac_drift_scan
-- ═══════════════════════════════════════════════════════════════════════════

-- Records externally-assisted scanner outputs from Claude/Codex/manual audit.
-- This is the ONLY path for writing to the rbac_drift_scan_* tables.
--
-- Security contract:
--   - SECURITY DEFINER + SET search_path: bypasses RLS for internal writes only;
--     caller still must pass the role_level >= 90 guard to proceed.
--   - No dynamic SQL in this function.
--   - Validates all scanner codes against rbac_drift_scanner_definitions.
--   - Validates p_results is a JSON array.
--   - Caps total results at 50 per run (overflow protection).
--   - Writes to rbac_drift_scan_runs, rbac_drift_scan_results, rbac_drift_scan_evidence only.
--   - Does NOT write to permission_drift_findings or any authorization-bearing table.
--   - Does NOT modify any RLS policy, RPC, trigger, or role assignment.
--
-- Expected p_results item shape (each element of the JSON array):
--   {
--     "scanner_code":     "S-01",
--     "fingerprint":      "<stable hash>",
--     "severity":         "high",
--     "module_key":       "plantilla",
--     "resource_key":     "plantilla",
--     "action_key":       "select",
--     "role_name":        null,
--     "expected_rule":    "RLS policy with role_level guard",
--     "observed_rule":    "No policy found in pg_policies",
--     "result_summary":   "Table plantilla has no RLS policy...",
--     "recommendation":   "Add a SELECT policy restricting...",
--     "confidence_score": 0.95,
--     "is_regression":    false,
--     "finding_code":     null,
--     "evidence": [
--       {
--         "evidence_type":    "rls_policy",
--         "reference_path":   null,
--         "reference_name":   "plantilla",
--         "line_note":        "No SELECT policy row in pg_policies",
--         "matched_pattern":  "SELECT policy",
--         "expected_value":   "policy with scope guard",
--         "observed_value":   "no policy",
--         "evidence_payload": {}
--       }
--     ]
--   }

CREATE OR REPLACE FUNCTION public.fn_record_assisted_rbac_drift_scan(
  p_scan_name       text,
  p_scanner_codes   text[],
  p_results         jsonb,
  p_module_filter   text    DEFAULT NULL,
  p_flutter_snapshot jsonb  DEFAULT NULL,
  p_notes           text    DEFAULT NULL
)
RETURNS uuid   -- returns the new scan_run_id
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_level   integer;
  v_result_count   integer;
  v_run_id         uuid;
  v_result         jsonb;
  v_result_id      uuid;
  v_evidence_item  jsonb;
  v_scanner_code   text;
  v_fingerprint    text;
  v_severity       text;
  v_finding_code   text;
  v_module_key     text;
  v_resource_key   text;
  v_action_key     text;
  v_role_name      text;
  v_expected_rule  text;
  v_observed_rule  text;
  v_result_summary text;
  v_recommendation text;
  v_confidence     numeric(5,2);
  v_is_regression  boolean;
  v_total_count    integer := 0;
  v_critical_count integer := 0;
  v_high_count     integer := 0;
  v_medium_count   integer := 0;
  v_low_count      integer := 0;
  v_info_count     integer := 0;
  v_bad_codes      text[];
BEGIN
  -- ─── Auth guard ───────────────────────────────────────────────────────────
  v_caller_level := public.get_my_role_level();
  IF v_caller_level < 90 THEN
    RAISE EXCEPTION 'Insufficient permissions to record assisted RBAC drift scan'
      USING ERRCODE = '42501';
  END IF;

  -- ─── Validate p_results is a JSON array ───────────────────────────────────
  IF p_results IS NULL OR jsonb_typeof(p_results) <> 'array' THEN
    RAISE EXCEPTION 'p_results must be a non-null JSON array'
      USING ERRCODE = '22023';
  END IF;

  -- ─── Validate result count cap ────────────────────────────────────────────
  v_result_count := jsonb_array_length(p_results);
  IF v_result_count > 50 THEN
    RAISE EXCEPTION 'Result count % exceeds maximum of 50 per assisted scan run. '
      'Split into multiple calls if needed.', v_result_count
      USING ERRCODE = '22023';
  END IF;

  -- ─── Validate all scanner codes exist in the registry ────────────────────
  IF array_length(p_scanner_codes, 1) > 0 THEN
    SELECT array_agg(requested_code)
    INTO v_bad_codes
    FROM unnest(p_scanner_codes) AS requested_code
    WHERE NOT EXISTS (
      SELECT 1 FROM public.rbac_drift_scanner_definitions d
      WHERE d.scanner_code = requested_code
    );

    IF v_bad_codes IS NOT NULL AND array_length(v_bad_codes, 1) > 0 THEN
      RAISE EXCEPTION 'Unknown scanner code(s): %. All scanner_codes must exist in rbac_drift_scanner_definitions.',
        array_to_string(v_bad_codes, ', ')
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ─── Validate all scanner_code values within p_results ───────────────────
  SELECT array_agg(DISTINCT (item->>'scanner_code'))
  INTO v_bad_codes
  FROM jsonb_array_elements(p_results) AS item
  WHERE (item->>'scanner_code') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.rbac_drift_scanner_definitions d
      WHERE d.scanner_code = item->>'scanner_code'
    );

  IF v_bad_codes IS NOT NULL AND array_length(v_bad_codes, 1) > 0 THEN
    RAISE EXCEPTION 'Unknown scanner_code value(s) in results: %. Must match rbac_drift_scanner_definitions.',
      array_to_string(v_bad_codes, ', ')
      USING ERRCODE = '22023';
  END IF;

  -- ─── Validate severity values within p_results ────────────────────────────
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_results) AS item
    WHERE (item->>'severity') NOT IN ('critical', 'high', 'medium', 'low', 'info')
  ) THEN
    RAISE EXCEPTION 'Invalid severity value in results. Allowed: critical, high, medium, low, info'
      USING ERRCODE = '22023';
  END IF;

  -- ─── Insert scan run (status = running) ───────────────────────────────────
  INSERT INTO public.rbac_drift_scan_runs (
    scan_name, scan_mode, scan_status, triggered_by,
    scanner_codes, module_filter, flutter_snapshot,
    started_at, notes
  ) VALUES (
    p_scan_name, 'assisted', 'running', auth.uid(),
    p_scanner_codes, p_module_filter, p_flutter_snapshot,
    now(), p_notes
  )
  RETURNING id INTO v_run_id;

  -- ─── Insert results and evidence ──────────────────────────────────────────
  FOR v_result IN SELECT * FROM jsonb_array_elements(p_results)
  LOOP
    -- Extract scalar fields with safe defaults.
    v_scanner_code   := v_result->>'scanner_code';
    v_fingerprint    := COALESCE(v_result->>'fingerprint', gen_random_uuid()::text);
    v_severity       := v_result->>'severity';
    v_finding_code   := v_result->>'finding_code';
    v_module_key     := v_result->>'module_key';
    v_resource_key   := v_result->>'resource_key';
    v_action_key     := v_result->>'action_key';
    v_role_name      := v_result->>'role_name';
    v_expected_rule  := v_result->>'expected_rule';
    v_observed_rule  := v_result->>'observed_rule';
    v_result_summary := COALESCE(v_result->>'result_summary', '');
    v_recommendation := v_result->>'recommendation';
    v_confidence     := COALESCE((v_result->>'confidence_score')::numeric(5,2), 0.80);
    v_is_regression  := COALESCE((v_result->>'is_regression')::boolean, false);

    -- Insert result row; skip duplicates within the same run by fingerprint.
    INSERT INTO public.rbac_drift_scan_results (
      scan_run_id, scanner_code, finding_code, fingerprint,
      severity, status, module_key, resource_key, action_key,
      role_name, expected_rule, observed_rule, result_summary,
      recommendation, confidence_score, is_regression
    ) VALUES (
      v_run_id, v_scanner_code, v_finding_code, v_fingerprint,
      v_severity, 'detected', v_module_key, v_resource_key, v_action_key,
      v_role_name, v_expected_rule, v_observed_rule, v_result_summary,
      v_recommendation, v_confidence, v_is_regression
    )
    ON CONFLICT (scan_run_id, fingerprint) DO NOTHING
    RETURNING id INTO v_result_id;

    -- Only insert evidence when the result row was actually inserted.
    IF v_result_id IS NOT NULL THEN
      -- Accumulate severity counts.
      v_total_count := v_total_count + 1;
      CASE v_severity
        WHEN 'critical' THEN v_critical_count := v_critical_count + 1;
        WHEN 'high'     THEN v_high_count     := v_high_count     + 1;
        WHEN 'medium'   THEN v_medium_count   := v_medium_count   + 1;
        WHEN 'low'      THEN v_low_count      := v_low_count      + 1;
        WHEN 'info'     THEN v_info_count     := v_info_count     + 1;
        ELSE NULL;
      END CASE;

      -- Insert each evidence item belonging to this result.
      IF v_result ? 'evidence' AND jsonb_typeof(v_result->'evidence') = 'array' THEN
        FOR v_evidence_item IN SELECT * FROM jsonb_array_elements(v_result->'evidence')
        LOOP
          INSERT INTO public.rbac_drift_scan_evidence (
            result_id, evidence_type, reference_path, reference_name,
            line_note, matched_pattern, expected_value, observed_value,
            evidence_payload
          ) VALUES (
            v_result_id,
            COALESCE(v_evidence_item->>'evidence_type', 'audit_gap'),
            v_evidence_item->>'reference_path',
            v_evidence_item->>'reference_name',
            v_evidence_item->>'line_note',
            v_evidence_item->>'matched_pattern',
            v_evidence_item->>'expected_value',
            v_evidence_item->>'observed_value',
            COALESCE((v_evidence_item->'evidence_payload'), '{}'::jsonb)
          );
        END LOOP;
      END IF;
    END IF;

    -- Reset per-iteration ID to detect ON CONFLICT skips correctly.
    v_result_id := NULL;
  END LOOP;

  -- ─── Finalize scan run ────────────────────────────────────────────────────
  UPDATE public.rbac_drift_scan_runs
  SET
    scan_status    = 'completed',
    completed_at   = now(),
    total_results  = v_total_count,
    critical_count = v_critical_count,
    high_count     = v_high_count,
    medium_count   = v_medium_count,
    low_count      = v_low_count,
    info_count     = v_info_count
  WHERE id = v_run_id;

  RETURN v_run_id;

EXCEPTION
  WHEN OTHERS THEN
    -- Mark the scan run as failed before re-raising.
    IF v_run_id IS NOT NULL THEN
      UPDATE public.rbac_drift_scan_runs
      SET scan_status = 'failed', completed_at = now()
      WHERE id = v_run_id;
    END IF;
    RAISE;
END;
$$;

COMMENT ON FUNCTION public.fn_record_assisted_rbac_drift_scan(text, text[], jsonb, text, jsonb, text) IS
  'Records externally-assisted RBAC drift scan outputs (Claude/Codex/manual audit) into the '
  'rbac_drift_scan_* tables. SECURITY DEFINER. Auth: role_level >= 90 (SA + HA only). '
  'Validates scanner codes, enforces 50-result cap, no dynamic SQL, no auth changes. '
  'Returns the new scan_run_id.';


-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATION QUERIES (run against staging after applying this migration)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. All four tables exist
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN (
--     'rbac_drift_scanner_definitions',
--     'rbac_drift_scan_runs',
--     'rbac_drift_scan_results',
--     'rbac_drift_scan_evidence'
--   );
-- → 4 rows

-- 2. All 7 scanner definitions seeded
-- SELECT scanner_code, scanner_name, scanner_category, default_severity
-- FROM public.rbac_drift_scanner_definitions ORDER BY sort_order;
-- → S-01 through S-07

-- 3. Read RPCs return correct shape (as SA/HA)
-- SELECT * FROM public.fn_get_rbac_drift_scanners();
-- → 7 rows
-- SELECT * FROM public.fn_get_rbac_drift_scan_runs();
-- → 0 rows (no runs yet)
-- SELECT * FROM public.fn_get_rbac_drift_scan_results(NULL);
-- → 0 rows (no results yet)

-- 4. Manual scan recording inserts run, results, and evidence
-- SELECT public.fn_record_assisted_rbac_drift_scan(
--   'Test Scan',
--   ARRAY['S-01'],
--   '[{
--     "scanner_code": "S-01",
--     "fingerprint": "test-fingerprint-001",
--     "severity": "medium",
--     "module_key": "plantilla",
--     "resource_key": "plantilla",
--     "action_key": "select",
--     "role_name": null,
--     "expected_rule": "RLS policy",
--     "observed_rule": "No policy",
--     "result_summary": "Test finding",
--     "recommendation": "Add policy",
--     "confidence_score": 0.90,
--     "is_regression": false,
--     "evidence": [{
--       "evidence_type": "rls_policy",
--       "reference_name": "plantilla",
--       "line_note": "No SELECT policy found",
--       "matched_pattern": "SELECT policy",
--       "expected_value": "policy with guard",
--       "observed_value": "no policy"
--     }]
--   }]'::jsonb
-- );
-- → returns a UUID (scan_run_id)

-- 5. Invalid scanner code rejected
-- SELECT public.fn_record_assisted_rbac_drift_scan(
--   'Bad Test', ARRAY['S-99'], '[]'::jsonb
-- );
-- → SQLSTATE 22023 (Unknown scanner code(s): S-99)

-- 6. Result count > 50 rejected
-- Build array of 51 items and call fn_record_assisted_rbac_drift_scan → SQLSTATE 22023

-- 7. Unauthorized user denied
-- (as role_level < 90) SELECT * FROM public.fn_get_rbac_drift_scanners();
-- → SQLSTATE 42501
-- (as role_level < 90) SELECT public.fn_record_assisted_rbac_drift_scan(...);
-- → SQLSTATE 42501
