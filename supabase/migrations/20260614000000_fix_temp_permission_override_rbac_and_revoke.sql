-- Migration: 20260614000000_fix_temp_permission_override_rbac_and_revoke.sql
-- Ticket: OHM2026_1132 — Fix Temp Permission Override Backend RBAC and Revoke Scope Cleanup
--
-- Problems fixed:
--   1. PERMISSION_DENIED raised for Head Admin because trg_validate_temp_override() and
--      the RLS write policy both used is_super_admin() — Super Admin only.
--   2. Revoke left temp-added user_scopes intact, so the user retained access after revoke.
--
-- Changes:
--   PART 1 — Fix RLS policy temp_overrides_write_superadmin → allow SA + HA
--   PART 2 — Fix trg_validate_temp_override() trigger → use i_have_full_access()
--   PART 3 — Create grant_temp_permission_override() RPC (SA + HA; handles scopes + notification)
--   PART 4 — Create revoke_temp_permission_override() RPC (SA + HA; cleans up temp scopes)
--
-- Invariants preserved:
--   • Encoder cannot grant temp permissions (blocked by trigger + RLS)
--   • Head Admin cannot grant to another HA or SA (role-level guard in trigger)
--   • Permanent user_scopes (created before the override) are never deleted
--   • Scope removal is safe: skips groups covered by another active override
-- ─────────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: Fix RLS write policy on temp_permission_overrides
-- ═══════════════════════════════════════════════════════════════════════════
-- Old policy: is_super_admin() → level >= 100 only
-- New policy: i_have_full_access() → Super Admin OR Head Admin

DROP POLICY IF EXISTS "temp_overrides_write_superadmin" ON public.temp_permission_overrides;

CREATE POLICY "temp_overrides_write_admin"
  ON public.temp_permission_overrides
  AS PERMISSIVE
  FOR ALL
  TO public
  USING (public.i_have_full_access())
  WITH CHECK (public.i_have_full_access());


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: Fix trg_validate_temp_override trigger function
-- ═══════════════════════════════════════════════════════════════════════════
-- Changes:
--   • Auth guard changed from is_super_admin() to i_have_full_access()
--   • Added role-level guard: caller must outrank target user
--   • Added SECURITY DEFINER + SET search_path (was missing search_path)

CREATE OR REPLACE FUNCTION public.trg_validate_temp_override()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_my_level     int;
  v_target_level int;
BEGIN
  -- Cannot grant override to yourself
  IF NEW.user_id = public.get_my_profile_id() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot grant a permission override to yourself.';
  END IF;

  -- Only Super Admin or Head Admin can grant/modify temp permission overrides
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin or Head Admin can grant permission overrides.';
  END IF;

  -- Caller must outrank the target user (HA cannot grant to another HA or SA)
  v_my_level := public.get_my_role_level();
  SELECT r.role_level
    INTO v_target_level
    FROM public.users_profile up
    JOIN public.roles r ON r.id = up.role_id
   WHERE up.id = NEW.user_id;

  IF v_target_level IS NOT NULL AND v_target_level >= v_my_level THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot grant permission override to a user at or above your role level.';
  END IF;

  -- Expiry cap: maximum 30 days from now
  IF NEW.expires_at > NOW() + INTERVAL '30 days' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Override expiry cannot exceed 30 days from now.';
  END IF;

  RETURN NEW;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: grant_temp_permission_override() RPC
-- ═══════════════════════════════════════════════════════════════════════════
-- Wraps the raw insert + scope upsert + notification into one atomic RPC.
-- Flutter should call this instead of raw table inserts.
--
-- The trigger trg_validate_temp_override still fires on the INSERT and
-- re-validates auth — belt-and-suspenders, no double-coding needed.
--
-- Returns: uuid of the created temp_permission_overrides record.

