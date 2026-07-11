-- ============================================================
-- OHM2026_0085E — Coverage Group Overlap and Integrity Guards
-- Migration: 20260924000000_coverage_group_overlap_guard.sql
--
-- Depends on:
--   20260923000000_coverage_group_plantilla_footprint_guard.sql
--
-- Problem:
--   System allows creating multiple active coverage groups with
--   overlapping stores.  CG-MG1-0001 covers stores A/B/C/D/E;
--   CG-MG1-0002 can still be created with stores B/C/D — the same
--   stores serve two active groups simultaneously.
--
-- Fixes (4 guards):
--   1. Overlap guard: block create if any selected store is already
--      assigned to an active coverage group.
--      (active = coverage_groups.archived_at IS NULL AND
--              coverage_group_stores.archived_at IS NULL)
--      Error includes the conflicting coverage_code and store name.
--   2. Minimum 2 stores: 1 store = use normal Vacancy workflow.
--   3. Slot parity: required_headcount must equal the number of slots
--      emitted by trg_emit_coverage_slots after insert.
--   4. get_coverage_group_eligible_stores: adds already_grouped_code
--      column so the Flutter store picker can render disabled rows.
--
-- §1  Update get_coverage_group_eligible_stores (add already_grouped_code)
-- §2  Update create_coverage_group (overlap + min-2 + parity)
-- §3  Grants
-- §4  Diagnostic — overlapping active groups (commented SQL)
-- ============================================================


-- ============================================================
-- §1  get_coverage_group_eligible_stores
-- ============================================================
-- Adds already_grouped_code: the CGCODE of the active coverage group
-- that owns this store, or NULL if the store is free to assign.
-- Flutter uses this to render disabled rows with "Already in CG-XX-0001".
-- ============================================================

DROP FUNCTION IF EXISTS public.get_coverage_group_eligible_stores(uuid);

CREATE FUNCTION public.get_coverage_group_eligible_stores(
  p_account_id uuid
)
  RETURNS TABLE (
    store_id            uuid,
    store_name          text,
    account_id          uuid,
    area_city           text,
    area_province       text,
    already_grouped_code text
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

  IF v_role = 'Encoder' THEN
    IF NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
      RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN QUERY
  SELECT DISTINCT ON (s.id)
    s.id                                AS store_id,
    s.store_name,
    s.account_id,
    COALESCE(s.area_city, '')           AS area_city,
    COALESCE(s.area_province, '')       AS area_province,
    (
      SELECT cg.coverage_code
      FROM public.coverage_group_stores cgs2
      JOIN public.coverage_groups cg ON cg.id = cgs2.coverage_group_id
      WHERE cgs2.store_id = s.id
        AND cgs2.archived_at IS NULL
        AND cg.archived_at IS NULL
      LIMIT 1
    )                                   AS already_grouped_code
  FROM public.stores s
  WHERE s.account_id = p_account_id
    AND s.is_active = true
    AND (
      EXISTS (
        SELECT 1
        FROM public.plantilla_slots ps
        WHERE ps.store_id = s.id
          AND ps.slot_status NOT IN ('closed')
      )
      OR EXISTS (
        SELECT 1
        FROM public.employee_store_allocations esa
        WHERE esa.store_id = s.id
          AND esa.is_active = true
      )
    )
  ORDER BY s.id, s.store_name;
END
$fn$;

COMMENT ON FUNCTION public.get_coverage_group_eligible_stores(uuid) IS
  'OHM2026_0085E: Returns stores eligible for the Coverage Group store picker. '
  'Adds already_grouped_code — CGCODE of the active group owning this store, or NULL. '
  'Flutter uses already_grouped_code to render disabled rows ("Already in CG-XX-0001"). '
  'A store is eligible if stores.is_active = true AND has Plantilla operational footprint '
  '(non-closed plantilla_slots OR active ESA). Supersedes OHM2026_0085D column set.';


-- ============================================================
-- §2  create_coverage_group
-- ============================================================
-- Full replacement with four additional guards:
--   a) minimum 2 stores (1 store → use normal Vacancy workflow)
--   b) overlap guard: block if any selected store is already in
--      an active coverage group; error names the conflict
--   c) slot parity: verify required_hc equals emitted slot count
-- All existing guards from 20260923000000 are preserved.
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
  v_caller_id         uuid;
  v_role              text;
  v_cgcode            text;
  v_group_id          uuid;
  v_store_id          uuid;
  v_overlap_store     text;
  v_overlap_cgcode    text;
  v_slot_count        integer;
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

  -- ── Scope check (Encoder must own the account) ───────────────────────────
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

  -- ── Account must have active Plantilla operational store footprint ───────
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
    RAISE EXCEPTION 'account has no active Plantilla operational store footprint'
      USING ERRCODE = '22023';
  END IF;

  -- ── Validate required_hc ─────────────────────────────────────────────────
  IF p_required_hc < 1 THEN
    RAISE EXCEPTION 'required_hc must be >= 1' USING ERRCODE = '22023';
  END IF;

  -- ── Minimum 2 stores ─────────────────────────────────────────────────────
  -- A coverage group must span at least 2 stores.
  -- A single store should use the normal Vacancy workflow instead.
  IF p_store_ids IS NULL OR array_length(p_store_ids, 1) < 2 THEN
    RAISE EXCEPTION 'coverage group requires at least 2 stores; use the normal Vacancy workflow for a single store'
      USING ERRCODE = '22023';
  END IF;

  -- ── Anchor store must be in selected stores ──────────────────────────────
  IF p_anchor_store_id IS NULL OR NOT (p_anchor_store_id = ANY (p_store_ids)) THEN
    RAISE EXCEPTION 'anchor store must be one of the selected stores'
      USING ERRCODE = '22023';
  END IF;

  -- ── Overlap guard ─────────────────────────────────────────────────────────
  -- Block if any selected store is already assigned to an active coverage group.
  -- Active = coverage_groups.archived_at IS NULL AND
  --          coverage_group_stores.archived_at IS NULL
  SELECT s.store_name, cg.coverage_code
  INTO v_overlap_store, v_overlap_cgcode
  FROM unnest(p_store_ids) AS t(sid)
  JOIN public.coverage_group_stores cgs
    ON cgs.store_id = t.sid
   AND cgs.archived_at IS NULL
  JOIN public.coverage_groups cg
    ON cg.id = cgs.coverage_group_id
   AND cg.archived_at IS NULL
  JOIN public.stores s ON s.id = t.sid
  LIMIT 1;

  IF v_overlap_store IS NOT NULL THEN
    RAISE EXCEPTION 'store "%" is already assigned to active coverage group %',
      v_overlap_store, v_overlap_cgcode
      USING ERRCODE = '23505';
  END IF;

  -- ── All stores: active + Plantilla footprint for this account ────────────
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
    RAISE EXCEPTION 'all stores must belong to the account and have active Plantilla operational footprint'
      USING ERRCODE = '22023';
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

  -- ── Slot parity check ─────────────────────────────────────────────────────
  -- trg_emit_coverage_slots must have emitted exactly required_hc slots.
  SELECT COUNT(*)::integer INTO v_slot_count
  FROM public.coverage_slots
  WHERE coverage_group_id = v_group_id;

  IF v_slot_count <> p_required_hc THEN
    RAISE EXCEPTION 'slot parity failure: expected % slot(s) but trigger emitted %',
      p_required_hc, v_slot_count
      USING ERRCODE = '22023';
  END IF;

  RETURN json_build_object(
    'coverage_group_id', v_group_id,
    'coverage_code',     v_cgcode
  );
