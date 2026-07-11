-- ─────────────────────────────────────────────────────────────────────────────
-- 20260531000000_app_settings_phase3_backend.sql
-- Backend Architecture for App Settings Phase 3
-- ─────────────────────────────────────────────────────────────────────────────

-- §1. Extend audit_action enum
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'UPDATE_SETTINGS';

-- §2. Create public.user_settings table
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id uuid PRIMARY KEY REFERENCES public.users_profile(id) ON DELETE CASCADE,
  push_notifications_enabled boolean NOT NULL DEFAULT true,
  vacancy_alerts_enabled boolean NOT NULL DEFAULT true,
  approval_alerts_enabled boolean NOT NULL DEFAULT true,
  sla_breach_alerts_enabled boolean NOT NULL DEFAULT true,
  reduce_motion_enabled boolean NOT NULL DEFAULT false,
  text_size text NOT NULL DEFAULT 'Default',
  theme_mode text NOT NULL DEFAULT 'system',
  auto_logout_minutes integer NOT NULL DEFAULT 30,
  biometric_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- §3. Add constraints
ALTER TABLE public.user_settings DROP CONSTRAINT IF EXISTS chk_text_size;
ALTER TABLE public.user_settings ADD CONSTRAINT chk_text_size CHECK (text_size IN ('Default', 'Large'));

ALTER TABLE public.user_settings DROP CONSTRAINT IF EXISTS chk_theme_mode;
ALTER TABLE public.user_settings ADD CONSTRAINT chk_theme_mode CHECK (theme_mode IN ('system', 'light', 'dark'));

ALTER TABLE public.user_settings DROP CONSTRAINT IF EXISTS chk_auto_logout_minutes;
ALTER TABLE public.user_settings ADD CONSTRAINT chk_auto_logout_minutes CHECK (auto_logout_minutes IN (15, 30, 60));

-- §4. Enable Row Level Security (RLS)
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- §5. Define RLS Policies
DROP POLICY IF EXISTS "Allow users to read own settings" ON public.user_settings;
CREATE POLICY "Allow users to read own settings"
  ON public.user_settings FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT id FROM public.users_profile WHERE auth_user_id = auth.uid())
    OR public.is_super_admin()
  );

DROP POLICY IF EXISTS "Allow users to insert own settings" ON public.user_settings;
CREATE POLICY "Allow users to insert own settings"
  ON public.user_settings FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT id FROM public.users_profile WHERE auth_user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Allow users to update own settings" ON public.user_settings;
CREATE POLICY "Allow users to update own settings"
  ON public.user_settings FOR UPDATE
  TO authenticated
  USING (
    user_id = (SELECT id FROM public.users_profile WHERE auth_user_id = auth.uid())
  )
  WITH CHECK (
    user_id = (SELECT id FROM public.users_profile WHERE auth_user_id = auth.uid())
  );

-- §6. Create Trigger for Security-Sensitive Settings Changes
CREATE OR REPLACE FUNCTION public.on_user_settings_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_actor_id UUID;
  v_actor_role TEXT;
  v_old_data JSONB := NULL;
  v_new_data JSONB := NULL;
  v_log_needed BOOLEAN := FALSE;
  v_user_name TEXT;
BEGIN
  -- Resolve actor
  v_actor_id := auth.uid();
  
  -- Resolve actor's role and target user's full name
  IF v_actor_id IS NOT NULL THEN
    SELECT r.role_name, up.full_name
      INTO v_actor_role, v_user_name
      FROM public.users_profile up
      LEFT JOIN public.roles r ON r.id = up.role_id
     WHERE up.auth_user_id = v_actor_id
     LIMIT 1;
  ELSE
    SELECT full_name
      INTO v_user_name
      FROM public.users_profile
     WHERE id = NEW.user_id;
  END IF;

  -- 1. Check for Auto Logout changes
  IF TG_OP = 'UPDATE' THEN
    IF OLD.auto_logout_minutes IS DISTINCT FROM NEW.auto_logout_minutes THEN
      v_old_data := COALESCE(v_old_data, jsonb_build_object()) || jsonb_build_object('auto_logout_minutes', OLD.auto_logout_minutes);
      v_new_data := COALESCE(v_new_data, jsonb_build_object()) || jsonb_build_object('auto_logout_minutes', NEW.auto_logout_minutes);
      v_log_needed := TRUE;
    END IF;

    -- 2. Check for Biometric Marker changes
    IF OLD.biometric_enabled IS DISTINCT FROM NEW.biometric_enabled THEN
      v_old_data := COALESCE(v_old_data, jsonb_build_object()) || jsonb_build_object('biometric_enabled', OLD.biometric_enabled);
      v_new_data := COALESCE(v_new_data, jsonb_build_object()) || jsonb_build_object('biometric_enabled', NEW.biometric_enabled);
      v_log_needed := TRUE;
    END IF;

    -- 3. Check for Push Notifications (Notification master toggle) changes
    IF OLD.push_notifications_enabled IS DISTINCT FROM NEW.push_notifications_enabled THEN
      v_old_data := COALESCE(v_old_data, jsonb_build_object()) || jsonb_build_object('push_notifications_enabled', OLD.push_notifications_enabled);
      v_new_data := COALESCE(v_new_data, jsonb_build_object()) || jsonb_build_object('push_notifications_enabled', NEW.push_notifications_enabled);
      v_log_needed := TRUE;
    END IF;
  ELSIF TG_OP = 'INSERT' THEN
    v_old_data := jsonb_build_object(
      'auto_logout_minutes', NULL,
      'biometric_enabled', NULL,
      'push_notifications_enabled', NULL
    );
    v_new_data := jsonb_build_object(
      'auto_logout_minutes', NEW.auto_logout_minutes,
      'biometric_enabled', NEW.biometric_enabled,
      'push_notifications_enabled', NEW.push_notifications_enabled
    );
    v_log_needed := TRUE;
  END IF;

  -- Write to audit logs if any monitored change occurred
  IF v_log_needed THEN
    v_old_data := v_old_data || jsonb_build_object('full_name', v_user_name);
    v_new_data := v_new_data || jsonb_build_object('full_name', v_user_name);

    INSERT INTO public.audit_logs (
      actor_id,
      module,
      action,
      record_id,
      old_data,
      new_data,
      timestamp,
      role
    ) VALUES (
      COALESCE(v_actor_id, (SELECT auth_user_id FROM public.users_profile WHERE id = NEW.user_id)),
      'App Settings',
      'UPDATE_SETTINGS'::public.audit_action,
      NEW.user_id,
      v_old_data,
      v_new_data,
      NOW(),
      v_actor_role
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_user_settings_changed ON public.user_settings;
CREATE TRIGGER trg_on_user_settings_changed
  AFTER INSERT OR UPDATE ON public.user_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.on_user_settings_changed();

-- §7. Create Trigger for Default Settings Provisioning
CREATE OR REPLACE FUNCTION public.handle_create_default_user_settings()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO public.user_settings (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_default_user_settings ON public.users_profile;
CREATE TRIGGER trg_create_default_user_settings
  AFTER INSERT ON public.users_profile
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_create_default_user_settings();

-- §8. Backfill existing user profiles with default settings
INSERT INTO public.user_settings (user_id)
SELECT id FROM public.users_profile
ON CONFLICT (user_id) DO NOTHING;
