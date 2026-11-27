-- Allow Super Admin (role_level >= 100) to modify, reactivate, and promote/assign
-- other users to Super Admin (role_level = 100), while preserving strict hierarchy
-- for all non-Super Admin roles and preserving the self-update guard.

CREATE OR REPLACE FUNCTION public.trg_enforce_user_hierarchy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor_level    INT;
  v_target_level   INT;
  v_new_role_level INT;
BEGIN
  -- Allow service-role operations (background jobs, migrations)
  -- auth.uid() is NULL when called via service role key
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  v_actor_level  := get_my_role_level();
  v_target_level := get_target_role_level(OLD.id);

  -- ── Self-update: only allow non-sensitive field changes ──────
  IF OLD.auth_user_id = auth.uid() THEN
    IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot change your own role.';
    END IF;
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot change your own role.';
    END IF;
    IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot change your own active status.';
    END IF;
    RETURN NEW;
  END IF;

  -- ── Editing another user: must strictly outrank target (unless Super Admin >= 100) ──
  IF v_actor_level IS NULL OR (v_actor_level < 100 AND v_actor_level <= COALESCE(v_target_level, 0)) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Insufficient role level to modify this user. '
      'Your level: %, Target level: %', v_actor_level, v_target_level;
  END IF;

  -- ── Role change: new role must be strictly below actor level (unless Super Admin >= 100) ─
  IF NEW.role_id IS DISTINCT FROM OLD.role_id THEN
    SELECT r.role_level INTO v_new_role_level
    FROM roles r WHERE r.id = NEW.role_id;

    IF v_new_role_level > v_actor_level OR (v_actor_level < 100 AND v_new_role_level >= v_actor_level) THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot assign a role at or above your own level. '
        'Your level: %, Attempted: %', v_actor_level, v_new_role_level;
    END IF;
  END IF;

  -- ── Email change: Super Admin only ───────────────────────────
  IF NEW.email IS DISTINCT FROM OLD.email THEN
    IF v_actor_level < 100 THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Only Super Admin can change a user email.';
    END IF;
  END IF;

  -- ── Reactivation guard ────────────────────────────────────────
  IF NEW.is_active = true AND OLD.is_active = false THEN
    IF v_actor_level < 100 AND v_actor_level <= COALESCE(v_target_level, 0) THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot reactivate a user at or above your role level.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
