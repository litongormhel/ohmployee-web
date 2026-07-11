-- ============================================================
-- OHM2026_0085C — Coverage Group: Require Active Operational Stores
-- Migration: 20260922000000_coverage_group_active_store_guard.sql
--
-- Depends on:
--   20260920000000_coverage_group_rpcs.sql  (create_coverage_group v1)
--   20260921000000_coverage_group_account_active_guard.sql (accounts.is_active guard)
--
-- Problem:
--   BANKO appears in the account dropdown for Coverage Group creation.
--   accounts.is_active = true but BANKO has 0 active operational stores
--   (stores.is_active = true). The OHM2026_0085B guard only checked
--   accounts.is_active — it did not verify store footprint.
--
-- Fix:
--   §1  New RPC get_coverage_group_eligible_accounts() — returns scoped
--       accounts that have >= 1 active operational store. Frontend uses this
--       instead of get_my_scoped_accounts for the account picker.
--   §2  Patch create_coverage_group — adds active-store guard after the
--       existing accounts.is_active check. Backend rejects any account with
--       no active operational stores even if called directly.
--   §3  Grants
--
-- Decision — store footprint is the eligibility source:
--   stores.is_active = true is the correct invariant. Plantilla employee
--   count and vacancy count are NOT eligibility requirements (proactive
--   operational setup must be allowed for new accounts with active stores).
--   An account with active stores but zero plantilla is valid for CG creation.
--
-- Note on 20260921000000 (OHM2026_0085B):
--   That migration added accounts.is_active guard only. This migration
--   supersedes it for create_coverage_group by adding the store-footprint
--   guard on top. The OHM2026_0085B is still correctly applied first.
-- ============================================================


-- ============================================================
-- §1  get_coverage_group_eligible_accounts
-- ============================================================
-- Returns only accounts from get_my_scoped_accounts() that have
-- at least one active operational store (stores.is_active = true).
-- Frontend account picker uses this RPC instead of get_my_scoped_accounts.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_coverage_group_eligible_accounts()
  RETURNS TABLE (
    account_id   uuid,
    account_name text,
    account_code text,
    group_id     uuid,
    group_name   text
  )
  LANGUAGE sql
  SECURITY DEFINER
  STABLE
  SET search_path TO 'public'
AS $fn$
  SELECT
    s.account_id,
    s.account_name,
    s.account_code,
    s.group_id,
    s.group_name
  FROM public.get_my_scoped_accounts() s
  WHERE EXISTS (
    SELECT 1
    FROM public.stores st
    WHERE st.account_id = s.account_id
      AND st.is_active = true
  )
  ORDER BY s.group_name, s.account_name;
$fn$;

COMMENT ON FUNCTION public.get_coverage_group_eligible_accounts() IS
  'OHM2026_0085C: Returns scoped accounts eligible for Coverage Group creation. '
  'An account is eligible only if accounts.is_active = true (via get_my_scoped_accounts) '
  'AND it has at least one active operational store (stores.is_active = true). '
  'Used by the Coverage Group account picker in place of get_my_scoped_accounts.';


-- ============================================================
-- §2  Patch create_coverage_group — add active-store guard
-- ============================================================
-- Adds: after the accounts.is_active check, verify that the account
-- has at least one stores.is_active = true. Raises 22023 if not.
-- All other logic is identical to 20260921000000.
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_coverage_group(
  p_account_id       uuid,
  p_position_id      uuid,
  p_employment_type  text,
  p_required_hc      integer,
  p_area_name        text,
  p_store_ids        uuid[],
  p_anchor_store_id  uuid
)
  RETURNS json
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller_id    uuid;
  v_role         text;
  v_cgcode       text;
  v_group_id     uuid;
  v_store_id     uuid;
