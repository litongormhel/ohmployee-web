-- ─────────────────────────────────────────────────────────────────────────────
-- 20260601000000_security_center_phase4_backend.sql
-- Backend Architecture for Security Center Phase 4
-- ─────────────────────────────────────────────────────────────────────────────

-- §1. Create public.active_user_sessions table
CREATE TABLE IF NOT EXISTS public.active_user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users_profile(id) ON DELETE CASCADE,
  device_platform text NOT NULL,
  app_version text NOT NULL,
  ip_address text,
  login_at timestamp with time zone NOT NULL DEFAULT now(),
  last_seen_at timestamp with time zone NOT NULL DEFAULT now(),
  revoked_at timestamp with time zone,
  revoke_reason text,
  is_suspicious boolean NOT NULL DEFAULT false,
  CONSTRAINT chk_revoke_reason CHECK (
    (revoked_at IS NULL AND revoke_reason IS NULL) OR 
    (revoked_at IS NOT NULL AND revoke_reason IS NOT NULL)
  )
);

COMMENT ON COLUMN public.active_user_sessions.ip_address IS 'Safely captured client IP metadata (coalesced header/parameter value).';
COMMENT ON COLUMN public.active_user_sessions.is_suspicious IS 'Groundwork flag for abnormal logins (e.g. concurrent logins from distinct platforms/locations).';

-- §2. Create public.security_audit_logs table
CREATE TABLE IF NOT EXISTS public.security_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users_profile(id) ON DELETE CASCADE,
  session_id uuid REFERENCES public.active_user_sessions(id) ON DELETE SET NULL,
  action text NOT NULL,
  ip_address text,
  device_platform text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT chk_security_audit_action CHECK (
    action IN ('LOGIN', 'LOGOUT', 'REMOTE_REVOKE', 'REVOKE', 'SECURITY_SETTINGS_CHANGED', 'SUSPICIOUS_LOGIN')
  )
);

COMMENT ON TABLE public.security_audit_logs IS 'Dedicated secure audit trail for sensitive access and settings changes.';

-- §3. Create Indexes
CREATE INDEX IF NOT EXISTS idx_active_user_sessions_user_id 
  ON public.active_user_sessions(user_id);

CREATE INDEX IF NOT EXISTS idx_active_user_sessions_active 
  ON public.active_user_sessions(user_id) 
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_security_audit_logs_user_id 
  ON public.security_audit_logs(user_id);

CREATE INDEX IF NOT EXISTS idx_security_audit_logs_created_at 
  ON public.security_audit_logs(created_at DESC);

-- §4. Enable Row Level Security (RLS)
ALTER TABLE public.active_user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_audit_logs ENABLE ROW LEVEL SECURITY;

-- §5. Define RLS Policies
DROP POLICY IF EXISTS "Allow users to read own sessions" ON public.active_user_sessions;
CREATE POLICY "Allow users to read own sessions"
  ON public.active_user_sessions FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT id FROM public.users_profile WHERE auth_user_id = auth.uid())
    OR public.is_super_admin()
  );

DROP POLICY IF EXISTS "Allow users to read own security audit logs" ON public.security_audit_logs;
CREATE POLICY "Allow users to read own security audit logs"
  ON public.security_audit_logs FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT id FROM public.users_profile WHERE auth_user_id = auth.uid())
    OR public.is_super_admin()
  );

-- §6. Create IP Resolution Helper Function
CREATE OR REPLACE FUNCTION public.resolve_client_ip()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN COALESCE(
    current_setting('request.headers', true)::json->>'x-forwarded-for',
    '0.0.0.0'
  );
EXCEPTION WHEN OTHERS THEN
  RETURN '0.0.0.0';
END;
$$;

-- §7. Create RPC Functions

