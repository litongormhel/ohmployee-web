-- ─────────────────────────────────────────────────────────────────────────────
-- 20260603000000_fix_mobile_number_constraints.sql
-- Fix Account Request Approval Mobile Number Constraint Compatibility
-- ─────────────────────────────────────────────────────────────────────────────

-- §1  Update public.fn_normalize_ph_mobile helper function
--     Accepts 09XXXXXXXXX, +639XXXXXXXXX, and 639XXXXXXXXX formats.
--     Normalizes consistently to +639XXXXXXXXX format.
CREATE OR REPLACE FUNCTION public.fn_normalize_ph_mobile(p_raw TEXT)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
  PARALLEL SAFE
  SET search_path TO 'public'
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  IF p_raw IS NULL THEN
    RETURN NULL;
  END IF;

  v_clean := REGEXP_REPLACE(TRIM(p_raw), '[^0-9]', '', 'g');

  -- Accept 09XXXXXXXXX (11 digits starting with 09)
  IF v_clean ~ '^09[0-9]{9}$' THEN
    RETURN '+63' || SUBSTRING(v_clean, 2);  -- +639XXXXXXXXX
  END IF;

  -- Accept 639XXXXXXXXX or +639XXXXXXXXX (12 digits starting with 639)
  IF v_clean ~ '^639[0-9]{9}$' THEN
    RETURN '+' || v_clean;  -- +639XXXXXXXXX
  END IF;

  RAISE EXCEPTION 'invalid_ph_mobile: must be 09XXXXXXXXX or +639XXXXXXXXX format, got: %', p_raw
    USING ERRCODE = '22023';
END;
$$;


-- §2  Update chk_mobile_number CHECK constraint on public.users_profile
--     Enforces that if populated, the mobile number matches any of the standard PH formats.
ALTER TABLE public.users_profile
  DROP CONSTRAINT IF EXISTS chk_mobile_number,
  ADD CONSTRAINT chk_mobile_number CHECK (
    mobile_number IS NULL OR 
    mobile_number ~ '^09[0-9]{9}$' OR
    mobile_number ~ '^\+639[0-9]{9}$' OR
    mobile_number ~ '^639[0-9]{9}$'
  );


-- §3  Redefine public.update_own_profile RPC to normalize mobile number
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
  v_mobile_norm    TEXT;
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
    -- Verify format and normalize at database level (raises 22023 on failure)
    v_mobile_norm := public.fn_normalize_ph_mobile(p_mobile_number);

    UPDATE public.users_profile
       SET mobile_number = v_mobile_norm,
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


