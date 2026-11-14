-- =============================================================================
-- Migration: 20260721000000_populate_position_dropdown_exclude_by_level.sql
-- Prompt ID : ohm#7f3a9c2d
-- Purpose   : Make the "Requested Role" dropdown in the Request Account form
--             dynamically DB-driven.
--
-- Changes:
--   §1. get_request_account_signup_options — switch from hardcoded IN-list
--       allowlist to exclusion by role_level < 90, so new non-admin roles
--       appear automatically without any code change.
--
--   §2. handle_new_auth_user trigger — add role_level guard: reject any
--       submitted requested_role_id whose role_level >= 90 before the
--       account_requests row is even written.
--
--   §3. fn_enrich_account_request — upgrade role-exclusion check from
--       name-string matching to role_level < 90 (authoritative; immune to
--       name aliases like "SuperAdmin" vs "Super Admin").
--
-- No schema changes. Existing grants are preserved.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- §1. get_request_account_signup_options
--     Switch: WHERE role_name IN (...) → WHERE role_level < 90
--     Ordering: role_level DESC, role_name ASC (logical hierarchy + alpha fallback)
--     Returns: id, role_name (same shape as before — no Flutter model change)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_request_account_signup_options()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
/*
  Intentionally public-safe.
  This RPC is called unauthenticated by the Request Account screen to populate
  role/scope selection dropdowns. It exposes only non-sensitive lookup data:
    - All requestable roles (id + role_name only), ordered by role hierarchy
    - Active groups (id + group_name only)
    - Active non-pool accounts (id + account_name + group_id only)

  Exclusion rule: roles with role_level >= 90 (Super Admin = 100, Head Admin = 90)
  are never returned, regardless of what names exist in the roles table.
  Using role_level (RBAC source of truth) is stronger than name-string matching
  because it is immune to aliases, typos, and future renames.

  New non-admin roles added to the DB will appear automatically.
*/
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
    'roles',    COALESCE(v_roles,    '[]'::jsonb),
    'groups',   COALESCE(v_groups,   '[]'::jsonb),
    'accounts', COALESCE(v_accounts, '[]'::jsonb)
  );
END;
$$;

-- Preserve existing grants (anon = pre-login Request Account form).
GRANT EXECUTE ON FUNCTION public.get_request_account_signup_options() TO anon;
GRANT EXECUTE ON FUNCTION public.get_request_account_signup_options() TO authenticated;

COMMENT ON FUNCTION public.get_request_account_signup_options IS
  'ohm#7f3a9c2d: Dynamic exclusion by role_level < 90 (was: IN-list allowlist). '
  'New non-admin roles auto-appear. SA/HA excluded by RBAC level, not name string.';


-- -----------------------------------------------------------------------------
-- §2. handle_new_auth_user — add role_level guard before inserting row
--     Rejects SA/HA role_id at the trigger level so no bad row is ever written.
-- -----------------------------------------------------------------------------
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

  -- ── ohm#7f3a9c2d: Enforce role_level < 90 (blocks SA/HA at insert time) ──
  -- Look up role_level; reject if the role doesn't exist or is admin-tier.
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
  -- ─────────────────────────────────────────────────────────────────────────

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
  -- (fn_enrich_account_request will validate strictly later)
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


-- -----------------------------------------------------------------------------
-- §3. fn_enrich_account_request — upgrade role exclusion from name-string
--     matching to role_level < 90 (authoritative; immune to name aliases).
--     Signature unchanged (8 params): no Flutter call-site changes needed.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_enrich_account_request(TEXT, TEXT, TEXT, TEXT, UUID, UUID[], UUID[], TEXT);

CREATE OR REPLACE FUNCTION public.fn_enrich_account_request(
  p_last_name         TEXT,
  p_first_name        TEXT,
  p_middle_name       TEXT     DEFAULT NULL,
  p_mobile_number     TEXT     DEFAULT NULL,
  p_requested_role_id UUID     DEFAULT NULL,
  p_group_ids         UUID[]   DEFAULT ARRAY[]::UUID[],
  p_account_ids       UUID[]   DEFAULT ARRAY[]::UUID[],
  p_notes             TEXT     DEFAULT NULL
)
  RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_request        public.account_requests%ROWTYPE;
  v_mobile_norm    TEXT;
  v_role_level     INTEGER;
  v_role_upper     TEXT;
  v_gid            UUID;
  v_aid            UUID;
  v_dup_count      INT;
