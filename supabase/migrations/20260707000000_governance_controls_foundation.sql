-- ─────────────────────────────────────────────────────────────────────────────
-- OHM's Safespace: Governance Controls Foundation
-- Creates governance_controls, governance_audit_log, and helper RPCs.
-- All controls are enforced backend-side; Flutter reads state only.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. governance_controls ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS governance_controls (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  control_key  text        UNIQUE NOT NULL,
  enabled      boolean     NOT NULL DEFAULT true,
  updated_by   uuid        REFERENCES users_profile(id) ON DELETE SET NULL,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  reason       text
);

-- ── 2. governance_audit_log ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS governance_audit_log (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  control_key  text        NOT NULL,
  action       text        NOT NULL,
  before_value jsonb,
  after_value  jsonb,
  changed_by   uuid        REFERENCES users_profile(id) ON DELETE SET NULL,
  changed_at   timestamptz NOT NULL DEFAULT now(),
  reason       text,
  metadata     jsonb
);

-- ── 3. Seed initial controls ──────────────────────────────────────────────────
INSERT INTO governance_controls (control_key, enabled)
VALUES
  ('account_registration', true),
  ('import_plantilla',     true)
ON CONFLICT (control_key) DO NOTHING;

-- ── 4. RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE governance_controls  ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance_audit_log ENABLE ROW LEVEL SECURITY;

-- Only superAdmin (role_level >= 100) may read controls directly.
-- Enforcement RPCs use SECURITY DEFINER and bypass RLS for backend checks.
CREATE POLICY "superadmin_select_governance_controls"
  ON governance_controls FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM users_profile up
      JOIN roles r ON r.id = up.role_id
      WHERE up.auth_user_id = auth.uid()
        AND r.role_level >= 100
    )
  );

CREATE POLICY "superadmin_select_governance_audit_log"
  ON governance_audit_log FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM users_profile up
      JOIN roles r ON r.id = up.role_id
      WHERE up.auth_user_id = auth.uid()
        AND r.role_level >= 100
    )
  );

-- ── 5. fn_get_governance_controls ────────────────────────────────────────────
-- Lightweight read for Flutter; returns all controls with last-updated metadata.
CREATE OR REPLACE FUNCTION fn_get_governance_controls()
RETURNS TABLE(
  control_key     text,
  enabled         boolean,
  updated_at      timestamptz,
  reason          text,
  updated_by_name text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    gc.control_key,
    gc.enabled,
    gc.updated_at,
    gc.reason,
    up.full_name AS updated_by_name
  FROM governance_controls gc
  LEFT JOIN users_profile up ON up.id = gc.updated_by
  ORDER BY gc.control_key;
$$;

-- ── 6. fn_update_governance_control ─────────────────────────────────────────
-- Atomically toggles a control and writes an audit entry.
-- Backend enforced: caller must be superAdmin (role_level >= 100).
CREATE OR REPLACE FUNCTION fn_update_governance_control(
  p_control_key text,
  p_enabled     boolean,
  p_reason      text,
  p_actor_id    uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before  boolean;
  v_level   int;
BEGIN
  -- Enforce superAdmin-only caller
  SELECT r.role_level INTO v_level
  FROM users_profile up
  JOIN roles r ON r.id = up.role_id
  WHERE up.id = p_actor_id;

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_update_governance_control requires superAdmin.';
  END IF;

  -- Read current value for audit
  SELECT enabled INTO v_before
  FROM governance_controls
  WHERE control_key = p_control_key;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown governance control: %', p_control_key;
  END IF;

  -- Apply update
  UPDATE governance_controls
  SET
    enabled    = p_enabled,
    updated_by = p_actor_id,
    updated_at = now(),
    reason     = p_reason
  WHERE control_key = p_control_key;

  -- Write audit entry
  INSERT INTO governance_audit_log (
    control_key, action, before_value, after_value, changed_by, reason
  ) VALUES (
    p_control_key,
    CASE WHEN p_enabled THEN 'enable' ELSE 'disable' END,
    jsonb_build_object('enabled', v_before),
    jsonb_build_object('enabled', p_enabled),
    p_actor_id,
    p_reason
  );
END;
$$;

-- ── 7. fn_check_governance_control ───────────────────────────────────────────
-- Used by backend RPCs/triggers to gate actions before executing.
-- Returns false if control is disabled; callers should raise an error.
CREATE OR REPLACE FUNCTION fn_check_governance_control(p_control_key text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT enabled FROM governance_controls WHERE control_key = p_control_key),
    true  -- default to enabled if key not found (safe fallback)
  );
$$;