-- heartbeat_session()
CREATE OR REPLACE FUNCTION public.heartbeat_session(
  p_session_id uuid,
  p_device_platform text,
  p_app_version text,
  p_ip_address text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_profile_id uuid;
  v_existing_user_id uuid;
  v_revoked_at timestamp with time zone;
  v_resolved_ip text;
  v_is_suspicious boolean := false;
  v_session_id uuid;
BEGIN
  -- 1. Resolve user profile ID
  SELECT id INTO v_profile_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true
  LIMIT 1;

  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_ERROR: No active profile for this user.' USING ERRCODE = '42501';
  END IF;

  v_resolved_ip := COALESCE(p_ip_address, public.resolve_client_ip());

  -- 2. Check if a session ID was provided and already exists
  IF p_session_id IS NOT NULL THEN
    SELECT user_id, revoked_at INTO v_existing_user_id, v_revoked_at
    FROM public.active_user_sessions
    WHERE id = p_session_id;

    IF FOUND THEN
      -- Ownership check
      IF v_existing_user_id IS DISTINCT FROM v_profile_id THEN
        RAISE EXCEPTION 'AUTH_ERROR: Unauthorized access to this session.' USING ERRCODE = '42501';
      END IF;

      -- Revocation remote logout check
      IF v_revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'SESSION_REVOKED: This session has been revoked.' USING ERRCODE = '42501';
      END IF;

      -- Update timestamps and metadata
      UPDATE public.active_user_sessions
      SET 
        last_seen_at = now(),
        device_platform = COALESCE(p_device_platform, device_platform),
        app_version = COALESCE(p_app_version, app_version),
        ip_address = COALESCE(v_resolved_ip, ip_address)
      WHERE id = p_session_id;

      RETURN p_session_id;
    END IF;
  END IF;

  -- 3. If session does not exist, insert a new one
  -- Suspicious login groundwork: Check if user has concurrent active sessions on different platforms/locations
  SELECT EXISTS (
    SELECT 1 FROM public.active_user_sessions
    WHERE user_id = v_profile_id
      AND revoked_at IS NULL
      AND (device_platform IS DISTINCT FROM p_device_platform OR ip_address IS DISTINCT FROM v_resolved_ip)
  ) INTO v_is_suspicious;

  v_session_id := COALESCE(p_session_id, gen_random_uuid());

  INSERT INTO public.active_user_sessions (
    id,
    user_id,
    device_platform,
    app_version,
    ip_address,
    login_at,
    last_seen_at,
    is_suspicious
  ) VALUES (
    v_session_id,
    v_profile_id,
    p_device_platform,
    p_app_version,
    v_resolved_ip,
    now(),
    now(),
    v_is_suspicious
  );

  RETURN v_session_id;
END;
$$;

-- revoke_session()
CREATE OR REPLACE FUNCTION public.revoke_session(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_profile_id uuid;
  v_session_user_id uuid;
  v_is_revoked boolean;
BEGIN
  -- 1. Resolve user profile ID
  SELECT id INTO v_profile_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true
  LIMIT 1;

  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_ERROR: No active profile for this user.' USING ERRCODE = '42501';
  END IF;

  -- 2. Resolve session details
  SELECT user_id, (revoked_at IS NOT NULL) INTO v_session_user_id, v_is_revoked
  FROM public.active_user_sessions
  WHERE id = p_session_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Session not found.' USING ERRCODE = '42704';
  END IF;

  -- 3. Ownership / RBAC check: Must be owner OR Super Admin
  IF v_session_user_id IS DISTINCT FROM v_profile_id AND NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'AUTH_ERROR: Unauthorized to revoke this session.' USING ERRCODE = '42501';
  END IF;

  -- 4. Mark session revoked
  IF NOT v_is_revoked THEN
    UPDATE public.active_user_sessions
    SET 
      revoked_at = now(),
      revoke_reason = CASE 
        WHEN v_session_user_id IS DISTINCT FROM v_profile_id THEN 'admin_revoke' 
        ELSE 'user_logout' 
      END
    WHERE id = p_session_id;
  END IF;
END;
$$;

-- revoke_other_sessions()
CREATE OR REPLACE FUNCTION public.revoke_other_sessions(p_current_session_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_profile_id uuid;
BEGIN
  -- 1. Resolve user profile ID
  SELECT id INTO v_profile_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true
  LIMIT 1;

  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_ERROR: No active profile for this user.' USING ERRCODE = '42501';
  END IF;

  -- 2. Revoke other sessions
  UPDATE public.active_user_sessions
  SET 
    revoked_at = now(),
    revoke_reason = 'remote_revoke'
  WHERE user_id = v_profile_id
    AND id IS DISTINCT FROM p_current_session_id
    AND revoked_at IS NULL;
END;
$$;

-- §8. Create Automated Triggers

-- Trigger function for active session lifecycle auditing
CREATE OR REPLACE FUNCTION public.on_active_user_sessions_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Log Login event
    INSERT INTO public.security_audit_logs (
      user_id,
      session_id,
      action,
      ip_address,
      device_platform,
      details
    ) VALUES (
      NEW.user_id,
      NEW.id,
      CASE WHEN NEW.is_suspicious THEN 'SUSPICIOUS_LOGIN' ELSE 'LOGIN' END,
      NEW.ip_address,
      NEW.device_platform,
      jsonb_build_object(
        'app_version', NEW.app_version,
        'is_suspicious', NEW.is_suspicious
      )
    );
  ELSIF TG_OP = 'UPDATE' THEN
    -- Log Revocation / Logout events
    IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
      INSERT INTO public.security_audit_logs (
        user_id,
        session_id,
        action,
        ip_address,
        device_platform,
        details
      ) VALUES (
        NEW.user_id,
        NEW.id,
        CASE 
          WHEN NEW.revoke_reason = 'user_logout' THEN 'LOGOUT'
          WHEN NEW.revoke_reason = 'remote_revoke' THEN 'REMOTE_REVOKE'
          ELSE 'REVOKE'
        END,
        NEW.ip_address,
        NEW.device_platform,
        jsonb_build_object(
          'revoke_reason', NEW.revoke_reason,
          'last_seen_at', NEW.last_seen_at
        )
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_active_user_sessions_change ON public.active_user_sessions;
CREATE TRIGGER trg_on_active_user_sessions_change
  AFTER INSERT OR UPDATE ON public.active_user_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.on_active_user_sessions_change();

-- Trigger function for public.user_settings security adjustments
CREATE OR REPLACE FUNCTION public.on_security_settings_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_log_needed boolean := false;
  v_changes jsonb := '{}'::jsonb;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    -- Monitor Biometrics toggle
    IF OLD.biometric_enabled IS DISTINCT FROM NEW.biometric_enabled THEN
      v_changes := v_changes || jsonb_build_object('biometric_enabled', jsonb_build_array(OLD.biometric_enabled, NEW.biometric_enabled));
      v_log_needed := true;
    END IF;

    -- Monitor Auto Logout configuration
    IF OLD.auto_logout_minutes IS DISTINCT FROM NEW.auto_logout_minutes THEN
      v_changes := v_changes || jsonb_build_object('auto_logout_minutes', jsonb_build_array(OLD.auto_logout_minutes, NEW.auto_logout_minutes));
      v_log_needed := true;
    END IF;

    IF v_log_needed THEN
      INSERT INTO public.security_audit_logs (
        user_id,
        action,
        details
      ) VALUES (
        NEW.user_id,
        'SECURITY_SETTINGS_CHANGED',
        jsonb_build_object('changes', v_changes)
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_security_settings_changed ON public.user_settings;
CREATE TRIGGER trg_on_security_settings_changed
  AFTER UPDATE ON public.user_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.on_security_settings_changed();
