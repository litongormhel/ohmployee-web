-- ============================================================
-- OHM2026_0097 - Coverage Architecture Phase 5 cleanup
-- ADR-001 alignment:
--   - Coverage Group is structure only.
--   - HC Request is the only workforce-demand source.
--   - Store count never affects HC.
--   - Coverage Weight / HC Share are not used.
-- ============================================================

BEGIN;

-- Coverage Groups keep the historical column for compatibility, but it is no
-- longer a demand source. New structure rows persist 0 and demand reports read
-- coverage_slots created by approved roving HC Requests.
ALTER TABLE public.coverage_groups
  DROP CONSTRAINT IF EXISTS coverage_groups_required_hc_check;

ALTER TABLE public.coverage_groups
  ALTER COLUMN required_headcount SET DEFAULT 0;

ALTER TABLE public.coverage_groups
  ADD CONSTRAINT coverage_groups_required_hc_check
  CHECK (required_headcount >= 0);

DROP TRIGGER IF EXISTS trg_emit_coverage_slots ON public.coverage_groups;

CREATE OR REPLACE FUNCTION public.fn_emit_coverage_slots()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  RETURN NULL;
END
$fn$;

COMMENT ON FUNCTION public.fn_emit_coverage_slots() IS
  'OHM2026_0097: Disabled by ADR-001. Coverage Group insert is structure-only; approved roving HC Requests create coverage_slots.';

CREATE OR REPLACE FUNCTION public.fn_coverage_group_structure_only_hc_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.required_headcount := 0;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.required_headcount := OLD.required_headcount;
  END IF;
  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_coverage_group_structure_only_hc_guard
  ON public.coverage_groups;

CREATE TRIGGER trg_coverage_group_structure_only_hc_guard
  BEFORE INSERT OR UPDATE OF required_headcount
  ON public.coverage_groups
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_coverage_group_structure_only_hc_guard();

COMMENT ON TRIGGER trg_coverage_group_structure_only_hc_guard
  ON public.coverage_groups IS
  'Prevents Coverage Group structure writes from creating or changing workforce demand. Demand is coverage_slots from approved roving HC Requests.';

DROP FUNCTION IF EXISTS public.create_coverage_group(uuid, uuid, text, text, uuid[], uuid);

CREATE OR REPLACE FUNCTION public.create_coverage_group(
  p_account_id       uuid,
  p_position_id      uuid,
  p_employment_type  text,
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
  v_caller_id      uuid;
  v_role           text;
  v_cgcode         text;
  v_group_id       uuid;
  v_store_id       uuid;
  v_overlap_store  text;
  v_overlap_cgcode text;
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

  IF v_role = 'Encoder'
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.accounts
    WHERE id = p_account_id
      AND is_active = true
  ) THEN
    RAISE EXCEPTION 'account not found or inactive' USING ERRCODE = '42501';
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
    0,
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

  RETURN json_build_object(
    'coverage_group_id', v_group_id,
    'coverage_code',     v_cgcode
  );
END
$fn$;

COMMENT ON FUNCTION public.create_coverage_group(uuid, uuid, text, text, uuid[], uuid) IS
  'OHM2026_0097: Structure-only Coverage Group creation. Does not accept or create Required HC, slots, vacancies, or pipeline.';

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
BEGIN
  RETURN public.create_coverage_group(
    p_account_id,
    p_position_id,
    p_employment_type,
    p_area_name,
    p_store_ids,
    p_anchor_store_id
  );
END
$fn$;

COMMENT ON FUNCTION public.create_coverage_group(uuid, uuid, text, integer, text, uuid[], uuid) IS
  'OHM2026_0097 compatibility wrapper. p_required_hc is ignored because Coverage Groups are structure-only under ADR-001.';

GRANT EXECUTE ON FUNCTION public.create_coverage_group(uuid, uuid, text, text, uuid[], uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_coverage_group(uuid, uuid, text, integer, text, uuid[], uuid)
  TO authenticated;

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
  sc.closed_count,
  sc.slot_total,
  sc.active_count AS filled_hc,
  CASE
    WHEN sc.required_hc > 0
      THEN ROUND(sc.active_count::numeric / sc.required_hc * 100, 2)
    ELSE 0::numeric
  END AS mfr_pct,
  (sc.required_hc > 0 AND sc.active_count >= sc.required_hc) AS is_mfr_met,
  CASE
    WHEN sc.open_count > 0 THEN 'open'
    WHEN sc.pipeline_count > 0 THEN 'pipeline'
    WHEN sc.hr_processing_count > 0 THEN 'hr_processing'
    WHEN sc.required_hc > 0
         AND sc.active_count >= sc.required_hc THEN 'filled'
    WHEN sc.required_hc = 0
         AND sc.closed_count > 0 THEN 'closed'
    ELSE 'structure'
  END AS vacancy_tab,
  sf.active_store_count,
  sf.anchor_store_id,
  sf.anchor_store_name,
  sf.store_preview,
  sf.store_ids
FROM public.coverage_groups cg
LEFT JOIN public.accounts  a ON a.id = cg.account_id
LEFT JOIN public.groups    g ON g.id = a.group_id
LEFT JOIN public.positions p ON p.id = cg.position_id
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) FILTER (WHERE cs.slot_status = 'open') AS open_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'pipeline') AS pipeline_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'hr_processing') AS hr_processing_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'active') AS active_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'closed') AS closed_count,
    COUNT(*) AS slot_total,
    COUNT(*) FILTER (WHERE cs.slot_status <> 'closed')::integer AS required_hc
  FROM public.coverage_slots cs
  WHERE cs.coverage_group_id = cg.id
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
  JOIN public.stores s ON s.id = cgs.store_id
  WHERE cgs.coverage_group_id = cg.id
    AND cgs.archived_at IS NULL
) sf ON true
WHERE cg.archived_at IS NULL
  AND cg.coverage_code LIKE 'CG-%';

