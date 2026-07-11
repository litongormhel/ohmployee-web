-- ============================================================
-- OHM2026_0085B — Coverage Group: Active Account Guard
-- Migration: 20260921000000_coverage_group_account_active_guard.sql
--
-- Depends on:
--   20260920000000_coverage_group_rpcs.sql (create_coverage_group)
--
-- Problem:
--   create_coverage_group accepted any account_id without verifying
--   the account is active. An archived/inactive account (e.g. BANKO)
--   could be used to create groups if its is_active flag was left true.
--
-- Fix:
--   Adds an accounts.is_active = true guard in create_coverage_group
--   immediately after the scope check, before any insert.
--   Store validation was already correct (s.is_active = true).
--   Frontend account picker (get_my_scoped_accounts) was already correct.
--   No frontend changes required.
--
-- Decision — no active plantilla guard:
--   Coverage groups are proactive operational setup; an account may have
--   zero plantilla employees while creating groups for incoming hires.
--   Blocking on "no plantilla data" would prevent legitimate new-account
--   setup. The correct invariant is accounts.is_active = true only.
-- ============================================================


-- ============================================================
-- §1  Patch create_coverage_group — add account active guard
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
    RAISE EXCEPTION 'all stores must belong to the selected account' USING ERRCODE = '22023';
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
  'OHM2026_0085B: Creates a roving coverage group with store footprint. '
  'Validates accounts.is_active = true before insert. '
  'Slots emitted by trg_emit_coverage_slots. Caller: Data Team (SA/HA/Encoder).';


-- ============================================================
-- §2  Cleanup instructions for CG-BG1-0001 (BANKO test group)
--
-- DO NOT execute automatically. Run manually after confirmation.
--
-- Step A — Archive the bad coverage group:
--
--   UPDATE public.coverage_slots
--   SET slot_status = 'closed', updated_at = now()
--   WHERE coverage_group_id = (
--     SELECT id FROM public.coverage_groups WHERE coverage_code = 'CG-BG1-0001'
--   )
--   AND slot_status = 'open';
--
--   UPDATE public.coverage_group_stores
--   SET archived_at = now()
--   WHERE coverage_group_id = (
--     SELECT id FROM public.coverage_groups WHERE coverage_code = 'CG-BG1-0001'
--   )
--   AND archived_at IS NULL;
--
--   UPDATE public.coverage_groups
--   SET archived_at    = now(),
--       archive_reason = 'Created for inactive account BANKO — cleanup OHM2026_0085B'
--   WHERE coverage_code = 'CG-BG1-0001';
--
-- Step B — Deactivate BANKO account (verify first):
--
--   SELECT id, account_name, is_active
--   FROM public.accounts
--   WHERE account_name ILIKE '%BANKO%';
--
--   -- After confirming correct row:
--   UPDATE public.accounts
--   SET is_active = false
--   WHERE account_name ILIKE '%BANKO%';
--
-- ============================================================
