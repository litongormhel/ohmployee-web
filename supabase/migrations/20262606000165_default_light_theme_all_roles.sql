-- 20262606000165_default_light_theme_all_roles.sql
-- Sets Light Mode as the explicit, persistent default theme across all roles in OHMployee.
-- Resolves automatic dark mode trigger when logging into other roles by changing user_settings
-- default from 'system' to 'light', updating all existing 'system' or NULL rows to 'light',
-- and updating handle_create_default_user_settings to initialize new profiles with 'light'.

-- §1. Update column default on public.user_settings
ALTER TABLE public.user_settings ALTER COLUMN theme_mode SET DEFAULT 'light';

-- §2. Update existing records with 'system' or NULL to 'light' (retaining explicit 'dark')
UPDATE public.user_settings
   SET theme_mode = 'light'
 WHERE theme_mode = 'system'
    OR theme_mode IS NULL;

-- §3. Update handle_create_default_user_settings to explicitly insert 'light'
CREATE OR REPLACE FUNCTION public.handle_create_default_user_settings()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO public.user_settings (user_id, theme_mode)
  VALUES (NEW.id, 'light')
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- §4. Backfill any user profiles missing user_settings records
INSERT INTO public.user_settings (user_id, theme_mode)
SELECT id, 'light' FROM public.users_profile
ON CONFLICT (user_id) DO NOTHING;
