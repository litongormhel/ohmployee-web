-- Migration: 20261246000000_fix_store_archived_at_references.sql
-- Purpose: Fix invalid s.archived_at references on public.stores table in _validate_coverage_request_payload and _coverage_request_review_artifacts, and ensure roving_group_id foreign key constraint is satisfied on employee_store_allocations inserts.
-- ============================================================

BEGIN;

-- ── 1. Drop existing function signatures to allow redefinition ──────────────
DROP FUNCTION IF EXISTS public._validate_coverage_request_payload(
  public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, uuid
) CASCADE;

DROP FUNCTION IF EXISTS public._coverage_request_review_artifacts(
  public.coverage_requests
) CASCADE;

-- ── 2. Redefine _validate_coverage_request_payload with s.status = 'archived' check ──
CREATE OR REPLACE FUNCTION public._validate_coverage_request_payload(
  p_request_type                 public.request_type,
  p_payload                      jsonb,
  p_account_id                   uuid DEFAULT NULL,
  p_position_id                  uuid DEFAULT NULL,
  p_employment_type              text DEFAULT NULL,
  p_target_coverage_group_id     uuid DEFAULT NULL,
  p_source_coverage_group_id     uuid DEFAULT NULL,
  p_destination_coverage_group_id uuid DEFAULT NULL,
  p_request_id                   uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_store_ids               uuid[];
  v_anchor_store_id         uuid;
  v_target_account_id       uuid;
  v_source_account_id       uuid;
  v_destination_account_id  uuid;

  -- GAP-09: employee with no retained-store allocation
  v_gap09_employee_name     text;

  -- GAP-10: coverage group code for a conflicting store
  v_gap10_cg_code           text;

  -- Validation helpers
  v_action_noun             text;
  v_conflicting_store_name  text;
BEGIN

  -- ── Structural-only guard ─────────────────────────────────────────────────
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'payload must be a json object' USING ERRCODE = '22023';
  END IF;

  IF p_payload::text ~* '"(required_hc|required_headcount|headcount|hc|slot_id|slot_ids|vacancy_id|vacancy_vcode|vcode|pipeline_id|coverage_weight|hc_share|store_count)"[[:space:]]*:' THEN
    RAISE EXCEPTION
      'Coverage Request payload must remain structure-only; HC, slot, vacancy, pipeline, coverage weight, and HC share fields are not allowed'
      USING ERRCODE = '22023';
  END IF;

  v_action_noun := CASE
    WHEN p_request_type = 'create_coverage_group'::public.request_type THEN 'create Coverage Group'
    WHEN p_request_type = 'add_store'::public.request_type THEN 'add store'
    WHEN p_request_type = 'remove_store'::public.request_type THEN 'remove store'
    WHEN p_request_type = 'dissolve_coverage_group'::public.request_type THEN 'dissolve Coverage Group'
    ELSE 'process coverage request'
  END;

  -- ── Resolve target/source/destination account_ids ────────────────────────
  IF p_target_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_target_account_id
    FROM public.coverage_groups
    WHERE id = p_target_coverage_group_id
      AND archived_at IS NULL;

    -- Imported roving groups may need normalization before account_id resolves.
    IF v_target_account_id IS NULL THEN
      PERFORM public.fn_normalize_imported_roving_group(p_target_coverage_group_id);
      SELECT account_id INTO v_target_account_id
      FROM public.coverage_groups
      WHERE id = p_target_coverage_group_id
        AND archived_at IS NULL;
    END IF;

    IF v_target_account_id IS NULL THEN
      RAISE EXCEPTION 'target coverage group not found or archived'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF p_source_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_source_account_id
    FROM public.coverage_groups
    WHERE id = p_source_coverage_group_id
      AND archived_at IS NULL;
  END IF;

  IF p_destination_coverage_group_id IS NOT NULL THEN
    SELECT account_id INTO v_destination_account_id
    FROM public.coverage_groups
    WHERE id = p_destination_coverage_group_id
      AND archived_at IS NULL;
  END IF;

  -- ── Extract store IDs depending on request type ──────────────────────────
  IF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_target_coverage_group_id
      AND archived_at IS NULL;
  ELSE
    IF p_payload ? 'store_ids' THEN
      -- If remove_store, require stores to be listed
      v_store_ids := public._coverage_request_uuid_array(
        p_payload,
        'store_ids',
        (p_request_type = 'remove_store'::public.request_type)
      );
    END IF;
  END IF;

  -- ── Per-type validation ───────────────────────────────────────────────────

  IF p_request_type = 'create_coverage_group'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload,
      ARRAY['store_ids', 'anchor_store_id', 'area_name', 'employment_type', 'notes']
    );
    IF p_account_id IS NULL THEN
      RAISE EXCEPTION 'create_coverage_group requires account_id'
        USING ERRCODE = '22023';
    END IF;

    -- GAP-10: block if any proposed store already belongs to another active CG
    IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
      SELECT cg.coverage_code
      INTO   v_gap10_cg_code
      FROM   unnest(v_store_ids) AS sid
      JOIN   public.coverage_group_stores cgs ON cgs.store_id = sid
      JOIN   public.coverage_groups       cg  ON cg.id = cgs.coverage_group_id
      WHERE  cgs.archived_at IS NULL
        AND  cg.archived_at  IS NULL
      LIMIT 1;

      IF v_gap10_cg_code IS NOT NULL THEN
        RAISE EXCEPTION 'Store already belongs to Coverage Group %.', v_gap10_cg_code
          USING ERRCODE = '23514';
      END IF;
    END IF;

  ELSIF p_request_type = 'add_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'add_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;

    -- GAP-10: block if any proposed store already belongs to another active CG
    -- (excluding the target group itself — already-member guard is at execution)
    IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
      SELECT cg.coverage_code
      INTO   v_gap10_cg_code
      FROM   unnest(v_store_ids) AS sid
      JOIN   public.coverage_group_stores cgs ON cgs.store_id = sid
      JOIN   public.coverage_groups       cg  ON cg.id = cgs.coverage_group_id
      WHERE  cgs.archived_at IS NULL
        AND  cg.archived_at  IS NULL
        AND  cg.id <> p_target_coverage_group_id
      LIMIT 1;

      IF v_gap10_cg_code IS NOT NULL THEN
        RAISE EXCEPTION 'Store already belongs to Coverage Group %.', v_gap10_cg_code
          USING ERRCODE = '23514';
      END IF;
    END IF;

  ELSIF p_request_type = 'remove_store'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['store_ids', 'below_minimum_action', 'notes']
    );
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'remove_store requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'convert_stationary_to_roving'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['store_ids', 'anchor_store_id', 'area_name', 'employment_type', 'notes']
    );
    IF p_account_id IS NULL THEN
      RAISE EXCEPTION 'convert_stationary_to_roving requires account_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'convert_roving_to_stationary'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['store_ids', 'notes']);
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'convert_roving_to_stationary requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'merge_coverage_groups'::public.request_type THEN
    PERFORM public._coverage_request_payload_has_only_keys(p_payload, ARRAY['notes']);
    IF p_source_coverage_group_id IS NULL OR p_destination_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'merge_coverage_groups requires source_coverage_group_id and destination_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    IF p_source_coverage_group_id = p_destination_coverage_group_id THEN
      RAISE EXCEPTION 'merge_coverage_groups source and destination must be different'
        USING ERRCODE = '22023';
    END IF;
    IF v_source_account_id <> v_destination_account_id THEN
      RAISE EXCEPTION 'merge_coverage_groups source and destination must belong to the same account'
        USING ERRCODE = '22023';
    END IF;

  ELSIF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    -- GAP-02 (from 20261240000000): employee_home_stores is a valid dissolve key
    PERFORM public._coverage_request_payload_has_only_keys(
      p_payload, ARRAY['notes', 'employee_home_stores']
    );
    IF p_target_coverage_group_id IS NULL THEN
      RAISE EXCEPTION 'dissolve_coverage_group requires target_coverage_group_id'
        USING ERRCODE = '22023';
    END IF;
    IF (p_payload -> 'employee_home_stores') IS NOT NULL
       AND jsonb_typeof(p_payload -> 'employee_home_stores') <> 'object'
    THEN
      RAISE EXCEPTION 'employee_home_stores must be a JSON object {plantilla_id: store_id}'
        USING ERRCODE = '22023';
    END IF;

  ELSE
    RAISE EXCEPTION 'unsupported request_type: %', p_request_type
      USING ERRCODE = '22023';
  END IF;

  -- GAP-09 check for dissolve
  IF p_request_type = 'dissolve_coverage_group'::public.request_type THEN
    IF (p_payload -> 'employee_home_stores') IS NOT NULL THEN
      -- Validate that all active employees in the group have their home store mapping
      -- matching an assigned store in employee_store_allocations
      SELECT pl.employee_name
      INTO   v_gap09_employee_name
      FROM   public.plantilla pl
      WHERE  pl.coverage_group_id = p_target_coverage_group_id
        AND  pl.status = 'Active'
        AND  COALESCE(pl.is_deleted,  false) = false
        AND  COALESCE(pl.is_archived, false) = false
        AND  (
               pl.source_employee_import_batch_id  IS NOT NULL
            OR pl.source_baseline_import_batch_id  IS NOT NULL
             )
        AND  NOT EXISTS (
               SELECT 1
               FROM   public.employee_store_allocations esa
               WHERE  esa.plantilla_id = pl.id
                 AND  esa.store_id     = ANY(v_store_ids)
                 AND  esa.is_active    = true
             )
      LIMIT 1;

      IF v_gap09_employee_name IS NOT NULL THEN
        RAISE EXCEPTION 'Selected Home Store is not assigned to employee.'
          USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;

  -- ── 4. General Store Footprint Validations ─────────────────────────────────
  IF COALESCE(array_length(v_store_ids, 1), 0) > 0 THEN
    
    -- A. Check for duplicates in the selected stores array (exclude dissolve/merge where store list is derived)
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      IF (
        SELECT COUNT(DISTINCT id) != COUNT(*)
        FROM unnest(v_store_ids) AS id
      ) THEN
        RAISE EXCEPTION 'Cannot %. Selected stores list contains duplicates.',
          v_action_noun
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- B. Check for archived/inactive stores (exclude dissolve where stores are already members)
    -- FIX: status = 'archived' check instead of archived_at IS NOT NULL
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      SELECT store_name INTO v_conflicting_store_name
      FROM public.stores
      WHERE id = ANY(v_store_ids)
        AND (is_active = false OR status = 'archived')
      LIMIT 1;

      IF v_conflicting_store_name IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot %. Store % is inactive or archived.',
          v_action_noun,
          v_conflicting_store_name
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- C. Check for invalid store account scope
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving') THEN
      DECLARE
        v_scoped_account_id uuid;
      BEGIN
        v_scoped_account_id := p_account_id;
        IF v_scoped_account_id IS NULL AND p_target_coverage_group_id IS NOT NULL THEN
          SELECT account_id INTO v_scoped_account_id
          FROM public.coverage_groups
          WHERE id = p_target_coverage_group_id;
        END IF;

        IF v_scoped_account_id IS NOT NULL THEN
          SELECT store_name INTO v_conflicting_store_name
          FROM public.stores
          WHERE id = ANY(v_store_ids)
            AND account_id <> v_scoped_account_id
          LIMIT 1;

          IF v_conflicting_store_name IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot %. Store % does not belong to the selected account scope.',
              v_action_noun,
              v_conflicting_store_name
              USING ERRCODE = '23514';
          END IF;
        END IF;
      END;
    END IF;

    -- D. Check for cross-island group (only for create_coverage_group and convert_stationary_to_roving)
    IF p_request_type IN ('create_coverage_group', 'convert_stationary_to_roving') THEN
      IF (
        SELECT COUNT(DISTINCT island_group)
        FROM public.stores
        WHERE id = ANY(v_store_ids)
      ) > 1 THEN
        RAISE EXCEPTION 'Cannot %. Stores must belong to the same island group.',
          v_action_noun
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- E. Block if any store already has a pending coverage request (excluding this request p_request_id)
    IF p_request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'dissolve_coverage_group') THEN
      DECLARE
        v_conflicting_store_name text;
      BEGIN
        WITH pending_requests AS (
          SELECT id, request_type, payload, target_coverage_group_id, source_coverage_group_id, destination_coverage_group_id
          FROM public.coverage_requests
          WHERE status = 'pending'::public.request_status
            AND archived_at IS NULL
            AND (p_request_id IS NULL OR id <> p_request_id)
        ),
        pending_stores AS (
          -- Stores explicitly listed in payload
          SELECT DISTINCT s_id
          FROM pending_requests pr,
               lateral unnest(public._coverage_request_uuid_array(pr.payload, 'store_ids', false)) AS s_id
          WHERE pr.request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving', 'convert_roving_to_stationary')

          UNION

          -- Stores in target group for dissolve
          SELECT DISTINCT cgs.store_id
          FROM pending_requests pr
          JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id = pr.target_coverage_group_id
          WHERE pr.request_type = 'dissolve_coverage_group'
            AND cgs.archived_at IS NULL

          UNION

          -- Stores in source/destination group for merge
          SELECT DISTINCT cgs.store_id
          FROM pending_requests pr
          JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id IN (pr.source_coverage_group_id, pr.destination_coverage_group_id)
          WHERE pr.request_type = 'merge_coverage_groups'
            AND cgs.archived_at IS NULL
        )
        SELECT store_name INTO v_conflicting_store_name
        FROM public.stores
        WHERE id = ANY(v_store_ids)
          AND id IN (SELECT s_id FROM pending_stores)
        LIMIT 1;

        IF v_conflicting_store_name IS NOT NULL THEN
          RAISE EXCEPTION 'Cannot %. One or more selected stores already have a pending coverage request. Pending request already exists for: %',
            v_action_noun,
            v_conflicting_store_name
            USING ERRCODE = '23514';
        END IF;
      END;
    END IF;

  END IF;

