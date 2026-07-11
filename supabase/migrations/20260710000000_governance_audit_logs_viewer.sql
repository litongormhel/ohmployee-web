-- ─────────────────────────────────────────────────────────────────────────────
-- OHM's Safespace: Governance Audit Logs Viewer RPC
-- Creates fn_get_governance_audit_log for safe frontend reads of audit log events.
-- Backend-enforced: caller must be superAdmin (role_level >= 100).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_get_governance_audit_log()
RETURNS TABLE(
  id              uuid,
  control_key     text,
  action          text,
  before_value    jsonb,
  after_value     jsonb,
  changed_at      timestamptz,
  reason          text,
  changed_by_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_level int;
BEGIN
  -- Enforce superAdmin-only caller
  SELECT r.role_level INTO v_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF v_level IS NULL OR v_level < 100 THEN
    RAISE EXCEPTION 'Access denied: fn_get_governance_audit_log requires superAdmin.';
  END IF;

  RETURN QUERY
  SELECT
    gal.id,
    gal.control_key,
    gal.action,
    gal.before_value,
    gal.after_value,
    gal.changed_at,
    gal.reason,
    up.full_name AS changed_by_name
  FROM public.governance_audit_log gal
  LEFT JOIN public.users_profile up ON up.id = gal.changed_by
  ORDER BY gal.changed_at DESC;
END;
$$;

-- Revoke all public execution permissions and grant to authenticated only
REVOKE ALL ON FUNCTION public.fn_get_governance_audit_log() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_governance_audit_log() TO authenticated;

COMMENT ON FUNCTION public.fn_get_governance_audit_log() IS
  'OHM2026_0043: Fetches security audit log records with last-updated administrator names. '
  'Enforces superAdmin-only (role_level >= 100) on authenticated caller.';