COMMENT ON VIEW public.vw_coverage_group_shadow IS
  'OHM2026_0097: Coverage Group shadow view. required_hc is active non-closed coverage_slots demand created by approved roving HC Requests; store footprint and coverage_groups.required_headcount do not create HC.';

GRANT SELECT ON public.vw_coverage_group_shadow TO authenticated;
GRANT SELECT ON public.vw_coverage_group_shadow TO service_role;

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
  LEFT JOIN public.accounts a ON a.id = cg.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN public.positions p ON p.id = cg.position_id
  LEFT JOIN public.coverage_slots cs ON cs.coverage_group_id = cg.id
  WHERE cg.id = p_coverage_group_id
    AND cg.archived_at IS NULL
  GROUP BY cg.id, a.account_name, a.group_id, g.group_name, p.position_name;

  IF v_group_row IS NULL THEN
    RAISE EXCEPTION 'coverage group not found or archived' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (
    public.i_have_full_access()
    OR v_group_row.account_id = ANY (public.get_my_allowed_account_ids())
  ) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

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
  JOIN public.stores s ON s.id = cgs.store_id
  WHERE cgs.coverage_group_id = p_coverage_group_id
    AND cgs.archived_at IS NULL;

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
  WHERE cs.coverage_group_id = p_coverage_group_id;

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
  'OHM2026_0097: Coverage Group detail returns structure plus coverage_slots demand. required_hc is non-closed slot count, not a Coverage Group creation field.';

GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid) TO service_role;

CREATE OR REPLACE VIEW public.v_account_allocation_kpi
  WITH (security_invoker = true)
