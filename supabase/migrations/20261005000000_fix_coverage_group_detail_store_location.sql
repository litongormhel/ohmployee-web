BEGIN;

DROP FUNCTION IF EXISTS public.get_coverage_group_detail(uuid);

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
      'id',            cgs.id,
      'store_id',      cgs.store_id,
      'store_name',    s.store_name,
      'is_anchor',     cgs.is_anchor,
      'store_branch',  s.store_branch,
      'area_city',     s.area_city,
      'area_province', COALESCE(s.area_province, s.province),
      'vcode',         s.vcode,
      'added_at',      cgs.added_at
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
  'OHM2026_0067: Returns full coverage group detail (group + stores + slots) as JSON. Scoped to caller account access with location/branch info.';

GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid) TO service_role;

COMMIT;
