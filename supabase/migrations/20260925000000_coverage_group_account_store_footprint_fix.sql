-- ============================================================
-- OHM2026_0085F - Coverage Group: Account Eligibility Store Footprint Fix
-- Migration: 20260925000000_coverage_group_account_store_footprint_fix.sql
--
-- Depends on:
--   20260924000000_coverage_group_overlap_guard.sql
--
-- Problem:
--   get_coverage_group_eligible_accounts() still allowed accounts with
--   non-closed plantilla_slots rows linked only by ps.account_id. That is
--   broader than the Coverage Group invariant because it does not prove any
--   active store has Plantilla operational footprint.
--
-- Fix:
--   Account eligibility must come from active store-level footprint only:
--     stores.account_id = account_id
--     stores.is_active = true
--     AND (
--       non-closed plantilla_slots.store_id = stores.id
--       OR active employee_store_allocations.store_id = stores.id
--     )
--
-- Notes:
--   - Store overlap behavior is unchanged.
--   - Store picker search/disabled grouped rows are frontend-only.
-- ============================================================


-- ============================================================
-- Section 1: get_coverage_group_eligible_accounts
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
    EXISTS (
      SELECT 1
      FROM public.plantilla_slots ps
      JOIN public.stores st ON st.id = ps.store_id
      WHERE st.account_id = s.account_id
        AND st.is_active = true
        AND ps.slot_status NOT IN ('closed')
    )
    OR EXISTS (
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
  'OHM2026_0085F: Returns scoped accounts eligible for Coverage Group creation. '
  'Eligibility requires accounts.is_active = true via get_my_scoped_accounts '
  'and active store-level Plantilla footprint: an active store with a non-closed '
  'plantilla_slots row or active employee_store_allocations row. Does not use '
  'ps.account_id alone.';


-- ============================================================
-- Section 2: create_coverage_group
-- ============================================================
-- Full replacement to align the direct-create account guard with the dropdown
-- RPC while preserving OHM2026_0085E overlap/minimum-2/slot-parity behavior.
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

  IF NOT EXISTS (
    SELECT 1 FROM public.accounts
    WHERE id = p_account_id
      AND is_active = true
  ) THEN
    RAISE EXCEPTION 'account not found or inactive' USING ERRCODE = '42501';
  END IF;

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

  IF p_required_hc < 1 THEN
    RAISE EXCEPTION 'required_hc must be >= 1' USING ERRCODE = '22023';
  END IF;

  IF p_store_ids IS NULL OR array_length(p_store_ids, 1) < 2 THEN
    RAISE EXCEPTION 'coverage group requires at least 2 stores; use the normal Vacancy workflow for a single store'
      USING ERRCODE = '22023';
  END IF;

  IF p_anchor_store_id IS NULL OR NOT (p_anchor_store_id = ANY (p_store_ids)) THEN
    RAISE EXCEPTION 'anchor store must be one of the selected stores'
      USING ERRCODE = '22023';
  END IF;

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

  v_cgcode := public.fn_generate_cgcode_for_account(p_account_id);

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
  'OHM2026_0085F: Creates a roving coverage group with active store-level Plantilla footprint guards. '
  'Preserves minimum 2 stores, overlap blocking, and slot parity from OHM2026_0085E.';


-- ============================================================
-- Section 3: grants
-- ============================================================

GRANT EXECUTE ON FUNCTION public.get_coverage_group_eligible_accounts()
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.create_coverage_group(uuid, uuid, text, integer, text, uuid[], uuid)
  TO authenticated;
