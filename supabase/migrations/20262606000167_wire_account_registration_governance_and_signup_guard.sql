-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: 20262606000167_wire_account_registration_governance_and_signup_guard.sql
-- Module: Auth / Admin Tools / Safespace
-- Description:
--   1. Wires fn_check_governance_control('account_registration') into handle_new_auth_user()
--      so database-level user creation strictly respects the Admin Tools toggle.
--   2. Adds public.is_account_signup_enabled() helper RPC and appends is_registration_enabled
--      to get_request_account_signup_options() for lightweight unauthenticated client queries.
--   3. Explicitly ensures anon and authenticated hold EXECUTE grants on fn_check_governance_control
--      and is_account_signup_enabled.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Lightweight public RPC for checking sign-up availability ───────────────
CREATE OR REPLACE FUNCTION public.is_account_signup_enabled()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.fn_check_governance_control('account_registration');
$$;

GRANT EXECUTE ON FUNCTION public.is_account_signup_enabled() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_check_governance_control(text) TO anon, authenticated;

COMMENT ON FUNCTION public.is_account_signup_enabled() IS
  'Lightweight check for web and mobile auth flows to check if account sign-up is enabled in Admin Tools.';


-- ── 2. Update get_request_account_signup_options() ─────────────────────────────
-- Append is_registration_enabled to options payload (100% backward compatible with mobile)
CREATE OR REPLACE FUNCTION public.get_request_account_signup_options()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_roles    jsonb;
  v_groups   jsonb;
  v_accounts jsonb;
