-- ─────────────────────────────────────────────────────────────────────────────
-- 20260605000000_add_font_family_to_user_settings.sql
-- Backend Architecture for App Settings Font Family Selection
-- ─────────────────────────────────────────────────────────────────────────────

-- §1. Add font_family column to user_settings table
ALTER TABLE public.user_settings ADD COLUMN IF NOT EXISTS font_family TEXT NOT NULL DEFAULT 'Inter';

-- §2. Add check constraint to ensure only valid font families can be stored
ALTER TABLE public.user_settings DROP CONSTRAINT IF EXISTS chk_font_family;
ALTER TABLE public.user_settings ADD CONSTRAINT chk_font_family CHECK (font_family IN ('Inter', 'SF Pro', 'Helvetica Neue', 'Plus Jakarta Sans', 'Manrope', 'System Default'));
