-- redfining vw_coverage_group_shadow view to include active imported roving groups
DROP VIEW IF EXISTS public.vw_coverage_group_shadow CASCADE;

CREATE OR REPLACE VIEW public.vw_coverage_group_shadow
  WITH (security_invoker = true)
AS
SELECT
  cg.id AS coverage_group_id,
  cg.coverage_code,
  cg.account_id,
  a.account_name,
  a.group_id,
  g.group_name,
  cg.position_id,
  p.position_name,
  cg.employment_type,
  cg.area_name,
  cg.status AS group_status,
  cg.created_at,
  sc.required_hc,
  sc.open_count,
  sc.pipeline_count,
  sc.hr_processing_count,
  sc.active_count,
  0::bigint AS closed_count,
  sc.slot_total,
  sc.active_count AS filled_hc,
  CASE
    WHEN sc.required_hc > 0 THEN ROUND(sc.active_count::numeric / sc.required_hc * 100, 2)
    ELSE 0::numeric
  END AS mfr_pct,
  (sc.required_hc > 0 AND sc.active_count >= sc.required_hc) AS is_mfr_met,
  CASE
    WHEN sc.open_count > 0 THEN 'open'
    WHEN sc.pipeline_count > 0 THEN 'pipeline'
    WHEN sc.hr_processing_count > 0 THEN 'hr_processing'
    WHEN sc.required_hc > 0 AND sc.active_count >= sc.required_hc THEN 'filled'
    ELSE 'structure'
  END AS vacancy_tab,
  sf.active_store_count::bigint AS active_store_count,
  sf.anchor_store_id,
  sf.anchor_store_name,
  sf.store_preview,
  sf.store_ids
FROM public.coverage_groups cg
JOIN public.accounts a
  ON a.id = cg.account_id
 AND a.is_active = true
 AND lower(COALESCE(a.status, 'active')) <> 'archived'
LEFT JOIN public.groups g ON g.id = a.group_id
LEFT JOIN public.positions p ON p.id = cg.position_id
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) FILTER (WHERE cs.slot_status = 'open') AS open_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'pipeline') AS pipeline_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'hr_processing') AS hr_processing_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'active') AS active_count,
    COUNT(*) AS slot_total,
    COUNT(*)::integer AS required_hc
  FROM public.coverage_slots cs
  WHERE cs.coverage_group_id = cg.id
    AND cs.slot_status <> 'closed'
) sc ON true
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) AS active_store_count,
    (ARRAY_AGG(cgs.store_id) FILTER (WHERE cgs.is_anchor))[1] AS anchor_store_id,
    MAX(s.store_name) FILTER (WHERE cgs.is_anchor) AS anchor_store_name,
    ARRAY_AGG(cgs.store_id ORDER BY cgs.is_anchor DESC, cgs.added_at ASC) AS store_ids,
    CASE
      WHEN COUNT(*) = 0 THEN NULL
      WHEN COUNT(*) <= 3 THEN string_agg(s.store_name, ', ' ORDER BY cgs.is_anchor DESC, cgs.added_at ASC)
      ELSE array_to_string((ARRAY_AGG(s.store_name ORDER BY cgs.is_anchor DESC, cgs.added_at ASC))[1:3], ', ')
           || ' +' || (COUNT(*) - 3)::text || ' more'
    END AS store_preview
  FROM public.coverage_group_stores cgs
  JOIN public.stores s
    ON s.id = cgs.store_id
   AND s.is_active = true
   AND lower(COALESCE(s.status, 'active')) <> 'archived'
  WHERE cgs.coverage_group_id = cg.id
    AND cgs.archived_at IS NULL
) sf ON true
WHERE cg.archived_at IS NULL
  AND lower(COALESCE(cg.status, '')) <> 'archived'
  AND cg.coverage_code LIKE 'CG-%'

UNION ALL