-- §4  Redefine public.approve_account_request_v2 RPC to propagate normalized mobile number
CREATE OR REPLACE FUNCTION public.approve_account_request_v2(
  p_request_id  UUID,
  p_role_id     UUID,
  p_scope_type  TEXT,
  p_group_ids   UUID[] DEFAULT ARRAY[]::UUID[],
  p_account_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
  RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_request              public.account_requests%ROWTYPE;
  v_profile_id           UUID;
  v_role_name            TEXT;
  v_caller_role_level    INT;
  v_gid                  UUID;
  v_aid                  UUID;
  v_invalid_account_count INT;
  v_mobile_norm          TEXT;
BEGIN
  -- Authorize approver
  SELECT r.role_level
  INTO v_caller_role_level
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.auth_user_id = auth.uid();

  IF COALESCE(v_caller_role_level, 0) < 90 THEN
    RAISE EXCEPTION 'unauthorized: requires Head Admin or higher'
      USING ERRCODE = '42501';
  END IF;

  IF p_scope_type NOT IN ('global', 'scoped', 'custom') THEN
    RAISE EXCEPTION 'invalid scope_type: %', p_scope_type
      USING ERRCODE = '22023';
  END IF;

  IF p_scope_type = 'scoped' AND COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'scoped access requires at least one group'
      USING ERRCODE = '22023';
  END IF;

  SELECT COUNT(*) INTO v_invalid_account_count
  FROM public.accounts a
  WHERE a.id = ANY(p_account_ids)
    AND NOT (a.group_id = ANY(p_group_ids));

  IF v_invalid_account_count > 0 THEN
    RAISE EXCEPTION 'one or more accounts do not belong to selected groups'
      USING ERRCODE = '22023';
  END IF;

  SELECT role_name INTO v_role_name
  FROM public.roles WHERE id = p_role_id;

  IF v_role_name IS NULL THEN
    RAISE EXCEPTION 'role not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_request
  FROM public.account_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'account request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.status <> 'pending'::account_request_status THEN
    RAISE EXCEPTION 'request already processed' USING ERRCODE = '22023';
  END IF;

  -- Normalize request mobile number
  v_mobile_norm := public.fn_normalize_ph_mobile(v_request.mobile_number);

  -- Upsert users_profile with identity fields from request
  INSERT INTO public.users_profile (
    auth_user_id,
    full_name,
    last_name,
    first_name,
    middle_name,
    email,
    role_id,
    mobile_number,
    directory_status,
    is_active
  )
  VALUES (
    v_request.auth_user_id,
    v_request.full_name,
    v_request.last_name,
    v_request.first_name,
    v_request.middle_name,
    v_request.email,
    p_role_id,
    v_mobile_norm,
    'Available',
    TRUE
  )
  ON CONFLICT (auth_user_id) DO UPDATE SET
    role_id          = EXCLUDED.role_id,
    full_name        = EXCLUDED.full_name,
    last_name        = COALESCE(EXCLUDED.last_name,    users_profile.last_name),
    first_name       = COALESCE(EXCLUDED.first_name,   users_profile.first_name),
    middle_name      = COALESCE(EXCLUDED.middle_name,  users_profile.middle_name),
    mobile_number    = public.fn_normalize_ph_mobile(COALESCE(EXCLUDED.mobile_number, users_profile.mobile_number)),
    directory_status = COALESCE(users_profile.directory_status, 'Available'),
    is_active        = TRUE,
    updated_at       = NOW()
  RETURNING id INTO v_profile_id;

  -- Rebuild user_scopes
  DELETE FROM public.user_scopes WHERE user_id = v_profile_id;

  IF p_scope_type <> 'global' THEN
    FOREACH v_gid IN ARRAY p_group_ids LOOP
      INSERT INTO public.user_scopes (user_id, group_id, account_id)
      VALUES (v_profile_id, v_gid, NULL)
      ON CONFLICT DO NOTHING;
    END LOOP;

    FOREACH v_aid IN ARRAY p_account_ids LOOP
      INSERT INTO public.user_scopes (user_id, group_id, account_id)
      SELECT v_profile_id, a.group_id, a.id
      FROM public.accounts a WHERE a.id = v_aid
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;

  -- Snapshot scope on request
  DELETE FROM public.account_request_group_scopes   WHERE account_request_id = p_request_id;
  DELETE FROM public.account_request_account_scopes WHERE account_request_id = p_request_id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    INSERT INTO public.account_request_group_scopes (account_request_id, group_id)
    VALUES (p_request_id, v_gid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  FOREACH v_aid IN ARRAY p_account_ids LOOP
    INSERT INTO public.account_request_account_scopes (account_request_id, account_id)
    VALUES (p_request_id, v_aid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Mark approved
  UPDATE public.account_requests
  SET
    status                   = 'approved'::account_request_status,
    approved_by              = auth.uid(),
    approved_at              = NOW(),
    reviewed_by              = auth.uid(),
    reviewed_at              = NOW(),
    assigned_role_id         = p_role_id,
    assigned_scope_type      = p_scope_type,
    assigned_groups_snapshot = to_jsonb(p_group_ids),
    assigned_accounts_snapshot = to_jsonb(p_account_ids),
    updated_at               = NOW()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success',       TRUE,
    'request_id',    p_request_id,
    'profile_id',    v_profile_id,
    'scope_type',    p_scope_type,
    'group_count',   COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0),
    'account_count', COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0)
  );
END;
$$;