BEGIN
  -- ── RBAC ────────────────────────────────────────────────────────────────
  SELECT id INTO v_caller_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_name INTO v_role
  FROM public.users_profile up
  JOIN public.roles r ON r.id = up.role_id
  WHERE up.id = v_caller_id;

  IF v_role NOT IN ('Super Admin', 'Head Admin', 'Encoder') THEN
    RAISE EXCEPTION 'forbidden: Data Team role required' USING ERRCODE = '42501';
  END IF;

  -- ── Scope check (non-admin must own the account) ────────────────────────
  IF v_role = 'Encoder' THEN
    IF NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
      RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Account must be active ───────────────────────────────────────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.accounts
    WHERE id = p_account_id
      AND is_active = true
  ) THEN
    RAISE EXCEPTION 'account not found or inactive' USING ERRCODE = '42501';
  END IF;

  -- ── Account must have at least one active operational store ──────────────
  IF NOT EXISTS (
    SELECT 1 FROM public.stores
    WHERE account_id = p_account_id
      AND is_active = true
  ) THEN
    RAISE EXCEPTION 'account has no active operational stores' USING ERRCODE = '22023';
  END IF;

  -- ── Validate params ──────────────────────────────────────────────────────
  IF p_required_hc < 1 THEN
    RAISE EXCEPTION 'required_hc must be >= 1' USING ERRCODE = '22023';
  END IF;

  IF p_store_ids IS NULL OR array_length(p_store_ids, 1) < 1 THEN
    RAISE EXCEPTION 'at least one store is required' USING ERRCODE = '22023';
  END IF;

  IF p_anchor_store_id IS NULL OR NOT (p_anchor_store_id = ANY (p_store_ids)) THEN
    RAISE EXCEPTION 'anchor store must be one of the selected stores' USING ERRCODE = '22023';
  END IF;

  -- ── Validate all stores belong to the account and are active ────────────
  IF EXISTS (
    SELECT 1
    FROM unnest(p_store_ids) AS sid
    WHERE NOT EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = sid
        AND s.account_id = p_account_id
        AND s.is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'all stores must belong to the selected account and be active' USING ERRCODE = '22023';
  END IF;

  -- ── Mint CGCODE ──────────────────────────────────────────────────────────
  v_cgcode := public.fn_generate_cgcode_for_account(p_account_id);

  -- ── Insert coverage group (slots emitted by trg_emit_coverage_slots) ─────
  INSERT INTO public.coverage_groups (
    coverage_code,
    account_id,
    position_id,
    employment_type,
    required_headcount,
    area_name,
    created_by
  ) VALUES (
    v_cgcode,
    p_account_id,
    p_position_id,
    p_employment_type,
    p_required_hc,
    nullif(trim(coalesce(p_area_name, '')), ''),
    v_caller_id
  )
  RETURNING id INTO v_group_id;

  -- ── Insert store footprint ───────────────────────────────────────────────
  FOREACH v_store_id IN ARRAY p_store_ids LOOP
    INSERT INTO public.coverage_group_stores (
      coverage_group_id,
      store_id,
      is_anchor,
      added_by
    ) VALUES (
      v_group_id,
      v_store_id,
      (v_store_id = p_anchor_store_id),
      v_caller_id
    );
  END LOOP;

  RETURN json_build_object(
    'coverage_group_id', v_group_id,
    'coverage_code',     v_cgcode
  );
END
$fn$;

COMMENT ON FUNCTION public.create_coverage_group(uuid, uuid, text, integer, text, uuid[], uuid) IS
  'OHM2026_0085C: Creates a roving coverage group with store footprint. '
  'Validates accounts.is_active = true and >= 1 active operational store before insert. '
  'All selected stores must be active and belong to the account. '
  'Slots emitted by trg_emit_coverage_slots. Caller: Data Team (SA/HA/Encoder).';


-- ============================================================
-- §3  Grants
-- ============================================================

GRANT EXECUTE ON FUNCTION public.get_coverage_group_eligible_accounts()
  TO authenticated;
