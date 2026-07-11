-- ============================================================
-- OHM2026_0085 — Coverage Group RPCs + INSERT/Archive policies
-- Migration: 20260920000000_coverage_group_rpcs.sql
--
-- Depends on:
--   20260826000000_coverage_group_phase_re_shadow_read_model.sql (shadow view)
--   20260822000005 (eager slot trigger)
--   20260822000002 (fn_generate_cgcode_for_account)
--
-- Sections:
--   §1  INSERT/UPDATE policies on coverage_groups and coverage_group_stores
--   §2  create_coverage_group
--   §3  list_coverage_groups
--   §4  get_coverage_group_detail
--   §5  archive_coverage_group
--   §6  Grants
-- ============================================================


-- ============================================================
-- §1  Policies — allow SECURITY DEFINER RPCs to bypass client locks
-- ============================================================
-- The tables have INSERT/UPDATE/DELETE revoked from authenticated/anon.
-- SECURITY DEFINER functions run as the function owner (postgres) and
-- bypass RLS by default, so no explicit policy is needed for the RPCs.
-- We add service_role INSERT/UPDATE policies as a belt-and-suspenders
-- confirmation that the service role path is always open.

-- (No policy change needed — SECURITY DEFINER bypasses RLS already.
--  Leaving this section as documentation only.)


-- ============================================================
-- §2  create_coverage_group
-- ============================================================
-- Creates a coverage group with its store footprint.
-- Slots are emitted automatically by trg_emit_coverage_slots (RA5).
--
-- Validation:
--   • p_required_hc >= 1
--   • at least 1 store in p_store_ids
--   • p_anchor_store_id must be in p_store_ids
--   • all stores must belong to p_account_id (enforced by RA3 trigger)
--   • caller must be superAdmin, headAdmin, or encoder
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

  -- ── Validate all stores belong to the account ────────────────────────────
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
  'OHM2026_0085: Creates a roving coverage group with store footprint. '
  'Slots emitted by trg_emit_coverage_slots. Caller: Data Team (SA/HA/Encoder).';


-- ============================================================
-- §3  list_coverage_groups
-- ============================================================
-- Returns rows from vw_coverage_group_shadow. The view is SECURITY INVOKER
-- so RLS on coverage_groups applies automatically. Full-access users see all;
-- scoped users see only their allowed accounts.
-- Optional p_account_id filters to a specific account.
-- ============================================================

CREATE OR REPLACE FUNCTION public.list_coverage_groups(
  p_account_id uuid DEFAULT NULL
)
  RETURNS TABLE (
    coverage_group_id  uuid,
    coverage_code      text,
    account_id         uuid,
    account_name       text,
    group_id           uuid,
    group_name         text,
    position_id        uuid,
    position_name      text,
    employment_type    text,
    area_name          text,
    group_status       text,
    created_at         timestamptz,
    required_hc        integer,
    open_count         bigint,
    pipeline_count     bigint,
    hr_processing_count bigint,
    active_count       bigint,
    closed_count       bigint,
    slot_total         bigint,
    filled_hc          bigint,
    mfr_pct            numeric,
    is_mfr_met         boolean,
    vacancy_tab        text,
    active_store_count bigint,
    anchor_store_id    uuid,
    anchor_store_name  text,
    store_preview      text,
    store_ids          uuid[]
  )
  LANGUAGE sql
  SECURITY INVOKER
  STABLE
  SET search_path TO 'public'
AS $fn$
  SELECT
    coverage_group_id,
    coverage_code,
    account_id,
    account_name,
    group_id,
    group_name,
    position_id,
    position_name,
    employment_type,
    area_name,
    group_status,
    created_at,
    required_hc,
    open_count,
    pipeline_count,
    hr_processing_count,
    active_count,
    closed_count,
    slot_total,
    filled_hc,
    mfr_pct,
    is_mfr_met,
    vacancy_tab,
    active_store_count,
    anchor_store_id,
    anchor_store_name,
    store_preview,
    store_ids
  FROM public.vw_coverage_group_shadow
  WHERE (p_account_id IS NULL OR account_id = p_account_id)
  ORDER BY created_at DESC;
$fn$;

COMMENT ON FUNCTION public.list_coverage_groups(uuid) IS
  'OHM2026_0085: Returns coverage groups from shadow view. SECURITY INVOKER — '
  'RLS on coverage_groups scopes results automatically.';


-- ============================================================
-- §4  get_coverage_group_detail
-- ============================================================
-- Returns full detail JSON: group summary + stores + slots.
-- Scope check: caller must have access to the group''s account.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_coverage_group_detail(
  p_coverage_group_id uuid
)
  RETURNS json
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller_id  uuid;
  v_group_row  record;
  v_stores     json;
  v_slots      json;
