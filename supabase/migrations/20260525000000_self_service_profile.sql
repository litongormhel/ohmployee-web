-- ─────────────────────────────────────────────────────────────────────────────
-- 20260525000000_self_service_profile.sql
-- Secure Self-Service User Profile Settings Module
--
-- Features implemented:
--   §1  Extend audit_action enum with self-service actions
--   §2  Add profile fields (avatar_path, mobile_number) to public.users_profile
--   §3  Add format validation check constraint for mobile numbers (09XXXXXXXXX)
--   §4  Create update_own_profile SECURITY DEFINER RPC with strict ownership boundaries
--   §5  Create database-level password change trigger on auth.users for audit logging
--   §6  Provision private profile_photos storage bucket and define secure RLS policies
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- §1  Extend audit_action enum
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'UPDATE_AVATAR';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'UPDATE_MOBILE';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'CHANGE_PASSWORD';

-- ─────────────────────────────────────────────────────────────────────────────
-- §2  Add columns to users_profile
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.users_profile
  ADD COLUMN IF NOT EXISTS avatar_path TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS mobile_number TEXT DEFAULT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- §3  Add mobile number format constraint
--     Enforces exact 09XXXXXXXXX mobile format if field is populated.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.users_profile
  DROP CONSTRAINT IF EXISTS chk_mobile_number,
  ADD CONSTRAINT chk_mobile_number CHECK (
    mobile_number IS NULL OR mobile_number ~ '^09[0-9]{9}$'
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- §4  Create update_own_profile RPC
--     Enforces that a user can strictly only update their own self-service details.
--     Super Admin or other users CANNOT update another user's self-service profile
--     using this function (context strictly resolved from caller JWT auth.uid()).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_own_profile(
  p_mobile_number TEXT DEFAULT NULL,
  p_avatar_path   TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_auth_id UUID;
  v_profile_id     UUID;
  v_old_mobile     TEXT;
  v_old_avatar     TEXT;
  v_target_name    TEXT;
BEGIN
  v_caller_auth_id := auth.uid();
  
  IF v_caller_auth_id IS NULL THEN
    RAISE EXCEPTION 'unauthenticated: caller has no active session'
      USING ERRCODE = '42501';
  END IF;

  -- Resolve the calling user's own profile row
  SELECT id, full_name, mobile_number, avatar_path
    INTO v_profile_id, v_target_name, v_old_mobile, v_old_avatar
    FROM public.users_profile
   WHERE auth_user_id = v_caller_auth_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user profile not found for authenticated user: %', v_caller_auth_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── 1. Apply Mobile Number Update ─────────────────────────────────────────
  IF p_mobile_number IS DISTINCT FROM v_old_mobile THEN
    -- Verify format at database level (redundant safety net)
    IF p_mobile_number IS NOT NULL AND p_mobile_number !~ '^09[0-9]{9}$' THEN
      RAISE EXCEPTION 'invalid mobile number format: must match 09XXXXXXXXX'
        USING ERRCODE = '22023';
    END IF;

    UPDATE public.users_profile
       SET mobile_number = p_mobile_number,
           updated_at    = NOW()
     WHERE id = v_profile_id;

    -- Audit log mobile change (privacy-safe: do not store raw mobile number values)
    INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_caller_auth_id,
      'User Profile',
      'UPDATE_MOBILE'::public.audit_action,
      v_profile_id,
      jsonb_build_object('full_name', v_target_name, 'action', 'Mobile number updated'),
      jsonb_build_object('full_name', v_target_name, 'action', 'Mobile number successfully updated')
    );
  END IF;

  -- ── 2. Apply Avatar Path Update ───────────────────────────────────────────
  IF p_avatar_path IS DISTINCT FROM v_old_avatar THEN
    -- Strict security: avatar file must lie strictly inside user's own folder
    IF p_avatar_path IS NOT NULL AND p_avatar_path !~ ('^' || v_caller_auth_id::text || '/avatar\.webp$') THEN
      RAISE EXCEPTION 'unauthorized storage path: avatar must reside inside own folder ({user_id}/avatar.webp)'
        USING ERRCODE = '42501';
    END IF;

    UPDATE public.users_profile
       SET avatar_path = p_avatar_path,
           updated_at  = NOW()
     WHERE id = v_profile_id;

    -- Audit log avatar change
    INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      v_caller_auth_id,
      'User Profile',
      'UPDATE_AVATAR'::public.audit_action,
      v_profile_id,
      jsonb_build_object('avatar_path', v_old_avatar, 'full_name', v_target_name),
      jsonb_build_object('avatar_path', p_avatar_path, 'full_name', v_target_name)
    );
  END IF;