CREATE OR REPLACE FUNCTION public.grant_temp_permission_override(
  p_user_id         uuid,
  p_additional_groups text[],
  p_expires_at      timestamptz,
  p_reason          text    DEFAULT NULL,
  p_notify_user     boolean DEFAULT true,
  p_granted_by      text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_override_id uuid;
  v_group_name  text;
  v_group_id    uuid;
BEGIN
  -- Auth: only SA or HA may call this RPC (trigger also validates on INSERT)
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin or Head Admin can grant permission overrides.';
  END IF;

  IF p_user_id = public.get_my_profile_id() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot grant a permission override to yourself.';
  END IF;

  IF p_expires_at IS NULL OR p_expires_at <= NOW() THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: expires_at must be a future timestamp.';
  END IF;

  -- Insert the override record (trigger re-validates before row is written)
  INSERT INTO public.temp_permission_overrides (
    user_id,
    granted_by,
    additional_groups,
    reason,
    expires_at,
    is_active,
    notify_user
  ) VALUES (
    p_user_id,
    COALESCE(p_granted_by, public.get_my_profile_id()::text),
    p_additional_groups,
    NULLIF(TRIM(COALESCE(p_reason, '')), ''),
    p_expires_at,
    true,
    COALESCE(p_notify_user, true)
  )
  RETURNING id INTO v_override_id;

  -- Upsert user_scopes for each additional group
  FOREACH v_group_name IN ARRAY p_additional_groups LOOP
    SELECT id INTO v_group_id
      FROM public.groups
     WHERE group_name = v_group_name
     LIMIT 1;

    IF v_group_id IS NOT NULL THEN
      INSERT INTO public.user_scopes (user_id, group_id)
      VALUES (p_user_id, v_group_id)
      ON CONFLICT (user_id, group_id, account_id) DO NOTHING;
    END IF;
  END LOOP;

  -- In-app notification to the recipient
  IF COALESCE(p_notify_user, true) THEN
    INSERT INTO public.notifications (
      recipient_role,
      title,
      message,
      reference_type,
      reference_id
    ) VALUES (
      'Encoder',
      '🔑 Temporary Access Granted',
      COALESCE(p_granted_by, 'An admin') || ' granted you temporary access to: '
        || array_to_string(p_additional_groups, ', ')
        || '. Expires: ' || to_char(p_expires_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') || '.',
      'temp_permission',
      p_user_id
    );
  END IF;

  RETURN v_override_id;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: revoke_temp_permission_override() RPC
-- ═══════════════════════════════════════════════════════════════════════════
-- Atomically revokes the override AND removes the temp-added user_scopes.
--
-- Scope removal safety rules:
--   A. Only removes scopes whose created_at >= override.created_at
--      (scopes that pre-dated the override are considered permanent and left intact).
--   B. Skips removal if the same group is covered by another active, non-expired
--      temp override for the same user (avoids breaking a parallel active grant).
--
-- Flutter should call this instead of a raw UPDATE on temp_permission_overrides.

CREATE OR REPLACE FUNCTION public.revoke_temp_permission_override(
  p_override_id uuid,
  p_revoked_by  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_target_user_id   uuid;
  v_additional_groups text[];
  v_override_created  timestamptz;
  v_group_name        text;
  v_group_id          uuid;
  v_covered_by_other  boolean;
BEGIN
  -- Auth: only SA or HA may revoke
  IF NOT public.i_have_full_access() THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin or Head Admin can revoke permission overrides.';
  END IF;

  -- Fetch override (must exist and be active)
  SELECT user_id, additional_groups, created_at
    INTO v_target_user_id, v_additional_groups, v_override_created
    FROM public.temp_permission_overrides
   WHERE id = p_override_id
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Override not found or already revoked.';
  END IF;

  -- Mark the override as revoked
  UPDATE public.temp_permission_overrides
     SET is_active   = false,
         revoked_at  = NOW(),
         revoked_by  = COALESCE(p_revoked_by, public.get_my_profile_id()::text)
   WHERE id = p_override_id;

  -- Remove temp-added user_scopes for each group in the override
  FOREACH v_group_name IN ARRAY v_additional_groups LOOP
    SELECT id INTO v_group_id
      FROM public.groups
     WHERE group_name = v_group_name
     LIMIT 1;

    CONTINUE WHEN v_group_id IS NULL;

    -- Safety B: check whether another active override still needs this group for the same user
    SELECT EXISTS (
      SELECT 1
        FROM public.temp_permission_overrides tpo
       WHERE tpo.user_id    = v_target_user_id
         AND tpo.id        != p_override_id
         AND tpo.is_active  = true
         AND tpo.expires_at > NOW()
         AND v_group_name   = ANY(tpo.additional_groups)
    ) INTO v_covered_by_other;

    CONTINUE WHEN v_covered_by_other;

    -- Safety A: only remove scope that was added at or after this override was created
    DELETE FROM public.user_scopes
     WHERE user_id   = v_target_user_id
       AND group_id  = v_group_id
       AND created_at >= v_override_created;
  END LOOP;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATION NOTES (run after migration)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Verify new RLS policy exists and old one is gone:
--    SELECT policyname, cmd, qual FROM pg_policies
--    WHERE tablename = 'temp_permission_overrides'
--    ORDER BY policyname;
--    Expected: temp_overrides_read_scoped (SELECT), temp_overrides_write_admin (ALL)
--    NOT expected: temp_overrides_write_superadmin

-- 2. Verify trigger still fires with updated function body:
--    SELECT routine_name, routine_definition
--    FROM information_schema.routines
--    WHERE routine_name = 'trg_validate_temp_override';

-- 3. Verify RPCs exist:
--    SELECT routine_name FROM information_schema.routines
--    WHERE routine_name IN (
--      'grant_temp_permission_override',
--      'revoke_temp_permission_override'
--    );
--    Expected: 2 rows

-- 4. Auth guard test (run as Encoder-level user):
--    SELECT grant_temp_permission_override(
--      p_user_id := '<some_uuid>',
--      p_additional_groups := ARRAY['Group 1'],
--      p_expires_at := NOW() + INTERVAL '7 days'
--    );
--    Expected: PERMISSION_DENIED exception

-- 5. Auth guard test (run as Head Admin):
--    SELECT grant_temp_permission_override(...);
--    Expected: returns uuid (success) — no longer PERMISSION_DENIED

-- 6. Revoke cleans scopes:
--    -- After grant, confirm user_scope exists
--    -- After revoke_temp_permission_override(override_id), confirm scope removed
--    SELECT * FROM user_scopes WHERE user_id = '<target_user_id>';
