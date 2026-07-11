-- ============================================================
-- OHM2026_0102 - Coverage Group global archive invisibility
--
-- Business rule:
--   Archived operational data must be invisible. Coverage Group structures,
--   store edges, and slots must retire with Archive All and must not leak
--   through list/detail/create/assignment read models.
-- ============================================================

BEGIN;

ALTER TABLE public.coverage_groups
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

ALTER TABLE public.coverage_group_stores
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL;

ALTER TABLE public.coverage_slots
  ADD COLUMN IF NOT EXISTS qa_archive_batch_id uuid DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS qa_archive_previous_status text DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS qa_archive_previous_occupant_plantilla_id uuid DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_coverage_groups_qa_archive_batch
  ON public.coverage_groups (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_coverage_group_stores_qa_archive_batch
  ON public.coverage_group_stores (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_coverage_slots_qa_archive_batch
  ON public.coverage_slots (qa_archive_batch_id)
  WHERE qa_archive_batch_id IS NOT NULL;

-- Historical zombie cleanup: MARIZ / inactive parent data
WITH stale_groups AS (
  SELECT cg.id
  FROM public.coverage_groups cg
  LEFT JOIN public.accounts a ON a.id = cg.account_id
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE cg.archived_at IS NULL
    AND (
      COALESCE(a.is_active, false) = false
      OR lower(COALESCE(a.status, '')) = 'archived'
      OR COALESCE(a.account_name, '') ILIKE '%MARIZ%'
      OR COALESCE(g.group_name, '') ILIKE '%MARIZ%'
      OR COALESCE(cg.coverage_code, '') ILIKE '%MARIZ%'
      OR COALESCE(cg.area_name, '') ILIKE '%MARIZ%'
      OR NOT EXISTS (
        SELECT 1
        FROM public.coverage_group_stores cgs
        JOIN public.stores s ON s.id = cgs.store_id
        WHERE cgs.coverage_group_id = cg.id
          AND cgs.archived_at IS NULL
          AND s.is_active = true
          AND lower(COALESCE(s.status, 'active')) <> 'archived'
      )
    )
)
UPDATE public.coverage_groups cg
SET archived_at = COALESCE(cg.archived_at, now()),
    archive_reason = COALESCE(
      NULLIF(cg.archive_reason, ''),
      'OHM2026_0102: archived inactive/MARIZ zombie Coverage Group data'
    ),
    status = CASE
      WHEN EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'coverage_groups'
          AND column_name = 'status'
      ) THEN 'archived'
      ELSE cg.status
    END
FROM stale_groups sg
WHERE cg.id = sg.id;

UPDATE public.coverage_group_stores cgs
SET archived_at = COALESCE(cgs.archived_at, now())
WHERE cgs.archived_at IS NULL
  AND (
    EXISTS (
      SELECT 1
      FROM public.coverage_groups cg
      WHERE cg.id = cgs.coverage_group_id
        AND (cg.archived_at IS NOT NULL OR lower(COALESCE(cg.status, '')) = 'archived')
    )
    OR EXISTS (
      SELECT 1
      FROM public.stores s
      WHERE s.id = cgs.store_id
        AND (COALESCE(s.is_active, false) = false OR lower(COALESCE(s.status, 'active')) = 'archived')
    )
  );

UPDATE public.coverage_slots cs
SET slot_status = 'closed',
    qa_archive_previous_status = COALESCE(cs.qa_archive_previous_status, cs.slot_status),
    qa_archive_previous_occupant_plantilla_id = COALESCE(
      cs.qa_archive_previous_occupant_plantilla_id,
      cs.current_occupant_plantilla_id
    ),
    current_occupant_plantilla_id = NULL,
    updated_at = now()
WHERE cs.slot_status <> 'closed'
  AND EXISTS (
    SELECT 1
    FROM public.coverage_groups cg
    WHERE cg.id = cs.coverage_group_id
      AND (cg.archived_at IS NOT NULL OR lower(COALESCE(cg.status, '')) = 'archived')
  );

UPDATE public.applicants a
SET is_archived = true
WHERE COALESCE(a.is_archived, false) = false
  AND a.coverage_group_id IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.coverage_groups cg
    WHERE cg.id = a.coverage_group_id
      AND (cg.archived_at IS NOT NULL OR lower(COALESCE(cg.status, '')) = 'archived')
  );