BEGIN
  -- ── Auth ────────────────────────────────────────────────────────────────
  SELECT id INTO v_caller_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

  -- ── Load group (scope check) ─────────────────────────────────────────────
  SELECT
    cg.id,
    cg.coverage_code,
    cg.account_id,
    a.account_name,
    a.group_id,
    g.group_name,
    cg.position_id,
    p.position_name,
    cg.employment_type,
    cg.area_name,
    cg.status             AS group_status,
    cg.created_at,
    cg.required_headcount AS required_hc
  INTO v_group_row
  FROM public.coverage_groups cg
  LEFT JOIN public.accounts  a ON a.id = cg.account_id
  LEFT JOIN public.groups    g ON g.id = a.group_id
  LEFT JOIN public.positions p ON p.id = cg.position_id
  WHERE cg.id = p_coverage_group_id
    AND cg.archived_at IS NULL;

  IF v_group_row IS NULL THEN
    RAISE EXCEPTION 'coverage group not found or archived' USING ERRCODE = 'P0002';
  END IF;

  -- Scope check
  IF NOT (
    public.i_have_full_access()
    OR v_group_row.account_id = ANY (public.get_my_allowed_account_ids())
  ) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

  -- ── Stores ───────────────────────────────────────────────────────────────
  SELECT json_agg(
    json_build_object(
      'id',         cgs.id,
      'store_id',   cgs.store_id,
      'store_name', s.store_name,
      'is_anchor',  cgs.is_anchor,
      'added_at',   cgs.added_at
    )
    ORDER BY cgs.is_anchor DESC, cgs.added_at ASC
  )
  INTO v_stores
  FROM public.coverage_group_stores cgs
  JOIN public.stores s ON s.id = cgs.store_id
  WHERE cgs.coverage_group_id = p_coverage_group_id
    AND cgs.archived_at IS NULL;

  -- ── Slots ────────────────────────────────────────────────────────────────
  SELECT json_agg(
    json_build_object(
      'id',           cs.id,
      'slot_ordinal', cs.slot_ordinal,
      'slot_status',  cs.slot_status,
      'created_at',   cs.created_at,
      'updated_at',   cs.updated_at
    )
    ORDER BY cs.slot_ordinal ASC
  )
  INTO v_slots
  FROM public.coverage_slots cs
  WHERE cs.coverage_group_id = p_coverage_group_id;

  RETURN json_build_object(
    'id',                   v_group_row.id,
    'coverage_code',        v_group_row.coverage_code,
    'account_id',           v_group_row.account_id,
    'account_name',         v_group_row.account_name,
    'group_id',             v_group_row.group_id,
    'group_name',           v_group_row.group_name,
    'position_id',          v_group_row.position_id,
    'position_name',        v_group_row.position_name,
    'employment_type',      v_group_row.employment_type,
    'area_name',            v_group_row.area_name,
    'group_status',         v_group_row.group_status,
    'created_at',           v_group_row.created_at,
    'required_hc',          v_group_row.required_hc,
    'stores',               coalesce(v_stores, '[]'::json),
    'slots',                coalesce(v_slots,  '[]'::json)
  );
END
$fn$;

COMMENT ON FUNCTION public.get_coverage_group_detail(uuid) IS
  'OHM2026_0085: Returns full coverage group detail (group + stores + slots) as JSON. '
  'Scoped to caller account access.';


-- ============================================================
-- §5  archive_coverage_group
-- ============================================================
-- Archives a coverage group.
-- Blocked if any slot has status active/pipeline/hr_processing.
-- On success: sets archived_at/archived_by/archive_reason on group;
-- archives all active store edges; closes all open slots.
-- ============================================================

CREATE OR REPLACE FUNCTION public.archive_coverage_group(
  p_coverage_group_id uuid,
  p_archive_reason    text DEFAULT NULL
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller_id      uuid;
  v_role           text;
  v_group_account  uuid;
  v_blocking_count integer;
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

  -- ── Load group ───────────────────────────────────────────────────────────
  SELECT account_id INTO v_group_account
  FROM public.coverage_groups
  WHERE id = p_coverage_group_id
    AND archived_at IS NULL;

  IF v_group_account IS NULL THEN
    RAISE EXCEPTION 'coverage group not found or already archived' USING ERRCODE = 'P0002';
  END IF;

  -- Scope check for Encoder
  IF v_role = 'Encoder' THEN
    IF NOT (v_group_account = ANY (public.get_my_allowed_account_ids())) THEN
      RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── Block if active/pipeline/hr_processing slots exist ──────────────────
  SELECT COUNT(*) INTO v_blocking_count
  FROM public.coverage_slots
  WHERE coverage_group_id = p_coverage_group_id
    AND slot_status IN ('active', 'pipeline', 'hr_processing');

  IF v_blocking_count > 0 THEN
    RAISE EXCEPTION
      'cannot archive: % active/pipeline/hr_processing slot(s) still open',
      v_blocking_count
      USING ERRCODE = '23514';
  END IF;

  -- ── Close all open slots ─────────────────────────────────────────────────
  UPDATE public.coverage_slots
  SET slot_status = 'closed',
      updated_at  = now()
  WHERE coverage_group_id = p_coverage_group_id
    AND slot_status = 'open';

  -- ── Archive store edges ──────────────────────────────────────────────────
  UPDATE public.coverage_group_stores
  SET archived_at  = now(),
      archived_by  = v_caller_id
  WHERE coverage_group_id = p_coverage_group_id
    AND archived_at IS NULL;

  -- ── Archive group ────────────────────────────────────────────────────────
  UPDATE public.coverage_groups
  SET archived_at    = now(),
      archived_by    = v_caller_id,
      archive_reason = nullif(trim(coalesce(p_archive_reason, '')), '')
  WHERE id = p_coverage_group_id;
END
$fn$;

COMMENT ON FUNCTION public.archive_coverage_group(uuid, text) IS
  'OHM2026_0085: Archives a coverage group. Blocked if active/pipeline/hr_processing slots exist. '
  'Closes open slots, archives store edges, archives the group. Caller: Data Team.';


-- ============================================================
-- §6  Grants — authenticated callers
-- ============================================================

GRANT EXECUTE ON FUNCTION public.create_coverage_group(uuid, uuid, text, integer, text, uuid[], uuid)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_coverage_groups(uuid)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.archive_coverage_group(uuid, text)
  TO authenticated;
