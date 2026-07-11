-- ============================================================
-- OHM2026_0085D — Coverage Group: Tighten Eligibility to Active Plantilla Store Footprint
-- Migration: 20260923000000_coverage_group_plantilla_footprint_guard.sql
--
-- Depends on:
--   20260920000000_coverage_group_rpcs.sql  (create_coverage_group v1)
--   20260921000000_coverage_group_account_active_guard.sql (accounts.is_active guard)
--   20260922000000_coverage_group_active_store_guard.sql (stores.is_active guard — superseded)
--
-- Problem:
--   OHM2026_0085C used stores.is_active = true as eligibility source.
--   Accounts such as BANKO, CITRUS, FOREVER SPICE have stores.is_active = true
--   but zero active Plantilla operational footprint (no active slots, no active
--   ESA rows). They still appeared in the account dropdown.
--
--   Expected: only accounts with active Plantilla operational footprint appear.
--   Current data: only MARIZ and ACTISERVE qualify.
--
-- Fix:
--   Source of truth = plantilla_slots.slot_status NOT IN ('closed')
--   Fallback = employee_store_allocations.is_active = true (covers roving ESA)
--
--   This ensures:
--   • Open/pipeline vacancy footprint counts (not just active employees)
--   • Roving employee store assignments covered via ESA fallback
--   • accounts.is_active = true guard preserved (via get_my_scoped_accounts)
--   • stores.is_active = true guard preserved on store-level RPC and CG creation
--
-- §1  Update get_coverage_group_eligible_accounts() — Plantilla footprint
-- §2  New get_coverage_group_eligible_stores(p_account_id) — per-account store footprint
-- §3  Update create_coverage_group — replace active-store guard with Plantilla footprint
-- §4  Grants
-- ============================================================


-- ============================================================
-- §1  get_coverage_group_eligible_accounts
-- ============================================================
-- Returns scoped accounts that have at least one active Plantilla
-- operational store footprint.
--
-- Footprint = any active store in the account with:
--   a) plantilla_slots.store_id = store AND slot_status NOT IN ('closed')
--      (includes open/pipeline/hr_processing/occupied — open vacancy slots count)
--   b) employee_store_allocations.is_active = true for that active store
--      (fallback for roving employees whose slot store_id may be NULL)
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
  WHERE (
    -- Primary: active store with non-closed plantilla_slots footprint.
    -- Do not use ps.account_id alone: legacy/account-level slots can make
    -- accounts look eligible even when no active store has operational footprint.
    EXISTS (
      SELECT 1
      FROM public.plantilla_slots ps
      JOIN public.stores st ON st.id = ps.store_id
      WHERE st.account_id = s.account_id
        AND st.is_active = true
        AND ps.slot_status NOT IN ('closed')
    )
    OR
    -- Fallback: active ESA rows for any active store in the account (covers roving ESA)
    EXISTS (
      SELECT 1
      FROM public.employee_store_allocations esa
      JOIN public.stores st ON st.id = esa.store_id
      WHERE st.account_id = s.account_id
        AND st.is_active = true
        AND esa.is_active = true
    )
  )
  ORDER BY s.group_name, s.account_name;
$fn$;

COMMENT ON FUNCTION public.get_coverage_group_eligible_accounts() IS
  'OHM2026_0085D: Returns scoped accounts eligible for Coverage Group creation. '
  'An account is eligible only if accounts.is_active = true (via get_my_scoped_accounts) '
  'AND it has active Plantilla operational store footprint: at least one active store '
  'with a non-closed plantilla_slots row OR active employee_store_allocations row. '
  'Open/pipeline vacancy slots count as footprint — active employees are not required. '
  'Supersedes OHM2026_0085C (stores.is_active guard).';


