-- ─────────────────────────────────────────────────────────────────────────────
-- 20260523100000_fix_user_management_backend.sql
-- User Management Backend Audit Fix
--
-- Fixes addressed:
--   §1  Add missing audit_action enum values used by User Management RPCs
--   §2  Fix set_user_active — cast CASE expression to ::audit_action
--   §3  Fix upsert_user_profile_and_scopes:
--         - Block Head Admin from creating new users (insert path)
--         - Add explicit RPC-level guard: cannot assign role at/above own level
--         - Cast CASE expression to ::audit_action
--   §4  Add archived_at + archived_by columns to users_profile (idempotent)
--   §5  Create fn_archive_user_account RPC (soft archive only)
--   §6  Create fn_log_password_reset_request RPC (RBAC check + audit)
--   §7  GRANT EXECUTE on new RPCs
--
-- Business rules enforced:
--   - Super Admin: full control
--   - Head Admin: may edit scopes, reset password, deactivate, archive
--   - Head Admin must NOT create users, assign SA/HA, escalate roles, hard-delete
--   - Self-deactivation / self-archive blocked (RPC guard + trg_enforce_user_hierarchy)
--   - Super Admin accounts cannot be archived/deactivated by Head Admin
--   - All destructive actions are soft only — no hard delete
--
-- Dependencies: none (self-contained; existing RPCs replaced via CREATE OR REPLACE)
-- Apply after: any migration that already applied set_user_active /
--              upsert_user_profile_and_scopes (20260508120000_p1_rpc_hardening)
--
-- Validation queries (manual, read-only):
--   V1: confirm enum values exist
--       SELECT enum_range(NULL::audit_action);
--   V2: confirm set_user_active compiles (no error = pass)
--       SELECT pg_get_functiondef('set_user_active(uuid,boolean)'::regprocedure);
--   V3: confirm upsert_user_profile_and_scopes compiles
--       SELECT pg_get_functiondef('upsert_user_profile_and_scopes(text,text,uuid,uuid[],uuid)'::regprocedure);
--   V4: confirm archived columns exist
--       SELECT column_name FROM information_schema.columns
--       WHERE table_name = 'users_profile' AND column_name IN ('archived_at','archived_by');
--   V5: confirm fn_archive_user_account exists
--       SELECT proname FROM pg_proc WHERE proname = 'fn_archive_user_account';
--   V6: confirm fn_log_password_reset_request exists
--       SELECT proname FROM pg_proc WHERE proname = 'fn_log_password_reset_request';
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- §1  Add missing audit_action enum values
--     ALTER TYPE ADD VALUE cannot run inside a transaction in PG < 12.
--     Supabase runs PG 15 — safe here. IF NOT EXISTS prevents re-run failures.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'ACTIVATE_USER';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'DEACTIVATE_USER';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'CREATE_USER';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'UPDATE_USER_ROLE';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'ARCHIVE_USER';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'RESET_PASSWORD_REQUEST';

