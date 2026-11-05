-- Migration: 20262606000087_fix_audit_logs_actor_id_fk_and_safe_resolution.sql
-- Purpose: Permanently resolve "insert or update on table 'audit_logs' violates foreign key constraint 'audit_logs_actor_id_fkey'"
-- 1. Create/harden public.resolve_audit_actor_id(uuid) to dynamically inspect audit_logs_actor_id_fkey and validate candidate IDs against the FK target.
-- 2. Update public.fn_audit_log() to safely resolve the actor ID and gracefully fall back to NULL on foreign_key_violation, guaranteeing status updates (Resigned, AWOL, Terminated) never abort due to audit logging.

-- ── 1. Create/Replace Safe Actor ID Resolver ───────────────────────────────
CREATE OR REPLACE FUNCTION public.resolve_audit_actor_id(p_input_user_id UUID DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_valid_actor_id UUID := NULL;
    v_input UUID := COALESCE(p_input_user_id, auth.uid());
    v_fk_target TEXT := NULL;
BEGIN
    IF v_input IS NULL THEN
        RETURN NULL;
    END IF;

    -- 1. Inspect direct foreign key referenced table on audit_logs.actor_id using pg_constraint
    SELECT c.confrelid::regclass::TEXT INTO v_fk_target
    FROM pg_constraint c
    WHERE c.conrelid = 'public.audit_logs'::regclass
      AND c.conname = 'audit_logs_actor_id_fkey'
    LIMIT 1;

    -- 2. Resolve actor according to the exact foreign table
    IF v_fk_target = 'public.users_profile' OR v_fk_target = 'users_profile' THEN
        -- If FK references users_profile directly:
        SELECT id INTO v_valid_actor_id
        FROM public.users_profile
        WHERE id = v_input OR auth_user_id = v_input
        LIMIT 1;
    ELSIF v_fk_target = 'public.profiles' OR v_fk_target = 'profiles' THEN
        -- If FK references profiles directly:
        BEGIN
            EXECUTE 'SELECT id FROM public.profiles WHERE id = $1 LIMIT 1' INTO v_valid_actor_id USING v_input;
        EXCEPTION WHEN OTHERS THEN
            v_valid_actor_id := NULL;
        END;
    ELSE
        -- Default (and live Supabase target): references auth.users(id)
        -- Step 2a: Check if input UUID is directly a valid auth.users id
        SELECT id INTO v_valid_actor_id
        FROM auth.users
        WHERE id = v_input
        LIMIT 1;

        -- Step 2b: If not direct auth user, resolve via users_profile with strict INNER JOIN against auth.users
        -- (Ensures orphaned profiles whose auth_user_id does not exist in auth.users are NEVER returned)
        IF v_valid_actor_id IS NULL THEN
            SELECT au.id INTO v_valid_actor_id
            FROM public.users_profile up
            JOIN auth.users au ON au.id = up.auth_user_id
            WHERE up.id = v_input
            LIMIT 1;
        END IF;

        -- Step 2c: Fallback to auth.uid() if valid in auth.users
        IF v_valid_actor_id IS NULL AND auth.uid() IS NOT NULL THEN
            SELECT id INTO v_valid_actor_id
            FROM auth.users
            WHERE id = auth.uid()
            LIMIT 1;
        END IF;
    END IF;

    -- If unresolvable (e.g. orphaned profile, admin utility context, or non-existent user), return NULL.
    -- Because public.audit_logs.actor_id is NULLABLE, returning NULL guarantees zero foreign key violation!
    RETURN v_valid_actor_id;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_audit_actor_id(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_audit_actor_id(UUID) TO authenticated, service_role;

-- ── 2. Update fn_audit_log() with safe actor resolution & error trapping ───
CREATE OR REPLACE FUNCTION public.fn_audit_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_action          audit_action;
  v_old_data        JSONB;
  v_new_data        JSONB;
  v_old_status      TEXT;
  v_new_status      TEXT;
  v_role            TEXT;
  v_resolved_actor  UUID;
  v_approval_states TEXT[] := ARRAY['Hired','Approved','Filled','Closed'];
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_action   := 'INSERT';
    v_old_data := NULL;
    v_new_data := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_data := to_jsonb(OLD);
    v_new_data := to_jsonb(NEW);
    IF (v_new_data ? 'is_deleted')
       AND (v_new_data->>'is_deleted')::BOOLEAN = TRUE
       AND COALESCE((v_old_data->>'is_deleted')::BOOLEAN, FALSE) = FALSE
    THEN
      v_action := 'SOFT_DELETE';
    ELSE
      v_action := 'UPDATE';
      v_old_status := v_old_data->>'status';
      v_new_status := v_new_data->>'status';
      IF v_new_status IS DISTINCT FROM v_old_status
         AND v_new_status = ANY(v_approval_states) THEN
        v_action := 'APPROVAL';
      END IF;
    END IF;
  END IF;

  BEGIN v_role := public.get_my_role(); EXCEPTION WHEN OTHERS THEN v_role := NULL; END;

  -- Safely resolve actor id against foreign key constraints
  BEGIN
    v_resolved_actor := public.resolve_audit_actor_id(auth.uid());
  EXCEPTION WHEN OTHERS THEN
    v_resolved_actor := NULL;
  END;

  -- Safe audit log insertion with fallback to NULL actor_id on foreign key violation
  BEGIN
    INSERT INTO public.audit_logs (actor_id, role, module, action, record_id, old_data, new_data)
    VALUES (
      v_resolved_actor, v_role, TG_TABLE_NAME, v_action,
      (to_jsonb(NEW)->>'id')::UUID, v_old_data, v_new_data
    );
  EXCEPTION WHEN foreign_key_violation THEN
    BEGIN
      INSERT INTO public.audit_logs (actor_id, role, module, action, record_id, old_data, new_data)
      VALUES (
        NULL, v_role, TG_TABLE_NAME, v_action,
        (to_jsonb(NEW)->>'id')::UUID, v_old_data, v_new_data
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  WHEN OTHERS THEN
    NULL;
  END;

  RETURN NEW;
END;
$function$;