SELECT
  irg.id AS coverage_group_id,
  'ROV-' || irg.employee_no AS coverage_code,
  irg.account_id,
  irg.account_name,
  irg.group_id,
  g.group_name,
  pl.position_id,
  COALESCE(pos.position_name, pl.position) AS position_name,
  'Roving'::text AS employment_type,
  pl.area AS area_name,
  'active'::text AS group_status,
  irg.created_at,
  1::integer AS required_hc,
  0::bigint AS open_count,
  0::bigint AS pipeline_count,
  0::bigint AS hr_processing_count,
  1::bigint AS active_count,
  0::bigint AS closed_count,
  1::bigint AS slot_total,
  1::bigint AS filled_hc,
  100.00::numeric AS mfr_pct,
  true AS is_mfr_met,
  'filled'::text AS vacancy_tab,
  irg.active_store_count::bigint AS active_store_count,
  NULL::uuid AS anchor_store_id,
  NULL::text AS anchor_store_name,
  (
    SELECT string_agg(esa.store_name, ', ' ORDER BY esa.store_name)
    FROM public.employee_store_allocations esa
    WHERE esa.roving_group_id = irg.id
      AND esa.is_active = true
      AND esa.effective_end IS NULL
  ) AS store_preview,
  (
    SELECT array_agg(esa.store_id ORDER BY esa.store_name)
    FROM public.employee_store_allocations esa
    WHERE esa.roving_group_id = irg.id
      AND esa.is_active = true
      AND esa.effective_end IS NULL
  ) AS store_ids
FROM public.import_roving_groups irg
LEFT JOIN public.groups g ON g.id = irg.group_id
LEFT JOIN public.plantilla pl ON pl.id = irg.plantilla_id
LEFT JOIN public.positions pos ON pos.id = pl.position_id
WHERE irg.archived_at IS NULL;

COMMENT ON VIEW public.vw_coverage_group_shadow IS
  'OHM2026_0102: Coverage Group shadow view excludes archived groups, archived/inactive accounts, archived/inactive stores, archived store edges, and closed slots. Redefined to include active imported roving groups.';

GRANT SELECT ON public.vw_coverage_group_shadow TO authenticated;
GRANT SELECT ON public.vw_coverage_group_shadow TO service_role;