END
$fn$;

COMMENT ON FUNCTION public.create_coverage_group(uuid, uuid, text, integer, text, uuid[], uuid) IS
  'OHM2026_0085E: Creates a roving coverage group with store footprint. '
  'Guards: accounts.is_active; Plantilla footprint (account + per-store); '
  'minimum 2 stores; overlap (no store may be in another active CG); '
  'slot parity (required_hc == emitted slot count). '
  'Slots emitted by trg_emit_coverage_slots. Caller: Data Team (SA/HA/Encoder).';


-- ============================================================
-- §3  Grants
-- ============================================================

GRANT EXECUTE ON FUNCTION public.get_coverage_group_eligible_stores(uuid)
  TO authenticated;


-- ============================================================
-- §4  Diagnostic — find overlapping active coverage groups
-- ============================================================
-- Run this query to identify existing overlaps before applying the guard.
-- Recommendation: archive the group with fewer distinct stores, or if equal,
-- archive the one created later (higher CGCODE sequence number).
--
-- SELECT
--   cg1.coverage_code                AS group_1,
--   cg2.coverage_code                AS group_2,
--   s.store_name                     AS shared_store,
--   cg1.created_at                   AS group_1_created,
--   cg2.created_at                   AS group_2_created
-- FROM public.coverage_group_stores cgs1
-- JOIN public.coverage_group_stores cgs2
--   ON  cgs2.store_id              = cgs1.store_id
--   AND cgs2.coverage_group_id    <> cgs1.coverage_group_id
--   AND cgs2.archived_at           IS NULL
-- JOIN public.coverage_groups cg1
--   ON  cg1.id = cgs1.coverage_group_id
--   AND cg1.archived_at IS NULL
-- JOIN public.coverage_groups cg2
--   ON  cg2.id = cgs2.coverage_group_id
--   AND cg2.archived_at IS NULL
-- JOIN public.stores s ON s.id = cgs1.store_id
-- WHERE cgs1.archived_at IS NULL
--   AND cg1.coverage_code < cg2.coverage_code   -- de-dup pairs
-- ORDER BY s.store_name, cg1.coverage_code;
--
-- To archive the duplicate group via RPC:
--   SELECT archive_coverage_group('<uuid-of-duplicate>', 'Duplicate test group — OHM2026_0085E cleanup');
-- ============================================================