-- ============================================================
-- §2  get_coverage_group_eligible_stores
-- ============================================================
-- Returns stores eligible for the Coverage Group store picker for a
-- given account. A store is eligible if:
--   • stores.is_active = true, AND
--   • has at least one non-closed plantilla_slots row (store_id = this store)
--     OR at least one active ESA row (covers roving store assignments)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_coverage_group_eligible_stores(
  p_account_id uuid
)
  RETURNS TABLE (
    store_id      uuid,
    store_name    text,
    account_id    uuid,
    area_city     text,
    area_province text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  STABLE
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller_id uuid;
  v_role      text;
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

  -- ── Encoder scope check ──────────────────────────────────────────────────
  IF v_role = 'Encoder' THEN
    IF NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
      RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN QUERY
  SELECT DISTINCT
    s.id                               AS store_id,
    s.store_name,
    s.account_id,
    COALESCE(s.area_city, '')          AS area_city,
    COALESCE(s.area_province, '')      AS area_province
  FROM public.stores s
  WHERE s.account_id = p_account_id
    AND s.is_active = true
    AND (
      -- Primary: store has a non-closed plantilla_slots entry
      EXISTS (
        SELECT 1
        FROM public.plantilla_slots ps
        WHERE ps.store_id = s.id
          AND ps.slot_status NOT IN ('closed')
      )
      OR
      -- Fallback: store has an active ESA row (roving assignments use ESA)
      EXISTS (
        SELECT 1
        FROM public.employee_store_allocations esa
        WHERE esa.store_id = s.id
          AND esa.is_active = true
      )
    )
  ORDER BY s.store_name;
END
$fn$;

COMMENT ON FUNCTION public.get_coverage_group_eligible_stores(uuid) IS
  'OHM2026_0085D: Returns stores eligible for the Coverage Group store picker for an account. '
  'A store is eligible if stores.is_active = true AND has Plantilla operational footprint: '
  'at least one non-closed plantilla_slots row OR at least one active ESA row. '
  'Open/pipeline vacancy slots count — active employees are not required. '
  'Returns store_id, store_name, account_id, area_city, area_province for search UX.';


-- ============================================================
-- §3  Patch create_coverage_group — Plantilla footprint guards
-- ============================================================
-- Replaces the OHM2026_0085C active-store guard with Plantilla footprint guards:
--   a) Account-level: account must have at least one non-closed plantilla_slots row
--      OR at least one active ESA row for the account.
--   b) Store-level: each selected store must be active (stores.is_active = true)
--      AND have at least one non-closed plantilla_slots row OR active ESA row.
-- All other logic is identical to 20260922000000.
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

  -- ── Account must have active Plantilla operational store footprint ────────
  -- Source of truth: active store with non-closed plantilla_slots OR active ESA.
  -- Open/pipeline vacancy slots count — active employees are not required.
  IF NOT (
    EXISTS (
      SELECT 1
      FROM public.plantilla_slots ps
      JOIN public.stores st ON st.id = ps.store_id
      WHERE st.account_id = p_account_id
        AND st.is_active = true
        AND ps.slot_status NOT IN ('closed')
    )
    OR EXISTS (
      SELECT 1
      FROM public.employee_store_allocations esa
      JOIN public.stores st ON st.id = esa.store_id
      WHERE st.account_id = p_account_id
        AND st.is_active = true
        AND esa.is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'account has no active Plantilla operational store footprint' USING ERRCODE = '22023';
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

  -- ── Validate all stores: active + Plantilla footprint for this account ────
  -- Each store must: belong to the account, be stores.is_active = true,
  -- AND have at least one non-closed plantilla_slots row OR active ESA row.
  IF EXISTS (
    SELECT 1
    FROM unnest(p_store_ids) AS sid
    WHERE NOT EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = sid
        AND s.account_id = p_account_id
        AND s.is_active = true
        AND (
          EXISTS (
            SELECT 1 FROM public.plantilla_slots ps
            WHERE ps.store_id = s.id
              AND ps.slot_status NOT IN ('closed')
          )
          OR EXISTS (
            SELECT 1 FROM public.employee_store_allocations esa
            WHERE esa.store_id = s.id
              AND esa.is_active = true
          )
        )
    )
  ) THEN
    RAISE EXCEPTION 'all stores must belong to the account and have active Plantilla operational footprint' USING ERRCODE = '22023';
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
  'OHM2026_0085D: Creates a roving coverage group with store footprint. '
  'Guards: accounts.is_active = true; account has active Plantilla operational footprint '
  '(non-closed plantilla_slots OR active ESA); each selected store must be stores.is_active = true '
  'AND have Plantilla operational footprint. '
  'Slots emitted by trg_emit_coverage_slots. Caller: Data Team (SA/HA/Encoder).';


-- ============================================================
-- §4  Grants
-- ============================================================

GRANT EXECUTE ON FUNCTION public.get_coverage_group_eligible_accounts()
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_coverage_group_eligible_stores(uuid)
  TO authenticated;
