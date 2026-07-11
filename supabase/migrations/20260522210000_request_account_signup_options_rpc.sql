-- =============================================================================
-- Migration: 20260522210000_request_account_signup_options_rpc.sql
-- Purpose  : Public-safe RPC for Request Account signup option loading.
--
-- Context  : The Request Account screen runs BEFORE login (anon session).
--            Direct table reads on roles/groups/accounts are RLS-blocked for
--            anon, causing "Unable to load role and scope options."
--
-- Fix      : SECURITY DEFINER function callable by anon + authenticated.
--            Returns only the safe lookup data the signup form needs:
--              - requestable roles (OM, Encoder, Recruitment, HRCO, ATL, TL)
--              - active groups
--              - active non-pool accounts
--
-- Safety   : Allowlist-based role filter — new admin roles added in future
--            are NOT exposed automatically.
--            No inserts, updates, deletes, or auth mutations.
--            Existing authenticated/admin RPC contracts are NOT changed.
--            Existing RLS on roles/groups/accounts tables is NOT weakened.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- RPC: get_request_account_signup_options
-- Callable by: anon, authenticated
-- Returns: jsonb { roles, groups, accounts }
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
    - A fixed allowlist of requestable role names (id + role_name only)
    - Active groups (id + group_name only)
    - Active non-pool accounts (id + account_name + group_id only)

  Super Admin, Head Admin, Executive Viewer, and any role not in the allowlist
  are never returned regardless of what exists in the roles table.
*/
DECLARE
  v_roles    jsonb;
  v_groups   jsonb;
  v_accounts jsonb;
BEGIN
  -- Requestable roles: exact allowlist only.
  -- Excluded: Super Admin, Head Admin, Executive Viewer, any unlisted role.
  SELECT jsonb_agg(
    jsonb_build_object('id', r.id, 'role_name', r.role_name)
    ORDER BY r.role_name
  )
  INTO v_roles
  FROM public.roles r
  WHERE r.role_name IN (
    'Operations Manager',
    'Encoder',
    'Recruitment',
    'Recruitment Team',
    'HRCO',
    'ATL',
    'TL'
  );

  -- Active groups only. id + group_name only — no internal metadata exposed.
  SELECT jsonb_agg(
    jsonb_build_object('id', g.id, 'group_name', g.group_name)
    ORDER BY g.group_name
  )
  INTO v_groups
  FROM public.groups g
  WHERE g.is_active = true;

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

-- Grant execute to anon (pre-login) and authenticated (post-login, in case
-- the screen is rendered inside an authenticated session for any reason).
GRANT EXECUTE ON FUNCTION public.get_request_account_signup_options() TO anon;
GRANT EXECUTE ON FUNCTION public.get_request_account_signup_options() TO authenticated;

-- =============================================================================
-- Validation SQL (read-only, run manually after applying):
--
-- V1: RPC exists and is SECURITY DEFINER
--   SELECT proname, prosecdef
--   FROM pg_proc
--   WHERE proname = 'get_request_account_signup_options'
--     AND pronamespace = 'public'::regnamespace;
--   → must return 1 row with prosecdef = true
--
-- V2: anon can execute (simulate with SET ROLE anon or via anon key call)
--   SELECT public.get_request_account_signup_options();
--   → must return jsonb with roles/groups/accounts keys
--
-- V3: roles array contains only requestable roles
--   SELECT jsonb_array_length(public.get_request_account_signup_options()->'roles'),
--          (SELECT bool_and(r->>'role_name' = ANY(ARRAY[
--            'Operations Manager','Encoder','Recruitment','Recruitment Team','HRCO','ATL','TL'
--          ]))
--           FROM jsonb_array_elements(public.get_request_account_signup_options()->'roles') r);
--   → length matches count of those roles in DB; bool_and = true
--
-- V4: Super Admin, Head Admin, Executive Viewer not in roles array
--   SELECT count(*) FROM jsonb_array_elements(
--     public.get_request_account_signup_options()->'roles'
--   ) r
--   WHERE r->>'role_name' IN ('Super Admin','Head Admin','Executive Viewer');
--   → must return 0
--
-- V5: groups array contains only active groups
--   SELECT jsonb_array_length(public.get_request_account_signup_options()->'groups');
--   → must match: SELECT count(*) FROM groups WHERE is_active = true
--
-- V6: accounts array excludes pool accounts
--   SELECT count(*) FROM jsonb_array_elements(
--     public.get_request_account_signup_options()->'accounts'
--   ) a
--   WHERE (a->>'group_id') IS NULL;
--   → expect 0 (all returned accounts have a group_id)
--
-- V7: no inserts/updates possible — function body has no DML
--   (code-only verification)
-- =============================================================================