AS
WITH filled AS (
  SELECT a.account_id,
         round(COALESCE(sum(a.filled_hc), 0), 4) AS filled_hc,
         count(DISTINCT a.employee_no) AS actual_hc
  FROM public.employee_store_allocations a
  WHERE a.is_active
  GROUP BY a.account_id
),
pipeline AS (
  SELECT he.account_id, count(*) AS pipeline_count
  FROM public.hr_emploc he
  LEFT JOIN public.vacancies v ON v.id = he.vacancy_id
  WHERE he.status <> ALL (ARRAY['Moved to Plantilla'::text, 'Backout'::text])
    AND he.deleted_at IS NULL
    AND he.coverage_slot_id IS NULL
    AND COALESCE(v.is_archived, false) = false
    AND COALESCE(v.is_pool_vacancy, false) = false
  GROUP BY he.account_id
),
coverage_slot_kpi AS (
  SELECT
    cg.account_id,
    COUNT(*) FILTER (WHERE cs.slot_status = 'active')::numeric AS filled_hc,
    CASE
      WHEN COUNT(DISTINCT cs.current_occupant_plantilla_id)
           FILTER (WHERE cs.slot_status = 'active'
                   AND cs.current_occupant_plantilla_id IS NOT NULL) > 0
        THEN COUNT(DISTINCT cs.current_occupant_plantilla_id)
             FILTER (WHERE cs.slot_status = 'active'
                     AND cs.current_occupant_plantilla_id IS NOT NULL)
      ELSE COUNT(*) FILTER (WHERE cs.slot_status = 'active')
    END AS actual_hc,
    COUNT(*) FILTER (WHERE cs.slot_status IN ('pipeline', 'hr_processing')) AS pipeline_count,
    COUNT(*) FILTER (WHERE cs.slot_status = 'open')::numeric AS slot_vacant_hc
  FROM public.coverage_slots cs
  JOIN public.coverage_groups cg ON cg.id = cs.coverage_group_id
  WHERE cg.archived_at IS NULL
  GROUP BY cg.account_id
),
slot_vacant_non_roving AS (
  SELECT
    ps.account_id,
    COUNT(*) FILTER (WHERE ps.slot_status IN ('open', 'pipeline')) AS vacant_slots
  FROM public.plantilla_slots ps
  INNER JOIN public.vacancies v
    ON v.vcode = ps.legacy_vcode
   AND v.deleted_at IS NULL
   AND COALESCE(v.is_archived, false) = false
   AND COALESCE(v.is_pool_vacancy, false) = false
  WHERE ps.is_roving = false
    AND ps.legacy_vcode IS NOT NULL
    AND ps.account_id IS NOT NULL
  GROUP BY ps.account_id
),
slot_vacant_roving AS (
  SELECT
    ps.account_id,
    SUM(
      CASE WHEN ps.slot_status IN ('open', 'pipeline')
           THEN 1.0 / NULLIF(grp.total_slots::numeric, 0)
           ELSE 0.0
      END
    ) AS vacant_hc
  FROM public.plantilla_slots ps
  JOIN (
    SELECT source_hc_request_id, COUNT(*) AS total_slots
    FROM public.plantilla_slots
    WHERE is_roving = true
      AND source_hc_request_id IS NOT NULL
    GROUP BY source_hc_request_id
  ) grp ON grp.source_hc_request_id = ps.source_hc_request_id
  WHERE ps.is_roving = true
    AND ps.source_hc_request_id IS NOT NULL
    AND ps.account_id IS NOT NULL
  GROUP BY ps.account_id
),
vacant AS (
  SELECT vv.account_id, count(*) AS open_hc
  FROM public.vacancies vv
  WHERE vv.status = 'Open'
    AND vv.deleted_at IS NULL
    AND COALESCE(vv.is_archived, false) = false
    AND COALESCE(vv.is_pool_vacancy, false) = false
    AND COALESCE(vv.affects_required_hc, true) = true
  GROUP BY vv.account_id
),
base AS (
  SELECT
    a.id AS account_id,
    a.account_name,
    a.account_code,
    a.group_id,
    g.group_name,
    g.group_code,
    round(COALESCE(f.filled_hc, 0) + COALESCE(csk.filled_hc, 0), 4)::numeric(12,4) AS filled_hc,
    COALESCE(f.actual_hc, 0) + COALESCE(csk.actual_hc, 0) AS actual_hc,
    COALESCE(p.pipeline_count, 0) + COALESCE(csk.pipeline_count, 0) AS pipeline_count,
    COALESCE(v.open_hc, 0) AS open_hc,
    round(
      COALESCE(svn.vacant_slots, 0)::numeric
    + COALESCE(svr.vacant_hc, 0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    4)::numeric(12,4) AS slot_vacant_hc,
    round(
      COALESCE(f.filled_hc, 0)
    + COALESCE(csk.filled_hc, 0)
    + COALESCE(p.pipeline_count, 0)
    + COALESCE(csk.pipeline_count, 0)
    + COALESCE(svn.vacant_slots, 0)::numeric
    + COALESCE(svr.vacant_hc, 0)::numeric
    + COALESCE(csk.slot_vacant_hc, 0)::numeric,
    4)::numeric(12,4) AS required_hc
  FROM public.accounts a
  LEFT JOIN public.groups g ON g.id = a.group_id
  LEFT JOIN filled f ON f.account_id = a.id
  LEFT JOIN pipeline p ON p.account_id = a.id
  LEFT JOIN coverage_slot_kpi csk ON csk.account_id = a.id
  LEFT JOIN vacant v ON v.account_id = a.id
  LEFT JOIN slot_vacant_non_roving svn ON svn.account_id = a.id
  LEFT JOIN slot_vacant_roving svr ON svr.account_id = a.id
  WHERE a.is_active = true
    AND COALESCE(a.is_pool_account, false) = false
    AND (public.i_have_full_access()
         OR a.id = ANY (public.get_my_allowed_account_ids()))
)
SELECT
  account_id, account_name, account_code, group_id, group_name, group_code,
  filled_hc, actual_hc, pipeline_count,
  open_hc,
  required_hc,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(filled_hc / required_hc, 4) END AS mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round((filled_hc + pipeline_count) / required_hc, 4) END AS projected_mfr,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(slot_vacant_hc / required_hc, 4) END AS vacancy_rate,
  CASE WHEN required_hc = 0 THEN 0.0
       ELSE round(pipeline_count / required_hc, 4) END AS pipeline_coverage,
  CASE WHEN required_hc = 0 THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 1.0 THEN 'healthy'::text
       WHEN filled_hc / required_hc >= 0.9 THEN 'at_risk'::text
       ELSE 'critical'::text
  END AS health_status,
  slot_vacant_hc
FROM base;

ALTER VIEW public.v_account_allocation_kpi OWNER TO postgres;
COMMENT ON VIEW public.v_account_allocation_kpi IS
  'OHM2026_0097: Allocation KPI includes approved roving HC Request demand from coverage_slots. Coverage Group store footprint and required_headcount are not HC sources.';
GRANT SELECT ON public.v_account_allocation_kpi TO authenticated, service_role;

COMMIT;