-- Eligible accounts: active account + active non-archived store footprint
-- Drop first: Postgres cannot change OUT-parameter row types via CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.get_coverage_group_eligible_accounts();
CREATE OR REPLACE FUNCTION public.get_coverage_group_eligible_accounts()
RETURNS TABLE (
  account_id   uuid,
  account_name text,
  group_id     uuid,
  group_name   text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO 'public'
AS $fn$
  SELECT DISTINCT
    a.id AS account_id,
    a.account_name,
    a.group_id,
    g.group_name
  FROM public.accounts a
  LEFT JOIN public.groups g ON g.id = a.group_id
  WHERE a.is_active = true
    AND lower(COALESCE(a.status, 'active')) <> 'archived'
    AND COALESCE(a.is_pool_account, false) = false
    AND (
      public.i_have_full_access()
      OR a.id = ANY (public.get_my_allowed_account_ids())
    )
    AND EXISTS (
      SELECT 1
      FROM public.stores s
      WHERE s.account_id = a.id
        AND s.is_active = true
        AND lower(COALESCE(s.status, 'active')) <> 'archived'
        AND (
          EXISTS (
            SELECT 1
            FROM public.plantilla_slots ps
            WHERE ps.store_id = s.id
              AND ps.slot_status <> 'closed'
          )
          OR EXISTS (
            SELECT 1
            FROM public.employee_store_allocations esa
            WHERE esa.store_id = s.id
              AND esa.is_active = true
          )
        )
    )
  ORDER BY a.account_name;
$fn$;

COMMENT ON FUNCTION public.get_coverage_group_eligible_accounts() IS
  'OHM2026_0102: Coverage Group create account picker. Returns only active, non-archived accounts with active, non-archived store-level operational footprint.';

GRANT EXECUTE ON FUNCTION public.get_coverage_group_eligible_accounts()
  TO authenticated;

DROP FUNCTION IF EXISTS public.get_coverage_group_eligible_stores(uuid);

CREATE FUNCTION public.get_coverage_group_eligible_stores(
  p_account_id uuid
)
RETURNS TABLE (
  store_id             uuid,
  store_name           text,
  account_id           uuid,
  area_city            text,
  area_province        text,
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

  IF v_role = 'Encoder'
     AND NOT (p_account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: account not in caller scope' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.accounts a
    WHERE a.id = p_account_id
      AND a.is_active = true
      AND lower(COALESCE(a.status, 'active')) <> 'archived'
  ) THEN
    RAISE EXCEPTION 'account not found or archived' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT DISTINCT ON (s.id)
    s.id AS store_id,
    s.store_name,
    s.account_id,
    COALESCE(s.area_city, '') AS area_city,
    COALESCE(s.area_province, '') AS area_province,
    (
      SELECT cg.coverage_code
      FROM public.coverage_group_stores cgs2
      JOIN public.coverage_groups cg
        ON cg.id = cgs2.coverage_group_id
       AND cg.archived_at IS NULL
       AND lower(COALESCE(cg.status, '')) <> 'archived'
      WHERE cgs2.store_id = s.id
        AND cgs2.archived_at IS NULL
      LIMIT 1
    ) AS already_grouped_code
  FROM public.stores s
  WHERE s.account_id = p_account_id
    AND s.is_active = true
    AND lower(COALESCE(s.status, 'active')) <> 'archived'
    AND (
      EXISTS (
        SELECT 1
        FROM public.plantilla_slots ps
        WHERE ps.store_id = s.id
          AND ps.slot_status <> 'closed'
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
  'OHM2026_0102: Coverage Group store picker. Returns only active, non-archived stores under an active, non-archived account; already_grouped_code ignores archived groups and edges.';

GRANT EXECUTE ON FUNCTION public.get_coverage_group_eligible_stores(uuid)
  TO authenticated;

-- Structure-only creation guard with archive-safe account/store checks
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
    SELECT 1
    FROM public.accounts
    WHERE id = p_account_id
      AND is_active = true
      AND lower(COALESCE(status, 'active')) <> 'archived'
  ) THEN
    RAISE EXCEPTION 'account not found or archived' USING ERRCODE = '42501';
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
   AND lower(COALESCE(cg.status, '')) <> 'archived'
  JOIN public.stores s
    ON s.id = t.sid
   AND s.is_active = true
   AND lower(COALESCE(s.status, 'active')) <> 'archived'
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
      SELECT 1
      FROM public.stores s
      WHERE s.id = sid
        AND s.account_id = p_account_id
        AND s.is_active = true
        AND lower(COALESCE(s.status, 'active')) <> 'archived'
        AND (
          EXISTS (
            SELECT 1
            FROM public.plantilla_slots ps
            WHERE ps.store_id = s.id
              AND ps.slot_status <> 'closed'
          )
          OR EXISTS (
            SELECT 1
            FROM public.employee_store_allocations esa
            WHERE esa.store_id = s.id
              AND esa.is_active = true
          )
        )
    )
  ) THEN
    RAISE EXCEPTION 'all stores must belong to the account and have active, non-archived Plantilla operational footprint'
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
    'coverage_code', v_cgcode
  );