END;
$$;

-- Secure access
REVOKE ALL ON FUNCTION public.update_own_profile(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_own_profile(TEXT, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- §5  Database password-change trigger
--     Intercepts changes to auth.users.encrypted_password and records audit log.
--     Captures password resets, manual updates, and email recovery changes.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.on_auth_user_password_changed()
RETURNS TRIGGER AS $$
DECLARE
  v_profile_id UUID;
  v_full_name  TEXT;
BEGIN
  IF NEW.encrypted_password IS DISTINCT FROM OLD.encrypted_password THEN
    -- Resolve linked user profile
    SELECT id, full_name
      INTO v_profile_id, v_full_name
      FROM public.users_profile
     WHERE auth_user_id = NEW.id;

    -- Insert password change audit entry
    INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
    VALUES (
      NEW.id,
      'User Profile',
      'CHANGE_PASSWORD'::public.audit_action,
      COALESCE(v_profile_id, NEW.id),
      jsonb_build_object('email', NEW.email, 'full_name', v_full_name, 'action', 'Password updated'),
      jsonb_build_object('email', NEW.email, 'full_name', v_full_name, 'action', 'Password successfully updated')
    );
  END IF;
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Swallow error to ensure auth.users password updates never fail/lockout
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_auth_user_password_changed ON auth.users;
CREATE TRIGGER trg_on_auth_user_password_changed
  AFTER UPDATE OF encrypted_password ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.on_auth_user_password_changed();

-- ─────────────────────────────────────────────────────────────────────────────
-- §6  Provision private profile_photos storage bucket & define secure RLS
-- ─────────────────────────────────────────────────────────────────────────────

-- Ensure the bucket exists and is private with tight limits
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'profile_photos',
  'profile_photos',
  FALSE,                      -- Private bucket preferred
  512000,                     -- Max 500KB size limit
  ARRAY['image/webp']         -- WebP files only
)
ON CONFLICT (id) DO UPDATE SET
  public = FALSE,
  file_size_limit = 512000,
  allowed_mime_types = ARRAY['image/webp'];

-- Enable Row-Level Security on storage objects (failsafe)

-- Policy A: SELECT read permission (Authenticated users can read all profile photos)
-- Allows the Team Directory, Plantilla screens, and detail sheets to load circular avatars safely.
DROP POLICY IF EXISTS "Allow authenticated read profile photos" ON storage.objects;
CREATE POLICY "Allow authenticated read profile photos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'profile_photos');

-- Policy B: WRITE write/update/delete permission (Strict owner folder restriction)
-- Enforces `{auth.uid()}/avatar.webp` constraint. Users can write/delete ONLY their own file.
DROP POLICY IF EXISTS "Allow users to upload own profile photos" ON storage.objects;
CREATE POLICY "Allow users to upload own profile photos"
  ON storage.objects FOR ALL
  TO authenticated
  USING (
    bucket_id = 'profile_photos' AND 
    name = (auth.uid()::text || '/avatar.webp')
  )
  WITH CHECK (
    bucket_id = 'profile_photos' AND 
    name = (auth.uid()::text || '/avatar.webp')
  );
