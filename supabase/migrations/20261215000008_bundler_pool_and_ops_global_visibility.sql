-- Migration: 20261215000008_bundler_pool_and_ops_global_visibility.sql
-- Goal:
--   1. Ensure pool position columns exist on positions table (idempotent with 007).
--   2. Seed Commando, Reliever, Seasonal, Bundler as pool positions.
--   3. Seed Bundler Pool into workforce_pool_types + vcode sequence.
--   4. Fix Ops GLOBAL Workforce visibility: update plantilla_read_scoped to
--      allow Ops (role level 40–70) to see is_pool_employee = true employees.
--
-- Safe to run even if migration 007 was already applied — all steps are idempotent.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Ensure pool position marker columns exist
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.positions
  ADD COLUMN IF NOT EXISTS is_pool_position boolean DEFAULT false NOT NULL,
  ADD COLUMN IF NOT EXISTS pool_sort_order  int;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Seed the four canonical pool positions
--    Uses upsert pattern: update if row exists, insert if not.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_id uuid;
BEGIN
  -- Commando
  SELECT id INTO v_id FROM public.positions
    WHERE LOWER(TRIM(position_name)) = 'commando' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.positions (position_name, is_active, is_pool_position, pool_sort_order)
    VALUES ('Commando', true, true, 1);
  ELSE
    UPDATE public.positions
       SET is_pool_position = true, pool_sort_order = 1
     WHERE id = v_id;
  END IF;

  -- Reliever
  SELECT id INTO v_id FROM public.positions
    WHERE LOWER(TRIM(position_name)) = 'reliever' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.positions (position_name, is_active, is_pool_position, pool_sort_order)
    VALUES ('Reliever', true, true, 2);
  ELSE
    UPDATE public.positions
       SET is_pool_position = true, pool_sort_order = 2
     WHERE id = v_id;
  END IF;

  -- Seasonal
  SELECT id INTO v_id FROM public.positions
    WHERE LOWER(TRIM(position_name)) = 'seasonal' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.positions (position_name, is_active, is_pool_position, pool_sort_order)
    VALUES ('Seasonal', true, true, 3);
  ELSE
    UPDATE public.positions
       SET is_pool_position = true, pool_sort_order = 3
     WHERE id = v_id;
  END IF;

  -- Bundler (new)
  SELECT id INTO v_id FROM public.positions
    WHERE LOWER(TRIM(position_name)) = 'bundler' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.positions (position_name, is_active, is_pool_position, pool_sort_order)
    VALUES ('Bundler', true, true, 4);
  ELSE
    UPDATE public.positions
       SET is_pool_position = true, pool_sort_order = 4
     WHERE id = v_id;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Seed Bundler Pool into workforce_pool_types
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_type_id uuid;
BEGIN
  SELECT id INTO v_type_id
  FROM public.workforce_pool_types
  WHERE code = 'BUN'
  LIMIT 1;

  IF v_type_id IS NULL THEN
    INSERT INTO public.workforce_pool_types
      (code, name, vcode_prefix, is_active, sort_order)
    VALUES
      ('BUN', 'Bundler Pool', 'BUN-GHQ', true, 4);
  ELSE
    UPDATE public.workforce_pool_types
    SET name = 'Bundler Pool', is_active = true, sort_order = 4
    WHERE id = v_type_id;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Ensure Bundler Pool vcode sequence entry exists
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.workforce_pool_vcode_sequences (prefix, last_val)
VALUES ('BUN-GHQ', 0)
ON CONFLICT (prefix) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Fix Ops GLOBAL Workforce visibility
--    Previous policy (migration 006) allowed pool employees visible to role
--    levels 20 (Recruitment), 30 (Encoder), and >=90 (Admin) only.
--    Ops users (role level 40–70) were excluded, making the Moses HQ pool
--    screen show empty counts for all Ops users (GLOBAL Workforce invisible).
--    Fix: add role level 40–70 (Ops) to the pool employee visibility condition.
--    This does NOT change pool VACANCY visibility in the Vacancy module (that
--    is controlled by vacancies_read_scoped which is unchanged).
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "plantilla_read_scoped" ON public.plantilla;

CREATE POLICY "plantilla_read_scoped" ON "public"."plantilla"
FOR SELECT TO authenticated
USING (
  public.i_can_view_plantilla()
  AND (
    public.i_have_full_access()
    OR (account = ANY (public.get_my_allowed_accounts()))
    OR (
      is_pool_employee = true
      AND (
        public.get_my_role_level() = 20
        OR public.get_my_role_level() = 30
        OR public.get_my_role_level() >= 90
        OR (public.get_my_role_level() BETWEEN 40 AND 70)
      )
    )
  )
  AND (COALESCE(is_deleted, false) = false)
  AND ((deactivated_visible_until IS NULL) OR (deactivated_visible_until > now()))
);