END
$fn$;

COMMENT ON FUNCTION public.create_coverage_group(uuid, uuid, text, text, uuid[], uuid) IS
  'OHM2026_0102: Structure-only Coverage Group creation with active/non-archived account and store guards.';

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
  'OHM2026_0102 compatibility wrapper. p_required_hc is ignored; active/non-archived guards live in the 6-arg function.';

GRANT EXECUTE ON FUNCTION public.create_coverage_group(uuid, uuid, text, text, uuid[], uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_coverage_group(uuid, uuid, text, integer, text, uuid[], uuid)
  TO authenticated;

-- Read model: exclude archived parents and archived store/slot data
-- Drop first: Postgres cannot change column list via CREATE OR REPLACE VIEW.
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
  sf.active_store_count,
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
  AND cg.coverage_code LIKE 'CG-%';

COMMENT ON VIEW public.vw_coverage_group_shadow IS
  'OHM2026_0102: Coverage Group shadow view excludes archived groups, archived/inactive accounts, archived/inactive stores, archived store edges, and closed slots.';

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
  JOIN public.stores s
    ON s.id = cgs.store_id
   AND s.is_active = true
   AND lower(COALESCE(s.status, 'active')) <> 'archived'
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
  WHERE cs.coverage_group_id = p_coverage_group_id
    AND cs.slot_status <> 'closed';

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
  'OHM2026_0102: Coverage Group detail excludes archived group/account/store parents, archived store edges, and closed slots.';

GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_coverage_group_detail(uuid) TO service_role;

-- add_applicant guard: archived/inactive parent account is also blocked.
CREATE OR REPLACE FUNCTION public.add_applicant_to_coverage_group(
  p_coverage_group_id  uuid,
  p_last_name          text,
  p_first_name         text,
  p_contact_number     text,
  p_middle_name        text DEFAULT NULL,
  p_status             text DEFAULT 'new',
  p_remarks            text DEFAULT NULL,
  p_source_channel     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor       uuid;
  v_grp         public.coverage_groups%ROWTYPE;
  v_status_opt  public.applicant_status_options%ROWTYPE;
  v_app_id      uuid;
  v_full_name   text;
  v_middle      text;
  v_bind_result jsonb;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR public.i_am_ops()
    OR public.i_am_recruitment()
  ) THEN
    RAISE EXCEPTION 'forbidden: insufficient role to add applicants to a coverage group'
      USING ERRCODE = '42501';
  END IF;

  v_actor := public.get_my_profile_id();

  SELECT cg.* INTO v_grp
  FROM public.coverage_groups cg
  JOIN public.accounts a
    ON a.id = cg.account_id
   AND a.is_active = true
   AND lower(COALESCE(a.status, 'active')) <> 'archived'
  WHERE cg.id = p_coverage_group_id
    AND cg.archived_at IS NULL
    AND lower(COALESCE(cg.status, '')) <> 'archived';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coverage group not found or archived'
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_grp.account_id = ANY (public.get_my_allowed_account_ids())) THEN
    RAISE EXCEPTION 'forbidden: coverage group account outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_status_opt
  FROM public.applicant_status_options
  WHERE status_code = p_status
    AND is_active = true
    AND allow_on_create = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid or non-createable status_code: %', p_status
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.coverage_slots
    WHERE coverage_group_id = p_coverage_group_id
      AND slot_status = 'open'
    LIMIT 1
  ) THEN
    RAISE EXCEPTION
      'no_open_coverage_slot: % has no open slots. All required headcount is currently in pipeline or filled. Contact your Admin to create an approved roving HC Request before adding another applicant.',
      v_grp.coverage_code
      USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.applicants a
    WHERE LOWER(TRIM(a.contact_number)) = LOWER(TRIM(p_contact_number))
      AND LOWER(TRIM(a.last_name)) = LOWER(TRIM(p_last_name))
      AND LOWER(TRIM(a.first_name)) = LOWER(TRIM(p_first_name))
      AND (
        p_middle_name IS NULL
        OR TRIM(COALESCE(p_middle_name, '')) = ''
        OR LOWER(TRIM(a.middle_name)) = LOWER(TRIM(p_middle_name))
      )
      AND public.fn_is_active_vacancy_applicant_status(a.status)
      AND COALESCE(a.is_archived, false) = false
      AND (
        (a.coverage_group_id IS NOT NULL AND a.coverage_group_id <> p_coverage_group_id)
        OR (a.coverage_slot_id IS NULL AND a.vacancy_vcode IS NOT NULL)
      )
  ) THEN
    RAISE EXCEPTION
      'duplicate_applicant_identity: An active applicant with the same name and contact number already exists in another vacancy or coverage group. Back out or archive the existing applicant record before adding a new one.'
      USING ERRCODE = 'P0001';
  END IF;

  v_middle := NULLIF(TRIM(COALESCE(p_middle_name, '')), '');
  v_full_name := TRIM(p_last_name) || ', ' || TRIM(p_first_name)
    || CASE WHEN v_middle IS NOT NULL THEN ' ' || v_middle ELSE '' END;

  INSERT INTO public.applicants (
    last_name,
    first_name,
    middle_name,
    full_name,
    contact_number,
    status,
    remarks,
    is_archived
  ) VALUES (
    TRIM(p_last_name),
    TRIM(p_first_name),
    v_middle,
    v_full_name,
    TRIM(p_contact_number),
    v_status_opt.label,
    NULLIF(TRIM(COALESCE(p_remarks, '')), ''),
    false
  )
  RETURNING id INTO v_app_id;

  SELECT public.fn_bind_applicant_to_coverage_group(
    p_applicant_id => v_app_id,
    p_coverage_group_id => p_coverage_group_id,
    p_performed_by => v_actor
  ) INTO v_bind_result;

  IF (v_bind_result->>'status') <> 'ok' THEN
    RAISE EXCEPTION
      'coverage_slot_bind_failed: slot transition blocked - %. The open slot may have been claimed concurrently. Please try again.',
      COALESCE(v_bind_result->>'blocked_reason', 'unknown')
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.log_audit_event(
    'vacancy_module',
    'INSERT',
    v_app_id,
    NULL,
    jsonb_build_object(
      'action', 'add_applicant_to_coverage_group',
      'coverage_group_id', p_coverage_group_id,
      'coverage_code', v_grp.coverage_code,
      'coverage_slot_id', v_bind_result->>'coverage_slot_id',
      'slot_ordinal', v_bind_result->>'slot_ordinal'
    )
  );

  RETURN jsonb_build_object(
    'applicant_id', v_app_id,
    'coverage_group_id', p_coverage_group_id,
    'coverage_slot_id', (v_bind_result->>'coverage_slot_id')::uuid,
    'slot_ordinal', (v_bind_result->>'slot_ordinal')::integer
  );