-- Redefining get_coverage_group_detail to fallback to import_roving_groups
CREATE OR REPLACE FUNCTION public.get_coverage_group_detail(
  p_coverage_group_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller_id uuid;
  v_group_row record;
  v_stores json;
  v_slots json;
BEGIN
  SELECT id INTO v_caller_id
  FROM public.users_profile
  WHERE auth_user_id = auth.uid()
    AND is_active = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'forbidden: active profile not found' USING ERRCODE = '42501';
  END IF;

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
    cg.status AS group_status,
    cg.created_at,
    COUNT(cs.id) FILTER (WHERE cs.slot_status <> 'closed')::integer AS required_hc
  INTO v_group_row
  FROM public.coverage_groups cg
  JOIN public.accounts a
    ON a.id = cg.account_id
   AND a.is_active = true
   AND lower(COALESCE(a.status, 'active')) <> 'archived'
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN public.positions p ON p.id = cg.position_id
  LEFT JOIN public.coverage_slots cs
    ON cs.coverage_group_id = cg.id
   AND cs.slot_status <> 'closed'
  WHERE cg.id = p_coverage_group_id
    AND cg.archived_at IS NULL
    AND lower(COALESCE(cg.status, '')) <> 'archived'
  GROUP BY cg.id, a.account_name, a.group_id, g.group_name, p.position_name;

  IF v_group_row IS NULL THEN
    -- Try fetching from import_roving_groups
    SELECT
      irg.id,
      'ROV-' || irg.employee_no AS coverage_code,
      irg.account_id,
      irg.account_name,
      irg.group_id,
      g.group_name,
      pl.position_id,
      COALESCE(pos.position_name, pl.position) AS position_name,
      'Roving' AS employment_type,
      pl.area AS area_name,
      'active' AS group_status,
      irg.created_at,
      1::integer AS required_hc
    INTO v_group_row
    FROM public.import_roving_groups irg
    LEFT JOIN public.groups g ON g.id = irg.group_id
    LEFT JOIN public.plantilla pl ON pl.id = irg.plantilla_id
    LEFT JOIN public.positions pos ON pos.id = pl.position_id
    WHERE irg.id = p_coverage_group_id
      AND irg.archived_at IS NULL;
  END IF;

  IF v_group_row IS NULL THEN
    RAISE EXCEPTION 'coverage group not found or archived' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (
    public.i_have_full_access()
    OR v_group_row.account_id = ANY (public.get_my_allowed_account_ids())
  ) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (SELECT 1 FROM public.coverage_groups WHERE id = p_coverage_group_id) THEN
    SELECT json_agg(
      json_build_object(
        'id', cgs.id,
        'store_id', cgs.store_id,
        'store_name', s.store_name,
        'is_anchor', cgs.is_anchor,
        'store_branch', s.store_branch,
        'area_city', s.area_city,
        'area_province', COALESCE(s.area_province, s.province),
        'vcode', s.vcode,
        'added_at', cgs.added_at
      )
      ORDER BY cgs.is_anchor DESC, cgs.added_at ASC
    )
    INTO v_stores
    FROM public.coverage_group_stores cgs
    JOIN public.stores s
      ON s.id = cgs.store_id
     AND s.is_active = true
     AND lower(COALESCE(s.status, 'active')) <> 'archived'
    WHERE cgs.coverage_group_id = p_coverage_group_id
      AND cgs.archived_at IS NULL;
  ELSE
    SELECT json_agg(
      json_build_object(
        'id', esa.id,
        'store_id', esa.store_id,
        'store_name', s.store_name,
        'is_anchor', false,
        'store_branch', s.store_branch,
        'area_city', s.area_city,
        'area_province', COALESCE(s.area_province, s.province),
        'vcode', s.vcode,
        'added_at', esa.created_at
      )
      ORDER BY s.store_name ASC
    )
    INTO v_stores
    FROM public.employee_store_allocations esa
    JOIN public.stores s
      ON s.id = esa.store_id
     AND s.is_active = true
     AND lower(COALESCE(s.status, 'active')) <> 'archived'
    WHERE esa.roving_group_id = p_coverage_group_id
      AND esa.is_active = true
      AND esa.effective_end IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM public.coverage_groups WHERE id = p_coverage_group_id) THEN
    SELECT json_agg(
      json_build_object(
        'id', cs.id,
        'slot_ordinal', cs.slot_ordinal,
        'slot_status', cs.slot_status,
        'created_at', cs.created_at,
        'updated_at', cs.updated_at
      )
      ORDER BY cs.slot_ordinal ASC
    )
    INTO v_slots
    FROM public.coverage_slots cs
    WHERE cs.coverage_group_id = p_coverage_group_id
      AND cs.slot_status <> 'closed';
  ELSE
    SELECT json_build_array(
      json_build_object(
        'id', irg.id,
        'slot_ordinal', 1,
        'slot_status', 'active',
        'created_at', irg.created_at,
        'updated_at', irg.updated_at
      )
    )
    INTO v_slots
    FROM public.import_roving_groups irg
    WHERE irg.id = p_coverage_group_id;
  END IF;

  RETURN json_build_object(
    'id', v_group_row.id,
    'coverage_code', v_group_row.coverage_code,
    'account_id', v_group_row.account_id,
    'account_name', v_group_row.account_name,
    'group_id', v_group_row.group_id,
    'group_name', v_group_row.group_name,
    'position_id', v_group_row.position_id,
    'position_name', v_group_row.position_name,
    'employment_type', v_group_row.employment_type,
    'area_name', v_group_row.area_name,
    'group_status', v_group_row.group_status,
    'created_at', v_group_row.created_at,
    'required_hc', COALESCE(v_group_row.required_hc, 0),
    'stores', COALESCE(v_stores, '[]'::json),
    'slots', COALESCE(v_slots, '[]'::json)
  );
END
$fn$;

COMMENT ON FUNCTION public.get_coverage_group_detail(uuid) IS
  'OHM2026_0102: Coverage Group detail excludes archived group/account/store parents, archived store edges, and closed slots. Redefined to support active imported roving groups.';

GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid) TO service_role;