-- ─────────────────────────────────────────────────────────────────────────────
-- §2  Fix set_user_active
--     Root cause: CASE expression returned text; no implicit text→audit_action cast.
--     Fix: explicit ::audit_action cast on the CASE result.
--     RBAC guards and last-SA guard are preserved unchanged.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_user_active(
  p_profile_id UUID,
  p_is_active  BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id    UUID;
  v_caller_level INT;
  v_target_name  TEXT;
  v_target_role  TEXT;
  v_old_state    BOOLEAN;
BEGIN
  v_caller_id := auth.uid();

  -- ── Auth ──────────────────────────────────────────────────────────────────
  SELECT r.role_level
    INTO v_caller_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = v_caller_id;

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch target ──────────────────────────────────────────────────────────
  SELECT up.full_name, r.role_name, up.is_active
    INTO v_target_name, v_target_role, v_old_state
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.id = p_profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user profile not found: %', p_profile_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Guard: self-action blocked ─────────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.users_profile
     WHERE id = p_profile_id AND auth_user_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'cannot change your own active status'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: Head Admin cannot deactivate a Super Admin ─────────────────────
  IF NOT p_is_active
     AND v_target_role IN ('Super Admin', 'superAdmin', 'super_admin')
     AND COALESCE(v_caller_level, 0) < 100 THEN
    RAISE EXCEPTION 'only Super Admin can deactivate another Super Admin'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: cannot deactivate the last active Super Admin ──────────────────
  IF NOT p_is_active AND v_target_role IN ('Super Admin', 'superAdmin', 'super_admin') THEN
    IF (
      SELECT COUNT(*) FROM public.users_profile up2
      JOIN public.roles r2 ON r2.id = up2.role_id
      WHERE r2.role_name IN ('Super Admin', 'superAdmin', 'super_admin')
        AND up2.is_active = TRUE
        AND up2.id <> p_profile_id
    ) = 0 THEN
      RAISE EXCEPTION 'cannot deactivate the last active Super Admin'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── Apply ─────────────────────────────────────────────────────────────────
  UPDATE public.users_profile
     SET is_active  = p_is_active,
         updated_at = NOW()
   WHERE id = p_profile_id;

  -- ── Audit — fixed: explicit ::audit_action cast ───────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    v_caller_id,
    'User Management',
    (CASE WHEN p_is_active THEN 'ACTIVATE_USER' ELSE 'DEACTIVATE_USER' END)::audit_action,
    p_profile_id,
    jsonb_build_object('is_active', v_old_state, 'full_name', v_target_name),
    jsonb_build_object('is_active', p_is_active, 'full_name', v_target_name)
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §3  Fix upsert_user_profile_and_scopes
--     Fixes:
--       (a) Block Head Admin from creating new users (insert path)
--       (b) Add explicit role-level escalation guard at RPC level
--           (defense-in-depth over trg_enforce_user_hierarchy)
--       (c) Cast CASE expression to ::audit_action
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.upsert_user_profile_and_scopes(
  p_full_name   TEXT,
  p_email       TEXT,
  p_role_id     UUID,
  p_group_ids   UUID[],
  p_profile_id  UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_level  INT;
  v_caller_role   TEXT;
  v_target_level  INT;
  v_target_role   TEXT;
  v_profile_id    UUID := p_profile_id;
  v_gid           UUID;
  v_old_data      jsonb;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────────────────────
  SELECT r.role_level, r.role_name
    INTO v_caller_level, v_caller_role
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard (a): Head Admin cannot create new users ─────────────────────────
  IF p_profile_id IS NULL AND v_caller_level < 100 THEN
    RAISE EXCEPTION 'only Super Admin can create new user accounts'
      USING ERRCODE = '42501';
  END IF;

  -- ── Resolve target role ───────────────────────────────────────────────────
  SELECT role_name, role_level
    INTO v_target_role, v_target_level
    FROM public.roles
   WHERE id = p_role_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'role not found: %', p_role_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Guard (b): cannot assign a role at or above own level ─────────────────
  --   Super Admin (100) can assign any role including other Super Admins.
  --   Head Admin (90) can assign roles with level < 90 only.
  IF COALESCE(v_target_level, 0) >= COALESCE(v_caller_level, 0)
     AND v_caller_level < 100 THEN
    RAISE EXCEPTION 'cannot assign a role at or above your own level (your level: %, role level: %)',
      v_caller_level, v_target_level
      USING ERRCODE = '42501';
  END IF;

  -- ── Update or insert users_profile ────────────────────────────────────────
  IF v_profile_id IS NOT NULL THEN
    SELECT to_jsonb(up.*)
      INTO v_old_data
      FROM public.users_profile up
     WHERE up.id = v_profile_id;

    UPDATE public.users_profile
       SET full_name  = p_full_name,
           email      = p_email,
           role_id    = p_role_id,
           updated_at = NOW()
     WHERE id = v_profile_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'user profile not found: %', v_profile_id
        USING ERRCODE = 'P0002';
    END IF;
  ELSE
    -- Only reachable by Super Admin (guard (a) above)
    INSERT INTO public.users_profile (full_name, email, role_id, is_active)
    VALUES (p_full_name, p_email, p_role_id, TRUE)
    RETURNING id INTO v_profile_id;
  END IF;

  -- ── Replace scopes ────────────────────────────────────────────────────────
  DELETE FROM public.user_scopes WHERE user_id = v_profile_id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    INSERT INTO public.user_scopes (user_id, group_id)
    VALUES (v_profile_id, v_gid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- ── Audit — fixed: explicit ::audit_action cast ───────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    'User Management',
    (CASE WHEN p_profile_id IS NULL THEN 'CREATE_USER' ELSE 'UPDATE_USER_ROLE' END)::audit_action,
    v_profile_id,
    v_old_data,
    jsonb_build_object(
      'full_name', p_full_name,
      'email',     p_email,
      'role_id',   p_role_id,
      'role_name', v_target_role,
      'group_ids', p_group_ids
    )
  );

  RETURN v_profile_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §4  Add archived_at + archived_by to users_profile (idempotent)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.users_profile
  ADD COLUMN IF NOT EXISTS archived_at  TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS archived_by  UUID        DEFAULT NULL
    REFERENCES auth.users(id) ON DELETE SET NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- §5  fn_archive_user_account
--     Soft-archives a user account. Distinct from deactivation:
--       - Sets is_active = false
--       - Stamps archived_at + archived_by
--       - Emits audit log entry with action = 'ARCHIVE_USER'
--     Business rules enforced:
--       - Caller must be Head Admin or higher
--       - Head Admin cannot archive a Super Admin
--       - Cannot archive own account (self-archive)
--       - Cannot archive the last active Super Admin (guarded via SA check above)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_archive_user_account(
  p_profile_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id    UUID;
  v_caller_level INT;
  v_target_name  TEXT;
  v_target_role  TEXT;
  v_target_active BOOLEAN;
BEGIN
  v_caller_id := auth.uid();

  -- ── Auth ──────────────────────────────────────────────────────────────────
  SELECT r.role_level
    INTO v_caller_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = v_caller_id;

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch target ──────────────────────────────────────────────────────────
  SELECT up.full_name, r.role_name, up.is_active
    INTO v_target_name, v_target_role, v_target_active
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.id = p_profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user profile not found: %', p_profile_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Guard: self-archive blocked ───────────────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.users_profile
     WHERE id = p_profile_id AND auth_user_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'cannot archive your own account'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: Head Admin cannot archive a Super Admin ────────────────────────
  IF v_target_role IN ('Super Admin', 'superAdmin', 'super_admin')
     AND v_caller_level < 100 THEN
    RAISE EXCEPTION 'only Super Admin can archive another Super Admin account'
      USING ERRCODE = '42501';
  END IF;

  -- ── Apply (soft archive only — no hard delete) ────────────────────────────
  UPDATE public.users_profile
     SET is_active   = FALSE,
         archived_at = NOW(),
         archived_by = v_caller_id,
         updated_at  = NOW()
   WHERE id = p_profile_id;

  -- ── Audit ─────────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, old_data, new_data)
  VALUES (
    v_caller_id,
    'User Management',
    'ARCHIVE_USER'::audit_action,
    p_profile_id,
    jsonb_build_object('is_active', v_target_active, 'full_name', v_target_name),
    jsonb_build_object('is_active', FALSE, 'archived_at', NOW(), 'full_name', v_target_name)
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §6  fn_log_password_reset_request
--     RBAC gate + audit log for password reset requests.
--     Flutter calls this first; on success calls supabase.auth.resetPasswordForEmail().
--     The actual email delivery is handled by Supabase Auth — no service role needed.
--     Business rules:
--       - Caller must be Head Admin or higher
--       - Head Admin cannot trigger reset for a Super Admin
--       - Cannot trigger reset for own account (user resets their own via auth flow)
--     Returns: the target user's email so Flutter can call resetPasswordForEmail()
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_log_password_reset_request(
  p_profile_id UUID
)
RETURNS TEXT   -- returns target email
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id    UUID;
  v_caller_level INT;
  v_target_name  TEXT;
  v_target_email TEXT;
  v_target_role  TEXT;
BEGIN
  v_caller_id := auth.uid();

  -- ── Auth ──────────────────────────────────────────────────────────────────
  SELECT r.role_level
    INTO v_caller_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.auth_user_id = v_caller_id;

  IF COALESCE(v_caller_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  -- ── Fetch target ──────────────────────────────────────────────────────────
  SELECT up.full_name, up.email, r.role_name
    INTO v_target_name, v_target_email, v_target_role
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.id = p_profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user profile not found: %', p_profile_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_target_email IS NULL OR trim(v_target_email) = '' THEN
    RAISE EXCEPTION 'target user has no email address registered'
      USING ERRCODE = '22023';
  END IF;

  -- ── Guard: self-reset blocked via this flow ───────────────────────────────
  IF EXISTS (
    SELECT 1 FROM public.users_profile
     WHERE id = p_profile_id AND auth_user_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'use your own profile settings to reset your password'
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: Head Admin cannot reset Super Admin password ───────────────────
  IF v_target_role IN ('Super Admin', 'superAdmin', 'super_admin')
     AND v_caller_level < 100 THEN
    RAISE EXCEPTION 'only Super Admin can trigger a password reset for another Super Admin'
      USING ERRCODE = '42501';
  END IF;

  -- ── Audit ─────────────────────────────────────────────────────────────────
  INSERT INTO public.audit_logs (actor_id, module, action, record_id, new_data)
  VALUES (
    v_caller_id,
    'User Management',
    'RESET_PASSWORD_REQUEST'::audit_action,
    p_profile_id,
    jsonb_build_object('full_name', v_target_name, 'email', v_target_email)
  );

  RETURN v_target_email;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §7  Grant EXECUTE on new RPCs
-- ─────────────────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.set_user_active(UUID, BOOLEAN)                          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.upsert_user_profile_and_scopes(TEXT, TEXT, UUID, UUID[], UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_archive_user_account(UUID)                            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_log_password_reset_request(UUID)                      FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.set_user_active(UUID, BOOLEAN)                          TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_user_profile_and_scopes(TEXT, TEXT, UUID, UUID[], UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_archive_user_account(UUID)                            TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_log_password_reset_request(UUID)                      TO authenticated;