END;
$$;

COMMENT ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text) IS
  'OHM2026_0102: Adds applicant only to active, unarchived Coverage Groups under active, non-archived accounts.';

GRANT EXECUTE ON FUNCTION public.add_applicant_to_coverage_group(uuid, text, text, text, text, text, text, text)
  TO authenticated;

-- Archive All cascade: retire Coverage Group structures with QA reset
CREATE OR REPLACE FUNCTION public.fn_qa_archive_operational_data_reset(
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id                 uuid;
  v_caller_name               text;
  v_batch_id                  uuid;
  v_now                       timestamptz;

  v_plantilla_count           integer := 0;
  v_vacancy_count             integer := 0;
  v_hr_emploc_count           integer := 0;
  v_slots_count               integer := 0;
  v_hc_request_count          integer := 0;
  v_esa_count                 integer := 0;
  v_coverage_group_count      integer := 0;
  v_coverage_store_count      integer := 0;
  v_coverage_slot_count       integer := 0;
  v_coverage_applicant_count  integer := 0;
  v_hr_coverage_link_count    integer := 0;
  v_plantilla_coverage_link_count integer := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access Denied: Super Admin only'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'archive_reason is required and must not be empty'
      USING ERRCODE = '22000';
  END IF;

  v_caller_id := public.get_current_profile_id();
  v_caller_name := public.get_my_full_name();
  v_batch_id := gen_random_uuid();
  v_now := now();

  UPDATE public.plantilla
  SET is_archived = true,
      archived_at = v_now,
      archived_by = v_caller_id,
      archive_reason = p_reason,
      qa_archive_batch_id = v_batch_id,
      updated_at = v_now,
      updated_by = v_caller_id
  WHERE is_deleted = false
    AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_plantilla_count = ROW_COUNT;

  UPDATE public.vacancies
  SET is_archived = true,
      archived_at = v_now,
      archived_by_id = v_caller_id,
      archived_by = v_caller_name,
      archive_reason = p_reason,
      status = 'Archived',
      qa_archive_batch_id = v_batch_id,
      updated_at = v_now,
      updated_by = v_caller_id
  WHERE deleted_at IS NULL
    AND (is_archived = false OR is_archived IS NULL);
  GET DIAGNOSTICS v_vacancy_count = ROW_COUNT;

  UPDATE public.hr_emploc
  SET deleted_at = v_now,
      qa_archived_at = v_now,
      qa_archived_by = v_caller_id,
      qa_archive_reason = p_reason,
      qa_archive_batch_id = v_batch_id,
      updated_at = v_now,
      updated_by = v_caller_id
  WHERE deleted_at IS NULL;
  GET DIAGNOSTICS v_hr_emploc_count = ROW_COUNT;

  UPDATE public.plantilla_slots
  SET slot_status = 'closed',
      closed_at = v_now,
      closed_by = v_caller_id,
      closure_reason_code = 'QA_RESET',
      qa_archive_batch_id = v_batch_id,
      updated_at = v_now,
      updated_by = v_caller_id
  WHERE slot_status <> 'closed';
  GET DIAGNOSTICS v_slots_count = ROW_COUNT;

  UPDATE public.headcount_requests
  SET is_archived = true,
      archived_at = v_now,
      qa_archive_batch_id = v_batch_id,
      updated_at = v_now
  WHERE is_archived = false;
  GET DIAGNOSTICS v_hc_request_count = ROW_COUNT;

  UPDATE public.employee_store_allocations
  SET is_active = false,
      effective_end = v_now::date,
      qa_archive_batch_id = v_batch_id
  WHERE is_active = true;
  GET DIAGNOSTICS v_esa_count = ROW_COUNT;

  UPDATE public.coverage_groups
  SET archived_at = v_now,
      archived_by = v_caller_id,
      archive_reason = p_reason,
      qa_archive_batch_id = v_batch_id,
      status = 'archived'
  WHERE archived_at IS NULL
    OR lower(COALESCE(status, '')) <> 'archived';
  GET DIAGNOSTICS v_coverage_group_count = ROW_COUNT;

  UPDATE public.coverage_group_stores
  SET archived_at = v_now,
      archived_by = v_caller_id,
      qa_archive_batch_id = v_batch_id
  WHERE archived_at IS NULL;
  GET DIAGNOSTICS v_coverage_store_count = ROW_COUNT;

  UPDATE public.coverage_slots
  SET slot_status = 'closed',
      qa_archive_previous_status = COALESCE(qa_archive_previous_status, slot_status),
      qa_archive_previous_occupant_plantilla_id = COALESCE(
        qa_archive_previous_occupant_plantilla_id,
        current_occupant_plantilla_id
      ),
      current_occupant_plantilla_id = NULL,
      qa_archive_batch_id = v_batch_id,
      updated_at = v_now
  WHERE slot_status <> 'closed';
  GET DIAGNOSTICS v_coverage_slot_count = ROW_COUNT;

  UPDATE public.applicants
  SET is_archived = true,
      qa_archive_batch_id = COALESCE(qa_archive_batch_id, v_batch_id)
  WHERE COALESCE(is_archived, false) = false
    AND coverage_group_id IS NOT NULL;
  GET DIAGNOSTICS v_coverage_applicant_count = ROW_COUNT;

  UPDATE public.hr_emploc_store_links
  SET deleted_at = v_now,
      updated_at = v_now,
      updated_by = v_caller_id
  WHERE deleted_at IS NULL
    AND coverage_group_id IS NOT NULL;
  GET DIAGNOSTICS v_hr_coverage_link_count = ROW_COUNT;

  UPDATE public.plantilla_store_links
  SET deleted_at = v_now,
      updated_at = v_now,
      updated_by = v_caller_id
  WHERE deleted_at IS NULL
    AND coverage_group_id IS NOT NULL;
  GET DIAGNOSTICS v_plantilla_coverage_link_count = ROW_COUNT;

  INSERT INTO public.archival_audit_logs
    (module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot)
  VALUES
    (
      'qa_reset_summary',
      v_batch_id,
      'qa_archive',
      v_caller_id,
      p_reason,
      v_batch_id,
      jsonb_build_object(
        'archive_batch_id', v_batch_id,
        'executed_by', v_caller_id,
        'executed_at', v_now,
        'reason', p_reason,
        'plantilla_count', v_plantilla_count,
        'vacancy_count', v_vacancy_count,
        'hr_emploc_count', v_hr_emploc_count,
        'slots_count', v_slots_count,
        'headcount_request_count', v_hc_request_count,
        'esa_count', v_esa_count,
        'coverage_group_count', v_coverage_group_count,
        'coverage_group_store_count', v_coverage_store_count,
        'coverage_slot_count', v_coverage_slot_count,
        'coverage_applicant_count', v_coverage_applicant_count,
        'hr_coverage_link_count', v_hr_coverage_link_count,
        'plantilla_coverage_link_count', v_plantilla_coverage_link_count
      )
    );

  RETURN jsonb_build_object(
    'archive_batch_id', v_batch_id,
    'plantilla_archived_count', v_plantilla_count,
    'vacancy_archived_count', v_vacancy_count,
    'slots_archived_count', v_slots_count,
    'hr_emploc_archived_count', v_hr_emploc_count,
    'hc_requests_archived_count', v_hc_request_count,
    'esa_deactivated_count', v_esa_count,
    'coverage_groups_archived_count', v_coverage_group_count,
    'coverage_group_stores_archived_count', v_coverage_store_count,
    'coverage_slots_closed_count', v_coverage_slot_count,
    'coverage_applicants_archived_count', v_coverage_applicant_count,
    'hr_coverage_links_deactivated_count', v_hr_coverage_link_count,
    'plantilla_coverage_links_deactivated_count', v_plantilla_coverage_link_count,
    'executed_by', v_caller_id,
    'executed_at', v_now
  );
END;
$$;

COMMENT ON FUNCTION public.fn_qa_archive_operational_data_reset(text) IS
  'OHM2026_0102: QA-only Super Admin batch archive. Soft-archives Plantilla, Vacancy, HR Emploc, Plantilla Slots, Headcount Requests, ESA, Coverage Groups, Coverage Group Stores, Coverage Slots, and Coverage applicants. No hard deletes.';

REVOKE ALL ON FUNCTION public.fn_qa_archive_operational_data_reset(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_qa_archive_operational_data_reset(text) TO authenticated;

-- Validation SQL:
-- A. No active Coverage Group under archived/inactive account
-- SELECT COUNT(*) FROM public.coverage_groups cg JOIN public.accounts a ON a.id = cg.account_id
-- WHERE cg.archived_at IS NULL AND lower(COALESCE(cg.status, '')) <> 'archived'
--   AND (COALESCE(a.is_active, false) = false OR lower(COALESCE(a.status, 'active')) = 'archived');
--
-- B. No active Coverage Group Store linked to archived/inactive store
-- SELECT COUNT(*) FROM public.coverage_group_stores cgs JOIN public.stores s ON s.id = cgs.store_id
-- WHERE cgs.archived_at IS NULL
--   AND (COALESCE(s.is_active, false) = false OR lower(COALESCE(s.status, 'active')) = 'archived');
--
-- C. No active Coverage Slot under archived Coverage Group
-- SELECT COUNT(*) FROM public.coverage_slots cs JOIN public.coverage_groups cg ON cg.id = cs.coverage_group_id
-- WHERE cs.slot_status <> 'closed'
--   AND (cg.archived_at IS NOT NULL OR lower(COALESCE(cg.status, '')) = 'archived');
--
-- D. MARIZ Coverage Groups no longer visible
-- SELECT COUNT(*) FROM public.vw_coverage_group_shadow
-- WHERE account_name ILIKE '%MARIZ%' OR group_name ILIKE '%MARIZ%' OR coverage_code ILIKE '%MARIZ%';
--
-- E. ONE account remains visible in Group 2
-- SELECT COUNT(*) FROM public.get_coverage_group_eligible_accounts()
-- WHERE group_name ILIKE '%Group 2%';
--
-- F. Coverage Group Create store footprint returns only active, non-archived stores
-- SELECT COUNT(*) FROM public.get_coverage_group_eligible_stores('<account-id>'::uuid) es
-- JOIN public.stores s ON s.id = es.store_id
-- WHERE COALESCE(s.is_active, false) = false OR lower(COALESCE(s.status, 'active')) = 'archived';

COMMIT;