BEGIN
  -- ── 1. Caller must be authenticated ──────────────────────────────────────
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  -- ── 2. Governance gate ───────────────────────────────────────────────────
  PERFORM public.fn_assert_governance_enabled('account_registration');

  -- ── 3. Load and lock own pending request ─────────────────────────────────
  SELECT * INTO v_request
  FROM public.account_requests
  WHERE auth_user_id = auth.uid()
    AND status = 'pending'::public.account_request_status
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no pending account request found for caller'
      USING ERRCODE = 'P0002';
  END IF;

  -- ── 4. Validate required name fields ─────────────────────────────────────
  IF NULLIF(TRIM(p_last_name),  '') IS NULL THEN
    RAISE EXCEPTION 'last_name is required' USING ERRCODE = '23502';
  END IF;
  IF NULLIF(TRIM(p_first_name), '') IS NULL THEN
    RAISE EXCEPTION 'first_name is required' USING ERRCODE = '23502';
  END IF;

  -- ── 5. Mobile normalization & duplicate check ─────────────────────────────
  IF p_mobile_number IS NOT NULL AND TRIM(p_mobile_number) <> '' THEN
    v_mobile_norm := public.fn_normalize_ph_mobile(p_mobile_number);

    SELECT COUNT(*) INTO v_dup_count
    FROM public.account_requests
    WHERE mobile_number = v_mobile_norm
      AND id <> v_request.id
      AND status <> 'rejected'::public.account_request_status;

    IF v_dup_count > 0 THEN
      RAISE EXCEPTION 'mobile_number_already_registered: % is already in use', v_mobile_norm
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- ── 6. Role validation — exclusion by role_level (ohm#7f3a9c2d) ──────────
  --     Upgraded from name-string matching to role_level < 90.
  --     Authoritative, immune to role name aliases and future renames.
  IF p_requested_role_id IS NOT NULL THEN
    SELECT role_level, UPPER(role_name)
    INTO   v_role_level, v_role_upper
    FROM   public.roles
    WHERE  id = p_requested_role_id;

    IF v_role_level IS NULL THEN
      RAISE EXCEPTION 'requested role not found: %', p_requested_role_id
        USING ERRCODE = 'P0002';
    END IF;

    -- Reject SA/HA and any future admin-tier roles by level (>= 90)
    IF v_role_level >= 90 THEN
      RAISE EXCEPTION 'restricted_role: role level % is not self-requestable (role_id: %)',
        v_role_level, p_requested_role_id
        USING ERRCODE = '42501';
    END IF;

    -- Scope rules for group-only roles
    IF v_role_upper IN ('OPERATIONS MANAGER', 'OM', 'ENCODER') THEN
      IF COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0) > 0 THEN
        RAISE EXCEPTION 'role_scope_violation: % may only request group scope (no accounts)', v_role_upper
          USING ERRCODE = '22023';
      END IF;
    END IF;

    IF COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0) > 0
      AND COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0) = 0 THEN
      RAISE EXCEPTION 'account scope requires at least one group'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- ── 7. Update account_requests with identity fields ───────────────────────
  UPDATE public.account_requests
  SET
    last_name          = TRIM(p_last_name),
    first_name         = TRIM(p_first_name),
    middle_name        = public.fn_coalesce_middle_name(p_middle_name),
    mobile_number      = v_mobile_norm,
    full_name          = TRIM(CONCAT_WS(' ',
                           TRIM(p_first_name),
                           public.fn_coalesce_middle_name(p_middle_name),
                           TRIM(p_last_name)
                         )),
    requested_role_id  = COALESCE(p_requested_role_id, requested_role_id),
    notes              = COALESCE(p_notes, notes),
    updated_at         = NOW()
  WHERE id = v_request.id;

  -- ── 8. Scope rows: replace requested scope ────────────────────────────────
  DELETE FROM public.account_request_group_scopes
  WHERE account_request_id = v_request.id;

  DELETE FROM public.account_request_account_scopes
  WHERE account_request_id = v_request.id;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    INSERT INTO public.account_request_group_scopes (account_request_id, group_id)
    VALUES (v_request.id, v_gid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  FOREACH v_aid IN ARRAY p_account_ids LOOP
    INSERT INTO public.account_request_account_scopes (account_request_id, account_id)
    VALUES (v_request.id, v_aid)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- ── 9. Return summary ─────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',        TRUE,
    'request_id',     v_request.id,
    'last_name',      TRIM(p_last_name),
    'first_name',     TRIM(p_first_name),
    'mobile_number',  v_mobile_norm,
    'role_id',        p_requested_role_id,
    'group_count',    COALESCE(ARRAY_LENGTH(p_group_ids, 1), 0),
    'account_count',  COALESCE(ARRAY_LENGTH(p_account_ids, 1), 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_enrich_account_request(TEXT, TEXT, TEXT, TEXT, UUID, UUID[], UUID[], TEXT)
  TO authenticated;

COMMENT ON FUNCTION public.fn_enrich_account_request IS
  'ohm#7f3a9c2d: Role exclusion upgraded to role_level >= 90 (was: name-string IN-list). '
  'Immune to role name aliases and future renames. '
  'Carries forward OHM2026_0041 governance gate and OHM2026_2010 identity enrichment.';


-- =============================================================================
-- Validation SQL (read-only, run manually after applying):
--
-- V1: SA and HA not returned by RPC
--   SELECT count(*) FROM jsonb_array_elements(
--     public.get_request_account_signup_options()->'roles'
--   ) r WHERE (r->>'role_name') IN ('Super Admin','Head Admin');
--   → 0
--
-- V2: All returned roles have role_level < 90
--   SELECT bool_and(
--     (SELECT role_level FROM public.roles WHERE id = (r->>'id')::uuid) < 90
--   )
--   FROM jsonb_array_elements(public.get_request_account_signup_options()->'roles') r;
--   → true
--
-- V3: Roles are ordered by level desc (OM first, Recruitment last)
--   SELECT r->>'role_name'
--   FROM jsonb_array_elements(public.get_request_account_signup_options()->'roles') r;
--   → Operations Manager, HRCO, ATL, TL, Encoder, Recruitment Team (approx)
--
-- V4: No roles → returns empty array not null
--   SELECT get_request_account_signup_options()->'roles' IS NOT NULL;
--   → true (always returns []::jsonb minimum)
--
-- V5: Bypass attempt rejected at trigger
--   -- Simulate: attempt signUp with a Super Admin role_id
--   -- → trigger raises: restricted_role: role level 100 is not self-requestable
--
-- V6: Bypass attempt rejected at fn_enrich_account_request
--   -- Simulate: authenticated call with SA role_id
--   -- → raises: restricted_role: role level 100 is not self-requestable
-- =============================================================================