BEGIN
  -- Requestable roles: exclude by role_level (SA=100, HA=90).
  -- Ordered by role_level DESC (hierarchy) then role_name ASC (alpha fallback).
  SELECT jsonb_agg(
    jsonb_build_object('id', r.id, 'role_name', r.role_name)
    ORDER BY r.role_level DESC, r.role_name ASC
  )
  INTO v_roles
  FROM public.roles r
  WHERE r.role_level < 90;

  -- Groups (all groups — groups table has no is_active column).
  SELECT jsonb_agg(
    jsonb_build_object('id', g.id, 'group_name', g.group_name)
    ORDER BY g.group_name
  )
  INTO v_groups
  FROM public.groups g;

  -- Active, non-pool accounts only. id + account_name + group_id only.
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',           a.id,
      'account_name', a.account_name,
      'group_id',     a.group_id
    )
    ORDER BY a.account_name
  )
  INTO v_accounts
  FROM public.accounts a
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false;

  RETURN jsonb_build_object(
    'roles',                   COALESCE(v_roles,    '[]'::jsonb),
    'groups',                  COALESCE(v_groups,   '[]'::jsonb),
    'accounts',                COALESCE(v_accounts, '[]'::jsonb),
    'is_registration_enabled', public.fn_check_governance_control('account_registration')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_request_account_signup_options() TO anon, authenticated;


-- ── 3. Update handle_new_auth_user() with governance check ───────────────────
-- Surgical copy from 20260721000000_populate_position_dropdown_exclude_by_level.sql
-- adding governance control gate before creating account request row.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_meta              JSONB := NEW.raw_user_meta_data;
  v_last_name         TEXT;
  v_first_name        TEXT;
  v_middle_name       TEXT;
  v_mobile_raw        TEXT;
  v_mobile_norm       TEXT;
  v_full_name         TEXT;
  v_requested_role_id UUID;
  v_request_id        UUID;
  v_gid               TEXT;
  v_aid               TEXT;
  v_notes             TEXT;
  v_role_level        INTEGER;
BEGIN
  -- Idempotency guard
  IF EXISTS (
    SELECT 1 FROM public.account_requests WHERE auth_user_id = NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  -- Governance control check: is account registration enabled?
  IF NOT public.fn_check_governance_control('account_registration') THEN
    RAISE EXCEPTION 'account_registration_disabled: User account registration is currently disabled by administrator.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Extract metadata
  v_last_name   := NULLIF(TRIM(COALESCE(v_meta->>'last_name',  '')), '');
  v_first_name  := NULLIF(TRIM(COALESCE(v_meta->>'first_name', '')), '');
  v_middle_name := public.fn_coalesce_middle_name(v_meta->>'middle_name');
  v_mobile_raw  := NULLIF(TRIM(COALESCE(v_meta->>'mobile_number', '')), '');
  v_requested_role_id := NULLIF(TRIM(COALESCE(v_meta->>'requested_role_id', '')), '')::UUID;

  -- Extract remarks/notes (support both keys for robust compatibility)
  v_notes := COALESCE(
               NULLIF(TRIM(v_meta->>'notes'), ''),
               NULLIF(TRIM(v_meta->>'remarks'), '')
             );

  -- Enforce requested role is not null
  IF v_requested_role_id IS NULL THEN
    RAISE EXCEPTION 'requested_role_required: requested_role_id must be provided'
      USING ERRCODE = '23502';
  END IF;

  -- Enforce role_level < 90 (blocks SA/HA at insert time)
  SELECT role_level INTO v_role_level
  FROM public.roles
  WHERE id = v_requested_role_id;

  IF v_role_level IS NULL THEN
    RAISE EXCEPTION 'requested_role_not_found: role_id % does not exist', v_requested_role_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_role_level >= 90 THEN
    RAISE EXCEPTION 'restricted_role: Super Admin and Head Admin roles cannot be self-requested'
      USING ERRCODE = '42501';
  END IF;

  -- Enforce group scope is not empty
  IF NOT (v_meta ? 'group_ids') OR jsonb_typeof(v_meta->'group_ids') <> 'array' OR jsonb_array_length(v_meta->'group_ids') = 0 THEN
    RAISE EXCEPTION 'group_scope_required: at least one group_id must be provided'
      USING ERRCODE = '23502';
  END IF;

  -- full_name: prefer metadata field, fall back to first+last composition
  v_full_name := COALESCE(
    NULLIF(TRIM(v_meta->>'full_name'), ''),
    NULLIF(TRIM(CONCAT_WS(' ', v_first_name, v_last_name)), ''),
    'No Name'
  );

  -- Normalize mobile silently — invalid format is stored as NULL at signup
  IF v_mobile_raw IS NOT NULL THEN
    BEGIN
      v_mobile_norm := public.fn_normalize_ph_mobile(v_mobile_raw);
    EXCEPTION WHEN OTHERS THEN
      v_mobile_norm := NULL;
    END;
  END IF;

  -- Generate request ID
  v_request_id := gen_random_uuid();

  -- Insert pending account request (role_level has already been validated)
  INSERT INTO public.account_requests (
    id,
    auth_user_id,
    email,
    full_name,
    last_name,
    first_name,
    middle_name,
    mobile_number,
    requested_role_id,
    status,
    notes
  )
  VALUES (
    v_request_id,
    NEW.id,
    NEW.email,
    v_full_name,
    v_last_name,
    v_first_name,
    v_middle_name,
    v_mobile_norm,
    v_requested_role_id,
    'pending'::public.account_request_status,
    v_notes
  );

  -- Insert group scopes
  FOR v_gid IN SELECT jsonb_array_elements_text(v_meta->'group_ids') LOOP
    INSERT INTO public.account_request_group_scopes (account_request_id, group_id)
    VALUES (v_request_id, v_gid::UUID)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Insert account scopes (if any)
  IF v_meta ? 'account_ids' AND jsonb_typeof(v_meta->'account_ids') = 'array' THEN
    FOR v_aid IN SELECT jsonb_array_elements_text(v_meta->'account_ids') LOOP
      INSERT INTO public.account_request_account_scopes (account_request_id, account_id)
      VALUES (v_request_id, v_aid::UUID)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'handle_new_auth_user FAILED | user=% email=% sqlstate=% msg=%',
      NEW.id, NEW.email, SQLSTATE, SQLERRM;
    RAISE;
END;
$$;