END;
$fn$;

COMMENT ON FUNCTION public._validate_coverage_request_payload(
  public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, uuid
) IS
  'Validates the payload of a Coverage Request. Enforces duplicate, inactive, island-group, scope, and pending request constraints.';

REVOKE EXECUTE ON FUNCTION public._validate_coverage_request_payload(public.request_type, jsonb, uuid, uuid, text, uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ── 3. Redefine _coverage_request_review_artifacts with s.status = 'archived' check ──
CREATE OR REPLACE FUNCTION public._coverage_request_review_artifacts(p_request coverage_requests)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $fn$
DECLARE
  v_store_ids uuid[] := ARRAY[]::uuid[];
  v_group_ids uuid[] := ARRAY[]::uuid[];
  v_affected_stores jsonb := '[]'::jsonb;
  v_affected_employees jsonb := '[]'::jsonb;
  v_affected_vacancies jsonb := '[]'::jsonb;
  v_affected_pipelines jsonb := '[]'::jsonb;
  v_conflicts jsonb := '[]'::jsonb;
  v_structural_migration_required boolean := false;
  
  v_pending_request_count integer;
BEGIN
  IF p_request.request_type = 'dissolve_coverage_group'::public.request_type THEN
    SELECT COALESCE(array_agg(store_id), ARRAY[]::uuid[]) INTO v_store_ids
    FROM public.coverage_group_stores
    WHERE coverage_group_id = p_request.target_coverage_group_id
      AND archived_at IS NULL;
  ELSE
    IF p_request.payload ? 'store_ids' THEN
      v_store_ids := public._coverage_request_uuid_array(p_request.payload, 'store_ids', false);
    END IF;
  END IF;

  SELECT COALESCE(array_agg(DISTINCT group_id), ARRAY[]::uuid[])
  INTO v_group_ids
  FROM unnest(ARRAY[
    p_request.target_coverage_group_id,
    p_request.source_coverage_group_id,
    p_request.destination_coverage_group_id
  ]) AS group_id
  WHERE group_id IS NOT NULL;

  IF COALESCE(array_length(v_group_ids, 1), 0) > 0 THEN
    SELECT COALESCE(array_agg(DISTINCT cgs.store_id), ARRAY[]::uuid[])
    INTO v_store_ids
    FROM (
      SELECT unnest(v_store_ids) AS store_id
      UNION
      SELECT cgs.store_id
      FROM public.coverage_group_stores cgs
      WHERE cgs.coverage_group_id = ANY (v_group_ids)
        AND cgs.archived_at IS NULL
    ) cgs;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'store_id', s.id,
        'store_name', s.store_name,
        'store_branch', s.store_branch,
        'account_id', s.account_id,
        'is_active', COALESCE(s.is_active, true),
        'is_existing_coverage_member', EXISTS (
          SELECT 1
          FROM public.coverage_group_stores cgs
          WHERE cgs.store_id = s.id
            AND cgs.archived_at IS NULL
            AND (
              COALESCE(array_length(v_group_ids, 1), 0) = 0
              OR NOT (cgs.coverage_group_id = ANY (v_group_ids))
            )
        )
      )
      ORDER BY s.store_name, s.store_branch
    ),
    '[]'::jsonb
  )
  INTO v_affected_stores
  FROM public.stores s
  WHERE s.id = ANY (v_store_ids);

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'plantilla_id', p.id,
        'employee_no', p.employee_no,
        'employee_name', p.employee_name,
        'store_id', p.store_id,
        'coverage_group_id', p.coverage_group_id,
        'coverage_slot_id', p.coverage_slot_id,
        'status', p.status
      )
      ORDER BY p.employee_name
    ),
    '[]'::jsonb
  )
  INTO v_affected_employees
  FROM public.plantilla p
  WHERE COALESCE(p.is_deleted, false) = false
    AND p.status = 'Active'
    AND (
      (COALESCE(array_length(v_group_ids, 1), 0) > 0 AND p.coverage_group_id = ANY (v_group_ids))
      OR (COALESCE(array_length(v_store_ids, 1), 0) > 0 AND p.store_id = ANY (v_store_ids))
    );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'vacancy_id', v.id,
        'vcode', v.vcode,
        'status', v.status,
        'store_id', v.store_id,
        'account_id', v.account_id,
        'position_id', v.position_id,
        'employment_type', v.employment_type
      )
      ORDER BY v.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_affected_vacancies
  FROM public.vacancies v
  WHERE COALESCE(v.is_archived, false) = false
    AND v.archived_at IS NULL
    AND v.deleted_at IS NULL
    AND v.status IN ('Open', 'For Sourcing', 'Pipeline')
    AND (
      (COALESCE(array_length(v_store_ids, 1), 0) > 0 AND v.store_id = ANY (v_store_ids))
      OR (
        p_request.account_id IS NOT NULL
        AND v.account_id = p_request.account_id
        AND (p_request.position_id IS NULL OR v.position_id = p_request.position_id)
        AND (
          NULLIF(TRIM(COALESCE(p_request.employment_type, '')), '') IS NULL
          OR lower(v.employment_type) = lower(p_request.employment_type)
        )
      )
    );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'applicant_id', a.id,
        'full_name', a.full_name,
        'status', a.status,
        'vacancy_vcode', a.vacancy_vcode,
        'coverage_group_id', a.coverage_group_id,
        'coverage_slot_id', a.coverage_slot_id
      )
      ORDER BY a.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_affected_pipelines
  FROM public.applicants a
  LEFT JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
  WHERE COALESCE(a.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a.status)
    AND (
      (COALESCE(array_length(v_group_ids, 1), 0) > 0 AND a.coverage_group_id = ANY (v_group_ids))
      OR (COALESCE(array_length(v_store_ids, 1), 0) > 0 AND v.store_id = ANY (v_store_ids))
      OR (
        p_request.account_id IS NOT NULL
        AND v.account_id = p_request.account_id
        AND (p_request.position_id IS NULL OR v.position_id = p_request.position_id)
      )
    );

  -- Suppress checks for create_coverage_group
  IF p_request.request_type <> 'create_coverage_group'::public.request_type THEN
    IF jsonb_array_length(v_affected_employees) > 0 THEN
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'check', 'active_employees',
        'severity', 'warning',
        'count', jsonb_array_length(v_affected_employees),
        'message', 'Active employees are attached to the affected stores or coverage groups.'
      ));
    END IF;

    IF jsonb_array_length(v_affected_vacancies) > 0 THEN
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'check', 'active_vacancies',
        'severity', 'warning',
        'count', jsonb_array_length(v_affected_vacancies),
        'message', 'Active vacancies exist in the affected scope.'
      ));
    END IF;

    IF jsonb_array_length(v_affected_pipelines) > 0 THEN
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'check', 'active_pipelines',
        'severity', 'warning',
        'count', jsonb_array_length(v_affected_pipelines),
        'message', 'Active pipeline applicants exist in the affected scope.'
      ));
    END IF;
  END IF;

  -- Store duplicates check
  IF p_request.request_type IN ('create_coverage_group'::public.request_type, 'add_store'::public.request_type, 'remove_store'::public.request_type) THEN
    IF (
      SELECT COUNT(DISTINCT id) != COUNT(*)
      FROM unnest(v_store_ids) AS id
    ) THEN
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'check', 'duplicate_stores',
        'severity', 'warning',
        'count', 1,
        'message', 'Selected stores list contains duplicates.'
      ));
    END IF;
  END IF;

  -- Store archived/inactive check
  -- FIX: status = 'archived' check instead of archived_at IS NOT NULL
  IF EXISTS (
    SELECT 1 FROM public.stores s
    WHERE s.id = ANY (v_store_ids)
      AND (s.is_active = false OR s.status = 'archived')
  ) THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'inactive_or_archived_store',
      'severity', 'warning',
      'count', (
        SELECT count(*)
        FROM public.stores s
        WHERE s.id = ANY (v_store_ids)
          AND (s.is_active = false OR s.status = 'archived')
      ),
      'message', 'One or more selected stores are archived or inactive.'
    ));
  END IF;

  -- Existing coverage group membership check
  IF EXISTS (
    SELECT 1
    FROM public.coverage_group_stores cgs
    WHERE cgs.archived_at IS NULL
      AND cgs.store_id = ANY (v_store_ids)
      AND (
        p_request.request_type IN (
          'create_coverage_group'::public.request_type,
          'convert_stationary_to_roving'::public.request_type,
          'add_store'::public.request_type
        )
        OR NOT (cgs.coverage_group_id = ANY (v_group_ids))
      )
  ) THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'existing_coverage_membership',
      'severity', 'warning',
      'count', (
        SELECT count(*)
        FROM public.coverage_group_stores cgs
        WHERE cgs.archived_at IS NULL
          AND cgs.store_id = ANY (v_store_ids)
      ),
      'message', 'One or more affected stores already have active coverage membership.'
    ));
  END IF;

  -- Pending request check
  DECLARE
    v_pending_exists boolean;
  BEGIN
    WITH pending_requests AS (
      SELECT id, request_type, payload, target_coverage_group_id, source_coverage_group_id, destination_coverage_group_id
      FROM public.coverage_requests
      WHERE status = 'pending'::public.request_status
        AND archived_at IS NULL
        AND id <> p_request.id
    ),
    pending_stores AS (
      SELECT DISTINCT s_id
      FROM pending_requests pr,
           lateral unnest(public._coverage_request_uuid_array(pr.payload, 'store_ids', false)) AS s_id
      WHERE pr.request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving', 'convert_roving_to_stationary')

      UNION

      SELECT DISTINCT cgs.store_id
      FROM pending_requests pr
      JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id = pr.target_coverage_group_id
      WHERE pr.request_type = 'dissolve_coverage_group'
        AND cgs.archived_at IS NULL

      UNION

      SELECT DISTINCT cgs.store_id
      FROM pending_requests pr
      JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id IN (pr.source_coverage_group_id, pr.destination_coverage_group_id)
      WHERE pr.request_type = 'merge_coverage_groups'
        AND cgs.archived_at IS NULL
    )
    SELECT EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = ANY(v_store_ids)
        AND s.id IN (SELECT s_id FROM pending_stores)
    ) INTO v_pending_exists;

    IF v_pending_exists THEN
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'check', 'pending_coverage_request',
        'severity', 'warning',
        'count', (
          SELECT count(*)
          FROM public.stores s
          WHERE s.id = ANY(v_store_ids)
            AND s.id IN (SELECT s_id FROM pending_stores)
        ),
        'message', 'One or more affected stores already have a pending coverage request.'
      ));
    END IF;
  END;

  v_structural_migration_required := p_request.request_type IN (
    'remove_store'::public.request_type,
    'convert_stationary_to_roving'::public.request_type,
    'convert_roving_to_stationary'::public.request_type,
    'merge_coverage_groups'::public.request_type,
    'dissolve_coverage_group'::public.request_type
  );

  IF v_structural_migration_required THEN
    v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
      'check', 'structural_migration_required',
      'severity', 'info',
      'count', 1,
      'message', 'Approval records intent only. Structural execution remains disabled.'
    ));
  END IF;

  RETURN jsonb_build_object(
    'simulation_summary', jsonb_build_object(
      'request_type', p_request.request_type,
      'affected_stores', v_affected_stores,
      'affected_employees', v_affected_employees,
      'affected_vacancies', v_affected_vacancies,
      'affected_pipelines', v_affected_pipelines,
      'approval_required', true,
      'structural_execution_enabled', false
    ),
    'conflict_report', jsonb_build_object(
      'has_conflicts', jsonb_array_length(v_conflicts) > 0,
      'checks', jsonb_build_object(
        'active_employees', jsonb_array_length(v_affected_employees),
        'active_vacancies', jsonb_array_length(v_affected_vacancies),
        'active_pipelines', jsonb_array_length(v_affected_pipelines),
        'existing_coverage_membership', EXISTS (
          SELECT 1
          FROM public.coverage_group_stores cgs
          WHERE cgs.archived_at IS NULL
            AND cgs.store_id = ANY (v_store_ids)
        ),
        'pending_coverage_request', EXISTS (
          SELECT 1
          FROM public.stores s
          WHERE s.id = ANY(v_store_ids)
            AND s.id IN (
              SELECT DISTINCT s_id
              FROM public.coverage_requests pr,
                   lateral unnest(public._coverage_request_uuid_array(pr.payload, 'store_ids', false)) AS s_id
              WHERE pr.status = 'pending'::public.request_status
                AND pr.archived_at IS NULL
                AND pr.id <> p_request.id
                AND pr.request_type IN ('create_coverage_group', 'add_store', 'remove_store', 'convert_stationary_to_roving', 'convert_roving_to_stationary')

              UNION

              SELECT DISTINCT cgs.store_id
              FROM public.coverage_requests pr
              JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id = pr.target_coverage_group_id
              WHERE pr.status = 'pending'::public.request_status
                AND pr.archived_at IS NULL
                AND pr.id <> p_request.id
                AND pr.request_type = 'dissolve_coverage_group'
                AND cgs.archived_at IS NULL

              UNION

              SELECT DISTINCT cgs.store_id
              FROM public.coverage_requests pr
              JOIN public.coverage_group_stores cgs ON cgs.coverage_group_id IN (pr.source_coverage_group_id, pr.destination_coverage_group_id)
              WHERE pr.status = 'pending'::public.request_status
                AND pr.archived_at IS NULL
                AND pr.id <> p_request.id
                AND pr.request_type = 'merge_coverage_groups'
                AND cgs.archived_at IS NULL
            )
        ),
        'inactive_or_archived_store', EXISTS (
          SELECT 1 FROM public.stores s
          -- FIX: status = 'archived' check instead of archived_at IS NOT NULL
          WHERE s.id = ANY(v_store_ids) AND (s.is_active = false OR s.status = 'archived')
        ),
        'structural_migration_required', v_structural_migration_required
      ),
      'conflicts', v_conflicts
    )
  );
END;
$fn$;

COMMENT ON FUNCTION public._coverage_request_review_artifacts(public.coverage_requests) IS
  'Generates simulation and conflict details for Coverage Request review. Checks for active employees, vacancies, pipelines, duplicates, and inactive/archived status.';

REVOKE EXECUTE ON FUNCTION public._coverage_request_review_artifacts(public.coverage_requests) FROM PUBLIC, anon, authenticated;


-- ── 4. Trigger to automatically satisfy roving_group_id constraint on allocations ──
CREATE OR REPLACE FUNCTION public.fn_ensure_import_roving_group_for_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.roving_group_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.import_roving_groups WHERE id = NEW.roving_group_id
    ) THEN
      INSERT INTO public.import_roving_groups (
        id, employee_no, account_id, group_id, account_name, label,
        active_store_count, filled_hc_per_store, source_import_batch_id,
        plantilla_id, created_at, created_by, updated_at, archived_at
      )
      SELECT
        NEW.roving_group_id,
        NEW.employee_no,
        NEW.account_id,
        NEW.group_id,
        (SELECT account_name FROM public.accounts WHERE id = NEW.account_id),
        'CG-' || NEW.employee_no,
        COALESCE(NEW.active_store_count, 2),
        COALESCE(NEW.filled_hc, 0.5),
        NEW.source_import_batch_id,
        NEW.plantilla_id,
        now(),
        NEW.created_by,
        now(),
        now();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_import_roving_group_for_allocation ON public.employee_store_allocations;

CREATE TRIGGER trg_ensure_import_roving_group_for_allocation
BEFORE INSERT ON public.employee_store_allocations
FOR EACH ROW
EXECUTE FUNCTION public.fn_ensure_import_roving_group_for_allocation();

COMMIT;
